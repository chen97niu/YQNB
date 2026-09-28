--[[
================================================================
  雅清脚本 · YQING Script  v0.1 （手机端多功能 · 单文件）
----------------------------------------------------------------
  功能总览：
    · 悬浮球：可拖动，点击展开 / 收起主面板
    · 主面板：雅清风高级质感 UI
        - 顶部「雅清脚本」+ 右侧「_雅清制作v0.1」
        - 实时时钟（时:分:秒，每秒刷新）
        - 五大功能：透视 / 飞行 / 加速 / 跳跃 / 锁头
          点功能名展开对应子面板，再点收起
        - 一键全关（总关闭）+ 关闭脚本（二次确认）
    · 透视：其他玩家头顶显示名字 + 人物描边高亮，
            关闭后全部清除恢复
    · 飞行：5 档速度，档位越高越快；方向 = 相机完整朝向
            （含俯仰）× 摇杆输入：摇杆前推沿视线飞，
            视角朝上再前推就向上飞，视角转多少方向就变多少；
            松开摇杆原地悬停；关闭 / 死亡清理干净，重生自动重绑
    · 加速：5 档移动速度（WalkSpeed），关闭恢复默认
    · 跳跃：5 档跳跃力（JumpPower / JumpHeight 两套环境兼容），
            关闭恢复默认
    · 锁头：手持工具（近战 / 枪械）时自动将视角平滑锁向
            最近非队友玩家头部；用队伍(Team)区分队友，
            自己无队伍时全员视为敌人；无有效目标不动作；
            关闭立即停止
    · 点档位即生效并自动开启，当前档高亮
    · 死亡 / 重生自动清理与重绑；防重复加载；pcall 防崩
    · 全中文界面，触屏大按钮，按分辨率自适应缩放，不依赖键盘
----------------------------------------------------------------
  适用范围：仅供在你自己创建的服务器 / 私人服务器内使用，
            请勿进入他人游戏使用，以免影响他人并违反平台规则。
  加载方式：loadstring(game:HttpGet("你的raw链接"))()
  兼容：忍者注入器等主流注入器（手机端可直接触屏操作）
================================================================
]]

-- ===== 防止重复加载：先卸载旧实例（含旧版飞行脚本） =====
if _G.YQING_SCRIPT_UNLOAD then
    pcall(_G.YQING_SCRIPT_UNLOAD)
    _G.YQING_SCRIPT_UNLOAD = nil
end
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

-- ===== 档位数值表（1 ~ 5 档） =====
local FLY_SPEEDS    = {30, 60, 100, 150, 220}   -- 飞行速度
local WALK_SPEEDS   = {20, 26, 34, 44, 60}      -- 加速
local JUMP_POWERS   = {60, 80, 105, 135, 170}   -- 跳跃（JumpPower 环境）
local JUMP_HEIGHTS  = {9.5, 13, 17, 22, 28}     -- 跳跃（JumpHeight 环境）
local AIM_STRENGTHS = {4, 7, 10, 14, 19}        -- 锁头速度：1 最平滑 → 5 最快
local DEFAULT_LEVEL = 2

-- ===== 功能状态 =====
local feat = {
    esp   = { enabled = false, level = DEFAULT_LEVEL, title = "透视" },
    fly   = { enabled = false, level = DEFAULT_LEVEL, title = "飞行" },
    speed = { enabled = false, level = DEFAULT_LEVEL, title = "加速" },
    jump  = { enabled = false, level = DEFAULT_LEVEL, title = "跳跃" },
    aim   = { enabled = false, level = DEFAULT_LEVEL, title = "锁头" },
}
local featOrder = { "esp", "fly", "speed", "jump", "aim" }

-- ===== 全局状态与前置声明 =====
local globalConnections = {}
local charConnections   = {}
local espConns          = {}
local screenGui         = nil

local refreshUI   -- 前置声明（功能逻辑里会调用）
local relayout    -- 前置声明（按钮回调里调用）
local togglePanel -- 前置声明（悬浮球回调里调用）
local unload      -- 前置声明（关闭按钮回调里调用）

-- 原始数值记录（恢复默认用）
local origWalk       = 16
local origJumpPower  = 50
local origJumpHeight = 7.2

-- ===== 通用小工具 =====
local function track(conn)
    table.insert(globalConnections, conn)
    return conn
end

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

local function addStroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness
    s.Transparency = transparency
    s.Parent = parent
    return s
