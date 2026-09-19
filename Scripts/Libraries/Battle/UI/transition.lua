local transition = {busy = false, mode = "menu", phase = "idle", edgeReveal = 0}
local animation, pending, steps, index
local hud
local entrancePlayer
local speed = 1.25
local durations = {pop = 12 / speed, slide = 28 / speed, fold = 26 / speed, morph = 24 / speed,
    defenseRise = 40 / speed, playerEntrance = 0.65 * 60, playerDelay = 0. * 60}
-- Preserve the menu's left edge (22) and the command frame's right edge (618).
local expandedWidth, compactHeight = 596, 130
local hudDrop = 197 - compactHeight
local compactY = 456 - compactHeight / 2
local defenseTextY = 400
local defenseY = defenseTextY - 20 - compactHeight / 2

local function clearEntrancePlayer()
    if entrancePlayer then
        entrancePlayer:Remove()
        entrancePlayer = nil
    end
end

local function easedProgress(time, delay, duration)
    local p = math.max(0, math.min(1, (time - delay) / duration))
    return p < 0.5 and 4 * p ^ 3 or 1 - (-2 * p + 2) ^ 3 / 2
end

function transition.Cancel()
    clearEntrancePlayer()
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

-- Place the complete defense layout without creating a tween.  Used when an
-- encounter starts in DEFENDING so the first rendered frame is already the
-- enemy-turn layout.
function transition.SetImmediate(mode)
    if mode ~= "defense" then return end
    if not hud then
        local tx, ty = UI.GetTextPosition()
        local bx, by = UI.GetBarPosition()
        hud = {tx, ty, bx, by}
    end
    transition.edgeReveal = 1
    transition.mode = mode
    Battle.mainarena:MoveTo(320, defenseY, true)
    Battle.mainarena:Resize(155, compactHeight, true)
    Battle.mainarena.is_active = true
    UI.SetTextPosition(hud[1], defenseTextY)
    UI.SetBarPosition(hud[3], defenseTextY - hud[2] + hud[4])
    UI.buttons.SetOffset(-160, false)
end

local function nextStep()
    index = index + 1
    local step = steps[index]
    if not step then
        local done = pending
        clearEntrancePlayer()
        animation, pending, steps = nil, nil, nil
        transition.busy = false
        transition.phase = "idle"
        done()
        return
    end
    transition.phase = step[1]
    animation = Tween.CreateTween(step[3], step[4] or "cubic", step[4] and "" or "inout", 0, 1, step[2])
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
    local function add(name, duration, setter, easing)
        steps[#steps + 1] = {name, duration, setter, easing}
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
            if Battle.preparing_attack and Battle.attack.Prepare and Battle.attack.Reveal then
                if not Battle.attack._prepared then
                    Battle.attack.Prepare(Battle.game.enemies[Battle.selected_enemy_index])
                end
                Battle.attack.Reveal(p)
            end
        end)
    end
    if mode == "defense" then
        local width = transition.mode == "menu" and expandedWidth or Battle.mainarena.width
        local height = transition.mode == "menu" and compactHeight or Battle.mainarena.height
        local startY = transition.mode == "menu" and compactY or Battle.mainarena.y
        local _, textY = UI.GetTextPosition()
        local startOffset = transition.mode == "menu" and hudDrop or textY - hud[2]
        local endOffset = defenseTextY - hud[2]
        local narrowDuration, riseDuration = durations.slide, durations.defenseRise
        local hudDelay = 0.12 * 60
        local playerStart = narrowDuration + durations.playerDelay
        local totalDuration = math.max(narrowDuration + riseDuration, playerStart + durations.playerEntrance)
        local entranceY = 240
        local entranceMask
        -- One clock keeps the delayed HUD and the two arena movements overlapping.
        add("defense", totalDuration, function(p)
            local time = p * totalDuration
            local narrow = easedProgress(time, 0, narrowDuration)
            local rise = easedProgress(time, narrowDuration, riseDuration)
            local hudProgress = easedProgress(time, hudDelay, durations.slide)
            local arena = Battle.mainarena
            arena:Resize(width + (155 - width) * narrow, height + (compactHeight - height) * rise, true)
            arena:MoveTo(320, startY + (defenseY - startY) * rise, true)
            local offset = startOffset + (endOffset - startOffset) * hudProgress
            UI.SetTextPosition(hud[1], hud[2] + offset)
            UI.SetBarPosition(hud[3], hud[4] + offset)
            if not entrancePlayer then
                local source = Player.sprite
                entrancePlayer = Sprites.CreateSprite(source.path, source.layer)
                entrancePlayer:Scale(source.xscale, source.yscale)
                entrancePlayer.color = source.color
                entrancePlayer.rotation = source.rotation
                entranceMask = Masks.New("rectangle", arena.x, arena.y, arena.width, arena.height, arena.rotation, 0)
                entrancePlayer:SetStencils({entranceMask})
            end
            entranceMask.x, entranceMask.y = arena.x, arena.y
            entranceMask.w, entranceMask.h = arena.width, arena.height
            entranceMask.r = arena.rotation
            -- Keep the masked entrance alive until the heart settles at the real player's spawn.
            local playerProgress = easedProgress(time, playerStart, durations.playerEntrance)
            entrancePlayer:MoveTo(320, entranceY + (defenseY - entranceY) * playerProgress)
        end, "linear")
    elseif mode == "menu" then
        local arena = Battle.mainarena
        local sx, sy, sw, sh, sr = arena.x, arena.y, arena.width, arena.height, arena.rotation
        local tx, ty = UI.GetTextPosition()
        local bx, by = UI.GetBarPosition()
        add("restore-wide", durations.morph, function(p)
            arena:MoveTo(sx + (320 - sx) * p, sy + (compactY - sy) * p, true)
            arena:Resize(sw + (expandedWidth - sw) * p, sh + (compactHeight - sh) * p, true)
            arena.rotation = sr * (1 - p)
            arena:RotateTo(arena.rotation)
            UI.SetTextPosition(tx + (hud[1] - tx) * p, ty + (hud[2] + hudDrop - ty) * p)
            UI.SetBarPosition(bx + (hud[3] - bx) * p, by + (hud[4] + hudDrop - by) * p)
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
