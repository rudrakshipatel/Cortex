import Foundation

// MARK: - Bulk-import JSON format
//
// A single JSON object may contain "clinical", "daily" and/or "emergencies"
// arrays. The case body ("case") is the same CaseDTO format everywhere; daily
// entries add a "date" and emergencies add a "sendAt" date-time. IDs are
// generated automatically; optional fields fall back to sensible defaults.

struct ImportPayload: Codable {
    var clinical: [CaseDTO]?
    var daily: [DailyDTO]?
    var emergencies: [EmergencyDTO]?
}

/// A daily case + the calendar day it should appear on.
struct DailyDTO: Codable {
    var date: String?            // "2026-06-22" (GMT day); defaults to today
    var clinicalCase: CaseDTO

    private enum CodingKeys: String, CodingKey {
        case date
        case clinicalCase = "case"   // JSON key is "case"
    }

    func toModel(_ label: String, requireKey: Bool = true) throws -> DailyCase {
        DailyCase(clinicalCase: try clinicalCase.toModel("\(label) case", requireKey: requireKey),
                  date: DateParse.day(date) ?? Date())
    }
}

/// A case to broadcast as an emergency + when it should go live (stays 3h).
struct EmergencyDTO: Codable {
    var sendAt: String?          // ISO-8601, e.g. "2026-06-22T20:00:00Z"; defaults to now
    var clinicalCase: CaseDTO

    private enum CodingKeys: String, CodingKey {
        case sendAt
        case clinicalCase = "case"   // JSON key is "case"
    }

    func toModel(_ label: String) throws -> EmergencyCase {
        EmergencyCase(clinicalCase: try clinicalCase.toModel("\(label) case"),
                      fireDate: DateParse.dateTime(sendAt) ?? Date())
    }
}

/// Lenient date parsing for import strings.
enum DateParse {
    /// A calendar day like "2026-06-22" (interpreted in GMT).
    static func day(_ s: String?) -> Date? {
        guard let s = s?.trimmed, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: s) { return d }
        return dateTime(s)   // accept a full datetime too
    }
    /// An ISO-8601 date-time like "2026-06-22T20:00:00Z".
    static func dateTime(_ s: String?) -> Date? {
        guard let s = s?.trimmed, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }
}

struct CaseDTO: Codable {
    var specialty: String
    var patientName: String
    var gender: String?
    var age: String?
    var chiefComplaint: String
    var infoCards: [InfoCardDTO]?
    var tests: [TestDTO]?
    var diagnosisQuestion: String?
    var diagnoses: [DiagnosisDTO]
    var treatments: [TreatmentDTO]?
    var outcomeTitle: String?
    var outcomeBody: String?
    var xpReward: Int?
    var mentorInsight: MentorInsightContent?
    // Fixed clinical sections (preferred). Each → a page, in this order. If all
    // are absent, the legacy free-form `infoCards` array is used instead.
    var presentation: SectionDTO?   // → "Chief Complaint" page
    var history: SectionDTO?        // → "History" page
    var examination: SectionDTO?    // → "Physical Examination" page
    /// Presenting vitals (BP, PR, RR, SpO₂, Temperature, BMI).
    var vitals: Vitals?
    // Card presentation (optional).
    var title: String?              // dramatic case title
    var teaser: String?             // narrative hook on the card
    var imageName: String?          // hero image asset name
    var difficulty: Int?            // 1…5 — pips when no label is authored
    var difficultyLabel: String?    // e.g. "Intern"
    // Case metadata (optional).
    var occupation: String?
    var duration: String?
    var setting: String?
    var guidelineFocus: String?

