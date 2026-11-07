# Space Fighter — Godot 4.7.2 / v1.3.1

Migration of the retired Unity port, using `reference/web/www` (the original
540x960 Canvas game) as the gameplay and numeric source of truth.

## v1.3.1 GS review performance pass

Claude-Code-Game-Studios review (`gs-code-review`) over the whole project.
Findings fixed in this patch:

- **Per-frame hex colour parsing removed**: enemy base/accent colours and the
  player weapon tint are cached instead of `Color.html()` every frame
  (up to 84 parses/frame at 42 enemies).
- **Enemy muzzle colour cached** on `Enemy.setup()` instead of re-parsing the
  glow string on every shot.
- **FX particle ceiling**: 420 particles / 40 floating texts, oldest dropped
  first, so stacked novas/explosions cannot grow draw cost unbounded.
- Remaining suggestions are architectural (split `main.gd` 1.6k-line god object
  into wave/collision/upgrade modules) and tracked as follow-up, not blocking.

## v1.3.0 boss roster, per-zone BGM and longer zones

- **Six bosses**: three new cel-shaded silhouettes — 塔罗斯 / 铁壁 (wide
  dreadnought), 许德拉 / 噬星者 (vertical serpent), 塞拉弗 / 裁决者 (X-wing
  seraph) — rendered with the same Blender anime pipeline. Zones rotate all six
  (`(zone-1)%6`), each with its own 3-phase sequence and bullet tint.
- **Per-zone BGM**: ten synthetic 29–53 s loops (`tools/gen_music.py`, OGG,
  ~3.4 MB total) in `assets/music/`; `MusicPlayer` fades in on zone change
  (−40 → −12 dB) and pauses with the pause menu.
- **Longer zones**: kill quota `12 + 4×zone` → `28 + 4×zone`, plus a 40 s
  minimum dwell time (`ZONE_MIN_TIME`); a zone now runs ~45 s instead of ~20 s
  before the boss.
- **Ship switching**: the hull art did change, but the second weapon line
  unlocked too late. The first supply crate now guarantees 棱镜, the 换线
  button shows `锁定` until two lines are unlocked, and an early tap shows a
  hint.
- Gate `checks=85`; selftest `n=5` adds BGM and zone-pacing assertions.
- Android versionName `1.3.0` / code `14`.

![v1.3.0 dreadnought](docs/shots/ui_v130_boss_dreadnought.png)
![v1.3.0 serpent](docs/shots/ui_v130_boss_serpent.png)
![v1.3.0 seraph](docs/shots/ui_v130_boss_seraph.png)
![v1.3.0 ship switch](docs/shots/ui_v130_switch.png)

## v1.2.1 gameplay integrity + two-round polish

Two review/optimization rounds after v1.2.0. Correctness first, then build
and readability polish.

- **Per-frame player collision**: bullet-vs-player, body contact and grazing
  were nested inside the enemy-death callback, so the player was effectively
  invulnerable and graze fired only on kill frames. They now run in
  `_resolve_player_hazards()` every frame, aligned with the web `collide()`.
- **Death closes the draft**: a lethal hit can no longer leave the three-card
  draft covering the results screen.
- **No dead upgrade cards**: hull/shield/speed cards are filtered out at their
  caps; each card shows its current `×N` stack.
- **Zone progress bar** under the `星区` chip; results now report
  `擦弹 / 裂隙`.
- **Headless self-test**: `-selftest` asserts hit / graze+drop / death-closes-draft.
- Android versionName `1.2.1` / code `13`; numeric gate `checks=81`.

![v1.2.1 zone draft](docs/shots/ui_v121_upgrade.png)
![v1.2.1 action](docs/shots/ui_v121_action.png)
![v1.2.1 results](docs/shots/ui_v121_results.png)

## v1.2.0 gameplay innovation

Benchmarked against Touhou (graze/bomb risk-reward), DoDonPachi (bullet-cancel
economy), Raiden/Sky Force (mobile readability and power-ups), Archero/Vampire
Survivors (in-run build choices) and Hades (three-choice boons). Gaps found:
graze had no mechanical payoff, and there was no inter-zone build agency.

- **裂隙碎片 (Rift Motes)**: every grazed bullet drops a magnetized shard.
  Collecting it adds score, extends the combo window, charges nova, and fills
  the new HUD `裂隙` counter. Grazing becomes a deliberate risk/reward loop
  instead of a hidden stat.
- **星区突破 three-card draft**: after every boss, the game freezes and offers
  3 of 10 run upgrades (damage, drone rate, max hull, shield, nova gain,
  overdrive duration, speed, crate rate, boss damage, rift resonance). Choices
  stack across the 10 zones and change how the run is played.
- No new touch button was added; the draft is modal and finger-friendly, and
  all upgrades are applied through existing systems.

