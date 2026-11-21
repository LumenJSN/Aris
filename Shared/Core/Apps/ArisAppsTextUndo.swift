//
//  ArisAppsTextUndo.swift
//  Shared/Core/Apps
//
//  The undo of text app.type put into a document or a field (third VM run, D3: a replay's typing was recorded as
//  run-with-undo, but nothing could take it back, so "되돌려" reached past it to a to-do from minutes before). What
//  was added is taken out again by its own range, so the rest of the text and its formatting stay: only when the
//  element still holds exactly what app.type left in it. What it held before is not kept (a whole document would sit
//  in the record): only lengths and hashes, and the text that went in.
//  Fourth VM run, D7: the recipe was made only when the field read back as exactly what it held plus the text sent
//  (TextEdit made "added line" "Added line"), and never for an empty field (its value reads as none); now it keeps where
//  the inserted run starts and the field's whole value right after the typing, both as read back (what the field
//  really holds, not what was sent), and the undo finds that value again and removes that range, or says exactly why
//  not. A replace (the field's whole value set) keeps what it erased in the undo store (a verified copy, as a file
//  overwrite does), and its undo puts that text back. Pure: the live performer (ArisAppsTextUndoLive) finds the
//  element and changes it.
//

import Foundation

extension ArisApps {
    enum TextUndo {
        /// What the record keeps of one insertion or replace (the recipe's `element`, as JSON).
        struct Mark: Codable, Equatable, Sendable {
            /// The app's bundle id.
            let bundle: String
            /// The element's role and label as the app layer read them ("textArea", "First Text View").
            let role: String
            let label: String
            /// The text Aris put in, as the field holds it (read back after the typing).
            let inserted: String
            /// What the element held before, in UTF-16 units (the range Accessibility counts in), and its hash.
            let beforeLength: Int
            let beforeHash: String
            /// Where the inserted text starts (UTF-16); nil in a recipe made before the fourth VM run (then right after
            /// what was there).
            var location: Int?
            /// The element's whole value right after the change, as read back: its length (UTF-16) and hash.
            var afterLength: Int?
            var afterHash: String?
            /// A replace: the undo store's id of the verified copy of what the field held (the erased text).
            var erased: String?
        }

        /// Where an undo stands against an element's value now.
        enum Found: Equatable, Sendable {
            /// The value is exactly what the change left: this range is what Aris put in.
            case range(NSRange)
            /// The value is what it was before the change: the text Aris put in is already gone.
            case gone
            /// Something else: the value was changed since.
            case changed
        }

        /// One insertion: the text put in at `location` (UTF-16) of `before`, as the difference of the two values read.
        struct Insertion: Equatable, Sendable {
            let location: Int
            let text: String
        }

        /// What app.type added, from the field's value before (`before`) and as read back right after (`after`): the run
        /// between their common start and end, only when everything that was there is still there (nothing replaced).
        static func insertion(before: String, after: String) -> Insertion? {
            let old = Array(before), new = Array(after)
            var prefix = 0
            while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < old.count - prefix, suffix < new.count - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
            guard prefix + suffix == old.count, new.count > old.count else { return nil }
            return Insertion(location: String(old[..<prefix]).utf16.count, text: String(new[prefix..<(new.count - suffix)]))
        }

        /// The recipe for what app.type left in that element: `before` read before it typed, `after` read back right
        /// after (an empty field reads as ""). Nil when nothing was added, or something that was there is gone.
        static func recipe(app: String, bundle: String, role: String, label: String, before: String, after: String) -> ArisUndoRecipe? {
            guard let added = insertion(before: before, after: after) else { return nil }
            let mark = Mark(bundle: bundle, role: role, label: label, inserted: added.text, beforeLength: before.utf16.count, beforeHash: hash(before),
                            location: added.location, afterLength: after.utf16.count, afterHash: hash(after))
            return encoded(mark, app: app)
        }

        /// `inserted` added after `before` (the text as it reads back).
        static func recipe(app: String, bundle: String, role: String, label: String, before: String, inserted: String) -> ArisUndoRecipe? {
            guard !inserted.isEmpty else { return nil }
            return recipe(app: app, bundle: bundle, role: role, label: label, before: before, after: before + inserted)
        }

        /// The recipe for a replace: the field held `before`, kept as the undo store's copy `copy`, and now holds `after`.
        static func replaced(app: String, bundle: String, role: String, label: String, before: String, after: String, copy: String) -> ArisUndoRecipe? {
            let mark = Mark(bundle: bundle, role: role, label: label, inserted: after, beforeLength: before.utf16.count, beforeHash: hash(before),
                            location: 0, afterLength: after.utf16.count, afterHash: hash(after), erased: copy)
            return encoded(mark, app: app)
        }

        private static func encoded(_ mark: Mark, app: String) -> ArisUndoRecipe? {
            guard let data = try? JSONEncoder().encode(mark), let element = String(data: data, encoding: .utf8) else { return nil }
            return .textInserted(app: app, element: element, before: "")
        }

        static func mark(_ element: String) -> Mark? {
            try? JSONDecoder().decode(Mark.self, from: Data(element.utf8))
        }

        /// The range (UTF-16) to take out of `value`: the added text, only when the value is what the change left.
        static func range(in value: String, mark: Mark) -> NSRange? {
            if case .range(let range) = find(in: value, mark: mark) { return range }
            return nil
        }

        /// Where `value` stands against the change `mark` describes.
        static func find(in value: String, mark: Mark) -> Found {
            let text = value as NSString
            let length = value.utf16.count, insertedLength = mark.inserted.utf16.count
            if let afterLength = mark.afterLength, let afterHash = mark.afterHash {
                if length == afterLength, hash(value) == afterHash {
                    let location = mark.location ?? mark.beforeLength
                    guard location >= 0, location + insertedLength <= length,
                          text.substring(with: NSRange(location: location, length: insertedLength)) == mark.inserted else { return .changed }
                    return .range(NSRange(location: location, length: insertedLength))
                }
            } else if length == mark.beforeLength + insertedLength, text.substring(from: mark.beforeLength) == mark.inserted,
                      hash(text.substring(to: mark.beforeLength)) == mark.beforeHash {
                // A recipe from before the fourth VM run: the text right after what was there.
                return .range(NSRange(location: mark.beforeLength, length: insertedLength))
            }
            return length == mark.beforeLength && hash(value) == mark.beforeHash ? .gone : .changed
        }

        /// Why nothing was taken back, in the app layer's words (ArisUndoWords says them in Aris's): `found` is what
        /// every text element of the app stood at.
        static func refusal(_ found: [Found], app: String, replace: Bool) -> String {
            if found.contains(.gone) { return replace ? "\(app)'s text is already back as it was" : "the text Aris typed is already gone from \(app)" }
            return replace ? "\(app)'s text was edited after Aris replaced it (or its window is closed), so it was left as it is"
                : "\(app)'s text was edited after Aris typed into it (or its window is closed), so it was left as it is"
        }

        /// A stable hash of a text (FNV-1a over its UTF-8, 64 bits): enough to tell the text is unchanged.
        static func hash(_ text: String) -> String {
            var value: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in text.utf8 {
                value ^= UInt64(byte)
                value = value &* 0x0000_0100_0000_01B3
            }
            return String(value, radix: 16)
        }
    }
}
