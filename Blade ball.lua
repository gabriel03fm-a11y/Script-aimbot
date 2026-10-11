-- ============================================================
-- AIM TRAINER - SISTEMA COMPLETO EM 1 SCRIPT
-- Local: StarterPlayer/StarterPlayerScripts (LocalScript)
-- Nome sugerido: AimTrainer
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- CONFIGURAÇÕES
-- ============================================================
local Config = {
    Aimbot = {
        Enabled = false,
        Smoothness = 0.15,      -- 0 = instantâneo, 1 = muito suave
        FOVRadius = 150,        -- raio em pixels
        MaxDistance = 500,      -- studs
        TargetPart = "Head",    -- Head / UpperTorso / HumanoidRootPart
    },
    ESP = {
        Enabled = false,
    },
    TeamCheck = {
        Enabled = true,
    },
    UI = {
        ToggleKey = Enum.KeyCode.RightShift,
        FOVColor = Color3.fromRGB(0, 255, 150),
        FOVThickness = 1.5,
    },
}

-- ============================================================
-- ESTADO INTERNO
-- ============================================================
local currentTarget = nil
local fovCircle = nil
local espObjects = {}      -- [player] = {highlight, billboard, nameLabel, distLabel}
local isMenuOpen = false

-- ============================================================
-- FUNÇÕES AUXILIARES
-- ============================================================
local function getScreenCenter()
    local v = Camera.ViewportSize
    return Vector2.new(v.X / 2, v.Y / 2)
end

local function isValidTarget(player)
    if player == LocalPlayer then return false end
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    if not char:FindFirstChild(Config.Aimbot.TargetPart) then return false end
    return true
end

local function passesTeamCheck(player)
    if not Config.TeamCheck.Enabled then return true end
    if LocalPlayer.Team == nil or player.Team == nil then return true end
    return LocalPlayer.Team ~= player.Team
end

local function findClosestTarget()
    local center = getScreenCenter()
    local closestDist = Config.Aimbot.FOVRadius
    local closestPlayer, closestPart = nil, nil

    for _, player in ipairs(Players:GetPlayers()) do
        if isValidTarget(player) and passesTeamCheck(player) then
            local char = player.Character
            local part = char:FindFirstChild(Config.Aimbot.TargetPart)
            if part then
                -- Verifica distância máxima
                local myChar = LocalPlayer.Character
                if myChar and myChar:FindFirstChild("HumanoidRootPart") then
                    local dist = (myChar.HumanoidRootPart.Position - part.Position).Magnitude
                    if dist <= Config.Aimbot.MaxDistance then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                        if onScreen then
                            local pixelDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                            if pixelDist < closestDist then
                                closestDist = pixelDist
                                closestPlayer = player
                                closestPart = part
                            end
                        end
                    end
                end
            end
        end
    end
    return closestPlayer, closestPart
end

-- ============================================================
-- FOV CIRCLE
-- ============================================================
local function createFOVCircle()
    local circle = Drawing.new("Circle")
    circle.Visible = false
    circle.Thickness = Config.UI.FOVThickness
    circle.Color = Config.UI.FOVColor
    circle.Filled = false
    circle.Transparency = 1
    return circle
end

local function updateFOVCircle()
    if not fovCircle then return end
    fovCircle.Visible = Config.Aimbot.Enabled
    if Config.Aimbot.Enabled then
        fovCircle.Position = getScreenCenter()
        fovCircle.Radius = Config.Aimbot.FOVRadius
        fovCircle.Color = Config.UI.FOVColor
        fovCircle.Thickness = Config.UI.FOVThickness
    end
end

-- ============================================================
-- ESP
-- ============================================================
local function createESP(player)
    if espObjects[player] then return end
    local char = player.Character
    if not char then return end

    -- Highlight (contorno oficial)
    local highlight = Instance.new("Highlight")
    highlight.Name = "AimTrainerESP"
    highlight.FillColor = Color3.fromRGB(255, 80, 80)
    highlight.FillTransparency = 0.65
    highlight.OutlineColor = Color3.fromRGB(255, 50, 50)
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Adornee = char
    highlight.Parent = char

    -- BillboardGui (nome + distância)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "AimTrainerTag"
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = Config.Aimbot.MaxDistance

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = player.Name
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextStrokeTransparency = 0.3
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = billboard

    local distLabel = Instance.new("TextLabel")
    distLabel.Size = UDim2.new(1, 0, 0.5, 0)
    distLabel.Position = UDim2.new(0, 0, 0.5, 0)
    distLabel.BackgroundTransparency = 1
    distLabel.Text = ""
    distLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
    distLabel.TextStrokeTransparency = 0.3
    distLabel.TextScaled = true
    distLabel.Font = Enum.Font.Gotham
    distLabel.Parent = billboard

    local adornPart = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    if adornPart then
        billboard.Adornee = adornPart
        billboard.Parent = adornPart
    end

    espObjects[player] = {
        highlight = highlight,
        billboard = billboard,
        distLabel = distLabel,
    }
