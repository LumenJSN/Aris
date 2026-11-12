//
//  ArisSettingsPanes.swift
//  aris-agent
//
//  System Settings in three tiers (the owner, 2026-11-07: "위험한 것도 아닌데"). A pane known to be safe (Appearance, Wi-Fi,
//  Bluetooth, Network, Displays, Sound, Battery, Control Center, Desktop & Dock, Notifications, Focus, Wallpaper,
//  Keyboard, Trackpad, Mouse, General › About, Storage, Date & Time) works like any app: the user's yes for System Settings,
//  then actions run. A protected pane (Privacy & Security and all of its panes, Users & Groups, passwords, profiles and
//  device management) is never acted in. Anything not told for sure (another pane, a sheet or panel, rows that can't be
//  read) shows the user a card every time, and their yes there is never kept. A safe pane is only ever told positively: by
//  the selected sidebar row's pane id or name. Desktop and Codex's own computer use both follow it. Pure.
//

import Foundation

enum ArisSettingsPane: Equatable {
    case safe
    case protected
    case unknown

    // MARK: - Protected

    /// Protected panes by their extension or preference id (lowercased fragments, also in a settings deep link).
    static let protectedIds = [
        "com.apple.settings.privacysecurity", "privacysecurity.extension", "com.apple.preference.security", "com.apple.settings.security",
        "com.apple.users-groups-settings", "com.apple.preferences.users", "users-groups", "com.apple.touch-id-settings", "touch-id-settings",
        "com.apple.passwords-settings", "passwords-settings", "com.apple.settings.passwords", "com.apple.preferences.password",
        "com.apple.profiles-settings", "profiles-settings", "com.apple.preferences.configurationprofiles", "com.apple.preference.profiles",
        "com.apple.loginitems-settings", "loginitems-settings", "com.apple.settings.loginitems", "filevault",
    ]

    /// Protected panes by name (exact, any case), English and Korean: as a selected sidebar row, any of these.
    static let protectedRows: Set<String> = [
        "privacy & security", "security & privacy", "개인정보 보호 및 보안", "보안 및 개인 정보 보호",
        "users & groups", "사용자 및 그룹", "passwords", "암호", "touch id & password", "touch id 및 암호", "login password", "로그인 암호",
        "profiles", "프로파일", "device management", "기기 관리",
    ]

    /// Privacy & Security's own panes and the other protected ones by the window's title: only names no safe or other
    /// pane shares (Accessibility, Bluetooth and Focus have panes of their own: told by the selected row instead).
    static let protectedTitles: Set<String> = protectedRows.union([
        "camera", "카메라", "microphone", "마이크", "location services", "위치 서비스", "files & folders", "파일 및 폴더",
        "full disk access", "전체 디스크 접근 권한", "screen recording", "screen & system audio recording", "화면 기록", "화면 및 시스템 오디오 녹음",
        "device control and data access", "기기 제어 및 데이터 접근", "automation", "자동화", "input monitoring", "입력 모니터링", "app management", "앱 관리", "developer tools", "개발자 도구",
        "login items", "login items & extensions", "로그인 항목", "로그인 항목 및 확장 프로그램", "allow in the background", "백그라운드에서 허용",
        "filevault", "contacts", "연락처", "calendars", "캘린더", "reminders", "미리 알림", "photos", "사진", "speech recognition", "음성 인식",
        "media & apple music", "미디어 및 apple music", "homekit", "remote desktop", "원격 데스크탑", "analytics & improvements", "분석 및 향상",
        "apple advertising", "apple 광고", "local network", "로컬 네트워크", "passkeys access for web browsers", "lockdown mode", "차단 모드",
    ])

    // MARK: - Safe

    /// Safe panes by their extension or preference id (lowercased fragments).
    static let safeIds = [
        "com.apple.appearance-settings", "com.apple.preference.general", "com.apple.wifi-settings", "com.apple.bluetoothsettings",
        "com.apple.preferences.bluetooth", "com.apple.network-settings", "com.apple.preference.network", "com.apple.displays-settings",
        "com.apple.preference.displays", "com.apple.sound-settings", "com.apple.preference.sound", "com.apple.battery-settings",
        "com.apple.preference.battery", "com.apple.controlcenter-settings", "com.apple.desktop-settings", "com.apple.preference.dock",
        "com.apple.notifications-settings", "com.apple.preference.notifications", "com.apple.focus-settings", "com.apple.wallpaper-settings",
        "com.apple.keyboard-settings", "com.apple.preference.keyboard", "com.apple.trackpad-settings", "com.apple.preference.trackpad",
        "com.apple.mouse-settings", "com.apple.preference.mouse",
    ]

