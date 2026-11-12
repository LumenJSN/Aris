//
//  ArisSkillsPage.swift
//  Aris
//
//  Settings › 스킬, the owner's pick C ("말로 시작", mockups/skills.html): a chat with Aris first (turning skills on, a
//  GitHub link, 말로 만들기, a folder dragged in), then 내 스킬: each skill with how many AIs it was tried on and its
//  switch, opening to what the AI sees, the AIs it was tested with, its files and 말로 고치기 / SKILL.md 직접 고치기 /
//  모든 AI로 시험 / 삭제. Everything goes through ArisSkillsModel to aris-agent; light and dark from the palette.
//

import SwiftUI
import UniformTypeIdentifiers

/// Where the page reads and acts (ArisSkillsModel; a stand-in for the offscreen renders).
@MainActor
protocol ArisSkillsSource: ObservableObject {
    var status: ArisSkillsStatus { get }
    var chat: [ArisSkillChatItem] { get }
    var draft: String { get set }
    var expanded: Set<String> { get set }
    var settingsVisible: Bool { get set }
    func refresh()
    func turnOn(saying: Bool)
    func turnOff()
    func later()
    func retry()
    func send(_ raw: String?)
    func addFolder(_ url: URL)
    func go(_ job: String)
    func decide(_ job: String, accept: Bool)
    func suggest(_ text: String)
    func toggle(_ name: String, on: Bool)
    func remove(_ name: String)
    func tryAll(_ name: String)
    func edit(_ name: String)
    func reveal()
    func speakFix(_ row: ArisSkillRow)
}

extension ArisSkillsSource {
    func job(_ id: String) -> ArisSkillJobRow? { status.jobs.first { $0.id == id } }
}

struct ArisSkillsPage<Source: ArisSkillsSource>: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsArt) private var art
    @Environment(\.arisSettingsStill) private var still
    @ObservedObject var model: Source
    @State private var dropping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if ArisSkillsOff.shown(enabled: model.status.enabled, chatEmpty: model.chat.isEmpty) {
                // Off, and nothing said yet: the one thing to do here is to turn it on (item 19). The chat, the list
                // and the switch beside the title come with it.
                ArisSkillsOffCard(megabytes: model.status.setup.totalMB) { model.turnOn(saying: true) }
                    .id("skills.feature").arisFlash("skills.feature").modifier(ArisRise(index: 2))
            } else {
                ArisSkillsChat(model: model).id("skills.add").arisFlash("skills.add").modifier(ArisRise(index: 2))
                HStack {
                    Text(w("내 스킬 \(model.status.ready ? model.status.skills.count : 0)개")).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.desc)
                    Spacer()
                    Text(w("폴더를 끌어 놓아도 돼요")).font(.system(size: 11.5)).foregroundStyle(palette.ink3)
                }
                .padding(.horizontal, 6).padding(.top, 22).padding(.bottom, 10)
                list.id("skills.list").arisFlash("skills.list").modifier(ArisRise(index: 3))
            }
        }
        .modifier(ArisSkillsDrop(enabled: !still, dropping: $dropping) { url in model.addFolder(url) })
        .overlay {
            if dropping && model.status.ready {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .allowsHitTesting(false)
            }
        }
        .onAppear { model.settingsVisible = true; model.refresh() }
        .onDisappear { model.settingsVisible = false }
    }

    @ViewBuilder private var list: some View {
        if !model.status.ready || model.status.skills.isEmpty {
            Text(w(model.status.ready ? "아직 스킬이 없어요. 위에서 말하거나 링크를 붙여 넣어 보세요." : "스킬 기능을 켜면 여기에 내 스킬이 모여요."))
                .font(.system(size: 12.5)).foregroundStyle(palette.desc)
                .frame(maxWidth: .infinity).padding(.vertical, 26)
                .arisCard()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(model.status.skills.enumerated()), id: \.element.id) { index, row in
                    ArisSkillListRow(row: row, brains: model.status.brains, model: model)
                    if index < model.status.skills.count - 1 { Rectangle().fill(palette.hairline).frame(height: 1).padding(.leading, 70) }
                }
            }
            .arisCard()
        }
    }
}

/// A folder dropped anywhere on the page is added (not in the offscreen renders, which can't draw a drop target).
private struct ArisSkillsDrop: ViewModifier {
    let enabled: Bool
    @Binding var dropping: Bool
    let add: (URL) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [UTType.fileURL], isTargeted: $dropping) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in add(url) }
                }
                return true
            }
        } else {
            content
        }
    }
}

