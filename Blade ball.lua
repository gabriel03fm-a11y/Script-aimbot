--[[
    SCRIPT: Aimbot + Hitbox Extender + ESP (Mobile UI) - v1.1
    CORREÇÕES:
      - Aimbot agora usa BindToRenderStep (prioridade correta)
      - FOV com círculo visual na tela
      - Suporte completo a mobile (centro da tela)
      - Suavidade corrigida
--]]

-- ============================================================
-- SERVIÇOS
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ============================================================
-- CONFIGURAÇÕES
-- ============================================================
local Settings = {
    -- Aimbot
    AimbotEnabled = false,
    AimbotKey = Enum.KeyCode.E,
    FOV = 120,
    Smoothness = 0.15,
    TargetPart = "Head",
    TeamCheck = true,
    MaxDistance = 500,
    ShowFovCircle = true,
    -- Hitbox
    HitboxEnabled = false,
    HitboxSize = 5,
    HitboxTransparency = 0.7,
    -- ESP
    ESPEnabled = false,
    ESPBox = true,
    ESPName = true,
    ESPHealth = true,
    ESPDistance = true,
    ESPHighlight = true,
    ESPTeamCheck = true,
    ESPEnemyColor = Color3.fromRGB(255, 50, 50),
    ESPTeamColor = Color3.fromRGB(50, 255, 50),
}

-- ============================================================
-- ESTADO GLOBAL
-- ============================================================
local CurrentTarget = nil
local AimbotBindName = "AimbotRenderStep"
local HitboxConnections = {}
local ESPObjects = {}
local FovCircle = nil
local ScreenGui = nil

-- ============================================================
-- FUNÇÕES UTILITÁRIAS
-- ============================================================
local function IsEnemy(player)
    if not Settings.TeamCheck then return true end
    if player.Team == LocalPlayer.Team then return false end
    return true
end

local function IsAlive(player)
    if not player or not player.Character then return false end
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health > 0
end

local function GetDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

local function GetTargetPart(character, partName)
    if not character then return nil end
    if partName == "Closest" then
        local closestPart, closestDist = nil, math.huge
        local center = Camera.ViewportSize / 2
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closestPart = part
                    end
                end
            end
        end
        return closestPart
    end
    return character:FindFirstChild(partName)
end

-- ============================================================
-- AIMBOT
-- ============================================================

-- Cria o círculo visual do FOV
local function CreateFovCircle()
    if FovCircle and FovCircle.Parent then FovCircle:Destroy() end

    local circle = Instance.new("Frame")
    circle.Name = "FovCircle"
    circle.AnchorPoint = Vector2.new(0.5, 0.5)
    circle.Position = UDim2.new(0.5, 0, 0.5, 0)
    circle.Size = UDim2.new(0, Settings.FOV * 2, 0, Settings.FOV * 2)
    circle.BackgroundTransparency = 1
    circle.BorderSizePixel = 0
    circle.ZIndex = 5
    circle.Visible = Settings.AimbotEnabled and Settings.ShowFovCircle
    circle.Parent = ScreenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = circle

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.5
    stroke.Color = Color3.fromRGB(80, 200, 255)
    stroke.Transparency = 0.3
    stroke.Parent = circle

    FovCircle = circle
    return circle
end

local function UpdateFovCircle()
    if not FovCircle then return end
    FovCircle.Size = UDim2.new(0, Settings.FOV * 2, 0, Settings.FOV * 2)
    FovCircle.Visible = Settings.AimbotEnabled and Settings.ShowFovCircle
end

-- Encontra o alvo mais próximo do centro da tela
local function GetClosestTarget()
    local closestTarget = nil
    local shortestDist = math.huge
    local center = Camera.ViewportSize / 2

    local myChar = LocalPlayer.Character
    if not myChar then return nil end
    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end
    local myPos = myRoot.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and IsAlive(player) and IsEnemy(player) then
            local char = player.Character
            local targetPart = GetTargetPart(char, Settings.TargetPart)
            if targetPart then
                local worldDist = (myPos - targetPart.Position).Magnitude
                if worldDist <= Settings.MaxDistance then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                    if onScreen then
                        local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                        if screenDist <= Settings.FOV and screenDist < shortestDist then
                            shortestDist = screenDist
                            closestTarget = player
                        end
                    end
                end
            end
        end
    end
    return closestTarget