![v1.2.0 rift motes](docs/shots/ui_v120_motes.png)
![v1.2.0 zone draft](docs/shots/ui_v120_upgrade.png)
![v1.2.0 action](docs/shots/ui_v120_action.png)

## v1.1.1 two-round polish

- **Cel-shaded planet/moon shader**: hard-banded spheres with ink edges and a
  ring, replacing the flat half-disc background orbs.
- **Mobile-first hints**: Android/phone menu now shows touch instructions
  (拖动屏幕 / 右下角技能 / 右上角暂停 / 换线键) instead of keyboard keycaps.
- **HUD Chinese pass**: 得分 / 最高 / 擦弹 / 星区; removed mixed English labels.
- **Three-button skill cluster**: 星爆 / 冲刺 / 换线; the 精准 slow-aim button
  and Shift focus mode were removed entirely.
- **Motion polish**: menu↔game fade, pause/results card slide-in, score count-up,
  smooth boss HP bar, start-button shimmer and arrow bounce.
- Android versionName `1.1.1` / code `11`; numeric gate `checks=75`.

![v1.1.1 menu](docs/shots/ui_v111_menu.png)
![v1.1.1 action](docs/shots/ui_v111_action.png)
![v1.1.1 tall phone](docs/shots/android_v111_tall_play.png)

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
- [x] Numeric gate `tools/verify_numbers.gd` (**85 checks**) plus headless
      `-selftest` behaviour assertions (`SELFTEST_OK n=5`)
- [x] **Cel-shaded sprite art**: player + 12 enemy hulls + **6 bosses** +
      drones + crates re-rendered in Blender into `assets/ships/`,
      including hit-flash masks and boss rings. Drawn via the `ShipArt` contract
      (visual outer edge = radius, canvas side = radius / 0.46); polygon fallback
      kept if a texture is missing.
- [x] **App icon (v1.1.0)**: cel-shaded 3/4 hero on a pastel nebula
      (`assets/icons/`), wired into the project icon, Windows exe icon and
      Android adaptive launcher icon.
- [x] Windows release export: `build/windows/SpaceFighter.exe` (v1.3.1.0)
- [x] Android APK: `SpaceFighter-Godot-v1.3.1.apk` (portrait, target SDK
      36, release-signed with the project keystore)
- [x] On-device install verified: Android 36 emulator with hardware GPU
      (1080x1920 and 1080x2400), versionName 1.3.1 / code 15, no black bars,
      touch controls work, 0 Godot script/shader errors
- [x] Release signing: project keystore (CN=Space Fighter, O=sctale), v2/v3 verified
      (`apksigner verify --verbose`)
- [x] Touch controls: 星爆 / 冲刺 / 换线 rings + top-right pause + menu buttons
- [x] Bundled Noto CJK subset (`assets/fonts/AuroraCJK.ttf`, 296 KB, 817 chars)
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

Controls: WASD/arrows move, mouse/touch drag, Tab switch weapon, Space dash,
X nova, 1/2/3 difficulty, P/Escape pause, R restart.

## Numeric gate

```bash
godot --headless --path D:\V-Coding\space-fighter-godot \
  --script res://tools/verify_numbers.gd
```

Expected: `VERIFY_OK checks=85` and exit code 0.

## Behaviour self-test

```bash
godot --headless --path D:\V-Coding\space-fighter-godot -- -selftest
```

Expected: `SELFTEST_OK n=5` and exit code 0 (hit without kills, graze drop,
death closes the upgrade draft, zone-1 BGM playing, 40 s zone pacing).

## Export

```bash
# Windows release (embedded PCK)
godot --headless --path D:\V-Coding\space-fighter-godot \
  --export-release "Windows Desktop" build/windows/SpaceFighter.exe

# Android release APK (requires Android SDK + JDK; Godot auto-detects both)
godot --headless --path D:\V-Coding\space-fighter-godot \
  --export-release "Android" build/android/SpaceFighter-release.apk
```

Both presets use `exclude_filter="reference/*,docs/*,build/*,.trae/*"`, so
screenshots and build artifacts never enter the shipped packs. The APK is
signed with the project keystore in `keystore/` (gitignored); verify with
`apksigner verify --verbose`.

## Reference

`reference/` is excluded from Godot import (`.gdignore`). It contains the original
web source, design docs, and Blender art generator. Do not edit it as game code;
port from it.

## Migration rules

1. Keep the 540x960 design coordinates and original numeric constants; the
   runtime viewport may expand to any phone aspect (`CFG.VIEW`), but gameplay
   values stay in design pixels. Do not reintroduce the Unity 0.025 world scale.
2. Player hit radius is **4.6 px**, graze radius **28 px**; the drawn hull is
   deliberately much larger (36 px visual radius).
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
