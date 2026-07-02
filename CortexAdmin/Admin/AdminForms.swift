import SwiftUI

// MARK: - Clinical case form

struct ClinicalCaseForm: View {
    @EnvironmentObject var store: ContentStore
    @Environment(\.dismiss) private var dismiss
    let editing: ClinicalCase?
    @State private var draft: CaseDraft

    init(editing: ClinicalCase? = nil) {
        self.editing = editing
        _draft = State(initialValue: editing.map(CaseDraft.init(from:)) ?? CaseDraft())
    }

    var body: some View {
        CaseEditor(draft: $draft)
            .navigationTitle(editing == nil ? "New Clinical Case" : "Edit Clinical Case")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var c = draft.build()
                        if let editing { c.id = editing.id; store.updateClinical(c) }
                        else { store.addClinical(c) }
                        dismiss()
                    }.fontWeight(.semibold).disabled(!draft.isValid)
                }
            }
    }
}

// MARK: - Daily case form (same format as a clinical case)

struct DailyCaseForm: View {
    @EnvironmentObject var store: ContentStore
    @Environment(\.dismiss) private var dismiss
    let editing: DailyCase?
    @State private var draft: CaseDraft
    @State private var date: Date

    init(editing: DailyCase? = nil) {
        self.editing = editing
        _draft = State(initialValue: editing.map { CaseDraft(from: $0.clinicalCase) } ?? CaseDraft())
        _date = State(initialValue: editing?.date ?? Date())
    }

    var body: some View {
        CaseEditor(draft: $draft, header: {
            Section {
                DatePicker("Appears on", selection: $date, displayedComponents: [.date])
            } header: {
                Text("Daily date")
            } footer: {
                Text("This case is the Daily Case on this calendar day (GMT).")
            }
        })
        .navigationTitle(editing == nil ? "New Daily Case" : "Edit Daily Case")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    let c = draft.build()
                    if let editing {
                        store.updateDaily(DailyCase(id: editing.id, clinicalCase: c, date: date))
                    } else {
                        store.addDaily(DailyCase(clinicalCase: c, date: date))
                    }
                    dismiss()
                }.fontWeight(.semibold).disabled(!draft.isValid)
            }
        }
    }
}

// MARK: - Shared case editor

/// A reusable form that edits a `CaseDraft`. Used by both the clinical-case and
/// emergency forms so the full case-authoring UI lives in one place.
struct CaseEditor<Header: View>: View {
    @Binding var draft: CaseDraft
    @ViewBuilder var header: Header

    init(draft: Binding<CaseDraft>, @ViewBuilder header: () -> Header = { EmptyView() }) {
        self._draft = draft
        self.header = header()
    }

