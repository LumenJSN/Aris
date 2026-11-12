//
//  ArisDesktopGate.swift
//  aris-agent
//
//  The one gate in front of `aris-tools desktop`, the same for every brain (ArisDesktopEngine calls it, whichever brain
//  asked). Reads (see, menu list, dialog list, window list) run at once on a clean turn and go to the read judge on a
//  careful one (dock list always); what they bring back is the app's own words, outside text for everything but computer
//  use in that app. Actions (click, type, press, menu click…) show the user a card unless they said yes to that app in this
//  conversation while no other outside text had come in (ArisComputerUseLedger); a menu item or button that deletes,
//  sends or pays always shows it. A mail, chat or call app always shows the card, with the exact text a send would carry
//  (read for the card) or a paste would put in (the clipboard's, read for the card and held to it), and never takes a
//  multi-key send or a line break. Calendar and Reminders show the card every time, and never delete, cut or send
//  through their windows (that is the event and reminder tools' work). A file panel always shows the card, with the
//  document and the place. Never: password stores, Keychain, terminals and code runners, sign-in prompts, the
//  installer, Aris and Peekaboo (ArisRiskPolicy.computerUseIsNever), System Settings' permission, account and profile
//  panes (the rest of it is an ordinary app), a password field, typing or screen reads while secure input is on, the
//  Apple menu, Recent Items, Services, an app's own Quit item (`desktop app quit` asks instead), logging out, and a
//  file panel aimed at a protected place; browsers go to Aside. Pure.
//

import Foundation

struct ArisDesktopContext: Equatable {
    /// The conversation's taint as computer use in this app sees it (its own window isn't outside text for it).
    var taintForApp: ArisTaint = .none
    /// The turn carries or follows the screen.
    var screen = false
    var handsFree = false
    /// A background job.
    var job = false
    /// agy's relay ran it.
    var relayed = false
    /// The home folder, for a file panel's places (I9).
    var home = NSHomeDirectory()
    /// In System Settings: the tier of the pane the action comes from (the look its ref came from, else the latest one).
    var settingsPane = ArisSettingsPane.unknown
    /// In Finder: the folder its window shows.
    var place = ArisShownPlace.notAFileBrowser
    /// The user's own words for the turn, and whether it is a critical one (sending, deleting, money): for a type of their
    /// words into a safe typing app (QA BUG-15).
    var request = ""
    var critical = false
    /// The app has several windows and the user's words name none of them: which one is meant is a question, so a type of their
    /// words never runs at once there (QA BUG-47 reopened); the card shows the window.
    var windowAmbiguous = false
    /// The user's own words name the app or one of its windows (a document): a file panel is driven only then (QA: the
    /// brain Saved-As an unrelated TextEdit document to answer "save the last answer").
    var userNamedApp = false
    /// His words point at the document he has in front ("이 문서 저장해 줘") and no other app is in front of this one:
    /// its file panel then goes to his card, which names the document (audit desk-8), instead of a refusal.
    var pointsAtFrontDocument = false
    /// The clipboard's text, read by the engine only for a paste in a messaging app (the user's card shows it, and the
    /// paste is held to it); nil: not read, or it holds no text.
    var clipboard: String? = nil

    /// His words say which document a file panel is for (the app or a window by name, or the one in front): otherwise
    /// the card says they didn't.
    var namesDocument: Bool { userNamedApp || pointsAtFrontDocument }

    /// A read is judged, never just run.
    var careful: Bool { taintForApp != .none || screen || handsFree || job || relayed }
}

/// The folder a file browser's window shows, for an action in it.
enum ArisShownPlace: Equatable {
    case notAFileBrowser
    /// Finder, but its window's folder couldn't be read: no yes is ever kept for it.
    case unreadable
    case path(String)

    static let finder = "com.apple.finder"
}

enum ArisDesktopDecision: Equatable {
    case run
    case judge
    /// The user's card; `remember`: their yes is kept for the app for this conversation.
    case ask(remember: Bool)
    case refuse(String)
}

