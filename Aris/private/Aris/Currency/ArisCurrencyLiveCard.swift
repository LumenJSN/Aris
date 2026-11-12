//
//  ArisCurrencyLiveCard.swift
//  Aris
//
//  The currency card as a light converter (the hidden preference arisCurrencyCard = live): the same card, with three
//  things to touch. The amount is a field: click it and type, and the result follows each key from the rate already
//  on the card (no request, no AI); Return or Esc leaves it. ↕ turns the pair round with the inverse rate and the
//  day's line turned over. A click on either code opens the app's one menu (the AI 서비스 page's: ArisAIMenuHost) with
//  the Mac's own currency, the six everyone uses and the last three he used; picking one is one request for the new
//  pair. Keyboard, while the field is being edited (the only time the notch has the keyboard: ArisPanelKeys): Tab goes
//  amount → the first code → the second, ↓ ↑ change a code through the same list, a digit goes back to the amount.
//  Nothing blinks or pulses; a press scales; the swap's arrows turn unless Reduce Motion is on.
//

import AppKit
import Combine
import SwiftUI

/// The live card's state and its one request. The view only draws it.
@MainActor
final class ArisCurrencyLiveModel: ObservableObject {
    /// The amount field is being edited: Esc only leaves the field (ArisWidgetModel's Esc otherwise lets the notch close).
    static var editing = false

    @Published private(set) var state: ArisCurrencyLive
    /// Where the keyboard is; nil while the field rests.
    @Published private(set) var stop: ArisCurrencyKeys.Stop?
    /// A code picked whose rate hasn't arrived: shown in its box, the result dimmed until it does.
    @Published private(set) var pending: (side: ArisCurrencyLive.Side, code: String)?
    /// The last picked pair's rate could not be read (the card stayed on the one it had).
    @Published private(set) var failed = false
    /// Counts the swaps: the arrows turn half round for each.
    @Published private(set) var swaps = 0
    /// The app's menu, as the settings pages open it.
    let menu = ArisAIServicesModel()
    private(set) var menuSide: ArisCurrencyLive.Side?
    /// Where the card and its two code boxes are, in global coordinates (the menu hangs from a box and the card makes
    /// room for it). Measured by the view; read when a menu opens.
    var cardBox = CGRect.zero
    var fromBox = CGRect.zero
    var toBox = CGRect.zero

    let home: String
    private(set) var recent: [String]
    /// The new pair's values for the words asked ("100 EUR CAD"): aris-agent's POST /currency in the app.
    private let fetch: (String) async -> [String: Any]?
    /// Called with the codes of a pair that was shown (the last-used list).
    private let used: ([String]) -> Void
    private var request: Task<Void, Never>?
    private var watching: AnyCancellable?
    /// How long a code stepped with ↓ ↑ rests before its rate is asked for.
    static let settle: Duration = .milliseconds(350)

    init(card: ArisCurrencyCard, home: String, recent: [String], fetch: @escaping (String) async -> [String: Any]?,
         used: @escaping ([String]) -> Void = { _ in }) {
        state = ArisCurrencyLive(card)
        self.home = home
        self.recent = recent
        self.fetch = fetch
        self.used = used
        // The menu closing itself (a click beside it) is a change here too: the card gives its room back.
        watching = menu.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        menu.perform = { [weak self] action in
            guard let self, case .pick(_, let code) = action, let side = self.menuSide else { return }
            self.menuSide = nil
            self.pick(code, for: side)
        }
    }

    var card: ArisCurrencyCard { state.card }
    var choices: [String] { ArisCurrencyLive.choices(home: home, recent: recent) }
    /// The result isn't this pair's and amount's yet.
    var waits: Bool { state.waits || pending != nil }

    func code(_ side: ArisCurrencyLive.Side) -> String {
        if let pending, pending.side == side { return pending.code }
        return side == .from ? card.from : card.to
    }

    // MARK: The amount

    func beginEditing() {
        state.beginEditing()
        stop = .amount
        failed = false
        Self.editing = true
    }

    func type(_ text: String) {
        // A digit typed while a code has the keyboard goes to the amount.
        stop = .amount
        state.type(text)
    }

    func endEditing() {
        guard stop != nil else { return }
        state.endEditing()
        stop = nil
        Self.editing = false
    }

    /// A key of the field, as AppKit names it; true when it was taken.
    func command(_ name: String) -> Bool {
        guard let stop else { return false }
        switch ArisCurrencyKeys.action(for: name, at: stop) {
        case .own: return false
        case .move(let next): self.stop = next
        case .leave: endEditing()
        case .step(let step):
            let side: ArisCurrencyLive.Side = stop == .from ? .from : .to
            let other = side == .from ? card.to : card.from
            pick(ArisCurrencyLive.stepped(code(side), by: step, in: choices, skipping: other), for: side, after: Self.settle)
        }
        return true
    }

    // MARK: The pair

    func swap() {
        guard pending == nil else { return }
        menu.menu = nil
        state.swap()
        swaps += 1
        failed = false
    }

