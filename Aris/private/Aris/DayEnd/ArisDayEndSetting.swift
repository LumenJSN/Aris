//
//  ArisDayEndSetting.swift
//  Aris
//
//  The one setting of the day-end summary (ArisDayEnd): whether the evening chip is offered at all. On by default; the
//  summary itself can always be asked for. Its row sits with the other alerts on the 대화 page, and a search for
//  "오늘 정리" or "하루 마감" finds it. The stored preference is `arisDayEndOffer` (ArisDayEndModel). Foundation only.
//

import Foundation

enum ArisDayEndSetting {
    static let id = "aris.dayEnd"

    /// The row's words, written in Korean as every row of the settings pages is (the settings catalog has their English).
    static let title = "저녁에 오늘 정리 알려주기"
    static let detail = "저녁 6시가 지나 Mac을 쓰고 있으면 노치 아래에 작은 칩으로 한 번 알려줘요. 소리는 내지 않고, 전할 게 없는 날은 건너뛰어요. “오늘 정리해 줘”라고 하면 언제든 볼 수 있어요."
    static let keywords = "오늘 정리, 하루 마감, 하루 정리, 저녁, 요약, 한 일, 확인 대기, 내일, 데이 엔드, wrap up"

    static func row(_ on: Bool) -> ArisSettingItem {
        ArisSettingItem(id: id, icon: .symbol("moon.stars"), title: title, desc: detail, control: .toggle(.dayEndOffer, on))
    }

    static let entry = ArisSettingsEntry(id: id, page: .aris, title: title, keywords: keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
}
