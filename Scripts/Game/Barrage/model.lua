local prefix = (...):match("(.-)[^%.]+$")
local Knife = require(prefix .. "knife")
local Lighting = require(prefix .. "lighting")
local Model = {}
Model.__index = Model
local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}; for k,v in pairs(t) do out[k] = copy(v) end; return out
end
Model.copy = copy
function Model.new(round, config, context)
    local self = setmetatable({round=round, lightStyle=Lighting.ADOPTED_STYLE,
        config=copy(config), context=context or {},
        player={x=320,y=330,hp=20,hurt=0}, lights={}, knives={}, vars={},
        elapsed=0,hits=0,stage=0,dark=true,curtain=false,done=false}, Model)
    self.wave = require(prefix .. "waves.wave0" .. round)
    self.arena = copy(self.wave.arena)
    self.player.x, self.player.y = self.arena.x, self.arena.y
    self:enter(1)
    return self
end
function Model:enter(stage)
    if stage > #self.wave.stages then self.done=true; self.knives={}; return end
    self.stage, self.phaseTime, self.attackTime = stage, 0, 0
    self.pending, self.knives, self.caption = false, {}, nil
    self.checkpoint = copy({arena=self.arena,otherArena=self.otherArena,player=self.player,vars=self.vars,
        lights=self.lights,dark=self.dark,curtain=self.curtain,clothTransition=self.clothTransition,elapsed=self.elapsed})
    self.wave.enter(self)
    self.player.oldX, self.player.oldY = self.player.x, self.player.y
    if self.context.enter then self.context.enter(self) end
end
function Model:retry(config)
    if self.clothState then self.clothState:destroy(); self.clothState=nil end
    local s = self.checkpoint
    for _, key in ipairs({"arena","otherArena","player","vars","lights","dark","curtain","clothTransition","elapsed"}) do self[key]=copy(s[key]) end
    if config then self.config=copy(config) end
    self.done, self.hits, self.player.hp, self.player.hurt = false, 0, 20, 0
    self:enter(self.stage)
end
function Model:knife(x,y,angle,scale)
    local k={x=x,y=y,angle=angle or 0,scale=scale or .7,active=false}
    self.knives[#self.knives+1]=k
    return k
end
function Model:lit(x,y)
    for _, l in ipairs(self.lights) do
        if (x-l.x)^2+(y-l.y)^2 <= l.r^2 then return true end
    end
    return false
end
function Model:hit()
    if self.player.hurt > 0 then return false end
    self.hits=self.hits+1
    -- Recording/debug: still count the contact, but never damage, blink or cry
    -- out. The gate has to sit before `hurt` is set: the renderer reads that
    -- field to pick the soul's alpha, so leaving it set would pin the heart at
    -- 0.4 opacity for as long as it stays inside the knife field.
    if self.context.invincible then return true end
    self.player.hp=math.max(0,self.player.hp-self.config.damage)
    self.player.hurt=1
    if self.context.hit then self.context.hit(self) end
    return true
end
function Model:next() self.pending=true end
function Model:dialogueDone()
    return not self.context.dialogueDone or self.context.dialogueDone(self)
end
function Model:update(dt,input)
    if self.done or (self.context.mortal and self.player.hp <= 0) then return end
    input=input or {}
    local p=self.player
    p.oldX,p.oldY=p.x,p.y
    p.hurt=math.max(0,p.hurt-dt)
    if self.context.move then self.context.move(p,input,dt)
    else
        local speed=input.slow and 60 or 120
        p.x=p.x+(input.dx or 0)*speed*dt; p.y=p.y+(input.dy or 0)*speed*dt
    end
    local a=self.arena
    p.x=math.max(a.x-a.w/2+8, math.min(a.x+a.w/2-8,p.x))
    p.y=math.max(a.y-a.h/2+8, math.min(a.y+a.h/2-8,p.y))
    self.elapsed,self.phaseTime=self.elapsed+dt,self.phaseTime+dt
    if self.wave.lighting then self.wave.lighting(self,dt) end
    self.slow=self.round>=3 and self.dark and input.slow and not self:lit(p.x,p.y)
    local bulletDt=dt*(self.slow and self.config.slowFactor or 1)
    self.attackTime=self.attackTime+bulletDt
    for _,k in ipairs(self.knives) do k.oldX,k.oldY,k.oldAngle=k.x,k.y,k.angle end
    self.wave.update(self,dt,bulletDt)
    a=self.arena
    p.x=math.max(a.x-a.w/2+8, math.min(a.x+a.w/2-8,p.x))
    p.y=math.max(a.y-a.h/2+8, math.min(a.y+a.h/2-8,p.y))
    if p.hurt<=0 then
        for _,k in ipairs(self.knives) do
            if Knife.hits(k,p) then self:hit(); break end
        end
    end
    if self.curtain then require(prefix.."curtain-preview").updateCloth(self,dt) end
    if self.context.update then self.context.update(self,dt) end
    if self.pending then self:enter(self.stage+1) end
end
function Model:destroy()
    if self.clothState then self.clothState:destroy(); self.clothState=nil end
    self.knives,self.lights,self.caption={},{},nil
    if self.context.destroy then self.context.destroy(self) end
    self.done=true
end
return Model
