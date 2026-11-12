// Tests for security review 4, M3: who macOS charges is decided by code identity, never by a path
// (ArisOrigin+Signature), and the start check is made again before a grant is used by a command that has been waiting
// (ArisOrigin+Recheck). And M1, the rest: neither program runs from a bundle that no longer verifies (ArisOrigin+Seal).
// The facts are the measured shapes (qa/design-1111/one-row-experiment.md, U1–U2).
// Called from runSecFix4Tests(); uses main.swift's check().
import Foundation
import Security

func secFix4IdentityTests() {
    secFix4IdentityRuleTests()
    secFix4ChargedTests()
    secFix4RecheckTests()
    secFix4SealTests()
    secFix4PeerTests()
}

private let identityRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
private func identityCode(_ path: String) -> String {
    ((try? String(contentsOf: identityRoot.appendingPathComponent(path), encoding: .utf8)) ?? "").components(separatedBy: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
}

private func secFix4IdentityRuleTests() {
    typealias O = ArisOrigin
    check(O.identity(validity: errSecSuccess, kernelIdentifier: nil, sameUser: true) == .aris, "sec4 M3: a process signed as one of Aris's programs by Aris's team is Aris")
    check(O.identity(validity: errSecCSReqFailed, kernelIdentifier: nil, sameUser: true) == .another, "sec4 M3: a process with someone else's valid signature (Terminal) is another program")
    check(O.identity(validity: errSecCSStaticCodeChanged, kernelIdentifier: "com.googlecode.iterm2", sameUser: true) == .another
            && O.identity(validity: errSecCSSignatureFailed, kernelIdentifier: "com.apple.Terminal", sameUser: true) == .another,
          "sec4 M3: a terminal that was updated while it runs (its file no longer matches) is still another program: the kernel names its identifier")
    for own in O.arisIdentifiers {
        check(O.identity(validity: errSecCSStaticCodeChanged, kernelIdentifier: own, sameUser: true) == .unknown,
              "sec4 M3: a process the kernel knows as \(own) whose file changed under it (an update of Aris while it runs) is never “another program”")
    }
    check(O.identity(validity: errSecCSUnsigned, kernelIdentifier: nil, sameUser: true) == .unknown && O.identity(validity: errSecCSStaticCodeChanged, kernelIdentifier: "", sameUser: true) == .unknown,
          "sec4 M3: a process whose signature can't be checked and that the kernel names nothing for is unknown")
    check(O.identity(validity: nil, kernelIdentifier: nil, sameUser: false) == .another, "sec4 M3: another user's process (root's sshd for a remote login) is another program")
    check(O.identity(validity: nil, kernelIdentifier: nil, sameUser: true) == .unknown && O.identity(validity: nil, kernelIdentifier: nil, sameUser: nil) == .unknown
            && O.identity(validity: nil, kernelIdentifier: "com.apple.Terminal", sameUser: true) == .unknown,
          "sec4 M3: this user's process that can't be asked, or one that is gone, is unknown")
    check(Set(O.arisIdentifiers) == ["com.lumenjsn.aris", "com.lumenjsn.aris.XPCHelper", "com.lumenjsn.aris.aris-agent", "com.lumenjsn.aris.aris-tools"],
          "sec4 M3: Aris's identifiers are its four programs'")
    let team = "ABCDE12345"
    check(O.requirement(identifiers: ["com.lumenjsn.aris"], team: team) == ArisXPCTrust.requirement(peer: "com.lumenjsn.aris", team: team)
            && O.requirement(identifiers: ["a.b", "c.d"], team: team) == "(identifier \"a.b\" or identifier \"c.d\") and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
            && O.requirement(identifiers: ["a.b", "c.d"], team: nil) == "(identifier \"a.b\" or identifier \"c.d\")",
          "sec4 M3: the requirement is “one of the identifiers, signed by this build's own team” (an ad-hoc build: the identifiers alone)")
    check(O.requirement(identifiers: ["a\" or anchor apple or identifier \"b"], team: team) == "never" && O.requirement(identifiers: [], team: team) == "never"
            && O.requirement(identifiers: ["a.b", "x\"y"], team: "evil\" or \"") == "identifier \"a.b\"",
          "sec4 M3: nothing that isn't a plain identifier or team id is ever spliced into a requirement")
    var requirement: SecRequirement?
    check(SecRequirementCreateWithString(O.requirement(identifiers: O.arisIdentifiers, team: team) as CFString, [], &requirement) == errSecSuccess
            && SecRequirementCreateWithString(O.requirement(identifiers: O.arisIdentifiers, team: nil) as CFString, [], &requirement) == errSecSuccess
            && SecRequirementCreateWithString(O.requirement(identifiers: [], team: nil) as CFString, [], &requirement) == errSecSuccess,
          "sec4 M3: macOS reads every requirement Aris writes")
    // This very process is not Aris (a test binary), launchd is root's, and nothing has pid 0.
    check(O.identity(of: getpid()) != .aris && O.identity(of: 1) == .another && O.identity(of: pid_t.max) == .unknown && !O.isSigned(getpid(), as: O.arisIdentifiers, team: team),
          "sec4 M3: asked for real, the test's own process is not Aris, launchd is another user's program and a pid nothing has is nobody")
}

private func secFix4ChargedTests() {
    typealias O = ArisOrigin
    let app = "/Applications/Aris.app", agent = app + "/Contents/MacOS/aris-agent", tools = app + "/Contents/MacOS/aris-tools"
    func facts(responsible: pid_t? = 300, program: String?, identity: O.Identity, vouchedBy: pid_t? = nil) -> O.Facts {
        O.Facts(me: 900, program: tools, responsible: responsible, responsibleProgram: program, responsibleIdentity: identity,
                job: O.Job(pid: 500, program: agent), launchdAnswered: true, signedAsAgent: [500], vouchedBy: vouchedBy, looksLikeJob: false)
    }
    let terminal = "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
    check(!O.chargedToApp(facts(program: terminal, identity: .another)) && O.mayRun(facts(program: terminal, identity: .another)),
          "sec4 M3: started from Terminal, macOS charges Terminal: the tool runs on Terminal's own permissions, with no question to the helper")
    let copy = "/Users/kim/c/Aris.app/Contents/MacOS/Aris"
    check(O.chargedToApp(facts(program: copy, identity: .aris)) && !O.mayRun(facts(program: copy, identity: .aris)),
          "sec4 M3: a copy of Aris elsewhere on the disk as the responsible process is Aris to macOS (U1c), so the tool needs the helper's yes; by its path it was “another program” and ran unchecked")
    check(O.mayRun(facts(program: copy, identity: .aris, vouchedBy: 500)), "sec4 M3: with the helper's yes it runs, as any tool charged to Aris does")
    check(!O.mayRun(facts(program: app + "/Contents/MacOS/Aris", identity: .aris)) && !O.mayRun(facts(program: agent, identity: .aris)),
          "sec4 M3: a launcher that became the genuine Aris or aris-agent by exec (U2: its path then shows the genuine program) gives the tool nothing without the helper's yes")
    check(!O.chargedToApp(facts(program: app + "/Contents/Helpers/launcher", identity: .another)),
          "sec4 M3: a foreign program planted inside Aris.app is not Aris (U1: macOS charges it to itself, with no grants); by its path it counted as the app")
    check(O.chargedToApp(facts(program: terminal, identity: .unknown)) && !O.mayRun(facts(program: terminal, identity: .unknown)),
          "sec4 M3: when the responsible process can't be told, nothing runs on a guess from its path")
    check(O.chargedToApp(facts(responsible: nil, program: nil, identity: .another)) && O.chargedToApp(facts(responsible: 900, program: tools, identity: .another)),
          "sec4 M3: a tool that is responsible for itself (a launchd job, a start that disclaimed responsibility), or whose responsible process is not known, is charged to Aris")
    let origin = identityCode("ArisAgent/ArisOrigin.swift")
    check(origin.contains("if let responsible, responsible != me { facts.responsibleIdentity = identity(of: responsible) }")
            && origin.contains("guard let responsible = facts.responsible, responsible != facts.me else { return true }\n        return facts.responsibleIdentity != .another"),
          "sec4 M3: wiring: who is charged is read from the responsible process's signature; a path is compared only in the rule of the release before")
    let signature = identityCode("ArisAgent/ArisOrigin+Signature.swift")
    check(signature.contains("kSecGuestAttributeAudit: token") && !signature.contains("kSecGuestAttributePid") && !signature.contains("proc_pidpath"),
          "sec4 M3: wiring: the signature is asked of the process by its audit token, never by its pid or path alone")
}

private func secFix4RecheckTests() {
    typealias O = ArisOrigin
    check(!O.isStale(checkedAt: nil, now: 1_000) && !O.isStale(checkedAt: 10, now: 12.9) && !O.isStale(checkedAt: 10, now: 13) && O.isStale(checkedAt: 10, now: 13.1),
          "sec4 M3: a check is looked at again when it is more than \(Int(O.recheckAfter)) seconds old, and never before one was made")
    let app = "/Applications/Aris.app", tools = app + "/Contents/MacOS/aris-tools"
    func facts(_ identity: O.Identity) -> O.Facts {
        O.Facts(me: 900, program: tools, responsible: 300, responsibleProgram: "/x", responsibleIdentity: identity, job: nil, launchdAnswered: true, signedAsAgent: [], looksLikeJob: false)
    }
    var asked = 0
    O.disarmRecheck()
    check(O.stillMayRun(now: 50, facts: { asked += 1; return facts(.aris) }, enforcing: true) && asked == 0, "sec4 M3: aris-agent as the server, and the tests, are never looked at again (nothing was armed)")
    O.armRecheck(now: 100)
    check(O.stillMayRun(now: 102, facts: { asked += 1; return facts(.aris) }, enforcing: true) && asked == 0, "sec4 M3: within a few seconds of the start check a grant is used without another look")
    check(O.stillMayRun(now: 110, facts: { asked += 1; return facts(.another) }, enforcing: true) && asked == 1, "sec4 M3: a command that has been waiting is looked at again before it uses a grant; still Terminal's, it goes on")
    check(O.stillMayRun(now: 112, facts: { asked += 1; return facts(.aris) }, enforcing: true) && asked == 1, "sec4 M3: and that look is good for the next few seconds")
    check(!O.stillMayRun(now: 120, facts: { asked += 1; return facts(.aris) }, enforcing: true) && asked == 2,
          "sec4 M3: when the responsible process has meanwhile become Aris (the launcher exec'd it while the tool waited on its input), the grant is not used")
    check(!O.stillMayRun(now: 121, facts: { asked += 1; return facts(.aris) }, enforcing: true) && asked == 3, "sec4 M3: a refusal is not remembered as a pass")
    O.disarmRecheck()
    let main = identityCode("ArisTools/main.swift")
    check(main.contains("exit(1)\n}\nArisOrigin.armRecheck()") && main.components(separatedBy: "FileHandle.standardInput.readDataToEndOfFile()\n    ArisOrigin.refuseUnlessStillAllowed()").count == 3
            && !main.replacingOccurrences(of: "readDataToEndOfFile()\n    ArisOrigin.refuseUnlessStillAllowed()", with: "").contains("standardInput.read"),
          "sec4 M3: wiring: aris-tools arms the second look once its start check passed, and takes it after every wait on its input")
    for (file, place) in [("ArisTools/ArisWindows.swift", "func requireAccessibility() {\n    ArisOrigin.refuseUnlessStillAllowed()"),
                          ("ArisTools/ArisBoundedRun.swift", "limit: TimeInterval?) -> Result? {\n        ArisOrigin.refuseUnlessStillAllowed()"),
                          ("ArisTools/ArisActivity.swift", "app: String) throws {\n        ArisOrigin.refuseUnlessStillAllowed()"),
                          ("ArisTools/ArisLocalStore.swift", "immutable: Bool) -> OpaquePointer? {\n        ArisOrigin.refuseUnlessStillAllowed()")] {
        check(identityCode(file).contains(place), "sec4 M3: wiring: \(file) takes the second look before it uses a grant")
    }
    check(identityCode("ArisAgent/main.swift").contains("if helperMode { ArisOrigin.armRecheck() }"), "sec4 M3: wiring: aris-agent's helper modes arm it too, the server never")
}

// MARK: - M1: the app must still be the app that was signed

private func secFix4SealTests() {
    typealias O = ArisOrigin
    let app = "/Applications/Aris.app", agent = app + "/Contents/MacOS/aris-agent", tools = app + "/Contents/MacOS/aris-tools"
    let light = O.sealChecks(app: app, program: tools, whole: false)
    check(light == [O.SealCheck(path: app, identifier: "com.lumenjsn.aris", flags: O.bundleSignatureFlags), O.SealCheck(path: tools, identifier: O.toolsSigningId, flags: O.programFlags)],
          "sec4 M1: aris-tools verifies the bundle's own signature (Aris's identifier) and its own program file (its identifier) at every start")
    let whole = O.sealChecks(app: app, program: agent, whole: true)
    check(whole == [O.SealCheck(path: app, identifier: "com.lumenjsn.aris", flags: O.wholeBundleFlags), O.SealCheck(path: agent, identifier: O.agentSigningId, flags: O.programFlags),
                    O.SealCheck(path: tools, identifier: O.toolsSigningId, flags: O.programFlags)],
          "sec4 M1: aris-agent as the server verifies the whole bundle and both programs, once per start")
    check(O.sealChecks(app: app, program: agent, whole: false) == [O.SealCheck(path: app, identifier: "com.lumenjsn.aris", flags: O.bundleSignatureFlags), O.SealCheck(path: agent, identifier: O.agentSigningId, flags: O.programFlags)],
          "sec4 M1: aris-agent's helper modes verify as a tool does")
    check(O.wholeBundleFlags & kSecCSStrictValidate != 0 && O.wholeBundleFlags & kSecCSCheckNestedCode != 0 && O.wholeBundleFlags & kSecCSDoNotValidateResources == 0
            && O.bundleSignatureFlags & kSecCSStrictValidate != 0 && O.programFlags & kSecCSStrictValidate != 0,
          "sec4 M1: every verification is strict; the whole one reads nested code and every sealed file")
    check(O.sealChecks(app: app, program: app + "/Contents/MacOS/Aris", whole: false).isEmpty && !O.sealHolds([], verify: { _ in true }),
          "sec4 M1: a program that is neither aris-agent nor aris-tools has no checks, and with none nothing holds")
    var asked: [String] = []
    check(O.sealHolds(light) { asked.append($0.path); return true } && asked == [app, tools], "sec4 M1: the seal holds when every check does")
    check(!O.sealHolds(light) { $0.path != app } && !O.sealHolds(light) { $0.path != tools } && !O.sealHolds(whole) { $0.path != tools },
          "sec4 M1: one failed check (the bundle re-assembled, the Info.plist changed, a program swapped) and it does not")
    check(O.staticValidity(O.SealCheck(path: "/nonexistent/Aris.app", identifier: "com.lumenjsn.aris", flags: O.bundleSignatureFlags), team: nil) != errSecSuccess,
          "sec4 M1: asked for real, a bundle that isn't there does not verify")
    func facts(program: String, me: pid_t, seal: Bool, identity: O.Identity = .aris) -> O.Facts {
        O.Facts(me: me, program: program, responsible: 500, responsibleProgram: agent, responsibleIdentity: identity, job: O.Job(pid: 500, program: agent), launchdAnswered: true,
                signedAsAgent: [500], vouchedBy: 500, looksLikeJob: true, sealIntact: seal)
    }
    check(O.mayRun(facts(program: tools, me: 900, seal: true)) && !O.mayRun(facts(program: tools, me: 900, seal: false)),
          "sec4 M1: a tool the helper vouched for still does not run from a bundle that no longer verifies")
    check(!O.mayRun(facts(program: tools, me: 900, seal: false, identity: .another)), "sec4 M1: nor when Terminal started it: a changed copy is refused whoever is charged")
    check(O.mayServe(facts(program: agent, me: 500, seal: true)) && !O.mayServe(facts(program: agent, me: 500, seal: false)) && !O.mayYetBeJob(facts(program: agent, me: 500, seal: false), enforcing: true),
          "sec4 M1: aris-agent does not serve from such a bundle, and stops at once")
    check(O.mayRun(O.Facts(me: 900, program: "/Users/kim/dev/out/aris-tools", responsible: 1, responsibleProgram: nil, job: nil, launchdAnswered: false, signedAsAgent: [], looksLikeJob: false, sealIntact: false)),
          "sec4 M1: a loose copy outside any app (a developer's build, the tests) has no bundle to verify and runs as before")
    check(O.refusal(facts(program: tools, me: 900, seal: false)) == O.refusedChangedLine && O.refusal(facts(program: tools, me: 900, seal: true)) == O.refusedLine
            && O.refusedChangedLine.contains("changed after it was signed") && O.refusedLine.contains("not started by Aris"),
          "sec4 M1: the refusal says which it was: a changed copy of Aris, or a tool Aris did not start")
    let origin = identityCode("ArisAgent/ArisOrigin.swift")
    // (final 2: the tool no longer verifies the bundle before it asks the helper: the real helper, which verified the
    // whole bundle at its own start, may say it stands; the rule itself still refuses without an intact seal.)
    check(origin.contains("facts.sealIntact = facts.bundleIsAris && sealIntact(app: app, program: facts.program, whole: serving, helpersWord: sealedByHelper && !serving)")
            && origin.contains("guard facts.bundleIsAris, facts.sealIntact else { return false }"),
          "sec4 M1: wiring: the seal is verified for both programs (by the program itself, or by the real helper for the tool it started), and nothing runs without it")
    let seal = identityCode("ArisAgent/ArisOrigin+Seal.swift")
    check(seal.contains("if let known = sealVerdicts[key] { return known }") && seal.contains("SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: check.flags), wanted)"),
          "sec4 M1: wiring: verified with SecStaticCodeCheckValidity against Aris's own team and identifier, once per process")
    check(identityCode("ArisTools/main.swift").contains("FileHandle.standardError.write(Data((ArisOrigin.refusal(startFacts) + \"\\n\").utf8))"), "sec4 M1: wiring: aris-tools says that line")
}

// MARK: - M5: the app is known by its signature

private func secFix4PeerTests() {
    typealias O = ArisOrigin
    let app = "/Applications/Aris.app/Contents/MacOS/Aris"
    check(ArisPeer.signedId(isSignedAsApp: true) == "com.lumenjsn.aris" && ArisPeer.signedId(isSignedAsApp: false) == nil,
          "sec4 M5: a process counts as com.lumenjsn.aris only when its own code signature says so")
    let claimed = ArisPeer.countedBundleId(reported: ArisPeer.signedId(isSignedAsApp: false), program: "/Users/kim/Fake.app/Contents/MacOS/Aris")
    check(ArisTeammateGate.appCheck(alive: true, bundleId: claimed, ownsSocket: true, sameConnection: false) == .bundle,
          "sec4 M5: a bundle that only calls itself com.lumenjsn.aris, alive and holding the connection and the token, is not the app: its yes to a card is refused")
    let genuine = ArisPeer.countedBundleId(reported: ArisPeer.signedId(isSignedAsApp: true), program: app)
    check(ArisTeammateGate.appCheck(alive: true, bundleId: genuine, ownsSocket: true, sameConnection: false) == nil
            && ArisTeammateGate.appCheck(alive: true, bundleId: ArisPeer.countedBundleId(reported: ArisPeer.signedId(isSignedAsApp: true), program: "/Users/kim/c/Aris.app/Contents/MacOS/Aris"),
                                         ownsSocket: true, sameConnection: false) == nil,
          "sec4 M5: the app signed as Aris is the app, wherever its file is")
    for helper in ["aris-agent", "aris-tools", "ArisXPCHelper"] {
        check(ArisPeer.countedBundleId(reported: ArisPeer.signedId(isSignedAsApp: true), program: "/Applications/Aris.app/Contents/MacOS/\(helper)") == nil,
              "sec4 M5: \(helper) still never counts as the app")
    }
    check(ArisPeer.bundleId(pid: getpid()) == nil && ArisPeer.bundleId(pid: 1) == nil, "sec4 M5: asked for real, the test's own process and launchd are not the app")
    let peer = identityCode("ArisAgent/ArisPeer.swift")
    check(ArisPeer.appId(isSignedAsApp: true, listed: nil, enforcing: true) == "com.lumenjsn.aris" && ArisPeer.appId(isSignedAsApp: false, listed: "com.lumenjsn.aris", enforcing: true) == nil
            && ArisPeer.appId(isSignedAsApp: false, listed: "com.lumenjsn.aris", enforcing: false) == "com.lumenjsn.aris" && ArisPeer.appId(isSignedAsApp: false, listed: "com.apple.Terminal", enforcing: false) == "com.apple.Terminal",
          "sec4 M5: enforced, only the signature counts; until then what macOS's list of running apps says still does, as before")
    check(peer.contains("let signed = ArisOrigin.isSigned(pid, as: [appBundleId])") && peer.contains("let listed = signed || ArisRollout.enforcing ? nil : NSRunningApplication(processIdentifier: pid)?.bundleIdentifier")
            && peer.contains("if !signed, counted == appBundleId { ArisRollout.wouldRefuse("),
          "sec4 M5: wiring: the peer check asks the process's signature by its audit token; the list of running apps is asked only while the new checks are not enforced, and that is written down")
    check(!identityCode("ArisAgent/ArisTeammateGate.swift").contains("NSRunningApplication(processIdentifier"), "sec4 M5: wiring: nor does the teammate gate")
    check(O.requirement(identifiers: [ArisPeer.appBundleId], team: "ABCDE12345") == "identifier \"com.lumenjsn.aris\" and anchor apple generic and certificate leaf[subject.OU] = \"ABCDE12345\"",
          "sec4 M5: the app's requirement is its identifier, signed by the helper's own team")
}
