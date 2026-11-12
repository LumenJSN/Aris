//
//  ArisSkillsStatus.swift
//  Aris
//
//  What aris-agent says about the user's skills (POST /skills "status"), as the settings page and the notch read it: the
//  switch, the one-time setup's progress, each skill (its phase, findings, the AIs it was tried on, its files) and the
//  add jobs under way. Plus the small rules the views share (a skill's tested line, a file's line and tag, the
//  intent "이 링크 스킬 추가해줘"). Foundation only, so the tests compile it.
//

import Foundation

struct ArisSkillLine: Equatable, Hashable {
    let text: String
    let file: String
    /// The check's own word on the internet, whatever language its line is in: true when the line is about reaching
    /// it, false when the check confirmed the file stays on this Mac, nil when it didn't say.
    var net: Bool? = nil
}

struct ArisSkillTried: Equatable {
    let brain: String
    let model: String
    let ok: Bool
}

struct ArisSkillFileRow: Equatable {
    let path: String
    let size: Int
    let kind: String
}

struct ArisSkillRow: Equatable, Identifiable {
    let name: String
    let title: String
    let summary: String
    let source: String
    let owner: String?
    let enabled: Bool
    /// "ready", "checking", "waiting" (a caution not yet accepted), "blocked", "changed" or "off".
    let phase: String
    let verdict: String
    let description: String
    let files: [ArisSkillFileRow]
    let findings: [ArisSkillLine]
    let checked: [ArisSkillLine]
    let tested: [ArisSkillTried]

    var id: String { name }
}

struct ArisSkillJobRow: Equatable, Identifiable {
    let id: String
    let kind: String
    let source: String
    /// "fetching", "review", "checking" or "done".
    let stage: String
    let step: String?
    let percent: Int
    /// "added", "caution", "blocked", "failed", "cancelled".
    let outcome: String?
    let message: String?
    let name: String?
    let title: String?
    let summary: String?
    let owner: String?
    let version: String?
    let stars: Int?
    let license: String?
    let pushedAt: Date?
    let files: [ArisSkillFileRow]
    let findings: [ArisSkillLine]
    let checked: [ArisSkillLine]
}

struct ArisSkillSetupRow: Equatable {
    /// "absent", "installing", "ready", "failed".
    var state = "absent"
    var step = ""
    var doneMB = 0
    var totalMB = 75
    var message: String?

    var fraction: Double { totalMB > 0 ? min(1, Double(doneMB) / Double(totalMB)) : 0 }
}

struct ArisSkillsStatus: Equatable {
    var enabled = false
    var deferred = false
    var setup = ArisSkillSetupRow()
    var skills: [ArisSkillRow] = []
    var jobs: [ArisSkillJobRow] = []
    var brains: [String] = []
    /// The agent answered at least once.
    var known = false

    var ready: Bool { enabled && setup.state == "ready" }

    static func parse(_ object: [String: Any]) -> ArisSkillsStatus {
        func lines(_ value: Any?) -> [ArisSkillLine] {
            (value as? [[String: Any]] ?? []).map { ArisSkillLine(text: $0["text"] as? String ?? "", file: $0["file"] as? String ?? "", net: $0["net"] as? Bool) }
        }
        func files(_ value: Any?) -> [ArisSkillFileRow] {
            (value as? [[String: Any]] ?? []).map { ArisSkillFileRow(path: $0["path"] as? String ?? "", size: $0["size"] as? Int ?? 0, kind: $0["kind"] as? String ?? "other") }
        }
        var status = ArisSkillsStatus()
        status.known = true
        status.enabled = object["enabled"] as? Bool == true
        status.deferred = object["deferred"] as? Bool == true
        if let setup = object["setup"] as? [String: Any] {
            status.setup = ArisSkillSetupRow(state: setup["state"] as? String ?? "absent", step: setup["step"] as? String ?? "",
                                             doneMB: setup["doneMB"] as? Int ?? 0, totalMB: setup["totalMB"] as? Int ?? 75, message: setup["message"] as? String)
        }
        status.skills = (object["skills"] as? [[String: Any]] ?? []).map { row in
            ArisSkillRow(name: row["name"] as? String ?? "", title: row["title"] as? String ?? "", summary: row["summary"] as? String ?? "",
                         source: row["source"] as? String ?? "folder", owner: row["owner"] as? String, enabled: row["enabled"] as? Bool == true,
                         phase: row["phase"] as? String ?? "changed", verdict: row["verdict"] as? String ?? "unscanned",
                         description: row["description"] as? String ?? "", files: files(row["files"]), findings: lines(row["findings"]),
                         checked: lines(row["checked"]),
                         tested: (row["tested"] as? [[String: Any]] ?? []).map { ArisSkillTried(brain: $0["brain"] as? String ?? "", model: $0["model"] as? String ?? "", ok: $0["ok"] as? Bool == true) })
        }
        status.jobs = (object["jobs"] as? [[String: Any]] ?? []).map { job in
            ArisSkillJobRow(id: job["id"] as? String ?? "", kind: job["kind"] as? String ?? "", source: job["source"] as? String ?? "",
                            stage: job["stage"] as? String ?? "fetching", step: job["step"] as? String, percent: job["percent"] as? Int ?? 0,
                            outcome: job["outcome"] as? String, message: job["message"] as? String, name: job["name"] as? String,
                            title: job["title"] as? String, summary: job["summary"] as? String, owner: job["owner"] as? String,
                            version: job["version"] as? String, stars: job["stars"] as? Int, license: job["license"] as? String,
                            pushedAt: (job["pushedAt"] as? Double).map(Date.init(timeIntervalSince1970:)), files: files(job["files"]),
                            findings: lines(job["findings"]), checked: lines(job["checked"]))
        }
        status.brains = object["brains"] as? [String] ?? []
        return status
    }
}

