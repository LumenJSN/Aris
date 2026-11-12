// Tests for the notch's geometry and controls (2026-11-11): every number is pinned, with what it means in its
// message. Called from main.swift; uses its check(). Nothing is drawn.
import CoreGraphics
import Foundation

private typealias V = ArisVNotch

private func vnotchSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The user's MacBook (a 14-inch at 1800 × 1169: housing 220 × 38, menu-bar strip 39), a 14-inch at its default 1512, a
/// 16-inch at 2056, and a display with no camera housing.
private let users = V.Display(hasHousing: true, topBand: 39, width: 1800)
private let fourteen = V.Display(hasHousing: true, topBand: 37, width: 1512)
private let sixteenMore = V.Display(hasHousing: true, topBand: 39, width: 2056)
private let plain = V.Display.plain(width: 2560)

/// The notch's constants.
private func vnotchConstantTests() {
    check(V.baseDisplayWidth == 1512 && V.maxScale == 1.24, "vnotch: the scale is against a 1512-wide display and stops at 1.24")
    check(V.topBand == 37 && V.topBandCap == 48 && V.recordingBand == 32 && V.recordingBandDrop == 5,
          "vnotch: the open band is 37 up to 48, the recording band 32 or the band less 5")
    check(V.compactBandWidth == 270 && V.idleWidth == 150 && V.idleContentHeight == 29,
          "vnotch: the closed band is 270 wide, the idle notch 150 × 29")
    check(V.idleRestHeight == 4 && V.idleGlassRestHeight == 5.5,
          "vnotch: with no housing the idle notch rests 4 tall, 5.5 as glass")
    check(V.idleAttach == CGSize(width: 320, height: 44) && V.collapsedWidth == 220,
          "vnotch: idle with attachments is 320 × 44, the hidden state 220 wide")
    check(V.expandedBodyWidth == 440 && V.expandedRadius == 31 && V.compactRadius == 13 && V.responseMaxHeight == 360,
          "vnotch: the open body is 440 with 31-point corners, a closed one has 13, an answer stops at 360")
    check(V.contentInset == 12 && V.contentTopInset == 2 && V.contentBottomInset == 8 && V.expandedBottomInset(composerShown: true) == 8 && V.expandedBottomInset(composerShown: false) == 12,
          "vnotch: the open content is inset 12 each side and 2 above; below it 8 while the composer shows and 12 without it")
    check(V.hoverGrow == 6 && V.hoverWiden == 16 && V.hoverWidenNotched == 52,
          "vnotch: a hovered idle notch grows 6 taller and 16 wider, 52 over a housing")
    check(V.hoverTargetPadding == 2 && V.hoverExitPadding == 8 && V.hoverHapticCooldown == 0.75,
          "vnotch: a hover begins 2 outside and ends 8 outside, one haptic per 750 ms")
    check(V.slot == CGSize(width: 68, height: 22) && V.edgeInset == 14 && V.slotGap == 10,
          "vnotch: the band's side slots are 68 × 22, 14 from the edge, 10 apart")
    check(V.orbSize == 18 && V.orbBox == 28 && V.orbLeft == 9 && V.orbCenterX == 23,
          "vnotch: the 18-point mark sits in a 28-point control 9 from the body's left edge, its centre at 23")
    check(V.voiceSwitch == CGSize(width: 32, height: 19) && V.voiceSwitchLeft == 32 && V.voiceSwitchMinX == 41,
          "vnotch: the voice switch is 32 × 19 at left 32 of the control, 41 from the body's edge")
    check(V.stopSize == 23 && V.closeBesideStop == 30 && V.slotTrailing == 14,
          "vnotch: Stop is 23 × 23 at the slot's right, 14 from the body's edge; Close moves to right 30 beside it")
}

