//
//  ArisThinking.swift
//  Aris (also built into aris-agent)
//
//  How hard a conversation brain thinks (the owner, 2026-11-14: "생각을 하고 답하든지… 알아볼께 이지랄하던가"). Every Claude turn
//  ran Haiku or Sonnet at effort low and Codex at effort low, so a question that needed looking into got a guess at once.
//  Then a normal turn was Sonnet at effort medium (Codex: medium); since 2026-11-17 a quick (spoken or plain chat) turn
//  is at low and other work at medium, from measurements (`efforts`, the one table); a turn that has to look things up (a vague question about
//  The user's own work, a report, a background job, the screen or a session to read and judge) is Opus at effort high (Codex:
//  high), and Aris says a short "알아볼게요" before the slow work starts. What the local router answers never reaches a
//  brain, and the small one-shot helpers (judges, dictation routes, sealed one-shots) keep their own low effort.
//  Who a vague question about the user's work goes to: Claude Code first, else another ready AI, else Aris digs itself and
//  asks one specific question only then. Pure, so the tests run it.
//

import Foundation

enum ArisThinking {
    /// The status a look-up turn starts with; the app says `lookingLine` at once on it (never after a wait).
    static let lookingStatus = "알아보는 중"

    static func lookingLine(korean: Bool) -> String { korean ? "알아볼게요." : "Let me look into it." }

    /// Whether the app says the short line at once for this status.
    static func saysAtOnce(_ status: String) -> Bool { status == lookingStatus }

    // MARK: - Which turns look things up

    /// Asking how the user's own work stands, for a report, or to find out: the answer has to be looked up first.
    private static let lookUpKorean = #"어떻게\s*(됐|되고|돼\s*가|되어\s*가|진행)|진행\s*(상황|상태|중인|된|됐)|현황|보고서|리포트|정리해\s*(줘|봐|서)|알아봐|알아\s*봐|"#
        + #"찾아봐|찾아\s*봐|조사해|살펴봐|분석해|파악해|세션"#
    private static let lookUpEnglish = #"(?i)\bhow('?s|\s+is|\s+are|\s+did|\s+has)?\b[^.?!]{0,60}\b(going|go|coming along|doing)\b|\bstatus\b|\breport\b|"#
        + #"\blook into\b|\bfind out\b|\bdig into\b|\bcatch me up\b|\bwhere (are|is) (we|my|the)\b|\bsessions?\b"#

    /// Whether a conversation turn has to look things up: its words ask for it, it reads the screen to judge (images or
    /// the screen's text came with it), or it is a background job. Never a hands-free turn (it may do little).
    static func looksUp(_ words: String, task: Bool, images: Bool, screenText: Bool, handsFree: Bool) -> Bool {
        guard !handsFree else { return false }
        if task || images || screenText { return true }
        return words.range(of: lookUpKorean, options: .regularExpression) != nil || words.range(of: lookUpEnglish, options: .regularExpression) != nil
    }

    /// The turn's tier: a look-up turn runs `.deep`; a careful (critical) one stays critical (the risk gate reads it),
    /// and thinks as hard.
    static func tier(_ tier: ArisTier, looksUp: Bool) -> ArisTier {
        tier == .critical || !looksUp ? tier : .deep
    }

    // MARK: - Model and effort

    /// The model a conversation or job runner of `brain` uses for `tier`: Claude is Sonnet for a normal turn and Opus
    /// for a look-up or careful one (never Haiku here: that is the one-shot helpers'); the others as ArisBrain says.
    static func model(_ brain: ArisBrain, tier: ArisTier) -> String {
        guard brain == .claude else { return brain.model(tier: tier) }
        return thinksHard(tier) ? "opus" : "sonnet"
    }

    /// How hard each tier thinks, on Claude and Codex, and why: the one table (jv-fastlane, 2026-11-17).
    /// `quick` is a spoken or plain chat turn (a fact, one command): measured on claude 2.1.327, Sonnet, Aris's ~10k-token
    /// system prompt, 5 plain Korean questions, warm process: first text at 510 ms median at low against 935 ms at
    /// medium, the same answers. Codex luna warm: 1279 ms at low against 1791 ms at medium. Low is the lowest both take.
    /// `work` (several steps, writing, planning) keeps medium; `deep` (a look-up, a job, the screen) and `critical`
    /// (sending, deleting, money: the gate reads it) keep high, as before.
    struct Effort: Equatable {
        let claude: String
        let codex: String
        let why: String
    }

    static let efforts: [ArisTier: Effort] = [
        .quick: Effort(claude: "low", codex: "low", why: "spoken or plain chat: first token first (measured 510 vs 935 ms warm)"),
        .work: Effort(claude: "medium", codex: "medium", why: "several steps or writing: keeps its depth"),
        .deep: Effort(claude: "high", codex: "high", why: "looks things up, a job or the screen: thinks hardest"),
        .critical: Effort(claude: "high", codex: "high", why: "sending, deleting, money: thinks hardest"),
    ]

    static func effort(_ tier: ArisTier) -> Effort { efforts[tier] ?? efforts[.work]! }

    /// Claude Code's effort for a turn of `tier` on a runner of `model`, sent before the turn when the process is at
    /// another one (ArisClaudeDriver: `apply_flag_settings`). Opus only ever answers deep and careful turns; Haiku is the
    /// one-shot helpers' and stays low.
    static func claudeEffort(model: String, tier: ArisTier) -> String {
        switch model {
        case "opus": return "high"
        case "haiku": return "low"
        default: return effort(tier).claude
        }
    }

    /// Claude Code's `--effort` when a runner of `model` starts: its most common turn's (a quick one for Sonnet), so the
    /// usual turn sends nothing first.
    static func claudeEffort(model: String) -> String { claudeEffort(model: model, tier: .quick) }

    /// Codex's effort for a turn of `tier`.
    static func codexEffort(tier: ArisTier) -> String { effort(tier).codex }

    static func thinksHard(_ tier: ArisTier) -> Bool { tier == .deep || tier == .critical }

    // MARK: - Who looks into the user's own work

    /// The order a vague question about the user's work is handed over in: Claude Code (it reads their files), then the others.
    static let handOffOrder: [ArisBrain] = [.claude, .codex, .antigravity, .api]

    /// The first of them that is ready on this Mac now; nil: none is, and Aris digs itself.
    static func handOffBrain(ready: (ArisBrain) -> Bool) -> ArisBrain? {
        handOffOrder.first(where: ready)
    }

    /// The turn's <reach> line: whom a vague question about the user's own work goes to now, or that Aris digs itself.
    static func reachLine(handTo brain: ArisBrain?) -> String {
        guard let brain else {
            return "<reach>No AI that can read the user's files is ready now: for a vague question about their own work, dig " +
                "yourself first (the screen, `memory`, the recent turns, `recall`, `find \"<words>\"` for their files, the web), then " +
                "ask one specific question that names your best guess (\"마케팅이 인스타그램 계정 말씀이세요?\"), never a general " +
                "\"더 알려 주세요\".</reach>"
        }
        let who = brain == .claude ? "Claude Code, which can read their files" : "\(brain.title), ready here while Claude Code isn't"
        return "<reach>For a vague question about the user's own work or projects, hand it out as one job: \"assignee\": \"clone\", " +
            "\"brain\": \"\(brain.rawValue)\" (\(who)).</reach>"
    }
}
