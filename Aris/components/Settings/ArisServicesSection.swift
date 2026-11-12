//
//  ArisServicesSection.swift
//  Aris
//
//  AI 서비스 › 연결된 서비스, the external services every brain reaches through `aris-tools mcp`: the user's Composio key
//  (one key, every app Composio connects) and his own MCP servers (a command or a URL, and a token). The agent keeps
//  the list and the Keychain; this page only sends what the user typed and shows what the agent says back, never a key.
//  Built from the page's own parts (ArisKeyRow's layout, ArisSwitch, ArisSettingsButton, ArisChip, ArisTextField):
//  no new look.
//

import SwiftUI

@MainActor
final class ArisServicesModel: ObservableObject {
    static let shared = ArisServicesModel()

    @Published private(set) var rows: [ArisMCPServiceRow] = []
    @Published private(set) var loaded = false
    @Published private(set) var reachable = true
    /// The agent found the list changed outside Aris: no server starts until it's saved again.
    @Published private(set) var problem: String?
    /// A line under a row (a test's result, or what went wrong), by row id.
    @Published var notes: [String: (ok: Bool, text: String)] = [:]
    @Published var busy: Set<String> = []
    @Published var composioDraft = ""
    @Published var composioEditing = false
    @Published var composioError: String?
    /// The add form (or a row being changed: `editing`).
    @Published var name = ""
    @Published var target = ""
    @Published var token = ""
    @Published var tokenName = ""
    @Published var formError: String?
    @Published var editing: String?
    var toast: (String) -> Void = { ArisSettingsOverlay.shared.show($0) }
    /// The same toast with the red mark: something that did not happen.
    var fail: (String) -> Void = { ArisSettingsOverlay.shared.show($0, tone: .bad) }

    var composio: ArisMCPServiceRow? { rows.first(where: \.composio) }
    var servers: [ArisMCPServiceRow] { rows.filter { !$0.composio } }

    func reload() async {
        let found = await ArisAgentClient.mcpServices()
        reachable = found != nil
        rows = found?.rows ?? []
        problem = found?.problem
        loaded = true
    }

    func saveComposio() async {
        let key = composioDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { composioError = "키를 붙여 넣어 주세요."; return }
        busy.insert("composio")
        defer { busy.remove("composio") }
        if let problem = await ArisAgentClient.setComposioKey(key) {
            composioError = problem
            return
        }
        composioDraft = ""
        composioError = nil
        composioEditing = false
        await reload()
        toast("Composio 키를 저장했어요")
        if let id = composio?.id { await test(id) }
    }

    func removeComposio() async {
        if let problem = await ArisAgentClient.setComposioKey(nil) { return fail(problem) }
        await reload()
        toast("Composio 키를 키체인에서 지웠어요")
    }

    func startEditing(_ row: ArisMCPServiceRow) {
        editing = row.id
        name = row.name
        target = row.edit
        token = ""
        tokenName = row.secretName ?? ""
        formError = nil
    }

    func cancelEditing() {
        editing = nil
        name = ""; target = ""; token = ""; tokenName = ""; formError = nil
    }

    /// 추가 or 저장 (a row being changed keeps its token unless a new one is typed).
    func saveServer() async {
        busy.insert("form")
        defer { busy.remove("form") }
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = await ArisAgentClient.saveMCPService(id: editing, name: name, target: target, secretName: tokenName,
                                                              secret: secret.isEmpty ? nil : secret) {
            formError = problem
            return
        }
        let added = editing == nil
        let shown = name.trimmingCharacters(in: .whitespaces).lowercased()
        cancelEditing()
        await reload()
        toast(added ? "\(shown) 서비스를 추가했어요" : "\(shown) 서비스를 바꿨어요")
        if let id = rows.first(where: { $0.name == shown })?.id { await test(id) }
    }

    func remove(_ row: ArisMCPServiceRow) async {
        if let problem = await ArisAgentClient.removeMCPService(row.id) { return fail(problem) }
        notes[row.id] = nil
        await reload()
        toast("\(row.name) 서비스를 뺐어요")
    }

    func toggle(_ row: ArisMCPServiceRow) async {
        if let problem = await ArisAgentClient.enableMCPService(row.id, !row.enabled) { return fail(problem) }
        await reload()
    }

    func test(_ id: String) async {
        busy.insert(id)
        defer { busy.remove(id) }
        let result = await ArisAgentClient.testMCPService(id)
        notes[id] = (result.ok, result.message)
        await reload()
    }

