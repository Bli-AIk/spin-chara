-- Run from the project root: luajit tests/knife-punish.lua
-- The barrage's knives ask for a shorter invincibility than a normal hit. While
-- the regular one is still counting down after that gate has already opened, any
-- further damage costs extra. This pins the window down.
package.path = package.path .. ";./?/init.lua"

Controller = {GetState = function() return 0 end}
Global = {SetVariable = function() end}
Scenes = {switchTo = function() end}
Collisions = {}
Sprites = {images = {}, CreateSprite = function() return {MoveTo = function() end} end}
Battle = {state = "ACTIONSELECT"}

local Player = require("Scripts.Libraries.Battle.Player")

local REGULAR = 60  -- Player.Hurt's default gate
local KNIFE = 30    -- config.lua hurtTime, the barrage's shorter gate
local HIT = 3       -- config.lua damage
local PUNISH = 2    -- config.lua punishDamage

local function knifeHit() Player.Hurt(HIT, KNIFE, nil, PUNISH) end
local function frames(n) for _ = 1, n do Player.Update(1 / 60) end end

-- A lone knife hit costs its own damage and opens both windows.
Player.maxhp, Player.hp = 20, 20
knifeHit()
assert(Player.hp == 17, "A knife hit must cost 3")
assert(Player.hurt_time == KNIFE, "The knife must grant the shorter gate")
assert(Player.hurt_regular == REGULAR, "The regular invincibility must still run")
assert(Player.hurt_punish == PUNISH and Player.hurt_serial == 1)
assert(Player.hurt_from == 1, "The bar needs the pre-hit fraction")

-- The gate opens well before the regular window closes: that gap is the window.
frames(KNIFE)
assert(Player.hurt_time == 0, "The knife's gate must be open by now")
assert(Player.hurt_regular == REGULAR - KNIFE, "The regular window must still be running")

-- Anything landing in the gap costs its own damage plus the extra 2.
knifeHit()
assert(Player.hp == 12, "A hit inside the gap must cost 3 + 2")
assert(Player.hurt_regular == REGULAR, "The follow-up must restart the regular window")

-- And the window reopens behind that hit, so a third one is charged too.
frames(KNIFE)
assert(Player.hurt_time == 0 and Player.hurt_regular == REGULAR - KNIFE)
knifeHit()
assert(Player.hp == 7, "The window must reopen behind a follow-up")

-- Once the regular window has run out, a knife hit is a fresh hit again.
Player.maxhp, Player.hp = 20, 20
knifeHit()
frames(REGULAR)
assert(Player.hurt_regular == 0 and Player.hurt_time == 0)
knifeHit()
assert(Player.hp == 14, "Past the regular window a knife hit must cost only 3")

-- Ordinary damage never opens a window of its own.
Player.maxhp, Player.hp = 20, 20
Player.Hurt(HIT)
assert(Player.hurt_punish == 0, "Ordinary damage must not arm a punish")
assert(Player.hurt_regular == Player.hurt_time,
    "Without a shorter gate there is no gap to punish")
Player.Hurt(HIT) -- still inside the gate
assert(Player.hp == 14, "A hit inside the gate must cost its own damage only")
frames(REGULAR)
assert(Player.hurt_regular == 0, "The regular window must run out")

-- A source that only passes a custom gate (the blue soul's slam) is not armed
-- either, so it can not punish the player for landing a second slam.
Player.maxhp, Player.hp = 20, 20
Player.Hurt(5, 20)
assert(Player.hurt_punish == 0 and Player.hurt_regular == REGULAR)
frames(20)
assert(Player.hurt_time == 0 and Player.hurt_regular == REGULAR - 20)
Player.Hurt(5, 20)
assert(Player.hp == 10, "An unarmed window must not charge extra")

frames(REGULAR)
Player.hp = 20
knifeHit()
frames(KNIFE)
Player.Heal(1)
Player.Hurt(1)
assert(Player.hp == 15, "Any damage in the knife gap must add 2, even after healing")
frames(REGULAR)
Player.hp = 20
knifeHit()
frames(REGULAR)
Player.Hurt(1)
assert(Player.hp == 16, "The exact regular-window boundary must not add damage")

print("PASS: knife gate, follow-up window, chaining, healing and ordinary damage")
