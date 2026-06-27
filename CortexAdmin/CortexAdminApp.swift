import SwiftUI

/// The Cortex **Admin** app — a separate binary used only to author and publish
/// content (clinical / daily / emergency cases) to Supabase. It shares the model,
/// backend and design code with the player app but ships none of the gameplay UI,
/// and the player app ships none of this admin code.
///
/// Access is gated twice: a local admin PIN (AdminContainer) and a Supabase admin
/// sign-in (CloudSyncView) before anything can be published.
@main
struct CortexAdminApp: App {
    @StateObject private var store = ContentStore()

    var body: some Scene {
        WindowGroup {
            AdminContainer()
                .environmentObject(store)
                .environmentObject(SupabaseService.shared)
                .tint(CX.orange)
        }
    }
}
