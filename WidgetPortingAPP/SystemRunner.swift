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
    private struct RunningCommand {
        let process: Process
        let stdinPipe: Pipe
    }

    private final class PipeOutputState {
        let queue: DispatchQueue
        var isTerminating = false

        init(token: String) {
            queue = DispatchQueue(label: "SystemRunner.output.\(token)")
        }
    }

    private static var running: [String: RunningCommand] = [:]
    private static let runningQueue = DispatchQueue(label: "SystemRunner.running")

    // MARK: - Permission

    /// Shows a permission dialog synchronously and returns whether the user allowed the command.
    /// Must be called on the main thread.
    static func requestPermission(command: String, appInfo: AppInfo, noAsk: Bool) -> Bool {
        if noAsk { return true }

        let silentMode = UserDefaults.standard.bool(forKey: "silentMode")
        if silentMode {
            print("[SM] Denied running: \(command)")
            return false
        }

        let alert = NSAlert()
        alert.messageText = "\(appInfo.displayName) would like to run a system command"
        alert.informativeText = "\(appInfo.bundleIdentifier) would like to run the following command: \n\n\(command)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")

        if let iconURL = appInfo.iconURL,
           let icon = NSImage(contentsOf: iconURL) {
            alert.icon = icon
        } else {
            alert.icon = NSApp.applicationIconImage
        }

        let response = alert.runModal()
        if response != .alertFirstButtonReturn {
            print("User denied running: \(command)")
            return false
        }
        return true
    }

    // MARK: - Async (streaming) execution

    static func runStreaming(command: String, token: String, webView: WKWebView, appInfo: AppInfo, noAsk: Bool) {
        // Defer to next run loop iteration to avoid showing modal during WKScriptMessageHandler callback
        DispatchQueue.main.async {
            guard self.requestPermission(command: command, appInfo: appInfo, noAsk: noAsk) else {
                let message = "Permission denied"
                let js = "window.__handleSystemOutput('\(token)', \(message.debugDescription), true, -1);"
                webView.evaluateJavaScript(js, completionHandler: nil)
                return
            }
            self.launchStreaming(command: command, token: token, webView: webView)
        }
    }

    private static func launchStreaming(command: String, token: String, webView: WKWebView) {
        let process = Process()
        process.launchPath = "/bin/zsh"
        process.arguments = ["-c", command]

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe
        let outputState = PipeOutputState(token: token)

        runningQueue.sync {
            running[token] = RunningCommand(process: process, stdinPipe: inPipe)
        }

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            outputState.queue.async {
                guard !outputState.isTerminating else { return }
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    let js = "window.__handleSystemOutput('\(token)', \(str.debugDescription), false, false);"
                    webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            outputState.queue.async {
                guard !outputState.isTerminating else { return }
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    let js = "window.__handleSystemOutput('\(token)', \(str.debugDescription), false, true);"
                    webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }

        process.terminationHandler = { proc in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            outputState.queue.async {
                outputState.isTerminating = true
                let remainingOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingErr = errPipe.fileHandleForReading.readDataToEndOfFile()

                runningQueue.sync { running[token] = nil }

                DispatchQueue.main.async {
                    if !remainingOut.isEmpty, let str = String(data: remainingOut, encoding: .utf8) {
                        let js = "window.__handleSystemOutput('\(token)', \(str.debugDescription), false, false);"
                        webView.evaluateJavaScript(js, completionHandler: nil)
                    }
                    if !remainingErr.isEmpty, let str = String(data: remainingErr, encoding: .utf8) {
                        let js = "window.__handleSystemOutput('\(token)', \(str.debugDescription), false, true);"
                        webView.evaluateJavaScript(js, completionHandler: nil)
                    }
                    let js = "window.__handleSystemOutput('\(token)', '', true, \(proc.terminationStatus));"
                    webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }

        do {
            try process.run()
        } catch {
            print("Failed to run command: \(error)")
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            runningQueue.sync {
                running[token] = nil
            }
            DispatchQueue.main.async {
                let message = "Failed to run command: \(error.localizedDescription)"
                let js = "window.__handleSystemOutput('\(token)', \(message.debugDescription), true, -1);"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    // MARK: - Stdin

    static func write(token: String, string: String) {
        let entry = runningQueue.sync { running[token] }
        guard let entry else { return }
        if let data = string.data(using: .utf8) {
            entry.stdinPipe.fileHandleForWriting.write(data)
        }
    }

    static func closeStdin(token: String) {
        let entry = runningQueue.sync { running[token] }
        guard let entry else { return }
        entry.stdinPipe.fileHandleForWriting.closeFile()
    }

    // MARK: - Cancel

    static func cancel(token: String) {
        let entry = runningQueue.sync { running[token] }
        entry?.process.terminate()
        runningQueue.sync {
            running[token] = nil
        }
    }
}
