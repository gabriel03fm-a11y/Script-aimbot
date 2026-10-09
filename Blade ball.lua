--[[
    ═══════════════════════════════════════════════════════════════════
    BLADE BALL — ADVANCED AUTOMATION SUITE  (v1.0.1 - FIX)
    Correção principal: removido uso inválido de Instance.new(cls, props)
    que abortava o build() da UI, deixando a janela vazia.
    ═══════════════════════════════════════════════════════════════════
--]]

-- ============================================================
-- 1. SERVIÇOS E CONSTANTES
-- ============================================================
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local UserInputService    = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService        = game:GetService("TweenService")
local HttpService         = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local CONFIG_FOLDER  = "BladeBallSuite"
local PARRY_COOLDOWN = 0.5
local MAX_PARRY_HISTORY = 3

-- ============================================================
-- 2. SIGNAL
-- ============================================================
local Signal = {}
Signal.__index = Signal
function Signal.new()
    return setmetatable({ _connections = {} }, Signal)
end
function Signal:Connect(event, cb)
    local c = event:Connect(cb)
    table.insert(self._connections, c)
    return c
end
function Signal:DisconnectAll()
    for _, c in ipairs(self._connections) do pcall(function() c:Disconnect() end) end
    self._connections = {}
end

-- ============================================================
-- 3. CONFIG MANAGER
-- ============================================================
local DEFAULT_CONFIG = {
    autoParryEnabled=false, manualSpamEnabled=false,
    delayMs=0, parryRange=18, sensitivity=50,
    legitMode=false, fastReactMode=false, antiRepeatEnabled=true,
    ballESP=false, ballHighlight=false, showTrajectory=false,
    showDistance=false, showSpeed=false, playerESP=false,
    playerHighlight=false, showThreatIndicator=true,
    uiScale=1.0, notifications=true, theme="Dark",
    keybindMenu="RightShift", keybindAutoParry="F",
    keybindManualSpam="G", keybindESP="H", keybindLegitMode="J",
    spamFrequency=50,
}

local ConfigManager = {}
ConfigManager.__index = ConfigManager

function ConfigManager.new()
    local self = setmetatable({}, ConfigManager)
    self.currentProfile = "default"
    self.data = {}
    for k, v in pairs(DEFAULT_CONFIG) do self.data[k] = v end
    return self
end
function ConfigManager:set(k, v) if self.data[k] ~= nil then self.data[k] = v end end
function ConfigManager:get(k) return self.data[k] end

function ConfigManager:save(profile)
    profile = profile or self.currentProfile
    local ok = pcall(function()
        if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
        writefile(CONFIG_FOLDER .. "/" .. profile .. ".json", HttpService:JSONEncode(self.data))
    end)
    return ok
end
function ConfigManager:load(profile)
    profile = profile or self.currentProfile
    local ok, data = pcall(function()
        local p = CONFIG_FOLDER .. "/" .. profile .. ".json"
        if isfile(p) then return HttpService:JSONDecode(readfile(p)) end
    end)
    if ok and data then
        for k, v in pairs(data) do if self.data[k] ~= nil then self.data[k] = v end end
        return true
    end
    return false
end
function ConfigManager:reset()
    for k, v in pairs(DEFAULT_CONFIG) do self.data[k] = v end
    self:save()
end

-- ============================================================
-- 4. ESTADO GLOBAL
-- ============================================================
local State = {
    currentBall=nil, ballTarget=nil, ballDistance=math.huge,
    ballSpeed=0, ballPosition=Vector3.zero,
    localHRP=nil, lastParryTime=0, parryHistory={},
    threatDetected=false, fps=0, ping=0,
    ui={}, signals=Signal.new(),
}

-- ============================================================
-- 5. BALL TRACKER
-- ============================================================
local BallTracker = {}
BallTracker.__index = BallTracker
function BallTracker.new() return setmetatable({}, BallTracker) end

function BallTracker:getActiveBall()
    local f = workspace:FindFirstChild("Balls")
    if not f then return nil end
    for _, b in ipairs(f:GetChildren()) do
        if b:GetAttribute("realBall") then return b end
    end
    return nil
end
function BallTracker:start()
    local folder = workspace:FindFirstChild("Balls")
    if folder then
        self._ballConn = folder.ChildAdded:Connect(function()
            task.wait(0.1); State.currentBall = self:getActiveBall()
        end)
    end
    self._conn = RunService.PreSimulation:Connect(function()
        local ball = self:getActiveBall()
        if not ball then State.currentBall = nil return end
        State.currentBall = ball
        pcall(function()
            State.ballTarget   = ball:GetAttribute("target")
            State.ballPosition = ball.Position
            local z = ball:FindFirstChild("zoomies")
            State.ballSpeed = (z and z:IsA("BodyVelocity")) and z.VectorVelocity.Magnitude or 0
        end)
    end)
end
function BallTracker:stop()
    if self._conn then self._conn:Disconnect() self._conn = nil end
    if self._ballConn then self._ballConn:Disconnect() self._ballConn = nil end
end

-- ============================================================
-- 6. THREAT ANALYZER
-- ============================================================
local ThreatAnalyzer = {}
ThreatAnalyzer.__index = ThreatAnalyzer
function ThreatAnalyzer.new() return setmetatable({}, ThreatAnalyzer) end

