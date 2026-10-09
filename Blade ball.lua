--[[
    ═══════════════════════════════════════════════════════════════════
    BLADE BALL — ADVANCED AUTOMATION SUITE
    Autor: Implementação própria (não copiada de Rise Hub ou similares)
    Versão: 1.0.0
    ═══════════════════════════════════════════════════════════════════
    
    Este script fornece Auto Parry, Manual Spam, ESP e UI moderna
    para o jogo Blade Ball no Roblox.
    
    Estrutura:
        1. Serviços e Constantes
        2. Signal (conexões gerenciadas)
        3. ConfigManager (persistência)
        4. Estado Global (State)
        5. BallTracker (detecção da bola)
        6. ThreatAnalyzer (análise de ameaça)
        7. ParryEngine (execução de parry)
        8. ManualSpam (overlay clicável)
        9. Visuals (ESP, Highlight, Trajetória)
       10. UICore (interface completa)
       11. KeybindManager (atalhos)
       12. Inicialização e Loop Principal
--]]

-- ============================================================
-- 1. SERVIÇOS E CONSTANTES
-- ============================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService       = game:GetService("TweenService")
local HttpService        = game:GetService("HttpService")
local StarterGui         = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- Constantes de configuração
local CONFIG_FOLDER = "BladeBallSuite"
local PARRY_COOLDOWN = 0.5       -- Cooldown interno entre parries (segundos)
local MAX_PARRY_HISTORY = 3      -- Histórico para anti-spam

-- ============================================================
-- 2. SIGNAL — Conexões gerenciadas
-- ============================================================
-- Wrapper simples para conexões que podem ser desconectadas em lote
local Signal = {}
Signal.__index = Signal

function Signal.new()
    local self = setmetatable({}, Signal)
    self._connections = {}
    return self
end

function Signal:Connect(event, callback)
    local conn = event:Connect(callback)
    table.insert(self._connections, conn)
    return conn
end

function Signal:DisconnectAll()
    for _, conn in ipairs(self._connections) do
        pcall(function() conn:Disconnect() end)
    end
    self._connections = {}
end

-- ============================================================
-- 3. CONFIG MANAGER — Persistência de configurações
-- ============================================================
local ConfigManager = {}
ConfigManager.__index = ConfigManager

-- Valores padrão de todas as configurações
local DEFAULT_CONFIG = {
    -- Combat
    autoParryEnabled   = false,
    manualSpamEnabled  = false,
    delayMs            = 0,          -- Delay em ms (mínimo -100)
    parryRange         = 18,         -- Distância máxima de ativação
    sensitivity        = 50,         -- 0-100
    legitMode          = false,
    fastReactMode      = false,
    antiRepeatEnabled  = true,
    -- Visuals
    ballESP            = false,
    ballHighlight      = false,
    showTrajectory     = false,
    showDistance       = false,
    showSpeed          = false,
    playerESP          = false,
    playerHighlight    = false,
    showThreatIndicator = true,
    -- Settings
    uiScale            = 1.0,
    notifications      = true,
    theme              = "Dark",
    -- Keybinds (KeyCode como string para salvar)
    keybindMenu        = "RightShift",
    keybindAutoParry   = "F",
    keybindManualSpam  = "G",
    keybindESP         = "H",
    keybindLegitMode   = "J",
    -- Manual Spam
    spamFrequency      = 50,         -- ms entre cliques
}

function ConfigManager.new()
    local self = setmetatable({}, ConfigManager)
    self.profiles = { default = {} }
    self.currentProfile = "default"
    self.data = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        self.data[k] = v
    end
    return self
end

function ConfigManager:set(key, value)
    if self.data[key] ~= nil then
        self.data[key] = value
    end
end

function ConfigManager:get(key)
    return self.data[key]
end

function ConfigManager:save(profileName)
    profileName = profileName or self.currentProfile
    local success, err = pcall(function()
        if not isfolder(CONFIG_FOLDER) then
            makefolder(CONFIG_FOLDER)
        end
        local path = CONFIG_FOLDER .. "/" .. profileName .. ".json"
        writefile(path, HttpService:JSONEncode(self.data))
    end)
    return success
end

function ConfigManager:load(profileName)
    profileName = profileName or self.currentProfile
    local success, data = pcall(function()
        local path = CONFIG_FOLDER .. "/" .. profileName .. ".json"
        if isfile(path) then
            return HttpService:JSONDecode(readfile(path))
        end
    end)
    if success and data then
        for k, v in pairs(data) do
            if self.data[k] ~= nil then
                self.data[k] = v
            end
        end
        return true
    end
    return false
end

function ConfigManager:reset()
    for k, v in pairs(DEFAULT_CONFIG) do
        self.data[k] = v
    end
    self:save()
end

function ConfigManager:listProfiles()
    local profiles = {}
    pcall(function()
        if isfolder(CONFIG_FOLDER) then
            for _, f in ipairs(listfiles(CONFIG_FOLDER)) do
                local name = f:match("([^/\\]+)%.json$")
                if name then table.insert(profiles, name) end
            end
        end
    end)
    return profiles
end

-- ============================================================
-- 4. ESTADO GLOBAL
-- ============================================================
local State = {
    -- Bola
    currentBall       = nil,
    ballTarget        = nil,
    ballDistance      = math.huge,
    ballSpeed         = 0,
    ballPosition      = Vector3.zero,
    -- Jogador
    localHRP          = nil,
    -- Parry
    lastParryTime     = 0,
    parryHistory      = {},
    threatDetected    = false,
    threatTime        = 0,
    -- Referências de UI
    ui                = {},
    -- Conexões ativas
    signals           = Signal.new(),
    -- Performance
    fps               = 0,
    ping              = 0,
}

-- ============================================================
-- 5. BALL TRACKER — Detecção da bola
-- ============================================================
local BallTracker = {}
BallTracker.__index = BallTracker

function BallTracker.new()
    local self = setmetatable({}, BallTracker)
    self._conn = nil
    self._ballConn = nil
    return self
end

function BallTracker:getActiveBall()
    local ballsFolder = workspace:FindFirstChild("Balls")
    if not ballsFolder then return nil end

    for _, ball in ipairs(ballsFolder:GetChildren()) do
        local isReal = ball:GetAttribute("realBall")
        if isReal then
            return ball
        end
    end
    return nil
end