end

local function addScale(parent)
    local s = Instance.new("UIScale")
    s.Scale = 1
    s.Parent = parent
    return s
end

-- ===== 配色（雅清：暗色 + 青瓷） =====
local COLOR_PANEL  = Color3.fromRGB(26, 29, 34)    -- 面板深灰
local COLOR_BTN    = Color3.fromRGB(42, 47, 55)    -- 常规按钮
local COLOR_BTN2   = Color3.fromRGB(54, 60, 70)    -- 强调按钮
local COLOR_ACCENT = Color3.fromRGB(143, 208, 193) -- 青瓷主色
local COLOR_DANGER = Color3.fromRGB(176, 78, 78)   -- 危险红
local COLOR_TEXT   = Color3.fromRGB(238, 242, 240)
local COLOR_SUB    = Color3.fromRGB(158, 166, 176)
local COLOR_DARK   = Color3.fromRGB(20, 23, 26)

-- ==================== 角色小工具 ====================
local function getCharParts()
    local char = LocalPlayer.Character
    if not char then
        return nil, nil, nil
    end
    return char,
        char:FindFirstChild("HumanoidRootPart"),
        char:FindFirstChildOfClass("Humanoid")
end

-- ==================== 飞行核心 ====================
local bodyGyro     = nil
local bodyVelocity = nil

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
    local _, hrp, hum = getCharParts()
    if not hrp or not hum or hum.Health <= 0 then
        return false
    end
    cleanupMovers()

    bodyGyro = Instance.new("BodyGyro")
    bodyGyro.Name = "YQ_FlyGyro"
    bodyGyro.MaxTorque = Vector3.new(900000, 900000, 900000)
    bodyGyro.P = 9000
    bodyGyro.D = 800
    bodyGyro.CFrame = hrp.CFrame
    bodyGyro.Parent = hrp

    bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.Name = "YQ_FlyVelocity"
    bodyVelocity.MaxForce = Vector3.new(1000000, 1000000, 1000000)
    bodyVelocity.Velocity = hrp.Velocity
    bodyVelocity.Parent = hrp

    pcall(function()
        hum:ChangeState(Enum.HumanoidStateType.Physics)
    end)
    return true
end

local function setFly(on)
    if on then
        return startFlight()
    end
    cleanupMovers()
    -- 平滑恢复：保留惯性，交给物理自然减速下落
    local _, hrp, hum = getCharParts()
    if hum and hrp and hum.Health > 0 then
        pcall(function()
            hum:ChangeState(Enum.HumanoidStateType.Freefall)
        end)
    end
    return false
end

-- 每帧驱动：方向 = 相机完整朝向（含俯仰）× 摇杆输入
local function flyStep(dt)
    if not feat.fly.enabled then
        return
    end
    local char, hrp, hum = getCharParts()
    if not char or not hrp or not hum or hum.Health <= 0 then
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
        local cam = WorkspaceService.CurrentCamera
        if not cam then
            return
        end
        local speed = FLY_SPEEDS[feat.fly.level] or 60

        -- 从摇杆（MoveDirection 已含相机相对关系）还原输入意图
        local md = hum.MoveDirection
        local inputF = 0
        local inputR = 0
        if md.Magnitude > 0.08 then
            local dir = md.Unit
            local look = cam.CFrame.LookVector
            local right = cam.CFrame.RightVector
            local flat = Vector3.new(look.X, 0, look.Z)
            local flatR = Vector3.new(right.X, 0, right.Z)
            if flat.Magnitude > 0.02 then
                inputF = dir:Dot(flat.Unit)
            end
            if flatR.Magnitude > 0.02 then
                inputR = dir:Dot(flatR.Unit)
            end
        end

        -- 3D 目标速度：相机完整朝向（含俯仰）× 输入
        -- 摇杆前推 = 沿视线飞（视角朝上就往上飞），松开 = 悬停
        local target = cam.CFrame.LookVector * inputF * speed
            + cam.CFrame.RightVector * inputR * speed
        local a = math.clamp((dt or 0.016) * 16, 0.1, 0.6)
        bodyVelocity.Velocity = bodyVelocity.Velocity:Lerp(target, a)

        -- 机体朝向跟随相机完整朝向；视角接近竖直时保持原朝向防抖
        local look = cam.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude > 0.05 then
            bodyGyro.CFrame = CFrame.new(hrp.Position, hrp.Position + look)
        end
    end)
