-- luajit tests/wave09-rules.lua
local P='Scripts.Game.Barrage.'
local Model,Config=require(P..'model'),require(P..'config')
local W,Curtain=require(P..'waves.wave09'),require(P..'curtain-preview')
local Covered=require(P..'waves.wave06').covered
local Knife=require(P..'knife')
assert(W.wallPitch==Knife.pitch())
local function fresh()
    local m=Model.new(9,Config.wave09D())
    -- Rule fixtures start at the end of the box entrance; engine tests exercise
    -- the complete resize/carry/expand sequence with the real soul.
    m.player.x,m.player.y=455,340
    m:enter(2)
    assert(m.player.x==455 and m.player.y==340, 'Scene entry preserves the soul position')
    while m.vars.sceneEntry do m:update(1/120,{}) end
    return m
end
-- The box can deliver the soul onto or beside the authored hat location.
-- Cover exact overlap and every approach direction, at both frame rates.
for _,dt in ipairs({1/30,1/120}) do
    for _,distance in ipairs({0,12,29,32}) do
        for direction=0,7 do
            local angle=direction*math.pi/4
            local x,y=430+math.cos(angle)*distance,300+math.sin(angle)*distance
            local m=Model.new(9,Config.wave09D())
            m.player.x,m.player.y=x,y
            m:enter(2)
            assert(m.player.x==x and m.player.y==y,'Spawning the hat never moves the soul')
            local h=m.vars.hats[1]
            assert(math.sqrt((h.x-x)^2+(h.y-y)^2)>=W.hatRadius+W.pushTouch,
                'Hat enters clear of the real soul position')
            while m.vars.sceneEntry do
                m:update(dt,{})
                assert(math.abs(m.player.x-x)<1e-8 and math.abs(m.player.y-y)<1e-8,
                    'Idle soul does not get ejected by entering scenery')
            end
            m:destroy()
        end
    end
end
local k={x=300,y=300,angle=0,scale=1,prop=true}
assert(not W.blocks(k,340,300,-1,0),'Tip admits the hat toward the handle')
assert(W.blocks(k,288,300,1,0),'Hat cannot reverse off the point')
assert(W.blocks(k,340,312,-1,0),'Blade body blocks the hat')
assert(W.blocks(k,270,300,1,0),'Handle blocks entry')
local function pushFixture()
    local m=fresh()
    m.knives={};m.vars.clock=-1e6
    local h=m.vars.hats[1]
    h.x,h.y,h.angle=380,300,0
    m.player.x,m.player.y=412,300
    return m,h
end
local function drivenRotation(degrees,speed)
    local angle=math.rad(degrees)
    local omega,total=0,0
    for _=1,240 do
        local turn
        turn,omega=W.pushRotation(omega,speed*math.cos(angle),speed*math.sin(angle),32,1/240)
        total=total+turn
    end
    return total,omega
end
do
    local headOn=drivenRotation(0,120)
    local shallow=drivenRotation(15,120)
    local oblique,omega=drivenRotation(45,120)
    local grazing=drivenRotation(85,120)
    assert(headOn==0 and shallow>0 and oblique>shallow and grazing<shallow,
        'Pressure and slip yield no head-on spin and reduced grazing torque')
    assert(math.abs(drivenRotation(-45,120)+oblique)<1e-8,
        'Mirrored force directions produce mirrored angular displacement')
    assert(math.abs(drivenRotation(45,60)*2-oblique)<1e-8,
        'A slower push supplies proportionally less rotation')
    local inertia=W.hatInertiaFactor
    W.hatInertiaFactor=inertia*4
    local heavy=drivenRotation(45,120)
    W.hatInertiaFactor=inertia
    assert(heavy<oblique,'Greater rotational inertia resists the same push')
    local _,nextOmega=W.pushRotation(omega,85,-85,32,1/240)
    assert(nextOmega>0 and nextOmega<omega,'Reversing input brakes angular momentum before reversing it')
    for _=1,240 do _,nextOmega=W.pushRotation(nextOmega,85,-85,32,1/240) end
    assert(nextOmega<0,'Sustained opposite input reverses the rotation')
    local turn,stopped=W.pushRotation(omega,0,100,32,1/240)
    assert(turn==0 and stopped==0,'Detached grazing cannot rotate or store momentum')
