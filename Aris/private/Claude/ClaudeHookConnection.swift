//
//  ClaudeHookConnection.swift
//  Aris
//
//  One connection to the hook server, from its first byte to its close, on a queue of its own: nothing another
//  connection waits for (a card, Reminders, the helper, a slow client) can delay this one. It is answered exactly
//  once, by whoever gets there first: the ordinary path, a deadline (ClaudeHookHold's limits, kept on a separate
//  clock queue so a stuck connection queue cannot hold them back), the card, or the server closing. After the answer
//  the rest of what the client sends is read and dropped until it closes or the linger passes.
//

import Foundation
import Network

final class HookConnection: @unchecked Sendable {
    struct Context {
        let port: Int
        let token: () -> String?
        let consumer: HookConsumer
        let limits: HookLimits
        let stats: HookStats
        /// Where consumers are called, in the order requests were read.
        let intake: DispatchQueue
        /// Where deadlines fire.
        let clock: DispatchQueue
        /// Shared by every connection: how many requests are being looked at now.
        let deciders: HookDeciders
    }

    private enum Phase { case reading, deciding, held, answered }

    private let connection: NWConnection
    private let context: Context
    private let queue: DispatchQueue
    private let onClose: (HookConnection) -> Void

    /// Read and written only on `queue`. A head without the token is turned away before its body (review 9, L3).
    private var reader: HookRequestStream
    private var saidContinue = false

    /// Under `lock`: the deadlines, the card and the server read and write these from their own threads.
    private let lock = NSLock()
    private var phase = Phase.reading
    private var hookEvent = false
    private var hold: HookHold?
    private var clientDone = false
    private var replySent = false
    private var closing = false

