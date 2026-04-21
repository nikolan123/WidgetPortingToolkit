//
//  Logic.swift
//  WidgetPortingAPP
//
//  Created by Niko on 8.09.25.
//

import SwiftUI
import ImageIO

// MARK: - BorderlessKeyWindow
class BorderlessKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let openCustomWindow = Notification.Name("openCustomWindow")
    static let resizeCustomWindow = Notification.Name("resizeCustomWindow")
}

fileprivate var openWindows: [NSWindow] = []
fileprivate var overlayControllers: [String: WidgetOverlayController] = [:]
fileprivate var globalFlagsMonitor: Any?
fileprivate var globalKeyMonitor: Any?

// Centralized Option key monitor
fileprivate func setupGlobalOverlayMonitor() {
    if globalFlagsMonitor == nil {
        globalFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let optionHeld = event.modifierFlags.contains(.option)
            
            // Find key window and toggle its overlay
            if let keyWindow = NSApp.keyWindow,
               let windowId = keyWindow.identifier?.rawValue,
               let controller = overlayControllers[windowId] {
                controller.handleOptionKey(held: optionHeld)
            }
            
            return event
        }
    }
    
    // Cmd+W monitor for closing widget windows
    if globalKeyMonitor == nil {
        globalKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Check for Cmd+W (keyCode 13 = W)
            if event.modifierFlags.contains(.command) && event.keyCode == 13 {
                if let keyWindow = NSApp.keyWindow,
                   let windowId = keyWindow.identifier?.rawValue,
                   overlayControllers[windowId] != nil {
                    // This is one of our widget windows
                    keyWindow.close()
                    return nil // Consume the event
                }
            }
            return event
        }
    }
}

// Cleanup global monitors when no overlays remain
fileprivate func cleanupGlobalOverlayMonitorIfNeeded() {
    if overlayControllers.isEmpty {
        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
    }
}

// MARK: - AppInfo
struct AppInfo: Identifiable, Hashable {
    let id: String
    let displayName: String
    let bundleIdentifier: String
    let version: String
    let htmlURL: URL
    let tempFolder: URL
    let installedFolder: URL
    let width: CGFloat
    let height: CGFloat
    let iconURL: URL?
    let languages: [String]
}

// MARK: - ViewModel
@MainActor
class WidgetManager: ObservableObject {
    @AppStorage("supportDirectoryPath") var supportDirectoryPath: String = ""
    @AppStorage("defaultWidgetLanguage") var defaultWidgetLanguage: String = ""
    @AppStorage("silentMode") var silentMode = false
    @AppStorage("autoOpenWidgetOnInstall") var autoOpenWidgetOnInstall = true
    @AppStorage("portableMode") var portableMode = false
    @AppStorage("borderlessFullScreenWidgets") var borderlessFullScreenWidgets: Bool = true
    @AppStorage("allowMultipleInstances") var allowMultipleInstances: Bool = false
    @Published var appInfos: [AppInfo] = []
    @Published var selectedLanguages: [String: String] = [:]
    @Published private(set) var tweaksPerBundle: [String: WidgetTweaks] = [:]
    private(set) var initialLoadComplete = false
    
    // MARK: - Loading progress properties
    @Published var currentLoadingWidgetName: String? = nil // The name of the widget currently loading
    @Published var loadingProgressNumerator: Int = 0       // Number of widgets loaded so far
    @Published var loadingProgressDenominator: Int = 0     // Total number of widgets to load
    private var loadingWindow: NSWindow? = nil             // Reference to the loading progress window

