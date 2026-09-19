local action = {
    sprite = nil,
    can_move = true,
    is_moving = false
}

local speed = 2
local multiplier, inertia = 1, 0
local vx, vy, lastX, lastY = 0, 0, nil, nil

function action.ResetMotion()
    vx, vy, lastX, lastY = 0, 0, nil, nil
end

function action.SetMovementModifiers(scale, seconds)
    multiplier, inertia = scale or 1, seconds or 0
    action.ResetMotion()
end

---Controls the player's movement and behaviour.
---@param dt number|nil
function action.Update(dt)
    if (not action.sprite) then return end

    local can_move = action.can_move
    local sprite = action.sprite
    local up, down, left, right = Controller.GetState("up"), Controller.GetState("down"), Controller.GetState("left"), Controller.GetState("right")
    local cancel = Controller.GetState("cancel")

    if (cancel > 0) then
        speed = 1
    else
        speed = 2
    end

    if (not can_move) then action.ResetMotion(); return end
    if inertia > 0 then
        local step = Global.GetVariable("UseRealTime(dt)") and (dt or 1 / 60) or 1 / 60
        -- Arena collision may have clamped the previous position.
        if lastX and math.abs(sprite.x - lastX) > 0.001 then vx = 0 end
        if lastY and math.abs(sprite.y - lastY) > 0.001 then vy = 0 end
        local tx = ((right > 0 and 1 or 0) - (left > 0 and 1 or 0)) * speed * 60 * multiplier
        local ty = ((down > 0 and 1 or 0) - (up > 0 and 1 or 0)) * speed * 60 * multiplier
        local decay = math.exp(-step / inertia)
        sprite.x = sprite.x + tx * step + (vx - tx) * inertia * (1 - decay)
        sprite.y = sprite.y + ty * step + (vy - ty) * inertia * (1 - decay)
        vx, vy = tx + (vx - tx) * decay, ty + (vy - ty) * decay
        lastX, lastY = sprite.x, sprite.y
        action.is_moving = math.abs(vx) + math.abs(vy) > 0.01
        return
    end
    speed = speed * multiplier
    if (sprite) then
        if (Global.GetVariable("UseRealTime(dt)")) then
            if (up > 0) then sprite.y = sprite.y - speed * 60 * dt end
            if (down > 0) then sprite.y = sprite.y + speed * 60 * dt end
            if (left > 0) then sprite.x = sprite.x - speed * 60 * dt end
            if (right > 0) then sprite.x = sprite.x + speed * 60 * dt end
        else
            if (up > 0) then sprite.y = sprite.y - speed end
            if (down > 0) then sprite.y = sprite.y + speed end
            if (left > 0) then sprite.x = sprite.x - speed end
            if (right > 0) then sprite.x = sprite.x + speed end
        end
    end
end

return action
