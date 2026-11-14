//
//  ArisSavedStepsReplay.swift
//  aris-agent
//
//  A saved request done again with no AI: each step's rules checked again for the new words, a fresh look at the app's
//  window, its control found again (one, in a window read in full), then the step's own desktop words through the
//  engine (ArisDesktopEngine.handle), exactly as a brain's call: read again, gated, carded, locked, verified. The first
//  step that can't be found or isn't done stops it, and the AI takes the request over with a note of what was done;
//  The user's no on a card stops it with nothing handed over.
//

import Foundation

enum ArisSavedStepsReplay {
    enum Outcome: Equatable {
        /// Every step was done.
        case done(steps: Int)
        /// It stopped at a step: what was done before it (for the AI's note), and why, in Aris's own words.
        case handOver(done: [ArisSavedStep], why: Why)
        /// The user said no (or didn't answer) on a step's card: nothing more, nothing handed over.
        case declined(done: [ArisSavedStep])
    }

    /// Why a replay stopped, in Aris's own words only (never a window's text: the note goes into the AI's prompt).
    enum Why: String, Equatable {
        case rules = "one of its steps can't be replayed for these words"
        case look = "Aris couldn't look at the app's window"
        case judged = "a look in it needs Aris's read check, which needs the AI"
        case missing = "a control it needs isn't in the window"
        case several = "more than one control in the window matches a step"
        case incomplete = "the window couldn't be read in full, so a control couldn't be told apart"
        case notDone = "a step wasn't done (one of Aris's checks stopped it)"
    }

    /// The taint a replay starts with: the conversation's now, and outside text whenever the recipe was learned on a
    /// turn that read it (its steps were picked while another app's words were in front of the AI): a replay is as
    /// tainted as the turn it was learned on, so no remembered yes skips its cards (security review 10, L2).
    static func startTaint(_ recipe: ArisSavedRecipe, sawScreen: Bool, sawOutside: Bool) -> ArisTaint {
        recipe.outside == true ? .outsideText : conversationTaint(sawScreen: sawScreen, sawOutside: sawOutside)
    }

    /// The conversation's own taint, the recipe aside.
    static func conversationTaint(sawScreen: Bool, sawOutside: Bool) -> ArisTaint {
        sawOutside ? .outsideText : sawScreen ? .screenSeen : .none
    }

    /// The taint a replay's step runs under for its app: outside text once another app's window was read in the replay;
    /// else the conversation's own when the live run did this step with no outside text for its app (`stepClean`,
    /// ArisSavedStep.appClean), so the replay asks the live run's cards; else the recipe's (`learned`: startTaint), as
    /// tainted as the turn it was learned on (review 10, L2). Never less than the live run had: a clean live step had none.
    static func stepTaint(learned: ArisTaint, conversation: ArisTaint, stepClean: Bool, readOther: Bool) -> ArisTaint {
        if readOther { return .outsideText }
        return stepClean ? conversation : learned
    }

    /// How long one step may take, a card and a pause for a sign-in window included.
    static let stepLimit: TimeInterval = ArisCardEdit.questionTimeout + ArisDesktopPause.Policy.live.limit + 30

    /// Runs `recipe` for `request` on `turn` (blocking: never on a server queue).
    static func run(_ recipe: ArisSavedRecipe, request: String, engine: ArisDesktopEngine, turn: ArisDesktopTurn,
                    limit: TimeInterval = stepLimit) -> Outcome {
        var done: [ArisSavedStep] = []
        guard !ArisSavedSteps.hasMomentWords(request) else { return .handOver(done: [], why: .rules) }
        // A look the live run needed the read judge for can't be judged here (no AI): handed over before any step or card.
        // (A step its rules refuse is said as that, at its turn, as before.)
        if recipe.steps.allSatisfy({ ArisSavedSteps.replayable($0, request: request) }), recipe.steps.contains(where: { $0.onControl && $0.lookJudged != false }) {
            return .handOver(done: [], why: .judged)
        }
        for step in recipe.steps {
            guard turn.live else { return .handOver(done: done, why: .notDone) }
            guard ArisSavedSteps.replayable(step, request: request) else { return .handOver(done: done, why: .rules) }
            var ref: String?
            if step.onControl {
                // Decided as the live run's look was: without the read judge.
                turn.ledger.replayLook(unjudged: true, clean: step.appClean == true)
                let seen = call(engine, ArisSavedSteps.lookWords(step), text: nil, turn: turn, limit: limit)
                turn.ledger.replayLook(unjudged: false)
                guard seen.status == 0, let look = turn.ledger.lastLook, look.target.bundle == step.bundle else { return .handOver(done: done, why: .look) }
                switch ArisSavedSteps.find(step, in: look) {
                case .one(let element):
                    // Found again, it must still be no secret field and no control that sends, deletes or pays.
                    if element.isSecure || ArisSavedSteps.riskyLabel(element.value) { return .handOver(done: done, why: .rules) }
                    ref = look.ref(element)
                case .none: return .handOver(done: done, why: .missing)
                case .several: return .handOver(done: done, why: .several)
                case .incomplete: return .handOver(done: done, why: .incomplete)
                }
            }
            guard let (words, text) = ArisSavedSteps.words(step, ref: ref) else { return .handOver(done: done, why: .rules) }
            // Done on the app's yes in the live run: on this replay's own earlier yes for the app (never one from before it).
            turn.ledger.replayStep(afterYes: step.afterYes == true, clean: step.appClean == true)
            let outcome = call(engine, words, text: text, turn: turn, limit: limit)
            turn.ledger.replayStep(afterYes: false)
            guard outcome.status == 0 else {
                if ArisDesktopEngine.isDecline(outcome.output) || outcome.output.contains(ArisDesktopEngine.unansweredLine) { return .declined(done: done) }
                return .handOver(done: done, why: .notDone)
            }
            done.append(step)
        }
        return .done(steps: done.count)
    }

