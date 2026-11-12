//
//  ArisDropChips.swift
//  Aris
//
//  The chips that come up the moment files are dropped on Aris, picked from what the files are and nothing else (no
//  brain is asked): 요약 and 번역 for a document whose text the app can send along, 변환 for a picture, a PDF, a video
//  or a sound aris-tools can convert where it is, 글자 뽑기 for a picture with words in it, 하나로 합치기 for several
//  PDFs, pictures or clips. Only what works today is offered; files with nothing to offer get no chips, and the
//  composer under them waits for what the user types. A chip that needs a target (a language, a format) does the obvious
//  one, and the others sit on a second row. Foundation only, so it is tested.
//

import Foundation

struct ArisDropChip: Equatable, Identifiable {
    enum Act: Equatable {
        case summarize
        /// `orElse`: the language to use when the file is already in `to` (the first-row chip only).
        case translate(to: String, orElse: String?)
        /// A picture's words, read on this Mac.
        case extractText
        case convert(to: String)
        case merge
        /// The user's yes to reading a file held back by its name; asks nothing of a brain.
        case allowReading
    }

    let act: Act
    let label: String
    var id: String { String(describing: act) }

    /// aris-tools makes a new file: the request goes with the files' paths alone, on a turn no outside text is in.
    var makesFile: Bool {
        switch act {
        case .convert, .merge: return true
        default: return false
        }
    }

    /// The files' words go with the request (read by the app, so any brain can answer).
    var sendsText: Bool {
        switch act {
        case .summarize, .translate, .extractText: return true
        default: return false
        }
    }
}

struct ArisDropOffer: Equatable {
    /// The first row: each does the obvious thing at one press.
    var main: [ArisDropChip] = []
    /// The second row: the same acts with another language or format.
    var more: [ArisDropChip] = []
    /// A line under them when Aris holds back from reading a file.
    var caption: String?
}

enum ArisDropChips {
    /// The languages a translation is offered into; the user's own comes first.
    static let languages = ["ko", "en", "ja", "zh"]

    static func offer(_ files: [ArisDropFile], english: Bool) -> ArisDropOffer {
        guard !files.isEmpty else { return ArisDropOffer() }
        let reads = readActs(files, english: english), makes = makeActs(files)
        // PDFs first say 합치기, then what reads them, then 변환; a picture's 글자 뽑기 comes last (it arrives a moment
        // after the drop, and nothing may move under the pointer).
        var main = makes.merge + reads.main.filter { $0 != .extractText } + makes.convert.prefix(1) + reads.main.filter { $0 == .extractText }
        if files.contains(where: { $0.hold == .secretName && !$0.allowed }) { main.append(.allowReading) }
        let more = reads.more + makes.convert.dropFirst()
        let chip = { (act: ArisDropChip.Act, main: Bool) in
            ArisDropChip(act: act, label: ArisDropCopy.label(act, files: files, main: main, english: english))
        }
        let hold = files.contains { $0.hold == .protectedPlace } ? ArisDropGuard.Hold.protectedPlace
            : files.contains { $0.isHeld } ? .secretName : nil
        return ArisDropOffer(main: main.map { chip($0, true) }, more: more.map { chip($0, false) },
                             caption: hold.map { ArisDropCopy.held($0, english: english) })
    }

    // MARK: - What reads the files

    /// 요약 for files whose words the app can all send; 번역 and its other languages for one document; 글자 뽑기 for one
    /// picture with words in it.
    private static func readActs(_ files: [ArisDropFile], english: Bool) -> (main: [ArisDropChip.Act], more: [ArisDropChip.Act]) {
        guard files.allSatisfy(\.isReadable) else { return ([], []) }
        if files.count == 1, files[0].kind == .image { return ([.extractText], []) }
        guard files.allSatisfy(\.kind.isRead) else { return ([], []) }
        guard files.count == 1, files[0].kind != .text else { return ([.summarize], []) }
        let own = english ? "en" : "ko", others = languages.filter { $0 != own }
        return ([.summarize, .translate(to: own, orElse: others.first)], others.map { .translate(to: $0, orElse: nil) })
    }

    // MARK: - What makes new files

    /// 합치기 for two or more files that merge into one, and the formats files of one kind can all become (the first
    /// is the obvious one).
    private static func makeActs(_ files: [ArisDropFile]) -> (merge: [ArisDropChip.Act], convert: [ArisDropChip.Act]) {
        guard files.allSatisfy(\.convertible) else { return ([], []) }
        let kinds = Set(files.map(\.kind))
        let pages = kinds.isSubset(of: [.pdf, .image]), clips = kinds == [.video] || kinds == [.audio]
        let merge: [ArisDropChip.Act] = files.count > 1 && (pages || clips) ? [.merge] : []
        guard kinds.count == 1, let kind = kinds.first else { return (merge, []) }
        return (merge, targets(kind, formats: Set(files.map(\.format)), several: files.count > 1).map { .convert(to: $0) })
    }

    /// The formats files of `kind` can become, commonest first, never one any of them already is (aris-tools refuses
    /// the whole call then). Several pictures have no PDF here: 합치기 makes the one PDF.
    static func targets(_ kind: ArisDropKind, formats: Set<String>, several: Bool) -> [String] {
        let all: [String]
        switch kind {
        case .image: all = several ? ["jpg", "png", "heic"] : ["jpg", "png", "pdf", "heic"]
        case .pdf: all = ["png", "jpg"]
        case .video: all = ["mp4", "m4a", "mov"]
        case .audio: all = ["m4a"]
        case .document, .text, .folder, .other: all = []
        }
        return all.filter { !formats.contains($0) }
    }

    // MARK: - Pressing one

    /// The files that are no longer there (moved, renamed or deleted since the drop).
    static func gone(_ files: [ArisDropFile], exists: (String) -> Bool) -> [ArisDropFile] { files.filter { !exists($0.path) } }

    /// The longest request a chip sends: aris-agent takes 32,000 characters with the files' text, and refuses the
    /// whole turn past that.
    static let longestRequest = 30_000
    private static let cutMark = "\n…(여기까지만 보냈어요)\n---)"

    /// The chip's whole request: its words, the files' note (with the paths' aside for one that makes files), and
    /// the files' text when the chip sends it, cut so the request stays within `longestRequest`.
    static func request(words: String, pending: ArisPendingFiles, makesFile: Bool, text: String?) -> String {
        let bare = pending.request(with: words, aside: makesFile ? ArisDropCopy.pathsAside : "")
        guard let text else { return bare }
        let room = max(0, longestRequest - bare.count - 2)
        let fitted = text.count > room ? String(text.prefix(max(0, room - cutMark.count))) + cutMark : text
        return pending.request(with: words, contents: { _ in fitted })
    }
}
