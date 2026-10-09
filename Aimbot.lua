--[[
    ⚡ AUTO PARRY SYSTEM
    ------------------------------------------------------------
    • Auto Parry com predição de trajetória
    • Delay configurável (-100ms a +100ms)
    • Manual Spam (TB) alternável com AP
    • Interface moderna, arrastável, PC + Mobile
    • Otimizado com cooldown e proteção por bola

    ⚠️ IMPORTANTE: adapte a seção CONFIG abaixo ao seu jogo.
]]

-- ============================================================
-- SERVIÇOS
-- ============================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Workspace          = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- ⚙️ CONFIG  — ADAPTE AO SEU JOGO
-- ============================================================
local CONFIG = {

    -- (1) COMO LOCALIZAR AS BOLAS -------------------------------------
    -- Retorne uma lista (array) com as partes que representam bolas.
    getBalls = function()
        local balls = {}

        -- Exemplo 1: pasta "Balls" no Workspace
        local folder = Workspace:FindFirstChild("Balls")
        if folder then
            for _, c in ipairs(folder:GetChildren()) do
                if c:IsA("BasePart") then
                    table.insert(balls, c)
                end
            end
        end

        -- Fallback: qualquer BasePart com "ball" no nome
        if #balls == 0 then
            for _, c in ipairs(Workspace:GetChildren()) do
                if c:IsA("BasePart") and string.find(string.lower(c.Name), "ball") then
                    table.insert(balls, c)
                end
            end
        end

        return balls
    end,

    -- (2) COMO OBTER VELOCIDADE DA BOLA ------------------------------
    getBallVelocity = function(ball)
        return ball.AssemblyLinearVelocity
    end,

    -- (3) COMO OBTER O ROOT DO JOGADOR -------------------------------
    getPlayerRoot = function()
        local char = LocalPlayer.Character
        if not char then return nil end
        return char:FindFirstChild("HumanoidRootPart")
    end,

    -- (4) COMO EXECUTAR O PARRY --------------------------------------
    -- >>> SUBSTITUA PELO MÉTODO DO SEU JOGO <<<
    -- Pode ser um RemoteEvent, RemoteFunction, ou simulação de input.
    executeParry = function()
        -- Exemplo genérico — adapte ao seu jogo:
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes then
            local parry = remotes:FindFirstChild("Parry")
            if parry and parry:IsA("RemoteEvent") then
                parry:FireServer()
                return true
            end
        end

        -- Alternativas comuns:
        -- game:GetService("ReplicatedStorage").Parry:FireServer()
        -- game:GetService("ReplicatedStorage").Remotes.Parry:FireServer()
        return false
    end,

    -- Ajustes de comportamento ---------------------------------------
    ParryRadius    = 9,      -- raio (studs) em que a trajetória deve passar do player
    CheckInterval  = 1/60,   -- frequência do loop (60 Hz)
    ParryCooldown  = 0.08,   -- cooldown global entre parries (segundos)
    SpamRate       = 0.05,   -- intervalo de spam no modo TB
    SpamRange      = 40,     -- distância máxima para spam parry (studs)
    DelayStep      = 5,      -- passo do botão +/- em ms
    DelayMin       = -100,
    DelayMax       = 100,
}

-- ============================================================
-- ESTADO GLOBAL
-- ============================================================
local State = {
    autoParryEnabled = false,
    delayMs          = 0,
    manualSpamOn     = false,   -- mostra/esconde botão AP/TB
    mode             = "AP",    -- "AP" (Auto Parry) | "TB" (Spam)
    lastParry        = 0,
    lastSpam         = 0,
    parriedBalls     = {},      -- [ball] = true
}

-- ============================================================
-- MATEMÁTICA DA TRAJETÓRIA
-- Calcula o tempo até a maior aproximação e a distância mínima.
-- t < 0 → bola já passou / afastando-se
-- ============================================================
local function predictImpact(ball)
    local root = CONFIG.getPlayerRoot()
    if not root or not ball or not ball.Parent then return nil end

    local relPos = ball.Position - root.Position
    local relVel = CONFIG.getBallVelocity(ball) - root.AssemblyLinearVelocity

    local speedSq = relVel:Dot(relVel)
    if speedSq < 1e-3 then return nil end

    local t = -relPos:Dot(relVel) / speedSq
    local closestDist = (relPos + relVel * t).Magnitude

    return t, closestDist
end

-- ============================================================
-- DISPARO DE PARRY (com cooldown global)
-- ============================================================
local function tryFireParry()
    local now = os.clock()
    if now - State.lastParry < CONFIG.ParryCooldown then
        return false
    end
    State.lastParry = now

    local ok, err = pcall(CONFIG.executeParry)
    if not ok then
        warn("[AutoParry] executeParry erro:", err)
    end
    return true
