#!/usr/bin/env python3
"""The side panels' demo writes nothing real (ArisSideDemo, 2026-11-07).

In the models that hold the panels' rows, every function that reads or writes a real source (Reminders, aris-agent's
to-dos or activity log, an undo, UserDefaults) must check the demo itself. In the views, every action that changes or
opens real data must sit behind the demo check. A new write added without that check fails here.
The ad's scripted demos (ArisAdDemo, 2026-11-08) are checked here too: their files may reach no real store (Reminders,
Calendar, the history, the activity log, the teammates file, memory, aris-agent, preferences, files), no AI, no microphone
and no screen capture, nothing that types into an app, and no real job run; the director's demo hooks only read the
demo's roster; and the 사용량 tab shows no account or amount without the side-demo mask.
Usage: side-demo-lint.py <boring.notch folder>
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) / "Aris" / "private" / "Aris"
MODELS = [ROOT / "ArisTodoModel.swift", ROOT / "Side" / "ArisActivityModel.swift"]
REAL = re.compile(r"reminders\.(add|update|complete|remove|reload|start)\(|ArisAgentClient\.(todos|activity)\(|undoEntry\(|UserDefaults\.standard\.set\(")
GUARD = re.compile(r"demo\.isOn|demo\.samples|ArisSideDemo\.shared\.(isOn|samples)")
# Views: (file, a call that acts on real data) -> each line with it must carry the demo check, or follow it within two
# lines (a guard).
VIEWS = {
    ROOT / "Side" / "ArisLeftPanel.swift": [r"\.resume\(", r"forgetPastTurns\("],
    ROOT / "ArisTodoView.swift": [r"menu\(item\)", r"composing = id"],
    ROOT / "Side" / "ArisRightPanel.swift": [r"tap\(\$0", r"AnyView\(menu\(", r"calendar\.loadIfAuthorized\(\)"],
}


AD_DEMO = [ROOT / "Demo" / "ArisAdDemo.swift", ROOT / "Demo" / "ArisAdDemoScript.swift"]
# What an ad demo may never call: real stores and their writers, aris-agent, an AI turn, the microphone, the screen,
# typing into an app, a real job's run, preferences and files.
AD_FORBIDDEN = re.compile(
    r"ArisAgentClient\.|ArisReminders|ArisTodoModel|ArisCalendar|EKEventStore|ArisHistory\.|pastTurns|remember\(|forgetPastTurns|"
    r"ArisActivityModel|ArisTeamModel|saveTeammates|ArisMemory|ArisVocabulary|ArisTuningLog|understood\(|finishTurn\(|"
    r"UserDefaults|Defaults\[|FileManager|\.write\(to|URLSession|NSPasteboard|"
    r"\.answer\(|askAndSpeak|speakUp\(|announce\(|speaker\.|ArisSpeaker|"
    r"AVAudioEngine|AVCapture|openMicrophone|ArisListener|ArisWakeDetector|startDictation|finishDictation|ArisDictationState|"
    r"insertDictation|lastText|CGEvent|ArisScreenCapture|ArisWindowCapture|ArisGestureCapture\b|ArisGestureHooks|SCStream|"
    r"\bdispatch\(|handOut\(|start\(id|jobRuns|jobQueue|cancelInAgent|reportDone|ArisBoard"
)
# The director's hooks: each line that names the demo's roster may only ask it (mate, fixedWindow).
DIRECTOR = ROOT / "Team" / "ArisDirector.swift"
USAGE = ROOT / "Side" / "ArisUsageCard.swift"
# A line of the 사용량 tab that shows an account or an amount must go through the mask.
USAGE_SHOWN = re.compile(r"Text\(account\)|Text\(\s*\"\$|ArisUsageFormat\.usd\(|provider\.account\b(?!\s*\{)")


def ad_demo_failures():
    failures = []
    for path in AD_DEMO:
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.split("//", 1)[0]
            hit = AD_FORBIDDEN.search(code)
            if hit:
                failures.append(f"{path.name}:{number}: an ad demo reaches {hit.group(0)!r}")
    for number, line in enumerate(DIRECTOR.read_text().splitlines(), 1):
        code = line.split("//", 1)[0]
        for use in re.findall(r"ArisAdDemoRoster\.(\w+)", code):
            if use not in ("mate", "fixedWindow", "notchScreen"):
                failures.append(f"{DIRECTOR.name}:{number}: the director may only read the demo roster, not {use}")
    # Only a demo may put a window into screen recordings (ArisCaptureSharing): the real features stay out of them.
    shown = re.compile(r"shownInCaptures\s*[:=]\s*true|showInCaptures\(true\)|sharingType\s*=\s*\.(readOnly|readWrite)")
    for path in sorted(ROOT.rglob("*.swift")):
        if path.parent.name == "Demo":
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if shown.search(line.split("//", 1)[0]):
                failures.append(f"{path.name}:{number}: a window shown in recordings outside the ad demos")
    for number, line in enumerate(USAGE.read_text().splitlines(), 1):
        code = line.split("//", 1)[0]
        if "if let account = provider.account" in code:
            continue
        if USAGE_SHOWN.search(code) and "ArisUsageMask" not in code:
            failures.append(f"{USAGE.name}:{number}: an account or amount shown without ArisUsageMask")
    return failures


def functions(text):
    """Each `func` at the type's level (4 spaces in) with its body, up to the next one."""
    starts = [m.start() for m in re.finditer(r"^    (?:@\w+\s+)*(?:private |static |nonisolated )*func ", text, re.M)]
    return [text[a:b] for a, b in zip(starts, starts[1:] + [len(text)])]


def main():
    failures = []
    for path in MODELS:
        for body in functions(path.read_text()):
            name = re.search(r"func (\w+)", body).group(1)
            if REAL.search(body) and not GUARD.search(body):
                failures.append(f"{path.name}: {name} reaches real data without checking the demo")
    for path, calls in VIEWS.items():
        lines = path.read_text().splitlines()
        for number, line in enumerate(lines, 1):
            # The check on the line itself, or as the guard just before it.
            near = "\n".join(lines[max(0, number - 3):number])
            for call in calls:
                if re.search(call, line) and not GUARD.search(near) and "func " not in line:
                    failures.append(f"{path.name}:{number}: {call} outside the demo check")
    failures += ad_demo_failures()
    for failure in failures:
        print("SIDE DEMO LINT:", failure)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
