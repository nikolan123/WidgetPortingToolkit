//
//  WidgetPlayerTemplateApp.swift
//  WidgetPlayerTemplate
//
//  Created by Niko on 24.04.26.
//

import SwiftUI
import AppKit

@main
struct WidgetPlayerTemplateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var overlayController: TemplateOverlayController?
    private var flagsMonitor: Any?

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

        let widgetController = WidgetPlayerViewController(config: config)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: config.width, height: config.height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = config.displayName
        window.contentViewController = widgetController
        window.setContentSize(NSSize(width: config.width, height: config.height))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        let overlayController = TemplateOverlayController(parentWindow: window, displayName: config.displayName)
        self.overlayController = overlayController

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.overlayController?.handleOptionKey(held: event.modifierFlags.contains(.option))
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        overlayController?.cleanup()
        overlayController = nil
    }
}
