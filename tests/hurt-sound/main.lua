-- The soul must cry out when a bullet lands on it. Boots the real battle and
-- drives a real bullet through Player.Update's collision loop into Battle.OnHit,
-- so the whole chain is covered: the scene's OnHit, Player.Hurt's use_sound
-- argument and Audio.PlaySound's path resolution. The file it resolves to must
-- be the requested hurt sample, and invincibility must stay quiet.
--
-- Run from the project root: xvfb-run -a env ALSOFT_DRIVERS=null love-git tests/hurt-sound
local project=love.filesystem.getWorkingDirectory()
dofile(project.."/main.lua")
local gameLoad,gameUpdate,gameDraw=love.load,love.update,love.draw
local task

local function frames(n) for _=1,n do coroutine.yield() end end

-- Same file the barrage hands the soul; snd_hurt1.wav under its engine name.
local HURT="snd_phurt.wav"
local SOURCE="Resources/Sounds/snd_hurt1.wav"

--- Records every sound the engine is asked to play, and hands back a stop
--- function that unpatches it and returns the names captured meanwhile.
local function recordSounds()
    local names={}
    local real=Audio.PlaySound
    Audio.PlaySound=function(name,...)
        names[#names+1]=name
        return real(name,...)
    end
    return function()
        Audio.PlaySound=real
        return names
    end
end

local function count(names,want)
    local n=0
    for _,name in ipairs(names) do if name==want then n=n+1 end end
    return n
end

--- Puts a live bullet on the soul, so the next Player.Update runs the real
--- `b.isBullet` collision test against it.
local function bulletOnSoul()
    for _,spr in ipairs(Sprites.images) do spr.isBullet=false end
    local bullet=Sprites.CreateSprite("bullet.png","Bullets")
    bullet:MoveTo(Player.sprite:GetPosition())
    bullet.isBullet=true
    return bullet
end

local function run()
    -- The scene installs its OnHit before DEFENDING, so wait for that state.
    local tries=0
    while Battle.state~="DEFENDING" and tries<600 do frames(1); tries=tries+1 end
    assert(Battle.state=="DEFENDING","battle never reached DEFENDING")

    local stop=recordSounds()

    -- A bullet on the soul costs HP and must be heard.
    Player.hp=Player.maxhp
    local bullet=bulletOnSoul()
    frames(2)
    local names=stop()
    assert(Player.hp<Player.maxhp,"the bullet must actually hurt the soul")
    assert(count(names,HURT)>0,
        "a bullet hit must play "..HURT..", got: "..table.concat(names,", "))

    -- The resolved path is a real file, and it is the requested sample.
    local resolved=Audio.ResolvePath("sound",HURT)
    local info=love.filesystem.getInfo(resolved)
    assert(info and info.type=="file","hurt sound does not resolve to a file: "..resolved)
    local played=love.filesystem.read(resolved)
    local want=love.filesystem.read(SOURCE)
    assert(played and want and played==want,
        resolved.." is not byte-identical to Resources/Sounds/snd_hurt1.wav")

    -- Invincibility: the soul is still blinking, so a second bullet is silent.
    bullet:Destroy()
    bulletOnSoul()
    local before=Player.hp
    frames(1)
    local stop2=recordSounds()
    frames(3)
    names=stop2()
    assert(Player.hp==before,"an invincible soul must not take the second bullet")
    assert(count(names,HURT)==0,"an invincible soul must not cry out again")

    print("[OK] hurt sound: bullet hit plays "..HURT.." (== snd_hurt1.wav), invincibility stays quiet")
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
