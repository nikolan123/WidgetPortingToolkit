//
//  TemplateAboutWindow.swift
//  WidgetPlayerTemplate
//
//  Created by Niko on 25.04.26.
//

import SwiftUI
import AppKit

struct TemplateAboutMetadata {
    let title: String
    let details: String
    let icon: NSImage?
}

enum TemplateAboutMetadataDecoder {
    static func decode(from config: WidgetConfig) -> TemplateAboutMetadata {
        let infoURL = config.widgetRoot.appendingPathComponent("Info.plist")
        let infoDict = NSDictionary(contentsOf: infoURL) as? [String: Any] ?? [:]

        let displayName = stringValue(infoDict["CFBundleDisplayName"])
            ?? stringValue(infoDict["CFBundleName"])
            ?? config.displayName
        let bundleID = stringValue(infoDict["CFBundleIdentifier"]) ?? config.bundleIdentifier
        let shortVersion = stringValue(infoDict["CFBundleShortVersionString"]) ?? "N/A"
        let buildVersion = stringValue(infoDict["CFBundleVersion"]) ?? "N/A"
        let mainHTML = stringValue(infoDict["MainHTML"]) ?? config.entryURL.lastPathComponent
        let allowFullAccess = boolValue(infoDict["AllowFullAccess"])
        let width = formatDimension(infoDict["Width"], fallback: config.width)
        let height = formatDimension(infoDict["Height"], fallback: config.height)
        let installationID = Bundle.main.bundleIdentifier ?? "N/A"
        let details = [
            "Widget Name: \(displayName)",
            "Widget Bundle ID: \(bundleID)",
            "Version: \(shortVersion) (\(buildVersion))",
            "Entry Point: \(mainHTML)",
            "Size: \(width) × \(height)",
            "Allow Full Access: \(allowFullAccess ? "Yes" : "No")",
            "Installation ID: \(installationID)"
        ].joined(separator: "\n")

        return TemplateAboutMetadata(
            title: displayName,
            details: details,
            icon: loadIcon(for: config.widgetRoot, infoDict: infoDict)
        )
    }

    private static func loadIcon(for widgetRoot: URL, infoDict: [String: Any]) -> NSImage? {
        let iconCandidates = [
            stringValue(infoDict["CFBundleIconFile"]),
            "Icon.icns",
            "icon.icns",
            "Icon.png",
            "icon.png",
            "Default.png",
            "Default@2x.png"
        ].compactMap { $0 }

        for iconName in iconCandidates {
            let iconURL = widgetRoot.appendingPathComponent(iconName)
            if let image = NSImage(contentsOf: iconURL) {
                return image
            }
        }
        return NSApp.applicationIconImage
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty {
            return string
        }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return false
    }

    private static func formatDimension(_ raw: Any?, fallback: CGFloat) -> String {
        if let number = raw as? NSNumber {
            return String(Int(CGFloat(truncating: number)))
        }
        if let string = raw as? String {
            let cleaned = string.replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Double(cleaned) {
                return String(Int(value))
            }
        }
        return String(Int(fallback))
    }
}

struct TemplateAboutWindow: View {
    let metadata: TemplateAboutMetadata

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                Image(nsImage: metadata.icon ?? NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 8) {
                    Text(metadata.title)
                        .font(.system(size: 24, weight: .semibold))
                        .lineLimit(2)

                    Text(metadata.details)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
                .overlay(Color(nsColor: NSColor(calibratedRed: 0.83, green: 0.34, blue: 0.78, alpha: 0.35)))

            HStack(spacing: 8) {
                Text("Widget Porting Toolkit")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Link("widgets.nikolan.net", destination: URL(string: "https://widgets.nikolan.net/")!)
                    .font(.system(size: 11, weight: .medium))

                Text("•")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Made by Niko")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
        }
        .frame(width: 700, height: 250)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private var templateAboutWindowController: NSWindowController?

func openTemplateAboutWindow(config: WidgetConfig) {
    let metadata = TemplateAboutMetadataDecoder.decode(from: config)
    let hosting = NSHostingController(rootView: TemplateAboutWindow(metadata: metadata))

    let window = NSWindow(contentViewController: hosting)
    window.title = "About \(metadata.title)"
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.setContentSize(NSSize(width: 700, height: 250))
    window.center()

    let controller = NSWindowController(window: window)
    templateAboutWindowController = controller
    controller.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
}
