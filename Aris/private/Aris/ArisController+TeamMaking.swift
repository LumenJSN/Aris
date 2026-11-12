//
//  ArisController+TeamMaking.swift
//  Aris
//
//  Zero setup for teammates in the notch: "문서 정리하는 팀원 하나 만들어줘, 이름은 코디" is read with no AI (ArisTeamMaking:
//  the name from the user's words, the routing line, instructions and scopes from the matching template, the main brain),
//  and the notch shows it on a card; it is saved only on 확인 (수정 saves it and opens Settings › 팀원 on it; 취소 drops it). And after the same kind
//  of job came up several times, Aris offers once to make a teammate for it (ArisTeamSuggestion); a no is final for
//  that kind.
//

import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "team")

extension ArisController {
    /// Shows the teammate the words ask for on the card (nothing saved yet) and asks; the reply to remember.
    func makeTeammate(_ request: ArisTeamMaking.Request) async -> String {
        let team = ArisTeamModel.shared
        // The list may not be in yet (the agent was starting): one more look, briefly.
        if team.load != .ready {
            team.refresh()
            for _ in 0..<20 where team.load != .ready { try? await Task.sleep(for: .milliseconds(100)) }
        }
        let brain = ArisBrain.named(Defaults[.arisBrain]).rawValue
        let said: String
        if let mate = team.preview(request, brain: brain, aris: ArisFace.current) {
            log.notice("a teammate asked for in words: card up")
            team.made = ArisTeamMade(heard: session.heard, preview: mate, request: request, brain: brain)
            said = ArisTeamCopy.madeAsk(mate.name)
        } else {
            said = team.teammates.count >= ArisTeamEditing.maxTeammates ? ArisTeamCopy.madeFull : ArisTeamCopy.madeFailed
        }
        session = session.answering(said)
        stats?.firstSound(at: .now)
        await speak { await self.speaker.speak(said) }
        return said
    }

    /// A spoken or typed yes or no for the new-teammate card (BUG-25c): a yes makes it only where a spoken yes counts
    /// (never hands-free or in an open conversation: then the card's button), a no drops it. The reply to remember.
    func answerMadeCard(_ yes: Bool) async -> String {
        let team = ArisTeamModel.shared
        let said: String
        if yes, !ArisTeamMadeAnswer.makes(yes: true, typed: turnTyped, inConversation: conversation.isOpen, handsFree: turnHandsFree) {
            said = ArisTeamCopy.madePress
        } else if yes {
            // Said only once the agent stored it (audit team-11): a save that failed is told as one.
            let mate = await team.confirmMadeAndWait(aris: ArisFace.current)
            said = ArisTeamSaveRule.madeLine(saved: mate != nil, name: mate?.name ?? "")
        } else {
            team.made = nil
            said = ArisTeamCopy.madeDropped
        }
        session = session.answering(said)
        stats?.firstSound(at: .now)
        await speak { await self.speaker.speak(said) }
        return said
    }

    /// 수정 on the made card: saved (the user pressed it), then Settings › 팀원 on it.
    func editMadeTeammate() {
        guard let id = ArisTeamModel.shared.confirmMade(aris: ArisFace.current) else { return }
        ArisTeamModel.shared.openOn = id
        ArisSettingsNav.shared.page = .team
        ArisSettingsWindow.shared.show()
    }

    /// The job for the teammate `words` call by name (BUG-25b), with the list read first if it isn't in yet.
    func teammateCalled(_ words: String) async -> ArisJobSpec? {
        let team = ArisTeamModel.shared
        if team.load != .ready {
            team.refresh()
            for _ in 0..<10 where team.load != .ready { try? await Task.sleep(for: .milliseconds(100)) }
        }
        return ArisTeamRouting.directJob(words, teammates: team.teammates)
    }

