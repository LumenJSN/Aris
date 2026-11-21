//
//  ArisAppsIntents.swift
//  Shared/Core/Apps
//
//  An app's App Intents, read from the metadata Xcode writes into its bundle (Contents/Resources/Metadata.appintents/
//  extract.actionsdata, JSON): each action's identifier, title, description, parameters and whether it opens the app.
//  macOS gives no public way for another app to run an App Intent directly; Shortcuts can, so an intent is listed as
//  a command whose channel is a Shortcut the owner has that uses it (`shortcuts run`), and is otherwise shown as what
//  the app can do with the next channel doing it. Pure.
//

import Foundation

extension ArisApps {
    enum Intents {
        struct Action: Codable, Equatable, Sendable {
            var id: String
            var title: String
            var description: String
            var parameters: [String]
            var opensApp: Bool
            /// Its summary line ("Add ${file} to ${note}"), when it has one.
            var summary: String?
        }

        /// The actions in an extract.actionsdata file, discoverable ones only, sorted by id.
        static func parse(_ data: Data) -> [Action] {
            guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let actions = root["actions"] as? [String: Any] else { return [] }
            return actions.compactMap { id, value -> Action? in
                guard let action = value as? [String: Any] else { return nil }
                if action["isDiscoverable"] as? Bool == false { return nil }
                let title = ((action["title"] as? [String: Any])?["key"] as? String) ?? id
                let description = (((action["descriptionMetadata"] as? [String: Any])?["descriptionText"] as? [String: Any])?["key"] as? String) ?? ""
                let parameters = (action["parameters"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                let summary = ((((action["actionConfiguration"] as? [String: Any])?["actionSummary"] as? [String: Any])?["wrapper"] as? [String: Any])?["summaryString"]
                               as? [String: Any])?["formatString"] as? String
                return Action(id: id, title: title, description: description, parameters: parameters,
                              opensApp: action["openAppWhenRun"] as? Bool ?? false, summary: summary)
            }.sorted { $0.id < $1.id }
        }
    }
}
