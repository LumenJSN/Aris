//
//  ArisTodoView.swift
//  Aris
//
//  The 할 일 tab, on Apple Reminders: a "+ 새로운 할 일" row that opens a composer (title, date, time, list, notes;
//  "내일 3시 보고서" fills the date itself), your open reminders grouped by when they're due, then the Canvas
//  deadlines still to hand in. Ticking a ring fills it with its list's colour and draws a check, strikes the title
//  through and, after a short hold (click again to undo), folds the row away and completes the reminder. A row opens
//  its composer to edit or delete.
//

import AppKit
import SwiftUI

extension Color {
    /// "#rrggbb".
    init(todoHex hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0x8e8e93
        self.init(.sRGB, red: Double(value >> 16 & 0xff) / 255, green: Double(value >> 8 & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }
}

struct ArisTodoView: View {
    @ObservedObject private var model = ArisTodoModel.shared
    @ObservedObject private var reminders = ArisReminders.shared
    @ObservedObject private var panels = ArisSidePanels.shared
    /// The side panels' demo: its samples, without Reminders' access lines, menus or composer.
    @ObservedObject private var demo = ArisSideDemo.shared
    private var composing: String? {
        get { model.composing }
        nonmutating set { model.composing = newValue }
    }

    /// A finished row (and a group heading left with nothing under it) folds shut as it fades, and the rest closes up.
    static let leave = AnyTransition.arisFold
    static let dueSoon = Color(red: 1, green: 0.55, blue: 0.35)
    private static let overdue = Color(red: 0xf1 / 255, green: 0x6c / 255, blue: 0x70 / 255)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if !demo.isOn, let error = reminders.lastError {
                        Text(error).font(.system(size: 11)).foregroundStyle(Self.overdue)
                            .padding(10).onTapGesture { reminders.lastError = nil }
                    }
                    if demo.isOn {
                        newRow
                    } else if !reminders.authorized {
                        Button { openSettings() } label: {
                            Text(ArisUIWords.text("미리 알림 접근을 허용해 주세요 ›", "Allow access to Reminders ›")).font(.system(size: 11.5)).foregroundStyle(ArisGlass.secondaryText)
                                .padding(EdgeInsets(top: 10, leading: 12, bottom: 6, trailing: 12))
                        }
                        .buttonStyle(.plain)
                    } else if reminders.includedLists.isEmpty {
                        Button(ArisUIWords.text("설정에서 표시할 목록을 골라 주세요 ›", "Choose the lists to show in Settings ›")) { openSettings() }
                            .buttonStyle(.plain).font(.system(size: 11.5)).padding(12)
                    } else if composing == "" {
                        ArisTodoComposer(item: nil, close: close)
                    } else {
                        newRow
                    }
                    // Canvas deadlines first: they're fixed and usually the most pressing.
                    if !model.due.isEmpty {
                        ArisSideStyle.dayHeading(ArisTodoWords.deadlines(demo: demo.isOn))
                        ForEach(model.due.prefix(5)) { due in
                            let (tag, soon) = Self.when(due.at)
                            ArisTodoRow(id: due.id, title: "\(Self.shortCourse(due.course)) \(due.title)", dueText: tag, overdue: soon, listName: nil,
                                        color: .white.opacity(0.5), hasNote: false,
                                        onComplete: { Task { await model.hide(due) } }, onOpen: { model.open(due) })
                                .transition(Self.leave)
                                .help(ArisUIWords.text("링을 누르면 다 했어요 (목록에서만 숨겨요) · 행을 누르면 Canvas에서 열어요", "Click the ring when it's done (it's only hidden from this list) · click the row to open it in Canvas"))
                        }
                    }
                    ForEach(ArisTodoGroup.grouped(model.items, now: context.date), id: \.group) { section in
                        Text(section.group.name())
                            .font(.system(size: 10.5, weight: .semibold)).tracking(0.1)
                            .foregroundStyle(section.group == .overdue ? Self.overdue.opacity(0.9) : .white.opacity(0.42))
                            .padding(EdgeInsets(top: 13, leading: 12, bottom: 5, trailing: 12))
                            .transition(Self.leave)
                        ForEach(section.items) { item in
                            if composing == item.id {
                                ArisTodoComposer(item: item, close: close)
                            } else {
                                ArisTodoRow(id: item.id, title: item.title, dueText: item.dueLabel(now: context.date), overdue: section.group == .overdue,
                                            listName: item.listName, color: Color(todoHex: item.colorHex), hasNote: !(item.notes ?? "").isEmpty,
                                            onComplete: { animateAway { model.complete(item) } }, onOpen: { open(item.id) })
                                    .contextMenu { if !demo.isOn { menu(item) } }
                                    .transition(Self.leave)
                            }
                        }
                    }
                    if reminders.authorized || demo.isOn, model.items.isEmpty, composing != "" {
                        ArisSideStyle.empty(ArisUIWords.text("할 일이 없어요", "Nothing to do"))
                    }
                }
                .padding(ArisSideStyle.listInsets(underHeader: true, toEdge: true))
            }
            // The list: behind the header and down to the panel's edge, fading in under the one and out at the other.
            .modifier(ArisSideListFrame(underHeader: true, toEdge: true))
            // After the mask: the mask must cover the rows widened by -7, or it cuts their rounded ends off.
            .padding(.horizontal, -7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await model.refresh() }
        .onChange(of: model.composing) { _, _ in claimKeyboard() }
        .onAppear { claimKeyboard() }
        .onDisappear { panels.holdOpen = false }
    }

    /// While a composer is open the panel is held open and takes the keyboard (it is non-activating, so the app is
    /// asked to activate too, for Korean input).
    private func claimKeyboard() {
        panels.holdOpen = model.composing != nil
        guard model.composing != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        for delay in [0.05, 0.3, 0.6] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { if model.composing != nil { panels.focus(.right) } } }
    }

    private func animateAway(_ change: () -> Void) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { change() } else { withAnimation(.easeInOut(duration: 0.28)) { change() } }
    }

    /// "+ 새로운 할 일".
    private var newRow: some View {
        ArisSideRow { open("") } content: {
            Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55)).frame(width: 16)
            Text(ArisUIWords.text("새로운 할 일", "New to-do")).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
        }
    }

    /// No composer during the demo: nothing it saves could be kept.
    private func open(_ id: String) {
        guard !demo.isOn else { return }
        withAnimation(.easeOut(duration: 0.18)) { composing = id }
    }

    private func close() { withAnimation(.easeOut(duration: 0.18)) { composing = nil } }

    private func openSettings() {
        ArisSettingsNav.shared.page = .todo
        ArisStepAside.showSettings()
    }

    @ViewBuilder private func menu(_ item: ArisTodoItem) -> some View {
        if item.canPostponeToTomorrow() {
            Button(ArisUIWords.text("내일로 미루기", "Put off until tomorrow")) { Task { await reminders.postponeToTomorrow(item.id) } }
        }
        Menu(ArisUIWords.text("목록 옮기기", "Move to a list")) {
            ForEach(reminders.includedLists) { list in
                Button(list.name) { Task { await reminders.move(item.id, to: list.id) } }.disabled(list.id == item.listID)
            }
        }
        Button(ArisUIWords.text("미리 알림에서 열기", "Open in Reminders")) { reminders.openInReminders(item.id) }
        Divider()
        Button(ArisUIWords.text("삭제", "Delete"), role: .destructive) { Task { await model.remove(item) } }
    }

    /// "오늘 23:59" (soon), "내일", or the weekday.
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> (String, Bool) {
        ArisDue.whenLabel(date, now: now, calendar: calendar)
    }

    /// "CSC263H1" -> "CSC263".
    static func shortCourse(_ code: String) -> String { ArisDue.shortCourse(code) }
}

