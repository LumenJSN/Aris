//
//  ArisFeatureScenes.swift
//  Aris
//
//  The detail sheet's demo tiles, drawn in code in Aris's own look: a small desktop (ArisWallpaper, a menu bar, an app
//  window) with Aris's notch at the top, and the feature happening, on one 9 s loop (ArisFeatureLook.notch: closed,
//  listening with the words coming in one by one, the answer, and closed again). Reduce Motion, and the offscreen
//  renders, show one still frame with the answer in place. The second tile is the answer as it lands in the notch.
//

import AppKit
import SwiftUI

struct ArisFeatureScene: View {
    @Environment(\.arisSettingsStill) private var still
    @Environment(\.arisWords) private var w
    let feature: ArisFeature
    /// One moment of the loop (0..<1) to show instead of playing it (the offscreen renders' frames).
    var moment: Double?

    /// The frame shown when nothing moves: the answer has landed.
    static let stillMoment = 0.6

    var body: some View {
        if let moment {
            frame(moment)
        } else if still || ArisSettingsMotion.reduced {
            frame(Self.stillMoment)
        } else {
            TimelineView(.animation) { time in
                frame(time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: ArisFeatureLook.loop) / ArisFeatureLook.loop)
            }
        }
    }

    private func frame(_ t: Double) -> some View {
        ZStack(alignment: .top) {
            ArisWallpaper()
                .scaleEffect(1.012 - 0.006 * sin(t * .pi))
                .saturation(0.9)
            ArisSceneMenuBar(app: w(appName))
            ArisSceneWindow(feature: feature, t: t)
                .frame(width: 236, height: 136)
                .offset(x: feature == .notify ? -70 : -60, y: 100)
            if feature == .notify {
                ArisSceneNotice(t: t, title: w(feature.content.query), line: w(feature.content.answer))
            }
            if feature == .notify {
                // A notice comes from Aris on its own: the notch stays closed and the card comes down under it.
                ArisSceneNotch(t: 0, query: "", answer: nil, feature: feature)
            } else {
                ArisSceneNotch(t: t, query: w(feature.content.query), answer: w(feature.content.answer), feature: feature)
            }
        }
        .frame(width: ArisFeatureLook.tile.width, height: ArisFeatureLook.tile.height)
        .clipped()
    }

    private var appName: String {
        switch feature {
        case .control: "터미널"
        case .skills: "메모"
        case .notify: "문서"
        case .savedSteps: "메일"
        }
    }
}

/// A desktop's menu bar, scaled to the tile: the app's name in bold, three menus, and the time.
private struct ArisSceneMenuBar: View {
    @Environment(\.arisWords) private var w
    let app: String

    var body: some View {
        HStack(spacing: 9) {
            Text(app).font(.system(size: 8, weight: .bold))
            ForEach(["파일", "편집", "보기"], id: \.self) { Text(w($0)).font(.system(size: 8)) }
            Spacer()
            Text("9:41").font(.system(size: 8, weight: .medium))
        }
        .foregroundStyle(.black.opacity(0.72))
        .padding(.horizontal, 12)
        .frame(height: 16)
        .background(.white.opacity(0.32))
    }
}

