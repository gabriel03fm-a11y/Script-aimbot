--!strict
-- ============================================================
-- STEAL AN EGG — SISTEMA COMPLETO (código único)
-- LocalScript → StarterPlayer > StarterPlayerScripts
-- Nome sugerido: StealAnEggController
-- ------------------------------------------------------------
-- Este é um script único auto-contido. Ele cria a UI, o banco de
-- ovos, o analisador, os filtros, o ranking e o controller de
-- roubo. Funciona no Studio em modo teste. Em produção, ligue os
-- RemoteEvents no final (marcados com SERVER HOOK) ao seu
-- servidor real para validação.
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- ============================================================
-- 1. CONFIG — Configurações globais
-- ============================================================
local Config = {
	AutoSteal        = false,
	InstantSteal     = false,
	MinValue         = 0,
	MaxValue         = math.huge,
	MinRarity        = "Comum",
	OnlyCreature     = "",
	MinIncome        = 0,
	PrioritizeBest   = true,
	FilterBestOnly   = false,
	FilterRareChance = false,
	Theme = {
		Bg         = Color3.fromRGB(18, 18, 24),
		Panel      = Color3.fromRGB(28, 28, 36),
		PanelAlt   = Color3.fromRGB(36, 36, 46),
		Accent     = Color3.fromRGB(120, 90, 255),
		Accent2    = Color3.fromRGB(0, 200, 160),
		Text       = Color3.fromRGB(240, 240, 245),
		SubText    = Color3.fromRGB(150, 150, 165),
		Border     = Color3.fromRGB(55, 55, 70),
		Success    = Color3.fromRGB(0, 200, 120),
		Warning    = Color3.fromRGB(255, 180, 0),
		Danger     = Color3.fromRGB(230, 70, 70),
	},
}

-- ============================================================
-- 2. EGG DATABASE — Banco de ovos (edite aqui)
-- Estrutura: nome, valor, raridade, criaturas com chance/valor.
-- ============================================================
local EggDatabase = {
	{
		Name = "Ovo Comum", Value = 1e5, Rarity = "Comum",
		Creatures = {
			{ Name = "🐣 Pintinho",  Chance = 0.70, Value = 5e4  },
			{ Name = "🐔 Galinha",   Chance = 0.25, Value = 2e5  },
			{ Name = "🦆 Pato",      Chance = 0.05, Value = 1e6  },
		},
	},
	{
		Name = "Ovo Raro", Value = 1e6, Rarity = "Raro",
		Creatures = {
			{ Name = "🐰 Coelho",    Chance = 0.55, Value = 5e5  },
			{ Name = "🦊 Raposa",    Chance = 0.35, Value = 2e6  },
			{ Name = "🐺 Lobo",      Chance = 0.10, Value = 1e7  },
		},
	},
	{
		Name = "Ovo Lendário", Value = 1.5e9, Rarity = "Lendário",
		Creatures = {
			{ Name = "🐔 Galinha",      Chance = 0.50, Value = 5e8  },
			{ Name = "🦊 Raposa",       Chance = 0.30, Value = 1e9  },
			{ Name = "🐉 Dragão",       Chance = 0.15, Value = 5e9  },
			{ Name = "👑 Rei Dragão",   Chance = 0.05, Value = 2e10 },
		},
	},
	{
		Name = "Ovo Mítico", Value = 1e10, Rarity = "Mítico",
		Creatures = {
			{ Name = "🦄 Unicórnio",    Chance = 0.50, Value = 5e9  },
			{ Name = "🐲 Wyvern",       Chance = 0.30, Value = 2e10 },
			{ Name = "🔥 Fênix",        Chance = 0.15, Value = 5e10 },
			{ Name = "🌌 Dragão Astral",Chance = 0.05, Value = 5e11 },
		},
	},
	{
		Name = "Ovo Divino", Value = 2.5e10, Rarity = "Divino",
		Creatures = {
			{ Name = "⚡ Anjo",         Chance = 0.50, Value = 1e10 },
			{ Name = "🕊️ Serafim",      Chance = 0.30, Value = 5e10 },
			{ Name = "✨ Deus Solar",   Chance = 0.15, Value = 2e11 },
			{ Name = "🌟 Criador",      Chance = 0.05, Value = 1e12 },
		},
	},
	{
		Name = "Ovo Supremo", Value = 5e10, Rarity = "Supremo",
		Creatures = {
			{ Name = "💎 Titã",         Chance = 0.50, Value = 2e10 },
			{ Name = "🌠 Estelar",      Chance = 0.30, Value = 8e10 },
			{ Name = "🔮 Onipotente",   Chance = 0.15, Value = 5e11 },
			{ Name = "👁️ Além-vida",    Chance = 0.05, Value = 5e12 },
		},
	},
}

