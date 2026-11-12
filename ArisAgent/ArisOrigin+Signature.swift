//
//  ArisOrigin+Signature.swift
//  aris-agent and aris-tools
//
//  Whose program a running process is, by its code signature and never by its path (security review 4, M3 and M5).
//  macOS charges permissions to code identity: a copy of Aris anywhere on the disk is Aris to it, and a process's
//  path shows the genuine program after an exec while macOS still charges whatever started it. So every "is this
//  Aris?" here asks the process itself, through the kernel's audit token for it (the pid together with the count
//  that tells it from a later process with the same pid): signed by this program's own team, under one of Aris's
//  identifiers. With no team (an ad-hoc build) the identifier alone, as ArisXPCTrust does.
//
//  The rule (`identity`) is pure and tested; the probes ask the kernel and the Security framework.
//

import Darwin
import Foundation
import Security

extension ArisOrigin {
    /// Whose program a process is.
    enum Identity: Equatable {
        /// Signed as one of Aris's programs by Aris's own team: macOS charges Aris for it, wherever its file is.
        case aris
        /// Provably something else (Terminal, another app, another user's process): macOS charges that program.
        case another
        /// Could not be told: treated as Aris, so nothing runs on a guess.
        case unknown
    }

    /// The signing identifiers of Aris's four programs: the app, its XPC service, aris-agent and aris-tools.
    static let arisIdentifiers = [ArisXPCTrust.appId, ArisXPCTrust.helperId, agentSigningId, toolsSigningId]

    /// This program's own signing team, read once: from the kernel, which read it when the program started (one
    /// call, nothing verified again); from the signature itself only when the kernel names none (an ad-hoc build).
    static let ownTeam: String? = kernelTeam(pid: getpid()) ?? ArisXPCTrust.ownTeam

