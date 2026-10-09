--[[
    ============================================================
    Steal An Egg — Clean Implementation (Single File)
    ============================================================
    Autor: Clean-room reimplementation
    Uso:   Executor Roblox (Synapse/Krnl/Fluxus/Delta/etc.)
    
    Funcionalidades:
      - Scan automático de ovos no workspace
      - Filtro por valor mínimo (ex: 1B+)
      - Filtro por raridade
      - Lista de ovos com nome, valor, raridade e criaturas
      - Ordenação por valor (maior -> menor)
      - Auto Steal (loop controlado)
      - Instant Steal (HoldDuration = 0)
      - Start/Stop controls
      - Tratamento de erros seguro (pcall)
    
    Observação:
      Algumas ações dependem de código server-side (spawn de ovos,
      bypass de guardiões, validação de hold) e NÃO podem ser
      reproduzidas apenas pelo cliente.
    ============================================================
--]]

-- ============================================================
-- SERVIÇOS
-- ============================================================
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

-- ============================================================
-- CONFIG (módulo interno)
-- ============================================================
local Config = {
    MinimumValue        = 0,       -- valor mínimo em número (ex: 1e9 = 1B)
    MinimumRarity       = 1,       -- 1=Common ... 8=Secret
    StealDelay          = 0.5,     -- delay entre tentativas (s)
    ScanInterval        = 2,       -- intervalo de re-scan (s)

    AutoStealEnabled    = false,
    InstantStealEnabled = true,
    AutoReturnEnabled   = false,
    ESPEnabled          = false,

    RarityOrder = {
        Common    = 1,
        Uncommon  = 2,
        Rare      = 3,
        Epic      = 4,
        Legendary = 5,
        Mythic    = 6,
        Cosmic    = 7,
        Secret    = 8,
    },
}

-- Converte strings tipo "1.5B", "200M", "3T" em número
function Config.ParseValue(str)
    if type(str) == "number" then return str end
    if type(str) ~= "string" then return 0 end
    str = str:upper():gsub("%s", "")
    local num = tonumber(str:match("^[%d%.]+"))
    if not num then return 0 end
    if str:find("K") then return num * 1e3
    elseif str:find("M") then return num * 1e6
    elseif str:find("B") then return num * 1e9
    elseif str:find("T") then return num * 1e12
    else return num end
end

-- Formata número para exibição (ex: 2500000000 -> "2.5B")
function Config.FormatValue(n)
    if type(n) ~= "number" then return tostring(n) end
    if n >= 1e12 then return string.format("%.2fT", n / 1e12)
    elseif n >= 1e9 then return string.format("%.2fB", n / 1e9)
    elseif n >= 1e6 then return string.format("%.2fM", n / 1e6)
    elseif n >= 1e3 then return string.format("%.2fK", n / 1e3)
    else return tostring(math.floor(n)) end
end

-- ============================================================
-- BANCO DE DADOS DE OVOS (fallback caso atributos não existam)
-- ============================================================
local EggDatabase = {
    ["Chicken Egg"]    = { value = 1,     rarity = "Common",    creatures = {"Chicken"} },
    ["Dog Egg"]        = { value = 2,     rarity = "Common",    creatures = {"Dog"} },
    ["Cat Egg"]        = { value = 5,     rarity = "Common",    creatures = {"Cat"} },
    ["Bird Egg"]       = { value = 8,     rarity = "Uncommon",  creatures = {"Bird"} },
    ["Owl Egg"]        = { value = 35,    rarity = "Rare",      creatures = {"Owl"} },
    ["Raccoon Egg"]    = { value = 45,    rarity = "Rare",      creatures = {"Raccoon"} },
    ["Fox Egg"]        = { value = 180,   rarity = "Epic",      creatures = {"Fox"} },
    ["Bear Egg"]       = { value = 240,   rarity = "Epic",      creatures = {"Bear"} },
    ["Patapim Egg"]    = { value = 1800,  rarity = "Legendary", creatures = {"Brr Brr Patapim"} },
    ["Nightflame Egg"] = { value = 3e9,   rarity = "Mythic",    creatures = {"Nightflame"} },
    ["Mecha Egg"]      = { value = 4e9,   rarity = "Cosmic",    creatures = {"Mecha Dreadscale"} },
    ["Secret Egg"]     = { value = 1e10,  rarity = "Secret",    creatures = {"???"} },
}

