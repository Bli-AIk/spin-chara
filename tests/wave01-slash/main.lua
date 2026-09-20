-- Drives round 1's opening slash and checks the things the change is about:
-- the blade falls on its own the moment the fourth intro line finishes typing,
-- it cuts the battle box into two arenas, it damages the player exactly once,
-- and the heart ends up locked inside one half.
-- Run from the project root: xvfb-run -a love-git tests/wave01-slash
local project = love.filesystem.getWorkingDirectory()
dofile(project .. "/main.lua")

local gameLoad, gameUpdate, gameDraw = love.load, love.update, love.draw
local task, screenshot

local function frames(count)
    for _ = 1, count do coroutine.yield() end
end

local function untilTrue(predicate, label)
    for _ = 1, 900 do
        if predicate() then return end
        frames(1)
    end
    error("Timed out: " .. label .. " (state=" .. tostring(Battle.state) .. ")")
end

local function settled(state)
    untilTrue(function() return Battle.state == state and not Battle.transition.busy end, state)
    frames(2)
end

local function capture(name)
    screenshot = name
    frames(2)
    assert(not screenshot, "Screenshot callback did not run")
end

---Hold down one virtual key for a single frame, exactly like the bubble test.
local function press(action)
    local controller, keyboard = Controller.GetState, Keyboard.GetState
    Controller.GetState = function(key) return key == action and 1 or controller(key) end
    Keyboard.GetState = function(key) return key == action and 1 or keyboard(key) end
    frames(1)
    Controller.GetState, Keyboard.GetState = controller, keyboard
    frames(2)
end

---Hold one virtual key down across many frames, for movement checks.
local function hold(action, count)
    local controller, keyboard = Controller.GetState, Keyboard.GetState
    Controller.GetState = function(key) return key == action and 1 or controller(key) end
    Keyboard.GetState = function(key) return key == action and 1 or keyboard(key) end
    frames(count)
    Controller.GetState, Keyboard.GetState = controller, keyboard
end

---The blade is the only sprite that carries spin_damage.
local function bladeSprite()
    for _, sprite in ipairs(Sprites.images) do
        if (sprite.spin_damage == 10) then return sprite end
    end
    return nil
end

---Newest typer showing a bubble - the wave's enemy bubble is the only one on
---screen during round 1. Live EText instances live in Typers.EText.insts.
local function bubbleTyper()
    local insts = Typers.EText.insts
    for i = #insts, 1, -1 do
        local typer = insts[i]
        if (typer.bubble) then return typer end
    end
    return nil
end

---True once the typer has drawn every character of its current sentence.
local function lineTyped(typer)
    if (not typer) then return false end
    local index = typer.sentence_index
    return index <= #typer.texts and typer.counter > #typer.texts[index]
end

---Press confirm until the current line is on screen, then move to the next one.
local function nextLine(label)
    untilTrue(function() return lineTyped(bubbleTyper()) end, label .. " typed out")
    press("confirm")
end

