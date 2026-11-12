//
//  ArisOrigin+Start.swift
//  aris-agent and aris-tools
//
//  What a tool's start costs, kept small by construction (final VM run: each aris-tools start spent about 2.4 s in the
//  checks security review 4 added, the two tool runs of one look at the screen took 6 s and 3.3 s, and every look
//  ran past its 10 s). aris-tools starts for every single call, so nothing may stand between its start and its work
//  that does not have to:
//
//   · nothing on this path ever uses the network (ArisOrigin+Seal, ArisOrigin+Signature);
//   · while the new checks only write down what they would have refused (ArisRollout.enforcing is false), the tool
//     gathers only what the rule of the release before reads, which decides; what the new rule would have said is
//     worked out afterwards on a background queue and written to the log if it disagrees. A tool that ends first
//     simply does not write its line: a check that cannot refuse anything never delays a tool;
//   · once the new rule decides, the tool does not verify the app's bundle again at each start: the helper, which
//     starts once, verified the whole bundle then, and with its yes for a tool it started it says whether the
//     bundle's signature files are still what it verified: the same files (inode, size and times) holding the same
//     bytes (a SHA-256 of Info.plist and of CodeResources, taken at its verification and again for each question:
//     the times alone do not move when a file is written through a shared mapping; security review 6, L1). The tool
//     still verifies its own program file itself. Only that helper's word counts (launchd's job for Aris, started
//     as this app's aris-agent, signed as it, holding the connection). A tool the helper did not start, or one the
//     helper cannot say this for, verifies the bundle as before.
//   · for the VM run that decides the switch there is a rollout audit (ArisRollout.auditing): with it on, every
//     start gathers everything before it runs and writes one "evaluated" line, so a short command proves as much
//     as a long one.
//

import CryptoKit
import Darwin
import Foundation

extension ArisOrigin {
    /// Whether a start gathers everything the new rule reads: aris-agent as the server always (it starts once), a
    /// tool only once the new rule decides.
    /// `auditing`: the rollout audit is on (ArisRollout): then a tool gathers everything too, before it runs.
    static func gathersAll(serving: Bool, enforcing: Bool = ArisRollout.enforcing, auditing: Bool = ArisRollout.isAuditing) -> Bool {
        serving || enforcing || auditing
    }

    /// What a start writes down and leaves for later (pure; `allows` does it).
    struct StartNotes: Equatable {
        /// The "would refuse" line, when all was asked and the new rule disagrees.
        var wouldRefuse: String?
        /// The rollout audit's line: one per start, whichever way the new rule went.
        var evaluated: String?
        /// The new rule's verdict is worked out afterwards, off the program's path (a tool that ends first writes nothing).
        var later = false
    }

    /// `allowed`: what was decided for this start.
    static func startNotes(_ facts: Facts, serving: Bool, allowed: Bool, enforcing: Bool = ArisRollout.enforcing,
                           auditing: Bool = ArisRollout.isAuditing) -> StartNotes {
        let refusal = enforcing ? nil : wouldRefuseLine(facts, serving: serving)
        var notes = StartNotes(wouldRefuse: refusal)
        if auditing, facts.thorough { notes.evaluated = evaluatedLine(facts, serving: serving, allowed: allowed, wouldRefuse: refusal != nil) }
        notes.later = allowed && !facts.thorough
        return notes
    }

    /// The rollout audit's line for one start.
    static func evaluatedLine(_ facts: Facts, serving: Bool, allowed: Bool, wouldRefuse: Bool, secondLook: Bool = false) -> String {
        let who = serving ? "aris-agent serving" : secondLook ? "a waiting tool's second look" : "a tool"
        let verdict = !allowed ? "refused" : wouldRefuse ? "allowed by the proven rule, the new rule would refuse" : "allowed, the new rule agrees"
        return "\(who): \(verdict) (\(describe(facts)))"
    }

    /// The facts the rule of the release before reads (`mayRunProven`), and no others: the parents, launchd's job
    /// and whether that job's process is signed as aris-agent, asked only when the path says Aris would be charged.
    static func provenFacts(_ found: Facts, chargedByPath: Bool) -> Facts {
        var facts = found
        facts.thorough = false
        guard facts.bundleIsAris, chargedByPath, !facts.homeRedirected else { return facts }
        facts.ancestors = ancestors(of: facts.me)
        let asked = job(label: label)
        facts.job = asked.job
        facts.launchdAnswered = asked.answered
        if let helper = asked.job?.pid, helper != facts.me, isSignedAsAgent(helper) { facts.signedAsAgent = [helper] }
        return facts
    }

