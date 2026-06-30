import SwiftUI

// MARK: - Home tab (daily + random + emergency)
struct HomeView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: ContentStore
    @State private var active: ClinicalCase?
    @State private var activeKind: CaseKind = .random
    @State private var activeDayKey: Int?
    @State private var randomCase: ClinicalCase?
    @State private var showNoLife = false
    /// After finishing a random case we chain straight into the next one; this
    /// remembers the case we just played so we don't immediately re-serve it.
    @State private var chainRandom = false
    @State private var lastRandomID: UUID?
    /// Drives live re-evaluation of the emergency window (opens/closes on time).
    @State private var now = Date()
    @State private var lastEmergencyPoll = Date.distantPast
    private let ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    enum CaseKind { case daily, random, emergency }

    /// The case scheduled as today's Daily Case (matched by calendar day), if any.
    private func dailyCase(forDay day: Int) -> ClinicalCase? {
        store.dailyCase(forDay: day)
    }
    /// The most recent emergency still inside its 3-hour window at `now`, if any.
    private var activeEmergency: EmergencyCase? {
        store.emergencies
            .filter { now >= $0.fireDate && now < $0.expiry }
            .sorted { $0.fireDate > $1.fireDate }.first
    }

    var body: some View {
        let today = app.todayKey
        return AppBackground {
            VStack(spacing: 0) {
                TopBar()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Text("Welcome, Doctor").font(CX.title(26)).foregroundStyle(CX.navy)
                            Spacer()
                            VixClip(anim: .wave, size: 56, fallback: .idle)
                        }

                        if let ec = activeEmergency { emergencyCard(ec) }

                        if let c = dailyCase(forDay: today) {
                            dailyCard(c, day: today)
                        } else {
                            EmptyStateCard(title: "No daily case today",
                                           body: "No case is scheduled for today. Daily cases are pinned to a calendar day (GMT).")
                        }

                        randomCard()
                    }
                    .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 24)
                }
            }
        }
        .fullScreenCover(item: $active, onDismiss: { advanceAfterDismiss() }) { c in
            CaseFlow(clinicalCase: c, consumesLife: activeKind == .random, onFinish: { _ in
                if activeKind == .daily, let day = activeDayKey { app.markDailySolved(day: day) }
                // Finishing a random case automatically opens the next one.
                if activeKind == .random { lastRandomID = active?.id; chainRandom = true }
            })
        }
        .alert("Not enough Energy", isPresented: $showNoLife) { Button("OK") {} } message: {
            Text("Each case costs \(AppState.randomCaseEnergyCost) energy, which refills over time (full in about a day). Go Pro and they cost only \(AppState.proCaseEnergyCost). Daily and Emergency cases are always free.")
        }
        .onReceive(ticker) { t in
            now = t
            // Poll for newly-broadcast emergencies (~every 45s) so a live one's
            // card appears while Home is open. The alert is delivered by the
            // server push, so no local notification is fired here.
            if t.timeIntervalSince(lastEmergencyPoll) > 45 {
                lastEmergencyPoll = t
                Task { store.setServerEmergencies(await SupabaseService.shared.fetchActiveEmergencies()) }
            }
        }
        .onAppear { now = Date(); app.refreshForNewDay(); ensureRandom() }
    }

    // MARK: Cards

    /// Active emergency — red, with a live countdown and a blinking siren border.
    private func emergencyCard(_ ec: EmergencyCase) -> some View {
        let c = ec.clinicalCase
        return Button {
            activeKind = .emergency; active = c
        } label: {
            CXCard {
                VStack(alignment: .leading, spacing: 10) {
                    Image(c.heroImageName)
                        .resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    HStack {
                        Label("EMERGENCY", systemImage: "cross.case.fill")
                            .font(CX.label(13)).foregroundStyle(.red)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "timer").foregroundStyle(.red)
                            // Guard the range so lowerBound is always < upperBound.
                            Text(timerInterval: min(now, ec.expiry.addingTimeInterval(-1))...ec.expiry, countsDown: true)
                                .font(CX.label(13)).foregroundStyle(.red).monospacedDigit()
                        }
                    }
                    Text(c.specialty).font(CX.heading(20)).foregroundStyle(CX.navy)
                    Text("\(c.patientName), \(c.age) · \(c.chiefComplaint)")
                        .font(CX.body(14)).foregroundStyle(CX.navySoft).fixedSize(horizontal: false, vertical: true)
                    Text("Tap to respond — vanishes when the timer ends. Free to play.")
                        .font(CX.label(12)).foregroundStyle(.red)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .modifier(SirenBorder())
        }.buttonStyle(PressStyle())
    }

    /// Today's daily case — free to play, solvable once. (Provision: set the
    /// case's `imageName`/`title`/`teaser` to make it a full illustrated card.)
    private func dailyCard(_ c: ClinicalCase, day: Int) -> some View {
        CaseHeroCard(clinicalCase: c, skill: app.skill,
                     costsEnergy: false, solved: app.solvedDaily(day: day),
                     kicker: "DAILY CASE", solveTitle: "Solve daily case") {
            activeKind = .daily; activeDayKey = day; active = c
        }
    }

    /// Ensures `randomCase` holds a valid unsolved case to preview & play. Keeps
    /// the same case stable until it's solved (so the teaser matches the button).
    /// When `excluding` is set we always re-pick, avoiding that case if any other
    /// unsolved case is available (used when chaining to the next random case).
    private func ensureRandom(excluding excludeID: UUID? = nil) {
        var unsolved = store.clinicalCases.filter { !app.isCaseSolved($0.id) }
        if let ex = excludeID {
            let others = unsolved.filter { $0.id != ex }
            if !others.isEmpty { unsolved = others }
        } else if let c = randomCase, unsolved.contains(where: { $0.id == c.id }) {
            return
        }
        randomCase = unsolved.randomElement()
    }

    /// Runs after a case cover closes. If the player just finished a random case,
    /// pick the next unsolved one and — energy permitting — open it immediately
    /// so cases flow one into the next without a trip back to Home.
    private func advanceAfterDismiss() {
        let chaining = chainRandom
        let justPlayed = lastRandomID
        chainRandom = false
        lastRandomID = nil
        ensureRandom(excluding: chaining ? justPlayed : nil)
        guard chaining, let next = randomCase, app.canAfford(life: app.randomCaseCost) else { return }
        activeKind = .random
        // Re-present once the dismissal animation has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { active = next }
    }

    /// A surprise case from the practice collection — costs Energy. Only ever
    /// picks cases the user hasn't already solved; solved cases never reappear.
    @ViewBuilder private func randomCard() -> some View {
        let total = store.clinicalCases.count
        Group {
            if let c = randomCase {
                CaseHeroCard(clinicalCase: c, skill: app.skill,
                             costsEnergy: true, kicker: "RANDOM CASE", solveTitle: "Solve the case") {
                    guard app.canAfford(life: app.randomCaseCost) else { showNoLife = true; return }
                    activeKind = .random; active = c
                }
            } else {
                CXCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("RANDOM CASE", systemImage: "shuffle").font(CX.label(13)).foregroundStyle(CX.orange)
                        Text(total == 0 ? "Add practice cases to enable this."
                                        : "You've solved every practice case! 🎉 New ones will appear here.")
                            .font(CX.body(15)).foregroundStyle(CX.navySoft).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear { ensureRandom() }
    }

    private func rewardChip(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(CX.label(13)).foregroundStyle(CX.navy)
        }
    }
}

