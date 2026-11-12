//
//  ArisSettingsControls.swift
//  Aris
//
//  The settings window's controls, drawn to mockup C's numbers: the switch (40 × 24,
//  #30d158, 220 ms (0.32, 0.72, 0, 1)), the glass sliding segmented control (thumb left 0.4 s (0.22, 1, 0.36, 1)),
//  the buttons (30 tall r12, small 26 r10), chips, key caps, the field (36 r12, 2 pt focus ring), the range slider
//  and the accent swatches. Presses scale to 0.98 (emil-design-eng); hovers are colour changes on a plain ease.
//

import AppKit
import SwiftUI

// MARK: - Switch

struct ArisSwitch: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let isOn: Bool
    var enabled = true
    let label: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) { ArisSwitchFace(isOn: isOn) }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
            .accessibilityLabel(w(label))
            .accessibilityValue(w(isOn ? "켬" : "끔"))
            .accessibilityAddTraits(.isToggle)
    }
}

/// The switch's look alone (a tile draws it inside its own button).
struct ArisSwitchFace: View {
    @Environment(\.arisPalette) private var palette
    let isOn: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(isOn ? palette.switchOn : palette.switchOff)
            Circle().fill(.white).frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                .offset(x: isOn ? 18 : 2)
        }
        .frame(width: 40, height: 24)
        .animation(ArisSettingsMotion.reduced ? .easeOut(duration: 0.15) : ArisSettingsMotion.toggle, value: isOn)
    }
}

// MARK: - Segmented

/// The glass segmented control: a 4-point track, a sheen thumb that slides to the choice.
struct ArisGlassSegmented: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    /// The choices as given; they are drawn (and measured) in the page's wording.
    let given: [ArisSettingOption]
    let selected: String
    var disabled: Set<String> = []
    let label: String
    let choose: (String) -> Void
    @State private var hovered: String?

    init(options: [ArisSettingOption], selected: String, disabled: Set<String> = [], label: String, choose: @escaping (String) -> Void) {
        given = options
        self.selected = selected
        self.disabled = disabled
        self.label = label
        self.choose = choose
    }

    private var options: [ArisSettingOption] { given.map { ArisSettingOption(id: $0.id, title: w($0.title), detail: $0.detail) } }

    /// The glass tab: 13/500, 16 each side, 6 above and below on a 1.5 line: 31.5 tall.
    private static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let side: CGFloat = 16
    private static let height: CGFloat = 31.5

    private func width(_ option: ArisSettingOption) -> CGFloat {
        let text = ceil((option.title as NSString).size(withAttributes: [.font: Self.font]).width)
        return text + Self.side * 2
    }

    var body: some View {
        let options = options
        let widths = options.map(width)
        let index = options.firstIndex { $0.id == selected } ?? 0
        ZStack(alignment: .leading) {
            Capsule().fill(palette.glassThumb)
                .overlay(Capsule().strokeBorder(palette.glassThumbBorder, lineWidth: 0.5))
                .shadow(color: palette.glassThumbShadow, radius: palette.dark ? 5 : 4, y: 2)
                .frame(width: widths.isEmpty ? 0 : widths[index], height: Self.height)
                .offset(x: widths.prefix(index).reduce(0, +))
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { offset, option in segment(option, width: widths[offset]) }
            }
        }
        .padding(4)
        .background(Capsule().fill(palette.glassTrack))
        .overlay(Capsule().strokeBorder(palette.glassTrackBorder, lineWidth: 0.5))
        .animation(ArisSettingsMotion.reduced ? .easeOut(duration: 0.15) : ArisSettingsMotion.house(0.4), value: selected)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(w(label))
    }

    private func segment(_ option: ArisSettingOption, width: CGFloat) -> some View {
        let on = option.id == selected, off = disabled.contains(option.id)
        return Button { choose(option.id) } label: {
            Text(option.title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(on ? palette.glassOn : hovered == option.id && !off ? palette.navHover : palette.glassIdle)
            .animation(.easeInOut(duration: 0.25), value: on)
            .frame(width: width, height: Self.height)
            .contentShape(Capsule())
        }
        .buttonStyle(ArisPressScale(scale: ArisPressScale.light))
        .disabled(off)
        .opacity(off ? 0.45 : 1)
        .onHover { hovered = $0 ? option.id : (hovered == option.id ? nil : hovered) }
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Buttons

/// Press feedback for anything pressable: a button goes to 0.97 over 140 ms on a strong ease-out (emil-design-eng:
/// 0.97, 100–160 ms); menu items, glass tabs and the select pass 0.98, key caps 0.95. Still under Reduce Motion.
struct ArisPressScale: ButtonStyle {
    var scale: CGFloat = 0.97
    /// The lighter press for menu items, glass tabs and pills.
    static let light: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !ArisSettingsMotion.reduced ? scale : 1)
            .animation(ArisSettingsMotion.press, value: configuration.isPressed)
    }
}