function ThreatAnalyzer:isThreat(cfg)
    local ball, hrp = State.currentBall, State.localHRP
    if not ball or not hrp then return false, 0, math.huge end
    if State.ballTarget ~= LocalPlayer.Name then return false, 0, math.huge end

    local ballPos, hrpPos = State.ballPosition, hrp.Position
    local dist  = (hrpPos - ballPos).Magnitude
    local speed = State.ballSpeed

    if dist > cfg.parryRange or speed < 5 then return false, dist, math.huge end

    local z = ball:FindFirstChild("zoomies")
    if z and z:IsA("BodyVelocity") then
        local dot = z.VectorVelocity.Unit:Dot((hrpPos - ballPos).Unit)
        if dot < 0.3 then return false, dist, math.huge end
    end
    return true, dist, dist / math.max(speed, 0.1)
end

function ThreatAnalyzer:getParryThreshold(cfg)
    local t = 0.35
    t = t * (1.0 - (cfg.sensitivity / 100) * 0.5)
    t = t + (cfg.delayMs / 1000)
    if cfg.fastReactMode then t = t * 0.6 end
    if cfg.legitMode      then t = t * (0.85 + math.random() * 0.3) end
    return math.max(0.02, t)
end

-- ============================================================
-- 7. PARRY ENGINE
-- ============================================================
local ParryEngine = {}
ParryEngine.__index = ParryEngine
function ParryEngine.new()
    return setmetatable({ _spamConn=nil, _lastSpamTime=0 }, ParryEngine)
end

function ParryEngine:executeParry()
    local now = tick()
    if now - State.lastParryTime < PARRY_COOLDOWN then return false end
    if ConfigManager:get("antiRepeatEnabled") then
        for _, t in ipairs(State.parryHistory) do
            if now - t < 0.15 then return false end
        end
    end
    local ok = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true,  game, 0)
        task.wait(0.02)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end)
    if ok then
        State.lastParryTime = now
        table.insert(State.parryHistory, now)
        while #State.parryHistory > MAX_PARRY_HISTORY do
            table.remove(State.parryHistory, 1)
        end
        return true
    end
    return false
end

function ParryEngine:update()
    if not ConfigManager:get("autoParryEnabled") then
        if State.threatDetected then
            State.threatDetected = false
            if State.ui.threatIndicator then State.ui.threatIndicator.Visible = false end
        end
        return
    end
    if not State.localHRP then return end

    local isThreat, _, tti = ThreatAnalyzer:isThreat(ConfigManager.data)

    if isThreat ~= State.threatDetected then
        State.threatDetected = isThreat
        if State.ui.threatIndicator and ConfigManager:get("showThreatIndicator") then
            State.ui.threatIndicator.Visible = isThreat
        end
    end

    if isThreat and tti <= ThreatAnalyzer:getParryThreshold(ConfigManager.data) then
        ParryEngine:executeParry()
    end
end

function ParryEngine:startManualSpam()
    self:stopManualSpam()
    self._spamConn = RunService.Heartbeat:Connect(function()
        if not ConfigManager:get("manualSpamEnabled") then return end
        local now = tick()
        if now - self._lastSpamTime >= (ConfigManager:get("spamFrequency") / 1000) then
            ParryEngine:executeParry()
            self._lastSpamTime = now
        end
    end)
end
function ParryEngine:stopManualSpam()
    if self._spamConn then self._spamConn:Disconnect() self._spamConn = nil end
end

-- ============================================================
-- 8. MANUAL SPAM OVERLAY
-- ============================================================
local ManualSpam = {}
ManualSpam.__index = ManualSpam
function ManualSpam.new()
    return setmetatable({ _frame=nil, _label=nil, _mode="AP" }, ManualSpam)
end
function ManualSpam:create(parent)
    local frame = Instance.new("Frame")
    frame.Name = "ManualSpamButton"
    frame.Size = UDim2.new(0, 60, 0, 30)
    frame.Position = UDim2.new(0.5, -30, 0.85, 0)
    frame.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.ZIndex = 50
    frame.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8); corner.Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 180, 50); stroke.Thickness = 1.5; stroke.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "AP"; label.TextColor3 = Color3.fromRGB(255,255,255)
    label.TextScaled = true; label.Font = Enum.Font.GothamBold
    label.Parent = frame

    self._frame, self._label = frame, label

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1
    btn.Text = ""; btn.Parent = frame

    btn.MouseButton1Click:Connect(function()
        if self._mode == "AP" then
            self._mode = "TB"; label.Text = "TB"
            frame.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
            stroke.Color = Color3.fromRGB(0, 160, 255)
        else
            self._mode = "AP"; label.Text = "AP"
            frame.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
            stroke.Color = Color3.fromRGB(255, 180, 50)
        end
    end)

    local dragging, dragStart, startPos
    btn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = frame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                       startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    return self
end
function ManualSpam:setVisible(v) if self._frame then self._frame.Visible = v end end

-- ============================================================
-- 9. VISUALS
-- ============================================================
local Visuals = {}
Visuals.__index = Visuals
function Visuals.new()
    return setmetatable({ _highlight=nil, _espGui=nil, _trajectory={}, _playerGuis={} }, Visuals)
