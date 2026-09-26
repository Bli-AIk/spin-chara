-- Run from the project root: luajit tests/wave07-rules.lua
-- Uses the game model and its wider authored collision outline.
local P='Scripts.Game.Barrage.'
local Model=require(P..'model')
local Config=require(P..'config')
local W=require(P..'waves.wave07')
local V={}
local dt=1/120
local function dist(x,y) return math.sqrt(x*x+y*y) end
local function fresh(index)
    local m=Model.new(7,Config.wave07B()); m:enter(2); return m
end
local function throw(m,number,input)
    m.vars.number=number-1; m.vars.gap=0; m:update(dt,input or {})
    return m.vars.hat
end
local function stream(index)
    local m=fresh(index); throw(m,3)
    -- Isolate the emitter from attraction and further throws.
    m.vars.hat=nil; m.vars.gap=100
    return m
end
local function filled(index)
    local m=stream(index)
    for _=1,360 do m:update(dt,{}) end
    return m
end
local function checkRows(m)
    local sides={{},{},{},{}}
    for _,k in ipairs(m.knives) do
        assert(k.alpha==1 and k.scale==1 and not k.backdrop,'Full-size, opaque, masked blades')
        if k.kind=='orbit' then table.insert(sides[k.side],k.distance) end
    end
    for _,positions in ipairs(sides) do
        table.sort(positions)
        for i=2,#positions do
            assert(math.abs(positions[i]-positions[i-1]-16)<1e-7,'Exact 16px pitch')
        end
    end
    return sides
