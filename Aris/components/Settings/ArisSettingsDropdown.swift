//
//  ArisSettingsDropdown.swift
//  Aris
//
//  A menu row's control. There is one menu in the settings window, the AI 서비스 page's (ArisAISelect and its panel,
//  ArisAIServicesMenu): a field-like button 40 tall that names the choice, and a list that opens under it with the
//  arrow keys, Return, Esc and type-ahead. Every page's choices go through it (the user's item 8); nothing draws a
//  second kind of dropdown.
//

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
        model.menu = same ? nil : .init(kind: .sheet("setting"), anchor: menu.anchor, custom: menu.content, byKey: ArisAIServicesModel.openedByKey)
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
        ArisAISelect(face: ArisAISelectFace(label: options.first { $0.id == selected }?.title ?? "–"), label: title, width: nil, minWidth: ArisAISelect.pageWidth,
                     expanded: handlers.menuOpen == key) { frame in
            handlers.openMenu(ArisSettingMenu(key: key, title: title, options: options, selected: selected, anchor: frame))
        }
        .environment(\.arisWords, choice)
    }
}
