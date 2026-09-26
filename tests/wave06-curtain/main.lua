-- SPIN_CHARA_WAVE=6 xvfb-run -a love-git --renderers opengl tests/wave06-curtain
local project=love.filesystem.getWorkingDirectory()
dofile(project..'/main.lua')
local gameLoad,gameUpdate,gameDraw=love.load,love.update,love.draw
local task,keys,capture=nil,{},nil
local function frames(n) for _=1,n do coroutine.yield() end end
local function run()
    frames(3)
    local m=assert(Battle._wave and Battle._wave.barrage,'Wave 6 loads through the normal engine entry')
    assert(m.round==6 and m.config.label=='D · 逐趟加速')
    assert(m.config.spacing==require('Scripts.Game.Barrage.knife').pitch())
    local oldController=Controller.GetState
    Controller.GetState=function(key) return keys[key] or 0 end
    local slow=os.getenv('WAVE06_SLOW')=='1'
    local seen,turns={},{}
    local priorPass=0
    local overlay=Layers.external_draws[#Layers.external_draws]
    local overriddenDraw=Player.sprite.Draw
    local movingDialogue=false
    local previousSweep
    for i=1,60*100 do
        keys={}
        if m.caption then seen[m.caption[2]]=true end
        if slow then keys.cancel=2 end
        if m.opening then
            keys.confirm=1
            assert(m.opening.duration==0 and #m.knives==0,'Opening preserves incoming box and waits for the real dialogue')
            if m.player.y>316 then keys.up=2 elseif m.player.y<314 then keys.down=2 end
        elseif m.stage==2 then
            seen.entry=true
            assert(m.arena.w==155 and m.arena.h==130 and #m.knives==0)
            assert(m.lights[1].y<=m.arena.y,'Spotlight slides in from above')
        elseif m.stage==3 then
            local v=m.vars
            assert(#v.sweep==1 and v.sweep[1].x+30==m.arena.x+m.arena.w/2,'One blade hugs the right rim')
            if not seen.pitch then
                for k=2,#v.left do assert(v.left[k].y-v.left[k-1].y==m.config.spacing) end
                seen.pitch=true
            end
            if v.pass~=priorPass then turns[#turns+1]=v.clock; priorPass=v.pass end
            if v.curtainAt then assert(v.curtainAt>=7) end
            if m.caption and m.caption[2]=='Wave06.Nap' and previousSweep and v.sweepY~=previousSweep then movingDialogue=true end
            previousSweep=v.sweepY
            local target=320
            local careful=v.mode=='sweep' and m.curtain and m.wave.covered(m,280,m.player.y)
            if careful then target=280 end
            if v.mode=='sneak' then
                if m.player.x<340 then keys.right=2 end
            elseif (not careful or i%3==0) and m.player.x>target+1 then keys.left=2 end
            if not seen.move and v.mode=='sweep' and v.clock<1 then
                local x=m.player.x
                keys={right=2}
                frames(1)
                assert(math.abs(m.player.x-x-2)<1e-6,'Native movement is applied exactly once')
                seen.move=true
            end
            if v.mode=='sweep' and v.clock>5 and not m.curtain and not seen.before then
                capture='wave06-before.png'; seen.before=true
            end
            if careful and m.clothTransition.time>2.2 and not seen.covered then
                capture='wave06-covered.png'; seen.covered=true
            end
            if v.mode=='exit' and v.time>.6 and not seen.exit then
                assert(m.lights[1].y<m.arena.y and m.darkAmount>0 and m.darkAmount<1)
                for _,k in ipairs(m.knives) do assert(not k.active) end
                capture='wave06-exit.png'; seen.exit=true
            end
        end
        assert(math.abs(Player.sprite.x-m.player.x)<1e-6,'Real soul stays in sync')
        if m.done then break end
        frames(1)
    end
    keys={}
    assert(m.done and seen.entry and seen.covered and seen.exit and seen.move)
    assert(seen['Wave06.Intro'] and seen['Wave06.Nap'] and seen['Wave06.Reply'] and movingDialogue)
    assert(m.hits==0 and Player.hp==20,'Native collision permits the cautious route: '..m.hits)
    for i=3,6 do assert(turns[i]-turns[i-1]<turns[i-1]-turns[i-2]-.04,'D accelerates each return') end
    for _=1,240 do if Battle.state=='ACTIONSELECT' then break end; frames(1) end
    assert(Battle.state=='ACTIONSELECT','Return to actual menu')
    assert(Battle.mainarena.white.visible and Battle.mainarena.black.visible)
    assert(Player.sprite.Draw~=overriddenDraw,'Native player drawing restored')
    for _,entry in ipairs(Layers.external_draws) do assert(entry~=overlay,'Barrage overlay removed') end
    for _,typer in ipairs(Typers.EText.insts) do assert(not typer.bubble,'No remaining bubbles') end
    assert(#m.lights==0 and #m.knives==0 and not m.clothState and not m.curtain and not m.dark)
    Controller.GetState=oldController
    print('[OK] engine wave06 D: '..Localize.currentLanguage..' / slow='..tostring(slow)..' / native movement / cautious route / completion / dialogue / light / cleanup')
    love.event.quit(0)
end
function love.load(...)
    Localize.setFile(os.getenv('WAVE06_LANGUAGE') or 'zh_CN')
    gameLoad(...); Global.SetVariable('FPS',10000); task=coroutine.create(run)
end
function love.update()
    for _=1,4 do
        gameUpdate(1/60)
        if coroutine.status(task)~='dead' then local ok,err=coroutine.resume(task); if not ok then error(debug.traceback(task,err)) end end
    end
end
function love.draw()
    gameDraw()
    if capture then love.graphics.captureScreenshot(capture); capture=nil end
end
