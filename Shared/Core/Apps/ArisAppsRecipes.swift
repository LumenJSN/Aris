//
//  ArisAppsRecipes.swift
//  Shared/Core/Apps
//
//  The things people ask most, as data over the app capabilities rather than code per app: each recipe names the
//  calls in order, each step with alternatives tried in turn when a channel is missing (a scripting dictionary, a
//  menu item, a URL scheme, the window's tree, keys), and the effect it has (sending is outward and says so). Values
//  come from the recipe's inputs ("{to}", "{text|url}" URL-encoded) and from the step before ("{last.path}"). The
//  runner is pure: it is handed the function that performs one capability call.
//

import Foundation

extension ArisApps {
    struct RecipeStep: Sendable {
        var call: String
        var arguments: [String: JSON]
        /// Run only when this input was given.
        var when: String? = nil
        var optional = false
        /// The effect this step has (the trust policy sees it per call too).
        var effect: Effect = .changeReversible

        init(_ call: String, _ arguments: [String: JSON], when: String? = nil, optional: Bool = false, effect: Effect = .changeReversible) {
            self.call = call
            self.arguments = arguments
            self.when = when
            self.optional = optional
            self.effect = effect
        }
    }

    /// One thing to get done: its ways (each a sequence of steps), tried in order until one finishes.
    struct RecipePart: Sendable {
        var name: String
        var ways: [[RecipeStep]]
        var optional = false
        var when: String? = nil
    }

    struct Recipe: Sendable {
        var id: String
        var title: String
        var titleEnglish: String
        var summary: String
        var inputs: [String]
        var required: [String]
        var effect: Effect
        var parts: [RecipePart]
        /// Words people use for it (matched by `Recipes.find`).
        var words: [String]
    }

    enum Recipes {
        private static func s(_ text: String) -> JSON { .string(text) }
        private static func step(_ call: String, _ arguments: [String: String], when: String? = nil, optional: Bool = false,
                                 effect: Effect = .changeReversible) -> RecipeStep {
            RecipeStep(call, arguments.mapValues(JSON.string), when: when, optional: optional, effect: effect)
        }

        /// System Settings panes people name, to their URL (x-apple.systempreferences:<id>, macOS 13 and later).
        static let settingsPanes: [String: String] = [
            "디스플레이": "com.apple.Displays-Settings.extension", "display": "com.apple.Displays-Settings.extension", "화면": "com.apple.Displays-Settings.extension",
            "소리": "com.apple.Sound-Settings.extension", "sound": "com.apple.Sound-Settings.extension",
            "블루투스": "com.apple.BluetoothSettings", "bluetooth": "com.apple.BluetoothSettings",
            "와이파이": "com.apple.wifi-settings-extension", "wifi": "com.apple.wifi-settings-extension", "wi-fi": "com.apple.wifi-settings-extension",
            "배터리": "com.apple.Battery-Settings.extension", "battery": "com.apple.Battery-Settings.extension",
            "키보드": "com.apple.Keyboard-Settings.extension", "keyboard": "com.apple.Keyboard-Settings.extension",
            "알림": "com.apple.Notifications-Settings.extension", "notifications": "com.apple.Notifications-Settings.extension",
            "개인정보": "com.apple.settings.PrivacySecurity.extension", "보안": "com.apple.settings.PrivacySecurity.extension",
            "privacy": "com.apple.settings.PrivacySecurity.extension",
            "일반": "com.apple.systempreferences.GeneralSettings", "general": "com.apple.systempreferences.GeneralSettings",
            "손쉬운 사용": "com.apple.Accessibility-Settings.extension", "accessibility": "com.apple.Accessibility-Settings.extension",
            "트랙패드": "com.apple.Trackpad-Settings.extension", "trackpad": "com.apple.Trackpad-Settings.extension",
            "마우스": "com.apple.Mouse-Settings.extension", "mouse": "com.apple.Mouse-Settings.extension",
            "네트워크": "com.apple.Network-Settings.extension", "network": "com.apple.Network-Settings.extension",
            "집중 모드": "com.apple.Focus-Settings.extension", "focus": "com.apple.Focus-Settings.extension",
            "화면 시간": "com.apple.Screen-Time-Settings.extension", "screen time": "com.apple.Screen-Time-Settings.extension",
            "외관": "com.apple.Appearance-Settings.extension", "다크 모드": "com.apple.Appearance-Settings.extension",
            "appearance": "com.apple.Appearance-Settings.extension", "dark mode": "com.apple.Appearance-Settings.extension",
            "배경화면": "com.apple.Wallpaper-Settings.extension", "wallpaper": "com.apple.Wallpaper-Settings.extension",
            "잠금 화면": "com.apple.Lock-Screen-Settings.extension", "lock screen": "com.apple.Lock-Screen-Settings.extension",
            "데스크탑": "com.apple.Desktop-Settings.extension", "dock": "com.apple.Desktop-Settings.extension", "독": "com.apple.Desktop-Settings.extension",
        ]

