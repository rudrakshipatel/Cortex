import SwiftUI
import PhotosUI

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
                TextField("Difficulty label (e.g. Intern)", text: $draft.difficultyLabel)
                if draft.difficultyLabel.trimmed.isEmpty {
                    Stepper("Difficulty: \(draft.cardDifficulty)/5", value: $draft.cardDifficulty, in: 1...5)
                }
            } header: {
                Text("Case card (optional)")
            } footer: {
                Text("Shown on the Home card. Add an image to the app's asset catalog and enter its name here; leave blank for a default banner. A difficulty label replaces the 1–5 pips.")
            }

            Section {
                TextField("Setting (e.g. Primary Care Clinic (OPD))", text: $draft.setting)
                TextField("Occupation (e.g. Elementary School Teacher)", text: $draft.occupation)
                TextField("Duration (e.g. 3 months)", text: $draft.duration)
                TextField("Guideline focus (e.g. NHLBI EPR-4 / GINA)", text: $draft.guidelineFocus, axis: .vertical).lineLimit(1...3)
            } header: {
                Text("Encounter (optional)")
            } footer: {
                Text("Shown under the patient strip on the first case page.")
            }

            Section {
                TextField("Blood pressure (e.g. 118/76 mmHg)", text: $draft.vBP)
                TextField("Pulse / heart rate (e.g. 76 bpm)", text: $draft.vPR)
                TextField("Respiratory rate (e.g. 16/min)", text: $draft.vRR)
                TextField("SpO₂ (e.g. 97% on room air)", text: $draft.vSpO2)
                TextField("Temperature (e.g. 98.4°F (36.9°C))", text: $draft.vTemp)
                TextField("BMI (e.g. 22.1 kg/m²)", text: $draft.vBMI)
            } header: {
                Text("Vitals (optional)")
            } footer: {
                Text("Leave blank to omit the vitals panel.")
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
            } header: { Text("2. History") } footer: {
                Text("Use bullets for a flat list, or add groups below for headed sections (e.g. \"Family History\").")
            }
            groupEditor("History group", $draft.historyCard.groups,
                        add: { draft.historyCard.groups.append(.init()) },
                        remove: { if !draft.historyCard.groups.isEmpty { draft.historyCard.groups.removeLast() } })

            Section {
                TextField("Exam findings — one bullet per line", text: $draft.examCard.bulletsText, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Mentor insight (optional)", text: $draft.examCard.mentor, axis: .vertical).lineLimit(1...4)
            } header: { Text("3. Physical Examination") } footer: {
                Text("Use bullets for a flat list, or add groups below for per-system findings (e.g. \"Respiratory\").")
            }
            groupEditor("Exam group", $draft.examCard.groups,
                        add: { draft.examCard.groups.append(.init()) },
                        remove: { if !draft.examCard.groups.isEmpty { draft.examCard.groups.removeLast() } })

            ForEach($draft.tests) { $t in
                Section("Test") {
                    TextField("Category (e.g. Hematology)", text: $t.category)
                    TextField("Test name", text: $t.name)
                    TextField("Result — one line per finding", text: $t.result, axis: .vertical).lineLimit(1...6)
                    Toggle("Helpful / high-yield", isOn: $t.helpful)
                    TextField("Mentor note", text: $t.mentor, axis: .vertical).lineLimit(1...3)
                    TextField("Status tag (e.g. COPD/Emphysema Distractor)", text: $t.tag)
                    TextField("Why this test was (in)appropriate", text: $t.rationale, axis: .vertical).lineLimit(1...4)
                    ResultImagePicker(imageURL: $t.imageURL)
                }
            }
            addRemoveRow("test", count: draft.tests.count,
                         add: { draft.tests.append(.init()) },
                         remove: { if draft.tests.count > 1 { draft.tests.removeLast() } })

            Section("Diagnosis · tap the circle to mark the correct one") {
                TextField("Diagnosis question", text: $draft.diagnosisQuestion, axis: .vertical).lineLimit(1...3)
                ForEach(draft.diagnoses.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Button { draft.setCorrectDiagnosis(i) } label: {
                            Image(systemName: draft.diagnoses[i].correct ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(draft.diagnoses[i].correct ? CX.teal : .secondary)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Diagnosis \(i + 1)", text: $draft.diagnoses[i].name)
                            TextField("Status tag (e.g. Definitive Diagnosis)", text: $draft.diagnoses[i].tag)
                                .font(.footnote)
                            TextField("Why it did / didn't fit", text: $draft.diagnoses[i].rationale, axis: .vertical)
                                .font(.footnote).lineLimit(1...4)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            addRemoveRow("diagnosis", count: draft.diagnoses.count,
                         add: { draft.diagnoses.append(.init()) },
                         remove: { if draft.diagnoses.count > 2 { draft.diagnoses.removeLast() } })

            Section("Treatment · tap the circle to mark the appropriate ones") {
                ForEach(draft.treatments.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Button { draft.treatments[i].appropriate.toggle() } label: {
                            Image(systemName: draft.treatments[i].appropriate ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(draft.treatments[i].appropriate ? CX.teal : .secondary)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Category (e.g. Medications)", text: $draft.treatments[i].category)
                                .font(.footnote).foregroundStyle(.secondary)
                            TextField("Treatment name", text: $draft.treatments[i].name)
                            TextField("Status tag (e.g. Symptomatic Distractor)", text: $draft.treatments[i].tag)
                                .font(.footnote)
                            TextField("Why this treatment was (in)appropriate",
                                      text: $draft.treatments[i].rationale, axis: .vertical)
                                .font(.footnote).lineLimit(1...4)
                        }
                    }
                    .padding(.vertical, 2)
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
            } header: {
                Text("Mentor Insight (coin-locked)")
            } footer: {
                Text("Optional. Leave blank to omit. Shown on the answer screen once the user unlocks it with coins. The Why-other-diagnoses / test / treatment sections are built from each option's own rationale above.")
            }

            ForEach($draft.pearls) { $p in
                Section("Clinical Pearl") {
                    TextField("Pearl title (the button)", text: $p.title)
                    TextField("What it opens", text: $p.body, axis: .vertical).lineLimit(2...8)
                }
            }
            addRemoveRow("pearl", count: draft.pearls.count,
                         add: { draft.pearls.append(.init()) },
                         remove: { if !draft.pearls.isEmpty { draft.pearls.removeLast() } })
        }
    }

    /// Repeating editor for an info card's grouped findings: a heading and its
    /// findings, one per line.
    @ViewBuilder private func groupEditor(_ noun: String, _ groups: Binding<[InfoGroupDraft]>,
                                          add: @escaping () -> Void, remove: @escaping () -> Void) -> some View {
        ForEach(groups) { $g in
            Section(noun) {
                TextField("Heading (e.g. Respiratory)", text: $g.system)
                TextField("Findings — one per line", text: $g.findingsText, axis: .vertical).lineLimit(2...8)
            }
        }
        addRemoveRow(noun.lowercased(), count: groups.wrappedValue.count, add: add, remove: remove)
    }

    private func addRemoveRow(_ noun: String, count: Int,
                              add: @escaping () -> Void, remove: @escaping () -> Void) -> some View {
        Section {
            HStack {
                // Both buttons must be `.borderless`: a Form row with two
                // tappable buttons otherwise resolves the tap at row level and
                // neither fires (which stopped the list growing past the point
                // where Remove became enabled).
                Button { add() } label: { Label("Add \(noun)", systemImage: "plus.circle.fill") }
                    .buttonStyle(.borderless)
                Spacer()
                Button(role: .destructive) { remove() } label: {
                    Label("Remove last", systemImage: "minus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(count <= minCount(noun))
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
    var difficultyLabel = ""
    var setting = ""
    var occupation = ""
    var duration = ""
    var guidelineFocus = ""
    var vBP = "", vPR = "", vRR = "", vSpO2 = "", vTemp = "", vBMI = ""
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
    var pearls: [PearlDraft] = []

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
        difficultyLabel = c.difficultyLabel ?? ""
        setting = c.setting ?? ""; occupation = c.occupation ?? ""
        duration = c.duration ?? ""; guidelineFocus = c.guidelineFocus ?? ""
        if let v = c.vitals {
            vBP = v.bp; vPR = v.pr; vRR = v.rr; vSpO2 = v.spo2; vTemp = v.temperature; vBMI = v.bmi
        }
        // Bucket existing info cards into the three fixed sections by title.
        for card in c.infoCards {
            let bullets = card.bullets.joined(separator: "\n")
            let groups = card.groups.map {
                InfoGroupDraft(system: $0.system, findingsText: $0.findings.joined(separator: "\n"))
            }
            let t = card.title.lowercased()
            if t.contains("history") || t.contains("hx") {
                historyCard.bulletsText = bullets; historyCard.mentor = card.mentor; historyCard.groups = groups
            } else if t.contains("exam") {
                examCard.bulletsText = bullets; examCard.mentor = card.mentor; examCard.groups = groups
            } else {
                chiefCard.bulletsText = bullets; chiefCard.mentor = card.mentor; chiefCard.groups = groups
            }
        }
        tests = c.tests.map {
            TestDraft(category: $0.category, name: $0.name, result: $0.result, helpful: $0.helpful,
                      mentor: $0.mentor, rationale: $0.rationale, tag: $0.tag, imageURL: $0.imageURL)
        }
        if tests.isEmpty { tests = [TestDraft()] }
        diagnosisQuestion = c.diagnosisQuestion
        diagnoses = c.diagnoses.map { DiagnosisDraft(name: $0.name, correct: $0.correct,
                                                     rationale: $0.rationale, tag: $0.tag) }
        while diagnoses.count < 2 { diagnoses.append(DiagnosisDraft()) }
        treatments = c.treatments.map {
            TreatmentDraft(category: $0.category, name: $0.name, appropriate: $0.appropriate,
                           rationale: $0.rationale, tag: $0.tag)
        }
        if treatments.isEmpty { treatments = [TreatmentDraft()] }
        outcomeTitle = c.outcomeTitle
        outcomeBody = c.outcomeBody
        xp = c.xpReward
        if let mi = c.mentorInsight {
            mReasoning = mi.reasoning
            pearls = mi.pearls.map { PearlDraft(title: $0.title, body: $0.body) }
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
            ].filter { !$0.bullets.isEmpty || !$0.mentor.isEmpty || !$0.groups.isEmpty },
            tests: tests.filter { !$0.name.trimmed.isEmpty }.map {
                TestOption(category: $0.category.trimmed, name: $0.name.trimmed,
                           result: $0.result.trimmed, helpful: $0.helpful, mentor: $0.mentor.trimmed,
                           imageURL: $0.imageURL.trimmed, rationale: $0.rationale.trimmed,
                           tag: $0.tag.trimmed)
            },
            diagnosisQuestion: diagnosisQuestion.trimmed,
            diagnoses: diagnoses.filter { !$0.name.trimmed.isEmpty }.map {
                DiagnosisOption(name: $0.name.trimmed, correct: $0.correct,
                                rationale: $0.rationale.trimmed, tag: $0.tag.trimmed)
            },
            treatments: treatments.filter { !$0.name.trimmed.isEmpty }.map {
                TreatmentOption(category: $0.category.trimmed, name: $0.name.trimmed, appropriate: $0.appropriate,
                                rationale: $0.rationale.trimmed, tag: $0.tag.trimmed)
            },
            outcomeTitle: outcomeTitle.trimmed.isEmpty ? "Well reasoned!" : outcomeTitle.trimmed,
            outcomeBody: outcomeBody.trimmed,
            xpReward: xp,
            mentorInsight: mentorInsight(),
            vitals: vitals(),
            title: cardTitle.trimmed.isEmpty ? nil : cardTitle.trimmed,
            teaser: cardTeaser.trimmed.isEmpty ? nil : cardTeaser.trimmed,
            imageName: cardImage.trimmed.isEmpty ? nil : cardImage.trimmed,
            difficulty: cardDifficulty,
            difficultyLabel: difficultyLabel.trimmed.isEmpty ? nil : difficultyLabel.trimmed,
            occupation: occupation.trimmed.isEmpty ? nil : occupation.trimmed,
            duration: duration.trimmed.isEmpty ? nil : duration.trimmed,
            setting: setting.trimmed.isEmpty ? nil : setting.trimmed,
            guidelineFocus: guidelineFocus.trimmed.isEmpty ? nil : guidelineFocus.trimmed
        )
    }

    /// The authored vitals, or nil when every field is blank.
    private func vitals() -> Vitals? {
        let v = Vitals(bp: vBP.trimmed, pr: vPR.trimmed, rr: vRR.trimmed,
                       spo2: vSpO2.trimmed, temperature: vTemp.trimmed, bmi: vBMI.trimmed)
        return v.isEmpty ? nil : v
    }

    private func mentorInsight() -> MentorInsightContent? {
        let mi = MentorInsightContent(reasoning: mReasoning.trimmed,
                                      pearls: pearls.map { ClinicalPearl(title: $0.title.trimmed, body: $0.body.trimmed) }
                                                    .filter { !$0.isEmpty })
        return mi.isEmpty ? nil : mi
    }

    /// Build one fixed info card with an enforced title.
    private static func card(_ title: String, _ d: InfoCardDraft) -> InfoCard {
        InfoCard(title: title,
                 bullets: lines(d.bulletsText),
                 mentor: d.mentor.trimmed,
                 groups: d.groups.map { InfoGroup(system: $0.system.trimmed, findings: lines($0.findingsText)) }
                                 .filter { !$0.system.isEmpty || !$0.findings.isEmpty })
    }

    /// One trimmed, non-empty entry per line.
    private static func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty }
    }
}

/// Attaches a result image to a test: pick a photo, upload it to the public
/// case-images bucket, and keep the returned URL on the test. The URL is
/// editable by hand too, for an image hosted elsewhere.
struct ResultImagePicker: View {
    @Binding var imageURL: String
    @EnvironmentObject private var sb: SupabaseService
    @State private var picked: PhotosPickerItem?
    @State private var uploading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PhotosPicker(selection: $picked, matching: .images) {
                    Label(imageURL.trimmed.isEmpty ? "Attach result image" : "Replace image",
                          systemImage: "photo.badge.plus")
                }
                .disabled(uploading || !sb.isAdminSignedIn)
                Spacer()
                if uploading { ProgressView() }
                else if !imageURL.trimmed.isEmpty {
                    Button(role: .destructive) { imageURL = ""; error = nil } label: {
                        Image(systemName: "trash")
                    }.buttonStyle(.borderless)
                }
            }
            if !sb.isAdminSignedIn {
                Text("Sign in under Cloud sync to upload images.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !imageURL.trimmed.isEmpty {
                AsyncImage(url: URL(string: imageURL.trimmed)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().frame(maxHeight: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .empty: ProgressView().frame(height: 40)
                    default:
                        Label("Can't preview this URL", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                TextField("Image URL", text: $imageURL, axis: .vertical)
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1...3)
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            upload(item)
        }
    }

    private func upload(_ item: PhotosPickerItem) {
        uploading = true; error = nil
        Task {
            defer { uploading = false; picked = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    error = "Couldn't read that image."; return
                }
                // PNG keeps screenshots (ECG strips, X-rays) crisp; everything
                // else uploads as-is.
                let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
                imageURL = try await sb.uploadCaseImage(data, fileExtension: isPNG ? "png" : "jpg")
            } catch {
                self.error = "Upload failed: \(error.localizedDescription)"
            }
        }
    }
}

struct InfoCardDraft: Identifiable {
    var id = UUID(); var title = ""; var bulletsText = ""; var mentor = ""
    var groups: [InfoGroupDraft] = []
}
struct InfoGroupDraft: Identifiable { var id = UUID(); var system = ""; var findingsText = "" }
struct PearlDraft: Identifiable { var id = UUID(); var title = ""; var body = "" }
struct TestDraft: Identifiable { var id = UUID(); var category = ""; var name = ""; var result = ""; var helpful = false; var mentor = ""; var rationale = ""; var tag = ""; var imageURL = "" }
struct DiagnosisDraft: Identifiable { var id = UUID(); var name = ""; var correct = false; var rationale = ""; var tag = "" }
struct TreatmentDraft: Identifiable { var id = UUID(); var category = ""; var name = ""; var appropriate = false; var rationale = ""; var tag = "" }
