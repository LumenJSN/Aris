<!-- HEADER IMAGE (to add): .github/header-light.png and header-dark.png, the open notch answering a question.
<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset=".github/header-dark.png" /><img alt="Aris: a voice assistant that lives in the MacBook notch." src=".github/header-light.png" width="720" /></picture></p>
-->
<h1 align="center">Aris</h1>

<p align="center">
  <img alt="macOS 14+ on Apple silicon" src="https://img.shields.io/badge/macOS-14%2B_Apple_silicon-000000?logo=apple" />
  <img alt="Xcode 26+" src="https://img.shields.io/badge/Xcode-26%2B-147EFB?logo=xcode&amp;logoColor=white" />
  <a href="LICENSE"><img alt="Apache-2.0" src="https://img.shields.io/badge/license-Apache--2.0-blue" /></a>
</p>

<div align="center">

A voice assistant that lives in the MacBook notch. Hold a key and talk, or type; the AI you already use answers,
and anything that would act on your Mac asks you first.

</div>

> **Use at your own risk.** Aris lets an AI read and act on your Mac: your messages, mail, files, calendar and other
> apps' windows. It asks before anything that writes, sends or deletes, and it is tested hard, but it is a personal
> project, not a product with a warranty. Read [the safety model](#safety-model) and the licence's disclaimer
> ([LICENSE](LICENSE), sections 7 and 8) before you give it your permissions.

## What it does

- **Talk or type in the notch.** Hold <kbd>⌥ Space</kbd> and speak, or click the notch and type. Answers, confirm
  cards and running work show in the notch; history, usage, to-dos and the calendar live in the side notches.
- **Your choice of brain.** Claude Code, Codex (ChatGPT), Antigravity (Gemini), or a model API with your own key,
  including local models in Ollama or LM Studio. Every feature works on every brain. Claude is the recommended one.
- **Works on your Mac.** Messages, Mail, Notes, Calendar, Reminders, Contacts, Finder and files (convert, merge,
  shrink, move, undo), music, timers, the weather, stocks, maps and currency. Other apps' windows can be read and
  operated (through [Peekaboo](https://github.com/openclaw/Peekaboo), downloaded on first use).
- **Sees what you point at.** Ask about the screen, circle something with the gesture, or pick windows to ask about.
- **Dictation.** Hold the right <kbd>⌥</kbd> to type by voice into any app, with a learned dictionary and your own
  writing style.
- **Hands-free conversation**, with on-device end-of-turn detection and barge-in.
- **Teammates.** Background workers (a clone of Aris, Claude Code in a terminal) that take a job and report back.
- **Skills** in the open Agent Skills format (`SKILL.md` plus optional `scripts/`, `references/`, `assets/`), so
  skills made for Claude Code or Codex work unchanged, on every brain. They are off until you turn them on, and each
  is checked by a static scan ([SkillSpector](https://github.com/NVIDIA/skillspector)) and a review by your AI
  before any AI sees it. A skill's scripts run only after you say yes.
- **Memory** you can read and edit: notes Aris keeps about how you like things done, plain Markdown on your Mac.
- **Korean and English**, in the UI, the voice and the answers.

### Screenshots

<!-- SCREENSHOTS TO ADD before or after publishing (none of the owner's real data on screen):
  1. .github/header-light.png and header-dark.png: the open notch with a short answer
  2. a confirm card ("send this message?") with its editable rows
  3. the side notch: history and to-dos
  4. Settings > AI services, showing the brain picker
  5. dictation into a text field
-->
Screenshots are coming.

## Requirements

- A Mac with **Apple silicon** and **macOS 14 Sonoma or later**. The notch's glass look needs macOS 26; older systems
  get a plain dark notch. Macs without a notch are supported too.
- To build: **Xcode 26 or later** (the full app, not only the command-line tools). No paid Apple Developer account.
- At least one **brain**: one of the CLIs below, logged in, or an API key.

## Install

### Download

1. Download `Aris-<version>.dmg` from [Releases](https://github.com/LumenJSN/Aris/releases). The official build
   includes the onboarding's sounds and its recorded Korean greeting. A `.zip` of the same app and a `SHA256SUMS`
   file are attached too; compare the checksum (`shasum -a 256 Aris-<version>.dmg`) with the one in the release notes.
2. Open the DMG and drag **Aris** onto **Applications**.
3. Open Aris. It is **ad-hoc signed and not notarized by Apple** (the project has no Developer ID), so the first time
   macOS refuses ("Apple could not verify Aris"). Click Done, go to **System Settings › Privacy & Security**, scroll
   down and click **Open Anyway** next to the Aris message, then confirm. You only do this once per download.
   (From Terminal instead: `xattr -dr com.apple.quarantine /Applications/Aris.app`.)
4. On first launch Aris sets up its background helper by itself and walks you through the permissions.

Only do this for a copy you downloaded from this repository's Releases page. Each new download is a new program to
macOS: grant the permissions again after an update (if a switch in System Settings already shows on, turn it off and
on, or remove the row with − and add Aris again).

### Build from source

```sh
git clone https://github.com/LumenJSN/Aris.git
cd Aris
./Scripts/build.sh            # builds the app, aris-agent and aris-tools into build/Aris.app, signed ad-hoc
```

Then move `build/Aris.app` to `/Applications` and open it. On first launch Aris sets up its background helper by
itself and walks you through the permissions.

For day-to-day development, `Scripts/deploy.sh` builds, checks, signs, swaps the installed copy and restarts the
helper in one step (and `--rollback` puts the previous build back). [docs/BUILD.md](docs/BUILD.md) explains the
parts, the signing choices and every script.

**Signing.** `Scripts/build.sh` signs ad-hoc, which needs nothing. macOS ties your permissions to the signature, so
with ad-hoc signing every rebuild is a new program and you grant the permissions again. To keep them across rebuilds,
sign with a free "Apple Development" certificate from Xcode (Xcode › Settings › Accounts):
`SIGN_ID="Apple Development" ./Scripts/build.sh`. The project contains no team id; Xcode builds it as is.

A build from source works the same, except that the onboarding sounds of the official build are not in the
repository (see [Notes](#notes)): the onboarding runs without its sounds, and the Mac's own voice speaks the greeting.

## Permissions

Aris asks for each one when a feature first needs it. In System Settings › Privacy & Security every one of them is a
single row, "Aris" (the helper and the tools inside the app are counted as the app).

| Permission | What Aris does with it |
| --- | --- |
| Microphone | hears you while you hold the talk key, during a hands-free conversation, and for its name if you turn the wake word on |
| Speech Recognition | turns what you say into text, on the Mac (an on-device Whisper model is an option) |
| Accessibility | finds and presses buttons and fields in other apps, types for you, reads the selected text and the focused window |
| Screen Recording | sees the screen only when you point at it, circle something or pick a window; password apps and Aris's own windows are always left out |
| Full Disk Access (optional) | reads Messages, Mail and Notes; it never writes there |
| Desktop, Documents, Downloads | moves, converts and restores your files when you ask |
| Calendars, Reminders, Contacts | shows and edits your events and to-dos, finds the person you name |
| Automation | controls Music, Spotify, Notes, Finder, Messages, Mail and the terminal Claude Code runs in, for what you ask |

## Brains

Pick the default in Settings › AI services; saying the name first ("ask Gemini …") picks one for that request.

| Brain | How to add it |
| --- | --- |
| **Claude Code** (recommended) | install [Claude Code](https://docs.anthropic.com/en/docs/claude-code), run `claude` once in Terminal and log in |
| **Codex** | install the [Codex CLI](https://github.com/openai/codex) and run `codex login` with your ChatGPT account |
| **Antigravity** (Gemini) | install Antigravity's CLI and run `agy` once to log in |
| **An API key** | Settings › AI services › API: OpenAI, Anthropic, Gemini API, OpenRouter, Groq, xAI, Mistral or DeepSeek |
| **A local model** | run [Ollama](https://ollama.com) or [LM Studio](https://lmstudio.ai) on the Mac and pick it in the same list |
| **Anything OpenAI-compatible** | add its address, key and model in the same list |

Aris looks for the CLIs in `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`. Keys are kept in the macOS
Keychain. Speech can also go through ElevenLabs or OpenAI with your key; by default the voice is the Mac's own.

Optional: `Scripts/install-claude-hooks.py` (and `install-agent-hooks.py` for Codex and Gemini CLI) show your coding
sessions in the notch and let you answer Claude Code's permission prompts there. Both are dry runs until you pass
`--apply`, and both back up the file they change.

## Privacy

- **On your Mac:** your history, memory notes, schedules, settings, skills and logs (in `~/.config/aris` and the
  app's container), the wake word, the end-of-turn model, dictation's dictionary, and the Mac's speech recognition.
  Aris has no server, no account and no analytics. Its helper listens on `127.0.0.1` only, behind a token.
- **To the AI you chose:** your request, the context it needs (the time, the app in front, what you selected or
  pointed at, the memory notes that apply) and the results of the steps it takes, such as the text of a message you
  asked it to read. That goes to the company behind the CLI or API you picked, under their terms, or stays on the Mac
  with a local model.
- **To other services, only when used:** the weather, stock, maps and currency lookups, a web page you ask about,
  ElevenLabs or OpenAI for speech if you set a key, and GitHub for the downloads on first use (Peekaboo, SkillSpector
  and its Python runtime, the Whisper model).

## Safety model

Every step a brain wants to take goes through one gate in `aris-agent`, whatever the brain. Reading runs without
asking. Anything that writes, sends, deletes, spends or automates another app shows a **confirm card** in the notch
that says exactly what will happen (who gets the message and its words, which file goes where), and waits for your
yes; you can change the values on the card before you say it. A few things are never done (paying, wiping a disk,
touching the system's protected places), and a command the gate cannot read is treated as the riskiest kind. After
you allow the same thing three times in a row, Aris offers to stop asking for it, and Settings lists and revokes
those.

Text from outside (a web page, an e-mail, a message, a file, a skill) is **tainted**: it is handed to the brain as
data, fenced and labelled as not yours, and a turn that has read it can no longer act on its own. From that point
even steps that would normally run need your yes, and nothing learned from such a turn is trusted as your own words.
Sends are confirmed one by one, with the exact text, and Aris checks the window is still the one on the card before
it presses anything.

## Notes

- **Private Apple APIs.** Aris uses some, each looked up at run time and with a public fallback where one exists:
  - AppKit's private glass settings on `NSGlassEffectView` (variant, content lensing, a custom path) and
    `_setHasActiveAppearance:` on the notch window, for the notch's look on macOS 26;
  - CoreGraphics' `CGSSpace*` functions and SkyLight's `SLSRemoveWindowsFromSpaces`, to keep the notch above
    full-screen apps and on the lock screen (with [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow));
  - `_AXUIElementGetWindow`, to match an accessibility element to its window;
  - MediaRemote (through the bundled [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)) for what
    is playing, and DisplayServices for the screen's brightness.

  Any macOS update can change or remove them; this is also why Aris can't be in the App Store.
- **Not notarized.** There is no Developer ID; see [Download](#download).
- No other app's code, artwork, sounds, fonts or prompts are included.
- The onboarding sounds of the official build are not part of this repository: a build from source runs the
  onboarding without them (see [OnboardingAudio](Aris/private/Aris/Onboarding/OnboardingAudio/README.md)).
- Aris is not affiliated with Anthropic, OpenAI, Google or any provider it can talk to; their names and logos belong
  to them and are shown only to say which brain is which.

## Build and test

```sh
./Scripts/build.sh                 # the app, aris-agent and aris-tools, assembled and signed into build/Aris.app
./Scripts/build.sh --agent-only    # only aris-agent and aris-tools (a minute; no Xcode project build)
bash Tests/run.sh                  # the test suite (about 400 files compiled; ends in ALL PASSED)
bash Tests/deploy-dry-tests.sh     # deploy.sh and the installers against a sandbox of fakes
```

The tests compile the Foundation-only parts of the app, the helper and the tools into one program and run them with a
throwaway home folder; they never touch your real data, preferences, permissions or the installed Aris.

## Credits

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax (MIT): on-device speech-to-text.
- [Smart Turn](https://github.com/pipecat-ai/smart-turn) by Daily (BSD-2-Clause): the bundled end-of-turn model.
- [Bot Avatars](https://github.com/Jakubantalik/Libraries.dev) by Jakub Antalik (MIT): Aris's face and the
  teammates', ported to Swift in `Packages/BotAvatarsKit`.
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den Berg (BSD-3-Clause).
- [Defaults](https://github.com/sindresorhus/Defaults) and [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
  by Sindre Sorhus, [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) by Lakr Aream,
  [MacroVisionKit](https://github.com/TheBoredTeam/MacroVisionKit) (all MIT),
  [AsyncXPCConnection](https://github.com/ChimeHQ/AsyncXPCConnection) by Chime (BSD-3-Clause),
  [swift-argument-parser](https://github.com/apple/swift-argument-parser) by Apple (Apache-2.0).
- [skill-creator](https://github.com/anthropics/skills) by Anthropic (Apache-2.0): the built-in skill that writes new
  skills.
- Downloaded on first use, not part of this repository: [Peekaboo](https://github.com/openclaw/Peekaboo) (MIT),
  [SkillSpector](https://github.com/NVIDIA/skillspector) by NVIDIA (Apache-2.0) with [uv](https://github.com/astral-sh/uv)
  and Python, and the Whisper models.

The full notices are in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) and [NOTICE](NOTICE).

## License

Aris is released under the [Apache License 2.0](LICENSE). Copyright 2026 Lumen. The bundled third-party code and
models keep their own licences; see [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Please report security problems privately as
described in [SECURITY.md](SECURITY.md).
