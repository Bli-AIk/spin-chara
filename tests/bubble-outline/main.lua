-- Drives ACT -> Napstablook -> Applause and screenshots the enemy reply bubble,
-- so the black rim can be inspected on a real frame.
-- Run from the project root: xvfb-run -a love-git tests/bubble-outline
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

local function press(action)
    local controller, keyboard = Controller.GetState, Keyboard.GetState
    Controller.GetState = function(key) return key == action and 1 or controller(key) end
    Keyboard.GetState = function(key) return key == action and 1 or keyboard(key) end
    frames(1)
    Controller.GetState, Keyboard.GetState = controller, keyboard
    frames(2)
end

local function bubbleTyper()
    local acts = Game.act_effects
    local typer = acts and acts.typer
    if (typer and typer.bubble) then return typer end
    return nil
end

local function run()
    frames(3)
    -- White backdrop so the rim is measurable against a light background.
    local backdrop = Sprites.CreateSprite("px.png", "Background")
    backdrop:Pivot(0, 0)
    backdrop:MoveTo(0, 0)
    backdrop:Scale(640, 480)
    settled("ACTIONSELECT")
    press("right")    -- FIGHT -> ACT
    press("confirm")  -- -> ACTMENU
    settled("ACTMENU")
    press("down")     -- Chara -> Napstablook
    press("confirm")  -- -> ACTIONMENU
    settled("ACTIONMENU")
    press("right")    -- Check -> Applause
    press("confirm")  -- -> DIALOGUERESULT, runs the ACT
    settled("DIALOGUERESULT")
    -- Enemy line first, the bubble only once that one is confirmed.
    for _ = 1, 20 do
        if bubbleTyper() then break end
        press("cancel")
        press("confirm")
        frames(10)
    end
    local typer = bubbleTyper()
    assert(typer, "Reply bubble never appeared")
    print(string.format("[BUBBLE] %s at %.0f,%.0f size %sx%s direction %s rim %s",
        tostring(typer.bubble and "shown" or "missing"),
        typer.bubble.main_rect_h.x, typer.bubble.main_rect_h.y,
        tostring(typer.bubble.main_rect_h.xscale), tostring(typer.bubble.main_rect_h.yscale),
        tostring(typer._direction or "?"), tostring(typer.bubble.rim and #typer.bubble.rim or 0)))
    frames(4)
    capture("reply-bubble")
    print("[STATE] " .. tostring(Battle.state))
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
