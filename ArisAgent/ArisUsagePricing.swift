//
//  ArisUsagePricing.swift
//  aris-agent
//
//  API prices for the cost the local logs add up to, after CodexBar's CostUsagePricing (github.com/steipete/CodexBar,
//  MIT). The models.dev catalog (trimmed to Anthropic, OpenAI and Google) is fetched at most once a day and kept in
//  ~/.config/aris/usage; a short bundled table covers being offline.
//

import Foundation

/// Prices per million tokens.
struct ArisModelRate: Equatable {
    struct Tier: Equatable {
        let size: Int
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double
    }

    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double
    var tier: Tier?

    init(input: Double, output: Double, cacheRead: Double? = nil, cacheWrite: Double? = nil, tier: Tier? = nil) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead ?? input
        self.cacheWrite = cacheWrite ?? input
        self.tier = tier
    }

    /// The rates for a request with this much input: the context tier's past its size.
    func effective(inputTokens: Int) -> ArisModelRate {
        guard let tier, inputTokens > tier.size else { return self }
        return ArisModelRate(input: tier.input, output: tier.output, cacheRead: tier.cacheRead, cacheWrite: tier.cacheWrite)
    }
}

enum ArisUsagePricing {
    static let providers = ["anthropic", "openai", "google"]

    static let bundled: [String: [String: ArisModelRate]] = [
        "anthropic": [
            "claude-opus-5-5": ArisModelRate(input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5),
            "claude-sonnet-5": ArisModelRate(input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5),
            "claude-haiku-4-5": ArisModelRate(input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25),
        ],
        "openai": [
            "gpt-6-astra": ArisModelRate(input: 10, output: 50, cacheRead: 1, cacheWrite: 12.5,
                                         tier: .init(size: 272_000, input: 20, output: 75, cacheRead: 2, cacheWrite: 25)),
            "gpt-5.5": ArisModelRate(input: 5, output: 30, cacheRead: 0.5),
        ],
    ]

    nonisolated(unsafe) private static var catalog: [String: [String: ArisModelRate]]?
    private static let lock = NSLock()

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/usage")
    }
    static var file: URL { directory.appendingPathComponent("models-dev.json") }

    /// `{providerID: {models: {modelID: {cost: {input, output, cache_read, cache_write, tiers?}}}}}`.
    static func parse(catalog data: Data) -> [String: [String: ArisModelRate]]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var result: [String: [String: ArisModelRate]] = [:]
        for provider in providers {
            guard let models = (json[provider] as? [String: Any])?["models"] as? [String: Any] else { continue }
            for (id, raw) in models {
                guard let cost = (raw as? [String: Any])?["cost"] as? [String: Any],
                      let input = number(cost["input"]), let output = number(cost["output"]) else { continue }
                var tier: ArisModelRate.Tier?
                if let tiers = cost["tiers"] as? [[String: Any]] {
                    for entry in tiers {
                        guard let spec = entry["tier"] as? [String: Any], spec["type"] as? String == "context",
                              let size = number(spec["size"]), let tierInput = number(entry["input"]),
                              let tierOutput = number(entry["output"]) else { continue }
                        tier = .init(size: Int(size), input: tierInput, output: tierOutput,
                                     cacheRead: number(entry["cache_read"]) ?? tierInput, cacheWrite: number(entry["cache_write"]) ?? tierInput)
                        break
                    }
                }
                result[provider, default: [:]][id] = ArisModelRate(input: input, output: output, cacheRead: number(cost["cache_read"]),
                                                                  cacheWrite: number(cost["cache_write"]), tier: tier)
            }
        }
        return result.isEmpty ? nil : result
    }

    /// The model's rates: the catalog's, else the bundled table's. Claude models retry without a trailing -YYYYMMDD,
    /// Codex's without a "-codex" suffix.
    static func rate(provider: String, model: String) -> ArisModelRate? {
        lock.lock()
        if catalog == nil { catalog = (try? Data(contentsOf: file)).flatMap(parse(catalog:)) ?? [:] }
        let loaded = catalog ?? [:]
        lock.unlock()
        for source in [loaded, bundled] {
            guard let models = source[provider] else { continue }
            for name in candidates(model) { if let rate = models[name] { return rate } }
        }
        return nil
    }

    static func candidates(_ model: String) -> [String] {
        var names = [model]
        if let range = model.range(of: #"-\d{8}$"#, options: .regularExpression) { names.append(String(model[..<range.lowerBound])) }
        if model.hasSuffix("-codex") { names.append(String(model.dropLast(6))) }
        return names
    }

    /// Fetches the catalog when ours is over a day old; blocking, so call it off the main work.
    static func refreshIfStale(now: Date = Date()) {
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let modified, now.timeIntervalSince(modified) < 86_400 { return }
        guard let url = URL(string: "https://models.dev/api.json") else { return }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var body: Data?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 { body = data }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 35)
        guard let body, let full = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return }
        var trimmed: [String: Any] = [:]
        for provider in providers {
            guard let models = (full[provider] as? [String: Any])?["models"] as? [String: Any] else { continue }
            trimmed[provider] = ["models": models.compactMapValues { raw -> Any? in
                (raw as? [String: Any])?["cost"].map { ["cost": $0] }
            }]
        }
        guard !trimmed.isEmpty, let data = try? JSONSerialization.data(withJSONObject: trimmed) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        lock.lock(); catalog = parse(catalog: data); lock.unlock()
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    // MARK: - Cost

    static func claudeCost(_ rate: ArisModelRate, input: Int, output: Int, cacheRead: Int, cacheCreation: Int, cache1h: Int) -> Double {
        let oneHour = min(max(0, cache1h), max(0, cacheCreation))
        let fiveMinutes = max(0, cacheCreation) - oneHour
        let perToken = 1.0 / 1_000_000
        return (Double(max(0, input)) * rate.input + Double(max(0, cacheRead)) * rate.cacheRead
            + Double(fiveMinutes) * rate.cacheWrite + Double(oneHour) * rate.input * 2
            + Double(max(0, output)) * rate.output) * perToken
    }

    static func codexCost(_ base: ArisModelRate, input: Int, cached: Int, cacheWrite: Int, output: Int) -> Double {
        let rate = base.effective(inputTokens: input)
        let cachedTokens = min(max(0, cached), max(0, input))
        let written = min(max(0, cacheWrite), max(0, input) - cachedTokens)
        let plain = max(0, input) - cachedTokens - written
        return (Double(plain) * rate.input + Double(cachedTokens) * rate.cacheRead + Double(written) * rate.cacheWrite
            + Double(max(0, output)) * rate.output) / 1_000_000
    }
}
