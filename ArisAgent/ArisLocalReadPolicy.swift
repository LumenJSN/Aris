//
//  ArisLocalReadPolicy.swift
//  aris-agent
//
//  The aris-tools commands that read the user's own Mac apps: iMessage, Apple Mail, Apple Notes, Spotlight and an Obsidian
//  vault (ArisTools/ArisLocalReads*). Everything they return was written by other people (a text, a mail, a shared
//  note, a downloaded file's name), so each one is outside text: never on the clean list, never on the sealed list.
//  After one, outbound actions and read-back writes ask, a jobs block is dropped, and nothing is learned. The private
//  ones (other people's words to the user) run only where each read and each later web call passes a gate: Codex's risk
//  gate, the open Claude's turn gate and the sealed Claude's hook (both with the read judge, ArisReadGate), and agy's
//  relay; an ungated process (the open agy) is refused them outright (its deny list, ARIS_UNGATED).
//  Pure, so the tests run it.
//

import Foundation

enum ArisLocalReadPolicy {
    /// Each read command and the only verbs it reads with. Any other verb is not a read (a `mail` send stays asked).
    static let forms: [String: Set<String>] = [
        "messages": ["recent"],
        // `read`: one mail whole; `thread`: its conversation in order (ArisMailStore). `mail reply` is no read: it asks.
        "mail": ["recent", "search", "read", "thread"],
        "notes": ["recent", "search"],
        // `read`: one file's text (a path, or the files on the shelf or selected in Finder: ArisFileText).
        "files": ["find", "read"],
        "obsidian": ["search"],
        // The user's Devin sessions, read only from Devin's own records (ArisDevinRead): what they were asked and answered.
        "devin": ["sessions"],
    ]

    /// The commands whose output is outside text, whatever their verb (a wrong verb taints too: fail closed).
    static var commands: Set<String> { Set(forms.keys) }

    /// Other people's words to the user: only the gated brain may read them.
    static let privateReads = ["messages", "mail", "notes", "obsidian"]

    /// Whether the aris-tools words (after the program) are one of the read forms: a known command and its read verb.
    static func isRead(_ words: [String]) -> Bool {
        guard words.count >= 2, let verbs = forms[words[0]] else { return false }
        return verbs.contains(words[1])
    }

    /// Paths a raw shell read must not reach without asking: the stores these commands read (aris-agent may hold Full
    /// Disk Access for them, and so may every command its AIs run). Lowercased path fragments.
    static let storeFragments = ["/library/messages", "/library/mail", "/group containers/group.com.apple.notes",
                                 "/library/containers/com.apple.mail", "/library/application support/addressbook",
                                 // Peekaboo's snapshot store: other apps' windows, element by element (I12).
                                 "/.peekaboo",
                                 // Devin's records and its sign-in (only `devin sessions` reads them, masked: ArisDevinRead).
                                 "/.local/share/devin"]

    /// The same stores as folders under the home folder, for the brains' Read and read_file denies (I4): only
    /// aris-tools reads them, through its redaction and limits.
    static let storeFolders = ["Library/Messages", "Library/Mail", "Library/Group Containers/group.com.apple.notes",
                               "Library/Containers/com.apple.mail", ".peekaboo", ".local/share/devin"]

    /// Whether aris-agent (and so every command its AIs run) has Full Disk Access, for the settings and onboarding
    /// row: the system TCC database (no one's content) is opened and closed at once, nothing read. Never prompts.
    /// That file opens without Full Disk Access when System Integrity Protection's file protection is off (a VM, a
    /// developer's Mac), and so does every folder only Full Disk Access opens (VM runs 2026-11-18, D6, and 2026-11-19):
    /// then macOS's own decision for Aris is read from that database (`decision`, ArisTCCReading), and what can't be
    /// read is never "allowed". With SIP on (the user's Mac) the open alone decides, as before.
    static func hasDiskAccess(probe: String = ArisTCCReading.systemDatabase, filesProtected: Bool = ArisSystemIntegrity.protectsFiles,
                              decision: () -> Bool? = { ArisTCCReading.allowed(service: ArisTCCReading.diskService, clients: ArisTCCReading.clients,
                                                                               database: ArisTCCReading.systemDatabase) }) -> Bool {
        guard opens(probe, flags: O_RDONLY) == 0 else { return false }
        if filesProtected { return true }
        return decision() ?? false
    }

    /// 0 when `path` opens (closed at once), else the errno.
    private static func opens(_ path: String, flags: Int32) -> Int32 {
        let fd = open(path, flags | O_NONBLOCK)
        guard fd >= 0 else { return errno }
        close(fd)
        return 0
    }

    /// Whether a command line runs one of the private reads (messages, mail, notes, Obsidian), in any segment.
    static func readsPrivate(_ command: String, tools: String) -> Bool {
        (ArisCommandPolicy.segments(command) ?? [command]).contains { piece in
            guard let words = ArisCommandPolicy.words(piece), words.first == tools else { return false }
            let rest = Array(words.dropFirst())
            return isRead(rest) && privateReads.contains(rest[0])
        }
    }

    /// A hands-free conversation turn that read the user's private data (I6) or called a connected service (review I1): its
    /// answer is shown, never spoken; the app says only "화면에 띄워 뒀어요" (ArisAgentReply.shownOnly), and nothing more
    /// streams to the voice.
    static func showsOnly(handsFree: Bool, task: Bool, commands: [String], tools: String) -> Bool {
        handsFree && !task && commands.contains { readsPrivate($0, tools: tools) || callsService($0, tools: tools) }
    }

    /// Whether a command line calls a connected service (`aris-tools mcp call …`), in any segment.
    static func callsService(_ command: String, tools: String) -> Bool {
        (ArisCommandPolicy.segments(command) ?? [command]).contains { piece in
            guard let words = ArisCommandPolicy.words(piece), words.first == tools else { return false }
            return words.dropFirst().first == "mcp" && words.dropFirst(2).first == "call"
        }
    }

    /// I1: a turn whose conversation already took in outside text (on any brain, before a restart or a model switch)
    /// starts marked, so the open Claude's reads and web calls go to the read judge.
    static func marksTurn(untrusted: Bool, outsideConversation: Bool) -> Bool { untrusted || outsideConversation }
}

/// System Integrity Protection, as the kernel has it now.
enum ArisSystemIntegrity {
    /// CSR_ALLOW_UNRESTRICTED_FS: set when SIP's file protection is off.
    private static let unrestrictedFiles: UInt32 = 1 << 1

    /// Its file protection is on (csr_check answers 0 when the thing asked for is allowed, that is, unprotected).
    static var protectsFiles: Bool { csrCheck(unrestrictedFiles) != 0 }
}

@_silgen_name("csr_check")
private func csrCheck(_ mask: UInt32) -> Int32
