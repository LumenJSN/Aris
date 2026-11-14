//
//  ArisMemoryReviewSettings.swift
//  Aris
//
//  설정 › 기억's memory-v2 rows, made of the existing settings components:
//  - 확인할 것: what the write gate held (넣기 / 버리기, with why), and conflicts (two memories that say yes and no about
//    the same thing: 이게 맞아요 on the one that is right now, or 둘 다 맞아요);
//  - 사람과 프로젝트: one row per person or project page (its summary, how many entries, what's still open; 지우기);
//  - 매주 정리: the tidy-up's switch (on by default) and each change it made, with 되돌리기.
//  The agent sends the data (ArisMemoryReviewRoute); the rows are plain functions of the snapshot. Each Korean string
//  has its English here (ArisSettingsCopyMore). Foundation only (tested).
//

import Foundation

/// The agent's whole answer to {"op": "list"} (ArisMemoryRoute).
struct ArisMemoryPage: Decodable, Sendable {
    let memories: [ArisMemoryItem]
    let auto: Bool
    var consolidate: Bool? = nil
    var held: [ArisMemoryHeldItem]? = nil
    var conflicts: [ArisMemoryConflictItem]? = nil
    var entities: [ArisMemoryEntityItem]? = nil
    var changes: [ArisMemoryChangeItem]? = nil
}

struct ArisMemoryHeldItem: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    /// "memory" or "lesson".
    let kind: String
    let text: String
    let source: String
    /// Why it was held, in Korean and in English.
    let why: String
    let whyEn: String
}

struct ArisMemoryConflictItem: Decodable, Equatable, Identifiable, Sendable {
    struct Side: Decodable, Equatable, Sendable {
        let id: String
        let text: String
        let source: String
        let said: Double
    }

    let id: String
    /// The older one first.
    let first: Side
    let second: Side
}

struct ArisMemoryEntityItem: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    /// "person" or "project".
    let kind: String
    let name: String
    let summary: String
    let entries: Int
    let open: Int
}

struct ArisMemoryChangeItem: Decodable, Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let before: String
    let after: String
    let at: Double
    let evidence: Int
}

enum ArisMemoryReviewRows {
    static let reviewHeading = "확인할 것"
    static let reviewNote = "AI에게 내리는 지시처럼 보이는 글은 바로 기억하지 않고 여기서 기다려요. 서로 맞지 않는 기억은 지금 맞는 쪽을 골라 주세요. 다른 쪽은 지난 기억으로 남아요."
    static let keep = "넣기"
    static let drop = "버리기"
    static let rightNow = "이게 맞아요"
    static let both = "둘 다 맞아요"
    static let lessonMark = "일하면서 배운 것"
    static let conflictMark = "서로 맞지 않아요"
    static let peopleHeading = "사람과 프로젝트"
    static let peopleNote = "사람이나 프로젝트마다 짧은 요약과 날짜별 기록이 쌓여요. 요약은 내가 직접 한 말로만 바뀌어요."
    static let person = "사람"
    static let project = "프로젝트"
    static let noSummary = "아직 요약이 없어요"
    static let entries = "기록 %d개"
    static let open = "남은 일 %d개"
    static let forget = "지우기"
    static let tidyTitle = "매주 정리하기"
    static let tidyDesc = "일주일에 한 번 쉬는 동안, 내가 직접 세 번 넘게 한 말로만 쓰는 AI가 사람·프로젝트 요약을 다듬고 바꾼 건 여기 남겨요."
    static let undo = "되돌리기"
    static let changed = "정리함"
    static let evidence = "직접 한 말 %d개"
    static let wasEmpty = "전에는 요약 없음"
    // Toasts.
    static let keptToast = "기억에 넣었어요"
    static let droppedToast = "버렸어요"
    static let settledToast = "정했어요"
    static let entityToast = "지웠어요"
    static let undoneToast = "되돌렸어요"

    /// The rows' English, by their Korean (ArisSettingsCopyMore).
    static let english: [String: String] = [
        reviewHeading: "To check",
        reviewNote: "Text that reads like an instruction to an AI isn't remembered at once: it waits here. For memories that disagree, pick the one that's right now; the other stays as an old memory.",
        keep: "Keep", drop: "Drop", rightNow: "This one's right", both: "Both are right",
        lessonMark: "Learned from work", conflictMark: "These disagree",
        peopleHeading: "People and projects",
        peopleNote: "Each person or project gets a short summary and a dated record. The summary changes only from your own words.",
        person: "Person", project: "Project", noSummary: "No summary yet", entries: "entries: %d", open: "%d still open", forget: "Remove",
        tidyTitle: "Tidy up weekly",
        tidyDesc: "Once a week while you're away, your AI polishes the people and project summaries from things you said yourself three or more times, and every change stays here.",
        undo: "Undo", changed: "Tidied", evidence: "%d things you said", wasEmpty: "no summary before",
        keptToast: "Kept in memory", droppedToast: "Dropped", settledToast: "Settled", entityToast: "Removed", undoneToast: "Undone",
        "직접 말함": "said", "추정": "inferred", "가져옴": "imported",
        ArisMemorySettingsRows.untilDay: "until %d/%d",
    ]

