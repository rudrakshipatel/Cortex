import SwiftUI
import Combine

// MARK: - App-wide state
@MainActor
final class AppState: ObservableObject {
    /// True while loading this account's cloud profile right after sign-in.
    @Published private(set) var isSyncing = false
    /// True once the signed-in account's profile has been bound this session.
    private var accountBound = false
    private var bag = Set<AnyCancellable>()

    /// Identity for the global leaderboard — the signed-in account when
    /// available, else the device's anonymous id.
    var leaderboardId: String { SupabaseService.shared.userId ?? playerId }
    /// Whether the user has finished onboarding. Published (not @AppStorage) so
    /// that flipping it actually re-renders RootView and shows the main app.
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }

    /// XP is the lifetime score that drives the Leagues ranking.
    @Published var lifetimeXP: Int  { didSet { defaults.set(lifetimeXP, forKey: K.xp) } }
    /// Coins are the spendable currency — earned by solving cases, spent to
    /// unlock Mentor Insight.
    @Published var coins: Int       { didSet { defaults.set(coins, forKey: K.coins) } }
    /// Life is energy spent to play cases; it refills to `maxLife` at GMT 00:00.
    /// Fractional so Pro's 8.5-energy cases can be represented exactly (the
    /// on-screen bar shows it rounded).
    @Published var life: Double     { didSet { defaults.set(life, forKey: K.life) } }
    @Published var isPro: Bool = false
    /// Username shown on the profile and the global leaderboard.
    @Published var displayName: String { didSet { defaults.set(displayName, forKey: K.name) } }

    /// Stable anonymous identity for the global leaderboard (generated once).
    let playerId: String

    /// Full Life bar — restored every GMT day.
    nonisolated static let maxLife = 100.0

    /// Country chosen during onboarding (persisted). Emergency timing uses the
    /// device's own timezone, which is more precise than country.
    @Published var country: String { didSet { defaults.set(country, forKey: K.country) } }

    // MARK: Onboarding personalization (persisted)
    /// What the user does — "Medical Student", "Resident", … Shown on the plan
    /// summary and the profile.
    @Published var position: String { didSet { defaults.set(position, forKey: K.position) } }
    /// Self-rated clinical experience — "Just starting out" … "Seasoned".
    @Published var experience: String { didSet { defaults.set(experience, forKey: K.experience) } }
    /// Specialties the user said they're interested in.
    @Published var specialtyInterests: [String] { didSet { defaults.set(specialtyInterests, forKey: K.interests) } }
    /// What they're training for — "Pass my exams", …
    @Published var trainingGoal: String { didSet { defaults.set(trainingGoal, forKey: K.goal) } }
    /// Cases-a-day the user committed to during onboarding.
    @Published var dailyGoalCases: Int { didSet { defaults.set(dailyGoalCases, forKey: K.dailyGoal) } }
    /// An invite code entered during onboarding, redeemed once an account binds.
    @Published var pendingInviteCode: String? { didSet { defaults.set(pendingInviteCode, forKey: K.invite) } }

    /// Marks onboarding complete — the single call that swaps RootView over to
    /// the main app.
    func finishOnboarding() { onboarded = true }

    // MARK: Streak (GMT-day based, persisted)
    @Published private(set) var streak: Int            { didSet { defaults.set(streak, forKey: K.streak) } }
    @Published private(set) var lastActiveEpochDay: Int { didSet { defaults.set(lastActiveEpochDay, forKey: K.lastDay) } }
    /// The best streak ever reached (for the "new record" coin bonus).
    @Published private(set) var highestStreak: Int     { didSet { defaults.set(highestStreak, forKey: K.highStreak) } }
    /// Streak Freezes owned — each covers one missed day (bought in the Shop).
    @Published private(set) var streakFreezes: Int     { didSet { defaults.set(streakFreezes, forKey: K.freezes) } }
    /// GMT days the user was active — drives the streak calendar.
    @Published private(set) var activeDays: Set<Int>   { didSet { defaults.set(Array(activeDays), forKey: K.activeDays) } }
    /// A pending "setback" (lost streak / league demotion) to commiserate with
    /// the player. Transient — surfaced once as a sheet, then cleared. Not saved.
    @Published var pendingSetback: SetbackInfo? = nil
    /// A case link the player tapped outside the app (a friend's challenge).
    /// Transient — the main tab view opens it, then clears it. Not saved.
    @Published var pendingLink: CortexLink? = nil
    /// The GMT day Life was last refilled — drives the daily reset.
    @Published private(set) var lastLifeDay: Int { didSet { defaults.set(lastLifeDay, forKey: K.lifeDay) } }
    /// Timestamp from which energy has been regenerating.
    private var lastEnergyDate: Date { didSet { defaults.set(lastEnergyDate.timeIntervalSince1970, forKey: K.energyDate) } }
    /// GMT days on which the user has already solved that day's Daily Case.
    @Published private(set) var solvedDailyDays: Set<Int> {
        didSet { defaults.set(Array(solvedDailyDays), forKey: K.solvedDaily) }
    }
    /// IDs of clinical/practice cases solved correctly — excluded from "random".
    @Published private(set) var solvedCaseIDs: Set<String> {
        didSet { defaults.set(Array(solvedCaseIDs), forKey: K.solvedCases) }
    }
    /// Count of distinct cases solved per specialty — drives mastery trophies.
    @Published private(set) var specialtySolved: [String: Int] {
        didSet { defaults.set(specialtySolved, forKey: K.specialtySolved) }
    }
    /// Best trophy tier earned per case (1 = bronze, 2 = silver, 3 = gold),
    /// keyed by case id — shown on that case's Practice card.
    @Published private(set) var caseTrophies: [String: Int] {
        didSet { defaults.set(caseTrophies, forKey: K.caseTrophies) }
    }

    // MARK: Solved progress (persisted)
    /// Cases finished with the correct diagnosis. Broken into trophy tiers by
    /// how well the workup went: gold = perfect, silver = strong, bronze = solved.
    @Published private(set) var casesSolved: Int { didSet { defaults.set(casesSolved, forKey: K.casesSolved) } }
    /// Total cases finished (regardless of outcome) — used to qualify for the league.
    @Published private(set) var casesFinished: Int { didSet { defaults.set(casesFinished, forKey: K.casesFinished) } }
    /// XP earned in the current league week (resets every week). Drives the league rank.
    @Published private(set) var weeklyXP: Int { didSet { defaults.set(weeklyXP, forKey: K.weeklyXP) } }
    /// Cases finished in the current league week — need ≥1 to enter the leaderboard.
    @Published private(set) var leagueCasesThisWeek: Int { didSet { defaults.set(leagueCasesThisWeek, forKey: K.leagueCases) } }
    private var lastLeagueWeek: Int { didSet { defaults.set(lastLeagueWeek, forKey: K.leagueWeek) } }
    @Published private(set) var gold: Int        { didSet { defaults.set(gold, forKey: K.gold) } }
    @Published private(set) var silver: Int      { didSet { defaults.set(silver, forKey: K.silver) } }
    @Published private(set) var bronze: Int      { didSet { defaults.set(bronze, forKey: K.bronze) } }
    /// Top-3 league finishes (shown as a profile stat).
    @Published private(set) var topThreeFinishes: Int { didSet { defaults.set(topThreeFinishes, forKey: K.topThree) } }

    /// Current league tier (0 = Bronze … 9 = Diamond). Rises on a promotion-zone finish.
    @Published private(set) var leagueTier: Int { didSet { defaults.set(leagueTier, forKey: K.leagueTier) } }
    /// The latest GMT week whose league result we've already applied (promotion + rewards).
    @Published private(set) var lastLeagueResultWeek: Int { didSet { defaults.set(lastLeagueResultWeek, forKey: K.leagueResultWeek) } }
    /// The player's current league tier.
    var league: League { League(rawValue: Swift.min(Swift.max(leagueTier, 0), League.allCases.count - 1)) ?? .bronze }

    private let defaults = UserDefaults.standard
    private enum K {
        static let xp = "cx.lifetimeXP", coins = "cx.coins", life = "cx.life", lifeDay = "cx.lifeDay"
        static let energyDate = "cx.lastEnergyDate"
        static let streak = "cx.streak", lastDay = "cx.lastActiveDay", country = "cx.country"
        static let casesSolved = "cx.casesSolved", gold = "cx.gold", silver = "cx.silver", bronze = "cx.bronze"
        static let casesFinished = "cx.casesFinished", topThree = "cx.topThreeFinishes"
        static let weeklyXP = "cx.weeklyXP", leagueCases = "cx.leagueCasesThisWeek", leagueWeek = "cx.leagueWeek"
        static let solvedDaily = "cx.solvedDaily", playerId = "cx.playerId", name = "cx.name"
        static let solvedCases = "cx.solvedCases", caseTrophies = "cx.caseTrophies"
        static let freezes = "cx.streakFreezes", activeDays = "cx.activeDays", highStreak = "cx.highStreak"
        static let leagueTier = "cx.leagueTier", leagueResultWeek = "cx.leagueResultWeek"
        static let specialtySolved = "cx.specialtySolved"
        static let position = "cx.position", experience = "cx.experience"
        static let interests = "cx.specialties", goal = "cx.goal"
        static let dailyGoal = "cx.dailyGoalCases", invite = "cx.pendingInviteCode"
    }

    init() {
        let d = UserDefaults.standard
        onboarded = d.bool(forKey: "onboarded")
        if let pid = d.string(forKey: K.playerId) {
            playerId = pid
        } else {
            let pid = UUID().uuidString.lowercased()
            d.set(pid, forKey: K.playerId)
            playerId = pid
        }
        lifetimeXP = d.object(forKey: K.xp)    as? Int ?? 0   // new users start at Level 1
        coins      = d.object(forKey: K.coins) as? Int ?? 500   // new users start with 500 free coins
        life       = d.object(forKey: K.life) != nil ? d.double(forKey: K.life) : Self.maxLife
        lastLifeDay = d.object(forKey: K.lifeDay) as? Int ?? Self.gmtDay()
        let storedEnergyTS = d.double(forKey: K.energyDate)   // 0 when unset
        lastEnergyDate = storedEnergyTS > 0 ? Date(timeIntervalSince1970: storedEnergyTS) : Date()
        // didSet doesn't fire during init, so persist the seed timestamp now —
        // otherwise every launch would reset the regen clock and energy would
        // never accrue across launches.
        if storedEnergyTS <= 0 { d.set(lastEnergyDate.timeIntervalSince1970, forKey: K.energyDate) }
        streak     = d.object(forKey: K.streak) as? Int ?? 0
        lastActiveEpochDay = d.object(forKey: K.lastDay) as? Int ?? 0
        streakFreezes = d.object(forKey: K.freezes) as? Int ?? 0
        highestStreak = d.object(forKey: K.highStreak) as? Int ?? 0
        activeDays = Set(d.array(forKey: K.activeDays) as? [Int] ?? [])
        solvedDailyDays = Set(d.array(forKey: K.solvedDaily) as? [Int] ?? [])
        solvedCaseIDs = Set(d.stringArray(forKey: K.solvedCases) ?? [])
        specialtySolved = d.dictionary(forKey: K.specialtySolved) as? [String: Int] ?? [:]
        caseTrophies = d.dictionary(forKey: K.caseTrophies) as? [String: Int] ?? [:]
        if let storedName = d.string(forKey: K.name), storedName != "Dr. Vix" {
            displayName = storedName
        } else {
            // First launch (or the legacy "Dr. Vix" default): assign a random
            // alphanumeric guest name (persisted), which stays until the user
            // edits it.
            let guest = AppState.randomGuestName()
            d.set(guest, forKey: K.name)
            displayName = guest
        }
        casesSolved = d.object(forKey: K.casesSolved) as? Int ?? 0
        casesFinished = d.object(forKey: K.casesFinished) as? Int ?? 0
        weeklyXP = d.object(forKey: K.weeklyXP) as? Int ?? 0
        leagueCasesThisWeek = d.object(forKey: K.leagueCases) as? Int ?? 0
        lastLeagueWeek = d.object(forKey: K.leagueWeek) as? Int ?? Self.gmtWeek()
        gold   = d.object(forKey: K.gold)   as? Int ?? 0
        silver = d.object(forKey: K.silver) as? Int ?? 0
        bronze = d.object(forKey: K.bronze) as? Int ?? 0
        topThreeFinishes = d.object(forKey: K.topThree) as? Int ?? 0
        country = d.string(forKey: K.country) ?? ""
        position = d.string(forKey: K.position) ?? ""
        experience = d.string(forKey: K.experience) ?? ""
        specialtyInterests = d.stringArray(forKey: K.interests) ?? []
        trainingGoal = d.string(forKey: K.goal) ?? ""
        dailyGoalCases = d.object(forKey: K.dailyGoal) as? Int ?? 5
        pendingInviteCode = d.string(forKey: K.invite)
        leagueTier = d.object(forKey: K.leagueTier) as? Int ?? 0          // start in Bronze
        lastLeagueResultWeek = d.object(forKey: K.leagueResultWeek) as? Int ?? Self.gmtWeek()
        refreshForNewDay()

        // Autosave: 2s after the last change, push the profile to the cloud (only
        // once an account is bound). Captures every mutation without instrumenting
        // each call site.
        objectWillChange
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.autosaveProfile() }
            .store(in: &bag)
    }

    // MARK: - Cloud profile (per-account, syncs on sign-in)

    /// The slice of state that belongs to the account (everything except the
    /// device-local `playerId`). Stored as the `state` JSON in `profiles`.
    /// Note: `onboarded` is deliberately NOT here — onboarding completion is a
    /// sticky, device-local flag (UserDefaults), so a sync hiccup or a fresh
    /// profile can never make the onboarding flow reappear.
    struct ProfileState: Codable {
        var lifetimeXP = 0, coins = 500, life = AppState.maxLife
        var displayName = "Dr. Vix", country = ""
        var streak = 0, lastActiveEpochDay = 0, highestStreak = 0, streakFreezes = 0
        var activeDays: [Int] = [], lastLifeDay = 0, lastEnergyTS = 0.0
        var solvedDailyDays: [Int] = [], solvedCaseIDs: [String] = []
        var caseTrophies: [String: Int] = [:]
        var specialtySolved: [String: Int] = [:]
        var casesSolved = 0, casesFinished = 0, weeklyXP = 0, leagueCasesThisWeek = 0
        var lastLeagueWeek = 0, gold = 0, silver = 0, bronze = 0, topThreeFinishes = 0
        var leagueTier = 0, lastLeagueResultWeek = 0
    }

    func exportProfile() -> ProfileState {
        ProfileState(
            lifetimeXP: lifetimeXP, coins: coins, life: life,
            displayName: displayName, country: country, streak: streak,
            lastActiveEpochDay: lastActiveEpochDay, highestStreak: highestStreak,
            streakFreezes: streakFreezes, activeDays: Array(activeDays), lastLifeDay: lastLifeDay,
            lastEnergyTS: lastEnergyDate.timeIntervalSince1970,
            solvedDailyDays: Array(solvedDailyDays), solvedCaseIDs: Array(solvedCaseIDs),
            caseTrophies: caseTrophies, specialtySolved: specialtySolved,
            casesSolved: casesSolved, casesFinished: casesFinished,
            weeklyXP: weeklyXP, leagueCasesThisWeek: leagueCasesThisWeek, lastLeagueWeek: lastLeagueWeek,
            gold: gold, silver: silver, bronze: bronze, topThreeFinishes: topThreeFinishes,
            leagueTier: leagueTier, lastLeagueResultWeek: lastLeagueResultWeek)
    }

    func applyProfile(_ p: ProfileState) {
        // `onboarded` intentionally untouched — it's a sticky local flag.
        lifetimeXP = p.lifetimeXP; coins = p.coins; life = p.life
        displayName = p.displayName; country = p.country
        streak = p.streak; lastActiveEpochDay = p.lastActiveEpochDay
        highestStreak = p.highestStreak; streakFreezes = p.streakFreezes
        activeDays = Set(p.activeDays); lastLifeDay = p.lastLifeDay
        lastEnergyDate = p.lastEnergyTS > 0 ? Date(timeIntervalSince1970: p.lastEnergyTS) : Date()
        solvedDailyDays = Set(p.solvedDailyDays); solvedCaseIDs = Set(p.solvedCaseIDs)
        caseTrophies = p.caseTrophies; specialtySolved = p.specialtySolved
        casesSolved = p.casesSolved; casesFinished = p.casesFinished
        weeklyXP = p.weeklyXP; leagueCasesThisWeek = p.leagueCasesThisWeek
        lastLeagueWeek = p.lastLeagueWeek
        gold = p.gold; silver = p.silver; bronze = p.bronze; topThreeFinishes = p.topThreeFinishes
        leagueTier = p.leagueTier
        lastLeagueResultWeek = Swift.max(lastLeagueResultWeek, p.lastLeagueResultWeek)
        refreshForNewDay()
    }

    /// Reset all account progress to a fresh start (used when a new account signs
    /// in on a device that previously held a different one). Leaves `onboarded`
    /// alone — the device has already been through onboarding.
    func resetProgress() {
        applyProfile(ProfileState())
        displayName = Self.randomGuestName()   // a fresh account starts as a new guest
    }

    /// A random alphanumeric guest name, e.g. "Guest7K2QX". Assigned to every new
    /// user until they set their own display name.
    static func randomGuestName() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")   // no ambiguous 0/O/1/I
        return "Guest" + String((0..<5).map { _ in chars.randomElement()! })
    }

    /// Whether a name is one we assigned rather than one the player typed — a
    /// "GuestXXXXX", the legacy "Dr. Vix" default, or nothing at all. Only these
    /// may be replaced by the name on their account.
    static func isAssignedName(_ n: String) -> Bool {
        let t = n.trimmed
        if t.isEmpty || t == "Dr. Vix" { return true }
        guard t.count == 10, t.hasPrefix("Guest") else { return false }
        return t.dropFirst(5).allSatisfy { $0.isUppercase || $0.isNumber }
    }

    /// Take the player's name from their sign-in details, so a signed-in user
    /// isn't left as "Guest7K2QX". Never touches a name they chose themselves.
    private func adoptAccountName() {
        guard Self.isAssignedName(displayName),
              let name = SupabaseService.shared.accountDisplayName else { return }
        displayName = name
    }

    /// Bind the signed-in account: load its cloud profile, or create a fresh one.
    /// The very first account to sign in on a device claims the existing local
    /// progress; later/other accounts start clean.
    func bindAccount() async {
        guard SupabaseService.shared.isSignedIn else { return }
        isSyncing = true
        defer { isSyncing = false; accountBound = true }
        switch await SupabaseService.shared.loadProfile() {
        case .found(let data):
            if let p = try? JSONDecoder().decode(ProfileState.self, from: data) {
                applyProfile(p)                          // existing account → its own state
            }
            adoptAccountName()                           // still unnamed → use the account's own name
            defaults.set(true, forKey: "cx.hasBoundAccount")
        case .empty:
            // Genuinely no profile for this account.
            if defaults.bool(forKey: "cx.hasBoundAccount") {
                resetProgress()                          // a different account had this device → fresh
            }                                            // else: first ever → claim current local progress
            adoptAccountName()                           // name the fresh profile before it's created
            await pushProfileNow()                       // create the row
            defaults.set(true, forKey: "cx.hasBoundAccount")
        case .failed:
            break   // transient failure — keep local state, don't reset or overwrite the cloud
        }
    }

    /// Save the latest state, then forget the account (used on sign-out).
    func unbindAccount() async {
        await pushProfileNow()
        accountBound = false
        resetProgress()
    }

    /// Forget a just-deleted account and wipe local progress WITHOUT saving to
    /// the cloud (the account no longer exists). Used after account deletion.
    func wipeAfterAccountDeletion() {
        accountBound = false
        resetProgress()
        defaults.set(false, forKey: "cx.hasBoundAccount")
    }

    private func autosaveProfile() {
        guard accountBound, SupabaseService.shared.isSignedIn else { return }
        Task { await pushProfileNow() }
    }

    func pushProfileNow() async {
        guard SupabaseService.shared.isSignedIn,
              let data = try? JSONEncoder().encode(exportProfile()) else { return }
        await SupabaseService.shared.saveProfile(data)
    }

    // MARK: - League promotion

    /// Apply last week's league finish: if the player landed in the promotion
    /// zone (the top third of their room), promote them one tier (capped at
    /// Diamond) and award coins + XP scaled by rank and the new league. Returns
    /// the reward to celebrate, or nil if they didn't promote. `groupSize` is
    /// how many players were in the room — the zones are a third of that, so a
    /// part-full room still moves only a third (and a room under
    /// `Seed.leagueMinPlayers` moves nobody).
    func applyLeagueResult(rank: Int, groupSize: Int) -> LeagueReward? {
        guard rank >= 1 else { return nil }
        let zones = LeagueZones(size: groupSize)
        if zones.isPromotion(rank: rank) {
            // Promotion zone → move up a tier and earn coins (top 3 earn the most).
            let from = league
            if let next = from.next { leagueTier = next.rawValue }   // promote (Diamond stays)
            if rank <= 3 { topThreeFinishes += 1 }
            let award = rank <= 3 ? Seed.leagueTopThreeReward : Seed.leaguePromotionReward
            coins += award
            let reward = LeagueReward(rank: rank, league: league, coins: award)
            lifetimeXP += reward.xp
            return reward
        }
        // Safe zone (middle) → stay in the league and earn a small coin reward.
        if rank <= zones.safeThrough {
            coins += Seed.leagueSafeReward
        }
        return nil   // demotion (bottom zone) is handled by applyLeagueDemotion
    }

    /// Apply last week's finish when it lands in the demotion zone (the bottom
    /// third of the room): drop one tier (Bronze is the floor) and return a
    /// setback to commiserate. Returns nil if they finished in a safe rank, or
    /// if the room was too small to move anyone.
    func applyLeagueDemotion(rank: Int, groupSize: Int) -> SetbackInfo? {
        let zones = LeagueZones(size: groupSize)
        guard zones.isDemotion(rank: rank) else { return nil }
        let from = league
        let dropped = from.rawValue > 0
        if dropped { leagueTier = from.rawValue - 1 }                  // demote (Bronze stays)
        return .demoted(to: league, dropped: dropped)
    }

    /// Mark that we've processed league results up to (and including) `week`.
    func markLeagueResultProcessed(week: Int) {
        if week > lastLeagueResultWeek { lastLeagueResultWeek = week }
    }

    /// Whole days since the Unix epoch in **GMT** (all daily resets are at GMT 00:00).
    nonisolated static func gmtDay(_ date: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "GMT")!
        let start = cal.startOfDay(for: date)
        return Int(start.timeIntervalSince1970 / 86_400)
    }
    /// Back-compat alias used around the app.
    nonisolated static func epochDay(_ date: Date = Date()) -> Int { gmtDay(date) }

    /// League week index (Mon-anchored, GMT). Leagues reset each week.
    nonisolated static func gmtWeek(_ date: Date = Date()) -> Int {
        // Unix epoch (1970-01-01) was a Thursday; shift by 4 days so weeks start Monday.
        return (gmtDay(date) + 4) / 7
    }
    /// Whole days remaining in the current league week (for "resets in N days").
    var leagueDaysLeft: Int {
        let dayInWeek = (Self.gmtDay() + 4) % 7      // 0 = Monday … 6 = Sunday
        return Swift.max(1, 7 - dayInWeek)
    }

    /// Top up time-based energy regen and roll the league over on a new week.
    /// Safe to call repeatedly (idempotent between accrued whole units).
    func refreshForNewDay() {
        regenerateEnergy()
        lastLifeDay = Self.gmtDay()
        // Roll the league over at the start of each new week.
        let week = Self.gmtWeek()
        if week != lastLeagueWeek {
            weeklyXP = 0
            leagueCasesThisWeek = 0
            lastLeagueWeek = week
        }
    }

    // MARK: Energy regeneration
    /// Energy regenerated per minute — 0.0694444…/min = exactly 100 over 24 hours.
    static let energyRegenPerMinute = 100.0 / (24.0 * 60.0)

    /// Grant the energy accrued since `lastEnergyDate`, capped at `maxLife`.
    /// Energy is fractional, so it accrues continuously (no whole-unit remainder
    /// to carry) and the clock simply advances to now.
    func regenerateEnergy() {
        guard life < Self.maxLife else { lastEnergyDate = Date(); return }
        let now = Date()
        let minutes = now.timeIntervalSince(lastEnergyDate) / 60.0
        guard minutes > 0 else { return }
        let gained = minutes * Self.energyRegenPerMinute
        guard gained > 0 else { return }
        life = Swift.min(Self.maxLife, life + gained)
        lastEnergyDate = now
    }

    // MARK: Daily Case
    /// The GMT day index for "today".
    var todayKey: Int { Self.gmtDay() }
    var solvedTodaysDaily: Bool { solvedDailyDays.contains(todayKey) }
    func solvedDaily(day: Int) -> Bool { solvedDailyDays.contains(day) }
    func markDailySolved(day: Int) { solvedDailyDays.insert(day) }

    // MARK: Solved cases (per-case, by id)
    func isCaseSolved(_ id: UUID) -> Bool { solvedCaseIDs.contains(id.uuidString) }
    /// Mark a case solved. The first time a given case is solved, it also counts
    /// toward that specialty's mastery trophy.
    func markCaseSolved(_ id: UUID, specialty: String = "") {
        let (inserted, _) = solvedCaseIDs.insert(id.uuidString)
        let sp = specialty.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inserted, !sp.isEmpty else { return }
        let n = (specialtySolved[sp] ?? 0) + 1
        specialtySolved[sp] = n
        // Mastery-trophy coin reward, paid once as each tier is reached.
        switch n {
        case Self.bronzeMastery: coins += Self.bronzeTrophyReward
        case Self.silverMastery: coins += Self.silverTrophyReward
        case Self.goldMastery:   coins += Self.goldTrophyReward
        default: break
        }
    }

    // MARK: Specialty mastery trophies (count of solved cases per specialty)
    /// Cumulative solve totals to earn each trophy. The card chips show this as
    /// three segments — Bronze: first 10, Silver: next 50 (→60), Gold: next 100 (→160).
    static let bronzeMastery = 10, silverMastery = 60, goldMastery = 160
    /// Segment sizes shown on the per-specialty progress chips.
    static let bronzeSegment = 10, silverSegment = 50, goldSegment = 100
    /// Coins paid once when a specialty reaches each mastery trophy tier.
    static let bronzeTrophyReward = 500, silverTrophyReward = 1000, goldTrophyReward = 1000

    /// Highest mastery trophy reached in a specialty: 3 = Gold, 2 = Silver, 1 = Bronze, 0 = none.
    func masteryTier(_ specialty: String) -> Int {
        let n = specialtySolved[specialty] ?? 0
        if n >= Self.goldMastery   { return 3 }
        if n >= Self.silverMastery { return 2 }
        if n >= Self.bronzeMastery { return 1 }
        return 0
    }
    func solvedCount(in specialty: String) -> Int { specialtySolved[specialty] ?? 0 }

    /// Specialties the player has made progress in, sorted by most solved.
    var specialtiesByProgress: [String] {
        specialtySolved.keys.sorted { (specialtySolved[$0] ?? 0) > (specialtySolved[$1] ?? 0) }
    }

    /// How many specialties sit at each mastery trophy tier (by their highest tier).
    var masteryCounts: (gold: Int, silver: Int, bronze: Int) {
        var g = 0, s = 0, b = 0
        for sp in specialtySolved.keys {
            switch masteryTier(sp) { case 3: g += 1; case 2: s += 1; case 1: b += 1; default: break }
        }
        return (g, s, b)
    }

    /// True once the user has already completed a case today.
    var playedToday: Bool { lastActiveEpochDay == Self.gmtDay() }

    /// Record that the user was active today. Advances the streak on a
    /// consecutive day; a Streak Freeze covers each missed day, otherwise the
    /// streak resets. No-op if already counted today.
    func registerDailyActivity() {
        let today = Self.gmtDay()
        guard lastActiveEpochDay != today else { return }   // already counted today
        if lastActiveEpochDay == 0 {
            streak = 1                                      // first ever play
        } else {
            let missed = Swift.max(0, today - lastActiveEpochDay - 1)
            if missed == 0 {
                streak += 1
            } else if missed <= streakFreezes {
                streakFreezes -= missed                     // freezes save the streak
                streak += 1
            } else {
                if streak > 0 { pendingSetback = .streakLost(streak) }   // commiserate the loss
                streak = 1                                  // streak broken
            }
        }
        lastActiveEpochDay = today
        activeDays.insert(today)
        let brokeRecord = streak > highestStreak
        if brokeRecord { highestStreak = streak }              // track the record
        // Daily-activity coin rewards (see Cortex Shop → How to Earn Coins).
        if streak > 0 {
            coins += 100                                        // completed today's daily streak
            if brokeRecord && streak > 1 { coins += 500 }       // broke your highest-ever streak
            if streak % 10 == 0 { coins += 500 }                // every 10-day streak milestone
        }
    }

    // MARK: Shop
    nonisolated static let streakFreezeCost = 1000       // per Streak Freeze
    nonisolated static let xpPackAmount = 50             // XP granted per XP pack
    nonisolated static let xpPackCost = 1000             // coin cost of one XP pack

    /// Buy `count` Streak Freezes with coins. Returns false if too few coins.
    @discardableResult
    func buyStreakFreeze(count: Int = 1) -> Bool {
        let cost = Self.streakFreezeCost * count
        guard count > 0, coins >= cost else { return false }
        coins -= cost
        streakFreezes += count
        return true
    }

    /// Buy one XP pack (adds `xpPackAmount` XP) with coins. Returns false if too few coins.
    @discardableResult
    func buyXP() -> Bool {
        guard coins >= Self.xpPackCost else { return false }
        coins -= Self.xpPackCost
        award(xp: Self.xpPackAmount)
        return true
    }

    // MARK: Energy economy
    // Energy is spent *after* a case, scaled to how well it was solved: a perfect
    // 100-XP solve costs the least (5), a 0-XP attempt costs the most (15). The
    // cost falls linearly by 1 for every 10 XP earned.
    static let maxEnergyCost = 15   // earning 0 XP
    static let minEnergyCost = 5    // earning a perfect 100 XP

    /// Energy spent for a case, by the XP earned (0 → 15, 10 → 14, … 90 → 6, 100 → 5).
    static func energyCost(forXP xp: Int) -> Int {
        let cost = maxEnergyCost - Int((Double(xp) / 10.0).rounded())
        return Swift.min(maxEnergyCost, Swift.max(minEnergyCost, cost))
    }

    /// Energy a random/practice/past case costs. Free players pay a flat 16.5
    /// (~6 per full bar); Pro players pay only 8.5 (~12 per full bar).
    static let randomCaseEnergyCost = 16.5
    static let proCaseEnergyCost = 8.5
    var randomCaseCost: Double { isPro ? Self.proCaseEnergyCost : Self.randomCaseEnergyCost }

    /// A short human label for an energy amount — drops a trailing ".0".
    static func energyText(_ v: Double) -> String {
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }

    func canAfford(life cost: Double) -> Bool { life >= cost }
    /// Spend energy after a case, never dropping below zero. Banks any pending
    /// regen first, then starts the regen clock if this drops us below full.
    func spendEnergy(_ cost: Double) {
        regenerateEnergy()
        let wasFull = life >= Self.maxLife
        life = Swift.max(0, life - cost)
        if wasFull && life < Self.maxLife { lastEnergyDate = Date() }
    }

    // MARK: Level & skill (XP-based progression)
    /// Player level, starting at 1. Advancing from level L → L+1 costs L×100 XP.
    var level: Int { Self.level(forXP: lifetimeXP) }
    nonisolated static func level(forXP xp: Int) -> Int {
        var lvl = 1, spent = 0
        while spent + lvl * 100 <= xp { spent += lvl * 100; lvl += 1 }
        return lvl
    }
    /// XP earned within the current level, and the XP needed to reach the next.
    var levelProgress: (into: Int, needed: Int) {
        var lvl = 1, spent = 0
        while spent + lvl * 100 <= lifetimeXP { spent += lvl * 100; lvl += 1 }
        return (lifetimeXP - spent, lvl * 100)
    }
    /// The player's current skill rank/title.
    var skill: SkillRank { Seed.skill(forLevel: level) }

    /// Total XP required to reach a given level.
    nonisolated static func xpForLevel(_ level: Int) -> Int { 50 * (level - 1) * level }
    /// Progress through the current skill band and the next skill (nil at top).
    var skillProgress: (into: Int, needed: Int, next: SkillRank?) {
        let band = (level - 1) / 10 + 1
        let bandStartXP = Self.xpForLevel((band - 1) * 10 + 1)
        guard band < Seed.skillRanks.count else { return (lifetimeXP - bandStartXP, 0, nil) }
        let nextStartXP = Self.xpForLevel(band * 10 + 1)
        return (lifetimeXP - bandStartXP, nextStartXP - bandStartXP, Seed.skill(forLevel: band * 10 + 1))
    }

    /// Award XP — the lifetime score that drives levels, plus the weekly score
    /// that drives the league leaderboard.
    func award(xp: Int) { lifetimeXP += xp; weeklyXP += xp }

    /// Award coins — the spendable currency.
    func award(coins amount: Int) { coins += amount }

    /// Record a case finished with the correct diagnosis. Awards a trophy tier
    /// (an achievement) based on the share of the case's reward that was earned.
    /// Coins are awarded only from the case payout (see `award(coins:)`), so the
    /// wallet always matches the amount shown on the outcome screen.
    func recordCaseSolved(_ id: UUID, earned: Int, outOf maxReward: Int) {
        casesSolved += 1
        let ratio = maxReward > 0 ? Double(earned) / Double(maxReward) : 0
        let tier: Int
        if ratio >= 1.0       { gold += 1;   tier = 3 }
        else if ratio >= 0.8  { silver += 1; tier = 2 }
        else                  { bronze += 1; tier = 1 }
        // Record this case's trophy on its Practice card, keeping the best tier.
        caseTrophies[id.uuidString] = Swift.max(caseTrophies[id.uuidString] ?? 0, tier)
    }

    /// The best trophy tier earned for a case (1 bronze … 3 gold), or nil if unsolved.
    func caseTrophyTier(_ id: UUID) -> Int? { caseTrophies[id.uuidString] }

    /// Record that a case was finished (any outcome). Drives league qualification.
    func recordCaseFinished() {
        casesFinished += 1
        refreshForNewDay()            // make sure the week is current before counting
        leagueCasesThisWeek += 1
    }

    /// Cases a trainee must finish this week to enter the league leaderboard.
    static let casesToQualify = 1
    /// True once the user has finished at least one case this league week.
    var qualifiedForLeague: Bool { leagueCasesThisWeek >= Self.casesToQualify }
}

