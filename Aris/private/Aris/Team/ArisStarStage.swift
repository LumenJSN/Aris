//
//  ArisStarStage.swift
//  Aris
//
//  The user's A6 (mockups/7-character.html, P1): Aris's one star rests beside the camera, and while the pill under the
//  notch shows with the star as its face (the user's B, mockups/pill-oneline.html: Aris's own job, or the 끝났어요) it drops
//  into the pill's face slot and works there, 22 pt (18 among small faces), then rises home when the pill goes. When a
//  teammate's face holds the slot the star isn't drawn: the teammate stands in its place, never both. The band and
//  the pill only keep a seat (an empty slot reporting its bounds); the notch's root view draws the star once, above
//  both and outside the band's clip, at the seat ArisStarSeat picks. The hop is a 420-ms parabola (ArisStarHop) after
//  the pill's 280-ms entry, with a landing squash on the render server; the star itself is its baked sprites
//  (ArisMainCharacter), so at rest and at work nothing here runs per frame. 모션 줄이기 or Reduce Motion: no hop, no
//  squash, the star is simply in its seat.
//

import Defaults
import SwiftUI

/// The seats the band and the pill report, as anchors resolved by the stage.
struct ArisStarSeats {
    var band: Anchor<CGRect>?
    var pill: Anchor<CGRect>?
    /// The pill shows, and a teammate's face holds its slot.
    var taken = false
}

struct ArisStarSeatKey: PreferenceKey {
    static var defaultValue: ArisStarSeats { ArisStarSeats() }

    static func reduce(value: inout ArisStarSeats, nextValue: () -> ArisStarSeats) {
        let next = nextValue()
        value = ArisStarSeats(band: value.band ?? next.band, pill: value.pill ?? next.pill, taken: value.taken || next.taken)
    }
}

extension View {
    /// This view is where the star sits when `seat` holds it (its centre).
    func arisStarSeat(_ seat: ArisStarSeat) -> some View {
        anchorPreference(key: ArisStarSeatKey.self, value: .bounds) { anchor in
            seat == .band ? ArisStarSeats(band: anchor) : ArisStarSeats(pill: anchor)
        }
    }

    /// This pill shows, and (`taken`) someone else's face holds its slot: no star while it does.
    func arisStarAway(_ taken: Bool) -> some View {
        transformPreference(ArisStarSeatKey.self) { seats in
            if taken { seats.taken = true }
        }
    }
}

/// Draws the star at its seat, in the coordinate space of the view it overlays.
struct ArisStarStage: View {
    let seats: ArisStarSeats
    let mode: ArisStarBand.Mode?
    /// False when the band is drawn but not seen (the flat stand-in notch keeps it at 0.01).
    var bandVisible = true
    /// The star rests asleep in the band (ArisRestStar).
    var asleep = false

    var body: some View {
        GeometryReader { proxy in
            let pill = seats.pill.map { proxy[$0] }
            ArisStarStagePlacement(band: bandVisible ? seats.band.map { Self.centre(proxy[$0]) } : nil,
                                   pill: pill.map(Self.centre), pillScale: pill.map { $0.width / ArisStarStagePlacement.size },
                                   taken: seats.taken, mode: mode, asleep: asleep)
        }
        .allowsHitTesting(false)
    }

    private static func centre(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
}

private struct ArisStarStagePlacement: View {
    let band: CGPoint?
    let pill: CGPoint?
    /// The pill seat's size against the band's (22 or 18 against 20).
    let pillScale: CGFloat?
    let taken: Bool
    let mode: ArisStarBand.Mode?
    var asleep = false

