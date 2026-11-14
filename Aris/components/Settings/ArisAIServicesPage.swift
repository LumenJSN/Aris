//
//  ArisAIServicesPage.swift
//  Aris
//
//  설정 › AI 서비스 as the owner picked it (mockup ai-services-D, without its summary sentence): 생각, then 음성 with 듣기 and
//  말하기, each a card whose first row names who does the job and changes it from a dropdown; under it the model, the
//  voice, and a row that appears only when something is missing or coming in. Sections sit 32 apart, cards 16, rows 20
//  inside. Below them: 연결된 서비스 (folded, as the mockup's row), and the
//  settings this page had that the mockup has no place for. It draws ArisAIPage; nothing here knows where a choice is kept.
//

import SwiftUI

struct ArisAIServicesPage: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsFlash) private var flash
    @ObservedObject var model: ArisAIServicesModel
    /// The page's rows as the builder lists them (ArisSettingsBuilder.services): the ones this view doesn't draw itself
    /// (연결된 서비스, 다른 앱을 다루는 방식, 팀원의 두뇌) are drawn as every other page draws them.
    let sections: [ArisSettingSection]

    /// The tags this view draws itself (ArisSettingsIndex finds them; a search scrolls to them).
    static let ownSections: Set<String> = ["ai.think", "ai.voice", "ai.keys"]
    static let servicesSection = "ai.services"

    var body: some View {
        let page = model.page
        VStack(alignment: .leading, spacing: 0) {
            heading("생각").id("ai.think")
            ArisAICardView(card: page.think, model: model).id("ai.brain").arisFlash("ai.brain").padding(.top, ArisSettingsMetrics.headingGap).modifier(ArisRise(index: 2))
            if let line = page.thinkLine { quiet(line) }
            if let login = page.login {
                ArisAILoginRow(line: login, model: model).id("ai.brainLogin").arisFlash("ai.brainLogin", radius: 10).padding(.top, 12).padding(.horizontal, 4)
            }
            ArisAIJevRow(line: page.jev, model: model).id("ai.jev").arisFlash("ai.jev", radius: 10).padding(.top, 12).padding(.horizontal, 4)

            HStack(alignment: .center, spacing: 8) {
                heading("음성")
                Text(w("듣기와 말하기는 따로 골라요")).font(.system(size: 12)).foregroundStyle(palette.desc)
                Spacer(minLength: 8)
                ArisAIIconButton(title: "같은 회사로 맞추기", trailing: "chevron.down", small: true) { model.toggle(.both, anchor: $0) }
            }
            .padding(.top, 32).id("ai.voice")
            ArisAICardView(card: page.hear, model: model).id("ai.hear").arisFlash("ai.hear").padding(.top, ArisSettingsMetrics.headingGap).modifier(ArisRise(index: 3))
            ArisAICardView(card: page.speak, model: model).id("ai.speak").arisFlash("ai.speak").padding(.top, 16).modifier(ArisRise(index: 4))
            if let line = page.voiceLine { quiet(line) }

            services.padding(.top, 32).modifier(ArisRise(index: 5))
            let rest = sections.filter { !Self.ownSections.contains($0.id) && $0.id != Self.servicesSection }
            if !rest.isEmpty { ArisSettingsPageView(sections: rest).padding(.top, 16) }
            if !page.savedKeys.isEmpty { ArisAISavedKeys(keys: page.savedKeys, model: model).id("ai.savedKeys").padding(.top, 16) }
        }
        .onAppear { unfold(flash) }
        .onChange(of: flash) { _, target in unfold(target) }
    }

    private func heading(_ text: String) -> some View {
        ArisSectionTitle(text: w(text))
    }

    /// A small line under a card ("안 되면 …"): 12 pt, the faintest ink, 8 above, 4 in.
    private func quiet(_ text: String) -> some View {
        Text(w.dotted(text)).font(.system(size: 12)).foregroundStyle(palette.ink3).padding(.top, 8).padding(.horizontal, 4)
    }

    /// 연결된 서비스: the mockup's one row; pressed, it unfolds the logins, Composio and the MCP servers under it.
    @ViewBuilder
    private var services: some View {
        let open = model.state.ui.servicesOpen
        let section = sections.first { $0.id == Self.servicesSection }
        VStack(alignment: .leading, spacing: 0) {
            ArisFoldRow(symbol: "powerplug", title: "연결된 서비스", desc: "Composio · 내 MCP 서버", open: open) { model.perform(.toggleServices) }
            if open, let section {
                Rectangle().fill(palette.hairline).frame(height: 1)
                if let note = section.note {
                    Text(ArisKoreanText.keepAll(w(note))).font(.system(size: 12)).foregroundStyle(palette.desc).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, ArisSettingsMetrics.rowInset).padding(.vertical, 14)
                    Rectangle().fill(palette.hairline).frame(height: 1)
                }
                ArisAIFoldedRows(rows: ArisAIServicesBuilder.serviceRows(section.rows, read: model.state.servicesRead).map(w.row))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .arisCard()
        .id(Self.servicesSection)
        .arisFlash(Self.servicesSection)
    }

    /// A search that lands on a folded row opens the fold first.
    private func unfold(_ target: ArisSettingsFlashTarget?) {
        guard let id = target?.id, !model.state.ui.servicesOpen, id.hasPrefix("ai.mcp") || id.hasPrefix("ai.service") else { return }
        model.perform(.toggleServices)
    }
}

