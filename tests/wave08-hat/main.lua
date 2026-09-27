-- SPIN_CHARA_WAVE=8 xvfb-run -a love-git --renderers opengl tests/wave08-hat
local project=love.filesystem.getWorkingDirectory()
dofile(project..'/main.lua')
local gameLoad,gameUpdate,gameDraw=love.load,love.update,love.draw
local task,keys,capture=nil,{},nil
local function frames(n) for _=1,n do coroutine.yield() end end
local function run()
    frames(3)
    local m=assert(Battle._wave and Battle._wave.barrage,'Normal wave 08 entry loads barrage')
    assert(m.round==8 and m.config.label=='C · 长短交替')
    assert(m.config.wave08Profile.speeds[1]==324 and m.config.wave08Profile.speeds[2]==418)
    assert(not Battle.Invincible,'Integration must exercise native damage')
    -- Test-only HP headroom lets a stationary soul survive the full eight-wave
    -- animation while every actual collision still runs through Battle.OnHit.
    Player.maxhp=80; Player.hp=80
    local original=Controller.GetState
    Controller.GetState=function(key) return keys[key] or 0 end
    local overlay=Layers.external_draws[#Layers.external_draws]
    local overridden=Player.sprite.Draw
    local heard,seen={},{}
    local sounds=0
    local play=Audio.PlaySound
    Audio.PlaySound=function(name,...) if name=='knife.wav' then sounds=sounds+1 end; return play(name,...) end
    local previousCurtain=false
    local entered,exited=0,0
    local cloth
    local movingDialogue=false
    local sawOut,sawBack,sawFlight=false,false,false
    local sawRow=false
    local startHP=Player.hp
    for frame=1,60*110 do
        keys={}
        if m.caption then heard[m.caption[2]]=true end
        if m.opening then
            keys.confirm=1
            assert(#m.knives==0 and not m.vars.hat,'No attack before opening dialogue confirmation')
        elseif m.stage==2 then
            local v=m.vars
            assert(m.arena.w==280 and m.arena.h==180)
            if v.number<4 or (v.number==4 and v.mode~='curtain') then
                assert(not m.curtain,'Four attacks precede the curtain')
            end
            if m.curtain and not previousCurtain then entered=entered+1; cloth=m.clothState end
            if m.curtain then
                assert(cloth==m.clothState,'Curtain stays across both aimed volleys and both rows')
                if v.number>=7 then assert(v.underAimed==2,'Two aimed volleys before rows') end
                if v.mode=='exit' then assert(v.number==8 and v.denseLaunched==2,'Lift only after both rows') end
            elseif previousCurtain then exited=exited+1 end
            previousCurtain=m.curtain
            local h=v.hat
            if h then
                if h.peekElapsed then
                    local distance=(h.x-h.peekStartX)*h.direction
                    if h.peekElapsed<=m.wave.peekMove and distance>12 and not sawOut then
                        sawOut=true; capture='wave08-extend.png'
                    end
                    if h.peekElapsed>m.wave.peekMove and distance<12 and not sawBack then
                        sawBack=true; capture='wave08-retract.png'
                    end
                elseif h.time>.2 and not sawFlight then
                    sawFlight=true;capture='wave08-throw.png'
                end
            end
            if m.caption and m.caption[2]=='Wave08.Nap' then
                for _,k in ipairs(m.knives) do if k.prepTime and k.prepTime>0 then movingDialogue=true end end
            end
            if v.mode=='dense' and not sawRow then
                assert(#m.knives==11,'Real round-02 blade row has eleven knives')
                for i=2,#m.knives do assert(m.knives[i].y-m.knives[i-1].y==16) end
                sawRow=true;capture='wave08-row.png'
            end
            if not seen.nativeMove and v.number==0 then
                local x=m.player.x; keys={right=2};frames(1)
                assert(math.abs(m.player.x-x-2)<1e-6,'Real soul moves exactly once')
                seen.nativeMove=true
            end
        end
        assert(math.abs(Player.sprite.x-m.player.x)<1e-6 and math.abs(Player.sprite.y-m.player.y)<1e-6,
            'Native soul stays synchronized with hat carry')
        if m.done then break end
        frames(1)
    end
    keys={}
    assert(m.done and sawOut and sawBack and sawFlight and sawRow and movingDialogue and seen.nativeMove,
        'Full C performance, visible hat windup and live speech')
    assert(heard['Wave08.Intro'] and heard['Wave08.Nap'] and heard['Wave08.Reply'],'Bilingual keys play')
    assert(entered==1 and exited==1 and m.vars.number==8 and m.vars.denseLaunched==2)
    assert(m.vars.normalLaunched==18 and m.vars.underAimed==2)
    assert(sounds==m.vars.normalLaunched+m.vars.denseLaunched,'One native launch sound per shot/row')
    assert(m.hits>0 and Player.hp<startHP and Player.hp>0,'Native damage is real and wave survives')
    for _=1,240 do if Battle.state=='ACTIONSELECT' then break end;frames(1) end
    assert(Battle.state=='ACTIONSELECT','Return to the actual menu')
    assert(Battle.mainarena.white.visible and Battle.mainarena.black.visible)
    assert(Player.sprite.Draw~=overridden,'Native soul rendering restored')
    for _,entry in ipairs(Layers.external_draws) do assert(entry~=overlay,'Barrage overlay removed') end
    for _,typer in ipairs(Typers.EText.insts) do assert(not typer.bubble,'Dialogue bubbles cleared') end
    assert(#m.knives==0 and #m.lights==0 and not m.vars.hat and not m.clothState and not m.curtain,
        'All eighth-round objects cleaned')
    Controller.GetState=original;Audio.PlaySound=play
    print('[OK] engine wave08 C '..Localize.currentLanguage..': peek/retract/throw, continuous cloth, volleys, real damage, sounds, dialogue, menu and cleanup; hp='..Player.hp)
    love.event.quit(0)
end
function love.load(...)
    Localize.setFile(os.getenv('WAVE08_LANGUAGE') or 'zh_CN')
    gameLoad(...);Global.SetVariable('FPS',10000);task=coroutine.create(run)
end
function love.update()
    for _=1,4 do
        gameUpdate(1/60)
        if coroutine.status(task)~='dead' then local ok,err=coroutine.resume(task);if not ok then error(debug.traceback(task,err)) end end
    end
end
function love.draw()
    gameDraw()
    if capture then love.graphics.captureScreenshot(capture);capture=nil end
end
