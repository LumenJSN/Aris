//
//  ArisSavedSteps.swift
//  aris-agent
//
//  Saved steps: a desktop task done again without the AI. When a conversation turn did a request with desktop actions
//  only, every one of them done and every one of a kind that can be found again, its steps are saved under the
//  request's words (ArisShortcuts.key). The same request later replays them with no model call: each target is found
//  fresh by its role, its label and the containers around it, and must be the only such control in a window Aris read
//  in full; anything else hands the request to the AI with a note of what was already done. Every replayed step goes
//  through the engine exactly as a live one does: its words read again, the gate, the user's cards, the lock, the checks.
//
//  Never saved, never replayed: a point or a pixel (click-at, a text mark), a drag, a dialog, a window move, a batch, a
//  step in a sending app, System Settings or Finder, a control that sends, deletes or pays (its words in any language:
//  ArisSavedStepsWords, and Aris's own risky words), a secret field, keys that delete or could send, typed text that
//  isn't word for word in the request, and a request that points at the moment (이거, 방금, 오늘, this, latest…).
//  Pure.
//

import CoreGraphics
import Foundation

/// One saved desktop step, as it is found and done again.
struct ArisSavedStep: Codable, Equatable {
    enum Action: String, Codable {
        case click, doubleClick, rightClick, setValue, type, scroll, press, menuClick, appLaunch, appFocus
    }

    let action: Action
    /// The app by its bundle id, and the name it had.
    let bundle: String
    let app: String
    /// The window's title when it was done (it is found by it again).
    var window: String? = nil
    /// The control: its role, its label, and the containers around it (outermost first, "role|label").
    var role: String? = nil
    var label: String? = nil
    var path: [String]? = nil
    var keys: [String]? = nil
    var text: String? = nil
    var menu: String? = nil
    var direction: String? = nil
    var amount: Int? = nil
    /// The live run did it on the user's yes for the app given on an earlier card of the same turn (no card of its own): a
    /// replay does it on its own earlier card's yes too, so it never asks more cards than the live run did.
    var afterYes: Bool? = nil
    /// How the live run's look before it was decided: false, it ran without the read judge (a replay's look runs without
    /// it too); true, the judge had to allow it (a replay hands the request over before acting). Nil: not known (saved
    /// before this was kept), as true.
    var lookJudged: Bool? = nil
    /// The text field's only name was what it held (TextEdit's text view): it is found again by its role and the
    /// containers around it, the window's only such text field, and its words are never kept here.
    var contentLabel: Bool? = nil
    /// A type's caret place from the brain's `--at` ("end" or "start"): replayed with it (the user's words still win).
    var at: String? = nil
    /// The live run did it with no outside text for its app (only that app's own window had been read): a replay runs it
    /// under the conversation's own taint, not the recipe's, so it asks no card the live run didn't (eleventh VM pass: the
    /// tool path's replay asked one where the live run asked none). Nil: not so, or not known (saved before): the recipe's.
    var appClean: Bool? = nil

    /// Whether it acts on a control (found again in a fresh look).
    var onControl: Bool { [.click, .doubleClick, .rightClick, .setValue, .type, .scroll].contains(action) }
}

/// One saved request: its key (the normalised words), the words as said, the steps, when.
struct ArisSavedRecipe: Codable, Equatable {
    let key: String
    let request: String
    let steps: [ArisSavedStep]
    let saved: String
    /// It was learned in a turn that read app windows (outside text): Settings says so.
    var outside: Bool? = nil
}

enum ArisSavedSteps {
    /// Recipes kept (the oldest go first), steps in one.
    static let limit = 100
    static let maxSteps = 12

    // MARK: - The request

