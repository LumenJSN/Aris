# Building and installing Aris

## What Aris is made of

Aris is **one bundle**. Everything a user installs is `Aris.app`:

| Part | Source | Built by | Ends up in |
| --- | --- | --- | --- |
| The app (with its XPC helper inside) | `Aris/`, `ArisXPCHelper/`, `Shared/`, `Packages/BotAvatarsKit` | Xcode (`Aris.xcodeproj`, scheme `Aris`) | `Aris.app` |
| The helper, `aris-agent` (a launchd login agent on 127.0.0.1:23351) | `ArisAgent/` plus about 30 files from `Aris/`, `ArisTools/`, `Shared/` | `swiftc`, from the list of files in `Tests/build-agent.sh` | `Aris.app/Contents/MacOS/aris-agent` |
| The tools, `aris-tools` (the one command the AI brains may run) | `ArisTools/` plus about 15 shared files | the same script | `Aris.app/Contents/MacOS/aris-tools`; `~/.config/aris/aris-tools` is a link to it |
| The built-in skill and the skills runtime list | `ArisSkills/` | copied by `Tests/assemble-app.sh` | `Aris.app/Contents/Resources/skills/` |

`Aris.xcodeproj` has two targets, the app and the XPC helper. The helper and the tools are not Xcode targets (their
list of source files is `Tests/build-agent.sh`), so pressing Build in Xcode gives an app that starts and says it has
no helper inside it. `Scripts/build.sh` builds all three and `Tests/assemble-app.sh` puts them together and signs
everything, inside-out.

**One row per permission.** A program that launchd starts from inside `Aris.app/Contents/MacOS` is charged to the app
by macOS, so System Settings shows one row, "Aris", for Accessibility, Screen Recording, Full Disk Access, the folder
consents and Automation (this mapping is observed behaviour, not documented by Apple).

**The app installs its own helper.** At every launch its unsandboxed XPC helper writes
`~/Library/LaunchAgents/com.lumenjsn.aris.agent.plist` for the `aris-agent` inside the app it sits in (only when it
differs), loads it, and waits until it answers with the app's own build. With the app moved to the Trash the helper
stops by itself. `aris-agent` serves only as launchd's job under Aris's label, `aris-tools` runs only with that job
behind it (or on the permissions of the program that started it, such as Terminal), and both are signed with the
hardened runtime (`ArisAgent/ArisOrigin.swift`).

## What you need

1. **A Mac with Apple silicon.** The helper and the tools are compiled for `arm64` only. The lowest macOS is 14.0
   (the project's `MACOSX_DEPLOYMENT_TARGET`); frameworks that only exist on newer systems are weak-linked.
2. **Xcode 26 or later** (the full app). Swift packages are fetched on the first build, so it needs the network.
3. **A way to sign**, see "Signing". Nothing here needs a paid Apple Developer Program membership.
4. **At least one brain**: Claude Code (`claude`), Codex (`codex`) or Antigravity (`agy`), installed and logged in,
   or an API key entered in Aris's settings. The helper looks for the programs in `~/.local/bin`,
   `/opt/homebrew/bin` and `/usr/local/bin` only.

## Building

```sh
./Scripts/build.sh                 # build/Aris.app, ad-hoc signed; move it to /Applications and open it
./Scripts/build.sh --agent-only    # only aris-agent and aris-tools, into build/agent
```

To build only the app, for a look at the UI: open `Aris.xcodeproj` and build the `Aris` scheme, or
`xcodebuild -project Aris.xcodeproj -scheme Aris -configuration Release -derivedDataPath build-release CODE_SIGNING_ALLOWED=NO build`.

### Rebuilding an installed copy: `Scripts/deploy.sh`

For development, `Scripts/deploy.sh` does, in this order: build the app (Release); build and check `aris-agent` and
`aris-tools`; start the new app in a sandbox for 10 seconds (`Tests/launch-smoke.sh`); put both programs into the
app, sign it all in a staging folder and verify it; and only then keep the installed app aside, quit Aris, swap in
the new one, restart the helper once and open the app. If anything fails before the swap, the installed Aris is
untouched; if the swap fails, the previous build is put back. `./Scripts/deploy.sh --rollback` puts back the bundle
the last deploy replaced, and `--clean` removes the copies it keeps. It installs into `/Applications/Aris.app`
(`APP=...` to change). Its build folders (`build-release/`, `deploy-stage/`, `deploy-previous/`) are ignored by git.

`Scripts/install-aris-agent.sh` is its helper (`--stage` builds the two programs, `--wait-idle` waits for the agent
to finish its work, `--restart` restarts it once).

## Which build is running

Every program carries the commit it was built from: the app in its `Info.plist` (`ArisCommit`), `aris-agent` and
`aris-tools` compiled in (`~/.config/aris/aris-tools --version`). A build from uncommitted changes is stamped
`<commit>-dirty`; a build made by hand in Xcode says `dev`. When the app finds the helper is another build, it
restarts the helper from itself and says so in its log (subsystem `com.lumenjsn.aris`).

## Signing

macOS ties the permissions a user grants (Microphone, Accessibility, Screen Recording, Full Disk Access, keychain
items) to *who signed* the program. How Aris is signed decides whether those survive a rebuild.

| Signed with | Permissions across rebuilds | Needs |
| --- | --- | --- |
| Ad-hoc (`Scripts/build.sh`'s default; `SIGN_ID=- ./Scripts/deploy.sh`) | **lost at every build**: each build is a new program to macOS, even though System Settings may still show the switches on | nothing |
| An "Apple Development" certificate (`SIGN_ID="Apple Development"`; `deploy.sh`'s default) | kept | an Apple ID signed in to Xcode (free: Xcode › Settings › Accounts › Manage Certificates). The free certificate lasts a year; renewing it keeps the permissions. |

The project has no team id in it: Xcode builds it unsigned (`CODE_SIGNING_ALLOWED=NO`) and the scripts sign
afterwards, so nobody has to edit the project to build. If you prefer to sign in Xcode itself, pick your team in the
target's Signing & Capabilities; don't commit that change.

`deploy.sh` never falls back to ad-hoc in silence: with no identity in the keychain it says so and what that costs,
and when the installed Aris is signed with a certificate it stops instead of replacing it with an ad-hoc build,
unless `SIGN_ID=-` says that is wanted. An ad-hoc build is never signed with the hardened runtime on the app itself
(library validation would refuse the bundled `MediaRemoteAdapter.framework`); the helper and the tools always are.

A build for other people would need a Developer ID certificate and Apple's notarization, which need the paid
programme; this project has neither, so a downloaded build has to be allowed by hand (see the README).

## Tests

```sh
bash Tests/run.sh                  # compiles about 400 files with the tests into one program and runs it (5 to 25 minutes)
bash Tests/deploy-dry-tests.sh     # deploy.sh, install-aris-agent.sh, the hooks installers and the status line, against fakes
```

`Tests/run.sh` must end in `ALL PASSED`; every line that does not start with `ok` is a failure. The tests run with a
throwaway home folder and preferences domain and fail if they wrote into your real `~/Library/Preferences`. They
never use your real messages, mail, calendar, files, permissions, or the installed Aris.

## Optional: coding sessions in the notch

`Scripts/install-claude-hooks.py` adds Aris's hooks and a status line to Claude Code's `~/.claude/settings.json`;
`Scripts/install-agent-hooks.py` does the same for Codex (`~/.codex/hooks.json`) and Gemini CLI. Both print a diff
and change nothing until `--apply`, keep other hooks, and back the file up first.
