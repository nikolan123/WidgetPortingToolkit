//
//  WidgetPlayerTemplateApp.swift
//  WidgetPlayerTemplate
//
//  Created by Niko on 24.04.26.
//

import SwiftUI
import AppKit
import Combine

@main
struct WidgetPlayerTemplateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var runtimeSettings = TemplateRuntimeSettings.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                Button("About \(aboutDisplayName)") {
                    guard let config = appDelegate.currentConfig else { return }
                    openTemplateAboutWindow(config: config)
                }
            }

            CommandGroup(replacing: .appSettings) {
            }

            CommandMenu("Options") {
                Toggle("Recreate Dashboard API", isOn: binding(\.recreateDashboardAPI))
                Toggle("Allow system command execution", isOn: binding(\.allowSystemCommands))
                Toggle("Don't ask when running system commands", isOn: binding(\.noAskSystemCommands))
                    .disabled(!runtimeSettings.allowSystemCommands)

                Divider()

                Toggle("Inject helper CSS", isOn: binding(\.injectCSS))
                Toggle("Transparent background", isOn: binding(\.transparentBackground))
                Toggle("Use native window shadow", isOn: binding(\.useNativeShadow))

                Divider()

                Toggle("Always on Top", isOn: binding(\.alwaysOnTop))
                Toggle("Hide Titlebar", isOn: binding(\.hideTitlebar))
            }
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<TemplateRuntimeSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { runtimeSettings[keyPath: keyPath] },
            set: { runtimeSettings[keyPath: keyPath] = $0 }
        )
    }

    private var aboutDisplayName: String {
        appDelegate.currentConfig?.displayName
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Widget"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var overlayController: TemplateOverlayController?
    private var flagsMonitor: Any?
    private let runtimeSettings = TemplateRuntimeSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private let windowFrameDefaults = UserDefaults.standard
    var currentConfig: WidgetConfig?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let config = WidgetConfigLoader.load() else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Widget payload missing"
            alert.informativeText = "Expected a widget folder with Info.plist at Contents/Resources/widget or WPT_WIDGET_DEV_ROOT."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        currentConfig = config
        showOrCreateWindow()
        bindRuntimeSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showOrCreateWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let window {
            saveWindowFrame(for: window)
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        overlayController?.cleanup()
        overlayController = nil
    }

    private func showOrCreateWindow() {
        guard let config = currentConfig else { return }

        if let window {
            installFlagsMonitor()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let widgetController = WidgetPlayerViewController(config: config, runtimeSettings: runtimeSettings)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: config.width, height: config.height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.title = config.displayName
        window.contentViewController = widgetController
        window.setContentSize(NSSize(width: config.width, height: config.height))
        applyWindowChrome(to: window)
        applyWindowLevel(to: window)
        applyWindowShadow(to: window)
        applyWindowTransparency(to: window)
        restoreWindowFrame(for: window, config: config)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        let overlayController = TemplateOverlayController(parentWindow: window, displayName: config.displayName)
        self.overlayController = overlayController

        installFlagsMonitor()
    }

    private func windowFrameDefaultsKey(for config: WidgetConfig) -> String {
        let appIdentifier = Bundle.main.bundleIdentifier ?? "WidgetPlayerTemplate"
        let widgetIdentifier = config.bundleIdentifier.isEmpty ? "widget" : config.bundleIdentifier
        return "WidgetWindowFrame::\(appIdentifier)::\(widgetIdentifier)"
    }

    private func restoreWindowFrame(for window: NSWindow, config: WidgetConfig) {
        let key = windowFrameDefaultsKey(for: config)
        if let frameString = windowFrameDefaults.string(forKey: key) {
            let restoredFrame = NSRectFromString(frameString)
            if restoredFrame.width > 0, restoredFrame.height > 0 {
                window.setFrame(restoredFrame, display: false)
                return
            }
        }
        window.center()
    }

    private func saveWindowFrame(for window: NSWindow) {
        guard let config = currentConfig else { return }
        let key = windowFrameDefaultsKey(for: config)
        windowFrameDefaults.set(NSStringFromRect(window.frame), forKey: key)
    }

    private func installFlagsMonitor() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.overlayController?.handleOptionKey(held: event.modifierFlags.contains(.option))
            return event
        }
    }

    private func bindRuntimeSettings() {
        Publishers.Merge3(
            runtimeSettings.$recreateDashboardAPI.map { _ in () },
            runtimeSettings.$allowSystemCommands.map { _ in () },
            runtimeSettings.$injectCSS.map { _ in () }
        )
        .dropFirst()
        .receive(on: RunLoop.main)
        .sink { [weak self] in
            self?.reloadWidgetController()
        }
        .store(in: &cancellables)

        runtimeSettings.$alwaysOnTop
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let window = self.window else { return }
                self.applyWindowLevel(to: window)
            }
            .store(in: &cancellables)

        runtimeSettings.$useNativeShadow
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let window = self.window else { return }
                self.applyWindowShadow(to: window)
            }
            .store(in: &cancellables)

        runtimeSettings.$transparentBackground
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let window = self.window else { return }
                self.applyWindowTransparency(to: window)
            }
            .store(in: &cancellables)

        runtimeSettings.$hideTitlebar
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let window = self.window else { return }
                self.applyWindowChrome(to: window)
            }
            .store(in: &cancellables)
    }

    private func currentViewportSize(in window: NSWindow) -> NSSize {
        if let contentView = window.contentView {
            return contentView.bounds.size
        }
        return window.contentRect(forFrameRect: window.frame).size
    }

    private func applyWindowLevel(to window: NSWindow) {
        window.level = runtimeSettings.alwaysOnTop ? .floating : .normal
    }

    private func applyWindowShadow(to window: NSWindow) {
        window.hasShadow = runtimeSettings.useNativeShadow
        window.invalidateShadow()
    }

    private func applyWindowTransparency(to window: NSWindow) {
        let transparent = runtimeSettings.transparentBackground
        window.isOpaque = !transparent
        window.backgroundColor = transparent ? .clear : .windowBackgroundColor
    }

    private func applyWindowChrome(to window: NSWindow) {
        let preservedOrigin = window.frame.origin
        let viewportSize = currentViewportSize(in: window)
        var styleMask = window.styleMask

        if runtimeSettings.hideTitlebar {
            styleMask.insert(.fullSizeContentView)
        } else {
            styleMask.remove(.fullSizeContentView)
        }

        window.styleMask = styleMask
        window.titleVisibility = runtimeSettings.hideTitlebar ? .hidden : .visible
        window.titlebarAppearsTransparent = runtimeSettings.hideTitlebar
        window.isMovableByWindowBackground = runtimeSettings.hideTitlebar
        window.titlebarSeparatorStyle = runtimeSettings.hideTitlebar ? .none : .automatic

        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = runtimeSettings.hideTitlebar
        }

        window.setContentSize(viewportSize)
        preserveWindowOrigin(window, origin: preservedOrigin)
    }

    private func reloadWidgetController() {
        guard let window, let config = currentConfig else { return }

        let preservedOrigin = window.frame.origin
        let viewportSize = currentViewportSize(in: window)
        let widgetController = WidgetPlayerViewController(config: config, runtimeSettings: runtimeSettings)
        window.contentViewController = widgetController
        window.setContentSize(viewportSize)
        applyWindowChrome(to: window)
        applyWindowTransparency(to: window)
        preserveWindowOrigin(window, origin: preservedOrigin)
    }

    private func preserveWindowOrigin(_ window: NSWindow, origin: NSPoint) {
        guard window.frame.origin != origin else { return }
        var frame = window.frame
        frame.origin = origin
        window.setFrame(frame, display: false)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender == window else { return true }
        saveWindowFrame(for: sender)
        overlayController?.dismissOverlay()
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        sender.orderOut(nil)
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard let movedWindow = notification.object as? NSWindow, movedWindow == window else { return }
        saveWindowFrame(for: movedWindow)
    }

    func windowDidResize(_ notification: Notification) {
        guard let resizedWindow = notification.object as? NSWindow, resizedWindow == window else { return }
        saveWindowFrame(for: resizedWindow)
    }
}