function BallTracker:start()
    -- Listener para quando novas bolas surgem
    local ballsFolder = workspace:FindFirstChild("Balls")
    if ballsFolder then
        self._ballConn = ballsFolder.ChildAdded:Connect(function()
            task.wait(0.1)
            State.currentBall = self:getActiveBall()
        end)
    end

    -- Listener para mudanças no alvo da bola
    self._conn = RunService.PreSimulation:Connect(function()
        local ball = self:getActiveBall()
        if not ball then
            State.currentBall = nil
            return
        end

        State.currentBall = ball
        local success, err = pcall(function()
            State.ballTarget = ball:GetAttribute("target")
            State.ballPosition = ball.Position

            -- Obter velocidade via corpo de força (zoomies) ou parte
            local zoomies = ball:FindFirstChild("zoomies")
            if zoomies and zoomies:IsA("BodyVelocity") then
                State.ballSpeed = zoomies.VectorVelocity.Magnitude
            else
                -- Fallback: calcular por posição
                State.ballSpeed = 0
            end
        end)
    end)
end

function BallTracker:stop()
    if self._conn then
        self._conn:Disconnect()
        self._conn = nil
    end
    if self._ballConn then
        self._ballConn:Disconnect()
        self._ballConn = nil
    end
end

-- ============================================================
-- 6. THREAT ANALYZER — Análise de ameaça da bola
-- ============================================================
local ThreatAnalyzer = {}
ThreatAnalyzer.__index = ThreatAnalyzer

function ThreatAnalyzer.new()
    local self = setmetatable({}, ThreatAnalyzer)
    return self
end

--[[
    Determina se a bola é uma ameaça real ao jogador.
    Critérios:
      1. Bola está direcionada ao jogador (target == nome do jogador)
      2. Bola está dentro do range configurado
      3. O vetor de velocidade aponta na direção do jogador (produto escalar)
      4. Tempo estimado de impacto é aceitável
--]]
function ThreatAnalyzer:isThreat(config)
    local ball = State.currentBall
    if not ball then return false, 0 end

    local hrp = State.localHRP
    if not hrp then return false, 0 end

    local target = State.ballTarget
    if target ~= LocalPlayer.Name then return false, 0 end

    local ballPos = State.ballPosition
    local hrpPos = hrp.Position
    local distance = (hrpPos - ballPos).Magnitude
    local speed = State.ballSpeed

    -- Range check
    if distance > config.parryRange then return false, distance end

    -- Velocidade mínima para considerar ameaça
    if speed < 5 then return false, distance end

    -- Verificar direção: produto escalar entre velocidade da bola e vetor para o jogador
    local zoomies = ball:FindFirstChild("zoomies")
    if zoomies and zoomies:IsA("BodyVelocity") then
        local ballVel = zoomies.VectorVelocity
        local dirToPlayer = (hrpPos - ballPos).Unit
        local dot = ballVel.Unit:Dot(dirToPlayer)
        -- Se o produto escalar for < 0.3, a bola não está vindo na direção do jogador
        if dot < 0.3 then return false, distance end
    end

    -- Tempo estimado de impacto
    local timeToImpact = distance / math.max(speed, 0.1)

    return true, distance, timeToImpact
end

--[[
    Calcula o limiar de tempo para disparar o parry.
    Incorpora:
      - Delay configurado (pode ser negativo)
      - Sensibilidade
      - Modo de reação rápida
--]]
function ThreatAnalyzer:getParryThreshold(config)
    local baseThreshold = 0.35 -- segundos base

    -- Ajuste por sensibilidade (mais sensível = dispara mais cedo)
    local sensFactor = 1.0 - (config.sensitivity / 100) * 0.5
    baseThreshold = baseThreshold * sensFactor

    -- Delay em ms (negativo = dispara mais cedo)
    local delaySec = config.delayMs / 1000
    baseThreshold = baseThreshold + delaySec

    -- Modo de reação rápida
    if config.fastReactMode then
        baseThreshold = baseThreshold * 0.6
    end

    -- Modo legítimo: adiciona variação aleatória para parecer humano
    if config.legitMode then
        baseThreshold = baseThreshold * (0.85 + math.random() * 0.3)
    end

    return math.max(0.02, baseThreshold)
end

-- ============================================================
-- 7. PARRY ENGINE — Execução do parry
-- ============================================================
local ParryEngine = {}
ParryEngine.__index = ParryEngine

function ParryEngine.new()
    local self = setmetatable({}, ParryEngine)
    self._spamConn = nil
    self._lastSpamTime = 0
    return self
end

--[[
    Executa um parry enviando evento de mouse.
    Método: VirtualInputManager.SendMouseButtonEvent
    Isso simula o clique no botão de parry do jogo.
--]]
function ParryEngine:executeParry()
    local now = tick()

    -- Cooldown interno
    if now - State.lastParryTime < PARRY_COOLDOWN then
        return false
    end

    -- Anti-repeat: se o parry anterior foi muito recente e a bola não mudou de alvo
    if ConfigManager:get("antiRepeatEnabled") then
        for _, t in ipairs(State.parryHistory) do
            if now - t < 0.15 then
                return false
            end
        end
    end

    -- Enviar evento de clique
    local success, err = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        task.wait(0.02)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end)

    if success then
        State.lastParryTime = now
        table.insert(State.parryHistory, now)
        -- Limitar histórico
        while #State.parryHistory > MAX_PARRY_HISTORY do
            table.remove(State.parryHistory, 1)
        end
        return true
    end

    return false
end

--[[
    Loop principal de Auto Parry.
    Executado a cada frame via RunService.
--]]
function ParryEngine:update()
    if not ConfigManager:get("autoParryEnabled") then return end

    -- Verificar se o jogador tem personagem vivo
    local hrp = State.localHRP
    if not hrp then return end

    local isThreat, distance, timeToImpact = ThreatAnalyzer:isThreat(ConfigManager.data)

    -- Indicador visual de ameaça
    if isThreat then
        if not State.threatDetected then
            State.threatDetected = true
            State.threatTime = tick()
            if State.ui.threatIndicator then
                State.ui.threatIndicator.Visible = true
            end
        end
    else
        if State.threatDetected then
            State.threatDetected = false
            if State.ui.threatIndicator then
                State.ui.threatIndicator.Visible = false
            end
        end
    end

    -- Disparar parry se for ameaça
    if isThreat and timeToImpact then
        local threshold = ThreatAnalyzer:getParryThreshold(ConfigManager.data)
        if timeToImpact <= threshold then
            ParryEngine:executeParry()
        end
    end
