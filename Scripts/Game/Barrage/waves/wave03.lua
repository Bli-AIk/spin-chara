local P=(...):match("(.-)[^%.]+$")
local C=require(P.."common")
local Lighting=require((...):match("(.-)waves%.").."lighting")

local W={
    arena={x=320,y=315,w=156,h=156},
    -- The engine draws a 5px border outside each piece; 18px leaves an 8px
    -- visible gutter between adjacent frames after both borders are drawn.
    expandedWidth=288,sideWidth=64,gap=18,
    verticalLaneCount=10,verticalLaneRadius=70,
    stages={"方框对白","十字刀阵","双重竖劈","聚光灯入场","环刃与摆框","空框滑落"},
}
local TAU=2*math.pi
local DROP_HOLD=0.7
local DROP_DURATION=1.9/math.sqrt(1.7)
local function variant(m) return m.config.wave03Prototype or {} end
local function box(left,right,y,h) return {x=(left+right)/2,y=y,w=right-left,h=h} end

local function bind(m)
    if not m.areas then return end
    local zone=m.vars.zone
    m.arena=m.areas[zone]
    local empty={}
    for i=1,3 do if i~=zone then empty[#empty+1]=m.areas[i] end end
    m.otherArena,m.thirdArena=empty[1],empty[2]
end

local function frameGeometry(m,offset)
    local centre=W.arena.x
    local outerL,outerR=centre-W.expandedWidth/2,centre+W.expandedWidth/2
    local cutL=outerL+W.sideWidth+W.gap/2+offset
    local cutR=outerR-W.sideWidth-W.gap/2+offset
    local y,h=W.arena.y,W.arena.h
    return box(outerL,cutL-W.gap/2,y,h),
        box(cutL+W.gap/2,cutR-W.gap/2,y,h),
        box(cutR+W.gap/2,outerR,y,h),cutL,cutR
end

local function selectZone(m,areas)
    local x=m.player.x
    if x<areas[1].x+areas[1].w/2+W.gap/2 then return 1 end
    if x>areas[3].x-areas[3].w/2-W.gap/2 then return 3 end
    return 2
end

local function setAreas(m,offset)
    local l,c,r=frameGeometry(m,offset)
    if m.areas then
        for i,new in ipairs({l,c,r}) do
            local old=m.areas[i]
            old.x,old.y,old.w,old.h=new.x,new.y,new.w,new.h
        end
    else m.areas={l,c,r} end
    bind(m)
end

local function offscreenDistance(dx,dy,laneX)
    -- Clear the entire 60px sprite beyond whichever screen edge the blade
    -- reaches first.
    local margin=48
    local vx,vy=-dx,-dy
    local originX=W.arena.x+(laneX or 0)
    local tx=vx>1e-8 and (640+margin-originX)/vx
        or vx< -1e-8 and (-margin-originX)/vx or math.huge
    local ty=vy>1e-8 and (480+margin-W.arena.y)/vy
        or vy< -1e-8 and (-margin-W.arena.y)/vy or math.huge
    return math.min(tx,ty)
end

local function openingBlades(m,t)
    local v=variant(m)
    local spin=v.spin or .38
    local burstAt,duration=m.vars.burstAt,m.vars.burstDuration
    if t>=burstAt then m.vars.burstStarted=true end
    if m.vars.burstStarted and m.stage==2 then
        local p=C.curve("quart",(t-burstAt)/(v.expand or .27))
        m.arena.w=C.lerp(W.arena.w,W.expandedWidth,p)
    end
    for _,k in ipairs(m.knives) do
        local emerge=k.emergeDuration or v.emerge or .36
        local prepareTime=t-(k.appearDelay or k.launchDelay or 0)
        local launchTime=t-(k.launchDelay or 0)
        local dx,dy=k.dx,k.dy
        local facing=math.atan2(-dy,-dx)
        local originX=W.arena.x+(k.laneX or 0)
        local originY=W.arena.y+(k.laneY or 0)
        if launchTime>=burstAt then
            local age=launchTime-burstAt
            local p=C.ease(age/duration)
            local distance=C.lerp(115,-k.exitDistance,p)
            k.x,k.y=originX+dx*distance,originY+dy*distance
            k.angle=facing+4*math.pi
            k.active=age<duration
            k.visibleInside=true
        elseif prepareTime<emerge then
            local distance=C.lerp(52,115,C.ease(prepareTime/emerge))
            k.x,k.y=originX+dx*distance,originY+dy*distance
            k.angle=facing+math.pi; k.active=false
        elseif prepareTime<emerge+spin then
            local p=C.curve("quart",(prepareTime-emerge)/spin)
            k.x,k.y=originX+dx*115,originY+dy*115
            k.angle=facing+math.pi+3*math.pi*p; k.active=false
        else
            k.x,k.y=originX+dx*115,originY+dy*115
            k.angle=facing+4*math.pi; k.active=false
        end
    end
end

local function strike(m,index)
    local cut=index==1 and m.vars.leftCut or m.vars.rightCut
    if math.abs(m.player.x-cut)<10 then m:hit(10) end
    m.vars.slashCount=index
    if index==1 then
        local left=frameGeometry(m,0)
        local outerR=W.arena.x+W.expandedWidth/2
        local remainder=box(left.x+left.w/2+W.gap,outerR,W.arena.y,W.arena.h)
        if m.player.x<cut then m.arena,m.otherArena=left,remainder
        else m.arena,m.otherArena=remainder,left end
    else
        local l,c,r=frameGeometry(m,0)
        m.areas={l,c,r}
        m.vars.zone=selectZone(m,m.areas)
        setAreas(m,0)
    end
end

local function createRings(m)
    local v,c=variant(m),m.config
    local light=m.lights[1]
    local omega=math.rad(c.orbitSpeed*(v.ringSpeed or 1))
    local latest=0
    m.knives={}
    for ring=1,c.ringCount do
        local radius=c.radius+24+(ring-1)*c.ringGap
        local count=math.floor(5*radius/(c.radius+24)+.5)
        local sign=c.alternate and ring%2==0 and 1 or -1
        if v.reverseRings and ring%2==0 then sign=-sign end
        local entryAngle=math.pi/4+(ring-1)*c.phaseOffset
        local tangent=entryAngle+sign*math.pi/2
        local entryDistance=math.max(190,radius+90)
        local entryDuration=entryDistance/(omega*radius)
        local orbitDuration=TAU/omega
        local exitDistance=580
        local exitDuration=exitDistance/(omega*radius)
        for blade=0,count-1 do
            local k=m:knife(light.x+math.cos(entryAngle)*radius-math.cos(tangent)*entryDistance,
                light.y+math.sin(entryAngle)*radius-math.sin(tangent)*entryDistance,tangent,1)
            k.ring,k.radius,k.baseAngle=ring,radius,entryAngle
            k.sign,k.omega,k.tangent=sign,omega,tangent
            k.entryDistance,k.entryDuration=entryDistance,entryDuration
            k.orbitDuration,k.exitDistance,k.exitDuration=orbitDuration,exitDistance,exitDuration
            local jitter=0
            if v.ringJitter then jitter=((ring*17+blade*11)%7-3)*v.ringJitter end
            k.born=(ring-1)*c.ringDelay*(v.ringDelay or 1)+blade*TAU/(count*omega)+jitter
            k.alpha=0
            latest=math.max(latest,k.born+entryDuration+orbitDuration+exitDuration)
        end
    end
    m.vars.knifeTime=0
    m.vars.knifeClearTime=latest
    m.vars.ringTotal=#m.knives
end

function W.enter(m)
    local s,v=m.stage,variant(m)
    if s==1 then
        m.arena={x=W.arena.x,y=W.arena.y,w=W.arena.w,h=W.arena.h}
        m.otherArena,m.thirdArena,m.areas=nil,nil,nil
        m.lights={}; m.dark=false; m.darkAmount=0
        m.caption={"Chara","Wave03.Intro"}
    elseif s==2 then
        m.vars.burstStarted=false
        m.vars.burstAt=(v.emerge or .42)+(v.spin or .38)+(v.pause or .22)
        m.vars.burstDuration=v.burst or .52
        local function blade(dx,dy,laneX,delay,scale,laneY,appearDelay,emergeDuration)
            laneX=laneX or 0
            laneY=laneY or 0
            local k=m:knife(W.arena.x+laneX+dx*52,W.arena.y+laneY+dy*52,
                math.atan2(dy,dx),1)
            k.dx,k.dy=dx,dy
            k.laneX,k.laneY,k.launchDelay=laneX,laneY,delay or 0
            k.appearDelay,k.emergeDuration=appearDelay,emergeDuration
            k.exitDistance=offscreenDistance(dx,dy,laneX)
            k.alpha=1; k.active=false; k.backdrop=true; k.visibleInside=false
        end
        local horizontalY=m.config.horizontalYOffsets or {0,0}
        local appear=v.horizontalAppearDelay or .24
        local quick=v.horizontalEmerge or .16
        blade(-1,0,0,0,1,horizontalY[1],appear,quick)
        blade(1,0,0,v.pairDelay or 0,1,horizontalY[2],appear,quick)
        -- Keep the original lane spacing, omitting both outermost lanes.
        local count,radius=W.verticalLaneCount,W.verticalLaneRadius
        local inner=radius/(count-1)
        for i=1,count-2 do
            local lane=-radius+2*radius*i/(count-1)
            local delay=(math.abs(lane)-inner)/(radius-inner)*(v.edgeDelay or .20)
            blade(0,-1,lane,delay,1)
            blade(0,1,lane,delay,1)
        end
        m.vars.openingBlades=m.knives
    elseif s==3 then
        m.knives=m.vars.openingBlades
        m.arena={x=W.arena.x,y=W.arena.y,w=W.expandedWidth,h=W.arena.h}
        m.otherArena,m.thirdArena=nil,nil
        m.vars.slashCount=0
        m.vars.leftCut=W.arena.x-W.expandedWidth/2+W.sideWidth+W.gap/2
        m.vars.rightCut=W.arena.x+W.expandedWidth/2-W.sideWidth-W.gap/2
    elseif s==4 then
        m.vars.openingBlades=nil
        setAreas(m,0)
        local centre=m.areas[2]
        m.dark=true; m.darkAmount=0
        m.vars.lightStartY=centre.y-centre.h/2-Lighting.outerRadius(m.config.radius,m.lightStyle)
        m.vars.lightTargetY=centre.y-(v.lightRadiusY or 20)
        m.lights={C.light(centre.x,m.vars.lightStartY,m.config.radius)}
    elseif s==5 then
        setAreas(m,0)
        m.caption={"Nap","Wave03.Nap","intermediate"}
        m.vars.lightAngle=-math.pi/2
        createRings(m)
    elseif s==6 then
        m.knives={}
        m.vars.falling={}
        local centre=m.areas[2]
        m.vars.dropLightOffset={
            x=m.lights[1].x-centre.x,y=m.lights[1].y-centre.y,
        }
        for i,area in ipairs(m.areas) do
            if i~=m.vars.zone then
                m.vars.falling[#m.vars.falling+1]={area=area,x=area.x,y=area.y,
                    sign=i==1 and -1 or i==3 and 1 or (m.vars.zone==1 and 1 or -1)}
            end
        end
    end
end

function W.lighting(m,dt)
    local s,v=m.stage,variant(m)
    if s==4 then
        local duration=v.lightEntry or 1.2
        local p=C.ease(m.phaseTime/duration)
        local centre=m.areas[2]
        m.darkAmount=p
        m.lights={C.light(centre.x,C.lerp(m.vars.lightStartY,m.vars.lightTargetY,p),m.config.radius)}
    elseif s==5 then
        local ramp=C.clamp(m.phaseTime/(v.swayRamp or .65))
        local envelope=ramp*ramp*ramp*(ramp*(ramp*6-15)+10)
        local offset=math.sin(TAU*m.phaseTime/(v.swayPeriod or 2.2))
            *(v.swayAmplitude or 16)*envelope
        setAreas(m,offset)
        local centre=m.areas[2]
        local speed=TAU/(v.orbitPeriod or 3.8)
        m.vars.lightAngle=m.vars.lightAngle+dt*speed*(v.orbitDirection or 1)
        local angle=m.vars.lightAngle
        local rx,ry=v.lightRadiusX or 26,v.lightRadiusY or 20
        m.lights={C.light(centre.x+math.cos(angle)*rx,
            centre.y+math.sin(angle)*ry,m.config.radius)}
        m.darkAmount=1
    elseif s==6 then
        local light=m.lights[1]
        local centre=m.areas[2]
        if m.vars.zone~=2 then
            light.x=centre.x+m.vars.dropLightOffset.x
            light.y=centre.y+m.vars.dropLightOffset.y
        end
    end
    for _,light in ipairs(m.lights) do light.fadeRadius=380 end
end

function W.update(m,dt)
    local s,v=m.stage,variant(m)
    if s==1 then
        if m:dialogueDone() then m:next() end
    elseif s==2 then
        openingBlades(m,m.phaseTime)
        if m.phaseTime>=m.vars.burstAt+(v.slashAt or .27) then
            m.vars.openingTimeline=m.phaseTime
            m:next()
        end
    elseif s==3 then
        openingBlades(m,m.vars.openingTimeline+m.phaseTime)
        local first=v.firstCut or .16
        local second=first+(v.cutGap or .12)
        if m.vars.slashCount==0 and m.phaseTime>=first then strike(m,1) end
        if m.vars.slashCount==1 and m.phaseTime>=second then strike(m,2) end
        local flightDone=m.vars.openingTimeline+m.phaseTime
            >=m.vars.burstAt+m.vars.burstDuration
                +math.max(v.edgeDelay or .20,v.pairDelay or 0)
        if flightDone and m.phaseTime>=second+(v.cutSettle or .28) then m:next() end
    elseif s==4 then
        if m.phaseTime>=(v.lightEntry or 1.2) then m:next() end
    elseif s==5 then
        if m.phaseTime>3 and m:dialogueDone() then
            m.caption={"Chara","Wave03.Chara","intermediate"}
        end
        local rate=m.slow and m.config.slowFactor*2 or 2
        m.vars.knifeTime=m.vars.knifeTime+dt*rate
        local light=m.lights[1]
        for _,k in ipairs(m.knives) do
            local age=m.vars.knifeTime-k.born
            if age<0 then
                k.active=false; k.alpha=0
            elseif age<k.entryDuration then
                local remaining=k.entryDistance*(1-age/k.entryDuration)
                k.x=light.x+math.cos(k.baseAngle)*k.radius-math.cos(k.tangent)*remaining
                k.y=light.y+math.sin(k.baseAngle)*k.radius-math.sin(k.tangent)*remaining
                k.angle=k.tangent; k.active=true; k.alpha=1
            elseif age<k.entryDuration+k.orbitDuration then
                local angle=k.baseAngle+k.sign*k.omega*(age-k.entryDuration)
                k.x,k.y=light.x+math.cos(angle)*k.radius,light.y+math.sin(angle)*k.radius
                k.angle=angle+k.sign*math.pi/2
                k.active=true; k.alpha=1
            elseif age<k.entryDuration+k.orbitDuration+k.exitDuration then
                local d=k.exitDistance*(age-k.entryDuration-k.orbitDuration)/k.exitDuration
                k.x=light.x+math.cos(k.baseAngle)*k.radius+math.cos(k.tangent)*d
                k.y=light.y+math.sin(k.baseAngle)*k.radius+math.sin(k.tangent)*d
                k.angle=k.tangent; k.active=true; k.alpha=1
            else k.active=false; k.alpha=0 end
        end
        if m.vars.knifeTime>m.vars.knifeClearTime and m:dialogueDone() then m:next() end
    elseif s==6 then
        local progress=C.clamp((m.phaseTime-DROP_HOLD)/DROP_DURATION)
        local descent=progress*progress
        for _,f in ipairs(m.vars.falling) do
            f.area.x=f.x+f.sign*10*descent
            f.area.y=f.y+300*descent
            f.area.rotation=f.sign*math.rad(6)*descent
        end
        if m.phaseTime>DROP_HOLD+DROP_DURATION then m:next() end
    end
end

return W
