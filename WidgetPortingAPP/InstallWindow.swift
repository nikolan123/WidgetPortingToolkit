//
//  InstallWindow.swift
//  WidgetPortingAPP
//
//  Created by Niko on 14.09.25.
//

import SwiftUI
import AppKit
import Security

struct InstallWindow: View {
    @EnvironmentObject var manager: WidgetManager
    @State private var generatedID = String(UUID().uuidString.prefix(8))
    let parsedInfo: ParsedInfo
    let folderURL: URL
    @Binding var windowRef: NSWindow?
    
    @State private var showingTweaks = false
    @State private var initialTweaks: WidgetTweaks?
    @State private var isPortableHovered = false
    @State private var signatureStatus: String = "Checking Signature…"

    private var backgroundImage: NSImage? {
        NSImage(named: "ecsb_background_tile")
    }

    var body: some View {
        ZStack {
            // Patterned background
            if let img = backgroundImage {
                Image(nsImage: img)
                    .resizable(resizingMode: .tile)
                    .ignoresSafeArea()
            } else {
                Color.gray.opacity(0.15).ignoresSafeArea()
            }

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    if let iconURL = parsedInfo.iconURL,
                       let nsImage = NSImage(contentsOf: iconURL) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 75, height: 75)
                    } else {
                        Image(systemName: "app.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 75, height: 75)
                            .foregroundStyle(.blue)
                            .padding(6)
                            .background(Color.white.opacity(0.2))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(parsedInfo.displayName)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            
                            if isPortableHovered {
                                StatusBadge(text: "TEMP", color: .orange)
                                    .help("This widget will not be copied to your library. It will disappear on next launch.")
                            } else {
                                StatusBadge(text: generatedID, color: .green)
                            }
                        }
                        Text("\(parsedInfo.bundleIdentifier) • \(parsedInfo.version)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        
                        // Signature status
                        HStack(spacing: 4) {
                            Image(systemName: {
                                switch signatureStatus {
                                case "Signed": return "checkmark.seal.fill"
                                case "Tampered": return "xmark.seal.fill"
                                default: return "questionmark.circle.fill"
                                }
                            }())
                            .foregroundStyle(signatureStatus == "Signed" ? .green : (signatureStatus == "Tampered" ? .red : .gray))
                            .imageScale(.small)
                            
                            Text(signatureStatus)
                                .font(.subheadline)
                                .foregroundStyle(signatureStatus == "Signed" ? .green : (signatureStatus == "Tampered" ? .red : .secondary))
                        }
                    }
                    Spacer()
                }

                HStack {
                    Button("Options") {
                        showingTweaks = true
                        initialTweaks = manager.tweaks(for: parsedInfo.bundleIdentifier, id: generatedID)
                    }
                    Spacer()
                    Button("Portable") {
                        manager.loadWidget(from: folderURL)
                        windowRef?.close()
                    }
                    .onHover { hovering in
                        isPortableHovered = hovering
                    }
                    Button("Install") {
                        // use the same id when installing!
                        if let (dest, _) = manager.installWidget(from: folderURL, id: generatedID) {
                            manager.loadWidget(from: dest, openWindow: manager.autoOpenWidgetOnInstall, plistInfo: parsedInfo, id: generatedID)
                        }
                        windowRef?.close()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(width: 400, height: 150)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingTweaks) {
            if let tweaks = initialTweaks {
                TweaksSheet(
                    displayName: parsedInfo.displayName,
                    isInstallWindow: true,
                    initialTweaks: tweaks
                ) { updated in
                    manager.updateTweaks(for: parsedInfo.bundleIdentifier, id: generatedID, to: updated)
                } onReset: {
                    manager.resetTweaks(for: parsedInfo.bundleIdentifier, id: generatedID)
                }
            }
        }
        .onAppear {
            updateSignatureStatus()
        }
    }
    
    // MARK: - Signature Check
    private func updateSignatureStatus() {
        let codeSignatureFolder = folderURL.appendingPathComponent("_CodeSignature")
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: codeSignatureFolder.path) else {
            signatureStatus = "Not signed"
            return
        }

        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(folderURL as CFURL, [], &staticCode)
        guard status == errSecSuccess, let code = staticCode else {
            signatureStatus = "Tampered"
            return
        }

        let verifyStatus = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil)
        if verifyStatus == errSecSuccess {
            signatureStatus = "Signed"
        } else {
            signatureStatus = "Tampered"
        }
    }
}

struct DefaultLanguagePopup: View {
    @AppStorage("defaultWidgetLanguage") var defaultWidgetLanguage: String = ""
    @Environment(\.presentationMode) private var presentationMode
    
    private var backgroundImage: NSImage? {
        NSImage(named: "ecsb_background_tile")
    }

    var body: some View {
        ZStack {
            // Patterned background
            if let img = backgroundImage {
                Image(nsImage: img)
                    .resizable(resizingMode: .tile)
                    .ignoresSafeArea()
            } else {
                Color.gray.opacity(0.15).ignoresSafeArea()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Set Global Default Widget Language").font(.headline)
                HStack {
                    TextField("Default Language", text: $defaultWidgetLanguage)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Text(".lproj")
                }
//                HStack {
//                    Spacer()
//                    Button("Close") { presentationMode.wrappedValue.dismiss() }
//                        .keyboardShortcut(.defaultAction)
//                }
            }
            .padding()
        }
        .frame(width: 300, height: 75)
        .preferredColorScheme(.dark)
    }
}

// Preview
#Preview {
    let exampleApp = ParsedInfo(
        displayName: "Stickies",
        bundleIdentifier: "com.apple.widget.stickies",
        version: "2.0.0",
        mainHTML: "cat.html",
        width: 223,
        height: 225,
        iconURL: URL(fileURLWithPath: "/Users/niko/Documents/code/widgetporting/Widgets_10.5/Stickies.wdgt/Icon.png"),
        languages: ["English", "German", "French", "I miss the misery"]
    )

    InstallWindow(parsedInfo: exampleApp, folderURL: URL(fileURLWithPath: "/"), windowRef: .constant(nil))
}

#Preview {
    DefaultLanguagePopup()
}