// MARK: - Departments (home list)
struct Department: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    /// Mystery one-liner shown on the Clinical-mode card.
    let teaser: String
    var bronze: Int = 0
    var silver: Int = 0
    var gold: Int = 0
    /// The curated mystery case opened from this department card.
    let caseRef: ClinicalCase
}

/// A skill-rank title derived from the player's level (every 10 levels = next
/// rank): Medical Student → Intern → Resident → … → Super Specialist.
struct SkillRank: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let icon: String
    let color: Color
}

// MARK: - Clinical case
// Codable so admin-uploaded cases can be persisted to disk (see ContentStore).
struct ClinicalCase: Identifiable, Codable {
    var id = UUID()
    let specialty: String
    let patientName: String
    let gender: String
    let age: String
    let chiefComplaint: String
    let infoCards: [InfoCard]
    let tests: [TestOption]
    let diagnosisQuestion: String
    let diagnoses: [DiagnosisOption]
    let treatments: [TreatmentOption]
    let outcomeTitle: String
    let outcomeBody: String
    let xpReward: Int
    /// Optional structured Mentor Insight, unlocked with coins on the answer screen.
    var mentorInsight: MentorInsightContent? = nil
    /// Optional presenting vitals (BP, PR, RR, SpO₂, Temperature, BMI).
    var vitals: Vitals? = nil
    // Presentation fields for the rich case card (all optional with fallbacks).
    var title: String? = nil        // dramatic case title, e.g. "Collapse in the Night"
    var teaser: String? = nil       // narrative hook shown on the card
    var imageName: String? = nil    // hero image asset name (added to the app)
    var difficulty: Int? = nil      // 1 (easy) … 5 (hard) — pips when no label is authored
    /// Authored difficulty label (e.g. "Intern"). Shown in place of the pips.
    var difficultyLabel: String? = nil
    // Case metadata, all optional.
    var occupation: String? = nil       // e.g. "Elementary School Teacher"
    var duration: String? = nil         // of the presenting complaint, e.g. "3 months"
    var setting: String? = nil          // e.g. "Primary Care Clinic (OPD)"
    var guidelineFocus: String? = nil   // e.g. "NHLBI EPR-4 / GINA Guidelines"
    /// If this case came from the server it arrives answer-stripped; this points
    /// back to the row so the attempt can be graded server-side (where the
    /// answers live). `nil` for built-in cases, which carry their own key.
    var remote: RemoteRef? = nil
}

