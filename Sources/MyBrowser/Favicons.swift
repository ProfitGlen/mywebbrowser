import AppKit

/// Site icons. Fetched straight from the site being visited (nothing is sent to a third party),
/// cached in memory and saved to ~/Library/Application Support/MyBrowser/favicons.
final class FaviconStore: ObservableObject {
    static let shared = FaviconStore()

    @Published private(set) var images: [String: NSImage] = [:]
    private var lastIconURL: [String: URL] = [:]
    private var attempted = Set<String>()
    private let dir: URL
    private let session: URLSession

    init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyBrowser/favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        session = URLSession(configuration: config)

        // Load the saved icons so bookmarks and restored tabs show them immediately.
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "png" {
                if let image = NSImage(contentsOf: file) {
                    images[file.deletingPathExtension().lastPathComponent] = image
                }
            }
        }
    }

    func image(for host: String?) -> NSImage? {
        guard let host = host?.lowercased() else { return nil }
        return images[host]
    }

    /// For a bookmark whose site has no saved icon yet: try the site's /favicon.ico once.
    func ensure(host: String?) {
        guard let host = host?.lowercased(), !host.isEmpty,
              images[host] == nil, !attempted.contains(host),
              let url = URL(string: "https://\(host)/favicon.ico") else { return }
        attempted.insert(host)
        fetch(iconURL: url, host: host, persist: true)
    }

    func fetch(iconURL: URL, host: String, persist: Bool) {
        let host = host.lowercased()
        if lastIconURL[host] == iconURL, images[host] != nil { return }
        session.dataTask(with: iconURL) { [weak self] data, response, _ in
            guard let self, let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data), image.size.width >= 8 else { return }
            DispatchQueue.main.async {
                self.lastIconURL[host] = iconURL
                self.images[host] = image
                if persist, let png = Self.pngData(image) {
                    try? png.write(to: self.dir.appendingPathComponent(Self.fileName(host)))
                }
            }
        }.resume()
    }

    private static func fileName(_ host: String) -> String {
        let safe = host.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        return safe + ".png"
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
