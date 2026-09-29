local P=(...):match('(.-)waves%.')
local C=require(P..'waves.common')
local Cloth=require(P..'cloth')
local Curtain=require(P..'curtain-preview')
local Wave06=require(P..'waves.wave06')
local Wave08=require(P..'waves.wave08')
local Covered=Wave06.covered
-- Round 09 is the pre-arranged puzzle: a scenery hat, scenery blades and a
-- half-width drape. Chara's aimed shots walk around a clock face; a full
-- revolution ends in the seamless wall the hat has to shelter the soul from.
-- 340 wide: the finale lays out the whole set. Height stays at the HUD's limit.
local W={arena={x=320,y=300,w=340,h=190},stages={'开场','解谜 · 送帽入幕'},
    animatesOpeningBox=true,openingWidth=70,resizeTime=.5,slideTime=.7,expandTime=.7,
    darkEnterTime=.85,
    -- Keep the adopted scenery hat at a 26px radius, regardless of the
    -- current game sprite's source dimensions.
    hatRadius=26,pushSpeed=92,pushTouch=6,
    -- Pixel-space constrained rigid body. Normal resistance models the force
    -- required to push across the stage; Coulomb friction limits sideways grip.
    hatMass=1,hatInertiaFactor=.5,hatFriction=.65,
    normalResistance=14,tangentResistance=12,angularDamping=4,physicsStep=1/240,
    -- Contact is measured to the blade's edge, not its centre line, so the
    -- drawn brim stops where the drawn blade begins.
    bladeHalf=7,
    -- A blade whose point lines up with the hat's centre pierces it and lets it
    -- through; anything else presents the blade's body and blocks.
    tipWindow=10,
    stabReach=28,retreatSpeed=78,recoverSpeed=20,maxRetreat=102,
    wallPitch=16,wallEnter=.5,wallStagger=.22,wallHold=.18,wallSlide=40,
    repelRadius=Wave08.repelRadius,repelAcceleration=Wave08.repelAcceleration,
    coveredHold=.3,clothMargin=Cloth.presets[Curtain.ADOPTED.clothStyle].margin}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function length(x,y) return math.sqrt(x*x+y*y) end
function W.hatBounds(m)
    local a=m.arena
    return a.x-a.w/2+W.hatRadius,a.x+a.w/2-W.hatRadius,
        a.y-a.h/2+W.hatRadius,a.y+a.h/2-W.hatRadius
end
-- Contact between a hat centre and one blade, in the blade's own frame, for a
-- hat arriving at (hx,hy) with step (sx,sy). Returns the blade axis when it
-- blocks, or nil when the hat may occupy that point. A blade lined up with the
-- hat's centre has pierced it: the hat keeps sliding toward the handle and out
-- the far side, but cannot back off the point, so each blade is a one-way door
-- facing the side its tip points at.
function W.blocks(k,hx,hy,sx,sy,radius)
    local c,s=math.cos(k.angle),math.sin(k.angle)
    local dx,dy=hx-k.x,hy-k.y
    local lx,ly=dx*c+dy*s,-dx*s+dy*c
    local along=clamp(lx,-16,30)
    if length(lx-along,ly)>=(radius or W.hatRadius+W.bladeHalf) then return nil end
    if math.abs(ly)<W.tipWindow then
        -- Standing skewered is legal; moving is only legal toward the handle.
        local move=(sx or 0)*c+(sy or 0)*s
        if move<0 or (sx==0 and sy==0) then return nil end
    end
    return c,s
end
-- The blade has gone into the hat: its point lines up and the hat reaches it.
function W.threads(k,hx,hy)
    local c,s=math.cos(k.angle),math.sin(k.angle)
    local dx,dy=hx-k.x,hy-k.y
    local lx,ly=dx*c+dy*s,-dx*s+dy*c
    local along=clamp(lx,-16,30)
    return math.abs(ly)<W.tipWindow and length(lx-along,ly)<W.hatRadius+W.bladeHalf
