//
//  ArisTurnView.swift
//  Aris
//
//  A turn: your words in a rounded card (radius 24, white 7%, 9% while live or hovered, two lines
//  then a fade; tap to see all), then the result slot (the answer as the owner's pick A document, ending in "자세히 보기 ›"
//  when it's taller than the reader limit, or the confirm card), then the
//  activity tags for what the AI did, kept as done under the answer. A follow-up's old prompt and answer leave over
//  the new turn. Stopping and closing live in the top band. A dictated message's countdown is the confirm card's countdown
//  mode, then its one-line end (ArisCountdownEndCard). Dictation, the morning brief and wake-word training keep their
//  own cards (ArisPanel).
//

import SwiftUI

struct ArisTurnView: View {
    @ObservedObject private var aris = ArisController.shared
    /// The answer's card, when it asked for one (pick B: the line, then the card).
    @ObservedObject private var widgets = ArisWidgetModel.shared
    /// "이 링크 스킬 추가해줘": its steps take the result slot (ArisSkillFlowCard).
    @ObservedObject private var skills = ArisSkillsModel.shared
    /// "…팀원 하나 만들어줘": the teammate made takes the result slot (ArisTeammateMadeCard).
    @ObservedObject private var team = ArisTeamModel.shared
    /// Why a right-⌥ press couldn't start a dictation just now (ArisDictationRefusalTag).
    @ObservedObject private var dictationState = ArisDictationState.shared
    /// When each running tag began, for its clock (ArisTagClock).
    @ObservedObject private var tagClock = ArisTagClock.shared
    /// What the turn really changed, on a line under the answer (ArisReceiptRow).
    @ObservedObject private var receipts = ArisReceiptModel.shared
    /// "오늘 정리해 줘": the day-end list sits under its sentence, as an answer's card does (ArisDayEndFold).
    @ObservedObject private var dayEnd = ArisDayEndModel.shared
    /// The button that fixes what the reply says went wrong (ArisFixButtons).
    @ObservedObject private var fixes = ArisFixModel.shared
    @State private var cardHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the rest of the open notch takes up, for the answer's height budget.
    var room = ArisAnswerRoom()

    @State private var promptHeight: CGFloat = 0
    /// The whole turn's height, for the chip preview's room (it never reaches past the turn, so never the notch's clip).
    @State private var turnHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    /// The answer's height on screen, for the copy that leaves when a follow-up starts. A class, so tracking it
    /// doesn't re-render the turn.
    @State private var shown = ArisShownAnswer()
    /// The previous prompt and answer while they leave.
    @State private var leaving: ArisLeavingResult?
    /// Counts the follow-ups this turn view has seen, so each one gets a fresh prompt card.
    @State private var promptTurn = 0
    /// The answer is taller than the reader limit: it ends in "자세히 보기 ›" (ArisAnswerReader).
    @State private var offersReader = false

    private var session: ArisSession { aris.session }

