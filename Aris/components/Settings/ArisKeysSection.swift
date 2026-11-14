//
//  ArisKeysSection.swift
//  Aris
//
//  AI 서비스 › API 키: ElevenLabs and TypeSafe, pasted once and kept only in the macOS Keychain (ArisKeychain). A saved
//  key shows as dots and its last four, with 바꾸기 and 지우기; an empty one shows the field, where to get the key, or
//  what is wrong with what was pasted (ArisKeyFile.check). The row is mockup C's `.keyrow` (settings-redesign.html).
//

import SwiftUI

@MainActor
final class ArisKeysModel: ObservableObject {
    struct Key: Identifiable {
        let name: String
        let title: String
        let use: String
        let source: String
        var id: String { name }
    }

    enum State: Equatable {
        case saved(masked: String)
        case empty(error: String?)
        case saving
    }

    struct Actions {
        var read: @MainActor (String) -> String?
        /// Nil when saved, else what to tell the user.
        var save: @MainActor (String, String) -> String?
        /// Nil when deleted (and its old file gone or unused), else what to tell the user.
        var delete: @MainActor (String) async -> String?
    }

    static let keys = [
        Key(name: "elevenlabs-key", title: "ElevenLabs", use: "Aris 목소리와 Scribe 받아쓰기에 써요. 없으면 Mac 목소리로 말해요.",
            source: "elevenlabs.io › 내 계정 › API 키"),
        Key(name: "typesafe-key", title: "TypeSafe", use: "“노래 바꿔 줘” 같은 짧은 명령을 빨리 알아듣는 데 써요. 없으면 이 기능만 꺼져요.",
            source: "typesafe.ai › 대시보드"),
    ]

    @Published private(set) var states: [String: State] = [:]
    @Published var drafts: [String: String] = [:]
    let actions: Actions
    var toast: (String) -> Void = { ArisSettingsOverlay.shared.show($0) }
    /// The same toast with the red mark: something that did not happen.
    var fail: (String) -> Void = { ArisSettingsOverlay.shared.show($0, tone: .bad) }

    init(actions: Actions) {
        self.actions = actions
        reload()
    }

    func reload() {
        for key in Self.keys {
            states[key.name] = actions.read(key.name).map { .saved(masked: ArisKeyFile.masked($0)) } ?? .empty(error: nil)
        }
    }

    func save(_ key: Key) {
        switch ArisKeyFile.check(drafts[key.name] ?? "") {
        case .failure(let problem):
            states[key.name] = .empty(error: problem.message)
        case .success(let value):
            states[key.name] = .saving
            if let failure = actions.save(key.name, value) {
                states[key.name] = .empty(error: failure)
            } else {
                drafts[key.name] = nil
                states[key.name] = .saved(masked: ArisKeyFile.masked(value))
                toast("\(key.title) 키를 저장했어요")
            }
        }
    }

    func edit(_ key: Key) { states[key.name] = .empty(error: nil) }

    /// Back to the saved key, leaving what was typed.
    func cancel(_ key: Key) {
        drafts[key.name] = nil
        states[key.name] = actions.read(key.name).map { .saved(masked: ArisKeyFile.masked($0)) } ?? .empty(error: nil)
    }

    /// A key is in the Keychain (so a change can be cancelled).
    func isStored(_ key: Key) -> Bool { actions.read(key.name) != nil }

    func delete(_ key: Key) async {
        let problem = await actions.delete(key.name)
        reload()
        if let problem { fail(problem) } else { toast("키체인에서 키를 지웠어요") }
    }
}

/// One key's row (`.keyrow`, 18 × 20): the key icon, the name with 켜짐 or 없음, what it's for, and under it (32 in)
/// either the saved key or the field with 저장.
struct ArisKeyRow: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let key: ArisKeysModel.Key
    @ObservedObject var model: ArisKeysModel

    private var state: ArisKeysModel.State { model.states[key.name] ?? .empty(error: nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                ArisLineIcon("key", size: 20).foregroundStyle(palette.icon).frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(key.title).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.title)
                        if case .saved = state { ArisChip(text: "켜짐", tone: .ok) } else { ArisChip(text: "없음") }
                    }
                    Text(w(key.use)).font(.system(size: 12)).foregroundStyle(palette.desc).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if case .saved = state {
                    HStack(spacing: 8) {
                        ArisSettingsButton(title: "바꾸기", small: true) { model.edit(key) }
                        ArisSettingsButton(title: "지우기", kind: .danger, small: true) { Task { await model.delete(key) } }
                    }
                }
            }
            detail.padding(.leading, 32)
        }
        .padding(ArisSettingsMetrics.rowInset)
    }

    @ViewBuilder
    private var detail: some View {
        switch state {
        case .saved(let masked):
            (Text(w("키체인에 저장됨 · ")).font(.system(size: 12)) + Text(masked).font(.system(size: 12, design: .monospaced)))
                .foregroundStyle(palette.desc).padding(.top, 8)
        case .saving:
            Text(w("키를 저장하는 중…")).font(.system(size: 12)).foregroundStyle(palette.desc).padding(.top, 8)
        case .empty(let error):
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ArisTextField(placeholder: "여기에 붙여 넣기", text: Binding(get: { model.drafts[key.name] ?? "" }, set: { model.drafts[key.name] = $0 }),
                                  secure: true) { model.save(key) }
                        .accessibilityLabel(w("\(key.title) API 키"))
                    ArisSettingsButton(title: "저장", kind: .primary) { model.save(key) }
                    if model.isStored(key) { ArisSettingsButton(title: "취소") { model.cancel(key) } }
                }
                .padding(.top, 12)
                Text(w(error ?? "키 받는 곳: \(w(key.source))")).font(.system(size: 12)).foregroundStyle(error == nil ? palette.desc : palette.red).padding(.top, 8)
            }
        }
    }
}
