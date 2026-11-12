# Security Policy

## Supported versions

Only the latest release and `main` get fixes.

| Version | Supported |
| ------- | --------- |
| Latest release, `main` | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

Please **don't open a public issue**. Use the private form instead:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability**.
3. Describe the problem, the Aris and macOS versions, the brain you use, and the steps to reproduce it.

Only the maintainer can see the report. You'll usually get a reply within a week, and you'll be credited in the
release notes unless you'd rather not be.

What counts, for example: a way for text from outside (a web page, a message, a mail, a file, a skill) to make Aris
act without a confirm card; a card that shows something other than what then happens; another program on the Mac
using Aris's helper, its tools or the permissions granted to Aris; a key or token leaving the Keychain or Aris's
folder; a way around the commands Aris never runs.

## Worth knowing

- Aris is not notarized by Apple; the README explains how to open a downloaded build, and building from source.
- Aris has no server. Its helper listens on `127.0.0.1` only and checks a token and the caller's code signature.
- What Aris sends goes to the AI you chose and to the services you use; see "Privacy" in the README.
- Aris uses private Apple APIs (listed in the README); a macOS update can change them.