/// One row: a ring, the title (two lines at most), and under it when it's due, its list, a note mark.
private struct ArisTodoRow: View {
    let id: String
    let title: String
    let dueText: String?
    let overdue: Bool
    let listName: String?
    let color: Color
    let hasNote: Bool
    let onComplete: () -> Void
    let onOpen: () -> Void

    private enum Phase { case idle, holding }

    @State private var phase = Phase.idle
    @State private var check: CGFloat = 0
    @State private var sweep: CGFloat = 0
    @State private var hold: Task<Void, Never>?
    @State private var hovering = false
    @ObservedObject private var model = ArisTodoModel.shared
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: tick) {
                ring.frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -6).padding(.top, -5).padding(.bottom, -5).padding(.trailing, -6)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .overlay { strike }
                if dueText != nil || listName != nil || hasNote {
                    HStack(spacing: 6) {
                        if let dueText { Text(dueText).foregroundStyle(overdue ? Color(red: 0xf1 / 255, green: 0x6c / 255, blue: 0x70 / 255) : .white.opacity(0.5)) }
                        if let listName {
                            HStack(spacing: 4) {
                                Circle().fill(color).frame(width: 6, height: 6)
                                Text(listName).lineLimit(1)
                            }
                            .foregroundStyle(.white.opacity(0.42))
                        }
                        if hasNote { Image(systemName: "note.text").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)) }
                    }
                    .font(.system(size: 10.5))
                }
            }
            .opacity(phase == .idle ? 1 : 0.5)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .circular).fill(hovering && phase == .idle ? ArisSideStyle.rowHover : .clear))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .circular))
        .onTapGesture { if phase == .idle { onOpen() } }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onDisappear { hold?.cancel() }
        .onChange(of: model.completeRequest) { _, request in
            if request == id { model.completeRequest = nil; tick() }
        }
    }

    private var ring: some View {
        ZStack {
            Circle().strokeBorder(phase == .idle ? Color.white.opacity(0.4) : color, lineWidth: 1.5)
            Circle().fill(color).opacity(check > 0 ? 1 : 0)
            ArisCheckmark().trim(from: 0, to: check)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .padding(4.5)
        }
        .frame(width: 16, height: 16)
    }

    /// The strikethrough sweeping across the title, left to right.
    private var strike: some View {
        GeometryReader { geometry in
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .strikethrough(true, color: .white.opacity(0.8))
                .foregroundStyle(.clear)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: geometry.size.width, alignment: .leading)
                .mask(alignment: .leading) { Rectangle().frame(width: geometry.size.width * sweep) }
        }
    }

    private func tick() {
        if phase == .holding {
            hold?.cancel()
            withAnimation(.easeOut(duration: 0.15)) { phase = .idle; check = 0; sweep = 0 }
            return
        }
        guard phase == .idle else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        phase = .holding
        if reduceMotion {
            check = 1
            sweep = 1
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { check = 1 }
            withAnimation(.easeOut(duration: 0.35)) { sweep = 1 }
        }
        hold = Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 900))
            guard !Task.isCancelled else { return }
            onComplete()
        }
    }
}

