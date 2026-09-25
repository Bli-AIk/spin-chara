-- ACT -> Chara -> Recall must read back the rules announced so far and then hand
-- the turn straight back to the command menu, exactly like Check: no defense is
-- ever started.
--
-- It also has to fit the menu dialogue box, and that is the tight half of the
-- feature -- English is a 27px monospace and only three lines clear the box
-- before the text runs past it.  Rather than hardcode that budget, this measures
-- Recall against Check, which already ships in the same box, so the two are
-- compared on the same rulers.
--
-- Run from the project root (`-l en` exercises the wide font):
--   xvfb-run -a env ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=skip SPIN_CHARA_LANGUAGE=en \
--       love-git tests/act-recall
local project = love.filesystem.getWorkingDirectory()
dofile(project.."/main.lua")
local gameLoad, gameUpdate, gameDraw = love.load, love.update, love.draw
local task

local CHECK_INDEX, RECALL_INDEX = 1, 2
local ACT_BUTTON = 2

local function frames(n) for _=1,n do coroutine.yield() end end
local function untilTrue(pred, label)
    for _ = 1, 900 do
        if pred() then return end
        frames(1)
    end
    error("Timed out: "..label.." (state="..tostring(Battle.state)..")")
end
--- A state is only ready for the next press once its transition has finished;
--- pressing into a busy transition is simply swallowed.
local function settled(state)
    untilTrue(function() return Battle.state == state and not Battle.transition.busy end, state)
    frames(2)
end
local function press(action)
    local controller, keyboard = Controller.GetState, Keyboard.GetState
    Controller.GetState = function(key) return key == action and 1 or controller(key) end
    Keyboard.GetState = function(key) return key == action and 1 or keyboard(key) end
    frames(1)
    Controller.GetState, Keyboard.GetState = controller, keyboard
end

local pendingShot, menuShot
--- Renders the current frame to a PNG in the save directory, so the layout can
--- be looked at instead of inferred from the typer's bookkeeping.
local function capture(name)
    pendingShot = name
    frames(4)
    assert(not pendingShot, "screenshot callback did not run")
end

local function alive(typer)
    for _, other in ipairs(Typers.EText.insts) do
        if other == typer then return true end
    end
    return false
end

--- The dialogue typer, told apart from the turn's own narration, which lives in
--- the same registry under Battle.narration_text.
local function dialogue_typer()
    for _, typer in ipairs(Typers.EText.insts) do
        if typer ~= Battle.narration_text and typer.texts and typer.texts[1] then
            return typer
        end
    end
end

local function typed_out(typer)
    local sentence = typer.texts[typer.sentence_index]
    return sentence and typer.counter > #sentence
end

