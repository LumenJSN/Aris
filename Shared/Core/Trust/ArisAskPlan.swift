//
//  ArisAskPlan.swift
//  Shared/Core (aris-agent, tests)
//
//  Asking well when Aris does ask: one ask per intent, not per call. The calls of one turn or task that wait for the
//  owner are put on one card with every one of them read back ("메일 3통: 엄마, 민수, 지현"); the say-then-run ones on one
//  countdown card. An answer is yes, "yes, always for this" (a standing grant for each target, never for something
//  content suggested), or no. A yes covers its intent for the rest of the turn: a later call of the same capability
//  and effect to a target already read back runs without a second card. The card's fields are the existing confirm
//  line's (ArisConfirmation in the app), so the card UI works unchanged.
//  A payment (decision 1) is never grouped, never covered and never kept: each one is a card of its own that reads
//  back what is paid, to whom and how much (or says it couldn't read them), says which of those the owner didn't
//  name and where they were read from, and runs on that card's yes only, for that one step. An act on a browser's
//  page (decision 2) is the same: a card of its own naming the site's host, never covered, never kept. Pure.
//

import Foundation

/// One call waiting for the owner.
struct ArisAskItem: Equatable, Sendable {
    let call: String
    let facts: ArisCallFacts
    let effect: ArisEffectClass
    let decision: ArisDecision
    let provenance: ArisCallProvenance
    /// The key-argument kinds the owner's own words gave (the payment card says which it lacks).
    var ownerNamed: Set<ArisKeyArgument.Kind> = []
    /// The content the owner pointed at that an amount or payee was read from (the payment card says so).
    var readFrom: ArisContentSource? = nil
    /// The call is the content's only because content asked for that kind of act and the owner's words didn't: no value
    /// in it came from what was read (ArisProvenanceVerdict.inspired), and the card says that, not "suggested".
    var inspired = false
}

/// A call as its owner's own earlier instruction says it, when there is one: a taught step of a replay (F3), worded
/// from the very step and values the call was made from (fifth VM run, D2: its card read "바꾸기 TextEdit $ =File › New
/// [cmd+n]" under an English UI). It takes the place of the call's summary line and the card's title and spoken words
/// only: every fact the card reads back about the call (where it came from, what it erases or sends) stays, and its
/// arguments are still read back in full under it.
struct ArisAskDescription: Equatable, Sendable {
    let title: String
    let line: String
    let spoken: String
    /// Where the call came from, in the card's words, when the replay made it from the owner's saved step: said in
    /// place of "읽은 내용(…)이 제안한 일이에요" (seventh VM run, item 6: a step he taught read "Suggested by what was
    /// read (app window TextEdit)", because the app's name was in an earlier step's result). Only for a call whose key
    /// arguments are exactly `arguments`; the decision, its rating and every other line of the card stay as they are.
    var origin: String? = nil
    /// Said after `origin` when the card also shows what a replace erases, read from the app just before the card.
    var originErases: String? = nil
    /// The key arguments of the call the step was made into.
    var arguments: [ArisKeyArgument] = []
    /// What is said in place of `spoken` when the call turns out to erase text (typing over a selection, read when the
    /// step runs): the question still says that text is erased.
    var spokenErases: String? = nil

    init(title: String, line: String, spoken: String, origin: String? = nil, originErases: String? = nil, arguments: [ArisKeyArgument] = []) {
        self.title = title
        self.line = line
        self.spoken = spoken
        self.origin = origin
        self.originErases = originErases
        self.arguments = arguments
    }

    /// The card's line about where `item` came from, when this description says it truthfully for exactly that call:
    /// its key arguments the same, in the same order and as many (a duplicated or reordered argument is no match).
    func origin(for item: ArisAskItem) -> String? {
        guard let origin, !arguments.isEmpty, arguments == item.facts.arguments else { return nil }
        guard let erases = originErases, item.facts.erases?.text != nil else { return origin }
        return origin + " " + erases
    }
}