    /// "도구 9개 · 읽기 6개 · 할 때마다 묻는 것 3개", or nil before any connection.
    static func toolsLine(_ row: ArisMCPServiceRow) -> String? {
        guard let tools = row.tools else { return nil }
        let reads = tools.filter { $0.kind == "read" }.count
        let names = tools.prefix(4).map(\.name).joined(separator: ", ") + (tools.count > 4 ? " …" : "")
        return "도구 \(tools.count)개 · 읽기 \(reads)개, 나머지 \(tools.count - reads)개는 할 때마다 물어봐요" + (names.isEmpty ? "" : "\n\(names)")
    }
}

/// The Composio row: the key (saved, or the field to paste it), the on/off switch, 연결 테스트 and what it found.
struct ArisComposioRow: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @ObservedObject var model: ArisServicesModel

    var body: some View {
        let row = model.composio
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 16.5, weight: .medium)).foregroundStyle(palette.icon).frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Composio").font(.system(size: 14, weight: .medium)).tracking(-0.07).foregroundStyle(palette.title)
                        if let row { ArisChip(text: row.enabled ? "켜짐" : "꺼짐", tone: row.enabled ? .ok : .plain) } else { ArisChip(text: "없음") }
                    }
                    Text(w("Gmail, Slack, Notion, Google 캘린더 등 여러 앱을 한 키로 연결해요. 읽기는 바로 하고, 보내거나 바꾸는 일은 매번 물어봐요."))
                        .font(.system(size: 12)).foregroundStyle(palette.desc).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let row, !model.composioEditing {
                    HStack(spacing: 8) {
                        ArisSwitch(isOn: row.enabled, label: "Composio") { Task { await model.toggle(row) } }
                        ArisSettingsButton(title: model.busy.contains(row.id) ? "확인 중…" : "연결 테스트", small: true, enabled: !model.busy.contains(row.id)) {
                            Task { await model.test(row.id) }
                        }
                        ArisSettingsButton(title: "바꾸기", small: true) { model.composioEditing = true }
                        ArisSettingsButton(title: "지우기", kind: .danger, small: true) { Task { await model.removeComposio() } }
                    }
                }
            }
            detail(row).padding(.leading, 32)
        }
        .padding(ArisSettingsMetrics.rowInset)
    }

    @ViewBuilder
    private func detail(_ row: ArisMCPServiceRow?) -> some View {
        if let row, !model.composioEditing {
            VStack(alignment: .leading, spacing: 6) {
                Text(w("키체인에 저장됨 · connect.composio.dev")).font(.system(size: 12)).foregroundStyle(palette.desc)
                ArisServiceNotes(row: row, model: model)
            }
            .padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ArisTextField(placeholder: "ck_로 시작하는 키 붙여 넣기", text: $model.composioDraft, secure: true) { Task { await model.saveComposio() } }
                        .accessibilityLabel(w("Composio API 키"))
                    ArisSettingsButton(title: model.busy.contains("composio") ? "저장 중…" : "저장", kind: .primary, enabled: !model.busy.contains("composio")) {
                        Task { await model.saveComposio() }
                    }
                    if row != nil { ArisSettingsButton(title: "취소") { model.composioEditing = false; model.composioDraft = "" } }
                }
                .padding(.top, 12)
                Text(w(model.composioError ?? "키 받는 곳: composio.dev에서 계정을 만들고 Install › MCP URL의 “Your API Key”를 복사해요. 앱 연결(구글 로그인 등)은 Composio가 처음 쓸 때 링크로 물어봐요."))
                    .font(.system(size: 12)).foregroundStyle(model.composioError == nil ? palette.desc : palette.red).padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One MCP server: its name and on/off, what it is, its tools, 연결 테스트, 바꾸기 and 지우기.
struct ArisMCPServerRow: View {
    @Environment(\.arisPalette) private var palette
    let row: ArisMCPServiceRow
    @ObservedObject var model: ArisServicesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: row.transport == "stdio" ? "terminal" : "network").font(.system(size: 16.5, weight: .medium))
                    .foregroundStyle(palette.icon).frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.name).font(.system(size: 14, weight: .medium)).tracking(-0.07).foregroundStyle(palette.title)
                        ArisChip(text: row.enabled ? "켜짐" : "꺼짐", tone: row.enabled ? .ok : .plain)
                        if row.hasSecret { ArisChip(text: "토큰 있음") }
                    }
                    Text(row.target).font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.desc).lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    ArisSwitch(isOn: row.enabled, label: row.name) { Task { await model.toggle(row) } }
                    ArisSettingsButton(title: model.busy.contains(row.id) ? "확인 중…" : "연결 테스트", small: true, enabled: !model.busy.contains(row.id)) {
                        Task { await model.test(row.id) }
                    }
                    ArisSettingsButton(title: "바꾸기", small: true) { model.startEditing(row) }
                    ArisSettingsButton(title: "지우기", kind: .danger, small: true) { Task { await model.remove(row) } }
                }
            }
            ArisServiceNotes(row: row, model: model).padding(.leading, 32).padding(.top, 8)
        }
        .padding(ArisSettingsMetrics.rowInset)
    }
}

