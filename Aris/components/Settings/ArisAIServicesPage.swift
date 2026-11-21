//
//  ArisAIServicesPage.swift
//  Aris
//
//  The AI parts of Aris와 말하기 (settings-ia option A). AI · 모델: the 답하는 AI card (mockup ai-services-D's 생각 card),
//  its login line, the slots for the model per role and 다른 AI로 넘기기 (other branches' rows: ArisSettingsViewSlots),
//  짧은 명령, then 연결된 서비스 folded. 듣기 and 목소리: the hearing and speaking cards, each with the page's own rows
//  in the same card under a hairline. Sections sit 32 apart, cards 16, rows 20 inside.
//  It draws ArisAIPage; nothing here knows where a choice is kept.
//

import SwiftUI

/// AI · 모델's body under its title.
struct ArisAIThinkPart: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsFlash) private var flash
    @Environment(\.arisSettingsFolds) private var folds
    @ObservedObject var model: ArisAIServicesModel
    /// The part's sections as the builder lists them (ArisSettingsBuilder.services).
    let sections: [ArisSettingSection]
    /// Other branches' views, drawn in their places when they are in (ArisSettingsViewSlots).
    var models: AnyView?

    static let servicesSection = "ai.services"

    var body: some View {
        let page = model.page
        VStack(alignment: .leading, spacing: 0) {
            ArisAICardView(card: page.think, model: model).id("ai.brain").arisFlash("ai.brain")
            if let line = page.thinkLine { ArisAIQuietLine(text: line) }
            if let login = page.login {
                ArisAILoginRow(line: login, model: model).id("ai.brainLogin").arisFlash("ai.brainLogin", radius: 10).padding(.top, 12).padding(.horizontal, 4)
            }
            // jv-models: 역할별 모델 (ArisModelChoiceSection), 16 under the card.
            if let models { models.id(ArisSettingsViewSlots.models).arisFlash(ArisSettingsViewSlots.models).padding(.top, ArisSettingsMetrics.sectionGap) }
            // 안 될 때 › 다른 AI로 넘기기 (ArisSettingsSlots.fallback): the builder's own row, drawn as any page draws it.
            if let fallback = sections.first(where: { $0.id == ArisSettingsViewSlots.fallback }) {
                ArisSettingsPageView(sections: [fallback]).padding(.top, ArisSettingsMetrics.sectionGap)
            }
            ArisSectionTitle(text: w("빠른 명령")).padding(.top, ArisSettingsMetrics.sectionGap)
            ArisAIJevRow(line: page.jev, router: page.router, model: model).id("ai.jev").arisFlash("ai.jev", radius: 18).padding(.top, 12)
            services.padding(.top, ArisSettingsMetrics.sectionGap)
        }
        .onAppear { unfold(flash) }
        .onChange(of: flash) { _, target in unfold(target) }
    }

    /// 연결된 서비스: one line; pressed, it unfolds the AIs' logins and usage and Claude Code's budget. Open or closed is
    /// remembered with the window's other folds.
    @ViewBuilder
    private var services: some View {
        let open = folds.open.contains(Self.servicesSection)
        let section = sections.first { $0.id == Self.servicesSection }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ArisFoldRow(symbol: section?.fold?.symbol ?? "powerplug", title: section?.fold?.title ?? "연결된 서비스",
                            desc: section?.fold?.desc ?? "", open: open) { folds.set(Self.servicesSection, open: !open) }
                if open, let section {
                    Rectangle().fill(palette.hairline).frame(height: 1)
                    ArisAIFoldedRows(rows: ArisAIServicesBuilder.serviceRows(section.rows, read: model.state.servicesRead).map(w.row))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .arisCard()
            .id(Self.servicesSection)
            .arisFlash(Self.servicesSection)
            if let note = section?.note { ArisFineLine(text: w(note)).padding(.top, ArisSettingsMetrics.fineGap) }
        }
    }

    /// A search that lands on a folded row opens the fold first.
    private func unfold(_ target: ArisSettingsFlashTarget?) {
        guard let id = target?.id, id.hasPrefix("ai.service") || id == "aris.claudeBudget" else { return }
        folds.set(Self.servicesSection, open: true)
    }
}

/// 듣기 or 목소리: the job's card with the page's own rows (쓰는 언어, 말하기 속도) in it under a hairline, then its small
/// lines (the hearing engine as plain status, the part's note).
struct ArisAIJobPart: View {
    let card: ArisAICard
    @ObservedObject var model: ArisAIServicesModel
    /// The card's own tag ("ai.hear", "ai.speak").
    let tag: String
    let rows: [ArisSettingItem]
    var lines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArisAICardView(card: card, model: model, extra: rows).id(tag).arisFlash(tag)
            ForEach(lines, id: \.self) { ArisAIQuietLine(text: $0) }
        }
    }
}

