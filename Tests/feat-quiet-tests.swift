// Tests for the mute button and quiet time (ArisQuiet, ArisQuietWords, ArisQuietGate): the one "may Aris make sound
// now?" decision in every combination, the night hours, the spoken mute phrases, the copy, and that every speaking and
// chiming path in the app asks the gate. Called from main.swift; uses its check(). Pure rules and source reads only:
// nothing is spoken, no sound plays, and no preference is written.
import Foundation

func runFeatQuietTests() {
    quietDecisionTests()
    quietStarterTests()
    quietHoursTests()
    quietGateTests()
    quietNoticeTests()
    quietPhraseTests()
    quietIntentTests()
    quietCopyTests()
    quietSettingsTests()
    quietWiringTests()
    quietAnnouncingTestsBlocking()
}

private func quietSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path).standardized, encoding: .utf8)) ?? ""
}

// MARK: - The decision, every combination

private func quietDecisionTests() {
    typealias Q = ArisQuiet
    let moments = [Q.Moment(), Q.Moment(screenAway: true), Q.Moment(night: true), Q.Moment(screenAway: true, night: true)]
    // Muted: nothing sounds, whoever started it and whatever the hour.
    for starter in Q.Starter.allCases {
        for moment in moments {
            check(Q.decide(starter: starter, muted: true, moment: moment) == .textOnly(.muted),
                  "a muted Aris never makes sound (\(starter), away \(moment.screenAway), night \(moment.night))")
        }
    }
    // Not muted, a reply to what the user just asked: always aloud, they is plainly there.
    for moment in moments {
        check(Q.decide(starter: .user, muted: false, moment: moment) == .aloud,
              "a reply to what the user just asked is spoken (away \(moment.screenAway), night \(moment.night))")
        check(Q.decide(starter: .userTimer, muted: false, moment: moment) == .aloud,
              "a timer he set himself still rings (away \(moment.screenAway), night \(moment.night))")
    }
    // Not muted, Aris's own initiative: only outside quiet time.
    check(Q.decide(starter: .aris, muted: false, moment: Q.Moment()) == .aloud, "Aris's own news is spoken in the daytime with the screen on")
    check(Q.decide(starter: .aris, muted: false, moment: Q.Moment(night: true)) == .textOnly(.night), "Aris's own news stays text at night")
    check(Q.decide(starter: .aris, muted: false, moment: Q.Moment(screenAway: true)) == .textOnly(.screenAway),
          "Aris's own news stays text while the screen is locked or asleep")
    check(Q.decide(starter: .aris, muted: false, moment: Q.Moment(screenAway: true, night: true)) == .textOnly(.screenAway),
          "locked at night: still text (the screen is named as the reason)")
    check(Q.Starter.allCases.count * 2 * moments.count == 24, "every combination is covered: 3 starters × muted or not × 4 moments")
    check(Q.Verdict.aloud.isAloud && !Q.Verdict.textOnly(.muted).isAloud && !Q.Verdict.textOnly(.night).isAloud, "only aloud makes sound")
    check(!Q.Moment().isQuiet && Q.Moment(screenAway: true).isQuiet && Q.Moment(night: true).isQuiet, "quiet time is the screen away or the night hours")
}

private func quietStarterTests() {
    typealias Q = ArisQuiet
    check(Q.starter(announcing: [], heard: "오늘 날씨 어때") == .user, "with no announcement going, what the notch says is the user's reply")
    check(Q.starter(announcing: ["메일 정리"], heard: "메일 정리") == .aris, "while Aris's own announcement holds the notch, its words are Aris's initiative")
    check(Q.starter(announcing: ["메일 정리"], heard: "오늘 날씨 어때") == .user,
          "once the user's turn has taken the notch from an announcement, the reply to them is his")
    check(Q.starter(announcing: ["메일 정리", "브리핑"], heard: "브리핑") == .aris, "two announcements overlapping are both Aris's own")
}

// MARK: - Night hours

