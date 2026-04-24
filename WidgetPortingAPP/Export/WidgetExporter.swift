//
//  WidgetExporter.swift
//  WidgetPortingAPP
//
//  Created by Niko on 24.04.26.
//

import Foundation

enum WidgetExportFormat: String, CaseIterable, Identifiable {
    case zip
    case webarchive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zip: return "ZIP (.zip)"
        case .webarchive: return "Web Archive (.webarchive)"
        }
    }

    var outputExtension: String {
        switch self {
        case .zip: return "zip"
        case .webarchive: return "webarchive"
        }
    }
}

struct WidgetExportArtifact {
    let workDirectory: URL
    let outputURL: URL
    let suggestedFileName: String
    let format: WidgetExportFormat
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
        format: WidgetExportFormat,
        supportDirectoryPath: String,
        progress: @escaping (String) -> Void
    ) throws -> WidgetExportArtifact {
        let fm = FileManager.default
        let normalizedPath = widgetURL.pathExtension.lowercased()
        var logLines: [String] = []

        func step(_ message: String) {
            progress(message)
            logLines.append("[\(isoTimestamp())] \(message)")
        }

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

        step("Parsing widget metadata…")
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

        step("Copying Support Directory…")
        do {
            try fm.copyItem(at: URL(fileURLWithPath: supportDirectoryPath), to: supportDestination)
        } catch {
            throw WidgetExportError.fileOperationFailed("Failed to copy Support Directory into export: \(error.localizedDescription)")
        }

        step("Patching HTML/JS/CSS paths…")
        try patchWidgetFilesForExport(in: exportFolder, mainHTMLPath: parsed.mainHTML)

        step("Preparing runtime JavaScript files…")
        try writeRuntimeScripts(into: exportFolder, bundleID: parsed.bundleIdentifier)

        step("Injecting runtime references into HTML files…")
        injectRuntimeScriptReferences(
            rootFolder: exportFolder,
            in: exportFolder,
            scriptFileNames: ["DashboardAPI.js", "WidgetShims.js", "SystemInject.js", "ExportRuntime.js"]
        )

        step("Preparing localizedStrings fallback…")
        let localizedFile = exportFolder.appendingPathComponent("localizedStrings.js")
        if !fm.fileExists(atPath: localizedFile.path) {
            let stub = "var localizedStrings = {};"
            try? stub.write(to: localizedFile, atomically: true, encoding: .utf8)
        }

        step("Removing hidden/version-control files…")
        try sanitizeExportFolder(at: exportFolder)

        step("Writing info.txt…")
        try writeInfoFile(
            into: exportFolder,
            widgetURL: widgetURL,
            parsed: parsed,
            supportDirectoryPath: supportDirectoryPath,
            logLines: logLines
        )

        let outputURL: URL
        let suggestedFileName: String
        switch format {
        case .zip:
            step("Creating zip archive…")
            let zipURL = workDirectory.appendingPathComponent("\(exportFolderName).zip")
            try zipFolder(at: exportFolder, to: zipURL, from: workDirectory)
            outputURL = zipURL
            suggestedFileName = "\(widgetURL.deletingPathExtension().lastPathComponent)-html-widget.zip"
        case .webarchive:
            step("Creating .webarchive (binary plist)…")
            let webarchiveURL = workDirectory.appendingPathComponent("\(exportFolderName).webarchive")
            try WebArchiveBuilder.writeWebArchive(from: exportFolder, parsed: parsed, to: webarchiveURL)
            outputURL = webarchiveURL
            suggestedFileName = "\(widgetURL.deletingPathExtension().lastPathComponent)-html-widget.webarchive"
        }

        return WidgetExportArtifact(
            workDirectory: workDirectory,
            outputURL: outputURL,
            suggestedFileName: suggestedFileName,
            format: format
        )
    }

    private static func writeInfoFile(
        into folder: URL,
        widgetURL: URL,
        parsed: ParsedInfo,
        supportDirectoryPath: String,
        logLines: [String]
    ) throws {
        let width = Int(parsed.width.rounded())
        let height = Int(parsed.height.rounded())
        let lines: [String] = [
            "Widget Porting Toolkit HTML Export",
            "Generated: \(isoTimestamp())",
            "",
            "Widget: \(widgetURL.lastPathComponent)",
            "Display Name: \(parsed.displayName)",
            "Bundle Identifier: \(parsed.bundleIdentifier)",
            "Version: \(parsed.version)",
            "",
            "Entry Point: \(parsed.mainHTML)",
            "Window Size: \(width)x\(height)",
            "",
            "Export Formats Available: zip, webarchive",
            "Support Directory Source: \(supportDirectoryPath)",
            "Injected Scripts: DashboardAPI.js, WidgetShims.js, SystemInject.js, ExportRuntime.js",
            "",
            "Logs:",
            logLines.isEmpty ? "(none)" : logLines.joined(separator: "\n")
        ]

        let infoURL = folder.appendingPathComponent("info.txt")
        do {
            try lines.joined(separator: "\n").write(to: infoURL, atomically: true, encoding: .utf8)
        } catch {
            throw WidgetExportError.fileOperationFailed("Failed to write info.txt: \(error.localizedDescription)")
        }
    }

    private static func patchWidgetFilesForExport(in folder: URL, mainHTMLPath: String) throws {
        let fm = FileManager.default
        let allowedExtensions = Set(["html", "js", "css"])
        let supportDirectoryURL = folder.appendingPathComponent("SupportDirectory", isDirectory: true)
        let mainDocumentDirectory = folder.appendingPathComponent(mainHTMLPath).deletingLastPathComponent()
        let supportPathForDocument = relativePath(
            fromDirectory: mainDocumentDirectory,
            toDirectory: supportDirectoryURL
        )
        let rootPathForDocument = relativePath(
            fromDirectory: mainDocumentDirectory,
            toDirectory: folder
        )
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil) else {
            throw WidgetExportError.fileOperationFailed("Failed to enumerate export folder.")
        }

        for case let fileURL as URL in enumerator {
            guard allowedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            if fileURL.path.contains(".lproj/") { continue }
            if ExportPathRules.shouldSkipExportedPath(fileURL, root: folder) { continue }

            do {
                let original = try String(contentsOf: fileURL, encoding: .utf8)
                var content = original
                let supportPathForFile = supportPathForDocument

                content = content.replacingOccurrences(
                    of: "file:///System/Library/WidgetResources",
                    with: supportPathForFile
                )
                content = content.replacingOccurrences(
                    of: "/System/Library/WidgetResources",
                    with: supportPathForFile
                )
                content = content.replacingOccurrences(
                    of: #"file:///Users/.+?/SupportDirectory"#,
                    with: supportPathForFile,
                    options: .regularExpression
                )
                content = content.replacingOccurrences(
                    of: #"/Users/.+?/SupportDirectory"#,
                    with: supportPathForFile,
                    options: .regularExpression
                )
                content = content.replacingOccurrences(
                    of: #"file://~/SupportDirectory"#,
                    with: supportPathForFile,
                    options: .regularExpression
                )
                content = content.replacingOccurrences(
                    of: #"~/SupportDirectory"#,
                    with: supportPathForFile,
                    options: .regularExpression
                )
                content = content.replacingOccurrences(
                    of: "\"AppleClasses",
                    with: "\"\(supportPathForFile)/AppleClasses"
                )
                content = content.replacingOccurrences(
                    of: #"~/Library/Widgets/(?:\\ |[^ ])+\.wdgt(.*)"#,
                    with: "\(rootPathForDocument)$1",
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

    private static func injectRuntimeScriptReferences(rootFolder: URL, in folder: URL, scriptFileNames: [String]) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil) else { return }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "html" else { continue }
            if fileURL.path.contains(".lproj/") { continue }
            if ExportPathRules.shouldSkipExportedPath(fileURL, root: folder) { continue }

            guard var html = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if html.contains("ExportRuntime.js") { continue }

            let prefix = relativePrefix(from: fileURL.deletingLastPathComponent(), toRoot: rootFolder)
            let scriptTags = scriptFileNames.map { "<script src=\"\(prefix)\($0)\"></script>" }

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

    private static func relativePrefix(from directory: URL, toRoot root: URL) -> String {
        let dirPath = directory.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path

        if dirPath == rootPath {
            return "./"
        }

        let expectedPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard dirPath.hasPrefix(expectedPrefix) else {
            return "./"
        }

        let remainder = String(dirPath.dropFirst(expectedPrefix.count))
        if remainder.isEmpty {
            return "./"
        }

        let depth = remainder.split(separator: "/").count
        if depth <= 0 {
            return "./"
        }
        return String(repeating: "../", count: depth)
    }

    private static func relativePath(fromDirectory source: URL, toDirectory target: URL) -> String {
        let src = source.standardizedFileURL.pathComponents
        let dst = target.standardizedFileURL.pathComponents
        var common = 0
        while common < src.count && common < dst.count && src[common] == dst[common] {
            common += 1
        }

        let upCount = max(0, src.count - common)
        let up = String(repeating: "../", count: upCount)
        let downParts = Array(dst.dropFirst(common))
        let down = downParts.joined(separator: "/")

        if up.isEmpty && down.isEmpty {
            return "./"
        }
        if up.isEmpty {
            return "./" + down
        }
        if down.isEmpty {
            return up.hasSuffix("/") ? String(up.dropLast()) : up
        }
        return up + down
    }

    private static func sanitizeExportFolder(at root: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        var toDelete: [URL] = []

        for case let url as URL in enumerator {
            if ExportPathRules.shouldSkipExportedPath(url, root: root) {
                toDelete.append(url)
            }
        }

        let ordered = toDelete.sorted { $0.path.count > $1.path.count }
        for url in ordered {
            try? fm.removeItem(at: url)
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

    private static func isoTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
