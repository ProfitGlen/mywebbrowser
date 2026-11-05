import SwiftUI
import WebKit

enum SearchEngine: String, CaseIterable, Identifiable {
    case google, duckDuckGo, bing, brave

    var id: String { rawValue }

    var name: String {
        switch self {
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .brave: return "Brave Search"
        }
    }

    /// %@ is replaced with the percent-encoded query.
    var template: String {
        switch self {
        case .google: return "https://www.google.com/search?q=%@"
        case .duckDuckGo: return "https://duckduckgo.com/?q=%@"
        case .bing: return "https://www.bing.com/search?q=%@"
        case .brave: return "https://search.brave.com/search?q=%@"
        }
    }
}

/// Reads the values the Settings window writes with @AppStorage.
enum AppSettings {
    static let defaultHomepage = "https://www.google.com"

    static var homepage: URL {
        let raw = (UserDefaults.standard.string(forKey: "homepage") ?? defaultHomepage)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return BrowserState.resolve(raw.isEmpty ? defaultHomepage : raw)
    }

    static var searchEngine: SearchEngine {
        SearchEngine(rawValue: UserDefaults.standard.string(forKey: "searchEngine") ?? "") ?? .google
    }

    static func searchURL(for query: String) -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        let urlString = searchEngine.template.replacingOccurrences(of: "%@", with: encoded)
        return URL(string: urlString) ?? URL(string: defaultHomepage)!
    }
}

struct SettingsView: View {
    @AppStorage("searchEngine") private var engine = SearchEngine.google.rawValue
    @AppStorage("homepage") private var homepage = AppSettings.defaultHomepage
    @AppStorage("autoUpdate") private var autoUpdate = true
    @AppStorage("autoCollapseSidebar") private var autoCollapseSidebar = false
    @AppStorage("tabLayout") private var tabLayout = "sidebar"
    @AppStorage("mergeTitleBar") private var mergeTitleBar = true
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var updater: Updater
    @State private var message = ""

    var body: some View {
        Form {
            Picker("Search engine", selection: $engine) {
                ForEach(SearchEngine.allCases) { Text($0.name).tag($0.rawValue) }
            }
            TextField("Home page", text: $homepage)

            Section("Layout") {
                Picker("Tabs and bookmarks", selection: $tabLayout) {
                    Text("Sidebar (vertical)").tag("sidebar")
                    Text("Across the top").tag("top")
                }
                Toggle("Toolbar shares the title bar row (Safari style)", isOn: $mergeTitleBar)
                Text("Turn this off if the address bar or buttons ever go missing, then quit and reopen MyBrowser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Across the top shows tabs in a strip above the address bar and bookmarks in a row below it. Switch any time with ⌥⌘\\.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sidebar") {
                Toggle("Shrink sidebar to icons automatically", isOn: $autoCollapseSidebar)
                Text("Shrinks after you click a tab or bookmark in the sidebar, or click the page. Expand it again with ⌘\\ or the sidebar button.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                LabeledContent("Version", value: Updater.currentVersion)
                Toggle("Check for updates automatically", isOn: $autoUpdate)
                Button(updater.isChecking ? "Checking…" : "Check Now") {
                    updater.checkForUpdates(userInitiated: true)
                }
                .disabled(updater.isChecking)
            }

            Section("Privacy") {
                Button("Clear Browsing History…") {
                    if confirmAction("Clear all browsing history?") {
                        history.clear()
                        message = "History cleared."
                    }
                }
                Button("Clear Cookies and Website Data…") {
                    if confirmAction("Clear cookies and website data?",
                                     message: "You will be signed out of websites.") {
                        WKWebsiteDataStore.default().removeData(
                            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                            modifiedSince: .distantPast
                        ) { message = "Website data cleared." }
                    }
                }
                if !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 720)
    }
}
