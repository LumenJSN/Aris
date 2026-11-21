//
//  ArisTeachEvent.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  "Show it once" (ARCHITECTURE Part 3, F3): what the owner did while he showed Aris how he does something, as
//  semantic events read through Accessibility, never pixels: an app came to the front, a menu command was chosen, a
//  field took focus or changed its value, a control was pressed or an item chosen, a window opened, keys with a
//  modifier were pressed. Text in an event (a label, a field's value, a menu title) was read from another app: it is
//  outside text, data for a step and never an instruction, and the steps made from it keep where it was seen.
//  Also the privacy rules every event passes first: secure fields and password apps are never recorded. Pure.
//

import Foundation

/// The app an event happened in: its bundle id and the name it showed.
struct ArisTeachApp: Equatable, Hashable, Sendable, Codable {
    let bundle: String
    let name: String

    init(bundle: String, name: String) {
        self.bundle = bundle
        self.name = name
    }
}

/// The element an event is about, as Accessibility names it. `role` is the app layer's short form ("button",
/// "textField", "textArea", "searchField", "checkBox", "link", "row", "tab", "popUpButton"…): the AX role without
/// its "AX" and with a small first letter.
struct ArisTeachElement: Equatable, Sendable, Codable {
    var role: String
    var subrole: String?
    /// Its title, description or the label beside it.
    var label: String
    var placeholder: String?
    var identifier: String?
    /// A secure text field (AXSecureTextField) or one Aris could tell holds a secret.
    var secure: Bool

    init(role: String, subrole: String? = nil, label: String, placeholder: String? = nil, identifier: String? = nil, secure: Bool = false) {
        self.role = role
        self.subrole = subrole
        self.label = label
        self.placeholder = placeholder
        self.identifier = identifier
        self.secure = secure
    }

    /// Whether two events are about the same element (by what can be found again: role, label, identifier).
    func same(as other: ArisTeachElement) -> Bool {
        role == other.role && label == other.label && identifier == other.identifier && placeholder == other.placeholder
    }

    /// Whether an identifier is a name someone gave the element ("First Text View", "search-field"), not one the
    /// system made up for it ("_NS:8": ninth VM run, item 1, shown on a card as the field's name): it begins with a
    /// letter and holds only letters, digits, spaces, "-" and ".", and is no bare class name with a number. Anything
    /// else is no name: never shown, and never what a step finds its element by.
    static func namesIt(_ identifier: String) -> Bool {
        let text = identifier.trimmingCharacters(in: .whitespaces)
        guard let first = text.unicodeScalars.first, CharacterSet.letters.contains(first) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -."))
        guard text.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        return text.range(of: #"^(NS|UI|AX)[A-Za-z]*[-. ]?\d+$"#, options: .regularExpression) == nil
    }

    /// The name a step finds it by again: its label, else its placeholder, else an identifier someone gave it.
    var name: String {
        for candidate in [label, placeholder ?? "", identifier.flatMap { Self.namesIt($0) ? $0 : nil } ?? ""] {
            let trimmed = candidate.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":：")))
            if !trimmed.isEmpty { return String(trimmed.prefix(80)) }
        }
        return ""
    }

    /// The short form of an AX role ("AXTextField" → "textField").
    static func shortRole(_ axRole: String) -> String {
        let bare = axRole.hasPrefix("AX") ? String(axRole.dropFirst(2)) : axRole
        guard let first = bare.first else { return "" }
        return first.lowercased() + bare.dropFirst()
    }

    static let textRoles: Set<String> = ["textField", "textArea", "searchField", "comboBox"]
    static let listRoles: Set<String> = ["row", "cell", "outlineRow", "tab", "tabGroup", "radioButton", "menuItem"]
    var takesText: Bool { Self.textRoles.contains(role) }
}