private func quietHoursTests() {
    typealias H = ArisQuietHours
    check(H(stored: "23-7") == H(stored: H.standard) && H(stored: "23-7")?.start == 23 && H(stored: "23-7")?.end == 7, "the standard night is 23:00 to 07:00")
    check(H(stored: H.off) == nil, "off means no night quiet")
    check(H(stored: "") == H(stored: H.standard) && H(stored: "밤") == H(stored: H.standard) && H(stored: "25-7") == H(stored: H.standard)
          && H(stored: "23-7-1") == H(stored: H.standard),
          "an unreadable stored value is the standard hours, never off")
    let night = H(stored: "23-7")!
    check(night.contains(hour: 23) && night.contains(hour: 0) && night.contains(hour: 6) && !night.contains(hour: 7) && !night.contains(hour: 22) && !night.contains(hour: 12),
          "23-7 wraps past midnight: 23:00 is quiet, 07:00 is not")
    let late = H(stored: "0-8")!
    check(late.contains(hour: 0) && late.contains(hour: 7) && !late.contains(hour: 8) && !late.contains(hour: 23), "0-8 does not wrap")
    check(H.choices == ["off", "22-7", "23-7", "0-8"] && H.choices.dropFirst().allSatisfy { H(stored: $0) != nil }, "the Settings row offers off and three nights")
    check(H.choice(for: "22-7") == "22-7" && H.choice(for: "off") == "off" && H.choice(for: "garbage") == "23-7", "the row shows what is stored, or the standard hours")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let at = { (hour: Int, minute: Int) in calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: hour, minute: minute))! }
    check(H.isNight(at(23, 0), stored: "23-7", calendar: calendar) && H.isNight(at(2, 30), stored: "23-7", calendar: calendar)
          && H.isNight(at(6, 59), stored: "23-7", calendar: calendar), "23:00, 02:30 and 06:59 are night")
    check(!H.isNight(at(7, 0), stored: "23-7", calendar: calendar) && !H.isNight(at(22, 59), stored: "23-7", calendar: calendar)
          && !H.isNight(at(14, 0), stored: "23-7", calendar: calendar), "07:00, 22:59 and the afternoon are not")
    check(!H.isNight(at(2, 30), stored: "off", calendar: calendar), "with night quiet off, 02:30 is not quiet time")
}

// MARK: - The gate from plain values

private func quietGateTests() {
    typealias G = ArisQuietGate
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12))!
    let midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 0, minute: 30))!
    check(G.verdict(.aris, muted: false, hours: "23-7", screenAway: false, now: midnight, calendar: calendar) == .textOnly(.night),
          "a scheduled job's result at 00:30 is not read aloud")
    check(G.verdict(.aris, muted: false, hours: "23-7", screenAway: false, now: noon, calendar: calendar) == .aloud, "the same result at noon is")
    check(G.verdict(.aris, muted: false, hours: "off", screenAway: false, now: midnight, calendar: calendar) == .aloud,
          "with night quiet turned off it is read at 00:30 too")
    check(G.verdict(.aris, muted: false, hours: "23-7", screenAway: true, now: noon, calendar: calendar) == .textOnly(.screenAway),
          "nothing is announced to a locked screen at noon")
    check(G.verdict(.user, muted: false, hours: "23-7", screenAway: false, now: midnight, calendar: calendar) == .aloud,
          "an answer to what the user asks at 00:30 is spoken")
    check(G.verdict(.userTimer, muted: false, hours: "23-7", screenAway: true, now: midnight, calendar: calendar) == .aloud,
          "his own timer rings at 00:30 with the screen locked")
    check(G.verdict(.user, muted: true, hours: "off", screenAway: false, now: noon, calendar: calendar) == .textOnly(.muted)
          && G.verdict(.userTimer, muted: true, hours: "off", screenAway: false, now: noon, calendar: calendar) == .textOnly(.muted),
          "muted at noon: no answer is spoken and no timer rings")
    check(G.mutedKey == "arisMuted" && G.hoursKey == "arisQuietHours", "the gate reads the preferences the settings write")
}

// MARK: - The one-time note

