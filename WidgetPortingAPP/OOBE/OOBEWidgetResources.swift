//
//  OOBEWidgetResources.swift
//  WidgetPortingAPP
//
//  Created by Niko on 28.11.25.
//

import SwiftUI

struct OOBEWidgetResourcesContent: View {
    @EnvironmentObject var manager: WidgetManager
    @ObservedObject var coordinator: OOBECoordinator
    
    @State private var statusMessage: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.fill")
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
            
            Text("Setup Widget Resources")
                .font(.custom("Lucida Grande", size: 22))
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            
            Text("Select the WidgetResources folder to enable widget functionality.")
                .font(.custom("Lucida Grande", size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            VStack(spacing: 6) {
                Button {
                    if let url = URL(string: "https://widgets.nikolan.net/widgetresources_guide") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "book.circle.fill")
                        Text("How to obtain WidgetResources yourself")
                    }
                }
                .font(.custom("Lucida Grande", size: 13))
                .buttonStyle(.link)
                .foregroundColor(.blue)
                
                Button {
                    browseForWidgetResources()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.circle.fill")
                        Text("Browse for folder manually")
                    }
                }
                .font(.custom("Lucida Grande", size: 13))
                .buttonStyle(.link)
                .foregroundColor(.blue)
            }
            
            HStack(spacing: 8) {
                if !coordinator.userSelectedResourcePath.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(coordinator.userSelectedResourcePath)
                        .font(.custom("Lucida Grande", size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if !statusMessage.isEmpty {
                    Image(systemName: "gear.circle.fill")
                        .foregroundStyle(.blue)
                    Text(statusMessage)
                        .font(.custom("Lucida Grande", size: 13))
                        .foregroundColor(.secondary)

                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("No folder selected")
                        .font(.custom("Lucida Grande", size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        !coordinator.userSelectedResourcePath.isEmpty
                            ? Color.green.opacity(0.1)       // path selected
                            : (!statusMessage.isEmpty
                                ? Color.blue.opacity(0.1)   // downloading
                                : Color.orange.opacity(0.1) // nothing selected
                              )
                    )
            )
            
            Button("Automatically Download") {
                coordinator.userSelectedResourcePath = ""
                startDownload()
            }
            .font(.custom("Lucida Grande", size: 15))
            .buttonStyle(.bordered)
            .controlSize(.large)
            
            HStack {
                Image(systemName: "shield.pattern.checkered")
                Text("This action will connect to widgets.nikolan.net")
            }
            .font(.custom("Lucida Grande", size: 10))
            .foregroundStyle(.gray)
        }
        .padding(40)
        .onAppear {
            if coordinator.userSelectedResourcePath.isEmpty {
                let installedSupport = WidgetManager.installedSupportDirectoryURL()
                if manager.supportDirectoryPath == installedSupport.path {
                    manager.supportDirectoryPath = ""
                }
            }
        }
    }
    
    private func browseForWidgetResources() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the WidgetResources folder"
        panel.prompt = "Select"
        
        if panel.runModal() == .OK, let url = panel.url {
            if manager.installSupportDirectory(from: url) != nil {
                coordinator.userSelectedResourcePath = url.path
            }
        }
    }
    
    private func startDownload() {
        guard let url = URL(string: "https://widgets.nikolan.net/WidgetResources_10.9.5.zip") else { return }
        
        downloadAndExtractWidgetResources(from: url, statusHandler: { message in
            statusMessage = message
        }, completion: { dir in
            if let dir = dir {
                let widgetResourcesDir = dir.appendingPathComponent("WidgetResources")
                if let _ = manager.installSupportDirectory(from: widgetResourcesDir) {
                    // coordinator.userSelectedResourcePath = installedURL.path
                    coordinator.userSelectedResourcePath = "WidgetResources installed!"
                    statusMessage = ""
                }
            }
        })
    }
}

#Preview {
OOBEWidgetResourcesContent(coordinator: OOBECoordinator())
    .environmentObject(WidgetManager())
    .frame(width: 650, height: 580)
    .background(
        Image(nsImage: NSImage(named: "ecsb_background_tile")!)
            .resizable(resizingMode: .tile)
    )
}
