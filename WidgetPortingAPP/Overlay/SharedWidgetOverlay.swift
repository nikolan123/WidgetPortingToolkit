//
//  SharedWidgetOverlay.swift
//  WidgetPortingAPP
//
//  Created by Niko on 26.12.25.
//

import SwiftUI

struct SharedWidgetOverlay: View {
    let appInfo: AppInfo
    @ObservedObject var widgetManager: WidgetManager
    
    @Binding var isPinned: Bool
    @Binding var isResizing: Bool
    let currentSize: CGSize
    
    @Binding var showInfoPopover: Bool
    @Binding var showResizePopover: Bool
    
    let onDragStart: () -> Void
    let onDrag: (CGSize) -> Void
    let onDragEnd: () -> Void
    let onClose: () -> Void
    let onResizeStart: () -> Void
    let onResizeChange: (CGSize) -> Void
    let onResizeEnd: () -> Void
    
    var useLocalCoordinates: Bool = false
    
    @State private var internalIsResizing = false
    @State private var internalIsDragging = false
    
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 164 || geometry.size.height < 224
            let minimal = geometry.size.width < 96 || geometry.size.height < 96
            let horizontal = geometry.size.width >= 360 && geometry.size.height >= 44 && geometry.size.height < 140
            let cornerSize = min(32, min(geometry.size.width, geometry.size.height) / 3)

            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.7))
                    .gesture(moveGesture)

                if isResizing {
                    Text("\(Int(currentSize.width)) × \(Int(currentSize.height))")
                        .font(.system(size: compact ? 22 : 32, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .padding(8)
                        .padding(.bottom, cornerSize)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if horizontal {
                    ZStack(alignment: .top) {
                        dragHandle(width: 40, height: 14)

                        HStack(spacing: 12) {
                            closeButton

                            Text(appInfo.displayName)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 6) {
                                controls(showLabels: geometry.size.width >= 600)
                            }
                            .frame(width: geometry.size.width >= 600 ? 344 : 112)
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                        .padding(.trailing, cornerSize)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if minimal {
                    Menu {
                        Button(isPinned ? "Unpin" : "Pin to Top") { isPinned.toggle() }
                        Button("Info") { showInfoPopover = true }
                        Button("Resize") { showResizePopover = true }
                        Divider()
                        Button("Close Widget", action: onClose)
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.white)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .environment(\.colorScheme, .dark)
                    .frame(width: min(32, geometry.size.width), height: min(24, geometry.size.height))
                    .help("Widget controls")
                    .accessibilityLabel("Widget controls")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(spacing: 0) {
                        ZStack(alignment: .leading) {
                            dragHandle(
                                width: min(40, geometry.size.width - 68),
                                height: 24
                            )
                            .frame(maxWidth: .infinity)

                            closeButton
                        }
                        Spacer(minLength: 4)

                        if !compact || geometry.size.height >= 140 {
                            Text(appInfo.displayName)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.bottom, compact ? 8 : 12)
                        }

                        if compact {
                            HStack(spacing: 4) {
                                controls(showLabels: false)
                            }
                            .frame(maxWidth: 180)
                        } else {
                            VStack(spacing: 6) {
                                controls(showLabels: true)
                            }
                            .frame(maxWidth: 150)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(compact ? 6 : 10)
                    .padding(.bottom, cornerSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: min(12, cornerSize / 2), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: cornerSize, height: cornerSize)
                    .contentShape(Rectangle())
                    .help("Drag to resize widget")
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                if !internalIsResizing {
                                    internalIsResizing = true
                                    onResizeStart()
                                }
                                onResizeChange(value.translation)
                            }
                            .onEnded { _ in
                                internalIsResizing = false
                                onResizeEnd()
                            }
                    )
                    .popover(isPresented: $showResizePopover) {
                        ResizePopover(appInfo: appInfo, widgetManager: widgetManager, liveUpdate: false)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .popover(isPresented: $showInfoPopover) {
            OverlayInfoPopover(appInfo: appInfo, isPresented: $showInfoPopover)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .frame(width: 24, height: 24)
                .foregroundStyle(.white.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help("Close Widget")
        .accessibilityLabel("Close Widget")
    }

    private func dragHandle(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.4))
            .frame(width: width, height: 4)
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(moveGesture)
            .help("Drag to move widget")
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: useLocalCoordinates ? .local : .global)
            .onChanged { value in
                if !internalIsDragging {
                    internalIsDragging = true
                    onDragStart()
                }
                onDrag(value.translation)
            }
            .onEnded { _ in
                internalIsDragging = false
                onDragEnd()
            }
    }

    @ViewBuilder
    private func controls(showLabels: Bool) -> some View {
        Button { isPinned.toggle() } label: {
            controlLabel(isPinned ? "Pinned" : "Pin to Top", image: isPinned ? "pin.fill" : "pin", showLabels: showLabels)
                .background(isPinned ? Color.accentColor : Color.white.opacity(0.2))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Unpin" : "Pin to Top")
        .accessibilityLabel(isPinned ? "Unpin" : "Pin to Top")

        Button { showInfoPopover.toggle() } label: {
            controlLabel("Info", image: "info.circle", showLabels: showLabels)
                .background(Color.white.opacity(0.2))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help("Widget Info")
        .accessibilityLabel("Widget Info")

        Button { showResizePopover.toggle() } label: {
            controlLabel("Resize", image: "arrow.up.left.and.arrow.down.right", showLabels: showLabels)
                .background(Color.white.opacity(0.2))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help("Resize Widget")
        .accessibilityLabel("Resize Widget")
    }

    private func controlLabel(_ title: String, image: String, showLabels: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: image)
            if showLabels {
                Text(title)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }
}
