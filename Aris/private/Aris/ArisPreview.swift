//
//  ArisPreview.swift
//  Aris
//
//  Puts the notch in a turn's look without a microphone or an AI, to check the design (listening band, thinking,
//  an answer, a long answer streaming in, steps then a markdown answer, a confirmation card (a long one, one with cut
//  text and 전체 보기, and the "앞으로 이건 그냥 할까?" proposal), an answer parked after the turn,
//  a long finished answer, a long prompt, the composer at one to four lines, Claude's done/error/limit notice, the usage tab's list and Claude's detail, silently), and
//  `side-demo:on|off`: the side panels on built-in sample rows (ArisSideDemo), and the ad's scripted demos (`team-demo`,
//  `dictation-demo:<text>`, `circle-demo[:x,y,w,h]`, each with `:off`; ArisAdDemo). Only while ~/.config/aris/aris-preview exists: its first line names the
//  state, and the "com.lumenjsn.aris.preview" distributed notification applies it. Nothing it shows can act — a
//  preview confirmation has no turn waiting on it.
//

import AppKit
import AVFoundation
import Defaults
import Foundation
import OSLog
import Speech
import SwiftUI

@MainActor
final class ArisPreview {
    static let shared = ArisPreview()

    private static var file: URL { URL(fileURLWithPath: ArisKeyFile.folder + "aris-preview") }
    private static let heard = "내일 오후 세 시에 팀 회의 잡고 엄마한테 늦는다고 문자 보내줘"
    private var voice: Timer?
    /// The answer-stream state's tokens, one every 40 ms.
    private var stream: Timer?
    /// Opens (true) or closes the top notch; set by the app delegate, which owns the notch windows.
    var notch: ((Bool) -> Void)?

    func watch() {
        // What a first ⌥Space will run into (reading these never prompts).
        let mic = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
        let speech = SFSpeechRecognizer.authorizationStatus().rawValue
        Logger(subsystem: "com.lumenjsn.aris", category: "permissions")
            .notice("microphone \(mic, privacy: .public) speech \(speech, privacy: .public) (0 not asked, 1 restricted, 2 denied, 3 allowed)")
        DistributedNotificationCenter.default().addObserver(forName: .init("com.lumenjsn.aris.preview"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ArisPreview.shared.apply() }
        }
    }