/// A small line under a card ("안 되면 …", the hearing engine): 12 pt, the faintest ink, 8 above, 4 in.
struct ArisAIQuietLine: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let text: String

    var body: some View {
        Text(ArisKoreanText.keepAll(w.dotted(text))).font(.system(size: 12)).foregroundStyle(palette.ink3).fixedSize(horizontal: false, vertical: true)
            .padding(.top, ArisSettingsMetrics.fineGap).padding(.horizontal, ArisSettingsMetrics.fineInset)
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
    /// The page's own rows drawn in the same card after the job's (쓰는 언어 under 듣기, 말하기 속도 under 목소리).
    var extra: [ArisSettingItem] = []

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
            ForEach(extra) { row in
                ArisInsetHairline()
                ArisSettingRowView(item: row).padding(ArisSettingsMetrics.rowInset).frame(minHeight: ArisSettingsMetrics.rowMinHeight)
                    .id(row.id).arisFlash(row.id, radius: 0)
            }
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
            // Nothing to choose here: said as plain status (#19), not dressed as a value that could be changed.
            ArisSaid(text: w.dotted(name))
        case .field(let field, let text, let placeholder):
            ArisAICommitField(field: field, stored: text, placeholder: placeholder, model: model)
        }
    }
}

/// A typed model name: saved on return, or when the field is left.
struct ArisAICommitField: View {
    @Environment(\.arisWords) private var w
    let field: ArisAIField
    let stored: String
    let placeholder: String
    var label = "모델 이름"
    var width: CGFloat = 200
    @ObservedObject var model: ArisAIServicesModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ArisAITextField(placeholder: placeholder, text: $text, mono: true, width: width) { commit() }
            .focused($focused)
            .onAppear { text = stored }
            .onChange(of: stored) { _, next in if !focused { text = next } }
            .onChange(of: focused) { _, now in if !now { commit() } }
            .accessibilityLabel(w(label))
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

/// 짧은 명령 빨리 알아듣기: a card of its own under the 생각 card (VM run 2026-11-18). Its dropdown picks who understands
/// the quick commands (자동, Jev, a connected API profile), the line under it says what that costs and what it sees,
/// and TypeSafe's key keeps its own line while Jev may be the one.
struct ArisAIJevRow: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let line: ArisAIJevLine
    let router: ArisAIRouterLine
    @ObservedObject var model: ArisAIServicesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                title("짧은 명령 빨리 알아듣기").frame(maxWidth: .infinity, alignment: .leading)
                ArisAISelect(face: router.face, label: "짧은 명령 빨리 알아듣기", expanded: model.menu?.kind == .router) { model.toggle(.router, anchor: $0) }
            }
            .frame(minHeight: 32)
            Text(w.dotted(router.line)).font(.system(size: 12)).foregroundStyle(palette.desc).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if router.jevKey { key }
            if let decision = router.decision { ArisAIDecisionRows(line: decision, model: model) }
            if case .editing(let error?) = line {
                Text(w(error)).font(.system(size: 12)).foregroundStyle(palette.red)
            }
        }
        .padding(ArisSettingsMetrics.rowInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .arisCard()
    }

    /// TypeSafe's key: add it, see it masked and take it out, or type it.
    private var key: some View {
        HStack(spacing: 8) {
            switch line {
            case .off:
                title("TypeSafe 키")
                Text(w.dotted("짧은 말을 AI보다 먼저 알아듣는 작은 모델(TypeSafe) · 없어도 돼요")).lineLimit(1).font(.system(size: 12)).foregroundStyle(palette.desc).frame(maxWidth: .infinity, alignment: .leading)
                ArisSettingsButton(title: "API 키 추가", small: true) { model.perform(.openJev) }
            case .on(let masked):
                title("TypeSafe 키")
                (Text(w("TypeSafe · 켜짐 · ")).font(.system(size: 12)) + Text(masked).font(.system(size: 12, design: .monospaced)))
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
            ForEach(Array(model.keyRows.rows(saved: keys).enumerated()), id: \.element.key.holder) { index, row in
                let key = row.key
                if index > 0 { ArisInsetHairline() }
                HStack(spacing: 12) {
                    ArisLineIcon("key", size: 20).foregroundStyle(palette.icon).frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w("\(key.name) API 키")).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.title)
                        switch row.mode {
                        case .saved:
                            (Text(w("키체인에 저장됨")).font(.system(size: 12)) + Text(key.masked.map { " · " + $0 } ?? "").font(.system(size: 12, design: .monospaced)))
                                .foregroundStyle(palette.desc)
                        case .confirming:
                            Text(w(ArisSavedKeyRows.ask)).font(.system(size: 12)).foregroundStyle(palette.desc)
                        case .cleared:
                            Text(w(ArisSavedKeyRows.cleared)).font(.system(size: 12)).foregroundStyle(palette.desc)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    switch row.mode {
                    case .saved:
                        // A first press only asks; nothing is cleared yet.
                        ArisSettingsButton(title: "지우기", kind: .danger, small: true) { model.keyRows.ask(key.holder) }
                    case .confirming:
                        // 취소 sits where 지우기 was: a second press at the same place takes the ask back.
                        ArisSettingsButton(title: "정말 지우기", kind: .danger, small: true) {
                            if model.keyRows.confirm(key.holder) { model.perform(.removeKey(key.holder)) }
                        }
                        ArisSettingsButton(title: "취소", small: true) { model.keyRows.cancel() }
                    case .cleared:
                        // The row keeps its height and its place, with nothing to press.
                        ArisSettingsButton(title: "지우기", kind: .danger, small: true) {}.hidden().allowsHitTesting(false)
                    }
                }
                .padding(ArisSettingsMetrics.rowInset)
            }
        }
        .onAppear { model.keyRows.sync(keys) }
        .onChange(of: keys) { _, now in model.keyRows.sync(now) }
        .onDisappear { model.keyRows.reset() }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .arisCard()
    }
}
