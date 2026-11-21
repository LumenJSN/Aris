//
//  ArisAIDecisionModels.swift
//  Aris
//
//  The decision models in 짧은 명령 빨리 알아듣기's dropdown and the lines under it (jv-decision): each provider of
//  ArisDecisionProviders with what it costs, "키 필요" until its own key is saved, and for the one chosen its key line,
//  its model id and (Cloudflare's account, Foundry's resource, a custom server) its address. Pure (tested).
//

import Foundation

/// The decision model chosen, as the card shows it under the dropdown.
struct ArisAIDecisionLine: Equatable, Sendable {
    struct Field: Equatable, Sendable {
        let label: String
        let value: String
        let hint: String
    }

    let id: String
    let name: String
    /// Its key: none, saved (masked), or being typed.
    let key: ArisAIJevLine
    /// A server of the owner's own may need no key.
    let keyOptional: Bool
    let model: Field
    let address: Field?
}

extension ArisAIServicesBuilder {
    static let decisionGroup = "판단 모델"
    static let rulesTitle = "키워드 규칙"
    static let rulesSubtitle = "무료 · 말이 Mac 밖으로 나가지 않아요"
    static let autoSubtitle = routerAutoLine
    static let unsetWord = "설정 필요"

    static func decisionName(_ id: String) -> String {
        guard let provider = ArisDecisionProviders.provider(id) else { return id }
        return provider.id == "custom" ? "Custom (Jev-compatible)" : provider.name
    }

    static func decisionReady(_ id: String, _ state: ArisAIServicesState) -> Bool {
        guard let provider = ArisDecisionProviders.provider(id) else { return false }
        return ArisDecisionProviders.ready(provider, setup: state.decisionSetup[id] ?? .init(), hasKey: state.decisionKeys[id] != nil)
    }

    /// "키 필요" without its key, "설정 필요" with the key but no usable address or model, nil when it can be asked.
    static func decisionTail(_ id: String, _ state: ArisAIServicesState) -> String? {
        guard let provider = ArisDecisionProviders.provider(id), !decisionReady(id, state) else { return nil }
        return provider.needsKey && state.decisionKeys[id] == nil ? ArisAILack.key.word : unsetWord
    }

    /// Why a chosen decision model is not asked, as the line says it; nil for any other choice.
    static func decisionLack(_ choice: ArisRouterModels.Choice, _ state: ArisAIServicesState) -> RouterPick? {
        guard case .decision(let id) = choice, let tail = decisionTail(id, state) else { return nil }
        return tail == unsetWord ? .unset(decisionName(id)) : .missing(decisionName(id))
    }

    static func decisionCost(_ provider: ArisDecisionProvider) -> String {
        if provider.id == "custom" { return "직접 띄운 서버 · Jev와 같은 API(/v1/systemone)" }
        return provider.inputPerMillion.map { "한 달 약 \(ArisRouterModels.dollars(ArisRouterModels.monthly(input: $0, output: 0)))" } ?? "그 서비스 요금으로"
    }

    static func decisionLine(_ provider: ArisDecisionProvider, model: String) -> String {
        // The price Aris knows is the provider's own model's; another model typed in costs what its page says.
        let cost = model == provider.model || provider.id == "custom" ? decisionCost(provider) : "그 서비스 요금으로"
        return ["\(decisionName(provider.id)) \(model)", cost, routerSees].joined(separator: " · ")
    }

    /// Every decision model but Jev (which keeps its own item), in the list's order.
    static func decisionItems(_ state: ArisAIServicesState, chosen: String) -> [ArisAIMenu.Entry] {
        ArisDecisionProviders.all.filter { $0.id != "jev" }.map { provider in
            let id = ArisDecisionProviders.stored(provider.id)
            let model = ArisDecisionProviders.model(provider, setup: state.decisionSetup[provider.id] ?? .init())
            return .item(ArisAIMenuItem(id: id, title: decisionName(provider.id), subtitle: decisionCost(provider), code: model,
                                        tail: decisionTail(provider.id, state), checked: chosen == id))
        }
    }

    /// The chosen decision model's key line and fields; nil unless one (other than Jev) is chosen.
    static func decisionFields(_ choice: ArisRouterModels.Choice, _ state: ArisAIServicesState) -> ArisAIDecisionLine? {
        guard case .decision(let id) = choice, let provider = ArisDecisionProviders.provider(id) else { return nil }
        let setup = state.decisionSetup[id] ?? .init()
        let key: ArisAIJevLine
        if state.ui.decisionOpen == id { key = .editing(error: state.ui.decisionError) } else { key = state.decisionKeys[id].map { .on(masked: $0) } ?? .off }
        let model: ArisAIDecisionLine.Field
        switch provider.address {
        case .resource: model = .init(label: "배포 이름", value: setup.model ?? "", hint: "pi-decision-1.1")
        case .custom: model = .init(label: "모델 이름", value: setup.model ?? "", hint: "kev-4b")
        case .fixed, .cloudflare: model = .init(label: "모델 ID", value: setup.model ?? "", hint: provider.model)
        }
        let address: ArisAIDecisionLine.Field?
        switch provider.address {
        case .fixed: address = nil
        case .cloudflare: address = .init(label: "계정 ID", value: setup.address ?? "", hint: "Cloudflare Account ID")
        case .resource: address = .init(label: "리소스 주소", value: setup.address ?? "", hint: "https://….services.ai.azure.com")
        case .custom: address = .init(label: "서버 주소", value: setup.address ?? "", hint: "http://localhost:8080")
        }
        return ArisAIDecisionLine(id: id, name: decisionName(id), key: key, keyOptional: !provider.needsKey, model: model, address: address)
    }
}
