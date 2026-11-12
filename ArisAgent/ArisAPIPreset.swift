//
//  ArisAPIPreset.swift
//  aris-agent
//
//  The API brains (cleanroom spec 14, §3.6): one preset per provider (pure data: its wire dialect, base address, headers,
//  where to get a key, default and curated models) and the profile the user saves for it (the models picked, what the model
//  can do), kept with no secret in ~/.config/aris/api-brains.json (beside the MCP list, outside the folder the brains
//  may read), signed like it (an HMAC key in the Keychain). The key itself is only ever in the Keychain (ArisAPISecrets).
//

import CryptoKit
import Foundation

/// How a provider speaks (ArisAPIDialects).
enum ArisAPIDialect: String, Codable, Sendable {
    /// OpenAI-compatible Chat Completions (OpenAI, OpenRouter, Groq, xAI, Mistral, DeepSeek, Ollama, LM Studio).
    case openAIChat = "openai-chat"
    /// Anthropic Messages.
    case anthropic
    /// Google's Gemini API (AI Studio), native `streamGenerateContent`.
    case gemini
}

struct ArisAPIPreset: Equatable, Sendable {
    let id: String
    let title: String
    let dialect: ArisAPIDialect
    let baseURL: String
    /// False for a local server (Ollama, LM Studio): no key, and the base address may be changed (loopback only).
    let needsKey: Bool
    /// Extra headers every request carries (OpenRouter's app attribution).
    let headers: [String: String]
    /// Where the user gets a key (the settings row's hint).
    let keySource: String
    let quick: String
    let strong: String
    /// The models offered when the provider has no list endpoint or it can't be reached.
    let curated: [String]
    /// The models usually take images (a profile can say otherwise).
    let vision: Bool

    var local: Bool { !needsKey }

    static let all: [ArisAPIPreset] = [
        ArisAPIPreset(id: "openai", title: "OpenAI", dialect: .openAIChat, baseURL: "https://api.openai.com/v1", needsKey: true, headers: [:],
                      keySource: "platform.openai.com › API keys", quick: "gpt-6-luna", strong: "gpt-6.1-sol",
                      curated: ["gpt-6-luna", "gpt-6.1-sol"], vision: true),
        ArisAPIPreset(id: "anthropic", title: "Anthropic", dialect: .anthropic, baseURL: "https://api.anthropic.com/v1", needsKey: true,
                      headers: [:], keySource: "console.anthropic.com › API Keys", quick: "claude-haiku-4-5", strong: "claude-sonnet-4-5",
                      curated: ["claude-haiku-4-5", "claude-sonnet-4-5"], vision: true),
        ArisAPIPreset(id: "gemini", title: "Gemini API", dialect: .gemini, baseURL: "https://generativelanguage.googleapis.com/v1beta",
                      needsKey: true, headers: [:], keySource: "aistudio.google.com › Get API key", quick: "gemini-flash-latest",
                      strong: "gemini-pro-latest", curated: ["gemini-flash-latest", "gemini-pro-latest"], vision: true),
        ArisAPIPreset(id: "openrouter", title: "OpenRouter", dialect: .openAIChat, baseURL: "https://openrouter.ai/api/v1", needsKey: true,
                      headers: ["X-Title": "Aris"],
                      keySource: "openrouter.ai › Keys", quick: "openai/gpt-oss-120b", strong: "anthropic/claude-sonnet-4.5",
                      curated: ["openai/gpt-oss-120b", "anthropic/claude-sonnet-4.5", "google/gemini-2.5-flash"], vision: false),
        ArisAPIPreset(id: "groq", title: "Groq", dialect: .openAIChat, baseURL: "https://api.groq.com/openai/v1", needsKey: true, headers: [:],
                      keySource: "console.groq.com › API Keys", quick: "llama-3.3-70b-versatile", strong: "openai/gpt-oss-120b",
                      curated: ["llama-3.3-70b-versatile", "openai/gpt-oss-120b"], vision: false),
        ArisAPIPreset(id: "xai", title: "xAI", dialect: .openAIChat, baseURL: "https://api.x.ai/v1", needsKey: true, headers: [:],
                      keySource: "console.x.ai › API Keys", quick: "grok-4-fast", strong: "grok-4", curated: ["grok-4-fast", "grok-4"], vision: true),
        ArisAPIPreset(id: "mistral", title: "Mistral", dialect: .openAIChat, baseURL: "https://api.mistral.ai/v1", needsKey: true, headers: [:],
                      keySource: "console.mistral.ai › API Keys", quick: "mistral-small-latest", strong: "mistral-large-latest",
                      curated: ["mistral-small-latest", "mistral-large-latest"], vision: false),
        ArisAPIPreset(id: "deepseek", title: "DeepSeek", dialect: .openAIChat, baseURL: "https://api.deepseek.com/v1", needsKey: true, headers: [:],
                      keySource: "platform.deepseek.com › API keys", quick: "deepseek-chat", strong: "deepseek-chat", curated: ["deepseek-chat"],
                      vision: false),
        ArisAPIPreset(id: "ollama", title: "Ollama (이 Mac)", dialect: .openAIChat, baseURL: "http://127.0.0.1:11434/v1", needsKey: false,
                      headers: [:], keySource: "ollama.com에서 설치한 뒤 `ollama pull qwen3:8b`", quick: "qwen3:8b", strong: "qwen3:8b",
                      curated: ["qwen3:8b"], vision: false),
        ArisAPIPreset(id: "lmstudio", title: "LM Studio (이 Mac)", dialect: .openAIChat, baseURL: "http://127.0.0.1:1234/v1", needsKey: false,
                      headers: [:], keySource: "LM Studio › Developer › Start Server", quick: "", strong: "", curated: [], vision: false),
    ]

