//
//  ArisWritingStyle.swift
//  Aris (and aris-agent)
//
//  How dictation is written in the app it goes to: casual in chat apps, formal in mail, raw in IDEs and terminals (no
//  polish, no full stop, so a command stays a command), standard everywhere else. The user can change each in settings ›
//  받아쓰기. The terminals are also where aris-agent adds a trailing space and never reads or watches a field.
//  Foundation only (tested).
//

import Foundation

enum ArisWritingStyle: String, CaseIterable, Codable {
    case casual, standard, formal, raw

    var title: String {
        switch self {
        case .casual: "편하게"
        case .standard: "보통"
        case .formal: "격식"
        case .raw: "그대로"
        }
    }

    /// Raw is typed as heard (fillers out), never through a model.
    var polishes: Bool { self != .raw }
    /// Casual and raw leave a single sentence without a full stop.
    var endsWithStop: Bool { self == .standard || self == .formal }
}

enum ArisAppKind: String, CaseIterable {
    case chat, mail, code, other

    var title: String {
        switch self {
        case .chat: "채팅 앱"
        case .mail: "메일"
        case .code: "개발 도구 · 터미널"
        case .other: "그 밖의 앱"
        }
    }

    var detail: String {
        switch self {
        case .chat: "카카오톡, 메시지, Slack, Discord, Telegram…"
        case .mail: "Mail, Outlook, Spark, Superhuman…"
        case .code: "Xcode, VS Code, Cursor, 터미널, iTerm… 기본은 다듬지 않고 그대로예요."
        case .other: "메모, 브라우저, 문서 앱"
        }
    }

    var defaultStyle: ArisWritingStyle {
        switch self {
        case .chat: .casual
        case .mail: .formal
        case .code: .raw
        case .other: .standard
        }
    }

    private static let chatIds: Set<String> = [
        "com.kakao.kakaotalkmac", "com.apple.mobilesms", "com.apple.ichat", "com.tinyspeck.slackmacgap", "com.hnc.discord",
        "ru.keepcoder.telegram", "org.telegram.desktop", "net.whatsapp.whatsapp", "desktop.whatsapp", "jp.naver.line.mac",
        "com.tencent.xinwechat", "org.whispersystems.signal-desktop", "com.facebook.archon", "com.microsoft.teams",
        "com.microsoft.teams2",
    ]
    private static let mailIds: Set<String> = [
        "com.apple.mail", "com.microsoft.outlook", "com.superhuman.electron", "com.readdle.smartemail-mac",
        "com.readdle.spark", "it.bloop.airmail2", "com.mimestream.mimestream", "com.freron.mailmate",
    ]
    private static let ideIds: Set<String> = [
        "com.apple.dt.xcode", "com.microsoft.vscode", "com.microsoft.vscodeinsiders", "com.vscodium",
        "com.todesktop.230313mzl4w4u92", "dev.zed.zed", "com.exafunction.windsurf", "com.google.android.studio",
        "com.sublimetext.4", "com.sublimetext.3", "com.panic.nova", "com.barebones.bbedit",
    ]
    private static let chatNames: Set<String> = ["카카오톡", "kakaotalk", "messages", "메시지", "slack", "discord", "telegram",
                                                 "whatsapp", "line", "wechat", "signal", "messenger", "microsoft teams"]
    private static let mailNames: Set<String> = ["mail", "메일", "microsoft outlook", "outlook", "spark", "superhuman", "mimestream", "airmail"]
    private static let codeNames: Set<String> = ["xcode", "visual studio code", "code", "cursor", "zed", "windsurf", "terminal", "터미널",
                                                 "iterm2", "ghostty", "warp", "kitty", "alacritty", "wezterm", "hyper"]

    /// The app's kind by its bundle id, else by its whole name.
    static func of(bundleId: String?, name: String?) -> ArisAppKind {
        let id = bundleId?.lowercased() ?? ""
        if !id.isEmpty {
            if chatIds.contains(id) { return .chat }
            if mailIds.contains(id) { return .mail }
            if ideIds.contains(id) || id.hasPrefix("com.jetbrains.") || ArisWritingStyles.isTerminal(id) { return .code }
        }
        let name = name?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        if chatNames.contains(name) { return .chat }
        if mailNames.contains(name) { return .mail }
        if codeNames.contains(name) { return .code }
        return .other
    }
}

enum ArisWritingStyles {
    private static let terminalIds: Set<String> = [
        "com.apple.terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.warp-stable", "dev.warp.warp",
        "net.kovidgoyal.kitty", "org.alacritty", "io.alacritty", "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby",
        "com.raphaelamorim.rio",
    ]

    static func isTerminal(_ bundleId: String?) -> Bool {
        guard let id = bundleId?.lowercased(), !id.isEmpty else { return false }
        return terminalIds.contains(id)
    }

    /// The style for an app kind: the owner's pick (`choices`, kind → style raw values), else the kind's default.
    static func style(for kind: ArisAppKind, choices: [String: String]) -> ArisWritingStyle {
        choices[kind.rawValue].flatMap(ArisWritingStyle.init(rawValue:)) ?? kind.defaultStyle
    }
}
