//
//  ArisDoneFold.swift
//  Aris
//
//  The owner's 1B (mockups/done-and-reader.html): in the open notch, work still running stays a tag each, and everything
//  finished folds into one chip ("3개 끝남 · 최근 것") whose tray lists the newest four. "다 봤어요" marks them seen and
//  the chip goes; a job finishing later brings it back. A job that has just finished stays a tag while its check
//  lands, then slides into the chip. The 기록 tab keeps every result either way. Pure, so it's tested.
//

import Foundation

enum ArisDoneFold {
    struct Fold: Equatable {
        /// Tags, oldest first: running jobs, and finished ones whose check is still landing.
        var running: [ArisBackgroundTask]
        /// The chip's jobs, unseen and finished (done, failed or cancelled), newest first.
        var done: [ArisBackgroundTask]
    }

    /// How many rows the tray lists before pointing at the 기록 tab.
    static let trayRows = 4
    /// The tag's check lands, then it slides into the chip.
    static let landingTime: Duration = .milliseconds(520)

    /// `tasks` oldest first, as the controller keeps them.
    static func fold(_ tasks: [ArisBackgroundTask], seen: Set<UUID>, landing: Set<UUID> = []) -> Fold {
        let running = tasks.filter { !$0.isFinished || (landing.contains($0.id) && !seen.contains($0.id)) }
        let done = tasks.filter { $0.isFinished && !seen.contains($0.id) && !landing.contains($0.id) }
        return Fold(running: running, done: done.reversed())
    }

    /// The row has something to show: a job running, or one finished and not yet seen.
    static func shows(_ tasks: [ArisBackgroundTask], seen: Set<UUID>) -> Bool {
        tasks.contains { !$0.isFinished || !seen.contains($0.id) }
    }

    /// What "다 봤어요" marks: every finished job there is now (older ids fall away with their jobs).
    static func seenAll(_ tasks: [ArisBackgroundTask]) -> Set<UUID> {
        Set(tasks.filter(\.isFinished).map(\.id))
    }

    static func count(_ done: Int, english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("\(done)개 끝남", "\(done) done", english: english) }

    /// The chip's count, by each job's verdict: "2 done · 1 not done" (a failed, not-done or stopped job is never counted
    /// as done: eighth VM pass, "✓ 4 done" with two of them failed).
    static func count(_ fold: Fold, english: Bool = ArisUIWords.english) -> String {
        let notDone = fold.done.filter(\.notDone).count, done = fold.done.count - notDone
        let doneWords = count(done, english: english)
        let notDoneWords = ArisUIWords.text("\(notDone)개 못 끝냄", "\(notDone) not done", english: english)
        if notDone == 0 { return doneWords }
        return done == 0 ? notDoneWords : doneWords + " · " + notDoneWords
    }

    /// The chip's mark: the check when every job in it was done, else the warning one.
    static func symbol(_ fold: Fold) -> String { fold.done.contains(where: \.notDone) ? "exclamationmark" : "checkmark" }

    /// The chip's second half: the newest finished job.
    static func latest(_ fold: Fold) -> String? {
        fold.done.first.map { "· \($0.title)" }
    }

    static func tray(_ fold: Fold) -> [ArisBackgroundTask] { Array(fold.done.prefix(trayRows)) }

    static func more(_ done: Int, english: Bool = ArisUIWords.english) -> String? {
        done > trayRows ? ArisUIWords.text("+\(done - trayRows)개 더 · 기록 탭에 있어요", "+\(done - trayRows) more · in the History tab", english: english) : nil
    }

    /// A tag's words: the title and what it's doing while it runs; the title alone once it's settled.
    static func label(_ task: ArisBackgroundTask, english: Bool = ArisUIWords.english) -> String {
        guard case .working(let status) = task.state else { return task.title }
        let doing = status.isEmpty ? ArisUIWords.text("하는 중", "Working", english: english) : ArisUIWords.status(status, english: english)
        return "\(runningTitle(task.title)) · \(doing)"
    }

    /// A running tag's title is cut to this many letters (with "…"), so what it's doing still shows on its one line.
    static let runningTitleLimit = 16

    static func runningTitle(_ title: String) -> String {
        guard title.count > runningTitleLimit else { return title }
        let cut = String(title.prefix(runningTitleLimit - 1)).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return cut + "…"
    }

    /// A tray row's words after the title: the answer, or what went wrong.
    static func detail(_ task: ArisBackgroundTask, english: Bool = ArisUIWords.english) -> String {
        switch task.state {
        case .working(let status): return ArisUIWords.status(status, english: english)
        case .done(let answer): return answer
        case .failed(let message): return ArisUIWords.status(message, english: english)
        }
    }
}

private extension ArisBackgroundTask {
    /// It finished without its work done (failed, not done by its verdict, or stopped).
    var notDone: Bool { if case .failed = state { true } else { false } }
}
