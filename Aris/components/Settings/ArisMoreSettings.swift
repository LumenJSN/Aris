//
//  ArisMoreSettings.swift
//  Aris
//
//  The notch, music and shelf settings that used to open on their own screens (고급 설정, 음악, 선반) are rows on
//  the 노치 · 사이드 노치 and 노치 기능 pages now. Here: their values as plain data, the keys the rows write, the
//  rounding each control does, and the sections themselves. The stored preferences are the same ones as before, so
//  nothing anyone set moves. Foundation only (tested).
//

import Foundation

/// A value one of these rows writes.
enum ArisMoreKey: Hashable {
    // 노치 · 사이드 노치
    case hoverDelay, rememberTab, animation, animationSpeed
    case closeGesture, mediaSwipe, gestureSensitivity, fixedDirection
    case flatHeightMode, flatHeight, cornerScaling, chin, lockScreen, hideFromRecording, hideFromMissionControl
    // 노치 기능 › 음악
    case musicSource, musicActivity, fullScreen, peek, peekStyle, idleWait
    case coloredBars, tinting
    // 노치 기능 › 선반
    case shelf, wideDrop, copyOnDrag, removeAfterDrag, reverseOrder, quickShare
}

/// What those rows show. The defaults are a fresh install's.
struct ArisMoreSettings: Equatable {
    // 노치 · 사이드 노치
    var hoverDelay = 0.3
    var rememberTab = false
    var animation = true
    var animationSpeed = 1.0
    var closeGesture = true
    var mediaSwipe = false
    /// 100 reacts to the shortest swipe, 300 needs the longest.
    var gestureSensitivity = 200.0
    var fixedDirection = true
    /// The closed notch's height on a display without a notch: "menubar" or "custom".
    var flatHeightMode = "menubar"
    var flatHeight = 32.0
    var cornerScaling = true
    var chin = true
    var lockScreen = false
    var hideFromRecording = false
    var hideFromMissionControl = true

    // 음악
    /// "nowPlaying", "appleMusic" or "spotify".
    var musicSource = "nowPlaying"
    /// False when this Mac's now-playing source doesn't answer (then it can't be picked).
    var nowPlayingWorks = true
    var musicActivity = true
    /// "always", "nowPlayingOnly" or "never".
    var fullScreen = "nowPlayingOnly"
    var peek = false
    /// "standard" or "inline".
    var peekStyle = "standard"
    var idleWait = 3.0
    var coloredBars = true
    var tinting = true
    /// "white", "albumArt" or "accent".

    // 선반
    var shelf = true
    var wideDrop = true
    var copyOnDrag = false
    var removeAfterDrag = false
    var reverseOrder = false
    var quickShare = "AirDrop"
    var quickShareOptions: [ArisSettingOption] = [.init(id: "AirDrop", title: "AirDrop")]
}

/// How each slider rounds what it's dragged to.
enum ArisMoreRounding {
    static func step(_ value: Double, by step: Double, in range: ClosedRange<Double>) -> Double {
        ArisSliderStep.snap(value, in: range, step: step)
    }

    /// A display without a notch takes 0 (all but hidden) or 15–40 points; in between snaps to the nearer end.
    static func flatHeight(_ value: Double) -> Double {
        let points = step(value, by: 1, in: 0...40)
        if points >= 15 || points == 0 { return points }
        return points < 7.5 ? 0 : 15
    }

    static func hoverDelay(_ value: Double) -> Double { step(value, by: 0.1, in: 0...1) }
    static func animationSpeed(_ value: Double) -> Double { step(value, by: 0.1, in: 0.1...2) }
    static func idleWait(_ value: Double) -> Double { step(value, by: 1, in: 0...10) }
}

enum ArisMoreRows {
    private static func options(_ pairs: [(String, String)]) -> [ArisSettingOption] { pairs.map { .init(id: $0.0, title: $0.1) } }
    private static func toggle(_ id: String, _ symbol: String, _ title: String, _ desc: String, _ key: ArisMoreKey, _ on: Bool) -> ArisSettingItem {
        ArisSettingItem(id: id, icon: .symbol(symbol), title: title, desc: desc, control: .toggle(.more(key), on))
    }

    // MARK: 노치 · 사이드 노치

