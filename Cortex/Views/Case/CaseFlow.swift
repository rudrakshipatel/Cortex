import SwiftUI

struct CaseFlow: View {
    let clinicalCase: ClinicalCase
    /// Whether finishing this case spends Life (false for Daily & Emergency).
    var consumesLife: Bool = true
    /// Called when the case is finished, with whether the diagnosis was correct.
    var onFinish: ((Bool) -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var app: AppState
    @StateObject private var session: CaseSession
    @ObservedObject private var speech = SpeechManager.shared
    @State private var step: Step = .info
    @State private var showStreak = false
    @State private var showHistory = false
    @State private var showResults = false
    @State private var recorded = false   // ensures grading is kicked off exactly once
    @State private var awarded = false    // ensures rewards are applied exactly once

    enum Step: Int, CaseIterable { case info, tests, results, diagnosis, treatment, outcome }

    init(clinicalCase: ClinicalCase, initialStep: Step = .info,
         consumesLife: Bool = true, onFinish: ((Bool) -> Void)? = nil) {
        self.clinicalCase = clinicalCase
        self.consumesLife = consumesLife
        self.onFinish = onFinish
        let s = CaseSession(clinicalCase)
        if initialStep.rawValue >= Step.outcome.rawValue {
            s.pickedDiagnosis = clinicalCase.diagnoses.first { $0.correct }
        }
        _session = StateObject(wrappedValue: s)
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                header
                Group {
                    switch step {
                    case .info:      InfoStep(session: session) { step = .tests }
                    case .tests:     TestsStep(session: session) { step = .results }
                    case .results:   ResultsStep(session: session, onBack: { step = .tests }) { step = .diagnosis }
                    case .diagnosis: DiagnosisStep(session: session) { step = .treatment }
                    case .treatment: TreatmentStep(session: session) { step = .outcome }
                    case .outcome:   OutcomeStep(session: session) { finish() }
                        .onAppear { recordOutcome() }   // save the moment the outcome is reached
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            .animation(.easeInOut, value: step)
        }
        .overlay(alignment: .bottomLeading) { reviewButtons }
        .sheet(isPresented: $showHistory) {
            ReviewSheet(title: "Patient History") { HistoryReview(clinicalCase: clinicalCase) }
        }
        .sheet(isPresented: $showResults) {
            ReviewSheet(title: "Test Results") { ResultsReview(ordered: session.tray) }
        }
        .fullScreenCover(isPresented: $showStreak) {
            CaseRewardCover(coins: session.earnedCoins) { dismiss() }
        }
        .onChange(of: step) { _, _ in speech.stop() }   // stop narration when the step changes
        // Apply rewards exactly once, the moment the result is known (local cases
        // reveal immediately; server cases after grading / sign-in).
        .onChange(of: session.revealed) { _, rev in if rev { award() } }
        .onDisappear { speech.stop() }
    }

    /// Floating "review" buttons — re-open the history (and results) any time
    /// during the workup, sliding up from the bottom.
    @ViewBuilder private var reviewButtons: some View {
        if step == .tests || step == .results || step == .diagnosis || step == .treatment {
            HStack(spacing: 10) {
                reviewButton("clock.arrow.circlepath") { showHistory = true }
                if step == .diagnosis || step == .treatment {
                    reviewButton("checklist") { showResults = true }
                }
            }
            .padding(.leading, 18).padding(.bottom, 14)
        }
    }
    private func reviewButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold))
                .foregroundStyle(CX.orange).frame(width: 48, height: 48)
                .background(CX.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CX.orange, lineWidth: 2))
                .shadow(color: CX.navy.opacity(0.12), radius: 6, y: 3)
        }.buttonStyle(PressStyle())
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CX.navy).frame(width: 40, height: 40)
                    .background(CX.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Spacer()
            Text(clinicalCase.specialty.uppercased())
                .font(CX.label(13)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(CX.tealButton, in: Capsule())
            Spacer()
            Button { speech.toggle(spokenText) } label: {
                Image(systemName: speech.speaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white).frame(width: 40, height: 40)
                    .background(CX.orangeButton, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    /// Reads the current step's content aloud. Mentor hints are only included
    /// once the user has unlocked them.
    private var spokenText: String {
        let c = clinicalCase
        var parts: [String] = []
        switch step {
        case .info:
            parts.append("\(c.specialty) case.")
            parts.append("Patient \(c.patientName), \(c.age), \(c.gender).")
            parts.append("Chief complaint: \(c.chiefComplaint).")
            for card in c.orderedInfoCards {
                parts.append(card.title + ".")
                parts.append(contentsOf: card.bullets.map { $0 + "." })
            }
        case .tests:
            parts.append("Order the tests you think are needed.")
            parts.append(contentsOf: c.tests.map { "\($0.category): \($0.name)." })
        case .results:
            let ordered = session.tray
            parts.append(ordered.isEmpty ? "No tests ordered." : "Test results.")
            parts.append(contentsOf: ordered.map { "\($0.name): \($0.result)." })
        case .diagnosis:
            parts.append(c.diagnosisQuestion)
            parts.append(contentsOf: c.diagnoses.map { $0.name + "." })
        case .treatment:
            parts.append("Choose the appropriate treatments.")
            parts.append(contentsOf: c.treatments.map { $0.name + "." })
        case .outcome:
            parts.append(session.diagnosisCorrect ? c.outcomeTitle : "Every expert starts here.")
            parts.append(c.outcomeBody)
        }
        if session.mentorUnlocked {
            let hints = c.infoCards.map(\.mentor) + c.tests.map(\.mentor)
            parts.append(contentsOf: hints.filter { !$0.isEmpty }.map { "Mentor insight: \($0)" })
        }
        return parts.joined(separator: " ")
    }

    /// Reach the outcome: for server cases, grade remotely first (the answer key
    /// lives on the server), then apply rewards. For built-in cases, grade
    /// locally and apply immediately. Runs exactly once per case.
    private func recordOutcome() {
        guard !recorded else { return }
        recorded = true
        if session.hasLocalKey || clinicalCase.remote == nil {
            session.markRevealed()           // local key (or nothing to grade) → award via onChange
        } else {
            Task { await session.gradeRemotely() }   // sets `revealed` on success → award via onChange
        }
    }

    /// Persist the (now-known) result so progress survives even if the player
    /// closes the case with ✕ instead of tapping "Continue". Runs once.
    private func award() {
        guard !awarded else { return }
        awarded = true
        app.award(coins: session.earnedCoins)   // spendable currency (scales with case)
        app.award(xp: session.earnedXP)          // lifetime/weekly score, out of 100 max
        if consumesLife { app.spendEnergy(AppState.energyCost(forXP: session.earnedXP)) }
        // A case counts as "solved" only with the correct diagnosis.
        if session.diagnosisCorrect {
            app.recordCaseSolved(clinicalCase.id, earned: session.earnedXP, outOf: CaseSession.maxXP)
            app.markCaseSolved(clinicalCase.id)   // excludes it from "random" forever
            UINotificationFeedbackGenerator().notificationOccurred(.success)   // celebratory haptic
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        app.recordCaseFinished()         // counts toward league qualification
        app.registerDailyActivity()      // advance / reset the day streak
        onFinish?(session.diagnosisCorrect)
    }

    /// "Continue" on the outcome — result is already recorded; show the celebration.
    private func finish() {
        recordOutcome()
        showStreak = true
    }
}

// MARK: - Step 1: Patient info cards
private struct InfoStep: View {
    @ObservedObject var session: CaseSession
    var onNext: () -> Void
    @State private var page = 0
    var cards: [InfoCard] { session.clinicalCase.orderedInfoCards }

    var body: some View {
        VStack(spacing: 14) {
            TabView(selection: $page) {
                ForEach(cards.indices, id: \.self) { i in
                    ScrollView(showsIndicators: false) {
                        infoCard(cards[i], showPatient: i == 0)
                    }.tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Back / forward navigation through the case pages. The last page
            // swaps the forward arrow for a full-width "Order Tests" button.
            HStack(spacing: 12) {
                pageArrow("chevron.left", filled: false, enabled: page > 0) {
                    withAnimation { page = max(0, page - 1) }
                }
                if page >= cards.count - 1 {
                    Button { onNext() } label: {
                        HStack(spacing: 8) {
                            Text("Order Tests").font(CX.heading(18)).foregroundStyle(.white)
                            Image(systemName: "arrow.right").foregroundStyle(.white)
                        }.frame(maxWidth: .infinity).padding(.vertical, 4)
                    }.buttonStyle(PushButtonStyle(face: CX.orange, lip: CX.orangeDark))
                } else {
                    Spacer()
                    PageDots(count: cards.count, index: page)
                    Spacer()
                    pageArrow("chevron.right", filled: false, enabled: true) {
                        withAnimation { page += 1 }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 16)
    }

    /// An orange-outlined square arrow. Filled on the last page to signal
    /// "proceed to tests".
    private func pageArrow(_ icon: String, filled: Bool, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 20, weight: .bold))
                .foregroundStyle(filled ? .white : (enabled ? CX.orange : CX.hairline))
                .frame(width: 54, height: 54)
                .background(filled ? AnyShapeStyle(CX.orange) : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(enabled ? CX.orange : CX.hairline, lineWidth: 2))
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
    }

    private func infoCard(_ c: InfoCard, showPatient: Bool) -> some View {
        VStack(spacing: 14) {
            CXCard {
                VStack(spacing: 16) {
                    Text(c.title).font(CX.heading(22)).foregroundStyle(CX.navy)
                        .multilineTextAlignment(.center)
                    if showPatient {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(CX.tealSoft).frame(height: 140)
                            .overlay(
                                HStack(spacing: 28) {
                                    patientStat("person.fill", "Name", session.clinicalCase.patientName)
                                    patientStat("calendar", "Age", session.clinicalCase.age)
                                    patientStat("staroflife.fill", session.clinicalCase.gender, "")
                                }
                            )
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(c.bullets, id: \.self) { b in
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(CX.navy).frame(width: 7, height: 7).padding(.top, 7)
                                Text(b).font(CX.body(16)).foregroundStyle(CX.navy)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            MentorInsight(session: session, text: c.mentor)
        }
        .padding(.horizontal, 18)
    }

    private func patientStat(_ icon: String, _ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(CX.orange).font(.system(size: 20))
            Text(label).font(CX.label(11)).foregroundStyle(CX.navySoft)
            if !value.isEmpty { Text(value).font(CX.body(15)).foregroundStyle(CX.navy) }
        }
    }
}

// MARK: - Step 2: Order tests
private struct TestsStep: View {
    @ObservedObject var session: CaseSession
    var onNext: () -> Void
    @State private var performing = false
    var tests: [TestOption] { session.clinicalCase.tests }

    /// Tests grouped by category, preserving authored order.
    private var grouped: [(category: String, items: [TestOption])] {
        var order: [String] = []
        var map: [String: [TestOption]] = [:]
        for t in tests {
            if map[t.category] == nil { order.append(t.category) }
            map[t.category, default: []].append(t)
        }
        return order.map { ($0, map[$0]!) }
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    MentorInsight(session: session, text: "Start with quick, high-yield tests — and skip the ones that won't change your plan.")
                    tray
                    ForEach(grouped, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text(categoryEmoji(group.category)).font(.system(size: 20))
                                Text(group.category).font(CX.heading(17)).foregroundStyle(CX.navy)
                            }
                            ForEach(group.items) { t in testRow(t) }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 8)
            }
            CXButton(title: "Review Results") { runTests() }
                .opacity(session.tray.isEmpty ? 0.5 : 1)
                .disabled(session.tray.isEmpty)
                .padding(.horizontal, 18)
        }
        .padding(.bottom, 16)
        .overlay { if performing { performingOverlay } }
    }

    // The order tray — horizontal cards, matching the video's "ADD TO TRAY HERE".
    private var tray: some View {
        VStack(spacing: 8) {
            Text("ADD TO TRAY HERE").font(CX.label(13)).foregroundStyle(CX.orange)
            if session.tray.isEmpty {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white)
                    .frame(height: 92)
                    .overlay(Image(systemName: "plus").font(.system(size: 26, weight: .bold)).foregroundStyle(CX.orange.opacity(0.6)))
                    .padding(.horizontal, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(session.tray) { t in
                            VStack {
                                Text(t.name).font(CX.body(15)).foregroundStyle(CX.navy)
                                    .multilineTextAlignment(.center).lineLimit(2)
                            }
                            .frame(width: 150, height: 84)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 20))
                                    .foregroundStyle(CX.navySoft).padding(6)
                                    .onTapGesture { withAnimation { session.tray.removeAll { $0 == t } } }
                            }
                        }
                    }.padding(.horizontal, 4)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity)
        .background(CX.orangeSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func testRow(_ t: TestOption) -> some View {
        let added = session.tray.contains(t)
        return HStack {
            Text(t.name).font(CX.body(16)).foregroundStyle(CX.navy)
            Spacer()
            Button(added ? "Remove" : "Add to Tray") {
                withAnimation { if added { session.tray.removeAll { $0 == t } } else { session.tray.append(t) } }
            }
            .font(CX.label(14)).foregroundStyle(added ? .white : CX.orange)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(added ? AnyShapeStyle(CX.orangeButton) : AnyShapeStyle(CX.orangeSoft), in: Capsule())
        }
        .padding(14)
        .background(CX.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CX.hairline, lineWidth: 1.5))
    }

    /// Brief "Performing Tests…" animation before the results appear.
    private var performingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                VixClip(anim: .writing, size: 120, fallback: .meditate)
                Text("Performing Tests…").font(CX.heading(18)).foregroundStyle(CX.orange)
            }
            .padding(28)
            .background(CX.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func runTests() {
        performing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            performing = false
            onNext()
        }
    }

    private func categoryEmoji(_ c: String) -> String {
        let l = c.lowercased()
        if l.contains("radiolog") || l.contains("imaging") { return "🩻" }
        if l.contains("microbiolog") || l.contains("infect") { return "🦠" }
        if l.contains("patholog") { return "🔬" }
        if l.contains("cardio") || l.contains("pulmon") { return "🫀" }
        if l.contains("blood") || l.contains("hematolog") || l.contains("lab") || l.contains("biochem") { return "🧪" }
        return "🧫"
    }
}

// MARK: - Step 3: Results
private struct ResultsStep: View {
    @ObservedObject var session: CaseSession
    var onBack: () -> Void
    var onNext: () -> Void
    @State private var page = 0
    // Only the investigations the user actually ordered — no auto-fill.
    var ordered: [TestOption] { session.tray }
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Test Results").font(CX.heading(22)).foregroundStyle(CX.navy)
                Spacer()
                if !ordered.isEmpty {
                    Text("\(page + 1)/\(ordered.count)").font(CX.heading(18)).foregroundStyle(CX.navySoft)
                }
            }.padding(.horizontal, 20)
            if ordered.isEmpty {
                Spacer()
                CXCard {
                    VStack(spacing: 12) {
                        Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(CX.navySoft)
                        Text("No tests ordered").font(CX.heading(18)).foregroundStyle(CX.navy)
                        Text("You didn't add any investigations, so there are no results to review — this will lower your score.")
                            .font(CX.body(15)).foregroundStyle(CX.navySoft)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity).padding(.vertical, 24)
                }.padding(.horizontal, 20)
                Spacer()
            } else {
                TabView(selection: $page) {
                    ForEach(ordered.indices, id: \.self) { i in
                        CXCard {
                            VStack(spacing: 14) {
                                Spacer()
                                Text(ordered[i].name).font(CX.heading(18)).foregroundStyle(CX.teal)
                                Text(ordered[i].result).font(CX.title(24)).foregroundStyle(CX.navy)
                                    .multilineTextAlignment(.center)
                                Spacer()
                                MentorInsight(session: session, text: ordered[i].mentor)
                            }.frame(maxWidth: .infinity, minHeight: 320)
                        }.padding(.horizontal, 20).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            VStack(spacing: 8) {
                Button { onBack() } label: {
                    Text("Perform More Tests").font(CX.heading(16)).foregroundStyle(CX.orange)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CX.orange, lineWidth: 2))
                }.buttonStyle(PressStyle())
                CXButton(title: "Select Diagnosis") { onNext() }
            }.padding(.horizontal, 18)
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Step 4: Diagnosis selection
private struct DiagnosisStep: View {
    @ObservedObject var session: CaseSession
    var onNext: () -> Void
    @State private var picked: DiagnosisOption?
    var body: some View {
        VStack(spacing: 14) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    MentorInsight(session: session, text: "Weigh every clue together — which single diagnosis explains all of them?")
                    HStack {
                        Image(systemName: "lightbulb.fill").foregroundStyle(CX.gold)
                        Text("1 correct option").font(CX.body(15)).foregroundStyle(CX.navySoft)
                    }
                    .padding(.vertical, 12).frame(maxWidth: .infinity)
                    .background(CX.card, in: RoundedRectangle(cornerRadius: 12)).overlay(
                        RoundedRectangle(cornerRadius: 12).stroke(CX.hairline, lineWidth: 1.5))
                    Text(session.clinicalCase.diagnosisQuestion)
                        .font(CX.heading(18)).foregroundStyle(CX.navy)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(session.clinicalCase.diagnoses) { d in
                        Button { withAnimation { picked = d; session.pickedDiagnosis = d } } label: {
                            HStack {
                                Text(d.name).font(CX.body(16)).foregroundStyle(CX.navy)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                // Server cases are graded remotely — don't reveal
                                // correctness here, just show the selection.
                                if let picked, picked.id == d.id {
                                    if session.hasLocalKey {
                                        Image(systemName: d.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(d.correct ? CX.teal : CX.orange)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(CX.teal)
                                    }
                                }
                            }
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(CX.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor(d), lineWidth: 2))
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 8)
            }
            CXButton(title: "Choose Treatments") { onNext() }
                .padding(.horizontal, 18).opacity(picked == nil ? 0.5 : 1).disabled(picked == nil)
        }
        .padding(.bottom, 16)
    }
    private func borderColor(_ d: DiagnosisOption) -> Color {
        guard let picked, picked.id == d.id else { return CX.hairline }
        // For server cases we can't (and shouldn't) show right/wrong yet.
        guard session.hasLocalKey else { return CX.teal }
        return d.correct ? CX.teal : CX.orange
    }
}

// MARK: - Step 5: Treatments
private struct TreatmentStep: View {
    @ObservedObject var session: CaseSession
    var onNext: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    MentorInsight(session: session, text: "Treat the cause first, then support the patient — avoid interventions that add no value.")
                    VStack(spacing: 8) {
                        Text("TREATMENT TRAY").font(CX.label(13)).foregroundStyle(CX.orange)
                        if session.treatmentTray.isEmpty {
                            Text("Add the treatments you'd start")
                                .font(CX.body(14)).foregroundStyle(CX.navySoft)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                        } else {
                            ForEach(session.treatmentTray) { t in
                                HStack {
                                    Text(t.name).font(CX.body(15)).foregroundStyle(CX.navy)
                                    Spacer()
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(CX.navySoft)
                                        .onTapGesture { session.treatmentTray.removeAll { $0 == t } }
                                }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity)
                    .background(CX.orangeSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    ForEach(session.clinicalCase.treatments) { t in
                        let added = session.treatmentTray.contains(t)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.category).font(CX.label(11)).foregroundStyle(CX.teal)
                                Text(t.name).font(CX.body(16)).foregroundStyle(CX.navy)
                            }
                            Spacer()
                            Button(added ? "Remove" : "Add") {
                                if added { session.treatmentTray.removeAll { $0 == t } }
                                else { session.treatmentTray.append(t) }
                            }
                            .font(CX.label(14)).foregroundStyle(added ? CX.navySoft : .white)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(added ? AnyShapeStyle(CX.hairline) : AnyShapeStyle(CX.orangeButton), in: Capsule())
                        }
                        .padding(14)
                        .background(CX.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CX.hairline, lineWidth: 1.5))
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 8)
            }
            CXButton(title: "See Outcomes") { onNext() }
                .opacity(session.treatmentTray.isEmpty ? 0.5 : 1)
                .disabled(session.treatmentTray.isEmpty)
                .padding(.horizontal, 18)
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Step 6: Outcome
private struct OutcomeStep: View {
    @ObservedObject var session: CaseSession
    @EnvironmentObject var app: AppState
    var onDone: () -> Void
    @State private var confirmMentor = false
    @State private var signingIn = false

    private var correct: Bool { session.diagnosisCorrect }

    /// Mapped (icon, color, title, body) learning sections from the case's
    /// structured mentor insight, in the video's display order.
    private var learningSections: [(icon: String, color: Color, title: String, body: String)] {
        guard let mi = session.clinicalCase.mentorInsight else { return [] }
        var out: [(String, Color, String, String)] = []
        func add(_ icon: String, _ color: Color, _ title: String, _ text: String) {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append((icon, color, title, text)) }
        }
        add("questionmark.circle.fill", CX.orange, "How We Landed on the Diagnosis", mi.reasoning)
        add("list.bullet.rectangle.fill", CX.teal, "Differential Diagnoses", mi.differentials)
        add("sparkles", CX.gold, "Clinical Pearls", mi.pearls)
        add("exclamationmark.triangle.fill", CX.orange, "Clinical Traps to Avoid", mi.pitfalls)
        add("graduationcap.fill", CX.teal, "Learning Points", mi.learningPoints)
        return out
    }

    private var challengeText: String {
        let c = session.clinicalCase
        return "I just \(correct ? "solved" : "tackled") a clinical case on Cortex — “\(c.displayTitle)” (\(c.specialty)). Same patient, same clues, same pressure. Think you can beat my score? 🦊🩺"
    }

    var body: some View {
        // Server cases are scored remotely; wait for the result before revealing
        // anything (otherwise the answer/score would flash as a wrong "0").
        if session.revealed || session.hasLocalKey {
            content
        } else if session.needsSignIn {
            signInPrompt
        } else {
            VStack(spacing: 16) {
                Spacer()
                ProgressView().controlSize(.large).tint(CX.teal)
                Text("Scoring your case…").font(CX.heading(18)).foregroundStyle(CX.navySoft)
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Shown when a server case is finished but no player is signed in — grading
    /// happens securely on the server, so we need a session first.
    private var signInPrompt: some View {
        VStack(spacing: 18) {
            Spacer()
            VixClip(anim: .wave, size: 140)
            Text("Sign in to see your score")
                .font(CX.title(22)).foregroundStyle(CX.navy).multilineTextAlignment(.center)
            Text("Cases are graded securely on our server, so you'll need to be signed in to get your result.")
                .font(CX.body(14)).foregroundStyle(CX.navySoft)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            if signingIn {
                ProgressView().controlSize(.large).tint(CX.teal).padding(.top, 6)
            } else {
                VStack(spacing: 12) {
                    signInButton("Sign in with Google", "g.circle.fill", "google")
                    signInButton("Sign in with Apple", "applelogo", "apple")
                }.padding(.horizontal, 32).padding(.top, 6)
            }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func signInButton(_ title: String, _ icon: String, _ provider: String) -> some View {
        Button {
            signingIn = true
            Task {
                _ = try? await SupabaseService.shared.signInWithOAuth(provider: provider)
                await session.gradeRemotely()   // re-grade; reveals on success, re-prompts if cancelled
                signingIn = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon); Text(title).font(CX.heading(16))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14).foregroundStyle(.white)
        }
        .buttonStyle(PushButtonStyle(face: CX.navy, lip: Color.black.opacity(0.4)))
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                // XP earned hero — out of 100 (full marks only for a perfect solve)
                Text("XP earned").font(CX.heading(20)).foregroundStyle(CX.navySoft).padding(.top, 8)
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(session.earnedXP)").font(.system(size: 64, weight: .heavy, design: .rounded))
                            .foregroundStyle(CX.navy)
                        Text("/ \(CaseSession.maxXP)").font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(CX.navySoft)
                    }
                    Image(systemName: "bolt.fill").font(.system(size: 40)).foregroundStyle(CX.teal)
                }.bounceIn()
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill").foregroundStyle(CX.gold)
                    Text("+\(session.earnedCoins) coins").font(CX.label(14)).foregroundStyle(CX.navy)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.white, in: Capsule())
                .overlay(Capsule().stroke(CX.hairline, lineWidth: 1.5))

                badge

                VixClip(anim: VixAnim.forXP(session.earnedXP), size: 168,
                        fallback: correct ? .cheer : .idea).bounceIn(delay: 0.05)
                Text(correct ? session.clinicalCase.outcomeTitle : "Tough case, but real progress starts here")
                    .font(CX.title(26)).foregroundStyle(CX.navy).multilineTextAlignment(.center)
                Text(correct ? session.clinicalCase.outcomeBody
                     : "Mistakes help you build real clinical judgment. Let's take the learnings and move forward stronger.")
                    .font(CX.body(16)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
                    .padding(.horizontal, 4)

                if !correct { wardsWarning }

                // Final diagnosis recap
                CXCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FINAL DIAGNOSIS").font(CX.label(12)).foregroundStyle(CX.navySoft)
                        Text(session.clinicalCase.diagnoses.first(where: \.correct)?.name ?? "—")
                            .font(CX.heading(18)).foregroundStyle(CX.teal)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }

                // Case review — how the player's tests / diagnosis / treatment went
                CaseReviewCard(session: session)

                // Learning breakdown (coin-locked, collapsible)
                if !learningSections.isEmpty {
                    if session.mentorUnlocked {
                        ForEach(Array(learningSections.enumerated()), id: \.offset) { _, sec in
                            CollapsibleInsight(icon: sec.icon, color: sec.color, title: sec.title, text: sec.body)
                        }
                    } else {
                        lockedBreakdown
                    }
                }

                // Share + continue
                ShareLink(item: challengeText) {
                    Text("Challenge Friends").font(CX.heading(16)).foregroundStyle(CX.orange)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CX.orange, lineWidth: 2))
                }
                CXButton(title: "Continue") { onDone() }
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .overlay(alignment: .top) {
            if correct { ConfettiBurst().padding(.top, 50) }
        }
    }

    @ViewBuilder private var badge: some View {
        HStack(spacing: 6) {
            Image(systemName: correct ? "checkmark.seal.fill" : "xmark.circle.fill")
            Text(correct ? "SOLVED" : "NOT SOLVED")
        }
        .font(CX.label(14)).foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(correct ? CX.tealButton : CX.orangeButton, in: Capsule())
        .bounceIn()
    }

    /// Wrong-answer reminder card (matches the video's red-siren note).
    private var wardsWarning: some View {
        CXCard(borderColor: .red.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "light.beacon.max.fill").foregroundStyle(.red)
                    Text("You'll see this case again in the wards.").font(CX.heading(15)).foregroundStyle(CX.navy)
                }
                Text("Guessing won't be acceptable then — learn the reasoning now.")
                    .font(CX.body(14)).foregroundStyle(CX.orange)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Locked teaser for the structured breakdown, unlocked with coins.
    private var lockedBreakdown: some View {
        let canAfford = app.coins >= AppState.mentorCost
        return CXCard(borderColor: CX.orange.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "graduationcap.fill").foregroundStyle(CX.orange)
                    Text("Full Case Breakdown").font(CX.heading(18)).foregroundStyle(CX.navy)
                    Spacer()
                    Image(systemName: "lock.fill").foregroundStyle(CX.navySoft)
                }
                ForEach(Array(learningSections.enumerated()), id: \.offset) { _, sec in
                    HStack(spacing: 8) {
                        Image(systemName: sec.icon).foregroundStyle(sec.color.opacity(0.6))
                        Text(sec.title).font(CX.body(15)).foregroundStyle(CX.navySoft)
                        Spacer()
                    }
                }
                Button { confirmMentor = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: canAfford ? "dollarsign.circle.fill" : "xmark.circle.fill")
                        Text(canAfford ? "Unlock · \(AppState.mentorCost) coins" : "Need \(AppState.mentorCost) coins")
                    }
                    .font(CX.label(14)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(canAfford ? AnyShapeStyle(CX.orangeButton) : AnyShapeStyle(CX.navySoft), in: Capsule())
                }
                .buttonStyle(PressStyle()).disabled(!canAfford)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Unlock the full breakdown?", isPresented: $confirmMentor, titleVisibility: .visible) {
            Button("Unlock for \(AppState.mentorCost) coins") {
                if app.spendCoins(AppState.mentorCost) {
                    withAnimation(.spring(duration: 0.35)) { session.mentorUnlocked = true }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This spends \(AppState.mentorCost) coins (you have \(app.coins)) to reveal the expert teaching for this case.")
        }
    }
}

