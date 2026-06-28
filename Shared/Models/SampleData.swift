import SwiftUI

enum Seed {

    // MARK: Daily / Neurology case — echoes DocRiddles "What's the Diagnosis?" (RLS)
    static let rlsCase = ClinicalCase(
        specialty: "Neurology",
        patientName: "Priya",
        gender: "Female",
        age: "45 Y",
        chiefComplaint: "Irresistible urge to move her legs, worse at night",
        infoCards: [
            InfoCard(
                title: "Basic Info & Chief Complaint",
                bullets: [
                    "45-year-old female, office worker",
                    "“Irresistible urge” to move her legs",
                    "Symptoms worst at night while falling asleep",
                    "Movement brings temporary relief"
                ],
                mentor: "An urge to move relieved by movement and worse at rest/night is the classic RLS pattern."
            ),
            InfoCard(
                title: "History (Hx)",
                bullets: [
                    "Symptoms for ~6 months, gradually worsening",
                    "Heavy menstrual periods for 2 years",
                    "Vegetarian diet, mild fatigue",
                    "No diabetes, no alcohol use",
                    "Mother had similar nighttime leg symptoms"
                ],
                mentor: "Iron deficiency and a positive family history are major RLS risk factors — check ferritin."
            ),
            InfoCard(
                title: "Physical Examination",
                bullets: [
                    "Conjunctival pallor noted",
                    "Normal motor power and reflexes",
                    "No sensory loss or peripheral neuropathy signs",
                    "Normal gait"
                ],
                mentor: "A normal neuro exam with pallor points away from neuropathy and toward iron-deficient RLS."
            )
        ],
        tests: [
            TestOption(category: "Hematology", name: "Complete Blood Count (CBC)",
                       result: "Hb 9.8 g/dL, microcytic", helpful: true,
                       mentor: "Confirms anemia — a strong RLS contributor."),
            TestOption(category: "Hematology", name: "Serum Ferritin",
                       result: "Low at 12 ng/mL", helpful: true,
                       mentor: "Ferritin < 50 is the key actionable RLS test."),
            TestOption(category: "Chemistry", name: "Renal Function / eGFR",
                       result: "Normal", helpful: true,
                       mentor: "Rules out uremia as a secondary cause."),
            TestOption(category: "Imaging", name: "MRI Brain",
                       result: "Normal", helpful: false,
                       mentor: "Adds little here — RLS is a clinical diagnosis."),
            TestOption(category: "Neurophysiology", name: "Nerve Conduction Study",
                       result: "Normal", helpful: false,
                       mentor: "Useful only if neuropathy is suspected — exam was normal.")
        ],
        diagnosisQuestion: "Which diagnosis best fits this presentation?",
        diagnoses: [
            DiagnosisOption(name: "Restless Legs Syndrome (iron-deficient)", correct: true),
            DiagnosisOption(name: "Peripheral neuropathy", correct: false),
            DiagnosisOption(name: "Nocturnal leg cramps", correct: false),
            DiagnosisOption(name: "Akathisia", correct: false)
        ],
        treatments: [
            TreatmentOption(category: "Supplements", name: "Oral iron replacement", appropriate: true),
            TreatmentOption(category: "Lifestyle", name: "Sleep hygiene & leg stretching", appropriate: true),
            TreatmentOption(category: "Medications", name: "Dopamine agonist (if severe)", appropriate: true),
            TreatmentOption(category: "Medications", name: "Broad-spectrum antibiotics", appropriate: false),
            TreatmentOption(category: "Procedural", name: "Lumbar puncture", appropriate: false)
        ],
        outcomeTitle: "Sharp call, Doctor!",
        outcomeBody: "You linked the nighttime urge, family history and pallor to iron-deficient Restless Legs Syndrome — then treated the cause, not just the symptom. Replenishing iron often resolves RLS entirely.",
        xpReward: 22
    )