-- Anexa valor esperado, melhor criatura e renda a cada ovo
for _, egg in ipairs(EggDatabase) do
	local ev, best, income = 0, nil, 0
	for _, c in ipairs(egg.Creatures) do
		ev = ev + (c.Chance * c.Value)
		if not best or c.Value > best.Value then best = c end
		income = income + c.Value * c.Chance
	end
	egg.ExpectedValue = ev
	egg.BestCreature  = best
	egg.Income        = income
end

local RarityOrder = { Comum = 1, Raro = 2, Lendário = 3, Mítico = 4, Divino = 5, Supremo = 6 }

-- ============================================================
-- 3. EGG ANALYZER — Filtros, ordenação e formatação
-- ============================================================
local EggAnalyzer = {}

function EggAnalyzer.formatNumber(n)
	if n >= 1e12 then return string.format("%.2fT", n / 1e12) end
	if n >= 1e9  then return string.format("%.2fB", n / 1e9) end
	if n >= 1e6  then return string.format("%.2fM", n / 1e6) end
	if n >= 1e3  then return string.format("%.2fK", n / 1e3) end
	return tostring(math.floor(n))
end

function EggAnalyzer.matches(egg)
	if egg.Value < Config.MinValue then return false end
	if egg.Value > Config.MaxValue then return false end
	if (RarityOrder[egg.Rarity] or 0) < (RarityOrder[Config.MinRarity] or 0) then return false end
	if egg.Income < Config.MinIncome then return false end

	if Config.OnlyCreature ~= "" then
		local found = false
		for _, c in ipairs(egg.Creatures) do
			if string.find(string.lower(c.Name), string.lower(Config.OnlyCreature), 1, true) then
				found = true; break
			end
		end
		if not found then return false end
	end

	if Config.FilterRareChance then
		local hasRare = false
		for _, c in ipairs(egg.Creatures) do
			if c.Chance <= 0.10 then hasRare = true; break end
		end
		if not hasRare then return false end
	end

	return true
end

function EggAnalyzer.getSorted()
	local list = {}
	for _, e in ipairs(EggDatabase) do
		if EggAnalyzer.matches(e) then table.insert(list, e) end
	end
	table.sort(list, function(a, b)
		if a.ExpectedValue ~= b.ExpectedValue then return a.ExpectedValue > b.ExpectedValue end
		if a.BestCreature.Value ~= b.BestCreature.Value then return a.BestCreature.Value > b.BestCreature.Value end
		if (RarityOrder[a.Rarity] or 0) ~= (RarityOrder[b.Rarity] or 0) then
			return (RarityOrder[a.Rarity] or 0) > (RarityOrder[b.Rarity] or 0)
		end
		return a.Value > b.Value
	end)
	return list
end

function EggAnalyzer.getBest()
	local list = EggAnalyzer.getSorted()
	return list[1]
end

-- ============================================================
-- 4. STEAL CONTROLLER — Lógica de roubo
-- ============================================================
local StealController = {
	CurrentTarget = nil,
	LastSteal    = 0,
	Cooldown     = 0.35,
	_conn        = nil,
}

