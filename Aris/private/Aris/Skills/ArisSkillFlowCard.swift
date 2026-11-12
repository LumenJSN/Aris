//
//  ArisSkillFlowCard.swift
//  Aris
//
//  The notch's skill flow wired to ArisSkillsModel: the status it draws and what its buttons do. While it's on screen
//  the model's polls say the job was seen (else a job that ends goes to the inbox).
//

import SwiftUI

struct ArisSkillFlowCard: View {
    @ObservedObject private var skills = ArisSkillsModel.shared
    let flow: ArisSkillNotchFlow
    var budget: CGFloat = 440

    var body: some View {
        ArisSkillFlowView(status: skills.status, flow: flow, budget: budget, actions: ArisSkillFlowActions(
            later: { skills.notchLater() }, turnOn: { skills.notchTurnOn() }, retry: { skills.retry() },
            decide: { skills.decide($0, accept: $1) }, go: { skills.notchGo($0) },
            shown: { visible in
                skills.notchVisible = visible
                if visible { skills.refresh() }
            }))
        .transition(ArisConfirmCard.entry)
    }
}
