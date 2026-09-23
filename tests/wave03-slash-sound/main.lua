-- Round three cuts its frame in two just like round one's opening does, so it
-- has to sound exactly like it: the heavy swing and the cut's pair all land on
-- the stage 1 -> 2 beat, each exactly once, while the warning stage before it
-- stays silent.
--
-- Run from the project root:
--   xvfb-run -a env ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=3 SPIN_CHARA_INVINCIBLE=1 \
--       love-git tests/wave03-slash-sound
local project=love.filesystem.getWorkingDirectory()
dofile(project.."/main.lua")
local gameLoad,gameUpdate,gameDraw=love.load,love.update,love.draw
local task

-- Round one's opening slash, by name and in the order it plays them: the swing
-- goes with the blade, then the cut with the box splitting in two, which owns
-- both of the samples left after it.
local SWING,CUT,KNIFE="heavyswing.wav","disappear.wav","knife.wav"
local SAMPLES={SWING,CUT,KNIFE}

local function frames(n) for _=1,n do coroutine.yield() end end

--- Records every sound the engine is asked to play and still lets the real call
--- through, so a sample that does not exist fails loudly instead of silently.
local function recordSounds()
    local names={}
    local real=Audio.PlaySound
    Audio.PlaySound=function(name,...)
        names[#names+1]=name
        return real(name,...)
    end
    return names,function() Audio.PlaySound=real end
end

local function count(names,want)
    local n=0
    for _,name in ipairs(names) do if name==want then n=n+1 end end
    return n
end

local function run()
    frames(3)
    assert(Battle.state=="DEFENDING","round 3 must open straight into DEFENDING")
    local model=assert(Battle._wave and Battle._wave.barrage,"the round 3 barrage must be loaded")
    assert(model.round==3,"expected round 3, got "..tostring(model.round))
    assert(model.stage==1,"round 3 must open on its warning stage")

    local names,stop=recordSounds()

    -- The warning stage is silent; every sample belongs to the beat the slash
    -- actually falls on, which is the first frame of the stage that splits the
    -- frame in two.
    local struckAt
    for i=1,3000 do
        frames(1)
        if count(names,SWING)>0 then struckAt=i break end
        assert(not model.done,"round 3 ended without ever swinging")
    end
    assert(struckAt,"the third round's slash never played "..SWING)
    assert(model.stage==2,"the slash must land on the stage 1 -> 2 cut, stage is "..tostring(model.stage))
    for _,sample in ipairs(SAMPLES) do
        assert(count(names,sample)==1,
            "round three must play "..sample.." once, got "..count(names,sample))
    end
    print(string.format("[SLASH] %s + %s + %s on frame %d, the frame is cut on stage %d",
        SWING,CUT,KNIFE,struckAt,model.stage))

    -- The slash keeps sweeping long after the cut; no sample may retrigger
    -- with it, the way round one's single blade only swings once.
    frames(60)
    for _,sample in ipairs(SAMPLES) do
        assert(count(names,sample)==1,
            sample.." replayed while the slash swept, "..count(names,sample).." times")
    end
    stop()

    -- "Same as round one" is the point of the change, so pin the two together:
    -- every sample has to resolve to a real file, and round one has to still be
    -- asking for exactly these names.
    local round1=assert(love.filesystem.read("Scripts/Game/Waves/wave01.lua"))
    for _,sample in ipairs(SAMPLES) do
        local resolved=Audio.ResolvePath("sound",sample)
        local info=love.filesystem.getInfo(resolved)
        assert(info and info.type=="file",sample.." does not resolve to a file: "..resolved)
        assert(round1:find('Audio.PlaySound("'..sample..'")',1,true),
            "round one no longer plays "..sample..", so round three no longer matches it")
        print("[SAMPLE] "..sample.." -> "..resolved)
    end

    print("[OK] round 3 slash plays round 1's "..SWING.." + "..CUT.." + "..KNIFE..", once each")
    love.event.quit(0)
end

function love.load(...)
    gameLoad(...)
    Global.SetVariable("FPS",10000)
    task=coroutine.create(run)
end

function love.update()
    gameUpdate(1/60)
    if coroutine.status(task)~="dead" then
        local ok,err=coroutine.resume(task)
        if not ok then error(debug.traceback(task,err)) end
    end
end

function love.draw()
    gameDraw()
end
