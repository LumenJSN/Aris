//
//  ArisUsage.swift
//  Aris
//
//  Plan limits for the AIs in use, after CodexBar (github.com/steipete/CodexBar, MIT): each provider has lanes
//  (Antigravity has two model groups), each lane a 5-hour and a weekly window with how much is used and when it
//  resets, plus what the local logs cost at API prices. Claude comes from its OAuth usage endpoint, Codex from
//  ChatGPT's usage endpoint (or, offline, the newest Codex session log), Antigravity from `agy -p /usage`.
//  Pure and shared: aris-agent fetches, the app shows.
//

import Foundation

struct ArisUsageWindow: Codable, Equatable {
    /// 0…100 used.
    let percent: Double
    let resetsAt: Date?
    /// 18000 for a session window, 604800 for a week.
    let windowSeconds: Double?

    init(percent: Double, resetsAt: Date?, windowSeconds: Double? = nil) {
        self.percent = percent
        self.resetsAt = resetsAt
        self.windowSeconds = windowSeconds
    }

    /// A window that has already reset reads 0% until a fresh report comes.
    func percent(at now: Date) -> Double {
        guard let resetsAt, now >= resetsAt else { return percent }
        return 0
    }

    func remaining(at now: Date) -> Double { 100 - percent(at: now) }

    /// How the use so far compares with an even spread over the window, after CodexBar's UsagePace.weekly
    /// (github.com/steipete/CodexBar, MIT; without its workday variant).
    func pace(at now: Date) -> ArisUsagePace? {
        guard let resetsAt, let duration = windowSeconds, duration > 0 else { return nil }
        let untilReset = resetsAt.timeIntervalSince(now)
        guard untilReset > 0, untilReset <= duration else { return nil }
        let elapsed = min(max(duration - untilReset, 0), duration)
        let expected = min(max(elapsed / duration * 100, 0), 100)
        let actual = min(max(percent, 0), 100)
        if elapsed == 0, actual > 0 { return nil }
        var eta: Double?
        var lasts = false
        if actual >= 100 {
            eta = 0
        } else if elapsed > 0, actual > 0 {
            let candidate = (100 - actual) / (actual / elapsed)
            if candidate >= untilReset { lasts = true } else { eta = candidate }
        } else if elapsed > 0 {
            lasts = true
        }
        return ArisUsagePace(expectedUsedPercent: expected, deltaPercent: actual - expected, etaSeconds: eta, willLastToReset: lasts)
    }
}

struct ArisUsagePace: Equatable {
    let expectedUsedPercent: Double
    /// Actual minus expected: under zero is ahead of the pace (spare), over zero is behind it.
    let deltaPercent: Double
    let etaSeconds: Double?
    let willLastToReset: Bool

    /// "6% 여유 · 재설정까지 유지", "28% 부족 · 7시간 4분 후 소진".
    func line(now: Date) -> String {
        let size = Int(abs(deltaPercent).rounded())
        var text = size == 0 ? "딱 맞게 쓰는 중" : deltaPercent < 0 ? "\(size)% 여유" : "\(size)% 부족"
        if willLastToReset {
            text += " · 재설정까지 유지"
        } else if let etaSeconds {
            text += etaSeconds <= 0 ? " · 다 썼어요" : " · \(ArisUsageParse.untilReset(now.addingTimeInterval(etaSeconds), now: now)) 후 소진"
        }
        return text
    }
}

struct ArisUsageLane: Codable, Equatable {
    /// "" for a provider with one lane.
    let name: String
    let fiveHour: ArisUsageWindow?
    let weekly: ArisUsageWindow?
}

struct ArisUsageSpend: Codable, Equatable {
    var usd: Double
    var tokens: Int
}

struct ArisUsageDay: Codable, Equatable {
    /// The start of the local day.
    let day: Date
    let usd: Double
    let tokens: Int
}

