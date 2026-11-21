//
//  ArisVoiceEnrolSheet.swift
//  Aris
//
//  Settings › 부르기 › 내 목소리 등록하기's sheet (F1), in the settings window's own sheet frame, the way 호출어 녹음's is
//  drawn (ArisWakeRecordSheet: ArisSheetFrame, ArisPillButton, the palette's tokens, its progress bar and level): how
//  far the five sentences are, then one sentence at a time in large type with the microphone's level under it while
//  it records. The work is ArisVoiceEnrolModel's.
//

import SwiftUI

struct ArisVoiceEnrolSheet: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsStill) private var still
    @ObservedObject var model: ArisVoiceEnrolModel
    let close: () -> Void

    private typealias Copy = ArisVoiceIDRows.Sheet

    var body: some View {
        ArisSheetFrame(title: Copy.title, subtitle: subtitle, onClose: finish) {
            VStack(alignment: .leading, spacing: 0) {
                progress.padding(.top, 14)
                stage.padding(.top, 14)
            }
        } footer: {
            footer
        }
        .onAppear { if !still { model.open() } }
        .onDisappear { model.stop() }
    }

    private func finish() {
        model.stop()
        close()
    }

    private var subtitle: String? {
        switch model.phase {
        case .intro: Copy.intro
        case .done: Copy.doneLine
        default: nil
        }
    }

    private var done: Int {
        switch model.phase {
        case .learning, .done: model.total
        case .saved: model.index + 1
        default: model.index
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(w(Copy.title)).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.desc)
                Spacer(minLength: 0)
                Text("\(done)/\(model.total)").font(.system(size: 12)).monospacedDigit().foregroundStyle(palette.faint)
            }
            bar(Double(done) / Double(max(1, model.total)))
        }
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.switchOff)
                Capsule().fill(palette.title).frame(width: proxy.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 4)
        .animation(still ? nil : .easeOut(duration: 0.2), value: fraction)
    }

    @ViewBuilder private var stage: some View {
        switch model.phase {
        case .intro:
            Text(w(Copy.introPrivacy)).font(.system(size: 12)).foregroundStyle(palette.faint).fixedSize(horizontal: false, vertical: true)
        case .ready, .listening, .saved, .retry:
            prompt
        case .learning:
            Text(w(Copy.learning)).font(.system(size: 13)).foregroundStyle(palette.desc)
        case .failed(let line):
            Text(w(line)).font(.system(size: 13)).foregroundStyle(palette.desc).fixedSize(horizontal: false, vertical: true)
        case .done:
            HStack(spacing: 8) {
                ArisLandingCheck()
                Text(w(Copy.done)).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.title)
            }
        }
    }

    /// The sentence to read, what to do now, and the level.
    private var prompt: some View {
        VStack(alignment: .center, spacing: 10) {
            Text(model.sentence).font(.system(size: 22, weight: .semibold)).foregroundStyle(palette.title)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
            Text(w(status)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(model.phase == .listening ? palette.title : palette.desc)
            bar(model.phase == .listening ? Double(model.level) : 0).frame(width: 160)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.soft))
    }

    private var status: String {
        switch model.phase {
        case .ready: Copy.ready
        case .listening: Copy.listening
        case .saved: Copy.saved
        case .retry: Copy.again
        default: ""
        }
    }

    @ViewBuilder private var footer: some View {
        switch model.phase {
        case .intro:
            ArisPillButton(title: Copy.close, kind: .ghost, action: finish)
            ArisPillButton(title: Copy.start) { model.begin() }
        case .ready, .listening, .saved, .retry:
            ArisPillButton(title: Copy.stop, kind: .ghost) { model.stop() }
        case .learning:
            EmptyView()
        case .failed:
            ArisPillButton(title: Copy.close, kind: .ghost, action: finish)
            ArisPillButton(title: Copy.start) { model.begin() }
        case .done:
            ArisPillButton(title: Copy.close, action: finish)
        }
    }
}
