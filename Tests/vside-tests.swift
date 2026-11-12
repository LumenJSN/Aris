// Tests for the two surfaces restyled on 2026-11-11 (the owner, shown the differences: "ㅇㅇ
// 그래"): the side notch (ArisSideLook) and the pill's glass (ArisPillLook). The answer reader was brought there too
// and taken back the same night: seeing the two side by side the user kept Aris's own, and the last test here holds that.
// Each value is pinned to its number, and each fallback to what it draws: the public blur where a private glass
// part is missing or an older look is chosen, solid surfaces with Reduce Transparency, no motion with Reduce Motion.
// Called from main.swift; uses its check(). Nothing is drawn on screen: only the rules, the numbers and the sources.
import CoreGraphics
import Foundation

private typealias S = ArisSideLook
private typealias K = ArisPillLook

private func vsideSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func near(_ a: Double, _ b: Double, _ slack: Double = 0.0001) -> Bool { abs(a - b) < slack }

/// The side notch's material: its glass, wash and rim.
private func vsideMaterialTests() {
    check(near(S.glassTintBlue, 0.015) && near(S.glassTintAlpha, 0.9), "side glass: the tint is sRGB(0, 0, .015) at .9")
    check(near(S.washBlue, 6.0 / 255) && near(S.washAlpha, 0.95) && near(ArisGlassRecipe.sideWash(reduceTransparency: false), S.washAlpha),
          "side wash: rgba(0, 0, 6, .95), the content wash (it was .92)")
    check(near(S.rimRadius, 2) && near(S.rimPeak, 0.12), "side rim: a white shadow of radius 2 (it was 1), .12 at its strongest")
    check(near(S.rimOpacity(width: 16), 0.12) && near(S.rimOpacity(width: 18), 0.12), "side rim: full on the 16-point sliver and on the 18 it is under the pointer")
    check(near(S.rimOpacity(width: 0), 0) && near(S.rimOpacity(width: 1), 0.03) && near(S.rimOpacity(width: 4), 0.12),
          "side rim: it grows with the first 4 points of width as the sliver comes out (min(1, W/4))")
    check(near(S.rimOpacity(width: 30), 0.06) && near(S.rimOpacity(width: 42), 0) && near(S.rimOpacity(width: 232), 0),
          "side rim: it fades as the panel widens past 18 and is gone from 42 points, so the open panel has none (clamp((42 − W)/24))")
    check(near(S.rimOpacity(width: -5), 0), "side rim: a width under nothing is no rim")
}

/// Which material is under the wash: the private glass only through the top notch's own probe, else the public blur.
private func vsideFallbackTests() {
    var glassCount = 0
    for bits in 0..<32 {
        let parts = ArisGlassParts(glassView: bits & 1 != 0, variant: bits & 2 != 0, lensing: bits & 4 != 0, path: bits & 8 != 0, activeAppearance: bits & 16 != 0)
        let material = S.material(look: .privateGlass, parts: parts, reduceTransparency: false)
        if material == .glass { glassCount += 1 }
        check(material == (bits == 31 ? .glass : .blur), "side fallback: private parts \(bits) of 31 draw \(bits == 31 ? "the private glass" : "the public blur")")
        check(S.material(look: .privateGlass, parts: parts, reduceTransparency: true) == .solid,
              "side fallback: with Reduce Transparency nothing is under the wash, whatever parts \(bits) took")
    }
    check(glassCount == 1, "side fallback: only with every private part is the glass drawn")
    // Old hidden preference values (arisGlassLook) keep working: none of them reaches a private call on the side either.
    for look in ArisGlassLook.allCases where look != .privateGlass {
        check(S.material(look: look, parts: .all, reduceTransparency: false) == .blur && S.material(look: look, parts: .none, reduceTransparency: false) == .blur,
              "side fallback: the older look \(look.rawValue) keeps the public blur, with no private glass")
    }
    for name in ["floor", "mid", "before", "regular-glass", "clear-glass", "CLEAR-GLASS ", "nonsense", ""] {
        let look = ArisGlassLook(preference: name)
        check(S.material(look: look, parts: .all, reduceTransparency: false) == (look == .privateGlass ? .glass : .blur),
              "side fallback: the stored preference “\(name)” still chooses a look, and the side follows it")
    }
    check(ArisGlassRecipe.sideWash(reduceTransparency: true) == 1 && ArisGlassRecipe.pillFill(reduceTransparency: true) == 1,
          "reduce transparency: the side's wash and the pill's fill are solid")
}

