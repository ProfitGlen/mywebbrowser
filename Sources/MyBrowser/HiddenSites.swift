import Foundation

/// Sites that are never saved to history. A site like "example.com" also covers its subdomains
/// (mail.example.com) and every page on it.
final class HiddenSitesStore: ObservableObject {
    static let shared = HiddenSitesStore()
    private static let key = "hiddenHistorySites"

    @Published private(set) var sites: [String]

    private init() {
        sites = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    /// "https://www.Example.com/page?x=1" -> "example.com"
    static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        if let end = text.firstIndex(where: { "/?#".contains($0) }) { text = String(text[..<end]) }
        if let at = text.lastIndex(of: "@") { text = String(text[text.index(after: at)...]) }
        if let colon = text.firstIndex(of: ":") { text = String(text[..<colon]) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        guard !text.isEmpty, text.contains(".") || text == "localhost",
              text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return text
    }

    /// Returns the saved site name, or nil if the text isn't a valid site.
    @discardableResult
    func add(_ input: String) -> String? {
        guard let site = Self.normalize(input) else { return nil }
        if !sites.contains(site) {
            sites.append(site)
            sites.sort()
            UserDefaults.standard.set(sites, forKey: Self.key)
        }
        return site
    }

    func remove(_ site: String) {
        sites.removeAll { $0 == site }
        UserDefaults.standard.set(sites, forKey: Self.key)
    }

    func matches(_ host: String?) -> Bool {
        guard var host = host?.lowercased() else { return false }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return sites.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
