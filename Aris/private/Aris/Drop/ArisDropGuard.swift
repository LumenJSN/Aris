//
//  ArisDropGuard.swift
//  Aris
//
//  The files Aris never reads on its own, for a file dropped on it: one whose name looks like a key, token or password
//  file, and one in a protected place (Aris's own folder, keys, startup files). These are the file tools' rules
//  (aris-tools' ArisFiles.looksSecret and ArisProtectedPlaces), kept here in the app's words because the sandboxed app
//  is not built with aris-tools; the tests hold the two to each other name by name. And where aris-tools makes new
//  files (convert, merge): the home folder outside those places, or an external disk. Foundation only, so it is tested.
//

import Foundation

enum ArisDropGuard {
    /// Why a dropped file isn't read up front.
    enum Hold: Equatable {
        /// Its name looks like a key, token or password file: read only once the user says so.
        case secretName
        /// It is in a place Aris never touches: never read.
        case protectedPlace
    }

    /// Links are followed by the caller first, so a link into a protected place is judged as that place.
    static func hold(_ path: String, home: String, isKeynote: (String) -> Bool) -> Hold? {
        if inProtectedPlace(path, home: home) { return .protectedPlace }
        return looksSecret(path, isKeynote: isKeynote) ? .secretName : nil
    }

    // MARK: - Secrets, by name (ArisFiles.looksSecret)

    private static let keyFormats: Set = ["pem", "p12", "pfx", "p8", "ppk", "jks", "keystore", "kdbx", "env", "gpg", "asc", "ovpn", "mobileprovision"]
    private static let keyNames: Set = ["authorized_keys", "known_hosts", "htpasswd", "netrc"]
    private static let keyPrefixes = ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519"]
    /// Documents, pictures, recordings and decks: read by people, never a credential store by their name.
    private static let rendered: Set = ["pdf", "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "tif", "bmp", "svg", "mov", "mp4", "m4v", "m4a",
                                        "mp3", "wav", "aiff", "ppt", "pptx", "epub"]
    private static let secretWords: Set = ["token", "tokens", "secret", "secrets", "password", "passwords", "passwd", "passphrase", "passcode", "passcodes",
                                           "credential", "credentials", "apikey", "apikeys", "privatekey", "암호"]
    private static let secretParts = ["비밀번호", "패스워드", "비번"]
    private static let keyQualifiers: Set = ["api", "private", "secret", "ssh", "access", "auth", "signing", "encryption", "pgp", "gpg", "rsa", "account",
                                             "license", "licence", "recovery", "master", "deploy", "aws", "root", "wallet", "seed"]
    private static let secretStems = ["password", "passwd", "passphrase", "passcode", "token", "secret", "credential"]
    private static let passwordStems = ["password", "passwd", "passphrase", "passcode"]
    private static let storeEndings: Set = ["s", "es", "list", "lists", "file", "files", "db", "store", "vault", "backup", "sheet", "manager"]
    private static let secretPhrases: Set = ["seed phrase", "recovery phrase", "recovery codes", "recoverycodes", "backup codes"]

    /// A name's words: cut at anything that isn't a letter or digit, where a small letter meets a capital (apiKey) and
    /// where letters meet digits (token2), lowercased.
    static func words(_ name: String) -> [String] {
        var words: [String] = [], word = ""
        var previous: Character?
        for character in name {
            defer { previous = character }
            guard character.isLetter || character.isNumber else {
                if !word.isEmpty { words.append(word); word = "" }
                continue
            }
            if let previous, !word.isEmpty, (previous.isLowercase && character.isUppercase) || (previous.isLetter != character.isLetter) {
                words.append(word)
                word = ""
            }
            word.append(character)
        }
        if !word.isEmpty { words.append(word) }
        return words.map { $0.lowercased() }
    }

    /// Whether the file looks like a key or a secret by its name and kind. `isKeynote`: whether a `.key` file is a
    /// Keynote deck (a zip or a package) rather than a private key (text).
    static func looksSecret(_ path: String, isKeynote: (String) -> Bool) -> Bool {
        let whole = (path as NSString).lastPathComponent
        let name = whole.lowercased(), kind = (name as NSString).pathExtension
        if keyFormats.contains(kind) || keyNames.contains(name) || keyPrefixes.contains(where: name.hasPrefix) { return true }
        if kind == "key" { return !isKeynote(path) }
        if rendered.contains(kind) { return false }
        let base = kind.isEmpty ? whole : (whole as NSString).deletingPathExtension
        if secretParts.contains(where: base.contains) { return true }
        let words = words(base)
        return words.contains(where: secretWords.contains) || hasGluedSecret(words) || hasSecretPhrase(words) || hasCredentialKey(words)
    }

