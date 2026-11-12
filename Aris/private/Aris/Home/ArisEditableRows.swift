//
//  ArisEditableRows.swift
//  Aris
//
//  The owner's ②A (mockups/new-features.html §2, A): the confirm card's values as rows the user can change before they says yes.
//  A label column 72 wide (11.5 medium, white 38%), the value at 12.5 (white 92%), rows 9 apart with a white-5% rule on
//  top. Click a value to type in it (Return or leaving the card ends it). A changed value gets the yellow highlighter
//  (rgba 255 214 10 / .34, the line's lower 52–94%) wiped in over 320 ms, and right under it "원래 ~~what the AI wrote~~"
//  at 11, fading in over 0.2 s. Changing it back takes both away. A time also reads as words ("오늘 오후 6:00").
//

import SwiftUI

/// The values of the card that waits now (ArisController.askUser starts it; the voice changes it too).
@MainActor
final class ArisCardEditor: ObservableObject {
    static let shared = ArisCardEditor()

    @Published private(set) var id: String?
    @Published private(set) var values: [String: String] = [:]
    /// The fields a spoken change just set (their highlighter wipes in again).
    @Published private(set) var revised: Set<String> = []
    /// A field has the keyboard (the card keeps waiting: ArisCardTiming).
    @Published private(set) var typing = false
    /// When a value last changed (system uptime), typed or spoken.
    private(set) var changedAt: Double?
    private var fields: [ArisCardField] = []

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    func start(_ ask: ArisConfirmation) {
        id = ask.id
        fields = ask.fields
        values = ArisCardEdit.values(ask.fields)
        revised = []
        typing = false
        changedAt = nil
    }

    func setTyping(_ on: Bool) {
        if typing != on { typing = on }
    }

    /// Whether a click or Y may say yes now: every value as aris-tools must read it, and no change in the last second
    /// (`changedBefore`: the time of the last change before the click ended any typing).
    func yesCounts(changedBefore: Double?) -> Bool {
        ArisCardEdit.allAccepted(fields, values) && ArisCardTiming.clickCounts(changedAt: changedBefore, now: Self.now)
    }

    func keepsWaiting() -> Bool {
        ArisCardTiming.keepsWaiting(typing: typing, changedAt: changedAt, now: Self.now)
    }

    func values(for ask: ArisConfirmation) -> [String: String] {
        id == ask.id ? values : ArisCardEdit.values(ask.fields)
    }

    func set(_ key: String, _ value: String) {
        guard values[key] != value else { return }
        values = values.merging([key: value]) { $1 }
        changedAt = Self.now
    }

    func revise(_ change: [String: String]) {
        values = values.merging(change) { $1 }
        revised = Set(change.keys)
        changedAt = Self.now
    }
}

struct ArisEditableRows: View {
    let question: ArisConfirmation
    /// The card is drawn in English (ArisConfirmCard): the fields' labels and the hints with it.
    var english = false
    @ObservedObject private var editor = ArisCardEditor.shared
    /// The field being typed in.
    @State private var editing: String?
    @FocusState private var focused: String?

    static let labelWidth: CGFloat = 72
    static let mark = Color(red: 1, green: 214 / 255, blue: 10 / 255).opacity(0.34)
    static let valueSize: CGFloat = 12.5
    static let lineSpacing: CGFloat = 3.5