    private func apply() {
        guard let text = try? String(contentsOf: Self.file, encoding: .utf8) else { return }
        let state = text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let aris = ArisController.shared
        if state.hasPrefix("settings:") {
            let parts = state.split(separator: ":").map(String.init)
            if parts.count > 1, let page = ArisSettingsPage.named(parts[1]) { ArisSettingsNav.shared.page = page }
            if parts.count > 2 { Defaults[.arisSettingsTheme] = parts[2] }
            return ArisSettingsWindow.shared.show()
        }
        if state.hasPrefix("side-tab:") {
            let tabs: [String: ArisSidePanels.Tab] = ["history": .history, "activity": .activity, "clipboard": .clipboard, "usage": .usage]
            if let tab = tabs[String(state.dropFirst(9))] { ArisSidePanels.shared.show(.left, tab: tab) }
            return
        }
        // The side panels on built-in samples (ArisSideDemo): nothing real read or written, nothing kept past `off` or a quit.
        if let on = ArisSideDemoSwitch.wanted(state) {
            ArisSideDemo.shared.set(on)
            return Self.report("side-demo \(ArisSideDemo.shared.isOn ? "on" : "off")")
        }
        // The ad's scripted demos (ArisAdDemo): the real views on scripted data, nothing run, read or kept.
        if let command = ArisAdDemoCommand.parse(state) { return Self.report(ArisAdDemo.shared.handle(command)) }
        if state.hasPrefix("todo-") || state.hasPrefix("side-todo") {
            // The test list's states write to Reminders: never while the demo shows its samples.
            if ArisSideDemo.shared.isOn, state.hasPrefix("todo-") { return Self.report("\(state) skipped: side-demo is on") }
            Self.todo(state)
            return
        }
        if state.hasPrefix("settings-detail:") || state.hasPrefix("settings-sheet:") {
            let nav = ArisSettingsNav.shared
            let value = String(state.drop { $0 != ":" }.dropFirst())
            if state.hasPrefix("settings-detail:") {
                // The old screens' names, now sections of the pages.
                let anchors: [String: (ArisSettingsPage, String)] = ["notchAdvanced": (.notch, "notch.advanced"),
                                                                     "music": (.features, "features.music"), "shelf": (.features, "features.shelf")]
                let (page, anchor) = anchors[value] ?? (.features, "features.music")
                nav.go(page, anchor: anchor)
            } else {
                nav.page = .voice
                nav.sheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { nav.sheet = value }
            }
            return ArisSettingsWindow.shared.show()
        }
        if state.hasPrefix("permission-guide:") {
            let kind = ArisPermissionGuide.Kind(rawValue: String(state.dropFirst("permission-guide:".count))) ?? .accessibility
            return ArisPermissionGuide.shared.show(kind)
        }
        if state == "permission-guide-close" { return ArisPermissionGuide.shared.close() }
        // Test turns ("검증 …") out of the 기록 tab.
        if state.hasPrefix("history-forget:") {
            let prefix = String(state.dropFirst("history-forget:".count))
            guard prefix.count >= 2 else { return }
            let before = aris.pastTurns.count
            aris.forgetPastTurns { $0.heard.hasPrefix(prefix) }
            return Self.report("history-forget \"\(prefix)\": \(before - aris.pastTurns.count) removed")
        }
        if state.hasPrefix("intent:") {
            let text = String(state.dropFirst(7))
            Task {
                aris.silentSpeech = true
                await aris.answer(text)
                aris.silentSpeech = false
                Self.report("intent \"\(text)\" -> reply: \(aris.session.reply)")
            }
            return
        }
        if state == "side-debug-rows:on" || state == "side-debug-rows:off" {
            UserDefaults.standard.set(state.hasSuffix(":on"), forKey: "arisDebugRowFill")
            return
        }
        if state == "side-pin:left" || state == "side-pin:right" {
            // The same call as a click on the lock.
            ArisSidePanels.shared.togglePin(state.hasSuffix("left") ? .left : .right)
            return
        }
        if state == "side-calendar" {
            ArisSidePanels.shared.show(.right, tab: .calendar)
            return
        }
        if state == "notch-open" || state == "notch-close" { notch?(state == "notch-open"); return }
        if state.hasPrefix("view:") {
            let views: [String: NotchViews] = ["home": .home, "claude": .claude, "shelf": .shelf]
            // The same call as a tap on the header's place icons.
            if let view = views[String(state.dropFirst(5))] { withAnimation(ArisGlass.resize) { ArisNotchNavigation.shared.currentView = view } }
            return
        }
        if state == "settings-close" { return ArisSettingsWindow.shared.close() }
        switch state {
        case "claude-done": return ClaudeStore.shared.previewPeek(.done)
        case "claude-error": return ClaudeStore.shared.previewPeek(.error)
        case "claude-limit": return ClaudeStore.shared.previewPeek(.limit)
        case "side-usage": return showUsage(detail: nil)
        case "side-usage-claude": return showUsage(detail: "claude")
        case "side-usage-codex": return showUsage(detail: "codex")
        case "side-usage-antigravity": return showUsage(detail: "antigravity")
        case "side-close":
            // It also ends the ad demos, and whatever they put up.
            ArisAdDemo.shared.stopAll()
            return ArisSidePanels.Edge.allCases.forEach { ArisSidePanels.shared.collapse($0) }
        default: break
        }
        speak(state == "listening" || state == "listening-words")
        stream?.invalidate()
        stream = nil
        switch state {
        case "listening": aris.session = ArisSession().listening()
        case "listening-words": aris.session = ArisSession().listening().hearing(Self.heard)
        case "thinking": aris.session = ArisSession().listening().hearing(Self.heard).thinking().working("캘린더 확인하는 중")
        case "confirm":
            aris.session = ArisSession().listening().hearing(Self.heard).thinking()
                .asking(ArisConfirmation(id: "preview", title: "메시지 보내기", detail: "받는 사람: 엄마\n내용: 오늘 조금 늦어요"))
        case "answer":
            aris.session = ArisSession().listening().hearing(Self.heard).thinking()
                .answering("내일 오후 3시에 ‘팀 회의’를 캘린더에 넣었어요. 엄마한테는 “오늘 조금 늦어요”라고 보냈어요.")
        case "answer-stream": streamAnswer()
        // Three steps 1.5 s apart (each tag entering, the one before landing its check), then a markdown answer.
        case "answer-steps": streamAnswer(Self.markdownAnswer, steps: ["캘린더 확인하는 중", "메시지 준비 중", "웹 검색 중"], stepEvery: 1.5)
        case "confirm-long":
            aris.session = ArisSession().listening().hearing(Self.heard).thinking().working("메시지 준비 중")
                .asking(ArisConfirmation(id: "preview", title: "메시지 보내기", detail: Self.longConfirmDetail))
        case "confirm-cut":
            let body = String(repeating: "회의 자료 정리해서 내일까지 공유할게요. ", count: 8)
            aris.session = ArisSession().listening().hearing(Self.heard).thinking().working("Notion 작업 중")
                .asking(ArisConfirmation(id: "preview", title: "Notion · notion-create-comment",
                                         detail: "대상: 1a2b…9z8y\n내용: \(body.prefix(119))… (+\(body.count - 119)자)",
                                         full: "대상: 1a2b3c4d5e6f7g8h9z8y\n내용: \(body)"))
        case "proposal":
            aris.session = ArisSession().listening().hearing(Self.heard).thinking().working("메시지 준비 중")
                .asking(ArisConfirmation(id: "preview", title: "앞으로 이건 그냥 할까?", detail: "종류: message\n앱: aris-tools\n대상: 엄마", proposal: true))
        case "parked":
            aris.session = .parked(heard: Self.heard, reply: "내일 오후 3시에 ‘팀 회의’를 캘린더에 넣었어요. 엄마한테는 “오늘 조금 늦어요”라고 보냈어요.")
        // The long answer, finished and no longer spoken: 닫기 alone, and 답 열기 under it.
        case "answer-done":
            aris.session = ArisSession().listening().hearing(Self.heard).thinking().answering(Self.longAnswer).done()
        // Words over two lines: the prompt card collapsed under its fade (tap to open it all).
        case "prompt-long":
            aris.session = ArisSession().listening().hearing(Self.longHeard).thinking()
                .answering("내일 오후 3시에 ‘팀 회의’를 3층 큰 회의실에 잡고 초대장을 보냈어요. 엄마한테는 “오늘 조금 늦어요, 저녁은 먼저 드세요”라고 보냈어요.")
        // The composer under a parked answer with one to four typed lines (it stops growing at three).
        case _ where state.hasPrefix("composer-"):
            aris.session = .parked(heard: Self.heard, reply: "내일 오후 3시에 ‘팀 회의’를 캘린더에 넣었어요.")
            let count = Int(state.dropFirst("composer-".count)) ?? 0
            let draft = (0..<count).map { "\($0 + 1)번째 줄: 내일 회의 자료도 같이 보내 줘" }.joined(separator: "\n")
            // After the composer is on screen to hear it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NotificationCenter.default.post(name: ArisComposer.previewDraft, object: draft)
            }
        default: aris.session = ArisSession()
        }
    }

    /// Words long enough for four lines of the prompt card.
    private static let longHeard = "내일 오후 세 시에 팀 회의 잡고 회의실은 3층 큰 방으로 예약해 줘. 참석자는 지난번 회의랑 같은 다섯 명으로 넣고 초대장도 바로 보내 줘. 그리고 엄마한테 오늘 조금 늦는다고 문자 보내고 저녁은 먼저 드시라고 해 줘."

    /// Results the harness reports, read back with `log show --predicate 'eventMessage CONTAINS "ARISPV"'`.
    static func report(_ text: String) {
        Logger(subsystem: "com.lumenjsn.aris", category: "preview").notice("ARISPV \(text, privacy: .public)")
    }

    private static var savedTodoLists: [String]?
    private static var testListID: String?

    /// To-do tab previews: a test Reminders list ("Aris 테스트") with two items, the tab, its composer, a completion.
    private static func todo(_ state: String) {
        let panels = ArisSidePanels.shared, model = ArisTodoModel.shared, reminders = ArisReminders.shared
        switch state {
        case "todo-seed":
            Task {
                guard reminders.authorized, let list = await reminders.createList(named: "Aris 테스트") else { return }
                testListID = list.id
                savedTodoLists = Defaults[.arisTodoLists]
                Defaults[.arisTodoLists] = [list.id]
                let cal = Calendar.current
                let tomorrow = cal.date(bySettingHour: 15, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: .now) ?? .now)
                var first = ArisTodoDraft()
                first.title = "보고서 초안 쓰기"
                first.due = tomorrow
                first.hasTime = true
                first.notes = "교수님께 보낼 초안"
                first.listID = list.id
                await reminders.add(first)
                var second = ArisTodoDraft()
                second.title = "우유 사기"
                second.listID = list.id
                await reminders.add(second)
                await model.refresh()
            }
        case "todo-cleanup":
            Task {
                for list in reminders.lists where list.id == testListID || list.name == "Aris 테스트" { await reminders.deleteList(list.id) }
                Defaults[.arisTodoLists] = savedTodoLists ?? []
                testListID = nil
                savedTodoLists = nil
                model.composing = nil
                await model.refresh()
            }
        case "todo-seedv":
            guard reminders.authorized else { return report("seedv: no access") }
            Task {
                let found = reminders.lists.first { $0.name == "검증 목록" }
                let list = if let found { Optional(found) } else { await reminders.createList(named: "검증 목록") }
                report("seedv list \(list?.name ?? "nil")")
            }
        case "todo-purge":
            Task {
                let count = await reminders.purge(titlePrefix: "검증")
                for list in reminders.lists where list.name == "검증 목록" { await reminders.deleteList(list.id) }
                report("purged \(count) reminders, test list removed")
            }
        case "todo-dump":
            Task { report("dump: " + (await reminders.describe(titlePrefix: "검증")).joined(separator: " || ")) }
        case _ where state.hasPrefix("side-todo-type:"):
            let text = String(state.dropFirst("side-todo-type:".count))
            panels.show(.right, tab: .todo)
            model.composing = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                let sides = NSApp.windows.compactMap { $0 as? ArisSideWindow }
                let desc = sides.map { "\($0.edge.rawValue) key=\($0.isKeyWindow) first=\($0.firstResponder.map { String(describing: type(of: $0)) } ?? "nil") editing=\(($0.firstResponder as? NSText)?.isFieldEditor ?? false)" }
                report("typing: appActive=\(NSApp.isActive) keyWindow=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil") sides: \(desc.joined(separator: "; "))")
                let right = NSApp.windows.compactMap { $0 as? ArisSideWindow }.first { $0.edge == .right }
                report("typing: ignoresMouse=\(right?.ignoresMouseEvents ?? false) canBecomeKey=\(right?.canBecomeKey ?? false) visible=\(right?.isVisible ?? false)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    report("typing after makeKeyAndOrderFront: key=\(right?.isKeyWindow ?? false) first=\(right?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")
                }
                model.chipRequest = "settitle=" + text
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.chipRequest = "submit" }
            }
        case _ where state.hasPrefix("side-todo-chip:"):
            model.chipRequest = String(state.dropFirst("side-todo-chip:".count))
        case _ where state.hasPrefix("todo-act:"):
            let parts = state.split(separator: ":", maxSplits: 2).map(String.init)
            let op = parts.count > 1 ? parts[1] : ""
            let prefix = parts.count > 2 ? parts[2] : ""
            guard let item = model.items.first(where: { $0.title.hasPrefix(prefix) }) else { return report("act \(op): no item \(prefix)") }
            Task {
                switch op {
                case "edit":
                    var draft = ArisTodoDraft(item)
                    draft.title = item.title + " 수정됨"
                    draft.due = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: .now))
                    draft.hasTime = false
                    await model.update(item, draft)
                case "postpone": await reminders.postponeToTomorrow(item.id)
                case "move":
                    if let target = reminders.lists.first(where: { $0.name == "검증 목록" }) { await reminders.move(item.id, to: target.id) }
                case "delete": await model.remove(item)
                case "open": reminders.openInReminders(item.id)
                default: break
                }
                report("act \(op) \(item.title)")
            }
        case "side-todo-undo":
            panels.show(.right, tab: .todo)
            model.completeRequest = model.items.first { $0.title.hasPrefix("검증") }?.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { model.completeRequest = model.items.first { $0.title.hasPrefix("검증") }?.id }
        case "side-todo-complete-v":
            panels.show(.right, tab: .todo)
            model.completeRequest = model.items.first { $0.title.hasPrefix("검증") }?.id
        case "side-todo-composer":
            panels.show(.right, tab: .todo)
            model.composing = ""
        case "side-todo-edit":
            panels.show(.right, tab: .todo)
            model.composing = model.items.first?.id
        case "side-todo-complete":
            panels.show(.right, tab: .todo)
            model.completeRequest = model.items.first { $0.due == nil }?.id
        case "side-todo-close":
            model.composing = nil
            panels.collapse(.right)
        default:
            panels.show(.right, tab: .todo)
            model.composing = nil
        }
    }

    private func showUsage(detail: String?) {
        ArisSidePanels.shared.show(.left, tab: .usage)
        ArisSidePanels.shared.usageDetail = detail
    }

    /// A long answer written token by token at about 25 a second, through the same calls the AI's stream uses
    /// (`showAnswer`, then `showFinalAnswer`). No voice. With `stepEvery`, the AI first works through `steps`, one
    /// every `stepEvery` seconds, before the first token.
    private func streamAnswer(_ answer: String = ArisPreview.longAnswer, steps: [String] = ["캘린더 확인하는 중"], stepEvery: TimeInterval = 0) {
        let aris = ArisController.shared
        aris.session = ArisSession().listening().hearing(Self.heard).thinking().working(steps[0])
        let tokens = Self.tokens(answer)
        let ticksPerStep = Int((stepEvery / 0.04).rounded())
        var ticks = 0
        var written = ""
        var next = 0
        stream = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                ticks += 1
                if ticksPerStep > 0, ticks < ticksPerStep * steps.count {
                    if ticks % ticksPerStep == 0 { aris.session = aris.session.working(steps[ticks / ticksPerStep]) }
                    return
                }
                guard next < tokens.count else {
                    timer.invalidate()
                    self?.stream = nil
                    aris.showFinalAnswer(answer)
                    return
                }
                written += tokens[next]
                next += 1
                aris.showAnswer(written)
            }
        }
    }

    /// Two to four characters at a time, about what a model streams for Korean.
    private static func tokens(_ text: String) -> [String] {
        let sizes = [3, 2, 4, 3, 2]
        var pieces: [String] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            let size = sizes[pieces.count % sizes.count]
            pieces.append(String(rest.prefix(size)))
            rest = rest.dropFirst(size)
        }
        return pieces
    }

    /// About 1,200 characters: a few paragraphs and a short list.
    private static let longAnswer = """
    내일 일정부터 정리해 드릴게요. 오전 아홉 시 반에 디자인 리뷰가 있고, 열한 시에는 지난주에 미뤄 둔 주간 회의가 잡혀 있어요. 점심 이후로는 비어 있어서 말씀하신 팀 회의는 오후 세 시에 넣었어요. 회의실은 아직 정하지 않았으니, 필요하면 나중에 말씀해 주세요. 참석자는 지난번 회의와 같은 다섯 명으로 넣어 두었고, 초대장은 아직 보내지 않았어요.

    엄마한테는 “오늘 조금 늦어요, 저녁은 먼저 드세요”라고 문자를 보냈어요. 보낸 시각은 오후 다섯 시 십이 분이고, 아직 읽지 않으셨어요. 답장이 오면 알림으로 알려 드릴게요. 혹시 도착 시간을 같이 알려 드리고 싶으시면 지금 교통 상황 기준으로 계산해서 한 번 더 보낼 수 있어요.

    이번 주에 놓치기 쉬운 것들도 같이 모아 봤어요.

    - 목요일 오전까지 보고서 초안을 교수님께 보내야 해요.
    - 금요일 저녁 일곱 시에 친구 생일 모임이 있어요. 선물은 아직 안 고르셨어요.
    - 토요일에 자동차 정기 점검 예약이 잡혀 있어요.
    - 다음 주 월요일이 통신비 자동 이체 날이에요.

    메일함도 잠깐 훑어봤어요. 오늘 들어온 메일 중에 답장이 필요한 건 세 통이에요. 하나는 동아리 회비 정산 건으로 이번 주 안에 계좌를 알려 달라는 내용이고, 하나는 수강 신청 변경 기간이 금요일에 끝난다는 학과 공지예요. 마지막 하나는 지난달에 주문한 키보드가 배송 지연된다는 안내인데, 환불이나 기다리기 중에 고르라고 해요. 셋 다 급하진 않지만 회비 정산은 내일 오전에 처리해 두시면 좋겠어요.

    날씨도 확인해 봤는데, 내일은 오후부터 비 소식이 있어요. 강수 확률은 칠십 퍼센트 정도이고 저녁에는 바람이 꽤 강하게 분다고 하니, 회의 끝나고 나가실 때 우산을 챙기시는 게 좋겠어요. 기온은 아침 팔 도, 낮 최고 십사 도로 오늘보다 조금 쌀쌀해요.

    마지막으로, 지난번에 말씀하신 운동 계획은 화요일과 목요일 저녁 여덟 시로 캘린더에 반복 일정으로 넣어 두었어요. 바꾸고 싶은 요일이나 시간이 있으면 말씀만 하세요. 그리고 보고서 초안은 오늘 밤에 한 시간 정도 집중 시간을 잡아 두면 목요일 마감까지 여유가 있을 것 같아요. 원하시면 지금 바로 오늘 밤 아홉 시부터 열 시까지 집중 시간으로 막아 둘게요. 다른 일정과 겹치지 않는지도 미리 확인해 두었으니, 그냥 “응”이라고만 말씀하시면 바로 넣어 둘게요. 내일 아침에는 오늘 정리한 내용을 짧게 다시 알려 드릴게요.
    """

    /// Every block the answer's markdown draws: headings, bold, a bulleted and a numbered list, a quote and code.
    private static let markdownAnswer = """
    ## 내일 일정

    오전에는 **디자인 리뷰**가 있고, 오후 세 시에 팀 회의를 넣었어요. 회의실은 아직 정하지 않았어요.

    - 오전 9시 30분: 디자인 리뷰
    - 오전 11시: 주간 회의
    - 오후 3시: **팀 회의** (새로 넣음)

    ### 보낸 메시지

    > 오늘 조금 늦어요, 저녁은 먼저 드세요

    1. 엄마한테 보냈어요.
    2. 답장이 오면 알려 드릴게요.

    필요하면 `팀 회의` 초대장도 바로 보낼 수 있어요.
    """

    /// A confirmation taller than 440 points, so the card scrolls under its floating 허용.
    private static let longConfirmDetail = (["받는 사람: 엄마", "보내는 곳: 메시지"]
        + (1...14).map { "\($0)번째 줄: 오늘 조금 늦어요, 저녁은 먼저 드세요" }
        + ["내용 전체를 확인한 뒤 보내 주세요. 보낸 메시지는 되돌릴 수 없어요."]).joined(separator: "\n")

    /// A voice-like level for the bars while "listening".
    private func speak(_ on: Bool) {
        voice?.invalidate()
        voice = nil
        ArisController.shared.level = 0
        guard on else { return }
        let start = Date()
        voice = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(start)
                let syllables = abs(sin(t * 9)) * (0.6 + 0.4 * sin(t * 1.7))
                ArisController.shared.level = Float(0.15 + 0.75 * syllables)
            }
        }
    }
}
