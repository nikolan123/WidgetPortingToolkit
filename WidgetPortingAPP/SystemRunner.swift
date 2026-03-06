//
//  SystemRunner.swift
//  WidgetPortingAPP
//
//  Created by Niko on 8.09.25.
//

import Foundation
import AppKit
import WebKit

class SystemRunner {
    private static var running: [String: Process] = [:]

    // ask for permission before running a command
    private static func requestPermissionAndRun(
        command: String,
        appInfo: AppInfo,
        noAsk: Bool,
        runBlock: @escaping () -> Void
    ) {
        if noAsk {
            runBlock()
            return
        }

        let silentMode = UserDefaults.standard.bool(forKey: "silentMode")
        if silentMode {
            print("[SM] Denied running: \(command)")
            return
        }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "\(appInfo.displayName) would like to run a system command"
            alert.informativeText = "\(appInfo.bundleIdentifier) would like to run the following command: \n\n\(command)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Don’t Allow")
            
            if let iconURL = appInfo.iconURL,
               let icon = NSImage(contentsOf: iconURL) {
                alert.icon = icon
            } else {
                alert.icon = NSApp.applicationIconImage
            }
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                runBlock()
            } else {
                print("User denied running: \(command)")
            }
        }
    }

    static func runStreaming(command: String, token: String, webView: WKWebView, appInfo: AppInfo, noAsk: Bool) {
        requestPermissionAndRun(command: command, appInfo: appInfo, noAsk: noAsk) {
            let process = Process()
            process.launchPath = "/bin/zsh"
            process.arguments = ["-c", command]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            running[token] = process

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                if let str = String(data: handle.availableData, encoding: .utf8), !str.isEmpty {
                    DispatchQueue.main.async {
                        let js = "window.__handleSystemOutput('\(token)', \(str.debugDescription), false);"
                        webView.evaluateJavaScript(js, completionHandler: nil)
                    }
                }
            }

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                if let str = String(data: handle.availableData, encoding: .utf8), !str.isEmpty {
                    DispatchQueue.main.async {
                        let js = "window.__handleSystemOutput('\(token)', \(str.debugDescription), false);"
                        webView.evaluateJavaScript(js, completionHandler: nil)
                    }
                }
            }

            process.terminationHandler = { proc in
                running[token] = nil
                DispatchQueue.main.async {
                    let js = "window.__handleSystemOutput('\(token)', '', true, \(proc.terminationStatus));"
                    webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }

            do {
                try process.run()
            } catch {
                print("Failed to run command: \(error)")
            }
        }
    }

    static func cancel(token: String) {
        running[token]?.terminate()
        running[token] = nil
    }
}
