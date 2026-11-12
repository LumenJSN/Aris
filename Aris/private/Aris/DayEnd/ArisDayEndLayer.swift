//
//  ArisDayEndLayer.swift
//  Aris
//
//  Where the evening offer of the day-end summary (ArisDayEnd) shows, never spoken and never a window. Under the closed
//  notch its chip (ArisDayEndChip) comes in from 4 points lower over 150 ms, hangs for a few seconds (longer under the
//  pointer) and steps back. Until the user opens it, it waits in the open notch as one chip in the done chip's dress. It
//  gives way to everything else that draws under the notch (the jobs' pill, the agent chip, the speech-model cards),
//  and never shows over a turn, a card, a drag or the guide.
//

import SwiftUI

/// Under the closed notch, for a few seconds.
struct ArisDayEndLayer: View {
    @ObservedObject private var dayEnd = ArisDayEndModel.shared
    @ObservedObject private var agent = ArisAgentMonitor.shared
    @ObservedObject private var downloads = ArisModelDownloader.shared
    @ObservedObject private var aris = ArisNotchState.shared
    @ObservedObject private var guide = ArisOnboardingGuide.shared

    let mode: ArisStarBand.Mode?
    let closed: Bool
    let bandHeight: CGFloat
    /// The jobs' pill has a line: it owns the space under the notch (ArisUnderNotch).
    var pillShown = false
    /// A drag is over the notch.
    var busy = false

    private var shows: Bool {
        guard closed, dayEnd.peeking, dayEnd.offerWaits else { return false }
        let taken = ArisUnderNotch.owner(pill: pillShown, agentChip: ArisAgentLayer.chipWanted(link: agent.link, hovered: agent.hovered, mode: mode),
                                         prep: downloads.appleInstalling, offer: downloads.cardOpen || downloads.offering) != nil
        return !taken && ArisDayEndOffer.mayShow(turn: aris.isActive, card: aris.cardWaiting, dragging: busy, onboarding: guide.showing)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if shows, let offer = dayEnd.offer {
                ArisDayEndChip(text: offer.chip) { ArisController.shared.openDayEnd() }
                    .onHover { dayEnd.chipHovered = $0 }
                    .padding(.top, bandHeight + 6)
                    .transition(.modifier(active: Entry(on: false), identity: Entry(on: true)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.15), value: shows)
    }

    /// In from 4 points lower at .97, as the agent chip.
    private struct Entry: ViewModifier {
        let on: Bool
        func body(content: Content) -> some View {
            content.opacity(on ? 1 : 0).scaleEffect(on ? 1 : 0.97, anchor: .top).offset(y: on ? 0 : 4)
        }
    }
}

/// In the open notch, while the offer waits: one chip on the tag row's line. A turn has the notch to itself.
struct ArisDayEndRow: View {
    @ObservedObject private var dayEnd = ArisDayEndModel.shared
    /// A turn or an answer is up.
    var hidden = false

    var body: some View {
        if !hidden, dayEnd.offerWaits, let offer = dayEnd.offer {
            let english = ArisUILanguage.english
            ArisDoneSummaryChip(count: ArisDayEndCopy.title(english: english), latest: offer.chipDetail, open: false, symbol: "moon.stars.fill",
                                unfolds: false, help: ArisDayEndCopy.chipHelp(english: english)) {
                ArisController.shared.openDayEnd()
            }
            .padding(.horizontal, ArisActivityTag.rowInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
    }
}
