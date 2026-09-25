local C=require((...):match("(.-)[^%.]+$").."common")
local Knife=require((...):match("(.-)waves%.").."knife")

local W={arena={x=320,y=290,w=280,h=156},entryDuration=2,exitDuration=1.6,scrollDistance=960,
    stages={"Chara 开场", "聚光灯入场", "卷轴与刀尖", "聚光灯退场"}}
local fallback={kind="steady",moves={240/54,240/54,240/54,240/54},wavePeriod=2.6,pauses={0,0,0,0},
    warning=.48,thrust=.30,hold=.12,retract=.36,cooldown=.60}

local function profile(m) return m.config.wave05Profile or fallback end
local function lamp(m,y,opening)
    local light=C.light(m.arena.x,y,m.config.radius)
    light.fadeRadius=220
    light.expansion=opening or 1
    return light
end

function W.scrollDuration(p)
    local total=0
    for i=1,4 do total=total+p.moves[i]+p.pauses[i] end
    return total
end

function W.scrollAt(p,time)
    if p.kind=="steady" then return W.scrollDistance*C.clamp(time/W.scrollDuration(p)) end
    local elapsed=0
    for i=1,4 do
        local move,pause=p.moves[i],p.pauses[i]
        if time<elapsed+move then
            return (i-1)*W.scrollDistance/4+W.scrollDistance/4*C.clamp((time-elapsed)/move)
        end
        elapsed=elapsed+move
        if time<elapsed+pause then return i*W.scrollDistance/4 end
        elapsed=elapsed+pause
    end
    return W.scrollDistance
end

local function addRow(m,kind,y,angle)
    -- Use the game's authored blade width and seam, covering both frame edges.
    local pitch=Knife.pitch()
    local first,count=Knife.row(m.arena.x,m.arena.w-16,pitch)
    for i=0,count-1 do
        local k=m:knife(first+i*pitch,y,angle,1)
        k.kind,k.state,k.clock=kind,"idle",0
        k.baseY,k.worldY=y,y
        k.ready=kind~="top"
    end
end

function W.enter(m)
    local s,a=m.stage,m.arena
    if s==1 then
        m.dark=false; m.darkAmount=0; m.lights={}
        m.caption={"Chara","Wave05.Intro"}
    elseif s==2 then
        m.dark=true; m.darkAmount=0
        m.lights={lamp(m,a.y+a.h/2+110,0)}
    elseif s==4 then
        m.knives=m.vars.exitKnives or {}
        m.vars.exitKnives=nil
        for _,k in ipairs(m.knives) do k.active=false; k.warning=false end
    else
        m.dark=true; m.darkAmount=1
        m.vars.scrollTime=0; m.vars.scrollOffset=0
        m.vars.finalTime=nil; m.vars.waveTime=0; m.vars.dialogueStep=0
        m.vars.finalWaveClock=nil; m.vars.finalWaveStart=nil
        m.lights={lamp(m,a.y)}
        addRow(m,"lower",a.y+a.h/2+31,-math.pi/2)
        -- Ascending the scroll carries scenery down through the fixed viewport.
        -- The ceiling exists offscreen from the start; it has no entry tween.
        addRow(m,"top",a.y-a.h/2-8-W.scrollDistance,math.pi/2)
    end
end

function W.afterMove(m,dt)
    if m.stage==3 and not m.vars.finalTime then
        local nextOffset=W.scrollAt(profile(m),m.vars.scrollTime+dt)
        m.player.y=m.player.y+nextOffset-m.vars.scrollOffset
    end
end

function W.lighting(m)
    if m.stage==4 then
        local p=C.curve("quart",m.phaseTime/W.exitDuration)
        local light=lamp(m,C.lerp(m.arena.y,m.arena.y-m.arena.h/2-140,p),1-p)
        light.r=light.r*(1-p)
        m.lights={light}; m.darkAmount=1-p
        return
    end
    if m.stage~=2 then return end
    local p=C.curve("quart",m.phaseTime/W.entryDuration)
    m.darkAmount=p
    m.lights={lamp(m,C.lerp(m.arena.y+m.arena.h/2+110,m.arena.y,p),p)}
end

local function nearTip(m,k)
    local x,y=Knife.tip(k)
    local direction=k.kind=="top" and 1 or -1
    local dx,dy=m.player.x-x,m.player.y-y
    local ahead=dy*direction
    return ahead>=-2 and ahead<=22 and math.abs(dx)<=9 and dx*dx+dy*dy<=22*22
end

