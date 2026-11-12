//
//  ArisOrigin.swift
//  aris-agent and aris-tools
//
//  Who started this program. aris-agent and aris-tools sit inside Aris.app so that macOS shows one row, "Aris", for
//  every permission: a program launchd starts from inside the app is charged to the app, with everything the user
//  granted Aris (Accessibility, Screen Recording, Full Disk Access, folders, Automation). That is true for ANY launchd
//  job of the same user that points at these programs, not only Aris's own (follow-up experiment, 2-symlink.txt). So
//  both programs find out who started them before they do anything:
//
//   · aris-tools runs when macOS would charge someone else for what it does (it was started from Terminal or by another
//     app: that program's own permissions apply, as before), or when Aris's helper says it started it: the job launchd
//     holds under Aris's label, started as the aris-agent of this same app and signed as it, answers the tool's
//     question from its own list of the processes it started (ArisOrigin+Vouch). Who the tool's parents are is not
//     asked of the tool. Otherwise it refuses with one plain line.
//   · aris-agent serves only as that job: launchd's record for Aris's label names this very process and this very
//     program. Its helper modes (api-brain, --usage-report) follow the rule for aris-tools.
//
//  A copy outside an app (a developer's build folder, the tests) is its own row in macOS with no grants of Aris's, so
//  it is left alone. The decisions are pure (tested); the probes below them ask the kernel, launchd and the code
//  signature (ArisOrigin+Signature), never a name or a path, for "who is charged" and "started by Aris".
//

import Darwin
import Foundation
import Security
import ServiceManagement

enum ArisOrigin {
    static let label = "com.lumenjsn.aris.agent"
    static let agentName = "aris-agent"
    /// aris-agent's signing identifier (kept from before the rename, like its permissions).
    static let agentSigningId = "com.lumenjsn.aris.aris-agent"
    /// aris-tools' signing identifier.
    static let toolsSigningId = "com.lumenjsn.aris.aris-tools"
    /// How far up the parents are followed.
    static let ancestorLimit = 32

    static let refusedLine = "aris-tools: not started by Aris, so it won't use Aris's permissions. Ask Aris, or run it from Terminal."
    /// The line for a tool that may not run: a changed copy of the app is said as that.
    static func refusal(_ facts: Facts) -> String { facts.sealIntact ? refusedLine : refusedChangedLine }

    static let agentRefusedLine = "aris-agent: not started by launchd as Aris's own helper (com.lumenjsn.aris.agent); stopping."

    // MARK: Decisions (pure)

    /// The app a program sits directly in ("/Applications/Aris.app/Contents/MacOS/aris-tools" gives
    /// "/Applications/Aris.app"); nil for a loose copy. Only this place makes macOS charge the app.
    static func app(ofProgram path: String) -> String? {
        let parts = (path as NSString).pathComponents
        guard parts.count >= 5, parts.first == "/", parts[parts.count - 2] == "MacOS", parts[parts.count - 3] == "Contents",
              parts[parts.count - 4].hasSuffix(".app") else { return nil }
        return NSString.path(withComponents: Array(parts.dropLast(3)))
    }

    /// The outermost app a path lies in: any folder named "….app" above it counts. macOS charges a program signed with
    /// the app's certificate to the app wherever it sits inside it (Contents/Helpers, Resources, the bundle's root:
    /// security review 4, M1; measured, U1), so "inside an app" is this, not only Contents/MacOS.
    static func enclosingApp(of path: String) -> String? {
        let parts = (path as NSString).pathComponents
        guard parts.first == "/", let index = parts.dropLast().firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return NSString.path(withComponents: Array(parts.prefix(index + 1)))
    }

    /// Where this program is.
    enum Place: Equatable {
        /// Not inside any app: its own row in macOS, none of Aris's grants.
        case loose
        /// Exactly where Aris keeps it: <app>/Contents/MacOS/aris-agent or aris-tools, in no nested app.
        case expected(app: String)
        /// Anywhere else inside an app: never run from there.
        case elsewhere
    }