    /// Opens the list under a code's box (`anchor`: the box, in global coordinates), or closes it when it is open.
    func toggleMenu(_ side: ArisCurrencyLive.Side, anchor: CGRect, english: Bool = ArisUIWords.english) {
        if menu.menu != nil, menuSide == side {
            menu.menu = nil
            menuSide = nil
            return
        }
        let current = code(side)
        let items = choices.map { code in
            ArisAIMenu.Entry.item(ArisAIMenuItem(id: code, title: code, tail: ArisCurrencyNames.name(code, korean: !english), checked: code == current))
        }
        menuSide = side
        menu.menu = .init(kind: .sheet("currency"), anchor: anchor, custom: ArisAIMenu(entries: items), byKey: false)
    }

    var menuOpen: ArisCurrencyLive.Side? { menu.menu == nil ? nil : menuSide }

    /// A code picked for a side: nothing, the pair turned round, or one request for the new pair (after `wait`, for a
    /// code still being stepped through).
    func pick(_ code: String, for side: ArisCurrencyLive.Side, after wait: Duration = .zero) {
        request?.cancel()
        pending = nil
        failed = false
        switch state.pick(code, for: side) {
        case .none: return
        case .swap: swap()
        case .fetch(let words):
            pending = (side, code)
            request = Task { [weak self] in
                if wait > .zero { try? await Task.sleep(for: wait) }
                guard !Task.isCancelled, let self else { return }
                let values = await self.fetch(words)
                guard !Task.isCancelled else { return }
                self.arrived(values, side: side, code: code)
            }
        }
    }

    private func arrived(_ values: [String: Any]?, side: ArisCurrencyLive.Side, code: String) {
        pending = nil
        let from = side == .from ? code : card.from, to = side == .to ? code : card.to
        // Only the pair that was picked: never another pair's rate under these codes.
        guard let fresh = values.flatMap({ ArisCurrencyCard.parse($0) }), fresh.from == from, fresh.to == to else {
            failed = true
            return
        }
        state.arrived(fresh)
        recent = ArisCurrencyLive.remembering([from, to], in: recent, home: home)
        used([from, to])
    }
}

/// The amount field: an AppKit field, so Tab, the arrows, Return and Esc are told apart exactly (doCommandBy), and
/// the notch's keyboard rule sees a real text field (ArisPanelKeys). It takes the keyboard as it appears.
struct ArisCurrencyAmountField: NSViewRepresentable {
    let text: String
    let typed: (String) -> Void
    let command: (String) -> Bool
    /// The field is still being edited (after a key that may have left it).
    let editing: () -> Bool
    let ended: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = ArisCurrencyTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedDigitSystemFont(ofSize: ArisCurrencyCardStyle.askedSize, weight: .medium)
        field.textColor = NSColor.white.withAlphaComponent(0.95)
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byClipping
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ArisCurrencyAmountField

        init(_ parent: ArisCurrencyAmountField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.typed(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let taken = parent.command(NSStringFromSelector(selector))
            // Return or Esc left the field: the keyboard is let go before the field is taken away, so the notch's
            // keyboard rule hands it back to the app he was in (ArisPanelKeys).
            if taken, !parent.editing() { control.window?.makeFirstResponder(nil) }
            return taken
        }

        func controlTextDidEndEditing(_ note: Notification) { parent.ended() }
    }
}

/// The field itself: once it is in its window it takes the keyboard, with the amount selected so a typed number
/// replaces it.
final class ArisCurrencyTextField: NSTextField {
    private var took = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !took else { return }
        took = true
        // After the layout pass that put it there (never inside it).
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            self.currentEditor()?.selectAll(nil)
        }
    }
}

/// A control's box: the amount and the two codes share it.
private struct ArisCurrencyBox: ViewModifier {
    var active = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .frame(height: ArisCurrencyCardStyle.controlHeight)
            .background(RoundedRectangle(cornerRadius: ArisCurrencyCardStyle.controlRadius, style: .continuous)
                .fill(active ? ArisCurrencyCardStyle.controlFillActive : ArisCurrencyCardStyle.controlFill))
            .overlay(RoundedRectangle(cornerRadius: ArisCurrencyCardStyle.controlRadius, style: .continuous)
                .strokeBorder(active ? ArisCurrencyCardStyle.controlLineActive : ArisCurrencyCardStyle.controlLine, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: ArisCurrencyCardStyle.controlRadius, style: .continuous))
    }
}

/// Press feedback for the card's buttons: 97%, 140 ms, none under Reduce Motion.
private struct ArisCurrencyPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !ArisSettingsMotion.reduced ? ArisCurrencyCardStyle.pressScale : 1)
            .animation(ArisCurrencyCardStyle.press, value: configuration.isPressed)
    }
}

struct ArisCurrencyLiveCard: View {
    @StateObject private var model: ArisCurrencyLiveModel
    var now: Date?
    var calendar: Calendar = .current
    var english = ArisUIWords.english
    /// Drawn once, off screen (the renders): the field as text with a still caret, the menu with no entrance.
    var still = false
    /// Brings the notch's keyboard to the field (the app's ArisPanelKeys); false: the press doesn't count as the user's.
    var takeKeyboard: () -> Bool = { true }

    private typealias Style = ArisCurrencyCardStyle

