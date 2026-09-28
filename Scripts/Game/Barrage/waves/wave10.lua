-- Undertale's obj_crygen1 / blt_crybullet, normal mercymod=-400.
-- Motion values are pixels per 30 Hz frame; never multiply friction/gravity
-- directly by the host's variable dt. See README for source and mask limits.
local P=(...):match('(.-)waves%.')
local Collision=require(P..'knife')
local W={arena={x=320,y=315,w=155,h=130},reusesIncomingBox=true,
    stages={'开场','Nap 上场','散落眼泪','Chara 质问','Nap 回答','罢演','最后通牒','离场'},
    frames=140,interval=10,sourceX=266,sourceY=44,
    -- Convex silhouette of the existing 12x13 tear, relative to (6,6).
    -- Exported GML has no GameMaker mask metadata; use swept host geometry.
    polygon={0,-6,4,1,4,4,1,6,-2,6,-5,3,-4,0}}
local function ease(t) t=math.min(1,math.max(0,t));return t*t*(3-2*t) end
local function random(v) v.rng=(v.rng*48271)%2147483647;return (v.rng-1)/2147483646 end
function W.enter(m)
    m.dark=false;m.darkAmount=0;m.curtain=false;m.lights={}
    if m.stage==1 then
        m.vars={tears={},rng=m.config.seed,frame=0,accumulator=0,emitted=0,bounces=0,
            napX=468,napY=44,napScale=2,charaX=320}
        m.caption={'Chara','Wave10.Intro'}
    elseif m.stage==2 then m.caption={'Nap','Wave10.Nap'}
    elseif m.stage==3 then
        m.vars.attackHits=m.hits
        m.vars.napX,m.vars.napY,m.vars.napScale=W.sourceX,W.sourceY,2
        m.vars.charaX=160
    elseif m.stage==4 then
        m.vars.tears={};m.vars.roundHits=m.hits-m.vars.attackHits
        m.vars.ending=m.vars.roundHits<=1 and 'FewHits' or 'ManyHits'
        m.caption={'Chara','Wave10.'..m.vars.ending}
    elseif m.stage==5 then m.caption={'Nap','Wave10.NapReply'}
    elseif m.stage==6 then m.caption={'Chara','Wave10.Quit'}
    elseif m.stage==7 then m.caption={'Chara','Wave10.Last'} end
end
function W.emit(m)
    local v=m.vars
    for eye=1,2 do
        local t={x=v.napX+(eye==1 and 52 or 82),y=v.napY+(eye==1 and 48 or 58),
            vx=random(v)*10-6.1,vy=4,scale=.8+random(v)*.4,angle=0,active=true,polygon=W.polygon}
        t.oldX,t.oldY=t.x,t.y
        v.tears[#v.tears+1]=t;v.emitted=v.emitted+1
    end
end
function W.stepTear(t)
    -- GM motion: friction reduces the current velocity magnitude, then gravity
    -- adds its downward component. The sprite points along the travel direction.
    t.angle=math.atan2(t.vy,t.vx)-math.pi/2
    local speed=math.sqrt(t.vx*t.vx+t.vy*t.vy)
    local factor=math.max(0,speed-.4)/math.max(speed,1e-9)
    t.vx,t.vy=t.vx*factor,t.vy*factor+.4
    t.x,t.y=t.x+t.vx,t.y+t.vy
end
function W.bounce(t,a)
    local minX,maxX=math.huge,-math.huge
    local maxY=-math.huge
    local vertices=Collision.vertices(t)
    for i=1,#vertices,2 do
        minX=math.min(minX,vertices[i]);maxX=math.max(maxX,vertices[i]);maxY=math.max(maxY,vertices[i+1])
    end
    -- Borders do not extend upwards to the emitter. Only the arena's sides
    -- reflect tears; top-edge crossing while falling is allowed.
    if maxY<a.y-a.h/2 then return false end
    local left,right=a.x-a.w/2,a.x+a.w/2
    if minX<=left and t.vx<0 then t.x=t.x+left-minX;t.vx=-t.vx;return true end
    if maxX>=right and t.vx>0 then t.x=t.x+right-maxX;t.vx=-t.vx;return true end
    return false
end
function W.update(m,dt)
    local v=m.vars
    if m.stage==2 then
        local t=ease(m.phaseTime/.8)
        v.napX=468+(W.sourceX-468)*t
        v.charaX=320-160*t
    elseif m.stage==4 then
        local t=ease(m.phaseTime/.9)
        v.napX=W.sourceX+(468-W.sourceX)*t
        v.charaX=160+160*t
    elseif m.stage==8 then
        v.charaX=320-440*ease(m.phaseTime/1)
        if m.phaseTime>=1 then m:next() end
        return
    end
    if m.stage~=3 then
        if m:dialogueDone() and m.phaseTime>=(m.stage==2 and .8 or m.stage==4 and .9 or .15) then m:next() end
        return
    end
    for _,t in ipairs(v.tears) do t.oldX,t.oldY,t.oldAngle=t.x,t.y,t.angle end
    v.accumulator=v.accumulator+dt
    while v.accumulator+1e-10>=1/30 do
        v.accumulator=v.accumulator-1/30;v.frame=v.frame+1
        if v.frame<=W.frames and v.frame%W.interval==0 then W.emit(m) end
        for i=#v.tears,1,-1 do
            local t=v.tears[i]
            W.stepTear(t)
            if W.bounce(t,m.arena) then v.bounces=v.bounces+1 end
            local minY=math.huge
            local vertices=Collision.vertices(t)
            for j=2,#vertices,2 do minY=math.min(minY,vertices[j]) end
            if minY>m.arena.y+m.arena.h/2 then table.remove(v.tears,i) end
        end
        if v.frame>=W.frames then v.attackDone=true end
    end
    for i=#v.tears,1,-1 do
        if Collision.hits(v.tears[i],m.player) and m:hit(m.config.damage) then
            table.remove(v.tears,i) -- Original parent destroys a tear on damage.
        end
    end
    -- Let the final volley finish its flight before Chara resumes speaking.
    if v.attackDone and #v.tears==0 then m:next();return end
end
return W
