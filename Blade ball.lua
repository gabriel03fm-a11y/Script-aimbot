--[[
    SCRIPT: Blade Ball | Aimbot (Interface Rafild)
    ESTILO: Idêntico ao print (Rafild UI)
    FUNÇÕES: Aimbot + FOV + Wall Check + Team Check + Save/Load
--]]

-- ============================================================
-- SERVIÇOS
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ============================================================
-- PARENT ROBUSTO PARA UI
-- ============================================================
local function GetUIParent()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then
        local ok2 = pcall(function()
            local test = Instance.new("Folder")
            test.Parent = cg
            test:Destroy()
        end)
        if ok2 then return cg end
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

-- ============================================================
-- CONFIG (SALVAR/CARREGAR)
-- ============================================================
local CONFIG_FILE = "rafild_aimbot.json"

local Defaults = {
    AimbotEnabled = false,
    FOV = 120,
    Smoothness = 0.15,
    TargetPart = "Head",
    TeamCheck = true,
    WallCheck = true,
    ShowFovCircle = true,
    MaxDistance = 500,
}

local Settings = {}
for k, v in pairs(Defaults) do Settings[k] = v end

local function SaveConfig()
    if not writefile then return end
    local parts = {}
    for k, v in pairs(Settings) do
        local val
        if type(v) == "string" then val = string.format("%q", v)
        elseif type(v) == "boolean" or type(v) == "number" then val = tostring(v)
        else val = "nil" end
        table.insert(parts, string.format("  [%q] = %s", k, val))
    end
    pcall(function() writefile(CONFIG_FILE, "{\n" .. table.concat(parts, ",\n") .. "\n}") end)
end

local function LoadConfig()
    if not readfile or not isfile then return end
    if not isfile(CONFIG_FILE) then return end
    local ok, data = pcall(readfile, CONFIG_FILE)
    if not ok or not data then return end
    local ok2, tbl = pcall(function() return loadstring("return " .. data)() end)
    if ok2 and type(tbl) == "table" then
        for k, v in pairs(tbl) do
            if Defaults[k] ~= nil then Settings[k] = v end
        end
    end
end

LoadConfig()

-- ============================================================
-- UTILITÁRIOS
-- ============================================================
local function IsEnemy(player)
    if not Settings.TeamCheck then return true end
    if player.Team == LocalPlayer.Team then return false end
    return true
end

local function IsAlive(player)
    if not player or not player.Character then return false end
    local hum = player.Character:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function GetTargetPart(char, name)
    if not char then return nil end
    return char:FindFirstChild(name)
end

local function HasClearView(targetPart)
    local myChar = LocalPlayer.Character
    if not myChar or not targetPart.Parent then return false end

    local success, parts = pcall(function()
        return Camera:GetPartsObscuringTarget(
            { targetPart.Position },
            { myChar, targetPart.Parent, Camera }
        )
    end)
    if success and parts then return #parts == 0 end
    return true
end

-- ============================================================
-- AIMBOT
-- ============================================================
local aimbotBind = "RafildAimbot"

local function GetClosestTarget()
    local closest, shortest = nil, math.huge
    local center = Camera.ViewportSize / 2
    local myChar = LocalPlayer.Character
    if not myChar then return nil end
    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end
    local myPos = myRoot.Position

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and IsAlive(p) and IsEnemy(p) then
            local part = GetTargetPart(p.Character, Settings.TargetPart)
            if part then
                local worldDist = (myPos - part.Position).Magnitude
                if worldDist <= Settings.MaxDistance then
                    local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
                    if onScreen and sp.Z > 0 then
                        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        if d <= Settings.FOV and d < shortest then
                            if not Settings.WallCheck or HasClearView(part) then
                                shortest = d
                                closest = part
                            end
                        end
                    end
                end
            end
        end
    end
    return closest
end

