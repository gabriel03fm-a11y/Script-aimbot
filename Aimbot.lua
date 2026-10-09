--[[
====================================================================
   SISTEMA COMPLETO — AIMBOT + ESP + UI MODERNA (SCRIPT ÚNICO)
   Local: StarterPlayer > StarterPlayerScripts (LocalScript)
   Autor: (personalize)
   Compatível com PC e Celular (UI responsiva)
====================================================================
]]

--==================== SERVIÇOS ====================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

--==================== CONFIGURAÇÕES GLOBAIS ====================
local Config = {
	Aimbot = {
		Enabled     = false,
		FOV         = 120,        -- raio em pixels
		MaxDistance = 500,        -- distância em studs
		TargetPart  = "Head",     -- Head | UpperTorso | HumanoidRootPart
		Smoothness  = 0.25,       -- 0.05 (lento) → 1 (instantâneo)
		WallCheck   = false,      -- Line of Sight (raycast)
		ShowFOV     = true,
	},
	ESP = {
		Enabled      = false,
		ShowName     = true,
		ShowDistance = true,
		Box          = true,
		Highlight    = true,
		TextSize     = 14,
		Color        = Color3.fromRGB(0, 170, 255),
	},
}

--==================== TEMA (fácil de personalizar) ====================
local Theme = {
	Background = Color3.fromRGB(16, 16, 20),
	Panel      = Color3.fromRGB(24, 24, 30),
	Element    = Color3.fromRGB(34, 34, 42),
	Accent     = Color3.fromRGB(0, 170, 255),
	Text       = Color3.fromRGB(235, 235, 240),
	SubText    = Color3.fromRGB(150, 150, 160),
	ToggleOff  = Color3.fromRGB(58, 58, 68),
}

local ColorPalette = {
	Color3.fromRGB(0, 170, 255),
	Color3.fromRGB(255, 60, 60),
	Color3.fromRGB(60, 255, 120),
	Color3.fromRGB(255, 200, 0),
	Color3.fromRGB(200, 80, 255),
	Color3.fromRGB(255, 255, 255),
}
local paletteIndex = 1

--==================== HELPERS ====================
local function new(class, props, parent)
	local obj = Instance.new(class)
	for k, v in pairs(props) do obj[k] = v end
	obj.Parent = parent
	return obj
end

--==================== SCREEN GUI ====================
local screenGui = new("ScreenGui", {
	Name = "ModernSystemUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, LocalPlayer:WaitForChild("PlayerGui"))

--==================== CÍRCULO DO FOV ====================
local fovCircle = new("Frame", {
	Name = "FOVCircle",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 3,
}, screenGui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, fovCircle)
local fovStroke = new("UIStroke", {
	Thickness = 1.5,
	Color = Theme.Accent,
	Transparency = 0.25,
}, fovCircle)

local function refreshFOVCircle()
	fovCircle.Visible = Config.Aimbot.Enabled and Config.Aimbot.ShowFOV
	fovCircle.Size = UDim2.fromOffset(Config.Aimbot.FOV * 2, Config.Aimbot.FOV * 2)
	fovStroke.Color = Theme.Accent
end
refreshFOVCircle()

--==================== BOTÃO FLUTUANTE (abrir/fechar) ====================
local toggleBtn = new("TextButton", {
	Name = "ToggleButton",
	Size = UDim2.fromOffset(52, 52),
	Position = UDim2.new(0, 18, 0.35, 0),
	BackgroundColor3 = Theme.Accent,
	Text = "☰",
	TextSize = 24,
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.new(1, 1, 1),
	AutoButtonColor = false,
	BorderSizePixel = 0,
	ZIndex = 50,
}, screenGui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, toggleBtn)
new("UIStroke", { Thickness = 1, Color = Color3.new(1, 1, 1), Transparency = 0.7 }, toggleBtn)

--==================== PAINEL PRINCIPAL (CanvasGroup p/ fade) ====================
local panel = new("CanvasGroup", {
	Name = "MainPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(320, 430),
	BackgroundColor3 = Theme.Background,
	BorderSizePixel = 0,
	GroupTransparency = 1,
	Visible = false,
	ZIndex = 40,
}, screenGui)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
new("UIStroke", { Thickness = 1, Color = Theme.Accent, Transparency = 0.5 }, panel)

-- UIScale responsivo (cabe na tela do celular)
local uiScale = new("UIScale", { Scale = 1 }, panel)
local function updateResponsiveScale()
	local vp = Camera.ViewportSize
	local s = math.min(1, vp.X / 400, vp.Y / 560)
	uiScale.Scale = math.clamp(s, 0.6, 1)
end
updateResponsiveScale()
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)

--==================== CABEÇALHO ====================
local header = new("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 42),
	BackgroundColor3 = Theme.Panel,
	BorderSizePixel = 0,
}, panel)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, header)

