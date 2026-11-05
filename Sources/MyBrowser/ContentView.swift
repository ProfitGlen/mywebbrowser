import SwiftUI
import WebKit

/// Bridges a Tab's WKWebView into SwiftUI.
struct WebViewContainer: NSViewRepresentable {
    let tab: Tab
    func makeNSView(context: Context) -> WKWebView { tab.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct ContentView: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var bookmarks: BookmarkStore
    @EnvironmentObject var history: HistoryStore
    @FocusState private var addressFocused: Bool

    /// Dropdown under the address bar while typing (hidden when the text is just the current URL).
    private var suggestions: [Suggestion] {
        guard addressFocused, state.addressText != state.selected?.url?.absoluteString else { return [] }
        return Suggestions.matching(state.addressText, bookmarks: bookmarks.items, history: history.entries)
    }

    @AppStorage("sidebarWidth") private var sidebarWidth = 240.0
    /// "sidebar" (vertical, left) or "top" (tab strip + bookmarks bar across the top).
    @AppStorage("tabLayout") private var tabLayout = "sidebar"

    private var detail: some View {
        VStack(spacing: 0) {
            if let tab = state.selected {
                Toolbar(tab: tab, addressFocused: $addressFocused)
                ProgressBar(tab: tab)
                if tabLayout == "top" && !bookmarks.items.isEmpty { BookmarksBar() }
                if state.showFind { FindBar() }
                ZStack(alignment: .top) {
                    WebViewContainer(tab: tab).id(tab.id)
                    if !suggestions.isEmpty {
                        SuggestionsList(suggestions: suggestions) { url in
                            state.openURL(url)
                            addressFocused = false
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var layout: some View {
        if tabLayout == "top" {
            VStack(spacing: 0) {
                TopTabBar()
                Divider()
                detail
            }
        } else {
            HStack(spacing: 0) {
                Group {
                    if state.sidebarCollapsed {
                        CollapsedSidebar()
                    } else {
                        Sidebar()
                    }
                }
                .frame(width: state.sidebarCollapsed ? 56 : CGFloat(sidebarWidth))
                .background(.regularMaterial)

                if state.sidebarCollapsed {
                    Divider()
                } else {
                    SidebarResizeHandle(width: $sidebarWidth)
                }

                detail
            }
            .animation(.easeInOut(duration: 0.2), value: state.sidebarCollapsed)
        }
    }

    var body: some View {
        layout
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) { _ in
            addressFocused = true
        }
        .sheet(item: $state.panel) { panel in
            switch panel {
            case .history: HistoryPanel()
            case .downloads: DownloadsPanel()
            }
        }
    }
}

// MARK: - Toolbar

struct Toolbar: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var bookmarks: BookmarkStore
    @EnvironmentObject var downloads: DownloadStore
    @ObservedObject var tab: Tab
    var addressFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Button { tab.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!tab.canGoBack)
            Button { tab.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!tab.canGoForward)
            Button {
                tab.isLoading ? tab.stop() : tab.reload()
            } label: {
                Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
            }

            if state.isPrivate {
                Label("Private", systemImage: "eye.slash")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.purple.opacity(0.25)))
            }

            TextField("Search or enter address", text: $state.addressText)
                .textFieldStyle(.roundedBorder)
                .focused(addressFocused)
                .onSubmit {
                    state.submitAddress()
                    addressFocused.wrappedValue = false
                }

            Button {
                bookmarks.toggle(title: tab.title, url: tab.url)
            } label: {
                Image(systemName: bookmarks.contains(tab.url) ? "star.fill" : "star")
                    .foregroundStyle(bookmarks.contains(tab.url) ? Color.yellow : Color.primary)
            }
            .help("Bookmark this page (⌘D)")
            .disabled(tab.url == nil)

            if !downloads.items.isEmpty {
                Button { state.panel = .downloads } label: { Image(systemName: "arrow.down.circle") }
                    .help("Downloads (⇧⌘J)")
            }
        }
        .buttonStyle(.borderless)
        .padding(8)
        // Keep the address bar in sync with the page unless the user is typing.
        .onChange(of: tab.url) { newURL in
            if !addressFocused.wrappedValue { state.addressText = newURL?.absoluteString ?? "" }
        }
    }
}

struct ProgressBar: View {
    @ObservedObject var tab: Tab
    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geo.size.width * tab.progress)
                .opacity(tab.isLoading ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: tab.progress)
        }
        .frame(height: 2)
    }
}

