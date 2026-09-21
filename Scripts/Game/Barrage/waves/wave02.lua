local C=require((...):match("(.-)[^%.]+$").."common")
local W={arena={x=320,y=290,w=180,h=156},entryDuration=1.5,
    stages={"对白","关灯与聚光灯入场","向左","向右","回中","佯动","反向"}}
function W.enter(m)
    local s,c=m.stage,m.config
    m.dark=s>1
    m.darkAmount=s<=2 and 0 or 1
    if s==2 then m.lights={} end
    if s==1 then m.lights={} end
    local l=m.lights[1] or C.light(W.arena.x,W.arena.y,c.radius)
    m.vars.from={x=l.x,y=l.y}
    local targets={{320,290},{320,290},{278,290},{362,290},{320,290},{320,270},{320,328}}
    local t=targets[s]
    m.vars.target={x=t[1],y=t[2]}
    m.vars.duration=(s==3 or s==4 or s==7) and c.wave02Light or s==6 and .55 or 1.4
    m.caption=s==1 and {"Chara","Wave02.Intro"} or nil
    if s==3 or s==4 or s==7 then
        local horizontal=s~=7
        local sign=s==3 and -1 or 1
        local a=m.arena
        local tip=30*.78
        local start=horizontal and a.x-sign*(a.w/2+tip+1) or a.y-a.h/2-tip-1
        local lo=horizontal and a.y-a.h/2+10 or a.x-a.w/2+10
        local hi=horizontal and a.y+a.h/2-10 or a.x+a.w/2-10
        for v=lo,hi,c.spacing do
            local k=m:knife(horizontal and start or v,horizontal and v or start,
                horizontal and (sign<0 and math.pi or 0) or math.pi/2,.78)
            k.start,k.stop,k.sign,k.axis=start,start,sign,horizontal and "x" or "y"
            k.perpendicular=v
            local distanceFromCentre=math.abs(v-(lo+hi)/2)/c.spacing
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
        local light=C.light(320,C.lerp(m.arena.y-m.arena.h/2-110,290,opening),m.config.radius)
        m.lights={light}
        return
    end
    local f,t=m.vars.from,m.vars.target
    local p=C.curve("quart",m.phaseTime/m.vars.duration)
    m.lights={C.light(C.lerp(f.x,t.x,p),C.lerp(f.y,t.y,p),m.config.radius)}
end
function W.update(m)
    local s,c=m.stage,m.config
    if s==1 then
        if m.phaseTime>.7 and m:dialogueDone() then m:next() end
        return
    end
    if s==2 then
        if m.phaseTime>W.entryDuration+.05 then m:next() end
        return
    end
    if #m.knives==0 then
        if m.phaseTime>m.vars.duration+(s==6 and .10 or .35) then m:next() end
        return
    end
    local finished=true
    for _,k in ipairs(m.knives) do
        -- Clock-driven: neither player arrival nor light arrival gates launch.
        local attackStart=m.vars.duration+c.wave02Reaction+k.delay
        local t=m.phaseTime-attackStart
        local thrust=c.wave02Thrust
        local exit=thrust+c.wave02Hold
        k.alpha=C.ease((m.phaseTime-m.vars.duration+.12)/.12)
        if t<0 then
            local anticipation=C.ease((t+.10)/.10)
            k[k.axis]=k.start-k.sign*6*anticipation
            k.active=false
        elseif t<thrust then
            local light=m.lights[1]
            local core=c.radius*34/38
            local perpendicularLight=k.axis=="x" and light.y or light.x
            local delta=math.abs(k.perpendicular-perpendicularLight)
            local boundary=delta<core and math.sqrt(core*core-delta*delta) or 0
            local desired=(k.axis=="x" and light.x or light.y)-k.sign*(boundary+30*k.scale)
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
