// Tests for decision models as the quick understanding (jv-decision): the stored choice and who is asked (자동 keeps
// its order and looks for a saved decision-model key before a chat profile), Jev asked through the seam exactly as
// before, any provider's reply read into the same answers, a failure thrown so the turn goes on with the keyword
// rules, and what a decision model can't do (a card change's field and value, the repair of heard words) kept on a
// chat profile. No live call: the decider is a fake.
import Foundation

private struct FakeDecider: ArisDecider {
    let reply: Data?
    func decide(_ ask: ArisDecisionAsk, timeout: TimeInterval) async throws -> Data {
        guard let reply else { throw ArisRouter.Failure(message: "fake failure") }
        return reply
    }
}

private let decideRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().path

private let decideApps = ["Safari", "KakaoTalk", "Music"]

private func jevReply(intent: String = "next_track", confidence: Double = 0.93) -> Data {
    Data("""
    {"model": "jev-1.14.0", "answers": {"intent": {"type": "choice", "choice": "\(intent)", "confidence": \(confidence), "probabilities": {}},
     "app": {"type": "choice", "choice": "none", "confidence": 0.9}, "effort": {"type": "choice", "choice": "quick", "confidence": 0.95},
     "browser": {"type": "choice", "choice": "other", "confidence": 0.97}}, "usage": {"input_tokens": 1900, "output_tokens": 60}}
    """.utf8)
}

func runDecisionModelTests() {
    decideChoiceTests()
    decideAskTests()
    decideReplyTests()
    decideChatTests()
    decideKeyTests()
    decideSettingsTests()
    let done = DispatchSemaphore(value: 0)
    Task { await decideSeamTests(); done.signal() }
    done.wait()
}

private func decideChoiceTests() {
    typealias M = ArisRouterModels
    check(M.choice("decide:openrouter") == .decision("openrouter") && M.stored(.decision("openrouter")) == "decide:openrouter",
          "decide: a decision model is a stored choice of its own")
    check(M.choice("decide:jev") == .jev && M.choice("decide:nobody") == .auto && M.choice("decide:") == .auto,
          "decide: Jev stays Jev, and an unknown provider reads as 자동")
    check(M.choice("rules") == .rules && M.stored(.rules) == "rules" && M.route(.rules, jevKey: true) == .rules,
          "decide: the keyword rules can be chosen outright, whatever keys are saved")
    check(M.choice("jev") == .jev && M.choice("api:openai") == .api("openai") && M.choice(nil) == .auto && M.choice("auto") == .auto,
          "decide: the choices there were read as before")

    let none: (String) -> Bool = { _ in false }
    let both: (String) -> Bool = { ["perplexity", "openrouter"].contains($0) }
    check(M.route(.auto, jevKey: true, ready: both) == .jev, "decide: 자동 is Jev while its key is saved, as before")
    check(M.route(.auto, jevKey: false, ready: both) == .decision("openrouter"),
          "decide: 자동 without a Jev key asks a decision model whose key is saved, the first in the list's order")
    check(M.route(.auto, jevKey: false, ready: none) == .api(nil) && M.route(.auto, jevKey: false) == .api(nil),
          "decide: 자동 with no decision-model key goes to the cheapest chat profile, as before")
    check(M.route(.decision("perplexity"), jevKey: true, ready: both) == .decision("perplexity"),
          "decide: a chosen decision model is asked even when a Jev key is saved")
    check(M.route(.decision("upstage"), jevKey: true, ready: both) == .rules,
          "decide: a chosen decision model without its key is the keyword rules, as Jev without its key")
    check(M.route(.api("openai"), jevKey: false, ready: both) == .api("openai") && M.route(.jev, jevKey: false, ready: both) == .rules,
          "decide: a chat profile and Jev are routed as before")
    check(M.Route.decision("openai").logName == "openai" && M.Route.jev.logName == "jev" && M.Route.api(nil).logName == "api" && M.Route.rules.logName == "rules",
          "decide: the log names who was asked")
}

