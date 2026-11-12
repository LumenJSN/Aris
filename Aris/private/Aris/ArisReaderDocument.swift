//
//  ArisReaderDocument.swift
//  Aris
//
//  The owner's 2A (mockups/done-and-reader.html): what the Aris reader shows. A saved task result (~/Documents/Aris/<date>
//  <title>.md), a whole answer ("답 열기") or the AI's board, as ArisBoardContent's blocks with a title, the line under
//  it and the bar's words. Inline marks become runs of styled text: never HTML, never a loaded image, and a link is
//  shown as its own address (only http, https and mailto ones can be clicked, and a click copies it). Pure, so it's
//  tested.
//

import Foundation

enum ArisReaderInline {
    enum Style: Equatable {
        case plain, strong, emphasis, strongEmphasis, code
        /// Shown as its address; a click copies it, nothing is opened.
        case link(URL)
    }

    struct Run: Equatable {
        let text: String
        let style: Style
    }

    static func runs(_ text: String) -> [Run] {
        guard let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return merged(bare(text, style: .plain))
        }
        var out: [Run] = []
        for run in parsed.runs {
            let words = String(parsed[run.range].characters)
            let style = style(of: run.inlinePresentationIntent ?? [])
            // An image is its words: imageURL is never read, so nothing is loaded.
            if let link = run.link {
                guard let safe = safeLink(link) else {
                    out += [Run(text: words, style: style)]
                    continue
                }
                out += words == safe.absoluteString ? [Run(text: words, style: .link(safe))]
                    : [Run(text: words, style: style), Run(text: " ", style: .plain), Run(text: safe.absoluteString, style: .link(safe))]
            } else if style == .code {
                out += [Run(text: words, style: .code)]
            } else {
                out += bare(words, style: style)
            }
        }
        return merged(out)
    }

    /// http and https with a host, or mailto with an address; anything else (javascript:, file:, a custom scheme) is
    /// never a link.
    static func safeLink(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "http", "https": return url.host?.isEmpty == false ? url : nil
        case "mailto": return url.absoluteString.count > "mailto:".count ? url : nil
        default: return nil
        }
    }

    /// The words of a run, without marks.
    static func plain(_ text: String) -> String { runs(text).map(\.text).joined() }

    private static func style(of intent: InlinePresentationIntent) -> Style {
        if intent.contains(.code) { return .code }
        let strong = intent.contains(.stronglyEmphasized), emphasis = intent.contains(.emphasized)
        return strong && emphasis ? .strongEmphasis : strong ? .strong : emphasis ? .emphasis : .plain
    }

    /// An address written out in the words: its own link run. A sentence's last stop or a closing bracket stays words.
    private static func bare(_ words: String, style: Style) -> [Run] {
        var out: [Run] = []
        var rest = words[...]
        while let found = rest.range(of: #"(https?|mailto):[^\s<>"'`\[\]{}]+"#, options: [.regularExpression, .caseInsensitive]) {
            var end = found.upperBound
            while end > found.lowerBound, ".,;:!?)'\"".contains(rest[rest.index(before: end)]) { end = rest.index(before: end) }
            let address = String(rest[found.lowerBound..<end])
            guard let url = safeLink(URL(string: address)) else {
                out.append(Run(text: String(rest[..<found.upperBound]), style: style))
                rest = rest[found.upperBound...]
                continue
            }
            if found.lowerBound > rest.startIndex { out.append(Run(text: String(rest[..<found.lowerBound]), style: style)) }
            out.append(Run(text: address, style: .link(url)))
            rest = rest[end...]
        }
        if !rest.isEmpty { out.append(Run(text: String(rest), style: style)) }
        return out
    }

    private static func merged(_ runs: [Run]) -> [Run] {
        runs.reduce(into: [Run]()) { out, run in
            guard !run.text.isEmpty else { return }
            if let last = out.last, last.style == run.style {
                out[out.count - 1] = Run(text: last.text + run.text, style: run.style)
            } else {
                out.append(run)
            }
        }
    }
}

struct ArisReaderDocument: Equatable {
    /// The bar's title.
    let title: String
    /// Under the first heading: when the result was saved.
    let meta: String?
    let blocks: [ArisBoardContent.Block]
    /// The saved result, for 메모에 저장 and 파일로 열기; nil for an answer or the board (복사 only).
    let file: String?
    let modified: Date?

