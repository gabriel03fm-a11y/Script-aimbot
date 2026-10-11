--!strict
--=====================================================================
-- AIM ASSIST + ESP + KILL AURA (NPCs) — Script único
-- v2: FAB arrastável, UI compacta, LOS no aim, FOV funcional
--=====================================================================

--=====================================================================
-- 0) SERVIÇOS
--=====================================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

--=====================================================================
-- 1) CONFIG
--=====================================================================
local Config = {}
Config.Defaults = {
    -- AIM
    AimEnabled     = false,
    AimPart        = "Head",
    AimSmooth      = 0.15,
    AimMaxDistance = 500,
    AimIgnoreDead  = true,
    AimTeamCheck   = true,
    AimRequireLOS  = true,   -- NOVO: só mira se houver linha de visão

    -- FOV
    FovRadius       = 120,
    FovVisible      = true,
    FovTransparency = 0.6,
    FovThickness    = 2,

    -- ESP
    EspEnabled     = false,
    EspName        = true,
    EspDistance    = true,
    EspBox         = true,
    EspHealth      = true,
    EspHighlight   = true,
    EspTeamCheck   = true,
    EspMaxDistance = 800,
    ColorEnemy     = Color3.fromRGB(255, 70, 70),
    ColorAlly      = Color3.fromRGB(70, 200, 255),

    -- AURA
    AuraEnabled    = false,
    AuraRadius     = 12,
    AuraCooldown   = 0.6,
    AuraRequireLOS = true,
    AuraIgnoreDead = true,
}
Config.Data = table.clone(Config.Defaults)
function Config.Get(k) return Config.Data[k] end
function Config.Set(k, v) Config.Data[k] = v end
function Config.Reset()
    for k, v in pairs(Config.Defaults) do Config.Data[k] = v end
end

--=====================================================================
-- 2) UTILS
--=====================================================================
local Utils = {}

function Utils.GetLocalTeam() return LocalPlayer.Team end

function Utils.GetTargets(includeNPCs)
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                list[#list+1] = {
                    kind="Player", ref=plr, model=plr.Character,
                    hum=hum, team=plr.Team, name=plr.DisplayName,
                }
            end
        end
    end
    if includeNPCs then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and obj:GetAttribute("CombatTarget") == true then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                if hum then
                    list[#list+1] = {
                        kind="NPC", ref=obj, model=obj,
                        hum=hum, team=nil, name=obj.Name,
                    }
                end
            end
        end
    end
    return list
end

function Utils.IsAlly(t, teamCheck)
    if not teamCheck then return false end
    if t.kind ~= "Player" then return false end
    local myTeam = Utils.GetLocalTeam()
    return myTeam ~= nil and t.team == myTeam
end

function Utils.IsDead(t) return not t.hum or t.hum.Health <= 0 end

function Utils.ResolvePart(t, mode)
    local char = t.model
    if not char then return nil end
    if mode == "Head" then
        local h = char:FindFirstChild("Head")
        return h and h.Position or nil
    elseif mode == "Torso" then
        local tr = char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Torso")
            or char:FindFirstChild("HumanoidRootPart")
        return tr and tr.Position or nil
    else
        local mouse = LocalPlayer:GetMouse()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = { char }
        local origin = Camera.CFrame.Position
        local dir = mouse.Hit.Position - origin
        local res = workspace:Raycast(origin, dir, params)
        if res and res.Instance then return res.Instance.Position end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        return hrp and hrp.Position or nil
    end
end

function Utils.WorldToScreen(worldPos)
    local sp, onScreen = Camera:WorldToViewportPoint(worldPos)
    return Vector2.new(sp.X, sp.Y), onScreen
end

-- NOVO: verifica LOS entre câmera e ponto-alvo
function Utils.HasLOS(targetPos, targetModel)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = { LocalPlayer.Character }
    if targetModel then table.insert(ignore, targetModel) end
    params.FilterDescendantsInstances = ignore
    local origin = Camera.CFrame.Position
    local res = workspace:Raycast(origin, targetPos - origin, params)
    return res == nil
end

--=====================================================================
-- 3) UI (compacta 260x380, FAB arrastável)
--=====================================================================
local UI = {}

