//
//  WidgetPortingAPPApp.swift
//  WidgetPortingAPP
//
//  Created by Niko on 7.09.25.
//

import SwiftUI

@main
struct WidgetPortingAPPApp: App {
    @StateObject private var widgetManager = WidgetManager()
    @AppStorage("defaultLaunchFullScreen") var defaultLaunchFullScreen: Bool = false
    @AppStorage("defaultWidgetLanguage") var defaultLanguage: String = ""
    @AppStorage("borderlessFullScreenWidgets") var borderlessFullScreenWidgets: Bool = true
    @AppStorage("hasCompletedOOBE") private var hasCompletedOOBE: Bool = false

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .navigationTitle("Widget Porting Toolkit")
                .environmentObject(widgetManager)
                .onAppear {
                    // OOBE on first launch
                    if !hasCompletedOOBE {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            widgetManager.openOOBEWindow()
                        }
                    } else if defaultLaunchFullScreen {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            // Find the main app window
                            if let window = NSApplication.shared.windows.first(where: { 
                                $0.title == "Widget Porting Toolkit" || $0.contentViewController is NSHostingController<AppRootView>
                            }) {
                                if !window.styleMask.contains(.fullScreen) {
                                    window.toggleFullScreen(nil)
                                }
                            }
                        }
                    }
                }
        }
        .commands {
            CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                Button("About") {
                    openAboutWindow()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            
            CommandMenu("Options") {
                Toggle("Silent Mode", isOn: $widgetManager.silentMode)
                Toggle("Auto Open Widget on Install", isOn: $widgetManager.autoOpenWidgetOnInstall)
                Toggle("Don't Copy Widgets", isOn: $widgetManager.portableMode)
                    .disabled(!widgetManager.silentMode)
                
                Divider()

                Toggle("Launch in Full Screen by Default", isOn: $defaultLaunchFullScreen)
                Toggle("Borderless Widgets", isOn: $borderlessFullScreenWidgets)
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
                            UserDefaults.standard.synchronize()
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