local function UpdateAimbot()
    if not Settings.AimbotEnabled then return end
    local target = GetClosestTarget()
    if not target then return end

    -- Revalida FOV
    local sp, onScreen = Camera:WorldToViewportPoint(target.Position)
    if not onScreen or sp.Z <= 0 then return end
    local center = Camera.ViewportSize / 2
    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
    if d > Settings.FOV then return end
    if Settings.WallCheck and not HasClearView(target) then return end

    local cf = CFrame.new(Camera.CFrame.Position, target.Position)
    local alpha = 1 - math.clamp(Settings.Smoothness, 0, 0.99)
    Camera.CFrame = Camera.CFrame:Lerp(cf, alpha)
end

local function SetAimbot(state)
    Settings.AimbotEnabled = state
    if state then
        RunService:UnbindFromRenderStep(aimbotBind)
        RunService:BindToRenderStep(aimbotBind, Enum.RenderPriority.Camera.Value - 1, UpdateAimbot)
    else
        RunService:UnbindFromRenderStep(aimbotBind)
    end
    SaveConfig()
end

-- ============================================================
-- FOV CIRCLE
-- ============================================================
local FovGui, FovCircle
local function CreateFovCircle()
    if FovCircle then FovCircle:Destroy() end
    if FovGui then FovGui:Destroy() end

    FovGui = Instance.new("ScreenGui")
    FovGui.Name = "FovGui_" .. tostring(math.random(1000, 9999))
    FovGui.ResetOnSpawn = false
    FovGui.IgnoreGuiInset = true
    FovGui.DisplayOrder = 999998
    FovGui.Parent = GetUIParent()

    local circle = Instance.new("Frame")
    circle.AnchorPoint = Vector2.new(0.5, 0.5)
    circle.Position = UDim2.new(0.5, 0, 0.5, 0)
    circle.Size = UDim2.new(0, Settings.FOV * 2, 0, Settings.FOV * 2)
    circle.BackgroundTransparency = 1
    circle.BorderSizePixel = 0
    circle.Visible = Settings.ShowFovCircle
    circle.Parent = FovGui

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent = circle

    local s1 = Instance.new("UIStroke")
    s1.Thickness = 4
    s1.Color = Color3.fromRGB(0, 0, 0)
    s1.Transparency = 0.5
    s1.Parent = circle

    local s2 = Instance.new("UIStroke")
    s2.Thickness = 2
    s2.Color = Color3.fromRGB(70, 170, 240)
    s2.Parent = circle

    FovCircle = circle
end

local function UpdateFovCircle()
    if not FovCircle then CreateFovCircle() end
    if FovCircle then
        FovCircle.Size = UDim2.new(0, Settings.FOV * 2, 0, Settings.FOV * 2)
        FovCircle.Visible = Settings.ShowFovCircle
    end
end

