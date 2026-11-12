//
//  ArisWorkSettings.swift
//  Aris
//
//  설정 › 기억 › 일하면서 배운 것: what Aris learned from its own work (the agent's work memory, ArisWorkMemory), as rows
//  of the existing settings components: the 한 일에서 배우기 switch (on by default), one row per lesson with what it is
//  based on and 지우기, and 배운 것 모두 지우기 (asked twice). The agent sends each lesson already worded in both
//  languages (the commands in it are what Aris ran, and stay as they are); the rows are plain functions of the
//  snapshot. Foundation only (tested).
//

import Foundation

/// One lesson as the agent's POST /memory {"op": "work"} gives it.
struct ArisWorkLessonItem: Decodable, Equatable, Identifiable, Sendable {
    let id: Int
    /// "way", "flag", "place" or "name".
    let kind: String
    /// What it says, in Korean and in English.
    let ko: String
    let en: String
    /// What it is based on: how many times, the latest of them, how sure.
    let basisKo: String
    let basisEn: String
    var confidence: Double? = nil
    /// It rests on a turn that read outside content (a page, mail, a file, the screen): the row says so.
    var outside: Bool? = nil
}

enum ArisWorkSettingsRows {
    static let heading = "일하면서 배운 것"
    static let note = "Aris가 직접 한 일의 기록에서 배워요. 웹·메일·파일·화면을 읽은 대화에서 배운 것에는 그렇다고 적어 두니, 마음에 안 들면 지우세요."
    /// The mark before the basis of a lesson that rests on a turn that read outside content.
    static let outsideMark = "바깥 글을 본 대화에서 배움"
    static let toggleTitle = "한 일에서 배우기"
    static let toggleDesc = "어떤 방법이 통했는지 이 Mac에 적어 두고 다음에는 바로 그렇게 해요."
    static let emptyTitle = "아직 배운 게 없어요"
    static let emptyDesc = "같은 일을 몇 번 하다 보면 여기에 모여요"
    static let loadingTitle = "불러오는 중"
    static let silentTitle = "Aris 에이전트가 답하지 않아요"
    static let clearTitle = "배운 것 모두 지우기"
    static let clearDesc = "한 일의 기록과 거기서 배운 것을 전부 지워요."
    static let clearAsk = "한 일의 기록과 배운 것을 지우고 되돌릴 수 없어요."
    static let forget = "지우기"
    static let cancel = "취소"
    static let really = "정말 지우기"
    static let forgotToast = "배운 걸 지웠어요"
    static let clearedToast = "배운 것을 모두 지웠어요"

    /// The rows' English, by their Korean (ArisSettingsCopyMore). A lesson's own words come from the agent in both.
    static let english: [String: String] = [
        heading: "What Aris learned from its work",
        note: "Aris learns from its own record of what it did. What it learned in a conversation that read the web, mail, a file or the screen says so: remove it if you don't want it.",
        outsideMark: "Learned in a conversation that read outside text",
        toggleTitle: "Learn from work",
        toggleDesc: "Notes which way worked on this Mac and starts there next time.",
        emptyTitle: "Nothing learned yet",
        emptyDesc: "It gathers here as the same kinds of things get done",
        clearTitle: "Forget everything learned",
        clearDesc: "Removes the record of what Aris did and everything learned from it.",
        clearAsk: "Removes the record and what was learned, and can't be undone.",
        forgotToast: "Forgotten",
        clearedToast: "Everything learned is forgotten",
    ]

    private static let symbols = ["way": "arrow.triangle.branch", "flag": "flag", "place": "folder", "name": "tag"]

    /// A lesson's small line: what it rests on, after the outside mark when it was learned where outside text was read.
    static func describe(_ item: ArisWorkLessonItem, english: Bool) -> String {
        let basis = english ? item.basisEn : item.basisKo
        guard item.outside == true else { return basis }
        return (english ? Self.english[outsideMark] ?? outsideMark : outsideMark) + " · " + basis
    }

    /// `english`: the UI's language (ArisUILanguage), for the lessons' own lines.
    static func sections(_ s: ArisSettingsSnapshot, english: Bool = ArisUILanguage.english) -> [ArisSettingSection] {
        var rows = [ArisSettingItem(id: "memory.work", icon: .symbol("checklist"), title: toggleTitle, desc: toggleDesc,
                                    control: .toggle(.workMemory, s.workMemory, enabled: s.workLessons != nil))]
        if let lessons = s.workLessons, !lessons.isEmpty {
            rows += lessons.map { item in
                ArisSettingItem(id: "memory.work.item.\(item.id)", icon: .symbol(symbols[item.kind] ?? "checklist"), title: english ? item.en : item.ko,
                                desc: describe(item, english: english),
                                control: .buttons([ArisSettingButton(title: forget, action: .forgetWorkLesson(item.id))]), indexed: false)
            }
        } else {
            let text = !s.memoriesLoaded ? loadingTitle : s.workLessons == nil ? silentTitle : emptyTitle
            rows.append(ArisSettingItem(id: "memory.work.none", icon: .none, title: text, desc: s.workLessons?.isEmpty == true ? emptyDesc : nil,
                                        control: s.memoriesLoaded ? .empty : .loading, indexed: false))
        }
        let clear: ArisSettingControl = s.confirmingWorkClear
            ? .buttons([ArisSettingButton(title: cancel, action: .keepWork), ArisSettingButton(title: really, action: .forgetAllWork, kind: .danger)])
            : .buttons([ArisSettingButton(title: forget, action: .forgetAllWork, kind: .danger, enabled: s.workEpisodes > 0 || s.workLessons?.isEmpty == false)])
        return [
            ArisSettingSection(id: "memory.working", heading: heading, note: note, grouped: true, rows: rows),
            ArisSettingSection(id: "memory.work.danger", rows: [
                ArisSettingItem(id: "memory.work.clear", icon: .symbol("trash"), title: clearTitle, desc: s.confirmingWorkClear ? clearAsk : clearDesc,
                                control: clear, danger: true),
            ]),
        ]
    }
}