/// The display scale at 1512, 1800 and 2056 wide, and with no housing.
private func vnotchScaleTests() {
    let a = V.metrics(fourteen), b = V.metrics(users), c = V.metrics(sixteenMore), d = V.metrics(plain)
    check(a.scale == 1 && a.band == 37 && a.recordingBand == 32 && a.compactWidth == 270 && a.idleWidth == 150 && a.idleHeight == 29,
          "vnotch scale: a 1512-wide display is ×1: band 37, recording band 32, closed band 270, idle 150 × 29")
    check(abs(b.scale - 1800.0 / 1512) < 0.0001 && b.band == 44 && b.recordingBand == 39,
          "vnotch scale: the user's 1800-wide display is ×1.19: band round(max(37·1.19, 39)) = 44, recording band 44 − 5 = 39")
    check(b.compactWidth == 321 && b.idleWidth == 179 && b.idleHeight == 35 && b.hoverWiden == 62,
          "vnotch scale: at ×1.19 the closed band is 321, the idle notch 179 × 35, the hover widens by 62 (270, 150, 29 and 52 × scale, rounded)")
    check(b.idleAttach == CGSize(width: 381, height: 52) && b.collapsedWidth == 262,
          "vnotch scale: at ×1.19 idle with attachments is 381 × 52 and the hidden state 262 (320 × 44 and 220 × scale)")
    check(c.scale == 1.24 && c.band == 46 && c.recordingBand == 41 && c.compactWidth == 335 && c.idleWidth == 186 && c.idleHeight == 36,
          "vnotch scale: a 2056-wide display stops at ×1.24: band 46, recording band 41, closed band 335, idle 186 × 36")
    check(d.scale == 1 && d.band == 37 && d.recordingBand == 32 && d.compactWidth == 270 && d.idleWidth == 150 && d.idleHeight == 5.5 && d.idleSolidHeight == 4 && d.hoverWiden == 16,
          "vnotch scale: with no housing nothing scales: band 37, recording band 32, closed band 270, idle 150 × 5.5 (4 solid), the hover widens by 16")
    check(V.scale(V.Display(hasHousing: true, topBand: 44, width: 1512)) == 44.0 / 37 && V.metrics(V.Display(hasHousing: true, topBand: 44, width: 1512)).band == 44,
          "vnotch scale: a taller top band alone scales the notch too: max(1, width / 1512, topBand / 37)")
    check(V.metrics(V.Display(hasHousing: true, topBand: 60, width: 3000)).band == 48,
          "vnotch scale: the open band never passes 48 (clamp(…, 37, 48))")
    check(V.expandedBodyWidth == 440,
          "vnotch scale: the open body is 440 on every display: the expanded state's width is not scaled")
}

/// Closed sizes by state, the hover growth and the outline's radii.
private func vnotchClosedTests() {
    let m = V.metrics(users), p = V.metrics(plain)
    check(V.closedSize(.idle, hovered: false, glass: true, metrics: m) == CGSize(width: 179, height: 35),
          "vnotch closed: over the user's housing (220 × 38) the idle notch is 179 × 35: narrower and shorter, so only the housing shows")
    check(V.closedSize(.idle, hovered: true, glass: true, metrics: m) == CGSize(width: 241, height: 41),
          "vnotch closed: hovered, it grows to 241 × 41: +62 wide and +6 tall")
    check(V.closedSize(.band, hovered: false, glass: true, metrics: m) == CGSize(width: 321, height: 39)
          && V.closedSize(.band, hovered: true, glass: true, metrics: m) == CGSize(width: 383, height: 45),
          "vnotch closed: a band is 321 × 39, and a resting one grows under the pointer as the idle notch does (the parked band widens too)")
    check(V.closedSize(.liveBand, hovered: true, glass: true, metrics: m) == CGSize(width: 321, height: 39),
          "vnotch closed: the listening band never grows under the pointer (the recording band keeps its width)")
    check(V.closedSize(.idle, hovered: false, glass: true, metrics: p) == CGSize(width: 150, height: 5.5)
          && V.closedSize(.idle, hovered: false, glass: false, metrics: p) == CGSize(width: 150, height: 4)
          && V.closedSize(.idle, hovered: true, glass: true, metrics: p) == CGSize(width: 166, height: 11.5),
          "vnotch closed: with no housing the idle notch is 150 × 5.5 as glass, 4 solid, and 166 × 11.5 hovered")
    check(V.closedSize(.band, hovered: false, glass: true, metrics: p) == CGSize(width: 270, height: 32),
          "vnotch closed: with no housing a band is 270 × 32 (the closed band's width, the recording band's height)")
    check(V.visualWidth(bodyWidth: 440) == 502 && V.visualWidth(bodyWidth: 150) == 176 && V.visualWidth(bodyWidth: 270) == 296,
          "vnotch outline: the surface is the body and a shoulder each side: 502 open, 176 idle, 296 for a band")
    check(V.radius(bodyWidth: 440, height: 300) == 31 && V.radius(bodyWidth: 321, height: 39) == 13 && V.radius(bodyWidth: 150, height: 5.5) == 2.75 && V.radius(bodyWidth: 150, height: 4) == 2,
          "vnotch outline: corners are 31 open and 13 closed, held to a quarter of the width and half the height")
    check(V.ear(body: 321, housing: 220) == 50.5 && V.orbFits(ear: 50.5) && V.orbFits(ear: V.ear(body: 270, housing: 185)) && !V.orbFits(ear: V.ear(body: 241, housing: 220)),
          "vnotch closed: the 28-point control 9 in fits the ear of a band (50.5 beside the user's housing, 42.5 at 1512) and not a hovered idle notch's 10.5")
    check(V.hoverGrowthShows(openOnHover: false, hoverDelay: 0) && V.hoverGrowthShows(openOnHover: true, hoverDelay: 0.3) && !V.hoverGrowthShows(openOnHover: true, hoverDelay: 0.05),
          "vnotch hover: the growth shows when a rest does not open the notch, and before it opens when the wait is long enough to see (Aris opens on a rest by default, after 0.3 s)")
    check(!V.hapticAllowed(sinceLast: 0.5) && V.hapticAllowed(sinceLast: 0.75),
          "vnotch hover: one haptic per hover, none within 750 ms of the last")
}

