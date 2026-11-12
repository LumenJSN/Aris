//
//  ArisSettingsModal.swift
//  Aris
//
//  The settings window's sheets and toast: 정보 › 데이터 and API 키 (mockup audit-4-settings-extra.html option C), and
//  언어 추가, the restart question and 팀원 빼기 (settings-redesign.html). The sheet: 460 wide, r20, the backdrop at
//  .38 / .78, in from scale .96 and 10 pt down, 300 ms ease-out. Destructive: red-600 on red-50 light, red-400 on
//  red-500/10 dark, border rgba(239,68,68,.2/.3). Primary #0a0a0a / #f3f6fa. Input r12, focus ring 3 pt
//  rgba(18,111,246,.25). The toast: a black chip bottom right, 14/500, r8.
//

import AppKit
import SwiftUI

/// The sheet on screen and the last toast, shared by the pages that open them and the root that draws them.
@MainActor
final class ArisSettingsOverlay: ObservableObject {
    static let shared = ArisSettingsOverlay()

    enum Sheet: String, Identifiable {
        case export, diagnostics, wipe, uninstall, languages, restart, removeMate, memoryImport
        var id: Self { self }
    }

    /// Opening a sheet remembers what had the keyboard, and closing it hands the keyboard back (item 16).
    @Published var sheet: Sheet? {
        didSet {
            if oldValue == nil, sheet != nil { opener = NSApp.keyWindow?.firstResponder }
            if oldValue != nil, sheet == nil, let opener, let window = NSApp.keyWindow {
                self.opener = nil
                window.makeFirstResponder(opener)
            }
        }
    }
    private weak var opener: NSResponder?
    /// The teammate 빼기 asks about, and what removing it does.
    var removal: (name: String, remove: () -> Void)?
    @Published private(set) var toast: String?
    /// Whether the toast says it was done, it wasn't, or just something to know (item 12).
    @Published private(set) var tone = ArisToastTone.ok
    private var toastTimer: Task<Void, Never>?

    /// `tone`: `.bad` for something that did not happen (a key that can't be used, a save that failed).
    func show(_ message: String, tone: ArisToastTone = .ok) {
        toast = message
        self.tone = tone
        startTimer()
    }

    /// The pointer rests on the toast: it stays until the pointer leaves, then for its time again.
    func hold(_ held: Bool) {
        guard toast != nil else { return }
        if held { toastTimer?.cancel() } else { startTimer() }
    }

    private func startTimer() {
        let seconds = ArisToastTone.seconds(for: toast ?? "")
        toastTimer?.cancel()
        toastTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}

// MARK: - Host

/// Draws the sheet over the whole settings window, and the toast in its bottom-right corner.
struct ArisSettingsModalHost<Sheet: View>: View {
    @Environment(\.arisPalette) private var palette
    @ObservedObject var overlay: ArisSettingsOverlay
    @ViewBuilder let content: (ArisSettingsOverlay.Sheet) -> Sheet

    var body: some View {
        ZStack {
            if let sheet = overlay.sheet {
                palette.backdrop.ignoresSafeArea()
                    .onTapGesture { overlay.sheet = nil }
                    .transition(.opacity)
                content(sheet)
                    .frame(width: 460)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.modal))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.modalBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    // One shadow for the whole sheet (ungrouped, every control in it casts its own).
                    .compositingGroup()
                    .shadow(color: .black.opacity(palette.dark ? 0.82 : 0.25), radius: palette.dark ? 32 : 25, y: palette.dark ? 24 : 25)
                    .transition(.scale(scale: 0.96).combined(with: .offset(y: 10)).combined(with: .opacity))
                    .onExitCommand { overlay.sheet = nil }
                    // Esc closes it wherever the keyboard is (and Return presses its main button: ArisPillButton).
                    .background(Button("") { overlay.sheet = nil }.keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true))
            }
            if let toast = overlay.toast {
                ArisToast(text: toast, tone: overlay.tone)
                    .onHover { overlay.hold($0) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(24)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        // In over 300 ms, out over 200: the way out is the system answering, and is quicker (emil-design-eng:
        // exits faster than entrances).
        .animation(.easeOut(duration: overlay.sheet == nil ? 0.2 : 0.3), value: overlay.sheet)
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.18), value: overlay.toast)
    }
}

struct ArisToast: View {
    @Environment(\.arisWords) private var w
    let text: String
    var tone = ArisToastTone.ok

