//
//  PreviewViewController.swift
//  WidgetQuickLook
//
//  Created by Niko on 22.04.26.
//

import Cocoa
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {
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
        preferredContentSize = NSSize(width: 640, height: 220)

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = 20
        root.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor

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

        root.addArrangedSubview(iconImageView)
        root.addArrangedSubview(right)
        right.setContentHuggingPriority(.defaultLow, for: .horizontal)

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @MainActor
    private func apply(metadata: WidgetMetadata) {
        titleLabel.stringValue = metadata.title
        detailsLabel.stringValue = metadata.details
        iconImageView.image = metadata.icon ?? NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "Widget icon")
    }
}
