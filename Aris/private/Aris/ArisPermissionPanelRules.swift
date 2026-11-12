//
//  ArisPermissionPanelRules.swift
//  Aris
//
//  When the drag panel beside System Settings shows (ArisPermissionGuide). Not for a permission already on (fresh
//  install F8: nothing is asked then), and not over macOS's own sheets: System Settings' password sheet, or the
//  system's password window, had its Cancel under the panel (F9), so while one of them is where the panel sits the
//  panel steps aside and comes back when it is gone. Pure, so the tests run it; frames are in one coordinate space.
//

import CoreGraphics
import Foundation

enum ArisPermissionPanelRules {
    /// A window on screen, as the window list describes it.
    struct Window: Equatable {
        /// The owning process's name.
        let owner: String
        /// It belongs to System Settings.
        let settings: Bool
        let layer: Int
        let frame: CGRect
    }

    /// The processes that put up macOS's password and permission windows.
    static let promptOwners: Set<String> = ["SecurityAgent", "coreautha", "LocalAuthenticationRemoteService", "universalAccessAuthWarn",
                                            "UserNotificationCenter", "CoreServicesUIAgent"]

    /// The panel shows only for a permission that isn't on yet.
    static func showsPanel(granted: Bool) -> Bool { !granted }

    /// Whether the panel must step aside: a sheet of System Settings (any of its windows but its main one, the
    /// largest) or one of macOS's own prompt windows overlaps where the panel sits.
    static func yields(panel: CGRect, windows: [Window]) -> Bool {
        let ofSettings = windows.filter(\.settings)
        let main = ofSettings.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        let sheets = ofSettings.filter { $0 != main }
        let prompts = windows.filter { !$0.settings && promptOwners.contains($0.owner) }
        return (sheets + prompts).contains { isWindow($0.frame) && $0.frame.intersects(panel) }
    }

    /// Big enough to be a sheet or a dialog (System Settings also keeps slivers of helper windows on screen).
    private static func isWindow(_ frame: CGRect) -> Bool { frame.width >= 120 && frame.height >= 60 }
}
