import Foundation

/// Pulls authored cases from a Google Sheet (via the Sheets API v4, read-only
/// API key) and turns each row into the same JSON shape `BulkImportView`
/// already accepts, so the actual import/publish validation lives in exactly
/// one place: `CaseDTO.toModel` (see ContentImport.swift).
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
    @Published var tabName: String      { didSet { defaults.set(tabName, forKey: K.tab) } }
    @Published var apiKey: String       { didSet { defaults.set(apiKey, forKey: K.key) } }

    private(set) var syncedIDs: Set<String> {
        didSet { defaults.set(Array(syncedIDs), forKey: K.synced) }
    }

    var isConfigured: Bool {
        !spreadsheetID.isEmpty && !tabName.trimmed.isEmpty && !apiKey.trimmed.isEmpty
    }

    private let defaults = UserDefaults.standard
    private enum K {
        static let sheet = "cx.sheets.sheetURLOrID", tab = "cx.sheets.tabName"
        static let key = "cx.sheets.apiKey", synced = "cx.sheets.syncedIDs"
    }

    private init() {
        sheetURLOrID = defaults.string(forKey: K.sheet) ?? ""
        tabName = defaults.string(forKey: K.tab) ?? "Sheet1"
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

    // MARK: - Fetch

    /// Alternate header spellings accepted alongside the canonical column
    /// names, so a slightly different sheet header still parses.
    private let headerAliases: [String: String] = [
        "Speciality": "Specialty",
        "SpO₂": "SpO2", "Spo2": "SpO2", "SPO2": "SpO2",
        "Temp": "Temperature", "Temperature (°C)": "Temperature",
    ]

    struct Row: Identifiable {
        var id: String            // the sheet's own "ID" column
        var fields: [String: String]
    }

    enum SheetsError: LocalizedError {
        case notConfigured, badResponse, http(Int, String), noHeaderRow, missingID(Int)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Add the sheet URL, tab name and API key first."
            case .badResponse: return "Couldn't read the sheet's response."
            case .http(let code, let msg): return "Sheets API error \(code): \(msg)"
            case .noHeaderRow: return "The sheet has no header row."
            case .missingID(let row): return "Row \(row) has no value in the ID column — skipped."
            }
        }
    }

    /// Fetch every row from the configured sheet. Rows missing an `ID` are
    /// dropped (surfaced via `warnings`); dedup against `syncedIDs` happens in
    /// the view, since "already synced" is about what the admin does with the
    /// row, not about the fetch itself.
    func fetchRows() async throws -> (rows: [Row], warnings: [String]) {
        guard isConfigured else { throw SheetsError.notConfigured }
        let range = tabName.trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tabName.trimmed
        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(range)?key=\(apiKey.trimmed)") else {
            throw SheetsError.badResponse
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw SheetsError.badResponse }
        guard 200..<300 ~= http.statusCode else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? "request failed"
            throw SheetsError.http(http.statusCode, msg)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["values"] as? [[Any]], let headerRow = values.first else {
            throw SheetsError.noHeaderRow
        }
        let headers = headerRow.map { headerAliases["\($0)".trimmed] ?? "\($0)".trimmed }
        var warnings: [String] = []
        var rows: [Row] = []
        for (offset, raw) in values.dropFirst().enumerated() {
            let cells = raw.map { "\($0)" }
            var fields: [String: String] = [:]
            for (i, h) in headers.enumerated() where !h.isEmpty {
                fields[h] = (i < cells.count ? cells[i] : "").trimmed
            }
            let id = (fields["ID"] ?? "").trimmed
            guard !id.isEmpty else {
                warnings.append(SheetsError.missingID(offset + 2).localizedDescription)
                continue
            }
            rows.append(Row(id: id, fields: fields))
        }
        return (rows, warnings)
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
                let caseDict = try caseJSON(from: row.fields)
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

    private func caseJSON(from f: [String: String]) throws -> [String: Any] {
        func s(_ key: String) -> String { (f[key] ?? "").trimmed }

        // "Name:Gender:Age", e.g. "Marco:Male:30 Y" — same packed-column
        // convention as Investigation-test / Diagnosis / Treatment below.
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
        func entries(_ key: String) -> [String] {
            s(key).components(separatedBy: ";;").map(\.trimmed).filter { !$0.isEmpty }
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

        // Presenting vitals — each optional; drop the object if all are blank.
        let vitals: [String: String] = [
            "bp": s("BP"), "pr": s("PR"), "rr": s("RR"),
            "spo2": s("SpO2"), "temperature": s("Temperature"),
        ].filter { !$0.value.isEmpty }
        if !vitals.isEmpty { dict["vitals"] = vitals }

        dict["history"] = ["bullets": historyBullets, "mentor": ""]
        let examBullets = bullets("Physical Examination")
        if !examBullets.isEmpty { dict["examination"] = ["bullets": examBullets, "mentor": ""] }

        dict["tests"] = try entries("Investigation - test").map { entry -> [String: Any] in
            let parts = entry.components(separatedBy: ":")
            guard parts.count >= 2 else { throw RowError.field("Investigation - test entry '\(entry)' needs at least Category:Name") }
            return [
                "category": parts[0].trimmed, "name": parts[1].trimmed,
                "result": parts.count > 2 ? parts[2].trimmed : "",
                "helpful": parts.count > 3 ? parts[3].trimmed.uppercased().hasPrefix("Y") : false,
                "mentor": parts.count > 4 ? parts[4...].joined(separator: ":").trimmed : "",
            ]
        }

        let diagnoses = try entries("Diagnosis").map { entry -> [String: Any] in
            let parts = entry.components(separatedBy: ":")
            guard let name = parts.first?.trimmed, !name.isEmpty else {
                throw RowError.field("Diagnosis entry '\(entry)' needs a Name:Y/N")
            }
            let correct = parts.count > 1 && parts[1].trimmed.uppercased().hasPrefix("Y")
            return ["name": name, "correct": correct]
        }
        guard diagnoses.count >= 2 else { throw RowError.field("needs at least 2 Diagnosis entries") }
        guard diagnoses.contains(where: { ($0["correct"] as? Bool) == true }) else {
            throw RowError.field("one Diagnosis entry must be marked Y (correct)")
        }
        dict["diagnoses"] = diagnoses

        dict["treatments"] = try entries("Treatment").map { entry -> [String: Any] in
            let parts = entry.components(separatedBy: ":")
            guard parts.count >= 2 else { throw RowError.field("Treatment entry '\(entry)' needs at least Category:Name") }
            return [
                "category": parts[0].trimmed, "name": parts[1].trimmed,
                "appropriate": parts.count > 2 ? parts[2].trimmed.uppercased().hasPrefix("Y") : false,
            ]
        }

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
