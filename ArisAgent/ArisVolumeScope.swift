//
//  ArisVolumeScope.swift
//  aris-agent
//
//  "이 영상 볼륨 30으로 해 줘" (the eleventh VM run, K3): the brain ran `aris-tools volume 30`, which sets the Mac's whole
//  volume, and said only "볼륨을 30으로 낮췄어요". Aris has no way to set one video's, tab's or app's own volume, so when
//  the owner named such a player and the turn changed the Mac's volume, Aris's own line says which volume moved, unless
//  the answer already says so. The model's text is never changed. Pure.
//

import Foundation

enum ArisVolumeScope {
    /// The request is about sound.
    private static let soundWords = #"(?i)(볼륨|소리|음량|\bvolume\b|\bsound\b|\blouder\b|\bquieter\b|\bmute\b|\bturn\b.*\b(?:up|down)\b)"#
    /// It names one player rather than the Mac: a video, a tab, a song, a site, an app.
    private static let playerWords = #"(?i)(영상|동영상|비디오|유튜브|넷플릭스|탭|이 노래|이 곡|플레이어|이 앱|이 사이트|브라우저|\bvideos?\b|\byoutube\b|\bnetflix\b|"#
        + #"\btabs?\b|\bthis song\b|\bplayer\b|\bthis app\b|\bmovie\b|\bbrowser\b|\bspotify\b)"#
    /// The answer already says it was the Mac's whole volume.
    private static let saysWhole = #"(?i)(맥 전체|전체 볼륨|시스템 볼륨|mac'?s (?:overall |whole |system )?volume|system volume|overall volume)"#

    static func asksPlayerVolume(_ request: String) -> Bool {
        matches(soundWords, request) && matches(playerWords, request)
    }

    /// Whether one of the turn's commands set the Mac's volume (`aris-tools volume …`).
    static func setsMacVolume(_ commands: [String], tools: String) -> Bool {
        commands.contains { command in
            guard let parts = ArisCommandPolicy.segments(ArisCommandPolicy.unwrap(command)) else { return false }
            return parts.contains { part in
                guard let words = ArisCommandPolicy.words(part), words.count >= 2, let first = words.first else { return false }
                return (first as NSString).lastPathComponent == (tools as NSString).lastPathComponent && words[1] == "volume"
            }
        }
    }

    static func line(english: Bool) -> String {
        english ? "To be clear: Aris can't set one video's or app's own volume, so what changed is the Mac's overall volume."
            : "참고로 영상이나 앱 하나의 볼륨은 따로 바꿀 수 없어서, 바뀐 건 맥 전체 볼륨이에요."
    }

    /// The line to add after `answer`, or nil.
    static func note(_ answer: String, request: String, commands: [String], tools: String, english: Bool) -> String? {
        guard asksPlayerVolume(request), setsMacVolume(commands, tools: tools), !matches(saysWhole, answer) else { return nil }
        return line(english: english)
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
}
