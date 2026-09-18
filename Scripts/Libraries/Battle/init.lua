---@diagnostic disable: undefined-field

Layers.new_layer("BOTTOM", -1000)
Layers.new_layer("Background", -10)
Layers.new_layer("UI", 0)
Layers.new_layer("ArenasExtraW", 10)
Layers.new_layer("ArenasExtraB", 10.01)
Layers.new_layer("UponArena", 11)
Layers.new_layer("BelowPlayer", 12)
Layers.new_layer("Player", 13)
Layers.new_layer("BelowBullets", 25)
Layers.new_layer("Bullets", 30)
Layers.new_layer("ArenasCoverW", 50)
Layers.new_layer("ArenasCoverB", 50.01)
Layers.new_layer("TopAll", 60)
Layers.new_layer("TOP", 1000)

local path = (...):match("(.-)[^%.]+$")
local battle = {
    player = require(path .. "Battle.Player"),
    arenas = require(path .. "Battle.Arenas"),

    state = "ACTIONSELECT",
    game = nil,

    selected_enemy_index = 0,
    selected_action_index = 0,
    selected_index = 0,
    dialog_texts = nil,

    attack = ImportFile("Battle.PlayerAttacks.stick"),
    attack_paths = {"Scripts.Libraries.Battle.PlayerAttacks.stick"},
    wave = "wave",
    _wave = {},
    restoring_arena = false,

    TIME_F = 0,
    TIME_R = 0,

    EXP = 0,
    GOLD = 0,
    room_end = "scene_end",
    _end = false,
    _end_time = 0
}

local blacktop = Sprites.CreateSprite("px.png", "TOP")
blacktop:Scale(1000, 1000)
blacktop.alpha = 0
blacktop.color = {0, 0, 0}
blacktop.Step = function (self)
    if (battle._end) then
        self.alpha = self.alpha + 0.05

        if (self.alpha >= 1) then
            Scenes.switchTo(battle.room_end)
        end
    end
end

-- Load battle method APIs for attaching to encounter tables via metatable
local game_apis = require(path .. "Battle.game_apis")

Player = battle.player
Arenas = battle.arenas
battle.ui = require(path .. "Battle.UI")
UI = battle.ui
battle.transition = require(path .. "Battle.UI.transition")

Player.SetSoul(1)
battle.mainarena = Arenas.New("plus", "rectangle", 249, 357.5, 454, 197, 0)
battle.mainarena.is_active = false
-- The menu box opens toward the separate command column.
Layers.add_external(function()
    local reveal = battle.transition.edgeReveal
    if reveal < 1 then
        local arena = battle.mainarena
        local right = arena.x + arena.width / 2
        SE.graphics.setColor(0, 0, 0)
        SE.graphics.rectangle("fill", right + arena.thickness * reveal,
            arena.y - arena.height / 2, arena.thickness * (1 - reveal), arena.height)
    end
end, "UponArena")
local narration_text = Typers.EText.New("", {41, 273}, "UponArena", {420, 170}, "none")
narration_text.auto_wrap = true
battle.narration_text = narration_text

function battle.BattleDialogue(texts, final_state)
    battle.dialogue_started = true
    local t = battle.NewDialogue(texts)
    t.auto_wrap = true
    t._onComplete = function ()
        Battle.ChangeState(final_state or "ACTIONSELECT")
        UI.state.block_transition = true
    end
end

function battle.NewDialogue(texts)
    local arena = battle.mainarena
    local t = Typers.EText.New(texts,
        {arena.x - arena.width / 2 + 19, arena.y - arena.height / 2 + 14},
        "UponArena", {arena.width - 38, arena.height - 24}, "manual")
    t.auto_wrap = true
    local update = t.Update
    function t:Update(dt)
        local box = battle.mainarena
        self.x = box.x - box.width / 2 + 19
        self.y = box.y - box.height / 2 + 14
        self.size[1] = math.max(416, box.width - 38)
        local mode = self.mode
        if battle.transition.busy then self.mode = "none" end
        update(self, dt)
        self.mode = mode
    end
    return t
end

function battle.FullDialogue(texts, call)
    local t = battle.NewDialogue(texts)
    t.auto_wrap = true
    t._onComplete = function ()
        call()
    end
end

function battle.DefenseEnding() end
function battle.HandleActions(enemy, action) end
function battle.HandleItems(item) end
function battle.HandleFlee() end
function battle.FleeUpdate(dt) end
function battle.OnHit(bullet) end

