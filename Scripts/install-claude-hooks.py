#!/usr/bin/env python3
"""Add Aris's Claude tab hooks to ~/.claude/settings.json.

Default is a dry run that prints the diff. Pass --apply to back up and write.
Existing hooks (e.g. Clawd's) are kept; re-running is a no-op.
Only the events Aris uses are registered, each with a short timeout: Aris answers an event in about a millisecond,
so a hook that waits longer than two seconds is a hook that is not being answered, and Claude Code moves on.
Running it over an older install brings Aris's own hooks (the ones posting to its URL, nobody else's) up to date:
today's timeouts, and its hooks on the events it no longer uses are taken off.
Each hook sends a shared secret header; the app rejects requests without it.
Each hook also passes which terminal the session runs in (Warp/iTerm/tmux ids from the
session's environment), so the notch can jump back to that exact tab.
It also installs a status line script that forwards plan limits and context use to the
notch, unless you already have a status line of your own.
A Claude Code that has not written settings.json yet gets one made here. Without Claude Code on this Mac
(no ~/.claude folder and no `claude` program) nothing is written and the script says so.
"""
import argparse, copy, difflib, json, os, secrets, shutil, time
from pathlib import Path

SETTINGS = Path.home() / ".claude" / "settings.json"
TOKEN_FILE = Path.home() / ".config" / "aris" / "claude-hook-token"
TOKEN_HEADER = "X-Aris-Token"
# Before the rename the folder was ~/.config/boring-notch (now a link to ~/.config/aris) and the header had another name.
LEGACY_TOKEN_HEADER = "X-Boring-Notch-Token"
STATUSLINE_SRC = Path(__file__).resolve().parent / "claude-statusline.sh"
STATUSLINE = TOKEN_FILE.parent / "statusline.sh"
LEGACY_STATUSLINE = Path.home() / ".config" / "boring-notch" / "statusline.sh"
URL = "http://127.0.0.1:23350/hook"
# Header -> environment variable Claude Code interpolates into it (only names in allowedEnvVars are read).
TERMINAL_HEADERS = {
    "X-Term-Program": "TERM_PROGRAM",
    "X-Warp-Focus": "WARP_FOCUS_URL",
    "X-Iterm-Session": "ITERM_SESSION_ID",
    "X-Tmux-Pane": "TMUX_PANE",
    "X-Bundle-Id": "__CFBundleIdentifier",
}
# Where the `claude` program is looked for when ~/.claude does not exist yet (the places Aris's agent looks, then PATH).
CLAUDE_PROGRAMS = [Path.home() / ".local" / "bin" / "claude", Path("/opt/homebrew/bin/claude"), Path("/usr/local/bin/claude")]
# The events Aris uses, and what the notch does with each (ClaudeModels.swift, ClaudeStore.swift):
#   SessionStart, SessionEnd      the session's row comes and goes; a teammate's job knows its session
#   UserPromptSubmit              "thinking"; the step list starts over
#   PreToolUse, PostToolUse       the step being run and the steps done; a card answered in the terminal is cleared
#   PostToolUseFailure, StopFailure   the error notice
#   Stop                          "done", its notice and chime; a teammate's job ends
#   Notification                  "waiting for you" (a permission prompt) or resting
#   PreCompact                    "thinking" while the conversation is compacted
#   PermissionRequest             the approval card (the one hook Aris may answer with a decision)
EVENTS = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
          "PostToolUseFailure", "Stop", "StopFailure", "Notification", "PreCompact", "PermissionRequest"]
# Events an earlier version registered that Aris has no use of its own for (a subagent's start and stop: the Agent
# tool's own PreToolUse and PostToolUse already say it): Aris's hooks on them are taken off, so Claude Code makes
# two round trips fewer per subagent.
RETIRED_EVENTS = ["SubagentStart", "SubagentStop"]
# Seconds Claude Code waits for a hook's answer before it carries on without one.
EVENT_TIMEOUT = 2
# The approval card keeps its request open for 120 s at most (ClaudeHookHold.swift), then Aris answers "no decision"
# itself; this is just past that.
PERMISSION_TIMEOUT = 130


def read_token():
    try:
        token = TOKEN_FILE.read_text().strip()
    except FileNotFoundError:
        return None
    return token if len(token) >= 32 else None


