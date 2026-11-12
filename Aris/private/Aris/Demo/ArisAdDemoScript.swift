//
//  ArisAdDemoScript.swift
//  Aris
//
//  The ad's scripted demos (ArisPreview `team-demo`, `dictation-demo:<text>`, `circle-demo`, each with `:off`), for a
//  recording made with nobody at the Mac: what each one says and when, as plain data. ArisAdDemo plays it through the
//  real notch, pill, figures, dictation card and ink; nothing here runs an AI, opens the microphone, captures the screen
//  or writes anything. Pure, so the tests run it.
//

import CoreGraphics
import Foundation

/// The three demos (side-demo is ArisSideDemo's).
enum ArisAdDemoKind: String, CaseIterable, Equatable {
    case team, dictation, circle
}

/// One preview state for a demo, or nil for anything else.
enum ArisAdDemoCommand: Equatable {
    case team
    case dictation(String)
    /// A rect in the notch display's points from its top left (nil: the default, in the middle).
    case circle(CGRect?)
    case off(ArisAdDemoKind)

    /// The dictated words read at most (the file is the harness's, but it is still bounded).
    static let maxText = 400

    static func parse(_ state: String) -> ArisAdDemoCommand? {
        let trimmed = state.trimmingCharacters(in: .whitespaces)
        let (head, rest) = split(trimmed)
        switch head.lowercased() {
        case "team-demo":
            guard let rest else { return .team }
            return rest.lowercased() == "off" ? .off(.team) : nil
        case "dictation-demo":
            guard let rest else { return nil }
            if rest.lowercased() == "off" { return .off(.dictation) }
            let words = rest.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let visible = String(words.unicodeScalars.filter { !$0.properties.generalCategory.isInvisible })
            guard !visible.isEmpty else { return nil }
            return .dictation(String(visible.prefix(maxText)))
        case "circle-demo":
            guard let rest else { return .circle(nil) }
            if rest.lowercased() == "off" { return .off(.circle) }
            return rect(rest).map { .circle($0) }
        default:
            return nil
        }
    }

    var kind: ArisAdDemoKind {
        switch self {
        case .team: .team
        case .dictation: .dictation
        case .circle: .circle
        case .off(let kind): kind
        }
    }

