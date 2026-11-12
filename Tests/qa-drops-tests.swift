// Tests for QA BUG-23, BUG-24 and BUG-27 (QA batch 7 on fork 868051ee): files given to Aris ride along with the
// next request however it is asked, mean "이 파일" instead of the screen, and are cleared once used or when the
// conversation closes; a drop on Aris's half keeps the notch open on the composer; a drag over any tab shows the drop
// zones; and a drag finds the closed notch a little lower. Each failed before its change. Called from main.swift.
import CoreGraphics
import Foundation

func runQADropsTests() {
    qaPendingFilesTests()
    qaAttachmentDeixisTests()
    qaAttachmentWiringTests()
    qaAttachmentClearTests()
    qaDropHoldTests()
    qaDropPageTests()
    qaDragHoverTests()
}

private let shells = URL(fileURLWithPath: "/Users/p/Downloads/shells.pdf")
private let p2 = URL(fileURLWithPath: "/Users/p/Downloads/p2.pdf")
private let question = "이 파일에 뭐가 적혀 있어? 한 줄로"

private func dropSource(_ path: String) -> String {
    let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    return (try? String(contentsOf: tests.appendingPathComponent("../" + path), encoding: .utf8)) ?? ""
}

/// The body of `name` in `source`, up to the next func.
private func body(of name: String, in source: String) -> String {
    guard let start = source.range(of: name) else { return "" }
    let rest = source[start.upperBound...]
    let end = rest.range(of: "\n    func ") ?? rest.range(of: "\n    private func ")
    return String(rest[..<(end?.lowerBound ?? rest.endIndex)])
}

/// BUG-23: the pending files go with the turn's words, once, and are gone after.
private func qaPendingFilesTests() {
    let pending = ArisPendingFiles().adding([shells])
    let taken = pending.taking(into: question)
    check(taken.text.hasPrefix(question) && taken.text.contains(shells.path) && ArisPendingFiles.carriesFiles(taken.text),
          "BUG-23: a spoken request carries the pending file")
    check(taken.left.files.isEmpty, "BUG-23: the files are cleared once the request took them")
    check(taken.text.contains("이 파일") && taken.text.contains("this file"), "BUG-23: the note says \"이 파일\" / \"this file\" means it")
    // Typed: the composer already put them in; taken again, they aren't added twice.
    let typed = pending.request(with: question)
    let again = pending.taking(into: typed)
    check(again.text == typed && again.left.files.isEmpty, "BUG-23: a typed request isn't given the files twice")
    // Nothing pending: the words as they are.
    check(ArisPendingFiles().taking(into: question).text == question, "BUG-23: no files, the words unchanged")
    check(ArisPendingFiles.words(of: taken.text) == question, "BUG-23: the words without the note")
    check(ArisFollowUp.isDone(ArisPendingFiles.words(of: ArisPendingFiles().adding([shells]).taking(into: "됐어").text)),
          "BUG-23: \"됐어\" with files pending still ends the conversation")
    let many = ArisPendingFiles().adding([shells, p2, shells])
    check(many.files == [shells, p2] && many.removing(shells).files == [p2], "BUG-23: a file is pending once, and can be taken off")
    check(ArisPendingFiles().adding((0..<20).map { URL(fileURLWithPath: "/tmp/\($0)") }).files.count == ArisPendingFiles.limit,
          "BUG-23: at most the limit")
    check(ArisPendingFiles().adding([URL(string: "https://example.com/a.pdf")!]).files.isEmpty, "BUG-23: only files")
}

/// BUG-23: with files attached, "이 파일" / "이거" is the file: the screen isn't read.
private func qaAttachmentDeixisTests() {
    check(ArisDeixis.refersToScreen(question), "BUG-23: without files, \"이 파일\" still points at the screen")
    let withFiles = ArisPendingFiles().adding([shells]).taking(into: question).text
    check(!ArisDeixis.refersToScreen(withFiles), "BUG-23: with files, \"이 파일\" is the file, never the screen")
    check(!ArisDeixis.refersToScreen(ArisPendingFiles().adding([shells]).taking(into: "이거 요약해줘").text), "BUG-23: \"이거\" with a file isn't the screen")
    check(!ArisDeixis.refersToScreen(ArisPendingFiles().adding([shells]).taking(into: "what does this file say?").text),
          "BUG-23: \"this file\" with a file isn't the screen")
}

