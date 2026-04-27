//
//  CustomWindowManager.swift
//  WidgetPortingAPP
//
//  Created by Niko on 17.09.25.
//

import SwiftUI
import WebKit

// MARK: - Custom Window Model

class CustomWindow: ObservableObject, Identifiable {
    let id = UUID()
    let appInfo: AppInfo
    let tweaks: WidgetTweaks
    @Published var position: CGPoint
    @Published var size: CGSize
    @Published var isPinned: Bool = false
    
    init(appInfo: AppInfo, tweaks: WidgetTweaks, position: CGPoint) {
        self.appInfo = appInfo
        self.tweaks = tweaks
        self.position = position
        self.size = CGSize(width: appInfo.width, height: appInfo.height)
    }
}

// MARK: - Window Container

struct CustomWindowContainer: View {
    @State private var openWindows: [CustomWindow] = []
    @State private var focusedWindowId: UUID?
    @State private var isOptionHeld: Bool = false
    @ObservedObject var widgetManager: WidgetManager
    let showCloseButtons: Bool
    
    private func bringToFront(_ window: CustomWindow) {
        if focusedWindowId == window.id { return }
        if let index = openWindows.firstIndex(where: { $0.id == window.id }) {
            openWindows.remove(at: index)
            
            if window.isPinned {
                openWindows.append(window)
            } else {
                // Insert before the first pinned window, or at the end if none
                if let firstPinnedIndex = openWindows.firstIndex(where: { $0.isPinned }) {
                    openWindows.insert(window, at: firstPinnedIndex)
                } else {
                    openWindows.append(window)
                }
            }
            focusedWindowId = window.id
        }
    }
    
    var body: some View {
        ZStack {
            ForEach(openWindows) { window in
                CustomWindowView(
                    window: window,
                    widgetManager: widgetManager,
                    isOptionHeld: isOptionHeld,
                    onClose: { windowId in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            openWindows.removeAll { $0.id == windowId }
                            if focusedWindowId == windowId {
                                focusedWindowId = openWindows.last?.id
                            }
                        }
                    },
                    onFocus: { window in
                        bringToFront(window)
                    }
                )
            }

            if showCloseButtons {
                ForEach(openWindows) { window in
                    DashboardCloseBoxOverlay(
                        window: window,
                        widgetManager: widgetManager,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                openWindows.removeAll { $0.id == window.id }
                                if focusedWindowId == window.id {
                                    focusedWindowId = openWindows.last?.id
                                }
                            }
                        }
                    )
                    .zIndex(1000)
                }
            }
            
            OptionKeyMonitor(isOptionHeld: $isOptionHeld)
                .frame(width: 0, height: 0)
            
            KeyboardShortcutCatcher {
                if let focused = focusedWindowId {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        openWindows.removeAll { $0.id == focused }
                    }
                    focusedWindowId = openWindows.last?.id
                }
            }
            .frame(width: 0, height: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCustomWindow)) { notification in
            if let userInfo = notification.userInfo,
               let appInfo = userInfo["appInfo"] as? AppInfo,
               let tweaks = userInfo["tweaks"] as? WidgetTweaks {
                
                let windowIdentifier = appInfo.bundleIdentifier + "_" + appInfo.id
                
                if !widgetManager.allowMultipleInstances {
                    let existingWindow = openWindows.first(where: { window in
                        let existingIdentifier = window.appInfo.bundleIdentifier + "_" + window.appInfo.id
                        return existingIdentifier == windowIdentifier
                    })
                    
                    if let existingWindow {
                        let alert = NSAlert()
                        alert.messageText = "Widget Already Open"
                        alert.informativeText = "A window for this widget is already open. To open multiple instances, go to Options > Allow multiple instances of the same widget."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                        bringToFront(existingWindow)
                        return
                    }
                }
                
                let position = CGPoint(
                    x: 200 + CGFloat(openWindows.count * 30),
                    y: 200 + CGFloat(openWindows.count * 30)
                )
                
                // Use custom size if provided, otherwise use saved tweaks, otherwise use default
                let width = userInfo["width"] as? CGFloat ?? tweaks.customWidth ?? appInfo.width
                let height = userInfo["height"] as? CGFloat ?? tweaks.customHeight ?? appInfo.height
                
                let window = CustomWindow(appInfo: appInfo, tweaks: tweaks, position: position)
                window.size = CGSize(width: width, height: height)
                openWindows.append(window)
                bringToFront(window)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .resizeCustomWindow)) { notification in
            if let userInfo = notification.userInfo,
               let appIdentifier = userInfo["appIdentifier"] as? String,
               let width = userInfo["width"] as? CGFloat,
               let height = userInfo["height"] as? CGFloat {
                
                // Find the window that matches this app identifier and update its size
                for window in openWindows {
                    let windowIdentifier = window.appInfo.bundleIdentifier + "_" + window.appInfo.id
                    if windowIdentifier == appIdentifier {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            window.size = CGSize(width: width, height: height)
                        }
                        break
                    }
                }
            }
        }
    }
}

