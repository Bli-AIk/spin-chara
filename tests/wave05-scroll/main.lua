-- Run: SPIN_CHARA_WAVE=5 xvfb-run -a love-git --renderers opengl tests/wave05-scroll
local project=love.filesystem.getWorkingDirectory()
dofile(project.."/main.lua")
local gameLoad,gameUpdate,gameDraw=love.load,love.update,love.draw
local task,keys,capture=nil,{},nil
local function frames(n) for _=1,n do coroutine.yield() end end
local function first(m,kind)
    for _,k in ipairs(m.knives) do if k.kind==kind then return k end end
end
local function run()
    frames(3)
    local m=assert(Battle._wave and Battle._wave.barrage,"Wave 5 must load through the engine")
    assert(m.round==5 and m.config.wave05Profile and m.config.wave05Profile.wavePeriod==2.6)
    local oldController=Controller.GetState
    Controller.GetState=function(key) return keys[key] or 0 end
    local seen,entry,scroll,outro={},false,false,false
    local previousReach,rising,peaks=0,false,{}
    local originalLower,originalTop,count
    local driftChecked=false
    for _=1,60*70 do
        keys={}
        if m.caption then seen[m.caption[2]]=true end
        if m.opening then
            keys.confirm=1 -- Adapter still waits for the real typer's final pause.
            if m.player.x>200 then keys.left=2 end
        elseif m.stage==2 then
            entry=true
            assert(m.arena.w==280 and m.arena.h==156)
            assert(m.lights[1].y>=m.arena.y,"Light enters from below")
            if m.player.x>200 then keys.left=2 end
        elseif m.stage==3 then
            scroll=true
            local lower,top=first(m,"lower"),first(m,"top")
            if not originalLower then
                originalLower,originalTop,count=lower,top,#m.knives
                local y,offset=m.player.y,m.vars.scrollOffset
                frames(1)
                assert(math.abs(m.player.y-y-(m.vars.scrollOffset-offset))<1e-6,
                    "Real soul receives scroll drift exactly once")
                assert(math.abs(Player.sprite.y-m.player.y)<1e-6)
                driftChecked=true
            end
            assert(lower==originalLower and top==originalTop and #m.knives==count)
            assert(m.lights[1].y==m.arena.y and m.lights[1].fadeRadius==220)
            if seen['Wave05.Nap'] then assert(m.vars.scrollTime>7,"Nap speaks mid-scroll") end
            local r=m.vars.lowerWaveReach or 0
            if rising and r<previousReach then peaks[#peaks+1]={time=m.vars.waveTime,reach=previousReach} end
            rising=r>previousReach; previousReach=r
            local target=m.vars.finalTime and math.max(240,math.min(265,lower.baseY-43)) or 258
            if m.player.y>target+1 then keys.up=2 elseif m.player.y<target-1 then keys.down=2 end
            if m.vars.finalWaveClock and m.vars.finalWaveClock>.1 then
                if m.player.x<435 then keys.right=2 end
            elseif m.player.x>200 then keys.left=2 end
            if m.vars.finalWaveClock and m.vars.finalWaveClock>1.2 and not seen.crestCapture then
                capture='wave05-big-wave.png'; seen.crestCapture=true
            end
        elseif m.stage==4 and not m.done then
            outro=true
            assert(m.lights[1].y<=m.arena.y and m.darkAmount>=0 and m.darkAmount<=1)
            for _,k in ipairs(m.knives) do assert(not k.active and not k.warning) end
            if m.phaseTime>.7 and not seen.outroCapture then
                capture='wave05-outro.png'; seen.outroCapture=true
            end
        end
        if m.done then break end
        frames(1)
    end
    keys={}
    assert(m.done and entry and scroll and outro and driftChecked,"All four phases complete")
    assert(seen['Wave05.Intro'] and seen['Wave05.Nap'] and seen['Wave05.Reply'],"All localized dialogue plays")
    assert(m.hits==0,"Real movement and native hitboxes permit the tested no-hit route: "..m.hits)
    local before,last=peaks[#peaks-1],peaks[#peaks]
    assert(before and before.reach<77 and last.reach>111 and math.abs(last.time-before.time-2.6)<.04,
        "Final crest is higher, on exactly the same beat")
    for _=1,180 do
        if Battle.state=='ACTIONSELECT' then break end
        frames(1)
    end
    assert(Battle.state=='ACTIONSELECT',"Returns to the real action menu")
    assert(Battle.mainarena.white.visible and Battle.mainarena.black.visible)
    assert(#m.lights==0 and #m.knives==0 and not m.dark)
    for _,typer in ipairs(Typers.EText.insts) do assert(not typer.bubble,"No leftover dialogue bubble") end
    Controller.GetState=oldController
    print('[OK] engine wave05: dialogue / real drift / continuous final crest / no-hit route / fade / cleanup')
    love.event.quit(0)
end
function love.load(...)
    gameLoad(...)
    Global.SetVariable('FPS',10000)
    task=coroutine.create(run)
end
function love.update()
    for _=1,4 do
        gameUpdate(1/60)
        if coroutine.status(task)~='dead' then
            local ok,err=coroutine.resume(task)
            if not ok then error(debug.traceback(task,err)) end
        end
    end
end
function love.draw()
    gameDraw()
    if capture then love.graphics.captureScreenshot(capture); capture=nil end
end
