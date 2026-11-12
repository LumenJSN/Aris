//
//  ArisRiskPolicy+Files.swift
//  aris-agent
//
//  The risk gate's reading of places and names (moved out of ArisRiskPolicy.swift, which had grown past what one file
//  should hold): which paths are protected, which an edit may ask about with its whole change and which it never
//  touches (audit gate-17), what lies outside the home folder, what a connector's tool does by its name, and which
//  files are keys, tokens or passwords.
//

import Foundation

extension ArisRiskPolicy {
    // MARK: - Files

    /// Places an edit could take over the Mac or Aris itself from: the system folders, and ArisProtectedPlaces under the
    /// home folder (compared without regard to case; a path that contains one counts too).
    static func isProtected(_ path: String, home: String) -> Bool {
        let system = ["/Library", "/System", "/etc", "/private/etc", "/usr", "/bin", "/sbin"]
        // And the folders of the user's login-shell PATH, outside home too (/opt/homebrew/bin): what is put there runs
        // inside the agent (security review M4).
        // And Aris's own app with whatever folder holds it (security review 4, M6: the helper, its tools and the built-in
        // skill moved into the app, which /Applications does not protect).
        return system.contains { isInside(path, $0) } || ArisProtectedPlaces.blocks(path, home: home) || ArisProtectedPlaces.inLoginFolder(path, home: home)
            || ArisProtectedPlaces.holdsApp(path)
    }

    /// Whether `path` (as an AI wrote it) names a protected place once it is made absolute and its links are followed.
    static func touchesProtected(_ path: String, home: String) -> Bool {
        let resolvedHome = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        let tilded = path == "~" ? home : path.hasPrefix("~/") ? home + path.dropFirst() : path
        let absolute = tilded.hasPrefix("/") ? tilded : home + "/.config/aris/aris/" + tilded
        let url = URL(fileURLWithPath: absolute).standardizedFileURL
        // The leaf resolved (a link to a protected place) and the leaf as named inside its resolved folder.
        let followed = url.resolvingSymlinksInPath().path
        let named = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
        return [url.path, followed, named].contains { isProtected($0, home: home) || isProtected($0, home: resolvedHome) }
    }

    /// Whether `path` (as an AI wrote it, read as aris-tools reads it) lies outside the home folder once it is made
    /// absolute and its links are followed.
    static func isOutsideHome(_ path: String, home: String) -> Bool {
        let resolvedHome = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        let tilded = path == "~" ? home : path.hasPrefix("~/") ? home + path.dropFirst() : path
        let absolute = tilded.hasPrefix("/") ? tilded : home + "/.config/aris/aris/" + tilded
        let real = URL(fileURLWithPath: absolute).standardizedFileURL.resolvingSymlinksInPath().path
        let standardHome = (home as NSString).standardizingPath
        return ![resolvedHome, standardHome].contains { real == $0 || real.hasPrefix($0 + "/") }
    }

    static func files(_ paths: [String], home: String) -> ArisRisk {
        guard !paths.isEmpty else { return .confirm }
        let work = workFolder(home: home)
        let expanded = paths.map { expand($0, home: home) }
        if expanded.allSatisfy({ isInside($0, work) }) { return .auto }
        // A shell or tool settings file (~/.zshrc, ~/.gitconfig, ~/bin, /usr/local) asks, on a card showing the whole
        // change (isSettingsEdit: audit gate-17); any other protected place is never edited.
        // (The work folder lies inside Aris's own protected folder: a file there is no refusal of an edit that also
        // reaches outside it, such as a draft moved out to the Desktop, which asks: security review 2 H2.)
        return expanded.contains { !isInside($0, work) && refusesEdit($0, home: home) } ? .never : .confirm
    }

    /// The system folders no edit reaches, and ArisProtectedPlaces' list without the settings an edit may ask about.
    /// /usr/local (tools the user installed themselves) asks; the rest of /usr never.
    static func neverEdited(_ path: String, home: String) -> Bool {
        let system = ["/Library", "/System", "/etc", "/private/etc", "/usr", "/bin", "/sbin"]
        return (system.contains { isInside(path, $0) } && !isInside(path, "/usr/local")) || ArisProtectedPlaces.blocksEdit(path, home: home)
            || ArisProtectedPlaces.holdsApp(path)
    }

    /// Whether an edit of `path` (expanded) is refused: by its name, and by what it really is once its links are
    /// followed (a settings file that is a link into a key folder is that key folder).
    static func refusesEdit(_ path: String, home: String) -> Bool {
        let resolvedHome = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        let url = URL(fileURLWithPath: path)
        let followed = url.resolvingSymlinksInPath().path
        let named = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
        return [path, followed, named].contains { neverEdited($0, home: home) || neverEdited($0, home: resolvedHome) }
    }