    /// A shipped provider, or a connection the user added (ArisAPIConnections: known once the signed list is read).
    static func named(_ id: String) -> ArisAPIPreset? { all.first { $0.id == id } ?? ArisAPICustomPresets.preset(id) }

    static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]

    /// Whether a request to `url` may carry this provider's key (security review C1): a keyed provider only over https
    /// to its own host; a local server only on this Mac (http allowed there).
    func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), url.user == nil, url.password == nil else { return false }
        if needsKey { return scheme == "https" && host == URL(string: baseURL)?.host?.lowercased() }
        return ["http", "https"].contains(scheme) && Self.loopbackHosts.contains(host)
    }

    /// A base address the user may give a local preset: http(s) on this Mac only (never another host: a key-less request
    /// still carries the user's words). Nil when it isn't one.
    static func checkLocalBase(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 200, let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), loopbackHosts.contains(host), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }
}

/// What the user saved for one provider. The secret isn't here (ArisAPISecrets, account = `id`).
struct ArisAPIProfile: Codable, Equatable, Sendable {
    /// The preset's id (one profile per provider).
    let id: String
    var quick: String
    var strong: String
    /// A local preset's own address (nil: the preset's).
    var baseURL: String?
    /// The model takes images (nil: the preset's guess, ArisAPIModels.capabilities).
    var vision: Bool?
    /// The model calls functions; false: the text relay (an ```aris-run block, ArisAgyRelay's protocol).
    var tools: Bool?

    var preset: ArisAPIPreset? { ArisAPIPreset.named(id) }

    func model(tier: ArisTier) -> String { tier == .quick ? quick : strong }

    /// A keyed provider always at its preset's address; only a local server's may be the user's own (checked on load).
    var base: String {
        guard let preset else { return "" }
        return preset.needsKey ? preset.baseURL : baseURL ?? preset.baseURL
    }

    /// The stored profile is one Aris would have written: a known provider, an address only for a local server and
    /// only on this Mac, model names of the allowed shape.
    var isValid: Bool {
        guard let preset else { return false }
        if let baseURL { guard !preset.needsKey, ArisAPIPreset.checkLocalBase(baseURL) == baseURL else { return false } }
        let shape = #"^[A-Za-z0-9._:/@+\-]{0,200}$"#
        return [quick, strong].allSatisfy { $0.range(of: shape, options: .regularExpression) != nil }
    }

    var takesImages: Bool { vision ?? preset?.vision ?? false }

    var callsTools: Bool { tools ?? true }
}

/// The models that passed the smoke check (ArisAPISmoke), with when and which probes.
struct ArisAPITested: Codable, Equatable, Sendable {
    let profile: String
    let model: String
    let at: Date
    let passed: [String]
    let failed: [String]
}

