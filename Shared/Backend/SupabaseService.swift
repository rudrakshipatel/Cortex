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

        var clinical: [ClinicalCase] = [], daily: [DailyCase] = []
        for row in rows {
            guard let id = row["id"] as? String,
                  let kind = row["kind"] as? String, let payload = row["payload"],
                  let pdata = try? JSONSerialization.data(withJSONObject: payload) else { continue }
            let ref = RemoteRef(source: "content", id: id)
            switch kind {
            case "clinical":
                if var c = try? JSONDecoder().decode(CaseDTO.self, from: pdata).toModel("server", requireKey: false) {
                    c.remote = ref; clinical.append(c)
                }
            case "daily":
                if var d = try? JSONDecoder().decode(DailyDTO.self, from: pdata).toModel("server", requireKey: false) {
                    d.clinicalCase.remote = ref; daily.append(d)
                }
            default: break
            }
        }
        // Authoritative: mirror exactly what the server returned (we only reach
        // here on a successful fetch, so an empty server clears local content).
        store.setServerContent(clinical: clinical, daily: daily)
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
            var ec = EmergencyCase(clinicalCase: clinicalCase, fireDate: fireDate)
            // Use the STABLE server row id (not a fresh UUID each fetch) so the
            // notification dedup recognises the same emergency across polls —
            // otherwise it re-alerts every refresh ("constant ringing").
            if let rid = UUID(uuidString: rowId) { ec.id = rid }
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
    func gradeCase(_ ref: RemoteRef, testIdx: [Int], dxIdx: Int?, txIdx: [Int],
                   testNames: [String] = [], dxName: String? = nil, txNames: [String] = [])
        async -> (result: GradeResult?, error: String?) {
        guard isConfigured else { return (nil, nil) }
        var args: [String: Any] = [
            "p_source": ref.source, "p_id": ref.id,
            "p_test_idx": testIdx, "p_tx_idx": txIdx,
            "p_test_names": testNames, "p_tx_names": txNames,
        ]
        if let dxIdx { args["p_dx_idx"] = dxIdx }
        if let dxName { args["p_dx_name"] = dxName }
        // Prefer name-based grading. If the database hasn't been migrated to the
        // name-aware grade_case yet, that call 404s — fall back to index-only so
        // grading still works everywhere.
        let first = await callGrade(args, ref: ref)
        if first.result != nil { return first }
        for k in ["p_test_names", "p_tx_names", "p_dx_name"] { args.removeValue(forKey: k) }
        return await callGrade(args, ref: ref)
    }

    private func callGrade(_ args: [String: Any], ref: RemoteRef) async -> (result: GradeResult?, error: String?) {
        guard let body = try? JSONSerialization.data(withJSONObject: args),
              let (data, _) = try? await send(method: "POST", path: "rest/v1/rpc/grade_case",
                                              body: body, player: true) else {
            return (nil, "Couldn't reach the server. Check your connection and try again.")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, "The server sent an unexpected response.")
        }
        // The RPC returns { "error": ... } for auth / rate-limit / not-found.
        if let serverError = obj["error"] as? String {
            switch serverError {
            case "rate limited":
                return (nil, "You've graded a lot of cases in a short time. Please wait a little and try again.")
            case "not found":
                return (nil, "This case is no longer available — reopen the app to refresh, then try again.")
            case "auth required":
                return (nil, "Please sign in to have your case scored.")
            default:
                return (nil, "Couldn't score this case. Please try again.")
            }
        }
        guard let caseObj = obj["case"], !(caseObj is NSNull),
              let pdata = try? JSONSerialization.data(withJSONObject: caseObj),
              // requireKey:false so a case whose answer key wasn't saved still
              // renders the outcome (with the server's score) instead of going blank.
              let full = try? JSONDecoder().decode(CaseDTO.self, from: pdata).toModel("graded", requireKey: false)
        else { return (nil, "Couldn't read the graded case.") }
        var graded = full
        graded.remote = ref
        let score = (obj["score"] as? NSNumber)?.doubleValue ?? 0
        let xp = (obj["earned_xp"] as? NSNumber)?.intValue ?? 0
        let coins = (obj["earned_coins"] as? NSNumber)?.intValue ?? 0
        return (GradeResult(score: score, earnedXP: xp, earnedCoins: coins, fullCase: graded), nil)
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

    // MARK: - Admin content management (edit / delete published content)
    //
    // The admin signs in as a user listed in public.admins, whose JWT is granted
    // full access to the content/emergencies tables (the "admin write … for all"
    // RLS policies). So an admin can read the RAW rows — full payload *with* the
    // answer key, unlike the answer-stripped get_cases() players use — and PATCH
    // or DELETE them by id. These power the "Manage published content" screen.

    /// A published clinical/daily row fetched with its server id, ready to edit.
    struct AdminCaseRow: Identifiable {
        let id: String            // server uuid
        let kind: String          // "clinical" | "daily"
        var clinicalCase: ClinicalCase
        var date: Date?           // daily only — the GMT day it appears on
    }

    /// A published emergency row with its server id and local fire time.
    struct AdminEmergencyRow: Identifiable {
        let id: String
        var clinicalCase: ClinicalCase
        var fireDate: Date        // reconstructed from send_date + local_hour/minute
    }

    /// Fetch every published clinical & daily case (newest first), with answers.
    func fetchPublishedCases() async throws -> [AdminCaseRow] {
        guard isConfigured else { throw SBError.notConfigured }
        guard isAdminSignedIn else { throw SBError.notSignedIn }
        let (data, _) = try await send(method: "GET",
            path: "rest/v1/content?select=id,kind,payload,created_at&order=created_at.desc", admin: true)
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var out: [AdminCaseRow] = []
        for row in rows {
            guard let id = row["id"] as? String, let kind = row["kind"] as? String,
                  let payload = row["payload"],
                  let pdata = try? JSONSerialization.data(withJSONObject: payload) else { continue }
            switch kind {
            case "clinical":
                if let c = try? JSONDecoder().decode(CaseDTO.self, from: pdata).toModel("published", requireKey: false) {
                    out.append(AdminCaseRow(id: id, kind: kind, clinicalCase: c, date: nil))
                }
            case "daily":
                if let d = try? JSONDecoder().decode(DailyDTO.self, from: pdata).toModel("published", requireKey: false) {
                    out.append(AdminCaseRow(id: id, kind: kind, clinicalCase: d.clinicalCase, date: d.date))
                }
            default: break   // ignore other kinds (mcq/mastery)
            }
        }
        return out
    }

    /// Fetch every published emergency (newest first), with answers.
    func fetchPublishedEmergencies() async throws -> [AdminEmergencyRow] {
        guard isConfigured else { throw SBError.notConfigured }
        guard isAdminSignedIn else { throw SBError.notSignedIn }
        let (data, _) = try await send(method: "GET",
            path: "rest/v1/emergencies?select=id,payload,send_date,local_hour,local_minute,created_at&order=created_at.desc",
            admin: true)
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        var out: [AdminEmergencyRow] = []
        for row in rows {
            guard let id = row["id"] as? String,
                  let sendDate = row["send_date"] as? String,
                  let payload = row["payload"],
                  let pdata = try? JSONSerialization.data(withJSONObject: payload),
                  let c = try? JSONDecoder().decode(CaseDTO.self, from: pdata).toModel("published emergency", requireKey: false)
            else { continue }
            let parts = sendDate.split(separator: "-").compactMap { Int($0) }
            var comps = DateComponents()
            if parts.count == 3 { comps.year = parts[0]; comps.month = parts[1]; comps.day = parts[2] }
            comps.hour = (row["local_hour"] as? Int) ?? 0
            comps.minute = (row["local_minute"] as? Int) ?? 0
            out.append(AdminEmergencyRow(id: id, clinicalCase: c, fireDate: cal.date(from: comps) ?? Date()))
        }
        return out
    }

    func updatePublishedClinical(id: String, case c: ClinicalCase) async throws {
        try await patch(id: id, path: "rest/v1/content",
                        row: OutRow(kind: "clinical", payload: CaseDTO(from: c)))
    }

    func updatePublishedDaily(id: String, case c: ClinicalCase, date: Date) async throws {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "GMT"); f.dateFormat = "yyyy-MM-dd"
        try await patch(id: id, path: "rest/v1/content",
                        row: OutRow(kind: "daily",
                                    payload: DailyDTO(date: f.string(from: date), clinicalCase: CaseDTO(from: c))))
    }

    func updatePublishedEmergency(id: String, case c: ClinicalCase, on date: Date) async throws {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let sendDate = String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
        try await patch(id: id, path: "rest/v1/emergencies",
                        row: EmergRow(payload: CaseDTO(from: c), send_date: sendDate,
                                      local_hour: comps.hour ?? 0, local_minute: comps.minute ?? 0))
    }

    func deletePublishedCase(id: String) async throws {
        guard isConfigured else { throw SBError.notConfigured }
        guard isAdminSignedIn else { throw SBError.notSignedIn }
        _ = try await send(method: "DELETE", path: "rest/v1/content?id=eq.\(id)", admin: true,
                           extraHeaders: ["Prefer": "return=minimal"])
    }

    func deletePublishedEmergency(id: String) async throws {
        guard isConfigured else { throw SBError.notConfigured }
        guard isAdminSignedIn else { throw SBError.notSignedIn }
        _ = try await send(method: "DELETE", path: "rest/v1/emergencies?id=eq.\(id)", admin: true,
                           extraHeaders: ["Prefer": "return=minimal"])
    }

    private func patch<T: Encodable>(id: String, path: String, row: T) async throws {
        guard isConfigured else { throw SBError.notConfigured }
        guard isAdminSignedIn else { throw SBError.notSignedIn }
        let body = try JSONEncoder().encode(row)
        _ = try await send(method: "PATCH", path: "\(path)?id=eq.\(id)", body: body, admin: true,
                           extraHeaders: ["Prefer": "return=minimal"])
    }

    // MARK: - AI case tutor (Pro "Ask AI about this case")

    /// One chat turn sent to / from the AI tutor. `role` is "user" or "assistant".
    struct AIMessage: Codable { let role: String; let content: String }
    private struct AIRequest: Encodable {
        let provider: String       // "openai" (ChatGPT) or "gemini"
        let caseContext: String
        let messages: [AIMessage]
    }

    /// Ask the case tutor a follow-up question through the `ask-ai` Edge Function
    /// (which holds the OpenAI / Gemini keys server-side). Returns the reply text.
    func askAI(provider: String, caseContext: String, messages: [AIMessage]) async throws -> String {
        guard isConfigured else { throw SBError.notConfigured }
        guard isSignedIn else { throw SBError.notSignedIn }
        let body = try JSONEncoder().encode(AIRequest(provider: provider, caseContext: caseContext, messages: messages))
        do {
            let (data, _) = try await send(method: "POST", path: "functions/v1/ask-ai", body: body, player: true)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let reply = obj["reply"] as? String, !reply.isEmpty {
                return reply
            }
            throw SBError.http(0, "The AI returned an empty response. Try again.")
        } catch let SBError.http(_, msg) {
            // The function replies with { "error": "..." } on failure — surface it.
            if let d = msg.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let err = obj["error"] as? String {
                throw SBError.http(0, err)
            }
            throw SBError.http(0, "Couldn't reach the AI tutor. Check your connection and try again.")
        }
    }

    // MARK: - Account deletion (App Store 5.1.1)

    /// Permanently delete the signed-in user's account + data through the
    /// `delete-account` Edge Function, then clear the local session.
    func deleteAccount() async throws {
        guard isConfigured, isSignedIn else { throw SBError.notSignedIn }
        do {
            _ = try await send(method: "POST", path: "functions/v1/delete-account",
                               body: Data("{}".utf8), player: true)
        } catch let SBError.http(_, msg) {
            if let d = msg.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let err = obj["error"] as? String {
                throw SBError.http(0, err)
            }
            throw SBError.http(0, "Couldn't delete your account. Check your connection and try again.")
        }
        signOutPlayer()
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
