//
//  ArisOfficeText.swift
//  aris-tools
//
//  The text of an Excel workbook (xlsx), a PowerPoint deck (pptx) and a Hangul document (hwpx) for `files read` (audit
//  16: they couldn't be read). Each is a zip of XML files, read here with what macOS has: the zip's own directory,
//  Compression's raw DEFLATE and Foundation's XMLParser (which never loads an outside entity). Nothing is started and
//  nothing is written to disk. Bounded: a zip with too many entries, an entry that inflates past its limit, a ZIP64 or
//  encrypted archive is not read; the text stops once it passes `limit` characters.
//
//  An old binary .hwp (HWP 5.0) is not a zip: it is an OLE2 compound file whose BodyText/Section streams are DEFLATE'd
//  records (the text in HWPTAG_PARA_TEXT, UTF-16 with inline controls). Reading it would need a compound-file reader
//  (its FAT and mini-FAT sector chains) and that record walk, about as much code again as this file, and still not the
//  distribution-protected (배포용) or password-protected kind, which are encrypted.
//

import Compression
import Foundation

enum ArisOfficeText {
    /// How much one entry may inflate to, and how many entries a document may have.
    static let entryLimit = 16 << 20
    static let mostEntries = 10_000

    enum Format: String { case xlsx, pptx, hwpx }

    static func format(_ path: String) -> Format? {
        Format(rawValue: (path as NSString).pathExtension.lowercased())
    }

