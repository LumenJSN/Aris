//
//  ArisDataSection.swift
//  Aris
//
//  정보 › 데이터's sheets (mockup audit-4-settings-extra.html option C). 데이터 내보내기 and 진단 내보내기 save a file;
//  데이터 지우기 and 제거 are red and wait for their word to be typed (ArisTypedConfirm). The work is ArisDataModel's;
//  the rows that open them are the 정보 page's (ArisSettingsBuilder).
//

import SwiftUI

/// The sheet for `kind`, drawn by the settings root (ArisSettingsModalHost).
struct ArisDataSheet: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let kind: ArisSettingsOverlay.Sheet
    @ObservedObject var model: ArisDataModel

    var body: some View {
        switch kind {
        case .export: export
        case .diagnostics: diagnostics
        case .wipe: wipe
        case .uninstall: uninstall
        default: EmptyView()
        }
    }

    private func close() { model.close() }

    // MARK: 데이터 내보내기

    private var export: some View {
        ArisSheetFrame(title: "데이터 내보내기", subtitle: "고른 것을 JSON 파일 하나로 묶어 저장해요.", onClose: close) {
            HStack {
                Text(w("대화 기록 기간")).font(.system(size: 12.5)).foregroundStyle(palette.desc)
                Spacer(minLength: 0)
                ArisGlassSegmented(options: [.init(id: "all", title: "전체"), .init(id: "recent", title: "최근 30일")],
                                   selected: model.exportRecent ? "recent" : "all", label: "대화 기록 기간") { model.exportRecent = $0 == "recent" }
            }
            .padding(.top, 10)
            VStack(alignment: .leading, spacing: 2) {
                ArisSheetListRow(lead: { ArisCheckBox(isOn: $model.exportHistory) }, title: "대화 기록", sub: "질문과 답, 날짜",
                                 size: "\(model.counts.history)개", dimmed: !model.exportHistory)
                ArisSheetListRow(lead: { ArisCheckBox(isOn: $model.exportMemory) }, title: "Aris가 기억하는 것", sub: "기억해 달라고 한 사실들",
                                 size: model.counts.memoryFacts.map { "\($0)개" }, dimmed: !model.exportMemory)
                ArisSheetListRow(lead: { ArisCheckBox(isOn: $model.exportTeammates) }, title: "팀원", sub: "이름, 역할, 모양",
                                 dimmed: !model.exportTeammates)
            }
            .padding(.top, 10)
        } footer: {
            ArisPillButton(title: "취소", kind: .ghost, action: close)
            ArisPillButton(title: "내보내기", enabled: model.canExport) { Task { await model.export() } }
        }
    }

    // MARK: 진단 내보내기

    private var diagnostics: some View {
        ArisSheetFrame(title: "진단 내보내기", subtitle: "문제가 생겼을 때 보낼 파일을 만들어요. 보내기 전에 열어 볼 수 있어요.", onClose: close) {
            HStack(alignment: .top, spacing: 10) {
                box("들어가는 것", ["앱 · macOS 버전, Mac 종류", "앱과 에이전트의 최근 기록", "권한 상태(켜짐/꺼짐만)"])
                box("절대 안 들어가는 것", ["API 키와 토큰", "~/.config/aris 설정 내용", "대화 내용, 클립보드", "화면, 사진"])
            }
            .padding(.top, 10)
        } footer: {
            ArisPillButton(title: "취소", kind: .ghost, action: close)
            ArisPillButton(title: model.busy ? "만드는 중…" : "파일 만들기", enabled: !model.busy) { Task { await model.diagnostics() } }
        }
    }

    private func box(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(w(title)).font(.system(size: 11, weight: .semibold)).tracking(0.33).foregroundStyle(palette.faint)
            ForEach(lines, id: \.self) { Text(w($0)).font(.system(size: 12)).foregroundStyle(palette.desc).lineSpacing(2) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.soft))
    }

    // MARK: 데이터 지우기

    private var wipe: some View {
        ArisSheetFrame(title: "데이터 지우기", subtitle: "고른 것을 이 Mac에서 지워요.", onClose: close) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ArisAppData.Item.allCases) { item in
                    ArisSheetListRow(lead: { ArisCheckBox(isOn: wipeBinding(item)) }, title: item.title, size: size(of: item),
                                     dimmed: !model.wipeSelection.contains(item))
                }
            }
            .padding(.top, 10)
            Text(w("설정, API 키와 작업 기록(actions.log)은 남겨요. 되돌릴 수 없어요.")).font(.system(size: 12)).foregroundStyle(palette.faint)
                .padding(.top, 8).padding(.leading, 10)
            ArisTypeToConfirm(word: ArisTypedConfirm.wipeWord, typed: $model.wipeTyped) { Task { await model.wipe() } }
        } footer: {
            ArisPillButton(title: "취소", kind: .ghost, action: close)
            ArisPillButton(title: "\(model.wipeSelection.count)개 지우기", kind: .solidRed, enabled: model.canWipe) { Task { await model.wipe() } }
        }
    }

    private func wipeBinding(_ item: ArisAppData.Item) -> Binding<Bool> {
        Binding(get: { model.wipeSelection.contains(item) }, set: { on in
            if on { model.wipeSelection.insert(item) } else { model.wipeSelection.remove(item) }
        })
    }

    private func size(of item: ArisAppData.Item) -> String? {
        let bytes = { (n: Int) in ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) }
        switch item {
        case .history: return "\(model.counts.history)개"
        case .clipboard: return "\(model.counts.clipboard)개"
        case .memory: return model.counts.memoryFacts.map { "\($0)개" }
        case .words: return nil
        case .sprites: return bytes(model.counts.spriteBytes)
        case .logs: return bytes(model.counts.appLogBytes + (model.counts.agentLogBytes ?? 0))
        }
    }

    // MARK: 제거

    private var uninstallTitle: (title: String, subtitle: String) {
        if model.uninstallFinished { return ("Aris를 제거했어요", "휴지통을 비우면 끝나요. 그동안 고마웠어요.") }
        if model.uninstallDone != nil { return ("제거하는 중", "잠시만 기다려 주세요.") }
        return ("Aris 제거", "Aris가 이 Mac에 만든 것을 모두 찾아 지워요. 끝나면 앱이 닫혀요.")
    }

    private var uninstallList: some View {
        let rows = ArisDataModel.uninstallRows(appPath: model.actions.appPath)
        let started = model.uninstallDone != nil
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let kept = row.id == "data" && !model.removeRecords
                ArisSheetListRow(lead: { uninstallLead(row.id, index: index, kept: kept) }, title: row.title, path: row.path,
                                 dimmed: kept, tag: row.id == "data" && !started ? "끄면 기록을 남겨요" : nil)
            }
        }
    }

    private var uninstall: some View {
        let started = model.uninstallDone != nil
        let finished = model.uninstallFinished
        let heading = uninstallTitle
        // No × while the agent works through the list.
        let onClose: (() -> Void)? = started && !finished ? nil : { model.close() }
        return ArisSheetFrame(title: heading.title, subtitle: heading.subtitle, onClose: onClose) {
            uninstallList.padding(.top, 10)
            if !started { ArisTypeToConfirm(word: ArisTypedConfirm.uninstallWord, typed: $model.uninstallTyped) { Task { await model.uninstall() } } }
            if let error = model.uninstallError {
                Text(w(error)).font(.system(size: 12)).foregroundStyle(palette.red).padding(.top, 8).fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            if finished {
                ArisPillButton(title: "닫기") { model.actions.quit() }
            } else if !started {
                ArisPillButton(title: "취소", kind: .ghost, action: close)
                ArisPillButton(title: "제거하고 닫기", kind: .solidRed, enabled: model.canUninstall) { Task { await model.uninstall() } }
            }
        }
    }

    @ViewBuilder
    private func uninstallLead(_ id: String, index: Int, kept: Bool) -> some View {
        if let done = model.uninstallDone {
            if kept { Text("–").font(.system(size: 13)).foregroundStyle(palette.faint) }
            else if index < done && model.failedRows.contains(id) {
                ArisLineIcon("exclamationmark.circle.fill", size: 17).foregroundStyle(palette.red)
            }
            else if index < done { ArisLandingCheck() }
            else { Color.clear.frame(width: 16, height: 16) }
        } else if id == "data" {
            ArisCheckBox(isOn: $model.removeRecords)
        } else {
            ArisCheckBox(isOn: .constant(true), enabled: false)
        }
    }
}
