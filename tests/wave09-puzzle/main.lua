-- SPIN_CHARA_WAVE=9 xvfb-run -a love-git --renderers opengl tests/wave09-puzzle
local project=love.filesystem.getWorkingDirectory()
dofile(project..'/main.lua')
local gameLoad,gameUpdate,gameDraw=love.load,love.update,love.draw
local task,keys,capture=nil,{},nil
local function frames(n) for _=1,n do coroutine.yield() end end
local function run()
    frames(3)
    local m=assert(Battle._wave and Battle._wave.barrage,'Normal wave 09 entry loads barrage')
    assert(m.round==9 and m.config.label=='04 · 幕布换边')
    assert(not Battle.Invincible,'Native damage stays enabled')
    Player.maxhp=100;Player.hp=100
    local original=Controller.GetState
    Controller.GetState=function(key) return keys[key] or 0 end
    local overlay=Layers.external_draws[#Layers.external_draws]
    local overridden=Player.sprite.Draw
    local play,sounds=Audio.PlaySound,0
    Audio.PlaySound=function(name,...) if name=='knife.wav' then sounds=sounds+1 end;return play(name,...) end
    local heard,seen={},{}
    local cloth,door
    local oldClock
    local unsafe=os.getenv("WAVE09_ROUTE")=="unsafe"
    local startHP=Player.hp
    local W=m.wave
    for frame=1,60*65 do
        keys={}
        if m.caption then heard[m.caption[2]]=true end
        if m.opening then
            keys.confirm=1
            assert(#m.knives==0 and not m.vars.hats,'Opening holds attacks until confirmation and resize')
        elseif m.stage==2 and not m.done then
            local v=m.vars
            assert(m.arena.w==340 and m.arena.h==190 and #m.lights==0)
            if not seen.nativeMove then
                local x=m.player.x;keys={right=2};frames(1)
                assert(math.abs(m.player.x-x-2)<1e-6,'Native movement applied exactly once')
                seen.nativeMove=true;keys={}
            end
            if not cloth and m.clothState then
                cloth=m.clothState;capture='wave09-right.png';seen.right=true
                assert(m.clothRect.x==410 and m.clothRect.w==80)
                for _,k in ipairs(m.knives) do if k.door then door=k end end
            end
            if v.switched=='pulling' and not seen.pulling then
                assert(v.hour==6 and m.clothTransition.kind=='exit' and m.clothState==cloth)
                capture='wave09-lift.png';seen.pulling=true
            elseif v.switched==true and m.clothState and m.clothState~=cloth and not seen.left then
                assert(m.clothRect.x==225 and m.clothRect.w==70 and m.clothTransition.kind=='enter')
                seen.left=true
            end
            if seen.left and not seen.fallen and m.clothTransition and m.clothTransition.time>2.15 then
                capture='wave09-left.png';seen.fallen=true
            end
            -- Actual controller input pushes the hat through the door after
            -- the switch. Lean off the blade axis once the tip pierces it.
            local h=v.hats[1]
            if not unsafe and seen.left and h and h.x>235 and not v.exit then
                local p=m.player
                local ty=W.threads(door,h.x,h.y) and h.y+18 or h.y
                if math.abs(p.y-ty)>1 then keys[p.y<ty and 'down' or 'up']=2 end
                if p.x<h.x+10 then keys.right=2 elseif math.abs(p.y-ty)<=3 then keys.left=2 end
            end
            if h and h.x<400 then seen.push=true end
            if v.solved and seen.fallen then seen.solved=true end
            if v.repelled>0 and seen.fallen then seen.repel=true end
            if m.caption and m.caption[2]=='Wave09.Nap' and oldClock and v.time>oldClock then
                seen.liveSpeech=true
            end
            oldClock=v.time
            if v.wallFired and not seen.wall then capture='wave09-wall.png';seen.wall=true end
            if v.exit and not seen.exit then capture='wave09-exit.png';seen.exit=true end
        end
        assert(math.abs(Player.sprite.x-m.player.x)<1e-6 and math.abs(Player.sprite.y-m.player.y)<1e-6,
            'Real soul stays synchronized with solid hat correction')
        if m.done then break end
        frames(1)
    end
    keys={}
    for _,key in ipairs({'nativeMove','right','pulling','left','fallen','liveSpeech','wall','exit'}) do
        assert(seen[key],'Observed '..key)
    end
    assert(m.done and m.vars.fired==12 and sounds==13,'Twelve aimed shots and one wall with native sound')
    assert(heard['Wave09.Intro'] and heard['Wave09.Nap'] and heard['Wave09.Reply'])
    if unsafe then
        assert(m.hits>0 and Player.hp<startHP and Player.hp>0,'Unsolved route exercises native damage')
    else
        assert(seen.push and seen.solved and seen.repel,'Real inputs deliver the hat and repel the wall')
        assert(m.hits==0 and Player.hp==startHP,'Careful input route shelters the real soul without damage')
    end
    for _=1,240 do if Battle.state=='ACTIONSELECT' then break end;frames(1) end
    assert(Battle.state=='ACTIONSELECT','Return to native action menu')
    assert(Battle.mainarena.white.visible and Battle.mainarena.black.visible)
    assert(Player.sprite.Draw~=overridden,'Restore native soul rendering')
    for _,entry in ipairs(Layers.external_draws) do assert(entry~=overlay,'Remove barrage overlay') end
    for _,typer in ipairs(Typers.EText.insts) do assert(not typer.bubble,'Clear dialogue bubbles') end
    assert(#m.knives==0 and #m.lights==0 and not m.vars.hats and not m.clothState
        and not m.clothRect and not m.clothTransition and not m.curtain and not m.ambient)
    Controller.GetState=original;Audio.PlaySound=play
    print('[OK] engine wave09 04 '..Localize.currentLanguage..' '..(unsafe and 'unsafe' or 'safe')..': movement, side switch, live speech, shelter/damage control, sound, menu and cleanup; hp='..Player.hp)
    print('[CAPTURE] '..love.filesystem.getSaveDirectory())
    love.event.quit(0)
end
function love.load(...)
    Localize.setFile(os.getenv('WAVE09_LANGUAGE') or 'zh_CN')
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