    /// The answer reveal: opacity over 180 ms (0.22, 0.61, 0.36, 1), once per answer; later text doesn't replay it.
    static let reveal = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.18)
    /// The result exit: to 0, 4 points up, 98.5% from the top, on the opening clock.
    static let exit: AnyTransition = .opacity.combined(with: .offset(y: -4)).combined(with: .scale(scale: 0.985, anchor: .top))

    var body: some View {
        if aris.training != nil || aris.dictation != nil || aris.briefTilesShown {
            ArisPanel(budget: room.answer(prompt: ArisPanel.tagRow))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let prompt {
                    ArisPromptPill(text: prompt.text, live: session.phase == .listening, placeholder: prompt.placeholder,
                                   thumbs: aris.shotThumbs, edit: editOffer(prompt), liveEdit: { editOffer(prompt) })
                        // A new card for each follow-up: collapsed again, its words fading in.
                        .id(promptTurn)
                        // Over the answer, so a chip's preview isn't covered by it.
                        .zIndex(1)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { promptHeight = $0 }
                }
                if let end = session.countdownEnd {
                    // A dictated message's countdown ended: sent or not, until the AI's answer takes the slot.
                    ArisCountdownEndCard(end: end)
                        .transition(.asymmetric(insertion: ArisCountdownEndCard.entry(reduceMotion: reduceMotion), removal: .identity))
                } else if let question = session.question {
                    // The confirm card takes the result slot under your words.
                    ArisConfirmCard(question: question, budget: room.answer(prompt: promptRoom), countdownStarted: aris.countdownStarted)
                        // In with a fade; out at once: a 300 ms fade-out left its rows drawn over the tags
                        // that take the slot.
                        .transition(.asymmetric(insertion: ArisConfirmCard.entry, removal: .identity))
                } else if let flow = skills.notchFlow, !flow.request.isEmpty, flow.request == session.heard {
                    ArisSkillFlowCard(flow: flow, budget: room.answer(prompt: promptRoom))
                } else if let made = team.made, made.heard == session.heard {
                    // In the result slot within the turn's room, as the confirm card (QA BUG-36): taller than the room, it scrolls.
                    ViewThatFits(in: .vertical) {
                        ArisTeammateMadeCard(made: made)
                        ScrollView(.vertical, showsIndicators: false) { ArisTeammateMadeCard(made: made) }
                    }
                    .frame(maxHeight: room.answer(prompt: promptRoom), alignment: .top)
                } else {
                    if showsAnswer, let skill = aris.skillInUse {
                        // The answer followed one of the user's skills (the brain read it).
                        ArisSkillTag(title: ArisUIWords.text("\(skill) 스킬 사용 중", "Using the \(skill) skill"))
                            .transition(.opacity.animation(Self.reveal))
                    }
                    if showsAnswer {
                        Group {
                            if session.settledCard { settledCard } else { answer }
                        }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shown.height = $0 }
                            .transition(.asymmetric(insertion: .opacity.animation(Self.reveal), removal: .identity))
                    }
                    if showsAnswer, let card = widgets.card(for: session.reply) {
                        ArisWidgetSlot(shown: card)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                            .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    }
                    if showsAnswer, let summary = dayEnd.shown(for: session), summary.hasList {
                        ArisDayEndFold(summary: summary, open: dayEnd.open, notPushed: dayEnd.notPushed, budget: dayEndBudget,
                                       toggle: { dayEnd.toggle() }, push: { dayEnd.push($0) }, show: { aris.dayEndShow(card: $0) })
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                    }
                    if showsFooter {
                        footer
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
                            .transition(.asymmetric(insertion: ArisActivityTag.entry, removal: .identity))
                    }
                }
                ArisReceiptRow()
                if let why = dictationState.refusal { ArisDictationRefusalTag(why: why) }
                ArisMuteNoticeTag()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .coordinateSpace(name: ArisShotPreviewLayer.space)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { turnHeight = $0 }
            .environment(\.arisTurnHeight, turnHeight)
            // Out of the layout: the surface retargets to the new turn at once while the old one fades over it.
            .overlay(alignment: .top) {
                if let leaving {
                    ArisLeavingResultView(result: leaving) { if self.leaving?.id == leaving.id { self.leaving = nil } }
                        .id(leaving.id)
                }
            }
            .animation(ArisGlass.opening, value: session.phase)
            .animation(ArisGlass.opening, value: dictationState.refusal)
            .onChange(of: session) { old, new in followUp(from: old, to: new) }
            .onChange(of: readerBudget) { updateReader() }
        }
    }

    /// The reply, with a card under it or without: the same text, height budget, fix button and "자세히 보기" either way
    /// (the upgrade VM run: an answer beside a card showed its raw marks, cut short, and never its fix button).
    private var answer: some View {
        VStack(alignment: .leading, spacing: 0) {
            replyText
            if let fix = fixOffer {
                // What went wrong has one thing he can do about it: that, under the sentence (and "자세히 보기" after it).
                HStack(spacing: ArisFixButtonRow.between) {
                    ArisFixButtons(offer: fix)
                    if reader { ArisOpenAnswerButton { openAnswer() } }
                }
                    .padding(.top, ArisFixButtonRow.gap)
                    .padding(.leading, replyInset)
                    .transition(ArisOpenAnswerButton.entry)
            } else if reader {
                ArisOpenAnswerButton { openAnswer() }
                    .padding(.top, ArisOpenAnswerButton.gap)
                    .padding(.leading, replyInset)
                    .transition(ArisOpenAnswerButton.entry)
            } else if brainTrouble {
                // The AI that should answer can't start here: the way to pick one that can, under the sentence.
                let words = ArisBrainTrouble.settingsButton(english: ArisUIWords.english)
                ArisFixPill(title: words + " ›", help: words) { openBrainSettings() }
                    .padding(.top, ArisFixButtonRow.gap)
                    .padding(.leading, replyInset)
                    .transition(ArisOpenAnswerButton.entry)
            }
        }
    }

    /// The reply as it is drawn: without the spoken line's tags an untrusted turn keeps (ArisSpeakable.withoutSayTags).
    private var shownReply: String { ArisSpeakable.withoutSayTags(session.reply) }

    /// The written answer's room: what the notch has left, never past 360; a longer answer scrolls inside.
    private var answerBudget: CGFloat { room.text(prompt: promptRoom, footer: footerRoom + moreRoom + cardRoom) }

    private var plainCardLine: Bool { widgets.isCardLine(session.reply) && ArisAnswerDocument.isPlainLine(shownReply) }

    /// The reply is drawn as one plain line: a card's line, or the day-end sentence above its list (ArisDayEndFold).
    private var plainLine: Bool { plainCardLine || (dayEnd.isLine(session.reply) && ArisAnswerDocument.isPlainLine(shownReply)) }

    /// The day-end list's room under its sentence and its 목록 row: the opened tiles scroll within it.
    private var dayEndBudget: CGFloat {
        max(ArisAnswerBudget.minimum, room.answer(prompt: promptRoom, footer: footerRoom) - ArisDayEndFold.reserved)
    }

    /// Where the row under the reply starts: on the reply's own text line (the card's line is set 4 in, an answer 14).
    private var replyInset: CGFloat { plainLine ? ArisWidgetLine.inset : ArisAnswerText.padding.leading }

    /// One plain line above a card stays the card's own line (pick B); every other answer is the document, so its
    /// headings, tables and lists are drawn and never shown as raw marks. Both scroll within the same budget.
    @ViewBuilder private var replyText: some View {
        if plainLine {
            ArisFadingScroll(budget: answerBudget) {
                ArisWidgetLine(text: shownReply)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        shown.content = height
                        updateReader()
                    }
            }
        } else {
            ArisAnswerText(text: shownReply, budget: answerBudget) { height in
                shown.content = height
                updateReader()
            }
        }
    }

    /// What is up is the agent's "this AI can't start here" (fresh install F2); it stays offered while the sentence stays.
    private var brainTrouble: Bool { showsAnswer && ArisBrainTrouble.isCannotStart(session.reply) }

    /// The fix for what the reply says, while the reply is up, beside a card or not: never over a card's words left
    /// up, and never beside the permission card (it has the same button of its own).
    private var fixOffer: ArisFixOffer? {
        guard showsAnswer else { return nil }
        var permissionCard = false
        if case .permission? = widgets.card(for: session.reply)?.content { permissionCard = true }
        return ArisAnswerDocument.showsFix(settledCard: session.settledCard, permissionCard: permissionCard) ? fixes.offer(for: session) : nil
    }

    /// Settings › AI 서비스, on 기본으로 답하는 AI.
    private func openBrainSettings() {
        ArisSettingsNav.shared.go(.ai, anchor: ArisSettingsCaption.brainAnchor)
        ArisStepAside.showSettings()
    }

    /// A card's words left up after the user answered it: two lines and "…", a tap for the rest (ArisSettledCardText).
    private var settledCard: some View {
        ArisSettledCardText(text: session.reply, budget: room.answer(prompt: promptRoom, footer: footerRoom))
    }

    /// The row under the answer and its gap, when one shows: the fix's pill, or "자세히 보기 ›".
    private var moreRoom: CGFloat {
        if fixOffer != nil || (!reader && brainTrouble) { return ArisFixButtonRow.height + ArisFixButtonRow.gap }
        return reader ? ArisOpenAnswerButton.height + ArisOpenAnswerButton.gap : 0
    }

    /// The card and its 12-point gap, when it shows.
    private var cardRoom: CGFloat {
        widgets.card(for: session.reply) == nil && dayEnd.shown(for: session)?.hasList != true ? 0 : cardHeight + 12
    }

    private var footer: ArisActivityFooter {
        ArisActivityFooter(tags: session.tags, times: tagClock.times.began,
                           stop: ArisTagStop(help: ArisStopLine.help(english: ArisUIWords.english)) { aris.stopFromTag() })
    }

    /// "자세히 보기 ›" while the answer is up and taller than the reader limit.
    private var reader: Bool { offersReader && showsAnswer && !session.settledCard }

    private var showsFooter: Bool { !session.tags.isEmpty }

    /// The reader limit's budget, without the footer or the "자세히 보기 ›" line; a card under the answer takes its room.
    private var readerBudget: CGFloat { room.answer(prompt: promptRoom, footer: cardRoom) }

    private func updateReader() {
        let next = ArisAnswerReader.offers(content: shown.content, budget: readerBudget)
        if next != offersReader { offersReader = next }
    }

    private func openAnswer() {
        ArisBoard.shared.open(answer: shownReply, question: session.heard)
        // The reader opens under the notch: the notch steps aside for it (ArisStepAside).
        ArisStepAside.openedElsewhere()
    }

    private var showsAnswer: Bool { session.phase != .listening && session.phase != .thinking && !session.reply.isEmpty }

    /// The prompt card's height, when it shows.
    private var promptRoom: CGFloat { prompt == nil ? 0 : promptHeight }

    /// The footer and its 12-point gap, when it shows.
    private var footerRoom: CGFloat { (showsFooter ? footerHeight + 12 : 0) + receipts.room }

    /// A new turn over an answer still on screen: the old prompt and answer stay as a copy outside the layout, which
    /// leaves on its own once it's on screen (ArisLeavingResultView) while the new turn is already in place.
    private func followUp(from old: ArisSession, to new: ArisSession) {
        guard !old.reply.isEmpty, old.question == nil, new.phase == .listening, new.reply.isEmpty else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            leaving = ArisLeavingResult(heard: old.heard, reply: ArisSpeakable.withoutSayTags(old.reply), tags: old.tags, answerHeight: shown.height)
            promptTurn += 1
            // The new answer measures itself before it can offer "Open answer".
            shown.content = 0
            offersReader = false
        }
    }

    /// Whether the sent words can be edited now (ArisPromptEdit): never while Aris listens or a card waits, never on
    /// words that went with files or circled shots; and whether the card must say the first request already acted.
    private func editOffer(_ prompt: (text: String, placeholder: Bool)) -> ArisPromptEdit.Offer {
        ArisPromptEdit.offer(.init(
            phase: session.phase, words: prompt.text, placeholder: prompt.placeholder,
            cardWaiting: session.question != nil || session.countdownEnd != nil || skills.notchFlow != nil || team.made != nil,
            carriesFiles: ArisPendingFiles.carriesFiles(session.heard),
            carriesShots: !ArisGestureMarkers.badges(in: prompt.text).isEmpty,
            didSomething: session.steps.contains { $0.done } || receipts.desk.line != nil))
    }

    /// Your words; while you're still talking with nothing heard yet, a hint in their place.
    private var prompt: (text: String, placeholder: Bool)? {
        // The user's words and their files' names, never the note that carries them to the brain (QA VM: the bubble showed
        // "(첨부한 파일: /Users/admin/Desktop/qa-drop.txt —").
        if !session.heard.isEmpty { return (ArisPendingFiles.shown(session.heard), false) }
        guard session.phase == .listening else { return nil }
        return (aris.followingUp ? ArisUIWords.text("더 필요한 거 있어요?", "Anything else?") : ArisUIWords.text("듣고 있어요…", "Listening…"), true)
    }
}

