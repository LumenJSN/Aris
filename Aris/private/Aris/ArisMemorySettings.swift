//
//  ArisMemorySettings.swift
//  Aris
//
//  설정 › 기억: what aris-agent remembers about the user (memory.sqlite, which only the agent opens), as rows of the
//  existing settings components: the 자동으로 기억하기 and 매주 정리하기 switches, what waits for his look, the people
//  and project pages (ArisMemoryReviewRows), a search field, one row per memory with where it came from (직접 말함 /
//  추정 / 가져옴) and 지우기, and 모두 지우기 (asked twice). The rows are plain functions of the snapshot. Foundation
//  only (tested).
//

import Foundation

/// One memory as the agent's POST /memory list gives it.
struct ArisMemoryItem: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: String
    let subject: String
    let text: String
    let source: String
    /// When the user said it (seconds since 1970).
    let said: Double
    let used: Double?
    /// 0…1; below `confirmedAt` it waits for the user's 확인 (or for them to say it again).
    var confidence: Double? = nil
    /// An imported memory: the AI it came from as the user named it, and "instruction" for a ticked instruction
    /// (ArisMemoryImportCopy).
    var via: String? = nil
    var mark: String? = nil
    /// How many older wordings it keeps (never shown; said here so the user knows it changed).
    var changed: Int? = nil
    /// An event's end (seconds since 1970): it holds until then.
    var until: Double? = nil

    static let confirmedAt = 0.8
    var confirmed: Bool { (confidence ?? 1) >= Self.confirmedAt }
}

enum ArisMemorySettingsRows {
    /// What aris-agent and aris-tools say after each memory write (ArisMemoryStore.changedNotification: the same name).
    static let changedNotification = "com.lumenjsn.aris.memory"

    /// The page reads the list again on that notification while 기억 is the page shown (ninth VM pass: it said "9가지"
    /// until it was opened again).
    static func reloadsOnChange(page: ArisSettingsPage) -> Bool { page == .memory }

    private static let kinds: [String: (title: String, symbol: String)] = [
        "preference": ("취향", "heart"), "fact": ("나에 대해", "person.text.rectangle"), "project": ("하는 일", "hammer"),
        "person": ("사람", "person.2"), "routine": ("습관", "repeat"), "commitment": ("약속", "checkmark.circle"), "event": ("일정", "calendar"),
    ]

    /// The memories whose words, subject or kind contain what was typed (spaces and case ignored; 초성 too).
    static func filtered(_ items: [ArisMemoryItem], query: String) -> [ArisMemoryItem] {
        let q = ArisSettingsIndex.normalized(query)
        guard !q.isEmpty else { return items }
        return items.filter { item in
            let words = item.subject + " " + item.text + " " + (kinds[item.kind]?.title ?? "")
            return ArisSettingsIndex.normalized(words).contains(q) || ArisSettingsIndex.initials(words).contains(q)
        }
    }

    /// An event's end in the row ("11월 14일까지"), as its English is looked up.
    static let untilDay = "%d월 %d일까지"

