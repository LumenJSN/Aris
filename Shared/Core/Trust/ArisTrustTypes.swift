//
//  ArisTrustTypes.swift
//  Shared/Core (aris-agent, tests)
//
//  The words of the trust policy (ARCHITECTURE Part 2, Judgment): where a call's instruction came from (provenance),
//  a standing permission the owner gave (a grant), what the policy says (a decision) and the owner's one "how much
//  Aris asks" control (the level). The app has its own ArisProvenance (a job's taint) and ArisGrant (onboarding), so
//  these are named ArisCallProvenance and ArisStandingGrant. Pure.
//

import Foundation

/// Where a capability call's instruction came from (ArisProvenanceTracker decides it, mechanically).
enum ArisCallProvenance: Equatable, Sendable, Codable {
    /// The owner's words of this turn ask for this effect and name its key arguments.
    case ownerSaid
    /// It follows from what the owner said earlier in the conversation or task.
    case ownerEarlier
    /// A step Aris takes toward what the owner asked (looking, a reversible change, or an act the owner did not name).
    case ownStep
    /// Suggested by text Aris read: a key argument first appeared there and the owner did not ask for it.
    case content(ArisContentSource)

    /// The table's column.
    var column: Column {
        switch self {
        case .ownerSaid: .ownerSaid
        case .ownerEarlier: .ownerEarlier
        case .ownStep: .ownStep
        case .content: .content
        }
    }

    enum Column: String, CaseIterable, Codable, Sendable {
        case ownerSaid, ownerEarlier, ownStep, content
    }

    var source: ArisContentSource? {
        if case .content(let source) = self { return source }
        return nil
    }
}

/// Where content came from: the same two fields as a tool result's content mark (ArisToolResult.Content).
struct ArisContentSource: Equatable, Hashable, Sendable, Codable {
    /// "web", "file", "shell", "app", "mail", "messages", "notes", "service", "screen", "aris".
    let kind: String
    /// The address, the path, the command, the app or service.
    let source: String

    /// Said to the owner: "웹 페이지 example.com", "파일 README.md".
    var spoken: String {
        let shown = kind == "file" ? (source as NSString).lastPathComponent : source
        return (ArisContentSource.kindWords[kind] ?? kind) + " " + String(shown.prefix(60))
    }

    static let kindWords = ["web": "웹 페이지", "file": "파일", "shell": "명령 출력", "app": "앱 화면", "mail": "메일", "messages": "메시지",
                            "notes": "메모", "service": "서비스", "screen": "화면", "aris": "Aris"]
}

/// The owner's one control over how much Aris asks (Settings; ArisTrustSettings keeps it).
enum ArisTrustLevel: String, CaseIterable, Codable, Sendable {
    /// Asks for every permanent or outward action.
    case careful
    /// The table as the user set it (ARCHITECTURE Part 2).
    case standard
    /// Permanent actions the owner asked for run without the spoken moment; outward ones he fully specified run at once.
    case free
}

/// What the policy says about one call.
enum ArisDecision: Equatable, Sendable {
    /// Run it.
    case run
    /// Run it and keep its undo in the record; `announce`: say aloud what was done (content suggested it).
    case runWithUndo(announce: Bool)
    /// Say what is about to happen, wait `delay` seconds for a "stop", then run (the countdown card).
    case sayThenRun(delay: TimeInterval)
    /// Read the whole action back (recipient, text, files) and run on the owner's yes.
    case readBackThenAsk
    /// Ask the owner first.
    case ask
    /// Refuse, and tell the owner why (`reason`, Korean first).
    case refuse(reason: String)

    /// The decision runs nothing until the owner answers.
    var waitsForOwner: Bool {
        switch self {
        case .readBackThenAsk, .ask: true
        case .run, .runWithUndo, .sayThenRun, .refuse: false
        }
    }

    /// Short form for the record and actions.log.
    var label: String {
        switch self {
        case .run: "run"
        case .runWithUndo(let announce): announce ? "runWithUndo+said" : "runWithUndo"
        case .sayThenRun(let delay): "sayThenRun(\(Int(delay))s)"
        case .readBackThenAsk: "readBackThenAsk"
        case .ask: "ask"
        case .refuse: "refuse"
        }
    }
}

/// One key argument of a call: what the policy and the provenance tracker look at. Everything else in a call (a
/// title, a format, a timeout) decides nothing.
struct ArisKeyArgument: Equatable, Hashable, Sendable, Codable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        /// Who it goes to: an address, a number, a name.
        case recipient
        /// A file or folder it touches.
        case path
        /// The app it acts in.
        case app
        /// A command line it runs.
        case command
        /// A web address it opens or posts to.
        case url
        /// The text it carries (a message's body, what is typed).
        case body
        /// Money: how much, and to whom.
        case amount, payee
    }

    let kind: Kind
    let value: String
}

/// A call as the policy sees it: its capability, its key arguments, and whether it is a payment.
/// What a replace would erase: the field's text now (nil: it couldn't be read), and whether a copy of it can be kept for
/// the undo.
struct ArisErasedText: Equatable, Sendable {
    let text: String?
    let keepable: Bool
}

