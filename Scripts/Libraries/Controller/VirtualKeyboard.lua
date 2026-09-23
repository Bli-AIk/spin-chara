--[[
    VirtualKeyboard.lua — 触屏虚拟按键（SoulEngine 移植版）

    素材和原始 LÖVE 触控实现来自 zzy（Bilibili UID 3546380257724712），贴图放在
    Resources/Sprites/UI/vk/。本文件是 SoulEngine 适配；Kristal 适配版见
    Bli-AIk/thrash-machine 的 libraries/virtualkeyboard。署名见仓库根 THIRD_PARTY.md。

    两种布局（VirtualKeyboard.Configure{ layout = "buttons" | "joystick" }）：
      buttons   左侧方向十字 + 右侧 Z/X/C（默认）
      joystick  左侧摇杆 + 右侧 Z/X/C

    行为要点：
      - 方向区按 X/Y 轴独立判定 → 支持斜向、滑动换向
      - 每个 touch id 独立绑定一个控件 → 可一边按住方向一边按动作键
      - 动作键支持按住不放、手指滑到另一个键上切换
      - 窗口够宽（两侧留白 ≥ 240 设计像素）时控件画在两侧空白区，否则画在 640x480 画面内
      - 桌面调试：鼠标左键等同触摸，可以直接点着试位置

    开关：F9 / PGUP / PGDN（VirtualKeyboard.toggleKey 可改），或 VirtualKeyboard.Toggle()。
    模拟输入仍走 Keyboard.SimulatePress / SimulateRelease，与真键盘同一套状态。
--]]

local gfx = setmetatable({}, {
    __index = function(t, key)
        local f = (SE and SE.graphics and SE.graphics[key]) or love.graphics[key]
        rawset(t, key, f)
        return f
    end,
})

local DESIGN_W = LOGICAL_WIDTH or 640
local DESIGN_H = LOGICAL_HEIGHT or 480

local MOUSE_TOUCH_ID = "__vk_mouse"

local VirtualKeyboard = {
    enabled = false,          -- 总开关（程序上是否接管触摸）
    visible = true,           -- 是否绘制（enabled 且 visible 才生效）
    autoDetect = true,        -- Android/iOS 上自动打开
    autoEnableOnTouch = true, -- 任何平台：一旦真收到触摸事件就自动打开（Termux:X11 靠这条）
    toggleKey = { "f9", "pageup", "pagedown" },  -- 开关键：字符串或数组（在 main.lua 的 keypressed 里调 HandleKey）
    layout = "buttons",       -- "buttons" | "joystick"
    target = "Keyboard",      -- "Keyboard"（模拟按键）| "Joystick"（模拟手柄）
    alpha = 0.78,
    assetRoot = "Resources/Sprites/UI/vk/",
    imageCache = {},
    buttons = {},
    directionPad = nil,
    joystick = nil,
    touches = {},
    sourceKeys = {},
    keySources = {},
    virtualKeys = {},
    sideLayout = false,
    drawScale = 1,
    imageFailed = false,
    touchSeen = false,
}

-- 640x480 设计空间的坐标（跟 Kristal 适配版同一组数字，方便两边对齐）
local function button_layout()
    return {
        { key = "left",  kind = "arrow",  x = 32,  y = 360 },
        { key = "right", kind = "arrow",  x = 192, y = 360 },
        { key = "up",    kind = "arrow",  x = 112, y = 285 },
        { key = "down",  kind = "arrow",  x = 112, y = 435 },
        { key = "z",     kind = "button", x = 520, y = 360 },
        { key = "x",     kind = "button", x = 600, y = 300 },
        { key = "c",     kind = "button", x = 600, y = 420 },
    }
end

local function action_button_layout()
    return {
        { key = "z", kind = "button", x = 520, y = 360 },
        { key = "x", kind = "button", x = 600, y = 300 },
        { key = "c", kind = "button", x = 600, y = 420 },
    }
end

