//
//  StoreWindow.swift
//  WidgetPortingAPP
//
//  Created by Niko on 30.04.26.
//

import SwiftUI

struct StoreWindow: View {
    @EnvironmentObject var manager: WidgetManager
    @StateObject private var viewModel: StoreViewModel

    init(manager: WidgetManager) {
        _viewModel = StateObject(wrappedValue: StoreViewModel(manager: manager))
    }

    var body: some View {
        ZStack {
            if let bgImage = NSImage(named: "ecsb_background_tile") {
                Image(nsImage: bgImage)
                    .resizable(resizingMode: .tile)
                    .ignoresSafeArea()
            } else {
                Color.gray.opacity(0.15).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                toolbar
                Divider()
                HStack(spacing: 0) {
                    listPane
                    Divider()
                    detailPane
                }
                Divider()
                statusBar
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .preferredColorScheme(.dark)
        .task {
            await viewModel.refresh()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text("Widget Store")
                .font(.custom("Lucida Grande", size: 18).weight(.semibold))
            TextField("Search", text: $viewModel.query)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 260)
                .onSubmit {
                    Task { await viewModel.refresh() }
                }
            Picker("Sort", selection: $viewModel.sort) {
                Text("Name").tag("name")
                Text("Newest").tag("newest")
                Text("Identifier").tag("identifier")
                Text("Shuffle").tag("shuffle")
            }
            .frame(width: 130)
            .onChange(of: viewModel.sort) { _ in
                Task { await viewModel.refresh() }
            }
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .disabled(viewModel.isLoading)
            Button {
                Task { await viewModel.selectRandomWidget() }
            } label: {
                Image(systemName: "shuffle")
            }
            .help("Random widget")
            .disabled(viewModel.isLoading || viewModel.isWorking)
            Spacer()
            Button {
                manager.openStoreAPIURLSetting()
            } label: {
                Image(systemName: "network")
            }
            .help(manager.widgetStoreAPIBaseURL)
        }
        .padding(14)
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.widgets.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.widgets) { widget in
                            StoreWidgetRow(
                                widget: widget,
                                iconURL: viewModel.iconURL(for: widget),
                                isSelected: viewModel.selectedWidget?.id == widget.id
                            ) {
                                viewModel.selectedWidget = widget
                            }
                        }
                    }
                    .padding(8)
                }
                .background(Color.black.opacity(0.08))
            }
            HStack {
                Button {
                    Task { await viewModel.previousPage() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(viewModel.page <= 1 || viewModel.isLoading)
                Text("\(viewModel.page) / \(viewModel.pages)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    Task { await viewModel.nextPage() }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(viewModel.page >= viewModel.pages || viewModel.isLoading)
                Spacer()
            }
            .padding(10)
        }
        .frame(width: 330)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let widget = viewModel.selectedWidget {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    AsyncImage(url: viewModel.iconURL(for: widget)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            Image(systemName: "app.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.blue)
                                .padding(8)
                        }
                    }
                    .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(widget.title)
                            .font(.custom("Lucida Grande", size: 24).weight(.semibold))
                            .lineLimit(2)
                        Text(widget.subtitle)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let version = widget.bundleVersion, !version.isEmpty {
                            Text("Version \(version)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                Text(widget.description?.isEmpty == false ? widget.description! : "No description available.")
                    .font(.custom("Lucida Grande", size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(7)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Picker("Mode", selection: $viewModel.selectedMode) {
                        ForEach(StoreInstallMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)

                    Button {
                        Task { await viewModel.sendSelectedToApp() }
                    } label: {
                        Label("Send to App", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.isWorking)
                }

                HStack {
                    Button {
                        Task { await viewModel.downloadSelectedToFolder() }
                    } label: {
                        Label("Save to Disk...", systemImage: "externaldrive")
                    }
                    .disabled(viewModel.isWorking)

                    Button {
                        viewModel.openSelectedInBrowser()
                    } label: {
                        Label("Open in Browser", systemImage: "globe")
                    }
                    Spacer()
                }

                StoreScreenshotView(url: viewModel.screenshotURL(for: widget))
                    .frame(height: 220)

                Spacer()
            }
            .padding(18)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("No Widget Selected")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statusBar: some View {
        HStack {
            if viewModel.isLoading || viewModel.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Text(viewModel.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(manager.widgetStoreAPIBaseURL)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct StoreWidgetRow: View {
    let widget: StoreWidget
    let iconURL: URL?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AsyncImage(url: iconURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Image(systemName: "app.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.blue)
                            .padding(7)
                    }
                }
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.08))
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(widget.title)
                            .font(.custom("Lucida Grande", size: 13).weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if widget.hasFrameworks {
                            Text("FW")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.opacity(0.16))
                                )
                        }
                    }
                    Text(widget.subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
            .background(rowBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.24))
        }
        if isHovered {
            return AnyShapeStyle(Color.white.opacity(0.08))
        }
        return AnyShapeStyle(Color.white.opacity(0.03))
    }
}

private struct StoreScreenshotView: View {
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.2))
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    } else if phase.error != nil {
                        placeholder
                    } else {
                        ProgressView()
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 42))
            .foregroundStyle(.secondary)
    }
}

extension WidgetManager {
    func openWidgetStoreWindow() {
        let hosting = NSHostingController(rootView: StoreWindow(manager: self).environmentObject(self))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Widget Store"
        window.setContentSize(NSSize(width: 920, height: 620))
        window.minSize = NSSize(width: 860, height: 560)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.setFrameAutosaveName("WidgetStoreWindow")
        NSApp.activate(ignoringOtherApps: true)
    }

    func openStoreExportWindow(for widgetURL: URL) {
        let view = InstallExportSheet(widgetURL: widgetURL, initialFormat: .zip)
            .environmentObject(self)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Export Widget"
        window.setContentSize(NSSize(width: 420, height: 220))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.level = .floating
    }
}