// MARK: - Ambulance-siren blinking red border
struct SirenBorder: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.red, lineWidth: on ? 4 : 1.5)
                    .shadow(color: .red.opacity(on ? 0.9 : 0.15), radius: on ? 14 : 2)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

// MARK: - Practice Cases tab (Clinical + Emergency)
struct PracticeView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: ContentStore
    @State private var active: ClinicalCase?
    @State private var showNoLife = false

    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                TopBar()
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        SectionTitle(text: "Clinical Cases")
                        Text("Your permanent collection — browse and solve anytime.")
                            .font(CX.body(14)).foregroundStyle(CX.navySoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if store.clinicalCases.isEmpty {
                            EmptyStateCard(title: "No clinical cases yet",
                                           body: "The permanent case collection appears here to browse and solve anytime.")
                        } else {
                            ForEach(store.clinicalCases) { c in
                                DepartmentCard(dept: caseDept(c, "🩺"), solved: app.isCaseSolved(c.id),
                                               trophy: app.caseTrophyTier(c.id),
                                               masterySolved: app.solvedCount(in: c.specialty)) { launch(c) }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 24)
                }
            }
        }
        .fullScreenCover(item: $active) { c in CaseFlow(clinicalCase: c) }
        .alert("Not enough Energy", isPresented: $showNoLife) { Button("OK") {} } message: {
            Text("Each case costs \(AppState.randomCaseEnergyCost) energy, which refills over time (full in about a day). Go Pro and they cost only \(AppState.proCaseEnergyCost).")
        }
        .onAppear { app.refreshForNewDay() }
    }

    private func launch(_ c: ClinicalCase) {
        guard app.canAfford(life: app.randomCaseCost) else { showNoLife = true; return }
        active = c
    }
}

/// Wraps a clinical case as a card model.
func caseDept(_ c: ClinicalCase, _ emoji: String) -> Department {
    Department(name: c.specialty, emoji: emoji,
               teaser: "\(c.patientName), \(c.age), \(c.chiefComplaint)", caseRef: c)
}