enum ArisDesktopGate {
    static let neverRefusal = "Refused: Aris never works in this app (password stores, Keychain, terminals, code runners, system settings and sign-in prompts, Aris itself). Don't try it another way."
    static let secureRefusal = "Refused: a password field (secure input) is active, and Aris never types, clicks or reads the screen then. Ask the user to do it themselves."
    static let secureFieldRefusal = "Refused: that is a password field, and Aris never types into one. Ask the user to type it themselves."
    static let hiddenRefusal = "Refused: the text carries hidden or direction-changing characters."
    static let unknownRefusal = "Refused: that app isn't running (or more than one app has that name). Open it first with `desktop app launch \"<name>\"`."
    static let jobRefusal = "Refused: this would bring a window forward, and a background job never does (nobody may be watching). Say so in the report."
    static let lineRefusal = "Refused: in a messaging app the text is typed one line at a time (a line break there sends). Type one line, then `press return` (or shift+return) as its own step."
    static let pasteRefusal = "Refused: the user's card couldn't show what this paste would put into a messaging app (the clipboard holds no plain text, or this is a step " +
        "of a batch). Paste with its own `desktop press cmd+v` call, or type the text with `desktop type`."
    static let pasteAloneRefusal = "Refused: in a messaging app a paste is pressed alone, as its own step (`desktop press cmd+v`), so the user's card shows exactly what goes in."
    static let pasteLongRefusal = "Refused: the clipboard holds more text than the user's card can show for a paste into a messaging app. Tell the user it is too long to paste for them there."
    /// The most clipboard text a paste in a messaging app may carry (what one `desktop type` takes).
    static let maxPaste = 10_000
    static let multiSendRefusal = "Refused: in a messaging app a send (return) is pressed alone, as its own step, so the user's card shows exactly what goes."
    static let menuRefusal = "Refused: Aris never opens the Apple menu, Recent Items or Services, and never quits an app or logs out from a menu. " +
        "To quit an app, use `desktop app quit \"<App>\"`: the user is asked on a card."
    /// `desktop app quit`: never the system's own (quitting one logs the user out or takes the desktop away).
    static let systemApps: Set<String> = ["com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver", "com.apple.controlcenter",
                                          "com.apple.notificationcenterui", "com.apple.WindowManager", "com.apple.Spotlight"]
    static let quitSystemRefusal = "Refused: Aris never quits the system's own apps (Finder, the Dock, the login window, the menu bar)."
    static let settingsRefusal = "Refused: Aris never acts in System Settings' Privacy & Security, Users & Groups, passwords or profiles panes (permissions, accounts, device management). Ask the user to do it there."
    static let placeRefusal = "Refused: that file or folder is one Aris never picks in a file panel (its own folders, keys, startup files, secrets)."