/// Where a server case lives, so we can grade it remotely.
struct RemoteRef: Codable, Equatable {
    var source: String   // "content" (clinical/daily) or "emergency"
    var id: String       // the table row's UUID
}

/// One teaching pearl: the title the player taps, and the note it opens.
struct ClinicalPearl: Codable, Equatable {
    var title: String = ""
    var body: String = ""
    var isEmpty: Bool { title.trimmed.isEmpty && body.trimmed.isEmpty }
}

/// Coin-locked expert teaching attached to a case (shown on the answer screen).
struct MentorInsightContent: Codable, Equatable {
    var reasoning: String = ""            // core clinical insights / expert reasoning
    var differentials: String = ""        // why other diagnoses didn't fit
    var testRationale: String = ""        // test selection rationale
    var treatmentSequencing: String = ""  // treatment priorities & sequencing
    var pearls: [ClinicalPearl] = []      // clinical pearls, one button each

    init(reasoning: String = "", differentials: String = "", testRationale: String = "",
         treatmentSequencing: String = "", pearls: [ClinicalPearl] = []) {
        self.reasoning = reasoning
        self.differentials = differentials
        self.testRationale = testRationale
        self.treatmentSequencing = treatmentSequencing
        self.pearls = pearls
    }

    // Tolerant decoding: every field is optional-with-default, so stored payloads
    // predating a key — or carrying retired ones — still decode cleanly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil) ?? "" }
        reasoning = str(.reasoning)
        differentials = str(.differentials)
        testRationale = str(.testRationale)
        treatmentSequencing = str(.treatmentSequencing)
        // `pearls` was authored as one prose blob before it became a list of
        // titled pearls; a stored blob decodes as a single untitled pearl.
        if let list = ((try? c.decodeIfPresent([ClinicalPearl].self, forKey: .pearls)) ?? nil) {
            pearls = list.filter { !$0.isEmpty }
        } else {
            let blob = str(.pearls)
            pearls = blob.trimmed.isEmpty ? [] : [ClinicalPearl(title: "", body: blob)]
        }
    }

    var isEmpty: Bool {
        [reasoning, differentials, testRationale, treatmentSequencing]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && pearls.isEmpty
    }
    /// The pearls as prose — used where a section needs plain text (the AI's
    /// case context, and pearls carried over from before they had titles).
    var pearlsText: String {
        pearls.map { $0.title.trimmed.isEmpty ? $0.body : "\($0.title): \($0.body)" }
            .joined(separator: "\n")
    }
    /// Non-empty (title, body) sections in display order.
    var sections: [(String, String)] {
        [("Core clinical insights", reasoning), ("Why other diagnoses didn't fit", differentials),
         ("Test selection rationale", testRationale), ("Treatment priorities & sequencing", treatmentSequencing),
         ("Clinical pearls", pearlsText)]
            .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

extension ClinicalCase {
    /// Card title — the authored title, else the chief complaint.
    var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return chiefComplaint
    }
    /// Card narrative — the authored teaser, else a one-line patient summary.
    var displayTeaser: String {
        if let t = teaser?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return "\(patientName), \(age) — \(chiefComplaint)"
    }
    /// Difficulty 1…5 (defaults to a middle 3).
    var difficultyLevel: Int { Swift.min(5, Swift.max(1, difficulty ?? 3)) }

    /// The hero illustration for this case — the authored `imageName` if set,
    /// else a bundled illustration whose depicted patient matches this case's
    /// gender and age (a young woman's case shows a young woman, a child's shows
    /// a child, …). Stable per case, so the same case always shows the same one.
    var heroImageName: String {
        if let n = imageName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        let candidates = Self.imageCandidates(gender: gender, age: age)
        var h: UInt64 = 1469598103934665603
        for b in (specialty + "|" + patientName + "|" + chiefComplaint).utf8 {
            h = (h ^ UInt64(b)) &* 1099511628211
        }
        return "case-img-\(candidates[Int(h % UInt64(candidates.count))])"
    }

    /// Illustration numbers (case-img-N) whose depicted patient roughly matches
    /// the given gender + age. The bundled images depict, in order:
    /// 1,11 young woman · 2 elderly man · 3,4 mother+baby · 5 elderly woman ·
    /// 6 boy · 7 girl · 8 adult man · 9 surgery (adult) · 10 surgery (elderly man).
    static func imageCandidates(gender: String, age: String) -> [Int] {
        let g = gender.lowercased()
        let female = g.hasPrefix("f")
        let male = g.hasPrefix("m")
        let a = age.lowercased()
        let group: Int   // 0 = baby, 1 = child, 2 = adult, 3 = elderly
        if a.contains("week") || a.contains("month") || a.contains("day") {
            group = 0
        } else {
            let digits = a.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
            let n = Int(digits) ?? 30
            group = n <= 1 ? 0 : (n < 13 ? 1 : (n < 60 ? 2 : 3))
        }
        switch group {
        case 0:  return [3, 4]                                              // baby / infant
        case 1:  return female ? [7] : (male ? [6] : [6, 7])               // child
        case 2:  return female ? [1, 11] : (male ? [8, 9] : [1, 8, 9, 11]) // adult
        default: return female ? [5] : (male ? [2, 10] : [2, 5, 10])       // elderly
        }
    }

    /// Info arranged into the standard clinical reading order regardless
    /// of how they were authored: chief complaint → history → physical
    /// examination → anything else (kept in its original relative order).
    var orderedInfoCards: [InfoCard] {
        func rank(_ c: InfoCard) -> Int {
            let t = c.title.lowercased()
            if t.contains("complaint") || t.contains("basic info")
                || t.contains("presenting") || t.contains("presentation") { return 0 }
            if t.contains("history") || t.contains("hx") { return 1 }
            if t.contains("exam") { return 2 }
            return 3
        }
        return infoCards.enumerated()
            .sorted { a, b in
                let ra = rank(a.element), rb = rank(b.element)
                return ra == rb ? a.offset < b.offset : ra < rb
            }
            .map(\.element)
    }
}

