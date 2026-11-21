//
//  ArisTurnVoices.swift
//  aris-agent
//
//  Who spoke each conversation turn (F1, the owner's voice): the app's `voice` field on POST /ask (ArisTurnSpeaker),
//  handed to the runner that takes that turn, as ArisTurnArrivals hands its arrival time: by the connection it came
//  on. Only the Aris app itself is heard; a missing or unknown value, or any other caller, is "not checked" (as before:
//  the owner). Core 2's trust gate reads it with the turn's words (ArisMindJudge.turn).
//

import Foundation

final class ArisTurnVoices: @unchecked Sendable {
    static let shared = ArisTurnVoices()
    private let lock = NSLock()
    private var heard: [ObjectIdentifier: (speaker: ArisTurnSpeaker, at: Date)] = [:]

    func received(_ owner: AnyObject, raw: Any?, fromApp: Bool, at time: Date = Date()) {
        let speaker = fromApp ? ArisTurnSpeaker.named(raw as? String) : .notChecked
        lock.withLock {
            if heard.count > 64 { heard = heard.filter { time.timeIntervalSince($0.value.at) < 600 } }
            heard[ObjectIdentifier(owner)] = (speaker, time)
        }
    }

    /// The speaker of the turn that came on `owner`; not checked when none was heard.
    func take(_ owner: AnyObject?) -> ArisTurnSpeaker {
        guard let owner else { return .notChecked }
        return lock.withLock { heard.removeValue(forKey: ObjectIdentifier(owner))?.speaker } ?? .notChecked
    }
}