end

function Visuals:updateBallHighlight()
    local ball = State.currentBall
    if not ball or not ConfigManager:get("ballHighlight") then
        if self._highlight then self._highlight:Destroy() self._highlight = nil end
        return
    end
    if not self._highlight or self._highlight.Parent ~= ball then
        if self._highlight then self._highlight:Destroy() end
        local hl = Instance.new("Highlight")
        hl.FillTransparency = 0.6; hl.OutlineTransparency = 0.2
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = ball
        self._highlight = hl
    end
    local d = State.ballDistance
    if d < 15 then self._highlight.FillColor = Color3.fromRGB(255, 50, 50)
    elseif d < 40 then self._highlight.FillColor = Color3.fromRGB(255, 180, 0)
    else self._highlight.FillColor = Color3.fromRGB(0, 200, 100) end
    self._highlight.OutlineColor = self._highlight.FillColor:Lerp(Color3.new(1,1,1), 0.4)
end

function Visuals:updateBallESP()
    local ball = State.currentBall
    if not ball or not ConfigManager:get("ballESP") then
        if self._espGui then self._espGui:Destroy() self._espGui = nil end
        return
    end
    if not self._espGui or self._espGui.Parent ~= ball then
        if self._espGui then self._espGui:Destroy() end
        local gui = Instance.new("BillboardGui")
        gui.Name = "BallESP"
        gui.Size = UDim2.new(0, 150, 0, 40)
        gui.StudsOffset = Vector3.new(0, 3, 0)
        gui.AlwaysOnTop = true
        gui.Parent = ball
        local lbl = Instance.new("TextLabel")
        lbl.Name = "InfoLabel"; lbl.Size = UDim2.new(1,0,1,0)
        lbl.BackgroundTransparency = 1; lbl.TextSize = 14
        lbl.Font = Enum.Font.GothamBold; lbl.TextStrokeTransparency = 0.5
        lbl.Parent = gui
        self._espGui = gui
    end
    local parts = {}
    if ConfigManager:get("showDistance") then table.insert(parts, string.format("Dist: %.0f", State.ballDistance)) end
    if ConfigManager:get("showSpeed")    then table.insert(parts, string.format("Spd: %.0f", State.ballSpeed)) end
    if #parts == 0 then table.insert(parts, "BALL") end
    local lbl = self._espGui:FindFirstChild("InfoLabel")
    if lbl then
        lbl.Text = table.concat(parts, " | ")
        if State.ballDistance < 15 then lbl.TextColor3 = Color3.fromRGB(255,60,60)
        elseif State.ballDistance < 40 then lbl.TextColor3 = Color3.fromRGB(255,200,0)
        else lbl.TextColor3 = Color3.fromRGB(100,255,100) end
    end
end

function Visuals:updateTrajectory()
    for _, p in ipairs(self._trajectory) do pcall(function() p:Destroy() end) end
    self._trajectory = {}
    if not ConfigManager:get("showTrajectory") then return end
    local ball, hrp = State.currentBall, State.localHRP
    if not ball or not hrp then return end
    local dir = hrp.Position - State.ballPosition
    local dist = dir.Magnitude
    if dist < 1 then return end
    dir = dir.Unit
    local steps = math.min(8, math.floor(dist / 5))
    for i = 1, steps do
        local pos = State.ballPosition + dir * (dist * i / (steps + 1))
        local part = Instance.new("Part")
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(0.3, 0.3, 0.3)
        part.Position = pos
        part.Anchored = true; part.CanCollide = false
        part.CanQuery = false; part.CanTouch = false
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(255, 140, 0)
        part.Transparency = 0.4
        part.Parent = workspace
        table.insert(self._trajectory, part)
    end
end

function Visuals:updatePlayerESP()
    for plr, gui in pairs(self._playerGuis) do
        if not plr.Parent or not plr.Character then gui:Destroy() self._playerGuis[plr] = nil end
    end
    if not ConfigManager:get("playerESP") then
        for plr, gui in pairs(self._playerGuis) do gui:Destroy() self._playerGuis[plr] = nil end
        return
    end
    local hrp = State.localHRP
    if not hrp then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        local char = plr.Character
        local head = char and char:FindFirstChild("Head")
        if not head then
            if self._playerGuis[plr] then self._playerGuis[plr]:Destroy() self._playerGuis[plr] = nil end
            continue
        end
        if not self._playerGuis[plr] or self._playerGuis[plr].Parent ~= head then
            if self._playerGuis[plr] then self._playerGuis[plr]:Destroy() end
            local gui = Instance.new("BillboardGui")
            gui.Name = "PlayerESP"
            gui.Size = UDim2.new(0, 120, 0, 30)
            gui.StudsOffset = Vector3.new(0, 2.5, 0)
            gui.AlwaysOnTop = true
            gui.Parent = head
            local lbl = Instance.new("TextLabel")
            lbl.Name = "InfoLabel"; lbl.Size = UDim2.new(1,0,1,0)
            lbl.BackgroundTransparency = 1; lbl.TextSize = 12
            lbl.Font = Enum.Font.Gotham; lbl.TextStrokeTransparency = 0.5
            lbl.Parent = gui
            self._playerGuis[plr] = gui
        end
        local pRoot = char:FindFirstChild("HumanoidRootPart")
        if pRoot then
            local dist = (hrp.Position - pRoot.Position).Magnitude
            local lbl = self._playerGuis[plr]:FindFirstChild("InfoLabel")
            if lbl then
                lbl.Text = string.format("%s [%.0f]", plr.Name, dist)
                lbl.TextColor3 = (State.ballTarget == plr.Name)
                    and Color3.fromRGB(255, 80, 80)
                    or  Color3.fromRGB(255, 255, 255)
            end
        end
    end