end

-- ============================================================
-- LÓGICA — MODO AP (Auto Parry)
-- ============================================================
local function stepAutoParry()
    local delaySec = State.delayMs / 1000
    local balls    = CONFIG.getBalls()

    for _, ball in ipairs(balls) do
        -- Proteção: pula bolas já parryadas
        if State.parriedBalls[ball] then
            if not ball.Parent then
                State.parriedBalls[ball] = nil
            end
        else
            local t, dist = predictImpact(ball)
            if t and dist and dist <= CONFIG.ParryRadius then
                -- Queremos disparar quando (t + delay) ≈ 0
                -- tolerância de 20ms + janela pós-impacto de 200ms
                local fireT = t + delaySec
                if fireT <= 0.02 and fireT > -0.2 then
                    if tryFireParry() then
                        State.parriedBalls[ball] = true
                    end
                end
            end
        end
    end
end

-- ============================================================
-- LÓGICA — MODO TB (Manual Spam)
-- ============================================================
local function stepSpamParry()
    local now = os.clock()
    if now - State.lastSpam < CONFIG.SpamRate then return end

    local root = CONFIG.getPlayerRoot()
    if not root then return end

    for _, ball in ipairs(CONFIG.getBalls()) do
        if (ball.Position - root.Position).Magnitude < CONFIG.SpamRange then
            State.lastSpam = now
            pcall(CONFIG.executeParry)
            return
        end
    end
end

-- ============================================================
-- INTERFACE — utilitário de drag
-- ============================================================
local function makeDraggable(frame, handle)
    handle = handle or frame
    local dragging, dragStart, startPos

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = input.Position
            startPos  = frame.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

-- ============================================================
-- INTERFACE — criação
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoParryUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- --- Painel principal --------------------------------------------
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 220, 0, 190)
main.Position = UDim2.new(0, 20, 0.35, 0)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
main.BorderSizePixel = 0
main.Active = false
main.Parent = ScreenGui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(60, 60, 75)
stroke.Thickness = 1

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "⚡ AUTO PARRY"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Active = true
title.Parent = main

-- Toggle Auto Parry
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -20, 0, 32)
toggleBtn.Position = UDim2.new(0, 10, 0, 34)
toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
toggleBtn.Text = "Auto Parry: OFF"
toggleBtn.TextColor3 = Color3.fromRGB(255, 110, 110)
toggleBtn.Font = Enum.Font.Gotham
toggleBtn.TextSize = 13
toggleBtn.BorderSizePixel = 0
toggleBtn.AutoButtonColor = false
toggleBtn.Parent = main
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 6)

-- Delay label
local delayLabel = Instance.new("TextLabel")
delayLabel.Size = UDim2.new(1, -20, 0, 18)
delayLabel.Position = UDim2.new(0, 10, 0, 72)
delayLabel.BackgroundTransparency = 1
delayLabel.Text = "Delay: 0 ms"
delayLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
delayLabel.Font = Enum.Font.Gotham
delayLabel.TextSize = 12
delayLabel.TextXAlignment = Enum.TextXAlignment.Left
delayLabel.Parent = main

local minusBtn = Instance.new("TextButton")
minusBtn.Size = UDim2.new(0, 40, 0, 28)
minusBtn.Position = UDim2.new(0, 10, 0, 94)
minusBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
minusBtn.Text = "−"
minusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minusBtn.Font = Enum.Font.GothamBold
minusBtn.TextSize = 18
minusBtn.BorderSizePixel = 0
minusBtn.Parent = main
Instance.new("UICorner", minusBtn).CornerRadius = UDim.new(0, 6)

local plusBtn = Instance.new("TextButton")
plusBtn.Size = UDim2.new(0, 40, 0, 28)
plusBtn.Position = UDim2.new(1, -50, 0, 94)
plusBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
plusBtn.Text = "+"
plusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
plusBtn.Font = Enum.Font.GothamBold
plusBtn.TextSize = 18
plusBtn.BorderSizePixel = 0
plusBtn.Parent = main
Instance.new("UICorner", plusBtn).CornerRadius = UDim.new(0, 6)

-- Indicador de status
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 18)
statusLabel.Position = UDim2.new(0, 10, 1, -26)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "● Idle"
statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 11
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = main

makeDraggable(main, title)

-- --- Botão flutuante: ativar Manual Spam -------------------------
local msBtn = Instance.new("TextButton")
msBtn.Name = "ManualSpamToggle"
msBtn.Size = UDim2.new(0, 46, 0, 46)
msBtn.Position = UDim2.new(0, 20, 0.35, 200)
msBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
msBtn.Text = "MS"
msBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
msBtn.Font = Enum.Font.GothamBold
msBtn.TextSize = 14
msBtn.BorderSizePixel = 0
msBtn.AutoButtonColor = false
msBtn.Parent = ScreenGui
Instance.new("UICorner", msBtn).CornerRadius = UDim.new(0, 8)

