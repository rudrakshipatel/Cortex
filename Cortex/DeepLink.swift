import Foundation

/// Cortex deep links for "Challenge a friend".
///
/// A shared case link is an **https** URL — `https://www.cortexcases.com/case/{id}`
/// — so it's tappable everywhere and works for people who don't have the app.
/// The web page at that path (hosted on cortexcases.com) tries to open the
/// `cortex://case/{id}` scheme; if Cortex is installed iOS/Android switches to
/// it, otherwise the page forwards to the App Store / Play Store. This file
/// owns both the format we share and the parsing of an incoming link.
///
/// `{id}` is the case's **server** id (`ClinicalCase.remote.id`) — the only
/// identifier that's stable across installs (seed cases get a fresh UUID per
/// launch, so they can't be shared). A case with no server id yields no
/// case-specific link; callers fall back to a plain "download Cortex" link.
enum CXDeepLink {
    static let scheme = "cortex"
    static let webBase = "https://www.cortexcases.com"
    /// Shown when there's no case-specific link to share.
    static var appDownloadURL: URL { URL(string: webBase)! }

    /// A shareable https link for this case, or nil if it isn't a server case.
    static func caseURL(_ c: ClinicalCase) -> URL? {
        guard let id = c.remote?.id, !id.isEmpty else { return nil }
        return URL(string: "\(webBase)/case/\(id)")
    }

    /// A shareable https invite link carrying the user's referral code.
    static func inviteURL(code: String) -> URL? {
        let c = code.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return nil }
        return URL(string: "\(webBase)/invite/\(c)")
    }

    /// Extract a referral code from an incoming invite link, accepting both
    /// `cortex://invite/{code}` and `https://www.cortexcases.com/invite/{code}`.
    static func parseInviteCode(from url: URL) -> String? {
        if url.scheme?.lowercased() == scheme {
            guard url.host?.lowercased() == "invite" else { return nil }
            let code = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return code.isEmpty ? nil : code
        }
        if url.scheme?.lowercased().hasPrefix("http") == true {
            let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            if parts.count >= 2, parts[0].lowercased() == "invite" { return parts[1] }
        }
        return nil
    }

    /// Extract the case id from an incoming link, accepting both the custom
    /// scheme (`cortex://case/{id}`) and the https form
    /// (`https://www.cortexcases.com/case/{id}`). Returns nil for anything else.
    static func parseCaseID(from url: URL) -> String? {
        // Custom scheme: host is "case", path is "/{id}".
        if url.scheme?.lowercased() == scheme {
            guard url.host?.lowercased() == "case" else { return nil }
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.isEmpty ? nil : id
        }
        // Universal/https form: path is "/case/{id}".
        if url.scheme?.lowercased().hasPrefix("http") == true {
            let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            if parts.count >= 2, parts[0].lowercased() == "case" { return parts[1] }
        }
        return nil
    }
}
