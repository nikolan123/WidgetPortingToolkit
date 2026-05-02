//
//  StoreAPIClient.swift
//  WidgetPortingAPP
//
//  Created by Niko on 30.04.26.
//

import Foundation

struct StoreAPIClient {
    let baseURL: URL

    func listWidgets(query: String, sort: String, page: Int, pageSize: Int) async throws -> StoreWidgetPage {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/widgets"), resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize))
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "q", value: trimmed))
        }
        components?.queryItems = items
        guard let url = components?.url else {
            throw StoreError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response)
        let decoder = JSONDecoder()
        return try decoder.decode(StoreWidgetPage.self, from: data)
    }

    func downloadWidget(_ widget: StoreWidget) async throws -> URL {
        let url = try absoluteURL(for: widget.links.download)
        let (localURL, response) = try await URLSession.shared.download(from: url)
        try validate(response: response)

        let suggestedName = response.suggestedFilename ?? "\(widget.title).zip"
        let safeName = suggestedName.replacingOccurrences(of: "/", with: "-")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreDownload_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let zipURL = destination.appendingPathComponent(safeName)
        try FileManager.default.moveItem(at: localURL, to: zipURL)
        return zipURL
    }

    func absoluteURL(for path: String) throws -> URL {
        if let url = URL(string: path), url.scheme != nil {
            return url
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw StoreError.invalidURL
        }
        return url
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw StoreError.httpStatus(http.statusCode)
        }
    }
}

enum StoreError: LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case noWidgetBundleFound
    case extractFailed(String)
    case extractTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid store API URL."
        case .httpStatus(let status): return "Store API returned HTTP \(status)."
        case .noWidgetBundleFound: return "No .wdgt bundle was found in the downloaded archive."
        case .extractFailed(let detail): return detail.isEmpty ? "Failed to extract widget archive." : "Failed to extract widget archive: \(detail)"
        case .extractTimedOut: return "Extracting the widget archive timed out."
        }
    }
}

enum StoreArchiveHelper {
    static func extractWidgetBundle(from zipURL: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreExtract_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        try runExtractor(zipURL: zipURL, destination: destination)

        if destination.pathExtension.lowercased() == "wdgt" {
            return destination
        }
        if let directBundle = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension.lowercased() == "wdgt" }) {
            return directBundle
        }
        guard let enumerator = FileManager.default.enumerator(at: destination, includingPropertiesForKeys: nil) else {
            throw StoreError.noWidgetBundleFound
        }
        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "wdgt" {
            return fileURL
        }
        throw StoreError.noWidgetBundleFound
    }

    private static func runExtractor(zipURL: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, destination.path]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            completion.signal()
        }

        try process.run()
        if completion.wait(timeout: .now() + 30) == .timedOut {
            process.terminate()
            throw StoreError.extractTimedOut
        }

        guard process.terminationStatus == 0 else {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw StoreError.extractFailed(detail)
        }
    }
}
