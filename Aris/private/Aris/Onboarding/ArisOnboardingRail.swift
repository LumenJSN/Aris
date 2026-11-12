//
//  ArisOnboardingRail.swift
//  Aris
//
//  How much of the setup is left: one bar at the top of the window and nothing else, no numbers and no step names
//  (the owner's pick 6, 2026-11-11). A single metallic rail, drawn from its numbers (ArisRailMetrics): an 11-point
//  track inset 24 with a soft dark lip and a white line inside, a blue-to-silver fill at 96° with a 48-point leading
//  fade, its width moving over 500 ms on (.4, 0, .2, 1) and its opacity over 180 ms; full, the fade drops. The
//  gradient is drawn here from its stops; no image is used. Its steps are the pages this person will see
//  (ArisSetupPlan), so a page that is left out never makes it jump. Reduce Motion: it changes at once. In the dark
//  theme the track is dark too.
//

import SwiftUI

struct ArisSetupRail: View {
    @ObservedObject var guide: ArisOnboardingGuide
    @ObservedObject var model: ArisOnboardingModel
    let palette: ArisSetupPalette

    private typealias M = ArisRailMetrics

    var body: some View {
        let fraction = model.flow.progress(granted: model.grants, shown: guide.plan.pages, tryDone: guide.askAnswered)
        let step = guide.plan.step(model.flow.page)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                track
                fill(width: geo.size.width * fraction, complete: fraction >= 1)
                    .opacity(fraction > 0 ? 1 : 0)
                    // Opacity 180 ms ease.
                    .animation(guide.reduced ? nil : .timingCurve(0.25, 0.1, 0.25, 1, duration: M.opacitySeconds), value: fraction > 0)
            }
            .clipShape(Capsule())
            // Width 500 ms cubic-bezier(.4, 0, .2, 1).
            .animation(guide.reduced ? nil : .timingCurve(M.widthCurve.0, M.widthCurve.1, M.widthCurve.2, M.widthCurve.3, duration: M.widthSeconds), value: fraction)
        }
        .frame(height: M.height)
        .padding(.horizontal, M.inset)
        .padding(.top, M.inset)
        .accessibilityElement()
        .accessibilityLabel(ArisOnboardingCopy.progress(step.number, step.count))
        .accessibilityValue("\(Int(fraction * 100))%")
    }

    /// The track: a vertical gradient, a soft dark lip under its top edge and a hard light line along its bottom.
    private var track: some View {
        let lip = palette.dark ? Color.black.opacity(0.4) : ArisOBColor.hex(M.lip.hex, M.lip.alpha)
        let shine = Color.white.opacity(palette.dark ? 0.06 : M.shine.alpha)
        // CSS's blur of 2 is a shadow radius of 1 here.
        return Capsule().fill(LinearGradient(stops: palette.track, startPoint: .top, endPoint: .bottom)
            .shadow(.inner(color: lip, radius: M.lip.blur / 2, y: M.lip.y))
            .shadow(.inner(color: shine, radius: 0, y: -M.shine.y)))
    }

    /// The fill, `width` wide: blue to silver and back along CSS's 96° line, fading out over its leading 48 points.
    private func fill(width: Double, complete: Bool) -> some View {
        let line = M.gradientLine(width: max(width, 1), height: M.height)
        let stops = M.fill.map { Gradient.Stop(color: ArisOBColor.hex($0.hex), location: $0.at) }
        let mask = M.mask(width: width, complete: complete).map { Gradient.Stop(color: .black.opacity($0.alpha), location: $0.at) }
        return LinearGradient(stops: stops, startPoint: UnitPoint(x: line.start.x, y: line.start.y), endPoint: UnitPoint(x: line.end.x, y: line.end.y))
            .frame(width: width)
            .mask { LinearGradient(stops: mask, startPoint: .leading, endPoint: .trailing) }
    }
}