/// Which mark the band shows, and when the glow is behind it.
private func vnotchIndicatorTests() {
    let table: [(Bool, Bool, Bool, Bool, V.Indicator)] = [
        (true, false, false, false, .waveform), (true, true, false, false, .waveform), (true, false, true, true, .waveform),
        (false, true, false, false, .loading), (false, true, true, false, .orb), (false, true, false, true, .orb),
        (false, false, false, false, .orb), (false, false, true, true, .orb), (false, false, true, false, .orb),
    ]
    check(table.allSatisfy { V.indicator(recording: $0.0, requestActive: $0.1, hasResult: $0.2, speaking: $0.3) == $0.4 },
          "vnotch mark: bars while recording; the working mark while the request is active with nothing arrived and nothing spoken; the orb otherwise")
    check(V.halo(indicator: .orb, speaking: true, error: false) == .speaking && V.halo(indicator: .orb, speaking: false, error: true) == .error
          && V.halo(indicator: .orb, speaking: false, error: false) == .none && V.halo(indicator: .waveform, speaking: true, error: true) == .none
          && V.halo(indicator: .loading, speaking: false, error: true) == .none,
          "vnotch mark: the glow is behind the orb only while speaking or in error, never behind the bars")
    let speaking = V.haloSpec(.speaking), error = V.haloSpec(.error)
    check(speaking?.outset == 10 && speaking?.blur == 4 && speaking?.alphas == [0.28, 0.16, 0.07] && error?.outset == 9 && error?.blur == 3 && error?.alphas == [0.55, 0.32, 0.13]
          && V.haloSpec(.none) == nil,
          "vnotch mark: the glow reaches 10 past the mark blurred 4 at .28/.16/.07 while speaking, 9 blurred 3 at .55/.32/.13 in error")
    check(V.crossfade.duration == 0.28 && V.crossfade.curve == (0.4, 0, 0.2, 1) && V.crossfade.orbScale == 0.75 && V.crossfade.barsScale == 0.85,
          "vnotch mark: the orb and the bars trade places over 280 ms on (0.4, 0, 0.2, 1), from 75 % and 85 %")
}

/// How a closed Aris rests.
private func vnotchRestTests() {
    check(ArisVNotchRest(stored: nil) == .outOfSight && ArisVNotchRest(stored: "") == .outOfSight && ArisVNotchRest(stored: "nonsense") == .outOfSight && ArisVNotchRest(stored: "star") == .star,
          "vnotch rest: with nothing written the closed notch rests out of sight; arisClosedRest = star keeps the star resting")
    check(!ArisVNotchRest.outOfSight.starRests(muted: false, agentDown: false, modelNote: false),
          "vnotch rest: at rest with nothing to tell there is no star band: the closed notch is the idle notch, hidden by the housing")
    check(ArisVNotchRest.outOfSight.starRests(muted: true, agentDown: false, modelNote: false) && ArisVNotchRest.outOfSight.starRests(muted: false, agentDown: true, modelNote: false)
          && ArisVNotchRest.outOfSight.starRests(muted: false, agentDown: false, modelNote: true),
          "vnotch rest: the star still comes out at rest for what only the closed notch says: muted, the helper down, a speech model's note")
    check(ArisVNotchRest.outOfSight.starRests(muted: false, agentDown: false, modelNote: false, filesWaiting: true),
          "vnotch rest: files given to Aris bring the band out at rest too, with their count in its right slot (the attachment count)")
    check(ArisVNotchRest.star.starRests(muted: false, agentDown: false, modelNote: false), "vnotch rest: the preference keeps the star resting in the band")
}

