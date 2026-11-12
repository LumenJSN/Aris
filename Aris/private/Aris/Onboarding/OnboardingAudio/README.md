# Onboarding sounds

The official build plays short sounds during the onboarding and a recorded greeting. They are not part of this
repository, so a build from it plays the onboarding without them: a missing cue plays nothing, and a missing voice line
is spoken by the Mac's own voice in the onboarding's language, with the captions timed to it.

To add your own, put MP3 files here under these names (any sample rate or channel count; the player converts):

- `sfx/swell.mp3`, `sfx/chime.mp3`, `sfx/whoosh.mp3`, `sfx/pop.mp3`, `sfx/check.mp3`, `sfx/resolve.mp3`: the cues
- `sfx/ambient.mp3`: the bed under the onboarding, looped
- `voice/<language>/greet.mp3` and `voice/<language>/greet-name.mp3`: the two voice lines, for example `voice/ko/`

Only add sounds you are allowed to redistribute.
