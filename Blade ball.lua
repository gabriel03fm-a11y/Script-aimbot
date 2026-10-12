--[[
    SCRIPT: Aimbot + Hitbox Extender + ESP (Mobile UI)
    DESCRIÇÃO: Script modular com interface moderna para Roblox.
    FUNÇÕES: Aimbot suave, Hitbox Extender, ESP completo.
    COMPATIBILIDADE: PC e Mobile (UI responsiva e arrastável).
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

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- ============================================================
-- CONFIGURAÇÕES (Todas as variáveis em um único lugar)
-- ============================================================
local Settings = {
    -- Aimbot
    AimbotEnabled = false,
    AimbotKey = Enum.KeyCode.E, -- Tecla para ativar/desativar (PC)
    FOV = 120,
    Smoothness = 0.15,
    TargetPart = "Head", -- "Head", "Torso", "Closest"
    TeamCheck = true,
    MaxDistance = 500,
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
local AimbotConnection = nil
local HitboxConnections = {}
local ESPObjects = {} -- [Player] = {Highlight=..., BillboardGui=..., Box=..., HealthBar=...}

-- ============================================================
-- FUNÇÕES UTILITÁRIAS
-- ============================================================

-- Verifica se o jogador é inimigo (Team Check)
local function IsEnemy(player)
    if not Settings.TeamCheck then return true end
    if player.Team == LocalPlayer.Team then return false end
    return true
end

-- Obtém a parte do corpo alvo
local function GetTargetPart(character, partName)
    if not character then return nil end
    if partName == "Closest" then
        -- Retorna a parte mais próxima do centro da mira
        local closestPart, closestDist = nil, math.huge
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - Camera.ViewportSize / 2).Magnitude
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

-- Calcula a distância entre dois pontos
local function GetDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

-- Verifica se o jogador está vivo
local function IsAlive(player)
    if not player or not player.Character then return false end
    local humanoid = player.Character:FindFirstChild("Humanoid")
    return humanoid and humanoid.Health > 0
end

-- ============================================================
-- AIMBOT
-- ============================================================

-- Encontra o jogador inimigo mais próximo do centro da tela
local function GetClosestTarget()
    local closestTarget = nil
    local shortestDistance = math.huge
    local center = Camera.ViewportSize / 2

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and IsAlive(player) and IsEnemy(player) then
            local character = player.Character
            local targetPart = GetTargetPart(character, Settings.TargetPart)
            if targetPart then
                local distance = GetDistance(LocalPlayer.Character.HumanoidRootPart.Position, targetPart.Position)
                if distance <= Settings.MaxDistance then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                    if onScreen then
                        local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                        if screenDist <= Settings.FOV and screenDist < shortestDistance then
                            shortestDistance = screenDist
                            closestTarget = player
                        end
                    end
                end
            end
        end
    end
    return closestTarget
end

-- Atualiza a mira do aimbot suavemente
local function UpdateAimbot()
    if not Settings.AimbotEnabled then return end

    local target = GetClosestTarget()
    CurrentTarget = target

    if target and target.Character then
        local targetPart = GetTargetPart(target.Character, Settings.TargetPart)
        if targetPart then
            local targetPos = targetPart.Position
            local currentCFrame = Camera.CFrame
            local goalCFrame = CFrame.new(currentCFrame.Position, targetPos)

            -- Suavização usando Lerp
            Camera.CFrame = currentCFrame:Lerp(goalCFrame, Settings.Smoothness)
        end
    end
end

-- Ativa/desativa o aimbot
local function ToggleAimbot(state)
    Settings.AimbotEnabled = state
    if state then
        if not AimbotConnection then
            AimbotConnection = RunService.RenderStepped:Connect(UpdateAimbot)
        end
    else
        if AimbotConnection then
            AimbotConnection:Disconnect()
            AimbotConnection = nil
        end
        CurrentTarget = nil
    end
end

-- ============================================================
-- HITBOX EXTENDER
-- ============================================================

-- Aplica a hitbox estendida em um jogador
local function ApplyHitbox(player)
    if player == LocalPlayer then return end
    if not IsAlive(player) or not IsEnemy(player) then return end

    local character = player.Character
    for _, part in ipairs(character:GetChildren()) do
        if part:IsA("BasePart") then
            -- Salva o tamanho original
            if not part:GetAttribute("OriginalSize") then
                part:SetAttribute("OriginalSize", part.Size)
            end
            -- Aplica o novo tamanho
            local originalSize = part:GetAttribute("OriginalSize")
            if originalSize then
                part.Size = originalSize + Vector3.new(Settings.HitboxSize, Settings.HitboxSize, Settings.HitboxSize)
            end
        end
    end
end

-- Restaura a hitbox original de um jogador
local function RestoreHitbox(player)
    if not player or not player.Character then return end
    local character = player.Character
    for _, part in ipairs(character:GetChildren()) do
        if part:IsA("BasePart") then
            local originalSize = part:GetAttribute("OriginalSize")
            if originalSize then
                part.Size = originalSize
                part:SetAttribute("OriginalSize", nil)
            end
        end
    end
end

-- Atualiza as hitboxes de todos os jogadores válidos
local function UpdateAllHitboxes()
    if not Settings.HitboxEnabled then return end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and IsAlive(player) and IsEnemy(player) then
            ApplyHitbox(player)
        end
    end
end

-- Ativa/desativa o hitbox extender
local function ToggleHitbox(state)
    Settings.HitboxEnabled = state
    if state then
        -- Aplica em todos os jogadores existentes
        UpdateAllHitboxes()
        -- Atualiza continuamente para novos jogadores ou respawn
        if not HitboxConnections.loop then
            HitboxConnections.loop = RunService.Heartbeat:Connect(function()
                if Settings.HitboxEnabled then
                    UpdateAllHitboxes()
                end
            end)
        end
    else
        -- Restaura todas as hitboxes
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
-- ESP (Extra Sensory Perception)
-- ============================================================

-- Cria os elementos de ESP para um jogador
local function CreateESP(player)
    if player == LocalPlayer then return end
    if not IsAlive(player) then return end

    -- Remove ESP antigo se existir
    if ESPObjects[player] then
        DestroyESP(player)
    end

    local character = player.Character
    local humanoid = character:FindFirstChild("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then return end

    -- Highlight
    local highlight = nil
    if Settings.ESPHighlight then
        highlight = Instance.new("Highlight")
        highlight.Name = "ESP_Highlight"
        highlight.Adornee = character
        highlight.FillColor = IsEnemy(player) and Settings.ESPEnemyColor or Settings.ESPTeamColor
        highlight.OutlineColor = Color3.new(1, 1, 1)
        highlight.FillTransparency = 0.5
        highlight.OutlineTransparency = 0
        highlight.Parent = character
    end

    -- BillboardGui para Nome, Distância e Vida
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_Billboard"
    billboard.Adornee = rootPart
    billboard.Size = UDim2.new(0, 200, 0, 100)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = character

    -- Nome
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "ESP_Name"
    nameLabel.Size = UDim2.new(1, 0, 0.3, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = player.DisplayName or player.Name
    nameLabel.TextColor3 = IsEnemy(player) and Settings.ESPEnemyColor or Settings.ESPTeamColor
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextSize = 14
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = billboard

    -- Distância
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
    distLabel.Parent = billboard

    -- Barra de Vida
    local healthBarBg = Instance.new("Frame")
    healthBarBg.Name = "ESP_HealthBg"
    healthBarBg.Size = UDim2.new(0.8, 0, 0.1, 0)
    healthBarBg.Position = UDim2.new(0.1, 0, 0.5, 0)
    healthBarBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    healthBarBg.BorderSizePixel = 0
    healthBarBg.Parent = billboard

    local healthBar = Instance.new("Frame")
    healthBar.Name = "ESP_HealthFill"
    healthBar.Size = UDim2.new(1, 0, 1, 0)
    healthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    healthBar.BorderSizePixel = 0
    healthBar.Parent = healthBarBg

    -- Armazena referências
    ESPObjects[player] = {
        Highlight = highlight,
        Billboard = billboard,
        NameLabel = nameLabel,
        DistanceLabel = distLabel,
        HealthBar = healthBar,
        HealthBg = healthBarBg,
    }
end

-- Atualiza os dados do ESP em tempo real
local function UpdateESP()
    for player, esp in pairs(ESPObjects) do
        if not player or not player.Parent or not player.Character then
            DestroyESP(player)
            continue
        end

        local character = player.Character
        local humanoid = character:FindFirstChild("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not rootPart or humanoid.Health <= 0 then
            DestroyESP(player)
            continue
        end

        -- Atualiza cor (inimigo/aliado)
        local color = IsEnemy(player) and Settings.ESPEnemyColor or Settings.ESPTeamColor
        if esp.Highlight then
            esp.Highlight.FillColor = color
        end
        if esp.NameLabel then
            esp.NameLabel.TextColor3 = color
        end

        -- Atualiza distância
        if esp.DistanceLabel then
            local distance = GetDistance(LocalPlayer.Character.HumanoidRootPart.Position, rootPart.Position)
            esp.DistanceLabel.Text = string.format("%.0fm", distance)
        end

        -- Atualiza barra de vida
        if esp.HealthBar and esp.HealthBg then
            local healthPercent = humanoid.Health / humanoid.MaxHealth
            esp.HealthBar.Size = UDim2.new(healthPercent, 0, 1, 0)
            -- Cor baseada na vida
            if healthPercent > 0.5 then
                esp.HealthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
            elseif healthPercent > 0.25 then
                esp.HealthBar.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
            else
                esp.HealthBar.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
            end
        end
    end
end

-- Destrói os elementos de ESP de um jogador
function DestroyESP(player)
    local esp = ESPObjects[player]
    if not esp then return end
    if esp.Highlight then esp.Highlight:Destroy() end
    if esp.Billboard then esp.Billboard:Destroy() end
    ESPObjects[player] = nil
end

-- Ativa/desativa o ESP
local function ToggleESP(state)
    Settings.ESPEnabled = state
    if state then
        -- Cria ESP para todos os jogadores existentes
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                CreateESP(player)
            end
        end
        -- Atualiza continuamente
        if not ESPObjects.loop then
            -- Usa um loop leve (Heartbeat com throttle)
            local lastUpdate = 0
            ESPObjects.loop = RunService.Heartbeat:Connect(function(dt)
                if not Settings.ESPEnabled then return end
                lastUpdate = lastUpdate + dt
                if lastUpdate >= 0.1 then -- Atualiza a cada 0.1s
                    lastUpdate = 0
                    UpdateESP()
                end
            end)
        end
    else
        -- Destrói todos os ESPs
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
-- GERENCIAMENTO DE JOGADORES (ENTRADA/SAÍDA/RESPAWN)
-- ============================================================

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        task.wait(0.5) -- Aguarda o personagem carregar
        if Settings.HitboxEnabled and IsEnemy(player) then
            ApplyHitbox(player)
        end
        if Settings.ESPEnabled then
            CreateESP(player)
        end
    end)

    player.CharacterRemoving:Connect(function()
        -- Limpa ESP quando o personagem é removido
        DestroyESP(player)
        -- Restaura hitbox
        RestoreHitbox(player)
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    DestroyESP(player)
    RestoreHitbox(player)
end)

-- Inicializa para jogadores já presentes
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function(character)
            task.wait(0.5)
            if Settings.HitboxEnabled and IsEnemy(player) then
                ApplyHitbox(player)
            end
            if Settings.ESPEnabled then
                CreateESP(player)
            end
        end)
    end
end

-- ============================================================
-- INTERFACE DO USUÁRIO (UI)
-- ============================================================

local function CreateUI()
    -- ScreenGui principal
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MobileCombatUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = CoreGui

    -- Botão de abrir/fechar
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "ToggleBtn"
    toggleBtn.Size = UDim2.new(0, 50, 0, 50)
    toggleBtn.Position = UDim2.new(0, 20, 0.5, -25)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Text = "⚙"
    toggleBtn.TextColor3 = Color3.new(1, 1, 1)
    toggleBtn.TextSize = 24
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
    mainFrame.Size = UDim2.new(0, 320, 0, 400)
    mainFrame.Position = UDim2.new(0.5, -160, 0.5, -200)
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true -- Arrastável nativamente
    mainFrame.Visible = false
    mainFrame.Parent = screenGui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 12)
    mainCorner.Parent = mainFrame

    -- Barra de título
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
    titleLabel.Text = "⚔️ Combat Suite"
    titleLabel.TextColor3 = Color3.new(1, 1, 1)
    titleLabel.TextSize = 16
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = titleBar

    -- Botão de fechar
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
        toggleBtn.Visible = true
    end)

    toggleBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = not mainFrame.Visible
    end)

    -- Container de abas
    local tabContainer = Instance.new("Frame")
    tabContainer.Name = "TabContainer"
    tabContainer.Size = UDim2.new(1, -20, 0, 35)
    tabContainer.Position = UDim2.new(0, 10, 0, 45)
    tabContainer.BackgroundTransparency = 1
    tabContainer.Parent = mainFrame

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 5)
    tabLayout.Parent = tabContainer

    -- Área de conteúdo
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "ContentFrame"
    contentFrame.Size = UDim2.new(1, -20, 1, -90)
    contentFrame.Position = UDim2.new(0, 10, 0, 85)
    contentFrame.BackgroundTransparency = 1
    contentFrame.ClipsDescendants = true
    contentFrame.Parent = mainFrame

    -- Função para criar abas
    local tabs = {}
    local currentTab = nil

    local function CreateTab(name)
        local tabBtn = Instance.new("TextButton")
        tabBtn.Size = UDim2.new(0, 70, 1, 0)
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
        content.ScrollBarThickness = 4
        content.Visible = false
        content.Parent = contentFrame

        local contentLayout = Instance.new("UIListLayout")
        contentLayout.Padding = UDim.new(0, 8)
        contentLayout.Parent = content

        tabs[name] = { button = tabBtn, content = content }

        tabBtn.MouseButton1Click:Connect(function()
            -- Esconde todas
            for _, tab in pairs(tabs) do
                tab.content.Visible = false
                tab.button.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
                tab.button.TextColor3 = Color3.fromRGB(180, 180, 180)
            end
            -- Mostra a selecionada
            content.Visible = true
            tabBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 100)
            tabBtn.TextColor3 = Color3.new(1, 1, 1)
            currentTab = name
        end)

        return content
    end

    -- Função para criar toggle
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
        toggleBg.Size = UDim2.new(0, 40, 0, 20)
        toggleBg.Position = UDim2.new(1, -40, 0.5, -10)
        toggleBg.BackgroundColor3 = default and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(60, 60, 70)
        toggleBg.BorderSizePixel = 0
        toggleBg.Parent = frame

        local toggleCorner = Instance.new("UICorner")
        toggleCorner.CornerRadius = UDim.new(1, 0)
        toggleCorner.Parent = toggleBg

        local toggleKnob = Instance.new("Frame")
        toggleKnob.Size = UDim2.new(0, 16, 0, 16)
        toggleKnob.Position = default and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        toggleKnob.BackgroundColor3 = Color3.new(1, 1, 1)
        toggleKnob.BorderSizePixel = 0
        toggleKnob.Parent = toggleBg

        local knobCorner = Instance.new("UICorner")
        knobCorner.CornerRadius = UDim.new(1, 0)
        knobCorner.Parent = toggleKnob

        local isOn = default
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.Parent = toggleBg

        btn.MouseButton1Click:Connect(function()
            isOn = not isOn
            toggleBg.BackgroundColor3 = isOn and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(60, 60, 70)
            TweenService:Create(toggleKnob, TweenInfo.new(0.2), {
                Position = isOn and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
            }):Play()
            if callback then callback(isOn) end
        end)

        return frame
    end

    -- Função para criar slider
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
        sliderBg.Size = UDim2.new(1, -10, 0, 8)
        sliderBg.Position = UDim2.new(0, 5, 0, 28)
        sliderBg.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
        sliderBg.BorderSizePixel = 0
        sliderBg.Parent = frame

        local sliderCorner = Instance.new("UICorner")
        sliderCorner.CornerRadius = UDim.new(1, 0)
        sliderCorner.Parent = sliderBg

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
        fill.BorderSizePixel = 0
        fill.Parent = sliderBg

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(1, 0)
        fillCorner.Parent = fill

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 14, 0, 14)
        knob.Position = UDim2.new((default - min) / (max - min), -7, 0.5, -7)
        knob.BackgroundColor3 = Color3.new(1, 1, 1)
        knob.BorderSizePixel = 0
        knob.ZIndex = 2
        knob.Parent = sliderBg

        local knobCorner = Instance.new("UICorner")
        knobCorner.CornerRadius = UDim.new(1, 0)
        knobCorner.Parent = knob

        local dragging = false

        local function updateSlider(input)
            local pos = math.clamp((input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
            local value = math.floor(min + (max - min) * pos)
            fill.Size = UDim2.new(pos, 0, 1, 0)
            knob.Position = UDim2.new(pos, -7, 0.5, -7)
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
                updateSlider(input)
            end
        end)

        btn.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                updateSlider(input)
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
    -- CONTEÚDO DAS ABAS
    -- ============================================================

    -- Aba Aimbot
    local aimbotTab = CreateTab("Aimbot")
    CreateToggle(aimbotTab, "Ativar Aimbot", Settings.AimbotEnabled, function(v)
        ToggleAimbot(v)
    end)
    CreateSlider(aimbotTab, "FOV", 10, 500, Settings.FOV, function(v)
        Settings.FOV = v
    end)
    CreateSlider(aimbotTab, "Suavidade", 1, 100, Settings.Smoothness * 100, function(v)
        Settings.Smoothness = v / 100
    end)
    CreateSlider(aimbotTab, "Distância Máx.", 50, 2000, Settings.MaxDistance, function(v)
        Settings.MaxDistance = v
    end)
    CreateToggle(aimbotTab, "Team Check", Settings.TeamCheck, function(v)
        Settings.TeamCheck = v
    end)

    -- Aba Hitbox
    local hitboxTab = CreateTab("Hitbox")
    CreateToggle(hitboxTab, "Ativar Hitbox", Settings.HitboxEnabled, function(v)
        ToggleHitbox(v)
    end)
    CreateSlider(hitboxTab, "Tamanho", 1, 20, Settings.HitboxSize, function(v)
        Settings.HitboxSize = v
    end)
    CreateSlider(hitboxTab, "Transparência", 0, 100, Settings.HitboxTransparency * 100, function(v)
        Settings.HitboxTransparency = v / 100
    end)

    -- Aba ESP
    local espTab = CreateTab("ESP")
    CreateToggle(espTab, "Ativar ESP", Settings.ESPEnabled, function(v)
        ToggleESP(v)
    end)
    CreateToggle(espTab, "Caixa (Box)", Settings.ESPBox, function(v)
        Settings.ESPBox = v
    end)
    CreateToggle(espTab, "Nome", Settings.ESPName, function(v)
        Settings.ESPName = v
    end)
    CreateToggle(espTab, "Barra de Vida", Settings.ESPHealth, function(v)
        Settings.ESPHealth = v
    end)
    CreateToggle(espTab, "Distância", Settings.ESPDistance, function(v)
        Settings.ESPDistance = v
    end)
    CreateToggle(espTab, "Highlight", Settings.ESPHighlight, function(v)
        Settings.ESPHighlight = v
    end)
    CreateToggle(espTab, "Team Check", Settings.ESPTeamCheck, function(v)
        Settings.ESPTeamCheck = v
    end)

    -- Aba Configurações
    local configTab = CreateTab("Config")
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(1, 0, 0, 60)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Text = "Script Modular v1.0\nDesenvolvido para Mobile\n\nAimbot | Hitbox | ESP"
    infoLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    infoLabel.TextSize = 11
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextWrapped = true
    infoLabel.Parent = configTab

    -- Seleciona a primeira aba
    if tabs["Aimbot"] then
        tabs["Aimbot"].button:Fire()
    end

    return mainFrame, toggleBtn
end

-- ============================================================
-- INICIALIZAÇÃO
-- ============================================================

-- Cria a interface
local mainFrame, toggleBtn = CreateUI()

-- Atalho de teclado para ativar/desativar aimbot (PC)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Settings.AimbotKey then
        ToggleAimbot(not Settings.AimbotEnabled)
        -- Atualiza o toggle na UI (não ideal, mas funcional para exemplo)
        -- Em um cenário real, você manteria uma referência ao toggle.
    end
end)

-- Notificação de inicialização
local StarterGui = game:GetService("StarterGui")
StarterGui:SetCore("SendNotification", {
    Title = "Combat Suite",
    Text = "Script carregado com sucesso!",
    Duration = 3,
})

print("✅ Script carregado com sucesso!")
