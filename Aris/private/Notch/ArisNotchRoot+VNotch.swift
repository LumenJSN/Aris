//
//  ArisNotchRoot+VNotch.swift
//  Aris
//
//  One display's closed notch at ArisVNotch's sizes: the idle notch when there is nothing to show (hidden by
//  a camera housing, a 5.5-point sliver without one), the band when a mark sits beside the camera, and the growth
//  under the pointer (6 taller; 16 wider, 52 scaled over a housing) while a rest on it waits to open it, or for as long
//  as the pointer stays when a rest opens nothing. The sizes are the default only: a notch height of one's own set in
//  Settings is kept as set.
//

import Defaults
import SwiftUI

extension ArisNotchRoot {
    /// The closed notch keeps Aris's older strip in the one case the idle notch cannot show what it must: muted, on a
    /// display with no camera housing, where the struck speaker sits at the strip's end (the idle sliver is 5.5 tall).
    var mutedStripHere: Bool {
        closedKind == .empty && ArisMutedMark.place(closed: .empty, muted: muted, hasNotch: vm.hasNotch) == .strip
    }

    /// The closed sizes are ArisVNotch's.
    var closedIsVNotch: Bool { vm.closedFollowsVNotch && !mutedStripHere }

    /// What the closed notch is, for its size.
    var closedShape: ArisVNotch.Closed {
        switch closedKind {
        case .empty: return .idle
        // Listening, and whatever sizes itself (the Now Playing notice): never grown under the pointer.
        case .star(.turn), .notice: return .liveBand
        case .star, .dueAlert, .timer, .claude, .music: return .band
        }
    }

    /// The pointer rests on the closed notch and the growth is shown (ArisVNotch.hoverGrowthShows).
    var closedGrown: Bool {
        closed && hovering && !hidden && !noticeActive && !musicPeekHere && closedIsVNotch
            && ArisVNotch.hoverGrowthShows(openOnHover: openOnHover, hoverDelay: hoverDelay)
    }

    /// The closed body at ArisVNotch's size for what it shows.
    var closedBody: CGSize {
        ArisVNotch.closedSize(closedShape, hovered: closedGrown, glass: !reduceTransparency, metrics: vm.vnotch)
    }

    /// The band's body on this display: ArisVNotch's, or nil for the older camera-relative width.
    var bandBody: CGFloat? {
        guard closedIsVNotch else { return nil }
        return ArisVNotch.closedSize(closedShape == .idle ? .band : closedShape, hovered: closedGrown, glass: true, metrics: vm.vnotch).width
    }

    /// Where what hangs under the closed notch starts (the jobs' pill, the helper's chip, a speech model's card): under
    /// the notch as drawn, and never behind the camera housing (the idle notch is shorter than the housing).
    var hangHeight: CGFloat {
        max(displayedHeight, closedIsVNotch && vm.hasNotch ? vm.effectiveClosedNotchHeight : 0)
    }

    /// The closed corners: 13, held to a quarter of the surface's width and half its height.
    var closedRadius: CGFloat { ArisVNotch.radius(bodyWidth: closedBody.width, height: displayedHeight) }

    /// The star rests in the band: Aris's choice of rest (ArisVNotchRest), or something only the closed notch tells.
    var starMayRest: Bool {
        ArisVNotchRest(stored: UserDefaults.standard.string(forKey: ArisVNotchRest.preferenceKey), starShown: restStarShown).starRests(muted: muted, agentDown: agentLink.link.dozes,
                                         modelNote: speechModels.state.earText != nil || speechModels.loadTrouble != nil,
                                         filesWaiting: !givenFiles.files.isEmpty)
    }

    /// The star at rest sleeps in the band, unless it is there to show files waiting or a speech model's note (ArisRestStar).
    var starAsleep: Bool {
        ArisRestStar.sleeps(mode: starMode, filesWaiting: !givenFiles.files.isEmpty,
                            modelNote: speechModels.state.earText != nil || speechModels.loadTrouble != nil)
    }

    /// One haptic as the pointer comes onto the closed notch, and none within 750 ms of the last.
    func hoverHaptic() {
        let now = Date()
        guard ArisVNotch.hapticAllowed(sinceLast: now.timeIntervalSince(lastHoverHaptic)) else { return }
        lastHoverHaptic = now
        haptic.toggle()
    }
}