local function defaultEnteringState(old, new)
    if (old == "ACTIONMENU" and new == "DIALOGUERESULT") then
        local enemy = battle.game.enemies[battle.selected_enemy_index]
        local action = enemy.actions[battle.selected_action_index]
        battle.HandleActions(enemy, action)
    elseif (old == "ITEMMENU" and new == "DIALOGUERESULT") then
        local item = battle.game.items[battle.selected_index]
        battle.HandleItems(item)

        for i = #battle.game.items, 1, -1
        do
            local item_ = battle.game.items[i]
            if (i == UI.state.item_slot) then
                if (not item_._cantdestroy) then
                    table.remove(battle.game.items, UI.state.item_slot)
                end
            end
        end
    end
    if (new == "DEFENDING") then
        battle.Defending()
        UI.buttons.ResetButtons()
    end

    if (new == "WIN") then
        Player.sprite.visible = false
    end
end

battle.EnteringState = defaultEnteringState
battle.defaultEnteringState = defaultEnteringState

-- Unified state transition: the only way to change the battle state.
-- Whenever the state actually changes, EnteringState is run exactly once,
-- so callers never need to trigger it manually.
function battle.ChangeState(new_state)
    if battle.transition.busy then
        battle.pending_state = new_state
        return
    end
    if (battle.state == new_state) then
        return
    end
    local old = battle.state
    local function commit(preserve_narration)
        battle.state = new_state
        battle.dialogue_started = false
        Player.sprite.visible = new_state ~= "WIN" and new_state ~= "DIALOGUERESULT"
            and new_state ~= "ATTACKING"
        battle.EnteringState(old, new_state)
        UI.state.Enter(preserve_narration)
        UI.state.block_transition = true
    end
    if old == "DEFENDING" then
        if battle._wave.EndWave and not battle._wave.ENDED then battle._wave.EndWave() end
        package.loaded["Scripts.Waves." .. battle.wave] = nil
        battle._wave = {}
        battle.DefenseEnding()
        Arenas.Clear()
    end
    local mode
    if new_state == "DEFENDING" then mode = "defense"
    elseif new_state == "ATTACKING" or new_state == "DIALOGUERESULT" then mode = "compact"
    elseif new_state == "ACTIONSELECT" then mode = "menu" end
    if mode and mode ~= battle.transition.mode then
        local early_dialogue = new_state == "DIALOGUERESULT"
        battle.transition.Start(mode, function()
            if not early_dialogue then commit(new_state == "ACTIONSELECT") end
            local pending = battle.pending_state
            battle.pending_state = nil
            if pending then battle.ChangeState(pending) end
        end)
        if early_dialogue then
            commit()
        elseif new_state == "ACTIONSELECT" then
            battle.narration_text:SetText(battle.game.narration)
        end
    else
        commit()
    end
end

function battle.SetEndRoom(room)
    battle.room_end = room
end

