-- Round 1's set piece: Chara's opening slash.
--
--   1. Chara's bubble types four localized lines while the player is free to
--      move. The fourth line ends with [func:Wave01Slash], so the blade falls the
--      moment "你要知道..." is on screen -- the player presses nothing -- and
--      Chara's bubble goes away with it: she has stopped talking and is now
--      performing.
--   2. The blade falls down the middle of the box and cuts it in two. Where the
--      heart ends up is decided by where it is standing, not by the wave: nothing
--      moves the player. Only a heart that the cut leaves outside both halves
--      gets nudged back in, by the engine's own containment.
--   3. Chara's closing lines play on the player's confirm; the round ends.
local wave = ImportFile("Battle.Waves")
local EndWave = wave.EndWave
local Arena = Battle.mainarena

-- Blade: the same 650px line as before, but half as wide and 4.4x faster. At
-- 4000px/s it overlaps the 130-tall box for roughly 0.2s, and its tip crosses
-- the box in about two frames.
local BLADE_W, BLADE_H = 2, 650
local BLADE_HALF = BLADE_H / 2              -- 325: half the line's length
local BLADE_SPAWN_Y = -320                  -- tail starts above the screen
local BLADE_SPEED = 4000                    -- px per second, falling
local BLADE_EXIT_Y = 480 + BLADE_HALF       -- 805: the tail has left the screen

-- Cut: the blade falls down the middle of the box, so the box ends up as two
-- halves with a gap where it passed. Both halves keep their outer edge pinned
-- and shrink and slide away from the cut line, which reads as one box being
-- sliced open rather than two new boxes appearing.
-- Both halves draw their own 5px border, so the visible seam between them is
-- CUT_GAP - 2 * thickness: 16 leaves a 6px dark channel, wider than the borders,
-- which is what makes the box read as severed instead of merely touching.
local CUT_GAP = 16
local CUT_MIN_HALF = 40                     -- never leave a sliver behind
local SPLIT_SPEED_X, SPLIT_SPEED_W = 2, 4   -- px per FRAME; Arenas smooths per frame

local phase = "intro"
local blade, blade_x, blade_y, blade_spent
local slash_armed, slash_fired
local intro_typer
local split_arena, split_settling
local half_w, left_cx, right_cx

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

local function enemyDialogue(lines, callback)
    local enemy = Battle.game and Battle.game.enemies and Battle.game.enemies[1]
    local position = (enemy and enemy.position) or {320, 120}
    local x, y = position[1], position[2]
    local width, height = 210, 100
    local on_left = x >= 300
    local bx = on_left and math.max(25, x - width - 45)
        or math.min(615 - width, x + 65)
    -- Copy the lines: EText writes the normalized sentence back into the array it
    -- is handed, and the localization table is shared for the whole session.
    local colored = {}
    for i, line in ipairs(lines) do colored[i] = "[colorHEX:000000]" .. line end
    local typer = Typers.EText.New(colored,
        {bx, math.max(35, y - height / 2 + 10)}, "UponArena", {width, height}, "manual")
    typer.font = "speechbubble.ttf"
    typer.fontsize = 13
    typer.use_bondfont = false
    typer.scale = 1
    typer.line_spacing = 0
    typer.auto_wrap = true
    typer:ShowBubble(on_left and "right" or "left", 0.5)
    typer.size[1] = width - 20
    typer._onComplete = callback
    return typer
end

