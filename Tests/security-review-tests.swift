// Tests for the fixes that came out of the security review of the release candidate (qa/audit-1110/SECURITY-REVIEW.md):
// a child's stream given as /dev/null is open on /dev/null (M1), a connected service's tool with a second, writing
// action isn't a read (M2), a stored brain is never replaced behind the user's back (M5), and file names that only
// glue a secret word to another word are still held back (L1). Called from main.swift; uses its check().
import Foundation

func runSecurityReviewTests() {
    nullStreamTests()
    serviceWriteTests()
    storedBrainTests()
    secretNameTests()
}

/// The shell's exit when it uses descriptor `stream`, which the test hands over as FileHandle.nullDevice.
private func exitUsing(_ stream: Int) -> Int32 {
    let process = ArisExactProcess()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", ["true <&0", "true >&1", "true >&2"][stream]]
    process.standardInput = stream == 0 ? FileHandle.nullDevice : nil
    process.standardOutput = stream == 1 ? FileHandle.nullDevice : Pipe()
    process.standardError = stream == 2 ? FileHandle.nullDevice : Pipe()
    guard (try? process.run()) != nil else { return -1 }
    process.waitUntilExit()
    return process.terminationStatus
}

private func nullStreamTests() {
    check(FileHandle.nullDevice.fileDescriptor < 0, "exact process: the null device has no descriptor of its own to hand over")
    check(exitUsing(0) == 0 && exitUsing(1) == 0 && exitUsing(2) == 0,
          "exact process: a stream given as the null device is open in the child (on /dev/null), never closed")
}

private func serviceWriteTests() {
    let own = { (name: String) in ArisMCPPolicy.kind(ofName: name, readOnlyHint: nil, destructiveHint: nil) }
    for name in ["fetch_post", "fetch_put", "fetch_patch", "get_set_volume", "read_mark_done", "search_archive", "list_move_items", "get_run_job",
                 "fetch_forward_email", "list_cancel_orders"] {
        check(own(name) != .read, "service tools: \(name) with no hint is not taken for a read (a second, writing word)")
    }
    check(ArisMCPPolicy.kind(ofName: "list_merge_requests", readOnlyHint: true, destructiveHint: nil) == .read
          && ArisMCPPolicy.kind(ofName: "get_trigger", readOnlyHint: true, destructiveHint: nil) == .read, "service tools: a server's own read-only mark still stands for things named like verbs")
    check(own("list_posts") == .read && own("list_labels") == .read && own("get_comments") == .read && own("search_messages") == .read
          && own("fetch_orders") == .read, "service tools: a plain read of things whose names only look like verbs still reads")
    for slug in ["HTTP_GET_PUT_OBJECT", "DROPBOX_GET_MOVE_FILE", "API_FETCH_FORWARD_EMAIL", "SHOP_LIST_CANCEL_ORDERS"] {
        check(ArisMCPPolicy.kind(ofSlug: slug) != .read, "service tools: \(slug) is not taken for a read")
    }
    check(ArisMCPPolicy.kind(ofSlug: "GMAIL_FETCH_EMAILS") == .read && ArisMCPPolicy.kind(ofSlug: "GITHUB_LIST_COMMITS") == .read
          && ArisMCPPolicy.kind(ofSlug: "SLACK_SEARCH_MESSAGES") == .read, "service tools: Composio's plain reads still read")
}

private func storedBrainTests() {
    let onlyAPI: [ArisBrain: Bool] = [.claude: false, .codex: false, .antigravity: false, .api: true]
    check(ArisBrainChoice.resolve(stored: "codex", ready: onlyAPI) == nil,
          "brain choice: a brain the user stored is never replaced, even when it reads as not set up (one slow look must not move them to another AI)")
    check(ArisBrainChoice.resolve(stored: nil, ready: onlyAPI) == .api && ArisBrainChoice.resolve(stored: "nonsense", ready: onlyAPI) == .api,
          "brain choice: with nothing (or nothing valid) stored, the first AI that is set up is stored")
    check(ArisBrainChoice.answering(.codex, ready: onlyAPI) == .api, "brain choice: a request still goes to one that can answer, for now")
}

private func secretNameTests() {
    for name in ["mypasswords.txt", "wifipassword.txt", "sshkey.txt", "secretkey.txt", "rootkey.csv", "authtoken.txt", "passwordlist.txt",
                 "bankpasswords.xlsx", "wallet keys.txt", "aws keys.csv", "seed phrase.txt", "recoverycodes.txt"] {
        check(ArisFiles.looksSecret("/Users/x/Documents/" + name, isKeynote: { _ in false }), "secret names: \(name) is held back")
    }
    for name in ["Token economy essay.pdf", "keynote-token-design.pdf", "answer key.docx", "key findings.txt", "monkey.txt", "turkey recipe.txt",
                 "hockey keys.txt", "passport renewal.txt", "notes.txt", "tokenizer.py", "secretary notes.txt", "passwordless-login-design.md"] {
        check(!ArisFiles.looksSecret("/Users/x/Documents/" + name, isKeynote: { _ in false }), "secret names: \(name) is an ordinary file")
    }
}
