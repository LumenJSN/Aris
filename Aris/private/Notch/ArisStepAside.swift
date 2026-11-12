//
//  ArisStepAside.swift
//  Aris
//
//  A press in the notch or in a side panel that opens Aris's Settings takes what was pressed out of the window's way
//  (the second VM run: the notch, and the side panel, stayed over the Settings window they had just opened). The
//  notch closes (ArisNotchRoot, unless a card or an approval in it still waits for the user), a side panel folds unless it
//  is locked open, and the dictation model's offer waits while the Settings window is in front (ArisModelLayer).
//

import AppKit

extension Notification.Name {
    /// A press in one of Aris's panels has just opened the Settings window.
    static let arisSettingsOpenedByPress = Notification.Name("arisSettingsOpenedByPress")
}

@MainActor
enum ArisStepAside {
    /// Shows the Settings window for a press in the notch or a side panel (the page was chosen by the caller).
    static func showSettings() {
        ArisSettingsWindow.shared.show()
        NotificationCenter.default.post(name: .arisSettingsOpenedByPress, object: nil)
        ArisSidePanels.shared.stepAside()
    }

    /// A press in the notch has just opened something else to look at: System Settings' own list for a permission
    /// (the Reminders fix button), or the reader with the whole answer. The notch gets out of its way as it does for
    /// Aris's Settings (third VM run: it stayed open over the list's top, and over the reader, whose text ran through
    /// the notch's until the pointer moved).
    static func openedElsewhere() {
        NotificationCenter.default.post(name: .arisSettingsOpenedByPress, object: nil)
        ArisSidePanels.shared.stepAside()
    }
}
