//
//  WidgetOverlayController.swift
//  WidgetPortingAPP
//
//  Created by Niko on 26.12.25.
//

import SwiftUI
import AppKit
import Combine

// MARK: - Overlay State

class WidgetOverlayState: ObservableObject {
    @Published var isPinned: Bool = false
    @Published var isResizing: Bool = false
    @Published var currentSize: CGSize = .zero
    @Published var showResizePopover: Bool = false
    @Published var showInfoPopover: Bool = false
    @Published var shouldCloseOverlay: Bool = false
    
    weak var parentWindow: NSWindow?
    weak var widgetManager: WidgetManager?
    var appInfo: AppInfo?
    
    func togglePin() {
        isPinned.toggle()
        parentWindow?.level = isPinned ? .floating : .normal
    }
    
    func closeWindow() {
        parentWindow?.close()
    }
}

// MARK: - Overlay View

struct WidgetOverlayView: View {
    let appInfo: AppInfo
    @ObservedObject var state: WidgetOverlayState
    @State private var dragStartOrigin: CGPoint = .zero
    @State private var dragStartMouseLocation: CGPoint = .zero

    var body: some View {
        if let widgetManager = state.widgetManager {
            SharedWidgetOverlay(
                appInfo: appInfo,
                widgetManager: widgetManager,
                isPinned: $state.isPinned,
                isResizing: $state.isResizing,
                currentSize: state.currentSize,
                showInfoPopover: $state.showInfoPopover,
                showResizePopover: $state.showResizePopover,
                onDragStart: {
                    guard let window = state.parentWindow else { return }
                    dragStartOrigin = window.frame.origin
                    dragStartMouseLocation = NSEvent.mouseLocation
                },
                onDrag: { _ in
                    guard let window = state.parentWindow else { return }

                    let currentMouseLocation = NSEvent.mouseLocation

                    window.setFrameOrigin(CGPoint(
                        x: dragStartOrigin.x + currentMouseLocation.x - dragStartMouseLocation.x,
                        y: dragStartOrigin.y + currentMouseLocation.y - dragStartMouseLocation.y
                    ))
                },
                onDragEnd: { },
                onClose: { state.closeWindow() },
                onResizeStart: { state.isResizing = true },
                onResizeChange: { _ in },
                onResizeEnd: { state.isResizing = false },
                useLocalCoordinates: true
            )
            .onChange(of: state.showInfoPopover) { isShowing in handlePopoverClose(isShowing) }
            .onChange(of: state.showResizePopover) { isShowing in handlePopoverClose(isShowing) }
        }
    }
    
    private func handlePopoverClose(_ isShowing: Bool) {
        if !isShowing && !NSEvent.modifierFlags.contains(.option) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !NSEvent.modifierFlags.contains(.option) {
                    state.shouldCloseOverlay = true
                }
            }
        }
    }
}

// MARK: - Overlay Controller

class WidgetOverlayController {
    private weak var parentWindow: NSWindow?
    private var overlayWindow: NSWindow?
    private var mouseMonitor: Any?
    private var windowObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private let appInfo: AppInfo
    private let state = WidgetOverlayState()
    private var isCleaningUp = false
    private var parentIsClosing = false
    
    private var isResizing = false
    private var initialMouseLocation: NSPoint = .zero
    private var initialContentSize: CGSize = .zero
    