        static func pane(_ said: String) -> String? {
            let key = Text.key(said)
            if let exact = settingsPanes.first(where: { Text.key($0.key) == key }) { return exact.value }
            return settingsPanes.filter { key.contains(Text.key($0.key)) }.max { $0.key.count < $1.key.count }?.value
        }

        static let all: [Recipe] = [
            Recipe(id: "message.send", title: "메시지 보내기", titleEnglish: "Send a message",
                   summary: "Send a chat message in any chat app (KakaoTalk, Messages, Slack, Discord…): open the conversation, put the text, send.",
                   inputs: ["app", "to", "text"], required: ["app", "to", "text"], effect: .outward, parts: [
                    RecipePart(name: "open the app", ways: [[step("app.open", ["app": "{app}"])]]),
                    RecipePart(name: "open the conversation", ways: [
                        [step("app.click", ["app": "{app}", "target": "{to}", "part": "list"])],
                        [step("app.do", ["app": "{app}", "command": "find search 검색 찾기"]), step("app.type", ["app": "{app}", "text": "{to}", "target": "search field"]),
                         step("app.press", ["app": "{app}", "keys": "return"])],
                        [step("app.press", ["app": "{app}", "keys": "cmd+k"]), step("app.type", ["app": "{app}", "text": "{to}"]), step("app.press", ["app": "{app}", "keys": "return"])],
                        [step("app.do", ["app": "{app}", "command": "new message 새로운 메시지"]), step("app.type", ["app": "{app}", "text": "{to}", "target": "to 받는 사람"]),
                         step("app.press", ["app": "{app}", "keys": "return"])],
                    ]),
                    RecipePart(name: "put the text", ways: [
                        [step("app.type", ["app": "{app}", "text": "{text}", "target": "message field 메시지 입력"])],
                        [step("app.type", ["app": "{app}", "text": "{text}"])],
                    ]),
                    RecipePart(name: "send", ways: [[step("app.press", ["app": "{app}", "keys": "return"], effect: .outward)]]),
                    RecipePart(name: "check it went", ways: [[step("app.read", ["app": "{app}", "part": "conversation"], effect: .observe)]], optional: true),
                   ], words: ["메시지", "문자", "카톡", "보내", "send", "message", "text", "dm", "chat"]),
            Recipe(id: "mail.compose", title: "메일 쓰기", titleEnglish: "Compose a mail",
                   summary: "Open a new mail in the default mail app with recipient, subject and body filled in; nothing is sent.",
                   inputs: ["to", "subject", "body"], required: [], effect: .changeReversible, parts: [
                    RecipePart(name: "open a new mail", ways: [
                        [step("app.open", ["url": "mailto:{to}?subject={subject|url}&body={body|url}"])],
                        [step("app.do", ["app": "Mail", "command": "sdef:make:outgoingmessage", "subject": "{subject}", "content": "{body}"])],
                    ]),
                   ], words: ["메일", "이메일", "mail", "email", "compose", "작성", "쓰기"]),
            Recipe(id: "mail.send", title: "메일 보내기", titleEnglish: "Send a mail",
                   summary: "Compose a mail as mail.compose does, then send it.",
                   inputs: ["to", "subject", "body"], required: ["to"], effect: .outward, parts: [
                    RecipePart(name: "open a new mail", ways: [[step("app.open", ["url": "mailto:{to}?subject={subject|url}&body={body|url}"])]]),
                    RecipePart(name: "send", ways: [
                        [step("app.do", ["app": "Mail", "command": "Message › Send 메시지 › 보내기"], effect: .outward)],
                        [step("app.press", ["app": "Mail", "keys": "cmd+shift+d"], effect: .outward)],
                    ]),
                   ], words: ["메일", "보내", "send", "mail", "email"]),
            Recipe(id: "music.play", title: "음악 틀기", titleEnglish: "Play music",
                   summary: "Play in a music app (Music, Spotify…): search for what was asked when something was named, then play.",
                   inputs: ["app", "query"], required: ["app"], effect: .changeReversible, parts: [
                    RecipePart(name: "open the app", ways: [[step("app.open", ["app": "{app}"])]]),
                    RecipePart(name: "find it", ways: [
                        [step("app.do", ["app": "{app}", "command": "search 검색", "text": "{query}"])],
                        [step("app.press", ["app": "{app}", "keys": "cmd+f"]), step("app.type", ["app": "{app}", "text": "{query}"]), step("app.press", ["app": "{app}", "keys": "return"])],
                    ], when: "query"),
                    RecipePart(name: "play", ways: [
                        [step("app.do", ["app": "{app}", "command": "play 재생"])],
                        [step("app.press", ["app": "{app}", "keys": "space"])],
                    ]),
                   ], words: ["음악", "노래", "틀어", "재생", "play", "music", "song"]),
            Recipe(id: "browser.open", title: "웹페이지 열기", titleEnglish: "Open a web page",
                   summary: "Open a URL in the default browser (or the browser named).",
                   inputs: ["url", "app"], required: ["url"], effect: .changeReversible, parts: [
                    RecipePart(name: "open it", ways: [[step("app.open", ["url": "{url}", "app": "{app}"])], [step("app.open", ["url": "{url}"])]]),
                   ], words: ["열어", "사이트", "웹", "url", "link", "open", "page", "브라우저"]),
            Recipe(id: "browser.search", title: "웹 검색", titleEnglish: "Search the web",
                   summary: "Search the web for words in the default browser.",
                   inputs: ["query", "app"], required: ["query"], effect: .changeReversible, parts: [
                    RecipePart(name: "search", ways: [[step("app.open", ["url": "https://www.google.com/search?q={query|url}", "app": "{app}"])],
                                                      [step("app.open", ["url": "https://www.google.com/search?q={query|url}"])]]),
                   ], words: ["검색", "찾아", "구글", "search", "google", "look up"]),
            Recipe(id: "note.create", title: "메모 만들기", titleEnglish: "Create a note",
                   summary: "Create a note in Notes (or the notes app named) with the text.",
                   inputs: ["text", "app"], required: ["text"], effect: .changeReversible, parts: [
                    RecipePart(name: "a new note with the text", ways: [
                        [step("app.do", ["app": "Notes", "command": "File › New Note 파일 › 새로운 메모"]), step("app.type", ["app": "Notes", "text": "{text}"])],
                        [step("app.do", ["app": "Notes", "command": "sdef:make:note", "body": "{text}"])],
                    ]),
                   ], words: ["메모", "노트", "적어", "기록", "note", "write down", "jot"]),
            Recipe(id: "reminder.create", title: "미리 알림 만들기", titleEnglish: "Create a reminder",
                   summary: "Add a reminder in Reminders.",
                   inputs: ["text"], required: ["text"], effect: .changeReversible, parts: [
                    RecipePart(name: "a new reminder", ways: [
                        [step("app.do", ["app": "Reminders", "command": "File › New Reminder 파일 › 새로운 미리 알림"]), step("app.type", ["app": "Reminders", "text": "{text}"]),
                         step("app.press", ["app": "Reminders", "keys": "return"])],
                        [step("app.do", ["app": "Reminders", "command": "sdef:make:reminder", "name": "{text}"])],
                    ]),
                   ], words: ["미리알림", "리마인더", "할일", "reminder", "todo", "remind"]),
            Recipe(id: "event.create", title: "일정 만들기", titleEnglish: "Create an event",
                   summary: "Add a calendar event: Aris's own calendar capability first, else Calendar's New Event.",
                   inputs: ["title", "start"], required: ["title", "start"], effect: .changeReversible, parts: [
                    RecipePart(name: "the event", ways: [
                        [step("event", ["title": "{title}", "start": "{start}"])],
                        [step("app.do", ["app": "Calendar", "command": "File › New Event 파일 › 새로운 이벤트"]), step("app.type", ["app": "Calendar", "text": "{title} {start}"]),
                         step("app.press", ["app": "Calendar", "keys": "return"])],
                    ]),
                   ], words: ["일정", "약속", "캘린더", "event", "calendar", "meeting", "회의"]),
            Recipe(id: "file.open", title: "파일 찾아 열기", titleEnglish: "Find and open a file",
                   summary: "Find a file by words in its name or contents and open it (in the app named, else its default app).",
                   inputs: ["words", "app"], required: ["words"], effect: .changeReversible, parts: [
                    RecipePart(name: "find it", ways: [[step("files.find", ["words": "{words}"], effect: .observe)]]),
                    RecipePart(name: "open it", ways: [[step("app.open", ["path": "{last.path}", "app": "{app}"])], [step("app.open", ["path": "{last.path}"])]]),
                   ], words: ["파일", "문서", "열어", "찾아", "file", "document", "open", "find"]),
            Recipe(id: "settings.change", title: "설정 바꾸기", titleEnglish: "Change a setting",
                   summary: "Open the System Settings pane named and switch or press the setting named in it.",
                   inputs: ["pane", "setting"], required: ["pane"], effect: .changeReversible, parts: [
                    RecipePart(name: "open the pane", ways: [[step("app.open", ["url": "x-apple.systempreferences:{pane|settingspane}"])],
                                                           [step("app.open", ["app": "System Settings"])]]),
                    RecipePart(name: "change it", ways: [[step("app.click", ["app": "System Settings", "target": "{setting}"])]], when: "setting"),
                    RecipePart(name: "check", ways: [[step("app.read", ["app": "System Settings", "part": "controls"], effect: .observe)]], optional: true, when: "setting"),
                   ], words: ["설정", "켜", "꺼", "바꿔", "setting", "settings", "turn on", "turn off", "preference"]),
        ]

