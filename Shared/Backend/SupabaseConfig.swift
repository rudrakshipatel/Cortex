import Foundation

/// Fill these in from your Supabase project → Settings → API.
/// Until both are set, all networking is skipped and the app runs fully
/// offline/local (exactly as before the backend was added).
enum SupabaseConfig {
    static let url = "https://lrzvmzkrtwawpiqxrkik.supabase.co"        // e.g. "https://abcdefgh.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxyenZtemtydHdhd3BpcXhya2lrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE4ODI3MzYsImV4cCI6MjA5NzQ1ODczNn0.Wl1a9zNr2BfJSeZaL9pkic_wDy7clQNchfHHJ5D23tA"    // the public "anon" key (safe to ship)

    static var isConfigured: Bool { !url.isEmpty && !anonKey.isEmpty }
}
