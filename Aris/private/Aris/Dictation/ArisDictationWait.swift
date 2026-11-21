//
//  ArisDictationWait.swift
//  Aris
//
//  Dictation's words waiting to go in (2026-11-18 audit). The helper types them only when the keys and pointer are free
//  (ArisDesktopLock: another task, computer use, may hold them up to 90 s), so the notch says it is waiting rather than
//  looking as if the words were lost, they are on the clipboard once the wait is long, and they are always kept for
//  ⌃⌘V. A paste the helper refuses for want of Accessibility says so in full on the notice pill, with the list to
//  open, where the dictation pill has room for a few words only. Foundation only (tested).
//

import Foundation

enum ArisDictationWait {
    /// The notch says it is waiting after this long without an answer.
    static let showAfter: Duration = .milliseconds(1500)
    /// From here the words are on the clipboard too.
    static let copyAfter: Duration = .seconds(6)
    /// The app waits as long as the helper may: 90 s for the keys (ArisDesktopLock's waitLimit), the paste's 2 s, and a
    /// margin. Before, it gave up at 6 s and said "copied" while the helper still typed the words later.
    static let insertTimeout: TimeInterval = 95

    enum Stage: Equatable { case typing, waiting, waitingCopied }

    static func stage(after elapsed: Duration) -> Stage {
        elapsed >= copyAfter ? .waitingCopied : elapsed >= showAfter ? .waiting : .typing
    }

    /// The notch's status for a stage (nil: typing, nothing to say).
    static func status(_ stage: Stage, english: Bool) -> String? {
        switch stage {
        case .typing: nil
        case .waiting: ArisUIWords.text("다른 작업이 키보드를 쓰는 중 · 끝나면 넣을게요", "Another task has the keyboard · typing it when it's done", english: english)
        case .waitingCopied: ArisUIWords.text("아직 기다리는 중 · 클립보드에도 복사해 뒀어요", "Still waiting · also copied to the clipboard", english: english)
        }
    }

    /// The dictation pill's own line when the helper may not type: short enough for the pill; the notice has the rest.
    static func pillLine(english: Bool) -> String {
        ArisUIWords.text("입력하지 못했어요 · 복사해 뒀어요", "Couldn't type it · copied", english: english)
    }
}
