//
//  ArisLiveSettingsReading.swift
//  Aris
//
//  What the live settings read from the system for their snapshot: the permissions, the terminals and screens on this
//  Mac, a shortcut's caps, a colour's hex.
//

import AppKit
import AVFoundation
import IOKit.hid
import KeyboardShortcuts
import Speech

extension ArisLiveSettings {
    static func readPermissions(diskAccess: Bool = false, folders: [String: Bool] = [:]) -> [ArisSettingsSnapshot.Permission] {
        base(diskAccess: diskAccess) + ArisSettingsSnapshot.folderPermissions(granted: diskAccess ? Dictionary(uniqueKeysWithValues: ArisSettingsSnapshot.agentFolders.map { ($0, true) }) : folders)
    }

    static func base(diskAccess: Bool) -> [ArisSettingsSnapshot.Permission] {
        [
            .init(id: "ax", title: ArisFix.Pane.accessibility.title(english: false), desc: "버튼·입력칸을 찾아 누르고 글자를 입력해요.", granted: AXIsProcessTrusted()),
            .init(id: "screen", title: ArisFix.Pane.screen.title(english: false), desc: "화면을 가리켜 말할 때 그 화면을 같이 봐요.", granted: CGPreflightScreenCaptureAccess()),
            .init(id: "mic", title: "마이크", desc: "말을 들어요.", granted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized),
            // jv-perms' model (ArisPermissionsLive) reads these two the same way; the setup asks the first with the
            // microphone, and nothing offered the second before (the dictation key and the circle key need it).
            .init(id: "speech", title: "음성 인식", desc: "들은 말을 글로 옮겨요.", granted: SFSpeechRecognizer.authorizationStatus() == .authorized),
            .init(id: "input", title: "입력 모니터링", desc: "어느 앱에서나 받아쓰기 키와 동그라미 키를 들어요.",
                  granted: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted),
            .init(id: "fda", title: "전체 디스크 접근", desc: "메시지·메일·메모를 읽기만 해요.",
                  granted: diskAccess),
        ]
    }

    /// The terminals on this Mac a teammate can open in (looked up by their bundle ids; nothing is opened).
    static func installedTerminals() -> [ArisTerminal] {
        ArisTerminal.allCases.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleId) != nil }
    }

    static func readScreens() -> [ArisSettingOption] {
        NSScreen.screens.compactMap { screen in screen.displayUUID.map { ArisSettingOption(id: $0, title: screen.localizedName) } }
    }

    static func caps(_ name: KeyboardShortcuts.Name) -> [String] {
        KeyboardShortcuts.getShortcut(for: name).map { ArisShortcutCaps.caps($0.description) } ?? []
    }

    static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}
