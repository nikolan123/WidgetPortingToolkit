//
//  ContentView.swift
//  WidgetPortingAPP
//
//  Created by Niko on 7.09.25.
//

import SwiftUI

// wrapper for splash screen
struct AppRootView: View {
    @EnvironmentObject var widgetManager: WidgetManager
    @State private var finishedLoading = false

    var body: some View {
        ZStack {
            if finishedLoading {
                ContentView(widgetManager: widgetManager)
                    .transition(.opacity)
            } else {
                SplashScreenView()
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.6), value: finishedLoading)
        .task {
            await widgetManager.startupLoadAsync()
            finishedLoading = true
        }
    }
}

struct ContentView: View {
    @ObservedObject var widgetManager: WidgetManager
    @State private var isFullScreen = false
    @State private var hostingWindow: NSWindow?

    var body: some View {
        Group {
            if isFullScreen {
                FullScreenBackgroundView(widgetManager: widgetManager, apps: widgetManager.appInfos)
            } else {
                VStack(spacing: 0) {
                    if widgetManager.appInfos.isEmpty {
                        EmptyStateView()
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(widgetManager.appInfos.indices, id: \.self) { index in
                                    let appInfo = widgetManager.appInfos[index]
                                    
                                    WidgetRow(appInfo: appInfo, widgetManager: widgetManager)

                                    if index < widgetManager.appInfos.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: 400, minHeight: 180)
            }
        }
        .background(WindowAccessor(window: $hostingWindow))
        .onAppear {
            updateIsFullScreen()
        }
        .onChange(of: hostingWindow) { _ in
            updateIsFullScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            // Only update if it's our window
            if let window = notification.object as? NSWindow, window == hostingWindow {
                // Check if another ContentView window is already in fullscreen
                let hasOtherFullscreenWindow = NSApplication.shared.windows.contains(where: { otherWindow in
                    otherWindow != window &&
                    (otherWindow.title == "Widget Porting Toolkit" || otherWindow.contentViewController is NSHostingController<AppRootView>) &&
                    otherWindow.styleMask.contains(.fullScreen)
                })
                
                if hasOtherFullscreenWindow {
                    // Another window is already fullscreen, exit fullscreen and show error
                    DispatchQueue.main.async {
                        window.toggleFullScreen(nil)
                        
                        let alert = NSAlert()
                        alert.messageText = "Only One Fullscreen Window Allowed"
                        alert.informativeText = "Another window is already in fullscreen mode. Please exit fullscreen on the other window first."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                } else {
                    updateIsFullScreen()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            // Only update if it's our window
            if let window = notification.object as? NSWindow, window == hostingWindow {
                updateIsFullScreen()
            }
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            widgetManager.handleDrop(providers: providers)
        }
    }

    private func updateIsFullScreen() {
        // Check the actual window this view is in
        if let window = hostingWindow {
            isFullScreen = window.styleMask.contains(.fullScreen)
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.dashed.inset.filled")
                .font(.system(size: 60))
                .foregroundStyle(Color.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("No Widgets Found")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                
                Text("Drop a .wdgt file here to get started")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Widget row component with its own popover state
struct WidgetRow: View {
    let appInfo: AppInfo
    @ObservedObject var widgetManager: WidgetManager
    @State private var showingResizePopover = false
    @State private var showingLanguagePopover = false
    @State private var showingTweaksSheet = false
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 15) {
                if let iconURL = appInfo.iconURL,
                   let nsImage = NSImage(contentsOf: iconURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(appInfo.displayName)
                            .font(.headline)
                        if !appInfo.installedFolder.path.hasPrefix(WidgetManager.installedWidgetsDirectoryURL().path) {
                            StatusBadge(text: "TEMP", color: .orange)
                                .help("This widget has not been copied to your library. It will disappear on next launch.")
                        } else {
                            StatusBadge(text: appInfo.id, color: .green)
                        }
                    }
                    Text(appInfo.bundleIdentifier)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Version: \(appInfo.version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 0) {
                    Button {
                        widgetManager.remove(appInfo)
                    } label: {
                        Image(systemName: "trash")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .frame(width: 32, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this Widget")
                    .tint(.red)

                    Divider().frame(height: 16)
                    
                    Button {
                        showingTweaksSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .frame(width: 32, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Modify this Widget's Tweaks")

                    Divider().frame(height: 16)
                    
                    Button {
                        showingResizePopover.toggle()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .frame(width: 32, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Resize Widget Window")
                    .popover(isPresented: $showingResizePopover) {
                        ResizePopover(appInfo: appInfo, widgetManager: widgetManager)
                    }

                    if !appInfo.languages.isEmpty {
                        Divider().frame(height: 16)
                        
                        Button {
                            showingLanguagePopover.toggle()
                        } label: {
                            Image(systemName: "globe")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                                .frame(width: 32, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .help("Change Language")
                        .popover(isPresented: $showingLanguagePopover) {
                            LanguagePopoverView(appInfo: appInfo, widgetManager: widgetManager)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )

                Button("Open") {
                    let key = appInfo.bundleIdentifier + "_" + appInfo.id
                    if let lang = widgetManager.selectedLanguages[key] {
                        widgetManager.prepareLanguage(for: appInfo, language: lang)
                    }
                    widgetManager.openHTMLWindow(appInfo: appInfo)
                }
                .buttonStyle(.borderedProminent)
                .frame(height: 15)
            }

        }
        .padding()
        .sheet(isPresented: $showingTweaksSheet) {
            TweaksSheet(
                displayName: appInfo.displayName,
                initialTweaks: widgetManager.tweaks(for: appInfo.bundleIdentifier, id: appInfo.id)
            ) { updated in
                widgetManager.updateTweaks(for: appInfo.bundleIdentifier, id: appInfo.id, to: updated)
            } onReset: {
                widgetManager.resetTweaks(for: appInfo.bundleIdentifier, id: appInfo.id)
            } onResetWidget: {
                widgetManager.clearPreferences(for: appInfo)
            }
        }
    }
}

// Status Badge Component
struct StatusBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
            )
    }
}

// Helper to get the NSWindow that contains this view
struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.window = nsView.window
        }
    }
}

struct TweaksSheet: View {
    let displayName: String
    let isInstallWindow: Bool
    @State private var working: WidgetTweaks
    let onSave: (WidgetTweaks) -> Void
    let onReset: (() -> Void)? // reset widget tweaks
    let onResetWidget: (() -> Void)? // reset widget data
    @Environment(\.dismiss) private var dismiss

    init(displayName: String,
         isInstallWindow: Bool = false,
         initialTweaks: WidgetTweaks,
         onSave: @escaping (WidgetTweaks) -> Void,
         onReset: (() -> Void)? = nil,
         onResetWidget: (() -> Void)? = nil) {
        self.displayName = displayName
        self.isInstallWindow = isInstallWindow
        self._working = State(initialValue: initialTweaks)
        self.onSave = onSave
        self.onReset = onReset
        self.onResetWidget = onResetWidget
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text("Tweaks for \(displayName)")
                .font(.title3)
                .bold()

            // Runtime section
            VStack(alignment: .leading, spacing: 10) {
                Text("Runtime")
                    .font(.headline)

                Toggle("Recreate Dashboard API", isOn: $working.recreateDashboardAPI)
                    .onChange(of: working.recreateDashboardAPI) { newValue in
                        if !newValue {
                            working.allowSystemCommands = false
                            working.noAskSystemCommands = false
                        }
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Allow system command execution", isOn: $working.allowSystemCommands)
                        .disabled(!working.recreateDashboardAPI)
                        .onChange(of: working.allowSystemCommands) { newValue in
                            if !newValue {
                                working.noAskSystemCommands = false
                            }
                        }

                    Toggle("Don't ask when running system commands", isOn: $working.noAskSystemCommands)
                        .disabled(!working.allowSystemCommands)
                }
                .padding(.leading, 20)

                Toggle("Inject helper CSS (disable drag/select)", isOn: $working.injectCSS)
                Toggle("Proxy XMLHttpRequest", isOn: $working.xhrProxyEnabled)
                Toggle("Transparent background", isOn: $working.transparentBackground)
                Toggle("Use native window shadow", isOn: $working.useNativeShadow)
            }

            Divider()

            // Preprocessing section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Preprocessing")
                        .font(.headline)
                    
                    Spacer()
                    
                    if !isInstallWindow {
                        Text("You can only modify these from the install window.")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }

                Toggle("Replace appropriate file paths", isOn: $working.replaceFileSchemePaths)
                Toggle("Copy Support Directory", isOn: $working.copySupportDirectory)
                Toggle("Fix self-closing <script /> tags", isOn: $working.fixSelfClosingScriptTags)
                Toggle("Add a blank localizedStrings.js if it doesn't exist", isOn: $working.createBlankLocalizedStrings)
            }
            .disabled(!isInstallWindow)

            Divider()
            
            if !isInstallWindow {
                Text("Runtime changes will apply on the next widget launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Action buttons
            HStack {
                if let onReset = onReset {
                    Button("Reset Tweaks") {
                        onReset()
                        if isInstallWindow {
                            // Reset everything including preprocessing
                            working = WidgetTweaks.defaults()
                        } else {
                            // Only reset runtime tweaks, preserve preprocessing
                            let preservedPreprocessing = (
                                replaceFileSchemePaths: working.replaceFileSchemePaths,
                                copySupportDirectory: working.copySupportDirectory,
                                fixSelfClosingScriptTags: working.fixSelfClosingScriptTags,
                                createBlankLocalizedStrings: working.createBlankLocalizedStrings
                            )
                            working = WidgetTweaks.defaults()
                            working.replaceFileSchemePaths = preservedPreprocessing.replaceFileSchemePaths
                            working.copySupportDirectory = preservedPreprocessing.copySupportDirectory
                            working.fixSelfClosingScriptTags = preservedPreprocessing.fixSelfClosingScriptTags
                            working.createBlankLocalizedStrings = preservedPreprocessing.createBlankLocalizedStrings
                        }
                    }
                }

                if let onResetWidget = onResetWidget {
                    Button("Reset Widget") {
                        onResetWidget()
                    }
                }

                Spacer()

                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(working)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 520)
    }
}

// previews

#Preview {
    ContentView(
        widgetManager: PreviewWidgetManager()
    )
}

#Preview("TweaksSheet") {
    TweaksSheet(
        displayName: "Stickies",
        initialTweaks: WidgetTweaks.defaults(),
        onSave: { _ in },
        onReset: {},
        onResetWidget: {}
    )
}