/// Editing a sent request: when the pencil is offered, what a press on the card does, and what Return sends.
private func vnotchEditTests() {
    typealias E = ArisPromptEdit
    check(E.pencilSize == 22 && E.pencilTop == 16 && E.pencilTrailing == 10 && E.pencilGlyph == 12 && E.pencilFill.alpha == 0.92,
          "vnotch edit: the pencil is a 22-point circle at top 16, right 10 of the card, rgba(28, 28, 32, .92), a 12-point glyph")
    let answered = E.Turn(phase: .speaking, words: "내일 날씨 알려줘")
    check(E.offer(answered) == .editable(saysDone: false) && E.offer(E.Turn(phase: .idle, words: "a")) == .editable(saysDone: false)
          && E.offer(E.Turn(phase: .failed, words: "a")) == .editable(saysDone: false) && E.offer(E.Turn(phase: .thinking, words: "a")) == .editable(saysDone: false),
          "vnotch edit: a sent request can be edited while Aris works on it, answers, has failed, or the answer is parked (the pencil is on the sent card whenever it is not being recorded)")
    check(E.offer(E.Turn(phase: .speaking, words: "메일 보내줘", didSomething: true)) == .editable(saysDone: true),
          "vnotch edit: when the first request already did something, the card says so while it is edited: an edit never resends over a finished action without saying it")
    check(E.offer(E.Turn(phase: .listening, words: "내일")) == .no(.listening) && E.offer(E.Turn(phase: .thinking, words: "듣고 있어요…", placeholder: true)) == .no(.placeholder)
          && E.offer(E.Turn(phase: .idle, words: "  ")) == .no(.noWords),
          "vnotch edit: no pencil while Aris listens, on the hint in the words' place, or with no words")
    check(E.offer(E.Turn(phase: .thinking, words: "보내줘", cardWaiting: true)) == .no(.cardWaiting) && E.offer(E.Turn(phase: .speaking, words: "응", cardWaiting: true, didSomething: true)) == .no(.cardWaiting),
          "vnotch edit: no pencil while a card waits for an answer: an edit never stands in for a yes or a no (the sent card is out of sight while a card asks)")
    check(E.offer(E.Turn(phase: .speaking, words: "이거 요약해줘", carriesFiles: true)) == .no(.carriesFiles) && E.offer(E.Turn(phase: .speaking, words: "이거 뭐야 [img 1]", carriesShots: true)) == .no(.carriesShots),
          "vnotch edit: no pencil on words that went with files or circled shots: the resend would leave them behind")
    check(E.tap(lines: 3, offer: .editable(saysDone: false)) == .toggles && E.tap(lines: 2, offer: .editable(saysDone: false)) == .edits
          && E.tap(lines: 1, offer: .no(.listening)) == .nothing && E.tap(lines: 5, offer: .no(.cardWaiting)) == .toggles,
          "vnotch edit: a press on a card over two lines opens and folds it; on a shorter one it starts the edit when it can")
    check(E.send(draft: "  내일 서울 날씨  \n", phase: .speaking) == .send("내일 서울 날씨", stopsFirst: false) && E.send(draft: "x", phase: .idle) == .send("x", stopsFirst: false)
          && E.send(draft: "x", phase: .failed) == .send("x", stopsFirst: false),
          "vnotch edit: Return sends the trimmed words as a new typed request, sent the way the composer sends, and the edited turn replaces the old one on screen")
    check(E.send(draft: "다시", phase: .thinking) == .send("다시", stopsFirst: true),
          "vnotch edit: sent while Aris still works on the first request, the first is stopped first, as Stop stops it")
    check(E.send(draft: "   ", phase: .speaking) == .discard && E.send(draft: "", phase: .thinking) == .discard,
          "vnotch edit: an emptied card sends nothing and the edit is thrown away")
    check(E.editorContent(lines: 1) == 22 && E.editorContent(lines: 2) == 44 && E.editorContent(lines: 3) == 62 && E.editorContent(lines: 9) == 62,
          "vnotch edit: the editor is the card's own box: its lines on the 22-point pitch up to two, then two and an 18-point peek, scrolling inside")
    check(E.doneNote(english: false).contains("새 요청") && E.doneNote(english: true).contains("new request") && !E.pencilHelp(english: true).isEmpty && E.pencilHelp(english: false) == "요청 고치기"
          && E.editorLabel(english: false) != E.editorLabel(english: true),
          "vnotch edit: the pencil, the editor and the note have Korean and English words")
    check(ArisPromptCollapse.padding == 16 && ArisPromptCollapse.lineHeight == 22 && ArisPromptCollapse.collapsedLines == 2 && ArisPromptCollapse.peek == 18 && ArisPromptCollapse.fade == 34
          && ArisPromptCollapse.box(lines: 1, collapsed: false) == 54 && ArisPromptCollapse.box(lines: 5, collapsed: true) == 94,
          "vnotch edit: the sent-prompt card is 16 of padding around 22-point lines (54 for one line), two lines and an 18-point peek under a 34-point fade when longer")
    check(ArisComposerLines.maxLines == 3 && ArisComposerLines.height(lines: 1) == 38 && ArisComposerLines.height(lines: 3) == 82 && ArisComposerLines.height(lines: 7) == 82,
          "vnotch edit: the composer is lines · 22 + 16, three lines at most")
}

