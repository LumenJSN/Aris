//
//  ArisStopLine.swift
//  Aris
//
//  What the notch says after the user stops the work from its tag. A stop can't take back what was already done, so the
//  line never says "취소했어요": it says what the activity record (한 일) holds for this piece of work and that the rest
//  was stopped ("여기까지 했어요: ‘일정 추가: 회의’. 나머지는 멈췄어요."). With nothing on record it names the step it
//  stopped at; and when the record couldn't be read it says that and where to look. Only what finished keeps its
//  check: the step that was cut off is not ticked. Foundation only, so it is tested.
//

import Foundation

enum ArisStopLine {
    /// The steps as they stood at the stop: the ones that had finished, and the one that was running (nil when Aris
    /// was between steps or had begun none).
    struct Cut: Equatable {
        let finished: [String]
        let cutOff: String?
    }

    /// How many done things the line names before it counts the others.
    static let listed = 3
    /// The record's clock and the app's are read a moment apart.
    private static let slack: TimeInterval = 1
    /// What a cancelled job's row says (ArisJob.backgroundTask).
    static let cancelledWord = "취소됨"
    /// The record keeps a job's name to this many letters (ArisActivityBridge.label).
    private static let recordedTitle = 80

    static func cut(_ session: ArisSession) -> Cut {
        Cut(finished: session.steps.filter(\.done).map(\.label), cutOff: session.steps.first { !$0.done }?.label)
    }

    /// A job stopped from its tag: cut off at the step it was running; one still waiting had begun nothing.
    static func jobCut(_ state: ArisJobState) -> Cut {
        guard case .running(let step) = state, !step.isEmpty else { return Cut(finished: [], cutOff: nil) }
        return Cut(finished: [], cutOff: step)
    }

    /// What the conversation itself did since the turn began, oldest first: never a job's work, never what was undone.
    static func mine(_ items: [ArisActivityItem], since: Date) -> [String] {
        done(items.filter { ArisActivityTab.teammate(of: $0) == ArisActivityTab.mainName }, since: since)
    }

    /// What was done under a job's name since it was handed out.
    static func job(_ items: [ArisActivityItem], title: String, since: Date) -> [String] {
        let name = String(title.trimmingCharacters(in: .whitespaces).prefix(recordedTitle))
        return done(items.filter { $0.job == name }, since: since)
    }

    private static func done(_ items: [ArisActivityItem], since: Date) -> [String] {
        items.filter { !$0.undone && $0.date >= since.addingTimeInterval(-slack) }.sorted { $0.date < $1.date }.map(\.summary)
    }

    /// The line. `record`: what the activity record holds for this work (nil: it couldn't be read).
    static func line(record: [String]?, cut: Cut, english: Bool) -> String {
        if let record, !record.isEmpty { return doneSoFar(record, english: english) }
        let began = cut.cutOff != nil || !cut.finished.isEmpty
        guard began else { return english ? "Stopped." : "멈췄어요." }
        let unread = english ? " The activity record couldn't be read: check the Activity tab for anything that changed."
            : " 한 일 기록을 못 읽었어요. 바뀐 게 있는지는 ‘한 일’ 탭에서 확인해 주세요."
        return stoppedAt(cut.cutOff, english: english) + (record == nil ? unread : "")
    }

    private static func doneSoFar(_ record: [String], english: Bool) -> String {
        let named = record.prefix(listed).map { "‘\($0)’" }.joined(separator: ", ")
        let more = record.count - listed
        if english { return "Done so far: \(named)\(more > 0 ? " and \(more) more" : ""). The rest was stopped." }
        return "여기까지 했어요: \(named)\(more > 0 ? " 외 \(more)건" : ""). 나머지는 멈췄어요."
    }

    private static func stoppedAt(_ cutOff: String?, english: Bool) -> String {
        guard let cutOff else { return english ? "Stopped. The rest wasn't done." : "멈췄어요. 나머지는 안 했어요." }
        let status = ArisTagProgress.split(cutOff)
        let words = ArisTagProgress.withoutMinutes(status.words).trimmingCharacters(in: CharacterSet(charactersIn: "….").union(.whitespaces))
        if english {
            return "Stopped at ‘\(words)’\(status.count.map { ", step \($0.step) of \($0.of)" } ?? ""). The rest wasn't done."
        }
        return "‘\(words)’\(status.count.map { " \($0.text) 단계" } ?? "")에서 멈췄어요. 나머지는 안 했어요."
    }

    /// The tip on a running tag.
    static func help(english: Bool) -> String { english ? "Click to stop" : "눌러서 멈추기" }

    /// A job's row as shown: one the user stopped from its tag says what it had done (`notes`), not 취소됨. Any other row,
    /// and a stop the agent never confirmed, is left as it is.
    static func shown(_ task: ArisBackgroundTask, notes: [UUID: String]) -> ArisBackgroundTask {
        guard task.state == .failed(cancelledWord), let note = notes[task.id] else { return task }
        return ArisBackgroundTask(id: task.id, title: task.title, state: .failed(note))
    }
}
