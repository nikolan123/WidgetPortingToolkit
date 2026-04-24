//
//  ContentView.swift
//  WidgetPlayerTemplate
//
//  Created by Niko on 24.04.26.
//

import AppKit
import WebKit

struct WidgetConfig {
    let widgetRoot: URL
    let entryURL: URL
    let width: CGFloat
    let height: CGFloat
    let displayName: String
    let bundleIdentifier: String
}

enum WidgetConfigLoader {
    static func load() -> WidgetConfig? {
        guard let widgetRoot = resolveWidgetRoot() else { return nil }

        let infoURL = widgetRoot.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }

        let mainHTML = (plist["MainHTML"] as? String) ?? "index.html"
        let entryURL = widgetRoot.appendingPathComponent(mainHTML)
        guard FileManager.default.fileExists(atPath: entryURL.path) else { return nil }

        let width = parseDimension(plist["Width"]) ?? defaultImageSize(in: widgetRoot)?.0 ?? 800
        let height = parseDimension(plist["Height"]) ?? defaultImageSize(in: widgetRoot)?.1 ?? 600
        let displayName = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? (plist["CFBundleIdentifier"] as? String)
            ?? "Widget"
        let bundleIdentifier = (plist["CFBundleIdentifier"] as? String) ?? "widget.export"

        return WidgetConfig(
            widgetRoot: widgetRoot,
            entryURL: entryURL,
            width: width,
            height: height,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier
        )
    }

    private static func resolveWidgetRoot() -> URL? {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment

        if let rawPath = env["WPT_WIDGET_DEV_ROOT"], !rawPath.isEmpty {
            let expanded = NSString(string: rawPath).expandingTildeInPath
            let candidate = URL(fileURLWithPath: expanded).standardizedFileURL
            if fm.fileExists(atPath: candidate.appendingPathComponent("Info.plist").path) {
                return candidate
            }
        }

        guard let resourcesURL = Bundle.main.resourceURL else { return nil }
        let bundled = resourcesURL.appendingPathComponent("widget", isDirectory: true)
        if fm.fileExists(atPath: bundled.appendingPathComponent("Info.plist").path) {
            return bundled
        }
        return nil
    }

    private static func parseDimension(_ raw: Any?) -> CGFloat? {
        if let number = raw as? NSNumber {
            let value = CGFloat(truncating: number)
            return value > 0 ? value : nil
        }
        if let text = raw as? String {
            let cleaned = text.replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Double(cleaned), value > 0 {
                return CGFloat(value)
            }
        }
        return nil
    }

    private static func defaultImageSize(in folder: URL) -> (CGFloat, CGFloat)? {
        let fm = FileManager.default
        for name in ["Default.png", "default.png"] {
            let imageURL = folder.appendingPathComponent(name)
            guard fm.fileExists(atPath: imageURL.path), let image = NSImage(contentsOf: imageURL) else { continue }
            let size = image.size
            if size.width > 0 && size.height > 0 {
                return (size.width, size.height)
            }
        }
        return nil
    }
}

final class WidgetPlayerViewController: NSViewController, WKScriptMessageHandler, WKNavigationDelegate {
    let config: WidgetConfig
    private let prefsNamespace: String
    private var transitionDirection: String?
    private let processQueue = DispatchQueue(label: "WidgetPlayerTemplate.systemCommand")
    private var runningProcesses: [String: Process] = [:]
    private var outputBuffers: [String: String] = [:]

    private(set) var webView: WKWebView!

    init(config: WidgetConfig) {
        self.config = config
        self.prefsNamespace = "WidgetPrefs::\(config.bundleIdentifier)"
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let webConfig = WKWebViewConfiguration()
        let controller = webConfig.userContentController
        webConfig.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Mirror main target bridge behavior.
        injectDashboardScripts(into: controller)
        injectCSSTweaks(into: controller)

        ["openURL", "setPreferenceForKey", "prepareForTransition", "performTransition", "resizeTo", "systemCommand"]
            .forEach { controller.add(self, name: $0) }

        let webView = WKWebView(frame: .zero, configuration: webConfig)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        self.webView = webView
        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.loadFileURL(config.entryURL, allowingReadAccessTo: config.widgetRoot)
    }