/// The folded section's rows, hairlines between, each drawn as a grouped card draws it.
private struct ArisAIFoldedRows: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsHandlers) private var handlers
    let rows: [ArisSettingItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { ArisInsetHairline() }
                Group {
                    if case .custom = row.control, let custom = handlers.custom(row) {
                        custom
                    } else {
                        ArisSettingRowView(item: row).padding(ArisSettingsMetrics.rowInset)
                    }
                }
                .id(row.id)
                .arisFlash(row.id, radius: 0)
            }
        }
    }
}

// MARK: - A job's card

struct ArisAICardView: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let card: ArisAICard
    @ObservedObject var model: ArisAIServicesModel

    var body: some View {
        // The row about what's missing sits under the model and above the voice.
        let voiceAt = card.rows.firstIndex { $0.preview != nil } ?? card.rows.count
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(card.rows.enumerated()), id: \.offset) { index, row in
                if index == voiceAt, let need = card.need { ArisAINeedRow(need: need, model: model) }
                if index > 0 { ArisInsetHairline() }
                ArisAIRowView(row: row, job: card.job, model: model)
            }
            if voiceAt == card.rows.count, let need = card.need { ArisAINeedRow(need: need, model: model) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .arisCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(w(card.job.title))
    }
}

/// One row: the icon column (20), the title with its line, the control at the end.
struct ArisAIRowView: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let row: ArisAIRow
    let job: ArisAIJob
    @ObservedObject var model: ArisAIServicesModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let icon = row.icon { ArisLineIcon(icon, size: 20).foregroundStyle(palette.icon) } else { Color.clear }
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(w(row.title)).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.title)
                if !row.desc.isEmpty || row.warn != nil { description }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                control
                if let preview = row.preview {
                    let playing = model.state.ui.playing == ""
                    ArisAIIconButton(title: playing ? "그만" : "미리 듣기", leading: playing ? "stop.circle" : "play.circle", enabled: preview) { _ in model.perform(.preview) }
                        .accessibilityLabel(w(playing ? "그만 듣기" : "목소리 미리 듣기"))
                }
            }
        }
        .padding(ArisSettingsMetrics.rowInset)
    }

    /// "Claude · 대화가 Mac 밖으로 나가요", or the name and what it is missing in the warn colour.
    private var description: some View {
        var text = Text(w.dotted(row.desc)).foregroundColor(palette.desc)
        if let warn = row.warn {
            text = text + Text(row.desc.isEmpty ? "" : " · ").foregroundColor(palette.desc) + Text(w(warn)).foregroundColor(palette.warn)
        }
        return text.font(.system(size: 12)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var control: some View {
        switch row.control {
        case .select(let kind, let face):
            ArisAISelect(face: face, label: row.title, expanded: model.menu?.kind == kind) { model.toggle(kind, anchor: $0) }
        case .fixed(let name):
            Text(w.dotted(name)).font(.system(size: 14)).foregroundStyle(palette.desc)
        case .field(let field, let text, let placeholder):
            ArisAICommitField(field: field, stored: text, placeholder: placeholder, model: model)
        }
    }
}

/// A typed model name: saved on return, or when the field is left.
private struct ArisAICommitField: View {
    @Environment(\.arisWords) private var w
    let field: ArisAIField
    let stored: String
    let placeholder: String
    @ObservedObject var model: ArisAIServicesModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ArisAITextField(placeholder: placeholder, text: $text, mono: true, width: 200) { commit() }
            .focused($focused)
            .onAppear { text = stored }
            .onChange(of: stored) { _, next in if !focused { text = next } }
            .onChange(of: focused) { _, now in if !now { commit() } }
            .accessibilityLabel(w("모델 이름"))
    }

    private func commit() {
        let typed = text.trimmingCharacters(in: .whitespaces)
        if typed != stored { model.perform(.commit(field, typed)) }
    }
}

// MARK: - What's missing, or coming in

