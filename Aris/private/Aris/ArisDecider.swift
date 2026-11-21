//
//  ArisDecider.swift
//  Aris
//
//  The seam every decision model is asked through (jv-decision): typed questions about some words in, each
//  question's choice and confidence out, in the shape Jev answers in, so the router and the card reader read any
//  provider's reply as they read Jev's. As with Jev, the app holds the key (the Keychain, ArisKeyFile) and makes the
//  call itself; the key goes only into the request's header and is taken out of anything logged.
//
//  Jev is the first implementation and is asked exactly as before: the same request, its reply handed on as it came.
//  Every other provider's reply is read strictly (ArisDecisionWire.answers) and anything else is thrown, so the turn
//  goes on with the keyword rules as when Jev fails. Foundation only (tested).
//

import Foundation

protocol ArisDecider: Sendable {
    /// The reply as System One gives it: {"answers": {question: {"choice", "confidence"}}}. Throws when none came.
    func decide(_ ask: ArisDecisionAsk, timeout: TimeInterval) async throws -> Data
}

struct ArisHTTPDecider: ArisDecider {
    let provider: ArisDecisionProvider
    var setup = ArisDecisionProviders.Setup()
    let key: String?
    /// Options that stay when the provider takes fewer than were asked.
    var keeping: Set<String> = ["none"]

    /// Who answers for `provider` in the log and in errors ("TypeSafe", as before, for Jev).
    static func name(_ provider: ArisDecisionProvider) -> String { provider.id == "jev" ? "TypeSafe" : provider.name }

    func decide(_ ask: ArisDecisionAsk, timeout: TimeInterval) async throws -> Data {
        guard let request = ArisDecisionProviders.request(provider, setup: setup, key: key, ask: ask, timeout: timeout, keeping: keeping) else {
            throw ArisRouter.Failure(message: "\(Self.name(provider)) can't be asked: its key, address or model is missing")
        }
        let (data, response) = try await ArisNoStore.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // What the answer says about Jev's key, for the settings' status line (ArisRouterKeyHealth).
        if provider.id == "jev" { ArisRouterKeyHealth.note(status: status == 0 ? nil : status) }
        return try Self.read(provider, data: data, status: status, ask: ask.capped(provider.maxOptions, keeping: keeping), key: key)
    }

    /// One answered request as the reply handed on, or the failure thrown.
    static func read(_ provider: ArisDecisionProvider, data: Data, status: Int, ask: ArisDecisionAsk, key: String?) throws -> Data {
        guard status == 200 else {
            let said = ArisProviderWords.loggable(ArisDecisionProviders.redacted(String(decoding: data.prefix(300), as: UTF8.self), key: key))
            throw ArisRouter.Failure(message: "\(name(provider)) answered \(status): \(said)", status: status)
        }
        // Jev's own reply is read by what always read it.
        if provider.id == "jev" { return data }
        guard let answers = provider.wire.answers(data, for: ask) else { throw ArisRouter.Failure(message: "\(name(provider))'s reply didn't make sense") }
        return ArisDecisionWire.systemOneReply(answers)
    }
}
