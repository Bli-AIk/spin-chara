-- Real-engine check for the shader-driven HP bar. Boots the actual battle and
-- samples the rendered frame, so it covers the shader compiling, the uniforms
-- reaching it and the regions landing in the right places. Screenshots of every
-- stage are written next to the save for eyeballing.
--
-- One simulation step per frame: the damage band drains on a real timer, so a
-- test that ran several steps per frame would see the band move between asking
-- for a screenshot and the frame actually being captured.
--
-- Run from the project root: xvfb-run -a love-git tests/hpbar-shader
local project=love.filesystem.getWorkingDirectory()
dofile(project.."/main.lua")
local gameLoad,gameUpdate,gameDraw=love.load,love.update,love.draw
local task

local function frames(n) for _=1,n do coroutine.yield() end end

-- Capture the frame that is about to be drawn and wait for the readback. The
-- image is only written out when a name is given, so a caller that samples
-- several frames can keep just the interesting one.
local function grab(name)
    local data
    love.graphics.captureScreenshot(function(image) data=image end)
    for _=1,20 do
        coroutine.yield()
        if data then break end
    end
    assert(data,"No frame captured for "..tostring(name))
    if name then data:encode("png",name) end
    return data
end

--- Color of the bar at `fraction` of its width, on the frame just captured.
local function barPixel(data,fraction)
    local barX,barY=UI.GetBarPosition()
    return data:getPixel(math.floor(barX+UI.GetMaxHPBar().xscale*fraction),math.floor(barY))
end

local function near(a,b) return math.abs(a-b)<0.02 end

local function expect(data,x,y,want,what)
    local r,g,blue=data:getPixel(math.floor(x),math.floor(y))
    assert(near(r,want[1]) and near(g,want[2]) and near(blue,want[3]),
        string.format("%s at (%d,%d): got (%.3f,%.3f,%.3f), want (%.2f,%.2f,%.2f)",
            what,math.floor(x),math.floor(y),r,g,blue,want[1],want[2],want[3]))
end

local YELLOW,WHITE,RED={1,1,0},{1,1,1},{1,0,0}

-- Missing HP is red; white is only a short shrinking damage trail.

-- One capture per stage, sampled at three fractions along the bar: inside the
-- fill, inside the damage band, and in the empty slot beyond it.
local function checkBar(fillAt,bandAt,slotAt,fillColor,bandColor,slotColor,label)
    local data=grab(label)
    local barX,barY=UI.GetBarPosition()
    local barW=UI.GetMaxHPBar().xscale
    expect(data,barX+barW*fillAt,barY,fillColor,label.." fill")
    expect(data,barX+barW*bandAt,barY,bandColor,label.." band")
    expect(data,barX+barW*slotAt,barY,slotColor,label.." slot")
end

