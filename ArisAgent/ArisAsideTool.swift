//
//  ArisAsideTool.swift
//  aris-agent
//
//  What `aris-tools aside "<brief>"` does once the agent knows whose turn it is, for every brain alike: the brains'
//  own calls (POST /aside-tool: Codex, the open and the sealed Claude, the API brain's helper) and agy's relay. Aside
//  missing: on a clean, heard turn, at most one card a turn whose 설치 opens the official download page (nothing is
//  installed), and a short line for the brain to say. A CLI not signed by Aside's team never runs. Otherwise the one
//  gate (ArisAside.risk) decides, the user's card when it asks (only the user answers it: no remembered yes, standing permission
//  or judge), an audit line either way, the conversation outside text before Aside runs (its answer is the web's), the
//  brief in the notch while it runs, one Aside call at a time in a turn. Blocks while a card waits or Aside works. The
//  process, the opener and the user's memory are handed in, so the tests run it with fakes.
//

import AppKit
import Darwin
import Foundation

/// A turn as the Aside tool sees it: the services' view, a key naming this turn, and the turn told when Aside starts
/// or a sign-in code waits (minutes, so it waits) and when that ends.
protocol ArisAsideTurn: ArisMCPTurn {
    /// A new key every turn: one Aside call at a time, one install or sign-in card.
    var asideTurnKey: String { get }
    /// The turn is still under way: a sign-in waiting for its code stops once it isn't (follow-up 2).
    var asideLive: Bool { get }
    func asideRunning(_ brief: String)
    /// A sign-in code waits for the user's approval: the turn waits too, and the notch shows `status` (the code).
    func asideWaiting(_ status: String)
    func asideEnded()
    /// The turn's request names one of Aris's own schedules by its title (ArisOwnData.namesSchedule): Aside gets nothing
    /// of such a turn, however a brief is worded.
    var asideOwnData: Bool { get }
    /// The turn's request is English: Aside's cards and lines are too (audit desk-11); else Korean.
    var asideEnglish: Bool { get }
}

extension ArisAsideTurn {
    var asideOwnData: Bool { false }
    var asideEnglish: Bool { false }
}

/// What the tool reaches outside itself.
struct ArisAsideDeps {
    /// Where Aside is and whether it's signed in (ArisAsideReadiness).
    let locate: () -> ArisAside.Found
    /// Runs the CLI: path, arguments, environment, time limit.
    let run: (String, [String], [String: String], TimeInterval) -> ArisSkillProcessResult
    /// Opens a page in the default browser.
    let open: (URL) -> Bool
    let environment: [String: String]
    /// The user's memories and recent day notes, which a brief must not carry off without their yes.
    var privateTexts: () -> [String] = { [] }
    /// The signature check run again right before Aside starts (the file could change during a card's wait).
    var verify: (String) -> Bool = ArisAside.isSignedByAside
    /// Aside's own app is installed here (signed by its team) though no CLI was found: no download is offered then.
    var hasApp: () -> Bool = { false }
    /// Forgets the cached readiness (after a failed exec or a sign-in).
    var forget: () -> Void = {}
    /// Runs `aside login --device-code` (path, environment, limit), handing each line it prints to the callback, until
    /// it ends, its limit, or `stop` says the turn is over.
    var login: (String, [String: String], TimeInterval, @escaping (String) -> Void, @escaping () -> Bool) -> ArisSkillProcessResult = { _, _, _, _, _ in
        ArisSkillProcessResult(status: -1, stdout: "", stderr: "", timedOut: false)
    }
    /// `aside account status` (read-only, plain text), to confirm a sign-in.
    var accountStatus: (String) -> ArisSkillProcessResult = { _ in ArisSkillProcessResult(status: -1, stdout: "", stderr: "", timedOut: false) }
    /// Whether a brief is about Aris's own data (ArisOwnData; live: one of Aris's schedules named in it counts too).
    var ownData: (String) -> Bool = { ArisOwnData.mentions($0) }

