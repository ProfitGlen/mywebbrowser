import SwiftUI

enum SpaceColor: String, Codable, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, green, teal, gray

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        case .teal: return .teal
        case .gray: return .gray
        }
    }
}

struct SpaceSymbol: Identifiable {
    let name: String
    let symbol: String
    var id: String { symbol }

    static let all: [SpaceSymbol] = [
        SpaceSymbol(name: "Home", symbol: "house.fill"),
        SpaceSymbol(name: "Work", symbol: "briefcase.fill"),
        SpaceSymbol(name: "Build", symbol: "hammer.fill"),
        SpaceSymbol(name: "Reading", symbol: "book.fill"),
        SpaceSymbol(name: "School", symbol: "graduationcap.fill"),
        SpaceSymbol(name: "Shopping", symbol: "cart.fill"),
        SpaceSymbol(name: "Games", symbol: "gamecontroller.fill"),
        SpaceSymbol(name: "Music", symbol: "music.note"),
        SpaceSymbol(name: "Photos", symbol: "camera.fill"),
        SpaceSymbol(name: "Design", symbol: "paintbrush.fill"),
        SpaceSymbol(name: "Nature", symbol: "leaf.fill"),
        SpaceSymbol(name: "Favorites", symbol: "star.fill"),
    ]
}

/// A named group of tabs (and pinned tabs), e.g. one per project.
struct Space: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String
    var color: SpaceColor
}

/// The list of spaces, shared by every window and saved to
/// ~/Library/Application Support/MyBrowser/spaces.json. There is always at least one.
final class SpaceStore: ObservableObject {
    static let shared = SpaceStore()

    @Published private(set) var spaces: [Space] = []

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MyBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("spaces.json")
    }()

    private init() {
        load()
        if spaces.isEmpty {
            spaces = [Space(name: "Home", symbol: "house.fill", color: .blue)]
            save()
        }
    }

    func space(_ id: UUID) -> Space? {
        spaces.first { $0.id == id }
    }

    @discardableResult
    func add(name: String) -> Space {
        let colors = SpaceColor.allCases
        let symbols = SpaceSymbol.all
        let n = spaces.count
        let space = Space(name: name,
                          symbol: symbols[n % symbols.count].symbol,
                          color: colors[n % colors.count])
        spaces.append(space)
        save()
        return space
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].name = name
        save()
    }

    func setStyle(_ id: UUID, symbol: String? = nil, color: SpaceColor? = nil) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        if let symbol { spaces[index].symbol = symbol }
        if let color { spaces[index].color = color }
        save()
    }

    func delete(_ id: UUID) {
        guard spaces.count > 1 else { return }
        spaces.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Space].self, from: data) else { return }
        spaces = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(spaces) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