        static func recipe(_ id: String) -> Recipe? { all.first { $0.id == id } }

        /// The recipes a request may mean, best first.
        static func find(_ text: String) -> [Recipe] {
            let asked = Set(Lexicon.terms(text))
            let meanings = Set(asked.flatMap(Lexicon.meanings))
            return all.map { recipe -> (Recipe, Int) in
                let words = Set(recipe.words.flatMap(Lexicon.terms))
                let hits = words.intersection(asked).count * 2 + Set(words.flatMap(Lexicon.meanings)).intersection(meanings).count
                return (recipe, hits)
            }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
        }

        // MARK: - Filling in

        /// A template's text with the inputs and the step before's data put in; nil when it needs an input not given.
        static func fill(_ template: String, inputs: [String: String], last: JSON?) -> String? {
            var out = "", rest = Substring(template)
            while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
                out += rest[..<open]
                let token = String(rest[rest.index(after: open)..<close])
                let parts = token.split(separator: "|").map(String.init)
                let name = parts.first ?? ""
                var value: String?
                if name.hasPrefix("last.") {
                    let key = String(name.dropFirst(5))
                    let data = last?["data"] ?? last
                    value = (data?[key] ?? data?["items"]?.array?.first?[key] ?? data?.array?.first?[key])?.string
                } else {
                    value = inputs[name]
                }
                guard var found = value, !found.isEmpty else { return nil }
                if parts.contains("url") { found = found.addingPercentEncoding(withAllowedCharacters: ArisApps.urlQueryValue) ?? found }
                if parts.contains("settingspane") { guard let pane = pane(found) else { return nil }; found = pane }
                out += found
                rest = rest[rest.index(after: close)...]
            }
            return out + rest
        }