// MARK: - Shared empty state
struct EmptyStateCard: View {
    let title: String
    let body_: String
    init(title: String, body: String) { self.title = title; self.body_ = body }
    var body: some View {
        CXCard {
            VStack(spacing: 8) {
                VixClip(anim: .wave, size: 96, fallback: .idle)
                Text(title).font(CX.heading(18)).foregroundStyle(CX.navy)
                Text(body_).font(CX.body(14)).foregroundStyle(CX.navySoft)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity).padding(.vertical, 10)
        }
    }
}

// MARK: - Case card (mystery patient)
struct DepartmentCard: View {
    let dept: Department
    var solved: Bool = false
    /// Trophy tier earned for this case (1 bronze, 2 silver, 3 gold), nil if unsolved.
    var trophy: Int? = nil
    /// Cases solved in this specialty — drives the mastery progress chips.
    var masterySolved: Int = 0
    var onPlay: () -> Void

    private static let bronzeColor = Color(hex: 0xCD8B5A)

    var body: some View {
        CXCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(dept.emoji).font(.system(size: 22))
                        Text(dept.name).font(CX.heading(21)).foregroundStyle(CX.navy)
                        if solved {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 16)).foregroundStyle(CX.teal)
                        }
                    }
                    Text(dept.teaser).font(CX.body(15)).foregroundStyle(CX.navySoft)
                        .fixedSize(horizontal: false, vertical: true)
                    masteryChips
                }
                Spacer(minLength: 4)
                Button(action: onPlay) {
                    Image(systemName: "play.fill").font(.system(size: 24))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(CX.orangeButton, in: Circle())
                        .shadow(color: CX.orange.opacity(0.4), radius: 8, y: 4)
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    /// Three segmented mastery-trophy progress chips for this specialty.
    private var masteryChips: some View {
        let n = masterySolved
        return HStack(spacing: 8) {
            masteryChip(progress: min(n, AppState.bronzeSegment), of: AppState.bronzeSegment, color: Self.bronzeColor)
            masteryChip(progress: max(0, min(n - AppState.bronzeMastery, AppState.silverSegment)), of: AppState.silverSegment, color: CX.teal)
            masteryChip(progress: max(0, min(n - AppState.silverMastery, AppState.goldSegment)), of: AppState.goldSegment, color: CX.gold)
        }
    }

    private func masteryChip(progress: Int, of total: Int, color: Color) -> some View {
        let earned = progress >= total
        return HStack(spacing: 5) {
            Text("\(progress)/\(total)").font(CX.label(12)).foregroundStyle(CX.navy)
            Image(systemName: "trophy.fill").font(.system(size: 13)).foregroundStyle(color)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(earned ? color.opacity(0.22) : CX.navySoft.opacity(0.08), in: Capsule())
    }
}

// MARK: - Leagues tab (XP ranking among individuals)

// MARK: - Leagues tab (weekly XP leaderboard)

struct LeaguesView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: ContentStore
    @State private var active: ClinicalCase?
    @State private var randomCase: ClinicalCase?
    @State private var showLearnMore = false
    @State private var showNoLife = false

    private var tierColor: Color { app.league.color }

    /// The real players in the user's weekly league room (≤30), loaded from the
    /// server and ranked by XP earned this week.
    @State private var board: [LeagueEntry] = []
    @State private var loadingLeague = false
    @State private var promotion: LeagueReward?
    private var myEntry: LeagueEntry? { board.first { $0.isYou } }

    /// Promote based on last week's finish (if the week rolled over), then join /
    /// refresh this week's league room and pull its real members.
    private func refreshLeague() async {
        await processLeagueRollover()
        let week = AppState.gmtWeek()
        if app.qualifiedForLeague {
            await SupabaseService.shared.reportLeague(
                week: week, kind: app.league.name, weeklyXP: app.weeklyXP,
                totalXP: app.lifetimeXP, trophies: app.gold, username: app.displayName)
        }
        let members = await SupabaseService.shared.fetchLeague(week: week)
        var entries = Seed.leagueEntries(from: members, youId: SupabaseService.shared.userId)
        // Always surface the leaderboard for a qualified player, even with just a
        // handful of people in the room (or before the server room has propagated):
        // if our own row isn't in the fetched members yet, add it so the board is
        // never blank just because fewer than a full room of 30 have joined.
        if app.qualifiedForLeague, !entries.contains(where: { $0.isYou }) {
            entries.append(makeSelfEntry(rank: entries.count + 1))
        }
        board = entries
        loadingLeague = false
    }

    /// A leaderboard row for the current player, built from local state — used as
    /// a fallback so the league always shows the user when the server room is
    /// empty or hasn't included them yet.
    private func makeSelfEntry(rank: Int) -> LeagueEntry {
        var e = LeagueEntry(name: app.displayName, weeklyXP: app.weeklyXP,
                            totalXP: app.lifetimeXP, trophies: app.gold, isYou: true)
        e.rank = rank
        e.avatarTint = CX.orange
        return e
    }

    /// On the first visit of a new league week, look up last week's final rank;
    /// if the player finished in the promotion zone, promote them a tier and
    /// award rank-/tier-scaled coins + XP.
    private func processLeagueRollover() async {
        let week = AppState.gmtWeek()
        guard week > app.lastLeagueResultWeek else { return }
        let prevWeek = week - 1
        let members = await SupabaseService.shared.fetchLeague(week: prevWeek)
        if let me = members.first(where: { $0.player_id == SupabaseService.shared.userId }) {
            if let reward = app.applyLeagueResult(rank: me.rank) {
                promotion = reward                              // promoted → celebrate
            } else if let setback = app.applyLeagueDemotion(rank: me.rank) {
                app.pendingSetback = setback                    // demoted → commiserate
            }
        }
        app.markLeagueResultProcessed(week: week)
    }

    var body: some View {
        ZStack {
            CX.appBackground.ignoresSafeArea()
            tierColor.opacity(0.14).ignoresSafeArea()      // league-tier colour wash
            VStack(spacing: 0) {
                TopBar()
                if app.qualifiedForLeague { qualifiedBody } else { notQualifiedBody }
            }
        }
        .fullScreenCover(item: $active, onDismiss: { ensureRandom() }) { c in
            CaseFlow(clinicalCase: c, consumesLife: true)
        }
        .alert("Not enough Energy", isPresented: $showNoLife) { Button("OK") {} } message: {
            Text("Each case costs \(AppState.randomCaseEnergyCost) energy, which refills over time (full in about a day). Go Pro and they cost only \(AppState.proCaseEnergyCost).")
        }
        .sheet(isPresented: $showLearnMore) { LeagueInfoSheet() }
        .alert("Promoted! 🎉", isPresented: Binding(get: { promotion != nil }, set: { if !$0 { promotion = nil } })) {
            Button("Awesome") { promotion = nil }
        } message: {
            if let r = promotion {
                Text("You finished #\(r.rank) and moved up to the \(r.league.name) League.\n\n+\(r.coins) coins · +\(r.xp) XP")
            }
        }
        .onAppear { app.refreshForNewDay(); ensureRandom(); loadingLeague = board.isEmpty }
        .task {
            await SupabaseService.shared.submitScore(
                playerId: app.leaderboardId, username: app.displayName, xp: app.lifetimeXP)
            await refreshLeague()
        }
    }

    // MARK: Not-qualified (themed tier intro)

    private var notQualifiedBody: some View {
        let need = max(0, AppState.casesToQualify - app.leagueCasesThisWeek)
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                tierBadge.padding(.top, 8)
                Text("\(app.league.name) League").font(CX.title(34)).foregroundStyle(CX.navy)
                Text(app.league.subtitle).font(CX.heading(17)).foregroundStyle(CX.navySoft)
                    .multilineTextAlignment(.center)

                Image(systemName: "lock.fill").font(.system(size: 30)).foregroundStyle(CX.navySoft).padding(.top, 8)

                Text("Find your own rank in this week's league")
                    .font(CX.title(24)).foregroundStyle(CX.navy).multilineTextAlignment(.center)
                Text("You need to complete at least \(need) case\(need == 1 ? "" : "s").")
                    .font(CX.body(16)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)

                Button { solveCase() } label: {
                    HStack(spacing: 10) {
                        Text("Solve a Case").font(CX.heading(18)).foregroundStyle(.white)
                        Image(systemName: "arrow.right").foregroundStyle(.white)
                    }.frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(PushButtonStyle(face: CX.orange, lip: CX.orangeDark))
                .padding(.top, 4)

                inviteCard
                learnMoreButton
            }
            .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 24)
        }
    }

    private var tierBadge: some View {
        ZStack {
            Circle().fill(tierColor.opacity(0.22)).frame(width: 150, height: 150)
            Circle().fill(tierColor.opacity(0.32)).frame(width: 112, height: 112)
            Image(systemName: app.league.icon).font(.system(size: 56)).foregroundStyle(tierColor)
        }
    }

    // MARK: Qualified (leaderboard)

    private var qualifiedBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                // League header
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: app.league.icon).foregroundStyle(tierColor)
                        Text("\(app.league.name) League").font(CX.title(22)).foregroundStyle(CX.navy)
                    }
                    Text("Top \(Seed.leaguePromotionCount) advance · resets in \(app.leagueDaysLeft) day\(app.leagueDaysLeft == 1 ? "" : "s")")
                        .font(CX.label(13)).foregroundStyle(CX.navySoft)
                }
                .padding(.top, 4)

                if board.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView().tint(tierColor)
                        Text(loadingLeague ? "Loading your league…" : "Waiting for competitors to join…")
                            .font(CX.body(14)).foregroundStyle(CX.navySoft)
                    }.padding(.vertical, 40)
                } else {
                    ForEach(Array(board.enumerated()), id: \.element.id) { idx, entry in
                        if idx == Seed.leaguePromotionCount {
                            zoneDivider("PROMOTION ZONE — top \(Seed.leaguePromotionCount) move up", color: CX.teal)
                        }
                        leagueRow(entry)
                    }
                }

                inviteCard.padding(.top, 6)
                learnMoreButton
            }
            .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) {
            if let me = myEntry { pinnedRow(me) }
        }
    }

    private func zoneDivider(_ text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold))
            Text(text).font(CX.label(13))
            Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func leagueRow(_ e: LeagueEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(e.rank)").font(CX.heading(18)).foregroundStyle(rankColor(e.rank))
                .frame(width: 26, alignment: .center)
            avatar(e.avatarTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(CX.heading(16)).foregroundStyle(CX.navy).lineLimit(1)
                if e.trophies > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "trophy.fill").font(.system(size: 11)).foregroundStyle(CX.gold)
                        Text("\(e.trophies)").font(CX.label(11)).foregroundStyle(CX.navySoft)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("+\(e.weeklyXP)").font(CX.heading(17)).foregroundStyle(CX.navy)
                Text("\(e.totalXP)").font(CX.label(12)).foregroundStyle(CX.teal)
            }
        }
        .padding(14)
        .background(rowBackground(e), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(e.isYou ? CX.orange : rowStroke(e.rank), lineWidth: e.isYou ? 2.5 : 1.5))
    }

    /// The sticky "you" row pinned above the tab bar.
    private func pinnedRow(_ e: LeagueEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(e.rank)").font(CX.heading(18)).foregroundStyle(CX.navy).frame(width: 26)
            avatar(CX.orange)
            Text(e.name).font(CX.heading(16)).foregroundStyle(CX.navy).lineLimit(1)
            Spacer()
            Text("+\(e.weeklyXP)").font(CX.heading(17)).foregroundStyle(CX.teal)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CX.orange, lineWidth: 2.5))
        .padding(.horizontal, 18).padding(.bottom, 6)
    }

    private func avatar(_ tint: Color) -> some View {
        ZStack {
            Circle().fill(tint.opacity(0.18)).frame(width: 38, height: 38)
            Image(systemName: "pawprint.fill").font(.system(size: 18)).foregroundStyle(tint)
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return CX.gold
        case 2: return Color(hex: 0xB8C2CC)
        case 3: return Color(hex: 0xCD8B5A)
        default: return CX.navySoft
        }
    }
    private func rowBackground(_ e: LeagueEntry) -> Color {
        if e.isYou { return CX.orange.opacity(0.10) }
        switch e.rank {
        case 1: return CX.gold.opacity(0.14)
        case 2: return Color(hex: 0xB8C2CC).opacity(0.16)
        case 3: return Color(hex: 0xCD8B5A).opacity(0.14)
        default: return CX.card
        }
    }
    private func rowStroke(_ rank: Int) -> Color { rank <= 3 ? rankColor(rank).opacity(0.5) : CX.hairline }

    // MARK: Shared pieces

    private var inviteCard: some View {
        ShareLink(item: "I've been climbing the weekly league on Cortex — real clinical cases, real ranks. Join me and let's see who tops the leaderboard! 🦊🩺") {
            CXCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Invite your friends").font(CX.title(20)).foregroundStyle(CX.navy)
                        Text("Challenge them everyday with a clinical case.")
                            .font(CX.body(14)).foregroundStyle(CX.navySoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "gift.fill").font(.system(size: 36)).foregroundStyle(CX.orange)
                }
            }
        }.buttonStyle(.plain)
    }

    private var learnMoreButton: some View {
        Button { showLearnMore = true } label: {
            Text("Learn more about Leagues").font(CX.heading(16)).foregroundStyle(CX.orange)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CX.hairline, lineWidth: 1.5))
        }.buttonStyle(PressStyle())
    }

    // MARK: Actions

    private func ensureRandom() {
        let unsolved = store.clinicalCases.filter { !app.isCaseSolved($0.id) }
        if let c = randomCase, unsolved.contains(where: { $0.id == c.id }) { return }
        randomCase = unsolved.randomElement() ?? store.clinicalCases.randomElement()
    }
    private func solveCase() {
        guard app.canAfford(life: app.randomCaseCost) else { showNoLife = true; return }
        ensureRandom()
        active = randomCase
    }
}

