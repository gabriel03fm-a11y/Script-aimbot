-- ============================================================
-- 10. UI CORE — RESPONSIVO (desktop / tablet / mobile)
-- ============================================================
local UICore = {}
UICore.__index = UICore

local COLORS = {
    bg=Color3.fromRGB(18,18,22), panel=Color3.fromRGB(25,25,32),
    panelAlt=Color3.fromRGB(32,32,40), accent=Color3.fromRGB(255,140,0),
    text=Color3.fromRGB(230,230,240), textDim=Color3.fromRGB(140,140,160),
    green=Color3.fromRGB(50,200,100), red=Color3.fromRGB(220,60,60),
    border=Color3.fromRGB(50,50,65),
}

-- Dimensões de design no DESKTOP (escala 1.0)
local DIMS_DESKTOP = {
    windowW = 560, windowH = 470,
    titleBarH = 40, tabBarH = 42,
    tabBtnW = 96, tabBtnH = 28,
    rowToggleH = 38,
    toggleTrackW = 46, toggleTrackH = 22, toggleKnob = 18,
    sliderH = 58, sliderTrackH = 6, sliderDragH = 22,
    inputH = 42,
    btnRowH = 34,
    scrollThickness = 5,
    titleFont = 15, labelFont = 14, btnFont = 13,
    pad = 14,
}

-- Dimensões de design no MOBILE (dedo ~44px mínimo)
local DIMS_TOUCH = {
    windowW = 560, windowH = 470,
    titleBarH = 54, tabBarH = 58,
    tabBtnW = 112, tabBtnH = 42,
    rowToggleH = 58,
    toggleTrackW = 62, toggleTrackH = 32, toggleKnob = 28,
    sliderH = 80, sliderTrackH = 12, sliderDragH = 46,
    inputH = 58,
    btnRowH = 54,
    scrollThickness = 10,
    titleFont = 17, labelFont = 16, btnFont = 15,
    pad = 16,
}

-- Dimensões ativas (definidas por build())
local D = DIMS_DESKTOP

-- ── Helpers de dispositivo ──────────────────────────────────
local function isTouch()
    return UserInputService.TouchEnabled
end

local function getViewport()
    local cam = workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

--[[
    Calcula a UIScale da janela.
    A janela tem tamanho fixo em "design" (560x470). A UIScale faz com que
    ela ocupe a fração correta da tela conforme o dispositivo:
      • Mobile : escala ≥ 1.0 (garante alvos de toque grandes)
      • Desktop: escala ≤ 1.0 (nunca fica exagerada)
--]]
local function computeUIScale(viewport)
    local maxW = viewport.X * 0.94
    local maxH = viewport.Y * 0.92
    local fit  = math.min(maxW / DIMS_DESKTOP.windowW, maxH / DIMS_DESKTOP.windowH)
    if isTouch() then
        return math.clamp(fit, 1.0, 1.8)
    else
        return math.clamp(fit, 0.75, 1.0)
    end
end

function UICore.new()
    return setmetatable({
        toggleStates = {},
        _notifContainer = nil,
        _uiscl = nil,
    }, UICore)
end

-- Helper de criação
function UICore:_create(className, props, parent)
    local obj = Instance.new(className)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then pcall(function() obj[k] = v end) end
    end
    if parent then obj.Parent = parent end
    return obj
end

