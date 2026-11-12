//
//  ArisDropChipsView.swift
//  Aris
//
//  The chips over the composer once files are dropped on Aris, under the files' own name chips: what the files that
//  wait can have done to them (ArisDropChips, from what ArisDropModel found out at the drop), drawn by
//  ArisDropChipRows; a press goes to the model, which starts the turn.
//

import SwiftUI

struct ArisDropChipsView: View {
    @ObservedObject private var attachments = ArisAttachments.shared
    @ObservedObject private var drop = ArisDropModel.shared

    var body: some View {
        ArisDropChipRows(offer: ArisDropChips.offer(drop.files(attachments.files), english: ArisUIWords.english), notice: drop.notice,
                         learned: drop.learnedChips(attachments.files), press: { drop.press($0) },
                         pressLearned: { drop.press($0) }, forget: { drop.forget($0) })
    }
}
