//
//  ArisWorkLessons.swift
//  aris-agent
//
//  Lessons, made by rule from the episodes: no model reads anything here, and nothing but Aris's own record goes in.
//  Any conversation turn the user asked from the app teaches, whatever its taint (ArisWorkTaintRule.feedsLessons: not a
//  job, not hands-free); the store refuses any other evidence again. A lesson resting on a turn that read outside
//  content carries that mark (ArisWorkLesson.outside), for Settings › 기억 to show.
//  - way: a request that went "A failed, then C worked" (in one turn, or over two turns of the same kind) becomes
//    "for this kind of request C works here; A fails".
//  - flag: the same command failed and then worked with one more argument: "this command needs this on this Mac".
//  - place: the same command went to the same folder, list or app three times: "this usually goes there".
//  - name: a word of the user's request was the name of the file or folder that worked, twice: "that name is this path".
//  Each repeat that works the same way makes a lesson surer; a later failure of the very way it says works (or the user
//  undoing what it did) makes it less sure, and below a floor it expires and is never offered again.
//  Foundation only (tested).
//

import Foundation

enum ArisWorkLessons {
    /// New lessons one episode may start.
    static let perEpisode = 2
    /// How many times the same target before it is "usually", and the same name before it is that path.
    static let placeRepeats = 3
    static let nameRepeats = 2
    /// How far back an earlier failed turn of the same kind counts.
    static let window: TimeInterval = 30 * 86_400
    static let mostSteps = 4
    static let mostEvidence = 8

