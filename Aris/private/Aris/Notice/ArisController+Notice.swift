//
//  ArisController+Notice.swift
//  Aris
//
//  Aris's own news on the notice pill under the notch (ArisNoticeCenter) instead of a line inside it; a deadline's
//  alert and a Claude Code notice come the same way. A notice waits its turn among Aris's news and for a pause, as the
//  line did (announce), and also for the notch to be closed, the setup gone and no turn or dictation running; once the
//  moment has held for 800 ms it comes up, and what used to be said is said once, when Aris may speak (mute and quiet
//  hours keep it to the pill). Afterwards the notch keeps the news as its parked answer, as it kept the line, so the
//  closed notch's dot and the 기록 tab are where they were.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "notice")

extension ArisController {
    /// Puts `notice` up at the right moment and says `said` then. `parking`: what the notch keeps as its parked answer
    /// afterwards (nil: nothing, as for a problem, whose card holds its button). `shown`: what happens the moment it is
    /// up, before it is said (the answer joins the conversation's context then, as it did when the line came). True
    /// once the card is up; false when it was dropped (waited too long), replaced or withdrawn before its moment, or the
    /// caller was cancelled.
    @discardableResult
    func notify(_ notice: ArisNotice, saying said: String = "", parking: String? = nil, shown: @MainActor () -> Void = {}) async -> Bool {
        let center = ArisNoticeCenter.shared
        // A card with the key of one already up takes its place at once: the moment was right for that one.
        if center.enqueue(notice) { return true }
        // What the interruption policy is asked each time the moment is looked at (ArisInterruption).
        let want = ArisNoticeRoute.want(notice, spoken: !said.isEmpty)
        while !Task.isCancelled {
            let now = interruption(want)
            if now == .drop { break }
            if case .hold = now {
                // Held (the user talking, a call, the lock): it waits outside the line, so what may come up now (a timer
                // in a call) is not stuck behind it.
                try? await Task.sleep(for: .seconds(ArisNoticeGate.recheck))
                center.dropExpired()
                guard center.isWaiting(notice.id) else { return false }
                continue
            }
            let outcome: Bool?? = await announce(recheck: .seconds(ArisNoticeGate.recheck), when: { center.mayShow }) {
                try? await Task.sleep(for: .seconds(ArisNoticeGate.settle))
                center.dropExpired()
                guard !Task.isCancelled, center.isWaiting(notice.id) else { return false }
                // The moment passed meanwhile (a turn began, the notch opened, the user began to talk): back in line, or
                // out of it while the policy holds it.
                let decision = self.interruption(want)
                guard self.isPause(present: false), center.mayShow, decision.comesUp else { return nil }
                center.present(notice.id)
                log.notice("card up: \(notice.kind.rawValue, privacy: .public)\(decision == .speak ? "" : " (quietly)", privacy: .public)")
                if let parking, self.session.phase == .idle, self.session.question == nil {
                    self.setSession(.parked(heard: notice.title, reply: parking))
                    self.unparkWhenGone(notice, reply: parking)
                }
                shown()
                if !said.isEmpty, decision == .speak { await self.sayNews(said) }
                return true
            }
            // Cancelled before its turn came.
            guard let outcome else { break }
            if let up = outcome { return up }
            // Otherwise the moment passed: back in line.
        }
        center.withdraw(notice.id)
        return false
    }

    /// A notice that goes by itself (a timer's: its showsFor) takes its parked line with it once it is gone and the
    /// notch isn't open on it (ArisParkedNotice; thirteenth VM run, T1: "Timer · 1 minute is up." stayed as the notch's
    /// answer long after its pill went).
    private func unparkWhenGone(_ notice: ArisNotice, reply: String) {
        guard notice.showsFor != nil else { return }
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(ArisParkedNotice.recheck))
                guard let self else { return }
                let center = ArisNoticeCenter.shared
                let up = center.queue.shown.contains { $0.id == notice.id } || center.isWaiting(notice.id)
                switch ArisParkedNotice.step(session: self.session, heard: notice.title, reply: reply, noticeUp: up, notchOpen: center.aside) {
                case .wait: continue
                case .stop: return
                case .clear:
                    log.notice("the timer's parked answer went with its card")
                    self.setSession(ArisSession())
                    return
                }
            }
        }
    }

    /// What the interruption policy says about `want` now, from the world's snapshot and the quiet rules.
    func interruption(_ want: ArisInterruption.Want) -> ArisInterruption.Decision {
        ArisInterruption.decide(want, ArisWorld.shared.moment(mayMakeSound: !silentSpeech && ArisQuietGate.maySound(.aris)))
    }

    /// What used to be said with the line: once, with the "done" chime, music paused meanwhile. Only when Aris may
    /// speak on its own (ArisQuiet: not muted, not in quiet hours, the screen on).
    private func sayNews(_ said: String) async {
        guard !silentSpeech else { return }
        ClaudeSounds.play(.done)
        guard ArisQuietGate.maySound(.aris) else { return }
        pauseMusic()
        do {
            if ArisQuietGate.maySound(.aris) { try await Self.within(Self.speakTimeout) { await self.speaker.speak(said) } }
        } catch is CancellationError {
            // A turn of the user's began: it has the voice now.
        } catch {
            log.error("speaking the card's line took too long")
            speaker.stop()
        }
        // A turn of the user's that began meanwhile keeps the music as it wants it.
        if session.phase == .idle { resumeMusicIfPaused() }
    }

    /// A handed-out job's 보기 on its card: its saved result in the reader, or its answer.
    func openDone(id: UUID) {
        if let task = tasks.first(where: { $0.id == id }) { return openDone(task) }
        if let file = jobFiles[id] { ArisBoard.shared.read(file: file) }
    }
}
