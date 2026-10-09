--!strict
--============================================================
-- RoubeUmOvo_Client.lua
-- LocalScript -> StarterPlayer/StarterPlayerScripts
-- Framework de UI + lógica client-side para o SEU jogo.
-- Onde houver [HOOK], conecte ao RemoteEvent do seu servidor.
--============================================================

local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

--============================================================
-- CONFIG CENTRAL
--============================================================
local Config = {
    UIKeybind        = Enum.KeyCode.RightShift,
    Theme            = "Dark",           -- "Dark" | "Midnight" | "Light"
    Transparency     = 0.15,
    Notifications    = true,

    ESP              = true,
    PlayerESP        = true,
    EggESP           = true,
    CreatureESP      = false,
    ItemESP          = false,
    BaseESP          = false,
    MaxESPDistance   = 500,

    AutoCollect      = false,
    AutoHatch        = false,
    AutoSell         = false,
    AutoEquip        = false,
    AutoClaim        = false,
    AutoBuy          = false,
    AutoRebirth      = false,
    AutoFarm         = false,
    AutomationDelay  = 0.5,
    StopWhenFull     = true,

    MinimumValue     = 1_000_000,
    RarityFilter     = "All",

    StealCooldown    = 30,
    StealDistance    = 15,
}

--============================================================
-- DADOS DE EXEMPLO (substitua pelos reais via [HOOK])
--============================================================
local EggDatabase = {
    { Name = "Ovo Comum",      Rarity = "Common",    Price = 100,      Value = 250,
      Creatures = {
        { Name = "Galinha",  Chance = 60, Value = 50,   Yield = 10, Rarity = "Common" },
        { Name = "Pato",     Chance = 30, Value = 120,  Yield = 20, Rarity = "Uncommon" },
        { Name = "Pavão",    Chance = 10, Value = 900,  Yield = 60, Rarity = "Rare" },
      }},
    { Name = "Ovo Raro",       Rarity = "Rare",      Price = 5_000,    Value = 12_000,
      Creatures = {
        { Name = "Lobo",     Chance = 50, Value = 2_000,  Yield = 150, Rarity = "Uncommon" },
        { Name = "Dragão",   Chance = 35, Value = 15_000, Yield = 800, Rarity = "Epic" },
        { Name = "Fênix",    Chance = 15, Value = 80_000, Yield = 3_000, Rarity = "Legendary" },
      }},
    { Name = "Ovo Lendário",   Rarity = "Legendary", Price = 250_000,  Value = 900_000,
      Creatures = {
        { Name = "Grifo",       Chance = 60, Value = 120_000,  Yield = 6_000,  Rarity = "Epic" },
        { Name = "Quimera",     Chance = 30, Value = 900_000,  Yield = 40_000, Rarity = "Legendary" },
        { Name = "Deus Dragão", Chance = 10, Value = 9_000_000, Yield = 500_000, Rarity = "Mythic" },
      }},
    { Name = "Ovo Mítico",     Rarity = "Mythic",    Price = 15_000_000, Value = 40_000_000,
      Creatures = {
        { Name = "Serafim",     Chance = 70, Value = 5_000_000,  Yield = 500_000,  Rarity = "Legendary" },
        { Name = "Cronos",      Chance = 25, Value = 80_000_000, Yield = 4_000_000, Rarity = "Mythic" },
        { Name = "Ovo Primordial", Chance = 5, Value = 999_000_000, Yield = 50_000_000, Rarity = "Secret" },
      }},
    { Name = "Ovo Secreto",    Rarity = "Secret",    Price = 500_000_000, Value = 1_500_000_000,
      Creatures = {
        { Name = "Anomalia",   Chance = 90, Value = 250_000_000,  Yield = 20_000_000, Rarity = "Secret" },
        { Name = "Criador",    Chance = 10, Value = 5_000_000_000, Yield = 400_000_000, Rarity = "Secret" },
      }},
}

-- Lista "flat" de criaturas para abas/rankings
local CreatureDatabase = {}
do
    for _, egg in ipairs(EggDatabase) do
        for _, c in ipairs(egg.Creatures) do
            table.insert(CreatureDatabase, {
                Name = c.Name, Rarity = c.Rarity,
                Value = c.Value, Yield = c.Yield,
                Origin = egg.Name, Chance = c.Chance,
            })
        end
    end
end

