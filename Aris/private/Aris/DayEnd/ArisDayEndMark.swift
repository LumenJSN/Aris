//
//  ArisDayEndMark.swift
//  Aris
//
//  The four marks of the day-end list (ArisDayEnd), drawn as the picked mockup draws them (qa/design-1111, 2-C; a
//  16-point box, 12 beside a count): done is a filled disc with a check, under way a ring half filled, not done an
//  empty ring, waiting a ring with a clock's hands. White by opacity only, and nothing on them moves. Then the small
//  counts the 목록 row carries ("✓ 3  ○ 2  ◷ 1").
//

import SwiftUI

struct ArisDayEndMark: View {
    let mark: ArisDayEnd.Mark
    var size: CGFloat = ArisDayEndMark.rowSize
    var english = ArisUILanguage.english

    /// In a row, and beside a count.
    static let rowSize: CGFloat = 16
    static let countSize: CGFloat = 12
    /// The stroke of the ring, the check and the hands, in the 16-point box.
    static let stroke: CGFloat = 1.6

    var body: some View {
        Canvas { context, canvas in
            // The mockup's paths are written in a 16-point box.
            let unit = canvas.width / 16
            let line = StrokeStyle(lineWidth: Self.stroke * unit, lineCap: .round, lineJoin: .round)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
            let ring = Path(ellipseIn: CGRect(x: 2 * unit, y: 2 * unit, width: 12 * unit, height: 12 * unit))
            switch mark {
            case .done:
                context.fill(Path(ellipseIn: CGRect(x: unit, y: unit, width: 14 * unit, height: 14 * unit)), with: .color(.white.opacity(0.16)))
                var check = Path()
                check.move(to: point(5, 8.3))
                check.addLine(to: point(7.1, 10.4))
                check.addLine(to: point(11.1, 5.9))
                context.stroke(check, with: .color(.white.opacity(0.88)), style: line)
            case .part:
                context.stroke(ring, with: .color(.white.opacity(0.22)), lineWidth: Self.stroke * unit)
                var half = Path()
                half.move(to: point(8, 2))
                half.addArc(center: point(8, 8), radius: 6 * unit, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
                half.closeSubpath()
                context.fill(half, with: .color(.white.opacity(0.72)))
            case .none:
                context.stroke(ring, with: .color(.white.opacity(0.22)), lineWidth: Self.stroke * unit)
            case .wait:
                context.stroke(ring, with: .color(.white.opacity(0.62)), lineWidth: Self.stroke * unit)
                var hands = Path()
                hands.move(to: point(8, 4.8))
                hands.addLine(to: point(8, 8))
                hands.addLine(to: point(10.3, 9.5))
                context.stroke(hands, with: .color(.white.opacity(0.88)), style: line)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(ArisDayEndCopy.mark(mark, english: english))
    }
}

/// The 목록 row's counts: a mark and its number each, 9 apart (the mockup's .cnt: 11 / 600 at .62, tabular).
struct ArisDayEndCounts: View {
    let marks: [(mark: ArisDayEnd.Mark, count: Int)]
    var english = ArisUILanguage.english

    static let gap: CGFloat = 9
    static let inner: CGFloat = 3

    var body: some View {
        HStack(spacing: Self.gap) {
            ForEach(Array(marks.enumerated()), id: \.offset) { _, one in
                HStack(spacing: Self.inner) {
                    ArisDayEndMark(mark: one.mark, size: ArisDayEndMark.countSize, english: english)
                    Text(verbatim: "\(one.count)").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.62))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(ArisDayEndCopy.mark(one.mark, english: english)) \(one.count)")
            }
        }
    }
}