local function updateKnife(m,k,bulletDt)
    local p=profile(m)
    local direction=k.kind=="top" and 1 or -1
    if k.state=="idle" then
        k.y=k.baseY
        if k.ready and nearTip(m,k) then k.state="warn"; k.clock=0 end
    else
        k.clock=k.clock+bulletDt
        if k.state=="warn" and k.clock>=p.warning then k.state="out"; k.clock=0
        elseif k.state=="out" and k.clock>=p.thrust then k.state="hold"; k.clock=0
        elseif k.state=="hold" and k.clock>=p.hold then k.state="back"; k.clock=0
        elseif k.state=="back" and k.clock>=p.retract then k.state="cooldown"; k.clock=0
        elseif k.state=="cooldown" and k.clock>=p.cooldown then k.state="idle"; k.clock=0 end
    end
    local reach=0
    if k.state=="warn" then reach=-6*C.ease(k.clock/p.warning)
    elseif k.state=="out" then reach=28*C.curve("quart",k.clock/p.thrust)
    elseif k.state=="hold" then reach=28
    elseif k.state=="back" then reach=28*(1-C.ease(k.clock/p.retract)) end
    k.y=k.baseY+direction*reach
    k.warning=k.state=="warn"
    k.active=k.ready and k.state~="warn"
end

local function finishDialogue(m)
    if m.vars.dialogueStep==0 and m.vars.scrollOffset>=W.scrollDistance*.45 then
        m.vars.dialogueStep=1; m.caption={"Nap","Wave05.Nap","intermediate"}
    elseif m.vars.dialogueStep==1 and m:dialogueDone() then
        m.vars.dialogueStep=2; m.caption={"Chara","Wave05.Reply","intermediate"}
    elseif m.vars.dialogueStep==2 and m:dialogueDone() then
        m.vars.dialogueStep=3; m.caption=nil
    end
end

function W.update(m,dt,bulletDt)
    if m.stage==4 then
        local opacity=1-C.curve("quart",m.phaseTime/W.exitDuration)
        for _,k in ipairs(m.knives) do k.alpha=opacity; k.active=false end
        if m.phaseTime>=W.exitDuration then
            m.dark=false; m.darkAmount=0; m.lights={}; m:next()
        end
        return
    end
    if m.stage==1 then
        if m:dialogueDone() then m:next() end
        return
    end
    if m.stage==2 then
        if m.phaseTime>=W.entryDuration then m.darkAmount=1; m:next() end
        return
    end

    local v=m.vars
    if not v.finalTime then
        v.scrollTime=v.scrollTime+dt
        v.scrollOffset=W.scrollAt(profile(m),v.scrollTime)
        if v.scrollTime>=W.scrollDuration(profile(m)) then
            v.scrollOffset=W.scrollDistance; v.finalTime=0
        end
    else
        v.finalTime=v.finalTime+dt
    end
    finishDialogue(m)
    v.waveTime=v.waveTime+bulletDt
    local progress=v.scrollOffset/W.scrollDistance
    -- The whole lower row shares one beat: rise together, then retreat together.
    local period=profile(m).wavePeriod
    local phase=(v.waveTime/period)%1
    local amplitude=76
    if v.finalTime then
        if not v.finalWaveStart then
            -- Finish the current ordinary cycle without resetting its phase.
            -- The next scheduled cycle is simply taller, at the same tempo.
            v.finalWaveStart=(math.floor(v.waveTime/period)+1)*period
        end
        v.finalWaveClock=v.waveTime-v.finalWaveStart
        if v.finalWaveClock>=0 then amplitude=112 end
    end
    local reach=amplitude*math.sin(math.pi*phase)^2
    if v.finalWaveClock and v.finalWaveClock>=period then reach=0 end
    v.lowerWaveReach=reach
    for _,k in ipairs(m.knives) do
        if k.kind=="top" then
            k.baseY=k.worldY+v.scrollOffset
            k.ready=v.finalTime~=nil and v.finalTime>=.45
            updateKnife(m,k,bulletDt)
        else
            k.baseY=m.arena.y+m.arena.h/2+31-12*progress-reach
            updateKnife(m,k,bulletDt)
        end
    end
    if v.finalWaveClock and v.finalWaveClock>=period+.65 and v.dialogueStep==3 then
        local busy=false
        for _,k in ipairs(m.knives) do
            if k.state=="warn" or k.state=="out" or k.state=="hold" or k.state=="back" then
                busy=true; break
            end
        end
        if not busy or v.finalWaveClock>=period+2.15 then
            v.exitKnives=m.knives
            m:next()
        end
    end
end
return W
