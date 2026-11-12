//
//  ArisOnboardingCopy.swift
//  Aris
//
//  Every word the onboarding shows or says, from Aris/Localizable.xcstrings (Korean and English), in the app's one UI
//  language (ArisUILanguage: Korean or English, English when the Mac is in neither). Formats go through the catalog, so a
//  name or a key lands where each language puts it. The English default values stand in only where no catalog is
//  bundled (the tests).
//

import Foundation

enum ArisOnboardingCopy {
    /// The languages the catalog has the onboarding in.
    static let languages: Set<String> = ["ko", "en"]

    /// The onboarding's language, read once per run (the app's language needs a restart to change anyway).
    nonisolated(unsafe) static var language = ArisUILanguage.code

    /// The compiled catalog for `language` (ko.lproj / en.lproj); the main bundle when there is none.
    nonisolated(unsafe) static var bundle: Bundle = lproj(language, in: .main)

    static func lproj(_ language: String, in bundle: Bundle) -> Bundle {
        bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? bundle
    }

    static var locale: Locale { Locale(identifier: language) }

    /// Picks the language again (a replay after the app's language changed, or the offscreen renders).
    static func use(_ code: String, in main: Bundle = .main) {
        language = code
        bundle = lproj(code, in: main)
    }

    // MARK: - The intro

    static var overlayLabel: String { String(localized: "onboarding.overlay.label", defaultValue: "Welcome to Aris", bundle: bundle, locale: locale, comment: "VoiceOver: the full-screen welcome") }
    static var kicker: String { String(localized: "onboarding.intro.kicker", defaultValue: "THE ASSISTANT IN YOUR NOTCH", bundle: bundle, locale: locale, comment: "Small tracked line over the tagline in the intro") }
    static var tagline: String { String(localized: "onboarding.intro.tagline", defaultValue: "Say it, and it's done.", bundle: bundle, locale: locale, comment: "The intro's one big line") }
    static var start: String { String(localized: "onboarding.intro.start", defaultValue: "Get started", bundle: bundle, locale: locale, comment: "The intro's glass button") }
    static var skip: String { String(localized: "onboarding.intro.skip", defaultValue: "Skip", bundle: bundle, locale: locale, comment: "Bottom-right, after 12 s: skip the intro") }
    static var skipHint: String { String(localized: "onboarding.intro.skip.hint", defaultValue: "Goes straight to setup.", bundle: bundle, locale: locale, comment: "VoiceOver hint for Skip") }
    static var mute: String { String(localized: "onboarding.mute", defaultValue: "Mute", bundle: bundle, locale: locale, comment: "VoiceOver: the intro's sound button while sound is on") }
    static var unmute: String { String(localized: "onboarding.unmute", defaultValue: "Unmute", bundle: bundle, locale: locale, comment: "VoiceOver: the intro's sound button while muted") }
    static var close: String { String(localized: "onboarding.close", defaultValue: "Close the guide", bundle: bundle, locale: locale, comment: "VoiceOver: the ✕ that closes the onboarding") }
    static var closeHint: String { String(localized: "onboarding.close.hint", defaultValue: "You can see it again in Settings › General.", bundle: bundle, locale: locale, comment: "VoiceOver hint for the ✕") }
    static var starLabel: String { String(localized: "onboarding.star", defaultValue: "Aris", bundle: bundle, locale: locale, comment: "VoiceOver: Aris's star") }

    // MARK: - The talk

    static var greet: [String] {
        [String(localized: "onboarding.greet.1", defaultValue: "Hi, I'm Aris.", bundle: bundle, locale: locale, comment: "Aris's first spoken line (caption)"),
         String(localized: "onboarding.greet.2", defaultValue: "What should I call you?", bundle: bundle, locale: locale, comment: "Aris asks the user's name (caption, own line)")]
    }

    /// The recorded greeting's captions, word for word (the Korean voice is a fixed recording: no name in it, N2). The
    /// name shows on the next line instead (permsNarration).
    static var greetName: [String] {
        [String(localized: "onboarding.greetName.1", defaultValue: "Nice to meet you!", bundle: bundle, locale: locale, comment: "Caption greeting the user after they typed their name (the recording has no name in it)"),
         String(localized: "onboarding.greetName.2", defaultValue: "Let's get a few things ready together.", bundle: bundle, locale: locale, comment: "Caption before the setup window")]
    }