---A localized array of lines, with a placeholder when the key is missing. A
---typer built from an empty array never advances and never completes, which
---would soft-lock the round with the round never ending.
local function localizedLines(key)
    local lines = Localize.localizeText(key)
    if (type(lines) ~= "table" or #lines == 0) then
        print("[wave01] WARNING: missing localization text: " .. key)
        return {"..."}
    end
    return lines
end

---Armed by the typer the moment it reaches [func:Wave01Slash], i.e. right after
---the last character of the fourth intro line is drawn. etext.lua looks this up
---in _G, so it has to be a global.
_G.Wave01Slash = function ()
    -- One blade per round: a replayed sentence, a duplicated tag or a stale
    -- global from an earlier round must not drop a second blade on the player.
    if (phase == "outro" or slash_armed or slash_fired) then return end
    slash_armed = true
end

---Take Chara's speech off the screen: she has finished the line and is now
---performing, so leaving the bubble (or its text floating without it) up during
---the slash would read as a mistake. The typer itself stays alive so the
---player's confirm still carries the scene on to the closing lines.
local function dismissBubble(typer)
    if (not typer) then return end
    typer:HideBubble()
    typer:Reset()
end

---Drop the blade once its tail has cleared the screen, so a wave torn down
---early cannot leave the sprite behind for the global collision sweep.
local function removeBlade()
    if (not blade) then return end
    blade:Destroy()
    for i = #wave.objects, 1, -1 do
        if (wave.objects[i] == blade) then
            table.remove(wave.objects, i)
            break
        end
    end
    blade = nil
end

local function startBlade()
    blade_x = Arena.x
    blade_y = BLADE_SPAWN_Y
    blade_spent = false
    blade = Sprites.CreateSprite("px.png", "TopAll")
    blade:Scale(BLADE_W, BLADE_H)
    blade:MoveTo(blade_x, blade_y)
    blade.color = {1, 1, 1}
    blade.spin_damage = 10
    -- Deliberately NOT isBullet. Player.Update sweeps every isBullet sprite and
    -- calls Battle.OnHit only while hurt_time is 0, while the wave's own hit test
    -- below ignores hurt_time -- with both paths the 20 HP player took two
    -- 10-damage hits and died on round 1. This is the only damage path.
    table.insert(wave.objects, blade)
    dismissBubble(intro_typer)
end

---Splits the box at the blade's column: mainarena becomes the left half and a
---new plus arena becomes the right half. The player is not touched.
local function cutArena()
    local left_edge = Arena.x - Arena.width / 2
    local right_edge = Arena.x + Arena.width / 2

    -- The blade falls down the middle of the box. The clamp only exists so a cut
    -- near an edge cannot leave a sliver behind, since Arenas silently forces any
    -- side under 16px to 16.
    local cut_x = clamp(blade_x,
        left_edge + CUT_MIN_HALF + CUT_GAP / 2,
        right_edge - CUT_MIN_HALF - CUT_GAP / 2)

    half_w = (Arena.width - CUT_GAP) / 2
    left_cx = cut_x - CUT_GAP / 2 - half_w / 2
    right_cx = cut_x + CUT_GAP / 2 + half_w / 2

    -- The right half is born as an exact copy of the whole box and animated
    -- outward from there, so the two peel apart instead of a second box popping
    -- into existence on top of the first.
    split_arena = Arenas.New("plus", "rectangle", Arena.x, Arena.y, Arena.width, Arena.height, Arena.rotation)

    -- Neither half carries the heart while they move. Which half the player ends
    -- up in is decided by where the player is standing, so dragging them along
    -- with a box would be the wave moving the player rather than the cut deciding
    -- it. A heart left outside both halves is pushed into the nearest one by the
    -- engine's own containment (Arenas.Update), which is the same clamp that
    -- holds the player inside a battle box every other frame of the game.
    Arena.move_player = false
    split_arena.move_player = false

    Arena:MoveTo(left_cx, Arena.y)
    Arena:ResizeWithSpeed(half_w, Arena.height, SPLIT_SPEED_W, 15)
    Arena.speeds.x = SPLIT_SPEED_X

    split_arena:MoveTo(right_cx, Arena.y)
    split_arena:ResizeWithSpeed(half_w, Arena.height, SPLIT_SPEED_W, 15)
    split_arena.speeds.x = SPLIT_SPEED_X

    split_settling = true
end

---True once both halves have finished sliding apart. Arenas moves the real
---geometry with smooth_value, which clamps exactly onto the target, so these are
---exact comparisons rather than a floating-point guess.
local function splitSettled()
    return Arena.width <= half_w and Arena.x <= left_cx
        and split_arena.width <= half_w and split_arena.x >= right_cx
end

---Hand the shared arena back the way every other wave expects to find it.
---Arenas.Clear only destroys extra arenas - it does not undo a resize, and the
---player is free to move from the first frame.
local function restoreArena()
    Arena:ResetSpeed()
    Arena.move_player = true
end

local function finishWave()
    restoreArena()
    _G.Wave01Slash = nil
    EndWave()
end

local function startOutro()
    phase = "outro"
    -- The intro typer is being destroyed as this runs, so nothing is left to
    -- dismiss: clear the reference before the safety net below can arm a blade.
    intro_typer = nil
    if (not slash_fired and not slash_armed) then
        -- Safety net: a translation that dropped [func:Wave01Slash] (the JSON is
        -- edited by hand) should play the beat a confirm late rather than quietly
        -- skip the round's set piece. Test slash_fired rather than `blade`: the
        -- blade is removed long before the player confirms past the line, so by
        -- then there is nothing left to test.
        print("[wave01] WARNING: [func:Wave01Slash] never fired - starting the slash from the outro.")
        slash_armed = true
    end
    enemyDialogue(localizedLines("Battle.Waves.Wave01.Outro"), finishWave)
end

local function startIntro()
    intro_typer = enemyDialogue(localizedLines("Battle.Waves.Wave01.Intro"), startOutro)
end

-- The heart starts centred and the player keeps control the whole time: the
-- slash is something to read the screen and dodge, not a cutscene that takes the
-- controls away.
Player.canMove = true
Player.sprite:MoveTo(Arena.x, Arena.y)

function wave.Update(dt)
    if (phase == "intro") then
        phase = "intro_wait"
        startIntro()
    end

    -- Armed by the tag, or by the safety net in startOutro.
    if (slash_armed and not slash_fired) then
        slash_armed = false
        slash_fired = true
        startBlade()
    end

    -- The blade runs on its own clock: the player can confirm past the fourth
    -- line while it is still falling, so it must not be tied to `phase`.
    if (blade) then
        blade_y = blade_y + BLADE_SPEED * dt
        -- Pin x to where the blade was born, not to Arena.x: the left half starts
        -- sliding the moment the box is cut, and the blade must stay on the cut.
        blade:MoveTo(blade_x, blade_y)

        -- The tip reaching the heart's line is the cut: the box is severed either
        -- way, and it happens once. Only a heart actually under the blade draws
        -- blood -- the blade is a 2px line, so the test is the engine's usual one
        -- of the bullet's width against the player's hitbox, and running clear of
        -- the cut dodges it.
        if (not blade_spent and blade_y + BLADE_HALF >= Player.sprite.y) then
            blade_spent = true
            local hitbox = (Player.sprite._hitbox and Player.sprite._hitbox[1]) or 16
            if (math.abs(Player.sprite.x - blade_x) <= BLADE_W / 2 + hitbox / 2) then
                Battle.OnHit(blade)
            end
            cutArena()
        end

        if (blade_y >= BLADE_EXIT_Y) then
            removeBlade()
        end
    end

    if (split_settling and splitSettled()) then
        split_settling = false
        restoreArena()
    end
end

return wave
