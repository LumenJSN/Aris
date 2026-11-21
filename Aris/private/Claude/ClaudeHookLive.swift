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
                                               switch path {
                                               case "/aris/todos": todos(object, reply)
                                               case ClaudeSessionsRoute.path: sessions(object, reply)
                                               case ArisPermissionRoute.path: permission(object, reply)
                                               default: events(object, reply)
                                               }
                                           })

    /// aris-agent's look at the user's Claude Code sessions before it sends a prompt into one, and its note that it did
    /// (ClaudeSessionsRoute): a read of what the hooks heard, and a watch for the session's next Stop.
    private static func sessions(_ object: [String: Any], _ reply: @escaping (HookReply) -> Void) {
        Task { @MainActor in
            reply(.ok(ClaudeSessionsRoute.answer(object, store: ClaudeStore.shared, watch: .shared)))
        }
    }

    /// aris-tools' first Apple Event to an app (ArisPermissionRoute): the feature's line of why, once, from the app's
    /// permission layer; macOS then asks by itself at the event.
    private static func permission(_ object: [String: Any], _ reply: @escaping (HookReply) -> Void) {
        guard let feature = ArisPermissionRoute.feature(object) else { return reply(.refusal(HookRequestReader.badRequest)) }
        Task { @MainActor in
            let center = ArisPermissionCenter.shared
            let proceed = ArisPermissionRoute.saysLine(feature, in: center.model) ? await center.require(feature) : true
            reply(.ok(ArisPermissionRoute.reply(proceed: proceed)))
        }
    }

    /// aris-tools' `todo`: Apple Reminders live in the app.
    private static func todos(_ object: [String: Any], _ reply: @escaping (HookReply) -> Void) {
        guard let todo = ArisTodoRoute.Request(json: object) else { return reply(.refusal(HookRequestReader.badRequest)) }
        Task { @MainActor in
            // A write only with the agent's grant for exactly it (ArisActionGrant): the token alone never writes.
            let grant = await ArisAgentClient.grant(for: ArisActionGrant.key(todo: object))
            guard grant.granted else { return reply(.ok(ArisTodoRoute.response(ok: false, message: ArisActionGrant.refusal))) }
            // From a turn the user is in front of, a missing Reminders grant is asked for now, once, after the line of
            // why (the permission layer); from anywhere else the handler says it is off.
            // The request waits for macOS's answer however long the person takes (up to ArisPermissionWait.dialog), then
            // is done under the grant it already had: never "run it again", never a second card (VM run 2026-11-19, A2).
            if ArisPermissionRoute.asks(object, granted: ArisReminders.shared.accessNow()), await !answered(.reminders) {
                return reply(.ok(ArisTodoRoute.response(ok: false, message: ArisPermissionWait.stillAskingLine)))
            }
            let answer = await ArisTodoRouteHandler.handle(todo)
            // Made by a write the automatic check let through: outside text in later turns' calendar (review 9, M2).
            if grant.outside { ArisOutsideItems.shared.noteMade(in: answer) }
            reply(.ok(answer))
        }
    }

    /// The permission layer's ask for `feature` (its line of why in the turn, then macOS's dialog): whether macOS
    /// answered within ArisPermissionWait.dialog, yes or no. A no leaves the permission off and the route says so.
    private static func answered(_ feature: ArisPermissionFeature) async -> Bool {
        await ArisPermissionWait.first(within: ArisPermissionWait.dialog) { await ArisPermissionCenter.shared.require(feature) } != nil
    }

    /// aris-tools' `event find|delete|change` (and add): the app holds the Calendar grant (ArisEventRoute, QA BUG-53).
    private static func events(_ object: [String: Any], _ reply: @escaping (HookReply) -> Void) {
        Task {
            // add, delete and change only with the agent's grant for exactly that event; find is a read.
            let grant = await ArisAgentClient.grant(for: ArisActionGrant.key(event: object))
            guard grant.granted else { return reply(.ok(ArisEventRoute.reply(ok: false, line: ArisActionGrant.refusal))) }
            // From a turn the user is in front of, a missing Calendars grant is asked for now, once, after the line of
            // why (the permission layer); from anywhere else the route says it is off (ArisEventRoute.noAccessLine).
            // The request waits for macOS's answer however long the person takes (up to ArisPermissionWait.dialog), then
            // is done under the grant it already had: never "run it again", never a second card (VM run 2026-11-19, A2).
            if ArisPermissionRoute.asks(object, granted: ArisLiveEventStore.granted), await !answered(.calendar) {
                return reply(.ok(ArisEventRoute.reply(ok: false, line: ArisPermissionWait.stillAskingLine)))
            }
            let answer = await Task.detached(priority: .userInitiated) { ArisEventRoute.handle(object) }.value
            // Made by a write the automatic check let through: outside text in later turns' calendar (review 9, M2).
            if grant.outside, object["op"] as? String == "add" { ArisOutsideItems.shared.noteMade(in: answer) }
            reply(.ok(answer))
        }
    }
}