    static var namePlaceholder: String { String(localized: "onboarding.name.placeholder", defaultValue: "Your name", bundle: bundle, locale: locale, comment: "The name field's placeholder") }
    static var nameLabel: String { String(localized: "onboarding.name.label", defaultValue: "What Aris should call you", bundle: bundle, locale: locale, comment: "VoiceOver: the name field") }
    static var send: String { String(localized: "onboarding.name.send", defaultValue: "Send", bundle: bundle, locale: locale, comment: "VoiceOver: the name field's send button") }
    static var nameMissing: String { String(localized: "onboarding.name.missing", defaultValue: "Type a name for me to call you.", bundle: bundle, locale: locale, comment: "Under the name field when it's empty") }

    // MARK: - The window

    static var windowTitle: String { String(localized: "onboarding.window.title", defaultValue: "Set up Aris", bundle: bundle, locale: locale, comment: "The setup window's title (VoiceOver, Mission Control)") }
    static var back: String { String(localized: "onboarding.window.back", defaultValue: "Back", bundle: bundle, locale: locale, comment: "Bottom-left: the previous page") }
    static var later: String { String(localized: "onboarding.window.later", defaultValue: "Finish later", bundle: bundle, locale: locale, comment: "Bottom-right: close the setup and resume it at a later launch") }
    static var laterHint: String { String(localized: "onboarding.window.later.hint", defaultValue: "The rest comes back the next time you open Aris.", bundle: bundle, locale: locale, comment: "VoiceOver hint for Finish later") }

    static func progress(_ page: Int, _ count: Int) -> String {
        String(localized: "onboarding.window.progress", defaultValue: "Step \(page) of \(count)", bundle: bundle, locale: locale, comment: "VoiceOver: the progress rail")
    }

    // MARK: - 권한

    static var permsTitle: String { String(localized: "onboarding.perms.title", defaultValue: "A few permissions", bundle: bundle, locale: locale, comment: "Permissions page heading") }
    /// `name`: what the user asked to be called (ArisUserName), on this one line after the greeting.
    static func permsNarration(name: String?) -> String {
        guard let name else {
            return String(localized: "onboarding.perms.narration", defaultValue: "Allow a few things and I can get to work.", bundle: bundle, locale: locale, comment: "The notch says this as the permissions page opens")
        }
        return String(localized: "onboarding.perms.narration.named", defaultValue: "\(name), allow a few things and I can get to work.", bundle: bundle, locale: locale, comment: "The notch says this as the permissions page opens; the argument is the name the user gave")
    }
    static var allow: String { String(localized: "onboarding.perms.allow", defaultValue: "Allow", bundle: bundle, locale: locale, comment: "A permission card's button") }
    static var notNow: String { String(localized: "onboarding.perms.notNow", defaultValue: "Not now", bundle: bundle, locale: locale, comment: "A permission card's secondary button") }
    static var putOff: String { String(localized: "onboarding.perms.putOff", defaultValue: "Later", bundle: bundle, locale: locale, comment: "A permission card's state after Not now") }
    static var waiting: String { String(localized: "onboarding.perms.waiting", defaultValue: "Waiting…", bundle: bundle, locale: locale, comment: "A permission card while macOS's window is up") }
    static var continueLabel: String { String(localized: "onboarding.perms.continue", defaultValue: "Continue", bundle: bundle, locale: locale, comment: "Permissions page: on to the next page") }
    static var stageLabel: String { String(localized: "onboarding.perms.stage", defaultValue: "Preview of the window macOS shows next", bundle: bundle, locale: locale, comment: "VoiceOver: the preview on the right") }

    /// A line that names Accessibility, said with the name this macOS gives that list (macOS 27 renamed it:
    /// ArisFix.Pane.title). The translations carry the name from before; it is swapped here, in one place.
    static func axNamed(_ line: String) -> String { ArisFix.Pane.accessibility.renamed(in: line, english: language != "ko") }

    static func cardTitle(_ card: ArisPermissionCard) -> String {
        switch card {
        case .mic: String(localized: "onboarding.perms.mic.title", defaultValue: "Allow the microphone", bundle: bundle, locale: locale, comment: "Permission card")
        case .accessibility: axNamed(String(localized: "onboarding.perms.ax.title", defaultValue: "Allow Accessibility", bundle: bundle, locale: locale, comment: "Permission card"))
        case .screen: String(localized: "onboarding.perms.screen.title", defaultValue: "Allow Screen Recording", bundle: bundle, locale: locale, comment: "Permission card")
        }
    }

