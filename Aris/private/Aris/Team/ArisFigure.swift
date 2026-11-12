//
//  ArisFigure.swift
//  Aris
//
//  One teammate out of the notch: its character (a 28-point box hosting ArisCharacterView, the view the travel
//  animator moves) and its bubble, both in the overlay panels (ArisOverlayPanels). The director (ArisDirector) decides;
//  this only places, travels, shows and hides. Nothing here runs per frame: travel is on the render server, the sprite
//  is baked, and a follow is one frame move when the window moves.
//

import AppKit
import Defaults
import SwiftUI

/// What the figure's two views show; they observe it, so a change never rebuilds a hosting view.
@MainActor
final class ArisFigureModel: ObservableObject {
    /// ArisCharacterMood's raw state: "working" while the job runs, "default" once it's done (the poke plays from idle).
    @Published var mood = "working"
    @Published var pokes = 0
    @Published var text: String?
    @Published var tone: ArisBubbleTone = .working
    @Published var bubbleShown = false
    @Published var side: ArisBubbleSide = .right
    /// The bubble speaks the job's language (from its title).
    var korean = true
    /// The letter-by-letter reveal under way (once, the first time the bubble shows after landing).
    @Published var revealFrom: Date?
    var revealed = false
}

@MainActor
final class ArisFigure {
    /// The bubble's host: as wide as the longest bubble (24 letters, the check) and tall enough for its shadow.
    static let bubbleHostWidth: CGFloat = 320
    static let bubbleInset: CGFloat = 12
    static let bubbleHostHeight: CGFloat = 48

    let id: UUID
    let look: ArisCharacterLook
    let model = ArisFigureModel()
    let animator = ArisTravelAnimator()
    let pid: Int32
    let windowNumber: Int
    /// The window's title bar height (ArisTitleBarProbe), read once when it goes out: never per frame.
    var titleBarHeight: CGFloat?
    var follower: ArisWindowFollower?
    /// Where it rests now (the character's centre, screen coordinates), and the window it sits on (AppKit).
    private(set) var perch: CGPoint?
    private(set) var window: CGRect?
    /// On its way somewhere: a window move waits for the landing, and so does the end of its job.
    private(set) var travelling = false
    var pendingPerch: (point: CGPoint, window: CGRect)?
    /// How its job ended, while that waits for the landing (ArisCast's `.onLanding`).
    var ending: ArisJobState?

    private let character: NSHostingView<ArisFigureCharacter>
    private let bubble: NSHostingView<ArisFigureBubble>
    private let size = ArisCharacterDirector.perchSize
    /// The panels it was put in (the director's).
    private weak var seatedIn: ArisOverlayPanels?
    /// Notch-close, 200 ms (0.45, 0, 0.55, 1): the bubble tucks away.
    private static let closing = Animation.timingCurve(0.45, 0, 0.55, 1, duration: ArisCharacterDirector.mergeFade)

    /// `aris`: Aris's own job (a clone): it wears Aris's face, live.
    init(id: UUID, look: ArisCharacterLook, name: String?, aris: Bool = false, pid: Int32, windowNumber: Int) {
        self.id = id
        self.look = look
        self.pid = pid
        self.windowNumber = windowNumber
        character = NSHostingView(rootView: ArisFigureCharacter(look: look, name: name, aris: aris, model: model))
        bubble = NSHostingView(rootView: ArisFigureBubble(model: model))
        for view in [character, bubble] as [NSView] {
            view.wantsLayer = true
            view.clipsToBounds = false
            view.layer?.masksToBounds = false
        }
        character.sizingOptions = []
        bubble.sizingOptions = []
        character.frame = CGRect(x: 0, y: 0, width: size, height: size)
        bubble.frame = CGRect(x: 0, y: 0, width: Self.bubbleHostWidth, height: Self.bubbleHostHeight)
    }

    // MARK: moving

    /// Appears at `home` (under the notch window, so it comes out from behind the pill).
    func spawn(at home: CGPoint, panels: ArisOverlayPanels) {
        seatedIn = panels
        place(character, centre: home, panels: panels)
    }