end

function Visuals:start()
    self._conn = RunService.RenderStepped:Connect(function()
        if State.localHRP and State.currentBall then
            State.ballDistance = (State.localHRP.Position - State.ballPosition).Magnitude
        end
        Visuals:updateBallHighlight()
        Visuals:updateBallESP()
        Visuals:updateTrajectory()
        Visuals:updatePlayerESP()
    end)
end
function Visuals:stop()
    if self._conn then self._conn:Disconnect() self._conn = nil end
    for _, p in ipairs(self._trajectory) do pcall(function() p:Destroy() end) end
    self._trajectory = {}
    for plr, gui in pairs(self._playerGuis) do gui:Destroy() end
    self._playerGuis = {}
    if self._highlight then self._highlight:Destroy() self._highlight = nil end
    if self._espGui then self._espGui:Destroy() self._espGui = nil end
end

-- ============================================================
-- 10. UI CORE
-- ============================================================
local UICore = {}
UICore.__index = UICore

local COLORS = {
    bg=Color3.fromRGB(18,18,22), panel=Color3.fromRGB(25,25,32),
    panelAlt=Color3.fromRGB(32,32,40), accent=Color3.fromRGB(255,140,0),
    text=Color3.fromRGB(230,230,240), textDim=Color3.fromRGB(140,140,160),
    green=Color3.fromRGB(50,200,100), red=Color3.fromRGB(220,60,60),
    border=Color3.fromRGB(50,50,65),
}

function UICore.new()
    return setmetatable({
        toggleStates={}, _notifContainer=nil, _dragState=nil,
    }, UICore)
end

-- Helper: cria instância aplicando tabela de propriedades (correto!)
function UICore:_create(className, props, parent)
    local obj = Instance.new(className)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then
            pcall(function() obj[k] = v end)
        end
    end
    if parent then obj.Parent = parent end
    return obj
end

function UICore:_createToggle(parent, labelText, configKey, callback)
    local config = ConfigManager
    local frame = self:_create("Frame", {
        Name = "Toggle_" .. configKey,
        Size = UDim2.new(1, -20, 0, 36),
        BackgroundColor3 = COLORS.panelAlt,
        BorderSizePixel = 0,
    }, parent)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)

    self:_create("TextLabel", {
        Size = UDim2.new(1, -70, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = labelText, TextColor3 = COLORS.text, TextSize = 14,
        Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)

    local track = self:_create("Frame", {
        Size = UDim2.new(0, 44, 0, 22),
        Position = UDim2.new(1, -58, 0.5, -11),
        BackgroundColor3 = COLORS.border, BorderSizePixel = 0,
    }, frame)
    self:_create("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

    local knob = self:_create("Frame", {
        Size = UDim2.new(0, 18, 0, 18),
        Position = UDim2.new(0, 2, 0.5, -9),
        BackgroundColor3 = COLORS.textDim, BorderSizePixel = 0,
    }, track)
    self:_create("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

    local btn = self:_create("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1, Text = "",
    }, frame)

    local state = config:get(configKey) or false
    self.toggleStates[configKey] = state

    local function updateVisual(on)
        TweenService:Create(track, TweenInfo.new(0.2), {
            BackgroundColor3 = on and COLORS.accent or COLORS.border }):Play()
        TweenService:Create(knob, TweenInfo.new(0.2), {
            Position = on and UDim2.new(0, 24, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
            BackgroundColor3 = on and Color3.new(1,1,1) or COLORS.textDim }):Play()
    end
    updateVisual(state)

    btn.MouseButton1Click:Connect(function()
        state = not state
        self.toggleStates[configKey] = state
        config:set(configKey, state)
        updateVisual(state)
        if callback then pcall(callback, state) end
    end)
    return frame
end

function UICore:_createSlider(parent, labelText, configKey, min, max, suffix)
    local config = ConfigManager
    suffix = suffix or ""

    local frame = self:_create("Frame", {
        Size = UDim2.new(1, -20, 0, 56),
        BackgroundColor3 = COLORS.panelAlt, BorderSizePixel = 0,
    }, parent)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)

    self:_create("TextLabel", {
        Size = UDim2.new(0.6, 0, 0, 24),
        Position = UDim2.new(0, 12, 0, 6),
        BackgroundTransparency = 1, Text = labelText,
        TextColor3 = COLORS.text, TextSize = 14,
        Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)

    local valueLabel = self:_create("TextLabel", {
        Size = UDim2.new(0.3, 0, 0, 24),
        Position = UDim2.new(0.7, 0, 0, 6),
        BackgroundTransparency = 1,
        Text = tostring(config:get(configKey)) .. suffix,
        TextColor3 = COLORS.accent, TextSize = 14,
        Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Right,
    }, frame)

    local trackBg = self:_create("Frame", {
        Size = UDim2.new(1, -24, 0, 6),
        Position = UDim2.new(0, 12, 0, 38),
        BackgroundColor3 = COLORS.border, BorderSizePixel = 0,
    }, frame)
    self:_create("UICorner", { CornerRadius = UDim.new(1, 0) }, trackBg)

    local fill = self:_create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = COLORS.accent, BorderSizePixel = 0,
    }, trackBg)
    self:_create("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)

    local dragBtn = self:_create("TextButton", {
        Size = UDim2.new(1, 12, 1, 20),
        Position = UDim2.new(0, -6, 0.5, -10),
        BackgroundTransparency = 1, Text = "",
    }, trackBg)

    local function updateFromValue(val)
        val = math.clamp(val, min, max)
        local pct = (val - min) / math.max(max - min, 0.0001)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        valueLabel.Text = tostring(val) .. suffix
        config:set(configKey, val)
    end
    updateFromValue(config:get(configKey) or min)

    local dragging = false
    local function processInput(input)
        local trackPos  = trackBg.AbsolutePosition
        local trackSize = trackBg.AbsoluteSize
        local pct = math.clamp((input.Position.X - trackPos.X) / math.max(trackSize.X, 1), 0, 1)
        updateFromValue(math.floor(min + (max - min) * pct))
    end
    dragBtn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; processInput(i)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then processInput(i) end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    return frame
end

function UICore:_createInput(parent, labelText, configKey, placeholder)
    local frame = self:_create("Frame", {
        Size = UDim2.new(1, -20, 0, 40),
        BackgroundColor3 = COLORS.panelAlt, BorderSizePixel = 0,
    }, parent)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)

    self:_create("TextLabel", {
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1, Text = labelText,
        TextColor3 = COLORS.text, TextSize = 14,
        Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)

    local box = self:_create("TextBox", {
        Size = UDim2.new(0, 90, 0, 28),
        Position = UDim2.new(1, -102, 0.5, -14),
        BackgroundColor3 = COLORS.bg,
        Text = tostring(ConfigManager:get(configKey) or ""),
        TextColor3 = COLORS.accent, TextSize = 14,
        Font = Enum.Font.GothamBold,
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = COLORS.textDim,
        ClearTextOnFocus = false,
    }, frame)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 4) }, box)

    box.FocusLost:Connect(function()
        local txt = box.Text
        local num = tonumber(txt)
        ConfigManager:set(configKey, num or txt)
    end)
    return frame
