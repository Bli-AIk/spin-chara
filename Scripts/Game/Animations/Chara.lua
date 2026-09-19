-- Chara animation factory.
--
-- This module is a FACTORY: `require` returns the module once (Lua caches it
-- in `package.loaded`), so `New(...)` is the only way to get a usable anim.
-- Every enemy gets its OWN instance (own sprite + own state) by calling
-- `New(pos)`, which means two enemies of the same type no longer share a
-- single `anim` table — updating or destroying one can't touch the other.

local CharaAnim = {}
CharaAnim.__index = CharaAnim

-- Create a brand-new, independent Chara animation instance.
function CharaAnim.New(pos)
    local self = setmetatable({}, CharaAnim)

    self.running = true
    self.x = 0
    self.y = 0
    self.elements = {}

    self.hurting = false
    self.hurttime = 0
    self.intensity = 16

    self:Init(pos)
    return self
end

-- Create the sprites.
function CharaAnim:Init(pos)
    local _pos = (pos or {320, 140})
    local chara = Sprites.CreateSprite("chara.png", "UI")
    chara:MoveTo(_pos[1], _pos[2])

    self.cpos = {chara.x, chara.y}
    self.chara = chara
end

function CharaAnim:Hurt()
    if (not self.chara) then
        return
    end
    self.hurting = true
    self.intensity = 16
end

function CharaAnim:Spare()
    if (not self.chara) then
        return
    end

    self.chara.alpha = 0.5
end

local function swing()
    
end

function CharaAnim:Update(dt)
    if (not self.running) then
        return
    end

    -- Put your monster's animation code here.
    --===================>
    if (self.hurting) then
        local p = self.chara
        p.x = self.cpos[1] + self.intensity
        if (self.intensity > 0) then self.intensity = self.intensity - 1; self.intensity = -self.intensity
        elseif (self.intensity < 0) then self.intensity = -self.intensity end
    end
    --<===================
end

-- Destroy the anim.
-- You can also use `sprite:Dust` function here.
function CharaAnim:Destroy()
    if (not self.chara) then
        return
    end

    local _flag = Global.GetVariable("FLAG_KILLING_COUNTER")
    if (_flag) then
        FLAG[_flag] = FLAG[_flag] + 1
    end

    self.chara:Dust(true, true)
    for i = #self.elements, 1, -1
    do
        local e = self.elements[i]
        if (e.Destroy) then
            e:Destroy()
        end
    end
end

return CharaAnim