/// Every MCP server the user added, hairlines between (or one line when there are none yet).
struct ArisMCPServerList: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @ObservedObject var model: ArisServicesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let problem = model.problem {
                Text(w(problem)).font(.system(size: 12)).foregroundStyle(palette.red).padding(.horizontal, 20).padding(.vertical, 14)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.servers.isEmpty {
                Text(w(!model.loaded ? "불러오는 중…" : model.reachable ? "아직 추가한 MCP 서버가 없어요." : "Aris 에이전트가 답하지 않아요."))
                    .font(.system(size: 12)).foregroundStyle(palette.desc).padding(.horizontal, 20).padding(.vertical, 14)
            }
            ForEach(Array(model.servers.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Rectangle().fill(palette.hairline).frame(height: 1) }
                ArisMCPServerRow(row: row, model: model)
            }
        }
    }
}

/// Under a row: the tools the last connection found, and the last test's line (or error).
struct ArisServiceNotes: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let row: ArisMCPServiceRow
    @ObservedObject var model: ArisServicesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let tools = ArisServicesModel.toolsLine(row) {
                Text(w(tools)).font(.system(size: 12)).foregroundStyle(palette.desc).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            if let note = model.notes[row.id] {
                Text(w(note.text)).font(.system(size: 12)).foregroundStyle(note.ok ? palette.desc : palette.red).fixedSize(horizontal: false, vertical: true)
            } else if let error = row.error {
                Text(w(error)).font(.system(size: 12)).foregroundStyle(palette.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 서버 추가 (or 바꾸기 for one row): a name, a command or URL, and an optional token with where it goes.
struct ArisMCPAddRow: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @ObservedObject var model: ArisServicesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: model.editing == nil ? "plus" : "pencil").font(.system(size: 16.5, weight: .medium)).foregroundStyle(palette.icon)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(w(model.editing == nil ? "MCP 서버 추가" : "MCP 서버 바꾸기")).font(.system(size: 14, weight: .medium)).tracking(-0.07).foregroundStyle(palette.title)
                    Text(w("명령(예: npx -y @modelcontextprotocol/server-everything)이나 https URL을 넣어요. 토큰은 키체인에만 저장되고, AI에게는 보이지 않아요."))
                        .font(.system(size: 12)).foregroundStyle(palette.desc).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ArisTextField(placeholder: "이름 (예: github)", text: $model.name, width: 160)
                    ArisTextField(placeholder: "명령 또는 URL", text: $model.target) { Task { await model.saveServer() } }
                }
                HStack(spacing: 8) {
                    ArisTextField(placeholder: model.editing == nil ? "토큰 (없으면 비워 두기)" : "새 토큰 (그대로면 비워 두기)", text: $model.token, secure: true)
                    ArisTextField(placeholder: "헤더 또는 환경 변수 이름 (선택)", text: $model.tokenName, width: 220)
                    ArisSettingsButton(title: model.busy.contains("form") ? "확인 중…" : model.editing == nil ? "추가" : "저장", kind: .primary,
                                       enabled: !model.busy.contains("form")) { Task { await model.saveServer() } }
                    if model.editing != nil { ArisSettingsButton(title: "취소") { model.cancelEditing() } }
                }
                Text(w(model.formError ?? "토큰은 URL이면 Authorization: Bearer로 보내고, 이름을 적으면 그 헤더(예: x-api-key)로 보내요. 명령이면 적은 환경 변수(예: GITHUB_TOKEN)로 넘겨요."))
                    .font(.system(size: 12)).foregroundStyle(model.formError == nil ? palette.desc : palette.red).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 32).padding(.top, 12)
        }
        .padding(ArisSettingsMetrics.rowInset)
    }
}