    static func decide(_ request: ArisDesktopRequest, target: ArisDesktopTarget, context: ArisDesktopContext, remembered: Bool,
                       secureInput: Bool, element: ArisDesktopElement? = nil) -> ArisDesktopDecision {
        if target.never { return .refuse(neverRefusal) }
        // Quitting an app (desk-imp-3: it was flatly refused): always the user's card, never kept, a browser too (quitting one
        // is no website work); never one of the system's own, nor an app without a bundle id.
        if request.verb == .app, request.operation == "quit" {
            guard let bundle = target.bundle, !systemApps.contains(where: { $0.caseInsensitiveCompare(bundle) == .orderedSame }) else { return .refuse(quitSystemRefusal) }
            if ArisMCPPolicy.hidesCharacters(request.app ?? "") { return .refuse(hiddenRefusal) }
            return .ask(remember: false)
        }
        if target.browser { return .refuse(ArisRiskPolicy.browserRefusal + ": websites go to Aside, never desktop control of a browser.") }
        switch request.verb.kind {
        case .read:
            // A look at the pixels while a password field is up could read it (I6).
            if request.ocr || request.annotate, secureInput { return .refuse(secureRefusal) }
            // The Dock lists running and recent apps and files: always judged (M2).
            return context.careful || request.verb == .dockList ? .judge : .run
        case .action:
            // Secure input stops typing, keys and looks at the screen (click-at's screenshot), not a plain click on a ref.
            if secureInput, request.verb.takesText || [.press, .clickAt].contains(request.verb) { return .refuse(secureRefusal) }
            if request.verb.takesText, element?.isSecure == true { return .refuse(secureFieldRefusal) }
            if context.job, request.bringsForward { return .refuse(jobRefusal) }
            let words = [request.text, request.path, request.button, request.field, request.name, request.select, request.target].compactMap { $0 } + request.keys
            if words.contains(where: ArisMCPPolicy.hidesCharacters) { return .refuse(hiddenRefusal) }
            if request.verb == .menuClick, let path = request.path {
                if refusesMenu(path, app: target.name) { return .refuse(menuRefusal) }
                // One of the system's own apps: nothing that names quitting is ever clicked there.
                if isSystemApp(target), mentionsQuit(path) { return .refuse(quitSystemRefusal) }
            }
            // System Settings: never in its protected panes, nor into one (a row, a menu item, a looked-for spot).
            if target.settings {
                if context.settingsPane == .protected { return .refuse(settingsRefusal) }
                if [element?.label, element?.identifier].compactMap({ $0 }).contains(where: ArisSettingsPane.namesProtected)
                    || request.path.map(namesBlockedPanePath) == true || request.target.map(ArisSettingsPane.mentionsProtected) == true {
                    return .refuse(settingsRefusal)
                }
            }
            if request.verb == .dialogFile, blocksPlace(request, home: context.home) { return .refuse(placeRefusal) }
            // A file panel their words named no document for was refused (audit gate-19): it asks on his card, which says so
            // and where it saves; with no folder given the card couldn't say where, so the folder is asked for first.
            if request.verb == .dialogFile, !context.namesDocument, request.path == nil { return .refuse(dialogFolderRefusal) }
            // Calendar and Reminders: removing, cutting and sending are their own tools' work, event by event, never their
            // windows' (QA BUG-53: a delete driven through Calendar's window, with a browser in front). Anything else
            // there (a view, a list, a date) was refused too (audit gate-19) and now asks on the user's card, every time.
            if isCalendarApp(target) { return removesInCalendar(request, element: element) ? .refuse(calendarRefusal) : .ask(remember: false) }
            // Finder showing a protected place (Aris's folders, keys, startup files) is never worked in.
            if case .path(let shown) = context.place, ArisProtectedPlaces.blocks(shown, home: context.home) { return .refuse(placeRefusal) }
            if target.sending {
                if let text = request.text, ArisCommandPolicy.hasLineBreak(text) { return .refuse(lineRefusal) }
                // A paste was refused outright (audit gate-19): it asks (below, every time) when the user's card can show
                // the clipboard's text in full, and is pressed alone.
                if pastes(request) {
                    if request.verb == .press, request.keys.count > 1 { return .refuse(pasteAloneRefusal) }
                    guard let clipboard = context.clipboard, !clipboard.isEmpty else { return .refuse(pasteRefusal) }
                    if clipboard.count > maxPaste { return .refuse(pasteLongRefusal) }
                    if ArisMCPPolicy.hidesCharacters(clipboard) { return .refuse(hiddenRefusal) }
                }
                if request.verb == .press, request.keys.count > 1, request.keys.contains(where: isSendChord) { return .refuse(multiSendRefusal) }
            }
            // A screenshot and a guessed spot, or a file panel brought forward: always the user, never remembered.
            if request.verb == .clickAt || request.verb == .dialogFile { return .ask(remember: false) }
            // Mail, chat and calls: every action asks, with what it types or may send.
            if target.sending { return .ask(remember: false) }
            // A menu item or a dialog button that deletes, sends, pays or quits, or only has the letters of quitting in
            // its name ("발표 종료 후 보기"): always the card (I8).
            if let named = request.verb == .menuClick ? request.path : request.verb == .dialogClick ? request.button : nil,
               ArisRiskPolicy.mentionsRiskyStep(named) || mentionsQuit(named) { return .ask(remember: false) }
            // A pane not told for sure (another one, a sheet, unreadable rows): the card every time, never kept.
            if target.settings, context.settingsPane != .safe { return .ask(remember: false) }
            // Finder whose folder can't be read: the card every time, never kept.
            if context.place == .unreadable { return .ask(remember: false) }
            // The user's own words typed into an app that can neither run code nor send (aris-tools type's safeTypingApps), the
            // installed and signed one, on a clean turn: at once, exactly as `aris-tools type --app` runs (QA BUG-15).
            if request.verb == .type, !context.careful, !context.critical, !context.windowAmbiguous, target.known, target.appleSigned, !target.sending,
               ArisRiskPolicy.isSafeTypingApp(name: target.name, bundle: target.bundle),
               let text = request.text, ArisRiskPolicy.typesUsersWords(text, request: context.request) { return .run }
            if remembered, !context.handsFree { return .run }
            return .ask(remember: target.memoryKey != nil && context.taintForApp == .none && !context.handsFree)
        }
    }

    // MARK: - Sends (I1)

    /// Words for sending, as a menu item, a button or a vision target names it.
    private static let sendWords = ["send", "submit", "post", "reply", "forward", "보내", "전송", "게시", "발송", "답장", "전달", "送信", "发送", "返信"]

    static func mentionsSend(_ text: String) -> Bool {
        let folded = ArisRiskPolicy.folded(text)
        return sendWords.contains(where: folded.contains)
    }

    /// A chord that sends in a chat (return or enter, with any modifier).
    static func isSendChord(_ chord: String) -> Bool {
        let key = chord.lowercased().split(separator: "+").last.map(String.init) ?? ""
        return ["return", "enter", "kp_enter", "keypadenter"].contains(key)
    }

    /// Whether the action may send what the field holds: return pressed, a send menu item or button, a click on a send
    /// control, or a look-and-click aimed at one.
    static func isSend(_ request: ArisDesktopRequest, element: ArisDesktopElement?) -> Bool {
        switch request.verb {
        case .press: return request.keys.contains(where: isSendChord)
        case .menuClick: return request.path.map(mentionsSend) ?? false
        case .dialogClick: return request.button.map(mentionsSend) ?? false
        case .click: return element.map { mentionsSend($0.label) || mentionsSend($0.value ?? "") } ?? false
        case .clickAt: return request.target.map(mentionsSend) ?? false
        default: return false
        }
    }