        /// A step's arguments filled in; nil when a needed input is missing. Optional inputs left empty drop their key,
        /// and a mailto/url whose optional parts are empty keeps only what was given.
        static func arguments(_ step: RecipeStep, inputs: [String: String], last: JSON?) -> [String: JSON]? {
            var out: [String: JSON] = [:]
            for (key, value) in step.arguments {
                guard case .string(let template) = value else { out[key] = value; continue }
                if let filled = fill(template, inputs: inputs, last: last) { out[key] = .string(filled); continue }
                if key == "url", template.hasPrefix("mailto:") {
                    out[key] = .string(mailto(inputs))
                    continue
                }
                // A whole-value template of an input not given: the argument is left out (an optional one).
                if template.hasPrefix("{"), template.hasSuffix("}"), template.dropFirst().dropLast().allSatisfy({ $0 != "{" }) { continue }
                return nil
            }
            return out
        }

        static func mailto(_ inputs: [String: String]) -> String {
            var query: [String] = []
            for key in ["subject", "body"] {
                if let value = inputs[key], !value.isEmpty { query.append("\(key)=\(value.addingPercentEncoding(withAllowedCharacters: ArisApps.urlQueryValue) ?? value)") }
            }
            let to = (inputs["to"] ?? "").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            return "mailto:\(to)" + (query.isEmpty ? "" : "?" + query.joined(separator: "&"))
        }