/// The last answer heights seen: on screen, and its whole content. A class, so writing them doesn't invalidate the turn.
private final class ArisShownAnswer {
    var height: CGFloat = 0
    var content: CGFloat = 0
}

/// The turn a follow-up replaces, as it was on screen.
struct ArisLeavingResult: Equatable {
    let id = UUID()
    let heard: String
    let reply: String
    let tags: [ArisStep]
    let answerHeight: CGFloat
}

/// The leaving turn: its prompt card, its answer cut to the height it had (from the top) and its tags, all still.
/// Once it appears it leaves: to 0, 4 points up and 98.5% from the top on the
/// opening clock (280 ms, 0.2 0.8 0.2 1); then `gone` takes it away.
private struct ArisLeavingResultView: View {
    let result: ArisLeavingResult
    let gone: () -> Void

    @State private var leaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !result.heard.isEmpty { ArisPromptPill(text: result.heard, reveals: false) }
            ArisAnswerDocumentView(text: result.reply, reveals: false)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: max(0, result.answerHeight - ArisAnswerText.padding.top - ArisAnswerText.padding.bottom), alignment: .top)
                .clipped()
                .padding(ArisAnswerText.padding)
            if !result.tags.isEmpty { ArisActivityFooter(tags: result.tags, still: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
        .opacity(leaving ? 0 : 1)
        .scaleEffect(leaving ? 0.985 : 1, anchor: .top)
        .offset(y: leaving ? -4 : 0)
        .onAppear {
            withAnimation(ArisGlass.opening) { leaving = true } completion: { gone() }
        }
    }
}

