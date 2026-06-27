import Foundation

/// RevenueCat configuration. Get the **public** SDK API key from the RevenueCat
/// dashboard → Project Settings → API Keys → "App Store" (it starts with `appl_`).
/// Safe to ship — it's a public key.
enum RevenueCatConfig {
    /// Public App Store API key (starts with `appl_`).
    static let apiKey = "appl_zOPEjiMmZmXtFuKhYqSyGypicFv"

    /// The entitlement identifier you create in RevenueCat (Entitlements tab)
    /// and attach to the Cortex Pro subscriptions. The user is "Pro" while this
    /// entitlement is active.
    static let entitlementID = "pro"

    static var isConfigured: Bool { !apiKey.contains("REPLACE_WITH") && !apiKey.isEmpty }
}
