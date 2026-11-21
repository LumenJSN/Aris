// Tests for the notice pill's line <-> card motion (2026-11-16, Emil Kowalski's rules): the hover intent (100 ms before
// the card opens, 150 ms of grace before it folds, a pointer back within the grace keeps it), the morph as one function of
// its progress (the size to a measured height, the crossfade never showing two layouts at once, the blur and rise, the
// mark and a shared title held in place), the springs (closed form, timings against the crossfade), the press feedback,
// Reduce Motion, and the wiring. Called from notice-pill-tests.swift; uses main.swift's check(). Nothing is drawn.
import CoreGraphics
import Foundation

private typealias P = ArisNoticePillLayout
private typealias Morph = ArisNoticePillMorph
private typealias Intent = ArisNoticeHoverIntent

private func motionSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The pointer's moves (seconds, the notice under it or nil) played through the intent as ArisNoticeCenter does:
/// each move cancels the running wait and may start one; a wait that runs out settles. What the card shows, sampled.
private func playIntent(_ moves: [(Double, UUID?)], sampleAt times: [Double]) -> [UUID?] {
    var intent = Intent()
    var due: Double?
    var events = moves.sorted { $0.0 < $1.0 }
    var shown: [UUID?] = []
    for sample in times.sorted() {
        while true {
            let nextMove = events.first?.0 ?? .infinity
            let nextWait = due ?? .infinity
            let next = min(nextMove, nextWait)
            guard next <= sample else { break }
            if nextWait <= nextMove {
                intent = intent.settled()
                due = nil
            } else {
                let (moved, wait) = intent.pointing(at: events.removeFirst().1)
                intent = moved
                due = wait.map { next + $0 }
            }
        }
        shown.append(intent.expanded)
    }
    return shown
}

