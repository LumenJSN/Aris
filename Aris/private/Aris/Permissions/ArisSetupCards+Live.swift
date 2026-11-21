//
//  ArisSetupCards+Live.swift
//  Aris
//
//  The setup's cards for the switches as they are now: dictation, the circle gesture and the wake word are read here
//  (only read: the first-run guide never touches them).
//

import Defaults

extension ArisSetupCards {
    @MainActor
    static func live() -> [ArisPermissionCard] {
        cards(for: chosen(dictation: Defaults[.arisDictationOn], circleGesture: Defaults[.arisCircleGesture], wakeWord: Defaults[.arisWakeWord]))
    }
}
