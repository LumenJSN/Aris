//
//  ArisMemoryImportBoard.swift
//  Aris
//
//  설정 › 기억 › 다른 AI에서 가져오기, as values: what the sheet shows at each of its steps and what a press changes
//  (the view only draws this). Step 1 the request to copy, step 2 the paste, step 3 every line the agent read with
//  what it made of it and a tick, step 4 the receipt with 되돌리기. Reading the paste, judging each line and writing
//  the memories are the agent's (ArisMemoryImport: the pasted text never reaches an AI); here are the groups, the
//  ticks, joining a second part of an export to the same preview, and the words. No AI is named anywhere: the source
//  is whatever the user types. Also the words that open the page ("다른 AI에서 기억 가져올래"). Foundation only (tested).
//

import Foundation

/// One line of the paste as the agent's POST /memory {"op": "importPreview"} gives it.
struct ArisImportRow: Decodable, Equatable, Identifiable, Sendable {
    var n: Int
    /// "instructions", "personal", "career", "projects", "preferences" or "other".
    let category: String
    /// "2025-03-01", or "" when the line had none.
    let date: String
    let text: String
    /// The kind Aris stores it as ("preference", "fact", "project", "person", "routine").
    let kind: String
    /// "new", "known", "updates", "older", "secret" or "acts".
    let state: String
    var ticked: Bool
    /// Exactly what will be stored when it differs from `text` (the memory's short title); nil when the line is stored
    /// as it reads.
    var stored: String?
    /// The wording of the memory this line would replace (an "updates" line).
    var replaces: String?
    /// Its date was later than tomorrow and was left out (the line stands on its own, not ticked).
    var future: Bool?
    /// Not ticked because it carries a link or an email address.
    var address: Bool?

    var id: Int { n }
    /// A tick can't import a secret, or a wording older than what Aris already has.
    var importable: Bool { state != "secret" && state != "older" }
}

/// What the agent wrote: POST /memory {"op": "importApply"}.
struct ArisImportReceipt: Decodable, Equatable, Sendable {
    let batch: String
    let added: Int
    let updated: Int
    let known: Int
    let skipped: Int

    var written: Int { added + updated + known }
}

enum ArisMemoryImportCopy {
    static let rowTitle = "다른 AI에서 가져오기"
    static let rowDesc = "쓰던 AI가 나에 대해 기억하는 것을 줄마다 확인하고 Aris의 기억으로 옮겨요."
    static let rowButton = "가져오기"
    static let sheetTitle = "다른 AI에서 기억 가져오기"
    static let stepCopy = "쓰던 AI에게 아래 요청을 보내고, 받은 답을 다음 단계에 붙여 넣어요."
    static let stepPaste = "그 AI가 쓴 답을 통째로 붙여 넣거나, .txt나 .md 파일을 끌어다 놓아요."
    static let stepPreview = "체크한 줄만 기억에 들어가요."
    static let copyButton = "요청 복사"
    static let copied = "복사했어요"
    static let sourceLabel = "가져오는 곳"
    static let sourceHint = "쓰던 AI 이름 (선택)"
    static let pasteHint = "여기에 붙여 넣기"
    static let next = "다음"
    static let back = "뒤로"
    static let cancel = "취소"
    static let preview = "미리 보기"
    static let reading = "읽는 중…"
    static let addMore = "이어 붙이기"
    static let done = "완료"
    static let undo = "되돌리기"
    static let undone = "되돌렸어요"
    static let failed = "가져오지 못했어요. 잠시 뒤에 다시 해 주세요."
    static let unreadable = "읽지 못한 줄"
    static let unreadableNote = "날짜와 내용이 있는 줄이 아니라서 가져오지 않아요."
    static let instructionNote = "답하는 방식에 대한 부탁이에요. 체크하면 Aris가 답할 때 참고하는 취향으로 기억해요."
    static let moreNote = "내보낸 내용이 더 있다고 해요. 다음 부분을 받으면 이어 붙이기로 이 목록에 더할 수 있어요."
    static let nothing = "가져올 줄을 찾지 못했어요. 답 전체를 붙여 넣었는지 확인해 주세요."
    static let noDate = "날짜 없음"

    static let categories: [String: String] = ["instructions": "지시 사항", "personal": "개인 정보", "career": "경력", "projects": "프로젝트", "preferences": "선호", "other": "그 밖"]
    static let kinds: [String: String] = ["preference": "취향", "fact": "나에 대해", "project": "하는 일", "person": "사람", "routine": "습관"]
    /// The mark a line carries when it isn't simply new.
    static let states: [String: String] = ["known": "이미 알아요", "updates": "새 표현으로 바꿔요", "older": "Aris 기억이 더 새로워요", "secret": "비밀처럼 보여서 뺐어요",
                                           "acts": "명령처럼 읽혀요"]
    /// The marks of a line left unticked for a reason of its own.
    static let futureNote = "날짜가 미래라서 뺐어요"
    static let addressNote = "주소가 있어서 직접 확인해요"