    init() {
        // make sure as base exists
        do {
            try FileManager.default.createDirectory(at: Self.applicationSupportBaseURL(), withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(at: Self.installedWidgetsDirectoryURL(), withIntermediateDirectories: true, attributes: nil)
        } catch {
            showError("Failed to create app support directories: \(error.localizedDescription)")
        }

        // If user previously installed support dir into App Support, prefer that
        let installedSupport = Self.installedSupportDirectoryURL()
        if FileManager.default.fileExists(atPath: installedSupport.path) {
            supportDirectoryPath = installedSupport.path
        }
        
        // Load persisted language selections
        loadSelectedLanguages()
    }
    
    @MainActor
    func startupLoadAsync() async {
        guard !initialLoadComplete else { return }
        initialLoadComplete = true

        let fm = FileManager.default
        let installedDir = Self.installedWidgetsDirectoryURL()
        guard let entries = try? fm.contentsOfDirectory(at: installedDir,
                                                       includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles]) else {
            return
        }

        loadingProgressNumerator = 0
        loadingProgressDenominator = entries.count
        currentLoadingWidgetName = nil

        for entry in entries {
            guard FileManager.default.fileExists(atPath: entry.appendingPathComponent("Info.plist").path) else { continue }

            var displayName: String = entry.lastPathComponent
            if let plistData = try? Data(contentsOf: entry.appendingPathComponent("Info.plist")),
               let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
               let name = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String {
                displayName = name
            }

            currentLoadingWidgetName = displayName
            if let uuidSubstring = entry.lastPathComponent.split(separator: "_").last {
                let uuid = String(uuidSubstring)
                loadWidget(from: entry, openWindow: false, id: uuid)
            }

            loadingProgressNumerator += 1
            await Task.yield()
        }

        currentLoadingWidgetName = nil
    }

    // MARK: - Language persistence
    func setLanguage(for key: String, language: String?) {
        selectedLanguages[key] = language
        saveSelectedLanguages()
    }
    
    private func saveSelectedLanguages() {
        if let data = try? JSONEncoder().encode(selectedLanguages) {
            UserDefaults.standard.set(data, forKey: "selectedLanguages")
        }
    }
    
    private func loadSelectedLanguages() {
        if let data = UserDefaults.standard.data(forKey: "selectedLanguages"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            selectedLanguages = decoded
        }
    }
    
    // MARK: - Tweaks helpers
    func tweaks(for bundleID: String, id: String) -> WidgetTweaks {
        let key = "\(bundleID)_\(id)"
        if let existing = tweaksPerBundle[key] { return existing }
        let loaded = TweaksStore.load(for: key)
        tweaksPerBundle[key] = loaded
        return loaded
    }
    // update tweaks
    func updateTweaks(for bundleID: String, id: String, to newTweaks: WidgetTweaks) {
        let key = "\(bundleID)_\(id)"
        tweaksPerBundle[key] = newTweaks
        TweaksStore.save(newTweaks, for: key)
    }
    // reset tweaks
    func resetTweaks(for bundleID: String, id: String) {
        let key = "\(bundleID)_\(id)"
        TweaksStore.reset(for: key)
        let defaults = WidgetTweaks.defaults()
        tweaksPerBundle[key] = defaults
        TweaksStore.save(defaults, for: key)
    }