def write_token(token):
    TOKEN_FILE.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(TOKEN_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(token + "\n")
    os.chmod(TOKEN_FILE, 0o600)


def headers(token, current=None):
    terminal = {name: "${" + var + "}" for name, var in TERMINAL_HEADERS.items()}
    kept = {k: v for k, v in (current or {}).items() if k != LEGACY_TOKEN_HEADER}
    return {**kept, **terminal, TOKEN_HEADER: token}


def timeout(event):
    return PERMISSION_TIMEOUT if event == "PermissionRequest" else EVENT_TIMEOUT


def entry(event, token):
    return {"matcher": "", "hooks": [{"type": "http", "url": URL, "timeout": timeout(event),
                                      "headers": headers(token),
                                      "allowedEnvVars": sorted(TERMINAL_HEADERS.values())}]}


def has_ours(groups):
    return any(h.get("url") == URL for g in groups for h in g.get("hooks", []))


def upgraded(groups, token, event):
    """Older installs lack the token or terminal headers, or wait longer; set them on our hooks only."""
    return [{**g, "hooks": [{**h, "timeout": timeout(event), "headers": headers(token, h.get("headers")),
                             "allowedEnvVars": sorted(set(h.get("allowedEnvVars", [])) | set(TERMINAL_HEADERS.values()))}
                            if h.get("url") == URL else h for h in g.get("hooks", [])]}
            for g in groups]


def without_ours(groups):
    """The groups without our hooks; anyone else's hook stays where it is, and a group left empty goes."""
    kept = []
    for g in groups:
        hooks = g.get("hooks", [])
        left = [h for h in hooks if h.get("url") != URL]
        if len(left) == len(hooks):
            kept.append(g)
        elif left:
            kept.append({**g, "hooks": left})
    return kept


def with_statusline(settings):
    """Ours is added only where no status line exists; someone else's is left alone."""
    current = settings.get("statusLine")
    if current and current.get("command") not in (str(STATUSLINE), str(LEGACY_STATUSLINE)):
        print(f"Note: keeping your own statusLine ({current.get('command')}); the notch usage meter needs ours.")
        return settings
    return {**settings, "statusLine": {"type": "command", "command": str(STATUSLINE), "padding": 0}}


def write_statusline():
    STATUSLINE.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    shutil.copyfile(STATUSLINE_SRC, STATUSLINE)
    os.chmod(STATUSLINE, 0o700)


def statusline_current():
    return STATUSLINE.exists() and STATUSLINE.read_bytes() == STATUSLINE_SRC.read_bytes()


def merged(settings, token):
    out = copy.deepcopy(settings)
    hooks = out.setdefault("hooks", {})
    for event in EVENTS:
        groups = hooks.get(event, [])
        hooks[event] = upgraded(groups, token, event) if has_ours(groups) else groups + [entry(event, token)]
    for event in RETIRED_EVENTS:
        groups = hooks.get(event, [])
        if not has_ours(groups):
            continue
        left = without_ours(groups)
        if left:
            hooks[event] = left
        else:
            del hooks[event]
    return with_statusline(out)


def claude_installed():
    return SETTINGS.parent.is_dir() or any(p.exists() for p in CLAUDE_PROGRAMS) or shutil.which("claude") is not None


def read_settings():
    """Claude Code's settings as a JSON object; {} when the file is missing or empty (a new install)."""
    if not SETTINGS.exists() or not SETTINGS.read_text().strip():
        return {}
    try:
        value = json.loads(SETTINGS.read_text())
    except ValueError as error:
        raise SystemExit(f"{SETTINGS} is not valid JSON ({error}); nothing was changed")
    if not isinstance(value, dict):
        raise SystemExit(f"{SETTINGS} is not a JSON object; nothing was changed")
    return value


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    if not claude_installed():
        print(f"Claude Code is not installed (no {SETTINGS.parent} and no claude program): nothing to set up. "
              "Run this again after installing it.")
        return
    token = read_token() or secrets.token_hex(32)
    before = read_settings()
    after = merged(before, token)
    a = json.dumps(before, indent=2, ensure_ascii=False).replace(token, "<token>").splitlines()
    b = json.dumps(after, indent=2, ensure_ascii=False).replace(token, "<token>").splitlines()
    diff = list(difflib.unified_diff(a, b, "settings.json", "settings.json (new)", lineterm=""))
    if not diff and read_token() == token and statusline_current():
        print("Already installed; nothing to change.")
        return
    print("\n".join(diff))
    if not args.apply:
        print("\nDry run. Re-run with --apply to write.")
        return
    backup = None
    if SETTINGS.exists():
        backup = SETTINGS.with_name(f"settings.json.pre-notch-claude.{time.strftime('%Y%m%d-%H%M%S')}")
        shutil.copy2(SETTINGS, backup)
        os.chmod(backup, 0o600)
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    write_token(token)
    write_statusline()
    SETTINGS.write_text(json.dumps(after, indent=2, ensure_ascii=False) + "\n")
    if backup is None:
        # Made new here, and it holds the hook token: its owner alone reads it. An existing file keeps its own mode.
        os.chmod(SETTINGS, 0o600)
    print(f"\nWritten. Backup: {backup}" if backup else f"\nWritten. {SETTINGS} is new (there was nothing to back up).")


if __name__ == "__main__":
    main()
