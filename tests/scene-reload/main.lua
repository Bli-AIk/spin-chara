-- Ctrl+R / F5 (reloadCurrentScene) from inside round 1, which is where it used
-- to crash: clearing the layers destroys the wave's live typer, and a typer takes
-- its whole bubble with it, so Layers.clear() dropped several entries in one go
-- and then indexed past the end.
-- Run from the project root: xvfb-run -a love-git tests/scene-reload
local project = love.filesystem.getWorkingDirectory()
dofile(project .. "/main.lua")

local gameLoad, gameUpdate = love.load, love.update
local task

local function frames(count)
    for _ = 1, count do coroutine.yield() end
end

local function press(action)
    local controller, keyboard = Controller.GetState, Keyboard.GetState
    Controller.GetState = function(key) return key == action and 1 or controller(key) end
    Keyboard.GetState = function(key) return key == action and 1 or keyboard(key) end
    frames(1)
    Controller.GetState, Keyboard.GetState = controller, keyboard
    frames(2)
end

local function run()
    frames(3)
    -- Walk logo -> battle, like a player would.
    for _ = 1, 20 do
        if (Battle and Battle.state) then break end
        press("confirm")
        frames(5)
    end
    frames(30)
    assert(Battle and Battle.state == "DEFENDING",
        "expected to reach round 1's DEFENDING turn, got " .. tostring(Battle and Battle.state))
    print("[RELOAD] before: state=" .. Battle.state ..
        " scene=" .. tostring(Scenes.name_current) ..
        " round=" .. tostring(Game.round) .. " arenas=" .. #Arenas.insts)

    -- Exactly what main.lua's reloadCurrentScene() does for Ctrl+R / F5.
    Localize.reload()
    ClearModuleTree("Scripts.Libraries")
    local sceneName = Scenes.name_current
    Scenes.UnloadModule(sceneName)
    Scenes.switchTo(sceneName)

    -- The switch is deferred by one frame; give the rebuilt scene time to run.
    for _ = 1, 240 do frames(1) end

    assert(Battle and Battle.state == "DEFENDING",
        "the reloaded scene should be back in round 1's DEFENDING turn, got " ..
        tostring(Battle and Battle.state))
    assert(#Arenas.insts >= 1, "the reloaded scene should have rebuilt its battle box")
    print("[RELOAD] after:  state=" .. Battle.state ..
        " round=" .. tostring(Game.round) .. " arenas=" .. #Arenas.insts)
    print("[OK] scene reload verified")
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
