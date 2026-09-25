local project=love.filesystem.getWorkingDirectory()
assert(love.filesystem.mountFullPath(project,"","read",true))
dofile(project.."/conf.lua")
local configure=love.conf
function love.conf(t) configure(t); t.identity="spin-chara-act-recall" end
function love.errorhandler(message)
    io.stderr:write(debug.traceback(tostring(message)),"\n"); os.exit(1)
end
