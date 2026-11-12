//
//  ArisMCPConfig.swift
//  aris-agent
//
//  The external services the user added in 설정 › 연결된 서비스: Composio (its MCP URL and their own key) and their own MCP
//  servers, a command run over stdio or a URL spoken to over streamable HTTP. Only the app writes this, through
//  POST /mcp (ArisPeer), and every field is checked here. The file holds no secret: keys and tokens live in the Keychain
//  (ArisMCPSecrets), never in a file and never in any brain's context. It sits in ~/.config/aris, outside the folder the
//  brains may read.
//

import CryptoKit
import Foundation
import Security

struct ArisMCPServer: Equatable, Codable {
    enum Transport: String, Codable { case stdio, http }

    /// "composio", or a lowercase UUID.
    let id: String
    /// What the brains call it (`aris-tools mcp call <name> …`) and the settings row shows.
    var name: String
    var transport: Transport
    /// stdio: the program (a name looked up on the agent's PATH, or an absolute path) and its arguments.
    var command: String?
    var arguments: [String]
    /// http: the endpoint.
    var url: String?
    /// Where the secret goes: an HTTP header's name (nil: "Authorization: Bearer …") or, for stdio, an environment
    /// variable's (nil: none is given).
    var secretName: String?
    var enabled: Bool
    /// A secret is saved for it in the Keychain (never the secret itself).
    var hasSecret: Bool

    static let composioId = "composio"
    /// Composio Connect: one MCP URL for every app, the key in this header (docs.composio.dev/docs/composio-connect,
    /// read 2026-11-05: "Auth: API key sent in the x-consumer-api-key header").
    static let composioURL = "https://connect.composio.dev/mcp"
    static let composioHeader = "x-consumer-api-key"

    static func composio(enabled: Bool = true) -> ArisMCPServer {
        ArisMCPServer(id: composioId, name: "composio", transport: .http, command: nil, arguments: [], url: composioURL,
                      secretName: composioHeader, enabled: enabled, hasSecret: true)
    }

    /// What the settings row says it is: the URL's host, or the command line.
    var target: String {
        switch transport {
        case .http: return url.flatMap { URLComponents(string: $0)?.host } ?? ""
        case .stdio: return ([command ?? ""] + arguments).map(ArisMCPTarget.quotedIfNeeded).joined(separator: " ")
        }
    }
}

/// What the user typed in 명령 또는 URL, read as one or the other.
enum ArisMCPTarget: Equatable {
    case http(String)
    case stdio(command: String, arguments: [String])

    static let maxWords = 32
    static let maxWordLength = 1_024

