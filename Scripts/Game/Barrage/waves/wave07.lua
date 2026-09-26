local W={arena={x=320,y=300,w=280,h=180},stages={'开场','抛帽 · 磁性束缚'},
    radius=38,innerRadius=30,total=6,rowOffset=10,rowSpacing=16}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function length(x,y) return math.sqrt(x*x+y*y) end
local function bounds(m)
    local a=m.arena
    return a.x-a.w/2+8,a.x+a.w/2-8,a.y-a.h/2+8,a.y+a.h/2-8
end
-- Relative to the approved strength-4 curve: keep launch speed, double exit speed.
local strength=4-math.log(2)
local timeScale=(strength/4)*(1-math.exp(-4))/(1-math.exp(-strength))
local function out(t)
    return (1-math.exp(-strength*clamp(t,0,1)))/(1-math.exp(-strength))
end
function W.position(m,h,t)
    local q=out(t/h.easeTime)
    return h.startX+h.vx*q,h.startY+h.vy*q+.5*h.gravity*q*q
end
local throws={
    {gravity=55,slope=0}, {gravity=92,slope=30}, {gravity=72,rise=.55},
    {gravity=116,slope=16}, {gravity=64,slope=65}, {gravity=100,rise=.75},
}
function W.aim(m,h,velocity)
    local a=m.arena
    local left,right,top,bottom=bounds(m)
    local style=throws[m.vars.number]
    h.startX=a.x-h.direction*(a.w/2+W.radius)
    -- End just beyond the mask so the player sees the full deceleration.
    h.vx=h.direction*(a.w+2*W.radius)
    h.gravity=style.gravity
    h.vy=style.rise and -h.gravity*(W.radius/math.abs(h.vx))*style.rise or style.slope
    local lo,hi=0,h.easeTime
    for _=1,36 do
        local t=(lo+hi)/2
        local x=h.startX+h.vx*out(t/h.easeTime)
        local target=clamp(m.player.x+velocity.x*t,left,right)
        if (x-target)*h.direction<0 then lo=t else hi=t end
    end
    h.aimTime=(lo+hi)/2
    h.aimX=clamp(m.player.x+velocity.x*h.aimTime,left,right)
    h.aimY=clamp(m.player.y+velocity.y*h.aimTime,top,bottom)
    if h.aimY>a.y+12 then h.vy=-h.gravity*1.12 end
    local q=out(h.aimTime/h.easeTime)
    h.startY=h.aimY-h.vy*q-.5*h.gravity*q*q
    h.apexX=h.startX+h.vx*(-h.vy/h.gravity)
    h.duration=h.easeTime
    local _,endY=W.position(m,h,h.duration)
    if endY<a.y-a.h/2-W.radius or endY>a.y+a.h/2+W.radius then
        lo,hi=h.aimTime,h.duration
        for _=1,36 do
            local t=(lo+hi)/2
            local _,y=W.position(m,h,t)
            if y>=a.y-a.h/2-W.radius and y<=a.y+a.h/2+W.radius then lo=t else hi=t end
        end
        h.duration=(lo+hi)/2
    end
end
local function orbit(m,k)
    local a=m.arena
    local along=k.distance
    if k.side==1 then k.x,k.y,k.angle=a.x+along,a.y-a.h/2-W.rowOffset,math.pi/2
    elseif k.side==2 then k.x,k.y,k.angle=a.x+a.w/2+W.rowOffset,a.y+along,math.pi
    elseif k.side==3 then k.x,k.y,k.angle=a.x-along,a.y+a.h/2+W.rowOffset,-math.pi/2
    else k.x,k.y,k.angle=a.x-a.w/2-W.rowOffset,a.y-along,0 end
end
local function startRows(m)
    if m.vars.rowStarted then return end
    m.vars.rowStarted=true; m.vars.rowTime=0; m.vars.nextRowAt=0
end
local function spawn(m)
    local v=m.vars
    v.number=v.number+1
    local direction=m.player.x>m.arena.x+20 and -1
        or m.player.x<m.arena.x-20 and 1 or v.number%2==1 and 1 or -1
    local h={time=0,easeTime=m.config.wave07Profile.easeTimes[v.number]*timeScale,direction=direction,
        captured=false,released=false,shots=0,shotClock=.04}
    W.aim(m,h,v.aimVelocity)
    h.x,h.y=W.position(m,h,0); v.hat=h
    if v.number>=3 then
        startRows(m)
        if v.number==3 then m.caption={'Nap','Wave07.Nap','intermediate'} end
    end
