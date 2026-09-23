local wave = ImportFile("Battle.Waves")
local EndWave = wave.EndWave
local Arena = Battle.mainarena

local Slash = require("Scripts.Game.Effects.opening_slash")
local phase = "intro"
local blade, blade_x, blade_spent
local warning_armed, slash_armed, slash_fired, finish_pending
local intro_typer
local intro_ready_index, intro_ready
local outro_typer, outro_ready_index, outro_hold
local ownedTypers={}
local split_arena, split_settling
local original_box

local function enemyDialogue(lines, callback)
    local enemy = Battle.game and Battle.game.enemies and Battle.game.enemies[1]
    local position = (enemy and enemy.position) or {320, 120}
    local x, y = position[1], position[2]
    local width, height = 210, 100
    local on_left = x >= 300
    local bx = on_left and math.max(25, x - width - 45)
        or math.min(615 - width, x + 65)
    local colored = {}
    for i, line in ipairs(lines) do colored[i] = "[colorHEX:000000]" .. line end
    local typer = Typers.EText.New(colored,
        {bx, math.max(35, y - height / 2 + 10)}, "UponArena", {width, height}, "none")
    typer.font = "speechbubble.ttf"
    typer.fontsize = 13
    typer.use_bondfont = false
    typer.scale = 1
    typer.line_spacing = 0
    typer.skip.canskip = false
    typer.auto_wrap = true
    typer:ShowBubble(on_left and "right" or "left", 0.5)
    typer.size[1] = width - 20
    ownedTypers[typer]=true
    typer._onComplete = function()
        ownedTypers[typer]=nil
        if callback then callback() end
    end
    return typer
end

