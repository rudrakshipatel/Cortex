import AuthenticationServices
import UIKit

/// Thin async wrapper around `ASWebAuthenticationSession` used for Supabase
/// OAuth (Sign in with Google / Apple). The callback scheme is intercepted by
/// the system, so it does not need to be registered in Info.plist.
@MainActor
enum WebAuthSession {
    static func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let presenter = AuthPresenter()
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                _ = presenter   // keep presenter (and the session it holds) alive until the callback fires
                if let callbackURL {
                    cont.resume(returning: callbackURL)
                } else {
                    cont.resume(throwing: error ?? URLError(.userCancelledAuthentication))
                }
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            presenter.session = session
            if !session.start() {
                cont.resume(throwing: URLError(.cannotConnectToHost))
            }
        }
    }
}

private final class AuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    var session: ASWebAuthenticationSession?   // strong ref so the sheet isn't dismissed early
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
