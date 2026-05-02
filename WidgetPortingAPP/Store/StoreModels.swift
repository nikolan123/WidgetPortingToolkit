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
    let status: String?
    let warnings: [String]
    let url: String?

    enum CodingKeys: String, CodingKey {
        case status, warnings, url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        url = try container.decodeIfPresent(String.self, forKey: .url)
    }
}

struct StoreWidgetLinks: Decodable, Hashable {
    let detail: String
    let download: String
    let icon: String?
    let screenshot: String?

    enum CodingKeys: String, CodingKey {
        case detail, download, icon, screenshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        detail = try container.decode(String.self, forKey: .detail)
        download = try container.decode(String.self, forKey: .download)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        screenshot = try container.decodeIfPresent(String.self, forKey: .screenshot)
    }
}