local COLORS = {
    bg      = Color3.fromRGB(22, 24, 30),
    panel   = Color3.fromRGB(30, 33, 41),
    accent  = Color3.fromRGB(0, 170, 255),
    danger  = Color3.fromRGB(255, 80, 80),
    text    = Color3.fromRGB(230, 230, 230),
    subtext = Color3.fromRGB(150, 155, 165),
}

local function corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end
local function stroke(p, col, th)
    local s = Instance.new("UIStroke"); s.Color = col or COLORS.panel
    s.Thickness = th or 1; s.Parent = p; return s
end

-- ---------- Componentes compactos ----------
local function makeToggle(parent, label, key)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -12, 0, 28); row.BackgroundTransparency = 1; row.Parent = parent

    local txt = Instance.new("TextLabel")
    txt.BackgroundTransparency = 1; txt.Size = UDim2.new(1, -50, 1, 0)
    txt.Font = Enum.Font.GothamMedium; txt.TextSize = 12; txt.TextColor3 = COLORS.text
    txt.TextXAlignment = Enum.TextXAlignment.Left; txt.Text = label; txt.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 38, 0, 20); btn.Position = UDim2.new(1, -38, 0.5, -10)
    btn.BackgroundColor3 = Config.Get(key) and COLORS.accent or Color3.fromRGB(60,63,72)
    btn.Text = ""; btn.AutoButtonColor = false; btn.Parent = row
    corner(btn, 10)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16); knob.Position = UDim2.new(0, 2, 0.5, -8)
    knob.BackgroundColor3 = Color3.new(1,1,1); knob.Parent = btn
    corner(knob, 8)

    btn.MouseButton1Click:Connect(function()
        local v = not Config.Get(key); Config.Set(key, v)
        TweenService:Create(btn, TweenInfo.new(0.15),
            { BackgroundColor3 = v and COLORS.accent or Color3.fromRGB(60,63,72) }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15),
            { Position = v and UDim2.new(0, 20, 0.5, -8) or UDim2.new(0, 2, 0.5, -8) }):Play()
    end)
    return row
end

local function makeSlider(parent, label, key, minV, maxV, step, fmt)
    fmt = fmt or "%.2f"
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -12, 0, 36); holder.BackgroundTransparency = 1; holder.Parent = parent

    local txt = Instance.new("TextLabel")
    txt.BackgroundTransparency = 1; txt.Size = UDim2.new(1, 0, 0, 14)
    txt.Font = Enum.Font.GothamMedium; txt.TextSize = 12; txt.TextColor3 = COLORS.text
    txt.TextXAlignment = Enum.TextXAlignment.Left
    txt.Text = string.format(label .. ": " .. fmt, Config.Get(key)); txt.Parent = holder

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 5); bar.Position = UDim2.new(0, 0, 0, 22)
    bar.BackgroundColor3 = Color3.fromRGB(55,58,68); bar.BorderSizePixel = 0; bar.Parent = holder
    corner(bar, 3)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = COLORS.accent; fill.BorderSizePixel = 0; fill.Parent = bar
    corner(fill, 3)

    local function refresh()
        local v = Config.Get(key)
        local ratio = (v - minV) / (maxV - minV)
        fill.Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0)
        txt.Text = string.format(label .. ": " .. fmt, v)
    end
    refresh()

    local dragging = false
    local function apply(x)
        local ratio = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local v = minV + (maxV - minV) * ratio
        v = math.floor(v / step + 0.5) * step
        Config.Set(key, v); refresh()
    end
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; apply(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            apply(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    return holder
end

local function makeDropdown(parent, label, key, options)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -12, 0, 32); holder.BackgroundTransparency = 1; holder.Parent = parent

    local txt = Instance.new("TextLabel")
    txt.BackgroundTransparency = 1; txt.Size = UDim2.new(1, -110, 1, 0)
    txt.Font = Enum.Font.GothamMedium; txt.TextSize = 12; txt.TextColor3 = COLORS.text
    txt.TextXAlignment = Enum.TextXAlignment.Left; txt.Text = label; txt.Parent = holder

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 100, 0, 24); btn.Position = UDim2.new(1, -100, 0.5, -12)
    btn.BackgroundColor3 = Color3.fromRGB(45,48,58); btn.TextColor3 = COLORS.text
    btn.Font = Enum.Font.GothamMedium; btn.TextSize = 12
    btn.Text = Config.Get(key); btn.Parent = holder
    corner(btn, 6)

    btn.MouseButton1Click:Connect(function()
        local idx = table.find(options, Config.Get(key)) or 1
        idx = idx % #options + 1
        Config.Set(key, options[idx]); btn.Text = options[idx]
    end)
    return holder
