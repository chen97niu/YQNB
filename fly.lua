--[[
================================================================
  雅清飞行 · YQNB Fly  v1.0 （手机端适配）
----------------------------------------------------------------
  功能：
    · 悬浮球：可拖动，点击展开 / 收起主面板
    · 主面板：飞行开关、速度调节、上升 / 下降、关闭脚本
    · 飞行：水平方向跟随视角 + 摇杆方向，按钮控制升降
    · 开关平滑切换，角色重生自动重新绑定
    · 死亡 / 移除角色 / 关闭脚本时自动清理（BodyGyro /
      BodyVelocity 无残留）
    · 全中文界面，触屏大按钮，按分辨率自适应缩放，不依赖键盘
----------------------------------------------------------------
  适用范围：仅供在你自己创建的服务器 / 私人服务器内使用，
            请勿进入他人游戏使用，以免影响他人并违反平台规则。
  加载方式：loadstring(game:HttpGet("你的raw链接"))()
  兼容：忍者注入器等主流注入器（手机端可直接触屏操作）
================================================================
]]

-- ===== 防止重复加载：先卸载旧实例 =====
if _G.YQNB_FLY_UNLOAD then
    pcall(_G.YQNB_FLY_UNLOAD)
    _G.YQNB_FLY_UNLOAD = nil
end

-- ===== 服务 =====
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local WorkspaceService = game:GetService("Workspace")

-- 兼容新旧注入器：优先 task.wait，老环境退回 wait
local _wait = (task and task.wait) or wait

-- ===== 本地玩家 =====
local LocalPlayer = Players.LocalPlayer
local tryCount = 0
while not LocalPlayer and tryCount < 30 do
    _wait(0.1)
    tryCount = tryCount + 1
    LocalPlayer = Players.LocalPlayer
end
if not LocalPlayer then
    return
end

-- ===== 状态与前置声明 =====
local flying       = false
local flySpeed     = 50
local SPEED_MIN    = 10
local SPEED_MAX    = 200
local SPEED_STEP   = 10
local upHeld       = false
local downHeld     = false

local bodyGyro     = nil
local bodyVelocity = nil

local globalConnections = {}
local charConnections   = {}
local screenGui         = nil

local setFlying    -- 前置声明（按钮回调里引用）
local unload
local togglePanel

local function track(conn)
    table.insert(globalConnections, conn)
    return conn
end

-- ===== 通用小工具 =====
local function delayCall(sec, fn)
    if task and task.delay then
        task.delay(sec, fn)
    else
        spawn(function()
            _wait(sec)
            fn()
        end)
    end
end

local function setProps(inst, props)
    for k, v in pairs(props) do
        inst[k] = v
    end
    return inst
end

local function addCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

local function addScale(parent)
    local s = Instance.new("UIScale")
    s.Scale = 1
    s.Parent = parent
    return s
end

-- ==================== 界面 ====================
local COLOR_PANEL  = Color3.fromRGB(26, 29, 34)    -- 面板深灰
local COLOR_BTN    = Color3.fromRGB(42, 47, 55)    -- 常规按钮
local COLOR_BTN2   = Color3.fromRGB(54, 60, 70)    -- 强调按钮
local COLOR_ACCENT = Color3.fromRGB(143, 208, 193) -- 青瓷主色
local COLOR_DANGER = Color3.fromRGB(176, 78, 78)   -- 危险红
local COLOR_TEXT   = Color3.fromRGB(238, 242, 240)
local COLOR_SUB    = Color3.fromRGB(158, 166, 176)
local COLOR_DARK   = Color3.fromRGB(20, 23, 26)

-- ScreenGui：优先挂 CoreGui（注入器环境），失败退回 PlayerGui
screenGui = Instance.new("ScreenGui")
screenGui.Name = "YQNB_FlyGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100000
screenGui.IgnoreGuiInset = true

local guiParented = false
pcall(function()
    screenGui.Parent = game:GetService("CoreGui")
    guiParented = (screenGui.Parent ~= nil)
end)
if not guiParented then
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        playerGui = LocalPlayer:WaitForChild("PlayerGui", 5)
    end
    if not playerGui then
        return
    end
    screenGui.Parent = playerGui
