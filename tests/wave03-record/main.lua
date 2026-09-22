-- Records the whole third-round defense with the soul invincible, one numbered
-- PNG per simulated 1/60 step. Exactly one step per drawn frame means the
-- sequence encodes at 60 fps with no dropped or duplicated frames, and reading
-- the canvas back keeps the window size, the compositor and the cursor out of
-- it entirely.
--
-- Run through `just record-wave3`, which owns the frame directory and the
-- ffmpeg pass. By hand:
--
--   xvfb-run -a env ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=3 \
--       SPIN_CHARA_INVINCIBLE=1 SPIN_RECORD_DIR=/tmp/frames \
--       love-git tests/wave03-record
local project=love.filesystem.getWorkingDirectory()
dofile(project.."/main.lua")
local gameLoad,gameUpdate,gameDraw=love.load,love.update,love.draw

local STEP=1/60
local MAXFRAMES=3000 -- ~24s is expected; past this it is a hang, not a round
local DIR=os.getenv("SPIN_RECORD_DIR")

local task
local model,stageAt,hitsAtStage4=nil,{},nil
local frames,wantCapture=0,false

---Counts distinct colours over an 8px grid — the same cheap "did anything
---render at all" check tests/template-update uses.
local function sampledColors(data)
    local seen,count={},0
    local w,h=data:getDimensions()
    for y=0,h-1,8 do
        for x=0,w-1,8 do
            local r,g,b=data:getPixel(x,y)
            local key=string.format("%.2f,%.2f,%.2f",r,g,b)
            if not seen[key] then seen[key]=true; count=count+1 end
        end
    end
    return count
end

---Encodes to an absolute path rather than through love.filesystem: the frame
---directory belongs to the caller, and the save directory would tie it to the
---identity and to XDG_DATA_HOME.
local function saveFrame(data)
    local file=assert(io.open(string.format("%s/%05d.png",DIR,frames),"wb"))
    file:write(data:encode("png"):getString())
    file:close()
end

local function run()
    assert(DIR,"SPIN_RECORD_DIR must point at a frame directory")
    assert(Battle.state=="DEFENDING","round 3 must open straight into DEFENDING")
    model=assert(Battle._wave and Battle._wave.barrage,"the round 3 barrage must be loaded")
    assert(model.round==3,"expected round 3, got "..tostring(model.round))
    assert(model.context.invincible==true,"SPIN_CHARA_INVINCIBLE did not reach the barrage model")
    -- A pending trigger would reload the scene mid-recording and silently start
    -- a second round, leaving the first frames plus a whole extra round behind.
    assert(not io.open(".reload_trigger","r"),"clear the pending .reload_trigger first")
    local canvas=assert(GetMainCanvas(),"MAIN_CANVAS is missing")
    assert(canvas:isReadable(),
        "MAIN_CANVAS is not readable; fall back to love.graphics.captureScreenshot")

    while not model.done do
        assert(frames<MAXFRAMES,"round 3 ran past "..MAXFRAMES.." frames without finishing")
        assert(Scenes.name_current=="Battle.scene_battle_init","the scene reloaded mid-recording")
        gameUpdate(STEP)
        frames=frames+1
        stageAt[model.stage]=stageAt[model.stage] or frames
        if model.stage==4 and not hitsAtStage4 then hitsAtStage4=model.hits end
        -- The step that ends the round has already torn the barrage down, so
        -- stop short of it: the last frame keeps the collapse's final pose.
        if model.done then break end
        wantCapture=true
        repeat coroutine.yield() until not wantCapture
    end

    -- The point of the run: the soul really did sit inside the knife field and
    -- the barrage still played out to its end.
    assert(model.hits>hitsAtStage4,"the soul never entered the knife field")
    assert(Player.hp==Player.maxhp,"an invincible soul must not lose HP")
    assert(Player.hurt_time==0,"an invincible soul must never blink")
    assert(stageAt[1] and stageAt[4] and stageAt[5],"all five stages must have run")
    print(string.format("[RECORD] frames=%d stages=%d/%d/%d/%d/%d hits=%d hp=%d/%d",
        frames,stageAt[1],stageAt[2],stageAt[3],stageAt[4],stageAt[5],
        model.hits,Player.hp,Player.maxhp))
    love.event.quit(0)
end

function love.load(...)
    -- No input during a recording, so pin the unified query to "nothing is
    -- pressed". Under load the engine does occasionally report a phantom
    -- `cancel` for a dozen frames; that would both cut the opening dialogue
    -- short (EText treats cancel as its skip key) and halve the bullet speed
    -- (wave03 slow-steps while the soul holds cancel in the dark), so the same
    -- command would produce a different number of frames on different runs.
    Controller.GetState=function() return 0 end
    -- main.lua seeds math.random from the wall clock and the opening slash
    -- throws randomised particles, so pin the sequence before anything loads.
    math.randomseed(0x5EED)
    gameLoad(...)
    -- The recorder owns the clock; main.lua's frame limiter must never sleep
    -- between steps.
    Global.SetVariable("FPS",10000)
    task=coroutine.create(run)
end

function love.update()
    -- Only ever resumed from here. Advancing the simulation anywhere else
    -- would break the one-step-per-frame guarantee.
    if coroutine.status(task)~="dead" then
        local ok,err=coroutine.resume(task)
        if not ok then error(debug.traceback(task,err)) end
    end
end

function love.draw()
    gameDraw()
    if wantCapture then
        wantCapture=false
        local data=love.graphics.readbackTexture(GetMainCanvas())
        if frames==1 or frames==stageAt[4] then
            assert(sampledColors(data)>=3,"blank rendered frame "..frames)
        end
        saveFrame(data)
    end
end