/// The app window the feature works in: a white window with its three dots and what the feature acts on.
private struct ArisSceneWindow: View {
    @Environment(\.arisWords) private var w
    let feature: ArisFeature
    let t: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                ForEach([0xff5f57, 0xfebc2e, 0x28c840], id: \.self) { Circle().fill(Color(arisHex: UInt32($0))).frame(width: 6, height: 6) }
            }
            .padding(8)
            content.padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .background(feature == .control ? Color(arisHex: 0x1e1f24) : .white)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
    }

    @ViewBuilder private var content: some View {
        switch feature {
        case .control: terminal
        case .skills: notes
        case .notify: document
        case .savedSteps: mail
        }
    }

    /// A terminal with an error, which a hand-drawn loop circles while the question is asked.
    private var terminal: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("$ open ~/보고서 최종.pdf").font(.system(size: 8, design: .monospaced)).foregroundStyle(.white.opacity(0.75))
            Text("No such file or directory").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(Color(arisHex: 0xff7a70))
                .padding(.vertical, 3)
                .overlay {
                    ArisSceneLasso().trim(from: 0, to: ramp(0.03, 0.13))
                        .stroke(Color(arisHex: 0x5aa2ff), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .padding(-6)
                        .opacity(1 - ramp(0.9, 0.97))
                }
            Text("$ _").font(.system(size: 8, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
        }
    }

    /// Meeting notes that the skill tidies into decisions and to-dos once the answer lands.
    private var notes: some View {
        let tidy = ramp(0.25, 0.33) * (1 - ramp(0.9, 0.97))
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<5, id: \.self) { i in Capsule().fill(.black.opacity(0.12)).frame(width: CGFloat([170, 140, 180, 120, 150][i]), height: 4) }
            }
            .opacity(1 - tidy)
            VStack(alignment: .leading, spacing: 5) {
                Text(w("정한 것")).font(.system(size: 8, weight: .bold)).foregroundStyle(.black.opacity(0.75))
                ForEach(0..<2, id: \.self) { i in row(i, done: false) }
                Text(w("할 일")).font(.system(size: 8, weight: .bold)).foregroundStyle(.black.opacity(0.75)).padding(.top, 2)
                ForEach(0..<2, id: \.self) { i in row(i + 2, done: true) }
            }
            .opacity(tidy)
        }
    }

    private func row(_ i: Int, done: Bool) -> some View {
        HStack(spacing: 5) {
            ArisLineIcon(done ? "check" : "aris-star", size: 8).foregroundStyle(done ? Color(arisHex: 0x2ebd54) : .black.opacity(0.5))
            Capsule().fill(.black.opacity(0.14)).frame(width: CGFloat([120, 96, 110, 84][i]), height: 4)
        }
    }

    /// A document being written while the teammate works.
    private var document: some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(.black.opacity(0.22)).frame(width: 90, height: 6)
            ForEach(0..<5, id: \.self) { i in Capsule().fill(.black.opacity(0.1)).frame(width: CGFloat([180, 170, 186, 150, 120][i]), height: 4) }
        }
    }

    /// A report mail the saved steps fill in, one field after another.
    private var mail: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(["받는 사람", "제목", "첨부"].enumerated()), id: \.offset) { i, label in
                HStack(spacing: 6) {
                    Text(w(label)).font(.system(size: 7.5)).foregroundStyle(.black.opacity(0.45)).frame(width: 40, alignment: .leading)
                    Capsule().fill(Color(arisHex: 0x2478f2, 0.55)).frame(width: CGFloat([90, 120, 60][i]) * ramp(0.26 + Double(i) * 0.08, 0.31 + Double(i) * 0.08), height: 4)
                    Spacer(minLength: 0)
                }
                Rectangle().fill(.black.opacity(0.06)).frame(height: 0.5)
            }
        }
    }

    private func ramp(_ a: Double, _ b: Double) -> Double { min(max((t - a) / (b - a), 0), 1) }
}

/// A loop drawn by hand around what is asked about: not quite closed, a little tilted.
private struct ArisSceneLasso: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY), rx = rect.width / 2, ry = rect.height / 2
        let steps = 48
        for i in 0...steps {
            let a = Double(i) / Double(steps) * 2.15 * .pi - 0.6
            let wobble = 1 + 0.05 * sin(a * 3)
            let point = CGPoint(x: c.x + rx * wobble * cos(a), y: c.y + ry * wobble * sin(a) - CGFloat(i) * 0.06)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Aris's notch in the scene: black, the notch's own outline, growing from closed (128 × 22) to listening (292 × 34,
/// Aris's star, four waving bars, the words coming in 80 ms apart) to the answer (300 wide), and back.
private struct ArisSceneNotch: View {
    @Environment(\.arisSettingsArt) private var art
    let t: Double
    let query: String
    let answer: String?
    let feature: ArisFeature

    var body: some View {
        let state = ArisFeatureLook.notch(at: t)
        let answering = answer != nil
        let to = answering ? state.to : min(state.to, 1)
        let from = answering ? state.from : min(state.from, 1)
        let e = Self.ease(state.progress)
        let size = Self.lerp(size(from), size(to), e)
        let showQuery = (from >= 1 || to >= 1) && t > 0.124 && t < 0.905
        let showAnswer = answering && (from == 2 || to == 2) && t > 0.235 && t < 0.905
        ZStack(alignment: .top) {
            NotchShape(topCornerRadius: 6, bottomCornerRadius: size.height > 40 ? 22 : 12, circular: 1)
                .fill(LinearGradient(colors: [Color(arisHex: 0x030305), Color(arisHex: 0x0b0b0e)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(arisHex: 0x040a16, 0.42), radius: 11, y: 17)
                .shadow(color: Color(arisHex: 0x040a16, 0.24), radius: 3.5, y: 4)
            if showQuery || showAnswer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        art.star(20).frame(width: 18, height: 18)
                        ArisSceneWords(text: query, t: t).frame(maxWidth: .infinity, alignment: .leading)
                        ArisSceneWave(t: t).opacity(showAnswer ? 0 : 1)
                    }
                    .frame(height: 20)
                    if showAnswer, let answer {
                        Text(answer).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.92)).lineSpacing(2.5)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(Self.ramp(t, 0.235, 0.27) * (1 - Self.ramp(t, 0.885, 0.905)))
                        if feature == .savedSteps { steps }
                    }
                }
                .padding(.horizontal, 14).padding(.top, 7)
                .frame(width: size.width, alignment: .leading)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    /// The saved steps ticking off one by one in the answer.
    private var steps: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                let done = Self.ramp(t, 0.3 + Double(i) * 0.07, 0.34 + Double(i) * 0.07)
                Circle().fill(Color(arisHex: 0x2ebd54).opacity(0.25 + 0.75 * done)).frame(width: 7, height: 7)
                    .overlay(ArisLineIcon("check", size: 6, stroke: 3.5).foregroundStyle(.white).opacity(done))
            }
        }
    }

    /// The notch's size in a state; answering, as tall as the answer needs (its lines at 11 pt in 272, the steps' row).
    func size(_ state: Int) -> CGSize {
        switch state {
        case 0: return ArisFeatureLook.notchClosed
        case 1: return ArisFeatureLook.notchListening
        default:
            let text = (answer ?? "") as NSString
            let box = text.boundingRect(with: CGSize(width: ArisFeatureLook.notchAnswerWidth - 28, height: 200), options: [.usesLineFragmentOrigin],
                                        attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)])
            let lines = max(1, Int((box.height / 13).rounded()))
            return CGSize(width: ArisFeatureLook.notchAnswerWidth, height: 7 + 20 + 8 + CGFloat(lines) * 15.5 + (feature == .savedSteps ? 15 : 0) + 14)
        }
    }

    /// The measured open curve (0.22, 1, 0.36, 1), close enough as an ease-out.
    static func ease(_ x: Double) -> Double { 1 - pow(1 - x, 3.4) }
    static func lerp(_ a: CGSize, _ b: CGSize, _ e: Double) -> CGSize {
        CGSize(width: a.width + (b.width - a.width) * e, height: a.height + (b.height - a.height) * e)
    }
    static func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double { min(max((t - a) / (b - a), 0), 1) }
}

