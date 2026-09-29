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

Round 6 adopts barrage-lab `55038c9` variant D. It uses the engine's 155×130
arena, a spotlight entering from above and exiting upward, a single horizontal
knife whose handle stays against the right inner edge, and a left knife column.
The curtain starts only after at least seven seconds of active play and a
sweeping knife approaches the soul. Under the cloth, nearby left blades retreat
at a capped speed, so fast movement can still collide with them. The right
blade accelerates across six passes (65, 145, 185, 225, 265, 305 px/s); dialogue
continues while it moves. Run `SPIN_CHARA_WAVE=6 xvfb-run -a love-git --renderers
opengl tests/wave06-curtain` for the real-engine check.

## Round 7 — adopted B hat throws

Adopted from barrage-lab `c7085c4` (B), approved 2026-09-27. Run with
`just run -w 7`. The 280×180 arena receives six predicted, varied parabolic
throws. Strong exponential Out easing retains the agreed launch speed and
2× minimum/exit speed: each B flight lasts about 1.39 seconds, with .85 seconds
between hats. The first two have no knives. This round uses the large
`hat-remilia.png` design (96×96); it is the only large design currently in the
selection pool. Hat artwork and the size pools are documented in
`Resources/Sprites/Attacks/Monsters/Hats/README.md`.

The hat carries the real soul while leaving control within its 30px inner
radius. It releases naturally at the edge, ahead of the blade belt. Starting
with throw three, four opaque knife rows enter one blade at a time, at 16px
pitch and 110px/s, clockwise with tips facing inward. The arena clips part of
each blade. Stop births at the end, then let the final knives walk out.

Round 5's near-tip rule still applies without wearing a hat: individual knives
warn, thrust inward 28px, and retract while continuing along the row. Occupied
hats additionally attract idle knives after a warning; already-thrusting knives
are not interrupted. No hat invulnerability is added. The real game's damage,
knife outline, soul movement and launch sound are retained. Mid-attack Chinese
and English dialogue does not stop the attack.

The shared model limits newborn swept collisions to their actual birth fraction
of a frame. Hat rendering uses the game's stencil; teardown clears the hat and
restores the native soul, arena and menu. Unlike the prototype, opening timing
is owned by the engine's confirmation and arena resize, without a second .6s hold.

Validation:

```sh
luajit tests/wave07-rules.lua
env SDL_VIDEODRIVER=x11 ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=7 xvfb-run -a love-git --renderers opengl tests/wave07-hat
env SDL_VIDEODRIVER=x11 ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=7 WAVE07_LANGUAGE=en xvfb-run -a love-git --renderers opengl tests/wave07-hat
```

The rule test checks speed endpoints, prediction, capture/release, actual
collision and safe routes, four-sided proximity thrusts, incremental streams
and natural draining at 30/120Hz. The engine test covers actual loading,
movement, dialogue, damage, launch sounds, completion and cleanup.

Migration regression: knife row coverage, damage punishment and round 6's native
engine check pass. `tests/wave03-slow.lua` currently fails its line 13 slow-factor
expectation on both the pre-migration HEAD and this worktree; this migration
does not change that round's speed settings.

## Round 8 — adopted C curtain and hat throws

Adopted from barrage-lab `7764f0a` (C), approved 2026-09-27. Run with
`just run -w 8`. Each knife fades in outside the arena, completes a full turn,
aims at the soul and launches. Hats first extend from the side, retract, then
follow the predicted parabolic throw from round 7. The first four volleys play
without the curtain; it then stays down for two more aimed volleys followed by
two dense knife rows. The rows use the real game's 14px blade outline and 16px
pitch, centred over the arena's reachable height as in round 2. Hats under the
curtain repel nearby knives with finite force, leaving collisions active.

Round 8 uses the same large Remilia hat as round 7. The body uses its own
movement, damage, launch sound, opening dialogue and
return-to-menu lifecycle. The curtain shader keeps hats and knives readable
outside the arena without introducing a spotlight. Wave 7's hat movement is
reused unchanged apart from exporting its movement and time-scale helpers.

Validation:

```sh
luajit tests/wave08-rules.lua
env SDL_VIDEODRIVER=x11 ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=8 xvfb-run -a love-git --renderers opengl tests/wave08-hat
env SDL_VIDEODRIVER=x11 ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=8 WAVE08_LANGUAGE=en xvfb-run -a love-git --renderers opengl tests/wave08-hat
```

The rule test covers row pitch, safe routes, actual damage when the hat is not
repelling, completion and cleanup at 30/120Hz. The engine test covers the hat's
extend/retract/throw order, continuous curtain, covered volley order, exact row
count, dialogue in both languages, real damage and launch sounds, and menu return.

## Round 9 — adopted layout 04, changing curtain sides

Adopted from barrage-lab `be715c8`, layout 04 “幕布换边”, approved 2026-09-28.
Run with `just run -w 9`. The 340×190 arena has a solid, pushable scenery hat,
a knife wall and one door with its point facing the hat. The hat has a 26px
radius and moves at up to 92px/s. It threads the door toward the handle;
following the blade axis can still injure the soul. At wave start, one of the
three 64×64 small hats is selected for the round; the image is scaled to a 52px
diameter independently of its source dimensions.

