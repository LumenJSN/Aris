//
//  ArisAPIRoutes.swift
//  aris-agent
//
//  POST /api-brains {"op", …, "pid", "started"} (the Aris app itself only, ArisPeer): settings' AI 서비스 › 두뇌 rows for
//  the API brains. The app sends what the user typed once and only ever hears back whether a key is saved, never the key.
//
//    "list"                                   ->  {"presets": [...], "profiles": [...], "active"?, "tested": [...], "problem"?}
//    "save" {"id", "key"?, "quick"?, "strong"?, "baseURL"?, "activate"?}  ->  {"profile": row} or {"error"} (400)
//            (key: a new key, "" removes it, absent keeps it; it goes to the Keychain, never back)
//    "activate" {"id"}  |  "remove" {"id"}       ->  {} or {"error"}
//    "models" {"id"}                           ->  {"models": [{"id", "vision", "tools"}], "fromProvider": bool}
//    "test" {"id", "model"?}                   ->  {"ok", "passed", "failed", "message"}  (the smoke check; nothing runs)
//

import Foundation

enum ArisAPIRoutes {
    static func json(_ object: Any) -> Data { (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8) }

    static func presetRow(_ preset: ArisAPIPreset) -> [String: Any] {
        ["id": preset.id, "title": preset.title, "needsKey": preset.needsKey, "keySource": preset.keySource, "local": preset.local,
         "baseURL": preset.baseURL, "quick": preset.quick, "strong": preset.strong]
    }

    /// `unchecked`: its key is saved and has never answered (ArisAPIBrains.neverAnswered).
    static func profileRow(_ profile: ArisAPIProfile, secrets: ArisMCPSecretStore, unchecked: Bool = false) -> [String: Any] {
        let hasKey = secrets.secret(for: profile.id) != nil
        var row: [String: Any] = ["id": profile.id, "quick": profile.quick, "strong": profile.strong,
                                  "hasKey": hasKey, "vision": profile.takesImages, "tools": profile.callsTools]
        if hasKey, unchecked { row["unchecked"] = true }
        if let base = profile.baseURL { row["baseURL"] = base }
        return row
    }

