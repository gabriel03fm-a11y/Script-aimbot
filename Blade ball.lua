--[[
    AIM ASSIST SUITE — Roblox
    Autor: (você)
    Uso: própria experiência / testes autorizados
    Coloque em: StarterPlayer > StarterPlayerScripts
--]]

--=========================================================
-- SERVIÇOS
--=========================================================
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera
local Mouse       = LocalPlayer:GetMouse()

--=========================================================
-- CONFIG (estado global, salvo em memória de sessão)
--=========================================================
local Config = {
    -- UI
    uiOpen = true,

    -- Aimbot
    aimEnabled        = false,
    aimPart           = "Head",       -- "Head" | "Torso" | "Closest"
    aimFov            = 120,
    aimSmoothing      = 0.25,         -- 0 = instantâneo, 1 = lento
    aimMaxDistance    = 500,
    aimIgnoreDead     = true,
    aimTeamCheck      = true,
    aimPriorityCenter = true,

    -- FOV visual
    fovCircleEnabled  = true,
    fovCircleTransp   = 0.6,
    fovCircleThick    = 2,
    fovCircleColor    = Color3.fromRGB(0, 170, 255),

    -- ESP
    espEnabled        = true,
    espName           = true,
    espDistance       = true,
    espBox            = true,
    espHealthBar      = true,
    espHighlight      = false,
    espTeamCheck      = true,
    espAllyColor      = Color3.fromRGB(0, 255, 120),
    espEnemyColor     = Color3.fromRGB(255, 60, 60),

    -- Kill Aura (apenas NPCs)
    kaEnabled         = false,
    kaRadius          = 25,
    kaCooldown        = 0.6,
    kaIgnoreDead      = true,
    kaRequireLOS      = true,
    kaTool            = nil,          -- ferramenta usada para atacar
}

-- Guarda cópia para Reset
local Defaults = {}
for k, v in pairs(Config) do Defaults[k] = v end

--=========================================================
-- UTILS
--=========================================================
local Utils = {}

function Utils.isAlive(character)
    if not character then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

function Utils.getRoot(character)
    return character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso"))
end

function Utils.isSameTeam(player)
    if not Config.aimTeamCheck and not Config.espTeamCheck then return false end
    if not player or not player.Team then return false end
    return player.Team == LocalPlayer.Team
end

function Utils.worldToScreen(pos)
    local sp, onScreen = Camera:WorldToViewportPoint(pos)
    return Vector2.new(sp.X, sp.Y), onScreen, sp.Z
end

function Utils.isNPC(model)
    -- Um NPC não tem Player associado
    if not model or not model:IsA("Model") then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    return Players:GetPlayerFromCharacter(model) == nil
end

function Utils.hasLineOfSight(from, to, ignoreList)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignoreList or {LocalPlayer.Character}
    local result = Workspace:Raycast(from, to - from, params)
    return result == nil
end

--=========================================================
-- UI (criada programaticamente, sem dependências externas)
--=========================================================
local UI = {}
UI.__index = UI

local function new(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props or {}) do obj[k] = v end
    obj.Parent = parent
    return obj
end