end

-- ---------- 悬浮球 ----------
local ball = Instance.new("TextButton")
setProps(ball, {
    Name = "YQNB_FlyBall",
    Text = "飞",
    TextColor3 = COLOR_TEXT,
    TextSize = 26,
    Font = Enum.Font.GothamBold,
    BackgroundColor3 = Color3.fromRGB(22, 24, 28),
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Active = true,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.88, 0, 0.32, 0),
    Size = UDim2.new(0, 64, 0, 64),
    ZIndex = 5,
})
addCorner(ball, 32)
local ballStroke = Instance.new("UIStroke")
ballStroke.Color = COLOR_ACCENT
ballStroke.Thickness = 2
ballStroke.Transparency = 0.3
ballStroke.Parent = ball
local ballScale = addScale(ball)
ball.Parent = screenGui

-- ---------- 主面板 ----------
local panel = Instance.new("Frame")
setProps(panel, {
    Name = "YQNB_FlyPanel",
    BackgroundColor3 = COLOR_PANEL,
    BackgroundTransparency = 0.08,
    BorderSizePixel = 0,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(0, 320, 0, 300),
    Visible = false,
    ZIndex = 10,
})
addCorner(panel, 16)
local panelScale = addScale(panel)
panel.Parent = screenGui

-- 标题行
local titleLabel = Instance.new("TextLabel")
setProps(titleLabel, {
    Text = "雅清飞行",
    TextColor3 = COLOR_TEXT,
    TextSize = 20,
    Font = Enum.Font.GothamBold,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 16, 0, 6),
    Size = UDim2.new(0, 160, 0, 40),
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 11,
})
titleLabel.Parent = panel

local collapseBtn = Instance.new("TextButton")
setProps(collapseBtn, {
    Text = "收起",
    TextColor3 = COLOR_SUB,
    TextSize = 16,
    Font = Enum.Font.GothamMedium,
    BackgroundColor3 = COLOR_BTN,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 250, 0, 10),
    Size = UDim2.new(0, 56, 0, 32),
    ZIndex = 11,
})
addCorner(collapseBtn, 10)
collapseBtn.Parent = panel

-- 飞行开关
local toggleBtn = Instance.new("TextButton")
setProps(toggleBtn, {
    Text = "飞行：关闭",
    TextColor3 = COLOR_TEXT,
    TextSize = 20,
    Font = Enum.Font.GothamBold,
    BackgroundColor3 = COLOR_BTN2,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 14, 0, 54),
    Size = UDim2.new(0, 292, 0, 56),
    ZIndex = 11,
})
addCorner(toggleBtn, 14)
toggleBtn.Parent = panel

-- 速度行：-  [速度 50]  +
local minusBtn = Instance.new("TextButton")
setProps(minusBtn, {
    Text = "-",
    TextColor3 = COLOR_TEXT,
    TextSize = 26,
    Font = Enum.Font.GothamBold,
    BackgroundColor3 = COLOR_BTN,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 14, 0, 118),
    Size = UDim2.new(0, 54, 0, 48),
    ZIndex = 11,
})
addCorner(minusBtn, 10)
minusBtn.Parent = panel

local speedLabel = Instance.new("TextLabel")
setProps(speedLabel, {
    Text = "速度 50",
    TextColor3 = COLOR_TEXT,
    TextSize = 18,
    Font = Enum.Font.GothamMedium,
    BackgroundColor3 = Color3.fromRGB(32, 36, 42),
    BorderSizePixel = 0,
    Position = UDim2.new(0, 74, 0, 118),
    Size = UDim2.new(0, 172, 0, 48),
    ZIndex = 11,
})
addCorner(speedLabel, 10)
speedLabel.Parent = panel

