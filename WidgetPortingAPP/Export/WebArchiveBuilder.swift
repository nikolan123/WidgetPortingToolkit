//
//  WebArchiveBuilder.swift
//  WidgetPortingAPP
//
//  Created by Niko on 24.04.26.
//

import Foundation

enum ExportPathRules {
    static func safeRelativePath(of fileURL: URL, root: URL) -> String? {
        let file = fileURL.standardizedFileURL
        let base = root.standardizedFileURL
        let fileComponents = file.pathComponents
        let baseComponents = base.pathComponents

        guard fileComponents.count >= baseComponents.count else { return nil }
        guard Array(fileComponents.prefix(baseComponents.count)) == baseComponents else { return nil }

        let relComponents = fileComponents.dropFirst(baseComponents.count)
        guard !relComponents.isEmpty else { return nil }
        return relComponents.joined(separator: "/")
    }

    static func shouldSkipExportedPath(_ url: URL, root: URL) -> Bool {
        guard let rel = safeRelativePath(of: url, root: root) else { return false }
        let parts = rel.split(separator: "/")
        for p in parts {
            let part = String(p).lowercased()
            if part == ".ds_store" || part == ".svn" || part == ".git" || part == ".hg" || part == "cvs" || part == "__macosx" {
                return true
            }
            if part.hasPrefix("._") {
                return true
            }
        }
        return false
    }
}

enum WebArchiveBuilder {
    static func writeWebArchive(from folder: URL, parsed: ParsedInfo, to outputURL: URL) throws {
        let fm = FileManager.default
        let mainHTMLURL = folder.appendingPathComponent(parsed.mainHTML)

        guard fm.fileExists(atPath: mainHTMLURL.path) else {
            throw WidgetExportError.fileOperationFailed("Main HTML file missing for webarchive: \(parsed.mainHTML)")
        }

        let archiveRoot = "https://widgets.nikolan.net/\(parsed.bundleIdentifier)_html_export/"
        guard let baseURL = URL(string: archiveRoot) else {
            throw WidgetExportError.fileOperationFailed("Failed to build webarchive base URL.")
        }
        let mainResource = try buildWebResourceDictionary(
            fileURL: mainHTMLURL,
            relativePath: parsed.mainHTML,
            baseURL: baseURL,
            frameName: "",
            includeResponse: false
        )

        var subresources: [[String: Any]] = []
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil) else {
            throw WidgetExportError.fileOperationFailed("Failed to enumerate files for webarchive.")
        }

        for case let fileURL as URL in enumerator {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            guard !ExportPathRules.shouldSkipExportedPath(fileURL, root: folder) else { continue }
            guard fileURL.path != mainHTMLURL.path else { continue }

            guard let relativePath = ExportPathRules.safeRelativePath(of: fileURL, root: folder) else { continue }
            let resource = try buildWebResourceDictionary(
                fileURL: fileURL,
                relativePath: relativePath,
                baseURL: baseURL,
                frameName: nil,
                includeResponse: true
            )
            subresources.append(resource)
        }

        do {
            var archive: [String: Any] = ["WebMainResource": mainResource]
            if !subresources.isEmpty {
                archive["WebSubresources"] = subresources
            }
            let binary = try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
            try binary.write(to: outputURL)
        } catch {
            throw WidgetExportError.fileOperationFailed("Failed to write webarchive: \(error.localizedDescription)")
        }
    }

    private static func buildWebResourceDictionary(
        fileURL: URL,
        relativePath: String,
        baseURL: URL,
        frameName: String?,
        includeResponse: Bool
    ) throws -> [String: Any] {
        let data = try Data(contentsOf: fileURL)
        let mime = mimeType(for: fileURL)
        let normalizedRelativePath = normalizeRelativePath(relativePath)
        let resourceURL = baseURL.appendingPathComponent(normalizedRelativePath)
        let encodingName = isTextMime(mime) ? "UTF-8" : nil

        var resource: [String: Any] = [
            "WebResourceData": data,
            "WebResourceMIMEType": mime,
            "WebResourceURL": resourceURL.absoluteString
        ]

        if let frameName {
            resource["WebResourceFrameName"] = frameName
        }
        if let encodingName {
            resource["WebResourceTextEncodingName"] = encodingName
        }
        if includeResponse,
           let response = HTTPURLResponse(
            url: resourceURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": encodingName != nil ? "\(mime); charset=utf-8" : mime,
                "Content-Length": "\(data.count)"
            ]
           ),
           let responseData = try? NSKeyedArchiver.archivedData(withRootObject: response, requiringSecureCoding: false) {
            resource["WebResourceResponse"] = responseData
        }

        return resource
    }

    private static func normalizeRelativePath(_ path: String) -> String {
        var out = path.replacingOccurrences(of: "\\", with: "/")
        while out.hasPrefix("./") { out.removeFirst(2) }
        while out.hasPrefix("/") { out.removeFirst() }
        return out
    }

    private static func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js", "mjs": return "application/javascript"
        case "json": return "application/json"
        case "txt": return "text/plain"
        case "xml": return "application/xml"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "ico": return "image/vnd.microsoft.icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "plist": return "application/x-plist"
        default: return "application/octet-stream"
        }
    }

    private static func isTextMime(_ mime: String) -> Bool {
        mime.hasPrefix("text/") || mime == "application/javascript" || mime == "application/json" || mime == "application/xml"
    }
}
