//
//  ArisDuplexLifetime.swift
//  Aris
//
//  When the duplex engine (one microphone and speaker owner, echo cancelled) runs, as a pure reducer.
//  - It runs while something listens: the wake word or a conversation's between-turn watch (`wake`), an open
//    conversation (`conversation`, so a key turn's hand-over to the answer and back keeps it), or a turn's or a card's
//    listener (`turn`). Aris's voice (`voice`) keeps a running engine running to the end of its line, but never starts
//    one: an answer with nothing listening plays through the old output, so the microphone stays off.
//  - The last listener letting go stops it after `linger`, not at once: the wake word hands the microphone to a key
//    turn's listener that way (the ring keeps the first word), and a quick release and take doesn't flick macOS's
//    microphone indicator. The screen going away (lock, display sleep, the Mac sleeping) stops it at once, as does
//    another Aris microphone opening (dictation, 호출어 녹음, the name's training keep their own engines for now): the
//    two never hold the microphone together.
//  - A route that no longer suits it (headphones came, an aggregate became the default) stops it; the consumers are
//    dropped and reopen on the old path. A start that fails, or configuration changes that keep coming, mark the device
//    pair failed for the rest of the app's run (the caller logs that once and tells the user nothing).
//  Foundation only: every rule is tested with events in, effects out.
//

import Foundation

struct ArisDuplexLifetime: Equatable {
    enum Need: Hashable {
        case wake
        case conversation
        /// A listener, by its own id (a turn and a card's yes/no may overlap for a moment).
        case turn(Int)
        case voice
    }

    enum Event: Equatable {
        /// A consumer wants the engine (the caller already checked that the route allows it).
        case need(Need)
        case release(Need)
        /// The linger timer `token` ran out.
        case lingerElapsed(token: Int)
        /// The screen went away (locked, asleep, the Mac sleeping) or came back.
        case away(Bool)
        /// Another Aris microphone (dictation, 호출어 녹음, the name's training) is about to open its own engine.
        case legacyMicOpening
        /// The real start (or a rebuild) finished.
        case started(ok: Bool)
        /// The hardware's configuration changed and stopped the engine; `routeAllows`: the route still suits it.
        case configurationChanged(routeAllows: Bool, at: Double)
    }

    enum Effect: Equatable {
        case start
        case stop
        /// Rebuild after a configuration change: voice processing on again, the tap in the new format, started.
        case rebuild
        /// Stop when `token`'s linger ends, unless something takes the engine meanwhile.
        case stopAfterLinger(token: Int)
        /// Every consumer is told its audio stopped (it reopens on the old path, or waits).
        case dropConsumers
        /// This device pair is not tried again this run.
        case markFailed
    }

    static let linger: Double = 1.5
    /// More rebuilds than this within `rebuildWindow` seconds: the device keeps changing; the old path takes over.
    static let rebuildsAllowed = 3
    static let rebuildWindow: Double = 30

    private(set) var needs: Set<Need> = []
    /// Started or starting (the real start runs on the engine's queue and reports back).
    private(set) var running = false
    private(set) var away = false
    private(set) var lingerToken = 0
    private(set) var rebuilds: [Double] = []

    /// Something listens (Aris's voice alone doesn't count).
    var listening: Bool { needs.contains { $0 != .voice } }

    /// Whether the engine should be running now.
    var keepsRunning: Bool { !away && (listening || (running && needs.contains(.voice))) }

    func reduce(_ event: Event) -> (ArisDuplexLifetime, [Effect]) {
        var next = self
        let effects = next.apply(event)
        return (next, effects)
    }

    private mutating func apply(_ event: Event) -> [Effect] {
        switch event {
        case .need(let need):
            // The voice never starts the engine: it only rides along on one that runs.
            if need == .voice, !running { return [] }
            needs.insert(need)
            lingerToken += 1
            guard !running, keepsRunning else { return [] }
            running = true
            return [.start]
        case .release(let need):
            guard needs.remove(need) != nil else { return [] }
            guard running, !keepsRunning else { return [] }
            lingerToken += 1
            return [.stopAfterLinger(token: lingerToken)]
        case .lingerElapsed(let token):
            guard token == lingerToken, running, !keepsRunning else { return [] }
            return stopNow(drop: false)
        case .away(let isAway):
            away = isAway
            if isAway { return running ? stopNow(drop: true) : [] }
            guard !running, keepsRunning else { return [] }
            running = true
            return [.start]
        case .legacyMicOpening:
            return running ? stopNow(drop: true) : []
        case .started(let ok):
            guard !ok else { return [] }
            running = false
            return [.dropConsumers, .markFailed]
        case .configurationChanged(let routeAllows, let now):
            guard running else { return [] }
            guard routeAllows else { return stopNow(drop: true) }
            rebuilds = rebuilds.filter { now - $0 < Self.rebuildWindow } + [now]
            guard rebuilds.count <= Self.rebuildsAllowed else {
                rebuilds = []
                return stopNow(drop: true) + [.markFailed]
            }
            return [.rebuild]
        }
    }

    /// Stops at once; `drop`: the consumers still subscribed are told (their audio ends here).
    private mutating func stopNow(drop: Bool) -> [Effect] {
        running = false
        lingerToken += 1
        // The consumers that are dropped let go of their needs themselves; what stays (an open conversation) waits
        // for the next consumer to start the engine again.
        needs.remove(.voice)
        return drop ? [.stop, .dropConsumers] : [.stop]
    }
}
