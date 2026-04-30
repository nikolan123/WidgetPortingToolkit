//
//  StoreModels.swift
//  WidgetPortingAPP
//
//  Created by Niko on 30.04.26.
//

import Foundation

enum StoreInstallMode: String, CaseIterable, Identifiable {
    case normal
    case portable
    case exporter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .portable: return "Portable"
        case .exporter: return "Exporter"
        }
    }
}

struct StoreWidgetPage: Decodable {
    let items: [StoreWidget]
    let total: Int
    let page: Int
    let pageSize: Int
    let pages: Int

    enum CodingKeys: String, CodingKey {
        case items, total, page, pages
        case pageSize = "page_size"
    }
}

struct StoreWidget: Decodable, Identifiable, Hashable {
    let uuid: String
    let name: String
    let bundleName: String?
    let displayName: String?
    let bundleIdentifier: String?
    let bundleVersion: String?
    let mainHTML: String?
    let hasFrameworks: Bool
    let description: String?
    let screenshot: StoreScreenshot?
    let links: StoreWidgetLinks

    var id: String { uuid }
    var title: String { displayName ?? name }
    var subtitle: String { bundleIdentifier ?? bundleName ?? uuid }

    enum CodingKeys: String, CodingKey {
        case uuid, name, description, screenshot, links
        case bundleName = "bundle_name"
        case displayName = "display_name"
        case bundleIdentifier = "bundle_identifier"
        case bundleVersion = "bundle_version"
        case mainHTML = "main_html"
        case hasFrameworks = "has_frameworks"
    }
}

struct StoreScreenshot: Decodable, Hashable {
    let status: String
    let warnings: [String]
    let url: String?
}

struct StoreWidgetLinks: Decodable, Hashable {
    let detail: String
    let download: String
    let icon: String
    let screenshot: String
}
