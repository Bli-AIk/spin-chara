-- Run from the project root: luajit tests/knife-rows.lua
-- A row of blades has to be a wall: whatever position the engine's clamp lets
-- the soul hold, some blade of that row must be able to reach it. The pitch and
-- the collision outline in knife.lua are what keep that true together, and a
-- row laid out by dividing its span between blades (instead of stepping on the
-- pitch from a known end) is what lets one stop short of a wall and leave a
-- strip to stand in. This drives the real models and the real swept collision.
package.path = package.path .. ";./?/init.lua"
-- Round 2 picks its fan direction with love.math.random; keep it reproducible.
math.randomseed(73)
love = {math = {random = function(a, b)
    if a == nil then return math.random() end
    return math.random(a, b)
end}}
local prefix = "Scripts.Game.Barrage."
local Config = require(prefix .. "config")
local Knife = require(prefix .. "knife")
local Model = require(prefix .. "model")

-- Stages that field a row of blades as a wall. Round 3's opening sweep is not
-- one: it deliberately leaves the frame's edges clear.
local ROWS = {[2] = {[3]=true, [4]=true, [5]=true, [6]=true, [7]=true},
    [3] = {[5]=true},
    [4] = {[4]=true, [6]=true, [8]=true, [11]=true, [13]=true, [15]=true},
    [5] = {[1]=true, [2]=true, [3]=true, [4]=true, [5]=true}}
local PRESETS = {[2] = 3, [3] = 3, [4] = 4, [5] = 1}

local function build(round)
    local config = round == 3 and Config.wave03A() or Config.defaults(PRESETS[round])
    return Model.new(round, config, {
        dialogueDone = function() return true end,
        move = function(p) p.x, p.y = p.x, p.y end, -- the soul holds still
    })
end

local function lit(m, x)
    for _, l in ipairs(m.lights) do
        if math.abs(x - l.x) < l.r + 12 then return true end
    end
    return false
end

-- Sample the soul across the strip the row spans (the engine clamps it 8px
-- clear of each wall, as model.lua does) at the row's own depth. The launch
-- stagger leaves some blades inactive for a moment and an inactive blade still
-- occupies its place, so activity is ignored: this is about the laid-out row.
local function openPositions(m, exempt)
    local a = m.arena
    local blades, sideways = {}, nil
    for _, k in ipairs(m.knives) do
        if not k.backdrop then
            local flat = math.abs(math.cos(k.angle)) > .5
            sideways = sideways == nil and flat or sideways
            if flat == sideways then blades[#blades+1] = k end
        end
    end
    if #blades == 0 then return 0, nil end
    local lo, hi, fixed
    if sideways then -- blades point sideways: the row runs across y
        lo, hi = a.y - a.h/2 + 8, a.y + a.h/2 - 8
        fixed = blades[1].x
    else
        lo, hi = a.x - a.w/2 + 8, a.x + a.w/2 - 8
        fixed = blades[1].y
    end
    local found, first = 0, nil
    for p = lo, hi, 0.25 do
        local covered = false
        for _, k in ipairs(blades) do
            local probe = sideways and {x = k.x, y = p} or {x = p, y = k.y}
            local was = k.active
            k.active = true
            covered = Knife.hits(k, probe)
            k.active = was
            if covered then break end
        end
        local absolute = sideways and fixed or p
        if not covered and not (exempt and exempt(m, absolute)) then
            found = found + 1
            first = first or absolute
        end
    end
    return found, first
end

-- After the cloth round 4 inverts: the blades belong inside the light, and the
-- shadow beside it is the refuge, so what has to hold is that no blade's width
-- reaches past the light's own edge.
local function leaks(m)
    local found, first = 0, nil
    for _, k in ipairs(m.knives) do
        for _, l in ipairs(m.lights) do
            local far = math.max(math.abs(k.x + Knife.high - l.x), math.abs(k.x + Knife.low - l.x))
            if far > l.r then found = found + 1; first = first or k.x end
        end
    end
    return found, first
end

for _, round in ipairs({2, 3, 4, 5}) do
    local m, rows, worst, stage, at, leaksWorst = build(round), 0, 0, nil, nil, 0
    for _ = 1, 120 * 120 do
        m:update(1 / 120, {})
        if m.done then break end
        if ROWS[round][m.stage] then
            if m.curtain then
                leaksWorst = math.max(leaksWorst, (leaks(m)))
            else
                local found, where = openPositions(m, (round == 4) and lit or nil)
                rows = rows + 1
                if found > worst then worst, stage, at = found, m.stage, where end
            end
        end
    end
    print(("round %d: %5d rows sampled, worst left %d open position(s)%s%s")
        :format(round, rows, worst,
            stage and (" at stage "..stage..", first x="..("%.2f"):format(at)) or "",
            leaksWorst > 0 and (", "..leaksWorst.." blade(s) past the light") or ""))
    assert(rows > 0, ("round %d never fielded a row of blades"):format(round))
    assert(worst == 0, ("round %d leaves room to stand inside a row"):format(round))
    assert(leaksWorst == 0, ("round %d lets a blade out of the light"):format(round))
    m:destroy()
end
print("ok")
