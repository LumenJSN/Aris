//
//  ArisMailMIME.swift
//  aris-tools (also built into aris-agent, for a reply card's addresses)
//
//  One mail as Mail keeps it on disk (an .emlx file: a byte count, the message as it came, then Mail's own property
//  list), read into what the user would see: its headers decoded, its text (the HTML part reduced to the text it shows,
//  or the plain part of a mail that has no other), and its attachments by name and size only. Nothing here opens an attachment, follows a link or loads a
//  picture: it reads bytes and gives back text. Pure, so the tests run it.
//

import Foundation

/// One address in a mail's header: who it says it is, and where a reply would really go.
struct ArisMailAddress: Equatable, Hashable {
    let name: String
    let address: String

    /// Addresses are the same whatever their capitals.
    var key: String { address.lowercased() }

    /// "김교수 <prof@uni.edu>", or the address alone.
    var shown: String { name.isEmpty ? address : "\(name) <\(address)>" }
}

/// A file that came with a mail: its name and size. Never its content.
struct ArisMailAttachment: Equatable {
    let name: String
    let bytes: Int
}

/// A mail read from its file.
struct ArisMailContent: Equatable {
    /// Header names lowercased; each header's first value, decoded.
    var headers: [String: String] = [:]
    var text = ""
    var attachments: [ArisMailAttachment] = []

    func addresses(_ header: String) -> [ArisMailAddress] { ArisMailMIME.addresses(headers[header] ?? "") }
}

/// One part of a mail: its own headers and its bytes, still encoded.
private struct ArisMailPart {
    let headers: [String: String]
    let body: Data

    var type: (value: String, parameters: [String: String]) { ArisMailMIME.parameters(headers["content-type"] ?? "text/plain") }
    var disposition: (value: String, parameters: [String: String]) { ArisMailMIME.parameters(headers["content-disposition"] ?? "") }
}

enum ArisMailMIME {
    /// The most of one mail file that is read (text comes first; a huge attachment after it is only counted).
    static let maxFileBytes = 12_000_000
    static let maxDepth = 8
    static let maxParts = 200

    // MARK: - The file

    /// The message inside an .emlx file: the first line says how many bytes it is. A file without that line is taken
    /// as the message itself (an .eml).
    static func message(emlx data: Data) -> Data {
        guard let lineEnd = data.firstIndex(of: 0x0A), lineEnd - data.startIndex <= 12,
              let count = Int(String(decoding: data[data.startIndex..<lineEnd], as: UTF8.self).trimmingCharacters(in: .whitespaces)), count >= 0 else {
            return data
        }
        let start = data.index(after: lineEnd)
        return data[start..<min(data.endIndex, start + count)]
    }

    /// A mail's headers, text and attachments from its raw message.
    static func parse(_ message: Data) -> ArisMailContent {
        let whole = split(message)
        var content = ArisMailContent(headers: whole.headers.mapValues(decodeWords))
        var texts: [String] = [], count = 0
        collect(whole, depth: 0, count: &count, texts: &texts, attachments: &content.attachments)
        content.text = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        return content
    }

    // MARK: - Parts