    private func injectDashboardScripts(into controller: WKUserContentController) {
        let prefs = UserDefaults.standard.dictionary(forKey: prefsNamespace) ?? [:]
        let prefsData = (try? JSONSerialization.data(withJSONObject: prefs, options: [])) ?? Data()
        let prefsJSON = String(data: prefsData, encoding: .utf8) ?? "{}"
        let widgetIdentifier = config.bundleIdentifier + "_template"

        if let dashboard = loadBundledJS(named: "DashboardAPI"),
           let widgetShims = loadBundledJS(named: "WidgetShims") {
            let dashboardPatched = dashboard
                .replacingOccurrences(of: "__WIDGET_PREFS__", with: prefsJSON)
                .replacingOccurrences(of: "__WIDGET_IDENTIFIER__", with: widgetIdentifier)

            controller.addUserScript(
                WKUserScript(source: dashboardPatched, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
            controller.addUserScript(
                WKUserScript(source: widgetShims, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }

        if let systemInject = loadBundledJS(named: "SystemInject") {
            controller.addUserScript(
                WKUserScript(source: systemInject, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }
    }

    private func injectCSSTweaks(into controller: WKUserContentController) {
        if let injectCSS = loadBundledJS(named: "InjectCSS") {
            controller.addUserScript(
                WKUserScript(source: injectCSS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            )
            return
        }

        // Fallback if InjectCSS.js is not in this target's resources.
        let fallback = """
        (function(){
          var s = document.createElement('style');
          s.type = 'text/css';
          s.appendChild(document.createTextNode(`
        * { -webkit-user-drag: none; -webkit-user-select: none; }
        *[src*="SupportDirectory/"][src*="button"], *[style*="SupportDirectory/"][style*="button"] { cursor: pointer; }
        html, body {
          overflow: hidden !important;
          margin: 0 !important;
          padding: 0 !important;
          width: 100% !important;
          height: 100% !important;
        }
          `));
          (document.head || document.documentElement).appendChild(s);
        })();
        """
        controller.addUserScript(
            WKUserScript(source: fallback, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
    }

    private func loadBundledJS(named name: String) -> String? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "js"),
            Bundle.main.url(forResource: name, withExtension: "js")
        ]
        for candidate in candidates {
            guard let url = candidate,
                  let data = try? Data(contentsOf: url),
                  let source = String(data: data, encoding: .utf8) else { continue }
            return source
        }
        return nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "openURL":
            guard let raw = message.body as? String, let url = URL(string: raw) else { return }
            NSWorkspace.shared.open(url)

        case "setPreferenceForKey":
            guard let dict = message.body as? [String: Any], let key = dict["key"] as? String else { return }
            var prefs = UserDefaults.standard.dictionary(forKey: prefsNamespace) ?? [:]
            let value = dict["value"] is NSNull ? nil : dict["value"]
            if let value { prefs[key] = value } else { prefs.removeValue(forKey: key) }
            UserDefaults.standard.set(prefs, forKey: prefsNamespace)

        case "prepareForTransition":
            transitionDirection = message.body as? String

        case "performTransition":
            performFlip(direction: transitionDirection ?? "toBack")
            transitionDirection = nil

        case "resizeTo":
            guard let dict = message.body as? [String: Any],
                  let width = readCGFloat(dict["width"]),
                  let height = readCGFloat(dict["height"]),
                  let window = webView.window else { return }

            let oldSize = window.contentLayoutRect.size
            let newSize = NSSize(width: max(1, width), height: max(1, height))

            let steps = 15
            let duration: TimeInterval = 0.25
            let stepDuration = duration / Double(steps)

            for i in 1...steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) {
                    let t = CGFloat(i) / CGFloat(steps)
                    let curW = oldSize.width + (newSize.width - oldSize.width) * t
                    let curH = oldSize.height + (newSize.height - oldSize.height) * t
                    window.setContentSize(NSSize(width: curW, height: curH))
                }
            }

        case "systemCommand":
            guard let dict = message.body as? [String: Any],
                  let action = dict["action"] as? String,
                  let token = dict["token"] as? String else { return }
            if action == "cancel" {
                cancelSystemCommand(token: token)
                return
            }
            guard action == "start", let command = dict["command"] as? String else { return }
            runSystemCommand(command: command, token: token)

        default:
            break
        }
    }

    private func readCGFloat(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber { return CGFloat(truncating: number) }
        if let text = value as? String, let number = Double(text) { return CGFloat(number) }
        return nil
    }

    private func performFlip(direction: String) {
        let transition = CATransition()
        transition.type = .init(rawValue: "oglFlip")
        transition.subtype = direction.lowercased().contains("back") ? .fromLeft : .fromRight
        transition.duration = 0.45
        webView.layer?.add(transition, forKey: "widgetFlip")
        webView.wantsLayer = true
        webView.evaluateJavaScript("if (typeof window.onshow === 'function') { window.onshow(); }", completionHandler: nil)
    }

    private func runSystemCommand(command: String, token: String) {
        let allow = promptForSystemCommand(command: command)
        guard allow else {
            emitSystemOutput(token: token, text: "Command denied by user.\n", done: true, status: 126)
            return
        }

        processQueue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = outPipe
            self.runningProcesses[token] = process
            self.outputBuffers[token] = ""

            outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let chunk = String(data: data, encoding: .utf8) ?? ""
                self.processQueue.async {
                    self.outputBuffers[token, default: ""] += chunk
                    self.emitSystemOutput(token: token, text: chunk, done: false, status: 0)
                }
            }

            process.terminationHandler = { [weak self] finished in
                guard let self else { return }
                self.processQueue.async {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    let output = self.outputBuffers.removeValue(forKey: token) ?? ""
                    self.runningProcesses.removeValue(forKey: token)
                    self.emitSystemOutput(token: token, text: output, done: true, status: Int(finished.terminationStatus))
                }
            }

            do {
                try process.run()
            } catch {
                self.runningProcesses.removeValue(forKey: token)
                self.outputBuffers.removeValue(forKey: token)
                self.emitSystemOutput(token: token, text: "Failed to run command: \(error.localizedDescription)\n", done: true, status: 127)
            }
        }
    }

    private func cancelSystemCommand(token: String) {
        processQueue.async {
            guard let process = self.runningProcesses[token], process.isRunning else { return }
            process.terminate()
        }
    }

    private func promptForSystemCommand(command: String) -> Bool {
        var allowed = false
        DispatchQueue.main.sync {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "'\(config.displayName)' wants to run a system command."
            alert.informativeText = command
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Deny")
            alert.buttons.first?.keyEquivalent = "\r"
            alert.buttons.last?.keyEquivalent = "\u{1b}"
            allowed = (alert.runModal() == .alertFirstButtonReturn)
        }
        return allowed
    }

    private func emitSystemOutput(token: String, text: String, done: Bool, status: Int) {
        let tokenJSON = jsonString(token)
        let textJSON = jsonString(text)
        let doneJSON = done ? "true" : "false"
        let js = "window.__handleSystemOutput(\(tokenJSON), \(textJSON), \(doneJSON), \(status));"
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func jsonString(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
           var encoded = String(data: data, encoding: .utf8) {
            encoded.removeFirst()
            encoded.removeLast()
            return encoded
        }
        return "\"\""
    }
}
