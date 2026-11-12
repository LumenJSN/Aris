//
//  ArisDesktopEngine.swift
//  aris-agent
//
//  Computer use for every brain: `aris-tools desktop …` (POST /desktop-tool), agy's relayed `desktop …` lines and the API
//  brain's desktop functions all end here, in the agent: one controller, Peekaboo underneath. A call's app is the one
//  Aris resolved (by name or bundle id for --app, or from its own record of the look a ref came from: never the
//  brain's say-so), the gate decides (ArisDesktopGate: run, the read judge, the user's card, or never), and the controller
//  does it (ArisDesktopController: an exact window, a fresh look before acting, a read-back after). What comes back is
//  filtered for privacy and fenced as that app's own words. The window being worked on gets the overlay and a line in
//  the notch. A turn takes at most `maxSteps` calls; a longer task goes to a teammate job.
//

import CoreGraphics
import Foundation

/// The turn a desktop call belongs to, as the engine sees it (the runner's, the relay's, or a fake in the tests).
protocol ArisDesktopTurn: ArisMCPTurn {
    var brain: ArisBrain { get }
    var ledger: ArisComputerUseLedger { get }
    /// The taint as computer use in this app (ArisDesktopTarget.readKey) sees it.
    func taint(forApp app: String) -> ArisTaint
    /// This app's window is about to come in (before Peekaboo runs).
    func markAppRead(_ app: String)
    /// The overlay and the notch's line for the window being worked on.
    func operating(_ target: ArisOperatingTarget)
    /// Counts one more desktop call in this turn; how many so far.
    func desktopStep() -> Int
    /// The turn is still under way: an answer (the user's card, the read judge) that comes after it ended is a no (M5).
    var live: Bool { get }
    /// The user's own words for the turn, and whether it is a critical one (QA BUG-15: their words typed into a safe app).
    var request: String { get }
    var critical: Bool { get }
}

extension ArisDesktopTurn {
    /// `request` has no default on purpose (audit desk-5): agy's relay turn kept the user's words private, this default
    /// quietly stood in for them, and the engine never saw what he asked. A turn must say them itself.
    var critical: Bool { true }
}

/// What the user's card showed, held against the window when the action runs (I1, I4): the window's title, and in a sending
/// app what the field holds (its raw value) and whether the action sends it. Anything different then, and nothing is done.
struct ArisDesktopBasis: Equatable {
    var title: String? = nil
    /// What the field held, for a send or a text action: held to it.
    var composer: String? = nil
    var send = false
    /// What the field held for any other action in a sending app: only shown.
    var shownField: String? = nil
    /// The message field gives no value (KakaoTalk's): the text is typed on the exact-text card and confirmed from the
    /// chat read back (re-review 4).
    var blindField = false
    /// A send from such a field: the text Aris itself typed there on the user's card this turn, which the window showed
    /// then and must still show when the send runs (audit desk-4). The card says it, and that the field can't be read.
    var blindSend: String? = nil
    /// Return pressed in a search field (a search, not a send): the focus must still be that field when it runs.
    var searchFocus: String? = nil
    /// A paste in a sending app: the clipboard's text as the user's card showed it, which the clipboard must still hold
    /// when the keys go (audit gate-19: a card, not a refusal).
    var paste: String? = nil
    /// System Settings: the pane's tier when it was decided (a safe pane ran without a card; anything else then asks).
    var settingsPane: ArisSettingsPane? = nil
    /// The window `title` was read from: the pinned window, held by its id once pinned (an app may rename it).
    var window: Int? = nil
    /// The app in front when the user's card went up: put back in front after the action, as the card says (not the app the
    /// card's yes handed activation to).
    var frontBefore: ArisCardTarget? = nil
    /// The field the card was about, as it was then: a renamed window is held only with this very field in it.
    var field: ArisDesktopElement? = nil
    /// The user said yes on this action's own card, which said the window may come forward: the raise and the focus guard
    /// then run with no second card (QA BUG-47 retest: one action, one card). Never in a job, never for a sending app.
    var cardYes = false
    /// A batch's step: the notch's line says which of how many ("… · 2/4", ArisStepLine). Nil for a single call.
    var step: ArisStepLine.Step? = nil
}

/// One flag a session sets once (a card it asked already).
final class ArisDesktopFlag {
    var isSet = false
}

/// The app in front when a session's card went up, as the process it was.
final class ArisDesktopFront {
    var target: ArisCardTarget?
    /// The session's last consent card closed with no answer from the user.
    var unanswered = false
}

