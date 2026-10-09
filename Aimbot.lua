--!strict
-- ============================================================
-- SYSTEM CORE — UI + Aimbot + ESP
-- Tudo em um único LocalScript.
-- Coloque em: StarterPlayer > StarterPlayerScripts > SystemCore (LocalScript)
-- ============================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ============================================================
-- 1. CONFIGURAÇÕES (edite livremente)
-- ============================================================
local CONFIG = {
	Aimbot = {
		Enabled       = false,
		FOV           = 120,
		MaxDistance   = 500,
		TargetPart    = "Head",         -- "Head" | "UpperTorso" | "HumanoidRootPart"
		Smoothness    = 0.35,           -- 0 = travado, 1 = muito lento
		UseLineOfSight= true,
		TeamCheck     = true,
	},
	ESP = {
		Enabled       = false,
		ShowName      = true,
		ShowDistance  = true,
		ShowBox       = true,
		UseHighlight  = true,
		Color         = Color3.fromRGB(0, 170, 255),
		TextSize      = 14,
	},
	Theme = {
		Background  = Color3.fromRGB(20, 20, 25),
		Panel       = Color3.fromRGB(28, 28, 35),
		Accent      = Color3.fromRGB(0, 170, 255),
		Text        = Color3.fromRGB(240, 240, 240),
		SubText     = Color3.fromRGB(160, 160, 170),
		ToggleOn    = Color3.fromRGB(0, 200, 120),
		ToggleOff   = Color3.fromRGB(80, 80, 90),
		Border      = Color3.fromRGB(45, 45, 55),
		Danger      = Color3.fromRGB(200, 60, 60),
	},
}

-- ============================================================
-- 2. HELPERS
-- ============================================================
local function new(className, props)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	return inst
end

local function addCorner(parent, radius)
	return new("UICorner", {
		CornerRadius = UDim.new(0, radius or 8),
		Parent = parent,
	})
end

local function addStroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color or CONFIG.Theme.Border,
		Thickness = thickness or 1,
		Transparency = transparency or 0.4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- ============================================================
-- 3. UI — CONSTRUÇÃO
-- ============================================================
local gui = new("ScreenGui", {
	Name = "SystemCoreUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- FOV Circle
local fovCircle = new("Frame", {
	Name = "FOVCircle",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(CONFIG.Aimbot.FOV * 2, CONFIG.Aimbot.FOV * 2),
	Visible = false,
	ZIndex = 2,
	Parent = gui,
})
addCorner(fovCircle, math.huge)
addStroke(fovCircle, CONFIG.Theme.Accent, 1.5, 0.2)

local function updateFOVCircle()
	fovCircle.Size = UDim2.fromOffset(CONFIG.Aimbot.FOV * 2, CONFIG.Aimbot.FOV * 2)
	fovCircle.Visible = CONFIG.Aimbot.Enabled
end

-- Botão flutuante (abrir painel)
local toggleBtn = new("TextButton", {
	Name = "ToggleBtn",
	Size = UDim2.fromOffset(50, 50),
	Position = UDim2.new(0, 20, 0.5, -25),
	BackgroundColor3 = CONFIG.Theme.Accent,
	Text = "⚙",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	AutoButtonColor = false,
	ZIndex = 10,
	Parent = gui,
})
addCorner(toggleBtn, 25)
addStroke(toggleBtn, CONFIG.Theme.Accent, 2, 0)

-- Painel principal
local panel = new("Frame", {
	Name = "Panel",
	Size = UDim2.fromOffset(360, 500),
	Position = UDim2.new(0.5, -180, 0.5, -250),
	BackgroundColor3 = CONFIG.Theme.Background,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 5,
	Parent = gui,
})
addCorner(panel, 12)
addStroke(panel)

-- Header (área de arraste)
local header = new("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundColor3 = CONFIG.Theme.Panel,
	BorderSizePixel = 0,
	Parent = panel,
})
addCorner(header, 12)
new("Frame", {
	Size = UDim2.new(1, 0, 0, 12),
	Position = UDim2.new(0, 0, 1, -12),
	BackgroundColor3 = CONFIG.Theme.Panel,
	BorderSizePixel = 0,
	Parent = header,
})

new("TextLabel", {
	Size = UDim2.new(1, -60, 1, 0),
	Position = UDim2.new(0, 16, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "PAINEL DE CONTROLE",
	TextColor3 = CONFIG.Theme.Text,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = header,
})

local closeBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(28, 28),
	BackgroundColor3 = CONFIG.Theme.Danger,
	Text = "✕",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	AutoButtonColor = false,
	Parent = header,
})
addCorner(closeBtn, 14)

