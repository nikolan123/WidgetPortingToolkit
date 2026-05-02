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

    @Published var emulateDashboardControlRegions: Bool { didSet { save() } }
    @Published var allowSystemCommands: Bool { didSet { save() } }
    @Published var noAskSystemCommands: Bool { didSet { save() } }
    @Published var injectCSS: Bool { didSet { save() } }
    @Published var transparentBackground: Bool { didSet { save() } }
    @Published var useNativeShadow: Bool { didSet { save() } }
    @Published var alwaysOnTop: Bool { didSet { save() } }
    @Published var hideTitlebar: Bool { didSet { save() } }

    private let defaultsKey = "WidgetPlayerTemplate.RuntimeSettings"
    private var isReady = false

    private init() {
        let raw = UserDefaults.standard.dictionary(forKey: defaultsKey) ?? [:]

        func bool(_ key: String, default fallback: Bool) -> Bool {
            if let value = raw[key] as? Bool { return value }
            if let value = raw[key] as? NSNumber { return value.boolValue }
            return fallback
        }

        self.emulateDashboardControlRegions = bool("emulateDashboardControlRegions", default: true)
        self.allowSystemCommands = bool("allowSystemCommands", default: true)
        self.noAskSystemCommands = bool("noAskSystemCommands", default: false)
        self.injectCSS = bool("injectCSS", default: true)
        self.transparentBackground = bool("transparentBackground", default: true)
        self.useNativeShadow = bool("useNativeShadow", default: Self.defaultUseNativeShadow())
        self.alwaysOnTop = bool("alwaysOnTop", default: false)
        self.hideTitlebar = bool("hideTitlebar", default: true)

        isReady = true
    }

    private static func defaultUseNativeShadow() -> Bool {
        // tahoe fucked up the window shadow
        // default to native shadow on 15 and below
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26
    }

    private func save() {
        guard isReady else { return }
        let raw: [String: Any] = [
            "emulateDashboardControlRegions": emulateDashboardControlRegions,
            "allowSystemCommands": allowSystemCommands,
            "noAskSystemCommands": noAskSystemCommands,
            "injectCSS": injectCSS,
            "transparentBackground": transparentBackground,
            "useNativeShadow": useNativeShadow,
            "alwaysOnTop": alwaysOnTop,
            "hideTitlebar": hideTitlebar
        ]
        UserDefaults.standard.set(raw, forKey: defaultsKey)
    }
}