    /// Words that point at the moment or at what's on screen now: the same words could mean other things next time.
    static let momentWords: Set<String> = ["this", "that", "it", "here", "there", "these", "those", "them", "latest", "newest", "oldest", "last", "first",
                                           "top", "next", "previous", "recent", "today", "tonight", "tomorrow", "yesterday", "current", "unread", "now"]
    /// Korean ones, matched at the start of a word (이거를, 오늘의).
    static let momentStarts = ["이거", "이걸", "이것", "이건", "이게", "저거", "저걸", "저것", "저건", "그거", "그걸", "그것", "그건", "방금", "최신", "최근", "오늘",
                               "어제", "내일", "지금", "여기", "거기", "저기", "이번", "다음", "지난", "마지막", "첫", "새로", "안읽은", "안 읽은", "아까", "요즘"]

    static func hasMomentWords(_ request: String) -> Bool {
        let folded = ArisSavedStepsWords.fold(request)
        let tokens = folded.components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted).filter { !$0.isEmpty }
        if tokens.contains(where: momentWords.contains) { return true }
        return tokens.contains { token in momentStarts.contains { token.hasPrefix($0) } } || momentStarts.contains { $0.contains(" ") && folded.contains($0) }
    }

    /// `text` is in `request` word for word (any case), not inside a longer word.
    static func inRequest(_ text: String, request: String) -> Bool {
        let fragment = ArisSavedStepsWords.fold(text), words = ArisSavedStepsWords.fold(request)
        guard !fragment.isEmpty else { return false }
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: fragment) + "(?![\\p{L}\\p{N}])"
        return words.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - What may be saved

    /// Apps whose steps are never saved: System Settings (its panes are judged one look at a time) and Finder (its
    /// folders are), besides the sending apps, browsers and the never-list.
    static let neverApps: Set<String> = ["com.apple.systempreferences", "com.apple.settings", "com.apple.finder"]

    /// The keys a saved ⌘ combo may end in: find, find again, a new window or tab, a view by its number, settings,
    /// back and forward, zoom in. Nothing that pastes (⌘V), cuts, quits (⌘Q), closes (⌘W), deletes (⌘⌫), undoes,
    /// saves, prints or selects everything; and no Control or Option combo but with a navigation key.
    static let safeCommandKeys: Set<String> = ["f", "g", "n", "t", ",", "[", "]", "=", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]

    /// Keys a saved press may hold: navigation (with any modifier), and ⌘ combos from a small safe list
    /// (safeCommandKeys); never Return or Enter (it may send), never a delete, never a plain letter (that is typing).
    static func keysReplayable(_ keys: [String]) -> Bool {
        guard !keys.isEmpty else { return false }
        let navigation: Set<String> = ["tab", "escape", "esc", "up", "down", "left", "right", "home", "end", "pageup", "pagedown", "space", "f1", "f2", "f3", "f4", "f5"]
        let modifiers: Set<String> = ["cmd", "command", "ctrl", "control", "opt", "option", "alt"]
        return keys.allSatisfy { combo in
            let parts = Set(combo.lowercased().split(separator: "+").map(String.init))
            if !parts.isDisjoint(with: ["return", "enter", "delete", "backspace", "forwarddelete", "del"]) { return false }
            guard ArisDesktopWords.isKeyCombo(combo) else { return false }
            let rest = parts.subtracting(modifiers).subtracting(["shift"])
            guard rest.count == 1, let key = rest.first else { return false }
            if navigation.contains(key) { return true }
            let held = parts.intersection(modifiers)
            return !held.isEmpty && held.isSubset(of: ["cmd", "command"]) && safeCommandKeys.contains(key)
        }
    }

    /// A label that sends, deletes, pays, quits or replaces (any language), or names a secret.
    static func riskyLabel(_ label: String?) -> Bool {
        guard let label else { return false }
        return ArisSavedStepsWords.namesFinalAction(label) || ArisSavedStepsWords.namesSecret(label) || ArisDesktopBatch.riskyWords(label)
    }

    /// The containers around `element` in `look` (outermost first): the groups and the generic areas whose frame holds
    /// it, as "role|label". Peekaboo gives no parents, so where it sits is what it is inside of.
    static func ancestors(of element: ArisDesktopElement, in look: ArisDesktopObservation) -> [String] {
        let box = element.bounds
        guard box.width > 0, box.height > 0 else { return [] }
        let containers = look.elements.filter { other in
            other.id != element.id && isContainer(other) && other.bounds.contains(box) && other.bounds.width * other.bounds.height > box.width * box.height
        }
        return containers.sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }.map { "\($0.role)|\($0.label)" }
    }

    static func isContainer(_ element: ArisDesktopElement) -> Bool {
        if element.role == "group" || element.role == "scrollArea" || element.role == "tabGroup" || element.role == "splitGroup" { return true }
        guard element.role == "other" else { return false }
        return ArisDesktopObservation.generic.contains(element.label) || ["scroll area", "tab group", "list", "table", "outline", "sheet", "web area"].contains(element.label)
    }

    /// The step a done desktop action is saved as, or why it can't be. `look`: the look its ref came from.
    static func step(for request: ArisDesktopRequest, target: ArisDesktopTarget, element: ArisDesktopElement?, look: ArisDesktopObservation?,
                     window: String?, words: String) -> Result<ArisSavedStep, ArisSavedStepsRefusal> {
        guard let bundle = target.bundle, target.known else { return .failure(.app) }
        if target.never || target.browser || target.sending || target.settings || neverApps.contains(bundle) { return .failure(.app) }
        var step: ArisSavedStep
        switch request.verb {
        case .click, .setValue, .type, .scroll:
            guard let ref = request.ref, !ref.mark else { return .failure(.spot) }
            guard let element, let look else { return .failure(.unnamed) }
            // A text field named only by what it holds (its text changes with every step): found again by its place, a click
            // on it too (eleventh VM pass: the click was saved under "note C" and never found once the text read "note C둘").
            let content = [.type, .setValue, .click].contains(request.verb) && element.isTextEntry && !element.isSecure
                && !element.label.isEmpty && (element.label == element.rawValue || element.label == element.value)
            guard content || !element.label.trimmingCharacters(in: .whitespaces).isEmpty else { return .failure(.unnamed) }
            if element.isSecure || ArisSavedStepsWords.namesSecret(element.label) { return .failure(.secret) }
            if !content, riskyLabel(element.label) || riskyLabel(element.value) { return .failure(.final) }
            let action: ArisSavedStep.Action
            switch request.verb {
            case .click: action = request.double ? .doubleClick : request.right ? .rightClick : .click
            case .setValue: action = .setValue
            case .type: action = .type
            default: action = .scroll
            }
            step = ArisSavedStep(action: action, bundle: bundle, app: target.name, window: look.title, role: element.role, label: content ? nil : element.label,
                                 path: ancestors(of: element, in: look))
            if content { step.contentLabel = true }
            if action == .setValue || action == .type {
                guard let text = request.text, !text.isEmpty, inRequest(text, request: words) else { return .failure(.text) }
                step.text = text
            }
            if action == .type { step.at = request.at?.rawValue }
            if action == .scroll {
                step.direction = request.direction ?? "down"
                step.amount = request.amount
            }
        case .press:
            guard keysReplayable(request.keys) else { return .failure(.keys) }
            step = ArisSavedStep(action: .press, bundle: bundle, app: target.name, window: window, keys: request.keys)
        case .menuClick:
            guard let path = request.path, !path.isEmpty else { return .failure(.final) }
            let parts = path.components(separatedBy: CharacterSet(charactersIn: ">›"))
            if parts.contains(where: riskyLabel) || parts.last.map(ArisDesktopBatch.selectsAll(label:)) == true { return .failure(.final) }
            step = ArisSavedStep(action: .menuClick, bundle: bundle, app: target.name, menu: path)
        case .app where request.operation == "launch" || request.operation == "focus":
            step = ArisSavedStep(action: request.operation == "launch" ? .appLaunch : .appFocus, bundle: bundle, app: target.name)
        default:
            return .failure(.kind)
        }
        return .success(step)
    }

    /// Whether a saved step may still be replayed for `request` (its rules checked again: the file could have been
    /// changed, the rules may be stricter now).
    static func replayable(_ step: ArisSavedStep, request: String) -> Bool {
        if neverApps.contains(step.bundle) || step.bundle.isEmpty { return false }
        switch step.action {
        case .click, .doubleClick, .rightClick, .scroll:
            guard step.text == nil, step.at == nil else { return false }
            if step.contentLabel == true { return step.label == nil && [.click, .doubleClick, .rightClick].contains(step.action) }
            return !(step.label ?? "").isEmpty && !riskyLabel(step.label)
        case .setValue, .type:
            guard let text = step.text, !text.isEmpty, step.at.map({ ArisDesktopCaret.Place(rawValue: $0) != nil && step.action == .type }) ?? true else { return false }
            let named = step.contentLabel == true ? step.label == nil : !(step.label ?? "").isEmpty && !riskyLabel(step.label)
            return named && inRequest(text, request: request)
        case .press: return step.keys.map(keysReplayable) ?? false
        case .menuClick:
            guard let menu = step.menu else { return false }
            let parts = menu.components(separatedBy: CharacterSet(charactersIn: ">›"))
            return !parts.contains(where: riskyLabel) && parts.last.map(ArisDesktopBatch.selectsAll(label:)) != true
        case .appLaunch, .appFocus: return true
        }
    }

    /// Whether a turn's steps make a recipe: a request that doesn't point at the moment, at least one step and no more
    /// than the limit, every one saveable.
    /// `outside`: the turn read app windows (or other outside text).
    static func recipe(key: String, request: String, notes: [Result<ArisSavedStep, ArisSavedStepsRefusal>], outside: Bool = false, now: Date = Date()) -> ArisSavedRecipe? {
        guard !key.isEmpty, !ArisShortcuts.isQuestion(key), !hasMomentWords(request), !notes.isEmpty, notes.count <= maxSteps else { return nil }
        var steps: [ArisSavedStep] = []
        for note in notes {
            guard case .success(let step) = note, replayable(step, request: request) else { return nil }
            steps.append(step)
        }
        return ArisSavedRecipe(key: key, request: String(request.prefix(300)), steps: steps, saved: ISO8601DateFormatter().string(from: now), outside: outside)
    }

    /// The answer says it failed (the same words a learned shortcut is held to).
    static func replySaysFailed(_ reply: String) -> Bool {
        let failed = ["못 ", "못했", "실패", "없어요", "수 없", "않았", "안 돼", "couldn't", "can't", "cannot", "failed", "error", "not found", "wasn't", "didn't"]
        return failed.contains { reply.localizedCaseInsensitiveContains($0) }
    }

    /// A conversation turn's recipe to save, or nil: under the user's words (`key`: nil for a job, a hands-free or a screen
    /// turn), desktop actions only (`otherTools` false), every one of them done (`notDone` 0 by the turn's ledger), an
    /// answer that doesn't say it failed, and every step saveable (recipe). Every brain's turn is held to this one rule:
    /// a runner's, and agy's relayed one.
    static func turnRecipe(key: String?, request: String, notes: [Result<ArisSavedStep, ArisSavedStepsRefusal>], notDone: Int, otherTools: Bool,
                           reply: String, outside: Bool, now: Date = Date()) -> ArisSavedRecipe? {
        guard let key, !otherTools, notDone == 0, !replySaysFailed(reply) else { return nil }
        return recipe(key: key, request: request, notes: notes, outside: outside, now: now)
    }

    // MARK: - Finding a target again

    enum Found: Equatable {
        case one(ArisDesktopElement)
        case none
        case several
        /// The look isn't the whole window (Peekaboo cut it, or the privacy filter hid part of it): uniqueness can't be told.
        case incomplete
    }

    /// The saved step's control in a fresh look: same role, same label, same containers, the only one.
    static func find(_ step: ArisSavedStep, in look: ArisDesktopObservation) -> Found {
        guard step.onControl, let role = step.role else { return .none }
        let content = step.contentLabel == true && [.type, .setValue, .click, .doubleClick, .rightClick].contains(step.action)
        guard content || step.label != nil else { return .none }
        if look.truncated || look.hidden { return .incomplete }
        let matches = look.elements.filter { element in
            guard element.role == role, ancestors(of: element, in: look) == (step.path ?? []) else { return false }
            // A field named by what it holds: any such text field there (one only), whatever it holds now.
            if content { return element.isTextEntry && !element.isSecure && (element.label.isEmpty || element.label == element.rawValue || element.label == element.value) }
            return element.label == step.label
        }
        switch matches.count {
        case 0: return .none
        case 1: return look.hiddenRegions.contains { $0.intersects(matches[0].bounds) } ? .incomplete : .one(matches[0])
        default: return .several
        }
    }

    // MARK: - The step as desktop words

    /// The words the engine reads for a step (`ref`: the control's ref in the fresh look), and its text if any.
    static func words(_ step: ArisSavedStep, ref: String?) -> (words: [String], text: String?)? {
        switch step.action {
        case .click: return ref.map { (["click", $0], nil) }
        case .doubleClick: return ref.map { (["click", $0, "--double"], nil) }
        case .rightClick: return ref.map { (["click", $0, "--right"], nil) }
        case .setValue: return ref.map { (["set-value", $0, "--stdin"], step.text) }
        case .type: return ref.map { (["type", $0] + (step.at.map { ["--at", $0] } ?? []) + ["--stdin"], step.text) }
        case .scroll:
            return ref.map { (["scroll", $0, "--direction", step.direction ?? "down"] + (step.amount.map { ["--amount", String($0)] } ?? []), nil) }
        case .press:
            guard let keys = step.keys else { return nil }
            return (["press"] + keys + ["--app", step.bundle] + (step.window.map { ["--title", $0] } ?? []), nil)
        case .menuClick: return step.menu.map { (["menu", "click", "--app", step.bundle, "--path", $0], nil) }
        case .appLaunch: return (["app", "launch", step.bundle], nil)
        case .appFocus: return (["app", "focus", step.bundle], nil)
        }
    }

    /// The look a control step is found in: the app's window by its title when it had one.
    static func lookWords(_ step: ArisSavedStep) -> [String] {
        ["see", "--app", step.bundle] + (step.window.map { $0.isEmpty ? [] : ["--title", $0] } ?? [])
    }

    /// A step as one line for the user (Settings, the hand-over note).
    static func describe(_ step: ArisSavedStep, english: Bool) -> String {
        let label = step.label.map { "“\(ArisDesktopCard.shown(String($0.prefix(60))))”" } ?? (step.contentLabel == true ? (english ? "the text" : "글 칸") : "")
        switch step.action {
        case .click, .doubleClick, .rightClick: return english ? "click \(label) in \(step.app)" : "\(step.app)에서 \(label) 누르기"
        case .setValue, .type: return english ? "enter “\(step.text ?? "")” in \(label)" : "\(label)에 “\(step.text ?? "")” 넣기"
        case .scroll: return english ? "scroll \(label)" : "\(label) 스크롤"
        case .press: return english ? "press \((step.keys ?? []).joined(separator: " "))" : "\((step.keys ?? []).joined(separator: " ")) 누르기"
        case .menuClick: return english ? "\(step.app) menu \(step.menu ?? "")" : "\(step.app) 메뉴 \(step.menu ?? "")"
        case .appLaunch, .appFocus: return english ? "open \(step.app)" : "\(step.app) 열기"
        }
    }
}

/// Why a desktop action can't be a saved step (the audit's words).
enum ArisSavedStepsRefusal: String, Error, Equatable {
    case app = "an app whose steps are never saved"
    case spot = "a spot on the screen, not a control"
    case unnamed = "a control with no name"
    case secret = "a secret field"
    case final = "a control or menu that sends, deletes, pays or replaces"
    case text = "text that isn't word for word in the request"
    case keys = "keys that delete, could send, or type"
    case kind = "a kind of step that is never saved"
    case notDone = "a step that wasn't done"
}
