//
//  WidgetAppExportBuilder.swift
//  WidgetPortingAPP
//
//  Created by Niko on 24.04.26.
//

import Foundation

enum WidgetAppExportBuilder {
    static func buildAppBundle(
        workDirectory: URL,
        processedWidgetFolder: URL,
        parsed: ParsedInfo,
        outputAppURL: URL
    ) throws {
        let fm = FileManager.default
        let templateAppURL = try resolveTemplateAppURL()

        if fm.fileExists(atPath: outputAppURL.path) {
            try? fm.removeItem(at: outputAppURL)
        }

        do {
            try fm.copyItem(at: templateAppURL, to: outputAppURL)
        } catch {
            throw WidgetExportError.fileOperationFailed("Failed to copy template app: \(error.localizedDescription)")
        }

        let contentsURL = outputAppURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let widgetDestination = resourcesURL.appendingPathComponent("widget", isDirectory: true)

        do {
            if fm.fileExists(atPath: widgetDestination.path) {
                try fm.removeItem(at: widgetDestination)
            }
            try fm.copyItem(at: processedWidgetFolder, to: widgetDestination)
        } catch {
            throw WidgetExportError.fileOperationFailed("Failed to copy widget payload into app bundle: \(error.localizedDescription)")
        }

        let displayName = parsed.displayName.isEmpty ? parsed.bundleIdentifier : parsed.displayName
        let generatedBundleID = buildExportBundleIdentifier(from: parsed.bundleIdentifier, fallbackName: displayName)

        let plistURL = contentsURL.appendingPathComponent("Info.plist")
        try patchAppPlist(
            at: plistURL,
            displayName: displayName,
            bundleIdentifier: generatedBundleID,
            iconConfigured: configureAppIcon(from: processedWidgetFolder, resourcesURL: resourcesURL, workDirectory: workDirectory)
        )

        try removeQuarantineAttribute(from: outputAppURL)
        try adHocSignAppBundle(at: outputAppURL)
    }

    private static func resolveTemplateAppURL() throws -> URL {
        let bundle = Bundle.main
        let siblingURL = bundle.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("WidgetPlayerTemplate.app", isDirectory: true)
        let candidates: [URL?] = [
            bundle.url(forResource: "WidgetPlayerTemplate", withExtension: "app"),
            bundle.url(forResource: "WidgetPlayerTemplate", withExtension: "app", subdirectory: "Templates"),
            bundle.resourceURL?.appendingPathComponent("WidgetPlayerTemplate.app", isDirectory: true),
            siblingURL
        ]

        for candidate in candidates {
            guard let url = candidate else { continue }
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        throw WidgetExportError.fileOperationFailed(
            "Missing WidgetPlayerTemplate.app. Build the WidgetPlayerTemplate target and ensure the app template is available beside or inside the main app bundle."
        )
    }

    private static func patchAppPlist(
        at plistURL: URL,
        displayName: String,
        bundleIdentifier: String,
        iconConfigured: Bool
    ) throws {
        let plistData: Data
        do {
            plistData = try Data(contentsOf: plistURL)
        } catch {
            throw WidgetExportError.fileOperationFailed("Failed to read app Info.plist: \(error.localizedDescription)")
        }

        var format = PropertyListSerialization.PropertyListFormat.xml
        guard var plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: &format) as? [String: Any] else {
            throw WidgetExportError.fileOperationFailed("App Info.plist has invalid format.")
        }

        plist["CFBundleDisplayName"] = displayName
        plist["CFBundleName"] = displayName
        plist["CFBundleIdentifier"] = bundleIdentifier
        if iconConfigured {
            plist["CFBundleIconFile"] = "AppIcon"
        }

        do {
            let outputData = try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
            try outputData.write(to: plistURL)
        } catch {
            throw WidgetExportError.fileOperationFailed("Failed to write patched app Info.plist: \(error.localizedDescription)")
        }
    }

    private static func buildExportBundleIdentifier(from original: String, fallbackName: String) -> String {
        let base = original.isEmpty ? fallbackName : original
        let lower = base.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        let sanitized = String(lower.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character(".") })
            .replacingOccurrences(of: "\\.+", with: ".", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        let core = sanitized.isEmpty ? "widget" : sanitized
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8)
        return "net.nikolan.widgetexport.\(core).\(suffix)"
    }

    private static func configureAppIcon(from widgetFolder: URL, resourcesURL: URL, workDirectory: URL) -> Bool {
        let fm = FileManager.default
        let icnsCandidates = [
            widgetFolder.appendingPathComponent("Icon.icns"),
            widgetFolder.appendingPathComponent("icon.icns")
        ]
        for candidate in icnsCandidates where fm.fileExists(atPath: candidate.path) {
            let outURL = resourcesURL.appendingPathComponent("AppIcon.icns")
            do {
                if fm.fileExists(atPath: outURL.path) { try fm.removeItem(at: outURL) }
                try fm.copyItem(at: candidate, to: outURL)
                return true
            } catch {
                continue
            }
        }

        let pngCandidates = [
            widgetFolder.appendingPathComponent("Icon.png"),
            widgetFolder.appendingPathComponent("icon.png"),
            widgetFolder.appendingPathComponent("Default.png"),
            widgetFolder.appendingPathComponent("default.png")
        ]
        guard let sourceImage = pngCandidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
            return false
        }

        let iconsetURL = workDirectory.appendingPathComponent("WidgetAppIcon.iconset", isDirectory: true)
        try? fm.removeItem(at: iconsetURL)
        do {
            try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
        } catch {
            return false
        }

        let sizes: [(Int, String)] = [
            (16, "icon_16x16.png"),
            (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),
            (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"),
            (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"),
            (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"),
            (1024, "icon_512x512@2x.png")
        ]

        for (size, fileName) in sizes {
            let output = iconsetURL.appendingPathComponent(fileName)
            guard runTool(
                executable: "/usr/bin/sips",
                arguments: ["-s", "format", "png", "-z", "\(size)", "\(size)", sourceImage.path, "--out", output.path]
            ) else {
                return false
            }
        }

        let outIcns = resourcesURL.appendingPathComponent("AppIcon.icns")
        try? fm.removeItem(at: outIcns)
        guard runTool(
            executable: "/usr/bin/iconutil",
            arguments: ["-c", "icns", iconsetURL.path, "-o", outIcns.path]
        ) else {
            return false
        }
        return fm.fileExists(atPath: outIcns.path)
    }

    private static func runTool(executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        return process.terminationStatus == 0
    }

    private static func removeQuarantineAttribute(from appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-r", "-d", "com.apple.quarantine", appURL.path]
        let stderr = Pipe()
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw WidgetExportError.fileOperationFailed("Failed to start xattr: \(error.localizedDescription)")
        }

        if process.terminationStatus == 0 {
            return
        }

        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8) ?? ""
        if errorText.contains("No such xattr") {
            return
        }

        throw WidgetExportError.fileOperationFailed("xattr failed with status \(process.terminationStatus): \(errorText)")
    }

    private static func adHocSignAppBundle(at appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--deep", "--sign", "-", appURL.path]
        let stderr = Pipe()
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw WidgetExportError.fileOperationFailed("Failed to start codesign: \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? "unknown error"
            throw WidgetExportError.fileOperationFailed("codesign failed with status \(process.terminationStatus): \(errorText)")
        }
    }
}
