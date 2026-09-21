local C={}
function C.arenas(arenas)
    local g=love.graphics
    local shader=g.getShader()
    g.setShader()
    g.setStencilState()
    g.clear(false,true,false)
    g.setColorMask(false)
    g.setStencilState("replace","always",1)
    for _,a in ipairs(arenas) do g.rectangle("fill",a.x-a.w/2,a.y-a.h/2,a.w,a.h) end
    g.setColorMask(true)
    g.setStencilState("keep","equal",1)
    g.setShader(shader)
end
return C