    /// After 위 노치 and 사이드 노치. The gesture rows only while gestures are on.
    static func notch(_ m: ArisMoreSettings, gestures: Bool) -> [ArisSettingSection] {
        var motion = [
            ArisSettingItem(id: "notch.hoverDelay", icon: .symbol("timer"), title: "열리기까지 머무는 시간",
                           desc: "노치 위에 이만큼 머물면 열려요.",
                           control: .slider(.more(.hoverDelay), value: m.hoverDelay, min: 0, max: 1, unit: "초", step: 0.1, zero: "바로")),
            toggle("notch.rememberTab", "bookmark", "보던 탭으로 열기", "다시 열면 닫을 때 보던 탭이 나와요.", .rememberTab, m.rememberTab),
            toggle("notch.animation", "wand.and.rays", "열고 닫는 애니메이션", "끄면 노치가 움직임 없이 바로 열리고 닫혀요.", .animation, m.animation),
        ]
        if m.animation {
            motion.append(ArisSettingItem(id: "notch.animationSpeed", icon: .symbol("gauge.with.dots.needle.50percent"), title: "애니메이션 속도",
                                         desc: "열고 닫는 빠르기예요.",
                                         control: .slider(.more(.animationSpeed), value: m.animationSpeed, min: 0.1, max: 2, unit: "배", step: 0.1)))
        }
        // The groups that are set once, if ever: each is one line until it is opened (pick 7-A).
        var sections = [ArisSettingSection(id: "notch.advanced", heading: "세부 설정", rows: motion,
                                           fold: ArisSettingFold(title: "열기와 움직임", desc: "머무는 시간 · 보던 탭 · 애니메이션", symbol: "wand.and.rays"))]
        if gestures {
            sections.append(ArisSettingSection(id: "notch.gestureDetail", rows: [
                toggle("notch.closeGesture", "hand.point.up", "쓸어 올려 닫기", "열린 노치에서 두 손가락으로 위로 쓸면 닫혀요.", .closeGesture, m.closeGesture),
                toggle("notch.mediaSwipe", "forward.end", "옆으로 쓸어 곡 넘기기", "노치 위에서 두 손가락으로 왼쪽, 오른쪽으로 쓸면 이전 곡, 다음 곡이에요.",
                       .mediaSwipe, m.mediaSwipe),
                toggle("notch.fixedDirection", "arrow.up.arrow.down", "제스처 방향 고정",
                       "‘자연스러운 스크롤’을 켜든 끄든 아래로 쓸면 열리고 위로 쓸면 닫혀요.", .fixedDirection, m.fixedDirection),
                ArisSettingItem(id: "notch.sensitivity", icon: .symbol("dial.medium"), title: "제스처 감도", desc: "얼마나 길게 쓸어야 반응할지 정해요.",
                               control: .choice(.more(.gestureSensitivity), options([("100", "예민하게"), ("200", "보통"), ("300", "둔하게")]),
                                                selected: String(Int(m.gestureSensitivity)))),
            ], fold: ArisSettingFold(title: "제스처 세부", desc: "닫기 · 곡 넘기기 · 방향 · 감도", symbol: "hand.draw")))
        }
        var window = [
            ArisSettingItem(id: "notch.flatHeight", icon: .symbol("display"), title: "노치 없는 화면",
                           desc: "외장 모니터처럼 노치가 없는 화면에서 닫힌 노치의 높이예요.",
                           control: .choice(.more(.flatHeightMode), options([("menubar", "메뉴 막대"), ("custom", "직접")]), selected: m.flatHeightMode)),
        ]
        if m.flatHeightMode == "custom" {
            window.append(ArisSettingItem(id: "notch.flatCustomHeight", icon: .symbol("slider.horizontal.3"), title: "노치 없는 화면의 높이",
                                         desc: "0으로 두면 거의 보이지 않아요.",
                                         control: .slider(.more(.flatHeight), value: m.flatHeight, min: 0, max: 40, unit: "pt")))
        }
        window += [
            toggle("notch.cornerScaling", "rectangle.roundedbottom", "높이에 맞춘 모서리", "닫힌 노치가 낮거나 높으면 모서리 둥글기도 그만큼 바꿔요.",
                   .cornerScaling, m.cornerScaling),
            toggle("notch.chin", "menubar.rectangle", "메뉴 막대 아래 띠까지", "닫힌 노치가 메뉴 막대보다 낮으면 남는 띠까지 노치 자리로 써요.", .chin, m.chin),
            toggle("notch.lockScreen", "lock", "잠금 화면에서도 보이기", "Mac이 잠겨 있을 때도 노치를 띄워 둬요.", .lockScreen, m.lockScreen),
            toggle("notch.hideFromRecording", "record.circle", "화면 기록에서 숨기기", "화면을 녹화하거나 공유할 때 노치가 찍히지 않아요.",
                   .hideFromRecording, m.hideFromRecording),
            toggle("notch.hideFromMissionControl", "rectangle.3.group", "미션 컨트롤에서 숨기기", "노치가 없는 화면의 노치를 미션 컨트롤에 보이지 않게 해요.",
                   .hideFromMissionControl, m.hideFromMissionControl),
        ]
        sections.append(ArisSettingSection(id: "notch.window", rows: window,
                                           fold: ArisSettingFold(title: "창", desc: "노치 없는 화면 · 모서리 · 잠금 화면 · 화면 기록", symbol: "macwindow")))
        return sections
    }