function UI.create()
    local gui = new("ScreenGui", {
        Name = "AimAssistUI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, LocalPlayer:WaitForChild("PlayerGui"))

    -- Botão flutuante (abrir/fechar)
    local toggleBtn = new("TextButton", {
        Name = "ToggleBtn",
        Size = UDim2.fromOffset(56, 56),
        Position = UDim2.new(0, 20, 0.5, -28),
        BackgroundColor3 = Color3.fromRGB(25, 25, 32),
        Text = "⚙",
        TextSize = 26,
        TextColor3 = Color3.fromRGB(0, 200, 255),
        Font = Enum.Font.GothamBold,
        AutoButtonColor = true,
        ZIndex = 10,
    }, gui)
    new("UICorner", {CornerRadius = UDim.new(1, 0)}, toggleBtn)
    new("UIStroke", {Color = Color3.fromRGB(0, 170, 255), Thickness = 1.5}, toggleBtn)

    -- Painel principal
    local panel = new("Frame", {
        Name = "Panel",
        Size = UDim2.fromOffset(320, 480),
        Position = UDim2.new(0, 90, 0.5, -240),
        BackgroundColor3 = Color3.fromRGB(18, 18, 24),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 5,
    }, gui)
    new("UICorner", {CornerRadius = UDim.new(0, 12)}, panel)
    new("UIStroke", {Color = Color3.fromRGB(0, 170, 255), Thickness = 1}, panel)

    -- Título
    local title = new("TextLabel", {
        Size = UDim2.new(1, -20, 0, 34),
        Position = UDim2.new(0, 10, 0, 8),
        BackgroundTransparency = 1,
        Text = "  AIM ASSIST SUITE",
        TextColor3 = Color3.fromRGB(0, 200, 255),
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, panel)

    -- Área rolável
    local scroll = new("ScrollingFrame", {
        Size = UDim2.new(1, -16, 1, -52),
        Position = UDim2.new(0, 8, 0, 46),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Color3.fromRGB(0, 170, 255),
    }, panel)
    new("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, scroll)

    local ui = setmetatable({
        gui = gui, panel = panel, scroll = scroll, toggleBtn = toggleBtn,
        isOpen = true, widgets = {},
    }, UI)

    -- Responsividade
    local function applyResponsive()
        local vp = Camera.ViewportSize
        if vp.X < 600 then
            panel.Size = UDim2.new(0.9, 0, 0.85, 0)
            panel.Position = UDim2.new(0.05, 0, 0.075, 0)
        else
            panel.Size = UDim2.fromOffset(320, 480)
            panel.Position = UDim2.new(0, 90, 0.5, -240)
        end
    end
    applyResponsive()
    Camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsive)

    -- Animação abrir/fechar
    ui:setOpen(true)

    toggleBtn.MouseButton1Click:Connect(function()
        ui:setOpen(not ui.isOpen)
    end)

    return ui
end

function UI:setOpen(open)
    self.isOpen = open
    local target
    if open then
        self.panel.Visible = true
        target = {Size = self.panel.Size, BackgroundTransparency = 0}
        self.panel.Size = UDim2.fromOffset(0, 0)
        self.panel.BackgroundTransparency = 1
        TweenService:Create(self.panel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = self.panel:GetAttribute("OpenSize") or self.panel.Size,
        })
    end

    -- Guardamos o tamanho original
    if not self.panel:GetAttribute("OpenSize") then
        self.panel:SetAttribute("OpenSize", self.panel.Size)
    end
    local openSize = self.panel:GetAttribute("OpenSize")

    self.panel.Visible = true
    if open then
        self.panel.Size = UDim2.fromOffset(0, 0)
        TweenService:Create(self.panel, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = openSize,
        }):Play()
    else
        local tw = TweenService:Create(self.panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Size = UDim2.fromOffset(0, 0),
        })
        tw:Play()
        tw.Completed:Connect(function() self.panel.Visible = false end)
    end
end

-- Widgets
function UI:section(text)
    local lbl = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = Color3.fromRGB(30, 30, 40),
        Text = "  " .. text,
        TextColor3 = Color3.fromRGB(0, 200, 255),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, self.scroll)
    new("UICorner", {CornerRadius = UDim.new(0, 6)}, lbl)
    return lbl
end