    private static func split(_ state: String) -> (String, String?) {
        guard let colon = state.firstIndex(of: ":") else { return (state, nil) }
        return (String(state[..<colon]), String(state[state.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
    }

    /// "x,y,w,h", every one a finite number, the rect at least 40 × 40 and at most 4000 on a side.
    private static func rect(_ text: String) -> CGRect? {
        let numbers = text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 4, let x = numbers[0], let y = numbers[1], let w = numbers[2], let h = numbers[3],
              [x, y, w, h].allSatisfy(\.isFinite), (40...4000).contains(w), (40...4000).contains(h), x >= 0, y >= 0
        else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

private extension Unicode.GeneralCategory {
    var isInvisible: Bool {
        switch self {
        case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned: true
        default: false
        }
    }
}

/// Which demos run. Only one at a time (they all drive the one notch): starting one stops the others. `:off` stops its
/// own; side-close and quitting stop them all.
struct ArisAdDemoBoard: Equatable {
    private(set) var running: Set<ArisAdDemoKind> = []

    /// The demos to stop before `kind` starts (every running one, `kind` too: it starts again from the top).
    mutating func start(_ kind: ArisAdDemoKind) -> [ArisAdDemoKind] {
        let stopping = ArisAdDemoKind.allCases.filter(running.contains)
        running = [kind]
        return stopping
    }

    /// True when `kind` was running.
    mutating func stop(_ kind: ArisAdDemoKind) -> Bool {
        running.remove(kind) != nil
    }

    /// side-close or quit: every running demo, to stop.
    mutating func stopAll() -> [ArisAdDemoKind] {
        defer { running = [] }
        return ArisAdDemoKind.allCases.filter(running.contains)
    }
}

/// Where every demo plays: the built-in display with the notch (the one the ad records), whatever display the owner picked
/// for the notch or has in front; then any built-in display, then his pick, then the main one.
enum ArisAdDemoDisplay {
    struct Screen: Equatable {
        let notch: Bool
        let builtIn: Bool
        let selected: Bool
        let main: Bool
    }

    static func pick(_ screens: [Screen]) -> Int? {
        screens.firstIndex { $0.notch && $0.builtIn } ?? screens.firstIndex(where: \.notch) ?? screens.firstIndex(where: \.builtIn)
            ?? screens.firstIndex(where: \.selected) ?? screens.firstIndex(where: \.main) ?? (screens.isEmpty ? nil : 0)
    }
}

/// One timed step of a demo: `at` seconds from its start.
struct ArisAdDemoCue<Step: Equatable>: Equatable {
    let at: TimeInterval
    let step: Step
}

// MARK: - team-demo

/// A teammate that exists only in the demo (never in the teammates file): its id, name and face.
struct ArisAdDemoMate: Equatable {
    let id: String
    let name: String
    let look: ArisCharacterLook
}

enum ArisTeamDemoStep: Equatable {
    /// The listening band, with a voice-like level.
    case listen
    /// The words heard so far.
    case hear(String)
    /// The key let go: the notch opens on the prompt card.
    case think
    /// The two jobs, queued then started (job 0 Claude Code's, job 1 코디's).
    case dispatch
    /// What Aris says it handed out.
    case reply(String)
    /// A job's live step, its teammate's bubble.
    case progress(job: Int, String)
    /// A job is done: 끝났어요, the poke, home.
    case finish(job: Int)
    /// The turn is over: the notch closes after the line's reading time.
    case closeTurn
    /// The demo's jobs leave the list (the pill is long gone).
    case clear
}

enum ArisTeamDemoScript {
    static let prompt = "Claude Code는 실크로드 소개글을 쓰고, 코디는 슬라이드 개요를 정리해 줘"
    /// Its id starts with the side demo's prefix (ArisSideDemoSamples.idPrefix), so it is never taken for a real teammate.
    static let kodi = ArisAdDemoMate(id: "aris-demo-kodi", name: "코디", look: .standard)
    static let claudeCodeId = "claude-code"

    struct Job: Equatable {
        let title: String
        let teammate: String
        let steps: [String]
        let result: String
    }

    static let jobs = [
        Job(title: "실크로드 소개글 쓰기", teammate: claudeCodeId,
            steps: ["실크로드 자료 찾는 중", "소개글 흐름 잡는 중", "본문 쓰는 중", "문장 다듬는 중"],
            result: "실크로드 소개글을 다 썼어요. 장안에서 로마까지 이어진 길과 오간 물건, 사람 이야기를 세 문단에 담았어요."),
        Job(title: "슬라이드 개요 정리", teammate: kodi.id,
            steps: ["슬라이드 흐름 짜는 중", "장별 제목 정리하는 중", "핵심 문장 고르는 중"],
            result: "슬라이드 개요를 정리했어요. 표지, 길의 시작, 오간 물건, 문화 교류, 마무리까지 다섯 장이에요."),
    ]

    /// What Aris says when it hands the two jobs out (the real line).
    static var answer: String { ArisHandoffLine.line(["Claude Code", kodi.name], korean: true) }

    /// Words every 0.32 s from 0.5 s; the jobs' steps every 3.2 s (Claude Code) and 3.6 s (코디), each done after its
    /// last step; the jobs gone 10 s after the last one finished (home, the pill's 끝났어요 and its flash all over).
    static func cues() -> [ArisAdDemoCue<ArisTeamDemoStep>] {
        var cues: [ArisAdDemoCue<ArisTeamDemoStep>] = [.init(at: 0, step: .listen)]
        let words = prompt.split(separator: " ").map(String.init)
        for index in words.indices {
            cues.append(.init(at: 0.5 + 0.32 * Double(index), step: .hear(words[...index].joined(separator: " "))))
        }
        let think = 0.5 + 0.32 * Double(words.count) + 0.5
        let handOut = think + 1.4
        cues += [.init(at: think, step: .think), .init(at: handOut, step: .dispatch), .init(at: handOut, step: .reply(answer))]
        var last = handOut
        for (index, job) in jobs.enumerated() {
            let every = index == 0 ? 3.2 : 3.6
            let first = handOut + 0.5 + 0.4 * Double(index)
            for (n, step) in job.steps.enumerated() { cues.append(.init(at: first + every * Double(n), step: .progress(job: index, step))) }
            let done = first + every * Double(job.steps.count)
            cues.append(.init(at: done, step: .finish(job: index)))
            last = max(last, done)
        }
        cues.append(.init(at: handOut + 1.8, step: .closeTurn))
        cues.append(.init(at: last + 10, step: .clear))
        return cues.sorted { $0.at < $1.at }
    }
}

/// Where the two figures perch: real windows when there are some (TextEdit's first, front to back, then any other
/// app's), else fixed points on the notch display, as stand-in windows only the demo knows (CG coordinates).
enum ArisTeamDemoSeats {
    /// A window the list showed (CG coordinates, front to back).
    struct Window: Equatable {
        let pid: Int32
        let number: Int
        let bundleId: String?
        let frame: CGRect
    }

    enum Seat: Equatable {
        case window(pid: Int32, number: Int)
        /// A stand-in window at a fixed place: no process has it, nothing is drawn for it.
        case fixed(number: Int, frame: CGRect)
    }

    /// No process has this id: a stand-in window's owner.
    static let fixedPid = Int32.max
    static let fixedNumberBase = 0x7FFF_FF00
    static let minimumSize = CGSize(width: 240, height: 160)
    static let fixedSize = CGSize(width: 560, height: 380)

    static func isFixed(pid: Int32, number: Int) -> Bool {
        pid == fixedPid && (fixedNumberBase..<fixedNumberBase + 16).contains(number)
    }

    /// `count` seats on `screen` (CG coordinates), never on a window of `own` (Aris itself).
    static func pick(_ windows: [Window], screen: CGRect, own: Int32, count: Int = 2) -> [Seat] {
        let usable = windows.filter { window in
            window.pid != own && window.frame.width >= minimumSize.width && window.frame.height >= minimumSize.height
                && overlap(window.frame, screen) >= 0.6
        }
        let ordered = usable.filter { $0.bundleId == "com.apple.TextEdit" } + usable.filter { $0.bundleId != "com.apple.TextEdit" }
        var seats: [Seat] = []
        var taken: Set<Int> = []
        for window in ordered where seats.count < count && taken.insert(window.number).inserted {
            seats.append(.window(pid: window.pid, number: window.number))
        }
        let fixed = fixedFrames(screen: screen)
        var index = 0
        while seats.count < count {
            seats.append(.fixed(number: fixedNumberBase + index, frame: fixed[index % fixed.count]))
            index += 1
        }
        return seats
    }

    /// Two stand-in windows a twelfth in from the display's sides, a third of the way down.
    static func fixedFrames(screen: CGRect) -> [CGRect] {
        let w = min(fixedSize.width, screen.width * 0.36), h = min(fixedSize.height, screen.height * 0.45)
        let y = screen.minY + screen.height * 0.3
        return [CGRect(x: screen.minX + screen.width / 12, y: y, width: w, height: h),
                CGRect(x: screen.maxX - screen.width / 12 - w, y: y, width: w, height: h)]
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull, a.width > 0, a.height > 0 else { return 0 }
        return (i.width * i.height) / (a.width * a.height)
    }
}

// MARK: - dictation-demo

enum ArisDictationDemoStep: Equatable {
    case listen
    case hear(String)
    /// Let go: the words, the dropped ones struck through, while they are tidied.
    case clean(String)
    /// "넣었어요": shown as typed (nothing is typed anywhere).
    case typed(String)
    case close
}

enum ArisDictationDemoScript {
    /// A word every 0.24 s plus 0.045 s a letter (at most 0.6 s), 0.25 s more after a comma or a stop: about how fast
    /// the recognizer's words come for Korean.
    static func cues(_ text: String) -> [ArisAdDemoCue<ArisDictationDemoStep>] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var cues: [ArisAdDemoCue<ArisDictationDemoStep>] = [.init(at: 0, step: .listen)]
        var at = 0.7
        for index in words.indices {
            cues.append(.init(at: at, step: .hear(words[...index].joined(separator: " "))))
            let word = words[index]
            at += min(0.6, 0.24 + 0.045 * Double(word.count)) + (word.last.map { ",.?!".contains($0) } == true ? 0.25 : 0)
        }
        let clean = at + 0.6
        let typed = clean + 0.8
        // The real card's linger after 넣었어요 (ArisController.dictationLinger).
        return cues + [.init(at: clean, step: .clean(text)), .init(at: typed, step: .typed(ArisDictationCleaner.clean(text, endStop: false))),
                       .init(at: typed + 1.2, step: .close)]
    }
}

// MARK: - circle-demo

enum ArisCircleDemoStep: Equatable {
    /// ⌥⇧ down: the turn listens and the ink session begins (hands-free: the ink never takes a click).
    case begin
    case hear(String)
    /// The talking stops: the ink session ends, the turn thinks.
    case end
    case work(String)
    case write(String)
    case final(String)
    case close
}

enum ArisCircleDemoScript {
    static let question = "이거 뭐야?"
    static let answer = "주간 매출 차트예요. 화요일이 가장 높고(1,240만 원), 금요일에 떨어졌어요. 전체적으로는 지난주보다 8% 늘었어요."
    /// The pointer rests, glides to the loop's start, draws it, drifts off; the session ends at `endAt`.
    static let restUntil = 0.45
    static let glideUntil = 0.95
    static let loopUntil = 2.3
    static let driftUntil = 2.65
    static let endAt = 3.0

    /// The default rect: a 520 × 300 chart in the middle of a display `size` points.
    static func defaultRect(display size: CGSize) -> CGRect {
        let w = min(520, size.width * 0.5), h = min(300, size.height * 0.4)
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    static func cues() -> [ArisAdDemoCue<ArisCircleDemoStep>] {
        var cues: [ArisAdDemoCue<ArisCircleDemoStep>] = [.init(at: 0, step: .begin), .init(at: 1.1, step: .hear("이거")),
                                                       .init(at: 1.7, step: .hear(question)), .init(at: endAt, step: .end),
                                                       .init(at: endAt + 0.35, step: .work("화면 보는 중"))]
        // Two to four letters every 40 ms from 4.6 s, as a model streams Korean; then the whole answer.
        let sizes = [3, 2, 4, 3, 2]
        var written = "", rest = Substring(answer), at = 4.6, n = 0
        while !rest.isEmpty {
            written += rest.prefix(sizes[n % sizes.count])
            rest = rest.dropFirst(sizes[n % sizes.count])
            cues.append(.init(at: at, step: .write(written)))
            at += 0.04
            n += 1
        }
        cues.append(.init(at: at, step: .final(answer)))
        // The real turn's linger after the answer (ArisController.lingerAfterAnswer); the notch then waits its reading time.
        cues.append(.init(at: at + 1.5, step: .close))
        return cues
    }
}

/// The scripted pointer around `rect` (top-left points on a display whose frame is `screen`, Cocoa global points):
/// where the ink's pen is `t` seconds in, in Cocoa global points. The real cursor never moves.
struct ArisCirclePath {
    let rect: CGRect
    let screen: CGRect

    /// Top-left display points to Cocoa global points.
    func global(_ p: CGPoint) -> CGPoint { CGPoint(x: screen.minX + p.x, y: screen.maxY - p.y) }

    private var centre: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
    /// Wide enough that the loop clears the rect's edges and cuts its corners only a little, as a hand does.
    private var radii: CGSize { CGSize(width: rect.width / 2 * 1.25 + 14, height: rect.height / 2 * 1.25 + 14) }
    private static let startAngle = -2.4
    private static let laps = 1.06

    /// A hand-drawn loop: one lap and a little more, slightly uneven.
    func loop(_ u: Double) -> CGPoint {
        let a = Self.startAngle + Self.laps * 2 * .pi * Self.ease(u), w = 1 + 0.035 * sin(3 * a)
        return CGPoint(x: centre.x + radii.width * w * cos(a), y: centre.y + radii.height * w * sin(a))
    }

    /// Below and right of the loop, where the pen comes from.
    var rest: CGPoint { CGPoint(x: rect.maxX + 60, y: rect.maxY + 70) }

    func point(at t: Double) -> CGPoint {
        typealias S = ArisCircleDemoScript
        let local: CGPoint
        if t < S.restUntil {
            local = rest
        } else if t < S.glideUntil {
            local = Self.mix(rest, loop(0), Self.ease((t - S.restUntil) / (S.glideUntil - S.restUntil)))
        } else if t < S.loopUntil {
            local = loop((t - S.glideUntil) / (S.loopUntil - S.glideUntil))
        } else {
            let end = loop(1), off = CGPoint(x: end.x + 26, y: end.y + 18)
            local = Self.mix(end, off, Self.ease(min(1, (t - S.loopUntil) / (S.driftUntil - S.loopUntil))))
        }
        return global(local)
    }

    private static func ease(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }
    private static func mix(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
    }
}

/// The circle demo's capture: it looks up no window and takes no picture. Every loop counts as on an empty desk (so it
/// seals, as on a window that may be seen) and its shot as made; nothing is kept but the badge numbers.
@MainActor
final class ArisAdDemoCapture: ArisGestureCapturing {
    private(set) var kept: [Int] = []
    private(set) var finalized = false

    func strokeStarted(on screen: ArisGestureScreen) {}

    func pickWindow(captureId: Int, for gesture: ArisGesture, on screen: ArisGestureScreen, handsFree: Bool,
                    done: @escaping (ArisWindowHit?) -> Void) {
        done(nil)
    }

    func capture(_ request: ArisGestureCaptureRequest, done: @escaping (Bool) -> Void) { done(true) }
    func keep(captureId: Int, badge: Int) { kept.append(badge) }
    func drop(captureId: Int, reason: String) {}
    func markFramesStale() {}
    func finalize(strokes: [UInt32: [[ArisGesturePoint]]], handsFree: Bool) { finalized = true }
    func abort() {}
}

// MARK: - the 사용량 tab while side-demo is on

/// While side-demo is on, the 사용량 tab hides who is signed in and every amount of money.
enum ArisUsageMask {
    static let account = "•••@•••"
    static let money = "$•••"

    static func account(_ text: String, masked: Bool) -> String { masked ? account : text }
    static func usd(_ amount: Double, masked: Bool) -> String { masked ? money : ArisUsageFormat.usd(amount) }
    /// The chart's peak label ("$12").
    static func peak(_ amount: Double, masked: Bool) -> String { masked ? money : "$\(Int(amount.rounded()))" }
}
