//
//  ArisSideDemo.swift
//  Aris
//
//  The side panels' demo mode, turned on and off by ArisPreview (`side-demo:on|off`): while it is on, 할 일, 캘린더,
//  기록 and 한 일 show ArisSideDemoSamples and read none of the real sources (Reminders, Canvas, EventKit, the history,
//  the activity log); ticking or undoing a sample changes it in memory only, and nothing real is written. In memory
//  only: off (or quitting) puts every panel back on its real source.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "preview")

@MainActor
final class ArisSideDemo: ObservableObject {
    static let shared = ArisSideDemo()

    @Published private(set) var state = ArisSideDemoSwitch()

    var isOn: Bool { state.isOn }
    var samples: ArisSideDemoSamples? { state.samples }

    func set(_ on: Bool) {
        guard state.set(on, now: .now) else { return }
        log.notice("side demo \(on ? "on" : "off", privacy: .public)")
        // The models that keep rows of their own take the samples, or go back to their real sources.
        ArisTodoModel.shared.demoChanged()
        ArisActivityModel.shared.demoChanged()
        // The 캘린더 tab's remembered events are real ones: never shown for a moment under the samples, or after them.
        ArisAgendaMemory.events = nil
    }
}