/// The running (and installed) apps, as the engine resolves them.
protocol ArisDesktopApps {
    /// The one running app with this name or bundle id; nil for none or several.
    func resolve(_ name: String) -> ArisDesktopTarget?
    /// An installed app (for `app launch` and `dock launch`): running or not; nil when it isn't one.
    func installed(_ name: String) -> ArisDesktopTarget?
    /// The Dock itself (for `dock list`).
    func dock() -> ArisDesktopTarget?
    /// The app is still the same running process.
    func isRunning(_ target: ArisDesktopTarget) -> Bool
    /// A password field (secure event input) is active somewhere.
    var secureInput: Bool { get }
    /// The folder a file browser's window (Finder) shows, by its window id; nil when it can't be read.
    func shownPath(_ target: ArisDesktopTarget, window: Int?) -> String?
    /// The process in front now (where keys typed for real go), and the frame of a process's focused window
    /// (Accessibility, the window server's terms); nil when either can't be told.
    func frontmostPid() -> Int32?
    func focusedWindowFrame(pid: Int32) -> CGRect?
    /// Seconds since the last key went down on this Mac (anyone's: the user's typing), for the raise's last check.
    func secondsSinceKeyDown() -> Double
    /// Raises the process's window at `frame` and makes it main (Accessibility's AXRaise and AXMain).
    func raiseWindow(pid: Int32, frame: CGRect)
    /// The process is Aris itself.
    func isAris(pid: Int32) -> Bool
    /// The process's focused element sits in web content (an AXWebArea above it); nil when that can't be read.
    func focusedInWebArea(pid: Int32) -> Bool?
    /// The process as a card names it (pid, bundle id, start time), to tell it from a reused pid; nil when unknown.
    func identity(pid: Int32) -> ArisCardTarget?
    /// The clipboard's change count (it moves on every copy or cut); nil when it can't be read.
    func clipboardChanges() -> Int?
    /// The clipboard's plain text, read only for a paste in a messaging app (the user's card shows it; a brain never gets
    /// it); nil when it holds none.
    func clipboardText() -> String?
    /// Whether the document in the process's window at `frame` has unsaved changes (Accessibility's AXModified); nil
    /// when the window has no such mark or it can't be read.
    func documentEdited(pid: Int32, frame: CGRect) -> Bool?
}

/// One on-screen window of a process (CoreGraphics' number, its frame in global points, top-left origin).
struct ArisDesktopWindow: Equatable {
    let id: Int
    let frame: CGRect
    /// Its title as the window server has it (nil when it can't be read).
    var title: String? = nil
}

/// Before any key, text or press goes out for real (foreground), the app the card named must be the one in front and
/// the window the card named its key window; else nothing is sent (QA BUG-53: a delete pressed "for real" must never
/// land in whatever app is in front, a browser on a checkout page). Unknown counts as no. Pure.
extension ArisDesktopApps {
    func raiseWindow(pid: Int32, frame: CGRect) {}
    func isAris(pid: Int32) -> Bool { false }
    func focusedInWebArea(pid: Int32) -> Bool? { nil }
    func identity(pid: Int32) -> ArisCardTarget? { nil }
    func clipboardChanges() -> Int? { nil }
    func clipboardText() -> String? { nil }
    func documentEdited(pid: Int32, frame: CGRect) -> Bool? { nil }
}

enum ArisDesktopFocus {
    /// Apps with one document per window that rename it themselves (TextEdit names "무제" from its first line, QA retest
    /// on 0c370061; Preview's single document). Tabbed and web apps (Obsidian, Notion, Finder, Pages, a PWA) keep one
    /// window id across documents, so a rename there may be another document (security review of b7997da3).
    static let renamesItself: Set<String> = ["com.apple.TextEdit", "com.apple.Preview"]

    /// A look of the same pinned window under another title is still the window the card named only in such an app,
    /// installed and signed as itself and not a sending one, and only with the very same field in it: the same control
    /// in the same place, holding what it held (or that, added to). Anything else needs the exact title. Pure.
    /// Never in a window with tabs (an AXTabGroup: TextEdit's window tabs share one window id), and never from an
    /// empty field: any text starts with "", so another tab with text would pass (re-review of 244e4893); an empty
    /// field's window keeps its exact title.
    static func renameHolds(bundle: String?, known: Bool, sending: Bool, sameWindow: Bool, tabbed: Bool, was: ArisDesktopElement, now: ArisDesktopElement) -> Bool {
        guard sameWindow, !tabbed, let bundle, renamesItself.contains(bundle), known, !sending else { return false }
        guard was.role == now.role, (was.id == now.id || was.sameControl(now)), ArisDesktopVerify.samePlace(was, now) else { return false }
        guard let before = was.rawValue, let after = now.rawValue, !was.rawCapped, !now.rawCapped, !before.isEmpty else { return false }
        return after == before || after.hasPrefix(before)
    }

    /// What a batch holds its next steps to after its own text step landed (audit desk-6: TextEdit names an untitled
    /// document from the first line typed into it, and the batch's next step then failed as "the window's title
    /// changed"). Only in an app that renames its one document itself (installed and signed as itself, not a sending
    /// one), in the same pinned window with no tabs, and only with the field read back holding text: the steps after are
    /// held to that very field (renameHolds, with all its limits) and to the title the window has now that the text is
    /// in it. Anything else keeps the basis as it was. Pure.
    static func afterOwnText(_ basis: ArisDesktopBasis, look: ArisDesktopObservation, field: ArisDesktopElement, target: ArisDesktopTarget) -> ArisDesktopBasis {
        guard let bundle = target.bundle, renamesItself.contains(bundle), target.known, !target.sending, basis.window == look.window, !hasTabs(look),
              let raw = field.rawValue, !raw.isEmpty, !field.rawCapped, !field.isSecure else { return basis }
        var next = basis
        next.field = field
        next.title = look.title
        return next
    }

    /// The look shows a tab group (window tabs: several documents under one window id).
    static func hasTabs(_ look: ArisDesktopObservation) -> Bool { look.elements.contains { $0.axRole == "AXTabGroup" || $0.role == "tabGroup" } }

