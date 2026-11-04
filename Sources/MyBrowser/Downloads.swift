import SwiftUI
import WebKit

final class DownloadItem: NSObject, ObservableObject, Identifiable {
    enum Status { case running, finished, failed, cancelled }

    let id = UUID()
    let download: WKDownload

    @Published var filename: String
    @Published var fraction = 0.0
    @Published var status = Status.running
    @Published var destination: URL?

    private var observation: NSKeyValueObservation?

    init(download: WKDownload, filename: String) {
        self.download = download
        self.filename = filename
        super.init()
        observation = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let value = progress.fractionCompleted
            DispatchQueue.main.async { self?.fraction = value }
        }
    }

    func cancel() {
        status = .cancelled
        download.cancel { _ in }
    }
}

/// Receives downloads from every tab and saves them to ~/Downloads.
final class DownloadStore: NSObject, ObservableObject, WKDownloadDelegate {
    @Published private(set) var items: [DownloadItem] = []

    func add(_ download: WKDownload) {
        let guess = download.originalRequest?.url?.lastPathComponent ?? ""
        let item = DownloadItem(download: download, filename: guess.isEmpty ? "Download" : guess)
        download.delegate = self
        items.insert(item, at: 0)
    }

    func clearFinished() {
        items.removeAll { $0.status != .running }
    }

    private func item(for download: WKDownload) -> DownloadItem? {
        items.first { $0.download === download }
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let destination = uniqueURL(in: directory, filename: sanitize(suggestedFilename))
        if let item = item(for: download) {
            item.filename = destination.lastPathComponent
            item.destination = destination
        }
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = item(for: download) else { return }
        item.fraction = 1
        item.status = .finished
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let item = item(for: download), item.status != .cancelled else { return }
        item.status = .failed
    }

    // MARK: Helpers

    private func sanitize(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "download" : cleaned
    }

    /// "report.pdf" -> "report (1).pdf" if it already exists.
    private func uniqueURL(in directory: URL, filename: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(filename)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var n = 1
        repeat {
            let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = directory.appendingPathComponent(name)
            n += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }
}

// MARK: - Downloads panel

struct DownloadsPanel: View {
    @EnvironmentObject var downloads: DownloadStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Downloads").font(.title2.bold())
                Spacer()
                Button("Clear Finished") { downloads.clearFinished() }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()

            if downloads.items.isEmpty {
                Text("No downloads yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(downloads.items) { DownloadRow(item: $0) }
            }
        }
        .frame(width: 540, height: 400)
    }
}

struct DownloadRow: View {
    @ObservedObject var item: DownloadItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename).lineLimit(1).truncationMode(.middle)
                switch item.status {
                case .running:
                    ProgressView(value: item.fraction)
                case .finished:
                    Text("Finished").font(.caption).foregroundStyle(.secondary)
                case .failed:
                    Text("Failed").font(.caption).foregroundStyle(.red)
                case .cancelled:
                    Text("Cancelled").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            switch item.status {
            case .running:
                Button { item.cancel() } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless)
                    .help("Cancel")
            case .finished:
                if let url = item.destination {
                    Button("Open") { NSWorkspace.shared.open(url) }
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                        Image(systemName: "magnifyingglass.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                }
            default:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
    }
}
