import UIKit
import WebKit

final class WebViewController: UIViewController, WKUIDelegate, WKScriptMessageHandler {

    private var webView: WKWebView!
    private let ble = BLEBridge()
    private let bg = UIColor(red: 10 / 255, green: 18 / 255, blue: 48 / 255, alpha: 1)

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = bg
        overrideUserInterfaceStyle = .dark

        let ucc = WKUserContentController()

        // localStorage-Inhalt aus UserDefaults vor der Seite bereitstellen
        let store = UserDefaults.standard.dictionary(forKey: "ls") as? [String: String] ?? [:]
        let storeJSON = (try? JSONSerialization.data(withJSONObject: store))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        ucc.addUserScript(WKUserScript(source: "window.__nativeStore=\(storeJSON);",
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))

        if let url = Bundle.main.url(forResource: "bridge", withExtension: "js"),
           let js = try? String(contentsOf: url, encoding: .utf8) {
            ucc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        ucc.add(self, name: "ble")

        let cfg = WKWebViewConfiguration()
        cfg.userContentController = ucc

        webView = WKWebView(frame: view.bounds, configuration: cfg)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = bg
        webView.scrollView.backgroundColor = bg
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        view.addSubview(webView)

        ble.host = self
        ble.reply = { [weak self] id, ok, payload in
            self?.eval("window.__eyReply.apply(null,\(Self.json([id, ok, payload])))")
        }
        ble.emit = { [weak self] type, obj in
            self?.eval("window.__eyEvent&&window.__eyEvent.apply(null,\(Self.json([type, obj])))")
        }

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    private static func json(_ any: [Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: any),
              let s = String(data: d, encoding: .utf8) else { return "[]" }
        return s
    }

    private func eval(_ js: String) {
        DispatchQueue.main.async { self.webView.evaluateJavaScript(js, completionHandler: nil) }
    }

    // MARK: Nachrichten aus der Seite

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let cmd = m["cmd"] as? String else { return }
        let id = m["id"] as? Int

        switch cmd {
        case "store":
            var d = UserDefaults.standard.dictionary(forKey: "ls") as? [String: String] ?? [:]
            switch m["op"] as? String ?? "" {
            case "set": if let k = m["key"] as? String, let v = m["value"] as? String { d[k] = v }
            case "del": if let k = m["key"] as? String { d.removeValue(forKey: k) }
            case "clear": d.removeAll()
            default: break
            }
            UserDefaults.standard.set(d, forKey: "ls")

        case "copy":
            UIPasteboard.general.string = m["text"] as? String ?? ""
            if let id = id { ble.reply(id, true, NSNull()) }

        case "share":
            let name = (m["name"] as? String) ?? "log.txt"
            let text = (m["text"] as? String) ?? ""
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                vc.popoverPresentationController?.sourceView = view
                vc.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                present(vc, animated: true)
                if let id = id { ble.reply(id, true, NSNull()) }
            } catch {
                if let id = id { ble.reply(id, false, ["name": "NetworkError", "message": error.localizedDescription]) }
            }

        default:
            ble.handle(m)
        }
    }

    // MARK: confirm() / alert() aus der Seite

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Abbrechen", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }
}
