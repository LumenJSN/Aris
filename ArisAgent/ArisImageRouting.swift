//
//  ArisImageRouting.swift
//  aris-agent
//
//  Which brain answers a turn that carries screen images (the owner's ruling R2 = a): Codex takes them itself, and so does
//  an API brain (gated like Codex: every call through ArisAPIGate); Claude's
//  and Antigravity's turns go to a sealed Claude, a separate process with Bash for the sealed aris-tools list only
//  (ArisSealedTools) and the web, every read and web call put to the read judge first (ArisReadGate), so a page on
//  screen can't quietly get anything fetched out. Antigravity can't take
//  images (P1.0); without Claude installed, a gesture turn goes to Codex, and a plain screenshot turn stays on
//  Antigravity without the image, told so. Once a conversation has seen the screen it stays that way until it starts
//  over (ArisScreenConversation): every later turn is screenSeen and restricted, on the same sealed or gated brain.
//  Dispatch is dispatchPolicy's (a screen turn may; outside text anywhere in the conversation never), and every
//  dispatched job runs untrusted, on the brain it asked for when that can run here, behind that brain's own gate for
//  outside words (ArisJobBrain; the two helpers that used to send them all to Codex are gone with their last caller).
//

import Foundation

enum ArisImageRouting {
    struct Route: Equatable {
        let brain: ArisBrain
        /// The sealed Claude (only with brain == .claude).
        let sealed: Bool
        /// The images go to the brain; false: they're dropped and `note` says so.
        let sendsImages: Bool
        /// A line for the prompt when the images couldn't come along (ArisAgentPrompt.cantSee).
        let note: String?
        /// What the notch says about the hand-over.
        let status: String?
        /// The turn can't go to any brain as it is: this is said instead (no route sets it since every brain takes hands-free turns).
        var refusal: String? = nil
        /// The images stay here but their text goes in (OCR, ArisAPIImageText): an API brain that can't see, with no other
        /// brain installed that can (never refused: the user, every feature on every brain). Outside text.
        var readsText = false
    }

    /// `screenConversation`: this conversation already saw the screen (ArisScreenConversation). `task`: background
    /// work, which has no sealed process, so a screen conversation's task goes to the gated brain.
    /// `handsFree`: heard without a key or the name (ArisHandsFree.profile): Codex gated as ever, Claude and agy sealed
    /// ("클로드한테 물어봐" from a video must not reach an open, ungated brain). A turn or a task.
    /// `privateRead`: Aris read the user's messages, mail or notes for agy in this conversation (ArisAgyRelay).
    /// `api`: what the API brain can do, when it's the one asked: whether its model takes images, and which other brains
    /// that see are installed (only read for an API brain that can't).
    static func route(requested: ArisBrain, images: [ArisTurnImage], screenText: Bool, claudeInstalled: Bool,
                      screenConversation: Bool = false, task: Bool = false, handsFree: Bool = false, privateRead: Bool = false,
                      api: APISight = APISight()) -> Route {
        let hasImages = !images.isEmpty
        // "이거" text from the screen goes to a gated brain only, as before (and it takes the images too): the API brain is
        // gated like Codex, so it keeps its own turn (the images as text when its model can't see them).
        if screenText {
            if requested == .api {
                return Route(brain: .api, sealed: false, sendsImages: hasImages && api.vision, note: hasImages && !api.vision ? ArisAgentPrompt.readText : nil,
                             status: nil, readsText: hasImages && !api.vision)
            }
            return Route(brain: .codex, sealed: false, sendsImages: hasImages, note: nil, status: nil)
        }
        if handsFree, requested == .api {
            // The sealed API brain; when it can't see, the images' text (the sealed list only either way).
            return Route(brain: .api, sealed: true, sendsImages: hasImages && api.vision, note: hasImages && !api.vision ? ArisAgentPrompt.readText : nil,
                         status: nil, readsText: hasImages && !api.vision)
        }
        if handsFree {
            let profile = ArisHandsFree.profile(requested)
            // The sealed agy takes no images: a screen shot in a hands-free turn is described to it as missing.
            let agy = profile.brain == .antigravity
            return Route(brain: profile.brain, sealed: profile.sealed, sendsImages: hasImages && !agy, note: agy && hasImages ? ArisAgentPrompt.cantSee : nil,
                         status: nil)
        }
        guard hasImages || screenConversation else {
            // A conversation in which Aris read the user's messages, mail or notes for agy stays with the sealed agy.
            return Route(brain: requested, sealed: requested == .antigravity && privateRead, sendsImages: false, note: nil, status: nil)
        }
        // A task has no sealed process: the gated brain (the API brain is gated itself).
        if task, requested != .codex, requested != .api { return Route(brain: .codex, sealed: false, sendsImages: false, note: nil, status: nil) }
        if task, requested == .api { return Route(brain: .api, sealed: false, sendsImages: false, note: nil, status: nil) }
        switch requested {
        case .codex:
            return Route(brain: .codex, sealed: false, sendsImages: hasImages, note: nil, status: nil)
        case .claude:
            return Route(brain: .claude, sealed: true, sendsImages: hasImages, note: nil, status: nil)
        case .antigravity:
            if claudeInstalled { return Route(brain: .claude, sealed: true, sendsImages: hasImages, note: nil, status: "화면은 Claude가 봐요") }
            // Without Claude: a follow-up, or gesture shots, go to the gated brain (never to agy, which has the web).
            if !hasImages || images.contains(where: { $0.kind == .gesture }) {
                return Route(brain: .codex, sealed: false, sendsImages: hasImages, note: nil,
                             status: hasImages ? "동그라미는 GPT가 봐요" : "화면을 본 대화라 GPT가 이어서 답해요")
            }
            return Route(brain: .antigravity, sealed: false, sendsImages: false, note: ArisAgentPrompt.cantSee, status: nil)
        case .api:
            // The API brain is gated like Codex: every call it makes passes ArisAPIGate, which knows the screen came in
            // (a read is judged, an action the user's words don't cover asks on their card). So a screen turn keeps its tools,
            // never the sealed process, where it could make no folder and read no file (audit gate-1, QA F1). Only a
            // hands-free turn is sealed (above). Its own model sees: it takes the images. Else another installed brain
            // that sees takes this one turn (the sealed Claude, then Codex), else the API brain gets the images' text.
            if api.vision || !hasImages { return Route(brain: .api, sealed: false, sendsImages: hasImages, note: nil, status: nil) }
            if api.claude { return Route(brain: .claude, sealed: true, sendsImages: true, note: nil, status: "화면은 Claude가 봐요") }
            if api.codex { return Route(brain: .codex, sealed: false, sendsImages: true, note: nil, status: "화면은 GPT가 봐요") }
            return Route(brain: .api, sealed: false, sendsImages: false, note: ArisAgentPrompt.readText, status: nil, readsText: true)
        }
    }

