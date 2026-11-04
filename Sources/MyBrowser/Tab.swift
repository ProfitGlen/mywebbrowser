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

    /// The address a pinned tab was pinned at (what gets restored on launch).
    var pinnedURL: URL?

    /// Called when a page asks to open a new tab (target=_blank, window.open, Cmd+click).
    var onOpenInNewTab: ((URLRequest) -> Void)?
    /// Called after every successful page load (used for history).
    var onVisit: ((String, URL) -> Void)?
    /// Called when a navigation turns into a file download.
    var onDownload: ((WKDownload) -> Void)?

    private var observations: [NSKeyValueObservation] = []

    init(url: URL? = nil, dataStore: WKWebsiteDataStore = .default(), spaceID: UUID, loadNow: Bool = true) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore // .default() persists, .nonPersistent() is private
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
        onOpenInNewTab?(navigationAction.request)
        return nil
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url { onVisit?(webView.title ?? "", url) }
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