end

-- ---------- Build ----------
function UI.Build()
    local gui = Instance.new("ScreenGui")
    gui.Name = "AimAssistUI"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    -- FAB (botão circular) — MENOR E ARRASTÁVEL
    local fab = Instance.new("TextButton")
    fab.Size = UDim2.new(0, 48, 0, 48)
    fab.Position = UDim2.new(0, 16, 0.5, -24)
    fab.BackgroundColor3 = COLORS.accent
    fab.Text = "🎯"; fab.TextSize = 20; fab.Font = Enum.Font.GothamBold
    fab.TextColor3 = Color3.new(1,1,1); fab.Parent = gui
    fab.AutoButtonColor = false
    corner(fab, 24); stroke(fab, COLORS.accent, 2)

    -- PANEL — MENOR (260 x 380)
    local PANEL_W, PANEL_H = 260, 380
    local panel = Instance.new("Frame")
    panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
    panel.Position = UDim2.new(0.5, -PANEL_W/2, 0.5, -PANEL_H/2)
    panel.BackgroundColor3 = COLORS.bg; panel.Visible = false
    panel.ClipsDescendants = true; panel.Parent = gui
    corner(panel, 12); stroke(panel, Color3.fromRGB(45,48,58))

    -- HEADER (arrastável)
    local header = Instance.new("TextButton")
    header.Size = UDim2.new(1, 0, 0, 34); header.BackgroundColor3 = COLORS.panel
    header.Text = "  ⚙️  Assist"; header.TextXAlignment = Enum.TextXAlignment.Left
    header.Font = Enum.Font.GothamBold; header.TextSize = 13
    header.TextColor3 = COLORS.text; header.Parent = panel
    corner(header, 12)

    -- Botão fechar dentro do header
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 22, 0, 22); closeBtn.Position = UDim2.new(1, -26, 0.5, -11)
    closeBtn.BackgroundColor3 = COLORS.danger; closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.new(1,1,1); closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 12; closeBtn.Parent = header
    corner(closeBtn, 11)

    -- TABS
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -12, 0, 26); tabBar.Position = UDim2.new(0, 6, 0, 40)
    tabBar.BackgroundTransparency = 1; tabBar.Parent = panel
    local tl = Instance.new("UIListLayout")
    tl.FillDirection = Enum.FillDirection.Horizontal
    tl.Padding = UDim.new(0, 4); tl.Parent = tabBar

    local pages, tabButtons = {}, {}
    local function addTab(name)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 48, 1, 0); b.BackgroundColor3 = COLORS.panel
        b.Font = Enum.Font.GothamMedium; b.TextSize = 11
        b.TextColor3 = COLORS.subtext; b.Text = name; b.Parent = tabBar
        corner(b, 6); tabButtons[name] = b

        local page = Instance.new("ScrollingFrame")
        page.Size = UDim2.new(1, -12, 1, -76)
        page.Position = UDim2.new(0, 6, 0, 70)
        page.BackgroundTransparency = 1; page.BorderSizePixel = 0
        page.ScrollBarThickness = 2
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Visible = false; page.Parent = panel
        local lay = Instance.new("UIListLayout")
        lay.SortOrder = Enum.SortOrder.LayoutOrder
        lay.Padding = UDim.new(0, 6); lay.Parent = page
        pages[name] = page
        return page
    end

    local pAim  = addTab("Aim")
    local pEsp  = addTab("ESP")
    local pFov  = addTab("FOV")
    local pAura = addTab("Aura")
    local pCfg  = addTab("Cfg")

    local function selectPage(n)
        for k, p in pairs(pages) do p.Visible = (k == n) end
        for k, b in pairs(tabButtons) do
            b.TextColor3 = (k == n) and COLORS.accent or COLORS.subtext
        end
    end
    for k, b in pairs(tabButtons) do
        b.MouseButton1Click:Connect(function() selectPage(k) end)
    end
    selectPage("Aim")

    -- Popula
    makeToggle(pAim, "Aim Assist", "AimEnabled")
    makeDropdown(pAim, "Parte", "AimPart", {"Head","Torso","Cursor"})
    makeSlider(pAim, "Suavização", "AimSmooth", 0.02, 1.0, 0.01)
    makeSlider(pAim, "Dist. Máx", "AimMaxDistance", 50, 2000, 10, "%.0f")
    makeToggle(pAim, "Ignorar Mortos", "AimIgnoreDead")
    makeToggle(pAim, "Team Check", "AimTeamCheck")
    makeToggle(pAim, "Exigir LOS", "AimRequireLOS")

    makeToggle(pEsp, "ESP", "EspEnabled")
    makeToggle(pEsp, "Nome", "EspName")
    makeToggle(pEsp, "Distância", "EspDistance")
    makeToggle(pEsp, "Caixa", "EspBox")
    makeToggle(pEsp, "Vida", "EspHealth")
    makeToggle(pEsp, "Highlight", "EspHighlight")
    makeToggle(pEsp, "Team Check", "EspTeamCheck")
    makeSlider(pEsp, "Dist. Máx ESP", "EspMaxDistance", 50, 3000, 50, "%.0f")

    makeSlider(pFov, "Raio FOV", "FovRadius", 20, 500, 5, "%.0f")
    makeToggle(pFov, "Círculo Visível", "FovVisible")
    makeSlider(pFov, "Transparência", "FovTransparency", 0, 1, 0.05)
    makeSlider(pFov, "Espessura", "FovThickness", 1, 6, 1, "%.0f")

    makeToggle(pAura, "Kill Aura (NPCs)", "AuraEnabled")
    makeSlider(pAura, "Raio", "AuraRadius", 4, 40, 1, "%.0f")
    makeSlider(pAura, "Cooldown", "AuraCooldown", 0.1, 3, 0.1)
    makeToggle(pAura, "Exigir LOS", "AuraRequireLOS")
    makeToggle(pAura, "Ignorar Mortos", "AuraIgnoreDead")

    local resetBtn = Instance.new("TextButton")
    resetBtn.Size = UDim2.new(1, -12, 0, 30); resetBtn.BackgroundColor3 = COLORS.danger
    resetBtn.Text = "Resetar"; resetBtn.Font = Enum.Font.GothamBold
    resetBtn.TextSize = 12; resetBtn.TextColor3 = Color3.new(1,1,1)
    resetBtn.Parent = pCfg
    corner(resetBtn, 6)
    resetBtn.MouseButton1Click:Connect(function()
        Config.Reset()
        gui:Destroy()
        UI.Build()
    end)

    -- ---------- Animação abrir/fechar ----------
    local open = false
    local function setOpen(v)
        open = v
        if open then
            panel.Visible = true
            panel.Size = UDim2.new(0, PANEL_W, 0, 0)
            TweenService:Create(panel,
                TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                { Size = UDim2.new(0, PANEL_W, 0, PANEL_H) }):Play()
        else
            local t = TweenService:Create(panel,
                TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                { Size = UDim2.new(0, PANEL_W, 0, 0) })
            t:Play()
            t.Completed:Connect(function() panel.Visible = false end)
        end
    end

    -- ---------- FAB: arrastar + clique ----------
    local fabDragging, fabStart, fabStartPos = false, nil, nil
    local fabMoved = false

    fab.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            fabDragging = true
            fabMoved = false
            fabStart = input.Position
            fabStartPos = fab.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if fabDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - fabStart
            if math.abs(d.X) > 4 or math.abs(d.Y) > 4 then
                fabMoved = true
            end
            fab.Position = UDim2.new(
                fabStartPos.X.Scale, fabStartPos.X.Offset + d.X,
                fabStartPos.Y.Scale, fabStartPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            if fabDragging and not fabMoved then
                setOpen(not open)
            end
            fabDragging = false
        end
    end)

    -- Botão fechar
    closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)

    -- Arrastar painel pelo header
    local dragging, dragStart, startPos = false, nil, nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = panel.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            panel.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    -- Atalho RightShift
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            setOpen(not open)
        end
    end)

    return gui, panel
