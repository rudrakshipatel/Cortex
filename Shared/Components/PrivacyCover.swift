import SwiftUI

/// Covers the UI with an opaque brand screen whenever the scene is not active,
/// so clinical case content (and, in the admin app, the answer keys on the
/// dashboard) never appear in the iOS app-switcher snapshot or during
/// backgrounding. It costs nothing while the app is in the foreground and adds
/// no state beyond the scene phase the system already tracks.
private struct PrivacyCover: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    // Only cover once the app has actually been active. This avoids flashing the
    // cover during the brief `.inactive` phase of a cold launch (which otherwise
    // looks like a "lock screen" on startup).
    @State private var wasActive = false

    func body(content: Content) -> some View {
        content.overlay {
            if wasActive && scenePhase != .active {
                // No transition: the cover must be present the instant the scene
                // goes inactive, before iOS captures the app-switcher snapshot —
                // an animated fade-in could leak a frame of real content.
                ZStack {
                    CX.appBackground.ignoresSafeArea()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(CX.teal)
                }
            }
        }
        .animation(nil, value: scenePhase)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { wasActive = true }
        }
    }
}

extension View {
    /// Hide sensitive content from the app-switcher snapshot and while inactive.
    func privacyCoverWhenInactive() -> some View { modifier(PrivacyCover()) }
}
