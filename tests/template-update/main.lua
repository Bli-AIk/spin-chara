-- Run from the project root: love-git tests/template-update
local project = love.filesystem.getWorkingDirectory()
dofile(project .. "/main.lua")

local gameLoad, gameUpdate, gameDraw = love.load, love.update, love.draw
local task, screenshot
local fixtures = {}
local function writeFixture(path, content)
    assert(love.filesystem.createDirectory(path:match("(.+)/")))
    assert(love.filesystem.write(path, content))
    fixtures[#fixtures + 1] = path
end
local function cleanup()
    for _, path in ipairs(fixtures) do love.filesystem.remove(path) end
end
local function frames(count)
    for _ = 1, count do coroutine.yield() end
end
local function untilTrue(predicate, label)
    for _ = 1, 600 do
        if predicate() then return end
        frames(1)
    end
    error("Timed out: " .. label .. " (state=" .. Battle.state .. ")")
end
local function settled(state)
    untilTrue(function() return Battle.state == state and not Battle.transition.busy end, state)
    frames(2)
end
local function capture(name)
    screenshot = name
    frames(2)
    assert(not screenshot, "Screenshot callback did not run")
end
local function press(action)
    local controller, keyboard = Controller.GetState, Keyboard.GetState
    Controller.GetState = function(key) return key == action and 1 or controller(key) end
    Keyboard.GetState = function(key) return key == action and 1 or keyboard(key) end
    frames(1)
    Controller.GetState, Keyboard.GetState = controller, keyboard
    frames(2)
end
local function pass(label) print("[PASS] " .. label) end

local function run()
    frames(3)
    assert(Scenes.module_current == "Scripts.Game.Scenes.Battle.scene_battle_init")
    assert(Battle.gameName == "Scripts.Game.Encounter.dummy")
    assert(Battle.mainarena.width == 454 and Battle.mainarena.height == 197)
    assert(Game.enemies[1].id == "Poseur" and #Game.items == 8)
    assert(Game.enemies[1].animation.poseur, "Custom enemy animation missing")
    assert((_RELEASED and Debugger == nil and DevTool == nil) or
        (not _RELEASED and Debugger and DevTool))
    capture(_RELEASED and "release-menu" or "menu")
    pass("custom encounter, layout, animation and build mode")

    local sprite = Sprites.CreateSprite("px.png", "TOP")
    assert(sprite:GetImagePath() == "Resources/Sprites/px.png")
    sprite:Destroy()
    assert(Audio.ResolvePath("sound", "snd_menu_0.wav") == "Resources/Sounds/snd_menu_0.wav")
    assert(Localize.GetLanguagePath("zh_CN") == "Localization/zh_CN.json")
    writeFixture("Scripts/Game/Resources/Sprites/px.png", assert(love.filesystem.read("Resources/Sprites/px.png")))
    sprite = Sprites.CreateSprite("px.png", "TOP")
    assert(sprite:GetImagePath() == "Scripts/Game/Resources/Sprites/px.png")
    sprite:Destroy()
    writeFixture("Scripts/Game/Resources/Sounds/snd_menu_0.wav", assert(love.filesystem.read("Resources/Sounds/snd_menu_0.wav")))
    assert(Audio.ResolvePath("sound", "snd_menu_0.wav") == "Scripts/Game/Resources/Sounds/snd_menu_0.wav")
    writeFixture("Scripts/Game/Localization/zh_CN.json", assert(love.filesystem.read("Localization/zh_CN.json")))
    assert(Localize.GetLanguagePath("zh_CN") == "Scripts/Game/Localization/zh_CN.json")
    cleanup()
    pass("sprite, sound and localization overrides and fallback")

    Battle.ChangeState("ITEMMENU")
    frames(3)
    local items = require("Scripts.Libraries.Battle.UI.items")
    assert(#items.rows == 5)
    assert(Game.items[1].statText == "HP -??" and Game.items[6].statText == "+SP")
    capture("items-top")
    for _ = 1, 6 do press("down") end
    assert(items.selected == 7 and items.first == 3)
    capture("items")
    press("down")
    Player.hp = 1
    local beforeItems = #Game.items
    press("confirm")
    settled("DIALOGUERESULT")
    assert(Player.hp == Player.maxhp and #Game.items == beforeItems - 1)
    for _ = 1, 8 do
        if Battle.state == "DEFENDING" then break end
        press("cancel")
        press("confirm")
    end
    settled("DEFENDING")
    local started = love.timer.getTime()
    settled("ACTIONSELECT")
    assert(love.timer.getTime() - started >= 4.8, "Item defense ended before five seconds")
    pass("item scrolling, healing, consumption and dialogue transition")

    local function finishDialogue(target)
        for _ = 1, 20 do
            if Battle.state == target then break end
            press("cancel")
            press("confirm")
        end
        settled(target)
    end
    local function useSlot(slot)
        Battle.ChangeState("ITEMMENU")
        frames(3)
        for _ = 2, slot do press("down") end
        press("confirm")
        settled("DIALOGUERESULT")
    end
    local function endDefense()
        Battle._wave.EndWave()
        settled("ACTIONSELECT")
    end
    Game.items = require("Scripts.Game.Logics.battle_items").Inventory()
    local originalHit = Battle.OnHit
    Battle.OnHit = function() end
    Player.hp = Player.maxhp
    useSlot(8)
    assert(#Game.items == 8 and Game.items[8].portion == 2)
    finishDialogue("DEFENDING")
    endDefense()
    useSlot(8)
    assert(#Game.items == 8 and Game.items[8].portion == 1)
    finishDialogue("DEFENDING")
    endDefense()
    Battle.ChangeState("ITEMMENU")
    frames(3)
    for _ = 1, 7 do press("down") end
    assert(items.rows[#items.rows].label == "HP + 4", "Last chocolate piece must show normal healing")
    capture("chocolate-crumb")
    press("confirm")
    settled("DIALOGUERESULT")
    assert(#Game.items == 7)
    finishDialogue("DEFENDING")
    endDefense()
    Player.hp = 1
    useSlot(1)
    assert(Player.hp == 1 and #Game.items == 6)
    finishDialogue("DEFENDING")
    for i, hp in ipairs({3, 6, 10}) do
        Battle._wave.EndWave()
        settled("ACTIONSELECT")
        assert(Player.hp == hp, "Live digestion tick " .. i)
        assert((Battle.GetNarration() == Localize.localizeText("Battle.Items.Stew.Digest")) == (i == 1))
        if i == 1 then frames(90); capture("digestion") end
        if i < 3 then Battle.ChangeState("DEFENDING"); settled("DEFENDING") end
    end
    useSlot(5)
    assert(Player.hp == 10 and #Game.items == 5, "Spray must not heal")
    press("cancel")
    frames(60)
    capture("spray")
    finishDialogue("DEFENDING")
    endDefense()
    assert(Battle.GetNarration() ~= Localize.localizeText("Battle.Items.Stew.Digest"))
    Battle.OnHit = originalHit
    pass("partial chocolate consumption, digestion narration and spray")

    Battle.selected_enemy_index = 1
    Battle.ChangeState("ATTACKING")
    settled("ATTACKING")
    assert(Battle.attack.target and Battle.attack.bar)
    capture("attack")
    press("confirm")
    settled("DEFENDING")
    assert(Battle.waveModule == "Scripts.Game.Waves.wave")
    assert(#Battle._wave.objects == 1)
    capture("defense")
    settled("ACTIONSELECT")
    assert(not package.loaded["Scripts.Game.Waves.wave"])
    assert(not package.loaded["Scripts.Waves.wave"])
    assert(Battle.mainarena.width == 454 and Battle.mainarena.height == 197)
    pass("attack, game wave, defense completion and menu restoration")

    Battle.ChangeState("DEFENDING")
    settled("DEFENDING")
    assert(#Battle._wave.objects == 1)
    settled("ACTIONSELECT")
    pass("second wave recreates objects and clears module caches")

    SetScreenScale(2)
    assert(GetScreenScale() == 2)
    SetScreenScale("integer")
    love.keypressed("f4")
    frames(3)
    assert(love.window.getFullscreen())
    local w, h = love.graphics.getDimensions()
    assert(DrawX == math.floor((w - CANVAS_WIDTH * ScreenScale) / 2 + 0.5))
    assert(DrawY == math.floor((h - CANVAS_HEIGHT * ScreenScale) / 2 + 0.5))
    capture("fullscreen")
    love.keypressed("f4")
    frames(3)
    assert(not love.window.getFullscreen())
    pass("window/fullscreen scaling and centering")

    if not _RELEASED then
        love.keypressed("f8")
        frames(5)
        assert(DevTool.win and not DevTool._failed, "F8 window failed")
        love.keypressed("f8")
        frames(3)
        assert(not DevTool.win)
        pass("Linux F8 native tool opens and closes")

        for _, mode in ipairs({"f5", "ctrl-r", "trigger", "f5"}) do
            local previousScene, previousBattle = Scenes.current, Battle
            if mode == "trigger" then
                assert(not io.open(".reload_trigger", "r"), "Existing user reload trigger")
                local file = assert(io.open(".reload_trigger", "w"))
                file:close()
            elseif mode == "ctrl-r" then
                local isDown = love.keyboard.isDown
                love.keyboard.isDown = function(key) return key == "lctrl" or isDown(key) end
                love.keypressed("r")
                love.keyboard.isDown = isDown
            else
                love.keypressed("f5")
            end
            frames(4)
            assert(Scenes.current ~= previousScene and Battle ~= previousBattle)
            assert(Scenes.module_current == "Scripts.Game.Scenes.Battle.scene_battle_init")
            assert(#Game.items == 8 and Battle.mainarena.width == 454)
            Battle.ChangeState("DEFENDING")
            settled("DEFENDING")
            assert(Battle.waveModule == "Scripts.Game.Waves.wave" and #Battle._wave.objects > 0)
            settled("ACTIONSELECT")
            pass(mode .. " reload and complete battle wave")
        end
        capture("reloaded-menu")
    else
        assert(not package.loaded["Scripts.Libraries.Engine.Debugger"])
        assert(not package.loaded["Scripts.Libraries.Engine.DevTool"])
        pass("release does not load development modules")
    end

    writeFixture("Scripts/Scenes/template_test.lua", "return {clear=function() end, marker='root'}")
    writeFixture("Scripts/Game/Scenes/template_test.lua", "return {clear=function() end, marker='game'}")
    Scenes.switchTo("template_test")
    frames(3)
    assert(Scenes.current.marker == "game")
    love.filesystem.remove("Scripts/Game/Scenes/template_test.lua")
    Scenes.switchTo("template_test")
    frames(3)
    assert(Scenes.current.marker == "root")
    Scenes.switchTo("Battle.scene_battle_init")
    frames(3)
    writeFixture("Scripts/Waves/template_test.lua", "return {marker='root'}")
    writeFixture("Scripts/Game/Waves/template_test.lua", "return {marker='game'}")
    assert(Battle.LoadWave("template_test").marker == "game")
    Battle.ClearWaveModule("template_test")
    love.filesystem.remove("Scripts/Game/Waves/template_test.lua")
    assert(Battle.LoadWave("template_test").marker == "root")
    Battle.ClearWaveModule("template_test")
    cleanup()
    pass("scene and wave overrides fall back after removing game copy")
    Localize.setFile("en")
    Scenes.switchTo("Battle.scene_battle_init")
    frames(3)
    Battle.ChangeState("ITEMMENU")
    frames(3)
    capture("english-items-top")
    for _ = 1, 7 do press("down") end
    capture("english-items-bottom")
    assert(Game.items[1].statText == "HP -??" and Game.items[6].statText == "+SP")
    pass("English names and special item stats")
    local currentMenu = require("Scripts.Libraries.Battle.UI.items")
    local getTime, now = SE.timer.getTime, 0
    SE.timer.getTime = function() return now end
    currentMenu.Open()
    currentMenu.first, currentMenu.selected = 4, 8
    currentMenu.Refresh()
    local chocolateRow = currentMenu.rows[5]
    for _, sample in ipairs({{0, "HP ? 4"}, {0.25, "HP ? 4"}, {0.6, "HP ?47"}, {1, "HP ?90"}, {1.19, "HP ?90"}, {1.5, "HP ?47"}, {1.85, "HP ? 4"}}) do
        now = sample[1]
        currentMenu.Update()
        assert(chocolateRow.label == sample[2], "Chocolate animation at " .. now .. ": " .. chocolateRow.label)
    end
    SE.timer.getTime = getTime
    untilTrue(function() return chocolateRow.label == "HP ?90" end, "Chocolate maximum")
    capture("chocolate-max")
    untilTrue(function() return chocolateRow.label == "HP ? 4" end, "Chocolate minimum")
    capture("chocolate-min")
    pass("eased chocolate range, endpoint holds and padded single digits")
    Battle.ChangeState("ACTIONSELECT")
    settled("ACTIONSELECT")
    useSlot(6)
    press("cancel")
    frames(60)
    capture("english-spray-single-page")
    finishDialogue("DEFENDING")
    endDefense()
    print("[PASS] All template integration checks; screenshots: " .. love.filesystem.getSaveDirectory())
    love.event.quit(0)
end

function love.load(...)
    gameLoad(...)
    task = coroutine.create(run)
end

function love.update(dt)
    gameUpdate(dt)
    if coroutine.status(task) ~= "dead" then
        local ok, err = coroutine.resume(task)
        if not ok then cleanup(); error(debug.traceback(task, err)) end
    end
end

function love.draw()
    gameDraw()
    if screenshot then
        local name = screenshot
        love.graphics.captureScreenshot(function(data)
            local colors, count = {}, 0
            local w, h = data:getDimensions()
            for y = 0, h - 1, 8 do
                for x = 0, w - 1, 8 do
                    local r, g, b = data:getPixel(x, y)
                    local color = string.format("%.2f,%.2f,%.2f", r, g, b)
                    if not colors[color] then colors[color] = true; count = count + 1 end
                end
            end
            data:encode("png", name .. ".png")
            print("[FRAME] " .. name .. ": " .. count .. " sampled colors")
            assert(count >= 3, "Blank or incomplete rendered frame: " .. name)
            screenshot = nil
        end)
    end
end
