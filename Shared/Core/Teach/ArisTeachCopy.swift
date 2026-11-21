//
//  ArisTeachCopy.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  What Aris says and shows about taught procedures (ARCHITECTURE Part 3, F3), Korean first with the English beside it:
//  each step in plain words, the card the owner sees before anything is saved (every step, what varies, what was left
//  out, and that sending or deleting still asks each time), the list, the rename and delete cards, and a run's account.
//  The words of a step that came from the app (a label, a menu title, a value) are shown in quotes as they were seen.
//  Pure.
//

import Foundation

enum ArisTeachCopy {
    struct Card: Equatable, Sendable {
        let title: String
        let detail: String
        /// Every line, when `detail` had to be cut.
        let full: String?
    }

    static let shownSteps = 10

    /// A reason a step didn't run, in the UI's language (third VM run, D4: "3단계 … 안 됐어요: no app on this Mac is
    /// called 'Spotlight'" under a Korean UI): the app layer's known reasons are written both ways; any other is shown
    /// only when it is already in that language (it stays in the log), else nil.
    static func reason(_ why: String, english: Bool) -> String? {
        let text = why.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        for (pattern, korean, inEnglish) in knownReasons {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            let name = match.numberOfRanges > 1 ? Range(match.range(at: 1), in: text).map { String(text[$0].prefix(60)) } ?? "" : ""
            return (english ? inEnglish : korean).replacingOccurrences(of: "%@", with: name)
        }
        let hangul = text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
        return hangul == !english ? String(text.prefix(160)) : nil
    }

    /// The app layer's reasons (ArisAppsHands), English as it writes them, with their Korean. The Korean says what
    /// couldn't be done as a fact ("찾을 수 없었어요"), never in the words of his own no ("…지 못했어요" is turned into
    /// "…지 않을게요" when he answers a card with no: fourth VM run, "창에서 ‘Format’ 항목을 찾지 않을게요").
    static let knownReasons: [(pattern: String, korean: String, english: String)] = [
        ("^no app on this Mac is called ‘(.+?)’", "이 Mac에 ‘%@’라는 앱이 없어요", "no app on this Mac is called ‘%@’"),
        ("^nothing called ‘(.+?)’ in ", "창에서 ‘%@’ 항목을 찾을 수 없었어요", "couldn't find ‘%@’ in the window"),
        ("^‘(.+?)’ matches \\d+ things", "‘%@’에 맞는 게 여러 개예요", "‘%@’ matches several things"),
        ("has no command like ‘(.+?)’", "‘%@’ 같은 메뉴 명령이 없어요", "there's no command like ‘%@’"),
        // A taught step's exact item or control isn't there now (fourth VM run, D5): what the app shows instead.
        ("^that menu item isn't there now \\(.+? shows ‘(.+?)’ instead\\)", "그 메뉴 항목이 지금은 없어요 (앱에는 ‘%@’ 항목이 있어요)",
         "that menu item isn't there now (the app shows ‘%@’ instead)"),
        ("^that menu item isn't there now", "그 메뉴 항목이 지금은 없어요", "that menu item isn't there now"),
        ("^that menu item has another key now", "그 메뉴 항목의 단축키가 바뀌어서 누르지 않았어요", "that menu item has another key now, so it wasn't pressed"),
        // The app's own menu answers (ArisAppsLiveAccessibility.pressMenu; fifth VM run, D1: the reason never reached him).
        ("“([^”]+)” is greyed out", "‘%@’ 메뉴가 지금은 비활성화되어 있어요", "‘%@’ is greyed out in the menu right now"),
        ("^no menu item “(.+?)”", "‘%@’ 메뉴 항목을 찾을 수 없었어요", "couldn't find the menu item ‘%@’"),
        ("^“(.+?)” has no submenu", "‘%@’ 메뉴를 열 수 없었어요", "couldn't open the menu ‘%@’"),
        ("^the menu item didn't take the press", "메뉴 항목이 눌리지 않았어요", "the menu item didn't take the press"),
        ("^no menu bar for that app", "앱의 메뉴를 읽을 수 없었어요", "couldn't read the app's menus"),
        ("^that control isn't there now \\(.+? shows ‘(.+?)’ instead\\)", "그 버튼이 지금은 없어요 (앱에는 ‘%@’ 버튼이 있어요)",
         "that control isn't there now (the app shows ‘%@’ instead)"),
        ("^that control isn't there now", "그 버튼이 지금은 없어요", "that control isn't there now"),
        ("^opened ‘.+?’ but found no option ‘(.+?)’", "‘%@’ 항목을 찾을 수 없었어요", "couldn't find the option ‘%@’"),
        ("^the selection changed since this step was checked", "확인한 뒤에 선택된 글이 바뀌어서 넣지 않았어요", "the selected text changed after it was checked, so nothing was typed"),
        ("^what the field holds changed since this step was checked", "확인한 뒤에 칸의 글이 바뀌어서 바꾸지 않았어요", "the field's text changed after it was checked, so nothing was replaced"),
        ("^couldn't type into ", "입력할 수 없었어요", "couldn't type there"),
        ("^couldn't (?:press|reach|select|set) ", "누를 수 없었어요", "couldn't press it"),
        ("^at=end puts text into a text field or document", "글을 넣을 수 있는 칸이 아니에요", "that isn't a place for text"),
        ("isn't running, so there is no text to add to", "앱이 실행 중이 아니라 넣을 수 없었어요", "the app isn't running, so nothing was typed"),
        ("didn't let the caret move to the end", "글 끝으로 갈 수 없어서 넣지 않았어요", "the caret couldn't go to the end, so nothing was typed"),
    ]