/// The card, in the confirm line's own fields.
struct ArisAskCard: Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let full: String?
    /// A countdown card: said aloud, run unless stopped.
    let countdown: Bool
    let spoken: String
    let calls: [String]
    let intent: String
    /// What "yes, always" keeps, as shown on the card (its full details): exactly the targets read back.
    var alwaysScope: [String] = []

    /// A countdown card for one message: its title is the recipient and its detail the text, as the app's message card
    /// reads them (받는 사람, 메시지). Any other countdown card is an action's (`action` in the confirm line).
    var isMessage: Bool { countdown && message }
    var message = false

    /// The confirm line's fields (ArisAgentReply's `confirm` object).
    var confirmFields: [String: Any] {
        var fields: [String: Any] = ["id": id, "title": title, "detail": detail, "spoken": spoken]
        if countdown { fields["countdown"] = true }
        if countdown && !message { fields["action"] = true }
        if let full { fields["full"] = full }
        return fields
    }
}

enum ArisAskAnswer: Equatable, Sendable {
    case yes, always, no

    /// The answer from the card (POST /confirm's allow, and `always` when the app sends it) or from words.
    static func from(allow: Bool, always: Bool = false) -> ArisAskAnswer { allow ? (always ? .always : .yes) : .no }

    /// Spoken or typed, read with the card's own words (ArisAnswerWords), negation first and failing closed:
    ///   a no or any negation, with no yes in the sentence             -> .no
    ///   a negation and a yes or "always" together ("아니, 항상 그러지 마") -> nil (asked again)
    ///   "always" with a clear yes and no negation ("응, 앞으로도 그렇게 해") -> .always
    ///   the card's short yes ("응", "보내")                              -> .yes
    ///   anything else                                                  -> nil
    /// "묻지 마" / "don't ask" said as consent is taken out before negation is looked for.
    static func parse(_ words: String) -> ArisAskAnswer? {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 60 else { return nil }
        let always = ArisAnswerWords.matches(text, ArisAnswerWords.always)
        let rest = text.replacingOccurrences(of: ArisAnswerWords.consentIdioms, with: " ", options: .regularExpression)
        let idiom = rest != text
        let negated = ArisAnswerWords.matches(rest, ArisAnswerWords.negation)
        // A yes word inside a negated phrase ("보내지 마", "don't send") is no yes.
        let unnegated = rest.replacingOccurrences(of: ArisAnswerWords.negatedPhrase, with: " ", options: .regularExpression)
        let affirmed = ArisAnswerWords.matches(unnegated, ArisAnswerWords.affirmative) || idiom
        if negated { return affirmed || always ? nil : .no }
        if always { return affirmed ? .always : nil }
        if ArisAnswerWords.matches(text, ArisAnswerWords.yes) { return .yes }
        return nil
    }
}

struct ArisAskPlan: Sendable {
    /// Cards waiting for an answer, by id.
    private(set) var open: [String: (card: ArisAskCard, items: [ArisAskItem])] = [:]
    /// What a yes approved, per intent: capability + effect → targets read back.
    private(set) var approved: [String: [String: Set<String>]] = [:]
    var makeID: @Sendable () -> String = { "trust-" + UUID().uuidString.lowercased() }

    static let detailLines = 6
    static let lineLength = 90

    init(makeID: @escaping @Sendable () -> String = { "trust-" + UUID().uuidString.lowercased() }) {
        self.makeID = makeID
    }

