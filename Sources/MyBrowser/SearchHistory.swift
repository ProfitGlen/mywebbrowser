import Foundation

/// The searches you've typed in the address bar, remembered so they come back as suggestions.
/// Saved to ~/Library/Application Support/MyBrowser/searches.json. Never recorded in private windows.
final class SearchHistoryStore: ObservableObject {
    static let shared = SearchHistoryStore()

    @Published private(set) var searches: [String] = []   // newest first

    private let limit = 300
    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MyBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("searches.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            searches = decoded
        }
    }

    func add(_ query: String) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searches.removeAll { $0.caseInsensitiveCompare(text) == .orderedSame }
        searches.insert(text, at: 0)
        if searches.count > limit { searches.removeLast(searches.count - limit) }
        save()
    }

    /// Searches that start with what you typed first, then ones that contain it.
    func matching(_ query: String, limit: Int = 4) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let starts = searches.filter { $0.lowercased().hasPrefix(q) && $0.lowercased() != q }
        let contains = searches.filter { $0.lowercased().contains(q) && !$0.lowercased().hasPrefix(q) }
        return Array((starts + contains).prefix(limit))
    }

    func clear() {
        searches.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(searches) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
