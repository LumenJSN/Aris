//
//  ArisSkillFormat.swift
//  aris-agent
//
//  The open Agent Skills format (agentskills.io, the same folders Claude Code, Codex, OpenClaw and ClawHub use): a
//  folder holding SKILL.md, whose YAML front matter names the skill (`name`) and says when to use it (`description`),
//  then the instructions; optional scripts/, references/ and assets/ beside it. This reads the front matter (a small
//  YAML subset: plain, quoted and block scalars, and one level of `metadata`), checks the format's limits and Aris's own
//  size caps, and never runs anything. Pure, so the tests run it.
//

import Foundation

struct ArisSkillManifest: Equatable {
    /// The format's id: lowercase letters, digits and single hyphens ("meeting-minutes").
    let name: String
    let description: String
    /// The instructions after the front matter.
    let body: String
    let license: String?
    /// `metadata:` (string values only), e.g. version, title.
    let metadata: [String: String]

    /// What the user sees: metadata's title when the skill has one, else the name with spaces.
    var title: String {
        if let title = metadata["title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { return String(title.prefix(40)) }
        return name.replacingOccurrences(of: "-", with: " ")
    }

    var version: String? { metadata["version"] }
}

enum ArisSkillProblem: Error, Equatable {
    case noSkillFile
    case tooBig(String)
    case noFrontMatter
    case badName(String)
    case noDescription
    case descriptionTooLong
    case link(String)
    case outside(String)
    case unreadable(String)

    /// What the user reads (Korean, short).
    var message: String {
        switch self {
        case .noSkillFile: return "SKILL.md가 없어요. 스킬 폴더에는 SKILL.md가 있어야 해요."
        case .tooBig(let what): return "너무 커요 (\(what))."
        case .noFrontMatter: return "SKILL.md 맨 위에 name과 description이 없어요."
        case .badName(let name): return "스킬 이름 ‘\(name.prefix(40))’은 쓸 수 없어요. 소문자, 숫자, 하이픈만 돼요."
        case .noDescription: return "SKILL.md에 description이 없어요."
        case .descriptionTooLong: return "description이 너무 길어요 (1024자까지)."
        case .link(let path): return "링크 파일은 받지 않아요: \(path.prefix(80))"
        case .outside(let path): return "스킬 폴더 밖을 가리켜요: \(path.prefix(80))"
        case .unreadable(let path): return "읽을 수 없는 파일이 있어요: \(path.prefix(80))"
        }
    }
}

enum ArisSkillFormat {
    static let skillFile = "SKILL.md"
    /// The format's limits.
    static let maxName = 64
    static let maxDescription = 1_024
    /// Aris's own caps on one skill (a skill is instructions and a few small scripts, never a program's worth).
    static let maxSkillFile = 256 * 1_024
    static let maxTotalBytes = 20 * 1_024 * 1_024
    static let maxFiles = 500
    static let maxDepth = 8

    /// Whether `name` is a valid skill name: 1–64 of a-z, 0-9 and "-", not starting or ending with "-", no "--".
    static func isName(_ name: String) -> Bool {
        guard (1...maxName).contains(name.count), !name.hasPrefix("-"), !name.hasSuffix("-"), !name.contains("--") else { return false }
        return name.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// A name as people write it ("Meeting Minutes", "meeting_minutes") made into the format's form, or nil.
    static func normalizedName(_ raw: String) -> String? {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: #"[\s_]+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"-{2,}"#, with: "-", options: .regularExpression)
        return isName(lowered) ? lowered : nil
    }

    /// Reads SKILL.md's text: its front matter, then the body.
    static func parse(_ text: String) -> Result<ArisSkillManifest, ArisSkillProblem> {
        guard text.utf8.count <= maxSkillFile else { return .failure(.tooBig("SKILL.md \(maxSkillFile / 1_024)KB")) }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: "")
        var lines = normalized.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return .failure(.noFrontMatter) }
        lines.removeFirst()
        guard let end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return .failure(.noFrontMatter) }
        let fields = frontMatter(Array(lines[..<end]))
        let body = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawName = fields.top["name"], !rawName.isEmpty else { return .failure(.noFrontMatter) }
        guard let name = isName(rawName) ? rawName : normalizedName(rawName) else { return .failure(.badName(rawName)) }
        let description = (fields.top["description"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return .failure(.noDescription) }
        guard description.count <= maxDescription else { return .failure(.descriptionTooLong) }
        return .success(ArisSkillManifest(name: name, description: description, body: body, license: fields.top["license"],
                                          metadata: fields.metadata))
    }