    static let programNames: Set<String> = ["aris-agent", "aris-tools"]

    static func place(ofProgram path: String) -> Place {
        guard let outer = enclosingApp(of: path) else { return .loose }
        guard app(ofProgram: path) == outer, programNames.contains((path as NSString).lastPathComponent) else { return .elsewhere }
        return .expected(app: outer)
    }

    /// launchd's record of a job: its process, the program launchd executes (`Program`, when the job names one), and
    /// the first of its arguments. A job whose `Program` is a shell, `env` or a script that later becomes aris-agent
    /// is not Aris's helper (security review 4, M2; measured, U2: macOS charges such a helper to the app).
    struct Job: Equatable {
        let pid: pid_t?
        let program: String?
        let argument0: String?

        init(pid: pid_t?, program: String?, argument0: String?) {
            self.pid = pid
            self.program = program
            self.argument0 = argument0
        }

        /// A job that names one program only, as its first argument (how Aris's own job is written).
        init(pid: pid_t?, program: String?) { self.init(pid: pid, program: nil, argument0: program) }

        /// Whether launchd starts exactly `path`: its first argument is that, and `Program`, when there is one, too.
        func starts(_ path: String) -> Bool { argument0 == path && (program == nil || program == path) }
    }

    /// What the probes found about this process.
    struct Facts: Equatable {
        /// This process and its program, as the kernel has them.
        var me: pid_t
        var program: String
        /// The process macOS holds responsible for this one, and its program; nil when it could not be asked.
        var responsible: pid_t?
        /// Its program's path: for the log line only, never for a decision.
        var responsibleProgram: String?
        /// Whose program the responsible process is, by its code signature (asked by its audit token).
        var responsibleIdentity: Identity = .unknown
        /// The parents, nearest first: read only for the rule of the release before (`mayRunProven`), never for the
        /// helper's yes.
        var ancestors: [pid_t] = []
        /// launchd's job under Aris's label; nil when launchd could not be asked or has none.
        var job: Job?
        /// Whether launchd could be asked at all.
        var launchdAnswered: Bool
        /// The processes whose code signature is aris-agent's (asked of launchd's job only).
        var signedAsAgent: Set<pid_t>
        /// The process that holds the other end of the connection this program asked on, when it answered "I started
        /// you, or one of your parents": only ever launchd's job, checked from the kernel's list of its sockets.
        var vouchedBy: pid_t?
        /// The parent is launchd and the job's name in the environment is Aris's label. Never enough by itself (both
        /// can be set by whoever starts the program): kept for the log line only.
        var looksLikeJob: Bool
        /// The app this program is in says it is Aris (its identifier and its main program's name).
        var bundleIsAris: Bool = true
        /// The app this program is in still verifies as the app that was signed (ArisOrigin+Seal).
        var sealIntact: Bool = true
        /// The environment points this program at another home folder (CFFIXED_USER_HOME): its config, token, tools
        /// link and the folders it looks for AI programs in would be someone else's.
        var homeRedirected: Bool = false
        /// Everything above was asked. False for a tool while the new rule only writes down (ArisRollout): then only
        /// what the rule of the release before reads was gathered, and the rest is worked out off the tool's path
        /// (ArisOrigin+Start).
        var thorough: Bool = true
    }

    /// Whether macOS charges Aris for what this program does: its responsible process is itself, unknown, or a
    /// program that is Aris by its code signature, wherever that program's file is (security review 4, M3: a copy of
    /// the app elsewhere is Aris to macOS, and a path shows the genuine program after an exec while macOS still
    /// charges the launcher; measured, U1c and U2). Only a responsible process that is provably another program
    /// (Terminal, another app) makes this false.
    static func chargedToApp(_ facts: Facts) -> Bool {
        guard let responsible = facts.responsible, responsible != facts.me else { return true }
        return facts.responsibleIdentity != .another
    }