-- Envia requisição de roubo. Se o RemoteEvent existir, usa-o.
-- Caso contrário, simula localmente (para testes no Studio).
function StealController.requestSteal(egg)
	local remotes = ReplicatedStorage:FindFirstChild("EggRemotes")
	local stealRE = remotes and remotes:FindFirstChild("RequestSteal")

	-- SERVER HOOK: se existir, o servidor valida e executa.
	if stealRE and stealRE:IsA("RemoteEvent") then
		stealRE:FireServer(egg.Name)
		return true
	end

	-- Fallback local (somente Studio / teste)
	warn("[StealController] RemoteEvent não encontrado. Simulando roubo de: " .. egg.Name)
	return true
end

function StealController.tick()
	if not Config.AutoSteal then
		StealController.CurrentTarget = nil
		return
	end
	if os.clock() - StealController.LastSteal < StealController.Cooldown then return end

	local target
	if Config.FilterBestOnly or Config.PrioritizeBest then
		target = EggAnalyzer.getBest()
	else
		local list = EggAnalyzer.getSorted()
		target = list[1]
	end

	if not target then return end

	StealController.CurrentTarget = target
	StealController.LastSteal = os.clock()

	if Config.InstantSteal or Config.AutoSteal then
		StealController.requestSteal(target)
	end
end

function StealController.start()
	if StealController._conn then return end
	StealController._conn = RunService.Heartbeat:Connect(function()
		pcall(StealController.tick)
	end)
end

-- ============================================================
-- 5. UI CONTROLLER — Interface moderna e responsiva
-- ============================================================
local UI = {}

local function new(class, props)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do inst[k] = v end
	return inst
end

