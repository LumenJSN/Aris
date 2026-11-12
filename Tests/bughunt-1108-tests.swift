// Tests for the 2026-11-08 bug hunt (BUGHUNT-2026-11-08.md): each one failed before its fix. Called from main.swift;
// uses its check().
import Foundation

func runBughunt1108Tests() {
    bughuntMissingTeammateTests()
    bughuntDesktopScopeTests()
    bughuntReadScopeTests()
    bughuntSuggestionCountTests()
    bughuntEnvironmentWordTests()
}

/// F1: a job naming a teammate that isn't stored (removed while its job waited, or an unreadable list) is refused,
/// never run as main Aris with no scopes.
private func bughuntMissingTeammateTests() {
    typealias J = ArisTeammateJobs
    let mate = ArisTeammate(id: "mong", name: "몽실", role: "메일", look: .standard, brain: "codex", memoryFile: "")
    check(J.missing("gone", in: [.claudeCode, mate]), "F1: a job for a teammate no longer stored is refused")
    check(J.missing("mong", in: [.claudeCode]), "F1: an unreadable list (only Claude Code) refuses a named teammate's job")
    check(!J.missing("mong", in: [.claudeCode, mate]), "F1: a stored teammate's job runs")
    check(!J.missing(nil, in: [.claudeCode]) && !J.missing(ArisTeammate.claudeCodeId, in: [.claudeCode]),
          "F1: a job naming no teammate (main Aris, a helper) or Claude Code isn't refused")
    check(J.missing("", in: [.claudeCode]) && J.missing(42, in: [.claudeCode]), "F1: a teammate field that isn't a stored id is refused")
}

private let bhTools = "/Users/p/.config/aris/aris-tools"

/// F2: `desktop type|set-value|batch|dialog input` must send its text as a quoted heredoc; with "using apps" on and the
/// terminal off it was refused as a terminal command (Claude's hook and Codex alike), so a teammate could click but
/// never type. The typed text is never read as a command (F9's "export" inside it).
private func bughuntDesktopScopeTests() {
    typealias S = ArisTeammateScope
    let type = "\(bhTools) desktop type @s8f3k2:e2 --stdin <<'ARIS'\nplease export it\nARIS"
    let batch = "\(bhTools) desktop batch --stdin <<'ARIS'\nclick @s8f3k2:e4\nARIS"
    check(S.permits(.shell(type), scopes: [.apps], tools: bhTools) && S.permits(.shell(batch), scopes: [.apps], tools: bhTools),
          "F2: Codex: an apps-only teammate types and batches through a desktop heredoc")
    check(!S.permits(.shell(type), scopes: [.files], tools: bhTools), "F2: Codex: without apps the desktop heredoc is still refused")
    let wrapped = "/bin/zsh -lc '" + type.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    check(S.permits(.shell(wrapped), scopes: [.apps], tools: bhTools), "F2: Codex: the same heredoc inside zsh -lc")
    let words = { (command: String) in ArisCommandPolicy.segments(command)?.map { ArisCommandPolicy.words($0) ?? [] } }
    let desktop = { (command: String) in ArisDesktopShell.parse(command, tools: bhTools)?.words }
    func hook(_ command: String, _ scopes: Set<S>) -> String? {
        let input = try! JSONSerialization.data(withJSONObject: ["tool_name": "Bash", "tool_input": ["command": command]])
        return S.hookRefusal(input: input, tools: bhTools, scopes: scopes, words: words, desktop: desktop)
    }
    check(hook(type, [.apps]) == nil && hook(batch, [.apps]) == nil, "F2: Claude's hook: an apps-only teammate types through a desktop heredoc")
    check(hook(type, [.files]) != nil, "F2: Claude's hook: without apps the heredoc is refused")
    check(hook("\(bhTools) desktop type @s8f3k2:e2 --stdin <<'ARIS'\nhi\nARIS\nenv", [.apps]) != nil,
          "F2: Claude's hook: a line after the heredoc's end isn't a desktop call (refused as the terminal)")
    check(hook("ARIS_TEAMMATE_SCOPES= \(bhTools) desktop type @s8f3k2:e2 --stdin <<'ARIS'\nhi\nARIS", [.apps]) != nil,
          "F2: Claude's hook: the scope variable on the heredoc's command line is still refused")
}