    static func cardDone(_ card: ArisPermissionCard) -> String {
        switch card {
        case .mic: String(localized: "onboarding.perms.mic.done", defaultValue: "The microphone is on.", bundle: bundle, locale: locale, comment: "Permission card once granted")
        case .accessibility: axNamed(String(localized: "onboarding.perms.ax.done", defaultValue: "Accessibility is on.", bundle: bundle, locale: locale, comment: "Permission card once granted"))
        case .screen: String(localized: "onboarding.perms.screen.done", defaultValue: "Screen Recording is on.", bundle: bundle, locale: locale, comment: "Permission card once granted")
        }
    }

    static func cardWhy(_ card: ArisPermissionCard) -> String {
        switch card {
        case .mic: String(localized: "onboarding.perms.mic.why", defaultValue: "So I can hear you. I listen while you hold the shortcut.", bundle: bundle, locale: locale, comment: "Why the microphone")
        case .accessibility: String(localized: "onboarding.perms.ax.why", defaultValue: "So I can click and type for you, as you say.", bundle: bundle, locale: locale, comment: "Why Accessibility")
        case .screen: String(localized: "onboarding.perms.screen.why", defaultValue: "So I can see the screen you're looking at.", bundle: bundle, locale: locale, comment: "Why Screen Recording")
        }
    }

    /// Under the microphone card's reason: macOS asks a second time, for speech recognition (fresh install F9: the page
    /// said three permissions and a fourth prompt came).
    static var micSpeech: String { String(localized: "onboarding.perms.mic.speech", defaultValue: "macOS asks twice here: for the microphone, then for speech recognition.", bundle: bundle, locale: locale, comment: "Microphone card: the second system prompt, so the count on the page is true") }

    // MARK: - The previews of macOS's own windows (in the onboarding's language, as macOS would draw them)

    static var alertMicTitle: String { String(localized: "onboarding.mac.mic.title", defaultValue: "“Aris” would like to access the microphone.", bundle: bundle, locale: locale, comment: "Preview of macOS's microphone alert: its title") }
    static var alertMicBody: String { String(localized: "onboarding.mac.mic.body", defaultValue: "Aris listens while you hold its shortcut, and for its name if you turn that on.", bundle: bundle, locale: locale, comment: "Preview of macOS's microphone alert: the app's reason") }
    static var alertDontAllow: String { String(localized: "onboarding.mac.dontAllow", defaultValue: "Don't Allow", bundle: bundle, locale: locale, comment: "Preview of macOS's alert button") }
    static var alertAllow: String { String(localized: "onboarding.mac.allow", defaultValue: "Allow", bundle: bundle, locale: locale, comment: "Preview of macOS's alert button") }
    static var alertScreenTitle: String { String(localized: "onboarding.mac.screen.title", defaultValue: "“Aris” would like to record this computer's screen and audio.", bundle: bundle, locale: locale, comment: "Preview of macOS's screen recording alert") }
    static var alertSettingsBody: String { String(localized: "onboarding.mac.settings.body", defaultValue: "Grant access to this application in Privacy & Security settings, located in System Settings.", bundle: bundle, locale: locale, comment: "Preview of macOS's alert body") }
    static var alertDeny: String { String(localized: "onboarding.mac.deny", defaultValue: "Deny", bundle: bundle, locale: locale, comment: "Preview of macOS's alert button") }
    static var alertOpenSettings: String { String(localized: "onboarding.mac.openSettings", defaultValue: "Open System Settings", bundle: bundle, locale: locale, comment: "Preview of macOS's alert button") }
    static var settingsSidebar: [String] {
        [String(localized: "onboarding.mac.side.general", defaultValue: "General", bundle: bundle, locale: locale, comment: "Preview of System Settings' sidebar"),
         String(localized: "onboarding.mac.side.accessibility", defaultValue: "Accessibility", bundle: bundle, locale: locale, comment: "Preview of System Settings' sidebar"),
         String(localized: "onboarding.mac.side.privacy", defaultValue: "Privacy & Security", bundle: bundle, locale: locale, comment: "Preview of System Settings' sidebar (selected)"),
         String(localized: "onboarding.mac.side.notifications", defaultValue: "Notifications", bundle: bundle, locale: locale, comment: "Preview of System Settings' sidebar"),
         String(localized: "onboarding.mac.side.sound", defaultValue: "Sound", bundle: bundle, locale: locale, comment: "Preview of System Settings' sidebar")]
    }
    static var paneAccessibility: String { axNamed(String(localized: "onboarding.mac.pane.ax", defaultValue: "Accessibility", bundle: bundle, locale: locale, comment: "Preview of System Settings: the list's title")) }
    /// The list's own description in the preview: macOS 27 words it anew with the new name (its own sentence, both languages).
    static var paneAccessibilityDesc: String {
        guard ArisFix.Pane.osMajor >= 27 else { return String(localized: "onboarding.mac.pane.ax.desc", defaultValue: "Allow the applications below to control your computer.", bundle: bundle, locale: locale, comment: "Preview of System Settings: the list's description") }
        return language == "ko" ? "이 접근 권한이 있는 앱은 이메일 열람 및 전송, 연락처 및 사진 편집, 키보드 모니터링, 웹사이트 추적, 화면 녹화, Mac의 앱 제어 등을 수행할 수 있습니다."
            : "Apps with this access can view and send email, edit contacts and photos, monitor your keyboard, track websites, record your screen, control any app on your Mac, and more."
    }
    static var paneScreen: String { String(localized: "onboarding.mac.pane.screen", defaultValue: "Screen & System Audio Recording", bundle: bundle, locale: locale, comment: "Preview of System Settings: the list's title") }
    static var paneScreenDesc: String { String(localized: "onboarding.mac.pane.screen.desc", defaultValue: "Allow the applications below to record the content of your screen and audio.", bundle: bundle, locale: locale, comment: "Preview of System Settings: the list's description") }
    static var paneOtherApp: String { String(localized: "onboarding.mac.pane.other", defaultValue: "Other app", bundle: bundle, locale: locale, comment: "Preview of System Settings: a stand-in app already in the list") }

