-- Chara animation factory.
--
-- This module is a FACTORY: `require` returns the module once (Lua caches it
-- in `package.loaded`), so `New(...)` is the only way to get a usable anim.
-- Every enemy gets its OWN instance (own sprite + own state) by calling
-- `New(pos)`, which means two enemies of the same type no longer share a
-- single `anim` table — updating or destroying one can't touch the other.

local CharaAnim = {}
CharaAnim.__index = CharaAnim

-- Dodge tuning, in FRAMES, like every other duration in this codebase.
-- Total = DODGE_OUT + DODGE_HOLD + DODGE_BACK = 30 frames (~0.5 s at 60 fps),
-- which is exactly when stick.lua's miss path calls Destroy() (time == 30).
local DODGE_OUT  = 10 -- slide left
local DODGE_HOLD = 6  -- parked at the far left
local DODGE_BACK = 14 -- slide home
local DODGE_DIST = 48 -- pixels to the left (~30% of chara.png's 162px width)

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

    -- Dodge state (see Dodge() / UpdateDodge()). The dodge is a hand-rolled
    -- frame counter rather than a Tween: Tween.Update runs BEFORE the enemy
    -- animation loop in main.lua, so a tween written here would be overwritten
    -- by this very file's hurt shake, and Tween has no cancel/complete hook for
    -- a dodge that gets re-triggered mid-slide.
    self.dodging = false
    self.dodge_time = 0
    self.dodge_from = 0

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

---Slide out of the way, hold, then slide back home. Called from OnAttack() when
---the incoming strike is resolved as a miss. Safe to call at any time: a second
---call mid-slide reuses the current x as the new starting point, so it extends
---the dodge instead of snapping.
function CharaAnim:Dodge()
    if (not self.chara) then
        return
    end

    -- The hurt shake below also writes chara.x; the dodge owns the sprite.
    self.hurting = false
    self.dodge_from = self.chara.x or self.cpos[1]
    self.dodging = true
    self.dodge_time = 0
end

---Called by the attack pattern the moment a strike is LAUNCHED at this enemy.
---A strike flagged as a miss makes this enemy slide out of the way; a real hit
---is left to Hurt() and the damage path in stick.lua.
function CharaAnim:OnAttack(data)
    if (type(data) == "table" and data.miss) then
        self:Dodge()
    end
end

---Advance the dodge timeline. Stepped at the END of Update so the dodge is the
---last writer of chara.x in any given frame.
function CharaAnim:UpdateDodge()
    if (not self.dodging) then
        return
    end
    if (not self.chara) then
        self.dodging = false
        return
    end

    self.dodge_time = self.dodge_time + 1
    local t = self.dodge_time
    local rest = self.cpos[1]
    local far = self.cpos[1] - DODGE_DIST
    local x

    if (t <= DODGE_OUT) then
        -- quad-out: snap away from the slice, then settle.
        local p = t / DODGE_OUT
        local e = 1 - (1 - p) * (1 - p)
        x = self.dodge_from + (far - self.dodge_from) * e
    elseif (t <= DODGE_OUT + DODGE_HOLD) then
        x = far
    elseif (t <= DODGE_OUT + DODGE_HOLD + DODGE_BACK) then
        -- smoothstep: eased at both ends, so the return has no velocity jump.
        local p = (t - DODGE_OUT - DODGE_HOLD) / DODGE_BACK
        local e = p * p * (3 - 2 * p)
        x = far + (rest - far) * e
    else
        -- Parked back home; cpos[1] is the base, so nothing drifts.
        x = rest
        self.dodging = false
    end

    self.chara.x = x
end

local function swing()

end

function CharaAnim:Update(dt)
    if (not self.running) then
        return
    end
    if (not self.chara) then
        return
    end

    -- Put your monster's animation code here.
    --===================>
    if (self.hurting) then
        local p = self.chara
        p.x = self.cpos[1] + self.intensity
        if (self.intensity > 0) then self.intensity = self.intensity - 1; self.intensity = -self.intensity
        elseif (self.intensity < 0) then self.intensity = -self.intensity
        else self.hurting = false end
    end
    --<===================

    -- Stepped LAST: while a dodge is active it must be the final writer of
    -- chara.x, otherwise the hurt shake above would pin the sprite to cpos[1].
    self:UpdateDodge()
end

-- Destroy the anim.
-- You can also use `sprite:Dust` function here.
function CharaAnim:Destroy()
    if (not self.chara) then
        return
    end

    -- A scene teardown mid-dodge must not leave the flag set.
    self.dodging = false

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
