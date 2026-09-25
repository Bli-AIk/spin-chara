local L={}
L.ADOPTED_STYLE=2
L.ADOPTED_LABEL="1B 小核心 / 距离衰减"
L.circlePath="Resources/Sprites/Shapes/circle.png"
-- The repository's authored, binary-alpha circle supplies every contour.
-- Only narrow layer widths and brightness differ; no procedural pixel grid.
L.styles={
    {spread=8,middle=.24,outer=.07,floor=.48},
    -- B: white core extended halfway into the original first grey band.
    -- Keep the original outer-band positions and 105px visibility cutoff.
    -- from the light centre (~three 35px knives in the comparison scene).
    {spread=12,middle=.30,outer=.09,floor=0,coreScale=34/38,ringBase=26/38,reach=105},
    {spread=16,middle=.22,outer=.05,floor=.42},
    {spread=10,middle=.18,outer=.045,floor=.56},
}
local shader,circle
-- Match lightAt's outermost rendered disc, not the knife visibility cutoff.
function L.outerRadius(radius,style)
    local profile=L.styles[style or L.ADOPTED_STYLE]
    return math.max(radius*(profile.coreScale or 1),profile.reach or radius+profile.spread)
end
local function lightingShader()
    if not shader then
        circle=love.graphics.newImage(L.circlePath)
        circle:setFilter("nearest","nearest")
        shader=love.graphics.newShader([[
            extern Image circleSprite;
            extern vec4 lamps[2];
            extern vec2 expansion;
            extern float darkAmount;
            extern int lampCount;
            extern vec4 profile;
            extern vec3 extent;
            extern vec3 soul;
            extern int renderPass;
            extern vec4 arenas[3];
            extern int arenaCount;
            float disc(vec2 p,vec2 centre,float radius) {
                if(radius<=0.0) return 0.0;
                vec2 uv=(p-centre)/(2.0*radius)+0.5;
                if(uv.x<0.0 || uv.x>=1.0 || uv.y<0.0 || uv.y>=1.0) return 0.0;
                return Texel(circleSprite,uv).a;
            }
            float lightAt(vec2 p,vec4 lamp,float growth) {
                vec2 centre=floor(lamp.xy+0.5);
                float radius=lamp.z*extent.x;
                float core=disc(p,centre,radius);
                if(extent.y>0.0) {
                    float light=core;
                    for(int i=1;i<=5;i++) {
                        // lamp.w includes this light's reach and expansion.
                        float ringRadius=mix(lamp.z*extent.z,lamp.w,float(i)/5.0);
                        float brightness=0.30*pow(0.48,float(i-1));
                        light=max(light,disc(p,centre,ringRadius)*brightness);
                    }
                    return light;
                }
                float middle=disc(p,centre,lamp.z+profile.x*growth*0.5);
                float outer=disc(p,centre,lamp.z+profile.x*growth);
                return max(core,max(middle*profile.y,outer*profile.z));
            }
            float bladeAt(vec2 p,vec4 lamp,float growth) {
                if(growth<=0.0) return 0.0;
                if(extent.y>0.0) {
                    float d=distance(p,lamp.xy);
                    return 1.0-smoothstep(lamp.z*extent.x,lamp.w,d);
                }
                return mix(profile.w,1.0,lightAt(p,lamp,growth));
            }
            vec4 effect(vec4 color,Image texture,vec2 uv,vec2 screen) {
                float light=0.0;
                float blade=0.0;
                for(int i=0;i<2;i++) {
                    if(i<lampCount) {
                        light=max(light,lightAt(screen,lamps[i],expansion[i]));
                        blade=max(blade,bladeAt(screen,lamps[i],expansion[i]));
                    }
                }
                if(renderPass==1) {
                    float inside=0.0;
                    for(int i=0;i<3;i++) {
                        if(i<arenaCount) {
                            vec4 box=arenas[i];
                            inside=max(inside,step(box.x,screen.x)*step(box.y,screen.y)
                                *step(screen.x,box.x+box.z)*step(screen.y,box.y+box.w));
                        }
                    }
                    light*=inside;
                    return vec4(0.0,0.0,0.0,0.52*(1.0-light)*darkAmount);
                }
                if(renderPass==2) {
                    vec4 pixel=Texel(texture,uv)*color;
                    // A small independent red source can reveal nearby blades
                    // even outside the white spotlight's visibility radius.
                    float red=soul.z*(1.0-smoothstep(8.0,28.0,distance(screen,soul.xy)));
                    float visibility=max(blade,red);
                    pixel.rgb*=vec3(visibility,blade,blade)/max(visibility,0.0001);
                    pixel.a*=visibility;
                    return pixel;
                }
                return vec4(1.0,1.0,1.0,light);
            }
        ]])
        shader:send("circleSprite",circle)
    end
    return shader