    /// The calls of one step that wait for the owner, as cards: at most one asking card and one countdown card per
    /// intent. A call a yes of this intent already covers is not on any card (`covered` lists it).
    /// `described`: the calls a replay words itself (ArisAskDescription), by call id.
    mutating func plan(_ items: [ArisAskItem], intent: String, home: String, described: [String: ArisAskDescription] = [:])
        -> (cards: [ArisAskCard], covered: [String]) {
        var covered: [String] = []
        var asking: [ArisAskItem] = [], countdown: [ArisAskItem] = [], payments: [ArisAskItem] = [], pages: [ArisAskItem] = []
        var folders: [ArisAskItem] = [], handOffs: [ArisAskItem] = []
        for item in items {
            if isCovered(item, intent: intent) { covered.append(item.call); continue }
            // A hand-off (twelfth VM run, B1): a card of its own every time, its words read back whole, never counted down.
            if item.facts.handOff != nil, item.decision.waitsForOwner || item.decision.label.hasPrefix("sayThenRun") {
                handOffs.append(item)
                continue
            }
            // A payment that waits (or, from any path, would run after a spoken moment) is a card of its own.
            if item.facts.registeredPayment, item.decision.waitsForOwner || item.decision.label.hasPrefix("sayThenRun") {
                payments.append(item)
                continue
            }
            // An act in a browser (decision 2): a card of its own, every time.
            if item.facts.browser != nil, item.decision.waitsForOwner || item.decision.label.hasPrefix("sayThenRun") {
                pages.append(item)
                continue
            }
            // A whole folder removed or moved (ArisBroadTarget): a card of its own, every time.
            if item.facts.wholeFolder != nil, item.decision.waitsForOwner || item.decision.label.hasPrefix("sayThenRun") {
                folders.append(item)
                continue
            }
            switch item.decision {
            case .ask, .readBackThenAsk: asking.append(item)
            case .sayThenRun: countdown.append(item)
            case .run, .runWithUndo, .refuse: continue
            }
        }
        var cards: [ArisAskCard] = []
        for payment in payments {
            let card = Self.paymentCard(payment, id: makeID(), intent: intent)
            open[card.id] = (card, [payment])
            cards.append(card)
        }
        for page in pages {
            let card = Self.browserCard(page, id: makeID(), intent: intent)
            open[card.id] = (card, [page])
            cards.append(card)
        }
        for folder in folders {
            let card = Self.folderCard(folder, id: makeID(), intent: intent, home: home)
            open[card.id] = (card, [folder])
            cards.append(card)
        }
        for item in handOffs {
            guard let handOff = item.facts.handOff else { continue }
            let card = ArisHandOffCard.card(item, handOff: handOff, id: makeID(), intent: intent, outside: Self.outsideLine([item], described: [:]))
            open[card.id] = (card, [item])
            cards.append(card)
        }
        for (group, isCountdown) in [(asking, false), (countdown, true)] where !group.isEmpty {
            let card = Self.card(group, id: makeID(), intent: intent, countdown: isCountdown, home: home, described: described)
            open[card.id] = (card, group)
            cards.append(card)
        }
        return (cards, covered)
    }

    /// The owner's answer to a card: the calls that now run, the grants to keep, the calls refused. An unknown card id
    /// does nothing (it was answered already, or never Aris's).
    mutating func answer(_ id: String, _ answer: ArisAskAnswer, home: String, now: Date = Date())
        -> (run: [String], grants: [ArisStandingGrant], refused: [String]) {
        guard let (card, items) = open.removeValue(forKey: id) else { return ([], [], []) }
        guard answer != .no else { return ([], [], items.map(\.call)) }
        // A payment's yes is for that one step: nothing is approved for later calls.
        for item in items where !item.facts.registeredPayment && item.facts.browser == nil && !Self.everyTime(item) && item.facts.handOff == nil {
            approved[card.intent, default: [:]][Self.key(item), default: []].formUnion(Self.targets(item))
        }
        let grants = answer == .always ? items.flatMap { Self.grants(for: $0, now: now, home: home) } : []
        var seen: [String] = []
        let unique = grants.filter { grant in
            let key = "\(grant.capability ?? "")|\(grant.effect?.rawValue ?? "")|\(grant.target?.pattern ?? "")"
            if seen.contains(key) { return false }
            seen.append(key)
            return true
        }
        return (items.map(\.call), unique, [])
    }

    /// The turn or task ended: its yeses end with it.
    mutating func end(intent: String) {
        approved[intent] = nil
        open = open.filter { $0.value.card.intent != intent }
    }

    func isCovered(_ item: ArisAskItem, intent: String) -> Bool {
        // A call that erases text shows what it erases on a card of its own, whatever was allowed before it; so does a
        // whole folder (ArisAskPlan.everyTime).
        guard item.provenance.source == nil, !item.facts.registeredPayment, item.facts.browser == nil, item.facts.sends == nil, item.facts.erases == nil,
              item.facts.handOff == nil, !Self.everyTime(item), let targets = approved[intent]?[Self.key(item)] else { return false }
        let wanted = Self.targets(item)
        return !wanted.isEmpty && wanted.isSubset(of: targets)
    }

    private static func key(_ item: ArisAskItem) -> String { item.facts.capability + "|" + item.effect.rawValue }

    private static func targets(_ item: ArisAskItem) -> Set<String> {
        Set(item.facts.targets.map { $0.kind.rawValue + ":" + ArisGrounding.fold($0.value) })
    }