/// 스킬 while it is off (item 19): one card that says what turning it on gives and what it takes, and one button.
struct ArisSkillsOffCard: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsArt) private var art
    let megabytes: Int
    let turnOn: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: ArisSettingsMetrics.iconGap) {
            art.star(34).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(w("스킬을 켜면 일하는 방법을 가르칠 수 있어요")).font(.system(size: 14, weight: .medium)).tracking(-0.07).foregroundStyle(palette.title)
                Text(w("처음 한 번 준비가 필요해요 · 약 \(megabytes)MB · 1~2분")).font(.system(size: 12)).foregroundStyle(palette.desc)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ArisSettingsButton(title: "스킬 켜기", kind: .primary, action: turnOn)
        }
        .padding(ArisSettingsMetrics.rowInset)
        .arisCard()
    }
}

/// The 스킬 기능 switch beside the page's title (the shell's accessory), once the feature is on or being set up: while
/// it is off the page's one card is the way to turn it on, and a second control for the same thing would say it twice.
struct ArisSkillsSwitch<Source: ArisSkillsSource>: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @ObservedObject var model: Source

    var body: some View {
        let on = model.status.enabled
        HStack(spacing: 8) {
            Text(w("스킬 기능")).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.title)
            ArisSwitch(isOn: on, label: "스킬 기능") { on ? model.turnOff() : model.turnOn(saying: true) }
        }
    }
}

// MARK: - The chat