/// The row under a card's rows (mockup `.need`: no line above, 52 in from the left, 20 below): a message and its
/// button, a key field, the question before a download, or its bar.
struct ArisAINeedRow: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let need: ArisAINeed
    @ObservedObject var model: ArisAIServicesModel

    var body: some View {
        Group {
            switch need {
            case .button(let message, let title, let action):
                line(message) { ArisSettingsButton(title: title, small: true) { model.perform(action) } }
            case .keyField(let holder, let placeholder, let hint, let error):
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ArisAITextField(placeholder: placeholder, text: model.draft("key:" + holder), secure: true, autofocus: true) { save(holder) }
                        ArisSettingsButton(title: "저장", kind: .primary, small: true) { save(holder) }
                        ArisSettingsButton(title: "취소", small: true) { model.perform(.cancelKey(holder)) }
                    }
                    Text(w.dotted(error ?? hint)).font(.system(size: 12)).foregroundStyle(error == nil ? palette.ink3 : palette.red).fixedSize(horizontal: false, vertical: true)
                }
            case .ask(let message, let asked):
                line(message) {
                    ArisSettingsButton(title: "받기", kind: .primary, small: true) { model.perform(.download(asked)) }
                    ArisSettingsButton(title: "취소", small: true) { model.perform(.cancelAsk) }
                }
            case .progress(let label, let percent):
                line(label) {
                    ArisAIProgress(percent: percent)
                    ArisSettingsButton(title: "취소", small: true) { model.perform(.cancelDownload) }
                }
            case .failed(let message):
                line(message) {
                    ArisSettingsButton(title: "다시 받기", small: true) { model.perform(.retryDownload) }
                    ArisSettingsButton(title: "취소", small: true) { model.perform(.cancelDownload) }
                }
            case .message(let message):
                line(message) { EmptyView() }
            case .checked(let message, let note):
                // Where 다시 확인 was, as tall as the button: plain text for a few seconds, no dot and nothing that blinks.
                line(message) { Text(w(note)).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.desc).fixedSize().frame(height: 26) }
            }
        }
        .padding(.leading, 52).padding(.trailing, 20).padding(.bottom, 20)
    }

    private func line<Trailing: View>(_ message: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Text(w.dotted(message)).font(.system(size: 13)).foregroundStyle(palette.title).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }

    private func save(_ holder: String) {
        model.perform(.saveKey(holder: holder, key: model.drafts["key:" + holder] ?? ""))
    }
}

/// The answering subscription's own sign-in, one line under the 생각 card in the Jev line's shape: aris-agent can't
/// see a sign-out, so the way back in is always at hand.
struct ArisAILoginRow: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let line: ArisAILoginLine
    @ObservedObject var model: ArisAIServicesModel

    var body: some View {
        HStack(spacing: 8) {
            Text(w(line.title)).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.title).fixedSize()
            Text(w(line.desc)).font(.system(size: 12)).foregroundStyle(palette.desc).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            ArisSettingsButton(title: "로그인", small: true) { model.perform(.signIn(line.brain)) }
        }
        .frame(minHeight: 32)
    }
}

/// 짧은 명령 빨리 알아듣기 (TypeSafe Jev): one line under the 생각 card, at least 32 tall.
struct ArisAIJevRow: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let line: ArisAIJevLine
    @ObservedObject var model: ArisAIServicesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                switch line {
                case .off:
                    title("짧은 명령 빨리 알아듣기")
                    Text(w("짧은 말을 AI보다 먼저 알아듣는 작은 모델(TypeSafe Jev) · 없어도 돼요")).font(.system(size: 12)).foregroundStyle(palette.desc).frame(maxWidth: .infinity, alignment: .leading)
                    ArisSettingsButton(title: "API 키 추가", small: true) { model.perform(.openJev) }
                case .on(let masked):
                    title("짧은 명령 빨리 알아듣기")
                    (Text(w("TypeSafe Jev · 켜짐 · ")).font(.system(size: 12)) + Text(masked).font(.system(size: 12, design: .monospaced)))
                        .foregroundStyle(palette.desc).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    ArisSettingsButton(title: "지우기", small: true) { model.perform(.clearJev) }
                case .editing:
                    title("TypeSafe API 키").padding(.trailing, 4)
                    ArisAITextField(placeholder: "TypeSafe API 키", text: model.draft("jev"), secure: true, autofocus: true) { save() }
                    ArisSettingsButton(title: "저장", kind: .primary, small: true) { save() }
                    ArisSettingsButton(title: "취소", small: true) { model.perform(.cancelJev) }
                }
            }
            .frame(minHeight: 32)
            if case .editing(let error?) = line {
                Text(w(error)).font(.system(size: 12)).foregroundStyle(palette.red)
            }
        }
    }

    private func title(_ text: String) -> some View {
        Text(w(text)).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.title).fixedSize()
    }

    private func save() { model.perform(.saveJev(model.drafts["jev"] ?? "")) }
}

/// The keys that are saved, each with 지우기: the mockup adds keys where they are needed and shows no way to take one
/// out again, so they are listed here.
struct ArisAISavedKeys: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let keys: [ArisAISavedKey]
    @ObservedObject var model: ArisAIServicesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(keys.enumerated()), id: \.element.holder) { index, key in
                if index > 0 { ArisInsetHairline() }
                HStack(spacing: 12) {
                    ArisLineIcon("key", size: 20).foregroundStyle(palette.icon).frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w("\(key.name) API 키")).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.title)
                        (Text(w("키체인에 저장됨")).font(.system(size: 12)) + Text(key.masked.map { " · " + $0 } ?? "").font(.system(size: 12, design: .monospaced)))
                            .foregroundStyle(palette.desc)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ArisSettingsButton(title: "지우기", kind: .danger, small: true) { model.perform(.removeKey(key.holder)) }
                }
                .padding(ArisSettingsMetrics.rowInset)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .arisCard()
    }
}
