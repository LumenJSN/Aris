// jv-models: the model and effort chosen per brain and per role (ArisModelChoice), the lists the tools give
// (ArisModelLists, ArisModelDiscovery's parsers), the request payload, the helper's resolution for every tier, the turn
// asked again on 자동 when its chosen model stopped working, the voice phrases, the usage row for a model with no price,
// and the settings rows. Fakes only: no process is started here.
import Foundation

func runModelsTests() {
    modelsChoiceTests()
    modelsResolutionTests()
    modelsDriverTests()
    modelsListTests()
    modelsDiscoveryTests()
    modelsRouteTests()
    modelsPayloadTests()
    modelsRetiredTests()
    modelsVoiceTests()
    modelsUsageTests()
    modelsRowsTests()
    ArisModelChoiceBox.shared.set(.automatic)
}

// MARK: - The choice model

private func modelsChoiceTests() {
    let none = ArisModelChoices.automatic
    check(ArisModelChoices.brains.allSatisfy { brain in ArisModelRole.allCases.allSatisfy { none.choice(brain, $0) == ArisRoleChoice() } },
          "model choice: nothing chosen is 자동 for every brain and role")
    let chosen = none.setting(.claude, .conversation, .model, to: "opus").setting(.codex, .deep, .effort, to: "xhigh")
        .setting(.claude, .job, .model, to: "claude-fable-5-2[1m]")
    check(chosen.choice(.claude, .conversation) == ArisRoleChoice(model: "opus", effort: nil) && chosen.choice(.codex, .deep).effort == "xhigh"
          && chosen.choice(.claude, .deep) == ArisRoleChoice() && chosen.choice(.claude, .job).model == "claude-fable-5-2[1m]",
          "model choice: each role of each brain on its own, a full id with brackets kept")
    check(chosen.entries["claude.conversation.model"] == "opus" && none.entries.isEmpty, "model choice: a copy is made, the original is untouched")
    check(chosen.setting(.claude, .conversation, .model, to: nil).choice(.claude, .conversation).model == nil, "model choice: nil goes back to 자동")
    let raw = ArisModelChoices(entries: ["claude.conversation.model": "my model", "api.conversation.model": "x", "claude.talk.model": "opus",
                                         "codex.deep.effort": "huge", "codex.deep.model": "gpt-6-luna", "claude.deep.effort": "max",
                                         "antigravity.job.model": "auto"])
    check(raw.entries == ["codex.deep.model": "gpt-6-luna", "claude.deep.effort": "max", "antigravity.job.model": "auto"],
          "model choice: an id with a space, the API brain, an unknown role or effort are dropped, never guessed")
    check(raw.choice(.antigravity, .job).model == nil, "model choice: \"auto\" reads as 자동")
    check(ArisModelChoices.parse(["claude.deep.model": "opus", "claude.job.model": 7]).entries == ["claude.deep.model": "opus"]
          && ArisModelChoices.parse("nonsense") == .automatic && ArisModelChoices.parse(nil) == .automatic,
          "model choice: a request's object keeps only its strings")
    check(ArisModelChoices.isModelID("gpt-6.1-sol") && ArisModelChoices.isModelID("openai/gpt-oss-120b") && ArisModelChoices.isModelID("qwen3:8b")
          && !ArisModelChoices.isModelID("") && !ArisModelChoices.isModelID("-x") && !ArisModelChoices.isModelID("a;rm -rf")
          && !ArisModelChoices.isModelID(String(repeating: "a", count: 121)),
          "model choice: a model id is safe characters only, and not too long")
    let saved = none.setting(.claude, .conversation, .model, to: "opus").setting(.claude, .deep, .model, to: "sonnet")
    let override = none.setting(.claude, .conversation, .model, to: "haiku").setting(.claude, .deep, .model, to: "auto")
    let merged = override.merged(over: saved)
    check(merged.choice(.claude, .conversation).model == "haiku" && merged.choice(.claude, .deep).model == nil && merged.entries["claude.deep.model"] == nil,
          "model choice: the conversation's word wins, and its \"auto\" takes the saved one away")
    check(ArisModelRole.of(tier: .quick, task: false) == .conversation && ArisModelRole.of(tier: .work, task: false) == .conversation
          && ArisModelRole.of(tier: .deep, task: false) == .deep && ArisModelRole.of(tier: .critical, task: false) == .deep
          && ArisModelRole.of(tier: .deep, task: true) == .job, "model choice: a turn's role from its tier, a job's own")
}

// MARK: - The helper's resolution

