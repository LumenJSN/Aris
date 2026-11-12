//
//  ArisWorkLive.swift
//  aris-agent
//
//  The agent's own work-memory desk: memory.sqlite in Aris's folder, the activity log beside it, and Apple's on-device
//  model for an episode's one-line title (as the person memory uses it: ArisMemoryOnDevice). Its line is never
//  trusted as it comes (ArisWorkTitle.checked); nil whenever the model isn't there, is too slow or fails.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum ArisWorkOnDevice {
    static let timeout: TimeInterval = 6

    private static let instructions = """
        You label one finished task of a personal assistant in one short line (at most eight words), in the language \
        of the user's request. Use only the words of the request and of the recorded steps below. No advice, no \
        quotation marks, nothing that was not in the input.
        """

    /// One line about `episode` from the model (unchecked), or nil. Asked only for an episode ArisWorkTitle would ask for.
    static func title(_ episode: ArisWorkEpisode) -> String? {
        guard ArisWorkTitle.asksModel(episode) else { return nil }
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability else { return nil }
        let input = ArisWorkTitle.input(episode)
        let box = ArisWorkTitleBox()
        let done = DispatchSemaphore(value: 0)
        let task = Task {
            box.set(try? await LanguageModelSession(instructions: instructions).respond(to: input).content)
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            return nil
        }
        return box.value
        #else
        return nil
        #endif
    }
}

private final class ArisWorkTitleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    func set(_ value: String?) { lock.withLock { stored = value } }
    var value: String? { lock.withLock { stored } }
}

extension ArisWorkDesk {
    /// The agent's desk: ~/.config/aris/aris/memory.sqlite, activity.jsonl and the on-device model.
    static let live = ArisWorkDesk(store: .live, tools: ArisAgentRunner.toolsPath, home: FileManager.default.homeDirectoryForCurrentUser.path,
                                   log: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/aris/activity.jsonl"),
                                   title: ArisWorkOnDevice.title)
}

extension ArisWorkDesk {
    /// The answer to "어제 그 파일 어디 저장했지" or "지난번에 … 어떻게 했지" from the episodes, or nil (not such a question,
    /// not the user's own plain turn from the app, the switch off, or nothing that clearly matches: the brain takes the turn).
    /// Reads the store, and only when the words are such a question.
    func localAnswer(_ request: String, fromApp: Bool, handsFree: Bool, plain: Bool) -> ArisWorkIntent.Answer? {
        guard fromApp, !handsFree, plain, let intent = ArisWorkIntent.parse(request), store.isOn else { return nil }
        let korean = ArisMemoryText.isKorean(request) || !request.contains(where: \.isLetter)
        guard let answer = ArisWorkIntent.answer(intent, episodes: store.episodes(tainted: true), now: Date(), korean: korean) else { return nil }
        ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["action": intent.auditName + (answer.tainted ? " (from a tainted episode)" : ""), "risk": "spoken"]), key: "local")
        return answer
    }

    /// The owner's "…잊어" when no memory about them matches the words and a lesson does (ArisWorkIntent.forget); nil otherwise.
    func forgetAnswer(_ intent: ArisMemoryIntent, said: String) -> String? {
        guard case .forget(let words) = intent, store.memory.matching(words).isEmpty, store.memory.overlapping(words).isEmpty else { return nil }
        let korean = ArisMemoryText.isKorean(said) || !said.contains(where: \.isLetter)
        guard let answer = ArisWorkIntent.forget(words, store: store, korean: korean) else { return nil }
        refresh()
        return answer
    }
}