--============================================================
-- UTILITÁRIOS
--============================================================
local U = {}
local connectionPool: {RBXScriptConnection} = {}
function U.Track(c: RBXScriptConnection) table.insert(connectionPool, c) end
function U.Clear()
    for _, c in ipairs(connectionPool) do pcall(function() c:Disconnect() end) end
    table.clear(connectionPool)
end

local debounces: {[string]: number} = {}
function U.Debounce(key: string, t: number): boolean
    local now = os.clock()
    if debounces[key] and now - debounces[key] < t then return false end
    debounces[key] = now
    return true
end

function U.Tween(i: Instance, p: {[string]: any}, t: number?)
    TweenService:Create(i, TweenInfo.new(t or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), p):Play()
end

function U.RarityColor(r: string): Color3
    local map = {
        Common    = Color3.fromRGB(180, 180, 180),
        Uncommon  = Color3.fromRGB(80, 200, 120),
        Rare      = Color3.fromRGB(80, 150, 255),
        Epic      = Color3.fromRGB(170, 90, 255),
        Legendary = Color3.fromRGB(255, 180, 40),
        Mythic    = Color3.fromRGB(255, 60, 60),
        Secret    = Color3.fromRGB(255, 90, 200),
        All       = Color3.fromRGB(255, 255, 255),
    }
    return map[r] or Color3.new(1, 1, 1)
end

function U.FormatNumber(n: number): string
    if n >= 1e12 then return string.format("%.2fT", n / 1e12) end
    if n >= 1e9  then return string.format("%.2fB", n / 1e9)  end
    if n >= 1e6  then return string.format("%.2fM", n / 1e6)  end
    if n >= 1e3  then return string.format("%.2fK", n / 1e3)  end
    return tostring(math.floor(n))
end

function U.LocalRoot(): BasePart?
    local c = LocalPlayer.Character
    return c and (c:FindFirstChild("HumanoidRootPart") :: BasePart?)
end

function U.Distance(a: Vector3, b: Vector3): number
    return (a - b).Magnitude
end

--============================================================
-- TEMA
--============================================================
local Themes = {
    Dark     = { bg = Color3.fromRGB(18,20,26),  panel = Color3.fromRGB(26,28,36),  accent = Color3.fromRGB(90,170,255),  text = Color3.new(1,1,1), sub = Color3.fromRGB(180,180,190) },
    Midnight = { bg = Color3.fromRGB(10,10,18),  panel = Color3.fromRGB(20,20,34),  accent = Color3.fromRGB(160,100,255), text = Color3.new(1,1,1), sub = Color3.fromRGB(170,170,200) },
    Light    = { bg = Color3.fromRGB(230,230,240), panel = Color3.fromRGB(250,250,255), accent = Color3.fromRGB(60,130,220),  text = Color3.fromRGB(20,20,30), sub = Color3.fromRGB(90,90,110) },
}
local theme = Themes[Config.Theme] or Themes.Dark

--============================================================
-- SCREEN GUI
--============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RoubeUmOvo_UI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = PlayerGui

local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local dragging, dragStart, startPos

--============================================================
-- HELPERS DE UI
--============================================================
local function corner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p; return c end
local function padding(p, t, r, b, l)
    local pd = Instance.new("UIPadding")
    pd.PaddingTop, pd.PaddingRight, pd.PaddingBottom, pd.PaddingLeft = UDim.new(0,t), UDim.new(0,r), UDim.new(0,b), UDim.new(0,l)
    pd.Parent = p
end
local function stroke(p, color, thick, trans)
    local s = Instance.new("UIStroke", p)
    s.Color, s.Thickness, s.Transparency = color, thick or 1, trans or 0.6
    return s
end

