// Tests for the setup's last page, 준비 끝, and its repository card (the owner's pick B, 2026-11-17: the star card is not on
// the dictation page; a short last page after it carries the heading, one line, the card and 시작하기):
//  · the page order: 받아쓰기's 마치기 goes on to 준비 끝, whose 시작하기 finishes the setup;
//  · the card's states from the helper's answers (gh logged in, starring, starred, no gh, starred before, skipped);
//  · gh's 204 / 404 and its login read from what it printed; gh found at Homebrew's places or on PATH;
//  · skipped or starred, it is recorded and never shown again;
//  · anything failing falls back to opening the repository's page; nothing is starred but from the button.
// Pure: the runner is a fake that records what it was asked, gh is never run and nothing is starred.
// Called from main.swift; uses its check().
import Foundation

func runStarCardTests() {
    starCardPageOrderTests()
    starCardStateTests()
    starCardGHParsingTests()
    starCardGHCallsTests()
    starCardSettledTests()
    starCardFallbackTests()
    starCardWiringTests()
}

private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
private let onboarding = "Aris/private/Aris/Onboarding/"

private func code(_ path: String) -> String {
    let text = (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    return text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
}

private func part(_ text: String, from: String, to: String) -> String {
    guard let start = text.range(of: from) else { return "" }
    let rest = text[start.lowerBound...]
    guard let end = rest.range(of: to, range: rest.index(after: rest.startIndex)..<rest.endIndex) else { return String(rest) }
    return String(rest[..<end.lowerBound])
}

/// The answer as the app gets it: through JSON, as the helper sends it.
private func wire(_ body: [String: Any]) -> [String: Any]? {
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

private func wire(_ data: Data) -> [String: Any]? { try? JSONSerialization.jsonObject(with: data) as? [String: Any] }

/// A runner that answers from `answers` (by its arguments joined with spaces) and records every call.
private final class FakeGH {
    var calls: [(program: String, arguments: [String], timeout: TimeInterval)] = []
    var answers: [String: ArisGitHubStar.Run]
    private let lock = NSLock()

    init(_ answers: [String: ArisGitHubStar.Run]) { self.answers = answers }

    var runner: ArisGitHubStar.Runner {
        { [self] program, arguments, timeout in
            lock.withLock {
                calls.append((program, arguments, timeout))
                return answers[arguments.joined(separator: " ")]
            }
        }
    }

    var starred: Bool { lock.withLock { calls.contains { $0.arguments.contains("PUT") } } }
}

private let user = "api user --jq .login"
private let isStarred = "api -i /user/starred/LumenJSN/Aris"
private let putStar = "api -X PUT /user/starred/LumenJSN/Aris"
private let ok204 = ArisGitHubStar.Run(status: 0, out: "HTTP/2.0 204 No Content\nDate: Mon, 17 Nov 2026 10:00:00 GMT\n\n")
private let no404 = ArisGitHubStar.Run(status: 1, out: "HTTP/2.0 404 Not Found\nContent-Type: application/json\n\n{\"message\":\"Not Found\",\"status\":\"404\"}",
                                       err: "gh: Not Found (HTTP 404)")
private let octocat = ArisGitHubStar.Run(status: 0, out: "octocat\n")
private let signedOut = ArisGitHubStar.Run(status: 4, out: "", err: "To get started with GitHub CLI, please run:  gh auth login")

// MARK: - The page order

private func starCardPageOrderTests() {
    typealias Page = ArisSetupPage
    check(Page.allCases.last == .done && Page.allCases.suffix(2) == [.dictation, .done], "star card: 준비 끝 is the setup's last page, right after 받아쓰기")
    var flow = ArisSetupFlow(page: .dictation)
    check(flow.next() && flow.page == .done && !flow.finished, "star card: 받아쓰기's 마치기 goes on to 준비 끝 and doesn't finish the setup")
    check(!flow.next() && flow.finished, "star card: 시작하기 on 준비 끝 finishes the setup")
    var back = ArisSetupFlow(page: .done)
    back.back()
    check(back.page == .dictation && back.backShown, "star card: 뒤로 from 준비 끝 goes back to 받아쓰기")
    for settled in [true, false] {
        for ready in [0, 1, 2, nil] as [Int?] {
            let plan = ArisSetupPlan.make(permissionsSettled: settled, readyAIs: ready)
            check(plan.pages.last == .done && plan.pages.suffix(2) == [.dictation, .done],
                  "star card: every kind of user ends on 받아쓰기 → 준비 끝 (permissions \(settled ? "on" : "to do"), AIs \(ready.map(String.init) ?? "unknown"))")
        }
    }
    check(Page.resume(saved: 6) == .done && Page.resume(saved: 5) == .dictation, "star card: a setup put off on 준비 끝 comes back on it")
    check(ArisOnboardingTalk.mode(phase: .setup, page: .done) == .turn, "star card: on 준비 끝 the talk key is a real turn (Aris can be called right away)")
    let plan = ArisSetupPlan.make(permissionsSettled: false, readyAIs: 1)
    let rail = plan.pages.map { ArisSetupFlow(page: $0).progress(granted: [:], shown: plan.pages) }
    check(zip(rail, rail.dropFirst()).allSatisfy { abs($1 - $0 - 1 / Double(plan.pages.count)) < 1e-9 }, "star card: the rail still moves one equal share a page, 준비 끝 included")
}

// MARK: - The card's states

private func starCardStateTests() {
    typealias C = ArisStarCard
    check(C.repo == "LumenJSN/Aris" && C.page.absoluteString == "https://github.com/LumenJSN/Aris" && C.api.absoluteString == "https://api.github.com/repos/LumenJSN/Aris",
          "star card: the real repository, its page and its public API")
    check(C.checked(wire(["gh": "ready", "login": "octocat", "starred": false])) == .ask(login: "octocat"), "star card: gh logged in, not starred → \"@login 계정으로 별 남기기\"")
    check(C.checked(wire(["gh": "ready", "login": "octocat", "starred": true])) == .thanks, "star card: starred before → only \"별 고마워요\"")
    check(C.pressing(.ask(login: "octocat")) == .busy(login: "octocat") && C.pressing(.web) == .web, "star card: pressing the star → starring (the sweep), with the same words' account")
    check(C.starred(wire(["starred": true])) == .done, "star card: GitHub took the star → \"별 남겼어요, 고마워요\"")
    check(C.press(.ask(login: "a")) == .star && C.press(.web) == .open, "star card: the button stars with gh, opens the page without")
    for state in [C.State.looking, .busy(login: "a"), .done, .thanks, .gone] {
        check(C.press(state) == .none, "star card: \(state): the button does nothing")
    }
    check(C.skips(.looking) && C.skips(.ask(login: "a")) && C.skips(.web) && !C.skips(.busy(login: "a")) && !C.skips(.done) && !C.skips(.thanks) && !C.skips(.gone),
          "star card: 건너뛰기 shows while there is something to skip, not while starring nor once starred")
    check(C.filled(.done) && C.filled(.thanks) && !C.filled(.ask(login: "a")) && !C.filled(.web), "star card: the star is gold (and the edge warm) once starred")
    check(C.shownCount(128, .done) == 129 && C.shownCount(128, .ask(login: "a")) == 128 && C.shownCount(128, .thanks) == 128 && C.shownCount(nil, .done) == nil,
          "star card: the count rolls up one when the star is left here; none read, no chip")
    check(C.count(from: Data(#"{"full_name":"LumenJSN/Aris","stargazers_count":128}"#.utf8)) == 128, "star card: the count is the public API's stargazers_count")
    check(C.count(from: nil) == nil && C.count(from: Data("{}".utf8)) == nil && C.count(from: Data(#"{"stargazers_count":-1}"#.utf8)) == nil
          && C.count(from: Data(#"{"message":"API rate limit exceeded"}"#.utf8)) == nil && C.count(from: Data("not json".utf8)) == nil,
          "star card: a count that couldn't be read hides the chip")
    check(C.takes(check: .looking) && !C.takes(check: .gone), "star card: a check that comes back after 건너뛰기 is dropped")
    check(ArisOnboardingCopy.starAsk("@octocat") == "Star Aris as @octocat" && ArisOnboardingCopy.starBusy == "Starring" && ArisOnboardingCopy.starDone == "Starred. Thank you"
          && ArisOnboardingCopy.starWeb == "Star on GitHub ↗" && ArisOnboardingCopy.starThanks == "Thanks for the star",
          "star card: its words in English (Korean in the catalog: the onboarding strings lint)")
    check(ArisOnboardingCopy.doneLine(wakeWord: true, keys: "⌥ Space") == "Say “Aris” or press ⌥ Space, anytime." && ArisOnboardingCopy.doneLine(wakeWord: false, keys: "⌥ Space") == "Press ⌥ Space, anytime.",
          "star card: the page's line names the wake word only when it is on, and the talk shortcut as it is set")
}

// MARK: - What gh printed

private func starCardGHParsingTests() {
    typealias G = ArisGitHubStar
    check(G.status(ok204) == 204 && G.starred(ok204) == true, "gh: 204 No Content → starred")
    check(G.status(no404) == 404 && G.starred(no404) == false, "gh: 404 Not Found (gh exits 1) → not starred")
    check(G.starred(G.Run(status: 0, out: "HTTP/1.1 204 No Content\r\n\r\n")) == true, "gh: an HTTP/1.1 line with CRLF reads the same")
    check(G.starred(G.Run(status: 1, out: "HTTP/2.0 401 Unauthorized\n")) == nil && G.starred(G.Run(status: 1, out: "HTTP/2.0 500 Internal Server Error\n")) == nil,
          "gh: any other status is unknown, never a yes or no")
    check(G.starred(signedOut) == nil && G.starred(G.Run(status: 0, out: "")) == nil && G.starred(nil) == nil
          && G.starred(G.Run(status: -1, out: "HTTP/2.0 204 No Content\n", timedOut: true)) == nil,
          "gh: no status line, no run, or a run whose time ran out: unknown")
    check(G.status(G.Run(status: 0, out: "HTTPS/2 204\n")) == nil && G.status(G.Run(status: 0, out: "HTTP/2.0 abc\n")) == nil, "gh: only a real status line counts")
    check(G.login(octocat) == "octocat" && G.login(G.Run(status: 0, out: "  jdoe-gh \n")) == "jdoe-gh", "gh: the login it printed, trimmed")
    check(G.login(signedOut) == nil && G.login(nil) == nil && G.login(G.Run(status: -1, out: "octocat", timedOut: true)) == nil, "gh: no login when it failed or ran out of time")
    for bad in ["", "-x", "x-", "a--b", "has space", "ünï", String(repeating: "a", count: 40), "a\nb", "gho_secret$"] {
        check(G.login(G.Run(status: 0, out: bad)) == nil, "gh: \(bad.debugDescription) is not a GitHub login")
    }
    check(G.starDone(G.Run(status: 0, out: "")) && !G.starDone(G.Run(status: 1, out: "", err: "HTTP 404")) && !G.starDone(G.Run(status: -1, out: "", timedOut: true)) && !G.starDone(nil),
          "gh: the PUT went through only when gh exited 0 in time")

    let homebrew: Set = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/Users/me/bin/gh"]
    check(G.find(path: "/Users/me/bin:/usr/bin", executable: homebrew.contains) == "/opt/homebrew/bin/gh", "gh: Homebrew's place (Apple silicon) first")
    check(G.find(path: "/usr/bin", executable: ["/usr/local/bin/gh"].contains) == "/usr/local/bin/gh", "gh: then Homebrew's Intel place")
    check(G.find(path: "/usr/bin:/Users/me/bin/:relative", executable: ["/Users/me/bin/gh", "relative/gh"].contains) == "/Users/me/bin/gh", "gh: then each PATH folder (never a relative one)")
    check(G.find(path: "/usr/bin:/bin", executable: { _ in false }) == nil && G.find(path: nil, executable: { _ in false }) == nil, "gh: not installed")
}

// MARK: - The calls, on a fake runner

private func starCardGHCallsTests() {
    typealias G = ArisGitHubStar
    let fake = FakeGH([user: octocat, isStarred: no404])
    check(G.check(gh: "/opt/homebrew/bin/gh", run: fake.runner) == .ready(login: "octocat", starred: false), "gh check: logged in, not starred")
    check(fake.calls.count == 2 && Set(fake.calls.map { $0.arguments.joined(separator: " ") }) == [user, isStarred] && fake.calls.allSatisfy { $0.program == "/opt/homebrew/bin/gh" },
          "gh check: who is logged in and the starred check, nothing else")
    check(fake.calls.allSatisfy { $0.timeout == G.timeout } && G.timeout == 10, "gh check: each call has 10 s")
    check(!fake.starred, "gh check: a check never stars")
    check(G.check(gh: "/x/gh", run: FakeGH([user: octocat, isStarred: ok204]).runner) == .ready(login: "octocat", starred: true), "gh check: starred before")
    check(G.check(gh: "/x/gh", run: FakeGH([user: signedOut, isStarred: signedOut]).runner) == .signedOut, "gh check: no login")
    check(G.check(gh: "/x/gh", run: FakeGH([user: octocat]).runner) == .ready(login: "octocat", starred: nil), "gh check: the starred check didn't answer: unknown")
    let none = FakeGH([:])
    check(G.check(gh: nil, run: none.runner) == .noGH && none.calls.isEmpty, "gh check: no gh, nothing is run")

    let star = FakeGH([putStar: G.Run(status: 0, out: "")])
    check(G.star(gh: "/x/gh", run: star.runner) && star.calls.count == 1 && star.calls[0].arguments == ["api", "-X", "PUT", "/user/starred/LumenJSN/Aris"] && star.calls[0].timeout == G.timeout,
          "gh star: one PUT on the repository's starred path, within the limit")
    check(!G.star(gh: "/x/gh", run: FakeGH([putStar: G.Run(status: 1, out: "", err: "HTTP 401")]).runner) && !G.star(gh: nil, run: FakeGH([:]).runner),
          "gh star: a refused PUT or no gh is no star")

    check(G.ask(request: ["do": "check"]) == .check && G.ask(request: ["do": "star"]) == .star && G.ask(request: ["do": "unstar"]) == nil && G.ask(request: [:]) == nil,
          "POST /github-star: only check and star are asked")
    // The helper's whole answer, as the app reads it.
    let checked = FakeGH([user: octocat, isStarred: no404])
    let answer = G.answer(.check, environment: ["PATH": "/usr/bin"], run: checked.runner, executable: { $0 == "/opt/homebrew/bin/gh" })
    check(ArisStarCard.checked(wire(answer)) == .ask(login: "octocat") && !checked.starred, "POST /github-star check → the card offers the star as @octocat")
    let starring = FakeGH([putStar: G.Run(status: 0, out: "")])
    check(ArisStarCard.starred(wire(G.answer(.star, environment: [:], run: starring.runner, executable: { $0 == "/usr/local/bin/gh" }))) == .done && starring.starred,
          "POST /github-star star → starred")
    check(wire(G.reply(.ready(login: "a", starred: nil)))?["starred"] == nil && wire(G.reply(.noGH))?["gh"] as? String == "missing"
          && wire(G.reply(.signedOut))?["gh"] as? String == "signedOut", "POST /github-star: \"starred\" is left out when GitHub's answer was neither")
}

// MARK: - Never asked again

private func starCardSettledTests() {
    typealias C = ArisStarCard
    check(C.settledKey == "arisStarCardSettled", "settled: one key")
    check(C.opening(settled: nil) == .looking && C.opening(settled: "") == .looking && C.opening(settled: "something else") == .looking,
          "settled: never settled, the card shows and gh is asked")
    check(C.opening(settled: C.Settled.skipped.rawValue) == .gone && C.opening(settled: C.Settled.starred.rawValue) == .gone,
          "settled: skipped or starred before, the card never shows again")
    check(C.settles(.done) == .starred && C.settles(.thanks) == .starred, "settled: starred here, or before, is recorded")
    for state in [C.State.looking, .ask(login: "a"), .busy(login: "a"), .web, .gone] {
        check(C.settles(state) == nil, "settled: \(state) records nothing by itself")
    }
    let model = code(onboarding + "ArisStarCardModel.swift")
    let skip = part(model, from: "func skip()", to: "\n    }\n")
    check(skip.contains("defaults.set(ArisStarCard.Settled.skipped.rawValue, forKey: ArisStarCard.settledKey)") && skip.contains("state = .gone"),
          "settled: 건너뛰기 records it and folds the card away")
    check(model.contains("if let settled = ArisStarCard.settles(next) { defaults.set(settled.rawValue, forKey: ArisStarCard.settledKey) }"),
          "settled: a star (or one found) is recorded as it is set")
    check(model.contains("state = ArisStarCard.opening(settled: defaults.string(forKey: ArisStarCard.settledKey))")
          && part(model, from: "func begin()", to: "\n    }\n").contains("guard !asked, state == .looking else { return }"),
          "settled: a settled card starts gone and never asks gh")
}

// MARK: - Every failure is the browser's way

private func starCardFallbackTests() {
    typealias C = ArisStarCard
    typealias G = ArisGitHubStar
    check(C.checked(nil) == .web, "fallback: the helper not running or not answering in time → \"GitHub에서 별 남기기 ↗\"")
    check(C.checked(wire(G.reply(.noGH))) == .web, "fallback: no gh")
    check(C.checked(wire(G.reply(.signedOut))) == .web, "fallback: gh with no login")
    check(C.checked(wire(G.reply(.ready(login: "octocat", starred: nil)))) == .web, "fallback: GitHub's answer neither 204 nor 404")
    check(C.checked(wire(["gh": "ready", "login": "bad login", "starred": false])) == .web && C.checked(wire(["gh": "ready", "starred": false])) == .web
          && C.checked(wire(["error": "x"])) == .web, "fallback: an answer that isn't one")
    check(C.starred(nil) == .web && C.starred(wire(["starred": false])) == .web && C.starred(wire([:])) == .web, "fallback: a star that didn't go through")
    check(C.press(.web) == .open, "fallback: the button opens the repository's page in the browser")
}

// MARK: - Wiring

private func starCardWiringTests() {
    let window = code(onboarding + "ArisOnboardingWindow.swift")
    check(window.contains("case .done: ArisDonePage(guide: guide, card: guide.starCard, palette: palette).transition(.opacity)"), "wiring: the window draws 준비 끝 for its page")
    check(window.contains("if (guide.phase == .setup || guide.phase == .handoff) && guide.page != .done {"), "wiring: no 나중에 할게요 on the last page (nothing is left to put off)")
    let dictation = part(code(onboarding + "ArisOnboardingTryPages.swift"), from: "struct ArisDictationPage", to: "private var practice")
    check(dictation.contains("ArisGlassRect(title: ArisOnboardingCopy.finish) { guide.next() }") && !dictation.contains("ArisStarCard") && !dictation.contains("finish()"),
          "wiring: 받아쓰기's 마치기 goes on (guide.next), and no star card is on the dictation page")
    let done = code(onboarding + "ArisOnboardingDonePage.swift")
    check(done.contains("ArisGlassRect(title: ArisOnboardingCopy.doneStart) { guide.next() }") && done.contains(".onAppear { card.begin() }")
          && done.contains("if card.state != .gone {") && done.contains("ArisStarCardView(card: card, palette: palette, reduced: guide.reduced)"),
          "wiring: 준비 끝 asks gh as it shows, hides a settled card, and 시작하기 finishes (the guide's next on the last page)")
    let setup = code(onboarding + "ArisOnboardingGuide+Setup.swift")
    check(part(setup, from: "    func next() {", to: "\n    }\n").contains("finish()") && setup.contains("case .done: return ArisOnboardingCopy.doneTitle"),
          "wiring: the last page's button finishes; the notch's line on 준비 끝 is its heading")
    let model = code(onboarding + "ArisStarCardModel.swift")
    check(model.components(separatedBy: "actions.star()").count == 2 && part(model, from: "func press()", to: "\n    }\n").contains("actions.star()"),
          "wiring: the star is left only from the card's button")
    check(model.contains("ArisAgentClient.githubStar(\"check\")") && model.contains("ArisAgentClient.githubStar(\"star\")") && model.contains("NSWorkspace.shared.open($0)"),
          "wiring: gh through the helper; the browser's way opens the default browser")
    let agent = code("ArisAgent/main.swift")
    let route = part(agent, from: "case \"/github-star\":", to: "case \"/maps\":")
    check(route.contains("guard isAppItself(object, on: connection, question: \"github-star\") else { return }") && route.contains("DispatchQueue.global"),
          "wiring: only the app itself may ask the helper, and gh runs off the helper's main queue")
    let gh = code("ArisAgent/ArisGitHubStar.swift")
    check(!gh.contains("auth token") && !gh.contains("GH_TOKEN") && !gh.contains("hosts.yml") && !gh.contains("print(") && !gh.lowercased().contains("log."),
          "wiring: no token is read or printed, and nothing gh says is logged")
    let view = code(onboarding + "ArisStarCardView.swift") + done
    check(!view.contains("repeatForever") && view.contains("timingCurve(0.23, 1, 0.32, 1"), "wiring: nothing pulses; the motion is the mockup's ease-out")
    check(view.contains("if reduced {") && view.contains("reduced ? .opacity : .numericText"), "wiring: Reduce Motion keeps only opacity changes")
}