        // MARK: - Running

        struct Trace: Equatable, Sendable {
            var part: String
            var call: String
            var ok: Bool
            var did: String
        }

        /// Runs a recipe: each part's ways in turn until one finishes every step; a required part with no way left
        /// stops it. `perform` runs one capability call.
        static func run(_ recipe: Recipe, inputs: [String: String], perform: (String, [String: JSON]) -> Outcome) -> Outcome {
            if let missing = recipe.required.first(where: { (inputs[$0] ?? "").isEmpty }) {
                return .failure("\(recipe.id) needs \(missing)", effect: recipe.effect)
            }
            var trace: [Trace] = [], last: JSON?, finished = true, verified = false
            for part in recipe.parts {
                if let when = part.when, (inputs[when] ?? "").isEmpty { continue }
                var done = false
                for way in part.ways {
                    var wayOK = true, wayLast = last
                    for step in way {
                        if let when = step.when, (inputs[when] ?? "").isEmpty { continue }
                        guard let arguments = arguments(step, inputs: inputs, last: wayLast) else { wayOK = false; break }
                        let outcome = perform(step.call, arguments)
                        trace.append(Trace(part: part.name, call: step.call, ok: outcome.ok, did: outcome.did))
                        guard outcome.ok || step.optional else { wayOK = false; break }
                        wayLast = outcome.json
                        verified = verified || outcome.verified
                    }
                    if wayOK { done = true; last = wayLast; break }
                }
                if !done, !part.optional { finished = false; break }
            }
            let lines: [JSON] = trace.map { .string("\($0.ok ? "✓" : "✗") \($0.part): \($0.call) — \($0.did)") }
            let failedPart = trace.last(where: { !$0.ok })?.part
            return Outcome(ok: finished, did: finished ? "\(recipe.titleEnglish): done" : "\(recipe.titleEnglish): stopped at “\(failedPart ?? "?")”",
                           now: trace.last.map { $0.did } ?? "", data: .object(["steps": .array(lines)]), effect: recipe.effect,
                           channel: "recipe", verified: verified)
        }
    }
}

extension ArisApps {
    /// What may stand unescaped in a URL query value (no &, =, +, ? or #).
    static let urlQueryValue: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#")
        return set
    }()
}