    /// The status icon colours: green-400, red-400, gray-300.
    private var mark: Color {
        switch tone {
        case .ok: Color(arisHex: 0x4ade80)
        case .bad: Color(arisHex: 0xf87171)
        case .info: Color(arisHex: 0xd1d5dc)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tone.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(mark)
            Text(w(text)).font(.system(size: 14, weight: .medium)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black))
        .shadow(color: .black.opacity(0.2), radius: 7, y: 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sheet parts

/// Title, ×, the line under it, and the body.
struct ArisSheetFrame<Body: View, Footer: View>: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let title: String
    var subtitle: String?
    var onClose: (() -> Void)?
    @ViewBuilder let content: () -> Body
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(w(title)).font(.system(size: 16, weight: .semibold)).foregroundStyle(palette.title)
                Spacer(minLength: 0)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.faint)
                            .frame(width: 28, height: 28).contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain).help(w("닫기")).accessibilityLabel(w("닫기"))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            Rectangle().fill(palette.line).frame(height: 1)
            // Every sheet's list is short (six rows at most): it sizes to fit, no scrolling.
            VStack(alignment: .leading, spacing: 0) {
                if let subtitle {
                    Text(w(subtitle)).font(.system(size: 13)).foregroundStyle(palette.desc).lineSpacing(2.5).fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
            HStack(spacing: 8) { Spacer(minLength: 0); footer() }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 18)
        }
    }
}

/// A sheet's button: the window's button (ArisSettingsButton), primary unless told otherwise.
struct ArisPillButton: View {
    let title: String
    var kind = ArisSettingButtonKind.primary
    var small = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        // A sheet's main button answers Return wherever the keyboard is; a red one never does (it is pressed on purpose).
        if kind == .primary {
            ArisSettingsButton(title: title, kind: kind, small: small, enabled: enabled, action: action).keyboardShortcut(.defaultAction)
        } else {
            ArisSettingsButton(title: title, kind: kind, small: small, enabled: enabled, action: action)
        }
    }
}

/// "확인하려면 <word>라고 써 주세요" and its field (the red button stays off until it matches: ArisTypedConfirm).
/// On an English Mac the line is "Type <word> to confirm" with the English word, which that keyboard can type.
struct ArisTypeToConfirm: View {
    @Environment(\.arisPalette) private var palette
    let word: String
    @Binding var typed: String
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    private var prompt: AttributedString {
        let parts = ArisTypedConfirm.prompt(word, english: ArisUILanguage.english)
        var bold = AttributedString(parts.word)
        bold.font = .system(size: 12, weight: .semibold)
        bold.foregroundColor = palette.title
        return AttributedString(parts.before) + bold + AttributedString(parts.after)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt).font(.system(size: 12)).foregroundStyle(palette.desc)
            TextField("", text: $typed)
                .focused($focused).onSubmit(onSubmit)
                .modifier(ArisFieldStyle(focused: focused))
                .accessibilityLabel(ArisUIWords.text("확인 글자", "Confirmation word"))
        }
        .padding(.top, 12)
    }
}

/// One row of a sheet's list: a box (or a status), the title, a second line and a size.
struct ArisSheetListRow<Lead: View>: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @ViewBuilder let lead: () -> Lead
    let title: String
    var sub: String?
    var path: String?
    var size: String?
    var dimmed = false
    var tag: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            lead().frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(w(title)).font(.system(size: 13)).foregroundStyle(palette.title)
                    if let tag { ArisChip(text: tag) }
                }
                if let sub { Text(w(sub)).font(.system(size: 11.5)).foregroundStyle(palette.faint) }
                if let path { Text(w(path)).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.faint).lineLimit(1).truncationMode(.middle) }
            }
            Spacer(minLength: 0)
            if let size { Text(w(size)).font(.system(size: 12)).monospacedDigit().foregroundStyle(palette.faint) }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .opacity(dimmed ? 0.55 : 1)
    }
}

/// A checkbox in the list's colours.
struct ArisCheckBox: View {
    @Binding var isOn: Bool
    var enabled = true

    var body: some View {
        Toggle("", isOn: $isOn).toggleStyle(.checkbox).labelsHidden().disabled(!enabled).tint(Color(arisHex: 0x126ff6))
    }
}

/// The green check that lands (16 pt, scale .4 → 1, 460 ms (.34,1.56,.64,1)).
struct ArisLandingCheck: View {
    @State private var landed = false

    var body: some View {
        Image(systemName: "checkmark").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 16, height: 16).background(Circle().fill(Color(red: 0x30 / 255, green: 0xd1 / 255, blue: 0x58 / 255)))
            .scaleEffect(landed ? 1 : 0.4).opacity(landed ? 1 : 0)
            .onAppear { withAnimation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.46)) { landed = true } }
    }
}
