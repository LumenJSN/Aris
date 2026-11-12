//
//  main.swift
//  aris-agent
//
//  Aris's brain runner, started by launchd as a login agent. It runs claude, codex or agy the
//  way a terminal would (with access to their logins), which the sandboxed
//  notch app can't. The app talks to it over loopback HTTP with the same token
//  as the Claude hooks:
//
//    POST /ask   {"text": "...", "context": "...", "tier": "quick"|"work"|"critical", "brain": "claude"|"codex"|"antigravity",
//                 "task": true|false, "title": "...", "browser": true|false, "teammate"?: "<id>"}
//                (tier: how much the request asks, which picks the model; brain: which AI, Claude by default;
//                 task: long work in the background, in its own process; a long answer is saved as a file
//                 named after `title` and opened on screen; browser: several steps on websites, for Aside; teammate: the
//                 stored teammate whose task it is, which the activity log names, with its id)
//                ->  JSON lines as the answer comes (ArisAgentReply): {"status": "..."}, {"delta": "..."}, …,
//                    {"confirm": {"id", "title", "detail"}} when an action waits for the user,
//                    then {"answer": "..."} or {"error": "..."}, and the connection closes
//    POST /confirm {"id": "...", "allow": true|false, "pid", "started", "detail", "full"?, "edits"?, "shown"?}   ->  {} (404 when
//                nothing waits for that id; 403 unless the caller is the Aris app itself (ArisPeer) and, for a yes, the details are
//                the card the agent made; "edits": {"field": "value"} the user changed on a card with "fields" (ArisEditableAction),
//                "shown": the card's fields as finally shown, which must be exactly those changes; the agent checks and judges
//                the changed action again, then runs it itself, refuses it, or asks with a fresh card)
//                (a confirm may carry "proposal": true, "앞으로 이건 그냥 할까?": a yes makes it a standing permission)
//    POST /ask with "task": true also takes "job" (the app's UUID for it), "pid" and "started" (the app's process
//                and its start time): a task is cancelled by POST /cancel {"job": "..."}  ->  {} (always recorded:
//                a job whose cancel came first is refused when it asks), or when its connection closes and that
//                process is gone; a dropped stream while the same app runs leaves it going
//    POST /permissions {"op": "list"}  ->  {"permissions": [{"kind", "app", "target"}]}   (standing permissions)
//                {"op": "revoke", "kind", "app", "target"}  ->  {} (the settings list's 취소)
//                {"op": "waiting", "id": "..."}  ->  {"waiting": bool}   (a parked card that expired never shows)
//    Main Aris's judgement of a background job's action (ArisJudge) is internal: the runner calls it, never HTTP.
//    POST /open  {"path": "..."}   ->  {} (404 unless it's a .md right in ~/Documents/Aris): opens it in its default app
//    POST /result {"op": "read"|"note", "path", "pid", "started"}  ->  read: {"text", "modified"}; note: {} or {"error"}
//                 (404 unless it's a saved task result; the app's reader reads results here, the app can't)
//    POST /warm  {"brain": "..."}   ->  {}   (the user started talking: start that AI's quick and work models)
//    POST /stop                   ->  {}
//    POST /log   {"turn": {...}}  ->  {}   (one turn's numbers, ArisTurnStats; kept in turns.jsonl)
//    POST /todos {"op": "list"|"hide"|"finish", "text"?, "id"?}  ->  {"todos": [...], "due": [...]}
//                (the 할 일 tab's Canvas deadlines still to hand in, and the old to-do file the app imports once;
//                 your to-dos are in Reminders, in the app: ArisTodoStore)
//    POST /brief {}  ->  the morning brief's facts (aris-tools brief: weather, Canvas due, unread announcements)
//    POST /weather {place?}  ->  the answer card's weather (aris-tools weather [place] --json: now, high and low, next hours)
//    POST /stock {symbol}  ->  the stock card (aris-tools stock <symbol> --json: price, change, high, low, time, points)
//    POST /currency {ask}  ->  the currency card (aris-tools currency <amount> <FROM> <TO> --json: rate, time, the day's points)
//    POST /maps {place, from?}  ->  the map card (aris-tools maps search|directions … --json: place, address, ETAs, route)
//    POST /look  {}  ->  {"context": "...", "selected": bool, "editable": bool}: what "이거" points at (ArisLook)
//    POST /ask also takes "screen": that context; it then goes to Codex only, marked as outside text
//    POST /ask also takes "images": [{"kind": "cursor"|"gesture"|"drawing", "mime": "image/png"|"image/jpeg", "data": base64,
//                "badge"?: 1…8, "app"?, "title"?}] and "focus": "screen"|"panel" (ArisTurnImage; the body may be up to 24 MiB).
//                Only from the Aris app itself (ArisPeer; else 403), never on a task; every image is checked (else 400, nothing
//                used). Codex takes them; Claude's and Antigravity's turns go to the sealed Claude (the sealed aris-tools list
//                only, no web; R2 = a). Images stay in memory: never written, never logged. The turn and every later turn of
//                its conversation (until "fresh") are screenSeen (R1 = B: only actions the user's own words cover go as judged)
//                and restricted, and stay on the sealed or gated brain; such
//                a turn's stream starts with {"untrusted": true, "screen": bool, "dispatch": bool}: a screen turn may dispatch
//                (every job untrusted, on Codex with web search off; a Claude Code launch always shows the user's card), and after
//                outside text the answer's jobs block becomes a notice; the
//                app sends "screenConversation": true on every later /ask of a conversation that saw it (resumes too), which
//                only ever adds to the agent's own flag. The 24 MiB
//                body limit applies only when the request head carries the token.
//    POST /paste {}  ->  {} or {"error"}: presses ⌘V for what the app just put on the clipboard (refused in password fields)
//    POST /insert {"text": "...", "learn"?: bool}  ->  {"confirmed": bool} or {"error": "..."} (500): dictated words
//                typed where the cursor is (lazy paste, clipboard put back; never Enter, never into a password field;
//                `learn`: watch the field for a fixed word, ArisEditWatch). /caret, /polish, /dictionary: ArisDictationRoutes
//    POST /activity {"today": bool}  ->  [{"id", "date", "job", "worker", "summary", "undoable", "undone", "asks"}]  (what Aris did,
//                oldest first; ArisActivity, from `aris-tools activity --json`)
//    POST /undo  {"id"?: "<uuid>", "confirmed"?: bool, "pid", "started", "summary"?}  ->  {"summary"} (200), {"confirm", "id",
//                "summary", "kind"} (409: it would delete an event Aris made or bring a removed schedule back; ask the user
//                and repeat with confirmed and the 409's summary as shown), 403 (not the Aris app itself (ArisPeer), or a
//                yes that doesn't echo a live 409 card for that id, once: ArisPendingUndos), or {"error"} (500). No id: the
//                latest undoable thing from the last day. The user's own request, so no AI gate; aris-tools checks every path.
//    POST /inbox {"op": "fetch"}  ->  {"items": [{"id", "date", "kind", "title", "text", "file"?, "confirm"?}]}  (what scheduled
//                jobs left for the user, oldest first: "result", "failure", "note", or "confirm" with a parked question's card,
//                which the app asks when the user is there; ArisScheduler. The agent nudges com.lumenjsn.aris.inbox.)
//                {"op": "ack", "ids": ["<uuid>", …]}  ->  {"removed": n}  (delivered: they leave the inbox)
//    POST /teammate {"job", "teammate": "claude-code", "prompt", "cwd", "turn"?}  ->  JSON lines: a Claude Code teammate opened
//                in a terminal window (ArisTeammateDesk; "turn" is the id an /ask answer carried as {"turn": "..."})
//    POST /teammates {"op": "list"|"save", "teammates"?: [{"id", "name", "role", "look", "brain"}], "pid", "started"}  ->
//                {"teammates": [...]} (200), {"error": "<what>"} (400, nothing written) or 403 unless the caller is the Aris
//                app itself (ArisPeer): the settings 팀원 page (ArisTeammateEdit checks every entry)
//    POST /data {"op": "summary"|"export"|"diagnostics"|"wipe"|"dropKeyFile"|"uninstall", …, "pid", "started"}  ->  see
//                ArisDataRoute: settings 정보 › 데이터 (and API 키) for what is in ~/.config/aris; 403 unless the caller is the
//                Aris app itself (ArisPeer); wipe and uninstall need the word the user typed; every op and refusal is audited
//    POST /mcp {"op", …, "pid", "started"}  ->  settings 연결된 서비스 (the Aris app itself only): ArisMCPRoutes
//    POST /mcp-tool {"op": "list"|"call", "turn", …}  ->  {"status", "output"}: aris-tools mcp, from inside a brain's turn
//    POST /message-tool {"turn", "to", "text"}  ->  {"status", "output"}: aris-tools message from the open Claude (ArisMessageGate)
//    POST /action-tool {"turn", "words"}  ->  {"status", "output"}: a Claude's write, send or thing opened, handed over by aris-tools
//                (ArisHandOff), judged as Codex's same command and asked on the user's card when that says to (ArisActionGate)
//    POST /routine-tool {"turn", "words"}  ->  {"status", "output"}: aris-tools routine (the user's routines; ArisRoutineRoutes)
//    POST /routine-step {"id", "local", "ok"?, "reply"?}  ->  {}: the app's answer for a routine's step offered to it (ArisRoutineHandBack)
//    POST /aside-tool {"turn", "brief"}  ->  {"status", "output"}: aris-tools aside (website work for Aside), the same checks
//    POST /desktop-tool {"turn", "words", "text"?}  ->  {"status", "output"}: aris-tools desktop (computer use), the same checks
//                (its runner's ARIS_MCP_TURN and its process tree; ArisMCPCaller), through the one gate (ArisMCPPolicy)
//    POST /arrange {"app": "Microsoft Excel", "count": 4}  ->  {} or {"error": "..."} (500): that many new
//                windows of the app in a grid, from words the app understood itself ("엑셀 4개 켜서 4등분")
//

import Foundation
import Network

// Its own id and name in what LaunchServices lists, before anything touches AppKit: never a second "Aris" that a quit
// sent to the app's id could reach (ArisHelperListing).
ArisHelperListing.settle()

// A write to a child that has gone is an error its writer catches, never the signal that ends the whole agent. A
// handler, never SIG_IGN, so children start with the default (audit sigpipe-1).
signal(SIGPIPE) { _ in }

// Who started this program (ArisOrigin). Inside Aris.app macOS charges the app for whatever this program does, with
// everything the user granted Aris, whoever started it: so it serves only as Aris's own launchd job, and its helper
// modes below run only when that job stands behind them (or macOS charges the program that started them instead).
// launchd's record is asked a few times: it names a job's process a moment after the process starts.
let helperMode = CommandLine.arguments.dropFirst().first == "api-brain" || CommandLine.arguments.contains("--usage-report")
var origin = ArisOrigin.facts(serving: !helperMode)
// Looked at again only while launchd has not yet named its job's process; a record that names anything else is final.
for _ in 0..<10 where !helperMode && !ArisOrigin.decision(origin, serving: true).allowed && ArisOrigin.mayYetBeJob(origin) {
    usleep(200_000)
    origin = ArisOrigin.facts(serving: true)
}
guard ArisOrigin.allows(origin, serving: !helperMode) else {
    FileHandle.standardError.write(Data("\(ArisOrigin.agentRefusedLine) (\(ArisOrigin.describe(origin)))\n".utf8))
    exit(1)
}
if helperMode { ArisOrigin.armRecheck() }
ArisOrigin.settleHome()

// `aris-agent api-brain --profile <id>`: an API brain's helper process (ArisAPIHelper), started by its runner. Nothing
// else of the agent runs in it.
if CommandLine.arguments.dropFirst().first == "api-brain" {
    ArisAPIHelper.runProcess()
}

// `aris-agent --usage-report`: the usage report as JSON on stdout (every source, one whole cost pass), then exit.
if CommandLine.arguments.contains("--usage-report") {
    ArisUsageFetch.printReport()
    exit(0)
}
// From here on this process is Aris's helper. It answers its own tools' question "did you start me?" before it
// starts anything (ArisVouchService): a tool that macOS charges to Aris runs only on the helper's own yes.
ArisVouchService.start()
// The commit this agent was built from: a line in agent.log and a file the app compares with its own (ArisBuildInfo).
ArisBuildInfo.recordRunningAgent(in: ArisAgentRunner.directory)
ArisUsageScanner.shared.kick()

// The shared secret, made here when none exists (the agent owns ~/.config/aris; the app and the hooks read the same file).
if ClaudeHookToken.createIfMissing() { FileHandle.standardError.write(Data("aris-agent: made a new token file\n".utf8)) }
// launchd keeps agent.log open as this process's stderr: over 20 MB it's copied to a dated file and emptied in place,
// and our own write offset moves to the new end (launchd's fd may not be O_APPEND).
if ArisLogRotation.rotateOpenLog(ArisAgentRunner.directory.appendingPathComponent("agent.log"), limit: 20 * 1_024 * 1_024) {
    lseek(STDERR_FILENO, 0, SEEK_END)
}

