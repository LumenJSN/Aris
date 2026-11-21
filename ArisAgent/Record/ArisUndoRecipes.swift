//
//  ArisUndoRecipes.swift
//  aris-agent
//
//  Making an undo recipe around a change, and carrying one out. Files the helper puts back itself, every path checked
//  first (inside the home folder or on an external disk, never a place on the never-list) and nothing overwritten:
//    created  -> to the Trash           edited or replaced -> its kept copy back, only if the file is still as Aris left it
//    moved or renamed -> moved back     trashed -> out of the Trash again
//  Calendar, reminder and note items, settings and system controls, text put into an app and window moves go through
//  the capability that made them (ArisUndoHands: jv-hands and jv-apps fill the live ones; the tests use fakes).
//

import Darwin
import Foundation

/// The undo performers for what isn't a file. A missing one says so instead of pretending.
struct ArisUndoHands: @unchecked Sendable {
    var trash: (String) throws -> Void = { try FileManager.default.trashItem(at: URL(fileURLWithPath: $0), resultingItemURL: nil) }
    var removeItem: ((_ kind: String, _ id: String) throws -> Void)?
    var restoreItem: ((_ kind: String, _ id: String, _ before: [String: String]) throws -> Void)?
    var setSetting: ((_ name: String, _ value: String) throws -> Void)?
    var setText: ((_ app: String, _ element: String, _ value: String) throws -> Void)?
    var moveWindow: ((_ app: String, _ window: Int, _ frame: [Double]) throws -> Void)?

    /// The helper's own: the capabilities that make items, settings, text and window moves register here.
    nonisolated(unsafe) static var live = ArisUndoHands()
}

struct ArisUndoError: Error, LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

enum ArisUndoRecipes {
    // MARK: - Around a file change

    /// What a file change needs kept before it runs: nothing for a new file, the old bytes for an edit or overwrite.
    struct Prepared: Equatable {
        let path: String
        let existed: Bool
        let copy: String?
    }