/// The voice switch: when it is offered, and what turning it off does.
private func vnotchVoiceSwitchTests() {
    check(V.voiceSwitchOffered(indicator: .orb) && !V.voiceSwitchOffered(indicator: .waveform) && !V.voiceSwitchOffered(indicator: .loading),
          "vnotch switch: the voice switch is offered beside the orb only, never beside the bars or the working mark (open, not recording, the orb showing)")
    check(ArisMuteSwitchRule.visible(shown: true, muted: false, hovering: true) && !ArisMuteSwitchRule.visible(shown: true, muted: false, hovering: false)
          && ArisMuteSwitchRule.visible(shown: true, muted: true, hovering: false) && !ArisMuteSwitchRule.visible(shown: false, muted: true, hovering: true),
          "vnotch switch: it comes up under the pointer, and Aris also keeps it up while muted")
    let day = ArisQuiet.Moment()
    check(ArisQuiet.decide(starter: .user, muted: true, moment: day) == .textOnly(.muted) && ArisQuiet.decide(starter: .aris, muted: true, moment: day) == .textOnly(.muted)
          && ArisQuiet.decide(starter: .userTimer, muted: true, moment: day) == .textOnly(.muted) && ArisQuiet.decide(starter: .user, muted: false, moment: day) == .aloud,
          "vnotch switch: off, replies are shown and not spoken, whoever started them; on, they are spoken again")
    check(!ArisQuiet.voiceMayPlay(muted: true, preview: false) && ArisQuiet.voiceMayPlay(muted: false, preview: false),
          "vnotch switch: off, nothing reaches the loudspeaker on any path (turning it off also stops a voice mid-sentence)")
    check(ArisQuietGate.mutedKey == "arisMuted",
          "vnotch switch: the state is one stored preference (default on)")
}

