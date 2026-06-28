import SwiftUI

// MARK: - Admin-uploaded content models

/// A clinical case scheduled to be the Daily Case on a specific calendar day.
struct DailyCase: Identifiable, Codable {
    var id = UUID()
    var clinicalCase: ClinicalCase
    var date: Date
    /// The GMT day index this case belongs to.
    var dayKey: Int { AppState.gmtDay(date) }
    var dateLabel: String {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "GMT"); f.dateFormat = "EEE, MMM d, yyyy"
        return f.string(from: date)
    }
}

/// A case pushed to users as an "emergency" at a scheduled date & local time.
struct EmergencyCase: Identifiable, Codable {
    var id = UUID()
    var clinicalCase: ClinicalCase
    var fireDate: Date

    var timeLabel: String { fireDate.formatted(date: .abbreviated, time: .shortened) }

    /// An emergency is only live for 3 hours after it fires, then it vanishes.
    static let activeWindow: TimeInterval = 3 * 3600
    var expiry: Date { fireDate.addingTimeInterval(Self.activeWindow) }
    var isActive: Bool { let now = Date(); return now >= fireDate && now < expiry }
}

// MARK: - Content store (local JSON persistence)

/// Holds everything the admin uploads and persists it to a JSON file in the
/// app's Documents directory. Injected app-wide so Home / Learning can surface
/// uploaded content alongside the built-in seed data.
@MainActor
final class ContentStore: ObservableObject {
    @Published private(set) var clinicalCases: [ClinicalCase] = []
    /// Daily cases, each pinned to a calendar day.
    @Published private(set) var dailyCases: [DailyCase] = []
    @Published private(set) var emergencies: [EmergencyCase] = []

    private struct Payload: Codable {
        var clinical: [ClinicalCase] = []
        var daily: [DailyCase] = []
        var emergencies: [EmergencyCase] = []
    }

    /// The case scheduled for a given GMT day, if any.
    func dailyCase(forDay day: Int) -> ClinicalCase? {
        dailyCases.first { $0.dayKey == day }?.clinicalCase
    }

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("cortex_content.json")
    }()

    init() { load() }

    // MARK: Mutations
    func addClinical(_ c: ClinicalCase) { clinicalCases.insert(c, at: 0); save() }
    func deleteClinical(_ c: ClinicalCase) { clinicalCases.removeAll { $0.id == c.id }; save() }
    func updateClinical(_ c: ClinicalCase) { if let i = clinicalCases.firstIndex(where: { $0.id == c.id }) { clinicalCases[i] = c; save() } }

    func addDaily(_ d: DailyCase) { dailyCases.insert(d, at: 0); save() }
    func deleteDaily(_ d: DailyCase) { dailyCases.removeAll { $0.id == d.id }; save() }
    func updateDaily(_ d: DailyCase) { if let i = dailyCases.firstIndex(where: { $0.id == d.id }) { dailyCases[i] = d; save() } }

    // MARK: Emergencies
    func emergency(id: UUID) -> EmergencyCase? { emergencies.first { $0.id == id } }

    /// Replace the live emergencies with the ones pulled from the server (player
    /// side). These drive the Home "emergency" card; locally-scheduled ones (admin
    /// authoring) keep their own notifications and are left untouched here.
    func setServerEmergencies(_ list: [EmergencyCase]) {
        emergencies = list
        save()
    }

    /// Schedule an emergency from a fully-built clinical case (same authoring
    /// format as a regular clinical case) and fire a local notification at `date`.
    @discardableResult
    func scheduleEmergency(case clinicalCase: ClinicalCase, at date: Date) -> EmergencyCase {
        let ec = EmergencyCase(clinicalCase: clinicalCase, fireDate: date)
        emergencies.insert(ec, at: 0)
        save()
        NotificationManager.shared.scheduleEmergency(id: ec.id, at: date)
        return ec
    }

    func cancelEmergency(_ ec: EmergencyCase) {
        NotificationManager.shared.cancel(id: ec.id)
        emergencies.removeAll { $0.id == ec.id }
        save()
    }

    // MARK: Server sync (authoritative)

    /// Make the local cache mirror the authoritative server content. The freshly
    /// fetched `clinical` / `daily` cases each carry their server `remote` id.
    /// Cases still present on the server keep their existing *local* id (so the
    /// player's solved-state and in-flight selection stay stable); cases that
    /// were deleted on the server disappear here too; brand-new cases are added.
    /// Call this only with a successful fetch — never on a network failure, or
    /// it would wrongly wipe everything.
    func setServerContent(clinical fresh: [ClinicalCase], daily freshDaily: [DailyCase]) {
        var existing: [String: ClinicalCase] = [:]
        for c in clinicalCases { if let rid = c.remote?.id { existing[rid] = c } }
        clinicalCases = fresh.map { f in
            if let rid = f.remote?.id, let keep = existing[rid] { return keep }
            return f
        }

        var existingDaily: [String: DailyCase] = [:]
        for d in dailyCases { if let rid = d.clinicalCase.remote?.id { existingDaily[rid] = d } }
        dailyCases = freshDaily.map { f in
            if let rid = f.clinicalCase.remote?.id, let keep = existingDaily[rid] { return keep }
            return f
        }
        save()
    }

    /// Bulk-import a JSON document (see ContentImport.swift for the format).
    /// Validates every item up-front and only commits if all parse cleanly,
    /// so a single bad entry never leaves a half-finished import.
    @discardableResult
    func importJSON(_ text: String) throws -> ImportSummary {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { throw ImportError.empty }

        let payload: ImportPayload
        do { payload = try JSONDecoder().decode(ImportPayload.self, from: data) }
        catch { throw ImportError.parse(error.localizedDescription) }

        let newCases = try (payload.clinical ?? []).enumerated()
            .map { try $0.element.toModel("Clinical case #\($0.offset + 1)") }
        let newDaily = try (payload.daily ?? []).enumerated()
            .map { try $0.element.toModel("Daily case #\($0.offset + 1)") }
        let newEmergencies = try (payload.emergencies ?? []).enumerated()
            .map { try $0.element.toModel("Emergency case #\($0.offset + 1)") }

        let summary = ImportSummary(clinical: newCases.count, daily: newDaily.count,
                                    emergencies: newEmergencies.count)
        guard summary.total > 0 else { throw ImportError.nothing }

        clinicalCases.insert(contentsOf: newCases, at: 0)
        dailyCases.insert(contentsOf: newDaily, at: 0)
        // Each emergency fires at its sendAt time and stays live for 3 hours.
        for ec in newEmergencies { _ = scheduleEmergency(case: ec.clinicalCase, at: ec.fireDate) }
        save()
        return summary
    }

    // MARK: Persistence
    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        clinicalCases = payload.clinical
        dailyCases = payload.daily
        emergencies = payload.emergencies
    }

    private func save() {
        let payload = Payload(clinical: clinicalCases, daily: dailyCases, emergencies: emergencies)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
