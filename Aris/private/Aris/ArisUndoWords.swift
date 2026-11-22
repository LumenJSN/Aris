//
//  ArisUndoWords.swift
//  Aris
//
//  What an undo from the app comes back as, and what Aris says about it: aris-agent's reasons (aris-tools' English) are
//  never shown or said as they are, but as a line of Aris's own (QA BUG-17). While an undo waits on macOS's folder
//  prompt for aris-agent ("…데스크탑 폴더의 파일에 접근하려고 합니다"), the notch says so after a few seconds. Pure, so the
//  tests run it.
//

import Foundation

enum ArisUndoOutcome: Equatable {
    /// Undone; what was.
    case done(String)
    /// It deletes an event Aris made, or (`revivesSchedule`) brings a removed schedule back: show `summary`, and if the
    /// user says yes, call again with this `id` and `confirmed: true` (the yes is for that entry only).
    case needsConfirm(id: String, summary: String, revivesSchedule: Bool = false)
    case failed(String)
    /// 403: the agent couldn't tell this was the Aris app, or the yes didn't echo the card it gave out (actions.log says
    /// which).
    case refused
}

enum ArisUndoWords {
    /// How long the app waits for an undo: past the agent's own minute (ArisActivityBridge.undoTimeout).
    static let clientTimeout: TimeInterval = 70
    /// After this long without an answer the notch says macOS may be asking about a folder.
    static let hintAfter: TimeInterval = 4

    /// Whether the outcome needs the user's yes on a card first (deleting an event Aris made, bringing a schedule back).
    static func asksOnCard(_ outcome: ArisUndoOutcome) -> Bool {
        if case .needsConfirm(let id, _, _) = outcome { return !id.isEmpty }
        return false
    }

    private static let folderNames = ["Desktop": ("데스크탑", "Desktop"), "Documents": ("문서", "Documents"), "Downloads": ("다운로드", "Downloads")]

    /// "Mac이 데스크탑 폴더 접근을 묻고 있어요. 허용하면 이어서 해요." (the folder when the log says which).
    static func waitingLine(folder: String?, korean: Bool) -> String {
        let name = folder.flatMap { folderNames[$0] }
        if korean {
            return "Mac이 \(name.map { $0.0 + " 폴더" } ?? "폴더") 접근을 묻고 있어요. 허용하면 이어서 해요."
        }
        return "Your Mac is asking whether Aris may use the \(name.map { $0.1 + " folder" } ?? "folder"). Allow it and I'll carry on."
    }

    /// The 200 reply's note when a taught run was undone in part (ArisUndoSteps.outcome): "kept:window", "kept:other".
    static let keptPrefix = "kept:"

    /// What a taught run's undo did and what stays (fourth VM run, D7: after a replay that made a new document, "되돌려"
    /// refused everything); nil when the note isn't one.
    static func keptLine(_ note: String, korean: Bool) -> String? {
        let kept = parse(note).map { $0.kept } ?? (note.hasPrefix(keptPrefix) ? String(note.dropFirst(keptPrefix.count)) : nil)
        guard let kept else { return nil }
        if kept == "window" {
            return korean ? "입력한 글은 지웠어요. 새 문서는 그대로 있어요." : "I removed the text I typed. The new document stays open."
        }
        return korean ? "되돌릴 수 있는 건 되돌렸어요. 나머지 단계는 그대로 있어요." : "I undid what can be undone. The other steps stay as they are."
    }

    // MARK: - What was undone, named (seventh VM run, item 5)

    /// The 200 reply's note when it says what was undone ("undid": "typed\t<app>" or "restored\t<app>" per line) or
    /// the lesson it was part of: "undo-note:" and the fields as JSON. Nil when it says neither (the note is as before).
    static let notePrefix = "undo-note:"

    struct Note: Equatable {
        var kept: String?
        /// What came back: the kind ("typed", "restored") and the app.
        var undid: [Undid]
        var lesson: String?
    }

    struct Undid: Equatable {
        let kind: String
        let app: String
    }

