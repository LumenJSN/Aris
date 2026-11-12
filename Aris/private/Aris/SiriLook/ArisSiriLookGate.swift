//
//  ArisSiriLookGate.swift
//  Aris
//
//  When the hidden preference arisVoiceLook is read: as the notch opens or closes and as a voice state begins, never
//  mid-state, and with no rebuild or restart. A changed look is then given to every view that draws it at once.
//

import SwiftUI

/// Reads the preference at the moments the look may change, and tells every view that draws the look when it has.
@MainActor
final class ArisSiriLookGate: ObservableObject {
    static let shared = ArisSiriLookGate()

    private let latch = ArisVoiceLookLatch()
    private var pending: ArisVoiceLook?
    /// The look in force (the same as ArisSiriLookNow.look), published so the views that draw it are drawn again.
    @Published private(set) var look = ArisVoiceLook.aris

    /// Called as the notch's surface is built: the preference is read again only when the notch has opened or
    /// closed or the voice state is a new one.
    static func refresh(open: Bool, state: String) { shared.refresh(open: open, state: state) }

    /// A changed look takes effect one turn of the run loop later, outside the view update that noticed it, and
    /// for every view at once: the first live run drew the surface in the new look and the band, your words and
    /// the tags in the old one, because they had been built a moment before the surface read the preference.
    private func refresh(open: Bool, state: String) {
        let next = latch.look(entering: ArisSiriLookMoment.name(open: open, state: state))
        guard next != (pending ?? ArisSiriLookNow.look) else { return }
        pending = next
        DispatchQueue.main.async { [self] in
            guard pending == next else { return }
            pending = nil
            ArisSiriLookNow.look = next
            look = next
        }
    }
}