// MARK: - Address bar suggestions

struct SuggestionsList: View {
    let suggestions: [Suggestion]
    let onPick: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button { onPick(suggestion.url) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: suggestion.isBookmark ? "star.fill" : "clock")
                            .foregroundStyle(suggestion.isBookmark ? Color.yellow : Color.secondary)
                            .frame(width: 16)
                        Text(suggestion.title).lineLimit(1)
                        Text(suggestion.url.absoluteString)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if suggestion.id != suggestions.last?.id { Divider() }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
        .shadow(radius: 8, y: 4)
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }
}

// MARK: - Find in page

struct FindBar: View {
    @EnvironmentObject var state: BrowserState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in page", text: $state.findText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .focused($focused)
                .onSubmit { state.findNext() }
                .onChange(of: state.findText) { _ in state.findNext() }
            if state.findNotFound && !state.findText.isEmpty {
                Text("Not found").font(.caption).foregroundStyle(.red)
            }
            Button { state.findNext(backwards: true) } label: { Image(systemName: "chevron.up") }
                .help("Previous match (⇧⌘G)")
            Button { state.findNext() } label: { Image(systemName: "chevron.down") }
                .help("Next match (⌘G)")
            Spacer()
            Button("Done") { state.closeFind() }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .focusFindField)) { _ in focused = true }
        .onExitCommand { state.closeFind() }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var bookmarks: BookmarkStore
    @EnvironmentObject var spaceStore: SpaceStore

    var body: some View {
        VStack(spacing: 0) {
            SpaceHeader()

            Divider()

            Button { state.newTabAndFocus() } label: {
                Label("New Tab", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    if !state.pinnedTabs.isEmpty {
                        SectionHeader(title: "Pinned")
                        ForEach(state.pinnedTabs) { tab in
                            TabRow(tab: tab, isSelected: tab.id == state.selectedID)
                        }
                    }

                    if !bookmarks.items.isEmpty {
                        SectionHeader(title: "Bookmarks").padding(.top, 8)
                        ForEach(bookmarks.unfiled) { bookmark in
                            BookmarkRow(bookmark: bookmark)
                        }
                        ForEach(bookmarks.folders, id: \.self) { folder in
                            FolderGroup(name: folder)
                        }
                    }

                    SectionHeader(title: "Tabs").padding(.top, 8)
                    ForEach(state.regularTabs) { tab in
                        TabRow(tab: tab, isSelected: tab.id == state.selectedID)
                    }
                }
                .padding(6)
            }

            Divider()

            SpaceSwitcher()
                .padding(.horizontal, 8)
                .padding(.top, 8)

            HStack(spacing: 14) {
                Button { state.panel = .history } label: { Image(systemName: "clock") }
                    .help("History (⌘Y)")
                Button { state.panel = .downloads } label: { Image(systemName: "arrow.down.circle") }
                    .help("Downloads (⇧⌘J)")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        // A faint wash of the current space's color.
        .background(state.currentSpace.color.color.opacity(0.07))
    }
}

// MARK: - Spaces

struct SpaceHeader: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var spaceStore: SpaceStore

    var body: some View {
        let space = state.currentSpace
        HStack(spacing: 8) {
            Image(systemName: space.symbol).foregroundStyle(space.color.color)
            Text(space.name).font(.headline).lineLimit(1)
            Spacer(minLength: 0)
            Button { state.toggleSidebar() } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(.borderless)
                .help("Shrink sidebar to icons (⌘\\)")
        }
        .padding(10)
        .contentShape(Rectangle())
        .contextMenu { SpaceMenuContent(space: space) }
    }
}

