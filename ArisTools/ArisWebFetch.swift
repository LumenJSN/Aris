//
//  ArisWebFetch.swift
//  aris-tools
//
//  `aris-tools web fetch <address>`: one public web page as plain text, for agy's relay (its own read tools are denied,
//  so Aris fetches the page after the judge allowed the address: ArisAgyRelay.runJudged). Only http(s) to a public host:
//  no credentials in the address, no localhost, private, link-local or .local host, no bare-number IP or octet with a
//  leading zero, and every address the name resolves to must be public (v4 and v6: no private, loopback, link-local,
//  CGNAT or ULA); a redirect is checked the same way, and the body is read with a hard 2 MB cap. The Claudes' WebFetch
//  addresses pass the same check in their hooks. Pure parts here (the resolver passed in), so the tests run them.
//

import Foundation

enum ArisWebFetch {
    static let maxBytes = 2_000_000
    static let maxText = 6_000
    static let timeout: TimeInterval = 15

    /// The address when it may be fetched; nil otherwise.
    static func checkURL(_ text: String) -> URL? {
        guard text.count <= 2_048, let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme), components.user == nil, components.password == nil,
              let host = components.host, isPublicHost(host), let url = components.url else { return nil }
        return url
    }

    /// A host name that names a public machine: letters in it (so no bare-number or hex IP), a dot, no IPv6 literal,
    /// nothing local; or a dotted IPv4 address outside the private, loopback, link-local and reserved ranges.
    static func isPublicHost(_ raw: String) -> Bool {
        let host = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty, !host.contains(":"), !host.contains("%"), host.contains(".") else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".internal") || host.hasSuffix(".lan") { return false }
        let parts = host.split(separator: ".").map(String.init)
        if parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            // 010.0.0.1 is octal to some resolvers.
            guard !parts.contains(where: { $0.count > 1 && $0.hasPrefix("0") }) else { return false }
            let octets = parts.compactMap { UInt8($0) }
            guard parts.count == 4, octets.count == 4 else { return false }
            return isPublicIPv4(octets)
        }
        // A name with a part like 0x7f… is read as a number by some resolvers.
        if parts.contains(where: { $0.hasPrefix("0x") }) { return false }
        return host.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    /// The address when it may be fetched and every address its host resolves to is public; nil otherwise (one that
    /// doesn't resolve included).
    static func allows(_ text: String, resolve: (String) -> [String]? = liveResolve) -> URL? {
        guard let url = checkURL(text), let host = url.host, let addresses = resolve(host), !addresses.isEmpty,
              addresses.allSatisfy(isPublicAddress) else { return nil }
        return url
    }

    /// One numeric address (v4 or v6) that is public.
    static func isPublicAddress(_ text: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, text, &v4) == 1 {
            return isPublicIPv4(withUnsafeBytes(of: v4.s_addr) { Array($0) })
        }
        let bare = text.split(separator: "%").first.map(String.init) ?? text
        guard inet_pton(AF_INET6, bare, &v6) == 1 else { return false }
        let b = withUnsafeBytes(of: v6) { Array($0) }
        if b.allSatisfy({ $0 == 0 }) { return false }                                   // ::
        if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return false }             // ::1
        if b[0] == 0xFE && (b[1] & 0xC0) == 0x80 { return false }                         // fe80::/10 link-local
        if b[0] == 0xFE && (b[1] & 0xC0) == 0xC0 { return false }                         // fec0::/10 site-local
        if (b[0] & 0xFE) == 0xFC { return false }                                         // fc00::/7 ULA
        if b[0] == 0xFF { return false }                                                  // multicast
        if b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0D && b[3] == 0xB8 { return false }  // documentation
        // An IPv4 address inside (mapped, compatible, NAT64): judged as that address.
        if b[0..<10].allSatisfy({ $0 == 0 }) && ((b[10] == 0xFF && b[11] == 0xFF) || (b[10] == 0 && b[11] == 0)) {
            return isPublicIPv4(Array(b[12..<16]))
        }
        if b[0] == 0x00 && b[1] == 0x64 && b[2] == 0xFF && b[3] == 0x9B { return isPublicIPv4(Array(b[12..<16])) }
        return true
    }

    /// The addresses a fetch's transactions connected to (URLSessionTaskTransactionMetrics.remoteAddress): at least one,
    /// and every one public; a transaction with none (or none at all) fails closed.
    static func connectedPublicly(_ addresses: [String?]) -> Bool {
        !addresses.isEmpty && addresses.allSatisfy { address in
            guard let address else { return false }
            return isPublicAddress(address.trimmingCharacters(in: CharacterSet(charactersIn: "[]")))
        }
    }

    /// Every address the host resolves to, numeric; nil when it doesn't resolve.
    static func liveResolve(_ host: String) -> [String]? {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0,
                             ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { return nil }
        defer { freeaddrinfo(list) }
        var found: [String] = []
        var node: UnsafeMutablePointer<addrinfo>? = first
        while let current = node {
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if let address = current.pointee.ai_addr,
               getnameinfo(address, current.pointee.ai_addrlen, &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0 {
                found.append(String(cString: name))
            }
            node = current.pointee.ai_next
        }
        return found.isEmpty ? nil : found
    }

    private static func isPublicIPv4(_ o: [UInt8]) -> Bool {
        switch (o[0], o[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168), (100, 64...127), (198, 18...19): return false
        case (172, 16...31): return false
        case (224...255, _): return false
        default: return true
        }
    }

    /// A page's readable text: scripts, styles and comments dropped, tags taken out (block ends as line breaks), the
    /// common entities decoded, blank runs folded, cut to `maxText`.
    static func text(fromHTML html: String) -> String {
        var text = html
        for (open, close) in [("<!--", "-->"), ("<head", "</head"), ("<script", "</script"), ("<style", "</style"), ("<noscript", "</noscript")] {
            text = cut(text, from: open, to: close)
        }
        text = text.replacingOccurrences(of: #"(?i)<(br|/p|/div|/li|/h[1-6]|/tr|/section|/article)\b[^>]*>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        text = decodeEntities(text)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{A0}" }).joined(separator: " ") }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")
        guard joined.count > maxText else { return joined }
        return String(joined.prefix(maxText)) + "\n…(cut)"
    }

    /// `text` without every run from `open` to the end of the next `close` (the rest of the page when it never closes),
    /// in one pass: no backtracking, however many open tags there are.
    static func cut(_ text: String, from open: String, to close: String) -> String {
        var result = "", rest = text[...]
        while let start = tag(open, in: rest) {
            result += rest[..<start.lowerBound] + " "
            guard let end = tag(close, in: rest[start.upperBound...]) else { return result }
            rest = rest[end.upperBound...]
            if let gt = rest.firstIndex(of: ">"), close != "-->" { rest = rest[rest.index(after: gt)...] }
        }
        return result + rest
    }

    /// The first `name` in `text` (any case) that ends there as a tag name: `<head` never matches `<header>`. A comment
    /// marker matches as it is. Each search goes on from the last, so it stays one pass.
    private static func tag(_ name: String, in text: Substring) -> Range<Substring.Index>? {
        var from = text.startIndex
        while let found = text[from...].range(of: name, options: .caseInsensitive) {
            guard name.hasPrefix("<"), name.hasPrefix("<!") == false, name.hasSuffix(">") == false else { return found }
            guard found.upperBound < text.endIndex else { return found }
            let next = text[found.upperBound]
            if next == ">" || next == "/" || next.isWhitespace { return found }
            from = found.upperBound
        }
        return nil
    }

    private static let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "#39": "'"]

    static func decodeEntities(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z]{2,8});") else { return text }
        var result = "", last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text) else { continue }
            result += text[last..<whole.lowerBound]
            let name = String(text[inner])
            if let value = named[name.lowercased()] {
                result += value
            } else if name.hasPrefix("#x"), let code = UInt32(name.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
            } else if name.hasPrefix("#"), let code = UInt32(name.dropFirst()), let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
            } else {
                result += text[whole]
            }
            last = whole.upperBound
        }
        return result + text[last...]
    }
}
