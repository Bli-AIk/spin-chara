-- `-w skip` (SPIN_CHARA_WAVE=skip) is the dev switch that opens the battle on
-- the player's turn instead of the scripted opening enemy turn. Three things
-- have to hold at once: the menu must be live on launch, the wave SetGame
-- loaded for that skipped turn must leave nothing behind (it is ended and
-- unloaded before it ever updates), and the round bookkeeping must still hand
-- the *next* defense the following wave rather than replaying the skipped one.
--
-- Run from the project root:
--   xvfb-run -a env ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=skip \
--       love-git tests/skip-to-player-turn
local project=love.filesystem.getWorkingDirectory()
dofile(project.."/main.lua")
local gameLoad,gameUpdate,gameDraw=love.load,love.update,love.draw
local task

local function frames(n) for _=1,n do coroutine.yield() end end

--- How many speech bubbles are on screen. The skipped wave owns the opening
--- dialogue, so a bubble here is the wave surviving its own removal.
local function bubbles()
    local count=0
    for _,typer in ipairs(Typers.EText.insts) do
        if typer.bubble then count=count+1 end
    end
    return count
end

local function run()
    assert(os.getenv("SPIN_CHARA_WAVE")=="skip","this check needs SPIN_CHARA_WAVE=skip")
    frames(240) -- long enough for the menu transition to commit

    assert(Battle.state=="ACTIONSELECT",
        "skip must open on the player's turn, got "..tostring(Battle.state))
    assert(Game.round==1,"skip must land on round 1, got "..tostring(Game.round))
    assert(Battle.wave=="wave01",
        "the round stays booked as wave01, got "..tostring(Battle.wave))
    assert(not Battle._wave.barrage,"the skipped wave must not survive into the menu")
    assert(bubbles()==0,"skip left a speech bubble in the action menu")

    -- The menu has to carry the turn's narration, which on round 1 is the
    -- battle's opening line (see scene_battle_init's Game.narration override).
    local expected=Localize.localizeText("Battle.Narration.Default")
    local texts=Battle.narration_text.texts
    assert(texts and texts[1]==expected,
        "the menu must open on the round's narration, got "..tostring(texts and texts[1]))

    -- Leaving the menu runs the defense the skipped turn would have led into.
    Battle.ChangeState("DEFENDING")
    for _=1,600 do
        frames(1)
        if Battle.state=="DEFENDING" then break end
    end
    assert(Battle.state=="DEFENDING","the next defense never started")
    assert(Battle.wave=="wave02",
        "skipping is final: expected wave02 next, got "..tostring(Battle.wave))
    assert(Battle._wave.barrage and Battle._wave.barrage.round==2,
        "wave02's barrage must be the loaded one")

    print("[OK] -w skip opens the player's turn and keeps the round order")
    love.event.quit(0)
end

function love.load(...)
    gameLoad(...)
    Global.SetVariable("FPS",10000) -- Fixed simulation ticks; don't sleep per test tick.
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

function love.draw() gameDraw() end