private func modelsResolutionTests() {
    typealias T = ArisThinking
    let tiers: [ArisTier] = [.quick, .work, .deep, .critical]
    let none = ArisModelChoices.automatic
    check(ArisBrain.allCases.allSatisfy { brain in tiers.allSatisfy { T.model(brain, tier: $0, choices: none) == T.model(brain, tier: $0)
                                                                         && T.model(brain, tier: $0, task: true, choices: none) == T.model(brain, tier: $0) } },
          "resolution: 자동 is today's model for every brain, tier and job")
    check(tiers.allSatisfy { tier in ["sonnet", "opus", "haiku", "claude-opus-5-5"].allSatisfy {
              T.claudeEffort(model: $0, tier: tier, task: false, choices: none) == T.claudeEffort(model: $0, tier: tier) } }
          && tiers.allSatisfy { T.codexEffort(tier: $0, task: false, choices: none) == T.codexEffort(tier: $0) },
          "resolution: 자동 effort is today's table on Claude and Codex")
    let chosen = none.setting(.claude, .conversation, .model, to: "opus").setting(.claude, .deep, .model, to: "claude-fable-5-2[1m]")
        .setting(.claude, .job, .model, to: "sonnet").setting(.codex, .conversation, .model, to: "gpt-5.6-terra")
        .setting(.codex, .deep, .effort, to: "xhigh").setting(.antigravity, .deep, .model, to: "claude-opus-4-6-thinking")
    check(T.model(.claude, tier: .quick, choices: chosen) == "opus" && T.model(.claude, tier: .work, choices: chosen) == "opus"
          && T.model(.claude, tier: .deep, choices: chosen) == "claude-fable-5-2[1m]" && T.model(.claude, tier: .critical, choices: chosen) == "claude-fable-5-2[1m]"
          && T.model(.claude, tier: .deep, task: true, choices: chosen) == "sonnet",
          "resolution: Claude's 대화, 깊은 일 and 작업 each take their own model")
    check(T.model(.codex, tier: .quick, choices: chosen) == "gpt-5.6-terra" && T.model(.codex, tier: .deep, choices: chosen) == T.model(.codex, tier: .deep)
          && T.model(.antigravity, tier: .critical, choices: chosen) == "claude-opus-4-6-thinking" && T.model(.antigravity, tier: .quick, choices: chosen) == "gemini-3.8-flash-low"
          && T.model(.api, tier: .quick, choices: chosen) == "api-quick",
          "resolution: Codex and agy likewise; an unchosen role stays 자동; the API brain's are its profile's")
    check(T.claudeEffort(model: "opus", tier: .quick, task: false, choices: chosen) == "low" && T.claudeEffort(model: "opus", tier: .work, task: false, choices: chosen) == "medium"
          && T.claudeEffort(model: "opus", tier: .quick, task: false, choices: none) == "high",
          "resolution: an Opus chosen for 대화 thinks as the tier does (low for a spoken turn), not at a look-up's high")
    check(T.claudeEffort(model: "sonnet", tier: .deep, task: true, choices: chosen) == "high" && T.codexEffort(tier: .deep, task: false, choices: chosen) == "xhigh"
          && T.codexEffort(tier: .quick, task: false, choices: chosen) == "low",
          "resolution: a chosen effort wins for its role only")
    let effortChosen = none.setting(.claude, .conversation, .effort, to: "max")
    check(T.claudeEffort(model: "sonnet", tier: .quick, task: false, choices: effortChosen) == "max"
          && T.claudeEffort(model: "opus", tier: .deep, task: false, choices: effortChosen) == "high",
          "resolution: 대화's effort, and 깊은 일 still on the table")
    check(T.jobModel(.codex, auto: "gpt-6.1-sol", choices: none) == "gpt-6.1-sol" && T.jobModel(.claude, auto: "sonnet", choices: chosen) == "sonnet"
          && T.jobModel(.codex, auto: "x", choices: none.setting(.codex, .job, .model, to: "gpt-6-luna")) == "gpt-6-luna",
          "resolution: a schedule's or a moved job's model is the 작업 choice, else its own 자동")
    let helper = none.setting(.claude, .helper, .model, to: "haiku").setting(.claude, .helper, .effort, to: "medium")
    check(T.helperModel(.claude, auto: "sonnet", choices: none) == "sonnet" && T.helperEffort(.claude, choices: none) == "low"
          && T.helperModel(.claude, auto: "sonnet", choices: helper) == "haiku" && T.helperEffort(.claude, choices: helper) == "medium",
          "resolution: the small helper is 자동 (its caller's model, low) until chosen")
    ArisModelChoiceBox.shared.set(helper)
    let sealed = ArisSealedOneShot.arguments(brain: .claude, model: T.helperModel(.claude, auto: "sonnet", choices: ArisModelChoiceBox.shared.current),
                                             instruction: "i", effort: T.helperEffort(.claude, choices: ArisModelChoiceBox.shared.current))
    check(sealed[sealed.firstIndex(of: "--model")! + 1] == "haiku" && sealed[sealed.firstIndex(of: "--effort")! + 1] == "medium",
          "resolution: a sealed one-shot runs the helper's choice")
    let judge = ArisReadJudge.arguments(brain: .claude, model: "haiku")
    let codexJudge = ArisReadJudge.arguments(brain: .codex, model: "gpt-6-luna")
    check(judge[judge.firstIndex(of: "--effort")! + 1] == "low" && codexJudge.contains(#"model_reasoning_effort="low""#),
          "resolution: the read judge itself stays at low whatever is chosen (the gate is unchanged)")
    ArisModelChoiceBox.shared.set(.automatic)
}

// MARK: - The drivers read the choices

private func modelsDriverTests() {
    func effortControl(_ line: Data) -> String? {
        let object = jsonLine(line)
        guard object["type"] as? String == "control_request", let request = object["request"] as? [String: Any] else { return nil }
        return (request["settings"] as? [String: Any])?["effortLevel"] as? String
    }
    ArisModelChoiceBox.shared.set(.automatic)
    let plain = ArisClaudeDriver(model: "sonnet", tools: "/t")
    let plainArgs = plain.arguments
    check(plainArgs[plainArgs.firstIndex(of: "--effort")! + 1] == "low" && plain.ask("q", tier: .quick).count == 1,
          "drivers: with nothing chosen a Sonnet process starts at low and a quick turn sends only the question")
    ArisModelChoiceBox.shared.set(ArisModelChoices.automatic.setting(.claude, .conversation, .model, to: "opus"))
    let opus = ArisClaudeDriver(model: "opus", tools: "/t")
    let opusArgs = opus.arguments
    check(opusArgs[opusArgs.firstIndex(of: "--model")! + 1] == "opus" && opusArgs[opusArgs.firstIndex(of: "--effort")! + 1] == "low",
          "drivers: an Opus chosen for 대화 starts at a quick turn's low")
    let work = opus.ask("q", tier: .work)
    check(work.count == 2 && effortControl(work[0]) == "medium", "drivers: and goes to medium for a work turn with the per-turn control message")
    ArisModelChoiceBox.shared.set(ArisModelChoices.automatic.setting(.claude, .conversation, .effort, to: "high"))
    let turn = opus.ask("q", tier: .quick)
    check(turn.count == 2 && effortControl(turn[0]) == "high", "drivers: a changed 대화 effort reaches the next turn of a running process")
    ArisModelChoiceBox.shared.set(ArisModelChoices.automatic.setting(.codex, .conversation, .effort, to: "xhigh"))
    let codex = ArisCodexDriver(model: "gpt-6-luna", tools: "/t", instructions: "i")
    let thread = codex.opening().map(jsonLine).last?["id"] as? Int ?? -1
    _ = codex.read(#"{"id":\#(thread),"result":{"thread":{"id":"T1"}}}"#)
    let quick = (jsonLine(codex.ask("x", tier: .quick)[0])["params"] as? [String: Any])?["effort"] as? String
    let deep = (jsonLine(codex.ask("x", tier: .deep)[0])["params"] as? [String: Any])?["effort"] as? String
    check(quick == "xhigh" && deep == "high", "drivers: Codex's turn/start carries the 대화 effort, 깊은 일 stays on the table")
    ArisModelChoiceBox.shared.set(.automatic)
}

// MARK: - The lists, cached

private func modelsListTests() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let empty = ArisModelLists()
    check(empty.needsRefresh(.claude, now: now), "lists: a brain never read is read")
    let opus = ArisModelOption(id: "opus", title: "Opus", detail: "Opus 5.5", efforts: ["low", "medium", "high", "xhigh", "max"])
    let fable = ArisModelOption(id: "claude-fable-5-2[1m]", title: "Fable", detail: nil, efforts: ["low", "high"])
    let read = empty.storing(.claude, options: [opus, fable], fromTool: true, at: now)
    check(!read.needsRefresh(.claude, now: now.addingTimeInterval(3_600)) && read.needsRefresh(.claude, now: now.addingTimeInterval(86_400)),
          "lists: read again at most daily")
    let failed = empty.storing(.codex, options: [], fromTool: true, at: now)
    check(failed.lists["codex"]?.fromTool == false && failed.lists["codex"]?.options == ArisModelLists.fixed(.codex)
          && failed.needsRefresh(.codex, now: now.addingTimeInterval(3_601)) && !failed.needsRefresh(.codex, now: now.addingTimeInterval(600)),
          "lists: a tool that gave nothing keeps today's names and is asked again within the hour")
    let kept = read.storing(.claude, options: [], fromTool: true, at: now.addingTimeInterval(90_000))
    check(kept.lists["claude"]?.options == [opus, fable] && kept.lists["claude"]?.fromTool == false, "lists: an empty answer keeps the list it had")
    let shown = read.options(.claude, selected: ["claude-old-4", "opus"])
    check(shown.map(\.id) == ["opus", "claude-fable-5-2[1m]", "claude-old-4"] && shown.last?.unlisted == true && shown.first?.unlisted == nil,
          "lists: a chosen model the tool no longer lists stays, marked")
    check(empty.options(.claude, selected: []).map(\.id) == ["opus", "sonnet", "haiku"]
          && empty.options(.codex, selected: []).map(\.id) == ["gpt-6-luna", "gpt-6.1-sol"]
          && empty.options(.antigravity, selected: []).map(\.id) == ["gemini-3.8-flash-high", "gemini-3.8-flash-low"],
          "lists: before any list, today's fixed names")
    check(read.efforts(.claude, model: "claude-fable-5-2[1m]") == ["low", "high"] && read.efforts(.claude, model: nil) == ["low", "medium", "high", "xhigh", "max"]
          && empty.efforts(.codex, model: nil) == ["low", "medium", "high"] && empty.efforts(.antigravity, model: nil).isEmpty,
          "lists: a model's own efforts, every listed one's for 자동, low to high when nothing says, none for agy")
    let round = ArisModelLists.decode(read.encoded())
    check(round == read && ArisModelLists.decode("not json") == ArisModelLists(), "lists: kept as JSON, an unreadable one is empty")
}

// MARK: - The tools' answers

private func modelsDiscoveryTests() {
    let initialize = #"{"type":"control_response","response":{"subtype":"success","request_id":"aris-models","response":{"models":["#
        + #"{"value":"default","displayName":"Default (recommended)","description":"Use the default model","supportedEffortLevels":["low"]},"#
        + #"{"value":"opus","displayName":"Opus","description":"Opus 5.5 · Best for everyday, complex tasks","supportedEffortLevels":["low","medium","high","xhigh","max"]},"#
        + #"{"value":"claude-fable-5-2[1m]","displayName":"Fable","description":"Fable 5.2","supportedEffortLevels":["low","high","turbo"]},"#
        + #"{"value":"bad id","displayName":"X"}],"account":{"email":"never read"}}}}"#
    let claude = ArisModelDiscovery.claudeModels(initialize)
    check(claude?.map(\.id) == ["opus", "claude-fable-5-2[1m]"] && claude?.first?.title == "Opus" && claude?.last?.efforts == ["low", "high"]
          && claude?.first?.detail == "Opus 5.5 · Best for everyday, complex tasks",
          "discovery: Claude Code's initialize lists its models (its own default and a bad id left out, unknown efforts dropped)")
    check(ArisModelDiscovery.claudeModels(#"{"type":"control_response","response":{"subtype":"success","request_id":"other","response":{"models":[]}}}"#) == nil
          && ArisModelDiscovery.claudeModels(#"{"type":"system","subtype":"init"}"#) == nil,
          "discovery: only the answer to Aris's own request counts")
    let ok = ArisModelDiscovery.claudeCheck(#"{"type":"control_response","response":{"subtype":"success","request_id":"aris-check","response":{"model":"claude-sonnet-5-5"}}}"#)
    let bad = ArisModelDiscovery.claudeCheck(#"{"type":"control_response","response":{"subtype":"error","request_id":"aris-check","error":"Model 'claude-bogus-9' not found","error_code":"not_found"}}"#)
    check(ok == .ok(resolved: "claude-sonnet-5-5") && bad == .unknown("Model 'claude-bogus-9' not found"),
          "discovery: set_model's success and not_found, as Claude Code 2.1.327 answers")
    let list = #"{"id":2,"result":{"data":["#
        + #"{"id":"gpt-5.6-terra","model":"gpt-5.6-terra","displayName":"GPT-5.6-Terra","hidden":false,"isDefault":false,"description":"","supportedReasoningEfforts":[{"reasoningEffort":"low"},{"reasoningEffort":"ultra"}]},"#
        + #"{"id":"gpt-6-luna","model":"gpt-6-luna","displayName":"GPT-6-Luna","hidden":false,"isDefault":true,"description":"Fast","supportedReasoningEfforts":[{"reasoningEffort":"low"},{"reasoningEffort":"max"}]},"#
        + #"{"id":"gpt-reserve","model":"gpt-reserve","displayName":"Reserve","hidden":true,"isDefault":false,"description":"","supportedReasoningEfforts":[]}],"nextCursor":null}}"#
    let codex = ArisModelDiscovery.codexModels(list)
    check(codex?.map(\.id) == ["gpt-6-luna", "gpt-5.6-terra"] && codex?.first?.efforts == ["low", "max"] && codex?.last?.detail == nil
          && ArisModelDiscovery.codexModels(list, includeHidden: true)?.map(\.id) == ["gpt-6-luna", "gpt-5.6-terra", "gpt-reserve"]
          && ArisModelDiscovery.codexModels(#"{"id":1,"result":{}}"#) == nil,
          "discovery: Codex's model/list, the default first, hidden ones only for a check")
    let agy = ArisModelDiscovery.agyModels("Fetching available models...\ngemini-3.8-flash-high\tGemini 3.8 Flash (High)\nclaude-opus-4-6-thinking\tClaude Opus 4.6 (Thinking)\n\n")
    check(agy.map(\.id) == ["gemini-3.8-flash-high", "claude-opus-4-6-thinking"] && agy.first?.title == "Gemini 3.8 Flash (High)",
          "discovery: agy models' id and name lines")
    let listed = [ArisModelOption(id: "gpt-5.6-terra", title: "T")]
    check(ArisModelDiscovery.listedCheck("gpt-5.6-terra", brain: .codex, listed: listed) == .ok(resolved: nil)
          && ArisModelDiscovery.listedCheck("gpt-6.1-sol", brain: .codex, listed: listed) == .ok(resolved: nil)
          && ArisModelDiscovery.listedCheck("gpt-bogus-9", brain: .codex, listed: listed) == .unknown("")
          && ArisModelDiscovery.listedCheck("gpt-bogus-9", brain: .codex, listed: nil) == .unchecked,
          "discovery: a typed Codex id is taken when listed or one of today's names, refused otherwise, unchecked when Codex can't be asked")
}

// MARK: - POST /models

private func modelsRouteTests() {
    func call(_ object: [String: Any], list: [ArisModelOption]? = nil, check verdict: ArisModelDiscovery.Check = .unchecked) -> (String, [String: Any]) {
        let done = DispatchSemaphore(value: 0)
        var answer = ("", [String: Any]())
        ArisModelRoutes.handle(object, environment: { [:] }, list: { _, _ in list }, check: { _, _, _ in verdict }) { status, body in
            answer = (status, (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:])
            done.signal()
        }
        _ = done.wait(timeout: .now() + 5)
        return answer
    }
    let listed = call(["op": "list", "brain": "claude"], list: [ArisModelOption(id: "opus", title: "Opus", detail: "d", efforts: ["low"])])
    let rows = listed.1["models"] as? [[String: Any]]
    check(listed.0 == "200 OK" && listed.1["fromTool"] as? Bool == true && rows?.first?["id"] as? String == "opus" && rows?.first?["detail"] as? String == "d",
          "route: list answers with the tool's models")
    let fixed = call(["op": "list", "brain": "codex"])
    check(fixed.1["fromTool"] as? Bool == false && (fixed.1["models"] as? [[String: Any]])?.compactMap { $0["id"] as? String } == ["gpt-6-luna", "gpt-6.1-sol"],
          "route: a tool that can't list answers with today's names")
    check(call(["op": "list", "brain": "api"]).0 == "400 Bad Request" && call(["op": "nope", "brain": "claude"]).0 == "400 Bad Request",
          "route: the API brain and unknown requests are refused")
    let unknown = call(["op": "check", "brain": "claude", "model": "claude-bogus-9"], check: .unknown("Model not found"))
    check(unknown.1["ok"] as? Bool == false && (unknown.1["message"] as? String)?.contains("claude-bogus-9") == true,
          "route: an id the tool refuses comes back with the line for under the field")
    check(call(["op": "check", "brain": "claude", "model": "sonnet"], check: .ok(resolved: "claude-sonnet-5-5")).1["resolved"] as? String == "claude-sonnet-5-5"
          && call(["op": "check", "brain": "claude", "model": "rm -rf"], check: .ok(resolved: nil)).1["ok"] as? Bool == false
          && call(["op": "check", "brain": "agy", "model": "x"]).0 == "400 Bad Request"
          && call(["op": "check", "brain": "antigravity", "model": "x"]).1["checked"] as? Bool == false,
          "route: a taken id, a malformed one refused before any tool, and an unchecked one taken by its shape")
}

// MARK: - The request payload

private func modelsPayloadTests() {
    let saved = ArisModelChoices.automatic.setting(.claude, .conversation, .model, to: "sonnet")
    let start = ArisConversationModels()
    let first = start.sending(fresh: true, saved: saved)
    check(first.choices == saved, "payload: a turn carries the saved choices")
    let said = first.state.saying(.claude, .conversation, .model, "opus")
    let turn = said.sending(fresh: false, saved: saved)
    check(turn.choices.choice(.claude, .conversation).model == "opus", "payload: a choice said for this conversation goes with its next turn")
    check(turn.state.sending(fresh: false, saved: saved).choices.choice(.claude, .conversation).model == "opus",
          "payload: and with every turn of it")
    check(turn.state.sending(fresh: true, saved: saved).choices == saved, "payload: a new conversation drops it")
    check(said.sending(fresh: true, saved: saved).choices.choice(.claude, .conversation).model == "opus",
          "payload: unless it was said just before the new conversation's first turn")
    let automatic = start.saying(.claude, .conversation, .model, nil).sending(fresh: false, saved: saved)
    check(automatic.choices.choice(.claude, .conversation).model == nil, "payload: \"자동으로\" for this conversation goes over a saved choice")
    check(said.forgetting(.claude, .conversation, .model).current(saved: saved) == saved, "payload: a saved choice made later gives the conversation's way")
    check(said.current(saved: saved).choice(.claude, .conversation).model == "opus" && said.justSaid,
          "payload: a warm-up or a job reads the conversation's choice without moving it")
    let box = ArisModelChoiceBox()
    let sent = ArisModelTurn.choices(["claude.deep.model": "opus"], fromApp: true, box: box)
    check(sent.choice(.claude, .deep).model == "opus" && box.current == sent, "payload: the helper keeps what the app sent")
    check(ArisModelTurn.choices(["claude.deep.model": "haiku"], fromApp: false, box: box) == sent && box.current == sent,
          "payload: a caller that isn't the app never changes it, and gets the app's")
    check(ArisModelTurn.choices(nil, fromApp: true, box: box) == sent, "payload: a request without models keeps what the app sent last")
    let warmBox = ArisModelChoiceBox()
    warmBox.set(sent)
    check(ArisModelTurn.choices(["claude.conversation.model": "haiku", "claude.job.model": "opus"], fromApp: false, box: warmBox) == sent
          && warmBox.current == sent,
          "payload: a /warm with models from anyone but the app is ignored (the app's last word stands, nothing is set)")
}

// MARK: - A model that stopped working

private func modelsRetiredTests() {
    let claudeSaid = ArisBrainFailure.friendly("There's an issue with the selected model (claude-bogus-9). It may not exist or you may not have access to it. Run --model to pick a different model.", brain: .claude)
    let codexSaid = ArisBrainFailure.friendly("The 'gpt-bogus-9' model is not supported when using Codex with a ChatGPT account.", brain: .codex)
    check(ArisModelRetired.matches(claudeSaid) && ArisModelRetired.matches(codexSaid),
          "retired: Claude Code's and Codex's exact words for a model they can't use")
    check(!ArisModelRetired.matches("model_not_found") && !ArisModelRetired.matches("Model 'x' not found") && !ArisModelRetired.matches("unknown model")
          && !ArisModelRetired.matches(ArisBrainFailure.friendly("rate limit reached", brain: .claude)) && !ArisModelRetired.matches("Claude: 답하지 않았어요")
          && !ArisModelRetired.matches("Claude: the selected model is fine") && !ArisModelRetired.matches("I found the model of the car you asked about"),
          "retired: nothing looser than those words (a page or a tool's other error never triggers a second run)")
    check(!ArisBrainFailure.isUnavailable(claudeSaid) && !ArisBrainFailure.isUnavailable(codexSaid) && !ArisBrainFailure.isLoginProblem(codexSaid),
          "retired: it never reads as a limit or a login (so the brain is never switched for it)")
    let chosen = ArisModelChoices.automatic.setting(.claude, .conversation, .model, to: "claude-bogus-9").setting(.claude, .conversation, .effort, to: "high")
    let again = ArisModelTurn.retired(.failure(claudeSaid), brain: .claude, tier: .quick, choices: chosen, acted: false, korean: true)
    check(again == .again(choices: ArisModelChoices.automatic.setting(.claude, .conversation, .effort, to: "high"),
                          notice: "고른 모델(claude-bogus-9)을 지금 쓸 수 없어서 이번에는 자동으로 고른 모델로 답할게요."),
          "retired: a turn that did nothing yet is asked again on 자동 (its effort kept), the same brain, saying so in one sentence")
    check(ArisModelTurn.retired(.failure(claudeSaid), brain: .claude, tier: .quick, choices: chosen, acted: true, korean: true)
          == .end("고른 모델(claude-bogus-9)을 지금 쓸 수 없어요. 설정 › AI 서비스 › 모델 고르기에서 다른 모델을 골라 주세요."),
          "retired: after a tool ran it ends with the notice and never runs a second time")
    check(ArisModelTurn.retired(.failure(claudeSaid), brain: .claude, tier: .deep, choices: chosen, acted: false, korean: true) == nil
          && ArisModelTurn.retired(.failure(claudeSaid), brain: .claude, tier: .quick, choices: .automatic, acted: false, korean: true) == nil
          && ArisModelTurn.retired(.answer("fine"), brain: .claude, tier: .quick, choices: chosen, acted: false, korean: true) == nil
          && ArisModelTurn.retired(.failure("Claude: quota"), brain: .claude, tier: .quick, choices: chosen, acted: false, korean: true) == nil,
          "retired: only for the role whose chosen model failed; a turn on 자동, an answer or another failure goes on as before")
    if case .again(_, let notice)? = ArisModelTurn.retired(.failure(codexSaid), brain: .codex, tier: .quick,
                                                          choices: .automatic.setting(.codex, .conversation, .model, to: "gpt-bogus-9"), acted: false, korean: false) {
        check(notice.hasPrefix("The model you chose (gpt-bogus-9)"), "retired: in English for an English turn")
    } else {
        check(false, "retired: in English for an English turn")
    }
    check(ArisModelTurn.acted(usedTools: true, handedOff: false, taint: .none, startedAt: .none)
          && ArisModelTurn.acted(usedTools: false, handedOff: true, taint: .none, startedAt: .none)
          && ArisModelTurn.acted(usedTools: false, handedOff: false, taint: .outsideText, startedAt: .none)
          && ArisModelTurn.acted(usedTools: false, handedOff: false, taint: .outsideText, startedAt: .screenSeen)
          && !ArisModelTurn.acted(usedTools: false, handedOff: false, taint: .outsideText, startedAt: .outsideText)
          && !ArisModelTurn.acted(usedTools: false, handedOff: false, taint: .none, startedAt: .none),
          "retired: a tool, a handed-off call or taint beyond what the turn came with counts as done; a marked turn that did nothing doesn't")
    check(ArisModelTurn.startTaint(marked: true, screen: true) == .outsideText && ArisModelTurn.startTaint(marked: false, screen: true) == .screenSeen
          && ArisModelTurn.startTaint(marked: false, screen: false) == .none, "retired: the taint a turn starts with")
    check(ArisModelTurn.carried(untrusted: false, screenSeen: false, taint: .outsideText) == (true, false)
          && ArisModelTurn.carried(untrusted: false, screenSeen: false, taint: .screenSeen) == (false, true)
          && ArisModelTurn.carried(untrusted: true, screenSeen: true, taint: .none) == (true, true)
          && ArisModelTurn.carried(untrusted: false, screenSeen: false, taint: .none) == (false, false),
          "retired: the retry keeps the first attempt's taint and its own provenance, never less")
    let notice = "N."
    check(ArisModelTurn.noted(.answer("A"), notice: notice) == .answer("N.\n\nA") && ArisModelTurn.noted(.status("s"), notice: notice) == .status("s")
          && ArisModelTurn.noted(.answer("A"), notice: nil) == .answer("A") && ArisModelTurn.lead(notice) == "N.\n\n",
          "retired: the answer starts with the sentence, as it was streamed first")
}

// MARK: - Said out loud

private func modelsVoiceTests() {
    typealias V = ArisModelVoice
    check(V.parse("모델 오퍼스로 바꿔") == ArisModelVoiceCommand(kind: .model("opus"), always: false), "voice: 모델 오퍼스로 바꿔")
    check(V.parse("use sonnet for this") == ArisModelVoiceCommand(kind: .model("sonnet"), always: false), "voice: use sonnet for this")
    check(V.parse("이번엔 깊게 생각해") == ArisModelVoiceCommand(kind: .effort("high"), always: false), "voice: 이번엔 깊게 생각해")
    check(V.parse("앞으로 항상 하이쿠 써") == ArisModelVoiceCommand(kind: .model("haiku"), always: true)
          && V.parse("Always use Opus.") == ArisModelVoiceCommand(kind: .model("opus"), always: true)
          && V.parse("항상 깊게 생각해 줘") == ArisModelVoiceCommand(kind: .effort("high"), always: true),
          "voice: 항상 / always make it the saved choice")
    check(V.parse("아리스, 소넷으로 답해 줘") == ArisModelVoiceCommand(kind: .model("sonnet"), always: false)
          && V.parse("think harder") == ArisModelVoiceCommand(kind: .effort("high"), always: false)
          && V.parse("최대한 깊게 생각해") == ArisModelVoiceCommand(kind: .effort("max"), always: false)
          && V.parse("가볍게 생각해") == ArisModelVoiceCommand(kind: .effort("low"), always: false)
          && V.parse("switch to luna") == ArisModelVoiceCommand(kind: .model("luna"), always: false)
          && V.parse("모델 자동으로 돌려") == ArisModelVoiceCommand(kind: .automatic, always: false),
          "voice: the other ways of saying it")
    check(["오퍼스가 뭐야?", "엑셀로 바꿔", "이 문서를 깊게 생각해 볼 수 있게 정리해 줘", "소넷 한 편 써 줘", "Opus vs Sonnet which is better",
           "use the hammer", "모델 Y 주문하고 싶어"].allSatisfy { V.parse($0) == nil },
          "voice: a question or a request that only mentions a name is not a command")
    let codexList = [ArisModelOption(id: "gpt-6-luna", title: "GPT-6-Luna"), ArisModelOption(id: "gpt-5.6-luna", title: "GPT-5.6-Luna"),
                     ArisModelOption(id: "gpt-5.6-terra", title: "GPT-5.6-Terra")]
    check(V.resolve("luna", brain: .codex, options: codexList) == "gpt-6-luna" && V.resolve("terra", brain: .codex, options: codexList) == "gpt-5.6-terra"
          && V.resolve("opus", brain: .codex, options: codexList) == nil && V.resolve("opus", brain: .claude, options: []) == "opus"
          && V.resolve("fable", brain: .claude, options: [ArisModelOption(id: "claude-fable-5-2[1m]", title: "Fable")]) == "claude-fable-5-2[1m]",
          "voice: a name finds the brain's model (Claude Code's own aliases, else the list's first)")
    let set = V.outcome(ArisModelVoiceCommand(kind: .model("luna"), always: false), brain: .codex, options: codexList, korean: true)
    check(set.changes == [.init(field: .model, value: "gpt-6-luna")] && !set.always && set.line == "이번 대화는 GPT-6-Luna 모델로 답할게요.",
          "voice: the model is set for this conversation and said back")
    let missing = V.outcome(ArisModelVoiceCommand(kind: .model("opus"), always: true), brain: .codex, options: codexList, korean: true)
    check(missing.changes.isEmpty && missing.line == "지금 답하는 Codex에는 Opus 모델이 없어요.", "voice: a name the brain doesn't have changes nothing")
    let effort = V.outcome(ArisModelVoiceCommand(kind: .effort("high"), always: true), brain: .claude, options: [], korean: false)
    check(effort.changes == [.init(field: .effort, value: "high")] && effort.always && effort.line == "From now on I'll think hard before answering.",
          "voice: an effort said with always is saved")
    check(V.outcome(ArisModelVoiceCommand(kind: .effort("high"), always: false), brain: .antigravity, options: [], korean: true).changes.isEmpty
          && V.outcome(ArisModelVoiceCommand(kind: .model("opus"), always: false), brain: .api, options: [], korean: true).changes.isEmpty
          && V.outcome(ArisModelVoiceCommand(kind: .automatic, always: false), brain: .claude, options: [], korean: true).changes.count == 2,
          "voice: agy's effort and the API brain's models aren't chosen by voice; 자동 resets both")
}

// MARK: - Usage for a model with no price

private func modelsUsageTests() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let events = [ArisCostEvent(at: now.addingTimeInterval(-60), model: "claude-opus-5-5", tokens: 100, usd: 1),
                  ArisCostEvent(at: now.addingTimeInterval(-120), model: "claude-new-9", tokens: 5_000, usd: 0, priced: false),
                  ArisCostEvent(at: now.addingTimeInterval(-40 * 86_400), model: "claude-gone-1", tokens: 10, usd: 0, priced: false)]
    let cost = ArisUsageAggregate.cost(events, now: now, weekEnd: nil)
    check(cost.unpricedModels == ["claude-new-9"] && cost.today.usd == 1 && cost.today.tokens == 5_100,
          "usage: a model with no price counts its tokens, adds no dollars, and is named (only within the 30 days)")
    check(ArisUsageAggregate.cost(Array(events.prefix(1)), now: now, weekEnd: nil).unpricedModels == nil, "usage: every model priced: nothing to say")
    let old = #"{"today":{"usd":1,"tokens":2},"last30":{"usd":1,"tokens":2},"daily":[],"windows":[]}"#
    check((try? JSONDecoder().decode(ArisUsageCost.self, from: Data(old.utf8)))?.unpricedModels == nil, "usage: a report from before reads as it did")
    check(ArisUsageWords.unpriced(["claude-new-9"], english: false) == "가격을 모르는 모델(claude-new-9)은 토큰만 세고 금액에는 넣지 않았어요."
          && ArisUsageWords.unpriced(["a", "b", "c", "d"], english: true).hasPrefix("No price is known for a, b, c …"),
          "usage: the line under the card names them")
}

// MARK: - The settings rows

private func modelsRowsTests() {
    typealias R = ArisModelChoiceRows
    let none = ArisModelChoices.automatic
    let lists = ArisModelLists().storing(.claude, options: [ArisModelOption(id: "opus", title: "Opus", detail: "Opus 5.5", efforts: ["low", "high", "max"])],
                                         fromTool: true, at: Date())
    let rows = R.rows(.claude, choices: none, lists: lists, advanced: false)
    check(rows.map(\.role) == [.conversation, .deep, .job] && rows.allSatisfy { $0.model == R.auto && $0.effort == R.auto },
          "rows: 대화, 깊은 일, 작업 on 자동; the small helper waits under 고급 설정")
    check(rows[0].models.first?.id == R.auto && rows[0].models.first?.detail == "지금은 sonnet" && rows[1].models.first?.detail == "지금은 opus"
          && rows[0].models.last?.id == R.custom && rows[0].models.map(\.id).contains("opus"),
          "rows: 자동 says what it picks now; the tool's models; 직접 입력 last")
    check(rows[0].efforts.map(\.id) == [R.auto, "low", "high", "max"] && rows[0].efforts.map(\.title) == ["자동", "낮음", "높음", "최대"]
          && rows[0].modelKey == "claude.conversation.model" && rows[0].effortKey == "claude.conversation.effort",
          "rows: 추론 수준 offers what the tool lists, and each dropdown names its setting")
    check(R.rows(.claude, choices: none, lists: lists, advanced: true).last?.role == .helper, "rows: 고급 설정 open shows the small helper")
    let typed = none.setting(.claude, .deep, .model, to: "claude-old-4").setting(.claude, .deep, .effort, to: "xhigh")
    let deep = R.row(.claude, .deep, choices: typed, lists: lists)
    check(deep.model == "claude-old-4" && deep.models.first { $0.id == "claude-old-4" }?.detail == "목록에 없는 모델" && deep.effort == "xhigh"
          && deep.efforts.map(\.id) == [R.auto, "low", "high", "xhigh", "max"],
          "rows: a typed id no longer listed still shows, and so does a chosen effort the list lacks")
    check(R.row(.claude, .job, choices: none, lists: lists, typing: true).model == R.custom, "rows: 직접 입력 open shows as picked")
    let agy = R.row(.antigravity, .conversation, choices: none, lists: ArisModelLists())
    check(agy.effortKey == nil && agy.efforts.isEmpty && agy.models.first?.detail == "지금은 gemini-3.8-flash-high, gemini-3.8-flash-low",
          "rows: agy picks a model only (its models carry their level)")
    check(R.rows(.api, choices: none, lists: lists, advanced: true).isEmpty, "rows: an API brain's models stay in its own row")
    check(R.source(.claude, lists: lists) == "Claude Code가 알려 준 모델이에요" && R.source(.codex, lists: ArisModelLists()) == "모델 목록을 확인하는 중이에요"
          && R.source(.codex, lists: ArisModelLists().storing(.codex, options: [], fromTool: true, at: Date())) == "Codex에서 목록을 받지 못해 기본 이름만 보여요",
          "rows: the line says where the list came from")
}
