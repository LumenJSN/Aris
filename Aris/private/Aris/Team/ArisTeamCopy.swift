//
//  ArisTeamCopy.swift
//  Aris
//
//  Every word of the teammates redesign (the 팀원 page's layout A, the templates, 말로 팀원 만들기, the suggestion and
//  앱 노하우), from Aris/Localizable.xcstrings in Korean and English, in the app's one UI language (ArisUILanguage).
//  The English defaults stand in only where no catalog is bundled (the tests). tests/team-strings-lint.py checks that
//  every key has both languages.
//

import Foundation

enum ArisTeamCopy {
    static let languages: Set<String> = ["ko", "en"]

    /// The language, chosen once: the app's one UI language (ArisUILanguage).
    nonisolated(unsafe) static var language: String = ArisUILanguage.code
    nonisolated(unsafe) static var bundle: Bundle = lproj(language, in: .main)

    static func lproj(_ language: String, in bundle: Bundle) -> Bundle {
        bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? bundle
    }

    static var locale: Locale { Locale(identifier: language) }
    static var korean: Bool { language == "ko" }

    /// Picks the language again (the offscreen renders).
    static func use(_ code: String, in main: Bundle = .main) {
        language = code
        bundle = lproj(code, in: main)
    }

    // MARK: - Faces (the 팀원 page's pickers and stage, N9)