/// api-brains.json: the active profile (the brain picker's "API"), every saved profile, and the smoke checks, all signed.
struct ArisAPIBrains: Codable, Equatable, Sendable {
    var active: String?
    var profiles: [ArisAPIProfile]
    var tested: [ArisAPITested]
    /// The user's own connections (다른 AI 연결…); absent in a file from before them.
    var connections: [ArisAPIConnection]?

    static let empty = ArisAPIBrains(active: nil, profiles: [], tested: [])

    var activeProfile: ArisAPIProfile? { active.flatMap { id in profiles.first { $0.id == id } } }

    func profile(_ id: String) -> ArisAPIProfile? { profiles.first { $0.id == id } }

    /// The list with `profile` saved in place (or added).
    func saving(_ profile: ArisAPIProfile) -> ArisAPIBrains {
        var copy = self
        copy.profiles = profiles.filter { $0.id != profile.id } + [profile]
        return copy
    }

    func removing(_ id: String) -> ArisAPIBrains {
        var copy = self
        copy.active = active == id ? nil : active
        copy.profiles = profiles.filter { $0.id != id }
        copy.tested = tested.filter { $0.profile != id }
        return copy
    }

    /// The check a key gets the moment it is saved, before anything was tried with it.
    static let uncheckedMark = "unchecked"

    /// A key that has never answered (final check on a new Mac: a made-up key was saved, its check failed, and it was
    /// still counted as a working AI everywhere): the profile has check results and none of them got an answer. A
    /// profile with no results at all is one saved before results were kept: nothing is known against it, and it
    /// stays as it was.
    func neverAnswered(_ id: String) -> Bool {
        let mine = tested.filter { $0.profile == id }
        return !mine.isEmpty && !mine.contains { $0.passed.contains("stream") }
    }

    /// A new key was saved for `id`: what the key before it did says nothing about this one, which starts as not yet
    /// answered until a check or a turn gets an answer.
    func withNewKey(_ id: String, model: String, at: Date) -> ArisAPIBrains {
        var copy = self
        copy.tested = tested.filter { $0.profile != id } + [ArisAPITested(profile: id, model: model, at: at, passed: [], failed: [Self.uncheckedMark])]
        return copy
    }

    /// A turn got its answer from `id`: it has answered.
    func answered(_ id: String, model: String, at: Date) -> ArisAPIBrains {
        guard neverAnswered(id) else { return self }
        var copy = self
        copy.tested = tested.filter { !($0.profile == id && $0.failed == [Self.uncheckedMark]) }
        return copy.recording(ArisAPITested(profile: id, model: model, at: at, passed: ["stream"], failed: []))
    }

    /// Keeps the latest result per profile and model, at most 100.
    func recording(_ result: ArisAPITested) -> ArisAPIBrains {
        var copy = self
        // A real check takes the place of the mark a new key starts with.
        copy.tested = Array((tested.filter { !($0.profile == result.profile && ($0.model == result.model || $0.failed == [Self.uncheckedMark])) } + [result]).suffix(100))
        return copy
    }
}

/// The signed file. A file changed outside Aris (its signature doesn't match) is no profile at all until saved again.
/// The signing key lives under a Keychain service of its own (security review C1): no profile id can ever name it.
final class ArisAPIStore {
    let file: URL
    private let signing: ArisMCPSecretStore
    private let lock = NSLock()
    static let signingKey = "config-hmac"