    /// "Yes, always for this": one grant per target exactly as the card read it back (a file is that file, never its
    /// folder), scoped to the capability and its effect. Never for content, never for a payment, never for a scope
    /// that is a root, the home folder, a system folder or Aris's own (ArisStandingGrant.isSafe).
    static func grants(for item: ArisAskItem, now: Date, home: String) -> [ArisStandingGrant] {
        guard item.provenance.source == nil, !item.facts.payment, item.facts.browser == nil, item.facts.sends == nil, !everyTime(item),
              item.facts.handOff == nil, item.effect == .outward || item.effect == .changePermanent else { return [] }
        let targets = item.facts.targets
        if targets.isEmpty {
            return [ArisStandingGrant(capability: item.facts.capability, effect: item.effect, created: now, words: alwaysWords)]
        }
        return targets.map { target in
            ArisStandingGrant(capability: item.facts.capability, effect: item.effect, target: .init(kind: target.kind, pattern: target.value),
                              created: now, words: alwaysWords)
        }.filter { $0.isSafe(home: home) }
    }

    static let alwaysWords = "카드에서 항상 허용"

    /// A call that is a card every time, never covered by an earlier yes and never kept as "always": a whole folder
    /// removed or moved, and a replace whose erased text couldn't be read (tenth VM run, items 2 and 4).
    static func everyTime(_ item: ArisAskItem) -> Bool {
        item.facts.wholeFolder != nil || (item.facts.erases != nil && item.facts.erases?.text == nil)
    }

    /// A whole folder's own card: that it is the whole folder and how many items it holds, where it is in full, what is
    /// done to it, and that the yes is for this once. Never a countdown, never "always".
    static func folderCard(_ item: ArisAskItem, id: String, intent: String, home: String) -> ArisAskCard {
        let folder = item.facts.wholeFolder ?? ArisPathTarget(path: item.facts.values(.path).first ?? "", kind: .unknown)
        let what = verb(item)
        var lines = ["폴더 전체예요: " + ArisBroadTarget.holds(folder), "위치: " + ArisBroadTarget.abbreviated(folder.path, home: home)]
        if let outside = outsideLine([item], described: [:]) { lines.insert(outside, at: 0) }
        for target in item.facts.pathTargets where target.path != folder.path {
            lines.append(target.kind.word + ": " + ArisBroadTarget.abbreviated(target.path, home: home))
        }
        lines.append("이 폴더에 이번 한 번만이에요. 다음에는 다시 물어봐요.")
        let shown = lines.flatMap { wrapped($0, width: lineLength) }
        return ArisAskCard(id: id, title: "폴더 통째로 " + what + " · " + folder.name, detail: shown.joined(separator: "\n"), full: nil, countdown: false,
                           spoken: "‘\(folder.name)’ 폴더 전체를 \(what), 할까요? \(ArisBroadTarget.holds(folder))예요.", calls: [item.call], intent: intent)
    }

    /// What "yes, always" would keep, in words for the card: exactly these targets.
    static func alwaysScope(_ items: [ArisAskItem], home: String) -> [String] {
        items.flatMap { grants(for: $0, now: Date(), home: home) }.map { grant in
            // Never a capability's id (twelfth VM run, B1-showall: "보내기 · aris.aside_task"): its name as the owner reads it.
            let what = grant.target.map { $0.kind == .path ? ($0.pattern as NSString).lastPathComponent : $0.pattern }
                ?? grant.capability.flatMap { ArisCapabilityNames.name($0)?.korean }
            return verb(grant.effect ?? .outward, capability: grant.capability ?? "") + (what.map { " · " + $0 } ?? "")
        }
    }

    // MARK: - The card

