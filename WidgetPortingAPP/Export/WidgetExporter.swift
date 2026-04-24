//
//  WidgetExporter.swift
//  WidgetPortingAPP
//
//  Created by Niko on 24.04.26.
//

import Foundation

struct WidgetExportArtifact {
    let workDirectory: URL
    let zipURL: URL
    let suggestedFileName: String
}

enum WidgetExportError: LocalizedError {
    case invalidInput(String)
    case missingSupportDirectory
    case parseFailed(String)
    case fileOperationFailed(String)
    case zipFailed(String)
    case runtimeGenerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidInput(let reason): return reason
        case .missingSupportDirectory: return "No Support Directory set. Install one from Options > Install Support Directory first."
        case .parseFailed(let reason): return reason
        case .fileOperationFailed(let reason): return reason
        case .zipFailed(let reason): return reason
        case .runtimeGenerationFailed: return "Failed to generate runtime bridge script."
        }
    }
}

enum WidgetExporter {
    static func exportWidgetToHTMLBundle(
        widgetURL: URL,
        supportDirectoryPath: String,
        progress: @escaping (String) -> Void
    ) throws -> WidgetExportArtifact {
        let fm = FileManager.default
        let normalizedPath = widgetURL.pathExtension.lowercased()

        guard normalizedPath == "wdgt" else {
            throw WidgetExportError.invalidInput("Expected a .wdgt bundle.")
        }
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: widgetURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WidgetExportError.invalidInput("The dropped item is not a valid widget folder.")
        }
        guard !supportDirectoryPath.isEmpty else {
            throw WidgetExportError.missingSupportDirectory
        }

        progress("Parsing widget metadata…")
        var parseError: String?
        guard let parsed = parsePlist(from: widgetURL, showError: { parseError = $0 }) else {
            throw WidgetExportError.parseFailed(parseError ?? "Failed to parse widget Info.plist.")
        }

        let exportID = UUID().uuidString
        let workDirectory = fm.temporaryDirectory.appendingPathComponent("WidgetHTMLExport_\(exportID)", isDirectory: true)
        let exportFolderName = "\(widgetURL.deletingPathExtension().lastPathComponent)_html_export"
        let exportFolder = workDirectory.appendingPathComponent(exportFolderName, isDirectory: true)
        let supportDestination = exportFolder.appendingPathComponent("SupportDirectory", isDirectory: true)

        do {
            try fm.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            try fm.copyItem(at: widgetURL, to: exportFolder)
        } catch {
            throw WidgetExportError.fileOperationFailed("Failed to create export workspace: \(error.localizedDescription)")
        }

        progress("Copying Support Directory…")
        do {
            try fm.copyItem(at: URL(fileURLWithPath: supportDirectoryPath), to: supportDestination)
        } catch {
            throw WidgetExportError.fileOperationFailed("Failed to copy Support Directory into export: \(error.localizedDescription)")
        }

        progress("Patching HTML/JS/CSS paths…")
        try patchWidgetFilesForExport(in: exportFolder)

        progress("Preparing runtime JavaScript files…")
        try writeRuntimeScripts(into: exportFolder, bundleID: parsed.bundleIdentifier)

        progress("Injecting runtime references into HTML files…")
        injectRuntimeScriptReferences(
            in: exportFolder,
            scriptFileNames: ["DashboardAPI.js", "WidgetShims.js", "SystemInject.js", "ExportRuntime.js"]
        )

        progress("Preparing localizedStrings fallback…")
        let localizedFile = exportFolder.appendingPathComponent("localizedStrings.js")
        if !fm.fileExists(atPath: localizedFile.path) {
            let stub = "var localizedStrings = {};"
            try? stub.write(to: localizedFile, atomically: true, encoding: .utf8)
        }

        progress("Creating zip archive…")
        let zipURL = workDirectory.appendingPathComponent("\(exportFolderName).zip")
        try zipFolder(at: exportFolder, to: zipURL, from: workDirectory)

