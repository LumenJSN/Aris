//
//  ArisTurnCapture.swift
//  Aris
//
//  The screenshot a turn carries when the user's words point at the screen (ArisScreenNeed; the owner, 2026-11-10): the display
//  under the pointer, taken once the words are known (heard or typed) and the turn goes to the AI. Nothing is captured
//  when the talk key goes down, a wake word is heard or a request is typed, and nothing at all for a plain question:
//  no capture, no look at the grant, no permission line. The turn takes the shot when it asks, waiting at most 3 s; if
//  it isn't there by then the turn goes without it. With the setting off nothing is captured. Without the Screen
//  Recording grant nothing is tried either (no system prompt from a turn; controller ruling 2026-11-03): only the
//  once-per-launch line shows, and only for a turn that wanted the screen.
//  The PNG stays in memory until the turn hands it out; a finished, cancelled or replaced turn drops it, and a shot
//  nobody collects is dropped after 30 s. Each turn has its own generation: a late wait from an earlier turn gets
//  nothing and never touches the next turn's capture.
//

import Foundation

@MainActor
final class ArisTurnCapture {
    struct Shot: Equatable {
        let png: Data
        let ms: Int
        let retried: Bool
    }

    /// What a turn sends: the image, what "이거" most likely means, and numbers for the turn log.
    struct Taken: Equatable {
        let image: ArisTurnImage
        let focus: ArisReferenceFocus
        let bytes: Int
        let ms: Int
        let retried: Bool
    }

    struct Dependencies {
        var shoot: @MainActor () async -> Shot?
        /// The "질문할 때 화면 같이 보기" setting.
        var enabled: @MainActor () -> Bool
        var permission: @MainActor () -> Bool
        /// The line due now, if any (`ArisScreenPermissionNotice.next`, shared with the gesture).
        var nextNotice: @MainActor () -> ArisScreenPermissionNotice.Line?
        var notify: @MainActor (ArisScreenPermissionNotice.Line) -> Void
        var waitAtSend: Duration = ArisCaptureRules.waitAtSend
        /// A shot nobody collected is dropped after this (as the gesture's pending result).
        var keepFor: Duration = .milliseconds(Int(ArisGestureConstants.Session.collectMaxAgeMs))
    }

    private let deps: Dependencies
    private var generation = 0
    private var notchShowedAnswer = false
    private var shooting: Task<Shot?, Never>?
    private var expiry: Task<Void, Never>?
    /// The turn's circled shots and drawing references (P1.9), held under the same generation and expiry.
    private var gesture: (images: [ArisTurnImage], turn: Int)?

    /// A capture was tried this turn (for the turn log: ok or not).
    private(set) var attempted = false

    init(dependencies: Dependencies) {
        deps = dependencies
    }

    /// A turn began (the talk key, a wake word, a typed request): whatever an earlier turn left is dropped, and
    /// nothing is captured yet. `notchShowsAnswer`: the open notch showed the previous answer as the turn began.
    func began(notchShowsAnswer: Bool) {
        cancel()
        notchShowedAnswer = notchShowsAnswer
    }

    /// The turn's words are known and it goes to the AI: the screen is shot now when they point at it
    /// (ArisScreenNeed), and only then; true when a capture started. Any other turn starts nothing: the grant isn't
    /// even read, so no permission line shows. A request too long to take is refused before it reaches the AI
    /// (ArisAgentCopy.overLimit), so it captures nothing (VM fourth re-check, #2: a 3.5 MB screenshot came first).
    @discardableResult
    func heard(_ words: String) -> Bool {
        guard !ArisAgentCopy.overLimit(words) else { return false }
        guard shooting == nil else { return true }
        let drew = gesture.map { $0.turn == generation } ?? false
        guard ArisScreenNeed.captures(words: words, setting: deps.enabled(), drew: drew) else { return false }
        guard deps.permission() else {
            if let line = deps.nextNotice() { deps.notify(line) }
            return false
        }
        attempted = true
        let shoot = deps.shoot
        shooting = Task { @MainActor in await shoot() }
        armExpiry()
        return true
    }

    /// The screenshot for this turn, waiting at most `waitAtSend`; nil when the words didn't ask for one, or it was
    /// skipped, failed, late, or the turn was replaced meanwhile. Handed out once.
    func image() async -> Taken? {
        guard let task = shooting else { return nil }
        let turn = generation
        let shot = await ArisTaskRace.value(of: task, within: deps.waitAtSend)
        guard turn == generation else { return nil } // a newer turn began: its capture isn't ours to take or clear
        let focus = ArisReferenceFocus.of(hasShots: false, notchShowsAnswer: notchShowedAnswer)
        clear()
        guard let shot else { return nil }
        let image = ArisTurnImage(kind: .cursor, name: "cursor-screen.png", format: .png, data: shot.png,
                                  badge: nil, app: nil, title: nil)
        return Taken(image: image, focus: focus, bytes: shot.png.count, ms: shot.ms, retried: shot.retried)
    }

    /// Whether this turn's screenshot is there, waiting at most `waitAtSend` for it. Nothing is taken: the ask still
    /// collects it (`image`). With it in hand the screen has been read, whatever aris-agent's own look could do (VM bug 1).
    func inHand() async -> Bool {
        guard let task = shooting else { return false }
        let turn = generation
        let shot = await ArisTaskRace.value(of: task, within: deps.waitAtSend)
        return turn == generation && shot != nil
    }

    /// The turn's circled shots arrived (collected at the end of listening): they replace the screenshot.
    func attachGesture(_ images: [ArisTurnImage]) {
        guard !images.isEmpty else { return }
        gesture = (images, generation)
        armExpiry()
    }

    /// This turn's circled shots, handed out once; nothing from an earlier turn.
    func takeGesture() -> [ArisTurnImage] {
        defer { gesture = nil }
        guard let gesture, gesture.turn == generation else { return [] }
        return gesture.images
    }

    /// The turn ended or was dropped: nothing pending survives it.
    func cancel() {
        generation += 1
        clear()
        attempted = false
    }

    // MARK: - Helpers

    /// Whatever this turn holds is dropped after `keepFor` if nobody takes it.
    private func armExpiry() {
        expiry?.cancel()
        let keep = deps.keepFor, turn = generation
        expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: keep)
            guard !Task.isCancelled, let self, self.generation == turn else { return }
            self.cancel()
        }
    }

    private func clear() {
        shooting?.cancel()
        shooting = nil
        expiry?.cancel()
        expiry = nil
        gesture = nil
    }
}
