// Tests for the quick understanding on a model the user picks (jv-router): Jev, an API profile through aris-agent, or the
// keyword rules. The question an API model gets (read off Jev's own request: the words and the app names, nothing
// more), the request built for each provider (shape, model id, JSON mode, thinking off, time limit, the key's header),
// the replies read strictly (good, fenced, malformed, refused, cut), every failure handed back as an error so the turn
// falls back to the keyword rules, 자동's rule on both sides, and the settings row. No live call: the sender is a fake.
import Foundation

private let routerApps = ["Safari", "KakaoTalk", "Figma", "Music", "Notes"]

private func routerQuestion(_ text: String = "노래 좀 바꿔줘") -> ArisRouterModels.Question {
    ArisRouterModels.question(text: text, apps: routerApps)!
}

private func goodReply(intent: String = "next_track", confidence: Any = 0.93, app: String = "none") -> String {
    """
    {"intent": {"choice": "\(intent)", "confidence": \(confidence)}, "app": {"choice": "\(app)", "confidence": 0.9},
     "effort": {"choice": "quick", "confidence": 0.95}, "browser": {"choice": "other", "confidence": 0.97}}
    """
}

func runRouterModelTests() {
    routerChoiceTests()
    routerQuestionTests()
    routerReplyTests()
    routerRequestTests()
    routerProviderReplyTests()
    routerRouteOpTests()
    routerSettingsTests()
}

// MARK: - The choice and 자동

private func routerChoiceTests() {
    typealias M = ArisRouterModels
    check(M.choice(nil) == .auto && M.choice("auto") == .auto && M.choice("jev") == .jev && M.choice("api:openai") == .api("openai")
          && M.choice("api:") == .auto && M.choice("nonsense") == .auto,
          "router choice: nothing stored is 자동; api:<id> is that profile; anything else reads as 자동")
    check([M.Choice.auto, .jev, .api("anthropic")].allSatisfy { M.choice(M.stored($0)) == $0 }, "router choice: every choice is stored as itself")
    check(M.route(.auto, jevKey: true) == .jev && M.route(.auto, jevKey: false) == .api(nil),
          "router 자동: Jev while its key is saved, else aris-agent's cheapest connected API profile")
    check(M.route(.jev, jevKey: true) == .jev && M.route(.jev, jevKey: false) == .rules,
          "router Jev without its key: the keyword rules, as with no key before")
    check(M.route(.api("openai"), jevKey: true) == .api("openai"), "router: a chosen API profile is asked even when a Jev key is saved")
    check(abs(M.timeoutSeconds - 0.6) < 0.0001, "router: aris-agent gets today's 600 ms limit")
}

// MARK: - The question

private func routerQuestionTests() {
    let text = "노래 좀 바꿔줘"
    let question = routerQuestion(text)
    check(question.user == text, "router question: the user message is the words alone")
    let jev = (try? JSONSerialization.jsonObject(with: ArisRouter.request(text: text, apps: routerApps, key: "").httpBody!)) as? [String: Any]
    let questions = jev?["questions"] as? [String: [String: Any]] ?? [:]
    let criteria = questions.values.flatMap { ($0["criteria"] as? [String: String] ?? [:]).values }
    let instructions = questions.values.compactMap { $0["instructions"] as? String }
    check(!criteria.isEmpty && criteria.allSatisfy(question.system.contains) && instructions.allSatisfy(question.system.contains),
          "router question: every question and option Jev gets is in the prompt")
    check(Set(question.options.keys) == Set(questions.keys) && question.options["intent"] == ArisRouter.Action.allCases.map(\.rawValue).sorted()
          && routerApps.allSatisfy { question.options["app"]?.contains($0) == true },
          "router question: the options are Jev's, the installed apps among them")
    // Privacy: what goes out is Jev's questions and the words, nothing else (no context, history or calendar).
    var known = question.system
    for piece in criteria + instructions + Array(questions.keys) + questions.values.flatMap({ ($0["criteria"] as? [String: String] ?? [:]).keys }) {
        known = known.replacingOccurrences(of: piece, with: "")
    }
    check(!known.contains(text) && known.count < 1_400, "router question: the prompt holds only Jev's questions and a short fixed preamble")
    let schema = question.schema
    check(schema["additionalProperties"] as? Bool == false && Set(schema["required"] as? [String] ?? []) == Set(questions.keys),
          "router schema: every question is required and nothing else is allowed")
    let intent = (schema["properties"] as? [String: Any])?["intent"] as? [String: Any]
    let choice = (intent?["properties"] as? [String: Any])?["choice"] as? [String: Any]
    check(intent?["additionalProperties"] as? Bool == false && (choice?["enum"] as? [String])?.contains("next_track") == true,
          "router schema: each answer is one of its options and a confidence")
    let apps = (0..<130).map { "Some App \($0)" }
    let big = ArisRouterModels.question(text: text, apps: apps)!
    check(big.system.count < 16_000, "router question: about 130 apps keep the prompt near \(big.system.count / 4) tokens (\(big.system.count) characters)")
}

