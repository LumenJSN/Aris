//
//  ArisDropLearnedStore.swift
//  Aris
//
//  Where the learned drop suggestions are kept (ArisDropLearned): one small JSON file in the app's own Application
//  Support folder, written whole each time it changes, readable only by the user. Never under ~/.config/aris: nothing an
//  AI brain reads or writes ever touches it, and nothing in it is sent anywhere until the user presses a chip.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "drop")

enum ArisDropLearnedStore {
    static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Aris", isDirectory: true).appendingPathComponent("drop-suggestions.json")
    }

    static func load() -> ArisDropLearned {
        guard let file, let data = try? Data(contentsOf: file) else { return ArisDropLearned() }
        return ArisDropLearned(data: data)
    }

    static func save(_ learned: ArisDropLearned) {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try learned.data.write(to: file, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            // Only how many, never what: the requests are the user's words.
            log.error("the learned suggestions (\(learned.habits.count, privacy: .public)) couldn't be saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