    /// A paste. In a messaging app the card shows the clipboard's text, and the paste is held to it (`pasteHolds`).
    static func pastes(_ request: ArisDesktopRequest) -> Bool {
        switch request.verb {
        case .press:
            return request.keys.contains { chord in
                let parts = Set(chord.lowercased().split(separator: "+").map(String.init))
                return parts.contains("v") && !parts.isDisjoint(with: ["cmd", "command", "meta", "super"]) || parts.contains("insert")
            }
        case .menuClick:
            let item = ArisRiskPolicy.folded(request.path?.components(separatedBy: " > ").last ?? "")
            return ["paste", "붙여넣기", "ペースト", "粘贴"].contains(where: item.contains)
        default: return false
        }
    }

    /// What the clipboard holds when the keys are about to go is exactly what the user's card showed (`card` nil: no paste
    /// card was shown, so there is nothing to hold).
    static func pasteHolds(card: String?, now: String?) -> Bool {
        guard let card else { return true }
        return now.map { Array($0.unicodeScalars) == Array(card.unicodeScalars) } ?? false
    }

    /// A menu path with a blocked System Settings pane on it.
    static func namesBlockedPanePath(_ path: String) -> Bool {
        path.components(separatedBy: " > ").contains(where: ArisSettingsPane.namesProtected)
    }

    // MARK: - Menus (I8) and file panels (I9)

    private static let quitWords = ["quit", "종료"]
    private static let logOutWords = ["log out", "logout", "로그아웃"]

    /// The letters of quitting anywhere in a name ("Quit", "종료", but also "발표 종료 후 보기" or "Acquittal Mode").
    static func mentionsQuit(_ text: String) -> Bool {
        let folded = ArisRiskPolicy.folded(text)
        return quitWords.contains(where: folded.contains)
    }

    static func isSystemApp(_ target: ArisDesktopTarget) -> Bool {
        target.bundle.map { bundle in systemApps.contains { $0.caseInsensitiveCompare(bundle) == .orderedSame } } ?? false
    }

    /// The app's own Quit item, told by what it is and not by its letters (audit gate-19: "발표 종료 후 보기" and
    /// "Acquittal Mode" were refused with it): "Quit" or "종료" alone, "Quit <App>" or "<App> 종료" (the app as Aris
    /// named it, or as the path's own first menu, the app menu, names it), "Quit and Keep Windows" / "종료 및 윈도우
    /// 유지", and the force-quit forms. Case, spacing, full-width letters and a trailing "…" aside.
    static func quitsApp(_ path: String, app: String = "") -> Bool {
        let plain = { (text: String) -> String in
            ArisRiskPolicy.folded(text).replacingOccurrences(of: "…", with: " ").replacingOccurrences(of: "...", with: " ")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let parts = path.components(separatedBy: " > ").map(plain)
        guard let item = parts.last, !item.isEmpty else { return false }
        if ["quit", "종료", "force quit", "강제 종료"].contains(item) || ["quit and ", "종료 및 ", "종료하고 "].contains(where: item.hasPrefix) { return true }
        let names = Set([plain(app)] + (parts.count > 1 ? [parts[0]] : [])).filter { !$0.isEmpty }
        return names.contains { name in ["quit \(name)", "\(name) 종료", "force quit \(name)", "\(name) 강제 종료"].contains(item) }
    }

    /// The Apple menu, Recent Items and Services (anywhere on the path), logging out, or the app's own Quit item, which
    /// `desktop app quit` asks about on a card instead. (Restart and shut down are the Apple menu's, refused with it;
    /// "Restart Numbering" or "Shut Down Server" in an app are fine. Another item that merely has the letters of
    /// quitting in it is asked about on the card: `mentionsQuit`.)
    static func refusesMenu(_ path: String, app: String = "") -> Bool {
        let parts = path.components(separatedBy: " > ").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.contains(where: ArisDesktopPrivacy.recentMenus.contains) { return true }
        let item = ArisRiskPolicy.folded(parts.last ?? "")
        return logOutWords.contains(where: item.contains) || quitsApp(path, app: app)
    }

    /// A file panel's --path, and the --path with its --select or --name, as paths (links followed too).
    private static func places(_ request: ArisDesktopRequest, home: String) -> [String] {
        let folder = request.path.map { $0 == "~" ? home : $0.hasPrefix("~/") ? home + $0.dropFirst() : $0 }
        let leaves = [request.select, request.name].compactMap { $0 }
        // With no folder, a name is judged by itself (a key's or a token's file name).
        let paths = (folder.map { [$0] } ?? []) + leaves.map { (folder ?? "") + "/" + $0 }
        return paths.flatMap { [$0, URL(fileURLWithPath: $0).resolvingSymlinksInPath().path] }
    }

    /// One of them is a protected place (Aris's own folders, keys, startup files, computer use's runtime): refused.
    static func blocksPlace(_ request: ArisDesktopRequest, home: String) -> Bool {
        places(request, home: home).contains { ArisProtectedPlaces.blocks($0, home: home) }
    }

    /// One of them looks like a secret (a key's, a token's or a password's file, a private store): the user's card says so
    /// (it always asks), rather than a refusal (re-review 4).
    static func secretPlace(_ request: ArisDesktopRequest, home: String) -> Bool {
        places(request, home: home).contains { ArisRiskPolicy.isSecretPath($0, home: home) }
    }
}

/// The card for a desktop action: titled from the app Aris resolved, with the element as the snapshot showed it, the
/// exact text it types (control characters shown escaped), and in a sending app the last text typed there.
extension ArisDesktopGate {
    static let calendarApps: Set<String> = ["com.apple.iCal", "com.apple.reminders"]
    static let dialogFolderRefusal = "Not done: the user named neither this app nor one of its documents, so the card must say where the document in front would " +
        "be saved or opened: run it again with `--path <folder>`. (To save text the user asked for, Aris writes the file itself; a file panel saves the document in front.)"

