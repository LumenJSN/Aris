//
//  ArisTaskResult.swift
//  aris-agent
//
//  How a background task's answer reaches the user: a short one is just said; a long one
//  (research, a summary, a plan) is said in a line and the rest is saved as a Markdown file
//  that opens on screen, so the user doesn't have to go and find it.
//

import Foundation

enum ArisTaskResult {
    /// Past this many characters beyond the spoken line, the rest is worth a file (more is too much for the notch).
    static let longest = 250

    /// How a background task answers (in its system prompt, instead of the conversation's "one or two sentences").
    static let instruction = """
        This is background work the user handed over: take the time it needs. Start your answer with one short \
        plain sentence to say out loud about what you found or did. If there is more worth keeping (research, a \
        summary, a plan, a list), add a blank line and then the full result in Markdown with headings and lists, as \
        long as it needs to be, right in your answer: don't create or save a file yourself; Aris saves your answer \
        and opens it for the user. If the whole result is a sentence or two, just give that.
        """

    /// The user asked for a file ("파일로 저장해", "문서로", "save it", "as a file"): in their own words, never the model's.
    private static let fileWords = #"(?i)(파일\s*(로|에|하나)|문서\s*(로|에|하나|파일)|저장\s*(해|하|좀|까지)|마크다운\s*(으로|파일)|\.md\b|\bmd\s*(로|파일)|\bsav(e|ing)\b|\b(as|to|into|in)\s+a\s+(file|doc|document)\b|\bmarkdown\b)"#
    /// …unless he said not to.
    private static let noFile = #"(?i)(저장\s*하?\s*지\s*(마|말)|파일\s*(로|에)?\s*(저장\s*)?하?\s*지\s*(마|말)|(don'?t|do not|no need to|never)\s+save|\bno\s+file)"#

    /// Told to a job whose answer Aris saves as the file the user asked for.
    static let fileJobRule = "(Aris saves your answer as the file the user asked for. Answer with the content itself: no file of " +
        "your own, no saving, no writing to disk, and never a note that you can't make files: Aris does that part.)"

    /// An answer that is no content: empty, or a short one (the whole of it) that starts by saying it can't or won't
    /// (security review: "I can't wait for Friday…" or a 죄송 deep in a real answer was thrown away).
    static func isRefusal(_ text: String) -> Bool {
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return true }
        guard plain.count <= 150, let found = plain.range(of: refusal, options: .regularExpression) else { return false }
        guard plain.distance(from: plain.startIndex, to: found.lowerBound) <= 30 else { return false }
        // "I can't wait", "can't believe": eagerness, not a refusal.
        return plain.range(of: #"(?i)can'?t\s+(wait|believe|stop|help)"#, options: .regularExpression) == nil
    }

    private static let refusal = #"(?i)(할\s*수\s*없|만들\s*수\s*없|저장할\s*수\s*없|작성할\s*수\s*없|못\s*(해|하|만들|저장)|죄송|권한이\s*없|거부|i\s*(can'?t|cannot|am\s*unable|'m\s*unable|won'?t)|unable\s+to|not\s+able\s+to|i'?m\s+sorry)"#

    /// The one line said when the user asked for a file and the job gave no content for it.
    static func noContentLine(korean: Bool) -> String {
        korean ? "파일로 저장할 내용을 받지 못해서 저장하지 않았어요." : "I didn't get anything to save, so I didn't make the file."
    }

    static func asksForFile(_ request: String) -> Bool {
        request.range(of: fileWords, options: .regularExpression) != nil && request.range(of: noFile, options: .regularExpression) == nil
    }

