// Tests for fix-16 (the twelfth VM pass on c2e1826c, qa/vm-run-1111/NOTES-twelfth-final-raw.txt): "이번 주 금요일"
// said on a Saturday was stored with an end in the past; the Settings sidebar's last row (정보), chosen and scrolled to,
// stayed under the bottom fade; the English "Notch · Side notch…" was cut. Temp folders only, never ~/.config/aris.
// Called from main.swift; uses its check().
import AppKit
import Foundation

private let fix16Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func fix16Source(_ path: String) -> String { (try? String(contentsOf: fix16Root.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runFix16Tests() {
    fix16ThisWeekTests()
    fix16StoredEndTests()
    fix16SidebarFadeTests()
    fix16SidebarLabelTests()
}

// MARK: - 1. "이번 주 X요일" once that day has passed

/// Monday 9 … Sunday 15 November 2026 (a week as the user's calendar has it, Monday first), at `hour` here.
private func fix16Day(_ day: Int, hour: Int = 10) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)) ?? Date()
}
private func fix16End(_ day: Int) -> Date { ArisMemoryWhen.endOf(fix16Day(day, hour: 12), calendar: .current) }

private func fix16ThisWeekTests() {
    let names = ["월", "화", "수", "목", "금", "토", "일"]
    // Every weekday said on every day of the week: this week's when it is still to come (or today), else the coming one.
    for today in 0..<7 {
        let now = fix16Day(9 + today)
        for (index, name) in names.enumerated() {
            let expected = index >= today ? fix16End(9 + index) : fix16End(16 + index)
            for text in ["이번 주 \(name)요일에 부산 가", "이번주 \(name)요일 회의"] {
                let end = ArisMemoryWhen.end(of: text, from: now)
                check(end == expected && (end ?? .distantPast) >= now,
                      "fix-16 this week: \"\(text)\" said on \(names[today])요일 ends \(expected) (got \(end.map { "\($0)" } ?? "nil"))")
            }
        }
    }
    // The VM's case: Saturday 14 November, "이번 주 금요일" → Friday 20, not Friday 13.
    let saturday = fix16Day(14, hour: 11)
    check(ArisMemoryWhen.end(of: "이번 주 금요일에 부산 가", from: saturday) == fix16End(20),
          "fix-16 this week: 이번 주 금요일 said on a Saturday is the coming Friday")
    // Said late on the day itself it is still today; the other weeks are untouched.
    check(ArisMemoryWhen.end(of: "이번 주 토요일에 캠핑", from: fix16Day(14, hour: 23)) == fix16End(14), "fix-16 this week: the same day late at night is today")
    check(ArisMemoryWhen.end(of: "다음 주 금요일에 발표", from: saturday) == fix16End(20)
          && ArisMemoryWhen.end(of: "다다음 주 월요일에 출장", from: saturday) == fix16End(23)
          && ArisMemoryWhen.end(of: "다음 주 월요일", from: fix16Day(9)) == fix16End(16),
          "fix-16 this week: 다음 주 / 다다음 주 still count from this week")
    check(ArisMemoryWhen.end(of: "this Friday dinner", from: saturday) == fix16End(20) && ArisMemoryWhen.end(of: "금요일에 부산 가", from: saturday) == fix16End(20),
          "fix-16 this week: 'this Friday' and a bare 금요일 were already the coming one")
    // The seventh pass's Friday keeps its own day.
    check(ArisMemoryWhen.end(of: "이번 주 금요일에 부산 가", from: fix16Day(13)) == fix16End(13), "fix-16 this week: said on the Friday itself, it is that day")
}

// MARK: - 1b. A new event is never stored with an end in the past