struct InfoCard: Identifiable, Codable {
    var id = UUID()
    let title: String
    let bullets: [String]
    let mentor: String
    /// Optional system-grouped findings (e.g. physical exam): each renders as a
    /// heading with its findings as sub-points, alongside any flat `bullets`.
    var groups: [InfoGroup] = []
}

/// A named group of findings inside an info card (e.g. "Respiratory").
struct InfoGroup: Identifiable, Codable, Equatable {
    var id = UUID()
    let system: String
    let findings: [String]

    enum CodingKeys: String, CodingKey { case system, findings }
}

/// Presenting vitals shown on the first case page.
struct Vitals: Codable, Equatable {
    var bp: String = ""
    var pr: String = ""
    var rr: String = ""
    var spo2: String = ""
    var temperature: String = ""
    var bmi: String = ""

    var isEmpty: Bool { pairs.isEmpty }
    /// Non-empty (label, value) pairs in display order.
    var pairs: [(String, String)] {
        [("BP", bp), ("PR", pr), ("RR", rr), ("SpO₂", spo2), ("Temp", temperature), ("BMI", bmi)]
            .filter { !$0.1.trimmed.isEmpty }
    }
}

struct TestOption: Identifiable, Equatable, Codable {
    var id = UUID()
    let category: String
    let name: String
    let result: String
    let helpful: Bool          // drives mentor feedback
    let mentor: String
    /// Optional result image (e.g. an ECG strip or chest X-ray), shown under the
    /// result text. A public URL; empty keeps the plain text-only layout.
    var imageURL: String = ""
    /// Why this test was (in)appropriate here — revealed on the answer screen.
    /// Part of the answer key: stripped from the case until it's been graded.
    var rationale: String = ""
    /// Short label for the role this option plays (e.g. "Definitive /
    /// Segregation Test", "COPD/Emphysema Distractor"), used as the heading of
    /// its rationale. Optional, and an answer: stripped until graded.
    var tag: String = ""
    static func == (l: TestOption, r: TestOption) -> Bool { l.id == r.id }
}