// MARK: - Custom Window View

struct CustomWindowView: View {
    @ObservedObject var window: CustomWindow
    @ObservedObject var widgetManager: WidgetManager
    let isOptionHeld: Bool
    let onClose: (UUID) -> Void
    let onFocus: (CustomWindow) -> Void
    
    @State private var isCloseHovered = false
    
    // Overlay state
    @State private var showInfoPopover = false
    @State private var showResizePopover = false
    @State private var isResizing = false
    @State private var initialSize: CGSize = .zero
    @State private var initialDragPosition: CGPoint = .zero
    @State private var dashboardDragInitialPosition: CGPoint = .zero
    @State private var dashboardDragInitialMouseLocation: CGPoint = .zero
    @State private var dashboardDragMonitor: Any?
    
    var body: some View {
        ZStack {
            // Main Content
            VStack(spacing: 0) {
                // MARK: Title Bar
                if !widgetManager.borderlessFullScreenWidgets {
                    HStack {
                        Text(window.appInfo.displayName)
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                        
                        Spacer()
                        
                        Button(action: {
                            onClose(window.id)
                        }) {
                            Image(systemName: "xmark")
                                .background(
                                    Circle()
                                        .fill(isCloseHovered ? Color.red.opacity(0.8) : Color.clear)
                                        .frame(width: 15, height: 15)
                                )
                                .foregroundStyle(isCloseHovered ? .white : .white.opacity(0.8))
                        }
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 15, height: 15)
                        .foregroundStyle(.white)
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.1)) {
                                isCloseHovered = hovering
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: window.size.width)
                    .background(Color.black.opacity(0.8))
                .contentShape(Rectangle())
                    .onTapGesture {
                        onFocus(window)
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newPosition = CGPoint(
                                    x: window.position.x + value.translation.width,
                                    y: window.position.y + value.translation.height
                                )
                                window.position = newPosition
                                onFocus(window)
                            }
                    )
                }
                
                // MARK: WebView content
                WebView(appInfo: window.appInfo, tweaks: window.tweaks)
                    .frame(width: window.size.width, height: window.size.height)
                    .background(window.tweaks.transparentBackground ? Color.clear : Color(NSColor.windowBackgroundColor))
            }
            .background(window.tweaks.transparentBackground ? Color.clear : Color(NSColor.windowBackgroundColor))
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            
            // MARK: Overlay
            if isOptionHeld || showInfoPopover || showResizePopover {
                SharedWidgetOverlay(
                    appInfo: window.appInfo,
                    widgetManager: widgetManager,
                    isPinned: $window.isPinned,
                    isResizing: $isResizing,
                    currentSize: window.size,
                    showInfoPopover: $showInfoPopover,
                    showResizePopover: $showResizePopover,
                    onDragStart: {
                        initialDragPosition = window.position
                    },
                    onDrag: { delta in
                        window.position = CGPoint(
                            x: initialDragPosition.x + delta.width,
                            y: initialDragPosition.y + delta.height
                        )
                    },
                    onDragEnd: { },
                    onClose: {
                        onClose(window.id)
                    },
                    onResizeStart: {
                        isResizing = true
                        initialSize = window.size
                    },
                    onResizeChange: { delta in
                        let newWidth = max(100, initialSize.width + delta.width)
                        let newHeight = max(100, initialSize.height + delta.height)
                        window.size = CGSize(width: newWidth, height: newHeight)
                    },
                    onResizeEnd: {
                        isResizing = false
                        widgetManager.resizeWindow(for: window.appInfo, width: window.size.width, height: window.size.height)
                    }
                )
                .frame(
                    width: window.size.width,
                    height: widgetManager.borderlessFullScreenWidgets ? window.size.height : window.size.height + 28
                )
                .transition(.opacity)
            }
        }
        .position(
            x: window.position.x + window.size.width / 2,
            y: window.position.y + window.size.height / 2
        )
        .onTapGesture {
            onFocus(window)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardCustomWindowDragStart)) { notification in
            guard notification.appIdentifier == appIdentifier else { return }
            beginDashboardContentDrag()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardCustomWindowDragEnd)) { notification in
            guard notification.appIdentifier == appIdentifier else { return }
            endDashboardContentDrag()
        }
        .onDisappear {
            endDashboardContentDrag()
        }
    }

    private var appIdentifier: String {
        window.appInfo.bundleIdentifier + "_" + window.appInfo.id
    }

    private func beginDashboardContentDrag() {
        dashboardDragInitialPosition = window.position
        dashboardDragInitialMouseLocation = NSEvent.mouseLocation
        onFocus(window)

        if dashboardDragMonitor == nil {
            dashboardDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { event in
                handleDashboardContentDragEvent(event)
                return event
            }
        }
    }

    private func handleDashboardContentDragEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            let mouseLocation = NSEvent.mouseLocation
            window.position = CGPoint(
                x: dashboardDragInitialPosition.x + mouseLocation.x - dashboardDragInitialMouseLocation.x,
                y: dashboardDragInitialPosition.y - (mouseLocation.y - dashboardDragInitialMouseLocation.y)
            )
        case .leftMouseUp:
            endDashboardContentDrag()
        default:
            break
        }
    }

    private func endDashboardContentDrag() {
        if let monitor = dashboardDragMonitor {
            NSEvent.removeMonitor(monitor)
            dashboardDragMonitor = nil
        }
    }
}

