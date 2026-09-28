-- luajit tests/wave09-rules.lua
local P='Scripts.Game.Barrage.'
local Model,Config=require(P..'model'),require(P..'config')
local W,Curtain=require(P..'waves.wave09'),require(P..'curtain-preview')
local Covered=require(P..'waves.wave06').covered
local Knife=require(P..'knife')
assert(W.wallPitch==Knife.pitch())
local function fresh()
    local m=Model.new(9,Config.wave09D());m:enter(2);return m
end
local k={x=300,y=300,angle=0,scale=1,prop=true}
assert(not W.blocks(k,340,300,-1,0),'Tip admits the hat toward the handle')
assert(W.blocks(k,288,300,1,0),'Hat cannot reverse off the point')
assert(W.blocks(k,340,312,-1,0),'Blade body blocks the hat')
assert(W.blocks(k,270,300,1,0),'Handle blocks entry')
local function route(dt,offset)
    local m=fresh()
    W.drape(m,W.layout.switchDrape);m.vars.switched=true
    for _=1,90 do Curtain.updateCloth(m,1/120) end
    m.vars.clock=-1e6 -- Isolate the scenery collision route from the clock shots.
    local h,door=m.vars.hats[1]
    for _,blade in ipairs(m.knives) do if blade.door then door=blade end end
    for _=1,math.ceil(12/dt) do
        local p=m.player
        local ty=W.threads(door,h.x,h.y) and h.y+offset or h.y
        local input={}
        if math.abs(p.y-ty)>1 then input.dy=p.y<ty and 1 or -1 end
        if p.x<h.x+10 then input.dx=1 elseif math.abs(p.y-ty)<=3 then input.dx=-1 end
        m:update(dt,input)
        assert(math.sqrt((h.x-p.x)^2+(h.y-p.y)^2)>=W.hatRadius+W.pushTouch-1e-6,
            'Hat stays solid while pushed')
        if h.x<=235 then break end
    end
    assert(h.x<=235 and Covered(m,h.x,h.y),'Input delivers the hat through the one-way door')
    return m
end
for _,dt in ipairs({1/30,1/120}) do
    local m=route(dt,18)
    assert(m.hits==0,'Off-axis pushing has a safe route')
    m.vars.hour,m.vars.clock=12,W.layout.period
    m:update(dt,{})
    local count,previous=0,nil
    for _,blade in ipairs(m.knives) do if blade.shot then
        count=count+1
        if previous then
            assert(math.abs(blade.vx-previous.vx)<1e-6 and math.abs(blade.vy-previous.vy)<1e-6)
            assert(math.abs(math.sqrt((blade.x-previous.x)^2+(blade.y-previous.y)^2)-W.wallPitch)<1e-6)
        end
        previous=blade
    end end
    assert(count==41,'The closing wall spans the arena with 41 parallel knives')
    for _=1,math.ceil(10/dt) do m:update(dt,{});if m.done then break end end
    assert(m.done and m.hits==0 and m.vars.repelled>0,'Delivered hat shelters the soul from the wall')
    assert(#m.knives==0 and #m.vars.hats==0 and not m.curtain and not m.clothState)
    m:destroy()
end
local naive=route(1/120,0)
assert(naive.hits>0,'Directly following the blade axis still hurts')
naive:destroy()
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
print('[OK] wave09 layout 04: one-way hat, safe/damaging routes, 30/120Hz sheltered wall, clock, side switch, unsolved finish and abort cleanup')
