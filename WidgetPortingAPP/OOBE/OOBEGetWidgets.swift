//
//  OOBEGetWidgets.swift
//  WidgetPortingAPP
//
//  Created by Niko on 28.11.25.
//

import SwiftUI

struct OOBEGetWidgetsContent: View {
    @EnvironmentObject var manager: WidgetManager
    @ObservedObject var coordinator: OOBECoordinator
    @State private var widgetSourceURL: String = "https://widgets.nikolan.net/getwidgets.html"
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down.fill")
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
                
                Text("Get Widgets")
                    .font(.custom("Lucida Grande", size: 22))
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                
                Text("Download classic Dashboard widgets to use with this app.")
                    .font(.custom("Lucida Grande", size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                
                Button {
                    if let url = URL(string: widgetSourceURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link.circle.fill")
                        Text(widgetSourceURL)
                            .font(.custom("Lucida Grande", size: 14))
                    }
                }
                .buttonStyle(.link)
                .foregroundColor(.blue)
                
            Text("Drag and drop .wdgt files into the app to install them.")
                .font(.custom("Lucida Grande", size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.top, 4)
        }
        .padding(40)
    }
}

#Preview {
    OOBEGetWidgetsContent(coordinator: OOBECoordinator())
        .environmentObject(WidgetManager())
        .frame(width: 650, height: 580)
        .background(
            Image(nsImage: NSImage(named: "ecsb_background_tile")!)
                .resizable(resizingMode: .tile)
        )
}
