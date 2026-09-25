local encounter = {
    rounds = require("Scripts.Game.Encounter.Rounds"),
    round = 0,
    -- Battle.GetNarration() samples one entry from this localized array
    -- on every player turn, so the flavor text keeps changing.
    narration = Localize.localizeText("Battle.Narration.Random"),
    can_flee = true,
    flee_percent = 0.75,
    enemy_id = 1,
    enemies = {
        {
            id = "Chara",
            name = Localize.localizeText("Battle.EnemiesName.Chara"),
            animation = require("Scripts.Game.Animations.Chara"),

            -- Chara can never be hit. Every strike is resolved as a MISS on the
            -- confirm frame (see Scripts/Libraries/Battle/PlayerAttacks/stick.lua),
            -- which is what drives the dodge in Scripts/Game/Animations/Chara.lua.
            -- This replaces the old `maxdamage = -400` trick, which only looked
            -- the same: it went through the DAMAGE path, popped its MISS bounce at
            -- time == 70 (long after the dodge had finished) and subtracted a
            -- negative number from hp -- i.e. it healed Chara back to full.
            always_miss = true,
            maxdamage = 0,
            dmg_float = 0,

            show_hpbar = true, -- Sans... stop hiding your hp bar.
            maxhp = 100,
            hp = 100,
            gold = 1,
            exp = 1,

            defensetext = "MISS",
            misstext = "MISS",

            -- Not spareable: MERCY -> Spare would otherwise remove Chara for free
            -- (stateinner.lua:305 needs `killable and canspare`) and leave the
            -- player alone with an enemy that cannot die. This also keeps Chara's
            -- menu row white -- stateinner.lua:83 tints any spareable row yellow.
            canspare = false,
            killable = true,

            -- Single source of truth: the scene inits each sprite from this table,
            -- so it must match the on-screen position. {320, 120} is what the live
            -- scene rendered before this change; {320, 140} was stale data.
            position = {320, 120},
            actions = {
                -- Every ACT is something the PLAYER does to Chara. Chara's own
                -- replies live in Battle.Actions.Texts.Chara.<id>.
                -- Recall has no per-enemy text: its lines come from the rounds
                -- table via Scripts/Game/Logics/battle_rules.lua, so any enemy
                -- listing it would read back the same rules.
                {id = "Check",     name = Localize.localizeText("Battle.Actions.Names.Check")},
                {id = "Recall",    name = Localize.localizeText("Battle.Actions.Names.Recall")},
                {id = "Applause",  name = Localize.localizeText("Battle.Actions.Names.Applause")},
                {id = "Boo",       name = Localize.localizeText("Battle.Actions.Names.Boo")},
            }
        },
        {
            id = "Napstablook",
            name = Localize.localizeText("Battle.EnemiesName.Napstablook"),
            -- Placeholder: Napstablook reuses chara.png for now, and the factory
            -- gives it its own independent sprite + state.
            animation = require("Scripts.Game.Animations.Chara"),

            -- Takes damage normally: 2-3 solid hits bring this to 0 HP.
            maxdamage = 50,
            dmg_float = 4,

            show_hpbar = true,
            maxhp = 100,
            hp = 100,
            gold = 1,
            exp = 1,

            defensetext = "MISS",
            misstext = "MISS",

            -- canspare stays false: the MERCY -> Spare sweep in stateinner.lua:305
            -- requires `killable and canspare`, so canspare = true would paint its
            -- FIGHTMENU row yellow while being impossible to spare.
            canspare = false,
            -- 0 HP must never kill it or sweep it from the enemy list.
            killable = false,

            position = {520, 120},
            actions = {
                -- Never leave this empty: stateinner.lua:279 indexes
                -- state.typers[choosing_action], which is nil with no actions.
                -- `Applause` shares its name key with Chara's — same player action,
                -- different reaction, so the two read side by side.
                {id = "Check",    name = Localize.localizeText("Battle.Actions.Names.Check")},
                {id = "Applause", name = Localize.localizeText("Battle.Actions.Names.Applause")},
            }
        },
    },

    state = "DEFENDING",
    wave = "wave01",

    player = {
        name = "sans",
        lv = 1,
        maxhp = 20,
        hp = 20
    },

    items = require("Scripts.Game.Logics.battle_items").Inventory()
}

-- Assign internal _id to each statically-defined enemy
for i = 1, #encounter.enemies
do
    local e = encounter.enemies[i]
    e._id = encounter.enemy_id
    encounter.enemy_id = encounter.enemy_id + 1
end

-- The following methods are now provided by Battle.game_apis via metatable:
--   encounter:AddEnemy(data)  — adds a validated enemy with auto-assigned _id
--   encounter:AddItem(item)    — adds a validated item
--   encounter:forceAttack(id, value) — applies forced damage to an enemy by _id

return encounter