        let suggestedFileName = "\(widgetURL.deletingPathExtension().lastPathComponent)-html-widget.zip"
        return WidgetExportArtifact(workDirectory: workDirectory, zipURL: zipURL, suggestedFileName: suggestedFileName)
    }

    private static func patchWidgetFilesForExport(in folder: URL) throws {
        let fm = FileManager.default
        let allowedExtensions = Set(["html", "js", "css"])
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil) else {
            throw WidgetExportError.fileOperationFailed("Failed to enumerate export folder.")
        }

        for case let fileURL as URL in enumerator {
            guard allowedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            if fileURL.path.contains(".lproj/") { continue }

            do {
                let original = try String(contentsOf: fileURL, encoding: .utf8)
                var content = original

                content = content.replacingOccurrences(
                    of: "file:///System/Library/WidgetResources",
                    with: "./SupportDirectory"
                )
                content = content.replacingOccurrences(
                    of: "/System/Library/WidgetResources",
                    with: "./SupportDirectory"
                )
                content = content.replacingOccurrences(
                    of: "\"AppleClasses",
                    with: "\"./SupportDirectory/AppleClasses"
                )
                content = content.replacingOccurrences(
                    of: #"~/Library/Widgets/(?:\\ |[^ ])+\.wdgt(.*)"#,
                    with: "./$1",
                    options: .regularExpression
                )

                let scriptPattern = #"<script([^>]*)\/>"#
                content = content.replacingOccurrences(
                    of: scriptPattern,
                    with: "<script$1></script>",
                    options: .regularExpression
                )

                if content != original {
                    try content.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            } catch {
                throw WidgetExportError.fileOperationFailed("Failed while patching \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    private static func injectRuntimeScriptReferences(in folder: URL, scriptFileNames: [String]) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil) else { return }
        let scriptTags = scriptFileNames.map { "<script src=\"./\($0)\"></script>" }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "html" else { continue }
            if fileURL.path.contains(".lproj/") { continue }

            guard var html = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if scriptFileNames.contains(where: { html.contains($0) }) { continue }

            let injected = scriptTags.joined(separator: "\n")

            if let headRange = html.range(of: "</head>", options: [.caseInsensitive]) {
                html.insert(contentsOf: "\(injected)\n", at: headRange.lowerBound)
            } else if let bodyRange = html.range(of: "</body>", options: [.caseInsensitive]) {
                html.insert(contentsOf: "\(injected)\n", at: bodyRange.lowerBound)
            } else {
                html.append("\n\(injected)\n")
            }

            try? html.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private static func zipFolder(at folder: URL, to zipURL: URL, from workingDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = workingDirectory
        process.arguments = ["-r", "-y", zipURL.lastPathComponent, folder.lastPathComponent]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw WidgetExportError.zipFailed("Failed to start zip process: \(error.localizedDescription)")
        }

        if process.terminationStatus != 0 {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: errorData, encoding: .utf8) ?? "unknown error"
            throw WidgetExportError.zipFailed("zip failed with status \(process.terminationStatus): \(stderrText)")
        }
    }

    private static func writeRuntimeScripts(into folder: URL, bundleID: String) throws {
        guard let dashboard = loadBundledJS(named: "DashboardAPI"),
              let widgetShims = loadBundledJS(named: "WidgetShims"),
              let systemInject = loadBundledJS(named: "SystemInject"),
              let exportRuntime = loadBundledJS(named: "ExportRuntime") else {
            throw WidgetExportError.runtimeGenerationFailed
        }

        let dashboardPatched = dashboard
            .replacingOccurrences(of: "__WIDGET_PREFS__", with: "{}")
            .replacingOccurrences(of: "__WIDGET_IDENTIFIER__", with: "\(bundleID)_html_export")

        let outputs: [(String, String)] = [
            ("DashboardAPI.js", dashboardPatched),
            ("WidgetShims.js", widgetShims),
            ("SystemInject.js", systemInject),
            ("ExportRuntime.js", exportRuntime)
        ]

        do {
            for (fileName, source) in outputs {
                let target = folder.appendingPathComponent(fileName)
                try source.write(to: target, atomically: true, encoding: .utf8)
            }
        } catch {
            throw WidgetExportError.fileOperationFailed("Failed to write runtime scripts: \(error.localizedDescription)")
        }
    }

    private static func loadBundledJS(named name: String) -> String? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "js"),
            Bundle.main.url(forResource: name, withExtension: "js", subdirectory: nil)
        ]

        for candidate in candidates {
            guard let url = candidate,
                  let data = try? Data(contentsOf: url),
                  let source = String(data: data, encoding: .utf8) else {
                continue
            }
            return source
        }
        return nil
    }
}
