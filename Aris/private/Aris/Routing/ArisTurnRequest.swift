//
//  ArisTurnRequest.swift
//  Aris
//
//  One turn's request as the answer() funnel reads it (ARCHITECTURE.md 3.1, migration step 3): the words, where they
//  came from, whether they were typed, the drawing that came with them, and the moment they were said in. It is read
//  in stages, each only when a handler needs it, so a turn some early handler takes never pays for the later ones:
//  `said` as it came; `heard` with the files given to Aris taken in, the AI or teammate named for a hand-off, the
//  new-teammate card's yes or no, the done words and the currency question; `read` with the router's guess (asked
//  only for words the matchers leave to the AI, as before) and the one guard every local action passes.
//  Foundation only (with the pure matchers), so the golden table in tests/funnel-tests.swift runs it.
//

import Foundation

struct ArisTurnRequest {
    /// How far the request has been read.
    enum Stage: Int, Comparable {
        case said, heard, read

        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The moment the words were said in, as far as the turn's start knows it.
    struct Context: Equatable {
        /// The onboarding's 물어보기: answered read-only, nothing routed or done (QA BUG-31).
        var practice = false
        var handsFree = false
    }

    /// The words with what came along, and what the words alone already settle.
    struct Heard {
        /// The words with the files given to Aris taken in.
        let heard: String
        /// Circled shots came with the words: the brain answers them, whatever a matcher would make of the words.
        let shots: Bool
        /// "아니 그냥 클로드 시켜": an AI or teammate named as the one to do it (ArisBrainHandOff).
        let handOff: ArisBrainHandOff?
        /// "GPT한테 물어봐, …": the AI named up front for this turn.
        let named: ArisBrain?
        /// What the AI or a job gets: their words, then the files he gave and their text.
        let whole: String
        /// His own words alone: the only part ever read as a command, sent to the router or matched against a phrase.
        let unmarked: String
        /// What the brain gets: `whole`, with `[img N]` markers when shots came with it.
        let text: String
        let brain: ArisBrain
        /// "응" or "아니" while the new-teammate card is up.
        let madeAnswer: Bool?
        /// "됐어", "고마워" in a conversation: it just ends.
        let done: Bool
        /// A plain currency question.
        let fx: ArisCurrencyAsk?
        /// The words ask about the Claude Code sessions Aris's hooks know (never a look at the screen).
        let asksSessions: Bool
        /// What the matchers make of their words, before the router.
        let parsed: ArisIntent

        /// No circled shots, no AI named, no card answered: the words may be one of Aris's own requests.
        var plain: Bool { !shots && named == nil && madeAnswer == nil }

        /// What the moment adds to the words (read when the words are heard, as answer() always read it).
        struct Moment {
            var conversationOpen = false
            /// Aris's last reply asked something: "괜찮아" answers it.
            var afterQuestion = false
            /// The new-teammate card is up.
            var teammateCardUp = false
            var defaultBrain = ArisBrain.claude
            /// The currency a bare amount is in (ArisCurrencyHome).
            var currencyHome = "KRW"
        }

        /// What the words settle, as answer() worked it out before its chain (ArisController.swift ce0683cd 880-920).
        static func make(heard: String, gesture: ArisGestureTurn?, handOff: ArisBrainHandOff?, moment: Moment) -> Heard {
            let shots = gesture?.hasShots == true
            let named = handOff == nil ? ArisBrain.pick(from: heard) : nil
            let whole = named?.request ?? heard
            let unmarked = ArisPendingFiles.words(of: whole)
            let text = shots ? (gesture?.markedRequest(heard) ?? whole) : whole
            let madeAnswer = !shots && named == nil ? ArisTeamMadeAnswer.reply(unmarked, cardUp: moment.teammateCardUp) : nil
            let done = !shots && madeAnswer == nil && moment.conversationOpen
                && ArisFollowUp.isDone(ArisPendingFiles.words(of: text), afterQuestion: moment.afterQuestion)
            let fx = !shots && named == nil && madeAnswer == nil ? ArisCurrencyRead.parse(unmarked, home: moment.currencyHome) : nil
            return Heard(heard: heard, shots: shots, handOff: handOff, named: named?.brain, whole: whole, unmarked: unmarked, text: text,
                         brain: named?.brain ?? moment.defaultBrain, madeAnswer: madeAnswer, done: done, fx: fx,
                         asksSessions: handOff == nil && !shots && ClaudeSessionsContext.asks(unmarked),
                         parsed: named == nil ? ArisGestureTurn.intent(unmarked: unmarked, marked: text, hasShots: shots) : .ask(text))
        }

