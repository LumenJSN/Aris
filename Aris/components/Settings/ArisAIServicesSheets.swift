//
//  ArisAIServicesSheets.swift
//  Aris
//
//  AI 서비스's sheets (mockup ai-services-D-connect: 460 wide, r20,
//  the backdrop at .38 / .78, in from 0.96 and 10 pt lower over 300 ms; header 16 × 24 with a 12.5/500 line under the
//  title, body 24 with 16 between, fields 36 tall): 다른 AI 연결…, ElevenLabs 라이브러리 and 링크로 추가…. They draw
//  ArisAISheet and send what is pressed back; the page's dropdown host draws their dropdowns too.
//

import SwiftUI

/// The sheet and the dropdown over the whole settings window.
struct ArisAIServicesOverlay: View {
    @ObservedObject var model: ArisAIServicesModel

    var body: some View {
        ZStack {
            ArisAISheetHost(model: model)
            ArisAIMenuHost(model: model)
        }
    }
}

struct ArisAISheetHost: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsStill) private var still
    @ObservedObject var model: ArisAIServicesModel

    var body: some View {
        ZStack {
            if let sheet = model.sheet {
                palette.backdrop.ignoresSafeArea().onTapGesture { model.performSheet(.close) }.transition(.opacity)
                ArisAISheetView(sheet: sheet, model: model)
                    .frame(width: 460)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.modal))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.modalBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .compositingGroup()
                    .shadow(color: .black.opacity(palette.dark ? 0.82 : 0.25), radius: palette.dark ? 32 : 25, y: palette.dark ? 24 : 25)
                    .transition(.scale(scale: 0.96).combined(with: .offset(y: 10)).combined(with: .opacity))
                    .onExitCommand { if model.menu == nil { model.performSheet(.close) } else { model.menu = nil } }
            }
        }
        .animation(still || ArisSettingsMotion.reduced ? nil : .easeOut(duration: 0.3), value: model.sheet != nil)
    }
}

/// One sheet: its header, body and foot.
struct ArisAISheetView: View {
    @Environment(\.arisPalette) private var palette
    let sheet: ArisAISheet
    @ObservedObject var model: ArisAIServicesModel

    var body: some View {
        switch sheet {
        case .connect(let draft):
            ArisAIConnectSheet(draft: draft, view: ArisAIConnect.view(draft, in: model.state), model: model)
        case .library(let library):
            ArisAILibrarySheet(library: library, model: model)
        case .link(let link):
            ArisAILinkSheet(link: link, model: model)
        }
    }
}

