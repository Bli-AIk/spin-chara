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
    local model,bubble,caption,fx,overlay
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
        if key==caption then return end
        clearBubble(); caption=key; complete=not key
        if not key then return end
        local nap=m.caption[1]=="Nap"
        local text=Localize.localizeText("Battle.BarrageLab."..key)
        assert(type(text)=="string","Missing barrage localization: "..key)
        bubble=Typers.EText.New({"[colorHEX:000000]"..text.."[next]"},
            {nap and 355 or 55,70},"BarrageDialogue",{210,100},"none")
        bubble.font="speechbubble.ttf"; bubble.fontsize=13
        bubble.use_bondfont=false; bubble.scale=1; bubble.line_spacing=0
        bubble.auto_wrap=true; bubble:ShowBubble(nap and "left" or "right",.5)
        bubble.size[1]=190
        bubble._onComplete=function() bubble=nil; complete=true end
    end
    Layers.new_layer("BarrageDialogue",61)
    local function syncArena(m)
        local a=m.arena
        arena:MoveTo(a.x,a.y,true); arena:Resize(a.w,a.h,true); arena:SyncSprites()
        arena.white.visible=false; arena.black.visible=false
        Player.sprite:MoveTo(m.player.x,m.player.y)
    end
    model=Model.new(round,Config.defaults(B.presets[round]),{
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
        -- Rounds two and four send their blades out as one fan or one volley, so
        -- the wave announces the launch and the sample lands with the blades
        -- leaving the box rather than with the stage or the light.
        launch=function(m) Audio.PlaySound("knife.wav") end,
        dialogueDone=function(m) syncDialogue(m); return complete end,
        enter=function(m)
            syncDialogue(m)
            if fx then fx:Destroy(); fx=nil end
            if round==3 and m.stage==2 then
                local a=m.wave.arena
                fx=Slash.New({x=a.x,y=a.y,width=a.w,height=a.h,thickness=4})
                fx:Strike()
                -- This beat cuts the frame in two just like round one's opening
                -- slash, so all of its samples play here, in the same order:
                -- the swing lands with the blade, then the cut's own pair, the
                -- box vanishing and the knife that split it.
                Audio.PlaySound("heavyswing.wav")
                Audio.PlaySound("disappear.wav")
            end
        end,
        update=function(m)
            syncDialogue(m)
            if round==3 and m.stage==1 and m.vars.warnStart and not fx then
                local a=m.arena
                fx=Slash.New({x=a.x,y=a.y,width=a.w,height=a.h,thickness=4})
            end
        end,
    })
    opening.target=Model.copy(model.arena)
    -- A wave that keeps the incoming box has nothing to resize, so its opening
    -- is only the hold that keeps the model paused for Chara's line.
    opening.duration=model.wave.reusesIncomingBox and 0 or .8
    opening.dark,opening.darkAmount=model.dark,model.darkAmount
    opening.lights,opening.knives=model.lights,model.knives
    model.arena=Model.copy(opening.from)
    model.player.x,model.player.y=Player.sprite.x,Player.sprite.y
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
        if fx then fx:Destroy(); fx=nil end
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
        if opening then
            -- Dialogue advances through the engine while the attack simulation
            -- remains stopped. Only start resizing after the final pause.
            if complete then opening.time=math.min(opening.duration,opening.time+dt) end
            -- Round three's opening slash is part of the box entrance. Let the
            -- warning advance with the resize; once it strikes, hand the arena
            -- to the wave immediately so the split animation runs at full speed.
            if round==3 and complete and model.stage==1 then
                model:update(dt,{slow=Controller.GetState("cancel")>0})
                if model.stage>1 then
                    model.opening=nil
                    opening=nil
                    syncArena(model)
                    return
                end
            end
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
        if model.done then wave.EndWave() end
    end
    return wave
end
return B
