//
//  ArisSettingsDropdown.swift
//  Aris
//
//  A menu row's control. There is one menu in the settings window (ArisAIServicesMenu's panel, to the measured
//  dropdown: ArisMenuLook): a settings row opens it from the measured settings select (ArisSettingSelect: the choice
//  at 12/500 and up-down chevrons, 30 tall), the AI 서비스 page from its field-like select (ArisAISelect, 40 tall).
//  The list opens under its button with the arrow keys, Return, Esc and type-ahead. Every page's choices go through
//  it (the user's item 8); nothing draws a second kind of dropdown.
//

import AppKit
import Combine
import SwiftUI

/// A menu row's choice, as the page hands it to the window's menu.
struct ArisSettingMenu: Equatable {
    let key: ArisSettingKey
    let title: String
    let options: [ArisSettingOption]
    let selected: String
    /// The button, in global coordinates.
    let anchor: CGRect

    var content: ArisAIMenu { .choices(options, selected: selected) }
}

/// The settings pages' open menu: the AI 서비스 page's own panel shows it, and the pick comes back with the setting it
/// was for.
@MainActor
final class ArisSettingMenus: ObservableObject {
    let model = ArisAIServicesModel()
    @Published private(set) var open: ArisSettingMenu?
    /// What a pick does (the window writes the setting).
    var choose: (ArisSettingMenu, String) -> Void = { _, _ in }
    private var watching: AnyCancellable?

    init() {
        // The panel closing itself (a click elsewhere, Esc) is a change here too: the button stops looking open.
        watching = model.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        model.perform = { [weak self] action in
            guard let self, case .pick(_, let id) = action, let menu = self.open else { return }
            self.open = nil
            self.choose(menu, id)
        }
    }

    /// The setting whose menu is on screen.
    var openKey: ArisSettingKey? { model.menu == nil ? nil : open?.key }

    /// Opens `menu` under its button, or closes it when it is the one open.
    func toggle(_ menu: ArisSettingMenu) {
        let same = openKey == menu.key
        open = same ? nil : menu
        model.menu = same ? nil : .init(kind: .sheet("setting"), anchor: menu.anchor, custom: menu.content)
    }

    func close() {
        open = nil
        model.menu = nil
    }
}

/// Draws the settings pages' open menu over the whole window.
struct ArisSettingMenuHost: View {
    @Environment(\.arisWords) private var w
    @ObservedObject var menus: ArisSettingMenus

    var body: some View {
        // A menu of the user's own names (the Reminders lists) is drawn as they are written.
        ArisAIMenuHost(model: menus.model)
            .environment(\.arisWords, menus.open.map { ArisSettingsWording.namesUserWords($0.key) } == true ? w.verbatim : w)
    }
}

/// The button that names the current choice and opens the menu.
struct ArisMenuButton: View {
    @Environment(\.arisSettingsHandlers) private var handlers
    @Environment(\.arisWords) private var w
    let key: ArisSettingKey
    let title: String
    let options: [ArisSettingOption]
    let selected: String

    var body: some View {
        // A choice that is the user's own name (a Reminders list) is shown as it is written.
        let choice = ArisSettingsWording.namesUserWords(key) ? w.verbatim : w
        ArisSettingSelect(choice: options.first { $0.id == selected }?.title ?? "–", label: title) { frame in
            handlers.openMenu(ArisSettingMenu(key: key, title: title, options: options, selected: selected, anchor: frame))
        }
        .environment(\.arisWords, choice)
    }
}

/// A settings row's select, the measured settings select button (ArisMenuLook): the choice at 12/500 and the up-down
/// chevrons after it, on a top-to-bottom fill with a 1-pt line, r8, 30 tall; under the pointer the text and the line
/// darken. It doesn't press in and looks the same while its menu is open, as the measured one.
struct ArisSettingSelect: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    /// What it shows, as given; drawn in the wording around it.
    let choice: String
    /// What VoiceOver calls it.
    let label: String
    var enabled = true
    let open: (CGRect) -> Void
    @State private var frame: CGRect = .zero
    @State private var hovering = false

    var body: some View {
        let dark = palette.dark, shape = RoundedRectangle(cornerRadius: ArisMenuLook.selectRadius, style: .continuous)
        let text = (hovering ? ArisMenuLook.selectTextHover : ArisMenuLook.selectText).color(dark)
        let fill = LinearGradient(colors: [ArisMenuLook.selectFillTop.color(dark), ArisMenuLook.selectFillBottom.color(dark)], startPoint: .top, endPoint: .bottom)
        let shown = w.dotted(choice)
        let room = ArisMenuLook.selectMaxWidth - 2 * ArisMenuLook.selectPaddingH - ArisMenuLook.selectGap - ArisMenuLook.selectIcon
        let natural = ceil((shown as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: ArisMenuLook.selectFont, weight: .medium)]).width) + 1
        Button { open(frame) } label: {
            HStack(spacing: ArisMenuLook.selectGap) {
                Text(shown).font(.system(size: ArisMenuLook.selectFont, weight: .medium)).foregroundStyle(text)
                    .lineLimit(1).truncationMode(.tail).frame(width: min(natural, room), alignment: .leading)
                // ChevronsUpDown, 14 square.
                ArisLineIcon("chevron.up.chevron.down", size: 11, stroke: 2.25)
                    .foregroundStyle(ArisMenuLook.selectChevron.color(dark))
                    .frame(width: ArisMenuLook.selectIcon, height: ArisMenuLook.selectIcon)
            }
            .padding(.horizontal, ArisMenuLook.selectPaddingH)
            .frame(height: ArisMenuLook.selectHeight)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder((hovering ? ArisMenuLook.selectBorderHover : ArisMenuLook.selectBorder).color(dark), lineWidth: 1))
            .contentShape(shape)
            .animation(.easeInOut(duration: 0.2), value: hovering)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 && enabled }
        .fixedSize()
        .modifier(ArisAIFrameReader(frame: $frame))
        .accessibilityLabel(w(label))
        .accessibilityValue(shown)
        .help(shown)
    }
}
