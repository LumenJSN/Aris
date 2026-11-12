//
//  ArisDropFile.swift
//  Aris
//
//  One file dropped on Aris, as the chips see it: its kind, whether the app found text it can send with a request,
//  whether Aris holds back from reading it (ArisDropGuard), and whether aris-tools may make new files from it. Looked
//  up once at the drop, on this Mac, without any brain. An alias or a link stands for the file it points at.
//  Foundation only, so it is tested.
//

import Foundation

struct ArisDropFile: Equatable {
    /// Whether the app can hand this file's words to a brain.
    enum Text: Equatable {
        /// Still being looked for (a picture's text is read off the main thread).
        case looking
        case found
        case none
    }

    let path: String
    let kind: ArisDropKind
    var text: Text
    var hold: ArisDropGuard.Hold?
    /// The user pressed 읽어도 돼요 for a file held back by its name.
    var allowed = false
    /// aris-tools may convert or merge it where it is.
    var convertible: Bool

    var name: String { (path as NSString).lastPathComponent }
    var format: String { ArisDropKind.format(path) }

    /// Held back, and the user hasn't said to read it (a protected place is never read, whatever they pressed).
    var isHeld: Bool { hold == .protectedPlace || (hold == .secretName && !allowed) }
    /// Its words can go with a request now.
    var isReadable: Bool { text == .found && !isHeld }

    /// The biggest file whose text the app reads (ArisAttachmentText.largestFile).
    static let largestRead = 30 << 20

    /// What a file at `path` is. `size`: its bytes when the app can open it, nil when it can't (gone, or outside what
    /// the sandbox lets the app read). `pdfHasText`: asked only for a PDF that may be read.
    static func inspect(_ path: String, isFolder: Bool, size: Int?, home: String, allowed: Bool = false,
                        isKeynote: (String) -> Bool = { _ in false }, pdfHasText: (String) -> Bool = { _ in true }) -> ArisDropFile {
        let kind = ArisDropKind.of(path, isFolder: isFolder)
        let hold = ArisDropGuard.hold(path, home: home, isKeynote: isKeynote)
        var file = ArisDropFile(path: path, kind: kind, text: .none, hold: hold, allowed: allowed,
                                convertible: !isFolder && ArisDropGuard.convertible(path, home: home))
        // A held file is not opened at all, not even to see whether it has text.
        guard !file.isHeld, let size, size > 0 else { return file }
        switch kind {
        case .pdf: file.text = size <= largestRead && pdfHasText(path) ? .found : .none
        case .document, .text: file.text = size <= largestRead ? .found : .none
        case .image: file.text = .looking
        case .video, .audio, .folder, .other: break
        }
        return file
    }

    /// The file an alias or a symbolic link stands for; the URL itself for anything else, or when the link is broken.
    static func original(of url: URL) -> URL {
        guard let values = try? url.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey]),
              values.isAliasFile == true || values.isSymbolicLink == true,
              let target = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]),
              FileManager.default.fileExists(atPath: target.path) else { return url }
        return target.standardizedFileURL
    }
}
