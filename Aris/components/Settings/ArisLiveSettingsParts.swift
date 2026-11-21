//
//  ArisLiveSettingsParts.swift
//  Aris
//
//  What each part of option A's long pages draws under its title (ArisSettingsLongPage): the AI parts from the AI
//  view's own state, 데이터 · 개인정보 with the saved keys after its rows, and every other part as the page view draws
//  sections. The views other branches build have their slots in ArisLiveSlots.
//

import SwiftUI

struct ArisLivePart: View {
    let part: ArisPartSections
    @ObservedObject var ai: ArisAIServicesModel
    /// The hearing engine's status line (ArisSettingsBuilder.engineLine).
    var engineLine: String?

    var body: some View {
        switch part.id {
        case "talk.ai":
            ArisAIThinkPart(model: ai, sections: part.sections, models: ArisLiveSlots.models)
        case "talk.hear":
            ArisAIJobPart(card: ai.page.hear, model: ai, tag: "ai.hear", rows: ownRows, lines: [engineLine, note].compactMap { $0 })
        case "talk.speak":
            ArisAIJobPart(card: ai.page.speak, model: ai, tag: "ai.speak", rows: ownRows, lines: [ai.page.voiceLine, note].compactMap { $0 })
        case "app.data":
            VStack(alignment: .leading, spacing: 0) {
                ArisSettingsPageView(sections: part.sections)
                // Under the builder's 저장된 키 title (a section with no rows of its own: the AI view draws the keys).
                if ai.keyRows.count(saved: ai.page.savedKeys) > 0 {
                    ArisAISavedKeys(keys: ai.page.savedKeys, model: ai).arisFlash("ai.savedKeys").padding(.top, ArisSettingsMetrics.headingGap)
                }
            }
        default:
            ArisSettingsPageView(sections: part.sections)
        }
    }

    /// The part's rows the AI card doesn't draw itself (쓰는 언어, 말하기 속도).
    private var ownRows: [ArisSettingItem] {
        part.sections.flatMap(\.rows).filter { if case .custom = $0.control { false } else { true } }
    }

    private var note: String? { part.sections.first?.note }
}
