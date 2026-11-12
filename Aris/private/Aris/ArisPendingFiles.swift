//
//  ArisPendingFiles.swift
//  Aris
//
//  Files dropped on "Aris한테 주기", waiting for the next request: whichever way it is asked (typed, the talk key, the
//  wake word, a follow-up) it takes them, as paths Aris may read with a note that "이 파일" / "이거" / "this file" means
//  them (so the screen isn't read), and they are gone after. They wait 5 minutes from the last drop, and never ride
//  along with a hands-free turn or one asked while the notch is closed with no chips to see (they stay for the user).
//  Values only: each change is a new one. Pure, so it's tested.
//

import Foundation

struct ArisPendingFiles: Equatable {
    /// Twenty photos dropped to convert at once are all taken; past that the notch says how many it took.
    static let limit = 20
    /// How many files' names the turn's line shows before it counts the rest.
    static let namesShown = 8
    /// How long dropped files wait for a request.
    static let lifetime: TimeInterval = 5 * 60
    /// How the request carries them; ArisDeixis reads its start to leave the screen alone.
    static let note = "(첨부한 파일: "

    private(set) var files: [URL] = []

    /// When files were last given.
    private(set) var givenAt: Date?

    func adding(_ urls: [URL], at now: Date = Date()) -> ArisPendingFiles {
        let fresh = urls.reduce(into: [URL]()) { kept, url in
            if url.isFileURL, !files.contains(url), !kept.contains(url) { kept.append(url) }
        }
        return ArisPendingFiles(files: Array((files + fresh).prefix(Self.limit)), givenAt: fresh.isEmpty ? givenAt : now)
    }

    /// Given more than `lifetime` ago.
    func isExpired(at now: Date = Date()) -> Bool { givenAt.map { now.timeIntervalSince($0) > Self.lifetime } ?? false }

    func removing(_ url: URL) -> ArisPendingFiles {
        let left = files.filter { $0 != url }
        return ArisPendingFiles(files: left, givenAt: left.isEmpty ? nil : givenAt)
    }

    func cleared() -> ArisPendingFiles { ArisPendingFiles() }

    /// The words without the note and what follows it (the files' paths, their text): what he said himself.
    static func ownWords(_ text: String) -> String {
        text.range(of: "\n\n" + note).map { String(text[..<$0.lowerBound]) } ?? text
    }

    /// The words, then the files they're about.
    /// `contents`: the files' text, read up front (ArisAttachmentText), sent after the note so the brain never opens them.
    /// `aside`: more for the brain inside the note (a chip that makes new files says to use these paths: ArisDropCopy).
    func request(with words: String, aside: String = "", contents: ([URL]) -> String? = { _ in nil }) -> String {
        guard !files.isEmpty else { return words }
        let text = contents(files).map { "\n\n" + $0 } ?? ""
        return words + "\n\n" + Self.note + files.map(\.path).joined(separator: ", ")
            + " — 사용자가 Aris에게 준 파일이에요. \"이 파일\", \"이거\", \"this file\"은 이 파일을 말해요\(aside))" + text
    }

    /// The turn's text and what is left pending. A typed request already has them (the composer showed the chips):
    /// nothing left. Expired: never attached, gone. A hands-free turn, or one asked with the chips out of sight: the
    /// words alone, the files still waiting. Otherwise the words with the files, and nothing left.
    func taking(into words: String, at now: Date = Date(), handsFree: Bool = false, shown: Bool = true,
                contents: ([URL]) -> String? = { _ in nil }) -> (text: String, left: ArisPendingFiles) {
        if Self.carriesFiles(words) || files.isEmpty || isExpired(at: now) { return (words, cleared()) }
        guard !handsFree, shown else { return (words, self) }
        return (request(with: words, contents: contents), cleared())
    }

    /// The conversation ended for good (닫기, its quiet timeout, "됐어"): files given in it never ride along with a later,
    /// unrelated question. Ending it with the talk key, Esc or a tap keeps them for the request the user is about to make.
    static func clearedWhenConversationEnds(_ reason: ArisConversation.EndReason) -> Bool {
        [.dismissed, .silence, .donePhrase].contains(reason)
    }

    static func carriesFiles(_ text: String) -> Bool { text.contains("\n\n" + note) }

    /// The turn's images are let go because files came with it: the files are what "이거" means, so no screenshot is
    /// sent. Shots the user circled are their own pointing and stay: the words keep their `[img N]` markers, and a marker
    /// with no image behind it would mean nothing to the AI.
    static func dropsTurnImages(_ text: String, circledShots: Bool) -> Bool { carriesFiles(text) && !circledShots }

    /// What the turn's line shows: the user's words, then the files' names ("이 파일 요약해 줘 · qa-drop.txt").
    static func shown(_ text: String) -> String {
        guard let start = text.range(of: "\n\n" + note) else { return text }
        let listed = text[start.upperBound...].components(separatedBy: " — ").first ?? ""
        let names = listed.components(separatedBy: ", ").map { ($0 as NSString).lastPathComponent }.filter { !$0.isEmpty }
        let words = String(text[..<start.lowerBound])
        // Twenty names would bury their words: past `namesShown`, the first and how many more.
        if names.count > namesShown { return words + " · \(names[0]) +\(names.count - 1)" }
        return names.isEmpty ? words : words + " · " + names.joined(separator: ", ")
    }

    /// The words alone, without the files' note.
    static func words(of text: String) -> String {
        guard let note = text.range(of: "\n\n" + note) else { return text }
        return String(text[..<note.lowerBound])
    }

    /// What the composer says once files were given: "shells.pdf 받았어요. 뭘 할까요?"; nil with none.
    static func hint(for files: [URL], korean: Bool) -> String? {
        guard let first = files.first?.lastPathComponent else { return nil }
        let more = files.count - 1
        if korean { return "\(first)\(more > 0 ? " 외 \(more)개" : "") 받았어요. 뭘 할까요?" }
        return more > 0 ? "Got \(first) and \(more) more. What should I do with them?" : "Got \(first). What should I do with it?"
    }
}
