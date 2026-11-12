//
//  ArisDesktopCopy.swift
//  aris-agent
//
//  Computer use's words for the user in English (audit desk-11: every card and status line was Korean only, on a Mac and a
//  request that were English). One switch decides for a whole call: the turn's own request, Korean when their words have
//  Hangul or there are none (a schedule), English otherwise (ArisScheduleCard.isEnglish, as the schedule card does).
//  The Korean lines stay where they are said (ArisDesktopCard, the engine, the controller); this file holds the English
//  beside them: the role, key and action words, the small consent cards, the notch's status lines, and what a brain is
//  told to say. A card is one language through and through, never half of each. Pure.
//

import CoreGraphics
import Foundation

enum ArisDesktopCopy {
    /// The call's cards and status lines are English: the user's request has words and none of them Korean.
    static func isEnglish(_ request: String) -> Bool { ArisScheduleCard.isEnglish(request) }

    // MARK: - The card's words

    /// An Accessibility role as an English card says it (ArisDesktopCard.roleWord has the Korean).
    static let roles: [String: String] = [
        "textfield": "text field", "textarea": "text field", "searchfield": "search field", "securetextfield": "password field", "combobox": "text field",
        "button": "button", "popupbutton": "pop-up button", "menubutton": "menu button", "checkbox": "checkbox", "radiobutton": "radio button",
        "link": "link", "menuitem": "menu item", "menu": "menu", "tab": "tab", "tabgroup": "tab", "slider": "slider",
        "statictext": "text", "text": "text", "image": "image", "row": "row", "cell": "cell", "table": "table", "list": "list",
        "outline": "list", "scrollarea": "scroll area", "window": "window", "group": "group", "toolbar": "toolbar", "webarea": "web page",
        "heading": "heading", "disclosuretriangle": "disclosure button",
    ]
    static let anyRole = "item"

    /// What the usual keys do, in plain words (ArisDesktopCard.keyWords has the Korean).
    static let keyMeanings = ["delete": "deletes what is selected", "backspace": "deletes what is selected", "cmd+delete": "deletes what is selected (to the Trash)",
                              "cmd+backspace": "deletes what is selected (to the Trash)", "forwarddelete": "deletes what is selected", "return": "confirm (Enter)",
                              "enter": "confirm (Enter)", "escape": "cancel", "esc": "cancel", "tab": "next field", "space": "space", "cmd+s": "save",
                              "cmd+shift+s": "save as", "cmd+z": "undo", "cmd+a": "select all", "cmd+c": "copy", "cmd+v": "paste", "cmd+x": "cut",
                              "cmd+w": "close window", "cmd+q": "quit app", "cmd+n": "new", "cmd+p": "print", "cmd+return": "send or confirm"]

    /// What a step is, as a card's title and a batch's lines say it (ArisDesktopCard.verbLabel has the Korean).
    static func verb(_ verb: ArisDesktopVerb) -> String {
        switch verb {
        case .click: return "Click"
        case .type: return "Type"
        case .setValue: return "Set a value"
        case .press: return "Press keys"
        case .scroll: return "Scroll"
        case .drag: return "Drag and drop"
        case .menuClick: return "Choose a menu item"
        case .dialogClick: return "Press a dialog button"
        case .dialogInput: return "Type in a dialog"
        case .dialogFile: return "Choose a file"
        case .window: return "Manage a window"
        case .app: return "Manage an app"
        case .clickAt: return "Look and click"
        case .see, .menuList, .dialogList, .windowList, .dockList: return "Look"
        case .batch: return "Do several steps"
        }
    }

    /// The card's first line: the window it is about.
    static func windowLine(_ title: String, english: Bool) -> String {
        let shown = ArisDesktopCard.shown(ArisWindowTitleMatch.safeTitle(title))
        return english ? "Window: “\(shown)”" : "창: “\(shown)”"
    }

    // MARK: - The small consent cards (a window brought forward, the real pointer, a spot, a settings screen)

    /// Their titles in English, by the Korean title the call site passes (ArisDesktopSession.consent).
    static let consentTitles: [String: String] = [
        ArisDesktopSession.foregroundCard: "Bring it to the front to do this",
        ArisDesktopSession.pointerCard: "Click with the real pointer?",
        ArisDesktopSession.spotCard: "Click this spot?",
        ArisDesktopSession.settingsCard: "Do it on this settings screen?",
    ]

    static func consentTitle(_ korean: String, english: Bool) -> String { english ? consentTitles[korean] ?? korean : korean }

    /// System Settings on a screen Aris can't tell for sure.
    static func settingsDetail(title: String, english: Bool) -> String {
        windowLine(title, english: english) + "\n" + (english ? "Aris can't tell for sure which settings screen this is, so it asks" : "어떤 설정 화면인지 확실히 알 수 없어서 물어봐요")
    }

