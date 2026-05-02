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
    @State private var showingExportSheet = false
    @State private var initialTweaks: WidgetTweaks?
    @State private var selectedExportFormat: WidgetExportFormat = .zip
    @State private var isPortableHovered = false
    @State private var signatureStatus: String = "Checking Signature…"

    private var backgroundImage: NSImage? {
        NSImage(named: "ecsb_background_tile")
    }

    private var exportFormats: [WidgetExportFormat] {
        WidgetExportFormat.allCases
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
                    Menu {
                        Section("Export As") {
                            ForEach(exportFormats) { format in
                                Button(format.displayName) {
                                    exportWidget(as: format)
                                }
                            }
                        }
                    } label: {
                        Text("Portable")
                    }
                    primaryAction: {
                        loadPortableWidget()
                    }
                    .onHover { hovering in
                        isPortableHovered = hovering
                    }
                    Button("Install") {
                        installWidget()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
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
        .sheet(isPresented: $showingExportSheet) {
            InstallExportSheet(
                widgetURL: folderURL,
                initialFormat: selectedExportFormat
            )
            .environmentObject(manager)
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

    private func installWidget() {
        // Use the same ID when installing and loading.
        if let (dest, _) = manager.installWidget(from: folderURL, id: generatedID) {
            manager.loadWidget(from: dest, openWindow: manager.autoOpenWidgetOnInstall, plistInfo: parsedInfo, id: generatedID)
        }
        windowRef?.close()
    }

    private func loadPortableWidget() {
        manager.loadWidget(from: folderURL)
        windowRef?.close()
    }

    private func exportWidget(as format: WidgetExportFormat) {
        selectedExportFormat = format
        showingExportSheet = true
    }
}

struct InstallExportSheet: View {
    @EnvironmentObject private var manager: WidgetManager
    @Environment(\.dismiss) private var dismiss

    let widgetURL: URL
    let initialFormat: WidgetExportFormat

    @State private var selectedFormat: WidgetExportFormat
    @State private var statusText = "Preparing export…"
    @State private var lastOutputPath: String?
    @State private var isBusy = false
    @State private var hasStartedInitialExport = false

    init(widgetURL: URL, initialFormat: WidgetExportFormat) {
        self.widgetURL = widgetURL
        self.initialFormat = initialFormat
        _selectedFormat = State(initialValue: initialFormat)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Export Widget")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            Text(widgetURL.lastPathComponent)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Format", selection: $selectedFormat) {
                ForEach(WidgetExportFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.menu)
            .disabled(isBusy)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity)

            if let lastOutputPath {
                Text(lastOutputPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            }

            HStack {
                Spacer()
                Button(isBusy ? "Exporting…" : "Export") {
                    startExport()
                }
                .disabled(isBusy)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 220)
        .preferredColorScheme(.dark)
        .onAppear {
            guard !hasStartedInitialExport else { return }
            hasStartedInitialExport = true
            startExport()
        }
    }

    private func startExport() {
        isBusy = true
        statusText = "Starting export…"
        lastOutputPath = nil

        WidgetExportCoordinator.exportWidget(
            at: widgetURL,
            format: selectedFormat,
            supportDirectoryPath: manager.supportDirectoryPath
        ) { progress in
            statusText = progress
        } completion: { _, statusText, outputPath in
            isBusy = false
            self.statusText = statusText
            lastOutputPath = outputPath
        }
    }
}

struct DefaultLanguagePopup: View {
    @EnvironmentObject var manager: WidgetManager
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
                    TextField("Default Language", text: $manager.defaultWidgetLanguage)
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
        languages: ["English", "German", "French", "I miss the misery"],
        closeBoxInsetX: 15,
        closeBoxInsetY: 15
    )

    InstallWindow(parsedInfo: exampleApp, folderURL: URL(fileURLWithPath: "/"), windowRef: .constant(nil))
}

#Preview {
    DefaultLanguagePopup()
        .environmentObject(WidgetManager())
}