    /// Calendar or Reminders, by bundle id, or by name when no bundle id was resolved.
    static func isCalendarApp(_ target: ArisDesktopTarget) -> Bool {
        if let bundle = target.bundle { return calendarApps.contains { $0.caseInsensitiveCompare(bundle) == .orderedSame } }
        return ArisRiskPolicy.calendarAppNames.contains(target.name.lowercased())
    }

    /// Words for cutting or clearing, which remove an event or a reminder as a delete does.
    private static let cutWords = ["cut", "오려두기", "잘라내기", "지움", "clear"]

    /// In Calendar or Reminders: a step that removes, cuts or sends. A deleting key or a cut in the keys (in any order
    /// or spelling: ArisDesktopBatch.normalized), or a control, menu item, dialog button or looked-for spot named for it
    /// (the risk gate's own words, and the cut words). These stay with `aris-tools event` and `aris-tools remind`.
    static func removesInCalendar(_ request: ArisDesktopRequest, element: ArisDesktopElement?) -> Bool {
        let removingKey = request.keys.contains { chord in
            let keys = ArisDesktopBatch.normalized(chord)
            return keys.contains("delete") || keys.contains("clear") || (keys.contains("cmd") && keys.contains("x")) || ArisRiskPolicy.mentionsRiskyStep(chord)
        }
        let named = [request.path, request.button, request.target, request.select, element?.label, element?.identifier].compactMap { $0 }
        return removingKey || named.contains { name in
            ArisRiskPolicy.mentionsRiskyStep(name) || cutWords.contains(where: ArisRiskPolicy.folded(name).contains)
        }
    }

    /// The user's words name the app (any of its names) or one of its windows' titles.
    static func namesApp(_ request: String, names: [String]) -> Bool {
        let heard = ArisWindowTitleMatch.normalized(request)
        return names.map(ArisWindowTitleMatch.normalized).contains { $0.count >= 2 && heard.contains($0) }
    }
    /// The user's words point at the document in front of them ("이 문서", "이거", "지금 열려 있는 파일", "this document", "save
    /// it"), and at nothing Aris said: "방금 답을 파일로 저장해 줘" is the answer, which Aris writes itself (the QA case the
    /// file panel's rule was made for). Pure.
    static func pointsAtDocument(_ request: String) -> Bool {
        let said = request.precomposedStringWithCanonicalMapping
        let answer = #"(?i)(답변|대답|답[을은이도만]|답\s|요약|방금\s*(한\s*)?(말|알려|얘기)|\b(answer|reply|response|summary|what you (just )?said)\b)"#
        guard said.range(of: answer, options: .regularExpression) == nil else { return false }
        let things = "(문서|파일|창|글|페이지|메모|그림|사진|이미지|표|시트|pdf)"
        let korean = "(?i)(이\\s*\(things)|(지금|현재)\\s*(이\\s*)?\(things)|(열려\\s*있는|열린|보고\\s*있는|앞에\\s*있는|작업\\s*중인)\\s*(이\\s*)?(\(things)|것|거)"
            + "|(?<![가-힣])이(거|것|걸|건)(를|을|는|은|도|만)?(?![가-힣]))"
        let english = #"(?i)\b(this|the (current|open|front|frontmost))\s+(document|doc|file|window|page|note|image|picture|sheet|pdf)\b|\bsave (this|it)\b"#
        return said.range(of: korean, options: .regularExpression) != nil || said.range(of: english, options: .regularExpression) != nil
    }
    static let calendarRefusal = "Nothing is deleted, cut or sent through Calendar's or Reminders' window: use `aris-tools event …` or `aris-tools remind …` " +
        "(by the event or reminder itself). Looking around there (a view, a list, a date) is fine, one desktop call at a time; each asks the user. Nothing was done."
}

enum ArisDesktopCard {
    /// An Accessibility role as the user reads it ("textField" → 입력칸), never the raw role (QA retest, the BUG-48 family).
    /// `english`: the call's cards are English (ArisDesktopCopy has those words); so for every function here.
    static func roleWord(_ role: String, english: Bool = false) -> String {
        let words: [String: String] = [
            "textfield": "입력칸", "textarea": "입력칸", "searchfield": "검색칸", "securetextfield": "암호 입력칸", "combobox": "입력칸",
            "button": "버튼", "popupbutton": "팝업 버튼", "menubutton": "메뉴 버튼", "checkbox": "체크박스", "radiobutton": "선택 버튼",
            "link": "링크", "menuitem": "메뉴 항목", "menu": "메뉴", "tab": "탭", "tabgroup": "탭", "slider": "슬라이더",
            "statictext": "글자", "text": "글자", "image": "그림", "row": "줄", "cell": "칸", "table": "표", "list": "목록",
            "outline": "목록", "scrollarea": "스크롤 영역", "window": "창", "group": "묶음", "toolbar": "도구 막대", "webarea": "웹 페이지",
            "heading": "제목", "disclosuretriangle": "펼치기 버튼",
        ]
        let key = role.lowercased().replacingOccurrences(of: "ax", with: "", options: .anchored)
        if english { return ArisDesktopCopy.roles[key] ?? ArisDesktopCopy.anyRole }
        return words[key] ?? "요소"
    }

