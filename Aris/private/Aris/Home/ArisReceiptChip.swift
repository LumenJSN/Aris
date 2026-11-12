//
//  ArisReceiptChip.swift
//  Aris
//
//  The receipt under an answer (ArisReceipt), drawn as one more chip of the answer's own row: the done chip's
//  28-point capsule (ArisDoneSummaryChip: white .07, a 10-point mark and 11.5-point words at .62) on the tag row's
//  inset, so its mark sits on the text line like the activity tags above it. "✓ 엄마에게 보냄" for one act; with an undo
//  the capsule ends in the 한 일 tab's 되돌리기 pill (20 tall, white .06, 10.5 semibold; it dips to .93 when pressed), and
//  after the press the words say what happened ("되돌렸어요", or why not, on two lines at most). Several acts are one
//  counted chip ("3가지 함 ›") that presses like a button and opens the 한 일 tab. In as the tags come in (220 ms
//  ease-out), out as they go; nothing on it moves while it is up.
//

import SwiftUI

/// The row from a line: no model, so the offscreen render draws the real thing.
struct ArisReceiptChip: View {
    let line: ArisReceiptLine
    var english = false
    /// The 한 일 tab isn't turned off in settings: a counted line is then the way to it.
    var opensTab = true
    var undo: () -> Void = {}
    var open: () -> Void = {}

    @State private var hovering = false

    static let height = ArisActivityTag.height
    /// The capsule's radius; a line that wraps (why an undo didn't happen) keeps it.
    static let radius = height / 2
    static let maxWidth: CGFloat = 380
    /// Inside the capsule: before the mark, after the words, and around the 되돌리기 pill (so the pill is concentric).
    static let leading: CGFloat = 8
    static let trailing: CGFloat = 11
    static let pillInset: CGFloat = 4
    static let wrapPadding: CGFloat = 6
    private static let font = Font(ArisFont.system(11.5, weight: 560) as CTFont)
    private static let tracking: CGFloat = -0.115
    private static let failedTint = Color(red: 1, green: 0.45, blue: 0.4)
    private static let hover = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.14)

    var body: some View {
        HStack(spacing: ArisActivityTag.gap) {
            Group {
                if pressable {
                    Button(action: open) { chip }
                        .buttonStyle(ArisPressStyle())
                        .arisNotchHover($hovering)
                        .help(ArisReceiptWords.openHelp(english: english))
                } else {
                    chip.help(line.receipt.detail)
                }
            }
            // The automatic check let this run: its quiet mark sits beside the capsule (ArisCheckedMark).
            if line.showsChecked { ArisCheckedMark(english: english) }
        }
        // The capsule is as wide as its words, up to the done chip's limit; past it they cut (or wrap, for a reason).
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, ArisActivityTag.rowInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Self.hover, value: hovering)
        .animation(ArisActivityTag.relabel, value: line)
    }

    /// Several acts, and a tab to show them in.
    private var pressable: Bool { line.opensActivity && opensTab }

    private var chip: some View {
        HStack(spacing: ArisActivityTag.gap) {
            Image(systemName: symbol).font(.system(size: 8.5, weight: .heavy)).frame(width: 10, height: 10)
                .foregroundStyle(failed ? Self.failedTint.opacity(0.85) : .white.opacity(0.62))
            Text(verbatim: line.words(english: english)).font(Self.font).tracking(Self.tracking)
                .lineLimit(failed ? 2 : 1).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.interpolate)
                .arisTextBacking()
            if pressable {
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).frame(width: 9, height: 9).opacity(0.6)
            }
            if line.offersUndo {
                Button(action: undo) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 8.5, weight: .bold))
                        Text(verbatim: ArisReceiptWords.undo(english: english))
                    }
                }
                .buttonStyle(ArisReceiptUndoStyle())
                .disabled(line.stage == .undoing)
                .opacity(line.stage == .undoing ? 0.5 : 1)
                .help(ArisReceiptWords.undo(english: english))
            }
        }
        .foregroundStyle(.white.opacity(hovering ? 0.82 : 0.62))
        .padding(.leading, Self.leading)
        .padding(.trailing, line.offersUndo ? Self.pillInset : Self.trailing)
        // One line is the capsule's 28 points whatever it holds; only a reason that wraps needs room above and below.
        .padding(.vertical, failed ? Self.wrapPadding : 0)
        .frame(minHeight: Self.height)
        .background(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).fill(.white.opacity(hovering ? 0.11 : 0.07)))
        .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
    }

    private var failed: Bool {
        if case .notUndone = line.stage { return true }
        return false
    }

    /// A check for what was done, the undo's arrow once it was undone, a mark when it wasn't.
    private var symbol: String {
        switch line.stage {
        case .done, .undoing: "checkmark"
        case .undone: "arrow.uturn.backward"
        case .notUndone: "exclamationmark"
        }
    }
}

/// The 한 일 tab's 되돌리기 pill (ArisActivityView's, which is private to it): 20 tall, 7 in, white 6% (10% hovered, 16%
/// pressed), 10.5 semibold at 62% (95% hovered); a press dips to 0.93 over 140 ms on a strong ease-out.
private struct ArisReceiptUndoStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration)
    }

    private struct Pill: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering || pressed ? 0.95 : 0.62))
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(Capsule().fill(.white.opacity(pressed ? 0.16 : hovering ? 0.1 : 0.06)))
                .contentShape(Capsule())
                .scaleEffect(pressed && !reduceMotion ? 0.93 : 1)
                .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.14), value: pressed)
                .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.14), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}
