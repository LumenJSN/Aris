//
//  ArisPermissionRoute.swift
//  Aris (jv-prompts)
//
//  POST /aris/permission {feature} on the hook server (the shared token, like /aris/todos): aris-tools asks it just
//  before its first Apple Event to an app (ArisAutomationGate), in a turn the user is in front of. The app's permission
//  layer answers (ArisPermissionCenter.require): the feature's one line of why the first time, then macOS asks by
//  itself at the event; a refusal is told once with the pane's button, and after that the feature does without. Only
//  the features that drive an app by Apple Events are taken. Never raises a dialog itself.
//  The same file says when the calendar and to-do routes may ask for Calendars or Reminders: only for a request
//  that says it comes from a turn the user is in front of (`ask`), and only while the permission is missing. Such a
//  request then waits for macOS's answer (ArisPermissionWait) and is done under the grant it came with.
//

import Foundation

enum ArisPermissionRoute {
    static let path = "/aris/permission"

    /// The feature asked about; nil for anything that isn't one that drives an app by Apple Events.
    static func feature(_ object: [String: Any]) -> ArisPermissionFeature? {
        guard let name = object["feature"] as? String, let feature = ArisPermissionFeature(rawValue: name),
              !feature.automationTargets.isEmpty else { return nil }
        return feature
    }

    /// Whether the feature's line is still to be said: some app it drives was never asked about from here. Once it
    /// was, the route says nothing more (macOS's own answer decides from then on), so a first event that never went
    /// out can't turn into an "it is off" card for a dialog that never came.
    static func saysLine(_ feature: ArisPermissionFeature, in model: ArisPermissions) -> Bool {
        model.keys(for: feature).contains { model.record($0).askedAt == nil }
    }

    static func reply(proceed: Bool) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["proceed": proceed])) ?? Data("{}".utf8)
    }

    /// Whether a calendar or to-do request should have the permission layer ask for its permission now: only one from
    /// a turn the user is in front of (`"ask": true`), and only when the permission isn't there.
    static func asks(_ object: [String: Any], granted: Bool) -> Bool {
        !granted && object["ask"] as? Bool == true
    }
}
