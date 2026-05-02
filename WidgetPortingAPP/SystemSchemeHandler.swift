//
//  SystemSchemeHandler.swift
//  WidgetPortingAPP
//
//  Created by Niko on 01.05.26.
//

import Foundation
import WebKit
import AppKit

/// Handles synchronous `widget.system()` calls via the `widget-system://` URL scheme.
/// JS sends a synchronous XMLHttpRequest; this handler runs the command on a background
/// thread and returns the result, keeping JS blocked until completion.
class SystemSchemeHandler: NSObject, WKURLSchemeHandler {
    let appInfo: AppInfo
    let noAsk: Bool
    private let stateQueue = DispatchQueue(label: "SystemSchemeHandler.state")
    private var canceledTasks: Set<ObjectIdentifier> = []
    private var runningProcesses: [ObjectIdentifier: Process] = [:]

    init(appInfo: AppInfo, noAsk: Bool) {
        self.appInfo = appInfo
        self.noAsk = noAsk
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let command = extractCommand(from: urlSchemeTask.request), !command.isEmpty else {
            respond(to: urlSchemeTask, outputString: "", errorString: "No command provided", status: -1)
            return
        }

        // Permission check must run on main because it shows NSAlert
        // runModal() is safe here because the JS thread is blocked in the web process,
        // not on the main thread.
        guard requestPermissionOnMain(command: command) else {
            respond(to: urlSchemeTask, outputString: "", errorString: "Permission denied", status: -1)
            return
        }

        // Run the command on a background thread so we don't block the main thread
        // during long-running commands.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.executeCommand(command, urlSchemeTask: urlSchemeTask)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask as AnyObject)
        stateQueue.sync {
            canceledTasks.insert(id)
            runningProcesses[id]?.terminate()
            runningProcesses[id] = nil
        }
    }

    /// Extracts the command string from the request, trying multiple sources
    /// since httpBody is unreliable for custom URL scheme requests in WKWebView.
    private func extractCommand(from request: URLRequest) -> String? {
        if let url = request.url,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let cmd = components.queryItems?.first(where: { $0.name == "cmd" })?.value,
           !cmd.isEmpty {
            return cmd
        }

        if let body = request.httpBody,
           let str = String(data: body, encoding: .utf8),
           !str.isEmpty {
            return str
        }

        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while true {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                return str
            }
        }

        return nil
    }

    private func requestPermissionOnMain(command: String) -> Bool {
        if Thread.isMainThread {
            return SystemRunner.requestPermission(command: command, appInfo: appInfo, noAsk: noAsk)
        }
        return DispatchQueue.main.sync {
            SystemRunner.requestPermission(command: command, appInfo: appInfo, noAsk: noAsk)
        }
    }

    private func executeCommand(_ command: String, urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        let process = Process()
        process.launchPath = "/bin/zsh"
        process.arguments = ["-c", command]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let shouldLaunch = stateQueue.sync {
            if canceledTasks.remove(taskID) != nil {
                return false
            }
            runningProcesses[taskID] = process
            return true
        }
        guard shouldLaunch else { return }

        do {
            try process.run()
        } catch {
            stateQueue.sync {
                runningProcesses[taskID] = nil
            }
            respond(to: urlSchemeTask, outputString: "", errorString: "Failed to run: \(error.localizedDescription)", status: -1)
            return
        }

        let group = DispatchGroup()
        var outData = Data()
        var errData = Data()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        process.waitUntilExit()
        group.wait()

        let outputString = String(data: outData, encoding: .utf8) ?? ""
        let errorString = String(data: errData, encoding: .utf8) ?? ""
        let status = process.terminationStatus

        stateQueue.sync {
            runningProcesses[taskID] = nil
        }
        respond(to: urlSchemeTask, outputString: outputString, errorString: errorString, status: Int(status))
    }

    private func respond(to urlSchemeTask: WKURLSchemeTask, outputString: String, errorString: String, status: Int) {
        let id = ObjectIdentifier(urlSchemeTask as AnyObject)
        let isCanceled = stateQueue.sync {
            canceledTasks.remove(id) != nil
        }
        if isCanceled { return }

        let result: [String: Any] = [
            "outputString": outputString,
            "errorString": errorString,
            "status": status
        ]

        guard let json = try? JSONSerialization.data(withJSONObject: result) else { return }

        let response = HTTPURLResponse(
            url: urlSchemeTask.request.url ?? URL(string: "widget-system://run")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/json; charset=utf-8",
                "Content-Length": "\(json.count)"
            ]
        )!

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(json)
        urlSchemeTask.didFinish()
    }
}