private func fix16StoredEndTests() {
    let saturday = fix16Day(14, hour: 11)
    let past = ArisMemoryCandidate(kind: .event, subject: "", text: "지난 주 금요일에 부산 갔어", confidence: 1)
    check(ArisMemoryWhen.end(of: past.text, from: saturday) != nil && ArisMemoryStore.ends(past, turnAt: saturday) == nil,
          "fix-16 stored end: a day already past when said (지난 주 금요일) is kept with no end, never as over")
    let dated = ArisMemoryCandidate(kind: .event, subject: "", text: "2026-11-02 마감이었어", confidence: 1)
    check(ArisMemoryStore.ends(dated, turnAt: saturday) == nil, "fix-16 stored end: a written date already past has no end")
    let coming = ArisMemoryCandidate(kind: .event, subject: "", text: "이번 주 금요일에 부산 가", confidence: 1)
    check(ArisMemoryStore.ends(coming, turnAt: saturday) == fix16End(20), "fix-16 stored end: 이번 주 금요일 on a Saturday ends next Friday")
    let today = ArisMemoryCandidate(kind: .event, subject: "", text: "오늘 치과 가", confidence: 1)
    check(ArisMemoryStore.ends(today, turnAt: fix16Day(14, hour: 23)) == fix16End(14), "fix-16 stored end: today's event ends tonight")

    // Through 기억해 on the VM's Saturday: an event, current now, valid until the end of Friday 20 November.
    for (say, expected) in [("이번 주 금요일에 부산 가", Optional(fix16End(20))), ("지난 주 금요일에 부산 갔어", nil)] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix16-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ArisMemoryStore.at(folder)
        let curator = ArisMemoryCurator(store: store, clock: { saturday }, extract: { _ in nil }, summarize: { _ in nil })
        _ = curator.answer(.remember(say), said: "기억해: " + say, now: saturday)
        let record = store.all().first { $0.text.contains("부산") }
        check(record?.kind == .event && record?.validUntil == expected && record?.isCurrent(at: saturday) == true
              && (record?.validUntil.map { $0 >= saturday } ?? true),
              "fix-16 stored end: 기억해: \(say) on a Saturday → 일정, current, until \(expected.map { "\($0)" } ?? "no end") (got \(String(describing: record?.validUntil)))")
    }
}

// MARK: - 2. The sidebar's bottom fade

private func fix16SidebarFadeTests() {
    typealias M = ArisSidebarMetrics
    let list = M.pagesHeight()
    let box = 480.0
    let about = M.rowSpan(.about), conversation = M.rowSpan(.aris)
    check(list == M.height() - (M.top + M.greeting + M.greetingGap + M.searchHeight + M.searchGap + M.bottom),
          "fix-16 fade: the pages' own height is the sidebar's less its header and bottom")
    let firstTop: Double = M.firstGroupTop + M.groupLabel + M.groupBottom
    let aboutLast: Bool = about?.bottom == list
    let conversationFirst: Bool = conversation?.top == firstTop && conversation.map { $0.bottom - $0.top } == M.row
    check(aboutLast && conversationFirst, "fix-16 fade: the rows lie where the list draws them (대화 under its group name, 정보 last)")
    // Rows: each 44 tall, in order, none overlapping.
    let spans: [(top: Double, bottom: Double)] = ArisSettingsPage.allCases.compactMap { M.rowSpan($0) }
    var ordered = spans.count == ArisSettingsPage.allCases.count
    for index in spans.indices.dropFirst() where spans[index - 1].bottom > spans[index].top { ordered = false }
    check(ordered, "fix-16 fade: every page has a row, in the sidebar's order")
    func span(_ page: ArisSettingsPage, _ top: Double) -> (top: Double, bottom: Double)? { M.rowSpan(page).map { ($0.top + top, $0.bottom + top) } }
    // At the top of a list taller than its box, with 대화 chosen: more below, so the end fades.
    check(M.fades(listHeight: list, boxHeight: box, listTop: 0, chosen: span(.aris, 0)), "fix-16 fade: more below and the chosen row high up → the end fades")
    // Scrolled to its end: nothing below, nothing fades (whatever is chosen).
    let end = box - list
    check(!M.fades(listHeight: list, boxHeight: box, listTop: end, chosen: span(.about, end))
          && !M.fades(listHeight: list, boxHeight: box, listTop: end, chosen: span(.aris, end))
          && !M.fades(listHeight: list, boxHeight: box, listTop: end, chosen: nil),
          "fix-16 fade: scrolled to the end, the last row (정보) isn't faded, chosen or not")
    // Half way, with the chosen row in the fade band: no fade over it.
    let half = -(list - box) / 2
    let band = ArisSettingsPage.allCases.first { page in span(page, half).map { $0.bottom > box - M.fade && $0.top < box } ?? false }
    check(band.map { !M.fades(listHeight: list, boxHeight: box, listTop: half, chosen: span($0, half)) } == true,
          "fix-16 fade: the chosen row lying in the fade band is never faded")
    check(M.fades(listHeight: list, boxHeight: box, listTop: half, chosen: span(.aris, half)) || span(.aris, half).map { $0.bottom > box - M.fade } == true,
          "fix-16 fade: half way with the chosen row out of the band, the end fades")
    // A list that fits fades nowhere; one a hair taller than its box neither.
    check(!M.fades(listHeight: list, boxHeight: list + 20, listTop: 0, chosen: nil) && !M.fades(listHeight: list, boxHeight: list - 0.5, listTop: 0, chosen: nil),
          "fix-16 fade: a list that fits its box has no fade")
    // The view reads it: the scroller tracks where its list is, and both the scroller and the still drawing ask fades.
    let sidebar = fix16Source("Aris/components/Settings/ArisSettingsSidebar.swift")
    check(sidebar.contains("ArisSidebarMetrics.fades(") && sidebar.contains(".coordinateSpace(name: Self.scrollSpace)")
          && sidebar.contains("listTop = frame.minY") && sidebar.contains("ArisSidebarMetrics.rowSpan(nav.page)")
          && !sidebar.contains("let more = listHeight > box.size.height + 1")
          && sidebar.components(separatedBy: "fadeMask(fades(").count == 3,
          "fix-16 fade: the sidebar fades from its scroll position and the chosen row, live and in the still drawing")
}

