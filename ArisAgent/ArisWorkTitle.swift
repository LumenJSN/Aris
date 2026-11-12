//
//  ArisWorkTitle.swift
//  aris-agent
//
//  An episode's one-line title: the only place the work memory uses language. The on-device model (the one the
//  person memory uses: nothing leaves the Mac, no brain's quota is spent) is fed only the user's own words and Aris's
//  structured record of the steps, and only for a clean episode; its line is kept only when it is in that input (most
//  of its syllable pairs and words are: the person memory's own check), is one short line and holds no secret.
//  Otherwise, and for every tainted episode, the title is made by rule: their words, cut. Foundation only (tested).
//

import Foundation

enum ArisWorkTitle {
    static let limit = 60
    /// A model's title is kept when this much of it is in what it was given.
    static let grounding = 0.7

    /// What the model is given: their words, then each step as Aris recorded it.
    static func input(_ episode: ArisWorkEpisode) -> String {
        (["asked: " + episode.asked] + episode.steps.prefix(8).map { "\($0.status): \($0.line)" }
            + episode.made.prefix(3).map { "made: \($0.value)" }).joined(separator: "\n")
    }

    /// Whether the model is asked at all: a clean episode with their words and at least two steps (one step is its own title).
    static func asksModel(_ episode: ArisWorkEpisode) -> Bool { episode.clean && !episode.asked.isEmpty && episode.steps.count >= 2 }

    /// The model's line when it may be kept; nil for anything else.
    static func checked(_ title: String?, for episode: ArisWorkEpisode) -> String? {
        guard let title, asksModel(episode) else { return nil }
        let line = ArisMemoryText.cleaned(title)
        guard line.count >= 4, line.count <= limit + 20, !title.contains("\n"), !ArisWorkSafe.looksSecret(line),
              ArisMemoryText.groundedness(line, in: input(episode)) >= grounding else { return nil }
        return String(line.prefix(limit))
    }

    /// The title by rule: their words, cut; with none, the steps.
    static func plain(_ episode: ArisWorkEpisode) -> String {
        let words = episode.asked.isEmpty ? episode.steps.prefix(3).map(\.line).joined(separator: " → ") : episode.asked
        return words.count > limit ? String(words.prefix(limit - 1)) + "…" : words
    }
}