    /// Keys the background can't deliver: the window comes forward for them.
    static func forwardKeysDetail(title: String, keys: [String], english: Bool) -> String {
        let pressed = ArisDesktopCard.shown(keys.joined(separator: " "))
        return windowLine(title, english: english) + "\n" + (english
            ? "Keys: \(pressed)\nThis can't be done in the background, so the window is brought to the front for the keys; then the app you were in comes back"
            : "키: \(pressed)\n백그라운드로는 안 돼서 창을 앞으로 가져와 누르고, 끝나면 원래 앱으로 돌아가요")
    }

    /// Text that didn't land in the background: the window comes forward and it is typed for real.
    static func forwardTypeDetail(title: String, text: String, english: Bool) -> String {
        windowLine(title, english: english) + "\n" + (english
            ? "Text to type:\n" + ArisDesktopCard.shown(text) + "\nTyping in the background didn't work, so the window is brought to the front and the text is typed for real"
            : "입력하는 글:\n" + ArisDesktopCard.shown(text) + "\n백그라운드 입력이 안 돼서 창을 앞으로 가져와 실제로 입력해요")
    }

    /// A click the background can't make: the real pointer.
    static func pointerDetail(title: String, label: String, english: Bool) -> String {
        let named = ArisDesktopCard.shown(label)
        return windowLine(title, english: english) + "\n" + (english
            ? "Target: “\(named)”\nIt couldn't be clicked in the background, so the real pointer clicks that spot (and goes back after)"
            : "대상: “\(named)”\n백그라운드로 안 눌러져서 실제 마우스로 그 자리를 눌러요 (끝나면 제자리로)")
    }

    /// A spot a vision brain picked in the window's picture.
    static func spotDetail(title: String, wanted: String, label: String, role: String, point: CGPoint?, english: Bool) -> String {
        let name = ArisDesktopCard.shown(String(label.prefix(80))), kind = role.isEmpty ? "" : ArisDesktopCard.shown(role) + " "
        var lines = [windowLine(title, english: english), (english ? "Looked for: " : "찾던 것: ") + ArisDesktopCard.shown(wanted)]
        if english {
            lines.append(label.isEmpty ? "Picked spot: a place with no name" : "Picked spot: \(kind)“\(name)”")
            if let point { lines.append("Position in the window: \(Int(point.x.rounded())), \(Int(point.y.rounded()))") }
        } else {
            lines.append(label.isEmpty ? "고른 자리: 이름 없는 곳" : "고른 자리: \(kind)“\(name)”")
            if let point { lines.append("창 안 위치: \(Int(point.x.rounded())), \(Int(point.y.rounded()))") }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - The notch's status lines

    static func working(_ verb: ArisDesktopVerb, app: String, english: Bool) -> String {
        switch verb.kind {
        case .read: return english ? "Looking at \(app)…" : "\(app) 보는 중…"
        case .action:
            if english { return verb.takesText ? "Typing in \(app)…" : "Working in \(app)…" }
            return verb.takesText ? "\(app)에서 입력 중…" : "\(app)에서 누르는 중…"
        }
    }

    static func needsAccessibility(english: Bool, osMajor: Int = ArisFix.Pane.osMajor) -> String {
        let list = ArisFix.Pane.accessibility.title(english: english, osMajor: osMajor)
        return english ? "Turn on \(list) for Aris" : "Aris에 \(list) 권한을 켜 주세요"
    }
    static func needsScreenRecording(english: Bool) -> String { english ? "Turn on Screen Recording for Aris" : "Aris에 화면 기록 권한을 켜 주세요" }
    static func installing(english: Bool) -> String { english ? "Installing the computer-use tool…" : "컴퓨터 사용 도구 설치 중…" }

    // MARK: - What a brain is told to say (English: the Korean lines are ArisDesktopEngine's)

    /// The lists are named as this macOS shows them (ArisFix.Pane.title: macOS 27 renamed Accessibility).
    static var accessLine: String {
        let list = ArisFix.Pane.accessibility.title(english: true)
        return "Aris doesn't have \(list) yet, so Aris can't see or press inside apps. System Settings is open at Privacy & Security › \(list). " +
            "Tell the user, in their language, in one sentence: \"To see and press inside apps, Aris needs \(list). Turn Aris on in the System Settings " +
            "window that just opened, under Privacy & Security › \(list) (only once).\""
    }
    static var screenLine: String {
        "Looking at the window's pixels needs Screen Recording for Aris (only for --ocr and click-at; everything else works without it). " +
            "System Settings is open at it. Tell the user, in their language, in one sentence: \"To look at the screen and click, Aris needs Screen Recording. " +
            "Turn Aris on in the System Settings window that just opened, under Privacy & Security › \(ArisFix.Pane.screen.title(english: true)).\""
    }
    static let blindLine = "Refused: Aris can read neither this app's message field nor its chat, so it won't type there blind. Tell the user, in their language, in one " +
        "sentence: \"This app's message field and its conversation can't be read, so I didn't type there for you. Please type it yourself.\""
}
