//
//  AutoDownloadWRS.swift
//  WidgetPortingAPP
//
//  Created by Niko on 26.12.25.
//

import Foundation
import SwiftUI

func downloadAndExtractWidgetResources(
    from url: URL,
    statusHandler: @escaping (String) -> Void,
    completion: @escaping (URL?) -> Void
) {
    statusHandler("Starting download...")

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 30
    let session = URLSession(configuration: config)

    let task = session.downloadTask(with: url) { localURL, _, error in
        if let error = error {
            DispatchQueue.main.async {
                statusHandler("Download failed: \(error.localizedDescription)")
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
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", localURL.path, "-d", tempDir.path]

        do {
            try process.run()
            process.waitUntilExit()

            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    statusHandler("") // clear status on success
                    completion(tempDir)
                } else {
                    statusHandler("Extraction failed!")
                    completion(nil)
                }
            }
        } catch {
            DispatchQueue.main.async {
                statusHandler("Error: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    task.resume()
}