// MARK: - The reply

private func routerReplyTests() {
    let question = routerQuestion()
    let answers = ArisRouterModels.answers(goodReply(), for: question)
    check(answers?.intent == .nextTrack && answers?.intentConfidence == 0.93 && answers?.tier == .quick && answers?.browserWork == false
          && ArisRouter.decide(answers!, text: "노래 좀 바꿔줘") == .media(.next),
          "router reply: a good answer reads as Jev's would, and is acted on the same way")
    check(ArisRouterModels.answers("```json\n" + goodReply() + "\n```", for: question)?.intent == .nextTrack,
          "router reply: one fenced JSON object is read")
    check(ArisRouterModels.answers(goodReply(intent: "next_track", confidence: 1), for: question)?.intentConfidence == 1,
          "router reply: a whole-number confidence is read")
    let open = ArisRouterModels.answers(goodReply(intent: "open_app", app: "Figma"), for: question)
    check(open.map { ArisRouter.decide($0, text: "피그마 켜줘") } == .openApp("Figma"), "router reply: an app from the list opens")
    let bad = [
        "", "sure!", "Here you go: " + goodReply(), goodReply() + " ok", "[1, 2]",
        goodReply(intent: "dance"), goodReply(confidence: 1.5), goodReply(confidence: -0.1), goodReply(confidence: "\"high\""), goodReply(confidence: "true"),
        goodReply(app: "Photoshop"), #"{"intent": {"choice": "next_track", "confidence": 0.9}}"#, "```json\n{\"intent\": 1}",
    ]
    check(bad.allSatisfy { ArisRouterModels.answers($0, for: question) == nil },
          "router reply: no JSON, text around it, an unknown choice or app, a confidence outside 0...1 or not a number, or a missing question is no answer")
}

// MARK: - The request per provider

private func routerProfile(_ id: String, router: String? = nil) -> ArisAPIProfile {
    let preset = ArisAPIPreset.named(id)!
    return ArisAPIProfile(id: id, quick: preset.quick, strong: preset.strong, baseURL: nil, vision: nil, tools: nil, router: router)
}

private func routerBody(_ request: URLRequest?) -> [String: Any] {
    request?.httpBody.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
}