/// The outline and the clocks: 44 points and their own curves (the fitted 180 ms curve is gone).
private func vsideMotionTests() {
    check(S.arcSamples == 10 && S.outlinePoints == 44, "side outline: 44 points, four arcs of 10 samples and four more (it was 52)")
    check(vsideSource("Aris/private/Aris/Design/ArisGlass.swift").contains("static let samples = 10\n"), "side outline: the outline is drawn with that count")
    check(S.opening == S.Timing(duration: 0.28, x1: 0.2, y1: 0.8, x2: 0.2, y2: 1), "side motion: the panel opens in 280 ms on (0.2, 0.8, 0.2, 1)")
    check(S.closing == S.Timing(duration: 0.2, x1: 0.45, y1: 0, x2: 0.55, y2: 1), "side motion: the panel closes in 200 ms on (0.45, 0, 0.55, 1)")
    check(S.sliver == S.Timing(duration: 0.18, x1: 0.4, y1: 0, x2: 0.2, y2: 1) && near(S.dotRevealDelay, 0.045),
          "side motion: the sliver comes and goes in 180 ms on (0.4, 0, 0.2, 1), its dots 45 ms in")
    let layers = vsideSource("Aris/private/Aris/Side/ArisSideLayers.swift")
    check(!layers.contains("0.25, 0.46, 0.45, 0.94") && !layers.contains("return 0.18"), "side motion: the 180 ms curve fitted from a recording is gone")
    check(layers.contains("case .opening: ArisSideLook.opening") && layers.contains("case .closing: ArisSideLook.closing") && layers.contains("case .sliver: ArisSideLook.sliver"),
          "side motion: wiring: each change runs on its own clock")
    check(layers.contains("if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return 0 }"), "reduce motion: the side notch changes at once")
    for timing in [S.opening, S.closing, S.sliver] {
        check(near(S.eased(0, timing), 0) && near(S.eased(1, timing), 1) && near(S.eased(-1, timing), 0) && near(S.eased(2, timing), 1),
              "side motion: the curve of \(Int(timing.duration * 1000)) ms starts at 0 and ends at 1")
        check(stride(from: 0.0, through: 0.95, by: 0.05).allSatisfy { S.eased($0, timing) <= S.eased($0 + 0.05, timing) + 1e-9 },
              "side motion: the curve of \(Int(timing.duration * 1000)) ms never goes backwards")
    }
    check(near(S.eased(0.5, S.closing), 0.5, 1e-6) && S.eased(0.5, S.opening) > 0.85, "side motion: closing is symmetric, opening is nearly there by halfway (CSS's cubic-bezier)")
    let opens = S.rimKeyframes(from: 18, to: 232, timing: S.opening), shows = S.rimKeyframes(from: 0, to: 16, timing: S.sliver)
    check(opens.count == 25 && near(opens[0], 0.12) && near(opens[24], 0) && zip(opens, opens.dropFirst()).allSatisfy { $0 >= $1 - 1e-9 },
          "side rim: opening, it falls from .12 to nothing along the opening's own clock")
    check(near(shows[0], 0) && near(shows[24], 0.12) && zip(shows, shows.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 }, "side rim: as the sliver comes out it rises to .12")
    check(layers.contains("ArisSideLook.rimKeyframes(from: from, to: to, timing: curve)") && layers.contains("rim.shadowRadius = ArisSideLook.rimRadius"),
          "side rim: wiring: the rim is laid along the morph frame by frame")
}