    /// The signing team the kernel holds for a running process; nil when it has none or cannot be asked.
    static func kernelTeam(pid: pid_t) -> String? {
        typealias Call = @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer?, Int) -> Int32
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csops") else { return nil }
        // CS_OPS_TEAMID: an 8-byte header, then the team as a C string.
        var buffer = [UInt8](repeating: 0, count: 8 + 256)
        guard unsafeBitCast(symbol, to: Call.self)(pid, 14, &buffer, buffer.count) == 0 else { return nil }
        return teamText(buffer.dropFirst(8).prefix { $0 != 0 })
    }

    /// A team as the kernel wrote it: a plain Apple team id, or nothing.
    static func teamText<Bytes: Collection>(_ bytes: Bytes) -> String? where Bytes.Element == UInt8 {
        let text = String(decoding: bytes, as: UTF8.self)
        return !text.isEmpty && text.count <= 16 && text.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) } ? text : nil
    }

    /// The code-signing requirement "one of `identifiers`, signed by `team`" (ArisXPCTrust's rule for the team: a
    /// value that is not a plain Apple team id is never spliced in, and with none the identifiers alone). An
    /// identifier with a quote or a backslash in it is left out; with none left nothing can satisfy it.
    static func requirement(identifiers: [String], team: String?) -> String {
        let plain = identifiers.filter { !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") } }
        guard let first = plain.first else { return "never" }
        let one = ArisXPCTrust.requirement(peer: first, team: team)
        guard plain.count > 1 else { return one }
        let any = "(" + plain.map { "identifier \"\($0)\"" }.joined(separator: " or ") + ")"
        return one.replacingOccurrences(of: "identifier \"\(first)\"", with: any)
    }

    /// The rule. `validity` is what checking the process against "one of Aris's identifiers, Aris's team" gave (nil:
    /// the process could not be asked at all); `kernelIdentifier` the signing identifier the kernel holds for it;
    /// `sameUser` whether it runs as this user.
    ///  · it satisfies the requirement: Aris;
    ///  · its signature is valid and is someone else's: another program;
    ///  · its signature could not be checked (its file changed under it: an update of that app while it runs): another
    ///    program only when the kernel itself names an identifier that is not one of Aris's, else unknown;
    ///  · it could not be asked: another user's process (root's sshd, a system service) is another program, since Aris's
    ///    own programs never run as another user; anything else is unknown.
    static func identity(validity: OSStatus?, kernelIdentifier: String?, sameUser: Bool?) -> Identity {
        guard let validity else { return sameUser == false ? .another : .unknown }
        if validity == errSecSuccess { return .aris }
        if validity == errSecCSReqFailed { return .another }
        guard let kernelIdentifier, !kernelIdentifier.isEmpty else { return .unknown }
        return arisIdentifiers.contains(kernelIdentifier) ? .unknown : .another
    }

    // MARK: Probes

    /// The kernel's audit token of a process (its pid and the count that tells it from a later process with the same
    /// pid), so the signature that is checked is that very process's.
    static func auditToken(of pid: pid_t) -> Data? {
        var name: mach_port_name_t = 0
        guard task_name_for_pid(mach_task_self_, pid, &name) == KERN_SUCCESS else { return nil }
        defer { mach_port_deallocate(mach_task_self_, name) }
        var token = audit_token_t()
        var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &token) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(name, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        return withUnsafeBytes(of: &token) { Data($0) }
    }

    /// What checking the running process behind `token` against "one of `identifiers`, signed by `team`" gives.
    static func validity(token: Data, identifiers: [String], team: String? = ownTeam) -> OSStatus {
        var code: SecCode?
        let found = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: token] as CFDictionary, [], &code)
        guard found == errSecSuccess, let code else { return found == errSecSuccess ? errSecCSNoSuchCode : found }
        guard let wanted = compiled(requirement(identifiers: identifiers, team: team)) else { return errSecCSReqInvalid }
        // Never the network (ArisOrigin+Seal): the question is whose program this is, not whether a certificate
        // was revoked since.
        return SecCodeCheckValidity(code, .noNetworkAccess, wanted)
    }

    private static let verifiedLock = NSLock()
    /// The processes this one has verified, by audit token and what they were verified as.
    nonisolated(unsafe) private static var verified: Set<Data> = []

    /// Whether a process that was verified before may be taken as verified still: the kernel says its code is valid
    /// now. `kernelValid` nil: the kernel could not be asked, so it is verified again.
    static func keepsVerdict(known: Bool, kernelValid: Bool?) -> Bool { known && kernelValid == true }

    /// Whether the running process `pid` is validly signed under one of `identifiers` by this program's own team.
    /// A process is verified once: its audit token names that very process (a later one with the same pid, and the
    /// same one after an exec, has another), so the helper, which is asked on every request of the app, pays for one
    /// verification per app process. Each later look still asks the kernel whether that process's code is valid.
    static func isSigned(_ pid: pid_t, as identifiers: [String], team: String? = ownTeam) -> Bool {
        guard let token = auditToken(of: pid) else { return false }
        let key = token + Data("|\(identifiers.joined(separator: ","))|\(team ?? "")".utf8)
        if keepsVerdict(known: verifiedLock.withLock({ verified.contains(key) }), kernelValid: kernelValid(token: token)) { return true }
        let holds = validity(token: token, identifiers: identifiers, team: team) == errSecSuccess
        verifiedLock.withLock { if holds { verified.insert(key) } else { verified.remove(key) } }
        return holds
    }

    /// Whether the kernel holds the process behind `token` as validly signed now (CS_VALID); nil when it cannot be asked.
    static func kernelValid(token: Data) -> Bool? {
        typealias Call = @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer?, Int, UnsafeRawPointer?) -> Int32
        guard token.count == MemoryLayout<audit_token_t>.stride,
              let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csops_audittoken") else { return nil }
        let pid = token.withUnsafeBytes { pid_t(bitPattern: $0.loadUnaligned(as: audit_token_t.self).val.5) }
        // CS_OPS_STATUS: the process's code-signing flags; the lowest bit is CS_VALID.
        var flags: UInt32 = 0
        let status = token.withUnsafeBytes { raw in unsafeBitCast(symbol, to: Call.self)(pid, 0, &flags, MemoryLayout<UInt32>.stride, raw.baseAddress) }
        return status == 0 ? flags & 1 != 0 : nil
    }

    /// Whether the running process `pid` is validly signed as aris-agent by this program's own team.
    static func isSignedAsAgent(_ pid: pid_t, team: String? = ownTeam) -> Bool {
        isSigned(pid, as: [agentSigningId], team: team)
    }

    /// The signing identifier the kernel holds for the process behind `token` (it read it when the program started,
    /// so a file that changed since does not matter); nil when it has none or cannot be asked.
    static func kernelIdentifier(token: Data) -> String? {
        typealias Call = @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer?, Int, UnsafeRawPointer?) -> Int32
        guard token.count == MemoryLayout<audit_token_t>.stride,
              let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csops_audittoken") else { return nil }
        // The sixth field of an audit token is the pid (libbsm's audit_token_to_pid reads the same field).
        let pid = token.withUnsafeBytes { pid_t(bitPattern: $0.loadUnaligned(as: audit_token_t.self).val.5) }
        // CS_OPS_IDENTITY: an 8-byte header, then the identifier as a C string.
        var buffer = [UInt8](repeating: 0, count: 8 + 1_024)
        let status = token.withUnsafeBytes { raw in unsafeBitCast(symbol, to: Call.self)(pid, 11, &buffer, buffer.count, raw.baseAddress) }
        guard status == 0 else { return nil }
        let text = buffer.dropFirst(8).prefix { $0 != 0 }
        return text.isEmpty ? nil : String(decoding: text, as: UTF8.self)
    }

    /// Whether process `pid` runs as this user; nil when there is no such process.
    static func isSameUser(_ pid: pid_t) -> Bool? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ucred.cr_uid == getuid()
    }

    /// Whose program the running process `pid` is.
    static func identity(of pid: pid_t) -> Identity {
        guard let token = auditToken(of: pid) else { return identity(validity: nil, kernelIdentifier: nil, sameUser: isSameUser(pid)) }
        let found = validity(token: token, identifiers: arisIdentifiers)
        return identity(validity: found, kernelIdentifier: found == errSecSuccess || found == errSecCSReqFailed ? nil : kernelIdentifier(token: token), sameUser: true)
    }
}