-- Corrige o canto inferior do header (fica quadrado para colar nas abas)
new("Frame", {
	Size = UDim2.new(1, 0, 0, 12),
	Position = UDim2.new(0, 0, 1, -12),
	BackgroundColor3 = Theme.Panel,
	BorderSizePixel = 0,
}, header)

new("TextLabel", {
	Size = UDim2.new(1, -50, 1, 0),
	Position = UDim2.new(0, 14, 0, 0),
	BackgroundTransparency = 1,
	Text = "PAINEL DE CONTROLE",
	TextColor3 = Theme.Text,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local closeBtn = new("TextButton", {
	Size = UDim2.fromOffset(28, 28),
	Position = UDim2.new(1, -36, 0.5, -14),
	BackgroundColor3 = Theme.Element,
	Text = "✕",
	TextColor3 = Theme.Text,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	AutoButtonColor = true,
	BorderSizePixel = 0,
}, header)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, closeBtn)

--==================== BARRA DE ABAS ====================
local tabBar = new("Frame", {
	Size = UDim2.new(1, -20, 0, 32),
	Position = UDim2.new(0, 10, 0, 48),
	BackgroundTransparency = 1,
}, panel)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, tabBar)

--==================== ÁREA DE CONTEÚDO ====================
local contentHolder = new("Frame", {
	Size = UDim2.new(1, -20, 1, -92),
	Position = UDim2.new(0, 10, 0, 86),
	BackgroundTransparency = 1,
}, panel)

local tabs = {}
local activeTab

local function createTab(name, order)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(94, 32),
		BackgroundColor3 = Theme.Element,
		Text = name,
		TextColor3 = Theme.SubText,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, tabBar)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, btn)

	local page = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, contentHolder)
	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, page)
	new("UIPadding", {
		PaddingRight = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 10),
	}, page)

	tabs[name] = { button = btn, page = page }

	btn.MouseButton1Click:Connect(function()
		if activeTab == name then return end
		activeTab = name
		for n, t in pairs(tabs) do
			local active = (n == name)
			t.page.Visible = active
			TweenService:Create(t.button, TweenInfo.new(0.18), {
				BackgroundColor3 = active and Theme.Accent or Theme.Element,
				TextColor3 = active and Color3.new(1, 1, 1) or Theme.SubText,
			}):Play()
		end
	end)
end

--==================== WIDGETS ====================
local function createRow(parent, order)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		LayoutOrder = order or 0,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, row)

	local label = new("TextLabel", {
		Size = UDim2.new(0.55, -12, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Theme.Text,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)

	return row, label
end

local function createToggle(row, default, callback)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(44, 22),
		Position = UDim2.new(1, -52, 0.5, -11),
		BackgroundColor3 = default and Theme.Accent or Theme.ToggleOff,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, row)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, btn)

	local knob = new("Frame", {
		Size = UDim2.fromOffset(18, 18),
		Position = default and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, btn)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

	local state = default
	btn.MouseButton1Click:Connect(function()
		state = not state
		TweenService:Create(btn, TweenInfo.new(0.15), {
			BackgroundColor3 = state and Theme.Accent or Theme.ToggleOff,
		}):Play()
		TweenService:Create(knob, TweenInfo.new(0.15), {
			Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
		}):Play()
		callback(state)
	end)
	return btn
end

local function createSlider(row, label, baseName, min, max, default, callback)
	local container = new("Frame", {
		Size = UDim2.fromOffset(130, 22),
		Position = UDim2.new(1, -140, 0.5, -11),
		BackgroundTransparency = 1,
	}, row)

	local track = new("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.new(0, 0, 0.5, -3),
		BackgroundColor3 = Theme.ToggleOff,
		BorderSizePixel = 0,
	}, container)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

	local fill = new("Frame", {
		Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
	}, track)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)

	local dragging = false
	local function updateFromX(x)
		local rel = math.clamp((x - container.AbsolutePosition.X) / math.max(container.AbsoluteSize.X, 1), 0, 1)
		local val = min + (max - min) * rel
		fill.Size = UDim2.new(rel, 0, 1, 0)
		label.Text = string.format("%s: %.2f", baseName, val)
		callback(val)
	end

	container.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromX(input.Position.X)
		end
	end)
	container.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromX(input.Position.X)
		end
	end)
	container.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	label.Text = string.format("%s: %.2f", baseName, default)
