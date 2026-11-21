// Tests for jv-voiceyes (the owner: "카드가 ‘실행할까요?’ 물을 때 말로 응 해도 안 되고 버튼을 눌러야 해요"; their log, 03:43 at
// night: a job he had asked for 7 s before put up its card with "the card waits for a click, Y or N (no microphone)").
// The pure word table is in Tests/ArisCoreTests/ArisAnswerWordsTests; here: whose card it is (ArisCardOwner), what the
// card says about hearing (ArisCardHearing), the card's own reading of the wider yes words, and the wiring.
// Called from main.swift; uses its check().
import Foundation

private let voiceyesRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func voiceyesSource(_ path: String) -> String { (try? String(contentsOf: voiceyesRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runVoiceyesTests() {
    voiceyesOwnerTests()
    voiceyesWordsTests()
    voiceyesHearingTests()
    voiceyesWiringTests()
}

// MARK: - 1: a card for what the user just asked is a reply to them

private func voiceyesOwnerTests() {
    typealias O = ArisCardOwner
    check(O.recent == 300, "voiceyes 1: his own request counts as just asked for five minutes")
    // askedAgo (nil: nobody asked, a schedule's), conversationOpenFor (nil: closed), screenAway -> a reply to them
    let table: [(TimeInterval?, TimeInterval?, Bool, Bool)] = [
        // The log's case: asked 7 s ago, no conversation, screen on.
        (7, nil, false, true),
        (0, nil, false, true), (300, nil, false, true), (7, 20, false, true), (7, 3, false, true),
        // Long after, no conversation: Aris's own initiative.
        (301, nil, false, false), (3600, nil, false, false),
        // Long after, but the conversation he asked in is still open.
        (500, 520, false, true), (500, 500, false, true),
        // A conversation opened after the request is another one.
        (500, 60, false, false), (3600, 590, false, false),
        // Nobody asked (a schedule's card), whatever else holds.
        (nil, nil, false, false), (nil, 20, false, false), (nil, 4000, false, false),
        // The screen is locked or asleep: never a reply.
        (7, nil, true, false), (7, 20, true, false), (500, 520, true, false), (nil, nil, true, false), (nil, 20, true, false), (3600, nil, true, false),
        // A clock that went backwards proves nothing.
        (-5, nil, false, false), (-5, 20, false, false),
    ]
    for (asked, open, away, expected) in table {
        check(O.isReply(askedAgo: asked, conversationOpenFor: open, screenAway: away) == expected,
              "voiceyes 1: asked \(asked.map { "\($0) s ago" } ?? "by nobody"), conversation \(open.map { "open \($0) s" } ?? "closed"), screen \(away ? "away" : "on") -> \(expected ? "a reply to the user" : "Aris's own")")
    }
    // With the quiet rule, every combination: what changes is only night for a reply; mute and everything unprompted stay.
    for (asked, open, away, _) in table {
        for muted in [false, true] {
            for night in [false, true] {
                let starter = O.starter(askedAgo: asked, conversationOpenFor: open, screenAway: away)
                let moment = ArisQuiet.Moment(screenAway: away, night: night)
                let verdict = ArisQuiet.decide(starter: starter, muted: muted, moment: moment)
                let before = ArisQuiet.decide(starter: .aris, muted: muted, moment: moment)
                let label = "asked \(String(describing: asked)), open \(String(describing: open)), away \(away), muted \(muted), night \(night)"
                if muted { check(verdict == .textOnly(.muted), "voiceyes 1: muted is text only, always (\(label))") }
                if away { check(!verdict.isAloud && verdict == before, "voiceyes 1: screen away is text only as before (\(label))") }
                if starter == .aris { check(verdict == before, "voiceyes 1: an unprompted card is exactly as before (\(label))") }
                if starter == .user, !muted { check(verdict.isAloud, "voiceyes 1: a reply to them is read aloud and listens, also at night (\(label))") }
                check(!before.isAloud || verdict.isAloud, "voiceyes 1: nothing that spoke before goes quiet (\(label))")
            }
        }
    }
    check(O.starter(askedAgo: 7, conversationOpenFor: nil, screenAway: false) == .user && O.starter(askedAgo: nil, conversationOpenFor: 9, screenAway: false) == .aris,
          "voiceyes 1: the starter is the user for a reply, Aris otherwise")
    // The log's night: 03:43 with the standard hours.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let night = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 3, minute: 43))!
    check(ArisQuietGate.verdict(.aris, muted: false, hours: ArisQuietHours.standard, screenAway: false, now: night, calendar: calendar) == .textOnly(.night)
          && ArisQuietGate.verdict(O.starter(askedAgo: 7, conversationOpenFor: nil, screenAway: false), muted: false, hours: ArisQuietHours.standard,
                                   screenAway: false, now: night, calendar: calendar) == .aloud,
          "voiceyes 1: 03:43, a job asked for 7 s ago: its card was text only as Aris's own, and is aloud as a reply")
    check(ArisQuietGate.verdict(O.starter(askedAgo: 7, conversationOpenFor: nil, screenAway: false), muted: true, hours: ArisQuietHours.standard,
                                screenAway: false, now: night, calendar: calendar) == .textOnly(.muted),
          "voiceyes 1: the same card with Aris muted stays text only")
}

// MARK: - 2: the card reads the wider yes words

private func voiceyesWordsTests() {
    for yes in ["실행해", "실행 해", "실행해 줘", "허용", "허용해", "허용 해", "진행해", "해", "어 해", "응응", "그렇게 해", "해도 돼", "해도 돼요", "run it", "allow it"] {
        check(ArisConfirmReply.parse(yes) == true, "voiceyes 2: “\(yes)” -> yes")
    }
    for no in ["실행하지 마", "허용 안 해", "진행하지 마", "안 해도 돼", "don't run it"] {
        check(ArisConfirmReply.parse(no) == false, "voiceyes 2: “\(no)” -> no")
    }
    for none in ["해 줘 말고", "어", "음", "허용하지 않아", "실행", "내일로 해", "해도 돼?", "실행해 보고 알려 줘"] {
        check(ArisConfirmReply.parse(none) == nil, "voiceyes 2: “\(none)” -> no answer")
    }
    // A streaming yes still has to hold still: "실행해" may grow into "실행해선 안 돼".
    let heard = ArisSpokenAnswer().heard("실행해", at: 10)
    check(heard.answer(at: 10.3, voiceYes: true) == nil && heard.answer(at: 10.7, voiceYes: true) == true,
          "voiceyes 2: a spoken “실행해” counts only once it held still for 0.6 s")
    check(heard.heard("실행해선 안 돼", at: 10.4).answer(at: 10.4, voiceYes: true) == false, "voiceyes 2: grown into a no, it is a no at once")
    // A spoken change of the card is still a change, never a yes.
    var listening = ArisCardListening().heard("내일로 해", at: 1)
    check(listening.answer(at: 5, voiceYes: true) == nil, "voiceyes 2: “내일로 해” is no yes")
    listening = ArisCardListening().heard("해", at: 1)
    check(listening.answer(at: 1.2, voiceYes: true) == nil && listening.answer(at: 1.7, voiceYes: true) == true, "voiceyes 2: “해” alone is a yes after it held still")
}

// MARK: - 3: the card says whether it hears

private func voiceyesHearingTests() {
    typealias H = ArisCardHearing
    check(H.words(.clickOnly, english: false) == "지금은 듣지 않아요. 눌러서 답해 주세요." && H.words(.clickOnly, english: true) == "Not listening. Click to answer."
          && H.words(.clickOnly, english: true, keys: true) == "Not listening. Click or press Y / N.",
          "voiceyes 3: a card that waits for a click says it does not hear, in both languages")
    check(H.words(.listening, english: false) == "듣는 중 · “응” 또는 “아니”" && H.words(.listening, english: true) == "Listening · say yes or no",
          "voiceyes 3: a card that listens says so, in both languages")
    for hearing in [H.listening, .clickOnly] {
        for english in [false, true] { check(H.words(hearing, english: english).count <= 40, "voiceyes 3: a few plain words (\(H.words(hearing, english: english)))") }
    }
    // Which card it is about: another card's state is never shown on this one.
    var ear = ArisCardEarState()
    check(ear.hearing(card: "a") == nil, "voiceyes 3: nothing is said before the card knows")
    ear = ear.setting(.listening, card: "a")
    check(ear.hearing(card: "a") == .listening && ear.hearing(card: "b") == nil, "voiceyes 3: the sign belongs to its own card")
    ear = ear.setting(.clickOnly, card: "a")
    check(ear.hearing(card: "a") == .clickOnly, "voiceyes 3: when the microphone closes, the card says it waits for a click")
    check(ear.clearing(card: "b").hearing(card: "a") == .clickOnly && ear.clearing(card: "a").hearing(card: "a") == nil,
          "voiceyes 3: a card that closes takes only its own sign away")
}

// MARK: - 4: wiring

private func voiceyesWiringTests() {
    let tasks = voiceyesSource("Aris/private/Aris/ArisController+Tasks.swift")
    let park = voiceyesSource("Aris/private/Aris/ArisController+CardPark.swift")
    let team = voiceyesSource("Aris/private/Aris/ArisController+Team.swift")
    let inbox = voiceyesSource("Aris/private/Aris/ArisController+Inbox.swift")
    let card = voiceyesSource("Aris/private/Aris/Home/ArisConfirmCard.swift")
    let view = voiceyesSource("Aris/private/Aris/Home/ArisCardHearingNote.swift")
    check(team.contains("settleCard(ask, title: job.title, job: job.id, asked: job.created, handsFree: handsFree)"),
          "voiceyes 4: a job's card carries when the user asked for the job")
    check(inbox.contains("settleCard(ask, title: item.title, job: nil, asked: nil, handsFree: false"), "voiceyes 4: a schedule's card was asked for by nobody")
    check(park.contains("ArisCardOwner.isReply(askedAgo: asked.map { Date().timeIntervalSince($0) }")
          && park.contains("!quietNow &&") && park.contains("self.speakUp(title, reply: reply)"),
          "voiceyes 4: whose card it is is decided as the card comes up, and never for one the user opened himself")
    check(tasks.contains("reply ? await work() : await ArisQuietGate.unprompted(title, reading: shown ?? text) { await work() }"),
          "voiceyes 4: a reply is not delivered as Aris's own announcement (the one quiet gate then lets it speak and listen)")
    // The guards are where they were.
    check(tasks.contains("if quiet || !ArisQuietGate.maySpeak(heard: session.heard) { return await clickAnswer(ask, key: key, waiter: waiter) }"),
          "voiceyes 4: the card's one quiet question is unchanged (mute, quiet time, a card the user opened: a click only)")
    check(tasks.contains("!(await spokenYesCounts(listener.recordedSamples))"), "voiceyes 4: a spoken yes is still checked against the owner's voice")
    check(tasks.contains("static let answerWait: Duration = .seconds(7)"), "voiceyes 4: the listening window is unchanged")
    // The sign follows the microphone.
    check(tasks.contains("ArisCardEar.shared.set(.clickOnly, card: ask.id)") && tasks.contains("ArisCardEar.shared.set(.listening, card: ask.id)")
          && tasks.contains("ArisCardEar.shared.clear(card: ask.id)"),
          "voiceyes 4: the card is told when it listens, when it waits for a click, and when it closes")
    if let click = tasks.range(of: "private func clickAnswer"), let said = tasks.range(of: "ArisCardEar.shared.set(.clickOnly, card: ask.id)", range: click.upperBound..<tasks.endIndex) {
        check(tasks.distance(from: click.upperBound, to: said.lowerBound) < 400, "voiceyes 4: every click-only wait says so (clickAnswer itself)")
    } else {
        check(false, "voiceyes 4: every click-only wait says so (clickAnswer itself)")
    }
    if let unclear = tasks.range(of: "no clear answer: the card waits for a click, Y or N\")") {
        check(tasks[unclear.upperBound...].prefix(200).contains("ArisCardEar.shared.set(.clickOnly, card: ask.id)"),
              "voiceyes 4: after the listening window the card says it waits for a click")
    } else {
        check(false, "voiceyes 4: after the listening window the card says it waits for a click")
    }
    check(card.contains("ArisCardHearingNote(") && card.contains("@ObservedObject private var ear = ArisCardEar.shared"), "voiceyes 4: the card's footer shows the sign")
    check(!view.contains("repeatForever") && !view.contains("TimelineView") && !view.contains("symbolEffect"),
          "voiceyes 4: the sign never blinks or pulses")
}