end

--=====================================================================
-- 4) FOV (círculo que acompanha o centro da tela) — FUNCIONAL
--=====================================================================
local Fov = {}
function Fov.Start()
    local gui = Instance.new("ScreenGui")
    gui.Name = "AimFovGui"; gui.IgnoreGuiInset = true; gui.ResetOnSpawn = false
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local ring = Instance.new("Frame")
    ring.AnchorPoint = Vector2.new(0.5, 0.5)
    ring.Position = UDim2.fromScale(0.5, 0.5)
    ring.BackgroundTransparency = 1
    ring.Parent = gui

    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color = COLORS.accent
    s.Parent = ring

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0); c.Parent = ring

    RunService.RenderStepped:Connect(function()
        local r = Config.Get("FovRadius")
        -- Mostra o círculo sempre que o Aim Assist estiver ligado
        local visible = Config.Get("FovVisible") and Config.Get("AimEnabled")
        ring.Visible = visible
        if visible then
            ring.Size = UDim2.fromOffset(r * 2, r * 2)
            s.Transparency = Config.Get("FovTransparency")
            s.Thickness = Config.Get("FovThickness")
        end
    end)
end

--=====================================================================
-- 5) AIM (com LOS — não trava em quem está atrás de parede)
--=====================================================================
local Aim = {}
local AIM_HZ = 60
local aimAcc = 0