/// How the body is put together, by source: one glass through the top notch's gate, the wash over it, no blinking.
private func vsideWiringTests() {
    let layers = vsideSource("Aris/private/Aris/Side/ArisSideLayers.swift"), glass = vsideSource("Aris/private/Aris/Side/ArisSideGlass.swift")
    check(glass.contains("glass.style = .regular") && glass.contains("blue: ArisSideLook.glassTintBlue, alpha: ArisSideLook.glassTintAlpha")
          && glass.contains("ArisGlassPrivate.configure(glass)") && glass.contains("ArisGlassPrivate.setPath(glass, path)")
          && glass.contains("ArisGlassPrivate.forceActiveAppearance(window, on: true)"),
          "side glass: the top notch's glass, tinted, with its outline as path and the window's active look, each through the top notch's own gate")
    check(glass.contains("ArisGlassHealth.shared.failed(\\.variant)") && glass.contains("ArisGlassHealth.shared.failed(\\.lensing)")
          && glass.contains("ArisGlassHealth.shared.failed(\\.path)") && glass.contains("ArisGlassHealth.shared.failed(\\.activeAppearance)"),
          "side glass: a private part that does not take is told to the one record the top notch keeps")
    check(!layers.contains("NSSelectorFromString") && !glass.contains("NSSelectorFromString") && !glass.contains("_setPath") && !layers.contains("set_variant"),
          "side glass: no private name is written outside ArisGlassPrivate")
    check(layers.contains("ArisSideLook.material(look: ArisGlassLook.current(), parts: ArisGlassHealth.shared.parts,")
          && layers.contains("ArisGlassHealth.shared.$parts.dropFirst().sink") && layers.contains("if first || opening || force { chooseMaterial() }"),
          "side glass: the look's preference is read as the panel opens, and a part failing later turns the body to its blur")
    check(layers.contains("ArisGlassRecipe.sideWash(reduceTransparency: Self.reduceTransparency)") && layers.contains("blue: ArisSideLook.washBlue"),
          "side wash: drawn from those numbers, solid with Reduce Transparency")
    check(layers.contains("guard material != .glass else { return hideGlows() }"), "side glass: on the glass the open panel has no shadow of its own")
    check(layers.contains("layer.opacity = 1") && !layers.contains("repeatCount"), "house rule: the sliver's dots do not blink or pulse")
    let panels = vsideSource("Aris/private/Aris/Side/ArisSidePanels.swift"), view = vsideSource("Aris/private/Aris/Side/ArisSidePanelView.swift")
    check(panels.contains("\"arisSliverPosition.\" + edge.rawValue") && view.contains("@AppStorage(\"arisDebugRowFill\")"),
          "old preferences: where the sliver was dragged to, and the row-shape preview switch, are still read")
}

