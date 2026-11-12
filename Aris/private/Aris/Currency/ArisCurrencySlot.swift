//
//  ArisCurrencySlot.swift
//  Aris
//
//  The currency card in the answer's slot: the plain card, or the live one when the hidden preference says so
//  (`defaults write com.lumenjsn.aris arisCurrencyCard live`; anything else, or nothing, is plain). Never live on a
//  turn that saw the screen or outside text: there a card only shows. Here are the live card's ties to the app: its
//  one request (aris-agent's POST /currency), the notch's keyboard for its field (as the composer takes it), and the
//  last three currencies he used.
//

import AppKit
import SwiftUI

struct ArisCurrencySlot: View {
    let card: ArisCurrencyCard
    let untrusted: Bool

    var body: some View {
        if !untrusted, ArisCurrencyStyle.isLive(setting: UserDefaults.standard.string(forKey: ArisCurrencyStyle.key)) {
            ArisCurrencyLiveCard(model: Self.model(card), takeKeyboard: Self.takeKeyboard)
        } else {
            ArisCurrencyCardView(card: card)
        }
    }

    @MainActor private static func model(_ card: ArisCurrencyCard) -> ArisCurrencyLiveModel {
        let home = ArisCurrencyHome.code()
        return ArisCurrencyLiveModel(card: card, home: home, recent: ArisCurrencyLiveModel.storedRecent(),
                                     fetch: { await ArisAgentClient.cardValues(path: "currency", body: ["ask": $0], timeout: 25) },
                                     used: { ArisCurrencyLiveModel.remember($0, home: home) })
    }

    /// The notch's panel takes the keyboard for the amount field, through ArisPanelKeys so the panel really is key and
    /// the app he was in gets the keyboard back when the field lets go; only after his own press (never a posted click).
    @MainActor private static func takeKeyboard() -> Bool {
        guard let panel = NSApp.windows.first(where: { $0 is ArisNotchPanel && $0.isVisible && $0.frame.contains(NSEvent.mouseLocation) }),
              ArisPanelKeys.tapTakesKeyboard(in: panel) else { return false }
        ArisPanelKeys.take(panel)
        return true
    }
}

extension ArisCurrencyLiveModel {
    /// The last currencies he used that the menu doesn't always show (three at most).
    static func storedRecent() -> [String] {
        UserDefaults.standard.stringArray(forKey: ArisCurrencyStyle.recentKey) ?? []
    }

    /// A pair was shown: its codes go to the front of the last-used list. Only while the live card is on: with the plain
    /// card (the default) nothing is kept.
    static func remember(_ codes: [String], home: String) {
        guard ArisCurrencyStyle.isLive(setting: UserDefaults.standard.string(forKey: ArisCurrencyStyle.key)) else { return }
        let next = ArisCurrencyLive.remembering(codes, in: storedRecent(), home: home)
        if next != storedRecent() { UserDefaults.standard.set(next, forKey: ArisCurrencyStyle.recentKey) }
    }
}