    private static func call(_ engine: ArisDesktopEngine, _ words: [String], text: String?, turn: ArisDesktopTurn, limit: TimeInterval) -> ArisMCPOutcome {
        let finished = DispatchSemaphore(value: 0)
        let box = OutcomeBox()
        engine.handle(words, text: text, turn: turn) { outcome in
            box.set(outcome)
            finished.signal()
        }
        guard finished.wait(timeout: .now() + limit) == .success else { return .failed("it took too long") }
        return box.value ?? .failed("no answer")
    }

    /// One outcome handed across threads.
    private final class OutcomeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: ArisMCPOutcome?
        func set(_ outcome: ArisMCPOutcome) { lock.withLock { if stored == nil { stored = outcome } } }
        var value: ArisMCPOutcome? { lock.withLock { stored } }
    }

    // MARK: - Words

    /// What the AI is told when it takes over: which kinds of steps Aris already did (no window's text: the labels came
    /// from the app), and why it stopped. `name`: an installed app's own name for a bundle id (nil when there is no such
    /// app); the name stored in the file never reaches the prompt (security review 10, L6).
    static func handOverNote(done: [ArisSavedStep], why: Why, name: (String) -> String?) -> String {
        let lines = done.enumerated().map { index, step in "\(index + 1). \(plain(step, name: name))" }
        let did = lines.isEmpty ? "None of its steps were done yet." : "Aris already did these steps of it, in this order:\n" + lines.joined(separator: "\n")
        return "[saved-steps] Aris tried this request from its saved steps (no AI) and stopped: \(why.rawValue). \(did)\n" +
            "Look at the app's window again before acting, do only what is left, and don't repeat a step that was done."
    }

    /// A step as a line with nothing read from a window or the file in it: the app by the name `name` gives its bundle
    /// id (plain letters only, else "the app"), and only keys the replay rules allow.
    static func plain(_ step: ArisSavedStep, name: (String) -> String?) -> String {
        let app = appName(step.bundle, name: name)
        let keys = step.keys.map { ArisSavedSteps.keysReplayable($0) ? $0.joined(separator: " ") : "keys" } ?? "keys"
        switch step.action {
        case .click, .doubleClick, .rightClick: return "clicked a control in \(app)"
        case .setValue, .type: return "entered text the user said into a field in \(app)"
        case .scroll: return "scrolled in \(app)"
        case .press: return "pressed \(keys) in \(app)"
        case .menuClick: return "chose a menu item in \(app)"
        case .appLaunch, .appFocus: return "opened \(app)"
        }
    }

    /// An installed app's own name by its bundle id, as the engine resolves it (the same id, or nothing).
    static func installedName(engine: ArisDesktopEngine) -> (String) -> String? {
        { bundle in engine.apps.installed(bundle).flatMap { $0.bundle == bundle && !$0.never ? $0.name : nil } }
    }

    /// The installed app's own name for `bundle`, when it is a short plain name (letters, digits, spaces and . - _ &);
    /// "the app" otherwise.
    static func appName(_ bundle: String, name: (String) -> String?) -> String {
        guard let found = name(bundle)?.trimmingCharacters(in: .whitespaces), !found.isEmpty, found.count <= 40,
              found.range(of: #"^[\p{L}\p{N} ._&-]+$"#, options: .regularExpression) != nil else { return "the app" }
        return found
    }

    /// The user's answer when every step was done.
    static func doneLine(steps: Int, english: Bool) -> String {
        english ? "Done with the saved steps (\(steps) step\(steps == 1 ? "" : "s"))." : "저장된 단계대로 했어요 (\(steps)단계)."
    }

    /// The user's answer when they said no on a step's card.
    static func declinedLine(done: Int, english: Bool) -> String {
        english ? "Stopped: the card wasn't a yes\(done > 0 ? " (\(done) step\(done == 1 ? " was" : "s were") done before it)" : ""), so nothing more was done."
            : "카드에 허락이 없어서 멈췄어요\(done > 0 ? " (그 전에 \(done)단계는 했어요)" : "")."
    }

    /// The notch's line while it runs.
    static func statusLine(english: Bool) -> String { english ? "Doing the saved steps" : "저장된 단계대로 하는 중" }
}