/// BUG-23: every path takes the files (ArisController.answer), and a turn with files takes no screenshot.
private func qaAttachmentWiringTests() {
    let controller = dropSource("Aris/private/Aris/ArisController.swift")
    let answer = body(of: "func answer(_ said: String, gesture: ArisGestureTurn? = nil, typed: Bool = false) async {", in: controller)
    check(answer.contains("ArisAttachments.shared.take(into: said, handsFree: turnHandsFree, shown: ArisNotchPresence.shared.isOpen)"),
          "BUG-23: the voice, wake-word and follow-up turn takes the files (never hands-free or out of sight: follow-up M6)")
    check(answer.contains("seeEnded()"), "BUG-23: a turn with files drops its screenshot")
    check(answer.contains("ArisFollowUp.isDone(ArisPendingFiles.words(of: text)"), "BUG-23: the done check reads only the words")
    let typed = dropSource("Aris/private/Aris/ArisController+Typed.swift")
    check(typed.contains("ArisPendingFiles.carriesFiles(text)"), "BUG-23: a typed request with files takes no screenshot")
    let composer = dropSource("Aris/private/Aris/Home/ArisComposer.swift")
    check(composer.contains("ArisPendingFiles"), "BUG-23: the composer's attachments are ArisPendingFiles")
}

/// BUG-27: stale files never ride along: cleared on 닫기 and when the conversation ends on its own.
private func qaAttachmentClearTests() {
    let controller = dropSource("Aris/private/Aris/ArisController.swift")
    check(body(of: "func dismissAnswer() {", in: controller).contains("ArisAttachments.shared.clear()"), "BUG-27: 닫기 clears the files")
    let conversation = dropSource("Aris/private/Aris/ArisController+Conversation.swift")
    check(body(of: "func closeConversation(_ reason: ArisConversation.EndReason) {", in: conversation).contains("if ArisPendingFiles.clearedWhenConversationEnds(reason) { ArisAttachments.shared.clear() }"),
          "BUG-27: the conversation ending (timeout, 됐어) clears the files")
    check(ArisPendingFiles.clearedWhenConversationEnds(.dismissed) && ArisPendingFiles.clearedWhenConversationEnds(.silence)
          && ArisPendingFiles.clearedWhenConversationEnds(.donePhrase), "BUG-27: 닫기, the quiet timeout and 됐어 clear them")
    check(!ArisPendingFiles.clearedWhenConversationEnds(.key) && !ArisPendingFiles.clearedWhenConversationEnds(.escape),
          "BUG-27: the talk key ending a conversation keeps them for the request about to be made")
    // Once cleared, an unrelated question goes alone.
    var pending = ArisPendingFiles().adding([shells, p2])
    pending = pending.taking(into: "이 파일 요약해줘").left
    check(pending.taking(into: "오늘 날씨 어때").text == "오늘 날씨 어때", "BUG-27: files a request used never attach to the next question")
    check(ArisPendingFiles().adding([p2]).cleared().taking(into: "오늘 날씨 어때").text == "오늘 날씨 어때",
          "BUG-27: cleared files never attach to the next question")
}

