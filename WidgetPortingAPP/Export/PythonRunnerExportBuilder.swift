//
//  PythonRunnerExportBuilder.swift
//  WidgetPortingAPP
//
//  Created by Niko on 24.04.26.
//

import Foundation

enum PythonRunnerExportBuilder {
    private static let runnerRootFolderName = "WidgetPythonRunner"
    private static let widgetFolderName = "widget_export"

    private static var resourcesURL: URL? {
        Bundle.main.resourceURL
    }

    static func buildArchive(
        workDirectory: URL,
        processedWidgetFolder: URL,
        outputZipURL: URL
    ) throws {
        guard let resources = resourcesURL else {
            throw WidgetExportError.fileOperationFailed("Could not locate app resources")
        }

        let fm = FileManager.default
        let runnerRoot = workDirectory.appendingPathComponent(runnerRootFolderName, isDirectory: true)
        let runnerWidgetFolder = runnerRoot.appendingPathComponent(widgetFolderName, isDirectory: true)
        let runnerJSFolder = runnerRoot.appendingPathComponent("js", isDirectory: true)

        do {
            if fm.fileExists(atPath: runnerRoot.path) {
                try fm.removeItem(at: runnerRoot)
            }
            try fm.createDirectory(at: runnerRoot, withIntermediateDirectories: true)
            try fm.copyItem(at: processedWidgetFolder, to: runnerWidgetFolder)
            try fm.createDirectory(at: runnerJSFolder, withIntermediateDirectories: true)
        } catch {
            throw WidgetExportError.fileOperationFailed("Failed to prepare Python runner workspace: \(error.localizedDescription)")
        }

        do {
            try copyFromResources(named: "main.py", to: runnerRoot, resources: resources)
            try copyFromResources(named: "preferences.py", to: runnerRoot, resources: resources)
            try copyFromResources(named: "pyproject.toml", to: runnerRoot, resources: resources)
            try writeFile(named: "prefs.json", in: runnerRoot, contents: "{}\n")

            try copyFromResources(named: "bridge_bootstrap.js", to: runnerJSFolder, resources: resources)
            try copyFromResources(named: "prefs_sync.js", to: runnerJSFolder, resources: resources)
            try copyFromResources(named: "drag_guard.js", to: runnerJSFolder, resources: resources)
        } catch {
            throw WidgetExportError.fileOperationFailed("Failed to write Python runner files: \(error.localizedDescription)")
        }

        try zipFolder(at: runnerRoot, to: outputZipURL, from: workDirectory)
    }

    private static func copyFromResources(named name: String, to destination: URL, resources: URL) throws {
        let source = resources.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: source.path) {
            throw WidgetExportError.fileOperationFailed("Missing resource: \(name)")
        }
        let destinationURL = destination.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destinationURL)
    }

    private static func writeFile(named name: String, in folder: URL, contents: String) throws {
        let url = folder.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func zipFolder(at folder: URL, to zipURL: URL, from workingDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = workingDirectory
        process.arguments = ["-r", "-y", zipURL.lastPathComponent, folder.lastPathComponent]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw WidgetExportError.zipFailed("Failed to start zip process: \(error.localizedDescription)")
        }

        if process.terminationStatus != 0 {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: errorData, encoding: .utf8) ?? "unknown error"
            throw WidgetExportError.zipFailed("zip failed with status \(process.terminationStatus): \(stderrText)")
        }
    }
}