private struct DashboardCloseBoxOverlay: View {
    @ObservedObject var window: CustomWindow
    @ObservedObject var widgetManager: WidgetManager
    let onClose: () -> Void
    @State private var isPressed = false

    private let closeBoxSize: CGFloat = 30

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: closeBoxSize, height: closeBoxSize)

            Image(isPressed ? "ecsb_closebox_pressed" : "ecsb_closebox")
                .resizable()
                .frame(width: closeBoxSize, height: closeBoxSize)
        }
            .contentShape(Rectangle())
            .position(closeButtonCenter)
            .onLongPressGesture(
                minimumDuration: 0,
                maximumDistance: closeBoxSize
            ) {
            } onPressingChanged: { pressing in
                isPressed = pressing
            }
            .highPriorityGesture(
                TapGesture().onEnded {
                    onClose()
                }
            )
    }

    private var closeButtonCenter: CGPoint {
        let titleBarOffset = widgetManager.borderlessFullScreenWidgets ? CGFloat(0) : CGFloat(-14)
        return CGPoint(
            x: window.position.x + window.appInfo.closeBoxInsetX,
            y: window.position.y + window.appInfo.closeBoxInsetY + titleBarOffset
        )
    }
}

private extension Notification {
    var appIdentifier: String? {
        userInfo?["appIdentifier"] as? String
    }
}

// MARK: - Keyboard Shortcut Catcher

struct KeyboardShortcutCatcher: NSViewRepresentable {
    let onCommandW: () -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.keyCode == 13 { // 13 = W
                onCommandW()
                return nil
            }
            return event
        }
        context.coordinator.monitor = monitor
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator { var monitor: Any? }
}

// MARK: - Option Key Monitor

struct OptionKeyMonitor: NSViewRepresentable {
    @Binding var isOptionHeld: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let isHeld = event.modifierFlags.contains(.option)
            // Animate only if changed
            if isHeld != self.isOptionHeld {
                // We must jump to main thread for UI updates? 
                // Event monitor is usually on main thread.
                // But modifying state during view update might handle it or need Dispatch.
                // Binding writes are generally safe but animation block needs care.
                // We can't access `self` effectively if it's a struct captured by value? 
                // Actually we can, but let's use a safer dispatch.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.isOptionHeld = isHeld
                    }
                }
            }
            return event
        }
        context.coordinator.monitor = monitor
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator { var monitor: Any? }
}

// MARK: - Preview

#Preview {
    let exampleApp = AppInfo(
        id: "8ee05b59",
        displayName: "Stickies",
        bundleIdentifier: "com.apple.widget.stickies",
        version: "2.0.0",
        htmlURL: URL(fileURLWithPath: "/Users/niko/Documents/code/widgetporting/Widgets_10.5/Stickies.wdgt/Stickies.html"),
        tempFolder: URL(fileURLWithPath: "/tmp/StickiesPreview/temp"),
        installedFolder: URL(fileURLWithPath: "/Users/niko/Documents/code/widgetporting/Widgets_10.5/Stickies.wdgt"),
        width: 223,
        height: 225,
        iconURL: URL(fileURLWithPath: "/Users/niko/Documents/code/widgetporting/Widgets_10.5/Stickies.wdgt/Icon.png"),
        languages: ["English", "German", "French", "I miss the misery"],
        closeBoxInsetX: 15,
        closeBoxInsetY: 15
    )

    let tweaks = WidgetTweaks(transparentBackground: true)
    let window = CustomWindow(appInfo: exampleApp, tweaks: tweaks, position: CGPoint(x: 130, y: 150))
    let widgetManager = PreviewWidgetManager()

    CustomWindowView(window: window, widgetManager: widgetManager, isOptionHeld: false, onClose: { _ in }, onFocus: { _ in })
}
