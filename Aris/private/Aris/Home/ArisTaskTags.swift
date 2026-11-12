//
//  ArisTaskTags.swift
//  Aris
//
//  Background work handed to Aris in the open notch, as the owner's 1B (mockups/done-and-reader.html) shows it: each running
//  job an activity tag ("블랙홀 자료 정리 · 웹 검색 중", light sweeping across), and everything finished folded
//  into one chip at the end of the row ("✓ 3개 끝남 · 최근 것"). A job that finishes keeps its tag while the check
//  lands, then slides into the chip (520 ms). The chip opens a tray in place: the newest four, each with 열기, and
//  "다 봤어요", which clears the chip (the 기록 tab keeps them all). A job's or a schedule's question that is not on
//  screen (the user's turn covered its card, or nobody answered) waits here as a 확인 대기 chip: a click shows the card.
//

import SwiftUI

struct ArisTaskTags: View {
    @ObservedObject private var aris = ArisController.shared
    @ObservedObject private var desk = ArisCardDesk.shared
    /// What a job stopped from its tag had done, for its row (ArisStopLine).
    @ObservedObject private var tagClock = ArisTagClock.shared
    @State private var landing: Set<UUID> = []
    @State private var trayOpen = false

    var body: some View {
        // A job whose question waits in 확인 대기 is that chip, not a tag that looks at work.
        let parked = desk.waiting.jobs
        let tasks = aris.tasks.filter { !parked.contains($0.id) }.map { ArisStopLine.shown($0, notes: tagClock.stopNotes) }
        ArisTaskTagsContent(fold: ArisDoneFold.fold(tasks, seen: aris.seenDone, landing: landing), trayOpen: $trayOpen,
                            open: { aris.openDone($0) }, seenAll: { aris.markDoneSeen() },
                            waiting: desk.waiting.cards.map(Self.chip), openWaiting: { aris.openWaitingCard($0) },
                            since: Dictionary(aris.jobs.map { ($0.id, $0.created) }) { first, _ in first }, stop: { aris.stopJobFromTag($0) },
                            stopHelp: ArisStopLine.help(english: ArisUIWords.english))
            .onChange(of: finished) { before, after in
                let new = after.subtracting(before)
                guard !new.isEmpty else { return }
                landing.formUnion(new)
                Task { @MainActor in
                    try? await Task.sleep(for: ArisDoneFold.landingTime)
                    withAnimation(ArisGlass.resize) { landing.subtract(new) }
                }
            }
    }

    private static func chip(_ card: ArisWaitingCard) -> ArisWaitingChip {
        ArisWaitingChip(id: card.id, lead: ArisParkedAsk.chipLead(english: ArisUIWords.english), detail: ArisParkedAsk.chipDetail(card),
                        help: ArisParkedAsk.chipHelp(english: ArisUIWords.english))
    }

    private var finished: Set<UUID> { Set(aris.tasks.filter(\.isFinished).map(\.id)) }
}