    static var live: ArisAsideDeps {
        ArisAsideDeps(locate: { ArisAsideReadiness.shared.check() },
                      run: { path, arguments, environment, limit in
                          ArisSkillProcess.run(path, arguments, environment: environment, timeout: limit, maxOutput: 512 * 1_024)
                      },
                      open: { url in NSWorkspace.shared.open(url) },
                      environment: ProcessInfo.processInfo.environment,
                      privateTexts: {
                          let store = ArisMemoryStore.live
                          let days = (0..<ArisMemoryStore.noteDays).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
                              .map { ArisMemoryText.day($0) }
                          return store.all().flatMap { [$0.text, $0.subject] } + days.flatMap { store.notes(day: $0) }
                      },
                      hasApp: { ArisAside.hasLocalHost(home: FileManager.default.homeDirectoryForCurrentUser.path) },
                      forget: { ArisAsideReadiness.shared.forget() },
                      login: { path, environment, limit, line, stop in
                          ArisAsideLogin.run(path, environment: environment, limit: limit, line: line, stop: stop)
                      },
                      accountStatus: { ArisAsideReadiness.accountStatus($0) },
                      ownData: { ArisOwnData.mentions($0, scheduleNames: ArisOwnDataTurn.scheduleNames(home: FileManager.default.homeDirectoryForCurrentUser.path)) })
    }
}

/// Whether Aside is usable, cached for ArisAside.readinessTTL: the signed CLI, then `aside account status` (read-only,
/// plain text) showing the active account signed in. The host isn't checked: a local Aside.app is the simple case,
/// and with none exec says itself that no host serves.
final class ArisAsideReadiness: @unchecked Sendable {
    static let shared = ArisAsideReadiness()
    private let lock = NSLock()
    private var cached: (found: ArisAside.Found, at: Date)?

    func check(now: Date = Date()) -> ArisAside.Found {
        if let cached = lock.withLock({ cached }), now.timeIntervalSince(cached.at) < ArisAside.readinessTTL { return cached.found }
        let found = Self.probe(ArisAside.locate(home: FileManager.default.homeDirectoryForCurrentUser.path), account: Self.accountStatus)
        // Only a usable Aside is remembered: a missing or signed-out one is checked again next time.
        if case .ready = found { lock.withLock { cached = (found, now) } }
        return found
    }

    func forget() { lock.withLock { cached = nil } }

    /// `aside account status`, plain text, no flag (its text is read, never stored).
    static func accountStatus(_ path: String) -> ArisSkillProcessResult {
        ArisSkillProcess.run(path, ArisAside.accountStatusArguments, environment: ArisAside.environment(ProcessInfo.processInfo.environment),
                             timeout: 20, maxOutput: 64 * 1_024)
    }

    /// The CLI's state, signed in or not (`account` runs `aside account status`; its text is read, never stored).
    static func probe(_ found: ArisAside.Found, account: (String) -> ArisSkillProcessResult) -> ArisAside.Found {
        guard case .ready(let path) = found else { return found }
        let result = account(path)
        return result.status == 0 && !result.timedOut && ArisAside.signedIn(accountStatus: result.stdout) ? .ready(path) : .signedOut(path)
    }
}