end
function W.enter(m)
    m.dark=false; m.darkAmount=0; m.lights={}; m.curtain=false
    if m.stage==1 then m.caption={'Chara','Wave07.Intro'}; return end
    m.vars={number=0,gap=.35,captures=0,releases=0,launched=0,rowStarted=false,rowStop=false,
        emitted=0,retired=0}
end
local function captureFraction(p,h,oldX,oldY)
    local x,y=p.oldX-oldX,p.oldY-oldY
    local dx,dy=(p.x-h.x)-x,(p.y-h.y)-y
    local c=x*x+y*y-W.innerRadius^2
    if c<=0 then return 0 end
    local a=dx*dx+dy*dy
    local b=2*(x*dx+y*dy)
    local discriminant=b*b-4*a*c
    if a<=1e-12 or discriminant<0 then return nil end
    local t=(-b-math.sqrt(discriminant))/(2*a)
    if t>=0 and t<=1 then return t end
end
local function moveHat(m,dt)
    local v,p=m.vars,m.player
    local h=v.hat
    local oldX,oldY=h.x,h.y
    h.time=math.min(h.duration,h.time+dt); h.x,h.y=W.position(m,h,h.time)
    if not h.captured and not h.released then
        local fraction=captureFraction(p,h,oldX,oldY)
        if fraction then
            h.captured=true; v.captures=v.captures+1
            p.x,p.y=p.x+(h.x-oldX)*(1-fraction),p.y+(h.y-oldY)*(1-fraction)
        end
    elseif h.captured then
        p.x,p.y=p.x+h.x-oldX,p.y+h.y-oldY
    end
    if not h.captured then return end
    local left,right,top,bottom=bounds(m)
    local nx,ny=clamp(h.x,left,right),clamp(h.y,top,bottom)
    local inset=v.number>=3 and math.max(0,30-W.rowOffset) or 0
    local rl,rr,rt,rb=left+inset,right-inset,top+inset,bottom-inset
    local slipRight=h.x>oldX and h.x>rr and p.x>=rr
    local slipLeft=h.x<oldX and h.x<rl and p.x<=rl
    local slipBottom=h.y>oldY and h.y>rb and p.y>=rb
    local slipTop=h.y<oldY and h.y<rt and p.y<=rt
    if slipRight or slipLeft or slipBottom or slipTop or length(nx-h.x,ny-h.y)>W.innerRadius then
        if slipRight and p.oldX<=rr then p.x=rr end
        if slipLeft and p.oldX>=rl then p.x=rl end
        if slipBottom and p.oldY<=rb then p.y=rb end
        if slipTop and p.oldY>=rt then p.y=rt end
        p.x,p.y=clamp(p.x,left,right),clamp(p.y,top,bottom)
        h.captured=false; h.released=true; v.releases=v.releases+1
        return
    end
    p.x,p.y=clamp(p.x,left,right),clamp(p.y,top,bottom)
    local dx,dy=p.x-h.x,p.y-h.y
    local distance=length(dx,dy)
    if distance<=W.innerRadius then return end
    local qx,qy=h.x+dx*W.innerRadius/distance,h.y+dy*W.innerRadius/distance
    if qx<left or qx>right then
        qx=clamp(qx,left,right)
        local span=math.sqrt(math.max(0,W.innerRadius^2-(qx-h.x)^2))
        qy=clamp(p.y,math.max(top,h.y-span),math.min(bottom,h.y+span))
    elseif qy<top or qy>bottom then
        qy=clamp(qy,top,bottom)
        local span=math.sqrt(math.max(0,W.innerRadius^2-(qy-h.y)^2))
        qx=clamp(p.x,math.max(left,h.x-span),math.min(right,h.x+span))
    end
    p.x,p.y=qx,qy
end
local function attract(m,dt)
    local h=m.vars.hat
    if not h or not h.captured or h.shots>=2 then return end
    h.shotClock=h.shotClock-dt
    if h.shotClock>0 then return end
    local nearest,best=nil,180
    local a=m.arena
    for _,k in ipairs(m.knives) do
        local span=(k.side==1 or k.side==3) and a.w or a.h
        if k.kind=='orbit' and not k.proximityClock and k.distance>=-span/2 and k.distance<=span/2 then
            local d=length(k.x-h.x,k.y-h.y)
            if d<best then nearest,best=k,d end
        end
    end
    if nearest then
        nearest.kind='warning'; nearest.warning=true; nearest.timer=.10
        h.shots=h.shots+1; h.shotClock=.18
    end