end
local function emission(index,step)
    local m=stream(index)
    assert(#m.knives==4 and m.vars.emitted==4,'Only the first knife of each row exists initially')
    local initial=m.knives[1]
    local speed=m.config.wave07Profile.orbitSpeed
    local period=16/speed
    local maxCount,previousCount=4,4
    for _=1,math.ceil(8/step) do
        local old={}
        for _,k in ipairs(m.knives) do old[k.id]=k.distance end
        m:update(step,{})
        assert(m.vars.emitted==4*(math.floor((m.vars.rowTime+1e-9)/period)+1),'One blade per side per interval')
        checkRows(m)
        for _,k in ipairs(m.knives) do
            if old[k.id] then assert(math.abs(k.distance-old[k.id]-speed*step)<1e-7,'No wrap or teleport') end
        end
        if m.vars.rowTime<1 then assert(#m.knives>=previousCount,'Entry progressively fills each row') end
        previousCount=#m.knives; maxCount=math.max(maxCount,#m.knives)
    end
    assert(m.vars.retired>0 and m.vars.emitted>maxCount*2 and maxCount<=68,'Bounded stream replenishes while old blades exit')
    assert(initial.distance>initial.exit,'The original blade travels out rather than being recycled')
    m.vars.rowStop=true
    local emitted=m.vars.emitted
    local previous={}
    local lastBySide={}
    for _,k in ipairs(m.knives) do previous[k.id]=k; lastBySide[k.side]=k end
    local lastRetired={}
    for _=1,math.ceil(4/step) do
        local count=#m.knives
        m:update(step,{})
        assert(m.vars.emitted==emitted and #m.knives<=count,'Stop births and let existing knives drain')
        local current={}
        for _,k in ipairs(m.knives) do current[k.id]=k; assert(k.alpha==1,'No end fade') end
        for id,k in pairs(previous) do
            if not current[id] then
                assert(k.distance>k.exit,'Retire only beyond the exit, never clear visible knives')
                lastRetired[k.side]=k
            end
        end
        previous=current
        if m.done then break end
    end
    assert(m.done and #m.knives==0 and m.vars.retired==emitted,'Finish only after the final blade exits')
    for side=1,4 do assert(lastRetired[side]==lastBySide[side],'Last-born knife exits last on each side') end
    m:destroy()
end
local function mechanics(index)
    local signatures={}
    for number=1,6 do
        for _,point in ipairs({{230,240},{320,300},{410,360}}) do
            local m=fresh(index); m.player.x,m.player.y=point[1],point[2]
            local h=throw(m,number)
            local x,y=W.position(m,h,h.aimTime)
            assert(dist(x-h.aimX,y-h.aimY)<1e-6,'Curve intersects the locked prediction')
            assert(h.apexX<180 or h.apexX>460,'Vertex stays outside the arena')
            local referenceTime=m.config.wave07Profile.easeTimes[number]
            assert(h.duration<referenceTime and h.duration>referenceTime*.8,'Shorter tail retains most of the flight time')
            local epsilon=1e-6
            local sx,sy=W.position(m,h,0)
            local ax,ay=W.position(m,h,epsilon)
            local ex,ey=W.position(m,h,h.easeTime)
            local bx,by=W.position(m,h,h.easeTime-epsilon)
            local referenceStart=dist(h.vx,h.vy)*4/(referenceTime*(1-math.exp(-4)))
            local referenceEnd=dist(h.vx,h.vy+h.gravity)*4*math.exp(-4)/(referenceTime*(1-math.exp(-4)))
            assert(math.abs(dist(ax-sx,ay-sy)/epsilon/referenceStart-1)<1e-5,'Keep reference initial speed')
            assert(math.abs(dist(ex-bx,ey-by)/epsilon/referenceEnd-2)<1e-5,'Exactly double reference minimum/exit speed')
            local previousSpeed=math.huge
            local firstSpeed
            for j=1,10 do
                local t=h.duration*j/10
                local xx,yy=W.position(m,h,t)
                local ox,oy=W.position(m,h,t-.001)
                local speed=dist(xx-ox,yy-oy)/.001
                assert(speed<previousSpeed and speed>0,'Out deceleration is continuous without pausing')
                firstSpeed=firstSpeed or speed
                previousSpeed=speed
            end
            assert(firstSpeed/previousSpeed>15,'Large, visible speed contrast throughout the throw')
            local halfway=W.position(m,h,h.duration*.5)
            local progress=(halfway-h.startX)/h.vx
            assert(progress>.82 and progress<.87,'Early travel followed by a long, visible slow exit')
            signatures[h.gravity]=true
            for _=1,360 do m:update(dt,{}); if h.released then break end end
            assert(h.released and m.vars.captures==1,'Every sampled stationary target is captured and released')
            if number<=2 then assert(#m.knives==0 and m.hits==0,'First two hats are harmless') end
            m:destroy()
        end
    end
    local count=0; for _ in pairs(signatures) do count=count+1 end
    assert(count==6,'Six different parabolic curvatures')
    for _,input in ipairs({{dx=1},{dx=-1},{dy=1},{dy=-1}}) do
        local m=fresh(index); local h=throw(m,1,input)
        local lockedX,lockedY=h.aimX,h.aimY
        for _=1,360 do
            m:update(dt,input)
            assert(h.aimX==lockedX and h.aimY==lockedY,'Prediction locks at launch; no homing')
            if h.captured or h.released then break end
        end
        assert(m.vars.captures==1,'Prediction catches continuous cardinal movement')
        m:destroy()
    end
    local m=fresh(index); local h=throw(m,1)
    while not h.captured do m:update(dt,{}) end
    local offset=m.player.x-h.x
    for _=1,8 do m:update(dt,{dx=-h.direction}) end
    assert((m.player.x-h.x-offset)*h.direction<-5,'Player can move inside the hat')
    for _=1,360 do
        local px,py,hx,hy=m.player.x,m.player.y,h.x,h.y
        m:update(dt,{})
        assert(dist(m.player.x-px,m.player.y-py)<=dist(h.x-hx,h.y-hy)+1e-6,'Release adds no teleport')
        if h.released then break end
        assert(dist(m.player.x-h.x,m.player.y-h.y)<=W.innerRadius+1e-6,'Soul stays inside hat disk')
    end
    assert(h.released and m.hits==0,'Natural harmless release')
    m:destroy()
    m=fresh(index)
    local sawProximity=false
    for _=1,120*20 do
        m:update(dt,{})
        for _,k in ipairs(m.knives) do sawProximity=sawProximity or k.proximityClock~=nil end
        if m.done then break end
    end
    assert(sawProximity and m.vars.launched>0,'Full round combines near-tip thrust and magnetic attraction')
    assert(m.done and m.vars.captures==6 and m.vars.releases==6,'Each of six throws re-aims at the current player')
    assert(#m.knives==0 and #m.lights==0 and not m.vars.hat,'Clean end')
    m:destroy()
end
-- Filled streams, centre start: move against the throw and up while held,
-- then wait clear of the crossing blade for 0.6 seconds after release.
local function route(index,number,onFrame)
    local m=filled(index); local h=throw(m,number)
    local r={-1,0,0}
    local warning,flight=false,false
    for _=1,360 do
        m:update(dt,h.captured and {dx=-h.direction,dy=r[1]} or {})
        for _,k in ipairs(m.knives) do
            assert(k.alpha==1,'Warning and launch never fade the blade')
            warning=warning or k.warning; flight=flight or k.kind=='flight'
        end
        if onFrame then onFrame(m,h) end
        if h.released then break end
    end
    assert(h.released and m.vars.launched>0 and warning and flight,'Occupied hat attracts actual warning/flight knives')
    for _=1,72 do m:update(dt,{dx=r[2],dy=r[3]}); if not m.vars.hat then m.vars.gap=100 end end
    assert(m.hits==0 and m.player.hp==20 and not m.context.invincible,'Dodge works through capture AND 0.6 seconds after release')
    m:destroy()
end
local function collision(index)
    local m=filled(index); local h=throw(m,3)
    local damaged=false
    for _=1,360 do
        local before=m.hits
        m:update(dt,h.captured and {dx=h.direction,dy=-1} or {})
        if m.hits>before and h.captured then damaged=true; break end
        if h.released then break end
    end
    assert(damaged and m.player.hp<20,'Moving into an attracted knife while captured hurts')
    m:destroy()
    m=filled(index)
    local bottom
    for _,k in ipairs(m.knives) do if k.side==3 and math.abs(k.x-320)<16 then bottom=k; break end end
    assert(bottom)
    m.player.x,m.player.y=bottom.x,bottom.y-22
    m:update(dt,{})
    assert(m.hits==1 and m.player.hp<20,'Masked border blades keep real collision')
    m:destroy()
    m=filled(index); h=throw(m,3)
    -- Deliberately relocate after launch to isolate empty-hat attraction rules.
    m.player.y=220
    for _=1,90 do m:update(dt,{}); if not m.vars.hat then break end end
    assert(m.vars.captures==0 and m.vars.launched==0,'Empty hats never attract blades')
    m:destroy()
end
local function proximityRule(index,onFrame)
    for side=1,4 do for _,dodge in ipairs({false,true}) do
        local m=filled(index)
        local span=(side==1 or side==3) and m.arena.w or m.arena.h
        local blade
        for _,k in ipairs(m.knives) do
            if k.side==side and k.distance>=-span/2+55 and k.distance<=-span/2+71 then blade=k; break end
        end
        assert(blade)
        local nx,ny=math.cos(blade.angle),math.sin(blade.angle)
        local tx,ty=ny,-nx
        m.player.x,m.player.y=blade.x+44*nx,blade.y+44*ny
        local maximum,warning=0,false
        local previous=blade.distance
        for frame=1,181 do
            -- Follow the row using normal-speed input pulses, or step inward
            -- away from its tip immediately after the warning appears.
            local follow=not dodge and frame<=90 and frame%12~=0 and 1 or 0
            local retreat=((dodge and frame>1 and frame<40)
                or (not dodge and frame>90 and frame<130)) and 1 or 0
            m:update(dt,{dx=tx*follow+nx*retreat,dy=ty*follow+ny*retreat})
            if previous<=blade.exit then
                assert(math.abs(blade.distance-previous-110*dt)<1e-7,'Thrust does not stop the flowing row')
            end
            previous=blade.distance
            maximum=math.max(maximum,blade.stabReach or 0); warning=warning or blade.warning
            assert(blade.alpha==1 and blade.active,'Near-tip warning keeps opacity and collision')
            if frame==1 then assert(blade.proximityClock and blade.warning,'Proximity triggers without a hat') end
            if onFrame then onFrame(m,blade,side,dodge,frame) end
        end
        assert(warning and maximum==28 and blade.stabReach==0,'Individual blade warns, thrusts and retracts')
        assert(not m.vars.hat and m.vars.launched==0,'Near-tip rule is independent of magnetic hats')
        if dodge then assert(m.hits==0 and m.player.hp==20,'Step away from the warned tip without damage')
        else assert(m.hits>0 and m.player.hp<20,'Remaining on the moving blade path causes real damage') end
        m:destroy()
    end end
end
function V.checkLogic()
    assert(W.rowSpacing==require('Scripts.Game.Barrage.config').wave06D().spacing,'Pitch matches main-game round 06')
    for index=2,2 do
        mechanics(index)
        emission(index,dt); emission(index,1/30)
        for number=3,6 do route(index,number) end
        collision(index); proximityRule(index)
        print('[OK] wave07 B: strong Out aim, incremental stream/drain, precise pitch, capture/control/release, dodge and damage, four-side near-tip thrust')
    end
end
V.checkLogic()
-- A blade born late in a frame cannot hit movement that preceded its birth.
local newborn=fresh(2)
newborn.player.x,newborn.player.y=260,300
newborn.context.move=function(p) p.x=340 end
newborn.wave={update=function(m)
    local k=m:knife(300,280,math.pi/2)
    k.active=true; k.birthFraction=.9
end}
newborn:update(dt,{})
assert(newborn.hits==0 and newborn.knives[1].birthFraction==nil,'Only collide during the part of the frame the knife exists')
newborn.wave={update=function() end}
newborn.context.move=function(p) p.x=260 end
newborn:update(dt,{})
assert(newborn.hits==1,'The same blade retains full swept collision on subsequent frames')
newborn:destroy()
print('[OK] birth-frame collision and subsequent-frame damage')
