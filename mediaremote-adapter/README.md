# mediaremote-adapter (third-party, vendored)

A copy of [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den Berg and
contributors, under its BSD 3-Clause licence (reproduced in [../THIRD_PARTY_LICENSES](../THIRD_PARTY_LICENSES)).

Apple's `MediaRemote.framework` is private, and a sandboxed app can't read what is playing from it directly. Aris
starts `mediaremote-adapter.pl` as a child process; the script loads `MediaRemoteAdapter.framework`, which streams
the now-playing state as JSON lines and takes play, pause and skip commands.

| File | In the app |
| --- | --- |
| `mediaremote-adapter.pl` | `Contents/Resources`, started by Aris (`stream`, `send`) |
| `MediaRemoteAdapter.framework` | `Contents/Frameworks`, loaded by the script |
| `MediaRemoteAdapterTestClient` | `Contents/Resources`, the adapter's own check that it works on this macOS (`test`) |

The script is upstream's `bin/mediaremote-adapter.pl` at tag `v0.7.7` (commit `e3ff502`). The framework and the test
client are builds of upstream's source at that tag, ad-hoc signed; they can't be checked bit for bit against it, so
when updating, prefer building them yourself from the tag (`cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake
--build build`), replace the three files, and note the new tag here.
