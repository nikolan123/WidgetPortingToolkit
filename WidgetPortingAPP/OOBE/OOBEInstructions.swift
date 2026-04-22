//
//  OOBEInstructions.swift
//  WidgetPortingAPP
//
//  Created by Niko on 28.11.25.
//

import SwiftUI

struct OOBEInstructionsContent: View {
    @EnvironmentObject var manager: WidgetManager
    @ObservedObject var coordinator: OOBECoordinator
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
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
                
            Text("Basic Instructions")
                .font(.custom("Lucida Grande", size: 20))
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            
            Text("Learn how to manage your widgets.")
                .font(.custom("Lucida Grande", size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            VStack(alignment: .leading, spacing: 12) {
                InstructionRow(
                    icon: "arrow.down.doc.fill",
                    text: "Drag and drop .wdgt files into the app to install widgets"
                )
                
                InstructionRow(
                    icon: "play.circle.fill",
                    text: "Click \"Open\" to launch a widget in its own window"
                )
                
                InstructionRow(
                    icon: "slider.horizontal.3",
                    text: "Use the tweaks menu to customize widget behavior"
                )
                
                InstructionRow(
                    icon: "globe",
                    text: "Select a language from the dropdown if available"
                )
                
                InstructionRow(
                    icon: "option",
                    text: "Hold option to show an overlay with widget info and controls"
                )
                
                InstructionRow(
                    icon: "trash",
                    text: "Remove widgets you no longer need with the trash button"
                )
            }
            .padding(.horizontal, 20)
        }
        .padding(30)
    }
}

struct InstructionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(.blue)
            
            Text(text)
                .font(.custom("Lucida Grande", size: 14))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}


#Preview {
    OOBEInstructionsContent(coordinator: OOBECoordinator())
        .environmentObject(WidgetManager())
        .frame(width: 650, height: 580)
        .background(
            Group {
                if let bg = NSImage(named: "ecsb_background_tile") {
                    Image(nsImage: bg)
                        .resizable(resizingMode: .tile)
                } else {
                    Color.clear
                }
            }
        )
}
