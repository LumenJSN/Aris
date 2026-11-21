//
//  ArisSetupCards.swift
//  Aris
//
//  Which permission cards the setup shows: only what the features this person uses need (ArisPermissionSetup.list),
//  drawn with the existing three cards. Talking, reading the app in front and working in other apps are always on;
//  dictation, the circle gesture and the wake word follow their switches as the setup opens. Reading what is on the
//  screen goes through Accessibility, and the circle gesture asks for Screen Recording the first time a circle is
//  drawn (ArisPermissionFeature.askedAtFirstUse), so the setup has no Screen Recording card, no Quit & Reopen for it
//  and no capture approval. Everything else (calendars, folders, an app's Automation, Full Disk Access) is asked the
//  first time a feature needs it. Pure.
//

import Foundation

enum ArisSetupCards {
    /// The features always on, whatever the switches say.
    static let always: Set<ArisPermissionFeature> = [.talk, .screenText, .appControl]

    static func chosen(dictation: Bool, circleGesture: Bool, wakeWord: Bool) -> Set<ArisPermissionFeature> {
        var features = always
        if dictation { features.formUnion([.dictation, .dictationKey]) }
        if circleGesture { features.insert(.circleGesture) }
        if wakeWord { features.insert(.wakeWord) }
        return features
    }

    /// The card that asks for `permission`, if the setup has one (Input Monitoring has none yet: jv-appbugs asks it
    /// with the key taps).
    static func card(for permission: ArisPermission) -> ArisPermissionCard? {
        switch permission {
        case .microphone, .speechRecognition: .mic
        case .accessibility: .accessibility
        case .screenRecording: .screen
        default: nil
        }
    }

    /// The cards for `chosen`, in the page's order.
    static func cards(for chosen: Set<ArisPermissionFeature>) -> [ArisPermissionCard] {
        let wanted = Set(ArisPermissionSetup.list(for: chosen, in: ArisPermissions()).compactMap { card(for: $0.permission) })
        return ArisPermissionCard.allCases.filter(wanted.contains)
    }
}