    static func card(_ items: [ArisAskItem], id: String, intent: String, countdown: Bool, home: String,
                     described: [String: ArisAskDescription] = [:]) -> ArisAskCard {
        let lines = items.enumerated().map { index, item in (items.count > 1 ? "\(index + 1). " : "") + (described[item.call]?.line ?? line(item)) }
        let outside = Self.outsideLine(items, described: described)
        let shown = (outside.map { [$0] } ?? []) + lines.prefix(detailLines).map { ArisTextClip.clip($0, lineLength) }
            + (lines.count > detailLines ? ["외 \(lines.count - detailLines)건"] : []) + items.flatMap(sendsLines) + items.flatMap(erasesLines)
        let detail = shown.joined(separator: "\n")
        let scope = alwaysScope(items, home: home)
        let alwaysLine = scope.isEmpty ? [] : ["‘항상’이라고 하시면 앞으로 이것만 묻지 않아요: " + scope.joined(separator: ", ")]
        let full = items.enumerated().map { index, item -> String in
            let said = described[item.call]?.line ?? line(item)
            return (items.count > 1 || described[item.call] != nil ? (items.count > 1 ? "\(index + 1). " : "") + said + "\n" : "") + fullLine(item)
        }
        let fullText = ((outside.map { [$0] } ?? []) + full + items.flatMap(sendsLines) + items.flatMap(erasesLines) + alwaysLine).joined(separator: "\n")
        // One message said before it goes: the recipient and the text alone, nothing else (VM run 2026-11-19, D7: the
        // card read "보내기 · 010-…" as the recipient and "보내기 → 010-… 「…」" as the message).
        if countdown, let message = messageParts(items) {
            var card = ArisAskCard(id: id, title: message.to, detail: message.text, full: nil, countdown: true, spoken: spoken(items, countdown: true),
                                   calls: items.map(\.call), intent: intent, alwaysScope: scope)
            card.message = true
            return card
        }
        // One call a replay words itself: its title and spoken words are that step's (the card is the step's card).
        let own = items.count == 1 ? described[items[0].call] : nil
        let ownSpoken = items.first?.facts.erases != nil ? own?.spokenErases ?? own?.spoken : own?.spoken
        return ArisAskCard(id: id, title: own?.title ?? title(items), detail: detail, full: fullText == detail ? nil : fullText, countdown: countdown,
                           spoken: ownSpoken ?? spoken(items, countdown: countdown), calls: items.map(\.call), intent: intent, alwaysScope: scope)
    }

    /// The card's line about what content suggested: "읽은 내용(…)이 제안한 일이에요." for the first call content
    /// suggested. A replay's own step says where it really came from (its saved step, ArisAskDescription.origin) only
    /// when every call content suggested on the card has such a line for exactly that call; one that hasn't keeps the
    /// warning for the card (a miss is never less strict than a hit). Nil when content suggested none of them.
    static func outsideLine(_ items: [ArisAskItem], described: [String: ArisAskDescription]) -> String? {
        let suggested = items.filter { $0.provenance.source != nil }
        guard let first = suggested.first else { return nil }
        let origins = suggested.map { described[$0.call]?.origin(for: $0) }
        if origins.allSatisfy({ $0 != nil }) {
            var lines: [String] = []
            for case let line? in origins where !lines.contains(line) { lines.append(line) }
            return lines.joined(separator: " ")
        }
        let warned = zip(suggested, origins).first { $0.1 == nil }?.0 ?? first
        // No value on the card came from what was read: said as it is, never "suggested" (tenth VM run, item 11).
        if warned.inspired { return inspiredLine }
        return "읽은 내용(\(warned.provenance.source?.spoken ?? ""))이 제안한 일이에요."
    }

    /// Said in place of "읽은 내용(…)이 제안한 일이에요" when the call's values are all the owner's or Aris's own and only
    /// the kind of act wasn't found in their words.
    static let inspiredLine = "말씀하신 내용에서 이 일을 해 달라는 말은 찾지 못해서 여쭤봐요."