// With the app moved to the Trash or deleted, launchd leaves this process running: it stops by itself then.
ArisAppBundle.watchGone()
// The path the AIs call aris-tools by stays a link to this app's own program (ArisToolsLink): looked at now and
// whenever something changes in Aris's folder.
ArisToolsLink.ensure()
ArisToolsLink.startWatching()

let port: NWEndpoint.Port = 23351
// Long-term memory: memory.md comes into memory.sqlite once, and days that ended get their summaries.
ArisMemoryCurator.live.start()
// The work memory (what Aris did, ArisWorkDesk): its cache fills and old episodes are compacted.
ArisWorkDesk.live.refresh()
let queue = DispatchQueue(label: "com.lumenjsn.aris.agent.server")
/// The user's own words in one request. A spoken one is a sentence or two, but a pasted one can be a letter or a page
/// (second upgrade run, bug 3: a 3,093-character paste was refused as "Aris's helper didn't take the request."). The
/// limit only bounds what every gate, judge and prompt reads of their words; the brains take far more (20,000 characters
/// is about 6,000 tokens). Memory learns only from requests of up to `maxLearned` (a pasted page is no fact about him).
/// The app says a longer one is too long, with this number (ArisAgentCopy.requestLimit).
let maxText = 20_000
let maxLearned = 2_000
/// What may ride along after the user's words: the files note and the attached files' text (the app's ArisAttachmentText caps
/// it at 24k characters, plus their names and the note). The user's own words stay within `maxText` (QA on the VM: with a file's
/// text the whole /ask was refused, so the API brain never saw it and went looking for the file).
let maxAttachedText = 30_000
let maxContext = 6_000
/// What ArisLook found on screen ("이거"): a selection, a page or a window's text.
let maxScreen = 9_000
/// Which AIs are out of quota right now (only touched on `queue`).
var brainHealth = ArisBrainHealth()
/// The undo cards /undo gave out with a 409, which a yes must echo (only touched on `queue`).
var pendingUndos = ArisPendingUndos()
/// Whether this conversation has seen the screen: then every turn is screenSeen, restricted and sealed until a fresh
/// start (only touched on `queue`).
var screenConversation = ArisScreenConversation()
/// Whether this conversation has taken in outside text on any brain: then it dispatches nothing until a fresh start
/// (only touched on `queue`).
var outsideConversation = ArisOutsideConversation()
/// Whether Aris read the user's messages, mail or notes for agy in this conversation (ArisAgyRelay): its later agy turns
/// go to the sealed agy, which has no tools. Cleared by a fresh conversation.
var agyPrivateConversation = ArisOutsideConversation()
/// The cards whose answers are in the audit ledger (ArisCardLedger); read and written on the server queue only.
var cardLedger = ArisCardLedger()

func respond(_ connection: NWConnection, _ status: String, _ body: Data) {
    let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
    connection.send(content: Data(head.utf8) + body, contentContext: .finalMessage, isComplete: true,
                    completion: .contentProcessed { _ in connection.cancel() })
}

/// Asks `requested`, or, while it is out of quota or isn't on this Mac at all, the first other brain that can take
/// this turn (ArisTurnFallback: a turn that saw the screen or carries outside text only where such a turn always
/// lands). If the AI runs out before doing anything, the same question goes once to another one, and the notch says so.
/// `screenText`: "이거" text from the screen came with the turn (it goes to a gated brain only).
/// `vouches`: the user's own turn from the Aris app itself (no screen, no model-written text, nothing others wrote in its
/// context or memory; ArisTeammateGate.vouches): when its answer dispatches a Claude Code job and no outside text came
/// into the conversation, the app gets a turn id that lets that job launch without asking.
/// `images` and `sealed`: a turn carrying screen images (ArisImageRouting). `untrusted`: outside text came with the turn;
/// `screenSeen`: its conversation saw the screen (R1 = B). Either way it's restricted: it never vouches, and another
/// brain takes it only as its own restricted turn; after outside text its answer hands out no jobs (ArisImageRouting.answerPlan).
func ask(_ requested: ArisBrain, tier: ArisTier, prompt: String, request: String, learnAs: String?, untrusted: Bool = false,
         screenSeen: Bool = false, outsideConversation conversationOutside: Bool = false, vouches: Bool = false, handsFree: Bool = false,
         images: [ArisTurnImage] = [], sealed: Bool = false, learnFrom: String? = nil, relayRound: Int = 0, shownOnly: Bool = false,
         ownData: Bool = false, screenText: Bool = false, on connection: NWConnection, retried: Bool = false) {
    // The app dropped the stream (a cancel, a timeout) before this turn started: nothing of it starts (audit
    // orphan-turn-11: a relay round or a shortcut's fall-through started a turn nobody was waiting for, and the next
    // question met "still answering the last one").
    guard ArisAskAdmission.proceeds(state: connection.state, cancelled: false) else { return }
    let restricted = untrusted || screenSeen || handsFree
    // What another brain needs to know to take this turn: a screen or outside-text turn lands only on its own route for
    // such a turn (the gated brains, the sealed Claude, the sealed agy), never on an open brain.
    let fallbackTurn = ArisTurnFallback.Turn(images: images, screenText: screenText, screenConversation: screenSeen, handsFree: handsFree,
                                             outside: untrusted || conversationOutside || agyPrivateConversation.seen)
    let another = { (failing: ArisBrain) in
        ArisTurnFallback.route(insteadOf: failing, turn: fallbackTurn, apiVision: ArisAPIActive.profile()?.takesImages == true,
                               usable: ArisSealedOneShot.available, available: { brainHealth.isAvailable($0) })
    }
    // Out of quota, or not on this Mac: another brain takes it from the start (a relay round stays with agy).
    let missing = !ArisSealedOneShot.available(requested)
    let instead = !retried && relayRound == 0 && (missing || !brainHealth.isAvailable(requested)) ? another(requested) : nil
    let brain = instead?.brain ?? requested
    let images = instead.map { $0.sendsImages ? images : [] } ?? images
    let sealed = instead?.sealed ?? sealed
    if instead != nil { stream(.status(ArisTurnFallback.status(from: requested, to: brain, missing: missing)), on: connection) }
    ArisWhyDesk.shared.asking(brain, instead: requested, on: ObjectIdentifier(connection))
    // Claude, agy and the API brain each have a sealed process of their own (agy's: no tools at all, ArisAgyRelay).
    let sealable = brain == .claude || brain == .antigravity || brain == .api
    let runner = ArisAgentRunner.shared(brain: brain, model: brain.model(tier: tier), sealed: sealed && sealable,
                                        handsFree: handsFree && sealed && sealable)
    // What this turn's handed-off calls do (a Claude's writes, judged by the agent: ArisActionGate) is noted from here.
    ArisHandOffLedger.shared.startTurn(runner, underWay: runner.mcpTurn)
    // Called on the runner's queue, where its taint is read.
    // The app is told once when outside text came in during this turn.
    let toldOutside = ArisCancelFlag()
    let reply = { (reply: ArisAgentReply) in
        // Outside text came in during this turn: the conversation keeps it (and the app, for a resume). Told before the
        // answer's next words, so the app reads a <say> line after it as plain text.
        let tellOutside = {
            guard runner.currentTaint == .outsideText, !conversationOutside, !toldOutside.isSet else { return }
            toldOutside.set()
            queue.async {
                outsideConversation.mark()
                stream(.untrusted(screen: screenSeen, dispatch: false, outside: true), on: connection)
            }
        }
        // After outside text (this turn's or the conversation's) the jobs block becomes a notice; a screen turn's jobs go
        // to the app, which dispatches them untrusted, and it never vouches (a launch asks the user). ArisImageRouting.answerPlan.
        guard case .answer(let text) = reply else {
            if case .delta = reply { tellOutside() }
            return queue.async { stream(reply, on: connection) }
        }
        // agy asked Aris to run commands for it: Aris runs them and the sealed agy answers (ArisAgyRelay).
        if brain == .antigravity, let commands = ArisAgyRelay.commands(in: text) {
            // Maps only from a clean turn: nothing outside came in, in the conversation or this turn's own tools (M1).
            let clean = !sealed && !untrusted && !conversationOutside && !runner.turnUsedTools
            return queue.async {
                relay(commands, request: request, tier: tier, handsFree: handsFree, sealedTurn: sealed || !clean, round: relayRound,
                      screenTurn: screenSeen || !images.isEmpty, untrustedTurn: untrusted || conversationOutside, on: connection)
            }
        }
        // A hands-free turn whose reads Aris ran: shown, never spoken.
        if shownOnly { queue.async { stream(.shownOnly, on: connection) } }
        let taint = runner.currentTaint
        // A clean turn whose brain read nothing others wrote teaches memory from the user's words, later, off this queue.
        // Never after a memory card this turn: what the user declined (or answered) there is never saved by learning (QA BUG-6).
        // Nor after any card: a turn that asked to do something was a request (QA BUG-6b).
        // A card for a handed-off call counts like any card (a Claude's `remember` the user declined is never learned anyway).
        let handedOffCard = ArisHandOffLedger.shared.current(runner)?.showed == true
        if let words = learnFrom, ArisMemoryLearning.learnsAfterTurn(taint: taint, card: runner.showedCard || runner.showedMemoryCard || handedOffCard) {
            ArisMemoryCurator.live.learn(from: words)
        }
        let plan = ArisImageRouting.answerPlan(answer: text, untrusted: untrusted || conversationOutside, restricted: restricted, vouches: vouches, taint: taint)
        tellOutside()
        // The app hears that the jobs were taken out as its own line, never by reading the answer's words.
        if ArisImageRouting.refusesJobs(answer: text, untrusted: untrusted || conversationOutside, taint: taint) {
            queue.async { stream(.refusedJobs, on: connection) }
        }
        guard let specs = plan.vouched else { return queue.async { stream(.answer(plan.answer), on: connection) } }
        let turn = UUID().uuidString
        queue.async {
            if ArisTeammateDesk.shared.record(turn, specs: specs, request: request) { stream(.turn(turn), on: connection) }
            stream(reply, on: connection)
        }
    }
    // Outside text anywhere in the conversation marks this turn too (I1): a restarted process, the idle restart or
    // another model's runner can't take the open Claude's web and reads off the read judge.
    runner.ask(prompt, tier: tier, learnAs: learnAs, request: request,
               untrusted: ArisLocalReadPolicy.marksTurn(untrusted: untrusted, outsideConversation: conversationOutside),
               screenSeen: screenSeen, handsFree: handsFree,
               images: images, owner: connection, ownData: ownData,
               whenUnavailable: { message in
        queue.async {
            brainHealth.markUnavailable(brain, until: ArisBrainHealth.resetDate(in: message))
            FileHandle.standardError.write(Data("aris-agent: \(brain.rawValue) unavailable (\(message))\n".utf8))
            // A turn whose handed-off call already ran is never asked again on another brain (it would act twice).
            let alreadyActed = ArisHandOffLedger.shared.current(runner)?.didRun == true
            guard !retried, !alreadyActed, relayRound == 0, let route = another(brain) else {
                return stream(.failure(ArisBrainFailure.friendly(message, brain: brain, korean: ArisBrainFailure.korean(request: request, prompt: prompt))), on: connection)
            }
            stream(.status(ArisTurnFallback.status(from: brain, to: route.brain, missing: false)), on: connection)
            // The other brain's turn is everything this one was: its taint, its images where that brain sees them, and
            // the sealed or gated process such a turn runs in there.
            ask(route.brain, tier: tier, prompt: prompt, request: request, learnAs: learnAs, untrusted: untrusted, screenSeen: screenSeen,
                outsideConversation: conversationOutside, vouches: vouches, handsFree: handsFree, images: route.sendsImages ? images : [],
                sealed: route.sealed, learnFrom: learnFrom, ownData: ownData, screenText: screenText, on: connection, retried: true)
        }
    }, listener: reply)
}