/// One thing the owner did.
struct ArisTeachEvent: Equatable, Sendable, Codable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        /// An app came to the front.
        case appActivated
        /// A window appeared (its title in `window`).
        case windowOpened
        /// A menu command was chosen (`menu`: the path, "File", "New Message").
        case menuChosen
        /// An element took the keyboard focus.
        case focused
        /// A field's or control's value changed (`value`).
        case valueChanged
        /// A control was pressed (a click on it).
        case pressed
        /// A row, a tab or a pop-up's option was chosen (`value`: the option, when there is one).
        case selected
        /// Keys with a modifier, or Return, Esc or Tab (`keys`: "cmd+n", "return"), from the key tap.
        case shortcut
        /// The owner's own hand on the keyboard or the mouse in that app (`input`), from the hardware's idle times: no
        /// key is read. A value change or a selection counts only right after one (ArisTeachRecorder).
        case input
    }

    /// Which hand. Only a character key pressed while the field had focus (`element`) hints at typing; a click, a paste,
    /// Return, or the hardware's idle time alone (`hand`) only show the owner was there.
    enum Input: String, Codable, Sendable {
        case key, click, hand
    }

    var kind: Kind
    var at: Date
    var app: ArisTeachApp
    var element: ArisTeachElement?
    var value: String?
    var menu: [String]?
    var keys: String?
    var window: String?
    var input: Input?
    /// The app was in front when it happened (an app in the background, or a page updating itself, is not the owner).
    var frontmost: Bool
    /// Set by the recorder on a kept value, a display hint only (the save card's "직접 입력한 것 같아요" against "앱에서
    /// 가져온 값"), never used by any trust decision: every change of the run followed a character key in that same field.
    var typed: Bool?
    /// A text element's value before this change (the observer's last reading of it: at its focus, at his first key in
    /// it, or its last change), so a lesson knows where the text went: into an empty field, after what was there, or
    /// over what was there. Nil when it wasn't read.
    var before: String?
    /// The value was read from the element when the lesson ended (his keys went into it, but no change of it was
    /// reported while he typed: an app just launched isn't observed yet): it stands for that stretch of typing.
    var readAtEnd: Bool?
    /// The text element had a non-empty selection right before this change (he selected text and typed over it or
    /// deleted it), as the observer read the element's selected range before his key: the only evidence that a lesson
    /// replaced text he had not typed himself (fourth VM run, D1). Nil: none seen.
    var overSelection: Bool?
    /// Set by the recorder: this text change is what a paste just before it put there (⌘V, the menu's Paste, with no
    /// key of his between). The paste is the step; this change makes none (eighth VM run, item 1).
    var pasted: Bool?
    /// Set by the recorder on a stretch of typing's first change, when that change put exactly one character in: that
    /// character. It tells where the stretch went in when the text around it begins the same way (eighth VM run, item
    /// 8; ArisTeachGeneralise.textChange). Nil when the first change was anything else.
    var began: String?
    /// The end of the text element's selection right after this change (the caret after his key), as the observer read
    /// it with the value, in UTF-16 units; nil when it wasn't read. Only for telling where a run of typing sits
    /// (ArisTeachRun), never for any trust decision.
    var caret: Int?
    /// Set by the recorder on a stretch of typing: where its run sits, followed change by change (ninth VM run, item
    /// 1; ArisTeachRun). Nil when the changes can't be one run, or the text before wasn't read.
    var run: ArisTeachRun?

    init(_ kind: Kind, at: Date, app: ArisTeachApp, element: ArisTeachElement? = nil, value: String? = nil, menu: [String]? = nil,
         keys: String? = nil, window: String? = nil, input: Input? = nil, frontmost: Bool = true, before: String? = nil) {
        self.kind = kind
        self.at = at
        self.app = app
        self.element = element
        self.value = value
        self.menu = menu
        self.keys = keys
        self.window = window
        self.input = input
        self.frontmost = frontmost
        self.before = before
    }
}