enum ArisSkillWords {
    /// The app's language as aris-agent is told it with every skills request ("en" or "ko").
    static func language(english: Bool) -> String { english ? "en" : "ko" }

    /// How the notch's skill flow words itself: as the 스킬 page does, from the settings catalog (one English for the
    /// same line in both places, the helper's own lines included).
    static func notchWording(english: Bool = ArisUIWords.english) -> ArisSettingsWording { .make(page: .skills, english: english) }

    /// "AI 4개 · 1개 아직", "AI 5개 모두", or "시험 전" (over the AIs this Mac has).
    static func tested(_ row: ArisSkillRow, brains: [String]) -> (text: String, all: Bool) {
        let passed = Set(row.tested.filter(\.ok).map(\.brain))
        let total = max(brains.count, passed.count)
        guard !passed.isEmpty else { return ("시험 전", false) }
        let left = total - passed.count
        return left <= 0 ? ("AI \(passed.count)개 모두", true) : ("AI \(passed.count)개 · \(left)개 아직", false)
    }

    /// A brain's chip name.
    static func brainName(_ brain: String) -> String {
        switch brain {
        case "claude": "Claude"
        case "codex": "GPT (Codex)"
        case "antigravity": "Gemini"
        case "api": "API 모델"
        default: brain
        }
    }

    /// Where a skill came from, for its row's line ("GitHub · hana-k", "skill-creator로 만듦", "내 폴더", "Aris 기본").
    static func source(_ row: ArisSkillRow) -> String {
        switch row.source {
        case "github": "GitHub" + (row.owner.map { " · " + $0 } ?? "")
        case "made": "skill-creator로 만듦"
        case "builtin": "Aris 기본"
        default: "내 폴더"
        }
    }

    /// A file's second line: what the check said about it, else what kind it is.
    static func fileLine(_ file: ArisSkillFileRow, notes: [ArisSkillLine]) -> String {
        if let note = notes.first(where: { $0.file == file.path }) { return note.text }
        switch file.kind {
        case "skill": return "지시문 · " + size(file.size)
        case "script": return "스크립트 · " + size(file.size)
        case "reference": return "참고 자료"
        case "asset": return "자료 · " + size(file.size)
        default: return size(file.size)
        }
    }

    /// The small tag beside a file: "인터넷 씀" when the check saw it reach out, "내 Mac 안에서만" when it confirmed it doesn't.
    /// The check says so itself with each line (`net`), so the tag is the same whatever language the line is written in
    /// (VM run, bug 4: it was read from Korean words in the line, and an English finding never got its tag). A line that
    /// carries no such word (a skill checked before the check said it) is still read by its Korean words, as it was.
    static func fileTag(_ file: ArisSkillFileRow, findings: [ArisSkillLine], checked: [ArisSkillLine]) -> (text: String, warn: Bool)? {
        guard file.kind == "script" else { return nil }
        let about = (findings + checked).filter { $0.file == file.path }, confirmed = checked.filter { $0.file == file.path }
        let words = ["인터넷", "접속", "다운로드", "받아요", "보내요", ".com", "http"]
        let unsaid = { (line: ArisSkillLine) in line.net == nil }
        if about.contains(where: { $0.net == true })
            || about.filter(unsaid).contains(where: { !$0.text.contains("보내지 않") && words.contains(where: $0.text.contains) }) {
            return ("인터넷 씀", true)
        }
        if confirmed.contains(where: { $0.net == false })
            || confirmed.filter(unsaid).contains(where: { $0.text.contains("Mac 안") || $0.text.contains("보내지 않") }) { return ("내 Mac 안에서만", false) }
        return nil
    }

    static func size(_ bytes: Int) -> String {
        bytes < 1_024 ? "\(bytes)B" : bytes < 1_048_576 ? String(format: "%.1fKB", Double(bytes) / 1_024) : String(format: "%.1fMB", Double(bytes) / 1_048_576)
    }

    /// "2주 전 업데이트".
    static func updated(_ date: Date, now: Date = Date()) -> String {
        let days = Int(now.timeIntervalSince(date) / 86_400)
        switch days {
        case ..<1: return "오늘 업데이트"
        case 1..<7: return "\(days)일 전 업데이트"
        case 7..<30: return "\(days / 7)주 전 업데이트"
        case 30..<365: return "\(days / 30)달 전 업데이트"
        default: return "\(days / 365)년 전 업데이트"
        }
    }

