//
//  WidgetSelectionDownloadButton.swift
//  WidgetPortingAPP
//
//  Created by Niko on 7.11.26.
//

import SwiftUI

struct WidgetSelectionDownloadButton: View {
    let manager: WidgetManager
    var title: LocalizedStringKey = "Download Widget Selection"
    var isActive: () -> Bool = { true }
    var statusFont: Font = .caption

    @State private var download: (id: UUID, task: URLSessionDownloadTask)?
    @State private var downloadStatus = ""
    @State private var selectionInstalled = false

    var body: some View {
        VStack(spacing: 6) {
            Button(title, action: downloadWidgetSelection)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(download != nil || selectionInstalled)

            Text(downloadStatus)
                .font(statusFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 34)
                .help(downloadStatus)
        }
        .onChange(of: isActive()) { active in
            if !active {
                cancelDownload()
            }
        }
        .onDisappear(perform: cancelDownload)
    }

    private func downloadWidgetSelection() {
        guard isActive(), download == nil, !selectionInstalled,
              let url = URL(string: "https://widgets.nikolan.net/widgetselection.zip") else { return }
        guard !manager.supportDirectoryPath.isEmpty else {
            downloadStatus = "Install Widget Resources in setup or from Options > Install Support Directory first."
            return
        }

        let id = UUID()
        downloadStatus = "Downloading the widget selection…"
        let task = downloadAndExtractZip(from: url, statusHandler: { message in
            guard download?.id == id else { return }
            downloadStatus = message
        }, completion: { directory in
            defer {
                if let directory {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
            guard download?.id == id else { return }
            download = nil
            guard isActive(), let directory else { return }

            do {
                let failed = try manager.installWidgetSelection(from: directory)
                selectionInstalled = failed.isEmpty
                downloadStatus = selectionInstalled
                    ? "Widget selection installed."
                    : "Could not install \(failed.joined(separator: ", ")). Try again."
            } catch {
                downloadStatus = "Could not install the widget selection. \(error.localizedDescription)"
            }
        })
        download = (id, task)
    }

    private func cancelDownload() {
        guard let download else { return }
        self.download = nil
        download.task.cancel()
        downloadStatus = ""
    }
}
