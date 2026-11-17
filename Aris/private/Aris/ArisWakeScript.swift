//
//  ArisWakeScript.swift
//  Aris
//
//  What Settings › 대화 › 호출어 녹음 asks the user to say, in order: about a hundred calls of the name the way they really
//  calls it (plainly, casually with a word in front, quietly, from across the room, over music, into AirPods, with a
//  request right after it) and the words most like it, ten times each. Each take is one fixed window of audio, so a
//  quiet call that a loudness gate would miss is kept too (it is exactly what a detector must learn). The takes are
//  labelled for the wake word's bench and its training (ArisWakeCorpus); nothing here touches the microphone.
//  Foundation only (tested).
//

import Foundation

/// One line to say, and how.
struct ArisWakePrompt: Equatable, Codable {
    /// The name, or a word that only sounds like it.
    enum Label: String, Codable, CaseIterable { case call, confusable }
    enum Style: String, Codable, CaseIterable { case normal, casual, quiet }
    enum Distance: String, Codable, CaseIterable { case near, far }
    enum Background: String, Codable, CaseIterable { case quiet, music }
    /// Which microphone the take asks for: the Mac's own, or the AirPods' (a headset's, when one is connected).
    enum Mic: String, Codable, CaseIterable { case builtIn = "built-in", airPods = "airpods" }

    /// Stable across versions of the script: the take's file is named after it.
    let id: String
    let phrase: String
    let label: Label
    var style = Style.normal
    var distance = Distance.near
    var background = Background.quiet
    var mic = Mic.builtIn
    let takes: Int

    /// How long one take records: the line and a little room on both sides.
    var seconds: Double { phrase.count > 8 ? 3.5 : 2.5 }
}

/// A group of prompts said the same way, with the one instruction shown before it.
struct ArisWakeBlock: Equatable {
    let id: String
    let title: String
    let how: String
    let prompts: [ArisWakePrompt]
    /// The block can be left out (no AirPods here, no music to play): the rest still counts.
    var optional = false

    var takes: Int { prompts.reduce(0) { $0 + $1.takes } }
}

/// One take to record: a prompt and which of its takes.
struct ArisWakeStep: Equatable {
    let block: ArisWakeBlock
    let prompt: ArisWakePrompt
    /// 1-based.
    let take: Int

    /// The take's key in the manifest and its file name: "call-plain-aris-t03".
    var key: String { String(format: "%@-t%02d", prompt.id, take) }
}

