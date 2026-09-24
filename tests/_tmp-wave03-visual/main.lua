local project=love.filesystem.getWorkingDirectory()
dofile(project.."/main.lua")
local gameLoad,gameUpdate,gameDraw=love.load,love.update,love.draw
local task,lastStage
local function frames(n) for _=1,n do coroutine.yield() end end
local function run()
    frames(5)
    local real=Controller.GetState
    Controller.GetState=function(name)
        if name=="confirm" then return 1 end
        if name=="cancel" then return 1 end
        return real(name)
    end
    local model=assert(Battle._wave and Battle._wave.barrage)
    for _=1,1800 do
        frames(1)
        if model.stage~=lastStage then
            lastStage=model.stage
            love.graphics.captureScreenshot("tmp-wave03-stage"..lastStage..".png")
            print("stage",lastStage,"arena",model.arena.x,model.arena.y,model.arena.w,model.arena.h)
        end
        if model.stage==5 and model.phaseTime>.1 and not shot then shot=true; love.graphics.captureScreenshot("tmp-wave03-beat.png") end
        if model.done then break end
    end
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
function love.draw() gameDraw() end
