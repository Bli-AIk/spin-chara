local Slash = { WARNING = 0.45, OPEN_TIME = 0.16, SWEEP_TIME = 0.34 }
local SWEEP_SPEED = 1200 * 1.5
local FALL_HOLD, FALL_DURATION = 0.7, 1.9 / math.sqrt(1.7)
local WHITE = {1, 1, 1}
local function clamp(t) return math.max(0, math.min(1, t)) end
local function out(t) return 1 - (1 - clamp(t)) ^ 3 end
local function round(v) return math.floor(v + 0.5) end

local function rect(x, y, w, h, color, alpha)
    SE.graphics.setColor(color[1], color[2], color[3], alpha or 1)
    SE.graphics.rectangle("fill", x, y, w, h)
end

local function polygon(points, color, alpha, grid)
    grid = grid or 2
    local lo, hi = math.huge, -math.huge
    for _, p in ipairs(points) do lo, hi = math.min(lo, p[2]), math.max(hi, p[2]) end
    lo = math.max(-16, math.floor(lo / grid) * grid)
    hi = math.min(CANVAS_HEIGHT + 16, math.ceil(hi / grid) * grid)
    SE.graphics.setColor(color[1], color[2], color[3], alpha or 1)
    for y = lo, hi - grid, grid do
        local sy, xs = y + grid / 2, {}
        for i, a in ipairs(points) do
            local b = points[i % #points + 1]
            if (a[2] <= sy and b[2] > sy) or (b[2] <= sy and a[2] > sy) then
                xs[#xs + 1] = a[1] + (sy - a[2]) * (b[1] - a[1]) / (b[2] - a[2])
            end
        end
        table.sort(xs)
        for i = 1, #xs - 1, 2 do
            local left = math.ceil((xs[i] - grid / 2) / grid) * grid
            local right = math.ceil((xs[i + 1] - grid / 2) / grid) * grid
            if right > left then SE.graphics.rectangle("fill", left, y, right - left, grid) end
        end
    end
end

function Slash.New(arena)
    local fx = Sprites.CreateSprite("px.png", "TopAll")
    local destroySprite = fx.Destroy
    fx:MoveTo(arena.x, arena.y)
    fx.spin_damage = 10
    fx.time, fx.age, fx.particles = 0, -Slash.WARNING, {}
    fx.struck = false
    fx.cut_x = arena.x
    fx.top = arena.y - arena.height / 2 - arena.thickness
    fx.bottom = arena.y + arena.height / 2 + arena.thickness
    fx.tip_start = fx.top + 15
    fx.bottom_delay = math.max(0, (fx.bottom - fx.tip_start) / SWEEP_SPEED)
    local ownedShake, previousShake

    local function releaseShake()
        if ownedShake and Camera.shaker == ownedShake then Camera.shaker = previousShake end
        ownedShake, previousShake = nil, nil
    end

    local function emit(x, y, count, blood, delay)
        for _ = 1, count do
            local angle = math.random() * math.pi * 2
            local speed = (blood and 75 or 105) + math.random() * (blood and 110 or 210)
            local hold = 0.18 + math.random() * 0.06
            fx.particles[#fx.particles + 1] = {
                x = x + (math.random() - 0.5) * (blood and 3 or 10), y = y,
                vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
                drag = 4 + math.random() * 3,
                width = math.random() < 0.6 and 1 or 2,
                length = 3 + math.random() * 4,
                rotation = math.random() * math.pi, spin = (math.random() - 0.5) * 24,
                born = delay + math.random() * 0.012,
                hold = hold, life = hold + 0.22 + math.random() * 0.08,
                dot = blood or math.random() < 0.4, blood = blood,
            }
        end
    end
    emit(fx.cut_x, fx.top, 9, false, 0)
    emit(fx.cut_x, fx.bottom, 9, false, fx.bottom_delay)

    function fx:Blood(x, y)
        emit(x, y, 4, true, math.max(0, self.age))
    end

    function fx:Strike()
        self.struck = true
        self.time, self.age = Slash.WARNING, 0
    end

    function fx:DropHalf(arenaToDrop, direction)
        self.falling = {
            x = arenaToDrop.x, y = arenaToDrop.y,
            width = arenaToDrop.width, height = arenaToDrop.height,
            thickness = arenaToDrop.thickness, direction = direction,
            color = {unpack(arenaToDrop.white.color)},
            start = Slash.OPEN_TIME + FALL_HOLD,
        }
    end

    function fx:Update(dt)
        if self.destroyed then return end
        self.time = self.time + dt
        self.age = self.struck and (self.time - Slash.WARNING) or -Slash.WARNING
        local a = self.age
        if a >= 0 and a < 0.18 then
            if not ownedShake then
                previousShake = Camera.shaker
                ownedShake = {_time = 0, x = 0, y = 0}
                Camera.shaker = ownedShake
            end
            local decay = (1 - a / 0.18) ^ 2
            ownedShake.x = round(math.sin(a * 115) * 6.5 * 0.7 * decay)
            ownedShake.y = round(math.cos(a * 160) * 6.5 * 1.2 * decay)
        else
            releaseShake()
        end
        local f = self.falling
        if f then
            local t = math.max(0, a - f.start)
            local progress = clamp(t / FALL_DURATION)
            local descent = progress * progress
            f.draw_x = f.x + f.direction * 10 * descent
            f.draw_y = f.y + 300 * descent
            f.angle = f.direction * math.rad(6) * descent
            f.gone = progress >= 1
        end
    end

    function fx:Finished()
        if self.age < 0.6 or not self.falling or not self.falling.gone then return false end
        for _, p in ipairs(self.particles) do
            if self.age < p.born + p.life then return false end
        end
        return true
    end

    function fx:Draw()
        if self.destroyed then return end
        local a, x = self.age, self.cut_x
        SE.graphics.push("all")
        SE.graphics.setShader()
        local f = self.falling
        if f and not f.gone then
            SE.graphics.push()
            SE.graphics.translate(f.draw_x or f.x, f.draw_y or f.y)
            SE.graphics.rotate(f.angle or 0)
            local b = f.thickness
            rect(-f.width / 2 - b, -f.height / 2 - b, f.width + 2*b, f.height + 2*b, f.color)
            rect(-f.width / 2, -f.height / 2, f.width, f.height, {0, 0, 0})
            SE.graphics.pop()
        end
        if a < 0 then
            local tick = math.min(3, math.floor(self.time / (Slash.WARNING / 4) + 1e-7))
            local yellow = tick % 2 == 1
            rect(x - 1, 0, 2, CANVAS_HEIGHT, yellow and {1, 240/255, 56/255} or {245/255, 30/255, 50/255})
        else
            if a < 0.028 then rect(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT, {1, 245/255, 229/255}, 0.26*(1-a/0.028)) end
            if a < Slash.SWEEP_TIME then
                local tip = self.tip_start + SWEEP_SPEED * a
                local tail, w = tip - 450, 27 * (0.7 + 0.3 * out(a / 0.018))
                local fade = 1 - clamp((a - 0.24) / 0.10)
                polygon({{x-1,tail-48},{x-4,tail+125},{x-1-w*.3,tip-94},{x-1,tip-16},{x+1,tip-95},{x,tail+135}}, {1,232/255,216/255}, fade*.28)
                polygon({{x,tail},{x+3,tail+115},{x+w*.3,tip-145},{x+w*.5,tip-72},{x+1,tip},{x-2,tip-22},{x-w*.48,tip-83},{x-3,tail+105}}, {1,254/255,249/255}, fade)
                polygon({{x-2,tip-64},{x+3,tip-91},{x+2,tip+8},{x,tip+18}}, WHITE, fade)
            end
            for i, y in ipairs({self.top, self.bottom}) do
                local t = a - (i == 1 and 0 or self.bottom_delay)
                if t >= 0 and t < .085 then
                    local fade, reach = 1-t/.085, 12+22*out(t/.085)
                    polygon({{x-reach,y},{x-4,y-2},{x,y-7*fade},{x+4,y-2},{x+reach,y},{x+4,y+2},{x,y+9*fade},{x-4,y+2}}, WHITE, fade)
                end
            end
            for _, p in ipairs(self.particles) do
                local t = a - p.born
                if t >= 0 and t < p.life then
                    local travel = (1 - math.exp(-p.drag * t)) / p.drag
                    local px, py = p.x+p.vx*travel, p.y+p.vy*travel
                    local alpha = (1-clamp((t-p.hold)/(p.life-p.hold))) ^ 2
                    local color = p.blood and {1,39/255,60/255} or WHITE
                    if p.dot then
                        rect(round(px), round(py), p.width, p.width, color, alpha)
                    else
                        local angle = p.rotation + p.spin * travel
                        local c, s = math.cos(angle), math.sin(angle)
                        local points = {}
                        for _, q in ipairs({{-p.length/2,-p.width/2},{p.length/2,-p.width/2},{p.length/2,p.width/2},{-p.length/2,p.width/2}}) do
                            points[#points+1] = {px+q[1]*c-q[2]*s, py+q[1]*s+q[2]*c}
                        end
                        polygon(points, color, alpha, 1)
                    end
                end
            end
        end
        SE.graphics.pop()
    end

    function fx:Destroy()
        if self.destroyed then return end
        self.destroyed = true
        releaseShake()
        destroySprite(self)
    end
    return fx
end

return Slash