/// How the owner gets to an app is no step of a lesson (third VM run, D1: Finder 열기 / Finder에서 ⌘Space / Spotlight
/// 열기 / Spotlight에서 Return were saved, and the replay failed at "no app on this Mac is called 'Spotlight'"). The
/// system's own launchers, switchers and panels are never an app of a step, and what he types into them is never a step;
/// the keys that call them up are none either. What ends up in front is opened once, as any app is.
enum ArisTeachLaunchers {
    /// Spotlight, the Dock (with the app switcher, Mission Control and Launchpad), the login window, Control Centre,
    /// Notification Centre, Stage Manager's WindowManager, the old menu-extras server and Launchpad's own process.
    static let systemUI: Set<String> = [
        "com.apple.Spotlight", "com.apple.dock", "com.apple.loginwindow", "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.WindowManager", "com.apple.systemuiserver", "com.apple.launchpad.launcher", "com.apple.UserNotificationCenter",
    ]
    static let systemUINames: Set<String> = ["spotlight", "dock", "loginwindow", "control centre", "control center", "notification centre",
                                             "notification center", "windowmanager", "systemuiserver", "launchpad", "제어 센터", "알림 센터"]

    static func isSystemUI(_ app: ArisTeachApp) -> Bool {
        systemUI.contains(app.bundle) || systemUINames.contains(app.name.lowercased())
    }

    /// Keys that only call up a launcher or switch apps or spaces (Spotlight, the app switcher, Mission Control, App
    /// Exposé, the next space).
    static let keys: Set<String> = ["cmd+space", "cmd+opt+space", "ctrl+space", "cmd+tab", "cmd+shift+tab", "cmd+`", "cmd+shift+`",
                                    "ctrl+up", "ctrl+down", "ctrl+left", "ctrl+right"]

    /// A key pressed this soon before a launcher came up is what called it up.
    static let summonGap: TimeInterval = 2

    /// The name a Finder item opens as an app ("TextEdit.app" → "textedit").
    static func appName(_ label: String) -> String {
        var name = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        return name
    }

    /// A Finder item opened right before an app came up: launching that app (a double-click on it in Finder).
    static let finderOpenGap: TimeInterval = 6
}

