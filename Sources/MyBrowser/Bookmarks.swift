import SwiftUI

struct Bookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var url: URL
    /// nil = not in a folder. Folders exist as long as a bookmark is in them.
    var folder: String? = nil
}

/// Stores bookmarks as JSON in ~/Library/Application Support/MyBrowser/bookmarks.json
final class BookmarkStore: ObservableObject {
    @Published private(set) var items: [Bookmark] = []

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MyBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bookmarks.json")
    }()

    init() { load() }

    // MARK: Queries

    var unfiled: [Bookmark] { items.filter { $0.folder == nil } }

    var folders: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in items.compactMap({ $0.folder }) where !seen.contains(name) {
            seen.insert(name)
            result.append(name)
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func items(in folder: String) -> [Bookmark] {
        items.filter { $0.folder == folder }
    }

    func contains(_ url: URL?) -> Bool {
        guard let url else { return false }
        return items.contains { $0.url == url }
    }

    // MARK: Changes

    func toggle(title: String, url: URL?) {
        guard let url else { return }
        if let index = items.firstIndex(where: { $0.url == url }) {
            items.remove(at: index)
        } else {
            let name = title.isEmpty || title == "New Tab" ? (url.host ?? url.absoluteString) : title
            items.append(Bookmark(title: name, url: url))
        }
        save()
    }

    func remove(_ bookmark: Bookmark) {
        items.removeAll { $0.id == bookmark.id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func move(_ bookmark: Bookmark, toFolder folder: String?) {
        guard let index = items.firstIndex(where: { $0.id == bookmark.id }) else { return }
        items[index].folder = folder
        save()
    }

    func renameFolder(_ old: String, to new: String) {
        for index in items.indices where items[index].folder == old {
            items[index].folder = new
        }
        save()
    }

    /// Removes the folder but keeps its bookmarks (they become unfiled).
    func deleteFolder(_ name: String) {
        for index in items.indices where items[index].folder == name {
            items[index].folder = nil
        }
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
