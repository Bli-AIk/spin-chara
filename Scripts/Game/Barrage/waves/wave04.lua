local C=require((...):match("(.-)[^%.]+$").."common")
local Lighting=require((...):match("(.-)waves%.").."lighting")
local Curtain=require((...):match("(.-)waves%.").."curtain-preview")
local W={arena={x=320,y=315,w=280,h=84},minTravel=58,entryDuration=1.2,
    stages={"开场对白","聚光灯滑入","换位一","阴影出刀一","换位二","阴影出刀二",
        "换位三","阴影出刀三","拉上幕布","换位一","光中出刀一","换位二","光中出刀二",
        "换位三","光中出刀三","扯下幕布"}}
local moving={[3]=true,[5]=true,[7]=true,[10]=true,[12]=true,[14]=true}
function W.travelSpeed(distance)
    local t=C.clamp((distance-45)/(184-45))
    return C.lerp(105,135,C.ease(t))
end
local function random(m)
    m.vars.rng=(m.vars.rng*48271)%2147483647
    return (m.vars.rng-1)/2147483646
end
local function randomTarget(m,lo,hi,from)
    local leftLength=math.max(0,math.min(hi,from-W.minTravel)-lo)
    local rightStart=math.max(lo,from+W.minTravel)
    local rightLength=math.max(0,hi-rightStart)
    local total=leftLength+rightLength
    if total<=0 then return math.abs(from-lo)>math.abs(hi-from) and lo or hi end
    local pick=random(m)*total
    if pick<leftLength then return lo+pick end
    return rightStart+(pick-leftLength)
end
-- Once the cloth hides the arena the light hunts the soul: it lands on the
-- player's position at the moment the move begins instead of a random spot, so
-- standing still is what invites it. The same minimum travel still applies --
-- a soul already inside the strip is aimed at from the nearest legal distance
-- and keeps a full-speed escape.
local function aimedTarget(m,lo,hi,from)
    local leftEnd=math.min(hi,from-W.minTravel)
    local rightStart=math.max(lo,from+W.minTravel)
    local leftLength=math.max(0,leftEnd-lo)
    local rightLength=math.max(0,hi-rightStart)
    if leftLength+rightLength<=0 then return math.abs(from-lo)>math.abs(hi-from) and lo or hi end
    local x=math.max(lo,math.min(hi,m.player.x))
    if leftLength>0 and x<=leftEnd then return x end
    if rightLength>0 and x>=rightStart then return x end
    -- Inside the dead ring the travel would be too short: take the nearer side.
    if leftLength<=0 then return rightStart end
    if rightLength<=0 then return leftEnd end
    return x-leftEnd<rightStart-x and leftEnd or rightStart
end
-- Conservative horizontal refuge: before the cloth aim for the light centre;
-- afterwards clear the lit blade strip including blade width and heart margin.
function W.safeTargetAt(m,x)
    if not m.curtain then return x end
    local lo,hi=m.arena.x-m.arena.w/2+8,m.arena.x+m.arena.w/2-8
    local left,right=x-m.config.radius-24,x+m.config.radius+24
    if left<lo then return right end
    if right>hi then return left end
    return math.abs(m.player.x-left)<math.abs(m.player.x-right) and left or right
end
function W.safeTarget(m) return W.safeTargetAt(m,m.lights[1].x) end
local function lights(m,centre)
    local r=m.config.radius
    m.lights={C.light(centre,315,r)}
end
function W.enter(m)
    local s=m.stage
    if s==1 then
        local seed=m.context.randomSeed and m.context.randomSeed()
            or love and love.math and love.math.random(1,2147483646)
            or math.random(1,2147483646)
        m.vars.rng=seed; m.vars.centre=320; lights(m,320)
        m.dark=false; m.darkAmount=0; m.lights={}
        m.caption={"Chara","Wave04.Intro"}
    elseif s==2 then
        m.dark=true; m.darkAmount=0
        W.lighting(m)
    elseif s==9 then
        m.curtain=true
        Curtain.applyAdopted(m)
        Curtain.transition(m,"enter")
        m.caption={"Chara","Wave04.Curtain"}
    elseif s==16 then
        Curtain.transition(m,"exit")
    elseif moving[s] then
        m.vars.from=m.vars.centre
        local a=m.arena
        local lo,hi=a.x-a.w/2+m.config.radius+10,a.x+a.w/2-m.config.radius-10
        local aim=m.curtain and aimedTarget or randomTarget
        local target=aim(m,lo,hi,m.vars.from)
        m.vars.target=target
        local distance=math.abs(target-m.vars.from)
        m.vars.travelSpeed=W.travelSpeed(distance)
        m.vars.duration=distance/m.vars.travelSpeed
    else
        local a=m.arena
        m.vars.safeX=W.safeTarget(m)
        m.vars.spawnDelay=0
        m.vars.shotSpeed=280
        for x=a.x-a.w/2+5,a.x+a.w/2-5,m.config.spacing do
            local inLight=false
            for _,l in ipairs(m.lights) do
                if math.abs(x-l.x)<l.r+12 then inLight=true end
            end
            -- Before the curtain avoid the entire light; afterwards put blades
            -- well inside it so their width cannot leak into the safe shadow.
            local spawn=not m.curtain and not inLight
            if m.curtain then
                for _,l in ipairs(m.lights) do if math.abs(x-l.x)<l.r-12 then spawn=true end end
            end
            if spawn then
                local k=m:knife(x,a.y-a.h/2-30,math.pi/2,.65)
                k.start=k.y; k.alpha=0
            end
        end
    end
end
function W.lighting(m)
    local s=m.stage
    if s==2 then
        local p=C.curve("quart",m.phaseTime/W.entryDuration)
        m.darkAmount=p
        m.lights={C.light(m.arena.x,C.lerp(m.arena.y-m.arena.h/2-Lighting.outerRadius(m.config.radius,m.lightStyle),m.arena.y,p),m.config.radius)}
    elseif moving[s] then
        m.vars.centre=C.lerp(m.vars.from,m.vars.target,C.curve("quart",m.phaseTime/m.vars.duration))
        lights(m,m.vars.centre)
    end
end
function W.update(m)
    local s=m.stage
    if s==1 or s==9 then
        if s==9 and m.caption[2]=="Wave04.Curtain" and m:dialogueDone() then
            m.caption={"Nap","Wave04.Nap"}
        elseif m.phaseTime>(s==9 and Curtain.ENTER_TIME or 0) and m:dialogueDone() then m:next() end
    elseif s==2 then
        if m.phaseTime>=W.entryDuration then m.darkAmount=1; m:next() end
    elseif s==16 then
        if m.phaseTime>1.0 then m.curtain=false; m:next() end
    elseif moving[s] then
        if m.phaseTime>=m.vars.duration then m:next() end
    else
        local waiting=m.phaseTime<m.vars.spawnDelay
        if waiting then m.attackTime=0 end
        local gone=true
        for _,k in ipairs(m.knives) do
            k.active=not waiting
            k.alpha=C.ease((m.phaseTime-m.vars.spawnDelay+.16)/.16)
            k.y=k.start+m.attackTime*m.vars.shotSpeed
            if k.y<m.arena.y+m.arena.h/2+45 then gone=false end
        end
        if gone and not waiting then m:next() end
    end
end
return W
