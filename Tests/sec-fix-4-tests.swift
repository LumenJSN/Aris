// Tests for the fourth security review (qa/audit-1110/SECURITY-REVIEW-4.md), the findings fixed on sec-fix-4.
// - M6: Aris's own app is protected exactly as ~/.config/aris is. The helper, its tools and the built-in skill moved
//   into Aris.app, and /Applications was in no never-list: a brain's edit, move or trash of them asked on an ordinary
//   card. Now it is refused outright, for every file tool and every way a brain names the place.
// - L4: two pins that left with the retired agent-row tests: the helper never types into Aris itself, and never
//   types without Accessibility.
// Everything runs on values made here; nothing is asked of macOS and no file is touched.
// Called from main.swift; uses its check(), risk() and shellRisk().
import Foundation

func runSecFix4Tests() {
    secFix4AppPlaceTests()
    secFix4GateTests()
    secFix4PinTests()
    secFix4OriginTests()
    secFix4VouchTests()
    secFix4IdentityTests()
    secFix4H1Tests()
    secFix4InstallTests()
    secFix4RolloutTests()
}

private let secFix4Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
private func secFix4Code(_ path: String) -> String {
    ((try? String(contentsOf: secFix4Root.appendingPathComponent(path), encoding: .utf8)) ?? "").components(separatedBy: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
}

private func secFix4AppPlaceTests() {
    typealias P = ArisProtectedPlaces
    let home = "/Users/p", own = "/Users/p/Applications/Aris.app"
    check(P.appPlaces(running: nil) == ["/Applications/Aris.app"] && P.appPlaces(running: own) == ["/Applications/Aris.app", own]
            && P.appPlaces(running: "/Applications/Aris.app") == ["/Applications/Aris.app"],
          "sec4 M6: Aris's app is protected where it is installed and where this program really runs from")
    let apps = P.appPlaces(running: own)
    for inside in ["/Applications/Aris.app", "/Applications/Aris.app/Contents/MacOS/aris-tools", "/Applications/Aris.app/Contents/MacOS/aris-agent",
                   "/Applications/Aris.app/Contents/Resources/skills/builtin/skill-creator/SKILL.md", "/Applications/Aris.app/Contents/Info.plist",
                   "/applications/ARIS.APP/Contents/MacOS/Aris", "/Applications/Aris.app/Contents/../Contents/MacOS/aris-tools", own + "/Contents/MacOS/aris-tools"] {
        check(P.inApp(inside, apps: apps) && P.blocks(inside, home: home, apps: apps) && P.blocksEdit(inside, home: home, apps: apps),
              "sec4 M6: \(inside) is inside Aris's app: never read from, written, moved or edited")
    }
    for outside in ["/Applications/Safari.app/Contents/MacOS/Safari", "/Applications/Aris.app.zip", "/Applications/Aris.application/x", "/Applications/Arisx.app/Contents/MacOS/x",
                    "/Users/p/Desktop/Aris.app/Contents/MacOS/aris-tools", "/Applications"] {
        check(!P.inApp(outside, apps: apps), "sec4 M6: \(outside) is not Aris's app")
    }
    check(P.holdsApp("/Applications", apps: apps) && P.holdsApp("/Users/p/Applications", apps: apps) && P.holdsApp("/Users", apps: apps)
            && !P.holdsApp("/Applications/Aris.app", apps: apps) && !P.holdsApp("/Applications/Safari.app", apps: apps) && !P.holdsApp("/", apps: apps),
          "sec4 M6: a folder that holds Aris's app counts for moves and edits (moving /Applications would carry it away)")
    check(!P.blocks("/Users/p/Desktop/notes.txt", home: home, apps: apps) && P.blocks("/Users/p/.config/aris/aris/schedules.json", home: home, apps: apps),
          "sec4 M6: everything else is judged as before")
    let guardCode = secFix4Code("Aris/private/Aris/Drop/ArisDropGuard.swift")
    check(ArisDropGuard.inProtectedPlace("/Users/p/Applications/Aris.app/Contents/MacOS/aris-tools", home: home, app: own)
            && ArisDropGuard.inProtectedPlace(own, home: home, app: own) && !ArisDropGuard.inProtectedPlace("/Users/p/Desktop/a.png", home: home, app: own)
            && !ArisDropGuard.inProtectedPlace("/Users/p/Desktop/a.png", home: home, app: "/usr/bin") && ArisDropGuard.protectedPlaces == P.relative
            && guardCode.contains("app: String = Bundle.main.bundlePath"),
          "sec4 M6: the drop guard knows Aris's own app too, and its list of places is still the tools' list in the same order")
}

private func secFix4GateTests() {
    // The gate itself, as every brain's action reaches it (ArisRiskPolicy.risk is the one judge for Codex, Claude, the
    // API brain and agy's relay). The tests run from a loose build, so the app here is the installed place.
    let app = "/Applications/Aris.app", tool = app + "/Contents/MacOS/aris-tools", skill = app + "/Contents/Resources/skills/builtin/skill-creator/SKILL.md"
    for path in [app, tool, app + "/Contents/MacOS/aris-agent", skill, app + "/Contents/Info.plist"] {
        check(risk(.fileChange([path])) == .never, "sec4 M6 gate: a file change at \(path) is never done")
    }
    check(risk(.fileChange([riskHome + "/Desktop/a.txt", tool])) == .never, "sec4 M6 gate: a change that reaches into the app among other files is never done")
    for command in ["\(riskTools) trash \(app)", "\(riskTools) trash \(tool)", "\(riskTools) move \(tool) ~/Desktop/t", "\(riskTools) rename \(app) Other.app",
                    "\(riskTools) folder new \(app)/Contents/x", "\(riskTools) move /Applications ~/Desktop/Apps"] {
        check(shellRisk(command) == .never, "sec4 M6 gate: “\(command.prefix(70))” is never done")
    }
    // A plain shell line is judged as it is for Aris's own folder: it is never run by itself, it asks on a card.
    let inFolder = riskHome + "/.config/aris/aris/schedules.json"
    for shape in ["rm %@", "mv %@ /tmp/x", "cp /tmp/evil %@", "echo x > %@", "ln -sf /tmp/evil %@", "chmod 777 %@", "sed -i '' s/a/b/ %@"] {
        let onApp = shellRisk(shape.replacingOccurrences(of: "%@", with: tool)), onFolder = shellRisk(shape.replacingOccurrences(of: "%@", with: inFolder))
        check(onApp != .auto && (onApp == .never || onFolder != .never), "sec4 M6 gate: “\(shape)” on a file inside the app is never run by itself, and is refused wherever the same line on Aris's own folder is")
    }
    check(shellRisk("mv ~/Desktop/a.txt ~/Documents/a.txt") != .never && risk(.fileChange([riskHome + "/Desktop/a.txt"])) != .never
            && shellRisk("\(riskTools) trash ~/Desktop/a.txt") != .never,
          "sec4 M6 gate: ordinary file work is judged as before (a card, never a refusal)")
    check(ArisRiskPolicy.isProtected(tool, home: riskHome) && ArisRiskPolicy.neverEdited(tool, home: riskHome) && ArisRiskPolicy.neverEdited(skill, home: riskHome)
            && ArisRiskPolicy.isProtected("/Applications", home: riskHome) && ArisRiskPolicy.neverEdited("/Applications", home: riskHome)
            && !ArisRiskPolicy.isProtected("/Applications/Safari.app", home: riskHome) && !ArisRiskPolicy.neverEdited(riskHome + "/Desktop/a.txt", home: riskHome),
          "sec4 M6 gate: the two lists the gate reads (protected, never edited) both hold the app, the folder that holds it, and nothing more")
    let files = secFix4Code("ArisAgent/ArisRiskPolicy+Files.swift")
    check(files.components(separatedBy: "ArisProtectedPlaces.holdsApp(path)").count == 3, "sec4 M6 gate: wiring: both lists ask about the folder that holds the app")
}

private func secFix4PinTests() {
    // (Review 9, L4 moved the rule into ArisInsertRefusal.refusal, where it is run rather than read.)
    let aris = ArisFrontLive.App(pid: 42, bundleId: "com.lumenjsn.aris", name: "Aris", ordinary: true)
    check(ArisInsertRefusal.refusal(trusted: true, secureInput: false, front: aris) != nil, "sec4 L4: the helper still refuses to type into Aris itself")
    check(ArisInsertRefusal.refusal(trusted: false, secureInput: false, front: aris) == ArisInsertRefusal.needsAccessibility
          && secFix4Code("ArisAgent/ArisInsert.swift").contains("ArisInsertRefusal.refusal(trusted: trusted, secureInput: IsSecureEventInputEnabled()"),
          "sec4 L4: typing is still refused without Accessibility")
    check(ArisInsertRefusal.reply(ArisInsertRefusal.needsAccessibility)["needs"] as? String == ArisInsertOutcome.needsAccessibility
            && ArisInsertRefusal.reply("a password field has the keyboard")["needs"] == nil,
          "sec4 L4: a paste refused for want of Accessibility names what is missing to the app, and only that refusal does")
}

// MARK: - Who may run the programs inside the app (M1, M2, M3, L1)

private func secFix4OriginTests() {
    typealias O = ArisOrigin
    let app = "/Applications/Aris.app", agent = app + "/Contents/MacOS/aris-agent", tools = app + "/Contents/MacOS/aris-tools"
    // M1: where a program is.
    check(O.enclosingApp(of: tools) == app && O.enclosingApp(of: app + "/Contents/Helpers/aris-tools") == app && O.enclosingApp(of: app + "/aris-tools") == app
            && O.enclosingApp(of: "/Users/kim/c/Aris.app/Contents/Resources/x/aris-tools") == "/Users/kim/c/Aris.app"
            && O.enclosingApp(of: "/Users/kim/dev/out/aris-tools") == nil && O.enclosingApp(of: "/Users/kim/Aris.app") == nil,
          "sec4 M1: a program anywhere under a folder named ….app is inside an app (macOS charges it to that app from anywhere inside)")
    check(O.place(ofProgram: tools) == .expected(app: app) && O.place(ofProgram: agent) == .expected(app: app) && O.place(ofProgram: "/Users/kim/dev/out/aris-tools") == .loose,
          "sec4 M1: the two programs are expected in Contents/MacOS only; a build folder is outside any app")
    for odd in [app + "/Contents/Helpers/aris-tools", app + "/Contents/Resources/aris-tools", app + "/aris-agent", app + "/Contents/MacOS/sub/aris-tools",
                app + "/Contents/MacOS/other-name", "/Users/kim/Outer.app/Contents/Resources/Aris.app/Contents/MacOS/aris-tools"] {
        check(O.place(ofProgram: odd) == .elsewhere, "sec4 M1: \(odd) is inside an app but not where Aris keeps its programs")
    }
    func facts(program: String = tools, me: pid_t = 900, responsible: pid_t? = 500, responsibleProgram: String? = agent,
               identity: O.Identity = .aris, job: O.Job? = O.Job(pid: 500, program: agent), answered: Bool = true, signed: Set<pid_t> = [500],
               vouchedBy: pid_t? = 500, bundleIsAris: Bool = true, homeRedirected: Bool = false) -> O.Facts {
        O.Facts(me: me, program: program, responsible: responsible, responsibleProgram: responsibleProgram, responsibleIdentity: identity, job: job, launchdAnswered: answered,
                signedAsAgent: signed, vouchedBy: vouchedBy, looksLikeJob: true, bundleIsAris: bundleIsAris, homeRedirected: homeRedirected)
    }
    for odd in [app + "/Contents/Helpers/aris-tools", app + "/Contents/Resources/aris-tools", "/Users/kim/c/Aris.app/aris-tools"] {
        check(!O.mayRun(facts(program: odd)) && !O.mayRun(facts(program: odd, responsible: 300, responsibleProgram: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", identity: .another, signed: [], vouchedBy: nil)),
              "sec4 M1: aris-tools copied to \(odd) never runs, whoever started it")
        check(!O.mayServe(facts(program: odd.replacingOccurrences(of: "aris-tools", with: "aris-agent"), me: 500)), "sec4 M1: nor does aris-agent serve from there")
    }
    check(!O.mayRun(facts(bundleIsAris: false)) && !O.mayServe(facts(program: agent, me: 500, bundleIsAris: false)),
          "sec4 M1: inside an app that does not say it is Aris (identifier, main program) neither program runs")
    // The legitimate chains.
    check(O.mayRun(facts()), "sec4 M2: a tool the helper started, directly or through an AI program or a shell, runs (the chains are in the vouch tests)")
    check(O.mayRun(facts(responsible: 300, responsibleProgram: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", identity: .another, signed: [], vouchedBy: nil)),
          "sec4 M2: Terminal → tool runs on Terminal's own permissions")
    check(O.mayServe(facts(program: agent, me: 500, responsible: 500, signed: [], vouchedBy: nil)), "sec4 M2: launchd's own job, started as the aris-agent of this app, serves")
    // The shapes the review and the measurements found (U2): the job's program is a shell, env or a script that
    // becomes the real aris-agent after forking a tool; macOS charges both to Aris.
    for (what, job) in [("a shell that execs it", O.Job(pid: 500, program: "/bin/sh", argument0: "/bin/sh")),
                        ("a Program other than its first argument", O.Job(pid: 500, program: "/Users/kim/evil.sh", argument0: agent)),
                        ("env", O.Job(pid: 500, program: nil, argument0: "/usr/bin/env")),
                        ("a script", O.Job(pid: 500, program: nil, argument0: "/Users/kim/start-helper.sh"))] {
        check(!O.mayServe(facts(program: agent, me: 500, responsible: 500, job: job, signed: [], vouchedBy: nil)),
              "sec4 M2: aris-agent does not serve when launchd's job is \(what), though the process is the real aris-agent by now")
        check(!O.mayRun(facts(job: job)), "sec4 M2: a tool forked before such a job became aris-agent is refused (its parent is signed as aris-agent, the job is not Aris's) (\(what))")
        check(!O.mayYetBeJob(facts(program: agent, me: 500, job: job)), "sec4 M3: and aris-agent stops at once, with no second look (\(what))")
    }
    check(O.Job(pid: 1, program: agent, argument0: agent).starts(agent) && O.Job(pid: 1, program: agent).starts(agent) && !O.Job(pid: 1, program: nil, argument0: nil).starts(agent)
            && !O.Job(pid: 1, program: agent, argument0: "/bin/sh").starts(agent),
          "sec4 M2: launchd starts the helper itself only when its first argument is the helper and Program, if there is one, is too")
    check(!O.mayServe(facts(program: agent, me: 500, homeRedirected: true)) && !O.mayRun(facts(homeRedirected: true)),
          "sec4 M2: with the home folder redirected by the environment (CFFIXED_USER_HOME) aris-agent does not serve and a tool charged to Aris does not run")
    // L1 and M3: no record, no guessing; a final refusal is at once.
    check(!O.mayServe(facts(program: agent, me: 500, job: nil, answered: false)) && !O.mayRun(facts(job: nil, answered: false)), "sec4 L1: with no answer from launchd nothing serves and nothing charged to Aris runs")
    check(O.mayYetBeJob(facts(program: agent, me: 500, job: nil)) && O.mayYetBeJob(facts(program: agent, me: 500, job: O.Job(pid: nil, program: agent)))
            && !O.mayYetBeJob(facts(program: agent, me: 650, job: O.Job(pid: 500, program: agent))) && !O.mayYetBeJob(facts(program: agent, me: 500, job: nil, answered: false)),
          "sec4 M3: a refused aris-agent looks again only while launchd has not yet named its job's process; when the record names another process it stops at once")
    let main = secFix4Code("ArisAgent/main.swift")
    check(main.contains("where !helperMode && !ArisOrigin.decision(origin, serving: true).allowed && ArisOrigin.mayYetBeJob(origin)"), "sec4 M3: wiring: the second look is taken only then")
    check(secFix4Code("ArisAgent/ArisOrigin.swift").contains("guard facts.launchdAnswered, let job = facts.job, let pid = job.pid, pid != facts.me,"),
          "sec4 L1: wiring: the helper behind a tool is launchd's job or nobody")
}
