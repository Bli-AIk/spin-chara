-- Small 3-D position-based cloth grid, projected orthographically by the shader.
-- Fixed-step Verlet integration, structural/shear/bending distance constraints,
-- pinned suspension, gravity, damping, and local swept contact forces.
local Cloth={}; Cloth.__index=Cloth
Cloth.presets={
    {label="A · D光影 / 厚绒垂挂",margin=28,depth=10,damping=4.5,compliance=.10,touch=.8,folds=5},
    {label="B · D光影 / 宽松包覆",margin=40,depth=17,damping=2.8,compliance=.24,touch=1.1,folds=4},
    {label="C · D光影 / 密褶重帘",margin=32,depth=12,damping=6,compliance=.06,touch=.65,folds=8},
    {label="D · D光影 / 轻柔垂摆",margin=36,depth=14,damping=2,compliance=.3,touch=1.35,folds=6},
}
function Cloth.new(arena,style)
    local self=setmetatable({nodes={},edges={},cols=25,rows=21,accumulator=0},Cloth)
    self.preset=Cloth.presets[style or 1]
    local p=self.preset
    self.x,self.y=arena.x-arena.w/2-p.margin,arena.y-arena.h/2-24
    self.w,self.h=arena.w+p.margin*2,arena.h+60
    for j=0,self.rows-1 do for i=0,self.cols-1 do
        local u,v=i/(self.cols-1),j/(self.rows-1)
        local fold=math.cos(u*p.folds*math.pi*2)
        local x=self.x+u*self.w+math.sin(v*math.pi)*math.cos(u*math.pi)*5
        local y=self.y+v*self.h+3*math.sin(u*p.folds*math.pi)^2*(1-v)-((1-fold)*7+6*math.sin(u*math.pi*3)^2)*v^3
        local z=p.depth*fold*(.55+.45*v)
        self.nodes[#self.nodes+1]={x=x,y=y,z=z,px=x,py=y,pz=z,
            rx=self.x+u*self.w,ry=self.y+v*self.h,ax=x,ay=y,az=z,pinned=j==0}
    end end
    local function edge(a,b,stiffness)
        local x,y=self.nodes[a],self.nodes[b]
        self.edges[#self.edges+1]={a=a,b=b,rest=math.sqrt((x.x-y.x)^2+(x.y-y.y)^2+(x.z-y.z)^2),stiffness=stiffness}
    end
    for j=0,self.rows-1 do for i=0,self.cols-1 do
        local n=j*self.cols+i+1
        if i<self.cols-1 then edge(n,n+1,1) end
        if j<self.rows-1 then edge(n,n+self.cols,1) end
        if i<self.cols-1 and j<self.rows-1 then edge(n,n+self.cols+1,.75); edge(n+1,n+self.cols,.75) end
        if i<self.cols-2 then edge(n,n+2,.22) end
        if j<self.rows-2 then edge(n,n+self.cols*2,.22) end
    end end
    return self
end
local function distanceToSegment(x,y,c)
    local dx,dy=c.x-c.ox,c.y-c.oy
    local t=math.max(0,math.min(1,((x-c.ox)*dx+(y-c.oy)*dy)/math.max(.001,dx*dx+dy*dy)))
    return (x-c.ox-dx*t)^2+(y-c.oy-dy*t)^2
end
function Cloth:step(dt,contacts)
    local p=self.preset
    local damping=math.exp(-p.damping*dt)
    for _,n in ipairs(self.nodes) do
        if not n.pinned then
            local x,y,z=n.x,n.y,n.z
            n.x=x+(x-n.px)*damping
            n.y=y+(y-n.py)*damping+95*dt*dt
            n.z=z+(z-n.pz)*damping
            for _,c in ipairs(contacts or {}) do
                local velocity=math.max(-180,math.min(180,(c.x-c.ox)/dt))
                if math.abs(velocity)>.1 then
                    local weight
                    if c.player then
                        -- Direction drives the whole hanging sheet. No player
                        -- coordinate dependence; suspension attenuates the top.
                        weight=.25+.75*math.max(0,math.min(1,(n.ry-self.y)/self.h))
                    else
                        local d2=distanceToSegment(x,y,c)
                        weight=math.max(0,1-d2/(c.radius*c.radius))^2
                    end
                    local force=velocity*(c.strength or 1)*(c.gain or 1)*p.touch*weight
                    n.x=n.x+force*.4*dt*dt
                    n.z=n.z+force*.08*dt*dt
                end
            end
            n.px,n.py,n.pz=x,y,z
        end
    end
    for _=1,5 do
        for _,e in ipairs(self.edges) do
            local a,b=self.nodes[e.a],self.nodes[e.b]
            local dx,dy,dz=b.x-a.x,b.y-a.y,b.z-a.z
            local length=math.sqrt(dx*dx+dy*dy+dz*dz)
            local wa,wb=a.pinned and 0 or 1,b.pinned and 0 or 1
            if wa+wb>0 and length>1e-8 then
                local correction=(length-e.rest)/length*e.stiffness/(wa+wb+p.compliance)
                if wa>0 then a.x=a.x+dx*correction; a.y=a.y+dy*correction; a.z=a.z+dz*correction end
                if wb>0 then b.x=b.x-dx*correction; b.y=b.y-dy*correction; b.z=b.z-dz*correction end
            end
        end
    end
    self.dirty=true
end
function Cloth:update(dt,contacts)
    self.accumulator=self.accumulator+dt
    while self.accumulator>=1/120 do self:step(1/120,contacts); self.accumulator=self.accumulator-1/120 end
end
function Cloth:texture()
    if not self.image then
        self.data=love.image.newImageData(self.cols,self.rows,"rgba32f")
        self.image=love.graphics.newImage(self.data)
        self.image:setFilter("linear","linear")
        self.dirty=true
    end
    if self.dirty then
        for index,n in ipairs(self.nodes) do
            self.data:setPixel((index-1)%self.cols,math.floor((index-1)/self.cols),n.x-n.rx+n.z*.32,n.y-n.ry+n.z*.12,n.z,1)
        end
        self.image:replacePixels(self.data); self.dirty=false
    end
    return self.image
end
function Cloth:destroy()
    if self.image then self.image:release(); self.data:release(); self.image=nil end
end
return Cloth
