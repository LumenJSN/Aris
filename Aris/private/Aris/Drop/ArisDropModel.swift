//
//  ArisDropModel.swift
//  Aris
//
//  Files dropped on "Aris한테 주기", from the drop to a chip's turn. At the drop each file is looked at once on this
//  Mac (what it is, whether the app can send its words, whether Aris holds back from reading it: ArisDropFile), an
//  alias or a link becoming the file it points at; a picture's words are read off the main thread and its 글자 뽑기
//  chip comes up when they are in. Pressing a chip makes the request the user would have typed and starts an ordinary
//  turn with it (ArisController.submitTyped), in a conversation of its own, so a chip that makes new files is never
//  refused for what an earlier answer read. The files' text for a typed or spoken request is read here too, never a
//  held file's: off the main thread at the drop (ArisDropTextAhead), so the request itself doesn't wait on a file.
//

import Foundation

@MainActor
final class ArisDropModel: ObservableObject {
    static let shared = ArisDropModel()

    /// What is known of each file given to Aris, by its path.
    @Published private(set) var known: [String: ArisDropFile] = [:]
    /// A line about the last drop or press: more dropped than taken, a file that is gone, no words found.
    @Published private(set) var notice: String?
    /// What the user often asks of each kind of file (ArisDropLearned), kept in the app's own folder.
    @Published private(set) var learned = ArisDropLearnedStore.load()
    /// The request a built-in chip just made in the user's place: those are Aris's words, never learned as their.
    private var builtInRequest: String?

    /// The words read off each picture, by its path.
    private var pictureWords: [String: String] = [:]
    /// The files' words read ahead of the request, off the main thread (ArisDropTextAhead).
    private var ahead = ArisDropTextAhead()
    private var noticeClock: Task<Void, Never>?
    /// How long a notice stays under the chips.
    private static let noticeStays: Duration = .seconds(8)

    // MARK: - The drop

    /// Files just dropped on Aris: they wait for the next request (ArisAttachments), each looked at for its chips.
    func dropped(_ urls: [URL], english: Bool = ArisUIWords.english) {
        let attachments = ArisAttachments.shared
        let before = attachments.files
        let given = urls.filter(\.isFileURL).map(ArisDropFile.original(of:))
        let fresh = Set(given).subtracting(before).count
        attachments.add(given)
        let kept = attachments.files
        known = known.filter { path, _ in kept.contains { $0.path == path } }
        pictureWords = pictureWords.filter { known[$0.key] != nil }
        ahead = ahead.only(Set(known.keys))
        for url in kept where known[url.path] == nil { look(at: url) }
        notice = nil
        if before.count + fresh > kept.count { say(ArisDropCopy.cut(dropped: before.count + fresh, kept: kept.count, english: english)) }
    }

    /// The chips' view of the files that wait, in their order.
    func files(_ urls: [URL]) -> [ArisDropFile] {
        urls.map { known[$0.path] ?? ArisDropFile(path: $0.path, kind: .other, text: .none, hold: nil, convertible: false) }
    }