end

-- ==================== 透视 ====================
local ESP_GUI_NAME = "YQ_ESP_Name"
local ESP_HL_NAME  = "YQ_ESP_Highlight"

local function espClearChar(char)
    if not char then
        return
    end
    for _, obj in ipairs(char:GetDescendants()) do
        if obj.Name == ESP_GUI_NAME or obj.Name == ESP_HL_NAME then
            pcall(function() obj:Destroy() end)
        end
    end
end

local function espApplyChar(pl, char)
    espClearChar(char)
    local head = char:FindFirstChild("Head")
    if not head then
        local ok, h = pcall(function()
            return char:WaitForChild("Head", 3)
        end)
        if ok then
            head = h
        end
    end
    if head then
        local bb = Instance.new("BillboardGui")
        bb.Name = ESP_GUI_NAME
        bb.Adornee = head
        bb.Size = UDim2.new(0, 150, 0, 30)
        bb.StudsOffset = Vector3.new(0, 2.6, 0)
        bb.AlwaysOnTop = true
        bb.MaxDistance = 400
        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, 0, 1, 0)
        tl.BackgroundTransparency = 0.45
        tl.BackgroundColor3 = COLOR_DARK
        tl.TextColor3 = COLOR_ACCENT
        tl.Text = pl.DisplayName or pl.Name
        tl.TextSize = 14
        tl.Font = Enum.Font.GothamBold
        tl.Parent = bb
        addCorner(tl, 8)
        bb.Parent = head
    end
    local hl = Instance.new("Highlight")
    hl.Name = ESP_HL_NAME
    hl.FillColor = COLOR_ACCENT
    hl.FillTransparency = 0.72
    hl.OutlineColor = COLOR_ACCENT
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = char
end

local function espWatchPlayer(pl)
    if pl == LocalPlayer then
        return
    end
    if pl.Character then
        pcall(espApplyChar, pl, pl.Character)
    end
    table.insert(espConns, pl.CharacterAdded:Connect(function(char)
        delayCall(0.2, function()
            if feat.esp.enabled then
                pcall(espApplyChar, pl, char)
            end
        end)
    end))
end

local function setEsp(on)
    if on then
        for _, pl in ipairs(Players:GetPlayers()) do
            pcall(espWatchPlayer, pl)
        end
        table.insert(espConns, Players.PlayerAdded:Connect(function(pl)
            pcall(espWatchPlayer, pl)
        end))
        return true
    end
    for _, c in ipairs(espConns) do
        pcall(function() c:Disconnect() end)
    end
    espConns = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then
            pcall(espClearChar, pl.Character)
        end
    end
    return false
end

-- ==================== 加速 ====================
local function applySpeed()
    local _, _, hum = getCharParts()
    if hum then
        pcall(function()
            hum.WalkSpeed = WALK_SPEEDS[feat.speed.level] or 26
        end)
    end
end

local function setSpeed(on)
    local _, _, hum = getCharParts()
    if on then
        if hum then
            applySpeed()
        end
        return true
    end
    if hum then
        pcall(function()
            hum.WalkSpeed = origWalk or 16
        end)
    end
    return false
end

-- ==================== 跳跃 ====================
local function applyJump()
    local _, _, hum = getCharParts()
    if not hum then
        return
    end
    pcall(function()
        -- 两套环境兼容：哪套生效用哪套，两个都设置
        hum.JumpPower = JUMP_POWERS[feat.jump.level] or 80
        hum.JumpHeight = JUMP_HEIGHTS[feat.jump.level] or 13
    end)
end

local function setJump(on)
    local _, _, hum = getCharParts()
    if on then
        if hum then
            applyJump()
        end
        return true
    end
    if hum then
        pcall(function()
            hum.JumpPower = origJumpPower or 50
            hum.JumpHeight = origJumpHeight or 7.2
        end)
    end
    return false
end

-- ==================== 锁头 ====================
local AIM_BIND_NAME = "YQ_Aim_v01"
local aimBound = false