    init(model: @autoclosure @escaping () -> ArisCurrencyLiveModel, now: Date? = nil, calendar: Calendar = .current, english: Bool = ArisUIWords.english,
         still: Bool = false, takeKeyboard: @escaping () -> Bool = { true }) {
        _model = StateObject(wrappedValue: model())
        self.now = now
        self.calendar = calendar
        self.english = english
        self.still = still
        self.takeKeyboard = takeKeyboard
    }

    var body: some View {
        ArisCurrencyCardFrame(card: model.card, waits: model.waits, note: note, now: now, calendar: calendar, english: english) {
            amount
        } from: {
            code(.from, size: Style.askedSize, weight: .medium, ink: ArisWidgetStyle.ink92)
        } to: {
            code(.to, size: Style.codeSize, weight: .semibold, ink: ArisWidgetStyle.ink92)
        } corner: {
            swap
        }
        // Room for the menu's rows under the code it hangs from, while it is open.
        .frame(minHeight: menuHeight, alignment: .top)
        .modifier(ArisAIFrameReader(frame: box(\.cardBox)))
        .overlay {
            ArisAIMenuHost(model: model.menu).environment(\.colorScheme, .dark).environment(\.arisSettingsStill, still)
        }
        .animation(still || ArisSettingsMotion.reduced ? nil : ArisGlass.resize, value: model.menuOpen)
        .onDisappear { model.endEditing() }
    }

    private var note: String? {
        model.failed ? ArisCurrencyCopy.pickFailed(english: english) : ArisCurrencyCopy.note(model.card, english: english)
    }

    /// The card's least height while a menu is open: down to the bottom of five of its rows.
    private var menuHeight: CGFloat? {
        guard let side = model.menuOpen, model.cardBox != .zero else { return nil }
        let anchor = side == .from ? model.fromBox : model.toBox
        let rows = min(Style.menuRoom, CGFloat(model.choices.count) * Style.menuRow + 16)
        return anchor.maxY - model.cardBox.minY + ArisAIMenuMetrics.gap + rows + ArisAIMenuMetrics.edge
    }

    /// One of the model's measured boxes, for the reader that measures it.
    private func box(_ path: ReferenceWritableKeyPath<ArisCurrencyLiveModel, CGRect>) -> Binding<CGRect> {
        Binding(get: { model[keyPath: path] }, set: { model[keyPath: path] = $0 })
    }

    // MARK: Parts

    @ViewBuilder private var amount: some View {
        let editing = model.stop != nil
        Group {
            if editing, !still {
                ArisCurrencyAmountField(text: model.state.amountText, typed: { model.type($0) }, command: { model.command($0) },
                                        editing: { model.stop != nil }, ended: { model.endEditing() })
                    .frame(width: fieldWidth)
            } else {
                HStack(spacing: 1) {
                    Text(verbatim: model.state.amountText).font(.system(size: Style.askedSize, weight: .medium).monospacedDigit())
                        .foregroundStyle(ArisWidgetStyle.ink95).lineLimit(1)
                    // The render's caret: still.
                    if editing { Rectangle().fill(.white.opacity(0.9)).frame(width: 1.5, height: 15) }
                }
            }
        }
        .modifier(ArisCurrencyBox(active: model.stop == .amount))
        .onTapGesture {
            guard !editing, takeKeyboard() else { return }
            model.beginEditing()
        }
        .accessibilityLabel(ArisCurrencyCopy.amount(english: english))
        .accessibilityValue(model.state.amountText)
        .accessibilityAddTraits(.isButton)
    }

    /// Wide enough for what is typed, within the row.
    private var fieldWidth: CGFloat { min(150, max(34, CGFloat(model.state.amountText.count) * 8.4 + 6)) }

    private func code(_ side: ArisCurrencyLive.Side, size: CGFloat, weight: Font.Weight, ink: Color) -> some View {
        let stop: ArisCurrencyKeys.Stop = side == .from ? .from : .to
        let open = model.menuOpen == side
        return Button {
            model.toggleMenu(side, anchor: side == .from ? model.fromBox : model.toBox, english: english)
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: model.code(side)).font(.system(size: size, weight: weight)).foregroundStyle(ink)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.5))
            }
            .modifier(ArisCurrencyBox(active: open || model.stop == stop))
        }
        .buttonStyle(ArisCurrencyPress())
        .modifier(ArisAIFrameReader(frame: box(side == .from ? \.fromBox : \.toBox)))
        .accessibilityLabel(ArisCurrencyCopy.change(model.code(side), english: english))
    }

    private var swap: some View {
        Button { model.swap() } label: {
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                .rotationEffect(.degrees(still || ArisSettingsMotion.reduced ? 0 : Double(model.swaps) * 180))
                .animation(Style.turn, value: model.swaps)
                .frame(width: Style.swapSize, height: Style.swapSize)
                .background(Circle().fill(Style.controlFill))
                .overlay(Circle().strokeBorder(Style.controlLine, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(ArisCurrencyPress())
        .help(ArisCurrencyCopy.swap(english: english))
        .accessibilityLabel(ArisCurrencyCopy.swap(english: english))
    }
}
