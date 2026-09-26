local P=(...):match('(.-)waves%.')
local C=require(P..'waves.common')
local Curtain=require(P..'curtain-preview')
local Lighting=require(P..'lighting')
local Knife=require(P..'knife')
local W={arena={x=320,y=315,w=155,h=130},reusesIncomingBox=true,stages={'开场','聚光灯入场','左右夹击 · 幕下退刀'},
    pressureSpeed=6,retreatSpeed=78,preCurtain=7,entryDuration=1.5,exitDuration=1.5}
local function approach(a,b,d) return a<b and math.min(b,a+d) or math.max(b,a-d) end

-- Use the same inverse cloth displacement as the curtain shader, so a tip
-- changes rules only once the actual falling fabric covers it.
function W.covered(m,x,y)
    local cloth=m.clothState
    if not m.curtain or not cloth then return false end
    local offset,stretch=Curtain.pose(m)
    local tr=m.clothTransition
    local laying=tr and tr.kind=='enter' and Curtain.laying(tr.time,m.entryVariant) or 1
    if laying<=0 then return false end
    local sy=cloth.y+(y-cloth.y-offset)/stretch
    sy=cloth.y+(sy-cloth.y)/math.max(.002,laying)
    local px,py=x,sy
    for _=1,2 do
        local u=C.clamp((px-cloth.x)/cloth.w)*(cloth.cols-1)
        local v=C.clamp((py-cloth.y)/cloth.h)*(cloth.rows-1)
        local i,j=math.min(cloth.cols-2,math.floor(u)),math.min(cloth.rows-2,math.floor(v))
        local dx,dy=0,0
        for oy=0,1 do for ox=0,1 do
            local n=cloth.nodes[(j+oy)*cloth.cols+i+ox+1]
            local weight=(ox==0 and 1-(u-i) or u-i)*(oy==0 and 1-(v-j) or v-j)
            dx=dx+(n.x-n.rx+n.z*.32)*weight; dy=dy+(n.y-n.ry+n.z*.12)*weight
        end end
        px,py=x-dx*laying,sy-dy*laying
    end
    return px>=cloth.x and px<=cloth.x+cloth.w and py>=cloth.y and py<=cloth.y+cloth.h