    // MARK: - The drag panel beside System Settings

    static func dragInstruction(screen: Bool) -> String {
        screen ? String(localized: "onboarding.drag.screen", defaultValue: "Drag Aris into the Screen & System Audio Recording list, then turn its switch on.", bundle: bundle, locale: locale, comment: "Drag panel beside System Settings")
            : axNamed(String(localized: "onboarding.drag.ax", defaultValue: "Drag Aris into the Accessibility list, then turn its switch on.", bundle: bundle, locale: locale, comment: "Drag panel beside System Settings"))
    }

    static func dragDone(screen: Bool) -> String {
        screen ? String(localized: "onboarding.drag.screen.done", defaultValue: "Screen Recording is on.", bundle: bundle, locale: locale, comment: "Drag panel once granted")
            : axNamed(String(localized: "onboarding.drag.ax.done", defaultValue: "Accessibility is on.", bundle: bundle, locale: locale, comment: "Drag panel once granted"))
    }

    static var dragHint: String { String(localized: "onboarding.drag.hint", defaultValue: "Drag", bundle: bundle, locale: locale, comment: "Drag panel: the app row's hint") }
    static var dragAllowed: String { String(localized: "onboarding.drag.allowed", defaultValue: "Allowed", bundle: bundle, locale: locale, comment: "Drag panel: the app row once granted") }
    static var dragHelp: String { String(localized: "onboarding.drag.help", defaultValue: "Drag this row into the list in System Settings", bundle: bundle, locale: locale, comment: "Drag panel: tooltip") }
    static var dragClose: String { String(localized: "onboarding.drag.close", defaultValue: "Close", bundle: bundle, locale: locale, comment: "Drag panel: close button") }

    // MARK: - 단축키

