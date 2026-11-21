//
//  ArisBrowserActs.swift
//  Shared/Core (aris-agent, tests)
//
//  Decision 2 (2026-11-18): a browser window through Aris's own app engine. Looks (reading the page, its address, its
//  tree, scrolling) run without a card; every act on the page (a click, typing, keys, a choice, a command) asks on a
//  card of its own each time that names the site's host, is never covered by an earlier yes and never kept as a grant.
//  The page's words stay outside content. A sign-in form's field or button, or a password field, is touched only when
//  the owner's own words of this turn ask for signing in, and nothing is ever typed into a password field. Pure.
//

import Foundation

/// What the trust policy knows of an act in a browser window (the gate reads it live).
struct ArisBrowserPage: Equatable, Sendable {
    /// The front page's host ("shop.example"); nil when it couldn't be read.
    var host: String?
    /// The element acted on, as the app shows it (its label, else the call's own words).
    var target: String?
    /// The element is a password field (a secure text field, or labelled as one).
    var secret = false
    /// The element belongs to signing in (a username, a sign-in button, a one-time code).
    var signIn = false
    /// The owner's own words of this turn ask for signing in ("로그인해 줘", "sign me in").
    var signInAsked = false
}

enum ArisBrowserActs {
    /// The app capabilities that act on what a window shows (a look, a scroll, a window's frame are not).
    static let acts: Set<String> = ["app.click", "app.type", "app.press", "app.select", "app.do", "app.recipe"]
    /// The ones that type text.
    static let typing: Set<String> = ["app.type", "app.recipe"]

    static let names: Set<String> = ["safari", "사파리", "safari technology preview", "google chrome", "chrome", "크롬", "chromium", "arc", "firefox",
                                     "파이어폭스", "firefox developer edition", "firefox nightly", "microsoft edge", "edge", "엣지", "brave browser", "brave",
                                     "opera", "opera gx", "orion", "zen", "zen browser", "vivaldi", "whale", "naver whale", "웨일", "네이버 웨일"]
    static let bundles: Set<String> = ["com.apple.safari", "com.apple.safaritechnologypreview", "com.google.chrome", "com.google.chrome.canary",
                                       "org.chromium.chromium", "company.thebrowser.browser", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
                                       "org.mozilla.nightly", "com.microsoft.edgemac", "com.brave.browser", "com.operasoftware.opera",
                                       "com.operasoftware.operagx", "com.kagi.kagimacos", "app.zen-browser.zen", "com.vivaldi.vivaldi", "com.naver.whale"]

    /// A web browser by its name or bundle id, in any case.
    static func isBrowser(_ app: String) -> Bool {
        let folded = app.trimmingCharacters(in: .whitespaces).lowercased()
        return names.contains(folded) || bundles.contains(folded)
    }

    /// The host of an address ("https://www.shop.example/cart" → "www.shop.example").
    static func host(_ address: String?) -> String? {
        guard let address, let host = URL(string: address)?.host, !host.isEmpty else { return nil }
        return host.lowercased()
    }

    private static let signInLabels = ["password", "passcode", "passwd", "비밀번호", "암호", "패스워드", "sign in", "signin", "sign-in", "log in", "login",
                                       "log-in", "로그인", "username", "user name", "아이디", "one-time code", "verification code", "인증번호", "인증 코드", "otp"]
    private static let secretLabels = ["password", "passcode", "passwd", "비밀번호", "암호", "패스워드", "pin"]

    /// An element's words that belong to signing in.
    static func namesSignIn(_ label: String?) -> Bool {
        guard let label else { return false }
        let folded = label.lowercased()
        return signInLabels.contains(where: folded.contains)
    }

    /// An element's words that name a password field.
    static func namesSecret(_ label: String?) -> Bool {
        guard let label else { return false }
        let folded = " " + label.lowercased() + " "
        return secretLabels.contains { folded.contains($0 == "pin" ? " pin " : $0) }
    }

    /// The owner's words ask for signing in.
    static func asksForSignIn(_ words: String) -> Bool {
        ArisGrounding.has(["로그인", "로그 인", "비밀번호 입력", "인증", "sign in", "sign me in", "log in", "log me in", "login"], in: words)
    }

    static let secretRefusal = "비밀번호 칸에는 Aris가 입력하지 않아요. 직접 입력해 주세요. (Aris never types into a password field.)"
    static let signInRefusal = "로그인 칸은 로그인해 달라고 직접 말씀하실 때만 눌러요. (A sign-in form is touched only when you ask to sign in.)"

    /// The decision for an act in a browser, after every other rule: a refusal stays; a password field is never typed
    /// into; a sign-in form only on the owner's own words asking for it; anything else is a card of its own (`.ask`).
    static func decide(_ decided: ArisDecision, call: ArisCallFacts, provenance: ArisCallProvenance) -> ArisDecision {
        guard let page = call.browser else { return decided }
        if case .refuse = decided { return decided }
        if page.secret, typing.contains(call.capability) { return .refuse(reason: secretRefusal) }
        if page.secret || page.signIn, !(page.signInAsked && provenance == .ownerSaid) { return .refuse(reason: signInRefusal) }
        return .ask
    }
}