    /// Glides (the user's G at 0.75×) to `point`, the bubble hidden on the way; `landed` once there.
    func travel(to point: CGPoint, window: CGRect?, panels: ArisOverlayPanels, landed: @escaping () -> Void) {
        let from = currentCentre ?? point
        hideBubble()
        travelling = true
        animator.travel(from: from, to: point, view: character, panels: panels) { [weak self] in
            guard let self else { return }
            self.travelling = false
            self.perch = point
            self.window = window
            landed()
        }
    }

    /// Sits at `point` now (a window moved, or the panels were rebuilt), the bubble with it.
    func sit(at point: CGPoint, window: CGRect, panels: ArisOverlayPanels) {
        perch = point
        self.window = window
        place(character, centre: point, panels: panels)
        placeBubble(panels: panels)
    }

    /// Ends whatever plays (the completion runs).
    func stopTravel() { animator.stop() }

    // MARK: the bubble

    /// The bubble's words and tone, shown once it sits (`show`), hidden on the way.
    func say(_ words: String?, tone: ArisBubbleTone?) {
        // Cut again to the width the bubble may take (24 wide letters would run past it).
        let text = words.map { ArisBubbleText.fitted($0, maxWidth: ArisBubbleView.maxTextWidth, width: ArisBubbleView.textWidth) }
        guard text != model.text || tone.map({ $0 != model.tone }) ?? false else { return }
        withAnimation(ArisGlass.opening) {
            model.text = text
            model.revealFrom = nil
            if let tone { model.tone = tone }
            if text == nil { model.bubbleShown = false }
        }
        // A longer line may need the other side of the character to stay on screen.
        if model.bubbleShown, let seatedIn { placeBubble(panels: seatedIn) }
    }

    /// `reveal`: the first show after landing brings its letters in one by one (not under Reduce Motion).
    func showBubble(panels: ArisOverlayPanels, reveal: Bool) {
        placeBubble(panels: panels)
        guard !model.bubbleShown, let text = model.text else { return }
        if reveal, !model.revealed, !Self.reducesMotion {
            model.revealed = true
            let started = Date()
            model.revealFrom = started
            DispatchQueue.main.asyncAfter(deadline: .now() + ArisBubbleView.revealTime(text)) { [weak model] in
                if model?.revealFrom == started { model?.revealFrom = nil }
            }
        }
        withAnimation(ArisGlass.opening) { model.bubbleShown = true }
    }

    private static var reducesMotion: Bool {
        Defaults[.arisReduceMotion] || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func hideBubble() {
        guard model.bubbleShown else { return }
        withAnimation(Self.closing) { model.bubbleShown = false }
    }

    /// Done: "끝!" with its check, and upstream's poke (a hop and a turn) from the idle loop.
    func celebrate() {
        model.mood = "default"
        model.pokes += 1
        say(ArisBubbleText.text(for: .done(""), korean: model.korean), tone: .done)
    }

    // MARK: going

    /// Fades into the notch (or wherever it is) and leaves the panels.
    func merge(completion: @escaping () -> Void) {
        hideBubble()
        follower?.stop()
        follower = nil
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = ArisCharacterDirector.mergeFade
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.55, 1)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                self?.removeNow()
                completion()
            }
        }
        character.alphaValue = 0
        character.layer?.add(fade, forKey: "aris.merge")
        CATransaction.commit()
    }

    /// Gone at once (its display went away).
    func removeNow() {
        animator.stop()
        follower?.stop()
        follower = nil
        character.removeFromSuperview()
        bubble.removeFromSuperview()
    }

    // MARK: placing

    private var currentCentre: CGPoint? {
        guard let window = character.window else { return nil }
        let f = character.frame
        return CGPoint(x: window.frame.minX + f.midX, y: window.frame.minY + f.midY)
    }

    /// `view` centred on `centre` (screen coordinates) in the panel of the display holding it.
    private func place(_ view: NSView, centre: CGPoint, panels: ArisOverlayPanels) {
        place(view, origin: CGPoint(x: centre.x - view.frame.width / 2, y: centre.y - view.frame.height / 2), holding: centre, panels: panels)
    }

    /// `view` with its frame's origin at `origin` (screen coordinates), in the panel of the display holding `point`.
    private func place(_ view: NSView, origin: CGPoint, holding point: CGPoint, panels: ArisOverlayPanels) {
        let screens = NSScreen.screens.map(\.frame)
        let index = ArisPerchGeometry.screenIndex(of: point, screens: screens) ?? 0
        guard let content = panels.panel(for: index)?.contentView, screens.indices.contains(index) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if view.superview !== content { content.addSubview(view, positioned: .above, relativeTo: nil) }
        let screenOrigin = screens[index].origin
        view.setFrameOrigin(CGPoint(x: origin.x - screenOrigin.x, y: origin.y - screenOrigin.y))
        CATransaction.commit()
    }

    /// The bubble beside the character, on the side its words fit (ArisBubbleGeometry). Its host is wider than any
    /// bubble, so it is pinned by the bubble's own edge: the edge next to the character.
    private func placeBubble(panels: ArisOverlayPanels) {
        guard let perch, let window, let text = model.text else { return }
        let screens = NSScreen.screens.map(\.frame)
        guard let screen = ArisPerchGeometry.screenIndex(of: perch, screens: screens).map({ screens[$0] }) else { return }
        let width = min(Self.bubbleHostWidth - 2 * Self.bubbleInset, ArisBubbleView.width(text: text, tone: model.tone))
        let side = ArisBubbleGeometry.side(perch: perch, size: size, width: width, window: window, screen: screen)
        if model.side != side { model.side = side }
        let rect = ArisBubbleGeometry.frame(perch: perch, size: size, width: width, side: side, screen: screen)
        let x = side == .right ? rect.minX - Self.bubbleInset : rect.maxX + Self.bubbleInset - Self.bubbleHostWidth
        place(bubble, origin: CGPoint(x: x, y: rect.midY - Self.bubbleHostHeight / 2), holding: perch, panels: panels)
    }
}