    /// A face type's name; nil for a type the pickers don't know.
    static func faceName(_ type: String) -> String? {
        switch type {
        case "star": String(localized: "team.face.name.star", defaultValue: "star", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "clover": String(localized: "team.face.name.clover", defaultValue: "clover", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "flower": String(localized: "team.face.name.flower", defaultValue: "flower", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "triangle": String(localized: "team.face.name.triangle", defaultValue: "triangle", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "square": String(localized: "team.face.name.square", defaultValue: "square", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "blob": String(localized: "team.face.name.blob", defaultValue: "blob", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "ghost": String(localized: "team.face.name.ghost", defaultValue: "ghost", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "circle": String(localized: "team.face.name.circle", defaultValue: "circle", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "drop": String(localized: "team.face.name.drop", defaultValue: "drop", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "droid": String(localized: "team.face.name.droid", defaultValue: "droid", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "mech": String(localized: "team.face.name.mech", defaultValue: "mech", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "alien": String(localized: "team.face.name.alien", defaultValue: "alien", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "hexagon": String(localized: "team.face.name.hexagon", defaultValue: "hexagon", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "cat": String(localized: "team.face.name.cat", defaultValue: "cat", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "cloud": String(localized: "team.face.name.cloud", defaultValue: "cloud", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "pill": String(localized: "team.face.name.pill", defaultValue: "pill", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "pebble": String(localized: "team.face.name.pebble", defaultValue: "pebble", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        case "puddle": String(localized: "team.face.name.puddle", defaultValue: "puddle", bundle: bundle, locale: locale, comment: "A face type's name in the pickers")
        default: nil
        }
    }

    static func shadingName(_ shading: String) -> String? {
        switch shading {
        case "fabric": String(localized: "team.face.shading.fabric", defaultValue: "Fabric", bundle: bundle, locale: locale, comment: "A texture in the face picker")
        case "plastic": String(localized: "team.face.shading.plastic", defaultValue: "Plastic", bundle: bundle, locale: locale, comment: "A texture in the face picker")
        case "crisp": String(localized: "team.face.shading.crisp", defaultValue: "Crisp", bundle: bundle, locale: locale, comment: "A texture in the face picker")
        case "smooth": String(localized: "team.face.shading.smooth", defaultValue: "Smooth", bundle: bundle, locale: locale, comment: "A texture in the face picker")
        case "flat": String(localized: "team.face.shading.flat", defaultValue: "Flat", bundle: bundle, locale: locale, comment: "A texture in the face picker")
        default: nil
        }
    }

    /// The line for a teammate moved off the face Aris took. The pieces come with their particles already on in Korean
    /// (ArisFace.notice), so the catalog's Korean is only "%@도 %@. 이제 %@ %@.".
    static func faceNotice(name: String, was: String, then: String, now: String) -> String {
        String(localized: "team.face.notice", defaultValue: "\(name) was the \(was) too. Now \(then) is the \(now).", bundle: bundle, locale: locale, comment: "The 팀원 page's line for a teammate moved off the face Aris took: the teammate, Aris's face (ko: with its 이었어요/였어요), the teammate again (ko: with 은/는), its new face (ko: with 이에요/예요)")
    }
    static func faceNoticeAction(_ name: String) -> String { String(localized: "team.face.notice.action", defaultValue: "Pick \(name)'s face", bundle: bundle, locale: locale, comment: "The button beside that line: the teammate's name") }
    static var faceTypeHeading: String { String(localized: "team.face.heading.type", defaultValue: "Type", bundle: bundle, locale: locale, comment: "Face picker heading (a teammate's)") }
    static var faceHeading: String { String(localized: "team.face.heading.face", defaultValue: "Face", bundle: bundle, locale: locale, comment: "Face picker heading (Aris's)") }
    static var faceColorHeading: String { String(localized: "team.face.heading.color", defaultValue: "Color", bundle: bundle, locale: locale, comment: "Face picker heading") }
    static var faceTexture: String { String(localized: "team.face.heading.texture", defaultValue: "Texture", bundle: bundle, locale: locale, comment: "Face picker heading and its control's VoiceOver label") }
    static func faceColor(_ hex: String) -> String { String(localized: "team.face.color", defaultValue: "Color \(hex)", bundle: bundle, locale: locale, comment: "VoiceOver: a colour tile; the argument is its hex") }
    static var faceOwnColor: String { String(localized: "team.face.color.own", defaultValue: "Default color", bundle: bundle, locale: locale, comment: "VoiceOver: the face's own colour tile") }
    static var faceInNotch: String { String(localized: "team.face.where.notch", defaultValue: "In the notch", bundle: bundle, locale: locale, comment: "Above the face preview drawn on the dark notch") }
    static var faceOnWindow: String { String(localized: "team.face.where.window", defaultValue: "On a window", bundle: bundle, locale: locale, comment: "Above the face preview drawn on a light window") }
    static var facePoolTitle: String { String(localized: "team.face.pool.title", defaultValue: "Faces teammates get", bundle: bundle, locale: locale, comment: "Heading of the faces new teammates are given") }
    static var facePoolDetail: String { String(localized: "team.face.pool.detail", defaultValue: "The face Aris picks leaves the teammates' choices, and the star takes its place. Other teammates keep their faces.", bundle: bundle, locale: locale, comment: "Under that heading") }
    static func facePoolLabel(_ faces: String) -> String { String(localized: "team.face.pool.label", defaultValue: "Faces teammates get: \(faces)", bundle: bundle, locale: locale, comment: "VoiceOver: the faces, comma separated") }
    static var faceStagePreview: String { String(localized: "team.face.stage.preview", defaultValue: "Preview", bundle: bundle, locale: locale, comment: "The face stage's corner label and its control's VoiceOver label") }
    static func faceStageLabel(_ caption: String) -> String { String(localized: "team.face.stage.label", defaultValue: "Aris's face preview: \(caption)", bundle: bundle, locale: locale, comment: "VoiceOver: the face stage; the argument is its caption") }
    static var faceStageAuto: String { String(localized: "team.face.stage.auto", defaultValue: "Auto", bundle: bundle, locale: locale, comment: "Face stage: cycle through the moods") }
    static var faceStageRest: String { String(localized: "team.face.stage.rest", defaultValue: "Resting", bundle: bundle, locale: locale, comment: "Face stage: at rest") }
    static var faceStageListen: String { String(localized: "team.face.stage.listen", defaultValue: "Listening", bundle: bundle, locale: locale, comment: "Face stage: listening") }
    static var faceStageWork: String { String(localized: "team.face.stage.work", defaultValue: "Working", bundle: bundle, locale: locale, comment: "Face stage: working") }
    static var faceStageRestCaption: String { String(localized: "team.face.stage.rest.caption", defaultValue: "Resting · waits beside the camera", bundle: bundle, locale: locale, comment: "Face stage caption") }
    static var faceStageListenCaption: String { String(localized: "team.face.stage.listen.caption", defaultValue: "Listening · the band widens and it looks up", bundle: bundle, locale: locale, comment: "Face stage caption") }
    static var faceStageWorkCaption: String { String(localized: "team.face.stage.work.caption", defaultValue: "Working · works in the pill under the notch", bundle: bundle, locale: locale, comment: "Face stage caption") }
    static var faceStageWorkLine: String { String(localized: "team.face.stage.workLine", defaultValue: "Sorting mail", bundle: bundle, locale: locale, comment: "Face stage: the working pill's sample line") }

    // MARK: - Templates

    static var tplDocs: String { String(localized: "team.tpl.docs", defaultValue: "Documents", bundle: bundle, locale: locale, comment: "Template label") }
    static var tplDocsName: String { String(localized: "team.tpl.docs.name", defaultValue: "Page", bundle: bundle, locale: locale, comment: "Template's teammate name") }
    static var tplDocsRouting: String { String(localized: "team.tpl.docs.routing", defaultValue: "When drafting or polishing documents, emails or slides", bundle: bundle, locale: locale, comment: "When to call: documents") }
    static var tplDocsHow: String { String(localized: "team.tpl.docs.how", defaultValue: "Show a short draft first and ask what to change.\nUse a title and subheadings; keep paragraphs to three lines.\nAlways check with me before sending anything.", bundle: bundle, locale: locale, comment: "How to work: documents") }
    static var tplResearch: String { String(localized: "team.tpl.research", defaultValue: "Researcher", bundle: bundle, locale: locale, comment: "Template label") }
    static var tplResearchName: String { String(localized: "team.tpl.research.name", defaultValue: "Tam", bundle: bundle, locale: locale, comment: "Template's teammate name") }
    static var tplResearchRouting: String { String(localized: "team.tpl.research.routing", defaultValue: "When something needs looking up, comparing and summing up", bundle: bundle, locale: locale, comment: "When to call: research") }
    static var tplResearchHow: String { String(localized: "team.tpl.research.how", defaultValue: "Always cite sources. Show differing views side by side.\nPut the conclusion first, in three lines.", bundle: bundle, locale: locale, comment: "How to work: research") }
    static var tplCode: String { String(localized: "team.tpl.code", defaultValue: "Coding", bundle: bundle, locale: locale, comment: "Template label") }
    static var tplCodeName: String { String(localized: "team.tpl.code.name", defaultValue: "Build", bundle: bundle, locale: locale, comment: "Template's teammate name") }
    static var tplCodeRouting: String { String(localized: "team.tpl.code.routing", defaultValue: "When fixing code, testing, or hunting bugs", bundle: bundle, locale: locale, comment: "When to call: coding") }
    static var tplCodeHow: String { String(localized: "team.tpl.code.how", defaultValue: "Say what you will change before changing it.\nRun the tests and report the results too.", bundle: bundle, locale: locale, comment: "How to work: coding") }
    static var tplSchedule: String { String(localized: "team.tpl.schedule", defaultValue: "Scheduler", bundle: bundle, locale: locale, comment: "Template label") }
    static var tplScheduleName: String { String(localized: "team.tpl.schedule.name", defaultValue: "Haru", bundle: bundle, locale: locale, comment: "Template's teammate name") }
    static var tplScheduleRouting: String { String(localized: "team.tpl.schedule.routing", defaultValue: "When booking or moving events, or sorting out to-dos", bundle: bundle, locale: locale, comment: "When to call: schedule") }
    static var tplScheduleHow: String { String(localized: "team.tpl.schedule.how", defaultValue: "Tell me first when events overlap.\nSay times as a.m. and p.m.", bundle: bundle, locale: locale, comment: "How to work: schedule") }
    static var tplCalc: String { String(localized: "team.tpl.calc", defaultValue: "Calculator", bundle: bundle, locale: locale, comment: "Template label (made in words only)") }
    static var tplCalcName: String { String(localized: "team.tpl.calc.name", defaultValue: "Calc", bundle: bundle, locale: locale, comment: "Template's teammate name") }
    static var tplCalcRouting: String { String(localized: "team.tpl.calc.routing", defaultValue: "When numbers need working out", bundle: bundle, locale: locale, comment: "When to call: calculation") }
    static var tplCalcHow: String { String(localized: "team.tpl.calc.how", defaultValue: "Put the answer first, then the working in a line or two.", bundle: bundle, locale: locale, comment: "How to work: calculation") }
    /// A teammate made in words whose role fits no template: called by its name (never the spoken role).
    static func routingByName(_ name: String) -> String {
        String(localized: "team.routing.byname", defaultValue: "When called by name (\(name))", bundle: bundle, locale: locale, comment: "Routing for a teammate made in words with no matching template: %@ is its name")
    }
    static var tplBlank: String { String(localized: "team.tpl.blank", defaultValue: "Blank teammate", bundle: bundle, locale: locale, comment: "Template label") }
    static var tplBlankName: String { String(localized: "team.tpl.blank.name", defaultValue: "Teammate", bundle: bundle, locale: locale, comment: "A blank teammate's name") }
    static var tplBlankLine: String { String(localized: "team.tpl.blank.line", defaultValue: "Set everything up yourself", bundle: bundle, locale: locale, comment: "Template menu: the blank one's line") }
    static var genericHow: String { String(localized: "team.tpl.generic.how", defaultValue: "See the job through, then say briefly what you did.", bundle: bundle, locale: locale, comment: "How to work for a teammate made by voice whose role fits no template") }

    // MARK: - Made by voice or text (the notch card)

    static func made(_ name: String) -> String {
        String(localized: "team.made.said", defaultValue: "I made \(name).", bundle: bundle, locale: locale, comment: "Spoken after a teammate was made by voice")
    }
    static func madeAsk(_ name: String) -> String {
        String(localized: "team.made.ask", defaultValue: "Shall I make \(name)?", bundle: bundle, locale: locale, comment: "Said with the made card, before saving")
    }
    static var cancel: String { String(localized: "team.made.cancel", defaultValue: "Cancel", bundle: bundle, locale: locale, comment: "Made card: drops it") }
    static var madePress: String { String(localized: "team.made.press", defaultValue: "Press OK on the card to make it.", bundle: bundle, locale: locale, comment: "A spoken yes that can't count (hands-free)") }
    static var madeDropped: String { String(localized: "team.made.dropped", defaultValue: "OK, I won't make it.", bundle: bundle, locale: locale, comment: "Said after a no to the new-teammate card") }
    static func removeTitle(_ name: String) -> String {
        String(localized: "team.remove.title", defaultValue: "Remove \(name)", bundle: bundle, locale: locale, comment: "Remove-teammate card's title: %@ is its name")
    }
    static var removeDetail: String { String(localized: "team.remove.detail", defaultValue: "This teammate's name and face are removed.", bundle: bundle, locale: locale, comment: "Remove-teammate card") }
    static func removed(_ name: String) -> String {
        String(localized: "team.remove.done", defaultValue: "I removed \(name) from the team.", bundle: bundle, locale: locale, comment: "Said after removing: %@ is its name")
    }
    static func removeFailed(_ name: String) -> String {
        String(localized: "team.remove.failed", defaultValue: "I couldn't save that, so \(name) is still on the team. Please try again in Settings › Teammates.", bundle: bundle, locale: locale, comment: "Removing by voice, but the save failed: %@ is its name")
    }
    static var removeKept: String { String(localized: "team.remove.kept", defaultValue: "OK, I left them on the team.", bundle: bundle, locale: locale, comment: "Said after a no to removing") }
    static var removeNone: String { String(localized: "team.remove.none", defaultValue: "There's no teammate by that name.", bundle: bundle, locale: locale, comment: "Removing a name nobody has") }
    static var removeFixed: String { String(localized: "team.remove.fixed", defaultValue: "Claude Code can't be removed.", bundle: bundle, locale: locale, comment: "Removing Claude Code") }
    static var madeTitle: String { String(localized: "team.made.title", defaultValue: "New teammate", bundle: bundle, locale: locale, comment: "The made card's kicker") }
    static var edit: String { String(localized: "team.made.edit", defaultValue: "Edit", bundle: bundle, locale: locale, comment: "Made card: opens Settings › Teammates on it") }
    static var done: String { String(localized: "team.made.done", defaultValue: "OK", bundle: bundle, locale: locale, comment: "Made card: closes it") }
    static var madeFailed: String { String(localized: "team.made.failed", defaultValue: "I couldn't save the teammate. Please try again in Settings › Teammates.", bundle: bundle, locale: locale, comment: "Made by voice, but the save failed") }
    static var madeFull: String { String(localized: "team.made.full", defaultValue: "You already have the most teammates Aris keeps.", bundle: bundle, locale: locale, comment: "Made by voice, but the list is full") }

    // MARK: - The suggestion

    static func suggest(_ role: String) -> String {
        String(localized: "team.suggest.ask", defaultValue: "You do this kind of thing often. Shall I set up a \(role) teammate?", bundle: bundle, locale: locale, comment: "Asked once per kind after several such jobs: %@ is a template label")
    }
    static var suggestTitle: String { String(localized: "team.suggest.title", defaultValue: "Make a teammate?", bundle: bundle, locale: locale, comment: "The suggestion card's title") }
    static var suggestLater: String { String(localized: "team.suggest.no", defaultValue: "OK, I won't ask again.", bundle: bundle, locale: locale, comment: "Said after a no to the suggestion") }

    // MARK: - Scopes

    static func scopeTitle(_ scope: ArisTeammateScope) -> String {
        switch scope {
        case .files: String(localized: "team.scope.files", defaultValue: "Files", bundle: bundle, locale: locale, comment: "Scope")
        case .web: String(localized: "team.scope.web", defaultValue: "Web", bundle: bundle, locale: locale, comment: "Scope")
        case .aside: String(localized: "team.scope.aside", defaultValue: "Use websites (Aside)", bundle: bundle, locale: locale, comment: "Scope")
        case .send: String(localized: "team.scope.send", defaultValue: "Send", bundle: bundle, locale: locale, comment: "Scope")
        case .apps: String(localized: "team.scope.apps", defaultValue: "Use apps", bundle: bundle, locale: locale, comment: "Scope")
        case .mail: String(localized: "team.scope.mail", defaultValue: "Read mail and messages", bundle: bundle, locale: locale, comment: "Scope")
        case .calendar: String(localized: "team.scope.calendar", defaultValue: "Calendar and reminders", bundle: bundle, locale: locale, comment: "Scope")
        case .terminal: String(localized: "team.scope.terminal", defaultValue: "Terminal", bundle: bundle, locale: locale, comment: "Scope")
        }
    }

    static func scopeDetail(_ scope: ArisTeammateScope) -> String {
        switch scope {
        case .files: String(localized: "team.scope.files.d", defaultValue: "Reads files in your folders and makes new ones", bundle: bundle, locale: locale, comment: "Scope detail")
        case .web: String(localized: "team.scope.web.d", defaultValue: "Searches and reads pages", bundle: bundle, locale: locale, comment: "Scope detail")
        case .aside: String(localized: "team.scope.aside.d", defaultValue: "Works on your signed-in sites through Aside", bundle: bundle, locale: locale, comment: "Scope detail")
        case .send: String(localized: "team.scope.send.d", defaultValue: "Sends messages and mail (asks with a card every time)", bundle: bundle, locale: locale, comment: "Scope detail")
        case .apps: String(localized: "team.scope.apps.d", defaultValue: "Looks at the screen, clicks and types", bundle: bundle, locale: locale, comment: "Scope detail")
        case .mail: String(localized: "team.scope.mail.d", defaultValue: "Reads the mail and messages you got", bundle: bundle, locale: locale, comment: "Scope detail")
        case .calendar: String(localized: "team.scope.calendar.d", defaultValue: "Sees and makes events and to-dos", bundle: bundle, locale: locale, comment: "Scope detail")
        case .terminal: String(localized: "team.scope.terminal.d", defaultValue: "Runs commands in a project folder", bundle: bundle, locale: locale, comment: "Scope detail")
        }
    }

    // MARK: - The 팀원 page (layout A)

    static var pageNote: String { String(localized: "team.page.note", defaultValue: "Set when each teammate is called, how it works, and which brain it uses for what. Aris can change its face here too.", bundle: bundle, locale: locale, comment: "The 팀원 page's note") }
    static var sectionWho: String { String(localized: "team.sec.who", defaultValue: "Name and face", bundle: bundle, locale: locale, comment: "Section") }
    static var sectionWhen: String { String(localized: "team.sec.when", defaultValue: "When to call", bundle: bundle, locale: locale, comment: "Section") }
    static var sectionHow: String { String(localized: "team.sec.how", defaultValue: "How to work", bundle: bundle, locale: locale, comment: "Section") }
    static var sectionBrain: String { String(localized: "team.sec.brain", defaultValue: "Brain", bundle: bundle, locale: locale, comment: "Section") }
    static var sectionScopes: String { String(localized: "team.sec.scopes", defaultValue: "What it may use", bundle: bundle, locale: locale, comment: "Section") }
    static var sectionMemory: String { String(localized: "team.sec.memory", defaultValue: "Memory", bundle: bundle, locale: locale, comment: "Section") }
    static var name: String { String(localized: "team.field.name", defaultValue: "Name", bundle: bundle, locale: locale, comment: "Field label") }
    static var face: String { String(localized: "team.field.face", defaultValue: "Face", bundle: bundle, locale: locale, comment: "Field label") }
    static var whenPlaceholder: String { String(localized: "team.when.placeholder", defaultValue: "e.g. When drafting documents or emails", bundle: bundle, locale: locale, comment: "Placeholder") }
    static var whenHint: String { String(localized: "team.when.hint", defaultValue: "Aris reads this line to hand out work. The more specific, the better it fits.", bundle: bundle, locale: locale, comment: "Hint under 언제 부를까요") }
    static var probeLabel: String { String(localized: "team.probe.label", defaultValue: "Who would take this?", bundle: bundle, locale: locale, comment: "The routing test line's label") }
    static var probePlaceholder: String { String(localized: "team.probe.placeholder", defaultValue: "e.g. Draft the report", bundle: bundle, locale: locale, comment: "The routing test line's placeholder") }
    static var probeNobody: String { String(localized: "team.probe.nobody", defaultValue: "No teammate fits, so Aris does it itself", bundle: bundle, locale: locale, comment: "Routing test: nobody") }
    static var probeNotThis: String { String(localized: "team.probe.notthis", defaultValue: "not this teammate", bundle: bundle, locale: locale, comment: "Routing test: someone else") }
    static var howPlaceholder: String { String(localized: "team.how.placeholder", defaultValue: "Tone, the shape of the result, rules to keep.", bundle: bundle, locale: locale, comment: "Placeholder") }
    static var howHint: String { String(localized: "team.how.hint", defaultValue: "This teammate reads it with every job.", bundle: bundle, locale: locale, comment: "Hint under 어떻게 일할까요") }
    static var signedIn: String { String(localized: "team.brain.ready", defaultValue: "Set up on this Mac", bundle: bundle, locale: locale, comment: "Brain row: ready") }
    static var loginNeeded: String { String(localized: "team.brain.login.needed", defaultValue: "Login needed", bundle: bundle, locale: locale, comment: "Chip") }
    static var login: String { String(localized: "team.brain.login", defaultValue: "Log in", bundle: bundle, locale: locale, comment: "Button") }
    static var apiLoginHint: String { String(localized: "team.brain.api.hint", defaultValue: "Add a key in Settings › AI services.", bundle: bundle, locale: locale, comment: "Brain row: API not set up") }
    static var ccBrain: String { String(localized: "team.brain.cc", defaultValue: "Claude Code works with Claude.", bundle: bundle, locale: locale, comment: "Claude Code's brain row") }
    static var terminalOnClaude: String { String(localized: "team.scope.terminal.claude", defaultValue: "No terminal switch on Claude: Claude runs only Aris's own commands.", bundle: bundle, locale: locale, comment: "In place of the terminal scope, for a Claude teammate") }
    static var terminalBypass: String { String(localized: "team.scope.terminal.bypass", defaultValue: "With the terminal on, this teammate can get around its other limits.", bundle: bundle, locale: locale, comment: "Under the terminal scope") }
    static var agyScoped: String { String(localized: "team.brain.agy.scoped", defaultValue: "With limited scopes, Gemini (agy) only answers in words.", bundle: bundle, locale: locale, comment: "Gemini row when a scope is off (agy can't be held to scopes)") }
    static var needsReview: String { String(localized: "team.mem.review", defaultValue: "Needs a look", bundle: bundle, locale: locale, comment: "Chip on a note learned from app or web content") }
    static var keepNote: String { String(localized: "team.mem.keep", defaultValue: "Keep", bundle: bundle, locale: locale, comment: "Button: lets turns read a reviewed note") }
    static var reviewHint: String { String(localized: "team.mem.review.d", defaultValue: "Learned from an app's or a page's own words. No brain reads it until you keep it.", bundle: bundle, locale: locale, comment: "Under a note that needs a look") }
    static var ccScopes: String { String(localized: "team.scopes.cc", defaultValue: "Claude Code asks for its own permissions in the terminal.", bundle: bundle, locale: locale, comment: "Claude Code has no scopes here") }
    static var safeLine: String { String(localized: "team.scopes.safe", defaultValue: "Sending, deleting, paying and other hard-to-undo steps always ask with a card first, even when switched on.", bundle: bundle, locale: locale, comment: "The line under the scopes") }
    static var memoryEmptyTitle: String { String(localized: "team.mem.empty", defaultValue: "Nothing remembered yet", bundle: bundle, locale: locale, comment: "Empty memory") }
    static var memoryEmptyDetail: String { String(localized: "team.mem.empty.d", defaultValue: "What it learns while working shows up here. You can also say “remember this”.", bundle: bundle, locale: locale, comment: "Empty memory detail") }
    static var forgetAll: String { String(localized: "team.mem.forgetall", defaultValue: "Clear all", bundle: bundle, locale: locale, comment: "Button") }
    static var forgetOne: String { String(localized: "team.mem.forget", defaultValue: "Forget this", bundle: bundle, locale: locale, comment: "VoiceOver") }
    static var learnedFromApp: String { String(localized: "team.mem.fromapp", defaultValue: "learned from an app", bundle: bundle, locale: locale, comment: "Tag on a note learned from app content") }
    static var savesAtOnce: String { String(localized: "team.foot.saves", defaultValue: "Changes save right away.", bundle: bundle, locale: locale, comment: "Footer") }
    static var remove: String { String(localized: "team.remove", defaultValue: "Remove teammate", bundle: bundle, locale: locale, comment: "Button") }
    static var add: String { String(localized: "team.add", defaultValue: "Add teammate", bundle: bundle, locale: locale, comment: "Roster button") }
    static var arisOnlyFace: String { String(localized: "team.aris.faceonly", defaultValue: "Aris is the main one, so only its face changes here. How work is handed out is set on the Conversation page.", bundle: bundle, locale: locale, comment: "Note for Aris's row") }
    static var noWhenYet: String { String(localized: "team.when.none", defaultValue: "When to call isn't set yet", bundle: bundle, locale: locale, comment: "Roster line when empty") }
    static var makeTitle: String { String(localized: "team.make.title", defaultValue: "Make a teammate by saying it", bundle: bundle, locale: locale, comment: "Make-by-words entry title") }
    static var makePlaceholder: String { String(localized: "team.make.placeholder", defaultValue: "e.g. Make a teammate that tidies documents, named Cody", bundle: bundle, locale: locale, comment: "Make-by-words placeholder") }
    static var makeButton: String { String(localized: "team.make.button", defaultValue: "Make", bundle: bundle, locale: locale, comment: "Button") }
    static var makeHint: String { String(localized: "team.make.hint", defaultValue: "Aris fills in when to call it, how it works and what it may use. You can also just say it.", bundle: bundle, locale: locale, comment: "Make-by-words hint") }
    static var makeNotUnderstood: String { String(localized: "team.make.unknown", defaultValue: "Say it like “make a … teammate”.", bundle: bundle, locale: locale, comment: "Make-by-words: not understood") }
    static var knowhowTitle: String { String(localized: "team.knowhow.title", defaultValue: "App know-how", bundle: bundle, locale: locale, comment: "Section") }
    static var knowhowNote: String { String(localized: "team.knowhow.note", defaultValue: "What Aris and its teammates learned about your apps. Every brain reads it as a hint, never as an order.", bundle: bundle, locale: locale, comment: "Section note") }
    static var knowhowEmpty: String { String(localized: "team.knowhow.empty", defaultValue: "Nothing learned yet. When Aris finds out how an app works, it notes it here.", bundle: bundle, locale: locale, comment: "Empty know-how") }
    static var loading: String { String(localized: "team.loading", defaultValue: "Loading…", bundle: bundle, locale: locale, comment: "Roster loading") }
    static var unavailable: String { String(localized: "team.unavailable", defaultValue: "Couldn't reach Aris's helper to load the teammates. Restart Aris, then open this again.", bundle: bundle, locale: locale, comment: "Agent down") }
    static var reload: String { String(localized: "team.reload", defaultValue: "Load again", bundle: bundle, locale: locale, comment: "Button") }

    static func notesCount(_ count: Int) -> String {
        String(localized: "team.mem.count", defaultValue: "\(count) · only this teammate reads them", bundle: bundle, locale: locale, comment: "Memory footer: %lld notes")
    }
    static func knowhowCount(_ count: Int) -> String {
        String(localized: "team.knowhow.count", defaultValue: "\(count) · every brain reads them", bundle: bundle, locale: locale, comment: "Know-how footer: %lld notes")
    }
    static func takes(_ name: String) -> String {
        let subject = korean ? name + subjectParticle(name) : name
        return String(localized: "team.probe.takes", defaultValue: "\(subject) takes it", bundle: bundle, locale: locale, comment: "Routing test: %@ takes it")
    }
    /// 이 or 가 after a Korean name (a final consonant takes 이).
    static func subjectParticle(_ name: String) -> String {
        guard let last = name.unicodeScalars.last?.value, (0xAC00...0xD7A3).contains(last) else { return "가" }
        return (last - 0xAC00) % 28 == 0 ? "가" : "이"
    }
    static func count(_ used: Int, of limit: Int) -> String { "\(used) / \(limit)" }
}

/// The SF Symbols the teammates' scopes use (the mockup's icons).
enum ArisTeamSymbols {
    static func scope(_ scope: ArisTeammateScope) -> String {
        switch scope {
        case .files: "folder"
        case .web: "globe"
        case .aside: "safari"
        case .send: "paperplane"
        case .apps: "cursorarrow"
        case .mail: "envelope"
        case .calendar: "calendar"
        case .terminal: "apple.terminal"
        }
    }
}
