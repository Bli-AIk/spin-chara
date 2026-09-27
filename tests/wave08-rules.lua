-- Run from the project root: luajit tests/wave08-rules.lua
local P='Scripts.Game.Barrage.'
local Model=require(P..'model')
local Config=require(P..'config')
local W=require(P..'waves.wave08')
local Curtain=require(P..'curtain-preview')
local Knife=require(P..'knife')
assert(W.rowSpacing==Knife.pitch(),'Use the engine blade pitch')
local function fresh()
    local m=Model.new(8,Config.wave08C());m:enter(2);return m
end
local function route(disabled,dt)
    local m=fresh();m.vars.number=6;m.vars.gap=0;m.curtain=true;m.dark=true
    Curtain.applyAdopted(m);Curtain.updateCloth(m,0)
    local radius=W.repelRadius
    if disabled then W.repelRadius=0 end
    local repelledEmpty=false
    for _=1,math.ceil(20/dt) do
        local v=m.vars;local before=v.repelled
        local input={}
        if v.mode=='dense' and not v.hatThrown and v.clock>W.hatAt-.10 then input.dy=-1 end
        m:update(dt,input)
        if v.repelled>before and v.hat and not v.hat.captured then repelledEmpty=true end
        if m.done then break end
    end
    W.repelRadius=radius
    assert(m.done and m.vars.denseLaunched==2 and m.vars.captures==0 and #m.knives==0)
    if disabled then assert(m.hits>0,'The same route takes damage without repulsion')
    else assert(m.hits==0 and repelledEmpty,'Empty hat provides a real route') end
    m:destroy()
end
for _,dt in ipairs({1/30,1/120}) do route(false,dt) end
route(true,1/120)
local m=fresh();m.vars.gap=0
for _=1,120*45 do m:update(1/120,{});if m.done then break end end
assert(m.done and m.vars.number==8 and m.vars.normalLaunched==18 and m.vars.underAimed==2 and m.vars.denseLaunched==2)
assert(not m.curtain and not m.clothState and #m.knives==0 and not m.vars.hat)
m:destroy()
print('[OK] wave08 C rules: 16px pitch, 30/120Hz empty-hat route, negative damage control, all eight waves and cleanup')