local function corner(p, r) return new("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = p }) end
local function stroke(p, c, t, tr)
	return new("UIStroke", {
		Color = c or Config.Theme.Border, Thickness = t or 1,
		Transparency = tr or 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = p,
	})
end

function UI.build()
	local gui = new("ScreenGui", {
		Name = "StealAnEggUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	UI.gui = gui

	-- Botão flutuante
	local openBtn = new("TextButton", {
		Name = "OpenBtn",
		Size = UDim2.fromOffset(54, 54),
		Position = UDim2.new(0, 20, 0.5, -27),
		BackgroundColor3 = Config.Theme.Accent,
		Text = "🥚",
		TextSize = 26,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = false,
		ZIndex = 20,
		Parent = gui,
	})
	corner(openBtn, 27)
	stroke(openBtn, Config.Theme.Accent, 2, 0)
	UI.openBtn = openBtn

	-- Painel
	local panel = new("Frame", {
		Name = "Panel",
		Size = UDim2.fromOffset(480, 560),
		Position = UDim2.new(0.5, -240, 0.5, -280),
		BackgroundColor3 = Config.Theme.Bg,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	corner(panel, 14)
	stroke(panel, Config.Theme.Border, 1, 0.2)
	UI.panel = panel

	-- Header
	local header = new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = Config.Theme.Panel,
		BorderSizePixel = 0,
		Parent = panel,
	})
	corner(header, 14)
	new("Frame", {
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 1, -14),
		BackgroundColor3 = Config.Theme.Panel,
		BorderSizePixel = 0,
		Parent = header,
	})
	new("TextLabel", {
		Size = UDim2.new(1, -80, 1, 0),
		Position = UDim2.new(0, 18, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "🥚 STEAL AN EGG",
		TextColor3 = Config.Theme.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	local closeBtn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Config.Theme.Danger,
		Text = "✕",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		AutoButtonColor = false,
		Parent = header,
	})
	corner(closeBtn, 15)

	-- Tab bar
	local tabBar = new("Frame", {
		Position = UDim2.new(0, 12, 0, 58),
		Size = UDim2.new(1, -24, 0, 34),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		Parent = tabBar,
	})

	local content = new("Frame", {
		Position = UDim2.new(0, 12, 0, 100),
		Size = UDim2.new(1, -24, 1, -112),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	UI.content = content
	UI.pages = {}
	UI.tabs = {}

	local TAB_NAMES = { "Steal", "Ovos", "Ranking", "Config" }

	for i, name in ipairs(TAB_NAMES) do
		local btn = new("TextButton", {
			Size = UDim2.new(0.25, -5, 1, 0),
			BackgroundColor3 = Config.Theme.Panel,
			Font = Enum.Font.GothamMedium,
			Text = name,
			TextColor3 = Config.Theme.Text,
			TextSize = 13,
			AutoButtonColor = false,
			Parent = tabBar,
		})
		corner(btn, 8)
		UI.tabs[name] = btn

		local page = new("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = Config.Theme.Accent,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Visible = false,
			Parent = content,
		})
		new("UIListLayout", { Padding = UDim.new(0, 8), Parent = page })
		UI.pages[name] = page

		btn.MouseButton1Click:Connect(function() UI.showPage(name) end)
	end

	-- Drag do painel
	local dragging, dragStart, startPos = false, nil, nil
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
			local d = input.Position - dragStart
			panel.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y
			)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	-- Abrir/fechar
	local isOpen = false
	local function setOpen(state)
		isOpen = state
		if state then
			panel.Visible = true
			panel.Size = UDim2.fromOffset(480, 0)
			TweenService:Create(panel,
				TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(480, 560) }):Play()
		else
			local t = TweenService:Create(panel, TweenInfo.new(0.2),
				{ Size = UDim2.fromOffset(480, 0) })
			t:Play()
			t.Completed:Connect(function() panel.Visible = false end)
		end
	end
	openBtn.MouseButton1Click:Connect(function() setOpen(not isOpen) end)
	closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)

	UI.showPage("Steal")
end

function UI.showPage(name)
	for k, p in pairs(UI.pages) do p.Visible = (k == name) end
	for k, b in pairs(UI.tabs) do
		TweenService:Create(b, TweenInfo.new(0.15), {
			BackgroundColor3 = (k == name) and Config.Theme.Accent or Config.Theme.Panel,
		}):Play()
	end
end

-- Componentes
local function createToggle(parent, labelText, getVal, setVal)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Config.Theme.Panel,
		Parent = parent,
	})
	corner(row, 8)
	new("TextLabel", {
		Size = UDim2.new(1, -80, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = labelText,
		TextColor3 = Config.Theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local btn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(46, 24),
		BackgroundColor3 = getVal() and Config.Theme.Success or Config.Theme.PanelAlt,
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})
	corner(btn, 12)
	local knob = new("Frame", {
		Size = UDim2.fromOffset(20, 20),
		Position = getVal() and UDim2.new(1, -22, 0, 2) or UDim2.new(0, 2, 0, 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = btn,
	})
	corner(knob, 10)
	btn.MouseButton1Click:Connect(function()
		local nv = not getVal()
		setVal(nv)
		TweenService:Create(btn, TweenInfo.new(0.18), {
			BackgroundColor3 = nv and Config.Theme.Success or Config.Theme.PanelAlt,
		}):Play()
		TweenService:Create(knob, TweenInfo.new(0.18), {
			Position = nv and UDim2.new(1, -22, 0, 2) or UDim2.new(0, 2, 0, 2),
		}):Play()
	end)
end

local function createNumberInput(parent, labelText, getVal, setVal)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Config.Theme.Panel,
		Parent = parent,
	})
	corner(row, 8)
	new("TextLabel", {
		Size = UDim2.new(0.5, -12, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = labelText,
		TextColor3 = Config.Theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local box = new("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(180, 28),
		BackgroundColor3 = Config.Theme.PanelAlt,
		Font = Enum.Font.Gotham,
		Text = tostring(getVal()),
		TextColor3 = Config.Theme.Text,
		PlaceholderText = "Ex: 1000000",
		TextSize = 13,
		ClearTextOnFocus = false,
		Parent = row,
	})
	corner(box, 6)
	box.FocusLost:Connect(function()
		local n = tonumber(box.Text:gsub("[^%d%.]", ""))
		if n then setVal(n); box.Text = tostring(n) else box.Text = tostring(getVal()) end
	end)
end

local function createDropdown(parent, labelText, options, getVal, setVal)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Config.Theme.Panel,
		Parent = parent,
	})
	corner(row, 8)
	new("TextLabel", {
		Size = UDim2.new(0.5, -12, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = labelText,
		TextColor3 = Config.Theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local current = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(160, 28),
		BackgroundColor3 = Config.Theme.PanelAlt,
		Font = Enum.Font.Gotham,
		Text = tostring(getVal()),
		TextColor3 = Config.Theme.Text,
		TextSize = 13,
		AutoButtonColor = false,
		Parent = row,
	})
	corner(current, 6)

	local list = new("Frame", {
		Position = UDim2.new(1, -12, 0, 38),
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(160, 0),
		BackgroundColor3 = Config.Theme.PanelAlt,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 15,
		Parent = row,
	})
	corner(list, 6)
	new("UIListLayout", { Parent = list })
	local opened = false
	current.MouseButton1Click:Connect(function()
		opened = not opened
		if opened then
			list.Visible = true
			TweenService:Create(list, TweenInfo.new(0.15), {
				Size = UDim2.fromOffset(160, #options * 26),
			}):Play()
		else
			list.Visible = false
			list.Size = UDim2.fromOffset(160, 0)
		end
	end)
	for _, opt in ipairs(options) do
		local b = new("TextButton", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = tostring(opt),
			TextColor3 = Config.Theme.Text,
			TextSize = 13,
			Parent = list,
		})
		b.MouseEnter:Connect(function() b.BackgroundTransparency = 0.8 end)
		b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
		b.MouseButton1Click:Connect(function()
			setVal(opt)
			current.Text = tostring(opt)
			opened = false
			list.Visible = false
			list.Size = UDim2.fromOffset(160, 0)
		end)
	end
end

-- ============================================================
-- 6. PÁGINAS DA UI
-- ============================================================

-- Página STEAL
local function buildStealPage()
	local page = UI.pages.Steal
	createToggle(page, "Auto Steal", function() return Config.AutoSteal end,
		function(v) Config.AutoSteal = v end)
	createToggle(page, "Instant Steal", function() return Config.InstantSteal end,
		function(v) Config.InstantSteal = v end)
	createToggle(page, "Priorizar maior valor", function() return Config.PrioritizeBest end,
		function(v) Config.PrioritizeBest = v end)
	createToggle(page, "Apenas melhor ovo", function() return Config.FilterBestOnly end,
		function(v) Config.FilterBestOnly = v end)

	createDropdown(page, "Valor mínimo (presets)",
		{ "1M+", "10M+", "100M+", "1B+", "10B+", "100B+", "Personalizado" },
		function()
			local v = Config.MinValue
			if v >= 1e11 then return "100B+" end
			if v >= 1e10 then return "10B+" end
			if v >= 1e9  then return "1B+"  end
			if v >= 1e8  then return "100M+" end
			if v >= 1e7  then return "10M+"  end
			if v >= 1e6  then return "1M+"   end
			return "Personalizado"
		end,
		function(opt)
			local map = { ["1M+"]=1e6, ["10M+"]=1e7, ["100M+"]=1e8,
				["1B+"]=1e9, ["10B+"]=1e10, ["100B+"]=1e11 }
			if map[opt] then Config.MinValue = map[opt] end
		end)

	createNumberInput(page, "Valor mínimo (custom)", function() return Config.MinValue end,
		function(v) Config.MinValue = v end)

	-- Info do alvo atual
	local info = new("Frame", {
		Size = UDim2.new(1, 0, 0, 80),
		BackgroundColor3 = Config.Theme.Panel,
		Parent = page,
	})
	corner(info, 8)
	stroke(info, Config.Theme.Accent, 1.5, 0.2)
	local infoTitle = new("TextLabel", {
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.new(0, 12, 0, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "🎯 Alvo atual: nenhum",
		TextColor3 = Config.Theme.Accent2,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = info,
	})
	local infoSub = new("TextLabel", {
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 12, 0, 36),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Valor esperado: —",
		TextColor3 = Config.Theme.SubText,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = info,
	})
	local infoSub2 = new("TextLabel", {
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 12, 0, 54),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Melhor criatura: —",
		TextColor3 = Config.Theme.SubText,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = info,
	})

	RunService.Heartbeat:Connect(function()
		local t = StealController.CurrentTarget
		if t then
			infoTitle.Text = "🎯 Alvo atual: " .. t.Name
			infoSub.Text = "Valor esperado: " .. EggAnalyzer.formatNumber(t.ExpectedValue)
			infoSub2.Text = "Melhor criatura: " .. t.BestCreature.Name ..
				" (" .. EggAnalyzer.formatNumber(t.BestCreature.Value) .. ")"
		else
			infoTitle.Text = "🎯 Alvo atual: nenhum"
			infoSub.Text = "Valor esperado: —"
			infoSub2.Text = "Melhor criatura: —"
		end
	end)
