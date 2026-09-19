---@diagnostic disable: undefined-field

-- ---------------------------------------------------------------------------
-- Game-first module resolution
--
-- Encounter scripts, waves and attack patterns are all per-game content, so the
-- Game area (Scripts/Game/...) wins and the engine directory is the fallback:
--
--   encounters      Scripts.Game.Encounter.<file>   (Game-only; no root twin)
--   waves           Scripts.Game.Waves.<name>      -> Scripts.Waves.<name>
--   attack patterns Scripts.Libraries.Battle.PlayerAttacks.<name>
--                                                -> kept, see SetAttackPattern
--
-- Existence is probed on the FILESYSTEM first rather than inferred from a failed
-- require. `pcall(require, ...)` cannot tell "the module is not there" apart from
-- "the module is there but its top-level code threw", and treating the second as
-- the first would silently cut the fallback chain short instead of surfacing a
-- genuine error in a module that really was found.
local BATTLE_MODULE_ROOTS = {
    waves = {"Scripts.Game.Waves.", "Scripts.Waves."}
}

-- Battle BGM. Pass only the file name: Audio.ResolvePath checks the Game
-- resource folder first (Scripts/Game/Resources/Music) and then falls back to
-- Resources/Music, so this custom track still works if the engine copy exists.
local BATTLE_BGM = "mus_elbow_grease.mp3"

-- "50. Elbow Grease" starts at 130 BPM in 4/4. The attached edit view marks
-- the one-time intro as 1.1 -> 2.1, i.e. four beats / one 4/4 bar.
-- The intro is played once; after that the track loops from bar 2.1 to the end.
local BATTLE_BGM_BPM = 130
local BATTLE_BGM_BEATS_PER_BAR = 4
local BATTLE_BGM_INTRO_BARS = 1 -- 1.1 -> 2.1 in the editor; use 4 for four full bars
local BATTLE_BGM_LOOP_START = BATTLE_BGM_INTRO_BARS * BATTLE_BGM_BEATS_PER_BAR * (60 / BATTLE_BGM_BPM)

--- Describe a module name as a project-relative file path, for filesystem probes.
---@param module_name string e.g. "Scripts.Waves.wave"
---@return string e.g. "Scripts/Waves/wave.lua"
local function battleModulePathOf(module_name)
    return (module_name:gsub("%.", "/")) .. ".lua"
end

--- Test whether a module's file actually exists on disk.
--- LÖVE 11 returns a table from getInfo while LÖVE 12 returns the info directly,
--- so the result is only trusted as a positive when it is truthy.
---@param module_name string
---@return boolean
local function battleModuleExists(module_name)
    local file_path = battleModulePathOf(module_name)

    local ok, info = pcall(function()
        return SE.filesystem.getInfo and SE.filesystem.getInfo(file_path)
    end)
    if (ok and info) then return true end

    -- Fallback probe: a real, readable file counts as existing.
    local readable, content = pcall(love.filesystem.read, file_path, 1)
    return (readable and content ~= nil)
end

--- Require the first module that exists among `roots`, Game area first.
---
--- Returns the module name that was found (nil when no root has the file) plus
--- the loaded value, so callers can distinguish three outcomes:
---   * loaded            -> module_name is set and loaded is the table
---   * found but crashed -> module_name is set, loaded is nil, error_message set
---   * not found         -> module_name is nil (caller decides on a default)
--- A missing Game copy never prevents the root copy from being tried.
---@param roots string[] Module prefixes to try, in order.
---@param name string Module name suffix (e.g. the wave name).
---@return string|nil module_name
---@return any loaded
---@return any error_message
---@return string|nil error_module
local function requireGameFirst(roots, name)
    -- Bare `return nil` yields exactly ONE value in Lua, which would make the
    -- caller's 4-value unpack collapse. Return the full shape on every path.
    if (not name) or (name == "") then return nil, nil, nil, nil end

    local found_module = nil
    local found_root = nil
    local first_error = nil
    local first_error_module = nil

    for _, root in ipairs(roots) do
        local module_name = root .. name

        if (battleModuleExists(module_name)) then
            found_module = found_module or module_name
            found_root = found_root or root

            local ok, loaded = pcall(require, module_name)
            if (ok and loaded) then
                -- A Game-area copy that exists but throws must never be silent,
                -- even when a lower root successfully supplies the module: the
                -- override is broken and the author needs to know.
                if (first_error) then
                    print("[Battle] WARNING: '" .. tostring(first_error_module) ..
                        "' exists but failed to load; using " .. module_name .. " instead.")
                    print("[Battle]   " .. tostring(first_error))
                elseif (root ~= roots[1]) then
                    print("[Battle] WARNING: '" .. name .. "' not found in " ..
                        roots[1] .. " (fell back to " .. module_name .. ").")
                end
                return module_name, loaded, nil, nil
            end

            if (not first_error) then
                first_error = loaded
                first_error_module = module_name
            end
        end
    end

    if (found_module) then
        if (found_root ~= roots[1]) then
            print("[Battle] WARNING: '" .. name .. "' not found in " ..
                roots[1] .. " (fell back to " .. found_module .. ").")
        end
        return found_module, nil, (first_error or "unknown error"), first_error_module
    end

    return nil, nil, nil, nil