struct SpaceSwitcher: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var spaceStore: SpaceStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(spaceStore.spaces) { space in
                    let isCurrent = space.id == state.currentSpaceID
                    Button { state.switchSpace(space.id) } label: {
                        Image(systemName: space.symbol)
                            .font(.system(size: 12))
                            .frame(width: 26, height: 26)
                            .foregroundStyle(isCurrent ? Color.white : space.color.color)
                            .background(
                                Circle().fill(isCurrent ? space.color.color : space.color.color.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(space.name)
                    .contextMenu { SpaceMenuContent(space: space) }
                }
                Button {
                    if let name = promptForText(title: "New Space",
                                                message: "For example: Work, School, a project name.",
                                                confirm: "Create") {
                        state.createSpace(name: name)
                    }
                } label: {
                    Image(systemName: "plus").frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help("New Space")
            }
        }
    }
}

/// Rename / color / icon / delete, shared by the header and the switcher buttons.
struct SpaceMenuContent: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var spaceStore: SpaceStore
    let space: Space

    var body: some View {
        Button("Rename Space…") {
            if let name = promptForText(title: "Rename Space", defaultValue: space.name, confirm: "Rename") {
                spaceStore.rename(space.id, to: name)
            }
        }
        Menu("Color") {
            ForEach(SpaceColor.allCases) { color in
                Button(color.name) { spaceStore.setStyle(space.id, color: color) }
            }
        }
        Menu("Icon") {
            ForEach(SpaceSymbol.all) { item in
                Button { spaceStore.setStyle(space.id, symbol: item.symbol) } label: {
                    Label(item.name, systemImage: item.symbol)
                }
            }
        }
        Divider()
        Button("Delete Space…", role: .destructive) {
            if confirmAction("Delete “\(space.name)”?",
                             message: "Its tabs will be closed. Bookmarks and history are kept.",
                             button: "Delete") {
                state.deleteSpace(space.id)
            }
        }
        .disabled(spaceStore.spaces.count < 2)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

struct FolderGroup: View {
    @EnvironmentObject var bookmarks: BookmarkStore
    let name: String
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(bookmarks.items(in: name)) { bookmark in
                BookmarkRow(bookmark: bookmark)
            }
        } label: {
            Label(name, systemImage: "folder").lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .contextMenu {
            Button("Rename Folder…") {
                if let new = promptForText(title: "Rename Folder", defaultValue: name, confirm: "Rename") {
                    bookmarks.renameFolder(name, to: new)
                }
            }
            Button("Delete Folder (Keep Bookmarks)", role: .destructive) {
                bookmarks.deleteFolder(name)
            }
        }
    }
}

struct BookmarkRow: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var bookmarks: BookmarkStore
    let bookmark: Bookmark
    @ObservedObject private var icons = FaviconStore.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            if let icon = icons.image(for: bookmark.url.host) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .frame(width: 14, height: 14)
            }
            Text(bookmark.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            if hovering {
                Button { bookmarks.remove(bookmark) } label: { Image(systemName: "xmark").font(.caption) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.primary.opacity(0.08) : .clear)
        )
        .contentShape(Rectangle())
        // Click loads in the current tab; Cmd+click opens a new one.
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) || state.selected == nil {
                state.newTab(url: bookmark.url)
            } else {
                state.selected?.load(bookmark.url)
            }
            state.sidebarItemClicked()
        }
        .onHover { hovering = $0 }
        .onAppear { icons.ensure(host: bookmark.url.host) }
        .contextMenu {
            Button("Open in New Tab") { state.newTab(url: bookmark.url) }
            Menu("Move to Folder") {
                if bookmark.folder != nil {
                    Button("No Folder") { bookmarks.move(bookmark, toFolder: nil) }
                }
                ForEach(bookmarks.folders.filter { $0 != bookmark.folder }, id: \.self) { folder in
                    Button(folder) { bookmarks.move(bookmark, toFolder: folder) }
                }
                Divider()
                Button("New Folder…") {
                    if let name = promptForText(title: "New Folder", confirm: "Create") {
                        bookmarks.move(bookmark, toFolder: name)
                    }
                }
            }
            Button("Remove Bookmark", role: .destructive) { bookmarks.remove(bookmark) }
        }
        .help(bookmark.url.absoluteString)
    }
}

