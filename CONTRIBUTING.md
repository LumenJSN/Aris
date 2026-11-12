# Contributing to Aris

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

Open an issue with the **Bug report** form. Say which Aris and macOS version you use, which brain (Claude Code, Codex,
Antigravity, or which API), whether the Mac has a notch, and the exact steps: what you said or typed, and what Aris
showed or did.

Don't paste your messages, mail, keys or other personal data. Logs are in `~/.config/aris`; look through what you
attach and cut anything private.

Security problems go through the private form instead; see [SECURITY.md](SECURITY.md).

## Building

You need an Apple silicon Mac with macOS 14 or later and Xcode 26 or later.

```sh
./Scripts/build.sh                 # builds build/Aris.app (ad-hoc signed)
./Scripts/build.sh --agent-only    # only aris-agent and aris-tools
bash Tests/run.sh                  # the test suite; it must end in ALL PASSED
bash Tests/deploy-dry-tests.sh     # the install scripts against a sandbox of fakes
```

[docs/BUILD.md](docs/BUILD.md) explains the parts (the app, its XPC helper, `aris-agent`, `aris-tools`) and the
signing choices.

## Pull requests

1. Fork the repository and branch from `main`.
2. Keep each pull request to one change, and match the style of the code around it: small focused files, plain
   comments that say what the code does for the user, user-visible text through the file's localisation pattern.
3. Write the test first. Pure logic goes in Foundation-only files so `Tests/run.sh` can compile it; a new test file
   is `Tests/<name>-tests.swift` with one entry function, added to the end of the `swiftc` list in `Tests/run.sh`
   and called from `Tests/main.swift`. Tests never touch real data, the real preferences or the installed Aris.
4. Run `bash Tests/run.sh` (and `bash Tests/deploy-dry-tests.sh` if you touched a script); every check should pass.
5. Use a short, conventional commit message, such as `fix: keep the card on screen while it waits` or
   `feat: add Mastodon to the services`.

A few rules Aris keeps:

- **The user is asked before anything that writes, sends, deletes or spends.** A change may add a confirm card; it
  never turns one into something that runs silently. Text from outside (web pages, mail, messages, files, skills)
  stays tainted.
- **Every feature works on every brain.** Nothing is locked to one provider.
- **A reply must be true.** Never "done" for something that was not checked; a failure says what failed and what the
  user can do.
- **No other app's code, artwork, sounds, fonts or prompt texts.**

## Licence

By contributing, you agree that your work is released under the [Apache License 2.0](LICENSE).