struct ArisUsageSpendWindow: Codable, Equatable {
    let start: Date
    let end: Date
    let usd: Double
    let tokens: Int
}

/// What the AI's local logs add up to at API prices (after CodexBar's cost scanner).
struct ArisUsageCost: Codable, Equatable {
    var today: ArisUsageSpend
    var last30: ArisUsageSpend
    /// Exactly 30, oldest first, the last one today.
    var daily: [ArisUsageDay]
    /// The current weekly window, then the two before it.
    var windows: [ArisUsageSpendWindow]
    var topModel: String?
}

struct ArisUsageProvider: Codable, Equatable, Identifiable {
    enum Billing: String, Codable { case subscription, api }

    let id: String
    let title: String
    var billing: Billing = .subscription
    var account: String?
    /// "Pro", "Max 20x", "Plus".
    var plan: String?
    var lanes: [ArisUsageLane]
    var cost: ArisUsageCost?
    let updatedAt: Date
    /// Why the numbers are old or missing, short and in Korean.
    var note: String?

    /// The fullest window: what the menu bar shows and what warns.
    func peak(at now: Date) -> Double {
        lanes.flatMap { [$0.fiveHour, $0.weekly] }.compactMap { $0?.percent(at: now) }.max() ?? 0
    }
}

struct ArisUsageReport: Codable, Equatable {
    var providers: [ArisUsageProvider]
    /// The AIs still being asked when this report was written, by id: a slow one never holds the others back, and the
    /// app asks again shortly while any is named here (ArisUsagePatience). Nil when none is.
    var pending: [String]? = nil

    static let empty = ArisUsageReport(providers: [])

    static func decode(_ data: Data) -> ArisUsageReport? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(ArisUsageReport.self, from: data)
    }

    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return (try? encoder.encode(self)) ?? Data("{\"providers\":[]}".utf8)
    }
}

/// How long reading the limits may take. Every wait has its own limit, so the 사용량 tab never sits on "불러오는 중…"
/// because one AI is slow or isn't on this Mac (VM run 2026-11-10, bug 3).
enum ArisUsagePatience {
    /// aris-agent answers POST /usage within this, with what it has; an AI it is still asking is named in `pending`.
    static let report: TimeInterval = 4
    /// The app gives up on one ask after this: the agent's own limit, plus room for a busy Mac.
    static let ask: TimeInterval = 10
    /// While an AI is pending the app asks again this often,
    static let again: TimeInterval = 3
    /// for at most this long after the read began. What still hasn't answered by then comes with the next read.
    static let followUp: TimeInterval = 30

    /// Whether the app asks once more after a report: something is still pending and the next ask fits in the limit.
    static func asksAgain(pending: [String]?, began: Date, now: Date) -> Bool {
        guard let pending, !pending.isEmpty else { return false }
        return now.timeIntervalSince(began) + again <= followUp
    }
}