-- ============================================================
-- EGG SCANNER (detecção)
-- ============================================================
local EggScanner = {}
EggScanner._cached   = {}
EggScanner._lastScan = 0

function EggScanner.Scan()
    local eggs = {}
    for _, d in ipairs(Workspace:GetDescendants()) do
        local isEgg = false
        if d:IsA("Model") then
            if d:GetAttribute("EggName") or d:GetAttribute("EggValue") then
                isEgg = true
            elseif d.Name:find("Egg") then
                isEgg = true
            end
        end

        if isEgg then
            local name    = d:GetAttribute("EggName")  or d.Name
            local value   = d:GetAttribute("EggValue") or 0
            local rarity  = d:GetAttribute("EggRarity") or nil
            local creatures = d:GetAttribute("PossibleCreatures")

            -- Fallback no banco de dados
            local db = EggDatabase[name]
            if db then
                if value == 0 then value = db.value end
                if not rarity then rarity = db.rarity end
                if not creatures then creatures = db.creatures end
            end

            value   = tonumber(value) or 0
            rarity  = rarity or "Common"
            creatures = creatures or {}

            if type(creatures) == "string" then
                local t = {}
                for c in creatures:gmatch("[^,]+") do
                    table.insert(t, c:match("^%s*(.-)%s*$"))
                end
                creatures = t
            end

            table.insert(eggs, {
                instance  = d,
                name      = name,
                value     = value,
                rarity    = rarity,
                creatures = creatures,
            })
        end
    end
    return eggs
end

function EggScanner.GetCached()
    if (os.clock() - EggScanner._lastScan) > Config.ScanInterval then
        EggScanner._cached   = EggScanner.Scan()
        EggScanner._lastScan = os.clock()
    end
    return EggScanner._cached
end

function EggScanner.Invalidate()
    EggScanner._lastScan = 0
end

-- ============================================================
-- FILTER (filtragem e ordenação)
-- ============================================================
local Filter = {}

function Filter.Apply(eggs)
    local out = {}
    for _, egg in ipairs(eggs) do
        local rar = Config.RarityOrder[egg.rarity] or 1
        if egg.value >= Config.MinimumValue and rar >= Config.MinimumRarity then
            table.insert(out, egg)
        end
    end
    return out
end

function Filter.SortByValue(eggs)
    table.sort(eggs, function(a, b) return a.value > b.value end)
    return eggs
end

function Filter.GetBest(eggs)
    local s = Filter.SortByValue(eggs)
    return s[1]
end

