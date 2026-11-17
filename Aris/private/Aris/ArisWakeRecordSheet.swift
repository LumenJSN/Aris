//
//  ArisWakeRecordSheet.swift
//  Aris
//
//  Settings › 대화 › 호출어 녹음's sheet, in the settings window's own sheet frame (ArisSheetFrame, ArisPillButton, the
//  palette's tokens; the bars are the AI 서비스 card's usage bar: a switch-off track and a title-ink fill). It shows how
//  far the takes are, the block's instruction, then one line at a time in large type with the microphone's level
//  under it while a take records. The work is ArisWakeRecorderModel's.
//

import SwiftUI

struct ArisWakeRecordSheet: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsStill) private var still
    @ObservedObject var model: ArisWakeRecorderModel
    let close: () -> Void

    private typealias Copy = ArisWakeRecordRows.Sheet

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

    // MARK: - Parts

    /// “34/170” and the bar.
    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(w(model.step.map(ArisWakeScript.counter) ?? Copy.title)).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.desc)
                Spacer(minLength: 0)
                Text("\(model.done)/\(model.total)").font(.system(size: 12)).monospacedDigit().foregroundStyle(palette.faint)
            }
            bar(Double(model.done) / Double(max(1, model.total)))
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
        case .block:
            if let step = model.step {
                VStack(alignment: .leading, spacing: 4) {
                    Text(w(step.block.title)).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.title)
                    Text(w(step.block.how)).font(.system(size: 13)).foregroundStyle(palette.desc).lineSpacing(2.5).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.soft))
            }
        case .ready, .listening, .saved, .retry:
            prompt
        case .failed(let line):
            Text(w(line)).font(.system(size: 13)).foregroundStyle(palette.desc).fixedSize(horizontal: false, vertical: true)
        case .done:
            HStack(spacing: 8) {
                ArisLandingCheck()
                Text(w(Copy.done)).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.title)
            }
        }
    }

    /// The line to say, what to do now, and the level.
    private var prompt: some View {
        VStack(alignment: .center, spacing: 10) {
            Text(model.step?.prompt.phrase ?? "").font(.system(size: 26, weight: .semibold)).foregroundStyle(palette.title)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(w(status)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(model.phase == .listening ? palette.title : palette.desc)
            bar(model.phase == .listening ? Double(model.level) : 0).frame(width: 160)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.soft))
    }

    private var status: String {
        switch model.phase {
        case .ready: Copy.ready
        case .listening: Copy.listening
        case .saved: Copy.saved
        case .retry(let line): line
        default: ""
        }
    }

    @ViewBuilder private var footer: some View {
        switch model.phase {
        case .intro:
            ArisPillButton(title: Copy.close, kind: .ghost, action: finish)
            ArisPillButton(title: model.done == 0 ? Copy.start : Copy.resume) { model.begin() }
        case .block:
            if model.step?.block.optional == true { ArisPillButton(title: Copy.skip, kind: .ghost) { model.skipBlock() } }
            ArisPillButton(title: Copy.start) { model.startBlock() }
        case .ready, .listening, .saved, .retry:
            ArisPillButton(title: Copy.stop, kind: .ghost) { model.stop() }
        case .failed:
            if model.step?.block.optional == true { ArisPillButton(title: Copy.skip, kind: .ghost) { model.skipBlock() } }
            ArisPillButton(title: Copy.again) { model.retryBlock() }
        case .done:
            ArisPillButton(title: Copy.close, action: finish)
        }
    }
}