function UI:toggle(text, key, callback)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = Color3.fromRGB(28, 28, 36),
        BorderSizePixel = 0,
    }, self.scroll)
    new("UICorner", {CornerRadius = UDim.new(0, 6)}, row)

    new("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Color3.fromRGB(230, 230, 230),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local btn = new("TextButton", {
        Size = UDim2.fromOffset(46, 20),
        Position = UDim2.new(1, -56, 0.5, -10),
        BackgroundColor3 = Config[key] and Color3.fromRGB(0, 170, 255) or Color3.fromRGB(60, 60, 70),
        Text = "",
        AutoButtonColor = false,
    }, row)
    new("UICorner", {CornerRadius = UDim.new(1, 0)}, btn)

    local knob = new("Frame", {
        Size = UDim2.fromOffset(16, 16),
        Position = Config[key] and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
    }, btn)
    new("UICorner", {CornerRadius = UDim.new(1, 0)}, knob)

    local function render(state)
        TweenService:Create(btn, TweenInfo.new(0.15), {
            BackgroundColor3 = state and Color3.fromRGB(0, 170, 255) or Color3.fromRGB(60, 60, 70)
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        }):Play()
    end
    render(Config[key])

    btn.MouseButton1Click:Connect(function()
        Config[key] = not Config[key]
        render(Config[key])
        if callback then callback(Config[key]) end
    end)
end