    static func shortcutTitle(_ keys: String) -> String { String(localized: "onboarding.shortcut.title", defaultValue: "Press \(keys)", bundle: bundle, locale: locale, comment: "Shortcut page heading; the argument is the talk shortcut, e.g. ⌥ Space") }
    static func shortcutNarration(_ keys: String) -> String { String(localized: "onboarding.shortcut.narration", defaultValue: "Press \(keys) and I'll listen. Give it a try.", bundle: bundle, locale: locale, comment: "The notch says this on the shortcut page") }
    static var shortcutQuestion: String { String(localized: "onboarding.shortcut.question", defaultValue: "Do the keys light up blue while you hold them?", bundle: bundle, locale: locale, comment: "Shortcut page card") }
    static var shortcutYes: String { String(localized: "onboarding.shortcut.yes", defaultValue: "Yes", bundle: bundle, locale: locale, comment: "Shortcut page: the keys lit") }
    static var shortcutChange: String { String(localized: "onboarding.shortcut.change", defaultValue: "No, I'll change the key", bundle: bundle, locale: locale, comment: "Shortcut page: opens Settings at the shortcut") }
    static var shortcutChanged: String { String(localized: "onboarding.shortcut.changed", defaultValue: "Change it in Settings › Shortcuts, then press it here.", bundle: bundle, locale: locale, comment: "Shortcut page note after opening Settings") }
    static func keysLabel(_ keys: String) -> String { String(localized: "onboarding.shortcut.keys", defaultValue: "The \(keys) keys", bundle: bundle, locale: locale, comment: "VoiceOver: the keycaps") }

    static func keyName(_ symbol: String) -> String {
        switch symbol {
        case "⌥": String(localized: "onboarding.key.option", defaultValue: "option", bundle: bundle, locale: locale, comment: "Keycap legend, as on the Mac keyboard")
        case "⌘": String(localized: "onboarding.key.command", defaultValue: "command", bundle: bundle, locale: locale, comment: "Keycap legend")
        case "⌃": String(localized: "onboarding.key.control", defaultValue: "control", bundle: bundle, locale: locale, comment: "Keycap legend")
        case "⇧": String(localized: "onboarding.key.shift", defaultValue: "shift", bundle: bundle, locale: locale, comment: "Keycap legend")
        case "Space": String(localized: "onboarding.key.space", defaultValue: "space", bundle: bundle, locale: locale, comment: "Keycap legend")
        default: ""
        }
    }

    // MARK: - 물어보기

    static var askTitle: String { String(localized: "onboarding.ask.title", defaultValue: "Ask me something simple", bundle: bundle, locale: locale, comment: "Ask page heading") }
    static func askHow(_ keys: String) -> String { String(localized: "onboarding.ask.how", defaultValue: "Hold \(keys) and say:", bundle: bundle, locale: locale, comment: "Ask page card; the argument is the talk shortcut") }
    static var askLine: String { String(localized: "onboarding.ask.line", defaultValue: "What time is it?", bundle: bundle, locale: locale, comment: "Ask page: the example question, lit word by word as Aris hears it; one that needs no permission (a new Mac has not been asked for Calendars)") }
    static var askHold: String { String(localized: "onboarding.ask.hold", defaultValue: "Hold to talk", bundle: bundle, locale: locale, comment: "Ask page: press and hold to talk to Aris") }
    static var askNarration: String { String(localized: "onboarding.ask.narration", defaultValue: "Ask, and I'll answer right here in the notch.", bundle: bundle, locale: locale, comment: "The notch says this on the ask page") }

    // MARK: - AI 고르기

    static var brainTitle: String { String(localized: "onboarding.brain.title", defaultValue: "Which AI should answer?", bundle: bundle, locale: locale, comment: "AI page heading") }
    static var brainNarration: String { String(localized: "onboarding.brain.narration", defaultValue: "Pick the AI I answer with.", bundle: bundle, locale: locale, comment: "The notch says this on the AI page") }

    /// What the page says over the rows: some AI is set up, none is, or the agent didn't answer.
    static func brainHeading(_ heading: ArisOnboardingBrainRows.Heading) -> String {
        switch heading {
        case .some: String(localized: "onboarding.brain.some", defaultValue: "These are on this Mac. Pick the one that answers by default; you can change it later in Settings.", bundle: bundle, locale: locale, comment: "AI page: at least one AI is set up")
        case .none: String(localized: "onboarding.brain.none", defaultValue: "No AI is set up on this Mac yet, so I can't answer questions. Get one of these ready, or continue and add one later in Settings › AI services.", bundle: bundle, locale: locale, comment: "AI page: no AI is set up on this Mac")
        case .unknown: String(localized: "onboarding.brain.unknown", defaultValue: "I couldn't check which AIs are set up right now. You can pick one later in Settings › AI services.", bundle: bundle, locale: locale, comment: "AI page: the agent did not answer")
        }
    }

