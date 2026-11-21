//
//  ArisTextDecoding.swift
//  aris-tools
//
//  A page's or an HTML file's bytes as text, in the charset it is really in (a Korean site in EUC-KR read as UTF-8
//  came out as replacement marks): the charset the server declared, else a byte-order mark, else the one the page
//  names in a <meta> near its top, else UTF-8 when the bytes are valid UTF-8, else CP949 when that reads them as
//  Korean, else Windows-1252. The Korean labels (euc-kr, ks_c_5601-1987, cp949, windows-949) are read as CP949, the
//  superset browsers use for all of them (EUC-KR alone has no 똠 or 뷁). Pure.
//

import Foundation

enum ArisTextDecoding {
    static let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
    static let koreanLabels: Set<String> = ["euc-kr", "euckr", "cp949", "ms949", "windows-949", "x-windows-949", "ks_c_5601-1987",
                                            "ks_c_5601-1989", "ksc5601", "ksc_5601", "korean", "csksc56011987", "iso-ir-149", "uhc"]
    /// How far into the bytes a <meta> charset is looked for (the HTML standard's prescan reads 1,024).
    static let sniffedBytes = 2_048

    /// The text of `data`; `contentType`: the Content-Type header, when there is one.
    static func decode(_ data: Data, contentType: String = "") -> String {
        if let bom = byteOrderMark(data), let text = String(data: data, encoding: bom) { return text }
        for label in [charset(contentType: contentType), sniffedCharset(data)].compactMap({ $0 }) {
            if let encoding = encoding(named: label), let text = String(data: data, encoding: encoding) { return text }
        }
        // A body cut at the size cap may end inside a character: up to three bytes are left off for that.
        for cut in 0...min(3, data.count) {
            if let text = String(data: data.dropLast(cut), encoding: .utf8) { return text }
        }
        if let text = String(data: data, encoding: cp949), looksKorean(text) { return text }
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    /// The `charset=` of a Content-Type ("text/html; charset=EUC-KR" → "euc-kr").
    static func charset(contentType: String) -> String? {
        for part in contentType.split(separator: ";").dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, pair[0].lowercased() == "charset" else { continue }
            let value = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'")).lowercased()
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// The charset a page names in its first bytes: `<meta charset="…">` or `<meta http-equiv … content="…charset=…">`,
    /// and an XML declaration's encoding.
    static func sniffedCharset(_ data: Data) -> String? {
        let head = String(decoding: data.prefix(sniffedBytes).map { $0 < 0x80 ? $0 : 0x20 }, as: UTF8.self)
        let patterns = [#"(?i)<meta[^>]*?charset\s*=\s*["']?\s*([A-Za-z0-9_:.+-]+)"#, #"(?i)<\?xml[^>]*?encoding\s*=\s*["']([A-Za-z0-9_:.+-]+)"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
                  let range = Range(match.range(at: 1), in: head) else { continue }
            return head[range].lowercased()
        }
        return nil
    }

    /// The encoding for a charset label; nil for one this Mac doesn't know.
    static func encoding(named label: String) -> String.Encoding? {
        let name = label.lowercased().trimmingCharacters(in: .whitespaces)
        if koreanLabels.contains(name) { return cp949 }
        if name == "utf-8" || name == "utf8" { return .utf8 }
        // A page that says Latin-1 is read as Windows-1252, as browsers do (its curly quotes are in 0x80–0x9F).
        if ["iso-8859-1", "latin1", "us-ascii", "ascii"].contains(name) { return .windowsCP1252 }
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    private static func byteOrderMark(_ data: Data) -> String.Encoding? {
        let b = [UInt8](data.prefix(3))
        if b.count >= 3, b[0] == 0xEF, b[1] == 0xBB, b[2] == 0xBF { return .utf8 }
        if b.count >= 2, b[0] == 0xFE, b[1] == 0xFF { return .utf16BigEndian }
        if b.count >= 2, b[0] == 0xFF, b[1] == 0xFE { return .utf16LittleEndian }
        return nil
    }

    /// Most of what isn't ASCII is Hangul syllables: the bytes were Korean, not Latin text that CP949 also takes.
    private static func looksKorean(_ text: String) -> Bool {
        let wide = text.unicodeScalars.filter { !$0.isASCII }
        guard !wide.isEmpty else { return false }
        return wide.filter { (0xAC00...0xD7A3).contains($0.value) }.count * 2 >= wide.count
    }
}