local function aimStep(dt)
    if not feat.aim.enabled then
        return
    end
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChildOfClass("Tool") then
        return -- 只有手持近战 / 枪械时才锁
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return
    end
    local cam = WorkspaceService.CurrentCamera
    if not cam then
        return
    end
    -- 队友判定：自己有队伍时同队为队友；自己无队伍则全员算敌人
    local myTeam = LocalPlayer.Team
    local best = nil
    local bestDist = nil
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer then
            local enemy = true
            if myTeam ~= nil and pl.Team == myTeam then
                enemy = false
            end
            if enemy then
                local c = pl.Character
                if c then
                    local head = c:FindFirstChild("Head")
                    local hum = c:FindFirstChildOfClass("Humanoid")
                    if head and hum and hum.Health > 0 then
                        local d = (head.Position - hrp.Position).Magnitude
                        if d > 0.5 and (bestDist == nil or d < bestDist) then
                            bestDist = d
                            best = head
                        end
                    end
                end
            end
        end
    end
    if not best then
        return -- 无有效目标不动作
    end
    local dtc = math.clamp(dt or 0.016, 0.001, 0.1)
    local k = AIM_STRENGTHS[feat.aim.level] or 10
    local alpha = 1 - math.exp(-k * dtc)
    local targetCF = CFrame.new(cam.CFrame.Position, best.Position)
    cam.CFrame = cam.CFrame:Lerp(targetCF, alpha)
end

local function bindAim()
    if aimBound then
        return
    end
    aimBound = true
    -- 挂在相机更新之后，平滑压过去不干扰正常视角操作
    local ok = pcall(function()
        RunService:BindToRenderStep(AIM_BIND_NAME,
            Enum.RenderPriority.Camera.Value + 1, aimStep)
    end)
    if not ok then
        aimBound = false
        table.insert(globalConnections,
            RunService.RenderStepped:Connect(aimStep))
    end
end

local function unbindAim()
    if aimBound then
        pcall(function()
            RunService:UnbindFromRenderStep(AIM_BIND_NAME)
        end)
        aimBound = false
    end
end

local function setAim(on)
    if on then
        bindAim()
        return true
    end
    unbindAim()
    return false
end

-- ==================== 功能开关统一入口 ====================
local APPLYERS = {
    esp = setEsp,
    fly = setFly,
    speed = setSpeed,
    jump = setJump,
    aim = setAim,
}

local function enableFeature(name, on)
    local f = feat[name]
    if not f then
        return
    end
    local _, res = pcall(APPLYERS[name], on)
    if name == "fly" then
        -- 飞行以实际挂载结果为准（角色不在时开不起来）
        f.enabled = (on and res == true) and true or false
    else
        f.enabled = on
    end
    if refreshUI then
        pcall(refreshUI)
    end
end

local function setLevel(name, n)
    local f = feat[name]
    if not f or n < 1 or n > 5 then
        return
    end
    f.level = n
    -- 点档位即生效：没开的自动开启
    if not f.enabled then
        enableFeature(name, true)
        return
    end
    if name == "speed" then
        pcall(applySpeed)
    elseif name == "jump" then
        pcall(applyJump)
    end
    -- 飞行 / 锁头的档位每帧实时读取，无需重挂
    if refreshUI then
        pcall(refreshUI)
    end
end

local function disableAll()
    for _, name in ipairs(featOrder) do
        if feat[name].enabled then
            pcall(enableFeature, name, false)
        end
    end
end

-- ==================== 界面 ====================
screenGui = Instance.new("ScreenGui")
screenGui.Name = "YQING_ScriptGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100000
screenGui.IgnoreGuiInset = true

-- ScreenGui：优先挂 CoreGui（注入器环境），失败退回 PlayerGui
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
    Name = "YQ_Ball",
    Text = "雅",
    TextColor3 = COLOR_TEXT,
    TextSize = 26,
    Font = Enum.Font.GothamBold,
    BackgroundColor3 = Color3.fromRGB(22, 24, 28),
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Active = true,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.88, 0, 0.30, 0),
    Size = UDim2.new(0, 64, 0, 64),
    ZIndex = 5,
})
addCorner(ball, 32)
addStroke(ball, COLOR_ACCENT, 2, 0.3)
local ballScale = addScale(ball)
ball.Parent = screenGui

-- ---------- 主面板 ----------
local panel = Instance.new("Frame")
setProps(panel, {
    Name = "YQ_Panel",
    BackgroundColor3 = COLOR_PANEL,
    BackgroundTransparency = 0.08,
    BorderSizePixel = 0,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(0, 340, 0, 480),
    Visible = false,
    ZIndex = 10,
})
addCorner(panel, 16)
addStroke(panel, COLOR_ACCENT, 1, 0.65)
local panelScale = addScale(panel)
panel.Parent = screenGui

