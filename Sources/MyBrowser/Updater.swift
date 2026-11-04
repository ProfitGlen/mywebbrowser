import SwiftUI

/// Checks GitHub Releases for a newer build, downloads it, swaps the installed app and relaunches.
/// Only works in the installed MyBrowser.app (not `swift run`) and needs a public repo
/// named in the UPDATE_REPO file (baked into Info.plist by build_app.sh).
final class Updater: ObservableObject {
    @Published var isChecking = false

    static let currentVersion: String =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"

    private static var repo: String {
        ((Bundle.main.infoDictionary?["MBUpdateRepo"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let lastCheckKey = "lastUpdateCheck"
    private var didAutoCheck = false

    private var isConfigured: Bool {
        let repo = Updater.repo
        return Bundle.main.bundlePath.hasSuffix(".app")
            && repo.contains("/") && !repo.hasPrefix("OWNER/")
    }

    // MARK: Checking

    /// Runs once per launch, at most every 6 hours, unless switched off in Settings.
    func autoCheckIfDue() {
        guard !didAutoCheck else { return }
        didAutoCheck = true
        let enabled = UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true
        guard enabled, isConfigured else { return }
        let last = UserDefaults.standard.double(forKey: Updater.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 6 * 3600 else { return }
        checkForUpdates(userInitiated: false)
    }

    func checkForUpdates(userInitiated: Bool) {
        guard !isChecking else { return }
        guard isConfigured else {
            if userInitiated {
                showAlert("Updates aren't set up",
                          "Updates work in the installed app once UPDATE_REPO names your GitHub repo. See the README.")
            }
            return
        }
        guard let url = URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/latest") else { return }

        isChecking = true
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Updater.lastCheckKey)

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MyBrowser-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isChecking = false
                self.handleCheck(data: data, response: response, error: error, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func handleCheck(data: Data?, response: URLResponse?, error: Error?, userInitiated: Bool) {
        if let error {
            if userInitiated { showAlert("Couldn't check for updates", error.localizedDescription) }
            return
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            if userInitiated {
                showAlert("Couldn't check for updates",
                          status == 404
                          ? "No release found. Is the repo public, and has a release been published?"
                          : "GitHub returned an unexpected response (\(status)).")
            }
            return
        }

        let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Updater.isNewer(remote, than: Updater.currentVersion) else {
            if userInitiated {
                showAlert("You're up to date", "MyBrowser \(Updater.currentVersion) is the latest version.")
            }
            return
        }

        let assets = json["assets"] as? [[String: Any]] ?? []
        let zipURL = assets
            .first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
            .flatMap { $0["browser_download_url"] as? String }
            .flatMap { URL(string: $0) }
        guard let zipURL else {
            if userInitiated { showAlert("Update found but no download", "Release \(tag) has no .zip file attached.") }
            return
        }

        var notes = (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.count > 500 { notes = String(notes.prefix(500)) + "…" }

        let alert = NSAlert()
        alert.messageText = "MyBrowser \(remote) is available"
        alert.informativeText = "You have \(Updater.currentVersion)." + (notes.isEmpty ? "" : "\n\n\(notes)")
        alert.addButton(withTitle: "Update and Restart")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            install(from: zipURL)
        }
    }

    /// Versions compare part by part as numbers, so 1.10 > 1.09 and 1.31 < 1.32.
    static func isNewer(_ remote: String, than current: String) -> Bool {
        let r = remote.split(separator: ".").map { Int($0) ?? 0 }
        let c = current.split(separator: ".").map { Int($0) ?? 0 }
        guard !c.isEmpty, current != "dev" else { return false }
        for i in 0..<max(r.count, c.count) {
            let a = i < r.count ? r[i] : 0
            let b = i < c.count ? c[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    // MARK: Installing

    private func install(from zipURL: URL) {
        URLSession.shared.downloadTask(with: zipURL) { tmp, _, error in
            guard let tmp, error == nil else {
                DispatchQueue.main.async {
                    self.showAlert("Download failed", error?.localizedDescription ?? "Unknown error.")
                }
                return
            }
            do {
                let fm = FileManager.default
                let work = fm.temporaryDirectory.appendingPathComponent("MyBrowserUpdate-\(UUID().uuidString)")
                try fm.createDirectory(at: work, withIntermediateDirectories: true)
                let zip = work.appendingPathComponent("update.zip")
                try fm.moveItem(at: tmp, to: zip)

                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-xk", zip.path, work.path]
                try unzip.run()
                unzip.waitUntilExit()
                guard unzip.terminationStatus == 0 else { throw UpdateError.unzipFailed }

                let contents = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                    throw UpdateError.noAppInZip
                }
                DispatchQueue.main.async { self.swapAndRelaunch(newApp: newApp, work: work) }
            } catch {
                DispatchQueue.main.async {
                    self.showAlert("Update failed", error.localizedDescription)
                }
            }
        }.resume()
    }

    private enum UpdateError: LocalizedError {
        case unzipFailed, noAppInZip
        var errorDescription: String? {
            switch self {
            case .unzipFailed: return "Couldn't unzip the download."
            case .noAppInZip: return "The download didn't contain an app."
            }
        }
    }

    /// A small detached script waits for this app to quit, replaces it, and reopens it.
    private func swapAndRelaunch(newApp: URL, work: URL) {
        let current = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptURL = work.appendingPathComponent("install.sh")
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(current.path)"
        /usr/bin/ditto "\(newApp.path)" "\(current.path)"
        /usr/bin/xattr -cr "\(current.path)"
        open "\(current.path)"
        rm -rf "\(work.path)"
        """
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
            launcher.arguments = ["-c", "nohup /bin/bash '\(scriptURL.path)' >/dev/null 2>&1 &"]
            try launcher.run()
            NSApp.terminate(nil)
        } catch {
            showAlert("Update failed", error.localizedDescription)
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
