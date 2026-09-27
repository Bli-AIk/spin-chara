local P=(...):match('(.-)waves%.')
local Knife=require(P..'knife')
local Hat=require(P..'waves.wave07')
local Covered=require(P..'waves.wave06').covered
local Curtain=require(P..'curtain-preview')
local W={arena={x=320,y=300,w=280,h=180},stages={'开场','抛帽对狙 · 幕下排刀'},
    repelRadius=108,repelAcceleration=5400,rowSpacing=16,
    fadeTime=.15,spinTime=.38,aimTime=.13,lockTime=.08,hatAt=.13,
    peekDepth=24,peekMove=.16,peekReturn=.12}
-- The real game's 14px blade outline and 16px pitch are used below.
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function norm(x,y) local d=math.sqrt(x*x+y*y); return x/math.max(d,.001),y/math.max(d,.001),d end
function W.enter(m)
    m.dark=false; m.darkAmount=0; m.lights={}; m.curtain=false
    if m.stage==1 then m.caption={'Chara','Wave08.Intro'}; return end
    m.vars={number=0,gap=.4,mode='gap',clock=0,captures=0,releases=0,repelled=0,
        denseLaunched=0,normalLaunched=0,underAimed=0,emitted=0}
end
local function hat(m)
    local v=m.vars
    local h={time=0,easeTime=1.65*Hat.timeScale,direction=v.direction,captured=false,released=false,
        peekElapsed=0}
    -- Predict from the actual throw, after the rim peek and withdrawal. The
    -- approved arc begins at its original off-screen point.
    local lead=W.peekMove+W.peekReturn
    local projected={x=m.player.x+v.aimVelocity.x*lead,y=m.player.y+v.aimVelocity.y*lead}
    local aimModel={arena=m.arena,player=projected,vars={number=(v.number-1)%6+1}}
    Hat.aim(aimModel,h,v.aimVelocity)
    h.peekStartX=h.startX
    h.x,h.y=h.peekStartX,h.startY
    v.hat=h
end
local function blade(m,x,y,delay,dense)
    local v=m.vars
    local angle=v.direction==1 and math.pi or 0
    local k=m:knife(x,y,angle)
    k.alpha=0; k.warning=true; k.life=0; k.prepTime=-(delay or 0)
    k.startAngle=angle; k.dense=dense; k.volley=v.number
    k.backdrop=true; k.visibleInside=true
    k.oldX,k.oldY,k.oldAngle=x,y,angle
    v.emitted=v.emitted+1
    return k
end
local function aimed(m,dense)
    local v,a=m.vars,m.arena
    -- All source pixels remain outside both the frame and drape while spinning.
    local x=a.x+v.direction*(a.w/2+76)
    if dense then
        -- Same centred coverage as real round 02: cover the soul's reachable
        -- height with a 14px blade outline and exact 16px pitch.
        local first,count=Knife.row(a.y,a.h-16,W.rowSpacing)
        for i=0,count-1 do blade(m,x,first+i*W.rowSpacing,0,true) end
    else
        for shot=1,3 do
            blade(m,x,a.y+(shot-2)*44,(shot-1)*m.config.wave08Profile.shotGap,false)
        end
    end
end
local function begin(m)
    local v=m.vars
    v.number=v.number+1; v.direction=v.number%2==1 and 1 or -1
    v.clock=0; v.hatThrown=false; v.fired=false
    v.mode=v.number<=6 and 'normal' or 'dense'
    aimed(m,v.number>=7)
end
local function angleNear(angle,reference)
    return reference+(angle-reference+math.pi)%(2*math.pi)-math.pi
end
local function prepare(m,k,dt)
    local v=m.vars
    k.prepTime=k.prepTime+dt
    local t=k.prepTime
    local fade=clamp(t/W.fadeTime,0,1); k.alpha=fade*fade*(3-2*fade)
    if t<=W.spinTime then
        local q=clamp(t/W.spinTime,0,1)
        k.angle=k.startAngle+2*math.pi*(q*q*(3-2*q))
        return
    end
    local spinEnd=k.startAngle+2*math.pi
    if not k.locked then
        -- Track while aiming; the final hold visibly locks a single straight shot.
        -- The wall already covers every Y the soul can reach. Point all its
        -- blades inward together; targeting each blade would open fan gaps.
        local x=k.dense and m.arena.x or m.player.x
        local y=k.dense and k.y or m.player.y
        local sourceY=k.y
        local target=angleNear(math.atan2(y-sourceY,x-k.x),spinEnd)
        local q=clamp((t-W.spinTime)/W.aimTime,0,1)
        k.angle=spinEnd+(target-spinEnd)*(q*q*(3-2*q))
        if q>=1 then
            k.locked=true; k.targetX,k.targetY=x,y
            local speed=m.config.wave08Profile.speeds[v.number]
            k.vx,k.vy=math.cos(k.angle)*speed,math.sin(k.angle)*speed
        end
    end
    if t>=W.spinTime+W.aimTime+W.lockTime then
        k.warning=false; k.active=true; k.alpha=1
        if k.dense then
            if not v.fired then v.fired=true; v.denseLaunched=v.denseLaunched+1; m:launch() end
        else
            v.normalLaunched=v.normalLaunched+1
            m:launch()
            if m.curtain and not v.fired then v.fired=true;v.underAimed=v.underAimed+1 end
        end
    end