-- Abas
local tabBar = new("Frame", {
	Position = UDim2.new(0, 12, 0, 56),
	Size = UDim2.new(1, -24, 0, 30),
	BackgroundTransparency = 1,
	Parent = panel,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 6),
	Parent = tabBar,
})

local content = new("Frame", {
	Position = UDim2.new(0, 12, 0, 96),
	Size = UDim2.new(1, -24, 1, -108),
	BackgroundTransparency = 1,
	Parent = panel,
})

local pages = {}
local tabButtons = {}

local function showPage(name)
	for k, p in pairs(pages) do
		p.Visible = (k == name)
	end
	for k, b in pairs(tabButtons) do
		TweenService:Create(b, TweenInfo.new(0.15), {
			BackgroundColor3 = (k == name) and CONFIG.Theme.Accent or CONFIG.Theme.Panel,
		}):Play()
	end
end

local function addTab(name)
	local btn = new("TextButton", {
		Size = UDim2.new(0.5, -3, 1, 0),
		BackgroundColor3 = CONFIG.Theme.Panel,
		Font = Enum.Font.GothamMedium,
		Text = name,
		TextColor3 = CONFIG.Theme.Text,
		TextSize = 13,
		AutoButtonColor = false,
		Parent = tabBar,
	})
	addCorner(btn, 8)
	tabButtons[name] = btn

	local page = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = CONFIG.Theme.Accent,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = content,
	})
	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		Parent = page,
	})
	pages[name] = page

	btn.MouseButton1Click:Connect(function() showPage(name) end)
	return page
end