    /// An edit that touches a shell or tool settings file and is not refused: the driver shows the whole change on
    /// The user's card and never remembers their yes; when the change can't be shown, it is refused.
    /// A file is what it really is once its links are followed, as in `refusesEdit`: ~/Documents/notes.txt that is a
    /// link to ~/.zshrc is the settings file, with its whole change on the card (security review 2 L1).
    static func isSettingsEdit(_ paths: [String], home: String) -> Bool {
        let expanded = paths.map { expand($0, home: home) }
        let resolvedHome = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        let isSettings = { (path: String) -> Bool in
            let url = URL(fileURLWithPath: path)
            let followed = url.resolvingSymlinksInPath().path
            let named = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
            return [path, followed, named].contains { isProtected($0, home: home) || isProtected($0, home: resolvedHome) }
        }
        return expanded.contains(where: isSettings) && !expanded.contains { refusesEdit($0, home: home) }
    }

    // MARK: - Tools (Notion, Gmail…)

    /// Verbs that only make or edit something, which is fine for a draft (create_draft, update_draft).
    private static let draftingVerbs: Set<String> = ["create", "update", "write", "edit", "set", "draft", "save", "modify"]

    /// A connector's tool by what its name says it does, read as the hub reads one (ArisMCPPolicy.action: the first
    /// plain verb is the action, so list_labels and get_commits read and no longer ask; HANDOVERS B1). A write asks
    /// (run_query, create_page), a read goes, anything else (getthread) asks.
    static func mcpTool(_ tool: String) -> ArisRisk {
        let words = ArisMCPPolicy.words(tool)
        let writes = ArisMCPPolicy.writeVerbs.filter { verb in words.contains { ArisMCPPolicy.isForm($0, of: verb) } }
        // A draft is made or edited freely, but sending or deleting one (send_draft) is still asked about.
        if words.contains(where: { $0.hasPrefix("draft") }), writes.isSubset(of: draftingVerbs) { return .auto }
        return connectorReads(tool) ? .auto : .confirm
    }

    /// Whether a connector's tool only reads, by its name: it leads with a verb that only reads and no later word is
    /// itself a write verb (these tools come with no hints, so fetch_post, search_archive and get_run_job still ask,
    /// while list_labels, list_posts and get_commits read); or it has a read word (status, info, summary) and no form
    /// of a write verb at all. Anything else is not a read: the user's card, never the read judge.
    static func connectorReads(_ tool: String) -> Bool {
        let words = ArisMCPPolicy.words(tool)
        switch ArisMCPPolicy.action(words) {
        case .reads:
            guard let lead = words.firstIndex(where: { ArisMCPPolicy.readVerbs.contains($0) || ArisMCPPolicy.writeVerbs.contains($0) }) else { return false }
            return !words[(lead + 1)...].contains(where: ArisMCPPolicy.writeVerbs.contains)
        case .mayRead:
            return !ArisMCPPolicy.hasWriteVerb(words)
        case .writes, .unclear:
            return false
        }
    }

    // MARK: - Paths

    static func expand(_ path: String, home: String) -> String {
        let full = path == "~" ? home : path.hasPrefix("~/") ? home + path.dropFirst() : path
        return (full as NSString).standardizingPath
    }

    static func isInside(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder + "/")
    }

    /// A key, token, password or private store (`isSecret`), for a path outside the risk gate's own commands (a file
    /// panel's place: ArisDesktopGate, I9).
    static func isSecretPath(_ path: String, home: String) -> Bool {
        isSecret(expand(path, home: home), work: workFolder(home: home)) || coversSecrets(expand(path, home: home), home: home)
    }

    /// Keys, tokens and passwords: reading them is asked first, since what's read can be sent on.
    /// In Aris's own folder only the key and token files are (elevenlabs-key, claude-hook-token); looking at
    /// aris-tools itself was being asked about.
    static func isSecret(_ path: String, work: String) -> Bool {
        guard !isInside(path, work) else { return false }
        let lowered = path.lowercased()
        let places = ["/.ssh", "/.gnupg", "/keychains", "/.codex", "/.claude", "/.aws", "/.netrc", "/.config/gh", "/.docker", "/.kube",
                      "/.npmrc", "/.pypirc", "/.git-credentials", "/.peekaboo", "/computer-runtime"]
        let file = (lowered as NSString).lastPathComponent
        // ~/.config/boring-notch is the old name of Aris's folder, kept as a link to it.
        let inArisFolder = lowered.contains("/.config/aris") || lowered.contains("/.config/boring-notch")
        let arisKey = inArisFolder && (file.hasSuffix("-key") || file.hasSuffix(".key"))
        // A teammate's brief and launch script (ArisTeammateLauncher.launchFolder): reading them asks (review 7, M1).
        let launchFile = inArisFolder && (lowered.hasSuffix("/aris/launch") || lowered.contains("/aris/launch/"))
        return places.contains(where: lowered.contains) || namesSecret(file) || arisKey || launchFile
            || ArisLocalReadPolicy.storeFragments.contains(where: lowered.contains)
    }
}
