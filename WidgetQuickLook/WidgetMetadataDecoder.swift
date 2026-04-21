//
//  PreviewViewController.swift
//  WidgetQuickLook
//
//  Created by Niko on 22.04.26.
//

import Cocoa
import Foundation
import Security

struct WidgetMetadata {
    let title: String
    let status: String
    let details: String
    let icon: NSImage?
}

final class WidgetMetadataDecoder {
    func decode(from url: URL) -> WidgetMetadata {
        let infoURL = url.appendingPathComponent("Info.plist")
        let infoDict = NSDictionary(contentsOf: infoURL) as? [String: Any] ?? [:]

        let displayName = stringValue(infoDict["CFBundleDisplayName"])
            ?? stringValue(infoDict["CFBundleName"])
            ?? url.deletingPathExtension().lastPathComponent
        let bundleID = stringValue(infoDict["CFBundleIdentifier"]) ?? "N/A"
        let shortVersion = stringValue(infoDict["CFBundleShortVersionString"]) ?? "N/A"
        let buildVersion = stringValue(infoDict["CFBundleVersion"]) ?? "N/A"
        let mainHTML = stringValue(infoDict["MainHTML"]) ?? "N/A"
        let allowFullAccess = boolValue(infoDict["AllowFullAccess"])
        let signature = signatureStatus(for: url)
        let packageStatus = packageStatus(for: url, mainHTML: mainHTML)
        let fileSize = packageByteCount(url: url)

        let details = [
            "Name: \(displayName)",
            "Bundle ID: \(bundleID)",
            "Version: \(shortVersion) (\(buildVersion))",
            "Main HTML: \(mainHTML)",
            "Allow Full Access: \(allowFullAccess ? "Yes" : "No")",
            "Package Status: \(packageStatus)",
            "Signature: \(signature)",
            "Size: \(fileSize)"
        ].joined(separator: "\n")

        return WidgetMetadata(
            title: displayName,
            status: "Dashboard Widget Package",
            details: details,
            icon: loadIcon(for: url, infoDict: infoDict)
        )
    }

    private func loadIcon(for url: URL, infoDict: [String: Any]) -> NSImage? {
        let iconCandidates = [
            stringValue(infoDict["CFBundleIconFile"]),
            "Icon.icns",
            "Default.png",
            "Default@2x.png"
        ].compactMap { $0 }

        for iconName in iconCandidates {
            let iconURL = url.appendingPathComponent(iconName)
            if let img = NSImage(contentsOf: iconURL) {
                return img
            }
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func packageStatus(for url: URL, mainHTML: String) -> String {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return "Invalid (not a package directory)"
        }
        let infoExists = FileManager.default.fileExists(atPath: url.appendingPathComponent("Info.plist").path)
        let mainExists = mainHTML != "N/A" && FileManager.default.fileExists(atPath: url.appendingPathComponent(mainHTML).path)
        if infoExists && mainExists {
            return "Valid"
        }
        if infoExists {
            return "Partial (missing MainHTML file)"
        }
        return "Invalid (missing Info.plist)"
    }

    private func signatureStatus(for url: URL) -> String {
        let sigFolder = url.appendingPathComponent("_CodeSignature").path
        let hasSignatureFolder = FileManager.default.fileExists(atPath: sigFolder)

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return hasSignatureFolder ? "Present (unverified)" : "Unsigned"
        }

        let verifyStatus = SecStaticCodeCheckValidity(staticCode, [], nil)
        if verifyStatus == errSecSuccess {
            return "Signed (valid)"
        }
        if hasSignatureFolder {
            return "Signed (invalid: \(verifyStatus))"
        }
        return "Unsigned"
    }

    private func packageByteCount(url: URL) -> String {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "N/A"
        }

        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                totalBytes += Int64(values?.fileSize ?? 0)
            }
        }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty {
            return string
        }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool {
            return b
        }
        if let n = value as? NSNumber {
            return n.boolValue
        }
        return false
    }
}
