//
//  ArisDropLearnedSetting.swift
//  Aris
//
//  The one row in Settings › 기억 about the dropped-file chips that learn (ArisDropLearned): 배운 제안 지우기, which
//  forgets every request Aris learned from what the user asks of the files they drops. One chip is forgotten from its own
//  menu (a secondary click on it). Foundation only (tested).
//

import Foundation

/// The row in Settings › 기억 that forgets every learned suggestion.
enum ArisDropLearnedSetting {
    static let id = "memory.dropHabits"
    static let title = "배운 제안 지우기"
    static let some = "파일을 주고 세 번 이상 부탁한 일은 다음에 칩으로 먼저 보여요. 칩을 오른쪽 클릭하면 하나씩 지울 수 있어요."
    static let none = "파일을 주고 자주 한 요청을 배우면 다음에 칩으로 먼저 보여 주는데, 아직 배운 게 없어요."
    static let button = "모두 지우기"
    static let heading = "파일을 줄 때의 제안"

    /// `count`: how many shapes are remembered.
    static func section(_ count: Int) -> ArisSettingSection {
        ArisSettingSection(id: "memory.drop", heading: heading, rows: [
            ArisSettingItem(id: id, icon: .symbol("sparkles.rectangle.stack"), title: title, desc: count > 0 ? some : none,
                            control: .buttons([ArisSettingButton(title: button, action: .forgetDropHabits, kind: .danger, enabled: count > 0)])),
        ])
    }

    static let entry = ArisSettingsEntry(id: id, page: .memory, title: title, keywords: ["파일", "드롭", "칩", "제안", "배운 것", "자주 한 요청", "지우기", "suggestions"])

    /// The row's English, by its Korean (ArisSettingsCopyMore).
    static let english = [
        title: "Forget learned suggestions", button: "Forget all", heading: "Suggestions for dropped files",
        some: "A request you make three or more times after dropping files comes up first as a chip. Right-click a chip to forget just that one.",
        none: "Once Aris learns what you often ask after dropping files it comes up first as a chip; nothing is learned yet.",
    ]
}