end
function W.free(m,hx,hy,sx,sy,ignore)
    for _,k in ipairs(m.knives) do
        if k.prop and not (ignore and ignore[k]) and W.blocks(k,hx,hy,sx,sy) then return false end
    end
    return true
end
-- Blocked pushes slide along the blade body instead of stopping dead. A blade
-- that thrust or drifted into the hat is ignored, so the hat is never sealed
-- inside a blade it did not walk into.
function W.moveHat(m,h,dx,dy)
    local left,right,top,bottom=W.hatBounds(m)
    -- A threaded hat rides the blade like a rail: any push becomes motion
    -- along the blade toward its handle, and nothing pulls it back off the point.
    for _,k in ipairs(m.knives) do
        if k.prop and W.threads(k,h.x,h.y) then
            local c,s=math.cos(k.angle),math.sin(k.angle)
            local along=math.min(0,dx*c+dy*s)
            dx,dy=along*c,along*s
            break
        end
    end
    if dx==0 and dy==0 then return false end
    local ignore
    for _,k in ipairs(m.knives) do
        -- Only a flank contact can be pre-existing: a blade drifted or thrust
        -- into the hat. A skewered blade stays in force, so the hat cannot
        -- reverse off the point it entered.
        if k.prop and W.blocks(k,h.x,h.y,0,0) then ignore=ignore or {}; ignore[k]=true end
    end
    local function try(ddx,ddy)
        local x,y=clamp(h.x+ddx,left,right),clamp(h.y+ddy,top,bottom)
        if not W.free(m,x,y,ddx,ddy,ignore) then return false end
        -- Props are solid to each other; a hat does not shove another hat.
        for _,other in ipairs(m.vars.hats or {}) do
            if other~=h and length(other.x-x,other.y-y)<2*W.hatRadius
                and length(other.x-x,other.y-y)<length(other.x-h.x,other.y-h.y) then return false end
        end
        h.x,h.y=x,y; return true
    end
    if try(dx,dy) then return true end
    for _,k in ipairs(m.knives) do
        if k.prop and not (ignore and ignore[k]) then
            local c,s=W.blocks(k,h.x+dx,h.y+dy,dx,dy)
            if c then
                local along=dx*c+dy*s
                if try(along*c,along*s) then return true end
            end
        end
    end
    return false
end
-- Rotate the whole prop around the contact point. Its centre follows the arc
-- too, so the drawn rotation and the circular collision body stay together.
-- Stop at the first blocked arc step instead of sliding off the pivot's circle.
function W.rotateHat(m,h,px,py,angle)
    local radius=length(h.x-px,h.y-py)
    if radius<.001 or math.abs(angle)<1e-10 then return 0 end
    local left,right,top,bottom=W.hatBounds(m)
    local steps=math.max(1,math.ceil(math.abs(angle)*radius))
    local turn=angle/steps
    local c,s=math.cos(turn),math.sin(turn)
    local turned=0
    for _=1,steps do
        local x,y=h.x,h.y
        local dx,dy=x-px,y-py
        local tx,ty=px+dx*c-dy*s,py+dx*s+dy*c
        if tx<left or tx>right or ty<top or ty>bottom then break end
        W.moveHat(m,h,tx-x,ty-y)
        if math.abs(h.x-tx)+math.abs(h.y-ty)>1e-7 then
            h.x,h.y=x,y
            break
        end
        h.angle=(h.angle or 0)+turn
        turned=turned+turn
    end
    return turned
