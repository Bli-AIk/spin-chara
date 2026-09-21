-- Blade geometry in source pixels, relative to the 60x60 image centre.
-- Handle, guard and transparent padding are deliberately excluded.
local K = {polygon = {-16,-2, -14,-4, 30,-4, 24,2, 16,6, -10,6, -16,2}}
function K.vertices(k, x, y, angle)
    local vertices, c, s = {}, math.cos(angle or k.angle), math.sin(angle or k.angle)
    for i = 1, #K.polygon, 2 do
        local px, py = K.polygon[i] * k.scale, K.polygon[i+1] * k.scale
        vertices[#vertices+1] = (x or k.x) + px*c - py*s
        vertices[#vertices+1] = (y or k.y) + px*s + py*c
    end
    return vertices
end
function K.tip(k)
    return k.x + 28*k.scale*math.cos(k.angle), k.y + 28*k.scale*math.sin(k.angle)
end
local function overlap(vertices, x, y)
    local axes = {1,0, 0,1}
    for i = 1, #vertices, 2 do
        local j = (i+1) % #vertices + 1
        axes[#axes+1] = -(vertices[j+1] - vertices[i+1])
        axes[#axes+1] = vertices[j] - vertices[i]
    end
    for i = 1, #axes, 2 do
        local ax, ay = axes[i], axes[i+1]
        local lo, hi = math.huge, -math.huge
        for j = 1, #vertices, 2 do
            local p = vertices[j]*ax + vertices[j+1]*ay
            lo, hi = math.min(lo,p), math.max(hi,p)
        end
        local centre, radius = x*ax+y*ay, 2*(math.abs(ax)+math.abs(ay))
        if centre+radius < lo or centre-radius > hi then return false end
    end
    return true
end
function K.hits(k, player)
    if not k.active then return false end
    local ox, oy, oa = k.oldX or k.x, k.oldY or k.y, k.oldAngle or k.angle
    local px, py = player.oldX or player.x, player.oldY or player.y
    -- Conservative swept bounds reject distant blades before allocating SAT
    -- polygons for every substep. Rotation remains inside the sprite radius.
    local radius=32*k.scale+2
    if math.max(ox,k.x)+radius<math.min(px,player.x)
        or math.min(ox,k.x)-radius>math.max(px,player.x)
        or math.max(oy,k.y)+radius<math.min(py,player.y)
        or math.min(oy,k.y)-radius>math.max(py,player.y) then return false end
    local travel = math.abs(k.x-ox) + math.abs(k.y-oy)
        + math.abs(k.angle-oa)*30*k.scale + math.abs(player.x-px) + math.abs(player.y-py)
    local steps = math.max(1, math.ceil(travel / 2))
    for i = 0, steps do
        local t = i/steps
        if overlap(K.vertices(k, ox+(k.x-ox)*t, oy+(k.y-oy)*t, oa+(k.angle-oa)*t),
            px+(player.x-px)*t, py+(player.y-py)*t) then return true end
    end
    return false
end
return K