local function run()
    frames(5)
    -- The shader is the whole point of the bar now; a silent fallback would make
    -- every color assertion below meaningless.
    assert(#UI.GetMaxHPBar()._shaders==1,"HPBar.glsl must be attached to the bar")

    Battle.ChangeState("ACTIONSELECT")
    frames(300)
    Player.maxhp,Player.hp=20,20
    frames(10)

    -- Full HP: the whole bar is the fill, nothing else to see.
    checkBar(0.2,0.6,0.9,YELLOW,YELLOW,YELLOW,"hpbar-full.png")

    -- HP moved without a hit (an item or the encounter): the fill shrinks but no
    -- wound color appears, so nothing may react to the number alone.
    Player.hp=14
    frames(10)
    checkBar(0.3,0.8,0.92,YELLOW,RED,RED,"hpbar-partial.png")

    -- A knife hit immediately lowers yellow and leaves a short white trail.
    Player.Hurt(3,30,nil,2)
    assert(Player.hp==11,"A knife hit must cost 3")
    frames(1)
    checkBar(0.25,0.62,0.92,YELLOW,WHITE,RED,"hpbar-hit.png")

    -- The white trail is gone at 0.5 seconds, before the regular gate ends.
    frames(30)
    assert(Player.hurt_time==0,"The knife's gate must be open by now")
    assert(Player.hurt_regular>0,"The regular window must still be running")
    checkBar(0.25,0.6,0.92,YELLOW,RED,RED,"hpbar-drained.png")

    -- No white trail returns after the regular window expires.
    frames(35)
    assert(Player.hurt_regular==0,"The regular window must have run out")
    checkBar(0.25,0.6,0.92,YELLOW,RED,RED,"hpbar-idle.png")

    -- The item menu pulses a yellow band out to the fraction the item would heal.
    Player.maxhp,Player.hp=20,10
    frames(5)
    -- Slot 1 is Stew, which takes HP away; walk the real menu onto Bunlet so the
    -- preview has a heal to show.
    local realGetState=Controller.GetState
    Controller.GetState=function(key) if key=="down" then return 1 end return realGetState(key) end
    Battle.ChangeState("ITEMMENU")
    frames(150)
    Controller.GetState=realGetState
    frames(5)
    assert(Battle.state=="ITEMMENU","The item menu must open")
    local preview=Player.hpbar_preview
    assert(type(preview)=="number","The item menu must preview a heal on the bar")
    assert(near(preview,1),"A 12 HP heal from 10/20 must preview a full bar, got "..tostring(preview))

    -- The band pulses on abs(sin()) against the wall clock, and the test runs at
    -- a fixed 10000 FPS, so sleeping between samples is what actually sweeps the
    -- pulse. |sin| is above 0.87 for a third of each period, so a full period of
    -- samples has to catch a crest: the stretch past the current fill must read
    -- yellow there, where the idle bar reads white.
    local shown,maxGreen=nil,0
    for _=1,30 do
        local data=grab()
        local r,g,b=barPixel(data,0.8)
        if g>maxGreen then maxGreen,shown=g,data end
        love.timer.sleep(0.1)
        frames(1)
    end
    assert(maxGreen>0.8,"The heal preview must pulse yellow over the red slot")
    shown:encode("png","hpbar-preview.png")

    -- The fill it previews onto is still the plain current-HP yellow.
    local barX,barY=UI.GetBarPosition()
    expect(shown,barX+UI.GetMaxHPBar().xscale*0.3,barY,YELLOW,"hpbar-preview.png fill")

    Battle.ChangeState("ACTIONSELECT")
    frames(150)
    assert(Player.hpbar_preview == nil, "Leaving items must clear the preview")
    checkBar(0.25,0.7,0.92,YELLOW,RED,RED,"hpbar-preview-closed.png")

    -- Inspect actual glyph pixels, not just the color calculation.
    local function numberGreen(data)
        local pos=UI.GetLayout().hptext
        local brightest=-1
        for y=math.floor(pos[2]),math.floor(pos[2])+18 do
            for x=math.floor(pos[1]),math.floor(pos[1])+10 do
                local r,g,b=data:getPixel(x,y)
                if r>0.98 and near(g,b) then brightest=math.max(brightest,g) end
            end
        end
        assert(brightest>=0,"HP glyph must be visible")
        return brightest
    end
    Player.Hurt(3,30,nil,2)
    local red=numberGreen(grab("hp-number-red.png"))
    assert(red<0.05,"HP numbers must immediately become red")
    frames(29)
    local fading=numberGreen(grab("hp-number-fading.png"))
    assert(fading>0.4 and fading<0.6,"HP numbers must gradually approach white")
    Player.Heal(5)
    frames(8)
    checkBar(0.5,0.7,0.92,YELLOW,RED,RED,"hpbar-heal-during-wound.png")
    frames(65)
    checkBar(0.5,0.7,0.92,YELLOW,RED,RED,"hpbar-healed-idle.png")
    assert(numberGreen(grab("hp-number-white.png"))>0.98,"HP numbers must finish white")
    Player.Hurt(1)
    assert(numberGreen(grab())<0.05,"Ordinary damage must restart the red fade too")

    print("[OK] HP bar: short white trail, red slot, item previews, HP number fade")
    love.event.quit(0)
end

function love.load(...)
    gameLoad(...)
    Global.SetVariable("FPS",10000)
    task=coroutine.create(run)
end

function love.update()
    gameUpdate(1/60)
    if coroutine.status(task)~="dead" then
        local ok,err=coroutine.resume(task)
        if not ok then error(debug.traceback(task,err)) end
    end
end

function love.draw()
    gameDraw()
end