end

function UICore:notify(title, text, duration)
    if not ConfigManager:get("notifications") then return end
    if not self.screenGui then return end
    duration = duration or 3

    if not self._notifContainer or not self._notifContainer.Parent then
        self._notifContainer = self:_create("Frame", {
            Name = "Notifications",
            Size = UDim2.new(0, 300, 1, -20),
            Position = UDim2.new(1, -310, 0, 10),
            BackgroundTransparency = 1,
        }, self.screenGui)
        self:_create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
        }, self._notifContainer)
    end

    local notif = self:_create("Frame", {
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor3 = COLORS.panel, BorderSizePixel = 0,
    }, self._notifContainer)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 8) }, notif)

    self:_create("Frame", {
        Size = UDim2.new(0, 4, 1, -12),
        Position = UDim2.new(0, 6, 0, 6),
        BackgroundColor3 = COLORS.accent, BorderSizePixel = 0,
    }, notif)

    self:_create("TextLabel", {
        Size = UDim2.new(1, -30, 0, 22),
        Position = UDim2.new(0, 18, 0, 6),
        BackgroundTransparency = 1, Text = title,
        TextColor3 = COLORS.accent, TextSize = 14,
        Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
    }, notif)
    self:_create("TextLabel", {
        Size = UDim2.new(1, -30, 0, 18),
        Position = UDim2.new(0, 18, 0, 26),
        BackgroundTransparency = 1, Text = text,
        TextColor3 = COLORS.textDim, TextSize = 12,
        Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
    }, notif)

    notif.Position = UDim2.new(1, 50, 0, 0)
    TweenService:Create(notif, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        { Position = UDim2.new(0, 0, 0, 0) }):Play()

    task.delay(duration, function()
        if notif and notif.Parent then
            local tw = TweenService:Create(notif, TweenInfo.new(0.3),
                { Position = UDim2.new(1, 50, 0, 0), BackgroundTransparency = 1 })
            tw:Play()
            tw.Completed:Connect(function() notif:Destroy() end)
        end
    end)
end

