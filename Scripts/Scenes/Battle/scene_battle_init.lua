local scene = {}

-- Import battle module
Battle = ImportFile("Battle")
Battle.SetEndRoom("scene_end")
Game = Battle.SetGame("dummy")
Game:AddItem({id = "STABLE", _color = {0.5, 0, 0}, heal = 99, name = "ImNotFood"})
Game:AddItem({id = "STABLE", _color = {0.5, 0, 0}, heal = 99, name = "ImNotFood"})
Game:AddItem({id = "STABLE", _color = {0.5, 0, 0}, heal = 99, name = "ImNotFood"})
Blasters = ImportFile("Attacks.Blasters")

-- Give each enemy its own independent animation instance. The animation
-- module is a factory, so every call to InitAnimation creates a fresh
-- instance with its own sprite — enemy #1 and enemy #2 no longer share one.
Game:InitAnimation(1, {320, 120})
--Game:InitAnimation(2, {120, 140})
local enemies = Game.enemies

local function DefenseEnding()
end

-- Handlers
local function HandleActions(enemy, action)
    Battle.BattleDialogue(Localize.localizeText("Battle.Actions.Texts." .. enemy.id .. "." .. action.id), "ACTIONSELECT")
end

local function HandleItems(item)
    print("Used " .. item.name)

    local heal = item.heal or 0
    Player.Heal(heal, true)
    Battle.BattleDialogue({
        "* You ate " .. item.name .. ".",
        "* You recovered " .. heal .. " HP!"
    }, "ACTIONSELECT")
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
    Battle.defaultEnteringState(oldstate, newstate)
    --print("[Battle] " .. oldstate .. " → " .. newstate)
end

local function OnHit(bullet)
    local damage = 1
    local color = (bullet["HurtMode"] or "normal")
    color = color:lower()

    if (color == "normal") then
        Player.Hurt(damage)
    elseif (color == "blue" or color == "cyan") then
        if (Controller.GetState("arrows") > 0) then
            Player.Hurt(damage)
        end
    elseif (color == "orange") then
        if (Controller.GetState("arrows") <= 0) then
            Player.Hurt(damage)
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



-- Scene backgrounds
local background = Sprites.CreateSprite("px.png", "Background")
background:Scale(640, 480)
background:MoveTo(320, 240)
background.color = {0.12, 0.06, 0.18} --todo: 后续需要改回

function scene.update(dt)
    Battle.Update(dt)
    Blasters.Update(dt)
end

function scene.clear()
    Layers.clear()
    Battle.Clear()
end

return scene
