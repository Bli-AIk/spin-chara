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
    for _=1,math.ceil(12/dt) do
        local p=m.player
        local ty=h.y
        local input={}
        if math.abs(p.y-ty)>1 then input.dy=p.y<ty and 1 or -1 end
        if p.x<h.x+10 then input.dx=1 elseif math.abs(p.y-ty)<=3 then input.dx=-1 end
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