    /// The app to put back in front after an action that brought the target forward: the one in front when the card
    /// went up, else the one in front when the action began; never the target itself or Aris (whose card click and
    /// yield made them front). Pure.
    /// `beforeCard`: only when that pid is still the same process (its bundle and start as when the card went up).
    static func restoreFront(beforeCard: Int32?, atAction: Int32?, target: Int32, isAris: (Int32) -> Bool) -> Int32? {
        [beforeCard, atAction].compactMap { $0 }.first { $0 > 0 && $0 != target && !isAris($0) }
    }

    /// `windows`: the target's windows now, from the window server. The focused window is told by its id, not its frame
    /// alone (security review of BUG-53: two windows can share a frame): of the target's windows at the focused frame,
    /// exactly one may be there, and it must be the card's.
    static func keysMayGo(frontmost: Int32?, target: Int32, focused: CGRect?, window: ArisDesktopWindow, windows: [ArisDesktopWindow]) -> Bool {
        guard let frontmost, frontmost == target, let focused else { return false }
        let there = windows.filter { ArisWindowTitles.same($0.frame, focused) }.map(\.id)
        return there == [window.id]
    }

    /// The commands that post keys or clicks to whatever is in front ("--foreground"): each runs only after
    /// `keysReachTarget`. `app launch` brings an app up but sends it nothing, so it isn't one (desktop-tests enumerate them).
    static let unguardedForeground: Set<String> = ["app launch"]

    static let refusalLine = "The user said yes, but the window couldn't be brought to the front (another app or window stayed in front), so " +
        "nothing was typed or pressed. Tell the user exactly that, e.g. “허락하셨지만 창을 앞으로 가져오지 못해서 입력하지 못했어요” (with the window's name), " +
        "or for a request in English “You said yes, but I couldn't bring the window to the front, so nothing was typed”; " +
        "never that they didn't answer."
}

/// The windows of a process, front to back (only real ones: layer 0, not tiny).
protocol ArisDesktopWindows {
    func windows(of pid: Int32) -> [ArisDesktopWindow]
    /// The topmost on-screen window at a global point (any level, Aris's own overlay left out): who a real pointer
    /// click there would reach (I10).
    func topWindow(at point: CGPoint) -> (pid: Int32, id: Int)?
    /// A sign-in, password or permission prompt's window on screen at any level (ArisRiskPolicy.authPrompts): its
    /// owner's name (I7).
    func promptOnScreen() -> String?
    /// One of Aris's own windows that takes clicks (the notch, a side panel) holds the point: a real click there would
    /// press Aris itself (security review).
    func hitsAris(_ point: CGPoint) -> Bool
}

extension ArisDesktopWindows {
    func hitsAris(_ point: CGPoint) -> Bool { false }
}

/// Who a real click at a point reaches, read from the window server's list (front to back). Pure.
enum ArisPointerHit {
    /// The system's own processes, by pid (never by a window's owner name, which any process can carry): the Dock,
    /// the window server, the window manager.
    struct System: Equatable {
        var dock: Int32? = nil
        var others: Set<Int32> = []
        var all: Set<Int32> { others.union(dock.map { [$0] } ?? []) }
    }

    /// Whether the point is inside any of `arisWindows` (Aris's windows that take clicks).
    static func hitsAris(_ point: CGPoint, arisWindows: [CGRect]) -> Bool {
        arisWindows.contains { $0.contains(point) }
    }

    /// Aris's windows that take clicks, from the window server's list: its processes' windows above the normal level
    /// (the notch, the side panels), leaving out the click-through ones: the operating overlay (normal level) and the
    /// full-display overlays (a display's whole frame).
    static func arisWindows(in list: [[String: Any]], aris: Set<Int32>, displays: [CGRect]) -> [CGRect] {
        list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, aris.contains(pid), (info[kCGWindowLayer as String] as? Int ?? 0) > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any], let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  !displays.contains(where: { ArisWindowTitles.same($0, frame) }) else { return nil }
            return frame
        }
    }

    /// The Dock's own level (kCGDockWindowLevel): its full-display window there passes clicks through.
    static let dockLevel = 20

    /// The first visible window (front to back) whose frame holds the point, Aris's own left out, and of the system's
    /// only the click-through layer over a whole display: the Dock's at its own level, or one that shows nothing (alpha
    /// 0). Launchpad, Mission Control and the Dock's menus are other windows, and count (bench canvas_launch).
    static func topWindow(at point: CGPoint, in list: [[String: Any]], skipping: Set<Int32>, displays: [CGRect] = [], system: System = System()) -> (pid: Int32, id: Int)? {
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, !skipping.contains(pid),
                  let bounds = info[kCGWindowBounds as String] as? [String: Any], let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.contains(point), let number = info[kCGWindowNumber as String] as? Int else { continue }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            if alpha <= 0 { continue }
            let wholeDisplay = displays.contains { $0.insetBy(dx: -1, dy: -1).contains(frame) && frame.width >= $0.width - 1 && frame.height >= $0.height - 1 }
            if wholeDisplay, pid == system.dock, info[kCGWindowLayer as String] as? Int == dockLevel { continue }
            return (pid, number)
        }
        return nil
    }
}

/// aris-agent's grants, which Peekaboo runs under (it is aris-agent's child).
protocol ArisDesktopAccess {
    var trusted: Bool { get }
    /// Screen Recording: only for a look at the window's pixels (`see --ocr`, click-at).
    var screenRecording: Bool { get }
    /// Opens System Settings at Accessibility (or Screen Recording), once per agent run each.
    func guide()
    func guideScreen()
}

