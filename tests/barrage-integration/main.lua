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
        local radii,overlapping={},false
        local fan={}
        local ring={}
        local lightRadius
        local fourthShots,entrySeen={},false
        for i=1,12000 do
            local m=Battle._wave and Battle._wave.barrage
            if m then
                seen=true
                if round==3 and m.vars.squeezeBounds then
                    local b=m.vars.squeezeBounds
                    assert(m.vars.squeezeEdge=="left" or m.vars.squeezeEdge=="right",
                        "Third round may only compress a left or right edge")
                    assert(math.abs(m.arena.y-m.arena.h/2-b.top)<1e-8
                        and math.abs(m.arena.y+m.arena.h/2-b.bottom)<1e-8,
                        "Third round top and bottom must remain fixed")
                end
                assert(m.borderThickness==Battle.mainarena.thickness,"Barrage frame must preserve engine border width")
                if round==4 then
                    if m.stage==2 then
                        entrySeen=true
                        assert(m.lights[1].y<=m.arena.y,"Fourth spotlight slides down into the box")
                    end
                    if m.stage==4 or m.stage==6 or m.stage==8 or m.stage==11 or m.stage==13 or m.stage==15 then
                        fourthShots[m.stage]=true
                    end
                end
                if m.opening then
                    openingSeen=true
                    local o=m.opening
                    assert(m.stage==1 and m.attackTime==0 and #m.knives==0,
                        "No attack may run during opening dialogue or resizing")
                    if o.duration==0 then
                        -- A wave that keeps the incoming box holds the model for
                        -- the line alone, so the box may not move at all.
                        assert(m.arena.x==o.from.x and m.arena.y==o.from.y
                            and m.arena.w==o.from.w and m.arena.h==o.from.h,
                            "Reusing the incoming box must not resize it")
                    elseif o.time==0 then
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
                if round==2 and m.stage>=3 and m.stage<=7 then
                    radii[m.stage]=m.vars.target.r
                    lightRadius=m.config.radius
                    if not fan[m.stage] and #m.knives>0 then
                        fan[m.stage]=true
                        -- The fan is centred on the box, so the blades straddle
                        -- the centre line and an odd count puts one on it.
                        local axis=m.knives[1].axis
                        local centre=axis=="x" and m.arena.y or m.arena.x
                        local positions={}
                        for _,k in ipairs(m.knives) do positions[#positions+1]=k.perpendicular end
                        table.sort(positions)
                        for i=1,#positions do
                            assert(math.abs(positions[i]+positions[#positions+1-i]-2*centre)<1e-9,
                                "Round 2 knives must straddle the box centre symmetrically")
                        end
                        if #positions%2==1 then
                            assert(math.abs(positions[(#positions+1)/2]-centre)<1e-9,
                                "Round 2's middle knife must sit on the box centre line")
                        end
                    end
                    if m.phaseTime<m.vars.duration then
                        for _,k in ipairs(m.knives) do overlapping=overlapping or k.active end
                    end
                    -- Once the thrust is over, the fan must still be skirting the
                    -- light: a fan whose blades all travelled the same distance
                    -- went straight past it and stabbed the far edge.
                    if not ring[m.stage] and m.phaseTime>m.vars.duration+.15 then
                        ring[m.stage]=true
                        local near,far=math.huge,-1
                        for _,k in ipairs(m.knives) do
                            local travel=math.abs(k.stop-k.start)
                            near,far=math.min(near,travel),math.max(far,travel)
                        end
                        assert(far-near>1e-9,
                            "Round 2 knives must ring the light, not thrust past it")
                    end
                end
                Player.hp=20 -- Survive unattended attacks; still run real hit handling.
                if i==600 then capture="round-"..round..".png" end
            elseif seen and Battle.state=="ACTIONSELECT" then finished=true; break end
            frames(1)
        end
        assert(seen and finished,"Real battle round did not finish: "..round)
        assert(openingSeen,"Opening dialogue must run before the attacks")
        if round~=2 then assert(transitionSeen,"Opening resize must be eased, not snapped") end
        if round==2 then
            local moves=0
            for _ in pairs(radii) do moves=moves+1 end
            assert(moves==5,"Round 2 must reposition the spotlight five times, saw "..moves)
            for stage=4,7 do
                assert(radii[stage-1]>radii[stage],"Every light move must shrink the core")
            end
            -- The five moves end at half the radius the three-move schedule
            -- used to leave on its last move (58% of the full one).
            assert(math.abs(radii[7]/lightRadius-.29)<1e-9,
                "The fifth move must leave the core at half the old minimum")
            assert(overlapping,"Knives must launch before the spotlight finishes moving")
        end
        for _,typer in ipairs(Typers.EText.insts) do assert(not typer.bubble,"Wave left a speech bubble in the action menu") end
        print(string.format("[PROFILE] round %d draw CPU %.2f ms",round,1000*drawTime/math.max(1,drawCount)))
        print(string.format("[PROFILE] round %d update CPU %.2f ms",round,1000*updateTime/math.max(1,updateCount)))
        drawTime,drawCount=0,0
        updateTime,updateCount=0,0
        assert(Battle.mainarena.white.visible and Battle.mainarena.black.visible,
            "Arena visibility must be restored")
        if round==4 then
            assert(curtain and entrySeen,"Fourth round needs curtain and spotlight entrance")
            local count=0; for _ in pairs(fourthShots) do count=count+1 end
            assert(count==6,"Fourth round needs three attacks before and three after the curtain")
        end
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