/// Explains how the weekly league works + the full rank ladder.
struct LeagueInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var app: AppState
    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                HStack {
                    Text("How Leagues Work").font(CX.title(22)).foregroundStyle(CX.navy)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(CX.navySoft)
                    }
                }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        CXCard {
                            VStack(alignment: .leading, spacing: 10) {
                                infoLine("person.3.fill", "Each league room holds up to \(Seed.leagueSize) real players. Your rank is the XP you earn from cases this week.")
                                infoLine("arrow.up.circle.fill", "Every week the top \(Seed.leaguePromotionCount) are promoted to the next league: Bronze → Silver → Gold → … → Diamond.")
                                infoLine("dollarsign.circle.fill", "Promoted players earn coins + XP scaled by their finishing rank and the league they reach — the higher the league, the bigger the reward.")
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("THE LEAGUES").font(CX.label(13)).foregroundStyle(CX.navySoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(spacing: 0) {
                            ForEach(Array(League.allCases.reversed().enumerated()), id: \.element.rawValue) { idx, lg in
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(lg.color.opacity(0.18)).frame(width: 40, height: 40)
                                        Image(systemName: lg.icon).font(.system(size: 19)).foregroundStyle(lg.color)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lg.name).font(CX.heading(16)).foregroundStyle(CX.navy)
                                        Text(lg == .diamond ? "Top league" : "League \(lg.tierLevel) of 10")
                                            .font(CX.body(13)).foregroundStyle(lg.color)
                                    }
                                    Spacer()
                                    if app.league == lg {
                                        Text("YOU").font(CX.label(11)).foregroundStyle(.white)
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(lg.color, in: Capsule())
                                    }
                                }.padding(.horizontal, 14).padding(.vertical, 12)
                                if idx < League.allCases.count - 1 { Divider().padding(.leading, 14) }
                            }
                        }
                        .background(CX.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(CX.hairline, lineWidth: 1.5))
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
    }
    private func infoLine(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(CX.teal).frame(width: 22)
            Text(text).font(CX.body(15)).foregroundStyle(CX.navySoft).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Me tab
struct MeView: View {
    @EnvironmentObject var app: AppState
    @State private var editingName = false
    @State private var draftName = ""
    @State private var showShop = false
    @State private var showTrophies = false
    @State private var showCoinsInfo = false
    @State private var confirmLogout = false
    @State private var infoPage: InfoPageKind?
    @Environment(\.openURL) private var openURL

    /// The Me-page legal/help screens, presented as sheets.
    enum InfoPageKind: String, Identifiable {
        case terms, privacy, faqs, support
        var id: String { rawValue }
    }

    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                TopBar()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        VixClip(anim: .tail, size: 130, fallback: .avatar)
                            .clipShape(Circle())
                            .padding(6)
                            .background(Circle().stroke(CX.orange, lineWidth: 4))
                            .padding(.top, 8)
                        VStack(spacing: 4) {
                            Text(app.displayName).font(CX.title(28)).foregroundStyle(CX.navy)
                            Text("June 2026").font(CX.heading(16)).foregroundStyle(CX.navySoft)
                        }
                        editProfileButton

                        leagueCard()
                        trophiesCard

                        // 2×2 stat grid (matches the video)
                        HStack(spacing: 12) {
                            statBox("🔥", "\(app.streak)", "Day Streak")
                            statBox("⚡️", "\(app.lifetimeXP)", "Lifetime XP")
                        }
                        HStack(spacing: 12) {
                            statBox("📗", "\(app.casesFinished)", "Cases")
                            statBox("🏅", "\(app.topThreeFinishes)", "Top 3 Finishes")
                        }

                        coinsCard

                        settingsList
                        Text("Cortex • v1.0").font(CX.label(12)).foregroundStyle(CX.navySoft)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 24)
                }
            }
        }
        .sheet(isPresented: $showShop) { StreakFreezeShop() }
        .sheet(isPresented: $showTrophies) { TrophyDetailSheet() }
        .sheet(isPresented: $showCoinsInfo) { CoinsInfoSheet() }
        .sheet(item: $infoPage) { page in
            switch page {
            case .terms:   TermsOfUseView()
            case .privacy: PrivacyPolicyView()
            case .faqs:    FAQsView()
            case .support: SupportView()
            }
        }
        .alert("Edit Profile", isPresented: $editingName) {
            TextField("Username", text: $draftName)
            Button("Save") { saveName() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown on your profile and the global leaderboard.")
        }
        .confirmationDialog("Log out of Cortex?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                // Save this account's progress, then sign out (returns to sign-in).
                Task { await app.unbindAccount(); SupabaseService.shared.signOutPlayer() }
            }
            Button("Stay Logged In", role: .cancel) {}
        } message: {
            Text(SupabaseService.shared.userEmail.map { "Signed in as \($0).\nYour progress is saved to your account — you'll need to sign in again to play." }
                 ?? "Your progress is saved to your account — you'll need to sign in again to play.")
        }
    }

    private var editProfileButton: some View {
        Button {
            draftName = app.displayName
            editingName = true
        } label: {
            HStack(spacing: 8) {
                Text("Edit Profile").font(CX.heading(16)).foregroundStyle(CX.navy)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(CX.orange)
            }
            .padding(.horizontal, 26).padding(.vertical, 12)
            .background(.white, in: Capsule())
            .overlay(Capsule().stroke(CX.hairline, lineWidth: 1.5))
        }.buttonStyle(PressStyle())
    }

    private var trophiesCard: some View {
        let m = app.masteryCounts
        return CXCard {
            VStack(spacing: 14) {
                HStack {
                    Text("Specialty Trophies").font(CX.heading(20)).foregroundStyle(CX.navy)
                    Spacer()
                    Button { showTrophies = true } label: {
                        Text("DETAILS ›").font(CX.label(13)).foregroundStyle(CX.teal)
                    }
                }
                HStack(spacing: 12) {
                    trophyBox("\(m.gold)", "GOLD", CX.gold)
                    trophyBox("\(m.silver)", "SILVER", CX.teal)
                    trophyBox("\(m.bronze)", "BRONZE", Color(hex: 0xCD8B5A))
                }
            }
        }
    }

    private var coinsCard: some View {
        CXCard {
            HStack(spacing: 14) {
                Button { showCoinsInfo = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dollarsign.circle.fill").font(.system(size: 40)).foregroundStyle(CX.gold)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(app.coins)").font(CX.title(26)).foregroundStyle(CX.navy)
                            Text("Coins").font(CX.body(14)).foregroundStyle(CX.navySoft)
                        }
                    }
                }.buttonStyle(.plain)
                Spacer()
                Button { showShop = true } label: {
                    Text("Shop").font(CX.heading(17)).foregroundStyle(.white)
                }
                .buttonStyle(PushButtonStyle(face: CX.orange, lip: CX.orangeDark))
            }
        }
    }

    private var settingsList: some View {
        VStack(spacing: 0) {
            settingsRow("doc.text.fill", "Terms of use") { infoPage = .terms }
            settingsRow("lock.shield.fill", "Privacy Policy") { infoPage = .privacy }
            settingsRow("questionmark.circle.fill", "FAQs") { infoPage = .faqs }
            settingsRow("envelope.fill", "Facing a Problem? Contact Us") { infoPage = .support }
            settingsRow("rectangle.portrait.and.arrow.right.fill", "Logout", tint: CX.orange, last: true) { confirmLogout = true }
        }
        .background(CX.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func saveName() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        app.displayName = String(name.prefix(40))
        // Push the new name to the leaderboard right away.
        Task { await SupabaseService.shared.submitScore(
            playerId: app.leaderboardId, username: app.displayName, xp: app.lifetimeXP) }
    }

    private func leagueCard() -> some View {
        let skill = app.skill
        let p = app.levelProgress
        let frac = min(1.0, Double(p.into) / Double(max(p.needed, 1)))
        return CXCard {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(skill.color.opacity(0.18)).frame(width: 52, height: 52)
                        Image(systemName: skill.icon).font(.system(size: 26)).foregroundStyle(skill.color)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("LEVEL \(app.level)").font(CX.label(12)).foregroundStyle(CX.navySoft)
                        Text(skill.name).font(CX.heading(22)).foregroundStyle(CX.navy)
                    }
                    Spacer()
                    Text("\(app.lifetimeXP) XP").font(CX.label(14)).foregroundStyle(CX.teal)
                }
                VStack(alignment: .leading, spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.08))
                            Capsule().fill(skill.color).frame(width: geo.size.width * frac)
                        }
                    }.frame(height: 10)
                    Text("\(p.into) / \(p.needed) XP to Level \(app.level + 1)")
                        .font(CX.label(12)).foregroundStyle(CX.orange)
                }
            }
        }
    }

    private func trophyBox(_ n: String, _ label: String, _ c: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "trophy.fill").font(.system(size: 30)).foregroundStyle(c)
            Text("\(n) \(label)").font(CX.label(12)).foregroundStyle(CX.navySoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(c.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    private func statBox(_ e: String, _ n: String, _ label: String) -> some View {
        CXCard {
            VStack(spacing: 4) {
                Text(e).font(.system(size: 24))
                Text(n).font(CX.title(22)).foregroundStyle(CX.navy)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(label).font(CX.body(12)).foregroundStyle(CX.navySoft)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
    }
    private func settingsRow(_ icon: String, _ title: String, tint: Color = CX.navySoft,
                             last: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(CX.orange).frame(width: 26)
                Text(title).font(CX.body(16)).foregroundStyle(tint)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14)).foregroundStyle(CX.hairline)
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
            .overlay(alignment: .bottom) { if !last { Divider().padding(.leading, 56) } }
        }.buttonStyle(PressStyle())
    }
}

