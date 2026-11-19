// RHCM ONLINE - WebKit bridge (HTML launcher UI)
// Replaces the SwiftUI launcher: UI lives in launcher.html (editable)

import SwiftUI
import UIKit
import WebKit
import Foundation

// MARK: - WebKit launcher

final class RHCMWebLauncher: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let parent: UIViewController
    let done: () -> Void
    var web: WKWebView!
    var timer: Timer?
    var lastProgress: Double = -1
    var lastError: String?
    var lastReady = false

    init(parent: UIViewController, done: @escaping () -> Void) {
        self.parent = parent
        self.done = done
        super.init()
        let cfg = WKWebViewConfiguration()
        let ctrl = WKUserContentController()
        ctrl.add(self, name: "rhcm")
        cfg.userContentController = ctrl
        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.isOpaque = false
        web.backgroundColor = UIColor.black
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.allowsLinkPreview = false
    }

    func show() {
        web.frame = parent.view.bounds
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.view.addSubview(web)

        // load bundled launcher.html
        if let url = Bundle.main.url(forResource: "launcher", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            web.loadHTMLString("<body style='background:#03120d;color:#fff;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh'>launcher.html not found in bundle</body>", baseURL: nil)
        }

        // poll importer state -> push to JS
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.pushStatus()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pushInit()
    }

    // MARK: native -> JS

    func js(_ code: String) {
        web.evaluateJavaScript(code, completionHandler: nil)
    }

    func pushInit() {
        let s = Settings()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        let zips = files.filter { $0.pathExtension.lowercased() == "zip" }.map { $0.lastPathComponent }
        let settings: [String: Any] = [
            "mode": s.mode, "scale": s.scale, "fps": s.fps, "textures": s.textures,
            "touch": s.touch, "mute": s.mute, "name": s.name
        ]
        let payload: [String: Any] = [
            "settings": settings,
            "gameReady": muguet_game_ready(),
            "hasCode": muguet_has_game_code(),
            "zips": zips
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            js("window.rhcmInit && window.rhcmInit(\(json));")
        }
    }

    func pushStatus() {
        let imp = Importer.shared
        if imp.progress != lastProgress {
            lastProgress = imp.progress ?? -1
            if let p = imp.progress {
                js("window.rhcmProgress && window.rhcmProgress(\(p));")
            }
        }
        if imp.error != lastError {
            lastError = imp.error
            if let e = imp.error {
                let esc = e.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                js("window.rhcmError && window.rhcmError('\(esc)');")
            }
        }
        if imp.ready != lastReady {
            lastReady = imp.ready
            if imp.ready {
                js("window.rhcmReady && window.rhcmReady();")
            }
        }
        if imp.progress == nil && lastProgress >= 0 {
            lastProgress = -1
            js("window.rhcmClearStatus && window.rhcmClearStatus();")
        }
    }

    // MARK: JS -> native

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        switch action {
        case "play":
            handlePlay(body)
        case "import":
            handleImport(body)
        default:
            break
        }
    }

    func handlePlay(_ body: [String: Any]) {
        guard let sd = body["settings"] as? [String: Any] else { return }
        let s = Settings()
        if let v = sd["mode"] as? Int, (1...2).contains(v) { s.mode = v }
        if let v = sd["scale"] as? Double { s.scale = v }
        if let v = sd["fps"] as? Int { s.fps = v }
        if let v = sd["textures"] as? Int, (0...2).contains(v) { s.textures = v }
        if let v = sd["touch"] as? Double { s.touch = v }
        if let v = sd["mute"] as? Bool { s.mute = v }
        s.multiplayer = true
        s.host = false
        s.server = (sd["server"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        if let v = sd["name"] as? String, !v.isEmpty { s.name = v }

        // RHCM: must have a server selected
        if s.server.isEmpty {
            js("window.rhcmError && window.rhcmError('กรุณาเลือกเซิร์ฟเวอร์ RHCM');")
            return
        }
        do { try s.save() } catch {
            js("window.rhcmError && window.rhcmError('บันทึกการตั้งค่าไม่ได้');")
            return
        }
        timer?.invalidate()
        web.removeFromSuperview()
        done()
    }

    func handleImport(_ body: [String: Any]) {
        guard let name = body["file"] as? String else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        Importer.shared.run(url)
    }

    // allow file:// subresources etc.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }
}

// MARK: - entry point (called from Rust)

@_cdecl("muguet_show_launcher")
public func muguetShowLauncher(_ viewController: UnsafeMutableRawPointer, _ done: @convention(c) () -> Void) {
    let parent = Unmanaged<UIViewController>.fromOpaque(viewController).takeUnretainedValue()
    let launcher = RHCMWebLauncher(parent: parent) {
        done()
    }
    launcher.show()
}
