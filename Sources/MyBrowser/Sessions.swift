import WebKit

/// Keeps you signed in across restarts and updates.
///
/// Many sites sign you in with a "session" cookie that has no expiry date, and WebKit throws those
/// away when the app quits. This watches the cookie store and gives each session cookie a long
/// expiry (400 days, the same cap Chrome uses), so it is saved to disk like a normal cookie.
/// It can't extend how long a site itself keeps you signed in on its server.
final class SessionKeeper: NSObject, WKHTTPCookieStoreObserver {
    static let shared = SessionKeeper()
    static let defaultsKey = "keepSignedIn"
    private static let lifetime: TimeInterval = 400 * 24 * 60 * 60

    private var store: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true
    }

    func start() {
        store.add(self)
        persistSessionCookies()
    }

    private var pending: DispatchWorkItem?

    /// Waits for cookie changes to settle before touching anything, so a sign-in in progress
    /// (which sets and deletes short-lived cookies in quick succession) is never interfered with.
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        DispatchQueue.main.async {
            self.pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.persistSessionCookies() }
            self.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
        }
    }

    private func persistSessionCookies() {
        guard enabled else { return }
        store.getAllCookies { cookies in
            for cookie in cookies where cookie.isSessionOnly {
                var properties = cookie.properties ?? [:]
                properties.removeValue(forKey: .discard)
                properties.removeValue(forKey: .maximumAge)
                properties[.expires] = Date().addingTimeInterval(Self.lifetime)
                if let longLived = HTTPCookie(properties: properties) {
                    self.store.setCookie(longLived)
                }
            }
        }
    }
}
