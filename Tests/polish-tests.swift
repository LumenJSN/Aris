// jv-polish: the brain the owner chose stays the one that answers. 다른 AI로 넘기기 (off by default) is the only way a
// turn or a warm-up goes to another AI on its own; Claude busy (a rate limit, an overload) is a turn that failed, never
// "Claude is gone"; the default brain is one constant; a screen conversation's task stays on the chosen brain.
// Pure checks and source reads only: nothing is launched or asked.
import Foundation

private func polishSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

func runPolishTests() {
    polishBusyIsNotGoneTests()
    polishFallbackSwitchTests()
    polishDefaultBrainTests()
}

private func polishBusyIsNotGoneTests() {
    for text in ["API Error: 529 {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}",
                 "API Error: 429 rate_limit_error", "Too many requests", "Rate limit exceeded", "Service at capacity"] {
        check(!ArisBrainFailure.isUnavailable(text, brain: .claude) && ArisBrainFailure.isBusy(text, brain: .claude),
              "polish: Claude's \"\(text.prefix(30))\" is busy, not gone")
        if case .failure(let line) = ArisBrainFailure.event(text, brain: .claude) {
            check(line == "Claude가 지금 붐벼요. 잠시 뒤에 다시 해 주세요.", "polish: Claude busy is said as a failure to try again (\(line))")
        } else {
            check(false, "polish: Claude busy never becomes .unavailable (\(text.prefix(30)))")
        }
        check(ArisBrainFailure.isUnavailable(text, brain: .codex) && ArisBrainFailure.isUnavailable(text, brain: .antigravity),
              "polish: the other brains keep every load word as before (\(text.prefix(30)))")
    }
    for text in ["Claude AI usage limit reached|1762300000", "You've hit your usage limit. Your limit resets at 3:00 PM.",
                 "5-hour limit reached ∙ resets 3pm", "You've hit your limit · resets 8pm"] {
        check(ArisBrainFailure.isUnavailable(text, brain: .claude), "polish: Claude's own plan limit is out (\(text.prefix(30)))")
        if case .unavailable = ArisBrainFailure.event(text, brain: .claude) {} else { check(false, "polish: a plan limit stays .unavailable (\(text.prefix(30)))") }
    }
    check(ArisBrainFailure.friendly("overloaded", brain: .claude, korean: false) == "Claude is busy right now. Please try again in a moment.",
          "polish: the busy line in English")
    // A Claude process whose last words are an overload: said once, not asked again at once, never .unavailable.
    if case .say(let line) = ArisBrainFailure.death(stderr: "API Error: 529 overloaded_error", brain: .claude, korean: true, acted: false, isTask: false,
                                                     events: 0, retried: false) {
        check(line.contains("붐벼요"), "polish: a Claude death by overload says busy (\(line))")
    } else {
        check(false, "polish: a Claude death by overload is said, not handed to another AI")
    }
    // Slow is never unavailable (the runner's timeout has its own line and no hand-off).
    check(!ArisBrainFailure.isUnavailable(ArisBrainFailure.slowLine(brain: .claude, korean: false), brain: .claude), "polish: slow is not gone")
}

private func polishFallbackSwitchTests() {
    check(!ArisBrainFallback.allowed([:], fromApp: true) && !ArisBrainFallback.allowed(["fallback": true], fromApp: false)
          && ArisBrainFallback.allowed(["fallback": true], fromApp: true) && ArisBrainFallback.field == ArisBrainFallbackSetting.field,
          "polish: only the app itself turns 다른 AI로 넘기기 on; missing counts as off")
    for missing in [false, true] {
        for available in [false, true] {
            check(!ArisBrainFallback.switchesFirst(allowed: false, retried: false, relayRound: 0, missing: missing, available: available),
                  "polish: switch off, no turn goes to another AI before the chosen one (missing \(missing), available \(available))")
        }
    }
    check(ArisBrainFallback.switchesFirst(allowed: true, retried: false, relayRound: 0, missing: false, available: false)
          && !ArisBrainFallback.switchesFirst(allowed: true, retried: false, relayRound: 0, missing: false, available: true)
          && !ArisBrainFallback.switchesFirst(allowed: true, retried: true, relayRound: 0, missing: true, available: false)
          && !ArisBrainFallback.switchesFirst(allowed: true, retried: false, relayRound: 1, missing: true, available: false),
          "polish: switch on, only an out or missing brain on a first try moves")
    check(!ArisBrainFallback.retriesElsewhere(allowed: false, retried: false, alreadyActed: false, relayRound: 0)
          && ArisBrainFallback.retriesElsewhere(allowed: true, retried: false, alreadyActed: false, relayRound: 0)
          && !ArisBrainFallback.retriesElsewhere(allowed: true, retried: false, alreadyActed: true, relayRound: 0),
          "polish: a limit asks another AI again only with the switch on, and never after something ran")
    var health = ArisBrainHealth()
    let now = Date()
    health.markUnavailable(.claude, at: now)
    check(health.brain(for: .claude, fallback: false, at: now) == .claude && health.brain(for: .claude, fallback: true, at: now) == .codex,
          "polish: /warm warms Claude while it is out unless the switch is on")
    let main = polishSource("ArisAgent/main.swift")
    check(main.contains("brainHealth.brain(for: ArisBrain.named(object[\"brain\"] as? String), fallback: ArisBrainFallback.allowed(object, fromApp: fromApp))")
          && main.contains("ArisBrainFallback.switchesFirst(allowed: fallback") && main.contains("ArisBrainFallback.retriesElsewhere(allowed: fallback")
          && main.contains("fallback: ArisBrainFallback.allowed(object, fromApp: fromApp), on: connection"),
          "polish: /warm, the first try and the limit's retry all read the switch")
    let client = polishSource("Aris/private/Aris/ArisAgentClient.swift")
    check(client.components(separatedBy: "ArisBrainFallbackSetting.field").count - 1 == 2, "polish: the app sends the switch with every question and warm-up")
    let routing = polishSource("ArisAgent/ArisImageRouting.swift")
    check(routing.contains("if task { return Route(brain: requested, sealed: false, sendsImages: false, note: nil, status: nil) }")
          && !routing.contains("Route(brain: .codex, sealed: false, sendsImages: false, note: nil, status: nil) }\n        if task"),
          "polish: a screen conversation's task is never sent to Codex by a rule")
}

private func polishDefaultBrainTests() {
    check(ArisBrain.standard == .claude && ArisBrain.named(nil) == .claude && ArisBrain.named("nonsense") == .claude, "polish: the default brain is one constant")
    check(ArisAIStore.read({ _ in nil }, facts: ArisAIStore.Facts(apiActive: nil, hasElevenKey: false, whisperLargeInstalled: false, languages: ["ko-KR"])).think == "claude"
          && ArisAIChoices().think == ArisBrain.standard.rawValue,
          "polish: the settings page reads the same default as everything else")
    let keys = polishSource("Aris/private/Aris/ArisPreferenceKeys.swift")
    check(keys.contains("Key<String>(\"arisBrain\", default: ArisBrain.standard.rawValue)") && keys.contains("arisBrainFallback = Key<Bool>(ArisBrainFallbackSetting.preferenceKey, default: false)"),
          "polish: the app's preference defaults to the same brain, and 다른 AI로 넘기기 to off")
}