    /// The GitHub line under a fetched skill's name: "GitHub · studyhub · 버전 1.3.0 · ★ 214 · 2주 전 업데이트 · MIT".
    static func meta(_ job: ArisSkillJobRow, now: Date = Date(), fileCount: Bool = false) -> String {
        var parts = ["GitHub"]
        if let owner = job.owner { parts.append(owner) }
        if let version = job.version { parts.append("버전 " + version) }
        if fileCount { parts.append("파일 \(job.files.count)개") } else {
            if let stars = job.stars { parts.append("★ \(stars)") }
            if let pushed = job.pushedAt { parts.append(updated(pushed, now: now)) }
            if let license = job.license { parts.append(license) }
        }
        return parts.joined(separator: " · ")
    }
}

/// What the user said, when it is "add this skill from a link" (the notch does it without a brain).
enum ArisSkillIntent {
    static func link(in text: String) -> String? {
        let lowered = text.lowercased()
        guard lowered.contains("스킬") || lowered.contains("skill"),
              ["추가", "설치", "넣어", "깔아", "받아", "add", "install"].contains(where: lowered.contains),
              let range = text.range(of: #"(?i)(https?://)?(www\.)?github\.com/[^\s<>"'`)\]]+"#, options: .regularExpression) else { return nil }
        return String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,!?。"))
    }
}

/// One line of the settings chat.
struct ArisSkillChatItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case aris(String)
        case user(String, link: Bool)
        /// "스킬 기능은 아직 꺼져 있어요. 켤까요?" (its buttons while it's off).
        case offer
        /// The setup's live progress card, then 준비됐어요 or the failure.
        case setup
        /// The chips under "어떤 일을 스킬로 만들까요?".
        case suggestions
        /// A link, folder or draft being added (its live card).
        case job(String)
        /// A SKILL.md 말로 만들기 wrote.
        case draft(String)
        /// Waiting for the AI's next line.
        case thinking
    }

    let id = UUID()
    let kind: Kind
}

/// The notch's skill flow for one request.
struct ArisSkillNotchFlow: Equatable {
    let request: String
    let link: String
    var job: String?
    /// The user said 나중에, or 취소 on a failed setup.
    var dropped = false
    /// The link couldn't be started (its reason).
    var problem: String?
}

/// A skill's icon by what it's about: the first keyword its title or name has, else one picked from its name.
enum ArisSkillLook {
    struct Look: Equatable {
        let symbol: String
        let tint: UInt32
    }

    /// Keywords (Korean and English, lowercased) and their look, checked in this order.
    static let table: [([String], Look)] = [
        (["회의", "회의록", "meeting", "minutes"], Look(symbol: "doc.text", tint: 0x2563eb)),
        (["과제", "공부", "시험", "숙제", "수업", "강의 노트", "study", "exam", "assignment", "homework", "course"], Look(symbol: "book.closed", tint: 0x16a34a)),
        (["유튜브", "영상", "강의", "youtube", "video", "lecture"], Look(symbol: "play.rectangle", tint: 0xdc2626)),
        (["캡션", "인스타", "사진", "caption", "instagram", "photo"], Look(symbol: "camera", tint: 0xdb2777)),
        (["영수증", "가계부", "예산", "receipt", "budget", "expense"], Look(symbol: "receipt", tint: 0xd97706)),
        (["일정", "캘린더", "달력", "calendar", "schedule"], Look(symbol: "calendar", tint: 0x0891b2)),
        (["할 일", "체크", "todo", "checklist", "task"], Look(symbol: "checklist", tint: 0x4f46e5)),
        (["메일", "이메일", "mail", "email"], Look(symbol: "envelope", tint: 0x2563eb)),
        (["번역", "translate", "translation"], Look(symbol: "character.bubble", tint: 0x7c3aed)),
        (["코드", "개발", "code", "git", "review"], Look(symbol: "chevron.left.forwardslash.chevron.right", tint: 0x475569)),
        (["pdf", "문서", "document", "docx", "slides", "pptx", "xlsx"], Look(symbol: "doc.richtext", tint: 0xea580c)),
        (["스킬", "skill"], Look(symbol: "wand.and.stars", tint: 0x0891b2)),
    ]

    static let fallback: [Look] = [Look(symbol: "doc.text", tint: 0x2563eb), Look(symbol: "sparkles", tint: 0x7c3aed),
                                   Look(symbol: "list.bullet.clipboard", tint: 0x4f46e5), Look(symbol: "wand.and.stars", tint: 0x0891b2)]

    static func pick(name: String, title: String) -> Look {
        let text = (title + " " + name.replacingOccurrences(of: "-", with: " ")).lowercased()
        if let hit = table.first(where: { entry in entry.0.contains { text.contains($0) } }) { return hit.1 }
        let hash = name.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 9_973 }
        return fallback[abs(hash) % fallback.count]
    }
}

/// Settings › 스킬 while the feature is off and nothing has been said in its chat: the page is one card with one
/// button, and the switch beside the title, the chat and the list come once it is on (settings item 19).
enum ArisSkillsOff {
    static func shown(enabled: Bool, chatEmpty: Bool) -> Bool { !enabled && chatEmpty }
}