    // MARK: 노치 기능

    static func music(_ m: ArisMoreSettings) -> ArisSettingSection {
        var rows = [
            ArisSettingItem(id: "features.musicSource", icon: .symbol("music.note.list"), title: "음악 가져올 곳",
                           desc: m.nowPlayingWorks ? "‘지금 재생 중’은 어느 앱에서 틀든 보여 줘요."
                                                   : "‘지금 재생 중’이 답하지 않으니 Apple Music이나 Spotify를 골라 주세요.",
                           control: .choice(.more(.musicSource), options([("nowPlaying", "지금 재생 중"), ("appleMusic", "Apple Music"), ("spotify", "Spotify")]),
                                            selected: m.musicSource, disabled: m.nowPlayingWorks ? [] : ["nowPlaying"],
                                            lead: m.nowPlayingWorks ? nil : ArisSettingButton(title: "다시 확인", action: .recheckNowPlaying))),
            toggle("features.musicActivity", "music.note", "닫힌 노치에 재생 중인 곡", "음악이 나오면 닫힌 노치 양옆에 앨범 아트와 막대가 보여요.",
                   .musicActivity, m.musicActivity),
            ArisSettingItem(id: "features.fullScreen", icon: .symbol("arrow.up.left.and.arrow.down.right"), title: "전체 화면일 때",
                           desc: "전체 화면 앱 위에서 노치를 숨길지 정해요.",
                           control: .menu(.more(.fullScreen), options([("always", "늘 숨기기"), ("nowPlayingOnly", "음악 앱일 때만 숨기기"), ("never", "숨기지 않기")]),
                                          selected: m.fullScreen)),
            toggle("features.peek", "eye", "곡이 바뀌면 잠깐 보여 주기", "새 곡이 시작되면 제목을 잠깐 띄워요.", .peek, m.peek),
        ]
        if m.peek {
            rows.append(ArisSettingItem(id: "features.peekStyle", icon: .symbol("text.below.photo"), title: "보여 주는 곳", desc: "제목을 노치 아래에 띄울지, 노치 안에 넣을지예요.",
                                       control: .choice(.more(.peekStyle), options([("standard", "노치 아래"), ("inline", "노치 안")]), selected: m.peekStyle)))
        }
        rows += [
            ArisSettingItem(id: "features.idleWait", icon: .symbol("pause.circle"), title: "멈춘 뒤 남아 있는 시간",
                           desc: "일시 정지한 뒤 이만큼 지나면 닫힌 노치에서 사라져요.",
                           control: .slider(.more(.idleWait), value: m.idleWait, min: 0, max: 10, unit: "초", zero: "바로")),
            toggle("features.coloredBars", "waveform", "앨범 색 막대", "닫힌 노치의 막대를 앨범 아트 색으로 칠해요.", .coloredBars, m.coloredBars),
            toggle("features.tinting", "paintbrush", "플레이어에 앨범 색", "가수 이름과 곡 제목 띠를 앨범 아트 색으로 보여 줘요.", .tinting, m.tinting),
        ]
        return ArisSettingSection(id: "features.music", heading: "음악", rows: rows)
    }

    static func shelf(_ m: ArisMoreSettings) -> ArisSettingSection {
        ArisSettingSection(id: "features.shelf", heading: "선반", rows: [
            toggle("features.shelfOn", "tray", "선반 쓰기", "파일을 노치에 끌어다 잠깐 올려 두는 탭이에요.", .shelf, m.shelf),
            toggle("features.wideDrop", "arrow.down.to.line", "노치 근처에서도 받기", "파일을 노치 가까이 끌어오기만 해도 노치가 열려요.", .wideDrop, m.wideDrop),
            toggle("features.copyOnDrag", "doc.on.doc", "끌어낼 때 복사", "선반에서 파일을 끌어내면 옮기지 않고 복사해요.", .copyOnDrag, m.copyOnDrag),
            toggle("features.removeAfterDrag", "tray.and.arrow.up", "끌어낸 뒤 선반에서 빼기", "파일을 다른 곳에 놓으면 선반에서 사라져요.", .removeAfterDrag, m.removeAfterDrag),
            toggle("features.reverseOrder", "arrow.left.arrow.right", "순서 거꾸로", "선반 타일을 반대 순서로 늘어놓아요.", .reverseOrder, m.reverseOrder),
            ArisSettingItem(id: "features.quickShare", icon: .symbol("square.and.arrow.up"), title: "빠른 공유", desc: "선반의 공유 타일에 파일을 놓으면 보낼 곳이에요.",
                           control: .menu(.more(.quickShare), m.quickShareOptions, selected: m.quickShare)),
        ])
    }
}
