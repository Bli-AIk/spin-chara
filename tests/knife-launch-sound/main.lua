-- The blades leaving the box is one beat in rounds two and four: round two fans
-- its knives out on each of the five repositioning moves, round four sends one
-- volley on each of the three stages before the curtain and each of the three
-- after it. Each launch is one sample -- knife.wav -- however many blades the
-- fan or the volley holds, and it lands while they are all still outside the
-- box, which is the only place a blade can leave from: the arena clips them
-- until they cross its edge.
--
-- Run from the project root:
--   xvfb-run -a env ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=2 \
--       love-git tests/knife-launch-sound
--   xvfb-run -a env ALSOFT_DRIVERS=null SPIN_CHARA_WAVE=4 \
--       love-git tests/knife-launch-sound
local project=love.filesystem.getWorkingDirectory()
dofile(project.."/main.lua")
local gameLoad,gameUpdate,gameDraw=love.load,love.update,love.draw
local task

local KNIFE="knife.wav"
-- Every launch of the round, named by the stage it falls on.
local LAUNCHES={[2]={3,4,5,6,7},[4]={4,6,8,11,13,15}}

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

--- A blade starts just past the edge it enters from and is clipped until it
--- crosses back in, so a launch sample has to land with every blade still out
--- there: the sound belongs to the blades leaving, not to them on their way.
local function outsideBox(m,k)
    local a=m.arena
    return k.x<a.x-a.w/2 or k.x>a.x+a.w/2 or k.y<a.y-a.h/2 or k.y>a.y+a.h/2
end

local function run()
    local round=tonumber(os.getenv("SPIN_CHARA_WAVE"))
    local stages=LAUNCHES[round or 0]
    assert(stages,"this check covers rounds 2 and 4, set SPIN_CHARA_WAVE to one of them, got "
        ..tostring(os.getenv("SPIN_CHARA_WAVE")))
    frames(3)
    local model=assert(Battle._wave and Battle._wave.barrage,
        "the round "..round.." barrage must be loaded")
    assert(model.round==round,"expected round "..round..", got "..tostring(model.round))

    local expected={}
    for _,stage in ipairs(stages) do expected[stage]=true end

    local names,stop=recordSounds()
    local launched,at={},count(names,KNIFE)
    local last=model
    for i=1,20000 do
        frames(1)
        if Battle._wave and Battle._wave.barrage then last=Battle._wave.barrage end
        local now=count(names,KNIFE)
        if now>at then
            local m,stage=last,last.stage
            assert(now==at+1,"stage "..stage.." played "..(now-at).." launch samples, not one")
            assert(expected[stage],"round "..round.." launched on stage "..stage
                ..", which is not one of its launch stages")
            assert(not launched[stage],"round "..round.." launched twice on stage "..stage)
            assert(#m.knives>1,"stage "..stage.." played one launch sample with "
                ..#m.knives.." blade(s) on screen, so the sample is not the fan's")
            for _,k in ipairs(m.knives) do
                assert(outsideBox(m,k),"stage "..stage.." played the launch sample with a blade "
                    .."already inside the box at "..string.format("%.1f,%.1f",k.x,k.y))
            end
            -- Round two's fan waits for the light it is thrown past, so its
            -- launch sits late in the move; round four's volley leaves as its
            -- stage opens, with nothing before it but the travel behind the box.
            if round==2 then
                assert(m.phaseTime>.3,"round two launched "..m.phaseTime
                    .."s into stage "..stage..", before the fan's thrust")
            else
                assert(m.phaseTime<.2,"round four launched "..m.phaseTime
                    .."s into stage "..stage..", and its volley leaves with the stage")
            end
            launched[stage]=#m.knives
            at=now
            print(string.format("[LAUNCH] round %d stage %d: %d blades leave, one %s on frame %d",
                round,stage,launched[stage],KNIFE,i))
        end
        if model.done then break end
    end
    stop()
    assert(model.done,"round "..round.." ended without finishing its barrage")

    for _,stage in ipairs(stages) do
        assert(launched[stage],KNIFE.." never played for round "..round.." stage "..stage)
    end
    assert(at==#stages,"round "..round.." played "..KNIFE.." "..at.." times, expected "..#stages)

    local resolved=Audio.ResolvePath("sound",KNIFE)
    local info=love.filesystem.getInfo(resolved)
    assert(info and info.type=="file",KNIFE.." does not resolve to a file: "..resolved)

    local blades=0
    for _,n in pairs(launched) do blades=blades+n end
    print(string.format("[OK] round %d launches %d times, one %s each, %d blades (%.1f per sample)",
        round,#stages,KNIFE,blades,blades/#stages))
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