    init(_ connection: NWConnection, context: Context, queue: DispatchQueue, onClose: @escaping (HookConnection) -> Void) {
        self.connection = connection
        self.context = context
        self.queue = queue
        self.onClose = onClose
        // A big body's token is checked at its head, counted among the requests looked at (past their limit it is read
        // as before and checked with its body); a token read that sticks is answered at the read limit.
        let token = context.token, deciders = context.deciders
        reader = HookRequestStream(admits: { head in
            guard deciders.enter().entered else { return nil }
            defer { deciders.leave() }
            return token().map { HTTPRequest(method: head.method, path: head.path, body: Data(), headers: head.headers).hasToken($0) } ?? false
        })
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed:
                self?.connection.cancel()
                self?.closed()
            case .cancelled: self?.closed()
            default: break
            }
        }
        connection.start(queue: queue)
        context.clock.asyncAfter(deadline: .now() + context.limits.read) { [weak self] in self?.readLimitPassed() }
        receive()
    }

    /// The server is closing (Aris quits, or its listener failed): answered now if anything is owed, then closed.
    func close() {
        let (phase, hold, hookEvent) = lock.withLock { () -> (Phase, HookHold?, Bool) in
            closing = true
            return (self.phase, self.hold, self.hookEvent)
        }
        context.stats.count(.closedByServer)
        switch phase {
        case .reading: connection.cancel()
        case .answered: if lock.withLock({ replySent }) { connection.cancel() }
        case .deciding, .held:
            if let hold, hold.end(.serverClosing) { return }
            finish(hookEvent ? .neutral : .refusal("503 Service Unavailable"))
        }
    }

    // MARK: - Reading

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.took(data) }
            if isComplete || error != nil { return self.clientFinished() }
            self.receive()
        }
    }

    /// More bytes: part of the request while it is being read; after it, nothing the server reads.
    private func took(_ data: Data) {
        guard lock.withLock({ phase == .reading }) else { return }
        let read = reader.take(data)
        // Known before the request is read, so a read that never ends still gets the neutral reply at its deadline.
        if ClaudeHookRoute.opensHook(reader.buffer) { lock.withLock { hookEvent = true } }
        switch read {
        case .more(let wantsContinue):
            guard wantsContinue, !saidContinue else { return }
            saidContinue = true
            connection.send(content: HookReply.continueBytes, completion: .contentProcessed { _ in })
        case .refuse(let status):
            reader.drop()
            if status == HookRequestReader.unauthorized { NSLog("ClaudeHookServer rejected a request at its head (missing or wrong token)") }
            finish(.refusal(status))
        case .tooBig(let head):
            reader.drop()
            tooBig(head)
        case .request(let request):
            reader.drop()
            decide(request)
        }
    }

    /// The client closed its side (or the connection broke).
    private func clientFinished() {
        let (phase, hold, replySent) = lock.withLock { () -> (Phase, HookHold?, Bool) in
            clientDone = true
            return (self.phase, self.hold, self.replySent)
        }
        switch phase {
        case .reading: connection.cancel()
        case .answered: if replySent { connection.cancel() }
        // A card nobody waits for is dropped; the reply is still tried (the client may only have closed its sending side).
        case .held: hold?.end(.clientGone)
        case .deciding: break
        }
    }

    // MARK: - Answering

    private func decide(_ request: HTTPRequest) {
        let hookEvent = request.method == "POST" && request.path == ClaudeHookRoute.hookPath
        guard lock.withLock({ () -> Bool in
            guard phase == .reading else { return false }
            phase = .deciding
            self.hookEvent = hookEvent
            return true
        }) else { return }
        let limits = context.limits
        if hookEvent {
            context.clock.asyncAfter(deadline: .now() + limits.answer) { [weak self] in self?.answerLimitPassed(request.path) }
        } else {
            context.clock.asyncAfter(deadline: .now() + limits.slow) { [weak self] in self?.slowLimitPassed(request.path) }
        }

        // Looking at a request is where a wedged Aris can stop a thread for good; the deadline above answers it anyway.
        let place = context.deciders.enter()
        guard place.entered else {
            context.stats.count(.turnedAway)
            if place.first {
                NSLog("[Claude] hook server: %d requests are still being looked at; new ones are answered without being read", context.limits.deciding)
            }
            finish(hookEvent ? .neutral : .refusal("503 Service Unavailable"))
            return
        }
        defer { context.deciders.leave() }
        let consumer = context.consumer
        switch ClaudeHookRoute.decide(request, token: context.token(), port: context.port) {
        case .refuse(let reply, let why):
            NSLog("ClaudeHookServer rejected %@ %@ (%@)", request.method, request.path, why)
            finish(reply)
        case .status(let report):
            finish(.neutral)
            context.intake.async { consumer.status(report) }
        case .event(let event):
            if finish(.neutral) { context.stats.count(.answered) }
            // Told after the answer, whoever sent it: an event answered by the deadline still reaches the notch.
            context.intake.async { consumer.event(event) }
        case .approval(let event):
            holdForCard(event)
        case .slow(let path, let body):
            guard lock.withLock({ () -> Bool in
                guard phase == .deciding else { return false }
                phase = .held
                return true
            }) else { return }
            // Straight from this connection's own queue: its order among the hook events doesn't matter, and it waits
            // for nothing the intake queue may be busy with.
            consumer.slow(path, body) { [weak self] reply in self?.finish(reply) }
        }
    }

    /// Claude's PermissionRequest: kept open for the card's answer, but only while the notch shows the card.
    private func holdForCard(_ event: ClaudeHookEvent) {
        let hold = HookHold { [weak self] body in self?.finish(body.map(HookReply.ok) ?? .neutral) }
        guard lock.withLock({ () -> Bool in
            guard phase == .deciding, !closing else { return false }
            phase = .held
            self.hold = hold
            return true
        }) else {
            // The neutral reply already went (the deadline, or the server closing): the event is told, with no card.
            let consumer = context.consumer
            context.intake.async { consumer.event(event) }
            finish(.neutral)
            return
        }
        let limits = context.limits, stats = context.stats, consumer = context.consumer
        context.clock.asyncAfter(deadline: .now() + limits.cardShown) { [weak hold] in
            guard hold?.end(.notShown) == true else { return }
            stats.count(.cardNotShown)
            NSLog("[Claude] hook server: the notch didn't show a card in %.1f s; Claude Code asks in its terminal", limits.cardShown)
        }
        context.clock.asyncAfter(deadline: .now() + limits.card) { [weak hold] in
            guard hold?.end(.timedOut) == true else { return }
            stats.count(.cardTimedOut)
            NSLog("[Claude] hook server: a card went unanswered for %.0f s; Claude Code asks in its terminal", limits.card)
        }
        context.intake.async { consumer.approval(event, hold) }
    }

    /// A body over the limit: Aris can't take the event in, so a hook event gets the neutral reply (with the token:
    /// the head is enough to check it) and anything else is refused.
    private func tooBig(_ head: HTTPHead) {
        context.stats.count(.tooBig)
        let request = HTTPRequest(method: head.method, path: head.path, body: Data(), headers: head.headers)
        let known = context.token().map { request.hasToken($0) } ?? false
        NSLog("ClaudeHookServer: %@ %@ is over %d bytes and was not read", head.method, head.path, HTTPRequestParser.maxBytes)
        finish(known && ClaudeHookRoute.isHook(head) ? .neutral : .refusal("413 Payload Too Large"))
    }

    /// Sends the one answer; false when another path already did (or, for `only`, when the connection has moved on
    /// from that phase: a deadline for a request still being decided must not answer one a card now holds).
    @discardableResult
    private func finish(_ reply: HookReply, only: Phase? = nil) -> Bool {
        guard lock.withLock({ () -> Bool in
            guard phase != .answered, only == nil || phase == only else { return false }
            phase = .answered
            return true
        }) else { return false }
        connection.send(content: reply.bytes, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { [weak self] _ in self?.sent() })
        return true
    }

    /// The answer is out: the connection closes once the client has (it reads `Connection: close`), or after the
    /// linger; at once when the client is already gone or the server is closing.
    private func sent() {
        let closeNow = lock.withLock { () -> Bool in
            replySent = true
            return clientDone || closing
        }
        guard !closeNow else { return connection.cancel() }
        context.clock.asyncAfter(deadline: .now() + context.limits.linger) { [weak self] in self?.connection.cancel() }
    }

    private func closed() {
        let hold = lock.withLock { () -> HookHold? in
            phase = .answered
            clientDone = true
            return self.hold
        }
        hold?.end(.clientGone)
        onClose(self)
    }

    // MARK: - Deadlines (on the clock queue)

    private func readLimitPassed() {
        let hookEvent = lock.withLock { self.hookEvent }
        guard finish(hookEvent ? .neutral : .refusal("408 Request Timeout"), only: .reading) else { return }
        context.stats.count(.unread)
        NSLog("[Claude] hook server: a request didn't arrive in %.1f s; its connection was answered and closed", context.limits.read)
    }

    private func answerLimitPassed(_ path: String) {
        guard finish(.neutral, only: .deciding) else { return }
        context.stats.count(.late)
        NSLog("[Claude] hook server: %@ wasn't answered in %.0f ms; the neutral reply was sent", path, context.limits.answer * 1000)
    }

    private func slowLimitPassed(_ path: String) {
        guard finish(.refusal("504 Gateway Timeout")) else { return }
        context.stats.count(.slowTimedOut)
        NSLog("[Claude] hook server: %@ wasn't answered in %.0f s; its connection was closed", path, context.limits.slow)
    }
}
