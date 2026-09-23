-- Pressing X (cancel) has to finish the current sentence on the spot, wait
-- pauses included. Those pauses used to survive the skip twice over: the burst
-- stopped dead at every [wait:] tag / wait opt / setWaitTime, and a press
-- landing inside a running pause had to sit the rest of that pause out before
-- the skip could even start. Covers EText, NText and SText.
-- Run from the project root: xvfb-run -a env ALSOFT_DRIVERS=null love-git tests/typer-skip
local project = love.filesystem.getWorkingDirectory()
dofile(project .. "/main.lua")

local gameLoad, gameUpdate = love.load, love.update
local task

local function frames(count)
    for _ = 1, count do coroutine.yield() end
end

-- The game loop steps every live typer with the wall clock's dt. The test steps
-- its own typers by hand instead, so one pause is exactly N/60 seconds.
local function freezeTypers()
    Typers.EText.Update = function() end
    Typers.NText.Update = function() end
    Typers.SText.Update = function() end
end

local function newNText(texts, opts)
    local t = Typers.NText.New(texts, {40, 40}, 0, {560, 200}, opts, "manual")
    t.voices = {} -- keep the run silent
    return t
end

local function newSText(build)
    local t = Typers.SText.New(build, {40, 40}, 0, {560, 200}, "manual")
    t.voices = {}
    return t
end

local function newTyper(texts)
    local t = Typers.EText.New(texts, {40, 40}, 0, {560, 200}, "manual")
    t.voices = {} -- keep the run silent
    return t
end

local DT = 1 / 60
-- The default interval is 1/30, so an unskipped character costs two frames.
local function steps(t, count)
    for _ = 1, count do t:Update(DT) end
end

---Hold "cancel" (X) down for a single Update, exactly like a real press.
local function pressCancel(t)
    local controller, keyboard = Controller.GetState, Keyboard.GetState
    Controller.GetState = function(key) return key == "cancel" and 1 or controller(key) end
    Keyboard.GetState = function(key) return key == "cancel" and 1 or keyboard(key) end
    t:Update(DT)
    Controller.GetState, Keyboard.GetState = controller, keyboard
end

local function run()
    frames(3) -- let the boot scene settle
    freezeTypers()

    -- 1. A sentence that opens on a pause stays empty for as long as it says.
    local opening = newTyper({"[wait:0.5]Hello[wait:0.5] world"})
    steps(opening, 12) -- 0.2s, well inside the first 0.5s pause
    assert(#opening.letters == 0, "the leading [wait:0.5] should hold the text back")
    assert(opening.cantype == false, "the leading [wait:0.5] should park the typer")

    pressCancel(opening)
    assert(opening.counter > #opening.texts[1], "X must clear the whole sentence within one frame")
    assert(#opening.letters == 10, "X must put every character on screen, got " .. #opening.letters)
    assert(opening.skip.skipping == false, "the skip must end with the sentence")

    -- 2. X landing inside a running pause must not sit that pause out.
    local midway = newTyper({"Hello[wait:5] world"})
    local updates = 0
    midway._onUpdate = function() updates = updates + 1 end
    steps(midway, 30) -- 0.5s: "Hello" is out, then the typer parks on the 5s pause
    assert(#midway.letters == 5, "the text before [wait:5] should have typed out")
    assert(midway.cantype == false, "the typer should be parked on the [wait:5]")

    pressCancel(midway)
    assert(midway.counter > #midway.texts[1], "X mid-pause must clear the rest of the sentence at once")
    assert(#midway.letters == 10, "the tail of the sentence must be on screen, got " .. #midway.letters)
    assert(updates == 10, "every skipped character must still run _onUpdate, got " .. updates)

    -- 3. Untouched, the pause is still a pause, and typing resumes after it.
    local untouched = newTyper({"Hi[wait:0.5] there"})
    steps(untouched, 12) -- 0.2s: "Hi" is out, the pause starts right after it
    assert(#untouched.letters == 2, "the text before [wait:0.5] should have typed out")
    steps(untouched, 12) -- 0.2s further in
    assert(#untouched.letters == 2, "typing must stay paused until [wait:0.5] elapses")
    steps(untouched, 24) -- past the 0.5s mark
    assert(#untouched.letters > 2, "typing must resume once [wait:0.5] elapses, got " .. #untouched.letters)

    -- 4. NText: the wait opt from the opts table has to give way the same way.
    local ntext = newNText({"&Hello& world"}, {{}, {wait = 5}})
    steps(ntext, 30) -- 0.5s: "Hello" is out, then the typer parks on the 5s wait opt
    assert(#ntext.letters == 5, "the text before the wait opt should have typed out")
    assert(ntext.cantype == false, "the typer should be parked on the wait opt")

    pressCancel(ntext)
    assert(ntext.counter > #ntext.texts[1], "X mid-pause must clear the rest of the sentence at once")
    assert(#ntext.letters == 10, "the tail of the sentence must be on screen, got " .. #ntext.letters)

    -- 5. SText: same for a setWaitTime pause in the queue.
    local stext = newSText(function(self)
        self:addText("Hello")
        self:setWaitTime(5)
        self:addText(" world")
    end)
    steps(stext, 30)
    assert(#stext.letters == 5, "the text before setWaitTime should have typed out")
    assert(stext.cantype == false, "the queue should be parked on the setWaitTime item")

    pressCancel(stext)
    assert(stext.queue_index > #stext.queue, "X mid-pause must drain the queue at once")
    assert(#stext.letters == 10, "the tail of the queue must be on screen, got " .. #stext.letters)

    print("[OK] typewriter skip runs through [wait:] for EText, NText and SText")
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