struct DiagnosisOption: Identifiable, Codable {
    var id = UUID()
    let name: String
    let correct: Bool
    /// Why this diagnosis did or didn't fit — revealed on the answer screen.
    /// Part of the answer key: stripped from the case until it's been graded.
    var rationale: String = ""
    /// Short label for the role it plays (e.g. "Definitive Diagnosis"), used as
    /// the heading of its rationale. Optional, and an answer: stripped too.
    var tag: String = ""
}

struct TreatmentOption: Identifiable, Equatable, Codable {
    var id = UUID()
    let category: String
    let name: String
    let appropriate: Bool
    /// Optional grey "dose • frequency • duration" line shown under the name
    /// while choosing. Neutral prescribing info, not an answer — present before
    /// grading. Any/all of the three • parts may be absent (or the whole line).
    var dosing: String = ""
    /// Why this treatment was (in)appropriate here — revealed on the answer
    /// screen. Part of the answer key: stripped until the case has been graded.
    var rationale: String = ""
    /// Short label for the role this option plays, used as the heading of its
    /// rationale. Optional, and an answer: stripped until graded.
    var tag: String = ""
    static func == (l: TreatmentOption, r: TreatmentOption) -> Bool { l.id == r.id }
}

// MARK: - Per-case progress while playing
@MainActor
final class CaseSession: ObservableObject {
    /// The case being played. For server cases this starts answer-stripped and
    /// is replaced with the full (answer-bearing) case once it's been graded.
    @Published private(set) var clinicalCase: ClinicalCase
    @Published var tray: [TestOption] = []
    @Published var pickedDiagnosis: DiagnosisOption?
    @Published var treatmentTray: [TreatmentOption] = []
    /// The in-case hints the player has tapped to reveal (Pro). Kept on the
    /// session so a hint stays open as pages come and go, and so narration only
    /// reads what's actually on screen.
    @Published var revealedMentorHints: Set<String> = []
    /// Server cases are scored remotely; this flips true once the result is in
    /// (or grading failed). The outcome screen waits on it before revealing.
    @Published private(set) var revealed = false
    /// Server grading requires a signed-in player; set when the outcome is
    /// reached without a session, so the outcome screen can prompt sign-in.
    @Published private(set) var needsSignIn = false
    /// A human-readable reason grading failed (e.g. rate-limited, case not found),
    /// so the outcome screen can explain instead of showing a blank 0-XP result.
    @Published private(set) var gradeError: String?

