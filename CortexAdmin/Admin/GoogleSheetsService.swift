import Foundation

/// Pulls authored cases from a Google Sheet (via the Sheets API v4, read-only
/// API key) and turns each row into the same JSON shape `BulkImportView`
/// already accepts, so the actual import/publish validation lives in exactly
/// one place: `CaseDTO.toModel` (see ContentImport.swift).
///
/// The sheet has 7 fixed tabs (see google-sheets-template.xlsx): `Sheet1`
/// holds one row per case; `Tests` / `Diagnosis` / `Treatment` each hold the
/// full pool of options offered for a case (by `CaseID`); `Correct Tests` /
/// `Correct Diagnosis` / `Correct Treatment` hold just the right answers
/// (with, for tests, the finding + teaching note). An option that's never
/// marked correct only needs a name — no per-distractor writing required.
///
/// Auth: a Sheets-restricted API key has no Google identity, so it can only
/// read a sheet shared as "Anyone with the link — Viewer". Dedup ("don't
/// publish an already-published row") is tracked locally by row `ID` — there
/// is no write-back to the sheet, since that would need OAuth/a service
/// account rather than a plain API key.
@MainActor
final class GoogleSheetsService: ObservableObject {
    static let shared = GoogleSheetsService()

    @Published var sheetURLOrID: String { didSet { defaults.set(sheetURLOrID, forKey: K.sheet) } }
    @Published var apiKey: String       { didSet { defaults.set(apiKey, forKey: K.key) } }

    private(set) var syncedIDs: Set<String> {
        didSet { defaults.set(Array(syncedIDs), forKey: K.synced) }
    }

    var isConfigured: Bool { !spreadsheetID.isEmpty && !apiKey.trimmed.isEmpty }

    private let defaults = UserDefaults.standard
    private enum K {
        static let sheet = "cx.sheets.sheetURLOrID"
        static let key = "cx.sheets.apiKey", synced = "cx.sheets.syncedIDs"
    }

    private init() {
        sheetURLOrID = defaults.string(forKey: K.sheet) ?? ""
        apiKey = defaults.string(forKey: K.key) ?? ""
        syncedIDs = Set(defaults.stringArray(forKey: K.synced) ?? [])
    }

    func markSynced(_ ids: [String]) { syncedIDs.formUnion(ids) }
    func resetSynced() { syncedIDs.removeAll() }

    /// The bare spreadsheet ID, whether the user pasted a full URL
    /// (".../spreadsheets/d/{id}/edit...") or just the ID itself.
    var spreadsheetID: String {
        let s = sheetURLOrID.trimmed
        guard let range = s.range(of: "/d/") else { return s }
        let rest = s[range.upperBound...]
        return String(rest.prefix { $0 != "/" })
    }

    // MARK: - Tabs

    /// Fixed tab names the sheet must use — see google-sheets-template.xlsx.
    private enum Tab {
        static let cases = "Sheet1"
        static let tests = "Tests", correctTests = "Correct Tests"
        static let diagnosis = "Diagnosis", correctDiagnosis = "Correct Diagnosis"
        static let treatment = "Treatment", correctTreatment = "Correct Treatment"
        static let all = [cases, tests, correctTests, diagnosis, correctDiagnosis, treatment, correctTreatment]
    }

    /// Alternate header spellings accepted alongside the canonical column
    /// names, so a slightly different sheet header still parses.
    private let headerAliases: [String: String] = ["Speciality": "Specialty"]

    struct Row: Identifiable {
        var id: String            // Sheet1's own "ID" column
        var fields: [String: String]
        var tests: [[String: Any]]
        var diagnoses: [[String: Any]]
        var treatments: [[String: Any]]
    }

