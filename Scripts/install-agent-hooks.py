#!/usr/bin/env python3
"""Show Codex and Gemini CLI sessions in Aris's Claude tab.

Adds a command hook (agent-hook.sh) to ~/.codex/hooks.json and ~/.gemini/settings.json for the events the
notch shows, turns Codex's hooks feature on, and writes the token header file agent-hook.sh reads.
Default is a dry run; --apply backs up each file first. Existing hooks (e.g. Orca's) are kept; re-running is
a no-op. Codex and Gemini approvals stay in their own terminal (only Claude's are answered in the notch).
An agent that is not installed (no ~/.codex or ~/.gemini folder) is skipped with a line saying so; the other one is
still set up.
"""
import argparse, json, re, shutil, time
from pathlib import Path

HOME = Path.home()
DIR = HOME / ".config" / "aris"
# The folder's name before the rename; ~/.config/boring-notch is now a link to it.
LEGACY_DIR = HOME / ".config" / "boring-notch"
TOKEN = DIR / "claude-hook-token"
HEADERS = DIR / "agent-hook-headers"
SCRIPT_SRC = Path(__file__).resolve().parent / "agent-hook.sh"
SCRIPT = DIR / "agent-hook.sh"
CODEX_HOOKS = HOME / ".codex" / "hooks.json"
CODEX_CONFIG = HOME / ".codex" / "config.toml"
GEMINI = HOME / ".gemini" / "settings.json"
CODEX_EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"]
GEMINI_EVENTS = ["SessionStart", "SessionEnd", "BeforeAgent", "AfterAgent", "BeforeTool", "AfterTool", "Notification"]
# How long one hook may run. Codex counts seconds; Gemini CLI counts milliseconds (its default is 60000).
CODEX_TIMEOUT = 5
GEMINI_TIMEOUT = 5000


def command(agent):
    return f'"{SCRIPT}" {agent}'


def legacy_command(agent):
    return f'"{LEGACY_DIR / "agent-hook.sh"}" {agent}'


def with_hooks(hooks, events, agent, timeout):
    """hooks: {event: [ {hooks: [ {type, command, timeout} ]} ]}; ours added once per event, with `timeout`."""
    updated = json.loads(json.dumps(hooks))
    for event in events:
        groups = updated.setdefault(event, [])
        # A hook installed under the old folder name is ours: point it at the new one instead of adding a second.
        # Ours already there keeps its place and gets today's timeout (an earlier version gave Gemini 5 ms).
        for g in groups:
            for h in g.get("hooks", []):
                if h.get("command") == legacy_command(agent):
                    h["command"] = command(agent)
                if h.get("command") == command(agent):
                    h["timeout"] = timeout
        if any(h.get("command") == command(agent) for g in groups for h in g.get("hooks", [])):
            continue
        groups.append({"hooks": [{"type": "command", "command": command(agent), "timeout": timeout}]})
    return updated


def read_json(path):
    """The file as a JSON object; {} when it is missing or empty. Anything else stops with a plain message."""
    if not path.exists() or not path.read_text().strip():
        return {}
    try:
        value = json.loads(path.read_text())
    except ValueError as error:
        raise SystemExit(f"{path} is not valid JSON ({error}); nothing was changed")
    if not isinstance(value, dict):
        raise SystemExit(f"{path} is not a JSON object; nothing was changed")
    return value


def read_token():
    try:
        token = TOKEN.read_text().strip()
    except OSError:
        token = ""
    if len(token) < 32:
        raise SystemExit(f"no hook token yet ({TOKEN}): start Aris once (its agent makes the token), "
                         "or run install-claude-hooks.py --apply, then run this again")
    return token


def codex_writes():
    """(path, new text, current text or None) for Codex's hooks and its feature switch, written together."""
    codex = read_json(CODEX_HOOKS)
    codex_new = {**codex, "hooks": with_hooks(codex.get("hooks", {}), CODEX_EVENTS, "codex", CODEX_TIMEOUT)}
    config = CODEX_CONFIG.read_text() if CODEX_CONFIG.exists() else ""
    config_new = re.sub(r"(?m)^codex_hooks\s*=\s*false\s*$", "codex_hooks = true", config)
    if "codex_hooks" not in config_new:
        config_new = config_new.replace("[features]\n", "[features]\ncodex_hooks = true\n", 1) if "[features]\n" in config_new \
            else config_new + "\n[features]\ncodex_hooks = true\n"
    return [(CODEX_HOOKS, json.dumps(codex_new, indent=2) + "\n", json.dumps(codex, indent=2) + "\n" if CODEX_HOOKS.exists() else None),
            (CODEX_CONFIG, config_new, config if CODEX_CONFIG.exists() else None)]


def gemini_writes():
    gemini = read_json(GEMINI)
    gemini_new = {**gemini, "hooks": with_hooks(gemini.get("hooks", {}), GEMINI_EVENTS, "gemini", GEMINI_TIMEOUT)}
    return [(GEMINI, json.dumps(gemini_new, indent=2) + "\n", json.dumps(gemini, indent=2) + "\n" if GEMINI.exists() else None)]


def backup(path):
    if path.exists():
        shutil.copy2(path, path.with_name(path.name + f".bak-{int(time.time())}"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    apply = parser.parse_args().apply
    token = read_token()

    # Only an agent that is installed (its folder exists) is set up; the other is named and left alone.
    writes = []
    for name, folder, planned in (("Codex", CODEX_HOOKS.parent, codex_writes), ("Gemini CLI", GEMINI.parent, gemini_writes)):
        if folder.is_dir():
            writes += planned()
        else:
            print(f"skip   {name} is not installed (no {folder}); run this again after installing it")
    if not writes:
        print("nothing to set up: neither Codex nor Gemini CLI is installed")
        return
    for path, text, current in writes:
        print(f"{'change' if current != text else 'same  '} {path}")
    if not apply:
        print("dry run: pass --apply to write (each file is backed up first)")
        return
    DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    shutil.copy2(SCRIPT_SRC, SCRIPT)
    SCRIPT.chmod(0o700)
    HEADERS.write_text(f"X-Aris-Token: {token}\n")
    HEADERS.chmod(0o600)
    for path, text, _ in writes:
        if path.exists() and path.read_text() == text:
            continue
        backup(path)
        path.write_text(text)
    print("done. Codex may ask once to trust the new hooks.")


if __name__ == "__main__":
    main()
