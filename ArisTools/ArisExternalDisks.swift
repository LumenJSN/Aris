//
//  ArisExternalDisks.swift
//  aris-tools
//
//  Files on a disk the user plugged in (a USB stick, an external SSD, an SD card, a network share): `trash`, `move`,
//  `rename`, `folder new`, `convert` and `open` work there as they do in the home folder, behind the same gate (audit
//  tools-12: all of them refused outright, "outside your home folder", for something he asked for). What stays
//  refused: every place outside the home folder that isn't such a disk (the system's folders, other users', /tmp), the
//  disk itself, the disk's own system folders (its Trash, Spotlight's index), the Mac's own system volumes that show
//  up beside it (Recovery), and a Time Machine backup disk. Paths come here already resolved (links followed), so a
//  link on the disk into a protected place is judged as that place.
//

import Foundation

struct ArisExternalDisks {
    enum Kind {
        /// A disk of the user's own files.
        case user
        /// One of the Mac's own volumes (the startup disk, Recovery), or not a disk at all.
        case system
        /// A Time Machine backup.
        case backup
    }

    /// Where disks are mounted.
    let root: String
    /// What the disk mounted at this folder is (the tests say; `mounted` asks macOS).
    let kind: (String) -> Kind

    /// The disks mounted on this Mac.
    static let mounted = ArisExternalDisks(root: "/Volumes", kind: liveKind)

    /// The disk's own folders that are never worked in.
    private static let systemFolders: Set = ["System Volume Information", "$RECYCLE.BIN", "Backups.backupdb", "lost+found"]

    /// The disk's folder and the path inside it, for a resolved path under `root`; nil for a path that isn't there.
    func place(_ resolved: String) -> (disk: String, inside: [String])? {
        guard resolved.hasPrefix(root + "/") else { return nil }
        let parts = resolved.dropFirst(root.count + 1).split(separator: "/").map(String.init)
        guard let name = parts.first else { return nil }
        return (root + "/" + name, Array(parts.dropFirst()))
    }

    /// Why this resolved path may not be worked on, as the words after the file's name; nil when it may.
    func refusal(_ resolved: String) -> String? {
        guard let place = place(resolved), !(place.disk as NSString).lastPathComponent.hasPrefix(".") else {
            return "is outside your home folder and not on an external disk"
        }
        switch kind(place.disk) {
        case .system: return "is outside your home folder, on one of the Mac's own system volumes"
        case .backup: return "is on a Time Machine backup disk, which Aris never changes"
        case .user: break
        }
        guard let top = place.inside.first else { return "is the disk itself, not something on it" }
        if top.hasPrefix(".") || Self.systemFolders.contains(top) { return "is in one of the disk's own system folders" }
        return nil
    }

    /// The disk's Trash for this user: where macOS puts what is trashed on that disk.
    func trash(of disk: String, user: uid_t) -> String { disk + "/.Trashes/\(user)" }

    /// A Time Machine destination by what it holds at its top.
    static func looksLikeBackup(_ disk: String) -> Bool {
        ["Backups.backupdb", "backup_manifest.plist", ".com.apple.timemachine.donotpresent"].contains { FileManager.default.fileExists(atPath: disk + "/" + $0) }
    }

    /// What macOS says of the volume mounted there: a user's disk when it is external, removable, ejectable or a network
    /// share; the startup disk, a hidden volume, an internal one that can't be ejected (Recovery) or a plain folder is
    /// the system's.
    static func liveKind(_ disk: String) -> Kind {
        if looksLikeBackup(disk) { return .backup }
        let keys: Set<URLResourceKey> = [.volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsRootFileSystemKey,
                                         .volumeIsBrowsableKey, .volumeIsLocalKey]
        guard let values = try? URL(fileURLWithPath: disk).resourceValues(forKeys: keys),
              values.volumeIsRootFileSystem != true, values.volumeIsBrowsable != false else { return .system }
        let own = values.volumeIsInternal == false || values.volumeIsEjectable == true || values.volumeIsRemovable == true || values.volumeIsLocal == false
        return own ? .user : .system
    }
}