private func decideAskTests() {
    guard let ask = ArisRouter.decisionAsk(text: "노래 좀 바꿔줘", apps: decideApps) else { return check(false, "decide: Jev's questions are an ask") }
    check(ask.state == "노래 좀 바꿔줘" && ask.questions.map(\.name) == ["app", "browser", "effort", "intent"],
          "decide: every provider is asked Jev's four questions about the words alone")
    check(ask.questions[3].options.keys.sorted() == ArisRouter.Action.allCases.map(\.rawValue).sorted()
          && ask.questions[0].options["KakaoTalk"]?.contains("카톡") == true && ask.questions[0].options[ArisRouter.noApp] != nil,
          "decide: with Jev's own options and their descriptions")

    // Jev through the seam gets the request it always got.
    let old = ArisRouter.request(text: "노래 좀 바꿔줘", apps: decideApps, key: "ts-key-ts-key-ts-key")
    let jev = ArisDecisionProviders.provider("jev")!
    let new = ArisDecisionProviders.request(jev, setup: .init(), key: "ts-key-ts-key-ts-key", ask: ask, timeout: 5, keeping: [ArisRouter.noApp])
    let bodies = [old.httpBody, new?.httpBody].map { $0.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? NSDictionary }
    check(bodies[0] != nil && bodies[0] == bodies[1], "decide: Jev's request body through the seam is the one it always got")
    check(new?.url == old.url && new?.httpMethod == old.httpMethod && new?.allHTTPHeaderFields == old.allHTTPHeaderFields,
          "decide: at the same address with the same headers")
    check(jev.model == ArisRouter.model && ArisDecisionProviders.url(jev, setup: .init()) == ArisRouter.endpoint,
          "decide: Jev's model and endpoint are the router's own")
}

