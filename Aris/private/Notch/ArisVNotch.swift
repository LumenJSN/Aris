//
//  ArisVNotch.swift
//  Aris
//
//  Aris's top notch in numbers: how the notch scales with the display, how big it is closed, hovered, listening and
//  open, where the band's controls sit, and which mark the band shows. One rule for every display, with a camera
//  housing or without one.
//  The open body does not scale: it is 440 wide when expanded on every display; only the bands, the idle and
//  collapsed sizes and the hover growth are multiplied.
//  CoreGraphics only, so the tests pin every number.
//

import CoreGraphics

enum ArisVNotch {
    // MARK: - The constants

    /// The display width the unscaled numbers were drawn for (a 14-inch MacBook Pro).
    static let baseDisplayWidth: CGFloat = 1512
    /// The most a display scales the notch by.
    static let maxScale: CGFloat = 1.24
    /// The open notch's top band, and what a display's own top band is measured against.
    static let topBand: CGFloat = 37
    /// The tallest the open band gets.
    static let topBandCap: CGFloat = 48
    /// The closed band while it listens or holds a parked answer.
    static let recordingBand: CGFloat = 32
    /// The recording band is the open band less this, never under 32.
    static let recordingBandDrop: CGFloat = 5
    /// The closed band's body.
    static let compactBandWidth: CGFloat = 270
    /// The closed notch with nothing to show, over a camera housing: its width and height.
    static let idleWidth: CGFloat = 150
    static let idleContentHeight: CGFloat = 29
    /// The same on a display with no housing (solid / glass).
    static let idleRestHeight: CGFloat = 4
    static let idleGlassRestHeight: CGFloat = 5.5
    /// Idle while attachments or a drag are pending.
    static let idleAttach = CGSize(width: 320, height: 44)
    /// The hidden state.
    static let collapsedWidth: CGFloat = 220
    /// The open body, on every display.
    static let expandedBodyWidth: CGFloat = 440
    /// The open corner radius (19 + 12) and the compact one.
    static let expandedRadius: CGFloat = 31
    static let compactRadius: CGFloat = 13
    /// A written answer's cap.
    static let responseMaxHeight: CGFloat = 360

    /// The open content's padding: 2 above and 12 each side; below it 8 while the composer shows, 12 otherwise.
    static let contentInset: CGFloat = 12
    static let contentTopInset: CGFloat = 2
    static let contentBottomInset: CGFloat = 8

    static func expandedBottomInset(composerShown: Bool) -> CGFloat { composerShown ? contentBottomInset : contentInset }

    /// What a hovered idle notch grows by: taller, wider, and wider again over a camera housing.
    static let hoverGrow: CGFloat = 6
    static let hoverWiden: CGFloat = 16
    static let hoverWidenNotched: CGFloat = 52
    /// How far outside the surface a hover begins and ends.
    static let hoverTargetPadding: CGFloat = 2
    static let hoverExitPadding: CGFloat = 8
    /// The quiet time after a hover haptic, in seconds.
    static let hoverHapticCooldown: Double = 0.75

    /// The band's side slot, its inset from the body's edges and the band row's gap.
    static let slot = CGSize(width: 68, height: 22)
    static let edgeInset: CGFloat = 14
    static let slotGap: CGFloat = 10
    /// The mark's size, in its 28-point control at `left: 9`.
    static let orbSize: CGFloat = 18
    static let orbBox: CGFloat = 28
    static let orbLeft: CGFloat = 9
    /// The voice switch: 32 × 19 at `left: 32` of the control, a 4-point bridge after the 28-point box.
    static let voiceSwitch = CGSize(width: 32, height: 19)
    static let voiceSwitchLeft: CGFloat = 32
    /// Stop: 23 × 23 at the slot's right; Close shifts to `right: 30` while Stop is beside it.
    static let stopSize: CGFloat = 23
    static let closeBesideStop: CGFloat = 30

    // MARK: - The display

    /// What the notch is told about a display: whether it has a camera housing, the height of the strip at its top,
    /// and its width, all in points.
    struct Display: Equatable {
        var hasHousing: Bool
        /// The strip at the display's top: the menu bar's, never less than the camera housing's.
        var topBand: CGFloat
        var width: CGFloat

        /// A display with no camera housing.
        static func plain(width: CGFloat) -> Display { Display(hasHousing: false, topBand: 0, width: width) }
    }