local msStroke = Instance.new("UIStroke", msBtn)
msStroke.Color = Color3.fromRGB(90, 90, 105)
msStroke.Thickness = 1

makeDraggable(msBtn)

-- --- Retângulo AP/TB (aparece quando MS está ativo) --------------
local modeBtn = Instance.new("TextButton")
modeBtn.Name = "ModeButton"
modeBtn.Size = UDim2.new(0, 54, 0, 36)
modeBtn.Position = UDim2.new(0, 76, 0.35, 205)
modeBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 0)   -- laranja
modeBtn.Text = "AP"
modeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
modeBtn.Font = Enum.Font.GothamBold
modeBtn.TextSize = 16
modeBtn.BorderSizePixel = 0
modeBtn.AutoButtonColor = false
modeBtn.Visible = false
modeBtn.Parent = ScreenGui
Instance.new("UICorner", modeBtn).CornerRadius = UDim.new(0, 6)

makeDraggable(modeBtn)

-- ============================================================
-- INTERFACE — atualizadores
-- ============================================================
local function refreshAutoToggle()
    if State.autoParryEnabled then
        toggleBtn.Text = "Auto Parry: ON"
        toggleBtn.TextColor3 = Color3.fromRGB(120, 255, 140)
        toggleBtn.BackgroundColor3 = Color3.fromRGB(35, 60, 40)
    else
        toggleBtn.Text = "Auto Parry: OFF"
        toggleBtn.TextColor3 = Color3.fromRGB(255, 110, 110)
        toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    end
end

local function refreshDelay()
    delayLabel.Text = string.format("Delay: %d ms", State.delayMs)
end

local function refreshStatus(text, color)
    statusLabel.Text = "● " .. text
    statusLabel.TextColor3 = color or Color3.fromRGB(180, 180, 180)
end

local function refreshMode()
    modeBtn.Text = State.mode
    if State.mode == "AP" then
        modeBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 0)   -- laranja
        refreshStatus(State.autoParryEnabled and "Auto Parry ativo" or "Idle",
                      State.autoParryEnabled and Color3.fromRGB(120,255,140) or Color3.fromRGB(150,150,150))
    else
        modeBtn.BackgroundColor3 = Color3.fromRGB(220, 70, 70)   -- vermelho (TB)
        refreshStatus("Manual Spam ativo", Color3.fromRGB(255, 180, 120))
    end
end

local function refreshManualSpam()
    modeBtn.Visible = State.manualSpamOn
    msStroke.Color = State.manualSpamOn
        and Color3.fromRGB(255, 140, 0)
        or  Color3.fromRGB(90, 90, 105)
end

-- ============================================================
-- INTERFACE — conexões de eventos
-- ============================================================
toggleBtn.MouseButton1Click:Connect(function()
    State.autoParryEnabled = not State.autoParryEnabled
    refreshAutoToggle()
    refreshMode()
end)

minusBtn.MouseButton1Click:Connect(function()
    State.delayMs = math.max(CONFIG.DelayMin, State.delayMs - CONFIG.DelayStep)
    refreshDelay()
end)

plusBtn.MouseButton1Click:Connect(function()
    State.delayMs = math.min(CONFIG.DelayMax, State.delayMs + CONFIG.DelayStep)
    refreshDelay()
end)

msBtn.MouseButton1Click:Connect(function()
    State.manualSpamOn = not State.manualSpamOn
    refreshManualSpam()
    if not State.manualSpamOn then
        State.mode = "AP"
        refreshMode()
    end
end)

modeBtn.MouseButton1Click:Connect(function()
    State.mode = (State.mode == "AP") and "TB" or "AP"
    refreshMode()
end)

-- ============================================================
-- INICIALIZAÇÃO DA UI
-- ============================================================
refreshAutoToggle()
refreshDelay()
refreshManualSpam()
refreshMode()

-- ============================================================
-- LOOP PRINCIPAL
-- ============================================================
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
    accumulator = accumulator + dt
    if accumulator < CONFIG.CheckInterval then return end
    accumulator = 0

    if State.mode == "AP" and State.autoParryEnabled then
        stepAutoParry()
    elseif State.mode == "TB" and State.manualSpamOn then
        stepSpamParry()
    end
end)

-- ============================================================
-- LIMPEZA: ao respawnar, mantém a UI (ResetOnSpawn=false)
-- ============================================================
LocalPlayer.CharacterAdded:Connect(function()
    State.parriedBalls = {}
end)