    /// "취향 · 11월 3일 · 직접 말함"; an event also says until when ("일정 · 11월 13일 · 11월 13일까지 · 직접 말함").
    static func desc(_ item: ArisMemoryItem, calendar: Calendar = .current) -> String {
        let date = Date(timeIntervalSince1970: item.said)
        let parts = calendar.dateComponents([.month, .day], from: date)
        let day = "\(parts.month ?? 0)월 \(parts.day ?? 0)일"
        let until = item.until.map { calendar.dateComponents([.month, .day], from: Date(timeIntervalSince1970: $0)) }
            .map { "\($0.month ?? 0)월 \($0.day ?? 0)일까지" } ?? ""
        // An imported one says where it came from ("가져옴 · <the name he gave>"), and an instruction that it is one.
        let source = item.via.map { ["가져옴", $0].joined(separator: " · ") } ?? ArisMemoryReviewRows.sourceLabel(item.source)
        return [kinds[item.kind]?.title ?? item.kind, item.mark == "instruction" ? "지시" : "", day, until, source, item.confirmed ? "" : "확인 전"]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func sections(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] {
        let shown = filtered(s.memories ?? [], query: s.memoryQuery)
        var rows: [ArisSettingItem] = []
        if let memories = s.memories, !memories.isEmpty {
            // The search comes with the first memory: over nothing there is nothing to find.
            rows.append(ArisSettingItem(id: "memory.search", icon: .symbol("magnifyingglass"), title: "기억 찾기", desc: "\(memories.count)가지를 기억하고 있어요.",
                                        control: .field(.memoryQuery, text: s.memoryQuery, placeholder: "찾을 말",
                                                        ArisSettingButton(title: "모두 보기", action: .clearMemoryQuery, enabled: !s.memoryQuery.isEmpty))))
            rows += shown.map { item in
                ArisSettingItem(id: "memory.item.\(item.id)", icon: .symbol(kinds[item.kind]?.symbol ?? "brain"),
                                title: item.subject.isEmpty || ArisSettingsIndex.normalized(item.text).contains(ArisSettingsIndex.normalized(item.subject))
                                    ? item.text : "\(item.subject) — \(item.text)",
                                desc: desc(item),
                                control: .buttons((item.confirmed ? [] : [ArisSettingButton(title: "확인", action: .confirmMemory(item.id))])
                                                  + [ArisSettingButton(title: "지우기", action: .forgetMemory(item.id))]), indexed: false)
            }
            if shown.isEmpty {
                rows.append(ArisSettingItem(id: "memory.none", icon: .none, title: "‘\(s.memoryQuery)’에 맞는 기억이 없어요", control: .empty, indexed: false))
            }
        } else {
            let text = !s.memoriesLoaded ? "불러오는 중" : s.memories == nil ? "Aris 에이전트가 답하지 않아요" : "아직 기억하는 게 없어요"
            rows.append(ArisSettingItem(id: "memory.none", icon: .none, title: text,
                                        desc: s.memories?.isEmpty == true ? "“기억해”라고 말하면 여기에 모여요" : nil,
                                        control: s.memoriesLoaded ? .empty : .loading, indexed: false))
        }
        let clear: ArisSettingControl = s.confirmingMemoryClear
            ? .buttons([ArisSettingButton(title: "취소", action: .keepMemories),
                        ArisSettingButton(title: "정말 지우기", action: .forgetAllMemories, kind: .danger)])
            // With nothing to erase the button stays where it is, at half strength (item 13).
            : .buttons([ArisSettingButton(title: "지우기", action: .forgetAllMemories, kind: .danger, enabled: s.memories?.isEmpty == false)])
        return [
            ArisSettingSection(id: "memory.learning", heading: "배우기", note: "내가 한 말에서만 고르고, 화면·웹·메일에서 온 글, 대화 모드에서 들은 말, 비밀번호는 기억하지 않아요. 꺼도 “기억해”라고 하면 기억해요.", rows: [
                ArisSettingItem(id: "memory.auto", icon: .symbol("square.and.pencil"), title: "자동으로 기억하기",
                                desc: "대화가 끝나면 오래 쓸 만한 걸 골라 이 Mac에 적어 둬요.",
                                control: .toggle(.autoMemory, s.autoMemory, enabled: s.memories != nil)),
                ArisMemoryReviewRows.tidyRow(s),
                ArisSettingItem(id: "memory.import", icon: .symbol("square.and.arrow.down"), title: ArisMemoryImportCopy.rowTitle, desc: ArisMemoryImportCopy.rowDesc,
                                control: .buttons([ArisSettingButton(title: ArisMemoryImportCopy.rowButton, action: .importMemory, enabled: s.memories != nil)])),
            ]),
        ] + ArisMemoryReviewRows.sections(s) + [
            ArisSettingSection(id: "memory.list", heading: "기억하는 것", grouped: true, rows: rows),
            ArisSettingSection(id: "memory.danger", rows: [
                ArisSettingItem(id: "memory.clear", icon: .symbol("trash"), title: "기억 모두 지우기",
                                desc: s.confirmingMemoryClear ? "기억과 하루 요약, 예전 기억 파일까지 지우고 되돌릴 수 없어요." : "기억과 하루 요약을 전부 지워요.",
                                control: clear, danger: true),
            ]),
        ] + ArisWorkSettingsRows.sections(s) + ArisSavedStepsSettingsRows.sections(s)
    }
}