end
do
    local reference
    for _,fps in ipairs({30,60,120,144}) do
        local m,h=pushFixture()
        for _=1,fps/2 do m:update(1/fps,{dx=-1,dy=.5}) end
        if reference then
            assert(math.sqrt((h.x-reference.x)^2+(h.y-reference.y)^2)<.5
                and math.abs(h.angle-reference.angle)<math.rad(1),
                'Frame-rate changes preserve the contact path within half a pixel and one degree')
        else reference={x=h.x,y=h.y,angle=h.angle} end
        m:destroy()
    end
end
for _,dt in ipairs({1/30,1/120}) do
    local m,h=pushFixture()
    for _=1,math.ceil(.2/dt) do m:update(dt,{dx=-1}) end
    assert(h.x<380 and math.abs(h.y-300)<1e-8 and h.angle==0,
        'A centred push translates without spinning')
    m:destroy()
    local offsets={}
    for _,side in ipairs({-1,1}) do
        m,h=pushFixture()
        for _=1,math.ceil(.2/dt) do m:update(dt,{dx=-1,dy=side}) end
        assert(h.angle*side<0 and (h.y-300)*side>0,
            'A sideways push turns both the hat artwork and its physical centre')
        assert(math.abs(math.sqrt((h.x-m.player.x)^2+(h.y-m.player.y)^2)
            -W.hatRadius-W.pushTouch)<1e-6,'Turning preserves contact with the soul')
        offsets[side]=h.y-300
        local x,y,angle=h.x,h.y,h.angle
        for _=1,10 do m:update(dt,{}) end
        assert(math.abs(h.x-x)+math.abs(h.y-y)+math.abs(h.angle-angle)<1e-8,
            'Releasing the push stops the hat without snapping its angle')
        m:destroy()
    end
    assert(math.abs(offsets[-1]+offsets[1])<1e-6,'Mirrored pushes turn in opposite directions')
end
do
    local m,h=pushFixture()
    h.x,h.y=432,300
    local px,py=400,300
    W.rotateHat(m,h,px,py,math.pi/4)
    assert(math.abs(h.x-(px+32/math.sqrt(2)))<1e-6
        and math.abs(h.y-(py+32/math.sqrt(2)))<1e-6
        and math.abs(h.angle-math.pi/4)<1e-6,
        'The whole hat rotates about the player pivot, not its own centre')
    assert(m.player.x==412 and m.player.y==300,'Rotation never repositions the soul')
    h.x,h.y,h.angle=400,300,0
    m.knives={{x=395,y=335,angle=0,prop=true}}
    W.rotateHat(m,h,368,300,math.pi/2)
    assert(h.angle>0 and h.angle<math.pi/2 and W.free(m,h.x,h.y,0,0),
        'The swept rotation stops at a blade instead of crossing it')
    m.knives={};h.x,h.y,h.angle=432,369,0
    W.rotateHat(m,h,400,369,math.pi/4)
    assert(h.x==432 and h.y==369 and h.angle==0,'The arena edge blocks outward rotation')
    m:destroy()