struct TabRow: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var bookmarks: BookmarkStore
    @EnvironmentObject var spaceStore: SpaceStore
    @ObservedObject var tab: Tab
    @ObservedObject private var icons = FaviconStore.shared
    let isSelected: Bool
    @State private var hovering = false
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            if tab.isLoading {
                ProgressView().controlSize(.small).frame(width: 14, height: 14)
            } else if let icon = icons.image(for: tab.url?.host) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: tab.isPinned ? "pin.fill" : "globe")
                    .font(.caption)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.secondary)
            }
            Text(tab.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            if (hovering || isSelected) && !tab.isPinned {
                Button { state.close(tab) } label: { Image(systemName: "xmark").font(.caption) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? state.currentSpace.color.color.opacity(0.28)
                      : hovering ? Color.primary.opacity(0.08) : .clear)
        )
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if dropTargeted { Rectangle().fill(state.currentSpace.color.color).frame(height: 2) }
        }
        .onTapGesture {
            state.select(tab)
            state.sidebarItemClicked()
        }
        .onHover { hovering = $0 }
        .draggable(tab.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            state.moveTab(id, onto: tab)
            return true
        } isTargeted: { dropTargeted = $0 }
        .contextMenu {
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { state.togglePin(tab) }
            Button("Bookmark This Page") { bookmarks.toggle(title: tab.title, url: tab.url) }
                .disabled(tab.url == nil)
            if spaceStore.spaces.count > 1 {
                Menu("Move to Space") {
                    ForEach(spaceStore.spaces.filter { $0.id != tab.spaceID }) { space in
                        Button { state.move(tab, toSpace: space.id) } label: {
                            Label(space.name, systemImage: space.symbol)
                        }
                    }
                }
            }
            Divider()
            Button("Close Tab") { state.close(tab) }
        }
    }
}

// MARK: - Sidebar resize handle

/// Thin draggable divider between an expanded sidebar and the page.
struct SidebarResizeHandle: View {
    @Binding var width: Double
    @State private var startWidth: Double?

    var body: some View {
        Divider()
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if startWidth == nil { startWidth = width }
                        width = min(max((startWidth ?? width) + value.translation.width, 180), 360)
                    }
                    .onEnded { _ in startWidth = nil }
            )
    }
}

// MARK: - Collapsed (icon-only) sidebar

struct CollapsedSidebar: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var bookmarks: BookmarkStore
    @EnvironmentObject var spaceStore: SpaceStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                RailButton(symbol: "sidebar.left", help: "Expand sidebar (⌘\\)") { state.toggleSidebar() }
                RailButton(symbol: "plus", help: "New Tab (⌘T)") { state.newTabAndFocus() }
            }
            .padding(.vertical, 10)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(state.pinnedTabs) { tab in
                        RailTabIcon(tab: tab, isSelected: tab.id == state.selectedID)
                    }
                    if !state.pinnedTabs.isEmpty {
                        Divider().padding(.horizontal, 12)
                    }
                    ForEach(bookmarks.items) { bookmark in
                        RailBookmarkIcon(bookmark: bookmark)
                    }
                    if !bookmarks.items.isEmpty {
                        Divider().padding(.horizontal, 12)
                    }
                    ForEach(state.regularTabs) { tab in
                        RailTabIcon(tab: tab, isSelected: tab.id == state.selectedID)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }

            Divider()

            VStack(spacing: 8) {
                ForEach(spaceStore.spaces) { space in
                    let isCurrent = space.id == state.currentSpaceID
                    Button { state.switchSpace(space.id) } label: {
                        Image(systemName: space.symbol)
                            .font(.system(size: 12))
                            .frame(width: 26, height: 26)
                            .foregroundStyle(isCurrent ? Color.white : space.color.color)
                            .background(
                                Circle().fill(isCurrent ? space.color.color : space.color.color.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(space.name)
                    .contextMenu { SpaceMenuContent(space: space) }
                }
                RailButton(symbol: "clock", help: "History (⌘Y)") { state.panel = .history }
                RailButton(symbol: "arrow.down.circle", help: "Downloads (⇧⌘J)") { state.panel = .downloads }
            }
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
        .background(state.currentSpace.color.color.opacity(0.07))
    }
}

struct RailButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 32, height: 28)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// Rounded square with the site's icon, or its first letter until the icon is known.
struct IconBadge: View {
    var icon: NSImage? = nil
    let title: String
    let colorKey: String
    let isSelected: Bool
    let selectionColor: Color