enum ArisWakeScript {
    /// The calls (100) and the confusable words (7 × 10).
    static let blocks: [ArisWakeBlock] = [
        ArisWakeBlock(id: "plain", title: "평소처럼", how: "Mac 앞에서 평소에 부르듯이 불러 주세요.", prompts: [
            ArisWakePrompt(id: "call-plain-aris", phrase: "아리스", label: .call, takes: 20),
        ]),
        ArisWakeBlock(id: "casual", title: "편하게", how: "앞에 말을 붙이거나 영어로, 편하게 불러 주세요.", prompts: [
            ArisWakePrompt(id: "call-casual-eo", phrase: "어 아리스", label: .call, style: .casual, takes: 5),
            ArisWakePrompt(id: "call-casual-ya", phrase: "아리스야", label: .call, style: .casual, takes: 5),
            ArisWakePrompt(id: "call-casual-hey", phrase: "헤이 아리스", label: .call, style: .casual, takes: 5),
            ArisWakePrompt(id: "call-casual-en", phrase: "Aris", label: .call, style: .casual, takes: 5),
        ]),
        ArisWakeBlock(id: "quiet", title: "작게", how: "옆 사람이 깨지 않을 만큼 작게 불러 주세요.", prompts: [
            ArisWakePrompt(id: "call-quiet-aris", phrase: "아리스", label: .call, style: .quiet, takes: 10),
        ]),
        ArisWakeBlock(id: "far", title: "멀리서", how: "Mac에서 2~3미터 떨어져서 불러 주세요. 화면의 숫자가 바뀌면 말하면 돼요.", prompts: [
            ArisWakePrompt(id: "call-far-aris", phrase: "아리스", label: .call, distance: .far, takes: 10),
            ArisWakePrompt(id: "call-far-ya", phrase: "아리스야", label: .call, style: .casual, distance: .far, takes: 5),
        ]),
        ArisWakeBlock(id: "music", title: "음악 틀고", how: "스피커로 음악을 평소 크기로 틀어 두고 불러 주세요.", prompts: [
            ArisWakePrompt(id: "call-music-aris", phrase: "아리스", label: .call, background: .music, takes: 10),
            ArisWakePrompt(id: "call-music-hey", phrase: "헤이 아리스", label: .call, style: .casual, background: .music, takes: 5),
        ], optional: true),
        ArisWakeBlock(id: "airpods", title: "AirPods로", how: "AirPods를 끼고 불러 주세요. 이 묶음만 AirPods 마이크로 녹음해요.", prompts: [
            ArisWakePrompt(id: "call-airpods-aris", phrase: "아리스", label: .call, mic: .airPods, takes: 10),
            ArisWakePrompt(id: "call-airpods-ya", phrase: "아리스야", label: .call, style: .casual, mic: .airPods, takes: 5),
        ], optional: true),
        ArisWakeBlock(id: "request", title: "부르고 바로 말하기", how: "이름을 부르고 쉬지 않고 바로 이어서 말해 주세요.", prompts: [
            ArisWakePrompt(id: "call-request-timer", phrase: "아리스, 타이머 삼 분 맞춰 줘", label: .call, takes: 5),
        ]),
        ArisWakeBlock(id: "confusable", title: "헷갈리는 말", how: "이번엔 이름이 아니에요. 화면에 나온 말을 평소처럼 말해 주세요.", prompts: [
            ArisWakePrompt(id: "near-ice", phrase: "아이스", label: .confusable, takes: 10),
            ArisWakePrompt(id: "near-arisu", phrase: "아리수", label: .confusable, takes: 10),
            ArisWakePrompt(id: "near-eoriseu", phrase: "어리스", label: .confusable, takes: 10),
            ArisWakePrompt(id: "near-arirang", phrase: "아리랑", label: .confusable, takes: 10),
            ArisWakePrompt(id: "near-alice", phrase: "앨리스", label: .confusable, takes: 10),
            ArisWakePrompt(id: "near-chris", phrase: "크리스", label: .confusable, takes: 10),
            ArisWakePrompt(id: "near-aristotle", phrase: "아리스토텔레스", label: .confusable, takes: 10),
        ]),
    ]

    /// Every take in the order they are asked for.
    static let steps: [ArisWakeStep] = blocks.flatMap { block in
        block.prompts.flatMap { prompt in (1...prompt.takes).map { ArisWakeStep(block: block, prompt: prompt, take: $0) } }
    }

    static var totalTakes: Int { steps.count }
    static var callTakes: Int { steps.filter { $0.prompt.label == .call }.count }

    /// The first take not yet recorded, leaving out the blocks skipped this time; nil when nothing is left.
    static func next(recorded: Set<String>, skipping skipped: Set<String> = []) -> ArisWakeStep? {
        steps.first { !recorded.contains($0.key) && !skipped.contains($0.block.id) }
    }

    /// How far a block is: its takes recorded, of all of them.
    static func progress(of block: ArisWakeBlock, recorded: Set<String>) -> (done: Int, of: Int) {
        let keys = steps.filter { $0.block.id == block.id }.map(\.key)
        return (keys.filter(recorded.contains).count, keys.count)
    }

    /// The step's line on the sheet: “평소처럼 · 3/20”.
    static func counter(_ step: ArisWakeStep) -> String {
        let inBlock = steps.filter { $0.block.id == step.block.id }
        let index = (inBlock.firstIndex(of: step) ?? 0) + 1
        return "\(step.block.title) · \(index)/\(inBlock.count)"
    }
}
