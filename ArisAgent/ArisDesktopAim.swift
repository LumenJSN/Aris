//
//  ArisDesktopAim.swift
//  aris-agent
//
//  Which of an app's windows a desktop action with no ref works in (audit desk-1: the user said "무제 창 내용 다 지워 줘"
//  with "무제 2" in front, and `press cmd+a delete` emptied 무제 2). Keys, a look-and-click and a window operation go to
//  the window the call names (`--window`, `--title`), else to the one the user's words name, never to the front one by
//  default while he named another. A menu, a dialog button or a file panel can only act on the app's front window, so
//  with another document in front they are refused, with the way to bring the named one forward. Pure.
//

import Foundation

enum ArisDesktopAim: Equatable {
    /// Nothing to pin: the call goes on as it is.
    case asIs
    /// The call works in this window (its id), whatever is in front.
    case window(Int)
    /// Nothing is done. `readsTitles`: the line lists other windows' titles (outside text the turn has then read).
    case refuse(String, readsTitles: Bool)

    /// `named`: the window the user's words name (ArisWindowNaming.named). `windows`: the app's, front to back.
    /// `isDialog`: a look of this conversation showed that window to be a sheet, a panel or a dialog.
    static func decide(_ request: ArisDesktopRequest, named: ArisDesktopWindow?, windows: [ArisDesktopWindow], app: String,
                       isDialog: (Int) -> Bool = { _ in false }) -> ArisDesktopAim {
        guard request.verb.kind == .action, request.ref == nil else { return .asIs }
        switch request.verb {
        case .press, .clickAt:
            var asked = request.window
            if asked == nil, let title = request.title {
                if ArisWindowTitleMatch.titlesUnreadable(windows) {
                    return .refuse(ArisWindowTitleMatch.unreadableLine(wanted: title, app: app), readsTitles: false)
                }
                let match = ArisWindowTitleMatch.pick(title, in: windows)
                guard case .one(let id) = match else {
                    var lists = false
                    if case .several = match { lists = true }
                    return .refuse(ArisWindowTitleMatch.line(match, wanted: title, app: app) ?? "", readsTitles: lists)
                }
                asked = id
            }
            guard let named else { return asked.map(ArisDesktopAim.window) ?? .asIs }
            if let asked, asked != named.id { return .refuse(otherWindowLine(named: named.title ?? "", app: app), readsTitles: false) }
            return .window(named.id)
        case .window:
            // A window operation that names no window is for the one the user named; one that names its own is left alone
            // (moving one window beside another names two).
            guard request.window == nil, request.title == nil, let named else { return .asIs }
            return .window(named.id)
        case .menuClick, .dialogClick, .dialogInput, .dialogFile:
            guard let named else { return .asIs }
            // The app's front document: a sheet or dialog of its own over it (untitled, or seen to be one) isn't another.
            guard let front = windows.first(where: { !($0.title ?? "").isEmpty && !isDialog($0.id) }), front.id != named.id else { return .asIs }
            return .refuse(frontFirstLine(named: named.title ?? "", front: front, app: app), readsTitles: false)
        default:
            return .asIs
        }
    }

    private static func quoted(_ title: String) -> String { ArisDesktopCard.shown(ArisWindowTitleMatch.safeTitle(title)) }

    /// Keys or a look-and-click aimed at another window than the one the user named.
    static func otherWindowLine(named: String, app: String) -> String {
        "The user named the window “\(quoted(named))”, and this call is aimed at another window of \(app), so nothing was done. " +
            "Aim it at the named one: add `--title \"\(quoted(named))\"`."
    }

    /// A menu or dialog call while another of the app's documents is in front of the one the user named.
    static func frontFirstLine(named: String, front: ArisDesktopWindow, app: String) -> String {
        "The user named the window “\(quoted(named))”, but another window of \(app) is in front (window-id \(front.id)), and a menu, a dialog " +
            "button or a file panel acts on the front one, so nothing was done. Bring the named one forward first with " +
            "`desktop window focus --app \"\(app)\" --title \"\(quoted(named))\"`, then run this again. (If the window in front is that " +
            "window's own panel or dialog, look at it first with `desktop see --app \"\(app)\" --window \(front.id)`.)"
    }
}