    private func look(at url: URL, allowed: Bool = false) {
        let path = url.path
        var isFolder: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
        let file = ArisDropFile.inspect(path, isFolder: isFolder.boolValue, size: exists ? Self.readableSize(path, isFolder: isFolder.boolValue) : nil,
                                        home: UserHome.path, allowed: allowed, isKeynote: Self.isKeynote, pdfHasText: ArisDropReading.pdfHasText)
        known[path] = file
        readAhead(url, of: file, isFolder: isFolder.boolValue)
        guard file.text == .looking else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let words = ArisDropReading.pictureWords(path)
            await self?.read(words, inPicture: path)
        }
    }

    /// The file's words are read now, off the main thread, for the request that comes next; never a held file's.
    private func readAhead(_ url: URL, of file: ArisDropFile, isFolder: Bool) {
        ahead = ahead.forgetting(url.path)
        guard !file.isHeld, !isFolder, ArisDropTextAhead.readsAhead(url.path) else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let stamp = ArisDropTextAhead.stamp(of: url) else { return }
            let text = ArisAttachmentText.extract(url)
            await self?.keep(text, of: url.path, stamp: stamp)
        }
    }

    /// A file's words are in. Kept only while the file still waits and is not held back.
    private func keep(_ text: String?, of path: String, stamp: ArisDropTextAhead.Stamp) {
        guard let file = known[path], !file.isHeld else { return }
        ahead = ahead.keeping(path, text: text, stamp: stamp)
    }

    /// A picture's words are in: with any, its 글자 뽑기 chip comes up.
    private func read(_ words: String, inPicture path: String) {
        guard var file = known[path] else { return }
        let found = words.contains { !$0.isWhitespace }
        pictureWords[path] = found ? words : nil
        file.text = found ? .found : .none
        known[path] = file
    }

    /// The file's bytes when the app can open it (a package counts as one); nil when it can't.
    private static func readableSize(_ path: String, isFolder: Bool) -> Int? {
        guard FileManager.default.isReadableFile(atPath: path) else { return nil }
        if isFolder { return 1 }
        return ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.intValue
    }

    /// A Keynote deck is a package or a zip; a private key named `.key` is text (ArisFiles.isKeynoteDocument).
    private static func isKeynote(_ path: String) -> Bool {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else { return false }
        if isFolder.boolValue { return true }
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == Data([0x50, 0x4B, 0x03, 0x04])
    }

    // MARK: - Reading

    /// A file's text for a request the user typed or said after the drop (ArisAttachmentText): never a held file's.
    func text(of url: URL) -> String? {
        let held = known[url.path]?.isHeld ?? (ArisDropGuard.hold(url.path, home: UserHome.path, isKeynote: Self.isKeynote) != nil)
        // What was read at the drop, when the file is still that file; otherwise it is read here, as before.
        if !held, let read = ahead.text(of: url.path, now: ArisDropTextAhead.stamp(of: url)) { return read }
        return held ? nil : ArisAttachmentText.extract(url)
    }

    /// The same for a chip, which also sends the words read off a picture.
    private func chipText(of url: URL) -> String? {
        guard known[url.path]?.kind == .image else { return text(of: url) }
        return pictureWords[url.path].map { ArisDropCopy.readFromPicture + "\n" + $0 }
    }

    // MARK: - A chip pressed

    func press(_ chip: ArisDropChip, english: Bool = ArisUIWords.english) {
        let attachments = ArisAttachments.shared, aris = ArisController.shared
        if chip.act == .allowReading { return allowReading(attachments.files) }
        // The chips are out of sight while Aris listens, works or asks; a press that slips in then starts nothing.
        guard aris.session.phase != .listening, aris.session.phase != .thinking, aris.session.question == nil else { return }
        let files = files(attachments.files)
        let gone = ArisDropChips.gone(files) { FileManager.default.fileExists(atPath: $0) }
        guard gone.isEmpty else {
            attachments.files.filter { url in gone.contains { $0.path == url.path } }.forEach(attachments.remove)
            return say(ArisDropCopy.gone(gone.map(\.name), english: english))
        }
        guard let words = ArisDropCopy.words(chip.act, files: files, english: english) else { return }
        var text: String?
        if chip.sendsText {
            text = ArisAttachmentText.block(for: attachments.files, read: { self.chipText(of: $0) })
            guard text != nil else { return say(ArisDropCopy.noText(english: english)) }
        }
        let request = ArisDropChips.request(words: words, pending: attachments.pending, makesFile: chip.makesFile, text: text)
        notice = nil
        builtInRequest = request
        // Its own conversation: what an earlier answer read never stops this one from making a file.
        aris.endConversation()
        aris.submitTyped(request)
        attachments.clear()
    }

    // MARK: - What the user often asks (ArisDropLearned)

    /// The learned chips for the files that wait now.
    func learnedChips(_ urls: [URL]) -> [ArisDropLearnedChip] {
        ArisDropLearnedChip.make(learned.chips(for: files(urls).map(\.kind)))
    }

    /// A turn's words as they go to the brain (`heard`: their words, then the files' note). When they carry files and
    /// are his own (typed, spoken, or a learned chip of his own words), their shape is remembered for that kind of file.
    func learn(from heard: String) {
        guard ArisPendingFiles.carriesFiles(heard) else { return }
        let fromChip = builtInRequest == heard
        builtInRequest = nil
        guard !fromChip else { return }
        let paths = ArisDropLearned.paths(in: heard)
        let kinds = paths.map { known[$0]?.kind ?? ArisDropKind.of($0) }
        let next = learned.recording(ArisPendingFiles.words(of: heard), kinds: kinds, fileNames: paths.map { ($0 as NSString).lastPathComponent })
        guard next != learned else { return }
        learned = next
        ArisDropLearnedStore.save(next)
    }

    /// A learned chip pressed: exactly the remembered request with the files, sent the way a typed one is (the
    /// composer's own path), so every card, confirmation and rule about outside text applies as if he had typed it.
    func press(_ chip: ArisDropLearnedChip, english: Bool = ArisUIWords.english) {
        let attachments = ArisAttachments.shared, aris = ArisController.shared
        guard aris.session.phase != .listening, aris.session.phase != .thinking, aris.session.question == nil, !attachments.files.isEmpty else { return }
        let gone = ArisDropChips.gone(files(attachments.files)) { FileManager.default.fileExists(atPath: $0) }
        guard gone.isEmpty else {
            attachments.files.filter { url in gone.contains { $0.path == url.path } }.forEach(attachments.remove)
            return say(ArisDropCopy.gone(gone.map(\.name), english: english))
        }
        notice = nil
        aris.submitTyped(attachments.request(with: chip.habit.request))
        attachments.clear()
    }

    func forget(_ chip: ArisDropLearnedChip) {
        learned = learned.forgetting(chip.habit)
        ArisDropLearnedStore.save(learned)
    }

    /// Settings › 기억 › 배운 제안 지우기.
    func forgetAllLearned() {
        learned = learned.forgettingAll()
        ArisDropLearnedStore.save(learned)
    }

    /// The user's yes: the files held back by their names are looked at again, now to be read.
    private func allowReading(_ urls: [URL]) {
        for url in urls where known[url.path]?.hold == .secretName { look(at: url, allowed: true) }
    }

    private func say(_ line: String) {
        notice = line
        noticeClock?.cancel()
        noticeClock = Task { [weak self] in
            try? await Task.sleep(for: Self.noticeStays)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}