private struct ArisCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.85))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.15))
        return path
    }
}

/// The composer, in place of the add row or of the row being edited: title, date / time / list / notes chips.
private struct ArisTodoComposer: View {
    let item: ArisTodoItem?
    let close: () -> Void
    @ObservedObject private var reminders = ArisReminders.shared
    @State private var draft = ArisTodoDraft()
    /// A save is on its way to Reminders.
    @State private var saving = false
    @State private var notesOpen = false
    @State private var datePopover = false
    @State private var timePopover = false
    @State private var listPopover = false
    @ObservedObject private var model = ArisTodoModel.shared
    @FocusState private var typing: Bool

    private var parsed: (title: String, due: Date?) { draft.due == nil ? ArisTodoDate.titled(draft.title, now: .now) : (draft.title, nil) }
    private static let overdue = Color(red: 0xf1 / 255, green: 0x6c / 255, blue: 0x70 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField(ArisUIWords.text("새로운 할 일", "New to-do"), text: $draft.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1...3)
                .focused($typing)
                .onSubmit { commit() }
                .onExitCommand { close() }
            if let due = parsed.due {
                chip(icon: "sparkles", text: "\(Self.format(due, hasTime: ArisTodoModel.hasTime(due))) · 「\(parsed.title)」") { applyParsed() }
            }
            ArisFlow(spacing: 5) {
                Button { datePopover = true } label: {
                    chipLabel(icon: "calendar", text: draft.due.map { Self.format($0, hasTime: false) } ?? ArisUIWords.text("날짜", "Date"), active: draft.due != nil)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $datePopover) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach([(ArisUIWords.text("오늘", "Today"), 0), (ArisUIWords.text("내일", "Tomorrow"), 1)], id: \.0) { title, offset in popoverRow(title) { setDay(offset: offset); datePopover = false } }
                        popoverRow(ArisUIWords.text("이번 주말", "This weekend")) { setDay(weekend: true); datePopover = false }
                        popoverRow(ArisUIWords.text("다음 주", "Next week")) { setDay(offset: 7 - ((Calendar.current.component(.weekday, from: .now) + 5) % 7)); datePopover = false }
                        Divider().padding(.vertical, 4)
                        DatePicker("", selection: Binding(get: { draft.due ?? .now }, set: { setDay($0) }), displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden()
                        if draft.due != nil {
                            Divider().padding(.vertical, 4)
                            popoverRow(ArisUIWords.text("날짜 없음", "No date")) { draft.due = nil; draft.hasTime = false; datePopover = false }
                        }
                    }
                    .padding(10).frame(width: 240)
                }
                Button { timePopover = true } label: {
                    chipLabel(icon: "clock", text: draft.due.flatMap { draft.hasTime ? Self.format($0, hasTime: true, dayless: true) : nil } ?? ArisUIWords.text("시간", "Time"), active: draft.hasTime)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $timePopover) {
                    VStack(spacing: 8) {
                        DatePicker("", selection: Binding(get: { draft.due ?? .now }, set: { setTime($0) }), displayedComponents: .hourAndMinute)
                            .datePickerStyle(.stepperField).labelsHidden()
                        Button(ArisUIWords.text("시간 없음", "No time")) { draft.hasTime = false; timePopover = false }
                    }
                    .padding(12)
                }
                Button { listPopover = true } label: {
                    let list = reminders.lists.first { $0.id == draft.listID }
                    HStack(spacing: 4) {
                        Circle().fill(Color(todoHex: list?.colorHex ?? "#8e8e93")).frame(width: 7, height: 7)
                        Text(list?.name ?? ArisUIWords.text("목록", "List")).lineLimit(1)
                    }
                    .chipStyle(active: false)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $listPopover) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(reminders.includedLists) { list in
                            popoverRow(list.name, dot: Color(todoHex: list.colorHex), checked: draft.listID == list.id) { draft.listID = list.id; listPopover = false }
                        }
                    }
                    .padding(8).frame(minWidth: 160)
                }
                Button { withAnimation(.easeOut(duration: 0.15)) { notesOpen.toggle() } } label: {
                    chipLabel(icon: "note.text", text: ArisUIWords.text("메모", "Notes"), active: !draft.notes.isEmpty)
                }
                .buttonStyle(.plain)
            }
            if notesOpen || !draft.notes.isEmpty {
                TextField(ArisUIWords.text("메모", "Notes"), text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 11.5)).lineLimit(2...5).foregroundStyle(.white.opacity(0.8))
                    .onExitCommand { close() }
            }
            HStack(spacing: 12) {
                if let item {
                    Button(ArisUIWords.text("삭제", "Delete")) { Task { if await ArisTodoModel.shared.remove(item) { close() } } }
                        .foregroundStyle(Self.overdue)
                }
                Spacer(minLength: 0)
                Button(ArisUIWords.text("취소", "Cancel")) { close() }.foregroundStyle(.white.opacity(0.55))
                Button(item == nil ? ArisUIWords.text("추가", "Add") : ArisUIWords.text("저장", "Save")) { commit() }
                    .foregroundStyle(.white).fontWeight(.semibold)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5))
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArisSideStyle.pill(RoundedRectangle(cornerRadius: 12, style: .circular)))
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .onChange(of: model.chipRequest) { _, request in
            guard let request else { return }
            model.chipRequest = nil
            run(request)
        }
        .onAppear {
            draft = item.map(ArisTodoDraft.init) ?? { var fresh = ArisTodoDraft(); fresh.listID = reminders.defaultListID; return fresh }()
            notesOpen = !draft.notes.isEmpty
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { typing = true }
        }
    }

    private func popoverRow(_ title: String, dot: Color? = nil, checked: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(title).font(.system(size: 12.5))
                Spacer(minLength: 8)
                if checked { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)) }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The preview's way of pressing chips and typing: the same popovers, setters and `commit()` the controls use.
    private func run(_ request: String) {
        let parts = request.split(separator: "=", maxSplits: 1).map(String.init)
        switch parts[0] {
        case "date": datePopover = true
        case "time": timePopover = true
        case "list": listPopover = true
        case "notes": withAnimation(.easeOut(duration: 0.15)) { notesOpen = true }
        case "pickdate": datePopover = false; setDay(offset: Int(parts.last ?? "") ?? 1)
        case "picktime": timePopover = false; setTime(Calendar.current.date(bySettingHour: Int(parts.last ?? "") ?? 15, minute: 0, second: 0, of: .now) ?? .now)
        case "picklist": listPopover = false; if let id = reminders.includedLists.last?.id { draft.listID = id }
        case "setnotes": notesOpen = true; draft.notes = parts.last ?? ""
        case "settitle": draft.title = parts.last ?? ""
        case "submit": commit()
        case "close": datePopover = false; timePopover = false; listPopover = false
        default: break
        }
    }

    private func chipLabel(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9.5))
            Text(text).lineLimit(1)
        }
        .chipStyle(active: active)
    }

    private func chip(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(icon: icon, text: text, active: true) }.buttonStyle(.plain)
    }

    private func applyParsed() {
        let result = parsed
        guard let due = result.due else { return }
        draft.title = result.title
        draft.due = due
        draft.hasTime = ArisTodoModel.hasTime(due)
    }

    private func commit() {
        if draft.due == nil { applyParsed() }
        guard !draft.title.trimmingCharacters(in: .whitespaces).isEmpty, !saving else { return }
        // Saved off the main actor: one save at a time (a second Return while it is on its way adds nothing twice).
        saving = true
        let item = item, draft = draft
        Task {
            let saved = if let item { await ArisTodoModel.shared.update(item, draft) } else { await ArisTodoModel.shared.add(draft) }
            saving = false
            if saved { close() }
        }
    }

    private func setDay(offset: Int) {
        let calendar = Calendar.current
        setDay(calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now)) ?? .now)
    }

    private func setDay(weekend: Bool) {
        let weekday = Calendar.current.component(.weekday, from: .now)
        setDay(offset: weekday == 1 ? 0 : 7 - weekday)
    }

    /// Picks the day, keeping the time of day when there is one.
    private func setDay(_ day: Date) {
        let calendar = Calendar.current
        if draft.hasTime, let current = draft.due {
            let time = calendar.dateComponents([.hour, .minute], from: current)
            draft.due = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day)
        } else {
            draft.due = calendar.startOfDay(for: day)
        }
    }

    private func setTime(_ time: Date) {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let day = draft.due ?? .now
        draft.due = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day)
        draft.hasTime = true
    }

    private static func format(_ date: Date, hasTime: Bool, dayless: Bool = false) -> String {
        let probe = ArisTodoItem(id: "", title: "", notes: nil, due: date, hasTime: hasTime, listID: "", listName: "", colorHex: "")
        if dayless { return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short) }
        return probe.dueLabel() ?? ""
    }
}