end
local function route(dt)
    local m=fresh()
    W.drape(m,W.layout.switchDrape);m.vars.switched=true
    for _=1,90 do Curtain.updateCloth(m,1/120) end
    m.vars.clock=-1e6 -- Isolate the scenery collision route from the clock shots.
    local h=m.vars.hats[1]
    assert(#m.knives==2, "Only the upper and lower scenery knives remain")
    for _,blade in ipairs(m.knives) do
        assert(math.abs(math.cos(blade.angle))<1e-6, "Scenery knives stand vertically")
    end
    local aligned=false
    for _=1,math.ceil(12/dt) do
        local p=m.player
        local ty=h.y
        local input={}
        if not aligned then
            -- Walk clear of the brim before aligning; rubbing along it now
            -- deliberately turns the prop around the soul.
            if p.x<h.x+W.hatRadius+W.pushTouch+3 then input.dx=1
            elseif math.abs(p.y-ty)>1 then input.dy=p.y<ty and 1 or -1
            else aligned=true end
        else
            input.dx=-1
            if math.abs(p.y-ty)>.5 then input.dy=p.y<ty and 1 or -1 end
        end
        m:update(dt,input)
        assert(math.sqrt((h.x-p.x)^2+(h.y-p.y)^2)>=W.hatRadius+W.pushTouch-1e-6,
            'Hat stays solid while pushed')
        if h.x<=235 then break end
    end
    assert(h.x<=235 and Covered(m,h.x,h.y),'Input delivers the hat through the central opening')
    return m
end
for _,dt in ipairs({1/30,1/120}) do
    local m=route(dt)
    assert(m.hits==0,'The central opening has a safe route')
    m.vars.hour,m.vars.clock=12,W.layout.period
    m:update(dt,{})
    local count,previous=0,nil
    assert(not m.vars.wallLaunched, 'Wall first enters without launching')
    for _,blade in ipairs(m.knives) do if blade.shot then
        count=count+1
        assert(blade.wallEntry and not blade.active and blade.alpha<1, "Entering wall cannot hurt")
        if previous then
            assert(math.abs(blade.vx-previous.vx)<1e-6 and math.abs(blade.vy-previous.vy)<1e-6)
            assert(math.abs(math.sqrt((blade.wallEntry.x-previous.wallEntry.x)^2+(blade.wallEntry.y-previous.wallEntry.y)^2)-W.wallPitch)<1e-6)
        end
        previous=blade
    end end
    assert(count==41,'The closing wall spans the arena with 41 parallel knives')
    for _=1,math.ceil((W.wallEnter+W.wallStagger+W.wallHold)/dt) do
        m:update(dt,{})
        if m.vars.wallLaunched then break end
    end
    assert(m.vars.wallLaunched, 'Wall launches after assembling')
    for _,blade in ipairs(m.knives) do if blade.shot then
        assert(blade.active and blade.alpha==1 and not blade.wallEntry)
    end end
    for _=1,math.ceil(10/dt) do m:update(dt,{});if m.done then break end end
    assert(m.done and m.hits==0 and m.vars.repelled>0,'Delivered hat shelters the soul from the wall')
    assert(#m.knives==0 and #m.vars.hats==0 and not m.curtain and not m.clothState)
    m:destroy()
end
local contact=fresh()
local top=contact.knives[1]
contact.player.x,contact.player.y=top.x,top.y+20
contact:update(1/120,{})
assert(contact.hits>0,'Vertical scenery knives retain damage')
contact:destroy()
local function clock(slow)
    local m=fresh()
    for _=1,240 do m:update(1/120,{slow=slow}) end
    local hour=m.vars.hour;m:destroy();return hour
end
assert(clock(true)<clock(false),'X slows the attack clock')
local m=fresh()
local right,pulling,left=false,false,false
for _=1,60*35 do
    m:update(1/60,{})
    if not m.vars.switched and m.clothState then
        assert(Covered(m,430,300) and not Covered(m,220,300));right=true
    elseif m.vars.switched=='pulling' then
        assert(m.vars.hour>=6 and m.clothTransition.kind=='exit');pulling=true
    elseif m.vars.switched==true and m.clothState and m.clothTransition.time>Curtain.ENTER_TIME then
        if not m.vars.exit then assert(Covered(m,220,300) and not Covered(m,430,300));left=true end
    end
    if m.done then break end
end
assert(right and pulling and left and m.done and m.vars.fired==12 and m.vars.wallFired)
assert(m.hits>0,'Leaving the hat on the right gives no shelter from the finale')
m:destroy()
local aborted=fresh();aborted:update(1/60,{});aborted:destroy()
assert(not aborted.vars.hats and not aborted.clothState and not aborted.clothRect
    and not aborted.clothTransition and not aborted.curtain and not aborted.ambient
    and #aborted.knives==0 and #aborted.lights==0)
print('[OK] wave09 layout 04: one-way hat, open central route, vertical blade damage, staged 30/120Hz sheltered wall, clock, side switch, unsolved finish and abort cleanup')
