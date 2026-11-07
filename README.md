# Space Fighter — Godot 4.7.2 migration

Migration of the retired Unity port, using `reference/web/www` (the original
540x960 Canvas game) as the gameplay and numeric source of truth.

## Status

- [x] Godot **4.7.2 stable** installed, export templates installed
- [x] Project skeleton at 540x960, portrait, `canvas_items` stretch
- [x] Playable core: keyboard + mouse/touch drag, pulse auto-fire, four enemy
      archetypes, aimed/fan/ring fire, swept collision, graze, score/lives,
      pause/restart, difficulty keys 1/2/3
- [x] Numeric gate `tools/verify_numbers.gd` (**66 checks**, includes behaviour assertions)
- [x] **Blender sprite art ported (v0.1.1)**: player + 12 enemy hulls + hit-flash
      masks, extracted from `_archive/space-fighter-unity-v0.21.14-src.tar.gz`
      into `assets/ships/` (94 PNGs). Drawn via the Unity `ShipArt` contract
      (visual outer edge = hit radius, canvas side = radius / 0.46); polygon
      fallback kept if a texture is missing.
- [x] **App icon (v0.1.1)**: 3/4 hero interceptor (`assets/icons/`), wired into
      the project icon, Windows exe icon and Android adaptive launcher icon.
- [x] Windows debug export: `build/windows/SpaceFighter.exe`
- [x] Android APK: `SpaceFighter-Godot-v1.0.1.apk` (38 MB, target SDK 36,
      portrait, release-signed with the project keystore)
- [x] On-device install verified: emulator 1080x1920, v1.0.1 / code 9, sprites
      render, touch controls work, 0 script errors (`docs/shots/godot_v1_play.png`)
- [x] Release signing: project keystore (CN=Space Fighter, O=sctale), v2/v3 verified
- [x] Touch controls: 星爆 / 冲刺 / 换线 rings + top-right pause + menu buttons
- [x] Touch controls: focus toggle (精准) + difficulty chips in the menu
- [x] Bundled Noto CJK subset (`assets/fonts/AuroraCJK.ttf`, 229 KB, 639 glyphs)
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

Expected: `VERIFY_OK checks=29` and exit code 0.

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

1. Keep pixel coordinates (540x960) and the original numeric constants; do not
   reintroduce the Unity 0.025 world scale.
2. Player hit radius is **4.6 px**, graze radius **28 px**.
3. Use swept segment-circle collision for bullets; do not use per-frame point
   checks.
4. Add a gate assertion before adding a new subsystem, then port the web logic.
5. Keep the game playable after each slice; do not port UI/audio before the core
   loop and collisions are verified.
6. Sprite sizing follows the Unity `ShipArt` contract: the PNG canvas's max
   radius is `0.46 × edge`, so to make the visual outer edge equal the hit
   radius, draw the texture at `side = radius / 0.46`, centered. Player hull
   canvas is 58.32 px (Unity world height 1.08 ÷ (10/540)); enemy hulls are
   pre-rendered nose-down, player nose-up — do not rotate them 180°.

## Art provenance

`assets/ships/` (94 PNGs) and `assets/icons/` were extracted from
`_archive/space-fighter-unity-v0.21.14-src.tar.gz`
(`Assets/Resources/Ships/*.png`, `Assets/Icons/icon*_1024.png`). They are the
Blender 4.5 Cycles renders described in `reference/docs/BLENDER-LOWPOLY.md`.
To refresh them, re-extract from the archive (or re-run `reference/artgen/`);
do not hand-edit the PNGs. `*_mask.png` are white silhouettes used for hit-flash.
Bullets stay procedural (as in Unity v0.21.14); the legacy `bullet_*.png` in the
archive are from the older v0.19 pipeline and are not used.

## Release signing

Release APKs are signed with the project keystore (kept **local only**,
`keystore/` is gitignored):

- keystore: `keystore/spacefighter.keystore`
- alias: `spacefighter`, store/key password: `spacefighter`
- certificate: `CN=Space Fighter, OU=Games, O=sctale`

Export: `godot --headless --path . --export-release "Android" build/android/SpaceFighter-release.apk`.
The debug keystore (`CN=Godot`) produces a different signature, so switching
between them requires uninstalling the app first.