private extension View {
    func chipStyle(active: Bool) -> some View {
        self.font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(active ? Color.white.opacity(0.95) : .white.opacity(0.6))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(active ? 0.14 : 0.07)))
    }
}

/// A deadline coming up, under the closed notch: blue a day before, red three hours before. Click to open it.
struct ArisDueAlertView: View {
    let due: ArisDue
    let kind: ArisDueAlert
    let height: CGFloat
    let notchWidth: CGFloat

    private var tint: Color { kind == .hoursBefore ? Color(red: 1, green: 0.27, blue: 0.23) : ArisOrb.glow }

    var body: some View {
        VStack(spacing: 0) {
            ArisBandRow(height: height, notchWidth: notchWidth) {
                ArisCharacterView(size: 20, isAris: true).frame(width: 28, height: 28)
            } trailing: {
                Text(kind == .hoursBefore ? "3h" : "24h")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(tint)
            }
            card
        }
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
        .onTapGesture {
            ArisTodoModel.shared.open(due)
            ArisTodoModel.shared.dismissAlert()
        }
    }

    private var card: some View {
        HStack(spacing: 14) {
            ArisCharacterView(size: 44, isAris: true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 8, height: 8)
                    Text(left).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    Text(ArisTodoWords.alertTag(due, shortCourse: ArisTodoView.shortCourse(due.course))).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                }
                Text("\(due.title) · \(ArisTodoView.when(due.at).0)").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minWidth: 380, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22).fill(Color(white: 0.09))
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, tint.opacity(0.24)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 46).clipShape(RoundedRectangle(cornerRadius: 22))
                }
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.07)))
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var left: String {
        ArisTodoWords.left(minutes: max(1, Int(due.at.timeIntervalSinceNow / 60)))
    }
}
