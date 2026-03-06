//
//  WidgetTweaks.swift
//  WidgetPortingAPP
//
//  Created by Niko on 8.09.25.
//

import Foundation

struct WidgetTweaks: Codable, Hashable {
    var recreateDashboardAPI: Bool = true
    var injectCSS: Bool = true
    var replaceFileSchemePaths: Bool = true
    var copySupportDirectory: Bool = true
    var fixSelfClosingScriptTags: Bool = true
    var transparentBackground: Bool = true
    var xhrProxyEnabled: Bool = false
    var createBlankLocalizedStrings: Bool = true

    var allowSystemCommands: Bool = true
    var noAskSystemCommands: Bool = false
    
    var useNativeShadow: Bool = false
    
    // Custom window size (nil means use default from Info.plist)
    var customWidth: CGFloat?
    var customHeight: CGFloat?

    static func defaults() -> WidgetTweaks {
        var tweaks = WidgetTweaks()
        // tahoe fucked up the window shadow
        // default to native shadow on 15 and below
        let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if majorVersion >= 26 {
            tweaks.useNativeShadow = false
        } else {
            tweaks.useNativeShadow = true
        }
        return tweaks
    }
}

enum TweaksStore {
    private static func key(for bundleID: String) -> String { "WidgetTweaks::\(bundleID)" }

    static func load(for bundleID: String) -> WidgetTweaks {
        let k = key(for: bundleID)
        guard let data = UserDefaults.standard.data(forKey: k) else { return .defaults() }
        do { return try JSONDecoder().decode(WidgetTweaks.self, from: data) }
        catch { return .defaults() }
    }

    static func save(_ tweaks: WidgetTweaks, for bundleID: String) {
        let k = key(for: bundleID)
        if let data = try? JSONEncoder().encode(tweaks) {
            UserDefaults.standard.set(data, forKey: k)
        }
    }

    static func reset(for bundleID: String) {
        UserDefaults.standard.removeObject(forKey: key(for: bundleID))
    }
}