    /// The pid of Aris's helper: launchd's job for the label, started as this app's aris-agent and nothing else, and
    /// signed as aris-agent (asked of the process itself, by its audit token: a path can be made to say anything after
    /// an exec). With no record from launchd there is no helper (security review 4, L1: no guessing from the environment).
    static func genuineHelper(_ facts: Facts, app: String) -> pid_t? {
        guard facts.launchdAnswered, let job = facts.job, let pid = job.pid, pid != facts.me,
              job.starts("\(app)/Contents/MacOS/\(agentName)"), facts.signedAsAgent.contains(pid) else { return nil }
        return pid
    }

    /// The pid of Aris's helper when it stands behind this process: that helper itself said it started this process
    /// or one of its parents (security review 4, M2: a parent that is "the genuine agent" proves nothing, since a
    /// script job can start a tool and then become the agent; what the helper started itself cannot be arranged).
    static func helperBehind(_ facts: Facts, app: String) -> pid_t? {
        guard let helper = genuineHelper(facts, app: app), facts.vouchedBy == helper else { return nil }
        return helper
    }

    // MARK: The rule of the release before, and which of the two decides (ArisRollout)

    /// aris-tools as commit 43428e42 decided it (run in the VM): charged by the responsible process's path, and
    /// behind it launchd's job, started as this app's aris-agent and signed as it, among its parents.
    static func mayRunProven(_ facts: Facts) -> Bool {
        switch place(ofProgram: facts.program) {
        case .loose: return true
        case .elsewhere: return false
        case .expected(let app):
            guard facts.bundleIsAris else { return false }
            if let responsible = facts.responsible, responsible != facts.me, let program = facts.responsibleProgram, !program.isEmpty, !program.hasPrefix(app + "/") { return true }
            guard !facts.homeRedirected, let helper = genuineHelper(facts, app: app) else { return false }
            return ([facts.responsible].compactMap { $0 } + facts.ancestors).contains(helper)
        }
    }

    /// aris-agent as the server, as that commit decided it.
    static func mayServeProven(_ facts: Facts) -> Bool {
        switch place(ofProgram: facts.program) {
        case .loose: return true
        case .elsewhere: return false
        case .expected:
            return facts.bundleIsAris && !facts.homeRedirected && facts.launchdAnswered && facts.job?.pid == facts.me && facts.job?.starts(facts.program) == true
        }
    }

    /// What is done, and whether the new rule alone would have refused it. Enforcing: the new rule decides. Not
    /// enforcing: the proven rule decides and the new rule's no is only written down; what the proven rule refuses
    /// stays refused.
    struct Decision: Equatable {
        let allowed: Bool
        let wouldRefuse: Bool
    }

    static func decision(_ facts: Facts, serving: Bool, enforcing: Bool = ArisRollout.enforcing) -> Decision {
        let strict = serving ? mayServe(facts) : mayRun(facts)
        guard !enforcing else { return Decision(allowed: strict, wouldRefuse: false) }
        let proven = serving ? mayServeProven(facts) : mayRunProven(facts)
        // Facts gathered for the proven rule alone say nothing about the new one: its no is worked out later.
        return Decision(allowed: proven, wouldRefuse: facts.thorough && proven && !strict)
    }

    /// The "would refuse" line for facts that were all asked; nil when the new rule agrees.
    static func wouldRefuseLine(_ facts: Facts, serving: Bool) -> String? {
        guard decision(facts, serving: serving, enforcing: false).wouldRefuse else { return nil }
        return "\(serving ? "aris-agent serving" : "a tool charged to Aris") (\(describe(facts)))"
    }

    /// Decides for this process and writes the "would refuse" line when there is one. For a tool that gathered only
    /// what the proven rule reads, that line is worked out afterwards, off the tool's path (ArisOrigin+Start).
    static func allows(_ facts: Facts, serving: Bool) -> Bool {
        let made = decision(facts, serving: serving)
        let notes = startNotes(facts, serving: serving, allowed: made.allowed)
        if let line = notes.wouldRefuse { ArisRollout.wouldRefuse(line) }
        if let line = notes.evaluated { ArisRollout.evaluated(line) }
        if notes.later { noteWouldRefuseLater(serving: serving) }
        return made.allowed
    }

