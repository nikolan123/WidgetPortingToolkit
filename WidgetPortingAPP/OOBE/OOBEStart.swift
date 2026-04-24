//
//  OOBEStart.swift
//  WidgetPortingAPP
//
//  Created by Niko on 28.11.25.
//

import SwiftUI

struct OOBEWelcomeContent: View {
    @EnvironmentObject var manager: WidgetManager
    @ObservedObject var coordinator: OOBECoordinator
    
    var body: some View {
        VStack(spacing: 16) {
            Image("dashboard_2015")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.8), .accentColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Welcome to Widget Porting Toolkit!")
                    .font(.custom("Lucida Grande", size: 22))
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                
            Text("Let's get your environment set up for using widgets.")
                .font(.custom("Lucida Grande", size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .padding(40)
    }
}


#Preview {
    OOBEWelcomeContent(coordinator: OOBECoordinator())
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