local function findBestAimTarget()
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)

    local best, bestDist = nil, math.huge
    local teamCheck  = Config.Get("AimTeamCheck")
    local ignoreDead = Config.Get("AimIgnoreDead")
    local maxDist    = Config.Get("AimMaxDistance")
    local fov        = Config.Get("FovRadius")
    local partMode   = Config.Get("AimPart")
    local requireLOS = Config.Get("AimRequireLOS")

    for _, t in ipairs(Utils.GetTargets(false)) do
        if ignoreDead and Utils.IsDead(t) then continue end
        if Utils.IsAlly(t, teamCheck) then continue end

        local wp = Utils.ResolvePart(t, partMode)
        if not wp then continue end
        if (Camera.CFrame.Position - wp).Magnitude > maxDist then continue end

        -- NOVO: valida linha de visão (parede bloqueia)
        if requireLOS then
            if not Utils.HasLOS(wp, t.model) then continue end
        end

        local sp, onScreen = Utils.WorldToScreen(wp)
        if not onScreen then continue end

        local d = (sp - center).Magnitude
        if d > fov then continue end

        if d < bestDist then
            bestDist = d
            best = { target = t, worldPos = wp }
        end
    end
    return best
end

function Aim.Start()
    RunService.RenderStepped:Connect(function(dt)
        if not Config.Get("AimEnabled") then return end
        aimAcc = aimAcc + dt
        if aimAcc < 1 / AIM_HZ then return end
        aimAcc = 0

        local best = findBestAimTarget()
        if not best then return end

        local smooth = math.clamp(Config.Get("AimSmooth"), 0.01, 1)
        local current = Camera.CFrame
        local desired = CFrame.lookAt(current.Position, best.worldPos)
        Camera.CFrame = current:Lerp(desired, smooth)
    end)
end

--=====================================================================
-- 6) ESP
--=====================================================================
local Esp = {}
local ESP_INTERVAL = 0.05
local espAcc = 0
local espGui, espCache = nil, {}

local function espDestroy(model)
    local e = espCache[model]; if not e then return end
    if e.highlight then e.highlight:Destroy() end
    if e.billboard then e.billboard:Destroy() end
    if e.box then e.box:Destroy() end
    espCache[model] = nil
end