    /// Every size that follows the display, rounded half up.
    struct Metrics: Equatable {
        var hasHousing: Bool
        /// clamp(max(1, width / 1512, topBand / 37), 1, 1.24); 1 without a housing.
        var scale: CGFloat
        /// The open notch's top band.
        var band: CGFloat
        /// The closed band while it listens, waits for the transcript or holds a parked answer.
        var recordingBand: CGFloat
        /// The closed band's body width.
        var compactWidth: CGFloat
        /// The closed notch with nothing to show (its body; glass or solid rest height without a housing).
        var idleWidth: CGFloat
        var idleHeight: CGFloat
        var idleSolidHeight: CGFloat
        /// What a hovered idle notch widens by.
        var hoverWiden: CGFloat
        var idleAttach: CGSize
        var collapsedWidth: CGFloat
    }

    /// The scale rule.
    static func scale(_ display: Display) -> CGFloat {
        guard display.hasHousing else { return 1 }
        let byWidth = display.width > 0 ? display.width / baseDisplayWidth : 1
        let byBand = display.topBand > 0 ? display.topBand / topBand : 1
        return min(maxScale, max(1, byWidth, byBand))
    }

    static func metrics(_ display: Display) -> Metrics {
        let scale = scale(display)
        guard display.hasHousing else {
            return Metrics(hasHousing: false, scale: 1, band: topBand, recordingBand: recordingBand, compactWidth: compactBandWidth,
                           idleWidth: idleWidth, idleHeight: idleGlassRestHeight, idleSolidHeight: idleRestHeight,
                           hoverWiden: hoverWiden, idleAttach: idleAttach, collapsedWidth: collapsedWidth)
        }
        let band = min(topBandCap, max(topBand, max(topBand * scale, display.topBand))).rounded()
        let idle = (idleContentHeight * scale).rounded()
        return Metrics(hasHousing: true, scale: scale, band: band,
                       recordingBand: max(recordingBand, (band - recordingBandDrop).rounded()),
                       compactWidth: (compactBandWidth * scale).rounded(),
                       idleWidth: (idleWidth * scale).rounded(), idleHeight: idle, idleSolidHeight: idle,
                       hoverWiden: (hoverWidenNotched * scale).rounded(),
                       idleAttach: CGSize(width: (idleAttach.width * scale).rounded(), height: (idleAttach.height * scale).rounded()),
                       collapsedWidth: (collapsedWidth * scale).rounded())
    }

    // MARK: - The outline

    /// A body narrower than 440 has 13-point shoulders, the open body 31; the surface is
    /// the body and a shoulder each side.
    static func shoulder(bodyWidth: CGFloat) -> CGFloat {
        let body = max(0, bodyWidth)
        return min(body >= expandedBodyWidth - 0.01 ? expandedRadius : compactRadius, body / 2)
    }

    static func visualWidth(bodyWidth: CGFloat) -> CGFloat {
        max(0, bodyWidth) + 2 * shoulder(bodyWidth: bodyWidth)
    }

    /// The corner radius drawn, held to a quarter of the surface's width and half its height.
    static func radius(bodyWidth: CGFloat, height: CGFloat) -> CGFloat {
        let visual = visualWidth(bodyWidth: bodyWidth)
        let base = visual >= expandedBodyWidth + 2 * expandedRadius - 0.01 ? expandedRadius : compactRadius
        return min(base, visual / 4, max(0, height) / 2)
    }

    // MARK: - The closed notch

    /// What a closed notch is, for its size.
    enum Closed: Equatable {
        /// Nothing to show: the idle notch.
        case idle
        /// A mark each side of the camera (Aris's star, a timer, music, a parked answer): the compact band.
        case band
        /// The same band while Aris listens: it never grows under the pointer.
        case liveBand
    }

    /// The closed body's size: idle 150 × 29 scaled (4 or 5.5 tall without a housing), a band
    /// 270 scaled × the recording band; hovered, an idle notch and a resting band grow 6 taller and 16 wider, 52
    /// scaled over a camera housing.
    static func closedSize(_ closed: Closed, hovered: Bool, glass: Bool, metrics: Metrics) -> CGSize {
        let grows = hovered && closed != .liveBand
        let widen = grows ? metrics.hoverWiden : 0, taller = grows ? hoverGrow : 0
        switch closed {
        case .idle:
            return CGSize(width: metrics.idleWidth + widen, height: (glass ? metrics.idleHeight : metrics.idleSolidHeight) + taller)
        case .band, .liveBand:
            return CGSize(width: metrics.compactWidth + widen, height: metrics.recordingBand + taller)
        }
    }

    /// The hover growth is shown while the pointer rests on a closed notch: always when a rest does not open it
    /// (a click does), and as the cue before it opens when the wait is long enough to see it
    /// begin (the growth runs on the 340 ms size clock; under this it would only flicker).
    static let shortestWaitToGrow: Double = 0.15