local function localizedLines(key)
    local lines = Localize.localizeText(key)
    if (type(lines) ~= "table" or #lines == 0) then
        print("[wave01] WARNING: missing localization text: " .. key)
        return {"..."}
    end
    return lines
end

_G.Wave01Slash = function ()
    if (phase == "outro" or slash_armed or slash_fired) then return end
    slash_armed = true
end

_G.Wave01Warning = function ()
    if not slash_fired and not blade then warning_armed = true end
end

local function removeBlade()
    if (not blade) then return end
    blade:Destroy()
    for i = #wave.objects, 1, -1 do
        if (wave.objects[i] == blade) then
            table.remove(wave.objects, i)
            break
        end
    end
    blade = nil
end

local function startBlade()
    blade_x = Arena.x
    blade_spent = false
    original_box = {x = Arena.x, y = Arena.y, width = Arena.width, height = Arena.height}
    blade = Slash.New(Arena)
    table.insert(wave.objects, blade)
end

local function layoutHalves(age)
    local progress = math.max(0, math.min(1, age / Slash.OPEN_TIME))
    local visible_gap = 2 + 4 * (1 - (1 - progress) ^ 3)
    local gap = Arena.thickness * 2 + visible_gap
    local width = (original_box.width - gap) / 2
    local left_x = blade_x - gap / 2 - width / 2
    local right_x = blade_x + gap / 2 + width / 2
    Arena:MoveTo(left_x, original_box.y, true)
    Arena:Resize(width, original_box.height, true)
    split_arena:MoveTo(right_x, original_box.y, true)
    split_arena:Resize(width, original_box.height, true)
    Arena:SyncSprites()
    split_arena:SyncSprites()
end

local function cutArena()
    -- Both samples belong to the cut, not the swing above it: the box vanishing
    -- and the knife that split it.
    Audio.PlaySound("disappear.wav")
    local gap = Arena.thickness * 2 + 2
    local width = (original_box.width - gap) / 2
    split_arena = Arenas.New("plus", "rectangle", blade_x + gap / 2 + width / 2,
        original_box.y, width, original_box.height, Arena.rotation)
    split_arena:SetThickness(Arena.thickness)
    split_arena:OuterColor({unpack(Arena.white.color)})
    Arena.move_player, split_arena.move_player = false, false
    layoutHalves(0)
    split_settling = true
end

local function dropEmptyHalf()
    local in_left = math.abs(Player.sprite.x - Arena.x) <= math.abs(Player.sprite.x - split_arena.x)
    local empty = in_left and split_arena or Arena
    blade:DropHalf(empty, in_left and 1 or -1)
    if not in_left then
        Arena:MoveTo(split_arena.x, split_arena.y, true)
        Arena:Resize(split_arena.width, split_arena.height, true)
        Arena:SyncSprites()
    end
    split_arena:Destroy()
    split_arena = nil
    split_settling = false
    Arena:ResetSpeed()
    Arena.move_player = true
end

local function restoreArena()
    Arena:ResetSpeed()
    Arena.move_player = true
end

local function finishWave()
    if blade then finish_pending = true; return end
    restoreArena()
    _G.Wave01Slash = nil
    _G.Wave01Warning = nil
    EndWave()
end

local function startOutro()
    phase = "outro"
    outro_typer = enemyDialogue(localizedLines("Battle.Waves.Wave01.Outro"), function()
        outro_typer=nil
        finishWave()
    end)
end

local function introComplete()
    intro_typer = nil
    if (not slash_fired and not slash_armed) then
        print("[wave01] WARNING: [func:Wave01Slash] never fired - starting the slash at intro completion.")
        slash_armed = true
    end
end

local function startIntro()
    intro_typer = enemyDialogue(localizedLines("Battle.Waves.Wave01.Intro"), introComplete)
end

table.insert(wave.objects, {
    Destroy = function()
        for typer in pairs(ownedTypers) do
            typer._onComplete=nil
            typer:Destroy()
        end
        ownedTypers={}
        intro_typer=nil
        restoreArena()
        _G.Wave01Slash = nil
        _G.Wave01Warning = nil
    end
})

Player.canMove = true
Player.sprite:MoveTo(Arena.x, Arena.y)

function wave.Update(dt)
    if (phase == "intro") then
        phase = "intro_wait"
        startIntro()
    end

    if intro_typer then
        local index=intro_typer.sentence_index
        if intro_ready_index~=index then
            intro_ready_index=index
            intro_ready=false
        end
        local line=intro_typer.texts[index]
        local ready=line and intro_typer.counter>#line and intro_typer.cantype
        if ready then
            if intro_ready and Controller.GetState("confirm")==1 then
                intro_typer.pending_next=true
            end
            intro_ready=true
        else
            intro_ready=false
        end
    end

    if outro_typer then
        local index=outro_typer.sentence_index
        if outro_ready_index~=index then
            outro_ready_index=index
            outro_hold=0
        end
        local line=outro_typer.texts[index]
        if line and outro_typer.counter>#line and outro_typer.cantype then
            outro_hold=outro_hold+dt
            if outro_hold>=(index==#outro_typer.texts and 2 or .5) then
                outro_typer.pending_next=true
            end
        end
    end

    if warning_armed then
        warning_armed = false
        if not blade and not slash_fired then startBlade() end
    end

    if (slash_armed and not slash_fired and not intro_typer) then
        slash_armed = false
        slash_fired = true
        if not blade then startBlade() end
        blade:Strike()
        Audio.PlaySound("heavyswing.wav")
    end

    if blade then
        if blade.age >= 0 and not blade_spent then
            blade_spent = true
            local hitbox = (Player.sprite._hitbox and Player.sprite._hitbox[1]) or 16
            if Player.hurt_time <= 0 and math.abs(Player.sprite.x - blade_x) <= 1 + hitbox / 2 then
                local hp, px, py = Player.hp, Player.sprite.x, Player.sprite.y
                Battle.OnHit(blade)
                if Player.hp < hp then blade:Blood(px, py) end
            end
            cutArena()
        end
        if split_settling then
            layoutHalves(blade.age)
            if blade.age >= Slash.OPEN_TIME then dropEmptyHalf() end
        end
        if blade:Finished() then
            removeBlade()
            startOutro()
        end
    end
    if finish_pending and not blade then finishWave() end
end

return wave