/// The panel's content: the header and list geometry.
private func vsideContentTests() {
    check(S.headerHeight == 91 && S.headerTop == 49 && S.headerEdgeSide == 14 && S.headerFarSide == 20 && S.headerPill == 36 && S.headerGap == 8,
          "side header: 91 tall, its 36-point pill 49 down, 14 from the edge and 20 from the far side, 8 before the lock")
    check(S.listTop == 95 && S.listFarSide == 13 && S.listEdgeSide == 7 && S.scrollEndPadding == 73,
          "side list: the first row starts 95 down (it was 93), rows run from 7 to 13 short of the far side, 73 clear at the end")
    check(S.fadeTopClear == 73 && S.fadeTopWhole == 105 && S.fadeBottom == 34 && S.listRise == 22,
          "side list: rows fade out between 105 and 73 as they slide under the header, and over the last 34 at the end")
    let under = S.listFade(height: 507, underHeader: true), plain = S.listFade(height: 300, underHeader: false)
    check(under.count == 4 && under[0] == S.FadeStop(location: 0, alpha: 0) && near(under[1].location * 507, 32) && under[1].alpha == 1
          && near((1 - under[2].location) * 507, 34) && under[3] == S.FadeStop(location: 1, alpha: 0),
          "side list: a list under the header is clear at its top, whole 32 points down, and fades over its last 34")
    check(plain.count == 3 && plain[0].alpha == 1 && near((1 - plain[1].location) * 300, 34) && plain[2].alpha == 0,
          "side list: a list under something else keeps its top whole and fades over its last 34 points, whatever its height (it was a share of the height)")
    check(S.listFade(height: 0, underHeader: true).allSatisfy { $0.alpha == 1 } && S.listFade(height: 40, underHeader: true).first?.alpha == 1,
          "side list: a list with no room, or too short for both fades, is never masked away")
    // Side 1 ("the text gets cut off"): a list that runs to the panel's frame is gone at the body's lower edge, 31
    // above the frame, where the outline would otherwise cut through a row's words.
    let edge = S.listFade(height: 507, underHeader: true, below: Double(S.bodyEdgeInset))
    check(S.bodyEdgeInset == 31 && edge.count == 5 && near(edge[3].location * 507, 507 - 31) && edge[3].alpha == 0 && edge[4] == S.FadeStop(location: 1, alpha: 0)
          && near(edge[2].location * 507, 507 - 31 - 34) && edge[2].alpha == 1,
          "side list (side 1): a list that reaches the panel's frame fades over the 34 points above the body's lower edge and is gone on it")
    check(S.scrollEndPadding - S.bodyEdgeInset > S.fadeBottom, "side list (side 1): scrolled to its end, the last row stands clear of that fade (73 − 31 > 34)")
    let frame = vsideSource("Aris/private/Aris/Side/ArisSidePanelView.swift")
    check(frame.contains("below: toEdge ? ArisSideLook.bodyEdgeInset : 0"), "side list (side 1): wiring: the lists that run to the edge fade out on the body's edge")
    let usage = vsideSource("Aris/private/Aris/Side/ArisUsageCard.swift")
    check(!usage.contains("frame(maxWidth: 120") && usage.contains(".lineLimit(1).fixedSize().layoutPriority(1)\n                Spacer(minLength: 8)\n                if let account"),
          "usage tab (side 1): who is signed in takes the room on its line (it was held to 120 points), the provider's name is always whole")
    check(usage.contains("Text(updated).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))\n                    .lineLimit(1).fixedSize().layoutPriority(1)"),
          "usage tab (side 1): when the numbers were read stays on one line whatever the plan's name is")
    check(S.emptySize == 12 && near(S.emptyAlpha, 0.52) && S.emptyInsets.top == 28 && S.emptyInsets.side == 18 && S.emptyInsets.bottom == 30,
          "side empty state: 12 at white .52, 28 above, 18 beside and 30 below")
    check(S.searchSize == 15 && S.searchLine == 22 && near(S.searchAlpha, 0.95) && near(Double(S.searchPlaceholderTracking), 0.2),
          "side search: 15 on a 22 line at white .95, the placeholder tracked 0.2")
    let view = vsideSource("Aris/private/Aris/Side/ArisSidePanelView.swift")
    check(view.contains("spacing: ArisSideLook.listTop - ArisSideLook.headerTop - ArisSideLook.headerPill") && view.contains(".padding(.top, ArisSideLook.headerTop)")
          && view.contains(".background(ArisSideStyle.pill(Capsule(), drop: false))") && view.contains(".zIndex(1)"),
          "side header: wiring: the panel is laid out from those numbers, the pill has no outer drop, and the header stays above the list")
    for (file, call) in [("Side/ArisLeftPanel.swift", "ArisSideListFrame(underHeader: true, toEdge: true)"), ("ArisTodoView.swift", "ArisSideListFrame(underHeader: true, toEdge: true)"),
                         ("Side/ArisUsageCard.swift", "ArisSideListFrame(underHeader: false, toEdge: true)"), ("Side/ArisActivityView.swift", "ArisSideListFrame(underHeader: false, toEdge: false)")] {
        check(vsideSource("Aris/private/Aris/" + file).contains(call), "side list: wiring: \(file) draws its list with the shared frame and fades")
    }
    for file in ["Side/ArisLeftPanel.swift", "ArisTodoView.swift", "Side/ArisUsageCard.swift", "Side/ArisActivityView.swift", "Side/ArisRightPanel.swift", "ArisClipboardView.swift"] {
        check(vsideSource("Aris/private/Aris/" + file).contains("ArisSideStyle.empty("), "side empty state: wiring: \(file) says nothing is there in one style")
    }
}