    /// aris-tools, and aris-agent's helper modes.
    static func mayRun(_ facts: Facts) -> Bool {
        switch place(ofProgram: facts.program) {
        case .loose: return true
        case .elsewhere: return false
        case .expected(let app):
            guard facts.bundleIsAris, facts.sealIntact else { return false }
            if !chargedToApp(facts) { return true }
            return !facts.homeRedirected && helperBehind(facts, app: app) != nil
        }
    }

    /// aris-agent as the server: launchd's record for the label names this very process and starts this very program.
    static func mayServe(_ facts: Facts) -> Bool {
        switch place(ofProgram: facts.program) {
        case .loose: return true
        case .elsewhere: return false
        case .expected:
            return facts.bundleIsAris && facts.sealIntact && !facts.homeRedirected && facts.launchdAnswered && facts.job?.pid == facts.me
                && facts.job?.starts(facts.program) == true
        }
    }

    /// Whether a refusal may be looked at again in a moment: only while launchd has not yet said which process its job
    /// is (it names it a moment after the process starts). A record that names another process or another program is
    /// final, and the program stops at once (security review 4, M3: a refused aris-agent used to stay for two seconds).
    static func mayYetBeJob(_ facts: Facts, enforcing: Bool = ArisRollout.enforcing) -> Bool {
        guard case .expected = place(ofProgram: facts.program), facts.bundleIsAris, facts.sealIntact || !enforcing, !facts.homeRedirected,
              facts.launchdAnswered else { return false }
        guard let job = facts.job else { return true }
        return job.pid == nil && job.starts(facts.program)
    }

    // MARK: Probes

