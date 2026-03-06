//
//  FocusRingDisabler.swift
//  WidgetPortingAPP
//
//  Created by Niko on 20.09.25.
//

import SwiftUI

extension View {
    // Disables the focus ring for any view on macOS 12+
    func focusRingDisabled() -> some View {
        self.background(FocusRingDisabler())
    }
}

private struct FocusRingDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let containerView = view.superview?.superview {
                containerView.setValue(NSFocusRingType.none.rawValue, forKey: "focusRingType")
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