end

local function createCycleButton(row, text, callback)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(120, 26),
		Position = UDim2.new(1, -128, 0.5, -13),
		BackgroundColor3 = Theme.Element,
		Text = text,
		TextColor3 = Theme.Text,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		AutoButtonColor = true,
		BorderSizePixel = 0,
	}, row)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)
	return btn
end

--==================== ABA: AIMBOT ====================
createTab("Aimbot", 1)
local function getPage(n) return tabs[n].page end

local rowOrder = 0
local function nextOrder() rowOrder += 1; return rowOrder end

do
	local page = getPage("Aimbot")

	local r1, l1 = createRow(page, nextOrder())
	l1.Text = "Ativar Aimbot"
	createToggle(r1, Config.Aimbot.Enabled, function(v)
		Config.Aimbot.Enabled = v
		refreshFOVCircle()
	end)

	local r2, l2 = createRow(page, nextOrder())
	l2.Text = "FOV"
	local fovBox = new("TextBox", {
		Size = UDim2.fromOffset(80, 24),
		Position = UDim2.new(1, -88, 0.5, -12),
		BackgroundColor3 = Theme.Element,
		Text = tostring(Config.Aimbot.FOV),
		TextColor3 = Theme.Text,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		PlaceholderText = "120",
		BorderSizePixel = 0,
	}, r2)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, fovBox)
	fovBox.FocusLost:Connect(function()
		local v = tonumber(fovBox.Text)
		if v then
			Config.Aimbot.FOV = math.clamp(v, 10, 800)
			fovBox.Text = tostring(math.floor(Config.Aimbot.FOV))
			refreshFOVCircle()
		else
			fovBox.Text = tostring(Config.Aimbot.FOV)
		end
	end)

	local r3, l3 = createRow(page, nextOrder())
	l3.Text = "Distância Máx."
	local distBox = new("TextBox", {
		Size = UDim2.fromOffset(80, 24),
		Position = UDim2.new(1, -88, 0.5, -12),
		BackgroundColor3 = Theme.Element,
		Text = tostring(Config.Aimbot.MaxDistance),
		TextColor3 = Theme.Text,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		BorderSizePixel = 0,
	}, r3)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, distBox)
	distBox.FocusLost:Connect(function()
		local v = tonumber(distBox.Text)
		if v then
			Config.Aimbot.MaxDistance = math.clamp(v, 10, 5000)
			distBox.Text = tostring(math.floor(Config.Aimbot.MaxDistance))
		else
			distBox.Text = tostring(Config.Aimbot.MaxDistance)
		end
	end)

	local r4, l4 = createRow(page, nextOrder())
	l4.Text = "Parte do Corpo"
	local partBtn = createCycleButton(r4, Config.Aimbot.TargetPart)
	local partList = { "Head", "UpperTorso", "HumanoidRootPart" }
	partBtn.MouseButton1Click:Connect(function()
		local idx = table.find(partList, Config.Aimbot.TargetPart) or 1
		idx = (idx % #partList) + 1
		Config.Aimbot.TargetPart = partList[idx]
		partBtn.Text = Config.Aimbot.TargetPart
	end)

	local r5, l5 = createRow(page, nextOrder())
	createSlider(r5, l5, "Suavidade", 0.05, 1, Config.Aimbot.Smoothness, function(v)
		Config.Aimbot.Smoothness = v
	end)

	local r6, l6 = createRow(page, nextOrder())
	l6.Text = "Só se estiver visível (LOS)"
	createToggle(r6, Config.Aimbot.WallCheck, function(v)
		Config.Aimbot.WallCheck = v
	end)

	local r7, l7 = createRow(page, nextOrder())
	l7.Text = "Mostrar círculo do FOV"
	createToggle(r7, Config.Aimbot.ShowFOV, function(v)
		Config.Aimbot.ShowFOV = v
		refreshFOVCircle()
	end)
end

--==================== ABA: ESP ====================
createTab("ESP", 2)
do
	local page = getPage("ESP")

	local r1, l1 = createRow(page, 1)
	l1.Text = "Ativar ESP"
	createToggle(r1, Config.ESP.Enabled, function(v)
		Config.ESP.Enabled = v
		if not v then
			for p in pairs(espCache) do clearESPFor(p) end
		end
	end)

	local r2, l2 = createRow(page, 2)
	l2.Text = "Mostrar Nick"
	createToggle(r2, Config.ESP.ShowName, function(v) Config.ESP.ShowName = v end)

	local r3, l3 = createRow(page, 3)
	l3.Text = "Mostrar Distância"
	createToggle(r3, Config.ESP.ShowDistance, function(v) Config.ESP.ShowDistance = v end)

	local r4, l4 = createRow(page, 4)
	l4.Text = "Box ESP"
	createToggle(r4, Config.ESP.Box, function(v) Config.ESP.Box = v end)

	local r5, l5 = createRow(page, 5)
	l5.Text = "Highlight"
	createToggle(r5, Config.ESP.Highlight, function(v) Config.ESP.Highlight = v end)

	local r6, l6 = createRow(page, 6)
	createSlider(r6, l6, "Tam. Texto", 8, 28, Config.ESP.TextSize, function(v)
		Config.ESP.TextSize = math.floor(v)
	end)

	local r7, l7 = createRow(page, 7)
	l7.Text = "Cor do ESP"
	local colorBtn = createCycleButton(r7, "Trocar Cor")
	colorBtn.MouseButton1Click:Connect(function()
		paletteIndex = (paletteIndex % #ColorPalette) + 1
		Config.ESP.Color = ColorPalette[paletteIndex]
		colorBtn.BackgroundColor3 = Config.ESP.Color
	end)
end

--==================== ABA: GERAL ====================
createTab("Geral", 3)
do
	local page = getPage("Geral")

	local r1, l1 = createRow(page, 1)
	l1.Text = "FOV exibido"
	createToggle(r1, Config.Aimbot.ShowFOV, function(v)
		Config.Aimbot.ShowFOV = v
		refreshFOVCircle()
	end)

	local r2, l2 = createRow(page, 2)
	l2.Text = "Aimbot Ativo"
	createToggle(r2, Config.Aimbot.Enabled, function(v)
		Config.Aimbot.Enabled = v
		refreshFOVCircle()
	end)

	local r3, l3 = createRow(page, 3)
	l3.Text = "ESP Ativo"
	createToggle(r3, Config.ESP.Enabled, function(v)
		Config.ESP.Enabled = v
	end)

	local r4, l4 = createRow(page, 4)
	l4.Text = "Info"
	new("TextLabel", {
		Size = UDim2.new(0.45, -12, 1, 0),
		Position = UDim2.new(0.55, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = "Arraste o painel pelo topo",
		TextColor3 = Theme.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, r4)
end

-- Ativa a primeira aba
tabs["Aimbot"].page.Visible = true
tabs["Aimbot"].button.BackgroundColor3 = Theme.Accent
tabs["Aimbot"].button.TextColor3 = Color3.new(1, 1, 1)
activeTab = "Aimbot"

--==================== ANIMAÇÃO DO PAINEL ====================
local isOpen = false
local function openPanel()
	if isOpen then return end
	isOpen = true
	panel.Visible = true
	panel.Size = UDim2.fromOffset(0, 0)
	TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(320, 430),
		GroupTransparency = 0,
	}):Play()
end

local function closePanel()
	if not isOpen then return end
	isOpen = false
	local tw = TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.fromOffset(0, 0),
		GroupTransparency = 1,
	})
	tw:Play()
	tw.Completed:Connect(function()
		if not isOpen then panel.Visible = false end
	end)