/// The pointer and the front app: kept before a real (foreground) click or typing the user consented to, put back after.
protocol ArisDesktopPointer {
    func save() -> ArisDesktopPointerState
    func restore(_ state: ArisDesktopPointerState)
}

struct ArisDesktopPointerState: Equatable {
    var location: CGPoint? = nil
    var frontmost: Int32? = nil
}

/// A vision brain's pick in a window's annotated screenshot: one of the marks drawn on it, or a point in its pixels.
enum ArisDesktopPick: Equatable {
    case mark(String)
    case point(CGPoint)
}

protocol ArisDesktopVision {
    /// Where in the screenshot (PNG) `target` is; nil when it can't tell (or there is no vision brain).
    func locate(png: Data, width: Int, height: Int, target: String, marks: [String]) -> ArisDesktopPick?
    /// A brain that can look at a picture is set up for a turn on `brain` (that brain itself, or another).
    func available(for brain: ArisBrain) -> Bool
    /// The same look, by the brain the turn runs on when that one can, else another that can (audit desk-9).
    func locate(png: Data, width: Int, height: Int, target: String, marks: [String], brain: ArisBrain) -> ArisDesktopPick?
}

extension ArisDesktopVision {
    func available(for brain: ArisBrain) -> Bool { true }
    func locate(png: Data, width: Int, height: Int, target: String, marks: [String], brain: ArisBrain) -> ArisDesktopPick? {
        locate(png: png, width: width, height: height, target: target, marks: marks)
    }
}

/// Text on a window's screenshot (Apple Vision): each piece with its box in the image's own unit square (top-left origin).
protocol ArisDesktopTextReader {
    func read(png: Data) -> [(text: String, box: CGRect)]
}

final class ArisDesktopEngine {
    let installer: ArisDesktopInstaller
    let apps: ArisDesktopApps
    let runner: ArisDesktopRunning
    let access: ArisDesktopAccess
    let windows: ArisDesktopWindows
    let pointer: ArisDesktopPointer
    let vision: ArisDesktopVision
    let reader: ArisDesktopTextReader
    let identity: ArisDesktopIdentity
    let tools: String
    /// The computer-use engine in force (ArisComputerEngineChoice): Peekaboo unless the user picked Codex and has it.
    let computerEngine: () -> ArisComputerEngine
    /// One Peekaboo run's time limit.
    static let runTimeout: TimeInterval = 25
    /// Calls one conversation turn may take; a background job may take more. Past it, a teammate job.
    static let maxSteps = 40
    static let maxJobSteps = 150

    init(installer: ArisDesktopInstaller, apps: ArisDesktopApps, runner: ArisDesktopRunning = ArisDesktopProcess(), access: ArisDesktopAccess,
         windows: ArisDesktopWindows, pointer: ArisDesktopPointer, vision: ArisDesktopVision, reader: ArisDesktopTextReader,
         identity: ArisDesktopIdentity, tools: String, computerEngine: @escaping () -> ArisComputerEngine = { .peekaboo }) {
        self.installer = installer
        self.apps = apps
        self.runner = runner
        self.access = access
        self.windows = windows
        self.pointer = pointer
        self.vision = vision
        self.reader = reader
        self.identity = identity
        self.tools = tools
        self.computerEngine = computerEngine
    }

    /// The Korean-speaking user's lines. The lists are named as this macOS shows them (ArisFix.Pane.title).
    static var accessLine: String {
        let list = ArisFix.Pane.accessibility.title(english: true), korean = ArisFix.Pane.accessibility.title(english: false)
        return "Aris doesn't have \(list) yet, so Aris can't see or press inside apps. System Settings is open at Privacy & Security › \(list). Tell the user, in Korean, in one sentence: \"앱 안을 보고 누르려면 Aris에 \(korean) 권한이 필요해요. 방금 열린 시스템 설정 › 개인정보 보호 및 보안 › \(korean)에서 Aris를 켜 주세요 (한 번만).\""
    }
    static var screenLine: String {
        "Looking at the window's pixels needs Screen Recording for Aris (only for --ocr and click-at; everything else works without it). System Settings is open at it. Tell the user, in Korean, in one sentence: \"화면을 보고 누르려면 Aris에 화면 기록 권한이 필요해요. 방금 열린 시스템 설정 › 개인정보 보호 및 보안 › \(ArisFix.Pane.screen.title(english: false))에서 Aris를 켜 주세요.\""
    }
    /// click-at with no brain that can look at a picture set up: said before any card (audit desk-9).
    static func noVisionLine(app: String) -> String {
        "click-at needs an AI that can look at a picture, and none is set up on this Mac (Claude Code installed, or an API model that takes images), " +
            "so nothing was clicked and the user wasn't asked. `desktop see --app \"\(app)\" --ocr` lists the text on the window with boxes: click one of " +
            "its marks instead. If that isn't enough, tell the user plainly that clicking by looking at the window needs Claude Code or an API model that sees images."
    }
    /// The same three lines for a turn whose request is English (audit desk-11): the user's language, not "in Korean".
    static func accessLine(english: Bool) -> String { english ? ArisDesktopCopy.accessLine : accessLine }
    static func screenLine(english: Bool) -> String { english ? ArisDesktopCopy.screenLine : screenLine }
    static func blindLine(english: Bool) -> String { english ? ArisDesktopCopy.blindLine : blindLine }
    static let notOursLine = "That ref isn't from a look Aris took in this conversation. Look first: `desktop see --app \"<App>\"`, then use its refs."
    static let quitLine = "That app quit or restarted since that look. Look again with `desktop see`."
    static let noLine = "the user said no (or didn't answer), so it wasn't done. Don't try it another way now. A later request in a new turn gets a new card."

