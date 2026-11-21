//
//  vmfix4-fast-tests.swift
//  The fast answer to a plain fact (VM run 2026-11-19, DeepSeek through the API brain): "프랑스의 수도는 어디야?" got
//  "파리의 수도는… 아니, 프랑스의 수도는 파리예요." and "파리의 수도예요." (and "파리의요." in the run before). Every wrong
//  answer starts "파리의": the answer put first and the question's own frame ("프랑스의 수도는") carried on after it. The
//  prompt asked for exactly that ("the answer comes first", "Never restate the question"), and its Korean rule listed
//  "파리의요" itself. These checks read the request the fast lane really builds for that typed question.
//

import Foundation

func runVmfix4FastTests() {
    let question = "프랑스의 수도는 어디야?"
    let profile = ArisAPIProfile(id: "deepseek", quick: "deepseek-chat", strong: "deepseek-chat", baseURL: nil, vision: nil, tools: nil)
    let driver = ArisAPIDriver(profile: profile, tools: "/usr/local/bin/aris-tools", home: "/Users/me", executable: URL(fileURLWithPath: "/usr/bin/true"))
    let prompt = ArisAgentStream.prompt(request: question, context: ArisAgentPrompt.typedMark, memory: nil)
    let line = driver.ask(prompt, tier: .quick).first.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
    let system = line["system"] as? String ?? ""
    let text = line["text"] as? String ?? ""
    check(line["type"] as? String == "ask" && line["model"] as? String == "deepseek-chat" && !system.isEmpty,
          "fast answer: a typed quick question goes to the API brain as one ask with the quick model and the conversation prompt")

    // What goes to DeepSeek: the system prompt, then one user message whose last line is the whole question. No assistant
    // turn is put first (no prefill or half answer to carry on from), and the answer has room.
    let spec = ArisAPIRequestSpec(dialect: .openAIChat, base: profile.base, model: "deepseek-chat", key: "k", headers: [:], system: system,
                                  entries: [.user(text: text, images: [])], functions: [], preset: "deepseek")
    let body = ArisAPIDialects.request(spec).flatMap { $0.httpBody }.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
    let messages = body["messages"] as? [[String: Any]] ?? []
    let user = messages.last?["content"] as? String ?? ""
    check(messages.map { $0["role"] as? String ?? "" } == ["system", "user"]
          && user.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("\n" + question),
          "fast answer: the request is the system prompt and the whole question as the user's last line, with nothing of an answer before it")
    check((body["max_tokens"] as? Int ?? 0) >= 1_024, "fast answer: a short answer is never cut by the token cap")

    // The wrong answers' cause: the prompt asked to put the answer first and never restate the question, which in Korean
    // ("X의 수도는 어디야?") made the model start with the answer and carry the question's frame on ("파리의 …").
    let rules = [ArisAgentPrompt.spokenRule, ArisAgentPrompt.koreanSpeech, ArisMindSession.rules]
    for (index, rule) in rules.enumerated() {
        check(!rule.contains("answer comes first") && !rule.localizedCaseInsensitiveContains("restate the question"),
              "fast answer: rule \(index) never asks to put the answer first or to leave the question's subject out")
        check(!rule.contains("파리의") && !rule.contains("파리에요"), "fast answer: rule \(index) never shows the wrong form it warns of")
    }
    check(!system.contains("answer comes first") && !system.localizedCaseInsensitiveContains("restate the question") && !system.contains("파리의"),
          "fast answer: the system prompt the API brain gets asks for neither, and never shows \"파리의\"")
    // A short answer stays a whole sentence with its subject, in Korean's own order (the answer before the copula at the end).
    check(ArisAgentPrompt.koreanSpeech.contains("whole sentence") && ArisAgentPrompt.koreanSpeech.contains("도쿄예요"),
          "fast answer: the Korean rule asks for a whole sentence with its subject, shown on a question other than the one tested")
    check(system.contains(ArisAgentPrompt.koreanSpeech) && ArisMindSession.rules.contains(ArisAgentPrompt.koreanSpeech),
          "fast answer: the conversation prompt and the Mind's both carry the Korean rule")
    // The spoken style keeps its point: short, no preamble, no closing offer.
    check(ArisAgentPrompt.spokenRule.contains("preamble") && ArisAgentPrompt.spokenRule.contains("무엇을 도와드릴까요")
          && ArisAgentPrompt.spokenRule.contains("one to three short"),
          "fast answer: the spoken style still asks for one to three short sentences, no preamble and no closing offer")
}