    /// "37개 가져오기".
    static func importButton(_ count: Int, english: Bool) -> String { english ? "Import \(count)" : "\(count)개 가져오기" }
    /// "37개 가져왔어요".
    static func imported(_ count: Int, english: Bool) -> String { english ? (count == 1 ? "Imported 1 memory" : "Imported \(count) memories") : "\(count)개 가져왔어요" }
    /// "새로 30 · 바꿈 2 · 이미 알던 것 5 · 건너뜀 1".
    static func breakdown(_ receipt: ArisImportReceipt, english: Bool) -> String {
        let parts = english ? [("new", receipt.added), ("replaced", receipt.updated), ("already known", receipt.known), ("skipped", receipt.skipped)]
                            : [("새로", receipt.added), ("바꿈", receipt.updated), ("이미 알던 것", receipt.known), ("건너뜀", receipt.skipped)]
        return parts.filter { $0.1 > 0 }.map { english ? "\($0.1) \($0.0)" : "\($0.0) \($0.1)" }.joined(separator: " · ")
    }

    /// Korean → English, for the settings pages' lookup (ArisSettingsCopyMore).
    static let english: [String: String] = [
        rowTitle: "Import from another AI", rowDesc: "Brings what another AI remembers about you into Aris's memory, after you check each line.",
        rowButton: "Import", sheetTitle: "Import memory from another AI",
        stepCopy: "Send the request below to the AI you used, then paste its answer in the next step.",
        stepPaste: "Paste that AI's whole answer, or drop a .txt or .md file here.",
        stepPreview: "Only the lines you tick go into memory.",
        copyButton: "Copy request", copied: "Copied", sourceLabel: "Coming from", sourceHint: "The AI's name (optional)", pasteHint: "Paste here",
        next: "Next", back: "Back", cancel: "Cancel", preview: "Preview", reading: "Reading…", addMore: "Add another part", done: "Done", undo: "Undo", undone: "Undone",
        failed: "The import didn't go through. Try again in a moment.",
        unreadable: "Lines that couldn't be read", unreadableNote: "These aren't lines with a date and an item, so they aren't imported.",
        instructionNote: "These are requests about how to answer. Tick one and Aris remembers it as a preference it keeps in mind when it answers.",
        moreNote: "The export says there is more. When you have the next part, Add another part joins it to this list.",
        nothing: "No lines to import were found. Check that the whole answer was pasted.", noDate: "No date",
        "지시 사항": "Instructions", "개인 정보": "Personal details", "경력": "Career", "프로젝트": "Projects", "선호": "Preferences", "그 밖": "Other",
        "이미 알아요": "Already known", "새 표현으로 바꿔요": "Replaces older wording", "Aris 기억이 더 새로워요": "Aris has a newer one", "비밀처럼 보여서 뺐어요": "Looks like a secret: left out",
        "명령처럼 읽혀요": "Reads like an order", "가져옴": "Imported", "지시": "Instruction",
        futureNote: "Date is in the future: left out", addressNote: "Has an address: check it yourself",
    ]
}

/// The sheet as a value.
struct ArisMemoryImportBoard: Equatable {
    enum Step: Equatable { case copy, paste, preview, done }

    static let mostPaste = 200_000
    static let order = ["instructions", "personal", "career", "projects", "preferences", "other"]

    var step = Step.copy
    /// The request to copy, in the UI's language (from the agent); "" until it answered.
    var prompt = ""
    /// The AI it comes from, as the user typed it; may be empty.
    var source = ""
    var pasted = ""
    var rows: [ArisImportRow] = []
    var unreadable: [String] = []
    /// What the export said about itself: nil when it said nothing.
    var complete: Bool?
    var receipt: ArisImportReceipt?
    var undone = false
    /// The agent is reading or writing.
    var busy = false
    /// The last call didn't go through.
    var failed = false

    struct Group: Equatable, Identifiable {
        let id: String
        let rows: [ArisImportRow]
    }

    /// The lines by group, in the export's own order; a group with none is left out.
    var groups: [Group] {
        Self.order.compactMap { category in
            let mine = rows.filter { $0.category == category }
            return mine.isEmpty ? nil : Group(id: category, rows: mine)
        }
    }

