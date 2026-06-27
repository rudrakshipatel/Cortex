import UIKit
import UserNotifications

/// Handles APNs device-token registration and routes the token to Supabase so
/// the server can push to this device. Notification taps are handled by
/// NotificationManager (set as the UNUserNotificationCenter delegate here).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await SupabaseService.shared.registerDevice(token: token) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No remote push available (e.g. no entitlement / simulator without push). Safe to ignore.
    }
}
