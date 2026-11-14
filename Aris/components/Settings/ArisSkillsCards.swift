//
//  ArisSkillsCards.swift
//  Aris
//
//  The cards inside settings › 스킬's chat (mockup skills.html, option C): the setup's progress (then 준비됐어요, or the
//  failure with 다시 시도), a skill being added (the GitHub card with its files, 검사하고 추가; the check's progress with
//  its two steps; then safe, caution with 그래도 추가 / 취소, or blocked with the reasons), and a draft 말로 만들기 wrote.
//  Drawn in the settings window's palette, light and dark; nothing blinks.
//

import SwiftUI

/// A thin bar that fills (the setup's megabytes, the check's percent); red when it failed.
struct ArisSkillBar: View {
    @Environment(\.arisPalette) private var palette
    let fraction: Double
    var failed = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.segTrack)
                Capsule().fill(failed ? palette.bad : palette.accent)
                    .frame(width: max(6, geometry.size.width * min(1, max(0, fraction))))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .frame(height: 6)
        .accessibilityValue("\(Int(fraction * 100))%")
    }
}

/// A bordered inner card (the setup, the check).
enum ArisSkillTone { case plain, ok, warn, bad }

struct ArisSkillInset<Content: View>: View {
    @Environment(\.arisPalette) private var palette
    var tone: ArisSkillTone = .plain
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
    }

    private var fill: Color {
        switch tone {
        case .ok: palette.okFill
        case .warn: palette.dark ? Color(arisHex: 0xf59e0b, 0.1) : Color(arisHex: 0xfffbeb)
        case .bad: palette.redFill
        default: palette.well
        }
    }

    private var border: Color {
        switch tone {
        case .ok: palette.ok.opacity(0.35)
        case .warn: Color(arisHex: 0xf59e0b, palette.dark ? 0.3 : 0.35)
        case .bad: palette.redBorder
        default: palette.line
        }
    }
}

/// The setup: installing (its step and megabytes), done, or failed with 다시 시도.
struct ArisSkillSetupCard: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let setup: ArisSkillSetupRow
    let retry: () -> Void

    /// The step under the bar. Before the helper names one it is 준비 중, which here is "getting ready" (the same
    /// words on a chip elsewhere in the window mean "coming").
    private var step: String {
        setup.step.isEmpty || setup.step == "준비 중" ? (w.pageEnglish ? "Getting ready" : "준비 중") : w(setup.step)
    }

    var body: some View {
        switch setup.state {
        case "ready":
            ArisSkillInset(tone: .ok) {
                HStack(spacing: 12) {
                    ArisSkillBadge(symbol: "checkmark", tint: palette.ok)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(w("준비됐어요")).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(palette.title)
                        Text(w("SkillSpector와 파이썬(Aris 전용)을 설치했어요. 이제 스킬을 추가할 수 있어요.")).font(.system(size: 12)).foregroundStyle(palette.desc)
                    }
                }
            }
        case "failed":
            ArisSkillInset(tone: .bad) {
                Text(w("준비하지 못했어요")).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.title)
                Text(w(setup.message ?? "다시 시도해 주세요.")).font(.system(size: 12)).foregroundStyle(palette.desc).fixedSize(horizontal: false, vertical: true)
                ArisSkillBar(fraction: setup.fraction, failed: true)
                HStack { Spacer(); ArisSettingsButton(title: "다시 시도", kind: .primary, small: true, action: retry) }
            }
        default:
            ArisSkillInset {
                Text(w("보안 검사 도구(SkillSpector)와 파이썬을 Aris 폴더에 설치해요 · 약 \(setup.totalMB)MB · 1~2분"))
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(palette.title).fixedSize(horizontal: false, vertical: true)
                ArisSkillBar(fraction: setup.fraction)
                HStack {
                    Text(step).font(.system(size: 11.5)).foregroundStyle(palette.desc)
                    Spacer()
                    Text("\(setup.doneMB) / \(setup.totalMB)MB").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(palette.desc)
                }
            }
        }
    }
}

/// A round mark with a symbol (the check's outcome).
struct ArisSkillBadge: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ArisLineIcon(symbol, size: 14, stroke: 2.5).foregroundStyle(.white)
            .frame(width: 26, height: 26).background(Circle().fill(tint))
    }
}

