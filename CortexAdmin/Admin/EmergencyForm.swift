import SwiftUI

/// Admin screen to schedule an "emergency" case. It is authored with the SAME
/// structured form as a regular clinical case, plus a send date/time. At that
/// time a local notification fires (and, if signed in, a backend broadcast goes
/// to every user at their own local time).
struct EmergencyForm: View {
    @EnvironmentObject var store: ContentStore
    @EnvironmentObject var sb: SupabaseService
    @Environment(\.dismiss) private var dismiss

    @State private var draft = CaseDraft()
    @State private var time = defaultTime()
    @State private var broadcast = true
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        CaseEditor(draft: $draft, header: {
            Section {
                DatePicker("Send date & time", selection: $time, in: Date()...,
                           displayedComponents: [.date, .hourAndMinute])
            } header: {
                Text("When to send")
            } footer: {
                Text("Each user gets the 🚨 alert at THIS local time on THIS date in their own timezone — e.g. 8 PM means 8 PM wherever they are.")
            }

            if sb.isConfigured {
                Section {
                    Toggle("Broadcast to all users", isOn: $broadcast)
                } footer: {
                    Text(sb.isAdminSignedIn
                         ? "On: every user gets the 🚨 push at the send time (via the backend). Off: schedules only on this device."
                         : "Sign in under Cloud sync to broadcast to all users.")
                }
            }

            if !store.emergencies.isEmpty {
                Section("Scheduled emergencies") {
                    ForEach(store.emergencies) { ec in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ec.clinicalCase.patientName + " · " + ec.clinicalCase.specialty)
                                    .font(.subheadline.weight(.semibold))
                                Text("Sends at \(ec.timeLabel)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { store.cancelEmergency(ec) } label: {
                                Image(systemName: "bell.slash.fill")
                            }
                        }
                    }
                }
            }
        })
        .navigationTitle("Emergency Case")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(broadcast && sb.isConfigured ? "Schedule & broadcast" : "Schedule") { schedule() }
                    .fontWeight(.semibold).disabled(!draft.isValid)
            }
        }
        .alert(alertTitle, isPresented: $showAlert) { Button("OK") {} } message: { Text(alertMessage) }
    }

    private func schedule() {
        let when = time
        let builtCase = draft.build()

        // Broadcast path: store server-side; the scheduled function delivers it
        // at this local time on this date in each user's own timezone.
        if broadcast, sb.isConfigured, sb.isAdminSignedIn {
            Task {
                do {
                    try await sb.broadcastEmergency(case: builtCase, on: when)
                    draft = CaseDraft()
                    present("Broadcast scheduled",
                            "Every user gets the 🚨 alert at \(when.formatted(date: .omitted, time: .shortened)) their local time on \(when.formatted(date: .abbreviated, time: .omitted)).")
                } catch {
                    present("Couldn't broadcast", error.localizedDescription)
                }
            }
            return
        }

        // Local-only path: schedule a notification on this device.
        NotificationManager.shared.requestAuthorization { granted in
            guard granted else {
                present("Notifications are off",
                        "Enable notifications for Cortex in Settings so the emergency alert can be delivered.")
                return
            }
            let ec = store.scheduleEmergency(case: builtCase, at: when)
            draft = CaseDraft()
            present("Emergency scheduled", "“\(ec.clinicalCase.patientName)” will alert you at \(ec.timeLabel).")
        }
    }

    private func present(_ t: String, _ m: String) {
        alertTitle = t; alertMessage = m; showAlert = true
    }

    private static func defaultTime() -> Date {
        Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    }
}