/// F3: Codex runs its own known-safe reads (sed -n, nl, a pipe into head, cd, date, echo) without asking, and a teammate
/// without the terminal had its whole job stopped by the first one. F7: a reading name given as a path, or a read
/// with a flag that runs a program, isn't a plain read.
private func bughuntReadScopeTests() {
    typealias S = ArisTeammateScope
    let p = { (command: String, scopes: Set<S>) in S.permits(.shell(command), scopes: scopes, tools: bhTools) }
    for read in ["sed -n 1,120p report.md", "nl -ba report.md", "ls -la ~/Documents | head -50", "cd ~/Documents && ls", "cat a.md | wc -l"] {
        check(p(read, [.files]), "F3: a files-only teammate may read: \(read)")
    }
    for harmless in ["date", "echo hi", "which python3", "pwd"] {
        check(p(harmless, [.web]), "F3: a web-only teammate may run \(harmless) (it reads no file)")
    }
    check(!p("cat notes.md", [.web]) && !p("sed -n 1p notes.md", [.web]), "F3: a web-only teammate still reads no file")
    for code in ["find . -exec sh -c id", "/tmp/x/cat a", "sed -i s/a/b/ f.txt", "sed -n 1w out.txt f.txt", "rg --pre ./x pattern",
                 "ls | sh", "cat a | tee b", "cat a || id", "cd /tmp && ./run"] {
        check(!p(code, [.files]), "F7: a files-only teammate may not run: \(code)")
        check(p(code, [.terminal]), "F7: a teammate with the terminal may: \(code)")
    }
}

/// F6: every helper job of one hand-out carries the same request, so one three-way split counted three times toward
/// "make a teammate?" and the offer came after a single request. One hand-out counts once.
private func bughuntSuggestionCountTests() {
    let split = ArisHelpers.assign([ArisJobSpec(title: "a", prompt: "p", assignee: .clone, cwd: nil, appHint: nil),
                                    ArisJobSpec(title: "b", prompt: "p", assignee: .clone, cwd: nil, appHint: nil),
                                    ArisJobSpec(title: "c", prompt: "p", assignee: .clone, cwd: nil, appHint: nil)])
    check(split.filter { ArisHelpers.countsTowardSuggestion($0.assignee) }.count == 1, "F6: a three-way split counts once")
    check(ArisHelpers.countsTowardSuggestion(.clone), "F6: Aris's own single job counts")
    check(!ArisHelpers.countsTowardSuggestion(.teammate("mong")), "F6: a teammate's job never counts")
}

/// F9: the environment check matched "export", "env" or "unset" anywhere, so a teammate's plain aris-tools call whose
/// argument held the word ("export the slides") was refused. An argument to aris-tools is data; the shell's own
/// environment commands and the scope variables stay refused.
private func bughuntEnvironmentWordTests() {
    typealias S = ArisTeammateScope
    let words = { (command: String) in ArisCommandPolicy.segments(command)?.map { ArisCommandPolicy.words($0) ?? [] } }
    func hook(_ command: String, _ scopes: Set<S>) -> String? {
        let input = try! JSONSerialization.data(withJSONObject: ["tool_name": "Bash", "tool_input": ["command": command]])
        return S.hookRefusal(input: input, tools: bhTools, scopes: scopes, words: words)
    }
    let note = "\(bhTools) note \"export the slides, unset the old env\""
    check(hook(note, [.files]) == nil && S.permits(.shell(note), scopes: [.files], tools: bhTools),
          "F9: a note that says export, unset and env is a note")
    for bad in ["env", "\(bhTools) note hi && env", "unset ARIS_TEAMMATE_JOB; \(bhTools) note hi", "\(bhTools) note ARIS_TEAMMATE_SCOPES",
                "export X=1 && \(bhTools) note hi"] {
        check(hook(bad, [.files, .terminal]) != nil && !S.permits(.shell(bad), scopes: [.files, .terminal], tools: bhTools),
              "F9: still refused: \(bad)")
    }
}
