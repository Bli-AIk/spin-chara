-- Real scene, native input/damage, normal wave10 wrapper and actual end scene.
local project=love.filesystem.getWorkingDirectory()
dofile(project..'/main.lua')
local gameLoad,gameUpdate,gameDraw=love.load,love.update,love.draw
local task,keys,capture=nil,{},nil
local function frames(n) for _=1,n do coroutine.yield() end end
local function run()
    frames(3)
    local m=assert(Battle._wave and Battle._wave.barrage,'Normal wave10 entry')
    assert(m.round==10 and not Battle.Invincible)
    m.vars.rng=73 -- Deterministic replay only in this test driver.
    local battle=Battle
    local enemies=Battle.game.enemies
    local nap=enemies[2].animation.sprite;local chara=enemies[1].animation.chara
    assert(nap and nap.path:find('spr_napstabattle'))
    local original=Controller.GetState
    Controller.GetState=function(key) return keys[key] or 0 end
    local overlay=Layers.external_draws[#Layers.external_draws]
    local overridden=Player.sprite.Draw
    local unsafe=os.getenv('WAVE10_ROUTE')=='unsafe'
    local abort=os.getenv('WAVE10_ROUTE')=='abort'
    local play,sounds=Audio.PlaySound,0
    Audio.PlaySound=function(name,...) if name=='snd_phurt.wav' then sounds=sounds+1 end;return play(name,...) end
    local heard,seen={},{}
    local startHP=Player.hp
    local switch=Scenes.switchTo
    local destination
    Scenes.switchTo=function(name,...) destination=name;return switch(name,...) end
    local function checkCleanup()
        assert(Player.sprite.Draw~=overridden,'Restore native soul rendering')
        for _,entry in ipairs(Layers.external_draws) do assert(entry~=overlay,'Remove overlay') end
        for _,typer in ipairs(Typers.EText.insts) do assert(not typer.bubble,'Clear bubbles') end
        assert(not m.vars.tears and #m.knives==0 and #m.lights==0 and not m.clothState and not m.curtain)
        assert(enemies[1].animation.running and enemies[2].animation.running,'Release actor control')
    end
    for frame=1,60*90 do
        keys={}
        if m.caption then heard[m.caption[2]]=true end
        assert(nap.xscale==2 and nap.yscale==2 and nap.y==120,'Nap only translates horizontally at constant height and scale')
        if m.opening then
            keys.confirm=1
            assert(m.vars.emitted==0,'Opening holds firing')
        elseif m.stage==2 then
            seen.enter=true
            if m.phaseTime>.4 and not seen.enterShot then capture='wave10-enter.png';seen.enterShot=true end
        elseif m.stage==3 then
            assert(m.arena.w==155 and m.arena.h==130 and #m.lights==0 and not m.dark)
            assert(nap.x==318 and nap.y==120,'Eye anchor uses actual translated engine actor')
            if not seen.nativeMove and not unsafe then
                local x=Player.sprite.x;keys.right=2;frames(1)
                assert(math.abs(Player.sprite.x-x-2)<1e-6,'Real movement exactly once')
                seen.nativeMove=true
            end
            if not unsafe then keys[m.phaseTime<5.6 and 'right' or 'left']=2 end
            if m.phaseTime>2 and not seen.attack then capture='wave10-attack.png';seen.attack=true end
            if abort and seen.attack then
                Battle.ChangeState('ACTIONSELECT')
                for _=1,120 do if Battle.state=='ACTIONSELECT' then break end;frames(1) end
                checkCleanup()
                assert(nap.x==520 and nap.y==120 and chara.x==320 and chara.visible,'Abort restores actors')
                assert(not Battle._end,'Abort does not finish encounter')
                print('[OK] engine wave10: interrupted wave restores actors, drawing and dialogue')
                love.event.quit(0);return
            end
        elseif m.stage==4 then
            assert(#m.vars.tears==0 and m.vars.frame>140,'Dialogue waits for final tears')
            seen.returning=true
            if m.phaseTime>1 and not seen.reply then capture='wave10-reply.png';seen.reply=true end
        elseif m.stage==8 then
            seen.exit=true
        end
        if m.done then break end
        frames(1)
    end
    keys={}
    assert(m.done and m.vars.emitted==28 and m.vars.frame>140,'Original attack completed')
    assert(seen.enter and seen.attack and seen.returning and seen.exit)
    for _,key in ipairs({'Intro','Nap','NapReply','Quit','Last'}) do assert(heard['Wave10.'..key],key) end
    if unsafe then
        assert(m.hits>=2 and startHP-Player.hp==m.hits*5 and sounds==m.hits,'Native damage/sound and 60-frame invulnerability')
        assert(heard['Wave10.ManyHits'])
    else
        assert(m.hits==0 and Player.hp==startHP and sounds==0 and heard['Wave10.FewHits'],'Native no-hit route')
    end
    assert(Battle.state=='WIN' and Battle._end,'Finale ends battle instead of returning to menu')
    assert(not chara.visible,'Departed Chara does not reappear during fade')
    checkCleanup()
    for _=1,120 do if destination then break end;frames(1) end
    assert(destination=='scene_end','Actual end scene reached')
    Controller.GetState=original;Audio.PlaySound=play;Scenes.switchTo=switch
    print('[OK] engine wave10 '..Localize.currentLanguage..' '..(unsafe and 'unsafe' or 'safe')..': fixed-size actors, native movement/damage, dialogue, cleanup and scene_end')
    print('[CAPTURE] '..love.filesystem.getSaveDirectory())
    love.event.quit(0)
end
function love.load(...)
    Localize.setFile(os.getenv('WAVE10_LANGUAGE') or 'zh_CN')
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
