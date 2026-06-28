import SwiftUI

// MARK: - Manage published content
//
// Edit or delete the clinical, daily and emergency cases that are LIVE on the
// server for all players. Unlike the "Add …" forms (which only save to this
// device) and Bulk Import (which only inserts), this screen reads the real
// server rows by id and PATCHes / DELETEs them — so changes reach every user
// on their next sync. Reachable from the Admin Console.

struct ManageContentView: View {
    @EnvironmentObject var sb: SupabaseService
    @State private var cases: [SupabaseService.AdminCaseRow] = []
    @State private var emergencies: [SupabaseService.AdminEmergencyRow] = []
    @State private var loading = false
    @State private var error: String?

    private var clinical: [SupabaseService.AdminCaseRow] { cases.filter { $0.kind == "clinical" } }
    private var daily: [SupabaseService.AdminCaseRow]    { cases.filter { $0.kind == "daily" } }

    var body: some View {
        List {
            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            if !sb.isAdminSignedIn {
                Section { Text("Sign in under Cloud sync to manage live content.").foregroundStyle(.secondary) }
            }

            Section("Clinical · \(clinical.count)") {
                if clinical.isEmpty { emptyRow("No clinical cases published") }
                ForEach(clinical) { row in
                    NavigationLink {
                        EditPublishedCase(row: row, reload: reload)
                    } label: { caseLabel(row.clinicalCase, subtitle: row.clinicalCase.chiefComplaint) }
                }
                .onDelete { remove(clinical, at: $0, delete: sb.deletePublishedCase) }
            }

            Section("Daily · \(daily.count)") {
                if daily.isEmpty { emptyRow("No daily cases published") }
                ForEach(daily) { row in
                    NavigationLink {
                        EditPublishedCase(row: row, reload: reload)
                    } label: { caseLabel(row.clinicalCase, subtitle: dailySubtitle(row)) }
                }
                .onDelete { remove(daily, at: $0, delete: sb.deletePublishedCase) }
            }

            Section("Emergency · \(emergencies.count)") {
                if emergencies.isEmpty { emptyRow("No emergencies published") }
                ForEach(emergencies) { row in
                    NavigationLink {
                        EditPublishedEmergency(row: row, reload: reload)
                    } label: { caseLabel(row.clinicalCase,
                                         subtitle: "Fires \(row.fireDate.formatted(date: .abbreviated, time: .shortened))") }
                }
                .onDelete { idx in
                    let targets = idx.map { emergencies[$0] }
                    emergencies.remove(atOffsets: idx)
                    Task { for t in targets { try? await sb.deletePublishedEmergency(id: t.id) }; await load() }
                }
            }
        }
        .navigationTitle("Published content")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .overlay { if loading && cases.isEmpty && emergencies.isEmpty { ProgressView() } }
        .refreshable { await load() }
        .onAppear { reload() }
    }

    // MARK: Rows
    private func caseLabel(_ c: ClinicalCase, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(c.patientName) · \(c.specialty)").font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
    private func dailySubtitle(_ row: SupabaseService.AdminCaseRow) -> String {
        guard let d = row.date else { return row.clinicalCase.chiefComplaint }
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "GMT"); f.dateFormat = "EEE, MMM d, yyyy"
        return "Appears \(f.string(from: d)) (GMT)"
    }
    private func emptyRow(_ t: String) -> some View {
        Text(t).font(.subheadline).foregroundStyle(.secondary)
    }

    // MARK: Loading & deletion
    private func reload() { Task { await load() } }

    private func load() async {
        guard sb.isAdminSignedIn else { cases = []; emergencies = []; return }
        loading = true; defer { loading = false }
        do {
            async let c = sb.fetchPublishedCases()
            async let e = sb.fetchPublishedEmergencies()
            cases = try await c
            emergencies = try await e
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Optimistically drop the swiped rows, delete them server-side, then refresh.
    private func remove(_ source: [SupabaseService.AdminCaseRow], at offsets: IndexSet,
                        delete: @escaping (String) async throws -> Void) {
        let targets = offsets.map { source[$0] }
        cases.removeAll { row in targets.contains { $0.id == row.id } }
        Task { for t in targets { try? await delete(t.id) }; await load() }
    }
}

// MARK: - Edit a published clinical / daily case

private struct EditPublishedCase: View {
    @EnvironmentObject var sb: SupabaseService
    @Environment(\.dismiss) private var dismiss
    let row: SupabaseService.AdminCaseRow
    let reload: () -> Void

    @State private var draft: CaseDraft
    @State private var date: Date
    @State private var saving = false
    @State private var error: String?

    init(row: SupabaseService.AdminCaseRow, reload: @escaping () -> Void) {
        self.row = row
        self.reload = reload
        _draft = State(initialValue: CaseDraft(from: row.clinicalCase))
        _date = State(initialValue: row.date ?? Date())
    }

    private var isDaily: Bool { row.kind == "daily" }

    var body: some View {
        CaseEditor(draft: $draft, header: {
            if isDaily {
                Section {
                    DatePicker("Appears on", selection: $date, displayedComponents: [.date])
                } header: { Text("Daily date") }
                footer: { Text("This case is the Daily Case on this calendar day (GMT).") }
            }
            if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
        })
        .navigationTitle(isDaily ? "Edit Daily Case" : "Edit Clinical Case")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!draft.isValid || saving)
            }
        }
    }

    private func save() {
        saving = true
        let c = draft.build()
        Task {
            defer { saving = false }
            do {
                if isDaily { try await sb.updatePublishedDaily(id: row.id, case: c, date: date) }
                else       { try await sb.updatePublishedClinical(id: row.id, case: c) }
                reload()
                dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

// MARK: - Edit a published emergency

private struct EditPublishedEmergency: View {
    @EnvironmentObject var sb: SupabaseService
    @Environment(\.dismiss) private var dismiss
    let row: SupabaseService.AdminEmergencyRow
    let reload: () -> Void

    @State private var draft: CaseDraft
    @State private var fireDate: Date
    @State private var saving = false
    @State private var error: String?

    init(row: SupabaseService.AdminEmergencyRow, reload: @escaping () -> Void) {
        self.row = row
        self.reload = reload
        _draft = State(initialValue: CaseDraft(from: row.clinicalCase))
        _fireDate = State(initialValue: row.fireDate)
    }

    var body: some View {
        CaseEditor(draft: $draft, header: {
            Section {
                DatePicker("Goes live at", selection: $fireDate, displayedComponents: [.date, .hourAndMinute])
            } header: { Text("Emergency time") }
            footer: { Text("Fires at this wall-clock time in every user's own timezone, and stays live for 3 hours.") }
            if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
        })
        .navigationTitle("Edit Emergency")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!draft.isValid || saving)
            }
        }
    }

    private func save() {
        saving = true
        let c = draft.build()
        Task {
            defer { saving = false }
            do {
                try await sb.updatePublishedEmergency(id: row.id, case: c, on: fireDate)
                reload()
                dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
