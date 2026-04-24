//
//  TemplateOverlayController.swift
//  WidgetPlayerTemplate
//
//  Created by Niko on 24.04.26.
//

import AppKit
import SwiftUI

final class TemplateOverlayController {
    private weak var parentWindow: NSWindow?
    private var overlayWindow: NSWindow?
    private var mouseMonitor: Any?
    private var resizeObserver: Any?
    private var isCleaningUp = false
    private var parentIsClosing = false

    private let state: TemplateOverlayState
    private var isResizing = false
    private var initialMouseLocation: NSPoint = .zero
    private var initialContentSize: CGSize = .zero

    init(parentWindow: NSWindow, displayName: String) {
        self.parentWindow = parentWindow
        self.state = TemplateOverlayState(title: displayName)
        self.state.parentWindow = parentWindow

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: parentWindow,
            queue: .main
        ) { [weak self] _ in
            self?.updateOverlayFrame()
        }
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

        let hosting = NSHostingController(
            rootView: TemplateOverlayView(
                state: state,
                onClose: { [weak self] in
                    self?.parentWindow?.close()
                },
                onDragStart: { },
                onDrag: { [weak self] delta in
                    guard let self, let parent = self.parentWindow else { return }
                    var origin = parent.frame.origin
                    origin.x += delta.width
                    origin.y -= delta.height
                    parent.setFrameOrigin(origin)
                    self.updateOverlayFrame()
                },
                onDragEnd: { }
            )
        )
        let overlay = NSWindow(contentRect: parent.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        overlay.contentViewController = hosting
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.ignoresMouseEvents = false
        overlay.level = parent.level + 1
        overlay.alphaValue = 0

        parent.addChildWindow(overlay, ordered: .above)
        overlayWindow = overlay
        updateOverlayFrame()

        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            overlay.animator().alphaValue = 1
        }
    }

    private func hideOverlay() {
        guard let overlay = overlayWindow else { return }
        guard !isCleaningUp && !parentIsClosing else {
            removeOverlayWindow(overlay)
            return
        }

        if isResizing {
            isResizing = false
            state.isResizing = false
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            overlay.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, let overlay = self.overlayWindow else { return }
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

    private func handleMouseEvent(_ event: NSEvent) {
        guard let parent = parentWindow, let overlay = overlayWindow else { return }

        let mouseInScreen = overlay.convertPoint(toScreen: event.locationInWindow)
        let parentFrame = parent.frame
        let cornerSize: CGFloat = 30
        let inResizeCorner = mouseInScreen.x > parentFrame.maxX - cornerSize && mouseInScreen.y < parentFrame.minY + cornerSize

        switch event.type {
        case .leftMouseDown:
            if inResizeCorner {
                initialMouseLocation = mouseInScreen
                initialContentSize = currentViewportSize(in: parent)
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
            }
        default:
            break
        }
    }

    private func currentViewportSize(in window: NSWindow) -> CGSize {
        if let contentView = window.contentView {
            return contentView.bounds.size
        }
        return window.contentRect(forFrameRect: window.frame).size
    }

    func dismissOverlay() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if isResizing {
            isResizing = false
            state.isResizing = false
        }
        if let overlay = overlayWindow {
            removeOverlayWindow(overlay)
        }
    }

    func cleanup() {
        guard !isCleaningUp else { return }
        isCleaningUp = true

        dismissOverlay()
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
            resizeObserver = nil
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    func parentWindowWillClose() {
        guard !parentIsClosing else { return }
        parentIsClosing = true

        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
            resizeObserver = nil
        }
        if let overlay = overlayWindow {
            overlay.orderOut(nil)
            overlay.contentViewController = nil
            overlayWindow = nil
        }
        parentWindow = nil
    }

    deinit {
        cleanup()
    }
}
