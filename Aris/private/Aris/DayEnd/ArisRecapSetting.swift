//
//  ArisRecapSetting.swift
//  Aris
//
//  The day in review's one switch (F5, ArisRecapSwitch): the day-end summary said in four or five sentences, with what
//  Aris did, what finished and what the coding sessions wait for, and "뭐 남았어" answered from the same card. Off until
//  The user has heard it (the contract's rule for a new feature). Its row sits under the day-end chip's on 조용히 · 알림, and
//  "하루 정리", "남은 일" or "recap" finds it. Foundation only.
//

import Foundation

enum ArisRecapSetting {
    static let id = "aris.recap"

    /// The row's words, written in Korean as every row is (Settings.xcstrings has their English).
    static let title = "하루 정리를 자세히 말하기"
    static let detail = "“오늘 뭐 했어?”에 네다섯 문장으로 답해요: 끝낸 일, Aris가 한 일, 끝난 작업, 기다리는 것, 내일. “뭐 남았어?”도 알아들어요. 목록은 그대로예요."
    static let keywords = "하루 정리, 남은 일, 뭐 남았어, 한 일, 요약, 리캡, 코딩 세션, recap, day in review, what's left"

    static func row(_ on: Bool) -> ArisSettingItem {
        ArisSettingItem(id: id, icon: .symbol("list-checks"), title: title, desc: detail, control: .toggle(.recap, on))
    }

    static let entry = ArisSettingsEntry(id: id, page: .aris, title: title, keywords: keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
}
