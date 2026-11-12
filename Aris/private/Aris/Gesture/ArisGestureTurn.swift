//
//  ArisGestureTurn.swift
//  Aris
//
//  A turn that comes with circled shots (plan P1.9):
//  - the shots and drawing references replace the plain screenshot, and "이거" means the screen;
//  - `[img N]` markers go into the words at the moment of each circle (by voiced time; none for the AI without a
//    speech window, though the prompt still shows the chips, at the end);
//  - with circled shots (not a drawing alone) local intents and the router's intent are skipped (the router may still
//    set the tier): the brain answers;
//  - an AI named up front is picked from the unmarked words; markers go on the full words, then its prefix is cut;
//  - the prompt shows the markers at sentence ends as chips with the PNG thumbnails (memory only).
//  Pure, so the tests run it.
//

import Foundation

struct ArisGestureTurn {
    /// What goes to the agent, in order: gesture shots by badge, then drawing references.
    let images: [ArisTurnImage]
    /// The chips' thumbnails by badge (PNG, no number on them): for the transcript only, never sent or saved.
    let thumbs: [Int: Data]
    private let shots: [ArisMarkedShot]
    private let speech: (startedAtMs: Double, endedAtMs: Double, totalVoicedMs: Double)?

    /// Nil when nothing was drawn worth sending.
    init?(result: ArisGestureResult?) {
        guard let result else { return nil }
        let images = result.images()
        guard !images.isEmpty else { return nil }
        self.images = images
        thumbs = Dictionary(result.shots.map { ($0.badge, $0.thumb) }, uniquingKeysWith: { first, _ in first })
        shots = result.shots.map { ArisMarkedShot(badge: $0.badge, voicedMsAtCapture: $0.voicedMsAtCapture, capturedAtMs: $0.capturedAtMs) }
        speech = result.speech
    }

    /// Circled shots, not only a drawing reference: the turn's words are about them.
    var hasShots: Bool { !shots.isEmpty }

    /// `text` with `[img N]` after the word the user was saying at each circle; unchanged without a speech window.
    func marked(_ text: String) -> String {
        guard let speech, !shots.isEmpty else { return text }
        return ArisGestureMarkers.insert(text, shots: shots, speech: speech)
    }

    /// The request for the brain: markers placed on the full words, then an AI named up front cut off (its name
    /// is picked from the unmarked words). If a marker fell inside the name, the request is marked on its own.
    func markedRequest(_ heard: String) -> String {
        let full = marked(heard)
        guard let named = ArisBrain.pick(from: heard) else { return full }
        if let picked = ArisBrain.pick(from: full), picked.brain == named.brain { return picked.request }
        return marked(named.request)
    }

    /// What the prompt shows: the marked words, or, without a speech window, the words with every chip at the end.
    func display(_ text: String) -> String {
        guard speech == nil, !shots.isEmpty else { return marked(text) }
        return ([text] + shots.map(\.badge).sorted().map { "[img \($0)]" }).joined(separator: " ")
    }

    /// With circled shots the brain answers, whatever a local intent would have made of the words.
    static func intent(unmarked: String, marked: String, hasShots: Bool) -> ArisIntent {
        hasShots ? .ask(marked) : ArisIntent.parse(unmarked)
    }

    /// The prompt as VoiceOver reads it: one line, each chip "동그라미 N".
    static func spoken(_ text: String, english: Bool = ArisUIWords.english) -> String {
        tokens(text).map { token in
            switch token {
            case .word(let word): word
            case .chip(let badge): ArisUIWords.text("동그라미 \(badge)", "Circle \(badge)", english: english)
            }
        }.joined(separator: " ")
    }

    enum Token: Equatable {
        case word(String)
        case chip(Int)
    }

    /// The prompt as words and chips, markers moved to sentence ends (the flow layout wraps between tokens).
    static func tokens(_ text: String) -> [Token] {
        ArisGestureMarkers.displayParts(text).flatMap { part -> [Token] in
            switch part {
            case .shot(let badge): [.chip(badge)]
            case .text(let words): words.split(whereSeparator: \.isWhitespace).map { .word(String($0)) }
            }
        }
    }
}

/// The chip preview's size (mockup `.pv`): within 360×300 and the room left below the chip inside the turn, never
/// larger than the thumbnail; nil when there's no room for a useful one (under 48 pt tall).
enum ArisShotPreviewFit {
    static let maxSize = CGSize(width: 360, height: 300)
    static let minHeight: CGFloat = 48

    static func size(image: CGSize, room: CGFloat) -> CGSize? {
        guard image.width > 0, image.height > 0 else { return nil }
        let k = min(1, maxSize.width / image.width, maxSize.height / image.height, max(0, room) / image.height)
        let size = CGSize(width: (image.width * k).rounded(), height: (image.height * k).rounded())
        return size.height < minHeight ? nil : size
    }
}