/// An expandable insight card used on the outcome screen.
private struct CollapsibleInsight: View {
    let icon: String
    let color: Color
    let title: String
    let text: String
    @State private var open = false

    var body: some View {
        CXCard(borderColor: color.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 10) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: icon).foregroundStyle(color)
                        Text(title).font(CX.heading(16)).foregroundStyle(CX.navy)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: open ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .foregroundStyle(CX.navySoft)
                    }
                }
                if open {
                    Text(text).font(CX.body(15)).foregroundStyle(CX.navySoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Case review (tabbed: how the player's tests / dx / tx went)
private struct CaseReviewCard: View {
    @ObservedObject var session: CaseSession
    @State private var tab: Tab = .tests
    enum Tab: String, CaseIterable { case tests = "Tests", diagnosis = "Diagnosis", treatment = "Treatment" }

    private var c: ClinicalCase { session.clinicalCase }

    var body: some View {
        CXCard {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "cross.case.fill").foregroundStyle(CX.navySoft)
                    Text("CASE REVIEW").font(CX.label(13)).foregroundStyle(CX.navySoft)
                }
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Button { withAnimation(.easeInOut(duration: 0.2)) { tab = t } } label: {
                            VStack(spacing: 6) {
                                Text(t.rawValue).font(CX.heading(15))
                                    .foregroundStyle(tab == t ? CX.orange : CX.navySoft)
                                Rectangle().fill(tab == t ? CX.orange : .clear).frame(height: 2)
                            }
                        }.frame(maxWidth: .infinity)
                    }
                }
                Group {
                    switch tab {
                    case .tests:     testsReview
                    case .diagnosis: diagnosisReview
                    case .treatment: treatmentReview
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // Tests: good = ordered & helpful; bad = ordered & not helpful.
    private var testsReview: some View {
        let good = session.tray.filter(\.helpful)
        let bad  = session.tray.filter { !$0.helpful }
        return VStack(alignment: .leading, spacing: 14) {
            reviewGroup(good: true, "Efficient Test Choices", good.map(\.name),
                        empty: "No high-yield tests ordered.")
            if !bad.isEmpty {
                reviewGroup(good: false, "Low-Yield Tests", bad.map(\.name), empty: "")
            }
        }
    }

    private var diagnosisReview: some View {
        let correct = c.diagnoses.first(where: \.correct)?.name ?? "—"
        let picked = session.pickedDiagnosis?.name ?? "No answer"
        return VStack(alignment: .leading, spacing: 14) {
            reviewGroup(good: session.diagnosisCorrect,
                        session.diagnosisCorrect ? "Correct Diagnosis" : "Your Diagnosis",
                        [picked], empty: "")
            if !session.diagnosisCorrect {
                reviewGroup(good: true, "Correct Answer", [correct], empty: "")
            }
        }
    }

    private var treatmentReview: some View {
        let good = session.treatmentTray.filter(\.appropriate)
        let bad  = session.treatmentTray.filter { !$0.appropriate }
        return VStack(alignment: .leading, spacing: 14) {
            reviewGroup(good: true, "Appropriate Treatments", good.map(\.name),
                        empty: "No appropriate treatments selected.")
            if !bad.isEmpty {
                reviewGroup(good: false, "Inappropriate Treatments", bad.map(\.name), empty: "")
            }
        }
    }

    private func reviewGroup(good: Bool, _ title: String, _ items: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: good ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(good ? CX.teal : .red)
                Text(title).font(CX.heading(16)).foregroundStyle(good ? CX.teal : .red)
            }
            if items.isEmpty {
                Text(empty).font(CX.body(14)).foregroundStyle(CX.navySoft)
            } else {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(CX.navy).frame(width: 6, height: 6).padding(.top, 7)
                        Text(item).font(CX.body(15)).foregroundStyle(CX.navy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Post-case celebration (league rank → streak flame → coins earned)
private struct CaseRewardCover: View {
    let coins: Int
    var onDone: () -> Void
    @EnvironmentObject var app: AppState
    @State private var page = 0

    /// The player's current weekly league room (real players), loaded on appear.
    @State private var board: [LeagueEntry] = []
    private var myIndex: Int { board.firstIndex { $0.isYou } ?? 0 }

    /// A fallback "you" row used until the real room loads (or if offline).
    private var youEntry: LeagueEntry {
        var e = LeagueEntry(name: app.displayName, weeklyXP: app.weeklyXP,
                            totalXP: app.lifetimeXP, trophies: app.gold, isYou: true)
        e.rank = 1
        return e
    }

    /// Report this week's score, then pull the real league room to show the rank.
    private func loadLeague() async {
        let week = AppState.gmtWeek()
        await SupabaseService.shared.reportLeague(
            week: week, kind: app.skill.name, weeklyXP: app.weeklyXP,
            totalXP: app.lifetimeXP, trophies: app.gold, username: app.displayName)
        let members = await SupabaseService.shared.fetchLeague(week: week)
        board = Seed.leagueEntries(from: members, youId: SupabaseService.shared.userId)
    }

    var body: some View {
        AppBackground {
            Group {
                switch page {
                case 0:  rankPage
                case 1:  streakPage
                default: coinsPage
                }
            }
            .transition(.opacity)
        }
        .task { await loadLeague() }
    }

    // Page 0 — weekly league position (matches the video's "Rank up complete").
    private var rankPage: some View {
        let me = board.indices.contains(myIndex) ? board[myIndex] : youEntry
        let below = myIndex + 1 < board.count ? board[myIndex + 1] : nil
        let mid = Seed.leagueSize - Seed.leaguePromotionCount - Seed.leagueDemotionCount
        return VStack(spacing: 16) {
            Spacer(minLength: 8)
            VixClip(anim: .confetti, size: 150, fallback: .cheer).bounceIn()
            VStack(spacing: 10) {
                rankRow(me, highlighted: true).bounceIn()
                if let below { rankRow(below, highlighted: false) }
            }
            Spacer(minLength: 8)
            Text(me.rank <= Seed.leaguePromotionCount ? "You're in the promotion zone!" : "Climbing the league")
                .font(CX.title(26)).foregroundStyle(CX.navy).multilineTextAlignment(.center)
            Text("Current position #\(me.rank)").font(CX.heading(18)).foregroundStyle(CX.navySoft)
            CXCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            ruleLine("Each league has \(Seed.leagueSize) players. Your rank is based on the XP you earn from cases.")
                            ruleLine("Every Monday, the top \(Seed.leaguePromotionCount) are promoted, the middle \(mid) stay, and the bottom \(Seed.leagueDemotionCount) are demoted.")
                            ruleLine("Weekly Rewards: Top 3 earn \(Seed.leagueTopThreeReward) coins, promotion zone \(Seed.leaguePromotionReward), and safe zone \(Seed.leagueSafeReward).")
                        }
                        VixClip(anim: .tail, size: 76, fallback: .idea)
                    }
                }
            }
            Spacer(minLength: 8)
            CXButton(title: "I'll take the next case") { withAnimation { page = 1 } }
        }
        .padding(.horizontal, 20).padding(.bottom, 24)
        .overlay(alignment: .top) { ConfettiBurst().padding(.top, 30) }
    }

    private func rankRow(_ e: LeagueEntry, highlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(e.rank)").font(CX.heading(18)).foregroundStyle(CX.navy).frame(width: 28)
            ZStack {
                Circle().fill((highlighted ? CX.orange : CX.teal).opacity(0.18)).frame(width: 38, height: 38)
                Image(systemName: "pawprint.fill").font(.system(size: 18)).foregroundStyle(highlighted ? CX.orange : CX.teal)
            }
            Text(e.name).font(CX.heading(16)).foregroundStyle(CX.navy).lineLimit(1)
            Spacer()
            Text("\(e.weeklyXP)").font(CX.heading(17)).foregroundStyle(CX.teal)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(highlighted ? CX.orange : CX.hairline, lineWidth: highlighted ? 2.5 : 1.5))
    }

    private func ruleLine(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(CX.teal)
            Text(t).font(CX.body(14)).foregroundStyle(CX.navySoft).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var streakPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "flame.fill").font(.system(size: 120))
                .foregroundStyle(LinearGradient(colors: [.orange, CX.gold], startPoint: .top, endPoint: .bottom))
                .bounceIn()
            Text("\(app.streak) DAY STREAK").font(CX.title(32)).foregroundStyle(CX.navySoft)
            Text("Solve a case every day to keep the flame alive.")
                .font(CX.body(16)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
            Spacer()
            CXButton(title: "Continue") { withAnimation { page = 2 } }
        }
        .padding(.horizontal, 22).padding(.bottom, 24)
    }

    private var coinsPage: some View {
        VStack(spacing: 18) {
            Spacer()
            VixClip(anim: .tail, size: 190, fallback: .cheer).bounceIn()
            Text("You've earned \(coins) coins!").font(CX.title(30)).foregroundStyle(CX.navySoft)
                .multilineTextAlignment(.center)
            CXCard {
                VStack(alignment: .leading, spacing: 10) {
                    rewardBullet("Coins are your in-game currency")
                    rewardBullet("Use them to buy Streak Freezes or unlock breakdowns")
                    rewardBullet("Keep playing, keep earning")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            CXButton(title: "Back to Ward") { onDone() }
        }
        .padding(.horizontal, 22).padding(.bottom, 24)
        .overlay(alignment: .top) { ConfettiBurst().padding(.top, 40) }
    }

    private func rewardBullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(CX.teal)
            Text(t).font(CX.body(15)).foregroundStyle(CX.navySoft).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Review sheets (slide up from the bottom for reference)

/// A titled bottom sheet used to re-show the history / results without losing
/// your place in the case.
struct ReviewSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                HStack {
                    Text(title).font(CX.title(22)).foregroundStyle(CX.navy)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(CX.navySoft)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)
                ScrollView(showsIndicators: false) {
                    content.padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Patient demographics + the case info pages (Chief Complaint → History → Exam).
private struct HistoryReview: View {
    let clinicalCase: ClinicalCase
    var body: some View {
        VStack(spacing: 14) {
            CXCard {
                HStack(spacing: 16) {
                    stat("person.fill", "Name", clinicalCase.patientName)
                    stat("calendar", "Age", clinicalCase.age)
                    stat("staroflife.fill", "Sex", clinicalCase.gender)
                }
            }
            ForEach(clinicalCase.orderedInfoCards) { card in
                CXCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(card.title).font(CX.heading(18)).foregroundStyle(CX.teal)
                        ForEach(card.bullets, id: \.self) { b in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(CX.navy).frame(width: 6, height: 6).padding(.top, 7)
                                Text(b).font(CX.body(15)).foregroundStyle(CX.navy)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    private func stat(_ icon: String, _ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).foregroundStyle(CX.orange)
            Text(value).font(CX.body(15)).foregroundStyle(CX.navy)
            Text(label).font(CX.label(11)).foregroundStyle(CX.navySoft)
        }.frame(maxWidth: .infinity)
    }
}

/// The results of the investigations the user ordered.
private struct ResultsReview: View {
    let ordered: [TestOption]
    var body: some View {
        if ordered.isEmpty {
            CXCard {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 34)).foregroundStyle(CX.navySoft)
                    Text("No tests ordered").font(CX.heading(17)).foregroundStyle(CX.navy)
                    Text("You didn't add any investigations for this case.")
                        .font(CX.body(14)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 16)
            }
        } else {
            VStack(spacing: 12) {
                ForEach(ordered) { t in
                    CXCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.name).font(CX.heading(16)).foregroundStyle(CX.teal)
                            Text(t.result).font(CX.body(16)).foregroundStyle(CX.navy)
                                .fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}