/// One file of a skill: its icon, path, what it does, and a tag.
struct ArisSkillFileLine: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let file: ArisSkillFileRow
    let findings: [ArisSkillLine]
    let checked: [ArisSkillLine]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ArisLineIcon(file.kind == "script" ? "chevron.left.forwardslash.chevron.right" : "doc", size: 14).foregroundStyle(palette.icon).frame(width: 16).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.path).font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.title)
                Text(w(ArisSkillWords.fileLine(file, notes: findings + checked))).font(.system(size: 11.5)).foregroundStyle(palette.desc).lineLimit(2)
            }
            Spacer(minLength: 8)
            if let tag = ArisSkillWords.fileTag(file, findings: findings, checked: checked) {
                ArisChip(text: tag.text, tone: tag.warn ? .warn : .plain)
            }
        }
        .padding(.vertical, 9)
    }
}

/// A skill being added: the GitHub card (and 검사하고 추가), the check under way, then its outcome.
struct ArisSkillJobCard: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let job: ArisSkillJobRow
    let go: () -> Void
    let decide: (Bool) -> Void

    var body: some View {
        switch (job.stage, job.outcome) {
        case ("review", _): review
        case ("done", "added"?): outcome(tone: .ok, symbol: "checkmark", title: "안전해요 · 추가했어요",
                                          line: "정적 검사와 AI 검토 모두 문제를 찾지 못했어요.", lines: job.checked)
        case ("done", "caution"?):
            VStack(alignment: .leading, spacing: 10) {
                outcome(tone: .warn, symbol: "exclamationmark", title: "확인할 게 \(job.findings.count)개 있어요",
                        line: "위험하진 않아요. 스크립트는 그래도 Aris 안전 검사를 거쳐요.", lines: job.findings)
                HStack(spacing: 8) {
                    Spacer()
                    ArisSettingsButton(title: "취소", small: true) { decide(false) }
                    ArisSettingsButton(title: "그래도 추가", kind: .primary, small: true) { decide(true) }
                }
            }
        case ("done", "blocked"?): outcome(tone: .bad, symbol: "xmark", title: "위험해서 추가하지 않았어요",
                                            line: "아무것도 설치하거나 실행하지 않았어요 · 받은 파일은 지웠어요", lines: job.findings)
        case ("done", "cancelled"?): Text(w("그만뒀어요. 받은 파일은 지웠어요.")).font(.system(size: 12)).foregroundStyle(palette.desc)
        case ("done", _): Text(w(job.message ?? "추가하지 못했어요.")).font(.system(size: 12.5)).foregroundStyle(palette.bad).fixedSize(horizontal: false, vertical: true)
        case ("fetching", _): ArisSkillInset { Label(w(job.kind == "link" ? "GitHub에서 받는 중" : "준비하는 중"), systemImage: "arrow.down.circle")
            .font(.system(size: 12.5, weight: .medium)).foregroundStyle(palette.desc) }
        default: checking
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ArisSkillTile(name: job.name ?? job.source, title: job.title ?? "", size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title ?? job.name ?? job.source).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.title)
                    Text(w(ArisSkillWords.meta(job))).font(.system(size: 11.5)).foregroundStyle(palette.desc).lineLimit(1)
                }
            }
            .padding(14)
            Rectangle().fill(palette.hairline).frame(height: 1)
            VStack(alignment: .leading, spacing: 12) {
                ArisSkillInset(tone: .warn) {
                    HStack(alignment: .top, spacing: 10) {
                        ArisLineIcon("exclamationmark.triangle", size: 16).foregroundStyle(palette.warn)
                        (Text(w("인터넷에서 받은 스킬은 나쁜 일을 하도록 만들어졌을 수도 있어요. ")).fontWeight(.semibold)
                         + Text(w("그래서 추가하기 전에 SkillSpector로 검사해요.")))
                            .font(.system(size: 12.5)).foregroundStyle(palette.title).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(w("파일 \(job.files.count)개 · 스크립트가 하는 일")).font(.system(size: 11.5)).foregroundStyle(palette.desc)
                VStack(spacing: 0) {
                    ForEach(Array(job.files.prefix(12).enumerated()), id: \.offset) { index, file in
                        ArisSkillFileLine(file: file, findings: job.findings, checked: job.checked)
                        if index < min(job.files.count, 12) - 1 { Rectangle().fill(palette.hairline).frame(height: 1) }
                    }
                }
            }
            .padding(14)
            Rectangle().fill(palette.hairline).frame(height: 1)
            HStack(spacing: 8) {
                Spacer()
                ArisSettingsButton(title: "그만두기") { decide(false) }
                ArisSettingsButton(title: "검사하고 추가", kind: .primary, action: go)
            }
            .padding(12)
        }
        .arisCard(radius: 16)
    }

    private var checking: some View {
        ArisSkillInset {
            (Text(w("이 스킬 안전한지 확인하고 있어요")).fontWeight(.semibold) + Text(w(" · 몇 분 걸릴 수 있어요")).foregroundColor(palette.desc))
                .font(.system(size: 13)).foregroundStyle(palette.title)
            ArisSkillBar(fraction: Double(job.percent) / 100)
            HStack(spacing: 14) {
                step(1, "정적 검사", on: job.step != "review")
                step(2, "AI 검토", on: job.step == "review")
                Spacer()
                Text("\(job.percent)%").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(palette.desc)
            }
            Text(w("SkillSpector가 스크립트와 SKILL.md를 규칙으로 살펴본 뒤, AI가 하는 일이 설명과 맞는지 읽어 봐요. 창을 닫아도 돼요. 끝나면 알려 드려요."))
                .font(.system(size: 12)).foregroundStyle(palette.desc).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ number: Int, _ title: String, on: Bool) -> some View {
        HStack(spacing: 6) {
            Text("\(number)").font(.system(size: 10, weight: .semibold)).frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(on ? palette.title : palette.ink3, lineWidth: 1))
            Text(w(title)).font(.system(size: 12, weight: on ? .semibold : .regular))
        }
        .foregroundStyle(on ? palette.title : palette.ink3)
    }

    private func outcome(tone: ArisSkillTone, symbol: String, title: String, line: String, lines: [ArisSkillLine]) -> some View {
        ArisSkillInset(tone: tone) {
            HStack(spacing: 10) {
                ArisSkillBadge(symbol: symbol, tint: tone == .ok ? palette.ok : tone == .warn ? palette.warn : palette.bad)
                Text(w(title)).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(palette.title)
            }
            Text(w(line)).font(.system(size: 12)).foregroundStyle(palette.desc).padding(.leading, 36)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lines, id: \.self) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w(item.text)).font(.system(size: 12.5)).foregroundStyle(palette.title).fixedSize(horizontal: false, vertical: true)
                        Text(w(item.file)).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.desc)
                    }
                }
            }
            .padding(.leading, 36).padding(.top, 2)
        }
    }
}