    /// The document's text, or nil when it can't be read (not a zip, a part missing, nothing in it).
    static func text(ofFile path: String, limit: Int = 20_000) -> String? {
        guard let format = format(path), let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              let zip = Zip(data) else { return nil }
        let text: String?
        switch format {
        case .xlsx: text = workbook(zip, limit: limit)
        case .pptx: text = deck(zip, limit: limit)
        case .hwpx: text = hangul(zip, limit: limit)
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Excel

    private static func workbook(_ zip: Zip, limit: Int) -> String? {
        let shared = zip.entry("xl/sharedStrings.xml").map(sharedStrings) ?? []
        let relations = zip.entry("xl/_rels/workbook.xml.rels").map(relationships) ?? [:]
        let listed = zip.entry("xl/workbook.xml").map(sheetList) ?? []
        var sheets: [(name: String, relation: String)] = listed.compactMap { sheet in
            relations[sheet.relation].map { (name: sheet.name, relation: part($0, under: "xl")) }
        }
        if sheets.isEmpty {
            sheets = numbered(zip.names, prefix: "xl/worksheets/sheet").enumerated().map { (name: "Sheet \($0.offset + 1)", relation: $0.element) }
        }
        var out = ""
        for sheet in sheets where out.count < limit {
            guard let data = zip.entry(sheet.relation) else { continue }
            let rows = SheetReader.rows(data, shared: shared, limit: limit - out.count)
            guard !rows.isEmpty else { continue }
            out += "[Sheet: \(sheet.name)]\n" + rows.joined(separator: "\n") + "\n\n"
        }
        return out
    }

    private static func sharedStrings(_ data: Data) -> [String] {
        let reader = TextReader(text: ["t"], paragraph: [], skip: ["rPh"], item: "si")
        reader.parse(data)
        return reader.items
    }

    private static func sheetList(_ data: Data) -> [(name: String, relation: String)] {
        let reader = AttributeReader(element: "sheet")
        reader.parse(data)
        return reader.found.compactMap { attributes in
            guard let name = attributes["name"], let id = attributes.first(where: { $0.key == "r:id" || $0.key.hasSuffix(":id") })?.value else { return nil }
            return (name, id)
        }
    }

    /// One worksheet's rows, each a line of cells by tab, a cell in its own column ("A1", "C1": one empty between).
    private final class SheetReader: NSObject, XMLParserDelegate {
        private let shared: [String]
        private let limit: Int
        private(set) var rows: [String] = []
        private var cells: [(column: Int, value: String)] = []
        private var type = "", column = 0, value = "", inValue = false, inInline = false, inText = false, size = 0

        private init(shared: [String], limit: Int) {
            self.shared = shared
            self.limit = limit
        }

        static func rows(_ data: Data, shared: [String], limit: Int) -> [String] {
            let reader = SheetReader(shared: shared, limit: limit)
            let parser = XMLParser(data: data)
            parser.delegate = reader
            parser.shouldResolveExternalEntities = false
            parser.parse()
            return reader.rows
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            switch local(name) {
            case "row": cells = []
            case "c":
                type = attributes["t"] ?? ""
                column = attributes["r"].map(columnNumber) ?? (cells.last.map { $0.column + 1 } ?? 0)
                value = ""
            case "v": inValue = true
            case "is": inInline = true
            case "t" where inInline: inText = true
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inValue || inText { value += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch local(name) {
            case "v": inValue = false
            case "t": inText = false
            case "is": inInline = false
            case "c":
                let shown: String
                switch type {
                case "s": shown = Int(value.trimmingCharacters(in: .whitespaces)).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? ""
                case "b": shown = value == "1" ? "TRUE" : value == "0" ? "FALSE" : value
                default: shown = value
                }
                if !shown.isEmpty { cells.append((column, shown.replacingOccurrences(of: "\n", with: " "))) }
            case "row":
                guard !cells.isEmpty else { return }
                var line = "", at = cells[0].column
                for cell in cells {
                    // Empty columns between two cells are kept (at most a few, so a far-off cell doesn't make a wall of tabs).
                    if !line.isEmpty { line += String(repeating: "\t", count: max(1, min(cell.column - at, 8))) }
                    line += cell.value
                    at = cell.column
                }
                rows.append(line)
                size += line.count + 1
                if size >= limit { parser.abortParsing() }
            default: break
            }
        }

        /// "C12" → 3; "AA1" → 27.
        private func columnNumber(_ reference: String) -> Int {
            reference.unicodeScalars.prefix { CharacterSet.uppercaseLetters.contains($0) }.reduce(0) { $0 * 26 + Int($1.value) - 64 }
        }
    }

    // MARK: - PowerPoint

    private static func deck(_ zip: Zip, limit: Int) -> String? {
        let relations = zip.entry("ppt/_rels/presentation.xml.rels").map(relationships) ?? [:]
        let order = zip.entry("ppt/presentation.xml").map { data -> [String] in
            let reader = AttributeReader(element: "sldId")
            reader.parse(data)
            return reader.found.compactMap { $0.first(where: { $0.key == "r:id" || $0.key.hasSuffix(":id") })?.value }
        } ?? []
        var slides = order.compactMap { relations[$0].map { part($0, under: "ppt") } }.filter { zip.entry($0) != nil }
        if slides.isEmpty { slides = numbered(zip.names, prefix: "ppt/slides/slide") }
        var out = ""
        for (index, slide) in slides.enumerated() where out.count < limit {
            guard let data = zip.entry(slide) else { continue }
            let reader = TextReader(text: ["t"], paragraph: ["p"], breaks: ["br"], limit: limit - out.count)
            reader.parse(data)
            let text = reader.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            out += "[Slide \(index + 1)]\n\(text)\n\n"
        }
        return out
    }

    // MARK: - Hangul (HWPX, OWPML)

    private static func hangul(_ zip: Zip, limit: Int) -> String? {
        var out = ""
        for section in numbered(zip.names, prefix: "Contents/section", from: 0) where out.count < limit {
            guard let data = zip.entry(section) else { continue }
            let reader = TextReader(text: ["t"], paragraph: ["p"], breaks: ["lineBreak"], tabs: ["tab"], limit: limit - out.count)
            reader.parse(data)
            out += reader.text + "\n"
        }
        return out
    }

    // MARK: - Parts

    /// A relationships file: each Id and the part it targets.
    private static func relationships(_ data: Data) -> [String: String] {
        let reader = AttributeReader(element: "Relationship")
        reader.parse(data)
        return reader.found.reduce(into: [:]) { map, attributes in
            if let id = attributes["Id"], let target = attributes["Target"] { map[id] = target }
        }
    }

    /// A relationship's target as the zip names it: relative to `folder`, or from the root when it starts with "/".
    private static func part(_ target: String, under folder: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        var parts = folder.split(separator: "/").map(String.init)
        for piece in target.split(separator: "/") {
            if piece == ".." { _ = parts.popLast() } else if piece != "." { parts.append(String(piece)) }
        }
        return parts.joined(separator: "/")
    }

    /// The entries named `<prefix><number>.xml`, by their number (slide2 before slide10).
    private static func numbered(_ names: [String], prefix: String, from first: Int = 1) -> [String] {
        names.compactMap { name -> (Int, String)? in
            guard name.hasPrefix(prefix), name.hasSuffix(".xml"), let number = Int(name.dropFirst(prefix.count).dropLast(4)), number >= first else { return nil }
            return (number, name)
        }.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private static func local(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    // MARK: - XML

    /// The text inside the `text` elements; a line break after each `paragraph`; with `item`, each item's text alone.
    private final class TextReader: NSObject, XMLParserDelegate {
        private let textNames: Set<String>, paragraphNames: Set<String>, skipNames: Set<String>, breakNames: Set<String>, tabNames: Set<String>
        private let itemName: String?
        private let limit: Int
        private(set) var text = ""
        private(set) var items: [String] = []
        private var inText = 0, skipping = 0, current = "", size = 0

        init(text: Set<String>, paragraph: Set<String>, skip: Set<String> = [], breaks: Set<String> = [], tabs: Set<String> = [], item: String? = nil,
             limit: Int = .max) {
            textNames = text
            paragraphNames = paragraph
            skipNames = skip
            breakNames = breaks
            tabNames = tabs
            itemName = item
            self.limit = limit
        }

        func parse(_ data: Data) {
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.shouldResolveExternalEntities = false
            parser.parse()
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            let name = ArisOfficeText.local(name)
            if skipNames.contains(name) { skipping += 1 }
            if textNames.contains(name) { inText += 1 }
            if breakNames.contains(name) { text += "\n" }
            if tabNames.contains(name) { text += "\t" }
            if name == itemName { current = "" }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard inText > 0, skipping == 0 else { return }
            if itemName != nil { current += string } else { text += string }
            size += string.count
            if size >= limit { parser.abortParsing() }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let name = ArisOfficeText.local(name)
            if textNames.contains(name) { inText = max(0, inText - 1) }
            if skipNames.contains(name) { skipping = max(0, skipping - 1) }
            if paragraphNames.contains(name), !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
            if name == itemName { items.append(current) }
        }
    }

    /// The attributes of every element with this local name.
    private final class AttributeReader: NSObject, XMLParserDelegate {
        private let element: String
        private(set) var found: [[String: String]] = []

        init(element: String) { self.element = element }

        func parse(_ data: Data) {
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.shouldResolveExternalEntities = false
            parser.parse()
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if ArisOfficeText.local(name) == element { found.append(attributes) }
        }
    }

    // MARK: - Zip

    /// A zip's entries by name, read from its central directory; each inflated only when asked for.
    struct Zip {
        private let data: Data
        private var entries: [String: (method: UInt16, flags: UInt16, compressed: Int, size: Int, offset: Int)] = [:]
        private(set) var names: [String] = []

        init?(_ data: Data) {
            self.data = data
            // The end of the central directory: in the last 64 KB (its comment is at most that long).
            let count = data.count
            guard count >= 22 else { return nil }
            var end: Int?
            var at = count - 22
            while at >= max(0, count - 22 - 65_535) {
                if data.u32(at) == 0x0605_4B50 { end = at; break }
                at -= 1
            }
            guard let end else { return nil }
            let total = Int(data.u16(end + 10)), directory = Int(data.u32(end + 16))
            // ZIP64 (a size or count that didn't fit) isn't read: a document never needs it.
            guard total != 0xFFFF, directory != 0xFFFF_FFFF, total <= ArisOfficeText.mostEntries else { return nil }
            var position = directory
            for _ in 0..<total {
                guard position + 46 <= count, data.u32(position) == 0x0201_4B50 else { return nil }
                let nameLength = Int(data.u16(position + 28)), extra = Int(data.u16(position + 30)), comment = Int(data.u16(position + 32))
                guard position + 46 + nameLength <= count else { return nil }
                let name = String(decoding: data[(data.startIndex + position + 46)..<(data.startIndex + position + 46 + nameLength)], as: UTF8.self)
                entries[name] = (data.u16(position + 10), data.u16(position + 8), Int(data.u32(position + 20)), Int(data.u32(position + 24)),
                                 Int(data.u32(position + 42)))
                names.append(name)
                position += 46 + nameLength + extra + comment
            }
        }

        /// One entry's bytes, inflated; nil when it is missing, encrypted, too big or broken.
        func entry(_ name: String) -> Data? {
            guard let entry = entries[name], entry.flags & 1 == 0, entry.size <= ArisOfficeText.entryLimit else { return nil }
            let local = entry.offset
            guard local + 30 <= data.count, data.u32(local) == 0x0403_4B50 else { return nil }
            let start = local + 30 + Int(data.u16(local + 26)) + Int(data.u16(local + 28))
            guard start + entry.compressed <= data.count else { return nil }
            let packed = data[(data.startIndex + start)..<(data.startIndex + start + entry.compressed)]
            switch entry.method {
            case 0: return packed.count == entry.size ? Data(packed) : nil
            case 8:
                guard entry.size > 0 else { return Data() }
                var out = Data(count: entry.size)
                let written = out.withUnsafeMutableBytes { target in
                    packed.withUnsafeBytes { source in
                        compression_decode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, entry.size,
                                                  source.bindMemory(to: UInt8.self).baseAddress!, packed.count, nil, COMPRESSION_ZLIB)
                    }
                }
                return written == entry.size ? out : nil
            default: return nil
            }
        }
    }
}

private extension Data {
    func u16(_ at: Int) -> UInt16 {
        guard at >= 0, at + 2 <= count else { return 0 }
        return UInt16(self[startIndex + at]) | UInt16(self[startIndex + at + 1]) << 8
    }

    func u32(_ at: Int) -> UInt32 {
        guard at >= 0, at + 4 <= count else { return 0 }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[startIndex + at + $1]) << (8 * UInt32($1)) }
    }
}