private func routerRequestTests() {
    typealias R = ArisAPIRouterCall
    let question = routerQuestion()
    func make(_ id: String, router: String? = nil) -> URLRequest? {
        let profile = routerProfile(id, router: router)
        return R.request(profile: profile, model: R.model(for: profile), key: "sk-test-key-0123456789", system: question.system, user: question.user,
                         schema: question.schema, timeout: 0.6)
    }
    check(R.model(for: routerProfile("openai")) == "gpt-6-luna" && R.model(for: routerProfile("anthropic")) == "claude-haiku-5-5"
          && R.model(for: routerProfile("gemini")) == "gemini-2.5-flash-lite" && R.model(for: routerProfile("anthropic", router: "claude-haiku-4-5")) == "claude-haiku-4-5"
          && R.model(for: routerProfile("groq")) == ArisAPIPreset.named("groq")!.quick,
          "router model: the small model per provider, the profile's own when set, else the profile's quick one")

    let openai = make("openai")
    let openaiBody = routerBody(openai)
    let format = openaiBody["response_format"] as? [String: Any]
    let schema = format?["json_schema"] as? [String: Any]
    let messages = openaiBody["messages"] as? [[String: Any]] ?? []
    check(openai?.url?.absoluteString == "https://api.openai.com/v1/chat/completions" && openai?.httpMethod == "POST"
          && openai?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-key-0123456789" && openai?.timeoutInterval == 0.6
          && openaiBody["model"] as? String == "gpt-6-luna" && openaiBody["stream"] == nil && openaiBody["max_completion_tokens"] as? Int == R.maxTokens
          && format?["type"] as? String == "json_schema" && schema?["strict"] as? Bool == true && schema?["schema"] != nil
          && openaiBody["reasoning_effort"] as? String == "none"
          && messages.count == 2 && messages[0]["content"] as? String == question.system && messages[1]["content"] as? String == question.user,
          "router request OpenAI: GPT-6 Luna, strict JSON schema, no reasoning, no stream, the key as a bearer, 600 ms")
    check(routerBody(make("openai", router: "gpt-6.2-sol"))["reasoning_effort"] == nil, "router request OpenAI: another model isn't told reasoning none")

    let anthropic = make("anthropic")
    let anthropicBody = routerBody(anthropic)
    let output = (anthropicBody["output_config"] as? [String: Any])?["format"] as? [String: Any]
    let system = anthropicBody["system"] as? [[String: Any]]
    check(anthropic?.url?.absoluteString == "https://api.anthropic.com/v1/messages" && anthropic?.value(forHTTPHeaderField: "x-api-key") == "sk-test-key-0123456789"
          && anthropic?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01" && anthropic?.value(forHTTPHeaderField: "Authorization") == nil
          && anthropicBody["model"] as? String == "claude-haiku-5-5" && anthropicBody["stream"] == nil && anthropicBody["max_tokens"] as? Int == R.maxTokens
          && output?["type"] as? String == "json_schema" && output?["schema"] != nil && (anthropicBody["thinking"] as? [String: Any])?["type"] as? String == "disabled"
          && system?.first?["text"] as? String == question.system && (system?.first?["cache_control"] as? [String: Any])?["type"] as? String == "ephemeral"
          && anthropicBody["temperature"] == nil,
          "router request Anthropic: Haiku 5.5, output_config JSON schema, thinking off, the prompt cached, no stream, no sampling fields")
    check(routerBody(make("anthropic", router: "claude-sonnet-5-5"))["thinking"] == nil, "router request Anthropic: a model that refuses thinking off isn't sent it")

    let gemini = make("gemini")
    let geminiBody = routerBody(gemini)
    let config = geminiBody["generationConfig"] as? [String: Any]
    let geminiSchema = config?["responseSchema"] as? [String: Any]
    check(gemini?.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"
          && gemini?.value(forHTTPHeaderField: "x-goog-api-key") == "sk-test-key-0123456789" && gemini?.url?.query == nil
          && config?["responseMimeType"] as? String == "application/json" && geminiSchema?["type"] as? String == "OBJECT" && geminiSchema?["additionalProperties"] == nil
          && config?["maxOutputTokens"] as? Int == R.maxTokens,
          "router request Gemini: 2.5 Flash-Lite, JSON with Gemini's schema, not streamed, the key in its header and never the address")

    check(R.mode(ArisAPIPreset.named("deepseek")!) == .object && (routerBody(make("deepseek"))["response_format"] as? [String: Any])?["type"] as? String == "json_object"
          && R.mode(ArisAPIPreset.named("groq")!) == .schema(strict: false) && routerBody(make("groq"))["max_tokens"] as? Int == R.maxTokens,
          "router request: DeepSeek's JSON object mode, a schema without strict on the other compatible providers")
    check(R.request(profile: routerProfile("openai"), model: "gpt 6", key: "k", system: "s", user: "u", schema: [:], timeout: 1) == nil
          && R.request(profile: routerProfile("openai"), model: "gpt-6-luna", key: "k", system: "s", user: "u", schema: [:], timeout: 1,
                       testServer: "https://example.com/v1") == nil,
          "router request: a model name of the wrong shape, or a key bound for another host, makes no request")
}

// MARK: - What a provider answers

