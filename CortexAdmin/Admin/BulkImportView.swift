import SwiftUI
import UniformTypeIdentifiers

/// Lets the admin bulk-upload clinical cases by pasting JSON or importing a
/// .json file. Includes a copy-paste-ready template.
struct BulkImportView: View {
    @EnvironmentObject var store: ContentStore
    @EnvironmentObject var sb: SupabaseService
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var showFileImporter = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var didSucceed = false
    @State private var publishing = false

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 220)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Paste your JSON here…")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("Paste JSON")
            } footer: {
                Text("A JSON object with \"clinical\", \"daily\" (each with a \"date\") and/or \"emergencies\" (each with a \"sendAt\") arrays. Each case uses \"presentation\", \"history\" and \"examination\" sections (Chief Complaint → History → Physical Examination). IDs are generated automatically.")
            }

            Section {
                Button { showFileImporter = true } label: {
                    Label("Import a .json file", systemImage: "doc.badge.plus")
                }
                Button { text = JSONTemplates.clinical } label: {
                    Label("Load full example", systemImage: "text.badge.star")
                }
                if !text.isEmpty {
                    Button(role: .destructive) { text = "" } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
            }

            Section {
                Button { runImport() } label: {
                    Label("Import to this device", systemImage: "square.and.arrow.down.fill")
                        .fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .disabled(text.trimmed.isEmpty)
                .listRowBackground(text.trimmed.isEmpty ? Color.gray.opacity(0.3) : CX.orange)
                .foregroundStyle(.white)
            }

            if sb.isConfigured {
                Section {
                    Button { publish() } label: {
                        HStack {
                            if publishing { ProgressView() }
                            Label("Publish to all users", systemImage: "icloud.and.arrow.up.fill")
                                .fontWeight(.semibold)
                        }.frame(maxWidth: .infinity)
                    }
                    .disabled(text.trimmed.isEmpty || !sb.isAdminSignedIn || publishing)
                    .listRowBackground(text.trimmed.isEmpty || !sb.isAdminSignedIn ? Color.gray.opacity(0.3) : CX.teal)
                    .foregroundStyle(.white)
                } footer: {
                    Text(sb.isAdminSignedIn ? "Sends this JSON to every user via the backend."
                                            : "Sign in under Cloud sync to publish to all users.")
                }
            }

            Section("Format reference — tap to copy") {
                templateRow("Clinical case", JSONTemplates.clinical)
                templateRow("Daily case", JSONTemplates.daily)
                templateRow("Emergency case", JSONTemplates.emergency)
            }
        }
        .navigationTitle("Bulk Import")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            handleFile(result)
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") { if didSucceed { dismiss() } }
        } message: { Text(alertMessage) }
    }

    private func templateRow(_ title: String, _ json: String) -> some View {
        DisclosureGroup(title) {
            Text(json).font(.system(.caption2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button { UIPasteboard.general.string = json } label: {
                Label("Copy template", systemImage: "doc.on.doc")
            }.font(.footnote)
        }
    }

    private func runImport() {
        do {
            let summary = try store.importJSON(text)
            didSucceed = true
            alertTitle = "Import complete"
            alertMessage = summary.text
        } catch {
            didSucceed = false
            alertTitle = "Import failed"
            alertMessage = error.localizedDescription
        }
        showAlert = true
    }

    private func publish() {
        publishing = true
        Task {
            do {
                let payload = try JSONDecoder().decode(ImportPayload.self, from: Data(text.trimmed.utf8))
                let n = try await sb.publish(payload)
                didSucceed = false   // keep screen open; this isn't a local import
                alertTitle = "Published"; alertMessage = "Sent \(n) item(s) to all users."
            } catch {
                didSucceed = false
                alertTitle = "Publish failed"; alertMessage = error.localizedDescription
            }
            showAlert = true
            publishing = false
        }
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) {
            text = s
        } else {
            alertTitle = "Couldn't read file"; alertMessage = "The file couldn't be read as text."
            didSucceed = false; showAlert = true
        }
    }
}

// MARK: - Copy-paste templates