enum ArisUsageParse {
    /// `GET chatgpt.com/backend-api/wham/usage`: rate_limit.primary_window (5 h) and secondary_window (week).
    static func codex(api data: Data, now: Date) -> ArisUsageProvider? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = json["rate_limit"] as? [String: Any] else { return nil }
        let window = { (key: String) -> ArisUsageWindow? in
            guard let raw = limits[key] as? [String: Any], let percent = number(raw["used_percent"]) else { return nil }
            return ArisUsageWindow(percent: clamped(percent), resetsAt: number(raw["reset_at"]).map { Date(timeIntervalSince1970: $0) },
                                   windowSeconds: number(raw["limit_window_seconds"]))
        }
        let lane = ArisUsageLane(name: "", fiveHour: window("primary_window"), weekly: window("secondary_window"))
        guard lane.fiveHour != nil || lane.weekly != nil else { return nil }
        return ArisUsageProvider(id: "codex", title: "Codex", account: json["email"] as? String,
                                 plan: (json["plan_type"] as? String).map(planName), lanes: [lane], updatedAt: now)
    }

    /// A Codex session log line with `rate_limits` (its token_count events): primary (5 h) and secondary (week).
    static func codex(sessionLine line: String, now: Date) -> ArisUsageProvider? {
        guard line.contains("\"rate_limits\""),
              let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let limits = find("rate_limits", in: json) else { return nil }
        let window = { (key: String) -> ArisUsageWindow? in
            guard let raw = limits[key] as? [String: Any], let percent = number(raw["used_percent"]) else { return nil }
            return ArisUsageWindow(percent: clamped(percent), resetsAt: number(raw["resets_at"]).map { Date(timeIntervalSince1970: $0) },
                                   windowSeconds: number(raw["window_minutes"]).map { $0 * 60 })
        }
        let lane = ArisUsageLane(name: "", fiveHour: window("primary"), weekly: window("secondary"))
        guard lane.fiveHour != nil || lane.weekly != nil else { return nil }
        return ArisUsageProvider(id: "codex", title: "Codex", plan: (limits["plan_type"] as? String).map(planName), lanes: [lane], updatedAt: now)
    }

    /// `agy -p /usage --output-format json`: command.data.groups, each with a "5h" and a "weekly" bucket that
    /// report the fraction *remaining*.
    static func antigravity(_ data: Data, now: Date) -> ArisUsageProvider? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = ((json["command"] as? [String: Any])?["data"] as? [String: Any])?["groups"] as? [[String: Any]] else { return nil }
        let iso = ISO8601DateFormatter()
        let lanes = groups.compactMap { group -> ArisUsageLane? in
            let buckets = group["buckets"] as? [[String: Any]] ?? []
            let window = { (name: String) -> ArisUsageWindow? in
                guard let bucket = buckets.first(where: { $0["window"] as? String == name }),
                      let remaining = number(bucket["remaining_fraction"]) else { return nil }
                return ArisUsageWindow(percent: clamped((1 - remaining) * 100), resetsAt: (bucket["reset_time"] as? String).flatMap(iso.date),
                                       windowSeconds: name == "5h" ? 18_000 : 604_800)
            }
            let lane = ArisUsageLane(name: shortGroupName(group["name"] as? String ?? ""), fiveHour: window("5h"), weekly: window("weekly"))
            return lane.fiveHour == nil && lane.weekly == nil ? nil : lane
        }
        return lanes.isEmpty ? nil : ArisUsageProvider(id: "antigravity", title: "Antigravity", lanes: lanes, updatedAt: now)
    }

    /// `GET api.anthropic.com/api/oauth/usage`: five_hour and seven_day (0…100 used, ISO resets_at), plus Opus and
    /// Sonnet weekly lanes when present. Account and plan are the caller's.
    static func claude(oauth data: Data, now: Date) -> ArisUsageProvider? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let window = { (key: String, seconds: Double) -> ArisUsageWindow? in
            guard let raw = json[key] as? [String: Any], let percent = number(raw["utilization"]) else { return nil }
            return ArisUsageWindow(percent: clamped(percent), resetsAt: (raw["resets_at"] as? String).flatMap(isoDate), windowSeconds: seconds)
        }
        var lanes: [ArisUsageLane] = []
        let main = ArisUsageLane(name: "", fiveHour: window("five_hour", 18_000), weekly: window("seven_day", 604_800))
        if main.fiveHour != nil || main.weekly != nil { lanes.append(main) }
        for (key, name) in [("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet")] {
            if let weekly = window(key, 604_800) { lanes.append(ArisUsageLane(name: name, fiveHour: nil, weekly: weekly)) }
        }
        guard !lanes.isEmpty else { return nil }
        return ArisUsageProvider(id: "claude", title: "Claude", lanes: lanes, updatedAt: now)
    }

    /// ISO 8601 with up to nine fractional digits and any offset ("2026-11-02T07:09:59.668164+00:00").
    static func isoDate(_ text: String) -> Date? {
        var text = text
        if let dot = text.firstIndex(of: ".") {
            let digits = text[text.index(after: dot)...].prefix { $0.isNumber }
            let rest = text[text.index(dot, offsetBy: 1 + digits.count)...]
            text = String(text[..<dot]) + "." + String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0) + String(rest)
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// Claude Code's credentials JSON (keychain item or ~/.claude/.credentials.json): the access token, when it
    /// expires and the plan it shows. The token is only ever held in memory.
    static func claudeCredentials(_ data: Data) -> (token: String, expiresAt: Date?, plan: String?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let expires = number(oauth["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        return (token, expires, claudePlan(subscription: oauth["subscriptionType"] as? String, tier: oauth["rateLimitTier"] as? String))
    }

    /// "pro" → "Pro"; "max" with a "…_max_20x" tier → "Max 20x".
    static func claudePlan(subscription: String?, tier: String?) -> String? {
        guard let subscription = subscription?.lowercased(), !subscription.isEmpty else { return nil }
        if subscription == "max" {
            let tier = tier?.lowercased() ?? ""
            if tier.hasSuffix("max_20x") { return "Max 20x" }
            if tier.hasSuffix("max_5x") { return "Max 5x" }
        }
        return planName(subscription)
    }

    /// `~/.claude.json`'s oauthAccount.organizationType.
    static func claudePlan(organizationType: String?) -> String? {
        switch organizationType {
        case "claude_pro": "Pro"
        case "claude_max": "Max"
        default: nil
        }
    }

    static func planName(_ raw: String) -> String { raw.prefix(1).uppercased() + raw.dropFirst() }

    /// "Gemini Models" → "Gemini", "Claude and GPT models" → "Claude·GPT".
    static func shortGroupName(_ name: String) -> String {
        let words = name.replacingOccurrences(of: " models", with: "", options: .caseInsensitive)
            .components(separatedBy: " and ")
        return words.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "·")
    }

    /// "4h 12m", "2d 3h", "12m": how long until a window resets.
    static func untilReset(_ date: Date?, now: Date) -> String {
        guard let date else { return "" }
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes >= 1_440 { return "\(minutes / 1_440)일 \(minutes % 1_440 / 60)시간" }
        if minutes >= 60 { return "\(minutes / 60)시간 \(minutes % 60)분" }
        return "\(minutes)분"
    }

    private static func find(_ key: String, in object: Any) -> [String: Any]? {
        if let dictionary = object as? [String: Any] {
            if let found = dictionary[key] as? [String: Any] { return found }
            for value in dictionary.values { if let found = find(key, in: value) { return found } }
        } else if let array = object as? [Any] {
            for value in array { if let found = find(key, in: value) { return found } }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func clamped(_ percent: Double) -> Double { min(max(percent, 0), 100) }
}

enum ArisUsageFormat {
    /// "7.1M", "941M", "2.6B", "12K": one decimal below 10, whole from 10.
    static func tokens(_ count: Int) -> String {
        let units: [(Double, String)] = [(1_000, "K"), (1_000_000, "M"), (1_000_000_000, "B")]
        let value = Double(max(0, count))
        guard value >= 1_000 else { return "\(max(0, count))" }
        var index = units.lastIndex { value >= $0.0 } ?? 0
        var scaled = value / units[index].0
        let shown = { (value: Double) in (value * 10).rounded() / 10 >= 10 ? value.rounded() : (value * 10).rounded() / 10 }
        if shown(scaled) >= 1_000, index + 1 < units.count {
            index += 1
            scaled = value / units[index].0
        }
        let rounded = (scaled * 10).rounded() / 10
        return (rounded >= 10 ? String(Int(rounded.rounded())) : String(format: "%.1f", rounded)) + units[index].1
    }

    /// "$8.65"
    static func usd(_ amount: Double) -> String { String(format: "$%.2f", amount) }
}
