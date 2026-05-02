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
        let webViewID: ObjectIdentifier
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

    private static func canUse(_ webView: WKWebView?) -> Bool {
        guard let webView else { return false }
        return webView.navigationDelegate != nil
    }

    private static func sendOutput(token: String, message: String, didFinish: Bool, isError: Bool, status: Int? = nil, to webView: WKWebView?) {
        guard canUse(webView) else { return }
        let finishValue = didFinish ? "true" : "false"
        let statusValue = status.map(String.init) ?? "false"
        let js = "window.__handleSystemOutput('\(token)', \(message.debugDescription), \(finishValue), \(didFinish ? statusValue : String(isError)));"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

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
        DispatchQueue.main.async { [weak webView] in
            guard canUse(webView) else { return }
            guard self.requestPermission(command: command, appInfo: appInfo, noAsk: noAsk) else {
                sendOutput(token: token, message: "Permission denied", didFinish: true, isError: true, status: -1, to: webView)
                return
            }
            guard let webView, canUse(webView) else { return }
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

        let webViewID = ObjectIdentifier(webView)
        runningQueue.sync {
            running[token] = RunningCommand(process: process, stdinPipe: inPipe, webViewID: webViewID)
        }

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            outputState.queue.async {
                guard !outputState.isTerminating else { return }
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    sendOutput(token: token, message: str, didFinish: false, isError: false, to: webView)
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            outputState.queue.async {
                guard !outputState.isTerminating else { return }
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    sendOutput(token: token, message: str, didFinish: false, isError: true, to: webView)
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
                        sendOutput(token: token, message: str, didFinish: false, isError: false, to: webView)
                    }
                    if !remainingErr.isEmpty, let str = String(data: remainingErr, encoding: .utf8) {
                        sendOutput(token: token, message: str, didFinish: false, isError: true, to: webView)
                    }
                    sendOutput(token: token, message: "", didFinish: true, isError: false, status: Int(proc.terminationStatus), to: webView)
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
                sendOutput(token: token, message: "Failed to run command: \(error.localizedDescription)", didFinish: true, isError: true, status: -1, to: webView)
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

    static func cancelAll(for webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        let tokens: [String] = runningQueue.sync {
            running.compactMap { token, entry in
                entry.webViewID == webViewID ? token : nil
            }
        }
        for token in tokens {
            cancel(token: token)
        }
    }
}
