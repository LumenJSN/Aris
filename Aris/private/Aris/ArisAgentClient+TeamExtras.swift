//
//  ArisAgentClient+TeamExtras.swift
//  Aris
//
//  The 팀원 page's other questions to aris-agent (POST /teammates, the app itself only: ArisTeamExtrasRoute): which
//  brains are set up on this Mac, a brain's login in a terminal, a teammate's 기억 and 앱 노하우 (read and delete).
//

import Foundation

extension ArisAgentClient {
    /// Which brains are set up here; nil when the agent didn't answer.
    static func teamBrains() async -> [String: Bool]? { await teamBrainsSaid()?.ready }

    /// Which brains can answer on this Mac, and which are set up but have never answered (an API key whose check
    /// failed: ArisBrainChoice.needsCheck).
    static func teamBrainsSaid() async -> (ready: [String: Bool], unchecked: [String])? {
        guard let (status, data) = await sendTeam(["op": "brains"]), status == 200,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let ready = root["brains"] as? [String: Bool] else { return nil }
        return (ready, root["unchecked"] as? [String] ?? [])
    }

    /// Opens a terminal running `brain`'s own login. False when it couldn't.
    static func loginBrain(_ brain: String) async -> Bool {
        guard let (status, _) = await sendTeam(["op": "login", "brain": brain]) else { return false }
        return status == 200
    }

    /// The owner accepts an AI's program that changed (ArisFix.acceptProgram): the helper writes the new one down.
    static func acceptProgram(_ brain: String) async -> Bool {
        guard let (status, _) = await sendTeam(["op": "acceptProgram", "brain": brain]) else { return false }
        return status == 200
    }

    static func teammateNotes(_ id: String) async -> [ArisNoteRow]? {
        await notes(["op": "notes", "id": id])
    }

    /// Forgets one note of the teammate's (nil: all of them); the notes left.
    static func forgetTeammateNote(_ id: String, note: String?) async -> [ArisNoteRow]? {
        var body: [String: Any] = ["op": "forgetNote", "id": id]
        if let note { body["note"] = note }
        return await notes(body)
    }

    /// Keeps a note learned from outside content (`teammate`: its 기억; nil: 앱 노하우); the notes as they are now.
    static func keepNote(_ note: String, teammate: String?) async -> [ArisNoteRow]? {
        await notes(teammate.map { ["op": "keepNote", "id": $0, "note": note] } ?? ["op": "keepKnowhow", "note": note])
    }

    static func knowhow() async -> [ArisNoteRow]? {
        await notes(["op": "knowhow"])
    }

    static func forgetKnowhow(_ note: String?) async -> [ArisNoteRow]? {
        var body: [String: Any] = ["op": "forgetKnowhow"]
        if let note { body["note"] = note }
        return await notes(body)
    }

    private static func notes(_ body: [String: Any]) async -> [ArisNoteRow]? {
        guard let (status, data) = await sendTeam(body), status == 200 else { return nil }
        return ArisNoteRow.list(from: data)
    }
}
