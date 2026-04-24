//
//  WidgetExportWindow.swift
//  WidgetPortingAPP
//
//  Created by Niko on 24.04.26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class WidgetExportViewModel: ObservableObject {
    @Published var statusText: String = "Drop a .wdgt file to export"
    @Published var isBusy: Bool = false
    @Published var lastOutputPath: String?
    @Published var exportFormat: WidgetExportFormat = .zip

    private let manager: WidgetManager

    init(manager: WidgetManager) {
        self.manager = manager
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !isBusy else { return true }

        for provider in providers where provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let fileURL = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    self.exportWidget(at: fileURL)
                }
            }
            return true
        }
        return false
    }

    private func exportWidget(at widgetURL: URL) {
        guard widgetURL.pathExtension.lowercased() == "wdgt" else {
            statusText = "Please drop a .wdgt bundle."
            return
        }

        isBusy = true
        statusText = "Starting export…"
        lastOutputPath = nil

        let supportPath = manager.supportDirectoryPath
        let selectedFormat = exportFormat

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let artifact = try WidgetExporter.exportWidgetToHTMLBundle(
                    widgetURL: widgetURL,
                    format: selectedFormat,
                    supportDirectoryPath: supportPath
                ) { progress in
                    DispatchQueue.main.async {
                        self.statusText = progress
                    }
                }

                DispatchQueue.main.async {
                    self.presentSavePanel(for: artifact)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.statusText = error.localizedDescription
                }
            }
        }
    }

    private func presentSavePanel(for artifact: WidgetExportArtifact) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = artifact.suggestedFileName
        panel.allowedContentTypes = [UTType(filenameExtension: artifact.format.outputExtension) ?? .data]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let response = panel.runModal()
        defer {
            try? FileManager.default.removeItem(at: artifact.workDirectory)
            isBusy = false
        }

        guard response == .OK, let destinationURL = panel.url else {
            statusText = "Export canceled."
            return
        }

        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.copyItem(at: artifact.outputURL, to: destinationURL)
            lastOutputPath = destinationURL.path
            statusText = "Export complete."
            NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
        } catch {
            statusText = "Failed to save export: \(error.localizedDescription)"
        }
    }
}

struct WidgetExportWindow: View {
    @StateObject private var model: WidgetExportViewModel

    init(widgetManager: WidgetManager) {
        _model = StateObject(wrappedValue: WidgetExportViewModel(manager: widgetManager))
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text("Export Widget to HTML")
                .font(.title3.weight(.semibold))

            Text("Drop a .wdgt bundle here")
                .foregroundStyle(.secondary)

            Picker("Format", selection: $model.exportFormat) {
                ForEach(WidgetExportFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.isBusy)
                Spacer()

            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            Text(model.statusText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity)

            if let output = model.lastOutputPath {
                Text(output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(width: 430, height: 260)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            model.handleDrop(providers: providers)
        }
    }
}

extension WidgetManager {
    func openHTMLExportWindow() {
        if let existing = htmlExportWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = WidgetExportWindow(widgetManager: self)
        let hosting = NSHostingController(rootView: content)

        let window = NSWindow(contentViewController: hosting)
        window.title = "Export .wdgt to HTML"
        window.setContentSize(NSSize(width: 430, height: 260))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.level = .floating

        htmlExportWindow = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.htmlExportWindow = nil
        }
    }
}