    /// One settings request; `reply` is called once, off the server queue for anything that waits on the network.
    /// `changed`: an API profile changed, so the API brain's processes start again with it.
    static func settings(_ object: [String: Any], store: ArisAPIStore = ArisAPISecrets.store, secrets: ArisMCPSecretStore = ArisAPISecrets.live,
                         strictOrigin: Bool = true,
                         changed: @escaping () -> Void = {}, audit: @escaping ([String: String]) -> Void = { _ in },
                         smoke: @escaping (ArisAPIProfile, String, String?) -> ArisAPISmoke.Outcome = { ArisAPISmoke.run(profile: $0, model: $1, key: $2) },
                         reply: @escaping (String, Data) -> Void) {
        let ok = { (body: Any) in reply("200 OK", json(body)) }
        let bad = { (message: String) in reply("400 Bad Request", json(["error": message])) }
        let id = object["id"] as? String ?? ""
        switch object["op"] as? String {
        case "list":
            let brains = store.load()
            var body: [String: Any] = ["presets": ArisAPIPreset.all.map(presetRow), "profiles": brains.profiles.map { profileRow($0, secrets: secrets, unchecked: brains.neverAnswered($0.id)) },
                                       "tested": brains.tested.map { ["profile": $0.profile, "model": $0.model, "at": $0.at.timeIntervalSince1970,
                                                                      "passed": $0.passed, "failed": $0.failed] }]
            if let active = brains.active { body["active"] = active }
            body["connections"] = ArisAPIConnectionRoutes.rows(brains, secrets: secrets)
            if store.tampered { body["problem"] = "API 브레인 설정 파일이 Aris 밖에서 바뀌어서 쓰지 않아요. 다시 저장해 주세요." }
            if store.unreadable { body["problem"] = ArisAPIStore.unreadableLine }
            ok(body)
        case "save":
            guard let preset = ArisAPIPreset.named(id) else { return bad("모르는 서비스예요.") }
            let existing = store.load().profile(id)
            var profile = existing ?? ArisAPIProfile(id: id, quick: preset.quick, strong: preset.strong, baseURL: nil, vision: nil, tools: nil)
            if let quick = object["quick"] as? String {
                guard let model = checkModel(quick) else { return bad("모델 이름이 맞지 않아요.") }
                profile.quick = model
            }
            if let strong = object["strong"] as? String {
                guard let model = checkModel(strong) else { return bad("모델 이름이 맞지 않아요.") }
                profile.strong = model
            }
            if profile.quick.isEmpty { profile.quick = profile.strong }
            if profile.strong.isEmpty { profile.strong = profile.quick }
            if let base = object["baseURL"] as? String {
                guard preset.local else { return bad("이 서비스는 주소를 바꿀 수 없어요.") }
                if base.trimmingCharacters(in: .whitespaces).isEmpty { profile.baseURL = nil } else {
                    guard let checked = ArisAPIPreset.checkLocalBase(base) else { return bad("이 Mac의 주소(127.0.0.1 또는 localhost)만 쓸 수 있어요.") }
                    profile.baseURL = checked == preset.baseURL ? nil : checked
                }
            }
            if let vision = object["vision"] as? Bool { profile.vision = vision }
            if let tools = object["tools"] as? Bool { profile.tools = tools }
            if let key = object["key"] as? String {
                guard preset.needsKey else { return bad("이 서비스는 키가 없어도 돼요.") }
                if key.isEmpty {
                    secrets.delete(id)
                } else {
                    guard let checked = ArisAPISecrets.check(key) else { return bad("키 모양이 맞지 않아요. 다시 붙여 넣어 주세요.") }
                    if let problem = secrets.save(checked, for: id) { return bad(problem) }
                }
            }
            let activate = object["activate"] as? Bool == true
            // A key that was just given has not answered yet: it starts as needing its check.
            let newKey = (object["key"] as? String).map { !$0.isEmpty } ?? false
            if let problem = store.update({ brains in
                var next = brains.saving(profile)
                if activate { next.active = id }
                return newKey ? next.withNewKey(id, model: profile.quick, at: Date()) : next
            }) { return bad(problem) }
            if newKey { ArisAPIActive.keySaved(id) }
            changed()
            ok(["profile": profileRow(profile, secrets: secrets)])
        case "activate":
            guard store.load().profile(id) != nil else { return bad("먼저 저장해 주세요.") }
            if let problem = store.update({ var next = $0; next.active = id; return next }) { return bad(problem) }
            changed()
            ok([String: Any]())
        case "remove":
            guard ArisAPIPreset.named(id) != nil else { return bad("모르는 서비스예요.") }
            secrets.delete(id)
            if let problem = store.update({ $0.removing(id) }) { return bad(problem) }
            changed()
            ok([String: Any]())
        case "models":
            guard let preset = ArisAPIPreset.named(id) else { return bad("모르는 서비스예요.") }
            let profile = store.load().profile(id) ?? ArisAPIProfile(id: id, quick: preset.quick, strong: preset.strong, baseURL: nil, vision: nil, tools: nil)
            ArisAPIModels.fetch(profile: profile, key: preset.needsKey ? secrets.secret(for: id) : nil, strictOrigin: strictOrigin) { models, fromProvider in
                ok(["models": models.map { model -> [String: Any] in
                    let can = ArisAPIModels.capabilities(preset: preset, model: model)
                    return ["id": model.id, "vision": can.vision, "tools": can.tools]
                }, "fromProvider": fromProvider])
            }
        case "test":
            // "active": the profile that answers now (the status line's "check again" names no service).
            let id = object["active"] as? Bool == true ? store.load().active ?? "" : id
            guard let profile = store.load().profile(id) else { return bad("먼저 저장해 주세요.") }
            let model = (object["model"] as? String).flatMap(checkModel) ?? profile.quick
            let key = profile.preset?.needsKey == true ? secrets.secret(for: id) : nil
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = smoke(profile, model, key)
                _ = store.update { $0.recording(ArisAPITested(profile: id, model: model, at: Date(), passed: outcome.passed, failed: outcome.failed)) }
                // A model that can't call functions is switched to the text relay (never locked out).
                if outcome.failed.contains("tool"), outcome.passed.contains("stream"), profile.tools == nil {
                    var relayed = profile
                    relayed.tools = false
                    _ = store.update { $0.saving(relayed) }
                    changed()
                }
                audit(["answer": "api brain tested", "question": "\(id) \(model)", "passed": outcome.passed.joined(separator: ","),
                       "failed": outcome.failed.joined(separator: ",")])
                ok(["ok": outcome.ok, "passed": outcome.passed, "failed": outcome.failed,
                    "message": outcome.ok ? "잘 돼요." : ArisAPISecrets.redacted(outcome.message)])
            }
        default:
            // 다른 AI 연결…: "probe", "connect", "disconnect" (ArisAPIConnections).
            ArisAPIConnectionRoutes.settings(object, store: store, secrets: secrets, changed: changed, reply: reply)
        }
    }

    /// A model name as the user typed or picked it: a provider's id (letters, digits and . _ - : / @ +).
    static func checkModel(_ raw: String) -> String? {
        let model = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.count <= 200, model.range(of: #"^[A-Za-z0-9._:/@+\-]*$"#, options: .regularExpression) != nil else { return nil }
        return model
    }
}