/// Your words, in the sent-prompt card: 15 pt on a 22-point line, 16 inset, radius 24, white 7% (9% while
/// live or hovered). Over two lines it collapses to two lines and an 18-point peek of the third under a 34-point fade
/// (ArisPromptCollapse); a tap shows all of it, however long, and another collapses it again. The words fade in once
/// when the card appears (180 ms, 0.22 0.61 0.36 1).
struct ArisPromptPill: View {
    let text: String
    var live = false
    var placeholder = false
    /// Fades the words in on appearing; the follow-up's leaving copy is already on screen.
    var reveals = true
    /// The circled shots' thumbnails for the `[img N]` chips (P1.9).
    var thumbs: [Int: NSImage] = [:]
    /// Whether these words can be edited and sent again (ArisPromptEdit); the leaving copy never can.
    var edit: ArisPromptEdit.Offer = .no(.noWords)
    /// Drawn as if the pointer were on it, or as if it were being edited (the off-screen render only).
    var previewHover = false
    var previewEditing = false
    /// The same offer, asked again at the moment Return is pressed.
    var liveEdit: () -> ArisPromptEdit.Offer = { .no(.noWords) }

    /// The words being edited; nil while the card only shows them.
    @State private var draft: String?
    @State private var hovering = false
    @State private var expanded = false
    /// For the tap only; the cut itself is decided in layout (ArisPromptClamp), a frame before this is measured.
    @State private var lines = 1
    @State private var revealed = false
    @State private var hoveredShot: Int?
    /// Re-draws this view when the hidden look changes (ArisSiriLookGate).
    @ObservedObject private var siriLook = ArisSiriLookGate.shared

