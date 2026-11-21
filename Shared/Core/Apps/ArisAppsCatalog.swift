//
//  ArisAppsCatalog.swift
//  Shared/Core/Apps
//
//  What people call apps, as data: one row per app with its bundle ids, its English name, the Korean names and
//  nicknames people say (카톡, 크롬, 파포, 디코…) and, for a service people also use in the browser, its web address.
//  This table is not a list of supported apps: every installed app is found by its own names (app.find reads them
//  from the bundles); the table only adds the names an app's bundle doesn't carry. To add an app, add a row. Rows
//  can also come from a JSON file of the same shape (`Row` is Codable). Pure.
//

import Foundation

extension ArisApps {
    enum Catalog {
        struct Row: Codable, Equatable, Sendable {
            /// Bundle ids this row stands for, the usual one first (old and new Teams, the App Store and direct Slack…).
            var bundles: [String]
            /// The app's English name as the Mac shows it.
            var name: String
            /// Korean names and nicknames, and English nicknames, as people say them.
            var says: [String]
            /// The service's web address, used when no native app for it is installed ("유튜브 열어").
            var web: String? = nil
        }

        private static func row(_ bundles: [String], _ name: String, _ says: [String], web: String? = nil) -> Row {
            Row(bundles: bundles, name: name, says: says, web: web)
        }

