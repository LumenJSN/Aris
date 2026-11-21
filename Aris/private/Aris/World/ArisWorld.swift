//
//  ArisWorld.swift
//  Aris
//
//  The one store of what is going on around Aris (ARCHITECTURE.md 3.5). It owns one observer per source (ArisWorld+
//  Sources, ArisWorldAudio) and folds each change into ArisWorldSnapshot; a change worth telling is published once:
//  into the kernel's ring as ArisEvent.world, and to every subscriber of its topic, in the order they subscribed,
//  synchronously on the main actor, the moment its notice comes (as each feature's own observer used to hear it).
//  A turn's context and the interruption policy read `snapshot`. Selection, screen text and the clipboard are not
//  watched: they stay where they are read on demand.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "world")

/// A subscription to the world's changes; it lasts until it is cancelled (like a NotificationCenter token).
@MainActor
final class ArisWorldSubscription {
    private let id: Int
    private weak var world: ArisWorld?

    fileprivate init(id: Int, world: ArisWorld) {
        self.id = id
        self.world = world
    }

    func cancel() { world?.unsubscribe(id) }
}

@MainActor
final class ArisWorld {
    static let shared = ArisWorld()

    typealias Handler = @MainActor (ArisWorldChange, ArisWorldSnapshot) -> Void

    private(set) var snapshot = ArisWorldSnapshot()
    /// In the order they subscribed.
    private var subscribers: [(id: Int, topics: Set<ArisWorldTopic>, handler: Handler)] = []
    private var nextID = 0
    private var started = false
    private var systemStarted = false
    /// Where the world's events go (the controller's kernel); set once it starts.
    private var kernel: ArisKernel?
    /// The sources' observers, kept for the app's life.
    var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    var watches: [Any] = []
    var audio: ArisWorldAudio?
    /// The Claude Code hook event being published, whole, for the subscribers that need more than its name.
    var lastHook: ClaudeHookEvent?

    private init() {}

    /// Starts every source once. Called from the controller's init; the system's sources may have started already
    /// (the first subscriber starts them, whenever it comes), the sources that read other singletons start a moment
    /// later (they must not be touched while the controller is being made).
    func start(aris: ArisController) {
        guard !started else { return }
        started = true
        kernel = aris.kernel
        startSystemSourcesOnce()
        startHooks()
        Task { @MainActor [weak self, weak aris] in
            guard let self, let aris else { return }
            self.startAppSources(aris)
        }
        log.notice("world: watching")
    }

    // MARK: - Subscribing

    /// `handler` hears every published change of `topics`, with the snapshot that already holds it.
    @discardableResult
    func subscribe(_ topics: Set<ArisWorldTopic>, _ handler: @escaping Handler) -> ArisWorldSubscription {
        startSystemSourcesOnce()
        nextID += 1
        subscribers.append((nextID, topics, handler))
        return ArisWorldSubscription(id: nextID, world: self)
    }

    private func startSystemSourcesOnce() {
        guard !systemStarted else { return }
        systemStarted = true
        startSystemSources()
    }

    fileprivate func unsubscribe(_ id: Int) {
        subscribers.removeAll { $0.id == id }
    }

    // MARK: - Changes

    /// Folds `change` in and publishes it when it is news (ArisWorldSnapshot.reduce).
    func note(_ change: ArisWorldChange) {
        let (next, publish) = ArisWorldSnapshot.reduce(snapshot, change)
        snapshot = next
        guard publish else { return }
        if !change.isChatter { kernel?.send(.world(change)) }
        let topic = change.topic
        // A handler that subscribes or cancels meanwhile changes the list for the next change, not this one.
        for subscriber in subscribers where subscriber.topics.contains(topic) {
            guard subscribers.contains(where: { $0.id == subscriber.id }) else { continue }
            subscriber.handler(change, next)
        }
    }

    /// The world as it already is when a source starts: taken without publishing anything.
    func seed(_ now: ArisWorldSnapshot) { snapshot = now }

    // MARK: - Reading

    /// The interruption policy's view of now. `mayMakeSound`: Aris may make a sound on its own (ArisQuietGate).
    func moment(mayMakeSound: Bool) -> ArisInterruption.Moment {
        var moment = ArisInterruption.moment(snapshot, now: ProcessInfo.processInfo.systemUptime, mayMakeSound: mayMakeSound)
        // A lock or a sleep whose "back" notice never came (QA BUG-38) must not hold everything for good: the screen
        // is asked directly before anything waits for an unlock.
        if moment.screenAway, !ArisController.screenIsAwayNow() { moment.screenAway = false }
        return moment
    }
}
