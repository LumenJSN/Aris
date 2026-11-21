//
//  ArisDecisionProviders.swift
//  Shared/Core (Aris, tests)
//
//  The decision models Aris can ask (설정 › AI 서비스 › 짧은 명령 빨리 알아듣기), each with the endpoint its own
//  documentation gives (read 2026-11-19; `docs` is the page). Aris is bring-your-own-key: each provider has its own key,
//  kept in the Keychain under `keyName`, sent only in a header to that provider's address and never in a URL or a log.
//  A provider whose API could not be confirmed on its own pages is not here. Pure.
//

import Foundation

struct ArisDecisionProvider: Equatable, Sendable {
    enum Address: Equatable, Sendable {
        /// One endpoint for everybody.
        case fixed(String)
        /// Cloudflare Workers AI: the account's id and the model are in the path.
        case cloudflare
        /// The owner's own resource (https only), with this path after it.
        case resource(path: String)
        /// The owner's own server speaking System One: https anywhere, plain http on this Mac or its network.
        case custom
    }

    enum Auth: Equatable, Sendable { case bearer, apiKey }

    let id: String
    let name: String
    /// The Keychain account of its key (ArisKeyFile).
    let keyName: String
    let wire: ArisDecisionWire
    let address: Address
    var auth = Auth.bearer
    /// Asked when none is typed; "": one must be typed (a deployment's or a server's own name).
    let model: String
    /// The most options one question may have there.
    var maxOptions = 255
    /// USD per million input tokens for `model`, where the provider's own page says it (output is free everywhere).
    var inputPerMillion: Double?
    var needsKey = true
    let docs: String
}

enum ArisDecisionProviders {
    /// In the order 자동 looks for a saved key.
    static let all: [ArisDecisionProvider] = [
        ArisDecisionProvider(id: "jev", name: "Jev", keyName: "typesafe-key", wire: .systemOne, address: .fixed("https://api.typesafe.ai/v1/systemone"),
                             model: "jev-1.14.0", inputPerMillion: 0.042, docs: "https://docs.typesafe.ai/models"),
        ArisDecisionProvider(id: "openai", name: "OpenAI Decisions", keyName: "openai-decisions-key", wire: .openAI, address: .fixed("https://api.openai.com/v1/decisions"),
                             model: "gpt-6-luna", inputPerMillion: 0.10, docs: "https://developers.openai.com/api/docs/guides/decisions"),
        ArisDecisionProvider(id: "openrouter", name: "OpenRouter", keyName: "openrouter-decisions-key", wire: .systemOne,
                             address: .fixed("https://openrouter.ai/api/alpha/decisions"), model: "typesafe/jev-1.14",
                             docs: "https://openrouter.ai/docs/api/api-reference/alphadecisions/submit-a-decisions-request"),
        ArisDecisionProvider(id: "cloudflare", name: "Cloudflare Clef", keyName: "cloudflare-ai-key", wire: .systemOne, address: .cloudflare,
                             model: "clef-flash", inputPerMillion: 0.038, docs: "https://developers.cloudflare.com/workers-ai/models/clef-flash/"),
        ArisDecisionProvider(id: "perplexity", name: "Perplexity Decider", keyName: "perplexity-decider-key", wire: .systemOne,
                             address: .fixed("https://api.perplexity.ai/v1/decisions"), model: "pplx-decider-flash-v1.3", inputPerMillion: 0.01,
                             docs: "https://docs.perplexity.ai/docs/decisions/quickstart"),
        ArisDecisionProvider(id: "inception", name: "Mercury Decide", keyName: "inception-key", wire: .systemOne,
                             address: .fixed("https://api.inceptionlabs.ai/v1/decisions"), model: "mercury-decide", inputPerMillion: 0.02,
                             docs: "https://docs.inceptionlabs.ai/capabilities/decisions"),
        ArisDecisionProvider(id: "upstage", name: "Solar Decide", keyName: "upstage-key", wire: .systemOne, address: .fixed("https://api.upstage.ai/v1/systemone"),
                             model: "solar-decide", maxOptions: 26, docs: "https://console.upstage.ai/api/systemone"),
        ArisDecisionProvider(id: "liquid", name: "Liquid d1", keyName: "liquid-key", wire: .systemOne, address: .fixed("https://api.liquid.ai/decisions/v1/systemone"),
                             model: "d1.2", docs: "https://docs.liquid.ai/lfm/models/d1"),
        ArisDecisionProvider(id: "foundry", name: "Microsoft Decision", keyName: "foundry-decision-key", wire: .systemOne,
                             address: .resource(path: "/providers/microsoft/v1/systemone"), auth: .apiKey, model: "",
                             docs: "https://learn.microsoft.com/en-us/azure/foundry/foundry-models/how-to/use-foundry-models-microsoft-decision"),
        ArisDecisionProvider(id: "custom", name: "Custom", keyName: "custom-decision-key", wire: .systemOne, address: .custom, model: "", needsKey: false,
                             docs: "https://docs.typesafe.ai/primitives/choice"),
    ]

