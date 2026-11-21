//
//  ArisUninstallReply.swift
//  Aris
//
//  What aris-agent said to 제거 (ArisDataRoute's uninstall), and the line the sheet shows when it stopped before
//  anything went. A helper that answered and refused is not one that couldn't be reached: the sheet used to say "couldn't
//  reach the background helper" for both (VM run 2026-11-18, D3), and the refusal is in the helper's actions.log.
//  Foundation only (tested).
//

import Foundation

/// One step the agent reported (ArisDataRoute's uninstall).
struct ArisUninstallStep: Equatable {
    let step: String
    let ok: Bool
    var note: String?
}

enum ArisUninstallReply: Equatable {
    /// No answer (the helper is off, or took longer than the wait): nothing was removed.
    case unreachable
    /// The helper answered and refused (a 400 or 403: not the Aris app itself, or not the typed word): nothing was removed.
    case refused
    /// It worked through the list: each step as it went.
    case steps([ArisUninstallStep])

    /// The reply for an HTTP status and its JSON body (nil status: no answer at all).
    static func from(status: Int?, body: [String: Any]?) -> ArisUninstallReply {
        guard let status else { return .unreachable }
        guard status == 200 else { return status == 400 || status == 403 ? .refused : .unreachable }
        guard let rows = body?["steps"] as? [[String: Any]] else { return .unreachable }
        return .steps(rows.compactMap { row in
            guard let step = row["step"] as? String, let ok = row["ok"] as? Bool else { return nil }
            return ArisUninstallStep(step: step, ok: ok, note: row["note"] as? String)
        })
    }

    /// The sheet's line when nothing was removed; nil once the agent did its steps and the app went to the Trash.
    /// Each line is whole, so the settings window finds its English (ArisSettingsCopy).
    var stoppedLine: String? {
        switch self {
        case .unreachable:
            return "백그라운드 에이전트에 연결하지 못해서 아무것도 지우지 않았어요. Aris를 다시 시작한 뒤 해 주세요."
        case .refused:
            return "백그라운드 에이전트가 제거를 거절해서 아무것도 지우지 않았어요."
        case .steps(let steps):
            guard steps.first(where: { $0.step == "app" })?.ok != true else { return nil }
            return steps.first?.note?.contains("translocated") == true
                ? "Aris 앱을 휴지통으로 옮기지 못해서 멈췄어요. 아무것도 지우지 않았어요. Aris를 응용 프로그램 폴더로 옮겨서 연 뒤 다시 해 주세요."
                : "Aris 앱을 휴지통으로 옮기지 못해서 멈췄어요. 아무것도 지우지 않았어요."
        }
    }

    /// What the sheet says when the steps are done: the rows not removed (`failedRows`, ArisDataModel's ids, with
    /// `titles` for the plain ones), each with what to do about it; then, only on a Mac that had the old helper
    /// (`oldHelper`: ArisHelperInstallWords' own note that its rows were due), the rows it may have left under a path
    /// tccutil can't name. A Mac that never had it is not told about a row that isn't there (ninth VM run, item 6:
    /// the red line stood on a fresh install). Whole lines, so the window finds their English.
    static func leftLines(failedRows: Set<String>, titles: [String], oldHelper: Bool) -> [String] {
        var lines: [String] = []
        if !titles.isEmpty { lines.append("이건 지우지 못했어요: \(titles.joined(separator: ", ")). Finder에서 직접 지워 주세요.") }
        if failedRows.contains("permissions") { lines.append(permissionsLine) }
        // A row Aris can't remove at all says so itself from the start, with what to do (`notRemovable`): it gets no
        // second line here (eighth VM run, item 9: the sandbox folder's note stood twice, in its row and in red).
        if failedRows.contains("sandbox"), !notRemovable.contains("sandbox") { lines.append(sandboxLine) }
        if oldHelper { lines.append(oldRowsLine) }
        return lines
    }

