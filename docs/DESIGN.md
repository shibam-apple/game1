# Sand Lancer - design

## Pitch

Two mech pilots settle it on foot. You are Ran Sen, pilot of the Sand Lancer.
Your opponent, callsign Kite, never lands unless you make him: he fights from
a flight harness and directs his proto-frame, Garuda, while he duels you.
The machines stand over the arena and intervene when their pilots call.

Tone: quiet, vast, dust-choked. Low sun, long shadows, near-monochrome amber
with one accent colour, the blue of Ran's blade.

Original world. Inspirations are the mood of desert science fiction, mech-pilot
duels, and the inventor-driven wonder of Bengali science fiction. No names,
characters or designs are taken from existing works.

## Story seed

Both machines were built by the same inventor, decades apart. Garuda is the
prototype he abandoned as too dangerous; the Sand Lancer is the one he finished.
Ishaan Vyas found Garuda and woke it. LANCER, the Sand Lancer's AI, speaks to
Ran throughout the fight; it knew Garuda's AI once.

## Combat

Borrowed structure: fast action combat with a stagger gauge and cooldown
techniques, inside a punishing one-on-one duel with strict telegraphs.

- Combo: four taps, the fourth is heavy. Taps buffer.
- Dodge: swipe. Invulnerable for the first 0.27 s. A dodge that an attack
  passes through is a perfect dodge: time slows and the next tap is a counter.
- Guard / parry: hold. A hold begun within 0.25 s before impact parries,
  dealing heavy LINK damage. Parried bolts fly back at him.
- Lunge: swipe up. Gap closer; strikes rise to meet an airborne target.
- Techniques: Stormrend (three spinning cuts, LINK shredder) and Glassfall
  (leaping slam), on cooldowns.
- LINK gauge (his): empty it and his harness fails. He drops for 5.5 s and
  damage ramps up to x1.5.
- Link gauge (yours): fills by fighting well. Full: call the Sand Lancer for
  one beam strike, then 8 s of faster, stronger, life-stealing attacks.
- Stamina for dodges, lunges and blocks. Three healing cells.

### Kite's moves

| Move | Tell | Answer |
| --- | --- | --- |
| Dive | amber | parry or dodge; he is grounded afterwards |
| Swoop (two passes) | amber | parry each, or dodge twice |
| Bolt volley | amber | parry to send them back |
| Garuda strike | red circle on the ground | leave the circle |
| Skybreaker | red, climbs high | dodge the landing; long punish window |
| Phase 2: barrage, dive into follow-up slash | | faster rhythm |

## Roadmap

1. Now: one duel, placeholder characters, procedural desert.
2. Art pass: real pilot and mech models with motion-captured sword
   animation, replacing `humanoid.gd`. Sand, rock and metal textures. Baked
   lighting once environment meshes exist.
3. Feel pass on a real phone: gesture thresholds, camera, difficulty.
4. Audio: music, voiced LANCER lines, recorded effects.
5. Beyond the proof of concept: approach level, second duel, progression.
