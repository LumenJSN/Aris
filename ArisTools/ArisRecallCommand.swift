//
//  ArisRecallCommand.swift
//  aris-tools
//
//  `recall`: Aris's own record of past work (ArisWorkMemory), for a brain that wants to know how it did something last
//  time instead of exploring again, and for the user at a terminal.
//    recall [<words>] [--limit N]   lessons and past episodes about the words (the latest when none): id, when, how it
//                                   ended, one line
//    recall --id E12 | --id L3      one episode's steps, or one lesson and what it is based on
//    recall --stats                 whether it saved anything
//    … --tainted                    also what came from turns that read outside content
//  The first line printed is the taint mark of everything after it. Without --tainted nothing a tainted turn left is
//  printed (only how many more there are); the gates count `--tainted` as a read of outside text
//  (ArisWorkRecallWords), so a turn that pulls one is tainted from there on.
//

import Foundation

func recall(_ arguments: [String]) {
    guard let call = ArisWorkRecallWords.parse(arguments) else { fail(ArisWorkRecallWords.usage) }
    let store = ArisWorkStore(memory: ArisMemoryStore.at(arisFolder))
    guard store.isOn else { return print("(learning from work is switched off in Settings › 기억: nothing is recorded or recalled)") }
    if call.stats {
        // Numbers only: counts of turns, steps, seconds and tokens, and each lesson's own line.
        return print(ArisWorkStats.text(ArisWorkStats.summary(episodes: store.episodes(tainted: true, limit: ArisWorkStore.capacity), lessons: store.lessons())))
    }
    if let id = call.lesson {
        guard let lesson = store.lessons(expired: true).first(where: { $0.id == id }) else { fail("no lesson L\(id)") }
        return print(ArisWorkRecall.detail(lesson))
    }
    if let id = call.episode {
        guard let episode = store.episode(id: id) else { fail("no episode E\(id)") }
        // One from a tainted turn is shown only when it was asked for as that.
        guard episode.clean || call.tainted else {
            fail("E\(id) is from a turn that read outside content (\(episode.taint.mark)). `recall --id E\(id) --tainted` shows it, and this turn then counts as having read outside text.")
        }
        return print(ArisWorkRecall.detail(episode))
    }
    let all = store.episodes(tainted: call.tainted)
    let found = ArisWorkRecall.matching(all, query: call.query)
    let hidden = call.tainted ? 0 : ArisWorkRecall.matching(store.episodes(tainted: true), query: call.query).filter { !$0.clean }.count
    let lessons = ArisWorkRecall.matching(store.lessons(), query: call.query)
    print(ArisWorkRecall.index(lessons: Array(lessons.prefix(call.limit)), episodes: Array(found.prefix(call.limit)), hiddenTainted: hidden))
}
