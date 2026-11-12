# Ported from

**Upstream:** https://github.com/Jakubantalik/Libraries.dev — MIT (see `LICENSE`)
**Commit:** `1c87c11` ("img-fx 0.5.2 — mosaic shader perf", 2026-11-03), synced 2026-11-03.
First vendored at `bfb396b`; `packages/bot-avatars` is byte-for-byte the same at both
commits (the only commit between them touches `packages/img-fx`), so the sync below
closes what the iOS port had never taken from the web source, not new upstream work.

`Sources/BotAvatarsKit` started as an unmodified copy of
`packages/bot-avatars/ports/ios/BotAvatarsKit` at that commit (the rig, the
renderer and the plastic material, a port of an earlier web engine). The
`fabric` shading was then ported line for line from the web source at the
same commit, `packages/bot-avatars/src`, keeping the web's names so later
upstream changes can be followed.

## What fabric was ported from

| Swift (this package)            | Web (`packages/bot-avatars/src`)                                                              |
| ------------------------------- | --------------------------------------------------------------------------------------------- |
| `BotAvatarFabricForm.swift`     | `plastic.ts`: `buildForm` (the web's current form), `reliefFor`, `edgeLift`, `softMask`, `rimOf`, `ringOf`, `ringOrder`, `reach`, `bilerp` |
| `BotAvatarFabricPile.swift`     | `plastic.ts`: the `fabric: a plush pile` section — `Fur`, the `FUR_*`, `LOCK_*`, `PILE_*`, `STRAND_*`, `FILM_*`, `HALO_*` constants, `furTier`, `hash2`, `hash3`, `rng`, `valueNoise`, `valueNoise3`, and `furJob` steps 1–2 (the flow grid, the crease, the locks, the hollows) |
| `BotAvatarFabricFleece.swift`   | `plastic.ts`: `furJob` step 3 (`fibreLight`, `lockSeen`, the strand kernels and buffer, the fleece, the lock height's spread) |
| `BotAvatarFabricHairs.swift`    | `plastic.ts`: `furJob`'s single hairs, fuzz, tufts and halo (mask, haze, core) |
| `BotAvatarFabricMatcap.swift`   | `plastic.ts`: `KEY_EL`, `BACK_SOFT`, `fabricKey`, `fabricBack`, `backFromKey`, `FurLights`, `stockLights`, `capFrame` (its `D` and `K` axes), `vivify`, `srgb`, `buildFabricMatcap`, `FRONT_FADE`, `shadeTexels` (with the lift), `gapFilm`, `tipFilm`, `sheenFilm`, `furCut` |
| `BotAvatarFabricHalo.swift`     | `plastic.ts`: `raysOf`, `sliceGradient` (the conic ramp), `hazeColor`, `brightest`, `stackReach`, `haloStretch`, `haloRays`, `haloMiss`, `measureMiss` |
| `BotAvatarFabric.swift`         | `plastic.ts`: the per-instance `State` and `drawPlasticCap` on its fabric path (the relief: the far half, its shade ramp, the equator, the near half, the front; the halo laid over, cut and cross-faded; the films) |
| `BotAvatarFabricBakes.swift`    | `plastic.ts`: `formFor`, `furReady`, `furFor`, `warmPlastic(…, fabric = true)`, `lightBin`, `furKey`, `bakesPending`, `onLanded` |
| `BotAvatarFabricGate.swift`     | `BotAvatar.tsx`: `SHOW_WITHIN`, `showReady`, `showWhenBaked` and the `opacity 0.3s ease-out` transition |
| `BotAvatarLighting`, fabric props | `draw.ts`: `LIGHT_DEFAULTS`, `backOf`, the fabric dispatch in `draw` (`drawSolid`'s `plush`, the rig's `bx/by/round`, the material's `front/shine/sheen/backSoft`); `types.ts` and `BotAvatar.tsx` for the props' defaults and ranges (`q()` rounding of the pile's style) |

Not ported (Pro features, not wanted): `wear.ts` — hats, glasses,
headphones, bow ties. Nothing of it is needed by fabric.

## Synced from the web source at 1c87c11 (2026-11-03)

The iOS port (`ports/ios`) was a port of an earlier web engine. These now follow
`packages/bot-avatars/src` line for line:

| Swift (this package)            | Web                                                                                           |
| ------------------------------- | --------------------------------------------------------------------------------------------- |
| `BotAvatarEngine.swift`         | `engine.ts` whole: the idle gaze (`GAZE_*`, `nextGaze`, `Wander.aim`, corners held 2.6–4.4 s and swung across), `setTurn` and `turnK`, the eyes leading a head turn (`gazeLead`), the default state's wander (2.6–5.4 s holds, eyes 0.6–2.2 s at 13), no winks (one blink for both eyes), `SWITCH_TO` 1.2 / 0.7 / 1.4 and `SWITCH_FROM_SLEEP` 1 on a sine ease every time, the jump's three-part landing (`SQUASH_PEAK`, `risePulse`, `groundShape`, the press, hold and rise) in `flipDuration` and the flip, and the working state's exit (the last hop's hold and rise, `exitFor`, instead of `HOP_EXIT`) |
| `BotAvatarJumpConfig`           | `JumpConfig` / `JUMP_DEFAULTS`: `groundTime` 0.11, `groundEase`, `riseTime` 0.33, `riseEase` |
| `BotAvatarDraw.swift`           | `draw.ts`: the eyes' mimic (taller looking up, shorter down, wider from a sideways glance: `past`, `up`, `side`, `tall`, `wide`) and the face clipped to the front's outline (`fm0 … ffo`; for fabric's cushion at 0.55 of `surfaceAt` under the face) |
| `FabricBakes.surfaceAt`         | `plastic.ts`: `surfaceAt` (the finest form made at that depth; the web takes the latest made) |
| `BotColor.richer`               | `color.ts`: `richer` and its OKLab helpers |
| `BotAvatarPreset`, `botAvatarPresets` | `presets.ts`: the palette as it is now (clover `#41C4FF`, flower `#2FCB7A`, hexagon `#EB7575`, cat `#EAA06F`, pebble `#ABC793`, puddle `#EE8BDB`) and the types' own `brightness` / `saturation` (clover 1.2 / 1.59, star 1.1 / 1.84, cat 1.22 / 1.88) |
| `BotAvatarModel.drawConfig`     | `BotAvatar.tsx`: brightness and saturation default to the type's own, the shade takes saturation up to 1.5, the rest is `vivid` (`richer` on the body colour, and `DrawConfig.vivid` into fabric's material) |
| `BotAvatar`                     | `BotAvatar.tsx`: `shading` defaults to `fabric`; `turn` (0–2, default 1); the jump's `groundTime` ≥ 0 and `riseTime` ≥ 0.05; a click pokes only while it runs (`!frozen`) |

`ExistingShadingsTests` re-pins clover's and cat's stills (their palette colours
changed); cloud's is the same as before. `UpstreamMotionTests` pins each behaviour above.

## Where the port differs from the web

- **Plastic is the iOS port's.** This package's plastic keeps its own (older)
  form and slice draw; only fabric uses the web's current form and relief (the
  web's 0.2.0 inflated plastic body is not ported). Its pinned stills are
  checked by `ExistingShadingsTests`.
- **The light defaults of the other shadings** stay this package's
  (0.35 / 1.3 / 265 / 0.5 / 1.55); the web's `other` light is now 300°.
- **Bakes** run as one job per pile on a serial background queue instead of
  idle-time steps on the main thread; the steps and their order (and so the
  random draws) are the web's. The web's "bake the smallest pile first while
  a large one bakes" shortcut is left out; the same shape's pile at another
  size or light still stands in while one bakes, as on the web.
- **Canvas compositing** is a SwiftUI `GraphicsContext`: the body's buffer
  and the sprites are layers drawn each frame (the GPU's work) rather than
  canvases rebuilt per matcap. A canvas's `destination-in` clears outside
  what it draws; here the same cut is a clip to the mask's alpha. A
  context's `destination-atop` reaches only as far as the halo's square.
- **`vivid`** reaches fabric's material; this package's older plastic does
  not read it.
- **The face** is drawn at full opacity on fabric, as on the web. On this
  package's (older, extruded) plastic it is clipped to the front cap's slice.
- **Antennae** of a fabric body take this package's plastic.
- **Showing:** a fabric avatar waits for its pile and fades in. A later
  change of shape, size or light holds the last look (in its own pile,
  resampled) until the new pile lands, as the web's `hold()` does; the
  held look keeps animating where the web's canvas freezes.
- **Presentation:** a standalone fabric avatar's canvas renders
  asynchronously (RenderBox's encoding off the main thread).

## Aris additions (not upstream)

- **`BotAvatarSprite.swift`**: `BotAvatar.drawConfig(scale:theme:)` (the still
  config a view draws with, built by the view's own `BotAvatarModel.drawConfig`)
  and `botAvatarFabricIsBaked(_:box:)`. Aris runs the Sim offline — upstream's
  motion, untouched — into sprite atlases (the idle, working and sleeping loops
  as shuffled variants, a poke's variant, the rest poses, the pointer poses) and
  plays them on the render server, so the fabric is never redrawn per frame.
  `botAvatarsKitRenderVersion` (`1c87c11+aris.2`) names what a baked frame
  depends on besides its look; Aris keys its atlases cached on disk with it, so
  bump it whenever the drawing or the motion changes.
- Removed at the 1c87c11 sync: `BotAvatar.gaze(_:)`, `BotAvatar.poked(_:)` and
  `BotAvatarPose.rest(_:yaw:)` (Aris's own glance, poke count and baked yaw turn;
  Aris now plays upstream's states as they are).