    /// `requireKey` is true for authored/imported cases (which must declare the
    /// correct answer) and false for server-delivered cases, which arrive with
    /// the answer key stripped out and are graded server-side instead.
    func toModel(_ label: String, requireKey: Bool = true) throws -> ClinicalCase {
        guard !specialty.trimmed.isEmpty, !patientName.trimmed.isEmpty, !chiefComplaint.trimmed.isEmpty else {
            throw ImportError.field("\(label): 'specialty', 'patientName' and 'chiefComplaint' are required")
        }
        let dx = diagnoses.filter { !$0.name.trimmed.isEmpty }
                          .map { DiagnosisOption(name: $0.name.trimmed, correct: $0.correct ?? false,
                                                 rationale: ($0.rationale ?? "").trimmed,
                                                 tag: ($0.tag ?? "").trimmed) }
        guard dx.count >= 2 else { throw ImportError.field("\(label): needs at least 2 diagnoses") }
        if requireKey {
            guard dx.contains(where: \.correct) else {
                throw ImportError.field("\(label): one diagnosis must have \"correct\": true")
            }
        }
        return ClinicalCase(
            specialty: specialty.trimmed,
            patientName: patientName.trimmed,
            gender: gender?.trimmed.isEmpty == false ? gender!.trimmed : "Other",
            age: (age ?? "").trimmed,
            chiefComplaint: chiefComplaint.trimmed,
            infoCards: Self.buildInfoCards(presentation: presentation, history: history,
                                           examination: examination, legacy: infoCards),
            tests: (tests ?? []).map {
                TestOption(category: ($0.category ?? "").trimmed, name: $0.name.trimmed,
                           result: ($0.result ?? "").trimmed, helpful: $0.helpful ?? false,
                           mentor: ($0.mentor ?? "").trimmed, imageURL: ($0.imageURL ?? "").trimmed,
                           rationale: ($0.rationale ?? "").trimmed, tag: ($0.tag ?? "").trimmed)
            },
            diagnosisQuestion: (diagnosisQuestion ?? "Which diagnosis best fits this presentation?").trimmed,
            diagnoses: dx,
            treatments: (treatments ?? []).map {
                TreatmentOption(category: ($0.category ?? "").trimmed, name: $0.name.trimmed,
                                appropriate: $0.appropriate ?? false, rationale: ($0.rationale ?? "").trimmed,
                                tag: ($0.tag ?? "").trimmed)
            },
            outcomeTitle: (outcomeTitle ?? "Well reasoned!").trimmed,
            outcomeBody: (outcomeBody ?? "").trimmed,
            xpReward: xpReward ?? 20,
            mentorInsight: (mentorInsight?.isEmpty ?? true) ? nil : mentorInsight,
            vitals: (vitals?.isEmpty ?? true) ? nil : vitals,
            title: title?.trimmed, teaser: teaser?.trimmed,
            imageName: imageName?.trimmed, difficulty: difficulty,
            difficultyLabel: difficultyLabel?.trimmed, occupation: occupation?.trimmed,
            duration: duration?.trimmed, setting: setting?.trimmed,
            guidelineFocus: guidelineFocus?.trimmed)
    }

    /// Build a DTO from a fully-formed case — used to broadcast/publish. Emits the
    /// named sections (and omits the legacy infoCards array).
    init(from c: ClinicalCase) {
        specialty = c.specialty
        patientName = c.patientName
        gender = c.gender
        age = c.age
        chiefComplaint = c.chiefComplaint
        infoCards = nil
        // Bucket the case's info cards into the three named sections by title.
        for card in c.infoCards {
            let t = card.title.lowercased()
            let s = SectionDTO(bullets: card.bullets, mentor: card.mentor,
                               groups: card.groups.isEmpty ? nil
                                   : card.groups.map { InfoGroupDTO(system: $0.system, findings: $0.findings) })
            if t.contains("history") || t.contains("hx") { history = s }
            else if t.contains("exam") { examination = s }
            else { presentation = s }
        }
        tests = c.tests.map { TestDTO(category: $0.category, name: $0.name, result: $0.result, helpful: $0.helpful, mentor: $0.mentor, rationale: $0.rationale, tag: $0.tag, imageURL: $0.imageURL) }
        diagnosisQuestion = c.diagnosisQuestion
        diagnoses = c.diagnoses.map { DiagnosisDTO(name: $0.name, correct: $0.correct, rationale: $0.rationale, tag: $0.tag) }
        treatments = c.treatments.map { TreatmentDTO(category: $0.category, name: $0.name, appropriate: $0.appropriate, rationale: $0.rationale, tag: $0.tag) }
        outcomeTitle = c.outcomeTitle
        outcomeBody = c.outcomeBody
        xpReward = c.xpReward
        mentorInsight = c.mentorInsight
        vitals = c.vitals
        title = c.title; teaser = c.teaser; imageName = c.imageName; difficulty = c.difficulty
        difficultyLabel = c.difficultyLabel
        occupation = c.occupation; duration = c.duration
        setting = c.setting; guidelineFocus = c.guidelineFocus
    }

