//
//  TemplateOverlayShared.swift
//  WidgetPlayerTemplate
//
//  Created by Niko on 24.04.26.
//

import AppKit
import SwiftUI
import Combine

final class TemplateOverlayState: ObservableObject {
    @Published var isPinned = false
    @Published var isResizing = false
    @Published var currentSize: CGSize = .zero

    let title: String
    weak var parentWindow: NSWindow?

    init(title: String) {
        self.title = title
    }
}

struct TemplateOverlayView: View {
    @ObservedObject var state: TemplateOverlayState
    let onClose: () -> Void
    let onDragStart: () -> Void
    let onDrag: (CGSize) -> Void
    let onDragEnd: () -> Void

    @State private var isDragging = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .cornerRadius(12)

            if state.isResizing {
                Text("\(Int(state.currentSize.width)) × \(Int(state.currentSize.height))")
                    .font(.system(size: 26, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            } else {
                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 40, height: 6)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle().size(width: 60, height: 30))
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in
                                    if !isDragging {
                                        isDragging = true
                                        onDragStart()
                                    }
                                    onDrag(value.translation)
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    onDragEnd()
                                }
                        )
                        .padding(.top, 8)

                    Spacer()

                    Text(state.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        Button(state.isPinned ? "Pinned" : "Pin") {
                            state.isPinned.toggle()
                            state.parentWindow?.level = state.isPinned ? .floating : .normal
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(state.isPinned ? Color.accentColor : Color.white.opacity(0.2))
                        .foregroundStyle(.white)
                        .cornerRadius(6)

                        Button("Close") {
                            onClose()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .foregroundStyle(.white)
                        .cornerRadius(6)
                    }
                    .padding(.bottom, 10)

                    Spacer()
                }
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 28, height: 28)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}