end

-- Loop do aimbot (executado ANTES da câmera do Roblox)
local function UpdateAimbot()
    if not Settings.AimbotEnabled then return end

    local target = GetClosestTarget()
    CurrentTarget = target

    if target and target.Character then
        local targetPart = GetTargetPart(target.Character, Settings.TargetPart)
        if targetPart then
            local targetCFrame = CFrame.new(Camera.CFrame.Position, targetPart.Position)
            local alpha = 1 - math.clamp(Settings.Smoothness, 0, 0.99)
            Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, alpha)
        end
    end
end

local function ToggleAimbot(state)
    Settings.AimbotEnabled = state

    if state then
        RunService:UnbindFromRenderStep(AimbotBindName)
        RunService:BindToRenderStep(AimbotBindName, Enum.RenderPriority.Camera.Value - 1, UpdateAimbot)
    else
        RunService:UnbindFromRenderStep(AimbotBindName)
        CurrentTarget = nil
    end

    UpdateFovCircle()
end

-- ============================================================
-- HITBOX EXTENDER
-- ============================================================
local function ApplyHitbox(player)
    if player == LocalPlayer then return end
    if not IsAlive(player) or not IsEnemy(player) then return end

    local character = player.Character
    for _, part in ipairs(character:GetChildren()) do
        if part:IsA("BasePart") then
            if not part:GetAttribute("OriginalSize") then
                part:SetAttribute("OriginalSize", part.Size)
            end
            local originalSize = part:GetAttribute("OriginalSize")
            if originalSize then
                part.Size = originalSize + Vector3.new(Settings.HitboxSize, Settings.HitboxSize, Settings.HitboxSize)
            end
        end
    end
end

local function RestoreHitbox(player)
    if not player or not player.Character then return end
    for _, part in ipairs(player.Character:GetChildren()) do
        if part:IsA("BasePart") then
            local originalSize = part:GetAttribute("OriginalSize")
            if originalSize then
                part.Size = originalSize
                part:SetAttribute("OriginalSize", nil)
            end
        end
    end
end

local function UpdateAllHitboxes()
    if not Settings.HitboxEnabled then return end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and IsAlive(player) and IsEnemy(player) then
            ApplyHitbox(player)
        end
    end
end

local function ToggleHitbox(state)
    Settings.HitboxEnabled = state
    if state then
        UpdateAllHitboxes()
        if not HitboxConnections.loop then
            HitboxConnections.loop = RunService.Heartbeat:Connect(function()
                if Settings.HitboxEnabled then
                    UpdateAllHitboxes()
                end
            end)
        end
    else
        for _, player in ipairs(Players:GetPlayers()) do
            RestoreHitbox(player)
        end
        if HitboxConnections.loop then
            HitboxConnections.loop:Disconnect()
            HitboxConnections.loop = nil
        end
    end
end

-- ============================================================
-- ESP
-- ============================================================
local function DestroyESP(player)
    local esp = ESPObjects[player]
    if not esp then return end
    if esp.Highlight then esp.Highlight:Destroy() end
    if esp.Billboard then esp.Billboard:Destroy() end
    if esp.Box then esp.Box:Destroy() end
    ESPObjects[player] = nil
end

