//
//  deepseek-tests.swift
//  DeepSeek's current models (2026-11-26): its API lists only deepseek-flash and deepseek-v4-pro, both thinking by
//  default, and in thinking mode a request with tools is refused (HTTP 400) unless every earlier answer's
//  reasoning_content comes back with it. deepseek-chat still answers (by deepseek-flash, no thinking) but is no longer
//  listed. The preset names the two, Aris asks DeepSeek with thinking off (only DeepSeek), a profile saved with
//  deepseek-chat or deepseek-reasoner is read as deepseek-flash, and no image goes to DeepSeek (deepseek-v4-pro can't
//  see). A connection the user added on DeepSeek's own host (api.deepseek.com exactly) is asked without thinking too.
//

import Foundation

private func deepseekBody(_ preset: String, base: String = "https://api.example.com/v1", entries: [ArisAPIEntry], functions: [ArisAPIFunction]) -> [String: Any] {
    let spec = ArisAPIRequestSpec(dialect: .openAIChat, base: base, model: "m-1", key: "k", headers: [:], system: "s",
                                  entries: entries, functions: functions, preset: preset, strictOrigin: false)
    return ArisAPIDialects.request(spec).flatMap { $0.httpBody }.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
}

private func deepseekPresetTests() {
    let preset = ArisAPIPreset.named("deepseek")!
    check(preset.quick == "deepseek-flash" && preset.strong == "deepseek-v4-pro" && preset.curated == ["deepseek-flash", "deepseek-v4-pro"]
          && preset.dialect == .openAIChat && preset.baseURL == "https://api.deepseek.com/v1" && !preset.vision,
          "deepseek preset: quick deepseek-flash, strong deepseek-v4-pro, both curated, OpenAI dialect, no images")
    check(!ArisAPIPreset.all.contains { $0.quick == "deepseek-chat" || $0.strong == "deepseek-chat" || $0.curated.contains("deepseek-chat") },
          "deepseek preset: the unlisted deepseek-chat is offered nowhere")
}