end

---Clear a wave module from the require cache under BOTH roots, so a wave that
---moved between the Game area and the engine directory never stays stale.
---@param wave_name string|nil Defaults to battle.wave when nil.
local function clearWaveModule(wave_name)
    local name = wave_name
    if (not name) or (name == "") then
        name = Battle.wave
    end
    if (not name) or (name == "") then return end

    for _, root in ipairs(BATTLE_MODULE_ROOTS.waves) do
        ClearModuleTree(root .. name)
        package.loaded[root .. name] = nil
    end
end

---Public wrapper so other Battle modules (e.g. UI states) can drop the wave
---module without hard-coding which root it came from.
---NOTE: defined further down, right after the `battle` table exists - this file
---assigns a field on a local table, so it cannot run before `local battle = {}`.

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

---Public wrapper so other Battle modules (e.g. UI states) can drop the wave
---module without hard-coding which root it came from. Defined here (not in the
---helpers block above) because it assigns a field on the local `battle` table.
---@param wave_name string|nil Defaults to battle.wave when nil.
function battle.ClearWaveModule(wave_name)
    clearWaveModule(wave_name)
end

---Resolve the narration line for the current player turn.
---
---Encounters may set `narration` to:
---  * a string  - legacy behavior, displayed as-is;
---  * an array   - one entry is picked at random every turn;
---  * a function - called with the encounter table, must return a string.
---The resolved value is always a string so callers can safely pass it to
---`EText:SetText`.
---@return string
local function resolveNarration()
    local game_ = battle.game
    local narration = game_ and game_.narration

    if (type(narration) == "function") then
        local ok, result = pcall(narration, game_)
        if (ok and type(result) == "string") then
            return result
        end
        print("[Battle System] WARNING: encounter narration function failed: " .. tostring(result))
        return ""
    end

    if (type(narration) == "table") then
        local count = #narration
        if (count > 0) then
            local line = narration[math.random(count)]
            if (type(line) == "string") then
                return line
            end
            print("[Battle System] WARNING: encounter narration table contains a non-string entry.")
            return ""
        end
        print("[Battle System] WARNING: encounter narration table is empty.")
        return ""
    end

    return type(narration) == "string" and narration or ""
end

-- Keep the resolved line stable through menu navigation and action dialogues.
function battle.GetNarration()
    if battle._turnNarration == nil then
        battle._turnNarration = resolveNarration()
    end
    return battle._turnNarration
end

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
        clearWaveModule(battle.wave)
        battle._wave.objects = {}
        battle._wave._paths = {}
        battle._wave = {}
        battle.DefenseEnding()
        battle._turnNarration = nil
        Arenas.Clear()
    end
    local mode
    if new_state == "DEFENDING" then mode = "defense"
    elseif new_state == "ATTACKING" or new_state == "DIALOGUERESULT" then mode = "compact"
    elseif new_state == "ACTIONSELECT" then mode = "menu" end
    if mode and mode ~= battle.transition.mode then
        local early_dialogue = new_state == "DIALOGUERESULT"
        battle.preparing_attack = new_state == "ATTACKING"
        battle.transition.Start(mode, function()
            battle.preparing_attack = false
            if not early_dialogue then commit(new_state == "ACTIONSELECT") end
            local pending = battle.pending_state
            battle.pending_state = nil
            if pending then battle.ChangeState(pending) end
        end)
        if early_dialogue then
            commit()
        elseif new_state == "ACTIONSELECT" then
            battle.narration_text:SetText(battle.GetNarration())
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

