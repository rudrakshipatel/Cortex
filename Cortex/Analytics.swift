import Foundation
import PostHog

/// PostHog project settings.
///
/// The **project API key** (`phc_…`) is a *public* client key — safe to ship,
/// exactly like the RevenueCat `appl_` key and the Supabase anon key. It can
/// only write events, never read your data. (The *personal* API key `phx_…`
/// is the secret one — never put that in the app.)
enum AnalyticsConfig {
    /// PostHog ▸ Settings ▸ Project ▸ "Project API key" (starts with `phc_`).
    static let apiKey = "phc_BfMMKu9iTBcBuSy5dUjyL7ARgjdL2tpttjtgjyB3EfBq"

    /// US cloud (your project is on us.posthog.com).
    /// Use `https://eu.i.posthog.com` if you ever move to the EU region.
    static let host = "https://us.i.posthog.com"

    /// Until the key is filled in, every Analytics call is a no-op.
    static var isConfigured: Bool { apiKey.hasPrefix("phc_") && !apiKey.contains("REPLACE") }
}

/// Thin wrapper around PostHog so the rest of the app never imports the SDK,
/// and analytics stays a safe no-op while unconfigured (or in the admin app,
/// which doesn't link PostHog at all).
enum Analytics {
    private static var started = false

    /// Configure the SDK once, as early as possible in the app's lifetime.
    static func start() {
        guard AnalyticsConfig.isConfigured, !started else { return }
        let config = PostHogConfig(apiKey: AnalyticsConfig.apiKey, host: AnalyticsConfig.host)
        config.captureScreenViews = true
        config.captureApplicationLifecycleEvents = true
        // Session replay stays off: this app renders clinical content and we
        // don't want screen recordings leaving the device.
        config.sessionReplay = false
        PostHogSDK.shared.setup(config)
        started = true
    }

    /// Tie events to the signed-in Supabase user — the same id used for the
    /// RevenueCat identity, so analytics and revenue line up. Passing `nil`
    /// (sign-out) resets to a fresh anonymous id.
    static func identify(_ userID: String?, properties: [String: Any] = [:]) {
        guard started else { return }
        guard let id = userID, !id.isEmpty else { PostHogSDK.shared.reset(); return }
        PostHogSDK.shared.identify(id, userProperties: properties)
    }

    /// Forget the current user (sign-out / account deletion).
    static func reset() {
        guard started else { return }
        PostHogSDK.shared.reset()
    }

    /// Record a product event. Keep property values primitive (String/Int/Bool).
    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
        guard started else { return }
        PostHogSDK.shared.capture(event, properties: properties)
    }
}