/// The pill's glass: the dictation pill's fill, ring and blur.
private func vsidePillTests() {
    check(near(K.fillTop.red, 22.0 / 255) && near(K.fillTop.blue, 27.0 / 255) && near(K.fillBottom.red, 12.0 / 255) && near(K.fillBottom.blue, 15.0 / 255)
          && near(ArisGlassRecipe.pillFill(reduceTransparency: false), 0.96),
          "pill fill: rgba(22,22,27) to rgba(12,12,15) at .96 (it was .92)")
    check(near(K.ringWidth, 1) && near(K.ringBase, 0.07) && K.ringStops.map(\.location) == [0, 0.3, 0.6] && K.ringStops.map(\.alpha) == [0.28, 0.08, 0]
          && near(K.ringReach, 2.0.squareRoot()),
          "pill border: a 1-point ring, white .07 lit to .28 at the top left and bottom right corners (it was an even .08)")
    check(near(K.radius, 24) && near(K.backdropBlur, 14) && near(K.shadowOpacity, 0), "pill: radius 24 in every state, a 14-point blur behind, and no shadow")
    let bubble = vsideSource("Aris/private/Aris/Team/ArisBubbleView.swift"), pill = vsideSource("Aris/private/Aris/Team/ArisPillView.swift")
    check(bubble.contains("ArisGlassRecipe.pillFill(reduceTransparency: reduceTransparency)") && bubble.contains("highlight(at: .topLeading)")
          && bubble.contains("highlight(at: .bottomTrailing)") && bubble.contains("ArisPillLook.ringBase"),
          "pill: wiring: the glass is drawn from those numbers")
    check(bubble.contains("if !reduceTransparency {\n                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).clipShape(shape)"),
          "reduce transparency: the pill has no blur behind it and a solid fill")
    check(!bubble.contains(".shadow(color: .black.opacity(0.28)") && !pill.contains(".shadow(color: .black.opacity(0.28)") && !bubble.contains(".white.opacity(0.08)"),
          "pill: the shadow and the even border Aris drew are gone from the pill and the bubble")
    check(vsideSource("Aris/private/Aris/Team/ArisStatusPill.swift").contains("PillEntry(opacity: 0, scale: 0.985, y: -4)"),
          "pill: it still comes down from the notch on the notch's clock, which the star's hop is timed to (Aris's own, kept)")
}

