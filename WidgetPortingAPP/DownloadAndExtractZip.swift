//
//  DownloadAndExtractZip.swift
//  WidgetPortingAPP
//
//  Created by Niko on 26.12.25.
//

import Foundation

@discardableResult
func downloadAndExtractZip(
    from url: URL,
    statusHandler: @escaping (String) -> Void,
    completion: @escaping (URL?) -> Void
) -> URLSessionDownloadTask {
    statusHandler("Starting download...")

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 30
    let session = URLSession(configuration: config)

    let task = session.downloadTask(with: url) { localURL, response, error in
        defer { session.finishTasksAndInvalidate() }

        if let error = error {
            DispatchQueue.main.async {
                statusHandler("Download failed: \(error.localizedDescription)")
                completion(nil)
            }
            return
        }

        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            DispatchQueue.main.async {
                statusHandler("Download failed (HTTP \(response.statusCode)).")
                completion(nil)
            }
            return
        }

        guard let localURL = localURL else {
            DispatchQueue.main.async {
                statusHandler("Download failed: unknown error")
                completion(nil)
            }
            return
        }

        DispatchQueue.main.async { statusHandler("Download complete. Extracting...") }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", localURL.path, "-d", tempDir.path]

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try process.run()
            process.waitUntilExit()

            let extracted = process.terminationStatus == 0
            if !extracted {
                try? FileManager.default.removeItem(at: tempDir)
            }
            DispatchQueue.main.async {
                if extracted {
                    statusHandler("") // clear status on success
                    completion(tempDir)
                } else {
                    statusHandler("Extraction failed!")
                    completion(nil)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            DispatchQueue.main.async {
                statusHandler("Error: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    task.resume()
    return task
}