-- ── Toggle ──────────────────────────────────────────────────
function UICore:_createToggle(parent, labelText, configKey, callback)
    local config = ConfigManager

    local frame = self:_create("Frame", {
        Name = "Toggle_" .. configKey,
        Size = UDim2.new(1, -20, 0, D.rowToggleH),
        BackgroundColor3 = COLORS.panelAlt,
        BorderSizePixel = 0,
    }, parent)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)

    self:_create("TextLabel", {
        Size = UDim2.new(1, -(D.toggleTrackW + 30), 1, 0),
        Position = UDim2.new(0, D.pad, 0, 0),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = COLORS.text,
        TextSize = D.labelFont,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)

    local track = self:_create("Frame", {
        Size = UDim2.new(0, D.toggleTrackW, 0, D.toggleTrackH),
        Position = UDim2.new(1, -(D.toggleTrackW + D.pad), 0.5, -D.toggleTrackH / 2),
        BackgroundColor3 = COLORS.border,
        BorderSizePixel = 0,
    }, frame)
    self:_create("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

    local knob = self:_create("Frame", {
        Size = UDim2.new(0, D.toggleKnob, 0, D.toggleKnob),
        Position = UDim2.new(0, 3, 0.5, -D.toggleKnob / 2),
        BackgroundColor3 = COLORS.textDim,
        BorderSizePixel = 0,
    }, track)
    self:_create("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

    -- Área de toque = linha inteira (mobile-friendly)
    local btn = self:_create("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
    }, frame)

    local onX  = D.toggleTrackW - D.toggleKnob - 3
    local offX = 3

    local state = config:get(configKey) or false
    self.toggleStates[configKey] = state

    local function updateVisual(on)
        TweenService:Create(track, TweenInfo.new(0.2), {
            BackgroundColor3 = on and COLORS.accent or COLORS.border
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.2), {
            Position = UDim2.new(0, on and onX or offX, 0.5, -D.toggleKnob / 2),
            BackgroundColor3 = on and Color3.new(1, 1, 1) or COLORS.textDim
        }):Play()
    end
    updateVisual(state)

    btn.MouseButton1Click:Connect(function()
        state = not state
        self.toggleStates[configKey] = state
        config:set(configKey, state)
        updateVisual(state)
        if callback then pcall(callback, state) end
    end)
    return frame
end

-- ── Slider ──────────────────────────────────────────────────
function UICore:_createSlider(parent, labelText, configKey, min, max, suffix)
    local config = ConfigManager
    suffix = suffix or ""

    local frame = self:_create("Frame", {
        Size = UDim2.new(1, -20, 0, D.sliderH),
        BackgroundColor3 = COLORS.panelAlt,
        BorderSizePixel = 0,
    }, parent)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)

    self:_create("TextLabel", {
        Size = UDim2.new(0.6, 0, 0, 24),
        Position = UDim2.new(0, D.pad, 0, 8),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = COLORS.text,
        TextSize = D.labelFont,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)

    local valueLabel = self:_create("TextLabel", {
        Size = UDim2.new(0.35, 0, 0, 24),
        Position = UDim2.new(0.62, 0, 0, 8),
        BackgroundTransparency = 1,
        Text = tostring(config:get(configKey)) .. suffix,
        TextColor3 = COLORS.accent,
        TextSize = D.labelFont,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, frame)

    -- Track
    local trackBg = self:_create("Frame", {
        Size = UDim2.new(1, -D.pad * 2, 0, D.sliderTrackH),
        Position = UDim2.new(0, D.pad, 1, -(D.sliderTrackH + 12)),
        BackgroundColor3 = COLORS.border,
        BorderSizePixel = 0,
    }, frame)
    self:_create("UICorner", { CornerRadius = UDim.new(1, 0) }, trackBg)

    local fill = self:_create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = COLORS.accent,
        BorderSizePixel = 0,
    }, trackBg)
    self:_create("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)

    -- Área de arraste ampliada (essencial em touch)
    local dragBtn = self:_create("TextButton", {
        Size = UDim2.new(1, D.pad * 2, 0, D.sliderDragH),
        Position = UDim2.new(0, -D.pad, 0.5, -D.sliderDragH / 2),
        BackgroundTransparency = 1,
        Text = "",
    }, trackBg)

    local function updateFromValue(val)
        val = math.clamp(val, min, max)
        local pct = (val - min) / math.max(max - min, 0.0001)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        valueLabel.Text = tostring(val) .. suffix
        config:set(configKey, val)
    end
    updateFromValue(config:get(configKey) or min)

    local dragging = false
    local function processInput(input)
        local tp = trackBg.AbsolutePosition
        local ts = trackBg.AbsoluteSize
        local pct = math.clamp((input.Position.X - tp.X) / math.max(ts.X, 1), 0, 1)
        updateFromValue(math.floor(min + (max - min) * pct))
    end

    dragBtn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            processInput(i)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then
            processInput(i)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    return frame
end

-- ── Input de texto ─────────────────────────────────────────
function UICore:_createInput(parent, labelText, configKey, placeholder)
    local frame = self:_create("Frame", {
        Size = UDim2.new(1, -20, 0, D.inputH),
        BackgroundColor3 = COLORS.panelAlt,
        BorderSizePixel = 0,
    }, parent)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)

    self:_create("TextLabel", {
        Size = UDim2.new(0.55, 0, 1, 0),
        Position = UDim2.new(0, D.pad, 0, 0),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = COLORS.text,
        TextSize = D.labelFont,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)

    local boxW = isTouch() and 120 or 90
    local box = self:_create("TextBox", {
        Size = UDim2.new(0, boxW, 0, D.inputH - 16),
        Position = UDim2.new(1, -(boxW + D.pad), 0.5, -(D.inputH - 16) / 2),
        BackgroundColor3 = COLORS.bg,
        Text = tostring(ConfigManager:get(configKey) or ""),
        TextColor3 = COLORS.accent,
        TextSize = D.labelFont,
        Font = Enum.Font.GothamBold,
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = COLORS.textDim,
        ClearTextOnFocus = false,
    }, frame)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 6) }, box)

    box.FocusLost:Connect(function()
        local num = tonumber(box.Text)
        ConfigManager:set(configKey, num or box.Text)
    end)
    return frame