-- ============================================================
-- 4. COMPONENTES (Toggle, Slider, Dropdown)
-- ============================================================
local function createToggle(parent, labelText, getValue, setValue)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	new("TextLabel", {
		Size = UDim2.new(1, -60, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = labelText,
		TextColor3 = CONFIG.Theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local btn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(44, 22),
		BackgroundColor3 = getValue() and CONFIG.Theme.ToggleOn or CONFIG.Theme.ToggleOff,
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})
	addCorner(btn, 11)

	local knob = new("Frame", {
		Size = UDim2.fromOffset(18, 18),
		Position = getValue() and UDim2.new(1, -20, 0, 2) or UDim2.new(0, 2, 0, 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = btn,
	})
	addCorner(knob, 9)

	btn.MouseButton1Click:Connect(function()
		local newVal = not getValue()
		setValue(newVal)
		TweenService:Create(btn, TweenInfo.new(0.2), {
			BackgroundColor3 = newVal and CONFIG.Theme.ToggleOn or CONFIG.Theme.ToggleOff,
		}):Play()
		TweenService:Create(knob, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
			Position = newVal and UDim2.new(1, -20, 0, 2) or UDim2.new(0, 2, 0, 2),
		}):Play()
	end)
end

local function createSlider(parent, labelText, min, max, getValue, setValue, onChange)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	new("TextLabel", {
		Size = UDim2.new(1, -60, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = labelText,
		TextColor3 = CONFIG.Theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local valLabel = new("TextLabel", {
		Size = UDim2.new(0, 60, 0, 20),
		Position = UDim2.new(1, -60, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = string.format("%.0f", getValue()),
		TextColor3 = CONFIG.Theme.Accent,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local bar = new("Frame", {
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = CONFIG.Theme.ToggleOff,
		BorderSizePixel = 0,
		Parent = row,
	})
	addCorner(bar, 3)

	local fill = new("Frame", {
		Size = UDim2.fromScale((getValue() - min) / (max - min), 1),
		BackgroundColor3 = CONFIG.Theme.Accent,
		BorderSizePixel = 0,
		Parent = bar,
	})
	addCorner(fill, 3)

	local dragging = false
	local function updateFromX(x)
		local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		local val = min + (max - min) * rel
		fill.Size = UDim2.fromScale(rel, 1)
		valLabel.Text = string.format("%.0f", val)
		setValue(val)
		if onChange then onChange(val) end
	end

	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromX(input.Position.X)
		end
	end)
	bar.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromX(input.Position.X)
		end
	end)
end

local function createDropdown(parent, labelText, options, getValue, setValue)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	new("TextLabel", {
		Size = UDim2.new(1, -150, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = labelText,
		TextColor3 = CONFIG.Theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local current = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(140, 32),
		BackgroundColor3 = CONFIG.Theme.Panel,
		Font = Enum.Font.Gotham,
		Text = getValue(),
		TextColor3 = CONFIG.Theme.Text,
		TextSize = 13,
		AutoButtonColor = false,
		Parent = row,
	})
	addCorner(current, 6)
	addStroke(current)

	local list = new("Frame", {
		Position = UDim2.new(1, 0, 0, 34),
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(140, 0),
		BackgroundColor3 = CONFIG.Theme.Panel,
		Visible = false,
		ClipsDescendants = true,
		ZIndex = 5,
		Parent = row,
	})
	addCorner(list, 6)
	addStroke(list)

	local opened = false
	current.MouseButton1Click:Connect(function()
		opened = not opened
		if opened then
			list.Visible = true
			TweenService:Create(list, TweenInfo.new(0.18), {
				Size = UDim2.fromOffset(140, #options * 28),
			}):Play()
		else
			local t = TweenService:Create(list, TweenInfo.new(0.18), {
				Size = UDim2.fromOffset(140, 0),
			})
			t:Play()
			t.Completed:Connect(function() list.Visible = false end)
		end
	end)

	new("UIListLayout", { Parent = list, SortOrder = Enum.SortOrder.LayoutOrder })
	for _, opt in ipairs(options) do
		local optBtn = new("TextButton", {
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = opt,
			TextColor3 = CONFIG.Theme.Text,
			TextSize = 13,
			Parent = list,
		})
		optBtn.MouseEnter:Connect(function() optBtn.BackgroundTransparency = 0.8 end)
		optBtn.MouseLeave:Connect(function() optBtn.BackgroundTransparency = 1 end)
		optBtn.MouseButton1Click:Connect(function()
			setValue(opt)
			current.Text = opt
			opened = false
			list.Visible = false
			list.Size = UDim2.fromOffset(140, 0)
		end)
	end
end

-- ============================================================
-- 5. PREENCHER ABAS
-- ============================================================
local aimPage = addTab("Aimbot")
local espPage = addTab("ESP")

-- Aimbot
createToggle(aimPage, "Aimbot Ativado",
	function() return CONFIG.Aimbot.Enabled end,
	function(v)
		CONFIG.Aimbot.Enabled = v
		updateFOVCircle()
	end)

createSlider(aimPage, "FOV", 20, 500,
	function() return CONFIG.Aimbot.FOV end,
	function(v) CONFIG.Aimbot.FOV = v end,
	function() updateFOVCircle() end)

createSlider(aimPage, "Distância Máxima", 50, 2000,
	function() return CONFIG.Aimbot.MaxDistance end,
	function(v) CONFIG.Aimbot.MaxDistance = v end)

createSlider(aimPage, "Suavidade", 0.05, 1,
	function() return CONFIG.Aimbot.Smoothness end,
	function(v) CONFIG.Aimbot.Smoothness = v end)

createDropdown(aimPage, "Parte do Corpo",
	{"Head", "UpperTorso", "HumanoidRootPart"},
	function() return CONFIG.Aimbot.TargetPart end,
	function(v) CONFIG.Aimbot.TargetPart = v end)

createToggle(aimPage, "Line of Sight",
	function() return CONFIG.Aimbot.UseLineOfSight end,
	function(v) CONFIG.Aimbot.UseLineOfSight = v end)

createToggle(aimPage, "Team Check",
	function() return CONFIG.Aimbot.TeamCheck end,
	function(v) CONFIG.Aimbot.TeamCheck = v end)

-- ESP
createToggle(espPage, "ESP Ativado",
	function() return CONFIG.ESP.Enabled end,
	function(v) CONFIG.ESP.Enabled = v end)

createToggle(espPage, "Mostrar Nome",
	function() return CONFIG.ESP.ShowName end,
	function(v) CONFIG.ESP.ShowName = v end)

createToggle(espPage, "Mostrar Distância",
	function() return CONFIG.ESP.ShowDistance end,
	function(v) CONFIG.ESP.ShowDistance = v end)

createToggle(espPage, "Box ESP",
	function() return CONFIG.ESP.ShowBox end,
	function(v) CONFIG.ESP.ShowBox = v end)

createToggle(espPage, "Highlight",
	function() return CONFIG.ESP.UseHighlight end,
	function(v) CONFIG.ESP.UseHighlight = v end)

createSlider(espPage, "Tamanho do Texto", 8, 24,
	function() return CONFIG.ESP.TextSize end,
	function(v) CONFIG.ESP.TextSize = v end)

-- ============================================================
-- 6. DRAG DO PAINEL
-- ============================================================
do
	local dragging = false
	local dragStart, startPos

	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = panel.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			panel.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- ============================================================
-- 7. ABRIR / FECHAR PAINEL
-- ============================================================
do
	local isOpen = false
	local function setOpen(state)
		isOpen = state
		if isOpen then
			panel.Visible = true
			panel.Size = UDim2.fromOffset(360, 0)
			TweenService:Create(panel,
				TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(360, 500) }):Play()
		else
			local t = TweenService:Create(panel, TweenInfo.new(0.2),
				{ Size = UDim2.fromOffset(360, 0) })
			t:Play()
			t.Completed:Connect(function() panel.Visible = false end)
		end
	end

	toggleBtn.MouseButton1Click:Connect(function() setOpen(not isOpen) end)
	closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
end

showPage("Aimbot")

-- ============================================================
-- 8. AIMBOT
-- ============================================================
local aimbotConn

local function isValidTarget(plr)
	if plr == player then return false end
	local char = plr.Character
	if not char then return false end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end

	if CONFIG.Aimbot.TeamCheck and plr.Team and player.Team
		and plr.Team == player.Team then
		return false
	end
	return true
end

local function getTargetPart(character)
	local partName = CONFIG.Aimbot.TargetPart
	local part = character:FindFirstChild(partName)
	if part then return part end

	if partName == "UpperTorso" then
		return character:FindFirstChild("Torso")
			or character:FindFirstChild("HumanoidRootPart")
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function getScreenDistance(worldPos)
	local screenPos, onScreen = camera:WorldToViewportPoint(worldPos)
	if not onScreen then return math.huge end
	local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	return (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
end

local function hasLineOfSight(targetPart)
	local origin = camera.CFrame.Position
	local dir = targetPart.Position - origin

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	params.IgnoreWater = true

	local result = Workspace:Raycast(origin, dir, params)
	if not result then return true end
	return result.Instance:IsDescendantOf(targetPart.Parent)
end

local function findBestTarget()
	local best, bestScore = nil, math.huge
	local myPos = camera.CFrame.Position
	local halfFOV = CONFIG.Aimbot.FOV

	for _, plr in ipairs(Players:GetPlayers()) do
		if isValidTarget(plr) then
			local part = getTargetPart(plr.Character)
			if part then
				local dist3D = (part.Position - myPos).Magnitude
				if dist3D <= CONFIG.Aimbot.MaxDistance then
					local distScreen = getScreenDistance(part.Position)
					if distScreen <= halfFOV then
						if CONFIG.Aimbot.UseLineOfSight and not hasLineOfSight(part) then
							continue
						end
						if distScreen < bestScore then
							bestScore = distScreen
							best = part
						end
					end
				end
			end
		end
	end
	return best
end

local function aimbotStep()
	if not CONFIG.Aimbot.Enabled then return end
	local target = findBestTarget()
	if not target then return end

	local targetCFrame = CFrame.new(camera.CFrame.Position, target.Position)
	local alpha = math.clamp(1 - CONFIG.Aimbot.Smoothness, 0.02, 1)
	camera.CFrame = camera.CFrame:Lerp(targetCFrame, alpha)
end

aimbotConn = RunService.RenderStepped:Connect(aimbotStep)

-- ============================================================
-- 9. ESP
-- ============================================================
local espCache = {}  -- [player] = { billboard, box, highlight, connection }

local function clearESP(plr)
	local data = espCache[plr]
	if not data then return end
	if data.billboard then data.billboard:Destroy() end
	if data.box then data.box:Destroy() end
	if data.highlight then data.highlight:Destroy() end
	if data.conn then data.conn:Disconnect() end
	espCache[plr] = nil
end

local function buildESP(plr)
	clearESP(plr)
	local char = plr.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end
	if plr == player then return end

	-- Highlight
	local highlight
	if CONFIG.ESP.UseHighlight then
		highlight = new("Highlight", {
			Name = "ESP_Highlight",
			FillColor = CONFIG.ESP.Color,
			OutlineColor = CONFIG.ESP.Color,
			FillTransparency = 0.6,
			OutlineTransparency = 0,
			Parent = char,
		})
	end

	-- Billboard (nome + distância)
	local billboard = new("BillboardGui", {
		Name = "ESP_Billboard",
		Adornee = char.Head or char:FindFirstChild("HumanoidRootPart"),
		Size = UDim2.fromOffset(180, 44),
		StudsOffset = Vector3.new(0, 2.5, 0),
		AlwaysOnTop = true,
		Parent = char,
	})
	local nameLabel = new("TextLabel", {
		Name = "Name",
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = plr.DisplayName,
		TextColor3 = CONFIG.ESP.Color,
		TextSize = CONFIG.ESP.TextSize,
		TextStrokeTransparency = 0.3,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		Visible = CONFIG.ESP.ShowName,
		Parent = billboard,
	})
	local distLabel = new("TextLabel", {
		Name = "Distance",
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = CONFIG.ESP.Color,
		TextSize = CONFIG.ESP.TextSize - 2,
		TextStrokeTransparency = 0.3,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		Visible = CONFIG.ESP.ShowDistance,
		Parent = billboard,
	})

	-- Box ESP (Frame em 2D reativo à câmera)
	local box
	if CONFIG.ESP.ShowBox then
		box = new("Frame", {
			Name = "ESP_Box_" .. plr.Name,
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 3,
			Parent = gui,
		})
		addStroke(box, CONFIG.ESP.Color, 1.5, 0)
	end

	-- Conexão por personagem
	local conn = RunService.RenderStepped:Connect(function()
		local c = plr.Character
		if not c or not c:FindFirstChild("HumanoidRootPart") then
			return
		end

		local root = c.HumanoidRootPart
		local myPos = camera.CFrame.Position
		local dist = (root.Position - myPos).Magnitude

		-- Atualiza billboard
		if billboard.Parent then
			billboard.Adornee = c:FindFirstChild("Head") or root
			nameLabel.Text = plr.DisplayName
			nameLabel.TextSize = CONFIG.ESP.TextSize
			nameLabel.TextColor3 = CONFIG.ESP.Color
			nameLabel.Visible = CONFIG.ESP.ShowName

			distLabel.Text = string.format("%d studs", dist)
			distLabel.TextSize = CONFIG.ESP.TextSize - 2
			distLabel.TextColor3 = CONFIG.ESP.Color
			distLabel.Visible = CONFIG.ESP.ShowDistance
		end

		-- Atualiza Highlight
		if highlight then
			highlight.FillColor = CONFIG.ESP.Color
			highlight.OutlineColor = CONFIG.ESP.Color
		end

		-- Atualiza Box 2D
		if box then
			if not CONFIG.ESP.ShowBox then
				box.Visible = false
			else
				local top, onTop = camera:WorldToViewportPoint(
					(root.CFrame * CFrame.new(0, 2.5, 0)).Position)
				local bottom = camera:WorldToViewportPoint(
					(root.CFrame * CFrame.new(0, -2.5, 0)).Position)
				if onTop then
					box.Visible = true
					local h = math.abs(bottom.Y - top.Y)
					local w = h * 0.55
					box.Size = UDim2.fromOffset(w, h)
					box.Position = UDim2.fromOffset(
						top.X - w / 2,
						math.min(top.Y, bottom.Y))
					local strokeObj = box:FindFirstChildOfClass("UIStroke")
					if strokeObj then
						strokeObj.Color = CONFIG.ESP.Color
					end
				else
					box.Visible = false
				end
			end
		end
	end)

	espCache[plr] = {
		billboard = billboard,
		box = box,
		highlight = highlight,
		conn = conn,
	}
end

-- Gerenciar entrada/saída de personagens
local function onPlayerAdded(plr)
	plr.CharacterAdded:Connect(function()
		if CONFIG.ESP.Enabled then
			task.wait(0.15)
			buildESP(plr)
		end
	end)
	plr.CharacterRemoving:Connect(function() clearESP(plr) end)
	if plr.Character and CONFIG.ESP.Enabled then
		buildESP(plr)
	end
end

for _, plr in ipairs(Players:GetPlayers()) do
	onPlayerAdded(plr)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(plr) clearESP(plr) end)

-- Controla liga/desliga global do ESP sem recriar tudo
RunService.Heartbeat:Connect(function()
	-- Se desligar globalmente, remove tudo
	if not CONFIG.ESP.Enabled then
		for plr in pairs(espCache) do
			clearESP(plr)
		end
	else
		-- Se ligar e algum player não tiver ESP, cria
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= player and plr.Character and not espCache[plr] then
				buildESP(plr)
			end
		end
	end
end)

-- ============================================================
-- 10. LIMPEZA AO SAIR
-- ============================================================
Players.LocalPlayer.AncestryChanged:Connect(function()
	if aimbotConn then aimbotConn:Disconnect() end
	for plr in pairs(espCache) do
		clearESP(plr)
	end
end)

print("[SystemCore] Carregado com sucesso. Pressione ⚙ para abrir o painel.")
