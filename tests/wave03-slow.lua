-- Run from the project root: luajit tests/wave03-slow.lua
-- Round 3's blades run at normalSpeedMultiplier, and holding X in the dark drops
-- them to slowFactor. That slow speed is deliberately doubled, so this pins the
-- two rates the ring stage advances knifeTime at.
package.path = package.path .. ";./?/init.lua"

local prefix = "Scripts.Game.Barrage."
local Config = require(prefix .. "config")
local Wave = require(prefix .. "waves.wave03")

local config = Config.defaults(3) -- the preset round 3 uses
assert(config.label:sub(1, 1) == "C", "Round 3 must keep its preset")
assert(Wave.slowMultiplier == 2, "The slow rate must be doubled")

local function makeModel(slow)
    return {
        stage = 4,
        slow = slow,
        config = config,
        phaseTime = 0,
        arena = {x = 320, y = 315, w = 454, h = 156},
        otherArena = {x = 320, y = 315, w = 454, h = 156},
        lights = {{x = 320, y = 315, r = 38}},
        knives = {}, -- The ring itself is not what this test is about.
        player = {x = 320, y = 315},
        vars = {
            knifeTime = 0, squeezeTime = 0,
            squeezeDuration = 10, knifeClearTime = 10,
            squeezeBounds = {left = 93, right = 547, top = 237, bottom = 393},
            squeezeEdge = "left",
        },
        dialogueDone = function() return true end,
        next = function() end,
    }
end

local step = 1 / 60

local normal = makeModel(false)
Wave.update(normal, step)
assert(math.abs(normal.vars.knifeTime - step * Wave.normalSpeedMultiplier) < 1e-9,
    "Unslowed blades must advance at the normal multiplier")

local slowed = makeModel(true)
Wave.update(slowed, step)
local want = step * config.slowFactor * Wave.slowMultiplier
assert(math.abs(slowed.vars.knifeTime - want) < 1e-9,
    "Slowed blades must advance at twice the configured slow factor")

-- Half the speed the unscaled slow factor would give, and well under normal.
assert(want > step * config.slowFactor, "The slow must actually be faster than before")
assert(want < step * Wave.normalSpeedMultiplier, "Slowed blades must still be slower than normal")

print(string.format("PASS: round 3 knife rate %.3fx normal, %.3fx while slowed with X",
    Wave.normalSpeedMultiplier, config.slowFactor * Wave.slowMultiplier))
