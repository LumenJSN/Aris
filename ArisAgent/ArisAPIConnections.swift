//
//  ArisAPIConnections.swift
//  aris-agent
//
//  다른 AI 연결… (settings › AI 서비스): an address of the user's own that speaks OpenAI's chat protocol (a provider Aris
//  doesn't ship, a server on this Mac) becomes an API brain like the shipped ones. A connection is its name and address,
//  kept in the same signed api-brains.json; its key lives only in the Keychain under the connection's id. The rules are
//  the shipped providers' (security review C1): a key only ever goes over https to the connection's own host, and an
//  address without a key must be this Mac. POST /api-brains (ArisAPIRoutes hands these ops on; the Aris app only):
//
//    "probe" {"base", "key"?, "id"?}                 ->  {"ok": bool, "models": [id]}   (GET {base}/models; nothing saved)
//    "connect" {"id"?, "name"?, "base", "key"?, "model", "activate"?}  ->  {"id"} or {"error"} (400)
//    "disconnect" {"id"}                             ->  {}
//

import Foundation

/// One address the user added.
struct ArisAPIConnection: Codable, Equatable, Sendable {
    /// "conn-" and eight hex digits: never a shipped provider's id.
    let id: String
    var name: String
    var base: String

    static let prefix = "conn-"
    /// The most connections kept.
    static let most = 12