local function CreateESP(player)
    if player == LocalPlayer then return end
    if not IsAlive(player) then return end

    DestroyESP(player)

    local character = player.Character
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then return end

    local color = IsEnemy(player) and Settings.ESPEnemyColor or Settings.ESPTeamColor

    -- Highlight
    local highlight = nil
    if Settings.ESPHighlight then
        highlight = Instance.new("Highlight")
        highlight.Name = "ESP_Highlight"
        highlight.Adornee = character
        highlight.FillColor = color
        highlight.OutlineColor = Color3.new(1, 1, 1)
        highlight.FillTransparency = 0.5
        highlight.OutlineTransparency = 0
        highlight.Parent = character
    end

    -- Billboard (Nome, Distância, Vida)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_Billboard"
    billboard.Adornee = rootPart
    billboard.Size = UDim2.new(0, 200, 0, 100)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = character

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "ESP_Name"
    nameLabel.Size = UDim2.new(1, 0, 0.3, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = player.DisplayName or player.Name
    nameLabel.TextColor3 = color
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextSize = 14
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Visible = Settings.ESPName
    nameLabel.Parent = billboard

    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "ESP_Distance"
    distLabel.Size = UDim2.new(1, 0, 0.2, 0)
    distLabel.Position = UDim2.new(0, 0, 0.3, 0)
    distLabel.BackgroundTransparency = 1
    distLabel.Text = "0m"
    distLabel.TextColor3 = Color3.new(1, 1, 1)
    distLabel.TextStrokeTransparency = 0
    distLabel.TextSize = 12
    distLabel.Font = Enum.Font.Gotham
    distLabel.Visible = Settings.ESPDistance
    distLabel.Parent = billboard

    local healthBarBg = Instance.new("Frame")
    healthBarBg.Name = "ESP_HealthBg"
    healthBarBg.Size = UDim2.new(0.8, 0, 0.08, 0)
    healthBarBg.Position = UDim2.new(0.1, 0, 0.5, 0)
    healthBarBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    healthBarBg.BorderSizePixel = 0
    healthBarBg.Visible = Settings.ESPHealth
    healthBarBg.Parent = billboard

    local healthBar = Instance.new("Frame")
    healthBar.Name = "ESP_HealthFill"
    healthBar.Size = UDim2.new(1, 0, 1, 0)
    healthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    healthBar.BorderSizePixel = 0
    healthBar.Parent = healthBarBg

    ESPObjects[player] = {
        Highlight = highlight,
        Billboard = billboard,
        NameLabel = nameLabel,
        DistanceLabel = distLabel,
        HealthBar = healthBar,
        HealthBg = healthBarBg,
    }
end

local function UpdateESP()
    for player, esp in pairs(ESPObjects) do
        if not player or not player.Parent or not player.Character then
            DestroyESP(player)
            continue
        end

        local character = player.Character
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not rootPart or humanoid.Health <= 0 then
            DestroyESP(player)
            continue
        end

        local color = IsEnemy(player) and Settings.ESPEnemyColor or Settings.ESPTeamColor
        if esp.Highlight then esp.Highlight.FillColor = color end
        if esp.NameLabel then
            esp.NameLabel.TextColor3 = color
            esp.NameLabel.Visible = Settings.ESPName
        end

        if esp.DistanceLabel then
            local myChar = LocalPlayer.Character
            if myChar and myChar:FindFirstChild("HumanoidRootPart") then
                local d = GetDistance(myChar.HumanoidRootPart.Position, rootPart.Position)
                esp.DistanceLabel.Text = string.format("%.0fm", d)
            end
            esp.DistanceLabel.Visible = Settings.ESPDistance
        end

        if esp.HealthBg then
            esp.HealthBg.Visible = Settings.ESPHealth
        end

        if esp.HealthBar then
            local hp = humanoid.Health / math.max(humanoid.MaxHealth, 1)
            esp.HealthBar.Size = UDim2.new(hp, 0, 1, 0)
            if hp > 0.5 then
                esp.HealthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
            elseif hp > 0.25 then
                esp.HealthBar.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
            else
                esp.HealthBar.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
            end
        end
    end
end

local function ToggleESP(state)
    Settings.ESPEnabled = state
    if state then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                CreateESP(player)
            end
        end
        if not ESPObjects.loop then
            local lastUpdate = 0
            ESPObjects.loop = RunService.Heartbeat:Connect(function(dt)
                if not Settings.ESPEnabled then return end
                lastUpdate = lastUpdate + dt
                if lastUpdate >= 0.1 then
                    lastUpdate = 0
                    UpdateESP()
                end
            end)
        end
    else
        for player, _ in pairs(ESPObjects) do
            DestroyESP(player)
        end
        if ESPObjects.loop then
            ESPObjects.loop:Disconnect()
            ESPObjects.loop = nil
        end
    end
end

-- ============================================================
-- CICLO DE VIDA DOS JOGADORES
-- ============================================================
local function OnCharacterAdded(player, character)
    task.wait(0.5)
    if Settings.HitboxEnabled and IsEnemy(player) then
        ApplyHitbox(player)
    end
    if Settings.ESPEnabled then
        CreateESP(player)
    end
end

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function(c) OnCharacterAdded(player, c) end)
        player.CharacterRemoving:Connect(function()
            DestroyESP(player)
            RestoreHitbox(player)
        end)
    end
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(c) OnCharacterAdded(player, c) end)
    player.CharacterRemoving:Connect(function()
        DestroyESP(player)
        RestoreHitbox(player)
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    DestroyESP(player)
    RestoreHitbox(player)
end)