end
-- A player-pivot constraint is intentional gameplay, rather than a free disc:
-- I_p = I_cm + m*r^2, with a uniform-disc estimate for the hat's mass profile.
-- Sideways grip opposes relative slip and is capped by mu * normal pressure.
-- Integrate I_p*omega' = r*F_t - damping*I_p*omega, retaining angular velocity
-- across contact steps so changes in push direction do not snap the turn rate.
function W.pushRotation(omega,normalSpeed,tangentSpeed,radius,dt)
    if normalSpeed<=0 or dt<=0 then return 0,0 end
    local mass=W.hatMass
    local inertia=mass*(W.hatInertiaFactor*W.hatRadius^2+radius^2)
    local normalForce=mass*W.normalResistance*normalSpeed
    local slip=tangentSpeed-radius*omega
    local force=clamp(mass*W.tangentResistance*slip,
        -W.hatFriction*normalForce,W.hatFriction*normalForce)
    local terminal=radius*force/(inertia*W.angularDamping)
    local decay=math.exp(-W.angularDamping*dt)
    local angle=terminal*dt+(omega-terminal)*(1-decay)/W.angularDamping
    return angle,terminal+(omega-terminal)*decay
end
-- Adopted layout 04 from barrage-lab be715c8: the clock keeps running
-- while the right drape lifts and the left drape falls.
W.layout={name='幕布换边',hours=12,period=1.30,volley=1,switchAt=6,
    drape={330,490},switchDrape={150,300},hats={{430,300}},
    -- Two inward-facing vertical blades leave the centre clear for the hat.
    blades={{kind='door',x=320,y=221,angle=math.pi/2},
        {kind='door',x=320,y=379,angle=-math.pi/2}}}
local function prop(m,x,y,angle)
    local k=m:knife(x,y,angle)
    k.prop=true; k.active=true; k.alpha=1
    k.baseX,k.baseY,k.retreat,k.stab=x,y,0,0
    k.oldX,k.oldY,k.oldAngle=x,y,angle
    return k
end
local function build(m,layout)
    for _,spec in ipairs(layout.blades) do
        local function skipped(v)
            for _,range in ipairs(spec.skips or {spec.skip}) do
                if range and v>range[1] and v<range[2] then return true end
            end
        end
        if spec.kind=='col' then
            for y=spec.from,spec.to,W.wallPitch do
                if not skipped(y) then
                    local k=prop(m,spec.x,y,spec.angle)
                    k.drift,k.driftPeriod=spec.drift,spec.driftPeriod
                end
            end
        elseif spec.kind=='row' then
            for x=spec.from,spec.to,W.wallPitch do
                if not skipped(x) then prop(m,x,spec.y,spec.angle) end
            end
        elseif spec.kind=='list' then
            for _,y in ipairs(spec.ys) do prop(m,spec.x,y,spec.angle) end
        elseif spec.kind=='door' then
            local k=prop(m,spec.x,spec.y,spec.angle)
            k.door,k.drift,k.driftPeriod=true,spec.drift,spec.driftPeriod
        elseif spec.kind=='ring' then
            for i=0,spec.n-1 do
                local a=-math.pi/2+i*2*math.pi/spec.n
                local x,y=m.arena.x+math.cos(a)*spec.rx,m.arena.y+math.sin(a)*spec.ry
                prop(m,x,y,math.atan2(m.arena.y-y,m.arena.x-x)).hour=i
            end
        end
    end
end
-- The cloth is built from a rect, so a half-width drape is the same physical
-- fabric over a narrower span. `span` is the arena X range it should cover.
function W.drape(m,span,animate)
    m.clothRect={x=(span[1]+span[2])/2,y=m.arena.y,
        w=span[2]-span[1]-2*W.clothMargin,h=m.arena.h}
    if m.clothState then m.clothState:destroy(); m.clothState=nil end
    m.curtain=true; Curtain.applyAdopted(m)
    m.clothTransition=animate and {kind='enter',time=0} or nil
