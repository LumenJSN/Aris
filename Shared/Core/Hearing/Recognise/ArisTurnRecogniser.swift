//
//  ArisTurnRecogniser.swift
//  Aris (Shared/Core, Foundation only)
//
//  The one seam every recogniser sits behind: "the final transcript of this turn's audio". A cloud engine that
//  streams also has a live session (its words show in the notch while the turn is spoken); reading a finished
//  recording through it is the same session fed all at once. Nil always means "no answer" (failed, or too slow), so
//  the caller goes to the next engine; an answer with no words is an answer.
//

import Foundation

/// What a recogniser is told about the turn before it hears it.
struct ArisHearRequest: Equatable, Sendable {
    /// The languages turned on, as base codes, the main one first ("ko", "en").
    var languages: [String]
    /// Words to expect (ArisHearHints), most important first; each engine takes as many as it allows.
    var hints: [String]
}

protocol ArisTurnRecogniser: Sendable {
    var engine: ArisHearEngine { get }
    /// 16 kHz mono samples of the whole turn; nil when there is no answer within `timeout`.
    func transcribe(_ samples: [Float], request: ArisHearRequest, timeout: Duration) async -> ArisHeard?
}

/// One turn streaming to a cloud engine while it is spoken.
protocol ArisLiveHearing: AnyObject, Sendable {
    var engine: ArisHearEngine { get }
    /// Everything heard so far, on the main thread.
    var onText: (@MainActor (String) -> Void)? { get set }
    func start()
    /// 16 kHz mono samples, from any thread.
    func append(_ samples: [Float])
    /// The whole turn once the engine has it; nil when it failed or took longer than `timeout`.
    func finish(timeout: Duration) async -> ArisHeard?
    func cancel()
}

/// A streaming engine reading a finished recording: the session, fed the whole turn at once.
struct ArisStreamedRecording: ArisTurnRecogniser {
    let engine: ArisHearEngine
    let open: @Sendable (ArisHearRequest) -> (any ArisLiveHearing)?

    func transcribe(_ samples: [Float], request: ArisHearRequest, timeout: Duration) async -> ArisHeard? {
        guard let session = open(request) else { return nil }
        session.start()
        session.append(samples)
        return await session.finish(timeout: timeout)
    }
}

/// "Repair what was heard" (ArisHeardRepair) has its own switch; untouched, it is on with Automatic and off with a
/// recogniser the owner picked himself (he chose to hear exactly what that engine writes).
enum ArisHearRepairSetting {
    static let key = "arisHearRepair"

    static func isOn(stored: Bool?, choice: ArisHearEngine) -> Bool { stored ?? (choice == .auto) }
}
