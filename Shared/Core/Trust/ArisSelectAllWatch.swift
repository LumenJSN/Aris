//
//  ArisSelectAllWatch.swift
//  Shared/Core/Trust
//
//  A replace done as two calls (eleventh VM run, item 1): Select All in an app, then typing there. This is an extra
//  signal only. The guard itself is the field's selection, read fresh when every model typing is decided and read again
//  right before it types (ArisTrustGate, ArisApps.TypeOver's marks), so a Select All this watch doesn't recognise
//  (another word for it, a command the app layer resolved by itself) still never erases unseen text: the typing asks
//  when it sees it, or is stopped when it finds it. What the watch adds is the case no read at the decision can see:
//  a Select All decided in the same batch as the typing, before either ran. Then the typing is a replace of the field's
//  whole text, on the replace's card and bound to that text.
//  - A Select All is recognised from its command (its menu path read as the app layer reads one, ArisApps.MenuBar.path,
//    its last step compared as menu titles are), its key equivalent, or ⌘A among pressed keys; and from a result that
//    says it pressed one.
//  - It is kept per conversation and per app as the app layer resolves it (its bundle id), so two names of one app are
//    one; a call that names no app applies to any app (a missing name is never less strict than a named one).
//  - Nothing else clears it (a key, a click, a menu command may or may not drop the selection): only that typing, or
//    the owner's next turn. Pure.
//

import Foundation

struct ArisSelectAllWatch: Sendable {
    /// The key a call that names no app is kept under: it matches typing into any app.
    static let anyApp = "*"

    private var pending: [String: Set<String>] = [:]

    /// The Select All command by its title, in the languages macOS menus use (compared as ArisApps.MenuBar.titleKey).
    static let commands: Set<String> = [
        "select all", "전체 선택", "모두 선택", "전체선택", "모두선택", "すべてを選択", "全选", "全選", "alles auswählen",
        "tout sélectionner", "seleccionar todo", "selecciona todo", "seleziona tutto", "selecionar tudo", "alles selecteren",
        "выбрать все", "выделить все",
    ].reduce(into: Set<String>()) { $0.insert(ArisApps.MenuBar.titleKey($1)) }

    /// Whether one pressed key (as app.press takes them, "cmd+a") or a written key equivalent ("⌘A") is ⌘A alone.
    static func isCommandA(_ key: String) -> Bool {
        var folded = key.lowercased().replacingOccurrences(of: " ", with: "")
        for (from, to) in [("⌘", "cmd+"), ("command", "cmd"), ("meta", "cmd"), ("super", "cmd"), ("-", "+")] {
            folded = folded.replacingOccurrences(of: from, with: to)
        }
        let parts = folded.split(separator: "+").map(String.init).filter { !$0.isEmpty }
        return parts.count == 2 && parts[0] == "cmd" && parts[1] == "a"
    }

    /// Whether a command's words name Select All: its menu path's last step, or its key equivalent ("[cmd+a]").
    static func namesSelectAll(_ command: String) -> Bool {
        var text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("=") { text.removeFirst() }
        // A taught step's key equivalent in brackets: "=Edit › Select All [cmd+a]".
        if let open = text.lastIndex(of: "["), text.hasSuffix("]") {
            if isCommandA(String(text[text.index(after: open)..<text.index(before: text.endIndex)])) { return true }
            text = String(text[..<open])
        }
        if isCommandA(text) { return true }
        guard let last = ArisApps.MenuBar.path(text).last else { return false }
        let title = ArisApps.MenuBar.titleKey(last).trimmingCharacters(in: CharacterSet(charactersIn: "…. "))
        return commands.contains(title)
    }

    /// Whether a call selects everything in its app.
    static func selectsAll(capability: String, arguments: [String: Any]) -> Bool {
        switch capability {
        case "app.press":
            let keys = arguments["keys"] as? String ?? ""
            return keys.split(whereSeparator: { $0 == " " || $0 == "," }).contains { isCommandA(String($0)) } || isCommandA(keys)
        case "app.do":
            return namesSelectAll(arguments["command"] as? String ?? "")
        default:
            return false
        }
    }

    /// Whether a call's result says it pressed Select All ("pressed Edit › Select All in TextEdit", "pressed cmd+a in
    /// TextEdit"), whatever its arguments said: a command the app layer found by itself. Returns the app it names.
    static func selectedAll(capability: String, result: String) -> String? {
        guard capability == "app.do" || capability == "app.press",
              let data = result.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["ok"] as? Bool == true, let did = object["did"] as? String, did.hasPrefix("pressed "),
              let split = did.range(of: " in ", options: .backwards) else { return nil }
        let what = String(did[did.index(did.startIndex, offsetBy: "pressed ".count)..<split.lowerBound])
        let app = String(did[split.upperBound...])
        let hit = capability == "app.press" ? what.split(separator: " ").contains { isCommandA(String($0)) } : namesSelectAll(what)
        return hit ? app : nil
    }

    /// A Select All in `app` (its resolved key; nil or empty: no app named) for conversation `session`.
    mutating func note(session: String, app: String?) {
        let key = app.flatMap { $0.isEmpty ? nil : $0 } ?? Self.anyApp
        pending[session, default: []].insert(key)
    }

    /// A call of `session` was decided: noted when it selects everything. `app`: its app as resolved.
    mutating func acted(session: String, capability: String, arguments: [String: Any], app: String?) {
        guard Self.selectsAll(capability: capability, arguments: arguments) else { return }
        note(session: session, app: app)
    }

    /// Typing into `app` (resolved) is being decided: whether a Select All of this turn came before it, in that app or
    /// in one not named (told once).
    mutating func typing(session: String, app: String?) -> Bool {
        guard var apps = pending[session] else { return false }
        let key = app.flatMap { $0.isEmpty ? nil : $0 }
        let hit = key.map { apps.remove($0) != nil } ?? false
        let any = apps.remove(Self.anyApp) != nil
        // Typing that names no app goes to whichever is in front: any noted app counts.
        let unnamed = key == nil && !apps.isEmpty
        if unnamed { apps.removeAll() }
        pending[session] = apps.isEmpty ? nil : apps
        return hit || any || unnamed
    }

    /// The owner's next turn, or the conversation's end.
    mutating func newTurn(session: String) { pending[session] = nil }
}
