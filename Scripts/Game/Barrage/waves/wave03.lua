local P=(...):match("(.-)[^%.]+$")
local C=require(P.."common")
local Lighting=require((...):match("(.-)waves%.").."lighting")
local W={arena={x=320,y=315,w=156,h=156},expandedWidth=288,
    outerHeight=38,gap=12,horizontalLaneCount=10,horizontalLaneRadius=54,
    horizontalSplit=true,
    stages={"方框对白","横向密刀","双重横劈","聚光灯入场","追光与纵刺","空框滑落"}}
local function variant(m) return m.config.wave03Prototype end
local function box(top,bottom) return {x=W.arena.x,y=(top+bottom)/2,w=W.expandedWidth,h=bottom-top} end
local function geometry()
    local top,bottom=W.arena.y-W.arena.h/2,W.arena.y+W.arena.h/2
    local upper,lower=top+W.outerHeight+W.gap/2,bottom-W.outerHeight-W.gap/2
    return box(top,upper-W.gap/2),box(upper+W.gap/2,lower-W.gap/2),
        box(lower+W.gap/2,bottom),upper,lower
end
local function bind(m)
    m.arena=m.areas[m.vars.zone]
    local empty={}
    for i,a in ipairs(m.areas) do if i~=m.vars.zone then empty[#empty+1]=a end end
    m.otherArena,m.thirdArena=empty[1],empty[2]
end
local function setAreas(m)
    if not m.areas then local a,b,c=geometry(); m.areas={a,b,c} end
    bind(m)
end
local function offscreenDistance(dx,dy,x,y)
    local vx,vy=-dx,-dy
    local tx=vx>0 and (688-x)/vx or vx<0 and (-48-x)/vx or math.huge
    local ty=vy>0 and (528-y)/vy or vy<0 and (-48-y)/vy or math.huge
    return math.min(tx,ty)
end
local function opening(m,t)
    local v=variant(m)
    if t>=m.vars.burstAt then m.vars.burstStarted=true end
    if m.stage==2 and m.vars.burstStarted then
        m.arena.w=C.lerp(W.arena.w,W.expandedWidth,C.curve("quart",(t-m.vars.burstAt)/v.expand))
    end
    for _,k in ipairs(m.knives) do
        local age=t-k.delay
        local facing=math.atan2(-k.dy,-k.dx)
        local distance
        if age>=m.vars.burstAt then
            local flight=age-m.vars.burstAt
            distance=C.lerp(115,-k.exitDistance,C.ease(flight/v.burst))
            k.angle=facing+4*math.pi; k.active=flight<v.burst; k.visibleInside=true
        elseif age<v.emerge then
            distance=C.lerp(52,115,C.ease(age/v.emerge))
            k.angle=facing+math.pi; k.active=false
        elseif age<v.emerge+v.spin then
            distance=115; k.angle=facing+math.pi+3*math.pi*C.curve("quart",(age-v.emerge)/v.spin)
            k.active=false
        else distance=115; k.angle=facing+4*math.pi; k.active=false end
        k.x,k.y=k.originX+k.dx*distance,k.originY+k.dy*distance
    end
end
local function strike(m,index)
    local cut=index==1 and m.vars.topCut or m.vars.bottomCut
    if math.abs(m.player.y-cut)<10 then m:hit(10) end
    m.vars.slashCount=index
    if index==1 then
        local upper=geometry()
        local remainder=box(upper.y+upper.h/2+W.gap,W.arena.y+W.arena.h/2)
        if m.player.y<cut then m.arena,m.otherArena=upper,remainder
        else m.arena,m.otherArena=remainder,upper end
    else
        local a,b,c=geometry(); m.areas={a,b,c}
        m.vars.zone=m.player.y<m.vars.topCut and 1 or m.player.y>m.vars.bottomCut and 3 or 2
        bind(m)
    end
end
local function attackSign(m,number)
    if m.vars.zone==1 then return -1 end
    if m.vars.zone==3 then return 1 end
    return number%2==1 and 1 or -1
end
local function createFan(m,sign,launchAt,flight)
    local top,bottom=W.arena.y-W.arena.h/2,W.arena.y+W.arena.h/2
    local start=sign>0 and top-32 or bottom+32
    local a=m.arena
    -- Use the farthest reachable edge, so retreating vertically cannot buy
    -- more time than the tutorial's stated deadline.
    local far=a.y+sign*(a.h/2-8)
    local speed=math.abs(far-(start+sign*30))/flight
    local fan={launchAt=launchAt,age=0,sign=sign,speed=speed,flight=flight,knives={}}
    local span=W.expandedWidth-8
    local intervals=math.ceil(span/m.config.spacing)
    for i=0,intervals do
        local x=W.arena.x-span/2+i*span/intervals
        local k=m:knife(x,start,sign*math.pi/2,1)
        k.startY,k.stopY,k.launchAt=start,(sign>0 and bottom or top)-sign*30,launchAt
        k.alpha=0; k.active=false
        fan.knives[#fan.knives+1]=k
    end
    m.vars.fans[#m.vars.fans+1]=fan
end
local function beginBeat(m,number)
    local v=variant(m)
    local light=m.lights[1]
    m.knives={}; m.vars.fans={}
    m.vars.beat,m.vars.beatTime=number,0
    m.vars.fromX=light.x
    local range=W.expandedWidth/2-m.config.radius-10
    local direction
    if v.kind=="tutorial" or number==1 then direction=m.player.x>=W.arena.x and -1 or 1
    else direction=-(m.vars.targetDirection or 1) end
    m.vars.targetDirection=direction
    m.vars.targetX=W.arena.x+direction*range
    m.vars.previousLight={x=light.x,y=light.y}
    m.vars.beatStartX=m.player.x
    m.vars.xUsed=false
    local flight
    if v.kind=="tutorial" then
        -- The last deadline is shorter than a full-speed soul needs to reach
        -- even the generous outer bound of the protected column. X buys time
        -- through real blade travel, never through an input-based damage check.
        local core=m.config.radius*34/38
        local distance=math.abs(m.vars.targetX-m.player.x)
        local reach=math.max(24,distance-core-8)
        local deadline=reach/125*v.lessonFactors[number]
        if number==1 and v.beats>1 then deadline=math.max(3.5,deadline) end
        flight=math.max(.18,deadline-v.launchAt)
        m.vars.normalDeadline=v.launchAt+flight
    else
        flight=v.flights[number]
        -- The middle strip receives opposite directions in the double beat;
        -- allow reaching the core before the second attack closes behind it.
        if v.kind=="double" and m.vars.zone==2 then flight=flight*1.16 end
    end
    local first=v.kind=="double" and (number-1)*2+1 or number
    createFan(m,attackSign(m,first),v.launchAt,flight)
    if v.kind=="double" then
        createFan(m,attackSign(m,first+1),v.launchAt+v.secondDelay,flight/v.secondSpeed)
    end
    m.vars.direction=m.vars.fans[1].sign
end
-- Exact segment/circle entry for the tip relative to the moving spotlight.
-- Once a blade is intercepted it remains stopped; a later light position
-- cannot pull an already-passed blade backwards or recreate lost shelter.
local function intercept(k,nextY,previous,light,core,sign)
    local x,y=k.x-previous.x,k.y+sign*30-previous.y
    local dx,dy=previous.x-light.x,nextY-k.y+previous.y-light.y
    local c=x*x+y*y-core*core
    if c<=0 then return 0 end
    local a=dx*dx+dy*dy
    if a<1e-12 then return nil end
    local b=2*(x*dx+y*dy)
    local discriminant=b*b-4*a*c
    if discriminant<0 then return nil end
    local t=(-b-math.sqrt(discriminant))/(2*a)
    if t>=0 and t<=1 then return t end
end
local function updateFans(m,dt,bulletDt)
    local v,light=variant(m),m.lights[1]
    local previous=m.vars.previousLight
    local allDone=true
    for _,fan in ipairs(m.vars.fans) do
        local activeDt=math.min(dt,math.max(0,m.vars.beatTime-fan.launchAt))
        if activeDt>0 then fan.age=fan.age+bulletDt*activeDt/dt end
        local finished=true
        for _,k in ipairs(fan.knives) do
            if k.gone then k.active=false
            elseif activeDt==0 then
                k.alpha=C.ease(m.vars.beatTime/math.max(.01,fan.launchAt))*.65
                k.active=false; finished=false
            elseif not k.arrivedAt then
                local nextY=k.y+fan.sign*fan.speed*bulletDt*activeDt/dt
                local reached=fan.sign*(nextY-k.stopY)>=0
                if reached then nextY=k.stopY end
                local portion=activeDt/dt
                local startLight={x=C.lerp(previous.x,light.x,1-portion),y=light.y}
                local contact=intercept(k,nextY,startLight,light,m.config.radius*34/38,fan.sign)
                if contact then
                    nextY=C.lerp(k.y,nextY,contact); k.blocked=true; reached=true
                end
                k.y=nextY; k.alpha=1; k.active=true
                if reached then k.arrivedAt=fan.age; k.heldY=k.y end
                finished=false
            else
                local t=fan.age-k.arrivedAt
                if t<v.hold then k.y=k.heldY; k.active=true
                else
                    local p=C.ease((t-v.hold)/v.retract)
                    k.y=C.lerp(k.heldY,k.startY,p); k.alpha=1-p; k.active=p<.8
                    if p>=1 then k.gone=true; k.active=false end
                end
                if not k.gone then finished=false end
            end
        end
        fan.done=finished
        if not finished then allDone=false end
    end
    m.vars.previousLight={x=light.x,y=light.y}
    return allDone
end
function W.enter(m)
    local s,v=m.stage,variant(m)
    if s==1 then
        m.arena={x=W.arena.x,y=W.arena.y,w=W.arena.w,h=W.arena.h}
        m.areas,m.otherArena,m.thirdArena=nil,nil,nil
        m.lights={}; m.dark=false; m.darkAmount=0
        m.caption={"Chara","Wave03.Intro"}
    elseif s==2 then
        m.vars.burstAt=v.emerge+v.spin+v.pause
        m.vars.burstStarted=false
        local function blade(dx,dy,laneX,laneY,delay)
            local x,y=W.arena.x+laneX,W.arena.y+laneY
            local k=m:knife(x+dx*52,y+dy*52,math.atan2(dy,dx),1)
            k.originX,k.originY,k.dx,k.dy=x,y,dx,dy
            k.delay=delay or 0; k.exitDistance=offscreenDistance(dx,dy,x,y)
            k.backdrop=true; k.visibleInside=false; k.alpha=1
        end
        -- Rotate the dense vertical opening into horizontal rows. The paired
        -- vertical blades keep the sparse second axis of the original cross.
        local offsets=m.config.verticalXOffsets or {-28,28}
        blade(0,-1,offsets[1],0,0); blade(0,1,offsets[2],0,0)
        -- Keep the central six rows; the two outer rows on each side were
        -- only edge clutter and made the opening read too dense vertically.
        for i=2,W.horizontalLaneCount-3 do
            local y=-W.horizontalLaneRadius+2*W.horizontalLaneRadius*i/(W.horizontalLaneCount-1)
            local delay=(math.abs(y)-6)/48*v.edgeDelay
            blade(-1,0,0,y,delay); blade(1,0,0,y,delay)
        end
        m.vars.openingBlades=m.knives
    elseif s==3 then
        m.knives=m.vars.openingBlades
        m.arena={x=W.arena.x,y=W.arena.y,w=W.expandedWidth,h=W.arena.h}
        m.otherArena,m.thirdArena=nil,nil
        local a,b,c,upper,lower=geometry()
        m.vars.topCut,m.vars.bottomCut,m.vars.slashCount=upper,lower,0
    elseif s==4 then
        m.vars.openingBlades=nil
        setAreas(m)
        local a=m.areas[2]
        m.dark=true; m.darkAmount=0
        m.vars.lightStartY=a.y-a.h/2-Lighting.outerRadius(m.config.radius,m.lightStyle)
        m.lights={C.light(a.x,m.vars.lightStartY,m.config.radius)}
    elseif s==5 then
        setAreas(m)
        m.vars.completedBeats=0; m.vars.lessonUsed=0
        m.vars.restTime=0
        beginBeat(m,1)
    elseif s==6 then
        m.knives={}; m.vars.falling={}
        for i,a in ipairs(m.areas) do
            if i~=m.vars.zone then
                m.vars.falling[#m.vars.falling+1]={area=a,x=a.x,y=a.y,sign=i==1 and -1 or 1}
            end
        end
        local a=m.areas[2]
        m.vars.dropLightOffset={x=m.lights[1].x-a.x,y=m.lights[1].y-a.y}
    end
end
function W.lighting(m,dt)
    local s,v=m.stage,variant(m)
    if s==4 then
        local p=C.ease(m.phaseTime/v.lightEntry)
        local a=m.areas[2]
        m.darkAmount=p
        m.lights={C.light(a.x,C.lerp(m.vars.lightStartY,a.y,p),m.config.radius)}
    elseif s==5 then
        m.vars.beatTime=m.vars.beatTime+dt
        local p=C.curve("quart",m.vars.beatTime/v.moveTime)
        m.lights={C.light(C.lerp(m.vars.fromX,m.vars.targetX,p),m.areas[2].y,m.config.radius)}
        m.darkAmount=1
    elseif s==6 and m.vars.zone~=2 then
        local a=m.areas[2]
        m.lights[1].x=a.x+m.vars.dropLightOffset.x
        m.lights[1].y=a.y+m.vars.dropLightOffset.y
    end
    for _,l in ipairs(m.lights) do l.fadeRadius=380 end
end
function W.update(m,dt,bulletDt)
    local s,v=m.stage,variant(m)
    if s==1 then
        if m.phaseTime>=.4 and m:dialogueDone() then m:next() end
    elseif s==2 then
        opening(m,m.phaseTime)
        if m.phaseTime>=m.vars.burstAt+v.slashAt then
            m.vars.openingTimeline=m.phaseTime; m:next()
        end
    elseif s==3 then
        opening(m,m.vars.openingTimeline+m.phaseTime)
        if m.vars.slashCount==0 and m.phaseTime>=v.firstCut then strike(m,1) end
        if m.vars.slashCount==1 and m.phaseTime>=v.firstCut+v.cutGap then strike(m,2) end
        if m.vars.openingTimeline+m.phaseTime>=m.vars.burstAt+v.burst+v.edgeDelay
            and m.phaseTime>=v.firstCut+v.cutGap+v.cutSettle then m:next() end
    elseif s==4 then
        if m.phaseTime>=v.lightEntry then m:next() end
    elseif s==5 then
        if m.slow then m.vars.xUsed=true end
        if updateFans(m,dt,bulletDt or dt) then
            m.vars.restTime=(m.vars.restTime or 0)+dt
            if m.vars.restTime>=.24 then
                m.vars.restTime=0
                m.vars.completedBeats=m.vars.beat
                if m.vars.xUsed then m.vars.lessonUsed=m.vars.lessonUsed+1 end
                if m.vars.beat<v.beats then beginBeat(m,m.vars.beat+1) else m:next() end
            end
        end
    elseif s==6 then
        local progress=C.clamp((m.phaseTime-.7)/(1.9/math.sqrt(1.7)))
        for _,f in ipairs(m.vars.falling) do
            f.area.x=f.x+f.sign*14*progress^2
            f.area.y=f.y+330*progress^2
            f.area.rotation=f.sign*math.rad(6)*progress^2
        end
        if progress>=1 then m:next() end
    end
end
-- Prototype shortcut: review each locked strip without replaying the opener.
function W.previewZone(m,zone)
    m.done=false; m.elapsed=0
    m.hits,m.player.hp,m.player.hurt=0,20,0
    m.vars={zone=zone}; m.areas=nil; setAreas(m)
    m.player.x,m.player.y=m.arena.x,m.arena.y
    m:enter(4)
end
return W