    static func note(reply: [String: Any]) -> String? {
        let undid = (reply["undid"] as? String).map { $0.split(separator: "\n").map(String.init) } ?? []
        let lesson = reply["lesson"] as? String
        guard !undid.isEmpty || lesson != nil else { return nil }
        var fields: [String: Any] = ["undid": undid]
        if let kept = reply["kept"] as? String { fields["kept"] = kept }
        if let lesson { fields["lesson"] = lesson }
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return nil }
        return notePrefix + String(decoding: data, as: UTF8.self)
    }

    static func parse(_ note: String) -> Note? {
        guard note.hasPrefix(notePrefix), let object = (try? JSONSerialization.jsonObject(with: Data(note.dropFirst(notePrefix.count).utf8))) as? [String: Any] else { return nil }
        let undid = (object["undid"] as? [String] ?? []).compactMap { code -> Undid? in
            let parts = code.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2, ["typed", "restored"].contains(parts[0]), !parts[1].isEmpty else { return nil }
            return Undid(kind: parts[0], app: clean(parts[1], limit: 60))
        }
        return Note(kept: object["kept"] as? String, undid: undid, lesson: (object["lesson"] as? String).map { clean($0, limit: 60) })
    }

    /// The reply after an undo: what was undone, named as what it was ("Removed the text I typed in TextEdit for “줄
    /// 추가”."), then what stays; a note that names nothing is said as before (keptLine, else the entry's own line).
    static func doneReply(_ note: String, summary: String, korean: Bool) -> String {
        guard let parsed = parse(note), !parsed.undid.isEmpty else { return keptLine(note, korean: korean) ?? doneLine(summary, korean: korean) }
        var seen: [Undid] = []
        for item in parsed.undid where !seen.contains(item) { seen.append(item) }
        let said = seen.map { undidLine($0, lesson: parsed.lesson, korean: korean) }.joined(separator: " ")
        switch parsed.kept {
        case "window"?: return said + (korean ? " 새 문서는 그대로 있어요." : " The new document stays open.")
        case let kept? where !kept.isEmpty: return said + (korean ? " 나머지 단계는 그대로 있어요." : " The other steps stay as they are.")
        default: return said
        }
    }

    static func undidLine(_ item: Undid, lesson: String?, korean: Bool) -> String {
        ArisJournalWords.textUndone(app: item.app, restored: item.kind == "restored", lesson: lesson, english: !korean)
    }

    /// The line for a failed undo, from the agent's reason: Aris's own words, never the reason as it came.
    static func failure(_ reason: String, korean: Bool) -> String {
        let said = reason.lowercased()
        func line(_ ko: String, _ en: String) -> String { korean ? ko : en }
        // Already Aris's own Korean (the app's "지금은 대화 중이에요…"): as it is.
        if korean, !reason.isEmpty, reason.replacingOccurrences(of: "Mac", with: "").range(of: "[A-Za-z]{3,}", options: .regularExpression) == nil { return reason }
        // Text put into an app (fourth VM run, D7: "되돌리지 못했어요." with no reason): why, in words.
        if said.contains("isn't available in this helper") {
            return line("그 일을 되돌리는 기능이 아직 켜지지 않았어요. Aris를 다시 연 뒤 해 주세요.", "Undo for that isn't ready yet. Reopen Aris and try again.")
        }
        if said.contains("was edited after aris") {
            return line("그 뒤로 글이 바뀌었거나 창이 닫혀서, 글은 그대로 뒀어요.", "The text was edited since, or its window was closed, so I left it as it is.")
        }
        if said.contains("already back as it was") || said.contains("already gone from") {
            return line("입력했던 글은 이미 없어요.", "The text I typed is already gone.")
        }
        if said.contains("isn't open any more") { return line("앱이 닫혀서 글은 그대로 뒀어요.", "The app is closed, so I left its text as it is.") }
        if said.contains("more than one place") { return line("같은 글이 여러 곳에 있어서 그대로 뒀어요.", "That text is in more than one place, so I left it as it is.") }
        if said.contains("didn't let aris") { return line("앱이 글을 고치게 해 주지 않아서 그대로 뒀어요.", "The app didn't let me change its text, so I left it as it is.") }
        if said.contains("changed the text differently") { return line("앱이 글을 다르게 바꿨어요. 확인해 주세요.", "The app changed the text differently. Please check it.") }
        if said.contains("needs accessibility") { return line("손쉬운 사용 권한이 있어야 글을 되돌릴 수 있어요.", "I need Accessibility to take the text back.") }
        if said.contains("kept copy") { return line("지웠던 글의 사본이 없어져서 되살릴 수 없어요.", "The copy of the erased text is gone, so it can't be put back.") }
        if said.contains("isn't one aris can take back") { return line("그 글은 되돌릴 수 없어요.", "That text can't be undone.") }
        if said.contains("didn't answer") || said.contains("in time") || said.contains("timed out") {
            return line("되돌리는 데 시간이 너무 걸려서 멈췄어요. Mac이 폴더 접근을 물었다면 허용한 뒤 다시 해 주세요.",
                        "Undoing took too long, so I stopped. If your Mac asked about a folder, allow it and try again.")
        }
        if said.contains("nothing to undo") { return line("되돌릴 게 없어요.", "There's nothing to undo.") }
        if said.contains("can't be undone") { return line("방금 한 일은 되돌릴 수 없어요.", "What I just did can't be undone.") }
        if said.contains("already undone") { return line("이미 되돌렸어요.", "That was already undone.") }
        if said.contains("no entry") { return line("그 기록을 찾지 못했어요.", "I couldn't find that entry.") }
        if said.contains("no such event") || said.contains("isn't there") || said.contains("already gone") {
            return line("되돌릴 게 이미 없어요. 지워졌거나 옮겨졌을 수 있어요.", "It's already gone: it may have been moved or deleted.")
        }
        if said.contains("already exists") { return line("그 자리에 같은 이름이 있어서 덮어쓰지 않았어요.", "Something with that name is already there, so I didn't overwrite it.") }
        if said.contains("not permitted") || said.contains("permission") || said.contains("not allowed") {
            // The page is named as the settings window names it on this Mac.
            let place = ArisSettingsPath.path(.control)
            return line("Mac이 접근을 허용하지 않아서 되돌리지 못했어요. \(place)에서 폴더 접근을 허용해 주세요.",
                        "Your Mac didn't allow it. Allow folder access in \(place).")
        }
        return line("되돌리지 못했어요.", "I couldn't undo it.")
    }

    // MARK: - Which entry, in the user's words (QA BUG-42 retest)

    /// One undoable entry, newest first in a list.
    struct Candidate: Equatable {
        let id: String
        let summary: String
        let action: String?
        /// Its undo needs a yes of its own from aris-agent (it deletes an event Aris made, or brings a removed
        /// schedule back): the helper asks about it itself (ArisUndoSteps).
        let asks: Bool
        /// A taught procedure's run (its record session): its steps are one change, undone together, newest first.
        var unit: String?

        init(id: String, summary: String, action: String?, asks: Bool = false, unit: String? = nil) {
            self.id = id
            self.summary = summary
            self.action = action
            self.asks = asks
            self.unit = unit
        }
    }

    /// One change as the activity list has it (the old log's rows and Core 2's record's, by time).
    struct Change: Equatable {
        let id: String
        let date: Date
        let summary: String
        let action: String?
        let asks: Bool
        let undoable: Bool
        var unit: String?
        /// Nothing of the user's to take back (ArisActivityItem.passOver): a bare "되돌려" walks past it.
        var passOver = false
    }

    /// What "되돌려" reaches (third VM run, D3: after a replay it offered a to-do from minutes earlier, because the
    /// replay's typing had no undo and the list skipped every change that couldn't be undone).
    enum Reach: Equatable {
        /// Undo this (a unit: every undoable step of the run, newest first).
        case undo(Candidate, newest: Candidate?, doubt: Bool)
        /// The newest change can't be undone: said, and nothing older is taken instead.
        case cannot(String)
        /// Nothing of the kind named among the undoable ones (the two newest offered in words).
        case noneOfKind([Candidate])
        case nothing
    }

    /// The changes since `reach`, newest first, a taught procedure's run made one change. A bare "되돌려" takes the
    /// newest change, and when that one can't be undone it says so instead of reaching past it; a kind named ("만든 거")
    /// takes the newest undoable change of that kind, as before. What changed nothing of his (an app opened, what is
    /// left of a run already undone) is no change: it is walked past to the change before it (fifth VM run, D6), and
    /// the card names that change.
    static func reach(_ changes: [Change], since reach: Date, kind: String?) -> Reach {
        let recent = changes.filter { $0.date >= reach }.sorted { $0.date > $1.date }
        var merged: [(change: Change, candidate: Candidate?)] = []
        var index = 0
        while index < recent.count {
            let change = recent[index]
            guard let unit = change.unit else {
                index += 1
                // No change of his: walked past.
                if change.passOver, !change.undoable { continue }
                merged.append((change, change.undoable ? Candidate(id: change.id, summary: change.summary, action: change.action, asks: change.asks) : nil))
                continue
            }
            var steps: [Change] = []
            while index < recent.count, recent[index].unit == unit {
                steps.append(recent[index])
                index += 1
            }
            // A run whose every step left is no change of his: walked past.
            if steps.allSatisfy({ $0.passOver && !$0.undoable }) { continue }
            let undoable = steps.filter(\.undoable)
            let candidate = undoable.first.map { newest in
                Candidate(id: newest.id, summary: undoable.map(\.summary).joined(separator: ", "), action: newest.action,
                          asks: undoable.contains(where: \.asks), unit: unit)
            }
            merged.append((steps[0], candidate))
        }
        guard let newest = merged.first else { return .nothing }
        let candidates = merged.compactMap(\.candidate)
        guard let kind else {
            guard let candidate = newest.candidate else { return .cannot(newest.change.summary) }
            return .undo(candidate, newest: candidate, doubt: false)
        }
        let (entry, doubt) = pick(candidates, kind: kind)
        guard let entry else { return candidates.isEmpty ? .nothing : .noneOfKind(candidates) }
        return .undo(entry, newest: candidates.first, doubt: doubt)
    }

    /// The newest change can't be undone: said, and nothing older is offered in its place.
    static func cannotLine(_ summary: String, korean: Bool) -> String {
        korean ? "방금 한 일(\(shown(summary, korean: true)))은 되돌릴 수 없어요. 그 전 일은 한 일 탭에서 골라 되돌릴 수 있어요."
            : "What I just did (\(shown(summary, korean: false))) can't be undone. Earlier changes can be undone from the Activity tab."
    }

    /// The kind the user's words name: "만든/추가한/저장한/보낸 거" made, "지운/삭제한/취소한/버린 거" removed, "옮긴 거" moved; nil for a
    /// bare "되돌려 줘".
    static func kind(in heard: String) -> String? {
        let words = heard.lowercased()
        if words.range(of: #"(지운|삭제한|취소한|버린|없앤|deleted|removed|cancel+ed)"#, options: .regularExpression) != nil { return "removed" }
        if words.range(of: #"(옮긴|moved)"#, options: .regularExpression) != nil { return "moved" }
        if words.range(of: #"(만든|만들어 ?준|추가한|넣은|저장한|보낸|예약한|made|added|created|saved|sent)"#, options: .regularExpression) != nil { return "made" }
        return nil
    }

    /// How far back "undo that" reaches by words alone.
    static let recent: TimeInterval = 15 * 60
    /// The first turn's own work came a little before its reply was recorded as the conversation's start.
    static let firstTurn: TimeInterval = 5 * 60

    /// The oldest change "undo that" may pick: this conversation's, or the last 15 minutes', whichever reaches further
    /// back. Anything older is undone from the 한 일 tab, by pointing at it (fourth VM run, bug 5: with nothing newer it
    /// offered a two-hour-old conversion from another conversation). `conversationBegan`: nil when no turn of this
    /// conversation has been recorded yet.
    static func reach(now: Date, conversationBegan: Date?) -> Date {
        let floor = now.addingTimeInterval(-recent)
        return conversationBegan.map { min(floor, $0.addingTimeInterval(-firstTurn)) } ?? floor
    }

    /// Said when the only things that could be undone are older than `reach`: nothing is offered.
    static func nothingRecent(korean: Bool) -> String {
        korean ? "방금 한 일 중에는 되돌릴 게 없어요. 예전 일은 한 일 탭에서 되돌릴 수 있어요."
            : "There's nothing recent to undo. Older changes can be undone from the Activity tab."
    }

    /// The entry to undo: the newest of the kind named, else (none named) the newest. `doubt`: the kind was named and
    /// the newest entry is another kind, so the card says which it is and which it isn't.
    static func pick(_ candidates: [Candidate], kind: String?) -> (entry: Candidate?, doubt: Bool) {
        guard let kind else { return (candidates.first, false) }
        let match = candidates.first { $0.action == kind }
        return (match, match != nil && candidates.first != match)
    }

    /// An entry's summary as a card or a reply shows it (a summary holds a brain's words: a title, a file name):
    /// control and invisible format characters out, at most `limit` characters with a visible "…".
    static func clean(_ text: String, limit: Int = 120) -> String {
        let kept = String(String.UnicodeScalarView(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .format }))
        return kept.count > limit ? String(kept.prefix(limit)) + "…" : kept
    }

    /// A summary as a card or a reply shows it: cleaned, and in English where the card is English (the log's own
    /// line is Korean: "할 일 추가: that" is shown as "To-do added: that", by the 한 일 tab's table; third VM run).
    static func shown(_ summary: String, korean: Bool) -> String {
        clean(korean ? summary : ArisActivityWords.english(summary))
    }

    /// A summary on the undo card itself: cleaned and in the card's language, never cut (the card wraps and scrolls;
    /// cut at 120 characters a schedule's line lost the time it ends with: security review 3, I1).
    static func whole(_ summary: String, korean: Bool) -> String {
        clean(korean ? summary : ArisActivityWords.english(summary), limit: .max)
    }

    /// The helper's own card (an event deleted, a schedule revived): its summary whole. Where the card's words are
    /// not the log's own line (an English card), that line is shown under them: the yes goes back with exactly it
    /// (ArisUndoSteps.request), so the card shows what the yes is bound to.
    static func helperDetail(_ summary: String, korean: Bool) -> String {
        let said = whole(summary, korean: korean), logged = clean(summary, limit: .max)
        return said == logged ? said : said + "\n" + (korean ? "기록: " : "Logged as: ") + logged
    }

    /// Its card: always what will be undone; with doubt, the newest one too, which is left as it is.
    static func card(for entry: Candidate, newest: Candidate?, doubt: Bool, korean: Bool) -> (title: String, detail: String) {
        var detail = korean ? "되돌릴 일: \(whole(entry.summary, korean: true))" : "To undo: \(whole(entry.summary, korean: false))"
        if doubt, let newest { detail += "\n" + staysLine(newest, korean: korean) }
        return (korean ? "되돌리기" : "Undo", detail)
    }

    /// The card's second line when the user named a kind and the newest change is another kind: that one stays.
    static func staysLine(_ newest: Candidate, korean: Bool) -> String {
        korean ? "가장 최근 일(\(shown(newest.summary, korean: true)))은 말씀하신 종류가 아니라서 그대로 둬요"
            : "The latest one (\(shown(newest.summary, korean: false))) isn't that kind, so it stays"
    }

    /// Nothing of the kind named: the two newest, nothing done.
    static func noneOfKindLine(_ candidates: [Candidate], korean: Bool) -> String {
        let latest = candidates.prefix(2).map { shown($0.summary, korean: korean) }
        guard !latest.isEmpty else { return korean ? "되돌릴 일이 없어요." : "There's nothing to undo." }
        return korean ? "말씀하신 종류의 일은 없어요. 최근 일은 \(latest.joined(separator: ", "))예요. 어떤 걸 되돌릴까요?"
            : "Nothing of that kind. The latest are: \(latest.joined(separator: "; ")). Which one should I undo?"
    }

    /// The reply from the entry itself ("예약 취소: 저녁 할 일 알림 (매일 20:00)" → "‘저녁 할 일 알림’ 예약을 되돌렸어요",
    /// "할 일 추가: 우유" → "‘우유’ 할 일을 되돌렸어요"; in English "Undid “우유” (To-do added)."), never the tool's English
    /// line. What was changed is named by the line's kind (`doneNouns`: the kind's first word was taken for it, so a
    /// to-do read "‘우유’ 할을 되돌렸어요"). Only a schedule's line ends with its time in brackets, which is left out; a
    /// title's own brackets stay.
    static func doneLine(_ summary: String, korean: Bool) -> String {
        let summary = shown(summary, korean: korean)
        let parts = summary.components(separatedBy: ": ")
        guard parts.count >= 2 else { return korean ? "‘\(summary)’ 되돌렸어요." : "I took back “\(summary)”." }
        let label = parts[0], rest = parts.dropFirst().joined(separator: ": ")
        let title = scheduleLabels.contains(label) ? rest.replacingOccurrences(of: #"\s*\([^)]*\)$"#, with: "", options: .regularExpression) : rest
        // In English as in Korean: what was taken back, named as the thing it is (eighth VM run, item 6: "Undid “run8
        // 물 사기” (To-do added)." read like a log line).
        guard korean else { return englishNouns[label].map { "I took back the \($0) “\(title)”." } ?? "I took back “\(title)” (\(label))." }
        let noun = doneNouns[label] ?? label
        return "‘\(title)’ \(noun)\(ArisUndoWords.objectParticle(noun)) 되돌렸어요."
    }

    /// The kinds whose line ends with a time in brackets ("(매일 20:00)"), as the log and its English table write them.
    private static let scheduleLabels: Set<String> = ["예약", "예약 취소", "Scheduled", "Schedule cancelled"]

    /// What an undo put back, by the kind the log's line starts with (every kind in ArisActivityWords' table): the
    /// thing itself where the kind names one, else what was done to it. A kind not here is named by its own words.
    static let doneNouns: [String: String] = [
        "할 일 추가": "할 일", "할 일 완료": "할 일", "할 일 지움": "할 일", "내일로 넘김": "할 일", "일정 추가": "일정", "일정 삭제": "일정", "일정 변경": "일정",
        "예약": "예약", "예약 취소": "예약", "옮김": "옮긴 것", "이름 바꿈": "이름 바꾼 것", "새 폴더": "새 폴더", "휴지통으로": "휴지통에 넣은 것",
        "집 위치": "집 위치", "변환": "변환", "합침": "합친 것", "나눔": "나눈 것", "압축": "압축", "창 배치": "창 배치", "타이머": "타이머",
        "메시지 보냄": "메시지", "미리 알림 추가": "미리 알림", "메모 저장": "메모", "기억함": "기억", "기억 지움": "기억 지운 것",
        "기본 캘린더": "기본 캘린더", "메일 답장 초안": "메일 답장 초안", "입력": "입력한 글", "글 바꿈": "바꾼 글", "글 지움": "지운 글",
    ]

    /// The same in English, by the kind as ArisActivityWords says it. A kind not here is named by its own words.
    static let englishNouns: [String: String] = [
        "To-do added": "to-do", "To-do done": "to-do", "To-do removed": "to-do", "Moved to tomorrow": "to-do", "Event added": "event",
        "Event deleted": "event", "Event changed": "event", "Scheduled": "schedule", "Schedule cancelled": "schedule", "Moved": "move",
        "Renamed": "rename", "New folder": "new folder", "To the Trash": "move to the Trash", "Home": "home location", "Converted": "conversion",
        "Merged": "merge", "Split": "split", "Made smaller": "compression", "Windows arranged": "window arrangement", "Timer": "timer",
        "Message sent": "message", "Reminder added": "reminder", "Note saved": "note", "Remembered": "memory", "Memories cleared": "memory clearing",
        "Default calendar": "default calendar", "Mail reply drafted": "mail reply draft", "Typed": "typing", "Text replaced": "text replacement",
        "Text erased": "erasing",
    ]

    /// 을 after a final consonant, 를 after a vowel (Hangul); 를 otherwise.
    static func objectParticle(_ word: String) -> String {
        guard let last = word.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return "를" }
        return (last.value - 0xAC00) % 28 == 0 ? "를" : "을"
    }
}