/// The sheet's frame: the title with its small line and ✕, a hairline, the body, the buttons.
private struct ArisAISheetFrame<Body: View, Foot: View>: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let title: String
    let meta: String
    let close: () -> Void
    /// False for a sheet with no buttons under its body (the library).
    var hasFoot = true
    @ViewBuilder let content: () -> Body
    @ViewBuilder let foot: () -> Foot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(w(title)).font(.system(size: 16, weight: .semibold)).foregroundStyle(palette.title).accessibilityAddTraits(.isHeader)
                    Text(w.dotted(meta)).font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.dark ? Color(.sRGB, red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: 0.6) : Color(.sRGB, red: 60 / 255, green: 60 / 255, blue: 67 / 255, opacity: 0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: close) {
                    ArisLineIcon("xmark", size: 13, stroke: 2.25).foregroundStyle(palette.ink3).frame(width: 28, height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(ArisPressScale())
                .accessibilityLabel(w("닫기"))
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            Rectangle().fill(palette.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 16) { content() }.padding(24)
            if hasFoot {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    foot()
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }
}

/// A labelled part of a sheet's body: the label (12/500), the control, then a hint or what is wrong.
private struct ArisAILabelled<Control: View>: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let label: String
    var note: String?
    var tone = ArisAIConnect.Tone.plain
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(w(label)).font(.system(size: 12, weight: .medium)).foregroundStyle(palette.desc)
            control()
            if let note {
                Text(w.dotted(note)).font(.system(size: 12)).foregroundStyle(tone == .bad ? palette.red : tone == .ok ? palette.ok : palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 다른 AI 연결…

private struct ArisAIConnectSheet: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let draft: ArisAIConnectDraft
    let view: ArisAIConnect.View
    @ObservedObject var model: ArisAIServicesModel

    /// A field of the draft; a changed address forgets the models it listed.
    private func binding(_ path: WritableKeyPath<ArisAIConnectDraft, String>, error: String) -> Binding<String> {
        Binding(get: { draft[keyPath: path] }, set: { value in
            guard case .connect(var next)? = model.sheet else { return }
            next[keyPath: path] = value
            next.errors[error] = nil
            if path == \ArisAIConnectDraft.base, next.load != .idle {
                next.load = .idle
                next.models = []
            }
            model.sheet = .connect(next)
        })
    }

    private func binding(_ id: String) -> Binding<String> {
        switch id {
        case "name": binding(\.name, error: "name")
        case "base": binding(\.base, error: "base")
        case "key": binding(\.key, error: "key")
        default: binding(\.model, error: "model")
        }
    }

    var body: some View {
        ArisAISheetFrame(title: view.title, meta: view.meta, close: { model.performSheet(.close) }) {
            if !view.quick.isEmpty {
                ArisFlow(spacing: 8) {
                    ForEach(view.quick, id: \.id) { pick in
                        ArisAIQuickChip(title: pick.name, picked: pick.picked) { model.performSheet(.quick(pick.id)) }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(w("바로 고르기"))
            }
            switch view.body {
            case .shipped(let note, let key, let saved):
                Text(w.dotted(note)).font(.system(size: 13)).foregroundStyle(palette.title).fixedSize(horizontal: false, vertical: true)
                if let key {
                    ArisAILabelled(label: key.label, note: key.error, tone: .bad) {
                        ArisAITextField(placeholder: key.placeholder, text: binding("key"), secure: true, autofocus: true) { model.performSheet(.useShipped) }
                    }
                } else if saved {
                    Text(w("저장된 API 키를 그대로 써요")).font(.system(size: 12)).foregroundStyle(palette.ink3)
                }
            case .custom(let fields, let control, let hint, let tone):
                ForEach(fields, id: \.id) { field in
                    ArisAILabelled(label: field.label, note: field.error, tone: .bad) {
                        ArisAITextField(placeholder: field.placeholder, text: binding(field.id), secure: field.secure, mono: field.mono, autofocus: field.id == "base" && draft.base.isEmpty) {
                            if field.id != "name" { model.performSheet(.loadModels) }
                        }
                    }
                }
                ArisAILabelled(label: "모델", note: hint, tone: tone) {
                    HStack(spacing: 8) {
                        switch control {
                        case .select(let chosen):
                            ArisAISelect(face: ArisAISelectFace(label: chosen), label: "모델", width: nil, expanded: model.menu?.kind == .sheet("model")) { frame in
                                model.toggle(.sheet("model"), anchor: frame, custom: ArisAIMenu(search: draft.models.count > 10 ? "모델 찾기" : nil, entries: draft.models.map {
                                    .item(ArisAIMenuItem(id: $0, title: $0, checked: $0 == chosen))
                                }))
                            }
                            .frame(maxWidth: .infinity)
                        case .field:
                            ArisAITextField(placeholder: "모델 이름", text: binding("model"), mono: true) { model.performSheet(.save(force: true)) }
                        case .waiting(let text):
                            ArisAISelect(face: ArisAISelectFace(label: text, enabled: false), label: "모델", width: nil) { _ in }.frame(maxWidth: .infinity)
                        }
                        ArisSettingsButton(title: "불러오기", enabled: draft.load != .loading) { model.performSheet(.loadModels) }
                    }
                }
            }
            if let error = view.error {
                Text(w(error)).font(.system(size: 12)).foregroundStyle(palette.red).fixedSize(horizontal: false, vertical: true)
            }
        } foot: {
            ArisSettingsButton(title: "취소") { model.performSheet(.close) }
            if view.force { ArisSettingsButton(title: "그래도 저장", enabled: !draft.busy) { model.performSheet(.save(force: true)) } }
            ArisSettingsButton(title: view.primary, kind: .primary, enabled: view.primaryEnabled) {
                if case .shipped = view.body { model.performSheet(.useShipped) } else { model.performSheet(.save(force: false)) }
            }
        }
    }
}

/// A quick pick (`.btn.sm`): its line and ink darken while it is the one picked.
private struct ArisAIQuickChip: View {
    @Environment(\.arisPalette) private var palette
    let title: String
    let picked: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(picked ? palette.title : hovering ? palette.buttonTextHover : palette.buttonText)
                .padding(.horizontal, 10).frame(height: 26)
                .background(shape.fill(palette.buttonFill))
                .overlay(shape.strokeBorder(picked ? palette.fieldFocus : hovering ? palette.buttonBorderHover : palette.buttonBorder, lineWidth: 1))
                .contentShape(shape)
                .animation(.easeInOut(duration: 0.2), value: hovering)
        }
        .buttonStyle(ArisPressScale())
        .onHover { hovering = $0 }
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

// MARK: - ElevenLabs 라이브러리

private struct ArisAILibrarySheet: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsStill) private var still
    let library: ArisAILibraryState
    @ObservedObject var model: ArisAIServicesModel

    private var search: Binding<String> {
        Binding(get: { library.query.search }, set: { value in
            guard case .library(var next)? = model.sheet else { return }
            next.query.search = value
            model.sheet = .library(next)
        })
    }

    var body: some View {
        ArisAISheetFrame(title: "ElevenLabs 라이브러리", meta: "공유된 목소리 · 추가하면 내 목소리에 들어가요", close: { model.performSheet(.close) }, hasFoot: false) {
            ArisAITextField(placeholder: "이름이나 느낌으로 찾기", text: search, leading: 32, autofocus: true) { model.performSheet(.searchLibrary) }
                .overlay(alignment: .leading) {
                    ArisLineIcon("magnifyingglass", size: 14).foregroundStyle(palette.ink3).padding(.leading, 11).allowsHitTesting(false)
                }
                .onChange(of: library.query.search) { _, _ in model.performSheet(.searchLibrary) }
            HStack(spacing: 8) {
                ForEach(["language", "gender", "use"], id: \.self) { filter in
                    let options = ArisAILibraryQuery.options(filter), value = library.query.value(filter)
                    ArisAISelect(face: ArisAISelectFace(label: options.first { $0.id == value }?.title ?? options[0].title), label: options[0].title, width: nil, height: 36,
                                 fontSize: 13, expanded: model.menu?.kind == .sheet(filter)) { frame in
                        model.toggle(.sheet(filter), anchor: frame, custom: ArisAIMenu(entries: options.map {
                            .item(ArisAIMenuItem(id: $0.id, title: $0.title, checked: $0.id == value))
                        }))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            rows
            Text(w("ElevenLabs에서 불러옴")).font(.system(size: 11)).foregroundStyle(palette.ink3)
        } foot: {
            EmptyView()
        }
    }

    @ViewBuilder
    private var rows: some View {
        if let voices = library.voices, !voices.isEmpty {
            let list = VStack(alignment: .leading, spacing: 0) {
                ForEach(voices) { voice in
                    ArisAILibraryRow(voice: voice, added: ArisAIConnect.isAdded(voice, in: library, account: model.state.voices["eleven"]?.voices ?? []),
                                     adding: library.adding == voice.id, playing: model.state.ui.playing == voice.id, model: model)
                }
            }
            if still { list.frame(maxHeight: 240, alignment: .top).clipped() } else { ScrollView { list }.scrollIndicators(.never).frame(height: min(240, CGFloat(voices.count) * 50)) }
        } else {
            Text(w(library.failed ? "라이브러리를 못 불러왔어요" : library.voices == nil ? "목소리를 불러오는 중…" : "찾는 목소리가 없어요"))
                .font(.system(size: 12)).foregroundStyle(palette.ink3).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        }
    }
}

private struct ArisAILibraryRow: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let voice: ArisAILibraryVoice
    let added: Bool
    let adding: Bool
    let playing: Bool
    @ObservedObject var model: ArisAIServicesModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.title).lineLimit(1)
                Text(voice.desc).font(.system(size: 11)).foregroundStyle(palette.desc).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ArisAISampleButton(playing: playing, name: voice.name, enabled: voice.preview != nil) { model.perform(.sample(id: voice.id, url: voice.preview)) }
            if added {
                Text(w("추가됨")).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.ink3).padding(.horizontal, 8)
            } else {
                ArisSettingsButton(title: adding ? "추가 중…" : "추가", small: true, enabled: !adding) { model.performSheet(.addFromLibrary(voice.id)) }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? palette.rowHover : .clear))
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }
}

