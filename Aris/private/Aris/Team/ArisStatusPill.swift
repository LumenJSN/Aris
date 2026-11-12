//
//  ArisStatusPill.swift
//  Aris
//
//  The pill that drops under the closed notch while background jobs run (or wait for the user), one line 30 tall (the user's
//  B, mockups/pill-oneline.html, in the P1 layout, ArisPillLayout): one face slot on the left, one line from
//  ArisStatusLine centred on the notch, and how long the work has run on the right. The face is who works: Aris's own
//  job is the star (A6: the one star drops in from beside the camera and works here, ArisStarStage), a teammate's job
//  that teammate's face instead (and no star), two jobs or more small faces and "+N" (ArisPillView). When the last
//  job finishes done it says 끝났어요 with a check for 1.6 s (ArisPillFinish), then tucks up and the star hops home.
//  The line is driven only by state; the clock ticks once a second and never blinks. It never reads the audio level.
//  When only one job runs and it waits at the notch, the line says what it does.
//

import SwiftUI

struct ArisStatusPill: View {
    @ObservedObject private var aris = ArisController.shared
    @ObservedObject private var director = ArisController.shared.director

    static let height = ArisPillLayout.height

    /// The 1.6 s of 끝났어요 have run out (until the flash that started them ends).
    @State private var doneOver = false
    @State private var doneHold: Task<Void, Never>?

    private var line: ArisPillLine? {
        ArisCharacterDirector.pillLine(single: director.single.map { (name: $0.name, text: $0.text) },
                                       fallback: ArisStatusLine.pillText(jobs: aris.jobs, korean: !ArisUIWords.english))
    }

    /// The jobs are over and the last one finished done (in the same update as the line going: the pill never blinks).
    private var finishing: Bool { line == nil && ArisPillFinish.showsDone(jobs: aris.jobs, justFinished: aris.taskJustFinished) }
    private var done: Bool { finishing && !doneOver }
    private var shown: ArisPillLine? { line ?? (done ? ArisPillLine(who: nil, text: ArisPillFinish.text(name: doneName)) : nil) }
    /// "Alex님, 끝났어요" (N10), but never in the ad demo's recording.
    private var doneName: String? { ArisAdDemoRoster.mates.isEmpty ? ArisUserName.current : nil }

    var body: some View {
        let crew = director.crew
        let faces = ArisPillLayout.faces(crew.map { ArisPillWorker(id: $0.id, aris: $0.aris) })
        ZStack {
            if let shown {
                ArisMergedPill(line: shown, done: done, since: ArisStatusLine.since(jobs: aris.jobs), faces: faces) { face, size in
                    switch face {
                    case .star:
                        // The star's seat: ArisStarStage draws the one star here.
                        Color.clear.frame(width: size, height: size).arisStarSeat(.pill)
                    case .mate(let id):
                        if let mate = crew.first(where: { $0.id == id }) {
                            ArisCharacterView(look: mate.look, size: size, label: mate.name, follows: false)
                        }
                    }
                }
                .arisStarAway(!faces.holdsStar)
                .transition(Self.entry)
            }
        }
        .animation(ArisGlass.opening, value: shown != nil)
        .allowsHitTesting(false)
        .onChange(of: finishing) { _, now in
            doneHold?.cancel()
            doneOver = false
            guard now else { return }
            doneHold = Task { @MainActor in
                try? await Task.sleep(for: .seconds(ArisPillFinish.hold))
                guard !Task.isCancelled else { return }
                doneOver = true
            }
        }
        .onDisappear { doneHold?.cancel() }
    }

    /// In from 4 pt above at .985, on the notch's clock; out the same way (it tucks up).
    private static let entry = AnyTransition.modifier(
        active: PillEntry(opacity: 0, scale: 0.985, y: -4), identity: PillEntry(opacity: 1, scale: 1, y: 0))

    private struct PillEntry: ViewModifier {
        let opacity: Double, scale: CGFloat, y: CGFloat
        func body(content: Content) -> some View {
            content.opacity(opacity).scaleEffect(scale, anchor: .top).offset(y: y)
        }
    }
}