/// The band's layout in the app's own files: the grid's numbers are ArisVNotch's, not literals of their own.
private func vnotchGridSourceTests() {
    let header = vnotchSource("Aris/private/Aris/Home/ArisNotchHeader.swift")
    check(header.contains("ArisBandFace(bodyWidth: width + 2 * ArisGlass.inset") && header.contains(".padding(.horizontal, -ArisGlass.inset)"),
          "vnotch grid: the open band spans the notch's body (the content and 12 each side), so the mark is 9 from the body's edge (it sat 23 in)")
    check(header.contains("ArisVNotch.closeBesideStop") && header.contains(".frame(height: ArisVNotch.stopSize)") && !header.contains("ArisGlass.textInset - 5"),
          "vnotch grid: Stop and Close share one slot: 23 tall, Close 30 from the right beside Stop")
    let face = vnotchSource("Aris/private/Aris/Home/ArisBandFace.swift")
    check(face.contains(".frame(width: ArisVNotch.orbBox, height: ArisVNotch.orbBox)") && face.contains(".padding(.leading, ArisVNotch.orbLeft)") && face.contains(".padding(.trailing, ArisVNotch.slotTrailing)"),
          "vnotch grid: the band's face places the 28-point control at left 9 and ends the right slot 14 from the edge")
    check(vnotchSource("Aris/private/Aris/Home/ArisMuteSwitch.swift").contains(".frame(width: ArisVNotch.voiceSwitchMinX)"),
          "vnotch grid: the voice switch starts 41 from the body's edge: 32 into the control at 9")
    check(vnotchSource("Aris/private/Aris/Team/ArisStarStage.swift").contains("static let size: CGFloat = ArisVNotch.orbSize"),
          "vnotch grid: the closed band's star is the 18-point mark (it was 20)")
    check(ArisBand.markCenter == V.orbCenterX && ArisBand.radius == V.compactRadius,
          "vnotch grid: the closed band's mark is centred 23 from the band's edge with 13-point corners: the control at 9 and the compact radius")
    let root = vnotchSource("Aris/private/Notch/ArisNotchRoot.swift")
    check(root.contains(".frame(height: vm.openBandHeight)") && root.contains(".environment(\\.arisBandBody, bandBody)") && root.contains("closedIsVNotch ? closedBody.height"),
          "vnotch grid: the notch's root takes the open band's height, the closed height and every band's width from the notch's rule for its display")
    check(ArisBand.earWidth(notchWidth: 224, body: 321) == 48.5 && ArisBand.earWidth(notchWidth: 224, body: nil) == ArisBand.earWidth(notchWidth: 224)
          && ArisClosedBand.surfaceWidth(notchWidth: 224, body: 321) == 347 && ArisClosedBand.timerControlWidth(notchWidth: 189, body: 270) == 40.5,
          "vnotch grid: a band's ears are what the band leaves beside the camera's width; with no band width given they are sized from the camera as before")
    check(ArisClosedBand.region(CGRect(x: 10, y: 0, width: 100, height: 30), insets: nil, pad: V.hoverTargetPadding) == CGRect(x: 8, y: -2, width: 104, height: 34),
          "vnotch grid: a rest on the closed notch begins 2 points outside its surface")
    let behaviour = vnotchSource("Aris/private/Notch/ArisNotchRoot+Behaviour.swift")
    check(behaviour.contains("ArisVNotch.hoverExitPadding") && behaviour.contains("hoverHaptic()") && behaviour.contains("ArisNotchDecisions.hoverOpens"),
          "vnotch hover: the closed notch lets go 8 points out and gives one haptic per 750 ms; a rest still opens Aris after its hover time, as before")
    let glyph = vnotchSource("Aris/private/Aris/Home/ArisVoiceGlyph.swift")
    check(glyph.contains("ArisVNotch.crossfade.orbScale") && glyph.contains("ArisVNotch.crossfade.barsScale") && glyph.contains("ArisVNotch.indicator(recording: self == .listening"),
          "vnotch mark: the band's mark follows one indicator rule and crossfade from one place (ArisVNotch)")
    check(glyph.contains("static let count = 4") && glyph.contains("static let barWidth: CGFloat = 2.5") && glyph.contains("static let gap: CGFloat = 1.5")
          && glyph.contains("static let minHeight: CGFloat = 2") && glyph.contains("static let maxHeight: CGFloat = 17") && glyph.contains("static let tick = 0.058"),
          "vnotch mark: four bars 2.5 wide with 1.5 each side (22 in all), 2 to 17 tall, a new height every 58 ms")
}

