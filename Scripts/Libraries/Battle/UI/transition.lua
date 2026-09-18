local transition = {busy = false, mode = "menu", phase = "idle", edgeReveal = 0}
local animation, pending, steps, index
local hud
local speed = 1.25
local durations = {pop = 12 / speed, slide = 28 / speed, fold = 26 / speed, morph = 24 / speed}
-- Preserve the menu's left edge (22) and the command frame's right edge (618).
local expandedWidth, compactHeight = 596, 130
local hudDrop = 197 - compactHeight
local compactY = 456 - compactHeight / 2

function transition.Cancel()
    if animation then
        for i = #Tween.animations, 1, -1 do
            if Tween.animations[i] == animation then table.remove(Tween.animations, i) end
        end
    end
    animation, pending, steps = nil, nil, nil
    transition.busy = false
    transition.phase = "idle"
end

local function frame(x, width, height, hudOffset)
    Battle.mainarena:MoveTo(x, 456 - height / 2, true)
    Battle.mainarena:Resize(width, height, true)
    UI.SetTextPosition(hud[1], hud[2] + hudOffset)
    UI.SetBarPosition(hud[3], hud[4] + hudOffset)
end

local function nextStep()
    index = index + 1
    local step = steps[index]
    if not step then
        local done = pending
        animation, pending, steps = nil, nil, nil
        transition.busy = false
        transition.phase = "idle"
        done()
        return
    end
    transition.phase = step[1]
    animation = Tween.CreateTween(step[3], "cubic", "inout", 0, 1, step[2])
end

function transition.Start(mode, done)
    transition.Cancel()
    if not hud then
        local tx, ty = UI.GetTextPosition()
        local bx, by = UI.GetBarPosition()
        hud = {tx, ty, bx, by}
    end
    transition.busy = true
    pending, steps, index = done, {}, 0
    Player.sprite.visible = false
    Battle.mainarena.is_active = false
    Battle.narration_text:SetText("")
    UI.state.ClearElements()
    UI.buttons.ResetButtons()
    local function add(name, duration, setter)
        steps[#steps + 1] = {name, duration, setter}
    end
    if mode ~= "menu" and transition.mode == "menu" then
        add("pop", durations.pop, function(p)
            transition.edgeReveal = p
            UI.buttons.SetOffset(10 * p, true)
        end)
        add("slide-in", durations.slide, function(p)
            UI.buttons.SetOffset(10 - 170 * p, p < 1)
            frame(249 + 71 * p, 454 + (expandedWidth - 454) * p, 197, 0)
        end)
        add("fold", durations.fold, function(p)
            frame(320, expandedWidth, 197 - hudDrop * p, hudDrop * p)
        end)
    end
    if mode == "defense" then
        local width = transition.mode == "menu" and expandedWidth or Battle.mainarena.width
        local height = transition.mode == "menu" and compactHeight or Battle.mainarena.height
        add("defense", durations.morph, function(p)
            frame(320, width + (155 - width) * p, height + (130 - height) * p, hudDrop)
        end)
    elseif mode == "menu" then
        local arena = Battle.mainarena
        local sx, sy, sw, sh, sr = arena.x, arena.y, arena.width, arena.height, arena.rotation
        add("restore-wide", durations.morph, function(p)
            arena:MoveTo(sx + (320 - sx) * p, sy + (compactY - sy) * p, true)
            arena:Resize(sw + (expandedWidth - sw) * p, sh + (compactHeight - sh) * p, true)
            arena.rotation = sr * (1 - p)
            arena:RotateTo(arena.rotation)
        end)
        add("unfold", durations.fold, function(p)
            frame(320, expandedWidth, compactHeight + hudDrop * p, hudDrop * (1 - p))
        end)
        add("slide-out", durations.slide, function(p)
            frame(320 - 71 * p, expandedWidth - (expandedWidth - 454) * p, 197, 0)
            UI.buttons.SetOffset(-160 + 170 * p, true)
        end)
        add("settle", durations.pop, function(p)
            transition.edgeReveal = 1 - p
            UI.buttons.SetOffset(10 * (1 - p), true)
        end)
    end
    local callback = pending
    pending = function()
        transition.mode = mode
        callback()
    end
    nextStep()
end

function transition.Update()
    if animation and animation.time > animation.duration then
        animation.variableSetter(animation.final)
        for i = #Tween.animations, 1, -1 do
            if Tween.animations[i] == animation then table.remove(Tween.animations, i) end
        end
        animation = nil
        nextStep()
    end
end

return transition