---Start the battle BGM. Any music (usually the overworld theme) is cleared
---first so two tracks can never overlap; Audio.Clear also stops leftover
---sound effects at the scene boundary.
local function startBattleBGM()
    if (Audio.FindMusic(BATTLE_BGM)) then
        return
    end

    Audio.Clear()
    battle._music = nil
    battle._music_source = nil
    battle._music_duration = nil
    battle._music_loop_start = nil

    -- Play the whole track once (intro included). updateBattleBGM() is what
    -- seeks back to BATTLE_BGM_LOOP_START after the first pass.
    local ok, source, inst = pcall(Audio.PlayMusic, BATTLE_BGM, nil, false)
    if (ok) then
        battle._music = inst
        battle._music_source = source or (inst and inst.source)
        battle._music_loop_start = BATTLE_BGM_LOOP_START

        if (battle._music_source) then
            local duration_ok, duration = pcall(function()
                return battle._music_source:getDuration()
            end)
            battle._music_duration = (duration_ok and duration) or nil
        end

        -- Audio.PlayMusic already set Source:setLooping(false). Mark the
        -- instance as managed by us so Audio.Update() does not release it
        -- when the stream momentarily reaches the end of the first pass.
        if (inst) then
            inst.loop = true
        end
    else
        print("[Battle] Failed to play BGM '" .. BATTLE_BGM .. "': " .. tostring(source))
    end
end

---Keep the battle BGM on its intro/loop schedule.
---First pass: the source plays from 0 to its natural end. After that every
---pass is seeked back to BATTLE_BGM_LOOP_START (bar 2.1), which skips the
---one-time intro. The audio file itself is never modified.
---@param dt number
local function updateBattleBGM(dt)
    local source = battle._music_source
    if (not source) then
        return
    end

    local ok_position, position = pcall(function()
        return source:tell()
    end)
    if (not ok_position) then
        return
    end

    local duration = battle._music_duration
    if (not duration or duration <= 0) then
        local ok_duration, value = pcall(function()
            return source:getDuration()
        end)
        duration = (ok_duration and value) or nil
        battle._music_duration = duration
    end

    -- If this frame would cross the end, seek back before the stream stops.
    -- The lookahead covers one frame (minimum 0.03 s), which is small enough
    -- not to be noticeable at the loop point.
    local lookahead = math.max(dt or 0, 0.03)
    local reached_end = (
        (duration and (position + lookahead) >= (duration - 0.01)) or
        (not source:isPlaying())
    )

    if (reached_end) then
        pcall(function()
            source:seek(battle._music_loop_start or BATTLE_BGM_LOOP_START)
            source:play()
        end)
    end
end

---Load an encounter script from the Game area.
---
---Encounters live under Scripts/Game/Encounter/ (there is no engine-side twin -
---Scripts/Encounter/ does not exist). The file is probed before requiring so a
---missing encounter reports "not found" instead of being confused with an
---encounter that exists but throws.
---@param file string Encounter name, e.g. "Chara" (no extension).
---@return table|nil The loaded encounter table, or nil on failure.
function battle.SetGame(file)
    battle.gameName = "Scripts.Game.Encounter." .. file

    if (not battleModuleExists(battle.gameName)) then
        print("[Battle System] WARNING: encounter '" .. tostring(file) .. "' not found at " ..
            battleModulePathOf(battle.gameName) .. ".")
        return nil
    end

    local ok, err = pcall(function ()
        battle.game = require(battle.gameName)
    end)

    if (not ok) then
        print("[Battle System] Error loading encounter '" .. tostring(file) .. "': " .. tostring(err))
        return nil
    else
        print("[Battle System] Loaded '" .. file .. "' as the battle successfully!")
        battle._turnNarration = nil
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
            narration_text:SetText(battle.GetNarration())
        end
        UI.barUpdate()

        -- Attach game_apis methods to the encounter table via metatable.
        -- This allows encounter:AddItem(...), encounter:AddEnemy(...),
        -- and encounter:forceAttack(...) to work seamlessly on any loaded game.
        if (type(game_) == "table") then
            setmetatable(game_, {__index = game_apis})
        end

        startBattleBGM()

        return battle.game
    end