end

-- Página OVOS — cards detalhados
local function buildEggsPage()
	local page = UI.pages.Ovos
	local container = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = page,
	})
	new("UIListLayout", { Padding = UDim.new(0, 10), Parent = container })

	local function buildCards()
		container:ClearAllChildren()
		new("UIListLayout", { Padding = UDim.new(0, 10), Parent = container })

		local sorted = EggAnalyzer.getSorted()
		if #sorted == 0 then
			local empty = new("TextLabel", {
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				Text = "Nenhum ovo bate com os filtros atuais.",
				TextColor3 = Config.Theme.SubText,
				TextSize = 13,
				Parent = container,
			})
			return
		end

		for _, egg in ipairs(sorted) do
			local card = new("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = Config.Theme.Panel,
				Parent = container,
			})
			corner(card, 10)
			stroke(card, Config.Theme.Border, 1, 0.3)

			local inner = new("Frame", {
				Size = UDim2.new(1, -20, 0, 0),
				Position = UDim2.new(0, 10, 0, 10),
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = card,
			})
			new("UIListLayout", { Padding = UDim.new(0, 4), Parent = inner })

			new("TextLabel", {
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Text = "🥚 " .. egg.Name .. "  •  " .. egg.Rarity,
				TextColor3 = Config.Theme.Text,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = inner,
			})
			new("TextLabel", {
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				Text = "💰 Valor: " .. EggAnalyzer.formatNumber(egg.Value) ..
					"   •   📈 Esperado: " .. EggAnalyzer.formatNumber(egg.ExpectedValue),
				TextColor3 = Config.Theme.Accent2,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = inner,
			})
			new("TextLabel", {
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				Text = "👑 Melhor: " .. egg.BestCreature.Name ..
					" (" .. EggAnalyzer.formatNumber(egg.BestCreature.Value) .. ")",
				TextColor3 = Config.Theme.Warning,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = inner,
			})

			for _, c in ipairs(egg.Creatures) do
				local cl = new("TextLabel", {
					Size = UDim2.new(1, 0, 0, 16),
					BackgroundTransparency = 1,
					Font = Enum.Font.Gotham,
					Text = string.format("  %s — %.0f%% — %s",
						c.Name, c.Chance * 100, EggAnalyzer.formatNumber(c.Value)),
					TextColor3 = Config.Theme.SubText,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = inner,
				})
			end

			local pad = new("Frame", {
				Size = UDim2.new(1, 0, 0, 10),
				BackgroundTransparency = 1,
				Parent = card,
			})
		end
	end

	buildCards()
	UI._rebuildEggs = buildCards