// MARK: - Trophy detail sheet (tap "DETAILS ›")
struct TrophyDetailSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    private static let bronzeColor = Color(hex: 0xCD8B5A)
    private func tierColor(_ tier: Int) -> Color {
        switch tier { case 3: return CX.gold; case 2: return CX.teal; case 1: return Self.bronzeColor
        default: return CX.navySoft }
    }
    private func tierName(_ tier: Int) -> String {
        switch tier { case 3: return "Gold"; case 2: return "Silver"; case 1: return "Bronze"; default: return "—" }
    }

    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                HStack {
                    Text("Specialty Trophies").font(CX.title(24)).foregroundStyle(CX.navy)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(CX.navySoft)
                    }
                }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        CXCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Master each specialty").font(CX.heading(17)).foregroundStyle(CX.navy)
                                ruleRow(Self.bronzeColor, "Bronze", "Solve \(AppState.bronzeSegment) cases")
                                ruleRow(CX.teal, "Silver", "Solve \(AppState.silverSegment) more (\(AppState.silverMastery))")
                                ruleRow(CX.gold, "Gold", "Solve \(AppState.goldSegment) more (\(AppState.goldMastery))")
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if app.specialtiesByProgress.isEmpty {
                            Text("Solve cases to start earning specialty trophies.")
                                .font(CX.body(14)).foregroundStyle(CX.navySoft)
                                .multilineTextAlignment(.center).padding(.top, 10)
                        } else {
                            ForEach(app.specialtiesByProgress, id: \.self) { sp in
                                specialtyRow(sp)
                            }
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func ruleRow(_ color: Color, _ name: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill").foregroundStyle(color).frame(width: 22)
            Text(name).font(CX.body(15)).foregroundStyle(CX.navy)
            Spacer()
            Text(detail).font(CX.label(13)).foregroundStyle(CX.navySoft)
        }
    }

    /// Next milestone above the current solved count (nil once Gold is reached).
    private func nextMilestone(_ solved: Int) -> Int? {
        if solved < AppState.bronzeMastery { return AppState.bronzeMastery }
        if solved < AppState.silverMastery { return AppState.silverMastery }
        if solved < AppState.goldMastery   { return AppState.goldMastery }
        return nil
    }

    private func specialtyRow(_ sp: String) -> some View {
        let solved = app.solvedCount(in: sp)
        let tier = app.masteryTier(sp)
        let color = tierColor(tier)
        let next = nextMilestone(solved)
        return CXCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(color.opacity(0.16)).frame(width: 48, height: 48)
                        Image(systemName: tier > 0 ? "trophy.fill" : "lock.fill")
                            .font(.system(size: 22)).foregroundStyle(color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sp).font(CX.heading(17)).foregroundStyle(CX.navy)
                        Text(tier > 0 ? "\(tierName(tier)) · \(solved) solved" : "\(solved) solved")
                            .font(CX.body(13)).foregroundStyle(CX.navySoft)
                    }
                    Spacer()
                    if tier > 0 {
                        Text(tierName(tier).uppercased()).font(CX.label(11)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(color, in: Capsule())
                    }
                }
                if let next {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.08))
                            Capsule().fill(color).frame(width: geo.size.width * min(1, Double(solved) / Double(next)))
                        }
                    }.frame(height: 8)
                    Text("\(solved) / \(next) to \(tierName(tier + 1))")
                        .font(CX.label(12)).foregroundStyle(CX.navySoft)
                } else {
                    Text("Gold mastery — fully complete! 🏆")
                        .font(CX.label(12)).foregroundStyle(CX.gold)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - "How to Earn Coins" sheet (tap the coins card)
struct CoinsInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 20, weight: .bold)).foregroundStyle(CX.navy)
                    }
                    Spacer()
                    Text("How to Earn Coins").font(CX.heading(18)).foregroundStyle(CX.navy)
                    Spacer()
                    Image(systemName: "chevron.left").font(.system(size: 20)).foregroundStyle(.clear)
                }.padding(.horizontal, 18).padding(.vertical, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        section("stethoscope", CX.teal, "Solve Cases", [
                            ("Diagnosis", "The right diagnosis is worth the most — up to 60% of the reward."),
                            ("Tests", "Order the high-yield tests, skip the noise — up to 20%."),
                            ("Treatment", "Choose the appropriate treatments — up to 20%.")
                        ])
                        section("dollarsign.circle.fill", CX.gold, "How much", [
                            ("Earn = score", "Coins added always match the amount shown on the case's result screen."),
                            ("Better workup", "A flawless solve pays the full reward; guessing pays little or nothing.")
                        ])
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
    }

    private func section(_ icon: String, _ color: Color, _ title: String, _ rows: [(String, String)]) -> some View {
        CXCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: icon).font(.system(size: 22)).foregroundStyle(color)
                    Text(title).font(CX.heading(20)).foregroundStyle(CX.teal)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "dollarsign.circle.fill").foregroundStyle(CX.gold).font(.system(size: 18))
                        Text(row.0).font(CX.heading(15)).foregroundStyle(CX.navy)
                        Text("- " + row.1).font(CX.body(14)).foregroundStyle(CX.navySoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
