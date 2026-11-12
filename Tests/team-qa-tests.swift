// Tests for QA's teammate bugs on 868051ee (BUG-25 a–d, BUG-26). Called from main.swift; uses its check().
import Foundation

func runTeamQATests() {
    qaRoleTemplateTests()
    qaAddressTests()
    qaMadeCardAnswerTests()
    qaNoFalseHandOffTests()
    qaRemovalTests()
}

private func qaMate(_ id: String, _ name: String, routing: String = "") -> ArisTeammate {
    ArisTeammate(id: id, name: name, routing: routing, look: .standard, brain: "codex", scopes: [], memoryFile: "teammates/\(id).md")
}

// BUG-25 (a): the stated role picks the closest template; with none, a routing line from the checked name, no scopes.
private func qaRoleTemplateTests() {
    let request = ArisTeamMaking.parse("숫자 계산만 하는 팀원 하나 만들어 줘, 이름은 큐에이봇")
    let made = request.flatMap { ArisTeamMaking.make($0, in: [.claudeCode], aris: .star, brain: "codex") }
    check(request?.template.id == "calc" && made.map { $0.name == "큐에이봇" && $0.routing == ArisTeamTemplate.calc.routing && $0.scopes.isEmpty } == true,
          "BUG-25a: a calculation role gets the 계산 template: its routing line, no scopes")
    check(!ArisTeamTemplate.calc.routing.isEmpty && ArisTeamTemplate.calc.scopes.isEmpty && !ArisTeamTemplate.all.contains { $0.id == "calc" },
          "BUG-25a: the 계산 template has a routing line and no scopes, and stays out of the 팀원 추가 menu")
    let odd = ArisTeamMaking.parse("식물 물 주는 팀원 만들어줘, 이름은 초록이")
    let oddMade = odd.flatMap { ArisTeamMaking.make($0, in: [.claudeCode], aris: .star, brain: "codex") }
    check(oddMade.map { $0.routing == ArisTeamCopy.routingByName("초록이") && $0.scopes.isEmpty && !$0.routing.isEmpty } == true,
          "BUG-25a: no confident match: a routing line built only from the checked name, and no scopes")
    let nameless = ArisTeamMaking.parse("식물 물 주는 팀원 만들어줘")
    let namelessMade = nameless.flatMap { ArisTeamMaking.make($0, in: [.claudeCode], aris: .star, brain: "codex") }
    check(namelessMade.map { !$0.routing.isEmpty && $0.routing == ArisTeamCopy.routingByName($0.name) } == true, "BUG-25a: never an empty routing line")
    check(!(made?.routing.contains("숫자 계산만") ?? true) && !(oddMade?.routing.contains("식물") ?? true), "BUG-25a: no spoken role text in the routing line")
}

// BUG-25 (b): a request that starts with a teammate's name goes to that teammate, decided here, not by a model.
private func qaAddressTests() {
    let team = [ArisTeammate.claudeCode, qaMate("mate-q", "큐에이봇"), qaMate("mate-p", "페이지")]
    for said in ["큐에이봇, 17 곱하기 23은?", "큐에이봇야 17 곱하기 23은?", "큐에이봇한테 17 곱하기 23 물어봐", "큐에이봇에게 계산 맡겨"] {
        check(ArisTeamRouting.addressee(in: said, teammates: team)?.id == "mate-q", "BUG-25b: “\(said)” speaks to 큐에이봇")
    }
    check(ArisTeamRouting.addressee(in: "큐에이봇이 뭐야?", teammates: team) == nil && ArisTeamRouting.addressee(in: "17 곱하기 23은?", teammates: team) == nil,
          "BUG-25b: a name not at the start as a call isn't an address")
    let spec = ArisTeamRouting.directJob("큐에이봇, 17 곱하기 23은?", teammates: team)
    check(spec.map { $0.assignee == .teammate("mate-q") && $0.prompt == "큐에이봇, 17 곱하기 23은?" && $0.cwd == nil } == true,
          "BUG-25b: the app hands it to the teammate itself, the user's words as said")
    let plans = spec.map { ArisHandOutPlan.plan([$0], turn: ArisHandOutPlan.Turn(words: "큐에이봇, 17 곱하기 23은?", brain: .claude, turnId: nil),
                                                brains: ["mate-q": .codex]) } ?? []
    check(plans.count == 1 && plans[0].spec.assignee == .teammate("mate-q") && !plans[0].provenance.untrusted && plans[0].brain == .codex,
          "BUG-25b: on the teammate's own brain, as the user's own words")
    check(ArisTeamRouting.directJob("Claude Code, 테스트 돌려", teammates: team) == nil, "BUG-25b: Claude Code still needs its folder from the brain")
    check(ArisTeamRouting.directJob("페이지 팀원 지워줘", teammates: team) == nil, "BUG-25b: talking about a teammate isn't calling it")
}