    static func isID(_ id: String) -> Bool { id.range(of: #"^conn-[0-9a-f]{8}$"#, options: .regularExpression) != nil }

    static func newID() -> String {
        prefix + (0..<4).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    /// The address as it is kept (no trailing slash), or nil when it may not be used: https to any host, or http(s) to
    /// this Mac; no user, password, query or fragment.
    static func checkBase(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 200, !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        let onThisMac = ArisAPIPreset.loopbackHosts.contains(host)
        guard scheme == "https" || (scheme == "http" && onThisMac) else { return nil }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    /// The name as it is kept: one short line.
    static func checkName(_ text: String) -> String? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40, !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        return name
    }

    static func host(_ base: String) -> String? { URL(string: base)?.host?.lowercased() }

    /// A server on this Mac: no key, and nothing leaves.
    var local: Bool { Self.host(base).map(ArisAPIPreset.loopbackHosts.contains) ?? false }

    var isValid: Bool { Self.isID(id) && Self.checkBase(base) == base && Self.checkName(name) == name }

    /// The connection as a provider: OpenAI's chat protocol at its address; a key unless it is this Mac.
    var preset: ArisAPIPreset {
        ArisAPIPreset(id: id, title: name, dialect: .openAIChat, baseURL: base, needsKey: !local, headers: [:], keySource: "", quick: "", strong: "",
                      curated: [], vision: false)
    }
}

/// The saved connections as providers, for ArisAPIPreset.named: set whenever the signed list is read (ArisAPIStore), so
/// a connection is a provider only while Aris's own file says so.
enum ArisAPICustomPresets {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var known: [String: ArisAPIPreset] = [:]

    static func set(_ connections: [ArisAPIConnection]) {
        let next = Dictionary(connections.map { ($0.id, $0.preset) }, uniquingKeysWith: { first, _ in first })
        lock.withLock { known = next }
    }

    static func preset(_ id: String) -> ArisAPIPreset? { lock.withLock { known[id] } }
}

enum ArisAPIConnectionRoutes {
    /// GET `request`, then its body (nil: no answer, or not a 200). The tests hand in a fake.
    typealias Fetch = (URLRequest, @escaping (Data?) -> Void) -> Void

    static let needsKeyLine = "클라우드 주소는 API 키가 필요해요."
    static let badBaseLine = "https:// 주소나, 이 Mac의 http:// 주소(127.0.0.1 또는 localhost)만 쓸 수 있어요."

    /// One row per connection for the settings list (never a key).
    static func rows(_ brains: ArisAPIBrains, secrets: ArisMCPSecretStore) -> [[String: Any]] {
        (brains.connections ?? []).map { connection in
            ["id": connection.id, "name": connection.name, "base": connection.base, "local": connection.local,
             "hasKey": secrets.secret(for: connection.id) != nil, "model": brains.profile(connection.id)?.strong ?? ""]
        }
    }

    /// The key a request to `base` carries: the one typed; else, while changing a saved connection whose host is still
    /// the same, its saved key (a key never follows a connection to another host). `.failure`: what to tell the user.
    static func key(for base: String, typed: String?, editing id: String?, brains: ArisAPIBrains, secrets: ArisMCPSecretStore) -> Result<String?, ArisAPIConnectionProblem> {
        let local = ArisAPIConnection(id: "", name: "", base: base).local
        if let typed, !typed.isEmpty {
            guard !local else { return .success(nil) }
            guard let checked = ArisAPISecrets.check(typed) else { return .failure(.init(text: "키 모양이 맞지 않아요. 다시 붙여 넣어 주세요.")) }
            return .success(checked)
        }
        if local { return .success(nil) }
        if let id, let saved = brains.connections?.first(where: { $0.id == id }), ArisAPIConnection.host(saved.base) == ArisAPIConnection.host(base),
           let key = secrets.secret(for: id) {
            return .success(key)
        }
        return .failure(.init(text: needsKeyLine))
    }

    static func modelsRequest(base: String, key: String?) -> URLRequest? {
        guard let url = URL(string: base + "/models") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        ArisAPIDialects.authorize(&request, dialect: .openAIChat, key: key)
        return request
    }

    static func settings(_ object: [String: Any], store: ArisAPIStore, secrets: ArisMCPSecretStore, changed: @escaping () -> Void,
                         fetch: @escaping Fetch = liveFetch, reply: @escaping (String, Data) -> Void) {
        let ok = { (body: Any) in reply("200 OK", ArisAPIRoutes.json(body)) }
        let bad = { (message: String) in reply("400 Bad Request", ArisAPIRoutes.json(["error": message])) }
        let id = object["id"] as? String
        switch object["op"] as? String {
        case "probe":
            guard let base = ArisAPIConnection.checkBase(object["base"] as? String ?? "") else { return bad(badBaseLine) }
            let key: String?
            switch Self.key(for: base, typed: object["key"] as? String, editing: id, brains: store.load(), secrets: secrets) {
            case .failure(let problem): return bad(problem.text)
            case .success(let found): key = found
            }
            guard let request = modelsRequest(base: base, key: key) else { return bad(badBaseLine) }
            fetch(request) { data in
                let models = data.flatMap { ArisAPIModels.parse($0, dialect: .openAIChat) }?.map(\.id) ?? []
                ok(["ok": !models.isEmpty, "models": Array(models.prefix(500))])
            }
        case "connect":
            guard let base = ArisAPIConnection.checkBase(object["base"] as? String ?? "") else { return bad(badBaseLine) }
            let brains = store.load()
            if let id { guard brains.connections?.contains(where: { $0.id == id }) == true else { return bad("모르는 연결이에요.") } }
            guard id != nil || (brains.connections ?? []).count < ArisAPIConnection.most else { return bad("연결은 \(ArisAPIConnection.most)개까지 둘 수 있어요.") }
            let typedName = (object["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name = ArisAPIConnection.checkName(typedName.isEmpty ? ArisAPIConnection.host(base) ?? "" : typedName) else { return bad("이름을 40자 안으로 적어 주세요.") }
            guard let model = ArisAPIRoutes.checkModel(object["model"] as? String ?? ""), !model.isEmpty else { return bad("모델 이름을 적어 주세요.") }
            let typed = object["key"] as? String
            let key: String?
            switch Self.key(for: base, typed: typed, editing: id, brains: brains, secrets: secrets) {
            case .failure(let problem): return bad(problem.text)
            case .success(let found): key = found
            }
            let connection = ArisAPIConnection(id: id ?? ArisAPIConnection.newID(), name: name, base: base)
            if let key {
                if let problem = secrets.save(key, for: connection.id) { return bad(problem) }
            } else {
                // This Mac's server: a key saved for the address it had before is not kept.
                secrets.delete(connection.id)
            }
            let old = brains.profile(connection.id)
            let profile = ArisAPIProfile(id: connection.id, quick: model, strong: model, baseURL: nil, vision: old?.vision, tools: old?.tools)
            let activate = object["activate"] as? Bool == true
            if let problem = store.update({ current in
                var next = current
                next.connections = (current.connections ?? []).filter { $0.id != connection.id } + [connection]
                next.profiles = current.profiles.filter { $0.id != connection.id } + [profile]
                if activate { next.active = connection.id }
                return next
            }) { return bad(problem) }
            changed()
            ok(["id": connection.id])
        case "disconnect":
            guard let id, ArisAPIConnection.isID(id) else { return bad("모르는 연결이에요.") }
            secrets.delete(id)
            if let problem = store.update({ current in
                var next = current.removing(id)
                let left = (current.connections ?? []).filter { $0.id != id }
                next.connections = left.isEmpty ? nil : left
                return next
            }) { return bad(problem) }
            changed()
            ok([String: Any]())
        default:
            bad("unknown op")
        }
    }

    /// The real GET: read as it arrives, never past a redirect, given up after 10 s (ArisAPIStreamTask's own limits).
    static func liveFetch(_ request: URLRequest, done: @escaping (Data?) -> Void) {
        let holder = ArisAPIOneShotHolder()
        var body: String?
        let task = ArisAPIStreamTask(request: request, totalTimeout: 10, idleTimeout: 10, queue: DispatchQueue(label: "com.lumenjsn.aris.api-probe"),
                                     onEvents: { events in body = events.first { $0.name == "json" }?.data ?? body },
                                     onDone: { error in
            holder.task = nil
            done(error == nil ? body?.data(using: .utf8) : nil)
        })
        holder.task = task
        task.start()
    }
}

struct ArisAPIConnectionProblem: Error, Equatable {
    let text: String
}