    /// What `episode` (already in the store, with its id) teaches: the lessons to save, changed or new. `lessons`: the
    /// store's own, expired ones too; `earlier`: the turns before it that may teach, newest first.
    static func learn(from episode: ArisWorkEpisode, lessons: [ArisWorkLesson], earlier: [ArisWorkEpisode], now: Date) -> [ArisWorkLesson] {
        guard ArisWorkTaintRule.feedsLessons(episode), episode.id > 0, !episode.asked.isEmpty else { return [] }
        let teaching = earlier.filter { ArisWorkTaintRule.feedsLessons($0) && $0.id != episode.id }
        let known = Dictionary((teaching + [episode]).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // The outside mark: any episode a lesson rests on read outside content (the store checks it again).
        let marked = { (lesson: ArisWorkLesson) -> ArisWorkLesson in
            var next = lesson
            next.outside = lesson.outside || ArisWorkTaintRule.outside(lesson.evidence.compactMap { known[$0] })
            return next
        }
        return learnMarked(from: episode, lessons: lessons, earlier: teaching, now: now).map(marked)
    }

    private static func learnMarked(from episode: ArisWorkEpisode, lessons: [ArisWorkLesson], earlier clean: [ArisWorkEpisode], now: Date) -> [ArisWorkLesson] {
        var changed: [ArisWorkLesson] = []
        var live = lessons.filter { !$0.expired }
        // What the episode says about the lessons there are.
        for (index, lesson) in live.enumerated() {
            guard let verdict = verdict(of: episode, on: lesson) else { continue }
            var next = lesson
            next.updatedAt = now
            if verdict {
                guard !next.evidence.contains(episode.id) else { continue }
                next.confidence = hundredths(min(1, next.confidence + ArisWorkLesson.repeatGain))
                next.evidence = Array((next.evidence + [episode.id]).suffix(mostEvidence))
            } else {
                next.confidence = hundredths(max(0, next.confidence - ArisWorkLesson.failureLoss))
                next.expired = next.confidence < ArisWorkLesson.expiresBelow
            }
            live[index] = next
            changed.append(next)
        }
        guard episode.outcome == .done else { return changed }
        let known = live.filter { !$0.expired }
        var fresh: [ArisWorkLesson] = []
        for candidate in [inTurn(episode, now: now), acrossTurns(episode, earlier: clean, now: now), place(episode, earlier: clean, now: now),
                          name(episode, earlier: clean, now: now)].compactMap({ $0 }) {
            guard !(known + fresh).contains(where: { same($0, candidate) }), fresh.count < perEpisode else { continue }
            fresh.append(candidate)
        }
        return changed + fresh
    }

    /// The lessons that rest on episodes the user undid since: each is less sure (what it did wasn't what they wanted).
    static func undone(_ ids: [Int], lessons: [ArisWorkLesson], now: Date) -> [ArisWorkLesson] {
        lessons.filter { !$0.expired && !Set($0.evidence).isDisjoint(with: ids) }.map { lesson in
            var next = lesson
            next.confidence = hundredths(max(0, lesson.confidence - ArisWorkLesson.failureLoss))
            next.expired = next.confidence < ArisWorkLesson.expiresBelow
            next.updatedAt = now
            return next
        }
    }

    /// A confidence in whole hundredths, so three losses from 0.9 land on 0.6, 0.3 and 0, not a hair beside them.
    private static func hundredths(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    /// Two lessons that say the same thing.
    private static func same(_ a: ArisWorkLesson, _ b: ArisWorkLesson) -> Bool {
        guard a.kind == b.kind else { return false }
        let sameWay = a.works.count == b.works.count && zip(a.works, b.works).allSatisfy { $0.sameCall(as: $1) }
        switch a.kind {
        case .way: return sameWay && ArisWorkAsk.same(a.asked, b.asked)
        case .flag, .place, .name: return a.key == b.key && sameWay
        }
    }

    // MARK: - What an episode says about a lesson

    /// True: the episode did what the lesson says works, and it worked. False: it did, and it failed. Nil: it says nothing.
    static func verdict(of episode: ArisWorkEpisode, on lesson: ArisWorkLesson) -> Bool? {
        guard let first = lesson.works.first else { return nil }
        switch lesson.kind {
        case .way:
            guard ArisWorkAsk.same(lesson.asked, episode.asked) else { return nil }
            return wayVerdict(lesson.works, in: episode)
        case .flag:
            return callVerdict(first, in: episode)
        case .place:
            guard let target = first.args.last else { return nil }
            let mine = episode.steps.filter { $0.verb == first.verb && destination(of: $0) == target }
            if mine.contains(where: \.worked) { return true }
            return mine.contains(where: \.failed) ? false : nil
        case .name:
            guard let path = first.args.last, ArisWorkAsk.tokens(episode.asked).contains(lesson.key) else { return nil }
            let mine = episode.steps.filter { $0.args.contains(path) }
            if mine.contains(where: \.worked) { return true }
            return mine.contains(where: \.failed) ? false : nil
        }
    }

    /// Whether the way's steps ran in order and worked; false when its first step ran and never worked.
    private static func wayVerdict(_ way: [ArisWorkStep], in episode: ArisWorkEpisode) -> Bool? {
        var left = way[...]
        for step in episode.steps where step.worked {
            if let next = left.first, next.sameCall(as: step) { left = left.dropFirst() }
        }
        if left.isEmpty, episode.outcome == .done { return true }
        return callVerdict(way[0], in: episode) == false ? false : nil
    }

    /// One call: true when it ran and worked at least once, false when it ran and only failed.
    private static func callVerdict(_ call: ArisWorkStep, in episode: ArisWorkEpisode) -> Bool? {
        let mine = episode.steps.filter { $0.sameCall(as: call) }
        if mine.contains(where: \.worked) { return true }
        return mine.contains(where: \.failed) ? false : nil
    }

    // MARK: - New lessons

    private static func plain(_ step: ArisWorkStep) -> ArisWorkStep {
        ArisWorkStep(tool: step.tool, verb: step.verb, args: step.args, gate: "", status: step.status, ms: 0, clean: step.clean)
    }

    private static func distinct(_ steps: [ArisWorkStep]) -> [ArisWorkStep] {
        var kept: [ArisWorkStep] = []
        for step in steps where !kept.contains(where: { $0.sameCall(as: step) }) { kept.append(plain(step)) }
        return kept
    }

    private static func made(_ kind: ArisWorkLesson.Kind, key: String, asked: String, works: [ArisWorkStep], fails: [ArisWorkStep] = [], evidence: [Int],
                             confidence: Double = ArisWorkLesson.startConfidence, now: Date) -> ArisWorkLesson {
        ArisWorkLesson(kind: kind, key: key, asked: asked, works: Array(works.prefix(mostSteps)), fails: Array(fails.prefix(3)),
                       evidence: Array(evidence.suffix(mostEvidence)), confidence: hundredths(min(1, confidence)), createdAt: now, updatedAt: now)
    }

    /// Something failed and then the turn ended well: what worked, and what failed first. When the one thing that
    /// worked is the failed command with more arguments, the lesson is about the command itself (flag).
    static func inTurn(_ episode: ArisWorkEpisode, now: Date) -> ArisWorkLesson? {
        let ran = episode.steps.filter { $0.worked || $0.failed }
        guard let last = ran.last, last.worked, ran.contains(where: \.failed) else { return nil }
        let works = distinct(ran.filter(\.worked)), fails = distinct(ran.filter(\.failed))
        if works.count == 1, let way = works.first, fails.allSatisfy({ $0.tool == way.tool && $0.verb == way.verb && Set($0.args.map(\.value)).isStrictSubset(of: Set(way.args.map(\.value))) }) {
            return made(.flag, key: way.verb, asked: episode.asked, works: works, fails: fails, evidence: [episode.id], now: now)
        }
        return made(.way, key: episode.key, asked: episode.asked, works: works, fails: fails, evidence: [episode.id], now: now)
    }

    /// This turn went straight through, and an earlier turn of the same kind failed another way: this way works, that
    /// one fails.
    static func acrossTurns(_ episode: ArisWorkEpisode, earlier: [ArisWorkEpisode], now: Date) -> ArisWorkLesson? {
        let ran = episode.steps.filter { $0.worked || $0.failed }
        guard !ran.isEmpty, ran.allSatisfy(\.worked) else { return nil }
        let failed = earlier.filter { other in
            other.at <= episode.at && episode.at.timeIntervalSince(other.at) <= window && ArisWorkAsk.same(other.asked, episode.asked)
                && (other.outcome == .failed || other.steps.last(where: { $0.worked || $0.failed })?.failed == true)
        }
        let fails = distinct(failed.flatMap { $0.steps.filter(\.failed) }).filter { fail in !ran.contains { $0.sameCall(as: fail) } }
        guard !fails.isEmpty else { return nil }
        return made(.way, key: episode.key, asked: episode.asked, works: distinct(ran), fails: fails, evidence: failed.map(\.id).sorted() + [episode.id], now: now)
    }

    /// Flags whose value says where a result goes.
    private static let placeFlags: Set<String> = ["--out", "--to", "--into", "--folder", "--dir", "--list", "--calendar"]

    /// Where a step put its result: the value after a place flag, or for a move the folder it went into.
    static func destination(of step: ArisWorkStep) -> ArisWorkArg? {
        for (index, arg) in step.args.enumerated() where arg.kind == .flag && placeFlags.contains(arg.value) && index + 1 < step.args.count {
            let value = step.args[index + 1]
            if value.kind == .path || value.kind == .name { return value }
        }
        guard step.verb == "move", step.args.count == 2, let last = step.args.last, last.kind == .path else { return nil }
        // "…/학교" is the folder; "…/학교/발표.key" names the file, whose folder it is.
        let name = (last.value as NSString).lastPathComponent
        return name.contains(".") ? ArisWorkArg(kind: .path, value: (last.value as NSString).deletingLastPathComponent) : last
    }

    /// The same command went to the same place in three turns that teach: it usually goes there.
    static func place(_ episode: ArisWorkEpisode, earlier: [ArisWorkEpisode], now: Date) -> ArisWorkLesson? {
        for step in episode.steps where step.worked {
            guard let target = destination(of: step), !target.value.isEmpty else { continue }
            let others = earlier.filter { $0.outcome == .done && $0.steps.contains { $0.worked && $0.verb == step.verb && destination(of: $0) == target } }
            guard others.count + 1 >= placeRepeats else { continue }
            let works = ArisWorkStep(tool: step.tool, verb: step.verb, args: [target], status: "ok", clean: step.clean)
            return made(.place, key: step.verb, asked: episode.asked, works: [works], evidence: others.map(\.id).sorted() + [episode.id],
                        confidence: ArisWorkLesson.startConfidence + Double(others.count + 1 - placeRepeats) * ArisWorkLesson.repeatGain, now: now)
        }
        return nil
    }

    /// A word of his request is in the name of the path that worked, in two turns that teach: that name is this path.
    static func name(_ episode: ArisWorkEpisode, earlier: [ArisWorkEpisode], now: Date) -> ArisWorkLesson? {
        func pairs(_ one: ArisWorkEpisode) -> [(String, ArisWorkArg, ArisWorkStep)] {
            let tokens = ArisWorkAsk.tokens(one.asked).filter { $0.count >= 2 && $0 != "#" }
            return one.steps.filter(\.worked).flatMap { step in
                step.args.filter { $0.kind == .path && $0.value.contains("/") }.flatMap { path -> [(String, ArisWorkArg, ArisWorkStep)] in
                    let last = ArisMemoryText.normalized(((path.value as NSString).lastPathComponent as NSString).deletingPathExtension)
                    return tokens.filter { last.contains(ArisMemoryText.normalized($0)) }.map { ($0, path, step) }
                }
            }
        }
        for (token, path, step) in pairs(episode) {
            let others = earlier.filter { $0.outcome == .done && pairs($0).contains { $0.0 == token && $0.1 == path } }
            guard others.count + 1 >= nameRepeats else { continue }
            let works = ArisWorkStep(tool: step.tool, verb: step.verb, args: [path], status: "ok", clean: step.clean)
            return made(.name, key: token, asked: episode.asked, works: [works], evidence: others.map(\.id).sorted() + [episode.id], now: now)
        }
        return nil
    }
}