    /// A request to remove a teammate (BUG-26), with the list read first if it isn't in yet.
    func teammateRemoval(_ words: String) async -> ArisTeamRemoval? {
        let team = ArisTeamModel.shared
        guard ArisTeamRemoval.parse(words, teammates: team.teammates + [.claudeCode]) != nil || words.contains("팀원")
                || words.range(of: #"(?i)\bteammate\b"#, options: .regularExpression) != nil else { return nil }
        if team.load != .ready {
            team.refresh()
            for _ in 0..<10 where team.load != .ready { try? await Task.sleep(for: .milliseconds(100)) }
        }
        return ArisTeamRemoval.parse(words, teammates: team.teammates)
    }

    /// Asks with the settings' 빼기 confirmation and removes the teammate only on a yes; the reply to remember.
    func removeTeammate(_ removal: ArisTeamRemoval) async -> String {
        let said: String
        switch removal {
        case .fixed: said = ArisTeamCopy.removeFixed
        case .unknown: said = ArisTeamCopy.removeNone
        case .teammate(let mate):
            // Removing a teammate is answered by the card's button or Y, never a spoken yes (as a hands-free card).
            let yes = await askUser(ArisTeamRemoval.confirmation(for: mate), handsFree: true)
            // The user started another turn over the card: nothing is removed, shown or said over it (audit card-1).
            guard !Task.isCancelled else { return ArisTeamCopy.removeKept }
            session = session.answered()
            if yes {
                let team = ArisTeamModel.shared
                // "뺐어요" only once the agent stored the list; a failed save leaves the teammate and says so.
                let saved = await team.applyAndWait(ArisTeamEditing.removing(mate.id, from: team.teammates))
                said = ArisTeamSaveRule.removedLine(saved: saved, name: mate.name)
            } else {
                // No answer at all isn't a no (QA BUG-39).
                said = cardUnanswered ? ArisCardWait.unansweredLine(korean: !ArisUILanguage.english)
                    : ArisTeamCopy.removeKept
            }
        }
        session = session.answering(said)
        stats?.firstSound(at: .now)
        await speak { await self.speaker.speak(said) }
        return said
    }

    // MARK: - The suggestion

    /// A job of the user's own words finished: counted, and when that kind has come up often enough (and no teammate does
    /// it, and it was never offered), Aris asks once at the next pause.
    func noteFinishedJob(_ words: String) {
        let store = ArisTeamSuggestionStore.self
        let (next, kind) = store.load().recording(words, at: Date(), teammates: ArisTeamModel.shared.teammates)
        store.save(kind.map(next.asking) ?? next)
        guard let kind else { return }
        Task { [weak self] in await self?.offerTeammate(kind) }
    }

    private func offerTeammate(_ kind: ArisWorkKind) async {
        let template = ArisTeamTemplate.of(kind)
        let question = ArisTeamCopy.suggest(template.label)
        let ask = ArisConfirmation(id: "team-suggest-" + UUID().uuidString, title: ArisTeamCopy.suggestTitle, detail: question)
        guard let yes = await announce(present: true, { await self.speakUp(ArisTeamCopy.suggestTitle) { await self.askUser(ask) } }) ?? nil else { return }
        if yes {
            let request = ArisTeamMaking.Request(role: nil, name: nil, template: template)
            let brain = ArisBrain.named(Defaults[.arisBrain]).rawValue
            let team = ArisTeamModel.shared
            if let mate = team.preview(request, brain: brain, aris: ArisFace.current) {
                let saved = await team.applyAndWait(team.teammates + [mate])
                let said = ArisTeamSaveRule.madeLine(saved: saved, name: mate.name)
                _ = await speakUp(ArisTeamCopy.madeTitle, saying: said) { await self.speak { await self.speaker.speak(said) } }
            }
        } else {
            let said = ArisTeamCopy.suggestLater
            _ = await speakUp(ArisTeamCopy.suggestTitle, saying: said) { await self.speak { await self.speaker.speak(said) } }
        }
    }
}

/// Where the suggestion's counts live (the app's own defaults; nothing of the user's words, only kinds and dates).
enum ArisTeamSuggestionStore {
    static let key = "arisTeamSuggestion"
    nonisolated(unsafe) static var store: UserDefaults = .standard

    static func load() -> ArisTeamSuggestion {
        store.data(forKey: key).flatMap { try? JSONDecoder().decode(ArisTeamSuggestion.self, from: $0) } ?? ArisTeamSuggestion()
    }

    static func save(_ value: ArisTeamSuggestion) {
        if let data = try? JSONEncoder().encode(value) { store.set(data, forKey: key) }
    }
}
