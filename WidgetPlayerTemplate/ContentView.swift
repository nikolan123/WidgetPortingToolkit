//
//  ContentView.swift
//  WidgetPlayerTemplate
//
//  Created by Niko on 24.04.26.
//

import SwiftUI
import WebKit
import AppKit

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
        guard let resourcesURL = Bundle.main.resourceURL else { return nil }
        let widgetRoot = resourcesURL.appendingPathComponent("widget", isDirectory: true)
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
        let displayName = (plist["CFBundleDisplayName"] as? String) ??
                          (plist["CFBundleName"] as? String) ??
                          (plist["CFBundleIdentifier"] as? String) ??
                          "Widget"
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

    private static func parseDimension(_ raw: Any?) -> CGFloat? {
        if let n = raw as? NSNumber {
            let value = CGFloat(truncating: n)
            return value > 0 ? value : nil
        }
        if let s = raw as? String {
            let cleaned = s.replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Double(cleaned), value > 0 {
                return CGFloat(value)
            }
        }
        return nil
    }

    private static func defaultImageSize(in folder: URL) -> (CGFloat, CGFloat)? {
        let fm = FileManager.default
        let candidates = ["Default.png", "default.png"]
        for name in candidates {
            let imageURL = folder.appendingPathComponent(name)
            guard fm.fileExists(atPath: imageURL.path) else { continue }
            guard let image = NSImage(contentsOf: imageURL) else { continue }
            let size = image.size
            if size.width > 0 && size.height > 0 {
                return (size.width, size.height)
            }
        }
        return nil
    }
}

struct ContentView: View {
    let config: WidgetConfig?
    @State private var didConfigureWindow = false

    var body: some View {
        Group {
            if let config {
                WidgetWebView(config: config)
                    .frame(width: config.width, height: config.height)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.orange)
                    Text("Widget payload missing")
                        .font(.headline)
                    Text("Expected widget files at Contents/Resources/widget.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
        }
        .onAppear {
            guard !didConfigureWindow else { return }
            didConfigureWindow = true
            configureWindow()
        }
    }

    private func configureWindow() {
        guard let config else { return }
        DispatchQueue.main.async {
            if let window = NSApp.windows.first {
                window.title = config.displayName
                window.setContentSize(NSSize(width: config.width, height: config.height))
            }
        }
    }
}

struct WidgetWebView: NSViewRepresentable {
    let config: WidgetConfig

    func makeCoordinator() -> Coordinator {
        Coordinator(config: config)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        controller.add(context.coordinator, name: "openURL")
        controller.add(context.coordinator, name: "setPreferenceForKey")
        controller.add(context.coordinator, name: "prepareForTransition")
        controller.add(context.coordinator, name: "performTransition")
        controller.add(context.coordinator, name: "resizeTo")
        controller.add(context.coordinator, name: "systemCommand")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadFileURL(config.entryURL, allowingReadAccessTo: config.widgetRoot)

        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let config: WidgetConfig
        let prefsNamespace: String
        weak var webView: WKWebView?
        var transitionDirection: String?
        private let processQueue = DispatchQueue(label: "WidgetPlayerTemplate.systemCommand")
        private var runningProcesses: [String: Process] = [:]
        private var outputBuffers: [String: String] = [:]

        init(config: WidgetConfig) {
            self.config = config
            self.prefsNamespace = "WidgetPrefs::\(config.bundleIdentifier)"
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
                if let value {
                    prefs[key] = value
                } else {
                    prefs.removeValue(forKey: key)
                }
                UserDefaults.standard.set(prefs, forKey: prefsNamespace)

            case "prepareForTransition":
                transitionDirection = message.body as? String

            case "performTransition":
                if let webView {
                    performFlip(on: webView, direction: transitionDirection ?? "toBack")
                }
                transitionDirection = nil

            case "resizeTo":
                guard let dict = message.body as? [String: Any],
                      let width = readCGFloat(dict["width"]),
                      let height = readCGFloat(dict["height"]),
                      let window = webView?.window else { return }
                window.setContentSize(NSSize(width: max(1, width), height: max(1, height)))

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
            if let number = value as? NSNumber {
                return CGFloat(truncating: number)
            }
            if let text = value as? String, let number = Double(text) {
                return CGFloat(number)
            }
            return nil
        }

        private func performFlip(on view: NSView, direction: String) {
            let transition = CATransition()
            transition.type = .init(rawValue: "oglFlip")
            transition.subtype = direction.lowercased().contains("back") ? .fromLeft : .fromRight
            transition.duration = 0.45
            view.layer?.add(transition, forKey: "widgetFlip")
            view.wantsLayer = true
            webView?.evaluateJavaScript("if (typeof window.onshow === 'function') { window.onshow(); }", completionHandler: nil)
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
                guard let process = self.runningProcesses[token] else { return }
                if process.isRunning {
                    process.terminate()
                }
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
                self.webView?.evaluateJavaScript(js, completionHandler: nil)
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
}