    var body: some View {
        Form {
            header

            Section("Patient") {
                TextField("Specialty (e.g. Endocrinology)", text: $draft.specialty)
                TextField("Patient name", text: $draft.patientName)
                Picker("Gender", selection: $draft.gender) {
                    ForEach(["Female", "Male", "Other"], id: \.self) { Text($0) }
                }
                TextField("Age (e.g. 45 Y)", text: $draft.age)
                TextField("Chief complaint", text: $draft.chiefComplaint, axis: .vertical).lineLimit(1...3)
            }

            Section {
                TextField("Title (e.g. Collapse in the Night)", text: $draft.cardTitle)
                TextField("Teaser / narrative hook", text: $draft.cardTeaser, axis: .vertical).lineLimit(1...4)
                TextField("Hero image asset name", text: $draft.cardImage)
                Stepper("Difficulty: \(draft.cardDifficulty)/5", value: $draft.cardDifficulty, in: 1...5)
            } header: {
                Text("Case card (optional)")
            } footer: {
                Text("Shown on the Home card. Add an image to the app's asset catalog and enter its name here; leave blank for a default banner.")
            }

            Section {
                TextField("Presentation — one bullet per line", text: $draft.chiefCard.bulletsText, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Mentor insight (optional)", text: $draft.chiefCard.mentor, axis: .vertical).lineLimit(1...4)
            } header: { Text("1. Chief Complaint") }

            Section {
                TextField("History — one bullet per line", text: $draft.historyCard.bulletsText, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Mentor insight (optional)", text: $draft.historyCard.mentor, axis: .vertical).lineLimit(1...4)
            } header: { Text("2. History") }

            Section {
                TextField("Exam findings — one bullet per line", text: $draft.examCard.bulletsText, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Mentor insight (optional)", text: $draft.examCard.mentor, axis: .vertical).lineLimit(1...4)
            } header: { Text("3. Physical Examination") }

            ForEach($draft.tests) { $t in
                Section("Test") {
                    TextField("Category (e.g. Hematology)", text: $t.category)
                    TextField("Test name", text: $t.name)
                    TextField("Result", text: $t.result)
                    Toggle("Helpful / high-yield", isOn: $t.helpful)
                    TextField("Mentor note", text: $t.mentor, axis: .vertical).lineLimit(1...3)
                }
            }
            addRemoveRow("test", count: draft.tests.count,
                         add: { draft.tests.append(.init()) },
                         remove: { if draft.tests.count > 1 { draft.tests.removeLast() } })

            Section("Diagnosis · tap the circle to mark the correct one") {
                TextField("Diagnosis question", text: $draft.diagnosisQuestion, axis: .vertical).lineLimit(1...3)
                ForEach(draft.diagnoses.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        Button { draft.setCorrectDiagnosis(i) } label: {
                            Image(systemName: draft.diagnoses[i].correct ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(draft.diagnoses[i].correct ? CX.teal : .secondary)
                        }
                        .buttonStyle(.plain)
                        TextField("Diagnosis \(i + 1)", text: $draft.diagnoses[i].name)
                    }
                }
            }
            addRemoveRow("diagnosis", count: draft.diagnoses.count,
                         add: { draft.diagnoses.append(.init()) },
                         remove: { if draft.diagnoses.count > 2 { draft.diagnoses.removeLast() } })

            ForEach($draft.treatments) { $t in
                Section("Treatment") {
                    TextField("Category (e.g. Medications)", text: $t.category)
                    TextField("Treatment name", text: $t.name)
                    Toggle("Appropriate", isOn: $t.appropriate)
                }
            }
            addRemoveRow("treatment", count: draft.treatments.count,
                         add: { draft.treatments.append(.init()) },
                         remove: { if draft.treatments.count > 1 { draft.treatments.removeLast() } })

            Section("Outcome") {
                TextField("Outcome title (e.g. Sharp call, Doctor!)", text: $draft.outcomeTitle)
                TextField("Outcome explanation", text: $draft.outcomeBody, axis: .vertical).lineLimit(2...6)
                Stepper("Coin reward: \(draft.xp)", value: $draft.xp, in: 5...100, step: 1)
            }

            Section {
                TextField("Core clinical insights", text: $draft.mReasoning, axis: .vertical).lineLimit(2...6)
                TextField("Why other diagnoses didn't fit", text: $draft.mDifferentials, axis: .vertical).lineLimit(2...6)
                TextField("Test selection rationale", text: $draft.mTestRationale, axis: .vertical).lineLimit(2...6)
                TextField("Treatment priorities & sequencing", text: $draft.mTreatmentSequencing, axis: .vertical).lineLimit(2...6)
                TextField("Clinical pearls", text: $draft.mPearls, axis: .vertical).lineLimit(2...6)
                TextField("Clinical traps to avoid", text: $draft.mPitfalls, axis: .vertical).lineLimit(2...6)
                TextField("Learning points", text: $draft.mLearning, axis: .vertical).lineLimit(2...6)
            } header: {
                Text("Mentor Insight (coin-locked)")
            } footer: {
                Text("Optional. Leave blank to omit. Shown on the answer screen once the user unlocks it with coins.")
            }
        }
    }

    private func addRemoveRow(_ noun: String, count: Int,
                              add: @escaping () -> Void, remove: @escaping () -> Void) -> some View {
        Section {
            HStack {
                Button { add() } label: { Label("Add \(noun)", systemImage: "plus.circle.fill") }
                Spacer()
                Button(role: .destructive) { remove() } label: {
                    Label("Remove last", systemImage: "minus.circle")
                }.disabled(count <= minCount(noun))
            }
            .font(.subheadline)
        }
    }
    private func minCount(_ noun: String) -> Int { noun == "diagnosis" ? 2 : 1 }
}

// MARK: - Editable drafts

struct CaseDraft {
    var specialty = ""
    var patientName = ""
    var gender = "Female"
    var age = ""
    var chiefComplaint = ""
    // Card presentation (optional)
    var cardTitle = ""
    var cardTeaser = ""
    var cardImage = ""
    var cardDifficulty = 3
    // Fixed clinical sections — every case follows: Chief Complaint → History →
    // Physical Examination (then Tests → Diagnoses → Treatments → Outcome).
    var chiefCard = InfoCardDraft(title: "Chief Complaint")
    var historyCard = InfoCardDraft(title: "History")
    var examCard = InfoCardDraft(title: "Physical Examination")
    var tests: [TestDraft] = [TestDraft(helpful: true), TestDraft()]
    var diagnosisQuestion = "Which diagnosis best fits this presentation?"
    var diagnoses: [DiagnosisDraft] = [DiagnosisDraft(correct: true), DiagnosisDraft()]
    var treatments: [TreatmentDraft] = [TreatmentDraft(appropriate: true), TreatmentDraft()]
    var outcomeTitle = ""
    var outcomeBody = ""
    var xp = 20
    // Mentor Insight (coin-locked teaching shown on the answer screen)
    var mReasoning = ""
    var mDifferentials = ""
    var mTestRationale = ""
    var mTreatmentSequencing = ""
    var mPearls = ""
    var mPitfalls = ""
    var mLearning = ""

    init() {}

    /// Prefill the editor from an existing case (for editing).
    init(from c: ClinicalCase) {
        specialty = c.specialty
        patientName = c.patientName
        gender = ["Female", "Male", "Other"].contains(c.gender) ? c.gender : "Other"
        age = c.age
        chiefComplaint = c.chiefComplaint
        cardTitle = c.title ?? ""; cardTeaser = c.teaser ?? ""
        cardImage = c.imageName ?? ""; cardDifficulty = c.difficulty ?? 3
        // Bucket existing info cards into the three fixed sections by title.
        for card in c.infoCards {
            let bullets = card.bullets.joined(separator: "\n")
            let t = card.title.lowercased()
            if t.contains("history") || t.contains("hx") {
                historyCard.bulletsText = bullets; historyCard.mentor = card.mentor
            } else if t.contains("exam") {
                examCard.bulletsText = bullets; examCard.mentor = card.mentor
            } else {
                chiefCard.bulletsText = bullets; chiefCard.mentor = card.mentor
            }
        }
        tests = c.tests.map {
            TestDraft(category: $0.category, name: $0.name, result: $0.result, helpful: $0.helpful, mentor: $0.mentor)
        }
        if tests.isEmpty { tests = [TestDraft()] }
        diagnosisQuestion = c.diagnosisQuestion
        diagnoses = c.diagnoses.map { DiagnosisDraft(name: $0.name, correct: $0.correct) }
        while diagnoses.count < 2 { diagnoses.append(DiagnosisDraft()) }
        treatments = c.treatments.map {
            TreatmentDraft(category: $0.category, name: $0.name, appropriate: $0.appropriate)
        }
        if treatments.isEmpty { treatments = [TreatmentDraft()] }
        outcomeTitle = c.outcomeTitle
        outcomeBody = c.outcomeBody
        xp = c.xpReward
        if let mi = c.mentorInsight {
            mReasoning = mi.reasoning; mDifferentials = mi.differentials
            mTestRationale = mi.testRationale; mTreatmentSequencing = mi.treatmentSequencing
            mPearls = mi.pearls; mPitfalls = mi.pitfalls; mLearning = mi.learningPoints
        }
    }

    var isValid: Bool {
        !specialty.trimmed.isEmpty && !patientName.trimmed.isEmpty &&
        !chiefComplaint.trimmed.isEmpty &&
        diagnoses.contains { $0.correct && !$0.name.trimmed.isEmpty } &&
        diagnoses.filter { !$0.name.trimmed.isEmpty }.count >= 2
    }

    mutating func setCorrectDiagnosis(_ index: Int) {
        for i in diagnoses.indices { diagnoses[i].correct = (i == index) }
    }

    func build() -> ClinicalCase {
        ClinicalCase(
            specialty: specialty.trimmed,
            patientName: patientName.trimmed,
            gender: gender,
            age: age.trimmed,
            chiefComplaint: chiefComplaint.trimmed,
            infoCards: [
                Self.card("Chief Complaint", chiefCard),
                Self.card("History", historyCard),
                Self.card("Physical Examination", examCard),
            ].filter { !$0.bullets.isEmpty || !$0.mentor.isEmpty },
            tests: tests.filter { !$0.name.trimmed.isEmpty }.map {
                TestOption(category: $0.category.trimmed, name: $0.name.trimmed,
                           result: $0.result.trimmed, helpful: $0.helpful, mentor: $0.mentor.trimmed)
            },
            diagnosisQuestion: diagnosisQuestion.trimmed,
            diagnoses: diagnoses.filter { !$0.name.trimmed.isEmpty }.map {
                DiagnosisOption(name: $0.name.trimmed, correct: $0.correct)
            },
            treatments: treatments.filter { !$0.name.trimmed.isEmpty }.map {
                TreatmentOption(category: $0.category.trimmed, name: $0.name.trimmed, appropriate: $0.appropriate)
            },
            outcomeTitle: outcomeTitle.trimmed.isEmpty ? "Well reasoned!" : outcomeTitle.trimmed,
            outcomeBody: outcomeBody.trimmed,
            xpReward: xp,
            mentorInsight: mentorInsight(),
            title: cardTitle.trimmed.isEmpty ? nil : cardTitle.trimmed,
            teaser: cardTeaser.trimmed.isEmpty ? nil : cardTeaser.trimmed,
            imageName: cardImage.trimmed.isEmpty ? nil : cardImage.trimmed,
            difficulty: cardDifficulty
        )
    }

    private func mentorInsight() -> MentorInsightContent? {
        let mi = MentorInsightContent(reasoning: mReasoning.trimmed, differentials: mDifferentials.trimmed,
                                      testRationale: mTestRationale.trimmed,
                                      treatmentSequencing: mTreatmentSequencing.trimmed,
                                      pearls: mPearls.trimmed, pitfalls: mPitfalls.trimmed,
                                      learningPoints: mLearning.trimmed)
        return mi.isEmpty ? nil : mi
    }

    /// Build one fixed info card with an enforced title.
    private static func card(_ title: String, _ d: InfoCardDraft) -> InfoCard {
        InfoCard(title: title,
                 bullets: d.bulletsText.split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty },
                 mentor: d.mentor.trimmed)
    }
}

struct InfoCardDraft: Identifiable { var id = UUID(); var title = ""; var bulletsText = ""; var mentor = "" }
struct TestDraft: Identifiable { var id = UUID(); var category = ""; var name = ""; var result = ""; var helpful = false; var mentor = "" }
struct DiagnosisDraft: Identifiable { var id = UUID(); var name = ""; var correct = false }
struct TreatmentDraft: Identifiable { var id = UUID(); var category = ""; var name = ""; var appropriate = false }
