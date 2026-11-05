import SwiftUI

/// A private note attached to a web page.
struct PageNote: Codable, Identifiable {
    var id: String        // normalized page address
    var url: URL
    var title: String
    var text: String
    var updated: Date
}

/// Notes you write about pages. Saved only on this Mac, in
/// ~/Library/Application Support/MyBrowser/notes.json. Never sent anywhere and not used in private windows.
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    @Published private(set) var notes: [String: PageNote] = [:]

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MyBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.json")
    }()

    private init() { load() }

    /// The same page gives the same key (ignores the #fragment and a trailing slash).
    static func key(for url: URL?) -> String? {
        guard let url, url.scheme == "http" || url.scheme == "https",
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.fragment = nil
        guard var string = parts.string else { return nil }
        while string.hasSuffix("/") { string.removeLast() }
        return string
    }

    func note(for url: URL?) -> PageNote? {
        guard let key = Self.key(for: url) else { return nil }
        return notes[key]
    }

    func hasNote(for url: URL?) -> Bool { note(for: url) != nil }

    var all: [PageNote] { notes.values.sorted { $0.updated > $1.updated } }

    func set(text: String, url: URL, title: String) {
        guard let key = Self.key(for: url) else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard notes[key] != nil else { return }
            notes.removeValue(forKey: key)
        } else {
            if notes[key]?.text == text { return }
            notes[key] = PageNote(id: key, url: url, title: title, text: text, updated: Date())
        }
        save()
    }

    func remove(_ id: String) {
        notes.removeValue(forKey: id)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PageNote].self, from: data) else { return }
        notes = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(notes.values)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Toolbar button: opens a small notepad for the current page. Filled and orange when the page has a note.
struct NoteButton: View {
    @ObservedObject var tab: Tab
    @ObservedObject private var notes = NotesStore.shared
    @State private var showing = false

    var body: some View {
        let has = notes.hasNote(for: tab.url)
        Button { showing.toggle() } label: {
            Image(systemName: has ? "note.text" : "note.text.badge.plus")
                .foregroundStyle(has ? Color.orange : Color.primary)
        }
        .help("Notes for this page (private, saved on this Mac)")
        .disabled(NotesStore.key(for: tab.url) == nil)
        .popover(isPresented: $showing, arrowEdge: .bottom) { NoteEditor(tab: tab) }
    }
}

struct NoteEditor: View {
    @ObservedObject var tab: Tab
    @ObservedObject private var notes = NotesStore.shared
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tab.title).font(.headline).lineLimit(1)
            Text("Only you can see this. It's saved on this Mac and never shared.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .focused($focused)
                .frame(width: 320, height: 180)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.15)))
            HStack {
                Text("Saved automatically").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Delete Note", role: .destructive) { text = "" }
                    .disabled(text.isEmpty)
            }
        }
        .padding(12)
        .onAppear {
            text = notes.note(for: tab.url)?.text ?? ""
            focused = true
        }
        .onChange(of: text) { newText in
            if let url = tab.url { notes.set(text: newText, url: url, title: tab.title) }
        }
    }
}

/// All your notes, newest first.
struct NotesPanel: View {
    @EnvironmentObject var state: BrowserState
    @ObservedObject private var notes = NotesStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [PageNote] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return notes.all }
        return notes.all.filter {
            $0.title.lowercased().contains(q) || $0.text.lowercased().contains(q)
                || $0.url.absoluteString.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()

            TextField("Search notes", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if filtered.isEmpty {
                Text(query.isEmpty ? "No notes yet. Use the note button in the toolbar on any page."
                                   : "No matches")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(note.title.isEmpty ? (note.url.host ?? "Page") : note.title)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()
                            Text(note.updated.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(note.url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(note.text).lineLimit(4)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.newTab(url: note.url)
                        dismiss()
                    }
                    .contextMenu {
                        Button("Open Page") { state.newTab(url: note.url); dismiss() }
                        Button("Delete Note", role: .destructive) { notes.remove(note.id) }
                    }
                }
            }
        }
        .frame(width: 580, height: 540)
    }
}