end
function W.enter(m)
    m.dark=false; m.darkAmount=0; m.lights={}; m.curtain=false
    m.ambient=nil; m.ambientSilhouette=nil; m.clothRect=nil; m.clothTransition=nil
    if m.stage==1 then m.caption={'Chara','Wave09.Intro'}; return end
    local layout=W.layout
    m.dark=true; m.darkAmount=0
    -- Tip direction is the puzzle, so the dark stage keeps blades readable.
    m.ambient=1
    m.ambientSilhouette=math.min(.85,m.ambient*2.5)
    m.vars={layout=layout,hour=0,clock=0,time=0,fired=0,solved=false,coveredTime=0,repelled=0,
        hits=0,wallFired=false,switched=false,hats={},sceneEntry=0}
    for _,spot in ipairs(layout.hats) do
        m.vars.hats[#m.vars.hats+1]={x=spot[1],y=spot[2],diameter=2*W.hatRadius,
            alpha=0,angle=0,angularVelocity=0}
    end
    build(m,layout)
    -- The moving box may leave the soul inside the authored hat position.
    -- Place the still-invisible prop clear of it; spawning scenery must never
    -- send the soul through afterMove's overlap correction on the next frame.
    for _,h in ipairs(m.vars.hats) do
        local dx,dy=h.x-m.player.x,h.y-m.player.y
        local d=length(dx,dy)
        local clearance=W.hatRadius+W.pushTouch+1
        if d<clearance then
            local distance=clearance-d
            if d<.001 then dx,dy,d=-1,0,1 end
            W.moveHat(m,h,dx/d*distance,dy/d*distance)
        end
    end
    for _,k in ipairs(m.knives) do k.active=false; k.alpha=0 end
    if not layout.curtainAt then W.drape(m,layout.drape,true) end
end
-- The engine holds the incoming box through the opening line. Resize it first,
-- carry the soul with its horizontal translation, then open only the left edge.
-- Expanding the box never drags the soul back toward the centre.
local function opening(m,dt)
    local v,a=m.vars,m.arena
    if not v.boxEntry then
        v.boxEntry={time=0,from={x=a.x,y=a.y,w=a.w,h=a.h}}
    end
    local entry=v.boxEntry
    entry.time=entry.time+dt
    local t,from=entry.time,entry.from
    local right=W.arena.x+W.arena.w/2
    local targetX=right-W.openingWidth/2
    if t<W.resizeTime then
        v.openingPhase='resize'
        local p=C.curve('quart',t/W.resizeTime)
        a.x=from.x; a.y=C.lerp(from.y,W.arena.y,p)
        a.w=C.lerp(from.w,W.openingWidth,p); a.h=C.lerp(from.h,W.arena.h,p)
    elseif t<W.resizeTime+W.slideTime then
        v.openingPhase='slide'
        local x=C.lerp(from.x,targetX,C.curve('quart',(t-W.resizeTime)/W.slideTime))
        m.player.x=m.player.x+x-a.x
        a.x,a.y,a.w,a.h=x,W.arena.y,W.openingWidth,W.arena.h
    else
        -- Account for the last fraction of translation before changing width.
        if v.openingPhase~='expand' then m.player.x=m.player.x+targetX-a.x end
        v.openingPhase='expand'
        local p=C.curve('quart',(t-W.resizeTime-W.slideTime)/W.expandTime)
        a.w=C.lerp(W.openingWidth,W.arena.w,p)
        a.x,a.y,a.h=right-a.w/2,W.arena.y,W.arena.h
        if p>=1 then m:next() end
    end