end
-- Round 05's near-tip rule still applies without a hat. Keep the row's
-- tangential motion and add an independent inward thrust to this blade.
local function proximity(m,k,dt)
    local nx,ny=math.cos(k.angle),math.sin(k.angle)
    local dx,dy=m.player.x-(k.x+28*nx),m.player.y-(k.y+28*ny)
    local ahead,across=dx*nx+dy*ny,math.abs(dx*ny-dy*nx)
    local span=(k.side==1 or k.side==3) and m.arena.w or m.arena.h
    if not k.proximityClock and k.distance>=-span/2 and k.distance<=span/2
        and ahead>=-2 and ahead<27 and across<12 then k.proximityClock=0 end
    local reach=0
    if k.proximityClock then
        k.proximityClock=k.proximityClock+dt
        local t=k.proximityClock
        local function ease(q) q=clamp(q,0,1); return q*q*(3-2*q) end
        k.warning=t<.4
        reach=t<.4 and 0 or t<.62 and 28*ease((t-.4)/.22)
            or t<.77 and 28 or 28*(1-ease((t-.77)/.36))
        if t>=1.5 then k.proximityClock=nil end
    else k.warning=false end
    k.stabReach=reach
    k.x,k.y=k.x+nx*reach,k.y+ny*reach
end
local function knives(m,dt)
    local v=m.vars
    if not v.rowStarted then return end
    local previous=v.rowTime
    v.rowTime=v.rowTime+dt
    local speed=m.config.wave07Profile.orbitSpeed
    local interval=W.rowSpacing/speed
    if not v.rowStop then
        while v.nextRowAt<=v.rowTime+1e-10 do
            for side=1,4 do
                local span=(side==1 or side==3) and m.arena.w or m.arena.h
                local k=m:knife(0,0,0)
                v.emitted=v.emitted+1
                k.id=v.emitted; k.side=side; k.born=v.nextRowAt
                k.entry=-span/2-10; k.exit=span/2+10
                k.kind='orbit'; k.active=true; k.alpha=1; k.distance=k.entry
                orbit(m,k); k.oldX,k.oldY,k.oldAngle=k.x,k.y,k.angle
                k.birthFraction=clamp((k.born-previous)/dt,0,1)
            end
            v.nextRowAt=v.nextRowAt+interval
        end
    end
    for i=#m.knives,1,-1 do
        local k=m.knives[i]
        if k.kind=='orbit' or k.kind=='warning' then
            k.distance=k.entry+speed*(v.rowTime-k.born)
            orbit(m,k)
            if k.distance>k.exit then
                table.remove(m.knives,i); v.retired=v.retired+1
            elseif k.kind=='warning' then
                k.timer=k.timer-dt
                if k.timer<=0 then
                    local h=v.hat
                    if h and h.captured then
                        local dx,dy=h.x-k.x,h.y-k.y; local n=length(dx,dy)
                        k.vx,k.vy=dx/n*360,dy/n*360
                        k.angle=math.atan2(dy,dx); k.oldAngle=k.angle
                        k.kind='flight'; k.warning=false
                        v.launched=v.launched+1
                        m:launch()
                    else k.kind='orbit'; k.warning=false end
                end
            else
                proximity(m,k,dt)
            end
        elseif k.kind=='flight' then
            k.x,k.y=k.x+k.vx*dt,k.y+k.vy*dt
            local a=m.arena
            if math.abs(k.x-a.x)>a.w/2+34 or math.abs(k.y-a.y)>a.h/2+34 then
                table.remove(m.knives,i); v.retired=v.retired+1
            end
        end
    end
end
function W.update(m,dt)
    if m.stage==1 then
        if m:dialogueDone() then m:next() end
        return
    end
    local v=m.vars
    v.aimVelocity={x=clamp((m.player.x-m.player.oldX)/dt,-120,120),
        y=clamp((m.player.y-m.player.oldY)/dt,-120,120)}
    if v.hat then
        moveHat(m,dt)
        if v.hat.time>=v.hat.duration then
            assert(not v.hat.captured,'Hat must release before fully leaving the mask')
            v.hat=nil; v.gap=m.config.wave07Profile.gaps[v.number]
            if v.number==W.total then v.stopRequested=true end
        end
    elseif not v.stopRequested then
        v.gap=v.gap-dt
        if v.gap<=0 then spawn(m) end
    end
    if m.caption and m.caption[2]=='Wave07.Nap' and m:dialogueDone() then
        m.caption={'Chara','Wave07.Reply','intermediate'}
    end
    if v.stopRequested and m:dialogueDone() then v.rowStop=true end
    knives(m,dt); attract(m,dt)
    if v.rowStop and #m.knives==0 then m.caption=nil; m:next() end
end
return W
