//
//  ArisQuietLive.swift
//  Aris
//
//  The mute switch as the app lives it. Whatever flips it (the notch's switch, the ✦ menu, "조용히 해 줘", the row in
//  Settings) lands in one preference, and this is what follows: the voice stops mid-word the moment Aris is muted,
//  and the first time the user then talks to it by voice a note says "음소거 중이라 글로 답할게요" for a few seconds, so
//  a silent answer is never a puzzle. The preference survives a restart; whether sound may play is ArisQuietGate's
//  answer, read fresh each time.
//

import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "voice")

@MainActor
final class ArisQuietLive: ObservableObject {
    static let shared = ArisQuietLive()

    /// The one-time note is up under the turn.
    @Published private(set) var noticeUp = false

    /// How long the note stays.
    static let noticeLinger: Duration = .seconds(6)

    private var notice = ArisMuteNotice()
    private var noticeClear: Task<Void, Never>?
    /// The mute state last acted on, so a change made elsewhere (the row in Settings) is followed once.
    private var applied = Defaults[.arisMuted]
    private var watch: Task<Void, Never>?

    private init() {
        watch = Task { [weak self] in
            for await muted in Defaults.updates(.arisMuted, initial: false) { self?.apply(muted, saidSo: false) }
        }
    }

    var muted: Bool { Defaults[.arisMuted] }

    func toggle() { setMuted(!muted) }

    /// `saidSo`: Aris's reply already tells the user it is muted (they muted it by voice), so no note follows.
    func setMuted(_ on: Bool, saidSo: Bool = false) {
        Defaults[.arisMuted] = on
        if on == applied, saidSo { notice = notice.switched(saidSo: true) }
        apply(on, saidSo: saidSo)
    }

    private func apply(_ on: Bool, saidSo: Bool) {
        guard on != applied else { return }
        applied = on
        log.notice("Aris \(on ? "muted" : "unmuted", privacy: .public)")
        notice = notice.switched(saidSo: saidSo)
        lowerNotice()
        // Muted mid-sentence: the voice stops now, as it does on Stop; the answer stays on screen.
        if on { ArisController.shared.speaker.stop() }
    }

    /// The user just finished saying something to Aris. True when the soft "heard you" tick may play; a muted Aris shows
    /// its one-time note instead.
    func heardUser() -> Bool {
        let heard = notice.hearing(muted: muted)
        notice = heard.next
        if heard.shows { raiseNotice() }
        return ArisQuietGate.maySound(.user)
    }

    private func raiseNotice() {
        noticeClear?.cancel()
        noticeUp = true
        noticeClear = Task { [weak self] in
            try? await Task.sleep(for: Self.noticeLinger)
            guard !Task.isCancelled else { return }
            self?.noticeUp = false
        }
    }

    private func lowerNotice() {
        noticeClear?.cancel()
        noticeClear = nil
        if noticeUp { noticeUp = false }
    }
}

extension ArisController {
    /// "조용히 해 줘" or "이제 말해도 돼", done; what Aris answers, from what the switch was. The caller shows it and
    /// says it, which only makes sound once Aris may speak again.
    func switchMute(_ mute: Bool, korean: Bool) -> String {
        let quiet = ArisQuietLive.shared
        let was = quiet.muted
        quiet.setMuted(mute, saidSo: mute)
        return ArisQuietCopy.reply(mute: mute, was: was, english: !korean)
    }

    /// "읽어줘" to a muted Aris: nothing is read, so it never answers "다 읽어 줬어요". It says why and how to get it
    /// read. Nil when Aris is not muted (the answer is read as usual).
    func mutedReading(heard: String, korean: Bool) async -> String? {
        guard ArisQuietGate.muted else { return nil }
        let reply = ArisQuietCopy.cannotRead(english: !korean)
        await sayLocal(reply, heard: heard)
        return reply
    }
}

extension ArisController {
    /// "방해 금지 시간을 밤 11시부터 아침 8시로 바꿔 줘", done: the hours are stored (the row in Settings shows them at
    /// once) and said back as they now are.
    func setQuietHours(_ stored: String, korean: Bool) -> String {
        let was = Defaults[.arisQuietHours]
        Defaults[.arisQuietHours] = stored
        log.notice("quiet hours set by voice: \(stored, privacy: .public)")
        return ArisQuietHoursCopy.reply(stored: stored, was: was, english: !korean)
    }
}
