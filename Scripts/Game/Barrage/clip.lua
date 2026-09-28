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
-- Everything above each arena's lower edge. Unlike C.arenas this keeps the
-- outside drawable, so a bullet that falls in from beyond the frame is drawn
-- on the way down and still cut by the edge it goes out through: the part that
-- has entered the box is what you see, and a bullet leaving by the bottom
-- shrinks to nothing there instead of being drawn over the frame and deleted
-- whole, in plain sight, past the box.
function C.exceptBelow(arenas)
    local g=love.graphics
    local shader=g.getShader()
    local _,height=g.getDimensions()
    g.setShader()
    g.setStencilState()
    g.clear(false,true,false)
    g.setColorMask(false)
    g.setStencilState("replace","always",1)
    for _,a in ipairs(arenas) do
        g.push()
        g.translate(a.x,a.y)
        g.rotate(a.rotation or 0)
        -- Twice the screen height reaches past the bottom from any placement,
        -- a rotated arena included, without a per-arena clip computation.
        g.rectangle("fill",-a.w/2,a.h/2,a.w,height*2)
        g.pop()
    end
    g.setColorMask(true)
    g.setStencilState("keep","equal",0)
    g.setShader(shader)
end
return C