    /// The band's star, the 18-point mark (ArisVNotch.orbSize; it was 20); in the pill it is scaled to its seat
    /// (a transform, the same baked sprites).
    static let size: CGFloat = ArisVNotch.orbSize

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Default(.arisReduceMotion) private var reduceSetting
    /// Down in the pill (or on its way there); else beside the camera (or on its way up).
    @State private var down = false
    /// The hop's clock: `hop` animates toward `hops`, one whole number a hop (ArisStarHopEffect).
    @State private var hop = 0.0
    @State private var hops = 0.0
    @State private var lands = 0
    /// Where each seat last was, so the star can rise from a pill that has just gone, or fade out where it stood.
    @State private var lastBand: CGPoint?
    @State private var lastPill: CGPoint?
    @State private var lastPillScale: CGFloat = 1
    @State private var pending: Task<Void, Never>?
    /// When the hop in flight took off (nil once it has landed), so turning it back starts where the star is.
    @State private var flying: Date?

    private var wanted: ArisStarSeat? { ArisStarSeat.seat(mode: mode, band: band != nil, pill: pill != nil, pillTaken: taken) }
    private var reduced: Bool { systemReduceMotion || reduceSetting }

    var body: some View {
        let bandAt = band ?? lastBand, pillAt = pill ?? lastPill
        ZStack(alignment: .topLeading) {
            if wanted != nil, let at = bandAt ?? pillAt {
                ArisMainCharacter(size: Self.size, lands: lands, asleep: asleep && wanted == .band)
                    .modifier(ArisStarHopEffect(hop: hop, hops: hops, band: bandAt ?? at, pill: pillAt ?? at,
                                                pillScale: pillScale ?? lastPillScale, down: down))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.2), value: wanted == nil)
        .onAppear {
            remember()
            down = wanted == .pill
        }
        .onChange(of: band) { remember() }
        .onChange(of: pill) { remember() }
        .onChange(of: pillScale) { remember() }
        .onChange(of: wanted) { old, new in move(from: old, to: new) }
        .onDisappear { pending?.cancel() }
    }

    private func remember() {
        if let band { lastBand = band }
        if let pill { lastPill = pill }
        if let pillScale { lastPillScale = pillScale }
    }

    private func move(from old: ArisStarSeat?, to new: ArisStarSeat?) {
        pending?.cancel()
        // Gone: it fades where it stands. Back in the same seat: nothing to do.
        guard let new, (new == .pill) != down else { return }
        let toPill = new == .pill
        // Appearing, or with one seat unknown, or no motion: it's simply there.
        guard old != nil, !reduced, (band ?? lastBand) != nil, (pill ?? lastPill) != nil else {
            down = toPill
            hops += 1
            hop = hops
            flying = nil
            return
        }
        // Turned back mid-flight (the pill came and went): the same parabola backwards from where the star is now,
        // not a restart from the far seat.
        let back = flying.map { ArisStarHop.reversal(elapsed: Date().timeIntervalSince($0)) }
        pending = Task { @MainActor in
            // Down only once the pill is in; up at once, as the pill tucks away.
            if toPill, back == nil { try? await Task.sleep(for: .seconds(ArisStarHop.delay)) }
            guard !Task.isCancelled else { return }
            down = toPill
            hops += 1
            let duration = back?.remaining ?? ArisStarHop.duration
            if let back {
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { hop = hops - (1 - back.progress) }
            }
            flying = Date().addingTimeInterval(duration - ArisStarHop.duration)
            withAnimation(.linear(duration: duration)) { hop = hops }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            flying = nil
            lands += 1
        }
    }
}

/// Places the star on the hop's path, scaled from the band's size to the pill seat's along it: `hop` runs from
/// `hops` − 1 to `hops` while it flies, and sits on `hops` at rest (so a settled star is at its seat and its size,
/// whatever moves the seats). Only `hop` animates.
private struct ArisStarHopEffect: GeometryEffect {
    var hop: Double
    let hops: Double
    let band: CGPoint
    let pill: CGPoint
    let pillScale: CGFloat
    let down: Bool

    var animatableData: Double {
        get { hop }
        set { hop = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = 1 - (hops - hop)
        let at = ArisStarHop.point(band: band, pill: pill, progress: progress, down: down)
        let scale = down ? ArisStarHop.scale(from: 1, to: pillScale, progress: progress)
            : ArisStarHop.scale(from: pillScale, to: 1, progress: progress)
        let placed = CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: at.x, y: at.y))
        return ProjectionTransform(placed)
    }
}