function Filter.GetWorst(eggs)
    local s = Filter.SortByValue(eggs)
    return s[#s]
end

-- ============================================================
-- STEAL LOGIC (roubo)
-- ============================================================
local StealLogic = {}
StealLogic._lastAttempt = 0
StealLogic._conn        = nil

local function getRoot()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:FindFirstChild("HumanoidRootPart")
end

function StealLogic.TeleportTo(egg)
    local root = getRoot()
    if not root or not egg.instance then return end
    local pos = egg.instance:GetPivot().Position
    pcall(function()
        root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    end)
    task.wait(0.08)
end

function StealLogic.TriggerPrompt(egg)
    if not egg.instance then return false end
    local prompt = egg.instance:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not prompt then return false end

    if Config.InstantStealEnabled then
        pcall(function() prompt.HoldDuration = 0 end)
    end

    local ok = pcall(function()
        prompt:InputHoldBegin()
        task.wait(0.05)
        prompt:InputHoldEnd()
    end)
    return ok
end

function StealLogic.StealBestEgg()
    local eggs     = EggScanner.GetCached()
    local filtered = Filter.Apply(eggs)
    if #filtered == 0 then return false end

    local best = Filter.GetBest(filtered)
    if not best then return false end

    StealLogic.TeleportTo(best)
    local ok = StealLogic.TriggerPrompt(best)
    if ok then EggScanner.Invalidate() end
    return ok
end

function StealLogic.StartAutoSteal()
    if StealLogic._conn then return end
    StealLogic._conn = RunService.Heartbeat:Connect(function()
        if not Config.AutoStealEnabled then return end
        if (os.clock() - StealLogic._lastAttempt) < Config.StealDelay then return end
        StealLogic._lastAttempt = os.clock()
        pcall(StealLogic.StealBestEgg)
    end)
end

function StealLogic.StopAutoSteal()
    if StealLogic._conn then
        StealLogic._conn:Disconnect()
        StealLogic._conn = nil
    end
end

-- ============================================================
-- UI (interface gráfica)
-- ============================================================
local UI = {}
UI._gui = nil
UI._dragging = false
UI._dragStart = nil
UI._frame = nil

local function newInstance(class, props)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        inst[k] = v
    end
    return inst
end

function UI.Create()
    if UI._gui then UI._gui:Destroy() end

    local gui = newInstance("ScreenGui", {
        Name = "StealAnEggCleanUI",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = LocalPlayer:WaitForChild("PlayerGui"),
    })
    UI._gui = gui

    -- Frame principal
    local frame = newInstance("Frame", {
        Size = UDim2.new(0, 560, 0, 440),
        Position = UDim2.new(0.5, -280, 0.5, -220),
        BackgroundColor3 = Color3.fromRGB(25, 27, 38),
        BorderSizePixel = 0,
        Parent = gui,
    })
    UI._frame = frame
    newInstance("UICorner", { CornerRadius = UDim.new(0, 10), Parent = frame })
    newInstance("UIStroke", {
        Color = Color3.fromRGB(80, 90, 130),
        Thickness = 1,
        Parent = frame,
    })

    -- Barra de título (arrastável)
    local titleBar = newInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = Color3.fromRGB(40, 45, 65),
        BorderSizePixel = 0,
        Parent = frame,
    })
    newInstance("UICorner", { CornerRadius = UDim.new(0, 10), Parent = titleBar })

    newInstance("TextLabel", {
        Size = UDim2.new(1, -100, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1,
        Text = "🥚 Steal An Egg — Clean UI",
        TextColor3 = Color3.fromRGB(240, 240, 255),
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar,
    })

    -- Botão fechar
    local closeBtn = newInstance("TextButton", {
        Size = UDim2.new(0, 30, 0, 30),
        Position = UDim2.new(1, -36, 0, 3),
        BackgroundColor3 = Color3.fromRGB(220, 70, 70),
        Text = "✕",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        BorderSizePixel = 0,
        Parent = titleBar,
    })
    newInstance("UICorner", { CornerRadius = UDim.new(0, 6), Parent = closeBtn })
    closeBtn.MouseButton1Click:Connect(function()
        gui.Enabled = false
    end)

    -- Drag
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            UI._dragging = true
            UI._dragStart = input.Position - Vector3.new(frame.AbsolutePosition.X, frame.AbsolutePosition.Y, 0)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            UI._dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if UI._dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local newPos = input.Position - UI._dragStart
            frame.Position = UDim2.new(0, newPos.X, 0, newPos.Y)
        end
    end)

    -- ============ Barra de status ============
    local statusLabel = newInstance("TextLabel", {
        Size = UDim2.new(1, -20, 0, 24),
        Position = UDim2.new(0, 10, 0, 42),
        BackgroundTransparency = 1,
        Text = "Status: Idle",
        TextColor3 = Color3.fromRGB(180, 220, 180),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    -- ============ Lista de ovos ============
    local listFrame = newInstance("ScrollingFrame", {
        Size = UDim2.new(1, -20, 0, 200),
        Position = UDim2.new(0, 10, 0, 70),
        BackgroundColor3 = Color3.fromRGB(18, 20, 28),
        BorderSizePixel = 0,
        ScrollBarThickness = 6,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Parent = frame,
    })
    newInstance("UICorner", { CornerRadius = UDim.new(0, 6), Parent = listFrame })
    newInstance("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = listFrame,
    })

    local function addRow(text, bgColor)
        local row = newInstance("TextLabel", {
            Size = UDim2.new(1, -8, 0, 24),
            BackgroundColor3 = bgColor or Color3.fromRGB(28, 30, 42),
            BackgroundTransparency = 0,
            Text = text,
            TextColor3 = Color3.fromRGB(230, 230, 240),
            Font = Enum.Font.Code,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            BorderSizePixel = 0,
            Parent = listFrame,
        })
        newInstance("UICorner", { CornerRadius = UDim.new(0, 4), Parent = row })
        return row
    end

    -- Header da lista
    addRow(string.format("%-22s %-12s %-12s %s", "OVO", "VALOR", "RARIDADE", "CRIATURAS"),
        Color3.fromRGB(45, 50, 70))

    local function refreshList()
        -- remove todas as linhas exceto header e layout
        for _, child in ipairs(listFrame:GetChildren()) do
            if child:IsA("TextLabel") then child:Destroy() end
        end
        addRow(string.format("%-22s %-12s %-12s %s", "OVO", "VALOR", "RARIDADE", "CRIATURAS"),
            Color3.fromRGB(45, 50, 70))

        local eggs = EggScanner.Scan()
        local sorted = Filter.SortByValue(eggs)
        for i, egg in ipairs(sorted) do
            local creatureStr = table.concat(egg.creatures, ", ")
            if #creatureStr > 25 then creatureStr = creatureStr:sub(1, 25) .. "..." end
            local name = egg.name
            if #name > 22 then name = name:sub(1, 22) end
            local line = string.format("%-22s %-12s %-12s %s",
                name,
                Config.FormatValue(egg.value),
                egg.rarity,
                creatureStr
            )
            addRow(line, i % 2 == 0 and Color3.fromRGB(28, 30, 42)
                            or Color3.fromRGB(22, 24, 34))
        end
        listFrame.CanvasSize = UDim2.new(0, 0, 0, (#sorted + 1) * 26)
        statusLabel.Text = string.format("Status: %d ovos detectados", #sorted)
    end

    -- ============ Controles ============
    local controlsY = 280

    local function makeButton(text, x, width, color, callback)
        local b = newInstance("TextButton", {
            Size = UDim2.new(0, width, 0, 30),
            Position = UDim2.new(0, x, 0, controlsY),
            BackgroundColor3 = color or Color3.fromRGB(60, 80, 130),
            Text = text,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            BorderSizePixel = 0,
            Parent = frame,
        })
        newInstance("UICorner", { CornerRadius = UDim.new(0, 6), Parent = b })
        b.MouseButton1Click:Connect(callback)
        return b
    end

    makeButton("🔄 Refresh", 10, 110, Color3.fromRGB(60, 100, 160), function()
        EggScanner.Invalidate()
        refreshList()
    end)

    makeButton("▶ Start Auto Steal", 128, 130, Color3.fromRGB(50, 140, 70), function()
        Config.AutoStealEnabled = true
        StealLogic.StartAutoSteal()
        statusLabel.Text = "Status: Auto Steal ATIVO"
        statusLabel.TextColor3 = Color3.fromRGB(140, 240, 140)
    end)

    makeButton("⏹ Stop", 266, 90, Color3.fromRGB(150, 60, 60), function()
        Config.AutoStealEnabled = false
        StealLogic.StopAutoSteal()
        statusLabel.Text = "Status: Auto Steal PARADO"
        statusLabel.TextColor3 = Color3.fromRGB(240, 140, 140)
    end)

    makeButton("⚡ Steal Once", 364, 110, Color3.fromRGB(150, 110, 40), function()
        local ok = StealLogic.StealBestEgg()
        statusLabel.Text = ok and "Status: Roubo bem-sucedido" or "Status: Nenhum ovo válido"
    end)

    makeButton("👁 ESP", 482, 60, Color3.fromRGB(80, 80, 120), function()
        Config.ESPEnabled = not Config.ESPEnabled
        -- implementação simples: highlight via SelectionBox
        for _, egg in ipairs(EggScanner.Scan()) do
            if egg.instance then
                if Config.ESPEnabled then
                    if not egg.instance:FindFirstChild("ESPBox") then
                        local box = Instance.new("SelectionBox")
                        box.Name = "ESPBox"
                        box.Adornee = egg.instance
                        box.Color3 = Color3.fromRGB(0, 255, 100)
                        box.LineThickness = 0.05
                        box.Parent = egg.instance
                    end
                else
                    local box = egg.instance:FindFirstChild("ESPBox")
                    if box then box:Destroy() end
                end
            end
        end
    end)

    -- ============ Filtros ============
    local filterY = 320

    -- Filtro de valor mínimo
    newInstance("TextLabel", {
        Size = UDim2.new(0, 130, 0, 24),
        Position = UDim2.new(0, 10, 0, filterY),
        BackgroundTransparency = 1,
        Text = "Valor mínimo:",
        TextColor3 = Color3.fromRGB(220, 220, 240),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local valueBox = newInstance("TextBox", {
        Size = UDim2.new(0, 120, 0, 26),
        Position = UDim2.new(0, 140, 0, filterY),
        BackgroundColor3 = Color3.fromRGB(35, 38, 55),
        Text = "",
        PlaceholderText = "ex: 1B / 500M",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.Code,
        TextSize = 13,
        BorderSizePixel = 0,
        Parent = frame,
    })
    newInstance("UICorner", { CornerRadius = UDim.new(0, 6), Parent = valueBox })

    valueBox.FocusLost:Connect(function()
        local txt = valueBox.Text
        if txt == "" then
            Config.MinimumValue = 0
        else
            Config.MinimumValue = Config.ParseValue(txt)
        end
        refreshList()
    end)

    -- Filtro de raridade
    newInstance("TextLabel", {
        Size = UDim2.new(0, 130, 0, 24),
        Position = UDim2.new(0, 270, 0, filterY),
        BackgroundTransparency = 1,
        Text = "Raridade mínima:",
        TextColor3 = Color3.fromRGB(220, 220, 240),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local rarityOptions = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret"}
    local rarityIndex = 1

    local rarityBtn = newInstance("TextButton", {
        Size = UDim2.new(0, 130, 0, 26),
        Position = UDim2.new(0, 400, 0, filterY),
        BackgroundColor3 = Color3.fromRGB(60, 70, 110),
        Text = "Common",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        BorderSizePixel = 0,
        Parent = frame,
    })
    newInstance("UICorner", { CornerRadius = UDim.new(0, 6), Parent = rarityBtn })

    rarityBtn.MouseButton1Click:Connect(function()
        rarityIndex = rarityIndex + 1
        if rarityIndex > #rarityOptions then rarityIndex = 1 end
        local r = rarityOptions[rarityIndex]
        rarityBtn.Text = r
        Config.MinimumRarity = Config.RarityOrder[r] or 1
        refreshList()
    end)

    -- ============ Info do executor ============
    newInstance("TextLabel", {
        Size = UDim2.new(1, -20, 0, 20),
        Position = UDim2.new(0, 10, 1, -26),
        BackgroundTransparency = 1,
        Text = "Instant Steal: " .. (Config.InstantStealEnabled and "ON" or "OFF") ..
               "  |  Delay: " .. Config.StealDelay .. "s",
        TextColor3 = Color3.fromRGB(150, 150, 180),
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    refreshList()

    -- Refresh automático a cada 5 segundos
    task.spawn(function()
        while UI._gui == gui do
            task.wait(5)
            pcall(refreshList)
        end
    end)

    return gui
end

-- ============================================================
-- MAIN (ponto de entrada)
-- ============================================================
local function safeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        warn("[StealAnEggClean] Erro: " .. tostring(err))
    end
    return ok
end

safeCall(function()
    UI.Create()
    print("[StealAnEggClean] Carregado com sucesso!")
end)

-- Atalho para mostrar/esconder UI com RightShift
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        if UI._gui then UI._gui.Enabled = not UI._gui.Enabled end
    end
end)
