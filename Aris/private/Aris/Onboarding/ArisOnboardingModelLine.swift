//
//  ArisOnboardingModelLine.swift
//  Aris
//
//  The 받아쓰기 page's one line about the model (the owner's pick 9-A; the mockup's `.mrow`): under the practice note's
//  button, over a hairline, a title and one sentence with 받기 at the right. Pressed, the sentence becomes how far the
//  download is, with a 4-point bar under it; nothing on the page waits for it, and it goes on after the setup is
//  closed (the closed notch's right ear shows it then, as before). What it says is ArisModelLine's.
//

import SwiftUI

struct ArisModelLineView: View {
    let palette: ArisSetupPalette
    let reduced: Bool
    @ObservedObject private var downloads = ArisModelDownloader.shared
    /// Whether a model is already on this Mac: read once as the page shows, and nothing is drawn until it is known
    /// (so a Mac that has one never sees the offer flash by). A still picture reads nothing of this Mac.
    @State private var installed: Bool?
    @Environment(\.arisOnboardingStill) private var still
    /// The model came in while this page was up: the line keeps saying it is ready.
    @State private var cameIn = false

    /// The mockup's `.mrow` and `.mbar`: 16 above and below its hairline, a 4-point bar 6 under the sentence.
    private static let gap: CGFloat = 16
    private static let barHeight: CGFloat = 4
    private static let barGap: CGFloat = 6

    var body: some View {
        VStack(spacing: 0) {
            if let installed = installed ?? (still ? false : nil),
               let line = ArisModelLine.shown(state: ArisModelLine.lineState(downloads.state, cameInHere: cameIn), model: downloads.model, installed: installed,
                                              english: ArisSetupWords.english) {
                row(line)
            }
        }
        .onAppear { if installed == nil, !still { installed = ArisSpeechModel.allCases.contains(where: ArisWhisper.installed) } }
        // Read again whenever the download's state changes: the model that has just come in is installed, and the
        // line says so from then on (it used to read "installed" once, and offered Download again six seconds after
        // the download finished).
        .onChange(of: downloads.state) { _, state in
            guard !still else { return }
            if state == .done { cameIn = true }
            installed = ArisSpeechModel.allCases.contains(where: ArisWhisper.installed)
        }
    }

    private func row(_ line: ArisModelLine.Shown) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(line.title).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.t1)
                Text(line.detail)
                    .font(.system(size: 13).monospacedDigit())
                    .lineSpacing(3)
                    .foregroundStyle(palette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                if let fraction = line.fraction { bar(fraction).padding(.top, Self.barGap) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action = line.action {
                Button(ArisSetupWords.modelAction(action)) { press(action) }
                    .buttonStyle(ArisQuietButtonStyle(palette: palette, weight: .regular))
            }
        }
        .padding(.top, Self.gap)
        .overlay(alignment: .top) { Rectangle().fill(palette.tileLine).frame(height: 1) }
        .padding(.top, Self.gap)
        .animation(reduced ? ArisOBCurve.fade : ArisOBCurve.card, value: line.action)
        .accessibilityElement(children: .contain)
    }

    /// How far it is: the back button's grey as the track, Aris's blue as the fill, moving evenly.
    private func bar(_ fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.back)
                Capsule().fill(ArisOBColor.blue).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: Self.barHeight)
        .animation(reduced ? nil : .linear(duration: 0.25), value: fraction)
        .accessibilityHidden(true)
    }

    private func press(_ action: ArisModelLine.Action) {
        switch action {
        case .get:
            downloads.choose(ArisModelLine.offered)
            downloads.accept()
        case .resume: downloads.togglePause()
        case .retry: downloads.retryNow()
        }
    }
}