/// The reader is Aris's own. A restyled reader was tried beside it on 2026-11-11 and the user said Aris's is better
/// ("아리스가 낫은데?"), so it was taken out again: this holds it out. Do not re-apply those reader values.
private func vsideReaderStaysArisTests() {
    let view = vsideSource("Aris/private/Aris/ArisReaderView.swift"), body = vsideSource("Aris/private/Aris/ArisReaderBody.swift")
    let board = vsideSource("Aris/private/Aris/ArisBoard.swift")
    check(view.contains("static let size = CGSize(width: 620, height: 428)") && view.contains("static let tallest: CGFloat = 640")
          && board.contains("styleMask: [.nonactivatingPanel, .borderless, .resizable]") && board.contains("panel.level = .floating"),
          "reader stays Aris's: a floating borderless panel, 620 × 428 growing to 640 (not a 960 × 780 titled window)")
    check(board.contains("ArisBoardContent.readerHeight(needed: ArisReaderView.neededHeight(document, width: width),"),
          "reader stays Aris's: the panel grows to fit an answer a little taller than it")
    check(body.contains("static let size: CGFloat = 14") && body.contains("static let textColor = Color.white.opacity(0.86)"),
          "reader stays Aris's: 14 on a 1.7 line at white .86 (not 16 in #ececec)")
    check(view.contains("ArisReaderButton(symbol: \"xmark\", label: nil)") && view.contains(".scaleEffect(presence.shown ? 1 : 0.965, anchor: .top)")
          && view.contains("VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)"),
          "reader stays Aris's: its bar's ✕, its glass ground, and its present and dismiss motion")
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Aris/private/Aris")
    check(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("ArisReaderLook.swift").path)
          && !FileManager.default.fileExists(atPath: folder.appendingPathComponent("ArisReaderBlocks.swift").path)
          && !view.contains("212121") && !body.contains("ececec"),
          "reader stays Aris's: the tried reader's values (#212121, #ececec, its own blocks) are not in the app")
}

/// Side 3 ("the category switch feels like a hard cut"): the highlight and the page on one 180 ms clock, the
/// highlight's curve the quicker, the page blurring across; nothing moves for a change no press made.
private func vsideTabSwitchTests() {
    let swap = vsideSource("Aris/private/Aris/Side/ArisTabSwap.swift"), tabs = vsideSource("Aris/private/Aris/Side/ArisSlidingTabs.swift")
    check(swap.contains("static let slide = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)"),
          "tab switch: the highlight slides in 180 ms on (0.22, 1, 0.36, 1) (it was a 300 ms spring, still gliding when the page had changed)")
    check(swap.contains("static let fade = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.18)") && swap.contains("static let blur: CGFloat = 2"),
          "tab switch: the page crossfades in 180 ms on (0.22, 0.61, 0.36, 1) through a 2-point blur (it was 220 ms on a curve four fifths done in 70 ms)")
    check(!swap.contains("Animation.spring") && !swap.contains("timingCurve(easeOut") && !swap.contains("static let shift") && !swap.contains(".offset(x:"),
          "tab switch: the spring, the front-loaded curve and the sideways shift are gone")
    check(swap.contains("AnyTransition.modifier(active: ArisTabPage(blur: blur, opacity: 0), identity: ArisTabPage(blur: 0, opacity: 1))")
          && swap.contains(".transition(Self.swap)"),
          "tab switch: the old page leaves as the new one comes, on one curve, so their opacities always add up to one")
    check(swap.contains("guard ArisTabPress.pressed else { return .identity }") && tabs.contains("ArisTabMotion.reduceMotion || !ArisTabPress.pressed ? nil : ArisTabMotion.slide"),
          "tab switch: a tab changed without a press on it (a shortcut, a chip, settings) is shown at once; with Reduce Motion the highlight jumps")
    check(swap.contains("let blur = ArisTabMotion.reduceMotion ? 0 : ArisTabMotion.blur"), "reduce motion: the page only fades")
    let panels = vsideSource("Aris/private/Aris/Side/ArisSidePanels.swift")
    check(panels.components(separatedBy: "ArisTabPress.changedWithoutPress()").count == 3,
          "tab switch: wiring: opening a panel on a tab, and a tab turned off in settings, both change the tab without motion")
    let right = vsideSource("Aris/private/Aris/Side/ArisRightPanel.swift"), demo = vsideSource("Aris/private/Aris/Side/ArisSideDemo.swift")
    check(right.contains("@State private var events: [ArisCalendarEvent] = ArisAgendaMemory.events ?? []") && right.contains("@State private var loading = ArisAgendaMemory.events == nil")
          && right.contains("ArisAgendaMemory.events = result"),
          "tab switch: the 캘린더 tab comes back with the timetable it last showed, not empty behind a spinner")
    check(demo.contains("ArisAgendaMemory.events = nil") && right.contains("guard calendar.access == .fullAccess else { events = []; ArisAgendaMemory.events = nil; return }"),
          "tab switch: those remembered events are dropped when the demo turns on or off and when calendar access goes")
}