end

closeBtn.MouseButton1Click:Connect(closePanel)

--==================== DRAG (painel + botão) ====================
local function makeDraggable(target, handle, onRelease)
	local dragging, dragStart, startPos, moved = false, nil, nil, false
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = false
			dragStart = input.Position
			startPos = target.Position
		end
	end)
	handle.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			if delta.Magnitude > 5 then moved = true end
			if moved then
				local s = target:IsDescendantOf(panel) and uiScale.Scale or 1
				target.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X / s,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y / s
				)
			end
		end
	end)
	handle.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			if onRelease then onRelease(moved) end
		end
	end)
end

makeDraggable(panel, header)
makeDraggable(toggleBtn, toggleBtn, function(moved)
	if not moved then
		if isOpen then closePanel() else openPanel() end
	end
end)

--==================== MÓDULO AIMBOT ====================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function getTargetPart(char)
	local part = char:FindFirstChild(Config.Aimbot.TargetPart)
	if part then return part end
	-- fallback caso R15/R6 diferentes
	return char:FindFirstChild("UpperTorso")
		or char:FindFirstChild("Torso")
		or char:FindFirstChild("Head")
end

local function findBestTarget()
	local bestPart, bestScore = nil, math.huge
	local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
	local myChar = LocalPlayer.Character

	for _, player in ipairs(Players:GetPlayers()) do
		if player == LocalPlayer then continue end
		local char = player.Character
		if not char then continue end
		if char == myChar then continue end

		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end

		local part = getTargetPart(char)
		if not part then continue end

		local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
		if not onScreen or screenPos.Z <= 0 then continue end

		local screenVec = Vector2.new(screenPos.X, screenPos.Y)
		local distFromCenter = (screenVec - center).Magnitude
		if distFromCenter > Config.Aimbot.FOV then continue end

		local worldDist = (part.Position - Camera.CFrame.Position).Magnitude
		if worldDist > Config.Aimbot.MaxDistance then continue end

		if Config.Aimbot.WallCheck then
			rayParams.FilterDescendantsInstances = { myChar, char }
			local hit = Workspace:Raycast(Camera.CFrame.Position,
				part.Position - Camera.CFrame.Position, rayParams)
			if hit then continue end
		end

		if distFromCenter < bestScore then
			bestPart, bestScore = part, distFromCenter
		end
	end

	return bestPart