/// agy's ```aris-run block (ArisAgyRelay): Aris runs the permitted commands itself, off the agent's queue, each read
/// (the user's apps, the web, a service's read) after agy's read judge allowed it, then the sealed agy (no tools) answers from
/// what came back. One round (a few for connected services and the web): a sealed agy that asks again beyond that gets
/// no more.
func relay(_ commands: [[String]], request: String, tier: ArisTier, handsFree: Bool, sealedTurn: Bool, round: Int, screenTurn: Bool = false,
           untrustedTurn: Bool = false, on connection: NWConnection) {
    // The app dropped the stream (the user cancelled): nothing more is run for a turn nobody waits for (audit orphan-turn-11).
    let waited = { ArisAskAdmission.proceeds(state: connection.state, cancelled: false) }
    guard waited() else { return }
    guard ArisAgyRelay.mayRelay(round: round, commands: commands) else { return stream(.answer(ArisAgyRelay.noMore), on: connection) }
    let permitted = commands.filter { ArisAgyRelay.permitted($0, sealed: sealedTurn, handsFree: handsFree) }
    // Connected services go through the one gate, whose cards go up on this stream.
    let services = commands.contains(where: ArisAgyRelay.isMCP)
    let searches = commands.contains(where: ArisAgyRelay.isWeb)
    let desktop = commands.contains(where: ArisAgyRelay.isDesktop)
    // A relayed turn's desktop calls are counted from its first round (ArisDesktopEngine.maxSteps).
    if round == 0 { ArisDesktopRoutes.relaySteps.reset() }
    // I1: a sealed or untrusted relay is outside text, a screen one screenSeen (careful either way).
    let serviceTaint: ArisTaint = screenTurn ? .screenSeen : sealedTurn || untrustedTurn || outsideConversation.seen ? .outsideText : .none
    // The relay's read judge (review I4, R5): Claude or Codex when installed (every tool of theirs can be turned off), agy
    // only as the last resort, the next one only when a judge can't be had; one memo for this round's reads and services,
    // told whose words these are.
    let environment = ArisAgentRunner.environment()
    let memo = ArisReadMemo(judge: ArisReadJudge.relay(environment: environment), source: handsFree ? .handsFree : .user)
    let serviceTurn = ArisRelayMCPTurn(taint: serviceTaint, screen: screenTurn, handsFree: handsFree, request: ArisMemoryText.ownWords(request), memo: memo, isOpen: {
        if case .ready = connection.state { return true }
        return false
    }) { reply in
        queue.async { stream(reply, on: connection) }
    }
    stream(.status(ArisAgyRelay.readsPrivate(permitted) ? "Aris가 대신 읽는 중" : searches ? "Aris가 대신 찾는 중" : "Aris가 대신 하는 중"), on: connection)
    // What this block's writes do (a card shown, the user's no): after their no, nothing else in it that asks runs.
    let writeNotes = ArisHandOffNotes()
    DispatchQueue.global(qos: .userInitiated).async {
        let outcome = ArisAgyRelay.runJudged(commands, permitted: permitted, judge: { memo.judgeNow($0, request: request) }) { words in
            // Cancelled meanwhile: the block's remaining lines aren't run.
            guard waited() else { return ArisAgyRelay.cancelled }
            if ArisAgyRelay.isMCP(words) { return ArisMCPRoutes.relayed(words, turn: serviceTurn) }
            if ArisAgyRelay.isDesktop(words) { return ArisDesktopRoutes.relayed(words, turn: serviceTurn) }
            // Its file changes: the same gate and card as on every other brain, then aris-tools as Aris.
            if ArisFileRelay.isFileChange(words) {
                return ArisFileRelay.relayed(words, turn: serviceTurn, tools: ArisAgentRunner.toolsPath, home: NSHomeDirectory()) { line in
                    // A video or sound job may take minutes: its full time, and the notch hears it is still going.
                    ArisFileRelay.whileLong(line, beat: { minutes in queue.async { stream(.status(ArisAgentStatus.longJob(minutes: minutes)), on: connection) } }) {
                        ArisAgyRelay.run(line, tools: ArisAgentRunner.toolsPath, environment: environment, timeout: ArisFileRelay.runLimit(line))
                    }
                }
            }
            // Any other write (an event, a reminder, a to-do, a note, a schedule…): the gate every brain's writes pass, and
            // for agy always the user's card, then aris-tools as Aris (ArisActionRelay; audit gate-16).
            // (Maps opened from a clean turn runs as before, without one: M1.)
            if ArisAgyRelay.isWrite(words), !(words.first == "maps" && !sealedTurn) {
                return ArisActionRelay.relayed(words, turn: serviceTurn, request: ArisMemoryText.ownWords(request), critical: tier == .critical,
                                               tools: ArisAgentRunner.toolsPath, home: NSHomeDirectory(), notes: writeNotes) { line in
                    ArisAgyRelay.run(line, tools: ArisAgentRunner.toolsPath, environment: environment, timeout: ArisActionGate.runLimit(line))
                }
            }
            // Website work: the one Aside gate and its card, as on every brain (ArisAsideTool).
            if ArisAgyRelay.isAside(words) { return ArisAsideTool.relayed(words, turn: serviceTurn, critical: tier == .critical) }
            if ArisAgyRelay.isSkill(words) {
                return ArisSkillTool.relayed(words, turn: serviceTurn, skills: .live) { title in queue.async { stream(.skill(title), on: connection) } }
            }
            if words.starts(with: ["web", "search"]) {
                return ArisAgySearch.run(query: words.dropFirst(2).joined(separator: " "), environment: environment)
            }
            return ArisAgyRelay.run(words, tools: ArisAgentRunner.toolsPath, environment: environment)
        }
        let results = outcome.results
        ArisWorkDesk.live.relayed(permitted, on: ObjectIdentifier(connection))
        for why in outcome.blocked {
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "read refused by the judge (\(why.rawValue))", "question": "agy relay"]), key: "relay")
            queue.async { stream(.status(ArisReadGate.status(why)), on: connection) }
        }
        let privateRead = ArisAgyRelay.readsPrivate(permitted)
        // Only what brings others' words back (a read, a list) makes the conversation outside text (M3); a timer doesn't.
        let outside = ArisAgyRelay.bringsInOutside(permitted)
        queue.async {
            if privateRead { agyPrivateConversation.mark() }
            // What was read counts for the conversation even when its turn was cancelled; no answer is started for it.
            if outside { outsideConversation.mark() }
            guard waited() else { return }
            if outside {
                // The conversation keeps that, and the app shows the answer as written.
                outsideConversation.mark()
                stream(.untrusted(screen: false, dispatch: false, outside: true), on: connection)
            }
            // A service's listing or result may need one more call (agy may ask for it, a few rounds at most).
            let more = (services || searches || commands.contains(where: ArisAgyRelay.isSkill) || commands.contains(where: ArisAgyRelay.isAside))
                && round + 1 < ArisAgyRelay.maxMCPRounds
            let moreDesktop = desktop && round + 1 < ArisAgyRelay.maxDesktopRounds
            let moreWrites = commands.contains(where: ArisAgyRelay.isWrite) && round + 1 < ArisAgyRelay.maxMCPRounds
            ask(.antigravity, tier: tier, prompt: ArisAgyRelay.prompt(request: request, results: results, moreServices: more, moreDesktop: moreDesktop,
                                                                        moreWrites: moreWrites), request: request,
                learnAs: nil, untrusted: outside, outsideConversation: outside, handsFree: handsFree, sealed: true, relayRound: round + 1,
                shownOnly: handsFree && (privateRead || services), on: connection)
        }
    }
}

/// The answer's lines go out as they come; the body ends when the connection closes.
func startStream(_ connection: NWConnection) {
    let head = "HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
    connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
}

/// A background task's question can wait a day for the user: a blank line every few minutes keeps the app's
/// request from timing out while nothing else is said (its task session allows 26 h of quiet). A conversation's
/// request allows 130 s of quiet (ArisAgentClient.timeout), so its blank lines come every 50 s. Both stop when the
/// connection ends.
let taskKeepAlive: TimeInterval = 240
let conversationKeepAlive: TimeInterval = 50

func keepAlive(_ connection: NWConnection, every interval: TimeInterval = taskKeepAlive) {
    queue.asyncAfter(deadline: .now() + interval) {
        guard case .ready = connection.state else { return }
        connection.send(content: Data("\n".utf8), completion: .contentProcessed { _ in })
        keepAlive(connection, every: interval)
    }
}

/// Notices the app closing its end of a task's stream (it sends nothing after the request) and cancels the
/// connection; the state handler then decides whether the task ends (only if the app's process is gone).
func watchClose(_ connection: NWConnection) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 1_024) { _, _, isComplete, error in
        if isComplete || error != nil { return connection.cancel() }
        watchClose(connection)
    }
}

func stream(_ reply: ArisAgentReply, on connection: NWConnection) {
    ArisWhyDesk.shared.heard(reply, on: ObjectIdentifier(connection))
    ArisWorkDesk.live.heard(reply, on: ObjectIdentifier(connection))
    // A routine running on this connection keeps each step's answer and sends one account at the end (ArisRoutineTurn).
    guard let reply = ArisRoutineTurn.through(reply, on: connection) else { return }
    // The button this turn's failure earned goes just before its last line (ArisFixTurns).
    if let fix = ArisFixTurns.shared.closingLine(reply, on: connection) { connection.send(content: fix, completion: .contentProcessed { _ in }) }
    guard reply.isLast else { return connection.send(content: reply.line, completion: .contentProcessed { _ in }) }
    connection.send(content: reply.line, contentContext: .finalMessage, isComplete: true,
                    completion: .contentProcessed { _ in connection.cancel() })
}

func handle(_ request: HTTPRequest, on connection: NWConnection) {
    guard let token = ClaudeHookToken.load(), request.hasToken(token) else {
        return respond(connection, "401 Unauthorized", Data())
    }
    guard request.method == "POST", request.isLocalClient(port: Int(port.rawValue)), request.isJSON,
          let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
        return respond(connection, "400 Bad Request", Data())
    }
    switch request.path {
    case "/ask":
        guard let text = object["text"] as? String, !text.isEmpty else { return respond(connection, "400 Bad Request", Data()) }
        // Too long: said as that (413, with the limit), never as a request the helper didn't take.
        guard ArisMemoryText.ownWords(text).count <= maxText, text.count <= maxText + maxAttachedText else {
            return respond(connection, "413 Payload Too Large", (try? JSONSerialization.data(withJSONObject: ["error": "too long", "limit": maxText])) ?? Data())
        }
        // Screen images: only from the Aris app itself (any token holder can /ask), never on a background task, and every
        // one checked before anything else happens (any problem refuses the turn, nothing half used).
        let offered = object["images"].map { !($0 is NSNull) && ($0 as? [Any])?.isEmpty != true } ?? false
        // Who asked: checked once, while the connection is open. Anything but the Aris app itself is outside text.
        let peerFailure = ArisPeer.failure(pid: (object["pid"] as? Int).flatMap { Int32(exactly: $0) }, started: object["started"] as? Double,
                                           remotePort: ArisTeammateDesk.remotePort(of: connection), agentPort: port.rawValue, requesterPort: nil)
        if offered {
            guard object["task"] as? Bool != true else { return respond(connection, "400 Bad Request", Data()) }
            if let failure = peerFailure {
                ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(failure.rawValue))", "question": "images"]), key: "ask")
                return respond(connection, "403 Forbidden", Data("{}".utf8))
            }
        }
        // Decoding up to 24 MiB of images takes long enough to hold every other route: it runs off the server queue
        // and the turn carries on here once it's done (a turn without images decodes nothing and goes on at once).
        // The app may close the connection during the decode: its state is watched from before the decode starts,
        // and a turn whose connection went isn't started at all (ArisAskAdmission).
        let cancelled = ArisCancelFlag()
        if offered {
            connection.stateUpdateHandler = { state in
                switch state {
                case .cancelled, .failed: cancelled.set()
                default: break
                }
            }
            watchClose(connection)
            DispatchQueue.global(qos: .userInitiated).async {
                let parsed = ArisTurnImage.parse(object["images"])
                // An API brain whose model can't see: the images' words are read here, off the server queue, in case no
                // other brain that sees is installed (ArisImageRouting.Route.readsText).
                var imageText: String?
                if ArisBrain.named(object["brain"] as? String) == .api, ArisAPIActive.profile()?.takesImages != true, case .success(let images) = parsed {
                    imageText = ArisAPIImageText.text(of: images)
                }
                queue.async {
                    handleAsk(object, text: text, peerFailure: peerFailure, parsed: parsed, imageText: imageText, cancelled: cancelled, watched: true,
                              on: connection)
                }
            }
        } else {
            handleAsk(object, text: text, peerFailure: peerFailure, parsed: .success([]), cancelled: cancelled, watched: false, on: connection)
        }
    default:
        handleOther(request, object: object, on: connection)
    }
}