/// Side 2 (a history row used to say only 이어서 말해 주세요): a row now puts that turn
/// back in the notch, with its card as it was, and never listens or asks to go on.
private func vsideHistoryRestoreTests() {
    typealias H = ArisHistoryRestore
    let when = Date(timeIntervalSince1970: 1_794_000_000)
    let entry = ArisHistoryEntry(date: when, heard: "올랜도 날씨 어때", reply: "지금 **3도**이고 흐려요.\n\n- 오후에 비", sawScreen: true)
    let shown = H.shown(entry, english: false)
    check(shown.id == entry.id && shown.date == when && shown.heard == entry.heard && shown.reply == entry.reply,
          "history restore: the notch gets the row's own words and its whole answer, markdown and all")
    let empty = ArisHistoryEntry(date: when, heard: "뭐였더라", reply: "  \n")
    check(H.reply(of: empty, english: false) == "이 대화는 저장된 답이 없어요." && H.reply(of: empty, english: true) == "No answer was saved for this conversation.",
          "history restore: a row with no saved answer says so, never a made-up one")
    let parked = ArisSession.parked(heard: shown.heard, reply: shown.reply)
    check(shown.isOn(parked) && parked.question == nil && parked.tags.isEmpty && parked.phase == .idle,
          "history restore: the turn is shown finished and idle: no card that asks, no activity tags, nothing running")
    check(!shown.isOn(parked.listening()) && !shown.isOn(ArisSession()) && !shown.isOn(.parked(heard: shown.heard, reply: "다른 답")),
          "history restore: the line saying when it was goes with the turn (a new turn, 닫기 or another answer ends it)")
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let later = when.addingTimeInterval(86_400)
    check(H.caption(when, now: later, timeZone: utc.timeZone, english: false).hasPrefix("기록 · 어제 ")
          && H.caption(when, now: later, timeZone: utc.timeZone, english: true, locale: Locale(identifier: "en_US")).hasPrefix("History · Yesterday, "),
          "history restore: the line over the turn says it is from the history and when, in the 기록 tab's own words")
    // The card: saved with its turn once its values arrive, and read back as it was.
    let weather = ArisWeatherCard(place: "올랜도", temp: 3, code: 3, day: true, high: 6, low: -1, hours: [.init(label: "지금", code: 3, temp: 3, day: true)])
    let card = ArisHistoryCard(request: ArisWidgetRequest(kind: .weather, place: "올랜도"), values: .weather(weather))
    let other = ArisHistoryEntry(date: when, heard: "환율", reply: "1,380원이에요.")
    let file = ArisHistoryEntry(date: when, heard: "자료 정리", reply: entry.reply, file: "/tmp/x.md", isTask: true)
    let kept = H.attaching(card, toReply: entry.reply, in: [other, file, entry])
    check(H.card(of: kept[2]) == card && kept[0].card == nil && kept[1].card == nil && kept.count == 3,
          "history restore: a card's values are kept on the turn whose answer they came with (never on a saved result, never on another turn)")
    check(H.attaching(card, toReply: "없는 답", in: [other, entry]) == [other, entry] && H.attaching(card, toReply: entry.reply, in: kept) == kept,
          "history restore: with no such turn, or once it has its card, nothing changes")
    check(card.request == ArisWidgetRequest(kind: .weather, place: "올랜도") && ArisHistoryCard(request: ArisWidgetRequest(kind: .stock, symbol: "AAPL"), values: .weather(weather)).request?.symbol == "AAPL",
          "history restore: the card remembers what it was asked for (the place, the symbol)")
    let encoded = (try? JSONEncoder().encode(kept)) ?? Data()
    check((try? JSONDecoder().decode([ArisHistoryEntry].self, from: encoded)) == kept, "history restore: a turn with its card survives being saved and read back")
    let old = Data(#"[{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","date":700000000,"heard":"옛날 질문","reply":"옛날 답","isTask":false}]"#.utf8)
    let read = (try? JSONDecoder().decode([ArisHistoryEntry].self, from: old)) ?? []
    var unreadable = entry
    unreadable.card = Data("not a card".utf8)
    check(H.card(of: unreadable) == nil && H.card(of: entry) == nil, "history restore: a card that cannot be read, or none, is no card (never a guess)")
    check(read.count == 1 && read[0].card == nil && H.reply(of: read[0], english: false) == "옛날 답",
          "history restore: a history saved before cards were kept still reads, and its rows show as their words and answer")
    let controller = vsideSource("Aris/private/Aris/ArisController.swift")
    let resume = controller.components(separatedBy: "func resume(_ entry: ArisHistoryEntry) {").dropFirst().first?.components(separatedBy: "\n    }\n").first ?? ""
    check(resume.contains("session = .parked(heard: shown.heard, reply: shown.reply)") && resume.contains("ArisWidgetModel.shared.restore(ArisHistoryRestore.card(of: entry), reply: shown.reply)")
          && resume.contains("NotificationCenter.default.post(name: .arisHistoryRestored, object: nil)") && resume.contains("restored = shown"),
          "history restore: wiring: a pressed row puts the turn, its card and when it was in the notch and asks the notch to open")
    check(!resume.contains("startListening()") && !resume.contains("listenHandsFree()") && !controller.contains("resumedFrom"),
          "history restore: a pressed row no longer opens the microphone, and the 이어서 말해 주세요 placeholder's state is gone")
    check(resume.contains("history = [ArisContext.Turn(heard: entry.heard, reply: entry.reply)]") && resume.contains("freshConversation = true")
          && resume.contains("screenConversation = entry.sawScreen == true") && resume.contains("outsideConversation = entry.sawOutside == true"),
          "history restore: the next thing said or typed carries that turn as its context, to a new session of whichever AI answers, with the turn's screen and outside-text marks")
    for file in ["Aris/private/Aris/Home/ArisTurnView.swift", "Aris/private/Aris/ArisPanel.swift"] {
        check(!vsideSource(file).contains("이어서 말해 주세요"), "history restore: \(file) no longer shows 이어서 말해 주세요 in place of the conversation")
    }
    let widgets = vsideSource("Aris/private/Aris/ArisWidgetModel.swift")
    check(widgets.contains("current = Shown(reply: reply, request: request, untrusted: true, content: Self.content(card.values))"),
          "history restore: a restored card is history: it is shown with its buttons off")
    check(widgets.contains("case .timer, .music, .permission: nil") && widgets.contains("ArisController.shared.keepCard(card, forReply: reply)"),
          "history restore: the timer's, the music's and a permission's cards show what is so now and are not kept; the others are, once their values arrive")
    let root = vsideSource("Aris/private/Notch/ArisNotchRoot+Behaviour.swift")
    check(root.contains("guard pointerIsHere, !approvalsPending, !hidden else { return }\n        navigation.currentView = .home\n        if closed { open() }")
          && root.contains("publisher(for: .arisHistoryRestored)) { _ in root.historyRestored() }"),
          "history restore: wiring: the notch on the pointer's display opens on the turn, without taking the keyboard")
    check(vsideSource("Aris/private/Aris/Home/ArisHomeView.swift").contains("ArisRestoredCaption()")
          && vsideSource("Aris/private/Aris/Home/ArisRestoredCaption.swift").contains("if let restored = aris.restored, restored.isOn(aris.session)"),
          "history restore: wiring: the line saying when it was sits over the restored turn only")
}

func runVSideTests() {
    vsideHistoryRestoreTests()
    vsideTabSwitchTests()
    vsideMaterialTests()
    vsideFallbackTests()
    vsideMotionTests()
    vsideWiringTests()
    vsideContentTests()
    vsidePillTests()
    vsideReaderStaysArisTests()
}