/// The character in the figure's box: the look's sprites, working while the job runs. Always dark: the overlay is
/// ambient UI, and the director bakes its atlases ahead for the dark look. Aris's own wears its face as it changes; a
/// teammate out on a window when Aris takes its type shows the replacement at once (ArisFace.shown).
struct ArisFigureCharacter: View {
    let look: ArisCharacterLook
    let name: String?
    var aris = false
    @ObservedObject var model: ArisFigureModel
    @AppStorage(ArisFace.key, store: ArisFace.store) private var arisFace = ""

    var body: some View {
        let shown = aris ? look : ArisFace.shown(look, name: name ?? "", aris: ArisFace.decode(arisFace))
        ArisCharacterView(look: shown, state: model.mood, size: ArisCharacterDirector.perchSize, label: name, pokes: model.pokes, follows: false,
                          isAris: aris)
            .environment(\.colorScheme, .dark)
    }
}

/// The bubble's host: the pill against the character's side, in from the character with the notch's open curve
/// (opacity, and .965 → 1 from the side it grows from), out with its close curve (up 4 at .985).
struct ArisFigureBubble: View {
    @ObservedObject var model: ArisFigureModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Default(.arisReduceMotion) private var reduceSetting

    private var reduced: Bool { systemReduceMotion || reduceSetting }

    var body: some View {
        let anchor: UnitPoint = model.side == .right ? .leading : .trailing
        ZStack(alignment: model.side == .right ? .leading : .trailing) {
            Color.clear
            if model.bubbleShown, let text = model.text {
                ArisBubbleView(text: text, tone: model.tone, reduceMotion: reduced, revealFrom: model.revealFrom)
                    .transition(reduced ? .opacity : .asymmetric(
                        insertion: .modifier(active: BubbleMotion(opacity: 0, scale: 0.965, y: 0, anchor: anchor),
                                             identity: BubbleMotion(opacity: 1, scale: 1, y: 0, anchor: anchor)),
                        removal: .modifier(active: BubbleMotion(opacity: 0, scale: 0.985, y: -4, anchor: anchor),
                                           identity: BubbleMotion(opacity: 1, scale: 1, y: 0, anchor: anchor))))
            }
        }
        .padding(.horizontal, ArisFigure.bubbleInset)
        .frame(width: ArisFigure.bubbleHostWidth, height: ArisFigure.bubbleHostHeight)
        .allowsHitTesting(false)
        .environment(\.colorScheme, .dark)
    }

    private struct BubbleMotion: ViewModifier {
        let opacity: Double, scale: CGFloat, y: CGFloat, anchor: UnitPoint
        func body(content: Content) -> some View {
            content.opacity(opacity).scaleEffect(scale, anchor: anchor).offset(y: y)
        }
    }
}