    static func hoverGrowthShows(openOnHover: Bool, hoverDelay: Double) -> Bool {
        !openOnHover || hoverDelay >= shortestWaitToGrow
    }

    /// One haptic per hover, and none within 750 ms of the last.
    static func hapticAllowed(sinceLast: Double) -> Bool { sinceLast >= hoverHapticCooldown }

    // MARK: - The band's grid, from the body's left and right edges

    /// The 28-point control holding the 18-point mark: from the body's left edge (`left: 9`).
    static var orbFrameMinX: CGFloat { orbLeft }
    /// The mark's centre, from the body's left edge: 9 + 14.
    static var orbCenterX: CGFloat { orbLeft + orbBox / 2 }
    /// The voice switch's left edge, from the body's left edge: 9 + 32.
    static var voiceSwitchMinX: CGFloat { orbLeft + voiceSwitchLeft }
    /// The right slot's right edge, from the body's right edge.
    static var slotTrailing: CGFloat { edgeInset }

    /// The ear beside a camera housing `housing` wide in a band `body` wide, and whether the 28-point control fits in
    /// it whole (9 in, 28 wide).
    static func ear(body: CGFloat, housing: CGFloat) -> CGFloat { max(0, (body - housing) / 2) }
    static func orbFits(ear: CGFloat) -> Bool { ear >= orbLeft + orbBox }

    // MARK: - The band's mark

    enum Indicator: Equatable { case waveform, loading, orb }

    /// Bars while the user is recording or the microphone captures; else the working mark while the request is active,
    /// nothing has arrived yet and nothing is being spoken; else the orb.
    static func indicator(recording: Bool, requestActive: Bool, hasResult: Bool, speaking: Bool) -> Indicator {
        if recording { return .waveform }
        if !speaking && !hasResult && requestActive { return .loading }
        return .orb
    }

    /// The glow behind the orb shows only in orb mode, while speaking or in error.
    enum Halo: Equatable { case none, speaking, error }

    static func halo(indicator: Indicator, speaking: Bool, error: Bool) -> Halo {
        guard indicator == .orb else { return .none }
        if error { return .error }
        return speaking ? .speaking : .none
    }

    /// The voice switch is offered beside the orb only: never beside the bars or the working mark (it is on offer
    /// while the notch is expanded, nothing is recorded and the indicator is the orb).
    static func voiceSwitchOffered(indicator: Indicator) -> Bool { indicator == .orb }

    /// The halo's reach past the 18-point mark, its blur and its three alphas (0 %, 30 %, 55 % of the radius).
    static func haloSpec(_ halo: Halo) -> (outset: CGFloat, blur: CGFloat, alphas: [Double])? {
        switch halo {
        case .none: return nil
        case .speaking: return (10, 4, [0.28, 0.16, 0.07])
        case .error: return (9, 3, [0.55, 0.32, 0.13])
        }
    }

    /// The orb and the bars trade places over 280 ms on (0.4, 0, 0.2, 1): the orb from 75 %, the bars from 85 %.
    static let crossfade: (duration: Double, curve: (Double, Double, Double, Double), orbScale: CGFloat, barsScale: CGFloat) =
        (0.28, (0.4, 0, 0.2, 1), 0.75, 0.85)
}

/// How a closed Aris rests on a display with a camera housing. The idle notch is narrower and shorter than the
/// housing, so at rest only the housing is seen. Aris's star used to rest in a band beside the camera, which made
/// the closed notch larger at rest. Now the star comes out with the band when Aris has something to show or to tell,
/// and rests out of sight otherwise. The hidden preference `arisClosedRest` = `star` keeps it resting in the band, to
/// compare on a real screen.
/// Since themes the star rests in the band, asleep, by default: Settings › 노치 › 쉬는 동안 별 보이기 (ArisRestStar).
enum ArisVNotchRest: String {
    case outOfSight, star

    static let preferenceKey = "arisClosedRest"

    init(stored: String?) { self = stored.flatMap(ArisVNotchRest.init(rawValue:)) ?? .outOfSight }

    /// The star rests in the band: when asked for, or while it has something to tell that only the closed notch says
    /// (Aris is muted, its helper cannot be reached, a speech model's note, files waiting for the next request).
    func starRests(muted: Bool, agentDown: Bool, modelNote: Bool, filesWaiting: Bool = false) -> Bool {
        self == .star || muted || agentDown || modelNote || filesWaiting
    }
}