/// POST /ask from the images on (`parsed`: ArisTurnImage.parse's result; `peerFailure`: why the caller isn't the app,
/// checked while the connection was open; `cancelled` and `watched`: the close watch installed before an off-queue
/// decode), on the server queue.
func handleAsk(_ object: [String: Any], text: String, peerFailure: ArisPeer.Failure?, parsed: Result<[ArisTurnImage], ArisTurnImageError>,
               imageText: String? = nil, cancelled: ArisCancelFlag, watched: Bool, on connection: NWConnection) {
        // Closed while the images were decoded: nothing of this turn happens (no flags, no fresh start, no brain).
        guard ArisAskAdmission.proceeds(state: connection.state, cancelled: cancelled.isSet) else {
            FileHandle.standardError.write(Data("aris-agent: /ask closed before its images were checked; nothing started\n".utf8))
            return
        }
        // The user's computer-use engine, from the app only; a change retires Codex's processes set for the old one.
        if peerFailure == nil, let engine = object["computerEngine"] as? String, ArisComputerEngineChoice.set(engine) { ArisAgentRunner.retire(brain: .codex) }
        let context = (object["context"] as? String).map { String($0.prefix(maxContext)) }
        // The notch shelf's files and the app in front as the user asked, from the app itself only and not for a background
        // job: kept for aris-tools' `--shelf` and `--finder` (ArisShelfFiles), never shown to a brain. An emptied shelf
        // clears them.
        if peerFailure == nil, object["task"] as? Bool != true {
            ArisShelfFiles.save((object["shelf"] as? [Any] ?? []).compactMap { $0 as? String }, front: object["frontApp"] as? String, home: NSHomeDirectory())
        }
        // What "이거" points at (ArisLook). Only a gated brain (Codex, an API brain) sees the screen: the others act without asking.
        var screen = (object["screen"] as? String).map { String($0.prefix(maxScreen)) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // A teammate's job (any but Claude Code, which opens in a terminal): its brain, instructions, notes and scopes are
        // the stored teammate's, never the request's.
        let storedTeam = object["task"] as? Bool == true ? ArisTeammateStore.load(file: ArisTeammateStore.file(home: home)) : []
        // A job naming a teammate that isn't stored (removed while it waited, an unreadable list) never runs as main Aris.
        if object["task"] as? Bool == true, ArisTeammateJobs.missing(object["teammate"], in: storedTeam) {
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (teammate not found)", "question": "task"]), key: "ask")
            return stream(.failure("그 팀원을 찾지 못했어요. 팀원 설정을 확인해 주세요."), on: connection)
        }
        let jobTeammate = object["task"] as? Bool == true ? ArisTeammateJobs.teammate(object["teammate"], in: storedTeam) : nil
        let requestedBrain = jobTeammate.map(ArisTeammateJobs.brain(of:)) ?? ArisBrain.named(object["brain"] as? String)
        let apiProfile = requestedBrain == .api ? ArisAPIActive.profile() : nil
        let images: [ArisTurnImage]
        switch parsed {
        case .success(let checked): images = checked
        case .failure(let problem):
            // Which check failed, never the bytes.
            FileHandle.standardError.write(Data("aris-agent: images refused (\(problem))\n".utf8))
            return respond(connection, "400 Bad Request", Data())
        }
        let focusRaw = object["focus"] as? String
        if let focusRaw, ArisReferenceFocus(rawValue: focusRaw) == nil { return respond(connection, "400 Bad Request", Data()) }
        // An image turn marks the whole conversation (screenSeen) until it starts over.
        let fresh = object["fresh"] as? Bool == true
        // The app keeps "saw the screen" with the conversation's history, so a resume or an agent restart carries it.
        let sawScreen = screenConversation.turn(fresh: fresh, images: images, claimed: object["screenConversation"] as? Bool == true)
        // Model-written text (a dispatched job) is as untrusted as screen content: outside text. A conversation that saw
        // the screen is screenSeen (R1 = B: the user's own words still go as judged). Either restricts the turn (no fallback,
        // shortcut, vouch, teammates or dispatch). `request` is what the user actually said.
        // Outside text: model-written text, any caller but the app itself (it never shares the user's thread clean), and a
        // context carrying a background job's result (done or failed: an untrusted job wrote it).
        let flagged = object["untrusted"] as? Bool == true || peerFailure != nil || ArisImageRouting.carriesJobResults(context)
        let untrusted = ArisImageRouting.untrusted(screenText: screen != nil, flagged: flagged, images: images, screenConversation: sawScreen)
        let outsideTextBefore = ArisImageRouting.taint(screenText: screen != nil, flagged: flagged, screenConversation: sawScreen) == .outsideText
        let request = (object["request"] as? String).map { String($0.prefix(maxText + maxAttachedText)) } ?? text
        // Heard in a conversation without a key or the name (ArisHandsFree): no vouch, standing permission, remembered
        // yes, learned shortcut or request coverage.
        let handsFree = object["handsFree"] as? Bool == true
        // Auto mode's "what the user asked" (ArisOwnerWords): only their own typed or spoken turn, from the app itself; never
        // hands-free, model-written, a job's brief, a routine's stored step, or a turn the app says takes no action (the
        // rewrite of a selection, which declines every card).
        // Whether the list and the calendar an unnamed to-do or event goes into are his own (review 9, L2): only the
        // app itself says, with each of its conversation turns; anything else leaves them unknown (today's card).
        if object["task"] as? Bool != true { ArisAutoPlacesBox.shared.set(peerFailure == nil ? ArisAutoPlaces(json: object["ownPlaces"]) : .unknown) }
        if object["task"] as? Bool != true {
            ArisOwnerWords.shared.turn(request, fresh: fresh, his: peerFailure == nil && !handsFree && object["untrusted"] as? Bool != true
                                       && object["noActions"] as? Bool != true && !ArisRoutineTurn.isStep(connection))
        }
        // Outside text anywhere in the conversation, on any brain (this turn's, a runner's, or the app's claim after a
        // resume): it dispatches nothing until a fresh start, and agy answers it sealed (R1).
        let sawOutsideBefore = outsideConversation.turn(fresh: fresh, outsideText: outsideTextBefore || (!fresh && ArisAgentRunner.anyOutsideText()),
                                                        claimed: object["outsideConversation"] as? Bool == true)
        let agySealed = ArisAgyRelay.sealsConversation(privateRead: agyPrivateConversation.turn(fresh: fresh, outsideText: false), outside: sawOutsideBefore)
        // A fresh conversation: agy's relayed computer use forgets its snapshots and the user's per-app yeses.
        if fresh { ArisDesktopRoutes.relayLedger.reset() }
        // Main Aris's own turn (not a task, not about the screen, not model-written) may hand jobs to Claude Code.
        // An API brain that can't see: which installed brains can (read only then).
        let apiVision = apiProfile?.takesImages == true
        let needsSight = requestedBrain == .api && !apiVision && (!images.isEmpty || sawScreen)
        let sight = ArisImageRouting.APISight(vision: apiVision, claude: needsSight && ArisClaudeDriver(model: "", tools: "").launch() != nil,
                                              codex: needsSight && ArisReadJudge.executable(.codex) != nil)
        let route = ArisImageRouting.route(requested: requestedBrain, images: images, screenText: screen != nil,
                                           claudeInstalled: !(sawScreen || handsFree) || ArisClaudeDriver(model: "", tools: "").launch() != nil,
                                           screenConversation: sawScreen, task: object["task"] as? Bool == true, handsFree: handsFree,
                                           privateRead: agySealed, api: sight)
        // The images' words instead of the images: other people's words, so the turn (and the conversation) carries outside text.
        let readsText = route.readsText && imageText != nil
        if readsText, let imageText {
            screen = [screen, imageText].compactMap { $0 }.joined(separator: "\n\n")
            outsideConversation.mark()
        }
        let outsideText = outsideTextBefore || readsText
        let sawOutside = sawOutsideBefore || readsText
        // Aris's own schedules, to-dos, memory, teammates, timers and settings (QA BUG-60): told from the user's words and the
        // schedules' own titles; done in this turn with Aris's own tool, never handed out, never Aside's.
        let scheduleNames = ArisOwnDataTurn.scheduleNames(home: home)
        let ownData = ArisOwnData.kind(of: ArisMemoryText.ownWords(request), scheduleNames: scheduleNames)
        let dispatch = ArisImageRouting.dispatchPolicy(outsideText: sawOutside, screenSeen: sawScreen, task: object["task"] as? Bool == true,
                                                       arisData: ownData != nil)
        let mainTurn = dispatch.vouch
        let focus = focusRaw.flatMap(ArisReferenceFocus.init(rawValue:)) ?? .screen
        let sent = route.sendsImages ? images : []
        // The images (or why they couldn't come), and in a screen conversation the rule to quote the user's words as said.
        let notes = [route.sendsImages ? ArisAgentPrompt.images(images, focus: focus) : route.note,
                     sawScreen ? ArisAgentPrompt.screenWords : nil].compactMap { $0 }
        // The few memories this turn is about (ArisMemoryRecall), only on the user's clean turn: none hands-free, after outside
        // text or the screen, from another caller, or for a job (ArisMemoryLearning.mayRecall).
        let memory = ArisMemoryCurator.live.context(for: request, eligible: ArisMemoryLearning.mayRecall(
            fromApp: peerFailure == nil, task: object["task"] as? Bool == true, untrusted: untrusted, outsideConversation: sawOutside,
            screenSeen: sawScreen, handsFree: handsFree, images: !images.isEmpty, screenText: screen != nil))
        // What Aris noted about the apps this involves, and a teammate's own block for its job (ArisTeamPrompt).
        let frontLine = context?.components(separatedBy: "\n").first { $0.hasPrefix("front app: ") }
        let knowhow = ArisTeamPrompt.knowhow(ArisNotesStore.load(ArisNotesStore.knowhowFile(home: home)), request: text, frontApp: frontLine)
        let mateBlock = jobTeammate.map { mate in
            ArisTeamPrompt.job(mate, notes: ArisNotesStore.teammateFile(home: home, id: mate.id).map(ArisNotesStore.load) ?? [])
        }
        let ownNote = ownData.map {
            ArisOwnDataTurn.note($0, tools: route.brain == .api ? ArisAPICatalog.generic : ArisAgentRunner.toolsPath, task: object["task"] as? Bool == true,
                                 named: ArisOwnData.namesSchedule(ArisMemoryText.ownWords(request), scheduleNames: scheduleNames))
        }
        // What worked before on this Mac (ArisWorkRecall): Aris's own record, for the same turns that get the user's memories.
        let worked = ArisWorkDesk.live.context(for: request, eligible: ArisMemoryLearning.mayRecall(
            fromApp: peerFailure == nil, task: object["task"] as? Bool == true, untrusted: untrusted, outsideConversation: sawOutside,
            screenSeen: sawScreen, handsFree: handsFree, images: !images.isEmpty, screenText: screen != nil))
        // What the turn's episode will be judged by when it ends (ArisWorkTaintRule), and what it was offered.
        ArisWorkDesk.live.begin(ArisWorkStart(
            request: request, facts: ArisWorkTurnFacts(fromApp: peerFailure == nil, task: object["task"] as? Bool == true, untrusted: untrusted,
                                                       outsideConversation: sawOutside, screenSeen: sawScreen, handsFree: handsFree, images: !images.isEmpty,
                                                       screenText: screen != nil, attached: ArisMemoryText.ownWords(request) != request),
            teammate: jobTeammate?.id ?? "", job: object["task"] as? Bool == true ? ArisWorkDesk.taskLabel((object["title"] as? String).map { String($0.prefix(80)) } ?? "Aris") : ArisWorkDesk.conversationJob,
            offered: worked.picked.names, firstSteps: worked.picked.firstSteps), on: ObjectIdentifier(connection))
        let noteBlock = [knowhow, mateBlock ?? ArisTeamPrompt.noteRule(teammate: false), mateBlock == nil ? ArisTeamPrompt.teamTruth : nil, ownNote, worked.block]
            .compactMap { $0 }.joined(separator: "\n")
        let prompt = ArisAgentStream.prompt(request: text, context: context, memory: memory, screen: screen,
                                            teammates: dispatch.teammates ? teammatesBlock(for: text) : nil,
                                            imageNote: notes.isEmpty ? nil : notes.joined(separator: "\n"),
                                            skills: ArisSkillPrompt.block(ArisSkills.live.listings(), tools: route.brain == .api ? ArisAPICatalog.generic : ArisAgentRunner.toolsPath),
                                            notes: noteBlock)
        let brain = route.brain
        let tier = ArisTier.named(object["tier"] as? String)
        let model = brain.model(tier: tier)
        let key = ArisShortcuts.key(for: text)
        if fresh { ArisAgentRunner.startNewConversation() }
        if !ArisRoutineTurn.isStep(connection) {
            startStream(connection)
            ArisFixTurns.shared.began(connection, task: object["task"] as? Bool == true, toldUnread: ArisScreenRead.saysPermissionOff(object["screen"] as? String))
        }
        // The app dispatches this turn's jobs only when it may (a screen turn: untrusted, launches ask), never otherwise.
        if untrusted || sawOutside { stream(.untrusted(screen: sawScreen, dispatch: dispatch.teammates, outside: sawOutside), on: connection) }
        if let status = route.status { stream(.status(status), on: connection) }
        // "왜 그렇게 했어?" is answered here from the last turn's own record, by no AI; any other turn opens its record (ArisWhyDesk).
        if ArisWhyDesk.shared.turn(ArisWhyStart(request: request, handsFree: handsFree, screen: sawScreen || !images.isEmpty || screen != nil,
                                                outside: sawOutside, memory: memory, wanted: requestedBrain, routed: brain),
                                   context: context, caller: ArisWhyDesk.Caller(fromApp: peerFailure == nil, task: object["task"] as? Bool == true,
                                                                                showsScreen: !images.isEmpty || screen != nil, tainted: untrusted || sawOutside),
                                   on: ObjectIdentifier(connection), answer: { text in
                                       queue.async {
                                           // Said first: this answer is the helper's own, no AI was asked (ArisAgentReply.helperAnswers).
                                           stream(.helperAnswers, on: connection)
                                           stream(.answer(text), on: connection)
                                       }
                                   }) { return }
        // A hands-free turn no brain can take restricted (Antigravity without Claude): said, nothing run.
        if let refusal = route.refusal { return stream(.answer(refusal), on: connection) }
        if object["task"] as? Bool == true {
            keepAlive(connection)
            let title = (object["title"] as? String).map { String($0.prefix(80)) } ?? "Aris"
            let browser = object["browser"] as? Bool == true
            // Website work goes to Aside with every name as the user said it; never when it is Aris's own data after all (the
            // job then does it with Aris's own tool, on its card).
            let taskPrompt = browser && ownData == nil
                ? ArisAgentStream.prompt(request: text + "\n\n(Website work: hand it to Aside, the user's browser agent, in one Aside task as your tools describe. Keep every name in the brief exactly as the user said it.)", context: context, memory: memory, screen: screen)
                : prompt
            // An untrusted job (a screen turn's, outside text's, a model's) runs on Codex with web search off; a teammate's
            // on its own brain behind that brain's gates and its scopes (ArisTeammateJobs). The log names it and keeps its id.
            // A helper's name from the app (the log files its rows under it, N14); never from anyone else.
            let helper = peerFailure == nil ? ArisActivityBridge.helperLabel(object["helper"]) : nil
            guard let runner = ArisAgentRunner.task(brain: brain, model: model, title: title, job: ArisTaskEnd.jobId(object["job"]),
                                                    untrusted: untrusted, teammate: jobTeammate, handsFree: handsFree && route.sealed,
                                                    helper: helper) else {
                return stream(.failure("이 작업은 취소됐어요."), on: connection)
            }
            ArisWorkDesk.live.bind(runner, to: ObjectIdentifier(connection))
            // A cancelled job comes as POST /cancel. A connection that closes otherwise cancels the task only when the
            // app's process is gone (quit, crashed): its pid no longer exists with the start time it sent. While that
            // same process still runs it was a dropped stream (a long sleep), and the task carries on: its result is
            // still saved and opened, and a parked question expires as a no.
            let appPid = (object["pid"] as? Int).flatMap { Int32(exactly: $0) }
            let appStarted = object["started"] as? Double
            connection.stateUpdateHandler = { state in
                switch state {
                case .cancelled, .failed:
                    ArisWorkDesk.live.closed(ObjectIdentifier(connection))
                    if ArisTaskEnd.cancelsOnClose(appAlive: ArisTaskEnd.isAlive(pid: appPid, started: appStarted)) { runner.cancelTask() }
                default: break
                }
            }
            if !watched { watchClose(connection) }
            return runner.ask(taskPrompt, tier: tier, request: request,
                              untrusted: ArisLocalReadPolicy.marksTurn(untrusted: outsideText, outsideConversation: sawOutside),
                              screenSeen: sawScreen, handsFree: handsFree, ownData: ownData != nil) { reply in
                queue.async { stream(reply, on: connection) }
            }
        }
        // A conversation's answer can wait on a card or a judgement longer than the app's request timeout: blank lines keep
        // the connection alive, and when the app drops it anyway (a timeout, sleep, a cancel) the turn it owns ends at
        // once, so the next question doesn't meet "still answering the last question".
        if !ArisRoutineTurn.isStep(connection) { keepAlive(connection, every: conversationKeepAlive) }
        connection.stateUpdateHandler = { state in
            switch state {
            case .cancelled, .failed:
                ArisWorkDesk.live.closed(ObjectIdentifier(connection))
                ArisAgentRunner.abandon(owner: connection)
            default: break
            }
        }
        if !watched { watchClose(connection) }
        // The user's routines ("출근 루틴 해 줘", "… 루틴 만들어 줘: …"): made, shown and changed here on their card, and run here
        // one step at a time, each step back through this function as a turn of its own (ArisRoutineTurn).
        if ArisRoutineTurn.takes(object, request: request, fromApp: peerFailure == nil, handsFree: handsFree, plain: images.isEmpty && screen == nil, on: connection,
                                 step: { handleAsk($0, text: $1, peerFailure: peerFailure, parsed: .success([]), cancelled: cancelled, watched: true, on: connection) }) { return }
        // About the screen: never learned or answered as a shortcut (the same words mean different things each time).
        // Checked now, while the caller's connection is open: only the app's own turn can vouch (any token holder can /ask).
        let fromApp = mainTurn && peerFailure == nil && ArisPeer.isApp(pid: (object["pid"] as? Int).flatMap { Int32(exactly: $0) }, started: object["started"] as? Double,
                                                 remotePort: ArisTeammateDesk.remotePort(of: connection), agentPort: port.rawValue,
                                                 requesterPort: nil)
        // The user's own words of a clean turn teach memory once it's answered (ArisMemoryLearning); nothing else ever does.
        let clean = ArisMemoryLearning.mayLearn(fromApp: fromApp, task: false, untrusted: untrusted, outsideConversation: sawOutside, screenSeen: sawScreen,
                                                handsFree: handsFree, images: !images.isEmpty, screenText: screen != nil, tainted: false)
        // "어제 그 파일 어디 저장했지 / 지난번에 … 어떻게 했지": answered here from Aris's own record of its work, by no AI, when
        // one clearly matches (ArisWorkIntent). One that rests on a turn that read outside content marks the conversation.
        if let found = ArisWorkDesk.live.localAnswer(request, fromApp: peerFailure == nil, handsFree: handsFree, plain: images.isEmpty && screen == nil) {
            if found.tainted {
                outsideConversation.mark()
                stream(.untrusted(screen: sawScreen, dispatch: false, outside: true), on: connection)
            }
            return stream(.answer(found.text), on: connection)
        }
        // "기억해 / 잊어 / 내가 뭐라고 했지 / 나에 대해 뭐 알아 / 어제 뭐 했지": answered here from the store, the user's words as said.
        if let intent = ArisMemoryCurator.live.pendingIntent(for: request) ?? ArisMemoryIntent.parse(request),
           ArisMemoryLearning.answersLocally(intent, fromApp: peerFailure == nil, handsFree: handsFree, images: !images.isEmpty, clean: clean) {
            DispatchQueue.global(qos: .userInitiated).async {
                // Several memories, or one found only loosely: the user sees exactly what would go on a card first (QA BUG-59).
                if case .forget(let words) = intent, let found = ArisMemoryCurator.live.forgetAsks(words) {
                    return queue.async { askForget(found, words: words, said: request, on: connection) }
                }
                // "…잊어" that names no memory about him but one thing Aris learned from its work: that lesson goes (ArisWorkIntent).
                let answer = ArisWorkDesk.live.forgetAnswer(intent, said: request) ?? ArisMemoryCurator.live.answer(intent, said: request)
                queue.async {
                    guard let answer else {
                        return converse(object, text: text, request: request, prompt: prompt, brain: brain, tier: tier, key: key, untrusted: untrusted,
                                        handsFree: handsFree, sawScreen: sawScreen, sawOutside: sawOutside, outsideText: outsideText, mainTurn: mainTurn,
                                        fromApp: fromApp, context: context, memory: memory, sent: sent, sealed: route.sealed, learnFrom: clean && request.count <= maxLearned ? request : nil,
                                        ownData: ownData != nil, screenText: object["screen"] is String, on: connection)
                    }
                    if intent.writes {
                        ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["action": "memory: \(intent.auditName)", "risk": "spoken"]), key: "local")
                    }
                    stream(.answer(answer), on: connection)
                }
            }
            return
        }
        converse(object, text: text, request: request, prompt: prompt, brain: brain, tier: tier, key: key, untrusted: untrusted, handsFree: handsFree,
                 sawScreen: sawScreen, sawOutside: sawOutside, outsideText: outsideText, mainTurn: mainTurn, fromApp: fromApp, context: context,
                 memory: memory, sent: sent, sealed: route.sealed, learnFrom: clean && request.count <= maxLearned ? request : nil, ownData: ownData != nil,
                 screenText: object["screen"] is String, on: connection)
}