    static var defaultFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/api-brains.json")
    }

    private struct Signed: Codable {
        let brains: ArisAPIBrains
        let mac: String
    }

    init(file: URL = ArisAPIStore.defaultFile, signing: ArisMCPSecretStore) {
        self.file = file
        self.signing = signing
    }

    private(set) var tampered = false
    /// The Keychain couldn't be read just now: the file's signature can't be checked, so no profile is used, but it
    /// isn't called changed, and it isn't saved over (audit mcp-3, the same as the services' list).
    private(set) var unreadable = false
    static let unreadableLine = "키체인을 읽지 못해서 API 브레인 설정을 쓰지 못했어요. 설정과 키는 그대로예요. Mac의 잠금을 풀거나 키체인 접근을 허용하면 다시 돼요."

    func load() -> ArisAPIBrains { lock.withLock { read() } }

    /// Applies `change` to what's on disk and writes it back whole (0600). Nil when written, else what to tell the user.
    func update(_ change: (ArisAPIBrains) -> ArisAPIBrains) -> String? {
        lock.withLock {
            let current = read()
            guard !unreadable else { return ArisMCPStore.unreadableSave }
            let next = change(current)
            guard let body = try? Self.encoder.encode(next), let key = key(creating: true) else { return "설정을 저장하지 못했어요." }
            let signed = Signed(brains: next, mac: ArisMCPStore.mac(body, key: key))
            guard let data = try? Self.encoder.encode(signed) else { return "설정을 저장하지 못했어요." }
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try data.write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            } catch {
                return "설정을 저장하지 못했어요."
            }
            tampered = false
            ArisAPICustomPresets.set((next.connections ?? []).filter(\.isValid))
            return nil
        }
    }

    private func read() -> ArisAPIBrains {
        unreadable = false
        guard let data = try? Data(contentsOf: file) else { tampered = false; return none() }
        let stored = ArisMCPStore.storedKey(signing, account: Self.signingKey)
        guard !stored.unreadable else {
            tampered = false
            unreadable = true
            return none()
        }
        guard data.count < 1_000_000, let signed = try? JSONDecoder.api.decode(Signed.self, from: data),
              let body = try? Self.encoder.encode(signed.brains), let key = stored.key,
              ArisMCPTurnCredential.same(ArisMCPStore.mac(body, key: key), signed.mac) else {
            tampered = true
            return none()
        }
        tampered = false
        var brains = signed.brains
        // The user's own connections first: they are providers only while this signed list names them.
        var known: Set<String> = []
        let connections = (brains.connections ?? []).filter { $0.isValid && known.insert($0.id).inserted }
        ArisAPICustomPresets.set(connections)
        brains.connections = connections.isEmpty ? nil : connections
        // Only known providers, once each.
        var seen: Set<String> = []
        brains.profiles = brains.profiles.filter { $0.isValid && seen.insert($0.id).inserted }
        if let active = brains.active, brains.profile(active) == nil { brains.active = nil }
        return brains
    }

    /// No list (none saved, changed outside Aris, or the Keychain can't be read): no connection is a provider either.
    private func none() -> ArisAPIBrains {
        ArisAPICustomPresets.set([])
        return .empty
    }

    private func key(creating: Bool) -> Data? {
        let stored = ArisMCPStore.storedKey(signing, account: Self.signingKey)
        if let key = stored.key { return key }
        guard creating, !stored.unreadable else { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        guard signing.save(bytes.map { String(format: "%02x", $0) }.joined(), for: Self.signingKey) == nil else { return nil }
        return Data(bytes)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}

/// The API brains' keys: generic passwords under their own service, one account per profile (and the list's signing key).
enum ArisAPISecrets {
    static let service = "com.lumenjsn.aris.brains"
    static let live: ArisMCPSecretStore = ArisMCPKeychain(service: service)
    /// The list's signing key, apart from the keys.
    static let signingService = "com.lumenjsn.aris.brains.signing"
    static let signing: ArisMCPSecretStore = ArisMCPKeychain(service: signingService)
    static let store = ArisAPIStore(signing: signing)

    /// The longest key accepted.
    static let maxKey = 400

    /// A pasted key, trimmed; nil when it can't be one (empty, too long, spaces or control characters inside).
    static func check(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.count <= maxKey, key.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else { return nil }
        return key
    }

    /// `text` with every secret in `secrets` and anything shaped like a provider key replaced by dots: for every log
    /// line, audit line, error text and anything a brain could read.
    static func redacted(_ text: String, secrets: [String] = []) -> String {
        var out = text
        for secret in secrets where secret.count >= 8 { out = out.replacingOccurrences(of: secret, with: "••••") }
        let shapes = [#"sk-[A-Za-z0-9_\-]{12,}"#, #"sk-ant-[A-Za-z0-9_\-]{12,}"#, #"AIza[0-9A-Za-z_\-]{20,}"#, #"gsk_[A-Za-z0-9]{12,}"#,
                      #"xai-[A-Za-z0-9]{12,}"#, #"(?i)bearer\s+[A-Za-z0-9._\-]{12,}"#, #"(?i)(x-api-key|x-goog-api-key|api[_-]?key)["':= ]+[A-Za-z0-9._\-]{12,}"#]
        for shape in shapes { out = out.replacingOccurrences(of: shape, with: "••••", options: .regularExpression) }
        return out
    }
}