    // MARK: - The YAML subset

    private struct Fields {
        var top: [String: String] = [:]
        var metadata: [String: String] = [:]
    }

    /// Top-level `key: value` pairs (plain, 'single' or "double" quoted, or a `|` / `>` block), and `metadata:`'s
    /// indented pairs. Anything else (lists, deeper maps) is skipped.
    private static func frontMatter(_ lines: [String]) -> Fields {
        var fields = Fields()
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let (key, rest) = pair(line) else { continue }
            if key == "metadata" && rest.isEmpty {
                while index < lines.count, lines[index].hasPrefix(" ") || lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    if let (inner, value) = pair(lines[index].trimmingCharacters(in: .whitespaces)), !value.isEmpty, fields.metadata.count < 32 {
                        fields.metadata[inner] = String(scalar(value).prefix(200))
                    }
                    index += 1
                }
                continue
            }
            if rest == "|" || rest == ">" || rest.hasPrefix("|-") || rest.hasPrefix(">-") || rest.hasPrefix("|+") || rest.hasPrefix(">+") {
                var block: [String] = []
                while index < lines.count, lines[index].hasPrefix(" ") || lines[index].hasPrefix("\t") || lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    block.append(lines[index].trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                while block.last?.isEmpty == true { block.removeLast() }
                fields.top[key] = rest.hasPrefix("|") ? block.joined(separator: "\n") : folded(block)
                continue
            }
            // A plain scalar may go on over indented lines.
            var value = rest
            while index < lines.count, lines[index].hasPrefix(" "), !value.hasPrefix("\""), !value.hasPrefix("'") {
                value += " " + lines[index].trimmingCharacters(in: .whitespaces)
                index += 1
            }
            fields.top[key] = scalar(value)
        }
        return fields
    }

    /// `key: rest`, the key a plain word.
    private static func pair(_ line: String) -> (String, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key.count <= 64, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return (key, line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
    }

    /// A folded block: lines joined with spaces, blank lines kept as breaks.
    private static func folded(_ block: [String]) -> String {
        block.split(separator: "", omittingEmptySubsequences: false).map { $0.joined(separator: " ") }.joined(separator: "\n")
    }

    /// A scalar's value: quotes taken off ('' and \" unescaped), a trailing comment dropped from a plain one.
    private static func scalar(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        // A quoted scalar ends at its closing quote (a comment may follow it).
        if text.hasPrefix("\""), let close = closing(text, quote: "\"") {
            return String(text[text.index(after: text.startIndex)..<close]).replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\n", with: "\n")
        }
        if text.hasPrefix("'"), let close = closing(text, quote: "'") {
            return String(text[text.index(after: text.startIndex)..<close]).replacingOccurrences(of: "''", with: "'")
        }
        if let comment = text.range(of: " #") { return String(text[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces) }
        return text
    }

    /// Where a quoted scalar's closing quote is ('' inside single quotes and \" inside double ones don't close it).
    private static func closing(_ text: String, quote: Character) -> String.Index? {
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if quote == "\"", character == "\\" { index = next < text.endIndex ? text.index(after: next) : next; continue }
            if character == quote {
                if quote == "'", next < text.endIndex, text[next] == "'" { index = text.index(after: next); continue }
                return index
            }
            index = next
        }
        return nil
    }
}

/// Why something about a skill didn't happen, already in the user's words.
struct ArisSkillWhy: Error, Equatable, ExpressibleByStringInterpolation, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    init(stringLiteral value: String) { message = value }
    var description: String { message }
}

/// Characters that hide or reorder text (security review M2): controls (Cc) other than tab and line breaks, format
/// characters (Cf: zero-width, bidi embeddings and isolates), and the bidi marks. Refused in archive paths, script
/// arguments and the prompt's list; shown escaped on cards.
enum ArisSkillText {
    static func isHidden(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "\n" || scalar == "\t" || scalar == "\r" { return false }
        switch scalar.properties.generalCategory {
        case .control, .format: return true
        default: return scalar.properties.isBidiControl
        }
    }

    static func hasHidden(_ text: String) -> Bool { text.unicodeScalars.contains(where: isHidden) }

    /// The text with each hidden character written out ("[U+202E]"), for a card.
    static func visible(_ text: String) -> String {
        text.unicodeScalars.map { isHidden($0) ? String(format: "[U+%04X]", $0.value) : String($0) }.joined()
    }
}