end

--[[
    Inicia o Manual Spam.
    Cria um loop que dispara parry na frequência configurada.
--]]
function ParryEngine:startManualSpam()
    self:stopManualSpam()
    self._spamConn = RunService.Heartbeat:Connect(function()
        if not ConfigManager:get("manualSpamEnabled") then return end

        local now = tick()
        local freq = ConfigManager:get("spamFrequency") / 1000
        if now - self._lastSpamTime >= freq then
            ParryEngine:executeParry()
            self._lastSpamTime = now
        end
    end)
end

function ParryEngine:stopManualSpam()
    if self._spamConn then
        self._spamConn:Disconnect()
        self._spamConn = nil
    end
end

-- ============================================================
-- 8. MANUAL SPAM — Overlay clicável
-- ============================================================
local ManualSpam = {}
ManualSpam.__index = ManualSpam

function ManualSpam.new()
    local self = setmetatable({}, ManualSpam)
    self._frame = nil
    self._label = nil
    self._mode = "AP" -- "AP" ou "TB"
    return self
end

function ManualSpam:create(parent)
    -- Frame do botão Manual Spam
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
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 180, 50)
    stroke.Thickness = 1.5
    stroke.Parent = frame

    local label = Instance.new("TextLabel")
    label.Name = "ModeLabel"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "AP"
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = frame

    self._frame = frame
    self._label = label

    -- Detectar clique para alternar modo
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.Parent = frame

    btn.MouseButton1Click:Connect(function()
        if self._mode == "AP" then
            self._mode = "TB"
            label.Text = "TB"
            frame.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
            stroke.Color = Color3.fromRGB(0, 160, 255)
        else
            self._mode = "AP"
            label.Text = "AP"
            frame.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
            stroke.Color = Color3.fromRGB(255, 180, 50)
        end
    end)

    -- Arrastar o botão
    local dragging, dragStart, startPos
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or
                         input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    return self
end

function ManualSpam:setVisible(visible)
    if self._frame then
        self._frame.Visible = visible
    end
end

-- ============================================================
-- 9. VISUALS — ESP, Highlight, Trajetória
-- ============================================================
local Visuals = {}
Visuals.__index = Visuals

function Visuals.new()
    local self = setmetatable({}, Visuals)
    self._highlight = nil
    self._espGui = nil
    self._trajectoryParts = {}
    self._playerGuis = {}
    self._conn = nil
    return self
end

--[[
    Cria ou atualiza o Highlight da bola.
--]]
function Visuals:updateBallHighlight()
    local ball = State.currentBall
    if not ball then
        if self._highlight then
            self._highlight:Destroy()
            self._highlight = nil
        end
        return
    end

    if not ConfigManager:get("ballHighlight") then
        if self._highlight then
            self._highlight:Destroy()
            self._highlight = nil
        end
        return
    end

    if not self._highlight or self._highlight.Parent ~= ball then
        if self._highlight then self._highlight:Destroy() end
        local hl = Instance.new("Highlight")
        hl.FillColor = Color3.fromRGB(255, 140, 0)
        hl.OutlineColor = Color3.fromRGB(255, 200, 100)
        hl.FillTransparency = 0.6
        hl.OutlineTransparency = 0.2
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = ball
        self._highlight = hl
    end

    -- Cor baseada na distância
    local dist = State.ballDistance
    if dist < 15 then
        self._highlight.FillColor = Color3.fromRGB(255, 50, 50) -- Crítico
    elseif dist < 40 then
        self._highlight.FillColor = Color3.fromRGB(255, 180, 0) -- Próximo
    else
        self._highlight.FillColor = Color3.fromRGB(0, 200, 100) -- Distante
    end
end

--[[
    Cria ou atualiza o ESP (BillboardGui) da bola.
--]]
function Visuals:updateBallESP()
    local ball = State.currentBall
    if not ball then
        if self._espGui then
            self._espGui:Destroy()
            self._espGui = nil
        end
        return
    end

    if not ConfigManager:get("ballESP") then
        if self._espGui then
            self._espGui:Destroy()
            self._espGui = nil
        end
        return
    end

    if not self._espGui or self._espGui.Parent ~= ball then
        if self._espGui then self._espGui:Destroy() end

        local gui = Instance.new("BillboardGui")
        gui.Name = "BallESP"
        gui.Size = UDim2.new(0, 150, 0, 50)
        gui.StudsOffset = Vector3.new(0, 3, 0)
        gui.AlwaysOnTop = true
        gui.Parent = ball

        local label = Instance.new("TextLabel")
        label.Name = "InfoLabel"
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(255, 140, 0)
        label.TextScaled = false
        label.TextSize = 14
        label.Font = Enum.Font.GothamBold
        label.TextStrokeTransparency = 0.5
        label.Text = "BALL"
        label.Parent = gui

        self._espGui = gui
    end

    -- Atualizar texto
    local parts = {}
    if ConfigManager:get("showDistance") then
        table.insert(parts, string.format("Dist: %.0f", State.ballDistance))
    end
    if ConfigManager:get("showSpeed") then
        table.insert(parts, string.format("Spd: %.0f", State.ballSpeed))
    end
    if #parts == 0 then
        table.insert(parts, "BALL")
    end

    local infoLabel = self._espGui:FindFirstChild("InfoLabel")
    if infoLabel then
        infoLabel.Text = table.concat(parts, " | ")
        -- Cor por distância
        if State.ballDistance < 15 then
            infoLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
        elseif State.ballDistance < 40 then
            infoLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
        else
            infoLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        end
    end
end

--[[
    Cria visualização de trajetória (linha pontilhada da bola até o jogador).
--]]
function Visuals:updateTrajectory()
    -- Limpar partes antigas
    for _, part in ipairs(self._trajectoryParts) do
        pcall(function() part:Destroy() end)
    end
    self._trajectoryParts = {}

    if not ConfigManager:get("showTrajectory") then return end

    local ball = State.currentBall
    local hrp = State.localHRP
    if not ball or not hrp then return end

    local ballPos = State.ballPosition
    local hrpPos = hrp.Position
    local dir = (hrpPos - ballPos)
    local dist = dir.Magnitude
    if dist < 1 then return end
    dir = dir.Unit

    -- Criar esferas ao longo da trajetória
    local steps = math.min(8, math.floor(dist / 5))
    for i = 1, steps do
        local t = i / (steps + 1)
        local pos = ballPos + dir * (dist * t)

        local part = Instance.new("Part")
        part.Name = "BBTrajectory"
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(0.3, 0.3, 0.3)
        part.Position = pos
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(255, 140, 0)
        part.Transparency = 0.4
        part.Parent = workspace

        table.insert(self._trajectoryParts, part)
    end