        static let rows: [Row] = [
            // Chat
            row(["com.kakao.KakaoTalkMac"], "KakaoTalk", ["카카오톡", "카톡", "까톡", "카카오", "kakao", "katalk"]),
            row(["com.apple.MobileSMS"], "Messages", ["메시지", "메세지", "문자", "아이메시지", "imessage", "sms"]),
            row(["com.tinyspeck.slackmacgap"], "Slack", ["슬랙", "스랙"], web: "https://app.slack.com/client"),
            row(["com.hnc.Discord"], "Discord", ["디스코드", "디코", "디스코"], web: "https://discord.com/app"),
            row(["ru.keepcoder.Telegram", "org.telegram.desktop"], "Telegram", ["텔레그램", "텔레"], web: "https://web.telegram.org"),
            row(["net.whatsapp.WhatsApp"], "WhatsApp", ["왓츠앱", "왓샵"], web: "https://web.whatsapp.com"),
            row(["jp.naver.line.mac"], "LINE", ["라인"]),
            row(["com.microsoft.teams2", "com.microsoft.teams"], "Microsoft Teams", ["팀즈", "팀스", "teams", "ms teams"], web: "https://teams.microsoft.com"),
            row(["us.zoom.xos"], "zoom.us", ["줌", "zoom", "줌 미팅"]),
            row(["com.apple.FaceTime"], "FaceTime", ["페이스타임", "페타"]),
            // Browsers
            row(["com.google.Chrome"], "Google Chrome", ["크롬", "구글 크롬", "크롬 브라우저", "chrome"]),
            row(["com.apple.Safari"], "Safari", ["사파리"]),
            row(["org.mozilla.firefox"], "Firefox", ["파이어폭스", "불여우"]),
            row(["company.thebrowser.Browser"], "Arc", ["아크", "아크 브라우저"]),
            row(["com.microsoft.edgemac"], "Microsoft Edge", ["엣지", "에지", "edge"]),
            row(["com.naver.Whale"], "Naver Whale", ["웨일", "네이버 웨일", "whale"]),
            // Work
            row(["notion.id"], "Notion", ["노션"], web: "https://www.notion.so"),
            row(["com.figma.Desktop"], "Figma", ["피그마"], web: "https://www.figma.com/files"),
            row(["com.microsoft.Excel"], "Microsoft Excel", ["엑셀", "excel"], web: "https://www.office.com/launch/excel"),
            row(["com.microsoft.Word"], "Microsoft Word", ["워드", "word", "ms 워드"], web: "https://www.office.com/launch/word"),
            row(["com.microsoft.Powerpoint"], "Microsoft PowerPoint", ["파워포인트", "파워 포인트", "파포", "피피티", "ppt", "powerpoint"],
                web: "https://www.office.com/launch/powerpoint"),
            row(["com.microsoft.Outlook"], "Microsoft Outlook", ["아웃룩", "outlook"], web: "https://outlook.office.com"),
            row(["com.hancom.office.hwp12.mac.general", "com.hancom.office.hwp.mac.general", "com.hancom.office.hwp10.mac.general"],
                "Hancom Office HWP", ["한글", "한컴", "한컴오피스", "한컴 오피스", "아래아한글", "아래아 한글", "hwp", "한글 워드"]),
            row(["com.apple.iWork.Keynote"], "Keynote", ["키노트"]),
            row(["com.apple.iWork.Pages"], "Pages", ["페이지스", "페이지"]),
            row(["com.apple.iWork.Numbers"], "Numbers", ["넘버스", "넘버즈"]),
            row(["md.obsidian"], "Obsidian", ["옵시디언"]),
            row(["com.microsoft.VSCode"], "Visual Studio Code", ["브이에스코드", "브이에스 코드", "비에스코드", "비주얼 스튜디오 코드", "vs code", "vscode", "코드", "code"]),
            row(["com.apple.dt.Xcode"], "Xcode", ["엑스코드", "x코드"]),
            row(["com.apple.Terminal"], "Terminal", ["터미널"]),
            row(["com.googlecode.iterm2"], "iTerm", ["아이텀", "iterm2", "아이텀2"]),
            row(["com.openai.chat"], "ChatGPT", ["챗지피티", "챗gpt", "지피티", "gpt"], web: "https://chatgpt.com"),
            row(["com.anthropic.claudefordesktop"], "Claude", ["클로드"], web: "https://claude.ai"),
            // Media
            row(["com.spotify.client"], "Spotify", ["스포티파이", "스포티화이", "스포티", "스포"], web: "https://open.spotify.com"),
            row(["com.apple.Music"], "Music", ["음악", "뮤직", "애플 뮤직", "애플뮤직", "apple music", "아이튠즈", "itunes"]),
            row([], "YouTube Music", ["유튜브 뮤직", "유튜브뮤직", "유튭 뮤직", "유튜브 음악", "유뮤", "youtube music", "yt music"], web: "https://music.youtube.com"),
            row([], "YouTube", ["유튜브", "유투브", "유튭", "youtube"], web: "https://www.youtube.com"),
            row([], "Netflix", ["넷플릭스", "넷플"], web: "https://www.netflix.com"),
            row([], "Gmail", ["지메일", "구글 메일", "gmail"], web: "https://mail.google.com"),
            row([], "Google Docs", ["구글 독스", "구글 문서", "구글독스", "google docs"], web: "https://docs.google.com"),
            row([], "Google Sheets", ["구글 시트", "구글 스프레드시트", "스프레드시트", "google sheets"], web: "https://sheets.google.com"),
            row([], "Google Drive", ["구글 드라이브", "드라이브", "google drive"], web: "https://drive.google.com"),
            row([], "Naver", ["네이버", "naver"], web: "https://www.naver.com"),
            row([], "Instagram", ["인스타", "인스타그램", "instagram"], web: "https://www.instagram.com"),
            row([], "GitHub", ["깃허브", "깃헙", "github"], web: "https://github.com"),
            row(["com.apple.podcasts"], "Podcasts", ["팟캐스트"]),
            row(["com.apple.TV"], "TV", ["티비", "애플 tv", "애플티비", "apple tv"]),
            row(["com.apple.QuickTimePlayerX"], "QuickTime Player", ["퀵타임", "퀵타임 플레이어"]),
            row(["com.apple.iBooksX"], "Books", ["책", "북스", "애플 북스"]),
            row(["com.apple.PhotoBooth"], "Photo Booth", ["포토 부스", "포토부스"]),
            // Apple's own
            row(["com.apple.Notes"], "Notes", ["메모", "노트", "애플 메모"]),
            row(["com.apple.reminders"], "Reminders", ["미리 알림", "미리알림", "리마인더", "할 일"]),
            row(["com.apple.iCal"], "Calendar", ["캘린더", "달력", "일정", "칼렌더"]),
            row(["com.apple.mail"], "Mail", ["메일", "이메일", "애플 메일"]),
            row(["com.apple.finder"], "Finder", ["파인더", "파인더 창"]),
            row(["com.apple.systempreferences"], "System Settings", ["시스템 설정", "설정", "환경설정", "시스템 환경설정", "맥 설정", "settings", "system preferences"]),
            row(["com.apple.Maps"], "Maps", ["지도", "맵", "애플 지도"]),
            row(["com.apple.Photos"], "Photos", ["사진", "사진 앱", "포토"]),
            row(["com.apple.calculator"], "Calculator", ["계산기"]),
            row(["com.apple.Preview"], "Preview", ["미리보기", "미리 보기", "프리뷰"]),
            row(["com.apple.TextEdit"], "TextEdit", ["텍스트 편집기", "텍스트편집기", "텍스트 편집", "텍스트에디트", "텍스트 에디트"]),
            row(["com.apple.AddressBook"], "Contacts", ["연락처", "주소록"]),
            row(["com.apple.shortcuts"], "Shortcuts", ["단축어", "숏컷"]),
            row(["com.apple.AppStore"], "App Store", ["앱스토어", "앱 스토어"]),
            row(["com.apple.ActivityMonitor"], "Activity Monitor", ["활성 상태 보기", "활성상태보기", "활동 모니터", "작업 관리자"]),
            row(["com.apple.clock"], "Clock", ["시계"]),
            row(["com.apple.weather"], "Weather", ["날씨"]),
            row(["com.apple.freeform"], "Freeform", ["프리폼"]),
            row(["com.apple.VoiceMemos"], "Voice Memos", ["음성 메모", "음성메모", "녹음"]),
            row(["com.apple.Stickies"], "Stickies", ["스티커", "스티키", "스티커 메모"]),
            row(["com.apple.Home"], "Home", ["홈", "홈 앱"]),
            row(["com.apple.DiskUtility"], "Disk Utility", ["디스크 유틸리티"]),
            row(["com.apple.FontBook"], "Font Book", ["서체 관리자", "폰트북"]),
            row(["com.apple.Passwords"], "Passwords", ["암호", "비밀번호", "패스워드"]),
            row(["com.apple.findmy"], "Find My", ["나의 찾기", "나의찾기"]),
            row(["com.apple.Image_Capture"], "Image Capture", ["이미지 캡처"]),
            row(["com.apple.screenshot.launcher"], "Screenshot", ["스크린샷"]),
        ]

        /// The row a bundle id belongs to.
        static func row(bundle: String, in rows: [Row] = rows) -> Row? {
            rows.first { $0.bundles.contains { $0.caseInsensitiveCompare(bundle) == .orderedSame } }
        }
    }
}