private func routerProviderReplyTests() {
    typealias R = ArisAPIRouterCall
    func data(_ text: String) -> Data { Data(text.utf8) }
    let json = #"{\"intent\": {}}"#
    check(R.read(data(#"{"choices":[{"message":{"content":"\#(json)","refusal":null},"finish_reason":"stop"}]}"#), dialect: .openAIChat) == .text(#"{"intent": {}}"#)
          && R.read(data(#"{"choices":[{"message":{"content":null,"refusal":"I can't help"},"finish_reason":"stop"}]}"#), dialect: .openAIChat) == .refused
          && R.read(data(#"{"choices":[{"message":{"content":"{\"in"},"finish_reason":"length"}]}"#), dialect: .openAIChat) == .failed(.malformed, "the answer was cut")
          && R.read(data(#"{"choices":[{"message":{"content":""},"finish_reason":"content_filter"}]}"#), dialect: .openAIChat) == .refused,
          "router reply OpenAI: the content, a refusal, a cut answer, a filter stop")
    check(R.read(data(#"{"content":[{"type":"text","text":"{}"}],"stop_reason":"end_turn"}"#), dialect: .anthropic) == .text("{}")
          && R.read(data(#"{"content":[],"stop_reason":"refusal"}"#), dialect: .anthropic) == .refused
          && R.read(data(#"{"content":[{"type":"text","text":"{"}],"stop_reason":"max_tokens"}"#), dialect: .anthropic) == .failed(.malformed, "the answer was cut")
          && R.read(data(#"{"content":[{"type":"thinking","thinking":""}],"stop_reason":"end_turn"}"#), dialect: .anthropic) == .failed(.malformed, "the answer was empty"),
          "router reply Anthropic: the text, a refusal, a cut answer, no text")
    check(R.read(data(#"{"candidates":[{"content":{"parts":[{"text":"{}"}]},"finishReason":"STOP"}]}"#), dialect: .gemini) == .text("{}")
          && R.read(data(#"{"candidates":[{"finishReason":"SAFETY"}]}"#), dialect: .gemini) == .refused
          && R.read(data(#"{"promptFeedback":{"blockReason":"OTHER"}}"#), dialect: .gemini) == .refused
          && R.read(data(#"{"candidates":[{"content":{"parts":[{"text":"x","thought":true},{"text":"{}"}]},"finishReason":"STOP"}]}"#), dialect: .gemini) == .text("{}"),
          "router reply Gemini: the text (never a thought), a safety stop, a blocked prompt")
    check(R.read(data("not json"), dialect: .anthropic) == .failed(.malformed, "the reply isn't JSON")
          && R.outcome(data: nil, status: 0, error: URLError(.timedOut), dialect: .openAIChat, key: nil) == .failed(.timeout, "no answer in time")
          && R.outcome(data: nil, status: 0, error: URLError(.notConnectedToInternet), dialect: .openAIChat, key: nil) == .failed(.network, "the provider couldn't be reached"),
          "router reply: not JSON, too slow, no network")
    if case .failed(let kind, let message) = R.outcome(data: data(#"{"error":{"message":"bad key sk-test-key-0123456789"}}"#), status: 401, error: nil,
                                                       dialect: .openAIChat, key: "sk-test-key-0123456789") {
        check(kind == .auth && !message.contains("sk-test-key"), "router reply: a refused key is an auth failure, and the key never shows")
    } else { check(false, "router reply: a 401 is a failure") }
}

// MARK: - The route op

private final class RouterSender: @unchecked Sendable {
    var asked: [(URLRequest, TimeInterval)] = []
    var answer: (Data?, Int, Error?) = (nil, 0, URLError(.timedOut))

    func send(_ request: URLRequest, _ timeout: TimeInterval, _ done: @escaping (Data?, Int, Error?) -> Void) {
        asked.append((request, timeout))
        done(answer.0, answer.1, answer.2)
    }
}

private func routerRouteOpTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-router-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let secrets = ArisMCPMemorySecrets(), signing = ArisMCPMemorySecrets()
    let store = ArisAPIStore(file: folder.appendingPathComponent("api-brains.json"), signing: signing)
    let sender = RouterSender()
    let question = routerQuestion()
    func route(_ extra: [String: Any]) -> (status: String, object: [String: Any]) {
        var out: (String, [String: Any]) = ("", [:])
        var body: [String: Any] = ["op": "route", "system": question.system, "user": question.user, "schema": question.schema, "timeout": 0.6]
        body.merge(extra) { $1 }
        ArisAPIRouterCall.route(body, store: store, secrets: secrets, send: sender.send) { status, data in
            out = (status, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
        }
        return out
    }
    check(route(["auto": true]).object["none"] as? Bool == true && route(["id": "openai"]).object["none"] as? Bool == true && sender.asked.isEmpty,
          "router op: with no profile connected there is no model, and nothing is sent")

    _ = store.update { $0.saving(routerProfile("openai")).saving(routerProfile("anthropic")).saving(routerProfile("gemini")) }
    check(route(["auto": true]).object["none"] as? Bool == true, "router op: profiles without their keys are never asked")
    _ = secrets.save("sk-openai-key-0123456789", for: "openai")
    _ = secrets.save("sk-ant-key-0123456789", for: "anthropic")
    check(ArisAPIRouterCall.cheapest(store.load(), hasKey: { secrets.secret(for: $0) != nil })?.id == "anthropic",
          "router 자동: of the connected profiles, the cheapest by known price (Haiku and Luna cost the same; the id decides)")
    _ = secrets.save("AIza-gemini-key-0123456789", for: "gemini")
    check(ArisAPIRouterCall.cheapest(store.load(), hasKey: { secrets.secret(for: $0) != nil })?.id == "gemini",
          "router 자동: Gemini 2.5 Flash-Lite is the cheapest once its key is there")
    _ = store.update { $0.saving(routerProfile("gemini", router: "some-unpriced-model")) }
    check(ArisAPIRouterCall.cheapest(store.load(), hasKey: { secrets.secret(for: $0) != nil })?.id == "anthropic",
          "router 자동: a model whose price isn't known is never 자동's pick")

    sender.answer = (Data(#"{"content":[{"type":"text","text":"{\"intent\":{\"choice\":\"next_track\",\"confidence\":0.9}}"}],"stop_reason":"end_turn"}"#.utf8), 200, nil)
    let answered = route(["id": "anthropic"])
    let sent = sender.asked.last
    let sentBody = routerBody(sent?.0)
    check(answered.status == "200 OK" && answered.object["text"] as? String == #"{"intent":{"choice":"next_track","confidence":0.9}}"#
          && answered.object["profile"] as? String == "anthropic" && answered.object["model"] as? String == "claude-haiku-5-5"
          && sent?.0.url?.host == "api.anthropic.com" && sent?.1 == 0.6,
          "router op: the chosen profile is asked with its key, in today's time limit, and its text comes back")
    let sentText = String(decoding: sent?.0.httpBody ?? Data(), as: UTF8.self)
    check(Set(sentBody.keys) == ["model", "max_tokens", "system", "messages", "output_config", "thinking"] && !sentText.contains("sk-ant")
          && (sentBody["messages"] as? [[String: Any]])?.count == 1,
          "router op: the request carries the prompt, the words and nothing else (the key only in its header)")

    sender.answer = (nil, 0, URLError(.timedOut))
    check(route(["id": "anthropic"]).object["kind"] as? String == "timeout", "router op: a slow provider is a timeout error, and the app goes on with its rules")
    sender.answer = (Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8), 200, nil)
    check(route(["id": "anthropic"]).object["kind"] as? String == "refused", "router op: a refusal is an error the app falls back from")
    sender.answer = (Data(#"{"error":{"type":"rate_limit_error","message":"slow down"}}"#.utf8), 429, nil)
    check(route(["id": "anthropic"]).object["kind"] as? String == "rate", "router op: a rate limit is an error the app falls back from")
    check(route(["user": ""]).status == "400 Bad Request" && route(["user": String(repeating: "a", count: 5_000)]).status == "400 Bad Request",
          "router op: no words, or far too many, is not a question")

    // The profile row tells settings which model understands and what it costs; "save" takes an override.
    var saved: (String, [String: Any]) = ("", [:])
    ArisAPIRoutes.settings(["op": "save", "id": "anthropic", "router": "claude-haiku-4-5"], store: store, secrets: secrets) { status, data in
        saved = (status, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
    }
    let row = saved.1["profile"] as? [String: Any]
    check(saved.0 == "200 OK" && store.load().profile("anthropic")?.router == "claude-haiku-4-5" && row?["router"] as? String == "claude-haiku-4-5"
          && row?["routerPrice"] == nil,
          "router save: the profile's own router model is kept, and its price is unknown to Aris")
    let openRow = ArisAPIRoutes.profileRow(routerProfile("openai"), secrets: secrets)
    check(openRow["router"] as? String == "gpt-6-luna" && (openRow["routerPrice"] as? [String: Any])?["input"] as? Double == 0.10,
          "router row: the default model and its price per million tokens")
    ArisAPIRoutes.settings(["op": "save", "id": "anthropic", "router": "bad model!"], store: store, secrets: secrets) { status, _ in saved.0 = status }
    check(saved.0 == "400 Bad Request", "router save: a model name of the wrong shape is refused")
}

// MARK: - The settings row

private func routerState(_ change: (inout ArisAIServicesState) -> Void = { _ in }) -> ArisAIServicesState {
    var state = ArisAIServicesState()
    state.presets = [
        ArisAIPreset(id: "openai", title: "OpenAI", needsKey: true, local: false, baseURL: "", quick: "gpt-6-luna", strong: "gpt-6.1-sol"),
        ArisAIPreset(id: "anthropic", title: "Anthropic", needsKey: true, local: false, baseURL: "", quick: "claude-haiku-4-5", strong: "claude-sonnet-4-5"),
        ArisAIPreset(id: "gemini", title: "Gemini API", needsKey: true, local: false, baseURL: "", quick: "gemini-flash-latest", strong: "gemini-pro-latest"),
    ]
    change(&state)
    return state
}

private func routerSettingsTests() {
    typealias B = ArisAIServicesBuilder
    let luna = ArisAIProfile(id: "openai", quick: "gpt-6-luna", strong: "gpt-6.1-sol", hasKey: true, router: "gpt-6-luna", routerPrice: ArisAIPrice(input: 0.10, output: 0.50))
    let haiku = ArisAIProfile(id: "anthropic", quick: "a", strong: "b", hasKey: true, router: "claude-haiku-5-5", routerPrice: ArisAIPrice(input: 0.10, output: 0.50))
    let flash = ArisAIProfile(id: "gemini", quick: "a", strong: "b", hasKey: false, router: "gemini-2.5-flash-lite", routerPrice: ArisAIPrice(input: 0.10, output: 0.40))

    let empty = routerState()
    check(B.routerPick(empty) == .rules && B.page(empty).router.line == "키워드 규칙으로 알아들어요 · 무료 · 말이 Mac 밖으로 나가지 않아요"
          && B.page(empty).router.face.label == "자동" && B.page(empty).router.jevKey,
          "router row 자동 with nothing set up: the keyword rules, free, nothing leaves the Mac; the TypeSafe key line is there")
    let jev = routerState { $0.jevKey = "••••77aa"; $0.profiles = [luna] }
    check(B.routerPick(jev) == .jev && B.page(jev).router.line == "Jev (TypeSafe) · 한 달 약 $0.25 · 요청한 말만 보내요",
          "router row 자동 with a Jev key: Jev, about $0.25 a month, only the words")
    let api = routerState { $0.profiles = [luna, haiku, flash] }
    guard case .api(let preset, _) = B.routerPick(api) else { return check(false, "router row 자동: an API profile") }
    check(preset.id == "anthropic" && B.page(api).router.line == "Anthropic claude-haiku-5-5 · 한 달 약 $0.72 · 요청한 말만 보내요",
          "router row 자동 without Jev: the cheapest connected profile (a key-less one is never it), about $0.72 a month")
    let chosen = routerState { $0.profiles = [luna]; $0.choices.router = "api:openai"; $0.jevKey = "••••77aa" }
    check(B.page(chosen).router.face.label == "OpenAI" && B.page(chosen).router.line.hasPrefix("OpenAI gpt-6-luna · 한 달 약 $0.72"),
          "router row: a chosen profile is named on the dropdown and costed under it")
    let gone = routerState { $0.choices.router = "api:gemini"; $0.profiles = [flash] }
    check(B.page(gone).router.face.tail == "키 필요" && B.page(gone).router.line == "Gemini API 키가 없어서 키워드 규칙으로 알아들어요" && !B.page(gone).router.jevKey,
          "router row: a chosen profile without its key says so, and the keyword rules understand meanwhile")
    let noJev = routerState { $0.choices.router = "jev" }
    check(B.page(noJev).router.face.tail == "키 필요" && B.routerPick(noJev) == .rules, "router row: Jev without its key needs one")

    let menu = B.menu(.router, api)
    let chat = menu.items.first { $0.id == "api:openai" }
    check(menu.items.map(\.id) == ["auto", "jev"] + ArisDecisionProviders.all.dropFirst().map { "decide:" + $0.id } + ["api:openai", "api:anthropic", "rules"]
          && menu.items[0].checked && menu.items[1].tail == "키 필요" && chat?.code == "gpt-6-luna" && chat?.subtitle == "한 달 약 $0.72",
          "router menu: 자동, Jev and the other decision models, then each connected API profile with its model and monthly cost, then the keyword rules")
    check(B.change(.router, picked: "api:openai", in: api) == .router("api:openai") && B.change(.router, picked: "api:gemini", in: api) == nil
          && B.change(.router, picked: "jev", in: api) == .router("jev"),
          "router menu: picking an item stores it; a profile that can't do it isn't a choice")
    check(ArisAIStore.plan(.router("api:openai")) == [.pref(ArisAIPrefKey.router, .text("api:openai"))] && ArisAIStore.plan(.router("api:")).isEmpty
          && ArisAIStore.applying(.router("jev"), to: ArisAIChoices()).router == "jev"
          && ArisAIStore.read({ $0 == ArisAIPrefKey.router ? "api:anthropic" : nil }, facts: .init()).router == "api:anthropic"
          && ArisAIStore.read({ _ in nil }, facts: .init()).router == "auto" && ArisAIPrefKey.router == "arisRouterModel",
          "router choice: one preference, the one routeNow reads; nothing stored is 자동")
    let list = ArisAIAgentAnswers.list(["presets": [], "profiles": [["id": "openai", "hasKey": true, "router": "gpt-6-luna", "routerPrice": ["input": 0.1, "output": 0.5]]]])
    check(list.profiles.first?.router == "gpt-6-luna" && list.profiles.first?.routerPrice == ArisAIPrice(input: 0.1, output: 0.5),
          "router row: the model and price come from aris-agent's profile rows")
    check(ArisRouterModels.dollars(ArisRouterModels.jevMonthly) == "$0.25" && ArisRouterModels.dollars(0.004) == "$0.01 미만"
          && ArisRouterModels.dollars(ArisRouterModels.monthly(input: 0.10, output: 0.40)) == "$0.70",
          "router cost: 3,000 calls a month of about 2,000 tokens in and 80 out")

    let shown = ArisSettingsBuilder.searchable(ArisSettingsSnapshot())
    check(["나노", "알아듣는 모델", "라우터", "Flash-Lite"].allSatisfy { ArisSettingsIndex.search($0, among: shown).first?.id == "ai.jev" }
          && ["하이쿠", "Luna"].allSatisfy { ArisSettingsIndex.search($0, among: shown).contains { $0.id == "ai.jev" } },
          "router search: the row is found by the models that can do it")
    let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/components/Settings/Settings.xcstrings")
    ArisSettingsCopy.install(ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: catalog)) ?? Data()))
    defer { ArisSettingsCopy.install([:]) }
    for line in [B.page(empty).router.line, B.page(jev).router.line, B.page(api).router.line, B.page(gone).router.line]
        + menu.items.compactMap(\.subtitle) + ["짧은 명령 빨리 알아듣기", "TypeSafe 키", "연결된 API"] {
        let english = ArisSettingsWording(pageEnglish: true, frameEnglish: true).dotted(line)
        check(english.range(of: #"[가-힣]"#, options: .regularExpression) == nil, "router row in English: “\(line)” → “\(english)”")
    }
}