    /// Prefer the three named sections (titled Chief Complaint / History /
    /// Physical Examination); fall back to a legacy free-form `infoCards` array.
    static func buildInfoCards(presentation: SectionDTO?, history: SectionDTO?,
                               examination: SectionDTO?, legacy: [InfoCardDTO]?) -> [InfoCard] {
        let sectioned = [
            section("Chief Complaint", presentation),
            section("History", history),
            section("Physical Examination", examination),
        ].compactMap { $0 }
        if !sectioned.isEmpty { return sectioned }
        return (legacy ?? []).map {
            InfoCard(title: $0.title.trimmed,
                     bullets: $0.bullets.map(\.trimmed).filter { !$0.isEmpty },
                     mentor: ($0.mentor ?? "").trimmed)
        }
    }
    private static func section(_ title: String, _ s: SectionDTO?) -> InfoCard? {
        guard let s else { return nil }
        let bullets = (s.bullets ?? []).map(\.trimmed).filter { !$0.isEmpty }
        let mentor = (s.mentor ?? "").trimmed
        let groups = (s.groups ?? []).map {
            InfoGroup(system: $0.system.trimmed, findings: $0.findings.map(\.trimmed).filter { !$0.isEmpty })
        }.filter { !$0.system.isEmpty || !$0.findings.isEmpty }
        guard !bullets.isEmpty || !mentor.isEmpty || !groups.isEmpty else { return nil }
        return InfoCard(title: title, bullets: bullets, mentor: mentor, groups: groups)
    }
}

struct SectionDTO: Codable { var bullets: [String]?; var mentor: String?; var groups: [InfoGroupDTO]? }
struct InfoGroupDTO: Codable { var system: String; var findings: [String] }

struct InfoCardDTO: Codable { var title: String; var bullets: [String]; var mentor: String? }
// `helpful`/`appropriate`/`rationale`/`tag` are absent on server-stripped cases.
struct TestDTO: Codable { var category: String?; var name: String; var result: String?; var helpful: Bool?; var mentor: String?; var rationale: String?; var tag: String?; var imageURL: String? }
struct DiagnosisDTO: Codable { var name: String; var correct: Bool?; var rationale: String?; var tag: String? }
struct TreatmentDTO: Codable { var category: String?; var name: String; var appropriate: Bool?; var rationale: String?; var tag: String? }

// MARK: - Result & errors

struct ImportSummary { var clinical = 0; var daily = 0; var emergencies = 0
    var total: Int { clinical + daily + emergencies }
    var text: String { "Added \(clinical) clinical, \(daily) daily, \(emergencies) emergency case(s)." }
}

enum ImportError: LocalizedError {
    case empty, parse(String), field(String), nothing
    var errorDescription: String? {
        switch self {
        case .empty:        return "The JSON is empty."
        case .parse(let m): return "Couldn't read the JSON: \(m)"
        case .field(let m): return m
        case .nothing:      return "No items found. Use top-level \"clinical\", \"daily\" or \"emergencies\" arrays."
        }
    }
}
