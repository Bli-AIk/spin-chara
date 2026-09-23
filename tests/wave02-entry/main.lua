-- Round two plays in the engine's own defense box, so nothing about the box may
-- move: the barrage starts with it already on screen and the whole opening beat
-- goes to the spotlight. The spotlight has to start entering the moment Chara's
-- line closes -- the battle freezes the barrage model through the line, so a
-- beat counted from the model clock would be served after it and read as a late
-- entrance.
--
-- Run from the project root:
--   xvfb-run -a env ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=2 \
--       love-git tests/wave02-entry
local project=love.filesystem.getWorkingDirectory()
dofile(project.."/main.lua")
local gameLoad,gameUpdate=love.load,love.update
local task

local function frames(n) for _=1,n do coroutine.yield() end end

--- Holds the cancel key, the way a player mashes X through the intro line, so
--- the entrance timing does not ride on the typer's own pacing.
local function holdSkip()
    local real=Controller.GetState
    Controller.GetState=function(name)
        if name=="cancel" then return 1 end
        return real(name)
    end
    return function() Controller.GetState=real end
end

local function run()
    frames(3)
    local model=assert(Battle._wave and Battle._wave.barrage,"the round 2 barrage must be loaded")
    assert(model.round==2,"expected round 2, got "..tostring(model.round))
    assert(model.opening and model.stage==1,"round 2 must open on Chara's line")
    local restore=holdSkip()

    local box={model.arena.x,model.arena.y,model.arena.w,model.arena.h}
    local fields={"x","y","w","h"}
    --- The box is the engine's defense box and has to stay exactly there, both
    --- in the model and in the arena the engine actually draws.
    local function boxHeld(where)
        for i,key in ipairs(fields) do
            assert(model.arena[key]==box[i],string.format("the box %s moved during %s: %s ~= %s",
                key,where,tostring(model.arena[key]),tostring(box[i])))
        end
        local arena=Battle.mainarena
        assert(arena.x==box[1] and arena.y==box[2]
            and arena.width==box[3] and arena.height==box[4],
            "the drawn arena left the box during "..where)
    end

    -- Chara's line is the whole opening; wait for it to close.
    local held
    for i=1,3000 do
        frames(1)
        boxHeld("the dialogue hold")
        if not model.opening then held=i break end
    end
    assert(held,"round 2 never left its dialogue hold")

    -- The spotlight has to be up on the next frames, not a beat later.
    local entry
    for i=1,10 do
        frames(1)
        boxHeld("the entrance")
        if model.stage==2 and model.lights[1] then entry=i break end
    end
    assert(entry,"the spotlight entrance never started after the line closed")
    assert(entry<=3,"the spotlight entrance started "..entry.." frames after the line closed")
    assert(model.darkAmount<.05,"the mask may only fade in with the slide, not before it")
    local light=model.lights[1]
    assert(light.x==box[1] and light.y<box[2]-box[4]/2 and light.r==model.config.radius,
        "the entrance starts above the box, centred and at full radius")
    assert(#model.knives==0,"no knife may cut into the entrance")

    -- It then slides down into the box and darkens the arena behind it.
    local landed
    for i=1,300 do
        frames(1)
        boxHeld("the entrance")
        if model.lights[1].y>=box[2] then landed=i break end
    end
    assert(landed,"the spotlight never reached the box centre")
    assert(model.darkAmount==1,"the mask must be fully in when the slide ends")
    assert(model.stage==2,"the entrance must run to its end, stage is "..tostring(model.stage))

    restore()
    print(string.format("[OK] round 2 keeps its box, spotlight enters %d frame(s) after the line, "
        .."lands %d frames later",entry,landed))
    love.event.quit(0)
end

function love.load(...)
    gameLoad(...)
    Global.SetVariable("FPS",10000) -- Fixed simulation ticks; don't sleep per test tick.
    task=coroutine.create(run)
end
function love.update()
    gameUpdate(1/60)
    if coroutine.status(task)~="dead" then
        local ok,err=coroutine.resume(task)
        if not ok then error(debug.traceback(task,err)) end
    end
end
function love.draw() end