    /// What an API brain turn can do with the screen (ArisAPIProfile.takesImages, and the brains installed beside it).
    struct APISight: Equatable {
        var vision = false
        var claude = false
        var codex = false
    }

    /// An untrusted answer can't hand out jobs: its ```json jobs block is taken out (the app holds that block back
    /// from speech and the notch anyway). Never empty.
    static func withoutJobs(_ answer: String) -> String {
        var text = answer, removed = false
        while let block = ArisDispatch.jobsBlockRange(in: text) {
            text.removeSubrange(block)
            removed = true
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard removed || text.isEmpty else { return text }
        return text.isEmpty ? refusedJobs : text + "\n" + refusedJobs
    }

    /// What the agent sends for a turn's answer, and the jobs that vouch for a Claude Code launch: after outside text
    /// (this turn's, the conversation's on any brain, or the answering driver's observed taint) the jobs block becomes
    /// the notice; a restricted turn (a screen turn) keeps its jobs for the app (untrusted) but never vouches; only a
    /// clean turn that vouches records jobs. `taint` is the driver's, from the tools it was seen to use.
    static func answerPlan(answer: String, untrusted: Bool, restricted: Bool, vouches: Bool, taint: ArisTaint) -> (answer: String, vouched: [ArisJobSpec]?) {
        if untrusted || taint == .outsideText { return (withoutJobs(answer), nil) }
        guard !restricted, vouches else { return (answer, nil) }
        return (answer, ArisTeammateGate.turnSpecs(vouches: vouches, tainted: taint != .none, answer: answer))
    }

    /// Whether answerPlan takes a jobs block out of this answer (outside text): the agent then sends the app a
    /// `refusedJobs` line, so the app never has to read the notice's words.
    static func refusesJobs(answer: String, untrusted: Bool, taint: ArisTaint) -> Bool {
        (untrusted || taint == .outsideText) && ArisDispatch.jobsBlockRange(in: answer) != nil
    }

    /// Whether the turn's context lists a background job that finished or failed: its words were written by an untrusted
    /// job, so the turn is outside text (ArisHandoff.contextLine writes "(done: …)" and "(failed: …)").
    static func carriesJobResults(_ context: String?) -> Bool {
        guard let context else { return false }
        return context.contains("(done:") || context.contains("(failed:")
    }

    /// Said in place of a jobs block a turn may not hand out (as ArisSpeakable.refusedJobs, in the app).
    static let refusedJobs = "이 일은 지금 팀원한테 못 넘겨요."

    struct DispatchPolicy: Equatable {
        /// The <teammates> block goes in and the answer's jobs may be dispatched (every job untrusted).
        let teammates: Bool
        /// The turn may vouch for a Claude Code launch (no card).
        let vouch: Bool
    }

    /// The owner's ruling (2026-11-04): a screen turn may dispatch, but its jobs are untrusted and a Claude Code launch from
    /// it always shows his card; outside text (the screen's text, model-written text) and background tasks never
    /// dispatch; only a clean main turn vouches.
    /// `arisData`: the request is about Aris's own data (ArisOwnData): done in this turn, never handed out, so no
    /// teammates are offered (QA BUG-60). It is still the user's own clean turn: what a clean turn may do besides (answer a
    /// memory request itself, learn from their words) is as before.
    static func dispatchPolicy(outsideText: Bool, screenSeen: Bool, task: Bool, arisData: Bool = false) -> DispatchPolicy {
        let clean = !task && !outsideText
        return DispatchPolicy(teammates: clean && !arisData, vouch: clean && !screenSeen)
    }

    /// Whether the turn is restricted: the screen's text, model-written text, any image, or a conversation that saw the
    /// screen. Then no learned shortcut (replayed or learned) and no vouched launch, and another brain takes it at a quota
    /// limit only as its own restricted turn (ArisTurnFallback), whatever the taint
    /// level (R1 = B table). Dispatch is dispatchPolicy's: a screen turn may (jobs untrusted, launches ask), outside text
    /// never; every untrusted job runs behind its brain's gate for outside words (ArisJobBrain).
    static func untrusted(screenText: Bool, flagged: Bool, images: [ArisTurnImage], screenConversation: Bool = false) -> Bool {
        screenText || flagged || !images.isEmpty || screenConversation
    }

    /// The taint the brain's thread starts this turn with (R1 = B): outside text for the screen's text or model-written
    /// text; screenSeen for a conversation that saw the screen (images now or earlier); else none.
    static func taint(screenText: Bool, flagged: Bool, screenConversation: Bool) -> ArisTaint {
        if screenText || flagged { return .outsideText }
        return screenConversation ? .screenSeen : .none
    }

    /// The name in a runner's key: the sealed Claude is a process of its own, never the one with the web.
    static func runnerName(_ brain: ArisBrain, sealed: Bool, handsFree: Bool = false) -> String {
        handsFree ? brain.rawValue + "-handsfree" : sealed ? brain.rawValue + "-sealed" : brain.rawValue
    }
}

/// Whether the conversation has seen the screen: its turns are screenSeen (R1 = B) and restricted. Any image turn sets
/// it; only a fresh conversation (POST /ask "fresh", ArisAgentRunner.startNewConversation) clears it. Only touched on
/// the agent's queue.
struct ArisScreenConversation {
    private(set) var seen = false