enum JSONTemplates {
    static let clinical = """
    {
      "clinical": [
        {
          "specialty": "Dermatology",
          "patientName": "Marco",
          "gender": "Male",
          "age": "30 Y",
          "chiefComplaint": "Itchy scaly plaques on elbows",
          "presentation": {
            "bullets": ["30M with itchy plaques on the extensor elbows", "Worse in winter"],
            "mentor": "Extensor distribution is a clue."
          },
          "history": {
            "bullets": ["Symptoms for 6 months", "Family history of psoriasis"],
            "mentor": "Family history supports psoriasis."
          },
          "examination": {
            "bullets": ["Well-demarcated silvery plaques", "Auspitz sign positive"],
            "mentor": "Silvery scale with Auspitz sign suggests psoriasis."
          },
          "tests": [
            { "category": "Clinical", "name": "Skin exam",
              "result": "Auspitz sign positive", "helpful": true,
              "mentor": "Supports psoriasis." }
          ],
          "diagnosisQuestion": "Best diagnosis?",
          "diagnoses": [
            { "name": "Plaque psoriasis", "correct": true },
            { "name": "Eczema", "correct": false }
          ],
          "treatments": [
            { "category": "Topical", "name": "Topical steroid", "appropriate": true },
            { "category": "Antibiotics", "name": "Oral antibiotics", "appropriate": false }
          ],
          "outcomeTitle": "Nailed it!",
          "outcomeBody": "Extensor silvery plaques is classic psoriasis.",
          "xpReward": 20
        }
      ]
    }
    """

    // Daily and Emergency reuse the same case body ("case") as clinical, plus a
    // schedule field: daily has "date" (the day it appears), emergency has
    // "sendAt" (when it goes live; stays for 3 hours).
    static let daily = """
    {
      "daily": [
        {
          "date": "2026-06-22",
          "case": {
            "specialty": "Cardiology",
            "patientName": "Rosa",
            "gender": "Female",
            "age": "62 Y",
            "chiefComplaint": "Crushing chest pain radiating to the left arm",
            "presentation": { "bullets": ["62F, sudden crushing chest pain", "Radiates to left arm"],
              "mentor": "Classic anginal description." },
            "history": { "bullets": ["Pain for 40 min", "Sweating, nausea"],
              "mentor": "Autonomic features suggest ischaemia." },
            "examination": { "bullets": ["Diaphoretic", "BP 100/70, HR 90"],
              "mentor": "Check for haemodynamic compromise." },
            "tests": [
              { "category": "Cardiac", "name": "ECG", "result": "ST elevation in II, III, aVF",
                "helpful": true, "mentor": "Inferior STEMI." }
            ],
            "diagnosisQuestion": "Best diagnosis?",
            "diagnoses": [
              { "name": "Inferior STEMI", "correct": true },
              { "name": "Pericarditis", "correct": false }
            ],
            "treatments": [
              { "category": "Reperfusion", "name": "Primary PCI", "appropriate": true }
            ],
            "outcomeTitle": "Sharp call!",
            "outcomeBody": "ST elevation in the inferior leads is a STEMI needing urgent PCI.",
            "xpReward": 25
          }
        }
      ]
    }
    """  // "date" is the GMT calendar day (YYYY-MM-DD); omit to use today.

    static let emergency = """
    {
      "emergencies": [
        {
          "sendAt": "2026-06-22T20:00:00Z",
          "case": {
            "specialty": "Acute Care & Surgery",
            "patientName": "Khalil",
            "gender": "Male",
            "age": "24 Y",
            "chiefComplaint": "Found unresponsive at home, rapid breathing",
            "presentation": { "bullets": ["24M found unresponsive", "Rapid breathing"],
              "mentor": "Reduced consciousness with abnormal breathing — act fast." },
            "history": { "bullets": ["Friends report recreational drug use", "No trauma"],
              "mentor": "History of drug use raises overdose suspicion." },
            "examination": { "bullets": ["GCS 9", "RR 30", "Pinpoint pupils"],
              "mentor": "Pinpoint pupils with low GCS suggests opioid toxicity." },
            "tests": [
              { "category": "Bedside", "name": "Capillary glucose", "result": "Normal",
                "helpful": true, "mentor": "Rules out hypoglycaemia." }
            ],
            "diagnosisQuestion": "Most likely cause?",
            "diagnoses": [
              { "name": "Opioid overdose", "correct": true },
              { "name": "Stroke", "correct": false }
            ],
            "treatments": [
              { "category": "Antidote", "name": "Naloxone", "appropriate": true },
              { "category": "Other", "name": "Observe only", "appropriate": false }
            ],
            "outcomeTitle": "Life saved!",
            "outcomeBody": "Naloxone reverses opioid-induced respiratory depression.",
            "xpReward": 30
          }
        }
      ]
    }
    """  // "sendAt" is ISO-8601 UTC; omit to go live now. Emergencies stay for 3 hours.
}
