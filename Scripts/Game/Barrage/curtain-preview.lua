local P=(...):match("(.-)[^%.]+$")
local Cloth=require(P.."cloth")
local Clip=require(P.."clip")
local Lighting=require(P.."lighting")
local C={labels={},ENTER_TIME=2.15,EXIT_TIME=1.0,
    ADOPTED={clothStyle=2,entryVariant=2,touchGain=2}}
local function clamp(t) return math.max(0,math.min(1,t)) end
local function smooth(t) t=clamp(t); return t*t*(3-2*t) end
C.entryVariants={
    {label="A · 轻弹 1.5%",amount=.015},
    {label="B · 小弹 2.5%",amount=.025},
    {label="C · 中弹 4%",amount=.04},
    {label="D · 大弹 6%",amount=.06},
}
function C.laying(time,variant)
    local t=clamp(time/C.ENTER_TIME)
    local amount=C.entryVariants[variant or 2].amount
    if t<.64 then
        local u=t/.64
        -- Quintic ease starts more gently than the previous cubic fall.
        return (1+amount)*(u*u*u*(10+u*(-15+6*u)))
    end
    if t<.88 then return 1+amount-amount*1.28*smooth((t-.64)/.24) end
    return 1-amount*.28+amount*.28*smooth((t-.88)/.12)
end
function C.transition(m,kind)
    m.clothTransition={kind=kind,time=0}
end
function C.applyAdopted(m)
    m.curtainStyle=C.ADOPTED.clothStyle
    m.entryVariant=C.ADOPTED.entryVariant
    m.touchGain=C.ADOPTED.touchGain
end
function C.pose(m)
    local transition=m.clothTransition
    if not transition then return 0,1 end
    local c=m.clothState
    local travel=c.y+c.h+40
    if transition.kind=="enter" then
        return 0,1
    end
    local t=clamp(transition.time/C.EXIT_TIME)
    return -travel*t*t,1+.22*math.sin(t*math.pi)