--============================================================
-- NOTIFICAÇÕES
--============================================================
local NotifContainer = Instance.new("Frame")
NotifContainer.Name = "Notif"
NotifContainer.AnchorPoint = Vector2.new(1, 0)
NotifContainer.Position = UDim2.new(1, -12, 0, 12)
NotifContainer.Size = UDim2.new(0, 300, 1, -24)
NotifContainer.BackgroundTransparency = 1
NotifContainer.Parent = screenGui
local notifLayout = Instance.new("UIListLayout", NotifContainer)
notifLayout.Padding = UDim.new(0, 8)
notifLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function Notify(title: string, message: string, dur: number?, color: Color3?)
    if not Config.Notifications then return end
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, 0)
    f.AutomaticSize = Enum.AutomaticSize.Y
    f.BackgroundColor3 = theme.panel
    f.BackgroundTransparency = 0.05
    f.BorderSizePixel = 0
    f.Parent = NotifContainer
    corner(f, 8)
    padding(f, 8, 12, 8, 14)

    local accent = Instance.new("Frame", f)
    accent.Size = UDim2.new(0, 4, 1, 0)
    accent.BackgroundColor3 = color or theme.accent
    accent.BorderSizePixel = 0
    corner(accent, 4)

    local t = Instance.new("TextLabel", f)
    t.BackgroundTransparency = 1
    t.Size = UDim2.new(1, 0, 0, 18)
    t.Font = Enum.Font.GothamBold
    t.TextSize = 14
    t.TextColor3 = theme.text
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Text = title

    local m = Instance.new("TextLabel", f)
    m.BackgroundTransparency = 1
    m.Position = UDim2.new(0, 0, 0, 20)
    m.Size = UDim2.new(1, 0, 0, 0)
    m.AutomaticSize = Enum.AutomaticSize.Y
    m.Font = Enum.Font.Gotham
    m.TextSize = 12
    m.TextWrapped = true
    m.TextColor3 = theme.sub
    m.TextXAlignment = Enum.TextXAlignment.Left
    m.Text = message

    task.delay(dur or 4, function()
        if not f.Parent then return end
        U.Tween(f, { BackgroundTransparency = 1 }, 0.3)
        for _, d in ipairs(f:GetDescendants()) do
            if d:IsA("TextLabel") then U.Tween(d, { TextTransparency = 1 }, 0.3) end
        end
        task.wait(0.35)
        f:Destroy()
    end)
end

--============================================================
-- JANELA PRINCIPAL
--============================================================
local main = Instance.new("Frame")
main.Size = isMobile and UDim2.new(0.95, 0, 0.82, 0) or UDim2.new(0, 660, 0, 460)
main.Position = UDim2.new(0.5, 0, 0.5, 0)
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.BackgroundColor3 = theme.bg
main.BackgroundTransparency = Config.Transparency
main.BorderSizePixel = 0
main.Visible = false
main.Active = true
main.Draggable = not isMobile
main.Parent = screenGui
corner(main, 12)
stroke(main, theme.accent, 1, 0.6)

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 36)
header.BackgroundColor3 = theme.panel
header.BackgroundTransparency = 0.2
header.BorderSizePixel = 0
header.Parent = main
corner(header, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -80, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = theme.text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "🥚 Roube um Ovo — v1.0"
title.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 28, 0, 28)
minBtn.Position = UDim2.new(1, -64, 0, 4)
minBtn.BackgroundColor3 = theme.panel
minBtn.Text = "—"
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
minBtn.TextColor3 = theme.text
minBtn.BorderSizePixel = 0
minBtn.Parent = header
corner(minBtn, 6)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -32, 0, 4)
closeBtn.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
closeBtn.Text = "×"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.TextColor3 = Color3.new(1,1,1)
closeBtn.BorderSizePixel = 0
closeBtn.Parent = header
corner(closeBtn, 6)

-- Search
local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -24, 0, 30)
searchBox.Position = UDim2.new(0, 12, 0, 46)
searchBox.BackgroundColor3 = theme.panel
searchBox.BorderSizePixel = 0
searchBox.PlaceholderText = "🔎 Pesquisar..."
searchBox.Text = ""
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 13
searchBox.TextColor3 = theme.text
searchBox.PlaceholderColor3 = theme.sub
searchBox.ClearTextOnFocus = false
searchBox.Parent = main
corner(searchBox, 6)
padding(searchBox, 0, 8, 0, 10)

-- Tab bar
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(0, 150, 1, -110)
tabBar.Position = UDim2.new(0, 12, 0, 86)
tabBar.BackgroundTransparency = 1
tabBar.Parent = main
local tabLayout = Instance.new("UIListLayout", tabBar)
tabLayout.Padding = UDim.new(0, 6)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- Content
local content = Instance.new("Frame")
content.Size = UDim2.new(1, -190, 1, -110)
content.Position = UDim2.new(0, 174, 0, 86)
content.BackgroundColor3 = theme.panel
content.BackgroundTransparency = 0.3
content.BorderSizePixel = 0
content.Parent = main
corner(content, 8)

