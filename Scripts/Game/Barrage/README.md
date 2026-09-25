# Adopted battle barrages

Originally copied from the independent barrage-lab repository. Round 3 now uses
prototype B; round 2 uses preset C, round 4 preset D, and round 5 preset A.
All knife sprites in rounds 2–5 use scale 1, which is also the size the rows and
fans are laid out for: `Model:knife` honours any other scale, but a wave that
passes one has to lay that row out on `Knife.pitch(scale)` itself or its blades
will overlap.

Rows and fans sit on the blade's own pitch — `knife.lua`'s `K.pitch`, the
sprite's 14px cross-section plus a 2px seam. The collision outline covers that
cross-section, so the seam between two neighbours stays narrower than the soul's
4x4 square: a row is a wall, and each row is laid out from a known end on whole
pixels rather than by dividing its span between blades, which is what used to
let a row stop short of a wall and leave a strip to stand in. Round 4's volleys
before the cloth stop clear of the light's lane and pick up again on the lane's
own edge for the same reason: the one refuge that round offers cannot be
undercut by a strip of dark that no blade reaches.

`battle.lua` bridges the model to real Player movement, Battle.OnHit, localized
EText dialogue and wave cleanup. Rendering draws only barrage content, leaving
the encounter's enemies and HUD to the engine. `clip.lua` uses LÖVE 12 stencil
state. Collision bounds reject distant knives before precise swept checks.
No prototype hotkeys or debug UI are connected to gameplay.

The opening keeps the incoming defense box throughout Chara's dialogue and
pauses the attack model. Once the final dialogue pause ends, the box moves and
resizes to the round's arena over 0.8 seconds with quartic in-out easing. Only
after this transition do lighting and attacks begin. A wave that declares
`reusesIncomingBox` has nothing to resize: its opening is the hold alone. A wave
that declares `animatesOpeningBox` scales the frame itself, so the hold keeps the
box the battle came in with and the wave takes over the moment the line closes.

Round 2 builds on C with five randomized spotlight destinations. Its radius
shrinks evenly across the five moves and ends at 29% of the initial radius —
half of what the earlier three-move schedule reached on its last move. The
dominant direction of each move selects the knife entry edge; the knives prepare
as the light starts moving and thrust before it arrives. Knife endpoints follow
the live white core, and the circle they close around it is never tighter than
one blade: below that no blade crosses the core any more and the whole fan
thrusts past the light to the far edge instead of ringing it. Each fan is laid
out about the middle of the box, so an odd count puts a blade on the centre line
and both ends keep the same clearance.

Round 2 plays in the engine's own defense box instead of one of its own, so
nothing about the box moves at any point. Its spotlight entrance therefore
starts on the first update after the line closes: the dialogue is the beat
before the light, not a timer counted from the model clock, which the battle
freezes for the whole line. The prototype eases between a box of its own and can
afford that timer — there the model keeps running while the line plays — so the
two copies differ here. `tests/wave02-entry` pins both halves: the box holds
still and the entrance follows the line.

Round 3 opens and reads its blades in the incoming defense box, which does not
move while the line is spoken or while the rows emerge and spin up. In the last
quarter second before the sweep it grows to the round's square height, at full
speed, so the change of shape lands on the attack instead of running while
nothing is coming. Its width is left alone until after the sweep, when the frame
expands to 288 as the rows cross it. Two rapid horizontal cuts form upper, middle
and lower areas, 38 / 56 / 38px high with 12px gaps. The soul stays in the strip
it occupied at the second cut. The spotlight
enters the middle strip and glides left or right while vertical knife rows attack
from the corresponding edge. Upper and lower strips receive only their outward
attack direction; the middle alternates. The five beats tighten their travel
time, so X is required to slow the blade rows and create a safe timing window.
Every row then stands still where its blades stopped for a quarter second before
withdrawing, so the ring it formed is readable and the move to the light's next
position can begin.
The rows carry no mark on the edge they enter from — the beat is read from the
light alone, and where the light will stop is deliberately left unmarked.

Rounds two and four sound their blades leaving the box. A fan or a volley is one
beat however many knives it holds, so the wave announces a launch and `knife.wav`
plays once with the blades starting to move — not with the stage or the light
that precedes them, and not once per blade. The box clips the blades until they
cross its edge, so that sample lands while they are all still outside it: in
round two on the fan's first blade, with the stagger behind it belonging to the
same sound, and in round four as the volley's stage opens.

Run a defense directly with `just run -w 2` (also 1 through 10). Window workspace
selection remains available as `--workspace auto` or `--workspace 9`.

`just run -w skip` skips the opening enemy turn instead and opens the battle on
the player's turn, which is how the menu, narration or item work is reached
without playing a defense first. The skip is final: the next defense is the wave
that follows the skipped one, not that wave again.

`SPIN_CHARA_INVINCIBLE=1` (dev only, ignored in releases) adds `invincible` to the
model's context, so `Model:hit` counts the contact but never damages, blinks or
cries out. The gate sits before `player.hurt` is set, because the renderer reads
that field for the soul's alpha. Use it to watch a defense play out whole:
`SPIN_CHARA_INVINCIBLE=1 just run -w 3`.

Run the real-engine integration check from the project root:
`xvfb-run -a love-git tests/barrage-integration`.
It exercises the chosen presets, dialogue, curtain, completion and cleanup.
Round 2's entrance timing has its own check:
`SPIN_CHARA_WAVE=2 xvfb-run -a love-git tests/wave02-entry`.
The skip switch has one too:
`SPIN_CHARA_WAVE=skip xvfb-run -a love-git tests/skip-to-player-turn`.
The launch sample has one too, for `SPIN_CHARA_WAVE` 2 and 4:
`xvfb-run -a love-git tests/knife-launch-sound`.

Round 5 adopts prototype A from barrage-lab `17d7636`: a fixed 280×156 viewport,
a spotlight rising from below, 54px/s downward soul drift, and one synchronized
lower knife wave with independent proximity stabs. Nap and Chara speak during
the scroll. The ceiling row enters through scroll displacement; the final wave
keeps the ordinary 2.6s rhythm and increases its reach from 76px to 112px.
The spotlight then exits upward over 1.6s as the darkness and inactive knives
fade. Warnings are nearly white pink. The game retains its own blade pitch,
swept collision shape, smoothed X slowdown and real movement/dialogue adapters.
Run `SPIN_CHARA_WAVE=5 xvfb-run -a love-git --renderers opengl tests/wave05-scroll` for the full
engine check, including the return to the action menu and presentation cleanup.
