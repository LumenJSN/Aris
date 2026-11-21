//
//  ArisToolErrorWords.swift
//  Aris
//
//  A tool's reason for not doing something, in the UI's language beside the app's own words: the known ones written
//  both ways, an unknown one shown only when it is already in that language (it is always in the log). A raw English
//  tool error never follows a Korean line again (VM run 2026-11-19: "바꾸지 못했어요: won't type into Aris"). Pure.
//

import Foundation

enum ArisToolErrorWords {
    /// A known reason: its pattern (one capture at most, put where %@ is), its Korean and English, and a reason as a
    /// tool writes it (the tests render every entry from it).
    struct Known {
        let pattern: String
        let korean: String
        let english: String
        let sample: String
    }

    static let known: [Known] = [
        Known(pattern: "^won't type into (.+)$", korean: "%@에는 입력하지 않아요", english: "Aris won't type into %@", sample: "won't type into Aris"),
        Known(pattern: "^a password field has the keyboard$", korean: "비밀번호 칸에 입력 중이라 넣지 않았어요", english: "a password field has the keyboard",
              sample: "a password field has the keyboard"),
        Known(pattern: "^no app has the keyboard right now", korean: "지금 어느 앱이 입력을 받는지 알 수 없어서 아무것도 넣지 않았어요",
              english: "no app has the keyboard right now, so nothing was typed", sample: "no app has the keyboard right now, so nothing was typed"),
        Known(pattern: "^another Aris task is using the keys and pointer", korean: "다른 Aris 작업이 키보드와 포인터를 쓰고 있어서 넣지 않았어요",
              english: "another Aris task is using the keys and pointer, so nothing was typed",
              sample: "another Aris task is using the keys and pointer, so nothing was typed"),
        Known(pattern: "^Aris needs .+ \\(System Settings → Privacy & Security\\)$",
              korean: "Aris에 \(ArisFix.Pane.accessibility.title(english: false)) 권한이 필요해요 (시스템 설정 → 개인정보 보호 및 보안)",
              english: "Aris needs \(ArisFix.Pane.accessibility.title(english: true)) (System Settings → Privacy & Security)",
              sample: "Aris needs Accessibility (System Settings → Privacy & Security)"),
        // The app layer's app.open and app.find (third VM run: a taught step's "no app on this Mac is called ‘Spotlight’"
        // stood in English inside a Korean line). The name stays as the tool wrote it.
        Known(pattern: "^no app on this Mac is called [‘'\"“](.+?)[’'\"”]$", korean: "이 Mac에 없는 앱이에요: ‘%@’",
              english: "no app on this Mac is called ‘%@’", sample: "no app on this Mac is called ‘Spotlight’"),
    ]

    /// `problem` in English (`english`) or Korean; nil when it can't be said in that language (left out, never shown raw).
    static func shown(_ problem: String, english: Bool) -> String? {
        let text = problem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        for entry in known {
            guard let match = try? NSRegularExpression(pattern: entry.pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            let name = match.numberOfRanges > 1 ? Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? "" : ""
            return (english ? entry.english : entry.korean).replacingOccurrences(of: "%@", with: name)
        }
        let korean = text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
        return korean == !english ? text : nil
    }

    /// "<the app's line>: <the reason>" in one language, or the line alone (with a full stop) when the reason can't be
    /// said in it.
    static func line(_ korean: String, _ english: String, problem: String, inEnglish: Bool = ArisUIWords.english) -> String {
        let lead = inEnglish ? english : korean
        guard let reason = shown(problem, english: inEnglish) else { return lead + "." }
        return "\(lead): \(reason)"
    }
}
