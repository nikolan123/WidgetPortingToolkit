//
//  FullScreenView.swift
//  WidgetPortingAPP
//
//  Created by Niko on 14.09.25.
//

import SwiftUI

// PreferenceKey to capture icon frames
private struct IconFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct FullScreenBackgroundView: View {
    @ObservedObject var widgetManager: WidgetManager
    @State private var isOverlayVisible = false
    @State private var expandedGroup: [AppInfo]? = nil
    @State private var showingTweaksForApp: AppInfo?
    @State private var languagePopoverApp: AppInfo? = nil
    @Environment(\.colorScheme) var colorScheme

    let apps: [AppInfo]
    let columns = Array(repeating: GridItem(.flexible(), spacing: 30), count: 7)

    // store icon frames in the root coordinate space
    @State private var iconFrames: [String: CGRect] = [:]
    // anchor point to position expandedGroup
    @State private var expandedAnchor: CGPoint? = nil

    private var groupedApps: [(key: String, value: [AppInfo])] {
        Dictionary(grouping: apps, by: \.bundleIdentifier)
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        ZStack {
            // Background
            ZStack {
                if widgetManager.fullScreenBackgroundStyle == .grid {
                    if colorScheme == .dark { // can be a one liner on 14.0+
                        Color.clear
                            .ignoresSafeArea()
                    } else {
                        Color(hex: "#3b3b3d")
                            .ignoresSafeArea()
                    }
                } else {
                    Color.clear
                        .ignoresSafeArea()
                }
                
                GeometryReader { _ in
                    Color.clear
                        .background(
                            Image(widgetManager.fullScreenBackgroundStyle.assetName)
                                .resizable(resizingMode: .tile)
                        )
                        .ignoresSafeArea()
                }
                .blur(radius: isOverlayVisible ? 2 : 0)
                .animation(.easeInOut(duration: 0.2), value: isOverlayVisible)
                
                if widgetManager.fullScreenBackgroundStyle == .grid {
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(hex: "#555456").opacity(0.12), location: 0.0),
                            .init(color: Color(hex: "#4d4c4e").opacity(0.25), location: 0.4),
                            .init(color: Color(hex: "#444443").opacity(0.45), location: 0.7),
                            .init(color: Color(hex: "#3e3f3d").opacity(0.6), location: 1.0)
                        ]),
                        center: .center,
                        startRadius: 50,
                        endRadius: 700
                    )
                    .blendMode(.overlay)
                    .ignoresSafeArea()
                }
            }
            .zIndex(0)
            
            // Custom window container
            CustomWindowContainer(widgetManager: widgetManager)
                .opacity(isOverlayVisible ? 0 : 1)
                .allowsHitTesting(!isOverlayVisible)
                .animation(.easeInOut(duration: 0.2), value: isOverlayVisible)
                .zIndex(1)
            
            // Dark overlay when folder is expanded
            if expandedGroup != nil {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: expandedGroup)
                    .zIndex(2)
                    .onTapGesture {
                        expandedGroup = nil
                        expandedAnchor = nil
                    }
            }
            
            if isOverlayVisible {
                if groupedApps.isEmpty {
                    VStack {
                        Spacer()
                        Text("No Widgets Installed. Drag a .wdgt here")
                            .foregroundColor(.white)
                            .font(.custom("Lucida Grande", size: 20))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 50) {
                        ForEach(groupedApps, id: \.key) { entry in
                            let group = entry.value
                            let firstApp = group.first!

                            Button {
                                let optionHeld = NSEvent.modifierFlags.contains(.option)
                                withAnimation(.spring()) {
                                    if group.count > 1 || optionHeld {
                                        expandedGroup = group
                                        if let frame = iconFrames[firstApp.id] {
                                            // anchor at midX, bottom of icon cell
                                            expandedAnchor = CGPoint(x: frame.midX, y: frame.maxY)
                                        } else {
                                            expandedAnchor = nil
                                        }
                                    } else {
                                        widgetManager.openHTMLWindow(appInfo: firstApp)
                                        isOverlayVisible = false
                                    }
                                }
                            } label: {
                                VStack(spacing: 5) {
                                    AppIconView(app: firstApp)
                                        .overlay(
                                            (expandedGroup != nil && !group.contains(where: { expandedGroup?.contains($0) == true }))
                                                ? Color.black.opacity(0.5)
                                                : Color.clear
                                        )
                                        .animation(.easeInOut(duration: 0.2), value: expandedGroup)
                                    
                                    Text(firstApp.displayName)
                                        .foregroundStyle(.white)
                                        .font(.custom("Lucida Grande", size: 14))
                                        .lineLimit(1)
                                        .opacity((expandedGroup != nil && !group.contains(where: { expandedGroup?.contains($0) == true })) ? 0.5 : 1)
                                        .animation(.easeInOut(duration: 0.2), value: expandedGroup)
                                }
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .preference(
                                                key: IconFramePreferenceKey.self,
                                                value: [firstApp.id: geo.frame(in: .named("root"))]
                                            )
                                    }
                                )

                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 100)
                    .padding(.horizontal, 50)
                }
                .allowsHitTesting(expandedGroup == nil)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 1.1).combined(with: .opacity),
                        removal: .scale(scale: 1.1).combined(with: .opacity)
                    )
                )
                .zIndex(3)
            }

            // Expanded group overlay
            if let group = expandedGroup {
                GeometryReader { geometry in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Select an Instance")
                                .foregroundStyle(.white)
                                .font(.custom("Lucida Grande", size: 20))
                            Spacer()
                            Button("Close") {
                                withAnimation(.spring()) {
                                    expandedGroup = nil
                                    expandedAnchor = nil
                                }
                            }
                            .foregroundStyle(.white)
                        }
                        
                        Divider()

                        ForEach(group, id: \.id) { app in
                            HStack(spacing: 15) {
                                Button {
                                    widgetManager.openHTMLWindow(appInfo: app)
                                    isOverlayVisible = false
                                    expandedGroup = nil
                                    expandedAnchor = nil
                                } label: {
                                    HStack(spacing: 15) {
                                        AppIconView(app: app, size: 30)

                                        Text("\(app.displayName) \(app.version)")
                                            .foregroundStyle(.white)
                                    }
                                }
                                .buttonStyle(.plain)

                                if !app.installedFolder.path.hasPrefix(WidgetManager.installedWidgetsDirectoryURL().path) {
                                    StatusBadge(text: "TEMP", color: .orange)
                                        .help("This widget has not been copied to your library. It will disappear on next launch.")
                                } else {
                                    StatusBadge(text: app.id, color: .green)
                                }

                                Spacer()

                                Button {
                                    languagePopoverApp = app
                                } label: {
                                    Image(systemName: "globe")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 15, height: 15)
                                }
                                .buttonStyle(.bordered)
                                .help("Change Language")
                                .popover(item: $languagePopoverApp) { app in
                                    LanguagePopoverView(appInfo: app, widgetManager: widgetManager)
                                }

                                Button {
                                    showingTweaksForApp = app
                                } label: {
                                    Image(systemName: "slider.horizontal.3")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 15, height: 15)
                                }
                                .buttonStyle(.bordered)
                                .help("Modify this Widget's Tweaks")

                                Button {
                                    widgetManager.remove(app)
                                    if var g = expandedGroup {
                                        withAnimation(.spring()) {
                                            g.removeAll { $0.id == app.id }
                                            expandedGroup = g.isEmpty ? nil : g
                                            if expandedGroup == nil { expandedAnchor = nil }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 15, height: 15)
                                }
                                .buttonStyle(.bordered)
                                .help("Delete this Widget")
                                .tint(.red)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                        }
                        
                        Divider()
                        
                        Button {
                            if let firstApp = group.first {
                                widgetManager.duplicate(firstApp)
                                withAnimation(.spring()) {
                                    expandedGroup = widgetManager.appInfos.filter { $0.bundleIdentifier == firstApp.bundleIdentifier }
                                }
                            }
                        } label: {
                            HStack(spacing: 15) {
                                Image(systemName: "plus.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 30, height: 30)
                                    .foregroundStyle(.green)
                                Text("New Instance")
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.custom("Lucida Grande", size: 14))
                    .padding(.horizontal, 50)
                    .padding(.vertical)
                    .frame(maxWidth: .infinity, alignment: .top) // grow downward only
                    .background(
                        Group {
                            if let bg = NSImage(named: "ecsb_background_tile") {
                                Image(nsImage: bg)
                                    .resizable(resizingMode: .tile)
                            } else {
                                Color.black.opacity(0.2)
                            }
                        }
                    )
                    .tint(.white)
                    .overlay(
                        VStack {
                            Rectangle()
                                .frame(height: 1)
                                .foregroundStyle(Color(hex: "#797979"))
                            Spacer()
                            Rectangle()
                                .frame(height: 1)
                                .foregroundStyle(Color(hex: "#797979"))
                        }
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 1.1).combined(with: .opacity),
                            removal: .scale(scale: 1.1).combined(with: .opacity)
                        )
                    )
                    .offset(x: 0, y: computeOverlayY(in: geometry.size))
                }
                .zIndex(4)
            }

            // Bottom control bar
            VStack {
                Spacer()
                HStack {
                    Button {
                        withAnimation(.spring()) {
                            isOverlayVisible.toggle()
                            if !isOverlayVisible {
                                expandedGroup = nil
                                expandedAnchor = nil
                            }
                        }
                    } label: {
                        Image("plusbutton")
                            .resizable()
                            .frame(width: 45, height: 45)
                            .opacity(isOverlayVisible ? 0.6 : 1.0)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        print("minus")
                    }) {
                        Image("minusbutton")
                            .resizable()
                            .frame(width: 45, height: 45)
                    }
                    
                    if isOverlayVisible {
                        Link(destination: URL(string: "https://widgets.nikolan.net/getwidgets")!) {
                            Image("MoreWidgetsText")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 45)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    if !isOverlayVisible {
                        Button(action: {
                            switchToNextSpace()
                        }) {
                            Image("exitarrow")
                                .resizable()
                                .frame(width: 45, height: 45)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding()
            .zIndex(5)
        }
        .coordinateSpace(name: "root")
        .onPreferenceChange(IconFramePreferenceKey.self) { new in
            iconFrames = new
        }
        .focusable(true)
        .focusRingDisabled()
        .onExitCommand {
            withAnimation(.easeInOut(duration: 0.1)) {
                if expandedGroup != nil {
                    expandedGroup = nil
                    expandedAnchor = nil
                } else if isOverlayVisible {
                    isOverlayVisible = false
                }
            }
        }
        .sheet(item: $showingTweaksForApp) { app in
            TweaksSheet(
                displayName: app.displayName,
                initialTweaks: widgetManager.tweaks(for: app.bundleIdentifier, id: app.id)
            ) { updated in
                widgetManager.updateTweaks(for: app.bundleIdentifier, id: app.id, to: updated)
            } onReset: {
                widgetManager.resetTweaks(for: app.bundleIdentifier, id: app.id)
            } onResetWidget: {
                widgetManager.clearPreferences(for: app)
            }
        }
        .onChange(of: expandedGroup) { newGroup in
            guard let grp = newGroup, let first = grp.first else {
                expandedAnchor = nil
                return
            }
            if let frame = iconFrames[first.id] {
                expandedAnchor = CGPoint(x: frame.midX, y: frame.maxY)
            }
        }
    }

    // Compute vertical offset for overlay (position above or below based on available space)
    private func computeOverlayY(in parentSize: CGSize) -> CGFloat {
        guard let anchor = expandedAnchor, let group = expandedGroup else {
            return 0
        }
        
        let verticalPadding: CGFloat = 10
        // Estimate overlay height based on number of items
        let estimatedHeight: CGFloat = CGFloat(100 + (group.count * 50) + 100)
        
        let spaceBelow = parentSize.height - anchor.y
        let spaceAbove = anchor.y
        
        // If there's enough space below, position below the icon
        if spaceBelow >= estimatedHeight + verticalPadding + 20 {
            return anchor.y + verticalPadding
        }
        // Otherwise, position above the icon
        else if spaceAbove >= estimatedHeight + verticalPadding {
            return anchor.y - estimatedHeight - verticalPadding
        }
        // If neither has enough space, center it vertically
        else {
            return (parentSize.height - estimatedHeight) / 2
        }
    }
}

// MARK: - AppIconView

struct AppIconView: View {
    let app: AppInfo
    var size: CGFloat = 75

    var body: some View {
        if let iconURL = app.iconURL,
           let nsImage = NSImage(contentsOf: iconURL) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .background(
                    Image("wviconshadow")
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 2.5, height: size * 2.5)
                        .allowsHitTesting(false)
                        .offset(x: 0, y: 0)
                )
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(.white)
            
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

func switchToNextSpace() {
    let script = "tell application \"System Events\" to key code 124 using control down"
    var error: NSDictionary?
    if let apple = NSAppleScript(source: script) {
        apple.executeAndReturnError(&error)
        if let err = error {
            print("AppleScript error: \(err)")
        }
    }
}

// previews

final class PreviewWidgetManager: WidgetManager {
    override func openHTMLWindow(appInfo: AppInfo) {
        print("Pretend to open \(appInfo.displayName)")
    }
}

#Preview {
    let mockApps: [AppInfo] = (1...10).map { index in
        AppInfo(
            id: "\(index)",
            displayName: "Sample App \(index)",
            bundleIdentifier: "com.example.sample\(index)",
            version: "1.0",
            htmlURL: URL(string: "https://example.com/\(index)")!,
            tempFolder: URL(fileURLWithPath: "/tmp"),
            installedFolder: URL(fileURLWithPath: "/Applications"),
            width: 800,
            height: 600,
            iconURL: nil,
            languages: ["en"]
        )
    } + [
        AppInfo(
            id: "67",
            displayName: "Sample App 3",
            bundleIdentifier: "com.example.sample3",
            version: "1.1",
            htmlURL: URL(string: "https://example.com/3copy")!,
            tempFolder: URL(fileURLWithPath: "/tmp"),
            installedFolder: URL(fileURLWithPath: "/Applications"),
            width: 1024,
            height: 768,
            iconURL: nil,
            languages: ["en"]
        )
    ]
    
    FullScreenBackgroundView(
        widgetManager: PreviewWidgetManager(),
        apps: mockApps
    )
    .frame(width: 800, height: 600)
}
