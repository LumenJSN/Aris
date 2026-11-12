//
//  ArisSkillFlow.swift
//  Aris
//
//  The notch's side of the user's skills (mockup skills.html, the shared notch flows): the small "<title> 스킬 사용 중" tag
//  over an answer that followed a skill, and the steps of "이 링크 스킬 추가해줘 <link>" in the result slot: 스킬 기능을
//  켤까요? (나중에 / 켜기), the setup's progress (or 준비하지 못했어요 with 다시 시도), GitHub에서 받는 중, the check's
//  progress, then added (what SkillSpector confirmed), caution (그래도 추가 / 취소) or blocked (막은 이유). The check runs
//  in aris-agent: the notch may close; the inbox says how it ended. Dark glass, nothing blinks.
//
//  Every line is written in Korean here and drawn through the 스킬 page's wording (`w`, the settings catalog), so on an
//  English Mac the flow reads the same English as the page, the helper's own lines and a finding's file included; what
//  an AI wrote (a finding, a skill's name) is drawn as it came.
//

import SwiftUI

/// A done step as a chip ("✓ 스킬 기능 준비됨"), or one under way ("GitHub에서 받는 중").
private struct ArisSkillStepChip: View {
    let text: String
    var symbol = "checkmark"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
            Text(text).font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.72))
        .padding(.horizontal, 10).frame(height: 26)
        .background(Capsule().fill(.white.opacity(0.08)))
    }
}

/// What the flow's buttons do (ArisSkillsModel's, or a render's stand-ins).
struct ArisSkillFlowActions {
    var later: () -> Void = {}
    var turnOn: () -> Void = {}
    var retry: () -> Void = {}
    var decide: (String, Bool) -> Void = { _, _ in }
    var go: (String) -> Void = { _ in }
    var shown: (Bool) -> Void = { _ in }
}

struct ArisSkillFlowView: View {
    let status: ArisSkillsStatus
    let flow: ArisSkillNotchFlow
    var budget: CGFloat = 440
    var actions = ArisSkillFlowActions()
    /// The 스킬 page's wording: Korean as written, English from the settings catalog on an English Mac.
    var w = ArisSkillWords.notchWording()

    private static let card = Color(red: 0x18 / 255, green: 0x19 / 255, blue: 0x1C / 255)
    private static let warn = Color(red: 0xfb / 255, green: 0xbf / 255, blue: 0x24 / 255)
    private static let bad = Color(red: 0xf8 / 255, green: 0x71 / 255, blue: 0x71 / 255)
    private static let ok = Color(red: 0x4a / 255, green: 0xde / 255, blue: 0x80 / 255)

