//
//  ArisSkillRoutes.swift
//  aris-agent
//
//  The two doors to the user's skills:
//
//    POST /skills {"op", …, "pid", "started"}  (the Aris app itself only, ArisPeer; 403 else): settings › 스킬 and the
//        notch's flows. "status" {"seen"?: [job ids]}, "feature" {"on", "brain"}, "defer", "retry", "add" {"text"|"path",
//        "brain", "hold"?}, "draft" {"conversation": [{"user", "text"}], "editing"?, "brain"}, "save" {"skill", "brain"},
//        "go" {"job"} (검사하고 추가 after a held fetch), "decide" {"job", "accept"}, "enable" {"name", "on"}, "remove" {"name"}, "try" {"name"}, "reveal" {"name"?},
//        "edit" {"name"}  ->  the status, {"job"}, {"ask"|"skill"} or {"error"} (400). Every one may carry "lang" ("en" or
//        "ko"): the app's language, which the AI-written lines are asked for (ArisSkillLanguage).
//    POST /skill-tool {"op": "list"|"read"|"run", "turn", …}  (aris-tools, from inside a brain's turn, checked exactly
//        as /mcp-tool is: the turn's credential and the brain's process tree)  ->  {"status", "output"}
//
//  A script runs only after the user's yes on a card (the same cards as the services', through the runner), never on a
//  turn that saw the screen; its output makes the conversation outside text. A read tells the app which skill the
//  answer follows ("회의록 정리 스킬 사용 중").
//

import Foundation
import Network

enum ArisSkillRoutes {
    // MARK: - Brains