    enum SheetsError: LocalizedError {
        case notConfigured, badResponse, http(Int, String), missingID(Int)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Add the sheet URL and API key first."
            case .badResponse: return "Couldn't read the sheet's response — check that all 7 tabs exist (Sheet1, Tests, Correct Tests, Diagnosis, Correct Diagnosis, Treatment, Correct Treatment)."
            case .http(let code, let msg): return "Sheets API error \(code): \(msg)"
            case .missingID(let row): return "Sheet1 row \(row) has no value in the ID column — skipped."
            }
        }
    }

    /// Fetch every case row plus its linked test/diagnosis/treatment options
    /// from the other 6 tabs, joined by `CaseID`. Case rows missing an `ID`
    /// are dropped (surfaced via `warnings`); dedup against `syncedIDs`
    /// happens in the view, since "already synced" is about what the admin
    /// does with the row, not about the fetch itself.
    func fetchRows() async throws -> (rows: [Row], warnings: [String]) {
        guard isConfigured else { throw SheetsError.notConfigured }
        var comps = URLComponents(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values:batchGet")
        comps?.queryItems = Tab.all.map { URLQueryItem(name: "ranges", value: "'\($0)'") }
            + [URLQueryItem(name: "key", value: apiKey.trimmed)]
        guard let url = comps?.url else { throw SheetsError.badResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw SheetsError.badResponse }
        guard 200..<300 ~= http.statusCode else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? "request failed"
            throw SheetsError.http(http.statusCode, msg)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let valueRanges = json["valueRanges"] as? [[String: Any]], valueRanges.count == Tab.all.count else {
            throw SheetsError.badResponse
        }

        var tableRows: [String: [[String: String]]] = [:]
        for (name, vr) in zip(Tab.all, valueRanges) {
            let values = (vr["values"] as? [[Any]]) ?? []
            guard let headerRow = values.first else { tableRows[name] = []; continue }
            let headers = headerRow.map { headerAliases["\($0)".trimmed] ?? "\($0)".trimmed }
            tableRows[name] = values.dropFirst().map { raw in
                let cells = raw.map { "\($0)" }
                var fields: [String: String] = [:]
                for (i, h) in headers.enumerated() where !h.isEmpty {
                    fields[h] = (i < cells.count ? cells[i] : "").trimmed
                }
                return fields
            }
        }

        func caseKey(_ f: [String: String]) -> String { (f["CaseID"] ?? f["ID"] ?? "").trimmed }
        func groupByCase(_ tab: String) -> [String: [[String: String]]] {
            Dictionary(grouping: (tableRows[tab] ?? []).filter { !caseKey($0).isEmpty }, by: caseKey)
        }
        let testsByCase = groupByCase(Tab.tests), correctTestsByCase = groupByCase(Tab.correctTests)
        let diagnosisByCase = groupByCase(Tab.diagnosis), correctDiagnosisByCase = groupByCase(Tab.correctDiagnosis)
        let treatmentByCase = groupByCase(Tab.treatment), correctTreatmentByCase = groupByCase(Tab.correctTreatment)

        var warnings: [String] = []
        var rows: [Row] = []
        for (offset, fields) in (tableRows[Tab.cases] ?? []).enumerated() {
            let id = (fields["ID"] ?? "").trimmed
            guard !id.isEmpty else {
                warnings.append(SheetsError.missingID(offset + 2).localizedDescription)
                continue
            }
            rows.append(Row(
                id: id, fields: fields,
                tests: Self.mergeTests(options: testsByCase[id] ?? [], correct: correctTestsByCase[id] ?? []),
                diagnoses: Self.mergeSimple(options: diagnosisByCase[id] ?? [], correct: correctDiagnosisByCase[id] ?? [], flag: "correct"),
                treatments: Self.mergeCategorized(options: treatmentByCase[id] ?? [], correct: correctTreatmentByCase[id] ?? [], flag: "appropriate")))
        }
        return (rows, warnings)
    }

    // MARK: - Options ⨝ Correct-answers merge
    //
    // Each "options" tab lists every choice a player can pick (decoys +
    // correct, matched by name only); each "correct" tab supplies the flag
    // (and, for tests, the finding + teaching note) for the right ones. An
    // entry present only in the "correct" tab is unioned in automatically,
    // so a typo'd/omitted option never silently loses its right answer.

    private static func norm(_ s: String) -> String { s.trimmed.lowercased() }

    private static func mergeTests(options: [[String: String]], correct: [[String: String]]) -> [[String: Any]] {
        var order: [String] = []
        var byKey: [String: [String: Any]] = [:]
        for o in options {
            let name = (o["Name"] ?? "").trimmed
            guard !name.isEmpty else { continue }
            let key = norm(name)
            if byKey[key] == nil { order.append(key) }
            byKey[key] = [
                "category": (o["Category"] ?? "").trimmed, "name": name,
                "result": "Not clinically significant for this presentation.", "helpful": false, "mentor": "",
            ]
        }
        for c in correct {
            let name = (c["Name"] ?? "").trimmed
            guard !name.isEmpty else { continue }
            let key = norm(name)
            var entry = byKey[key] ?? ["category": (c["Category"] ?? "").trimmed, "name": name]
            if !(c["Category"] ?? "").trimmed.isEmpty { entry["category"] = (c["Category"] ?? "").trimmed }
            entry["result"] = (c["Result"] ?? "").trimmed
            entry["mentor"] = (c["Mentor"] ?? "").trimmed
            entry["helpful"] = true
            if byKey[key] == nil { order.append(key) }
            byKey[key] = entry
        }
        return order.compactMap { byKey[$0] }
    }

    private static func mergeSimple(options: [[String: String]], correct: [[String: String]], flag: String) -> [[String: Any]] {
        var order: [String] = []
        var byKey: [String: [String: Any]] = [:]
        for o in options {
            let name = (o["Name"] ?? "").trimmed
            guard !name.isEmpty else { continue }
            let key = norm(name)
            if byKey[key] == nil { order.append(key) }
            byKey[key] = ["name": name, flag: false]
        }
        for c in correct {
            let name = (c["Name"] ?? "").trimmed
            guard !name.isEmpty else { continue }
            let key = norm(name)
            if byKey[key] == nil { order.append(key) }
            byKey[key] = ["name": name, flag: true]
        }
        return order.compactMap { byKey[$0] }
    }

    private static func mergeCategorized(options: [[String: String]], correct: [[String: String]], flag: String) -> [[String: Any]] {
        var order: [String] = []
        var byKey: [String: [String: Any]] = [:]
        for o in options {
            let name = (o["Name"] ?? "").trimmed
            guard !name.isEmpty else { continue }
            let key = norm(name)
            if byKey[key] == nil { order.append(key) }
            byKey[key] = ["category": (o["Category"] ?? "").trimmed, "name": name, flag: false]
        }
        for c in correct {
            let name = (c["Name"] ?? "").trimmed
            guard !name.isEmpty else { continue }
            let key = norm(name)
            var entry = byKey[key] ?? ["category": (c["Category"] ?? "").trimmed, "name": name]
            if !(c["Category"] ?? "").trimmed.isEmpty { entry["category"] = (c["Category"] ?? "").trimmed }
            entry[flag] = true
            if byKey[key] == nil { order.append(key) }
            byKey[key] = entry
        }
        return order.compactMap { byKey[$0] }
    }

    // MARK: - Row → BulkImportView JSON

    /// Converts valid rows into the combined JSON text `ContentStore.importJSON`
    /// / `SupabaseService.publish` already know how to parse. Rows that fail to
    /// convert are returned separately (with a reason) instead of aborting the
    /// whole batch — one bad row in the sheet shouldn't block the rest.
    func buildImportJSON(from rows: [Row]) -> (json: String, failed: [(id: String, reason: String)]) {
        var clinical: [[String: Any]] = []
        var daily: [[String: Any]] = []
        var emergencies: [[String: Any]] = []
        var failed: [(String, String)] = []

        for row in rows {
            do {
                let caseDict = try caseJSON(from: row)
                switch (row.fields["Type"] ?? "clinical").trimmed.lowercased() {
                case "daily":
                    daily.append(["date": (row.fields["Date"] ?? "").trimmed, "case": caseDict])
                case "emergency":
                    emergencies.append(["sendAt": (row.fields["Date"] ?? "").trimmed, "case": caseDict])
                default:
                    clinical.append(caseDict)
                }
            } catch {
                failed.append((row.id, error.localizedDescription))
            }
        }

        var payload: [String: Any] = [:]
        if !clinical.isEmpty { payload["clinical"] = clinical }
        if !daily.isEmpty { payload["daily"] = daily }
        if !emergencies.isEmpty { payload["emergencies"] = emergencies }
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        return (String(data: data, encoding: .utf8) ?? "{}", failed)
    }

    private enum RowError: LocalizedError {
        case field(String)
        var errorDescription: String? { if case .field(let m) = self { return m }; return nil }
    }

    private func caseJSON(from row: Row) throws -> [String: Any] {
        let f = row.fields
        func s(_ key: String) -> String { (f[key] ?? "").trimmed }

        // "Name:Gender:Age", e.g. "Marco:Male:30 Y".
        let patientParts = s("Patient info").components(separatedBy: ":").map(\.trimmed)
        let patientName = patientParts.first ?? ""
        let gender = patientParts.count > 1 ? patientParts[1] : ""
        let age = patientParts.count > 2 ? patientParts[2...].joined(separator: ":").trimmed : ""

        guard !s("Specialty").isEmpty, !patientName.isEmpty else {
            throw RowError.field("'Specialty' and 'Patient info' (Name:Gender:Age) are required")
        }

        func bullets(_ key: String) -> [String] {
            s(key).components(separatedBy: "|").map(\.trimmed).filter { !$0.isEmpty }
        }

        // The app shows Chief Complaint and History as separate pages, but
        // this sheet only has one combined column: its bullets become the
        // History page, and the first bullet doubles as the required
        // one-line chief complaint shown on the case card.
        let historyBullets = bullets("History (Chief Complaint)")
        guard let chiefComplaint = historyBullets.first else {
            throw RowError.field("'History (Chief Complaint)' is required")
        }

        var dict: [String: Any] = [
            "specialty": s("Specialty"), "patientName": patientName,
            "gender": gender, "age": age, "chiefComplaint": chiefComplaint,
            "diagnosisQuestion": s("DiagnosisQuestion"),
        ]
        if !s("Case name").isEmpty { dict["title"] = s("Case name") }
        dict["history"] = ["bullets": historyBullets, "mentor": ""]
        let examBullets = bullets("Physical Examination")
        if !examBullets.isEmpty { dict["examination"] = ["bullets": examBullets, "mentor": ""] }

        guard !row.tests.isEmpty else { throw RowError.field("no rows found in the Tests tab for this CaseID") }
        dict["tests"] = row.tests

        guard row.diagnoses.count >= 2 else { throw RowError.field("needs at least 2 rows in the Diagnosis tab") }
        guard row.diagnoses.contains(where: { ($0["correct"] as? Bool) == true }) else {
            throw RowError.field("no matching row in the Correct Diagnosis tab for this CaseID")
        }
        dict["diagnoses"] = row.diagnoses

        guard !row.treatments.isEmpty else { throw RowError.field("no rows found in the Treatment tab for this CaseID") }
        dict["treatments"] = row.treatments

        if !s("OutcomeTitle").isEmpty { dict["outcomeTitle"] = s("OutcomeTitle") }
        if !s("OutcomeBody").isEmpty { dict["outcomeBody"] = s("OutcomeBody") }
        if let xp = Int(s("XPReward")) { dict["xpReward"] = xp }

        let mentor: [String: String] = [
            "reasoning": s("MentorReasoning"), "differentials": s("MentorDifferentials"),
            "testRationale": s("MentorTestRationale"), "treatmentSequencing": s("MentorTreatmentSequencing"),
            "pearls": s("MentorPearls"), "pitfalls": s("MentorPitfalls"), "learningPoints": s("MentorLearningPoints"),
        ]
        if mentor.values.contains(where: { !$0.isEmpty }) { dict["mentorInsight"] = mentor }

        return dict
    }
}
