local project=love.filesystem.getWorkingDirectory()
assert(love.filesystem.mountFullPath(project,"","read",true))
dofile(project.."/conf.lua")
local configure=love.conf
function love.conf(t)
    configure(t)
    t.identity="spin-chara-wave03-visual-tmp"
    t.window.width=920
    t.window.height=640
end