    /// Nil, with why, when it can't be used.
    static func parse(_ text: String) -> Result<ArisMCPTarget, ArisMCPConfigError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.target("명령이나 URL을 넣어 주세요.")) }
        guard !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return .failure(.target("줄바꿈이나 보이지 않는 글자는 넣을 수 없어요."))
        }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return checkURL(trimmed).map { .http($0) }
        }
        guard let words = words(trimmed), let first = words.first else { return .failure(.target("따옴표가 닫히지 않았어요.")) }
        guard words.count <= maxWords, words.allSatisfy({ $0.count <= maxWordLength && !$0.isEmpty }) else {
            return .failure(.target("명령이 너무 길어요."))
        }
        // VAR=value before the program is a shell's job, and no shell runs here.
        guard !first.contains("="), !first.hasPrefix("-") else { return .failure(.target("명령의 첫 단어는 프로그램이어야 해요.")) }
        return .success(.stdio(command: first, arguments: Array(words.dropFirst())))
    }

    /// https anywhere; plain http only to this Mac. No user or password in it, no fragment, at most 2048 characters.
    static func checkURL(_ text: String) -> Result<String, ArisMCPConfigError> {
        guard text.count <= 2_048, let parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(), !host.isEmpty else { return .failure(.target("URL을 읽을 수 없어요.")) }
        guard parts.user == nil, parts.password == nil, parts.fragment == nil else {
            return .failure(.target("URL에 아이디·비밀번호나 # 뒤 부분은 넣을 수 없어요. 토큰은 아래 칸에 넣어 주세요."))
        }
        // A key in the address would be kept in the plain list and shown on the row (M4): it goes in the token field.
        let secretish = ["key", "token", "secret", "auth", "password", "pass", "sig", "signature", "credential", "session", "bearer", "jwt"]
        if parts.queryItems?.contains(where: { item in secretish.contains { item.name.lowercased().contains($0) } }) == true
            || parts.path.split(separator: "/").contains(where: { looksLikeToken(String($0)) }) {
            return .failure(.target("URL에 키나 토큰이 들어 있어요. 그 값은 빼고 아래 토큰 칸에 넣어 주세요 (헤더 이름도 함께)."))
        }
        let local = ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)
        guard scheme == "https" || (scheme == "http" && local) else { return .failure(.target("https 주소만 돼요 (이 Mac 안의 서버는 http도 돼요).")) }
        return .success(text)
    }

    /// A path segment that looks like a key: a known key prefix (sk-, ck_, ghp_, xoxb-…), a long hex run (24+), or a long
    /// base64/base64url run (32+ with digits and letters mixed).
    static func looksLikeToken(_ raw: String) -> Bool {
        let segment = raw.removingPercentEncoding ?? raw
        let lowered = segment.lowercased()
        let prefixes = ["sk-", "sk_", "ck_", "pk_", "rk_", "ghp_", "gho_", "ghs_", "github_pat_", "xoxb-", "xoxp-", "xapp-", "glpat-", "ya29.", "eyj", "ak_",
                        "api_", "key-", "token"]
        if prefixes.contains(where: { lowered.hasPrefix($0) }) && segment.count >= 12 { return true }
        if segment.count >= 24, segment.range(of: #"^[0-9a-fA-F]+$"#, options: .regularExpression) != nil { return true }
        // A plain UUID names a server, not a key.
        if UUID(uuidString: segment) != nil { return false }
        if segment.count >= 32, segment.range(of: #"^[A-Za-z0-9+/_=-]+$"#, options: .regularExpression) != nil,
           segment.contains(where: \.isNumber), segment.contains(where: \.isLetter) { return true }
        return false
    }

    /// Shell-like words: spaces split, "…" and '…' group, \ escapes the next character. Nil for an open quote.
    static func words(_ text: String) -> [String]? {
        var words: [String] = [], current = "", quote: Character?, escaped = false, inWord = false
        for character in text {
            if escaped { current.append(character); escaped = false; inWord = true; continue }
            if character == "\\" && quote != "'" { escaped = true; inWord = true; continue }
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
                continue
            }
            if character == "\"" || character == "'" { quote = character; inWord = true; continue }
            if character == " " || character == "\t" {
                if inWord { words.append(current) }
                current = ""
                inWord = false
                continue
            }
            current.append(character)
            inWord = true
        }
        guard quote == nil, !escaped else { return nil }
        if inWord { words.append(current) }
        return words
    }

    static func quotedIfNeeded(_ word: String) -> String {
        word.isEmpty || word.contains(where: { " \"'\\\t".contains($0) }) ? "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'" : word
    }
}

enum ArisMCPConfigError: Error, Equatable {
    case name(String), target(String), secret(String), secretName(String), full, missing

    var message: String {
        switch self {
        case .name(let why), .target(let why), .secret(let why), .secretName(let why): return why
        case .full: return "서비스는 \(ArisMCPConfig.maxServers)개까지 넣을 수 있어요."
        case .missing: return "그 서비스를 찾지 못했어요."
        }
    }
}

enum ArisMCPConfig {
    static let maxServers = 20

