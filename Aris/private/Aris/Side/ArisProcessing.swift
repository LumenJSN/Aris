//
//  ArisProcessing.swift
//  Aris
//
//  The "working" row: a shine crosses the title on a 2.4 s linear clock. Every working row shares the clock,
//  so they stay in step. The row's mark stays still (the user wants no blinking).
//

import SwiftUI

enum ArisProcessingClock {
    static let period: TimeInterval = 2.4

    /// 0…1 through the current cycle.
    static func phase(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }
}

/// The shimmer: the title in white 50% with a bright band (100% at its centre) sweeping left to right
/// over the first half of each cycle; plain white 94% when not working.
struct ArisProcessingShimmer: ViewModifier {
    let on: Bool

    private static let stops: [Gradient.Stop] = [
        .init(color: .white.opacity(0.5), location: 0), .init(color: .white.opacity(0.55), location: 0.35),
        .init(color: .white, location: 0.5), .init(color: .white.opacity(0.55), location: 0.65),
        .init(color: .white.opacity(0.5), location: 1),
    ]

    func body(content: Content) -> some View {
        if on {
            TimelineView(.animation) { context in
                // The gradient is twice the title's width; its start runs from -1 to +1 widths, so the bright centre
                // goes from the left edge (start of the cycle) past the right edge (halfway).
                let start = -1 + 2 * ArisProcessingClock.phase(context.date)
                content.foregroundStyle(LinearGradient(stops: Self.stops, startPoint: UnitPoint(x: start, y: 0.5),
                                                       endPoint: UnitPoint(x: start + 2, y: 0.5)))
            }
        } else {
            content.foregroundStyle(.white.opacity(0.94))
        }
    }
}