end

function battle.SetAttackPattern(pattern)
    local _pattern
    local module_name = "Scripts.Libraries.Battle.PlayerAttacks." .. tostring(pattern)
    local _exists = battleModuleExists(module_name)

    if (_exists) then
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
            return
        end

        print("[Battle - PlayerAttack] Error in '" .. module_name .. "': " .. tostring(err))
    else
        print("[Battle - PlayerAttack] WARNING: attack pattern '" .. tostring(pattern) ..
            "' not found at " .. battleModulePathOf(module_name) .. ".")
    end

    -- Fall back to the default attack pattern so ACTIONSELECT still works.
    print("[Battle - PlayerAttack] Falling back to the default pattern (stick).")
    battle.attack = ImportFile("Battle.PlayerAttacks.stick")
end

---Load a wave script, Game area first (Scripts/Game/Waves/) then engine
---(Scripts/Waves/). A wave that is missing or broken falls back to the default
---"wave" script and warns, so a battle always has *something* to run.
---@param wave_name string
---@return table The wave table that was selected.
function battle.LoadWave(wave_name)
    local name = (wave_name and wave_name ~= "") and wave_name or "wave"
    local roots = BATTLE_MODULE_ROOTS.waves

    local module_name, loaded, error_message, error_module = requireGameFirst(roots, name)
    battle.waveModule = module_name

    if (loaded) then
        return loaded
    end

    if (module_name) then
        -- Found, but its top-level code threw: report the real error instead of
        -- silently degrading, then still fall back so the battle can continue.
        print("[Battle - Wave] Error in '" .. tostring(error_module) .. "': " .. tostring(error_message))
    else
        print("[Battle - Wave] WARNING: wave '" .. name .. "' not found. Searched, in order:")
        for _, root in ipairs(roots) do
            print("    " .. root .. name .. "  (" .. battleModulePathOf(root .. name) .. ")")
        end
    end

    -- Fall back to the default wave. It lives in the engine directory, but go
    -- through the resolver so a Game-side "wave" override still wins.
    local fallback_module, fallback, fallback_error = requireGameFirst(roots, "wave")
    battle.waveModule = fallback_module or battle.waveModule

    if (fallback) then
        print("[Battle - Wave] Falling back to the default wave (" .. tostring(fallback_module) .. ").")
        return fallback
    end

    print("[Battle - Wave] Error: default wave unavailable: " .. tostring(fallback_error))
    return {}
end

function battle.Defending()
    Player.sprite:MoveTo(Battle.mainarena.x, Battle.mainarena.y)
    Battle.mainarena.is_active = true

    local _wave = battle.LoadWave(Battle.wave)

    -- Wave wrappers share Battle.Waves; reset both completion flags per round.
    _wave._end = false
    _wave.ENDED = false
    Battle._wave = _wave
end

function battle.Update(dt)
    updateBattleBGM(dt)

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
    if (battle._music) then
        battle._music:Stop()
        battle._music = nil
    end
    battle._music_source = nil
    battle._music_duration = nil
    battle._music_loop_start = nil

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
    -- Clear the wave wrapper (under both roots) and reset the shared
    -- "Battle.Waves" state so a future wave doesn't inherit a stale _end = true.
    clearWaveModule(Battle.wave)
    battle.restoring_arena = false
    battle.enemy_anims = {}

    -- Clear the entire Battle library tree (UI, buttons, Player, Arenas,
    -- game_apis, Waves, PlayerAttacks, Souls, etc.) in a single pass.
    ClearModuleTree("Scripts.Libraries.Attacks")
    ClearModuleTree("Scripts.Libraries.Battle")
end

return battle