private func decideReplyTests() {
    guard let ask = ArisRouter.decisionAsk(text: "노래 좀 바꿔줘", apps: decideApps) else { return }
    let jev = ArisDecisionProviders.provider("jev")!, openrouter = ArisDecisionProviders.provider("openrouter")!, openAI = ArisDecisionProviders.provider("openai")!
    func read(_ provider: ArisDecisionProvider, _ data: Data, status: Int = 200, key: String? = "sk-secret-secret") -> Result<Data, ArisRouter.Failure> {
        do { return .success(try ArisHTTPDecider.read(provider, data: data, status: status, ask: ask, key: key)) } catch let failure as ArisRouter.Failure {
            return .failure(failure)
        } catch { return .failure(ArisRouter.Failure(message: "other")) }
    }
    if case .success(let data) = read(jev, jevReply()) {
        check(data == jevReply(), "decide: Jev's reply is handed on as it came (read as leniently as before)")
    } else { check(false, "decide: Jev's good reply is an answer") }
    if case .success(let data) = read(jev, Data(#"{"answers": {"intent": {"choice": "next_track", "confidence": 0.9}}}"#.utf8)) {
        check(ArisRouter.parse(data)?.intent == .nextTrack, "decide: Jev answering the intent alone is still read, as before")
    } else { check(false, "decide: Jev's short reply is still an answer") }

    if case .success(let data) = read(openrouter, jevReply(confidence: 0.81)), let answers = ArisRouter.parse(data) {
        check(answers.intent == .nextTrack && answers.intentConfidence == 0.81 && answers.app == ArisRouter.noApp && answers.tier == .quick && !answers.browserWork,
              "decide: another provider's System One reply becomes the same answers")
        check(ArisRouter.decide(answers, text: "노래 좀 바꿔줘") == .media(.next), "decide: and is acted on by the same thresholds")
    } else { check(false, "decide: a System One reply is an answer") }
    let openAIReply = Data("""
    {"model": "gpt-6-luna", "answers": [{"type": "choice", "name": "app", "choice": "none", "confidence": 0.9},
      {"type": "choice", "name": "browser", "choice": "other", "confidence": 0.9}, {"type": "choice", "name": "effort", "choice": "critical", "confidence": 0.8},
      {"type": "choice", "name": "intent", "choice": "ask_claude", "confidence": 0.95}]}
    """.utf8)
    if case .success(let data) = read(openAI, openAIReply), let answers = ArisRouter.parse(data) {
        check(answers.intent == .askClaude && answers.tier == .critical, "decide: OpenAI's reply becomes the same answers")
    } else { check(false, "decide: OpenAI's reply is an answer") }

    for (name, data) in [("a choice that is no option", jevReply(intent: "launch_rocket")), ("a confidence over 1", jevReply(confidence: 1.4)),
                         ("a missing question", Data(#"{"answers": {"intent": {"choice": "next_track", "confidence": 0.9}}}"#.utf8)),
                         ("no JSON", Data("next_track".utf8))] {
        if case .failure(let failure) = read(openrouter, data) {
            check(failure.status == nil && failure.message.contains("OpenRouter"), "decide: \(name) is no answer")
        } else { check(false, "decide: \(name) is no answer") }
    }
    if case .failure(let failure) = read(openrouter, Data(#"{"error": {"code": 401, "message": "bad key sk-secret-secret"}}"#.utf8), status: 401) {
        check(failure.status == 401 && failure.message.contains("OpenRouter answered 401") && !failure.message.contains("sk-secret-secret"),
              "decide: a refused request is an error with its status and never the key")
    } else { check(false, "decide: a 401 is an error") }
    if case .failure(let failure) = read(jev, Data("nope".utf8), status: 429) {
        check(failure.status == 429 && failure.message.hasPrefix("TypeSafe answered 429"), "decide: Jev's errors read as they did")
    } else { check(false, "decide: Jev's 429 is an error") }
}

private func decideSeamTests() async {
    let good = try? await ArisRouter.ask("노래 좀 바꿔줘", apps: decideApps, decider: FakeDecider(reply: jevReply()))
    check(good?.intent == .nextTrack && good?.intentConfidence == 0.93 && good?.inputTokens == 1900, "decide: the router asks whoever is behind the seam")
    var threw = false
    do { _ = try await ArisRouter.ask("노래 좀 바꿔줘", apps: decideApps, decider: FakeDecider(reply: nil)) } catch { threw = true }
    check(threw, "decide: a decider's failure is thrown on (the turn then uses the keyword rules)")
    threw = false
    do { _ = try await ArisRouter.ask("노래 좀 바꿔줘", apps: decideApps, decider: FakeDecider(reply: Data("{}".utf8))) } catch { threw = true }
    check(threw, "decide: a reply that makes no sense is thrown too")
}

private func decideChatTests() {
    typealias M = ArisRouterModels
    check(M.chat(.api("anthropic")) == .profile("anthropic"), "decide: what only a chat model can do goes to the chat profile chosen")
    check(M.chat(.auto) == .cheapest && M.chat(.jev) == .cheapest && M.chat(.decision("openrouter")) == .cheapest && M.chat(.rules) == .cheapest,
          "decide: with a decision model (or Jev, 자동, the rules) chosen it goes to the cheapest connected chat profile")
    check(M.routeBody(.profile("openai"), ["op": "route"])["id"] as? String == "openai" && M.routeBody(.profile("openai"), [:])["auto"] == nil
          && M.routeBody(.cheapest, [:])["auto"] as? Bool == true && M.routeBody(.cheapest, [:])["id"] == nil,
          "decide: and aris-agent is told which")
    check(!M.Route.jev.writes && !M.Route.decision("openai").writes && !M.Route.rules.writes && M.Route.api(nil).writes && M.Route.api("openai").writes,
          "decide: only a chat profile can write a value; a decision model only picks")

    typealias I = ArisCardIntent
    let picked = I.Verdict(label: .revise, confidence: 0.9)
    check(I.revised(picked, chat: I.Verdict(label: .revise, confidence: 0.6, field: "시간", value: "내일")) == I.Verdict(label: .revise, confidence: 0.9, field: "시간", value: "내일"),
          "decide: a card change the decision model saw gets its field and value from the chat model, at the decision model's confidence")
    check(I.revised(picked, chat: nil) == picked, "decide: with no chat model the change stays a change without a value (the card says it missed it)")
    check(I.revised(picked, chat: I.Verdict(label: .approve, confidence: 0.99)) == picked,
          "decide: the chat model never turns a change into a yes")
    let yes = I.Verdict(label: .approve, confidence: 0.9)
    check(!I.needsChat(yes) && !I.needsChat(I.Verdict(label: .decline, confidence: 0.9)) && !I.needsChat(I.Verdict(label: .unrelated, confidence: 0.9))
          && I.needsChat(picked) && !I.needsChat(I.Verdict(label: .revise, confidence: 0.3)) && !I.needsChat(nil),
          "decide: approve, decline and unrelated never go to a chat model; only a change the decision model is sure of does")
}

private func decideKeyTests() {
    let fromCatalogue = ArisDecisionProviders.all.map(\.keyName).filter { $0 != ArisRouter.keyName }
    check(ArisKeyFile.decisionNames == fromCatalogue, "decide: every decision model's key is one the app keeps in the Keychain")
    check(Set(ArisKeyFile.names).isDisjoint(with: ArisKeyFile.decisionNames) && ArisKeyFile.allNames == ArisKeyFile.names + ArisKeyFile.decisionNames,
          "decide: beside the keys there were (all of them are redacted from diagnostics and deleted with everything else)")
    check(ArisKeyFile.checkOwn("local") == .success("local") && ArisKeyFile.checkOwn(" a b ") == .failure(.spaces) && ArisKeyFile.checkOwn("  ") == .failure(.empty),
          "decide: a self-hosted server's key may be short")
}

private func decideSettingsTests() {
    typealias B = ArisAIServicesBuilder
    var state = ArisAIServicesState()
    func items() -> [ArisAIMenuItem] { B.menu(.router, state).items }
    let ids = items().map(\.id)
    check(ids == ["auto", "jev"] + ArisDecisionProviders.all.dropFirst().map { "decide:" + $0.id } + ["rules"],
          "decide settings: the dropdown lists 자동, the decision models (Jev first), then the keyword rules")
    let groups = B.menu(.router, state).entries.compactMap { entry -> String? in if case .group(let title) = entry { return title } else { return nil } }
    check(groups == ["판단 모델"], "decide settings: grouped as decision models (chat models join once one is connected)")
    check(items().filter { $0.id.hasPrefix("decide:") && $0.id != "decide:custom" }.allSatisfy { $0.tail == "키 필요" },
          "decide settings: each decision model needs its own key")
    check(items().first { $0.id == "decide:custom" }?.tail == "설정 필요" && items().first { $0.id == "rules" }?.tail == nil,
          "decide settings: a custom server needs its address, not a key")
    check(items().first { $0.id == "decide:openai" }?.code == "gpt-6-luna" && items().first { $0.id == "decide:openai" }?.subtitle == "한 달 약 $0.60"
          && items().first { $0.id == "decide:upstage" }?.subtitle == "그 서비스 요금으로",
          "decide settings: with the model asked and what a month costs where the provider says")
    check(B.change(.router, picked: "decide:openrouter", in: state) == .router("decide:openrouter") && B.change(.router, picked: "rules", in: state) == .router("rules")
          && B.change(.router, picked: "decide:nobody", in: state) == nil, "decide settings: a decision model or the rules can be picked; an unknown one can't")

    state.choices.router = "decide:openrouter"
    var page = B.page(state)
    check(page.router.face == ArisAISelectFace(label: "OpenRouter", tail: "키 필요") && page.router.line == "OpenRouter 키가 없어서 키워드 규칙으로 알아들어요",
          "decide settings: a decision model without its key says so, and the keyword rules understand meanwhile")
    check(page.router.decision?.key == .off && page.router.decision?.model == .init(label: "모델 ID", value: "", hint: "typesafe/jev-1.14")
          && page.router.decision?.address == nil && page.router.decision?.keyOptional == false && !page.router.jevKey,
          "decide settings: its key line (API 키 추가) and its model id field are shown, TypeSafe's line is not")
    state.ui.decisionOpen = "openrouter"
    state.ui.decisionError = "키가 너무 짧아요."
    check(B.page(state).router.decision?.key == .editing(error: "키가 너무 짧아요."), "decide settings: the key field opens with what was wrong")
    state.ui = ArisAIUI()
    state.decisionKeys["openrouter"] = "••••••••a91c"
    state.decisionSetup["openrouter"] = .init(model: "cloudflare/clef-flash")
    page = B.page(state)
    check(page.router.face == ArisAISelectFace(label: "OpenRouter") && page.router.line == "OpenRouter cloudflare/clef-flash · 그 서비스 요금으로 · 요청한 말만 보내요"
          && page.router.decision?.key == .on(masked: "••••••••a91c") && page.router.decision?.model.value == "cloudflare/clef-flash",
          "decide settings: with its key it is the one asked, with the model id typed")
    check(items().first { $0.id == "decide:openrouter" }?.checked == true && items().first { $0.id == "decide:openrouter" }?.tail == nil
          && items().first { $0.id == "decide:openrouter" }?.code == "cloudflare/clef-flash", "decide settings: and checked in the dropdown")

    state.choices.router = "decide:cloudflare"
    state.decisionKeys["cloudflare"] = "••••••••beef"
    page = B.page(state)
    check(page.router.face.tail == "설정 필요" && page.router.line == "Cloudflare Clef 설정이 덜 돼서 키워드 규칙으로 알아들어요"
          && page.router.decision?.address == .init(label: "계정 ID", value: "", hint: "Cloudflare Account ID"),
          "decide settings: Cloudflare with its key still needs the account id")
    state.decisionSetup["cloudflare"] = .init(address: "0123456789abcdef0123456789abcdef")
    check(B.page(state).router.line == "Cloudflare Clef clef-flash · 한 달 약 $0.23 · 요청한 말만 보내요" && B.page(state).router.face.tail == nil,
          "decide settings: and is asked once it has it")

    state.choices.router = "decide:custom"
    check(B.page(state).router.decision?.keyOptional == true && B.page(state).router.decision?.address?.label == "서버 주소"
          && B.page(state).router.decision?.model.label == "모델 이름" && B.page(state).router.face == ArisAISelectFace(label: "Custom (Jev-compatible)", tail: "설정 필요"),
          "decide settings: a custom server has an address and a model name, and its key is optional")
    state.decisionSetup["custom"] = .init(model: "kev-4b", address: "http://localhost:8080")
    check(B.page(state).router.line == "Custom (Jev-compatible) kev-4b · 직접 띄운 서버 · Jev와 같은 API(/v1/systemone) · 요청한 말만 보내요",
          "decide settings: a custom server is asked without a key")

    state.choices.router = "rules"
    check(B.page(state).router.face == ArisAISelectFace(label: "키워드 규칙") && B.page(state).router.line.hasPrefix("키워드 규칙으로 알아들어요")
          && B.page(state).router.decision == nil, "decide settings: the keyword rules chosen outright")

    state.choices.router = "auto"
    check(B.routerPick(state) == .decision(ArisDecisionProviders.provider("openrouter")!, model: "cloudflare/clef-flash"),
          "decide settings: 자동 with no Jev key says the decision model whose key is saved")
    state.jevKey = "••••••••1234"
    check(B.routerPick(state) == .jev && B.page(state).router.jevKey, "decide settings: 자동 with a Jev key is Jev, as before")
    check(items().first { $0.id == "auto" }?.subtitle == "Jev 키가 있으면 Jev, 없으면 키가 있는 판단 모델, 그다음 연결된 API (요금을 아는 것 중 가장 싼 것 먼저), 그것도 없으면 키워드 규칙",
          "decide settings: and 자동 says its order (with the tenth VM run's: a connected API whose price isn't known still counts)")

    // Every new line of the page has its English.
    let strings = (try? String(contentsOfFile: decideRoot + "/Aris/components/Settings/Settings.xcstrings", encoding: .utf8)) ?? ""
    for korean in ["판단 모델", "키워드 규칙", "설정 필요", "%@ 설정이 덜 돼서 키워드 규칙으로 알아들어요", "%@ 키", "키 없이도 돼요", "이 모델에 물어보려면 키가 필요해요",
                   "배포 이름", "모델 ID", "계정 ID", "리소스 주소", "서버 주소", "직접 띄운 서버", "Jev와 같은 API(/v1/systemone)", B.autoSubtitle] {
        check(strings.contains("\"\(korean)\""), "decide settings: \(korean) has its English")
    }
}
