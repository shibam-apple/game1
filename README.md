# Sand Lancer

A gesture-driven sword duel for Android: one pilot on foot, one flying enemy
commanding his mech, in the deep desert. Proof of concept, built in Godot 4.4.

## Play

No on-screen buttons. Landscape, two thumbs.

| Gesture | Action |
| --- | --- |
| Tap | Strike. Keep tapping for a four-hit combo |
| Swipe | Dodge that way. A last-instant dodge slows time; tap to counter |
| Swipe up | Lunge. Closes distance and reaches him in the air |
| Hold | Guard. Start the hold just before an amber strike lands to parry |
| Drag | Move |
| Both thumbs swipe up / down | Stormrend / Glassfall |
| Both thumbs hold | Call the Sand Lancer (when the link gauge is full) |
| Tap the cells, bottom left | Heal |

Amber blade: guard or parry. Red blade or red ground circle: move.
Empty his LINK gauge to burn out his flight harness and drop him.

Desktop testing: WASD, J strike, Space dodge, L lunge, K guard, Q/E techniques,
R summon, F heal. The mouse acts as one finger.

## Get the APK

Every push to `main` builds an APK with GitHub Actions. Open the repo's
**Actions** tab, pick the latest run, and download `sandlancer-apk`. Install
it on your phone (allow installs from unknown sources).

## Run in the editor

Install Godot 4.4.1, open `project.godot`, press F5.

## Layout

- `scripts/main.gd` - world, lighting, mechs, camera, effects, game flow
- `scripts/player.gd` - Ran Sen: combos, dodge, parry, techniques, summon
- `scripts/boss.gd` - Kite: flight, attack patterns, phases, stagger
- `scripts/gesture_input.gd` - tap / swipe / hold / drag recognition
- `scripts/humanoid.gd` - placeholder character rig (to be replaced by real models)
- `scripts/hud.gd`, `scripts/sfx.gd` - interface and synthesised sound
- `shaders/sand.gdshader` - rippled sand (photo grain + procedural dunes)
- `assets/` - textures and their credits
- `docs/DESIGN.md` - concept, story, combat design, roadmap

## Status

Combat and controls are playable. Characters and mechs are placeholders built
from primitives; see `docs/DESIGN.md` for the art pass that replaces them.
