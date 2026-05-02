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
enum WidgetExportCoordinator {
    private enum SaveResult {
        case saved(URL)
        case canceled
        case failed(String)
    }

    static func exportWidget(
        at widgetURL: URL,
        format: WidgetExportFormat,
        supportDirectoryPath: String,
        progress: @escaping (String) -> Void,
        completion: @escaping (_ success: Bool, _ statusText: String, _ outputPath: String?) -> Void
    ) {
        progress("Starting export…")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let artifact = try WidgetExporter.exportWidgetToHTMLBundle(
                    widgetURL: widgetURL,
                    format: format,
                    supportDirectoryPath: supportDirectoryPath
                ) { message in
                    DispatchQueue.main.async {
                        progress(message)
                    }
                }

                DispatchQueue.main.async {
                    switch presentSavePanel(for: artifact) {
                    case .saved(let destinationURL):
                        completion(true, "Export complete.", destinationURL.path)
                        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
                    case .canceled:
                        completion(false, "Export canceled.", nil)
                    case .failed(let message):
                        completion(false, message, nil)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription, nil)
                }
            }
        }
    }

    private static func presentSavePanel(for artifact: WidgetExportArtifact) -> SaveResult {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = artifact.suggestedFileName
        panel.allowedContentTypes = [UTType(filenameExtension: artifact.format.outputExtension) ?? .data]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let response = panel.runModal()
        defer {
            try? FileManager.default.removeItem(at: artifact.workDirectory)
        }

        guard response == .OK, let destinationURL = panel.url else {
            return .canceled
        }

        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.copyItem(at: artifact.outputURL, to: destinationURL)
            return .saved(destinationURL)
        } catch {
            return .failed("Failed to save export: \(error.localizedDescription)")
        }
    }
}

@MainActor
final class WidgetExportViewModel: ObservableObject {
    @Published var statusText: String = "Drop a .wdgt file to create an export package."
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

        WidgetExportCoordinator.exportWidget(
            at: widgetURL,
            format: selectedFormat,
            supportDirectoryPath: supportPath
        ) { progress in
            self.statusText = progress
        } completion: { success, statusText, outputPath in
            self.isBusy = false
            self.statusText = statusText
            self.lastOutputPath = outputPath
        }
    }
}

struct WidgetExportWindow: View {
    @StateObject private var model: WidgetExportViewModel

    init(widgetManager: WidgetManager) {
        _model = StateObject(wrappedValue: WidgetExportViewModel(manager: widgetManager))
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 4) {
                Text("Widget Exporter")
                    .font(.title3.weight(.semibold))

                Text("EXPERIMENTAL")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.white)
                    .background(
                        Capsule()
                            .fill(Color.orange)
                    )
            }

            Text("Drop a .wdgt bundle to create a portable widget package.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Picker("Format", selection: $model.exportFormat) {
                ForEach(WidgetExportFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.isBusy)

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
        .padding(22)
        .frame(width: 470, height: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                .padding(8)
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
        window.title = "Widget Exporter"
        window.setContentSize(NSSize(width: 470, height: 300))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        htmlExportWindow = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.htmlExportWindow = nil
            }
        }
    }
}
