//
//  ArisDeciders.swift
//  Aris
//
//  The decision models as they are set up on this Mac: each one's key from the Keychain (ArisKeyFile), and the model
//  id and address typed in 설정 › AI 서비스 › 짧은 명령 빨리 알아듣기 (preferences, never secrets).
//

import Foundation

enum ArisDeciders {
    static func modelKey(_ id: String) -> String { "arisDecisionModel." + id }
    static func addressKey(_ id: String) -> String { "arisDecisionAddress." + id }

    static func setup(_ id: String, _ defaults: UserDefaults = .standard) -> ArisDecisionProviders.Setup {
        ArisDecisionProviders.Setup(model: defaults.string(forKey: modelKey(id)), address: defaults.string(forKey: addressKey(id)))
    }

    /// Whether `id` can be asked now: its key is saved (where it needs one) and its address and model are usable.
    static func ready(_ id: String) -> Bool {
        guard let provider = ArisDecisionProviders.provider(id) else { return false }
        return ArisDecisionProviders.ready(provider, setup: setup(id), hasKey: ArisKeyFile.load(provider.keyName) != nil)
    }

    static func decider(_ id: String) -> ArisDecider? {
        guard let provider = ArisDecisionProviders.provider(id) else { return nil }
        return ArisHTTPDecider(provider: provider, setup: setup(id), key: ArisKeyFile.load(provider.keyName), keeping: [ArisRouter.noApp])
    }

    /// Who the stored choice asks this turn.
    static func route() -> ArisRouterModels.Route {
        ArisRouterModels.route(ArisRouterModels.choice(UserDefaults.standard.string(forKey: ArisRouterModels.preferenceKey)),
                               jevKey: ArisKeyFile.load(ArisRouter.keyName) != nil, ready: ready)
    }
}
