# Adopted battle barrages

Copied from the independent barrage-lab repository at `b30e7e4`.
Rounds 2 and 3 use preset C; round 4 uses preset D. Round 5 uses the prototype's
default preset A with the same dialogue-first arena transition.

`battle.lua` bridges the model to real Player movement, Battle.OnHit, localized
EText dialogue and wave cleanup. Rendering draws only barrage content, leaving
the encounter's enemies and HUD to the engine. `clip.lua` uses LÖVE 12 stencil
state. Collision bounds reject distant knives before precise swept checks.
No prototype hotkeys or debug UI are connected to gameplay.

The opening keeps the incoming defense box throughout Chara's dialogue and
pauses the attack model. Once the final dialogue pause ends, the box moves and
resizes to the round's arena over 0.8 seconds with quartic in-out easing. Only
after this transition do lighting and attacks begin.

Round 2 builds on C with three randomized spotlight destinations. Its radius
shrinks to 88%, 73%, then 58% of the initial radius. The dominant direction of
each move selects the knife entry edge; the knives prepare as the light starts
moving and thrust before it arrives. Knife endpoints follow the live white core.

Run a defense directly with `just run -w 2` (also 1 through 10). Window workspace
selection remains available as `--workspace auto` or `--workspace 9`.

`SPIN_CHARA_INVINCIBLE=1` (dev only, ignored in releases) adds `invincible` to the
model's context, so `Model:hit` counts the contact but never damages, blinks or
cries out. The gate sits before `player.hurt` is set, because the renderer reads
that field for the soul's alpha. Use it to watch a defense play out whole:
`SPIN_CHARA_INVINCIBLE=1 just run -w 3`.

Run the real-engine integration check from the project root:
`xvfb-run -a love-git tests/barrage-integration`.
It exercises the chosen presets, dialogue, curtain, completion and cleanup.
