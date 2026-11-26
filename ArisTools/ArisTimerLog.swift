//
//  ArisTimerLog.swift
//  aris-tools
//
//  A timer's length as the activity log words it ("5분", "1분 30초"), the way the app logs its own ("타이머: 25분") and
//  ArisActivityWords.timerLength reads it back: the log never keeps the bare number the tool was given (seventeenth VM
//  run, M2u: "타이머: 5" came back on the undo card as "Timer: 5"). Pure.
//

enum ArisTimerLog {
    static func length(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60, rest = max(0, seconds) % 60
        let words = [minutes > 0 ? "\(minutes)분" : nil, rest > 0 ? "\(rest)초" : nil].compactMap { $0 }
        return words.isEmpty ? "0초" : words.joined(separator: " ")
    }
}