    /// POST /skill-tool, off the server queue once the caller is known.
    static func tool(_ object: [String: Any], on connection: NWConnection, agentPort: UInt16, reply: @escaping (String, Data) -> Void) {
        let refuse = { (why: String) in
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(why))", "question": "skill-tool"]), key: "skill")
            reply("403 Forbidden", ArisMCPRoutes.json(["status": 1, "output": "aris-tools skill works only inside an Aris turn."]))
        }
        guard let credential = object["turn"] as? String, let runner = ArisAgentRunner.runner(forMCPTurn: credential) else { return refuse("no turn credential") }
        let remotePort = ArisTeammateDesk.remotePort(of: connection)
        DispatchQueue.global(qos: .userInitiated).async {
            let now = runner.mcpSnapshot()
            guard now.active else { return refuse("no turn under way") }
            guard runner.brain != .antigravity else { return refuse("Antigravity uses the relay") }
            guard let pid = now.pid, let remotePort, ArisMCPCaller.isInside(root: pid, remotePort: remotePort, agentPort: agentPort) else {
                return refuse("not from the brain's own process")
            }
            let turn = ArisRunnerMCPTurn(runner: runner, handsFree: now.handsFree, screen: now.screen, credential: credential)
            let send = { (outcome: ArisMCPOutcome) in reply("200 OK", ArisMCPRoutes.json(["status": Int(outcome.status), "output": outcome.output])) }
            // A script's card waits for the user inside the agent, never inside the brain's shell command (QA BUG-47 retest):
            // past one command's time the call hands back an id, `skill wait <id>` collects it (ArisSlowCalls).
            if object["op"] as? String == "wait" {
                guard let id = object["id"] as? String, ArisSlowCalls.isID(id) else { return send(.failed("usage: aris-tools skill wait <id>")) }
                return ArisSlowCalls.shared.wait(id: id, owner: credential, kind: "skill", reply: send)
            }
            ArisSlowCalls.shared.run(owner: credential, kind: "skill", work: { done in
                done(ArisSkillTool.answer(object, turn: turn, skills: .live) { title in runner.skillNote(title) })
            }, reply: send)
        }
    }

    // MARK: - The app

    /// POST /skills, after the app was checked to be itself. Off the server queue (a draft takes minutes).
    static func settings(_ object: [String: Any], reply: @escaping (String, Data) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let skills = ArisSkills.live
            let brain = ArisBrain.named(object["brain"] as? String)
            // The app's language, for the lines an AI writes for the page (a review's findings, the maker's questions).
            ArisSkillLanguage.heard(object["lang"])
            let ok = { (extra: [String: Any]) in reply("200 OK", ArisMCPRoutes.json(extra)) }
            let bad = { (why: String) in reply("400 Bad Request", ArisMCPRoutes.json(["error": why])) }
            let audit = { (what: String) in
                ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": what, "question": "skills settings"]), key: "settings")
            }
            let name = object["name"] as? String ?? ""
            switch object["op"] as? String {
            case "status":
                let seen = (object["seen"] as? [String] ?? []).prefix(20).compactMap(UUID.init(uuidString:))
                skills.seen(Array(seen))
                skills.sync()
                ok(skills.status())
            case "feature":
                let on = object["on"] as? Bool == true
                audit("skills \(on ? "on" : "off")")
                skills.setFeature(on, brain: brain)
                ok(skills.status())
            case "defer":
                skills.deferFeature()
                ok(skills.status())
            case "retry":
                skills.setFeature(true, brain: brain)
                ok(skills.status())
            case "add":
                let made = (object["path"] as? String).map { skills.addFolder($0, brain: brain) }
                    ?? skills.addLink(String((object["text"] as? String ?? "").prefix(2_000)), brain: brain, hold: object["hold"] as? Bool == true)
                switch made {
                case .failure(let why): bad(why.message)
                case .success(let id): audit("skill add (\(object["path"] != nil ? "folder" : "link"))"); ok(["job": id.uuidString])
                }
            case "draft":
                let lines = (object["conversation"] as? [[String: Any]] ?? []).suffix(12).map { ((($0["user"] as? Bool) ?? true), String((($0["text"] as? String) ?? "").prefix(2_000))) }
                switch skills.draft(conversation: lines.map { (user: $0.0, text: $0.1) }, editing: object["editing"] as? String, brain: brain) {
                case .ask(let question): ok(["ask": question])
                case .draft(let text): ok(["skill": text])
                case .failed(let why): bad(why)
                }
            case "save":
                switch skills.addDraft(String((object["skill"] as? String ?? "").prefix(ArisSkillFormat.maxSkillFile)), brain: brain) {
                case .failure(let why): bad(why.message)
                case .success(let id): audit("skill made"); ok(["job": id.uuidString])
                }
            case "go":
                guard let id = (object["job"] as? String).flatMap(UUID.init(uuidString:)) else { return bad("job") }
                skills.proceed(id) ? ok(skills.status()) : bad("이미 끝난 일이에요.")
            case "decide":
                guard let id = (object["job"] as? String).flatMap(UUID.init(uuidString:)) else { return bad("job") }
                let accept = object["accept"] as? Bool == true
                audit("skill \(accept ? "added anyway" : "cancelled")")
                skills.decide(id, accept: accept) ? ok(skills.status()) : bad("이미 끝난 일이에요.")
            case "enable":
                skills.setEnabled(name, object["on"] as? Bool == true) ? ok(skills.status()) : bad("그런 스킬이 없어요.")
            case "remove":
                audit("skill removed")
                skills.remove(name) ? ok(skills.status()) : bad("그런 스킬이 없어요.")
            case "try":
                skills.tryAll(name)
                ok(skills.status())
            case "reveal", "edit":
                let target: URL
                if let record = skills.state.record(name) {
                    let folder = skills.folder.appendingPathComponent(record.folder)
                    target = object["op"] as? String == "edit" ? folder.appendingPathComponent(ArisSkillFormat.skillFile) : folder
                } else {
                    try? FileManager.default.createDirectory(at: skills.folder, withIntermediateDirectories: true)
                    target = skills.folder
                }
                let edit = object["op"] as? String == "edit"
                _ = ArisSkillProcess.run("/usr/bin/open", edit ? ["-t", target.path] : ["-R", target.path], environment: ["PATH": "/usr/bin:/bin"], timeout: 10)
                ok([:])
            default:
                bad("op")
            }
        }
    }
}
