//
//  TemplateRuntimeSettings.swift
//  WidgetPlayerTemplate
//
//  Created by Niko on 25.04.26.
//

import Foundation
import Combine

final class TemplateRuntimeSettings: ObservableObject {
    static let shared = TemplateRuntimeSettings()

    @Published var recreateDashboardAPI: Bool = true { didSet { saveIfReady() } }
    @Published var allowSystemCommands: Bool = true { didSet { saveIfReady() } }
    @Published var noAskSystemCommands: Bool = false { didSet { saveIfReady() } }
    @Published var injectCSS: Bool = true { didSet { saveIfReady() } }
    @Published var transparentBackground: Bool = true { didSet { saveIfReady() } }
    @Published var useNativeShadow: Bool = TemplateRuntimeSettings.defaultUseNativeShadow() { didSet { saveIfReady() } }
    @Published var alwaysOnTop: Bool = false { didSet { saveIfReady() } }
    @Published var hideTitlebar: Bool = false { didSet { saveIfReady() } }

    private let fileManager: FileManager
    private let legacyDefaultsKey = "WidgetPlayerTemplate.RuntimeSettings"
    private var isReady = false

    private struct PersistedSettings: Codable {
        var recreateDashboardAPI: Bool
        var allowSystemCommands: Bool
        var noAskSystemCommands: Bool
        var injectCSS: Bool
        var transparentBackground: Bool
        var useNativeShadow: Bool
        var alwaysOnTop: Bool
        var hideTitlebar: Bool
    }

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let loaded = loadPersistedSettings() ?? migrateLegacySettings() ?? PersistedSettings(
            recreateDashboardAPI: true,
            allowSystemCommands: true,
            noAskSystemCommands: false,
            injectCSS: true,
            transparentBackground: true,
            useNativeShadow: Self.defaultUseNativeShadow(),
            alwaysOnTop: false,
            hideTitlebar: false
        )

        recreateDashboardAPI = loaded.recreateDashboardAPI
        allowSystemCommands = loaded.allowSystemCommands
        noAskSystemCommands = loaded.noAskSystemCommands
        injectCSS = loaded.injectCSS
        transparentBackground = loaded.transparentBackground
        useNativeShadow = loaded.useNativeShadow
        alwaysOnTop = loaded.alwaysOnTop
        hideTitlebar = loaded.hideTitlebar

        isReady = true
        save()
    }

    private static func defaultUseNativeShadow() -> Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26
    }

    private var storageURL: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.niko.WidgetPlayerTemplate"
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("RuntimeSettings.json", isDirectory: false)
    }

    private func loadPersistedSettings() -> PersistedSettings? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        return try? JSONDecoder().decode(PersistedSettings.self, from: data)
    }

    private func migrateLegacySettings() -> PersistedSettings? {
        guard let raw = UserDefaults.standard.dictionary(forKey: legacyDefaultsKey) else { return nil }

        func bool(_ key: String, default fallback: Bool) -> Bool {
            if let value = raw[key] as? Bool { return value }
            if let value = raw[key] as? NSNumber { return value.boolValue }
            return fallback
        }

        let migrated = PersistedSettings(
            recreateDashboardAPI: bool("recreateDashboardAPI", default: true),
            allowSystemCommands: bool("allowSystemCommands", default: true),
            noAskSystemCommands: bool("noAskSystemCommands", default: false),
            injectCSS: bool("injectCSS", default: true),
            transparentBackground: bool("transparentBackground", default: true),
            useNativeShadow: bool("useNativeShadow", default: Self.defaultUseNativeShadow()),
            alwaysOnTop: bool("alwaysOnTop", default: false),
            hideTitlebar: bool("hideTitlebar", default: false)
        )

        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        return migrated
    }

    private func saveIfReady() {
        guard isReady else { return }
        save()
    }

    private func save() {
        let settings = PersistedSettings(
            recreateDashboardAPI: recreateDashboardAPI,
            allowSystemCommands: allowSystemCommands,
            noAskSystemCommands: noAskSystemCommands,
            injectCSS: injectCSS,
            transparentBackground: transparentBackground,
            useNativeShadow: useNativeShadow,
            alwaysOnTop: alwaysOnTop,
            hideTitlebar: hideTitlebar
        )

        guard let data = try? JSONEncoder().encode(settings) else { return }
        let folderURL = storageURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try? data.write(to: storageURL, options: .atomic)
    }
}