end
function W.repulse(m,k,dt)
    local h=m.vars.hat
    if not h or not Covered(m,h.x,h.y) then return end
    local nx,ny,d=norm(k.x-h.x,k.y-h.y)
    if d>=W.repelRadius then return end
    -- Finite acceleration changes the actual trajectory. A dead-centre blade
    -- reverses; off-centre blades bend around the hat. Collision stays enabled.
    if d<.001 then nx,ny=-math.cos(k.angle),-math.sin(k.angle) end
    local force=W.repelAcceleration*(1-d/W.repelRadius)
    k.vx,k.vy=k.vx+nx*force*dt,k.vy+ny*force*dt
    local ux,uy,speed=norm(k.vx,k.vy)
    if speed>560 then k.vx,k.vy=ux*560,uy*560 end
    if not k.repelled then k.repelled=true; m.vars.repelled=m.vars.repelled+1 end
end
local function knives(m,dt)
    for i=#m.knives,1,-1 do
        local k=m.knives[i]
        if k.warning then prepare(m,k,dt) end
        if k.active then
            k.life=k.life+dt
            W.repulse(m,k,dt)
            local angle=math.atan2(k.vy,k.vx)
            -- Keep the swept collision rotation on the shortest angular arc.
            k.angle=k.angle+(angle-k.angle+math.pi)%(2*math.pi)-math.pi
            k.x,k.y=k.x+k.vx*dt,k.y+k.vy*dt
            if k.x < -36 or k.x > 676 or k.y < -36 or k.y > 516 then table.remove(m.knives,i) end
        end
    end
end
local function clearCloth(m)
    m.curtain=false; m.dark=false; m.clothTransition=nil
    if m.clothState then m.clothState:destroy(); m.clothState=nil end
end
function W.update(m,dt,bulletDt)
    if m.stage==1 then
        if m:dialogueDone() and m.phaseTime>.6 then m:next() end
        return
    end
    local v=m.vars
    local step=bulletDt or dt
    v.aimVelocity={x=clamp((m.player.x-m.player.oldX)/dt,-120,120),y=clamp((m.player.y-m.player.oldY)/dt,-120,120)}
    v.clock=v.clock+step
    if v.hat then
        local h=v.hat
        if h.peekElapsed then
            h.peekElapsed=h.peekElapsed+step
            local distance
            if h.peekElapsed<=W.peekMove then
                local q=clamp(h.peekElapsed/W.peekMove,0,1)
                distance=W.peekDepth*(q*q*(3-2*q))
            else
                local q=clamp((h.peekElapsed-W.peekMove)/W.peekReturn,0,1)
                distance=W.peekDepth*(1-q*q*(3-2*q))
            end
            h.x=h.peekStartX+h.direction*distance
            if h.peekElapsed>=W.peekMove+W.peekReturn then
                h.peekElapsed=nil; h.x,h.y=Hat.position(m,h,0)
            end
        else
            Hat.moveHat(m,step)
            if h.time>=h.duration then v.hat=nil end
        end
    end
    if v.mode=='gap' then
        v.gap=v.gap-step
        if v.gap<=0 then
            if v.number==4 and not m.curtain then
                v.mode='curtain';m.curtain=true;m.dark=true
                Curtain.applyAdopted(m);Curtain.transition(m,'enter')
                m.caption={'Nap','Wave08.Nap','intermediate'}
            else begin(m) end
        end
    elseif v.mode=='curtain' then
        if m.clothTransition.time>=Curtain.ENTER_TIME*.64 then begin(m) end
    elseif v.mode=='normal' or v.mode=='dense' then
        if not v.hatThrown and v.clock>=W.hatAt then hat(m);v.hatThrown=true end
        if v.hatThrown and not v.hat and #m.knives==0 then
            if v.number==8 then
                Curtain.transition(m,'exit');v.mode='exit'
            else
                v.mode='gap';v.gap=m.config.wave08Profile.gaps[v.number]
            end
        end
    elseif v.mode=='exit' then
        if m.clothTransition.time>=Curtain.EXIT_TIME then clearCloth(m);v.mode='finish' end
    elseif v.mode=='finish' and m:dialogueDone() then
        m.caption=nil;m:next()
    end
    knives(m,step)
    if m.caption and m.caption[2]=='Wave08.Nap' and m:dialogueDone() then
        m.caption={'Chara','Wave08.Reply','intermediate'}
    end
end
return W