local function clamp(v, minimum, maximum)
    return math.max(minimum, math.min(maximum, v))
end

local function distance_squared(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return dx * dx + dy * dy
end

local function is_touch_device()
    if (love and love.system and love.system.getOS) then
        local osname = love.system.getOS()
        if (osname == "Android" or osname == "iOS" or osname == "tvOS") then
            return true
        end
    end
    return false
end

--- 方向区映射：两轴独立判定，斜向可以同时按住两个方向
local function direction_mapping(x, y, center_x, center_y, radius, deadzone)
    local dx, dy = x - center_x, y - center_y
    local threshold = radius * deadzone
    local mapping = {}
    if (math.abs(dx) > threshold) then mapping[dx < 0 and "left" or "right"] = true end
    if (math.abs(dy) > threshold) then mapping[dy < 0 and "up" or "down"] = true end
    return mapping
end

-- ============================================================
--  模拟输入
-- ============================================================

--- 把一个虚拟键的按下/抬起喂给 Keyboard（走模拟键，逻辑层读 GetState 看不出区别）
---@param key string
---@param pressed boolean
function VirtualKeyboard.EmitKey(key, pressed)
    if (VirtualKeyboard.virtualKeys[key] == pressed) then return end
    VirtualKeyboard.virtualKeys[key] = pressed

    if (VirtualKeyboard.target == "Joystick") then
        if (Joystick and Joystick.SimulatePress and Joystick.SimulateRelease) then
            if (pressed) then Joystick.SimulatePress(key) else Joystick.SimulateRelease(key) end
        end
        return
    end

    if (pressed) then
        if (Keyboard and Keyboard.SimulatePress) then Keyboard.SimulatePress(key) end
    else
        if (Keyboard and Keyboard.SimulateRelease) then Keyboard.SimulateRelease(key) end
    end
end

--- 某个触摸源当前按住哪些键（多点按同一个键时靠引用计数决定何时真的抬起）
---@param source any
---@param keys table<string, boolean>
function VirtualKeyboard.SetSourceKeys(source, keys)
    if (source == nil) then return end
    local previous = VirtualKeyboard.sourceKeys[source] or {}
    local next_keys = {}
    for key, active in pairs(keys or {}) do
        if (active) then next_keys[key] = true end
    end

    for key in pairs(previous) do
        if (not next_keys[key]) then
            local sources = VirtualKeyboard.keySources[key]
            if (sources) then
                sources[source] = nil
                if (next(sources) == nil) then
                    VirtualKeyboard.keySources[key] = nil
                    VirtualKeyboard.EmitKey(key, false)
                end
            end
        end
    end

    for key in pairs(next_keys) do
        if (not previous[key]) then
            local sources = VirtualKeyboard.keySources[key]
            local was_active = sources and next(sources) ~= nil
            if (not sources) then
                sources = {}
                VirtualKeyboard.keySources[key] = sources
            end
            sources[source] = true
            if (not was_active) then
                VirtualKeyboard.EmitKey(key, true)
            end
        end
    end

    VirtualKeyboard.sourceKeys[source] = (next(next_keys) == nil) and nil or next_keys
end

--- 全部松开（隐藏 / 失焦 / 关闭时用，避免键卡住不放）
function VirtualKeyboard.ReleaseAll()
    for _, button in ipairs(VirtualKeyboard.buttons or {}) do
        button.touchId = nil
        button.pressed = false
    end
    if (VirtualKeyboard.joystick) then
        VirtualKeyboard.joystick.touchId = nil
        VirtualKeyboard.joystick.handleX = VirtualKeyboard.joystick.x
        VirtualKeyboard.joystick.handleY = VirtualKeyboard.joystick.y
        VirtualKeyboard.joystick.mapping = {}
    end

    local pressed_keys = {}
    for key, pressed in pairs(VirtualKeyboard.virtualKeys) do
        if (pressed) then pressed_keys[#pressed_keys + 1] = key end
    end

    VirtualKeyboard.touches = {}
    VirtualKeyboard.sourceKeys = {}
    VirtualKeyboard.keySources = {}

    for _, key in ipairs(pressed_keys) do
        VirtualKeyboard.EmitKey(key, false)
    end
end

-- ============================================================
--  控件构建
-- ============================================================

local function load_image(path)
    if (VirtualKeyboard.imageCache[path] ~= nil) then
        return VirtualKeyboard.imageCache[path] or nil
    end

    local ok, image = pcall(love.graphics.newImage, VirtualKeyboard.assetRoot .. path)
    if (not ok) or (not image) then
        print("[VirtualKeyboard] 贴图读不到 " .. tostring(path) .. "（退回矢量绘制）")
        io.stdout:flush()
        VirtualKeyboard.imageCache[path] = false
        VirtualKeyboard.imageFailed = true
        return nil
    end
    image:setFilter("nearest", "nearest")
    VirtualKeyboard.imageCache[path] = image
    return image
end

local function make_button(data)
    local normal = load_image("buttons/" .. data.kind .. "-" .. data.key .. ".png")
    local pressed_image = load_image("buttons/" .. data.kind .. "-" .. data.key .. "1.png")
    if (not normal) or (not pressed_image) then return nil end

    return {
        key = data.key,
        kind = data.kind,
        x = data.x,
        y = data.y,
        radius = 38,
        scale = 2.5,
        normal = normal,
        pressedImage = pressed_image,
        touchId = nil,
        pressed = false,
        enabled = true,
    }
end

--- 按 layout 重建控件表
function VirtualKeyboard.BuildLayout()
    VirtualKeyboard.buttons = {}
    VirtualKeyboard.directionPad = nil
    VirtualKeyboard.joystick = nil

    if (VirtualKeyboard.layout == "joystick") then
        local container = load_image("joystick/joystick-container.png")
        local handle = load_image("joystick/joystick-handle.png")
        if (container and handle) then
            VirtualKeyboard.joystick = {
                kind = "joystick",
                x = 112,
                y = 360,
                radius = 108,
                maxRadius = 54 * 2.5,
                deadzone = 0.35,
                scale = 2.5,
                container = container,
                handle = handle,
                touchId = nil,
                handleX = 112,
                handleY = 360,
                mapping = {},
            }
        end
        for _, data in ipairs(action_button_layout()) do
            local button = make_button(data)
            if (button) then VirtualKeyboard.buttons[#VirtualKeyboard.buttons + 1] = button end
        end
    else
        VirtualKeyboard.directionPad = {
            kind = "direction_pad",
            x = 112,
            y = 360,
            radius = 122,
            deadzone = 0.2,
        }
        for _, data in ipairs(button_layout()) do
            local button = make_button(data)
            if (button) then VirtualKeyboard.buttons[#VirtualKeyboard.buttons + 1] = button end
        end
    end
end

--- 重新计算控件位置（每帧调；窗口/缩放/转屏变化自动跟上）
--- 三种摆法：左右留白（横屏）→ 上下留白（竖屏）→ 压在 640x480 画面内（完全没有留白时的兜底）
function VirtualKeyboard.UpdateLayout()
    local scale = (ScreenScale and ScreenScale > 0) and ScreenScale or 1
    local ox, oy = DrawX or 0, DrawY or 0
    local win_w, win_h = love.graphics.getWidth(), love.graphics.getHeight()
    local canvas_w, canvas_h = DESIGN_W * scale, DESIGN_H * scale

    local space_left = ox
    local space_right = win_w - (ox + canvas_w)
    local space_top = oy
    local space_bottom = win_h - (oy + canvas_h)

    local mode = "canvas"
    if (math.min(space_left, space_right) >= 240 * scale) then
        mode = "h"          -- 左右留白够宽（横屏）：控件放两侧，不压画面
    elseif (math.max(space_top, space_bottom) >= 150 * scale) then
        mode = "v"          -- 上下留白够高（竖屏）：控件放画面上/下方
    end

    -- 留白模式下控件要按「手指大小」定尺寸，跟游戏画布缩放脱钩（spin-chara 画布是
    -- integer 缩放，常只有 1x，跟着它画按钮会小得没法按）。canvas 模式沿用 Kristal 的 2.5。
    local k = VirtualKeyboard.uiScaleOverride or clamp(math.min(win_w, win_h) / 200, 2, 6)
    local S = (mode == "canvas") and 2.5 or k
    local px = (mode ~= "canvas")

    VirtualKeyboard.drawScale = scale
    VirtualKeyboard.controlScale = S
    VirtualKeyboard.layoutMode = mode
    VirtualKeyboard.sideLayout = px
    VirtualKeyboard.pxMode = px       -- true：坐标/尺寸都是窗口像素；false：640x480 设计单位

    local space_w = px and win_w or DESIGN_W
    local direction_center_x, direction_center_y
    local action_center_x, action_center_y

    if (mode == "h") then
        direction_center_x = space_left * 0.5
        action_center_x = space_w - space_right * 0.5
        direction_center_y = oy + canvas_h * 0.5
        action_center_y = direction_center_y
    elseif (mode == "v") then
        local use_bottom = (space_bottom >= space_top)
        local band_start = use_bottom and (oy + canvas_h) or 0
        local band_size = use_bottom and space_bottom or space_top
        direction_center_x = 40 * S
        action_center_x = space_w - 40 * S
        direction_center_y = band_start + band_size * 0.5
        action_center_y = direction_center_y
    else
        direction_center_x, direction_center_y = 112, 360
        action_center_x, action_center_y = 560, 360
    end

    if (VirtualKeyboard.directionPad) then
        VirtualKeyboard.directionPad.radius = 49 * S        -- 方向区半径（按住滑动都在这个圈里判方向）
        VirtualKeyboard.directionPad.x = direction_center_x
        VirtualKeyboard.directionPad.y = direction_center_y
    end
    if (VirtualKeyboard.joystick) then
        VirtualKeyboard.joystick.radius = 43 * S
        VirtualKeyboard.joystick.maxRadius = 54 * S
        VirtualKeyboard.joystick.scale = S
        VirtualKeyboard.joystick.x = direction_center_x
        VirtualKeyboard.joystick.y = direction_center_y
        VirtualKeyboard.joystick.handleX = direction_center_x
        VirtualKeyboard.joystick.handleY = direction_center_y
    end

    for _, button in ipairs(VirtualKeyboard.buttons) do
        button.scale = S
        button.radius = 15.2 * S            -- 命中半径（跟 2.5 倍时的 38 对齐）
        if (button.kind == "arrow") then
            if (button.key == "left") then
                button.x, button.y = direction_center_x - 32 * S, direction_center_y
            elseif (button.key == "right") then
                button.x, button.y = direction_center_x + 32 * S, direction_center_y
            elseif (button.key == "up") then
                button.x, button.y = direction_center_x, direction_center_y - 30 * S
            elseif (button.key == "down") then
                button.x, button.y = direction_center_x, direction_center_y + 30 * S
            end
        elseif (button.key == "z") then
            button.x, button.y = action_center_x - 16 * S, action_center_y
        elseif (button.key == "x") then
            button.x, button.y = action_center_x + 16 * S, action_center_y - 24 * S
        elseif (button.key == "c") then
            button.x, button.y = action_center_x + 16 * S, action_center_y + 24 * S
        end
    end
end

-- ============================================================
--  触摸分发
-- ============================================================

local function release_button(button)
    local touch_id = button.touchId
    if (touch_id == nil) then return end
    button.touchId = nil
    button.pressed = false
    VirtualKeyboard.SetSourceKeys(touch_id, {})
    local touch = VirtualKeyboard.touches[touch_id]
    if (touch and touch.owner == button) then touch.owner = nil end
end

local function reset_joystick()
    local joystick = VirtualKeyboard.joystick
    if (not joystick) then return end
    local touch_id = joystick.touchId
    if (touch_id ~= nil) then
        VirtualKeyboard.SetSourceKeys(touch_id, {})
        local touch = VirtualKeyboard.touches[touch_id]
        if (touch and touch.owner == joystick) then touch.owner = nil end
    end
    joystick.touchId = nil
    joystick.handleX = joystick.x
    joystick.handleY = joystick.y
    joystick.mapping = {}
end

local function update_direction_touch(touch_id)
    local touch = VirtualKeyboard.touches[touch_id]
    local pad = VirtualKeyboard.directionPad
    if (not touch or not pad or touch.owner ~= pad) then return end
    VirtualKeyboard.SetSourceKeys(touch_id, direction_mapping(
        touch.x, touch.y, pad.x, pad.y, pad.radius, pad.deadzone))
end

local function update_joystick()
    local joystick = VirtualKeyboard.joystick
    if (not joystick or joystick.touchId == nil) then return end

    local touch = VirtualKeyboard.touches[joystick.touchId]
    if (not touch) then
        reset_joystick()
        return
    end

    local dx, dy = touch.x - joystick.x, touch.y - joystick.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local handle_distance = math.min(distance, joystick.maxRadius)

    if (distance > 0) then
        joystick.handleX = joystick.x + (dx / distance) * handle_distance
        joystick.handleY = joystick.y + (dy / distance) * handle_distance
    else
        joystick.handleX, joystick.handleY = joystick.x, joystick.y
    end

    local mapping = {}
    if (distance > joystick.radius * joystick.deadzone) then
        local horizontal = math.abs(dx) / distance
        local vertical = math.abs(dy) / distance
        if (math.abs(dx) > 0 and horizontal >= joystick.deadzone) then
            mapping[dx < 0 and "left" or "right"] = true
        end
        if (math.abs(dy) > 0 and vertical >= joystick.deadzone) then
            mapping[dy < 0 and "up" or "down"] = true
        end
    end
    joystick.mapping = mapping
    VirtualKeyboard.SetSourceKeys(joystick.touchId, mapping)
end

--- 屏幕坐标 → 控件坐标（跟绘制用的变换保持一致）
local function screen_to_control(x, y)
    if (VirtualKeyboard.pxMode) then
        return x, y          -- 留白模式：控件空间就是窗口像素
    end
    local scale = VirtualKeyboard.drawScale
    return (x - (DrawX or 0)) / scale, (y - (DrawY or 0)) / scale
end

local function press_button(button, touch_id)
    if (button.touchId ~= nil or not button.enabled) then return false end
    button.touchId = touch_id
    button.pressed = true
    VirtualKeyboard.SetSourceKeys(touch_id, { [button.key] = true })
    return true
end

local function assign_touch(touch_id, touch)
    if (not VirtualKeyboard.visible or touch.owner) then return false end

    local pad = VirtualKeyboard.directionPad
    if (pad and distance_squared(touch.x, touch.y, pad.x, pad.y) <= pad.radius * pad.radius) then
        touch.owner = pad
        update_direction_touch(touch_id)
        return true
    end

    local joystick = VirtualKeyboard.joystick
    if (joystick and joystick.touchId == nil
        and distance_squared(touch.x, touch.y, joystick.x, joystick.y) <= joystick.radius * joystick.radius) then
        joystick.touchId = touch_id
        touch.owner = joystick
        update_joystick()
        return true
    end

    for _, button in ipairs(VirtualKeyboard.buttons) do
        if (distance_squared(touch.x, touch.y, button.x, button.y) <= button.radius * button.radius
            and press_button(button, touch_id)) then
            touch.owner = button
            return true
        end
    end
    return false
end

local function update_button_touch(touch_id, touch)
    local button = touch.owner
    if (not button or button.touchId ~= touch_id) then
        touch.owner = nil
        assign_touch(touch_id, touch)
        return
    end
    if (distance_squared(touch.x, touch.y, button.x, button.y) > button.radius * button.radius) then
        release_button(button)
        assign_touch(touch_id, touch)
    end
end

--- 触摸按下（main.lua 的 love.touchpressed 调）——返回 true 表示这个触摸被控件吃掉了
---@return boolean consumed
function VirtualKeyboard.TouchPressed(id, x, y)
    if (not VirtualKeyboard.enabled) then
        if (VirtualKeyboard.autoEnableOnTouch) then
            VirtualKeyboard.SetEnabled(true)
        else
            return false
        end
    end
    VirtualKeyboard.touchSeen = true

    VirtualKeyboard.UpdateLayout()
    if (not VirtualKeyboard.visible) then return false end

    local game_x, game_y = screen_to_control(x, y)
    local touch = { x = game_x, y = game_y, owner = nil }
    VirtualKeyboard.touches[id] = touch
    return assign_touch(id, touch)
end

--- 触摸移动（main.lua 的 love.touchmoved 调）
function VirtualKeyboard.TouchMoved(id, x, y)
    local touch = VirtualKeyboard.touches[id]
    if (not touch) then return end

    touch.x, touch.y = screen_to_control(x, y)

    if (touch.owner == VirtualKeyboard.directionPad) then
        update_direction_touch(id)
    elseif (touch.owner == VirtualKeyboard.joystick) then
        update_joystick()
    elseif (touch.owner) then
        update_button_touch(id, touch)
    else
        assign_touch(id, touch)
    end
end

--- 触摸抬起（main.lua 的 love.touchreleased 调）——返回 true 表示被控件吃掉
---@return boolean consumed
function VirtualKeyboard.TouchReleased(id, x, y)
    if (VirtualKeyboard.touches[id]) then
        VirtualKeyboard.TouchMoved(id, x, y)
    end

    local touch = VirtualKeyboard.touches[id]
    if (not touch) then return false end

    if (touch.owner == VirtualKeyboard.joystick) then
        reset_joystick()
    elseif (touch.owner and touch.owner.touchId == id) then
        release_button(touch.owner)
    else
        VirtualKeyboard.SetSourceKeys(id, {})
    end

    VirtualKeyboard.touches[id] = nil
    return true
end

--- 桌面调试：鼠标左键当成一根手指
---@return boolean consumed
function VirtualKeyboard.MousePressed(x, y)
    return VirtualKeyboard.TouchPressed(MOUSE_TOUCH_ID, x, y)
end

---@return boolean consumed
function VirtualKeyboard.MouseReleased(x, y)
    return VirtualKeyboard.TouchReleased(MOUSE_TOUCH_ID, x, y)
end

--- 桌面调试：鼠标拖动等同手指滑动（这样才能试出方向区的斜向/换向）
function VirtualKeyboard.MouseMoved(x, y)
    VirtualKeyboard.TouchMoved(MOUSE_TOUCH_ID, x, y)
end

-- ============================================================
--  开关 / 配置
-- ============================================================

function VirtualKeyboard.SetEnabled(bool)
    VirtualKeyboard.enabled = not not bool
    if (VirtualKeyboard.enabled) then
        if (#VirtualKeyboard.buttons == 0 and not VirtualKeyboard.joystick) then
            VirtualKeyboard.BuildLayout()
            VirtualKeyboard.UpdateLayout()
        end
    else
        VirtualKeyboard.ReleaseAll()
    end
end

function VirtualKeyboard.SetVisible(bool)
    bool = not not bool
    if (VirtualKeyboard.visible == bool) then return bool end
    if (not bool) then VirtualKeyboard.ReleaseAll() end
    VirtualKeyboard.visible = bool
    return bool
end

function VirtualKeyboard.SetAutoDetect(bool)
    VirtualKeyboard.autoDetect = not not bool
end

--- 切换布局："buttons" 或 "joystick"
function VirtualKeyboard.SetLayout(layout)
    VirtualKeyboard.layout = (layout == "joystick") and "joystick" or "buttons"
    VirtualKeyboard.BuildLayout()
    VirtualKeyboard.UpdateLayout()
end

--- 模拟输入目标："Keyboard" 或 "Joystick"（兼容旧接口）
function VirtualKeyboard.SetTarget(target)
    VirtualKeyboard.target = (target == "Joystick") and "Joystick" or "Keyboard"
end

--- 单独关掉某个键的控件（例如某场景不用 X 键）
function VirtualKeyboard.SetButtonEnabled(key, bool)
    for _, button in ipairs(VirtualKeyboard.buttons) do
        if (button.key == key) then button.enabled = not not bool end
    end
end

--- 批量改配置：VirtualKeyboard.Configure{ layout = "joystick", alpha = 0.6 }
function VirtualKeyboard.Configure(opts)
    if (type(opts) ~= "table") then return end
    if (opts.layout) then VirtualKeyboard.SetLayout(opts.layout) end
    if (opts.alpha) then VirtualKeyboard.alpha = clamp(tonumber(opts.alpha) or VirtualKeyboard.alpha, 0, 1) end
    if (opts.toggleKey) then VirtualKeyboard.toggleKey = opts.toggleKey end
    if (opts.assetRoot) then VirtualKeyboard.assetRoot = opts.assetRoot end
    if (opts.target) then VirtualKeyboard.SetTarget(opts.target) end
    if (opts.visible ~= nil) then VirtualKeyboard.SetVisible(opts.visible) end
end

--- 这个键是不是开关键（toggleKey 写字符串或数组都行）
---@return boolean
function VirtualKeyboard.IsToggleKey(key)
    local tk = VirtualKeyboard.toggleKey
    if (type(tk) == "string") then return key == tk end
    if (type(tk) == "table") then
        for i = 1, #tk do
            if (key == tk[i]) then return true end
        end
    end
    return false
end

--- 开关键：在 main.lua 的 love.keypressed 里调，返回 true 表示这个键被吃掉了。
--- 默认 {"f9","pageup","pagedown"} —— 平板/手机在 Termux:X11 里按不到 F9，
--- 而 Termux:X11 的软键盘上有 PGUP / PGDN。
---@return boolean handled
function VirtualKeyboard.HandleKey(key, isrepeat)
    if (isrepeat) then return false end
    if (VirtualKeyboard.IsToggleKey(key)) then
        VirtualKeyboard.Toggle()
        return true
    end
    return false
end

--- 开/关（关掉再开时保持原布局；第一次打开会自己建控件）
function VirtualKeyboard.Toggle()
    if (not VirtualKeyboard.enabled) then
        VirtualKeyboard.SetEnabled(true)
        VirtualKeyboard.SetVisible(true)
        VirtualKeyboard.UpdateLayout()
        print(string.format(
            "[VirtualKeyboard] 打开：%s 布局 / %s 模式 / 缩放 %.3f / 窗口 %dx%d / 画布偏移 %d,%d",
            VirtualKeyboard.layout, tostring(VirtualKeyboard.layoutMode),
            VirtualKeyboard.drawScale, love.graphics.getWidth(), love.graphics.getHeight(),
            DrawX or 0, DrawY or 0))
        io.stdout:flush()
        return true
    end

    local visible = VirtualKeyboard.SetVisible(not VirtualKeyboard.visible)
    print("[VirtualKeyboard] " .. (visible and "显示" or "隐藏"))
    io.stdout:flush()
    return visible
end

--- 当前是不是触摸优先设备（兼容旧接口）
function VirtualKeyboard.IsTouchDevice()
    return is_touch_device()
end

--- 每帧调（main.lua 的 love.update）
function VirtualKeyboard.Update()
    if (VirtualKeyboard.autoDetect and not VirtualKeyboard.enabled and is_touch_device()) then
        VirtualKeyboard.SetEnabled(true)
        VirtualKeyboard.SetVisible(true)
    end

    if (VirtualKeyboard.enabled) then
        -- 失焦时把手上的键全松开，免得卡住
        if (love.window and love.window.hasFocus and not love.window.hasFocus()
            and next(VirtualKeyboard.touches) ~= nil) then
            VirtualKeyboard.ReleaseAll()
        end
        VirtualKeyboard.UpdateLayout()
    end
end

-- ============================================================
--  绘制
-- ============================================================

local function draw_fallback_controls()
    -- 贴图缺失时的兜底：画方块 + 文字，保证按键还能按
    local font = (SE and SE.graphics and SE.graphics.getFont and SE.graphics.getFont())
        or love.graphics.getFont()
    for _, button in ipairs(VirtualKeyboard.buttons) do
        if (button.enabled) then
            local pressed = button.pressed or VirtualKeyboard.virtualKeys[button.key]
            gfx.setColor(0.25, 0.25, 0.35, pressed and 1 or VirtualKeyboard.alpha)
            gfx.rectangle("fill", button.x - 34, button.y - 34, 68, 68, 8, 8)
            gfx.setColor(1, 1, 1, 0.9)
            gfx.print(button.key, button.x - 10, button.y - 8)
        end
    end
    if (font) then gfx.setFont(font) end
end

local function draw_controls(render_scale)
    local alpha = clamp(VirtualKeyboard.alpha, 0, 1)
    local joystick = VirtualKeyboard.joystick

    if (joystick) then
        gfx.setColor(1, 1, 1, alpha)
        gfx.draw(joystick.container,
            joystick.x * render_scale, joystick.y * render_scale, 0,
            joystick.scale * render_scale, joystick.scale * render_scale,
            joystick.container:getWidth() / 2, joystick.container:getHeight() / 2)
        gfx.draw(joystick.handle,
            joystick.handleX * render_scale, joystick.handleY * render_scale, 0,
            joystick.scale * render_scale, joystick.scale * render_scale,
            joystick.handle:getWidth() / 2, joystick.handle:getHeight() / 2)
    end

    if (VirtualKeyboard.imageFailed) then
        draw_fallback_controls()
        return
    end

    for _, button in ipairs(VirtualKeyboard.buttons) do
        local pressed = button.touchId ~= nil
        if (button.kind == "arrow") then
            pressed = VirtualKeyboard.virtualKeys[button.key] == true
        end
        local image = pressed and button.pressedImage or button.normal
        gfx.setColor(1, 1, 1, pressed and math.min(1, alpha + 0.12) or alpha)
        gfx.draw(image,
            button.x * render_scale, button.y * render_scale, 0,
            button.scale * render_scale, button.scale * render_scale,
            image:getWidth() / 2, image:getHeight() / 2)
    end
end

--- 每帧调（main.lua 的 love.draw，屏幕空间）
function VirtualKeyboard.Draw()
    if (not VirtualKeyboard.enabled or not VirtualKeyboard.visible) then return end
    if (#VirtualKeyboard.buttons == 0 and not VirtualKeyboard.joystick) then
        VirtualKeyboard.BuildLayout()
    end
    VirtualKeyboard.UpdateLayout()

    gfx.push("all")
    gfx.origin()
    if (VirtualKeyboard.pxMode) then
        -- 留白模式：坐标和尺寸已经是窗口像素（尺寸系数见 UpdateLayout 的 S）
        draw_controls(1)
    else
        -- 画在 640x480 画面内，跟游戏画面同一套变换
        gfx.translate(DrawX or 0, DrawY or 0)
        gfx.scale(VirtualKeyboard.drawScale, VirtualKeyboard.drawScale)
        draw_controls(1)
    end
    gfx.pop()
    gfx.setColor(1, 1, 1, 1)
end

return VirtualKeyboard
