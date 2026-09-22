local P="prototypes.barrage-lab.waves."
local Baseline=require(P.."wave03-baseline")
local Pattern=require(P.."wave03-pattern")
local W={}
for k,v in pairs(Baseline) do W[k]=v end
function W.enter(m)
    Baseline.enter(m)
    if m.stage==4 then Pattern.enter(m) end
end
function W.lighting(m,dt)
    local l=m.lights[1]
    m.vars.previousLight=l and {x=l.x,y=l.y} or nil
    Baseline.lighting(m,dt)
end
function W.update(m,dt)
    if m.stage==4 then Pattern.update(m,dt) else Baseline.update(m,dt) end
end
return W
-- Legacy implementation retained below in history; the adapter above is the
-- only returned wave used by the live battle.
--[[
local W={arena={x=320,y=315,w=422,h=156},knifeEntryDistance=72,
    knifeExitDistance=620,normalSpeedMultiplier=2,slowMultiplier=2,minPlayerSpan=32,
    dropDuration=1.05,dropDistance=260,
    stages={"竖劈","双框分离","彼岸亮灯","环刃","收束"}}
local function layout(m,t)
    local original=W.arena
    local gap=C.lerp(0,18,C.ease(t))
    local width=(original.w-gap)/2
    local offset=(width+gap)/2
    m.arena={x=original.x+m.vars.side*offset,y=original.y,w=width,h=original.h}
    m.otherArena={x=original.x-m.vars.side*offset,y=original.y,w=width,h=original.h}
end
local function random(m)
    m.vars.rng=(m.vars.rng*48271)%2147483647
    return (m.vars.rng-1)/2147483646
end
local function target(m)
    local a=m.otherArena
    return {x=a.x+(random(m)*2-1)*(a.w/2-m.config.radius-12),
        y=a.y+(random(m)*2-1)*(a.h/2-m.config.radius-12)}
end
local function chooseSqueezeEdge(m)
    local a,p=m.arena,m.player
    local bounds={left=a.x-a.w/2,right=a.x+a.w/2,top=a.y-a.h/2,bottom=a.y+a.h/2}
    -- Compress the player's box toward the spotlight box, independent of the
    -- player's current position: left-side player pulls from the left wall,
    -- right-side player pulls from the right wall.
    local edge=m.vars.side==-1 and "left" or "right"
    m.vars.squeezeBounds=bounds
    m.vars.squeezeEdge=edge
end
local function squeezeArena(m)
    local b=m.vars.squeezeBounds
    local p=C.ease(m.vars.squeezeTime/m.vars.squeezeDuration)
    local left,right,top,bottom=b.left,b.right,b.top,b.bottom
    if m.vars.squeezeEdge=="left" then left=C.lerp(left,right-W.minPlayerSpan,p)
    else right=C.lerp(right,left+W.minPlayerSpan,p) end
    m.arena={x=(left+right)/2,y=(top+bottom)/2,w=right-left,h=bottom-top}
end
function W.enter(m)
    local s,c=m.stage,m.config
    if s==1 then
        m.dark=false; m.darkAmount=0; m.lights={}; m.otherArena=nil
        m.vars.warnStart=nil
        m.caption={"Chara","Wave03.Intro"}
    elseif s==2 then
        m.vars.side=m.player.x<W.arena.x and -1 or 1
        layout(m,0)
    elseif s==3 then
        layout(m,1); m.dark=true; m.darkAmount=0
        m.vars.rng=c.seed
        local a=m.otherArena
        m.lights={C.light(a.x,a.y-a.h/2-Lighting.outerRadius(c.radius,m.lightStyle),c.radius)}
        m.vars.lightFrom={x=a.x,y=a.y}; m.vars.lightTarget=target(m); m.vars.lightTime=0
    elseif s==4 then
        m.caption={"Nap","Wave03.Nap"}
        chooseSqueezeEdge(m)
        m.vars.knifeTime,m.vars.squeezeTime=0,0
        local lastBorn,lastFinish=0,0
        for ring=1,c.ringCount do
            local radius=c.radius+24+(ring-1)*c.ringGap
            local count=math.floor(5*radius/(c.radius+24)+.5)
            -- One stream feeds each ring through a shared tangent point.  The
            -- default direction matches the reference: lower-left to upper-right.
            local direction=c.alternate and ring%2==0 and 1 or -1
            local entryAngle=math.pi/4+(ring-1)*c.phaseOffset
            local tangent=entryAngle+math.pi/2*direction
            local omega=math.rad(c.orbitSpeed)
            for blade=0,count-1 do
                local l=m.lights[1]
                local k=m:knife(l.x+math.cos(entryAngle)*radius-math.cos(tangent)*W.knifeEntryDistance,
                    l.y+math.sin(entryAngle)*radius-math.sin(tangent)*W.knifeEntryDistance,
                    tangent,.72)
                local spacingTime=(math.pi*2/count)/omega
                k.ring,k.radius,k.baseAngle=ring,radius,entryAngle
                k.direction=direction
                k.entryDuration=W.knifeEntryDistance/(omega*radius)
                k.orbitDuration=math.pi*2/omega
                k.exitDuration=W.knifeExitDistance/(omega*radius)
                k.born=(ring-1)*c.ringDelay+blade*spacingTime
                lastBorn=math.max(lastBorn,k.born)
                lastFinish=math.max(lastFinish,k.born+k.entryDuration+k.orbitDuration+k.exitDuration)
                k.alpha=0
            end
        end
        m.vars.knifeEmissionStop=lastBorn
        m.vars.knifeClearTime=lastFinish
        -- Under normal play the frame reaches its near-final span just after
        -- the last knife clears. Slow mode may make knives take longer, so the
        -- frame holds there instead of coupling its motion to bullet time.
        m.vars.squeezeDuration=lastFinish/W.normalSpeedMultiplier+.2
    elseif s==5 then
        m.vars.dropArenaY=m.otherArena.y
        m.vars.dropLightY=m.lights[1].y
    end
end
function W.lighting(m,dt)
    if m.stage<3 then return end
    local v=m.vars
    if m.stage==3 then
        local a=m.otherArena
        local p=C.ease(m.phaseTime/1.2)
        m.darkAmount=p
        m.lights={C.light(a.x,C.lerp(a.y-a.h/2-Lighting.outerRadius(m.config.radius,m.lightStyle),a.y,p),m.config.radius)}
        return
    end
    if m.stage==5 then
        local p=C.curve("quart",m.phaseTime/W.dropDuration)
        m.darkAmount=1
        m.lights[1].y=m.vars.dropLightY+W.dropDistance*p
        return
    end
    m.darkAmount=1
    v.lightTime=v.lightTime+dt
    if v.lightTime>=m.config.lightWander then
        v.lightTime=v.lightTime-m.config.lightWander
        v.lightFrom=v.lightTarget; v.lightTarget=target(m)
    end
    local p=C.ease(v.lightTime/m.config.lightWander)
    m.lights={C.light(C.lerp(v.lightFrom.x,v.lightTarget.x,p),C.lerp(v.lightFrom.y,v.lightTarget.y,p),m.config.radius)}
end
local updateLighting=W.lighting
function W.lighting(m,dt)
    updateLighting(m,dt)
    for _,light in ipairs(m.lights) do light.fadeRadius=380 end
end
function W.update(m,dt)
    local s,c=m.stage,m.config
    if s==1 then
        if m:dialogueDone() then m.vars.warnStart=m.vars.warnStart or m.phaseTime end
        if m.vars.warnStart and m.phaseTime-m.vars.warnStart>=.45 then
            if math.abs(m.player.x-W.arena.x)<=3 then m:hit(10) end
            m:next()
        end
    elseif s==2 then
        layout(m,m.phaseTime/.5)
        if m.phaseTime>.7 then m:next() end
    elseif s==3 and m.phaseTime>=1.2 then m:next()
    elseif s==4 then
        if m.phaseTime>3 and m:dialogueDone() then m.caption={"Chara","Wave03.Chara"} end
        m.vars.knifeTime=m.vars.knifeTime+dt*(m.slow and c.slowFactor*W.slowMultiplier or W.normalSpeedMultiplier)
        m.vars.squeezeTime=math.min(m.vars.squeezeDuration,m.vars.squeezeTime+dt)
        squeezeArena(m)
        local l=m.lights[1]
        for _,k in ipairs(m.knives) do
            local age=m.vars.knifeTime-k.born
            local direction=k.direction
            local tangent=k.baseAngle+math.pi/2*direction
            if age<0 then
                k.alpha=0; k.active=false
            elseif age<k.entryDuration then
                local p=age/k.entryDuration
                local targetX=l.x+math.cos(k.baseAngle)*k.radius
                local targetY=l.y+math.sin(k.baseAngle)*k.radius
                k.x=targetX-math.cos(tangent)*W.knifeEntryDistance*(1-p)
                k.y=targetY-math.sin(tangent)*W.knifeEntryDistance*(1-p)
                k.angle=tangent
                k.alpha=1; k.active=true
            else
                -- Rotation starts only after this knife reaches its circle.
                local orbitAge=age-k.entryDuration
                if orbitAge<k.orbitDuration then
                    local angle=k.baseAngle+math.rad(c.orbitSpeed)*orbitAge*direction
                    k.x,k.y=l.x+math.cos(angle)*k.radius,l.y+math.sin(angle)*k.radius
                    k.angle=angle+math.pi/2*direction
                    k.alpha=1; k.active=true
                else
                    local exitAge=orbitAge-k.orbitDuration
                    if exitAge<k.exitDuration then
                        local tangent=k.baseAngle+math.pi/2*direction
                        local distance=W.knifeExitDistance*exitAge/k.exitDuration
                        k.x=l.x+math.cos(k.baseAngle)*k.radius+math.cos(tangent)*distance
                        k.y=l.y+math.sin(k.baseAngle)*k.radius+math.sin(tangent)*distance
                        k.angle=tangent
                        k.alpha=1; k.active=true
                    else
                        k.alpha=0; k.active=false
                    end
                end
            end
        end
        if m.vars.knifeTime>m.vars.knifeClearTime and m:dialogueDone() then m:next() end
    elseif s==5 then
        local p=C.curve("quart",m.phaseTime/W.dropDuration)
        m.otherArena.y=m.vars.dropArenaY+W.dropDistance*p
        if m.phaseTime>W.dropDuration then m:next() end
    end
end
return W
]]
