//
//  PlistParser.swift
//  WidgetPortingAPP
//
//  Created by Niko on 14.09.25.
//

import Foundation
import CoreGraphics
import ImageIO

struct ParsedInfo {
    let displayName: String
    let bundleIdentifier: String
    let version: String
    let mainHTML: String
    let width: CGFloat
    let height: CGFloat
    let iconURL: URL?
    let languages: [String]
    let closeBoxInsetX: CGFloat
    let closeBoxInsetY: CGFloat
}

func parsePlist(from folderURL: URL, showError: (String) -> Void) -> ParsedInfo? {
    let plistURL = folderURL.appendingPathComponent("Info.plist")

    guard let plistData = try? Data(contentsOf: plistURL) else {
        showError("No Info.plist found in \(folderURL.lastPathComponent).")
        return nil
    }

    guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
        showError("Malformed Info.plist in \(folderURL.lastPathComponent).")
        return nil
    }

    guard let displayName = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String,
          let bundleID = plist["CFBundleIdentifier"] as? String,
          let mainHTML = plist["MainHTML"] as? String else {
        showError("Missing or malformed values in \(folderURL.lastPathComponent)'s Info.plist.")
        return nil
    }

    let version = plist["CFBundleShortVersionString"] as? String ?? "unknown"

    // Try explicit width/height, or fall back to default.png size, or default to 800x600
    let plistWidth = cgFloatValue(plist["Width"])
    let plistHeight = cgFloatValue(plist["Height"])
    let closeBoxInsetX = cgFloatValue(plist["CloseBoxInsetX"]) ?? 15
    let closeBoxInsetY = cgFloatValue(plist["CloseBoxInsetY"]) ?? 15

    let (width, height): (CGFloat, CGFloat) = {
        if plistWidth == nil && plistHeight == nil {
            if let sz = defaultPNGSize(in: folderURL) {
                return (sz.width, sz.height)
            } else {
                return (800, 600)
            }
        } else {
            return (plistWidth ?? 800, plistHeight ?? 600)
        }
    }()

    // Find icon
    let possibleIcons = ["icon.png", "icon.icns"]
    let iconURL = possibleIcons
        .map { folderURL.appendingPathComponent($0) }
        .first { FileManager.default.fileExists(atPath: $0.path) }

    // Find available languages
    let fm = FileManager.default
    let languages = (try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil))?
        .filter { $0.pathExtension == "lproj" }
        .map { $0.deletingPathExtension().lastPathComponent }
        .sorted { lhs, rhs in
            let lhsCap = lhs.first?.isUppercase ?? false
            let rhsCap = rhs.first?.isUppercase ?? false
            if lhsCap == rhsCap {
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            } else {
                return lhsCap && !rhsCap
            }
        } ?? []

    return ParsedInfo(
        displayName: displayName,
        bundleIdentifier: bundleID,
        version: version,
        mainHTML: mainHTML,
        width: width,
        height: height,
        iconURL: iconURL,
        languages: languages,
        closeBoxInsetX: closeBoxInsetX,
        closeBoxInsetY: closeBoxInsetY
    )
}

private func cgFloatValue(_ value: Any?) -> CGFloat? {
    if let value = value as? CGFloat { return value }
    if let value = value as? NSNumber { return CGFloat(truncating: value) }
    if let value = value as? Double { return CGFloat(value) }
    if let value = value as? Int { return CGFloat(value) }
    return nil
}

private func defaultPNGSize(in folder: URL) -> CGSize? {
    let candidates = ["default.png", "Default.png"]
    for name in candidates {
        let url = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
                  let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
                  w > 0, h > 0 else { continue }
            return CGSize(width: w, height: h)
        }
    }
    return nil
}
