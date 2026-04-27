//
//  WebView.swift
//  WidgetPortingAPP
//
//  Created by Niko on 8.09.25.
//

import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let appInfo: AppInfo
    let tweaks: WidgetTweaks

    func makeCoordinator() -> Coordinator {
        Coordinator(appInfo: appInfo, tweaks: tweaks)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        let namespace = context.coordinator.namespace

        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled") // devtools

        // load preferences from UserDefaults and expose them
        let existingPrefs = (UserDefaults.standard.dictionary(forKey: namespace) ?? [:]) as NSDictionary
        let prefsData = (try? JSONSerialization.data(withJSONObject: existingPrefs, options: [])) ?? Data()
        let prefsJSONString = String(data: prefsData, encoding: .utf8) ?? "{}"

        if tweaks.xhrProxyEnabled {
            if let nativeXHRBootstrap = loadJSFromBundle(named: "XHRBridge") {
                controller.addUserScript(
                    WKUserScript(
                        source: nativeXHRBootstrap,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: false
                    )
                )
                controller.add(context.coordinator, name: "nativeXHR_send")
                controller.add(context.coordinator, name: "nativeXHR_abort")
            }
        }

        // inject dashboard api
        if tweaks.recreateDashboardAPI {
            if let widgetBridgeBootstrap = loadJSFromBundle(named: "DashboardAPI"),
               let widgetShims = loadJSFromBundle(named: "WidgetShims") {

                // inject prefs dynamically by replacing placeholder
                let widgetIdentifier = appInfo.bundleIdentifier + "_" + appInfo.id
                let dashboardScript = widgetBridgeBootstrap
                    .replacingOccurrences(of: "__WIDGET_PREFS__", with: prefsJSONString)
                    .replacingOccurrences(of: "__WIDGET_IDENTIFIER__", with: widgetIdentifier)

                // Inject DashboardAPI
                controller.addUserScript(
                    WKUserScript(
                        source: dashboardScript,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    )
                )

                // Inject WidgetShims
                controller.addUserScript(
                    WKUserScript(
                        source: widgetShims,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    )
                )

                if tweaks.emulateDashboardControlRegions,
                   let dragRegions = loadJSFromBundle(named: "DashboardDragRegions") {
                    let dragRegionsScript = dragRegions.replacingOccurrences(
                        of: "__DASHBOARD_REGION_CSS__",
                        with: dashboardRegionCSSJSONString(for: appInfo.tempFolder)
                    )
                    controller.addUserScript(
                        WKUserScript(
                            source: dragRegionsScript,
                            injectionTime: .atDocumentEnd,
                            forMainFrameOnly: true
                        )
                    )
                }

                // Add message handlers
                controller.add(context.coordinator, name: "openURL")
                controller.add(context.coordinator, name: "setPreferenceForKey")
                controller.add(context.coordinator, name: "prepareForTransition")
                controller.add(context.coordinator, name: "performTransition")
                controller.add(context.coordinator, name: "resizeTo")
                controller.add(context.coordinator, name: "dashboardDragStart")
                controller.add(context.coordinator, name: "dashboardDragEnd")
            }
        }
        
        if tweaks.recreateDashboardAPI && tweaks.allowSystemCommands {
            if let systemInjectScript = loadJSFromBundle(named: "SystemInject") {
                controller.addUserScript(
                    WKUserScript(
                        source: systemInjectScript,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    )
                )
                
                controller.add(context.coordinator, name: "systemCommand")
            }

        }

        // css injection
        if tweaks.injectCSS {
            if let cssInjection = loadJSFromBundle(named: "InjectCSS") {
                controller.addUserScript(
                    WKUserScript(
                        source: cssInjection,
                        injectionTime: .atDocumentEnd,
                        forMainFrameOnly: true
                    )
                )
            }
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.wantsLayer = true
        webView.navigationDelegate = context.coordinator

        webView.setValue(tweaks.transparentBackground ? false : true, forKey: "drawsBackground")

        context.coordinator.webView = webView

        webView.loadFileURL(appInfo.htmlURL, allowingReadAccessTo: appInfo.tempFolder)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No-op; re-open window to apply updated tweaks.
    }
    
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let appInfo: AppInfo
        let tweaks: WidgetTweaks
        let namespace: String
        weak var webView: WKWebView?
        private var transitionDirection: String?
        private var dragInitialWindowOrigin: CGPoint?
        private var dragInitialMouseLocation: CGPoint?
        private var dragEventMonitor: Any?

        // XHR-native management
        private lazy var xhrProxy: NativeXHRProxy? = {
            return tweaks.xhrProxyEnabled ? NativeXHRProxy(owner: self) : nil
        }()

        init(appInfo: AppInfo, tweaks: WidgetTweaks) {
            self.appInfo = appInfo
            self.tweaks = tweaks
            self.namespace = "WidgetPrefs::" + appInfo.bundleIdentifier + "_" + appInfo.id
            print("Prefs namespace: \(self.namespace)")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "openURL":
                if let s = message.body as? String, let u = URL(string: s) {
                    NSWorkspace.shared.open(u)
                }
            case "setPreferenceForKey":
                guard let dict = message.body as? [String: Any],
                      let key = dict["key"] as? String else { return }
                print("Setting preference \(key) to \(String(describing: dict["value"]))")
                let val: Any? = dict["value"] is NSNull ? nil : dict["value"]
                var prefs = UserDefaults.standard.dictionary(forKey: namespace) ?? [:]
                if let val { prefs[key] = val } else { prefs.removeValue(forKey: key) }
                UserDefaults.standard.set(prefs, forKey: namespace)

            case "prepareForTransition":
                // Save the requested direction ("toBack" / "toFront")
                transitionDirection = message.body as? String

            case "performTransition":
                guard let webView = webView else { return }
                flipTransition(on: webView, direction: transitionDirection ?? "toBack") {
                    // After animation completes, call back into JS for onshow
                    webView.evaluateJavaScript("""
                      if (typeof window.onshow === 'function') { window.onshow(); }
                    """, completionHandler: nil)
                }
                transitionDirection = nil
                
            case "systemCommand":
                guard let dict = message.body as? [String: Any],
                      let action = dict["action"] as? String,
                      let token = dict["token"] as? String else { return }

                if action == "start" {
                    guard let command = dict["command"] as? String else { return }
                    SystemRunner.runStreaming(command: command, token: token, webView: message.webView!, appInfo: appInfo, noAsk: tweaks.noAskSystemCommands)
                } else if action == "cancel" {
                    SystemRunner.cancel(token: token)
                }
                
            case "resizeTo":
                if let dict = message.body as? [String: Any],
                   let w = dict["width"] as? CGFloat,
                   let h = dict["height"] as? CGFloat,
                   let webView = webView {

                    // Check if we're in a regular window or fullscreen custom window
                    if let window = webView.window, !window.styleMask.contains(.fullScreen) {
                        // Regular window mode - resize the actual NSWindow
                        let oldSize = window.contentLayoutRect.size
                        let newSize = NSSize(width: w, height: h)

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
                    } else {
                        // Fullscreen custom window mode - post notification to update the custom window size
                        NotificationCenter.default.post(
                            name: .resizeCustomWindow,
                            object: nil,
                            userInfo: [
                                "appIdentifier": appInfo.bundleIdentifier + "_" + appInfo.id,
                                "width": w,
                                "height": h
                            ]
                        )
                    }
                }

            case "dashboardDragStart":
                guard tweaks.emulateDashboardControlRegions,
                      let window = webView?.window,
                      !window.styleMask.contains(.fullScreen) else { return }
                beginNativeDashboardDrag(window: window)

            case "dashboardDragEnd":
                endNativeDashboardDrag(callEndHook: true)

            // --- Native XHR handlers ---
            case "nativeXHR_send":
                guard let dict = message.body as? [String: Any],
                      let id = dict["id"] as? Int,
                      let method = dict["method"] as? String,
                      let urlStr = dict["url"] as? String,
                      let url = URL(string: urlStr)
                else { return }

                var request = URLRequest(url: url)
                request.httpMethod = method
                if let headers = dict["headers"] as? [[Any]] {
                    for entry in headers {
                        if entry.count >= 2,
                           let k = entry[0] as? String,
                           let v = entry[1] as? String {
                            request.addValue(v, forHTTPHeaderField: k)
                        }
                    }
                }
                if let body = dict["body"] as? String {
                    request.httpBody = body.data(using: .utf8)
                }
                if let timeout = dict["timeout"] as? Int, timeout > 0 {
                    request.timeoutInterval = TimeInterval(timeout) / 1000.0
                }

                xhrProxy?.start(id: id, request: request)

            case "nativeXHR_abort":
                guard let dict = message.body as? [String: Any],
                      let id = dict["id"] as? Int else { return }
                xhrProxy?.abort(id: id)

            default:
                break
            }
        }

        // XHR -> JS callback
        func sendXHRCallback(_ payload: [String: Any]) {
            guard let webView = webView else { return }
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
               let json = String(data: data, encoding: .utf8) {
                let js = "window.__nativeXHRCallback(\(json));"
                DispatchQueue.main.async {
                    webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }

        // Flip animation
        private func flipTransition(on view: NSView, direction: String, completion: @escaping () -> Void) {
            // Core Animation based flip
            let animation = CATransition()
            animation.type = .init(rawValue: "oglFlip")
            let normalized = direction.lowercased()
            animation.subtype = (normalized == "toback") ? .fromRight : .fromLeft
            animation.duration = 0.6
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            CATransaction.begin()
            CATransaction.setCompletionBlock(completion)
            view.layer?.add(animation, forKey: "flip")
            CATransaction.commit()
        }

        private func beginNativeDashboardDrag(window: NSWindow) {
            dragInitialWindowOrigin = window.frame.origin
            dragInitialMouseLocation = NSEvent.mouseLocation
            callDashboardDragHook("onstartdrag")

            if dragEventMonitor == nil {
                dragEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                    self?.handleNativeDashboardDragEvent(event)
                    return event
                }
            }
        }

        private func handleNativeDashboardDragEvent(_ event: NSEvent) {
            guard let initialWindowOrigin = dragInitialWindowOrigin,
                  let initialMouseLocation = dragInitialMouseLocation,
                  let window = webView?.window,
                  !window.styleMask.contains(.fullScreen) else {
                endNativeDashboardDrag(callEndHook: false)
                return
            }

            switch event.type {
            case .leftMouseDragged:
                let mouseLocation = NSEvent.mouseLocation
                window.setFrameOrigin(CGPoint(
                    x: initialWindowOrigin.x + mouseLocation.x - initialMouseLocation.x,
                    y: initialWindowOrigin.y + mouseLocation.y - initialMouseLocation.y
                ))
            case .leftMouseUp:
                endNativeDashboardDrag(callEndHook: true)
            default:
                break
            }
        }

        private func endNativeDashboardDrag(callEndHook: Bool) {
            guard dragInitialWindowOrigin != nil || dragEventMonitor != nil else { return }

            dragInitialWindowOrigin = nil
            dragInitialMouseLocation = nil

            if let monitor = dragEventMonitor {
                NSEvent.removeMonitor(monitor)
                dragEventMonitor = nil
            }

            if callEndHook {
                callDashboardDragHook("onenddrag")
            }
        }

        private func callDashboardDragHook(_ name: String) {
            webView?.evaluateJavaScript("""
            (function() {
                try {
                    var widgetHook = window.widget && window.widget.\(name);
                    var windowHook = window.\(name);
                    if (typeof widgetHook === 'function') widgetHook();
                    if (typeof windowHook === 'function' && windowHook !== widgetHook) windowHook();
                } catch (e) {}
            })();
            """, completionHandler: nil)
        }

        deinit {
            if let monitor = dragEventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
    func loadJSFromBundle(named name: String, inFolder folder: String? = nil) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: folder),
              let data = try? Data(contentsOf: url),
              let js = String(data: data, encoding: .utf8) else {
            print("Failed to load JS file \(name) in folder \(folder ?? "nil")")
            return nil
        }
        return js
    }

    func dashboardRegionCSSJSONString(for folder: URL) -> String {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil) else { return "[]" }

        var stylesheetSources: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension.caseInsensitiveCompare("css") == .orderedSame {
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            if let css = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
               css.contains("-apple-dashboard-region") {
                stylesheetSources.append(css)
            }
        }

        guard let data = try? JSONSerialization.data(withJSONObject: stylesheetSources, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return json
    }
}
