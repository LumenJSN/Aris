//
//  ArisMemoryOnDevice.swift
//  aris-agent
//
//  Apple's on-device model, for the two memory jobs that need language: picking 0–3 lasting memories out of the user's
//  words after a clean turn, and one paragraph about a day from that day's notes. Nothing leaves the Mac and no
//  brain's quota is spent. Its answers are never trusted as they come: ArisMemoryLearning.accepted keeps only what
//  is in the user's words, and a summary must share most of its words with the notes (else the plain list is used).
//  Nil whenever the model isn't there (no Apple Intelligence), is too slow or fails.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum ArisMemoryOnDevice {
    static let extractTimeout: Duration = .seconds(8)
    static let summaryTimeout: Duration = .seconds(15)
    /// A summary is kept when this much of it is in the notes.
    static let summaryGrounding = 0.5

    private static let extractInstructions = """
        You keep a personal assistant's long-term notes about its user. From the user's own words, pick out at most \
        three things that will still be true and useful weeks from now: preferences and defaults, facts about the user \
        (school, work, where they live), ongoing projects, people they mention and what they call them, routines. Use \
        the user's own words and language. Ignore one-off requests, questions, commands and anything only about today. \
        Most words hold nothing lasting: then return no memories. Never invent anything that wasn't said.
        """

    private static let summaryInstructions = """
        Write one short paragraph (two or three sentences) about what the user worked on during one day, from the \
        user's own requests below. Use only what the requests say. Write in the language of the requests: in Korean, \
        polite 해요체 with no pronoun at all (like "발표 자료를 고치고 장보기 목록을 정리했어요."); in English, \
        address the user as "you". Don't quote the requests or list them. No advice.
        """

    /// The memories the model picks out of `words` (unchecked: the caller filters them), or nil without a model.
    static func extract(_ words: String) -> [ArisMemoryCandidate]? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability else { return nil }
        return wait(extractTimeout) {
            let session = LanguageModelSession(instructions: extractInstructions)
            let reply = try await session.respond(to: "The user said: \(words)", generating: ArisPickedMemories.self)
            return reply.content.memories.map { picked in
                ArisMemoryCandidate(kind: ArisMemoryKind(rawValue: picked.kind.lowercased()) ?? ArisMemoryKind.guess(picked.text),
                                    subject: picked.subject, text: picked.text, confidence: 0.7)
            }
        }
        #else
        return nil
        #endif
    }

    /// One paragraph about the day from its notes, or nil (no model, too slow, or not in the notes' words).
    static func summarize(_ notes: [String]) -> String? {
        #if canImport(FoundationModels)
        guard !notes.isEmpty, #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability else { return nil }
        let joined = notes.map { "- " + $0 }.joined(separator: "\n")
        let text = wait(summaryTimeout) {
            try await LanguageModelSession(instructions: summaryInstructions).respond(to: joined).content
        }
        // A Korean day in Korean only (the model sometimes slips an English "you" in).
        let korean = notes.contains(where: ArisMemoryText.isKorean)
        guard let paragraph = text.map(ArisMemoryText.cleaned), paragraph.count >= 10,
              !korean || !paragraph.lowercased().contains("you"),
              // Never the user's requests word for word.
              !notes.contains(where: { $0.count >= 10 && ArisMemoryText.normalized(paragraph).contains(ArisMemoryText.normalized($0)) }),
              ArisMemoryText.groundedness(paragraph, in: joined) >= summaryGrounding else { return nil }
        return paragraph
        #else
        return nil
        #endif
    }

    /// Runs `work` and waits for it up to `limit` (the memory queue is a background serial queue).
    private static func wait<T: Sendable>(_ limit: Duration, _ work: @escaping @Sendable () async throws -> T) -> T? {
        let box = ArisResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        let task = Task {
            box.set(try? await work())
            done.signal()
        }
        let seconds = Double(limit.components.seconds) + Double(limit.components.attoseconds) / 1e18
        if done.wait(timeout: .now() + seconds) == .timedOut {
            task.cancel()
            return nil
        }
        return box.value
    }
}

private final class ArisResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    func set(_ value: T?) { lock.withLock { stored = value } }
    var value: T? { lock.withLock { stored } }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct ArisPickedMemory {
    @Guide(description: "one of: preference, fact, project, person, routine")
    var kind: String
    @Guide(description: "what it is about, in the user's words; empty if unclear")
    var subject: String
    @Guide(description: "the memory as a short sentence in the user's words and language")
    var text: String
}

@available(macOS 26.0, *)
@Generable
struct ArisPickedMemories {
    @Guide(description: "0 to 3 lasting memories; empty when the words hold nothing lasting about the user", .maximumCount(3))
    var memories: [ArisPickedMemory]
}
#endif

extension ArisMemoryCurator {
    /// The agent's curator: ~/.config/aris/aris/memory.sqlite and the on-device model.
    static let live = ArisMemoryCurator(store: .live, extract: ArisMemoryOnDevice.extract, summarize: ArisMemoryOnDevice.summarize)
}
