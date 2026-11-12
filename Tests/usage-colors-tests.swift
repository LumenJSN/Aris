// Tests for each AI service's colour in the 사용량 tab (ArisProviderColors), done the way CodexBar does it: one fixed
// colour a provider, in one table; what is too dim for the side notch's glass is lifted until it reads; a provider the
// table doesn't know has none (the views draw it in the glass's white). Called from main.swift; uses its check().
import Foundation

func runUsageColorsTests() {
    let shown = ["claude", "codex", "antigravity"]
    let colours = shown.compactMap { ArisProviderColors.color($0) }
    check(colours.count == shown.count, "usage colours: every provider the tab shows has a colour of its own")
    check(Set(shown.compactMap { ArisProviderColors.hex[$0] }).count == shown.count, "usage colours: no two providers share one")
    check(colours.allSatisfy { max($0.r, $0.g, $0.b) - min($0.r, $0.g, $0.b) > 0.2 }, "usage colours: none reads as plain white")
    check(ArisProviderColors.hex.keys.allSatisfy { id in
        ArisProviderColors.color(id).map { ClaudeAccent.contrast($0, ClaudeAccent.glass) >= ClaudeAccent.minContrast } ?? false
    }, "usage colours: every colour in the table reads on the glass")
    check(ArisProviderColors.color("claude") == ClaudeAccent.parse("#CC7C5E") && ArisProviderColors.color("codex") == ClaudeAccent.parse("#49A3B0")
          && ArisProviderColors.color("antigravity") == ClaudeAccent.parse("#8AB4F8"), "usage colours: CodexBar's own for Claude and Codex, and Antigravity keeps its blue (the user's pick)")
    if let raw = ClaudeAccent.parse("#6467F2"), let lifted = ArisProviderColors.color("openrouter") {
        check(ClaudeAccent.contrast(raw, ClaudeAccent.glass) < ClaudeAccent.minContrast && lifted != raw && lifted.b >= raw.b && lifted.r > raw.r,
              "usage colours: one too dim for the glass is lifted toward white")
    } else {
        check(false, "usage colours: OpenRouter has a colour")
    }
    check(ArisProviderColors.color("somebody-new") == nil && ArisProviderColors.color("") == nil, "usage colours: a provider the table doesn't know has none")
}
