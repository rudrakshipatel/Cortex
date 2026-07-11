import SwiftUI
import UIKit
import UserNotifications

@main
struct CortexApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()
    @StateObject private var store = ContentStore()
    @StateObject private var notif = NotificationManager.shared
    @StateObject private var storeManager = StoreManager()
    @Environment(\.scenePhase) private var scenePhase

    /// Configure analytics before the first screen renders, so autocaptured
    /// screen views and lifecycle events aren't missed.
    init() { Analytics.start() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(store)
                .environmentObject(notif)
                .environmentObject(storeManager)
                .environmentObject(SupabaseService.shared)
                .tint(CX.orange)
                // A tapped "Challenge a friend" link (cortex://case/{id} or the
                // https form) — stash the case id; MainTabView opens it once
                // content is ready.
                .onOpenURL { url in
                    if let id = CXDeepLink.parseCaseID(from: url) { app.pendingCaseLink = id }
                    else if let code = CXDeepLink.parseInviteCode(from: url) { app.pendingInviteCode = code }
                }
                // Refill Energy (and roll the league) whenever the app comes to the
                // foreground, so a new GMT day restores energy even if the app was
                // left open or backgrounded across midnight.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        app.refreshForNewDay()
                        Task {
                            // Refresh the Home emergency card. The alert itself is
                            // delivered by the server push (works when killed/closed),
                            // so we don't fire a local notification here.
                            store.setServerEmergencies(await SupabaseService.shared.fetchActiveEmergencies())
                        }
                    } else {
                        // Persist this account's progress when leaving the foreground.
                        Task { await app.pushProfileNow() }
                    }
                }
                // Mirror the real StoreKit subscription entitlement into AppState.
                .onChange(of: storeManager.isPro) { _, pro in app.isPro = pro }
                .task(id: storeManager.isPro) { app.isPro = storeManager.isPro }
                // Keep the RevenueCat identity == the Supabase user, so the
                // referral reward (a server-side promo grant) reaches this account.
                // Analytics uses the same id so events and revenue line up.
                .task(id: SupabaseService.shared.userId) {
                    let uid = SupabaseService.shared.userId
                    await storeManager.identify(uid)
                    Analytics.identify(uid, properties: [
                        "position": app.position,
                        "country": app.country,
                        "is_pro": app.isPro,
                    ])
                }
                .task {
                    // Register for remote push (used to broadcast emergencies) and
                    // pull any content published to all users.
                    UIApplication.shared.registerForRemoteNotifications()
                    // Cold launch with a restored session → load the account's profile.
                    if SupabaseService.shared.isSignedIn { await app.bindAccount() }
                    await SupabaseService.shared.syncContent(into: store)
                    store.setServerEmergencies(await SupabaseService.shared.fetchActiveEmergencies())
                    await SupabaseService.shared.submitScore(
                        playerId: app.leaderboardId, username: app.displayName, xp: app.lifetimeXP)
                }
                // Hide clinical content from the app-switcher snapshot / backgrounding.
                .privacyCoverWhenInactive()
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var sb: SupabaseService
    var body: some View {
        Group {
            #if DEBUG
            // Screenshot-only screen router. Compiled out of Release entirely, so
            // the routing table and its seed data never ship in the store binary.
            if let key = ProcessInfo.processInfo.environment["CX_SCREEN"], !key.isEmpty {
                DebugRouter(key: key)
            } else {
                mainContent
            }
            #else
            mainContent
            #endif
        }
        .transition(.opacity)
        .animation(.easeInOut, value: sb.isSignedIn)
        .animation(.easeInOut, value: app.isSyncing)
        .animation(.easeInOut, value: app.onboarded)
    }

    @ViewBuilder private var mainContent: some View {
        if !sb.isSignedIn && !app.onboarded {
            OnboardingFlow(startAt: .intro)           // first run: sign-in is optional (can skip)
        } else if app.isSyncing {
            SyncingScreen()                           // loading this account's cloud profile
        } else if !app.onboarded {
            OnboardingFlow(startAt: .country)         // new account finishes onboarding
        } else {
            MainTabView()
        }
    }
}

/// Shown briefly right after sign-in while the account's progress loads.
struct SyncingScreen: View {
    var body: some View {
        AppBackground {
            VStack(spacing: 16) {
                VixClip(anim: .wave, size: 150)
                ProgressView().controlSize(.large).tint(CX.teal)
                Text("Loading your progress…").font(CX.heading(17)).foregroundStyle(CX.navySoft)
            }
        }
    }
}

#if DEBUG
/// Renders a single screen selected by the CX_SCREEN launch env var so each
/// screen can be screenshotted without UI automation. Debug builds only — this
/// whole type is compiled out of Release.
struct DebugRouter: View {
    let key: String
    var body: some View {
        switch key {
        case "auth":          OnboardingFlow(startAt: .auth)
        case "country":       OnboardingFlow(startAt: .country)
        case "reminder":      OnboardingFlow(startAt: .reminder)
        case "intro":         OnboardingFlow(startAt: .intro)
        case "case_info":     CaseFlow(clinicalCase: Seed.rlsCase)
        case "case_tests":    CaseFlow(clinicalCase: Seed.rlsCase, initialStep: .tests)
        case "case_results":  CaseFlow(clinicalCase: Seed.rlsCase, initialStep: .results)
        case "case_dx":       CaseFlow(clinicalCase: Seed.rlsCase, initialStep: .diagnosis)
        case "case_tx":       CaseFlow(clinicalCase: Seed.rlsCase, initialStep: .treatment)
        case "case_outcome":  CaseFlow(clinicalCase: Seed.rlsCase, initialStep: .outcome)
        case "home":          HomeView()
        case "practice":      PracticeView()
        case "streak":        StreakView()
        case "shop":          StreakFreezeShop()
        case "leagues":       LeaguesView()
        case "me":            MeView()
        case "pro":           GoProSheet()
        default:              MainTabView()
        }
    }
}
#endif