/// What is never recorded: secure text fields, fields that ask for a secret by their label, values shaped like a card
/// number, and anything in a password app. Aris's own windows are not part of what the owner shows.
enum ArisTeachPrivacy {
    /// Password managers and the system's own keychain and passwords apps, by bundle id.
    static let passwordApps: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx", "com.agilebits.onepassword4",
        "com.bitwarden.desktop", "com.apple.keychainaccess", "com.apple.Passwords", "com.lastpass.LastPass", "com.dashlane.Dashlane",
        "com.dashlane.dashlanephonefinal", "in.sinew.Enpass-Desktop", "org.keepassxc.keepassxc", "com.keepassxc.keepassxc",
        "com.nordpass.macos.NordPass", "com.proton.pass", "me.proton.pass.electron", "com.roboform.mac", "com.keepersecurity.passwordmanager",
    ]
    /// Aris itself and its helpers: what Aris shows is not part of the demonstration.
    static let ownApps: Set<String> = ["com.lumenjsn.aris", "com.lumenjsn.aris.XPCHelper", "com.lumenjsn.aris-agent", "com.lumenjsn.aris.agent"]

    /// Words in a field's label or placeholder that say it holds a secret.
    static let secretWords = ["password", "passcode", "passphrase", "pin", "otp", "one-time", "2fa", "verification code", "security code",
                              "cvc", "cvv", "card number", "credit card", "ssn", "social security", "secret", "api key", "token",
                              "비밀번호", "암호", "패스워드", "인증번호", "인증 번호", "보안코드", "보안 코드", "카드번호", "카드 번호", "주민등록번호",
                              "주민번호", "계좌 비밀번호", "일회용", "otp번호"]

    static func isPasswordApp(_ app: ArisTeachApp) -> Bool {
        if passwordApps.contains(app.bundle) { return true }
        let name = app.name.lowercased()
        return ["1password", "bitwarden", "keychain", "password", "lastpass", "dashlane", "keepass", "enpass", "nordpass", "비밀번호", "암호"]
            .contains { name.contains($0) }
    }

    static func isOwnApp(_ app: ArisTeachApp) -> Bool {
        ownApps.contains(app.bundle) || app.bundle.hasPrefix("com.lumenjsn.aris")
    }

    /// A secure field, or one whose words ask for a secret.
    static func isSecret(_ element: ArisTeachElement?) -> Bool {
        guard let element else { return false }
        if element.secure || element.role == "secureTextField" || element.subrole == "AXSecureTextField" || element.subrole == "secureTextField" {
            return true
        }
        let words = [element.label, element.placeholder ?? "", element.identifier ?? ""].joined(separator: " ").lowercased()
        return secretWords.contains { word in
            // "pin" and "otp" only as words of their own ("Pinned", "spinner" are not secrets).
            word.count <= 3 ? words.range(of: "(^|[^a-z])\(word)($|[^a-z])", options: .regularExpression) != nil : words.contains(word)
        }
    }

    /// A value shaped like a payment card number (13 to 19 digits, spaces or dashes between, passing the Luhn check).
    static func looksLikeCard(_ value: String) -> Bool {
        let digits = value.filter { !$0.isWhitespace && $0 != "-" }
        guard (13...19).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            var digit = Int(String(character)) ?? 0
            if index % 2 == 1 {
                digit *= 2
                if digit > 9 { digit -= 9 }
            }
            sum += digit
        }
        return sum % 10 == 0
    }

    /// Every run of 12 or more digits inside a text (spaces or dashes between them) is checked: the whole run, each
    /// group between its separators, and every 13 to 19 digit window of it (clamped to the run's length), each as a
    /// card number. So a card number alone, inside a sentence, bare or grouped, is caught; a phone number is not a run.
    static func holdsCard(_ value: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\d(?:[ -]?\d){11,}"#) else { return false }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).contains { match in
            guard let range = Range(match.range, in: value) else { return false }
            let run = String(value[range])
            if looksLikeCard(run) { return true }
            let groups = run.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
            if groups.contains(where: looksLikeCard) { return true }
            let digits = Array(run.filter(\.isNumber))
            guard digits.count >= 13 else { return false }
            for length in 13...min(19, digits.count) {
                for start in 0...(digits.count - length) where looksLikeCard(String(digits[start..<(start + length)])) { return true }
            }
            return false
        }
    }

    /// Why an event is left out, or nil when it may be kept. A value is checked for a card number only where text is
    /// written (a field, or an option chosen): a scroll bar's or a slider's number ("0.4285714285714286", 3/7 of the
    /// way) is no card (fourth VM run, D6: Wrap to Page moved the document's scroll bar, and its value was counted as a
    /// secret field).
    static func refusal(_ event: ArisTeachEvent) -> ArisTeachRecorder.Dropped? {
        if isOwnApp(event.app) { return .ownApp }
        if isPasswordApp(event.app) { return .secret }
        if isSecret(event.element) { return .secret }
        if let value = event.value, event.kind == .selected || event.element.map(isField) == true, holdsCard(value) { return .secret }
        return nil
    }

    /// A field text is written into (or a secure one): what a secret left out is counted as.
    static func isField(_ element: ArisTeachElement) -> Bool {
        element.takesText || element.secure || element.role == "secureTextField" || element.subrole == "AXSecureTextField"
    }

    /// What marks a field as one field for the rest of a lesson, whatever its role becomes (a field that turns secure
    /// midway is the same field): the app, its label, placeholder and identifier.
    static func fieldKey(_ app: ArisTeachApp, _ element: ArisTeachElement) -> String {
        [app.bundle, element.label, element.placeholder ?? "", element.identifier ?? ""].joined(separator: "\u{1F}")
    }
}