end

local function removeESP(player)
    local data = espObjects[player]
    if not data then return end
    if data.highlight then data.highlight:Destroy() end
    if data.billboard then data.billboard:Destroy() end
    espObjects[player] = nil
end

local function updateESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end

        local char = player.Character
        local hasData = espObjects[player] ~= nil

        if Config.ESP.Enabled and char and not hasData then
            createESP(player)
        elseif (not Config.ESP.Enabled or not char) and hasData then
            removeESP(player)
        end

        local data = espObjects[player]
        if data and data.distLabel and char then
            local myChar = LocalPlayer.Character
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local root = char:FindFirstChild("HumanoidRootPart")
            if myRoot and root then
                local d = (myRoot.Position - root.Position).Magnitude
                data.distLabel.Text = string.format("%d studs", math.floor(d))
            end
        end
    end
end

-- ============================================================
-- AIMBOT
-- ============================================================
local function runAimbot()
    if not Config.Aimbot.Enabled then
        currentTarget = nil
        return
    end

    local targetPlayer, targetPart = findClosestTarget()

    if targetPlayer and targetPart then
        currentTarget = targetPlayer
        local currentCFrame = Camera.CFrame
        local desiredCFrame = CFrame.new(currentCFrame.Position, targetPart.Position)

        if Config.Aimbot.Smoothness <= 0.01 then
            Camera.CFrame = desiredCFrame
        else
            local alpha = 1 - Config.Aimbot.Smoothness
            Camera.CFrame = currentCFrame:Lerp(desiredCFrame, alpha)
        end
    else
        currentTarget = nil
    end
end

