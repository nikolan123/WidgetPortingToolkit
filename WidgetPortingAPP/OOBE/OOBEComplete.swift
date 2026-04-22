//
//  OOBEComplete.swift
//  WidgetPortingAPP
//
//  Created by Niko on 3.12.25.
//

import SwiftUI

struct OOBECompleteContent: View {
    @EnvironmentObject var manager: WidgetManager
    @ObservedObject var coordinator: OOBECoordinator
    let onFinish: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green.opacity(0.8), .green],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("You're All Set!")
                .font(.custom("Lucida Grande", size: 28))
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            
            Text("You're ready to start using Widget Porting Toolkit.")
                .font(.custom("Lucida Grande", size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            Button {
                if let url = URL(string: "https://widgets.nikolan.net/qsg.html") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "book.circle.fill")
                    Text("Quick Start Guide")
                }
            }
            .font(.custom("Lucida Grande", size: 13))
            .buttonStyle(.link)
            .foregroundColor(.blue)
            
        }
        .padding(40)
    }
}

#Preview {
    OOBECompleteContent(coordinator: OOBECoordinator(), onFinish: {})
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
