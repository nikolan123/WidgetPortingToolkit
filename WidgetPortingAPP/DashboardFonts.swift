//
//  DashboardFonts.swift
//  WidgetPortingAPP
//
//  Created by Niko on 8.11.26.
//

import CoreText
import Foundation

enum DashboardFonts {
    private struct Face: Encodable {
        let file: String
        let names: [String]
        let fragment: String?
        let weight: Int
        let italic: Bool
        let source: String?
    }

    static func styleScript(for files: [String], in folder: URL, localWidget: Bool = false) -> String? {
        let faces = Set(files).sorted().flatMap { fontFaces(in: folder, file: $0) }
        guard !faces.isEmpty,
              let facesData = try? JSONEncoder().encode(faces) else { return nil }

        let baseExpression: String
        if localWidget {
            let folderURL = URL(fileURLWithPath: folder.path, isDirectory: true)
            guard let urlData = try? JSONEncoder().encode(folderURL.absoluteString) else { return nil }
            baseExpression = "location.protocol === 'file:' ? \(String(decoding: urlData, as: UTF8.self)) : null"
        } else {
            // The exported runtime script and the declared fonts live at the widget root.
            baseExpression = "document.currentScript?.src"
        }

        return """
        (() => {
            const baseURL = \(baseExpression);
            if (!baseURL) return;

            const rules = [];
            for (const face of \(String(decoding: facesData, as: UTF8.self))) {
                const url = new URL(encodeURIComponent(face.file), baseURL);
                if (face.fragment) url.hash = face.fragment;
                const source = CSS.escape(face.source || url.href);
                const style = face.italic ? 'italic' : 'normal';
                for (const name of face.names) {
                    rules.push(`@font-face {
                        font-family: "${CSS.escape(name)}";
                        src: url("${source}");
                        font-weight: ${face.weight};
                        font-style: ${style};
                    }`);
                }
            }

            const stylesheet = document.createElement('style');
            stylesheet.textContent = rules.join('');
            (document.head || document.documentElement).prepend(stylesheet);
        })();
        """
    }

    private static func fontFaces(in folder: URL, file: String) -> [Face] {
        // Dashboard declares files at the bundle root.
        guard !file.isEmpty, file != ".", file != "..", !file.contains("/"), !file.contains("\0") else {
            return []
        }
        let url = folder.appendingPathComponent(file)
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            return []
        }

        // Suitcase fonts may keep all their TrueType data in the resource fork.
        // WebKit cannot fetch that fork, so expose each sfnt resource as a data URL.
        if (try? Data(contentsOf: url).isEmpty) == true {
            return resourceForkFonts(at: url).flatMap { data in
                let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor] ?? []
                return faces(
                    for: descriptors,
                    file: file,
                    source: "data:font/ttf;base64," + data.base64EncodedString()
                )
            }
        }
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        return faces(for: descriptors, file: file, source: nil)
    }

    private static func faces(for descriptors: [CTFontDescriptor], file: String, source: String?) -> [Face] {
        return descriptors.map { descriptor in
            let font = CTFontCreateWithFontDescriptor(descriptor, 0, nil)
            let postScriptName = CTFontCopyPostScriptName(font) as String
            let names = Set([
                postScriptName,
                CTFontCopyFamilyName(font) as String,
                CTFontCopyFullName(font) as String
            ]).filter { !$0.isEmpty }.sorted()
            let traits = CTFontGetSymbolicTraits(font)
            return Face(
                file: file,
                names: names,
                fragment: descriptors.count > 1 ? postScriptName : nil,
                weight: cssWeight(of: font) ?? (traits.contains(.boldTrait) ? 700 : 400),
                italic: traits.contains(.italicTrait),
                source: source
            )
        }
    }

    private static func resourceForkFonts(at url: URL) -> [Data] {
        let forkURL = url.appendingPathComponent("..namedfork/rsrc")
        guard let fork = try? Data(contentsOf: forkURL) else { return [] }
        func integer(at offset: Int, bytes: Int) -> Int? {
            guard offset >= 0, offset <= fork.count - bytes else { return nil }
            return fork[offset..<(offset + bytes)].reduce(0) { ($0 << 8) | Int($1) }
        }

        guard let dataOffset = integer(at: 0, bytes: 4),
              let mapOffset = integer(at: 4, bytes: 4),
              let typeOffset = integer(at: mapOffset + 24, bytes: 2) else { return [] }
        let typeList = mapOffset + typeOffset
        guard let typeCount = integer(at: typeList, bytes: 2), typeCount != 0xffff else { return [] }
        var fonts: [Data] = []
        for index in 0...typeCount {
            let entry = typeList + 2 + index * 8
            guard let tag = integer(at: entry, bytes: 4),
                  let count = integer(at: entry + 4, bytes: 2),
                  let referenceOffset = integer(at: entry + 6, bytes: 2) else { return [] }
            guard tag == 0x73666e74, count != 0xffff else { continue } // sfnt
            for resource in 0...count {
                let reference = typeList + referenceOffset + resource * 12
                guard let offset = integer(at: reference + 5, bytes: 3),
                      let length = integer(at: dataOffset + offset, bytes: 4) else { return [] }
                let start = dataOffset + offset + 4
                guard start <= fork.count, length <= fork.count - start else { return [] }
                fonts.append(fork.subdata(in: start..<(start + length)))
            }
        }
        return fonts
    }

    private static func cssWeight(of font: CTFont) -> Int? {
        // OpenType's OS/2 table stores the CSS-compatible usWeightClass at byte 4.
        guard let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?,
              table.count >= 6 else { return nil }
        let weight = Int(table[4]) * 256 + Int(table[5])
        return (1...1000).contains(weight) ? weight : nil
    }
}
