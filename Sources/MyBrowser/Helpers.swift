import SwiftUI
import WebKit

/// Modal text prompt (SwiftUI alerts can't take text input on macOS 13).
func promptForText(title: String, message: String = "", defaultValue: String = "", confirm: String = "OK") -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: confirm)
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    field.stringValue = defaultValue
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

/// Modal yes/no confirmation for destructive actions.
func confirmAction(_ title: String, message: String = "", button: String = "Clear") -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: button)
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
}

/// Web view that makes right-click "Download Image" reliable: it finds the image under the
/// pointer itself and downloads it (with the page as referrer) into the Downloads list.
final class MBWebView: WKWebView {
    var onStartDownload: ((WKDownload) -> Void)?
    private var menuPoint = CGPoint.zero

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        let p = convert(event.locationInWindow, from: nil)
        menuPoint = CGPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y)
        for item in menu.items where item.identifier?.rawValue == "WKMenuItemIdentifierDownloadImage" {
            item.target = self
            item.action = #selector(saveImageToDownloads)
        }
    }

    @objc private func saveImageToDownloads() {
        let js = """
        (function(){
          var el=document.elementFromPoint(\(Int(menuPoint.x)),\(Int(menuPoint.y)));
          while(el){
            if(el.tagName==='IMG'&&(el.currentSrc||el.src)) return el.currentSrc||el.src;
            var i=el.querySelector&&el.querySelector('img');
            if(i&&(i.currentSrc||i.src)) return i.currentSrc||i.src;
            var bg=getComputedStyle(el).backgroundImage;
            var m=bg&&bg.match(/url\\(["']?(.*?)["']?\\)/);
            if(m) return m[1];
            el=el.parentElement;
          }
          return '';
        })()
        """
        evaluateJavaScript(js) { [weak self] result, _ in
            guard let self, let string = result as? String, !string.isEmpty,
                  let url = URL(string: string, relativeTo: self.url)?.absoluteURL else { return }
            var request = URLRequest(url: url)
            if let page = self.url?.absoluteString { request.setValue(page, forHTTPHeaderField: "Referer") }
            self.startDownload(using: request) { download in
                self.onStartDownload?(download)
            }
        }
    }
}