    static let folderLabel = "~/Documents/Aris"

    /// A saved task result: "# <title>\n\n<document>", as aris-agent writes it.
    static func result(markdown: String, file: String, modified: Date, timeZone: TimeZone = .current) -> ArisReaderDocument {
        let blocks = ArisBoardContent.blocks(from: markdown)
        let heading: String? = if case .heading(1, let text) = blocks.first { ArisReaderInline.plain(text) } else { nil }
        return ArisReaderDocument(title: heading ?? title(fromFile: file), meta: meta(modified: modified, timeZone: timeZone),
                                  blocks: blocks, file: file, modified: modified)
    }

    /// The notch's "답 열기": the whole answer under the question.
    static func answer(_ answer: String, question: String) -> ArisReaderDocument {
        let heading: [ArisBoardContent.Block] = question.isEmpty ? [] : [.heading(level: 3, text: question)]
        return ArisReaderDocument(title: "Aris", meta: nil, blocks: heading + ArisBoardContent.blocks(from: answer), file: nil, modified: nil)
    }

    /// What the AI put on the board (aris-tools board).
    static func board(_ markdown: String) -> ArisReaderDocument {
        ArisReaderDocument(title: "Aris", meta: nil, blocks: ArisBoardContent.blocks(from: markdown), file: nil, modified: nil)
    }

    /// "2026-11-05 블랙홀 자료 정리.md" → "블랙홀 자료 정리".
    static func title(fromFile file: String) -> String {
        let name = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        let title = name.replacingOccurrences(of: #"^\d{4}-\d{2}-\d{2} "#, with: "", options: .regularExpression)
        return title.isEmpty ? "Aris" : title
    }

    /// "2026년 11월 5일 오후 3:41 · Aris".
    static func meta(modified: Date, timeZone: TimeZone = .current, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        if english {
            // "Nov 5, 2026 at 3:41 PM · Aris".
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            return ArisUIDates.string(modified, korean: "", template: "yMMMdjmm", english: true, calendar: calendar, locale: locale) + " · Aris"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy년 M월 d일 a h:mm"
        return "\(formatter.string(from: modified)) · Aris"
    }

    /// The bar's second line: "방금 · ~/Documents/Aris", "10분 전 · …", "2시간 전 · …", else the day.
    static func subtitle(modified: Date, now: Date, timeZone: TimeZone = .current, folder: String = folderLabel,
                         english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        let ago = max(0, now.timeIntervalSince(modified))
        let when: String
        if ago < 60 {
            when = ArisUIWords.text("방금", "Just now", english: english)
        } else if english {
            // "10 min. ago", "2 hr. ago", then the day: "Nov 5".
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            when = ago < 86_400 ? ArisUIDates.relative(seconds: -ago, locale: locale) : ArisUIDates.day(modified, english: true, calendar: calendar, locale: locale)
        } else if ago < 3_600 {
            when = "\(Int(ago / 60))분 전"
        } else if ago < 86_400 {
            when = "\(Int(ago / 3_600))시간 전"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.timeZone = timeZone
            formatter.dateFormat = "M월 d일"
            when = formatter.string(from: modified)
        }
        return "\(when) · \(folder)"
    }

    /// What 복사 gives: the words without markdown marks, a list's markers kept (a checklist's as ☐ and ☑), blocks a
    /// blank line apart.
    static func plainText(_ blocks: [ArisBoardContent.Block]) -> String {
        blocks.map { block in
            switch block {
            case .heading(_, let text), .label(let text), .paragraph(let text): return ArisReaderInline.plain(text)
            case .bullets(let items): return items.map { "• " + ArisReaderInline.plain($0) }.joined(separator: "\n")
            case .checklist(let items): return items.map { ($0.done ? "☑ " : "☐ ") + ArisReaderInline.plain($0.text) }.joined(separator: "\n")
            case .numbered(let items): return items.enumerated().map { "\($0.offset + 1). " + ArisReaderInline.plain($0.element) }.joined(separator: "\n")
            case .quote(let text): return text.components(separatedBy: "\n").map(ArisReaderInline.plain).joined(separator: "\n")
            case .code(let code): return code
            case .table(let header, let rows):
                return ([header] + rows).map { $0.map(ArisReaderInline.plain).joined(separator: "\t") }.joined(separator: "\n")
            }
        }
        .joined(separator: "\n\n")
    }
}
