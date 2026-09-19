-- Run from the project root: luajit tests/battle-items.lua
local json = dofile("Scripts/Libraries/Utils/dkjson.lua")
local language
Localize = {localizeText = function(key, args)
    local value = assert(language[key], key)
    return args and string.format(value, unpack(args)) or value
end}
Audio = {PlaySound = function(name) Audio.played = name end}
Player = {hp = 20, maxhp = 20, action = {SetMovementModifiers = function(scale, seconds) Player.modifiers = {scale, seconds} end}}
Player.Heal = function(n) Player.hp = math.min(Player.maxhp, Player.hp + n) end
Battle = {state = "ACTIONSELECT", transition = {busy = false}}
Battle.ChangeState = function(state) Battle.state = state end
Battle.BattleDialogue = function(lines, state) Battle.lines, Battle.next = lines, state end
local module = dofile("Scripts/Game/Logics/battle_items.lua")
for _, locale in ipairs({"en", "zh_CN"}) do
    local file = assert(io.open("Localization/" .. locale .. ".json"))
    language = assert(json.decode(file:read("*a")))
    file:close()
    local inventory = module.Inventory()
    assert(#inventory == 8 and inventory[2] ~= inventory[3] and inventory[6] ~= inventory[7])
    local cases = {
        {3, 5, 90, 0}, {3, 6, 15, 1}, {3, 15, 15, 1}, {3, 16, 4, 2}, {3, 20, 4, 2},
        {2, 5, 15, 0}, {2, 15, 15, 0}, {2, 16, 4, 1},
        {1, 5, 4, 0}, {1, 15, 4, 0}, {1, 20, 4, 0}
    }
    for _, case in ipairs(cases) do
        local amount, remaining = module.Chocolate(case[1], case[2], 20)
        assert(amount == case[3] and remaining == case[4])
        local state = module.New()
        local item = {id = "Chocolate", portion = case[1]}
        Player.hp = case[2]
        local lines = state:Use(item)
        assert(Player.hp == math.min(20, case[2] + amount))
        assert(item.portion == remaining and item._cantdestroy == (remaining > 0))
        assert(#lines == 1 and lines[1]:find("\n* ", 1, true), "Item result must be one page")
    end
    local state = module.New()
    Player.hp = 1
    state:Use(inventory[1])
    assert(Player.hp == 1)
    for i, hp in ipairs({3, 6, 10, 10}) do
        state:DefenseStarting()
        state:DefenseEnding()
        assert(Player.hp == hp, "Digestion tick " .. i)
        assert((state.narration ~= nil) == (i == 1), "Digestion narration lasts one turn")
        state:DefenseEnding()
        assert(Player.hp == hp, "Duplicate digestion")
    end
    Player.hp = 20
    state:Use(inventory[1])
    assert(Player.hp == 16)
    Player.maxhp, Player.hp = 24, 20
    state:Use(inventory[1])
    assert(Player.hp == 15, "Stew damage must round up")
    Player.maxhp, Player.hp = 21, 1
    state:DefenseStarting(); state:DefenseEnding()
    assert(Player.hp == 4, "Healing must round up")
    Player.maxhp, Player.hp = 20, 0
    state:DefenseStarting(); state:DefenseEnding()
    assert(Player.hp == 0, "Digestion cannot revive")
    state:Clear()
    Player.hp = 10
    state:Use(inventory[6])
    assert(Player.hp == 10 and state.oil == 3)
    assert(Audio.played == "snd_splat.wav", "WD40 must spray")
    state:DefenseStarting()
    assert(Player.modifiers[1] == 1.875 and Player.modifiers[2] == 0.15, "Oil speed boost")
    state:DefenseEnding()
    assert(state.oil == 2)
    state:Use(inventory[7])
    assert(state.oil == 3)
    for _ = 1, 3 do state:DefenseStarting(); state:DefenseEnding() end
    assert(state.oil == 0)
    state:DefenseStarting()
    assert(Player.modifiers[1] == 1, "Boost must expire with the oil")
    local first = state:Use(inventory[2])
    local second = state:Use(inventory[3])
    assert(first[1] ~= second[1] and Player.hp == 20)
    state:Clear()
    assert(state.oil == 0 and state.digestion == 0 and next(state.used) == nil)
    state:Refresh(inventory)
    assert(inventory[1].statText == "HP -??" and inventory[6].statText == "+SP" and inventory[8].heal == 4)
end

local keys, realTime = {}, true
Controller = {GetState = function(key) return keys[key] and 1 or 0 end}
Global = {GetVariable = function() return realTime end}
local red = dofile("Scripts/Libraries/Battle/Player/Souls/red.lua")
red.sprite = {x = 0, y = 0}
keys.right = true
red.Update(1 / 60)
assert(red.sprite.x == 2)
keys.cancel = true
red.Update(1 / 60)
assert(red.sprite.x == 3)
keys.cancel = nil
for _, fps in ipairs({30, 60, 144}) do
    red.sprite.x = 0
    red.SetMovementModifiers(1.5, 0.15)
    for _ = 1, fps do red.Update(1 / fps) end
    assert(math.abs(red.sprite.x - (180 - 27 * (1 - math.exp(-1 / 0.15)))) < 0.001)
end
local before = red.sprite.x
keys.right = nil
red.Update(1 / 60)
assert(red.sprite.x > before, "Must coast after releasing input")
keys.left = true
before = red.sprite.x
red.Update(1 / 60)
assert(red.sprite.x > before, "Reversal must have inertia")
red.sprite.x = 0 -- Simulate arena clamping.
red.Update(1 / 60)
assert(red.sprite.x < 0, "Blocked velocity must clear")
red.SetMovementModifiers(1, 0)
before = red.sprite.x
red.Update(1 / 60)
assert(red.sprite.x == before - 2)

for _, fps in ipairs({30, 60, 144}) do
    local ended, elapsed = false, 0
    local wave = {objects = {}, EndWave = function() ended = true end, Import = function() return {Update = function() end} end}
    ImportFile = function() return wave end
    Battle.mainarena = {x = 0, y = 0, width = 100, height = 100}
    Masks = {New = function() return {Follow = function() end} end}
    Sprites = {CreateSprite = function() return {Scale = function() end, MoveTo = function() end, SetStencils = function() end} end}
    local testWave = dofile("Scripts/Game/Waves/wave.lua")
    while not ended do elapsed = elapsed + 1 / fps; testWave.Update(1 / fps) end
    assert(elapsed >= 5 and elapsed <= 5 + 1 / fps + 0.00001)
end
print("PASS: bilingual item rules, digestion, chocolate, oil, movement and five-second waves")