    /// Before writing or editing `path`. Nil: it exists but couldn't be kept (too big, unreadable), so the change has
    /// no undo and is permanent.
    static func beforeWrite(_ path: String, store: ArisUndoStore, now: Date = Date()) -> Prepared? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return Prepared(path: path, existed: false, copy: nil) }
        guard info.st_mode & S_IFMT == S_IFREG, let copy = store.keep(path, now: now) else { return nil }
        return Prepared(path: path, existed: true, copy: copy)
    }

    /// After the write: the recipe (nil when the file isn't there or can't be read).
    static func afterWrite(_ prepared: Prepared) -> ArisUndoRecipe? {
        guard let after = ArisUndoStore.hash(of: prepared.path) else { return nil }
        guard prepared.existed, let copy = prepared.copy else { return .fileCreated(path: prepared.path) }
        return .fileChanged(path: prepared.path, copy: copy, after: after)
    }

    // MARK: - Carrying one out

    /// Undoes `recipe`; its line for the owner, or why not.
    static func perform(_ recipe: ArisUndoRecipe, home: String, store: ArisUndoStore, hands: ArisUndoHands = .live) throws -> String {
        switch recipe {
        case .fileCreated(let path):
            let checked = try check(try unchanged(path, home: home), home: home)
            guard FileManager.default.fileExists(atPath: checked) else { throw ArisUndoError(message: "\(name(path)) isn't there any more") }
            try hands.trash(checked)
            return "\(name(path)) 휴지통으로 옮겼어요"
        case .fileChanged(let path, let copy, let after):
            let checked = try check(try unchanged(path, home: home), home: home)
            guard ArisUndoStore.hash(of: checked) == after else { throw ArisUndoError(message: "\(name(path)) changed since, so it was left as it is") }
            guard let data = store.copy(copy) else { throw ArisUndoError(message: "the earlier copy of \(name(path)) is gone") }
            try putBack(data, at: checked)
            store.remove(copy)
            return "\(name(path)) 이전 내용으로 되돌렸어요"
        case .fileMoved(let original, let current):
            try move(from: try check(try unchanged(current, home: home), home: home), to: try check(try unchanged(original, home: home), home: home))
            return "\(name(current)) 원래 자리로 옮겼어요"
        case .fileTrashed(let original, let trash):
            try move(from: try check(try unchanged(trash, home: home), home: home, trash: true), to: try check(try unchanged(original, home: home), home: home))
            return "\(name(original)) 휴지통에서 꺼냈어요"
        case .itemCreated(let kind, let id):
            guard let removeItem = hands.removeItem else { throw unavailable(kind) }
            try removeItem(kind, id)
            return "만든 \(kindWord(kind)) 지웠어요"
        case .itemChanged(let kind, let id, let before):
            guard let restoreItem = hands.restoreItem else { throw unavailable(kind) }
            try restoreItem(kind, id, before)
            return "\(kindWord(kind)) 이전대로 되돌렸어요"
        case .setting(let name, let before):
            guard let setSetting = hands.setSetting else { throw unavailable(name) }
            try setSetting(name, before)
            return "\(name) 이전 값으로 되돌렸어요"
        case .textInserted(let app, let element, let before):
            guard let setText = hands.setText else { throw unavailable(app) }
            // A replace: what it erased comes back from its kept copy (fourth VM run, D1).
            if let copy = ArisApps.TextUndo.mark(element)?.erased {
                guard let data = store.copy(copy), let erased = String(data: data, encoding: .utf8) else {
                    throw ArisUndoError(message: "the kept copy of what \(app)'s text held is gone")
                }
                try setText(app, element, erased)
                store.remove(copy)
                return "\(app)에서 지웠던 글을 되살렸어요"
            }
            try setText(app, element, before)
            return "\(app)에 입력한 글을 지웠어요"
        case .windowMoved(let app, let window, let frame):
            guard frame.count == 4, frame.allSatisfy(\.isFinite) else { throw ArisUndoError(message: "that window's frame isn't one Aris keeps") }
            guard let moveWindow = hands.moveWindow else { throw unavailable(app) }
            try moveWindow(app, window, frame)
            return "\(app) 창을 원래 자리로 옮겼어요"
        }
    }

    /// `path` absolute, standardized, inside the home folder (or an external disk under /Volumes), and not a place on the
    /// never-list. `trash`: it must be in the home folder's Trash.
    static func check(_ path: String, home: String, trash: Bool = false) throws -> String {
        guard path.hasPrefix("/") else { throw ArisUndoError(message: "not an absolute path") }
        let standardized = (path as NSString).standardizingPath
        let inHome = standardized.hasPrefix(home + "/"), onDisk = standardized.hasPrefix("/Volumes/") && standardized.split(separator: "/").count > 2
        guard inHome || onDisk else { throw ArisUndoError(message: "\(name(path)) is outside the home folder") }
        if trash, !standardized.hasPrefix(home + "/.Trash/") && !standardized.contains("/.Trashes/") {
            throw ArisUndoError(message: "\(name(path)) isn't in the Trash")
        }
        if ArisNeverList.pathRule(standardized, effect: .changeReversible, home: home) != nil {
            throw ArisUndoError(message: "\(name(path)) is in or holds a protected place")
        }
        return standardized
    }

    /// `path` only while every folder on the way to it is still the folder it was: resolved now (links followed, as the
    /// shell sandbox and the never-list resolve), its parent must be the parent kept in the recipe, and the resolved path
    /// must not be a protected place. A folder swapped for a link since (or any link on the way) refuses the undo, and
    /// nothing is touched. The system's own /var, /tmp and /etc links are the same place either way.
    static func unchanged(_ path: String, home: String) throws -> String {
        guard path.hasPrefix("/") else { throw ArisUndoError(message: "not an absolute path") }
        let standardized = (path as NSString).standardizingPath
        let parent = (standardized as NSString).deletingLastPathComponent
        let real = ArisShellSandbox.real(parent)
        guard systemForm(real) == systemForm(parent) else {
            throw ArisUndoError(message: "a folder on the way to \(name(path)) changed since, so nothing was touched")
        }
        let resolved = (real as NSString).appendingPathComponent((standardized as NSString).lastPathComponent)
        if ArisNeverList.pathRule(resolved, effect: .changeReversible, home: home) != nil
            || ArisNeverList.pathRule(resolved, effect: .changeReversible, home: ArisShellSandbox.real(home)) != nil {
            throw ArisUndoError(message: "\(name(path)) is in or holds a protected place")
        }
        return standardized
    }

    /// /private/var, /private/tmp and /private/etc as /var, /tmp and /etc (the system's own links).
    private static func systemForm(_ path: String) -> String {
        for place in ["/private/var", "/private/tmp", "/private/etc"] where path == place || path.hasPrefix(place + "/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }

    /// A move that never replaces anything (one atomic step).
    static func move(from: String, to: String) throws {
        guard renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 else {
            let failure = errno
            switch failure {
            case EEXIST: throw ArisUndoError(message: "\(name(to)) already exists there, so nothing was overwritten")
            case ENOENT: throw ArisUndoError(message: "\(name(from)) isn't there any more")
            default: throw ArisUndoError(message: "couldn't move it back: \(String(cString: strerror(failure)))")
            }
        }
    }

    /// The bytes written beside the file and renamed over it, keeping its permissions.
    private static func putBack(_ data: Data, at path: String) throws {
        let mode = ((try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? NSNumber)?.intValue ?? 0o644
        let temp = (path as NSString).deletingLastPathComponent + "/.aris-undo-" + UUID().uuidString
        guard FileManager.default.createFile(atPath: temp, contents: data, attributes: [.posixPermissions: mode]) else {
            throw ArisUndoError(message: "couldn't write \(name(path)) back")
        }
        guard rename(temp, path) == 0 else {
            unlink(temp)
            throw ArisUndoError(message: "couldn't put \(name(path)) back: \(String(cString: strerror(errno)))")
        }
    }

    private static func name(_ path: String) -> String { (path as NSString).lastPathComponent }

    private static func kindWord(_ kind: String) -> String {
        ["calendar": "일정", "reminder": "미리 알림", "note": "메모"][kind] ?? kind
    }

    private static func unavailable(_ what: String) -> ArisUndoError {
        ArisUndoError(message: "undoing \(what) isn't available in this helper yet")
    }
}