end

-- ── Notificação ────────────────────────────────────────────
function UICore:notify(title, text, duration)
    if not ConfigManager:get("notifications") then return end
    if not self.screenGui then return end
    duration = duration or 3

    if not self._notifContainer or not self._notifContainer.Parent then
        -- Em mobile, notificações vão para o topo centralizadas (largura quase total)
        -- Em desktop, ficam no canto superior direito
        local containerProps
        if isTouch() then
            containerProps = {
                Name = "Notifications",
                Size = UDim2.new(1, -20, 0, 400),
                Position = UDim2.new(0, 10, 0, 10),
                BackgroundTransparency = 1,
                ZIndex = 500,
            }
        else
            containerProps = {
                Name = "Notifications",
                Size = UDim2.new(0, 300, 1, -20),
                Position = UDim2.new(1, -310, 0, 10),
                BackgroundTransparency = 1,
                ZIndex = 500,
            }
        end
        self._notifContainer = self:_create("Frame", containerProps, self.screenGui)
        self:_create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
            HorizontalAlignment = isTouch() and Enum.HorizontalAlignment.Center
                                or Enum.HorizontalAlignment.Right,
        }, self._notifContainer)
    end

    local notif = self:_create("Frame", {
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundColor3 = COLORS.panel,
        BorderSizePixel = 0,
    }, self._notifContainer)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 8) }, notif)
    self:_create("UIStroke", { Color = COLORS.accent, Thickness = 1, Transparency = 0.6 }, notif)

    self:_create("TextLabel", {
        Size = UDim2.new(1, -24, 0, 22),
        Position = UDim2.new(0, 14, 0, 6),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = COLORS.accent,
        TextSize = D.labelFont,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, notif)
    self:_create("TextLabel", {
        Size = UDim2.new(1, -24, 0, 18),
        Position = UDim2.new(0, 14, 0, 28),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = COLORS.textDim,
        TextSize = math.max(D.labelFont - 2, 11),
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, notif)

    -- Entrada deslizando
    local startY = isTouch() and UDim2.new(0, 0, 0, -60) or UDim2.new(1, 50, 0, 0)
    local endPos = UDim2.new(0, 0, 0, 0)
    notif.Position = startY
    TweenService:Create(notif, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        { Position = endPos }):Play()

    task.delay(duration, function()
        if notif and notif.Parent then
            local tw = TweenService:Create(notif, TweenInfo.new(0.3), {
                Position = startY,
                BackgroundTransparency = 1,
            })
            tw:Play()
            tw.Completed:Connect(function() notif:Destroy() end)
        end
    end)
end

-- ── Construção da UI ───────────────────────────────────────
function UICore:build()
    -- Escolhe o conjunto de dimensões
    D = isTouch() and DIMS_TOUCH or DIMS_DESKTOP

    local pg = LocalPlayer:WaitForChild("PlayerGui", 10)
    if not pg then warn("[BB] PlayerGui não encontrado") return end
    local existing = pg:FindFirstChild("BladeBallSuite")
    if existing then existing:Destroy() end

    -- Em touch, respeitamos os insets do sistema (barra de status / notch)
    self.screenGui = self:_create("ScreenGui", {
        Name = "BladeBallSuite",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = not isTouch(), -- mobile: respeita insets
    }, pg)
    State.ui.screenGui = self.screenGui

    -- ── JANELA PRINCIPAL ─────────────────────────────────
    local main = self:_create("Frame", {
        Name = "MainWindow",
        Size = UDim2.new(0, D.windowW, 0, D.windowH),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        BackgroundColor3 = COLORS.bg,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, self.screenGui)
    self.mainFrame = main
    self:_create("UICorner", { CornerRadius = UDim.new(0, 12) }, main)
    self:_create("UIStroke", { Color = COLORS.border, Thickness = 1 }, main)

    -- UIScale para responsividade
    local uiscl = Instance.new("UIScale")
    uiscl.Scale = computeUIScale(getViewport())
    uiscl.Parent = main
    self._uiscl = uiscl

    -- Reage à rotação / redimensionamento
    local cam = workspace.CurrentCamera
    if cam then
        cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            if uiscl and uiscl.Parent then
                uiscl.Scale = computeUIScale(getViewport())
            end
        end)
    end

    -- ── BARRA DE TÍTULO ──────────────────────────────────
    local titleBar = self:_create("Frame", {
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, D.titleBarH),
        BackgroundColor3 = COLORS.panel,
        BorderSizePixel = 0,
    }, main)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 12) }, titleBar)
    self:_create("Frame", {
        Size = UDim2.new(1, 0, 0, 12),
        Position = UDim2.new(0, 0, 1, -12),
        BackgroundColor3 = COLORS.panel,
        BorderSizePixel = 0,
    }, titleBar)

    self:_create("TextLabel", {
        Size = UDim2.new(1, -80, 1, 0),
        Position = UDim2.new(0, 16, 0, 0),
        BackgroundTransparency = 1,
        Text = "⚔  BLADE BALL SUITE",
        TextColor3 = COLORS.accent,
        TextSize = D.titleFont,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, titleBar)

    -- Botão fechar (maior em touch)
    local closeSize = isTouch() and 36 or 28
    local closeBtn = self:_create("TextButton", {
        Size = UDim2.new(0, closeSize, 0, closeSize),
        Position = UDim2.new(1, -(closeSize + 10), 0.5, -closeSize / 2),
        BackgroundColor3 = COLORS.red,
        Text = "✕",
        TextColor3 = Color3.new(1, 1, 1),
        TextSize = isTouch() and 18 or 14,
        Font = Enum.Font.GothamBold,
    }, titleBar)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 8) }, closeBtn)
    closeBtn.MouseButton1Click:Connect(function()
        main.Visible = false
        if State.ui.floatingBtn then State.ui.floatingBtn.Visible = true end
    end)

    -- Arrastar (funciona com toque e mouse automaticamente)
    local titleDrag = self:_create("TextButton", {
        Size = UDim2.new(1, -(closeSize + 20), 1, 0),
        BackgroundTransparency = 1,
        Text = "",
    }, titleBar)
    local dragging, dragStart, startPos
    titleDrag.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = i.Position
            startPos = main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    -- ── BARRA DE ABAS ─────────────────────────────────────
    local tabBar = self:_create("Frame", {
        Name = "TabBar",
        Size = UDim2.new(1, 0, 0, D.tabBarH),
        Position = UDim2.new(0, 0, 0, D.titleBarH),
        BackgroundColor3 = COLORS.panel,
        BorderSizePixel = 0,
    }, main)
    self:_create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        VerticalAlignment = Enum.VerticalAlignment.Center,
    }, tabBar)
    self:_create("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
    }, tabBar)

    -- ── CONTEÚDO ──────────────────────────────────────────
    local content = self:_create("Frame", {
        Name = "Content",
        Size = UDim2.new(1, 0, 1, -(D.titleBarH + D.tabBarH)),
        Position = UDim2.new(0, 0, 0, D.titleBarH + D.tabBarH),
        BackgroundTransparency = 1,
    }, main)

    local tabNames = { "Combat", "Visuals", "Settings" }
    local tabContents, tabButtons = {}, {}

    for i, name in ipairs(tabNames) do
        local tabBtn = self:_create("TextButton", {
            Name = "Tab_" .. name,
            Size = UDim2.new(0, D.tabBtnW, 0, D.tabBtnH),
            BackgroundColor3 = (i == 1) and COLORS.accent or COLORS.panelAlt,
            Text = name,
            TextColor3 = (i == 1) and Color3.new(1, 1, 1) or COLORS.textDim,
            TextSize = D.btnFont,
            Font = Enum.Font.GothamBold,
            AutoButtonColor = true,
        }, tabBar)
        self:_create("UICorner", { CornerRadius = UDim.new(0, 8) }, tabBtn)
        tabButtons[name] = tabBtn

        local scroll = self:_create("ScrollingFrame", {
            Name = "Scroll_" .. name,
            Size = UDim2.new(1, -20, 1, -10),
            Position = UDim2.new(0, 10, 0, 6),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = D.scrollThickness,
            ScrollBarImageColor3 = COLORS.accent,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            Visible = (i == 1),
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        }, content)
        self:_create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
        }, scroll)

        tabContents[name] = scroll

        tabBtn.MouseButton1Click:Connect(function()
            for _, other in pairs(tabButtons) do
                other.BackgroundColor3 = COLORS.panelAlt
                other.TextColor3 = COLORS.textDim
            end
            tabBtn.BackgroundColor3 = COLORS.accent
            tabBtn.TextColor3 = Color3.new(1, 1, 1)
            for _, sc in pairs(tabContents) do sc.Visible = false end
            scroll.Visible = true
        end)
    end

    -- Recalcula CanvasSize
    for _, scroll in pairs(tabContents) do
        local layout = scroll:FindFirstChildOfClass("UIListLayout")
        local function updateCanvas()
            if layout then
                scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 12)
            end
        end
        if layout then
            layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
        end
        scroll.ChildAdded:Connect(function() task.defer(updateCanvas) end)
        scroll.ChildRemoved:Connect(function() task.defer(updateCanvas) end)
        task.defer(updateCanvas)
    end

    -- ═════════ ABA COMBAT ═════════
    local combat = tabContents["Combat"]
    self:_create("TextLabel", {
        Size = UDim2.new(1, -20, 0, 26),
        BackgroundTransparency = 1,
        Text = "⚔  COMBAT",
        TextColor3 = COLORS.accent,
        TextSize = D.titleFont,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, combat)

    self:_createToggle(combat, "Auto Parry", "autoParryEnabled", function(on)
        UICore:notify("Auto Parry", on and "Ativado" or "Desativado", 2)
    end)
    self:_createToggle(combat, "Manual Spam (AP / TB)", "manualSpamEnabled", function(on)
        if State.ui.manualSpamBtn then State.ui.manualSpamBtn:setVisible(on) end
        UICore:notify("Manual Spam", on and "Ativado" or "Desativado", 2)
    end)
    self:_createSlider(combat, "Delay (pode ser negativo)", "delayMs", -100, 200, " ms")
    self:_createSlider(combat, "Range de ativação", "parryRange", 5, 60, " studs")
    self:_createSlider(combat, "Sensitivity", "sensitivity", 0, 100, "%")
    self:_createToggle(combat, "Legit Mode (humanizado)", "legitMode")
    self:_createToggle(combat, "Fast React Mode", "fastReactMode")
    self:_createToggle(combat, "Anti-Repeat Parry", "antiRepeatEnabled")
    self:_createSlider(combat, "Spam Frequency", "spamFrequency", 10, 200, " ms")

    -- ═════════ ABA VISUALS ═════════
    local vis = tabContents["Visuals"]
    self:_create("TextLabel", {
        Size = UDim2.new(1, -20, 0, 26),
        BackgroundTransparency = 1,
        Text = "👁  VISUALS",
        TextColor3 = COLORS.accent,
        TextSize = D.titleFont,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, vis)
    self:_createToggle(vis, "Ball ESP", "ballESP")
    self:_createToggle(vis, "Ball Highlight", "ballHighlight")
    self:_createToggle(vis, "Show Trajectory", "showTrajectory")
    self:_createToggle(vis, "Show Distance", "showDistance")
    self:_createToggle(vis, "Show Speed", "showSpeed")
    self:_createToggle(vis, "Player ESP", "playerESP")
    self:_createToggle(vis, "Threat Indicator", "showThreatIndicator")

    -- ═════════ ABA SETTINGS ═════════
    local st = tabContents["Settings"]
    self:_create("TextLabel", {
        Size = UDim2.new(1, -20, 0, 26),
        BackgroundTransparency = 1,
        Text = "⚙  SETTINGS",
        TextColor3 = COLORS.accent,
        TextSize = D.titleFont,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, st)
    self:_createToggle(st, "Notificações", "notifications")
    self:_createInput(st, "Tecla — Menu",        "keybindMenu",       "RightShift")
    self:_createInput(st, "Tecla — Auto Parry",  "keybindAutoParry",  "F")
    self:_createInput(st, "Tecla — Manual Spam", "keybindManualSpam", "G")
    self:_createInput(st, "Tecla — ESP",         "keybindESP",        "H")
    self:_createInput(st, "Tecla — Legit Mode",  "keybindLegitMode",  "J")

    -- Botões Salvar / Carregar / Reset — em touch empilham em duas linhas se preciso
    local btnRow = self:_create("Frame", {
        Size = UDim2.new(1, -20, 0, D.btnRowH),
        BackgroundTransparency = 1,
    }, st)

    local function makeButton(label, color, xPos, w, onClick)
        local b = self:_create("TextButton", {
            Size = UDim2.new(w, -4, 1, 0),
            Position = UDim2.new(xPos, 0, 0, 0),
            BackgroundColor3 = color,
            Text = label,
            TextColor3 = Color3.new(1, 1, 1),
            TextSize = D.btnFont,
            Font = Enum.Font.GothamBold,
        }, btnRow)
        self:_create("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
        b.MouseButton1Click:Connect(onClick)
        return b
    end

    makeButton("Salvar",   COLORS.green,               0.00, 0.32, function()
        UICore:notify("Config", ConfigManager:save() and "Salvo!" or "Falha ao salvar.", 2)
    end)
    makeButton("Carregar", Color3.fromRGB(60,120,200), 0.34, 0.32, function()
        UICore:notify("Config", ConfigManager:load() and "Carregado!" or "Nada salvo.", 2)
    end)
    makeButton("Reset",    COLORS.red,                 0.68, 0.32, function()
        ConfigManager:reset()
        UICore:notify("Config", "Restaurado.", 2)
    end)

    -- ── BOTÃO FLUTUANTE ──────────────────────────────────
    local fbSize = isTouch() and 64 or 50
    local floatingBtn = self:_create("TextButton", {
        Name = "FloatingButton",
        Size = UDim2.new(0, fbSize, 0, fbSize),
        Position = UDim2.new(0, 20, 0.5, -fbSize / 2),
        BackgroundColor3 = COLORS.accent,
        Text = "⚔",
        TextColor3 = Color3.new(1, 1, 1),
        TextSize = isTouch() and 28 or 22,
        Font = Enum.Font.GothamBold,
        Visible = false,
        ZIndex = 10,
    }, self.screenGui)
    self:_create("UICorner", { CornerRadius = UDim.new(1, 0) }, floatingBtn)
    floatingBtn.MouseButton1Click:Connect(function()
        main.Visible = true
        floatingBtn.Visible = false
    end)
    State.ui.floatingBtn = floatingBtn
    State.ui.mainWindow = main

    -- ── INDICADOR DE AMEAÇA ──────────────────────────────
    local threatW = isTouch() and 200 or 140
    local threatH = isTouch() and 34  or 26
    local threat = self:_create("Frame", {
        Name = "ThreatIndicator",
        Size = UDim2.new(0, threatW, 0, threatH),
        Position = UDim2.new(0.5, -threatW / 2, 0, 10),
        BackgroundColor3 = Color3.fromRGB(255, 40, 40),
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 100,
    }, self.screenGui)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 8) }, threat)
    self:_create("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "⚠ THREAT DETECTED",
        TextColor3 = Color3.new(1, 1, 1),
        TextSize = isTouch() and 14 or 11,
        Font = Enum.Font.GothamBold,
    }, threat)
    State.ui.threatIndicator = threat

    -- ── FPS / PING ───────────────────────────────────────
    local statsW = isTouch() and 280 or 230
    local statsH = isTouch() and 26  or 22
    local stats = self:_create("Frame", {
        Name = "Stats",
        Size = UDim2.new(0, statsW, 0, statsH),
        Position = UDim2.new(1, -(statsW + 10), 1, -(statsH + 10)),
        BackgroundColor3 = COLORS.panel,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        ZIndex = 5,
    }, self.screenGui)
    self:_create("UICorner", { CornerRadius = UDim.new(0, 6) }, stats)
    local statsLabel = self:_create("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "FPS: -- | Ping: -- | AP: OFF",
        TextColor3 = COLORS.textDim,
        TextSize = isTouch() and 12 or 11,
        Font = Enum.Font.Gotham,
    }, stats)
    State.ui.statsLabel = statsLabel

    -- ── OVERLAY MANUAL SPAM ──────────────────────────────
    State.ui.manualSpamBtn = ManualSpam.new()
    State.ui.manualSpamBtn:create(self.screenGui)

    return self
end

function UICore:startStatsLoop()
    local frames, lastTime = 0, tick()
    RunService.RenderStepped:Connect(function()
        frames = frames + 1
        local now = tick()
        if now - lastTime >= 1 then
            State.fps = frames; frames = 0; lastTime = now
        end
    end)
    task.spawn(function()
        while task.wait(0.5) do
            pcall(function()
                State.ping = LocalPlayer:GetNetworkPing() * 1000
                if State.ui.statsLabel then
                    State.ui.statsLabel.Text = string.format(
                        "FPS: %d | Ping: %.0fms | AP: %s | MS: %s",
                        State.fps, State.ping,
                        ConfigManager:get("autoParryEnabled")  and "ON" or "OFF",
                        ConfigManager:get("manualSpamEnabled") and "ON" or "OFF"
                    )
                end
            end)
        end
    end)
end