// MARK: - 링크로 추가…

private struct ArisAILinkSheet: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let link: ArisAILinkState
    @ObservedObject var model: ArisAIServicesModel

    private var text: Binding<String> {
        Binding(get: { link.text }, set: { value in
            guard case .link(var next)? = model.sheet else { return }
            next.text = value
            next.error = nil
            model.sheet = .link(next)
        })
    }

    var body: some View {
        ArisAISheetFrame(title: "링크로 추가", meta: "ElevenLabs", close: { model.performSheet(.close) }) {
            if let found = link.found {
                let (id, name, desc, preview): (String, String, String, String?) = {
                    switch found {
                    case .mine(let voice): (voice.id, voice.name, voice.desc, voice.preview)
                    case .shared(let voice): (voice.id, voice.name, voice.desc, voice.preview)
                    }
                }()
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.title)
                        if !desc.isEmpty { Text(desc).font(.system(size: 11)).foregroundStyle(palette.desc) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ArisAISampleButton(playing: model.state.ui.playing == id, name: name, enabled: preview != nil) { model.perform(.sample(id: id, url: preview)) }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.well))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.hairline, lineWidth: 1))
                Text(w({ if case .mine = found { return "내 ElevenLabs 계정에 이미 있는 목소리예요" }; return "내 ElevenLabs 계정에 이 목소리를 추가해요" }()))
                    .font(.system(size: 12)).foregroundStyle(palette.ink3)
                if let error = link.error { Text(w(error)).font(.system(size: 12)).foregroundStyle(palette.red) }
            } else {
                ArisAILabelled(label: "라이브러리 공유 링크나 목소리 ID", note: link.error, tone: .bad) {
                    ArisAITextField(placeholder: "https://elevenlabs.io/app/voice-library?voiceId=…", text: text, mono: true, autofocus: true) { model.performSheet(.checkLink) }
                }
            }
        } foot: {
            ArisSettingsButton(title: "취소") { model.performSheet(.close) }
            if case .mine? = link.found {
                ArisSettingsButton(title: "이 목소리 쓰기", kind: .primary, enabled: !link.busy) { model.performSheet(.addLink) }
            } else if link.found != nil {
                ArisSettingsButton(title: link.busy ? "추가 중…" : "추가", kind: .primary, enabled: !link.busy) { model.performSheet(.addLink) }
            } else {
                ArisSettingsButton(title: link.busy ? "확인 중…" : "확인", kind: .primary, enabled: !link.busy) { model.performSheet(.checkLink) }
            }
        }
    }
}