-- ============================================================
-- INTERFACE
-- ============================================================
local function CreateUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MobileCombatUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = CoreGui
    ScreenGui = screenGui

    -- Botão flutuante de abrir
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "ToggleBtn"
    toggleBtn.Size = UDim2.new(0, 55, 0, 55)
    toggleBtn.Position = UDim2.new(0, 20, 0.5, -27)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Text = "⚙"
    toggleBtn.TextColor3 = Color3.new(1, 1, 1)
    toggleBtn.TextSize = 26
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.Active = true
    toggleBtn.Draggable = true
    toggleBtn.Parent = screenGui

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(1, 0)
    btnCorner.Parent = toggleBtn

    -- Janela principal
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 320, 0, 420)
    mainFrame.Position = UDim2.new(0.5, -160, 0.5, -210)
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.Visible = false
    mainFrame.Parent = screenGui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 12)
    mainCorner.Parent = mainFrame

    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 40)
    titleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame

    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 12)
    titleCorner.Parent = titleBar

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -40, 1, 0)
    titleLabel.Position = UDim2.new(0, 10, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "⚔️ Combat Suite v1.1"
    titleLabel.TextColor3 = Color3.new(1, 1, 1)
    titleLabel.TextSize = 15
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = titleBar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -35, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.TextSize = 14
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = titleBar

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(1, 0)
    closeCorner.Parent = closeBtn

    closeBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = false
    end)

    toggleBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = not mainFrame.Visible
    end)

    -- Abas
    local tabContainer = Instance.new("Frame")
    tabContainer.Size = UDim2.new(1, -20, 0, 35)
    tabContainer.Position = UDim2.new(0, 10, 0, 45)
    tabContainer.BackgroundTransparency = 1
    tabContainer.Parent = mainFrame

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 5)
    tabLayout.Parent = tabContainer

    local contentFrame = Instance.new("Frame")
    contentFrame.Size = UDim2.new(1, -20, 1, -90)
    contentFrame.Position = UDim2.new(0, 10, 0, 85)
    contentFrame.BackgroundTransparency = 1
    contentFrame.ClipsDescendants = true
    contentFrame.Parent = mainFrame

    local tabs = {}

    local function CreateTab(name)
        local tabBtn = Instance.new("TextButton")
        tabBtn.Size = UDim2.new(0, 72, 1, 0)
        tabBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
        tabBtn.Text = name
        tabBtn.TextColor3 = Color3.fromRGB(180, 180, 180)
        tabBtn.TextSize = 12
        tabBtn.Font = Enum.Font.Gotham
        tabBtn.BorderSizePixel = 0
        tabBtn.Parent = tabContainer

        local tabCorner = Instance.new("UICorner")
        tabCorner.CornerRadius = UDim.new(0, 6)
        tabCorner.Parent = tabBtn

        local content = Instance.new("ScrollingFrame")
        content.Name = name .. "Content"
        content.Size = UDim2.new(1, 0, 1, 0)
        content.BackgroundTransparency = 1
        content.BorderSizePixel = 0
        content.ScrollBarThickness = 4
        content.CanvasSize = UDim2.new(0, 0, 0, 0)
        content.AutomaticCanvasSize = Enum.AutomaticSize.Y
        content.Visible = false
        content.Parent = contentFrame

        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 8)
        layout.Parent = content

        tabs[name] = { button = tabBtn, content = content }

        tabBtn.MouseButton1Click:Connect(function()
            for _, tab in pairs(tabs) do
                tab.content.Visible = false
                tab.button.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
                tab.button.TextColor3 = Color3.fromRGB(180, 180, 180)
            end
            content.Visible = true
            tabBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 100)
            tabBtn.TextColor3 = Color3.new(1, 1, 1)
        end)

        return content
    end

    -- Toggle
    local function CreateToggle(parent, text, default, callback)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 30)
        frame.BackgroundTransparency = 1
        frame.Parent = parent

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0.7, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = Color3.fromRGB(200, 200, 200)
        label.TextSize = 13
        label.Font = Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = frame

        local toggleBg = Instance.new("Frame")
        toggleBg.Size = UDim2.new(0, 42, 0, 22)
        toggleBg.Position = UDim2.new(1, -42, 0.5, -11)
        toggleBg.BackgroundColor3 = default and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(60, 60, 70)
        toggleBg.BorderSizePixel = 0
        toggleBg.Parent = frame

        local bgCorner = Instance.new("UICorner")
        bgCorner.CornerRadius = UDim.new(1, 0)
        bgCorner.Parent = toggleBg

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 18, 0, 18)
        knob.Position = default and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
        knob.BackgroundColor3 = Color3.new(1, 1, 1)
        knob.BorderSizePixel = 0
        knob.Parent = toggleBg

        local knobCorner = Instance.new("UICorner")
        knobCorner.CornerRadius = UDim.new(1, 0)
        knobCorner.Parent = knob

        local isOn = default
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.Parent = toggleBg

        btn.MouseButton1Click:Connect(function()
            isOn = not isOn
            toggleBg.BackgroundColor3 = isOn and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(60, 60, 70)
            TweenService:Create(knob, TweenInfo.new(0.2), {
                Position = isOn and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
            }):Play()
            if callback then callback(isOn) end
        end)

        return frame
    end

    -- Slider
    local function CreateSlider(parent, text, min, max, default, callback)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 45)
        frame.BackgroundTransparency = 1
        frame.Parent = parent

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, 18)
        label.BackgroundTransparency = 1
        label.Text = text .. ": " .. default
        label.TextColor3 = Color3.fromRGB(200, 200, 200)
        label.TextSize = 12
        label.Font = Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = frame

        local sliderBg = Instance.new("Frame")
        sliderBg.Size = UDim2.new(1, -10, 0, 10)
        sliderBg.Position = UDim2.new(0, 5, 0, 28)
        sliderBg.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
        sliderBg.BorderSizePixel = 0
        sliderBg.Parent = frame

        local sliderCorner = Instance.new("UICorner")
        sliderCorner.CornerRadius = UDim.new(1, 0)
        sliderCorner.Parent = sliderBg

        local initPct = math.clamp((default - min) / (max - min), 0, 1)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(initPct, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
        fill.BorderSizePixel = 0
        fill.Parent = sliderBg

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(1, 0)
        fillCorner.Parent = fill

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 16, 0, 16)
        knob.Position = UDim2.new(initPct, -8, 0.5, -8)
        knob.BackgroundColor3 = Color3.new(1, 1, 1)
        knob.BorderSizePixel = 0
        knob.ZIndex = 2
        knob.Parent = sliderBg

        local knobCorner = Instance.new("UICorner")
        knobCorner.CornerRadius = UDim.new(1, 0)
        knobCorner.Parent = knob

        local dragging = false

        local function update(input)
            local pos = math.clamp((input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
            local value = math.floor(min + (max - min) * pos + 0.5)
            fill.Size = UDim2.new(pos, 0, 1, 0)
            knob.Position = UDim2.new(pos, -8, 0.5, -8)
            label.Text = text .. ": " .. value
            if callback then callback(value) end
        end

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.Parent = sliderBg

        btn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                update(input)
            end
        end)

        btn.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                update(input)
            end
        end)

        btn.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)

        return frame
    end

    -- ============================================================
    -- ABA AIMBOT
    -- ============================================================
    local aimbotTab = CreateTab("Aimbot")

    CreateToggle(aimbotTab, "Ativar Aimbot", Settings.AimbotEnabled, function(v)
        ToggleAimbot(v)
    end)

    CreateToggle(aimbotTab, "Mostrar FOV", Settings.ShowFovCircle, function(v)
        Settings.ShowFovCircle = v
        UpdateFovCircle()
    end)

    CreateSlider(aimbotTab, "FOV", 10, 500, Settings.FOV, function(v)
        Settings.FOV = v
        UpdateFovCircle() -- 🔥 atualiza em tempo real
    end)

    CreateSlider(aimbotTab, "Suavidade", 1, 99, math.floor(Settings.Smoothness * 100), function(v)
        Settings.Smoothness = v / 100
    end)

    CreateSlider(aimbotTab, "Distância Máx.", 50, 2000, Settings.MaxDistance, function(v)
        Settings.MaxDistance = v
    end)

    CreateToggle(aimbotTab, "Team Check", Settings.TeamCheck, function(v)
        Settings.TeamCheck = v
    end)

    -- Seleção de parte do corpo
    local partFrame = Instance.new("Frame")
    partFrame.Size = UDim2.new(1, 0, 0, 60)
    partFrame.BackgroundTransparency = 1
    partFrame.Parent = aimbotTab

    local partLabel = Instance.new("TextLabel")
    partLabel.Size = UDim2.new(1, 0, 0, 18)
    partLabel.BackgroundTransparency = 1
    partLabel.Text = "Parte Alvo"
    partLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    partLabel.TextSize = 12
    partLabel.Font = Enum.Font.Gotham
    partLabel.TextXAlignment = Enum.TextXAlignment.Left
    partLabel.Parent = partFrame

    local btnRow = Instance.new("Frame")
    btnRow.Size = UDim2.new(1, 0, 0, 30)
    btnRow.Position = UDim2.new(0, 0, 0, 22)
    btnRow.BackgroundTransparency = 1
    btnRow.Parent = partFrame

    local rowLayout = Instance.new("UIListLayout")
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.Padding = UDim.new(0, 5)
    rowLayout.Parent = btnRow

    local partOptions = { "Head", "Torso", "Closest" }
    local partButtons = {}

    for _, option in ipairs(partOptions) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 90, 1, 0)
        btn.BackgroundColor3 = Settings.TargetPart == option and Color3.fromRGB(80, 140, 255) or Color3.fromRGB(45, 45, 60)
        btn.Text = option
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.TextSize = 11
        btn.Font = Enum.Font.Gotham
        btn.BorderSizePixel = 0
        btn.Parent = btnRow

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = btn

        partButtons[option] = btn

        btn.MouseButton1Click:Connect(function()
            Settings.TargetPart = option
            for k, b in pairs(partButtons) do
                b.BackgroundColor3 = (k == option) and Color3.fromRGB(80, 140, 255) or Color3.fromRGB(45, 45, 60)
            end
        end)
    end

    -- ============================================================
    -- ABA HITBOX
    -- ============================================================
    local hitboxTab = CreateTab("Hitbox")

    CreateToggle(hitboxTab, "Ativar Hitbox", Settings.HitboxEnabled, function(v)
        ToggleHitbox(v)
    end)

    CreateSlider(hitboxTab, "Tamanho", 1, 20, Settings.HitboxSize, function(v)
        Settings.HitboxSize = v
    end)

    -- ============================================================
    -- ABA ESP
    -- ============================================================
    local espTab = CreateTab("ESP")

    CreateToggle(espTab, "Ativar ESP", Settings.ESPEnabled, function(v)
        ToggleESP(v)
    end)

    CreateToggle(espTab, "Nome", Settings.ESPName, function(v) Settings.ESPName = v end)
    CreateToggle(espTab, "Distância", Settings.ESPDistance, function(v) Settings.ESPDistance = v end)
    CreateToggle(espTab, "Barra de Vida", Settings.ESPHealth, function(v) Settings.ESPHealth = v end)
    CreateToggle(espTab, "Highlight", Settings.ESPHighlight, function(v)
        Settings.ESPHighlight = v
        if Settings.ESPEnabled then
            ToggleESP(false)
            ToggleESP(true)
        end
    end)
    CreateToggle(espTab, "Team Check ESP", Settings.ESPTeamCheck, function(v)
        Settings.ESPTeamCheck = v
    end)

    -- ============================================================
    -- ABA CONFIG
    -- ============================================================
    local configTab = CreateTab("Config")

    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(1, 0, 0, 80)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Text = "Script Modular v1.1\nAimbot com FOV visual\nMobile-friendly\n\nAtalho (PC): E = toggle Aimbot"
    infoLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    infoLabel.TextSize = 11
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextWrapped = true
    infoLabel.Parent = configTab

    -- Seleciona aba Aimbot
    if tabs["Aimbot"] then
        tabs["Aimbot"].button:Fire()
    end

    return mainFrame, toggleBtn
end

-- ============================================================
-- INICIALIZAÇÃO
-- ============================================================
local mainFrame, toggleBtn = CreateUI()
CreateFovCircle()

-- Atalho PC
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Settings.AimbotKey then
        ToggleAimbot(not Settings.AimbotEnabled)
    end
end)

StarterGui:SetCore("SendNotification", {
    Title = "Combat Suite v1.1",
    Text = "Aimbot e FOV corrigidos!",
    Duration = 3,
})

print("✅ Combat Suite v1.1 carregado!")