/// "…잊어 줘" that would remove several memories, or one found only loosely: the card lists exactly what goes, and only
/// The user's yes on it removes them (a no, or no answer, leaves them). On the server queue.
func askForget(_ found: [ArisMemoryRecord], words: String, said: String, on connection: NWConnection) {
    let korean = ArisMemoryText.isKorean(said) || !said.contains(where: \.isLetter)
    let card = ArisMemoryAnswer.forgetCard(found, words: words, korean: korean)
    let shown = ArisMCPCards.shared.put(card, timeout: ArisCardEdit.questionTimeout) { answer in
        DispatchQueue.global(qos: .userInitiated).async {
            let reply: String
            switch answer {
            case .yes:
                reply = ArisMemoryCurator.live.forget(found, korean: korean)
                ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["action": "memory: forget \(found.count) (card)", "risk": "asked"]), key: "local")
            case .no: reply = ArisMemoryAnswer.kept(unanswered: false, korean: korean)
            case .unanswered: reply = ArisMemoryAnswer.kept(unanswered: true, korean: korean)
            }
            queue.async { stream(.answer(reply), on: connection) }
        }
    }
    stream(.confirm(shown), on: connection)
}

/// A conversation turn's brain (or learned shortcut), once /ask has decided everything about it (handleAsk).
/// `learnFrom`: the user's words when the turn may teach memory (ArisMemoryLearning.mayLearn).
func converse(_ object: [String: Any], text: String, request: String, prompt: String, brain: ArisBrain, tier: ArisTier, key: String,
              untrusted: Bool, handsFree: Bool, sawScreen: Bool, sawOutside: Bool, outsideText: Bool, mainTurn: Bool, fromApp: Bool,
              context: String?, memory: String?, sent: [ArisTurnImage], sealed: Bool, learnFrom: String?, ownData: Bool = false,
              screenText: Bool = false, on connection: NWConnection) {
        let vouches = ArisHandsFree.vouches(ArisTeammateGate.vouches(mainTurn: mainTurn, fromApp: fromApp, context: context, memory: memory),
                                            handsFree: handsFree)
        let askBrain = { ask(brain, tier: tier, prompt: prompt, request: request, learnAs: untrusted || handsFree ? nil : key, untrusted: outsideText,
                             screenSeen: sawScreen, outsideConversation: sawOutside,
                             vouches: vouches, handsFree: handsFree, images: sent, sealed: sealed, learnFrom: learnFrom, ownData: ownData,
                             screenText: screenText, on: connection) }
        // A learned shortcut answers at once, without any AI; one that no longer works is forgotten.
        guard ArisHandsFree.mayReplayShortcut(untrusted: untrusted, handsFree: handsFree), let learned = ArisShortcutStore.shared.lookup(key) else { return askBrain() }
        // Learned before questions were kept out: forgotten, and the AI answers.
        guard !ArisShortcuts.isQuestion(key) else {
            ArisShortcutStore.shared.forget(key)
            return askBrain()
        }
        // The replay runs commands: the turn shows a step before the first one starts (ArisAgentStatus.forReplay), so
        // the app knows this turn has done something and never asks it again by itself.
        stream(.status(ArisAgentStatus.forReplay(learned.commands, tools: ArisAgentRunner.toolsPath)), on: connection)
        DispatchQueue.global(qos: .userInitiated).async {
            if ArisShortcutStore.shared.replay(learned, tools: ArisAgentRunner.toolsPath, environment: ArisAgentRunner.environment()) {
                queue.async { stream(.answer(learned.reply), on: connection) }
            } else {
                ArisShortcutStore.shared.forget(key)
                // On the server queue, where the brains' quota state is read (it was read from this one: audit orphan-turn-11).
                queue.async { askBrain() }
            }
        }
}