    /// Whether this Mac had the old helper, as far as Aris knows: its line about the old rows became due here at some
    /// launch (an install switched from it, or Aris was already set up when the rows became known), said since or
    /// not. Aris can't read the privacy lists themselves, so this is the nearest thing to "the row exists".
    static func hadOldHelper(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: ArisHelperInstallWords.oldRowsDueKey) || defaults.bool(forKey: ArisHelperInstallWords.oldRowsSaidKey)
    }

    // MARK: - The list before and after

    /// The rows Aris can't remove at all: macOS keeps the sandbox folder for the app (the helper never tries it). They
    /// are shown that way from the start, never as a ticked box that turns red afterwards (third VM run: "샌드박스 폴더"
    /// stood checked, and only the end said it wasn't removed).
    static let notRemovable: Set<String> = ["sandbox"]
    /// What such a row says under its name from the start, with what to do.
    static let sandboxBefore = "macOS가 지켜서 Aris는 지울 수 없어요. 제거가 끝나면 Finder에서 ~/Library/Containers/com.lumenjsn.aris를 휴지통으로 옮겨 주세요."
    static let sandboxTag = "직접 지워요"

    /// What a row's lead shows.
    enum Mark: Equatable {
        /// The box the user turns off to keep their records.
        case choice
        /// Ticked, not to be changed: it will be removed.
        case willRemove
        /// Aris can't remove it: an info mark, before and after.
        case byHand
        /// Kept (the records, when the box was off).
        case kept
        case removed
        case failed
        /// Not reached yet while the rows tick.
        case pending
    }

    /// The lead of row `id` (at `index`): before the uninstall (`done` nil) and while its rows tick.
    static func mark(_ id: String, index: Int, done: Int?, kept: Bool, failed: Set<String>) -> Mark {
        if notRemovable.contains(id) { return .byHand }
        guard let done else { return id == "data" ? .choice : .willRemove }
        if kept { return .kept }
        guard index < done else { return .pending }
        return failed.contains(id) ? .failed : .removed
    }

    /// The rows with a line of their own (the rest are named together).
    static let ownLines: Set<String> = ["permissions", "sandbox"]

    static let sandboxLine = "Aris의 샌드박스 폴더(~/Library/Containers/com.lumenjsn.aris)는 macOS가 지켜서 Aris가 지우지 않았어요. Finder에서 휴지통으로 옮겨 주세요."
    static let permissionsLine = "개인정보 보호 및 보안에 Aris 줄이 일부 남았어요. 시스템 설정에서 빼 주세요."
    static let oldRowsLine = "예전 버전이 남긴 ‘aris-agent’ 줄이 손쉬운 사용이나 화면 기록에 보이면 시스템 설정에서 빼 주세요."

    /// The sheet's new words in English (ArisSettingsCopyMore).
    static let english: [String: String] = [
        sandboxLine: "Aris's sandbox folder (~/Library/Containers/com.lumenjsn.aris) is guarded by macOS, so Aris didn't remove it. Move it to the Trash in Finder.",
        permissionsLine: "Some of Aris's rows are still in Privacy & Security. Remove them in System Settings.",
        oldRowsLine: "If an “aris-agent” row from an earlier version shows in Accessibility or Screen Recording, remove it in System Settings.",
        "권한 기록": "Permission rows", "개인정보 보호 및 보안의 Aris 줄": "Aris's rows in Privacy & Security",
        "샌드박스 폴더": "Sandbox folder", "~/Library/Containers/com.lumenjsn.aris": "~/Library/Containers/com.lumenjsn.aris",
        sandboxBefore: "macOS guards it, so Aris can't remove it. Once the uninstall is done, move ~/Library/Containers/com.lumenjsn.aris to the Trash in Finder.",
        sandboxTag: "You remove it",
    ]

    /// The agent's steps, when it got to them.
    var steps: [ArisUninstallStep]? {
        if case .steps(let steps) = self { return steps }
        return nil
    }
}
