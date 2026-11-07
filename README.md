# Space Fighter — Godot 4.7.2 / v1.1.0

Migration of the retired Unity port, using `reference/web/www` (the original
540x960 Canvas game) as the gameplay and numeric source of truth.

## v1.1.0 visual reset

- **Anime cel-shaded art**: all player/enemy/boss/drone/crate sprites re-rendered
  in Blender with two-tone shading, dark plum outlines, hand-painted highlights
  and supersampled anti-aliasing (`tools/artgen_anime.py`).
- **Key visual**: a 3/4 cel-shaded hero ship (`assets/keyart/hero.png`) and a
  3D beveled title logo (`assets/keyart/logo.png`) rendered for the menu.
- **Adaptive full-screen layout**: `stretch/aspect="expand"`, dynamic
  `CFG.VIEW`, safe-area insets (notch/navigation bar) and HUD/controls anchored
  to the real viewport. Verified at 540x960, 540x1061 (long phone), 720x960
  (tablet) and on an Android emulator at 1080x1920 / 1080x2400 with hardware
  GPU passthrough.
- **New UI**: cream sticker panels, ink outlines, candy-colored chips/buttons,
  live boss bar, pause and results cards, floating combo text, redesigned touch
  controls.
- **New background**: animated FBM nebula shader, three parallax star layers,
  cel-shaded planet/moon, gameplay-only bottom dimming for bullet readability.
- **New FX**: explosions, shards, shockwave rings, hit sparks, pickup text,
  screen shake, engine flames, dash afterimages and bullet-type silhouettes.
- **New app icon** generated from the 3/4 hero render.

![menu](docs/shots/ui_v110_menu.png)
![action](docs/shots/ui_v110_action.png)
![boss](docs/shots/ui_v110_boss.png)
![long phone](docs/shots/android_v110_tall_play.png)
![tablet](docs/shots/ui_v110_tablet.png)

## Status

- [x] Godot **4.7.2 stable** installed, export templates installed
- [x] Project skeleton at 540x960 design size, portrait, `canvas_items`
      `expand` stretch + dynamic `CFG.VIEW` + safe-area insets
- [x] Playable core: keyboard + mouse/touch drag, pulse auto-fire, four enemy
      archetypes, aimed/fan/ring fire, swept collision, graze, score/lives,
      pause/restart, difficulty keys 1/2/3
- [x] Numeric gate `tools/verify_numbers.gd` (**76 checks**, includes behaviour assertions)
- [x] **Cel-shaded sprite art (v1.1.0)**: player + 12 enemy hulls + 3 bosses +
      drones + crates re-rendered in Blender into `assets/ships/` (94 PNGs),
      including hit-flash masks and boss rings. Drawn via the `ShipArt` contract
      (visual outer edge = radius, canvas side = radius / 0.46); polygon fallback
      kept if a texture is missing.
- [x] **App icon (v1.1.0)**: cel-shaded 3/4 hero on a pastel nebula
      (`assets/icons/`), wired into the project icon, Windows exe icon and
      Android adaptive launcher icon.
- [x] Windows release export: `build/windows/SpaceFighter.exe` (v1.1.0.0)
- [x] Android APK: `SpaceFighter-Godot-v1.1.0.apk` (41 MB, portrait, target SDK
      36, release-signed with the project keystore)
- [x] On-device install verified: Android 36 emulator with hardware GPU
      (1080x1920 and 1080x2400), versionName 1.1.0 / code 10, no black bars,
      touch controls work, 0 Godot script/shader errors
- [x] Release signing: project keystore (CN=Space Fighter, O=sctale), v2/v3 verified
      (`apksigner verify --verbose`)
- [x] Touch controls: 星爆 / 冲刺 / 换线 rings + top-right pause + menu buttons
- [x] Touch controls: focus toggle (精准) + difficulty chips in the menu
- [x] Bundled Noto CJK subset (`assets/fonts/AuroraCJK.ttf`, 267 KB, 938 mapped glyphs)
- [x] Numeric parity: enemy hit radius `size * 0.78`, enemy bullet speed
      `min(300, 150×(1+tier×0.14))` (web `entities.js:1263,1393`)
- [x] All 12 enemy behaviours, elite affixes, 6 movement / 9 fire modes,
      zone/tier scaling, kill-quota director
- [x] Three weapon lines (charge/detune/resonance), 5 levels, swap/cycle,
      homing swarm, piercing prism, overdrive; shields/hull, dash, nova