    static func program(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    /// The process macOS holds responsible for `pid` (the one its permission checks are charged to); nil when the
    /// system has no such call.
    static func responsible(for pid: pid_t) -> pid_t? {
        typealias Call = @convention(c) (pid_t) -> pid_t
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        let found = unsafeBitCast(symbol, to: Call.self)(pid)
        return found > 0 ? found : nil
    }

    /// launchd's record for `label` in the user's own domain. `answered` is false when launchd could not be asked:
    /// the list of all its jobs came back missing or empty, which a working launchd never gives.
    static func job(label: String) -> (job: Job?, answered: Bool) {
        guard let all = legacyJobs(), !all.isEmpty else { return (nil, false) }
        guard let record = all.first(where: { $0["Label"] as? String == label }) else { return (nil, true) }
        let pid = (record["PID"] as? NSNumber).map { pid_t($0.int32Value) }
        return (Job(pid: pid, program: record["Program"] as? String, argument0: (record["ProgramArguments"] as? [String])?.first), true)
    }

    @available(macOS, deprecated: 10.10)
    private static func legacyJobs() -> [[String: Any]]? {
        SMCopyAllJobDictionaries(kSMDomainUserLaunchd)?.takeRetainedValue() as? [[String: Any]]
    }

    /// Everything the decisions need, for this process. A loose copy, and a tool that another program is charged for,
    /// are decided by where they are and who is responsible: launchd and the signatures are asked only when macOS
    /// would charge the app (`serving`: aris-agent as the server always asks launchd).
    /// `thorough`: everything the new rule reads. Without it (a tool, while the new rule only writes down) only what
    /// the rule of the release before reads is gathered here, so that no check that cannot refuse anything yet stands
    /// between a tool's start and its work (final VM run: every look at the screen timed out behind them).
    static func facts(serving: Bool = false, environment: [String: String] = ProcessInfo.processInfo.environment,
                      thorough: Bool? = nil) -> Facts {
        let thorough = thorough ?? gathersAll(serving: serving)
        let me = getpid()
        let responsible = responsible(for: me)
        var facts = Facts(me: me, program: program(of: me) ?? "", responsible: responsible, responsibleProgram: responsible.flatMap(program(of:)),
                          job: nil, launchdAnswered: false, signedAsAgent: [],
                          looksLikeJob: getppid() == 1 && environment["XPC_SERVICE_NAME"] == label)
        facts.thorough = thorough
        guard case .expected(let app) = place(ofProgram: facts.program) else { return facts }
        let info = NSDictionary(contentsOfFile: "\(app)/Contents/Info.plist")
        facts.bundleIsAris = info?["CFBundleIdentifier"] as? String == "com.lumenjsn.aris" && info?["CFBundleExecutable"] as? String == "Aris"
        facts.homeRedirected = environment["CFFIXED_USER_HOME"] != nil
        // Launchd and the helper are asked only when macOS would charge Aris (by the signature, or, while the rule of
        // the release before still decides, by the path).
        let chargedByPath = !(responsible != nil && responsible != me && !(facts.responsibleProgram ?? "").isEmpty && !(facts.responsibleProgram ?? "").hasPrefix(app + "/"))
        guard thorough else { return provenFacts(facts, chargedByPath: chargedByPath) }
        if let responsible, responsible != me { facts.responsibleIdentity = identity(of: responsible) }
        var sealedByHelper = false
        if serving || chargedToApp(facts) || (!ArisRollout.enforcing && chargedByPath) {
            if !ArisRollout.enforcing { facts.ancestors = ancestors(of: me) }
            let asked = job(label: label)
            facts.job = asked.job
            facts.launchdAnswered = asked.answered
            if !serving, let helper = asked.job?.pid, helper != me, isSignedAsAgent(helper) {
                facts.signedAsAgent = [helper]
                // The question goes out only when launchd's job is the real helper; its yes counts only while that very
                // process holds the other end of the connection.
                if genuineHelper(facts, app: app) != nil, !facts.homeRedirected, let token = ClaudeHookToken.load() {
                    let said = helperReply(pid: me, token: token, listens: { holdsSocket(pid: helper, localPort: vouchPort, remotePort: 0) }) { mine in
                        holdsSocket(pid: helper, localPort: vouchPort, remotePort: mine)
                    }
                    facts.vouchedBy = said.vouched ? helper : nil
                    sealedByHelper = said.vouched && said.sealed
                }
            }
        }
        // A changed or re-assembled copy is refused (security review 4, M1). The real helper, which verified the whole
        // bundle at its own start and sees its signature files unchanged since, may say so for the tool it started
        // (ArisOrigin+Start): that tool then verifies only its own program file. Any other tool verifies the bundle's
        // signature and its own program itself.
        let prints = serving && facts.bundleIsAris ? printsBeforeFirstVerification(app: app) : nil
        facts.sealIntact = facts.bundleIsAris && sealIntact(app: app, program: facts.program, whole: serving, helpersWord: sealedByHelper && !serving)
        if serving, facts.sealIntact, let prints { rememberVerifiedSeal(app: app, files: prints) }
        return facts
    }

    /// The parents of a process, nearest first (for the rule of the release before only).
    static func ancestors(of pid: pid_t) -> [pid_t] {
        var chain: [pid_t] = []
        var current = pid
        while chain.count < ancestorLimit, let next = live(current)?.parent, next > 1, !chain.contains(next) {
            chain.append(next)
            current = next
        }
        return chain
    }

    /// One line for the log about what was found (no secrets in it).
    static func describe(_ facts: Facts) -> String {
        "pid \(facts.me) program \(facts.program) responsible \(facts.responsible.map(String.init) ?? "?") (\(facts.responsibleProgram ?? "?"), \(facts.responsibleIdentity)) "
            + "job \(facts.job.map { "\($0.pid.map(String.init) ?? "-") \($0.argument0 ?? "-")\($0.program.map { " (Program \($0))" } ?? "")" } ?? "none") launchd \(facts.launchdAnswered ? "answered" : "silent")"
            + " helper \(facts.vouchedBy.map { "\($0) vouched" } ?? "did not vouch") seal \(facts.sealIntact ? "holds" : "broken")"
    }
}