/// Security review 7, L2 and L3: what an edited request may take with it, and what Return may never do.
private func vnotchEditReviewTests() {
    typealias E = ArisPromptEdit
    let file = URL(fileURLWithPath: "/tmp/vnotch-review/notes.txt")
    let waiting = ArisPendingFiles().adding([file], at: Date())
    // L2: files that wait for "the next request" stay waiting when an older request is edited and sent again.
    check(!E.chipsInSight(notchOpen: true, editedRequest: true) && E.chipsInSight(notchOpen: true, editedRequest: false) && !E.chipsInSight(notchOpen: false, editedRequest: false),
          "review-7 L2: while a request is edited the waiting files' chips are out of sight (the composer steps aside), as they are with the notch closed")
    let edited = waiting.taking(into: "내일 서울 날씨", shown: E.chipsInSight(notchOpen: true, editedRequest: true))
    check(edited.text == "내일 서울 날씨" && !ArisPendingFiles.carriesFiles(edited.text) && edited.left.files == [file],
          "review-7 L2: an edited request goes out as its words alone, and the files keep waiting for the next request")
    let typed = waiting.taking(into: "이거 요약해 줘", shown: E.chipsInSight(notchOpen: true, editedRequest: false))
    check(ArisPendingFiles.carriesFiles(typed.text) && typed.left.files.isEmpty, "review-7 L2: a request asked with the chips in sight still takes the files, as before")
    let sent = E.Sent.sending("내일 서울 날씨")
    check(sent.taken(by: "내일 서울 날씨").isEdit && sent.taken(by: "내일 서울 날씨").left == E.Sent() && !sent.taken(by: "다른 요청").isEdit && sent.taken(by: "다른 요청").left == E.Sent()
          && !E.Sent().taken(by: "내일 서울 날씨").isEdit,
          "review-7 L2: only the edited request's own turn leaves the files; it is asked once, and any other turn is an ordinary one")
    let turn = vnotchSource("Aris/private/Aris/Home/ArisTurnView.swift"), composer = vnotchSource("Aris/private/Aris/Home/ArisComposer.swift")
    check(turn.contains("ArisPromptEditing.shared.sending(words)\n        aris.submitTyped(words)") && !turn.contains("ArisAttachments.shared.request(with: words)") && !turn.contains("ArisAttachments.shared.clear()"),
          "review-7 L2: wiring: the editor sends the words alone and neither takes nor clears the waiting files")
    check(composer.contains("let shown = ArisPromptEdit.chipsInSight(notchOpen: shown, editedRequest: ArisPromptEditing.shared.takeEdit(words))\n        let taken = pending.taking(into: words, handsFree: handsFree, shown: shown,"),
          "review-7 L2: wiring: the one place waiting files join a turn asks first whether the turn is the edited request")

    // L3: Return in the editor never answers a card.
    check(ArisCardWait.typedAnswer("응 지워", cardUp: true) == true && ArisCardWait.typedAnswer("yes go ahead", cardUp: true) == true,
          "review-7 L3: the danger: typed words that read as a yes answer a waiting card")
    check(E.send(draft: "응 지워", phase: .thinking, offer: .no(.cardWaiting)) == .discard && E.send(draft: "yes go ahead", phase: .speaking, offer: .no(.cardWaiting)) == .discard,
          "review-7 L3: Return in the frame a card comes up sends nothing: the edit is thrown away and the card stays unanswered")
    check(E.send(draft: "다시", phase: .listening, offer: .no(.listening)) == .discard && E.send(draft: "다시", phase: .idle, offer: .no(.carriesFiles)) == .discard,
          "review-7 L3: the same for anything else that took the pencil away since the editor opened")
    check(E.send(draft: "응 지워", phase: .speaking, offer: .editable(saysDone: true)) == .send("응 지워", stopsFirst: false),
          "review-7 L3: with no card waiting the same words are an ordinary request")
    check(!E.offer(E.Turn(phase: .thinking, words: "응 지워", cardWaiting: true)).isEditable,
          "review-7 L3: a card coming up takes the pencil away, which closes the editor")
    check(turn.contains("ArisPromptEdit.send(draft: draft ?? \"\", phase: aris.session.phase, offer: liveEdit())") && turn.contains("liveEdit: { editOffer(prompt) }")
          && turn.contains(".onChange(of: edit.isEditable) { _, can in if !can { endEdit() } }"),
          "review-7 L3: wiring: Return asks what the turn is now, not what it was when the card was last drawn")
}

