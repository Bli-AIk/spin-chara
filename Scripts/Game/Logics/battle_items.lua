local items = {}
local function text(key, args)
    return Localize.localizeText("Battle.Items." .. key, args)
end

function items.Chocolate(portion, hp, maxhp)
    if portion == 1 then return 4, 0, "Finish" end
    if portion == 2 then
        if hp / maxhp > 0.75 then return 4, 1, "Bite" end
        return 15, 0, "FinishOff"
    end
    if hp / maxhp <= 0.25 then return 90, 0, "Whole" end
    if hp / maxhp <= 0.75 then return 15, 1, "Big" end
    return 4, 2, "Small"
end

function items.Inventory()
    local result = {}
    for _, id in ipairs({"Stew", "Bunlet", "Bunlet", "Pinecone", "Pinecone", "WD40", "WD40", "Chocolate"}) do
        result[#result + 1] = {
            id = id, name = text(id .. ".Name"),
            heal = id == "Bunlet" and 12 or id == "Pinecone" and 22 or nil,
            portion = id == "Chocolate" and 3 or nil
        }
    end
    return result
end

local function heal(amount)
    local before = Player.hp
    Player.Heal(amount, before < Player.maxhp)
    if Player.hp == Player.maxhp then return Localize.localizeText("Battle.HP.Full") end
    return Localize.localizeText("Battle.HP.NotFull", {Player.hp - before})
end

function items.New()
    local self = {used = {}, oil = 0, digestion = 0, narration = nil, defending = false}

    function self:Refresh(inventory)
        for _, item in ipairs(inventory) do
            if item.id == "Chocolate" then
                item.name = text("Chocolate.Name" .. item.portion)
                item.heal = items.Chocolate(item.portion, Player.hp, Player.maxhp)
                item.statRange = item.portion > 1 and {4, item.portion == 3 and 90 or 15} or nil
                item.statPrefix = item.portion > 1 and "HP ?" or nil
            elseif item.id == "Stew" then item.statText = text("Stew.Stat")
            elseif item.id == "WD40" then item.statText = text("Speed") end
        end
    end

    function self:Use(item)
        local id = item.id
        self.used[id] = (self.used[id] or 0) + 1
        local page
        if id == "Stew" then
            Player.hp = math.max(1, Player.hp - math.ceil(Player.maxhp / 5))
            Audio.PlaySound("snd_phurt.wav")
            self.digestion = 1
            page = text("Stew.Use")
        elseif id == "WD40" then
            Audio.PlaySound("snd_splat.wav")
            self.oil = 3
            page = text("WD40.Use")
        elseif id == "Chocolate" then
            local amount, remaining, line = items.Chocolate(item.portion, Player.hp, Player.maxhp)
            item.portion = remaining
            item._cantdestroy = remaining > 0
            if remaining > 0 then item.name = text("Chocolate.Name" .. remaining) end
            page = text("Chocolate." .. line, {heal(amount)})
        else
            page = text(id .. (self.used[id] > 1 and ".Repeat" or ".Use"), {heal(item.heal)})
        end
        return {page}
    end

    function self:DefenseStarting()
        self.defending = true
        if Player.action.SetMovementModifiers then
            Player.action.SetMovementModifiers(self.oil > 0 and 1.875 or 1, self.oil > 0 and 0.15 or 0)
        end
    end

    function self:DefenseEnding()
        if not self.defending then return end
        self.defending = false
        if Player.action.SetMovementModifiers then Player.action.SetMovementModifiers(1, 0) end
        self.oil = math.max(0, self.oil - 1)
        self.narration = nil
        if self.digestion > 0 and Player.hp > 0 and not Battle._end then
            local percent = ({10, 15, 20})[self.digestion]
            Player.Heal(math.ceil(Player.maxhp * percent / 100), Player.hp < Player.maxhp)
            if self.digestion == 1 then self.narration = text("Stew.Digest") end
            self.digestion = self.digestion == 3 and 0 or self.digestion + 1
        end
    end

    function self:Clear()
        self.narration, self.oil, self.digestion, self.defending = nil, 0, 0, false
        self.used = {}
        if Player.action.SetMovementModifiers then Player.action.SetMovementModifiers(1, 0) end
    end
    return self
end

return items
