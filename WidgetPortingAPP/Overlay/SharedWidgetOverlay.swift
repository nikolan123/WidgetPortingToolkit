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
        ZStack {
            Color.black.opacity(0.7)
                .cornerRadius(12)
            
            if isResizing {
                Text("\(Int(currentSize.width)) × \(Int(currentSize.height))")
                    .font(.system(size: 32, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            } else {
                VStack(spacing: 8) {
                    // Drag handle
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 40, height: 6)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle().size(width: 60, height: 30))
                        .gesture(
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
                        )
                        .padding(.top, 8)
                    
                    Spacer()
                    
                    Text(appInfo.displayName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    // Control buttons
                    VStack(spacing: 8) {
                        Button { isPinned.toggle() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isPinned ? "pin.fill" : "pin")
                                Text(isPinned ? "Pinned" : "Pin to Top")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isPinned ? Color.accentColor : Color.white.opacity(0.2))
                            .foregroundStyle(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button { showInfoPopover.toggle() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                Text("Info")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.2))
                            .foregroundStyle(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showInfoPopover) {
                            OverlayInfoPopover(appInfo: appInfo, isPresented: $showInfoPopover)
                        }
                        
                        Button { showResizePopover.toggle() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                Text("Resize")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.2))
                            .foregroundStyle(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showResizePopover) {
                            ResizePopover(appInfo: appInfo, widgetManager: widgetManager, liveUpdate: false)
                        }
                    }
                    .fixedSize()
                    .frame(width: 150)
                    
                    Spacer()
                }
            }
            
            // Close button
            if !isResizing {
                VStack {
                    HStack {
                        Button { onClose() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        Spacer()
                    }
                    Spacer()
                }
            }
            
            // Resize handle
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 12))
                        path.addLine(to: CGPoint(x: 12, y: 12))
                        path.addLine(to: CGPoint(x: 12, y: 0))
                    }
                    .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle().size(width: 30, height: 30))
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
                    .padding(10)
                }
            }
        }
    }
}