private func deepseekThinkingTests() {
    let functions = ArisAPICatalog.functions(sealed: false)
    let call = ArisAPIToolCall(id: "call_1", name: "timer", arguments: #"{"minutes":5}"#)
    let first: [ArisAPIEntry] = [.user(text: "타이머 5분", images: [])]
    let second: [ArisAPIEntry] = first + [.assistant(text: "", calls: [call], echo: nil), .tool(id: "call_1", name: "timer", text: "$ aris timer 5\n[exit 0]")]
    for entries in [first, second] {
        let body = deepseekBody("deepseek", entries: entries, functions: functions)
        check((body["thinking"] as? [String: Any])?["type"] as? String == "disabled" && body["tools"] != nil && body["reasoning_effort"] == nil,
              "deepseek thinking: a DeepSeek request with tools asks with thinking off (round \(entries.count == 1 ? 1 : 2))")
    }
    check((deepseekBody("deepseek", entries: first, functions: [])["thinking"] as? [String: Any])?["type"] as? String == "disabled",
          "deepseek thinking: off without tools too (a one-shot question, the read judge)")
    for other in ["openai", "openrouter", "groq", "xai", "mistral", "ollama", "lmstudio", "my-connection"] {
        check(deepseekBody(other, entries: second, functions: functions)["thinking"] == nil,
              "deepseek thinking: \(other) never gets DeepSeek's thinking field")
    }

    // The router's own body (no stream, JSON object mode).
    func routerBody(_ id: String) -> [String: Any] {
        let preset = ArisAPIPreset.named(id)!
        return ArisAPIRouterCall.body(preset: preset, model: preset.quick.isEmpty ? "m" : preset.quick, system: "s", user: "u", schema: ["type": "object"])
    }
    let router = routerBody("deepseek")
    check((router["thinking"] as? [String: Any])?["type"] as? String == "disabled" && (router["response_format"] as? [String: Any])?["type"] as? String == "json_object"
          && router["model"] as? String == "deepseek-flash",
          "deepseek thinking: the router asks deepseek-flash for a JSON object with thinking off")
    check(["openai", "openrouter", "groq", "xai", "mistral", "ollama"].allSatisfy { routerBody($0)["thinking"] == nil },
          "deepseek thinking: no other OpenAI-compatible router request carries it")
}

private func deepseekMigrationTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-deepseek-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let signing = ArisMCPMemorySecrets()
    let store = ArisAPIStore(file: folder.appendingPathComponent("api-brains.json"), signing: signing)
    let old = ArisAPIProfile(id: "deepseek", quick: "deepseek-chat", strong: "deepseek-reasoner", baseURL: nil, vision: nil, tools: nil, router: "deepseek-chat")
    let groq = ArisAPIProfile(id: "groq", quick: "deepseek-chat", strong: "openai/gpt-oss-120b", baseURL: nil, vision: nil, tools: nil)
    check(store.update { var next = $0.saving(old).saving(groq); next.active = "deepseek"; return next } == nil, "deepseek migration: an old file is written")

    let loaded = store.load()
    let profile = loaded.profile("deepseek")
    check(profile?.quick == "deepseek-flash" && profile?.strong == "deepseek-flash" && profile?.router == "deepseek-flash" && !store.tampered
          && loaded.active == "deepseek",
          "deepseek migration: a profile saved with deepseek-chat or deepseek-reasoner is read as deepseek-flash (quick, strong, router), still signed and active")
    check(loaded.profile("groq")?.quick == "deepseek-chat", "deepseek migration: another provider's model of the same name is left alone")
    let reasoner = ArisAPIProfile(id: "openrouter", quick: "deepseek-reasoner", strong: "deepseek-reasoner", baseURL: nil, vision: nil, tools: nil)
    check(reasoner.current == reasoner, "deepseek migration: deepseek-reasoner on another provider is left alone")
    check(ArisAPIHelper.resolve("deepseek", store: store)?.quick == "deepseek-flash" && ArisAPIActive.profile(store: store)?.strong == "deepseek-flash",
          "deepseek migration: the helper and the active profile get the new name")

    // The next save writes the new name (the file is rewritten from what was read).
    _ = store.update { $0 }
    let raw = (try? String(contentsOf: store.file, encoding: .utf8)) ?? ""
    check(!raw.contains("deepseek-reasoner") && !raw.contains(#""quick":"deepseek-chat","router""#) && raw.contains("deepseek-flash") && !store.tampered && store.load().profile("deepseek")?.quick == "deepseek-flash",
          "deepseek migration: saving again writes deepseek-flash, and the file still checks")

    let kept = ArisAPIProfile(id: "deepseek", quick: "deepseek-flash", strong: "deepseek-v4-pro", baseURL: nil, vision: nil, tools: nil)
    check(kept.current == kept, "deepseek migration: the current names are kept as they are")
    // What the old name gets is what it got before: deepseek-flash with thinking off.
    let body = deepseekBody("deepseek", entries: [.user(text: "hi", images: [])], functions: [])
    check((body["thinking"] as? [String: Any])?["type"] as? String == "disabled", "deepseek migration: the migrated model is asked without thinking, as deepseek-chat answered")
}

private func deepseekVisionTests() {
    let preset = ArisAPIPreset.named("deepseek")!
    let profile = ArisAPIProfile(id: "deepseek", quick: preset.quick, strong: preset.strong, baseURL: nil, vision: nil, tools: nil)
    check(!profile.takesImages, "deepseek vision: a DeepSeek profile takes no images")
    check(["deepseek-flash", "deepseek-v4-pro"].allSatisfy { !ArisAPIModels.capabilities(preset: preset, model: ArisAPIModel(id: $0)).vision },
          "deepseek vision: neither listed model is guessed to take images")
    let driver = ArisAPIDriver(profile: profile, tools: "/usr/local/bin/aris-tools", home: "/Users/me", executable: URL(fileURLWithPath: "/usr/bin/true"))
    let image = ArisTurnImage(kind: .cursor, name: "cursor-screen.png", format: .png, data: Data([1, 2, 3]), badge: nil, app: nil, title: nil)
    for tier in [ArisTier.quick, .work] {
        let line = driver.ask("화면 봐줘", images: [image], tier: tier).first.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
        check((line["images"] as? [Any])?.isEmpty == true && line["model"] as? String == profile.model(tier: tier),
              "deepseek vision: an image turn on DeepSeek (\(tier)) sends no image, the way other models that can't see are asked")
    }
}

private func deepseekConnectionTests() {
    let functions = ArisAPICatalog.functions(sealed: false)
    let entries: [ArisAPIEntry] = [.user(text: "타이머 5분", images: [])]
    func thinking(_ base: String) -> Bool { deepseekBody(ArisAPIConnection.newID(), base: base, entries: entries, functions: functions)["thinking"] != nil }
    for base in ["https://api.deepseek.com/v1", "https://API.DeepSeek.COM/v1", "https://api.deepseek.com"] {
        check(thinking(base), "deepseek connection: a connection on \(base) is asked with thinking off")
    }
    for base in ["https://api.deepseek.com.evil.example/v1", "https://deepseek.example.com/v1", "https://xapi.deepseek.com/v1",
                 "https://evil.example/api.deepseek.com/v1", "https://api.deepseek.co/v1", "https://openrouter.ai/api/v1", "http://127.0.0.1:11434/v1"] {
        check(!thinking(base), "deepseek connection: \(base) never gets DeepSeek's thinking field")
    }
    check(ArisAPIPreset.isDeepSeek(preset: "deepseek", base: "") && !ArisAPIPreset.isDeepSeek(preset: "groq", base: "https://api.groq.com/openai/v1")
          && !ArisAPIPreset.isDeepSeek(preset: "x", base: "https://user@api.deepseek.com.evil.example/v1"),
          "deepseek connection: the preset by its id, anything else only by DeepSeek's exact host")

    // Through a saved connection, as the helper and the router build their requests.
    let deep = ArisAPIConnection(id: ArisAPIConnection.newID(), name: "DeepSeek 직접", base: "https://api.deepseek.com/v1")
    let lookalike = ArisAPIConnection(id: ArisAPIConnection.newID(), name: "Look-alike", base: "https://api.deepseek.com.evil.example/v1")
    ArisAPICustomPresets.set([deep, lookalike])
    defer { ArisAPICustomPresets.set([]) }
    for (connection, expected) in [(deep, true), (lookalike, false)] {
        let profile = ArisAPIProfile(id: connection.id, quick: "deepseek-flash", strong: "deepseek-flash", baseURL: nil, vision: nil, tools: nil)
        let body = deepseekBody(connection.id, base: profile.base, entries: entries, functions: functions)
        let router = ArisAPIRouterCall.body(preset: profile.preset!, model: "deepseek-flash", system: "s", user: "u", schema: ["type": "object"])
        check((body["thinking"] != nil) == expected && (router["thinking"] != nil) == expected,
              "deepseek connection: \(connection.name)'s turns and router requests \(expected ? "ask without thinking" : "never carry the field")")
    }
}

func runDeepseekTests() {
    deepseekPresetTests()
    deepseekThinkingTests()
    deepseekConnectionTests()
    deepseekMigrationTests()
    deepseekVisionTests()
}
