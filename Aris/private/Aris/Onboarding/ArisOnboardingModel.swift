//
//  ArisOnboardingModel.swift
//  Aris
//
//  The setup window's live state: the flow (ArisSetupFlow), what macOS says about each permission right now (checked
//  every second while the window is open, since System Settings tells Aris nothing), and the cards' real asks. What
//  touches macOS comes in as Actions (ArisOnboardingSystem.live), so the tests and the offscreen renders can drive any
//  card without asking for anything.
//

import Foundation

@MainActor
final class ArisOnboardingModel: ObservableObject {
    typealias Step = ArisOnboardingStep
    typealias Card = ArisPermissionCard

    struct Actions {
        /// What macOS says now (never asks).
        var grant: @MainActor (Step) -> ArisGrant
        /// 허용: macOS's own dialog, or System Settings with the drag panel (a step already denied opens its pane).
        var request: @MainActor (Step) async -> Void
        /// 나중에 while waiting: the drag panel goes.
        var stop: @MainActor (Step) -> Void
        /// The talk shortcut as key caps ("⌥", "Space").
        var talkKeys: @MainActor () -> [String]
        /// The app's first real screen capture, which brings macOS's second question (ArisFirstCapture); the frame
        /// is dropped, only what came of it comes back.
        var firstCapture: @MainActor () async -> ArisFirstCapture.Outcome = { .unknown }
        /// macOS already said yes to that question on this Mac (never asks).
        var captureAllowed: @MainActor () -> Bool = { false }
    }

    @Published private(set) var flow: ArisSetupFlow
    @Published private(set) var live: [Step: ArisGrant] = [:]
    /// A card just turned on (its check pops with its sound).
    var onGranted: (Card) -> Void = { _ in }
    /// A step's ask came back: macOS's dialog was answered (`prompted`), or System Settings was opened for it.
    var onAsked: (_ step: Step, _ prompted: Bool) -> Void = { _, _ in }
    /// The Screen Recording card's second question from macOS (ArisFirstCapture): where it is.
    @Published private(set) var firstCapture: ArisFirstCapture.Step = .idle
    /// What came of that question, as it comes back.
    var onFirstCapture: (ArisFirstCapture.Outcome) -> Void = { _ in }
    /// macOS's own prompts for a card are being answered: one is up, or the card's next one is about to be (the
    /// microphone's two come one after the other, and Screen Recording's second question follows its switch). Never
    /// for a card turned on in System Settings.
    var prompting: Bool { asking || firstCapture == .asking }
    /// A card's 허용 has macOS's prompts up.
    private var asking = false

    let actions: Actions
    private var poll: Timer?
    private var popped: Set<Card> = []

    init(actions: Actions, page: ArisSetupPage = .permissions) {
        self.actions = actions
        flow = ArisSetupFlow(page: page)
        live = Self.read(actions)
        popped = Set(Card.allCases.filter { card in card.steps.allSatisfy { live[$0] == .granted } })
    }

    private static func read(_ actions: Actions) -> [Step: ArisGrant] {
        Dictionary(uniqueKeysWithValues: Card.allCases.flatMap(\.steps).map { ($0, actions.grant($0)) })
    }

    func granted(_ card: Card) -> Bool { card.steps.allSatisfy { live[$0] == .granted } }
    var grants: [Card: Bool] { Dictionary(uniqueKeysWithValues: Card.allCases.map { ($0, granted($0)) }) }
    func state(_ card: Card) -> ArisCardState { flow.state(card, granted: granted(card)) }

    // MARK: - Watching macOS

    func begin() {
        refresh()
        flow.begin(granted: grants)
    }

    /// Checks every second while the window is open.
    func start() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    var polling: Bool { poll != nil }

    func stop() {
        poll?.invalidate()
        poll = nil
    }

    func refresh() {
        let now = Self.read(actions)
        if now != live { live = now }
        var flow = self.flow
        for card in Card.allCases {
            if granted(card) {
                if popped.insert(card).inserted { onGranted(card) }
            } else if flow.waiting.contains(card), card.steps.contains(where: { live[$0] == .denied }) {
                // A no in macOS's dialog: put off; Aris asks again the first time it needs it.
                flow.putOff(card)
            }
        }
        flow.settle(granted: grants)
        if flow != self.flow { self.flow = flow }
    }

    // MARK: - Buttons

    /// 허용: asks macOS for what isn't on yet, one dialog after the other.
    func allow(_ card: Card) {
        flow.ask(card)
        let steps = card.steps.filter { live[$0] != .granted }
        Task { [weak self] in
            for (index, step) in steps.enumerated() {
                guard let self else { return }
                // One refused before gets no prompt (macOS won't ask twice): its System Settings list opens instead.
                let prompts = steps[index...].map { $0.way == .ask && self.actions.grant($0) != .denied }
                self.asking = prompts.contains(true)
                await self.actions.request(step)
                self.refresh()
                self.onAsked(step, prompts[0])
            }
            self?.asking = false
            self?.refresh()
        }
    }

    // MARK: - Screen Recording's second question

    /// macOS already has its yes for capturing the screen directly.
    var captureAllowed: Bool { actions.captureAllowed() }

    /// The line the Screen Recording card shows about that question, if any.
    var captureNote: ArisFirstCapture.Note? {
        ArisFirstCapture.note(card: state(.screen), step: firstCapture, allowedBefore: captureAllowed)
    }

    /// Takes the app's first real capture when it is due (ArisFirstCapture.due), so macOS's second question comes in
    /// the setup; true when it was started. What came of it lands in `firstCapture` and `onFirstCapture`.
    @discardableResult
    func takeFirstCaptureIfDue() -> Bool {
        guard ArisFirstCapture.due(page: flow.page, screenGranted: granted(.screen), waiting: !flow.waiting.isEmpty, step: firstCapture,
                                   allowedBefore: captureAllowed) else { return false }
        firstCapture = .asking
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.actions.firstCapture()
            self.firstCapture = .done(outcome)
            self.onFirstCapture(outcome)
        }
        return true
    }

    /// 나중에.
    func later(_ card: Card) {
        if flow.waiting.contains(card) { card.steps.forEach(actions.stop) }
        // Put off with macOS's prompt still up: the page moves on, and nothing is held in front for that prompt.
        if card.way == .ask { asking = false }
        flow.putOff(card)
        flow.settle(granted: grants)
    }

    func next(skipping skipped: Set<ArisSetupPage> = []) -> Bool { flow.next(skipping: skipped) }
    func back(skipping skipped: Set<ArisSetupPage> = []) { flow.back(skipping: skipped) }
}