local plusBtn = Instance.new("TextButton")
setProps(plusBtn, {
    Text = "+",
    TextColor3 = COLOR_TEXT,
    TextSize = 26,
    Font = Enum.Font.GothamBold,
    BackgroundColor3 = COLOR_BTN,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 252, 0, 118),
    Size = UDim2.new(0, 54, 0, 48),
    ZIndex = 11,
})
addCorner(plusBtn, 10)
plusBtn.Parent = panel

-- 上升 / 下降（按住生效）
local upBtn = Instance.new("TextButton")
setProps(upBtn, {
    Text = "↑ 上升",
    TextColor3 = COLOR_TEXT,
    TextSize = 19,
    Font = Enum.Font.GothamBold,
    BackgroundColor3 = COLOR_BTN,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 14, 0, 174),
    Size = UDim2.new(0, 142, 0, 56),
    ZIndex = 11,
})
addCorner(upBtn, 12)
upBtn.Parent = panel

local downBtn = Instance.new("TextButton")
setProps(downBtn, {
    Text = "↓ 下降",
    TextColor3 = COLOR_TEXT,
    TextSize = 19,
    Font = Enum.Font.GothamBold,
    BackgroundColor3 = COLOR_BTN,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 164, 0, 174),
    Size = UDim2.new(0, 142, 0, 56),
    ZIndex = 11,
})
addCorner(downBtn, 12)
downBtn.Parent = panel

-- 关闭脚本（二次确认）
local killBtn = Instance.new("TextButton")
setProps(killBtn, {
    Text = "关闭脚本",
    TextColor3 = COLOR_SUB,
    TextSize = 17,
    Font = Enum.Font.GothamMedium,
    BackgroundColor3 = COLOR_BTN,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 14, 0, 240),
    Size = UDim2.new(0, 292, 0, 44),
    ZIndex = 11,
})
addCorner(killBtn, 12)
killBtn.Parent = panel

-- ---------- 界面状态 ----------
local function updateToggleUI()
    if flying then
        toggleBtn.Text = "飞行：开启中"
        toggleBtn.BackgroundColor3 = COLOR_ACCENT
        toggleBtn.TextColor3 = COLOR_DARK
    else
        toggleBtn.Text = "飞行：关闭"
        toggleBtn.BackgroundColor3 = COLOR_BTN2
        toggleBtn.TextColor3 = COLOR_TEXT
    end
end

local function updateSpeedUI()
    speedLabel.Text = "速度 " .. tostring(flySpeed)
end

togglePanel = function()
    panel.Visible = not panel.Visible
end

-- ---------- 悬浮球：拖动 + 点击展开 ----------
local ballDragging = false
local ballDragged  = false
local ballDragStart = nil
local ballStartX = 0
local ballStartY = 0

ball.InputBegan:Connect(function(input)
    local t = input.UserInputType
    if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
        ballDragging = true
        ballDragged = false
        ballDragStart = Vector2.new(input.Position.X, input.Position.Y)
        ballStartX = ball.AbsolutePosition.X
        ballStartY = ball.AbsolutePosition.Y
    end
end)

track(UserInputService.InputChanged:Connect(function(input)
    if not ballDragging then
        return
    end
    local t = input.UserInputType
    if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseMovement then
        return
    end
    local delta = Vector2.new(input.Position.X, input.Position.Y) - ballDragStart
    if delta.Magnitude > 8 then
        ballDragged = true
    end
    local cam = WorkspaceService.CurrentCamera
    if not cam then
        return
    end
    local vp = cam.ViewportSize
    local half = ball.AbsoluteSize.X * 0.5
    local x = ballStartX + delta.X
    local y = ballStartY + delta.Y
    x = math.clamp(x, half, math.max(half, vp.X - half))
    y = math.clamp(y, half, math.max(half, vp.Y - half))
    ball.Position = UDim2.new(0, x, 0, y)
end))

track(UserInputService.InputEnded:Connect(function(input)
    local t = input.UserInputType
    if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
        return
    end
    if ballDragging then
        ballDragging = false
        if not ballDragged then
            pcall(togglePanel)
        end
    end
end))