    /// True when the case carries its own answer key (built-in/seed cases).
    /// Server cases arrive stripped of answers and are graded remotely instead.
    var hasLocalKey: Bool { clinicalCase.diagnoses.contains { $0.correct } }

    /// Server-authoritative reward, set when a remote case is graded.
    private var serverXP: Int?
    private var serverCoins: Int?

    // MARK: Display order
    //
    // The pick lists, shuffled once per play so no two players are asked the
    // same arrangement. Tests and treatments shuffle only *within* a category,
    // leaving the authored headings and their order untouched.
    //
    // `clinicalCase` itself is never reordered: grading addresses options by
    // their authored index, so these are strictly a display concern. They hold
    // the same option values (same ids), so picks map back correctly.
    @Published private(set) var shuffledTests: [TestOption] = []
    @Published private(set) var shuffledTreatments: [TreatmentOption] = []
    @Published private(set) var shuffledDiagnoses: [DiagnosisOption] = []

    init(_ c: ClinicalCase) {
        self.clinicalCase = c
        makeDisplayOrder()
    }

    /// Re-roll the display order for the current case. Called once per session,
    /// and again when a graded case replaces the stripped one.
    private func makeDisplayOrder() {
        shuffledTests      = Self.shuffledWithinCategory(clinicalCase.tests, by: \.category)
        shuffledTreatments = Self.shuffledWithinCategory(clinicalCase.treatments, by: \.category)
        shuffledDiagnoses  = clinicalCase.diagnoses.shuffled()
    }