struct ArisCallFacts: Equatable, Sendable {
    /// The registry's dotted id ("mail.send", "shell.run", "aris.message").
    let capability: String
    let arguments: [ArisKeyArgument]
    /// The call moves money (the registry says so, or it carries an amount or payee).
    var payment = false
    /// The folder a command runs in (shell.run's `cwd`); nil: the home folder.
    var cwd: String?
    /// The capability registry marks this call as a payment (its entry's `payment`; decision 1): it asks on a card of
    /// its own every time. A call that only carries an amount or a payee is `payment` but not this.
    var registeredPayment = false
    /// An act on a browser window's page (decision 2): its host and element; nil for anything else.
    var browser: ArisBrowserPage?
    /// A shell line whose first program is osascript: its card is titled 스크립트 실행 (ArisAskPlan.verb). Presentation
    /// only: no rule reads it.
    var scriptTitle = false
    /// A read rated a send by the outbound rule (ArisWebCarry): everything it sends (the whole address, the whole
    /// words), for its card to show whole; such a call is never kept as "always". Nil for anything else.
    var sends: String?
    /// A replace of a field's whole value (app.type replace): what it would erase, read just before the card, for the
    /// card to show (fourth VM run, D1). Presentation only: no rule reads it.
    var erases: ArisErasedText?
    /// The call puts input into an app (ArisContentReach.isInput): one that content drives asks.
    var inputAct = false
    /// An address in the call first appeared in content the owner didn't point at, and not in a page Aris fetched from
    /// the public web itself (ArisContentReach): the call asks.
    var contentAddress = false
    /// What each path the call changes is, read at the moment of the decision (ArisBroadTarget), for its card.
    var pathTargets: [ArisPathTarget] = []
    /// The call removes or moves a whole folder the owner named (ArisBroadTarget): a card of its own, every time.
    var wholeFolder: ArisPathTarget?
    /// Words handed to something that then works on its own (Aside, a job, a schedule, a routine, a coding session),
    /// as its card reads them back (ArisHandOffCard): a card of its own every time, never kept. Nil for anything else.
    var handOff: ArisHandOffFacts?
    /// The card's own title for an aris-tools act its words name ("일정 지우기": ArisToolWords.title), in place of the
    /// effect's bare verb. Presentation only: no rule reads it.
    var actionTitle: String?

    init(capability: String, arguments: [ArisKeyArgument], payment: Bool = false, cwd: String? = nil, registeredPayment: Bool = false,
         browser: ArisBrowserPage? = nil) {
        self.browser = browser
        self.capability = capability
        self.arguments = arguments
        self.payment = payment || registeredPayment || arguments.contains { $0.kind == .amount || $0.kind == .payee }
        self.cwd = cwd
        self.registeredPayment = registeredPayment
    }

    func values(_ kind: ArisKeyArgument.Kind) -> [String] { arguments.filter { $0.kind == kind }.map(\.value) }

    /// Every target a grant could be scoped to: recipients, paths, apps, addresses.
    var targets: [ArisKeyArgument] { arguments.filter { [.recipient, .path, .app, .url, .payee].contains($0.kind) } }
}

/// A standing permission ("앞으로 엄마한테 보내는 건 묻지 마"): a capability or an effect class, optionally narrowed to
/// a target (a recipient, a folder, an app), optionally until a moment. Learned from the owner's words or added in
/// Settings; never from anything Aris read.
struct ArisStandingGrant: Equatable, Sendable, Codable, Identifiable {
    let id: UUID
    /// A capability id ("mail.send"), or a family ("mail.*"); nil: any capability of `effect`.
    let capability: String?
    /// The effect class it covers; nil: whatever `capability` does.
    let effect: ArisEffectClass?
    /// What it is narrowed to; nil: anything.
    let target: Target?
    let expires: Date?
    let created: Date
    /// The owner's words it was learned from (cut short), for Settings.
    let words: String?

    struct Target: Equatable, Sendable, Codable {
        let kind: ArisKeyArgument.Kind
        /// A recipient's name or address, a folder (a path covers what is inside it), an app's name.
        let pattern: String
        /// The addresses a recipient's name stands for (from the World's contacts when it was learned).
        var addresses: [String] = []
    }

    init(id: UUID = UUID(), capability: String? = nil, effect: ArisEffectClass? = nil, target: Target? = nil, expires: Date? = nil,
         created: Date = Date(), words: String? = nil) {
        self.id = id
        self.capability = capability
        self.effect = effect
        self.target = target
        self.expires = expires
        self.created = created
        self.words = words.map { String($0.prefix(120)) }
    }

    /// A grant must say what it covers: a capability or an effect, and never the never-list or plain looking.
    var isWellFormed: Bool {
        guard capability != nil || effect != nil, effect != .never, effect != .observe else { return false }
        if let capability, capability.isEmpty || capability.count > 80 || capability == "*" { return false }
        if let target, target.pattern.trimmingCharacters(in: .whitespaces).isEmpty || target.pattern.count > 300 { return false }
        return true
    }
}
