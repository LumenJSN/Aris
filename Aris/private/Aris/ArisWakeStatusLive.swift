//
//  ArisWakeStatusLive.swift
//  Aris
//
//  The wake word's state as it was last looked at (ArisWakeStatus), for Settings › 부르기 and the diagnostics. The
//  controller writes it whenever it decides whether to listen (waitForWakeWord), when a candidate is checked over
//  playback, and when the microphone goes down or comes back.
//

import Combine
import Foundation

@MainActor
final class ArisWakeStatusLive: ObservableObject {
    static let shared = ArisWakeStatusLive()

    @Published private(set) var state = ArisWakeStatus.State()

    func update(_ change: (inout ArisWakeStatus.State) -> Void) {
        var next = state
        change(&next)
        if next != state { state = next }
    }

    func line(english: Bool) -> String { ArisWakeStatus.line(state, english: english) }
}