function UICore:build()
    -- Evita ScreenGui duplicada em re-execução
    local pg = LocalPlayer:WaitForChild("PlayerGui", 10)
    if not pg then warn("[BB] PlayerGui não encontrado") return end

    local existing = pg:FindFirstChild("BladeBallSuite")
    if existing then existing:Destroy() end

    self.screenGui = self:_create("ScreenGui", {
        Name = "BladeBallSuite",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
    }, pg)
    State.ui.screenGui = self.screenGui

    -- ==== JANELA PRINCIPAL ====
    local main = self:_create("Frame", {
        Name = "MainWindow",
        Size = UDim2.new(0, 560, 0, 420),
        Position = UDim2.new(0.5, -280, 0.5, -210),
        BackgroundColor3 = COLORS.bg,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, self.screenGui)
    self.mainFrame = main
    self:_create("UICorner", { CornerRadius = UDim.new(0, 10) }, main)
    self:_create("UIStroke", { Color = COLORS.border, Thickness = 1 }, main)

    -- ==== BARRA DE TÍTULO ====
    local titleBar = self:_create("Frame", {
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = COLORS.panel,
        BorderSizePixel = 0,
    }, main)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 10) }, titleBar)
    self:_create("Frame", {
        Size = UDim2.new(1, 0, 0, 10),
        Position = UDim2.new(0, 0, 1, -10),
        BackgroundColor3 = COLORS.panel, BorderSizePixel = 0,
    }, titleBar)

    self:_create("TextLabel", {
        Size = UDim2.new(0, 300, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1,
        Text = "⚔  BLADE BALL SUITE",
        TextColor3 = COLORS.accent, TextSize = 15,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, titleBar)

    -- Botão fechar
    local closeBtn = self:_create("TextButton", {
        Size = UDim2.new(0, 28, 0, 28),
        Position = UDim2.new(1, -36, 0.5, -14),
        BackgroundColor3 = COLORS.red,
        Text = "✕", TextColor3 = Color3.new(1,1,1),
        TextSize = 14, Font = Enum.Font.GothamBold,
    }, titleBar)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 6) }, closeBtn)
    closeBtn.MouseButton1Click:Connect(function()
        main.Visible = false
        if State.ui.floatingBtn then State.ui.floatingBtn.Visible = true end
    end)

    -- Arrastar
    local titleDrag = self:_create("TextButton", {
        Size = UDim2.new(1, -80, 1, 0),
        BackgroundTransparency = 1, Text = "",
    }, titleBar)
    local dragging, dragStart, startPos
    titleDrag.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                       startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)

    -- ==== BARRA DE ABAS ====
    local tabBar = self:_create("Frame", {
        Name = "TabBar",
        Size = UDim2.new(1, 0, 0, 34),
        Position = UDim2.new(0, 0, 0, 36),
        BackgroundColor3 = COLORS.panel,
        BorderSizePixel = 0,
    }, main)
    self:_create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 4),
    }, tabBar)
    self:_create("UIPadding", {
        PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 4),
    }, tabBar)

    -- ==== CONTEÚDO ====
    local content = self:_create("Frame", {
        Name = "Content",
        Size = UDim2.new(1, 0, 1, -70),
        Position = UDim2.new(0, 0, 0, 70),
        BackgroundTransparency = 1,
    }, main)

    local tabNames = { "Combat", "Visuals", "Settings" }
    local tabContents = {}
    local tabButtons = {}

    for i, name in ipairs(tabNames) do
        local tabBtn = self:_create("TextButton", {
            Name = "Tab_" .. name,
            Size = UDim2.new(0, 90, 0, 26),
            BackgroundColor3 = (i == 1) and COLORS.accent or COLORS.panelAlt,
            Text = name,
            TextColor3 = (i == 1) and Color3.new(1,1,1) or COLORS.textDim,
            TextSize = 13, Font = Enum.Font.GothamBold,
        }, tabBar)
        self:_create("UICorner", { CornerRadius = UDim.new(0, 6) }, tabBtn)
        tabButtons[name] = tabBtn

        local scroll = self:_create("ScrollingFrame", {
            Name = "Scroll_" .. name,
            Size = UDim2.new(1, -20, 1, -10),
            Position = UDim2.new(0, 10, 0, 5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = COLORS.accent,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            Visible = (i == 1),
        }, content)
        self:_create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
        }, scroll)

        tabContents[name] = scroll

        tabBtn.MouseButton1Click:Connect(function()
            for _, other in pairs(tabButtons) do
                other.BackgroundColor3 = COLORS.panelAlt
                other.TextColor3 = COLORS.textDim
            end
            tabBtn.BackgroundColor3 = COLORS.accent
            tabBtn.TextColor3 = Color3.new(1,1,1)
            for _, sc in pairs(tabContents) do sc.Visible = false end
            scroll.Visible = true
        end)
    end

    -- Recalcula CanvasSize sempre que o layout mudar
    for name, scroll in pairs(tabContents) do
        local layout = scroll:FindFirstChildOfClass("UIListLayout")
        local function updateCanvas()
            if layout then
                scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
            end
        end
        if layout then
            layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
        end
        scroll.ChildAdded:Connect(function() task.defer(updateCanvas) end)
        scroll.ChildRemoved:Connect(function() task.defer(updateCanvas) end)
        task.defer(updateCanvas)
    end

    -- ══════════ ABA COMBAT ══════════
    local combat = tabContents["Combat"]
    self:_create("TextLabel", {
        Size = UDim2.new(1, -20, 0, 24),
        BackgroundTransparency = 1, Text = "⚔  COMBAT",
        TextColor3 = COLORS.accent, TextSize = 16,
        Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
    }, combat)

    self:_createToggle(combat, "Auto Parry", "autoParryEnabled", function(on)
        UICore:notify("Auto Parry", on and "Ativado" or "Desativado", 2)
    end)
    self:_createToggle(combat, "Manual Spam (AP / TB)", "manualSpamEnabled", function(on)
        if State.ui.manualSpamBtn then State.ui.manualSpamBtn:setVisible(on) end
        UICore:notify("Manual Spam", on and "Ativado" or "Desativado", 2)
    end)
    self:_createSlider(combat, "Delay (pode ser negativo)", "delayMs", -100, 200, " ms")
    self:_createSlider(combat, "Range de ativação", "parryRange", 5, 60, " studs")
    self:_createSlider(combat, "Sensitivity", "sensitivity", 0, 100, "%")
    self:_createToggle(combat, "Legit Mode (humanizado)", "legitMode")
    self:_createToggle(combat, "Fast React Mode", "fastReactMode")
    self:_createToggle(combat, "Anti-Repeat Parry", "antiRepeatEnabled")
    self:_createSlider(combat, "Spam Frequency", "spamFrequency", 10, 200, " ms")

    -- ══════════ ABA VISUALS ══════════
    local vis = tabContents["Visuals"]
    self:_create("TextLabel", {
        Size = UDim2.new(1, -20, 0, 24),
        BackgroundTransparency = 1, Text = "👁  VISUALS",
        TextColor3 = COLORS.accent, TextSize = 16,
        Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
    }, vis)
    self:_createToggle(vis, "Ball ESP", "ballESP")
    self:_createToggle(vis, "Ball Highlight", "ballHighlight")
    self:_createToggle(vis, "Show Trajectory", "showTrajectory")
    self:_createToggle(vis, "Show Distance", "showDistance")
    self:_createToggle(vis, "Show Speed", "showSpeed")
    self:_createToggle(vis, "Player ESP", "playerESP")
    self:_createToggle(vis, "Threat Indicator", "showThreatIndicator")

    -- ══════════ ABA SETTINGS ══════════
    local set = tabContents["Settings"]
    self:_create("TextLabel", {
        Size = UDim2.new(1, -20, 0, 24),
        BackgroundTransparency = 1, Text = "⚙  SETTINGS",
        TextColor3 = COLORS.accent, TextSize = 16,
        Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
    }, set)
    self:_createToggle(set, "Notificações", "notifications")
    self:_createInput(set, "Tecla — Menu", "keybindMenu", "RightShift")
    self:_createInput(set, "Tecla — Auto Parry", "keybindAutoParry", "F")
    self:_createInput(set, "Tecla — Manual Spam", "keybindManualSpam", "G")
    self:_createInput(set, "Tecla — ESP", "keybindESP", "H")
    self:_createInput(set, "Tecla — Legit Mode", "keybindLegitMode", "J")

    -- Botões de config
    local btnRow = self:_create("Frame", {
        Size = UDim2.new(1, -20, 0, 32),
        BackgroundTransparency = 1,
    }, set)

    local function makeButton(label, color, xPos, onClick)
        local b = self:_create("TextButton", {
            Size = UDim2.new(0.3, -4, 1, 0),
            Position = UDim2.new(xPos, 0, 0, 0),
            BackgroundColor3 = color,
            Text = label, TextColor3 = Color3.new(1,1,1),
            TextSize = 13, Font = Enum.Font.GothamBold,
        }, btnRow)
        self:_create("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
        b.MouseButton1Click:Connect(onClick)
        return b
    end

    makeButton("Salvar",  COLORS.green, 0.00, function()
        UICore:notify("Config", ConfigManager:save() and "Salvo!" or "Falha ao salvar.", 2)
    end)
    makeButton("Carregar", Color3.fromRGB(60,120,200), 0.35, function()
        UICore:notify("Config", ConfigManager:load() and "Carregado!" or "Nada para carregar.", 2)
    end)
    makeButton("Reset",   COLORS.red, 0.70, function()
        ConfigManager:reset(); UICore:notify("Config", "Restaurado.", 2)
    end)

    -- ==== Botão flutuante (reabrir) ====
    local floatingBtn = self:_create("TextButton", {
        Name = "FloatingButton",
        Size = UDim2.new(0, 50, 0, 50),
        Position = UDim2.new(0, 20, 0.5, -25),
        BackgroundColor3 = COLORS.accent,
        Text = "⚔", TextColor3 = Color3.new(1,1,1),
        TextSize = 22, Font = Enum.Font.GothamBold,
        Visible = false, ZIndex = 10,
    }, self.screenGui)
    self:_create("UICorner", { CornerRadius = UDim.new(1, 0) }, floatingBtn)
    floatingBtn.MouseButton1Click:Connect(function()
        main.Visible = true
        floatingBtn.Visible = false
    end)
    State.ui.floatingBtn = floatingBtn
    State.ui.mainWindow = main

    -- ==== Indicador de ameaça ====
    local threat = self:_create("Frame", {
        Name = "ThreatIndicator",
        Size = UDim2.new(0, 140, 0, 26),
        Position = UDim2.new(0.5, -70, 0, 10),
        BackgroundColor3 = Color3.fromRGB(255, 40, 40),
        BorderSizePixel = 0, Visible = false, ZIndex = 100,
    }, self.screenGui)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 6) }, threat)
    self:_create("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1, Text = "⚠ THREAT DETECTED",
        TextColor3 = Color3.new(1,1,1), TextSize = 11,
        Font = Enum.Font.GothamBold,
    }, threat)
    State.ui.threatIndicator = threat

    -- ==== FPS/Ping ====
    local stats = self:_create("Frame", {
        Name = "Stats",
        Size = UDim2.new(0, 230, 0, 22),
        Position = UDim2.new(1, -240, 1, -30),
        BackgroundColor3 = COLORS.panel,
        BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 5,
    }, self.screenGui)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 6) }, stats)
    local statsLabel = self:_create("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "FPS: -- | Ping: -- | AP: OFF",
        TextColor3 = COLORS.textDim, TextSize = 11,
        Font = Enum.Font.Gotham,
    }, stats)
    State.ui.statsLabel = statsLabel

    -- ==== Manual Spam overlay ====
    State.ui.manualSpamBtn = ManualSpam.new()
    State.ui.manualSpamBtn:create(self.screenGui)

    return self
