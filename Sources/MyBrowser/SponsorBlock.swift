import WebKit
import CryptoKit

/// Skips sponsor segments on YouTube using the community SponsorBlock database (sponsor.ajay.app).
/// The page asks the app for a video's segments; the app looks them up (sending only the first 4
/// characters of a hash of the video ID, so the server can't tell exactly which video) and the
/// page script then jumps past each segment as it is reached.
/// SponsorBlock data is licensed CC BY-NC-SA 4.0 (non-commercial use, with attribution).
enum SponsorBlock {
    static let defaultsKey = "skipSponsors"
    static let handlerName = "mbSponsor"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    static func install(in controller: WKUserContentController) {
        guard isEnabled else { return }
        controller.add(SponsorBlockHandler.shared, name: handlerName)
        controller.addUserScript(WKUserScript(source: source,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
    }

    static let source = #"""
    (function () {
      if (!/(^|\.)youtube(-nocookie)?\.com$/.test(location.hostname)) return;
      if (window.__mbSponsorBlock) return;
      window.__mbSponsorBlock = true;

      var currentID = null;
      var segments = [];
      var toastTimer = null;

      function videoIDFromURL() {
        try {
          var u = new URL(location.href);
          if (u.pathname === '/watch') return u.searchParams.get('v');
          var m = u.pathname.match(/^\/(shorts|embed|live)\/([\w-]{11})/);
          return m ? m[2] : null;
        } catch (e) { return null; }
      }

      // Called by the app with the segments it found: [[start, end], ...]
      window.__mbSetSegments = function (id, list) {
        if (id === currentID && Array.isArray(list)) segments = list;
      };

      function toast(text) {
        var el = document.getElementById('mb-sponsor-toast');
        if (!el) {
          el = document.createElement('div');
          el.id = 'mb-sponsor-toast';
          el.style.cssText = 'position:fixed;top:72px;left:50%;transform:translateX(-50%);z-index:2147483647;' +
            'background:rgba(20,20,20,.85);color:#fff;font:13px -apple-system,sans-serif;padding:6px 12px;' +
            'border-radius:14px;pointer-events:none;transition:opacity .3s;opacity:0;';
          (document.body || document.documentElement).appendChild(el);
        }
        el.textContent = text;
        el.style.opacity = '1';
        clearTimeout(toastTimer);
        toastTimer = setTimeout(function () { el.style.opacity = '0'; }, 1800);
      }

      setInterval(function () {
        var id = videoIDFromURL();
        if (id !== currentID) {
          currentID = id;
          segments = [];
          if (id) {
            try { window.webkit.messageHandlers.mbSponsor.postMessage(id); } catch (e) {}
          }
        }
        if (!segments.length) return;

        var player = document.querySelector('.html5-video-player');
        if (player && player.classList.contains('ad-showing')) return;
        var video = document.querySelector('video.html5-main-video') || document.querySelector('video');
        if (!video || video.seeking) return;

        var t = video.currentTime;
        for (var i = 0; i < segments.length; i++) {
          var start = segments[i][0], end = segments[i][1];
          if (t >= start && t < end - 0.25) {
            video.currentTime = end;
            toast('Skipped sponsored segment');
            break;
          }
        }
      }, 200);
    })();
    """#
}

final class SponsorBlockHandler: NSObject, WKScriptMessageHandler {
    static let shared = SponsorBlockHandler()

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config)
    }()

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let id = message.body as? String,
              id.range(of: #"^[A-Za-z0-9_-]{6,20}$"#, options: .regularExpression) != nil else { return }

        let digest = SHA256.hash(data: Data(id.utf8))
        let prefix = digest.map { String(format: "%02x", $0) }.joined().prefix(4)

        var components = URLComponents(string: "https://sponsor.ajay.app/api/skipSegments/\(prefix)")
        components?.queryItems = [
            URLQueryItem(name: "categories", value: "[\"sponsor\",\"selfpromo\",\"interaction\"]"),
            URLQueryItem(name: "actionTypes", value: "[\"skip\"]"),
        ]
        guard let url = components?.url else { return }

        weak var webView = message.webView
        let frame = message.frameInfo

        session.dataTask(with: url) { data, response, _ in
            var pairs: [[Double]] = []
            if (response as? HTTPURLResponse)?.statusCode == 200, let data,
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for entry in list where entry["videoID"] as? String == id {
                    for segment in entry["segments"] as? [[String: Any]] ?? [] {
                        if let times = segment["segment"] as? [Double], times.count == 2 { pairs.append(times) }
                    }
                }
            }
            guard !pairs.isEmpty,
                  let json = (try? JSONSerialization.data(withJSONObject: pairs)).flatMap({ String(data: $0, encoding: .utf8) })
            else { return }
            DispatchQueue.main.async {
                webView?.evaluateJavaScript("window.__mbSetSegments && window.__mbSetSegments(\"\(id)\", \(json))",
                                            in: frame, in: .page) { _ in }
            }
        }.resume()
    }
}
