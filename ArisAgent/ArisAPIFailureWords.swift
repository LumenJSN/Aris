//
//  ArisAPIFailureWords.swift
//  aris-agent
//
//  The API brain's own failure lines (a key the service refused, a conversation too long for it, a service it can't
//  reach), in both languages. The driver makes the Korean line, as every brain's driver does; the runner says it in
//  English for a request with no Korean in it (ArisBrainFailure.english reads it back here). These three were Korean
//  only, so "name one famous painting by monet" on an English Mac got "Groq API 키가 맞지 않아요…" (second upgrade run,
//  bug 2). Pure, so the tests run it.
//

import Foundation

enum ArisAPIFailureWords {
    enum Kind: CaseIterable {
        /// The service said the key is not valid.
        case key
        /// The conversation is longer than the model takes.
        case tooLong
        /// No answer from the service (offline, a local server that isn't running).
        case unreachable
        /// The service says too many requests, or the plan's limit is used up.
        case limit
        /// The service itself failed (a 5xx, overloaded).
        case down
        /// Anything else it answered that isn't an answer: said plainly, never in the service's own words (tenth VM
        /// run, item 7: "DeepSeek: Authentication Fails, Your api key: ****0000 is invalid (request_id: …)" was shown
        /// and logged as it came).
        case other
    }

    /// The kind of line for a provider's error, by how the transport classified it; nil for a turn Aris itself ended
    /// (cancelled) and for what the driver words itself.
    static func kind(_ error: ArisAPIError.Kind?) -> Kind? {
        switch error {
        case .auth: .key
        case .context: .tooLong
        case .network, .timeout: .unreachable
        case .quota, .rate: .limit
        case .overloaded, .server: .down
        case .unsupported, .malformed, .noTools, nil: .other
        case .cancelled: nil
        }
    }

    /// The line for `kind`, naming the service (`title`, e.g. "Groq").
    static func line(_ kind: Kind, title: String, english: Bool) -> String {
        // Where the key and the model are changed, in the settings window's own names (ArisSettingsNames: the eleventh VM
        // run, E2, was sent to "설정 › AI 서비스 › 두뇌", a page that is gone).
        let place = ArisSettingsNames.aiPlace(english: english)
        switch (kind, english) {
        case (.key, false): return "\(title) API 키가 맞지 않아요. \(place)에서 키를 다시 넣어 주세요."
        case (.key, true): return "\(title) didn't accept its API key. Enter the key again in \(place)."
        case (.tooLong, false): return "대화가 너무 길어져서 \(title)가 답하지 못했어요. 새 대화에서 다시 물어봐 주세요."
        case (.tooLong, true): return "The conversation got too long for \(title) to answer. Please ask again in a new conversation."
        case (.unreachable, false): return "\(title)에 닿지 못했어요. 인터넷 연결(로컬 서버면 켜져 있는지)을 확인해 주세요."
        case (.unreachable, true): return "Couldn't reach \(title). Check the internet connection (for a local server, that it's running)."
        case (.limit, false): return "\(title) 사용 한도에 닿았어요. 잠시 뒤에 다시 해 주세요."
        case (.limit, true): return "\(title) has reached its limit. Please try again in a little while."
        case (.down, false): return "\(title) 서버에 문제가 있어요. 잠시 뒤에 다시 해 주세요."
        case (.down, true): return "\(title) is having trouble on its side. Please try again in a little while."
        case (.other, false): return "\(title)가 답하지 못했어요. 다시 해 보시고, 계속되면 \(place)에서 모델을 확인해 주세요."
        case (.other, true): return "\(title) couldn't answer. Try again; if it keeps happening, check the model in \(place)."
        }
    }

    /// The English of a Korean line made by `line`, or nil when `korean` is no such line. The service's name is read
    /// back from where the Korean line has it (a name with any characters, as a connection's own name may be).
    static func english(_ korean: String) -> String? {
        for kind in Kind.allCases {
            let template = line(kind, title: "\u{0}", english: false)
            guard let marker = template.range(of: "\u{0}") else { continue }
            let head = String(template[..<marker.lowerBound]), tail = String(template[marker.upperBound...])
            guard korean.hasPrefix(head), korean.hasSuffix(tail), korean.count > head.count + tail.count else { continue }
            let title = String(korean.dropFirst(head.count).dropLast(tail.count))
            return line(kind, title: title, english: true)
        }
        return nil
    }
}
