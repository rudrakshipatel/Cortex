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
                Text("A JSON object with \"clinical\", \"daily\" (each with a \"date\") and/or \"emergencies\" (each with a \"sendAt\") arrays. Each case uses \"presentation\", \"history\" and \"examination\" sections (Chief Complaint → History → Physical Examination) — a section can list flat \"bullets\" and/or system \"groups\" (e.g. { \"system\": \"Cardiovascular\", \"findings\": [...] }), and \"mentor\" hints show only on History & Physical Examination. Each test may carry an optional \"imageURL\" (a public image shown under its result — upload one from a Clinical Case form to get the URL). Optional per-case fields: \"vitals\" (bp, pr, rr, spo2, temperature, bmi), \"occupation\", \"duration\", \"title\", \"difficulty\" (1–5), and a \"mentorInsight\" object (reasoning, differentials, testRationale, treatmentSequencing, pearls, pitfalls, learningPoints). IDs are generated automatically. Tap \"Load full example\" for a complete case.")
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
          "title": "Heart Failure with Reduced Ejection Fraction (HFrEF)",
          "specialty": "Cardiology",
          "difficulty": 1,
          "patientName": "Michael Johnson",
          "gender": "Male",
          "age": "68 Y",
          "occupation": "Retired school teacher",
          "chiefComplaint": "I've been getting more short of breath over the last few days.",
          "duration": "5 days",
          "vitals": {
            "temperature": "98.9°F (37.2°C)",
            "bp": "168/92 mmHg",
            "pr": "108 bpm",
            "rr": "24/min",
            "spo2": "89% on room air",
            "bmi": "31 kg/m²"
          },
          "presentation": {
            "bullets": [
              "68M, retired school teacher",
              "Chief complaint: progressive shortness of breath",
              "Duration: 5 days, now at rest"
            ]
          },
          "history": {
            "bullets": [
              "Presenting Complaint: Progressive shortness of breath for 5 days, now at rest.",
              "Orthopnoea: Sleeps on three pillows due to breathlessness when lying flat.",
              "Paroxysmal Nocturnal Dyspnoea: Wakes at night gasping for air nearly every night.",
              "Oedema: Bilateral ankle swelling for one week.",
              "Weight: Gained 5 lb over the past week.",
              "Functional Status: Fatigue and reduced exercise tolerance.",
              "Medication History: Missed several doses of his heart and blood pressure medications over the past month.",
              "Past History: Hypertension, anterior MI (4 years ago), type 2 diabetes.",
              "Review of Systems: No fever, productive cough, pleuritic chest pain, or recent travel.",
              "Social History: Former smoker (30 pack-years), quit 10 years ago."
            ],
            "mentor": "Pay close attention to how the patient's breathing changes with body position and during sleep. Recent weight gain and missed medications may be an important clue to the cause of this episode."
          },
          "examination": {
            "groups": [
              {
                "system": "General",
                "findings": [
                  "Mild respiratory distress",
                  "Speaking in short sentences",
                  "Sitting upright"
                ]
              },
              {
                "system": "Hands",
                "findings": [
                  "Warm extremities",
                  "No cyanosis",
                  "No clubbing"
                ]
              },
              {
                "system": "Neck",
                "findings": [
                  "JVP ≈12 cm H₂O"
                ]
              },
              {
                "system": "Cardiovascular",
                "findings": [
                  "Tachycardia",
                  "Laterally displaced apex beat",
                  "S3 gallop",
                  "No new murmur"
                ]
              },
              {
                "system": "Respiratory",
                "findings": [
                  "Bibasal crackles halfway up both lungs",
                  "Reduced air entry at both bases",
                  "No wheeze"
                ]
              },
              {
                "system": "Abdomen",
                "findings": [
                  "Mild hepatomegaly",
                  "Positive hepatojugular reflux"
                ]
              },
              {
                "system": "Extremities",
                "findings": [
                  "Bilateral 2+ pitting edema to mid-shins"
                ]
              }
            ],
            "mentor": "Elevated JVP, crackles, and leg edema often indicate a common underlying physiological problem. An S3 heart sound is an important clue when assessing patients with dyspnea."
          },
          "tests": [
            {
              "category": "Laboratory",
              "name": "BNP",
              "result": "1,560 pg/mL (elevated)",
              "helpful": true,
              "mentor": "Supports the diagnosis of heart failure."
            },
            {
              "category": "Laboratory",
              "name": "CBC",
              "result": "WBC 7.4, Hb 13.1, Plt 245",
              "helpful": true,
              "mentor": "Assesses for anemia or infection."
            },
            {
              "category": "Laboratory",
              "name": "Comprehensive Metabolic Panel (CMP)",
              "result": "Na 131, K 4.8, Cr 1.4, BUN 30, AST/ALT normal",
              "helpful": true,
              "mentor": "Evaluates renal function and electrolytes before treatment."
            },
            {
              "category": "Laboratory",
              "name": "High-Sensitivity Troponin",
              "result": "18 ng/L (stable)",
              "helpful": true,
              "mentor": "Looks for myocardial ischemia as a trigger."
            },
            {
              "category": "Laboratory",
              "name": "Arterial Blood Gas",
              "result": "Not performed",
              "helpful": false,
              "mentor": "Consider only if severe hypoxemia or respiratory failure develops."
            },
            {
              "category": "Cardiac",
              "name": "ECG",
              "result": "Sinus tachycardia, old anterior Q waves, LVH, no acute ST elevation",
              "helpful": true,
              "mentor": "Detects ischemia or arrhythmias."
            },
            {
              "category": "Cardiac",
              "name": "Transthoracic Echocardiogram",
              "result": "EF 30%, dilated LV, global hypokinesis, mild functional MR",
              "helpful": true,
              "mentor": "Confirms EF and structural abnormalities."
            },
            {
              "category": "Imaging",
              "name": "Chest X-ray",
              "result": "Cardiomegaly, pulmonary vascular congestion, bilateral pulmonary edema, small pleural effusions",
              "helpful": true,
              "mentor": "Identifies pulmonary edema and cardiomegaly."
            },
            {
              "category": "Imaging",
              "name": "CT Pulmonary Angiography",
              "result": "Not performed",
              "helpful": false,
              "mentor": "Not indicated unless PE is strongly suspected."
            },
            {
              "category": "Other",
              "name": "Lower Extremity Venous Doppler",
              "result": "Not performed",
              "helpful": false,
              "mentor": "No clinical evidence of DVT."
            },
            {
              "category": "Other",
              "name": "Sputum Culture",
              "result": "Not performed",
              "helpful": false,
              "mentor": "No evidence of respiratory infection."
            },
            {
              "category": "Other",
              "name": "D-dimer",
              "result": "Not performed",
              "helpful": false,
              "mentor": "Low yield because PE is unlikely."
            }
          ],
          "diagnosisQuestion": "Choose the most likely diagnosis.",
          "diagnoses": [
            {
              "name": "Acute decompensated heart failure with reduced ejection fraction",
              "correct": true
            },
            {
              "name": "COPD exacerbation",
              "correct": false
            },
            {
              "name": "Acute coronary syndrome",
              "correct": false
            },
            {
              "name": "Community-acquired pneumonia",
              "correct": false
            },
            {
              "name": "Pulmonary embolism",
              "correct": false
            },
            {
              "name": "Acute asthma exacerbation",
              "correct": false
            },
            {
              "name": "Chronic kidney disease with fluid overload",
              "correct": false
            },
            {
              "name": "Acute pericarditis",
              "correct": false
            },
            {
              "name": "Hypertensive emergency",
              "correct": false
            },
            {
              "name": "Constrictive pericarditis",
              "correct": false
            }
          ],
          "treatments": [
            {
              "category": "Acute",
              "name": "Oxygen",
              "appropriate": true
            },
            {
              "category": "Acute",
              "name": "IV Furosemide",
              "appropriate": true
            },
            {
              "category": "Acute",
              "name": "Nitroglycerin infusion",
              "appropriate": true
            },
            {
              "category": "Chronic",
              "name": "Empagliflozin (after stabilization)",
              "appropriate": true
            },
            {
              "category": "Chronic",
              "name": "Sacubitril/Valsartan (after stabilization)",
              "appropriate": true
            },
            {
              "category": "Chronic",
              "name": "Metoprolol Succinate (after stabilization)",
              "appropriate": true
            },
            {
              "category": "Chronic",
              "name": "Spironolactone",
              "appropriate": true
            },
            {
              "category": "General",
              "name": "Sodium and Fluid Restriction",
              "appropriate": true
            },
            {
              "category": "Other",
              "name": "Digoxin",
              "appropriate": false
            },
            {
              "category": "Other",
              "name": "Lisinopril",
              "appropriate": false
            },
            {
              "category": "Other",
              "name": "Hydralazine + Isosorbide Dinitrate",
              "appropriate": false
            },
            {
              "category": "Other",
              "name": "Therapeutic anticoagulation",
              "appropriate": false
            },
            {
              "category": "Other",
              "name": "IV Antibiotics",
              "appropriate": false
            },
            {
              "category": "Other",
              "name": "Nebulized Albuterol",
              "appropriate": false
            },
            {
              "category": "Other",
              "name": "Large-volume IV Normal Saline",
              "appropriate": false
            },
            {
              "category": "Other",
              "name": "Immediate discharge home",
              "appropriate": false
            }
          ],
          "outcomeTitle": "Sharp call!",
          "outcomeBody": "Orthopnoea, PND, elevated JVP, an S3 gallop and pulmonary edema with a markedly raised BNP point to acute decompensated HFrEF (EF 30%). Treat congestion first, then start guideline-directed therapy once stable.",
          "xpReward": 25,
          "mentorInsight": {
            "reasoning": "Orthopnea, PND and edema suggest acute heart failure. Elevated JVP, S3 and crackles indicate fluid overload. BNP is markedly elevated, the chest X-ray shows pulmonary edema, and the echocardiogram confirms HFrEF (EF 30%).",
            "differentials": "COPD exacerbation — wheeze usually present; BNP/pulmonary edema typically absent. Pneumonia — fever, productive cough and focal consolidation expected. PE — usually sudden dyspnoea; pulmonary edema and S3 uncommon. ACS — ongoing ischaemic chest pain with a rising troponin.",
            "testRationale": "BNP supports heart failure; CBC screens for anemia/infection; CMP checks renal function and electrolytes before diuresis; troponin looks for an ischaemic trigger; ECG for ischaemia/arrhythmia; chest X-ray for edema/cardiomegaly; echo confirms EF. ABG, CTPA, D-dimer, venous Doppler and sputum culture are low-yield here.",
            "treatmentSequencing": "Stabilise first: oxygen, IV furosemide and (with high BP) a nitroglycerin infusion. After stabilization start guideline-directed therapy — ARNI (sacubitril/valsartan), a beta-blocker (metoprolol succinate), an MRA (spironolactone for EF ≤35%) and an SGLT2 inhibitor (empagliflozin) — plus sodium and fluid restriction. Avoid large-volume IV fluids.",
            "pearls": "Orthopnea and PND are classic for left-sided heart failure. An S3 gallop strongly suggests volume overload. Interpret BNP with the clinical picture. Echo determines EF and guides long-term therapy. Medication nonadherence is a common trigger.",
            "pitfalls": "Don't mistake heart failure for COPD on dyspnoea alone. A mild troponin rise doesn't always mean MI. Always look for triggers (nonadherence, ischaemia, arrhythmia, infection, uncontrolled hypertension). Avoid unnecessary IV fluids in volume overload. Up-titrate chronic HFrEF meds only once haemodynamically stable.",
            "learningPoints": "Recognise acute decompensated HFrEF, treat congestion first, then layer in the four pillars of guideline-directed medical therapy once stable."
          }
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
            "xpReward": 25,
            "mentorInsight": {
              "reasoning": "Core clinical insights — how the diagnosis was reached.",
              "differentials": "Why the other diagnoses didn't fit.",
              "testRationale": "Why these tests were the right ones to order.",
              "treatmentSequencing": "Treatment priorities and the order to start them.",
              "pearls": "Clinical pearls worth remembering.",
              "pitfalls": "Clinical traps to avoid.",
              "learningPoints": "Key learning points from this case."
            }
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
            "xpReward": 30,
            "mentorInsight": {
              "reasoning": "Core clinical insights — how the diagnosis was reached.",
              "differentials": "Why the other diagnoses didn't fit.",
              "testRationale": "Why these tests were the right ones to order.",
              "treatmentSequencing": "Treatment priorities and the order to start them.",
              "pearls": "Clinical pearls worth remembering.",
              "pitfalls": "Clinical traps to avoid.",
              "learningPoints": "Key learning points from this case."
            }
          }
        }
      ]
    }
    """  // "sendAt" is ISO-8601 UTC; omit to go live now. Emergencies stay for 3 hours.
}
