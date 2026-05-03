//
//  CLIRunner.swift
//  WidgetPortingAPP
//
//  Created by Niko on 3.05.26.
//

import Foundation

// Handles all command-line interface logic for the app.
// Call `CLIRunner.run()` from `main` or `App.init()` if flags are detected.
enum CLIRunner {
    
    struct Arguments {
        var input: String?
        var output: String?
        var format: WidgetExportFormat = .zip
        var supportDir: String?
        
        static func parse(from args: [String]) -> Arguments {
            var parsed = Arguments()
            var i = 0
            while i < args.count {
                let arg = args[i]
                switch arg {
                case "--input", "-i":
                    parsed.input = safeArg(args, at: i + 1)
                    i += 1
                case "--output", "-o":
                    parsed.output = safeArg(args, at: i + 1)
                    i += 1
                case "--format", "-f":
                    let raw = (safeArg(args, at: i + 1) ?? "").lowercased()
                    switch raw {
                    case "zip": parsed.format = .zip
                    case "webarchive": parsed.format = .webarchive
                    case "pythonrunner", "python": parsed.format = .pythonRunner
                    case "macosapp", "app": parsed.format = .macOSApp
                    default: fatalError("Unknown format '\(raw)'. Use zip, webarchive, pythonrunner, or macosapp.")
                    }
                    i += 1
                case "--support-dir":
                    parsed.supportDir = safeArg(args, at: i + 1)
                    i += 1
                case "--help", "-h":
                    printUsage()
                    exit(0)
                default:
                    break
                }
                i += 1
            }
            return parsed
        }
        
        private static func safeArg(_ args: [String], at index: Int) -> String? {
            guard index < args.count else { return nil }
            return args[index]
        }
    }

    static func run(args: [String]) {
        let arguments = Arguments.parse(from: args)

        guard let inputPath = arguments.input else {
            print("Error: --input is required")
            printUsage()
            exit(1)
        }

        guard let outputPath = arguments.output else {
            print("Error: --output is required")
            printUsage()
            exit(1)
        }

        let inputURL = URL(fileURLWithPath: inputPath).standardizedFileURL
        
        // Default support dir logic: check args, then environment, then standard location
        let supportDir = arguments.supportDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.niko.WidgetPortingAPP/SupportDirectory")
            .path

        print("Exporting widget: \(inputURL.lastPathComponent)")
        print("Format: \(arguments.format.displayName)")

        do {
            let artifact = try WidgetExporter.exportWidgetToHTMLBundle(
                widgetURL: inputURL,
                format: arguments.format,
                supportDirectoryPath: supportDir,
                progress: { print("→ \($0)") }
            )

            let destination = URL(fileURLWithPath: outputPath).standardizedFileURL
            let fm = FileManager.default

            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }

            try fm.copyItem(at: artifact.outputURL, to: destination)

            print("Export complete: \(destination.path)")

            // Cleanup work directory
            try? fm.removeItem(at: artifact.workDirectory)

        } catch {
            print("Export failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func printUsage() {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Widget Porting Toolkit"
            
        print("""
        Usage: \(appName) --export --input <widget.wdgt> --output <destination> [options]

        Required:
          --export            Export a .wdgt bundle to run standalone
          --input, -i         Path to the .wdgt folder to export
          --output, -o        Path to save the exported file

        Options:
          --format, -f        Export format: zip (default), webarchive, pythonrunner, macosapp
          --support-dir       Path to the Support Directory (defaults to standard location)
        """)
    }
}