struct ArisSkillsChat<Source: ArisSkillsSource>: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsArt) private var art
    @Environment(\.arisSettingsStill) private var still
    @ObservedObject var model: Source
    /// The mic's hint: Aris's own dictation (right ⌥) types into the field.
    @State private var hint = false

    /// The example to start from, in the page's wording: pressed, it is what the skill's maker is asked.
    private var suggestion: String { w("시험 날짜 주면 공부 계획 짜기") }

    /// What the page itself put in the user's bubble (a pressed chip, a dropped folder) is said in the page's wording;
    /// what he typed is shown as he typed it.
    private func own(_ text: String) -> String {
        if ["켜 줘", "나중에"].contains(text) { return w(text) }
        if let folder = text.range(of: "폴더 · "), folder.lowerBound == text.startIndex { return w("폴더") + " · " + text[folder.upperBound...] }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                if model.chat.isEmpty && model.status.ready {
                    intro
                } else if model.chat.isEmpty {
                    arisLine("스킬 기능이 꺼져 있어요. 다시 켤까요?")
                }
                ForEach(model.chat) { item in itemView(item) }
            }
            .padding(24)
            Rectangle().fill(palette.hairline).frame(height: 1)
            composer.padding(.horizontal, 16).padding(.vertical, 14)
            if hint {
                Text(ArisDictationKey.Choice.current.naming(w("오른쪽 ⌥를 누른 채 말하면 여기에 받아 적어요."))).font(.system(size: 11.5)).foregroundStyle(palette.desc)
                    .padding(.horizontal, 24).padding(.bottom, 12)
            }
        }
        .arisCard()
    }

    /// The offer as a line of the chat (after 나중에, or when the feature was turned off again).
    private var offer: some View {
        HStack(alignment: .top, spacing: 12) {
            art.star(22).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text(w("스킬 기능은 아직 꺼져 있어요. 켤까요?")).font(.system(size: 13.5, weight: .medium)).foregroundStyle(palette.title)
                Text(w("처음 한 번 작은 준비가 필요해요. 보안 검사 도구(SkillSpector)와 파이썬을 Aris 폴더에 설치해요 · 약 \(model.status.setup.totalMB)MB · 1~2분."))
                    .font(.system(size: 12)).foregroundStyle(palette.desc).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    chip("켜 줘", symbol: "power") { model.turnOn(saying: true) }
                    chip("나중에") { model.later() }
                }
                .padding(.top, 6)
            }
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 14) {
            art.star(34).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 8) {
                Text(w("어떤 일을 스킬로 만들까요?")).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.title)
                Text(w("평소에 시키는 일을 말로 설명해 주세요. Aris 안의 skill-creator가 SKILL.md를 써 드려요. GitHub 링크를 붙여 넣으면 SkillSpector로 먼저 검사하고 알려 줘요."))
                    .font(.system(size: 12.5)).foregroundStyle(palette.desc).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                suggestions.padding(.top, 6)
            }
        }
    }

    private var suggestions: some View {
        ArisFlow(spacing: 8) {
            chip(suggestion, symbol: "sparkle") { model.suggest(suggestion) }
            chip("GitHub 링크 붙여 넣기", symbol: "link") {
                if let text = NSPasteboard.general.string(forType: .string), text.contains("github.com") { model.send(text) }
            }
            chip("폴더에서", symbol: "folder") { model.reveal() }
        }
    }

    private func arisLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            art.star(22).frame(width: 22, height: 22)
            Text(w(text)).font(.system(size: 13.5)).foregroundStyle(palette.title).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
        }
    }

    @ViewBuilder private func itemView(_ item: ArisSkillChatItem) -> some View {
        switch item.kind {
        case .aris(let text): arisLine(text)
        case .user(let text, let link): user(link ? text : own(text), link: link)
        case .offer: offer
        case .setup:
            ArisSkillSetupCard(setup: model.status.setup) { model.retry() }.padding(.leading, 34)
        case .suggestions: suggestions.padding(.leading, 34)
        case .job(let id):
            if let job = model.job(id) {
                ArisSkillJobCard(job: job, go: { model.go(id) }, decide: { model.decide(id, accept: $0) }).padding(.leading, 34)
                if job.stage == "done", job.outcome == "added" {
                    arisLine("추가했어요. 연결한 AI로 시험도 하는 중이에요. 이제 “\(job.title ?? job.name ?? "") 스킬로 해줘”라고 하면 써요.")
                }
            }
        case .draft(let text): ArisSkillDraftCard(text: text) { model.edit($0) }.padding(.leading, 34)
        case .thinking:
            HStack(spacing: 12) {
                art.star(22).frame(width: 22, height: 22)
                Text(w("생각하는 중…")).font(.system(size: 13)).foregroundStyle(palette.desc)
            }
        }
    }

    private func user(_ text: String, link: Bool) -> some View {
        HStack {
            Spacer(minLength: 60)
            HStack(spacing: 6) {
                if link { Image(systemName: "link").font(.system(size: 11)) }
                Text(text).font(.system(size: link ? 12.5 : 13.5, design: link ? .monospaced : .default)).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(palette.title)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.chip))
        }
    }

    private func chip(_ title: String, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11)) }
                Text(w(title)).font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(palette.buttonText)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(palette.buttonFill))
            .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
        }
        .buttonStyle(ArisPressScale())
    }

    // MARK: composer

    private var composer: some View {
        let ready = model.status.ready
        return HStack(spacing: 10) {
            if ready && !model.chat.isEmpty {
                round(symbol: "plus", filled: false) { model.reveal() }.help(w("폴더에서 추가"))
            }
            Group {
                if still {
                    Text(model.draft.isEmpty ? placeholder : model.draft).foregroundStyle(model.draft.isEmpty ? palette.ink3 : palette.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(placeholder, text: $model.draft).textFieldStyle(.plain).onSubmit { model.send(nil) }.disabled(!ready)
                }
            }
            .font(.system(size: 13.5))
            .padding(.horizontal, 16).frame(height: 42)
            .background(Capsule().fill(palette.field))
            .overlay(Capsule().strokeBorder(palette.fieldBorder, lineWidth: 1))
            round(symbol: "mic", filled: false) { hint.toggle() }.help(ArisDictationKey.Choice.current.naming(w("오른쪽 ⌥를 누른 채 말하기"))).disabled(!ready)
            round(symbol: "arrow.up", filled: true) { model.send(nil) }.disabled(!ready)
        }
    }

    private var placeholder: String { w(model.status.ready ? "말하거나 적어 보세요. GitHub 링크도 돼요" : "스킬 기능을 켜면 쓸 수 있어요") }

    private func round(symbol: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(filled ? palette.primaryInk : palette.icon)
                .frame(width: 38, height: 38)
                .background(Circle().fill(filled ? AnyShapeStyle(palette.primary) : AnyShapeStyle(palette.buttonFill)))
                .overlay(Circle().strokeBorder(filled ? .clear : palette.line, lineWidth: 1))
        }
        .buttonStyle(ArisPressScale(scale: 0.95))
    }
}

// MARK: - The list

