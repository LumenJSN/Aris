//
//  ArisFleetGrant.swift
//  Shared/Core (app, aris-agent, tests)
//
//  What the owner's yes on a `fleet.answer` allow card lets through: one Claude Code session's one pending permission
//  request, named by the session and the request's fingerprint (its tool and exact input). The helper puts it on the
//  card it asks; the app applies it at the owner's yes, on its own card queue, to the card in the notch with that very
//  fingerprint, and to nothing else (a request that changed meanwhile isn't answered). No token holder can send an
//  allow any other way. Pure.
//

import Foundation

struct ArisFleetGrant: Equatable, Sendable {
    let session: String
    let fingerprint: String

    var json: [String: Any] { ["session": session, "fingerprint": fingerprint] }

    static func parse(_ value: Any?) -> ArisFleetGrant? {
        guard let object = value as? [String: Any], let session = object["session"] as? String, !session.isEmpty, session.count <= 100,
              let fingerprint = object["fingerprint"] as? String, fingerprint.range(of: "^[0-9a-f]{1,16}$", options: .regularExpression) != nil else { return nil }
        return ArisFleetGrant(session: session, fingerprint: fingerprint)
    }
}