    init(parentWindow: NSWindow, appInfo: AppInfo, widgetManager: WidgetManager) {
        self.parentWindow = parentWindow
        self.appInfo = appInfo
        state.parentWindow = parentWindow
        state.appInfo = appInfo
        state.widgetManager = widgetManager
        
        state.$shouldCloseOverlay
            .sink { [weak self] shouldClose in
                if shouldClose {
                    self?.hideOverlay()
                    self?.state.shouldCloseOverlay = false
                }
            }
            .store(in: &cancellables)
            
        state.$isPinned
            .sink { [weak self] isPinned in
                self?.parentWindow?.level = isPinned ? .floating : .normal
            }
            .store(in: &cancellables)
        
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: parentWindow, queue: .main
        ) { [weak self] _ in self?.updateOverlayFrame() }
    }
    
    func handleOptionKey(held: Bool) {
        guard let parent = parentWindow, parent.isKeyWindow else {
            if overlayWindow != nil { hideOverlay() }
            return
        }
        held ? showOverlay() : hideOverlay()
    }
    
    private func showOverlay() {
        guard overlayWindow == nil, let parent = parentWindow else { return }
        
        let hosting = NSHostingController(rootView: WidgetOverlayView(appInfo: appInfo, state: state))
        let overlay = NSWindow(contentRect: parent.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        
        overlay.contentViewController = hosting
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.ignoresMouseEvents = false
        overlay.isReleasedWhenClosed = false
        overlay.level = parent.level + 1
        overlay.alphaValue = 0
        
        parent.addChildWindow(overlay, ordered: .above)
        overlayWindow = overlay
        updateOverlayFrame()
        
        guard parent.isKeyWindow, mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            overlay.animator().alphaValue = 1
        }
    }
    
    private func handleMouseEvent(_ event: NSEvent) {
        guard let parent = parentWindow, let overlay = overlayWindow else { return }
        
        let mouseInScreen = overlay.convertPoint(toScreen: event.locationInWindow)
        let parentFrame = parent.frame
        let cornerSize: CGFloat = 30
        let isInResizeCorner = mouseInScreen.x > parentFrame.maxX - cornerSize && mouseInScreen.y < parentFrame.minY + cornerSize
        
        switch event.type {
        case .leftMouseDown:
            if isInResizeCorner {
                initialMouseLocation = mouseInScreen
                initialContentSize = parent.contentLayoutRect.size
                isResizing = true
                state.isResizing = true
                state.currentSize = initialContentSize
            }
        case .leftMouseDragged:
            if isResizing {
                let deltaX = mouseInScreen.x - initialMouseLocation.x
                let deltaY = mouseInScreen.y - initialMouseLocation.y
                let newWidth = max(100, initialContentSize.width + deltaX)
                let newHeight = max(100, initialContentSize.height - deltaY)
                parent.setContentSize(NSSize(width: newWidth, height: newHeight))
                overlay.setFrame(parent.frame, display: true)
                state.currentSize = CGSize(width: newWidth, height: newHeight)
            }
        case .leftMouseUp:
            if isResizing {
                isResizing = false
                state.isResizing = false
                let finalSize = parent.contentLayoutRect.size
                saveCurrentSize(finalSize)
            }
        default: break
        }
    }
    
    private func hideOverlay() {
        guard let overlay = overlayWindow else { return }
        guard !isCleaningUp && !parentIsClosing else {
            removeOverlayWindow(overlay)
            return
        }
        
        if isResizing, let parent = parentWindow {
            isResizing = false
            state.isResizing = false
            let finalSize = parent.contentLayoutRect.size
            saveCurrentSize(finalSize)
        }
        
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            overlay.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self, let overlay = self.overlayWindow else { return }
            self.removeOverlayWindow(overlay)
        })
    }

    private func removeOverlayWindow(_ overlay: NSWindow) {
        if !parentIsClosing {
            parentWindow?.removeChildWindow(overlay)
        }
        overlay.orderOut(nil)
        overlay.contentViewController = nil
        if overlayWindow === overlay {
            overlayWindow = nil
        }
    }
    
    private func updateOverlayFrame() {
        guard let parent = parentWindow, let overlay = overlayWindow else { return }
        overlay.setFrame(parent.frame, display: true)
    }
    
    func cleanup() {
        guard !isCleaningUp else { return }
        isCleaningUp = true

        dismissOverlay()
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }
    }

    private func dismissOverlay() {
        if isResizing, let parent = parentWindow {
            isResizing = false
            state.isResizing = false
            let finalSize = parent.contentLayoutRect.size
            saveCurrentSize(finalSize)
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let overlay = overlayWindow {
            removeOverlayWindow(overlay)
        }
    }

    func parentWindowWillClose() {
        guard !parentIsClosing else { return }
        parentIsClosing = true

        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }
        if let overlay = overlayWindow {
            overlay.orderOut(nil)
            overlay.contentViewController = nil
            overlayWindow = nil
        }
        parentWindow = nil
        state.parentWindow = nil
    }

    private func saveCurrentSize(_ size: CGSize) {
        Task { @MainActor in
            guard let widgetManager = state.widgetManager else { return }
            var tweaks = widgetManager.tweaks(for: appInfo.bundleIdentifier, id: appInfo.id)
            tweaks.customWidth = size.width
            tweaks.customHeight = size.height
            widgetManager.updateTweaks(for: appInfo.bundleIdentifier, id: appInfo.id, to: tweaks)
        }
    }
    
    deinit { cleanup() }
}
