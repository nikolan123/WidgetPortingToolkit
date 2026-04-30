//
//  StoreViewModel.swift
//  WidgetPortingAPP
//
//  Created by Niko on 30.04.26.
//

import AppKit
import Foundation

@MainActor
final class StoreViewModel: ObservableObject {
    @Published var query = ""
    @Published var sort = "name"
    @Published var selectedMode: StoreInstallMode = .normal
    @Published var widgets: [StoreWidget] = []
    @Published var selectedWidget: StoreWidget?
    @Published var statusText = ""
    @Published var isLoading = false
    @Published var isWorking = false
    @Published var page = 1
    @Published var pages = 1
    @Published var total = 0

    private let manager: WidgetManager
    private let pageSize = 30

    init(manager: WidgetManager) {
        self.manager = manager
    }

    var client: StoreAPIClient? {
        guard let baseURL = manager.normalizedWidgetStoreAPIBaseURL() else { return nil }
        return StoreAPIClient(baseURL: baseURL)
    }

    func refresh(resetPage: Bool = true) async {
        guard let client else {
            statusText = "Set a valid Store API URL first."
            return
        }
        if resetPage {
            page = 1
        }
        isLoading = true
        statusText = "Loading widgets..."
        do {
            let result = try await client.listWidgets(query: query, sort: sort, page: page, pageSize: pageSize)
            widgets = result.items
            selectedWidget = selectedWidget.flatMap { old in result.items.first(where: { $0.id == old.id }) } ?? result.items.first
            pages = max(1, result.pages)
            total = result.total
            statusText = "\(result.total) widgets"
        } catch {
            statusText = error.localizedDescription
        }
        isLoading = false
    }

    func nextPage() async {
        guard page < pages else { return }
        page += 1
        await refresh(resetPage: false)
    }

    func previousPage() async {
        guard page > 1 else { return }
        page -= 1
        await refresh(resetPage: false)
    }

    func selectRandomWidget() async {
        guard let client else {
            statusText = "Set a valid Store API URL first."
            return
        }
        isLoading = true
        statusText = "Finding a random widget..."
        do {
            let firstPage = try await client.listWidgets(query: query, sort: sort, page: 1, pageSize: pageSize)
            guard firstPage.total > 0, firstPage.pages > 0 else {
                widgets = []
                selectedWidget = nil
                pages = 1
                page = 1
                total = 0
                statusText = "No widgets found."
                isLoading = false
                return
            }

            let randomPage = Int.random(in: 1...max(1, firstPage.pages))
            let result = randomPage == 1
                ? firstPage
                : try await client.listWidgets(query: query, sort: sort, page: randomPage, pageSize: pageSize)

            widgets = result.items
            selectedWidget = result.items.randomElement()
            page = result.page
            pages = max(1, result.pages)
            total = result.total
            statusText = "Random pick from page \(result.page)."
        } catch {
            statusText = error.localizedDescription
        }
        isLoading = false
    }

    func sendSelectedToApp() async {
        guard let widget = selectedWidget else { return }
        await sendToApp(widget, mode: selectedMode)
    }

    func sendToApp(_ widget: StoreWidget, mode: StoreInstallMode) async {
        guard let client else {
            statusText = "Set a valid Store API URL first."
            return
        }
        isWorking = true
        statusText = "Downloading \(widget.title)..."
        do {
            let zipURL = try await client.downloadWidget(widget)
            statusText = "Extracting \(widget.title)..."
            let bundleURL = try await Task.detached {
                try StoreArchiveHelper.extractWidgetBundle(from: zipURL)
            }.value
            statusText = "Preparing \(widget.title)..."
            switch mode {
            case .normal:
                if let (dest, id) = manager.installWidget(from: bundleURL) {
                    manager.loadWidget(from: dest, openWindow: manager.autoOpenWidgetOnInstall, id: id)
                    statusText = "Installed \(widget.title)."
                } else {
                    statusText = "Install cancelled or failed."
                }
            case .portable:
                manager.loadWidget(from: bundleURL, openWindow: manager.autoOpenWidgetOnInstall)
                statusText = "Opened \(widget.title) as portable."
            case .exporter:
                manager.openStoreExportWindow(for: bundleURL)
                statusText = "Sent \(widget.title) to exporter."
            }
        } catch {
            statusText = error.localizedDescription
        }
        isWorking = false
    }

    func downloadSelectedToFolder() async {
        guard let widget = selectedWidget else { return }
        await downloadToFolder(widget)
    }

    func downloadToFolder(_ widget: StoreWidget) async {
        guard let client else {
            statusText = "Set a valid Store API URL first."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder to save the widget zip."
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        isWorking = true
        statusText = "Downloading \(widget.title)..."
        do {
            let zipURL = try await client.downloadWidget(widget)
            let destination = uniqueDestination(in: folder, suggestedName: zipURL.lastPathComponent)
            try FileManager.default.copyItem(at: zipURL, to: destination)
            statusText = "Saved to \(destination.path)."
        } catch {
            statusText = error.localizedDescription
        }
        isWorking = false
    }

    func openSelectedInBrowser() {
        guard let widget = selectedWidget, let client else { return }
        if let detailURL = try? client.absoluteURL(for: widget.links.detail) {
            NSWorkspace.shared.open(detailURL)
        }
    }

    func iconURL(for widget: StoreWidget) -> URL? {
        try? client?.absoluteURL(for: widget.links.icon)
    }

    func screenshotURL(for widget: StoreWidget) -> URL? {
        guard widget.screenshot?.status == "ok" else { return nil }
        let path = widget.screenshot?.url ?? widget.links.screenshot
        return try? client?.absoluteURL(for: path)
    }

    private func uniqueDestination(in folder: URL, suggestedName: String) -> URL {
        let base = suggestedName.isEmpty ? "widget.zip" : suggestedName
        var destination = folder.appendingPathComponent(base)
        guard FileManager.default.fileExists(atPath: destination.path) else { return destination }

        let ext = destination.pathExtension
        let stem = destination.deletingPathExtension().lastPathComponent
        for index in 2...999 {
            let name = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            destination = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                return destination
            }
        }
        return folder.appendingPathComponent("\(UUID().uuidString).zip")
    }
}