    /// Keys as the card says them: the keys themselves, and what the usual ones do in plain words (QA BUG-53: a batch
    /// card's "press delete" didn't say it removes what is selected).
    static func keyWords(_ keys: [String], english: Bool = false) -> String {
        let meanings = ["delete": "선택한 것을 지워요", "backspace": "선택한 것을 지워요", "cmd+delete": "선택한 것을 지워요 (휴지통)",
                        "cmd+backspace": "선택한 것을 지워요 (휴지통)", "forwarddelete": "선택한 것을 지워요", "return": "확인 (엔터)", "enter": "확인 (엔터)",
                        "escape": "취소", "esc": "취소", "tab": "다음 칸으로", "space": "스페이스", "cmd+s": "저장", "cmd+shift+s": "다른 이름으로 저장",
                        "cmd+z": "실행 취소", "cmd+a": "전체 선택", "cmd+c": "복사", "cmd+v": "붙여넣기", "cmd+x": "잘라내기", "cmd+w": "창 닫기",
                        "cmd+q": "앱 종료", "cmd+n": "새로 만들기", "cmd+p": "프린트", "cmd+return": "보내기 또는 확인"]
        return keys.map { key in
            let shownKey = shown(key)
            return (english ? ArisDesktopCopy.keyMeanings : meanings)[key.lowercased()].map { "\(shownKey) (\($0))" } ?? shownKey
        }.joined(separator: " ")
    }

    static func verbLabel(_ verb: ArisDesktopVerb, english: Bool = false) -> String {
        if english { return ArisDesktopCopy.verb(verb) }
        switch verb {
        case .click: return "누르기"
        case .type: return "입력하기"
        case .setValue: return "값 넣기"
        case .press: return "키 누르기"
        case .scroll: return "스크롤"
        case .drag: return "끌어다 놓기"
        case .menuClick: return "메뉴 고르기"
        case .dialogClick: return "대화상자 버튼 누르기"
        case .dialogInput: return "대화상자에 입력하기"
        case .dialogFile: return "파일 고르기"
        case .window: return "창 다루기"
        case .app: return "앱 다루기"
        case .clickAt: return "화면 보고 누르기"
        case .see, .menuList, .dialogList, .windowList, .dockList: return "보기"
        case .batch: return "여러 단계 하기"
        }
    }

    /// "~/Desktop/a" or "/Users/me/Desktop/a" as Finder names it from home: 바탕화면 › a.
    /// In English the folders keep their own names: Desktop › a.
    static func friendlyPath(_ path: String, home: String = NSHomeDirectory(), english: Bool = false) -> String {
        var rest = path
        var inHome = false
        if rest.hasPrefix("~/") { rest.removeFirst(2); inHome = true } else if rest.hasPrefix(home + "/") { rest.removeFirst(home.count + 1); inHome = true }
        var parts = rest.split(separator: "/").map(String.init)
        let folders = ["Desktop": "바탕화면", "Documents": "문서", "Downloads": "다운로드", "Pictures": "사진", "Movies": "동영상", "Music": "음악"]
        if inHome, let first = parts.first, let named = folders[first] { parts[0] = english ? first : named } else if inHome { parts.insert(english ? "Home" : "홈", at: 0) }
        return parts.isEmpty ? path : parts.joined(separator: " › ")
    }

    /// Text as the card shows it: line breaks kept, every other control or invisible character escaped.
    static func shown(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            if scalar == "\n" { out.append("\n") } else if scalar == "\t" { out += "\\t" } else if CharacterSet.controlCharacters.contains(scalar) || ArisJSTokens.isHidden(scalar)
                        || ArisCommandPolicy.isLineBreak(scalar) {
                out += String(format: "\\u{%04X}", scalar.value)
            } else { out.unicodeScalars.append(scalar) }
        }
        return out
    }

