import SwiftUI
import WebKit

/// One browser tab: owns a WKWebView and publishes its state to the UI.
final class Tab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let webView: WKWebView

    /// Which space this tab belongs to.
    var spaceID: UUID
    /// A restored pinned tab in a space you haven't opened yet isn't loaded until you switch to it.
    private var pendingURL: URL?

    @Published var title = "New Tab"
    @Published var url: URL?
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isPinned = false
    /// Set false for private windows so their icons aren't saved to disk.
    var persistFavicons = true

    /// The address a pinned tab was pinned at (what gets restored on launch).
    var pinnedURL: URL?

    /// Called when a page asks to open a new tab (target=_blank, window.open, Cmd+click).
    var onOpenInNewTab: ((URLRequest) -> Void)?
    /// Called after every successful page load (used for history).
    var onVisit: ((String, URL) -> Void)?
    /// Called when a navigation turns into a file download.
    var onDownload: ((WKDownload) -> Void)?

    private var observations: [NSKeyValueObservation] = []

    /// Called when a page opens a popup (window.open). Must return a tab built from the given configuration.
    var onCreatePopup: ((WKWebViewConfiguration) -> Tab?)?
    /// Called when the page closes itself (window.close), e.g. after a sign-in popup finishes.
    var onClose: (() -> Void)?

    /// The version of the Safari installed on this Mac (major.minor, as Safari reports it in its
    /// user agent), so MyBrowser stays current as macOS updates Safari. Falls back to a guess from
    /// the macOS version if Safari can't be read.
    static let safariVersion: String = {
        let paths = ["/Applications/Safari.app",
                     "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app",
                     "/System/Applications/Safari.app"]
        for path in paths {
            if let version = Bundle(path: path)?.infoDictionary?["CFBundleShortVersionString"] as? String {
                let parts = version.split(separator: ".").prefix(2)
                if parts.count >= 1, parts.allSatisfy({ Int($0) != nil }) { return parts.joined(separator: ".") }
            }
        }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion >= 26 ? "\(v.majorVersion).\(v.minorVersion)" : "18.6"
    }()

    /// Safari-like identity, because sites such as Google refuse sign-in from unknown embedded browsers.
    static func makeConfiguration(dataStore: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore // .default() persists, .nonPersistent() is private
        config.applicationNameForUserAgent = "Version/\(safariVersion) Safari/605.1.15"
        YouTubeAdBlocker.install(in: config.userContentController)
        SponsorBlock.install(in: config.userContentController)
        return config
    }

    convenience init(url: URL? = nil, dataStore: WKWebsiteDataStore = .default(), spaceID: UUID, loadNow: Bool = true) {
        self.init(configuration: Tab.makeConfiguration(dataStore: dataStore), spaceID: spaceID)
        if let url {
            if loadNow {
                webView.load(URLRequest(url: url))
            } else {
                pendingURL = url
                self.url = url
                title = url.host ?? "New Tab"
            }
        }
    }

    init(configuration config: WKWebViewConfiguration, spaceID: UUID) {
        webView = WKWebView(frame: .zero, configuration: config)
        self.spaceID = spaceID
        super.init()

        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self

        observations = [
            webView.observe(\.title) { [weak self] web, _ in
                guard let self else { return }
                if let t = web.title, !t.isEmpty { self.title = t }
                else { self.title = web.url?.host ?? "New Tab" }
            },
            webView.observe(\.url) { [weak self] web, _ in self?.url = web.url },
            webView.observe(\.isLoading) { [weak self] web, _ in self?.isLoading = web.isLoading },
            webView.observe(\.estimatedProgress) { [weak self] web, _ in self?.progress = web.estimatedProgress },
            webView.observe(\.canGoBack) { [weak self] web, _ in self?.canGoBack = web.canGoBack },
            webView.observe(\.canGoForward) { [weak self] web, _ in self?.canGoForward = web.canGoForward },
        ]
    }

    func load(_ url: URL) {
        pendingURL = nil
        webView.load(URLRequest(url: url))
    }

    /// Loads a deferred (restored but not yet opened) tab.
    func ensureLoaded() {
        guard let url = pendingURL else { return }
        pendingURL = nil
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }

    // MARK: Find in page

    func find(_ text: String, backwards: Bool = false, completion: @escaping (Bool) -> Void) {
        guard !text.isEmpty else {
            clearFind()
            completion(true)
            return
        }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.wraps = true
        config.caseSensitive = false
        webView.find(text, configuration: config) { result in
            completion(result.matchFound)
        }
    }

    func clearFind() {
        webView.evaluateJavaScript("window.getSelection().removeAllRanges()", completionHandler: nil)
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Return a web view built from WebKit's configuration so window.opener keeps working
        // (needed by "Sign in with Google" and other OAuth popups). WebKit loads the request itself.
        return onCreatePopup?(configuration)?.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        onClose?()
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url { onVisit?(webView.title ?? "", url) }
        loadFavicon()
    }

    /// Finds the page's best icon (apple-touch-icon / PNG / ICO) and hands it to the shared store.
    private func loadFavicon() {
        guard let pageURL = webView.url, let host = pageURL.host,
              pageURL.scheme == "http" || pageURL.scheme == "https" else { return }
        let js = """
        (function(){
          var best='', bestSize=-1;
          document.querySelectorAll('link[rel*="icon"]').forEach(function(e){
            var h=e.href; if(!h) return;
            if(/\\.svg(\\?|$)/i.test(h) || (e.type||'').indexOf('svg')>=0) return;
            var m=((e.getAttribute('sizes')||'')).match(/(\\d+)x/);
            var size = m ? parseInt(m[1]) : (/apple-touch/.test(e.rel) ? 180 : 16);
            if(size>192) size=1;
            if(size>bestSize){bestSize=size;best=h;}
          });
          return best;
        })()
        """
        let persist = persistFavicons
        webView.evaluateJavaScript(js) { result, _ in
            var iconURL: URL?
            if let string = result as? String, !string.isEmpty { iconURL = URL(string: string) }
            if iconURL == nil { iconURL = URL(string: "\(pageURL.scheme ?? "https")://\(host)/favicon.ico") }
            if let iconURL { FaviconStore.shared.fetch(iconURL: iconURL, host: host, persist: persist) }
        }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        // Cmd+click opens in a new tab.
        if navigationAction.navigationType == .linkActivated,
           navigationAction.modifierFlags.contains(.command) {
            onOpenInNewTab?(navigationAction.request)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // Anything WebKit can't display (zip, dmg, ...) becomes a download.
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView,
                 navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        onDownload?(download)
    }

    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        onDownload?(download)
    }
}