-- 标题 + 右侧小字
local titleLabel = Instance.new("TextLabel")
setProps(titleLabel, {
    Text = "雅清脚本",
    TextColor3 = COLOR_TEXT,
    TextSize = 21,
    Font = Enum.Font.GothamBold,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 16, 0, 8),
    Size = UDim2.new(0, 160, 0, 30),
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 11,
})
titleLabel.Parent = panel

local subLabel = Instance.new("TextLabel")
setProps(subLabel, {
    Text = "_雅清制作v0.1",
    TextColor3 = COLOR_SUB,
    TextSize = 12,
    Font = Enum.Font.GothamMedium,
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -16, 0, 15),
    Size = UDim2.new(0, 130, 0, 18),
    TextXAlignment = Enum.TextXAlignment.Right,
    ZIndex = 11,
})
subLabel.Parent = panel

-- 分隔线
local divider = Instance.new("Frame")
setProps(divider, {
    BackgroundColor3 = COLOR_ACCENT,
    BackgroundTransparency = 0.72,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 14, 0, 44),
    Size = UDim2.new(0, 312, 0, 1),
    ZIndex = 11,
})
divider.Parent = panel

-- 实时时钟（每秒刷新）
local clockLabel = Instance.new("TextLabel")
setProps(clockLabel, {
    Name = "Clock",
    Text = "--:--:--",
    TextColor3 = COLOR_ACCENT,
    TextSize = 14,
    Font = Enum.Font.GothamMedium,
    BackgroundColor3 = COLOR_DARK,
    BorderSizePixel = 0,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 52),
    Size = UDim2.new(0, 120, 0, 26),
    ZIndex = 11,
})
addCorner(clockLabel, 13)
clockLabel.Parent = panel

local function updateClock()
    local ok, t = pcall(os.date, "*t")
    if ok and t and t.hour then
        pcall(function()
            clockLabel.Text = string.format("%02d:%02d:%02d",
                t.hour, t.min, t.sec)
        end)
    end
end

-- ---------- 功能行 / 子面板构建 ----------
local rows = {}         -- 功能行按钮
local subs = {}         -- 子面板
local toggles = {}      -- 子面板里的开关
local levelBtns = {}    -- 档位按钮 [功能名][1~5]
local nameLabels = {}   -- 行左侧名称
local statusLabels = {} -- 行右侧状态
local expanded = {}     -- 子面板展开状态
local SUB_H = { esp = 60, fly = 112, speed = 112, jump = 112, aim = 140 }

