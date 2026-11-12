//
//  ArisController+See.swift
//  Aris
//
//  A turn sees the display under the pointer only when the user's words point at the screen (the owner, 2026-11-10;
//  ArisScreenNeed): the talk key, a wake word or a typed request only begins the turn, and once its words are known
//  and it goes to the AI, `ArisTurnCapture` shoots if they say "이거", "화면 봐 줘", "what's on my screen". The turn's
//  ask then takes the screenshot (waiting at most 3 s) with its focus. Any other turn captures nothing and sends no
//  image. A drawing (circled shots, drawing references) goes as before, in place of the screenshot.
//  A turn with an image is outside content: the agent marks it untrusted and the conversation `sawScreen`, so its
//  answer never dispatches (the app's own gate, `screen == nil && !untrustedTurn`, is unchanged). A turn without one
//  is the user's own words alone, and the brain they chose answers it unsealed.
//

import AppKit
import Defaults
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "see")

extension ArisTurnCapture.Dependencies {
    @MainActor static var live: Self {
        Self(shoot: {
                 guard let shot = await ArisScreenCapture.shared.cursorDisplayShot() else { return nil }
                 return ArisTurnCapture.Shot(png: shot.png, ms: shot.ms, retried: shot.retried)
             },
             enabled: { Defaults[.arisSeesScreen] },
             permission: { CGPreflightScreenCaptureAccess() },
             nextNotice: { ArisScreenPermissionNotice.next() },
             notify: { ArisGesturePermissionChip.shared.showNearPointer($0) })
    }
}

extension ArisTurnCapture {
    /// The app's one per-turn capture.
    static let shared = ArisTurnCapture(dependencies: .live)
}

extension ArisController {
    /// A turn is about to listen (the talk key, a wake word, a follow-up): nothing is captured yet. What an earlier
    /// turn left is dropped, and whether the open notch shows the previous answer is noted before the turn changes
    /// it (D3 focus).
    func seeTurnStarting() {
        ArisTurnCapture.shared.began(notchShowsAnswer: notchShowsAnswerNow())
        shotThumbs = [:] // the last turn's chips go with it
    }

    func notchShowsAnswerNow() -> Bool {
        ArisCaptureTiming.notchShowsAnswer(notchOpen: ArisNotchPresence.shared.isOpen, previousReply: session.reply)
    }

    /// A typed turn begins at submit; `notchShowsAnswer` was read before the submit changed the notch.
    func seeTyped(notchShowsAnswer: Bool) { ArisTurnCapture.shared.began(notchShowsAnswer: notchShowsAnswer) }
    /// The words are known and the turn goes to the AI: the screen is captured now when they point at it, and never
    /// otherwise (no capture, no permission line).
    func seeWords(_ words: String) {
        let capturing = ArisTurnCapture.shared.heard(words)
        log.notice("screen for this turn: \(capturing ? "capturing (the words point at it)" : "none", privacy: .public)")
    }
    /// The turn ended (answered, cancelled or failed): an image not yet sent is dropped.
    func seeEnded() { ArisTurnCapture.shared.cancel() }

    /// The images this turn sends and what "이거" most likely means; logs the capture's numbers (never the image).
    func turnImages() async -> (images: [ArisTurnImage], focus: ArisReferenceFocus?) {
        let capture = ArisTurnCapture.shared
        // The drawing goes in place of the screenshot (none was taken for it): taken first, nothing waited for.
        let gestureImages = capture.takeGesture()
        let attempted = capture.attempted
        let taken: ArisTurnCapture.Taken?
        if gestureImages.isEmpty {
            taken = await capture.image()
        } else {
            capture.cancel()
            taken = nil
        }
        let images = ArisCaptureTiming.images(cursor: taken?.image, gesture: gestureImages)
        if attempted || taken != nil {
            stats?.captured(source: "cursorDisplay", ok: taken != nil, bytes: taken?.bytes ?? 0, ms: taken?.ms ?? 0,
                            retried: taken?.retried ?? false)
        }
        stats?.shots(gestureImages.filter { $0.kind == .gesture }.count)
        guard !images.isEmpty else { return ([], nil) }
        let focus = gestureImages.isEmpty ? taken?.focus : ArisReferenceFocus.of(hasShots: true, notchShowsAnswer: false)
        return (images, focus)
    }
}