    /// The lines a press of the import button sends: ticked, and importable at all.
    var chosen: [ArisImportRow] { rows.filter { $0.ticked && $0.importable } }
    var canPreview: Bool { !busy && !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canImport: Bool { !busy && !chosen.isEmpty }

    mutating func toggle(_ n: Int) {
        guard let index = rows.firstIndex(where: { $0.n == n }), rows[index].importable else { return }
        rows[index].ticked.toggle()
    }

    /// The agent's reading of a paste. The first part replaces the list; a later part ("이어 붙이기") joins it: its lines
    /// come after the ones there (the ticks already made stay), a line already in the list is not added twice, and what
    /// the newest part says about being complete is what counts.
    mutating func show(_ fresh: [ArisImportRow], unreadable more: [String], complete said: Bool?, joining: Bool) {
        let normal = { (text: String) in text.lowercased().filter { $0.isLetter || $0.isNumber } }
        if joining {
            var seen = Set(rows.map { $0.category + "|" + normal($0.text) })
            for var row in fresh where seen.insert(row.category + "|" + normal(row.text)).inserted {
                row.n = (rows.map(\.n).max() ?? 0) + 1
                rows.append(row)
            }
            unreadable += more.filter { !unreadable.contains($0) }
        } else {
            rows = fresh
            unreadable = more
        }
        complete = said
        pasted = ""
        step = .preview
        busy = false
        failed = false
    }

    /// The body of POST /memory {"op": "importApply"}: only what each chosen line is, never what Aris made of it (the
    /// agent judges each line again).
    var applyLines: [[String: String]] { chosen.map { ["category": $0.category, "date": $0.date, "text": $0.text] } }

    /// A row's small line: "2025-03-01 · 취향" (the date as written, the kind in Korean: the page's lookup says it in English).
    static func sub(_ row: ArisImportRow) -> String {
        [row.date.isEmpty ? ArisMemoryImportCopy.noDate : row.date, ArisMemoryImportCopy.kinds[row.kind] ?? row.kind].joined(separator: " · ")
    }

    /// The text a dropped file gives the paste box: a .txt or .md file's own text, cut to the most a paste may be; nil
    /// for any other file.
    static func dropped(name: String, data: Data) -> String? {
        guard ["txt", "md", "markdown", "text"].contains((name as NSString).pathExtension.lowercased()), let text = String(data: data, encoding: .utf8) else { return nil }
        return String(text.prefix(mostPaste))
    }
}

/// "다른 AI에서 기억 가져올래", "import my memory from another AI": the words that open the import page (no AI is asked).
/// Naming an AI works too and only fills in where it comes from; nothing else is different.
enum ArisMemoryImportWords {
    struct Asked: Equatable {
        /// The AI named, as its own name is written; nil for "다른 AI".
        var source: String?
    }

    private static let names: [(String, [String])] = [
        ("Claude", ["클로드", "claude"]), ("ChatGPT", ["챗지피티", "챗gpt", "chatgpt", "지피티", "gpt"]), ("Gemini", ["제미나이", "제미니", "gemini"]),
        ("Grok", ["그록", "grok"]), ("Perplexity", ["퍼플렉시티", "perplexity"]), ("Copilot", ["코파일럿", "copilot"]),
    ]
    private static let generic = ["다른ai", "다른에이아이", "다른인공지능", "딴ai", "anotherai", "otherai", "anotherassistant", "otherassistant"]
    private static let verbs = ["가져올래", "가져와", "가져오", "가져올", "불러와", "불러오", "불러올", "옮겨", "옮길", "옮기", "import", "bringover", "bringin", "transfer", "moveover"]
    private static let things = ["기억", "메모리", "memory", "memories"]

    static func asked(_ said: String) -> Asked? {
        let compact = said.precomposedStringWithCanonicalMapping.lowercased().filter { !$0.isWhitespace && !"?.!,~".contains($0) }
        guard compact.count <= 60, things.contains(where: compact.contains), verbs.contains(where: compact.contains) else { return nil }
        // From somewhere: "다른 AI", or an AI by its name. "이거 기억해", "어제 기억 가져와"? are not this.
        let source = names.first { $0.1.contains(where: compact.contains) }?.0
        if generic.contains(where: compact.contains) { return Asked(source: source) }
        // An AI by its name needs the "from" too ("클로드에서 …", "… from Gemini"): "클로드 기억 옮겨 적어 줘" is something else.
        guard source != nil, compact.contains("에서") || compact.contains("from") || compact.contains("한테서") || compact.contains("에있는") else { return nil }
        return Asked(source: source)
    }

    /// What Aris says as the page opens.
    static func reply(korean: Bool) -> String {
        korean ? "설정 › 기억에서 가져오기를 열었어요. 거기 있는 요청을 쓰던 AI에게 보내고 답을 붙여 넣어 주세요."
               : "I opened the import in Settings › Memory. Send the request there to the AI you used and paste its answer."
    }
}