    /// Safe panes by the selected sidebar row's name (exact, any case).
    static let safeRows: Set<String> = [
        "appearance", "모양", "wi-fi", "bluetooth", "network", "네트워크", "displays", "디스플레이", "sound", "사운드", "battery", "배터리",
        "control center", "제어 센터", "desktop & dock", "데스크탑 및 dock", "notifications", "알림", "focus", "집중 모드", "wallpaper", "배경화면",
        "keyboard", "키보드", "trackpad", "트랙패드", "mouse", "마우스",
    ]

    /// General's safe panes, by the window's title while General is the selected row.
    static let generalRows: Set<String> = ["general", "일반"]
    static let safeGeneralTitles: Set<String> = ["about", "정보", "storage", "저장 공간", "date & time", "날짜 및 시간"]

    private static func name(_ text: String) -> String { ArisRiskPolicy.folded(text).trimmingCharacters(in: .whitespaces) }

    /// The tier of the pane a look at System Settings shows.
    static func of(_ look: ArisDesktopObservation) -> ArisSettingsPane {
        let rows = look.elements.filter { $0.selected && !["checkbox", "switch", "radioButton"].contains($0.role) }
        let title = name(look.title)
        // Protected by any sign: a selected row's id or name, the window's title.
        if protectedTitles.contains(title) { return .protected }
        for row in rows {
            if let id = row.identifier.map(name), protectedIds.contains(where: id.contains) { return .protected }
            if protectedRows.contains(name(row.label)) || protectedRows.contains(name(rowName(row, in: look))) { return .protected }
        }
        // A sheet or panel over the pane, or a look through a parent window: not told for sure.
        if look.isDialog || look.note != nil { return .unknown }
        // Safe only positively, by the one selected row of the sidebar (inside it: an outline or the element named
        // Sidebar), named by its own label or the text inside it.
        let sidebars = look.elements.filter {
            ($0.axRole == "AXOutline" || ArisDesktopPrivacy.sidebarNames.contains($0.label)) && $0.bounds.width > 0 && $0.bounds.height > 0
        }.map(\.bounds)
        let inSidebar = rows.filter { row in sidebars.contains { $0.insetBy(dx: -1, dy: -1).contains(row.bounds) } }
        let kinds = inSidebar.compactMap { row -> ArisSettingsPane? in
            if let id = row.identifier.map(name), safeIds.contains(where: id.contains) { return .safe }
            let label = name(rowName(row, in: look))
            if safeRows.contains(label) { return .safe }
            if generalRows.contains(label) { return safeGeneralTitles.contains(title) ? .safe : .unknown }
            return nil
        }
        // One answer from the selected row (a row and its cell are both selected, and say the same).
        return Set(kinds) == [.safe] ? .safe : .unknown
    }

    /// A row's name: its own label, else (a generic row or cell) the first text inside it.
    private static func rowName(_ row: ArisDesktopElement, in look: ArisDesktopObservation) -> String {
        let generic: Set<String> = ["", "outline row", "row", "cell", "윤곽체 행", "행", "셀"]
        guard generic.contains(name(row.label)) else { return row.label }
        return look.elements.first { $0.axRole == "AXStaticText" && row.bounds.insetBy(dx: -1, dy: -1).contains($0.bounds) && !$0.label.isEmpty }?.label ?? row.label
    }

    /// A pane id or a protected pane's name (exact): a row, a menu item or a control that would open it.
    static func namesProtected(_ text: String) -> Bool {
        let folded = name(text)
        return protectedTitles.contains(folded) || protectedIds.contains(where: folded.contains)
    }

    /// A settings deep link (`x-apple.systempreferences:…`) that opens a protected pane.
    static func isProtectedLink(_ text: String) -> Bool {
        let folded = name(text)
        return folded.hasPrefix("x-apple.systempreferences:") && protectedIds.contains(where: folded.contains)
    }

    /// Words of a look-and-click target, a computer-use step or a menu path that name a protected pane (a card, not a
    /// refusal, when the pane they act in is told otherwise).
    static func mentionsProtected(_ text: String) -> Bool {
        let folded = name(text)
        return protectedIds.contains(where: folded.contains) || protectedTitles.contains { $0.count > 4 && folded.contains($0) }
    }
}
