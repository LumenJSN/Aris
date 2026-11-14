//
//  ArisController+Notice.swift
//  Aris
//
//  Aris's own news on a card under the notch (ArisNoticeCenter) instead of a line inside it. The card waits its turn
//  among Aris's news and for a pause, as the line did (announce), and also for the notch to be closed and the setup
//  gone; once the moment has held for 800 ms it comes up, and what used to be said is said once, when Aris may speak
//  (mute and quiet hours keep it to the card). Afterwards the notch keeps the news as its parked answer, as it kept
//  the line, so the closed notch's dot and the 기록 tab are where they were.
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
        while !Task.isCancelled {
            let outcome: Bool?? = await announce(recheck: .seconds(ArisNoticeGate.recheck), when: { center.mayShow }) {
                try? await Task.sleep(for: .seconds(ArisNoticeGate.settle))
                center.dropExpired()
                guard !Task.isCancelled, center.isWaiting(notice.id) else { return false }
                // The moment passed meanwhile (a turn began, the notch opened): back in line.
                guard self.isPause(present: false), center.mayShow else { return nil }
                center.present(notice.id)
                log.notice("card up: \(notice.kind.rawValue, privacy: .public)")
                if let parking, self.session.phase == .idle, self.session.question == nil {
                    self.session = .parked(heard: notice.title, reply: parking)
                }
                shown()
                if !said.isEmpty { await self.sayNews(said) }
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