-- Status
local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -24, 0, 20)
status.Position = UDim2.new(0, 12, 1, -26)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextColor3 = theme.sub
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = "Pressione " .. Config.UIKeybind.Name .. " para abrir/fechar."
status.Parent = main

-- Botão flutuante
local openBtn = Instance.new("TextButton")
openBtn.Size = UDim2.new(0, isMobile and 56 or 48, 0, isMobile and 56 or 48)
openBtn.Position = UDim2.new(0, 16, 0.4, 0)
openBtn.BackgroundColor3 = theme.accent
openBtn.Text = "🥚"
openBtn.Font = Enum.Font.GothamBold
openBtn.TextSize = isMobile and 24 or 20
openBtn.TextColor3 = Color3.new(1,1,1)
openBtn.BorderSizePixel = 0
openBtn.Active = true
openBtn.Draggable = true
openBtn.Parent = screenGui
corner(openBtn, 100)

openBtn.MouseButton1Click:Connect(function() main.Visible = not main.Visible end)
closeBtn.MouseButton1Click:Connect(function() main.Visible = false end)
minBtn.MouseButton1Click:Connect(function()
    local minimized = content.Visible
    content.Visible = not minimized
    tabBar.Visible = not minimized
    U.Tween(main, { Size = minimized and UDim2.new(0, 660, 0, 40) or (isMobile and UDim2.new(0.95,0,0.82,0) or UDim2.new(0,660,0,460)) }, 0.2)
end)

U.Track(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Config.UIKeybind then
        main.Visible = not main.Visible
    end
end))

--============================================================
-- SISTEMA DE ABAS
--============================================================
local tabs: {[string]: ScrollingFrame} = {}
local currentTab = "Home"

local function AddTab(name: string, icon: string)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 30)
    btn.BackgroundColor3 = theme.panel
    btn.BackgroundTransparency = 0.4
    btn.BorderSizePixel = 0
    btn.Text = icon .. "  " .. name
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 12
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.TextColor3 = theme.text
    btn.AutoButtonColor = true
    btn.Parent = tabBar
    corner(btn, 6)
    padding(btn, 0, 8, 0, 10)

    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(1, -16, 1, -16)
    page.Position = UDim2.new(0, 8, 0, 8)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.ScrollBarThickness = 4
    page.Visible = false
    page.Parent = content
    local l = Instance.new("UIListLayout", page)
    l.Padding = UDim.new(0, 6)
    tabs[name] = page

    btn.MouseButton1Click:Connect(function()
        for _, p in pairs(tabs) do p.Visible = false end
        page.Visible = true
        currentTab = name
    end)
end

--============================================================
-- COMPONENTES REUTILIZÁVEIS
--============================================================
local UI = {}

function UI.Section(parent: Instance, text: string)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, 22)
    f.BackgroundTransparency = 1
    f.Parent = parent
    local l = Instance.new("TextLabel", f)
    l.Size = UDim2.new(1, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.GothamBold
    l.TextSize = 12
    l.TextColor3 = theme.accent
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text:upper()
end

function UI.Toggle(parent: Instance, text: string, default: boolean, cb: (boolean) -> ())
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 28)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(1, -60, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 13
    lbl.TextColor3 = theme.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = text

    local track = Instance.new("Frame", row)
    track.Size = UDim2.new(0, 42, 0, 20)
    track.Position = UDim2.new(1, -42, 0.5, -10)
    track.BackgroundColor3 = default and theme.accent or Color3.fromRGB(60, 60, 70)
    track.BorderSizePixel = 0
    corner(track, 10)

    local knob = Instance.new("Frame", track)
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = default and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    knob.BackgroundColor3 = Color3.new(1,1,1)
    knob.BorderSizePixel = 0
    corner(knob, 8)

    local state = default
    local btn = Instance.new("TextButton", row)
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.MouseButton1Click:Connect(function()
        state = not state
        U.Tween(track, { BackgroundColor3 = state and theme.accent or Color3.fromRGB(60,60,70) }, 0.15)
        U.Tween(knob, { Position = state and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8) }, 0.15)
        cb(state)
    end)
end

