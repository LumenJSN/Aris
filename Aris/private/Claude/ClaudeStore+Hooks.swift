//
//  ClaudeStore+Hooks.swift
//  Aris
//
//  How a held hook request (Claude's PermissionRequest) becomes a card. The hook server has already made sure nothing
//  else waits for this: here, on the main actor, the session is noted and the card goes up, unless no card can be
//  seen now or the server stopped waiting before the notch got to it (a stalled main thread): then the request gets
//  "no decision" and Claude Code asks in its own terminal. A hold that ends without the user's answer (its time passed,
//  the client left, Aris is closing) takes its card down.
//  Foundation only (tested).
//

import Foundation

extension ClaudeStore {
    func take(_ event: ClaudeHookEvent, hold: HookHold, cardPossible: Bool = true) {
        apply(event)
        let approval = ClaudeApproval(
            id: UUID(),
            sessionId: event.sessionId,
            cwd: event.cwd,
            toolName: event.toolName ?? "Tool",
            summary: event.toolSummary ?? "",
            kind: event.approvalKind,
            alwaysRules: event.permissionSuggestions,
            toolInput: event.toolInput as NSDictionary,
            edit: event.edit
        )
        let drop: (HookHold.End) -> Void = { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.cancelApproval(approval.id) } }
        }
        guard cardPossible, hold.show(onEnd: drop) else { return hold.answer(nil) }
        requestApproval(approval, resolve: { decision in hold.answer(decision.responseBody(input: event.toolInput)) },
                        onDrop: { hold.answer(nil) })
    }
}

extension HookConsumer {
    /// The consumer that feeds a Claude store. Events, status reports and cards are put on the main queue in the
    /// order the server handed them over and nothing here waits for the main thread: while it is wedged they pile
    /// up, the server keeps answering, and a card that could not go up in time is never shown late (`take`).
    /// `cardPossible` is asked on the main thread as a card is about to go up; `slow` is the app's to-do and event routes.
    static func feeding(_ store: @escaping @MainActor () -> ClaudeStore, cardPossible: @escaping @MainActor () -> Bool = { true },
                        slow: @escaping (String, [String: Any], @escaping (HookReply) -> Void) -> Void) -> HookConsumer {
        HookConsumer(
            event: { event in
                DispatchQueue.main.async { MainActor.assumeIsolated { store().apply(event) } }
            },
            // Status line updates (plan limits, context use) from statusline.sh.
            status: { object in
                guard let report = ClaudeStatusReport(json: object) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { store().applyStatus(report) } }
            },
            approval: { event, hold in
                DispatchQueue.main.async { MainActor.assumeIsolated { store().take(event, hold: hold, cardPossible: cardPossible()) } }
            },
            slow: slow)
    }
}