    var body: some View {
        ArisFadingScroll(budget: budget) {
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .onAppear { actions.shown(true) }
        .onDisappear { actions.shown(false) }
    }

    private var job: ArisSkillJobRow? { flow.job.flatMap { id in status.jobs.first { $0.id == id } } }

    @ViewBuilder private var content: some View {
        if flow.dropped {
            Text(w("알겠어요. 필요할 때 설정의 스킬에서 켜면 돼요.")).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
        } else if !status.ready {
            setup
        } else {
            HStack(spacing: 8) {
                ArisSkillStepChip(text: w("스킬 기능 준비됨"))
                if job?.outcome == "added" { ArisSkillStepChip(text: w("안전 검사 통과")) }
            }
            if let problem = flow.problem {
                line(w(problem))
            } else if let job {
                jobSteps(job)
            }
        }
    }

    // MARK: setup

    @ViewBuilder private var setup: some View {
        switch status.setup.state {
        case "installing":
            box {
                title(w("스킬 기능 준비 중"))
                note(w("보안 검사 도구(SkillSpector)와 파이썬을 Aris 폴더에 설치해요 · 약 \(status.setup.totalMB)MB · 1~2분"))
                bar(status.setup.fraction)
                HStack {
                    Text(setupStep)
                    Spacer()
                    Text("\(status.setup.doneMB) / \(status.setup.totalMB)MB").monospacedDigit()
                }
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
            }
        case "failed":
            box {
                title(w("준비하지 못했어요"))
                note(w(status.setup.message ?? "다시 시도해 주세요."))
                bar(status.setup.fraction, color: Self.bad)
                HStack(spacing: 8) {
                    Spacer()
                    button(w("취소"), bright: false) { actions.later() }
                    button(w("다시 시도"), bright: true) { actions.retry() }
                }
            }
        default:
            box {
                title(w("스킬 기능을 켤까요?"))
                note(w("스킬은 아직 꺼져 있어요. 처음 한 번 작은 준비가 필요해요. 보안 검사 도구(SkillSpector)와 파이썬을 Aris 폴더에 설치해요 · 약 \(status.setup.totalMB)MB · 1~2분"))
                HStack(spacing: 8) {
                    Spacer()
                    button(w("나중에"), bright: false) { actions.later() }
                    button(w("켜기"), bright: true) { actions.turnOn() }
                }
            }
        }
    }

    /// The setup's step as the helper names it; its first one ("준비 중") is “Getting ready” in English, as on the 스킬 page
    /// (the catalog's 준비 중 is another line's: a feature that is still coming).
    private var setupStep: String {
        let step = status.setup.step
        return step.isEmpty || step == "준비 중" ? ArisUIWords.text("준비 중", "Getting ready", english: w.pageEnglish) : w(step)
    }

    // MARK: the job

    @ViewBuilder private func jobSteps(_ job: ArisSkillJobRow) -> some View {
        switch (job.stage, job.outcome) {
        case ("fetching", _):
            ArisSkillStepChip(text: w("GitHub에서 받는 중"), symbol: "arrow.down")
        case ("review", _):
            meta(job)
            box {
                title(w("추가하기 전에 같이 확인해요"))
                note(w("인터넷에서 받은 스킬은 나쁜 일을 하도록 만들어졌을 수도 있어요. 그래서 추가하기 전에 SkillSpector로 검사해요."))
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(job.files.prefix(6), id: \.path) { file in
                        Text(file.path).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                }
                HStack(spacing: 8) {
                    Spacer()
                    button(w("그만두기"), bright: false) { actions.decide(job.id, false) }
                    button(w("검사하고 추가"), bright: true) { actions.go(job.id) }
                }
            }
        case ("checking", _):
            meta(job)
            box {
                title(w("이 스킬 안전한지 확인하고 있어요"))
                note(w("몇 분 걸릴 수 있어요. 노치를 닫아도 돼요, 끝나면 알려 드려요."))
                bar(Double(job.percent) / 100)
                HStack(spacing: 12) {
                    Text(w("정적 검사")).foregroundStyle(.white.opacity(job.step != "review" ? 0.9 : 0.45))
                    Text(w("AI 검토")).foregroundStyle(.white.opacity(job.step == "review" ? 0.9 : 0.45))
                    Spacer()
                    Text("\(job.percent)%").monospacedDigit().foregroundStyle(.white.opacity(0.5))
                }
                .font(.system(size: 11.5, weight: .semibold))
            }
        case ("done", "added"?):
            meta(job)
            headline(w((job.title ?? job.name).map { "\($0) 스킬을 추가했어요." } ?? "새 스킬을 추가했어요."))
            line(w("이제 “\(job.title ?? job.name ?? "") 스킬로 해줘”라고 하면 써요. 연결한 AI \(max(1, status.brains.count))개로 시험도 하고 있어요."))
            section(w("SkillSpector가 확인한 것"), job.checked, Self.ok)
        case ("done", "caution"?):
            meta(job)
            headline(w("추가하기 전에 확인할 게 \(job.findings.count)개 있어요."))
            section(w("주의"), job.findings, Self.warn)
            box {
                title(w("그래도 추가할까요?"))
                note(w("위험하진 않아요. 스크립트는 그래도 Aris 안전 검사를 거쳐요."))
                HStack(spacing: 8) {
                    Spacer()
                    button(w("취소"), bright: false) { actions.decide(job.id, false) }
                    button(w("그래도 추가"), bright: true, tint: Self.warn) { actions.decide(job.id, true) }
                }
            }
        case ("done", "blocked"?):
            meta(job)
            headline(w("위험해서 추가하지 않았어요."))
            section(w("막은 이유"), job.findings, Self.bad)
            Text(w("아무것도 설치하거나 실행하지 않았어요 · 받은 파일은 지웠어요 · SkillSpector")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
        case ("done", "cancelled"?):
            line(w("추가하지 않았어요. 받은 파일은 지웠어요."))
        default:
            line(w(job.message ?? "스킬을 추가하지 못했어요."))
        }
    }

    private func meta(_ job: ArisSkillJobRow) -> some View {
        HStack(spacing: 10) {
            let look = ArisSkillLook.pick(name: job.name ?? job.source, title: job.title ?? "")
            Image(systemName: look.symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.sRGB, red: Double(look.tint >> 16 & 0xff) / 255,
                                                                                               green: Double(look.tint >> 8 & 0xff) / 255, blue: Double(look.tint & 0xff) / 255)))
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title ?? job.name ?? job.source).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.95))
                Text(w(ArisSkillWords.meta(job, fileCount: true))).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
        }
    }

    private func section(_ label: String, _ lines: [ArisSkillLine], _ dot: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
            ForEach(lines, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(dot).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(w(item.text)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                        Text(w(item.file)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
        }
    }

    // MARK: pieces

    private func box<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Self.card))
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.95))
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).lineSpacing(4).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
    }

    private func headline(_ text: String) -> some View {
        Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.95)).fixedSize(horizontal: false, vertical: true)
    }

    private func line(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).lineSpacing(4).foregroundStyle(.white.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
    }

    private func bar(_ fraction: Double, color: Color = .white.opacity(0.9)) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule().fill(color).frame(width: max(4, geometry.size.width * min(1, max(0, fraction))))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .frame(height: 4)
    }

    private func button(_ title: String, bright: Bool, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(bright ? .white.opacity(0.95) : .white.opacity(0.5))
                .padding(.horizontal, 14).frame(height: 30)
                .overlay(Capsule().strokeBorder(bright ? tint.opacity(0.5) : .white.opacity(0.1), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