        /// Whether the router is asked: only for words the matchers leave to the AI (or an app this Mac doesn't have),
        /// never for an AI named, a card answered, a hand-off, a currency question or a schedule.
        func asksRouter(hasApp: (String) -> Bool) -> Bool {
            guard named == nil, madeAnswer == nil, handOff == nil, fx == nil, !ArisIntent.isRecurring(unmarked) else { return false }
            switch shots ? ArisIntent.parse(unmarked) : parsed {
            case .ask: return true
            case .openApp(let name), .arrange(let name, _): return !hasApp(name)
            default: return false
            }
        }
    }

    /// The router's answer: an everyday request it is sure of (nil: the AI's), how much work it is, website work.
    struct Routed: Equatable {
        var intent: ArisIntent?
        var tier: ArisTier
        var browserWork: Bool
        /// The services Aris reaches without a browser at this moment (ArisServiceReach): website work that names one
        /// of them goes to that service first, the browser agent last.
        var reach: ArisServiceReach = .none

        /// The tier when the router can't say (no router key, or no answer in time): from the words themselves, so a
        /// plain question is quick and a request that looks things up, points at the screen or files, or is long is
        /// work (ArisLocalTier; the helper still makes a look-up turn deep, ArisThinking). Before, it was always quick.
        static func withoutRouter(_ words: String) -> Routed {
            let looksUp = ArisThinking.looksUp(words, task: false, images: false, screenText: false, handsFree: false)
            let screen = ArisDeixis.refersToScreen(words) || ArisDeixis.refersToClipboard(words)
            return Routed(intent: nil, tier: ArisLocalTier.isWork(words, looksUp: looksUp, pointsAtScreen: screen) ? .work : .quick, browserWork: false)
        }
    }

    /// The request as every local action and the brain read it.
    struct Reading {
        let intent: ArisIntent
        let tier: ArisTier
        /// Several steps on websites: for Aside, in the background.
        let browserWork: Bool
        /// Website work the router saw that names a service Aris reaches without a browser: those services, in the
        /// order to try them (empty: none). The brain takes the turn then, with that order in its context.
        var reached: [ArisServiceReach.Service] = []

        static func make(_ heard: Heard, routed: Routed?) -> Reading {
            var intent = heard.parsed
            var tier = ArisTier.quick
            var browserWork = false
            var reached: [ArisServiceReach.Service] = []
            if let routed {
                tier = routed.tier
                if !heard.shots {
                    // Never Aris's own schedules, to-dos, memory, teammates, timers or settings: those are done in this
                    // turn with their own tool and card (QA BUG-60). agy's job has no relay (ArisAgyRelay).
                    browserWork = routed.browserWork && heard.brain != .antigravity && !ArisOwnData.mentions(heard.unmarked)
                        && !ArisRoutineWords.mentions(heard.unmarked)
                    // Aris's own tool, then a connected service, before the browser agent (the owner, 2026-11-19).
                    if browserWork {
                        reached = routed.reach.reaching(heard.unmarked)
                        if !reached.isEmpty { browserWork = false }
                    }
                    if let action = routed.intent { intent = action }
                }
            }
            // One guard for every local action, whichever matcher or router picked it (BUG-58 audit).
            if heard.named == nil, !heard.shots { intent = ArisIntent.guarded(intent, said: heard.unmarked) }
            if ArisRouter.asksForCare(heard.unmarked) { tier = .critical }
            return Reading(intent: intent, tier: tier, browserWork: browserWork, reached: reached)
        }
    }

    let said: String
    let origin: ArisTurnOrigin
    let typed: Bool
    let gesture: ArisGestureTurn?
    let context: Context
    var heard: Heard?
    var reading: Reading?

    init(said: String, origin: ArisTurnOrigin, typed: Bool = false, gesture: ArisGestureTurn? = nil, context: Context = Context()) {
        self.said = said
        self.origin = origin
        self.typed = typed
        self.gesture = gesture
        self.context = context
    }

    var stage: Stage { reading != nil ? .read : heard != nil ? .heard : .said }
}
