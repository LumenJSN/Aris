//
//  ArisNotchRoot.swift
//  Aris
//
//  One display's notch, closed or open: what the closed band shows (first match wins: the Now Playing notice, Aris's
//  star band, a due alert, a timer, Claude, music), the open pages under the user's header, the glass surface clipped to
//  the notch outline, and the star, agent and model layers above it. Behaviour (hover, gestures, drops, Aris and
//  Claude rules) is in ArisNotchRoot+Behaviour.swift. While the first-run guide holds the notch, its onboarding state
//  (ArisOnboardingNotch) draws instead.
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct ArisNotchRoot: View {
    @EnvironmentObject var vm: ArisNotchModel
    @ObservedObject var navigation = ArisNotchNavigation.shared
    @ObservedObject var music = ArisNowPlaying.shared
    @ObservedObject var aris = ArisNotchState.shared
    @ObservedObject var claude = ClaudeStore.shared
    @ObservedObject var todo = ArisTodoModel.shared
    @ObservedObject var timer = ArisTimerModel.shared
    @ObservedObject var fullscreen = ArisFullscreenWatch.shared
    @ObservedObject var sharing = SharingStateManager.shared
    /// Re-draws the notch when the hidden look changes (ArisSiriLookGate).
    @ObservedObject var siriLook = ArisSiriLookGate.shared

    @Default(.enableGestures) var gesturesOn
    @Default(.closeGestureEnabled) var closeGestureOn
    @Default(.enableHorizontalMediaGestures) var mediaGesturesOn
    @Default(.gestureSensitivity) var sensitivity
    @Default(.enableHaptics) var hapticsOn
    @Default(.openNotchOnHover) var openOnHover
    @Default(.minimumHoverDuration) var hoverDelay
    @Default(.shelfEnabled) var shelfOn
    @Default(.sneakPeekStyles) var peekStyle
    @Default(.cornerRadiusScaling) var cornerScaling
    @Default(.arisMuted) var muted
    /// 쉬는 동안 별 보이기: watched so the closed notch is drawn again the moment it is switched (starMayRest reads it).
    @Default(.arisRestStar) var restStarShown
    /// For the closed notch at ArisVNotch's sizes (ArisNotchRoot+VNotch): the glass rest height, what the star tells
    /// at rest.
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @ObservedObject var agentLink = ArisAgentMonitor.shared
    @ObservedObject var speechModels = ArisModelDownloader.shared
    @ObservedObject var givenFiles = ArisAttachments.shared
    @State var lastHoverHaptic = Date.distantPast

    @State var hovering = false
    @State var hoverTask: Task<Void, Never>?
    @State var haptic = false
    @State var gestureProgress: CGFloat = 0
    @State var mediaNudge: CGFloat = 0
    @State var mediaFired = false
    @State var openedForApproval = false
    @State var openedForNotice = false
    /// The notch opened for a card that came when no turn was on (it closes again once the card is answered).
    @State var openedForCard = false
    @State var arisOpenedNotch: Bool?
    /// The page this display showed before an Aris turn took it.
    @State var pageBeforeAris: NotchViews?
    @State var endTask: Task<Void, Never>?
    @State var dropLeaveTask: Task<Void, Never>?
    @State var lastApproval: String?
    /// The open notch's content height, and the height the surface is drawn at (BUGS-notch N2).
    @State var contentHeight: CGFloat = 0
    @State var drawnHeight: CGFloat = 0
    @State var openingUntil = Date.distantPast
    /// The surface's frame in its window (from the window's top-left), for checking where the pointer really is.
    @State var surfaceFrame = CGRect.zero
    /// Checks the pointer's place while the notch believes it is hovered (ArisNotchPointer).
    @State var hoverWatch: Task<Void, Never>?
    /// The open notch's own look at the pointer while no hover is known (ArisNotchPointer.openStep).
    @State var openWatch: Task<Void, Never>?
    /// The measured place agreed with the last hover that began, so it may overrule a missed hover event.
    @State var pointerTrusted = false

    // MARK: - Derived

    var isOpen: Bool { vm.notchState == .open }
    var closed: Bool { vm.notchState == .closed }
    var hidden: Bool { vm.hideOnClosed }
    var flat: Bool { vm.effectiveClosedNotchHeight == 0 }
    var displayedHeight: CGFloat { flat ? 10 : closedIsVNotch ? closedBody.height : vm.effectiveClosedNotchHeight }
    var notchWidth: CGFloat { vm.closedNotchSize.width }
    var ear: CGFloat { ArisBand.earWidth(notchWidth: notchWidth, body: bandBody) }
    var displayUUID: String? { vm.screenUUID ?? NSScreen.main?.displayUUID }
    var musicPeekHere: Bool { navigation.shouldShowSneakPeek(on: vm.screenUUID) && navigation.sneakPeekState(for: vm.screenUUID).type == .music }
    /// The inline peek widens the music pill (inline peek style only).
    /// This display's standard-style music peek, while the notch isn't hidden.
    var standardPeekHere: Bool { closed && !hidden && peekStyle == .standard && musicPeekHere }

    /// The closed notch's bump on a media swipe.
    static let mediaBump: CGFloat = 0.02

    var inlineMusic: Bool { peekStyle == .inline && navigation.expandingView.show && navigation.expandingView.type == .music }

    var musicShowing: Bool {
        ArisNotchDecisions.musicShowing(liveActivity: navigation.musicLiveActivityEnabled, playing: music.isPlaying, idle: music.isPlayerIdle,
                                        expansionShown: peekStyle == .inline && navigation.expandingView.show,
                                        expansionIsMusic: navigation.expandingView.type == .music)
    }

    var musicBusy: Bool { navigation.musicLiveActivityEnabled && (music.isPlaying || !music.isPlayerIdle) }

    var noticeActive: Bool {
        guard music.nowPlayingNotice != nil, !flat, let uuid = displayUUID, NSScreen.screen(withUUID: uuid) != nil else { return false }
        return uuid == navigation.selectedScreenUUID || uuid == NSScreen.main?.displayUUID
    }

    /// A turn, or a conversation listening between turns (the same band, calm).
    var arisTurn: Bool { (aris.isActive || aris.conversing) && closed && !hidden }
    var dueAlert: Bool { closed && !hidden && todo.alert != nil }
    var arisTasks: Bool { closed && !hidden && (aris.hasUnfinishedTask || aris.taskJustFinished) }
    var timerShowing: Bool { closed && !hidden && timer.isRunning }
    var claudeShowing: Bool {
        closed && !hidden && ArisNotchDecisions.claudeShowing(live: claude.isLive, sessions: claude.hasSessions, liveActivity: navigation.musicLiveActivityEnabled,
                                                              playing: music.isPlaying, idle: music.isPlayerIdle)
    }
    var ours: Bool { arisTurn || dueAlert || arisTasks || timerShowing || claudeShowing }
    var parked: Bool { closed && !hidden && !aris.isActive && aris.hasReply && !ours && !musicShowing }
    var fullscreenHere: Bool { displayUUID.flatMap { fullscreen.fullscreenStatus[$0] } ?? false }
    var characterHome: Bool {
        ArisStarBand.showsHome(closed: closed, hidden: hidden, fullscreen: fullscreenHere, hasNotch: vm.hasNotch, flat: flat,
                               busy: ours || parked || musicShowing || noticeActive || musicPeekHere, filesWaiting: !givenFiles.files.isEmpty) && starMayRest
    }
    var starMode: ArisStarBand.Mode? {
        ArisStarBand.mode(turn: arisTurn, dueAlert: dueAlert, timer: timerShowing, tasks: arisTasks, claude: claudeShowing,
                          music: musicShowing, parked: parked, home: characterHome)
    }
    var pillCanShow: Bool { closed && !hidden && !dueAlert && !musicPeekHere && !noticeActive }
    var pillHasLine: Bool { pillCanShow && (aris.hasUnfinishedTask || aris.taskJustFinished) }

    var closedKind: ArisNotchDecisions.Closed {
        ArisNotchDecisions.closedContent(.init(notice: closed && noticeActive, starMode: starMode, dueAlert: dueAlert, timer: timerShowing,
                                               claude: claudeShowing, music: musicShowing && closed && !hidden))
    }

    var radii: (top: CGFloat, bottom: CGFloat) {
        isOpen ? cornerRadiusInsets.opened
            : closedIsVNotch && !flat ? (closedRadius, closedRadius)
            : ArisNotchDecisions.closedRadii(base: cornerRadiusInsets.closed, displayedHeight: displayedHeight, scaling: cornerScaling)
    }

    var shape: NotchShape {
        // Quarter-circle corners in every state.
        NotchShape(topCornerRadius: radii.top, bottomCornerRadius: radii.bottom, circular: 1)
    }

    var grows: Bool { isOpen && [.claude, .home, .aris, .shelf].contains(navigation.currentView) }
    var claudeNotice: ClaudePeek? {
        // Only on a display that opened for the notice, and never over waiting approval cards.
        guard openedForNotice, claude.approvals.isEmpty, let peek = claude.currentPeek, navigation.currentView == .claude else { return nil }
        return peek
    }

    // MARK: - Body

    var body: some View {
        if let guide = vm.guide {
            // The first-run guide's onboarding state, in this same window (ArisOnboardingNotch).
            ArisOnboardingNotch(guide: guide)
        } else {
            regular
        }
    }

    private var regular: some View {
        ZStack(alignment: .top) {
            notch
            if closed && !hidden { chin }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .ignoresSafeArea()
        .compositingGroup()
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        // Every control shown on hover lets go when the pointer has left the notch (ArisNotchHovered).
        .environment(\.arisNotchHovered, hovering)
        // Every band on this display is ArisVNotch's width.
        .environment(\.arisBandBody, bandBody)
        .modifier(ArisNotchBehaviour(root: self))
    }

    private var notch: some View {
        // The swipe scale and the media bump together, so the band, the pill and the layers move as one.
        let progressScale = ArisNotchDecisions.gestureScale(progress: gestureProgress) * (closed ? 1 + abs(mediaNudge) * Self.mediaBump : 1)
        return surfaced
            // Only the band fades on a flat (0 pt) notch; the pill and the layers above stay.
            .opacity(flat && closed ? 0.01 : 1)
            .overlay(alignment: .top) { underNotch }
            .overlayPreferenceValue(ArisStarSeatKey.self) { seats in
                ArisStarStage(seats: seats, mode: starMode, bandVisible: !(flat && closed), asleep: starAsleep)
            }
            .overlayPreferenceValue(ArisStarSeatKey.self) { seats in
                GeometryReader { proxy in
                    let band = seats.band.map { proxy[$0] }
                    ZStack(alignment: .top) {
                        ArisAgentLayer(seat: band, mode: starMode, bandHeight: hangHeight, ear: ear, pillShown: pillHasLine)
                        ArisModelLayer(seat: band, mode: starMode, closed: closed, bandHeight: hangHeight, pillShown: pillHasLine,
                                       busy: vm.dropInteraction.dragNear || vm.dropInteraction.anyDropZoneTargeting)
                        ArisDayEndLayer(mode: starMode, closed: closed && !hidden, bandHeight: hangHeight, pillShown: pillHasLine,
                                        busy: vm.dropInteraction.dragNear || vm.dropInteraction.anyDropZoneTargeting)
                        if closedKind == .timer {
                            // The timer's own control, on its ear and above the notch's hover (as the dozing star's
                            // is): everywhere else on the band a rest or a click opens Aris (vm2 bug 6).
                            ArisTimerEarControl(width: ArisClosedBand.timerControlWidth(notchWidth: notchWidth, body: bandBody), height: displayedHeight)
                                .offset(x: ArisClosedBand.timerControlOffset(notchWidth: notchWidth, body: bandBody))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
            }
            .scaleEffect(progressScale, anchor: .top)
            .animation(.smooth, value: gestureProgress)
    }

    /// The camera housing's height on the notch's display (0 without one): the black always covers it.
    private var glassSafeTop: CGFloat {
        (vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main)?.safeAreaInsets.top ?? 0
    }

    /// The siri look's full-black top: the open notch's own band (the lock, the buttons and the mark stand in it),
    /// the closed notch's height otherwise. Whatever the display makes them: nothing is assumed.
    private var siriBand: CGFloat { isOpen ? vm.openBandHeight : displayedHeight }

    /// The notch content on its glass, clipped to the outline.
    private var surfaced: some View {
        let open = isOpen
        // The look is read here, as the notch opens or closes and as a voice state begins (ArisSiriLookGate).
        ArisSiriLookGate.refresh(open: open, state: aris.isActive ? "\(aris.phase)" : "idle")
        let siri = ArisSiriLookNow.surfaceOn
        return content
            // What the siri look's scrim needs of the surface the content stands on (ArisSiriLookScrim).
            .environment(\.arisSiriLookSurface, ArisSiriLookSurfaceInfo(
                height: open ? (drawnHeight > 0 ? drawnHeight : contentHeight) : 0, band: siriBand,
                base: ArisSiriLookSurface<NotchShape>.baseShare(frosted: ArisSiriLookNow.look == .siriFrost)))
            .coordinateSpace(name: ArisSiriLookScrim.space)
            .padding(.horizontal, open ? cornerRadiusInsets.opened.top + ArisGlass.inset : cornerRadiusInsets.closed.bottom)
            .padding(.bottom, open ? ArisGlass.bottomInset : 0)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeightChanged($0) }
            .frame(height: open && drawnHeight > 0 ? drawnHeight : nil, alignment: .top)
            .clipShape(shape)
            // The hidden "siri" look (arisVoiceLook) brings its own surface (ArisSiriLookSurface) and the notch's
            // own glass is then not in the tree at all; with the preference unset this is the glass alone, as ever.
            .background(siri ? nil : ArisGlassSurface(shape: shape, open: open, hidden: hidden, safeTop: glassSafeTop,
                                                      glassBody: (inset: cornerRadiusInsets.opened.top, corner: cornerRadiusInsets.opened.bottom)))
            .background(siri ? ArisSiriLookSurface(shape: shape, open: open, band: siriBand,
                                                   frosted: ArisSiriLookNow.look == .siriFrost) : nil)
            .overlay {
                if aris.isActive && aris.phase == .listening && !hidden {
                    ArisListeningRim(shape: shape).transition(.opacity.animation(.easeOut(duration: 0.2)))
                } else if aris.conversing && !hidden {
                    // Paused for another app's sound: the same still rim, dimmer (no blink).
                    ArisListeningRim(shape: shape, calm: true)
                        .opacity(aris.listeningPaused ? 0.35 : 1)
                        .animation(.easeOut(duration: 0.3), value: aris.listeningPaused)
                        .transition(.opacity.animation(.easeOut(duration: 0.2)))
                }
            }
            .overlay(alignment: .top) {
                if !(flat && closed) {
                    Rectangle().fill(.black).frame(height: 1).padding(.horizontal, radii.top)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { surfaceFrame = $0 }
            .contentShape(hitShape)
            .modifier(ArisNotchInput(root: self))
            // Centred inside the animated scope: the surface's place is part of its open/close motion. Centred by the
            // window's frame outside it, the size animated but the place jumped to the end (it grew rightward from the
            // open notch's left edge); the curve on the whole root fixed that but animated every layer above the
            // surface each frame, and the open stuttered.
            .frame(maxWidth: .infinity, alignment: .top)
            // The siri look's own springs: nearer the content than the curve below, so they replace it only while
            // the look is on; with the look off this changes nothing.
            .transaction(value: vm.notchState) { if ArisSiriLookNow.on { $0.animation = ArisSiriLookMotion.surface(open: open) } }
            .animation(open ? StandardAnimations.open : StandardAnimations.close, value: vm.notchState)
            // A closed band giving way to another: the size transition, 340 ms (0.45, 0, 0.55, 1).
            .animation(ArisGlass.resize, value: closedKind)
            // The growth under the pointer, on the same size clock.
            .animation(ArisGlass.resize, value: closedGrown)
    }

    /// Closed, what a band keeps for itself is left out: the resting star's ears, a timer's ring (ArisClosedBand).
    var hoverInsets: ArisClosedBand.Insets? {
        closed ? ArisClosedBand.hoverInsets(closedKind, notchWidth: notchWidth, body: bandBody) : nil
    }

    private var hitShape: some Shape { ArisHitStrip(insets: hoverInsets, pad: closed && closedIsVNotch ? ArisVNotch.hoverTargetPadding : 0) }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            top
            if isOpen { page }
            if closed && !hidden && peekStyle == .standard && musicPeekHere {
                ArisMusicPeekRow(width: notchWidth + 2 * ear)
            }
        }
        .fixedSize(horizontal: standardPeekHere, vertical: standardPeekHere)
        .modifier(ArisGrowFrame(open: isOpen, grows: grows,
                                minHeight: navigation.currentView == .claude && claudeNotice == nil ? openNotchSize.height : 0,
                                maxHeight: [.home, .aris].contains(navigation.currentView) ? arisSurfaceMax(screenUUID: vm.screenUUID) : openNotchMaxHeight))
    }

    @ViewBuilder
    private var top: some View {
        if closed {
            closedTop
        } else {
            ArisNotchHeader(showingNotice: claudeNotice != nil)
                .frame(height: vm.openBandHeight)
                .opacity(ArisNotchDecisions.gestureOpacity(progress: gestureProgress))
        }
    }

    @ViewBuilder
    private var closedTop: some View {
        switch closedKind {
        case .notice:
            if let notice = music.nowPlayingNotice { ArisNowPlayingNoticeCard(notice: notice) }
        case .star(let mode):
            ArisActivity(mode: mode, height: displayedHeight, notchWidth: notchWidth, pillHoldsStatus: pillHasLine) {
                navigation.currentView = .aris
                withAnimation(StandardAnimations.interactive) { _ = vm.open() }
            }
        case .dueAlert:
            if let alert = todo.alert { ArisDueAlertView(due: alert.due, kind: alert.kind, height: displayedHeight, notchWidth: notchWidth) }
        case .timer:
            ArisTimerEar(height: displayedHeight, notchWidth: notchWidth)
        case .claude:
            ClaudeLiveActivity(height: displayedHeight, notchWidth: notchWidth) {
                navigation.currentView = .claude
                withAnimation(StandardAnimations.interactive) { _ = vm.open() }
            }
        case .music:
            ArisMusicPill(notchWidth: notchWidth, height: displayedHeight, inlineExpanded: inlineMusic)
        case .empty:
            Rectangle().fill(.clear).frame(width: closedIsVNotch ? closedBody.width : max(0, notchWidth - 4),
                                           height: closedIsVNotch || vm.hasNotch ? displayedHeight : 11)
                // No camera housing, so no ears: a muted Aris shows at the strip's right end (vm2 bug 8).
                .overlay(alignment: .trailing) {
                    ArisMutedStripMark(muted: ArisMutedMark.place(closed: .empty, muted: muted, hasNotch: vm.hasNotch) == .strip)
                }
        }
    }

    @ViewBuilder
    private var page: some View {
        Group {
            switch navigation.currentView {
            case .home, .aris:
                ArisHomeView()
            case .shelf:
                ShelfView(dropInteraction: vm.dropInteraction, animation: vm.animation)
                    .frame(width: ArisGlass.contentWidth, height: ArisShelfTileLayout.stripHeight)
                    .padding(.top, 2)
            case .claude:
                if let peek = claudeNotice {
                    ClaudeNoticeView(peek: peek).transition(.opacity)
                } else {
                    ClaudeTabView().frame(width: ArisGlass.claudeWidth)
                }
            }
        }
        // The siri look: black behind the content column where Siri's fill is too thin for Aris's white text.
        .background(ArisSiriLookScrim())
        .opacity(ArisNotchDecisions.gestureOpacity(progress: gestureProgress))
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -4)).animation(StandardAnimations.open),
                                removal: .opacity.combined(with: .offset(y: -4)).animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.18))))
        .allowsHitTesting(isOpen)
    }

    /// The status pill 6 points under the band.
    @ViewBuilder
    private var underNotch: some View {
        if pillCanShow {
            ArisStatusPill()
                .padding(.top, hangHeight + 6)
        }
    }

    /// An almost transparent strip under a closed notch that widens the hover area down to the menu bar's bottom.
    private var chin: some View {
        let wide = arisTurn || parked || ours || musicShowing
        let width = ArisNotchDecisions.chinWidth(closedWidth: notchWidth, notice: noticeActive, wide: wide, ear: ear, inlineMusic: inlineMusic && closedKind == .music)
        return Rectangle().fill(Color.black.opacity(0.001))
            .frame(width: width, height: vm.chinHeight)
            .padding(.top, displayedHeight)
            .allowsHitTesting(vm.chinHeight > 0)
    }

    // MARK: - Open height (N2)

    private func contentHeightChanged(_ height: CGFloat) {
        contentHeight = height
        guard isOpen else { drawnHeight = 0; return }
        if drawnHeight == 0 || Date() < openingUntil {
            withAnimation(StandardAnimations.open) { drawnHeight = height }
        } else if height != drawnHeight {
            if ArisSiriLookNow.on {
                withAnimation(ArisSiriLookMotion.resize(taller: height > drawnHeight)) { drawnHeight = height }
            } else {
                withAnimation(ArisGlass.resize) { drawnHeight = height }
            }
        }
    }
}

/// The open notch's height: grows with the content on the pages that do, else the fixed open height.
private struct ArisGrowFrame: ViewModifier {
    let open: Bool
    let grows: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat

    func body(content: Content) -> some View {
        GrowDownFrame(active: grows, minHeight: minHeight, maxHeight: maxHeight) { content }
            .frame(height: open && !grows ? openNotchSize.height : nil, alignment: .top)
    }
}

/// The hover and tap region: the surface less `insets` at its left and right, or all of it.
struct ArisHitStrip: Shape {
    let insets: ArisClosedBand.Insets?
    /// How far outside the surface a rest on it begins (the hover target padding on the closed notch).
    var pad: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        Path(ArisClosedBand.region(rect, insets: insets, pad: pad))
    }
}
