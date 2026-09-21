local project=love.filesystem.getWorkingDirectory()
dofile(project.."/main.lua")
local gameLoad,gameUpdate,gameDraw=love.load,love.update,love.draw
local task,capture
local drawTime,drawCount=0,0
local updateTime,updateCount=0,0
local function frames(n) for _=1,n do coroutine.yield() end end
local function run()
    frames(5)
    local requested=tonumber(os.getenv("SPIN_CHARA_WAVE"))
    if requested then
        assert(Battle._wave.barrage and Battle._wave.barrage.round==requested,
            "Direct launch must load the requested wave, not just change its number")
    end
    for _,round in ipairs({2,3,4,5}) do
        if Battle._wave and Battle._wave.EndWave then Battle._wave.EndWave() end
        -- Exercise the normal defense transition and the real wave loader.
        Battle.ChangeState("ACTIONSELECT")
        frames(180)
        Game.round=round-1
        Player.hp=20
        Battle.ChangeState("DEFENDING")
        local seen,curtain,finished=false,false,false
        local openingSeen,transitionSeen=false,false
        for i=1,12000 do
            local m=Battle._wave and Battle._wave.barrage
            if m then
                seen=true
                if m.opening then
                    openingSeen=true
                    local o=m.opening
                    assert(m.stage==1 and m.attackTime==0 and #m.knives==0,
                        "No attack may run during opening dialogue or resizing")
                    if o.time==0 then
                        assert(m.arena.w==o.from.w and m.arena.h==o.from.h,
                            "Opening dialogue must preserve the incoming arena")
                    elseif o.time<o.duration then
                        transitionSeen=true
                        assert(m.arena.w~=o.target.w or m.arena.h~=o.target.h,
                            "Opening resizing must interpolate, not snap")
                    end
                end
                assert(m.round==round)
                assert(m.config.label:sub(1,1)==(round==5 and "A" or round==4 and "D" or "C"))
                curtain=curtain or m.curtain
                Player.hp=20 -- Survive unattended attacks; still run real hit handling.
                if i==600 then capture="round-"..round..".png" end
            elseif seen and Battle.state=="ACTIONSELECT" then finished=true; break end
            frames(1)
        end
        assert(seen and finished,"Real battle round did not finish: "..round)
        assert(openingSeen and transitionSeen,"Opening dialogue and eased resize must both run")
        for _,typer in ipairs(Typers.EText.insts) do assert(not typer.bubble,"Wave left a speech bubble in the action menu") end
        print(string.format("[PROFILE] round %d draw CPU %.2f ms",round,1000*drawTime/math.max(1,drawCount)))
        print(string.format("[PROFILE] round %d update CPU %.2f ms",round,1000*updateTime/math.max(1,updateCount)))
        drawTime,drawCount=0,0
        updateTime,updateCount=0,0
        assert(Battle.mainarena.white.visible and Battle.mainarena.black.visible,
            "Arena visibility must be restored")
        if round==4 then assert(curtain,"Adopted curtain was not used") end
        print("[OK] real round "..round..": selected preset, dialogue, render, completion and cleanup")
    end
    love.event.quit(0)
end
function love.load(...)
    gameLoad(...)
    Global.SetVariable("FPS",10000) -- Fixed simulation ticks; don't sleep per test tick.
    task=coroutine.create(run)
end
function love.update()
    for _=1,4 do
        local started=love.timer.getTime()
        gameUpdate(1/60)
        updateTime=updateTime+love.timer.getTime()-started; updateCount=updateCount+1
        if coroutine.status(task)~="dead" then
            local ok,err=coroutine.resume(task)
            if not ok then error(debug.traceback(task,err)) end
        end
    end
end
function love.draw()
    local started=love.timer.getTime()
    gameDraw()
    drawTime=drawTime+love.timer.getTime()-started; drawCount=drawCount+1
    if capture then love.graphics.captureScreenshot(capture); capture=nil end
end
