//
//  ArisPillView.swift
//  Aris
//
//  The jobs' pill under the notch as drawn, the user's B (mockups/pill-oneline.html) in the P1 layout: one line in the
//  dictation pill's glass, 30 tall, 10 in, 10 between columns, at least 168 wide; the face slot left, the line on the
//  notch's centre line, the elapsed time right. A longer line or more faces make it wider, never taller. The faces come
//  from the caller (ArisStatusPill: the star's seat or a teammate's baked sprites), so this view holds no state of its
//  own beyond the check's landing.
//

import SwiftUI

struct ArisMergedPill<Face: View>: View {
    let line: ArisPillLine
    /// The jobs are over: the line is 끝났어요 and a check, no clock.
    var done = false
    let since: Date?
    let faces: ArisPillFaces
    /// One face at its size (22 alone, 18 small).
    @ViewBuilder let face: (ArisPillFace, CGFloat) -> Face

    var body: some View {
        ArisP1Row {
            ArisPillFaceSlot(faces: faces, face: face)
            ZStack {
                lineText
                    .id(line)
                    .transition(.opacity)
            }
            .lineLimit(1)
            .fixedSize()
            .animation(.easeInOut(duration: 0.18), value: line)
            ArisPillClock(since: done ? nil : since)
        }
        .frame(height: ArisPillLayout.height)
        .padding(.horizontal, ArisPillLayout.padding)
        .background(ArisPillGlass(shape: Capsule(style: .continuous)))
        .animation(ArisGlass.opening, value: faces)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: line.spoken))
    }

    /// What runs, swept by the working shimmer (the face says who: the teammate's name is only read out); 끝났어요 and
    /// a check at the end.
    @ViewBuilder
    private var lineText: some View {
        if done {
            HStack(spacing: 4) {
                Text(verbatim: line.text)
                    .font(Font(ArisFont.system(ArisPillShimmerLabel.size, weight: ArisPillShimmerLabel.weight)))
                    .tracking(ArisPillShimmerLabel.tracking)
                    .foregroundStyle(.white.opacity(0.9))
                ArisDoneCheck()
            }
        } else {
            ArisPillShimmerLabel(text: line.text)
        }
    }
}

/// The one face slot: a face alone, or up to two small ones (the next 5 under the first, the first on top) and "+N"
/// (10 / 650 at .62, 3 after them).
private struct ArisPillFaceSlot<Face: View>: View {
    let faces: ArisPillFaces
    let face: (ArisPillFace, CGFloat) -> Face

    var body: some View {
        let size = faces.small ? ArisPillLayout.smallFaceSize : ArisPillLayout.faceSize
        HStack(spacing: ArisPillLayout.plusGap) {
            HStack(spacing: -ArisPillLayout.faceOverlap) {
                ForEach(Array(faces.faces.enumerated()), id: \.element) { index, each in
                    face(each, size)
                        .frame(width: size, height: size)
                        .zIndex(Double(faces.faces.count - index))
                }
            }
            if faces.more > 0 {
                Text(verbatim: "+\(faces.more)")
                    .font(Font(ArisFont.system(10, weight: 650)).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize()
            }
        }
    }
}

/// The mockup's check after 끝났어요: green, 11 pt, landing with a little overshoot (460 ms); still under Reduce Motion.
private struct ArisDoneCheck: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9.5, weight: .heavy))
            .foregroundStyle(Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255))
            .scaleEffect(landed || reduceMotion ? 1 : 0.4)
            .opacity(landed || reduceMotion ? 1 : 0)
            .onAppear {
                withAnimation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.46)) { landed = true }
            }
    }
}

/// The right column: time since the oldest unfinished job, 10.5 / 600 at .43, tabular so it doesn't jiggle.
private struct ArisPillClock: View {
    let since: Date?

    var body: some View {
        if let since {
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text(ArisPillLayout.elapsed(context.date.timeIntervalSince(since)))
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.43))
                    .fixedSize()
            }
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

/// Three columns, P1: left and right as wide as the wider of them (and wider while the pill is under 168), the middle
/// centred between them.
private struct ArisP1Row: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard sizes.count == 3 else { return .zero }
        let width = ArisPillLayout.width(left: sizes[0].width, center: sizes[1].width, right: sizes[2].width)
            - 2 * ArisPillLayout.padding
        return CGSize(width: width, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard sizes.count == 3 else { return }
        // The bounds are already symmetric (sizeThatFits): the ends hold the sides, the middle the text.
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified)
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: .unspecified)
    }
}