end
for i,p in ipairs(C.entryVariants) do C.labels[i]=p.label end
function C.updateCloth(m,dt,previousPlayer,previousKnives)
    if not m.clothState then m.clothState=Cloth.new(m.arena,m.curtainStyle or 2) end
    local p=m.player
    local old=previousPlayer or {x=p.oldX or p.x,y=p.oldY or p.y}
    local contacts={{x=p.x,y=p.y,ox=old.x,oy=old.y,radius=28,strength=1,player=true,gain=m.touchGain or 2}}
    for i,k in ipairs(m.knives) do
        local oldKnife=previousKnives and previousKnives[i]
        local ox,oy=oldKnife and oldKnife.x or k.oldX or k.x,oldKnife and oldKnife.y or k.oldY or k.y
        -- A newly spawned knife has no velocity/contact impulse.
        if math.abs(k.x-ox)+math.abs(k.y-oy)<40 then
            contacts[#contacts+1]={x=k.x,y=k.y,ox=ox,oy=oy,radius=19,strength=.035,gain=m.touchGain or 2}
        end
    end
    m.clothState:update(dt,contacts)
    if m.clothTransition then m.clothTransition.time=m.clothTransition.time+dt end
end
function C.new(style)
    local m={round=6,curtainStyle=C.ADOPTED.clothStyle,entryVariant=style,
        touchGain=C.ADOPTED.touchGain,clothTransition={kind="enter",time=0},elapsed=0,done=false,stage=1,
        arena={x=320,y=245,w=330,h=300},player={x=386,y=294,hp=20,hurt=0},lights={},knives={}}
    function m:update(dt,input)
        local previousPlayer={x=self.player.x,y=self.player.y}
        local previousKnives=self.knives
        self.elapsed=self.elapsed+dt
        local t=self.elapsed
        self.lights={{x=310+95*math.sin(t*.38),y=240+56*math.sin(t*.51),r=38}}
        local speed=input.slow and 60 or 120
        self.player.x=math.max(163,math.min(477,self.player.x+(input.dx or 0)*speed*dt))
        self.player.y=math.max(103,math.min(387,self.player.y+(input.dy or 0)*speed*dt))
        self.knives={}
        for row=0,5 do for col=0,5 do
            self.knives[#self.knives+1]={x=178+col*57+8*math.sin(t*.7+row),
                y=120+row*50,angle=-math.pi/3+.2*math.sin(t*.8),scale=1}
        end end
        C.updateCloth(self,dt,previousPlayer,previousKnives)
    end
    function m:destroy() if self.clothState then self.clothState:destroy() end; self.lights={}; self.knives={} end
    m:update(0,{dx=0,dy=0})
    return {model=m,camera={}}
end
local shader
local function getShader()
    if shader then return shader end
    shader=love.graphics.newShader([[
        extern Image displacement;
        extern vec4 bounds;
        extern vec2 gridSize;
        extern vec2 lamp;
        extern vec3 visibilityRange;
        extern vec2 soul;
        extern bool unlit;
        extern int pass;
        extern vec2 drapePose;
        extern float laying;
        vec3 field(vec2 p) {
            vec2 uv=clamp((p-bounds.xy)/bounds.zw,0.0,1.0);
            uv=(uv*(gridSize-1.0)+.5)/gridSize;
            return Texel(displacement,uv).rgb;
        }
        vec2 materialPoint(vec2 screen) {
            screen.y=bounds.y+(screen.y-bounds.y-drapePose.x)/drapePose.y;
            float drop=max(.002,laying);
            screen.y=bounds.y+(screen.y-bounds.y)/drop;
            vec2 p=screen;
            // The top starts straight. Physical folds progressively take over;
            // there is no rear plane, trapezoid or perspective widening.
            for(int i=0;i<2;i++) p=screen-field(p).xy*laying;
            return p;
        }
        float covered(vec2 screen) {
            vec2 p=materialPoint(screen);
            return step(bounds.x,p.x)*step(bounds.y,p.y)*step(p.x,bounds.x+bounds.z)*step(p.y,bounds.y+bounds.w);
        }
        vec4 effect(vec4 color,Image tex,vec2 uv,vec2 screen) {
            // Rasterise silhouette and contour on the game's 1px grid.
            vec2 p=floor(screen)+.5;
            if(laying<=0.0) return vec4(0.0);
            float mask=covered(p);
            if(mask<.5) return vec4(0.0);
            float lit=unlit ? 0.0:1.0-smoothstep(22.0,70.0,distance(p,lamp));
            float red=unlit ? 0.0:1.0-smoothstep(7.0,30.0,distance(p,soul));
            red*=lit;
            if(pass==1 || pass==2) {
                vec4 pixel=Texel(tex,uv)*color;
                float grey=.065+lit*.10;
                if(pass==2) {
                    pixel.rgb=vec3(.055+lit*.44,.009+lit*.025,.009+lit*.025);
                } else {
                    float white=unlit ? 1.0:visibilityRange.z*(1.0-smoothstep(visibilityRange.x,visibilityRange.y,distance(screen,lamp)));
                    float localRed=unlit ? 0.0:visibilityRange.z*.50*(1.0-smoothstep(8.0,28.0,distance(screen,soul)));
                    float visible=max(white,localRed);
                    pixel.rgb=vec3(grey)*vec3(visible,white,white)/max(visible,.0001);
                    pixel.a*=visible;
                }
                return pixel;
            }
            float outline=1.0-min(min(covered(p+vec2(4,0)),covered(p-vec2(4,0))),
                min(covered(p+vec2(0,4)),covered(p-vec2(0,4))));
            vec2 q=materialPoint(p);
            float z=field(q).z;
            vec2 gradient=vec2(field(q+vec2(3,0)).z-field(q-vec2(3,0)).z,
                               field(q+vec2(0,3)).z-field(q-vec2(0,3)).z)/6.0;
            vec3 normal=normalize(vec3(-gradient,1));
            float ridge=pow(max(0.0,dot(normal,normalize(vec3(-.8,-.3,.45)))),3.0);
            float checker=mod(floor(p.x)+floor(p.y),2.0);
            float fabric=.008+ridge*.035+checker*ridge*.012;
            // Same restrained transmission and shadow values as adopted D.
            vec3 surface=vec3(fabric+lit*.035)+vec3(red*.035,0,0);
            // A dark inward-facing lip makes the outer white hem read as thick.
            float lip=1.0-min(min(covered(p+vec2(5,0)),covered(p-vec2(5,0))),
                min(covered(p+vec2(0,5)),covered(p-vec2(0,5))));
            surface*=1.0-lip*.6;
            return vec4(mix(surface,vec3(.88+lit*.12),outline),1.0);
        }
    ]])
    return shader
end
function C.drawOverlay(m,assets,debugUnlit)
    if not m.clothState then C.updateCloth(m,0) end
    local cloth=m.clothState
    local g=love.graphics
    local s=getShader()
    local l=m.lights[1] or m.player
    g.push("all"); g.setStencilState()
    local offset,stretch=C.pose(m)
    s:send("drapePose",{offset,stretch})
    local t=m.clothTransition
    local laying=t and t.kind=="enter" and C.laying(t.time,m.entryVariant) or 1
    s:send("laying",laying)
    s:send("displacement",cloth:texture())
    s:send("bounds",{cloth.x,cloth.y,cloth.w,cloth.h})
    s:send("gridSize",{cloth.cols,cloth.rows})
    local profile=Lighting.styles[Lighting.ADOPTED_STYLE]
    local growth=l.expansion or 1
    s:send("visibilityRange",{l.r*profile.coreScale,(l.fadeRadius or profile.reach)*growth,#m.lights>0 and growth>0 and 1 or 0})
    s:send("lamp",{l.x,l.y}); s:send("soul",{m.player.x,m.player.y})
    s:send("unlit",not not debugUnlit)
    g.setShader(s); s:send("pass",0); g.setColor(1,1,1)
    -- Deliberately outside the battle stencil: the drape hides the frame itself.
    g.rectangle("fill",cloth.x-64,cloth.y+offset-40,cloth.w+128,cloth.h*stretch+80)
    -- Objects remain clipped to the arena even though the cloth covers its rim.
    local a=m.arena
    Clip.arenas({a})
    s:send("pass",1)
    for _,k in ipairs(m.knives) do
        g.setColor(1,1,1,k.alpha or (k.warning and .5 or 1))
        g.draw(assets.knife,k.x,k.y,k.angle,k.scale,k.scale,30,30)
    end
    s:send("pass",2); g.setColor(1,1,1)
    g.draw(assets.heart,m.player.x,m.player.y,0,1,1,8,8)
    g.pop()
end
function C.draw(m,assets,debugUnlit)
    local g=love.graphics
    local a=m.arena
    g.push("all"); g.clear(0,0,0,1)
    g.setColor(1,1,1); g.rectangle("fill",a.x-a.w/2-4,a.y-a.h/2-4,a.w+8,a.h+8)
    g.setColor(0,0,0); g.rectangle("fill",a.x-a.w/2,a.y-a.h/2,a.w,a.h)
    Clip.arenas({a})
    if not debugUnlit then Lighting.drawLights(m.lights,Lighting.ADOPTED_STYLE) end
    local active=Lighting.beginBullets(m.lights,Lighting.ADOPTED_STYLE,not debugUnlit,m.player)
    g.setColor(1,1,1)
    for _,k in ipairs(m.knives) do g.draw(assets.knife,k.x,k.y,k.angle,k.scale,k.scale,30,30) end
    Lighting.endBullets(active)
    g.setStencilState()
    if not debugUnlit then Lighting.drawPlayerGlow(m.player,m.lights,1) end
    local bodyBrightness=Lighting.playerBodyBrightness(m.player,m.lights,not debugUnlit)
    g.setColor(bodyBrightness,0,0); g.draw(assets.heart,m.player.x,m.player.y,0,1,1,8,8)
    Lighting.drawMask(m.lights,not debugUnlit,Lighting.ADOPTED_STYLE,nil,{a})
    if not debugUnlit then Lighting.drawPlayerEmission(assets.heart,m.player,m.lights,1,bodyBrightness) end
    C.drawOverlay(m,assets,debugUnlit)

    g.pop()
end
return C
