import SwiftUI
import WebKit
import Combine

enum Panel: String, Identifiable {
    case history, downloads, notes
    var id: String { rawValue }
}

/// State for one browser window: its tabs (grouped into spaces), selection, address bar,
/// find bar and open panel.
final class BrowserState: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var selectedID: UUID?
    @Published var currentSpaceID: UUID
    /// Sidebar shrunk to an icon rail.
    @Published var sidebarCollapsed: Bool {
        didSet { UserDefaults.standard.set(sidebarCollapsed, forKey: "sidebarCollapsed") }
    }
    @Published var addressText = ""
    /// True while the user is typing in the address bar (drives the suggestions dropdown).
    @Published var addressEditing = false
    @Published var panel: Panel?

    @Published var showFind = false
    @Published var findText = ""
    @Published var findNotFound = false

    let isPrivate: Bool
    /// Private windows get a throwaway in-memory store shared by their tabs.
    let dataStore: WKWebsiteDataStore

    /// Set by the window once it appears (owned by the App).
    weak var history: HistoryStore?
    weak var downloads: DownloadStore?

    /// The tab you were last on in each space.
    private var lastSelected: [UUID: UUID] = [:]
    private var spaceObserver: AnyCancellable?

    private static let pinnedKey = "pinnedTabsBySpace"
    private static let legacyPinnedKey = "pinnedTabURLs"
    private static let lastSpaceKey = "lastSpaceID"

    // MARK: Derived

    var currentSpace: Space {
        SpaceStore.shared.space(currentSpaceID) ?? SpaceStore.shared.spaces[0]
    }
    var selected: Tab? { tabs.first { $0.id == selectedID } }
    /// Tabs in the current space only.
    var spaceTabs: [Tab] { tabs.filter { $0.spaceID == currentSpaceID } }
    var pinnedTabs: [Tab] { spaceTabs.filter { $0.isPinned } }
    var regularTabs: [Tab] { spaceTabs.filter { !$0.isPinned } }

    // MARK: Init

    init(isPrivate: Bool = false) {
        self.isPrivate = isPrivate
        self.dataStore = isPrivate ? WKWebsiteDataStore.nonPersistent() : WKWebsiteDataStore.default()
        self.sidebarCollapsed = UserDefaults.standard.bool(forKey: "sidebarCollapsed")

        let store = SpaceStore.shared
        let savedID = UUID(uuidString: UserDefaults.standard.string(forKey: BrowserState.lastSpaceKey) ?? "")
        self.currentSpaceID = store.spaces.first(where: { $0.id == savedID })?.id ?? store.spaces[0].id

        if isPrivate {
            newTab()
        } else {
            let pins = BrowserState.loadPins(fallbackSpace: store.spaces[0].id)
            for space in store.spaces {
                for url in pins[space.id] ?? [] {
                    // Only the space you open into loads right away.
                    let tab = newTab(url: url, select: false, spaceID: space.id, loadNow: space.id == currentSpaceID)
                    tab.isPinned = true
                    tab.pinnedURL = url
                }
            }
            newTab(url: AppSettings.homepage)
        }

        // If a space is deleted (from any window), close its tabs and move off it.
        spaceObserver = store.$spaces
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spaces in self?.reconcile(spaces) }

        // Memory saver: once a minute, empty tabs you haven't looked at for a while.
        saverTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.runMemorySaver()
        }
    }

    deinit { saverTimer?.invalidate() }

    private var saverTimer: Timer?

    /// Frees the memory of tabs unused for the chosen time. Tabs and Spaces stay exactly where
    /// they are; a freed tab reloads when you click it. Never touches the tab you're on,
    /// tabs playing audio/video, or (optionally) pinned tabs.
    private func runMemorySaver() {
        selected?.lastActive = Date()
        let defaults = UserDefaults.standard
        let minutes = defaults.object(forKey: "memorySaverMinutes") as? Int ?? 30
        guard minutes > 0 else { return }
        let protectPinned = defaults.bool(forKey: "memorySaverProtectPinned")
        let cutoff = Date().addingTimeInterval(-Double(minutes) * 60)
        for tab in tabs where tab.id != selectedID && tab.lastActive < cutoff {
            if protectPinned && tab.isPinned { continue }
            tab.discard()
        }
    }

    // MARK: Tabs

    @discardableResult
    func newTab(url: URL? = nil, select: Bool = true, spaceID: UUID? = nil, loadNow: Bool = true) -> Tab {
        let space = spaceID ?? currentSpaceID
        let tab = Tab(url: url, dataStore: dataStore, spaceID: space, loadNow: loadNow)
        wire(tab)
        tabs.append(tab)
        if select {
            selectedID = tab.id
            lastSelected[space] = tab.id
            addressText = url?.absoluteString ?? ""
            showFind = false
        }
        return tab
    }

    private func wire(_ tab: Tab) {
        tab.persistFavicons = !isPrivate
        tab.onOpenInNewTab = { [weak self] request in
            guard let url = request.url else { return }
            self?.newTab(url: url)
        }
        tab.onVisit = { [weak self] title, url in
            guard let self, !self.isPrivate else { return }
            self.history?.add(title: title, url: url)
        }
        tab.onDownload = { [weak self] download in
            self?.downloads?.add(download)
        }
        tab.onCreatePopup = { [weak self, weak tab] configuration in
            guard let self, let tab else { return nil }
            let popup = Tab(configuration: configuration, spaceID: tab.spaceID)
            self.wire(popup)
            popup.onClose = { [weak self, weak popup] in
                guard let self, let popup else { return }
                DispatchQueue.main.async { self.close(popup) }
            }
            self.tabs.append(popup)
            self.selectedID = popup.id
            self.lastSelected[popup.spaceID] = popup.id
            self.showFind = false
            return popup
        }
    }

    /// Opens a blank tab and puts the cursor in the address bar.
    func newTabAndFocus() {
        newTab()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .focusAddressBar, object: nil)
        }
    }

    func select(_ tab: Tab) {
        if tab.spaceID != currentSpaceID {
            currentSpaceID = tab.spaceID
            UserDefaults.standard.set(tab.spaceID.uuidString, forKey: BrowserState.lastSpaceKey)
        }
        tab.ensureLoaded()
        selectedID = tab.id
        lastSelected[tab.spaceID] = tab.id
        addressText = tab.url?.absoluteString ?? ""
        addressEditing = false
        showFind = false
    }

    func close(_ tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        let spaceID = tab.spaceID
        let position = tabs.filter { $0.spaceID == spaceID }.firstIndex(where: { $0.id == tab.id }) ?? 0
        let wasPinned = tab.isPinned

        tabs.removeAll { $0.id == tab.id }
        if wasPinned { savePins() }

        let remaining = tabs.filter { $0.spaceID == spaceID }
        if remaining.isEmpty {
            if spaceID == currentSpaceID { newTab(url: isPrivate ? nil : AppSettings.homepage) }
        } else if selectedID == tab.id {
            select(remaining[min(position, remaining.count - 1)])
        }
    }

    func closeSelected() { if let t = selected { close(t) } }

    func selectNext(_ offset: Int) {
        let list = spaceTabs
        guard let current = list.firstIndex(where: { $0.id == selectedID }), !list.isEmpty else { return }
        select(list[(current + offset + list.count) % list.count])
    }

    // MARK: Spaces

    func switchSpace(_ id: UUID) {
        guard id != currentSpaceID, SpaceStore.shared.space(id) != nil else { return }
        currentSpaceID = id
        UserDefaults.standard.set(id.uuidString, forKey: BrowserState.lastSpaceKey)
        showFind = false

        let inSpace = tabs.filter { $0.spaceID == id }
        inSpace.filter { $0.isPinned }.forEach { $0.ensureLoadedIfNeverOpened() }

        if let remembered = lastSelected[id], let tab = inSpace.first(where: { $0.id == remembered }) {
            select(tab)
        } else if let first = inSpace.first(where: { !$0.isPinned }) ?? inSpace.first {
            select(first)
        } else {
            newTabAndFocus()
        }
    }

    func createSpace(name: String) {
        let space = SpaceStore.shared.add(name: name)
        switchSpace(space.id)
    }

    func deleteSpace(_ id: UUID) {
        SpaceStore.shared.delete(id) // reconcile() below cleans up tabs in every window
    }

    func move(_ tab: Tab, toSpace id: UUID) {
        guard tab.spaceID != id, SpaceStore.shared.space(id) != nil else { return }
        let wasSelected = tab.id == selectedID
        let oldSpace = tab.spaceID
        tab.spaceID = id
        if tab.isPinned { savePins() }
        if wasSelected {
            if let next = tabs.first(where: { $0.spaceID == oldSpace && $0.id != tab.id }) {
                select(next)
            } else {
                newTabAndFocus()
            }
        }
        objectWillChange.send()
    }

    private func reconcile(_ spaces: [Space]) {
        let ids = Set(spaces.map { $0.id })
        if tabs.contains(where: { !ids.contains($0.spaceID) }) {
            tabs.removeAll { !ids.contains($0.spaceID) }
            savePins()
        }
        if !ids.contains(currentSpaceID), let first = spaces.first {
            switchSpace(first.id)
        }
    }

    // MARK: Sidebar

    private var clickMonitor: Any?

    deinit {
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor) }
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) { sidebarCollapsed.toggle() }
    }

    func collapseSidebar() {
        guard !sidebarCollapsed else { return }
        withAnimation(.easeInOut(duration: 0.2)) { sidebarCollapsed = true }
    }

    /// Settings > "Shrink sidebar automatically".
    private var autoCollapseSidebar: Bool {
        UserDefaults.standard.bool(forKey: "autoCollapseSidebar")
    }

    /// Call after the user clicks a tab or bookmark in the sidebar.
    func sidebarItemClicked() {
        if autoCollapseSidebar { collapseSidebar() }
    }

    /// Watches mouse clicks so a click on the page itself (not the sidebar or toolbar) can
    /// shrink the sidebar. The click still goes through to the page.
    func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleMouseDown(event)
            return event
        }
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard let webView = selected?.webView,
              let content = event.window?.contentView,
              let hit = content.hitTest(event.locationInWindow),
              hit.isDescendant(of: webView) else { return }
        if addressEditing { addressEditing = false } // clicking the page closes the suggestions
        guard autoCollapseSidebar, !sidebarCollapsed else { return }
        collapseSidebar()
    }

    // MARK: Pinned tabs

    /// Drag and drop: put the dragged tab where `target` is (same space, same pinned/unpinned group).
    func moveTab(_ id: UUID, onto target: Tab) {
        guard let from = tabs.firstIndex(where: { $0.id == id }),
              let targetIndex = tabs.firstIndex(where: { $0.id == target.id }),
              from != targetIndex else { return }
        let tab = tabs[from]
        guard tab.spaceID == target.spaceID, tab.isPinned == target.isPinned else { return }
        tabs.remove(at: from)
        let newTarget = tabs.firstIndex(where: { $0.id == target.id }) ?? tabs.count
        tabs.insert(tab, at: from < targetIndex ? newTarget + 1 : newTarget)
        if tab.isPinned { savePins() }
    }

    func togglePin(_ tab: Tab) {
        tab.isPinned.toggle()
        tab.pinnedURL = tab.isPinned ? tab.url : nil
        savePins()
        objectWillChange.send() // sidebar groups tabs by pinned state
    }

    private func savePins() {
        guard !isPrivate else { return }
        var result: [String: [String]] = [:]
        for tab in tabs where tab.isPinned {
            if let url = tab.pinnedURL ?? tab.url {
                result[tab.spaceID.uuidString, default: []].append(url.absoluteString)
            }
        }
        UserDefaults.standard.set(result, forKey: BrowserState.pinnedKey)
    }

    /// Pinned tab URLs per space. Older versions saved one flat list, which goes to the first space.
    private static func loadPins(fallbackSpace: UUID) -> [UUID: [URL]] {
        var result: [UUID: [URL]] = [:]
        if let dict = UserDefaults.standard.dictionary(forKey: pinnedKey) as? [String: [String]] {
            for (key, urls) in dict {
                if let id = UUID(uuidString: key) {
                    result[id] = urls.compactMap { URL(string: $0) }
                }
            }
        } else if let legacy = UserDefaults.standard.stringArray(forKey: legacyPinnedKey) {
            result[fallbackSpace] = legacy.compactMap { URL(string: $0) }
        }
        return result
    }

    // MARK: Navigation

    /// Loads in the current tab (or a new one if there is none).
    func openURL(_ url: URL) {
        if let tab = selected { tab.load(url) } else { newTab(url: url) }
    }

    /// Turns whatever was typed into a URL, or a search if it isn't one.
    func submitAddress() {
        let text = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let tab = selected else { return }
        addressEditing = false
        if !isPrivate, BrowserState.isSearch(text) { SearchHistoryStore.shared.add(text) }
        tab.load(BrowserState.resolve(text))
    }

    /// Text field binding that marks the address bar as "being edited" when the user types.
    var addressBinding: Binding<String> {
        Binding(get: { self.addressText },
                set: { self.addressText = $0; self.addressEditing = true })
    }

    /// True when the typed text would be a web search (not an address).
    static func isSearch(_ input: String) -> Bool {
        if let url = URL(string: input), let scheme = url.scheme,
           ["http", "https", "file", "about"].contains(scheme) { return false }
        if !input.contains(" "), input.contains("."),
           let url = URL(string: "https://" + input), url.host != nil { return false }
        if input == "localhost" || input.hasPrefix("localhost:") { return false }
        return true
    }

    static func resolve(_ input: String) -> URL {
        if let url = URL(string: input), let scheme = url.scheme,
           ["http", "https", "file", "about"].contains(scheme) {
            return url
        }
        // Looks like a host (has a dot, no spaces) -> https://
        if !input.contains(" "), input.contains("."),
           let url = URL(string: "https://" + input), url.host != nil {
            return url
        }
        if input == "localhost" || input.hasPrefix("localhost:"),
           let url = URL(string: "http://" + input) {
            return url
        }
        return AppSettings.searchURL(for: input)
    }

    // MARK: Find in page

    func openFind() {
        showFind = true
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .focusFindField, object: nil)
        }
    }

    func closeFind() {
        showFind = false
        findText = ""
        findNotFound = false
        selected?.clearFind()
    }

    func findNext(backwards: Bool = false) {
        guard let tab = selected else { return }
        guard !findText.isEmpty else {
            tab.clearFind()
            findNotFound = false
            return
        }
        tab.find(findText, backwards: backwards) { [weak self] found in
            self?.findNotFound = !found
        }
    }
}
