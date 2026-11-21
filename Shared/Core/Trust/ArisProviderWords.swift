//
//  ArisProviderWords.swift
//  Shared/Core (the app, aris-agent, tests)
//
//  A provider's own error text as it may go into a log (the eleventh VM run, E2: "Your api key: ****11ab is invalid
//  (request_id: …)" was written to the unified log as it came; the round before had taken it off the screen only).
//  What follows a word for a credential, a masked key's visible tail and a request id are dotted out, and the text is
//  capped. The exact key is taken out before this where it is known (ArisAPISecrets, ArisDecisionProviders). Pure.
//

import Foundation

enum ArisProviderWords {
    /// The most of a provider's text a log line keeps.
    static let longest = 300
    private static let dots = "••••"

    private static let shapes: [(pattern: String, with: String)] = [
        // Authorization: Basic dXNlcjpwYXNz, Bearer abc.def
        (#"(?i)\b(authorization|bearer|basic)\b[\s:=]*(?:(?:bearer|basic)\s+)?["']?[^\s"',)]+"#, "$1 " + dots),
        // token=eyJ…, api_key: abcdef (whatever follows the sign)
        (#"(?i)\b((?:x-)?(?:goog-)?api[ _-]?key|key|token|secret|password)\s*[:=]\s*["']?[^\s"',)]+"#, "$1 " + dots),
        // Your api key ****11ab, x-api-key "abcd1234", API key provided: sk-abc***wxyz, key ending in 9f3c
        (#"(?i)\b((?:x-)?(?:goog-)?api[ _-]?key|key|token|secret|password)\b(?:\s+(?:provided|ending\s+in|is|was|of))*[\s:=]*["']?[^\s"',)]*[\d*_\-.][^\s"',)]*"#, "$1 " + dots),
        // a masked key on its own: ****11ab, sk-ab***yz
        (#"[A-Za-z0-9_\-]*\*{2,}[A-Za-z0-9_\-*]*"#, dots),
        (#"(?i)\brequest[ _-]?id\b[\s:=]*["']?[A-Za-z0-9_\-]+"#, "request id " + dots),
    ]

    /// `text` for a log line.
    static func loggable(_ text: String) -> String {
        var out = text
        for shape in shapes { out = out.replacingOccurrences(of: shape.pattern, with: shape.with, options: .regularExpression) }
        return out.count > longest ? String(out.prefix(longest)) + "…" : out
    }
}
