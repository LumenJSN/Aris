//
//  ArisLoginItem.swift
//  Aris
//
//  로그인 시 실행 through SMAppService.mainApp: off unless the user turns it on (the first-run guide's consent step or
//  settings › 일반). Aris used to switch it on silently at first launch; it never does now.
//

import ServiceManagement
import os

enum ArisLoginItem {
    private static let log = Logger(subsystem: "com.lumenjsn.aris", category: "login-item")

    /// On, or waiting for the user's approval in System Settings › 로그인 항목.
    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    /// Turns it on or off. When macOS wants the user to approve it, System Settings opens on 로그인 항목.
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        do {
            if on {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            log.error("login item \(on ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