func runNoticePillMotionTests() {
    // --- the numbers, each from Emil's rules
    check(P.expand >= 0.32 && P.expand <= 0.36 && P.expandBounce > 0 && P.expandBounce <= 0.1,
          "pill motion: the grow is a 0.32-0.36 s spring with very little bounce (≤ .1)")
    check(abs(P.collapse - 0.22) < 1e-9 && P.collapseBounce == 0 && P.collapse < P.expand,
          "pill motion: the fold is a 0.22 s spring with no bounce, faster than the grow")
    check(P.hoverIntent == 0.1 && P.hoverGrace == 0.15, "pill motion: 100 ms of intent before the card, 150 ms of grace before it folds")
    check(P.pressScale == 0.97 && P.press >= 0.1 && P.press <= 0.16 && P.pressDim < 1, "pill motion: a press scales to .97 in 100-160 ms (Reduce Motion dims)")
    check(P.cardBlur > 0 && P.cardBlur <= 2 && P.cardRise >= 2 && P.cardRise <= 4, "pill motion: the card's text comes in from ≤ 2 pt of blur, rising 2-4 pt")
    check(P.lineFadeEnd < P.cardFadeStart && P.cardFadeStart < P.cardFadeEnd && P.cardFadeEnd <= 1,
          "pill motion: the line's rest is gone before the card's text starts (masked, never both)")
    check(P.reducedFade == P.contentFade, "pill motion: Reduce Motion crossfades in the content's own 150 ms")

    // --- the springs (Apple's duration / bounce form)
    let grow = { (t: Double) in P.spring(t, duration: P.expand, bounce: P.expandBounce) }
    let fold = { (t: Double) in P.spring(t, duration: P.collapse, bounce: P.collapseBounce) }
    check(grow(0) == 0 && fold(0) == 0 && grow(-1) == 0, "pill spring: starts at 0, at rest")
    check(grow(P.expand) > 0.98 && fold(P.collapse) > 0.98 && grow(1) > 0.9999 && fold(1) > 0.9999,
          "pill spring: 98 % there by its (perceptual) duration, settled after")
    let peak = (0...1000).map { grow(Double($0) / 1000) }.max() ?? 0
    check(peak > 1 && peak < 1.002, "pill spring: the grow's bounce passes 1 by under 0.2 % (no visible overshoot)")
    let foldSteps = (0...600).map { fold(Double($0) / 1000) }
    check(zip(foldSteps, foldSteps.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 } && (foldSteps.max() ?? 2) <= 1,
          "pill spring: the fold never overshoots (no bounce)")
    check(grow(0.1) >= Double(P.lineFadeEnd), "pill spring: the line's rest is gone within ~100 ms of the grow")
    let lineGone = (0...400).first { grow(Double($0) / 1000) >= Double(P.lineFadeEnd) } ?? 400
    let cardStarts = (0...400).first { grow(Double($0) / 1000) >= Double(P.cardFadeStart) } ?? 0
    check(cardStarts > lineGone && cardStarts <= 120, "pill spring: the card's text starts after a short delay (\(cardStarts) ms), after the line's rest went (\(lineGone) ms)")
    let cardGone = (0...300).first { 1 - fold(Double($0) / 1000) <= Double(P.cardFadeStart) } ?? 300
    check(cardGone <= 80, "pill spring: folding, the card's text is gone within 80 ms (\(cardGone) ms)")

    // --- the morph: one function of the progress
    let line = Morph(progress: 0), card = Morph(progress: 1), half = Morph(progress: 0.5)
    check(line.size(collapsed: 284, card: 180) == CGSize(width: 284, height: 38) && card.size(collapsed: 284, card: 180) == CGSize(width: 364, height: 180)
          && half.size(collapsed: 284, card: 180) == CGSize(width: 324, height: 109),
          "pill morph: the line's width × 38 to 364 × the card's measured height, half-way half-way")
    check(card.size(collapsed: 440, card: 120).width == 364 && Morph(progress: 0.5).size(collapsed: 440, card: 120).width == 402,
          "pill morph: a 440 line narrows to the 364 card")
    check(line.size(collapsed: 284, card: 180, arrival: 0) == P.barSize && line.size(collapsed: 284, card: 180, arrival: 0.5) == CGSize(width: 160, height: 23),
          "pill morph: arriving, from the 36 × 8 bar")
    check(line.lineOpacity == 1 && line.cardOpacity == 0 && card.lineOpacity == 0 && card.cardOpacity == 1,
          "pill morph: the line all line, the card all card")
    let sweep = (0...1000).map { Morph(progress: CGFloat($0) / 1000) }
    check(sweep.allSatisfy { $0.lineOpacity == 0 || $0.cardOpacity == 0 }, "pill morph: never the line's rest and the card's text at once")
    check(sweep.allSatisfy { $0.cardBlur >= 0 && $0.cardBlur <= P.cardBlur && $0.cardRise >= 0 && $0.cardRise <= P.cardRise }
          && line.cardBlur == 0 && card.cardBlur == 0 && card.cardRise == 0,
          "pill morph: blur ≤ 2 only while the card comes in (none unseen, none once there), rise ≤ 3 to 0")
    check(line.headerTop == 9 && card.headerTop == 10 && Morph(progress: 1.001).headerTop == 10 && Morph(progress: -0.001).headerTop == 9,
          "pill morph: the mark sits 9 down on the line (centred in 38), 10 on the card (its padding), never past either")
    var jump: CGFloat = 0
    for (a, b) in zip(sweep, sweep.dropFirst()) {
        let sa = a.size(collapsed: 284, card: 200), sb = b.size(collapsed: 284, card: 200)
        jump = max(jump, abs(sb.height - sa.height), abs(sb.width - sa.width), abs(b.headerTop - a.headerTop),
                   100 * abs(b.lineOpacity - a.lineOpacity), 100 * abs(b.cardOpacity - a.cardOpacity))
    }
    check(jump < 0.4, "pill morph: no jump anywhere (a thousandth of progress moves nothing more than \(jump))")
    let over = Morph(progress: 1.0006)
    check(over.cardOpacity == 1 && over.lineOpacity == 0 && over.cardBlur == 0, "pill morph: past 1 on the bounce, the opacities hold")
    check(!Morph(progress: 0.6).cardLive && Morph(progress: 0.8).cardLive, "pill morph: the card takes clicks once it is more than half there")
    check(ArisNoticePillPhase.radius(height: half.size(collapsed: 284, card: 180).height) == 24
          && ArisNoticePillPhase.radius(height: Morph(progress: 0.05).size(collapsed: 284, card: 180).height) < 24,
          "pill morph: the corner follows the height, 19 to 24")

    // --- the title kept in place
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let mail = ArisNotice(kind: .incoming, title: "김지원", body: "내일 오후 3시에 리뷰 괜찮을까요?", posted: now)
    let due = ArisDue(id: "8", course: "CSC209H1", title: "Lab 4", at: now.addingTimeInterval(9_000), url: "https://q.exampleu.edu/x")
    let deadline = ArisNoticeRoute.deadline(due, .hoursBefore, now: now, english: false)
    let wide = ArisNotice(kind: .done, title: String(repeating: "보고서 ", count: 30), body: "", posted: now)
    check(ArisNoticePillFit.sharesTitle(mail, now: now, english: false), "pill title: a notice's title is drawn once, the same in the line and the card")
    check(!ArisNoticePillFit.sharesTitle(deadline, now: now, english: false), "pill title: a deadline leads its line with what is due, so its two crossfade")
    check(!ArisNoticePillFit.sharesTitle(wide, now: now, english: false) && P.cardTitleRoom == 282,
          "pill title: a title cut in either (the card's room is 282) crossfades instead of jumping its cut")

    // --- the hover intent
    let a = UUID(), b = UUID()
    let (resting, wait) = Intent().pointing(at: a)
    check(wait == P.hoverIntent && resting.pointer == a && resting.expanded == nil && resting.settled().expanded == a,
          "pill intent: the pointer on it, the card opens after 100 ms")
    let (brushed, brushWait) = resting.pointing(at: nil)
    check(brushWait == nil && brushed.expanded == nil && brushed.settled().expanded == nil, "pill intent: brushing past (gone before 100 ms) never opens it")
    let open = resting.settled()
    let (leaving, grace) = open.pointing(at: nil)
    check(grace == P.hoverGrace && leaving.expanded == a && leaving.settled().expanded == nil, "pill intent: off it, the card folds after 150 ms")
    let (back, backWait) = leaving.pointing(at: a)
    check(backWait == nil && back.expanded == a && back.settled().expanded == a, "pill intent: back within the grace, the fold is cancelled")
    check(open.pointing(at: a).wait == nil && open.pointing(at: a).intent == open, "pill intent: told again it is on it, nothing changes")
    check(open.pointing(at: b).wait == P.hoverIntent && open.pointing(at: b).intent.settled().expanded == b,
          "pill intent: on another notice, it waits its 100 ms again")
    check(Intent().pointer == nil && Intent().expanded == nil, "pill intent: idle is nothing under the pointer, no card")
    // played out in time, as the center runs it
    check(playIntent([(0, a), (0.06, nil)], sampleAt: [0.05, 0.1, 0.2, 1]) == [nil, nil, nil, nil], "pill intent in time: a 60 ms brush never opens it")
    check(playIntent([(0, a)], sampleAt: [0.09, 0.11, 1]) == [nil, a, a], "pill intent in time: resting, it opens at 100 ms")
    check(playIntent([(0, a), (0.5, nil), (0.6, a)], sampleAt: [0.55, 0.62, 0.7, 2]) == [a, a, a, a],
          "pill intent in time: off for 100 ms and back, it never folds")
    check(playIntent([(0, a), (0.5, nil)], sampleAt: [0.6, 0.64, 0.66, 2]) == [a, a, nil, nil], "pill intent in time: off it, it folds at 150 ms")
    check(playIntent([(0, a), (0.5, nil), (0.55, a), (0.6, nil), (0.62, a), (0.7, nil)], sampleAt: [0.8, 0.84, 0.86]) == [a, a, nil],
          "pill intent in time: an edge that flickers in and out keeps it open; the grace counts from the last exit")

    // --- the wiring
    let view = motionSource("Aris/private/Aris/Notice/ArisNoticePillView.swift")
    let morphView = motionSource("Aris/private/Aris/Notice/ArisNoticePillMorphView.swift")
    let center = motionSource("Aris/private/Aris/Notice/ArisNoticeCenter.swift")
    let tokens = motionSource("Aris/private/Aris/Notice/ArisNoticePill.swift")
    check(view.contains("ArisNoticePillMorphing(arrival: arrived ? 1 : 0, progress: progress, collapsedWidth: collapsedWidth)")
          && !view.contains("card.transition(.opacity)") && !view.contains("row.transition(.opacity)") && !view.contains("height: size.height"),
          "pill wiring: one sprung progress draws both, no plain opacity swap, no height to nil")
    check(morphView.contains("struct ArisNoticePillMorphing<Content: View>: View, Animatable") && morphView.contains("AnimatablePair(arrival, progress)")
          && morphView.contains("ProposedViewSize(width: ArisNoticePillLayout.expandedWidth, height: nil)")
          && morphView.contains("ArisNoticePillMorph(progress: progress).size(collapsed: collapsedWidth, card: card, arrival: arrival)"),
          "pill wiring: the layout measures the card at 364 and sizes the pill to a number between line and card")
    check(view.contains(".layoutValue(key: ArisNoticePillCardKey.self, value: true)") && view.contains(".blur(radius: reduceMotion ? 0 : morph.cardBlur)")
          && view.contains(".offset(y: reduceMotion ? 0 : morph.cardRise)") && view.contains(".allowsHitTesting(morph.cardLive)")
          && view.contains(".padding(.top, morph.headerTop)"),
          "pill wiring: the card layer is the one measured; it blurs and rises in (not with Reduce Motion) and takes clicks once there; the header stays")
    check(view.components(separatedBy: "markRoom").count - 1 == 3 && view.components(separatedBy: "\n            mark\n").count - 1 == 1,
          "pill wiring: the mark is drawn once (the header), the layers keep only its room (the star has one seat)")
    check(view.components(separatedBy: ".buttonStyle(ArisNoticePillPressStyle())").count - 1 == 2 && !view.contains(".buttonStyle(.plain)")
          && morphView.contains("pressed && !reduceMotion ? ArisNoticePillLayout.pressScale : 1"),
          "pill wiring: the buttons and the ✕ press to .97 (dim with Reduce Motion)")
    check(view.contains(".animation(fade, value: reduceMotion ? progress : 0)") && view.contains("Animation.easeOut(duration: L.reducedFade)"),
          "pill wiring: Reduce Motion: the size at once, only the opacity in 150 ms")
    check(center.contains("let (next, wait) = intent.pointing(at: id)") && center.contains("self.intent = self.intent.settled()")
          && center.contains("try? await Task.sleep(for: .seconds(wait))") && center.contains("if stepAside { dropHover() }"),
          "pill wiring: the center waits out the intent; stepping aside drops it")
    check(tokens.contains("Emil Kowalski") && tokens.contains("static let hoverGrace: Double = 0.15") && tokens.contains("static let cardBlur: CGFloat = 2"),
          "pill tokens: the new numbers live in the Motion section, each with where it comes from")
}