    // MARK: - Installed locations
    static func applicationSupportBaseURL() -> URL {
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let bundle = Bundle.main.bundleIdentifier ?? "WidgetPortingAPP"
            return appSupport.appendingPathComponent(bundle, isDirectory: true)
        } else {
            // fallback to home/Library/Application Support/WidgetPortingAPP
            let home = URL(fileURLWithPath: NSHomeDirectory())
            return home.appendingPathComponent("Library/Application Support/\(Bundle.main.bundleIdentifier ?? "WidgetPortingAPP")", isDirectory: true)
        }
    }

    static func installedSupportDirectoryURL() -> URL {
        return applicationSupportBaseURL().appendingPathComponent("SupportDirectory", isDirectory: true)
    }

    static func installedWidgetsDirectoryURL() -> URL {
        return applicationSupportBaseURL().appendingPathComponent("InstalledWidgets", isDirectory: true)
    }

    // copy support directory into as
    func installSupportDirectory(from url: URL) -> URL? {
        let dest = Self.installedSupportDirectoryURL()
        let fm = FileManager.default
        do {
            // remove old if present
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: url, to: dest)
            supportDirectoryPath = dest.path
            return dest
        } catch {
            showError("Failed to install Support Directory: \(error.localizedDescription)")
            return nil
        }
    }

    // copy a widget into InstalledWidgets
    func installWidget(from folderURL: URL, id: String = String(UUID().uuidString.prefix(8))) -> (URL, String)? {
        // try to read bundle id from Info.plist
        let plistURL = folderURL.appendingPathComponent("Info.plist")
        var destName = folderURL.lastPathComponent
        var bundleID: String?

        if let plistData = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
           let bid = plist["CFBundleIdentifier"] as? String {
            bundleID = bid
            destName = bid
        } else {
            // no fallback because plist parsing will fail anyways
            showError("Missing Bundle ID in Info.plist.")
            
        }
        
        destName += "_\(id)"

        let dest = Self.installedWidgetsDirectoryURL().appendingPathComponent(destName, isDirectory: true)
        let fm = FileManager.default

        // ask user to replace if already exists unless sm
        if fm.fileExists(atPath: dest.path) {
            var shouldReplace = true

            if !silentMode {
                let alert = NSAlert()
                alert.messageText = "Widget Already Installed"
                alert.informativeText = "A widget with the same identifier (\(bundleID ?? destName)) is already installed. Do you want to replace it?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Replace")
                alert.addButton(withTitle: "Cancel")
                let response = alert.runModal()
                shouldReplace = (response == .alertFirstButtonReturn)
            }

            if shouldReplace {
                do {
                    try fm.removeItem(at: dest)
                } catch {
                    showError("Failed to remove old widget: \(error.localizedDescription)")
                    return nil
                }
            } else {
                return nil
            }
        }

        do {
            try fm.copyItem(at: folderURL, to: dest)
            return (dest, id)
        } catch {
            showError("Failed to install widget \(folderURL.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
    
    func openInstallWindow(with info: ParsedInfo, folderURL: URL) {
        var window: NSWindow? = nil
        let windowState = Binding<NSWindow?>(
            get: { window },
            set: { window = $0 }
        )

        let installView = InstallWindow(
            parsedInfo: info,
            folderURL: folderURL,
            windowRef: windowState
        )
        .environmentObject(self)

        let hosting = NSHostingController(rootView: installView)

        let newWindow = NSWindow(contentViewController: hosting)
        window = newWindow

        newWindow.title = "Install Widget"
        newWindow.setContentSize(NSSize(width: 400, height: 150))
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        newWindow.level = .floating
    }
    
    func openDefaultLanguageSetting() {
        let popupView = DefaultLanguagePopup()
        let hosting = NSHostingController(rootView: popupView)

        let window = NSWindow(contentViewController: hosting)
        window.title = "Default Language"
        window.center()
        window.setContentSize(NSSize(width: 300, height: 100))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.makeKeyAndOrderFront(nil)
        window.level = .floating
    }
    
    func handleOpenedWidgetURL(_ folderURL: URL) {
        guard folderURL.lastPathComponent != "-NSDocumentRevisionsDebugMode" else { return } // xcode temp dir
        guard folderURL.pathExtension.lowercased() == "wdgt" else { return }
        
        if silentMode {
            if portableMode {
                loadWidget(from: folderURL, openWindow: autoOpenWidgetOnInstall)
            } else if let (dest, shortUUID) = installWidget(from: folderURL) {
                loadWidget(from: dest, openWindow: autoOpenWidgetOnInstall, id: shortUUID)
            }
        } else if let info = parsePlist(from: folderURL, showError: showError) {
            openInstallWindow(with: info, folderURL: folderURL)
        }
    }

    // MARK: - Drop handling
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let folderURL = URL(dataRepresentation: data, relativeTo: nil) else { return }

                    Task { @MainActor in
                        self.handleOpenedWidgetURL(folderURL)
                    }
                }
                handled = true
            }
        }
        return handled
    }

    // support dir browser, for menu bar
    func browseAndInstallSupportDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            _ = installSupportDirectory(from: url)
        }
    }
    
    func remove(_ appInfo: AppInfo) {
        let fm = FileManager.default
        // first remove temp folder
        try? fm.removeItem(at: appInfo.tempFolder)
        // second remove installed folder if in installed dir
        if appInfo.installedFolder.path.hasPrefix(Self.installedWidgetsDirectoryURL().path) {
            try? fm.removeItem(at: appInfo.installedFolder)
        }
        // third reset tweaks and prefs
        self.resetTweaks(for: appInfo.bundleIdentifier, id: appInfo.id)
        self.clearPreferences(for: appInfo)
        appInfos.removeAll { $0.id == appInfo.id }
    }
    
    func duplicate(_ appInfo: AppInfo) {
        let newId = String(UUID().uuidString.prefix(8))
        let fm = FileManager.default

        // copy and stuff
        let originalFolder = appInfo.installedFolder
        let destFolder = Self.installedWidgetsDirectoryURL().appendingPathComponent("\(appInfo.bundleIdentifier)_\(newId)", isDirectory: true)

        do {
            try fm.copyItem(at: originalFolder, to: destFolder)
        } catch {
            showError("Failed to duplicate widget folder: \(error.localizedDescription)")
            return
        }

        // duplicate tweaks
        let oldKey = "\(appInfo.bundleIdentifier)_\(appInfo.id)"
        let newKey = "\(appInfo.bundleIdentifier)_\(newId)"
        if let oldTweaks = tweaksPerBundle[oldKey] {
            tweaksPerBundle[newKey] = oldTweaks
            TweaksStore.save(oldTweaks, for: newKey)
        }

        loadWidget(from: destFolder, openWindow: false, id: newId)
    }

    // Preprocess
    private func preprocessFolder(_ folder: URL, bundleID: String, id: String, tweaks: WidgetTweaks) -> URL? {
        guard !supportDirectoryPath.isEmpty else {
            showError("No Support Directory set. Please select one (Options > Install Support Directory) before loading a widget.")
            return nil
        }
        // make temp dir
        let fm = FileManager.default
        let tempFolderName = "\(bundleID)_\(id)"
        let tempFolder = fm.temporaryDirectory.appendingPathComponent(tempFolderName)
        try? fm.removeItem(at: tempFolder)
        do { try fm.copyItem(at: folder, to: tempFolder) }
        catch {
            showError("Failed to copy \(bundleID)'s folder to temporary location: \(error.localizedDescription)")
            return nil
        }

        // Determine the support directory source (widgetresources)
        let installedSupportURL = URL(fileURLWithPath: supportDirectoryPath)

        // copy if requested
        var supportPathForReplacement = installedSupportURL.path
        if tweaks.copySupportDirectory {
            let tempSupportDir = tempFolder.appendingPathComponent("SupportDirectory")
            do {
                if fm.fileExists(atPath: tempSupportDir.path) {
                    try fm.removeItem(at: tempSupportDir)
                }
                try fm.copyItem(at: installedSupportURL, to: tempSupportDir)
                supportPathForReplacement = tempSupportDir.path
            } catch {
                showError("Failed to copy Support Directory into \(bundleID): \(error.localizedDescription)")
                return nil
            }
        }

        // go thru each html,js,css and replace hardcoded library dir
        let allowedExtensions = ["html", "js", "css"]
        let fileEnumerator = fm.enumerator(at: tempFolder, includingPropertiesForKeys: nil)!

        for case let fileURL as URL in fileEnumerator where allowedExtensions.contains(fileURL.pathExtension.lowercased()) {
            // localized files make it error
            if fileURL.path.contains(".lproj/") {
                continue
            }
            do {
                var content = try String(contentsOf: fileURL, encoding: .utf8)

                if tweaks.replaceFileSchemePaths {
                    content = content.replacingOccurrences(
                        of: "file:///System/Library/WidgetResources",
                        with: "file://\(supportPathForReplacement)"
                    )
                    content = content.replacingOccurrences(
                        of: "/System/Library/WidgetResources",
                        with: "file://\(supportPathForReplacement)"
                    )
                    content = content.replacingOccurrences(
                        of: "\"AppleClasses",
                        with: "\"file://\(supportPathForReplacement)/AppleClasses"
                    )
                    // replace ~/Library/Widgets/[^ ]+\.wdgt with widget's new path
                    let pattern = #"~/Library/Widgets/(?:\\ |[^ ])+\.wdgt(.*)"#
                    content = content.replacingOccurrences(
                        of: pattern,
                        with: "file://\(tempFolder.path)$1",
                        options: .regularExpression
                    )
                }

                if tweaks.fixSelfClosingScriptTags {
                    // fix self-closing script tags
                    let scriptPattern = #"<script([^>]*)\/>"#
                    content = content.replacingOccurrences(
                        of: scriptPattern,
                        with: "<script$1></script>",
                        options: .regularExpression
                    )
                }

                let original = try String(contentsOf: fileURL, encoding: .utf8)
                if content != original {
                    try content.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            } catch {
                print("Failed to process file \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        if tweaks.createBlankLocalizedStrings {
            let localizedFile = tempFolder.appendingPathComponent("localizedStrings.js")
            if !fm.fileExists(atPath: localizedFile.path) {
                let stub = "var localizedStrings = {};"
                try? stub.write(to: localizedFile, atomically: true, encoding: .utf8)
            }
        }

        return tempFolder
    }

    // widget loader
    func loadWidget(
        from folderURL: URL,
        openWindow: Bool = true,
        plistInfo: ParsedInfo? = nil,
        id: String = String(UUID().uuidString.prefix(8))
    ) {
        let info = plistInfo ?? parsePlist(from: folderURL, showError: showError)
        guard let plistInfo = info else { return }

        let tweaks = self.tweaks(for: plistInfo.bundleIdentifier, id: id)

        guard let processedFolder = preprocessFolder(folderURL, bundleID: plistInfo.bundleIdentifier, id: id, tweaks: tweaks) else {
            return
        }

        let htmlFileURL = processedFolder.appendingPathComponent(plistInfo.mainHTML)
        guard FileManager.default.fileExists(atPath: htmlFileURL.path) else {
            showError("Main HTML file “\(plistInfo.mainHTML)” not found for “\(plistInfo.displayName)”.")
            return
        }

        let newAppInfo = AppInfo(
            id: id,
            displayName: plistInfo.displayName,
            bundleIdentifier: plistInfo.bundleIdentifier,
            version: plistInfo.version,
            htmlURL: htmlFileURL,
            tempFolder: processedFolder,
            installedFolder: folderURL,
            width: plistInfo.width,
            height: plistInfo.height,
            iconURL: plistInfo.iconURL.map { processedFolder.appendingPathComponent($0.lastPathComponent) },
            languages: plistInfo.languages
        )

        appInfos.append(newAppInfo)
        
        // Check if there's a saved language selection first
        let langKey = newAppInfo.bundleIdentifier + "_" + newAppInfo.id
        if selectedLanguages[langKey] != nil {
            // Already have a saved language, use it
            if let savedLang = selectedLanguages[langKey] {
                prepareLanguage(for: newAppInfo, language: savedLang)
            }
        } else {
            // No saved language, try to use the global default
            if let matchedLang = newAppInfo.languages.first(where: { $0.caseInsensitiveCompare(defaultWidgetLanguage) == .orderedSame }) {
                prepareLanguage(for: newAppInfo, language: matchedLang)
                setLanguage(for: langKey, language: matchedLang)
            }
            // if no language is selected the key won't exist
        }

        if openWindow {
            openHTMLWindow(appInfo: newAppInfo)
        }
    }

    // Language prep
    func prepareLanguage(for appInfo: AppInfo, language: String?) {
        // find language.lproj and copy its localizedStrings.js to temp folder root
        let fm = FileManager.default
        let destFile = appInfo.tempFolder.appendingPathComponent("localizedStrings.js")

        try? fm.removeItem(at: destFile)
        
        if let language = language {
            let langFolder = appInfo.tempFolder.appendingPathComponent("\(language).lproj")
            let sourceFile = langFolder.appendingPathComponent("localizedStrings.js")
            if fm.fileExists(atPath: sourceFile.path) {
                try? fm.copyItem(at: sourceFile, to: destFile)
            }
        }
    }

    // Window handling
    func openHTMLWindow(appInfo: AppInfo) {
        let tweaks = self.tweaks(for: appInfo.bundleIdentifier, id: appInfo.id)
        let windowIdentifier = appInfo.bundleIdentifier + "_" + appInfo.id
        
        if !allowMultipleInstances {
            // Check regular windows
            let existingRegularWindow = openWindows.first(where: { $0.identifier?.rawValue == windowIdentifier })
            
            if existingRegularWindow != nil {
                showDuplicateWindowWarning(for: appInfo)
                return
            }
        }
        
        // Use custom size if saved, otherwise use default from Info.plist
        let width = tweaks.customWidth ?? appInfo.width
        let height = tweaks.customHeight ?? appInfo.height
        
        // Check if any ContentView window is in fullscreen
        let isAnyContentViewInFullscreen = NSApp.windows.contains(where: { window in
            (window.title == "Widget Porting Toolkit" || window.contentViewController is NSHostingController<AppRootView>) 
            && window.styleMask.contains(.fullScreen)
        })

        // If any ContentView is in fullscreen, use custom window system
        if isAnyContentViewInFullscreen {
            NotificationCenter.default.post(
                name: .openCustomWindow,
                object: nil,
                userInfo: ["appInfo": appInfo, "tweaks": tweaks, "width": width, "height": height]
            )
            return
        }
        
        // Otherwise use regular NSWindow
        let hosting = NSHostingController(rootView: WebView(appInfo: appInfo, tweaks: tweaks))
        let contentRect = NSRect(x: 0, y: 0, width: width, height: height)
        
        let styleMask: NSWindow.StyleMask = borderlessFullScreenWidgets ? [.borderless] : [.titled, .closable]
        
        let window: NSWindow
        if borderlessFullScreenWidgets {
            window = BorderlessKeyWindow(
                contentRect: contentRect,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
            window.isMovableByWindowBackground = true
        } else {
            window = NSWindow(
                contentRect: contentRect,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
        }

        window.title = appInfo.displayName
        window.contentViewController = hosting
        window.hasShadow = tweaks.useNativeShadow

        window.backgroundColor = tweaks.transparentBackground ? .clear : .windowBackgroundColor

        hosting.view.wantsLayer = true
        if !tweaks.useNativeShadow {
            window.hasShadow = false
            if let layer = hosting.view.layer {
                layer.masksToBounds = false
                layer.shadowColor = NSColor.black.cgColor
                layer.shadowOpacity = 0.45
                layer.shadowOffset = CGSize(width: 0, height: -15)
                layer.shadowRadius = 40
                layer.shadowPath = CGPath(rect: hosting.view.bounds, transform: nil)
            }
        }

        window.setContentSize(NSSize(width: width, height: height))
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Store window with identifier for resizing
        window.identifier = NSUserInterfaceItemIdentifier(windowIdentifier)
        
        openWindows.append(window)
        
        // Setup overlay controller for Option key
        let overlayController = WidgetOverlayController(parentWindow: window, appInfo: appInfo, widgetManager: self)
        overlayControllers[windowIdentifier] = overlayController
        
        // Setup global monitor on first window
        setupGlobalOverlayMonitor()
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            overlayControllers[windowIdentifier]?.cleanup()
            overlayControllers.removeValue(forKey: windowIdentifier)
            openWindows.removeAll { $0 == window }
            cleanupGlobalOverlayMonitorIfNeeded()
            NotificationCenter.default.removeObserver(self as Any, name: NSWindow.willCloseNotification, object: window)
        }
    }

    func resizeWindow(for appInfo: AppInfo, width: CGFloat, height: CGFloat) {
        let windowIdentifier = appInfo.bundleIdentifier + "_" + appInfo.id
        
        // Save the custom size to tweaks
        var tweaks = self.tweaks(for: appInfo.bundleIdentifier, id: appInfo.id)
        tweaks.customWidth = width
        tweaks.customHeight = height
        updateTweaks(for: appInfo.bundleIdentifier, id: appInfo.id, to: tweaks)
        
        // Resize normal window if open
        if let window = openWindows.first(where: { $0.identifier?.rawValue == windowIdentifier }) {
            let oldFrame = window.frame
            let newContentRect = NSRect(x: 0, y: 0, width: width, height: height)
            var newFrame = window.frameRect(forContentRect: newContentRect)
            
            let newY = oldFrame.origin.y + oldFrame.height - newFrame.height
            newFrame.origin = CGPoint(x: oldFrame.origin.x, y: newY)
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        }
        
        // Resize fullscreen custom window if open
        NotificationCenter.default.post(
            name: .resizeCustomWindow,
            object: nil,
            userInfo: [
                "appIdentifier": windowIdentifier,
                "width": width,
                "height": height
            ]
        )
    }
    
    func clearPreferences(for appInfo: AppInfo) {
        let namespace = "WidgetPrefs::" + appInfo.bundleIdentifier + "_" + appInfo.id
        UserDefaults.standard.removeObject(forKey: namespace)
        UserDefaults.standard.synchronize()
    }
    
    private func showError(_ message: String) {
        if !silentMode {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } else {
            print("[SM] \(message)")
        }
    }
    
    private func showDuplicateWindowWarning(for appInfo: AppInfo) {
        let alert = NSAlert()
        alert.messageText = "Widget Already Open"
        alert.informativeText = "A window for this widget is already open. To open multiple instances, go to Options > Allow multiple instances of the same widget."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
