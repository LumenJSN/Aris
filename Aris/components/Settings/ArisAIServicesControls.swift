//
//  ArisAIServicesControls.swift
//  Aris
//
//  AI 서비스's own controls, to the mockup's numbers (ai-services-D.html): the dropdown button (40 tall, r12, 12
//  inside, 14/500, the field's fill, line and inset shadow, a chevron), the thin download bar, and a button with a
//  leading icon. Also the page's view state: what is open (a menu, a sheet) and what is typed, with the actions
//  handed in, so the same views draw from fixtures offscreen.
//

import AppKit
import SwiftUI

/// What the AI 서비스 views share: the page's state, the open dropdown and sheet, and what is typed into open fields.
/// It does nothing itself: ArisAIServicesLive (the app) or a fixture (the offscreen renders) fills it and takes its actions.
@MainActor
final class ArisAIServicesModel: ObservableObject {
    struct OpenMenu: Equatable {
        var kind: ArisAIMenuKind
        /// The button it opened from, in global coordinates.
        var anchor: CGRect
        var query = ""
        /// A sheet's own dropdown: its items (the page's dropdowns are built from the state).
        var custom: ArisAIMenu?
        /// Its one highlighted row: the keyboard's and the pointer's alike.
        var highlight = ArisAIMenuHighlight()
    }

    @Published var state = ArisAIServicesState()
    @Published var menu: OpenMenu?
    @Published var sheet: ArisAISheet?
    /// Typed text by field: "key:<holder>", "jev", "model:<id>".
    @Published var drafts: [String: String] = [:]
    var perform: (ArisAIAction) -> Void = { _ in }
    var performSheet: (ArisAISheetAction) -> Void = { _ in }

    var page: ArisAIPage { ArisAIServicesBuilder.page(state) }

    /// Opens a dropdown under `anchor` (or closes it when it is the one open).
    func toggle(_ kind: ArisAIMenuKind, anchor: CGRect, custom: ArisAIMenu? = nil) {
        menu = menu?.kind == kind ? nil : OpenMenu(kind: kind, anchor: anchor, custom: custom)
    }

    /// The open dropdown's content.
    var openMenu: ArisAIMenu? {
        menu.map { $0.custom?.filtered(by: $0.query) ?? ArisAIServicesBuilder.menu($0.kind, state, query: $0.query) }
    }

    /// ↓ or ↑ in the open dropdown.
    func moveHighlight(_ step: Int) {
        guard let open = menu, let content = openMenu else { return }
        menu?.highlight = open.highlight.moved(step, in: content, pointer: NSEvent.mouseLocation)
    }

    /// A letter typed in the open dropdown: the highlight goes to the next item that starts with it (`said`: an
    /// item's title as it is drawn).
    func typeAhead(_ typed: String, said: (String) -> String) {
        guard let open = menu, let content = openMenu else { return }
        menu?.highlight = open.highlight.typed(typed, in: content, said: said, pointer: NSEvent.mouseLocation)
    }

    /// The pointer moved over an item of the open dropdown (`over`), or left it.
    func hoverMenu(_ item: String, over: Bool) {
        guard let open = menu, let content = openMenu else { return }
        let pointer = NSEvent.mouseLocation
        let next = over ? open.highlight.hovered(item, pointer: pointer, in: content) : open.highlight.unhovered(item, pointer: pointer)
        if next != open.highlight { menu?.highlight = next }
    }

    func pick(_ id: String) {
        guard let kind = menu?.kind else { return }
        menu = nil
        perform(.pick(kind, id))
    }

    func draft(_ key: String) -> Binding<String> {
        Binding(get: { self.drafts[key] ?? "" }, set: { self.drafts[key] = $0 })
    }
}

/// Reports a view's frame in global coordinates (a dropdown opens under its button).
struct ArisAIFrameReader: ViewModifier {
    @Binding var frame: CGRect

    func body(content: Content) -> some View {
        content.background(GeometryReader { proxy in
            Color.clear
                .onAppear { frame = proxy.frame(in: .global) }
                .onChange(of: proxy.frame(in: .global)) { _, next in frame = next }
        })
    }
}