    /// The products' own names; only the API row's is Aris's word.
    static func brainName(_ brain: ArisBrain) -> String {
        switch brain {
        case .claude: "Claude"
        case .codex: "GPT (Codex)"
        case .antigravity: "Gemini (Antigravity)"
        case .api: String(localized: "onboarding.brain.name.api", defaultValue: "API key", bundle: bundle, locale: locale, comment: "AI page row: an API provider with the user's own key")
        }
    }

    /// Under a row's name: that it answers, what the agent found (its tool installed, or an API key saved; whether the
    /// tool is signed in only shows at the first question), or plainly how to get it.
    static func brainDetail(_ row: ArisOnboardingBrainRows.Row) -> String {
        switch row.state {
        case .chosen: String(localized: "onboarding.brain.chosen", defaultValue: "Answers by default", bundle: bundle, locale: locale, comment: "AI page row: the one that answers")
        case .ready where row.brain == .api: String(localized: "onboarding.brain.ready.api", defaultValue: "Key saved", bundle: bundle, locale: locale, comment: "AI page row: an API provider's key is saved")
        case .ready: String(localized: "onboarding.brain.ready", defaultValue: "Installed on this Mac", bundle: bundle, locale: locale, comment: "AI page row: the AI's own tool is installed")
        case .missing, .unknown: brainHow(row.brain)
        }
    }

    static func brainHow(_ brain: ArisBrain) -> String {
        switch brain {
        case .claude: String(localized: "onboarding.brain.how.claude", defaultValue: "Install Claude Code, then run “claude” once in Terminal to sign in.", bundle: bundle, locale: locale, comment: "AI page row: how to get Claude ready")
        case .codex: String(localized: "onboarding.brain.how.codex", defaultValue: "Install Codex, then run “codex login” in Terminal to sign in with ChatGPT.", bundle: bundle, locale: locale, comment: "AI page row: how to get Codex ready")
        case .antigravity: String(localized: "onboarding.brain.how.antigravity", defaultValue: "Install Antigravity, then run “agy” once in Terminal to sign in.", bundle: bundle, locale: locale, comment: "AI page row: how to get Antigravity ready")
        case .api: String(localized: "onboarding.brain.how.api", defaultValue: "Paste a key from OpenAI, Anthropic, Gemini, DeepSeek or another provider.", bundle: bundle, locale: locale, comment: "AI page row: how to use an API key")
        }
    }

    static var brainRecommended: String { String(localized: "onboarding.brain.recommended", defaultValue: "Recommended", bundle: bundle, locale: locale, comment: "AI page row: beside the recommended AI's name") }
    static var brainProvider: String { String(localized: "onboarding.brain.api.provider", defaultValue: "Provider", bundle: bundle, locale: locale, comment: "AI page: the API provider menu (VoiceOver)") }
    static var brainKeyPlaceholder: String { String(localized: "onboarding.brain.api.placeholder", defaultValue: "Paste the API key", bundle: bundle, locale: locale, comment: "AI page: the key field's placeholder") }
    static var brainKeySave: String { String(localized: "onboarding.brain.api.save", defaultValue: "Save", bundle: bundle, locale: locale, comment: "AI page: saves the key") }
    static var brainKeySaving: String { String(localized: "onboarding.brain.api.saving", defaultValue: "Saving…", bundle: bundle, locale: locale, comment: "AI page: while the key is saved") }
    static func brainKeyWhere(_ source: String) -> String { String(localized: "onboarding.brain.api.where", defaultValue: "Get a key at \(source). It is kept only in this Mac's Keychain.", bundle: bundle, locale: locale, comment: "AI page: where the provider's keys come from; the argument is the place") }
    static var brainKeyKept: String { String(localized: "onboarding.brain.api.kept", defaultValue: "The key is kept only in this Mac's Keychain.", bundle: bundle, locale: locale, comment: "AI page: under the key field before a provider is chosen") }
    static var brainKeyEmpty: String { String(localized: "onboarding.brain.api.empty", defaultValue: "Paste a key first.", bundle: bundle, locale: locale, comment: "AI page: Save pressed with no key") }
    static var brainKeyFailed: String { String(localized: "onboarding.brain.api.failed", defaultValue: "The key couldn't be saved. Check it and try again.", bundle: bundle, locale: locale, comment: "AI page: the agent refused the key") }
    static var brainAgain: String { String(localized: "onboarding.brain.again", defaultValue: "Check again", bundle: bundle, locale: locale, comment: "AI page: asks again which AIs are set up") }
    static var brainChecking: String { String(localized: "onboarding.brain.checking", defaultValue: "Checking…", bundle: bundle, locale: locale, comment: "AI page: while asking which AIs are set up") }

