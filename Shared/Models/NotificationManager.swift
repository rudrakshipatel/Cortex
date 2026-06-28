import SwiftUI
import UserNotifications

/// Schedules the local "emergency" notification and routes a tap on it back to
/// the matching case. Set as the UNUserNotificationCenter delegate at launch.
///
/// Note: this fires a *local* notification on this device. Broadcasting an
/// emergency to every user requires a push backend (APNs); the scheduling shape
/// here is designed to move to a server with minimal change.
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private override init() { super.init() }

    /// Set when the user taps an emergency notification; observed by the UI to
    /// open the case.
    @Published var openEmergencyID: UUID?

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
    }

    /// Custom ambulance-siren sound for emergencies. Requires `siren.caf` in the
    /// app bundle (see note in scheduleEmergency); falls back to the default
    /// alert sound if the file isn't present.
    static let sirenSound = UNNotificationSound(named: UNNotificationSoundName("siren.caf"))

    private func emergencyContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "🚨 Emergency — you're on duty"
        content.body = "There's an emergency and you're the only doctor on duty. Save the patient — tap to respond."
        // Ambulance-siren sound. Add an audio file named `siren.caf` (≤30s) to the
        // Cortex app target for this to play; otherwise iOS uses the default sound.
        content.sound = Self.sirenSound
        content.interruptionLevel = .timeSensitive   // break through Focus when live
        return content
    }

    /// Schedules the emergency alert on this device for the given local date/time.
    func scheduleEmergency(id: UUID, at date: Date) {
        let content = emergencyContent()
        content.userInfo = ["emergencyID": id.uuidString]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancel(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    // MARK: Server emergencies → local alerts
    private static let notifiedKey = "cx.notifiedEmergencies"

    /// Make sure every server emergency triggers exactly one alert on this device:
    /// scheduled at its fire time if it's still upcoming, or fired right away if
    /// it's already live and we haven't alerted for it yet. Idempotent — safe to
    /// call on every launch/foreground.
    func syncEmergencyNotifications(_ emergencies: [EmergencyCase]) {
        guard !emergencies.isEmpty else { return }
        let now = Date()
        let d = UserDefaults.standard
        var notified = Set(d.stringArray(forKey: Self.notifiedKey) ?? [])
        var toSchedule: [(UUID, Date)] = []
        var toFire: [UUID] = []

        for ec in emergencies {
            let idStr = ec.id.uuidString
            if notified.contains(idStr) {
                if now < ec.fireDate { toSchedule.append((ec.id, ec.fireDate)) }   // keep a future one fresh
                continue
            }
            if now < ec.fireDate {
                toSchedule.append((ec.id, ec.fireDate)); notified.insert(idStr)
            } else if now < ec.expiry {                    // already live → alert immediately
                toFire.append(ec.id); notified.insert(idStr)
            }
        }
        // Forget ids no longer present so a re-broadcast can alert again, and
        // persist SYNCHRONOUSLY now — before the async auth call — so overlapping
        // calls (launch + foreground + poll) can't each fire a duplicate.
        notified.formIntersection(Set(emergencies.map { $0.id.uuidString }))
        d.set(Array(notified), forKey: Self.notifiedKey)

        guard !toSchedule.isEmpty || !toFire.isEmpty else { return }
        requestAuthorization { granted in
            guard granted else { return }
            for (id, date) in toSchedule { self.scheduleEmergency(id: id, at: date) }
            for id in toFire { self.fireEmergencyNow(id: id) }
        }
    }

    private func fireEmergencyNow(id: UUID) {
        let content = emergencyContent()
        content.userInfo = ["emergencyID": id.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Daily case reminder
    private static let dailyReminderID = "cx.dailyCaseReminder"

    /// Schedule a repeating daily reminder to solve the daily case, fired at the
    /// given local hour:minute. Asks for notification permission first. Replaces
    /// any existing daily reminder so it's safe to call repeatedly.
    func scheduleDailyReminder(hour: Int = 10, minute: Int = 0) {
        requestAuthorization { granted in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Your patient is waiting 🩺"
            content.body = "Solve today's case to keep your streak alive and stay sharp."
            content.sound = .default

            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            // hour/minute only + repeats → fires once a day at that LOCAL time.
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: Self.dailyReminderID, content: content, trigger: trigger)

            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [Self.dailyReminderID])
            center.add(request)
        }
    }

    /// Turn off the daily reminder.
    func cancelDailyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.dailyReminderID])
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show the alert even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Tapping the notification opens the case.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let raw = response.notification.request.content.userInfo["emergencyID"] as? String,
           let id = UUID(uuidString: raw) {
            DispatchQueue.main.async { self.openEmergencyID = id }
        }
        completionHandler()
    }
}
