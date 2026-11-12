//
//  ArisMailCommand.swift
//  aris-tools
//
//  The command line of a whole mail, a thread and a reply (the lists stay in ArisLocalReadCommands.mailRead):
//    mail read <id> [--part N] [--quoted]     one mail's whole text (the id is the #number a list shows)
//    mail thread <id>                         the mails of its conversation, oldest first, quoted history folded
//    mail reply <id> --text "<reply>" [--all] [--to <address>] [--cc <address>]
//                                             opens the reply in Mail as a draft, after the user's card; never sends
//  Reading asks macOS for nothing (a missing Full Disk Access is one Korean line). The reply opens through Mail's own
//  new-message address, so it needs no permission to control Mail.
//

import AppKit
import Foundation

private let mailHome = FileManager.default.homeDirectoryForCurrentUser.path

/// `mail read`, `mail thread` or `mail reply`: done here. False for the lists.
func mailMore(_ args: [String]) -> Bool {
    switch args.first {
    case "read": mailWhole(Array(args.dropFirst()))
    case "thread": mailThread(Array(args.dropFirst()))
    case "reply": mailReply(args)
    default: return false
    }
    return true
}

/// Mail's index, and the folder its mail files are under; a store error is its Korean line (exit 1).
private func mailStore() -> (db: ArisLocalDatabase, root: String) {
    do {
        let path = try ArisMailRead.databasePath(home: mailHome)
        // <root>/MailData/Envelope Index
        return (try ArisLocalDatabase(path: path), ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent)
    } catch { fail(ArisLocalStore.line(error, app: "Mail")) }
}

/// The number in "412" or "#412".
private func mailNumber(_ word: String?) -> Int64? {
    guard let word else { return nil }
    return Int64(word.hasPrefix("#") ? String(word.dropFirst()) : word).flatMap { $0 > 0 ? $0 : nil }
}

private let mailGone = "그 번호의 메일을 찾지 못했어요 (옮겨졌거나 지워졌을 수 있어요). mail search로 다시 찾아 주세요."

private func mailWhole(_ args: [String]) {
    let plain = ArisLocalStore.plainWords(args, flags: ["--part"]).filter { $0 != "--quoted" }
    guard plain.count == 1, let id = mailNumber(plain[0]) else { fail("usage: mail read <id> [--part N] [--quoted]   (the id is the #number `mail recent` and `mail search` show)") }
    let part = ArisLocalStore.value("--part", in: args).flatMap { Int($0) } ?? 1
    let store = mailStore()
    do {
        guard let envelope = try ArisMailStore.envelope(store.db, id: id) else { fail(mailGone) }
        print(ArisMailStore.printed(ArisMailStore.full(root: store.root, envelope: envelope), part: part, quoted: args.contains("--quoted")))
    } catch { fail(ArisLocalStore.line(error, app: "Mail")) }
}

private func mailThread(_ args: [String]) {
    guard args.count == 1, let id = mailNumber(args[0]) else { fail("usage: mail thread <id>   (the id is the #number of any mail in it)") }
    let store = mailStore()
    do {
        let found = try ArisMailStore.thread(store.db, id: id)
        guard !found.mails.isEmpty else { fail(mailGone) }
        print(ArisMailStore.printed(thread: found.mails.map { ArisMailStore.full(root: store.root, envelope: $0) }, left: found.left))
    } catch { fail(ArisLocalStore.line(error, app: "Mail")) }
}

/// The reply worked out from Mail's own record of the mail, as the card showed it, then opened in Mail as a draft.
private func mailReply(_ args: [String]) {
    guard let words = ArisMailReplyWords.parse(args) else { fail(ArisMailReplyWords.usage) }
    let store = mailStore()
    let plan: ArisMailReplyPlan
    do {
        guard let original = try ArisMailStore.envelope(store.db, id: words.id) else { fail(ArisMailReply.noSuchMail(words.id)) }
        let replyTo = ArisMailStore.full(root: store.root, envelope: original).content?.addresses("reply-to").first
        plan = ArisMailReply.plan(words, original: original, replyTo: replyTo, thread: try ArisMailStore.thread(store.db, id: words.id).mails,
                                  own: ArisMailStore.own(store.db), request: "")
    } catch { fail(ArisLocalStore.line(error, app: "Mail")) }
    guard let address = ArisMailReply.mailto(plan) else { fail(ArisMailReply.noRecipient) }
    guard let mail = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail") else { fail(ArisMailReply.noMail) }
    // Only Mail opens it, whatever the Mac's default mail app is: the mail being answered lives there.
    let done = DispatchSemaphore(value: 0)
    var failure: Error?
    NSWorkspace.shared.open([address], withApplicationAt: mail, configuration: NSWorkspace.OpenConfiguration()) { _, error in
        failure = error
        done.signal()
    }
    guard done.wait(timeout: .now() + 15) == .success, failure == nil else { fail(ArisMailReply.couldntOpen) }
    logActivity("메일 답장 초안: \(plan.to.map(\.address).joined(separator: ", "))", undo: nil)
    print(ArisMailReply.drafted(plan))
}