/// Every route but /ask, on the server queue.
func handleOther(_ request: HTTPRequest, object: [String: Any], on connection: NWConnection) {
    switch request.path {
    case "/confirm":
        guard let id = object["id"] as? String, let allow = object["allow"] as? Bool else {
            return respond(connection, "400 Bad Request", Data())
        }
        // Every card is answered only by the app itself (ArisPeer: any token holder, a Claude Code session included, could
        // otherwise say yes), and a yes only for the card exactly as the agent made it (the app sends back what it showed).
        let pid = (object["pid"] as? Int).flatMap { Int32(exactly: $0) }, started = object["started"] as? Double
        let detail = object["detail"] as? String, full = object["full"] as? String
        // The owner's ②A: what they changed on the card, and the card's text as finally shown (both checked below).
        guard let edits = ArisCardEdit.edits(from: object["edits"]) else { return respond(connection, "400 Bad Request", Data()) }
        let shown = object["shown"] as? String
        // The app closed the card at its limit, the user never answered: told apart from their no (QA live on 827cfdb4).
        let unanswered = !allow && object["unanswered"] as? Bool == true
        // This card's line in the ledger is the gate's own, never a second "app card" one (ArisCardLedger).
        cardLedger = cardLedger.agentAnswered(id)
        // A routine reads this to tell whether a step's card got the user's yes; it approves nothing (ArisRoutineCards).
        ArisRoutineCards.shared.answered(id, allow: allow, unanswered: unanswered)
        if id.hasPrefix(ArisTeammateGate.questionPrefix) {
            // A Claude Code launch card has nothing to change.
            guard edits.isEmpty else { return respond(connection, "403 Forbidden", Data("{}".utf8)) }
            switch ArisTeammateDesk.shared.decide(id, allow: allow, pid: pid, started: started, detail: detail, full: full, on: connection) {
            case .decided: return respond(connection, "200 OK", Data("{}".utf8))
            case .refused: return respond(connection, "403 Forbidden", Data("{}".utf8))
            case .unknown: return respond(connection, "404 Not Found", Data("{}".utf8))
            }
        }
        if let failure = ArisPeer.failure(pid: pid, started: started, remotePort: ArisTeammateDesk.remotePort(of: connection),
                                          agentPort: port.rawValue, requesterPort: nil) {
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(failure.rawValue))", "question": id]), key: "confirm")
            return respond(connection, "403 Forbidden", Data("{}".utf8))
        }
        // An external-service card (ArisMCPCards), from any brain's turn: only for the card as made, with the user's changes.
        if ArisMCPCards.owns(id) {
            switch ArisMCPCards.shared.decide(id, allow: allow, detail: detail, full: full, edits: edits, shown: shown, unanswered: unanswered) {
            case .decided: return respond(connection, "200 OK", Data("{}".utf8))
            case .refused:
                ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (the card shown isn't the card made)", "question": id]), key: "confirm")
                return respond(connection, "403 Forbidden", Data("{}".utf8))
            case .unknown: return respond(connection, "404 Not Found", Data("{}".utf8))
            }
        }
        guard ArisAgentRunner.shownMatches(id, allow: allow, detail: detail, full: full, edits: allow ? edits : [:], shown: allow ? shown : nil) else {
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (the card shown isn't the card made)", "question": id]),
                                       key: "confirm")
            return respond(connection, "403 Forbidden", Data("{}".utf8))
        }
        let waiting = ArisAgentRunner.decide(id, allow: allow, edits: allow ? edits : [:], unanswered: unanswered)
        respond(connection, waiting ? "200 OK" : "404 Not Found", Data("{}".utf8))
    case "/api-brains":
        guard isAppItself(object, on: connection, question: "api-brains") else { return }
        ArisAPIRoutes.settings(object, changed: { ArisAgentRunner.retire(brain: .api) },
                               audit: { ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON($0), key: "api") }) { status, body in
            queue.async { respond(connection, status, body) }
        }
    case "/mcp":
        guard isAppItself(object, on: connection, question: "mcp") else { return }
        ArisMCPRoutes.settings(object) { status, body in queue.async { respond(connection, status, body) } }
    case "/mcp-tool":
        ArisMCPRoutes.tool(object, on: connection, agentPort: port.rawValue) { status, body in queue.async { respond(connection, status, body) } }
    case "/desktop-tool":
        ArisDesktopRoutes.tool(object, on: connection, agentPort: port.rawValue) { status, body in queue.async { respond(connection, status, body) } }
    case "/skills":
        guard isAppItself(object, on: connection, question: "skills") else { return }
        ArisSkillRoutes.settings(object) { status, body in queue.async { respond(connection, status, body) } }
    case "/skill-tool":
        ArisSkillRoutes.tool(object, on: connection, agentPort: port.rawValue) { status, body in queue.async { respond(connection, status, body) } }
    case "/message-tool":
        ArisMessageRoutes.tool(object, on: connection, agentPort: port.rawValue) { status, body in queue.async { respond(connection, status, body) } }
    case "/action-tool":
        ArisMessageRoutes.action(object, on: connection, agentPort: port.rawValue) { status, body in queue.async { respond(connection, status, body) } }
    case "/aside-tool":
        ArisAsideRoutes.tool(object, on: connection, agentPort: port.rawValue) { status, body in queue.async { respond(connection, status, body) } }
    case "/routine-tool":
        ArisRoutineRoutes.tool(object, on: connection, agentPort: port.rawValue) { status, body in queue.async { respond(connection, status, body) } }
    case "/routine-step":
        // The app's word on a routine's step it was offered (ArisRoutineHandBack): only the app itself may give it.
        guard isAppItself(object, on: connection, question: "routine-step") else { return }
        respond(connection, ArisRoutineTurn.stepEnded(object) ? "200 OK" : "404 Not Found", Data("{}".utf8))
    case "/cancel":
        guard isAppItself(object, on: connection, question: "cancel") else { return }
        guard let job = ArisTaskEnd.jobId(object["job"]) else { return respond(connection, "400 Bad Request", Data()) }
        // A Claude Code teammate's session finished: its window is closed or left (ArisTeammateDesk.finished).
        if object["done"] as? Bool == true {
            return ArisTeammateDesk.shared.finished(job: job) { end in
                respond(connection, "200 OK", (try? JSONSerialization.data(withJSONObject: ["window": end?.rawValue ?? ""])) ?? Data("{}".utf8))
            }
        }
        ArisAgentRunner.cancel(job: job)
        ArisTeammateDesk.shared.cancel(job: job)
        respond(connection, "200 OK", Data("{}".utf8))
    case "/permissions":
        guard isAppItself(object, on: connection, question: "permissions") else { return }
        switch object["op"] as? String {
        case "list":
            let list = ArisAgentRunner.permissions.all.map { ["kind": $0.kind, "app": $0.app, "target": $0.target] }
            respond(connection, "200 OK", (try? JSONSerialization.data(withJSONObject: ["permissions": list])) ?? Data("{}".utf8))
        case "revoke":
            guard let kind = object["kind"] as? String, let app = object["app"] as? String, let target = object["target"] as? String else {
                return respond(connection, "400 Bad Request", Data())
            }
            let scope = ArisActionScope(kind: kind, app: app, target: target)
            ArisAgentRunner.permissions.revoke(scope)
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "revoked", "question": "permissions",
                                                                  "scope": ArisEscalation.describe(scope)]), key: "settings")
            respond(connection, "200 OK", Data("{}".utf8))
        case "folder":
            // 설정 › 컴퓨터 제어's 허용하기 for Desktop, Documents or Downloads: aris-agent reads the folder's list once, so
            // macOS asks the user now rather than in the middle of an undo (QA BUG-17). Only those three folders.
            guard let url = (object["folder"] as? String).flatMap({ ArisFolderAccess.url(named: $0, home: FileManager.default.homeDirectoryForCurrentUser.path) }) else {
                return respond(connection, "400 Bad Request", Data())
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let granted = ArisFolderAccess.touch(url)
                queue.async { respond(connection, "200 OK", Data(granted ? #"{"granted":true}"#.utf8 : #"{"granted":false}"#.utf8)) }
            }
        case "diskAccess":
            // Whether aris-agent has Full Disk Access (the settings and onboarding row); never asks macOS.
            respond(connection, "200 OK", Data(ArisLocalReadPolicy.hasDiskAccess() ? #"{"granted":true}"#.utf8 : #"{"granted":false}"#.utf8))
        case "screenAccess":
            // Whether aris-agent has Screen Recording (the permission card under an answer); never asks macOS.
            respond(connection, "200 OK", Data(ArisWidgetPick.Access.now.screen ? #"{"granted":true}"#.utf8 : #"{"granted":false}"#.utf8))
        case "accessibilityAccess":
            // Whether aris-agent has its own Accessibility switch (the setup, the helper panel, the settings row): macOS is
            // asked at each call, and is never asked to show anything.
            respond(connection, "200 OK", Data(ArisHelperAccess.accessibility ? #"{"granted":true}"#.utf8 : #"{"granted":false}"#.utf8))
        case "consumeGrant":
            // The app's /aris/events or /aris/todos route asks: was this exact write let run by a gate (ArisActionGrant)?
            guard let key = object["key"] as? String, key.count <= 2_000 else { return respond(connection, "400 Bad Request", Data()) }
            let taken = ArisActionGrants.shared.take(key), granted = taken.granted
            if !granted { ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (no grant)", "question": "app route", "action": String(key.prefix(160))]), key: "grant") }
            // "outside": the automatic check let it through, so the app marks the made item as outside text (review 9, M2).
            respond(connection, "200 OK", Data(!granted ? #"{"granted":false}"#.utf8 : taken.outside ? #"{"granted":true,"outside":true}"#.utf8 : #"{"granted":true}"#.utf8))
        case "cardAnswer":
            // An app-handled card's answer and where it came from, in the same audit ledger as the agent's cards.
            let fields = ["id", "title", "answer", "source"].reduce(into: [String: String]()) { $0[$1] = (object[$1] as? String).map { String($0.prefix(120)) } ?? "" }
            // One line for one card's answer, keyed by its id: never a second one for a card the agent's own gate answers,
            // or for the same answer told twice (QA BUG-60).
            let id = fields["id"] ?? "", now = Date()
            let agentWaits = ArisTeammateDesk.shared.isWaiting(id) ?? (ArisMCPCards.owns(id) ? ArisMCPCards.shared.isWaiting(id) : ArisAgentRunner.isWaiting(id))
            if cardLedger.writesAppLine(id, agentWaits: agentWaits || ArisMCPCards.owns(id), at: now) {
                cardLedger = cardLedger.appWrote(id, at: now)
                ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": fields["answer"] ?? "", "question": "app card", "card": fields["title"] ?? "",
                                                                      "id": id, "source": fields["source"] ?? ""]), key: "card")
            }
            respond(connection, "200 OK", Data("{}".utf8))
        case "waiting":
            guard let id = object["id"] as? String else { return respond(connection, "400 Bad Request", Data()) }
            let waiting = ArisTeammateDesk.shared.isWaiting(id) ?? (ArisMCPCards.owns(id) ? ArisMCPCards.shared.isWaiting(id) : ArisAgentRunner.isWaiting(id))
            respond(connection, "200 OK", Data(waiting ? #"{"waiting":true}"#.utf8 : #"{"waiting":false}"#.utf8))
        default:
            respond(connection, "400 Bad Request", Data())
        }
    case "/save-text":
        // "방금 답을 … 저장해 줘", after the user's yes on the app's card: only the app itself asks (ArisSaveText).
        guard isAppItself(object, on: connection, question: "save-text") else { return }
        // "방금 답 메모에 저장해 줘": the answer as a new Apple Notes note, after the user's yes on the app's note card.
        if object["to"] as? String == "note" {
            guard let text = object["text"] as? String else { return respond(connection, "400 Bad Request", Data()) }
            DispatchQueue.global(qos: .userInitiated).async {
                let failure = ArisAgentRunner.noteText(text)
                ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": failure == nil ? "saved" : "refused (\(failure ?? ""))",
                                                                      "question": "save-note"]), key: "files")
                let body: [String: Any] = failure.map { ["saved": false, "why": $0] } ?? ["saved": true]
                queue.async { respond(connection, "200 OK", (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)) }
            }
            return
        }
        guard let path = object["path"] as? String, let text = object["text"] as? String, path.count <= 400 else {
            return respond(connection, "400 Bad Request", Data())
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = ArisSaveText.save(text, to: path, home: FileManager.default.homeDirectoryForCurrentUser.path)
            let body: [String: Any]
            switch outcome {
            case .saved(let saved): body = ["saved": true, "path": saved]
            case .refused(let why): body = ["saved": false, "why": why]
            }
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": body["saved"] as? Bool == true ? "saved" : "refused (\((body["why"] as? String) ?? ""))",
                                                                  "question": "save-text"]), key: "files")
            queue.async { respond(connection, "200 OK", (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)) }
        }
    case "/open":
        let opened = (object["path"] as? String).map(ArisAgentRunner.openResult) ?? false
        respond(connection, opened ? "200 OK" : "404 Not Found", Data("{}".utf8))
    case "/result":
        guard isAppItself(object, on: connection, question: "result") else { return }
        guard let path = object["path"] as? String, ArisResultPath.resolve(path, in: ArisAgentRunner.resultFolders) != nil else {
            return respond(connection, "404 Not Found", Data("{}".utf8))
        }
        switch object["op"] as? String {
        case "read":
            guard let result = ArisAgentRunner.readResult(path) else { return respond(connection, "404 Not Found", Data("{}".utf8)) }
            let body = ["text": result.text, "modified": result.modified.timeIntervalSince1970] as [String: Any]
            respond(connection, "200 OK", (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8))
        case "note":
            DispatchQueue.global(qos: .userInitiated).async {
                let failure = ArisAgentRunner.noteResult(path)
                let body = (try? JSONSerialization.data(withJSONObject: failure.map { ["error": $0] } ?? [:])) ?? Data("{}".utf8)
                queue.async { respond(connection, failure == nil ? "200 OK" : "500 Internal Server Error", body) }
            }
        default:
            respond(connection, "400 Bad Request", Data())
        }
    case "/warm":
        let brain = brainHealth.brain(for: ArisBrain.named(object["brain"] as? String))
        for tier in [ArisTier.quick, .work] { ArisAgentRunner.shared(brain: brain, model: brain.model(tier: tier)).warm() }
        ArisAgentRunner.warmTask(brain: brain, model: brain.model(tier: .work))
        respond(connection, "200 OK", Data("{}".utf8))
    case "/stop":
        guard isAppItself(object, on: connection, question: "stop") else { return }
        ArisAgentRunner.stopAll()
        // agy's desktop looks and the user's yeses for it end with everything else (I12).
        ArisDesktopRoutes.relayLedger.reset()
        respond(connection, "200 OK", Data("{}".utf8))
    case "/arrange":
        guard isAppItself(object, on: connection, question: "arrange") else { return }
        guard let app = object["app"] as? String, let count = object["count"] as? Int,
              let commands = ArisArrange.commands(app: app, count: count) else { return respond(connection, "400 Bad Request", Data()) }
        if let line = try? JSONSerialization.data(withJSONObject: ["action": "arrange: \(count) × \(app)", "risk": "spoken"], options: [.sortedKeys]) {
            ArisAgentRunner.writeAudit(String(decoding: line, as: UTF8.self), key: "local")
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let failure = ArisArrange.run(commands, tools: ArisAgentRunner.toolsPath, environment: ArisAgentRunner.environment())
            // The change goes in the activity log (not undoable), so "방금 한 거 되돌려" never reaches past it (QA BUG-18).
            if failure == nil { logLocalChange(kind: "arrange", summary: "창 배치: \(app) \(count)개", id: nil, level: nil) }
            let body = (try? JSONSerialization.data(withJSONObject: failure.map { ["error": $0] } ?? [:])) ?? Data("{}".utf8)
            queue.async { respond(connection, failure == nil ? "200 OK" : "500 Internal Server Error", body) }
        }
    case "/activity-log":
        // A change the notch app made itself (a to-do, the timer, the volume), logged so undo takes the latest (QA BUG-18).
        guard isAppItself(object, on: connection, question: "activity-log") else { return }
        guard let kind = object["kind"] as? String, let summary = object["summary"] as? String,
              ArisActivityBridge.localLogArguments(kind: kind, summary: summary, id: object["id"] as? String, level: object["level"] as? Int,
                                                   due: object["due"] as? Double, timed: object["timed"] as? Bool ?? false) != nil else {
            return respond(connection, "400 Bad Request", Data())
        }
        DispatchQueue.global(qos: .utility).async {
            logLocalChange(kind: kind, summary: summary, id: object["id"] as? String, level: object["level"] as? Int,
                           due: object["due"] as? Double, timed: object["timed"] as? Bool ?? false)
            queue.async { respond(connection, "200 OK", Data("{}".utf8)) }
        }
    case "/undo-folder":
        // Which protected folder (Desktop, Documents, Downloads) an undo touches, read from the log alone (no folder is
        // opened): the app names it while macOS may be asking aris-agent for it (QA BUG-17).
        guard isAppItself(object, on: connection, question: "undo-folder") else { return }
        let folder = ArisActivityBridge.folder(ofEntry: object["id"] as? String)
        respond(connection, "200 OK", (try? JSONSerialization.data(withJSONObject: folder.map { ["folder": $0] } ?? [:])) ?? Data("{}".utf8))
    case "/activity", "/undo":
        let undoing = request.path == "/undo"
        if !undoing { guard isAppItself(object, on: connection, question: "activity") else { return } }
        let arguments: [String]?
        let undoGrant: UUID?
        if undoing {
            // As /confirm: only the Aris app itself undoes (any token holder could otherwise), and a yes only for the card
            // the agent's 409 made, echoed exactly, once.
            let pid = (object["pid"] as? Int).flatMap { Int32(exactly: $0) }, started = object["started"] as? Double
            if let failure = ArisPeer.failure(pid: pid, started: started, remotePort: ArisTeammateDesk.remotePort(of: connection),
                                              agentPort: port.rawValue, requesterPort: nil) {
                ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(failure.rawValue))", "question": "undo"]), key: "undo")
                return respond(connection, "403 Forbidden", Data("{}".utf8))
            }
            if object["confirmed"] as? Bool == true {
                let yes = pendingUndos.consuming(id: object["id"] as? String, summary: object["summary"] as? String, at: Date())
                pendingUndos = yes.rest
                guard yes.allowed else {
                    ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (the card shown isn't the card made)", "question": "undo"]),
                                               key: "undo")
                    return respond(connection, "403 Forbidden", Data("{}".utf8))
                }
            }
            arguments = ArisActivityBridge.undoArguments(id: object["id"] as? String, confirmed: object["confirmed"] as? Bool == true)
            // The app asked for this undo: when it is a to-do's (a reopen or a removal by id), that one write may reach
            // its route. Any other undo mints nothing, and a grant the run didn't use goes when it returns (review 3, L4).
            undoGrant = arguments != nil && ArisActivityBridge.undoWritesTodo(ofEntry: object["id"] as? String) ? ArisActionGrants.shared.mintUndo() : nil
        } else {
            arguments = ArisActivityBridge.activityArguments(today: object["today"] as? Bool == true)
            undoGrant = nil
        }
        guard let arguments else { return respond(connection, "400 Bad Request", Data()) }
        DispatchQueue.global(qos: .userInitiated).async {
            // An undo may wait on macOS's folder prompt (QA BUG-17): it gets a minute, the app a little longer.
            let result = ArisActivityBridge.run(tools: ArisAgentRunner.toolsPath, arguments: arguments, environment: ArisAgentRunner.environment(job: "Aris", worker: "user"),
                                                timeout: undoing ? ArisActivityBridge.undoTimeout : 20)
            ArisActionGrants.shared.dropUndo(undoGrant)
            if undoing, let result {
                let line = ["action": "undo: \(arguments.dropFirst().joined(separator: " "))", "risk": "spoken", "exit": String(result.status)]
                if let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) {
                    ArisAgentRunner.writeAudit(String(decoding: data, as: UTF8.self), key: "app")
                }
            }
            queue.async {
                guard let result else { return respond(connection, "500 Internal Server Error", Data(#"{"error":"\#(ArisActivityBridge.noAnswer)"}"#.utf8)) }
                if undoing {
                    let reply = ArisActivityBridge.undoReply(status: result.status, out: result.out, err: result.err)
                    // The card the app will show: a yes must come back with exactly this summary.
                    if reply.code == 409 { pendingUndos = pendingUndos.issuing(replyBody: reply.body, at: Date()) }
                    let line = reply.code == 200 ? "200 OK" : reply.code == 409 ? "409 Conflict" : "500 Internal Server Error"
                    respond(connection, line, Data(reply.body.utf8))
                } else {
                    let valid = result.status == 0 && (try? JSONSerialization.jsonObject(with: Data(result.out.utf8))) != nil
                    // Rows the automatic check let run come with "checked": true (ArisAutoMarks: the "확인함" mark).
                    respond(connection, valid ? "200 OK" : "500 Internal Server Error",
                            valid ? ArisAutoMarks.shared.annotated(Data(result.out.utf8), log: ArisAutoMarks.logRows()) : Data("{}".utf8))
                }
            }
        }
    case "/inbox":
        guard isAppItself(object, on: connection, question: "inbox") else { return }
        let file = ArisInbox.file(home: FileManager.default.homeDirectoryForCurrentUser.path)
        switch object["op"] as? String {
        case "fetch":
            respond(connection, "200 OK", ArisInbox.fetchBody(ArisInbox.load(file: file)))
        case "ack":
            guard let raw = object["ids"] as? [String], raw.count <= ArisInbox.limit else { return respond(connection, "400 Bad Request", Data()) }
            let ids = raw.compactMap(UUID.init(uuidString:))
            guard ids.count == raw.count else { return respond(connection, "400 Bad Request", Data()) }
            let removed = ArisInbox.ack(Set(ids), file: file)
            respond(connection, "200 OK", Data(#"{"removed":\#(removed)}"#.utf8))
        default:
            respond(connection, "400 Bad Request", Data())
        }
    case "/todos":
        guard isAppItself(object, on: connection, question: "todos") else { return }
        let op = object["op"] as? String ?? "list"
        guard ["list", "hide", "finish"].contains(op) else { return respond(connection, "400 Bad Request", Data()) }
        ArisTodoStore.handle(op: op, text: (object["text"] as? String).map { String($0.prefix(ArisTodoList.textLimit)) },
                             id: object["id"] as? String) { body in
            queue.async { respond(connection, "200 OK", body) }
        }
    case "/brief":
        guard isAppItself(object, on: connection, question: "brief") else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            // Whole, never cut at the look's 4,000 characters (many deadlines run past it).
            let values = ArisLook.cardValues(ArisAgentRunner.toolsPath, ["brief"], ArisAgentRunner.environment(), timeout: 20)
            queue.async { respond(connection, values != nil ? "200 OK" : "500 Internal Server Error", values ?? Data("{}".utf8)) }
        }
    case "/dayend":
        // Tomorrow's schedule runs for the notch's day-end summary (ArisDayEndRoute): titles and times, read only.
        guard isAppItself(object, on: connection, question: "dayend") else { return }
        let runs = ArisDayEndRoute.answer(object, home: FileManager.default.homeDirectoryForCurrentUser.path)
        respond(connection, runs == nil ? "400 Bad Request" : "200 OK", runs ?? Data("{}".utf8))
    case "/weather":
        // The answer card's values (ArisWidget): read here, never taken from the brain's words.
        guard isAppItself(object, on: connection, question: "weather") else { return }
        // A place that isn't one gets no weather, never home's.
        guard let arguments = ArisWidgetPick.weatherArguments(request: object) else {
            return respond(connection, "400 Bad Request", Data("{}".utf8))
        }
        respondWithCard(connection, arguments: arguments, timeout: 15)
    case "/stock":
        // The stock card's values (ArisWidget): Yahoo's chart through aris-tools, never the brain's numbers.
        guard isAppItself(object, on: connection, question: "stock") else { return }
        guard let arguments = ArisWidgetPick.stockArguments(request: object) else { return respond(connection, "400 Bad Request", Data("{}".utf8)) }
        respondWithCard(connection, arguments: arguments, timeout: 20)
    case "/currency":
        // The currency card's values: the pair's own quote through aris-tools, never the brain's numbers.
        guard isAppItself(object, on: connection, question: "currency") else { return }
        guard let arguments = ArisCurrencyRoute.arguments(request: object) else { return respond(connection, "400 Bad Request", Data("{}".utf8)) }
        respondWithCard(connection, arguments: arguments, timeout: 25)
    case "/maps":
        // The map card's values: MapKit's place and ETAs through aris-tools (nothing opens).
        guard isAppItself(object, on: connection, question: "maps") else { return }
        guard let arguments = ArisWidgetPick.mapsArguments(request: object) else { return respond(connection, "400 Bad Request", Data("{}".utf8)) }
        respondWithCard(connection, arguments: arguments, timeout: 40)
    case "/look":
        guard isAppItself(object, on: connection, question: "look") else { return }
        // Its own queue: reading a window can wait seconds on aris-tools, which must not hold up /paste and /insert on main.
        lookQueue.async {
            // The app that asks is known (isAppItself checked its pid): with Aris itself in front, the look reads the app under it.
            // `front`: the app Aris says he was in when he asked (Aris's own NSWorkspace is current; this process's is
            // not: second upgrade run, bug 1).
            let look = ArisLook.gather(tools: ArisAgentRunner.toolsPath, environment: ArisAgentRunner.environment(),
                                       aris: (object["pid"] as? Int).flatMap { Int32(exactly: $0) },
                                       told: (object["front"] as? Int).flatMap { Int32(exactly: $0) })
            let body: [String: Any] = ["context": look.context, "selected": look.selection != nil, "editable": look.editable, "confirmed": look.confirmed,
                                       "unread": look.unread ?? "", "unselected": look.unselected ?? "", "needs": look.needs]
            let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
            queue.async { respond(connection, "200 OK", data) }
        }
    case "/paste":
        guard isAppItself(object, on: connection, question: "paste") else { return }
        // The clipboard history's "paste": the app set the clipboard; only ⌘V is pressed here.
        DispatchQueue.main.async {
            let failure = ArisInsert.pressPaste()
            let body = (try? JSONSerialization.data(withJSONObject: failure.map(ArisInsertRefusal.reply) ?? [:])) ?? Data("{}".utf8)
            queue.async { respond(connection, failure == nil ? "200 OK" : "500 Internal Server Error", body) }
        }
    case "/insert":
        guard isAppItself(object, on: connection, question: "insert") else { return }
        guard let raw = object["text"] as? String, let text = ArisInsert.text(from: raw) else {
            return respond(connection, "400 Bad Request", Data())
        }
        // What was typed stays private: only how much.
        ArisAgentRunner.writeAudit("{\"action\":\"insert: \(text.count) characters\",\"risk\":\"dictated\"}", key: "local")
        let learn = object["learn"] as? Bool ?? false
        DispatchQueue.main.async {
            ArisInsert.paste(text, learn: learn) { pasted in
                let reply: [String: Any] = pasted.failure.map(ArisInsertRefusal.reply) ?? ["confirmed": pasted.confirmed]
                let body = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{}".utf8)
                queue.async { respond(connection, pasted.failure == nil ? "200 OK" : "500 Internal Server Error", body) }
            }
        }
    case _ where ArisDictationRoutes.paths.contains(request.path):
        guard isAppItself(object, on: connection, question: "insert") else { return }
        ArisDictationRoutes.handle(request.path, object, on: connection)
    case "/usage":
        DispatchQueue.global(qos: .utility).async {
            let body = ArisUsageFetch.report().encoded()
            queue.async { respond(connection, "200 OK", body) }
        }
    case "/teammate":
        ArisTeammateDesk.shared.handle(object, on: connection)
    case "/teammates":
        // As /confirm: only the Aris app itself reads or changes the list (a model's shell holds the token too).
        let pid = (object["pid"] as? Int).flatMap { Int32(exactly: $0) }, started = object["started"] as? Double
        let failure = ArisPeer.failure(pid: pid, started: started, remotePort: ArisTeammateDesk.remotePort(of: connection),
                                       agentPort: port.rawValue, requesterPort: nil)
        if let failure {
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(failure.rawValue))", "question": "teammates"]), key: "teammates")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if let op = object["op"] as? String, ArisTeamExtrasRoute.ops.contains(op) {
            guard failure == nil else { return respond(connection, "403 Forbidden", Data("{}".utf8)) }
            // Off the server queue: a login opens a terminal (osascript may wait on Automation), the brains check looks on disk.
            DispatchQueue.global(qos: .userInitiated).async {
                let reply = ArisTeamExtrasRoute.handle(object, world: ArisTeamExtrasRoute.live(home: home))
                if op != "brains" && op != "notes" && op != "knowhow" {
                    ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "\(op) (\(reply.status))", "question": "teammates"]), key: "teammates")
                }
                queue.async {
                    let line = [200: "200 OK", 400: "400 Bad Request", 404: "404 Not Found"][reply.status] ?? "500 Internal Server Error"
                    respond(connection, line, reply.body)
                }
            }
            return
        }
        let file = ArisTeammateStore.file(home: home)
        let reply = ArisTeammateRoute.handle(object, fromApp: failure == nil, load: { ArisTeammateStore.load(file: file) },
                                             save: { try ArisTeammateStore.save($0, file: file) },
                                             removed: { ArisNotesStore.removeTeammate(ids: $0, home: home) })
        let line = [200: "200 OK", 400: "400 Bad Request", 403: "403 Forbidden"][reply.status] ?? "500 Internal Server Error"
        respond(connection, line, reply.body)
    case "/data":
        guard isAppItself(object, on: connection, question: "data") else { return }
        // Uninstall may put only the calling app's own bundle in the Trash: its pid was just verified (ArisPeer).
        let appBundle = ArisDataRoute.appBundle(pid: object["pid"])
        var effects = ArisDataRoute.Effects.live { line in
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["action": line, "risk": "settings"]), key: "data")
        }
        // Uninstall stops the skills setup before its folder goes (security review M5).
        effects.stopSkills = {
            let done = DispatchSemaphore(value: 0)
            ArisSkills.live.deps.setup.remove { done.signal() }
            _ = done.wait(timeout: .now() + 30)
        }
        // Off the server queue: reading and redacting logs, or an uninstall's file work, must not hold up other routes.
        DispatchQueue.global(qos: .userInitiated).async {
            let reply = ArisDataRoute.handle(object, places: ArisDataRoute.Places(home: FileManager.default.homeDirectoryForCurrentUser),
                                             appBundle: appBundle, effects: effects)
            queue.async { respond(connection, reply.status == 200 ? "200 OK" : "400 Bad Request", reply.body) }
        }
    case "/memory":
        // The settings 기억 page: only the Aris app itself (ArisPeer). Off the server queue (SQLite).
        guard isAppItself(object, on: connection, question: "memory") else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let reply = ArisMemoryRoute.handle(object, store: ArisMemoryCurator.live.store)
            ArisMemoryCurator.live.refresh()
            ArisWorkDesk.live.refresh()
            if let line = reply.audit { ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["action": line, "risk": "settings"]), key: "memory") }
            let status = reply.status == 200 ? "200 OK" : reply.status == 400 ? "400 Bad Request" : "500 Internal Server Error"
            queue.async { respond(connection, status, reply.body) }
        }
    case "/log":
        guard let turn = object["turn"] as? [String: Any] else { return respond(connection, "400 Bad Request", Data()) }
        ArisTurnLog.append(turn, in: ArisAgentRunner.directory)
        respond(connection, "200 OK", Data("{}".utf8))
    case "/health":
        // Which process answers here: the app asks before a question and again when its stream ends with no last
        // line, to tell a helper that went away (another process now, or none) from an AI that did not answer.
        let own = ProcessInfo.processInfo.processIdentifier
        let who: [String: Any] = ["pid": Int(own), "started": ArisProcessStart.of(pid: own) ?? 0]
        respond(connection, "200 OK", (try? JSONSerialization.data(withJSONObject: who)) ?? Data("{}".utf8))
    default:
        respond(connection, "404 Not Found", Data())
    }
}