    /// This turn's answer: whether it counts as having seen the screen. `claimed`: the app says this conversation saw
    /// the screen (kept with its history, so a resume or an agent restart can't wash it out); it only ever adds.
    mutating func turn(fresh: Bool, images: [ArisTurnImage], claimed: Bool = false) -> Bool {
        if fresh { seen = false }
        if !images.isEmpty || claimed { seen = true }
        return seen
    }
}

/// The sealed Claude's working folder: a fresh empty 0700 folder per process, removed when the process ends (and any
/// left over swept at agent start), so even a command Claude Code thinks harmless finds nothing there.
enum ArisSealedScratch {
    static let prefix = "aris-sealed-"

    static func make(in parent: URL = FileManager.default.temporaryDirectory) -> URL? {
        let folder = parent.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            return folder
        } catch {
            return nil
        }
    }

    static func remove(_ folder: URL) {
        guard folder.lastPathComponent.hasPrefix(prefix) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    static func sweep(in parent: URL = FileManager.default.temporaryDirectory) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        for name in names where name.hasPrefix(prefix) { remove(parent.appendingPathComponent(name, isDirectory: true)) }
    }
}

/// Whether the conversation has taken in outside text (a web page, mail, the screen's text, a tool's result), on any
/// brain: then nothing in it dispatches until a fresh start, even after a switch to another brain or to the sealed
/// Claude (whose own thread is clean). Set by a turn's outside text, by any runner that reports it, or by the app's
/// claim (kept with the conversation's history, so a resume or an agent restart can't wash it out). Only touched on the
/// agent's queue.
struct ArisOutsideConversation {
    private(set) var seen = false

    mutating func turn(fresh: Bool, outsideText: Bool, claimed: Bool = false) -> Bool {
        if fresh { seen = false }
        if outsideText || claimed { seen = true }
        return seen
    }

    /// A runner found outside text during a turn.
    mutating func mark() { seen = true }
}
