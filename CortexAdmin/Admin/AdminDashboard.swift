import SwiftUI

/// The admin console — only reachable through the PIN gate. Lets the admin
/// create clinical cases and emergencies, and review/delete what has been
/// uploaded.
struct AdminDashboard: View {
    @EnvironmentObject var store: ContentStore
    @EnvironmentObject var sb: SupabaseService
    @Environment(\.dismiss) private var dismiss
    @State private var showTestAlert = false
    @State private var testAlertMsg = ""
    @State private var broadcasting = false

    private var cloudFooter: String {
        guard sb.isConfigured else { return "Connect a backend to broadcast to all users." }
        return sb.isAdminSignedIn
            ? "Signed in as \(sb.adminEmail ?? "admin"). Publishing & emergencies broadcast to all users."
            : "Sign in to publish content and broadcast emergencies to all users."
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    createLink("Add Clinical Case", "stethoscope", CX.orange) { ClinicalCaseForm() }
                    createLink("Add Daily Case", "calendar", CX.teal) { DailyCaseForm() }
                } header: {
                    Text("Upload cases")
                } footer: {
                    Text("Content is saved on this device and appears instantly in Home for users.")
                }

                Section {
                    createLink("Bulk import (JSON)", "square.and.arrow.down.on.square.fill", CX.gold) { BulkImportView() }
                } footer: {
                    Text("Paste or import a .json file to add many cases at once.")
                }

                Section {
                    createLink("Sync from Google Sheet", "tablecells", CX.gold) { GoogleSheetSyncView() }
                } footer: {
                    Text("Author cases in a shared Google Sheet, then fetch and publish new rows. Already-synced rows are skipped automatically.")
                }

                Section {
                    createLink("Emergency case", "cross.case.fill", .red) { EmergencyForm() }
                    Button { broadcastLiveNow() } label: {
                        HStack {
                            Label("Broadcast live emergency now", systemImage: "bolt.heart.fill")
                                .foregroundStyle(.red)
                            if broadcasting { Spacer(); ProgressView() }
                        }
                    }.disabled(broadcasting)
                } header: {
                    Text("Push")
                } footer: {
                    Text(sb.isAdminSignedIn
                         ? "Broadcasts a 🚨 emergency to ALL signed-in players right now (live for 3 hours)."
                         : "Sign in under Cloud sync first — that's how emergencies reach players.")
                }

                Section {
                    createLink("Cloud sync", "icloud.fill", CX.teal) { CloudSyncView() }
                } footer: {
                    Text(cloudFooter)
                }

                Section {
                    createLink("Manage published content", "square.and.pencil", CX.navy) { ManageContentView() }
                } footer: {
                    Text("Edit or delete the clinical, daily and emergency cases that are live on the server for all users.")
                }

                Section("Clinical cases · \(store.clinicalCases.count)") {
                    if store.clinicalCases.isEmpty { emptyRow("No clinical cases yet") }
                    ForEach(store.clinicalCases) { c in
                        NavigationLink {
                            ClinicalCaseForm(editing: c).environmentObject(store)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(c.patientName) · \(c.specialty)").font(.subheadline.weight(.semibold))
                                Text(c.chiefComplaint).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .onDelete { idx in idx.map { store.clinicalCases[$0] }.forEach(store.deleteClinical) }
                }

                Section("Daily cases · \(store.dailyCases.count)") {
                    if store.dailyCases.isEmpty { emptyRow("No daily cases yet") }
                    ForEach(store.dailyCases) { d in
                        NavigationLink {
                            DailyCaseForm(editing: d).environmentObject(store)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(d.dateLabel) · \(d.clinicalCase.specialty)").font(.subheadline.weight(.semibold))
                                Text("\(d.clinicalCase.patientName) — \(d.clinicalCase.chiefComplaint)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .onDelete { idx in idx.map { store.dailyCases[$0] }.forEach(store.deleteDaily) }
                }
            }
            .navigationTitle("Admin Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
        }
        .tint(CX.orange)
        .alert("Emergency", isPresented: $showTestAlert) {
            Button("OK") {}
        } message: {
            Text(testAlertMsg)
        }
    }

    /// Broadcast a demo emergency to ALL players, live right now (3-hour window).
    private func broadcastLiveNow() {
        guard sb.isConfigured, sb.isAdminSignedIn else {
            testAlertMsg = "Sign in under Cloud sync first — that's how the emergency reaches players."
            showTestAlert = true
            return
        }
        broadcasting = true
        Task {
            defer { broadcasting = false }
            do {
                try await sb.broadcastEmergency(case: Seed.demoEmergency, on: Date())
                testAlertMsg = "🚨 Live! Every signed-in player gets the alert (and the Home card) within about a minute, or the moment they next open the app. Active for 3 hours."
            } catch {
                testAlertMsg = "Couldn't broadcast: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            }
            showTestAlert = true
        }
    }

    private func createLink<D: View>(_ title: String, _ icon: String, _ color: Color,
                                     @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink {
            dest().environmentObject(store).environmentObject(SupabaseService.shared)
        } label: {
            Label {
                Text(title).fontWeight(.semibold)
            } icon: {
                Image(systemName: icon).foregroundStyle(color)
            }
        }
    }

    private func emptyRow(_ t: String) -> some View {
        Text(t).font(.subheadline).foregroundStyle(.secondary)
    }
}
