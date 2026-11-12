//
//  ArisFirstTries.swift
//  Aris
//
//  The moment after the setup (the owner's pick 5-A; ArisFirstTriesPlan has the rules and the words): the real notch opens
//  on its home page with one line and three things to try, and the left side notch comes out once with "기록은 여기".
//  A press sends that request as one typed into the notch is sent (ArisController.submitTyped), so it takes the same
//  path, cards and all, as anything asked later. The three are part of the open notch's home page until the first
//  request of any kind; the notch Aris opened closes by itself after a minute if the pointer never came to it.
//  Drawn in the open notch's own dress (ArisGlass): the prompt card's fill for the three, its text sizes, press and
//  hover on each; they come in one after the other, once, and plainly under Reduce Motion.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class ArisFirstTries: ObservableObject {
    static let shared = ArisFirstTries()

    /// The three on offer; empty when nothing is offered.
    @Published private(set) var tries: [ArisFirstTry] = []
    /// What the user asked to be called, for the line.
    @Published private(set) var name: String?
    /// The left side notch is out by itself, with its words beside it.
    @Published private(set) var sliverShown = false
    /// Reduce Motion was on when the setup ended.
    private(set) var reduced = false
    /// The words are English (the UI's language as the setup ended).
    private(set) var english = false

    private weak var host: ArisNotchModel?
    private var hostScreen: NSScreen?
    private var turns: AnyCancellable?
    private var clocks: [Task<Void, Never>] = []

    var offered: Bool { !tries.isEmpty }

    private init() {}

    /// The setup's last page has closed. `host`: the notch that takes it and its display; none (no notch window
    /// anywhere) offers nothing.
    func begin(on host: (model: ArisNotchModel, screen: NSScreen)?, noAI: Bool, name: String?, reduced: Bool, english: Bool = ArisUIWords.english) {
        guard let host else { return }
        stopClocks()
        self.host = host.model
        hostScreen = host.screen
        self.name = name
        self.reduced = reduced
        self.english = english
        tries = ArisFirstTriesPlan.tries(noAI: noAI)
        ArisNotchNavigation.shared.currentView = .home
        withAnimation(reduced ? nil : StandardAnimations.interactive) { _ = host.model.open() }
        // The first request of any kind ends the offer (a turn already going when the setup closed is not that request).
        turns = ArisController.shared.$session.map { $0.phase != .idle }.removeDuplicates().dropFirst()
            .sink { [weak self] inTurn in
                DispatchQueue.main.async { MainActor.assumeIsolated { if ArisFirstTriesPlan.ends(turnStarted: inTurn) { self?.end() } } }
            }
        showSliver()
        after(ArisFirstTriesPlan.staysOpen) { $0.closeIfLeftAlone() }
    }

    /// One of the three was pressed: it is asked as typed words are.
    func press(_ item: ArisFirstTry) {
        guard tries.contains(item) else { return }
        let text = item.text(english: english)
        end()
        ArisController.shared.submitTyped(text)
    }

    /// The offer is over (the first request came).
    func end() {
        guard offered || sliverShown else { return }
        stopClocks()
        turns = nil
        tries = []
        sliverShown = false
    }

    /// 시작 안내로 돌아가기 during the finish: the offer goes and the notch it opened closes for the setup's own.
    func cancel() {
        let wasOffered = offered
        end()
        if wasOffered, host?.notchState == .open { host?.close() }
    }

    /// The left side notch comes out once, with its words, and goes back in.
    private func showSliver() {
        guard ArisSidePanels.shared.showOnce(.left, for: ArisFirstTriesPlan.sliverSeconds) else { return }
        sliverShown = true
        after(ArisFirstTriesPlan.sliverSeconds) { $0.sliverShown = false }
    }

    /// Nobody came to the notch Aris opened: it closes; the three are there the next time it is opened.
    private func closeIfLeftAlone() {
        guard let host, let screen = hostScreen ?? NSScreen.main else { return }
        let region = ArisNotchWindowRules.openNotchRegion(screenFrame: screen.frame, openSize: host.notchSize)
        if ArisFirstTriesPlan.closesItself(offered: offered, open: host.notchState == .open, inTurn: ArisController.shared.session.phase != .idle,
                                           pointerOnNotch: region.contains(NSEvent.mouseLocation)) {
            host.close()
        }
    }

    private func after(_ seconds: TimeInterval, _ work: @escaping @MainActor (ArisFirstTries) -> Void) {
        clocks.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            work(self)
        })
    }

    private func stopClocks() {
        clocks.forEach { $0.cancel() }
        clocks = []
    }
}

