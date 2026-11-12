//
//  ArisOrigin+Recheck.swift
//  aris-agent and aris-tools
//
//  The start check, looked at again (security review 4, M3). A tool is checked when it starts; a command that then
//  waits (on its input, on a slow step) could be started by one program and still be running when the process macOS
//  holds responsible for it has become another. So right before a grant is first used (a key press, a capture, another
//  app's data, a script sent to an app) the check is made again when more than a few seconds have passed since the
//  last one. Within those seconds nothing is asked again, so an ordinary command pays for one check.
//
//  Only a program that passed `mayRun` at its start arms this (aris-tools, aris-agent's helper modes); aris-agent as
//  the server and the tests never do, and for them every call here is nothing.
//

import Foundation

extension ArisOrigin {
    /// How old the last check may be when a grant is used.
    static let recheckAfter: TimeInterval = 3

    private static let recheckLock = NSLock()
    /// When the last check passed (time since boot); nil until armed.
    nonisolated(unsafe) private static var checkedAt: TimeInterval?

    /// Whether a check made at `checkedAt` is too old at `now` (never, when none was armed).
    static func isStale(checkedAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard let checkedAt else { return false }
        return now - checkedAt > recheckAfter
    }

    /// Says the start check has just passed.
    static func armRecheck(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        recheckLock.withLock { checkedAt = now }
    }

    /// Whether this program may still use Aris's permissions: true while the last check is fresh, else what a new
    /// look at the same facts says (a pass is remembered, a refusal is final for the caller).
    static func stillMayRun(now: TimeInterval = ProcessInfo.processInfo.systemUptime, facts: () -> Facts = { ArisOrigin.facts() },
                            enforcing: Bool = ArisRollout.enforcing) -> Bool {
        recheckLock.withLock {
            guard isStale(checkedAt: checkedAt, now: now) else { return true }
            // With the rollout audit on these facts are all asked (ArisOrigin.gathersAll), so the second look's line
            // can be written; without it the look gathers what the proven rule reads, and only that rule speaks.
            let found = facts()
            let made = decision(found, serving: false, enforcing: enforcing)
            if made.wouldRefuse { ArisRollout.wouldRefuse("a tool that had been waiting, at its second look") }
            if ArisRollout.isAuditing, found.thorough {
                ArisRollout.evaluated(evaluatedLine(found, serving: false, allowed: made.allowed, wouldRefuse: made.wouldRefuse, secondLook: true))
            }
            guard made.allowed else { return false }
            checkedAt = now
            return true
        }
    }

    /// Right before a grant is used: one plain line and the end of the program when it may no longer run.
    static func refuseUnlessStillAllowed() {
        guard !stillMayRun() else { return }
        FileHandle.standardError.write(Data((refusedLine + "\n").utf8))
        exit(1)
    }

    /// The home folder in this program's environment, set to the account's own (getpwuid) once the start check has
    /// passed inside an app (security review 4, L5): whoever started the program may have put another HOME there, and
    /// what it starts would take its folders from it. (The folders this program builds itself come from the account,
    /// not from HOME, and a redirected CFFIXED_USER_HOME is refused at the start.) A loose copy keeps what it was given.
    static func settledHome(program: String, account: String?) -> String? {
        guard case .expected = place(ofProgram: program), let account, account.hasPrefix("/") else { return nil }
        return account
    }

    static func settleHome() {
        let account = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) }
        if let home = settledHome(program: program(of: getpid()) ?? "", account: account) { setenv("HOME", home, 1) }
    }

    /// For the tests: as before any check.
    static func disarmRecheck() {
        recheckLock.withLock { checkedAt = nil }
    }
}
