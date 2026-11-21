//
//  ArisWorldOutbox.swift
//  Aris
//
//  The World a conversation turn takes to the helper (ArisWorldWire), only while the helper says Core 2 is on (its
//  /health answer): the app in front, the app nicknames Aris knows (ArisIntent.appAliases), and the contacts, read only
//  when macOS already granted Aris Contacts (never asked for here: with any other answer the list stays empty). The
//  contacts are read off the main thread at most every ten minutes and kept in memory only.
//

import AppKit
import Contacts
import Foundation

enum ArisWorldOutbox {
    /// The helper's last /health said Core 2 is on (set off the main thread, read before a turn is sent).
    nonisolated(unsafe) private static var core2 = false
    private static let lock = NSLock()

    /// /health's body: whether the helper runs Core 2.
    static func noteHealth(_ data: Data) {
        let on = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["core2"] as? Bool == true
        lock.withLock { core2 = on }
    }

    static var helperRunsCore2: Bool { lock.withLock { core2 } }

    /// The `world` field for a conversation turn; nil while the helper doesn't run Core 2.
    static func field() async -> [String: Any]? {
        guard helperRunsCore2 else { return nil }
        let front = await MainActor.run { ArisWorld.shared.snapshot.frontApp ?? NSWorkspace.shared.frontmostApplication.map(ArisWorld.app) }
        let payload = ArisWorldWire.Payload(frontApp: front?.name, frontBundle: front?.bundleID, contacts: ArisWorldContacts.shared.current(),
                                            apps: ArisWorldWire.apps(fromAliases: ArisIntent.appAliases))
        return ArisWorldWire.encode(payload)
    }
}

/// The address book as names and addresses, only with Contacts already granted.
final class ArisWorldContacts: @unchecked Sendable {
    static let shared = ArisWorldContacts()
    static let freshFor: TimeInterval = 600

    private let lock = NSLock()
    private var kept: [ArisWorldFacts.Contact] = []
    private var readAt: Date?
    private var reading = false

    /// What was read last (empty until the first read); a stale list starts a new read for the next turn.
    func current(now: Date = Date()) -> [ArisWorldFacts.Contact] {
        let (list, due) = lock.withLock { () -> ([ArisWorldFacts.Contact], Bool) in
            let due = !reading && (readAt.map { now.timeIntervalSince($0) > Self.freshFor } ?? true)
            if due { reading = true }
            return (kept, due)
        }
        if due {
            DispatchQueue.global(qos: .utility).async { [self] in
                let read = Self.read()
                lock.withLock {
                    kept = read
                    readAt = Date()
                    reading = false
                }
            }
        }
        return list
    }

    /// Never asks: any answer but "granted" reads nothing.
    static func read() -> [ArisWorldFacts.Contact] {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return [] }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactOrganizationNameKey,
                    CNContactEmailAddressesKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        var contacts: [ArisWorldFacts.Contact] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        try? CNContactStore().enumerateContacts(with: request) { contact, stop in
            let full = [contact.familyName, contact.givenName].filter { !$0.isEmpty }.joined()
            let western = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let name = contact.nickname.isEmpty ? (full.isEmpty ? contact.organizationName : full) : contact.nickname
            guard !name.isEmpty else { return }
            let aliases = Array(Set([full, western, contact.givenName, contact.nickname].filter { !$0.isEmpty && $0 != name })).sorted()
            let addresses = contact.emailAddresses.map { String($0.value) } + contact.phoneNumbers.map { $0.value.stringValue }
            contacts.append(ArisWorldFacts.Contact(name: name, aliases: aliases, addresses: addresses))
            if contacts.count >= ArisWorldWire.mostContacts { stop.pointee = true }
        }
        return contacts
    }
}