local function buildFeatureUI(name)
    local f = feat[name]

    local row = Instance.new("TextButton")
    setProps(row, {
        Name = "Row_" .. name,
        Text = "",
        TextColor3 = COLOR_TEXT,
        TextSize = 18,
        Font = Enum.Font.GothamMedium,
        BackgroundColor3 = COLOR_BTN,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Size = UDim2.new(0, 312, 0, 48),
        ZIndex = 11,
    })
    addCorner(row, 12)
    row.Parent = panel
    rows[name] = row

    local nl = Instance.new("TextLabel")
    setProps(nl, {
        BackgroundTransparency = 1,
        Text = "▸  " .. f.title,
        TextColor3 = COLOR_TEXT,
        TextSize = 18,
        Font = Enum.Font.GothamMedium,
        Position = UDim2.new(0, 14, 0, 0),
        Size = UDim2.new(0, 150, 0, 48),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 12,
    })
    nl.Parent = row
    nameLabels[name] = nl

    local st = Instance.new("TextLabel")
    setProps(st, {
        BackgroundTransparency = 1,
        Text = "未开启",
        TextColor3 = COLOR_SUB,
        TextSize = 14,
        Font = Enum.Font.GothamMedium,
        Position = UDim2.new(1, -104, 0, 0),
        Size = UDim2.new(0, 96, 0, 48),
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 12,
    })
    st.Parent = row
    statusLabels[name] = st

    local sub = Instance.new("Frame")
    setProps(sub, {
        Name = "Sub_" .. name,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 312, 0, SUB_H[name]),
        Visible = false,
        ZIndex = 11,
    })
    sub.Parent = panel
    subs[name] = sub

    -- 子面板：开关按钮
    local tg = Instance.new("TextButton")
    setProps(tg, {
        Name = "Toggle",
        Text = f.title .. "：关闭",
        TextColor3 = COLOR_TEXT,
        TextSize = 18,
        Font = Enum.Font.GothamBold,
        BackgroundColor3 = COLOR_BTN2,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(0, 312, 0, 48),
        ZIndex = 12,
    })
    addCorner(tg, 12)
    tg.Parent = sub
    toggles[name] = tg

    -- 子面板：档位按钮（透视无档位）
    if name ~= "esp" then
        local lvRow = {}
        for i = 1, 5 do
            local b = Instance.new("TextButton")
            setProps(b, {
                Name = "Lv" .. i,
                Text = tostring(i) .. "档",
                TextColor3 = COLOR_TEXT,
                TextSize = 15,
                Font = Enum.Font.GothamBold,
                BackgroundColor3 = COLOR_BTN,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Position = UDim2.new(0, (i - 1) * 63, 0, 56),
                Size = UDim2.new(0, 60, 0, 44),
                ZIndex = 12,
            })
            addCorner(b, 10)
            b.Parent = sub
            lvRow[i] = b
            b.Activated:Connect(function()
                pcall(setLevel, name, i)
            end)
        end
        levelBtns[name] = lvRow
    end

    -- 锁头子面板：队伍前提提示
    if name == "aim" then
        local hint = Instance.new("TextLabel")
        setProps(hint, {
            BackgroundTransparency = 1,
            Text = "提示：需地图有队伍才能区分队友；自己无队伍时全员视为敌人",
            TextColor3 = COLOR_SUB,
            TextSize = 12,
            Font = Enum.Font.Gotham,
            Position = UDim2.new(0, 2, 0, 106),
            Size = UDim2.new(0, 308, 0, 30),
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 12,
        })
        hint.Parent = sub
    end

    -- 行点击：展开 / 收起（同时收起其他，保持面板整洁）
    row.Activated:Connect(function()
        local willOpen = not expanded[name]
        for _, other in ipairs(featOrder) do
            expanded[other] = false
        end
        expanded[name] = willOpen
        pcall(relayout)
        pcall(refreshUI)
    end)

    -- 开关点击
    tg.Activated:Connect(function()
        pcall(enableFeature, name, not feat[name].enabled)
    end)
end

for _, name in ipairs(featOrder) do
    buildFeatureUI(name)
end

-- ---------- 底部：一键全关 + 关闭脚本 ----------
local allOffBtn = Instance.new("TextButton")
setProps(allOffBtn, {
    Name = "AllOff",
    Text = "一键全关",
    TextColor3 = COLOR_TEXT,
    TextSize = 17,
    Font = Enum.Font.GothamBold,
    BackgroundColor3 = Color3.fromRGB(64, 46, 48),
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Size = UDim2.new(0, 312, 0, 46),
    ZIndex = 11,
})
addCorner(allOffBtn, 12)
allOffBtn.Parent = panel
allOffBtn.Activated:Connect(function()
    pcall(disableAll)
end)

local killBtn = Instance.new("TextButton")
setProps(killBtn, {
    Name = "Kill",
    Text = "关闭脚本",
    TextColor3 = COLOR_SUB,
    TextSize = 16,
    Font = Enum.Font.GothamMedium,
    BackgroundColor3 = COLOR_BTN,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Size = UDim2.new(0, 312, 0, 42),
    ZIndex = 11,
})
addCorner(killBtn, 12)
killBtn.Parent = panel

-- ---------- 布局：从上到下排布，面板高度自适应 ----------
relayout = function()
    local y = 86 -- 头部区高度（标题 + 时钟）
    for _, name in ipairs(featOrder) do
        rows[name].Position = UDim2.new(0, 14, 0, y)
        y = y + 48 + 8
        if expanded[name] then
            subs[name].Position = UDim2.new(0, 14, 0, y)
            subs[name].Visible = true
            y = y + SUB_H[name] + 8
        else
            subs[name].Visible = false
        end
    end
    allOffBtn.Position = UDim2.new(0, 14, 0, y)
    y = y + 46 + 8
    killBtn.Position = UDim2.new(0, 14, 0, y)
    y = y + 42 + 14
    panel.Size = UDim2.new(0, 340, 0, y)
end