/// Where /look reads the screen (ArisLook.gather: AX, then aris-tools), off the main queue the key presses use.
let lookQueue = DispatchQueue(label: "com.lumenjsn.aris.agent.look", qos: .userInitiated)

/// A connection that has sent no complete request by then is closed (a client that connects and goes quiet).
let requestIdleLimit: TimeInterval = 60

/// One request's bytes as they arrive, appended in place (a 24 MiB /ask is not copied once per piece). Only touched on `queue`.
final class RequestBuffer: @unchecked Sendable {
    var data = Data()
    /// The request head and body arrived (or the connection was answered): the idle limit no longer applies.
    var complete = false
    /// The agent's token, read once per connection: only a head that carries it gets the 24 MiB /ask limit.
    lazy var limit = HTTPRequestParser.agentLimit(token: ClaudeHookToken.load())
}

/// Whether the caller is the Aris app itself (ArisPeer: any token holder, a Claude Code session included, could
/// otherwise cancel jobs, read or revoke standing permissions, read the activity log or take the inbox). When it isn't,
/// the 403 is sent and the refusal written to actions.log.
/// An answer card's values: aris-tools' --json reply when it is a JSON object, `{}` with a 500 otherwise.
func respondWithCard(_ connection: NWConnection, arguments: [String], timeout: TimeInterval) {
    DispatchQueue.global(qos: .userInitiated).async {
        // Whole, never cut to the look's limit (a long route's card is longer: QA BUG-2).
        let values = ArisLook.cardValues(ArisAgentRunner.toolsPath, arguments, ArisAgentRunner.environment(), timeout: timeout)
        queue.async { respond(connection, values != nil ? "200 OK" : "500 Internal Server Error", values ?? Data("{}".utf8)) }
    }
}

