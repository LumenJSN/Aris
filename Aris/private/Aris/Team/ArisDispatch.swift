//
//  ArisDispatch.swift
//  Aris
//
//  Reads the main brain's dispatch reply: a fenced json block {"jobs":[…]} instead of a spoken answer.
//  Anything else (plain answer, broken json, no jobs) is nil, so it falls back to a normal answer.
//

import Foundation

enum ArisDispatch {
    static let maxJobs = 5
    static let maxTitle = 40

    /// The ids a jobs block may name: every teammate in the user's list, and Claude Code always (also before the list is in).
    static func teammateIds(_ teammates: [ArisTeammate]) -> Set<String> {
        Set(teammates.map(\.id)).union([ArisTeammate.claudeCodeId])
    }

    static func parse(_ reply: String, teammateIds: Set<String>) -> [ArisJobSpec]? {
        for block in jobsBlocks(in: reply) {
            guard let raw = block.root["jobs"] as? [[String: Any]] else { continue }
            let specs = raw.prefix(maxJobs).compactMap { spec($0, teammateIds: teammateIds) }
            return specs.isEmpty ? nil : specs
        }
        return nil
    }

    private static func spec(_ item: [String: Any], teammateIds: Set<String>) -> ArisJobSpec? {
        guard let prompt = nonEmpty(item["prompt"]) else { return nil }
        let assignee: ArisJobAssignee = nonEmpty(item["assignee"]).flatMap { teammateIds.contains($0) ? .teammate($0) : nil } ?? .clone
        let title = nonEmpty(item["title"]) ?? prompt
        return ArisJobSpec(title: shortened(title), prompt: prompt, assignee: assignee,
                           cwd: nonEmpty(item["cwd"]), appHint: nonEmpty(item["appHint"]))
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func shortened(_ title: String) -> String {
        title.count > maxTitle ? String(title.prefix(maxTitle)) + "…" : title
    }

    /// Whether this turn's answer may be dispatched: never with the screen's text ("이거") in it; after the agent said
    /// the turn is untrusted, only when it also said dispatch is allowed (a screen turn: jobs untrusted, launches ask).
    static func mayDispatch(screenText: Bool, untrustedTurn: Bool, dispatchAllowed: Bool) -> Bool {
        !screenText && (!untrustedTurn || dispatchAllowed)
    }

    /// The turn id a dispatched job carries to the agent: none from an untrusted turn, so its Claude Code launch always
    /// shows the user's card (the agent sends none then either).
    static func turnId(_ id: String?, untrustedTurn: Bool) -> String? {
        untrustedTurn ? nil : id
    }

    /// The range of the first jobs block (its fence or "json" label included); nil when there is none. The controller
    /// holds it back from speech, the notch and the stored reply.
    static func jobsBlockRange(in text: String) -> Range<String.Index>? {
        jobsBlocks(in: text).first?.range
    }

    /// Every block whose root object has a `jobs` key, in order: a ```json or ```jobs fence, or a bare JSON object that is
    /// the whole trailing part of the answer (Claude writes it unfenced at times; a "json" label line just before it, the
    /// remains of a fence, goes with it). A JSON example inside any other fence, or bare in the middle of prose, is
    /// never a jobs block.
    static func jobsBlocks(in text: String) -> [(range: Range<String.Index>, root: [String: Any])] {
        let all = fences(in: text)
        var blocks: [(range: Range<String.Index>, root: [String: Any])] = all.compactMap { fence in
            guard ["json", "jobs"].contains(fence.tag), let root = jobsRoot(fence.body) else { return nil }
            return (fence.range, root)
        }
        let tail = (all.last?.range.upperBound ?? text.startIndex)..<text.endIndex
        if let span = jsonObjects(in: text, tail).last, text[span.upperBound...].allSatisfy(\.isWhitespace),
           let root = jobsRoot(String(text[span])) {
            blocks.append((withLabel(text, span, from: tail.lowerBound), root))
        }
        return blocks
    }

    /// A "json" word alone on the line before `span` (the remains of a ```json fence) belongs to the block.
    private static func withLabel(_ text: String, _ span: Range<String.Index>, from start: String.Index) -> Range<String.Index> {
        let before = text[start..<span.lowerBound]
        guard let label = before.range(of: #"(?i)(?:^|\n)[ \t]*json[ \t]*\n[ \t]*$"#, options: .regularExpression) else { return span }
        let lead = before[label].first == "\n" ? before.index(after: label.lowerBound) : label.lowerBound
        return lead..<span.upperBound
    }

    private static func jobsRoot(_ body: String) -> [String: Any]? {
        guard let data = body.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], root["jobs"] != nil else { return nil }
        return root
    }

    /// The ``` fences in order: each one's full range, its language tag (lowercased; empty for none) and its body.
    private static func fences(in text: String) -> [(range: Range<String.Index>, tag: String, body: String)] {
        var fences: [(Range<String.Index>, String, String)] = []
        var from = text.startIndex
        while let open = text.range(of: "```", range: from..<text.endIndex) {
            guard let close = text.range(of: "```", range: open.upperBound..<text.endIndex) else { break }
            let inside = text[open.upperBound..<close.lowerBound]
            let first = inside.prefix { $0 != "\n" }
            let isTag = first.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " }
            let tag = isTag ? first.trimmingCharacters(in: .whitespaces).lowercased() : ""
            fences.append((open.lowerBound..<close.upperBound, tag, String(isTag ? inside.dropFirst(first.count) : inside)))
            from = close.upperBound
        }
        return fences
    }

    /// The JSON objects in `range` that parse whole, outermost only: an object starts at a { followed by a quote, and
    /// ends at its matching } (braces inside strings don't count). Used by the agent and the app alike.
    static func jsonObjects(in text: String, _ range: Range<String.Index>? = nil) -> [Range<String.Index>] {
        let range = range ?? text.startIndex..<text.endIndex
        var found: [Range<String.Index>] = []
        var i = range.lowerBound
        while let open = text[i..<range.upperBound].firstIndex(of: "{") {
            let next = text[text.index(after: open)..<range.upperBound].first { !$0.isWhitespace }
            guard next == "\"", let close = matchingBrace(text, from: open, end: range.upperBound) else {
                i = text.index(after: open)
                continue
            }
            let span = open..<text.index(after: close)
            if let data = String(text[span]).data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
                found.append(span)
                i = span.upperBound
            } else {
                i = text.index(after: open)
            }
        }
        return found
    }

    private static func matchingBrace(_ text: String, from open: String.Index, end: String.Index) -> String.Index? {
        var depth = 0, inString = false, escaped = false
        var i = open
        while i < end {
            let c = text[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" || c == "[" {
                depth += 1
            } else if c == "}" || c == "]" {
                depth -= 1
                if depth == 0 { return c == "}" ? i : nil }
                if depth < 0 { return nil }
            }
            i = text.index(after: i)
        }
        return nil
    }
}