    /// Works out what the new rule would have said, off this program's path, and writes the line when it disagrees.
    /// Nothing waits for it.
    static func noteWouldRefuseLater(serving: Bool, later: (@escaping @Sendable () -> Void) -> Void = { DispatchQueue.global(qos: .utility).async(execute: $0) }) {
        later {
            if let line = wouldRefuseLine(facts(serving: serving, thorough: true), serving: serving) { ArisRollout.wouldRefuse(line) }
        }
    }

    // MARK: The helper's word on the seal

    /// One file as it was when the helper verified the app: which file it is, how long, and when it and its entry
    /// last changed. The change time cannot be set back by the user, and writing a new file in its place gives
    /// another inode. `digest`: the SHA-256 of its bytes, for the two signature files: bytes written through a shared
    /// mapping change what every reader gets and move none of the times (measured in security review 6, L1).
    struct FilePrint: Equatable {
        let device: Int32
        let inode: UInt64
        let size: Int64
        let modified: Int64
        let modifiedNanos: Int
        let changed: Int64
        let changedNanos: Int
        var digest: Data? = nil
    }

    /// The files whose bytes are compared too: the bundle's signed Info.plist and its list of sealed files (small;
    /// the programs' own pages are checked by the kernel against the signature it accepted, and the tool verifies
    /// its own file itself).
    static func isHashed(_ path: String) -> Bool {
        path.hasSuffix("/Contents/Info.plist") || path.hasSuffix("/Contents/_CodeSignature/CodeResources")
    }

    /// The files a tool's own check reads (the bundle's signature and signed Info.plist, the tool itself), with the
    /// app's main program and the helper.
    static func sealedFiles(app: String) -> [String] {
        ["Contents/Info.plist", "Contents/_CodeSignature/CodeResources", "Contents/MacOS/Aris", "Contents/MacOS/\(agentName)", "Contents/MacOS/aris-tools"]
            .map { "\(app)/\($0)" }
    }

    /// The print of each of those files; nil when one is missing, is not a plain file, or cannot be read.
    static func sealPrint(app: String, print: (String) -> FilePrint? = { filePrint($0, hashed: isHashed($0)) }) -> [FilePrint]? {
        let found = sealedFiles(app: app).map(print)
        return found.contains(nil) ? nil : found.compactMap { $0 }
    }

    /// `hashed`: with the SHA-256 of the file's bytes; a file that should have one and cannot be read has no print.
    static func filePrint(_ path: String, hashed: Bool = false) -> FilePrint? {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        var digest: Data?
        if hashed {
            guard let bytes = FileManager.default.contents(atPath: path) else { return nil }
            digest = Data(SHA256.hash(data: bytes))
        }
        return FilePrint(device: info.st_dev, inode: UInt64(info.st_ino), size: Int64(info.st_size),
                         modified: Int64(info.st_mtimespec.tv_sec), modifiedNanos: info.st_mtimespec.tv_nsec,
                         changed: Int64(info.st_ctimespec.tv_sec), changedNanos: info.st_ctimespec.tv_nsec, digest: digest)
    }

    /// Whether the helper may say "the app is as I verified it": it did verify it, whole, and every file reads now
    /// exactly as it did then.
    static func sealStands(verified: [FilePrint]?, now: [FilePrint]?) -> Bool {
        guard let verified, let now, !verified.isEmpty else { return false }
        return verified == now
    }

    private static let sealRecordLock = NSLock()
    nonisolated(unsafe) private static var sealRecord: (app: String, files: [FilePrint])?
    nonisolated(unsafe) private static var sealPrintsTaken = false

    /// aris-agent as the server, right before it verifies the whole bundle for the first time: the files' prints as
    /// they are now. Taken before the verification, so a file changed between the two reads differently afterwards;
    /// and only that once, since later looks reuse the first verification's verdict.
    static func printsBeforeFirstVerification(app: String) -> [FilePrint]? {
        let first = sealRecordLock.withLock {
            defer { sealPrintsTaken = true }
            return !sealPrintsTaken
        }
        return first ? sealPrint(app: app) : nil
    }

    /// The whole bundle verified after those prints were taken: the helper keeps them.
    static func rememberVerifiedSeal(app: String, files: [FilePrint]) {
        sealRecordLock.withLock { if sealRecord == nil { sealRecord = (app, files) } }
    }

    /// Whether this helper verified its app and sees its files unchanged since: five lstat calls and two small files
    /// read and hashed, for each question.
    static func sealStandsAsVerified() -> Bool {
        guard let record = sealRecordLock.withLock({ sealRecord }) else { return false }
        return sealStands(verified: record.files, now: sealPrint(app: record.app))
    }
}