    /// Shuffle the options inside each category, keeping the categories
    /// themselves in the order the author wrote them.
    private static func shuffledWithinCategory<T>(_ items: [T], by category: KeyPath<T, String>) -> [T] {
        var order: [String] = []
        var byCategory: [String: [T]] = [:]
        for item in items {
            let key = item[keyPath: category]
            if byCategory[key] == nil { order.append(key) }
            byCategory[key, default: []].append(item)
        }
        return order.flatMap { byCategory[$0]!.shuffled() }
    }

    var diagnosisCorrect: Bool { pickedDiagnosis?.correct ?? false }

    // MARK: Scoring — Dynamic Pro-Rata Valuation
    //
    // Out of 100: the diagnosis is worth a flat 35, and the remaining 65 is
    // split pro-rata across every correct investigation and treatment the case
    // defines. Each correct pick earns that per-item value (VC); a wrong pick
    // costs half a VC; each recommended item left un-picked costs 0.25·VC.
    // Investigations and treatments are each floored at 0 before summing, so a
    // wasteful tray never drags the total negative. Must stay in lock-step with
    // the server's grade_case() in supabase/setup_all.sql.

    /// Flat award for naming the right diagnosis.
    nonisolated static let diagnosisPoints = 35.0
    /// Split pro-rata across the case's correct investigations + treatments.
    /// `diagnosisPoints + itemPool` is the 100-point maximum.
    nonisolated static let itemPool = 65.0
    /// A wrong pick costs this fraction of one correct pick's value.
    nonisolated static let wrongPickPenalty = 0.5
    /// A recommended item left un-picked costs this fraction.
    nonisolated static let omissionPenalty = 0.25

