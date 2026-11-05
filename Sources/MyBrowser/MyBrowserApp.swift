import SwiftUI

extension Notification.Name {
    static let focusAddressBar = Notification.Name("focusAddressBar")
    static let focusFindField = Notification.Name("focusFindField")
}

/// One browser window. Each window owns its own tabs; private windows use an in-memory data store.
struct BrowserWindow: View {
    @StateObject private var state: BrowserState
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var downloads: DownloadStore
    @EnvironmentObject var updater: Updater

    init(isPrivate: Bool) {
        _state = StateObject(wrappedValue: BrowserState(isPrivate: isPrivate))
    }

    var body: some View {
        ContentView()
            .environmentObject(state)
            .focusedSceneObject(state) // lets menu commands act on the frontmost window
            .frame(minWidth: 800, minHeight: 500)
            .onAppear {
                state.history = history
                state.downloads = downloads
                updater.autoCheckIfDue()
                state.installClickMonitor()
                if state.isPrivate {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .focusAddressBar, object: nil)
                    }
                }
            }
    }
}

@main
struct MyBrowserApp: App {
    @StateObject private var bookmarks = BookmarkStore()
    @StateObject private var history = HistoryStore()
    @StateObject private var downloads = DownloadStore()
    @StateObject private var spaceStore = SpaceStore.shared
    @StateObject private var updater = Updater()

    init() {
        // Show hover tooltips quickly (macOS default is over a second). Value is in milliseconds.
        UserDefaults.standard.set(150, forKey: "NSInitialToolTipDelay")
        // A SwiftPM executable isn't a bundled app, so promote it to a regular
        // app with a Dock icon and menu bar.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("MyBrowser", id: "main") {
            BrowserWindow(isPrivate: false)
                .environmentObject(bookmarks)
                .environmentObject(history)
                .environmentObject(downloads)
                .environmentObject(spaceStore)
                .environmentObject(updater)
        }
        .commands {
            BrowserCommands(bookmarks: bookmarks, history: history, spaceStore: spaceStore, updater: updater)
        }

        WindowGroup("Private Browsing", id: "private") {
            BrowserWindow(isPrivate: true)
                .environmentObject(bookmarks)
                .environmentObject(history)
                .environmentObject(downloads)
                .environmentObject(spaceStore)
                .environmentObject(updater)
        }

        Settings {
            SettingsView()
                .environmentObject(history)
                .environmentObject(updater)
        }
    }
}

struct BrowserCommands: Commands {
    /// The window currently in front.
    @FocusedObject private var state: BrowserState?
    @Environment(\.openWindow) private var openWindow
    @AppStorage("tabLayout") private var tabLayout = "sidebar"
    @ObservedObject var bookmarks: BookmarkStore
    @ObservedObject var history: HistoryStore
    @ObservedObject var spaceStore: SpaceStore
    @ObservedObject var updater: Updater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates(userInitiated: true) }
        }

        CommandGroup(replacing: .sidebar) {
            Button("Toggle Sidebar") { state?.toggleSidebar() }
                .keyboardShortcut("\\")
            Button(tabLayout == "top" ? "Show Tabs in Sidebar" : "Show Tabs Across the Top") {
                tabLayout = tabLayout == "top" ? "sidebar" : "top"
            }
            .keyboardShortcut("\\", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .newItem) {
            Button("New Tab") { state?.newTabAndFocus() }
                .keyboardShortcut("t")
            Button("New Window") { openWindow(id: "main") }
                .keyboardShortcut("n")
            Button("New Private Window") { openWindow(id: "private") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Close Tab") { state?.closeSelected() }
                .keyboardShortcut("w")
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        CommandMenu("Bookmarks") {
            Button("Bookmark This Page") {
                bookmarks.toggle(title: state?.selected?.title ?? "", url: state?.selected?.url)
            }
            .keyboardShortcut("d")
            if !bookmarks.items.isEmpty {
                Divider()
                ForEach(bookmarks.unfiled) { bookmark in
                    Button(bookmark.title) { state?.newTab(url: bookmark.url) }
                }
                ForEach(bookmarks.folders, id: \.self) { folder in
                    Menu(folder) {
                        ForEach(bookmarks.items(in: folder)) { bookmark in
                            Button(bookmark.title) { state?.newTab(url: bookmark.url) }
                        }
                    }
                }
            }
        }

        CommandMenu("Spaces") {
            Button("New Space…") {
                if let name = promptForText(title: "New Space",
                                            message: "For example: Work, School, a project name.",
                                            confirm: "Create") {
                    state?.createSpace(name: name)
                }
            }
            if let space = state?.currentSpace {
                Button("Rename Current Space…") {
                    if let name = promptForText(title: "Rename Space", defaultValue: space.name, confirm: "Rename") {
                        spaceStore.rename(space.id, to: name)
                    }
                }
                Button("Delete Current Space…") {
                    if confirmAction("Delete “\(space.name)”?",
                                     message: "Its tabs will be closed. Bookmarks and history are kept.",
                                     button: "Delete") {
                        state?.deleteSpace(space.id)
                    }
                }
                .disabled(spaceStore.spaces.count < 2)
            }
            Divider()
            // Ctrl+1 ... Ctrl+9 jump to the first nine spaces.
            ForEach(Array(spaceStore.spaces.enumerated()), id: \.element.id) { index, space in
                if index < 9 {
                    Button(space.name) { state?.switchSpace(space.id) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .control)
                } else {
                    Button(space.name) { state?.switchSpace(space.id) }
                }
            }
        }

        CommandMenu("History") {
            Button("Show History") { state?.panel = .history }
                .keyboardShortcut("y")
            Button("Show Downloads") { state?.panel = .downloads }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            Divider()
            Button("Clear History…") {
                if confirmAction("Clear all browsing history?") { history.clear() }
            }
        }

        CommandMenu("Navigate") {
            Button("Open Location") {
                NotificationCenter.default.post(name: .focusAddressBar, object: nil)
            }
            .keyboardShortcut("l")
            Button("Back") { state?.selected?.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { state?.selected?.goForward() }
                .keyboardShortcut("]")
            Button("Reload") { state?.selected?.reload() }
                .keyboardShortcut("r")
            Divider()
            Button("Find in Page") { state?.openFind() }
                .keyboardShortcut("f")
            Button("Find Next") { state?.findNext() }
                .keyboardShortcut("g")
            Button("Find Previous") { state?.findNext(backwards: true) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Divider()
            Button("Pin / Unpin Tab") {
                if let tab = state?.selected { state?.togglePin(tab) }
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Next Tab") { state?.selectNext(1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { state?.selectNext(-1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }
    }
}