end

--[[
    Atualiza ESP de jogadores.
--]]
function Visuals:updatePlayerESP()
    -- Limpar GUIs de jogadores que não existem mais
    for plr, gui in pairs(self._playerGuis) do
        if not plr.Parent or not plr.Character then
            if gui then gui:Destroy() end
            self._playerGuis[plr] = nil
        end
    end

    if not ConfigManager:get("playerESP") then
        for plr, gui in pairs(self._playerGuis) do
            if gui then gui:Destroy() end
            self._playerGuis[plr] = nil
        end
        return
    end

    local hrp = State.localHRP
    if not hrp then return end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end

        local char = plr.Character
        local pHead = char and char:FindFirstChild("Head")
        if not pHead then
            if self._playerGuis[plr] then
                self._playerGuis[plr]:Destroy()
                self._playerGuis[plr] = nil
            end
            continue
        end

        -- Criar GUI se não existir
        if not self._playerGuis[plr] or self._playerGuis[plr].Parent ~= pHead then
            if self._playerGuis[plr] then self._playerGuis[plr]:Destroy() end

            local gui = Instance.new("BillboardGui")
            gui.Name = "PlayerESP"
            gui.Size = UDim2.new(0, 120, 0, 40)
            gui.StudsOffset = Vector3.new(0, 2.5, 0)
            gui.AlwaysOnTop = true
            gui.Parent = pHead

            local label = Instance.new("TextLabel")
            label.Name = "InfoLabel"
            label.Size = UDim2.new(1, 0, 1, 0)
            label.BackgroundTransparency = 1
            label.TextColor3 = Color3.fromRGB(255, 255, 255)
            label.TextScaled = false
            label.TextSize = 12
            label.Font = Enum.Font.Gotham
            label.TextStrokeTransparency = 0.5
            label.Text = plr.Name
            label.Parent = gui

            self._playerGuis[plr] = gui
        end

        -- Atualizar distância
        local pRoot = char:FindFirstChild("HumanoidRootPart")
        if pRoot then
            local dist = (hrp.Position - pRoot.Position).Magnitude
            local label = self._playerGuis[plr]:FindFirstChild("InfoLabel")
            if label then
                label.Text = string.format("%s [%.0f]", plr.Name, dist)
                -- Destacar se for o alvo da bola
                if State.ballTarget == plr.Name then
                    label.TextColor3 = Color3.fromRGB(255, 80, 80)
                else
                    label.TextColor3 = Color3.fromRGB(255, 255, 255)
                end
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
    if self._conn then
        self._conn:Disconnect()
        self._conn = nil
    end
    -- Limpar
    for _, part in ipairs(self._trajectoryParts) do
        pcall(function() part:Destroy() end)
    end
    self._trajectoryParts = {}
    for plr, gui in pairs(self._playerGuis) do
        if gui then pcall(function() gui:Destroy() end) end
    end
    self._playerGuis = {}
    if self._highlight then self._highlight:Destroy() self._highlight = nil end
    if self._espGui then self._espGui:Destroy() self._espGui = nil end
end

-- ============================================================
-- 10. UI CORE — Interface moderna
-- ============================================================
local UICore = {}
UICore.__index = UICore

-- Paleta de cores
local COLORS = {
    bg        = Color3.fromRGB(18, 18, 22),
    panel     = Color3.fromRGB(25, 25, 32),
    panelAlt  = Color3.fromRGB(32, 32, 40),
    accent    = Color3.fromRGB(255, 140, 0),
    accentDim = Color3.fromRGB(180, 100, 0),
    text      = Color3.fromRGB(230, 230, 240),
    textDim   = Color3.fromRGB(140, 140, 160),
    green     = Color3.fromRGB(50, 200, 100),
    red       = Color3.fromRGB(220, 60, 60),
    border    = Color3.fromRGB(50, 50, 65),
}

function UICore.new()
    local self = setmetatable({}, UICore)
    self.screenGui = nil
    self.mainFrame = nil
    self.tabs = {}
    self.currentTab = nil
    self.toggleStates = {}
    self.connections = Signal.new()
    self.dragging = false
    self.dragStart = nil
    self.startPos = nil
    self._notifContainer = nil
    return self
end

-- Cria um elemento com propriedades comuns
function UICore:_create(className, props, parent)
    local obj = Instance.new(className)
    for k, v in pairs(props) do
        obj[k] = v
    end
    obj.Parent = parent
    return obj
end