The stage has ambient blade visibility and soul glow, with no spotlight.
The right half curtain lifts at hour six, then falls on the left. The clock
continues throughout the switch and Nap/Chara's dialogue. Twelve aimed shots
at 1.3s intervals end with 41 parallel knives at the game's 16px pitch.
A hat actually covered by the cloth repels them with round 8's finite force.
X retains the game's smooth attack slowdown. Both solving and failing the
puzzle lead to the curtain exit, fading scenery and the native action menu.

Opening confirmation and arena resizing belong to the engine, so the prototype's
extra .6s hold is omitted. Native movement, blade collision, damage and one
launch sound per shot or wall remain connected. Cleanup also removes the half
curtain state, hat list and ambient lighting on interruption.

Validation:

```sh
luajit tests/wave09-rules.lua
env SDL_VIDEODRIVER=x11 ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=9 xvfb-run -a love-git --renderers opengl tests/wave09-puzzle
env SDL_VIDEODRIVER=x11 ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=9 WAVE09_LANGUAGE=en xvfb-run -a love-git --renderers opengl tests/wave09-puzzle
env SDL_VIDEODRIVER=x11 ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=9 WAVE09_ROUTE=unsafe xvfb-run -a love-git --renderers opengl tests/wave09-puzzle
```

Rule checks cover one-way blocking, safe off-axis pushing versus blade-axis
injury, the sheltered closing wall at 30/120Hz, X slowdown, side switching,
unsolved completion and interrupted cleanup. Engine checks use actual controller
input to deliver the hat and survive without damage in both languages; the
unsafe route leaves the hat behind and verifies real HP loss. They also check
continuous dialogue, sounds, curtain rendering, menu return and object cleanup.


## 第十回合：Nap 原作散落眼泪与战斗收尾（2026-09-28）

```sh
just run -w 10
```

用户采纳 barrage-lab 第十回合，并要求 Nap 只平移，不缩放。
Nap 的真实敌人动画现使用项目已有两帧战斗贴图，全程固定 2×（原型攻击时的尺寸）；
从侧边平移到原作发射位置，攻击后平移回去。独立动画实例保留受伤反应和清理接口。
Nap 的气泡位于右下方，避开演员的移动路径。引擎角色只绘制一份，不用覆盖层冒充演员。

采用原作 crygen1 / crybullet 普通情绪：10 帧一对，140 帧（30Hz）一轮，
双眼位置 (318,154)/(348,164)，155×130 内框。原作横速、重力、摩擦、缩放随机范围与
左右反弹均保留；每次进回合使用新的随机种子。眼泪复用 `spr_teardrop_0.png`，
从框外的双眼直接落入场内。原作导出缺少碰撞 mask，眼泪沿用采纳原型的凸轮廓扫掠近似；
本体碰撞模块支持单弹自定义轮廓，现有刀保持默认刀刃轮廓。

开场使用本体确认键和缩框流程，Nap 对白结束后再发射。真实 Player 只移动一次，
X 只减慢玩家；眼泪保持 30Hz 节奏。眼泪通过原有 `Battle.OnHit` / `Player.Hurt` 扣 5 HP，
60 帧无敌、无连续受伤加罚，保留受伤音效。回合内 0–1 次受伤走放水对白，2 次以上走伤害低对白。
所有中英键已进入本体 Localization。Chara 最后离场后清理波次并淡出到现有 `scene_end`，
不额外发奖励、死亡消息或再次开放行动菜单。中途切回菜单则恢复演员原位置与显示状态。

```sh
env SDL_VIDEODRIVER=x11 ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=10 xvfb-run -a love-git --renderers opengl tests/wave10-finale
env SDL_VIDEODRIVER=x11 ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=10 WAVE10_LANGUAGE=en WAVE10_ROUTE=unsafe xvfb-run -a love-git --renderers opengl tests/wave10-finale
env SDL_VIDEODRIVER=x11 ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=10 WAVE10_ROUTE=abort xvfb-run -a love-git --renderers opengl tests/wave10-finale
```

真实引擎检查覆盖固定缩放与平移、双眼锚点、移动只施加一次、攻击计时与数量、
无伤／受伤及音效、两支对白、正常结束／中断退出，以及清理弹幕、灯、气泡、角色控制和绘制覆盖。
另通过刀阵无缝检查、第七／八／九回合规则及第九回合真实引擎回归。
本体修改尚未提交或推送；既有第九回合等工作区改动继续保留。

### 第十回合收尾修正（2026-09-28）

第 140 个原作帧生成最后一对眼泪后停止发射，已有眼泪继续运动、反弹和伤害判定。眼泪整个碰撞轮廓越过战斗框底边才移除；全部离场（或命中被消耗）后，Chara 才继续说话，结算包含这段收尾中的受击。

眼泪入框后由框的遮罩收走：`clip.lua` 的 `exceptBelow` 把各框底线以下（框宽范围内）挖空，
眼泪照旧从框外双眼一路落下，越过底边的部分被裁掉，离场因此是贴着底边逐帧变细、滑出遮罩，
而不再先压到白色边框上再整颗消失。移除判定仍用同一条边——碰撞轮廓最上面的顶点就是贴图顶边，
所以裁没的那一帧和移出列表的那一帧重合，画面上没有跳变。框外的下落与入框过程不受遮罩影响。
