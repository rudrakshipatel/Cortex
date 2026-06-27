import Foundation

/// A thin, dependency-free Supabase client (PostgREST + Auth over URLSession).
/// Used to broadcast content/emergencies from the admin device and to sync them
/// down to every user. No-ops cleanly when SupabaseConfig isn't filled in.
@MainActor
final class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    private init() {
        adminToken = UserDefaults.standard.string(forKey: "cx.sbToken")
        refreshToken = UserDefaults.standard.string(forKey: "cx.sbRefresh")
        userToken = UserDefaults.standard.string(forKey: "cx.sbUserToken")
    }

    @Published private(set) var adminEmail: String? = UserDefaults.standard.string(forKey: "cx.sbEmail")
    private var adminToken: String? { didSet { UserDefaults.standard.set(adminToken, forKey: "cx.sbToken") } }
    private var refreshToken: String? { didSet { UserDefaults.standard.set(refreshToken, forKey: "cx.sbRefresh") } }

    // MARK: Player account (Sign in with Google / Apple)
    @Published private(set) var userEmail: String? = UserDefaults.standard.string(forKey: "cx.sbUserEmail")
    private var userToken: String? { didSet { UserDefaults.standard.set(userToken, forKey: "cx.sbUserToken") } }

    var isConfigured: Bool { SupabaseConfig.isConfigured }
    var isAdminSignedIn: Bool { adminToken != nil }
    /// Whether a player is signed in with Google / Apple.
    var isSignedIn: Bool { userToken != nil }

    /// Sign in the player via a Supabase OAuth provider ("google" or "apple"),
    /// using a web auth session. Returns the account email on success.
    /// Provider credentials live in the Supabase dashboard, not in the app.
    func signInWithOAuth(provider: String) async throws -> String? {
        guard isConfigured else { throw SBError.notConfigured }
        let scheme = "cortexauth"
        var comps = URLComponents(string: "\(SupabaseConfig.url)/auth/v1/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: "\(scheme)://login-callback"),
        ]
        let callback = try await WebAuthSession.start(url: comps.url!, callbackScheme: scheme)
        // Supabase returns the session in the URL fragment (implicit flow).
        let params = Self.parseFragment(callback.fragment ?? "")
        guard let access = params["access_token"] else {
            throw SBError.http(401, params["error_description"] ?? "Sign-in was cancelled or failed.")
        }
        userToken = access
        UserDefaults.standard.set(params["refresh_token"], forKey: "cx.sbUserRefresh")
        let email = try? await fetchUserEmail(access)
        userEmail = email
        UserDefaults.standard.set(email, forKey: "cx.sbUserEmail")
        return email
    }

    func signOutPlayer() {
        userToken = nil
        userEmail = nil
        UserDefaults.standard.removeObject(forKey: "cx.sbUserRefresh")
        UserDefaults.standard.removeObject(forKey: "cx.sbUserEmail")
    }

    /// GET /auth/v1/user to read the signed-in account's email.
    private func fetchUserEmail(_ accessToken: String) async throws -> String? {
        guard let url = URL(string: "\(SupabaseConfig.url)/auth/v1/user") else { return nil }
        var req = URLRequest(url: url)
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj?["email"] as? String
    }

    private static func parseFragment(_ fragment: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { out[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
        }
        return out
    }

    enum SBError: LocalizedError {
        case notConfigured, notSignedIn, http(Int, String), badJSON
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Add your Supabase URL and anon key in SupabaseConfig.swift first."
            case .notSignedIn:   return "Your admin session expired — sign in again under Cloud sync, then retry."
            case .http(let c, let m): return "Server error \(c): \(m)"
            case .badJSON:       return "Unexpected response from server."
            }
        }
    }

    // MARK: - Device registration (every install)
    /// Registers the APNs token plus this device's timezone, so the server can
    /// fire emergencies at each user's *local* time.
    func registerDevice(token: String) async {
        guard isConfigured else { return }
        let body = try? JSONSerialization.data(withJSONObject: [
            "p_token": token,
            "p_timezone": TimeZone.current.identifier,
        ])
        _ = try? await send(method: "POST", path: "rest/v1/rpc/register_device", body: body)
    }

    // MARK: - Content sync (every install, on launch)
    func syncContent(into store: ContentStore) async {
        guard isConfigured else { return }
        guard let (data, _) = try? await send(method: "GET",
                path: "rest/v1/content?select=id,kind,payload&order=created_at.asc"),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        var clinical: [ClinicalCase] = [], daily: [DailyCase] = [], ids: [String] = []
        for row in rows {
            guard let id = row["id"] as? String, !store.hasIngested(id),
                  let kind = row["kind"] as? String, let payload = row["payload"],
                  let pdata = try? JSONSerialization.data(withJSONObject: payload) else { continue }
            switch kind {
            case "clinical":
                if let c = try? JSONDecoder().decode(CaseDTO.self, from: pdata).toModel("server") { clinical.append(c); ids.append(id) }
            case "daily":
                if let d = try? JSONDecoder().decode(DailyDTO.self, from: pdata).toModel("server") { daily.append(d); ids.append(id) }
            default: break
            }
        }
        if !ids.isEmpty { store.addRemote(clinical: clinical, daily: daily, serverIDs: ids) }
    }

    /// Pull all broadcast emergencies from the server and turn them into
    /// `EmergencyCase`s anchored to *this device's* local timezone, so the Home
    /// "emergency" card appears during its 3-hour window even without a push.
    /// Only emergencies that haven't expired yet are returned.
    func fetchActiveEmergencies() async -> [EmergencyCase] {
        guard isConfigured,
              let (data, _) = try? await send(method: "GET",
                  path: "rest/v1/emergencies?select=payload,send_date,local_hour,local_minute&order=send_date.desc"),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let now = Date()
        var out: [EmergencyCase] = []
        for row in rows {
            guard let sendDate = row["send_date"] as? String,
                  let payload = row["payload"],
                  let pdata = try? JSONSerialization.data(withJSONObject: payload),
                  let clinicalCase = try? JSONDecoder().decode(CaseDTO.self, from: pdata).toModel("emergency")
            else { continue }
            let parts = sendDate.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            var comps = DateComponents()
            comps.year = parts[0]; comps.month = parts[1]; comps.day = parts[2]
            comps.hour = (row["local_hour"] as? Int) ?? 0
            comps.minute = (row["local_minute"] as? Int) ?? 0
            guard let fireDate = cal.date(from: comps) else { continue }
            let ec = EmergencyCase(clinicalCase: clinicalCase, fireDate: fireDate)
            if now < ec.expiry { out.append(ec) }   // active or upcoming; drop expired
        }
        return out
    }

    /// Fetch a single emergency case by its server id (after a remote push tap).
    func fetchEmergencyCase(id: UUID) async -> ClinicalCase? {
        guard isConfigured,
              let (data, _) = try? await send(method: "GET",
                  path: "rest/v1/emergencies?id=eq.\(id.uuidString.lowercased())&select=payload"),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let payload = rows.first?["payload"],
              let pdata = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return try? JSONDecoder().decode(CaseDTO.self, from: pdata).toModel("emergency")
    }

    // MARK: - Global leaderboard
    /// One ranked row from the leaderboard.
    struct LeaderRow: Decodable, Identifiable {
        let rank: Int
        let player_id: String
        let username: String
        let xp: Int
        var id: String { player_id }
    }

    /// Report this player's lifetime XP (upsert). No-ops when not configured.
    func submitScore(playerId: String, username: String, xp: Int) async {
        guard isConfigured else { return }
        let body = try? JSONSerialization.data(withJSONObject: [
            "p_player": playerId, "p_username": username, "p_xp": xp,
        ])
        _ = try? await send(method: "POST", path: "rest/v1/rpc/submit_score", body: body)
    }

    /// Fetch the global ranking (top `limit` plus the caller's own row).
    func fetchLeaderboard(playerId: String, limit: Int = 50) async -> [LeaderRow] {
        guard isConfigured,
              let body = try? JSONSerialization.data(withJSONObject: ["p_player": playerId, "p_limit": limit]),
              let (data, _) = try? await send(method: "POST", path: "rest/v1/rpc/get_leaderboard", body: body),
              let rows = try? JSONDecoder().decode([LeaderRow].self, from: data)
        else { return [] }
        return rows
    }

    // MARK: - Admin auth
    func signIn(email: String, password: String) async throws {
        guard isConfigured else { throw SBError.notConfigured }
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, _) = try await send(method: "POST", path: "auth/v1/token?grant_type=password", body: body)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["access_token"] as? String else { throw SBError.badJSON }
        adminToken = token
        refreshToken = obj["refresh_token"] as? String
        adminEmail = email
        UserDefaults.standard.set(email, forKey: "cx.sbEmail")
    }

    func signOut() {
        adminToken = nil; refreshToken = nil; adminEmail = nil
        UserDefaults.standard.removeObject(forKey: "cx.sbEmail")
    }

    /// Exchange the refresh token for a fresh access token. Returns false if
    /// there's no refresh token or it's no longer valid.
    private func refreshSession() async -> Bool {
        guard isConfigured, let rt = refreshToken,
              let body = try? JSONSerialization.data(withJSONObject: ["refresh_token": rt]),
              let (data, _) = try? await send(method: "POST",
                  path: "auth/v1/token?grant_type=refresh_token", body: body),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["access_token"] as? String
        else { return false }
        adminToken = token
        refreshToken = (obj["refresh_token"] as? String) ?? refreshToken
        return true
    }

    // MARK: - Admin publishing
    private struct OutRow<P: Encodable>: Encodable { let kind: String; let payload: P }
    private struct EmergRow: Encodable {
        let payload: CaseDTO; let send_date: String; let local_hour: Int; let local_minute: Int
    }

    /// Publish parsed bulk content to all users. Returns how many items went up.
    @discardableResult
    func publish(_ payload: ImportPayload) async throws -> Int {
        guard isConfigured else { throw SBError.notConfigured }
        guard isAdminSignedIn else { throw SBError.notSignedIn }
        var count = 0
        if let c = payload.clinical, !c.isEmpty {
            try await insert(c.map { OutRow(kind: "clinical", payload: $0) }); count += c.count
        }
        if let d = payload.daily, !d.isEmpty {
            try await insert(d.map { OutRow(kind: "daily", payload: $0) }); count += d.count
        }
        if let es = payload.emergencies, !es.isEmpty {
            for e in es {
                let ec = try e.toModel("emergency")
                try await broadcastEmergency(case: ec.clinicalCase, on: ec.fireDate)
            }
            count += es.count
        }
        return count
    }

    /// Broadcast an emergency. Stores the target *local* wall-clock time and
    /// date; the scheduled function delivers it at that local time in every
    /// user's own timezone.
    func broadcastEmergency(case clinicalCase: ClinicalCase, on date: Date) async throws {
        guard isConfigured else { throw SBError.notConfigured }
        guard isAdminSignedIn else { throw SBError.notSignedIn }
        let dto = CaseDTO(from: clinicalCase)
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let sendDate = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        try await insert([EmergRow(payload: dto, send_date: sendDate,
                                   local_hour: c.hour ?? 0, local_minute: c.minute ?? 0)],
                         path: "rest/v1/emergencies")
    }

    private func insert<T: Encodable>(_ rows: [T], path: String = "rest/v1/content") async throws {
        let body = try JSONEncoder().encode(rows)
        _ = try await send(method: "POST", path: path, body: body, admin: true,
                           extraHeaders: ["Prefer": "return=minimal"])
    }

    // MARK: - HTTP core
    @discardableResult
    private func send(method: String, path: String, body: Data? = nil,
                      admin: Bool = false, extraHeaders: [String: String] = [:],
                      retrying: Bool = false) async throws -> (Data, HTTPURLResponse) {
        guard isConfigured, let url = URL(string: "\(SupabaseConfig.url)/\(path)") else { throw SBError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bearer = admin ? (adminToken ?? SupabaseConfig.anonKey) : SupabaseConfig.anonKey
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SBError.badJSON }

        // Admin token expired? Refresh once and retry; if that fails, force re-login.
        if http.statusCode == 401, admin, !retrying {
            if await refreshSession() {
                return try await send(method: method, path: path, body: body,
                                      admin: admin, extraHeaders: extraHeaders, retrying: true)
            }
            adminToken = nil; refreshToken = nil
            throw SBError.notSignedIn
        }
        guard (200...299).contains(http.statusCode) else {
            throw SBError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return (data, http)
    }
}
