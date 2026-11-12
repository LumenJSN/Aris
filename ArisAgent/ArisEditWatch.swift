//
//  ArisEditWatch.swift
//  aris-agent
//
//  After dictation typed into a field, the field is read once a second for up to a minute (the edit session):
//  when the user's edits settle (the same text two reads running), or they leaves the field or clears it, the change is
//  checked (ArisCorrection). One misheard word he fixed is proposed for the dictionary, and added the second time.
//  Only the dictation's own field, only while it keeps the keyboard; never a password field, secure input, a password
//  app, a terminal or Aris (ArisFocusedField). Nothing it reads is logged or kept but the word itself.
//

import Foundation

final class ArisEditWatch: @unchecked Sendable {
    static let queue = DispatchQueue(label: "com.lumenjsn.aris.agent.editwatch", qos: .utility)
    /// The dictionary changed (the app's settings read it again).
    static let notification = "com.lumenjsn.aris.dictionary"
    private static let longest: TimeInterval = 60
    private static let every: TimeInterval = 1
    /// The app needs a moment to show the pasted text.
    private static let settle: TimeInterval = 0.3
    /// Touched on `queue` only.
    nonisolated(unsafe) private static var current: ArisEditWatch?

    private let field: ArisFocusedField
    private let inserted: String
    private let first: String
    private let started = Date()
    private var last: String
    private var changed = false
    private var stable = 0
    private var stopped = false

    private init(field: ArisFocusedField, inserted: String, value: String) {
        self.field = field
        self.inserted = inserted
        first = value
        last = value
    }

    /// Starts watching the focused field for the words just pasted (a watch already running ends unread).
    static func start(inserted: String) {
        queue.asyncAfter(deadline: .now() + settle) {
            current?.stopped = true
            current = nil
            guard let field = ArisFocusedField.current(), let value = field.value, value.contains(inserted) else { return }
            let watch = ArisEditWatch(field: field, inserted: inserted, value: value)
            current = watch
            watch.schedule()
        }
    }

    private func schedule() {
        Self.queue.asyncAfter(deadline: .now() + Self.every) { [self] in poll() }
    }

    private func poll() {
        guard !stopped else { return }
        guard Date().timeIntervalSince(started) < Self.longest, field.stillFocused, let value = field.value, !value.isEmpty else {
            return finish()
        }
        if value != last {
            last = value
            changed = true
            stable = 0
        } else if changed {
            stable += 1
            if stable >= 2 { return finish() }
        }
        schedule()
    }

    private func finish() {
        stopped = true
        if Self.current === self { Self.current = nil }
        guard changed, let change = ArisCorrection.detect(inserted: inserted, before: first, after: last) else { return }
        let outcome = ArisDictionaryStore.record(change)
        FileHandle.standardError.write(Data("aris-agent: dictation correction -> \(outcome)\n".utf8))
        DistributedNotificationCenter.default().postNotificationName(.init(Self.notification), object: nil, userInfo: nil,
                                                                     deliverImmediately: true)
    }
}

/// The learned dictionary file, changed by one writer at a time.
enum ArisDictionaryStore {
    private static let lock = NSLock()

    private static var file: URL {
        ArisLearnedDictionary.file(home: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    static func record(_ change: ArisCorrection.Change) -> ArisLearnedDictionary.Outcome {
        update { $0.record(heard: change.heard, meant: change.meant, at: Date()) } ?? .ignored
    }

    /// "accept", "dismiss" or "remove" `text`; false for anything else or when the file couldn't be written.
    static func apply(_ op: String, text: String) -> Bool {
        let done: Bool? = update { dictionary in
            switch op {
            case "accept": return dictionary.accept(text, at: Date())
            case "dismiss": dictionary.dismiss(text); return true
            case "remove": dictionary.remove(text); return true
            default: return false
            }
        }
        return done ?? false
    }

    /// Loads, changes and saves the file; nil when it couldn't be saved.
    private static func update<T>(_ change: (inout ArisLearnedDictionary) -> T) -> T? {
        lock.withLock {
            var dictionary = ArisLearnedDictionary.load(from: file)
            let result = change(&dictionary)
            return dictionary.save(to: file) ? result : nil
        }
    }
}
