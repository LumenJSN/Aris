//
//  ArisAnswerDocumentView.swift
//  Aris
//
//  The owner's pick A, "깔끔한 문서" (mockups/answer-format.html): the open notch's answer as a clean document.
//  The lead line at 16 on 24, weight 600, white .95, 14 above what follows; each section's label 7 above its body,
//  sections 14 apart; tables, bullets and checklists as ArisDocumentBlocks draws them. Each piece rises in once
//  (ArisRevealClock: 420 ms on (.22, .61, .36, 1), 90 ms apart, from 6 points down and a slight blur; at once with
//  Reduce Motion). While the answer streams, pieces are appended: the ones already shown are equal and aren't drawn
//  again, only the last grows. Words are ArisReaderInline's runs: no HTML, no images, and a link (http, https, mailto
//  only) is copied when clicked, never opened.
//

import AppKit
import SwiftUI

struct ArisAnswerDocumentView: View, Equatable {
    let text: String
    /// Rises in; the follow-up's leaving copy is already on screen.
    var reveals = true

    @State private var clock = ArisRevealTimer()

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text && lhs.reveals == rhs.reveals }

    var body: some View {
        let pieces = ArisAnswerDocument.pieces(from: text)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { index, piece in
                let previous = index > 0 ? pieces[index - 1] : nil
                ArisAnswerPieceView(piece: piece, joins: ArisAnswerDocument.joinsPrevious(piece, after: previous),
                                    reveals: reveals, clock: clock)
                    .equatable()
                    .padding(.top, Self.gap(after: previous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .tint(ArisReaderBody.linkColor)
        .environment(\.openURL, OpenURLAction { url in
            // Never opened: the words may come from web pages or mail. The address goes on the clipboard.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            return .handled
        })
    }

    /// 7 under a label, 14 between sections and under the lead, nothing above the first.
    static func gap(after previous: ArisAnswerDocument.Piece?) -> CGFloat {
        switch previous {
        case nil: return 0
        case .block(.label): return 7
        default: return 14
        }
    }
}

/// When each piece starts rising, on the system clock. A class, so asking it doesn't re-render the answer.
final class ArisRevealTimer {
    private var clock = ArisRevealClock()

    func delay(joins: Bool) -> Double {
        let now = ProcessInfo.processInfo.systemUptime
        return max(0, clock.start(now: now, joinsPrevious: joins) - now)
    }
}

/// One piece of the answer, rising in once when it first appears.
private struct ArisAnswerPieceView: View, Equatable {
    let piece: ArisAnswerDocument.Piece
    let joins: Bool
    let reveals: Bool
    let clock: ArisRevealTimer

    @State private var risen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Re-draws this view when the hidden look changes (ArisSiriLookGate).
    @ObservedObject private var siriLook = ArisSiriLookGate.shared

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.piece == rhs.piece && lhs.joins == rhs.joins && lhs.reveals == rhs.reveals }

    static let rise = Animation.timingCurve(ArisRevealClock.curve[0], ArisRevealClock.curve[1], ArisRevealClock.curve[2],
                                            ArisRevealClock.curve[3], duration: ArisRevealClock.duration)

    private var shown: Bool { risen || !reveals || reduceMotion }

    var body: some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : ArisRevealClock.rise)
            .blur(radius: shown ? 0 : ArisRevealClock.blur)
            .onAppear {
                guard !shown else { return }
                withAnimation(Self.rise.delay(clock.delay(joins: joins))) { risen = true }
            }
    }

    private var siri: Bool { ArisSiriLookNow.on }

    @ViewBuilder private var content: some View {
        switch piece {
        case .lead(let words):
            // The siri look: Siri's answer is one size and weight throughout, 15 regular on an 18-point line.
            ArisReaderBody.text(words, size: siri ? CGFloat(ArisSiriLook.Answer.fontSize) : 16, weight: siri ? 400 : 600,
                                color: .white.opacity(siri ? ArisSiriLook.Answer.ink : 0.95))
                .tracking(siri ? 0 : -0.16)
                .lineBox(siri ? CGFloat(ArisSiriLook.Answer.fontSize) : 16, siri ? ArisSiriLook.Answer.lineHeight / ArisSiriLook.Answer.fontSize : 1.5)
                .fixedSize(horizontal: false, vertical: true)
        case .block(let block):
            ArisAnswerBlockView(block: block)
        }
    }
}

/// A block of the answer below the lead.
private struct ArisAnswerBlockView: View {
    let block: ArisBoardContent.Block
    /// Re-draws this view when the hidden look changes (ArisSiriLookGate).
    @ObservedObject private var siriLook = ArisSiriLookGate.shared

    var body: some View {
        switch block {
        case .label(let words):
            ArisDocLabel(text: words)
        case .table(let header, let rows):
            ArisDocTable(header: header, rows: rows)
        case .bullets(let items):
            ArisDocBullets(items: items)
        case .checklist(let items):
            ArisDocChecklist(items: items)
        case .numbered(let items):
            VStack(alignment: .leading, spacing: ArisDocMetrics.notch.itemGap) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "\(index + 1).").font(.system(size: 14).monospacedDigit()).foregroundStyle(ArisDocLook.quiet)
                            .frame(width: 16, alignment: .trailing)
                        ArisDocLine(words: item)
                    }
                }
            }
        case .paragraph(let words):
            ArisDocLine(words: words)
        case .heading(let level, let words):
            ArisReaderBody.text(words, size: level == 1 ? 17 : 15, weight: level == 1 ? 700 : 650, color: .white.opacity(0.95))
                .lineBox(level == 1 ? 17 : 15, 1.4)
                .fixedSize(horizontal: false, vertical: true)
        case .quote(let words):
            ArisDocLine(words: words, color: .white.opacity(0.65))
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.18)).frame(width: 2) }
        case .code(let code):
            Text(verbatim: code).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(.white.opacity(0.82))
                .lineBox(12.5, 1.6).fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.06)))
        }
    }
}
