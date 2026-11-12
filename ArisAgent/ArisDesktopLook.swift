//
//  ArisDesktopLook.swift
//  aris-agent
//
//  Windows with nothing for accessibility there (a canvas, a custom-drawn view): Aris takes the window's annotated
//  screenshot (Peekaboo draws its element marks on it), a vision brain picks a mark or a point (ArisDesktopVision), and
//  Aris clicks that mark's centre with background delivery. A text-only brain gets the text on the screenshot with its
//  boxes instead (`see --ocr`) and clicks a mark. When nothing pressable is at the point (Peekaboo can't press a drawn
//  view in the background), a real pointer click in the pinned window is the next way: only with the user's yes, only while
//  he is there, the pointer and the front app put back after.
//

import CoreGraphics
import Foundation
import ImageIO

extension ArisDesktopSession {
    static let pointerCard = "실제 마우스로 누를까요"
    static let spotCard = "이 자리를 누를까요"
    static let coveredLine = "Something else is over that spot (another window), so the real pointer wasn't used and nothing was clicked."

    func clickAt(_ request: ArisDesktopRequest) -> ArisDesktopResult {
        let window: ArisDesktopWindow
        switch pinned(request.window, title: request.title) {
        case .failure(let why): return .failed(why.text)
        case .success(let found): window = found
        }
        guard let (look, annotated) = lookWithText(window, annotate: true), let png = annotated, let size = Self.pixelSize(png) else {
            return .failed("Couldn't look at \(target.name)'s window.")
        }
        if let refused = held(look, field: nil) { return refused }
        let marks = look.elements.filter { $0.actionable }.map(\.id)
        guard engine.vision.available(for: turn.brain) else { return .failed(ArisDesktopEngine.noVisionLine(app: target.name)) }
        guard let pick = engine.vision.locate(png: png, width: size.width, height: size.height, target: request.target ?? "", marks: marks, brain: turn.brain) else {
            return .failed("Aris looked at \(target.name)'s window, but the AI that looks at the picture couldn't find that there (or gave no answer in time), so nothing was clicked. " +
                           "`desktop see --app \"\(target.name)\" --ocr` lists the text on the window with boxes.")
        }
        switch pick {
        case .mark(let id):
            guard let element = look.element(id: id) else { return .failed("The vision brain picked a mark that isn't in the window.") }
            // In a sending app the control the vision brain chose is shown to the user before it is pressed (I10).
            if target.sending, !consent(Self.spotCard, detail: Self.spotDetail(element.label, role: element.role, in: look, request: request, english: english)) {
                return .failed(consentRefusal)
            }
            let before = windowIds
            if engine.windows.promptOnScreen() != nil { return .failed(Self.promptLine) }
            let envelope = run(ArisPeekabooCommands.click(element.id, snapshot: look.peekaboo))
            let after = lookAfter(window.id)
            return readBack(after.map { ArisDesktopVerify.acted(on: element, before: look, after: $0) } ?? .notSeen("the window is gone"), envelope: envelope, after: after, before: before)
        case .point(let pixel):
            let scale = window.frame.width / CGFloat(max(size.width, 1))
            let point = CGPoint(x: window.frame.minX + pixel.x * scale, y: window.frame.minY + pixel.y * scale)
            // A raw point: what is there is shown on its own card before anything is clicked (I10). The job's own card covers
            // it only in a known document app, onto a labelled text control (ArisDesktopBatch.spotCovered: an allowlist,
            // security review of 4d40bb80).
            let there = Self.under(point, in: look)
            let covered = basis.cardYes && ArisDesktopBatch.spotCovered(there, at: point, in: look, target: target, webAncestor: engine.apps.focusedInWebArea(pid: target.pid))
            guard covered || consent(Self.spotCard, detail: Self.spotDetail(there?.label ?? "", role: there?.role ?? "", in: look, request: request,
                                                                 point: CGPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY), english: english)) else {
                return .failed(consentRefusal)
            }
            // That card said the pointer may be used, except in a sending app, where the pointer has its own card.
            return clickPoint(point, in: look, label: there?.label ?? request.target ?? "", consented: !target.sending)
        }
    }

    /// True once `condition` holds, read again a few times over half a second.
    static func settles(_ condition: () -> Bool, tries: Int = 6, wait: TimeInterval = 0.1) -> Bool {
        for attempt in 0..<tries {
            if attempt > 0 { Thread.sleep(forTimeInterval: wait) }
            if condition() { return true }
        }
        return false
    }

    /// The smallest element or text mark under a point.
    static func under(_ point: CGPoint, in look: ArisDesktopObservation) -> ArisDesktopElement? {
        (look.shown + look.marks).filter { $0.bounds.contains(point) && $0.bounds.width > 0 }.min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    static func spotDetail(_ label: String, role: String, in look: ArisDesktopObservation, request: ArisDesktopRequest, point: CGPoint? = nil, english: Bool = false) -> String {
        ArisDesktopCopy.spotDetail(title: look.title, wanted: request.target ?? "", label: label, role: role, point: point, english: english)
    }

    static let arisLine = "Aris's own notch or panel is over that spot, so nothing was clicked (a click never presses Aris itself)."

    /// A click at a global point inside the look's window: in the background first, then (nothing pressable there) a real
    /// pointer click with the user's yes (in a sending app always its own card), only when that window is the topmost one at
    /// the point, no password field is up and no sign-in prompt shows.
    func clickPoint(_ point: CGPoint, in look: ArisDesktopObservation, label: String, consented: Bool) -> ArisDesktopResult {
        guard let window = windows.first(where: { $0.id == look.window }), window.frame.insetBy(dx: -1, dy: -1).contains(point) else {
            return .failed("That spot isn't inside \(target.name)'s window, so nothing was clicked.")
        }
        let inside = CGPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY)
        let before = windowIds
        // No sign-in or permission prompt up, right before the background click too (security review of 4d40bb80).
        if engine.windows.promptOnScreen() != nil { return .failed(Self.promptLine) }
        var envelope = run(ArisPeekabooCommands.clickAt(inside, snapshot: look.peekaboo, window: window.id, foreground: false))
        var how = "a background click"
        if envelope?.nothingPressable == true {
            guard !turn.isTask else { return .failed("Nothing pressable is there in the background, and a background job never moves the pointer. Say so in the report.") }
            guard (consented && !target.sending) || basis.cardYes || consent(Self.pointerCard, detail: ArisDesktopCopy.pointerDetail(title: look.title, label: label, english: english)) else {
                return .failed(consentRefusal)
            }
            // Right before the pointer moves: no password field and no prompt; the window raised first, then nothing else
            // may be over the spot (I6, I7, I10, re-review 2). The pointer and the front app go back either way.
            if engine.apps.secureInput { return .failed(ArisDesktopGate.secureRefusal) }
            if engine.windows.promptOnScreen() != nil { return .failed(Self.promptLine) }
            // A real click on Aris's own notch or panel is never made (security review).
            if engine.windows.hitsAris(point) { return .failed(Self.arisLine) }
            let saved = engine.pointer.save()
            defer { restore(saved) }
            _ = run(ArisPeekabooCommands.window("focus", window: window.id))
            // The raise can take a moment to reach the window server; the check itself stays the same.
            guard Self.settles({ engine.windows.topWindow(at: point).map { $0.pid == target.pid && $0.id == window.id } ?? false }) else { return .failed(Self.coveredLine) }
            guard keysReachTarget(window) else { return .failed(ArisDesktopFocus.refusalLine) }
            envelope = run(ArisPeekabooCommands.clickAt(inside, snapshot: look.peekaboo, window: window.id, foreground: true))
            how = "a real pointer click, after the user's yes; the pointer is back"
        }
        // A drawn view shows nothing in the tree: its text, read again from the screen, is what changed.
        if !look.marks.isEmpty, engine.access.screenRecording, let (after, _) = lookWithText(window) {
            let check = ArisDesktopVerify.textChanged(before: look, after: after)
            if case .done = check { return report(check, envelope: envelope, after: after, how: how) }
            return readBack(ArisDesktopVerify.acted(on: nil, before: look, after: after), envelope: envelope, after: after, before: before, how: how)
        }
        let after = lookAfter(window.id)
        return readBack(after.map { ArisDesktopVerify.acted(on: nil, before: look, after: $0) } ?? .notSeen("the window is gone"), envelope: envelope, after: after,
                        before: before, how: how)
    }

    static func pixelSize(_ png: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }
}