struct ArisSkillListRow<Source: ArisSkillsSource>: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let row: ArisSkillRow
    let brains: [String]
    @ObservedObject var model: Source
    @State private var hovering = false

    private var open: Bool { model.expanded.contains(row.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if open { ArisSkillDetail(row: row, brains: brains, model: model).padding(.leading, 70).padding(.trailing, 20).padding(.bottom, 18) }
        }
        .background(hovering && !open ? palette.rowHover : .clear)
        .onHover { hovering = $0 }
        .opacity(row.enabled || open ? 1 : 0.72)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ArisSkillTile(name: row.name, title: row.title, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(palette.title)
                // Where it came from in the page's wording, then the skill's own line as it was written.
                Text(w(ArisSkillWords.source(row)) + " · " + (row.summary.isEmpty ? row.description : row.summary))
                    .font(.system(size: 12)).foregroundStyle(palette.desc).lineLimit(1)
            }
            Spacer(minLength: 8)
            phase
            ArisSwitch(isOn: row.enabled, label: row.title) { model.toggle(row.name, on: !row.enabled) }
            Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.ink3).frame(width: 14)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(ArisSettingsMotion.house(0.3)) {
                if open { model.expanded.remove(row.name) } else { model.expanded.insert(row.name) }
            }
        }
    }

    @ViewBuilder private var phase: some View {
        switch row.phase {
        case "checking": ArisChip(text: "검사 중")
        case "waiting": ArisChip(text: "확인 필요", tone: .warn)
        case "blocked": ArisChip(text: "막음", tone: .warn)
        default:
            let tested = ArisSkillWords.tested(row, brains: brains)
            ArisChip(text: (tested.text == "시험 전" ? "" : "✓ ") + w(tested.text), tone: tested.all ? .ok : .plain)
        }
    }
}

struct ArisSkillDetail<Source: ArisSkillsSource>: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let row: ArisSkillRow
    let brains: [String]
    @ObservedObject var model: Source

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("AI가 보는 것")
            (Text(row.name).font(.system(size: 12.5, weight: .semibold, design: .monospaced)) + Text(" — " + row.description).font(.system(size: 12.5)))
                .foregroundStyle(palette.title).fixedSize(horizontal: false, vertical: true)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.well))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
            if row.phase == "waiting" || row.phase == "blocked" { findings }
            label("어느 AI에서 테스트됨").padding(.top, 6)
            ArisFlow(spacing: 6) {
                ForEach(allBrains, id: \.self) { brain in
                    let tried = row.tested.first { $0.brain == brain }
                    if tried?.ok == true {
                        ArisChip(text: "✓ " + w(ArisSkillWords.brainName(brain)), tone: .ok)
                    } else {
                        ArisChip(text: "아직 · " + ArisSkillWords.brainName(brain))
                    }
                }
            }
            Text(w(testedLine)).font(.system(size: 12)).foregroundStyle(palette.desc).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            label("파일").padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(Array(row.files.prefix(20).enumerated()), id: \.offset) { index, file in
                    ArisSkillFileLine(file: file, findings: row.findings, checked: row.checked)
                    if index < min(row.files.count, 20) - 1 { Rectangle().fill(palette.hairline).frame(height: 1) }
                }
            }
            ArisFlow(spacing: 8) {
                ArisSettingsButton(title: "말로 고치기", kind: .primary) { model.speakFix(row) }
                ArisSettingsButton(title: "SKILL.md 직접 고치기") { model.edit(row.name) }
                ArisSettingsButton(title: "모든 AI로 시험") { model.tryAll(row.name) }
                ArisSettingsButton(title: "삭제", kind: .danger) { model.remove(row.name) }
            }
            .padding(.top, 8)
        }
    }

    private var allBrains: [String] {
        let known = ["claude", "codex", "antigravity", "api"]
        return known.filter { brain in brains.contains(brain) || row.tested.contains { $0.brain == brain } }
    }

    private var testedLine: String {
        let passed = row.tested.filter(\.ok).count
        let total = max(allBrains.count, 1)
        if passed >= total { return "연결한 AI \(total)개 모두에서 시험했어요." }
        return "연결한 AI \(total)개 중 \(passed)개에서 시험했어요. 스킬은 모든 AI에서 돌아가야 해서, 나머지도 시험해 보는 걸 권해요. AI는 AI 서비스에서 더 연결할 수 있어요."
    }

    private var findings: some View {
        ArisSkillInset(tone: row.phase == "blocked" ? .bad : .warn) {
            Text(w(row.phase == "blocked" ? "위험해서 쓰지 않아요" : "확인할 게 \(row.findings.count)개 있어요")).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.title)
            ForEach(row.findings, id: \.self) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(w(item.text)).font(.system(size: 12.5)).foregroundStyle(palette.title)
                    Text(w(item.file)).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.desc)
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(w(text)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(palette.desc)
    }
}