function UI:slider(text, key, min, max, callback)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = Color3.fromRGB(28, 28, 36),
        BorderSizePixel = 0,
    }, self.scroll)
    new("UICorner", {CornerRadius = UDim.new(0, 6)}, row)

    local lbl = new("TextLabel", {
        Size = UDim2.new(1, -20, 0, 18),
        Position = UDim2.new(0, 10, 0, 4),
        BackgroundTransparency = 1,
        Text = text .. ": " .. tostring(Config[key]),
        TextColor3 = Color3.fromRGB(230, 230, 230),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local bar = new("Frame", {
        Size = UDim2.new(1, -20, 0, 8),
        Position = UDim2.new(0, 10, 0, 28),
        BackgroundColor3 = Color3.fromRGB(50, 50, 60),
        BorderSizePixel = 0,
    }, row)
    new("UICorner", {CornerRadius = UDim.new(1, 0)}, bar)

    local fill = new("Frame", {
        Size = UDim2.new((Config[key] - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(0, 170, 255),
        BorderSizePixel = 0,
    }, bar)
    new("UICorner", {CornerRadius = UDim.new(1, 0)}, fill)

    local dragging = false
    local function update(input)
        local rel = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local val = min + (max - min) * rel
        Config[key] = val
        fill.Size = UDim2.new(rel, 0, 1, 0)
        lbl.Text = text .. ": " .. string.format("%.2f", val)
        if callback then callback(val) end
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            update(input)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

function UI:dropdown(text, key, options, callback)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = Color3.fromRGB(28, 28, 36),
        BorderSizePixel = 0,
    }, self.scroll)
    new("UICorner", {CornerRadius = UDim.new(0, 6)}, row)

    new("TextLabel", {
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Color3.fromRGB(230, 230, 230),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local idx = table.find(options, Config[key]) or 1
    local btn = new("TextButton", {
        Size = UDim2.new(0.45, 0, 0, 22),
        Position = UDim2.new(0.5, 0, 0.5, -11),
        BackgroundColor3 = Color3.fromRGB(40, 40, 52),
        Text = options[idx],
        TextColor3 = Color3.fromRGB(0, 200, 255),
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
    }, row)
    new("UICorner", {CornerRadius = UDim.new(0, 6)}, btn)

    btn.MouseButton1Click:Connect(function()
        local cur = table.find(options, Config[key]) or 1
        cur = cur % #options + 1
        Config[key] = options[cur]
        btn.Text = options[cur]
        if callback then callback(options[cur]) end
    end)
end

function UI:button(text, callback)
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Color3.fromRGB(0, 120, 200),
        Text = text,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
    }, self.scroll)
    new("UICorner", {CornerRadius = UDim.new(0, 6)}, btn)
    btn.MouseButton1Click:Connect(callback)
end

--=========================================================
-- AIM ASSIST
--=========================================================
local Aim = {}

local function getTargets()
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        if Config.aimTeamCheck and Utils.isSameTeam(plr) then continue end
        local char = plr.Character
        if not char then continue end
        if Config.aimIgnoreDead and not Utils.isAlive(char) then continue end
        local root = Utils.getRoot(char)
        if not root then continue end
        local dist = (root.Position - Camera.CFrame.Position).Magnitude
        if dist > Config.aimMaxDistance then continue end

        local aimPart
        if Config.aimPart == "Head" then
            aimPart = char:FindFirstChild("Head")
        elseif Config.aimPart == "Torso" then
            aimPart = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
        else -- Closest
            aimPart = root
        end
        if not aimPart then continue end

        local screenPos, onScreen = Utils.worldToScreen(aimPart.Position)
        if not onScreen then continue end
        local center = Camera.ViewportSize / 2
        local offCenter = (screenPos - center).Magnitude
        if offCenter > Config.aimFov then continue end

        table.insert(list, {player = plr, character = char, part = aimPart, screenPos = screenPos, offCenter = offCenter})
    end
    return list
end

local function pickTarget()
    local targets = getTargets()
    if #targets == 0 then return nil end

    if Config.aimPriorityCenter then
        table.sort(targets, function(a, b) return a.offCenter < b.offCenter end)
    else
        table.sort(targets, function(a, b)
            return (a.part.Position - Camera.CFrame.Position).Magnitude < (b.part.Position - Camera.CFrame.Position).Magnitude
        end)
    end
    return targets[1]
end

function Aim.step(dt)
    if not Config.aimEnabled then return end
    -- Só mira quando o botão direito estiver pressionado (PC) ou toque contínuo
    local active = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    if not active then
        -- No mobile: manter mira enquanto tocar na tela à direita
        if UserInputService.TouchEnabled then
            active = #UserInputService:GetKeysPressed() > 0 -- fallback
        end
    end
    -- Se quiser mira sempre ativa, descomente:
    -- active = true
    if not active then return end

    local target = pickTarget()
    if not target then return end

    local from = Camera.CFrame.Position
    local to   = target.part.Position
    local desired = CFrame.new(from, to)
    local alpha = 1 - math.clamp(Config.aimSmoothing, 0, 0.95)
    Camera.CFrame = Camera.CFrame:Lerp(desired, alpha)
end

--=========================================================
-- FOV CIRCLE (desenhado com Frame)
--=========================================================
local FovCircle = {}

function FovCircle.create(parent)
    local circle = new("Frame", {
        Name = "FovCircle",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(200, 200),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, parent)
    new("UICorner", {CornerRadius = UDim.new(1, 0)}, circle)
    local stroke = new("UIStroke", {
        Thickness = Config.fovCircleThick,
        Color = Config.fovCircleColor,
        Transparency = Config.fovCircleTransp,
    }, circle)
    return {frame = circle, stroke = stroke}
end

function FovCircle.update(circle)
    if not circle then return end
    local size = Config.aimFov * 2
    circle.frame.Size = UDim2.fromOffset(size, size)
    circle.frame.Visible = Config.fovCircleEnabled
    circle.stroke.Thickness = Config.fovCircleThick
    circle.stroke.Transparency = Config.fovCircleTransp
end

--=========================================================
-- ESP
--=========================================================
local ESP = {cache = {}}

local function clearESP(plr)
    local data = ESP.cache[plr]
    if not data then return end
    for _, obj in pairs(data) do
        if obj and obj.Destroy then obj:Destroy() end
    end
    ESP.cache[plr] = nil
end

function ESP.update()
    -- limpar jogadores que saíram ou ESP desligado
    for plr, _ in pairs(ESP.cache) do
        if not plr.Parent or not Config.espEnabled then
            clearESP(plr)
        end
    end
    if not Config.espEnabled then return end

    local myPos = Camera.CFrame.Position
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        local char = plr.Character
        if not char then clearESP(plr); continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local root = Utils.getRoot(char)
        if not hum or not root then clearESP(plr); continue end

        local isAlly = plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team
        if Config.espTeamCheck and isAlly then
            -- esconder aliados
            clearESP(plr)
            continue
        end

        local color = isAlly and Config.espAllyColor or Config.espEnemyColor
        local data = ESP.cache[plr]
        if not data then
            local gui = new("BillboardGui", {
                Name = "ESP_" .. plr.Name,
                Size = UDim2.fromOffset(200, 60),
                AlwaysOnTop = true,
                Adornee = root,
            }, root)
            local box = new("Frame", {
                Name = "Box",
                BackgroundTransparency = 1,
                Size = UDim2.fromScale(1, 1),
                Visible = false,
            }, gui)
            new("UIStroke", {Name = "Stroke", Thickness = 1.5, Color = color}, box)

            local name = new("TextLabel", {
                Name = "Name",
                Size = UDim2.new(1, 0, 0, 14),
                Position = UDim2.new(0, 0, 0, -16),
                BackgroundTransparency = 1,
                Text = plr.Name,
                TextColor3 = color,
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextStrokeTransparency = 0.5,
            }, gui)

            local dist = new("TextLabel", {
                Name = "Dist",
                Size = UDim2.new(1, 0, 0, 12),
                Position = UDim2.new(0, 0, 1, 2),
                BackgroundTransparency = 1,
                Text = "0m",
                TextColor3 = Color3.fromRGB(220, 220, 220),
                Font = Enum.Font.Gotham,
                TextSize = 11,
                TextStrokeTransparency = 0.5,
            }, gui)

            local hpBg = new("Frame", {
                Name = "HpBg",
                Size = UDim2.new(0, 3, 1, 0),
                Position = UDim2.new(-0.02, 0, 0, 0),
                BackgroundColor3 = Color3.fromRGB(30, 30, 30),
                BorderSizePixel = 0,
                Visible = false,
            }, box)
            local hpFill = new("Frame", {
                Name = "HpFill",
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundColor3 = Color3.fromRGB(0, 255, 90),
                BorderSizePixel = 0,
            }, hpBg)

            local highlight = new("Highlight", {
                Name = "Highlight",
                FillColor = color,
                OutlineColor = color,
                FillTransparency = 0.7,
                OutlineTransparency = 0.4,
                Enabled = false,
                Adornee = char,
            }, char)

            data = {gui = gui, box = box, stroke = box:FindFirstChild("Stroke"), name = name, dist = dist,
                    hpBg = hpBg, hpFill = hpFill, highlight = highlight}
            ESP.cache[plr] = data
        end

        -- Atualizações
        data.name.Visible    = Config.espName
        data.dist.Visible    = Config.espDistance
        data.box.Visible     = Config.espBox
        data.hpBg.Visible    = Config.espHealthBar
        data.highlight.Enabled = Config.espHighlight
        data.stroke.Color    = color
        data.name.TextColor3 = color

        local distance = (root.Position - myPos).Magnitude
        data.dist.Text = string.format("%.0fm", distance)

        local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
        data.hpFill.Size = UDim2.new(1, 0, hp, 0)
        data.hpFill.BackgroundColor3 = Color3.fromRGB(255 * (1 - hp), 255 * hp, 0)

        -- Caixa dinâmica baseada em distância
        if Config.espBox then
            local top, onScreenTop = Utils.worldToScreen((root.CFrame * CFrame.new(0, 2.5, 0)).Position)
            local bottom       = Utils.worldToScreen((root.CFrame * CFrame.new(0, -2.5, 0)).Position)
            if onScreenTop then
                local height = math.abs(bottom.Y - top.Y)
                local width  = height * 0.55
                data.box.Size = UDim2.fromOffset(width, height)
                data.box.Position = UDim2.new(0.5, -width/2, 0.5, -height/2)
            end
        end
    end
end

--=========================================================
-- KILL AURA (apenas NPCs)
--=========================================================
local KillAura = {lastAttack = 0}

function KillAura.step()
    if not Config.kaEnabled then return end
    local now = tick()
    if now - KillAura.lastAttack < Config.kaCooldown then return end

    local char = LocalPlayer.Character
    if not char then return end
    local myRoot = Utils.getRoot(char)
    if not myRoot then return end

    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return end

    local bestTarget, bestDist
    for _, model in ipairs(Workspace:GetChildren()) do
        if not Utils.isNPC(model) then continue end
        if Config.kaIgnoreDead and not Utils.isAlive(model) then continue end
        local root = Utils.getRoot(model)
        if not root then continue end
        local dist = (root.Position - myRoot.Position).Magnitude
        if dist <= Config.kaRadius and (not bestDist or dist < bestDist) then
            if Config.kaRequireLOS then
                if not Utils.hasLineOfSight(myRoot.Position, root.Position, {char, model}) then
                    continue
                end
            end
            bestTarget, bestDist = model, dist
        end
    end

    if bestTarget then
        local hum = bestTarget:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            tool:Activate()
            KillAura.lastAttack = now
        end
    end
end

--=========================================================
-- BOOTSTRAP
--=========================================================
local ui = UI.create()
local fovCircle = FovCircle.create(ui.gui)

ui:section("AIMBOT")
ui:toggle("Ativar Aimbot", "aimEnabled")
ui:dropdown("Parte do alvo", "aimPart", {"Head", "Torso", "Closest"})
ui:slider("FOV", "aimFov", 10, 800)
ui:slider("Suavização", "aimSmoothing", 0, 0.95)
ui:slider("Distância Máx", "aimMaxDistance", 10, 2000)
ui:toggle("Ignorar mortos", "aimIgnoreDead")
ui:toggle("Team Check (Aim)", "aimTeamCheck")
ui:toggle("Priorizar centro", "aimPriorityCenter")

ui:section("FOV VISUAL")
ui:toggle("Mostrar círculo", "fovCircleEnabled")
ui:slider("Transparência", "fovCircleTransp", 0, 1)
ui:slider("Espessura", "fovCircleThick", 1, 8)

ui:section("ESP")
ui:toggle("Ativar ESP", "espEnabled")
ui:toggle("Nome", "espName")
ui:toggle("Distância", "espDistance")
ui:toggle("Caixa", "espBox")
ui:toggle("Barra de vida", "espHealthBar")
ui:toggle("Highlight", "espHighlight")
ui:toggle("Team Check (ESP)", "espTeamCheck")

ui:section("KILL AURA (NPCs)")
ui:toggle("Ativar Kill Aura", "kaEnabled")
ui:slider("Raio", "kaRadius", 5, 100)
ui:slider("Cooldown", "kaCooldown", 0.1, 3)
ui:toggle("Ignorar NPCs mortos", "kaIgnoreDead")
ui:toggle("Exigir linha de visão", "kaRequireLOS")

ui:section("SISTEMA")
ui:button("Resetar Configurações", function()
    for k, v in pairs(Defaults) do Config[k] = v end
    -- reaplica visuais
    FovCircle.update(fovCircle)
end)

-- Atalhos de teclado (PC)
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        ui:setOpen(not ui.isOpen)
    elseif input.KeyCode == Enum.KeyCode.Insert then
        Config.aimEnabled = not Config.aimEnabled
    elseif input.KeyCode == Enum.KeyCode.Delete then
        Config.espEnabled = not Config.espEnabled
    end
end)

-- Loops
RunService.RenderStepped:Connect(function(dt)
    Aim.step(dt)
    FovCircle.update(fovCircle)
    ESP.update()
end)

task.spawn(function()
    while task.wait(0.05) do
        KillAura.step()
    end
end)

-- Mantém FOV sincronizado com o slider
RunService.Heartbeat:Connect(function()
    FovCircle.update(fovCircle)
end)