func isAppItself(_ object: [String: Any], on connection: NWConnection, question: String) -> Bool {
    let pid = (object["pid"] as? Int).flatMap { Int32(exactly: $0) }, started = object["started"] as? Double
    guard let failure = ArisPeer.failure(pid: pid, started: started, remotePort: ArisTeammateDesk.remotePort(of: connection),
                                         agentPort: port.rawValue, requesterPort: nil) else { return true }
    ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(failure.rawValue))", "question": question]), key: question)
    respond(connection, "403 Forbidden", Data("{}".utf8))
    return false
}

func read(_ connection: NWConnection, buffer: RequestBuffer = RequestBuffer(), started: Bool = false) {
    if !started {
        queue.asyncAfter(deadline: .now() + requestIdleLimit) {
            guard !buffer.complete else { return }
            FileHandle.standardError.write(Data("aris-agent: a connection sent no request in \(Int(requestIdleLimit)) s; closed\n".utf8))
            connection.cancel()
        }
    }
    connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { data, _, isComplete, error in
        if error != nil { return connection.cancel() }
        if let data { buffer.data.append(data) }
        // The head is read first: a body over its request's limit (24 MiB for POST /ask with the token, 1 MiB else)
        // is refused before it arrives.
        switch HTTPRequestParser.parse(buffer.data, limit: buffer.limit) {
        case .complete(let request):
            buffer.data = Data()
            buffer.complete = true
            handle(request, on: connection)
        case .invalid:
            buffer.data = Data()
            buffer.complete = true
            respond(connection, "400 Bad Request", Data())
        case .incomplete: isComplete ? connection.cancel() : read(connection, buffer: buffer, started: true)
        }
    }
}

/// The <teammates> block for main Aris: Claude Code (the one teammate that can be launched so far), under the name the user
/// gave it, and whether this request speaks to it by name.
func teammatesBlock(for text: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    // Every teammate the user has (Claude Code always among them; ArisTeammate.list), each with its role.
    let team = ArisTeammateStore.load(file: ArisTeammateStore.file(home: home))
    let addressed = ArisTeamRouting.addressee(in: text, teammates: team)
    // The teammate whose 언제 부를까요 fits these words best (the 팀원 page's test line shows the same): a hint, the brain decides.
    let fits = addressed == nil ? ArisTeamRouting.bestMatch(text, teammates: team) : nil
    return ArisAgentPrompt.teammates(team, home: home, addressed: addressed)
        + (fits.map { "\nOf the teammates, \"\($0.id)\" (\($0.name)) fits this request's words best, if it is work to hand out." } ?? "")
}

// External-service cards (ArisMCPCards) write their answers to actions.log.
ArisMCPCards.shared.audit = { ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON($0), key: "mcp") }

// A prompt names GPT as the one to ask only on a Mac where Codex is installed (QA F1).
ArisAgentPrompt.gptInstalled = { ArisReadJudge.executable(.codex) != nil }

// The sealed Claude's working folders an earlier run left (each is removed with its process).
ArisSealedScratch.sweep()

// Claude Code prompt files a day old or more (their sessions read them long ago).
ArisTeammateLauncher.sweep(ArisTeammateLauncher.launchFolder(home: FileManager.default.homeDirectoryForCurrentUser.path), now: Date())
// The same from before the launch files had a folder of their own.
ArisTeammateLauncher.sweep(ArisTeammateLauncher.workFolder(home: FileManager.default.homeDirectoryForCurrentUser.path), now: Date())
// No teammate's brain outlives the agent that started it: their job files go.
ArisTeammateJobFile.sweep(home: FileManager.default.homeDirectoryForCurrentUser.path)

// Scheduled jobs (ArisScheduler): what the last launch left is settled, then they're checked every 30 s.
ArisScheduler.shared.start()

// The user's skills (ArisSkills): the folder is looked at now and every minute; new or changed skills are checked.
ArisSkills.live.watch()

// Held refusal counts reach actions.log before the process goes: at a normal exit, and on launchd's SIGTERM (caught
// with a handler, never SIG_IGN, which children would inherit: ArisProcessEnd.catchTermination).
atexit { ArisAgentRunner.flushAudit() }
ArisProcessEnd.catchTermination(on: queue) {
    ArisAgentRunner.flushAudit()
    // The external services' programs end with the agent.
    ArisMCPHub.shared.disconnectAll()
    exit(0)
}

// Peekaboo's snapshot folders a run left behind (it stopped before its conversation could forget them): other apps'
// windows, element by element. The agent holds none yet (I12).
DispatchQueue.global(qos: .utility).async { ArisPeekabooSnapshots.clean() }

let parameters = NWParameters.tcp
// Local processes only: never reachable from the network.
parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
do {
    let listener = try NWListener(using: parameters)
    listener.newConnectionHandler = { connection in
        connection.start(queue: queue)
        read(connection)
    }
    listener.stateUpdateHandler = { state in
        if case .failed(let error) = state {
            FileHandle.standardError.write(Data("aris-agent: listener failed: \(error)\(ArisPeer.holderNote(ofPort: port.rawValue))\n".utf8))
            exitAfterPause()
        }
    }
    listener.start(queue: queue)
} catch {
    FileHandle.standardError.write(Data("aris-agent: can't listen on \(port): \(error)\(ArisPeer.holderNote(ofPort: port.rawValue))\n".utf8))
    exitAfterPause()
}

/// launchd starts the agent again as soon as it exits (KeepAlive): a pause first keeps a port that another process
/// holds from turning into a restart every few seconds, each with a log line.
func exitAfterPause() -> Never {
    sleep(30)
    exit(1)
}
// The main run loop, not dispatchMain(): it runs the main queue as before, and is also where the pasteboard asks for a
// lazy paste's data (ArisPasteSession), so a paste never holds the main thread.
CFRunLoopRun()

/// Logs a change of the notch app's (or the agent's own arrange) through aris-tools, the log's one writer; best effort.
func logLocalChange(kind: String, summary: String, id: String?, level: Int?, due: Double? = nil, timed: Bool = false) {
    guard let arguments = ArisActivityBridge.localLogArguments(kind: kind, summary: summary, id: id, level: level, due: due, timed: timed) else { return }
    var environment = ArisAgentRunner.environment(job: "Aris", worker: "user")
    environment[ArisActivityBridge.localLogKey] = "1"
    _ = ArisActivityBridge.run(tools: ArisAgentRunner.toolsPath, arguments: arguments, environment: environment, timeout: 10)
}