end
-- The soul pushes the prop hat by touching its brim. The hat is solid, so a
-- push that the blades refuse also stops the soul.
function W.afterMove(m,dt)
    if m.stage~=2 or not m.vars.hats or dt<=0 then return end
    local p,touch=m.player,W.hatRadius+W.pushTouch
    local startX,startY=p.oldX or p.x,p.oldY or p.y
    local moveX,moveY=p.x-startX,p.y-startY
    -- Reconstruct the native movement in small contact steps. This prevents
    -- a slow frame from delivering its entire push/rotation as one impulse.
    local steps=math.max(1,math.ceil(dt/W.physicsStep),math.ceil(length(moveX,moveY)))
    local step=dt/steps
    local a=m.arena
    p.x,p.y=startX,startY
    for _=1,steps do
        local oldX,oldY=p.x,p.y
        p.x=clamp(p.x+moveX/steps,a.x-a.w/2+8,a.x+a.w/2-8)
        p.y=clamp(p.y+moveY/steps,a.y-a.h/2+8,a.y+a.h/2-8)
        local vx,vy=(p.x-oldX)/step,(p.y-oldY)/step
        for _,h in ipairs(m.vars.hats) do
            local dx,dy=h.x-p.x,h.y-p.y
            local d=length(dx,dy)
            if d<touch then
                if d<.001 then dx,dy,d=0,-1,1 end
                local nx,ny=dx/d,dy/d
                local normal=math.max(0,nx*vx+ny*vy)
                local tangent=nx*vy-ny*vx
                local turn,omega=W.pushRotation(h.angularVelocity or 0,normal,tangent,touch,step)
                local outward=touch-d
                local gain=math.min(1,W.pushSpeed*step/math.max(.001,length(outward,touch*turn)))
                W.moveHat(m,h,nx*outward*gain,ny*outward*gain)
                local rx,ry=h.x-p.x,h.y-p.y
                local radius=length(rx,ry)
                if radius<touch then
                    if radius<.001 then rx,ry,radius=0,-1,1 end
                    p.x,p.y=h.x-rx/radius*touch,h.y-ry/radius*touch
                end
                turn=turn*gain
                local turned=W.rotateHat(m,h,p.x,p.y,turn)
                h.angularVelocity=math.abs(turned-turn)<1e-8 and omega*gain or 0
            else
                -- Preserve the adopted stop-on-release rule; no spin is stored
                -- while detached, so a later touch cannot revive old momentum.
                h.angularVelocity=0
            end
        end
    end
end
-- Round 05's near-tip thrust and round 06's under-cloth retreat, unchanged.
-- Only motion along the blade's own axis can open or close a passage, so the
-- 28px thrust is pressure and the 102px retreat is the gate.
-- Blades that drift or thrust into a hat shove it off their body. A hat the
-- blade has pierced rides along with the blade's sideways motion instead.
local function resolveHats(m,moved)
    local left,right,top,bottom=W.hatBounds(m)
    local contact=W.hatRadius+W.bladeHalf
    for _,h in ipairs(m.vars.hats) do
        for _,k in ipairs(m.knives) do
            if k.prop and moved[k] then
                local c,s=math.cos(k.angle),math.sin(k.angle)
                local dx,dy=h.x-k.x,h.y-k.y
                local lx,ly=dx*c+dy*s,-dx*s+dy*c
                local along=clamp(lx,-16,30)
                local d=length(lx-along,ly)
                if d<contact then
                    if math.abs(ly)<W.tipWindow then
                        local mx,my=moved[k][1],moved[k][2]
                        local side=-mx*s+my*c
                        h.x,h.y=h.x-s*side,h.y+c*side
                    elseif d>.001 then
                        local nx,ny=(lx-along)/d,ly/d
                        local wx,wy=nx*c-ny*s,nx*s+ny*c
                        h.x,h.y=h.x+wx*(contact-d),h.y+wy*(contact-d)
                    end
                    h.x,h.y=clamp(h.x,left,right),clamp(h.y,top,bottom)
                end
            end
        end
    end
end
-- A hat resting against a blade's body holds that blade back: recovery never
-- shoves the hat back out from under the cloth the soul just pushed it into.
local function pressesHat(m,k,x,y)
    local probe={x=x,y=y,angle=k.angle}
    for _,h in ipairs(m.vars.hats) do
        if W.blocks(probe,h.x,h.y,0,0) then return true end
    end
    return false