    /// A ready-made emergency used by the admin "Trigger test emergency" button.
    static let demoEmergency = ClinicalCase(
        specialty: "Emergency Medicine",
        patientName: "Test Patient",
        gender: "Male",
        age: "54 Y",
        chiefComplaint: "Crushing central chest pain, sweating and short of breath",
        infoCards: [
            InfoCard(title: "Basic Info & Chief Complaint",
                     bullets: ["54-year-old male", "Sudden crushing chest pain", "Diaphoretic and clammy"],
                     mentor: "Acute chest pain with autonomic features — think acute coronary syndrome."),
            InfoCard(title: "Physical Examination",
                     bullets: ["BP 92/60 mmHg", "HR 112, irregular", "Cool peripheries"],
                     mentor: "Hypotension with tachycardia points to a large infarct.")
        ],
        tests: [
            TestOption(category: "Cardiac", name: "12-lead ECG", result: "ST elevation in V1–V4",
                       helpful: true, mentor: "Anterior STEMI."),
            TestOption(category: "Cardiac", name: "Troponin", result: "Markedly raised",
                       helpful: true, mentor: "Confirms myocardial injury.")
        ],
        diagnosisQuestion: "Most likely diagnosis?",
        diagnoses: [
            DiagnosisOption(name: "Anterior STEMI", correct: true),
            DiagnosisOption(name: "Pericarditis", correct: false),
            DiagnosisOption(name: "Panic attack", correct: false)
        ],
        treatments: [
            TreatmentOption(category: "Reperfusion", name: "Primary PCI", appropriate: true),
            TreatmentOption(category: "Antiplatelet", name: "Aspirin + ticagrelor", appropriate: true),
            TreatmentOption(category: "Other", name: "Discharge home", appropriate: false)
        ],
        outcomeTitle: "Crisis managed!",
        outcomeBody: "An anterior STEMI needs emergent reperfusion — primary PCI is the gold standard.",
        xpReward: 40
    )

    // MARK: Departments shown on Home
    //
    // No default cases ship with the app — Clinical mode is
    // populated entirely from admin-uploaded / server-synced content
    // (see ContentStore). Kept as an empty list so HomeView still compiles.
    static let departments: [Department] = []

    // MARK: Skill ranks (one per 10 levels: 1–10, 11–20, … up to 71–80+)
    static let skillRanks: [SkillRank] = [
        SkillRank(name: "Medical Student",  subtitle: "Every expert was once here.",             icon: "graduationcap.fill",  color: Color(hex: 0xF08AB0)),
        SkillRank(name: "Intern",           subtitle: "Stepping up to real action.",            icon: "stethoscope",         color: CX.teal),
        SkillRank(name: "Resident",         subtitle: "Rising fast through clinical chaos.",     icon: "cross.case.fill",     color: Color(hex: 0x5AA9E6)),
        SkillRank(name: "Medical Fellow",   subtitle: "Specialization starts, intensity rises.", icon: "books.vertical.fill", color: CX.navySoft),
        SkillRank(name: "Consultant",       subtitle: "You call the final shots.",              icon: "star.circle.fill",    color: CX.gold),
        SkillRank(name: "Specialist",       subtitle: "Expertise isn't optional anymore.",       icon: "rosette",             color: Color(hex: 0x7FD8E8)),
        SkillRank(name: "Senior Specialist",subtitle: "Rare air, rare talent.",                 icon: "medal.fill",          color: Color(hex: 0x9B7BE0)),
        SkillRank(name: "Super Specialist", subtitle: "Legends are made up here.",              icon: "crown.fill",          color: Color(hex: 0xE0A23C)),
    ]

    /// Skill title for a given level (every 10 levels advances the rank).
    static func skill(forLevel level: Int) -> SkillRank {
        let band = Swift.min(skillRanks.count, Swift.max(1, (level - 1) / 10 + 1))
        return skillRanks[band - 1]
    }
}