    var body: some View {
        VStack(alignment: .leading, spacing: ArisPromptDoneNote.gap) {
            // The siri look: your words as Siri's bubble (ArisSiriLookBubble) while they are only shown; a request
            // being edited, and words that carry circled shots, are the card below, editor, chips and all.
            if siriBubble {
                bubble
            } else {
                card
            }
            // An edit never resends over something already done without saying so (ArisPromptEdit).
            if draft != nil, edit == .editable(saysDone: true) { ArisPromptDoneNote() }
        }
        .onChange(of: draft != nil) { _, editing in ArisPromptEditing.shared.set(editing) }
        .onChange(of: edit.isEditable) { _, can in if !can { endEdit() } }
        .onDisappear { if draft != nil { ArisPromptEditing.shared.set(false) } }
    }

    /// Return in the edited card: the words go as a new typed request, by the typed path (the same gate and
    /// cards as any request); an emptied card sends nothing.
    private func sendEdit() {
        let aris = ArisController.shared
        // What the turn is now, not as the card was last drawn: with a card up, Return answers nothing (review 7, L3).
        let sent = ArisPromptEdit.send(draft: draft ?? "", phase: aris.session.phase, offer: liveEdit())
        endEdit()
        guard case .send(let words, let stopsFirst) = sent else { return }
        if stopsFirst { aris.cancel() }
        // The words alone: files waiting for the next request keep waiting, their chips back with the composer (L2).
        ArisPromptEditing.shared.sending(words)
        aris.submitTyped(words)
    }

    private func endEdit() {
        guard draft != nil else { return }
        withAnimation(ArisGlass.resize) { draft = nil }
    }

    /// The siri look draws these words as the bubble: not while they are edited (the card has the editor), and not
    /// words with circled shots (the card draws their chips).
    private var siriBubble: Bool {
        ArisSiriLookNow.on && draft == nil && !previewEditing && (placeholder || ArisGestureMarkers.badges(in: text).isEmpty)
    }

