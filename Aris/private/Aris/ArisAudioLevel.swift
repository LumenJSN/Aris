//
//  ArisAudioLevel.swift
//  Aris
//
//  The live voice level, on its own object. It changes 20 to 50 times a second while someone talks, and only the
//  voice mark draws it (ArisLiveVoiceGlyph). Published on ArisController, it re-rendered the whole notch at that rate.
//

import Combine

@MainActor
final class ArisAudioLevel: ObservableObject {
    /// Loudness of whoever is talking (you, then Aris), 0...1.
    @Published var value: Float = 0
}
