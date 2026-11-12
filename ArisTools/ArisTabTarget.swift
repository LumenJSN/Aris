//
//  ArisTabTarget.swift
//  aris-tools
//
//  Which browser `tab` reads. A bare `tab` reads the browser in front, else the first one running, as it always did.
//  `tab --app <bundle id>` reads exactly that browser: the helper's look names the app it chose (with Aris in front the
//  first running browser used to be read and labelled as the chosen one: security review 3, M1), and a named browser
//  that isn't running, or an app that is no known browser, fails with nothing read. A private (incognito) window's tab
//  is read like any other: the owner's ruling of 2026-11-11. Foundation only (tested).
//

import Foundation

enum ArisTabTarget {
    enum Choice: Equatable {
        /// The browser to read, by its bundle id as macOS writes it.
        case browser(String)
        /// Nothing is read: why, in words.
        case refused(String)
    }

    /// `named`: the bundle id after --app (any letter case); `front`: the app in front; `running`: every running app;
    /// `browsers`: the browsers Aris reads tabs from, in the order a bare `tab` tries them.
    static func choose(named: String?, front: String?, running: Set<String>, browsers: [String]) -> Choice {
        guard let named else {
            let picked = front.flatMap { front in browsers.first { $0 == front } } ?? browsers.first(where: running.contains)
            return picked.map(Choice.browser) ?? .refused("no browser is open")
        }
        guard let browser = browsers.first(where: { $0.lowercased() == named.lowercased() }) else { return .refused(notBrowser(named)) }
        return running.contains(browser) ? .browser(browser) : .refused(notRunning(browser))
    }

    static func notBrowser(_ named: String) -> String { "\(named.isEmpty ? "that" : named) isn't a browser Aris reads tabs from" }
    static func notRunning(_ browser: String) -> String { "\(browser) isn't running, so there is no tab to read" }
}
