//
//  WidgetPortingAPPApp.swift
//  WidgetPortingAPP
//
//  Created by Niko on 7.09.25.
//

import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let widgetManager = WidgetManager.shared
    private var mainWindow: NSWindow?
    private var openedWidgetDuringLaunch = false
    private var hasPresentedMainWindow = false
    
    private var hasCompletedOOBE: Bool {
        widgetManager.hasCompletedOOBE
    }
    
    private func isWidgetURL(_ url: URL) -> Bool {
        url.lastPathComponent != "-NSDocumentRevisionsDebugMode" && url.pathExtension.lowercased() == "wdgt"
    }
    
    private func openWidgetURLs(_ urls: [URL]) -> Bool {
        let widgetURLs = urls.filter(isWidgetURL)
        guard !widgetURLs.isEmpty else { return false }
        
        openedWidgetDuringLaunch = true
        for url in widgetURLs {
            widgetManager.handleOpenedWidgetURL(url)
        }
        return true
    }
    
    private func makeMainWindow() -> NSWindow {
        let rootView = AppRootView()
            .environmentObject(widgetManager)
        let hosting = NSHostingController(rootView: rootView)
        
        let window = NSWindow(contentViewController: hosting)
        window.title = "Widget Porting Toolkit"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 400, height: 180)
        window.setContentSize(NSSize(width: 720, height: 520))
        window.center()
        window.delegate = self
        window.setFrameAutosaveName("MainWindow")
        return window
    }
    
    private func showMainWindow() {
        let window = mainWindow ?? makeMainWindow()
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        if !hasPresentedMainWindow {
            hasPresentedMainWindow = true
            scheduleStartupWindows(for: window)
        }
    }
    
    private func scheduleStartupWindows(for window: NSWindow) {
        if !hasCompletedOOBE {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.widgetManager.openOOBEWindow()
            }
        } else if widgetManager.defaultLaunchFullScreen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard !window.styleMask.contains(.fullScreen) else { return }
                window.toggleFullScreen(nil)
            }
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !openedWidgetDuringLaunch {
            showMainWindow()
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }
    
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == mainWindow {
            mainWindow = nil
        }
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        _ = openWidgetURLs(urls)
    }
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        return openWidgetURLs([url])
    }
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        _ = openWidgetURLs(urls)
        sender.reply(toOpenOrPrint: .success)
    }
}

@main
struct WidgetPortingAPPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var widgetManager = WidgetManager.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                Button("About") {
                    openAboutWindow()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandGroup(replacing: .appSettings) {
            }
            
            CommandMenu("Options") {
                Toggle("Silent Mode", isOn: $widgetManager.silentMode)
                Toggle("Auto Open Widget on Install", isOn: $widgetManager.autoOpenWidgetOnInstall)
                Toggle("Don't Copy Widgets", isOn: $widgetManager.portableMode)
                    .disabled(!widgetManager.silentMode)
                
                Divider()

                Toggle("Launch in Full Screen by Default", isOn: $widgetManager.defaultLaunchFullScreen)
                Toggle("Borderless Widgets", isOn: $widgetManager.borderlessFullScreenWidgets)
                Toggle("Allow multiple instances of the same widget", isOn: $widgetManager.allowMultipleInstances)

                Divider()
                
                Button("Set Default Language") {
                    widgetManager.openDefaultLanguageSetting()
                }
                
                Divider()
                
                Button("Install Support Directory…") {
                    widgetManager.browseAndInstallSupportDirectory()
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Support Directory Installed"
                        alert.informativeText =
                            "The new Support Directory will be used for newly added widgets.\n" +
                            "Existing widgets must be removed and re-added to use it."
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }

                Button("Open Data Folder…") {
                    let supportURL = WidgetManager.applicationSupportBaseURL()
                    NSWorkspace.shared.open(supportURL)
                }
                
                Button("Reset All Data") {
                    let alert = NSAlert()
                    alert.messageText = "Reset All Data?"
                    alert.informativeText = "This will delete all installed widgets, support directory, and settings. The app will restart and show the welcome guide."
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "Reset & Restart")
                    alert.addButton(withTitle: "Cancel")
                    
                    if alert.runModal() == .alertFirstButtonReturn {
                        // Delete all application support data
                        let supportURL = WidgetManager.applicationSupportBaseURL()
                        try? FileManager.default.removeItem(at: supportURL)
                        
                        // Reset UserDefaults
                        if let bundleID = Bundle.main.bundleIdentifier {
                            UserDefaults.standard.removePersistentDomain(forName: bundleID)
                        }
                        
                        // Restart the app
                        let appPath = Bundle.main.bundlePath
                        let task = Process()
                        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                        task.arguments = ["-n", appPath]
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            try? task.run()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                NSApplication.shared.terminate(nil)
                            }
                        }
                    }
                }
                
                Divider()
                
                Button("Show Welcome Guide…") {
                    widgetManager.openOOBEWindow()
                }
            }
        }
    }
}