end

-- Render step com prioridade acima da câmera padrão
local function aimbotUpdate(dt)
	if not Config.Aimbot.Enabled then return end

	local target = findBestTarget()
	if not target then return end

	local camPos = Camera.CFrame.Position
	local desired = CFrame.lookAt(camPos, target.Position)

	-- Suavização frame-independent
	local alpha = math.clamp(Config.Aimbot.Smoothness * dt * 60, 0, 1)
	Camera.CFrame = Camera.CFrame:Lerp(desired, alpha)
end

RunService:BindToRenderStep("SystemAimbot", Enum.RenderPriority.Camera.Value + 1, aimbotUpdate)

--==================== MÓDULO ESP ====================
local espCache = {}  -- [Player] = { char, highlight, billboard, nameLabel, distLabel, box }

function clearESPFor(player)
	local data = espCache[player]
	if not data then return end
	for _, obj in pairs(data) do
		if typeof(obj) == "Instance" and obj.Parent then obj:Destroy() end
	end
	espCache[player] = nil
end

function buildESPFor(player)
	clearESPFor(player)

	local char = player.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	if not head then return end

	-- Highlight
	local highlight = new("Highlight", {
		Name = "ESP_Highlight",
		FillColor = Config.ESP.Color,
		OutlineColor = Config.ESP.Color,
		FillTransparency = 0.6,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
	}, char)

	-- BillboardGui (nome + distância)
	local billboard = new("BillboardGui", {
		Name = "ESP_Billboard",
		Size = UDim2.fromOffset(220, 46),
		StudsOffsetWorldSpace = Vector3.new(0, 3, 0),
		AlwaysOnTop = true,
		Adornee = head,
		LightInfluence = 0,
	}, head)

	local nameLabel = new("TextLabel", {
		Size = UDim2.new(1, 0, 0.5, 0),
		BackgroundTransparency = 1,
		Text = player.DisplayName,
		TextColor3 = Config.ESP.Color,
		Font = Enum.Font.GothamBold,
		TextSize = Config.ESP.TextSize,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	}, billboard)

	local distLabel = new("TextLabel", {
		Size = UDim2.new(1, 0, 0.5, 0),
		Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Config.ESP.Color,
		Font = Enum.Font.Gotham,
		TextSize = math.max(10, Config.ESP.TextSize - 2),
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	}, billboard)

	-- Box (Frame com UIStroke)
	local box = new("Frame", {
		Name = "ESP_Box",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
	}, screenGui)
	new("UIStroke", {
		Thickness = 1.5,
		Color = Config.ESP.Color,
		Transparency = 0,
	}, box)

	espCache[player] = {
		char = char,
		highlight = highlight,
		billboard = billboard,
		nameLabel = nameLabel,
		distLabel = distLabel,
		box = box,
		lastTextUpdate = 0,
	}