end
local function recover(m,k,retreat,baseY,c,s)
    if retreat>=k.retreat then return retreat end
    local offset=k.stab-retreat
    if pressesHat(m,k,k.baseX+c*offset,baseY+s*offset) then return k.retreat end
    return retreat
end
local function props(m,dt)
    local v=m.vars
    local moved={}
    for _,k in ipairs(m.knives) do
        if k.prop then
            local px,py=k.x,k.y
            local c,s=math.cos(k.angle),math.sin(k.angle)
            local baseY=k.baseY
            if k.drift then baseY=baseY+math.sin(v.time/k.driftPeriod*2*math.pi)*k.drift end
            local dx,dy=m.player.x-(k.x+28*c),m.player.y-(k.y+28*s)
            local ahead,across=dx*c+dy*s,math.abs(-dx*s+dy*c)
            k.covered=Covered(m,k.x+28*c,k.y+28*s)
            if k.covered then
                k.warnClock=nil; k.warning=false; k.stab=0
                -- Round 06: only the soul walks a covered blade back. A hat
                -- pressed against the point does not, so the soul has to get
                -- ahead of the hat, drive the row back, then return and push.
                if across<17 and ahead>-30 and ahead<30 then
                    k.retreat=math.min(W.maxRetreat,k.retreat+W.retreatSpeed*dt)
                else
                    k.retreat=recover(m,k,math.max(0,k.retreat-W.recoverSpeed*dt),baseY,c,s)
                end
            else
                k.retreat=recover(m,k,math.max(0,k.retreat-38*dt),baseY,c,s)
                if not k.warnClock and across<12 and ahead>=-2 and ahead<27 then k.warnClock=0 end
                if k.warnClock then
                    k.warnClock=k.warnClock+dt
                    local t=k.warnClock
                    k.warning=t<.4
                    k.stab=t<.4 and 0 or t<.62 and W.stabReach*C.ease((t-.4)/.22)
                        or t<.77 and W.stabReach or W.stabReach*(1-C.ease((t-.77)/.36))
                    if t>=1.5 then k.warnClock=nil; k.stab=0 end
                else k.warning=false end
            end
            local offset=k.stab-k.retreat
            k.x,k.y=k.baseX+c*offset,baseY+s*offset
            if k.x~=px or k.y~=py then moved[k]={k.x-px,k.y-py} end
        end
    end
    resolveHats(m,moved)
end
local function hourAngle(hour) return -math.pi/2+(hour%12)*math.pi/6 end
W.hourAngle=hourAngle
local function shot(m,x,y,tx,ty,speed)
    local dx,dy=tx-x,ty-y
    local d=math.max(.001,length(dx,dy))
    local k=m:knife(x,y,math.atan2(dy,dx))
    k.active,k.alpha,k.shot=true,1,true
    k.backdrop,k.visibleInside=true,true
    k.vx,k.vy=dx/d*speed,dy/d*speed
    k.oldX,k.oldY,k.oldAngle=x,y,k.angle
    return k
end
local function volley(m)
    local v,layout=m.vars,m.vars.layout
    local speed=layout.shotSpeed or 215
    v.fired=v.fired+1
    m:launch()
    if layout.ring then
        -- The clock face itself fires: that blade turns red, leaves, and the
        -- slot it held stays open for the hat.
        for _,k in ipairs(m.knives) do
            if k.prop and k.hour==v.hour then k.armed,k.speed=.35,speed; return end
        end
        return
    end
    local angle=hourAngle(v.hour)
    local a=m.arena
    local sx,sy=a.x+math.cos(angle)*(a.w/2+54),a.y+math.sin(angle)*(a.h/2+54)
    local ux,uy=-math.sin(angle),math.cos(angle)
    local count=layout.volley or 1
    for i=1,count do
        local offset=(i-(count+1)/2)*26
        shot(m,sx+ux*offset,sy+uy*offset,m.player.x,m.player.y,speed)
    end
