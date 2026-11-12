//
//  ArisFiles.swift
//  aris-tools
//
//  "작년 세금 서류 찾아줘", "그 PDF 열어줘": `find "<words>"` asks Spotlight (names and contents) and lists the
//  newest matches in the home folder and iCloud Drive; `open "<path>"` opens one document. The rest of Library, hidden
//  folders and anything that looks like a key or secret never show up, and only documents, images and media open (never
//  an app or a script).
//
//  What "looks like a key or secret" means (audit tools-3: any name with "key" or "token" inside it was dropped, so
//  Keynote decks, "Keyboard shortcuts.pdf", "monkey.png" and "tokenomics.pdf" could never be found or opened):
//  - a key or credential format by its extension (pem, p12, env…), an SSH key by its name, and a `.key` file that is
//    not a Keynote document (a private key is text; a deck is a zip or a package);
//  - a data file (text, JSON, a spreadsheet, no extension…) whose name has a secret word as a whole word: token,
//    secret, password, credential, or "key" on its own or beside a word like api, private or ssh.
//  A PDF, a picture, a recording or a deck is never one by its name: "keynote-token-design.pdf" is a document about
//  tokens, not a token.
//

import Foundation

enum ArisFiles {
    static let shown = 10
    private static let openable: Set = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "md",
                                        "rtf", "csv", "png", "jpg", "jpeg", "heic", "gif", "webp", "mov", "mp4", "m4a", "mp3",
                                        "wav", "hwp", "hwpx", "epub", "tex", "json"]
    /// Documents macOS may keep as a folder (a package): they open like a file.
    private static let packages: Set = ["key", "pages", "numbers"]

    /// iCloud Drive, inside Library; no other app's iCloud folder beside it is listed.
    private static let cloudDrive = "Library/Mobile Documents/com~apple~CloudDocs/"

    /// iCloud Drive's own folder (`files find --in` may search all of it).
    static func cloudDriveFolder(home: String) -> String { home + "/" + cloudDrive.dropLast() }

    /// Whether a found path may be listed: in the home folder or iCloud Drive, not in the rest of Library or a hidden
    /// folder, nothing secret-looking. `isKeynote`: whether a `.key` file is a Keynote document (the tests say).
    static func listable(_ path: String, home: String, isKeynote: (String) -> Bool = isKeynoteDocument) -> Bool {
        inListedPlace(path, home: home) && !looksSecret(path, isKeynote: isKeynote)
    }

    /// The place alone: under the home folder, outside Library (but for iCloud Drive) and every hidden folder.
    static func inListedPlace(_ path: String, home: String) -> Bool {
        guard path.hasPrefix(home + "/") else { return false }
        var inside = path.dropFirst(home.count + 1)
        if inside.hasPrefix(cloudDrive) { inside = inside.dropFirst(cloudDrive.count) } else if inside.hasPrefix("Library/") { return false }
        return !inside.isEmpty && !inside.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    // MARK: - Secrets, by name

    /// Formats that hold keys or credentials, whatever the file is called.
    private static let keyFormats: Set = ["pem", "p12", "pfx", "p8", "ppk", "jks", "keystore", "kdbx", "env", "gpg", "asc", "ovpn", "mobileprovision"]
    /// Files that are a key or a list of them by their own name.
    private static let keyNames: Set = ["authorized_keys", "known_hosts", "htpasswd", "netrc"]
    private static let keyPrefixes = ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519"]
    /// Documents, pictures, recordings and decks: read by people, never a credential store by their name.
    private static let rendered: Set = ["pdf", "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "tif", "bmp", "svg", "mov", "mp4", "m4v", "m4a",
                                        "mp3", "wav", "aiff", "ppt", "pptx", "epub"]
    private static let secretWords: Set = ["token", "tokens", "secret", "secrets", "password", "passwords", "passwd", "passphrase", "passcode", "passcodes",
                                           "credential", "credentials", "apikey", "apikeys", "privatekey", "암호"]
    private static let secretParts = ["비밀번호", "패스워드", "비번"]
    /// The words that make a "key" a credential ("api key", "ssh keys"); "answer key" and "key findings" aren't.
    private static let keyQualifiers: Set = ["api", "private", "secret", "ssh", "access", "auth", "signing", "encryption", "pgp", "gpg", "rsa", "account",
                                             "license", "licence", "recovery", "master", "deploy", "aws", "root", "wallet", "seed"]
    /// Secret words glued to another word: a word that ends with one ("mypasswords", "authtoken"), or starts with one
    /// of the password words ("passwordlist"). "tokenizer" and "secretary" are ordinary words, so those two only end one.
    private static let secretStems = ["password", "passwd", "passphrase", "passcode", "token", "secret", "credential"]
    private static let passwordStems = ["password", "passwd", "passphrase", "passcode"]
    /// What may follow a password word glued to it and still name a store of them ("passwordlist"); "passwordless" is a
    /// design topic, not a secret.
    private static let storeEndings: Set = ["s", "es", "list", "lists", "file", "files", "db", "store", "vault", "backup", "sheet", "manager"]
    /// Two-word names that are a secret by themselves.
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
            if let previous, !word.isEmpty,
               (previous.isLowercase && character.isUppercase) || (previous.isLetter != character.isLetter) {
                words.append(word)
                word = ""
            }
            word.append(character)
        }
        if !word.isEmpty { words.append(word) }
        return words.map { $0.lowercased() }
    }

    /// Whether the file looks like a key or a secret by its name and kind (the rule at the top of this file).
    static func looksSecret(_ path: String, isKeynote: (String) -> Bool = isKeynoteDocument) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        let kind = (name as NSString).pathExtension
        if keyFormats.contains(kind) || keyNames.contains(name) || keyPrefixes.contains(where: name.hasPrefix) { return true }
        if kind == "key" { return !isKeynote(path) }
        if rendered.contains(kind) { return false }
        let base = kind.isEmpty ? (path as NSString).lastPathComponent : ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        if secretParts.contains(where: base.contains) { return true }
        let words = words(base)
        if words.contains(where: secretWords.contains) { return true }
        // Glued forms (security review L1): "mypasswords", "wifipassword", "authtoken", "passwordlist"; and "…key(s)" glued
        // to a qualifier ("sshkey", "secretkey", "rootkey"). "monkey", "turkey" and "hockey" have no qualifier before "key".
        if words.contains(where: { word in
            secretStems.contains { word.hasSuffix($0) || word.hasSuffix($0 + "s") }
                || passwordStems.contains { word.hasPrefix($0) && storeEndings.contains(String(word.dropFirst($0.count))) }
        }) { return true }
        if words.contains(where: { word in
            guard let stem = ["keys", "key"].first(where: word.hasSuffix).map({ String(word.dropLast($0.count)) }), !stem.isEmpty else { return false }
            return keyQualifiers.contains(stem)
        }) { return true }
        let spaced = words.joined(separator: " ")
        if secretPhrases.contains(where: { spaced == $0 || spaced.hasPrefix($0 + " ") || spaced.hasSuffix(" " + $0) || spaced.contains(" " + $0 + " ") }) { return true }
        let said = words.filter { !$0.allSatisfy(\.isNumber) }
        return words.indices.contains { index in
            guard words[index] == "key" || words[index] == "keys" else { return false }
            if said.count == 1 { return true }
            return [index - 1, index + 1].contains { words.indices.contains($0) && keyQualifiers.contains(words[$0]) }
        }
    }

    /// A Keynote document: a package (a folder) or a zip file. A private key named `.key` is text and is neither; a
    /// file that can't be read is not taken for a deck.
    static func isKeynoteDocument(_ path: String) -> Bool {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else { return false }
        if isFolder.boolValue { return true }
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == Data([0x50, 0x4B, 0x03, 0x04])
    }

    // MARK: - Opening

    /// Whether `open` may open it: a document, image or media file, by extension.
    static func openableFile(_ path: String) -> Bool {
        openable.contains((path as NSString).pathExtension.lowercased())
    }

    /// Why `open` won't open this path, as a sentence for the brain; nil when it may. A Keynote, Pages or Numbers
    /// document opens as a package (a folder) too; no other folder and no app does.
    static func openRefusal(_ path: String, home: String, isFolder: Bool, isKeynote: (String) -> Bool = isKeynoteDocument,
                            disks: ArisExternalDisks = .mounted) -> String? {
        let kind = (path as NSString).pathExtension.lowercased()
        if isFolder, !packages.contains(kind) { return "folders and app bundles don't open this way" }
        // On an external disk too (audit tools-12), outside its hidden folders.
        let onDisk = disks.refusal(path) == nil && disks.place(path)?.inside.contains { $0.hasPrefix(".") } == false
        guard inListedPlace(path, home: home) || onDisk else {
            return "only documents, images and media in your home folder, iCloud Drive or on an external disk open this way"
        }
        if looksSecret(path, isKeynote: isKeynote) {
            return "\((path as NSString).lastPathComponent) looks like a key, token or password file by its name, and Aris never opens those: tell the user to open it in Finder themselves"
        }
        return openableFile(path) ? nil : "only documents, images and media open this way (not apps, scripts or other kinds of file)"
    }

    // MARK: - Matches left out

    /// How many found paths were left out only because their names look like secrets (they sit where files are listed).
    static func heldBack(_ paths: [String], home: String) -> Int {
        paths.filter { inListedPlace($0, home: home) && looksSecret($0) }.count
    }

    /// What a search adds when it left matches out, so a file that is there is never told as missing; nil for none.
    static func heldBackNote(_ count: Int, korean: Bool) -> String? {
        guard count > 0 else { return nil }
        return korean ? "(이름이 키·토큰·비밀번호 파일처럼 보이는 \(count)개는 목록에서 뺐어요. 그런 파일은 Aris가 보여 주지 않아요: Finder에서 직접 열어 주세요.)"
            : "(\(count) match\(count == 1 ? " was" : "es were") left out: the name\(count == 1 ? " looks" : "s look") like a key, token or password file, which Aris never lists. The user can open \(count == 1 ? "it" : "them") in Finder.)"
    }
}