/// BUG-24a: a drop on Aris's half holds the notch open on the composer, with a hint.
private func qaDropHoldTests() {
    check(ArisPendingFiles.hint(for: [shells], korean: true) == "shells.pdf 받았어요. 뭘 할까요?", "BUG-24a: the Korean hint")
    check(ArisPendingFiles.hint(for: [shells], korean: false) == "Got shells.pdf. What should I do with it?", "BUG-24a: the English hint")
    check(ArisPendingFiles.hint(for: [shells, p2], korean: true) == "shells.pdf 외 1개 받았어요. 뭘 할까요?"
          && ArisPendingFiles.hint(for: [shells, p2], korean: false) == "Got shells.pdf and 1 more. What should I do with them?",
          "BUG-24a: several files")
    check(ArisPendingFiles.hint(for: [], korean: true) == nil, "BUG-24a: no files, no hint")
    typealias D = ArisNotchDecisions
    check(!D.automaticCloseAllowed(open: true, hovering: false, popover: false, sharing: false, approvalsPending: false, turnHolds: false,
                                   dropHold: true), "BUG-24a: a drop on Aris's half keeps the notch from closing")
    check(D.automaticCloseAllowed(open: true, hovering: false, popover: false, sharing: false, approvalsPending: false, turnHolds: false),
          "BUG-24a: otherwise it closes as before")
    check(D.dropHold(true, hoverInside: false, wasHovering: false), "BUG-24a: a hover-exit with no hover since the drop keeps the hold")
    check(D.dropHold(true, hoverInside: true, wasHovering: false), "BUG-24a: the pointer coming in keeps the hold")
    check(!D.dropHold(true, hoverInside: false, wasHovering: true), "BUG-24a: the pointer leaving after it came in ends the hold")
    check(!D.dropHold(false, hoverInside: true, wasHovering: true), "BUG-24a: no hold without a drop")
    let shelf = dropSource("Aris/private/Aris/Home/ArisShelfChips.swift")
    check(shelf.contains("interaction.arisDropHold = true"), "BUG-24a: the drop on Aris's half sets the hold")
    let composer = dropSource("Aris/private/Aris/Home/ArisComposer.swift")
    // Through ArisPanelKeys, so the panel really is key and the user's app gets the keyboard back after (BUG-22).
    check(composer.contains("ArisPanelKeys.take(") && composer.contains("ArisPendingFiles.hint("), "BUG-24a: the composer takes focus and shows the hint")
}

/// BUG-24b: a drag over any open tab but the shelf (a drop target itself) switches to the home page's drop zones.
private func qaDropPageTests() {
    typealias D = ArisNotchDecisions
    check(D.dropPage(.claude) == .home, "BUG-24b: a drag over the Claude tab shows the drop zones")
    check(D.dropPage(.home) == nil && D.dropPage(.aris) == nil, "BUG-24b: home and Aris already have them")
    check(D.dropPage(.shelf) == nil, "BUG-24b: the shelf page keeps its own drop")
    let behaviour = dropSource("Aris/private/Notch/ArisNotchRoot+Behaviour.swift")
    check(behaviour.contains("ArisNotchDecisions.dropPage("), "BUG-24b: the notch's drop delegate switches the page")
}

/// BUG-24c: during a content drag only, the closed notch catches it down to 56 pt below the top.
private func qaDragHoverTests() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let region = ArisNotchWindowRules.dragHoverRegion(screenFrame: screen, width: 200)
    check(region.height == ArisNotchDecisions.dragHoverDepth && ArisNotchDecisions.dragHoverDepth >= 56 && region.maxY == screen.maxY
          && region.midX == screen.midX && region.width == 200, "BUG-24c: the drag area reaches 56 pt below the top, centred")
    var watch = ArisDragWatch(region: region)
    watch.mouseDown(changeCount: 1)
    let at40 = watch.dragged(to: CGPoint(x: screen.midX, y: screen.maxY - 40), changeCount: 2) { true }
    check(at40.contains(.entered), "BUG-24c: a file dragged at y=40 is over the notch")
    let at70 = watch.dragged(to: CGPoint(x: screen.midX, y: screen.maxY - 70), changeCount: 2) { true }
    check(at70.contains(.exited), "BUG-24c: below the area it isn't")
    var window = ArisDragWatch(region: region)
    window.mouseDown(changeCount: 1)
    check(window.dragged(to: CGPoint(x: screen.midX, y: screen.maxY - 40), changeCount: 1) { true }.isEmpty,
          "BUG-24c: dragging a window (no content) never counts")
    let root = dropSource("Aris/private/Notch/ArisNotchRoot+Behaviour.swift")
    check(root.contains("dropInteraction.dragNear ? ArisNotchDecisions.dragHoverDepth"), "BUG-24c: the larger area shows only during a drag")
    let notch = dropSource("Aris/private/Notch/ArisNotchRoot.swift")
    check(notch.contains(".frame(width: width, height: vm.chinHeight)"), "BUG-24c: normal hover's strip is unchanged")
}
