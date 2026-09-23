local C={}
function C.arenas(arenas)
    local g=love.graphics
    local shader=g.getShader()
    g.setShader()
    g.setStencilState()
    g.clear(false,true,false)
    g.setColorMask(false)
    g.setStencilState("replace","always",1)
    for _,a in ipairs(arenas) do
        g.push()
        g.translate(a.x,a.y)
        g.rotate(a.rotation or 0)
        g.rectangle("fill",-a.w/2,-a.h/2,a.w,a.h)
        g.pop()
    end
    g.setColorMask(true)
    g.setStencilState("keep","equal",1)
    g.setShader(shader)
end
return C
