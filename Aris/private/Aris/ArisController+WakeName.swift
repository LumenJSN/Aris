//
//  ArisController+WakeName.swift
//  Aris
//
//  The wake name's learned spellings: once the user has taught Aris their voice, Whisper reads each of the training's
//  recordings (in memory, on this Mac, once) and what it wrote for them becomes spellings of the name
//  (ArisWakeName.learning). Nothing is learned while Whisper isn't on the Mac; the recordings are never kept for it.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    func learnWakeSpellings(from recordings: [[Float]]) {
        guard !recordings.isEmpty else { return }
        ArisTurnScope.outside {
            Task.detached(priority: .utility) {
                var texts: [String] = []
                for recording in recordings {
                    let padded = ArisTranscript.paddedForWhisper(recording, sampleRate: ArisVoicePrint.sampleRate)
                    // Whisper not ready: nothing is learned this time.
                    guard let text = (try? await ArisWhisper.shared.transcribe(padded)) ?? nil else { return }
                    texts.append(text)
                }
                await MainActor.run {
                    let before = ArisWakeName.load(.standard)
                    let after = before.learning(from: texts)
                    guard after != before else { return }
                    ArisWakeName.save(learned: after, to: .standard)
                    log.notice("wake word: \(after.learned.count - before.learned.count, privacy: .public) spellings learned from the training")
                }
            }
        }
    }
}