function UI.Slider(parent: Instance, text: string, min: number, max: number, default: number, cb: (number) -> ())
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 44)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(1, 0, 0, 18)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextColor3 = theme.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = text .. ": " .. tostring(default)

    local track = Instance.new("Frame", row)
    track.Size = UDim2.new(1, 0, 0, 6)
    track.Position = UDim2.new(0, 0, 0, 28)
    track.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    track.BorderSizePixel = 0
    corner(track, 3)

    local fill = Instance.new("Frame", track)
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = theme.accent
    fill.BorderSizePixel = 0
    corner(fill, 3)

    local btn = Instance.new("TextButton", row)
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""

    local function update(x: number)
        local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local val = math.floor(min + (max - min) * rel)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        lbl.Text = text .. ": " .. tostring(val)
        cb(val)
    end

    U.Track(btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            update(input.Position.X)
        end
    end))
    U.Track(UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            if btn:IsHovered() or input.UserInputType == Enum.UserInputType.Touch then
                update(input.Position.X)
            end
        end
    end))
end

function UI.Button(parent: Instance, text: string, cb: () -> ())
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 28)
    b.BackgroundColor3 = theme.accent
    b.BorderSizePixel = 0
    b.Text = text
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 13
    b.TextColor3 = Color3.new(1,1,1)
    b.Parent = parent
    corner(b, 6)
    b.MouseButton1Click:Connect(cb)
    return b
end

function UI.Dropdown(parent: Instance, text: string, options: {string}, default: string, cb: (string) -> ())
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 30)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(0.5, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextColor3 = theme.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = text

    local current = default
    local btn = Instance.new("TextButton", row)
    btn.Size = UDim2.new(0.5, -4, 1, 0)
    btn.Position = UDim2.new(0.5, 4, 0, 0)
    btn.BackgroundColor3 = theme.panel
    btn.BorderSizePixel = 0
    btn.Text = current .. " ▾"
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 12
    btn.TextColor3 = theme.text
    corner(btn, 4)

    btn.MouseButton1Click:Connect(function()
        local idx = table.find(options, current) or 0
        current = options[(idx % #options) + 1]
        btn.Text = current .. " ▾"
        cb(current)
    end)
end

function UI.TextBox(parent: Instance, text: string, default: string, cb: (string) -> ())
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 30)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(0.5, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextColor3 = theme.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = text

    local box = Instance.new("TextBox", row)
    box.Size = UDim2.new(0.5, -4, 1, 0)
    box.Position = UDim2.new(0.5, 4, 0, 0)
    box.BackgroundColor3 = theme.panel
    box.BorderSizePixel = 0
    box.Text = default
    box.Font = Enum.Font.Gotham
    box.TextSize = 12
    box.TextColor3 = theme.text
    box.ClearTextOnFocus = false
    corner(box, 4)
    box.FocusLost:Connect(function() cb(box.Text) end)
end

-- Cria uma lista rolável filtrável dentro de uma aba
function UI.ListContainer(parent: Instance): (Frame, (string) -> ())
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 0)
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.BackgroundTransparency = 1
    holder.Parent = parent
    local layout = Instance.new("UIListLayout", holder)
    layout.Padding = UDim.new(0, 4)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    local function clear()
        for _, c in ipairs(holder:GetChildren()) do
            if c:IsA("GuiObject") and not c:IsA("UIListLayout") then c:Destroy() end
        end
    end
    return holder, clear
end

local function Card(parent: Instance, titleText: string, subText: string, rarity: string, onClick: (() -> ())?)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 52)
    card.BackgroundColor3 = theme.panel
    card.BackgroundTransparency = 0.35
    card.BorderSizePixel = 0
    card.Parent = parent
    corner(card, 8)

    local accent = Instance.new("Frame", card)
    accent.Size = UDim2.new(0, 4, 1, 0)
    accent.BackgroundColor3 = U.RarityColor(rarity)
    accent.BorderSizePixel = 0
    corner(accent, 8)

    local t = Instance.new("TextLabel", card)
    t.BackgroundTransparency = 1
    t.Position = UDim2.new(0, 14, 0, 4)
    t.Size = UDim2.new(1, -20, 0, 20)
    t.Font = Enum.Font.GothamBold
    t.TextSize = 13
    t.TextColor3 = theme.text
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Text = titleText

    local s = Instance.new("TextLabel", card)
    s.BackgroundTransparency = 1
    s.Position = UDim2.new(0, 14, 0, 24)
    s.Size = UDim2.new(1, -20, 0, 22)
    s.Font = Enum.Font.Gotham
    s.TextSize = 11
    s.TextColor3 = theme.sub
    s.TextXAlignment = Enum.TextXAlignment.Left
    s.TextWrapped = true
    s.Text = subText

    if onClick then
        local b = Instance.new("TextButton", card)
        b.Size = UDim2.new(1, 0, 1, 0)
        b.BackgroundTransparency = 1
        b.Text = ""
        b.MouseButton1Click:Connect(onClick)
    end
    return card
end

--============================================================
-- ABA: HOME
--============================================================
AddTab("Home", "🏠")
do
    local p = tabs["Home"]
    UI.Section(p, "Bem-vindo")
    Card(p, "Roube um Ovo — Framework de UI",
        "Este painel demonstra todos os componentes prontos para o seu jogo.\nConecte as ações a RemoteEvents do servidor nos pontos [HOOK].",
        "Rare")
    UI.Section(p, "Atalhos")
    Card(p, Config.UIKeybind.Name .. "  →  Abrir/fechar menu", "Também clique no botão flutuante 🥚", "Common")
    Card(p, "Ctrl + S (opcional)", "Salvar configurações (via Attribute no servidor).", "Common")
end

--============================================================
-- ABA: OVOS
--============================================================
AddTab("Ovos", "🥚")
do
    local p = tabs["Ovos"]
    UI.Section(p, "Filtros")
    local filterMin = Config.MinimumValue
    UI.Dropdown(p, "Raridade:", { "All","Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret" }, "All", function(v) filterMin = filterMin end)
    UI.Slider(p, "Valor mínimo", 0, 1_000_000_000, Config.MinimumValue, function(v)
        Config.MinimumValue = v
        -- [HOOK] se quiser, avise o servidor da sua preferência
    end)
    UI.Section(p, "Lista de Ovos")
    local holder, clear = UI.ListContainer(p)

    local function render(search: string)
        clear()
        local list = {}
        for _, e in ipairs(EggDatabase) do
            local totalYield = 0
            for _, c in ipairs(e.Creatures) do totalYield += c.Yield end
            if e.Value >= Config.MinimumValue
                and (search == "" or e.Name:lower():find(search:lower(), 1, true)) then
                table.insert(list, { egg = e, totalYield = totalYield })
            end
        end
        table.sort(list, function(a, b) return a.egg.Value > b.egg.Value end)

        for _, entry in ipairs(list) do
            local e = entry.egg
            local sub = string.format(
                "Preço: %s • Valor: %s • Rendimento total: %s\nCriaturas: %d • Chance melhor: %d%%",
                U.FormatNumber(e.Price), U.FormatNumber(e.Value),
                U.FormatNumber(entry.totalYield), #e.Creatures,
                (function() local m=0; for _,c in ipairs(e.Creatures) do if c.Chance>m then m=c.Chance end end return m end)()
            )
            Card(p_holder_wrap(holder), e.Name .. "  [" .. e.Rarity .. "]", sub, e.Rarity, function()
                -- [HOOK] exemplo: ReplicatedStorage.BuyEgg:FireServer(e.Name)
                Notify("Ovo selecionado", e.Name, 2, U.RarityColor(e.Rarity))
            end)
        end
    end

    -- wrapper para permitir re-render
    function p_holder_wrap(h) return h end

    render("")
    U.Track(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        if currentTab == "Ovos" then render(searchBox.Text) end
    end))