private func quietNoticeTests() {
    let fresh = ArisMuteNotice()
    check(fresh.hearing(muted: false).shows == false && fresh.hearing(muted: false).next == fresh, "talking to an unmuted Aris shows no note")
    let first = fresh.hearing(muted: true)
    check(first.shows && first.next.told, "the first time the user talks to a muted Aris, the note shows")
    check(!first.next.hearing(muted: true).shows, "the second time it does not")
    check(first.next.switched().hearing(muted: true).shows, "muting again later tells once more")
    check(!fresh.switched(saidSo: true).hearing(muted: true).shows, "muted by voice: the reply already said it, so no note follows")
    typealias R = ArisMuteSwitchRule
    check(R.visible(shown: true, muted: true, hovering: false) && R.visible(shown: true, muted: false, hovering: true)
          && !R.visible(shown: true, muted: false, hovering: false) && !R.visible(shown: false, muted: true, hovering: true),
          "the notch's mute switch stays up while muted, comes on hover otherwise, and goes where the mark steps aside")
}

// MARK: - What the user says

private func quietPhraseTests() {
    typealias P = ArisQuietPhrase
    let mutes = ["조용히 해 줘", "조용히 해줘", "조용히 해", "아리스 조용히 해 줘", "이제 조용히 해 줘", "잠깐 조용히 있어", "조용히", "음소거", "음소거 해 줘",
                 "음소거 켜 줘", "음소거 모드", "쉿", "조용히 해 줄 수 있어", "조용히 해 주실래요", "mute", "mute yourself", "please be quiet",
                 "be quiet for a while", "can you be quiet", "quiet", "stop talking", "hush"]
    for said in mutes { check(P.parse(ArisIntent.phrase(of: said)) == true, "“\(said)” mutes Aris") }
    let unmutes = ["이제 말해도 돼", "말해도 돼", "이제 말해도 괜찮아", "다시 말해도 돼요", "음소거 해제", "음소거 해제해 줘", "음소거 풀어 줘", "음소거 꺼 줘",
                   "소리 내도 돼", "unmute", "unmute please", "you can talk now", "you can speak again", "mute off"]
    for said in unmutes { check(P.parse(ArisIntent.phrase(of: said)) == false, "“\(said)” lets Aris speak again") }
    let others = ["볼륨 음소거", "소리 음소거해 줘", "맥 음소거", "mute the volume", "mute the mac", "조용한 음악 틀어 줘", "조용필 노래 틀어 줘",
                  "음소거가 뭐야", "조용히 하고 메일 읽어 줘", "quieter", "what is mute", "오늘 날씨 어때", "말해 봐", ""]
    for said in others { check(P.parse(ArisIntent.phrase(of: said)) == nil, "“\(said)” is not Aris's mute") }
}

private func quietIntentTests() {
    check(ArisIntent.parse("조용히 해 줘") == .arisMute(true) && ArisIntent.parse("음소거") == .arisMute(true) && ArisIntent.parse("Mute.") == .arisMute(true),
          "aris: 조용히 해 줘, 음소거 and mute are Aris's own mute, done on the Mac")
    check(ArisIntent.parse("이제 말해도 돼") == .arisMute(false) && ArisIntent.parse("unmute") == .arisMute(false) && ArisIntent.parse("이제 말해도 괜찮아") == .arisMute(false),
          "aris: 이제 말해도 돼 and unmute let it speak again")
    check(ArisIntent.parse("볼륨 음소거") == .volume(.mute) && ArisIntent.parse("소리 꺼 줘") == .volume(.mute) && ArisIntent.parse("mute the volume") == .volume(.mute),
          "aris: the Mac's own sound is still muted by 볼륨 음소거, 소리 꺼 and mute the volume")
    check(ArisIntent.parse("음소거 하지 마") == .ask("음소거 하지 마") && ArisIntent.parse("음소거 할까?") == .ask("음소거 할까?"),
          "aris: a don't or a question about muting is the AI's, never done")
    check(ArisIntent.parse("조용히 하고 메일 읽어 줘") == .ask("조용히 하고 메일 읽어 줘"), "aris: a request that goes on after the mute is the AI's, whole")
    check(ArisIntent.guarded(.arisMute(true), said: "조용히 해 줘") == .arisMute(true) && ArisIntent.guarded(.arisMute(true), said: "조용히 하지 마") == .ask("조용히 하지 마"),
          "aris: the one guard before every local action covers the mute")
    check(!ArisIntent.arisMute(true).isReadOnly && ArisIntent.arisMute(true).isOneAct && ArisIntent.arisMute(true).acknowledgement(korean: true) == nil,
          "aris: the mute is one act whose reply comes from what the switch was (ArisQuietCopy)")
    check(ArisControl(.arisMute(true)) == nil, "aris: the mute is not a volume change")
}

