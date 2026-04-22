//
//  PreviewViewController.swift
//  WidgetQuickLook
//
//  Created by Niko on 22.04.26.
//

import Cocoa
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {
    private let appIconImageView = NSImageView()
    private let bannerTitleLabel = NSTextField(labelWithString: "Widget Porting Toolkit")
    private let creditLabel = NSTextField(labelWithString: "Made by Niko")
    private let iconImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Widget")
    private let detailsLabel = NSTextField(labelWithString: "")
    private let decoder = WidgetMetadataDecoder()

    override var nibName: NSNib.Name? {
        return NSNib.Name("PreviewViewController")
    }

    override func loadView() {
        super.loadView()
        configureUI()
    }

    /*
    func preparePreviewOfSearchableItem(identifier: String, queryString: String?) async throws {
        // Implement this method and set QLSupportsSearchableItems to YES in the Info.plist of the extension if you support CoreSpotlight.

        // Perform any setup necessary in order to prepare the view.
        // Quick Look will display a loading spinner until this returns.
    }
    */

    func preparePreviewOfFile(at url: URL) async throws {
        let metadata = decoder.decode(from: url)
        await MainActor.run {
            self.apply(metadata: metadata)
        }
    }

    private func configureUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        preferredContentSize = NSSize(width: 700, height: 250)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        appIconImageView.translatesAutoresizingMaskIntoConstraints = false
        appIconImageView.imageScaling = .scaleProportionallyUpOrDown
        appIconImageView.image = hostAppIcon()
        NSLayoutConstraint.activate([
            appIconImageView.widthAnchor.constraint(equalToConstant: 20),
            appIconImageView.heightAnchor.constraint(equalToConstant: 20)
        ])

        bannerTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        bannerTitleLabel.lineBreakMode = .byTruncatingTail
        
        creditLabel.font = .systemFont(ofSize: 11, weight: .medium)
        creditLabel.textColor = .secondaryLabelColor
        creditLabel.alignment = .right

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let footer = NSStackView(views: [appIconImageView, bannerTitleLabel, spacer, creditLabel])
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        footer.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        footer.wantsLayer = true
        footer.layer?.backgroundColor = NSColor.clear.cgColor

        let content = NSStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .horizontal
        content.alignment = .top
        content.spacing = 20

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 72, weight: .regular)
        iconImageView.image = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "Widget icon")
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 132),
            iconImageView.heightAnchor.constraint(equalToConstant: 132)
        ])

        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        detailsLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailsLabel.textColor = .secondaryLabelColor
        detailsLabel.maximumNumberOfLines = 0
        detailsLabel.lineBreakMode = .byWordWrapping

        let right = NSStackView(views: [titleLabel, detailsLabel])
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 8

        content.addArrangedSubview(iconImageView)
        content.addArrangedSubview(right)
        right.setContentHuggingPriority(.defaultLow, for: .horizontal)

        container.addSubview(content)
        container.addSubview(footer)

        let footerTopBorder = NSView()
        footerTopBorder.translatesAutoresizingMaskIntoConstraints = false
        footerTopBorder.wantsLayer = true
        footerTopBorder.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.35).cgColor
        container.addSubview(footerTopBorder)

        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 32),
            footerTopBorder.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            footerTopBorder.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            footerTopBorder.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footerTopBorder.heightAnchor.constraint(equalToConstant: 1),

            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: footerTopBorder.topAnchor, constant: -20)
        ])

        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func hostAppIcon() -> NSImage? {
        let extensionBundleURL = Bundle.main.bundleURL
        let appBundleURL = extensionBundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return NSWorkspace.shared.icon(forFile: appBundleURL.path)
    }

    @MainActor
    private func apply(metadata: WidgetMetadata) {
        titleLabel.stringValue = metadata.title
        detailsLabel.stringValue = metadata.details
        iconImageView.image = metadata.icon ?? NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "Widget icon")
    }
}
