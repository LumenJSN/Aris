//
//  ClaudeUsagePreferences.swift
//  Aris
//
//  Where 설정 › 대화 › Claude Code keeps its picks: what the ear's ring shows, and the API key's daily budget (on,
//  and the amount). Read by the ear (ClaudeLiveActivity), the tab and the settings window.
//

import Defaults
import SwiftUI

extension Defaults.Keys {
    static let claudeRingMode = Key<String>(ClaudeRingMode.defaultsKey, default: ClaudeRingMode.fiveHour.rawValue)
    static let claudeBudgetOn = Key<Bool>(ClaudeBudget.onKey, default: true)
    static let claudeBudget = Key<Double>(ClaudeBudget.amountKey, default: ClaudeBudget.fallback)
}

/// The ring's reading from the store and the saved picks (the views hold them as @Default, so a change redraws).
@MainActor
enum ClaudeRingNow {
    static func reading(_ store: ClaudeStore, mode: String, budgetOn: Bool, budget: Double, now: Date = Date()) -> ClaudeRingReading {
        ClaudeRingReading.make(plan: store.spend.plan, mode: ClaudeRingMode(stored: mode), usage: store.usage, spent: store.spentToday(at: now),
                               budget: budgetOn ? ClaudeBudget.stored(budget) : nil, now: now)
    }
}

/// The settings window's budget row on the saved budget (ClaudeBudgetRowView in ArisClaudeBudgetRow.swift draws it).
struct ClaudeBudgetRow: View {
    @Default(.claudeBudgetOn) private var on
    @Default(.claudeBudget) private var amount
    let title: String

    var body: some View {
        ClaudeBudgetRowView(title: title, on: on, amount: ClaudeBudget.stored(amount), toggle: { on.toggle() }, save: { amount = $0 })
    }
}
