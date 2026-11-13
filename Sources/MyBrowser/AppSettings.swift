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
    @AppStorage("iconOnlyTabs") private var iconOnlyTabs = false
    @AppStorage("keepSignedIn") private var keepSignedIn = true
    @AppStorage("memorySaverMinutes") private var memorySaverMinutes = 30
    @AppStorage("memorySaverProtectPinned") private var memorySaverProtectPinned = false
    @ObservedObject private var hiddenSites = HiddenSitesStore.shared
    @State private var newHiddenSite = ""
    @AppStorage("blockYouTubeAds") private var blockYouTubeAds = true
    @AppStorage("skipSponsors") private var skipSponsors = true
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var updater: Updater
    @State private var message = ""

    private func addHiddenSite() {
        if hiddenSites.add(newHiddenSite) != nil {
            history.purgeHidden()
            newHiddenSite = ""
            message = ""
        } else {
            message = "That doesn't look like a site address. Try something like example.com."
        }
    }

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
                Toggle("Show only icons on tabs (top layout)", isOn: $iconOnlyTabs)
                Text("Shrinks each tab to just its site icon, as large as the tab bar allows. Hover a tab to see its title and a small close button.")
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

            Section("Memory saver") {
                Picker("Free memory from tabs unused for", selection: $memorySaverMinutes) {
                    Text("Never").tag(0)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                }
                Toggle("Leave pinned tabs alone", isOn: $memorySaverProtectPinned)
                Text("Stops the page of a tab you haven't looked at for this long. The tab and its Space stay put, nothing is closed, and the page reloads when you click it. Tabs playing audio or video, and the tab you're on, are never touched. Unsaved form text and scroll position in a freed tab are lost.")
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

            Section("Ads") {
                Toggle("Block YouTube ads (experimental)", isOn: $blockYouTubeAds)
                Text("Best effort. YouTube changes often, so this may stop working at times. Applies to tabs opened after you change it; reload open YouTube tabs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("YouTube sponsors") {
                Toggle("Skip sponsored segments", isOn: $skipSponsors)
                Text("Uses SponsorBlock, a community database (sponsor.ajay.app). It skips sponsor reads, self-promotion and subscribe reminders. For each video, only a short code made from the video ID is sent to SponsorBlock, not the video itself. Applies to tabs opened after you change it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hidden from history") {
                ForEach(hiddenSites.sites, id: \.self) { site in
                    HStack {
                        Text(site)
                        Spacer()
                        Button { hiddenSites.remove(site) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Stop hiding \(site)")
                    }
                }
                HStack {
                    TextField("Add a site, e.g. example.com", text: $newHiddenSite)
                        .onSubmit(addHiddenSite)
                    Button("Add", action: addHiddenSite)
                        .disabled(newHiddenSite.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Visits to these sites, and everything on them (including subdomains like mail.example.com), are never saved to history or shown in suggestions. Adding a site also removes its existing history. Bookmarks aren't affected. You can also right-click any item in History > Show History.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Toggle("Keep me signed in across restarts", isOn: $keepSignedIn)
                Text("Saves the temporary logins sites use, so quitting or updating MyBrowser doesn't sign you out. Sites can still end a login on their side. Turn off on a shared Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .frame(width: 480, height: 1020)
    }
}