    /// ~/.config/aris/mcp-servers.json: beside the token, outside the folder the brains may read (aris/).
    static var defaultFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/mcp-servers.json")
    }

    /// A name the brains type: a letter or digit, then letters, digits, - and _, at most 32. Stored lowercased.
    static func checkName(_ raw: String) -> Result<String, ArisMCPConfigError> {
        let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard name.range(of: #"^[a-z0-9][a-z0-9_-]{0,31}$"#, options: .regularExpression) != nil else {
            return .failure(.name("이름은 영어 소문자·숫자·-·_로 32자까지예요 (예: slack, my-notes)."))
        }
        return .success(name)
    }

    /// A key or token: one line, no spaces, at most 4096 characters.
    static func checkSecret(_ raw: String) -> Result<String, ArisMCPConfigError> {
        let secret = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { return .failure(.secret("키를 넣어 주세요.")) }
        guard secret.count <= 4_096, !secret.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else {
            return .failure(.secret("키에 띄어쓰기나 줄바꿈이 들어 있어요. 키만 붙여 넣어 주세요."))
        }
        return .success(secret)
    }

    /// Headers the agent sets itself, which a secret may not take over.
    private static let reservedHeaders: Set<String> = ["host", "content-length", "content-type", "accept", "mcp-session-id",
                                                       "mcp-protocol-version", "connection", "transfer-encoding", "cookie",
                                                       "user-agent", "last-event-id"]
    /// Variables the program needs as they are, or that would change what it loads.
    private static let reservedVariables: Set<String> = ["PATH", "HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "PWD",
                                                         "NODE_OPTIONS", "PYTHONPATH", "PYTHONSTARTUP", "RUBYOPT", "PERL5OPT", "BASH_ENV", "ENV"]

    /// Where the secret goes: an HTTP header name, or an environment variable for a command. Nil: the default.
    static func checkSecretName(_ raw: String?, transport: ArisMCPServer.Transport) -> Result<String?, ArisMCPConfigError> {
        guard let name = raw?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return .success(nil) }
        switch transport {
        case .http:
            guard name.range(of: #"^[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil, !reservedHeaders.contains(name.lowercased()) else {
                return .failure(.secretName("헤더 이름은 영어·숫자·-로 64자까지예요 (예: Authorization, x-api-key)."))
            }
        case .stdio:
            guard name.range(of: #"^[A-Z_][A-Z0-9_]{0,63}$"#, options: .regularExpression) != nil, !reservedVariables.contains(name),
                  !name.hasPrefix("DYLD_"), !name.hasPrefix("LD_"), !name.hasPrefix("ARIS_") else {
                return .failure(.secretName("환경 변수 이름은 영어 대문자·숫자·_예요 (예: GITHUB_TOKEN)."))
            }
        }
        return .success(name)
    }

    /// A new or changed server from what the settings sent; `existing`: the list as it is (names stay unique).
    static func server(id: String, name rawName: String, target rawTarget: String, secretName rawSecretName: String?, hasSecret: Bool,
                       enabled: Bool, existing: [ArisMCPServer]) -> Result<ArisMCPServer, ArisMCPConfigError> {
        let name: String
        switch checkName(rawName) {
        case .failure(let error): return .failure(error)
        case .success(let checked): name = checked
        }
        guard !existing.contains(where: { $0.name == name && $0.id != id }) else { return .failure(.name("같은 이름의 서비스가 이미 있어요.")) }
        guard id != ArisMCPServer.composioId || name == "composio" else { return .failure(.name("Composio의 이름은 바꿀 수 없어요.")) }
        guard id == ArisMCPServer.composioId || name != "composio" else { return .failure(.name("composio는 Composio 키 자리의 이름이에요.")) }
        let target: ArisMCPTarget
        switch ArisMCPTarget.parse(rawTarget) {
        case .failure(let error): return .failure(error)
        case .success(let parsed): target = parsed
        }
        let transport: ArisMCPServer.Transport
        switch target {
        case .http: transport = .http
        case .stdio: transport = .stdio
        }
        let secretName: String?
        switch checkSecretName(rawSecretName, transport: transport) {
        case .failure(let error): return .failure(error)
        case .success(let checked): secretName = checked
        }
        switch target {
        case .http(let url):
            return .success(ArisMCPServer(id: id, name: name, transport: .http, command: nil, arguments: [], url: url, secretName: secretName,
                                          enabled: enabled, hasSecret: hasSecret))
        case .stdio(let command, let arguments):
            return .success(ArisMCPServer(id: id, name: name, transport: .stdio, command: command, arguments: arguments, url: nil,
                                          secretName: secretName, enabled: enabled, hasSecret: hasSecret))
        }
    }

    /// An id for a new server.
    static func newId() -> String { UUID().uuidString.lowercased() }

    static func isId(_ text: String) -> Bool {
        text == ArisMCPServer.composioId || (UUID(uuidString: text) != nil && text == text.lowercased())
    }
}

/// The server list on disk (0600, written whole and atomically). A file that can't be read is an empty list, never
/// a partial one; servers that don't pass the checks are dropped.
final class ArisMCPStore {
    let file: URL
    private let secrets: ArisMCPSecretStore
    private let lock = NSLock()
    /// The Keychain account of the key that signs the list (security review I5): not a server id, so never removed with one.
    static let signingKey = "config-hmac"

    /// What's on disk: the servers, and an HMAC-SHA256 of their JSON under a key kept in the Keychain.
    private struct Signed: Codable {
        let servers: [ArisMCPServer]
        let mac: String
    }

    init(file: URL = ArisMCPConfig.defaultFile, secrets: ArisMCPSecretStore) {
        self.file = file
        self.secrets = secrets
    }

    /// The list on disk was changed by something other than Aris (its signature doesn't match, or its key is gone): no
    /// server in it starts until the user saves the list again in settings.
    private(set) var tampered = false
    /// The Keychain couldn't be read just now, so the list's signature can't be checked: no server starts, but nothing
    /// is wrong with the list. It is not called tampering, it isn't saved over, and no saved token is removed until the
    /// Keychain can be read again (audit mcp-3).
    private(set) var unreadable = false
    static let unreadableSave = "키체인을 읽지 못해서 저장하지 않았어요. Mac의 잠금을 풀고 키체인 접근을 허용한 뒤 다시 해 주세요. 저장된 서비스와 키는 그대로예요."

