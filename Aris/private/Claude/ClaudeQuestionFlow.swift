//
//  ClaudeQuestionFlow.swift
//  Aris
//
//  Answer state for one AskUserQuestion card: which question is showing and
//  what has been picked or typed. The store holds it (not the view), so a
//  redraw or a second display's notch never loses the picks. Every change
//  returns a new value.
//

import Foundation

struct QuestionFlow: Equatable {
    /// Keys that work while the card is armed, matched by physical key code (any input source).
    enum Key: Equatable {
        case option(Int), next, previous, submit, terminal

        private static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

        init?(keyCode: UInt16) {
            if let index = Self.digits.firstIndex(of: keyCode) { self = .option(index); return }
            switch keyCode {
            case 124, 48: self = .next
            case 123: self = .previous
            case 36, 76: self = .submit
            case 53: self = .terminal
            default: return nil
            }
        }
    }

    let questions: [ClaudeQuestion]
    let current: Int
    let picked: [String: Set<String>]
    let typed: [String: String]

    init(questions: [ClaudeQuestion]) {
        self.init(questions: questions, current: 0, picked: [:], typed: [:])
    }

    private init(questions: [ClaudeQuestion], current: Int, picked: [String: Set<String>], typed: [String: String]) {
        self.questions = questions
        self.current = current
        self.picked = picked
        self.typed = typed
    }

    var question: ClaudeQuestion? { questions.indices.contains(current) ? questions[current] : nil }

    /// One single-select question: a tap is the whole answer.
    var answersOnTap: Bool { questions.count == 1 && questions.first?.multiSelect == false }

    var isComplete: Bool { !questions.isEmpty && questions.allSatisfy { answer(for: $0) != nil } }

    /// Picked labels in option order, then any typed text; nil when nothing is chosen.
    func answer(for question: ClaudeQuestion) -> String? {
        let labels = question.options.map(\.label).filter { (picked[question.question] ?? []).contains($0) }
        let text = (typed[question.question] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = labels + (text.isEmpty ? [] : [text])
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var answers: [String: String] {
        Dictionary(uniqueKeysWithValues: questions.compactMap { question in answer(for: question).map { (question.question, $0) } })
    }

    func picking(_ label: String) -> QuestionFlow {
        guard let question else { return self }
        let current = picked[question.question] ?? []
        let next: Set<String> = question.multiSelect
            ? (current.contains(label) ? current.subtracting([label]) : current.union([label]))
            : [label]
        let changed = with(picked: picked.merging([question.question: next]) { _, new in new },
                           typed: question.multiSelect ? typed : typed.filter { $0.key != question.question })
        return question.multiSelect ? changed : changed.advancing()
    }

    func picking(index: Int) -> QuestionFlow {
        guard let options = question?.options, options.indices.contains(index) else { return self }
        return picking(options[index].label)
    }

    /// Typed "other" answer for the current question; for single-select it replaces the pick.
    func typing(_ text: String) -> QuestionFlow {
        guard let question else { return self }
        let picks = question.multiSelect || text.isEmpty ? picked : picked.filter { $0.key != question.question }
        return with(picked: picks, typed: typed.merging([question.question: text]) { _, new in new })
    }

    func moving(to index: Int) -> QuestionFlow {
        QuestionFlow(questions: questions, current: min(max(index, 0), max(questions.count - 1, 0)), picked: picked, typed: typed)
    }

    /// The next unanswered question after this one (wrapping), or stay when everything is answered.
    private func advancing() -> QuestionFlow {
        let order = questions.indices.map { (current + 1 + $0) % questions.count }
        guard let next = order.first(where: { answer(for: questions[$0]) == nil }) else { return self }
        return moving(to: next)
    }

    private func with(picked: [String: Set<String>], typed: [String: String]) -> QuestionFlow {
        QuestionFlow(questions: questions, current: current, picked: picked, typed: typed)
    }
}