/// `aside login --device-code` in a process group of its own, its output read as it comes (the code shows before it
/// waits). It ends on its own, at its limit, or when `stop` says the turn is over; then the whole group gets SIGTERM and,
/// a moment later, SIGKILL (follow-up 2), so nothing it started keeps waiting.
enum ArisAsideLogin {
    static func run(_ path: String, environment: [String: String], limit: TimeInterval, line: @escaping (String) -> Void,
                    stop: @escaping () -> Bool, arguments: [String] = ArisAside.loginArguments) -> ArisSkillProcessResult {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return failed }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 2)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Its own group (pgid = its pid), and nothing else of the agent's open files.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let started = ArisChildren.spawn(&pid, path, &actions, &attributes, argv, envp)
        close(fds[1])
        guard started == 0 else { close(fds[0]); return failed }
        let lock = NSLock()
        nonisolated(unsafe) var printed = ""
        let reading = DispatchSemaphore(value: 0)
        let readEnd = fds[0]
        DispatchQueue.global().async {
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = read(readEnd, &buffer, buffer.count)
                if count <= 0 { break }
                let text = String(decoding: buffer[0..<count], as: UTF8.self)
                lock.withLock { printed = String((printed + text).suffix(8_192)) }
                line(text)
            }
            close(readEnd)
            reading.signal()
        }
        let deadline = Date().addingTimeInterval(limit)
        var status: Int32 = 0
        var ended = false
        while Date() < deadline, !stop() {
            if waitpid(pid, &status, WNOHANG) == pid { ended = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        if !ended {
            endGroup(pid, status: &status)
            _ = reading.wait(timeout: .now() + 2)
            return ArisSkillProcessResult(status: -1, stdout: lock.withLock { printed }, stderr: "", timedOut: true)
        }
        _ = reading.wait(timeout: .now() + 2)
        let exited = status & 0x7f == 0
        return ArisSkillProcessResult(status: exited ? (status >> 8) & 0xff : 128 + (status & 0x7f), stdout: lock.withLock { printed }, stderr: "",
                                      timedOut: false)
    }

    /// SIGTERM to the group, a short grace, then SIGKILL to the group; the child reaped.
    private static func endGroup(_ pid: pid_t, status: inout Int32) {
        kill(-pid, SIGTERM)
        let grace = Date().addingTimeInterval(2)
        var reaped = false
        while Date() < grace {
            if waitpid(pid, &status, WNOHANG) == pid { reaped = true; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        kill(-pid, SIGKILL)
        if !reaped { _ = waitpid(pid, &status, 0) }
    }

    private static let failed = ArisSkillProcessResult(status: -1, stdout: "", stderr: "couldn't start", timedOut: false)
}

enum ArisAsideTool {
    /// How long a card may wait (a background job's waits ten minutes, a conversation's a minute: the runner's).
    static let cardWait: TimeInterval = 900

    /// The turns with an Aside call under way, and the turns that showed the install card (the last few).
    private static let lock = NSLock()
    nonisolated(unsafe) private static var running: Set<String> = []
    nonisolated(unsafe) private static var installShown: [String] = []
    nonisolated(unsafe) private static var loginShown: [String] = []

    /// One `aside "<brief>"` line of agy's aris-run block.
    static func relayed(_ words: [String], turn: ArisAsideTurn, critical: Bool, deps: ArisAsideDeps = .live) -> String {
        String(answer(words.dropFirst().joined(separator: " "), turn: turn, critical: critical, deps: deps).output.prefix(ArisAgyRelay.maxResult * 2))
    }

    /// Blocks (a card may wait for the user, and Aside takes minutes).
    static func answer(_ raw: String, turn: ArisAsideTurn, critical: Bool, deps: ArisAsideDeps = .live) -> ArisMCPOutcome {
        let brief: String
        switch ArisAside.brief(raw) {
        case .failure(let why): return .failed(why.text)
        case .success(let made): brief = made
        }
        let action = "aside: " + String(brief.prefix(500))
        // Aris's own schedules, to-dos, memory, teammates, timers and settings are never Aside's, in a conversation or a
        // job, with or without a card (QA BUG-60: a job asked Aside to find and delete Aris's own schedule on websites).
        if turn.asideOwnData || deps.ownData(brief) {
            turn.audit(["answer": "refused (Aris's own data)", "action": action, "risk": "never", "brain": turn.brainName])
            return .failed(ArisAside.ownDataLine)
        }
        let path: String
        switch deps.locate() {
        case .missing: return missing(action, turn: turn, deps: deps)
        case .untrusted(let found):
            turn.audit(["answer": "refused (unsigned CLI)", "action": action, "risk": "never", "brain": turn.brainName, "note": found])
            return .failed(ArisAside.untrustedLine(english: turn.asideEnglish))
        case .signedOut(let found): return signIn(found, action: action, turn: turn, deps: deps)
        case .ready(let found): path = found
        }
        // One Aside call at a time in a turn (M4): a second waits for the first's answer.
        let key = turn.asideTurnKey
        guard lock.withLock({ running.insert(key).inserted }) else {
            turn.audit(["answer": "refused (one already running)", "action": action, "brain": turn.brainName])
            return .failed(ArisAside.busy)
        }
        defer { lock.withLock { _ = running.remove(key) } }
        let risk = ArisAside.risk(brief: brief, taint: turn.taint, screen: turn.screen, handsFree: turn.handsFree, critical: critical,
                                  privateTexts: deps.privateTexts())
        if risk != .auto {
            let preview = brief.count > ArisAside.cardPreview ? String(brief.prefix(ArisAside.cardPreview)) + "…" : brief
            let card = ArisMCPCard(title: ArisAside.cardTitle(english: turn.asideEnglish), detail: preview, full: preview == brief ? nil : brief, fields: [])
            // A card nobody answered is told as that, never as the user's no (audit desk-12).
            let answer = ask(card, turn: turn)
            guard case .yes = answer else {
                turn.audit(["answer": answer == .unanswered ? "unanswered" : "no", "action": action, "risk": risk.rawValue, "brain": turn.brainName])
                return .failed(ArisAside.notYesLine(answer))
            }
        }
        // The CLI may have been swapped while the card waited: its signature again, right before it runs.
        guard deps.verify(path) else {
            turn.audit(["answer": "refused (unsigned CLI)", "action": action, "risk": "never", "brain": turn.brainName, "note": path])
            return .failed(ArisAside.untrustedLine(english: turn.asideEnglish))
        }
        turn.audit(["answer": risk == .auto ? "auto" : "yes", "action": action, "risk": risk.rawValue, "brain": turn.brainName])
        // What Aside brings back was read from websites: outside text from here on, before it runs.
        turn.takeOutsideText()
        turn.asideRunning(brief)
        defer { turn.asideEnded() }
        let result = deps.run(path, ArisAside.arguments(brief: brief), ArisAside.environment(deps.environment), ArisAside.runLimit)
        // A failed run may mean Aside is no longer ready (signed out, no host): checked again next time.
        if !result.ok { deps.forget() }
        return ArisAside.output(status: result.status, stdout: result.stdout, stderr: result.stderr, timedOut: result.timedOut)
    }

    /// A card about setting Aside up may go up: on a clean, heard turn only (never after outside text, the screen or
    /// hands-free: L7), and once a turn for each kind.
    private static func mayShow(_ shown: inout [String], turn: ArisAsideTurn) -> Bool {
        guard turn.taint == .none && !turn.screen && !turn.handsFree else { return false }
        let key = turn.asideTurnKey
        guard !shown.contains(key) else { return false }
        shown = Array((shown + [key]).suffix(64))
        return true
    }

    /// Aside isn't installed: the line to say, and (L7) the 설치 card, whose yes opens the download page and nothing more.
    private static func missing(_ action: String, turn: ArisAsideTurn, deps: ArisAsideDeps) -> ArisMCPOutcome {
        // The app is here and only its command-line tool is missing: said as that, with no install card.
        if deps.hasApp() {
            turn.audit(["answer": "CLI missing (the app is installed)", "action": action, "risk": "missing", "brain": turn.brainName])
            return .failed(ArisAside.cliMissingOutput(english: turn.asideEnglish))
        }
        let first = lock.withLock { mayShow(&installShown, turn: turn) }
        let yes = first && isYes(ask(ArisAside.missingCard(english: turn.asideEnglish), turn: turn))
        let opened = yes && deps.open(ArisAside.downloadPage)
        let answer = opened ? "download page opened" : yes ? "download page didn't open" : first ? "missing" : "missing (no card)"
        turn.audit(["answer": answer, "action": action, "risk": "missing", "brain": turn.brainName])
        return .failed(ArisAside.missingOutput(opened: opened, english: turn.asideEnglish))
    }

    /// The CLI isn't signed in: the "Aside 로그인" card (L7's rules); its yes runs `aside login --device-code` (never a
    /// password), shows the code in the notch and waits until the user approves it in Aside or it expires. Aris never reads
    /// or keeps a credential, and never touches Aside's approval itself.
    private static func signIn(_ path: String, action: String, turn: ArisAsideTurn, deps: ArisAsideDeps) -> ArisMCPOutcome {
        let first = lock.withLock { mayShow(&loginShown, turn: turn) }
        guard first, isYes(ask(ArisAside.loginCard(english: turn.asideEnglish), turn: turn)), deps.verify(path) else {
            turn.audit(["answer": first ? "sign-in declined" : "signed out", "action": action, "risk": "signed out", "brain": turn.brainName])
            return .failed(ArisAside.signedOutLine(english: turn.asideEnglish))
        }
        turn.asideWaiting(ArisAside.codeWaitingStatus(english: turn.asideEnglish))
        defer { turn.asideEnded() }
        let seen = ArisAsideCodeBox()
        let key = turn.asideTurnKey
        let result = deps.login(path, ArisAside.environment(deps.environment), ArisAside.loginLimit, { text in
            if let code = seen.add(text) { turn.asideWaiting(ArisAside.loginStatus(code, english: turn.asideEnglish)) }
        }, { !turn.asideLive || turn.asideTurnKey != key })
        deps.forget()
        // Its exit alone isn't trusted (follow-up 3): `account status` once more must show the account signed in.
        let approved = result.ok && ArisAsideReadiness.probe(.ready(path), account: deps.accountStatus) == .ready(path)
        turn.audit(["answer": approved ? "signed in" : result.timedOut ? "sign-in code expired" : "sign-in failed", "action": action,
                    "risk": "signed out", "brain": turn.brainName])
        let output = ArisAside.loginOutput(approved: approved, code: seen.code, timedOut: result.timedOut, english: turn.asideEnglish)
        return approved ? ArisMCPOutcome(status: 0, output: output) : .failed(output)
    }

    /// The user's answer on `card`: their yes or no, or unanswered when the card closed with none or the wait ran out.
    private static func ask(_ card: ArisMCPCard, turn: ArisAsideTurn, wait: TimeInterval = cardWait) -> ArisMCPAnswer {
        let done = DispatchSemaphore(value: 0)
        let box = ArisAsideAnswerBox()
        turn.ask(card) { answer in
            box.set(answer)
            done.signal()
        }
        return done.wait(timeout: .now() + wait) == .success ? box.value ?? .unanswered : .unanswered
    }

    private static func isYes(_ answer: ArisMCPAnswer) -> Bool {
        if case .yes = answer { return true }
        return false
    }
}

private final class ArisAsideAnswerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ArisMCPAnswer?
    func set(_ answer: ArisMCPAnswer) { lock.withLock { if stored == nil { stored = answer } } }
    var value: ArisMCPAnswer? { lock.withLock { stored } }
}

/// The sign-in's output as it comes, and its code once one can be told (handed on only the first time).
private final class ArisAsideCodeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private var found: String?
    var code: String? { lock.withLock { found } }
    func add(_ chunk: String) -> String? {
        lock.withLock {
            guard found == nil else { return nil }
            text = String((text + chunk).suffix(8_192))
            found = ArisAside.deviceCode(in: text)
            return found
        }
    }
}