local function espEnsure(model)
    if espCache[model] then return espCache[model] end
    local e = {}

    if Config.Get("EspHighlight") then
        local h = Instance.new("Highlight")
        h.Adornee = model; h.Parent = model
        e.highlight = h
    end

    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 180, 0, 60)
    bb.StudsOffset = Vector3.new(0, 3.2, 0)
    bb.AlwaysOnTop = true; bb.Parent = model
    e.billboard = bb

    local nameL = Instance.new("TextLabel")
    nameL.BackgroundTransparency = 1; nameL.Size = UDim2.new(1, 0, 0.4, 0)
    nameL.Font = Enum.Font.GothamBold; nameL.TextSize = 12
    nameL.TextStrokeTransparency = 0.4; nameL.TextColor3 = Color3.new(1,1,1)
    nameL.Parent = bb; e.name = nameL

    local distL = Instance.new("TextLabel")
    distL.BackgroundTransparency = 1
    distL.Position = UDim2.new(0, 0, 0.4, 0)
    distL.Size = UDim2.new(1, 0, 0.3, 0)
    distL.Font = Enum.Font.Gotham; distL.TextSize = 11
    distL.TextStrokeTransparency = 0.4
    distL.TextColor3 = Color3.fromRGB(210,210,210); distL.Parent = bb
    e.dist = distL

    local hpBg = Instance.new("Frame")
    hpBg.BackgroundColor3 = Color3.fromRGB(30,30,30); hpBg.BorderSizePixel = 0
    hpBg.Size = UDim2.new(0, 60, 0, 4)
    hpBg.Position = UDim2.new(0.5, -30, 1, 2); hpBg.Parent = bb
    local hpFill = Instance.new("Frame")
    hpFill.BackgroundColor3 = Color3.fromRGB(80,220,80); hpFill.BorderSizePixel = 0
    hpFill.Size = UDim2.new(1, 0, 1, 0); hpFill.Parent = hpBg
    e.hpBg, e.hpFill = hpBg, hpFill

    local box = Instance.new("Frame")
    box.BackgroundTransparency = 1; box.Visible = false
    box.Parent = espGui
    local bStroke = Instance.new("UIStroke")
    bStroke.Thickness = 1.5; bStroke.Parent = box
    e.box, e.boxStroke = box, bStroke

    espCache[model] = e
    return e
end

function Esp.Start()
    espGui = Instance.new("ScreenGui")
    espGui.Name = "AimEspGui"; espGui.IgnoreGuiInset = true
    espGui.ResetOnSpawn = false; espGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    RunService.RenderStepped:Connect(function(dt)
        espAcc = espAcc + dt
        if espAcc < ESP_INTERVAL then return end
        espAcc = 0

        if not Config.Get("EspEnabled") then
            for m in pairs(espCache) do espDestroy(m) end
            return
        end

        local seen = {}
        local teamCheck = Config.Get("EspTeamCheck")
        local maxDist = Config.Get("EspMaxDistance")
        local enemyC = Config.Get("ColorEnemy")
        local allyC  = Config.Get("ColorAlly")

        for _, t in ipairs(Utils.GetTargets(true)) do
            local model = t.model
            if not model or not model.Parent then continue end
            seen[model] = true

            local isAlly = Utils.IsAlly(t, teamCheck)
            local color = isAlly and allyC or enemyC

            local e = espEnsure(model)

            local root = model:FindFirstChild("HumanoidRootPart")
            local head = model:FindFirstChild("Head")
            local pos = root and root.Position or (head and head.Position)
            if not pos then continue end

            local d3 = (Camera.CFrame.Position - pos).Magnitude
            local show = d3 <= maxDist

            e.name.Visible = show and Config.Get("EspName")
            e.name.Text = t.name
            e.name.TextColor3 = color

            e.dist.Visible = show and Config.Get("EspDistance")
            e.dist.Text = string.format("%d m", math.floor(d3))

            e.hpBg.Visible = show and Config.Get("EspHealth")
            if e.hpBg.Visible and t.hum then
                local p = math.clamp(t.hum.Health / t.hum.MaxHealth, 0, 1)
                e.hpFill.Size = UDim2.new(p, 0, 1, 0)
                e.hpFill.BackgroundColor3 = Color3.fromRGB(255 - 175*p, 60 + 160*p, 60