end
local function prepare(lights,style,renderPass,player,darkAmount,arenas)
    local s=lightingShader()
    local p=L.styles[style or 2]
    s:send("profile",{p.spread,p.middle,p.outer,p.floor})
    s:send("extent",{p.coreScale or 1,p.reach or 0,p.ringBase or p.coreScale or 1})
    s:send("lampCount",math.min(2,#lights))
    s:send("soul",player and #lights>0 and {player.x,player.y,.50} or {0,0,0})
    local a,b=lights[1],lights[2]
    local function lamp(light)
        if not light then return {0,0,0,0} end
        return {light.x,light.y,light.r,(light.fadeRadius or p.reach or 105)*(light.expansion or 1)}
    end
    s:send("expansion",{a and (a.expansion or 1) or 0,b and (b.expansion or 1) or 0})
    s:send("lamps",lamp(a),lamp(b))
    s:send("darkAmount",darkAmount or 1)
    s:send("renderPass",renderPass)
    local first,second,third=arenas and arenas[1],arenas and arenas[2],arenas and arenas[3]
    local function box(arena)
        return arena and {arena.x-arena.w/2,arena.y-arena.h/2,arena.w,arena.h} or {0,0,0,0}
    end
    s:send("arenaCount",arenas and math.min(3,#arenas) or 0)
    s:send("arenas",box(first),box(second),box(third))
    return s
end
local function drawPass(lights,style,pass,darkAmount,arenas)
    local g=love.graphics
    g.push("all"); g.setShader(prepare(lights,style,pass,nil,darkAmount,arenas)); g.setColor(1,1,1)
    g.rectangle("fill",0,0,640,480); g.pop()
end
function L.drawLights(lights,style) drawPass(lights,style,0) end
function L.drawPlayerGlow(player,lights,alpha)
    if #lights==0 then return end
    lightingShader() -- Load the same authored circle used by the spotlight.
    local g=love.graphics
    g.push("all"); g.setShader(); g.setBlendMode("add","alphamultiply")
    local x,y=math.floor(player.x+.5),math.floor(player.y+.5)
    for _,layer in ipairs({{17,.045},{13,.06},{10,.10}}) do
        g.setColor(1,0,0,layer[2]*(alpha or 1))
        local scale=layer[1]*2/circle:getWidth()
        g.draw(circle,x,y,0,scale,scale,circle:getWidth()/2,circle:getHeight()/2)
    end
    g.pop()
end
-- Body brightness only: the independent red halo and blade illumination keep
-- their original radius and power.
function L.playerBodyBrightness(player,lights,dark,amount)
    if not dark then return 1 end
    local visibility=L.bulletAlpha(lights,player.x,player.y,true,L.ADOPTED_STYLE)
    return 1-.5*(1-visibility)*(amount or 1)
end
function L.drawPlayerEmission(image,player,lights,alpha,brightness)
    if #lights==0 then return end
    local g=love.graphics
    g.push("all"); g.setShader(); g.setBlendMode("add","alphamultiply")
    -- Small self-emission after the environmental mask, not full-bright red.
    g.setColor(brightness or 1,0,0,.14*(alpha or 1))
    g.draw(image,player.x,player.y,0,1,1,8,8)
    g.pop()
end
-- Approximate point visibility for headless checks; actual rendering samples
-- the circle sprite per fragment, including blades that straddle a boundary.
function L.bulletAlpha(lights,x,y,dark,style)
    if not dark then return 1 end
    local p=L.styles[style or 2]
    if p.reach then
        local alpha=0
        for _,light in ipairs(lights) do
            local d=math.sqrt((x-light.x)^2+(y-light.y)^2)
            local core=light.r*p.coreScale
            local reach=(light.fadeRadius or p.reach)*(light.expansion or 1)
            if reach>core then
                local t=math.max(0,math.min(1,(d-core)/(reach-core)))
                alpha=math.max(alpha,1-t*t*(3-2*t))
            end
        end
        return alpha
    end
    local distance=math.huge
    for _,light in ipairs(lights) do
        distance=math.min(distance,math.sqrt((x-light.x)^2+(y-light.y)^2)-light.r)
    end
    local light=distance<=0 and 1 or distance<=p.spread*.5 and p.middle or distance<=p.spread and p.outer or 0
    return p.floor+(1-p.floor)*light
end
function L.beginBullets(lights,style,dark,player)
    if not dark then return false end
    love.graphics.push("all"); love.graphics.setShader(prepare(lights,style,2,player))
    return true
end
function L.endBullets(active) if active then love.graphics.pop() end end
function L.drawMask(lights,dark,style,amount,arenas) if dark then drawPass(lights,style,1,amount,arenas) end end
return L