    /// A payment's own card: what is paid, to whom, how much (or that it couldn't be read), every argument of the call
    /// in full (wrapped, never cut), what the owner didn't name and where it was read, and that the yes is for this one
    /// payment. Never a countdown, never "always". (The policy refuses a payment with two amounts or payees, or one too
    /// long to show: ArisTrustPolicy.unreadablePayment.)
    static func paymentCard(_ item: ArisAskItem, id: String, intent: String) -> ArisAskCard {
        let facts = item.facts
        let payees = unique(facts.values(.payee) + facts.values(.recipient)), amounts = unique(facts.values(.amount))
        var lines = ["받는 곳: " + (payees.isEmpty ? "읽지 못했어요 (확인해 주세요)" : payees.joined(separator: ", ")),
                     "금액: " + (amounts.isEmpty ? "읽지 못했어요 (확인해 주세요)" : amounts.joined(separator: ", "))]
        for argument in facts.arguments where ![.payee, .amount].contains(argument.kind) && !(argument.kind == .recipient && payees.contains(argument.value)) {
            lines.append(argumentWord(argument.kind) + ": " + argument.value)
        }
        let named = item.ownerNamed
        var unnamed: [String] = []
        if !payees.isEmpty, !named.contains(.payee), !named.contains(.recipient) { unnamed.append("받는 곳") }
        if !amounts.isEmpty, !named.contains(.amount) { unnamed.append("금액") }
        if let source = item.readFrom {
            lines.append("받는 곳이나 금액 중 직접 말씀하지 않은 것은 \(source.spoken)에서 읽은 거예요.")
        }
        if !unnamed.isEmpty, item.readFrom == nil { lines.append(unnamed.joined(separator: "·") + "은 직접 말씀하지 않으셨어요.") }
        lines.append("이번 결제 한 번만이에요. 다음 결제는 다시 물어봐요.")
        let shown = lines.flatMap { wrapped($0, width: lineLength) }
        let detail = shown.joined(separator: "\n")
        let full = (shown + [fullLine(item)]).joined(separator: "\n")
        let title = (["결제"] + payees + amounts).joined(separator: " · ")
        let to = payees.first, amount = amounts.first
        let spoken = to.map { to in amount.map { "\(to)에 \($0) 결제할까요?" } ?? "\(to)에 결제할까요? 금액은 읽지 못했어요." }
            ?? "결제할까요? 받는 곳은 읽지 못했어요."
        return ArisAskCard(id: id, title: title, detail: detail, full: full, countdown: false, spoken: spoken, calls: [item.call], intent: intent)
    }

    /// An act in a browser's card (decision 2): the site's host first (or that it couldn't be read), the app, what is
    /// acted on, the text typed, and that the yes is for this one step on this page. Never a countdown, never "always".
    static func browserCard(_ item: ArisAskItem, id: String, intent: String) -> ArisAskCard {
        let page = item.facts.browser ?? ArisBrowserPage()
        let app = item.facts.values(.app).first ?? "브라우저"
        let verb = browserVerb(item.facts.capability)
        var lines = ["사이트: " + (page.host ?? "주소를 읽지 못했어요 (확인해 주세요)") + " · " + app]
        if let target = page.target, !target.isEmpty { lines.append("대상: " + target) }
        for argument in item.facts.arguments where argument.kind != .app { lines.append(argumentWord(argument.kind) + ": " + argument.value) }
        if let source = item.provenance.source { lines.insert("읽은 내용(\(source.spoken))이 제안한 일이에요.", at: 0) }
        lines.append("이 페이지에서 이번 한 번만이에요. 다음 동작은 다시 물어봐요.")
        let shown = lines.flatMap { wrapped($0, width: lineLength) }
        let host = page.host ?? app
        return ArisAskCard(id: id, title: verb + " · " + host, detail: shown.joined(separator: "\n"), full: (shown + [fullLine(item)]).joined(separator: "\n"),
                           countdown: false, spoken: "\(host)에서 \(verb), 할까요?", calls: [item.call], intent: intent)
    }

    static func browserVerb(_ capability: String) -> String {
        switch capability {
        case "app.click": "누르기"
        case "app.type": "입력하기"
        case "app.press": "키 누르기"
        case "app.select": "고르기"
        default: "하기"
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert(ArisGrounding.fold($0)).inserted }
    }

    private static func argumentWord(_ kind: ArisKeyArgument.Kind) -> String {
        switch kind {
        case .recipient: "받는 사람"
        case .path: "파일"
        case .app: "앱"
        case .command: "명령"
        case .url: "주소"
        case .body: "내용"
        case .amount: "금액"
        case .payee: "받는 곳"
        }
    }

    /// A line broken into pieces of at most `width` characters, nothing left out.
    static func wrapped(_ line: String, width: Int) -> [String] {
        guard line.count > width, width > 0 else { return [line] }
        var pieces: [String] = [], rest = Substring(line)
        while !rest.isEmpty {
            pieces.append(String(rest.prefix(width)))
            rest = rest.dropFirst(width)
        }
        return pieces
    }

    /// The capabilities that send one plain message (a text to people), and nothing else: only these get the message card.
    static let plainMessageSends: Set<String> = ["aris.send_message", "aris.message", "message.send"]