// MARK: - Copy

private func quietCopyTests() {
    typealias C = ArisQuietCopy
    check(C.reply(mute: true, was: false, english: false) == "음소거했어요. 이제 글로만 답할게요." && C.reply(mute: true, was: false, english: true) == "Muted. I'll answer in text from now on.",
          "copy: muting says so and what changes")
    check(C.reply(mute: true, was: true, english: false).hasPrefix("이미 음소거 중이에요") && C.reply(mute: false, was: false, english: false) == "지금도 소리 내서 말하고 있어요.",
          "copy: a reply is true: already muted and already speaking say so")
    check(C.reply(mute: false, was: true, english: false) == "이제 다시 소리 내서 말할게요." && C.reply(mute: false, was: true, english: true) == "I'll speak out loud again.",
          "copy: unmuting says Aris speaks again")
    check(C.notice(english: false) == "음소거 중이라 글로 답할게요" && C.notice(english: true) == "Muted, so I'll answer in text", "copy: the one-time note")
    check(C.cannotRead(english: false).contains("이제 말해도 돼") && C.cannotRead(english: true).contains("unmute"), "copy: 읽어줘 while muted says how to get it read")
    for english in [false, true] {
        let lines = [C.menuItem(english: english), C.switchHelp(muted: true, english: english), C.switchHelp(muted: false, english: english), C.mutedLabel(english: english),
                     C.muteTitle(english: english), C.muteDesc(english: english), C.hoursTitle(english: english), C.hoursDesc(english: english)]
            + ArisQuietHours.choices.map { C.hoursLabel($0, english: english) }
        check(lines.allSatisfy { !$0.isEmpty } && Set(lines).count == lines.count - 1, "copy: every label has words in \(english ? "English" : "Korean") (the menu item and the settings title are the same word)")
    }
    check(ArisQuietHours.choices.map { C.hoursLabel($0, english: false) } == ["끄기", "22–7시", "23–7시", "0–8시"], "copy: the hours row's choices, in order")
}

// MARK: - Settings rows

private func quietSettingsTests() {
    let fresh = ArisSettingsSnapshot()
    check(fresh.muted == false && fresh.quietHours == ArisQuietHours.standard, "settings: a fresh install is not muted and is quiet from 23 to 7")
    let rows = ArisSettingsBuilder.sections(.aris, fresh).flatMap(\.rows)
    let mute = rows.first { $0.id == "aris.mute" }, hours = rows.first { $0.id == "aris.quietHours" }
    check(mute?.control == .toggle(.muted, false) && mute?.title == ArisQuietCopy.muteTitle(english: false), "settings: 음소거 is one switch on the Aris page")
    // Since feat-2 the row also offers 직접 고르기 (ArisQuietSpan.custom), after the same four choices.
    check(hours?.control == .choice(.quietHours, ArisQuietHours.choices.map { ArisSettingOption(id: $0, title: ArisQuietCopy.hoursLabel($0, english: false)) }
                                    + [ArisSettingOption(id: ArisQuietSpan.custom, title: ArisQuietHoursCopy.customLabel)], selected: "23-7"),
          "settings: 밤에는 조용히 is one row that shows the hours, 23–7시 picked")
    var changed = ArisSettingsSnapshot()
    changed.muted = true
    changed.quietHours = "garbage"
    let again = ArisSettingsBuilder.sections(.aris, changed).flatMap(\.rows)
    check(again.first { $0.id == "aris.mute" }?.control == .toggle(.muted, true), "settings: the switch shows a muted Aris")
    if case .choice(_, _, let selected, _, _)? = again.first(where: { $0.id == "aris.quietHours" })?.control {
        check(selected == "23-7", "settings: an unreadable stored night shows as the standard hours")
    } else {
        check(false, "settings: the hours row is a choice")
    }
    check(ArisSettingsIndex.entry("aris.mute")?.page == .aris && ArisSettingsIndex.entry("aris.quietHours")?.page == .aris
          && ArisSettingsIndex.search("음소거").first?.id == "aris.mute" && ArisSettingsIndex.search("mute").contains { $0.id == "aris.mute" }
          && ArisSettingsIndex.search("방해 금지").contains { $0.id == "aris.quietHours" } && ArisSettingsIndex.search("밤에는 조용히").first?.id == "aris.quietHours",
          "settings: a search finds both rows")
}

