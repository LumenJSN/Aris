//
//  ArisCaptureTiming.swift
//  Aris
//
//  What "이거" most likely means for a turn (plan D3), and which images a turn carries. The screenshot itself is no
//  longer timed from the key (1.5 s after the press): it is taken once the words are known, and only when
//  they point at the screen (ArisScreenNeed, ArisTurnCapture). Pure, so the tests run it.
//

import Foundation

enum ArisCaptureTiming {
    /// The open notch shows the previous answer as a turn begins (read before the turn starts listening): "이거"
    /// then most likely means that answer, and the image is a fallback (`ArisReferenceFocus.of`, D3).
    static func notchShowsAnswer(notchOpen: Bool, previousReply: String) -> Bool {
        notchOpen && !previousReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The turn's images: gesture shots (and drawing references) when the user circled something, which replace the
    /// plain screenshot; otherwise the screenshot, if there is one.
    static func images(cursor: ArisTurnImage?, gesture: [ArisTurnImage]) -> [ArisTurnImage] {
        guard gesture.isEmpty else { return gesture }
        return cursor.map { [$0] } ?? []
    }
}