    /// One plain message: who it goes to and what it says. Only for a call that carries nothing else (no file, address,
    /// app, command, amount or payee, no second text, not a payment) of a plain message send: anything more stays on
    /// the full card, every fact read back (security review of D7).
    static func messageParts(_ items: [ArisAskItem]) -> (to: String, text: String)? {
        guard items.count == 1, let item = items.first, item.effect == .outward, item.provenance.source == nil, !item.facts.payment,
              plainMessageSends.contains(item.facts.capability.lowercased()),
              item.facts.arguments.allSatisfy({ $0.kind == .recipient || $0.kind == .body }) else { return nil }
        let to = item.facts.values(.recipient), bodies = item.facts.values(.body)
        guard !to.isEmpty, bodies.count == 1, let text = bodies.first?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let names = to.joined(separator: ", ")
        return names.count <= 120 ? (names, text) : nil
    }

    static func verb(_ effect: ArisEffectClass, capability: String) -> String {
        switch effect {
        case .outward: capability.contains("pay") || capability.contains("order") ? "결제" : capability.contains("post") ? "올리기" : "보내기"
        case .changePermanent: capability.contains("shell") || capability.contains("run") ? "실행" : "지우기"
        case .changeReversible: "바꾸기"
        case .observe: "보기"
        case .never: "하지 않기"
        }
    }

    /// The item's verb: as `verb(_:capability:)`, except a shell line whose first program is osascript (as the gate's
    /// own splitter read it: ArisCallFacts.scriptTitle) is titled as what it is, a script run, never "보내기" (VM run 2,
    /// H2: Finder's "get selection" was put on a 보내기 card). Presentation only: the class and the decision are the
    /// shell rule's, untouched.
    static func verb(_ item: ArisAskItem) -> String {
        if item.facts.erases != nil { return replaceText }
        if let own = item.facts.actionTitle { return own }
        return item.facts.scriptTitle ? scriptRun : verb(item.effect, capability: item.facts.capability)
    }
    static let scriptRun = "스크립트 실행"
    /// A field's whole text replaced (app.type replace): what it is, never "지우기" alone (fourth VM run, D1).
    static let replaceText = "글 바꾸기"

    /// What a replace erases, for its card (fourth VM run, D1: "Delete · TextEdit" showed only the new text): its length
    /// and first lines, and whether "되돌려" can put it back.
    static func erasesLines(_ item: ArisAskItem) -> [String] {
        guard let erases = item.facts.erases else { return [] }
        // Where the new text is from, when it is his own words of this turn (eleventh VM run, item 1: the card had no such line).
        let origin = item.provenance.source == nil && item.ownerNamed.contains(.body) ? [newTextIsOwners] : []
        guard let text = erases.text else { return origin + [erasesUnread] }
        guard !text.isEmpty else { return origin + [erasesNothing] }
        let lines = text.components(separatedBy: CharacterSet.newlines)
        var shown = origin + ["지워지는 글 (\(text.count)자, \(lines.count)줄):"]
        shown += lines.prefix(3).map { "「" + ArisTextClip.clip($0, 60) + "」" }
        if lines.count > 3 { shown.append("…(\(lines.count - 3)줄 더)") }
        shown.append(erases.keepable ? erasesKept : erasesLost)
        return shown
    }
    /// What Allow does when the text couldn't be read for the card (eleventh VM run, item 1): it is read again right
    /// before anything is typed; text he hasn't seen stops it (ArisApps.TypeOver.unseen), and only a field that still
    /// can't be read is typed into unseen.
    static let erasesUnread = "지워질 글을 미리 읽지 못했어요. 허용하면 넣기 직전에 다시 읽어서, 못 보신 글이 있으면 멈추고 보여 드려요. 그때도 읽을 수 없으면 있던 글이 보지 못한 채 지워질 수 있어요."
    static let newTextIsOwners = "새로 넣을 글은 직접 말씀하신 그대로예요."
    static let erasesNothing = "지금 비어 있는 칸이라 지워지는 글은 없어요"
    static let erasesKept = "지운 글은 남겨 둬서, 되돌려 달라고 하면 다시 넣어요."
    static let erasesLost = "지운 글을 남겨 둘 수 없어서 되돌릴 수 없어요."