-- ---------- 分辨率自适应缩放 ----------
local curScale = 0
track(RunService.RenderStepped:Connect(function()
    local cam = WorkspaceService.CurrentCamera
    if not cam then
        return
    end
    local vp = cam.ViewportSize
    local s = math.clamp(vp.Y / 780, 0.9, 1.6)
    if math.abs(s - curScale) > 0.01 then
        curScale = s
        panelScale.Scale = s
        ballScale.Scale = s
    end
end))

-- ==================== 飞行核心 ====================
local function getCharacterParts()
    local char = LocalPlayer.Character
    if not char then
        return nil, nil, nil
    end
    return char,
        char:FindFirstChild("HumanoidRootPart"),
        char:FindFirstChildOfClass("Humanoid")
end

local function cleanupMovers()
    if bodyGyro then
        pcall(function() bodyGyro:Destroy() end)
        bodyGyro = nil
    end
    if bodyVelocity then
        pcall(function() bodyVelocity:Destroy() end)
        bodyVelocity = nil
    end
end

-- 挂载飞行推进器（平滑起步：初速继承当前速度）
local function startFlight()
    local _, hrp, hum = getCharacterParts()
    if not hrp or not hum or hum.Health <= 0 then
        return false
    end
    cleanupMovers()

    bodyGyro = Instance.new("BodyGyro")
    bodyGyro.Name = "YQNB_FlyGyro"
    bodyGyro.MaxTorque = Vector3.new(900000, 900000, 900000)
    bodyGyro.P = 9000
    bodyGyro.D = 800
    bodyGyro.CFrame = hrp.CFrame
    bodyGyro.Parent = hrp

    bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.Name = "YQNB_FlyVelocity"
    bodyVelocity.MaxForce = Vector3.new(1000000, 1000000, 1000000)
    bodyVelocity.Velocity = hrp.Velocity
    bodyVelocity.Parent = hrp

    pcall(function()
        hum:ChangeState(Enum.HumanoidStateType.Physics)
    end)
    return true
end

setFlying = function(on)
    if on == flying then
        return
    end
    if on then
        local ok = startFlight()
        flying = ok
    else
        flying = false
        upHeld = false
        downHeld = false
        cleanupMovers()
        -- 平滑恢复：保留惯性，交给物理自然减速下落
        local _, hrp, hum = getCharacterParts()
        if hum and hrp and hum.Health > 0 then
            pcall(function()
                hum:ChangeState(Enum.HumanoidStateType.Freefall)
            end)
        end
    end
    updateToggleUI()
end

-- 每帧驱动：状态维持 + 速度合成 + 朝向跟随视角
local function onStep()
    if not flying then
        return
    end
    local _, hrp, hum = getCharacterParts()
    if not hrp or not hum or hum.Health <= 0 then
        return
    end
    -- 角色更换 / 推进器被移除时自动重绑
    if not bodyGyro or not bodyVelocity or bodyGyro.Parent ~= hrp then
        if not startFlight() then
            return
        end
    end
    pcall(function()
        -- 维持物理状态，避免状态机抢回控制
        if hum:GetState() ~= Enum.HumanoidStateType.Physics then
            hum:ChangeState(Enum.HumanoidStateType.Physics)
        end
        -- 水平：摇杆方向（MoveDirection 已含视角相对关系）
        local target = hum.MoveDirection * flySpeed
        -- 垂直：按住上升 / 下降按钮
        if upHeld then
            target = target + Vector3.new(0, flySpeed, 0)
        end
        if downHeld then
            target = target - Vector3.new(0, flySpeed, 0)
        end
        -- 平滑趋近目标速度
        bodyVelocity.Velocity = bodyVelocity.Velocity:Lerp(target, 0.35)
        -- 朝向：仅水平跟随相机
        local cam = WorkspaceService.CurrentCamera
        if cam then
            local look = cam.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude > 0.001 then
                flat = flat.Unit
                local pos = hrp.Position
                bodyGyro.CFrame = CFrame.new(pos, pos + flat)
            end
        end
    end)
end

