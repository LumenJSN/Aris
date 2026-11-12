//
//  ArisOnboardingGuide+Brain.swift
//  Aris
//
//  AI 고르기's 저장 (the owner's pick 3-A): the pasted key goes where Settings › AI services sends one (to the helper, once;
//  it checks the key's shape and keeps it in the Keychain, and the provider becomes the one that answers), then the
//  helper tries it the way Settings does after a save. The trying can take a while, so it never holds the page: the
//  row shows the key as saved at once, and only a key that did not answer is said, with the field open again. Kept on
//  the guide so what the check finds is still said after the page's own views have changed.
//

import Foundation

extension ArisOnboardingGuide {
    /// Saves `key` for the provider `id`. Nil when it was saved; else what the form says (the helper's refusal).
    func saveBrainKey(provider id: String, key: String) async -> String? {
        if let refused = await ArisAgentClient.saveAPIBrain(id: id, key: key, quick: nil, strong: nil, baseURL: nil) {
            return ArisSetupWords.keyRefused(refused)
        }
        brainKeyOpen = false
        brainKeyTrouble = nil
        // What the last press of 다시 확인 found is no longer what is true.
        brainChecked = nil
        await ArisBrainSetup.shared.refresh()
        // The key was just given so that it answers.
        if ArisBrainSetup.shared.ready?[.api] == true { ArisBrainSetup.shared.choose(.api) }
        Task { [weak self] in
            // The helper's own short check (one greeting, one tool call that is never run), as Settings runs after 저장.
            let result = await ArisAgentClient.testAPIBrain(id, model: nil)
            // The key counts as an AI from its first answer (ArisBrainChoice.needsCheck): what the check found is read back.
            await ArisBrainSetup.shared.refresh()
            if ArisBrainSetup.shared.ready?[.api] == true { ArisBrainSetup.shared.choose(.api) }
            guard let self, self.showing, let said = ArisOnboardingBrainRows.keyTestTrouble(ok: result.ok, message: result.message) else { return }
            self.brainKeyTrouble = ArisSetupWords.keyNotWorking(said)
            self.brainKeyOpen = true
        }
        return nil
    }
}