/// In the open notch's home page while the three are on offer: the line, the hint, the three. A turn has the notch to
/// itself.
struct ArisFirstTriesRow: View {
    @ObservedObject private var first = ArisFirstTries.shared
    /// A turn or an answer is up.
    var hidden = false
    @State private var entered = false
    /// A still picture draws them as they end up.
    @Environment(\.arisOnboardingStill) private var still

    /// The mockup's `.nsay` and `.nchip`: the line 14 medium with a 12-point hint, inset 14; each try 36 high, radius
    /// 14, 6 apart, on the prompt card's fill; the line and the three 12 apart, as the open notch's rows are.
    private static let textInset: CGFloat = 14
    private static let tryGap: CGFloat = 6
    private static let rowGap: CGFloat = 12
    /// Each comes in 50 ms after the one before, rising 6 points on the house ease.
    private static let stagger = 0.05
    private static let rise: CGFloat = 6
    private static let enter = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.28)

    var body: some View {
        if !hidden, first.offered {
            let english = first.english
            VStack(alignment: .leading, spacing: Self.rowGap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ArisFirstTriesPlan.line(name: first.name, english: english))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ArisGlass.text)
                    Text(ArisFirstTriesPlan.hint(keys: ArisOnboardingSystem.talkKeys().joined(separator: " "), english: english))
                        .font(.system(size: 12))
                        .foregroundStyle(ArisGlass.secondaryText)
                }
                .padding(.horizontal, Self.textInset)
                .padding(.top, 2)
                VStack(spacing: Self.tryGap) {
                    ForEach(Array(first.tries.enumerated()), id: \.element) { index, item in
                        Button(item.text(english: english)) { first.press(item) }
                            .buttonStyle(ArisFirstTryStyle())
                            .opacity(entered || still ? 1 : 0)
                            .offset(y: entered || still || first.reduced ? 0 : Self.rise)
                            .animation(first.reduced ? .easeOut(duration: 0.15) : Self.enter.delay(Double(index) * Self.stagger), value: entered)
                    }
                }
            }
            .onAppear { entered = true }
            .transition(.opacity)
        }
    }
}

/// One thing to try: the prompt card's fill (a little brighter under the pointer), 14-point text, and it gives a
/// little when pressed.
private struct ArisFirstTryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Label(configuration: configuration) }

    private struct Label: View {
        let configuration: ButtonStyleConfiguration
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: 14))
                .foregroundStyle(ArisGlass.text)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hover ? Color.white.opacity(0.10) : ArisGlass.promptFill))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.16), value: hover)
                .onHover { hover = $0 }
        }
    }
}

/// The words beside the left side notch while it shows itself, in a popover's dress (the dark gradient, radius 12,
/// a white-8% hairline), 28 high.
struct ArisFirstTriesSliverLabel: View {
    var body: some View {
        Text(ArisFirstTriesPlan.sliverWord(english: ArisFirstTries.shared.english))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.94))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(.sRGB, red: 32 / 255, green: 32 / 255, blue: 35 / 255, opacity: 0.965),
                                              Color(.sRGB, red: 19 / 255, green: 19 / 255, blue: 22 / 255, opacity: 0.98)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
            .fixedSize()
            .accessibilityHidden(true)
    }
}
