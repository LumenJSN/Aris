// VM run 2, H2's second half: the model's `osascript -e 'tell application "Finder" to get selection'` asked on a card
// titled "보내기". The only change for osascript is the card's title: a line whose first program is osascript is titled
// 스크립트 실행 with the script shown whole. Every shell line's class stays exactly what the base classifier
// (jarvis d701ec39) gives it or stronger (the looking list made narrower), pinned below, and the decision never
// reads the title.

import Foundation

private let scriptTools = "/opt/aris-tools"

/// Every line with the class the base classifier gave it (ArisCore2.shellEffect at d701ec39) and the class it has now.
/// The base's ratings are pinned: a line may only ever be rated the same or stronger. What changed: `env`, `awk`, `sed`,
/// `less`, `more` and `rg` left the looking list, and a looking program is a look only with the flags on its own list
/// (ArisCore2.lookingFlags) and no operand that can be an output; anything else asks. git: the verbs that reach other
/// machines are outward and every other git command asks (a repository's settings can make any of them run a program).
private let ratings: [(String, base: ArisEffectClass, now: ArisEffectClass)] = [
    (#"osascript -e 'tell application "Finder" to get selection'"#, .outward, .outward),
    (#"osascript -e 'tell application "Mail" to send message 1'"#, .outward, .outward),
    (#"/usr/bin/osascript -e 'beep'"#, .outward, .outward),
    (#"o's'ascript -e 'beep'"#, .outward, .outward),
    (#"os\ascript -e 'beep'"#, .never, .never),
    (#"$(echo osascript) -e 'beep'"#, .never, .never),
    (#"`echo osascript` -e 'beep'"#, .never, .never),
    (#"env osascript -e 'beep'"#, .observe, .changePermanent),
    (#"/usr/bin/env osascript -e 'beep'"#, .observe, .changePermanent),
    (#"env rm -rf ~/x"#, .observe, .changePermanent),
    (#"env -S "osascript -e beep""#, .observe, .changePermanent),
    (#"exec osascript -e 'beep'"#, .changePermanent, .changePermanent),
    (#"exec -a x ls"#, .changePermanent, .changePermanent),
    (#"command osascript -e 'beep'"#, .changePermanent, .changePermanent),
    (#"nohup /usr/bin/osascript -e 'beep'"#, .changePermanent, .changePermanent),
    (#"X=1 osascript -e 'beep'"#, .changePermanent, .changePermanent),
    (#"/usr/bin/osa* -e 'beep'"#, .never, .never),
    (#"X=osascript; $X -e 'beep'"#, .never, .never),
    (#"echo 'beep' | osascript"#, .never, .never),
    // git: even a reading verb runs what the repository's settings name; the network verbs are outward, every other asks.
    (#"git -c alias.x='!osascript -e beep' x"#, .changeReversible, .changePermanent),
    (#"git -c core.pager=x log"#, .changeReversible, .changePermanent),
    (#"git --exec-path=/tmp/x status"#, .changeReversible, .changePermanent),
    (#"git -C ~/x status"#, .changeReversible, .changePermanent),
    (#"git --git-dir=/tmp/x log"#, .changeReversible, .changePermanent),
    (#"git --work-tree=/tmp/x status"#, .changeReversible, .changePermanent),
    (#"git diff --output=/tmp/x"#, .observe, .changePermanent),
    (#"git log --ext-diff"#, .observe, .changePermanent),
    (#"git clean -fd"#, .changeReversible, .changePermanent),
    (#"git reset --hard"#, .changeReversible, .changePermanent),
    (#"git add ."#, .changeReversible, .changePermanent),
    (#"git commit -m x"#, .changeReversible, .changePermanent),
    (#"git branch new-name"#, .observe, .changePermanent),
    (#"git remote add x https://x.example"#, .observe, .changePermanent),
    (#"git remote set-url origin https://x.example"#, .observe, .changePermanent),
    (#"git fetch"#, .changeReversible, .outward),
    (#"git pull"#, .changeReversible, .outward),
    (#"git clone https://x.example/r.git"#, .changeReversible, .outward),
    (#"git ls-remote origin"#, .changeReversible, .outward),
    ("git", .changeReversible, .changePermanent),
    (#"git status -sb"#, .observe, .changePermanent),
    (#"git log --oneline -n 5"#, .observe, .changePermanent),
    (#"git log -5 --stat"#, .observe, .changePermanent),
    (#"git diff --cached --stat"#, .observe, .changePermanent),
    (#"git diff HEAD~1 -- notes.txt"#, .observe, .changePermanent),
    (#"git show --stat HEAD"#, .observe, .changePermanent),
    (#"git branch -a"#, .observe, .changePermanent),
    (#"git rev-parse --abbrev-ref HEAD"#, .observe, .changePermanent),
    (#"git remote -v"#, .observe, .changePermanent),
    (#"git blame -L 1,20 notes.txt"#, .observe, .changePermanent),
    // find reads on past `--`: any `--` is no look; its acting primaries ask.
    (#"find . -- -name x -delete"#, .changePermanent, .changePermanent),
    (#"find -- . -fprint /tmp/x"#, .observe, .changePermanent),
    (#"find . -fprint0 /tmp/x"#, .observe, .changePermanent),
    (#"find . -fprintf /tmp/x '%p'"#, .observe, .changePermanent),
    (#"find -- . -name x"#, .observe, .changePermanent),
    (#"which -- ls"#, .observe, .changePermanent),
    (#"grep -- -x notes.txt"#, .observe, .observe),
    (#"git push origin main"#, .outward, .outward),
    (#"awk 'BEGIN { system("osascript -e beep") }'"#, .observe, .changePermanent),
    (#"awk '{print $1}' notes.txt"#, .observe, .changePermanent),
    (#"sed 'w /tmp/x' notes.txt"#, .observe, .changePermanent),
    (#"sed -n '1p' notes.txt"#, .observe, .changePermanent),
    (#"less notes.txt"#, .observe, .changePermanent),
    (#"more notes.txt"#, .observe, .changePermanent),
    (#"sort -o notes.txt notes.txt"#, .observe, .changePermanent),
    (#"sort -nro out.txt in.txt"#, .observe, .changePermanent),
    (#"sort --compress-program=x big.txt"#, .observe, .changePermanent),
    (#"sort --out=x big.txt"#, .observe, .changePermanent),
    (#"uniq - out.txt"#, .observe, .changePermanent),
    (#"tail -f notes.txt"#, .observe, .changePermanent),
    (#"sort -n notes.txt"#, .observe, .observe),
    (#"uniq in.txt out.txt"#, .observe, .changePermanent),
    (#"uniq -c notes.txt"#, .observe, .observe),
    (#"tree -o out.txt ~"#, .observe, .changePermanent),
    (#"tree -L 2 ~"#, .observe, .observe),
    (#"find . -fls /tmp/x"#, .observe, .changePermanent),
    (#"find . -name '*.txt' -okdir rm '{}' ';'"#, .observe, .changePermanent),
    (#"find . -name '*.txt' -delete"#, .changePermanent, .changePermanent),
    (#"find . -name '*.txt'"#, .observe, .observe),
    (#"date 0101000026"#, .observe, .changePermanent),
    (#"date +%Y-%m-%d"#, .observe, .observe),
    (#"date -u"#, .observe, .observe),
    (#"file -C -m magic"#, .observe, .changePermanent),
    (#"file notes.txt"#, .observe, .observe),
    (#"diff --output=/tmp/x a.txt b.txt"#, .observe, .changePermanent),
    (#"diff a.txt b.txt"#, .observe, .observe),
    (#"rg --pre ./x pattern"#, .observe, .changePermanent),
    (#"rg pattern ~/notes"#, .observe, .changePermanent),
    (#"rg --hostname-bin=x pattern"#, .observe, .changePermanent),
    (#"ls ~/Desktop > /tmp/x"#, .never, .never),
    (#"cat notes.txt >> /tmp/x"#, .never, .never),
    (#"cat notes.txt | tee /tmp/x"#, .never, .never),
    (#"echo $(id)"#, .never, .never),
    (#"open -a 'Script Editor' ~/x.scpt"#, .outward, .outward),
    (#"python3 -c 'import os; os.system("osascript -e beep")'"#, .changePermanent, .changePermanent),
    (#"cd ~ && osascript -e 'beep'"#, .outward, .outward),
    ("PATH=/tmp/x ls", .changePermanent, .changePermanent),
    ("GIT_SSH_COMMAND=x git status", .changePermanent, .changePermanent),
    ("DYLD_INSERT_LIBRARIES=/tmp/x.dylib cat notes.txt", .changePermanent, .changePermanent),
    ("PAGER=x git log", .changePermanent, .changePermanent),
    // The everyday reads still run as looks.
    ("ls ~/Desktop", .observe, .observe),
    ("ls -la ~", .observe, .observe),
    ("grep -rn -A 3 x ~/notes", .observe, .observe),
    ("grep -r --include='*.txt' x .", .observe, .observe),
    ("ps aux", .observe, .observe),
    ("tail -n 20 notes.txt", .observe, .observe),
    ("date -r 1700000000", .observe, .observe),
    ("cat notes.txt", .observe, .observe),
    ("grep x notes.txt", .observe, .observe),
    ("head -n 5 notes.txt", .observe, .observe),
    ("wc -l notes.txt", .observe, .observe),
    ("pwd", .observe, .observe),
    ("which git", .observe, .observe),
    ("stat notes.txt", .observe, .observe),
    ("du -sh ~/Desktop", .observe, .observe),
    ("df -h", .observe, .observe),
    ("mkdir ~/Desktop/new", .changeReversible, .changeReversible),
    ("make build", .changePermanent, .changePermanent),
]

private let strength: [ArisEffectClass] = [.observe, .changeReversible, .changePermanent, .outward, .never]

private func scriptItem(_ command: String, effect: ArisEffectClass, decision: ArisDecision, provenance: ArisCallProvenance = .ownStep) -> ArisAskItem {
    var facts = ArisCallFacts(capability: "shell.run", arguments: [ArisKeyArgument(kind: .command, value: command)])
    facts.scriptTitle = ArisTrustGate.firstProgramIsScript(command)
    return ArisAskItem(call: "c", facts: facts, effect: effect, decision: decision, provenance: provenance)
}

func runVmfix4ScriptTests() {
    // Never weaker than the base, and exactly the rating pinned now.
    for (line, base, now) in ratings {
        let rated = ArisCore2.shellEffect(line, tools: scriptTools)
        check(rated == now, "shell class: \(line) is \(now) (got \(rated))")
        check(strength.firstIndex(of: rated)! >= strength.firstIndex(of: base)!, "shell class: \(line) is never weaker than the base's \(base)")
    }

    // The title never moves a decision: the same call decides the same with and without it, at every level and provenance.
    for (line, _, rated) in ratings where rated != .never {
        for provenance in [ArisCallProvenance.ownerSaid, .ownerEarlier, .ownStep] {
            for level in [ArisTrustLevel.standard, .free] {
                let context = ArisTrustPolicy.Context(level: level, home: "/Users/admin")
                let plain = ArisCallFacts(capability: "shell.run", arguments: [ArisKeyArgument(kind: .command, value: line)])
                var titled = plain
                titled.scriptTitle = true
                check(ArisTrustPolicy.decide(plain, effect: rated, provenance: provenance, context: context)
                      == ArisTrustPolicy.decide(titled, effect: rated, provenance: provenance, context: context),
                      "script: the title doesn't change the decision (\(level), \(provenance)): \(line)")
            }
        }
    }

    // The title: a line whose first program, as the shell rule's splitter reads it, is osascript.
    for line in [#"osascript -e 'tell application "Finder" to get selection'"#, #"/usr/bin/osascript -e 'beep'"#, #"o's'ascript -e 'beep'"#,
                 #"osascript -e 'tell application "Mail" to send message 1'"#] {
        check(ArisTrustGate.firstProgramIsScript(line), "script title: \(line)")
    }
    for line in [#"env osascript -e 'beep'"#, #"cd ~ && osascript -e 'beep'"#, "make build", #"echo 'beep' | osascript"#, "osascripts", ""] {
        check(!ArisTrustGate.firstProgramIsScript(line), "script title: not a script's title: \(line)")
    }

    // The VM's line: the base asks (outward, Aris's own step); its card says 스크립트 실행, never 보내기, the script whole.
    let vm = #"osascript -e 'tell application "Finder" to get selection'"#
    let decision = ArisTrustPolicy.decide(ArisCallFacts(capability: "shell.run", arguments: [ArisKeyArgument(kind: .command, value: vm)]),
                                          effect: .outward, provenance: .ownStep, context: ArisTrustPolicy.Context(home: "/Users/admin"))
    let card = ArisAskPlan.card([scriptItem(vm, effect: .outward, decision: decision)], id: "c", intent: "i", countdown: false, home: "/Users/admin")
    check(card.title.hasPrefix("스크립트 실행") && !card.title.contains("보내기"), "script title: Finder's get selection is a 스크립트 실행 card")
    check((card.full ?? card.detail).contains(vm), "script title: the card shows the script whole")
    // Any other shell line keeps its old title.
    let other = ArisAskPlan.card([scriptItem("make build", effect: .changePermanent, decision: .ask)], id: "d", intent: "i", countdown: false, home: "/Users/admin")
    check(other.title.hasPrefix("실행"), "script title: other commands keep theirs")
    let hidden = ArisAskPlan.card([scriptItem(#"cd ~ && osascript -e 'beep'"#, effect: .outward, decision: .ask)], id: "e", intent: "i", countdown: false,
                                  home: "/Users/admin")
    check(hidden.title.hasPrefix("보내기"), "script title: a line not starting with osascript keeps the old title")

    // The shell sandbox is the base's: no exec rule was added there; the classifier has no script reading.
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    let core2 = (try? String(contentsOf: root.appendingPathComponent("ArisAgent/ArisCapabilityCore2.swift"), encoding: .utf8)) ?? ""
    let sandbox = (try? String(contentsOf: root.appendingPathComponent("ArisAgent/Trust/ArisShellSandbox.swift"), encoding: .utf8)) ?? ""
    check(!core2.contains("unwrapped(") && !core2.contains("runsOthers") && !core2.contains("ArisScriptEffect") && core2.contains("\"osascript\", \"open\", \"gh\"]"),
          "script: shell.run's classifier reads no script")
    check(!sandbox.contains("process-exec"), "script: the shell sandbox's profile is the base's")
}
