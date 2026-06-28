import Foundation

/// A thin, dependency-free Supabase client (PostgREST + Auth over URLSession).
/// Used to broadcast content/emergencies from the admin device and to sync them
/// down to every user. No-ops cleanly when SupabaseConfig isn't filled in.
@MainActor
final class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    private init() {
        Self.migrateLegacyTokensIfNeeded()
        adminToken = Keychain.get(K.adminToken)
        refreshToken = Keychain.get(K.adminRefresh)
        userToken = Keychain.get(K.userToken)
    }

    /// Keychain account names for the bearer tokens (the only true secrets).
    private enum K {
        static let adminToken   = "cx.sbToken"
        static let adminRefresh = "cx.sbRefresh"
        static let userToken    = "cx.sbUserToken"
        static let userRefresh  = "cx.sbUserRefresh"
    }

    /// One-time move of any tokens left in UserDefaults by older builds into the
    /// Keychain, then scrub them from the plist.
    private static func migrateLegacyTokensIfNeeded() {
        let d = UserDefaults.standard
        for key in [K.adminToken, K.adminRefresh, K.userToken, K.userRefresh] {
            if Keychain.get(key) == nil, let legacy = d.string(forKey: key) {
                Keychain.set(legacy, for: key)
            }
            d.removeObject(forKey: key)
        }
    }

    // Tokens live in the Keychain (encrypted, excluded from backups); emails are
    // not secrets and stay in UserDefaults.
    @Published private(set) var adminEmail: String? = UserDefaults.standard.string(forKey: "cx.sbEmail")
    private var adminToken: String? { didSet { Keychain.set(adminToken, for: K.adminToken) } }
    private var refreshToken: String? { didSet { Keychain.set(refreshToken, for: K.adminRefresh) } }

    // MARK: Player account (Sign in with Google / Apple)
    @Published private(set) var userEmail: String? = UserDefaults.standard.string(forKey: "cx.sbUserEmail")
    /// The signed-in player's auth user id — the key for their cloud profile and
    /// their leaderboard identity. Not a secret, so it stays in UserDefaults.
    @Published private(set) var userId: String? = UserDefaults.standard.string(forKey: "cx.sbUserId")
    private var userToken: String? { didSet { Keychain.set(userToken, for: K.userToken) } }

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
        Keychain.set(params["refresh_token"], for: K.userRefresh)
        let user = try? await fetchUser(access)
        userEmail = user?.email
        userId = user?.id
        UserDefaults.standard.set(user?.email, forKey: "cx.sbUserEmail")
        UserDefaults.standard.set(user?.id, forKey: "cx.sbUserId")
        return user?.email
    }

    func signOutPlayer() {
        userToken = nil
        userEmail = nil
        userId = nil
        Keychain.delete(K.userRefresh)
        UserDefaults.standard.removeObject(forKey: "cx.sbUserEmail")
        UserDefaults.standard.removeObject(forKey: "cx.sbUserId")
    }

    // MARK: Email sign-in (6-digit code)

    /// Email an account a 6-digit sign-in code (creates the account if new).
    /// NOTE: for a CODE (not a magic link) to be sent, the Supabase "Magic Link"
    /// email template must include `{{ .Token }}` (Supabase ▸ Auth ▸ Templates).
    func sendEmailCode(_ email: String) async throws {
        guard isConfigured, let url = URL(string: "\(SupabaseConfig.url)/auth/v1/otp") else { throw SBError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "create_user": true])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SBError.http((resp as? HTTPURLResponse)?.statusCode ?? 0,
                               Self.authError(data) ?? "Couldn't send the code. Check the email and try again.")
        }
    }

    /// Verify the 6-digit code and start the player session. Returns the email.
    @discardableResult
    func verifyEmailCode(_ email: String, code: String) async throws -> String? {
        guard isConfigured, let url = URL(string: "\(SupabaseConfig.url)/auth/v1/verify") else { throw SBError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["type": "email", "email": email, "token": code])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String else {
            throw SBError.http((resp as? HTTPURLResponse)?.statusCode ?? 0,
                               Self.authError(data) ?? "That code didn't work. Check it or request a new one.")
        }
        userToken = access
        Keychain.set(obj["refresh_token"] as? String, for: K.userRefresh)
        let userObj = obj["user"] as? [String: Any]
        userId = userObj?["id"] as? String
        userEmail = (userObj?["email"] as? String) ?? email
        UserDefaults.standard.set(userEmail, forKey: "cx.sbUserEmail")
        UserDefaults.standard.set(userId, forKey: "cx.sbUserId")
        return userEmail
    }

    /// Pull a human-readable message out of a Supabase auth error body.
    private static func authError(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (obj["msg"] ?? obj["error_description"] ?? obj["error"] ?? obj["message"]) as? String
    }

    /// GET /auth/v1/user to read the signed-in account's id + email.
    private func fetchUser(_ accessToken: String) async throws -> (id: String, email: String?)? {
        guard let url = URL(string: "\(SupabaseConfig.url)/auth/v1/user") else { return nil }
        var req = URLRequest(url: url)
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String else { return nil }
        return (id, obj["email"] as? String)
    }

    /// Resolve the current user id, fetching it from the server if we only have
    /// a token (e.g. after a cold launch with a restored session).
    func currentUserId() async -> String? {
        if let id = userId { return id }
        guard let token = userToken, let user = try? await fetchUser(token) else { return nil }
        userId = user.id
        userEmail = user.email
        UserDefaults.standard.set(user.id, forKey: "cx.sbUserId")
        return user.id
    }

    // MARK: - Cloud profile (per-account game state)

    /// Result of a profile load — distinguishes "no row yet" (a genuinely new
    /// account) from "the request failed" (network/auth), so a transient blip is
    /// never mistaken for a fresh account and used to wipe progress.
    enum ProfileLoad { case found(Data), empty, failed }

    func loadProfile() async -> ProfileLoad {
        guard isConfigured, let uid = await currentUserId(),
              let (data, _) = try? await send(method: "GET",
                  path: "rest/v1/profiles?user_id=eq.\(uid)&select=state", player: true),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return .failed }
        guard let state = rows.first?["state"],
              let blob = try? JSONSerialization.data(withJSONObject: state) else { return .empty }
        return .found(blob)
    }

    /// Upsert this account's game state (the `stateJSON` is the encoded profile).
    func saveProfile(_ stateJSON: Data) async {
        guard isConfigured, let uid = await currentUserId(),
              let state = try? JSONSerialization.jsonObject(with: stateJSON) else { return }
        let iso = ISO8601DateFormatter().string(from: Date())
        let row: [[String: Any]] = [["user_id": uid, "state": state, "updated_at": iso]]
        guard let body = try? JSONSerialization.data(withJSONObject: row) else { return }
        _ = try? await send(method: "POST", path: "rest/v1/profiles", body: body, player: true,
                            extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"])
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
    /// Pulls published content through `get_cases`, which returns every case with
    /// the answer key STRIPPED OUT (the raw tables are no longer readable). Each
    /// case carries a `remote` ref so the attempt can be graded server-side.
    func syncContent(into store: ContentStore) async {
        guard isConfigured else { return }
        guard let (data, _) = try? await send(method: "POST",
                path: "rest/v1/rpc/get_cases", body: Data("{}".utf8)),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        var clinical: [ClinicalCase] = [], daily: [DailyCase] = [], ids: [String] = []
        for row in rows {
            guard let id = row["id"] as? String, !store.hasIngested(id),
                  let kind = row["kind"] as? String, let payload = row["payload"],
                  let pdata = try? JSONSerialization.data(withJSONObject: payload) else { continue }
            let ref = RemoteRef(source: "content", id: id)
            switch kind {
            case "clinical":
                if var c = try? JSONDecoder().decode(CaseDTO.self, from: pdata).toModel("server", requireKey: false) {
                    c.remote = ref; clinical.append(c); ids.append(id)
                }
            case "daily":
                if var d = try? JSONDecoder().decode(DailyDTO.self, from: pdata).toModel("server", requireKey: false) {
                    d.clinicalCase.remote = ref; daily.append(d); ids.append(id)
                }
            default: break
            }
        }
        if !ids.isEmpty { store.addRemote(clinical: clinical, daily: daily, serverIDs: ids) }
    }

    /// Pull all broadcast emergencies (answer-stripped) and turn them into
    /// `EmergencyCase`s anchored to *this device's* local timezone, so the Home
    /// "emergency" card appears during its 3-hour window even without a push.
    /// Only emergencies that haven't expired yet are returned.
    func fetchActiveEmergencies() async -> [EmergencyCase] {
        guard isConfigured,
              let (data, _) = try? await send(method: "POST",
                  path: "rest/v1/rpc/get_emergencies", body: Data("{}".utf8)),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let now = Date()
        var out: [EmergencyCase] = []
        for row in rows {
            guard let rowId = row["id"] as? String,
                  let sendDate = row["send_date"] as? String,
                  let payload = row["payload"],
                  let pdata = try? JSONSerialization.data(withJSONObject: payload),
                  var clinicalCase = try? JSONDecoder().decode(CaseDTO.self, from: pdata).toModel("emergency", requireKey: false)
            else { continue }
            clinicalCase.remote = RemoteRef(source: "emergency", id: rowId)
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

    /// Fetch a single emergency case (answer-stripped) by its server id.
    func fetchEmergencyCase(id: UUID) async -> ClinicalCase? {
        guard isConfigured,
              let body = try? JSONSerialization.data(withJSONObject: ["p_id": id.uuidString.lowercased()]),
              let (data, _) = try? await send(method: "POST", path: "rest/v1/rpc/get_emergency", body: body),
              let payload = try? JSONSerialization.jsonObject(with: data),
              !(payload is NSNull),
              let pdata = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        var c = try? JSONDecoder().decode(CaseDTO.self, from: pdata).toModel("emergency", requireKey: false)
        c?.remote = RemoteRef(source: "emergency", id: id.uuidString.lowercased())
        return c
    }

    // MARK: - Server-side grading
    /// Result of grading an attempt: the score-derived rewards plus the full
    /// (answer-bearing) case, returned only in response to a submitted attempt.
    struct GradeResult {
        let score: Double
        let earnedXP: Int
        let earnedCoins: Int
        let fullCase: ClinicalCase
    }

    /// Submit an attempt (pick indices) to `grade_case`; the server scores it
    /// against the stored answers and returns the score + the full case.
    func gradeCase(_ ref: RemoteRef, testIdx: [Int], dxIdx: Int?, txIdx: [Int]) async -> GradeResult? {
        guard isConfigured else { return nil }
        var args: [String: Any] = [
            "p_source": ref.source, "p_id": ref.id,
            "p_test_idx": testIdx, "p_tx_idx": txIdx,
        ]
        if let dxIdx { args["p_dx_idx"] = dxIdx }
        guard let body = try? JSONSerialization.data(withJSONObject: args),
              let (data, _) = try? await send(method: "POST", path: "rest/v1/rpc/grade_case",
                                              body: body, player: true),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let caseObj = obj["case"], !(caseObj is NSNull),
              let pdata = try? JSONSerialization.data(withJSONObject: caseObj),
              let full = try? JSONDecoder().decode(CaseDTO.self, from: pdata).toModel("graded")
        else { return nil }
        var graded = full
        graded.remote = ref
        let score = (obj["score"] as? NSNumber)?.doubleValue ?? 0
        let xp = (obj["earned_xp"] as? NSNumber)?.intValue ?? 0
        let coins = (obj["earned_coins"] as? NSNumber)?.intValue ?? 0
        return GradeResult(score: score, earnedXP: xp, earnedCoins: coins, fullCase: graded)
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

    // MARK: - Weekly leagues (real players, rooms of ≤30)

    struct LeagueMember: Decodable {
        let player_id: String
        let username: String
        let weekly_xp: Int
        let total_xp: Int
        let trophies: Int
        let rank: Int
    }

    /// Join (or update) the signed-in player's league room for the week. The
    /// server places them in a room of the same `kind` with a free seat, or a new
    /// room when all are full. No-ops when not signed in.
    func reportLeague(week: Int, kind: String, weeklyXP: Int, totalXP: Int,
                      trophies: Int, username: String) async {
        guard isConfigured, isSignedIn,
              let body = try? JSONSerialization.data(withJSONObject: [
                "p_week": week, "p_kind": kind, "p_weekly_xp": weeklyXP,
                "p_total_xp": totalXP, "p_trophies": trophies, "p_username": username]) else { return }
        _ = try? await send(method: "POST", path: "rest/v1/rpc/report_league", body: body, player: true)
    }

    /// The ≤30 real players in the caller's league room for the week, ranked.
    func fetchLeague(week: Int) async -> [LeagueMember] {
        guard isConfigured, isSignedIn,
              let body = try? JSONSerialization.data(withJSONObject: ["p_week": week]),
              let (data, _) = try? await send(method: "POST", path: "rest/v1/rpc/get_league", body: body, player: true),
              let rows = try? JSONDecoder().decode([LeagueMember].self, from: data)
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
                      admin: Bool = false, player: Bool = false,
                      extraHeaders: [String: String] = [:],
                      retrying: Bool = false) async throws -> (Data, HTTPURLResponse) {
        guard isConfigured, let url = URL(string: "\(SupabaseConfig.url)/\(path)") else { throw SBError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Bearer: admin token for admin writes, the signed-in player's token when
        // an authenticated action is needed (grading), else the public anon key.
        let bearer = admin  ? (adminToken ?? SupabaseConfig.anonKey)
                   : player ? (userToken ?? SupabaseConfig.anonKey)
                   :          SupabaseConfig.anonKey
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