    static func title(_ items: [ArisAskItem]) -> String {
        guard let first = items.first else { return "확인" }
        var who: [String] = []
        for name in items.flatMap({ $0.facts.values(.recipient) + $0.facts.values(.app) }) where !who.contains(name) { who.append(name) }
        let names = who.prefix(3).joined(separator: ", ") + (who.count > 3 ? " 외 \(who.count - 3)" : "")
        let count = items.count > 1 ? " (\(items.count)건)" : ""
        return ArisTextClip.clip(verb(first) + (names.isEmpty ? "" : " · " + names) + count, 80)
    }

    /// One call read back: the capability's verb, where it goes, what it carries.
    static func line(_ item: ArisAskItem) -> String {
        let facts = item.facts
        var parts: [String] = []
        let to = facts.values(.recipient) + facts.values(.payee)
        if !to.isEmpty { parts.append("→ " + to.joined(separator: ", ")) }
        if let amount = facts.values(.amount).first { parts.append(amount) }
        // A path the call changes is read back in full with what it is (tenth VM run, item 2); any other by its name.
        let kinds = Dictionary(facts.pathTargets.map { ($0.path, $0.kind) }, uniquingKeysWith: { first, _ in first })
        let places = facts.values(.path).map { path in kinds[path].map { $0.word + " " + path } ?? (path as NSString).lastPathComponent }
            + facts.values(.app) + facts.values(.url)
        if !places.isEmpty { parts.append(places.joined(separator: ", ")) }
        if let command = facts.values(.command).first { parts.append(commandShown(command, capability: facts.capability)) }
        if let body = facts.values(.body).first { parts.append("「" + ArisTextClip.clip(body, 60) + "」") }
        return verb(item) + " " + parts.joined(separator: " ")
    }

    /// A command as a card reads it: a shell line after "$ "; an app's command (app.do) as the item it names, a taught
    /// step's exactness mark and key equivalent read as words ("=File › New [cmd+n]" → "‘File › New’ (⌘N)"), never the
    /// call's own syntax (fifth VM run, D2).
    static func commandShown(_ command: String, capability: String) -> String {
        capability == "app.do" ? commandValue(command, capability: capability) : "$ " + command
    }

    static func commandValue(_ command: String, capability: String) -> String {
        guard capability == "app.do" else { return command }
        let named = ArisApps.Exact.parse(command)
        let key = named.key.map { " (" + ArisTeachCopy.keys($0) + ")" } ?? ""
        return "‘" + named.text + "’" + key
    }

    /// What a read rated a send by the outbound rule sends, whole (wrapped, never cut), and why it asks.
    static func sendsLines(_ item: ArisAskItem) -> [String] {
        guard let sends = item.facts.sends else { return [] }
        return wrapped("보내는 내용: " + sends, width: lineLength) + [privateReadLine, privateReadEnglish]
    }

    static let privateReadLine = "이 대화에서 개인 내용을 읽어서 물어봐요. 이번 한 번만이에요."
    static let privateReadEnglish = "(Private content was read in this conversation; this yes is for this one call.)"

    /// The call's arguments read back in full, one labelled row each ("앱: TextEdit", "내용: …"), never a capability's
    /// id (fourth VM run, D8: the card showed a raw "[app.type] app" row).
    static func fullLine(_ item: ArisAskItem) -> String {
        let kinds = Dictionary(item.facts.pathTargets.map { ($0.path, $0.kind) }, uniquingKeysWith: { first, _ in first })
        let rows = item.facts.arguments.map { argument -> String in
            if argument.kind == .path, let kind = kinds[argument.value] { return kind.word + ": " + argument.value }
            return argumentWord(argument.kind) + ": " + (argument.kind == .command ? commandValue(argument.value, capability: item.facts.capability) : argument.value)
        }
        return rows.isEmpty ? line(item) : rows.joined(separator: "\n")
    }

    static func spoken(_ items: [ArisAskItem], countdown: Bool) -> String {
        guard let first = items.first else { return "" }
        if items.count == 1, first.effect == .outward, let to = first.facts.values(.recipient).first {
            let body = first.facts.values(.body).first.map { " ‘" + ArisTextClip.clip($0, 40) + "’" } ?? ""
            return countdown ? "\(to)한테\(body) 보낼게요." : "\(to)한테\(body) 보낼까요?"
        }
        let what = verb(first)
        return countdown ? "\(items.count)건 \(what) 할게요. 멈추려면 말씀하세요." : "\(items.count)건 \(what), 할까요?"
    }
}
