//
//  ArisTodoRouteHandler.swift
//  Aris
//
//  POST /aris/todos on the hook server: what `aris-tools todo` asks of the to-do list in Apple Reminders (list, add,
//  done, edit, remove, and reopen for an undo). Answers {ok, message, items}.
//

import Foundation

@MainActor
enum ArisTodoRouteHandler {
    static func handle(_ request: ArisTodoRoute.Request) async -> Data {
        let reminders = ArisReminders.shared
        reminders.start()
        await reminders.reload()
        guard await reminders.accessForRequest() else {
            // aris-tools asked for the to-do list in a turn: the button that allows Reminders goes under its answer.
            ArisFixModel.shared.noted(.pane(.reminders))
            // Read by the AI, which tells the user where: the page as the settings window names it on this Mac.
            return ArisTodoRoute.response(ok: false, message: "Reminders access hasn't been allowed for Aris (\(ArisSettingsPath.path(.todo)))")
        }
        switch request.op {
        case .list:
            return ArisTodoRoute.response(ok: true, message: "\(reminders.items.count) open", items: reminders.items)
        case .add:
            // The title as the tool named it, which is what the card showed: never read for dates (only --due sets one).
            var draft = ArisTodoModel.draft(title: request.text ?? "")
            guard !draft.title.isEmpty else { return ArisTodoRoute.response(ok: false, message: "nothing to add") }
            // A due date that was given and can't be read is said, never dropped (the reply then told of a date the
            // reminder didn't have).
            if let due = request.due {
                guard let parsed = ArisTodoDate.due(due, now: .now) else { return ArisTodoRoute.response(ok: false, message: ArisTodoDate.unreadDue(due)) }
                draft.due = parsed
                draft.hasTime = ArisTodoModel.hasTime(parsed)
            }
            if let name = request.list, !name.isEmpty {
                guard let list = reminders.lists.first(where: { $0.name.lowercased() == name.lowercased() }) else {
                    return ArisTodoRoute.response(ok: false, message: "no Reminders list named \"\(name)\"")
                }
                draft.listID = list.id
            }
            if let note = request.note { draft.notes = note }
            guard let item = await reminders.add(draft) else { return ArisTodoRoute.response(ok: false, message: "couldn't save it") }
            return ArisTodoRoute.response(ok: true, message: "added: \(item.title)", items: [item])
        case .reopen:
            // Undoing a tick (the activity log's undo): only by the id that was ticked.
            guard let id = request.id, await reminders.reopen(id) else {
                return ArisTodoRoute.response(ok: false, message: reminders.lastError ?? "couldn't reopen it")
            }
            return ArisTodoRoute.response(ok: true, message: "reopened")
        case .setDue:
            // Undoing 내일로 넘기기 (the activity log's undo): the date it had, only by the id that was moved.
            guard let item = request.id.flatMap({ id in reminders.items.first { $0.id == id } }), let at = request.at else {
                return ArisTodoRoute.response(ok: false, message: "that to-do isn't on the list any more")
            }
            var draft = ArisTodoDraft(item)
            draft.due = Date(timeIntervalSince1970: at)
            draft.hasTime = request.timed
            guard let saved = await reminders.update(item.id, draft) else { return ArisTodoRoute.response(ok: false, message: reminders.lastError ?? "couldn't save it") }
            return ArisTodoRoute.response(ok: true, message: "updated: \(saved.title)", items: [saved])
        case .done, .remove, .edit:
            guard let item = request.id.flatMap({ id in reminders.items.first { $0.id == id } }) ?? ArisTodoMatch.one(request.text ?? "", in: reminders.items) else {
                return ArisTodoRoute.response(ok: false, message: ArisTodoMatch.unclear(request.text ?? request.id ?? "", in: reminders.items))
            }
            switch request.op {
            case .done:
                guard await reminders.complete(item.id) else {
                    return ArisTodoRoute.response(ok: false, message: reminders.lastError ?? "couldn't complete it")
                }
                // With the item, so the log can keep its id (undo opens it again).
                return ArisTodoRoute.response(ok: true, message: "done: \(item.title)", items: [item])
            case .remove:
                guard await reminders.remove(item.id) else {
                    return ArisTodoRoute.response(ok: false, message: reminders.lastError ?? "couldn't remove it")
                }
                return ArisTodoRoute.response(ok: true, message: "removed: \(item.title)")
            default:
                var draft = ArisTodoDraft(item)
                if let note = request.note { draft.notes = note }
                if let title = request.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty { draft.title = title }
                if let due = request.due {
                    guard let parsed = ArisTodoDate.due(due, now: .now) else { return ArisTodoRoute.response(ok: false, message: ArisTodoDate.unreadDue(due)) }
                    draft.due = parsed
                    draft.hasTime = ArisTodoModel.hasTime(parsed)
                }
                guard let saved = await reminders.update(item.id, draft) else { return ArisTodoRoute.response(ok: false, message: "couldn't save it") }
                return ArisTodoRoute.response(ok: true, message: "updated: \(saved.title)", items: [saved])
            }
        }
    }
}