    static func isEnglish(_ text: String) -> Bool {
        !text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
            && text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    // MARK: - Steps

    /// Keys as a person reads them ("cmd+shift+n" → "⌘⇧N", "return" → "Return").
    static func keys(_ keys: String) -> String {
        let marks = ["cmd": "⌘", "ctrl": "⌃", "opt": "⌥", "shift": "⇧", "fn": "fn "]
        let named = ["return": "Return", "esc": "Esc", "escape": "Esc", "space": "Space", "delete": "Delete", "tab": "Tab", "up": "↑", "down": "↓",
                     "left": "←", "right": "→"]
        return keys.split(separator: "+").map { part in
            let word = String(part)
            return marks[word] ?? named[word] ?? word.uppercased()
        }.joined()
    }

    /// A value as a card or a line shows it, in quotes: a line break as "↵" so it never makes a row of its own on the
    /// card (fourth VM run: "Lesson line one\nEnglish line" read as two rows).
    static func quoted(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n", with: "↵")
        return "‘" + ArisTextClip.clip(flat, 60) + "’"
    }

    /// A parameter's label as the card says it: a document's main text is Aris's own word for it ("본문"), so in an
    /// English UI it is "text" (fourth VM run, D8: "[본문]", "Changes each time: 본문"); a field's own label stays.
    static func label(_ label: String, english: Bool) -> String {
        english && label.hasPrefix(ArisTeachGeneralise.bodyLabel) ? "text" + label.dropFirst(ArisTeachGeneralise.bodyLabel.count) : label
    }

    /// One step in plain words. `values`: the run's values (nil: the read-back, which shows the parameter and its example).
    static func step(_ step: ArisTeachStep, in procedure: ArisTeachProcedure, values: [String: String]? = nil, english: Bool) -> String {
        let app = step.app
        let what = step.label.map(quoted) ?? step.target.map(quoted) ?? ""
        switch step.action {
        case .open:
            return english ? "Open \(app)" : "\(app) 열기"
        case .menu:
            let path = quoted(step.menuPath ?? "")
            return english ? "In \(app), choose \(path)" : "\(app)에서 메뉴 \(path) 누르기"
        case .type:
            let field = step.label.map { english && $0 == ArisTeachGeneralise.bodyLabel ? "the document's text" : quoted($0) }
                ?? step.target.map(quoted) ?? (english ? "the field" : "칸")
            // A step that replaces what the field holds says so: it erases what is there, and asks each time.
            if step.replaces {
                let value: String
                if let key = step.parameter, let parameter = procedure.parameter(key) {
                    value = values.map { quoted($0[key] ?? parameter.example) } ?? "[\(label(parameter.label, english: english))]"
                } else {
                    value = quoted(step.text ?? "")
                }
                return english ? "In \(app), replace everything in \(field) with \(value) (what was there is erased; asks each time)"
                               : "\(app)의 \(field) 내용을 지우고 \(value) 넣기 (원래 내용은 지워져요, 할 때마다 물어봐요)"
            }
            // A text that begins a line says so, and shows the line break it may put first as ↵ (the text the call carries).
            let onLine = step.newLine ? (english ? ", on a new line" : "") : ""
            let into = step.newLine && !english ? "\(field)에 새 줄로" : english ? field : "\(field)에"
            let mark = step.newLine ? lineBreak : ""
            if let key = step.parameter, let parameter = procedure.parameter(key) {
                if let values {
                    let value = quoted(step.typedText(values: [key: values[key] ?? parameter.example]) ?? parameter.example)
                    return english ? "In \(app), put \(value) in \(into)\(onLine)" : "\(app)의 \(into) \(value) 넣기"
                }
                if parameter.fromApp == true {
                    return english ? "In \(app), put \(mark)[\(label(parameter.label, english: true))] in \(into)\(onLine) (taken from the app: \(quoted(parameter.example)))"
                                   : "\(app)의 \(into) \(mark)[\(parameter.label)] 넣기 (앱에서 가져온 값: \(quoted(parameter.example)))"
                }
                return english ? "In \(app), put \(mark)[\(label(parameter.label, english: true))] in \(into)\(onLine) (looks typed by you: \(quoted(parameter.example)))"
                               : "\(app)의 \(into) \(mark)[\(parameter.label)] 넣기 (직접 입력한 것 같아요: \(quoted(parameter.example)))"
            }
            let text = quoted(step.typedText(values: [:]) ?? "")
            if step.fromApp ?? true {
                return english ? "In \(app), put \(text) in \(into)\(onLine) (taken from the app)" : "\(app)의 \(into) \(text) 넣기 (앱에서 가져온 값)"
            }
            return english ? "In \(app), put \(text) in \(into)\(onLine)" : "\(app)의 \(into) \(text) 넣기"
        case .click:
            let word = ArisTeachGeneralise.roleWord(step.role).map { " " + $0 } ?? ""
            return english ? "In \(app), press \(what)" : "\(app)에서 \(what)\(word) 누르기"
        case .select:
            if let option = step.option {
                return english ? "In \(app), set \(what) to \(quoted(option)) (taken from the app)"
                               : "\(app)에서 \(what) 고르기 → \(quoted(option)) (앱에서 가져온 값)"
            }
            return english ? "In \(app), pick \(what)" : "\(app)에서 \(what) 고르기"
        case .press:
            let shown = keys(step.keys ?? "")
            return english ? "In \(app), press \(shown)" : "\(app)에서 \(shown) 누르기"
        }
    }

    static func numbered(_ lines: [String]) -> [String] { lines.enumerated().map { "\($0.offset + 1). \($0.element)" } }

    // MARK: - The save card

    /// The card before a procedure is saved: every step, what varies, what was left out, and that its sending or
    /// deleting steps still ask every time.
    static func saveCard(_ procedure: ArisTeachProcedure, replacing: Bool, leftOut: [ArisTeachGeneralise.LeftOut] = [], english: Bool) -> Card {
        let lines = numbered(procedure.steps.map { step($0, in: procedure, english: english) })
        var tail: [String] = []
        if !procedure.parameters.isEmpty {
            let labels = procedure.parameters.map { label($0.label, english: english) }.joined(separator: ", ")
            tail.append(english ? "Changes each time: \(labels) (say it when you ask, e.g. “\(procedure.name), \(label(procedure.parameters[0].label, english: true)) …”)"
                                : "바뀌는 값: \(labels) (부를 때 말하면 바꿔서 해요. 예: “\(procedure.name) 해 줘, \(procedure.parameters[0].label)은 …”)")
        }
        if procedure.skipped > 0 {
            tail.append(english ? "Left out: \(procedure.skipped) password or secret field\(procedure.skipped == 1 ? "" : "s") (never recorded)."
                                : "비밀번호·보안 칸 \(procedure.skipped)곳은 기록하지 않았어요.")
        }
        // What he showed that no step does again (deleting, a field with no name): said before he allows it.
        tail += leftOutLines(leftOut, pastes: procedure.steps.contains { $0.action == .menu && ArisTeachRecorder.pastes(menu: $0.menu ?? [], keys: $0.keys) }, english: english)
        tail.append(english ? "Steps that send, delete or pay still ask every time." : "보내기·지우기·결제 같은 단계는 할 때마다 다시 물어봐요.")
        if replacing { tail.append(english ? "This replaces the one with the same name." : "같은 이름으로 배운 것을 이걸로 바꿔요.") }
        let title = english ? "Learn “\(procedure.name)”? (\(procedure.steps.count) steps)" : "‘\(procedure.name)’ 배울까요? (\(procedure.steps.count)단계)"
        let shown = lines.count > shownSteps ? Array(lines.prefix(shownSteps)) + [english ? "… and \(lines.count - shownSteps) more" : "… 외 \(lines.count - shownSteps)단계"] : lines
        let detail = (shown + [""] + tail).joined(separator: "\n")
        let full = lines.count > shownSteps ? (lines + [""] + tail).joined(separator: "\n") : nil
        return Card(title: title, detail: detail, full: full)
    }

    static func saved(_ procedure: ArisTeachProcedure, english: Bool) -> String {
        english ? "Learned “\(procedure.name)”. Say “\(procedure.name)” and I'll do it."
                : "‘\(procedure.name)’ 배웠어요. 이제 “\(procedure.name) 해 줘”라고 하면 해요."
    }

    static func notSaved(unanswered: Bool, english: Bool) -> String {
        if unanswered { return english ? "No answer, so I didn't save it." : "답이 없어서 저장하지 않았어요." }
        return english ? "OK, I didn't save it." : "알겠어요, 저장하지 않았어요."
    }

    static func saveFailed(english: Bool) -> String { english ? "I couldn't save it. Nothing changed." : "저장하지 못했어요. 바뀐 건 없어요." }

    // MARK: - Starting and stopping

    static func started(_ name: String, english: Bool) -> String {
        english ? "Watching. Show me “\(name)” now, then say “done”. Passwords are never recorded."
                : "보고 있을게요. 이제 ‘\(name)’ 하는 걸 보여 주시고, 끝나면 “다 했어”라고 하세요. 비밀번호는 기록하지 않아요."
    }

    static func needsName(english: Bool) -> String {
        english ? "What should I call it? Say, for example, “watch me, call it morning setup”."
                : "뭐라고 부를까요? 예를 들어 “지금부터 하는 거 출근 준비라고 해”처럼 말해 주세요."
    }

    static func alreadyWatching(_ name: String, english: Bool) -> String {
        english ? "I'm already watching “\(name)”. Say “done” when you've shown it, or “cancel the lesson”."
                : "지금 ‘\(name)’ 보는 중이에요. 다 보여 주셨으면 “다 했어”, 그만두려면 “배우기 취소”라고 하세요."
    }

    static func notWatching(english: Bool) -> String {
        english ? "I wasn't watching anything." : "지금 보고 있던 건 없어요."
    }

    static func cancelled(_ name: String, english: Bool) -> String {
        english ? "Stopped watching. Nothing about “\(name)” was kept." : "그만 볼게요. ‘\(name)’ 기록은 남기지 않았어요."
    }

    static func nothingToLearn(_ name: String, english: Bool) -> String {
        english ? "I didn't see anything I can do again for “\(name)”, so nothing was saved. Show it in an app and say “done”."
                : "‘\(name)’로 다시 할 수 있는 동작을 보지 못해서 저장하지 않았어요. 앱에서 보여 주시고 “다 했어”라고 해 주세요."
    }

    /// Nothing to learn, and what he showed was deleting text (eighth VM run, item 7: a lesson of Delete alone got "I
    /// didn't see anything I can do again", as if nothing had been seen): said plainly, that deleting on its own is
    /// not something Aris can learn yet.
    static func onlyDeleted(_ name: String, english: Bool) -> String {
        english ? "I saw you delete text for “\(name)”, but deleting on its own isn't something I can learn yet, so nothing was saved."
                : "‘\(name)’에서 글을 지우신 건 봤어요. 그런데 지우기만 하는 건 아직 배울 수 없어서 저장하지 않았어요."
    }

    /// The reply when a lesson holds nothing that can be done again.
    static func nothingSaved(_ name: String, deletedText: Bool, english: Bool) -> String {
        deletedText ? onlyDeleted(name, english: english) : nothingToLearn(name, english: english)
    }

    static func tooLong(_ count: Int, english: Bool) -> String {
        english ? "That was \(count) steps, more than I can keep (\(ArisTeachGeneralise.mostSteps)). Show a shorter version."
                : "\(count)단계라 한 번에 배울 수 있는 것(\(ArisTeachGeneralise.mostSteps)단계)보다 길어요. 조금 나눠서 보여 주세요."
    }

    static func expired(_ name: String, english: Bool) -> String {
        english ? "I stopped watching “\(name)”: it went on too long." : "‘\(name)’ 보는 걸 멈췄어요: 너무 오래 걸렸어요."
    }

    static func busyWatching(_ name: String, english: Bool) -> String {
        english ? "I'm watching “\(name)” right now, so I won't act in apps. Say “done” to finish, or “cancel the lesson”."
                : "지금 ‘\(name)’ 보는 중이라 다른 일은 하지 않아요. 끝나면 “다 했어”, 그만두려면 “배우기 취소”라고 하세요."
    }

    static func cannotWatch(english: Bool) -> String {
        english ? "I can't watch right now: Aris needs Accessibility (System Settings › Privacy & Security › Accessibility)."
                : "지금은 볼 수 없어요. 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 Aris를 켜 주세요."
    }

    static func nameTaken(_ name: String, english: Bool) -> String {
        english ? "There's already a routine called “\(name)”. Pick another name." : "‘\(name)’이라는 루틴이 이미 있어요. 다른 이름으로 해 주세요."
    }

    // MARK: - The list, rename, delete

    static func list(_ procedures: [ArisTeachProcedure], english: Bool) -> String {
        guard !procedures.isEmpty else {
            return english ? "You haven't shown me anything yet. Say “watch me, call it …” to start."
                           : "아직 배운 게 없어요. “지금부터 하는 거 …라고 해”라고 하면 배우기 시작해요."
        }
        let rows = procedures.map { procedure -> String in
            let apps = procedure.apps.joined(separator: ", ")
            return english ? "• \(procedure.name): \(procedure.steps.count) steps in \(apps)" : "• \(procedure.name): \(apps)에서 \(procedure.steps.count)단계"
        }
        return ((english ? ["What you've shown me:"] : ["배운 것:"]) + rows).joined(separator: "\n")
    }

    static func show(_ procedure: ArisTeachProcedure, english: Bool) -> String {
        let lines = numbered(procedure.steps.map { step($0, in: procedure, english: english) })
        return ([english ? "“\(procedure.name)”:" : "‘\(procedure.name)’:"] + lines).joined(separator: "\n")
    }

    static func renameCard(_ procedure: ArisTeachProcedure, to name: String, english: Bool) -> Card {
        Card(title: english ? "Rename “\(procedure.name)”?" : "‘\(procedure.name)’ 이름 바꾸기",
             detail: english ? "“\(procedure.name)” → “\(name)”" : "‘\(procedure.name)’ → ‘\(name)’", full: nil)
    }

    static func renamed(_ procedure: ArisTeachProcedure, english: Bool) -> String {
        english ? "Renamed. Say “\(procedure.name)” from now on." : "이름을 바꿨어요. 이제 “\(procedure.name) 해 줘”라고 하세요."
    }

    static func deleteCard(_ procedure: ArisTeachProcedure, english: Bool) -> Card {
        let lines = numbered(procedure.steps.map { step($0, in: procedure, english: english) })
        let shown = lines.count > shownSteps ? Array(lines.prefix(shownSteps)) + ["…"] : lines
        return Card(title: english ? "Forget “\(procedure.name)”?" : "‘\(procedure.name)’ 지울까요?", detail: shown.joined(separator: "\n"), full: nil)
    }

    static func deleted(_ procedure: ArisTeachProcedure, english: Bool) -> String {
        english ? "Forgot “\(procedure.name)”." : "‘\(procedure.name)’ 지웠어요."
    }

    static func left(unanswered: Bool, english: Bool) -> String {
        if unanswered { return english ? "No answer, so I left it as it was." : "답이 없어서 그대로 뒀어요." }
        return english ? "OK, I left it as it was." : "알겠어요, 그대로 뒀어요."
    }

    // MARK: - A run

    /// The question before a run whose words gave no value for what it types: one short line, and each value as a field
    /// holding the one he typed when he showed it (`fields`: the field's key, its parameter's label, and that value).
    static func valuesCard(_ procedure: ArisTeachProcedure, missing: [ArisTeachParameter], last: [String: String] = [:], english: Bool)
        -> (card: Card, fields: [(key: String, value: String)]) {
        let labels = missing.map { label($0.label, english: english) }
        let title: String
        if labels.count == 1 {
            title = english ? "“\(procedure.name)”: what goes in \(labels[0])?" : "‘\(procedure.name)’: \(labels[0])에 뭐라고 넣을까요?"
        } else {
            title = english ? "“\(procedure.name)”: what goes in \(labels.joined(separator: ", "))?" : "‘\(procedure.name)’: \(labels.joined(separator: ", "))에 뭐라고 넣을까요?"
        }
        var detail = suggestion(missing, last: last, english: english)
        // A value whose step begins a line: said before it runs (the field holds only the value).
        let asked = Set(missing.map(\.key))
        if procedure.steps.indices.contains(where: { procedure.steps[$0].parameter.map(asked.contains) == true && procedure.putsLineBreak(at: $0) }) {
            detail += english ? " It goes on a new line (\(lineBreak))." : " 새 줄(\(lineBreak))에 넣어요."
        }
        let fields = emptyFields(missing, english: english)
        // An editable card draws the lines above its fields' own "label: value" lines as its note (ArisCardEdit.note),
        // so the text ends with them (seventh VM run, item 1: without them the note, new line and all, was never drawn).
        detail += "\n" + fields.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        return (Card(title: title, detail: detail, full: nil), fields)
    }

    /// A value asked on a card comes up empty (eleventh VM run, T2: the field held last time's value, the yes typed it,
    /// and the owner had said another): what goes in is what he writes or says there. Last time's value is only a
    /// suggestion, said as that above the fields, and never typed unless he puts it in the field himself (the card's
    /// yes waits until every field holds a value: ArisCardEdit.allAccepted).
    static func emptyFields(_ missing: [ArisTeachParameter], english: Bool) -> [(key: String, value: String)] {
        missing.map { (key: label($0.label, english: english), value: "") }
    }

    /// The note above a card's empty value fields: what to do, and last time's value marked as a suggestion: the value
    /// the last run used (`last`, by key; twelfth VM run: the card offered the taught example "Added line" after runs
    /// with "우유"), else, never run since he showed it, the value he showed then.
    static func suggestion(_ missing: [ArisTeachParameter], last: [String: String] = [:], english: Bool) -> String {
        var lines = [english ? "Write what goes in below (or say it)." : "넣을 글을 아래 칸에 적거나 말해 주세요."]
        for parameter in missing {
            let used = last[parameter.key].flatMap { $0.isEmpty ? nil : $0 } ?? parameter.example
            guard !used.isEmpty else { continue }
            let value = quoted(fieldValue(used))
            let name = label(parameter.label, english: english)
            lines.append(english ? "Suggestion, last time's \(name): \(value) (not used unless you write it in)."
                                 : "제안: 지난번 \(name) \(value) (칸에 적어야 들어가요).")
        }
        return lines.joined(separator: " ")
    }

    /// The line-break mark a card shows in place of a line break (`quoted`), in a field too (fifth VM run, M3: the
    /// values card showed a blank line where the lesson card shows "↵").
    static let lineBreak = "↵"

    /// A value as a card's field holds it: each line break as ↵.
    static func fieldValue(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n", with: lineBreak)
    }

    /// What a field's text means: each ↵ the line break it stands for.
    static func fromField(_ text: String) -> String { text.replacingOccurrences(of: lineBreak, with: "\n") }

    /// Said when he said no to that question (or didn't answer): nothing ran.
    static func notRun(_ procedure: ArisTeachProcedure, unanswered: Bool, english: Bool) -> String {
        if unanswered { return english ? "No answer, so I didn't do “\(procedure.name)”." : "답이 없어서 ‘\(procedure.name)’ 하지 않았어요." }
        return english ? "OK, I didn't do “\(procedure.name)”." : "알겠어요, ‘\(procedure.name)’ 하지 않았어요."
    }

    /// The card when a step that ran didn't work and steps are left (fifth VM run, D7): which step, why, how many are
    /// left and which, and that each of them is still checked. Its buttons are 계속 and 멈추기 (Continue, Stop).
    static func goOnCard(_ procedure: ArisTeachProcedure, failedAt index: Int, why: String, english: Bool) -> Card {
        let line = index < procedure.steps.count ? step(procedure.steps[index], in: procedure, english: english) : ""
        let rest = numbered(procedure.steps.map { step($0, in: procedure, english: english) }).dropFirst(index + 1)
        let reason = Self.reason(why, english: english) ?? (english ? "the app didn't do it" : "앱에서 되지 않았어요")
        let left = rest.count
        let title = english ? "Step \(index + 1) didn't work. Go on with the \(left) step\(left == 1 ? "" : "s") left?"
                            : "\(index + 1)단계가 안 됐어요. 남은 \(left)단계를 계속할까요?"
        var head = english ? ["Didn't work: \(index + 1). \(line)", "Why: \(reason)"] : ["안 된 단계: \(index + 1). \(line)", "이유: \(reason)"]
        // A later step in the same app may stand on it (the window it opens, the selection it makes): said, not hidden.
        if !ArisTeachReplay.canGoOnWithout(index, steps: procedure.steps) {
            head.append(english ? "The steps after it may need it, so they may not work either." : "다음 단계가 이 단계에 기대고 있으면 그 단계도 안 될 수 있어요.")
        }
        head += english ? ["", "Left to do:"] : ["", "남은 단계:"]
        let tail = english ? ["", "Each step left is checked again, and steps that send, delete or pay still ask."]
                           : ["", "남은 단계도 하나씩 다시 확인하고, 보내기·지우기·결제 같은 단계는 다시 물어봐요."]
        return Card(title: title, detail: (head + rest + tail).joined(separator: "\n"), full: nil)
    }

    /// The go-on card's buttons: 계속 / 멈추기 (Continue / Stop).
    static func goOnAllow(english: Bool) -> String { english ? "Continue" : "계속" }

    /// Said before the go-on card, as its own sentence: which step didn't work and why. In Korean the step's own line
    /// is in double marks: it holds single ones itself (eighth VM run, item 6: "2단계 ‘TextEdit에서 메뉴 ‘Format › Wrap to
    /// Page’ 누르기’가 안 됐어요").
    static func failedLine(_ procedure: ArisTeachProcedure, at index: Int, why: String, english: Bool) -> String {
        let line = index < procedure.steps.count ? step(procedure.steps[index], in: procedure, english: english) : ""
        let reason = Self.reason(why, english: english).map { ": " + $0 } ?? ""
        return english ? "Step \(index + 1) didn't work (\(line))\(reason)." : "\(index + 1)단계 “\(line)”가 안 됐어요\(reason)."
    }

    /// A replay step's card (fifth VM run, D2: "바꾸기 · TextEdit" over "Change TextEdit $ =File › New [cmd+n]"): the
    /// step as the lesson says it, with this run's values, in the UI's language; titled by the lesson and the step.
    /// `ownerGave`: the values the owner gave for this run (their words, the values card); `arguments`: the key arguments
    /// of the call the step was made into.
    static func stepCard(_ procedure: ArisTeachProcedure, at index: Int, values: [String: String], ownerGave: Set<String> = [],
                         arguments: [ArisKeyArgument] = [], english: Bool) -> ArisAskDescription {
        let count = procedure.steps.count
        let taught = procedure.steps[index]
        let line = step(taught, in: procedure, values: values, english: english)
        let title = english ? "“\(procedure.name)”, step \(index + 1) of \(count)" : "‘\(procedure.name)’ \(index + 1)/\(count)단계"
        // Said short: the whole step is on the card (ArisTeachRunCard).
        let spoken = stepSpoken(procedure, at: index, english: english)
        let made = origin(procedure, step: taught, values: values, ownerGave: ownerGave, english: english)
        var described = ArisAskDescription(title: title, line: line, spoken: spoken, origin: made.origin, originErases: made.erases, arguments: arguments)
        // Typing that turns out to go over a selection: its card's question says the text is erased.
        if taught.action == .type { described.spokenErases = erasesSpoken(procedure, at: index, english: english) }
        return described
    }

    /// Where a replay's step comes from, said truthfully (seventh VM run, item 6): the owner's saved steps, the values he
    /// gave for this run; a value recorded when he showed it is said to be one read from the app then; and what a
    /// replace erases (shown on the card) is said to be read from the app just now.
    static func origin(_ procedure: ArisTeachProcedure, step: ArisTeachStep, values: [String: String], ownerGave: Set<String>,
                       english: Bool) -> (origin: String, erases: String?) {
        var origin = english ? "From your saved steps “\(procedure.name)”." : "저장한 단계 ‘\(procedure.name)’ 그대로예요."
        if step.action == .type, step.carriesRecordedValue(ownerGave: ownerGave), let text = step.typedText(values: values), !text.isEmpty {
            let value = quoted(text)
            // A value that looked typed by them when he showed it is never said as read from the app (eleventh VM run,
            // item 5: H1's "hello there" was called "TextEdit에서 읽은 값"); the recorder's mark is a hint only, so it is
            // said as last time's value. It is still not this turn's words: its step asks.
            let typedByHim = step.parameter.flatMap { key in procedure.parameters.first { $0.key == key } }?.fromApp == false
                || (step.parameter == nil && step.fromApp == false)
            if typedByHim {
                origin += english ? " The text \(value) is last time's, from when you showed it, not something you said now."
                                  : " 넣는 글(\(value))은 보여 주실 때의 지난번 값이에요. 이번에 말씀하신 값은 아니에요."
            } else {
                origin += english ? " The text \(value) is what was read from \(step.app) when you showed it."
                                  : " 넣는 글(\(value))은 보여 주실 때 \(step.app)에서 읽은 값이에요."
            }
        }
        let erases = step.replaces ? (english ? "The text it erases was read from \(step.app) just now." : "지워질 글은 방금 \(step.app)에서 읽었어요.") : nil
        return (origin, erases)
    }

    static func running(_ procedure: ArisTeachProcedure, english: Bool) -> String {
        english ? "Doing “\(procedure.name)”" : "‘\(procedure.name)’ 하는 중"
    }

    /// The run's one answer at the end.
    static func account(_ procedure: ArisTeachProcedure, outcome: ArisTeachReplay.Outcome, english: Bool) -> String {
        switch outcome {
        case .done(let steps):
            return english ? "Done: “\(procedure.name)” (\(steps) steps)." : "‘\(procedure.name)’ 다 했어요. (\(steps)단계)"
        case .partly(let done, let skipped):
            let left = skipped.map { index -> String in
                let line = index < procedure.steps.count ? step(procedure.steps[index], in: procedure, english: english) : ""
                return english ? "step \(index + 1) (\(line))" : "\(index + 1)단계 “\(line)”"
            }.joined(separator: ", ")
            // How many of its steps ran, and which was skipped (eighth VM run, item 6: "Done: “랩 메모” (2 steps),
            // without step 2 …" read as if the lesson had two steps and one more).
            let total = procedure.steps.count
            return english ? "Did “\(procedure.name)”: \(done) of its \(total) steps ran. Skipped \(left), which didn't work."
                           : "‘\(procedure.name)’ \(total)단계 중 \(done)단계를 했어요. 안 된 \(left)는 건너뛰었어요."
        case .stopped(let index, let end, let done):
            let line = index < procedure.steps.count ? step(procedure.steps[index], in: procedure, english: english) : ""
            let did = done == 0 ? "" : english ? " (\(done) step\(done == 1 ? "" : "s") done before it)" : " (앞의 \(done)단계는 했어요)"
            switch end {
            case .declined:
                return english ? "Stopped at step \(index + 1), \(line): you said no\(did)." : "\(index + 1)단계 “\(line)”에서 멈췄어요: 하지 말라고 하셨어요\(did)."
            case .unanswered:
                // A card nobody answered is not his no (ninth VM run, item 3: "you said no" after two minutes of silence).
                return english ? "Stopped at step \(index + 1), \(line): there was no answer, so I didn't do it\(did)."
                               : "\(index + 1)단계 “\(line)”에서 멈췄어요: 답이 없어서 하지 않았어요\(did)."
            case .refused(let why):
                let reason = Self.reason(why, english: english).map { ": " + $0 } ?? ""
                return english ? "Stopped at step \(index + 1), \(line)\(reason)\(did)." : "\(index + 1)단계 “\(line)”에서 멈췄어요\(reason)\(did)."
            case .failed(let why):
                let reason = Self.reason(why, english: english).map { ": " + $0 } ?? ""
                return english ? "Step \(index + 1) didn't work (\(line))\(reason)\(did). If the app changed, show me again and I'll learn it anew."
                               : "\(index + 1)단계 “\(line)”가 안 됐어요\(reason)\(did). 앱이 바뀌었으면 다시 보여 주세요. 새로 배울게요."
            case .stale:
                return english ? "Stopped: a newer request took over\(did)." : "새 요청이 들어와서 멈췄어요\(did)."
            case .unmade:
                return english ? "Step \(index + 1) has no value to use (\(line)), so I stopped\(did)." : "\(index + 1)단계 “\(line)”에 넣을 값이 없어서 멈췄어요\(did)."
            }
        }
    }
}