---Plays the victory message. The base lines come from "Battle.WinTexts1"
---(EXP / GOLD); `extra_texts` are appended after them. When the typewriter
---finishes, `on_complete` runs and then the battle fades out (`_end = true`).
---
---Scenes usually override `Battle.Win` (keeping this as `Battle.defaultWin`) to
---react on victory, e.g. to append "* Your LOVE increased!" only on a level-up.
---@param extra_texts table|nil Extra text lines appended to the win message.
---@param on_complete function|nil Called once the win message has finished.
function battle.Win(extra_texts, on_complete)
    battle.transition.Cancel()
    battle.ChangeState("WIN")
    local texts = Localize.localizeText("Battle.WinTexts1", {Battle.EXP, Battle.GOLD})

    if (extra_texts) then
        for _, line in ipairs(extra_texts) do
            texts[#texts + 1] = line
        end
    end

    local t = battle.NewDialogue(texts)
    t.auto_wrap = true
    t._onComplete = function ()
        if (on_complete) then on_complete() end
        battle._end = true
    end
end
-- Base implementation, kept so a scene can override Battle.Win and still call it.
battle.defaultWin = battle.Win

function battle.SetGame(file)
    battle.gameName = "Scripts.Game." .. file
    local ok, err = pcall(function ()
        battle.game = require(battle.gameName)
    end)

    if (not ok) then
        print("[Battle System] Error: " .. err)
    else
        print("[Battle System] Loaded '" .. file .. "' as the battle successfully!")
        local game_ = battle.game
        if (not game_) then return end
        local player_data = game_.player

        if (player_data.name) then Player.name = player_data.name end
        if (player_data.lv) then Player.lv = player_data.lv end
        if (player_data.maxhp) then Player.maxhp = player_data.maxhp end
        if (player_data.hp) then Player.hp = player_data.hp end
        if (game_.wave) then Battle.wave = game_.wave end
        Battle.ChangeState(game_.state or "ACTIONSELECT")
        UI.buttons.ResetButtons()
        if (Battle.state == "ACTIONSELECT" and not battle.transition.busy) then
            narration_text:SetText(game_.narration or "")
        end
        UI.barUpdate()

        -- Attach game_apis methods to the encounter table via metatable.
        -- This allows encounter:AddItem(...), encounter:AddEnemy(...),
        -- and encounter:forceAttack(...) to work seamlessly on any loaded game.
        if (type(game_) == "table") then
            setmetatable(game_, {__index = game_apis})
        end

        return battle.game
    end
end

function battle.SetAttackPattern(pattern)
    local _pattern
    local ok, err = pcall(function ()
        _pattern = ImportFile("Battle.PlayerAttacks." .. pattern)
    end)

    if (ok) then
        battle.attack = _pattern

        local _add = true
        for _, v in ipairs(battle.attack_paths)
        do
            if (pattern == v) then
                _add = false
            end
        end

        if (_add) then
            table.insert(battle.attack_paths, pattern)
        end
    else
        battle.attack = ImportFile("Battle.PlayerAttacks.stick")
        print("[Battle - PlayerAttack] Error: " .. err)
    end
end

function battle.Defending()
    Player.sprite:MoveTo(Battle.mainarena.x, Battle.mainarena.y)
    Battle.mainarena.is_active = true

    local _wave = {}
    local ok, err = pcall(function ()
        _wave = require("Scripts.Waves." .. Battle.wave)
    end)

    -- Defensive reset: the wave is the shared "Battle.Waves" table, which may
    -- still hold _end = true from a previous run if cleanup was skipped.
    if (ok) then
        _wave._end = false
        Battle._wave = _wave
    else
        _wave = require("Scripts.Waves.wave")
        _wave._end = false
        Battle._wave = _wave
        print("[Battle - Wave] Error: " .. err)
    end
end

function battle.Update(dt)
    local transitioning = battle.transition.busy
    battle.transition.Update()
    local arena = battle.mainarena
    battle.narration_text.x = arena.x - arena.width / 2 + 19
    battle.narration_text.y = arena.y - arena.height / 2 + 14
    if not transitioning and not battle.transition.busy then Player.Update(dt) end
    Arenas.Update(dt)
    if not transitioning then UI.Update(dt) else UI.barUpdate() end

    -- Timers
    battle.TIME_F = battle.TIME_F + 1
    battle.TIME_R = battle.TIME_R + dt

    -- Enemies Animation
    if (not battle.game) then return end
    for _, v in ipairs(battle.game.enemies)
    do
        local anim = v.animation
        if (anim) then
            -- Expose the enemy table plus the fields monsters commonly need, so
            -- animation code can read them straight off `self`.
            anim.enemy    = v
            anim.canspare = v.canspare
            anim.killable = v.killable
            anim.hp       = v.hp
            anim.maxhp    = v.maxhp
            -- Convenience signal: HP has reached 0 and the enemy is killable.
            anim.dead     = (v.hp ~= nil and v.hp <= 0 and v.killable == true)

            if (anim.Update) then
                anim:Update(dt)
            end
        end
    end

    if (battle._end) then
        battle._end_time = battle._end_time + 1
    end
end

-- Compatibility entry point; restoration is owned by the transition controller.
function battle.UpdateRestore(dt)
    battle.transition.Update()
end

function battle.Clear()
    battle.transition.Cancel()
    battle.pending_state = nil
    -- Clear the game module tree so it re-queries Localize on next load
    if battle.gameName then
        ClearModuleTree(battle.gameName)
    end

    -- Clear all loaded attack pattern modules (Scripts.Libraries.Battle.PlayerAttacks.*)
    for i = #battle.attack_paths, 1, -1
    do
        ClearModuleTree(battle.attack_paths[i])
    end

    if (Battle._wave) then
        Battle._wave._end = false
        Battle._wave.objects = {}
        Battle._wave._paths = {}
    end
    Battle._wave = {}
    -- Clear the wave wrapper and reset the shared "Battle.Waves" state so a
    -- future wave doesn't inherit a stale _end = true flag.
    ClearModuleTree("Scripts.Waves." .. Battle.wave)
    battle.restoring_arena = false
    battle.enemy_anims = {}

    -- Clear the entire Battle library tree (UI, buttons, Player, Arenas,
    -- game_apis, Waves, PlayerAttacks, Souls, etc.) in a single pass.
    ClearModuleTree("Scripts.Libraries.Attacks")
    ClearModuleTree("Scripts.Libraries.Battle")
end

return battle