// BUG-25 (c): a yes or no while the new-teammate card is up answers the card.
private func qaMadeCardAnswerTests() {
    check(ArisTeamMadeAnswer.reply("응", cardUp: true) == true && ArisTeamMadeAnswer.reply("네 좋아요", cardUp: true) == true
          && ArisTeamMadeAnswer.reply("아니", cardUp: true) == false && ArisTeamMadeAnswer.reply("취소해", cardUp: true) == false,
          "BUG-25c: yes or no answers the open card")
    check(ArisTeamMadeAnswer.reply("응", cardUp: false) == nil && ArisTeamMadeAnswer.reply("17 곱하기 23은?", cardUp: true) == nil,
          "BUG-25c: without a card, or for anything else, it's an ordinary turn")
}

// BUG-25 (c, d): the brain never claims a teammate it didn't make or a hand-off to one that doesn't exist.
private func qaNoFalseHandOffTests() {
    let rule = ArisTeamPrompt.teamTruth
    check(rule.contains("never say") && rule.lowercased().contains("make") && rule.contains("<teammates>"),
          "BUG-25d: every turn is told it can't make teammates and hands work only to listed ones")
    let block = ArisAgentPrompt.teammates([.claudeCode], home: "/Users/me", addressed: nil)
    check(block.contains("No one else") || block.contains("no teammate by that name"), "BUG-25d: the teammates block says the list is everyone")
}

// BUG-26: removing a teammate by voice is a local intent with the settings' confirmation, never a job.
private func qaRemovalTests() {
    let team = [ArisTeammate.claudeCode, qaMate("mate-q", "큐에이봇"), qaMate("mate-p", "페이지")]
    for said in ["큐에이봇 팀원 지워 줘", "큐에이봇 빼 줘", "큐에이봇 팀원 삭제해", "팀원 큐에이봇 빼줘", "Remove teammate 큐에이봇", "delete 큐에이봇 from the team"] {
        check(ArisTeamRemoval.parse(said, teammates: team) == .teammate(team[1]), "BUG-26: “\(said)” removes 큐에이봇")
    }
    check(ArisTeamRemoval.parse("없는애 팀원 지워줘", teammates: team) == .unknown && ArisTeamRemoval.parse("Claude Code 팀원 빼줘", teammates: team) == .fixed,
          "BUG-26: an unknown name or Claude Code is said, not removed")
    check(ArisTeamRemoval.parse("파일 지워줘", teammates: team) == nil && ArisTeamRemoval.parse("큐에이봇, 17 빼기 3은?", teammates: team) == nil,
          "BUG-26: other requests aren't removals")
    let ask = ArisTeamRemoval.confirmation(for: team[1])
    check(ask.title == ArisTeamCopy.removeTitle("큐에이봇") && ask.detail == ArisTeamCopy.removeDetail, "BUG-26: the settings' 빼기 confirmation")
    check(ArisTeamEditing.removing("mate-q", from: team).map(\.id) == ["claude-code", "mate-p"], "BUG-26: a yes removes it")
}