    /// The line to say, and the rest when it's long enough for a file. `toFile` (the user asked for one): the rest however
    /// short, or the whole answer when it is only a line.
    static func split(_ raw: String, toFile: Bool = false) -> (spoken: String, document: String?) {
        let answer = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let gap = answer.range(of: "\n\n") {
            let spoken = String(answer[..<gap.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = String(answer[gap.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if rest.count >= longest || (toFile && !rest.isEmpty) { return (spoken, rest) }
        }
        if toFile, answer.count < longest { return (answer, answer.isEmpty ? nil : answer) }
        guard answer.count >= longest else { return (answer, nil) }
        // Long, without a line to say first: say its first sentence.
        let end = answer.firstIndex { ".!?。\n".contains($0) }.map { answer.index(after: $0) } ?? answer.index(answer.startIndex, offsetBy: 80)
        return (String(answer[..<end]).trimmingCharacters(in: .whitespacesAndNewlines), answer)
    }

    /// A background task's answer as the agent sends it: the line to say and, when the user asked for a file or the rest is
    /// long, the rest saved as "<date> <title>.md" in the first of `folders` that can be written (~/Documents/Aris, then
    /// Aris's own), the answer saying where. Otherwise the answer as it is (its Markdown and line breaks kept).
    /// `tainted`: the job read outside text. A long answer the user didn't ask to save is then shown, never written to a file
    /// (security review: outside text written to disk unasked).
    static func deliver(_ raw: String, request: String, title: String, date: Date = Date(), timeZone: TimeZone = .current,
                        tainted: Bool = false, folders: [URL]) -> (answer: String, file: URL?) {
        let toFile = asksForFile(request)
        if tainted, !toFile { return (ArisAgentStream.spoken(raw), nil) }
        let (line, document) = split(raw, toFile: toFile)
        // A refusal or nothing is never saved as the file the user asked for: one clean line says so (QA BUG-20).
        if toFile, document.map(isRefusal) ?? true {
            let korean = request.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
            return (noContentLine(korean: korean), nil)
        }
        guard let document else { return (ArisAgentStream.spoken(raw), nil) }
        let said = ArisAgentStream.spoken(line)
        let korean = said.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
            || (said.isEmpty && request.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) })
        let name = fileName(title: title, date: date, timeZone: timeZone)
        guard let saved = save("# \(title)\n\n" + document, as: name, in: folders) else {
            return (said + (korean ? " 그런데 결과를 파일로 저장하지 못했어요." : " But I couldn't save the details."), nil)
        }
        // The name it was really saved under (a second result of the same title on the same day gets its own file).
        return (said + " " + savedLine(name: saved.file.lastPathComponent, inDocuments: saved.index == 0, korean: korean), saved.file)
    }

    /// Where the result went, after the line: Documents › Aris (or Aris's own folder when Documents couldn't be written)
    /// and the file's name, which the voice leaves out (ArisSpeakable.readable).
    static func savedLine(name: String, inDocuments: Bool, korean: Bool) -> String {
        if korean { return "\(inDocuments ? "문서 › Aris" : "Aris") 폴더에 ‘\(name)’로 저장해서 열어 뒀어요." }
        return "I saved it in \(inDocuments ? "Documents › Aris" : "Aris's own folder") as “\(name)” and opened it."
    }

    /// Written in the first of `folders` that works; which one, or nil when none could be written. A file already there
    /// is never replaced: an earlier result of the same title on the same day stays, and this one is saved beside it
    /// as "<name> 2.md", "<name> 3.md"… (audit result-overwrite-12). The file that was written is the one returned.
    static func save(_ text: String, as name: String, in folders: [URL]) -> (file: URL, index: Int)? {
        for (index, folder) in folders.enumerated() {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for number in 1...maxCopies {
                    let file = folder.appendingPathComponent(numbered(name, number))
                    // Made only if nothing has that name (O_EXCL): two jobs ending together can't take the same one.
                    let made = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
                    if made < 0 {
                        if errno == EEXIST { continue }
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                    }
                    let handle = FileHandle(fileDescriptor: made, closeOnDealloc: true)
                    do {
                        try handle.write(contentsOf: Data(text.utf8))
                        try handle.close()
                    } catch {
                        try? FileManager.default.removeItem(at: file)
                        throw error
                    }
                    return (file, index)
                }
                FileHandle.standardError.write(Data("aris-agent: couldn't save to \(folder.path): too many results named \(name)\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("aris-agent: couldn't save to \(folder.path): \(error.localizedDescription)\n".utf8))
            }
        }
        return nil
    }

    /// Results of one title on one day, at most.
    static let maxCopies = 99

    /// "2026-11-10 블랙홀.md", then "2026-11-10 블랙홀 2.md", "… 3.md".
    static func numbered(_ name: String, _ number: Int) -> String {
        guard number > 1 else { return name }
        let file = name as NSString
        let ext = file.pathExtension
        return file.deletingPathExtension + " \(number)" + (ext.isEmpty ? "" : "." + ext)
    }

    /// "2026-10-25 블랙홀 정리.md": the date and the task, without characters a file name can't have.
    static func fileName(title: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        let safe = title.replacingOccurrences(of: #"[/:\\\n]"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return "\(formatter.string(from: date)) \(safe.isEmpty ? "Aris" : String(safe.prefix(60))).md"
    }
}