// MARK: - Every speaking and chiming path asks the gate

private func quietWiringTests() {
    let controller = quietSource("Aris/private/Aris/ArisController.swift")
    check(controller.contains("guard !silentSpeech else { return }\n        guard ArisQuietGate.maySpeak(heard: session.heard) else { return }"),
          "wiring: the controller's one speak() asks the gate before any voice plays")
    check(controller.contains("speaking = silentSpeech || !ArisQuietGate.maySpeak(heard: session.heard)"),
          "wiring: an answer still being written is only read aloud when the gate allows it")
    check(controller.contains("if lastVoiceAt != nil, ArisQuietLive.shared.heardUser() { Self.heardSound?.play() }"),
          "wiring: the heard-you tick asks, and a muted Aris shows its one-time note there")
    check(controller.contains("if let muted = await mutedReading(heard: heard, korean: korean) { return muted }"),
          "wiring: 읽어줘 while muted says it cannot read aloud, never that it read")
    // No voice path goes around speak(): every speaker.speak in the app sits inside speak { }, the answer's stream, or a gate check.
    let direct = ["ArisController.swift", "ArisController+Wake.swift", "ArisController+Tasks.swift", "ArisController+Local.swift", "ArisController+Inbox.swift",
                  "ArisController+CardPark.swift", "ArisController+Team.swift", "ArisController+Teammate.swift", "ArisController+TeamMaking.swift",
                  "ArisController+Undo.swift", "ArisController+Look.swift", "ArisController+Countdown.swift", "ArisController+Conversation.swift",
                  "ArisController+Arrange.swift", "ArisController+Practice.swift", "ArisController+SaveAnswer.swift", "ArisController+Brief.swift"]
        .flatMap { file in quietSource("Aris/private/Aris/" + file).components(separatedBy: "\n").filter { $0.contains("speaker.speak(") } }
    let ungated = direct.filter { line in
        !line.contains("speak { await self.speaker.speak(") && !line.contains("speak(timeout:") && !line.contains("ArisQuietGate.maySound(")
            && !line.contains(": Task { await self.speaker.speak(sentences: sentences) }")
    }
    check(!direct.isEmpty && ungated.isEmpty, "wiring: no line speaks without going through speak() or the gate (\(ungated))")

    let tasks = quietSource("Aris/private/Aris/ArisController+Tasks.swift")
    check(tasks.contains("let result = await ArisQuietGate.unprompted(title, reading: shown ?? text) { await work() }"),
          "wiring: what Aris says when it speaks up on its own is marked as its own initiative")
    check(quietSource("Aris/private/Aris/ArisQuietGate.swift").contains("if silent, !text.isEmpty, !Task.isCancelled { try? await Task.sleep(for: ArisNotch.readingTime(for: text)) }"),
          "wiring: news kept to text holds the notch for its reading time, so the next one does not replace it at once")
    check(tasks.contains("if ArisQuietGate.maySound(.aris) { pauseMusic() }"), "wiring: music is not paused for news that stays silent")
    check(tasks.contains("if quiet || !ArisQuietGate.maySpeak(heard: session.heard) { return await clickAnswer(ask, waiter: waiter) }"),
          "wiring: a card that may not be read aloud waits for a click or Y/N, and no microphone opens")
    check(tasks.contains("ClaudeSounds.play(.approval, starter: ArisQuietGate.starter(heard: session.heard))"),
          "wiring: a card's ping follows who started the card")

    let sounds = quietSource("Aris/private/Claude/ClaudeSounds.swift")
    check(sounds.contains("static func play(_ cue: Cue, starter: ArisQuiet.Starter = .aris)") && sounds.contains("guard enabled, ArisQuietGate.maySound(starter) else { return }"),
          "wiring: every chime asks the gate, as Aris's own news unless a card says who started it")
    check(quietSource("Aris/private/Aris/ArisTimerModel.swift").contains("guard ArisQuietGate.maySound(.userTimer) else { return }"),
          "wiring: the timer's chime asks as a timer the user set")
    check(quietSource("Aris/private/Aris/ArisController+Dictation.swift").contains("if ArisQuietGate.maySound(.user) { Self.heardSound?.play() }"),
          "wiring: dictation's tick is silent while muted")
    check(quietSource("Aris/private/Aris/ArisController+Wake.swift").contains("if ArisQuietGate.maySound(.user) { await speaker.speak("),
          "wiring: the wake-word training's last line is only said when Aris may speak")
    check(quietSource("Aris/private/Aris/ArisController+Local.swift").contains("case .arisMute(let mute):\n            return switchMute(mute, korean: korean)"),
          "wiring: the spoken mute is done on the Mac and answered from what the switch was")

    check(quietSource("Aris/private/Aris/Home/ArisNotchHeader.swift").contains("ArisMuteSwitch(shown: showsGlyph && ArisVNotch.voiceSwitchOffered(indicator: aris.session.phase.indicator)"),
          "wiring: the open notch's band carries the mute switch beside Aris's mark")
    check(quietSource("Aris/private/Aris/ArisActivity.swift").contains("case .rest:\n            ArisMutedEar(muted: muted)"),
          "wiring: the closed notch shows a still mark while muted")
    check(quietSource("Aris/private/Aris/Home/ArisTurnView.swift").contains("ArisMuteNoticeTag()"), "wiring: the one-time note sits under the turn")
    check(quietSource("Aris/private/Aris/ArisStatusItem.swift").contains("menu.addItem(ArisQuietMenu.item())"), "wiring: the ✦ menu has the mute item")
    let view = quietSource("Aris/private/Aris/Home/ArisMuteSwitch.swift") + quietSource("Aris/private/Aris/Home/ArisMutedMarks.swift")
    check(!view.contains("repeatForever") && !view.contains(".pulse") && !view.contains("symbolEffect"), "ui: the muted marks are still: nothing blinks or pulses")
}

// MARK: - The announcement in progress

private func quietAnnouncingTestsBlocking() {
    final class Done: @unchecked Sendable { var value = false }
    let done = Done()
    Task { @MainActor in
        check(ArisQuietGate.announcing.isEmpty && ArisQuietGate.starter(heard: "메일 정리") == .user, "gate: nothing is announced until Aris speaks up")
        let inside = await ArisQuietGate.unprompted("메일 정리") { () -> [ArisQuiet.Starter] in
            await Task.yield()
            return [ArisQuietGate.starter(heard: "메일 정리"), ArisQuietGate.starter(heard: "오늘 날씨 어때")]
        }
        check(inside == [.aris, .user], "gate: during an announcement its own words are Aris's, a turn of the user's that took the notch is his")
        check(ArisQuietGate.announcing.isEmpty && ArisQuietGate.starter(heard: "메일 정리") == .user, "gate: the mark goes when the announcement is over")
        let nested = await ArisQuietGate.unprompted("브리핑") {
            await ArisQuietGate.unprompted("브리핑") { ArisQuietGate.announcing.count }
        }
        check(nested == 2 && ArisQuietGate.announcing.isEmpty, "gate: two announcements with the same title end one at a time")
        done.value = true
    }
    while !done.value { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}
