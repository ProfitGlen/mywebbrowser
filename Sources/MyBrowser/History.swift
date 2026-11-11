import SwiftUI

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var url: URL
    var date: Date
}

/// Browsing history (newest first), saved to ~/Library/Application Support/MyBrowser/history.json.
/// Private windows never write to this.
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let maxEntries = 5000
    private var pendingSave: DispatchWorkItem?

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MyBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() { load() }

    func add(title: String, url: URL) {
        guard let scheme = url.scheme, ["http", "https"].contains(scheme) else { return }
        let name = title.isEmpty ? (url.host ?? url.absoluteString) : title
        // Reloads / redirects to the same page just refresh the newest entry.
        if let first = entries.first, first.url == url {
            entries[0].title = name
            entries[0].date = Date()
        } else {
            entries.insert(HistoryEntry(title: name, url: url, date: Date()), at: 0)
            if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        }
        scheduleSave()
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        scheduleSave()
    }

    func clear() {
        entries.removeAll()
        SearchHistoryStore.shared.clear()
        scheduleSave()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Address bar suggestions

struct Suggestion: Identifiable {
    let url: URL
    let title: String
    let isBookmark: Bool
    var isSearch = false
    var id: String { (isSearch ? "search:" : "") + url.absoluteString }
}

enum Suggestions {
    /// Bookmarks first, then history, de-duplicated by URL.
    static func matching(_ query: String, bookmarks: [Bookmark], history: [HistoryEntry],
                         searches: [String] = [], limit: Int = 8) -> [Suggestion] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }

        var seen = Set<String>()
        var result: [Suggestion] = []

        for b in bookmarks where result.count < limit {
            let key = b.url.absoluteString
            if !seen.contains(key), b.title.lowercased().contains(q) || key.lowercased().contains(q) {
                seen.insert(key)
                result.append(Suggestion(url: b.url, title: b.title, isBookmark: true))
            }
        }
        // Searches you've typed before.
        for text in searches where result.count < limit {
            result.append(Suggestion(url: AppSettings.searchURL(for: text), title: text,
                                     isBookmark: false, isSearch: true))
        }
        for h in history where result.count < limit {
            let key = h.url.absoluteString
            if !seen.contains(key), h.title.lowercased().contains(q) || key.lowercased().contains(q) {
                seen.insert(key)
                result.append(Suggestion(url: h.url, title: h.title, isBookmark: false))
            }
        }
        return result
    }
}

// MARK: - History panel

struct HistoryGroup: Identifiable {
    let day: Date
    let items: [HistoryEntry]
    var id: Date { day }
}

struct HistoryPanel: View {
    @EnvironmentObject var state: BrowserState
    @EnvironmentObject var history: HistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = q.isEmpty ? history.entries : history.entries.filter {
            $0.title.lowercased().contains(q) || $0.url.absoluteString.lowercased().contains(q)
        }
        return Array(list.prefix(500))
    }

    private var groups: [HistoryGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { HistoryGroup(day: $0, items: grouped[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History").font(.title2.bold())
                Spacer()
                Button("Clear All…") {
                    if confirmAction("Clear all browsing history?") { history.clear() }
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()

            TextField("Search history", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if filtered.isEmpty {
                Text(query.isEmpty ? "No history yet" : "No matches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { group in
                        Section(group.day.formatted(date: .complete, time: .omitted)) {
                            ForEach(group.items) { entry in
                                HistoryRow(entry: entry) {
                                    state.openURL(entry.url)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 580, height: 540)
    }
}

struct HistoryRow: View {
    @EnvironmentObject var history: HistoryStore
    let entry: HistoryEntry
    let open: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).lineLimit(1)
                Text(entry.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .contextMenu {
            Button("Open") { open() }
            Button("Delete", role: .destructive) { history.remove(entry) }
        }
    }
}