- [x] Drones (4 kinds, unique pick), supply crates (10 kinds, magnet),
      nova/overdrive, combo multiplier, grading (S/A/B/C)
- [x] Three bosses × 22 original named moves × per-phase fixed sequences,
      66%/30%/12% phases, break gauge + stun, 0.5 s telegraph with colour families
- [x] 10 zone skies + soft nebulae, procedural SFX (shot/hit/boom/pick/nova),
      menu / pause / results screens with persisted best score
- [x] Wave director: line / V / twin-column / cluster / pincer formations,
      elite squad every 4th wave, boss at each zone quota
- [x] Git repository + GitHub release (sctale/SpaceFighter-Godot)

## Run

```bash
godot --path D:\V-Coding\space-fighter-godot
```

Controls: WASD/arrows move, Shift focus, mouse/touch drag, 1/2/3 difficulty,
P/Escape pause, R restart.

## Numeric gate

```bash
godot --headless --path D:\V-Coding\space-fighter-godot \
  --script res://tools/verify_numbers.gd
```

Expected: `VERIFY_OK checks=76` and exit code 0.

## Export

```bash
# Windows debug
godot --headless --path D:\V-Coding\space-fighter-godot \
  --export-debug "Windows Desktop" build/windows/SpaceFighter.exe

# Android debug APK (requires Android SDK + JDK; Godot settings auto-detected both)
godot --headless --path D:\V-Coding\space-fighter-godot \
  --export-debug "Android" build/android/SpaceFighter.apk
```

The APK is debug-signed with Godot's generated debug keystore. A release build
needs an owned keystore before distribution.

## Reference

`reference/` is excluded from Godot import (`.gdignore`). It contains the original
web source, design docs, and Blender art generator. Do not edit it as game code;
port from it.

## Migration rules

1. Keep the 540x960 design coordinates and original numeric constants; the
   runtime viewport may expand to any phone aspect (`CFG.VIEW`), but gameplay
   values stay in design pixels. Do not reintroduce the Unity 0.025 world scale.
2. Player hit radius is **4.6 px**, graze radius **28 px**; the drawn hull is
   deliberately much larger (32 px visual radius).
3. Use swept segment-circle collision for bullets; do not use per-frame point
   checks.
4. Add a gate assertion before adding a new subsystem, then port the web logic.
5. Keep the game playable after each slice; do not port UI/audio before the core
   loop and collisions are verified.
6. Sprite sizing follows the Unity `ShipArt` contract: the PNG canvas's max
   radius is `0.46 × edge`, so to make the visual outer edge equal the hit
   radius, draw the texture at `side = radius / 0.46`, centered. Player hull
   visual radius is 36 px (78.3 px canvas); enemy hulls are pre-rendered
   nose-down, player nose-up — do not rotate them 180°.

## Art provenance

The v1.1.0 sprites are re-renders of the archived Unity geometry using the
project's own cel-shading pipeline, not the original PBR renders:

- `tools/artgen_anime.py` — imports `reference/artgen/blender/gen_art.py`
  (read-only source of the procedural models), swaps in `tools/anime_toon.py`
  cel materials (two-tone shading, AO, diagonal gloss, Fresnel rim, Freestyle
  outer/inner lines), renders at 2x and downscales to the existing 512/384/640
  canvases. The `0.46 × side` art contract, mask and boss ring layers are
  unchanged.
- `tools/artgen_keyart.py` — 3/4 hero ship and 3D title logo.
- `tools/gen_icon_anime.py` — legacy + adaptive launcher icon.
- `assets/ships/*.png` (94 files) and `assets/keyart/` were produced by these
  scripts; `*_mask.png` are white silhouettes for hit-flash.
- Bullets stay procedural; the legacy `bullet_*.png` files are not used.

Rebuild examples:

```bash
blender -b --factory-startup --python tools/artgen_anime.py -- \
  --only player_pulse,boss_gatekeeper --out build/art_anime --samples 24
blender -b --factory-startup --python tools/artgen_keyart.py -- --only hero,logo
python tools/gen_icon_anime.py
```

## Release signing

Release APKs are signed with the project keystore (kept **local only**,
`keystore/` is gitignored):

- keystore: `keystore/spacefighter.keystore`
- alias: `spacefighter`, store/key password: `spacefighter`
- certificate: `CN=Space Fighter, OU=Games, O=sctale`

Export: `godot --headless --path . --export-release "Android" build/android/SpaceFighter-release.apk`.
The debug keystore (`CN=Godot`) produces a different signature, so switching
between them requires uninstalling the app first.