--- Top, right and bottom of what the current sentence drew, in screen space,
--- plus how many visual lines it landed on.  Letters carry typer-local offsets,
--- so the typer's own anchor goes back on.
---
--- Lines are counted by clustering the letters' own y offsets: the narration
--- star sits 8px below its line's baseline, while the smallest line advance
--- either locale can produce is far bigger than that, so a 12px tolerance
--- merges the star into its line and still separates real lines.
local LINE_TOLERANCE = 12
local function extent(typer)
    local top, right, bottom = 1e9, -1e9, -1e9
    local offsets = {}
    for _, letter in ipairs(typer.letters) do
        local scale = letter.scale or 1
        local x = typer.x + letter.x
        local y = typer.y + letter.y * scale
        top = math.min(top, y)
        right = math.max(right, x + letter.width * scale)
        bottom = math.max(bottom, y + letter.font:getHeight() * scale)
        offsets[#offsets + 1] = y
    end
    table.sort(offsets)
    local lines, last, starts = 0, nil, {}
    for _, y in ipairs(offsets) do
        if not last or y - last > LINE_TOLERANCE then
            lines = lines + 1
            starts[#starts + 1] = ("%.1f"):format(y)
        end
        last = y
    end
    return top, right, bottom, lines, table.concat(starts, ",")
end

--- Steps the cursor onto `index` in the action grid and confirms it.  The
--- command cursor keeps its position across turns, so park it on FIGHT first --
--- left is a no-op once it is already there.
local function open_action(index)
    -- The command cursor keeps its position between turns, so steer it by
    -- observation rather than by counting presses.
    for _ = 1, 6 do
        if UI.button_selecting == ACT_BUTTON then break end
        press("right")
    end
    assert(UI.button_selecting == ACT_BUTTON, "could not land on the ACT button")
    press("confirm")
    settled("ACTMENU")
    press("confirm")         -- Chara is the first enemy listed
    settled("ACTIONMENU")
    if menuShot then capture(menuShot) menuShot = nil end
    for _ = 2, index do press("right") end
    press("confirm")
    settled("DIALOGUERESULT")
end

--- Confirms through every screen, checking each one against the box as it goes.
--- Returns the worst right edge, the lowest baseline and the screen count.
--- `strict` asserts the text stays inside the box.  Check is measured but not
--- held to it: it is shipped content, so wherever it overflows, that is the
--- game's existing standard rather than something Recall has to beat.
local function walk(typer, label, shoot, strict)
    local arena = Battle.mainarena
    local boxRight = arena.x + arena.width / 2
    local boxBottom = arena.y + arena.height / 2
    local worstRight, lowestBottom, screens = -1e9, -1e9, 0
    while true do
        screens = screens + 1
        assert(screens <= 16, label..": dialogue never ended")
        untilTrue(function() return typed_out(typer) end,
            label.." screen "..screens.." to type out")
        if shoot then capture(("recall-%s-s%d"):format(shoot, screens)) end
        local top, right, bottom, lines, starts = extent(typer)
        print(("[recall] %s screen %d: %d line(s) at [%s], top %.1f, right %.1f (box %.1f), bottom %.1f (box %.1f) :: %s")
            :format(label, screens, lines, starts, top, right, boxRight, bottom, boxBottom,
                (typer.texts[typer.sentence_index] or ""):gsub("\n", " | ")))
        if strict then
            -- Horizontal overflow is the one this can be trusted on: a rule that
            -- runs past the box's right edge is really off the edge.  The
            -- vertical readout is not trustworthy -- the typer's letter list
            -- reports a stray cluster well below the last drawn line (Chinese,
            -- multi-line sentences) that the rendered frame does not contain, so
            -- the vertical fit is checked by looking at the captured PNGs.
            assert(right <= boxRight,
                ("%s screen %d draws %dpx past the box's right edge (box %.1f, text %.1f)")
                    :format(label, screens, right - boxRight, boxRight, right))
        end
        worstRight = math.max(worstRight, right)
        lowestBottom = math.max(lowestBottom, bottom)
        press("confirm")
        if not alive(typer) then break end
    end
    settled("ACTIONSELECT")
    return worstRight, lowestBottom, screens
end

-- Rules announced by the end of each round, cumulative.  Rounds 6-10 are the
-- placeholder wave and announce nothing, so the count stops moving at five.
local ANNOUNCED_BY_ROUND = {[1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 5}
local function rules_by(round)
    return ANNOUNCED_BY_ROUND[math.min(round, 5)]
end
local function screens_by(round)
    return 1 + math.ceil(rules_by(round) / 3)
end

--- The player's turn at `round`, however it was reached: assert the rules list
--- holds exactly what has been announced by then, walk every screen, and check
--- the turn comes straight back with no defense in between.
local function recall_at(round, shoot)
    local wasRound = Game.round
    open_action(RECALL_INDEX)
    local typer = dialogue_typer()
    assert(typer, "choosing Recall did not open the rules dialogue")
    assert(typer.texts[1] == Localize.localizeText("Battle.Rules.Intro"),
        "the dialogue must open on the lead-in, got "..tostring(typer.texts[1]))
    assert(#typer.texts == screens_by(round),
        ("round %d has announced %d rule(s), so it wants the lead-in plus %d screen(s), got %d")
            :format(round, rules_by(round), screens_by(round) - 1, #typer.texts))

    walk(typer, "Recall round "..round, shoot, true)

    assert(not dialogue_typer(), "the rules dialogue must be gone once the menu is back")
    assert(Game.round == wasRound, "Recall must not advance the round")
    -- The round's own narration is live again, not the rules text.
    assert(Battle.narration_text.texts and Battle.narration_text.texts[1],
        "the menu must go back to the turn's narration")
end

local function run()
    local wave = os.getenv("SPIN_CHARA_WAVE") or ""
    local skipRound = tonumber(wave:match("^skip%-(%d+)$"))
    assert(wave == "skip" or skipRound,
        "this check needs SPIN_CHARA_WAVE=skip or skip-N")
    local lang = os.getenv("SPIN_CHARA_LANGUAGE") or "zh_CN"
    frames(240)

    assert(Battle.state == "ACTIONSELECT", "expected the menu, got "..tostring(Battle.state))

    if skipRound then
        -- `-w skip-N` is the switch's own test: it must land on round N's
        -- player turn, with the next defense booked as wave N+1.
        assert(Game.round == skipRound,
            ("skip-%d must open on round %d, got %s"):format(skipRound, skipRound, tostring(Game.round)))
        assert(Battle.wave == ("wave%02d"):format(skipRound),
            ("skip-%d must book its own wave, got %s"):format(skipRound, tostring(Battle.wave)))
        recall_at(skipRound, lang)
        print("[OK] skip-"..skipRound.." opens the player's turn with every announced rule on it")
        love.event.quit(0)
        return
    end

    assert(Game.round == 1, "expected round 1, got "..tostring(Game.round))

    -- Check ships in this box already, so it is measured as a reference for what
    -- the game already accepts.  It is not held to the box: shipped Chinese
    -- Check overflows it, which is a pre-existing thing, not Recall's problem.
    open_action(CHECK_INDEX)
    local checkTyper = dialogue_typer()
    assert(checkTyper, "Check opened no dialogue")
    local checkRight, checkBottom, checkScreens = walk(checkTyper, "Check", nil, false)

    recall_at(1, nil)
    -- And the worst case, which is also the widest a rules screen ever gets:
    -- every rule the battle has, reached the way a player would reach it.
    Game.round = 5
    menuShot = "recall-menu-"..lang
    recall_at(5, lang)

    print(("[recall] Check %d screen(s) to %.1f wide / %.1f low")
        :format(checkScreens, checkRight, checkBottom))
    print("[OK] Recall lists the announced rules and hands the turn back without a defense")
    love.event.quit(0)
end

function love.load(...)
    gameLoad(...)
    Global.SetVariable("FPS",10000)
    task=coroutine.create(run)
end

function love.update()
    for _=1,4 do
        gameUpdate(1/60)
        if coroutine.status(task)~="dead" then
            local ok,err=coroutine.resume(task)
            if not ok then error(debug.traceback(task,err)) end
        end
    end
end

function love.draw()
    gameDraw()
    if pendingShot then
        local name = pendingShot
        love.graphics.captureScreenshot(function(data)
            data:encode("png", name..".png")
            print("[recall] wrote "..name..".png to "..love.filesystem.getSaveDirectory())
            pendingShot = nil
        end)
    end
end
