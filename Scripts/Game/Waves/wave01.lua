local wave = ImportFile("Battle.Waves")
local EndWave = wave.EndWave
local Arena = Battle.mainarena
local mask = Masks.New("rectangle", Arena.x, Arena.y, Arena.width, Arena.height, 0, 0)
local phase, line, line_hit, line_y = "intro", nil, false, -320

local function enemyDialogue(lines, callback)
    local position = Battle.game.enemies[1].position or {320, 120}
    local x, y = position[1], position[2]
    local width, height = 210, 100
    local on_left = x >= 300
    local bx = on_left and math.max(25, x - width - 45)
        or math.min(615 - width, x + 65)
    local colored = {}
    for i, line in ipairs(lines) do colored[i] = "[colorHEX:000000]" .. line end
    local typer = Typers.EText.New(colored,
        {bx, math.max(35, y - height / 2 + 10)}, "UponArena", {width, height}, "manual")
    typer.font = "speechbubble.ttf"
    typer.fontsize = 13
    typer.use_bondfont = false
    typer.scale = 1
    typer.line_spacing = 0
    typer.auto_wrap = true
    typer:ShowBubble(on_left and "right" or "left", 0.5)
    typer.size[1] = width - 20
    typer._onComplete = callback
end

Player.canMove = false
Player.sprite:MoveTo(Arena.x, Arena.y)

local function startLine()
    phase = "line"
    line = Sprites.CreateSprite("px.png", "TopAll")
    line:Scale(4, 650)
    line:MoveTo(Arena.x, line_y)
    line.color = {1, 1, 1}
    line.isBullet = true
    line.spin_damage = 10
end

local function finishLine()
    if line then line:Remove(); line = nil end
    phase = "outro"
    enemyDialogue({
        'Chara：说到"演出"...[wait:0.35]',
        "最好的节目效果，当然是嘉宾面临真实的致命危机时的表情啦！[wait:0.35]",
        "为什么不笑一下呢，嗯？[wait:0.35]",
    }, function () Player.canMove = true; EndWave() end)
end

local function startIntro()
    enemyDialogue({
        "看来又到了上台表演的时候啦！[wait:0.35]",
        "欢迎欢迎，我们的新朋友！[wait:0.35]",
        "嘿，愁眉苦脸的干什么——笑一个呀，亲？我们可是在**演出**呢？[wait:0.35]",
        "不要露出那种惹人厌的脸色啊，你要知道...[wait:0.35]",
    }, startLine)
end

function wave.Update(dt)
    mask:Follow(Arena.black)
    if phase == "intro" then
        startIntro()
        phase = "intro_wait"
    elseif phase == "line" then
        line_y = line_y + 900 * dt
        line:MoveTo(Arena.x, line_y)
        if not line_hit and line_y >= Player.sprite.y - 18 then
            line_hit = true
            Battle.OnHit(line)
        end
        if line_y >= 520 then finishLine() end
    end
end

return wave
