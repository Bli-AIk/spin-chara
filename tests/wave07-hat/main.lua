-- Normal-engine integration of the adopted round 07 B prototype.
local project=love.filesystem.getWorkingDirectory()
dofile(project..'/main.lua')
local gameLoad,gameUpdate,gameDraw=love.load,love.update,love.draw
local task,keys,capture=nil,{},nil
local function frames(n) for _=1,n do coroutine.yield() end end
local function run()
    frames(3)
    local m=assert(Battle._wave and Battle._wave.barrage,'Normal wave 07 entry loads barrage')
    assert(m.round==7 and m.config.label=='B · 停顿抛接')
    assert(m.config.wave07Profile.gaps[1]==.85 and m.config.wave07Profile.easeTimes[1]==1.65)
    local original=Controller.GetState
    Controller.GetState=function(key) return keys[key] or 0 end
    local overlay=Layers.external_draws[#Layers.external_draws]
    local overridden=Player.sprite.Draw
    local seen,moving,drain={},false,false
    local launchSounds=0
    local play=Audio.PlaySound
    Audio.PlaySound=function(name,...) if name=='knife.wav' then launchSounds=launchSounds+1 end; return play(name,...) end
    for _=1,60*70 do
        keys={}
        if m.caption then seen[m.caption[2]]=true end
        if m.opening then
            keys.confirm=1
            assert(#m.knives==0 and not m.vars.hat,'No attacks during opening dialogue/resize')
        elseif m.stage==2 then
            assert(m.arena.w==280 and m.arena.h==180 and not m.dark and not m.curtain)
            local h=m.vars.hat
            if h and h.captured then keys[h.direction==1 and 'left' or 'right']=2; keys.up=2 end
            if m.vars.number<=2 then assert(#m.knives==0,'First two hats remain harmless') end
            if not seen.move and m.vars.number==0 then
                local x=m.player.x; keys={right=2}; frames(1)
                assert(math.abs(m.player.x-x-2)<1e-6,'Native movement occurs exactly once'); seen.move=true
            end
            if h and not seen.hat then capture='wave07-hat.png'; seen.hat=true end
            if h and h.captured and not seen.captured then capture='wave07-captured.png';seen.captured=true end
            for _,k in ipairs(m.knives) do
                assert(k.scale==1 and k.alpha==1 and not k.backdrop and not k.birthFraction)
                if k.proximityClock then seen.proximity=true end
                if k.kind=='flight' then seen.flight=true end
            end
            if m.vars.rowStop and #m.knives>0 then
                if not drain then capture='wave07-drain.png' end
                drain=true
            end
            if m.caption and m.caption[2]=='Wave07.Nap' and h then
                local x=h.x; frames(1)
                if m.vars.hat==h and h.x~=x then moving=true end
            end
        end
        assert(math.abs(Player.sprite.x-m.player.x)<1e-6 and math.abs(Player.sprite.y-m.player.y)<1e-6,'Real soul stays synchronized with hat carry')
        if m.done then break end
        frames(1)
    end
    keys={}
    assert(m.done and seen.move and seen.captured and seen.flight and drain,'Full native round completes')
    assert(seen['Wave07.Intro'] and seen['Wave07.Nap'] and seen['Wave07.Reply'] and moving,'Real bilingual dialogue keeps attack moving')
    assert(m.hits>0 and Player.hp<20 and Player.hp>0,'Native damage is applied without invulnerability')
    assert(m.vars.captures>0 and m.vars.captures==m.vars.releases,'All occupied hats release')
    assert(launchSounds==m.vars.launched and launchSounds>0,'Magnetic launches use native sound')
    assert(m.vars.emitted==m.vars.retired,'Every emitted knife exits naturally')
    for _=1,240 do if Battle.state=='ACTIONSELECT' then break end;frames(1) end
    assert(Battle.state=='ACTIONSELECT','Return to battle menu')
    assert(Battle.mainarena.white.visible and Battle.mainarena.black.visible)
    assert(Player.sprite.Draw~=overridden,'Restore native soul rendering')
    for _,entry in ipairs(Layers.external_draws) do assert(entry~=overlay,'Remove barrage overlay') end
    for _,typer in ipairs(Typers.EText.insts) do assert(not typer.bubble,'Remove dialogue bubbles') end
    assert(#m.knives==0 and #m.lights==0 and not m.vars.hat,'Clear all attack objects')
    Controller.GetState=original; Audio.PlaySound=play
    print('[OK] engine wave07 B '..Localize.currentLanguage..': movement, capture/release, live dialogue, streams, sound, menu and cleanup; hits='..m.hits..' hp='..Player.hp)
    love.event.quit(0)
end
function love.load(...)
    Localize.setFile(os.getenv('WAVE07_LANGUAGE') or 'zh_CN')
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