end
-- The closing wall is genuinely seamless: identical directions at blade pitch,
-- so position alone cannot dodge it and only a covered hat bends it open.
local function wall(m)
    local v,layout=m.vars,m.vars.layout
    local angle,a=hourAngle(v.hour),m.arena
    local sx,sy=a.x+math.cos(angle)*(a.w/2+76),a.y+math.sin(angle)*(a.h/2+76)
    local tx,ty=m.player.x,m.player.y
    local d=math.max(.001,length(tx-sx,ty-sy))
    local ux,uy=-(ty-sy)/d,(tx-sx)/d
    local half=math.ceil(((a.w+a.h)/2+48)/W.wallPitch)
    for i=-half,half do
        local ox,oy=ux*i*W.wallPitch,uy*i*W.wallPitch
        local k=shot(m,sx+ox,sy+oy,tx+ox,ty+oy,layout.wallSpeed or 245)
        k.wallEntry={x=k.x,y=k.y,delay=math.abs(i)/half*W.wallStagger}
        k.x,k.y=k.x-math.cos(k.angle)*W.wallSlide,k.y-math.sin(k.angle)*W.wallSlide
        k.oldX,k.oldY=k.x,k.y
        k.active,k.alpha=false,0
    end
    v.wallFired,v.wallClock=true,0
end
-- Round 08's rule, unchanged: a hat the physical cloth actually covers pushes
-- nearby blades aside with finite force. Collisions stay enabled.
local function repel(m,k,dt)
    for _,h in ipairs(m.vars.hats) do
        if Covered(m,h.x,h.y) then
            local dx,dy=k.x-h.x,k.y-h.y
            local d=length(dx,dy)
            if d<W.repelRadius then
                if d<.001 then dx,dy,d=-math.cos(k.angle),-math.sin(k.angle),1 end
                if not k.repelled then k.repelled=true; m.vars.repelled=m.vars.repelled+1 end
                local force=W.repelAcceleration*(1-d/W.repelRadius)
                k.vx,k.vy=k.vx+dx/d*force*dt,k.vy+dy/d*force*dt
                local speed=length(k.vx,k.vy)
                if speed>560 then k.vx,k.vy=k.vx/speed*560,k.vy/speed*560 end
            end
        end
    end
end
local function flights(m,dt)
    local v=m.vars
    local wallDuration=W.wallEnter+W.wallStagger+W.wallHold
    if v.wallClock then
        v.wallClock=v.wallClock+dt
        if v.wallClock>=wallDuration and not v.wallLaunched then
            v.wallLaunched=true
            m:launch()
        end
    end
    for i=#m.knives,1,-1 do
        local k=m.knives[i]
        if k.wallEntry then
            local entry=k.wallEntry
            local progress=C.ease((v.wallClock-entry.delay)/W.wallEnter)
            k.alpha=progress
            k.x=entry.x-math.cos(k.angle)*W.wallSlide*(1-progress)
            k.y=entry.y-math.sin(k.angle)*W.wallSlide*(1-progress)
            if v.wallLaunched then
                k.wallEntry=nil; k.active=true
                k.oldX,k.oldY=k.x,k.y
            end
        elseif k.armed then
            k.armed=k.armed-dt; k.warning=true
            if k.armed<=0 then
                local dx,dy=m.player.x-k.x,m.player.y-k.y
                local d=math.max(.001,length(dx,dy))
                k.prop,k.armed,k.warning,k.shot=nil,nil,false,true
                k.backdrop,k.visibleInside=true,true
                k.vx,k.vy=dx/d*k.speed,dy/d*k.speed
                k.angle=math.atan2(dy,dx)
            end
        elseif k.shot then
            repel(m,k,dt)
            k.angle=k.angle+(math.atan2(k.vy,k.vx)-k.angle+math.pi)%(2*math.pi)-math.pi
            k.x,k.y=k.x+k.vx*dt,k.y+k.vy*dt
            if k.x<-40 or k.x>680 or k.y<-40 or k.y>520 then table.remove(m.knives,i) end
        end
    end
