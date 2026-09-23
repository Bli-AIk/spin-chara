-- Engine adapter for the adopted barrage models. No prototype input or UI.
local P="Scripts.Game.Barrage."
local Model=require(P.."model")
local Config=require(P.."config")
local Renderer=require(P.."renderer")
local Slash=require("Scripts.Game.Effects.opening_slash")
local Ease=require(P.."waves.common")
local B={presets={[2]=3,[3]=3,[4]=4,[5]=1}}
function B.start(round)
    local wave=ImportFile("Battle.Waves")
    local arena=Battle.mainarena
    local renderer=Renderer.new()
    local model,bubble,caption,captionKind,captionFinished,captionHold,overlay
    local effects,seenSlash,openingLaunchPlayed={},0,false
    local complete=true
    local oldDraw=Player.sprite.Draw
    local oldMove=arena.move_player
    local oldWhite,oldBlack=arena.white.visible,arena.black.visible
    local opening={from={x=arena.x,y=arena.y,w=arena.width,h=arena.height},time=0,duration=.8}
    local function clearBubble()
        if bubble then bubble._onComplete=nil; bubble:Destroy(); bubble=nil end
    end
    local function syncDialogue(m)
        local key=m.caption and m.caption[2]
        if not key then return end
        if key==caption then return end
        clearBubble()
        caption=key
        captionKind=m.caption[3] or (m.stage==1 and "opening" or "final")
        captionFinished=false
        captionHold=0
        complete=false
        local speaker=m.caption[1]
        local enemyIndex=speaker=="Nap" and 2 or 1
        local enemy=Battle.game and Battle.game.enemies and Battle.game.enemies[enemyIndex]
        local position=enemy and enemy.position or {speaker=="Nap" and 520 or 320,120}
        local width,height=210,100
        local x=math.max(25,position[1]-width-45)
        local y=math.max(35,position[2]-height/2+10)
        local text=Localize.localizeText("Battle.BarrageLab."..key)
        assert(type(text)=="string","Missing barrage localization: "..key)
        bubble=Typers.EText.New({"[colorHEX:000000]"..text},
            {x,y},"BarrageDialogue",{width,height},"none")
        bubble.font="speechbubble.ttf"; bubble.fontsize=13
        bubble.use_bondfont=false; bubble.scale=1; bubble.line_spacing=0
        bubble.skip.canskip=false
        bubble.auto_wrap=true; bubble:ShowBubble("right",.5)
        bubble.size[1]=width-20
    end
    local function updateDialogue(dt)
        if not bubble then return end
        -- A trailing [wait:] must finish before the line counts as spoken.
        if bubble.counter<=#bubble.texts[1] or not bubble.cantype then return end
        if not captionFinished then
            captionFinished=true
            if captionKind=="opening" then return end
        end
        if captionKind=="opening" then
            if Controller.GetState("confirm")==1 then
                clearBubble()
                complete=true
            end
        else
            complete=true
            if captionKind=="final" or captionKind=="intermediate" then
                captionHold=captionHold+dt
                if captionHold>=2 then clearBubble() end
            end
        end
    end
    Layers.new_layer("BarrageDialogue",61)
    local function syncArena(m)
        local a=m.arena
        arena:MoveTo(a.x,a.y,true); arena:Resize(a.w,a.h,true); arena:SyncSprites()
        arena.white.visible=false; arena.black.visible=false
        Player.sprite:MoveTo(m.player.x,m.player.y)
    end
    local config=round==3 and Config.wave03A() or Config.defaults(B.presets[round])
    if round==3 then
        config.horizontalYOffsets={love.math.random(-48,48),love.math.random(-48,48)}
    end
    model=Model.new(round,config,{
        mortal=true,
        -- SPIN_CHARA_INVINCIBLE: knives still spawn and collide, they just
        -- never reach Battle.OnHit, so the soul keeps its HP and its alpha.
        invincible=Battle.Invincible,
        -- The engine already moves the real soul before wave.Update.
        move=function(p) p.x,p.y=Player.sprite.x,Player.sprite.y end,
        hit=function(m,damage)
            if Player.hurt_time<=0 then
                Battle.OnHit({spin_damage=damage or m.config.damage,spin_hurt_time=m.config.hurtTime,
                    spin_punish=m.config.punishDamage})
            end
        end,
        -- Play one launch sample per volley, not one sample per knife.
        launch=function(m) Audio.PlaySound("knife.wav") end,
        dialogueDone=function(m) syncDialogue(m); return complete end,
        enter=function(m)
            syncDialogue(m)
            if round==3 and m.stage==3 then seenSlash=0 end
            if round==3 and m.stage==5 then
                for _,effect in ipairs(effects) do effect:Destroy() end
                effects={}
            end
        end,
        update=function(m)
            syncDialogue(m)
            if round==3 and m.stage==2 and m.vars.burstStarted and not openingLaunchPlayed then
                openingLaunchPlayed=true
                m:launch()
            end
            if round==3 and m.stage==3 then
                while seenSlash<(m.vars.slashCount or 0) do
                    seenSlash=seenSlash+1
                    local cut=seenSlash==1 and m.vars.leftCut or m.vars.rightCut
                    local a=m.wave.arena
                    local effect=Slash.New({x=cut,y=a.y,width=m.wave.expandedWidth,
                        height=a.h,thickness=4})
                    effect:Strike()
                    effects[#effects+1]=effect
                    Audio.PlaySound("heavyswing.wav")
                    Audio.PlaySound("disappear.wav")
                end
            end
        end,
    })
    model.player.x,model.player.y=Player.sprite.x,Player.sprite.y
    opening.target=Model.copy(model.arena)
    opening.duration=model.wave.reusesIncomingBox and 0 or .8
    opening.dark,opening.darkAmount=model.dark,model.darkAmount
    opening.lights,opening.knives=model.lights,model.knives
    model.arena=Model.copy(opening.from)
    model.dark=false; model.darkAmount=0; model.lights={}; model.knives={}
    model.opening=opening
    wave.barrage=model
    model.borderThickness=arena.thickness
    arena.move_player=false
    Player.canMove=true
    Player.sprite.Draw=function() end
    syncArena(model)
    overlay=Layers.add_external(function() renderer:draw(model) end,"TopAll")
    local destroyed=false
    table.insert(wave.objects,{Destroy=function()
        if destroyed then return end
        destroyed=true
        clearBubble()
        for _,effect in ipairs(effects) do effect:Destroy() end
        Layers.remove_external(overlay)
        model:destroy()
        Player.sprite.Draw=oldDraw
        arena.move_player=oldMove
        arena.white.visible=oldWhite; arena.black.visible=oldBlack
        arena:ResetSpeed()
        wave.barrage=nil
    end})
    function wave.Update(dt)
        model.player.hp=Player.hp
        model.player.hurt=math.max(0,Player.hurt_time/60)
        updateDialogue(dt)
        if opening then
            -- Dialogue advances through the engine while the attack simulation
            -- remains stopped. Only start resizing after the final pause.
            if complete then opening.time=math.min(opening.duration,opening.time+dt) end
            -- A zero-length opening still has to wait for the line, so the
            -- run is gated on `complete` and not on the clock alone.
            local progress=opening.duration>0 and Ease.curve("quart",opening.time/opening.duration) or 1
            for _,key in ipairs({"x","y","w","h"}) do
                model.arena[key]=Ease.lerp(opening.from[key],opening.target[key],progress)
            end
            local a=model.arena
            model.player.x=math.max(a.x-a.w/2+8,math.min(a.x+a.w/2-8,Player.sprite.x))
            model.player.y=math.max(a.y-a.h/2+8,math.min(a.y+a.h/2-8,Player.sprite.y))
            syncArena(model)
            if complete and progress>=1 then
                model.dark,model.darkAmount=opening.dark,opening.darkAmount
                model.lights,model.knives=opening.lights,opening.knives
                model.opening=nil; opening=nil
            end
            return
        end
        model:update(dt,{slow=Controller.GetState("cancel")>0})
        syncArena(model)
        if model.done and not bubble then wave.EndWave() end
    end
    return wave
end
return B
