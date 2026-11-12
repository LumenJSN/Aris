//
//  ArisReceiptWords.swift
//  Aris
//
//  The words of the receipt under an answer (ArisReceipt): what one act is called, short and in the past tense
//  ("엄마에게 보냄", "미리 알림에 추가함"), read from the activity log's own line for it ("메시지 보냄: 엄마"), never from what
//  the brain said; the count for several ("3가지 함"); and the undo's words. A log line this table doesn't know is
//  shown as the log has it, so a new kind of act is never hidden or renamed. Korean and English, by the UI's language.
//  Foundation only, so it is tested against every line the tools write.
//

import Foundation

enum ArisReceiptWords {
    /// The longest a receipt's own words run before "…": it is one line of a chip.
    static let lineLimit = 40
    /// A file's name in a receipt is cut to this many letters.
    static let nameLimit = 24

    static func undo(english: Bool) -> String { english ? "Undo" : "되돌리기" }
    static func undone(english: Bool) -> String { english ? "Undone" : "되돌렸어요" }
    static func undoing(english: Bool) -> String { english ? "Undoing…" : "되돌리는 중…" }

    /// Several acts in one turn.
    static func count(_ acts: Int, english: Bool) -> String { english ? "Did \(acts) things" : "\(acts)가지 함" }

    /// The count line's tooltip: a press opens the side notch's 한 일 tab.
    static func openHelp(english: Bool) -> String { english ? "See them in the \(ArisSideTab.activity.name(english: true)) tab" : "한 일 탭에서 보기" }

    /// The agent couldn't tell the undo came from the Aris app (403).
    static func refused(english: Bool) -> String {
        english ? "I couldn't undo it: Aris couldn't confirm the press was yours (see actions.log)." : ArisActivityTab.refusedNotice
    }

    /// Why an undo didn't happen, in Aris's own words (ArisUndoWords), never the agent's reason as it came.
    static func notUndone(_ reason: String, english: Bool) -> String { ArisUndoWords.failure(reason, korean: !english) }

    /// Log labels whose receipt is the same whatever they name.
    private static let fixed: [String: (korean: String, english: String)] = [
        "미리 알림 추가": ("미리 알림에 추가함", "Added to Reminders"),
        "할 일 추가": ("할 일에 추가함", "Added to your to-dos"),
        "할 일 완료": ("할 일 완료함", "Ticked off a to-do"),
        "할 일 지움": ("할 일 지움", "Removed a to-do"),
        "내일로 넘김": ("내일로 넘김", "Moved to tomorrow"),
        "일정 추가": ("캘린더에 추가함", "Added to Calendar"),
        "일정 삭제": ("일정 지움", "Deleted an event"),
        "일정 변경": ("일정 바꿈", "Changed an event"),
        "이름 바꿈": ("이름 바꿈", "Renamed"),
        "새 폴더": ("폴더 만듦", "Made a folder"),
        "예약": ("예약함", "Scheduled"),
        "예약 취소": ("예약 취소함", "Removed a schedule"),
        "타이머": ("타이머 맞춤", "Set a timer"),
        "타이머 끔": ("타이머 끔", "Stopped the timer"),
        "뽀모도로": ("뽀모도로 시작함", "Started a Pomodoro"),
        "창 배치": ("창 배치함", "Arranged the windows"),
        "집 위치": ("집 위치 저장함", "Saved your home place"),
        "메모 저장": ("메모에 저장함", "Saved to Notes"),
        "기억함": ("기억해 둠", "Remembered"),
        "기억 지움": ("기억에서 지움", "Forgotten"),
        "기본 캘린더": ("기본 캘린더 바꿈", "Changed the default calendar"),
        "음소거 바꿈": ("볼륨 바꿈", "Changed the volume"),
    ]

    /// Files made from others (`convert`, `merge`, `split`, `compress`): the log names the verb in Korean once it is
    /// done and as the command's own word while it runs or when it stopped half-way.
    private static let made: [String: (korean: String, english: String)] = [
        "변환": ("변환함", "Converted"), "convert": ("변환함", "Converted"),
        "합침": ("하나로 합침", "Merged"), "merge": ("하나로 합침", "Merged"),
        "나눔": ("PDF 나눔", "Split the PDF"), "split": ("PDF 나눔", "Split the PDF"),
        "압축": ("용량 줄임", "Made smaller"), "compress": ("용량 줄임", "Made smaller"),
    ]

    /// One act's receipt from its log line.
    static func line(_ summary: String, english: Bool) -> String {
        let shown = ArisUndoWords.clean(summary, limit: lineLimit)
        let parts = ArisUndoWords.clean(summary, limit: 400).components(separatedBy: ": ")
        let label = parts[0].trimmingCharacters(in: .whitespaces)
        let detail = parts.dropFirst().joined(separator: ": ").trimmingCharacters(in: .whitespaces)
        func say(_ korean: String, _ inEnglish: String) -> String { english ? inEnglish : korean }
        if let words = fixed[label] { return say(words.korean, words.english) }
        if let words = made[label] {
            // "convert: 2개 (중간에 멈춤)": what was made before it stopped is still there.
            guard detail.contains("중간에 멈춤") else { return say(words.korean, words.english) }
            let count = String(detail.prefix { $0.isNumber })
            return say("\(count.isEmpty ? "" : "\(count)개 ")만들고 멈춤", count.isEmpty ? "Stopped part-way" : "Made \(count), then stopped")
        }
        switch label {
        case "메시지 보냄":
            // A name is said ("엄마에게 보냄"); a number or an address is in the tooltip, not the line.
            return isHandle(detail) || detail.isEmpty ? say("메시지 보냄", "Message sent") : say("\(detail)에게 보냄", "Sent to \(detail)")
        case "옮김":
            let name = short(detail.components(separatedBy: " → ")[0])
            return name.isEmpty ? say("파일 옮김", "Moved a file") : say("\(name) 옮김", "Moved \(name)")
        case "휴지통으로":
            let name = short(detail)
            return name.isEmpty ? say("휴지통으로 옮김", "Moved to the Trash") : say("\(name) 휴지통으로", "Moved \(name) to the Trash")
        default:
            if label.hasPrefix("볼륨") { return say("볼륨 바꿈", "Changed the volume") }
            return shown
        }
    }

    /// A phone number or an address, as Messages takes them, rather than a contact's name.
    private static func isHandle(_ who: String) -> Bool {
        who.contains("@") || who.range(of: #"^[+0-9][0-9 ()\-]{4,}$"#, options: .regularExpression) != nil
    }

    /// A file's name, cut in the middle so its ending (the kind of file) stays.
    private static func short(_ name: String) -> String {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard name.count > nameLimit else { return name }
        let tail = 8
        return String(name.prefix(nameLimit - tail - 1)) + "…" + String(name.suffix(tail))
    }
}