end
function W.enter(m)
    m.dark=false; m.darkAmount=0
    if m.stage==1 then
        m.caption={'Chara','Wave06.Intro'}
        return
    end
    m.dark=true
    if m.stage==2 then
        m.lights={C.light(m.arena.x,m.arena.y-m.arena.h/2-Lighting.outerRadius(m.config.radius,m.lightStyle),m.config.radius)}
        return
    end
    m.darkAmount=1
    m.lights={C.light(m.arena.x,m.arena.y,m.config.radius)}
    local v=m.vars
    v.rest=0; v.clock=0; v.mode='sweep'; v.pass=0; v.direction=1
    v.sweepY=m.arena.y-m.arena.h/2-24
    v.left={}; v.sweep={}
    local first,count=Knife.row(m.arena.y,m.arena.h-16,m.config.spacing)
    for i=0,count-1 do
        local y=first+i*m.config.spacing
        local k=m:knife(m.arena.x-m.arena.w/2-30,y,0)
        k.kind='left'; k.retreat=0; k.stab=0; k.active=true
        v.left[#v.left+1]=k
    end
    -- One authored-size horizontal blade; only its Y changes through the stencil.
    -- The 60px sprite is centred at 30px; its rightmost handle meets the inner rim.
    local k=m:knife(m.arena.x+m.arena.w/2-30,v.sweepY,math.pi)
    k.kind='sweep'; k.active=true
    v.sweep[1]=k
end
local function leftRow(m,dt)
    local v=m.vars
    v.pressure=math.min(m.curtain and 102 or 40,(v.pressure or 0)+dt*W.pressureSpeed)
    local base=m.arena.x-m.arena.w/2-30+v.pressure
    for _,k in ipairs(v.left) do
        k.covered=W.covered(m,k.x+30,k.y)
        local dy=math.abs(m.player.y-k.y)
        if k.covered then
            k.warnClock=nil; k.stab=0; k.warning=false
            -- Repulsion is a velocity, not a guaranteed safe offset. Normal
            -- movement (120px/s) can overtake this retreat and hit the blade.
            local gap=m.player.x-(k.x+30)
            if dy<17 and gap<30 and gap>-30 then
                k.retreat=math.min(110,k.retreat+W.retreatSpeed*dt)
            else
                k.retreat=approach(k.retreat,0,dt*20)
            end
        else
            k.retreat=approach(k.retreat,0,dt*38)
            local gap=m.player.x-(k.x+30)
            if not k.warnClock and dy<12 and gap>=0 and gap<27 then k.warnClock=0 end
            if k.warnClock then
                k.warnClock=k.warnClock+dt
                local t=k.warnClock
                k.warning=t<.4
                k.stab=t<.4 and 0 or t<.62 and 26*C.ease((t-.4)/.22)
                    or t<.77 and 26 or 26*(1-C.ease((t-.77)/.36))
                if t>1.5 then k.warnClock=nil end
            else k.stab=0; k.warning=false end
        end
        k.x=base-k.retreat+k.stab
    end
end
function W.update(m,dt,bulletDt)
    if m.stage==1 then
        if m:dialogueDone() then m:next() end
        return
    end
    if m.stage==2 then
        if m.phaseTime>=W.entryDuration then m:next() end
        return
    end
    local v=m.vars
    v.clock=v.clock+bulletDt
    if v.mode=='sweep' then
        leftRow(m,bulletDt)
        if v.clock>1.6 then
            local profile=m.config.wave06Profile
            local travelDt=bulletDt
            if v.rest>0 then
                local held=math.min(v.rest,travelDt)
                v.rest=v.rest-held; travelDt=travelDt-held
            end
            v.sweepY=v.sweepY+v.direction*travelDt*profile.speeds[math.min(v.pass+1,#profile.speeds)]
            if not m.curtain and v.clock>=W.preCurtain and v.direction==1 and v.sweepY>=m.player.y-70 then
                m.curtain=true; Curtain.applyAdopted(m); Curtain.transition(m,'enter')
                m.caption={'Nap','Wave06.Nap','intermediate'}; v.curtainAt=v.clock
                v.finishPass=2*math.ceil((v.pass+6)/2)
            end
            if m.caption and m.caption[2]=='Wave06.Nap' and m:dialogueDone() then
                m.caption={'Chara','Wave06.Reply','intermediate'}
            end
            local top,bottom=m.arena.y-m.arena.h/2-24,m.arena.y+m.arena.h/2+24
            local boundary=v.direction==1 and bottom or top
            if (v.sweepY-boundary)*v.direction>=0 then
                v.sweepY=boundary; v.direction=-v.direction; v.pass=v.pass+1
                v.rest=profile.rest
                if v.finishPass and v.pass==v.finishPass then
                    v.mode='uncover'; v.time=0
                    Curtain.transition(m,'exit')
                    for _,k in ipairs(v.sweep) do k.active=false end
                end
            end
        end
        for _,k in ipairs(v.sweep) do k.y=v.sweepY end
    elseif v.mode=='uncover' then
        -- Preserve the existing opening while the curtain lifts. The final
        -- attack is a single visible blade, after the retreat rule has ended.
        v.time=v.time+dt
        if v.time>=Curtain.EXIT_TIME then
            m.curtain=false
            v.mode='sneak'; v.time=0
            local nearest
            for _,k in ipairs(v.left) do
                if not nearest or math.abs(k.y-m.player.y)<math.abs(nearest.y-m.player.y) then nearest=k end
            end
            v.sneak=nearest; v.sneakX=nearest.x; nearest.warning=true
        end
    elseif v.mode=='sneak' then
        v.time=v.time+bulletDt
        local t=v.time
        v.sneak.warning=t<.4
        local reach=t<.4 and 0 or t<.58 and 44*C.ease((t-.4)/.18)
            or t<.70 and 44 or 44*(1-C.ease((t-.70)/.4))
        v.sneak.x=v.sneakX+reach
        if t>=1.2 then
            v.mode='exit'; v.time=0
            for _,k in ipairs(m.knives) do k.active=false; k.warning=false end
        end
    elseif v.mode=='exit' then
        v.time=v.time+dt
        m.darkAmount=1-C.curve("quart",v.time/W.exitDuration)
        for _,k in ipairs(m.knives) do k.alpha=1-C.ease(v.time/W.exitDuration) end
        if v.time>=W.exitDuration and m:dialogueDone() then
            m.lights={}; m.dark=false; m.curtain=false; m.caption=nil
            if m.clothState then m.clothState:destroy(); m.clothState=nil end
            m:next()
        end
    end
end
function W.lighting(m)
    if m.stage==1 then m.lights={}; return end
    local outside=m.arena.y-m.arena.h/2-Lighting.outerRadius(m.config.radius,m.lightStyle)
    if m.stage==2 then
        local t=C.curve('quart',m.phaseTime/W.entryDuration)
        m.darkAmount=t
        m.lights={C.light(m.arena.x,C.lerp(outside,m.arena.y,t),m.config.radius)}
    elseif m.vars.mode=='exit' then
        local t=C.curve('quart',m.vars.time/W.exitDuration)
        m.lights={C.light(m.arena.x,C.lerp(m.arena.y,outside,t),m.config.radius)}
    end
end
return W
