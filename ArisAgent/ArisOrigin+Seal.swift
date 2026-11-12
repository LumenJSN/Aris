//
//  ArisOrigin+Seal.swift
//  aris-agent and aris-tools
//
//  Whether the app this program sits in is still the app that was signed (security review 4, M1). macOS's own
//  attribution does not care: a program signed with Aris's certificate is charged to Aris inside a copy whose seal is
//  broken too (measured, U1). But a bundle that no longer verifies is a changed or re-assembled copy, and neither
//  program runs from one.
//
//  Checked once per start, and what is checked follows what it costs (measured on the signed 67 MB bundle, on a busy
//  Mac): the whole bundle, strictly, with its nested code and every sealed file, takes 150–185 ms; that is done by
//  aris-agent as the server, which starts once. aris-tools starts for every single call, so it checks the bundle's own
//  signature and signed Info.plist (3–13 ms) and its own program file (about 13 ms): Aris's team and identifiers on
//  both. What that gives up: a file added to, or changed in, the bundle other than those two (the app's main program,
//  the framework, the XPC service, the built-in skill, the list of sealed files itself) is noticed by the helper at
//  its next start, not by each tool.
//
//  No check here ever uses the network (kSecCSNoNetworkAccess on every one): without that flag the Security framework
//  may look up certificate revocation and notarisation online while it validates (CSCommon.h), a wait of seconds on a
//  slow or loaded machine, paid again by every tool start (final VM run: 2.4 s per start, every look timed out).
//  Revocation is not what these checks are for: they ask whether the files are still the ones that were signed.
//
//  Which checks are made is pure (tested); the verification is the Security framework's.
//

import Foundation
import Security

extension ArisOrigin {
    /// One verification: the code at `path` must be validly signed under `identifier` by this build's own team.
    struct SealCheck: Equatable {
        let path: String
        let identifier: String
        let flags: UInt32
    }

    /// On every check: nothing that needs the network (no online revocation or notarisation lookup).
    static let noNetwork = SecCSFlags.noNetworkAccess.rawValue
    /// Strictly, with nested code and every sealed file, for every architecture.
    static let wholeBundleFlags = kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures | noNetwork
    /// Strictly, the bundle's signature and signed Info.plist only: neither its sealed files nor its main program are read.
    static let bundleSignatureFlags = kSecCSStrictValidate | kSecCSDoNotValidateResources | kSecCSDoNotValidateExecutable | noNetwork
    /// Strictly, one program file.
    static let programFlags = kSecCSStrictValidate | kSecCSCheckAllArchitectures | noNetwork

    static let refusedChangedLine = "aris-tools: this copy of Aris was changed after it was signed, so it won't run. Install Aris again."

    /// The signing identifier of one of the two programs, by its file name.
    static func signingId(ofProgram path: String) -> String? {
        switch (path as NSString).lastPathComponent {
        case agentName: return agentSigningId
        case "aris-tools": return toolsSigningId
        default: return nil
        }
    }

    /// What is verified before the program at `program` in `app` does anything. `whole`: aris-agent as the server
    /// (the whole bundle and both programs); otherwise the bundle's signature and this program itself.
    static func sealChecks(app: String, program: String, whole: Bool) -> [SealCheck] {
        guard let own = signingId(ofProgram: program) else { return [] }
        let bundle = SealCheck(path: app, identifier: ArisXPCTrust.appId, flags: whole ? wholeBundleFlags : bundleSignatureFlags)
        let programs = whole ? [agentName, "aris-tools"].map { ("\(app)/Contents/MacOS/\($0)", $0 == agentName ? agentSigningId : toolsSigningId) } : [(program, own)]
        return [bundle] + programs.map { SealCheck(path: $0.0, identifier: $0.1, flags: programFlags) }
    }

    /// What a tool still verifies itself after the real helper said the bundle is as it verified it: its own program
    /// file (about 13 ms). The helper's word stands in for the bundle's signature and Info.plist only.
    static func sealChecksAfterHelpersWord(app: String, program: String) -> [SealCheck] {
        sealChecks(app: app, program: program, whole: false).filter { $0.path == program }
    }

    /// Whether every check holds; with none to make (not one of the two programs) nothing holds.
    static func sealHolds(_ checks: [SealCheck], verify: (SealCheck) -> Bool) -> Bool {
        !checks.isEmpty && checks.allSatisfy(verify)
    }

    // MARK: Probes

    /// What verifying the code on disk at `path` gives.
    static func staticValidity(_ check: SealCheck, team: String? = ownTeam) -> OSStatus {
        var code: SecStaticCode?
        let found = SecStaticCodeCreateWithPath(URL(fileURLWithPath: check.path) as CFURL, [], &code)
        guard found == errSecSuccess, let code else { return found == errSecSuccess ? errSecCSNoSuchCode : found }
        guard let wanted = compiled(requirement(identifiers: [check.identifier], team: team)) else { return errSecCSReqInvalid }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: check.flags), wanted)
    }

    private static let requirementLock = NSLock()
    nonisolated(unsafe) private static var requirements: [String: SecRequirement] = [:]

    /// A requirement's text, compiled once per process.
    static func compiled(_ text: String) -> SecRequirement? {
        requirementLock.withLock {
            if let known = requirements[text] { return known }
            var made: SecRequirement?
            guard SecRequirementCreateWithString(text as CFString, [], &made) == errSecSuccess, let made else { return nil }
            requirements[text] = made
            return made
        }
    }

    private static let sealLock = NSLock()
    nonisolated(unsafe) private static var sealVerdicts: [String: Bool] = [:]

    /// Whether the app's seal holds for this program, verified once per process (and once more, whole, when a tool's
    /// light look is followed by the server's).
    /// `helpersWord`: the real helper said the bundle is as it verified it, so only this program's own file is verified.
    static func sealIntact(app: String, program: String, whole: Bool, helpersWord: Bool = false) -> Bool {
        sealLock.withLock {
            let key = "\(whole)|\(helpersWord)|\(app)|\(program)"
            if let known = sealVerdicts[key] { return known }
            let checks = helpersWord ? sealChecksAfterHelpersWord(app: app, program: program) : sealChecks(app: app, program: program, whole: whole)
            let verdict = sealHolds(checks) { staticValidity($0) == errSecSuccess }
            sealVerdicts[key] = verdict
            return verdict
        }
    }
}
