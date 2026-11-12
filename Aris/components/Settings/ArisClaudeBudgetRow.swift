//
//  ArisClaudeBudgetRow.swift
//  Aris
//
//  설정 › 대화 › Claude Code's second row (mockup claude-usage.html, A): the API key's daily budget as a "$" field
//  (the settings text field, 112 wide, the amount on the right) and its switch, and under a hairline the allowed
//  range or what's wrong with the entry, and $3 / $5 / $10. A good entry is saved as it's typed; a bad one shows its
//  hint and keeps the last good amount, which comes back when the field is left (ClaudeBudgetEntry). It lives with
//  the settings window's views because its field is an ordinary window's, not a notch panel's.
//

import SwiftUI

/// The row from plain values (ClaudeBudgetRow hands it the saved ones).
struct ClaudeBudgetRowView: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsStill) private var still
    let title: String
    let on: Bool
    let amount: Double
    let toggle: () -> Void
    let save: (Double) -> Void
    @State private var entry = ClaudeBudgetEntry()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "dollarsign").font(.system(size: 16.5, weight: .medium)).foregroundStyle(palette.icon).frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(w(title)).font(.system(size: 14, weight: .medium)).tracking(-0.07).foregroundStyle(palette.title)
                    Text(ArisKoreanText.keepAll(w(ClaudeBudget.line(on ? amount : nil)))).font(.system(size: 12))
                        .foregroundStyle(palette.desc).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    field
                    ArisSwitch(isOn: on, label: ClaudeBudget.switchLabel, toggle: toggle)
                }
            }
            .padding(ArisSettingsMetrics.rowInset)
            // The mockup's `.under`: tucked 6 pt up into the row, under the card's hairline.
            VStack(spacing: 0) {
                Rectangle().fill(palette.hairline).frame(height: 1)
                HStack(spacing: 8) {
                    Text(w(ClaudeBudget.hint(entry.problem))).font(.system(size: 12))
                        .foregroundStyle(entry.problem == nil ? palette.ink3 : palette.red)
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        ForEach(ClaudeBudget.quick, id: \.self) { value in
                            ClaudeQuickAmount(title: ClaudeBudget.money(value), enabled: on) { pick(value) }
                        }
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 52, bottom: 16, trailing: 20))
            }
            .padding(.top, -6)
        }
    }

    private var field: some View {
        let bad = entry.problem != nil
        let text = entry.text(saved: amount)
        return Group {
            if still {
                Text(text).frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                TextField("", text: Binding(get: { text }, set: typed)).multilineTextAlignment(.trailing)
                    .focused($focused)
                    .onSubmit { entry = entry.settled() }
            }
        }
        .font(.system(size: 13).monospacedDigit())
        .modifier(ArisFieldStyle(focused: focused))
        .environment(\.arisFieldLeading, 24)
        .overlay(alignment: .leading) { Text("$").font(.system(size: 13)).foregroundStyle(palette.ink3).padding(.leading, 12).allowsHitTesting(false) }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.red, lineWidth: 1).opacity(bad ? 1 : 0))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.red.opacity(0.18), lineWidth: 2).padding(-2).opacity(bad ? 1 : 0))
        .frame(width: 112)
        .disabled(!on)
        .opacity(on ? 1 : 0.5)
        .animation(.easeOut(duration: 0.15), value: bad)
        .onChange(of: focused) { _, now in if !now { entry = entry.settled() } }
        .accessibilityLabel(w(ClaudeBudget.fieldLabel))
        .accessibilityValue(ClaudeBudget.money(amount))
        .accessibilityHint(w(ClaudeBudget.hint(entry.problem)))
    }

    private func typed(_ value: String) {
        let next = entry.typing(value)
        entry = next.entry
        if let dollars = next.save { save(dollars) }
    }

    private func pick(_ value: Double) {
        entry = ClaudeBudgetEntry()
        save(value)
    }
}

/// "$5": a small text button under the field (24 tall, r8), lit on hover.
private struct ClaudeQuickAmount: View {
    @Environment(\.arisPalette) private var palette
    let title: String
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12)).foregroundStyle(hovering && enabled ? palette.title : palette.desc)
                .padding(.horizontal, 8).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering && enabled ? palette.navFill : .clear))
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }
}
