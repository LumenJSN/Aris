//
//  ClaudeAnswerViews.swift
//  Aris
//
//  Controls for answering Claude Code's questions and plan approvals.
//

import SwiftUI

/// One question at a time: step chips, the options (pills, or rows when they carry
/// descriptions), a typed "other" answer and Submit. The picks live in the store.
struct QuestionCard: View {
    let id: UUID
    let flow: QuestionFlow

    @State private var hovered: String?
    private var store: ClaudeStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if flow.questions.count > 1 {
                StepChips(flow: flow) { index in store.updateFlow(id) { $0.moving(to: index) } }
            }
            // Every question is laid out (only the current one shown) so the card keeps the tallest
            // one's height: the notch doesn't jump, or slide out from under the pointer, while stepping.
            ZStack(alignment: .topLeading) {
                ForEach(Array(flow.questions.enumerated()), id: \.offset) { index, question in
                    let shown = index == flow.current
                    VStack(alignment: .leading, spacing: 8) {
                        QuestionBody(question: question, picked: flow.picked[question.question] ?? [], hovered: $hovered) { label in
                            store.pick(label, in: id)
                        }
                        if shown {
                            OtherField(text: flow.typed[question.question] ?? "",
                                       onChange: { text in store.updateFlow(id) { $0.typing(text) } },
                                       onReturn: returnPressed)
                        } else {
                            // Same height, but no live field: leaving a question drops its text focus,
                            // so number keys pick again.
                            OtherField(text: "", onChange: { _ in }, onReturn: {}).hidden()
                        }
                    }
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown)
                }
            }
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if flow.questions.count > 1 {
                Text(flow.questions.map { flow.answer(for: $0) ?? "—" }.joined(separator: "  ·  "))
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Button { store.decide(id, .passthrough) } label: { KeyHintLabel("Terminal", key: "esc") }
                .buttonStyle(.notch(.quiet))
            if !flow.answersOnTap {
                Button { store.submit(id) } label: { KeyHintLabel("Submit", key: "↩") }
                    .buttonStyle(.notch(.primary))
                    .disabled(!flow.isComplete)
            }
        }
    }

    /// Return in the text field: send when everything is answered, else go to the next question.
    private func returnPressed() {
        if flow.isComplete { store.submit(id) } else { store.updateFlow(id) { $0.moving(to: $0.current + 1) } }
    }
}

/// "Color ✓  Font  Extras": where you are, what's answered, tap to jump.
private struct StepChips: View {
    let flow: QuestionFlow
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(flow.questions.enumerated()), id: \.offset) { index, question in
                let answered = flow.answer(for: question) != nil
                Button { onPick(index) } label: {
                    HStack(spacing: 4) {
                        if answered { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                        Text(question.header.isEmpty ? "Q\(index + 1)" : question.header).lineLimit(1)
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(index == flow.current ? .white : (answered ? .green : .gray))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(index == flow.current ? 0.2 : 0.06)))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Text("\(flow.current + 1)/\(flow.questions.count)")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.gray)
        }
    }
}

private struct QuestionBody: View {
    let question: ClaudeQuestion
    let picked: Set<String>
    @Binding var hovered: String?
    let onPick: (String) -> Void

    private var detailed: Bool { question.options.contains { !$0.detail.isEmpty || $0.preview != nil } }
    private var preview: String? {
        let focus = hovered ?? question.options.first { picked.contains($0.label) }?.label
        return question.options.first { $0.label == focus }?.preview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(question.question)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if question.multiSelect {
                    Text("pick any").font(.system(size: 10.5)).foregroundStyle(.gray)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                options
                if let preview {
                    PreviewBox(text: preview)
                }
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        let numbered = Array(question.options.prefix(9).enumerated())
        if detailed {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(numbered, id: \.element.label) { index, option in
                    OptionRow(number: index + 1, option: option, selected: picked.contains(option.label),
                              hovered: $hovered) { onPick(option.label) }
                }
            }
        } else {
            HStack(spacing: 8) {
                ForEach(numbered, id: \.element.label) { index, option in
                    OptionPill(number: index + 1, label: option.label, selected: picked.contains(option.label)) {
                        onPick(option.label)
                    }
                }
            }
        }
    }
}

private struct OptionPill: View {
    let number: Int
    let label: String
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("\(number)").font(.system(size: 10, weight: .bold, design: .rounded)).opacity(0.45)
                Text(label).font(.system(size: 13, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? .black : .white)
            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(hovering ? 0.24 : 0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Option with Claude's description underneath, like the terminal's own picker.
private struct OptionRow: View {
    let number: Int
    let option: ClaudeOption
    let selected: Bool
    @Binding var hovered: String?
    let action: () -> Void

    private var isHovered: Bool { hovered == option.label }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.white.opacity(selected ? 0.9 : 0.12)))
                    .foregroundStyle(selected ? .black : .white)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    if !option.detail.isEmpty {
                        Text(option.detail).font(.system(size: 11)).foregroundStyle(.gray).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(selected ? 0.16 : (isHovered ? 0.09 : 0.04))))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = option.label } else if isHovered { hovered = nil }
        }
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PreviewBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }
}

/// "Other…": a typed answer. Typing works while the pointer is on the card (the notch takes key focus then).
private struct OtherField: View {
    let text: String
    let onChange: (String) -> Void
    let onReturn: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(.gray)
            TextField("Other…", text: Binding(get: { text }, set: onChange))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .onSubmit(onReturn)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(text.isEmpty ? 0.04 : 0.1)))
    }
}

/// ExitPlanMode: show the plan and jump to the terminal to approve it.
struct PlanCard: View {
    let plan: String
    let onDecide: (ClaudeDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan ready for review")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(plan.isEmpty ? "Claude wants to leave plan mode." : plan)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(14)
                .fixedSize(horizontal: false, vertical: true)
            // Claude Code only takes a plan approval from its own dialog, so the card leads there.
            Button { onDecide(.passthrough) } label: { KeyHintLabel("Approve in terminal", key: "Y") }
                .buttonStyle(.notch(.primary))
        }
    }
}