    private var letter: String {
        guard let first = title.trimmingCharacters(in: .whitespaces).first, title != "New Tab" else { return "" }
        return String(first).uppercased()
    }

    /// Same site -> same color, every launch (String.hashValue changes between launches).
    private var tint: Color {
        let colors = SpaceColor.allCases
        let sum = colorKey.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return colors[sum % colors.count].color
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(icon != nil ? Color(nsColor: .controlBackgroundColor) : tint.opacity(isSelected ? 0.4 : 0.2))
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if letter.isEmpty {
                Image(systemName: "globe").font(.system(size: 14)).foregroundStyle(.secondary)
            } else {
                Text(letter).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            }
        }
        .frame(width: 34, height: 34)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? selectionColor : Color.clear, lineWidth: 2)
        )
    }
}

struct RailTabIcon: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var bookmarks: BookmarkStore
    @ObservedObject var tab: Tab
    @ObservedObject private var icons = FaviconStore.shared
    let isSelected: Bool
    @State private var dropTargeted = false

    var body: some View {
        Button {
            state.select(tab)
            state.sidebarItemClicked()
        } label: {
            IconBadge(icon: icons.image(for: tab.url?.host),
                      title: tab.title,
                      colorKey: tab.url?.host ?? tab.title,
                      isSelected: isSelected,
                      selectionColor: state.currentSpace.color.color)
                .overlay(alignment: .topTrailing) {
                    if tab.isLoading {
                        ProgressView().controlSize(.mini).offset(x: 4, y: -4)
                    } else if tab.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 7))
                            .padding(3)
                            .background(Circle().fill(.regularMaterial))
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .overlay(alignment: .top) {
            if dropTargeted { Rectangle().fill(state.currentSpace.color.color).frame(width: 30, height: 2).offset(y: -4) }
        }
        .draggable(tab.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            state.moveTab(id, onto: tab)
            return true
        } isTargeted: { dropTargeted = $0 }
        .contextMenu {
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { state.togglePin(tab) }
            Button("Bookmark This Page") { bookmarks.toggle(title: tab.title, url: tab.url) }
                .disabled(tab.url == nil)
            Divider()
            Button("Close Tab") { state.close(tab) }
        }
    }
}

struct RailBookmarkIcon: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var bookmarks: BookmarkStore
    let bookmark: Bookmark
    @ObservedObject private var icons = FaviconStore.shared

    var body: some View {
        Button {
            if NSEvent.modifierFlags.contains(.command) || state.selected == nil {
                state.newTab(url: bookmark.url)
            } else {
                state.selected?.load(bookmark.url)
            }
            state.sidebarItemClicked()
        } label: {
            IconBadge(icon: icons.image(for: bookmark.url.host),
                      title: bookmark.title,
                      colorKey: bookmark.url.host ?? bookmark.title,
                      isSelected: false,
                      selectionColor: .clear)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.yellow)
                        .padding(3)
                        .background(Circle().fill(.regularMaterial))
                        .offset(x: 4, y: -4)
                }
        }
        .buttonStyle(.plain)
        .help(bookmark.title)
        .onAppear { icons.ensure(host: bookmark.url.host) }
        .contextMenu {
            Button("Open in New Tab") { state.newTab(url: bookmark.url) }
            Button("Remove Bookmark", role: .destructive) { bookmarks.remove(bookmark) }
        }
    }
}


// MARK: - Top layout (tab strip + bookmarks bar)

struct TopTabBar: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var spaceStore: SpaceStore
    @AppStorage("tabLayout") private var tabLayout = "sidebar"

    var body: some View {
        HStack(spacing: 6) {
            RailButton(symbol: "sidebar.left", help: "Show tabs in sidebar (⌥⌘\\)") { tabLayout = "sidebar" }

            // Same space icons as the sidebar's icon rail.
            ForEach(spaceStore.spaces) { space in
                let isCurrent = space.id == state.currentSpaceID
                Button { state.switchSpace(space.id) } label: {
                    Image(systemName: space.symbol)
                        .font(.system(size: 12))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(isCurrent ? Color.white : space.color.color)
                        .background(
                            Circle().fill(isCurrent ? space.color.color : space.color.color.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .help(space.name)
                .contextMenu { SpaceMenuContent(space: space) }
            }

            Divider().frame(height: 16)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(state.pinnedTabs) { tab in
                            TopTabItem(tab: tab, isSelected: tab.id == state.selectedID)
                        }
                        if !state.pinnedTabs.isEmpty {
                            Divider().frame(height: 16)
                        }
                        ForEach(state.regularTabs) { tab in
                            TopTabItem(tab: tab, isSelected: tab.id == state.selectedID)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: state.selectedID) { id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id) }
                }
            }

            RailButton(symbol: "plus", help: "New Tab (⌘T)") { state.newTabAndFocus() }
            RailButton(symbol: "clock", help: "History (⌘Y)") { state.panel = .history }
            RailButton(symbol: "arrow.down.circle", help: "Downloads (⇧⌘J)") { state.panel = .downloads }
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(.regularMaterial)
    }
}