/// The window's button: ghost, primary (black / near-white), danger (red-600 on red-50, in dark red-400 on
/// red-500/10, a 20–30% red border), and solid red for a sheet's last word.
struct ArisSettingsButton: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let title: String
    var kind = ArisSettingButtonKind.ghost
    var small = false
    var enabled = true
    var minWidth: CGFloat?
    var trailingSymbol: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: small ? 10 : 12, style: .continuous)
        Button(action: action) {
            HStack(spacing: 6) {
                Text(w(title)).lineLimit(1)
                if let trailingSymbol {
                    if minWidth != nil { Spacer(minLength: 4) }
                    Image(systemName: trailingSymbol).font(.system(size: 10, weight: .semibold))
                }
            }
            .font(.system(size: 12, weight: kind == .ghost || kind == .danger ? .medium : .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, small ? 10 : 12)
            .frame(minWidth: minWidth, minHeight: small ? 26 : 30, maxHeight: small ? 26 : 30)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .contentShape(shape)
            .animation(.easeInOut(duration: 0.2), value: hovering)
        }
        .buttonStyle(ArisPressScale())
        // A button that can't be pressed yet keeps its place at half strength: it never hides, so nothing beside it
        // moves when it wakes.
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 && enabled }
        .fixedSize()
    }

    private var ink: Color {
        switch kind {
        case .ghost: hovering ? palette.buttonTextHover : palette.buttonText
        case .primary: palette.primaryInk
        case .danger: palette.red
        case .solidRed: .white
        }
    }

    private var fill: AnyShapeStyle {
        switch kind {
        case .ghost: AnyShapeStyle(palette.buttonFill)
        case .primary: AnyShapeStyle(hovering ? palette.primaryHover : palette.primary)
        case .danger: AnyShapeStyle(hovering ? palette.redFillHover : palette.redFill)
        case .solidRed: AnyShapeStyle(palette.solidRed)
        }
    }

    private var border: Color {
        switch kind {
        case .ghost: hovering ? palette.buttonBorderHover : palette.buttonBorder
        case .primary: hovering ? palette.primaryHover : palette.primary
        case .danger: palette.redBorder
        case .solidRed: palette.solidRed
        }
    }
}

// MARK: - Chips and caps

struct ArisChip: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let text: String
    var tone = ArisChipTone.plain

    var body: some View {
        Text(w(text)).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            .foregroundStyle(tone == .ok ? palette.ok : tone == .warn ? palette.warn : palette.desc)
            .padding(.horizontal, 8).frame(height: 20)
            .background(Capsule().fill(tone == .ok ? palette.okFill : palette.chip))
            .fixedSize()
    }
}

/// A key cap: 28 square at least, r8, 12/600, a soft raised fill; blue while recording.
struct ArisKeyCap: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let text: String
    var recording = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Text(w(text)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            .foregroundStyle(recording ? palette.capRecordingInk : palette.title)
            .padding(.horizontal, 8).frame(minWidth: 28, minHeight: 28)
            .background(shape.fill(recording ? palette.capRecording : palette.capFill))
            .overlay(shape.strokeBorder(recording ? palette.capRecordingBorder : palette.capBorder, lineWidth: 1))
            .shadow(color: palette.capShadow, radius: 1.5, x: 1, y: 2)
            .fixedSize()
    }
}