end

function UICore:startStatsLoop()
    local frames, lastTime = 0, tick()
    RunService.RenderStepped:Connect(function()
        frames = frames + 1
        local now = tick()
        if now - lastTime >= 1 then
            State.fps = frames; frames = 0; lastTime = now
        end
    end)
    task.spawn(function()
        while task.wait(0.5) do
            pcall(function()
                State.ping = LocalPlayer:GetNetworkPing() * 1000
                if State.ui.statsLabel then
                    State.ui.statsLabel.Text = string.format(
                        "FPS: %d | Ping: %.0fms | AP: %s | MS: %s",
                        State.fps, State.ping,
                        ConfigManager:get("autoParryEnabled")   and "ON" or "OFF",
                        ConfigManager:get("manualSpamEnabled")  and "ON" or "OFF"
                    )
                end
            end)
        end
    end)
end

-- ============================================================
-- 11. KEYBINDS
-- ============================================================
local KeybindManager = {}
KeybindManager.__index = KeybindManager
function KeybindManager.new() return setmetatable({}, KeybindManager) end

function KeybindManager:start()
    self._conn = UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        local key = input.KeyCode.Name

        if key == ConfigManager:get("keybindMenu") then
            if State.ui.mainWindow then
                State.ui.mainWindow.Visible = not State.ui.mainWindow.Visible
                if State.ui.floatingBtn then
                    State.ui.floatingBtn.Visible = not State.ui.mainWindow.Visible
                end
            end
        elseif key == ConfigManager:get("keybindAutoParry") then
            local s = not ConfigManager:get("autoParryEnabled")
            ConfigManager:set("autoParryEnabled", s)
            UICore:notify("Auto Parry", s and "Ativado" or "Desativado", 2)
        elseif key == ConfigManager:get("keybindManualSpam") then
            local s = not ConfigManager:get("manualSpamEnabled")
            ConfigManager:set("manualSpamEnabled", s)
            if State.ui.manualSpamBtn then State.ui.manualSpamBtn:setVisible(s) end
            UICore:notify("Manual Spam", s and "Ativado" or "Desativado", 2)
        elseif key == ConfigManager:get("keybindESP") then
            local s = not ConfigManager:get("ballESP")
            ConfigManager:set("ballESP", s)
            ConfigManager:set("ballHighlight", s)
            UICore:notify("ESP", s and "Ativado" or "Desativado", 2)
        elseif key == ConfigManager:get("keybindLegitMode") then
            local s = not ConfigManager:get("legitMode")
            ConfigManager:set("legitMode", s)
            UICore:notify("Legit Mode", s and "Ativado" or "Desativado", 2)
        end
    end)
