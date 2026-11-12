//
//  ArisToolsLink.swift
//  aris-agent
//
//  ~/.config/aris/aris-tools, the path the AIs are told. It is a link to the aris-tools inside this helper's own app,
//  and the user's folder is a place any of their programs can write: something else put at that path would be run by
//  an AI that Aris started, as Aris (security review 4, H1). The helper never starts that path for its own work
//  (ArisAppBundle.ownTools); for what an AI runs through it, the helper looks at the link before it starts an AI,
//  before it passes an AI's call on, and whenever something changes in the folder: it must be a link to exactly this
//  app's aris-tools (not a file of its own, not a link elsewhere). A link that is wrong is put right with the same
//  write the installer uses (ArisSafeFiles); when that fails the AI is not started and the call is not passed on.
//
//  What this cannot close: between the helper's look and the AI's own use of the path, another program of the same
//  user can still swap it. The watch makes that window short, not nil.
//
//  A loose copy of the helper (a developer's build, the tests) has no app and no link to keep: every check says yes
//  and touches nothing.
//

import Foundation

enum ArisToolsLink {
    static let refusedLine = "Aris의 도구 연결(~/.config/aris/aris-tools)이 다른 곳을 가리키고 있고 고치지 못해서, 실행하지 않았어요. Aris를 다시 열어 주세요."
    static let refusedLineEnglish = "The link to Aris's tools (~/.config/aris/aris-tools) points somewhere else and couldn't be put right, so nothing was run. Open Aris again."

    /// Whether what is at the link's path is right: a link whose text is exactly this app's aris-tools.
    static func isRight(kind: ArisSafeFiles.Kind, target: String?, own: String) -> Bool {
        kind == .link && target == own
    }

    /// What the helper does about the link (pure): nothing for a loose copy or a right link, else a repair.
    enum Step: Equatable {
        case nothing, repair
    }

    static func step(app: String?, kind: ArisSafeFiles.Kind, target: String?, own: String) -> Step {
        guard app != nil else { return .nothing }
        return isRight(kind: kind, target: target, own: own) ? .nothing : .repair
    }

    /// Looks at the link and repairs it when it is wrong. True when the link is right now (or this is a loose copy).
    /// `kind`, `target` and `repair` are the real file calls unless a test gives its own.
    @discardableResult
    static func ensure(app: String? = ArisAppBundle.path, link: String = ArisAppBundle.toldTools, own: String = ArisAppBundle.ownTools,
                       kind: (String) -> ArisSafeFiles.Kind = ArisSafeFiles.kind, target: (String) -> String? = ArisSafeFiles.linkTarget,
                       repair: (_ target: String, _ path: String) -> Bool = { ArisSafeFiles.replaceLink(target: $0, at: $1) },
                       note: (String) -> Void = { FileHandle.standardError.write(Data(("aris-agent: " + $0 + "\n").utf8)) },
                       enforcing: Bool = ArisRollout.enforcing) -> Bool {
        let found = kind(link)
        let pointed = target(link)
        guard step(app: app, kind: found, target: pointed, own: own) == .repair else { return true }
        note("the tools link was \(describe(found, pointed)); putting it back to this app's aris-tools")
        guard repair(own, link), isRight(kind: kind(link), target: target(link), own: own) else {
            note("the tools link could not be put right")
            // Until the new checks are enforced (ArisRollout) this is written down and nothing is held back for it.
            if !enforcing { ArisRollout.wouldRefuse("an AI's start or call: the tools link could not be put right") }
            return !enforcing
        }
        return true
    }

    /// For the log: what was there, without the content of anything.
    static func describe(_ kind: ArisSafeFiles.Kind, _ target: String?) -> String {
        switch kind {
        case .nothing: return "missing"
        case .file: return "a file of its own"
        case .folder: return "a folder"
        case .other: return "not a file or a link"
        case .link: return "a link to \(target ?? "?")"
        }
    }

    // MARK: The watch

    nonisolated(unsafe) private static var watch: DispatchSourceFileSystemObject?

    /// Looks again whenever anything is made, renamed or removed in Aris's folder (only inside an app).
    static func startWatching(app: String? = ArisAppBundle.path, link: String = ArisAppBundle.toldTools, queue: DispatchQueue = .global(qos: .utility)) {
        guard app != nil, watch == nil else { return }
        let folder = open((link as NSString).deletingLastPathComponent, O_EVTONLY | O_DIRECTORY | O_NOFOLLOW)
        guard folder >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: folder, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { ensure() }
        source.setCancelHandler { close(folder) }
        source.resume()
        watch = source
    }
}
