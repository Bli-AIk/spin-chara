local C=require((...):match("(.-)[^%.]+$").."common")
local Lighting=require((...):match("(.-)waves%.").."lighting")
-- Five repositioning moves. The core shrinks evenly across them and ends at
-- half the radius the three-move schedule's last move used to leave.
local FIRST_MOVE,MOVES=3,5
local LAST_MOVE,CLOSING=FIRST_MOVE+MOVES-1,FIRST_MOVE+MOVES
local LAST_SCALE=.58/2
-- The engine's own defense box, kept as it is: the barrage starts with the box
-- already on screen, so nothing about it moves and the whole opening beat goes
-- to the spotlight. Easing onto a box of nearly the same size only read as a
-- twitch.
local W={arena={x=320,y=315,w=155,h=130},reusesIncomingBox=true,entryDuration=1.5,
    stages={"对白","关灯与聚光灯入场","第一次换位","第二次换位","第三次换位",
        "第四次换位","第五次换位","收束"}}
local function randomTarget(a,from,radius)
    local margin=radius+6
    local best,bestDistance
    for _=1,32 do
        local t={x=a.x+(love.math.random()*2-1)*(a.w/2-margin),
            y=a.y+(love.math.random()*2-1)*(a.h/2-margin)}
        local distance=(t.x-from.x)^2+(t.y-from.y)^2
        if not bestDistance or distance>bestDistance then best,bestDistance=t,distance end
        if distance>=42^2 then return t end
    end
    return best
end
function W.enter(m)
    local s,c=m.stage,m.config
    m.dark=s>1
    m.darkAmount=s<=2 and 0 or 1
    if s==2 then m.lights={} end
    if s==1 then m.lights={} end
    local l=m.lights[1] or C.light(W.arena.x,W.arena.y,c.radius)
    m.vars.from={x=l.x,y=l.y,r=l.r}
    local attacking=s>=FIRST_MOVE and s<=LAST_MOVE
    local radius=attacking and c.radius*(1-(1-LAST_SCALE)*(s-FIRST_MOVE+1)/MOVES) or l.r
    m.vars.target=attacking and randomTarget(m.arena,m.vars.from,radius) or {x=l.x,y=l.y}
    m.vars.target.r=radius
    m.vars.duration=attacking and c.wave02Light or .4
    m.caption=s==1 and {"Chara","Wave02.Intro"} or nil
    if attacking then
        m.vars.launched=false
        local dx,dy=m.vars.target.x-l.x,m.vars.target.y-l.y
        local horizontal=math.abs(dx)>=math.abs(dy)
        local sign=(horizontal and dx or dy)>0 and 1 or -1
        local a=m.arena
        local tip=30*.78
        local start=horizontal and a.x-sign*(a.w/2+tip+1) or a.y-sign*(a.h/2+tip+1)
        -- Lay the fan out about the middle of the box instead of stacking it
        -- from one edge: a blade then sits on the centre line whenever the
        -- count is odd, and both ends keep the same clearance.
        local centre=horizontal and a.y or a.x
        local span=(horizontal and a.h or a.w)-20
        local count=math.floor(span/c.spacing)+1
        local first=centre-(count-1)*c.spacing/2
        for i=0,count-1 do
            local v=first+i*c.spacing
            local k=m:knife(horizontal and start or v,horizontal and v or start,
                horizontal and (sign<0 and math.pi or 0) or sign*math.pi/2,.78)
            k.start,k.stop,k.sign,k.axis=start,start,sign,horizontal and "x" or "y"
            k.perpendicular=v
            local distanceFromCentre=math.abs(v-centre)/c.spacing
            if c.wave02Pattern=="centre" then
                k.delay=distanceFromCentre*c.wave02Stagger
            elseif c.wave02Pattern=="alternate" then
                k.delay=math.floor(distanceFromCentre+.5)%2*c.wave02Stagger
            else
                k.delay=0
            end
        end
    end
end
function W.lighting(m)
    if m.stage==1 then m.lights={}; return end
    if m.stage==2 then
        local opening=C.curve("quart",m.phaseTime/W.entryDuration)
        m.darkAmount=opening
        -- From one halo radius above the box's top edge down to the light's
        -- resting place in the middle of the box.
        local top=m.arena.y-m.arena.h/2
        local light=C.light(320,C.lerp(top-Lighting.outerRadius(m.config.radius,m.lightStyle),m.arena.y,opening),m.config.radius)
        m.lights={light}
        return
    end
    local f,t=m.vars.from,m.vars.target
    local p=C.curve("quart",m.phaseTime/m.vars.duration)
    m.lights={C.light(C.lerp(f.x,t.x,p),C.lerp(f.y,t.y,p),C.lerp(f.r,t.r,p))}
end
function W.update(m)
    local s,c=m.stage,m.config
    if s==1 then
        -- The dialogue is the beat. The battle freezes this model for the whole
        -- line, so a beat counted from phaseTime is served after it and reads
        -- as a late spotlight: the entrance has to start on the first update
        -- after the line closes.
        if m:dialogueDone() then m:next() end
        return
    end
    if s==2 then
        if m.phaseTime>W.entryDuration+.05 then m:next() end
        return
    end
    if #m.knives==0 then
        if m.phaseTime>m.vars.duration+(s==CLOSING and .10 or .35) then m:next() end
        return
    end
    local finished=true
    for _,k in ipairs(m.knives) do
        -- Clock-driven: neither player arrival nor light arrival gates launch.
        -- Preparation begins with the light; the thrust overlaps its arrival.
        local attackStart=math.max(.12,m.vars.duration-c.wave02Thrust*.75)+k.delay
        local t=m.phaseTime-attackStart
        local thrust=c.wave02Thrust
        local exit=thrust+c.wave02Hold
        k.alpha=C.ease(m.phaseTime/.12)
        -- The fan leaves on its first blade; the staggered ripple behind it is
        -- the same beat, not a second launch.
        if t>=0 and not m.vars.launched then
            m.vars.launched=true
            m:launch()
        end
        if t<0 then
            local anticipation=C.ease(m.phaseTime/attackStart)
            k[k.axis]=k.start-k.sign*6*anticipation
            k.active=false
        elseif t<thrust then
            local light=m.lights[1]
            -- Blades ring the light on the white core's circle, and that circle
            -- is never tighter than one blade: once the core shrinks below the
            -- blade's own reach no knife crosses it any more, so the whole fan
            -- would thrust past the light to the far edge instead of going
            -- around it.
            local core=math.max(light.r*34/38,30*k.scale)
            local perpendicularLight=k.axis=="x" and light.y or light.x
            local delta=math.abs(k.perpendicular-perpendicularLight)
            local desired
            if delta<core then
                local boundary=math.sqrt(core*core-delta*delta)
                desired=(k.axis=="x" and light.x or light.y)-k.sign*(boundary+30*k.scale)
            else
                local a=m.arena
                local centre=k.axis=="x" and a.x or a.y
                local span=k.axis=="x" and a.w or a.h
                -- Align the leading tip just inside the opposite inner edge.
                desired=centre+k.sign*(span/2-1-30*k.scale)
            end
            k.stop=desired
            k[k.axis]=C.lerp(k.start,desired,C.curve(c.wave02Curve,t/thrust))
            k.active=true
        elseif t<exit then
            k[k.axis]=k.stop; k.active=true
        else
            local p=C.ease((t-exit)/.45)
            k[k.axis]=C.lerp(k.stop,k.start,p); k.alpha=1-p; k.active=p<.8
        end
        if t<exit+.45 then finished=false end
    end
    if finished then m:next() end
end
return W