    var body: some View {
        let values = editor.values(for: question)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(question.fields, id: \.key) { field in
                row(field, value: values[field.key] ?? field.value, marked: ArisCardEdit.isMarked(field, values))
            }
        }
        .onChange(of: focused) { _, now in
            if now == nil { editing = nil }
            editor.setTyping(now != nil)
        }
    }

    private func row(_ field: ArisCardField, value: String, marked: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(english ? ArisCardEnglish.label(field.label) : field.label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.38))
                .frame(width: Self.labelWidth, alignment: .leading).padding(.top, 3)
            VStack(alignment: .leading, spacing: 0) {
                if field.fixed {
                    Text(value).font(.system(size: Self.valueSize)).foregroundStyle(.white.opacity(0.62)).padding(.horizontal, 3).padding(.vertical, 1)
                } else if editing == field.key {
                    input(field, value: value, marked: marked)
                } else {
                    shown(field, value: value, marked: marked)
                }
                if !field.fixed, !ArisCardEdit.accepts(value, role: field.role) {
                    Text(ArisConfirmWords.refused(time: field.role == .time, english: english))
                        .font(.system(size: 11)).foregroundStyle(Color(red: 240 / 255, green: 185 / 255, blue: 90 / 255).opacity(0.95))
                        .padding(.horizontal, 3)
                }
                if field.role == .time, let words = ArisCardTime.friendly(value, english: english) {
                    Text(words).font(.system(size: 11)).foregroundStyle(.white.opacity(0.38)).padding(.horizontal, 3)
                }
                if marked {
                    (Text(ArisConfirmWords.was(english: english)) + Text(field.first).strikethrough().foregroundColor(.white.opacity(0.43)))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.38))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(EdgeInsets(top: 2, leading: 3, bottom: 0, trailing: 3))
                        .transition(.opacity.animation(.easeOut(duration: 0.2)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.05)).frame(height: 1) }
        .animation(.easeOut(duration: 0.2), value: marked)
    }

    /// The value as text, highlighted when changed; a click starts typing in it.
    private func shown(_ field: ArisCardField, value: String, marked: Bool) -> some View {
        ArisMarkedText(text: value, marked: marked, rewipe: editor.revised.contains(field.key))
            .contentShape(Rectangle())
            .onTapGesture {
                editing = field.key
                focused = field.key
            }
            .help(ArisConfirmWords.editHelp(english: english))
    }

    private func input(_ field: ArisCardField, value: String, marked: Bool) -> some View {
        TextField("", text: Binding(get: { value }, set: { editor.set(field.key, $0) }), axis: field.role == .text ? .vertical : .horizontal)
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .font(.system(size: Self.valueSize))
            .lineSpacing(Self.lineSpacing)
            .foregroundStyle(.white.opacity(0.92))
            .focused($focused, equals: field.key)
            .onSubmit { focused = nil }
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.white.opacity(marked ? 0.06 : 0.032)))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
}

/// A value with the yellow highlighter along each of its lines (the lower 52–94%), wiped in left to right over 320 ms.
struct ArisMarkedText: View {
    let text: String
    let marked: Bool
    /// A spoken change set it: the wipe runs again.
    var rewipe = false
    @State private var progress: Double = 0

    var body: some View {
        label
            .onAppear { progress = marked ? 1 : 0 }
            .onChange(of: marked) { _, now in withAnimation(Self.wipe) { progress = now ? 1 : 0 } }
            .onChange(of: text) { _, _ in
                guard marked, rewipe else { return }
                progress = 0
                withAnimation(Self.wipe) { progress = 1 }
            }
    }

    /// 320 ms on the mockup's ease-out (0.23, 1, 0.32, 1).
    static let wipe = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.32)

    @ViewBuilder private var label: some View {
        let base = Text(text).font(.system(size: ArisEditableRows.valueSize)).foregroundColor(.white.opacity(0.92))
        Group {
            if #available(macOS 15.0, *) {
                base.textRenderer(ArisMarkRenderer(progress: progress))
            } else {
                base.background(alignment: .leading) {
                    GeometryReader { box in
                        ArisEditableRows.mark.frame(width: box.size.width * progress, height: box.size.height * 0.42)
                            .offset(y: box.size.height * 0.52)
                    }
                }
            }
        }
        .lineSpacing(ArisEditableRows.lineSpacing)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 3).padding(.vertical, 1)
    }
}

/// Draws the highlighter band under each line, `progress` of the way along all of them, then the line.
@available(macOS 15.0, *)
struct ArisMarkRenderer: TextRenderer {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let total = layout.reduce(0) { $0 + $1.typographicBounds.width }
        var left = total * progress
        for line in layout {
            let bounds = line.typographicBounds.rect
            let width = min(bounds.width, max(0, left))
            left -= bounds.width
            if width > 0 {
                let height = bounds.height
                let band = CGRect(x: bounds.minX - 2, y: bounds.minY + height * 0.52, width: width + 4, height: height * 0.42)
                context.fill(Path(roundedRect: band, cornerRadius: 3), with: .color(ArisEditableRows.mark))
            }
            context.draw(line)
        }
    }
}
