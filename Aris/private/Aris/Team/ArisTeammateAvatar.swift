//
//  ArisTeammateAvatar.swift
//  Aris
//
//  A teammate's face wherever the app shows who did something (the 한 일 tab's strip and headings): the character the user
//  picked for them in the 팀원 settings (ArisTeamModel; Aris is the star; anyone not in the list a character fixed by
//  their name).
//

import SwiftUI

struct ArisTeammateAvatar: View {
    let name: String
    /// The teammate's id when its rows carry one: the face follows it through a rename.
    var id: String?
    let size: CGFloat
    @ObservedObject private var team = ArisTeamModel.shared

    var body: some View {
        ArisCharacterView(look: team.look(teammateId: id, name: name), size: size, label: name)
    }
}