    /// The card closed with no answer from the user: never worded as their no (QA live on 827cfdb4: "알겠어요, … 입력하지 않을게요").
    static let unansweredLine = "the user didn't answer the card in time, so it wasn't done. Don't try it another way now. A later request in a new turn gets a new card. " +
        "Say exactly that (e.g. “카드에 답이 없어서 입력하지 않았어요”, or for a request in English “The card wasn't answered, so I didn't type it”), " +
        "never “알겠어요” or “All right” as if he said no."

    /// What a card's answer that isn't a yes says.
    static func notYesLine(_ answer: ArisMCPAnswer) -> String { answer == .unanswered ? unansweredLine : noLine }

    /// The engine's own reason for a result that wasn't done: its first line, after the outside-text wrapper (for the
    /// audit and QA's log: which check stopped it).
    static func reason(_ output: String) -> String {
        var body = Substring(output)
        if let head = body.range(of: #"^\[outside text from [^\n]*\]\n(The tool reported an error:\n)?"#, options: .regularExpression) {
            body = body[head.upperBound...]
        }
        return String(body.prefix { $0 != "\n" }.prefix(300))
    }

    /// After an action the user's card said yes to, worked or not: the app that was in front when the card went up comes back
    /// if the yield (or the action) left the target in front (QA live on 827cfdb4: TextEdit stayed in front after a
    /// failed step). Only that very process (pid, bundle, start), never Aris.
    func putBack(_ before: ArisCardTarget?, target: ArisDesktopTarget) {
        guard let before, before.pid != target.pid, apps.frontmostPid() == target.pid, !apps.isAris(pid: before.pid),
              apps.identity(pid: before.pid).map({ $0.matches(bundle: before.bundle, started: before.started) }) == true else { return }
        pointer.restore(ArisDesktopPointerState(location: nil, frontmost: before.pid))
    }

    /// The user's own no: the engine's result itself begins with `noLine` (bare, inside the outside-text wrapper, or after
    /// the type's NOT TYPED lead), never the words showing up in window text rendered after it. Pure.
    static func isDecline(_ output: String) -> Bool {
        var body = Substring(output)
        if let head = body.range(of: #"^\[outside text from [^\n]*\]\n(The tool reported an error:\n)?"#, options: .regularExpression) {
            body = body[head.upperBound...]
        }
        let typed = ArisDesktopSession.notTypedLead + " "
        if body.hasPrefix(typed) { body = body.dropFirst(typed.count) }
        return body.hasPrefix(noLine)
    }
    static let lateLine = "The answer came after this turn ended, so nothing was done."
    static let codexEngineLine = "Codex's own computer use is the one picked: work the app with it (cua_repl), not with desktop actions."
    static let unreadSendLine = "Refused: Aris couldn't read exactly what this would send (the message field, in full), so it won't ask the user to send it blind. Look again, or ask the user to send it."
    static let unreadLine = "Refused: Aris couldn't read the window before asking the user. Look again with `desktop see`."
    static let blindLine = "Refused: Aris can read neither this app's message field nor its chat, so it won't type there blind. Tell the user, in Korean, in one sentence: \"이 앱은 입력 칸도 대화 내용도 읽을 수 없어서 대신 입력하지 않았어요. 직접 입력해 주세요.\""
    /// How near (points, frame to frame) an unnamed button must be to the message field to be its send button.
    static let sendReach: CGFloat = 60
    static func stepsLine(job: Bool) -> String {
        job ? "This job has made \(maxJobSteps) desktop calls. Stop here and report what's done and what's left."
            : "That's \(maxSteps) desktop calls in one turn: a long task. Stop and hand the rest to a teammate job (the jobs block), saying what's done and what's left."
    }

