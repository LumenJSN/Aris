//
//  ArisMessageRequest.swift
//  aris-tools
//
//  How `aris-tools message <to> <text…>` goes: sent here only with the agent's one-shot pass for exactly it
//  (ArisMessagePass: the user's yes to Codex's or the API brain's card, their changed card, the agent's own send), or handed to
//  the agent (POST /message-tool) from a Claude, which has no gate of its own: the agent decides it (ArisMessageGate)
//  and sends it on the user's yes. The open Claude is told by its turn-gate folder (ARIS_TURN_STATE, set for it alone), the
//  sealed one by ArisSealedTools.messageKey; inside either, without the turn's credential, nothing is sent (fail
//  closed). Pure, so the tests run it.
//
//  The same hand-off for every other write, send or thing opened (ArisHandOff: a to-do, an event, a note, the Trash, a
//  link, keys, a schedule, an undo…): inside a Claude's process aris-tools never runs one itself; it goes to the agent
//  (POST /action-tool), which judges it as Codex's same command and asks the user on a card when that says to (audit gate-2).
//

import Foundation

enum ArisMessageRouting: Equatable {
    /// Send it here (the gate that let it run already asked).
    case direct
    /// The JSON body for POST /message-tool.
    case agent(to: String, text: String, turn: String)
    case refused(String)
}

/// `consume`: the agent's one-shot pass for exactly this message (ArisMessagePass); without one nothing is sent here.
func messageRouting(_ args: [String], environment: [String: String],
                    consume: (String, String) -> Bool = { ArisMessagePass.consume(to: $0, text: $1) }) -> ArisMessageRouting {
    guard args.count >= 2 else { return .refused("usage: message <name|number|email> <text>") }
    guard environment[ArisTurnGate.stateKey] != nil || environment[ArisSealedTools.messageKey] == "1" else {
        return consume(args[0], args.dropFirst().joined(separator: " ")) ? .direct
            : .refused("Refused: a message goes out only through Aris's gate (the user's card). Don't try another way.")
    }
    guard let path = environment["ARIS_MCP_TURN_FILE"], path.hasPrefix("/"), let turn = readCredential(path), !turn.isEmpty else {
        return .refused("aris-tools message works only inside an Aris turn")
    }
    return .agent(to: args[0], text: args.dropFirst().joined(separator: " "), turn: turn)
}

enum ArisHandOffRouting: Equatable {
    /// Run it here: not a Claude's process (Codex and the API brain passed their own gate first, the agent runs its
    /// own), or not a call that is handed off (a read, a timer).
    case direct
    /// The JSON body for POST /action-tool: the words as given, and the turn's credential.
    case agent(words: [String], turn: String)
    case refused(String)
}

/// How `aris-tools <args…>` goes when it may be one of the handed-off calls. Inside a Claude's process (the open one is
/// told by its turn-gate folder, the sealed one by ArisHandOff.sealedKey) such a call is never run here: it goes to the
/// agent with the turn's credential, and without one, or with words that aren't one plain call, nothing happens (fail
/// closed).
func handOffRouting(_ args: [String], environment: [String: String]) -> ArisHandOffRouting {
    guard environment[ArisTurnGate.stateKey] != nil || environment[ArisHandOff.sealedKey] == "1", ArisHandOff.names(args) else { return .direct }
    guard ArisHandOff.isWrite(args) else {
        return .refused("Refused: give \(args.first ?? "it") as one plain command (no control characters or line breaks; \\n for a new line in a note).")
    }
    guard let path = environment["ARIS_MCP_TURN_FILE"], path.hasPrefix("/"), let turn = readCredential(path), !turn.isEmpty else {
        return .refused("aris-tools \(args.first ?? "this") works only inside an Aris turn")
    }
    return .agent(words: args, turn: turn)
}
