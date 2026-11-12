//
//  ArisSkillJob.swift
//  aris-agent
//
//  One skill being added (from a GitHub link, a folder the user dragged in, or one 말로 만들기 wrote) or checked again,
//  as the settings chat and the notch draw it: fetching, then checking (static scan, then the AI review, with a
//  percentage), then done: added, caution (waiting for 그래도 추가 or 취소), blocked (danger; nothing kept), failed or
//  cancelled. Pure.
//

import Foundation

/// `review`: fetched and waiting for the user's 검사하고 추가 (the settings chat asks first; the notch doesn't).
enum ArisSkillJobStage: String { case fetching, review, checking, done }

enum ArisSkillJobOutcome: String { case added, caution, blocked, failed, cancelled }

struct ArisSkillJob: Equatable {
    enum Kind: String { case link, folder, made, rescan }

    let id: UUID
    let kind: Kind
    /// What the user gave: the link as shown, the folder's name, or the skill's name.
    let source: String
    var stage: ArisSkillJobStage = .fetching
    var step: ArisSkillCheckStep?
    var stepStarted = Date()
    var outcome: ArisSkillJobOutcome?
    var message: String?
    var name: String?
    var title: String?
    var summary: String?
    var owner: String?
    var version: String?
    var stars: Int?
    var license: String?
    var pushedAt: Date?
    var files: [ArisSkillFile] = []
    var findings: [ArisSkillFinding] = []
    var checked: [ArisSkillFinding] = []
    /// Where a skill waiting for the owner's decision sits (Skills/.incoming/<id>).
    var staging: URL?
    /// The brain whose review it gets, and the link it came from (kept while it waits for 검사하고 추가).
    var brain: ArisBrain?
    var origin: ArisGitHubSource?
    /// The last time the app asked about it (a job nobody watched when it ended is told through the inbox).
    var lastSeen = Date.distantPast

    init(id: UUID = UUID(), kind: Kind, source: String) {
        self.id = id
        self.kind = kind
        self.source = source
    }

    /// How far the check is, 0–100: the static scan fills the first half, the review the second, each by how long it
    /// has run (neither says how far it is), never reaching the end until it ends.
    func percent(now: Date) -> Int {
        switch stage {
        case .fetching, .review: return 0
        case .done: return 100
        case .checking:
            let elapsed = max(0, now.timeIntervalSince(stepStarted))
            switch step {
            case .review?: return 50 + Int(min(45, 45 * (1 - exp(-elapsed / 40))))
            default: return Int(min(45, 45 * (1 - exp(-elapsed / 6))))
            }
        }
    }

    func json(now: Date) -> [String: Any] {
        var object: [String: Any] = ["id": id.uuidString, "kind": kind.rawValue, "source": source, "stage": stage.rawValue,
                                     "percent": percent(now: now)]
        if let step { object["step"] = step.rawValue }
        if let outcome { object["outcome"] = outcome.rawValue }
        let optional: [String: Any?] = ["message": message, "name": name, "title": title, "summary": summary, "owner": owner,
                                        "version": version, "stars": stars, "license": license,
                                        "pushedAt": pushedAt?.timeIntervalSince1970]
        for (key, value) in optional { if let value { object[key] = value } }
        object["files"] = files.map { ["path": $0.path, "size": $0.size, "kind": $0.kind.rawValue] }
        object["findings"] = findings.map(\.json)
        object["checked"] = checked.map(\.json)
        return object
    }

    /// The line the inbox says when nobody saw the job end. `english`: in the app's language (ArisSkillLanguage); the
    /// helper's own reason for a failure follows as the helper wrote it.
    func inboxLine(english: Bool = false) -> String? {
        let name = title ?? self.name ?? (english ? "new" : "새")
        switch outcome {
        case .added?: return english ? "Added the \(name) skill." : "\(name) 스킬을 추가했어요."
        case .caution?:
            return english ? "The \(name) skill has \(findings.count == 1 ? "1 thing" : "\(findings.count) things") to look at. Choose whether to add it under Skills in Settings."
                : "\(name) 스킬은 확인할 게 \(findings.count)개 있어요. 설정의 스킬에서 추가할지 골라 주세요."
        case .blocked?: return english ? "The \(name) skill wasn't added: it's dangerous." : "\(name) 스킬은 위험해서 추가하지 않았어요."
        case .failed?: return (english ? "Couldn't add the skill. " : "스킬을 추가하지 못했어요. ") + (message ?? "")
        case .cancelled?, nil: return nil
        }
    }

    /// The inbox entry's title.
    static func inboxTitle(english: Bool) -> String { english ? "Skills" : "스킬" }
}
