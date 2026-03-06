//
//  OverlayInfoPopover.swift
//  WidgetPortingAPP
//
//  Info popover displayed in the overlay
//

import SwiftUI

struct OverlayInfoPopover: View {
    let appInfo: AppInfo
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let iconURL = appInfo.iconURL,
                   let nsImage = NSImage(contentsOf: iconURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .frame(width: 40, height: 40)
                }
                
                Text(appInfo.displayName)
                    .font(.headline)
                
                Spacer()
                
                if !appInfo.installedFolder.path.hasPrefix(WidgetManager.installedWidgetsDirectoryURL().path) {
                    StatusBadge(text: "TEMP", color: .orange)
                        .help("This widget has not been copied to your library. It will disappear on next launch.")
                } else {
                    StatusBadge(text: appInfo.id, color: .green)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(appInfo.bundleIdentifier) • \(appInfo.version)")
                Text("Supported Languages: \(appInfo.languages.joined(separator: ", "))")
                Text("Installed in \(appInfo.installedFolder.path)")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Close") { isPresented = false }
            }
        }
        .padding()
        .frame(width: 320)
    }
}