    // MARK: - 아리스라고 부르기

    static var wakeTitle: String { String(localized: "onboarding.wake.title", defaultValue: "Call me by saying “Aris”?", bundle: bundle, locale: locale, comment: "Wake word page heading") }
    static var wakeNarration: String { String(localized: "onboarding.wake.narration", defaultValue: "You can call me by name, too.", bundle: bundle, locale: locale, comment: "The notch says this on the wake word page") }
    static var wakeHow: String { String(localized: "onboarding.wake.how", defaultValue: "Say “Aris” and I start listening, with no shortcut.", bundle: bundle, locale: locale, comment: "Wake word page card: what turning it on does") }
    static var wakeHonest: String { String(localized: "onboarding.wake.honest", defaultValue: "If you turn this on, the microphone stays on to listen for the name. It listens on this Mac, and nothing is sent anywhere until it hears “Aris”.", bundle: bundle, locale: locale, comment: "Wake word page: the honest cost of turning it on") }
    static var wakeChange: String { String(localized: "onboarding.wake.change", defaultValue: "You can change this any time in Settings.", bundle: bundle, locale: locale, comment: "Wake word page: under the honest line") }
    static var wakeYes: String { String(localized: "onboarding.wake.yes", defaultValue: "Yes, turn it on", bundle: bundle, locale: locale, comment: "Wake word page: turns the wake word on") }
    static var wakeNo: String { String(localized: "onboarding.wake.no", defaultValue: "No, just the shortcut", bundle: bundle, locale: locale, comment: "Wake word page: leaves the wake word off") }

    // MARK: - 받아쓰기

    static var dictateTitle: String { String(localized: "onboarding.dictate.title", defaultValue: "Dictation", bundle: bundle, locale: locale, comment: "Dictation page heading") }
    static var dictateLead: String { String(localized: "onboarding.dictate.lead", defaultValue: "In any app, hold the right ⌥ and talk. Let go, and I'll type it, tidied up.", bundle: bundle, locale: locale, comment: "Dictation page body") }
    static var dictateNarration: String { String(localized: "onboarding.dictate.narration", defaultValue: "Speak, and I'll tidy up the filler.", bundle: bundle, locale: locale, comment: "The notch says this on the dictation page") }
    static var finish: String { String(localized: "onboarding.dictate.finish", defaultValue: "Finish", bundle: bundle, locale: locale, comment: "Dictation page: ends the setup") }
    static var note: String { String(localized: "onboarding.dictate.note", defaultValue: "Note", bundle: bundle, locale: locale, comment: "Dictation page: the practice note's title") }
    static var noteHint: String { String(localized: "onboarding.dictate.noteHint", defaultValue: "I'll type here. Say anything you like.", bundle: bundle, locale: locale, comment: "Dictation page: under the practice note") }
    static var dictateStart: String { String(localized: "onboarding.dictate.start", defaultValue: "Click here to start", bundle: bundle, locale: locale, comment: "Dictation page: starts a real dictation into the note") }
    static var dictateStop: String { String(localized: "onboarding.dictate.stop", defaultValue: "Done talking", bundle: bundle, locale: locale, comment: "Dictation page: ends the dictation") }

    // MARK: - The finish

    static func finishLine(name: String?) -> String {
        guard let name else {
            return String(localized: "onboarding.finish.line", defaultValue: "I'll be right here. Call me anytime.", bundle: bundle, locale: locale, comment: "The notch's last line as the setup closes")
        }
        return String(localized: "onboarding.finish.line.named", defaultValue: "I'll be right here, \(name). Call me anytime.", bundle: bundle, locale: locale, comment: "The notch's last line as the setup closes; the argument is the name the user gave")
    }
}