    /// Siri's bubble with the card's own pencil beside it while the pointer is on the row; the pencil, or a tap
    /// where the card's tap would edit, hands the words to the card's editor.
    private var bubble: some View {
        ArisSiriLookBubble(text: text, quiet: placeholder) {
            if hovering || previewHover, edit.isEditable {
                ArisPromptPencil { draft = text }.transition(.opacity)
            }
        }
        .opacity(revealed || !reveals ? 1 : 0)
        .onTapGesture {
            if case .edits = ArisPromptEdit.tap(lines: 1, offer: edit) { draft = text }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onAppear {
            guard reveals, !revealed else { return }
            withAnimation(ArisTurnView.reveal) { revealed = true }
        }
    }

    @ViewBuilder private var shown: some View {
        if draft != nil {
            // A field on its way out still writes its text back once: that never reopens the editor (ArisPromptEdit.draft).
            ArisPromptEditor(text: Binding(get: { draft ?? "" }, set: { draft = ArisPromptEdit.draft(draft, typed: $0) }),
                             send: sendEdit, cancel: endEdit, preview: previewEditing)
        } else {
            ArisPromptClamp(expanded: expanded) {
                words.padding(.top, ArisPromptCard.halfLeading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lines = ArisPromptCollapse.lines(measured: $0) }
            }
            .clipped()
            .mask {
                // The fade from the cut's own size, in the same pass as the cut.
                GeometryReader { geometry in
                    let fades = ArisPromptCollapse.fades(height: geometry.size.height, expanded: expanded)
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: fades ? ArisPromptCollapse.fadeStart : 1),
                        .init(color: fades ? .clear : .black, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
            }
            .opacity(revealed || !reveals ? 1 : 0)
        }
    }

    private var card: some View {
        shown
            .padding(ArisPromptCollapse.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(live || hovering || previewHover || draft != nil ? ArisGlass.promptFillActive : ArisGlass.promptFill))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            // The pencil, while the pointer is on a card that can be edited.
            .overlay(alignment: .topTrailing) {
                if hovering || previewHover, draft == nil, edit.isEditable {
                    ArisPromptPencil { draft = text }
                        .padding(.top, ArisPromptEdit.pencilTop)
                        .padding(.trailing, ArisPromptEdit.pencilTrailing)
                        .transition(.opacity)
                }
            }
            .onTapGesture {
                guard draft == nil else { return }
                switch ArisPromptEdit.tap(lines: lines, offer: edit) {
                // The card's new height rides the surface's opening clock.
                case .toggles: withAnimation(ArisGlass.opening) { expanded.toggle() }
                case .edits: draft = text
                case .nothing: break
                }
            }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.14), value: hovering)
            // The hovered chip's preview, outside the prompt's clip.
            .overlayPreferenceValue(ArisShotAnchors.self) { anchors in
                ArisShotPreviewLayer(anchors: anchors, hovered: hoveredShot, thumbs: thumbs)
            }
            .onAppear {
                if previewEditing { draft = text }
                guard reveals, !revealed else { return }
                withAnimation(ArisTurnView.reveal) { revealed = true }
            }
    }

    @ViewBuilder private var words: some View {
        if !placeholder, !ArisGestureMarkers.badges(in: text).isEmpty {
            ArisMarkedPrompt(text: text, thumbs: thumbs, hovered: $hoveredShot)
        } else {
            Text(text)
                .font(.system(size: 15))
                .lineSpacing(ArisPromptCollapse.lineSpacing)
                .foregroundStyle(.white.opacity(placeholder ? 0.45 : 0.9))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Your words at their full height, cut to the collapsed height in the same layout pass when they run past two lines
/// (ArisPromptCollapse.clamped), so a long prompt never shows whole for a frame before it collapses.
private struct ArisPromptClamp: Layout {
    let expanded: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let words = subviews.first else { return .zero }
        let full = words.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let cut = ArisPromptCollapse.clamped(full: full.height, expanded: expanded)
        // Whole, the last line gets the 2 points under it that every 22-point line has (the first has them above).
        return CGSize(width: full.width, height: cut < full.height ? cut : full.height + ArisPromptCard.halfLeading)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

/// Aris's answer: the owner's pick A document (ArisAnswerDocumentView), padding 4 / 14 / 8, in one scroller from the
/// first token that grows to `budget` and then scrolls (ArisFadingScroll).
struct ArisAnswerText: View {
    let text: String
    var budget: CGFloat = ArisAnswerBudget.widgetMax
    /// The whole answer's height with its padding, as it changes.
    var contentHeight: (CGFloat) -> Void = { _ in }

    static let padding = EdgeInsets(top: 4, leading: 14, bottom: 8, trailing: 14)

    var body: some View {
        ArisFadingScroll(budget: budget) {
            ArisAnswerDocumentView(text: text)
                .equatable()
                .padding(Self.padding)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight($0) }
        }
    }
}
