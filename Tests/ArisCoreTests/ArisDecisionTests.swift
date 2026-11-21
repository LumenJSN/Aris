import XCTest
@testable import ArisCore

/// Decision models behind one seam (jv-decision): the question as each provider's documented endpoint takes it,
/// and its reply read as strictly as Jev's. The replies here are the examples on the providers' own pages.
final class ArisDecisionTests: XCTestCase {
    typealias P = ArisDecisionProviders

    static let ask = ArisDecisionAsk(state: "노래 좀 바꿔줘", questions: [
        .init(name: "app", instructions: "Which app?", options: ["none": "No app", "Music": "Music (뮤직)"]),
        .init(name: "intent", instructions: "What does the user want?", options: ["next_track": "Skip", "ask_claude": "Anything else"]),
    ])

    static func json(_ data: Data?) -> [String: Any] {
        (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }

    static func provider(_ id: String) -> ArisDecisionProvider { P.provider(id)! }

    // MARK: - The ask, read off Jev's own request

    func testAnAskIsReadOffASystemOneBody() {
        let body: [String: Any] = ["model": "jev-1.14.0", "state": "노래 좀 바꿔줘", "questions": [
            "intent": ["type": "choice", "instructions": "What does the user want?", "criteria": ["next_track": "Skip", "ask_claude": "Anything else"]],
            "app": ["type": "choice", "instructions": "Which app?", "criteria": ["none": "No app", "Music": "Music (뮤직)"]],
        ]]
        XCTAssertEqual(ArisDecisionAsk(systemOne: body), Self.ask)
        XCTAssertNil(ArisDecisionAsk(systemOne: ["state": "x", "questions": [:] as [String: Any]]), "no question is no ask")
        XCTAssertNil(ArisDecisionAsk(systemOne: ["state": "x", "questions": ["a": ["type": "score", "criteria": ["low", "high"]]]]), "only choices are asked")
        XCTAssertNil(ArisDecisionAsk(systemOne: ["questions": ["a": ["type": "choice", "criteria": ["x": "y"]]]]), "no words is no ask")
    }

    func testOptionsAreCappedKeepingWhatTheWordsName() {
        var apps = ["none": "No app is named"]
        for index in 0..<40 { apps["App\(String(format: "%02d", index))"] = "App\(String(format: "%02d", index))" }
        apps["KakaoTalk"] = "KakaoTalk (카톡, 카카오톡)"
        apps["Zed"] = "Zed"
        let ask = ArisDecisionAsk(state: "카톡 열어 줘", questions: [.init(name: "app", instructions: "", options: apps), Self.ask.questions[1]])
        let capped = ask.capped(26, keeping: ["none"])
        let kept = capped.questions[0].options
        XCTAssertEqual(kept.count, 26)
        XCTAssertNotNil(kept["none"], "the kept option stays")
        XCTAssertNotNil(kept["KakaoTalk"], "an option the words name by its nickname stays")
        XCTAssertNil(kept["Zed"], "the rest is cut in order")
        XCTAssertEqual(capped.questions[1], Self.ask.questions[1], "a question within the limit is untouched")
        XCTAssertEqual(ask.capped(255, keeping: ["none"]), ask)
    }

    // MARK: - System One (TypeSafe, OpenRouter, Perplexity, Inception, Upstage, Liquid, Foundry, Cloudflare, custom)

    func testTheSystemOneBodyIsJevs() {
        let body = ArisDecisionWire.systemOne.body(Self.ask, model: "jev-1.14.0")
        XCTAssertEqual(body["model"] as? String, "jev-1.14.0")
        XCTAssertEqual(body["state"] as? String, "노래 좀 바꿔줘")
        let questions = body["questions"] as? [String: [String: Any]]
        XCTAssertEqual(questions?.keys.sorted(), ["app", "intent"])
        XCTAssertEqual(questions?["intent"]?["type"] as? String, "choice")
        XCTAssertEqual(questions?["intent"]?["instructions"] as? String, "What does the user want?")
        XCTAssertEqual(questions?["intent"]?["criteria"] as? [String: String], ["next_track": "Skip", "ask_claude": "Anything else"])
        XCTAssertEqual(Set(body.keys), ["model", "state", "questions"], "the words and the questions, nothing more")
    }

    /// docs.typesafe.ai/primitives/choice, openrouter.ai/docs/api/api-reference/alphadecisions (with its id, provider, cost).
    static let systemOneReply = """
    {"answers": {"intent": {"type": "choice", "choice": "next_track", "confidence": 0.75, "probabilities": {"next_track": 0.84, "ask_claude": 0.16}},
                 "app": {"choice": "none", "confidence": 0.99, "probabilities": {"none": 0.99, "Music": 0.01}, "type": "choice"}},
     "id": "gen-dec-1", "model": "typesafe/jev-1.13-20260917", "provider": "TypeSafe", "usage": {"cost": 0.00002, "input_tokens": 476, "output_tokens": 70}}
    """

    func testASystemOneReplyIsReadPerQuestion() {
        let answers = ArisDecisionWire.systemOne.answers(Data(Self.systemOneReply.utf8), for: Self.ask)
        XCTAssertEqual(answers, ["intent": .init(choice: "next_track", confidence: 0.75), "app": .init(choice: "none", confidence: 0.99)])
    }

    func testCloudflaresEnvelopeIsOpened() {
        let wrapped = #"{"result": \#(Self.systemOneReply), "success": true, "errors": [], "messages": []}"#
        XCTAssertEqual(ArisDecisionWire.systemOne.answers(Data(wrapped.utf8), for: Self.ask)?["intent"], .init(choice: "next_track", confidence: 0.75))
        let failed = #"{"result": null, "success": false, "errors": [{"code": 10000, "message": "Authentication error"}]}"#
        XCTAssertNil(ArisDecisionWire.systemOne.answers(Data(failed.utf8), for: Self.ask))
    }

    func testAnythingButExactAnswersIsNoAnswer() {
        func read(_ intent: String, app: String = #"{"choice": "none", "confidence": 0.9}"#) -> [String: ArisDecisionAnswer]? {
            ArisDecisionWire.systemOne.answers(Data(#"{"answers": {"intent": \#(intent), "app": \#(app)}}"#.utf8), for: Self.ask)
        }
        XCTAssertNotNil(read(#"{"choice": "next_track", "confidence": 1}"#))
        XCTAssertNil(read(#"{"choice": "volume_up", "confidence": 0.9}"#), "a choice that is not one of the options")
        XCTAssertNil(read(#"{"choice": "next_track", "confidence": 1.2}"#), "a confidence over 1")
        XCTAssertNil(read(#"{"choice": "next_track", "confidence": -0.1}"#), "a confidence under 0")
        XCTAssertNil(read(#"{"choice": "next_track", "confidence": true}"#), "a confidence that is no number")
        XCTAssertNil(read(#"{"choice": "next_track", "confidence": "0.9"}"#))
        XCTAssertNil(read(#"{"choice": "next_track"}"#), "no confidence")
        XCTAssertNil(read(#"{"type": "refusal"}"#), "a refusal")
        XCTAssertNil(read(#"{"choice": "next_track", "confidence": 0.9}"#, app: "null"), "a missing question")
        XCTAssertNil(ArisDecisionWire.systemOne.answers(Data(#"{"answers": {"intent": {"choice": "next_track", "confidence": 0.9}}}"#.utf8), for: Self.ask))
        for malformed in ["", "next_track", "[]", #"{"answers": []}"#, #"{"error": {"code": 400, "message": "Invalid request parameters"}}"#] {
            XCTAssertNil(ArisDecisionWire.systemOne.answers(Data(malformed.utf8), for: Self.ask), malformed)
        }
        XCTAssertNil(ArisDecisionWire.systemOne.answers(Data(repeating: 0x20, count: 1_000_001), for: Self.ask), "an oversized reply")
    }

    // MARK: - OpenAI's Decisions API

    func testTheOpenAIBodyNamesEachQuestionAndItsChoices() {
        let body = ArisDecisionWire.openAI.body(Self.ask, model: "gpt-6-luna")
        XCTAssertEqual(body["model"] as? String, "gpt-6-luna")
        XCTAssertEqual(body["input"] as? String, "노래 좀 바꿔줘")
        XCTAssertEqual(Set(body.keys), ["model", "input", "questions"])
        let questions = body["questions"] as? [[String: Any]]
        XCTAssertEqual(questions?.map { $0["name"] as? String }, ["app", "intent"])
        XCTAssertEqual(questions?[1]["type"] as? String, "choice")
        XCTAssertEqual(questions?[1]["instructions"] as? String, "What does the user want?")
        let choices = questions?[1]["choices"] as? [[String: String]]
        XCTAssertEqual(choices, [["value": "ask_claude", "description": "Anything else"], ["value": "next_track", "description": "Skip"]])
    }

    func testAnOpenAIReplyIsReadByName() {
        // developers.openai.com/api/reference/resources/decisions/methods/create: answers in question order, each with its name.
        let reply = """
        {"model": "gpt-6-luna", "answers": [
          {"type": "choice", "name": "app", "choice": "none", "confidence": 0.97, "probabilities": [{"value": "none", "probability": 0.98}, {"value": "Music", "probability": 0.02}]},
          {"type": "choice", "name": "intent", "choice": "next_track", "confidence": 0.81, "probabilities": []}],
         "usage": {"input_tokens": 42, "output_tokens": 0, "total_tokens": 42}}
        """
        XCTAssertEqual(ArisDecisionWire.openAI.answers(Data(reply.utf8), for: Self.ask),
                       ["intent": .init(choice: "next_track", confidence: 0.81), "app": .init(choice: "none", confidence: 0.97)])
        let refused = #"{"answers": [{"type": "refusal", "name": "app"}, {"type": "choice", "name": "intent", "choice": "next_track", "confidence": 0.8}]}"#
        XCTAssertNil(ArisDecisionWire.openAI.answers(Data(refused.utf8), for: Self.ask), "one refusal is no answer")
        let typed = #"{"answers": [{"type": "choice", "name": "app", "choice": true, "confidence": 0.9}, {"type": "choice", "name": "intent", "choice": "next_track", "confidence": 0.8}]}"#
        XCTAssertNil(ArisDecisionWire.openAI.answers(Data(typed.utf8), for: Self.ask), "a boolean is not one of the options")
        let other = #"{"answers": [{"type": "predicate", "name": "app", "probability": 0.9}, {"type": "choice", "name": "intent", "choice": "next_track", "confidence": 0.8}]}"#
        XCTAssertNil(ArisDecisionWire.openAI.answers(Data(other.utf8), for: Self.ask))
        XCTAssertNil(ArisDecisionWire.openAI.answers(Data(Self.systemOneReply.utf8), for: Self.ask), "another provider's shape")
    }

    func testAnswersGoBackInJevsShape() {
        let data = ArisDecisionWire.systemOneReply(["intent": .init(choice: "next_track", confidence: 0.75)])
        let answers = Self.json(data)["answers"] as? [String: [String: Any]]
        XCTAssertEqual(answers?["intent"]?["choice"] as? String, "next_track")
        XCTAssertEqual(answers?["intent"]?["confidence"] as? Double, 0.75)
    }

    // MARK: - The providers

    func testEveryProviderHasItsOwnKeyAndADocumentedEndpoint() {
        XCTAssertEqual(P.all.map(\.id), ["jev", "openai", "openrouter", "cloudflare", "perplexity", "inception", "upstage", "liquid", "foundry", "custom"])
        XCTAssertEqual(Set(P.all.map(\.keyName)).count, P.all.count, "one key each")
        XCTAssertEqual(Self.provider("jev").keyName, "typesafe-key", "Jev keeps the key it has")
        for provider in P.all {
            XCTAssertTrue(provider.docs.hasPrefix("https://"), provider.id)
            XCTAssertTrue((2...255).contains(provider.maxOptions), provider.id)
        }
        XCTAssertEqual(Self.provider("upstage").maxOptions, 26, "console.upstage.ai/api/systemone: 2 to 26 options")
        XCTAssertEqual(P.all.filter { !$0.needsKey }.map(\.id), ["custom"])
    }

    func testFixedEndpoints() {
        let expected = [
            "jev": "https://api.typesafe.ai/v1/systemone", "openai": "https://api.openai.com/v1/decisions",
            "openrouter": "https://openrouter.ai/api/alpha/decisions", "perplexity": "https://api.perplexity.ai/v1/decisions",
            "inception": "https://api.inceptionlabs.ai/v1/decisions", "upstage": "https://api.upstage.ai/v1/systemone",
            "liquid": "https://api.liquid.ai/decisions/v1/systemone",
        ]
        for (id, url) in expected {
            XCTAssertEqual(P.url(Self.provider(id), setup: .init())?.absoluteString, url, id)
        }
    }

    func testTheRequestCarriesTheKeyOnlyInItsHeader() {
        let request = P.request(Self.provider("openrouter"), setup: .init(model: "perplexity/pplx-decider-flash-v1.3:free"), key: "sk-or-secret-secret-secret", ask: Self.ask, timeout: 0.6)
        XCTAssertEqual(request?.url?.absoluteString, "https://openrouter.ai/api/alpha/decisions")
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-secret-secret-secret")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request?.timeoutInterval, 0.6)
        XCTAssertEqual(Self.json(request?.httpBody)["model"] as? String, "perplexity/pplx-decider-flash-v1.3:free")
        XCTAssertFalse(String(decoding: request?.httpBody ?? Data(), as: UTF8.self).contains("secret"))
        XCTAssertFalse(request?.url?.absoluteString.contains("secret") ?? true)
        XCTAssertNil(P.request(Self.provider("openrouter"), setup: .init(), key: nil, ask: Self.ask, timeout: 0.6), "no key, no request")
        XCTAssertNil(P.request(Self.provider("openrouter"), setup: .init(model: "bad model\n"), key: "k", ask: Self.ask, timeout: 0.6), "a model that is no id")
        let openAI = P.request(Self.provider("openai"), setup: .init(), key: "sk-secret", ask: Self.ask, timeout: 0.6)
        XCTAssertEqual(Self.json(openAI?.httpBody)["input"] as? String, "노래 좀 바꿔줘")
        XCTAssertEqual(Self.json(openAI?.httpBody)["model"] as? String, "gpt-6-luna")
    }

    func testJevsRequestIsTheOneItAlwaysGot() {
        let request = P.request(Self.provider("jev"), setup: .init(), key: "ts-key", ask: Self.ask, timeout: 5)
        XCTAssertEqual(request?.url?.absoluteString, "https://api.typesafe.ai/v1/systemone")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer ts-key")
        XCTAssertEqual(Self.json(request?.httpBody)["model"] as? String, "jev-1.14.0")
    }

    func testCloudflareNeedsItsAccountAndOneOfItsTwoModels() {
        let cloudflare = Self.provider("cloudflare")
        let account = "0123456789abcdef0123456789abcdef"
        XCTAssertEqual(P.url(cloudflare, setup: .init(address: account))?.absoluteString,
                       "https://api.cloudflare.com/client/v4/accounts/\(account)/ai/run/@cf/cloudflare/clef-flash")
        XCTAssertEqual(P.url(cloudflare, setup: .init(model: "clef", address: account))?.absoluteString,
                       "https://api.cloudflare.com/client/v4/accounts/\(account)/ai/run/@cf/cloudflare/clef")
        XCTAssertNil(P.url(cloudflare, setup: .init()), "no account")
        XCTAssertNil(P.url(cloudflare, setup: .init(address: "../../zones")), "an account that is no id")
        XCTAssertNil(P.url(cloudflare, setup: .init(model: "llama-4", address: account)), "not a decision model of theirs")
        let body = Self.json(P.request(cloudflare, setup: .init(address: account), key: "cf-token", ask: Self.ask, timeout: 1)?.httpBody)
        XCTAssertEqual(body["model"] as? String, "clef-flash")
    }

    func testFoundryTakesTheResourceAndItsDeployment() {
        let foundry = Self.provider("foundry")
        let setup = P.Setup(model: "pi-decision-1.1", address: "https://example-resource.services.ai.azure.com/")
        XCTAssertEqual(P.url(foundry, setup: setup)?.absoluteString, "https://example-resource.services.ai.azure.com/providers/microsoft/v1/systemone")
        let request = P.request(foundry, setup: setup, key: "azure-key", ask: Self.ask, timeout: 1)
        XCTAssertEqual(request?.value(forHTTPHeaderField: "api-key"), "azure-key")
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(P.url(foundry, setup: .init(model: "d", address: "http://example-resource.services.ai.azure.com")), "never over plain http")
        XCTAssertNil(P.request(foundry, setup: .init(address: setup.address), key: "k", ask: Self.ask, timeout: 1), "no deployment name")
    }

    func testCustomSpeaksSystemOneAtItsOwnAddress() {
        let custom = Self.provider("custom")
        func url(_ address: String) -> String? { P.url(custom, setup: .init(model: "kev-4b", address: address))?.absoluteString }
        XCTAssertEqual(url("http://localhost:8080"), "http://localhost:8080/v1/systemone")
        XCTAssertEqual(url("http://127.0.0.1:8080/"), "http://127.0.0.1:8080/v1/systemone")
        XCTAssertEqual(url("http://192.168.0.12:9000/v1/systemone"), "http://192.168.0.12:9000/v1/systemone")
        XCTAssertEqual(url("http://127.0.0.1:8080/v1/decisions"), "http://127.0.0.1:8080/v1/decisions", "a decisions path given whole is used as it is")
        XCTAssertEqual(url("http://mini.local:8080"), "http://mini.local:8080/v1/systemone")
        XCTAssertEqual(url("http://10.0.0.5:8000"), "http://10.0.0.5:8000/v1/systemone")
        XCTAssertEqual(url("http://172.20.1.1"), "http://172.20.1.1/v1/systemone")
        XCTAssertEqual(url("https://decide.example.com/api"), "https://decide.example.com/api/v1/systemone")
        XCTAssertNil(url("http://decide.example.com"), "plain http only on this Mac or its network")
        XCTAssertNil(url("http://172.32.0.1"))
        XCTAssertNil(url("http://8.8.8.8"))
        XCTAssertNil(url("ftp://localhost"))
        XCTAssertNil(url("https://user:pass@decide.example.com"), "no credentials in the address")
        XCTAssertNil(url("https://decide.example.com/v1?key=1"))
        XCTAssertNil(url(""))
        let open = P.request(custom, setup: .init(model: "kev-4b", address: "http://localhost:8080"), key: nil, ask: Self.ask, timeout: 1)
        XCTAssertNotNil(open, "a key is optional")
        XCTAssertNil(open?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(Self.json(open?.httpBody)["model"] as? String, "kev-4b")
        XCTAssertNil(P.request(custom, setup: .init(address: "http://localhost:8080"), key: nil, ask: Self.ask, timeout: 1), "the model's name is needed")
    }

    func testUpstageGetsNoMoreOptionsThanItTakes() {
        var apps = ["none": "No app"]
        for index in 0..<60 { apps["App\(index)"] = "App\(index)" }
        let ask = ArisDecisionAsk(state: "열어 줘", questions: [.init(name: "app", instructions: "", options: apps)])
        let body = Self.json(P.request(Self.provider("upstage"), setup: .init(), key: "up-key", ask: ask, timeout: 1, keeping: ["none"])?.httpBody)
        let criteria = (body["questions"] as? [String: [String: Any]])?["app"]?["criteria"] as? [String: String]
        XCTAssertEqual(criteria?.count, 26)
        XCTAssertNotNil(criteria?["none"])
    }

    // MARK: - What a decision model can't write

    func testACardChangeGetsItsValueFromAChatModelOnly() {
        typealias I = ArisCardIntent
        let change = I.Verdict(label: .revise, confidence: 0.9)
        XCTAssertTrue(I.needsChat(change))
        for label in [I.Label.approve, .decline, .unrelated] {
            XCTAssertFalse(I.needsChat(I.Verdict(label: label, confidence: 0.99)), "\(label) never goes to a chat model")
        }
        XCTAssertFalse(I.needsChat(I.Verdict(label: .revise, confidence: I.minConfidence - 0.01)), "a change it is not sure of is no answer anyway")
        XCTAssertFalse(I.needsChat(nil))
        XCTAssertEqual(I.revised(change, chat: I.Verdict(label: .revise, confidence: 0.5, field: "시간", value: "내일")),
                       I.Verdict(label: .revise, confidence: 0.9, field: "시간", value: "내일"))
        XCTAssertEqual(I.revised(change, chat: nil), change, "no chat profile: the change stays one without a value")
        XCTAssertEqual(I.revised(change, chat: I.Verdict(label: .approve, confidence: 1)), change, "the chat model never makes it a yes")
        let yes = I.Verdict(label: .approve, confidence: 0.9)
        XCTAssertEqual(I.revised(yes, chat: I.Verdict(label: .revise, confidence: 1, field: "시간", value: "내일")), yes)
    }

    func testStoredChoices() {
        XCTAssertEqual(P.stored("openrouter"), "decide:openrouter")
        XCTAssertEqual(P.id(stored: "decide:openrouter"), "openrouter")
        XCTAssertNil(P.id(stored: "decide:nobody"))
        XCTAssertNil(P.id(stored: "decide:"))
        XCTAssertNil(P.id(stored: "api:openai"))
    }

    func testAKeyIsTakenOutOfWhatIsLogged() {
        XCTAssertEqual(P.redacted("401: key sk-or-secret is invalid", key: "sk-or-secret"), "401: key *** is invalid")
        XCTAssertEqual(P.redacted("plain", key: nil), "plain")
        XCTAssertEqual(P.redacted("plain", key: ""), "plain")
    }
}