    func load() -> [ArisMCPServer] {
        lock.withLock { read() }
    }

    static func mac(_ data: Data, key: Data) -> String {
        HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)).map { String(format: "%02x", $0) }.joined()
    }

    /// The signing key as the Keychain has it: found, not there, or a Keychain that couldn't be read.
    static func storedKey(_ secrets: ArisMCPSecretStore, account: String) -> (key: Data?, unreadable: Bool) {
        switch secrets.lookup(account) {
        case .found(let hex): return (Data(hex: hex).flatMap { $0.count == 32 ? $0 : nil }, false)
        case .missing: return (nil, false)
        case .unreadable: return (nil, true)
        }
    }

    private func key(creating: Bool) -> Data? {
        let stored = Self.storedKey(secrets, account: Self.signingKey)
        if let key = stored.key { return key }
        // A key is made only when there is none: never over one that just couldn't be read.
        guard creating, !stored.unreadable else { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        guard secrets.save(hex, for: Self.signingKey) == nil else { return nil }
        return Data(bytes)
    }

    private func read() -> [ArisMCPServer] {
        unreadable = false
        guard let data = try? Data(contentsOf: file) else { tampered = false; return [] }
        let stored = Self.storedKey(secrets, account: Self.signingKey)
        guard !stored.unreadable else {
            tampered = false
            unreadable = true
            return []
        }
        guard data.count < 1_000_000, let signed = try? JSONDecoder().decode(Signed.self, from: data),
              let body = try? Self.encoder.encode(signed.servers), let key = stored.key,
              ArisMCPTurnCredential.same(Self.mac(body, key: key), signed.mac) else {
            tampered = true
            return []
        }
        tampered = false
        var seen: Set<String> = []
        return signed.servers.filter { server in
            guard ArisMCPConfig.isId(server.id), seen.insert(server.name).inserted, seen.insert("id:" + server.id).inserted,
                  case .success(let checked) = ArisMCPConfig.server(id: server.id, name: server.name, target: Self.targetText(server),
                                                                    secretName: server.secretName, hasSecret: server.hasSecret,
                                                                    enabled: server.enabled, existing: []),
                  checked == server else { return false }
            return true
        }.prefix(ArisMCPConfig.maxServers).map { $0 }
    }

    /// Every saved secret but the signing key and those of `keeping` is removed from the Keychain.
    private func removeOrphans(keeping: Set<String>) {
        for account in secrets.accounts() where account != Self.signingKey && !keeping.contains(account) { secrets.delete(account) }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// What `parse` reads back into the same server.
    static func targetText(_ server: ArisMCPServer) -> String {
        switch server.transport {
        case .http: return server.url ?? ""
        case .stdio: return ([server.command ?? ""] + server.arguments).map(ArisMCPTarget.quotedIfNeeded).joined(separator: " ")
        }
    }

    /// Applies `change` to the list and writes it; the result of `change`, or why nothing was written.
    func update<T>(_ change: (inout [ArisMCPServer]) -> Result<T, ArisMCPConfigError>) -> Result<T, ArisMCPConfigError> {
        lock.withLock {
            var servers = read()
            // The list couldn't be checked, so it isn't the empty list it looks like: nothing is saved over it.
            guard !unreadable else { return .failure(.target(Self.unreadableSave)) }
            // A list changed outside Aris starts over from nothing: the secrets of the servers it held go (once saved).
            let wasTampered = tampered
            let result = change(&servers)
            guard case .success = result else { return result }
            guard servers.count <= ArisMCPConfig.maxServers else { return .failure(.full) }
            do {
                let folder = file.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                guard let key = key(creating: true) else { return .failure(.target("키체인에 서명 키를 만들지 못해서 저장하지 않았어요.")) }
                let body = try Self.encoder.encode(servers)
                let data = try Self.encoder.encode(Signed(servers: servers, mac: Self.mac(body, key: key)))
                try data.write(to: file, options: [.atomic])
                tampered = false
                if wasTampered { removeOrphans(keeping: Set(servers.map(\.id))) }
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            } catch {
                return .failure(.target("서비스 목록을 저장하지 못했어요."))
            }
            return result
        }
    }
}

extension Data {
    /// Lowercase or uppercase hex; nil for anything else.
    init?(hex: String) {
        guard hex.count % 2 == 0, hex.allSatisfy(\.isHexDigit) else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