struct TopTabItem: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var bookmarks: BookmarkStore
    @EnvironmentObject var spaceStore: SpaceStore
    @ObservedObject var tab: Tab
    @ObservedObject private var icons = FaviconStore.shared
    let isSelected: Bool
    @State private var hovering = false
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 6) {
            if tab.isLoading {
                ProgressView().controlSize(.small).frame(width: 14, height: 14)
            } else if let icon = icons.image(for: tab.url?.host) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: tab.isPinned ? "pin.fill" : "globe")
                    .font(.caption)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.secondary)
            }
            if !tab.isPinned {
                Text(tab.title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if hovering || isSelected {
                    Button { state.close(tab) } label: { Image(systemName: "xmark").font(.caption) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(width: tab.isPinned ? 36 : 170, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? state.currentSpace.color.color.opacity(0.28)
                      : hovering ? Color.primary.opacity(0.08) : .clear)
        )
        .overlay(alignment: .leading) {
            if dropTargeted { Rectangle().fill(state.currentSpace.color.color).frame(width: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture { state.select(tab) }
        .onHover { hovering = $0 }
        .draggable(tab.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            state.moveTab(id, onto: tab)
            return true
        } isTargeted: { dropTargeted = $0 }
        .help(tab.title)
        .contextMenu {
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { state.togglePin(tab) }
            Button("Bookmark This Page") { bookmarks.toggle(title: tab.title, url: tab.url) }
                .disabled(tab.url == nil)
            if spaceStore.spaces.count > 1 {
                Menu("Move to Space") {
                    ForEach(spaceStore.spaces.filter { $0.id != tab.spaceID }) { space in
                        Button { state.move(tab, toSpace: space.id) } label: {
                            Label(space.name, systemImage: space.symbol)
                        }
                    }
                }
            }
            Divider()
            Button("Close Tab") { state.close(tab) }
        }
    }
}

/// Bookmarks as a row under the address bar (top layout). Folders open as menus.
struct BookmarksBar: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var bookmarks: BookmarkStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(bookmarks.unfiled) { bookmark in
                    BookmarkChip(bookmark: bookmark)
                }
                ForEach(bookmarks.folders, id: \.self) { folder in
                    Menu {
                        ForEach(bookmarks.items(in: folder)) { bookmark in
                            Button(bookmark.title) { state.newTab(url: bookmark.url) }
                        }
                    } label: {
                        Label(folder, systemImage: "folder")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 28)
        .background(.bar)
    }
}

struct BookmarkChip: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var bookmarks: BookmarkStore
    @ObservedObject private var icons = FaviconStore.shared
    let bookmark: Bookmark
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon = icons.image(for: bookmark.url.host) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
            }
            Text(bookmark.title).font(.callout).lineLimit(1).frame(maxWidth: 140)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.primary.opacity(0.1) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            // Click loads in the current tab; Cmd+click opens a new one.
            if NSEvent.modifierFlags.contains(.command) || state.selected == nil {
                state.newTab(url: bookmark.url)
            } else {
                state.selected?.load(bookmark.url)
            }
        }
        .onHover { hovering = $0 }
        .onAppear { icons.ensure(host: bookmark.url.host) }
        .help(bookmark.url.absoluteString)
        .contextMenu {
            Button("Open in New Tab") { state.newTab(url: bookmark.url) }
            Button("Remove Bookmark", role: .destructive) { bookmarks.remove(bookmark) }
        }
    }
}