/// A skill's icon: the measured app-icon tile (ArisIconTile) on a gradient of the tint chosen by what the skill is about
/// (its title and name, by keyword, else picked from its name: always the same for one skill), its glyph white.
struct ArisSkillTile: View {
    let name: String
    var title = ""
    var size: CGFloat = 36

    var body: some View {
        let look = ArisSkillLook.pick(name: name, title: title)
        ArisIconTile(look.symbol, size: size, fill: .tinted(look.tint))
    }
}

/// A SKILL.md 말로 만들기 wrote: its file name, the front matter, the steps.
struct ArisSkillDraftCard: View {
    @Environment(\.arisPalette) private var palette
    let text: String
    let edit: (String) -> Void

    private var name: String { text.components(separatedBy: "\n").first { $0.hasPrefix("name:") }.map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) } ?? "skill" }

    var body: some View {
        let lines = text.components(separatedBy: "\n")
        let end = lines.dropFirst().firstIndex(of: "---") ?? 0
        let front = Array(lines[0...min(end, lines.count - 1)])
        let body = lines.dropFirst(end + 1).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ArisSkillTile(name: name, title: text, size: 36)
                Text("\(name)/SKILL.md · skill-creator").font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.desc)
                Spacer()
                ArisSettingsButton(title: "직접 고치기", small: true) { edit(name) }
            }
            .padding(14)
            Rectangle().fill(palette.hairline).frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(front.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(palette.ink3).lineLimit(1)
                }
                ForEach(Array(body.prefix(12).enumerated()), id: \.offset) { _, line in
                    if line.hasPrefix("#") {
                        Text(line.drop { $0 == "#" || $0 == " " }).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.title).padding(.top, 6)
                    } else {
                        Text(line).font(.system(size: 12.5)).foregroundStyle(palette.title).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
        }
        .arisCard(radius: 16)
    }
}
