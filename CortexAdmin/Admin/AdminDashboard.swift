import SwiftUI

/// The admin console — only reachable through the PIN gate. Lets the admin
/// create clinical cases and emergencies, and review/delete what has been
/// uploaded.
struct AdminDashboard: View {
    @EnvironmentObject var store: ContentStore
    @EnvironmentObject var sb: SupabaseService
    @Environment(\.dismiss) private var dismiss
    @State private var showTestAlert = false

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
                    createLink("Emergency case", "cross.case.fill", .red) { EmergencyForm() }
                    Button {
                        store.scheduleEmergency(case: Seed.demoEmergency, at: Date())
                        showTestAlert = true
                    } label: {
                        Label("Trigger test emergency now", systemImage: "bolt.heart.fill")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Push")
                } footer: {
                    Text(store.emergencies.isEmpty
                         ? "Schedule a 🚨 emergency case, or trigger a live test one on the Home tab right now."
                         : "\(store.emergencies.count) emergency case(s) on this device.")
                }

                Section {
                    createLink("Cloud sync", "icloud.fill", CX.teal) { CloudSyncView() }
                } footer: {
                    Text(cloudFooter)
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
        .alert("Test emergency live", isPresented: $showTestAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("Close the Admin Console and open the Home tab — the emergency is active now for 3 hours.")
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
