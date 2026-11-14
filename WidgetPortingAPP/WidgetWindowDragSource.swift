//
//  WidgetWindowDragSource.swift
//  WidgetPortingAPP
//
//  Created by Niko on 14.11.26.
//

import AppKit

final class WidgetWindowDragSource: NSObject, NSDraggingSource {
    private static let pasteboardType = NSPasteboard.PasteboardType("net.nikolan.widget-window")

    private weak var window: NSWindow?
    private let initialOrigin: NSPoint
    private let initialMouseLocation: NSPoint
    private let onEnd: () -> Void
    private var escapeMonitor: Any?
    private var activeSource: WidgetWindowDragSource?
    private var cancelled = false
    private(set) var isDragging = true

    init(window: NSWindow, initialOrigin: NSPoint, initialMouseLocation: NSPoint, onEnd: @escaping () -> Void) {
        self.window = window
        self.initialOrigin = initialOrigin
        self.initialMouseLocation = initialMouseLocation
        self.onEnd = onEnd
    }

    func begin(from view: NSView, event: NSEvent) {
        // A window can close during tracking; keep its drag source alive until AppKit finishes.
        activeSource = self
        let item = NSPasteboardItem()
        item.setString(UUID().uuidString, forType: Self.pasteboardType)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)

        // The live widget window follows the drag, so the session image stays invisible.
        let image = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true }
        let point = view.convert(event.locationInWindow, from: nil)
        draggingItem.setDraggingFrame(NSRect(origin: point, size: image.size), contents: image)

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelled = true
            }
            return event
        }
        let session = view.beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .delete
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        moveWindow(to: screenPoint)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let cancelled = cancelled || (operation.isEmpty && NSEvent.pressedMouseButtons & 1 != 0)
        finish(at: screenPoint, operation: operation, cancelled: cancelled)
    }

    func finish(at point: NSPoint, operation: NSDragOperation, cancelled: Bool) {
        guard isDragging else { return }
        defer { activeSource = nil }
        isDragging = false
        removeEscapeMonitor()

        let draggedWindow = window
        if cancelled {
            draggedWindow?.setFrameOrigin(initialOrigin)
        } else if !operation.contains(.delete) {
            moveWindow(to: point)
        }
        onEnd()
        if !cancelled && operation.contains(.delete), let draggedWindow {
            draggedWindow.close()
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                NSAnimationEffect.poof.show(centeredAt: point, size: .zero, completionHandler: {})
            }
        }
    }

    func abandon() {
        window = nil
        removeEscapeMonitor()
    }

    private func moveWindow(to point: NSPoint) {
        window?.setFrameOrigin(NSPoint(
            x: initialOrigin.x + point.x - initialMouseLocation.x,
            y: initialOrigin.y + point.y - initialMouseLocation.y
        ))
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    deinit {
        removeEscapeMonitor()
    }
}