end

--============================================================
-- ABA: CRIATURAS
--============================================================
AddTab("Criaturas", "🐉")
do
    local p = tabs["Criaturas"]
    UI.Section(p, "Ranking")
    local holder, clear = UI.ListContainer(p)

    local function render(search: string)
        clear()
        local list = {}
        for _, c in ipairs(CreatureDatabase) do
            if search == "" or c.Name:lower():find(search:lower(), 1, true) then
                table.insert(list, c)
            end
        end
        table.sort(list, function(a, b) return a.Value > b.Value end)
        for i, c in ipairs(list) do
            local sub = string.format("#%d • %s • Valor: %s • Yield: %s • Ovo: %s • Chance: %d%%",
                i, c.Rarity, U.FormatNumber(c.Value), U.FormatNumber(c.Yield), c.Origin, c.Chance)
            Card(holder, c.Name, sub, c.Rarity)
        end
    end

    render("")
    U.Track(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        if currentTab == "Criaturas" then render(searchBox.Text) end
    end))
end

--============================================================
-- ABA: ROUBO
--============================================================
AddTab("Roubo", "🎯")
do
    local p = tabs["Roubo"]
    UI.Section(p, "Configuração")
    UI.Slider(p, "Cooldown (s)", 0, 120, Config.StealCooldown, function(v) Config.StealCooldown = v end)
    UI.Slider(p, "Distância máx (studs)", 5, 100, Config.StealDistance, function(v) Config.StealDistance = v end)

    UI.Section(p, "Alvos")
    local holder, clear = UI.ListContainer(p)

    local function refresh()
        clear()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local root = plr.Character:FindFirstChild("HumanoidRootPart")
                local myRoot = U.LocalRoot()
                if root and myRoot then
                    local d = U.Distance(root.Position, myRoot.Position)
                    local sub = string.format("Distância: %.1f studs", d)
                    Card(holder, plr.Name, sub, "Rare", function()
                        if not U.Debounce("steal_" .. plr.Name, Config.StealCooldown) then
                            Notify("Cooldown", "Aguarde antes de tentar novamente.", 2, Color3.fromRGB(255,180,40))
                            return
                        end
                        if d > Config.StealDistance then
                            Notify("Longe demais", "Aproxime-se do alvo.", 2, Color3.fromRGB(255,60,60))
                            return
                        end
                        -- [HOOK] ReplicatedStorage.StealRequest:FireServer(plr)
                        Notify("Roubo enviado", "Alvo: " .. plr.Name, 2)
                    end)
                end
            end
        end
    end

    refresh()
    U.Track(Players.PlayerAdded:Connect(refresh))
    U.Track(Players.PlayerRemoving:Connect(function() task.wait(0.1); refresh() end))
