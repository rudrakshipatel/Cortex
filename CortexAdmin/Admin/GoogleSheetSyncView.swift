import SwiftUI

/// Pulls new rows from a Google Sheet and runs them through the exact same
/// import/publish pipeline as Bulk Import. Rows already imported or published
/// (tracked by their sheet `ID`) are hidden on future fetches, so the admin
/// can keep authoring in one continuous sheet.
struct GoogleSheetSyncView: View {
    @EnvironmentObject var store: ContentStore
    @EnvironmentObject var sb: SupabaseService
    @ObservedObject private var sheets = GoogleSheetsService.shared

    @State private var fetching = false
    @State private var newRows: [GoogleSheetsService.Row] = []
    @State private var warnings: [String] = []
    @State private var failed: [(id: String, reason: String)] = []
    @State private var importing = false
    @State private var publishing = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        Form {
            Section {
                TextField("Sheet URL or ID", text: $sheets.sheetURLOrID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Tab name", text: $sheets.tabName)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("API key", text: $sheets.apiKey)
            } header: {
                Text("Google Sheet")
            } footer: {
                Text("Share the sheet as \"Anyone with the link — Viewer\", enable the Sheets API in Google Cloud Console, and create an API key restricted to it. Row content becomes readable by anyone with the link, so keep sensitive data out of the sheet.")
            }

            Section {
                Button { fetch() } label: {
                    HStack {
                        if fetching { ProgressView() }
                        Label("Fetch new rows", systemImage: "arrow.triangle.2.circlepath")
                            .fontWeight(.semibold)
                    }.frame(maxWidth: .infinity)
                }
                .disabled(!sheets.isConfigured || fetching)
                .listRowBackground(!sheets.isConfigured ? Color.gray.opacity(0.3) : CX.gold)
                .foregroundStyle(.white)
            } footer: {
                Text(sheets.syncedIDs.isEmpty ? "No rows synced yet."
                     : "\(sheets.syncedIDs.count) row(s) already synced and hidden.")
            }

            if !sheets.syncedIDs.isEmpty {
                Section {
                    Button(role: .destructive) { sheets.resetSynced() } label: {
                        Label("Reset synced rows", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("Forgets which rows were already synced — the next fetch will show all of them again. Doesn't delete or unpublish anything.")
                }
            }

            if !newRows.isEmpty {
                Section("New rows · \(newRows.count)") {
                    ForEach(newRows) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(row.id) · \(row.fields["PatientName"] ?? "") · \(row.fields["Specialty"] ?? "")")
                                .font(.subheadline.weight(.semibold))
                            Text((row.fields["Type"] ?? "clinical").capitalized)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button { runImport() } label: {
                        HStack {
                            if importing { ProgressView() }
                            Label("Import new rows to this device", systemImage: "square.and.arrow.down.fill")
                                .fontWeight(.semibold)
                        }.frame(maxWidth: .infinity)
                    }
                    .disabled(importing || publishing)
                    .listRowBackground(CX.orange)
                    .foregroundStyle(.white)
                }

                if sb.isConfigured {
                    Section {
                        Button { runPublish() } label: {
                            HStack {
                                if publishing { ProgressView() }
                                Label("Publish new rows to all users", systemImage: "icloud.and.arrow.up.fill")
                                    .fontWeight(.semibold)
                            }.frame(maxWidth: .infinity)
                        }
                        .disabled(!sb.isAdminSignedIn || importing || publishing)
                        .listRowBackground(!sb.isAdminSignedIn ? Color.gray.opacity(0.3) : CX.teal)
                        .foregroundStyle(.white)
                    } footer: {
                        Text(sb.isAdminSignedIn ? "Sends these rows to every user via the backend."
                                                : "Sign in under Cloud sync to publish to all users.")
                    }
                }
            }

            if !warnings.isEmpty || !failed.isEmpty {
                Section("Skipped rows") {
                    ForEach(warnings, id: \.self) { w in
                        Text(w).font(.caption).foregroundStyle(CX.orange)
                    }
                    ForEach(failed, id: \.id) { f in
                        Text("\(f.id): \(f.reason)").font(.caption).foregroundStyle(CX.orange)
                    }
                }
            }
        }
        .navigationTitle("Google Sheet Sync")
        .navigationBarTitleDisplayMode(.inline)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: { Text(alertMessage) }
    }

    private func fetch() {
        fetching = true
        Task {
            defer { fetching = false }
            do {
                let (rows, warn) = try await sheets.fetchRows()
                newRows = rows.filter { !sheets.syncedIDs.contains($0.id) }
                warnings = warn
                failed = []
                if newRows.isEmpty {
                    alertTitle = "No new rows"
                    alertMessage = warn.isEmpty ? "Every row in the sheet has already been synced."
                                                 : "No new rows. \(warn.count) row(s) were skipped — see below."
                    showAlert = true
                }
            } catch {
                alertTitle = "Fetch failed"
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }

    private func runImport() {
        let (json, badRows) = sheets.buildImportJSON(from: newRows)
        failed = badRows
        let goodIDs = newRows.map(\.id).filter { id in !badRows.contains { $0.id == id } }
        guard !goodIDs.isEmpty else {
            alertTitle = "Nothing to import"; alertMessage = "Every fetched row failed to convert — see Skipped rows."
            showAlert = true
            return
        }
        importing = true
        do {
            let summary = try store.importJSON(json)
            sheets.markSynced(goodIDs)
            newRows.removeAll { id in goodIDs.contains(id.id) }
            alertTitle = "Import complete"; alertMessage = summary.text
        } catch {
            alertTitle = "Import failed"; alertMessage = error.localizedDescription
        }
        importing = false
        showAlert = true
    }

    private func runPublish() {
        let (json, badRows) = sheets.buildImportJSON(from: newRows)
        failed = badRows
        let goodIDs = newRows.map(\.id).filter { id in !badRows.contains { $0.id == id } }
        guard !goodIDs.isEmpty else {
            alertTitle = "Nothing to publish"; alertMessage = "Every fetched row failed to convert — see Skipped rows."
            showAlert = true
            return
        }
        publishing = true
        Task {
            defer { publishing = false }
            do {
                let payload = try JSONDecoder().decode(ImportPayload.self, from: Data(json.utf8))
                let n = try await sb.publish(payload)
                sheets.markSynced(goodIDs)
                newRows.removeAll { id in goodIDs.contains(id.id) }
                alertTitle = "Published"; alertMessage = "Sent \(n) item(s) to all users."
            } catch {
                alertTitle = "Publish failed"; alertMessage = error.localizedDescription
            }
            showAlert = true
        }
    }
}