// MARK: - 3. English sidebar names fit their row

private func fix16SidebarLabelTests() {
    typealias M = ArisSidebarMetrics
    let file = fix16Root.appendingPathComponent("Aris/components/Settings/Settings.xcstrings")
    let pairs = ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: file)) ?? Data())
    let font = NSFont.systemFont(ofSize: M.labelSize, weight: .medium)
    func width(_ text: String, _ font: NSFont) -> Double { Double((text as NSString).size(withAttributes: [.font: font]).width) }
    let newMark = width(pairs["새"] ?? "New", NSFont.systemFont(ofSize: M.newSize, weight: .semibold)) + 2 * M.newPadding + M.iconGap
    check(M.labelRoom == 124.5, "fix-16 labels: a name has 220 − 2 × 16 − 15.5 − 16 − 20 − 12 = 124.5 pt (got \(M.labelRoom))")
    for page in ArisSettingsPage.allCases {
        guard let english = pairs[page.title] else { check(false, "fix-16 labels: \(page.title) has an English name"); continue }
        let room = M.labelRoom - (page.isNew ? newMark : 0)
        check(width(english, font) <= room, "fix-16 labels: \"\(english)\" fits its row at 14 pt (\(Int(width(english, font))) of \(Int(room)) pt)")
        check(width(page.title, font) <= room, "fix-16 labels: \(page.title) fits its row at 14 pt")
    }
    check(pairs["노치 · 사이드 노치"] == "Notch", "fix-16 labels: the notch page is \"Notch\" in English (\"Notch · Side notches\" was cut)")
    ArisSettingsCopy.install(pairs)
    let shownPath = ArisSettingsPath.shown("설정 › 노치 · 사이드 노치", english: true)
    ArisSettingsCopy.install([:])
    check(shownPath == "Settings › Notch", "fix-16 labels: a reply's path names it as the sidebar does (\(shownPath))")
    // The name has the whole room after the icon: no spacer (and its 12-pt gap) after it.
    let sidebar = fix16Source("Aris/components/Settings/ArisSettingsSidebar.swift")
    let item = sidebar.components(separatedBy: "private struct ArisNavItem").last?.components(separatedBy: "struct ArisGlassHighlight").first ?? ""
    check(item.contains(".frame(maxWidth: .infinity, alignment: .leading)") && !item.contains("Spacer("),
          "fix-16 labels: the sidebar name fills the row after the icon, with no spacer gap eating its room")
}
