//
//  OOBEFullScreen.swift
//  WidgetPortingAPP
//
//  Created by Niko on 28.11.25.
//

import SwiftUI

struct OOBEFullScreenContent: View {
    @EnvironmentObject var manager: WidgetManager
    @ObservedObject var coordinator: OOBECoordinator
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.8), .accentColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
            Text("Full Screen Mode")
                .font(.custom("Lucida Grande", size: 20))
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            
            Text("Experience widgets like the classic Dashboard.")
                .font(.custom("Lucida Grande", size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            VStack(alignment: .leading, spacing: 12) {
                FullScreenInstructionRow(
                    icon: "arrow.up.left.and.arrow.down.right",
                    shortcut: "Maximize",
                    text: "Enter/exit full screen mode"
                )
                
                FullScreenInstructionRow(
                    icon: "plus.circle.fill",
                    shortcut: "Click +",
                    text: "Add widgets to the dashboard"
                )
                
                FullScreenInstructionRow(
                    icon: "minus.circle.fill",
                    shortcut: "Click −",
                    text: "Does nothing"
                )
                
                FullScreenInstructionRow(
                    icon: "hand.point.up.left.fill",
                    shortcut: "Hold ⌥",
                    text: "Show control overlay"
                )
                
                FullScreenInstructionRow(
                    icon: "xmark.circle.fill",
                    shortcut: "⌘W",
                    text: "Close focused widget"
                )
            }
            .padding(.horizontal, 20)
        }
        .padding(30)
    }
}

struct FullScreenInstructionRow: View {
    let icon: String
    let shortcut: String
    let text: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(.blue)
            
            Text(shortcut)
                .font(.custom("Lucida Grande", size: 13))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .frame(width: 80, alignment: .leading)
            
            Text(text)
                .font(.custom("Lucida Grande", size: 14))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}


#Preview {
    OOBEFullScreenContent(coordinator: OOBECoordinator())
        .environmentObject(WidgetManager())
        .frame(width: 650, height: 580)
        .background(
            Image(nsImage: NSImage(named: "ecsb_background_tile")!)
                .resizable(resizingMode: .tile)
        )
}
