//
//  ArisXPCTrust.swift
//  Aris
//
//  Who may talk over the app ↔ XPC helper connection: each end requires the other's bundle id, signed by this build's
//  own team (read from its own signature, so a re-signed build keeps working). An ad-hoc build has no team: then the
//  bundle id alone. In both targets.
//

import Foundation
import Security

enum ArisXPCTrust {
    static let appId = "com.lumenjsn.aris"
    static let helperId = "com.lumenjsn.aris.XPCHelper"

    /// The code-signing requirement for the peer. A team that isn't a plain Apple team id is never spliced in.
    static func requirement(peer: String, team: String?) -> String {
        let id = "identifier \"\(peer)\""
        guard let team, !team.isEmpty, team.count <= 16, team.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else { return id }
        return id + " and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// This process's signing team, nil when ad-hoc or unsigned.
    static var ownTeam: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    static func requirement(peer: String) -> String { requirement(peer: peer, team: ownTeam) }
}