    /// `window`: the window's title as the look showed it. `composer`: in a sending app, what the field holds right now
    /// (its raw value, read for the card: I1). `send`: the action may send it.
    /// `paste`: in a sending app, the clipboard's text a paste would put in. `unnamedDocument`: a file panel the user's words
    /// named no app or document for. `english`: the whole card in English (audit desk-11), else Korean.
    static func card(_ request: ArisDesktopRequest, target: ArisDesktopTarget, element: ArisDesktopElement?, window: String? = nil,
                     composer: String? = nil, send: Bool = false, blindField: Bool = false, blindSend: String? = nil, searchFocus: String? = nil,
                     paste: String? = nil, unnamedDocument: Bool = false, remember: Bool, wiped: Bool, mayRaise: Bool = false, english: Bool = false) -> ArisMCPCard {
        // One line in the card's language.
        let say = { (korean: String, inEnglish: String) in english ? inEnglish : korean }
        let empty = say("(비어 있음)", "(empty)")
        var lines: [String] = []
        if let window { lines.append(ArisDesktopCopy.windowLine(window, english: english)) }
        if let element {
            let name = shown(String(element.label.prefix(80)))
            let kind = element.role.isEmpty ? say("요소", ArisDesktopCopy.anyRole) : roleWord(element.role, english: english)
            lines.append(say("대상: ", "Target: ") + kind + (name.isEmpty ? "" : " “\(name)”"))
        } else if let ref = request.ref {
            lines.append(say("대상: ", "Target: ") + ref.text)
        }
        switch request.verb {
        case .type, .setValue, .dialogInput:
            if let field = request.field { lines.append(say("칸: ", "Field: ") + shown(field)) }
            if target.sending, let composer { lines.append(say("칸에 지금 있는 글:\n", "In the field now:\n") + (composer.isEmpty ? empty : shown(composer))) }
            if blindField {
                lines.append(say("이 앱은 입력 칸의 글을 읽을 수 없어서, 입력한 뒤 창을 다시 읽어 확인해요",
                                 "This app's text field can't be read, so after typing Aris reads the window again to check"))
            }
            lines.append(say("입력하는 글:\n", "Text to type:\n") + shown(request.text ?? ""))
        case .press:
            // One press that selects everything and deletes it says so first (audit desk-3: the card that guards replacing).
            if ArisDesktopBatch.selectsThenDeletes(request.keys) {
                lines.insert(say("⚠️ 이 창의 글을 모두 선택해서 지워요", "⚠️ This selects all the text in this window and deletes it"), at: 0)
            }
            lines.append(say("키: ", "Keys: ") + keyWords(request.keys, english: english))
            if let searchFocus { lines.append(say("검색 칸 “\(shown(searchFocus))”에서 눌러요 (보내기 아님)", "Pressed in the search field “\(shown(searchFocus))” (not a send)")) }
            if let paste { lines.append(pasteLine(english: english) + "\n" + shown(paste)) }
        case .menuClick:
            lines.append(say("메뉴: ", "Menu: ") + shown(request.path ?? ""))
            if let paste { lines.append(pasteLine(english: english) + "\n" + shown(paste)) }
        case .dialogClick:
            lines.append(say("버튼: ", "Button: ") + shown(request.button ?? ""))
        case .dialogFile:
            // His words named neither this app nor a document: said first, before the document it would save.
            if unnamedDocument { lines.insert(unnamedDocumentLine(english: english), at: 0) }
            if window != nil { lines.append(say("이 문서를 저장하거나 열어요 (지금 앞에 있는 문서)", "This saves or opens this document (the one in front now)")) }
            lines.append(say("폴더: ", "Folder: ") + (request.path.map { shown(friendlyPath($0, english: english)) } ?? say("파일 창에 지금 열려 있는 폴더", "the folder the file panel shows now")))
            lines.append(say("누를 버튼: ", "Button to press: ") + (request.select.map(shown) ?? say("기본 버튼 (저장 또는 열기)", "the default button (Save or Open)")))
            if let name = request.name {
                lines.append(say("파일 이름: ", "File name: ") + shown(name))
                let kind = (name as NSString).pathExtension
                lines.append(say("형식: ", "Format: ") + (kind.isEmpty ? say("앱이 정하는 형식 (확장자가 붙을 수 있어요)", "the app's own format (it may add an extension)")
                    : ".\(shown(kind)) " + say("(앱이 다른 형식으로 바꿀 수 있어요)", "(the app may change it to another format)")))
            }
            if ArisDesktopGate.secretPlace(request, home: NSHomeDirectory()) { lines.append(say("⚠️ 키, 토큰이나 비밀번호 파일일 수 있어요", "⚠️ This may be a key, token or password file")) }
            lines.append(say("파일 창을 앞으로 가져와서 다뤄요", "The file panel is brought to the front for this"))
        case .window:
            lines.append(say("창 다루기: ", "Window: ") + shown(request.operation ?? ""))
        case .app:
            lines.append(request.operation == "quit" ? say("앱을 종료해요 (저장하지 않은 문서가 있으면 앱이 먼저 물어봐요)", "This quits the app (if a document isn't saved, the app asks first)")
                : say("앱: ", "App: ") + shown(request.operation ?? ""))
        case .drag:
            if let to = request.to { lines.append(say("놓을 곳: ", "Drop on: ") + to.text) }
        case .clickAt:
            lines.append(say("찾을 것: ", "Looking for: ") + shown(request.target ?? ""))
            lines.append(say("창을 찍어 AI가 위치를 찾은 뒤 그 자리를 눌러요 (안 되면 실제 마우스로)",
                             "Aris takes a picture of the window, an AI finds the spot, and that spot is clicked (with the real pointer if it must)"))
        default: break
        }
        // One action, one card (QA BUG-47 retest): this yes also covers bringing the window forward when the background
        // can't reach it; then nothing more is asked, and if the window still isn't in front, nothing is done.
        if mayRaise, [.type, .setValue, .press, .click, .clickAt].contains(request.verb) {
            let title = window.map { shown(ArisWindowTitleMatch.safeTitle($0)) }
            if english {
                lines.append("If it can't be done in the background, the window\(title.map { " “\($0)”" } ?? "") is brought to the front for it (then the app you were in comes back)")
            } else {
                let named = title.map { "‘\($0)’ 창을" } ?? "창을"
                lines.append("백그라운드로 안 되면 \(named) 앞으로 가져와서 \(verbLabel(request.verb)) (끝나면 원래 앱으로 돌아가요)")
            }
        }
        if target.sending, !request.verb.takesText {
            if send, let blindSend {
                // The field gives no value (KakaoTalk's): the card says what Aris itself typed there this turn, and that
                // the field can't be read (audit desk-4: a card, not a refusal).
                lines.append(say("보낼 글 (Aris가 방금 입력한 글):\n", "Text to send (what Aris just put there):\n") + shown(blindSend))
                lines.append(say("이 앱은 입력 칸을 읽을 수 없어요. 칸에 다른 글이 더 있었다면 함께 보내져요",
                                 "This app's text field can't be read. If it held other text too, that is sent with it"))
            } else if send {
                lines.append(say("보낼 글 (지금 칸에 있는 그대로):\n", "Text to send (exactly what the field holds now):\n")
                    + (composer.map { $0.isEmpty ? empty : shown($0) } ?? say("(읽지 못함)", "(couldn't be read)")))
            } else if let composer, !composer.isEmpty {
                lines.append(say("칸에 있는 글:\n", "In the field:\n") + shown(composer))
            }
        }
        lines += closing(target: target, remember: remember, wiped: wiped, english: english)
        let detail = lines.joined(separator: "\n")
        let short = detail.count > 600 ? String(detail.prefix(600)) + "…" : detail
        let quits = request.verb == .app && request.operation == "quit"
        let name = shown(target.name)
        let title: String
        if english {
            title = send ? "Send in \(name)" : quits ? "Quit \(name)" : paste != nil ? "Paste in \(name)" : "\(verbLabel(request.verb, english: true)) in \(name)"
        } else {
            title = send ? "\(name)에서 보내기" : quits ? "\(name) 종료하기" : paste != nil ? "\(name)에서 붙여넣기" : "\(name)에서 \(verbLabel(request.verb))"
        }
        return ArisMCPCard(title: title, detail: short, full: short == detail ? nil : detail, fields: [])
    }