    static func provider(_ id: String) -> ArisDecisionProvider? { all.first { $0.id == id } }

    // MARK: - The stored choice

    static let storedPrefix = "decide:"

    static func stored(_ id: String) -> String { storedPrefix + id }

    /// The provider a stored choice names ("decide:openrouter"), when it is one of these.
    static func id(stored: String?) -> String? {
        guard let stored, stored.hasPrefix(storedPrefix) else { return nil }
        return provider(String(stored.dropFirst(storedPrefix.count)))?.id
    }

    // MARK: - What the owner typed for one provider

    struct Setup: Equatable, Sendable {
        /// The model's id (OpenRouter's "cloudflare/clef-flash", a deployment's name); nil: the provider's own.
        var model: String?
        /// Cloudflare's account id, Foundry's resource endpoint, or a custom server's base URL.
        var address: String?

        init(model: String? = nil, address: String? = nil) {
            self.model = model
            self.address = address
        }
    }

    static let maxModel = 128

    /// The model asked: what was typed, else the provider's own; nil when there is none or it is no model id.
    static func model(_ provider: ArisDecisionProvider, setup: Setup) -> String? {
        let typed = setup.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = typed.isEmpty ? provider.model : typed
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:/@~-")
        guard !model.isEmpty, model.count <= maxModel, model.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        if provider.address == .cloudflare, !["clef", "clef-flash"].contains(model) { return nil }
        return model
    }

    /// Where the request goes; nil when what was typed can't be used.
    static func url(_ provider: ArisDecisionProvider, setup: Setup) -> URL? {
        let typed = setup.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch provider.address {
        case .fixed(let address): return URL(string: address)
        case .cloudflare:
            guard let model = model(provider, setup: setup), (16...64).contains(typed.count),
                  typed.unicodeScalars.allSatisfy(CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains) else { return nil }
            return URL(string: "https://api.cloudflare.com/client/v4/accounts/\(typed)/ai/run/@cf/cloudflare/\(model)")
        case .resource(let path):
            guard let base = base(typed), base.scheme == "https" else { return nil }
            return URL(string: base.absoluteString + path)
        case .custom:
            guard let base = base(typed), base.scheme == "https" || isLocal(base.host ?? "") else { return nil }
            let whole = base.path.hasSuffix("/systemone") || base.path.hasSuffix("/decisions")
            return whole ? base : URL(string: base.absoluteString + "/v1/systemone")
        }
    }

    /// A typed base address without its last slash: http or https, a host, and no credentials, query or fragment.
    private static func base(_ typed: String) -> URL? {
        var text = typed
        while text.hasSuffix("/") { text.removeLast() }
        guard let parts = URLComponents(string: text), let scheme = parts.scheme, ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return nil }
        return parts.url
    }

    /// This Mac or its own network: where a key or the words may go over plain http.
    static func isLocal(_ host: String) -> Bool {
        let host = host.lowercased()
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4, host.split(separator: ".").count == 4 else { return false }
        return parts[0] == 127 || parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 169 && parts[1] == 254)
    }

    /// Whether the provider can be asked with what is saved: its key (where it needs one), its address and its model.
    static func ready(_ provider: ArisDecisionProvider, setup: Setup, hasKey: Bool) -> Bool {
        (hasKey || !provider.needsKey) && url(provider, setup: setup) != nil && model(provider, setup: setup) != nil
    }

    // MARK: - The request

    /// One request, or nil when the key, the address or the model is missing. `keeping`: options that stay when the
    /// provider takes fewer than were asked (ArisDecisionAsk.capped).
    static func request(_ provider: ArisDecisionProvider, setup: Setup, key: String?, ask: ArisDecisionAsk, timeout: TimeInterval,
                        keeping: Set<String> = []) -> URLRequest? {
        let key = key.flatMap { $0.isEmpty ? nil : $0 }
        guard key != nil || !provider.needsKey, let url = url(provider, setup: setup), let model = model(provider, setup: setup),
              let body = try? JSONSerialization.data(withJSONObject: provider.wire.body(ask.capped(provider.maxOptions, keeping: keeping), model: model)) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key {
            switch provider.auth {
            case .bearer: request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            case .apiKey: request.setValue(key, forHTTPHeaderField: "api-key")
            }
        }
        return request
    }

    /// `text` without the key, for anything that is logged.
    static func redacted(_ text: String, key: String?) -> String {
        guard let key, !key.isEmpty else { return text }
        return text.replacingOccurrences(of: key, with: "***")
    }
}
