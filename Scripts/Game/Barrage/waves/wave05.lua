local C=require((...):match("(.-)[^%.]+$").."common")
local Knife=require((...):match("(.-)waves%.").."knife")
local W={arena={x=320,y=290,w=180,h=290},stages={"刀尖与聚光灯", "第一对刀排", "第二对刀排", "第三对刀排", "最后一对刀排", "收束"}}
function W.enter(m)
    local a,c=m.arena,m.config
    m.lights={C.light(a.x,a.y-a.h/2+55,c.radius)}
    m.caption=m.stage==1 and {"Chara","Wave05.Intro"} or nil
    for x=a.x-a.w/2+6,a.x+a.w/2-6,c.spacing do
        local k=m:knife(x,a.y-a.h/2-8,math.pi/2,1)
        k.kind,k.baseY,k.state,k.clock="top",k.y,"idle",0
    end
    if m.stage>=2 and m.stage<=5 then
        local level=a.y+a.h/2-22-(m.stage-2)*45
        for row=0,1 do
            for x=a.x-a.w/2+6,a.x+a.w/2-6,c.spacing do
                local k=m:knife(x,level+row*24,-math.pi/2,1)
                k.kind,k.baseY,k.row="bottom",k.y,row
            end
        end
    end
end
function W.update(m,dt,bulletDt)
    local c=m.config
    local bottomDone=true
    for _,k in ipairs(m.knives) do
        if k.kind=="top" then
            k.clock=k.clock+bulletDt
            if k.state=="idle" then
                local x,y=Knife.tip(k)
                if m.player.y>=y-2 and math.abs(m.player.x-x)<=10
                    and (m.player.x-x)^2+(m.player.y-y)^2<c.triggerDistance^2 then k.state,k.clock="warn",0 end
            elseif k.state=="warn" and k.clock>=c.warning then k.state,k.clock="out",0
            elseif k.state=="out" and k.clock>=c.thrustTime then k.state,k.clock="hold",0
            elseif k.state=="hold" and k.clock>=c.hold then k.state,k.clock="back",0
            elseif k.state=="back" and k.clock>=c.thrustTime*1.7 then k.state,k.clock="cooldown",0
            elseif k.state=="cooldown" and k.clock>=1 then k.state,k.clock="idle",0 end
            local reach=0
            if k.state=="out" then reach=C.ease(k.clock/c.thrustTime)
            elseif k.state=="hold" then reach=1
            elseif k.state=="back" then reach=1-C.ease(k.clock/(c.thrustTime*1.7)) end
            k.y=k.baseY+c.thrustLength*reach
            k.active=k.state~="warn"; k.warning=k.state=="warn"
        else
            -- Both rows appear together, extend and withdraw before the next pair.
            local t=m.attackTime-c.warning
            local out,hold,back=c.thrustTime,c.hold,c.thrustTime*1.7
            local reach=0
            if t>=0 and t<out then reach=C.ease(t/out)
            elseif t>=out and t<out+hold then reach=1
            elseif t>=out+hold then reach=1-C.ease((t-out-hold)/back) end
            k.y=k.baseY-c.thrustLength*.65*reach
            k.active=t>=0 and t<out+hold+back
            k.warning=t<0
            if t<out+hold+back+c.hold then bottomDone=false end
        end
    end
    if m.stage==1 and m.phaseTime>1 and m:dialogueDone() then m:next()
    elseif m.stage>=2 and m.stage<=5 and bottomDone then
        local settled=true
        for _,k in ipairs(m.knives) do
            if k.kind=="top" and k.state~="idle" and k.state~="cooldown" then settled=false end
        end
        if settled then m:next() end
    elseif m.stage==6 and m.phaseTime>1.5 then m:next() end
end
return W