-- Cria um toggle moderno
function UICore:_createToggle(parent, labelText, configKey, callback)
    local config = ConfigManager

    local frame = self:_create("Frame", {
        Name = "Toggle_" .. configKey,
        Size = UDim2.new(1, -20, 0, 36),
        BackgroundColor3 = COLORS.panelAlt,
        BorderSizePixel = 0,
    }, parent)

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame

    local label = self:_create("TextLabel", {
        Size = UDim2.new(1, -70, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = COLORS.text,
        TextSize = 14,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)

    -- Switch track
    local track = self:_create("Frame", {
        Size = UDim2.new(0, 44, 0, 22),
        Position = UDim2.new(1, -58, 0.5, -11),
        BackgroundColor3 = COLORS.border,
        BorderSizePixel = 0,
    }, frame)

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track

    -- Switch knob
    local knob = self:_create("Frame", {
        Size = UDim2.new(0, 18, 0, 18),
        Position = UDim2.new(0, 2, 0.5, -9),
        BackgroundColor3 = COLORS.textDim,
        BorderSizePixel = 0,
    }, track)

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    -- Botão invisível para clique
    local btn = self:_create("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
    }, frame)

    local state = config:get(configKey) or false
    self.toggleStates[configKey] = state

    local function updateVisual(on)
        TweenService:Create(track, TweenInfo.new(0.2), {
            BackgroundColor3 = on and COLORS.accent or COLORS.border
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.2), {
            Position = on and UDim2.new(0, 24, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
            BackgroundColor3 = on and Color3.fromRGB(255, 255, 255) or COLORS.textDim
        }):Play()
    end

    updateVisual(state)

    btn.MouseButton1Click:Connect(function()
        state = not state
        self.toggleStates[configKey] = state
        config:set(configKey, state)
        updateVisual(state)
        if callback then callback(state) end
    end)

    return frame, function(v) state = v; self.toggleStates[configKey] = v; updateVisual(v) end
end

-- Cria um slider moderno
function UICore:_createSlider(parent, labelText, configKey, min, max, suffix)
    local config = ConfigManager

    local frame = self:_create("Frame", {
        Name = "Slider_" .. configKey,
        Size = UDim2.new(1, -20, 0, 56),
        BackgroundColor3 = COLORS.panelAlt,
        BorderSizePixel = 0,
    }, parent)

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame

    self:_create("TextLabel", {
        Size = UDim2.new(0.6, 0, 0, 24),
        Position = UDim2.new(0, 12, 0, 6),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = COLORS.text,
        TextSize = 14,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)

    local valueLabel = self:_create("TextLabel", {
        Size = UDim2.new(0.3, 0, 0, 24),
        Position = UDim2.new(0.7, 0, 0, 6),
        BackgroundTransparency = 1,
        Text = tostring(config:get(configKey)) .. suffix,
        TextColor3 = COLORS.accent,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, frame)

    -- Track
    local trackBg = self:_create("Frame", {
        Size = UDim2.new(1, -24, 0, 6),
        Position = UDim2.new(0, 12, 0, 38),
        BackgroundColor3 = COLORS.border,
        BorderSizePixel = 0,
    }, frame)

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = trackBg

    local fill = self:_create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = COLORS.accent,
        BorderSizePixel = 0,
    }, trackBg)

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    -- Botão de arrastar
    local dragBtn = self:_create("TextButton", {
        Size = UDim2.new(1, 12, 1, 20),
        Position = UDim2.new(0, -6, 0.5, -10),
        BackgroundTransparency = 1,
        Text = "",
    }, trackBg)

    local function updateFromValue(val)
        local pct = (val - min) / (max - min)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        valueLabel.Text = tostring(val) .. suffix
        config:set(configKey, val)
    end

    updateFromValue(config:get(configKey))

    local dragging = false

    local function processInput(input)
        local trackPos = trackBg.AbsolutePosition
        local trackSize = trackBg.AbsoluteSize
        local mouseX = input.Position.X
        local pct = math.clamp((mouseX - trackPos.X) / trackSize.X, 0, 1)
        local val = math.floor(min + (max - min) * pct)
        updateFromValue(val)
    end

    dragBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            processInput(input)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or
                         input.UserInputType == Enum.UserInputType.Touch) then
            processInput(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    return frame
end

-- Cria um campo de texto numérico
function UICore:_createInput(parent, labelText, configKey, placeholder)
    local frame = self:_create("Frame", {
        Size = UDim2.new(1, -20, 0, 40),
        BackgroundColor3 = COLORS.panelAlt,
        BorderSizePixel = 0,
    }, parent)

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame

    self:_create("TextLabel", {
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = COLORS.text,
        TextSize = 14,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)

    local box = self:_create("TextBox", {
        Size = UDim2.new(0, 80, 0, 28),
        Position = UDim2.new(1, -92, 0.5, -14),
        BackgroundColor3 = COLORS.bg,
        Text = tostring(ConfigManager:get(configKey) or ""),
        TextColor3 = COLORS.accent,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = COLORS.textDim,
        ClearTextOnFocus = false,
    }, frame)

    local boxCorner = Instance.new("UICorner")
    boxCorner.CornerRadius = UDim.new(0, 4)
    boxCorner.Parent = box

    box.FocusLost:Connect(function()
        local num = tonumber(box.Text)
        if num then
            ConfigManager:set(configKey, num)
        else
            box.Text = tostring(ConfigManager:get(configKey))
        end
    end)

    return frame
end

-- Cria notificação
function UICore:notify(title, text, duration)
    if not ConfigManager:get("notifications") then return end
    duration = duration or 3

    if not self._notifContainer then
        self._notifContainer = self:_create("Frame", {
            Name = "Notifications",
            Size = UDim2.new(0, 300, 1, -20),
            Position = UDim2.new(1, -310, 0, 10),
            BackgroundTransparency = 1,
        }, self.screenGui)

        local layout = Instance.new("UIListLayout")
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 6)
        layout.Parent = self._notifContainer
    end

    local notif = self:_create("Frame", {
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor3 = COLORS.panel,
        BorderSizePixel = 0,
    }, self._notifContainer)

    local nCorner = Instance.new("UICorner")
    nCorner.CornerRadius = UDim.new(0, 8)
    nCorner.Parent = notif

    local accentBar = self:_create("Frame", {
        Size = UDim2.new(0, 4, 1, -12),
        Position = UDim2.new(0, 6, 0, 6),
        BackgroundColor3 = COLORS.accent,
        BorderSizePixel = 0,
    }, notif)

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(1, 0)
    barCorner.Parent = accentBar

    self:_create("TextLabel", {
        Size = UDim2.new(1, -30, 0, 22),
        Position = UDim2.new(0, 18, 0, 6),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = COLORS.accent,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, notif)

    self:_create("TextLabel", {
        Size = UDim2.new(1, -30, 0, 18),
        Position = UDim2.new(0, 18, 0, 26),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = COLORS.textDim,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, notif)

    -- Animação de entrada
    notif.Position = UDim2.new(1, 50, 0, 0)
    TweenService:Create(notif, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 0, 0, 0)
    }):Play()

    -- Auto-remover
    task.delay(duration, function()
        if notif and notif.Parent then
            local outTween = TweenService:Create(notif, TweenInfo.new(0.3), {
                Position = UDim2.new(1, 50, 0, 0),
                BackgroundTransparency = 1
            })
            outTween:Play()
            outTween.Completed:Connect(function()
                notif:Destroy()
            end)
        end
    end)
end

-- Cria a interface principal
function UICore:build()
    -- ScreenGui principal
    self.screenGui = Instance.new("ScreenGui")
    self.screenGui.Name = "BladeBallSuite"
    self.screenGui.ResetOnSpawn = false
    self.screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    self.screenGui.IgnoreGuiInset = true
    self.screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    State.ui.screenGui = self.screenGui

    -- Frame principal
    local main = Instance.new("Frame")
    main.Name = "MainWindow"
    main.Size = UDim2.new(0, 560, 0, 400)
    main.Position = UDim2.new(0.5, -280, 0.5, -200)
    main.BackgroundColor3 = COLORS.bg
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Parent = self.screenGui

    self.mainFrame = main

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 10)
    mainCorner.Parent = main

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = COLORS.border
    mainStroke.Thickness = 1
    mainStroke.Parent = main

    -- Barra de título
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 36)
    titleBar.BackgroundColor3 = COLORS.panel
    titleBar.BorderSizePixel = 0
    titleBar.Parent = main

    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 10)
    titleCorner.Parent = titleBar

    -- Cobrir cantos inferiores da titleBar
    local cover = Instance.new("Frame")
    cover.Size = UDim2.new(1, 0, 0, 10)
    cover.Position = UDim2.new(0, 0, 1, -10)
    cover.BackgroundColor3 = COLORS.panel
    cover.BorderSizePixel = 0
    cover.Parent = titleBar

    Instance.new("TextLabel", {
        Size = UDim2.new(0, 200, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1,
        Text = "⚔ BLADE BALL SUITE",
        TextColor3 = COLORS.accent,
        TextSize = 15,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar,
    })

    -- Botão fechar
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -36, 0.5, -14)
    closeBtn.BackgroundColor3 = COLORS.red
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 14
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Parent = titleBar

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 6)
    closeCorner.Parent = closeBtn

    closeBtn.MouseButton1Click:Connect(function()
        main.Visible = false
        if State.ui.floatingBtn then
            State.ui.floatingBtn.Visible = true
        end
    end)

    -- Arrastar janela
    local titleDrag = Instance.new("TextButton")
    titleDrag.Size = UDim2.new(1, -80, 1, 0)
    titleDrag.BackgroundTransparency = 1
    titleDrag.Text = ""
    titleDrag.Parent = titleBar

    local dragging, dragStart, startPos

    titleDrag.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or
                         input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    -- Container de abas
    local tabBar = Instance.new("Frame")
    tabBar.Name = "TabBar"
    tabBar.Size = UDim2.new(1, 0, 0, 34)
    tabBar.Position = UDim2.new(0, 0, 0, 36)
    tabBar.BackgroundColor3 = COLORS.panel
    tabBar.BorderSizePixel = 0
    tabBar.Parent = main

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 4)
    tabLayout.Parent = tabBar

    local tabPadding = Instance.new("UIPadding")
    tabPadding.PaddingLeft = UDim.new(0, 10)
    tabPadding.PaddingTop = UDim.new(0, 4)
    tabPadding.Parent = tabBar

    -- Container de conteúdo
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, 0, 1, -70)
    content.Position = UDim2.new(0, 0, 0, 70)
    content.BackgroundTransparency = 1
    content.Parent = main

    -- Criar abas
    local tabNames = { "Combat", "Visuals", "Settings" }
    local tabContents = {}

    for i, name in ipairs(tabNames) do
        -- Botão da aba
        local tabBtn = Instance.new("TextButton")
        tabBtn.Name = "Tab_" .. name
        tabBtn.Size = UDim2.new(0, 90, 0, 26)
        tabBtn.BackgroundColor3 = i == 1 and COLORS.accent or COLORS.panelAlt
        tabBtn.Text = name
        tabBtn.TextColor3 = i == 1 and Color3.fromRGB(255, 255, 255) or COLORS.textDim
        tabBtn.TextSize = 13
        tabBtn.Font = Enum.Font.GothamBold
        tabBtn.Parent = tabBar

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 6)
        btnCorner.Parent = tabBtn

        -- Scroll container
        local scroll = Instance.new("ScrollingFrame")
        scroll.Name = "Scroll_" .. name
        scroll.Size = UDim2.new(1, -20, 1, -10)
        scroll.Position = UDim2.new(0, 10, 0, 5)
        scroll.BackgroundTransparency = 1
        scroll.ScrollBarThickness = 4
        scroll.ScrollBarImageColor3 = COLORS.accent
        scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.Visible = (i == 1)
        scroll.Parent = content

        local listLayout = Instance.new("UIListLayout")
        listLayout.SortOrder = Enum.SortOrder.LayoutOrder
        listLayout.Padding = UDim.new(0, 6)
        listLayout.Parent = scroll

        tabContents[name] = scroll

        tabBtn.MouseButton1Click:Connect(function()
            for _, other in ipairs(tabBar:GetChildren()) do
                if other:IsA("TextButton") then
                    other.BackgroundColor3 = COLORS.panelAlt
                    other.TextColor3 = COLORS.textDim
                end
            end
            tabBtn.BackgroundColor3 = COLORS.accent
            tabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

            for _, sc in pairs(tabContents) do
                sc.Visible = false
            end
            scroll.Visible = true
        end)
    end

    -- ═══ ABA COMBAT ═══
    local combatScroll = tabContents["Combat"]

    self:_create("TextLabel", {
        Size = UDim2.new(1, -20, 0, 24),
        BackgroundTransparency = 1,
        Text = "⚔ COMBAT",
        TextColor3 = COLORS.accent,
        TextSize = 16,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, combatScroll)

    -- Auto Parry toggle
    self:_createToggle(combatScroll, "Auto Parry", "autoParryEnabled", function(on)
        UICore:notify("Auto Parry", on and "Ativado" or "Desativado", 2)
    end)

    -- Manual Spam toggle
    self:_createToggle(combatScroll, "Manual Spam (AP/TB)", "manualSpamEnabled", function(on)
        if State.ui.manualSpamBtn then
            State.ui.manualSpamBtn:setVisible(on)
        end
        UICore:notify("Manual Spam", on and "Ativado" or "Desativado", 2)
    end)

    -- Delay slider (-100 a 200 ms)
    self:_createSlider(combatScroll, "Delay (ms)", "delayMs", -100, 200, "ms")

    -- Range slider
    self:_createSlider(combatScroll, "Range", "parryRange", 5, 60, " studs")

    -- Sensitivity slider
    self:_createSlider(combatScroll, "Sensitivity", "sensitivity", 0, 100, "%")

    -- Legit Mode toggle
    self:_createToggle(combatScroll, "Legit Mode (humanizado)", "legitMode")

    -- Fast React toggle
    self:_createToggle(combatScroll, "Fast React Mode", "fastReactMode")

    -- Anti-Repeat toggle
    self:_createToggle(combatScroll, "Anti-Repeat Parry", "antiRepeatEnabled")

    -- ═══ ABA VISUALS ═══
    local visualScroll = tabContents["Visuals"]

    self:_create("TextLabel", {
        Size = UDim2.new(1, -20, 0, 24),
        BackgroundTransparency = 1,
        Text = "👁 VISUALS",
        TextColor3 = COLORS.accent,
        TextSize = 16,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, visualScroll)

    self:_createToggle(visualScroll, "Ball ESP", "ballESP")
    self:_createToggle(visualScroll, "Ball Highlight", "ballHighlight")
    self:_createToggle(visualScroll, "Show Trajectory", "showTrajectory")
    self:_createToggle(visualScroll, "Show Distance", "showDistance")
    self:_createToggle(visualScroll, "Show Speed", "showSpeed")
    self:_createToggle(visualScroll, "Player ESP", "playerESP")
    self:_createToggle(visualScroll, "Threat Indicator", "showThreatIndicator")

    -- ═══ ABA SETTINGS ═══
    local settingsScroll = tabContents["Settings"]

    self:_create("TextLabel", {
        Size = UDim2.new(1, -20, 0, 24),
        BackgroundTransparency = 1,
        Text = "⚙ SETTINGS",
        TextColor3 = COLORS.accent,
        TextSize = 16,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, settingsScroll)

    -- UI Scale slider
    self:_createSlider(settingsScroll, "UI Scale", "uiScale", 1, 3, "x")

    -- Notifications toggle
    self:_createToggle(settingsScroll, "Notifications", "notifications")

    -- Spam Frequency
    self:_createSlider(settingsScroll, "Spam Frequency", "spamFrequency", 10, 200, "ms")

    -- Keybind inputs
    self:_createInput(settingsScroll, "Menu Key", "keybindMenu", "RightShift")
    self:_createInput(settingsScroll, "Auto Parry Key", "keybindAutoParry", "F")
    self:_createInput(settingsScroll, "Manual Spam Key", "keybindManualSpam", "G")
    self:_createInput(settingsScroll, "ESP Key", "keybindESP", "H")
    self:_createInput(settingsScroll, "Legit Mode Key", "keybindLegitMode", "J")

    -- Botões de config
    local btnRow = Instance.new("Frame")
    btnRow.Size = UDim2.new(1, -20, 0, 32)
    btnRow.BackgroundTransparency = 1
    btnRow.Parent = settingsScroll

    local saveBtn = self:_create("TextButton", {
        Size = UDim2.new(0.3, -4, 1, 0),
        BackgroundColor3 = COLORS.green,
        Text = "Salvar",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 13,
        Font = Enum.Font.GothamBold,
    }, btnRow)

    local saveCorner = Instance.new("UICorner")
    saveCorner.CornerRadius = UDim.new(0, 6)
    saveCorner.Parent = saveBtn

    saveBtn.MouseButton1Click:Connect(function()
        if ConfigManager:save() then
            UICore:notify("Config", "Salvo com sucesso!", 2)
        else
            UICore:notify("Config", "Erro ao salvar.", 2)
        end
    end)

    local loadBtn = self:_create("TextButton", {
        Size = UDim2.new(0.3, -4, 1, 0),
        Position = UDim2.new(0.35, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(60, 120, 200),
        Text = "Carregar",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 13,
        Font = Enum.Font.GothamBold,
    }, btnRow)

    local loadCorner = Instance.new("UICorner")
    loadCorner.CornerRadius = UDim.new(0, 6)
    loadCorner.Parent = loadBtn

    loadBtn.MouseButton1Click:Connect(function()
        if ConfigManager:load() then
            UICore:notify("Config", "Carregado!", 2)
        else
            UICore:notify("Config", "Nenhum save encontrado.", 2)
        end
    end)

    local resetBtn = self:_create("TextButton", {
        Size = UDim2.new(0.3, -4, 1, 0),
        Position = UDim2.new(0.7, 0, 0, 0),
        BackgroundColor3 = COLORS.red,
        Text = "Reset",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 13,
        Font = Enum.Font.GothamBold,
    }, btnRow)

    local resetCorner = Instance.new("UICorner")
    resetCorner.CornerRadius = UDim.new(0, 6)
    resetCorner.Parent = resetBtn

    resetBtn.MouseButton1Click:Connect(function()
        ConfigManager:reset()
        UICore:notify("Config", "Restaurado para padrão.", 2)
    end)

    -- Botão flutuante para reabrir
    local floatingBtn = Instance.new("TextButton")
    floatingBtn.Name = "FloatingButton"
    floatingBtn.Size = UDim2.new(0, 50, 0, 50)
    floatingBtn.Position = UDim2.new(0, 20, 0.5, -25)
    floatingBtn.BackgroundColor3 = COLORS.accent
    floatingBtn.Text = "⚔"
    floatingBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    floatingBtn.TextSize = 22
    floatingBtn.Font = Enum.Font.GothamBold
    floatingBtn.Visible = false
    floatingBtn.ZIndex = 10
    floatingBtn.Parent = self.screenGui

    local fbCorner = Instance.new("UICorner")
    fbCorner.CornerRadius = UDim.new(1, 0)
    fbCorner.Parent = floatingBtn

    floatingBtn.MouseButton1Click:Connect(function()
        main.Visible = not main.Visible
        if main.Visible then
            floatingBtn.Visible = false
        end
    end)

    State.ui.floatingBtn = floatingBtn
    State.ui.mainWindow = main

    -- Indicador de ameaça
    local threatIndicator = Instance.new("Frame")
    threatIndicator.Name = "ThreatIndicator"
    threatIndicator.Size = UDim2.new(0, 120, 0, 24)
    threatIndicator.Position = UDim2.new(0.5, -60, 0, 10)
    threatIndicator.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
    threatIndicator.BorderSizePixel = 0
    threatIndicator.Visible = false
    threatIndicator.ZIndex = 100
    threatIndicator.Parent = self.screenGui

    local tiCorner = Instance.new("UICorner")
    tiCorner.CornerRadius = UDim.new(0, 6)
    tiCorner.Parent = threatIndicator

    local tiLabel = Instance.new("TextLabel")
    tiLabel.Size = UDim2.new(1, 0, 1, 0)
    tiLabel.BackgroundTransparency = 1
    tiLabel.Text = "⚠ THREAT DETECTED"
    tiLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    tiLabel.TextSize = 11
    tiLabel.Font = Enum.Font.GothamBold
    tiLabel.Parent = threatIndicator

    State.ui.threatIndicator = threatIndicator

    -- FPS/Ping display
    local statsFrame = Instance.new("Frame")
    statsFrame.Name = "Stats"
    statsFrame.Size = UDim2.new(0, 160, 0, 22)
    statsFrame.Position = UDim2.new(1, -170, 1, -30)
    statsFrame.BackgroundColor3 = COLORS.panel
    statsFrame.BackgroundTransparency = 0.4
    statsFrame.BorderSizePixel = 0
    statsFrame.ZIndex = 5
    statsFrame.Parent = self.screenGui

    local statsCorner = Instance.new("UICorner")
    statsCorner.CornerRadius = UDim.new(0, 6)
    statsCorner.Parent = statsFrame

    local statsLabel = Instance.new("TextLabel")
    statsLabel.Size = UDim2.new(1, 0, 1, 0)
    statsLabel.BackgroundTransparency = 1
    statsLabel.Text = "FPS: -- | Ping: -- | AP: OFF"
    statsLabel.TextColor3 = COLORS.textDim
    statsLabel.TextSize = 11
    statsLabel.Font = Enum.Font.Gotham
    statsLabel.Parent = statsFrame

    State.ui.statsLabel = statsLabel

    -- Inicializar Manual Spam
    State.ui.manualSpamBtn = ManualSpam.new()
    State.ui.manualSpamBtn:create(self.screenGui)

    return self
end

function UICore:startStatsLoop()
    local frameCount = 0
    local lastTime = tick()

    RunService.RenderStepped:Connect(function()
        frameCount = frameCount + 1
        local now = tick()
        if now - lastTime >= 1 then
            State.fps = frameCount
            frameCount = 0
            lastTime = now
        end
    end)

    -- Atualizar stats label
    task.spawn(function()
        while task.wait(0.5) do
            pcall(function()
                local ping = LocalPlayer:GetNetworkPing() * 1000
                State.ping = ping
                if State.ui.statsLabel then
                    local apStatus = ConfigManager:get("autoParryEnabled") and "ON" or "OFF"
                    local msStatus = ConfigManager:get("manualSpamEnabled") and "ON" or "OFF"
                    State.ui.statsLabel.Text = string.format(
                        "FPS: %d | Ping: %.0fms | AP: %s | MS: %s",
                        State.fps, State.ping, apStatus, msStatus
                    )
                end
            end)
        end
    end)
end

-- ============================================================
-- 11. KEYBIND MANAGER
-- ============================================================
local KeybindManager = {}
KeybindManager.__index = KeybindManager

function KeybindManager.new()
    local self = setmetatable({}, KeybindManager)
    self._conn = nil
    return self
end

function KeybindManager:start()
    self._conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        local keyName = input.KeyCode.Name

        -- Menu
        if keyName == ConfigManager:get("keybindMenu") then
            if State.ui.mainWindow then
                local visible = State.ui.mainWindow.Visible
                State.ui.mainWindow.Visible = not visible
                if State.ui.floatingBtn then
                    State.ui.floatingBtn.Visible = visible
                end
            end
            return
        end

        -- Auto Parry
        if keyName == ConfigManager:get("keybindAutoParry") then
            local newState = not ConfigManager:get("autoParryEnabled")
            ConfigManager:set("autoParryEnabled", newState)
            UICore:notify("Auto Parry", newState and "Ativado" or "Desativado", 2)
            return
        end

        -- Manual Spam
        if keyName == ConfigManager:get("keybindManualSpam") then
            local newState = not ConfigManager:get("manualSpamEnabled")
            ConfigManager:set("manualSpamEnabled", newState)
            if State.ui.manualSpamBtn then
                State.ui.manualSpamBtn:setVisible(newState)
            end
            UICore:notify("Manual Spam", newState and "Ativado" or "Desativado", 2)
            return
        end

        -- ESP
        if keyName == ConfigManager:get("keybindESP") then
            local newState = not ConfigManager:get("ballESP")
            ConfigManager:set("ballESP", newState)
            ConfigManager:set("ballHighlight", newState)
            UICore:notify("Visuals", newState and "ESP Ativado" or "ESP Desativado", 2)
            return
        end

        -- Legit Mode
        if keyName == ConfigManager:get("keybindLegitMode") then
            local newState = not ConfigManager:get("legitMode")
            ConfigManager:set("legitMode", newState)
            UICore:notify("Legit Mode", newState and "Ativado" or "Desativado", 2)
            return
        end
    end)
end

function KeybindManager:stop()
    if self._conn then
        self._conn:Disconnect()
        self._conn = nil
    end
end

-- ============================================================
-- 12. INICIALIZAÇÃO E LOOP PRINCIPAL
-- ============================================================
local function onCharacterAdded(character)
    local hrp = character:WaitForChild("HumanoidRootPart", 10)
    if hrp then
        State.localHRP = hrp
    end
end

local function onCharacterRemoving()
    State.localHRP = nil
end

-- Inicializar sistemas
local config = ConfigManager.new()
local ballTracker = BallTracker.new()
local parryEngine = ParryEngine.new()
local visuals = Visuals.new()
local ui = UICore.new()
local keybinds = KeybindManager.new()

-- Tornar acessível globalmente (para módulos)
ConfigManager = config
BallTracker = ballTracker
ParryEngine = parryEngine
Visuals = visuals
UICore = ui

-- Carregar config salva
config:load()

-- Construir UI
ui:build()
ui:startStatsLoop()

-- Iniciar rastreamento da bola
ballTracker:start()

-- Iniciar visualizações
visuals:start()

-- Iniciar keybinds
keybinds:start()

-- Configurar personagem
if LocalPlayer.Character then
    onCharacterAdded(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
LocalPlayer.CharacterRemoving:Connect(onCharacterRemoving)

-- Loop principal do Parry Engine
State.signals:Connect(RunService.PreSimulation, function()
    pcall(function()
        ParryEngine:update()
    end)
end)

-- Manual Spam loop
parryEngine:startManualSpam()

-- Notificação inicial
task.wait(1)
ui:notify("Blade Ball Suite", "Carregado com sucesso! Pressione RightShift para abrir.", 4)

-- Tratamento de erros global
local function safeCall(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            warn("[BladeBallSuite] Erro: " .. tostring(err))
        end
    end
end

print("[BladeBallSuite] Script inicializado com sucesso.")