-- ---------- 角色绑定（重生自动重绑） ----------
local function bindCharacter(char)
    for _, c in ipairs(charConnections) do
        pcall(function() c:Disconnect() end)
    end
    charConnections = {}
    local hum = char:WaitForChild("Humanoid", 8)
    if not hum then
        return
    end
    table.insert(charConnections, hum.Died:Connect(function()
        upHeld = false
        downHeld = false
        cleanupMovers()
    end))
end

track(LocalPlayer.CharacterAdded:Connect(function(char)
    bodyGyro = nil
    bodyVelocity = nil
    upHeld = false
    downHeld = false
    pcall(function() bindCharacter(char) end)
    if flying then
        local hrp = char:WaitForChild("HumanoidRootPart", 8)
        if flying and hrp then
            startFlight()
        end
    end
end))

track(LocalPlayer.CharacterRemoving:Connect(function()
    cleanupMovers()
end))

track(RunService.RenderStepped:Connect(onStep))

-- ---------- 按钮：按住生效（上升 / 下降） ----------
local function bindHold(btn, setter)
    btn.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
            setter(true)
        end
    end)
    btn.InputEnded:Connect(function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
            setter(false)
        end
    end)
    -- 兜底：鼠标滑出按钮后松开时 InputEnded 不一定送达按钮，
    -- 用抬起位置判断（留 90px 容差）清除按住状态
    track(UserInputService.InputEnded:Connect(function(input)
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 then
            return
        end
        local p = input.Position
        local pos = btn.AbsolutePosition
        local size = btn.AbsoluteSize
        local slack = 90
        local inside = p.X >= pos.X - slack and p.X <= pos.X + size.X + slack
            and p.Y >= pos.Y - slack and p.Y <= pos.Y + size.Y + slack
        if not inside then
            setter(false)
        end
    end))
end

-- ---------- 面板按钮连接 ----------
toggleBtn.Activated:Connect(function()
    pcall(setFlying, not flying)
end)

minusBtn.Activated:Connect(function()
    flySpeed = math.max(SPEED_MIN, flySpeed - SPEED_STEP)
    updateSpeedUI()
end)

plusBtn.Activated:Connect(function()
    flySpeed = math.min(SPEED_MAX, flySpeed + SPEED_STEP)
    updateSpeedUI()
end)

collapseBtn.Activated:Connect(function()
    pcall(togglePanel)
end)

bindHold(upBtn, function(v)
    upHeld = v
end)

bindHold(downBtn, function(v)
    downHeld = v
end)

-- ---------- 关闭脚本（二次确认 + 完整清理） ----------
local killArmed = false
killBtn.Activated:Connect(function()
    if killArmed then
        pcall(unload)
        return
    end
    killArmed = true
    killBtn.Text = "再点一次确认关闭"
    killBtn.BackgroundColor3 = COLOR_DANGER
    killBtn.TextColor3 = COLOR_TEXT
    delayCall(3, function()
        if killArmed and screenGui and screenGui.Parent then
            killArmed = false
            pcall(function()
                killBtn.Text = "关闭脚本"
                killBtn.BackgroundColor3 = COLOR_BTN
                killBtn.TextColor3 = COLOR_SUB
            end)
        end
    end)
end)

-- ---------- 卸载清理 ----------
unload = function()
    flying = false
    upHeld = false
    downHeld = false
    for _, c in ipairs(globalConnections) do
        pcall(function() c:Disconnect() end)
    end
    globalConnections = {}
    for _, c in ipairs(charConnections) do
        pcall(function() c:Disconnect() end)
    end
    charConnections = {}
    cleanupMovers()
    -- 恢复角色正常状态
    local _, _, hum = getCharacterParts()
    if hum and hum.Health > 0 then
        pcall(function()
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end
    if screenGui then
        pcall(function() screenGui:Destroy() end)
        screenGui = nil
    end
    _G.YQNB_FLY_UNLOAD = nil
end
_G.YQNB_FLY_UNLOAD = unload

-- ---------- 初始化 ----------
updateToggleUI()
updateSpeedUI()
if LocalPlayer.Character then
    pcall(function() bindCharacter(LocalPlayer.Character) end)
end
