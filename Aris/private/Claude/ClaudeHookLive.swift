//
//  ClaudeHookLive.swift
//  Aris
//
//  The running app's hook server and what it hands its work to: hook events, status reports and cards go to the
//  Claude store (HookConsumer.feeding, ClaudeStore.take); aris-tools' `todo` and `event` are answered once Reminders
//  or Calendar has.
//

import Foundation

extension ClaudeHookServer {
    static let shared = ClaudeHookServer(consumer: .live)
}

extension HookConsumer {
    /// The Claude store is fed on the main queue (HookConsumer.feeding). A locked Mac or a sleeping display shows no
    /// card: Claude Code asks in its own terminal.
    static let live = HookConsumer.feeding({ ClaudeStore.shared }, cardPossible: { !ArisQuietGate.screenIsAway() },
                                           slow: { path, object, reply in
                                               path == "/aris/todos" ? todos(object, reply) : events(object, reply)
                                           })

    /// aris-tools' `todo`: Apple Reminders live in the app.
    private static func todos(_ object: [String: Any], _ reply: @escaping (HookReply) -> Void) {
        guard let todo = ArisTodoRoute.Request(json: object) else { return reply(.refusal(HookRequestReader.badRequest)) }
        Task { @MainActor in
            // A write only with the agent's grant for exactly it (ArisActionGrant): the token alone never writes.
            let grant = await ArisAgentClient.grant(for: ArisActionGrant.key(todo: object))
            guard grant.granted else { return reply(.ok(ArisTodoRoute.response(ok: false, message: ArisActionGrant.refusal))) }
            let answer = await ArisTodoRouteHandler.handle(todo)
            // Made by a write the automatic check let through: outside text in later turns' calendar (review 9, M2).
            if grant.outside { ArisOutsideItems.shared.noteMade(in: answer) }
            reply(.ok(answer))
        }
    }

    /// aris-tools' `event find|delete|change` (and add): the app holds the Calendar grant (ArisEventRoute, QA BUG-53).
    private static func events(_ object: [String: Any], _ reply: @escaping (HookReply) -> Void) {
        Task {
            // add, delete and change only with the agent's grant for exactly that event; find is a read.
            let grant = await ArisAgentClient.grant(for: ArisActionGrant.key(event: object))
            guard grant.granted else { return reply(.ok(ArisEventRoute.reply(ok: false, line: ArisActionGrant.refusal))) }
            let answer = await Task.detached(priority: .userInitiated) { ArisEventRoute.handle(object) }.value
            // Made by a write the automatic check let through: outside text in later turns' calendar (review 9, M2).
            if grant.outside, object["op"] as? String == "add" { ArisOutsideItems.shared.noteMade(in: answer) }
            reply(.ok(answer))
        }
    }
}
