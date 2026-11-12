//
//  ArisCurrencyCardView.swift
//  Aris
//
//  The currency answer card, in the stock card's layout and tokens (ArisWidgetStyle; the day's line is the stock
//  card's own ArisSparkline, green or red as it is there): the converted amount large with its code ("21.34 CAD"),
//  under it what was asked and the rate ("100 CNY · 1 CNY = 0.2134 CAD") with the rate's time, the day's line of this
//  pair, then 고가 · 저가 and a small line when a dollar was assumed or the rate was worked out through the US dollar.
//  Values are drawn as Text(verbatim:); nothing moves or blinks. ArisCurrencyLiveCard is the same card with its amount,
//  its two codes and a swap as controls (the hidden preference arisCurrencyCard = live).
//

import SwiftUI

/// The card's measurements, all in one place.
enum ArisCurrencyCardStyle {
    static let padding = EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16)
    static let gap: CGFloat = 10
    static let resultSize: CGFloat = 38
    static let resultTracking: CGFloat = -1.14
    static let codeSize: CGFloat = 15
    static let askedSize: CGFloat = 13
    static let rateSize: CGFloat = 12
    static let smallSize: CGFloat = 11
    static let chartHeight: CGFloat = 60
    static let statGap: CGFloat = 22
    /// A control's box (the amount, a code): 24 high, radius 8, white 7%, a hairline.
    static let controlHeight: CGFloat = 24
    static let controlRadius: CGFloat = 8
    static let controlFill = Color.white.opacity(0.07)
    static let controlFillActive = Color.white.opacity(0.11)
    static let controlLine = Color.white.opacity(0.1)
    /// The box that has the keyboard: a brighter line, never a glow that moves.
    static let controlLineActive = Color.white.opacity(0.42)
    static let swapSize: CGFloat = 30
    /// The result while what is typed isn't an amount yet, or a new pair's rate is on its way.
    static let waiting = 0.35
    /// A press: 97% on a strong ease-out, 140 ms.
    static let pressScale: CGFloat = 0.97
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
    /// The swap's arrows turn half round: 220 ms, ease-out.
    static let turn = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)
    /// Room for five of the menu's rows under a code (the rest scroll).
    static let menuRoom: CGFloat = 206
    static let menuRow: CGFloat = 38
}

/// The card's layout, with what stands for the amount, the two codes and the corner left to whoever draws it.
struct ArisCurrencyCardFrame<Amount: View, From: View, To: View, Corner: View>: View {
    let card: ArisCurrencyCard
    /// The result is not this pair's yet: drawn dimmed.
    var waits = false
    var note: String?
    /// A fixed moment, for the renders; nil is now.
    var now: Date?
    var calendar: Calendar = .current
    var english = ArisUIWords.english
    @ViewBuilder var amount: () -> Amount
    @ViewBuilder var from: () -> From
    @ViewBuilder var to: () -> To
    @ViewBuilder var corner: () -> Corner

    private typealias Style = ArisCurrencyCardStyle
    private var tone: Color { card.up ? ArisStockMapStyle.up : ArisStockMapStyle.down }
    private var charted: Bool { card.points.count >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: Style.gap) {
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // line-height 1: a 38-point box, as the stock card's price.
                    Text(verbatim: card.convertedText).font(.system(size: Style.resultSize, weight: .light).monospacedDigit())
                        .tracking(Style.resultTracking).foregroundStyle(ArisWidgetStyle.ink92).lineLimit(1).minimumScaleFactor(0.6)
                        .frame(height: Style.resultSize).opacity(waits ? Style.waiting : 1)
                    to()
                }
                Spacer(minLength: 0)
                corner()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                amount()
                from()
                Text(verbatim: "· " + card.rateLine).font(.system(size: Style.rateSize).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1).minimumScaleFactor(0.75).opacity(waits ? Style.waiting : 1).arisTextBacking()
                Spacer(minLength: 4)
                Text(verbatim: card.asOf(now: now ?? Date(), calendar: calendar, english: english)).font(.system(size: Style.smallSize).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4)).lineLimit(1).fixedSize().arisTextBacking()
            }
            if charted {
                ArisSparkline(values: card.points, previous: card.reference, color: tone).frame(height: Style.chartHeight)
                    .opacity(waits ? Style.waiting : 1)
            }
            if charted || note != nil {
                HStack(alignment: .firstTextBaseline, spacing: Style.statGap) {
                    if charted {
                        stat(ArisCurrencyCopy.high(english: english), card.highText)
                        stat(ArisCurrencyCopy.low(english: english), card.lowText)
                    }
                    Spacer(minLength: 0)
                    if let note {
                        Text(verbatim: note).font(.system(size: Style.smallSize)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                    }
                }
            }
        }
        .padding(Style.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ArisWidgetStyle.radius, style: .continuous).fill(ArisWidgetStyle.fill))
    }

    /// The stock card's `.hl2`: the label 11 at .4, the value 13 / 600 six points after it.
    private func stat(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: label).font(.system(size: Style.smallSize)).foregroundStyle(.white.opacity(0.4))
            Text(verbatim: value).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(ArisWidgetStyle.ink92)
        }
    }
}

/// The plain card: everything is words.
struct ArisCurrencyCardView: View {
    let card: ArisCurrencyCard
    var now: Date?
    var calendar: Calendar = .current
    var english = ArisUIWords.english

    var body: some View {
        ArisCurrencyCardFrame(card: card, note: ArisCurrencyCopy.note(card, english: english), now: now, calendar: calendar, english: english) {
            Text(verbatim: "\(card.amountText) \(card.from)").font(.system(size: ArisCurrencyCardStyle.askedSize, weight: .medium).monospacedDigit())
                .foregroundStyle(ArisWidgetStyle.ink72).lineLimit(1)
        } from: {
            EmptyView()
        } to: {
            Text(verbatim: card.to).font(.system(size: ArisCurrencyCardStyle.codeSize, weight: .semibold)).foregroundStyle(.white.opacity(0.58))
        } corner: {
            EmptyView()
        }
        .accessibilityElement(children: .combine)
    }
}
