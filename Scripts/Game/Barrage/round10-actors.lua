-- Move the engine-owned actors; no duplicate sprites or per-frame scaling.
local A={}
function A.new(enemies)
    local actors={}
    for i=1,2 do
        local enemy=assert(enemies[i],'Finale actor missing')
        local animation=enemy.animation
        local sprite=assert(animation.sprite or animation.chara,'Finale sprite missing')
        actors[i]={animation=animation,sprite=sprite,x=sprite.x,y=sprite.y,
            visible=sprite.visible,running=animation.running}
        animation.running=false
    end
    return actors
end
function A.update(actors,m)
    local v=m.vars
    actors[1].sprite:MoveTo(v.charaX,120)
    actors[2].sprite:MoveTo(v.napX+52,actors[2].y)
end
function A.restore(actors,finished)
    for i,a in ipairs(actors) do
        a.animation.running=a.running
        a.sprite:MoveTo(a.x,a.y)
        a.sprite.visible=a.visible
        if finished and i==1 then a.sprite.visible=false end
    end
end
return A