end
function KeybindManager:stop()
    if self._conn then self._conn:Disconnect() self._conn = nil end
end

-- ============================================================
-- 12. INICIALIZAÇÃO
-- ============================================================
local config       = ConfigManager.new()
local ballTracker  = BallTracker.new()
local parryEngine  = ParryEngine.new()
local visuals      = Visuals.new()
local ui           = UICore.new()
local keybinds     = KeybindManager.new()

-- Substitui o "module" pelo instance em escopo local para os métodos usarem
ConfigManager = config
BallTracker   = ballTracker
ParryEngine   = parryEngine
Visuals       = visuals
UICore        = ui

-- Carrega config salva (se houver)
config:load()

-- Configuração de personagem
local function bindChar(char)
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    if hrp then State.localHRP = hrp end
end
if LocalPlayer.Character then bindChar(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(bindChar)
LocalPlayer.CharacterRemoving:Connect(function() State.localHRP = nil end)

-- Build da UI (protegido para não derrubar tudo se algo falhar)
local ok, err = pcall(function() ui:build() end)
if not ok then warn("[BB] Erro ao construir UI: " .. tostring(err)) end

ui:startStatsLoop()
ballTracker:start()
visuals:start()
keybinds:start()

-- Loop principal
State.signals:Connect(RunService.PreSimulation, function()
    pcall(function() ParryEngine:update() end)
end)

parryEngine:startManualSpam()

task.wait(1)
ui:notify("Blade Ball Suite", "Pronto! Pressione RightShift para abrir.", 4)

print("[BladeBallSuite] Inicializado com sucesso.")