end

--========== Atualização do ESP (RenderStepped) ==========
local lastCacheRefresh = 0

local function updateESP()
	if not Config.ESP.Enabled then return end

	local now = tick()

	-- Recria cache a cada 0.5s (jogadores entrando/saindo, respawn)
	if now - lastCacheRefresh > 0.5 then
		lastCacheRefresh = now
		for _, p in ipairs(Players:GetPlayers()) do
			if p == LocalPlayer then continue end
			local char = p.Character
			if char and char:FindFirstChild("Head") then
				local data = espCache[p]
				if not data or data.char ~= char then
					buildESPFor(p)
				end
			end
		end
	end

	local textUpdate = now - (espCache._lastText or 0) > 0.1
	if textUpdate then espCache._lastText = now end

	for player, data in pairs(espCache) do
		if type(player) ~= "Instance" then continue end  -- ignora chaves auxiliares

		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		local head = char and char:FindFirstChild("Head")
		local hum  = char and char:FindFirstChildOfClass("Humanoid")

		local valid = hrp and head and hum and hum.Health > 0

		-- Highlight
		if data.highlight then
			data.highlight.Enabled = valid and Config.ESP.Highlight
			data.highlight.FillColor = Config.ESP.Color
			data.highlight.OutlineColor = Config.ESP.Color
		end

		if not valid then
			if data.box then data.box.Visible = false end
			if data.billboard then data.billboard.Enabled = false end
			continue
		end

		-- Billboard (nome / distância)
		data.billboard.Enabled = Config.ESP.ShowName or Config.ESP.ShowDistance
		data.nameLabel.Visible = Config.ESP.ShowName
		data.distLabel.Visible = Config.ESP.ShowDistance
		data.nameLabel.TextColor3 = Config.ESP.Color
		data.distLabel.TextColor3 = Config.ESP.Color
		data.nameLabel.TextSize = Config.ESP.TextSize
		data.distLabel.TextSize = math.max(10, Config.ESP.TextSize - 2)

		if textUpdate then
			data.nameLabel.Text = player.DisplayName
			if Config.ESP.ShowDistance then
				local d = (hrp.Position - Camera.CFrame.Position).Magnitude
				data.distLabel.Text = string.format("[%d m]", math.floor(d))
			end
		end

		-- Box ESP
		if Config.ESP.Box then
			local topWorld = head.Position + Vector3.new(0, head.Size.Y * 0.5 + 0.6, 0)
			local botWorld = hrp.Position - Vector3.new(0, hrp.Size.Y * 0.5 + 2.5, 0)

			local topScreen, on1 = Camera:WorldToViewportPoint(topWorld)
			local botScreen, on2 = Camera:WorldToViewportPoint(botWorld)

			if on1 and on2 and topScreen.Z > 0 and botScreen.Z > 0 then
				local h = math.abs(botScreen.Y - topScreen.Y)
				local w = h * 0.55
				data.box.Size = UDim2.fromOffset(w, h)
				data.box.Position = UDim2.fromOffset(topScreen.X - w / 2, topScreen.Y)
				data.box.Visible = true
			else
				data.box.Visible = false
			end
		else
			data.box.Visible = false
		end
	end
end

RunService.RenderStepped:Connect(updateESP)

--==================== CICLO DE VIDA DE JOGADORES ====================
Players.PlayerRemoving:Connect(function(player)
	clearESPFor(player)
end)

Players.PlayerAdded:Connect(function(player)
	if player == LocalPlayer then return end
	player.CharacterAdded:Connect(function()
		task.wait(0.35)  -- aguarda o personagem montar
		if Config.ESP.Enabled then
			buildESPFor(player)
		end
	end)
end)

-- Ao morrer/respawnar, limpamos o cache do LocalPlayer (não faz nada, mas garante)
LocalPlayer.CharacterAdded:Connect(function()
	-- nada a fazer além de deixar o loop recriar depois
end)

--==================== LIMPEZA (caso o script seja destruído) ====================
screenGui.Destroying:Connect(function()
	pcall(function()
		RunService:UnbindFromRenderStep("SystemAimbot")
	end)
	for p in pairs(espCache) do
		if type(p) == "Instance" then clearESPFor(p) end
	end
end)

print("[Sistema] Carregado com sucesso. Toque no botão ☰ para abrir o painel.")
