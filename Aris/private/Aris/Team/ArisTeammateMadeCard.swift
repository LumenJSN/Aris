//
//  ArisTeammateMadeCard.swift
//  Aris
//
//  The made card (ArisTeammateMadeView) wired to the app: the unsaved preview; 확인 saves it, 수정 saves it and opens
//  Settings on it, 취소 drops it.
//

import SwiftUI

/// The card wired to the app: the made teammate as stored now.
struct ArisTeammateMadeCard: View {
    @ObservedObject private var team = ArisTeamModel.shared
    let made: ArisTeamMade

    var body: some View {
        let mate = made.preview
        ArisTeammateMadeView(mate: mate, face: AnyView(ArisCharacterView(look: mate.look, size: 40, follows: false).environment(\.colorScheme, .dark)),
                             edit: { ArisController.shared.editMadeTeammate() },
                             confirm: {
                                 // The card goes at once; a save that failed is said in the notch (audit team-11).
                                 team.confirmMade(aris: ArisFace.current) { saved in
                                     if saved == nil { ArisController.shared.announce(title: ArisTeamCopy.madeTitle, text: ArisTeamCopy.madeFailed, kind: .problem) }
                                 }
                                 ArisController.shared.dismissAnswer()
                             },
                             cancel: {
                                 team.made = nil
                                 ArisController.shared.dismissAnswer()
                             })
            .transition(ArisConfirmCard.entry)
    }
}
