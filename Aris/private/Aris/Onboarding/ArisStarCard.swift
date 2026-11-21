//
//  ArisStarCard.swift
//  Aris
//
//  The setup's last page (준비 끝났어요) carries one small card for Aris's GitHub repository (the owner's pick B,
//  2026-11-17: the repository's name, its star count and one button). Its rules, pure so the tests run each state:
//   · gh logged in, not starred: "@login 계정으로 별 남기기"; the star is left only when that button is pressed;
//   · while it is being left: the same button, its words under a linear sweep;
//   · left: "별 남겼어요, 고마워요", the count one up;
//   · no gh, no login, or anything failing: "GitHub에서 별 남기기 ↗" opens the repository's page in the browser;
//   · already starred: only "별 고마워요";
//   · 건너뛰기 folds the card away. Skipped or starred, it is recorded and the card never shows again.
//  The helper's answers come from aris-agent (ArisGitHubStar); the count from GitHub's public API, no login.
//

import Foundation

enum ArisStarCard {
    static let repo = "LumenJSN/Aris"
    static let page = URL(string: "https://github.com/LumenJSN/Aris")!
    /// Public and unauthenticated: its `stargazers_count`.
    static let api = URL(string: "https://api.github.com/repos/LumenJSN/Aris")!
    /// The count's own limit.
    static let countTimeout: TimeInterval = 5
    /// UserDefaults: "starred" or "skipped" once the card is settled.
    static let settledKey = "arisStarCardSettled"

    enum Settled: String { case starred, skipped }

    enum State: Equatable {
        /// gh is being asked; nothing to press yet.
        case looking
        /// Logged in as `login`, not starred.
        case ask(login: String)
        /// The star is being left.
        case busy(login: String)
        /// Just starred, on this page.
        case done
        /// No gh, no login, or something failed: the repository's page in the browser.
        case web
        /// Starred before.
        case thanks
        /// Skipped, or settled before this showing: no card.
        case gone
    }

    /// What pressing the card's button does.
    enum Press: Equatable { case star, open, none }

    /// The card as the page opens: gone for good once it was skipped or starred; otherwise gh is asked.
    static func opening(settled: String?) -> State { settled.flatMap(Settled.init(rawValue:)) == nil ? .looking : .gone }

    /// The helper's answer to the check ({"gh": "ready", "login": …, "starred": …}); anything short of a login and a
    /// clear yes or no (no gh, no login, no answer) is the browser's way.
    static func checked(_ reply: [String: Any]?) -> State {
        guard let reply, reply["gh"] as? String == "ready", let login = reply["login"] as? String, validLogin(login),
              let starred = reply["starred"] as? Bool else { return .web }
        return starred ? .thanks : .ask(login: login)
    }

    /// The helper's answer to the star ({"starred": true}); anything else is the browser's way.
    static func starred(_ reply: [String: Any]?) -> State { reply?["starred"] as? Bool == true ? .done : .web }

    /// A check that comes back after the card changed (skipped meanwhile) is dropped.
    static func takes(check state: State) -> Bool { state == .looking }

    static func press(_ state: State) -> Press {
        switch state {
        case .ask: .star
        case .web: .open
        case .looking, .busy, .done, .thanks, .gone: .none
        }
    }

    /// The star is being left for `state`.
    static func pressing(_ state: State) -> State {
        if case .ask(let login) = state { return .busy(login: login) }
        return state
    }

    /// What a state records: starred (just now, or before) or nothing yet. Skipping records `.skipped` itself.
    static func settles(_ state: State) -> Settled? {
        switch state {
        case .done, .thanks: .starred
        default: nil
        }
    }

    /// 건너뛰기 shows while there is something to skip (not while the star is being left, nor once it is).
    static func skips(_ state: State) -> Bool {
        switch state {
        case .looking, .ask, .web: true
        case .busy, .done, .thanks, .gone: false
        }
    }

    /// The star is filled (gold) and the card's edge warm.
    static func filled(_ state: State) -> Bool { state == .done || state == .thanks }

    /// `stargazers_count` from the public API's JSON; nil (the chip is hidden) for anything else.
    static func count(from data: Data?) -> Int? {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let count = object["stargazers_count"] as? Int, count >= 0 else { return nil }
        return count
    }

    /// The count the chip shows: one up once the star was left on this page.
    static func shownCount(_ base: Int?, _ state: State) -> Int? { base.map { state == .done ? $0 + 1 : $0 } }

    /// GitHub's login shape: letters, digits and single inner hyphens, at most 39.
    static func validLogin(_ login: String) -> Bool {
        guard (1...39).contains(login.count), !login.hasPrefix("-"), !login.hasSuffix("-"), !login.contains("--") else { return false }
        return login.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") }
    }
}