end

--============================================================
-- ABA: ESP
--============================================================
AddTab("ESP", "👁")
do
    local p = tabs["ESP"]
    UI.Section(p, "Ativar")
    UI.Toggle(p, "ESP geral", Config.ESP, function(v) Config.ESP = v end)
    UI.Toggle(p, "Jogadores", Config.PlayerESP, function(v) Config.PlayerESP = v end)
    UI.Toggle(p, "Ovos", Config.EggESP, function(v) Config.EggESP = v end)
    UI.Toggle(p, "Criaturas", Config.CreatureESP, function(v) Config.CreatureESP = v end)
    UI.Toggle(p, "Itens", Config.ItemESP, function(v) Config.ItemESP = v end)
    UI.Toggle(p, "Bases", Config.BaseESP, function(v) Config.BaseESP = v end)
    UI.Section(p, "Distância")
    UI.Slider(p, "Máx (studs)", 50, 2000, Config.MaxESPDistance, function(v) Config.MaxESPDistance = v end)
    UI.Section(p, "Info")
    Card(p, "ESP é apenas para objetos do seu jogo",
        "Exiba apenas informações que o jogador JÁ pode ver (ex.: destacar o ladrão recente).",
        "Legendary")
end

--============================================================
-- ABA: FARM
--============================================================
AddTab("Farm", "⚙")
do
    local p = tabs["Farm"]
    UI.Section(p, "Automações")
    UI.Toggle(p, "Auto Collect", Config.AutoCollect, function(v) Config.AutoCollect = v; Notify("Auto Collect", v and "Ligado" or "Desligado", 2) end)
    UI.Toggle(p, "Auto Hatch",   Config.AutoHatch,   function(v) Config.AutoHatch = v end)
    UI.Toggle(p, "Auto Sell",    Config.AutoSell,    function(v) Config.AutoSell = v end)
    UI.Toggle(p, "Auto Equip",   Config.AutoEquip,   function(v) Config.AutoEquip = v end)
    UI.Toggle(p, "Auto Claim",   Config.AutoClaim,   function(v) Config.AutoClaim = v end)
    UI.Toggle(p, "Auto Buy",     Config.AutoBuy,     function(v) Config.AutoBuy = v end)
    UI.Toggle(p, "Auto Rebirth", Config.AutoRebirth, function(v) Config.AutoRebirth = v end)
    UI.Toggle(p, "Auto Farm",    Config.AutoFarm,    function(v) Config.AutoFarm = v end)
    UI.Toggle(p, "Parar quando cheio", Config.StopWhenFull, function(v) Config.StopWhenFull = v end)
    UI.Section(p, "Filtros")
    UI.Slider(p, "Delay (s)", 0, 5, Config.AutomationDelay * 10, function(v) Config.AutomationDelay = v / 10 end)
    UI.Slider(p, "Valor mínimo", 0, 1_000_000_000, Config.MinimumValue, function(v) Config.MinimumValue = v end)