/// Caps for a shortcut (없음 when there is none); pressing them records a new one (ArisShortcutRecorder). Under the
/// pointer, or with the keyboard on them, 바꾸기 appears before them: every key of Aris's can be changed, and the caps
/// say so where they are (item 18). While it records, esc cancels and (for a shortcut that may be empty) ⌫ or 지우기
/// clears it.
struct ArisShortcutCapsButton: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsStill) private var still
    let caps: [String]
    let recording: Bool
    let label: String
    /// False for a key that can't be none (the dictation key): there is nothing to clear.
    var clearable = true
    let toggle: () -> Void
    let clear: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if recording {
                Text(w(clearable ? "esc 취소 · ⌫ 지우기" : "esc 취소")).font(.system(size: 11)).foregroundStyle(palette.ink3)
                if clearable { ArisSettingsButton(title: "지우기", kind: .danger, small: true, action: clear) }
            } else {
                Text(w("바꾸기")).font(.system(size: 11)).foregroundStyle(palette.ink3)
                    .opacity(hovering || focused ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: hovering || focused)
                    .accessibilityHidden(true)
            }
            Button(action: toggle) {
                HStack(spacing: 4) {
                    if recording {
                        ArisKeyCap(text: "키를 누르세요", recording: true)
                    } else if caps.isEmpty {
                        ArisChip(text: "없음")
                    } else {
                        ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in ArisKeyCap(text: cap) }
                    }
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            // Key caps press to 0.95.
            .buttonStyle(ArisPressScale(scale: 0.95))
            .focused($focused)
            .accessibilityLabel(w("\(w(label)) 단축키 바꾸기"))
            .accessibilityValue(recording ? w("키를 기다리는 중") : caps.isEmpty ? w("없음") : caps.joined(separator: " "))
        }
        .onHover { hovering = $0 }
    }
}

/// A key that can't be changed, as plain words (none of Aris's own is fixed any more; a row may still name one).
struct ArisFixedKey: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let caps: [String]

    var body: some View {
        Text(caps.map { w($0) }.joined(separator: " ")).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.desc).lineLimit(1).fixedSize()
    }
}

// MARK: - Field, slider, swatches

private struct FieldLeadingKey: EnvironmentKey { static let defaultValue: CGFloat = 12 }

extension EnvironmentValues {
    /// Room at a field's start (the search field's magnifier).
    var arisFieldLeading: CGFloat {
        get { self[FieldLeadingKey.self] }
        set { self[FieldLeadingKey.self] = newValue }
    }
}


/// The field's look: 36 tall (14-pt text, 8 above and below), r12, a 1-pt line that darkens on focus
/// with a 2-pt ring.
struct ArisFieldStyle: ViewModifier {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisFieldLeading) private var leading
    let focused: Bool
    var height: CGFloat = 36

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(palette.title)
            .padding(.leading, leading).padding(.trailing, 12).frame(height: height)
            .background(shape.fill(palette.field).shadow(color: palette.fieldShadow, radius: palette.dark ? 2 : 0.5, y: palette.dark ? 1 : 0.5))
            .overlay(shape.strokeBorder(focused ? palette.fieldFocus : palette.fieldBorder, lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(focused ? palette.fieldRing : .clear, lineWidth: 2).padding(-2))
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

struct ArisTextField: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    /// The words in the empty field, as given; drawn in the page's wording.
    let hint: String
    @Environment(\.arisSettingsStill) private var still
    @Binding var text: String
    var width: CGFloat?
    var secure = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    init(placeholder: String, text: Binding<String>, width: CGFloat? = nil, secure: Bool = false, onSubmit: @escaping () -> Void = {}) {
        hint = placeholder
        _text = text
        self.width = width
        self.secure = secure
        self.onSubmit = onSubmit
    }

    private var placeholder: String { w(hint) }

    var body: some View {
        Group {
            if still {
                Text(text.isEmpty ? placeholder : secure ? String(repeating: "•", count: text.count) : text)
                    .foregroundStyle(text.isEmpty ? palette.ink3 : palette.title).frame(maxWidth: .infinity, alignment: .leading)
            } else if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
        }
        .focused($focused)
        .onSubmit(onSubmit)
        .modifier(ArisFieldStyle(focused: focused))
        .frame(width: width)
        .accessibilityLabel(placeholder)
    }
}