-- ============================================================
-- INTERFACE (ESTILO RAFILD — IGUAL AO PRINT)
-- ============================================================
local function CreateUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RafildUI_" .. tostring(math.random(1000, 9999))
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 999999
    screenGui.Parent = GetUIParent()

    -- Botão flutuante
    local openBtn = Instance.new("TextButton")
    openBtn.Size = UDim2.new(0, 55, 0, 55)
    openBtn.Position = UDim2.new(0, 20, 0.5, -27)
    openBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    openBtn.BorderSizePixel = 0
    openBtn.Text = "⚙"
    openBtn.TextColor3 = Color3.new(1, 1, 1)
    openBtn.TextSize = 26
    openBtn.Font = Enum.Font.GothamBold
    openBtn.Active = true
    openBtn.Draggable = true
    openBtn.Parent = screenGui

    local oc = Instance.new("UICorner")
    oc.CornerRadius = UDim.new(1, 0)
    oc.Parent = openBtn

    -- ==================== JANELA ====================
    local main = Instance.new("Frame")
    main.Name = "MainFrame"
    main.Size = UDim2.new(0, 620, 0, 560)
    main.Position = UDim2.new(0.5, -310, 0.5, -280)
    main.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = screenGui

    local mc = Instance.new("UICorner")
    mc.CornerRadius = UDim.new(0, 16)
    mc.Parent = main

    local mStroke = Instance.new("UIStroke")
    mStroke.Color = Color3.fromRGB(70, 70, 70)
    mStroke.Thickness = 1
    mStroke.Parent = main

    -- Título
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -80, 0, 40)
    title.Position = UDim2.new(0, 20, 0, 15)
    title.BackgroundTransparency = 1
    title.Text = "Blade Ball | Aimbot"
    title.TextColor3 = Color3.new(1, 1, 1)
    title.TextSize = 22
    title.Font = Enum.Font.GothamMedium
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = main

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -45, 0, 20)
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.TextSize = 14
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = main

    local cc = Instance.new("UICorner")
    cc.CornerRadius = UDim.new(1, 0)
    cc.Parent = closeBtn

    closeBtn.MouseButton1Click:Connect(function() main.Visible = false end)
    openBtn.MouseButton1Click:Connect(function() main.Visible = not main.Visible end)

    -- Aba selecionada (estilo print)
    local tabBtn = Instance.new("TextButton")
    tabBtn.Size = UDim2.new(0, 220, 0, 45)
    tabBtn.Position = UDim2.new(0, 20, 0, 70)
    tabBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    tabBtn.Text = ""
    tabBtn.BorderSizePixel = 0
    tabBtn.Parent = main

    local tbc = Instance.new("UICorner")
    tbc.CornerRadius = UDim.new(0, 10)
    tbc.Parent = tabBtn

    local icon = Instance.new("Frame")
    icon.Size = UDim2.new(0, 22, 0, 22)
    icon.Position = UDim2.new(0, 15, 0.5, -11)
    icon.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    icon.BorderSizePixel = 0
    icon.Parent = tabBtn

    local ic = Instance.new("UICorner")
    ic.CornerRadius = UDim.new(0, 4)
    ic.Parent = icon

    local iconStroke = Instance.new("UIStroke")
    iconStroke.Color = Color3.new(1, 1, 1)
    iconStroke.Thickness = 2
    iconStroke.Parent = icon

    local tabText = Instance.new("TextLabel")
    tabText.Size = UDim2.new(1, -50, 1, 0)
    tabText.Position = UDim2.new(0, 45, 0, 0)
    tabText.BackgroundTransparency = 1
    tabText.Text = "Aimbot"
    tabText.TextColor3 = Color3.new(1, 1, 1)
    tabText.TextSize = 16
    tabText.Font = Enum.Font.GothamMedium
    tabText.TextXAlignment = Enum.TextXAlignment.Left
    tabText.Parent = tabBtn

    -- ==================== SEÇÃO: Controles ====================
    local sectionLabel1 = Instance.new("TextLabel")
    sectionLabel1.Size = UDim2.new(1, -40, 0, 25)
    sectionLabel1.Position = UDim2.new(0, 25, 0, 125)
    sectionLabel1.BackgroundTransparency = 1
    sectionLabel1.Text = "Controles"
    sectionLabel1.TextColor3 = Color3.fromRGB(170, 170, 170)
    sectionLabel1.TextSize = 15
    sectionLabel1.Font = Enum.Font.Gotham
    sectionLabel1.TextXAlignment = Enum.TextXAlignment.Left
    sectionLabel1.Parent = main

    -- Função para criar linha de toggle (estilo print)
    local function CreateControlRow(yPos, text, default, callback)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -40, 0, 55)
        row.Position = UDim2.new(0, 20, 0, yPos)
        row.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
        row.BorderSizePixel = 0
        row.Parent = main

        local rc = Instance.new("UICorner")
        rc.CornerRadius = UDim.new(0, 10)
        rc.Parent = row

        local rStroke = Instance.new("UIStroke")
        rStroke.Color = Color3.fromRGB(80, 80, 80)
        rStroke.Thickness = 1
        rStroke.Parent = row

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0.6, 0, 1, 0)
        lbl.Position = UDim2.new(0, 20, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = Color3.new(1, 1, 1)
        lbl.TextSize = 16
        lbl.Font = Enum.Font.Gotham
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        -- Toggle azul (estilo print)
        local tBg = Instance.new("Frame")
        tBg.Size = UDim2.new(0, 60, 0, 32)
        tBg.Position = UDim2.new(1, -80, 0.5, -16)
        tBg.BackgroundColor3 = default and Color3.fromRGB(70, 170, 240) or Color3.fromRGB(70, 70, 70)
        tBg.BorderSizePixel = 0
        tBg.Parent = row

        local tBgC = Instance.new("UICorner")
        tBgC.CornerRadius = UDim.new(1, 0)
        tBgC.Parent = tBg

        local tStroke = Instance.new("UIStroke")
        tStroke.Color = Color3.fromRGB(90, 90, 90)
        tStroke.Thickness = 1.5
        tStroke.Parent = tBg

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 26, 0, 26)
        knob.Position = default and UDim2.new(1, -29, 0.5, -13) or UDim2.new(0, 3, 0.5, -13)
        knob.BackgroundColor3 = Color3.new(1, 1, 1)
        knob.BorderSizePixel = 0
        knob.Parent = tBg

        local knobC = Instance.new("UICorner")
        knobC.CornerRadius = UDim.new(1, 0)
        knobC.Parent = knob

        local isOn = default
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.Parent = tBg

        btn.MouseButton1Click:Connect(function()
            isOn = not isOn
            tBg.BackgroundColor3 = isOn and Color3.fromRGB(70, 170, 240) or Color3.fromRGB(70, 70, 70)
            TweenService:Create(knob, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                Position = isOn and UDim2.new(1, -29, 0.5, -13) or UDim2.new(0, 3, 0.5, -13)
            }):Play()
            if callback then callback(isOn) end
        end)

        return row
    end

    CreateControlRow(160, "Aimbot", Settings.AimbotEnabled, function(v)
        SetAimbot(v)
    end)

    CreateControlRow(225, "Team Check", Settings.TeamCheck, function(v)
        Settings.TeamCheck = v
        SaveConfig()
    end)

    CreateControlRow(290, "Wall Check", Settings.WallCheck, function(v)
        Settings.WallCheck = v
        SaveConfig()
    end)

    CreateControlRow(355, "Mostrar FOV", Settings.ShowFovCircle, function(v)
        Settings.ShowFovCircle = v
        UpdateFovCircle()
        SaveConfig()
    end)

    -- ==================== SEÇÃO: Detecção ====================
    local sectionLabel2 = Instance.new("TextLabel")
    sectionLabel2.Size = UDim2.new(1, -40, 0, 25)
    sectionLabel2.Position = UDim2.new(0, 25, 0, 430)
    sectionLabel2.BackgroundTransparency = 1
    sectionLabel2.Text = "Detecção"
    sectionLabel2.TextColor3 = Color3.fromRGB(170, 170, 170)
    sectionLabel2.TextSize = 15
    sectionLabel2.Font = Enum.Font.Gotham
    sectionLabel2.TextXAlignment = Enum.TextXAlignment.Left
    sectionLabel2.Parent = main

    -- ==================== Slider FOV (estilo badge azul) ====================
    local sliderRow = Instance.new("Frame")
    sliderRow.Size = UDim2.new(1, -40, 0, 90)
    sliderRow.Position = UDim2.new(0, 20, 0, 465)
    sliderRow.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
    sliderRow.BorderSizePixel = 0
    sliderRow.Parent = main

    local src = Instance.new("UICorner")
    src.CornerRadius = UDim.new(0, 10)
    src.Parent = sliderRow

    local srStroke = Instance.new("UIStroke")
    srStroke.Color = Color3.fromRGB(80, 80, 80)
    srStroke.Thickness = 1
    srStroke.Parent = sliderRow

    local sliderLbl = Instance.new("TextLabel")
    sliderLbl.Size = UDim2.new(1, -20, 0, 30)
    sliderLbl.Position = UDim2.new(0, 20, 0, 5)
    sliderLbl.BackgroundTransparency = 1
    sliderLbl.Text = "Tamanho do FOV"
    sliderLbl.TextColor3 = Color3.new(1, 1, 1)
    sliderLbl.TextSize = 16
    sliderLbl.Font = Enum.Font.Gotham
    sliderLbl.TextXAlignment = Enum.TextXAlignment.Left
    sliderLbl.Parent = sliderRow

    -- Badge azul (valor)
    local valueBadge = Instance.new("Frame")
    valueBadge.Size = UDim2.new(0, 130, 0, 38)
    valueBadge.Position = UDim2.new(1, -145, 0, 20)
    valueBadge.BackgroundColor3 = Color3.fromRGB(70, 170, 240)
    valueBadge.BorderSizePixel = 0
    valueBadge.Parent = sliderRow

    local vbc = Instance.new("UICorner")
    vbc.CornerRadius = UDim.new(1, 0)
    vbc.Parent = valueBadge

    local valueText = Instance.new("TextLabel")
    valueText.Size = UDim2.new(1, 0, 1, 0)
    valueText.BackgroundTransparency = 1
    valueText.Text = Settings.FOV .. " px"
    valueText.TextColor3 = Color3.new(1, 1, 1)
    valueText.TextSize = 15
    valueText.Font = Enum.Font.GothamMedium
    valueText.Parent = valueBadge

    -- Barra do slider
    local trackBg = Instance.new("Frame")
    trackBg.Size = UDim2.new(1, -40, 0, 8)
    trackBg.Position = UDim2.new(0, 20, 1, -18)
    trackBg.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    trackBg.BorderSizePixel = 0
    trackBg.Parent = sliderRow

    local tbgC = Instance.new("UICorner")
    tbgC.CornerRadius = UDim.new(1, 0)
    tbgC.Parent = trackBg

    local trackFill = Instance.new("Frame")
    trackFill.Size = UDim2.new((Settings.FOV - 10) / 490, 0, 1, 0)
    trackFill.BackgroundColor3 = Color3.fromRGB(70, 170, 240)
    trackFill.BorderSizePixel = 0
    trackFill.Parent = trackBg

    local tfc = Instance.new("UICorner")
    tfc.CornerRadius = UDim.new(1, 0)
    tfc.Parent = trackFill

    local dragging = false
    local function updateSlider(input)
        local pos = math.clamp((input.Position.X - trackBg.AbsolutePosition.X) / trackBg.AbsoluteSize.X, 0, 1)
        local val = math.floor(10 + 490 * pos + 0.5)
        trackFill.Size = UDim2.new(pos, 0, 1, 0)
        valueText.Text = val .. " px"
        Settings.FOV = val
        UpdateFovCircle()
    end

    local sliderBtn = Instance.new("TextButton")
    sliderBtn.Size = UDim2.new(1, 0, 3, 0)
    sliderBtn.Position = UDim2.new(0, 0, 0, -8)
    sliderBtn.BackgroundTransparency = 1
    sliderBtn.Text = ""
    sliderBtn.Parent = trackBg

    sliderBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateSlider(input)
        end
    end)
    sliderBtn.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateSlider(input)
        end
    end)
    sliderBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            SaveConfig()
        end
    end)

    main.Visible = false
    return main
end

-- ============================================================
-- INICIALIZAÇÃO
-- ============================================================
CreateUI()
CreateFovCircle()
UpdateFovCircle()

if Settings.AimbotEnabled then SetAimbot(true) end

StarterGui:SetCore("SendNotification", {
    Title = "Rafild Aimbot",
    Text = "Carregado com sucesso!",
    Duration = 3,
})

print("✅ Rafild Aimbot carregado!")
