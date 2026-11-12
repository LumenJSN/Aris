//
//  ArisTeamRemoval.swift
//  Aris
//
//  "큐에이봇 팀원 지워 줘" / "remove teammate Cody" (BUG-26): a local intent, never a job. It names a stored teammate
//  (or Claude Code, which can't go, or a name nobody has), asks with the settings' own 빼기 confirmation, and removes the
//  teammate only on a yes. Pure: no files, no AI.
//

import Foundation

enum ArisTeamRemoval: Equatable {
    case teammate(ArisTeammate)
    /// It asks to remove a teammate by a name nobody has.
    case unknown
    /// Claude Code: always on the team.
    case fixed

    private static let korean = #"^(?:팀원\s+)?(.+?)\s*(?:팀원)?\s*(?:을|를)?\s*(?:지워|지우|빼|삭제|없애|내보내)(?:\s*줘|\s*주세요|\s*줄래|해|해\s*줘|해\s*주세요|하기)?[\s.!?~]*$"#
    private static let english = #"(?i)^(?:please\s+)?(?:remove|delete|fire|drop)\s+(?:the\s+)?(?:teammate\s+)?(.+?)(?:\s+from\s+(?:the\s+|my\s+)?team)?[\s.!?]*$"#

    /// What `text` asks, or nil when it isn't a request to remove a teammate.
    static func parse(_ text: String, teammates: [ArisTeammate]) -> ArisTeamRemoval? {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard said.count <= 80 else { return nil }
        let aboutTeam = said.contains("팀원") || said.range(of: #"(?i)\bteam(mate)?\b"#, options: .regularExpression) != nil
        for pattern in [korean, english] {
            guard let name = capture(pattern, in: said) else { continue }
            if let mate = teammates.first(where: { $0.name.lowercased() == name.lowercased() }) {
                return mate.id == ArisTeammate.claudeCodeId ? .fixed : .teammate(mate)
            }
            if name.lowercased() == ArisTeammate.claudeCode.name.lowercased() { return .fixed }
            return aboutTeam ? .unknown : nil
        }
        return nil
    }

    /// The settings' 빼기 confirmation, as a card.
    static func confirmation(for mate: ArisTeammate) -> ArisConfirmation {
        ArisConfirmation(id: "team-remove-" + UUID().uuidString, title: ArisTeamCopy.removeTitle(mate.name), detail: ArisTeamCopy.removeDetail)
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let found = text[range].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
        return found.isEmpty ? nil : found
    }
}
