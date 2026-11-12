//
//  ArisController+SaveAnswer.swift
//  Aris
//
//  "방금 답을 … 파일로 저장해 줘": the user's card (where, and the first lines), then the agent writes it (POST /save-text,
//  ArisSaveText) and the reply says what is on disk (QA BUG-20b: the brain answered it through TextEdit's Save panel).
//

import Foundation
import SwiftUI

extension ArisController {
    func saveLastAnswer(_ request: ArisSaveAnswer, heard: String, korean: Bool) async -> String {
        // "이거" is the last answer only while it is fresh; otherwise it could as well be the screen, so Aris asks.
        let fresh = lastAnswer.flatMap { answer -> String? in
            if request.pronoun { return Date().timeIntervalSince(answer.at) <= ArisSaveAnswer.pronounFresh ? answer.text : nil }
            return ArisSpeakable.stillReadable(since: answer.at) ? answer.text : nil
        }
        if request.pronoun, fresh == nil {
            return await sayLocal(korean ? "무엇을 저장할까요? 방금 답이 없어서요. 화면의 내용이면 그렇게 말해 주세요." : "What should I save? There's no recent answer; if you mean what's on screen, say so.", heard: heard)
        }
        guard let text = fresh?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return await sayLocal(korean ? "저장할 방금 답이 없어요." : "There's no answer to save.", heard: heard)
        }
        // An answer from a conversation that read outside text says so on the card.
        let card = request.note ? ArisSaveAnswer.noteCard(text: text, outside: outsideConversation, korean: korean)
            : ArisSaveAnswer.card(path: request.path, text: text, outside: outsideConversation, korean: korean)
        let allow = await askUser(ArisConfirmation(id: "save-answer-" + UUID().uuidString, title: card.title, detail: card.detail))
        withAnimation(ArisGlass.resize) { session = session.answered() }
        guard allow else {
            let reply = await saidNotDone(korean: korean, declined: ArisSaveAnswer.declinedLine(korean: korean))
            recordTurn(heard: heard, reply: reply)
            return reply
        }
        if request.note {
            // The app's own reasons (the agent didn't answer, or gave none) are said in the request's language.
            let failure = (await ArisAgentClient.saveNote(text: text)).map { ArisSaveAnswer.noteProblem($0, korean: korean) }
            return await sayLocal(Self.noteReply(failure, korean: korean), heard: heard)
        }
        let saved = await ArisAgentClient.saveText(path: request.path, text: text)
        return await sayLocal(Self.saveReply(saved, path: request.path, korean: korean), heard: heard)
    }

    /// The reply from what the agent did on disk, never from what was meant.
    static func saveReply(_ saved: ArisSavedText?, path: String, korean: Bool) -> String {
        let place = ArisSaveAnswer.shown(path)
        guard let saved else { return korean ? "저장하지 못했어요. Aris 에이전트가 답하지 않았어요." : "It wasn't saved: Aris's agent didn't answer." }
        if saved.saved { return korean ? "방금 답을 \(place)에 저장했어요." : "Saved the last answer to \(place)." }
        let why: String
        switch saved.why {
        case "exists": why = korean ? "같은 이름의 파일이 이미 있어서 덮어쓰지 않았어요" : "a file with that name is already there, and it isn't replaced"
        case "outside": why = korean ? "홈 폴더 안에만 저장해요" : "Aris saves only inside the home folder"
        case "hidden", "protected": why = korean ? "그 폴더에는 저장하지 않아요" : "Aris doesn't save in that folder"
        case "kind": why = korean ? ".txt나 .md 파일로만 저장해요" : "only as a .txt or .md file"
        case "empty": why = korean ? "답이 비었거나 너무 길어요" : "the answer is empty or too long"
        default: why = korean ? "파일을 쓰거나 다시 읽지 못했어요" : "the file couldn't be written or read back"
        }
        return korean ? "저장하지 못했어요: \(why)." : "It wasn't saved: \(why)."
    }

    /// The note's reply from what the agent did (nil: the note was made).
    static func noteReply(_ failure: String?, korean: Bool) -> String {
        guard let failure else { return korean ? "방금 답을 메모 앱에 새 메모로 저장했어요." : "Saved the last answer as a new note in Notes." }
        return korean ? "메모에 저장하지 못했어요: \(failure)" : "It wasn't saved to Notes: \(failure)"
    }

    private func sayLocal(_ reply: String, heard: String) async -> String {
        session = session.answering(reply)
        stats?.firstSound(at: .now)
        recordTurn(heard: heard, reply: reply)
        await speak { await self.speaker.speak(reply) }
        return reply
    }
}

/// What POST /save-text answered.
struct ArisSavedText: Equatable {
    let saved: Bool
    let path: String?
    let why: String?
}

extension ArisAgentClient {
    private static let saveURL = URL(string: "http://127.0.0.1:23351/save-text")!

    static func saveText(path: String, text: String) async -> ArisSavedText? {
        guard let data = await agentCall(["path": path, "text": text], url: saveURL, timeout: 10),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let saved = body["saved"] as? Bool else { return nil }
        return ArisSavedText(saved: saved, path: body["path"] as? String, why: body["why"] as? String)
    }

    /// The answer as a new Apple Notes note (POST /save-text with "to": "note"): nil when it was made, else why not.
    static func saveNote(text: String) async -> String? {
        guard let data = await agentCall(["to": "note", "text": text], url: saveURL, timeout: 40),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ArisSaveAnswer.noAnswer(korean: true) }
        if body["saved"] as? Bool == true { return nil }
        return body["why"] as? String ?? ArisSaveAnswer.notMade(korean: true)
    }
}
