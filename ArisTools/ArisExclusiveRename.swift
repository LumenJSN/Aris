//
//  ArisExclusiveRename.swift
//  aris-tools
//
//  A rename that never replaces what is at the target, also on disks that can't do it in one step. APFS and HFS+ take
//  renamex_np's RENAME_EXCL; exFAT, FAT (most USB sticks and SD cards) and many network shares answer ENOTSUP or EINVAL,
//  so a move or a conversion onto one failed with "Operation not supported" (audit 15). There it falls back to a hard
//  link then unlinking the old name (link never replaces either), and where links are missing too (exFAT, FAT) to a
//  check that nothing is at the target followed by a plain rename. That last step leaves a moment between the check and
//  the rename in which another program could put a file there; on those disks that is the best the system offers.
//

import Darwin
import Foundation

enum ArisExclusiveRename {
    /// The system calls, so the tests can play a disk that refuses them.
    struct System {
        var exclusive: (String, String) -> Int32 = { renamex_np($0, $1, UInt32(RENAME_EXCL)) == 0 ? 0 : errno }
        var link: (String, String) -> Int32 = { Darwin.link($0, $1) == 0 ? 0 : errno }
        var unlink: (String) -> Int32 = { Darwin.unlink($0) == 0 ? 0 : errno }
        var exists: (String) -> Bool = { path in var info = stat(); return lstat(path, &info) == 0 }
        var rename: (String, String) -> Int32 = { Darwin.rename($0, $1) == 0 ? 0 : errno }
        static let live = System()
    }

    /// The answers that mean "this disk can't rename exclusively" rather than a real failure.
    static func unsupported(_ failure: Int32) -> Bool { failure == ENOTSUP || failure == EINVAL || failure == EOPNOTSUPP }

    /// Renames `from` to `to` without replacing anything there. 0 when done, else the errno (EEXIST: something is at
    /// `to`; EXDEV: another disk, the caller copies).
    static func rename(_ from: String, _ to: String, system: System = .live) -> Int32 {
        let failure = system.exclusive(from, to)
        guard failure != 0, unsupported(failure) else { return failure }
        // A file: a new name made by link (which fails if one is there), then the old name taken away. A folder can't
        // be linked; nor can anything on exFAT or FAT.
        let linked = system.link(from, to)
        if linked == 0 {
            let removed = system.unlink(from)
            guard removed == 0 else {
                _ = system.unlink(to)
                return removed
            }
            return 0
        }
        if linked == EEXIST { return EEXIST }
        if linked == EXDEV { return EXDEV }
        if system.exists(to) { return EEXIST }
        return system.rename(from, to)
    }
}