local function run()
    frames(3)

    settled("DEFENDING")
    local hp0 = Player.hp
    assert(hp0 == 20, "expected a full 20 HP player, got " .. tostring(hp0))
    local arena_w0, arena_x0, arena_y0 = Battle.mainarena.width, Battle.mainarena.x, Battle.mainarena.y
    print(string.format("[SETUP] defense arena %.1fx%.1f at %.1f,%.1f  arenas=%d",
        Battle.mainarena.width, Battle.mainarena.height, arena_x0, arena_y0, #Arenas.insts))

    -- Round 1 opens dry: an encounter that starts in DEFENDING holds the battle
    -- BGM back so the monologue and the slash play without it.
    assert(Battle._music_source == nil,
        "the scripted opening DEFENDING turn should have no BGM")

    -- Advance through the first three lines. Each press only lands once the
    -- current line has finished typing, so wait for that instead of guessing.
    -- First let the heart reach the middle of the box, where the wave drops it:
    -- driving the dialogue before it settles lets a hitched frame type the intro
    -- out and fire the blade while the heart is still sliding, which is not the
    -- "heart sitting on the cut line" this test means to check.
    untilTrue(function()
        return math.abs(Player.sprite.x - Battle.mainarena.x) <= 1
            and math.abs(Player.sprite.y - Battle.mainarena.y) <= 1
    end, "the heart settled at the middle of the box")

    nextLine("intro line 1")
    nextLine("intro line 2")
    nextLine("intro line 3")

    -- From here the player presses NOTHING: the blade has to fall by itself the
    -- moment "你要知道..." finishes typing. Under the old wave this never
    -- happened without a fourth confirm, so this is the check for that.
    untilTrue(function() return lineTyped(bubbleTyper()) end, "intro line 4 typed out")
    local confirmed_at = 0
    untilTrue(function() return bladeSprite() ~= nil end, "blade falls with no confirm")
    print("[BLADE] spawned without a confirm after the fourth line finished typing")

    -- The player never moved, so the heart is sitting exactly on the cut line:
    -- the blade has to draw blood, exactly once.
    local x_at_cut = Player.sprite.x
    untilTrue(function() return #Arenas.insts == 2 end, "box split into two arenas")
    -- The cut and the damage land in the same frame, but do not assume the order
    -- they become observable in: wait for the hit instead of reading hp on the
    -- frame the second arena shows up.
    untilTrue(function() return Player.hp ~= hp0 end, "the blade drew blood")
    assert(Player.hp == hp0 - 10,
        "expected exactly one 10 damage hit, hp " .. tostring(hp0) .. " -> " .. tostring(Player.hp))
    assert(Player.hurt_time > 0, "the hit should have started invincibility")
    print(string.format("[CUT] hp %d -> %d, arenas=%d, heart never moved from %.1f",
        hp0, Player.hp, #Arenas.insts, x_at_cut))
    assert(Player.canMove, "the player must keep control across the cut")

    -- The halves slide apart. Wait for the geometry rather than for a flag: the
    -- wave no longer announces a "player is placed" moment, because it does not
    -- place the player at all.
    untilTrue(function()
        local second = Arenas.insts[2]
        return second and Battle.mainarena.width < arena_w0 and second.width < arena_w0
            and Battle.mainarena.x == Battle.mainarena.target.x
            and second.x == second.target.x
    end, "both halves settled")

    -- The box must have been cut, not merely duplicated.
    local left, right = Arenas.insts[1], Arenas.insts[2]
    local seam = (right.x - right.width / 2 - 5) - (left.x + left.width / 2 + 5)
    print(string.format("[CUT] left %.1fx%.1f at %.1f  right %.1fx%.1f at %.1f  seam %.1fpx",
        left.width, left.height, left.x, right.width, right.height, right.x, seam))
    assert(left.width < arena_w0 and right.width < arena_w0,
        "both halves should be narrower than the original box")
    assert(seam > 0, "the halves must not overlap, seam was " .. tostring(seam))

    -- The heart was left on the cut line, which once the halves have separated is
    -- inside neither of them. The wave itself must never have moved it there --
    -- by the time we look, the engine's own containment has pushed it into a
    -- half, which is the only placement this wave allows.
    local inner_left = left.x + left.width / 2 - 8
    local inner_right = right.x - right.width / 2 + 8
    local stalled = Player.sprite.x
    frames(4)
    local x = Player.sprite.x
    print(string.format("[LAND] heart pushed %.1f -> %.1f (left interior ends %.1f, right starts %.1f)  blade=%s",
        stalled, x, inner_left, inner_right, tostring(bladeSprite() ~= nil)))
    assert(x <= inner_left or x >= inner_right,
        string.format("heart is stranded in the gap at %.1f (left ends %.1f, right starts %.1f)",
            x, inner_left, inner_right))
    local in_left = x <= inner_left
    print("[LAND] containment placed the heart in the " .. (in_left and "left" or "right") .. " half")

    capture("wave01-split")

    -- Push hard across the cut: whichever half holds the heart has to keep it.
    hold("left", 90)
    local x_after = Player.sprite.x
    print(string.format("[LOCK] after 90 frames of left: x %.1f (was %.1f)", x_after, x))
    if (not in_left) then
        assert(x_after >= inner_right - 1,
            "heart crossed the cut into the left half: x=" .. tostring(x_after))
    else
        assert(x_after <= inner_left + 1,
            "heart crossed the cut into the right half: x=" .. tostring(x_after))
    end

    -- The blade clears the screen without a second hit.
    untilTrue(function() return bladeSprite() == nil end, "blade left the screen")
    frames(90)
    assert(Player.hp == hp0 - 10,
        "the blade hit more than once, hp is " .. tostring(Player.hp))

    -- The fourth intro line still needs its confirm and then Chara's closing
    -- lines follow, so press whenever the current line is fully typed until the
    -- round hands over rather than hard-coding how many lines that is.
    local presses = 0
    untilTrue(function()
        if (Battle.state ~= "DEFENDING") then return true end
        if (lineTyped(bubbleTyper())) then
            presses = presses + 1
            press("confirm")
        end
        return false
    end, "round handed over")
    print("[OUTRO] dismissed " .. presses .. " line(s) after the cut")
    settled("ACTIONSELECT")
    frames(60)

    -- ...and the BGM starts the moment that opening turn ends.
    assert(Battle._music_source ~= nil,
        "the battle BGM should start once the opening turn ends")

    -- Round 1's hand-over is pinned to the opening line, not sampled from the
    -- Random table: this is the battle's introduction, not a random peek.
    local default_line = Localize.localizeText("Battle.Narration.Default")
    local narration = Battle.GetNarration()
    print("[NARRATION] round 1: " .. tostring(narration))
    assert(narration == default_line,
        "round 1 should show Battle.Narration.Default, got " .. tostring(narration))

    -- ...and from round 2 the Random table takes over. EnterRound bumps
    -- Game.round when the next DEFENDING turn begins; poke it and drop the
    -- cached line rather than play a whole extra turn to observe it.
    Game.round = 2
    Battle._turnNarration = nil
    local later = Battle.GetNarration()
    print("[NARRATION] round 2: " .. tostring(later))
    assert(later ~= default_line and type(later) == "string" and later ~= "",
        "round 2's narration should be a random line, got " .. tostring(later))
    local random_pool = Localize.localizeText("Battle.Narration.Random")
    local matches = false
    for _, line in ipairs(random_pool) do
        if (line == later) then matches = true end
    end
    assert(matches, "round 2's narration is not from Battle.Narration.Random: " .. tostring(later))

    print(string.format("[END] state=%s arenas=%d mainarena %.1fx%.1f at %.1f,%.1f hp=%d canMove=%s",
        tostring(Battle.state), #Arenas.insts, Battle.mainarena.width, Battle.mainarena.height,
        Battle.mainarena.x, Battle.mainarena.y, Player.hp, tostring(Player.canMove)))
    assert(#Arenas.insts == 1, "the cut half should be cleared when the round ends, got " .. #Arenas.insts)
    assert(Player.hp > 0, "the player should have survived round 1")

    print("[OK] wave01 slash verified")
    love.event.quit(0)
end

function love.load(...)
    gameLoad(...)
    task = coroutine.create(run)
end

function love.update(dt)
    gameUpdate(dt)
    if coroutine.status(task) ~= "dead" then
        local ok, err = coroutine.resume(task)
        if not ok then error(debug.traceback(task, err)) end
    end
end

function love.draw()
    gameDraw()
    if screenshot then
        local name = screenshot
        love.graphics.captureScreenshot(function(data)
            data:encode("png", name .. ".png")
            screenshot = nil
        end)
    end
end
