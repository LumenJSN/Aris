//
//  ArisDropTextAhead.swift
//  Aris
//
//  The words of the files given to Aris, read ahead of the request. A request with files used to open and read each
//  of them on the main thread the moment the user pressed Return or stopped talking (a 40-page PDF, a long Word file),
//  and the whole notch stood still for that long. Now each file is read off the main thread when it is dropped, and
//  the request takes what was read, as long as the file is still the one that was read: same size, same time of last
//  change. A file changed since, or one not read yet, is read at the request as before, so the words sent are always
//  the file's own at that moment.
//

import Foundation

struct ArisDropTextAhead: Equatable, Sendable {
    /// What a file was when it was read: enough to tell that it has not been saved again since.
    struct Stamp: Equatable, Sendable {
        let size: Int
        let changed: Date
    }

    /// A file's words (nil: it has none Aris can read) and what the file was then.
    struct Read: Equatable, Sendable {
        let stamp: Stamp
        let text: String?
    }

    private(set) var read: [String: Read] = [:]

    /// Web pages are turned into text by the system's HTML reader, which only works on the main thread: they are
    /// read at the request, never ahead.
    static let mainThreadOnly: Set<String> = ["html", "htm", "webarchive"]

    static func readsAhead(_ path: String) -> Bool {
        !mainThreadOnly.contains((path as NSString).pathExtension.lowercased())
    }

    /// With the file at `path` read. `stamp` is taken before the reading starts, so a file saved while it was being
    /// read no longer matches and is read again at the request.
    func keeping(_ path: String, text: String?, stamp: Stamp) -> ArisDropTextAhead {
        var next = self
        next.read[path] = Read(stamp: stamp, text: text)
        return next
    }

    /// Without the files that no longer wait.
    func only(_ paths: Set<String>) -> ArisDropTextAhead {
        var next = self
        next.read = read.filter { paths.contains($0.key) }
        return next
    }

    /// Without what was read of one file (it is being looked at again).
    func forgetting(_ path: String) -> ArisDropTextAhead {
        var next = self
        next.read[path] = nil
        return next
    }

    /// What was read ahead, when the file is still what it was then (`now`: what it is at the request; nil when it
    /// can't be told). The outer nil: read it now.
    func text(of path: String, now: Stamp?) -> String?? {
        guard let known = read[path], let now, known.stamp == now else { return nil }
        return .some(known.text)
    }

    /// What the file at `url` is now; nil when it is gone or can't be looked at. Asked of the disk each time (a URL
    /// keeps the size and date it was first asked for, which would make every file look unchanged).
    static func stamp(of url: URL) -> Stamp? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        let changed = TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
        return Stamp(size: Int(info.st_size), changed: Date(timeIntervalSince1970: changed))
    }
}