end

--============================================================
-- ABA: INVENTÁRIO
--============================================================
AddTab("Inventário", "🎒")
do
    local p = tabs["Inventário"]
    UI.Section(p, "Ações")
    UI.Button(p, "🔄 Atualizar inventário", function()
        -- [HOOK] ReplicatedStorage.RequestInventory:FireServer()
        Notify("Inventário", "Solicitado ao servidor.", 2)
    end)

    UI.Section(p, "Criaturas no inventário")
    local holder, clear = UI.ListContainer(p)
    -- [HOOK] Preencha com dados reais do servidor via RemoteEvent.
    -- Exemplo fictício de estrutura esperada:
    -- { Name = "Dragão", Rarity = "Epic", Value = 15000, Yield = 800 }
    local mockInventory = {
        { Name = "Galinha", Rarity = "Common", Value = 50, Yield = 10 },
        { Name = "Dragão",  Rarity = "Epic",   Value = 15_000, Yield = 800 },
    }
    for _, c in ipairs(mockInventory) do
        Card(holder, c.Name,
            string.format("%s • Valor: %s • Yield: %s",
                c.Rarity, U.FormatNumber(c.Value), U.FormatNumber(c.Yield)),
            c.Rarity, function()
                -- [HOOK] ReplicatedStorage.EquipCreature:FireServer(c.Name)
                Notify("Equipar", c.Name, 2)
            end)
    end
end

--============================================================
-- ABA: TELEPORTE
--============================================================
AddTab("Teleporte", "📡")
do
    local p = tabs["Teleporte"]
    UI.Section(p, "Locais do mapa")
    local holder = UI.ListContainer(p)
    -- [HOOK] Substitua por locais reais obtidos do seu servidor.
    local locations = {
        { Name = "Base",        Pos = Vector3.new(0, 10, 0) },
        { Name = "Loja",        Pos = Vector3.new(50, 10, 0) },
        { Name = "Área de Ovos", Pos = Vector3.new(-50, 10, 0) },
    }
    for _, loc in ipairs(locations) do
        Card(holder, loc.Name, "Posição: " .. tostring(loc.Pos), "Uncommon", function()
            local root = U.LocalRoot()
            if not root then return end
            -- [HOOK] Idealmente, o servidor valida e teleporta. Aqui, apenas setamos localmente.
            root.CFrame = CFrame.new(loc.Pos + Vector3.new(0, 3, 0))
            Notify("Teleporte", "Movido para " .. loc.Name, 2)
        end)
    end
end

--============================================================
-- ABA: CONFIGURAÇÕES
--============================================================
AddTab("Config", "🛠")
do
    local p = tabs["Config"]
    UI.Section(p, "Aparência")
    UI.Dropdown(p, "Tema:", { "Dark","Midnight","Light" }, Config.Theme, function(v)
        Config.Theme = v
        Notify("Tema", "Aplicado: " .. v .. " (reabra o menu para ver 100%)", 3)
    end)
    UI.Slider(p, "Transparência", 0, 100, Config.Transparency * 100, function(v)
        Config.Transparency = v / 100
        main.BackgroundTransparency = Config.Transparency
    end)

    UI.Section(p, "Sistema")
    UI.Toggle(p, "Notificações", Config.Notifications, function(v) Config.Notifications = v end)

    UI.Section(p, "Salvar")
    UI.Button(p, "💾 Salvar configurações", function()
        -- [HOOK] ReplicatedStorage.SaveSettings:FireServer(Config)
        Notify("Salvar", "Enviado ao servidor (ligue o RemoteEvent).", 3)
    end)
    UI.Button(p, "♻ Resetar padrões", function()
        Config.Transparency = 0.15
        main.BackgroundTransparency = Config.Transparency
        Notify("Reset", "Padrões restaurados.", 3)
    end)
end

--============================================================
-- LIMPEZA
--============================================================
U.Track(LocalPlayer.CharacterAdded:Connect(function()
    -- Re-render quando o personagem renasce (evita referências antigas)
    task.wait(0.5)
end))

game:BindToClose(function() U.Clear() end)
LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent then U.Clear() end
end)

Notify("Carregado", "Pressione " .. Config.UIKeybind.Name .. " ou toque no 🥚.", 4)