    /// One desktop call; `done` gets what aris-tools prints. Blocks its caller (never the agent's server queue).
    func handle(_ words: [String], text: String?, positionalText: Bool = false, turn: ArisDesktopTurn, done: @escaping (ArisMCPOutcome) -> Void) {
        let asked: ArisDesktopRequest
        switch ArisDesktopWords.parse(words, text: text, positionalText: positionalText) {
        case .failure(let usage): return done(.failed(usage.text))
        case .success(let parsed): asked = parsed
        }
        if asked.verb == .batch { return handleBatch(asked, turn: turn, done: done) }
        guard turn.desktopStep() <= (turn.isTask ? Self.maxJobSteps : Self.maxSteps) else {
            turn.audit(["answer": "refused (step cap)", "action": "desktop \(asked.verb.rawValue)", "brain": turn.brainName])
            return done(.failed(Self.stepsLine(job: turn.isTask)))
        }
        let target: ArisDesktopTarget
        switch resolve(asked, turn: turn) {
        case .failure(let why): return done(.failed(why.text))
        case .success(let found): target = found
        }
        // Codex's own computer use picked: the Codex brain works apps with it, never with desktop's actions too (I14).
        if turn.brain == .codex, computerEngine() == .codex, asked.verb.kind == .action {
            turn.audit(["answer": "refused (Codex's own computer use is picked)", "action": "desktop \(asked.verb.rawValue)", "brain": turn.brainName])
            return done(.failed(Self.codexEngineLine))
        }
        let taint = turn.taint(forApp: target.readKey)
        // The window the user named, if their words name one of the app's windows: an action on a ref in another one is refused
        // (QA BUG-47 reopened), and with several windows and none named, no type runs without a card.
        let appWindows = windows.windows(of: target.pid)
        turn.ledger.noteTitles(appWindows.compactMap(\.title))
        let namedWindow = ArisWindowNaming.named(in: turn.request, windows: appWindows)
        if asked.verb.kind == .action, let named = namedWindow, let ref = asked.ref,
           let refWindow = turn.ledger.observation(ref.snapshot)?.window, refWindow != named.id {
            turn.audit(["answer": "refused (not the window the user named)", "action": "desktop \(asked.verb.rawValue)", "brain": turn.brainName])
            return done(.failed(ArisWindowNaming.wrongWindowLine(named: named.title ?? "", app: target.name)))
        }
        // A call with no ref works in the window it names, else the one the user named: never the front one while they named
        // another (audit desk-1). From here on the request carries that window's id.
        var aimed = asked
        switch ArisDesktopAim.decide(asked, named: namedWindow, windows: appWindows, app: target.name,
                                     isDialog: { turn.ledger.latestLook(window: $0)?.isDialog == true }) {
        case .asIs: break
        case .window(let id):
            aimed.window = id
            aimed.title = nil
        case .refuse(let why, let readsTitles):
            if readsTitles { turn.markAppRead(target.readKey) }
            turn.audit(["answer": "refused (not the window the user named, or no such window)", "action": "desktop \(asked.verb.rawValue)", "brain": turn.brainName])
            return done(.failed(why))
        }
        let request = aimed
        // A replace the user's words didn't ask for stops here, before any card (audit desk-3).
        if request.verb.kind == .action, let why = replaceRefusal(request, target: target, turn: turn) {
            turn.audit(["answer": "refused (would replace what the window holds)", "action": "desktop \(request.verb.rawValue)", "brain": turn.brainName])
            return done(.failed(why))
        }
        let source = request.ref.flatMap { turn.ledger.observation($0.snapshot) }
            ?? windows.windows(of: target.pid).first.flatMap { turn.ledger.latestLook(window: $0.id) }
        let pane = target.settings ? source?.settingsPane ?? .unknown : .unknown
        // Finder: the folder its window shows, against the protected places (file work goes to the file tools; this is
        // the screen way, kept to what can be told).
        let finderWindow = source?.window ?? windows.windows(of: target.pid).first?.id
        let shownPlace = { () -> ArisShownPlace in
            target.bundle == ArisShownPlace.finder && request.verb.kind == .action
                ? self.apps.shownPath(target, window: finderWindow).map(ArisShownPlace.path) ?? .unreadable : .notAFileBrowser
        }
        let place = shownPlace()
        // "이 문서 저장해 줘": their words point at the document in front, unless another app (not Aris) plainly is in front.
        let otherAppInFront = apps.frontmostPid().map { $0 != target.pid && !apps.isAris(pid: $0) } ?? false
        var context = ArisDesktopContext(taintForApp: taint, screen: turn.screen, handsFree: turn.handsFree, job: turn.isTask, relayed: turn.relayed,
                                         home: identity.home, settingsPane: pane, place: place, request: turn.request, critical: turn.critical,
                                         windowAmbiguous: appWindows.count > 1 && namedWindow == nil,
                                         userNamedApp: ArisDesktopGate.namesApp(turn.request, names: [target.name] + (target.bundle.map { [$0] + Array(ArisAppIdentity.names(ofBundle: $0)) } ?? [])
                                                                                                  + appWindows.compactMap(\.title)),
                                         pointsAtFrontDocument: request.verb == .dialogFile && !otherAppInFront && ArisDesktopGate.pointsAtDocument(turn.request))
        // A paste in a messaging app: the clipboard's text is read for the user's card and for nothing else.
        if target.sending, ArisDesktopGate.pastes(request) { context.clipboard = apps.clipboardText() }
        let remembered = target.memoryKey.map { turn.ledger.allows($0, tainted: taint != .none) } ?? false
        let element = request.ref.flatMap { turn.ledger.element($0) }
        let decision = ArisDesktopGate.decide(request, target: target, context: context, remembered: remembered, secureInput: apps.secureInput,
                                              element: element)
        let what = "desktop \(request.verb.rawValue) · \(target.name)"
        // What the card (or, with no card, the look the ref came from) showed: the action is held to it.
        let snapshotTitle = request.ref.flatMap { turn.ledger.observation($0.snapshot)?.title }
        switch decision {
        case .refuse(let why):
            turn.audit(["answer": "refused", "action": what, "brain": turn.brainName])
            done(.failed(why))
        case .run:
            turn.audit(["answer": remembered ? "ran (the user's yes for this app)" : "ran (\(request.verb.kind == .read ? "read" : "action"))", "action": what, "brain": turn.brainName])
            done(perform(request, target: target, turn: turn, basis: ArisDesktopBasis(title: snapshotTitle, settingsPane: pane,
                                                                                    window: request.ref.flatMap { turn.ledger.observation($0.snapshot)?.window })))
        case .judge:
            turn.judgeRead(Self.readCall(request, target: target)) { [weak self] verdict in
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let self else { return done(.failed(ArisReadGate.refusal(.undecided))) }
                    guard turn.live else {
                        turn.audit(["answer": "dropped (the judge answered after the turn ended)", "action": what, "brain": turn.brainName])
                        return done(.failed(Self.lateLine))
                    }
                    guard verdict.allowed else {
                        let why = verdict.why ?? .other
                        turn.audit(["answer": "refused by the read judge (\(why.rawValue))", "note": verdict.note, "action": what, "brain": turn.brainName])
                        turn.quiet(ArisReadGate.status(why))
                        return done(.failed(ArisReadGate.refusal(why)))
                    }
                    turn.audit(["answer": "ran (read, the judge allowed)", "action": what, "brain": turn.brainName])
                    done(self.perform(request, target: target, turn: turn))
                }
            }
        case .ask(let remember):
            // What the action can't do without is checked before the user is asked, never after their yes (audit desk-9: the
            // card went up, then "no vision brain" or the Screen Recording line).
            if let missing = missingBeforeCard(request, target: target, turn: turn) {
                turn.audit(["answer": "refused (\(missing.prefix(80)))", "action": what, "brain": turn.brainName])
                return done(.failed(missing))
            }
            var basis: ArisDesktopBasis
            switch cardBasis(request, target: target, element: element, turn: turn) {
            case .failure(let why):
                turn.audit(["answer": "refused (\(why.text.prefix(80)))", "action": what, "brain": turn.brainName])
                return done(.failed(why.text))
            case .success(let found): basis = found
            }
            basis.paste = context.clipboard
            // A file panel saves or opens the document in front: the card names it (QA: an unrelated document was saved).
            // Keys and a look-and-click say theirs too, even with no look at it yet (audit desk-1: no window line at all).
            let aimedTitle = request.window.flatMap { id in appWindows.first { $0.id == id } }?.title
            let shownWindow = basis.title ?? snapshotTitle ?? aimedTitle ?? ([.dialogFile, .press, .clickAt].contains(request.verb) ? appWindows.first?.title : nil)
            let card = ArisDesktopCard.card(request, target: target, element: element, window: shownWindow, composer: basis.composer ?? basis.shownField,
                                            send: basis.send, blindField: basis.blindField, blindSend: basis.blindSend, searchFocus: basis.searchFocus, paste: basis.paste,
                                            unnamedDocument: request.verb == .dialogFile && !context.namesDocument, remember: remember,
                                            wiped: target.memoryKey.map(turn.ledger.wasWiped) ?? false, mayRaise: !turn.isTask && !target.sending,
                                            english: ArisDesktopCopy.isEnglish(turn.request))
            turn.operating(operatingTarget(request, target: target, turn: turn))
            let frontBefore = apps.frontmostPid().flatMap(apps.identity)
            // A card whose yes may bring the window forward names its process: the app hands activation back to it.
            turn.ask(!turn.isTask && !target.sending ? card.aimed(pid: target.pid, bundle: target.bundle) : card) { [weak self] answer in
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let self else { return done(.failed(Self.noLine)) }
                    guard case .yes = answer else {
                        turn.audit(["answer": answer == .unanswered ? "unanswered" : "no", "action": what, "brain": turn.brainName])
                        return done(.failed(Self.notYesLine(answer)))
                    }
                    guard turn.live else {
                        turn.audit(["answer": "dropped (the yes came after the turn ended)", "action": what, "brain": turn.brainName])
                        return done(.failed(Self.lateLine))
                    }
                    // Finder may have gone to another folder while the card waited: a protected one is still never worked in.
                    if case .path(let shown) = shownPlace(), ArisProtectedPlaces.blocks(shown, home: self.identity.home) {
                        turn.audit(["answer": "refused (Finder now shows a protected place)", "action": what, "brain": turn.brainName])
                        return done(.failed(ArisDesktopGate.placeRefusal))
                    }
                    if remember, let key = target.memoryKey { turn.ledger.remember(key, tainted: turn.taint(forApp: target.readKey) != .none) }
                    turn.audit(["answer": "yes", "action": what, "brain": turn.brainName])
                    var held = basis
                    if held.title == nil {
                        held.title = snapshotTitle
                        held.window = request.ref.flatMap { turn.ledger.observation($0.snapshot)?.window }
                    }
                    held.frontBefore = frontBefore
                    if held.field == nil { held.field = element }
                    held.settingsPane = pane
                    held.cardYes = !turn.isTask && !target.sending
                    let outcome = self.perform(request, target: target, turn: turn, basis: held)
                    // A send from a field that can't be read gets one try: what Aris typed there no longer vouches for
                    // what the field holds.
                    if held.blindSend != nil { turn.ledger.clearBlindTyped(window: held.window) }
                    self.putBack(frontBefore, target: target)
                    done(outcome)
                }
            }
        }
    }

    /// What the card shows of the window: its title (the ref's look, else the latest look at the app's front window),
    /// and in a sending app a fresh look at what the field holds now (raw), never recorded. A send whose text can't be
    /// read in full isn't asked about: it is refused (I1).
    func cardBasis(_ request: ArisDesktopRequest, target: ArisDesktopTarget, element: ArisDesktopElement?,
                   turn: ArisDesktopTurn) -> Result<ArisDesktopBasis, ArisDesktopUsage> {
        // The window the call is aimed at (the one it or the user's words named: ArisDesktopAim), else the front one.
        let all = windows.windows(of: target.pid)
        let front = request.window.flatMap { id in all.first { $0.id == id } } ?? all.first
        var basis = ArisDesktopBasis(title: request.ref == nil ? front.flatMap { turn.ledger.latestLook(window: $0.id)?.title } : nil,
                                     window: request.ref == nil ? front?.id : nil)
        guard target.sending, request.verb != .app, request.verb != .window else { return .success(basis) }
        let maySend = ArisDesktopGate.isSend(request, element: element)
        guard access.trusted, case .success(let binary) = installer.ready() else {
            return .failure(ArisDesktopUsage(text: maySend ? Self.unreadSendLine : Self.unreadLine))
        }
        let session = ArisDesktopSession(engine: self, binary: binary, target: target, turn: turn)
        let pinned = request.ref.flatMap { turn.ledger.window(ofSnapshot: $0.snapshot) } ?? request.window
        guard case .success(let window) = session.pinned(pinned), case .success(let (look, _)) = session.look(window, record: false) else {
            return .failure(ArisDesktopUsage(text: maySend ? Self.unreadSendLine : Self.unreadLine))
        }
        turn.ledger.discard(look.peekaboo)
        let control = element.flatMap { ArisDesktopVerify.find($0, in: look) } ?? (element?.isTextEntry == true ? element : nil)
        let field = look.composer(for: control)
        var send = ArisDesktopGate.isSend(request, element: control ?? element)
        // An icon button with no name right by the message field is its send button.
        if request.verb == .click, let control, control.isUnlabelledButton, let field, ArisDesktopObservation.distance(field, control) <= Self.sendReach {
            send = true
        }
        // Return in a search field searches: asked as keys, held to that field still having the focus.
        if send, request.verb == .press, let focused = look.focusedElement, focused.isSearch {
            send = false
            basis.searchFocus = focused.label
        }
        if send || request.verb.takesText {
            guard let field, !field.rawCapped, !field.isSecure else { return .failure(ArisDesktopUsage(text: send ? Self.unreadSendLine : Self.unreadLine)) }
            if let raw = field.rawValue {
                basis.composer = raw
            } else if !send, look.showsText(besides: field) {
                basis.blindField = true
            } else if send, let typed = turn.ledger.blindTyped(window: look.window), session.windowShows(typed, in: look) {
                // The field gives no value, but Aris typed into it on the user's card this turn and the window still shows
                // that text: his send card says exactly that, instead of a refusal (audit desk-4).
                basis.blindSend = typed
            } else {
                return .failure(ArisDesktopUsage(text: send ? Self.unreadSendLine : Self.blindLine(english: ArisDesktopCopy.isEnglish(turn.request))))
            }
        } else {
            basis.shownField = field?.rawValue
        }
        basis.title = look.title
        basis.window = look.window
        basis.field = field
        basis.send = send
        return .success(basis)
    }

    /// What the read judge sees of a read: the verb and the app, and what it looks for.
    static func readCall(_ request: ArisDesktopRequest, target: ArisDesktopTarget) -> ArisReadCall {
        ArisReadCall(tool: "desktop \(request.verb.rawValue)", arguments: ([target.name] + (request.ocr ? ["--ocr"] : []) + (request.annotate ? ["--annotate"] : [])).joined(separator: " "))
    }

    /// The app a call is for: the app of the look its ref came from, the --app name resolved, an installed app for a
    /// launch, the Dock for its list.
    func resolve(_ request: ArisDesktopRequest, turn: ArisDesktopTurn) -> Result<ArisDesktopTarget, ArisDesktopUsage> {
        if let ref = request.ref {
            guard let target = turn.ledger.target(ofSnapshot: ref.snapshot) else { return .failure(ArisDesktopUsage(text: Self.notOursLine)) }
            guard apps.isRunning(target) else { return .failure(ArisDesktopUsage(text: Self.quitLine)) }
            return .success(target)
        }
        if request.verb == .dockList {
            return apps.dock().map { .success($0) } ?? .failure(ArisDesktopUsage(text: "The Dock isn't running."))
        }
        guard let name = request.app else { return .failure(ArisDesktopUsage(text: ArisDesktopGate.unknownRefusal)) }
        if request.verb == .app && request.operation == "launch" {
            if let running = apps.resolve(name) { return .success(running) }
            return apps.installed(name).map { .success($0) } ?? .failure(ArisDesktopUsage(text: "Refused: no installed app has that name."))
        }
        guard let target = apps.resolve(name) else {
            // Nothing to quit is said as that, not as "open it first".
            if request.verb == .app, request.operation == "quit" { return .failure(ArisDesktopUsage(text: "That app isn't running (or more than one app has that name), so there is nothing to quit.")) }
            return .failure(ArisDesktopUsage(text: ArisDesktopGate.unknownRefusal))
        }
        return .success(target)
    }

    /// The notch's line while a call works (Korean, or English for an English request: ArisDesktopCopy.working).
    static func statusLine(_ verb: ArisDesktopVerb, app: String, english: Bool = false) -> String {
        ArisDesktopCopy.working(verb, app: app, english: english)
    }

    func operatingTarget(_ request: ArisDesktopRequest, target: ArisDesktopTarget, turn: ArisDesktopTurn) -> ArisOperatingTarget {
        let window = request.ref.flatMap { turn.ledger.window(ofSnapshot: $0.snapshot) } ?? request.window
        return ArisOperatingTarget(app: target.name, pid: target.pid, window: window,
                                   line: Self.statusLine(request.verb, app: target.name, english: ArisDesktopCopy.isEnglish(turn.request)))
    }
}