/// Security review 7, L1: a card too long for its room cannot be approved by a press before its end has been seen.
private func vnotchCardReadTests() {
    typealias R = ArisCardRead
    check(R.applies(allow: true, source: .click, countdown: false) && R.applies(allow: true, source: .key, countdown: false),
          "review-7 L1: a yes by a click and a yes by the Y key both wait until the card has been read to its end")
    check(!R.applies(allow: false, source: .click, countdown: false) && !R.applies(allow: false, source: .key, countdown: false) && !R.applies(allow: true, source: .click, countdown: true)
          && !R.applies(allow: true, source: .typed, countdown: false) && !R.applies(allow: true, source: .voice, countdown: false) && !R.applies(allow: true, source: .countdown, countdown: true),
          "review-7 L1: a no never waits; typed and spoken answers and a dictated message's countdown are as before")
    let fresh = R().following("a")
    check(!fresh.yesCounts(card: "a") && !R().yesCounts(card: "a"), "review-7 L1: a card that has not been laid out takes no pressed yes")
    let fits = fresh.scrolled(card: "a", offset: 0, visible: 180, content: 180)
    check(fits.yesCounts(card: "a") && fits.readToEnd, "review-7 L1: a card that fits its room is read as it stands: nothing changes for it")
    let long = fresh.scrolled(card: "a", offset: 0, visible: 440, content: 2600)
    check(!long.yesCounts(card: "a") && !long.readToEnd, "review-7 L1: a card taller than its room (a 3,000-character text, then its app's row) takes no pressed yes at first")
    let partway = long.scrolled(card: "a", offset: 900, visible: 440, content: 2600)
    check(!partway.yesCounts(card: "a"), "review-7 L1: scrolled part of the way, still none")
    let end = partway.scrolled(card: "a", offset: 2160, visible: 440, content: 2600)
    check(end.yesCounts(card: "a"), "review-7 L1: scrolled to its end, the yes counts")
    check(end.scrolled(card: "a", offset: 0, visible: 440, content: 2600).yesCounts(card: "a"), "review-7 L1: once is enough: scrolling back up keeps it")
    check(!end.scrolled(card: "a", offset: 2160, visible: 440, content: 5200).yesCounts(card: "a")
          && end.scrolled(card: "a", offset: 2160, visible: 440, content: 5200).scrolled(card: "a", offset: 4760, visible: 440, content: 5200).yesCounts(card: "a"),
          "review-7 L1: a card that grew (전체 보기) must be read to its new end")
    check(end.scrolled(card: "b", offset: 0, visible: 100, content: 100) == end && !end.yesCounts(card: "b"), "review-7 L1: another card's layout is not this card's")
    check(!end.following("b").yesCounts(card: "b") && end.following("a") == end && !end.following(nil).yesCounts(card: "a") && !end.shown("a").yesCounts(card: "a"),
          "review-7 L1: the next card starts unread, also when it is put up again under the same id")
    check(fresh.scrolled(card: "a", offset: 0, visible: 0, content: 0) == fresh, "review-7 L1: a card with no size yet has not been read")
    check(!R.hint(english: false).isEmpty && R.hint(english: true) != R.hint(english: false), "review-7 L1: the button says why it waits, in Korean and English")
    let controller = vnotchSource("Aris/private/Aris/ArisController.swift"), card = vnotchSource("Aris/private/Aris/Home/ArisConfirmCard.swift")
    check(controller.contains("if ArisCardRead.applies(allow: allow, source: source, countdown: question.countdown), !ArisCardReadLive.shared.yesCounts(card: question.id) {")
          && controller.contains("if session.question?.id != oldValue.question?.id { ArisCardReadLive.shared.follow(session.question?.id) }")
          && vnotchSource("Aris/private/Aris/ArisController+Tasks.swift").contains("ArisCardReadLive.shared.shown(ask.id)"),
          "review-7 L1: wiring: the one place a card is answered refuses a pressed yes on an unread card, whatever sent it (the button, Y, Return)")
    check(card.contains("ArisCardReadLive.shared.scrolled(card: question.id, offset: $0, visible: $1, content: $2)") && card.contains("ArisCardEdit.allAccepted(question.fields, editor.values(for: question))) && read") && card.contains(".disabled(!ready)"),
          "review-7 L1: wiring: the card reports how far it has been scrolled, and its yes is disabled until its end has been on screen")
}

func runVNotchTests() {
    vnotchConstantTests()
    vnotchScaleTests()
    vnotchClosedTests()
    vnotchIndicatorTests()
    vnotchRestTests()
    vnotchEditTests()
    vnotchVoiceSwitchTests()
    vnotchGridSourceTests()
    vnotchEditReviewTests()
    vnotchCardReadTests()
}