    /// A card's last line: why it asks every time, or what a yes is kept for.
    static func closing(target: ArisDesktopTarget, remember: Bool, wiped: Bool, english: Bool) -> [String] {
        if target.sending { return [english ? "This is a messaging app, so Aris asks every time" : "메시지 앱이라 매번 물어봐요"] }
        if remember {
            return [english ? "If you allow it, Aris won't ask again for \(shown(target.name)) in this conversation"
                            : "허용하면 이 대화에서 \(ArisJosa.attach(shown(target.name), "은", "는")) 다시 묻지 않아요"]
        }
        if wiped { return [english ? "Aris has read other text since your yes, so it asks again" : "읽은 내용이 있어서 다시 물어봐요"] }
        return []
    }

    /// Above the clipboard's text on a paste card.
    static let pasteLine = "붙여넣을 글 (지금 클립보드에 있는 그대로):"
    static func pasteLine(english: Bool) -> String { english ? "Text to paste (exactly what is on the clipboard now):" : pasteLine }
    /// First on a file panel's card when the user's words named neither the app nor a document.
    static let unnamedDocumentLine = "⚠️ 말씀에 이 앱이나 문서 이름이 없었어요. 지금 앞에 있는 아래 문서를 다뤄요"
    static func unnamedDocumentLine(english: Bool) -> String {
        english ? "⚠️ Your request named neither this app nor a document. This acts on the document in front, named below" : unnamedDocumentLine
    }
}
