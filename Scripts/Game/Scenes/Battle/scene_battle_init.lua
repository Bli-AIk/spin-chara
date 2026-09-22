local scene = {}

-- Import battle module
Battle = ImportFile("Battle")
Battle.SetEndRoom("scene_end")
Game = Battle.SetGame("dummy")
local requestedWave=tonumber(os.getenv("SPIN_CHARA_WAVE"))
if requestedWave and not _RELEASED then
    assert(requestedWave%1==0 and Game.rounds[requestedWave],"Invalid starting wave")
    Game.round=requestedWave-1
end
local items = require("Scripts.Game.Logics.battle_items").New()
local acts = require("Scripts.Game.Logics.battle_acts").New()
-- Indexed by enemy._id, then tag name; active only during the upcoming defense.
Game.act_effects = acts
local random_narration = Game.narration
-- The hand-over out of round 1 is the battle's opening line, not a random peek
-- at the stage, so the first turn is pinned to Battle.Narration.Default and the
-- Random table only starts being sampled from round 2 on. EnterRound increments
-- Game.round on entering DEFENDING, so round 1 is 1 for the whole of its turn.
local opening_narration = Localize.localizeText("Battle.Narration.Default")
Game.narration = function()
    if (items.narration) then return items.narration end
    if (Game.round <= 1 and type(opening_narration) == "string") then
        return opening_narration
    end
    return random_narration[math.random(#random_narration)]
end
Blasters = ImportFile("Attacks.Blasters")

-- Give each enemy its own independent animation instance, at the position the
-- encounter declares. The animation module is a factory, so every call to
-- InitAnimation creates a fresh instance with its own sprite — enemy #1 and
-- enemy #2 no longer share one.
-- Reading each enemy's own `position` (instead of hard-coding coordinates here)
-- keeps the encounter the single source of truth for where a monster stands:
-- the same field is what stick.lua uses to place the slice / MISS text.
for i, enemy in ipairs(Game.enemies)
do
    Game:InitAnimation(i, enemy.position)
end
local enemies = Game.enemies

local function EnterRound()
    Game.round = math.min(Game.round + 1, #Game.rounds)
    local round = Game.rounds[Game.round]
    Battle.wave = round.wave
    print("回合 " .. Game.round)
end

local function DefenseEnding()
    items:DefenseEnding()
    acts:DefenseEnding()
end

-- Handlers
local function HandleActions(enemy, action)
    acts:Use(enemy, action)
end

local function HandleItems(item)
    Battle.BattleDialogue(items:Use(item), "DEFENDING")
end

local function HandleFlee()
    Audio.PlaySound("snd_flee.wav")
    local legs_ = Sprites.CreateSprite("Soul Library Sprites/spr_heartgtfo_0.png", Player.sprite.layer)
    legs_.color = Player.sprite.color
    legs_:MoveTo(Player.sprite:GetPosition())
    legs_.y = legs_.y + 6
    legs_.velocity.x = -1
    legs_:SetAnimation({
        "Soul Library Sprites/spr_heartgtfo_1.png",
        "Soul Library Sprites/spr_heartgtfo_0.png"
    }, 0.1)

    Player.sprite.y = Player.sprite.y - 6
    Player.sprite.velocity.x = -1
    Battle.FullDialogue({
        "* 我跑路了."
    }, function ()
        Battle._end = true
    end)
end

local function FleeUpdate(dt)
    print("Fleeing")
end

local function EnteringState(oldstate, newstate)
    if newstate == "DEFENDING" then EnterRound() end
    if newstate == "ITEMMENU" then items:Refresh(Game.items) end
    if newstate == "DEFENDING" then
        items:DefenseStarting()
        acts:DefenseStarting()
    end
    Battle.defaultEnteringState(oldstate, newstate)
    --print("[Battle] " .. oldstate .. " → " .. newstate)
end

local function OnHit(bullet)
    local damage = bullet.spin_damage or 1
    local color = (bullet["HurtMode"] or "normal")
    color = color:lower()

    if (color == "normal") then
        Player.Hurt(damage, bullet.spin_hurt_time, true, bullet.spin_punish)
    elseif (color == "blue" or color == "cyan") then
        if (Controller.GetState("arrows") > 0) then
            Player.Hurt(damage, bullet.spin_hurt_time, true, bullet.spin_punish)
        end
    elseif (color == "orange") then
        if (Controller.GetState("arrows") <= 0) then
            Player.Hurt(damage, bullet.spin_hurt_time, true, bullet.spin_punish)
        end
    end
end

-- Don't touch these.
Battle.DefenseEnding = DefenseEnding
Battle.HandleActions = HandleActions
Battle.HandleItems = HandleItems
Battle.EnteringState = EnteringState
Battle.HandleFlee = HandleFlee
Battle.FleeUpdate = FleeUpdate
Battle.OnHit = OnHit

-- SetGame loads the encounter before this scene installs its handlers.  Emit
-- the initial round here so startup and later DEFENDING entries use the same
-- round bookkeeping.
if Battle.state == "DEFENDING" and (Game.round == 0 or requestedWave and not _RELEASED) then
    if requestedWave and not _RELEASED then
        -- SetGame has already loaded the encounter's default wave01. Replace
        -- that instance as well as the round number before the first update.
        if Battle._wave.EndWave then Battle._wave.EndWave() end
        Battle.ClearWaveModule(Battle.wave)
    end
    EnterRound()
    if requestedWave and not _RELEASED then Battle.Defending() end
end



-- Scene backgrounds
local background = Sprites.CreateSprite("px.png", "Background")
background:Scale(640, 480)
background:MoveTo(320, 240)
background.color = {0., 0., 0.}

function scene.update(dt)
    Battle.Update(dt)
    Blasters.Update(dt)
end

function scene.clear()
    acts:Clear()
    ClearModuleTree("Scripts.Game.Logics.battle_acts")
    items:Clear()
    ClearModuleTree("Scripts.Game.Logics.battle_items")
    Layers.clear()
    Battle.Clear()
end

return scene