    /// Correct investigations (helpful tests) + correct treatments — the
    /// pro-rata denominator.
    private var correctItemCount: Int {
        clinicalCase.tests.filter(\.helpful).count + clinicalCase.treatments.filter(\.appropriate).count
    }
    /// Value of one correct clinical decision: the item pool split evenly.
    private var itemValue: Double {
        let n = correctItemCount
        return n > 0 ? Self.itemPool / Double(n) : 0
    }

    /// Diagnosis — flat and all-or-nothing.
    var diagnosisScore: Double { diagnosisCorrect ? Self.diagnosisPoints : 0.0 }

    /// Investigations — floored at 0.
    var investigationScore: Double {
        let vc = itemValue
        var raw = 0.0
        for t in tray { raw += t.helpful ? vc : -Self.wrongPickPenalty * vc }
        let picked = Set(tray.map(\.id))
        for t in clinicalCase.tests where t.helpful && !picked.contains(t.id) {
            raw -= Self.omissionPenalty * vc
        }
        return Swift.max(0, raw)
    }

    /// Treatments — floored at 0.
    var treatmentScore: Double {
        let vc = itemValue
        var raw = 0.0
        for t in treatmentTray { raw += t.appropriate ? vc : -Self.wrongPickPenalty * vc }
        let picked = Set(treatmentTray.map(\.id))
        for t in clinicalCase.treatments where t.appropriate && !picked.contains(t.id) {
            raw -= Self.omissionPenalty * vc
        }
        return Swift.max(0, raw)
    }

    /// Raw final score, 0...100 (each category floored, then summed).
    var rawScore: Double { diagnosisScore + investigationScore + treatmentScore }

    /// Workup quality for this attempt, 0...1 — drives the coin reward.
    var performance: Double { Swift.min(1.0, Swift.max(0.0, rawScore / 100.0)) }

    /// XP for this attempt — out of a fixed 100. Round half-up, then clamp.
    static let maxXP = 100
    /// Minimum XP for an attempt to count the case as "solved" (and stop it
    /// reappearing). Below this it stays unsolved.
    static let solvedXP = 25
    var earnedXP: Int { serverXP ?? Swift.min(100, Swift.max(0, Int(rawScore.rounded()))) }

    /// Whether this attempt solves the case — scored at least `solvedXP`.
    var solved: Bool { earnedXP >= Self.solvedXP }

    /// Coins for this attempt — scale with the case's own reward value.
    var earnedCoins: Int { serverCoins ?? Int((performance * Double(clinicalCase.xpReward)).rounded()) }

    // MARK: Server-side grading (answers never ship to the device)

    /// The picked options as array indices into the played (stripped) case —
    /// these line up with the server's stored arrays because stripping keeps
    /// option order intact.
    /// The player's picks captured both as array indices (legacy) and as option
    /// NAMES. Grading matches by name, so a case that was edited or reordered
    /// after it loaded still scores correctly.
    struct Picks {
        var testIdx: [Int]; var dxIdx: Int?; var txIdx: [Int]
        var testNames: [String]; var dxName: String?; var txNames: [String]
    }
    private func gatherPicks() -> Picks {
        // Indices stay parallel to the name arrays (use -1 when not found), so the
        // review re-map can zip them safely; the server ignores negative indices.
        Picks(testIdx: tray.map { p in clinicalCase.tests.firstIndex { $0.id == p.id } ?? -1 },
              dxIdx: pickedDiagnosis.flatMap { p in clinicalCase.diagnoses.firstIndex { $0.id == p.id } },
              txIdx: treatmentTray.map { p in clinicalCase.treatments.firstIndex { $0.id == p.id } ?? -1 },
              testNames: tray.map(\.name),
              dxName: pickedDiagnosis?.name,
              txNames: treatmentTray.map(\.name))
    }

    /// Grade a server case: submit the picks, get back the score and the full
    /// (answer-bearing) case, then reveal it so the outcome screen renders as
    /// usual. Grading needs a signed-in player (the server enforces this); if
    /// there's no session we ask the outcome screen to prompt sign-in instead of
    /// revealing. Marks `revealed` on success/failure so the flow never hangs.
    func gradeRemotely() async {
        guard let ref = clinicalCase.remote else { revealed = true; return }
        guard SupabaseService.shared.isSignedIn else { needsSignIn = true; return }
        needsSignIn = false
        gradeError = nil
        let picks = gatherPicks()
        let (result, error) = await SupabaseService.shared.gradeCase(
            ref, testIdx: picks.testIdx, dxIdx: picks.dxIdx, txIdx: picks.txIdx,
            testNames: picks.testNames, dxName: picks.dxName, txNames: picks.txNames)
        if let result {
            apply(full: result.fullCase, xp: result.earnedXP, coins: result.earnedCoins, picks: picks)
        } else {
            gradeError = error
        }
        revealed = true
    }

    /// Mark the outcome ready without remote grading (built-in cases, or a case
    /// with neither a local key nor a server ref).
    func markRevealed() { revealed = true }

    /// Swap the stripped case for the graded one and re-map the player's picks
    /// onto the now-complete option objects (so the review screens show ✓/✗).
    private func apply(full: ClinicalCase, xp: Int, coins: Int, picks: Picks) {
        var graded = full
        graded.id = clinicalCase.id          // keep the progress-tracking id stable
        graded.remote = clinicalCase.remote
        // Re-map picks onto the graded (answer-bearing) options BY NAME (falling
        // back to index), so the review ✓/✗ stays correct even if option order
        // changed since load, and never comes back blank.
        tray = zip(picks.testNames, picks.testIdx).compactMap { name, idx in
            graded.tests.first { $0.name == name } ?? (graded.tests.indices.contains(idx) ? graded.tests[idx] : nil)
        }
        pickedDiagnosis = (picks.dxName.flatMap { n in graded.diagnoses.first { $0.name == n } })
            ?? picks.dxIdx.flatMap { graded.diagnoses.indices.contains($0) ? graded.diagnoses[$0] : nil }
        treatmentTray = zip(picks.txNames, picks.txIdx).compactMap { name, idx in
            graded.treatments.first { $0.name == name } ?? (graded.treatments.indices.contains(idx) ? graded.treatments[idx] : nil)
        }
        clinicalCase = graded
        makeDisplayOrder()   // the stripped options are gone; re-order the new ones
        serverXP = xp
        serverCoins = coins
    }
}
