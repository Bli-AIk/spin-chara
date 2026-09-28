-- Real Nap presentation, fixed at the original battle size throughout a turn.
local Nap={}
Nap.__index=Nap
function Nap.New(pos)
    pos=pos or {520,120}
    local sprite=Sprites.CreateSprite('Characters/Napstablook/spr_napstabattle_0.png','UI')
    sprite:Scale(2,2)
    sprite:MoveTo(pos[1],pos[2])
    sprite:SetAnimation({'Characters/Napstablook/spr_napstabattle_0.png',
        'Characters/Napstablook/spr_napstabattle_1.png'},1/6)
    return setmetatable({sprite=sprite,cpos={pos[1],pos[2]},running=true,hurttime=0},Nap)
end
function Nap:Hurt() self.hurttime=.35 end
function Nap:Spare() self.sprite.alpha=.5 end
function Nap:Update(dt)
    if not self.running then return end
    if self.hurttime>0 then
        self.hurttime=math.max(0,self.hurttime-dt)
        self.sprite:MoveTo(self.cpos[1]+math.sin(self.hurttime*90)*self.hurttime*12,self.cpos[2])
        if self.hurttime==0 then self.sprite:MoveTo(self.cpos[1],self.cpos[2]) end
    end
end
function Nap:Destroy() self.sprite:Destroy() end
return Nap
