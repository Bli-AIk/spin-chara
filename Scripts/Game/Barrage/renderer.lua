-- Barrage-only rendering; enemies, HUD and dialogue belong to the engine.
local R={}
local Clip=require("Scripts.Game.Barrage.clip")
local Lighting=require((...):match("(.-)[^%.]+$").."lighting")
local CurtainPreview=require((...):match("(.-)[^%.]+$").."curtain-preview")
R.__index=R
local g=love.graphics
local function rect(x,y,w,h,color)
    g.setColor(color or {1,1,1}); g.rectangle("fill",x,y,w,h)
end
function R.new()
    local self=setmetatable({assets={}},R)
    for key,path in pairs({knife="Attacks/Monsters/spr_dummyknife_0.png",
        heart="Soul Library Sprites/spr_default_heart.png"}) do
        self.assets[key]=g.newImage("Resources/Sprites/"..path)
    end
    return self
end
function R:draw(m,presentation,debugUnlit)
    if m.round==6 then CurtainPreview.draw(m,self.assets,debugUnlit); return end
    local dark=m.dark and not debugUnlit
    local a=self.assets
    g.push("all")
    -- DEFENDING layout: centred arena, lower-right status, no action menu.
    local arenas={m.arena}
    if m.otherArena then arenas[#arenas+1]=m.otherArena end
    for _,box in ipairs(arenas) do
        rect(box.x-box.w/2-4,box.y-box.h/2-4,box.w+8,box.h+8)
        rect(box.x-box.w/2,box.y-box.h/2,box.w,box.h,{0,0,0})
    end
    Clip.arenas(arenas)
    if not debugUnlit then Lighting.drawLights(m.lights,m.lightStyle) end
    local pixelLighting=Lighting.beginBullets(m.lights,m.lightStyle,dark,m.player)
    for _,k in ipairs(m.knives) do
        local opacity=(k.alpha or (k.warning and .5 or 1))
        if not pixelLighting then opacity=opacity*Lighting.bulletAlpha(m.lights,k.x,k.y,dark) end
        g.setColor(1,1,1,opacity)
        g.draw(a.knife,k.x,k.y,k.angle,k.scale,k.scale,30,30)
    end
    Lighting.endBullets(pixelLighting)
    g.setStencilState()
    if presentation and presentation.fx then presentation.fx:Draw() end
    local p=m.player
    local playerAlpha=p.hurt>0 and (math.floor(p.hurt*16)%2==0 and .4 or 1) or 1
    if not debugUnlit then Lighting.drawPlayerGlow(p,m.lights,playerAlpha) end
    local bodyBrightness=Lighting.playerBodyBrightness(p,m.lights,dark,m.darkAmount)
    g.setColor(bodyBrightness,0,0,playerAlpha)
    g.draw(a.heart,p.x,p.y,0,1,1,8,8)
    if m.curtain then CurtainPreview.drawOverlay(m,a,debugUnlit) end
    -- Both the heart and its faint emission live inside the scene lighting.
    Lighting.drawMask(m.lights,dark,m.lightStyle,m.darkAmount,arenas)
    if not debugUnlit and not m.curtain then Lighting.drawPlayerEmission(a.heart,p,m.lights,playerAlpha,bodyBrightness) end
    g.pop()
end
return R
