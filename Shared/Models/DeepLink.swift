import Foundation

/// Links that open Cortex from outside the app.
///
/// A shared case link is a **Universal Link** on the marketing site:
///
///     https://www.cortexcases.com/case/<server-case-id>[?s=emergency]
///
/// If Cortex is installed, iOS hands the URL straight to the app and we open
/// that case (see the `associated-domains` entitlement, plus the
/// `apple-app-site-association` file the site must serve). If it isn't
/// installed, the same URL simply opens in the browser, and the site redirects
/// it to the App Store. One link, both behaviours — no app-detection hacks.
enum CortexLink: Equatable {
    /// An invite to play one specific case.
    case caseInvite(source: String, id: String)

    /// Marketing site that serves the Universal Link and the store redirect.
    static let webHost = "cortexcases.com"
    /// Where the browser lands when Cortex isn't installed.
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6784620799")!

    /// The shareable link for a case.
    ///
    /// Returns nil for built-in/seed cases: those exist only on this device, so
    /// there is nothing for the recipient to open. Callers fall back to sharing
    /// the App Store link on its own.
    static func shareURL(for clinicalCase: ClinicalCase) -> URL? {
        guard let ref = clinicalCase.remote,
              !ref.id.trimmed.isEmpty else { return nil }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "www.\(webHost)"
        comps.path = "/case/\(ref.id)"
        // "content" is the default source; only tag the unusual one.
        if ref.source != "content" {
            comps.queryItems = [URLQueryItem(name: "s", value: ref.source)]
        }
        return comps.url
    }

    /// Parse an incoming URL into a link we know how to open. Returns nil for
    /// anything else, so unknown URLs are ignored rather than mis-routed.
    static func parse(_ url: URL) -> CortexLink? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host?.lowercased(),
              host == webHost || host.hasSuffix(".\(webHost)") else { return nil }
        let parts = comps.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0].lowercased() == "case" else { return nil }
        let id = parts[1]
        // Server ids are UUIDs — reject anything else rather than chase it.
        guard UUID(uuidString: id) != nil else { return nil }
        let source = comps.queryItems?.first { $0.name == "s" }?.value ?? "content"
        return .caseInvite(source: source, id: id.lowercased())
    }
}