    private static let sourceLabels = ["said": "직접 말함", "learned": "추정", "tool": "추정", "imported": "가져옴"]

    /// Where a memory came from, in the three words the page uses.
    static func sourceLabel(_ source: String) -> String { sourceLabels[source] ?? "" }

    /// "11월 3일" for a time.
    static func day(_ seconds: Double, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: Date(timeIntervalSince1970: seconds))
        return "\(parts.month ?? 0)월 \(parts.day ?? 0)일"
    }

    /// 매주 정리하기, for the 배우기 section.
    static func tidyRow(_ s: ArisSettingsSnapshot) -> ArisSettingItem {
        ArisSettingItem(id: "memory.consolidate", icon: .symbol("calendar.badge.clock"), title: tidyTitle, desc: tidyDesc,
                        control: .toggle(.consolidateMemory, s.consolidateMemory, enabled: s.memories != nil))
    }

    /// 확인할 것, 사람과 프로젝트 and the tidy-up's changes: each only when it has something.
    static func sections(_ s: ArisSettingsSnapshot, english: Bool = ArisUILanguage.english) -> [ArisSettingSection] {
        var sections: [ArisSettingSection] = []
        var review: [ArisSettingItem] = s.memoryHeld.map { item in
            ArisSettingItem(id: "memory.held.\(item.id)", icon: .symbol("exclamationmark.shield"), title: item.text,
                            desc: [english ? item.whyEn : item.why, item.kind == "lesson" ? lessonMark : sourceLabel(item.source)].joined(separator: " · "),
                            control: .buttons([ArisSettingButton(title: drop, action: .dropHeldMemory(item.id)),
                                               ArisSettingButton(title: keep, action: .keepHeldMemory(item.id))]), indexed: false)
        }
        for conflict in s.memoryConflicts {
            for (side, last) in [(conflict.first, false), (conflict.second, true)] {
                review.append(ArisSettingItem(id: "memory.conflict.\(conflict.id).\(side.id)", icon: .symbol("arrow.left.arrow.right"), title: side.text,
                                              desc: [conflictMark, sourceLabel(side.source), day(side.said)].joined(separator: " · "),
                                              control: .buttons((last ? [ArisSettingButton(title: both, action: .settleMemoryConflict(conflict.id, keep: "both"))] : [])
                                                                + [ArisSettingButton(title: rightNow, action: .settleMemoryConflict(conflict.id, keep: side.id))]),
                                              indexed: false))
            }
        }
        if !review.isEmpty { sections.append(ArisSettingSection(id: "memory.review", heading: reviewHeading, note: reviewNote, grouped: true, rows: review)) }
        if !s.memoryEntities.isEmpty {
            let rows = s.memoryEntities.map { entity in
                ArisSettingItem(id: "memory.entity.\(entity.id)", icon: .symbol(entity.kind == "project" ? "hammer" : "person.crop.circle"),
                                title: entity.name,
                                desc: ([entity.summary.isEmpty ? noSummary : entity.summary, entity.kind == "project" ? project : person,
                                        entries.replacingOccurrences(of: "%d", with: "\(entity.entries)")]
                                       + (entity.open > 0 ? [open.replacingOccurrences(of: "%d", with: "\(entity.open)")] : [])).joined(separator: " · "),
                                control: .buttons([ArisSettingButton(title: forget, action: .forgetMemoryEntity(entity.id))]), indexed: false)
            }
            sections.append(ArisSettingSection(id: "memory.people", heading: peopleHeading, note: peopleNote, grouped: true, rows: rows))
        }
        if !s.memoryChanges.isEmpty {
            let rows = s.memoryChanges.map { change in
                ArisSettingItem(id: "memory.change.\(change.id)", icon: .symbol("wand.and.stars"), title: "\(change.name): \(change.after)",
                                desc: [changed, day(change.at), evidence.replacingOccurrences(of: "%d", with: "\(change.evidence)"),
                                       change.before.isEmpty ? wasEmpty : change.before].joined(separator: " · "),
                                control: .buttons([ArisSettingButton(title: undo, action: .undoMemoryChange(change.id))]), indexed: false)
            }
            sections.append(ArisSettingSection(id: "memory.tidied", heading: tidyTitle, grouped: true, rows: rows))
        }
        return sections
    }
}