-- ============================================================
-- UI - CRIAÇÃO DO MENU
-- ============================================================
local function buildUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AimTrainerMenu"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = PlayerGui

    -- Painel principal
    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, 300, 0, 440)
    main.Position = UDim2.new(0.5, -150, 0.5, -220)
    main.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    main.BorderSizePixel = 0
    main.Visible = false
    main.Parent = screenGui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 12)
    mainCorner.Parent = main

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 255, 150)
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    stroke.Parent = main

    -- Título
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 45)
    title.BackgroundTransparency = 1
    title.Text = "🎯  AIM TRAINER"
    title.TextColor3 = Color3.fromRGB(0, 255, 150)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = main

    -- Função: criar toggle
    local function makeToggle(parent, labelText, getter, setter, y)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, -30, 0, 36)
        frame.Position = UDim2.new(0, 15, 0, y)
        frame.BackgroundTransparency = 1
        frame.Parent = parent

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0.6, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        lbl.TextScaled = true
        lbl.Font = Enum.Font.Gotham
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = frame

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 80, 0, 28)
        btn.Position = UDim2.new(1, -80, 0.5, -14)
        btn.BackgroundColor3 = getter() and Color3.fromRGB(0, 180, 80) or Color3.fromRGB(70, 70, 75)
        btn.Text = getter() and "ON" or "OFF"
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextScaled = true
        btn.Font = Enum.Font.GothamBold
        btn.BorderSizePixel = 0
        btn.AutoButtonColor = false
        btn.Parent = frame

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = btn

        btn.MouseButton1Click:Connect(function()
            local v = not getter()
            setter(v)
            btn.BackgroundColor3 = v and Color3.fromRGB(0, 180, 80) or Color3.fromRGB(70, 70, 75)
            btn.Text = v and "ON" or "OFF"
        end)
    end

    -- Função: criar slider
    local function makeSlider(parent, labelText, minV, maxV, getter, setter, y, decimals)
        decimals = decimals or 2

        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, -30, 0, 55)
        frame.Position = UDim2.new(0, 15, 0, y)
        frame.BackgroundTransparency = 1
        frame.Parent = parent

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 20)
        lbl.BackgroundTransparency = 1
        lbl.Text = string.format("%s: %." .. decimals .. "f", labelText, getter())
        lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
        lbl.TextScaled = true
        lbl.Font = Enum.Font.Gotham
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = frame

        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(1, 0, 0, 8)
        bar.Position = UDim2.new(0, 0, 0, 32)
        bar.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
        bar.BorderSizePixel = 0
        bar.Parent = frame

        local barC = Instance.new("UICorner")
        barC.CornerRadius = UDim.new(0, 4)
        barC.Parent = bar

        local fillRatio = (getter() - minV) / (maxV - minV)
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(fillRatio, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(0, 200, 120)
        fill.BorderSizePixel = 0
        fill.Parent = bar

        local fillC = Instance.new("UICorner")
        fillC.CornerRadius = UDim.new(0, 4)
        fillC.Parent = fill

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 16, 0, 16)
        knob.Position = UDim2.new(fillRatio, -8, 0.5, -8)
        knob.BackgroundColor3 = Color3.fromRGB(0, 255, 150)
        knob.BorderSizePixel = 0
        knob.Parent = bar

        local knobC = Instance.new("UICorner")
        knobC.CornerRadius = UDim.new(1, 0)
        knobC.Parent = knob

        local dragging = false

        local function update(x)
            local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            local val = minV + rel * (maxV - minV)
            setter(val)
            lbl.Text = string.format("%s: %." .. decimals .. "f", labelText, val)
            fill.Size = UDim2.new(rel, 0, 1, 0)
            knob.Position = UDim2.new(rel, -8, 0.5, -8)
        end

        bar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                update(input.Position.X)
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                update(input.Position.X)
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
    end

    -- Preenche UI
    local y = 55
    makeToggle(main, "Aimbot",
        function() return Config.Aimbot.Enabled end,
        function(v) Config.Aimbot.Enabled = v end, y)
    y = y + 42

    makeToggle(main, "ESP",
        function() return Config.ESP.Enabled end,
        function(v) Config.ESP.Enabled = v end, y)
    y = y + 42

    makeToggle(main, "Team Check",
        function() return Config.TeamCheck.Enabled end,
        function(v) Config.TeamCheck.Enabled = v end, y)
    y = y + 48

    makeSlider(main, "Suavidade", 0, 0.95,
        function() return Config.Aimbot.Smoothness end,
        function(v) Config.Aimbot.Smoothness = v end, y, 2)
    y = y + 60

    makeSlider(main, "FOV", 50, 500,
        function() return Config.Aimbot.FOVRadius end,
        function(v) Config.Aimbot.FOVRadius = v end, y, 0)
    y = y + 60

    makeSlider(main, "Dist. Máx.", 50, 2000,
        function() return Config.Aimbot.MaxDistance end,
        function(v) Config.Aimbot.MaxDistance = v end, y, 0)

    -- Botão flutuante mobile
    local mobileBtn = Instance.new("TextButton")
    mobileBtn.Size = UDim2.new(0, 55, 0, 55)
    mobileBtn.Position = UDim2.new(1, -75, 1, -75)
    mobileBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
    mobileBtn.Text = "🎯"
    mobileBtn.TextScaled = true
    mobileBtn.BorderSizePixel = 0
    mobileBtn.AutoButtonColor = false
    mobileBtn.Parent = screenGui

    local mbC = Instance.new("UICorner")
    mbC.CornerRadius = UDim.new(1, 0)
    mbC.Parent = mobileBtn

    mobileBtn.MouseButton1Click:Connect(function()
        main.Visible = not main.Visible
        isMenuOpen = main.Visible
    end)

    return main
end

local mainFrame = buildUI()

-- ============================================================
-- ATALHO DE TECLADO
-- ============================================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Config.UI.ToggleKey then
        isMenuOpen = not isMenuOpen
        mainFrame.Visible = isMenuOpen
    end
end)

-- ============================================================
-- EVENTOS DE JOGADORES
-- ============================================================
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.4)
        if Config.ESP.Enabled then
            createESP(player)
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    removeESP(player)
end)

-- Registra jogadores já presentes
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        if player.Character then
            player.CharacterAdded:Connect(function()
                task.wait(0.4)
                if Config.ESP.Enabled then
                    createESP(player)
                end
            end)
        else
            player.CharacterAdded:Connect(function()
                task.wait(0.4)
                if Config.ESP.Enabled then
                    createESP(player)
                end
            end)
        end
    end
end

-- ============================================================
-- LOOP PRINCIPAL
-- ============================================================
fovCircle = createFOVCircle()

RunService.RenderStepped:Connect(function()
    updateFOVCircle()
    updateESP()
    runAimbot()
end)

print("[AimTrainer] Sistema carregado. Pressione " .. Config.UI.ToggleKey.Name .. " para abrir o menu.")
