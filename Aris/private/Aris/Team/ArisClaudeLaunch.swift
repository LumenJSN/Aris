//
//  ArisClaudeLaunch.swift
//  Aris (also built into aris-agent)
//
//  What starts the Claude Code teammate: one shell line typed into a new terminal window, and the AppleScript that
//  types it. The prompt is never in either: it sits in a private file, and the shell reads it ("$(cat …)"). The
//  folder and the file's path are single-quoted for the shell, and the whole line is escaped again for AppleScript.
//  Interactive `claude` only: no -p and no flag that loosens its permissions, so its own prompts stay in the window.
//

import Foundation

enum ArisClaudeLaunch {
    enum Host: String {
        case terminal, iTerm

        var bundleId: String {
            switch self {
            case .terminal: return "com.apple.Terminal"
            case .iTerm: return "com.googlecode.iterm2"
            }
        }
    }

    /// `cd '<cwd>' && '<claude>' "$(cat '<promptFile>')"`: `claude` is the checked binary's absolute path
    /// (ArisTeammateGate.claudeBinary); without one, the bare `claude` on the PATH (such a launch is never vouched).
    static func command(promptFile: String, cwd: String, claude: String? = nil) -> String {
        "cd \(shellQuoted(cwd)) && \(claude.map(shellQuoted) ?? "claude") \"$(cat \(shellQuoted(promptFile)))\""
    }

    /// POSIX single quotes: nothing inside is special, and a quote itself becomes '\''.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// An AppleScript string literal: backslashes and double quotes escaped, nothing else special.
    static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// A new window that runs `command` in the user's shell. Terminal: `do script`; iTerm2: a new window whose session
    /// is sent the line (`write text`), so both go through the login shell the same way.
    static func script(command: String, host: Host) -> String {
        let line = appleScriptString(command)
        switch host {
        case .terminal:
            return """
                tell application id "\(host.bundleId)"
                    activate
                    do script \(line)
                end tell
                """
        case .iTerm:
            return """
                tell application id "\(host.bundleId)"
                    activate
                    set newWindow to (create window with default profile)
                    tell current session of newWindow to write text \(line)
                end tell
                """
        }
    }

    static func promptFileName(_ id: UUID) -> String {
        "cc-\(id.uuidString.lowercased()).txt"
    }

    /// Steps in a prompt that would reach outside the Mac (push, publish, deploy, upload, send), in the order they
    /// appear, each once. A more specific step ("git push") hides the general word inside it ("push").
    /// Advisory only: no list can name every way out (a script, a new tool). The backstops are Claude Code's own
    /// permission prompts in the visible terminal and ArisTeammateGate's vouching rules.
    static func outboundSteps(in prompt: String) -> [String] {
        var taken: [Range<String.Index>] = []
        var found: [(at: String.Index, word: String)] = []
        for (pattern, word) in outboundPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)) {
                guard let range = Range(match.range, in: prompt), !taken.contains(where: { $0.overlaps(range) }) else { continue }
                taken.append(range)
                found.append((range.lowerBound, word))
            }
        }
        var seen = Set<String>()
        return found.sorted { $0.at < $1.at }.map(\.word).filter { seen.insert($0).inserted }
    }

    /// The rest of one shell command on the same line (no `;`, `|`, `&` or newline in between).
    private static let sameCommand = #"[^\n;|&]*?"#

    /// Most specific first. Options between `git` and `push` (`git -C x push`, `git -c a=b push`) still count.
    private static let outboundPatterns: [(String, String)] = [
        (#"\bgit(?:\s+(?:-[Cc]\s+\S+|--?[\w-]+(?:=\S+)?))*\s+push\b"#, "git push"),
        (#"\bdocker\s+push\b"#, "docker push"),
        (#"\bpnpm\s+publish\b"#, "pnpm publish"),
        (#"\byarn\s+(?:npm\s+)?publish\b"#, "yarn publish"),
        (#"\bnpm\s+publish\b"#, "npm publish"),
        (#"\bcargo\s+publish\b"#, "cargo publish"),
        (#"\btwine\s+upload\b"#, "twine upload"),
        (#"\bgh\s+release\b"#, "gh release"),
        (#"\bgh\s+pr\s+(?:create|merge)\b"#, "gh pr"),
        (#"\bwrangler\s+(?:deploy|publish)\b"#, "wrangler deploy"),
        (#"\bfly(?:ctl)?\s+deploy\b"#, "fly deploy"),
        (#"\bnetlify\s+deploy\b"#, "netlify deploy"),
        (#"\bfirebase\s+deploy\b"#, "firebase deploy"),
        (#"\baws\s+s3\s+(?:cp|sync|mv)\b"#, "aws s3"),
        (#"\bgcloud\b"# + sameCommand + #"\bdeploy\b"#, "gcloud deploy"),
        (#"\bcurl\b"# + sameCommand + #"(?:\s-X\s*(?:POST|PUT|PATCH|DELETE)\b|\s--request[=\s]+(?:POST|PUT|PATCH|DELETE)\b|\s-d\b|\s--data\S*|\s-F\b|\s--form\b|\s-T\b|\s--upload-file\b)"#, "curl upload"),
        (#"\bwget\b"# + sameCommand + #"(?:\s--post-(?:data|file)\b|\s--method[=\s]+(?:POST|PUT|PATCH|DELETE)\b|\s--body-(?:data|file)\b)"#, "wget upload"),
        (#"\bscp\b"#, "scp"),
        (#"\brsync\b"# + sameCommand + #"(?:\s\S*[\w.-]+:(?!//)\S*|rsync://)"#, "rsync"),
        (#"\bvercel\b"#, "vercel"),
        (#"\bdeploy"#, "deploy"),
        (#"\bpublish"#, "publish"),
        (#"\bupload"#, "upload"),
        (#"\breleas(?:e|es|ed|ing)\b"#, "release"),
        (#"\bpush"#, "push"),
        (#"\bsend"#, "send"),
        (#"\be-?mail"#, "email"),
        (#"\bmail(?:s|ed|ing)?\b"#, "mail"),
        (#"\bpost(?:s|ed|ing)?\b"#, "post"),
        (#"\btweet"#, "tweet"),
        ("업로드", "업로드"), ("배포", "배포"), ("푸시", "푸시"), ("보내", "보내"), ("전송", "전송"), ("게시", "게시"), ("올려", "올려"),
    ]
}
