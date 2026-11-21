//
//  ArisTeachMatch.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  The values of a run from the owner's words (ARCHITECTURE Part 3, F3): "출근 준비 해 줘, 제목은 월간 보고" fills the
//  parameter labelled 제목; "보고서 보내기 김팀장한테" fills the one whose field is a recipient's; with one parameter, what
//  he said beside the name fills it. A parameter he doesn't mention keeps the value he typed when he showed it. Also
//  how a procedure's name is matched however it is spelled. Pure.
//

import Foundation

enum ArisTeachNames {
    /// Letters and digits only, lowercased: "출근 준비", "출근준비" and "출근-준비" are one name.
    static func key(_ raw: String) -> String {
        let folded = raw.precomposedStringWithCanonicalMapping.lowercased()
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    /// A name as it is kept: one line, no quotes or closing marks, at most 30 characters.
    static func clean(_ raw: String) -> String {
        let quotes = CharacterSet(charactersIn: "\"'“”‘’「」『』`")
        let words = raw.precomposedStringWithCanonicalMapping.components(separatedBy: quotes.union(.newlines)).joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        let trimmed = words.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;!?~ "))
        return String(trimmed.prefix(30))
    }

    static func find(_ said: String, in procedures: [ArisTeachProcedure]) -> ArisTeachProcedure? {
        let wanted = key(said)
        guard !wanted.isEmpty else { return nil }
        return procedures.first { key($0.name) == wanted }
    }

    /// The procedure whose name `words` start with (the longest name wins), and the words after it.
    static func leading(_ words: String, in procedures: [ArisTeachProcedure]) -> (ArisTeachProcedure, String)? {
        let said = words.precomposedStringWithCanonicalMapping
        var best: (ArisTeachProcedure, String, Int)?
        for procedure in procedures {
            let wanted = key(procedure.name)
            guard wanted.count >= 2, let rest = after(key: wanted, in: said) else { continue }
            if best == nil || wanted.count > best!.2 { best = (procedure, rest, wanted.count) }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// The text after the first letters of `said` that spell `key` (spaces and marks between them skipped); nil when
    /// `said` doesn't start with it.
    static func after(key: String, in said: String) -> String? {
        var wanted = Array(key)
        var index = said.startIndex
        let skippable = CharacterSet.alphanumerics.inverted
        // Leading quotes and spaces.
        while index < said.endIndex, said[index].unicodeScalars.allSatisfy({ skippable.contains($0) }) { index = said.index(after: index) }
        while !wanted.isEmpty, index < said.endIndex {
            let character = said[index]
            let folded = String(character).precomposedStringWithCanonicalMapping.lowercased()
            if folded.unicodeScalars.allSatisfy({ skippable.contains($0) }) { index = said.index(after: index); continue }
            guard let first = wanted.first, folded == String(first) else { return nil }
            wanted.removeFirst()
            index = said.index(after: index)
        }
        guard wanted.isEmpty else { return nil }
        // The name must end at a word's end or a particle, not in the middle of a longer word ("출근준비물").
        let rest = String(said[index...])
        if let next = rest.first, next.isLetter, !ArisTeachMatch.startsWithParticle(rest) { return nil }
        return rest
    }
}

enum ArisTeachMatch {
    /// Particles and endings that may follow the name ("출근 준비를 해 줘", "출근 준비 좀").
    static let particles = ["을", "를", "은", "는", "이", "가", "도", "좀", "로", "으로"]
    /// The words that ask for it to be done, at the end ("해 줘", "실행해", "please").
    static let doing = #"(?:\s*(?:좀|다시|한\s*번|한번))*\s*(?:해\s*줘요?|해줘요?|해\s*주세요|해\s*줄래(?:요)?|해\s*봐|하자|해|실행해\s*줘|실행해|실행|돌려\s*줘|돌려|시작해\s*줘|시작해|시작|please|now)?[\s.!?~]*$"#
    /// Words that mark a recipient's field ("받는 사람", "To").
    static let recipientLabels = ["받는 사람", "받는사람", "받는 이", "수신", "수신자", "to", "recipient", "recipients", "대상", "보낼 사람"]

    static func startsWithParticle(_ text: String) -> Bool {
        particles.contains { text.hasPrefix($0) && (text.count == $0.count || !(text.dropFirst($0.count).first?.isLetter ?? false) || $0 == "좀") }
    }

    /// The words of a run with the name taken off: the asking words at the end, a leading particle and comma.
    static func rest(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for particle in particles.sorted(by: { $0.count > $1.count }) where text.hasPrefix(particle) {
            let after = text.dropFirst(particle.count)
            if after.isEmpty || after.first == " " || after.first == "," { text = String(after); break }
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,，:;"))
        return withoutAsking(text)
    }

    /// The asking words taken off both ends ("해 줘, 제목은 …", "… 로 해 줘").
    static func withoutAsking(_ raw: String) -> String {
        var text = raw
        if let range = text.range(of: leadingAsk, options: [.regularExpression, .caseInsensitive]) { text.removeSubrange(range) }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,，:;"))
        if let range = text.range(of: doing, options: [.regularExpression, .caseInsensitive]) { text.removeSubrange(range) }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ,，.;:"))
    }

    /// Asking words at the start, before the values ("해 줘, 제목은 월간 보고").
    static let leadingAsk = #"^(?:좀\s*)?(?:해\s*줘요?|해줘요?|해\s*주세요|실행해\s*줘|실행해|돌려\s*줘|시작해\s*줘|하자|해)(?=[\s,，]|$)[\s,，]*"#

    /// Whether the words beside the name ask for it to be done (at their start or their end).
    static func asks(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.range(of: leadingAsk, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        return text.range(of: #"(?:해\s*줘|해줘|해\s*주세요|실행해|실행|돌려|시작|하자|해|please)[\s.!?~]*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Whether the words after the name only ask for it to be done (nothing to fill).
    static func onlyAsks(_ raw: String) -> Bool { rest(raw).isEmpty }

    /// The run's values from the words after the name: by a parameter's label, a recipient's "…한테", or (with one
    /// parameter) all of what is left. Keys of the parameters filled.
    static func values(_ procedure: ArisTeachProcedure, words raw: String) -> [String: String] {
        var left = rest(raw)
        guard !left.isEmpty, !procedure.parameters.isEmpty else { return [:] }
        var found: [String: String] = [:]
        // "제목은 월간 보고", "제목: 월간 보고", "subject is monthly report": up to the next comma or the next label.
        let labels = procedure.parameters.map(\.label).filter { !$0.isEmpty }
        for parameter in procedure.parameters.sorted(by: { $0.label.count > $1.label.count }) where !parameter.label.isEmpty {
            let label = labelPattern(parameter.label)
            let others = labels.filter { $0 != parameter.label }.map(labelPattern)
            let stop = others.isEmpty ? "" : "|\\s(?=(?:" + others.joined(separator: "|") + ")(?:은|는|을|를|이|가|:|\\s))"
            let pattern = "(?:^|[\\s,])" + label + "(?:은|는|을|를|이|가)?\\s*(?:[:=]|is|으로|로)?\\s*(.+?)(?:\\s*(?:으로|로|이요|요|라고|이라고))?(?=$|,|，" + stop + ")"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: left, range: NSRange(left.startIndex..., in: left)),
                  let whole = Range(match.range, in: left), let value = Range(match.range(at: 1), in: left) else { continue }
            let text = cleaned(String(left[value]))
            guard !text.isEmpty else { continue }
            found[parameter.key] = text
            left.removeSubrange(whole)
            left = left.trimmingCharacters(in: CharacterSet(charactersIn: " ,，"))
        }
        // "김팀장한테", "to Kim": a recipient's field.
        if let recipient = procedure.parameters.first(where: { found[$0.key] == nil && isRecipient($0.label) }) {
            let pattern = #"(?:^|[\s,])(?:to\s+(\S+(?:\s\S+)?)|(\S+?)(?:한테|에게|께|한테로))(?=$|[\s,])"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: left, range: NSRange(left.startIndex..., in: left)), let whole = Range(match.range, in: left) {
                let value = [1, 2].compactMap { Range(match.range(at: $0), in: left) }.first.map { String(left[$0]) } ?? ""
                if !value.isEmpty {
                    found[recipient.key] = cleaned(value)
                    left.removeSubrange(whole)
                    left = left.trimmingCharacters(in: CharacterSet(charactersIn: " ,，"))
                }
            }
        }
        // One parameter left and words left: they are its value.
        left = withoutAsking(left)
        let open = procedure.parameters.filter { found[$0.key] == nil }
        if open.count == 1, !cleaned(left).isEmpty {
            found[open[0].key] = cleaned(left)
        }
        return found
    }

    /// A label as the owner may say it: a document's main text ("본문", Aris's own word) also as the English UI shows it
    /// ("text") or "body" (fourth VM run, D8).
    static func labelPattern(_ label: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        guard label.hasPrefix(ArisTeachGeneralise.bodyLabel) else { return escaped }
        let rest = NSRegularExpression.escapedPattern(for: String(label.dropFirst(ArisTeachGeneralise.bodyLabel.count)))
        return "(?:" + NSRegularExpression.escapedPattern(for: ArisTeachGeneralise.bodyLabel) + "|text|body)" + rest
    }

    static func isRecipient(_ label: String) -> Bool {
        let folded = label.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        return recipientLabels.contains(folded) || folded.hasPrefix("to ") || folded.contains("받는")
    }

    /// A value as said: no quotes around it, no particle or ending after it.
    static func cleaned(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.!?~")))
        let quotes = CharacterSet(charactersIn: "\"'“”‘’「」『』")
        text = text.trimmingCharacters(in: quotes)
        for ending in ["이라고", "라고", "으로", "로"] where text.hasSuffix(ending) && text.count > ending.count + 1 {
            text = String(text.dropLast(ending.count))
            break
        }
        return text.trimmingCharacters(in: quotes.union(.whitespaces))
    }
}