-- ---------- 刷新全部界面状态 ----------
refreshUI = function()
    for _, name in ipairs(featOrder) do
        local f = feat[name]
        nameLabels[name].Text = (expanded[name] and "▾  " or "▸  ")
            .. f.title
        rows[name].BackgroundColor3 = expanded[name]
            and COLOR_BTN2 or COLOR_BTN
        local st = statusLabels[name]
        if f.enabled then
            st.Text = (name == "esp") and "已开启"
                or ("已开启 · " .. tostring(f.level) .. "档")
            st.TextColor3 = COLOR_ACCENT
        else
            st.Text = "未开启"
            st.TextColor3 = COLOR_SUB
        end
        local tg = toggles[name]
        if f.enabled then
            tg.Text = f.title .. "：已开启"
            tg.BackgroundColor3 = COLOR_ACCENT
            tg.TextColor3 = COLOR_DARK
        else
            tg.Text = f.title .. "：关闭"
            tg.BackgroundColor3 = COLOR_BTN2
            tg.TextColor3 = COLOR_TEXT
        end
        if levelBtns[name] then
            for i = 1, 5 do
                local b = levelBtns[name][i]
                if i == f.level then
                    b.BackgroundColor3 = COLOR_ACCENT
                    b.TextColor3 = COLOR_DARK
                else
                    b.BackgroundColor3 = COLOR_BTN
                    b.TextColor3 = COLOR_TEXT
                end
            end
        end
    end
end

togglePanel = function()
    panel.Visible = not panel.Visible
    if panel.Visible then
        pcall(relayout)
        pcall(refreshUI)
    end
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

-- ---------- 每帧驱动：飞行 + 时钟 + 分辨率自适应 ----------
track(RunService.RenderStepped:Connect(function(dt)
    pcall(flyStep, dt)
end))

local curScale = 0
track(RunService.RenderStepped:Connect(function()
    updateClock()
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

-- ---------- 角色绑定（重生自动重绑 + 恢复默认用原始值） ----------
local function bindCharacter(char)
    for _, c in ipairs(charConnections) do
        pcall(function() c:Disconnect() end)
    end
    charConnections = {}
    local ok, hum = pcall(function()
        return char:WaitForChild("Humanoid", 8)
    end)
    if not ok or not hum then
        return
    end
    -- 在应用任何功能前记录原始数值
    pcall(function()
        origWalk = hum.WalkSpeed
        origJumpPower = hum.JumpPower
        origJumpHeight = hum.JumpHeight
    end)
    table.insert(charConnections, hum.Died:Connect(function()
        cleanupMovers()
    end))
    -- 已开启的功能在新角色上自动重新应用
    if feat.speed.enabled then
        pcall(applySpeed)
    end
    if feat.jump.enabled then
        pcall(applyJump)
    end
end

track(LocalPlayer.CharacterAdded:Connect(function(char)
    bodyGyro = nil
    bodyVelocity = nil
    pcall(bindCharacter, char)
    -- 飞行开着时重生自动重新起飞
    if feat.fly.enabled then
        delayCall(0.1, function()
            local c = LocalPlayer.Character
            if not c or not feat.fly.enabled then
                return
            end
            local hrp = c:WaitForChild("HumanoidRootPart", 8)
            if feat.fly.enabled and hrp then
                pcall(startFlight)
            end
        end)
    end
end))

track(LocalPlayer.CharacterRemoving:Connect(function()
    cleanupMovers()
end))

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
    -- 依次关闭所有功能（恢复速度 / 跳跃 / 清理透视 / 停锁头 / 停飞行）
    for _, name in ipairs(featOrder) do
        if feat[name].enabled then
            pcall(enableFeature, name, false)
        end
    end
    unbindAim()
    for _, c in ipairs(globalConnections) do
        pcall(function() c:Disconnect() end)
    end
    globalConnections = {}
    for _, c in ipairs(charConnections) do
        pcall(function() c:Disconnect() end)
    end
    charConnections = {}
    for _, c in ipairs(espConns) do
        pcall(function() c:Disconnect() end)
    end
    espConns = {}
    cleanupMovers()
    -- 恢复角色正常状态
    local _, _, hum = getCharParts()
    if hum and hum.Health > 0 then
        pcall(function()
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end
    if screenGui then
        pcall(function() screenGui:Destroy() end)
        screenGui = nil
    end
    _G.YQING_SCRIPT_UNLOAD = nil
end
_G.YQING_SCRIPT_UNLOAD = unload

-- ---------- 初始化 ----------
pcall(relayout)
pcall(refreshUI)
updateClock()
if LocalPlayer.Character then
    pcall(bindCharacter, LocalPlayer.Character)
end