end

-- Página RANKING
local function buildRankingPage()
	local page = UI.pages.Ranking
	local container = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = page,
	})

	local function build()
		container:ClearAllChildren()
		new("UIListLayout", { Padding = UDim.new(0, 8), Parent = container })

		local sorted = EggAnalyzer.getSorted()
		local medals = { "🏆 #1", "🥈 #2", "🥉 #3" }
		for i, egg in ipairs(sorted) do
			local label = medals[i] or ("#" .. i)
			local row = new("Frame", {
				Size = UDim2.new(1, 0, 0, 44),
				BackgroundColor3 = i == 1 and Config.Theme.Accent or Config.Theme.Panel,
				Parent = container,
			})
			corner(row, 8)
			new("TextLabel", {
				Size = UDim2.new(0.55, -12, 1, 0),
				Position = UDim2.new(0, 12, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Text = label .. " — " .. egg.Name,
				TextColor3 = Color3.new(1, 1, 1),
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = row,
			})
			new("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.new(0.45, -12, 1, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Text = EggAnalyzer.formatNumber(egg.ExpectedValue) .. " EV",
				TextColor3 = Color3.new(1, 1, 1),
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = row,
			})
		end
	end

	build()
	UI._rebuildRanking = build
end

-- Página CONFIG — filtros avançados
local function buildConfigPage()
	local page = UI.pages.Config
	createNumberInput(page, "Valor máximo", function() return Config.MaxValue end,
		function(v) Config.MaxValue = v end)
	createNumberInput(page, "Renda mínima", function() return Config.MinIncome end,
		function(v) Config.MinIncome = v end)
	createDropdown(page, "Raridade mínima",
		{ "Comum", "Raro", "Lendário", "Mítico", "Divino", "Supremo" },
		function() return Config.MinRarity end,
		function(v) Config.MinRarity = v end)

	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Config.Theme.Panel,
		Parent = page,
	})
	corner(row, 8)
	new("TextLabel", {
		Size = UDim2.new(0.5, -12, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Apenas criatura (nome)",
		TextColor3 = Config.Theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local box = new("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(180, 28),
		BackgroundColor3 = Config.Theme.PanelAlt,
		Font = Enum.Font.Gotham,
		Text = Config.OnlyCreature,
		PlaceholderText = "Ex: Dragão",
		TextColor3 = Config.Theme.Text,
		TextSize = 13,
		ClearTextOnFocus = false,
		Parent = row,
	})
	corner(box, 6)
	box.FocusLost:Connect(function()
		Config.OnlyCreature = box.Text
	end)

	createToggle(page, "Apenas ovos com criatura rara (≤10%)",
		function() return Config.FilterRareChance end,
		function(v) Config.FilterRareChance = v end)

	local apply = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = Config.Theme.Accent,
		Font = Enum.Font.GothamBold,
		Text = "Aplicar filtros",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 14,
		AutoButtonColor = false,
		Parent = page,
	})
	corner(apply, 8)
	apply.MouseButton1Click:Connect(function()
		if UI._rebuildEggs then UI._rebuildEggs() end
		if UI._rebuildRanking then UI._rebuildRanking() end
	end)
end

-- ============================================================
-- 7. BOOTSTRAP
-- ============================================================
UI.build()
buildStealPage()
buildEggsPage()
buildRankingPage()
buildConfigPage()
StealController.start()

-- Rebuild automático do ranking a cada 5s (caso filtros mudem)
task.spawn(function()
	while true do
		task.wait(5)
		if UI._rebuildRanking then UI._rebuildRanking() end
	end
end)

print("[StealAnEgg] Sistema carregado. Clique em 🥚 para abrir.")