    /// "mypasswords", "authtoken", "passwordlist"; and "key" glued to a word that makes it a credential ("sshkey").
    private static func hasGluedSecret(_ words: [String]) -> Bool {
        words.contains { word in
            if secretStems.contains(where: { word.hasSuffix($0) || word.hasSuffix($0 + "s") }) { return true }
            if passwordStems.contains(where: { word.hasPrefix($0) && storeEndings.contains(String(word.dropFirst($0.count))) }) { return true }
            guard let stem = ["keys", "key"].first(where: word.hasSuffix).map({ String(word.dropLast($0.count)) }), !stem.isEmpty else { return false }
            return keyQualifiers.contains(stem)
        }
    }

    private static func hasSecretPhrase(_ words: [String]) -> Bool {
        let spaced = words.joined(separator: " ")
        return secretPhrases.contains { spaced == $0 || spaced.hasPrefix($0 + " ") || spaced.hasSuffix(" " + $0) || spaced.contains(" " + $0 + " ") }
    }

    /// "key" on its own, or beside a word like api, private or ssh ("answer key" and "key findings" aren't).
    private static func hasCredentialKey(_ words: [String]) -> Bool {
        let said = words.filter { !$0.allSatisfy(\.isNumber) }
        return words.indices.contains { index in
            guard words[index] == "key" || words[index] == "keys" else { return false }
            if said.count == 1 { return true }
            return [index - 1, index + 1].contains { words.indices.contains($0) && keyQualifiers.contains(words[$0]) }
        }
    }

    // MARK: - Protected places (ArisProtectedPlaces)

    /// Relative to the home folder.
    static let protectedPlaces = [
        ".config/aris", ".config/boring-notch", ".ssh", ".gnupg", "Library/LaunchAgents", ".local/bin", "bin",
        ".zshrc", ".zshenv", ".zprofile", ".zlogin", ".bashrc", ".bash_profile", ".bash_login", ".profile",
        ".gitconfig", ".config/git", ".config/fish", ".claude", ".codex", ".gemini",
        // The shell's start-up folders: a file put there runs at the next login (security review M4).
        ".oh-my-zsh", ".zsh", ".config/zsh", ".zshrc.d", ".bashrc.d",
        "Library/Application Support/Aris/Skills", "Library/Application Support/Aris/skills-runtime",
        "Library/Application Support/Aris/computer-runtime", ".peekaboo",
    ]

    /// A path as it is compared: canonical Unicode, case folded as APFS does.
    private static func key(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)
    }

    /// The home folder itself, a path at or under a protected place, or a folder that holds one.
    static func inProtectedPlace(_ path: String, home: String, app: String = Bundle.main.bundlePath) -> Bool {
        let target = key((path as NSString).standardizingPath), root = key((home as NSString).standardizingPath)
        // Aris's own app (ArisProtectedPlaces.inApp): a copy under the home folder (~/Applications) is protected too.
        if app.hasSuffix(".app"), target == key(app) || target.hasPrefix(key(app) + "/") { return true }
        if target == root { return true }
        guard target.hasPrefix(root + "/") else { return false }
        let inside = String(target.dropFirst(root.count + 1))
        return protectedPlaces.map(key).contains { inside == $0 || inside.hasPrefix($0 + "/") || $0.hasPrefix(inside + "/") }
    }

    // MARK: - Where aris-tools makes new files

    /// Where disks the user plugged in are mounted.
    static let disksRoot = "/Volumes"

    /// A file aris-tools may convert or merge: under the home folder outside the protected places, or on an external
    /// disk outside its hidden folders. aris-tools checks again itself (the disk's kind, links): this only keeps a chip
    /// from showing where it is sure to be refused.
    static func convertible(_ path: String, home: String) -> Bool {
        let path = (path as NSString).standardizingPath, home = (home as NSString).standardizingPath
        if path.hasPrefix(home + "/") { return !inProtectedPlace(path, home: home) }
        guard path.hasPrefix(disksRoot + "/") else { return false }
        let parts = path.dropFirst(disksRoot.count + 1).split(separator: "/")
        return parts.count >= 2 && !parts.prefix(2).contains { $0.hasPrefix(".") }
    }
}