end
function W.update(m,dt,bulletDt)
    if m.stage==1 then
        if m:dialogueDone() then opening(m,dt) end
        return
    end
    local v,step=m.vars,bulletDt or dt
    local layout=v.layout
    if v.sceneEntry then
        v.sceneEntry=v.sceneEntry+dt
        local p=C.ease(v.sceneEntry/W.darkEnterTime)
        m.darkAmount=p
        m.ambient=C.lerp(1,layout.ambient or .62,p)
        m.ambientSilhouette=math.min(.85,m.ambient*2.5)
        for _,k in ipairs(m.knives) do k.alpha=p end
        for _,h in ipairs(v.hats) do h.alpha=p end
        if v.sceneEntry>=math.max(W.darkEnterTime,Curtain.ENTER_TIME) then
            v.sceneEntry=nil
            for _,k in ipairs(m.knives) do k.active=true end
        end
        return
    end
    v.clock,v.time=v.clock+step,v.time+step
    if layout.curtainAt and not m.curtain and v.hour>=layout.curtainAt then
        W.drape(m,layout.drape,true)
    end
    -- Switching sides pulls the first drape up with round 04's exit, then lays
    -- the second one; the soul is never under two cloths at once.
    if layout.switchAt and not v.switched and v.hour>=layout.switchAt then
        v.switched='pulling'; m.clothTransition={kind='exit',time=0}
    end
    if v.switched=='pulling' and m.clothTransition and m.clothTransition.time>=Curtain.EXIT_TIME then
        v.switched=true; W.drape(m,layout.switchDrape,true)
    end
    if not v.wallFired and v.clock>=layout.period then
        v.clock=v.clock-layout.period
        if v.hour>=layout.hours then wall(m) else volley(m); v.hour=v.hour+1 end
    end
    if v.hour>=3 and not v.spoke then
        v.spoke=true; m.caption={'Nap','Wave09.Nap','intermediate'}
    end
    props(m,step); flights(m,step)
    -- Solved is the same test round 08 repels with: the physical cloth actually
    -- covers the hat's centre. One rule serves as both goal and shelter.
    -- Latched once the set is struck: pulling the cloth up is not un-solving it.
    if not v.exit then
        local covered=false
        for _,h in ipairs(v.hats) do if Covered(m,h.x,h.y) then covered=true end end
        v.coveredTime=covered and v.coveredTime+dt or 0
        v.solved=v.coveredTime>=W.coveredHold
    end
    if m.caption and m.caption[2]=='Wave09.Nap' and m:dialogueDone() then
        m.caption={'Chara','Wave09.Reply','intermediate'}
    end
    if v.wallFired and not v.exit then
        local flying=false
        for _,k in ipairs(m.knives) do if k.shot then flying=true end end
        -- Once the wall has passed, the set is struck: the cloth pulls up with
        -- the adopted exit while the scenery fades, then the round closes.
        if not flying then
            v.exit=0
            if m.curtain then m.clothTransition={kind='exit',time=0} end
        end
    end
    if v.exit then
        v.exit=v.exit+dt
        local alpha=1-C.ease(v.exit/Curtain.EXIT_TIME)
        for _,k in ipairs(m.knives) do if k.prop then k.alpha=alpha end end
        for _,h in ipairs(v.hats) do h.alpha=alpha end
        if v.exit>=Curtain.EXIT_TIME and m.curtain then
            m.curtain=false; m.clothTransition=nil; m.clothRect=nil
            if m.clothState then m.clothState:destroy(); m.clothState=nil end
        end
        if v.exit>=Curtain.EXIT_TIME+.3 and m:dialogueDone() then
            m.knives={}; v.hats={}; m.caption=nil; m:next()
        end
    end
end
return W