/// The range input (item 10): its value written beside it in tabular figures, a 4-pt track 170 wide whose travelled
/// part is filled, and a 20-pt white thumb that presses to 0.94. With the keyboard on it (Tab), ← and → move it a step.
struct ArisRangeSlider: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let value: Double
    let range: ClosedRange<Double>
    let label: String
    let change: (Double) -> Void
    /// The drag began (true) or ended: what listens for the value hears it only then.
    var editing: (Bool) -> Void = { _ in }
    /// What one notch of the slider is (ArisSliderStep): 1 moves in whole numbers, 0.1 in tenths.
    var step: Double = 1
    /// The value as it is written beside the track ("0.3초"); nil draws the track alone.
    var said: String?
    var width: CGFloat = 170
    @State private var dragging = false
    @FocusState private var focused: Bool

    var body: some View {
        let span = range.upperBound - range.lowerBound
        let x = CGFloat((value - range.lowerBound) / span) * (width - 20)
        HStack(spacing: 10) {
            if let said {
                Text(said).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(palette.desc)
                    .frame(minWidth: 38, alignment: .trailing).fixedSize()
                    .accessibilityHidden(true)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(palette.switchOff).frame(height: 4)
                Capsule().fill(palette.title).frame(width: x + 10, height: 4)
                Circle().fill(.white).frame(width: 20, height: 20).shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .scaleEffect(dragging && !ArisSettingsMotion.reduced ? 0.94 : 1)
                    .animation(ArisSettingsMotion.press, value: dragging)
                    .offset(x: x)
            }
            .frame(width: width, height: 24)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                if !dragging {
                    dragging = true
                    editing(true)
                }
                let next = ArisSliderStep.value(at: Double((drag.location.x - 10) / (width - 20)), in: range, step: step)
                if next != value { change(next) }
            }.onEnded { _ in
                dragging = false
                editing(false)
            })
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .modifier(ArisFocusRing(shown: focused, radius: 12, inset: -4))
            .onKeyPress(.leftArrow) { nudge(up: false) }
            .onKeyPress(.rightArrow) { nudge(up: true) }
        }
        .accessibilityElement()
        .accessibilityLabel(w(label))
        .accessibilityValue(said ?? ArisSliderStep.spoken(value, step: step))
        .accessibilityAdjustableAction { direction in _ = nudge(up: direction == .increment) }
    }

    /// One step with a key: the value moves at once (a key repeats; nothing is animated), and what listens hears it.
    private func nudge(up: Bool) -> KeyPress.Result {
        let next = ArisSliderStep.nudge(value, up: up, in: range, step: step)
        if next != value {
            change(next)
            editing(false)
        }
        return .handled
    }
}

/// The ring a control wears while the keyboard is on it: 2 pt of the accent at 40%, 2 pt clear of the control.
struct ArisFocusRing: ViewModifier {
    @Environment(\.arisPalette) private var palette
    let shown: Bool
    var radius: CGFloat = 12
    var inset: CGFloat = -2

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius + 2, style: .continuous).strokeBorder(palette.accent.opacity(shown ? 0.4 : 0), lineWidth: 2)
                .padding(inset - 2).allowsHitTesting(false)
        )
    }
}

/// The accent colours as 22-pt dots, the picked one ringed; the last opens the colour panel.
struct ArisSwatches: View {
    @Environment(\.arisWords) private var w
    let colors: [String]
    let selected: String?
    let pick: (String) -> Void
    let custom: () -> Void

    var body: some View {
        let isCustom = selected.map { !colors.contains($0) } ?? false
        HStack(spacing: 10) {
            ForEach(colors, id: \.self) { hex in
                dot(Color(arisHexString: hex) ?? .gray, selected: selected == hex, label: "색 \(hex)") { pick(hex) }
            }
            dot(nil, selected: isCustom, label: "다른 색 고르기", action: custom)
        }
    }

    private func dot(_ color: Color?, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let color { Circle().fill(color) } else {
                    Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                }
            }
            .overlay(Circle().strokeBorder(.black.opacity(0.1), lineWidth: 1))
            .frame(width: 22, height: 22)
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? (color ?? .primary) : .clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(ArisPressScale(scale: 0.92))
        .accessibilityLabel(w(label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A removable language chip.
struct ArisRemovableChip: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let title: String
    let removable: Bool
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(w(title)).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.title)
            if removable {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(hovering ? palette.title : palette.ink3)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(hovering ? palette.navFill : .clear))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .accessibilityLabel(w("\(w(title)) 빼기"))
            }
        }
        .padding(.leading, 12).padding(.trailing, removable ? 6 : 12).frame(height: 30)
        .background(Capsule().fill(palette.chip))
        .overlay(Capsule().strokeBorder(palette.hairline, lineWidth: 1))
    }
}

// MARK: - Landing highlight

/// A search result's row lands highlighted: an accent ring and wash that fade out once (no pulse).
struct ArisFlash: ViewModifier {
    @Environment(\.arisPalette) private var palette
    let token: Int?
    let radius: CGFloat
    @State private var shown = 0.0

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(palette.accent.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(palette.accent.opacity(0.55), lineWidth: 2))
                    .opacity(shown)
                    .allowsHitTesting(false)
            )
            .onAppear { land(token) }
            .onChange(of: token) { _, next in land(next) }
    }

    private func land(_ token: Int?) {
        guard token != nil else { return }
        shown = 1
        withAnimation(.easeOut(duration: 0.8).delay(1.0)) { shown = 0 }
    }
}