/// The dropdown's button: the choice, small warn text after it, a chevron, and a 2-pt bar along the bottom while a
/// model comes in.
struct ArisAISelect: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let face: ArisAISelectFace
    /// What VoiceOver calls it ("생각").
    let label: String
    /// 200 on the page; nil: as wide as it is given (a sheet's dropdowns), or with `minWidth`, as wide as its choice
    /// needs and never narrower than that (a settings row, whose choices can be long).
    var width: CGFloat? = ArisAISelect.pageWidth
    var minWidth: CGFloat?
    static let pageWidth: CGFloat = 200
    var height: CGFloat = 40
    var fontSize: CGFloat = 14
    var expanded = false
    let open: (CGRect) -> Void
    @State private var frame: CGRect = .zero
    @State private var hovering = false

    private func name(_ text: String) -> some View {
        Text(w.dotted(text)).font(.system(size: fontSize, weight: .medium)).foregroundStyle(palette.title).lineLimit(1).truncationMode(.tail)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button { open(frame) } label: {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    if let short = face.short {
                        // The whole label when it fits, else the short one (a longer English line never ends in "…").
                        ViewThatFits(in: .horizontal) {
                            name(face.label).fixedSize()
                            name(short)
                        }
                    } else {
                        name(face.label)
                    }
                    if let tail = face.tail {
                        Text(w.dotted(tail)).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.warn).lineLimit(1).fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ArisLineIcon("chevron.down", size: 13, stroke: 2.25).foregroundStyle(palette.ink3)
            }
            .padding(.horizontal, 12)
            .frame(width: width, height: height)
            .frame(minWidth: minWidth, maxWidth: width == nil && minWidth == nil ? .infinity : nil)
            .fixedSize(horizontal: minWidth != nil, vertical: false)
            .background(shape.fill(palette.dark ? Color.white.opacity(0.05) : .white))
            // Inset 0 1px 2px: a soft dark line just under the top edge.
            .overlay(shape.strokeBorder(LinearGradient(colors: [.black.opacity(palette.dark ? 0.3 : 0.06), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.18)), lineWidth: 1.5)
                .padding(1).allowsHitTesting(false))
            .overlay(shape.strokeBorder(hovering || expanded ? palette.fieldFocus : palette.fieldBorder, lineWidth: 1))
            .overlay(alignment: .bottom) {
                if let bar = face.bar {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.switchOff)
                            Capsule().fill(palette.title).frame(width: proxy.size.width * CGFloat(min(max(bar, 0), 100)) / 100)
                        }
                    }
                    .frame(height: 2).padding(.horizontal, 12).padding(.bottom, 4)
                }
            }
            .contentShape(shape)
            .animation(.easeInOut(duration: 0.2), value: hovering)
        }
        .buttonStyle(ArisPressScale(scale: ArisPressScale.measured))
        .disabled(!face.enabled)
        .opacity(face.enabled ? 1 : 0.5)
        .onHover { hovering = $0 && face.enabled }
        .modifier(ArisAIFrameReader(frame: $frame))
        .accessibilityLabel(w(label))
        .accessibilityValue([face.label, face.tail].compactMap { $0 }.map { w.dotted($0) }.joined(separator: ", "))
        .help(w.dotted(face.label))
    }
}

/// The ghost button with an icon before its title: 미리 듣기, 같은 회사로 맞추기.
struct ArisAIIconButton: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let title: String
    var leading: String?
    var trailing: String?
    var small = false
    var enabled = true
    let action: (CGRect) -> Void
    @State private var hovering = false
    @State private var frame: CGRect = .zero

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: small ? 10 : 12, style: .continuous)
        Button { action(frame) } label: {
            HStack(spacing: 6) {
                if let leading { ArisLineIcon(leading, size: 15) }
                Text(w(title)).lineLimit(1)
                if let trailing { ArisLineIcon(trailing, size: 11, stroke: 2.25) }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(hovering ? palette.buttonTextHover : palette.buttonText)
            .padding(.horizontal, small ? 10 : 12)
            .frame(height: small ? 26 : 30)
            .background(shape.fill(palette.buttonFill))
            .overlay(shape.strokeBorder(hovering ? palette.buttonBorderHover : palette.buttonBorder, lineWidth: 1))
            .contentShape(shape)
            .animation(.easeInOut(duration: 0.2), value: hovering)
        }
        .buttonStyle(ArisPressScale())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 && enabled }
        .fixedSize()
        .modifier(ArisAIFrameReader(frame: $frame))
    }
}

/// A download's bar (120 × 4) and its percent.
struct ArisAIProgress: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let percent: Int

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(palette.switchOff)
                Capsule().fill(palette.title).frame(width: 120 * CGFloat(min(max(percent, 0), 100)) / 100)
            }
            .frame(width: 120, height: 4)
            .animation(.linear(duration: 0.16), value: percent)
            Text("\(percent)%").font(.system(size: 12)).monospacedDigit().foregroundStyle(palette.ink3).frame(width: 32, alignment: .trailing)
        }
        .accessibilityElement()
        .accessibilityLabel(w("받는 중"))
        .accessibilityValue("\(percent)%")
    }
}

/// A field on the page or in a sheet: 36 tall, 13 pt (the window's own field look, ArisFieldStyle).
struct ArisAITextField: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsStill) private var still
    @Environment(\.arisWords) private var w
    /// The words in the empty field, as given; drawn in the page's wording.
    let hint: String
    private var placeholder: String { w(hint) }
    @Binding var text: String
    var secure = false
    var mono = false
    var width: CGFloat?
    var leading: CGFloat = 12
    /// Takes the keyboard when it appears (a field that was just opened).
    var autofocus = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    init(placeholder: String, text: Binding<String>, secure: Bool = false, mono: Bool = false, width: CGFloat? = nil, leading: CGFloat = 12,
         autofocus: Bool = false, onSubmit: @escaping () -> Void = {}) {
        hint = placeholder
        _text = text
        self.secure = secure
        self.mono = mono
        self.width = width
        self.leading = leading
        self.autofocus = autofocus
        self.onSubmit = onSubmit
    }

    var body: some View {
        Group {
            if still {
                Text(text.isEmpty ? placeholder : secure ? String(repeating: "•", count: text.count) : text)
                    .foregroundStyle(text.isEmpty ? palette.ink3 : palette.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            } else if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
        }
        .font(mono ? .system(size: 13, design: .monospaced) : .system(size: 13))
        .focused($focused)
        .onSubmit(onSubmit)
        .modifier(ArisFieldStyle(focused: focused, height: 36))
        .environment(\.arisFieldLeading, leading)
        .frame(width: width)
        .accessibilityLabel(placeholder)
        .onAppear { if autofocus, !still { focused = true } }
    }
}