/// The question's words, each in from a 2.5-pt blur and 2 down, 80 ms apart, from 14% of the loop.
private struct ArisSceneWords: View {
    let text: String
    let t: Double

    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        HStack(spacing: 3) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                let start = 0.14 + Double(index) * (0.08 / ArisFeatureLook.loop)
                let shown = ArisSceneNotch.ramp(t, start, start + 0.025)
                Text(word).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.95))
                    .blur(radius: 2.5 * (1 - shown)).offset(y: 2 * (1 - shown)).opacity(shown)
            }
        }
        .lineLimit(1)
    }
}

/// Four bars waving while Aris listens (1.1 s a wave).
private struct ArisSceneWave: View {
    let t: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                let phase = (t * ArisFeatureLook.loop / 1.1 + Double(i) * 0.22) * 2 * .pi
                Capsule().fill(.white.opacity(0.85)).frame(width: 2.5, height: 4 + 7 * CGFloat(0.5 + 0.5 * sin(phase)))
            }
        }
        .frame(width: 18, height: 14)
    }
}

/// The notice card sliding down under the notch while the notch stays closed.
private struct ArisSceneNotice: View {
    let t: Double
    let title: String
    let line: String

    var body: some View {
        let shown = ArisSceneNotch.ramp(t, 0.16, 0.24) * (1 - ArisSceneNotch.ramp(t, 0.86, 0.93))
        HStack(alignment: .top, spacing: 9) {
            ArisIconTile("check", size: 26, fill: .gradient(top: Color(arisHex: 0x58dd7c), bottom: Color(arisHex: 0x23a047)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                Text(line).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 250)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(arisHex: 0x141418, 0.92)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
        .offset(y: 30 + 10 * (1 - shown))
        .opacity(shown)
        .scaleEffect(0.96 + 0.04 * shown, anchor: .top)
    }
}

/// The second tile: on black, the notch open with the question and the answer as they land.
struct ArisFeatureAnswerTile: View {
    @Environment(\.arisSettingsArt) private var art
    let query: String
    let answer: String
    let feature: ArisFeature

    var body: some View {
        if feature == .notify {
            // A notice lands as its card, under a closed notch.
            VStack(spacing: 10) {
                NotchShape(topCornerRadius: 6, bottomCornerRadius: 12, circular: 1).fill(Color(arisHex: 0x030305))
                    .frame(width: ArisFeatureLook.notchClosed.width, height: ArisFeatureLook.notchClosed.height)
                ArisSceneNotice(t: 0.5, title: query, line: answer).offset(y: -30).scaleEffect(1.25, anchor: .top)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RadialGradient(colors: [Color(arisHex: 0x23262e), Color(arisHex: 0x111111)], center: .top, startRadius: 0, endRadius: 260))
        } else {
            answerNotch
        }
    }

    private var answerNotch: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    art.star(20).frame(width: 20, height: 20)
                    Text(query).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                }
                Text(answer).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.94)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 20)
            .frame(width: 340, alignment: .leading)
            .background(NotchShape(topCornerRadius: 8, bottomCornerRadius: 24, circular: 1)
                .fill(LinearGradient(colors: [Color(arisHex: 0x030305), Color(arisHex: 0x0b0b0e)], startPoint: .top, endPoint: .bottom)))
            .overlay(NotchShape(topCornerRadius: 8, bottomCornerRadius: 24, circular: 1).stroke(.white.opacity(0.07), lineWidth: 1))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RadialGradient(colors: [Color(arisHex: 0x23262e), Color(arisHex: 0x111111)], center: .top, startRadius: 0, endRadius: 260))
    }
}