    /// Headers and body, cut at the first empty line. Header lines that go on (a leading space or tab) are joined.
    private static func split(_ data: Data) -> ArisMailPart {
        let bytes = [UInt8](data)
        var cut = bytes.count, bodyStart = bytes.count
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x0A {
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A { (cut, bodyStart) = (index, index + 2); break }
                if index + 2 < bytes.count, bytes[index + 1] == 0x0D, bytes[index + 2] == 0x0A { (cut, bodyStart) = (index, index + 3); break }
            }
            index += 1
        }
        // A part that starts with its empty line has no headers at all.
        if bytes.first == 0x0A { (cut, bodyStart) = (0, 1) } else if bytes.count > 1, bytes[0] == 0x0D, bytes[1] == 0x0A { (cut, bodyStart) = (0, 2) }
        let head = text(Data(bytes[0..<cut]), charset: nil)
        var headers: [String: String] = [:], name = ""
        for line in head.replacingOccurrences(of: "\r", with: "").split(separator: "\n", omittingEmptySubsequences: true) {
            if line.first == " " || line.first == "\t" {
                if !name.isEmpty { headers[name] = (headers[name] ?? "") + " " + line.trimmingCharacters(in: .whitespaces) }
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { name = ""; continue }
            name = line[..<colon].lowercased()
            // The first of a repeated header counts; a later one never replaces it.
            if headers[name] == nil { headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces) } else { name = "" }
        }
        return ArisMailPart(headers: headers, body: Data(bytes[min(bodyStart, bytes.count)...]))
    }

    /// Walks a part: text is kept, an attachment is only named and sized, and of two versions of the same text
    /// (plain and HTML) the HTML one is used, reduced to what it shows: it is the one Mail puts on screen, so a mail
    /// can't tell the AI in its plain version what the user never saw in the other. The plain one when the HTML gives no text.
    private static func collect(_ part: ArisMailPart, depth: Int, count: inout Int, texts: inout [String], attachments: inout [ArisMailAttachment]) {
        count += 1
        guard depth <= maxDepth, count <= maxParts else { return }
        let type = part.type
        let kind = type.value.lowercased()
        if kind.hasPrefix("multipart/"), let boundary = type.parameters["boundary"], !boundary.isEmpty {
            let children = pieces(part.body, boundary: boundary).map(split)
            guard kind == "multipart/alternative" else {
                for child in children { collect(child, depth: depth + 1, count: &count, texts: &texts, attachments: &attachments) }
                return
            }
            // The same mail twice: the version Mail shows (HTML, alone or with its pictures) if it has any text, else
            // the plain one, else the first other version that gives text.
            let shown = { (part: ArisMailPart) -> Bool in
                let kind = part.type.value.lowercased()
                return kind == "text/html" || kind.hasPrefix("multipart/")
            }
            let plain = { (part: ArisMailPart) -> Bool in part.type.value.lowercased() == "text/plain" }
            let ordered = children.filter(shown) + children.filter(plain) + children.filter { !shown($0) && !plain($0) }
            for child in ordered {
                var found: [String] = []
                collect(child, depth: depth + 1, count: &count, texts: &found, attachments: &attachments)
                if found.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { texts += found; return }
            }
            return
        }
        let name = fileName(part)
        let attached = part.disposition.value.lowercased() == "attachment" || !(kind == "text/plain" || kind == "text/html")
        if attached {
            // A picture inside the text with no name of its own is part of how the mail looks, not a file to list.
            guard name != nil || part.disposition.value.lowercased() == "attachment" || !kind.hasPrefix("image/") else { return }
            attachments.append(ArisMailAttachment(name: name ?? kind, bytes: size(part)))
            return
        }
        let decoded = text(decode(part.body, encoding: part.headers["content-transfer-encoding"]), charset: type.parameters["charset"])
        texts.append(kind == "text/html" ? ArisMailText.html(decoded) : decoded)
    }

    /// The parts between a multipart's boundary lines.
    private static func pieces(_ body: Data, boundary: String) -> [Data] {
        let marker = Data(("--" + boundary).utf8)
        var parts: [Data] = [], start: Data.Index?
        var search = body.startIndex
        while let found = body.range(of: marker, in: search..<body.endIndex) {
            let atLineStart = found.lowerBound == body.startIndex || body[body.index(before: found.lowerBound)] == 0x0A
            if atLineStart {
                if let start { parts.append(trimLineEnd(body[start..<found.lowerBound])) }
                // "--boundary--" ends the list.
                if body[found.upperBound...].starts(with: Data("--".utf8)) { start = nil; break }
                start = body[found.upperBound...].firstIndex(of: 0x0A).map { body.index(after: $0) } ?? body.endIndex
            }
            search = found.upperBound
        }
        // Cut off before its closing line (a file read only to the size limit): what is there still counts.
        if let start, start < body.endIndex { parts.append(body[start...]) }
        return parts
    }

    private static func trimLineEnd(_ data: Data) -> Data {
        var end = data.endIndex
        if end > data.startIndex, data[data.index(before: end)] == 0x0A { end = data.index(before: end) }
        if end > data.startIndex, data[data.index(before: end)] == 0x0D { end = data.index(before: end) }
        return data[data.startIndex..<end]
    }

    /// An attachment's name: the disposition's filename, else the type's name.
    private static func fileName(_ part: ArisMailPart) -> String? {
        let name = part.disposition.parameters["filename"] ?? part.type.parameters["name"]
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return decodeWords(name)
    }

    /// How big an attachment is once decoded. Mail notes the size of one it took out of the file (X-Apple-Content-Length).
    private static func size(_ part: ArisMailPart) -> Int {
        if let noted = part.headers["x-apple-content-length"].flatMap({ Int($0) }), noted >= 0 { return noted }
        guard part.headers["content-transfer-encoding"]?.lowercased() == "base64" else { return part.body.count }
        let letters = part.body.reduce(0) { $1 == 0x0A || $1 == 0x0D || $1 == 0x20 || $1 == 0x3D ? $0 : $0 + 1 }
        return letters * 3 / 4
    }

    // MARK: - Decoding

    /// A part's bytes out of base64 or quoted-printable.
    static func decode(_ body: Data, encoding: String?) -> Data {
        switch encoding?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "base64": return Data(base64Encoded: body, options: .ignoreUnknownCharacters) ?? Data()
        case "quoted-printable": return quotedPrintable([UInt8](body), underscoreIsSpace: false)
        default: return body
        }
    }

    static func quotedPrintable(_ bytes: [UInt8], underscoreIsSpace: Bool) -> Data {
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x3D {
                // "=" at a line's end joins it to the next line.
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A { index += 2; continue }
                if index + 2 < bytes.count, bytes[index + 1] == 0x0D, bytes[index + 2] == 0x0A { index += 3; continue }
                if index + 2 < bytes.count, let value = UInt8(String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                    out.append(value)
                    index += 3
                    continue
                }
            }
            out.append(underscoreIsSpace && byte == 0x5F ? 0x20 : byte)
            index += 1
        }
        return Data(out)
    }

    /// Bytes as text in the charset the mail names (EUC-KR, ISO-2022-KR, Windows-1252…); with none, or one that
    /// doesn't fit, UTF-8, then the Korean one old mail uses, then Latin-1 (which reads any bytes).
    static func text(_ data: Data, charset: String?) -> String {
        if let charset = charset?.trimmingCharacters(in: .whitespaces), !charset.isEmpty {
            let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if encoding != kCFStringEncodingInvalidId,
               let text = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))) { return text }
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        let korean = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
        return String(data: data, encoding: korean) ?? String(decoding: data, as: UTF8.self)
    }

    /// A header's encoded words ("=?UTF-8?B?…?=") as text. Words next to each other in one charset are joined before
    /// they are read, since a letter's bytes may be split between them.
    static func decodeWords(_ value: String) -> String {
        guard value.contains("=?"), let regex = try? NSRegularExpression(pattern: #"=\?([^?\s]+)\?([bBqQ])\?([^?\s]*)\?="#) else { return value }
        let whole = NSRange(value.startIndex..., in: value)
        var out = "", last = value.startIndex
        var pending: (charset: String, bytes: Data)?
        func flush() { if let held = pending { out += text(held.bytes, charset: held.charset); pending = nil } }
        for match in regex.matches(in: value, range: whole) {
            guard let range = Range(match.range, in: value), let charset = Range(match.range(at: 1), in: value).map({ String(value[$0]) }),
                  let kind = Range(match.range(at: 2), in: value).map({ value[$0].lowercased() }),
                  let payload = Range(match.range(at: 3), in: value).map({ String(value[$0]) }) else { continue }
            let between = value[last..<range.lowerBound]
            let bytes = kind == "b" ? (Data(base64Encoded: payload, options: .ignoreUnknownCharacters) ?? Data())
                                    : quotedPrintable([UInt8](payload.utf8), underscoreIsSpace: true)
            // Only white space between two encoded words: it isn't part of the text.
            let onlySpace = pending != nil && between.allSatisfy(\.isWhitespace)
            if let held = pending, onlySpace, held.charset.lowercased() == charset.lowercased() {
                pending = (charset, held.bytes + bytes)
            } else {
                flush()
                if !onlySpace { out += between }
                pending = (charset, bytes)
            }
            last = range.upperBound
        }
        flush()
        return out + value[last...]
    }

    /// "text/plain; charset=utf-8; name=\"a b.pdf\"" as its value and parameters (names lowercased). A parameter in
    /// the extended form (filename*=UTF-8''%EC…, or cut into filename*0*, filename*1*) is put back together.
    static func parameters(_ header: String) -> (value: String, parameters: [String: String]) {
        var fields: [String] = [], current = "", quoted = false
        for character in header {
            if character == "\"" { quoted.toggle() }
            if character == ";" && !quoted { fields.append(current); current = "" } else { current.append(character) }
        }
        fields.append(current)
        var plain: [String: String] = [:], pieces: [String: [(Int, String, Bool)]] = [:]
        for field in fields.dropFirst() {
            guard let equals = field.firstIndex(of: "=") else { continue }
            var name = field[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            var value = field[field.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"") }
            let encoded = name.hasSuffix("*")
            if encoded { name.removeLast() }
            if let star = name.lastIndex(of: "*"), let order = Int(name[name.index(after: star)...]) {
                pieces[String(name[..<star]), default: []].append((order, value, encoded))
            } else if encoded {
                pieces[name, default: []].append((0, value, true))
            } else if plain[name] == nil {
                plain[name] = value
            }
        }
        for (name, parts) in pieces { plain[name] = extended(parts.sorted { $0.0 < $1.0 }) }
        return (fields.first?.trimmingCharacters(in: .whitespaces) ?? "", plain)
    }

    /// An extended parameter's pieces joined: the first may name a charset ("UTF-8''"), encoded pieces are %XX bytes.
    private static func extended(_ parts: [(Int, String, Bool)]) -> String {
        var charset: String?, bytes = Data()
        for (index, part) in parts.enumerated() {
            var value = part.1
            if index == 0, part.2, let first = value.firstIndex(of: "'"), let second = value[value.index(after: first)...].firstIndex(of: "'") {
                charset = String(value[..<first])
                value = String(value[value.index(after: second)...])
            }
            bytes.append(part.2 ? Data(percentDecoded(value)) : Data(value.utf8))
        }
        return text(bytes, charset: charset)
    }

    private static func percentDecoded(_ value: String) -> [UInt8] {
        let bytes = [UInt8](value.utf8)
        var out = [UInt8](), index = 0
        while index < bytes.count {
            if bytes[index] == 0x25, index + 2 < bytes.count, let byte = UInt8(String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                out.append(byte)
                index += 3
            } else {
                out.append(bytes[index])
                index += 1
            }
        }
        return out
    }

    // MARK: - Addresses

    /// The addresses in a To, Cc, From or Reply-To header: `Name <a@b>`, `"Last, First" <a@b>`, `a@b`, `a@b (Name)`.
    /// Anything without an @ is left out.
    static func addresses(_ header: String) -> [ArisMailAddress] {
        var fields: [String] = [], current = "", quoted = false, angle = 0
        for character in decodeWords(header) {
            if character == "\"" { quoted.toggle() }
            if !quoted { if character == "<" { angle += 1 } else if character == ">" { angle = max(0, angle - 1) } }
            if character == "," && !quoted && angle == 0 { fields.append(current); current = "" } else { current.append(character) }
        }
        fields.append(current)
        return fields.compactMap(address)
    }

    private static func address(_ field: String) -> ArisMailAddress? {
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = trimmed.lastIndex(of: "<"), let close = trimmed.lastIndex(of: ">"), open < close {
            let address = trimmed[trimmed.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            let name = trimmed[..<open].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")).trimmingCharacters(in: .whitespaces)
            return address.contains("@") ? ArisMailAddress(name: name, address: address) : nil
        }
        // "a@b (Name)"
        if let open = trimmed.firstIndex(of: "("), trimmed.hasSuffix(")") {
            let address = trimmed[..<open].trimmingCharacters(in: .whitespaces)
            return address.contains("@") ? ArisMailAddress(name: String(trimmed[trimmed.index(after: open)...].dropLast()), address: address) : nil
        }
        return trimmed.contains("@") && !trimmed.contains(" ") ? ArisMailAddress(name: "", address: trimmed) : nil
    }
}
