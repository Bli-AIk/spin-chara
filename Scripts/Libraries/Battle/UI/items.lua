local menu = {rows = {}, selected = 1, first = 1}
local rowHeight = 33
local pageSize, rowTop, nameX, valueX, markerX
local openedAt = 0

local function layout()
    local arena = Battle.mainarena
    local left = arena.x - arena.width / 2
    local right = arena.x + arena.width / 2
    rowTop = arena.y - arena.height / 2 + 14
    pageSize = math.max(1, math.floor((arena.height - 28) / rowHeight))
    nameX, valueX, markerX = left + 54, right - 42, right - 12
end

local function stat(item)
    if item.statText then return item.statText end
    if item.statRange then
        -- A fast eased sweep with a readable hold at each endpoint.
        local phase = (SE.timer.getTime() - openedAt) % 1.8
        local progress
        if phase < 0.3 then progress = 0
        elseif phase < 0.9 then progress = (phase - 0.3) / 0.6
        elseif phase < 1.2 then progress = 1
        else progress = (1.8 - phase) / 0.6 end
        local fraction = (1 - math.cos(math.pi * progress)) / 2
        local low, high = item.statRange[1], item.statRange[2]
        return string.format("%s%2d", item.statPrefix or "HP +", math.floor(low + (high - low) * fraction + 0.5))
    end
    local kind = item.type
    -- Existing inline items may omit type; infer only an unambiguous stat.
    if not kind then
        local count = 0
        for field, category in pairs({heal = "food", atk = "weapon", def = "armor"}) do
            if type(item[field]) == "number" then count = count + 1; kind = category end
        end
        if count ~= 1 then kind = nil end
    end
    if kind == "food" and type(item.heal) == "number" then
        return "HP " .. (item.heal > 0 and "+" or "") .. string.format("%2d", item.heal)
    elseif kind == "weapon" and type(item.atk) == "number" then return "ATK " .. item.atk
    elseif kind == "armor" and type(item.def) == "number" then return "DEF " .. item.def end
    return "--"
end

local function fit(text, width)
    local longest = 0
    for _, letter in ipairs(text.letters) do longest = math.max(longest, letter.line_width) end
    if longest > width then
        local scale = width / longest
        for _, letter in ipairs(text.letters) do
            letter.x = letter.x * scale
            letter.y = letter.y * scale
            letter.line_width = letter.line_width * scale
            letter.scale = letter.scale * scale
        end
    end
end

function menu.Clear()
    Player.hpbar_preview = nil
    for _, row in ipairs(menu.rows) do row.name:Destroy(); row.stat:Destroy() end
    menu.rows = {}
end

function menu.Refresh()
    menu.Clear()
    local items = Battle.game.items
    for i = 1, pageSize do
        local index = menu.first + i - 1
        local item = items[index]
        if item then
            local y = rowTop + (i - 1) * rowHeight
            local color = item._color or {1, 1, 1}
            local name = Typers.InstText.New("* " .. item.name, {nameX, y}, "UponArena")
            name.color = color
            fit(name, valueX - nameX - 118)
            local label = stat(item)
            local value = Typers.InstText.New(label, {valueX, y}, "UponArena")
            value:SetAlign("right")
            value.color = color
            fit(value, 106)
            menu.rows[#menu.rows + 1] = {name = name, stat = value, item = item, label = label}
        end
    end
end

function menu.Open()
    layout()
    openedAt = SE.timer.getTime()
    menu.selected = 1
    menu.first = 1
    UI.state.item_slot = 1
    menu.Refresh()
end

function menu.Update()
    for _, row in ipairs(menu.rows) do
        if row.item.statRange then
            local label = stat(row.item)
            if label ~= row.label then
                row.stat:SetText(label)
                fit(row.stat, 106)
                row.label = label
            end
        end
    end
    local previous = menu.selected
    local count = #Battle.game.items
    if Controller.GetState("up") == 1 then menu.selected = math.max(1, previous - 1)
    elseif Controller.GetState("down") == 1 then menu.selected = math.min(count, previous + 1) end
    if menu.selected ~= previous then
        if menu.selected < menu.first then menu.first = menu.selected
        elseif menu.selected >= menu.first + pageSize then menu.first = menu.selected - pageSize + 1 end
        Audio.PlaySound("snd_menu_0.wav")
        menu.Refresh()
    end
    UI.state.item_slot = menu.selected
    local item = Battle.game.items[menu.selected]
    local heal = item and item.heal
    Player.hpbar_preview = type(heal) == "number" and heal > 0
        and math.min(1, (Player.hp + heal) / Player.maxhp) or nil
    Player.sprite:MoveTo(nameX - 20, rowTop + 18 + (menu.selected - menu.first) * rowHeight)
    return menu.selected
end

Layers.add_external(function()
    if #menu.rows == 0 then return end
    local count = #Battle.game.items
    if count == 0 then return end
    local center = markerX
    local middle = rowTop + 18 + (pageSize - 1) * rowHeight / 2
    local top, bottom = middle - 54, middle + 54
    local spacing = math.min(12, (bottom - top) / math.max(1, count - 1))
    local start = math.floor((top + bottom - (count - 1) * spacing) / 2)
    SE.graphics.setColor(1, 1, 1)
    for i = 1, count do
        local size = i == menu.selected and 6 or 4
        SE.graphics.rectangle("fill", center - size / 2,
            math.floor(start + (i - 1) * spacing) - size / 2, size, size)
    end
    local function arrow(y, direction)
        for row = 0, 2 do
            SE.graphics.rectangle("fill", center - (1 + row * 2),
                y + direction * row * 2, 2 + row * 4, 2)
        end
    end
    -- Integer offsets preserve crisp pixels during the gentle bob.
    local bob = math.floor(2 * math.sin((SE.timer.getTime() - openedAt) * math.pi / 0.75) + 0.5)
    local last = math.floor(start + (count - 1) * spacing)
    if menu.selected > 1 then arrow(start - 16 - bob, 1) end
    if menu.selected < count then arrow(last + 16 + bob, -1) end
end, "UponArena")

return menu
