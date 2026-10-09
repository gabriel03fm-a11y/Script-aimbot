--[[
    BLADE BALL SUITE — v4.0 "GHOST-CLEAN"
    Anti-detect:
      - parry emitido de um ambiente LIMPO (sem writefile) -> burla o probe getfenv
      - sem hooks (__namecall/__index) -> sem detecção de hook
      - bypass opcional do canal de report do AC
      - humanização estatística mantida
]]

local function MAIN()
    local Players             = game:GetService("Players")
    local RunService          = game:GetService("RunService")
    local UserInputService    = game:GetService("UserInputService")
    local VirtualInputManager = game:GetService("VirtualInputManager")
    local TweenService        = game:GetService("TweenService")
    local HttpService         = game:GetService("HttpService")

    local LocalPlayer = Players.LocalPlayer
    if not LocalPlayer then error("LocalPlayer indisponível") end

    local REG = (getgenv and getgenv()) or _G
    if REG.BB_Suite_Conns then
        for _, c in ipairs(REG.BB_Suite_Conns) do pcall(function() c:Disconnect() end) end
    end
    REG.BB_Suite_Conns = {}
    local function track(c) table.insert(REG.BB_Suite_Conns, c); return c end

    local CONFIG_FOLDER = "BladeBallSuite"
    local PARRY_COOLDOWN = 0.5

    local DEFAULT_CONFIG = {
        autoParryEnabled=false, manualSpamEnabled=false,
        delayMs=0, parryRange=40, sensitivity=50,
        legitMode=false, fastReactMode=false, antiRepeatEnabled=true,
        stealthMode=true, missChance=4,
        legitReactionBase=450, legitReactionSpread=120,
        doubleTapChance=10, readingNoise=2,
        antiCheatBypass=true, parryMethod="VIM",   -- "VIM" | "Remote"
        ballESP=false, ballHighlight=false, showTrajectory=false,
        showDistance=false, showSpeed=false, playerESP=false,
        playerHighlight=false, showThreatIndicator=true,
        uiScale=1.0, notifications=true, theme="Dark",
        keybindMenu="RightShift", keybindAutoParry="F",
        keybindManualSpam="G", keybindESP="H", keybindLegitMode="J",
        spamFrequency=50,
    }

    local ConfigManager = {}
    ConfigManager.__index = ConfigManager
    function ConfigManager.new()
        local self = setmetatable({}, ConfigManager)
        self.currentProfile = "default"
        self.data = {}
        for k, v in pairs(DEFAULT_CONFIG) do self.data[k] = v end
        return self
    end
    function ConfigManager:set(k, v) self.data[k] = v end
    function ConfigManager:get(k) return self.data[k] end

    local function hasFS()
        return type(isfolder) == "function" and type(writefile) == "function"
    end
    function ConfigManager:save(profile)
        if not hasFS() then return false end
        profile = profile or self.currentProfile
        return pcall(function()
            if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
            writefile(CONFIG_FOLDER .. "/" .. profile .. ".json", HttpService:JSONEncode(self.data))
        end)
    end
    function ConfigManager:load(profile)
        if not hasFS() then return false end
        profile = profile or self.currentProfile
        local ok, data = pcall(function()
            local p = CONFIG_FOLDER .. "/" .. profile .. ".json"
            if isfile(p) then return HttpService:JSONDecode(readfile(p)) end
        end)
        if ok and data then
            for k, v in pairs(data) do if DEFAULT_CONFIG[k] ~= nil then self.data[k] = v end end
            return true
        end
        return false
    end
    function ConfigManager:reset()
        for k, v in pairs(DEFAULT_CONFIG) do self.data[k] = v end
        self:save()
    end

    local config = ConfigManager.new()

    -- ═══════════════ ESTADO ═══════════════
    local State = {
        currentBall=nil, ballTarget=nil, ballDistance=math.huge,
        ballSpeed=0, ballPosition=Vector3.zero,
        localHRP=nil, lastParryTime=0,
        threatActive=false, committedThreshold=0.45,
        missThisThreat=false, willDouble=false, doubleDone=false,
        turboActive=false,
        fps=0, ping=0, ui={},
    }

    -- ═══════════════ ANTI-DETECT ═══════════════
    -- (1) Click emitido de um ambiente sem globais do executor.
    --     O AC roda getfenv(1..10) dentro do sender do parry; se achar
    --     'writefile' em qualquer frame, reporta -> kick. Ambiente limpo evita isso.
    local AntiDetect = {}

    function AntiDetect.buildCleanClick()
        local src = [[return function(x, y, down)
            game:GetService("VirtualInputManager"):SendMouseButtonEvent(x, y, 0, down, game, 0)
        end]]
        local ok, fn = pcall(function()
            local chunk = loadstring(src, "=ReplicatedStorage.Packages._Index.sleitnick_net@0.1.0.net")
            if chunk then return chunk() end
        end)
        if ok and type(fn) == "function" then
            -- ambiente SEM writefile / getrenv / etc.
            pcall(function() setfenv(fn, { game = game }) end)
            return fn
        end
        -- fallback (funciona, mas roda no env global)
        return function(x, y, down)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, down, game, 0)
        end
    end

    -- (2) Bypass opcional do canal de report do AC (best-effort).
    function AntiDetect.runBypass()
        if not config:get("antiCheatBypass") then return false end
        local did = false
        pcall(function()
            local rs = game:GetService("ReplicatedStorage")
            local sec = rs:FindFirstChild("Security")
            if sec then
                for _, c in ipairs(sec:GetChildren()) do pcall(function() c:Destroy() end) end
                pcall(function() sec:Destroy() end)
                did = true
            end
        end)
        pcall(function()
            local ps = LocalPlayer:FindFirstChild("PlayerScripts")
            local client = ps and ps:FindFirstChild("Client")
            local dc = client and client:FindFirstChild("DeviceChecker")
            if dc then dc:Destroy(); did = true end
        end)
        return did
    end

    local cleanClick = AntiDetect.buildCleanClick()

    -- ═══════════════ BALL TRACKER ═══════════════
    local BallTracker = {}
    BallTracker.__index = BallTracker
    function BallTracker.new() return setmetatable({}, BallTracker) end
    function BallTracker:getActiveBall()
        local f = workspace:FindFirstChild("Balls")
        if not f then return nil end
        for _, b in ipairs(f:GetChildren()) do
            if b:GetAttribute("realBall") then return b end
        end
        return nil
    end
    function BallTracker:start()
        local folder = workspace:FindFirstChild("Balls")
        if folder then
            track(folder.ChildAdded:Connect(function()
                task.wait(0.1); State.currentBall = self:getActiveBall()
            end))
        end
        track(RunService.PreSimulation:Connect(function()
            local ball = self:getActiveBall()
            if not ball then State.currentBall = nil return end
            State.currentBall = ball
            pcall(function()
                State.ballTarget   = ball:GetAttribute("target")
                State.ballPosition = ball.Position
                local z = ball:FindFirstChild("zoomies")
                State.ballSpeed = (z and z:IsA("BodyVelocity")) and z.VectorVelocity.Magnitude or 0
            end)
        end))
    end
    local ballTracker = BallTracker.new()

    -- ═══════════════ STEALTH / HUMANIZAÇÃO ═══════════════
    local Stealth = {}
    function Stealth.gauss()
        local u1 = math.max(math.random(), 1e-6)
        local u2 = math.random()
        return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    end
    local function gclamp(mean, sd, lo, hi)
        return math.clamp(mean + Stealth.gauss() * sd, lo, hi)
    end

    function Stealth.clickPoint()
        local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize)
                   or Vector2.new(1280, 720)
        if not config:get("stealthMode") then
            return math.floor(vp.X / 2), math.floor(vp.Y / 2)
        end
        local sx, sy = vp.X * 0.05, vp.Y * 0.05
        local x = vp.X / 2 + Stealth.gauss() * sx
        local y = vp.Y / 2 + Stealth.gauss() * sy
        return math.floor(math.clamp(x, 4, vp.X - 4)),
               math.floor(math.clamp(y, 4, vp.Y - 4))
    end

    function Stealth.holdTime()
        if not config:get("stealthMode") then return 0.02 end
        return gclamp(0.026, 0.011, 0.008, 0.065)
    end

    -- ═══════════════ THREAT ANALYZER ═══════════════
    local ThreatAnalyzer = {}
    ThreatAnalyzer.__index = ThreatAnalyzer
    function ThreatAnalyzer.new() return setmetatable({}, ThreatAnalyzer) end

    function ThreatAnalyzer:isThreat(cfg)
        local ball, hrp = State.currentBall, State.localHRP
        if not ball or not hrp then return false, 0, math.huge end
        if State.ballTarget ~= LocalPlayer.Name then return false, 0, math.huge end

        local ballPos, hrpPos = State.ballPosition, hrp.Position
        local dist  = (hrpPos - ballPos).Magnitude
        if config:get("stealthMode") then
            dist = dist * (1 + Stealth.gauss() * ((cfg.readingNoise or 2) / 100))
        end

        local speed = State.ballSpeed
        if dist > cfg.parryRange or speed < 5 then return false, dist, math.huge end

        local z = ball:FindFirstChild("zoomies")
        if z and z:IsA("BodyVelocity") and z.VectorVelocity.Magnitude > 0.01 then
            local dot = z.VectorVelocity.Unit:Dot((hrpPos - ballPos).Unit)
            if dot < 0.3 then return false, dist, math.huge end
        end
        return true, dist, dist / math.max(speed, 0.1)
    end

    function ThreatAnalyzer:getParryThreshold(cfg)
        local base = (cfg.legitReactionBase or 450) / 1000
        base = base + ((50 - cfg.sensitivity) / 100) * 0.15
        base = base + (cfg.delayMs / 1000)
        if cfg.fastReactMode then base = base * 0.7 end
        if config:get("legitMode") then base = base + 0.03 end
        if config:get("stealthMode") then
            base = base + Stealth.gauss() * ((cfg.legitReactionSpread or 120) / 1000)
        end
        return math.max(0.02, base)
    end
    local threatAnalyzer = ThreatAnalyzer.new()

    -- ═══════════════ PARRY ENGINE ═══════════════
    local _parryRemote
    local function getParryRemote()
        if _parryRemote and _parryRemote.Parent then return _parryRemote end
        local rs = game:GetService("ReplicatedStorage")
        local rem = rs:FindFirstChild("Remotes")
        local r = rem and rem:FindFirstChild("ParryButtonPress")
        _parryRemote = r
        return r
    end

    local ParryEngine = {}
    ParryEngine.__index = ParryEngine
    function ParryEngine.new() return setmetatable({}, ParryEngine) end

    function ParryEngine:getCooldown()
        if State.turboActive then
            local c = 0.035
            if config:get("stealthMode") then c = c * (1 + Stealth.gauss() * 0.18) end
            return math.max(c, 0.02)
        end
        local cd
        if config:get("manualSpamEnabled") then
            cd = config:get("spamFrequency") / 1000
        else
            cd = PARRY_COOLDOWN
        end
        if config:get("stealthMode") then cd = cd * (1 + Stealth.gauss() * 0.12) end
        return math.max(cd, 0.02)
    end

    function ParryEngine:executeParry(force)
        local now = tick()
        if not force then
            if now - State.lastParryTime < ParryEngine:getCooldown() then return false end
            if config:get("antiRepeatEnabled") and (now - State.lastParryTime) < 0.05 then return false end
        end
        State.lastParryTime = now

        -- Método "Remote": dispara o remote do jogo direto (o sender não roda -> sem probe)
        if config:get("parryMethod") == "Remote" then
            local r = getParryRemote()
            if r then
                return pcall(function()
                    if r:IsA("RemoteEvent") then r:FireServer() else r:Fire() end
                end)
            end
        end

        -- Método "VIM": clique real via ambiente limpo
        local cx, cy = Stealth.clickPoint()
        local hold   = Stealth.holdTime()
        return pcall(function()
            cleanClick(cx, cy, true)
            task.wait(hold)
            cleanClick(cx, cy, false)
        end)
    end

    function ParryEngine:update()
        if not State.localHRP then return end

        if config:get("manualSpamEnabled") or State.turboActive then
            ParryEngine:executeParry()
        end

        if not config:get("autoParryEnabled") then
            if State.threatActive then
                State.threatActive = false
                State.willDouble = false
                State.doubleDone = false
                if State.ui.threatIndicator then State.ui.threatIndicator.Visible = false end
            end
            return
        end

        local isThreat, _, tti = threatAnalyzer:isThreat(config.data)

        if isThreat and not State.threatActive then
            State.threatActive = true
            State.doubleDone = false
            State.committedThreshold = threatAnalyzer:getParryThreshold(config.data)

            local mc = config:get("missChance") or 0
            State.missThisThreat = config:get("stealthMode") and (math.random() * 100 < mc)

            local spam = config:get("manualSpamEnabled") or State.turboActive
            State.willDouble = config:get("stealthMode") and not spam
                              and (math.random() * 100 < (config:get("doubleTapChance") or 0))

            if State.ui.threatIndicator and config:get("showThreatIndicator") then
                State.ui.threatIndicator.Visible = true
            end
        elseif not isThreat and State.threatActive then
            State.threatActive = false
            State.willDouble = false
            State.doubleDone = false
            if State.ui.threatIndicator then State.ui.threatIndicator.Visible = false end
        end

        if isThreat and not State.missThisThreat and tti <= State.committedThreshold then
            ParryEngine:executeParry()
            if State.willDouble and not State.doubleDone then
                State.doubleDone = true
                local d = math.random(55, 130) / 1000
                task.delay(d, function() ParryEngine:executeParry(true) end)
            end
        end
    end
    local parryEngine = ParryEngine.new()

    -- ═══════════════ MANUAL SPAM OVERLAY ═══════════════
    local ManualSpam = {}
    ManualSpam.__index = ManualSpam
    function ManualSpam.new() return setmetatable({ _mode="AP", _frame=nil }, ManualSpam) end
    function ManualSpam:create(parent, touch)
        local w, h = touch and 118 or 96, touch and 46 or 32
        local modeW = touch and 42 or 34
        local frame = Instance.new("Frame")
        frame.Name = "ManualSpamButton"
        frame.Size = UDim2.new(0, w, 0, h)
        frame.Position = UDim2.new(0.5, -w/2, 0.86, 0)
        frame.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
        frame.BorderSizePixel = 0; frame.Visible = false; frame.ZIndex = 50
        frame.Parent = parent
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = frame
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(255, 180, 50); stroke.Thickness = 1.2; stroke.Parent = frame
        self._frame, self._stroke = frame, stroke

        local action = Instance.new("TextButton")
        action.Size = UDim2.new(1, -modeW, 1, 0)
        action.BackgroundTransparency = 1; action.Text = ""; action.Parent = frame

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1; label.Text = "AP"
        label.TextColor3 = Color3.new(1,1,1); label.TextScaled = true
        label.Font = Enum.Font.GothamBold; label.Parent = action

        local modeBtn = Instance.new("TextButton")
        modeBtn.Size = UDim2.new(0, modeW, 1, 0)
        modeBtn.Position = UDim2.new(1, -modeW, 0, 0)
        modeBtn.BackgroundColor3 = Color3.fromRGB(0,0,0); modeBtn.BackgroundTransparency = 0.75
        modeBtn.Text = "⇄"; modeBtn.TextColor3 = Color3.new(1,1,1)
        modeBtn.TextSize = touch and 16 or 13; modeBtn.Font = Enum.Font.GothamBold
        modeBtn.Parent = frame
        local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 8); mc.Parent = modeBtn

        local function applyMode()
            if self._mode == "AP" then
                label.Text = "AP"
                frame.BackgroundColor3 = Color3.fromRGB(255,140,0)
                stroke.Color = Color3.fromRGB(255,180,50)
            else
                label.Text = "TB"
                frame.BackgroundColor3 = Color3.fromRGB(0,120,215)
                stroke.Color = Color3.fromRGB(0,160,255)
            end
        end
        applyMode()

        modeBtn.MouseButton1Click:Connect(function()
            self._mode = (self._mode == "AP") and "TB" or "AP"
            State.turboActive = false
            applyMode()
        end)

        local dragging, downPos, downTime, startPos
        action.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                dragging = true; downPos = i.Position; downTime = tick(); startPos = frame.Position
                if self._mode == "TB" then State.turboActive = true end
            end
        end)
        track(UserInputService.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then
                local d = i.Position - downPos
                frame.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end))
        action.InputEnded:Connect(function(i)
            if not dragging then return end
            dragging = false
            if self._mode == "TB" then
                State.turboActive = false
            else
                local moved = (i.Position - downPos).Magnitude > 10
                if not moved and (tick() - downTime) < 0.5 then
                    ParryEngine:executeParry()
                end
            end
        end)
        return self
    end
    function ManualSpam:setVisible(v) if self._frame then self._frame.Visible = v end end

    -- ═══════════════ VISUALS ═══════════════
    local Visuals = {}
    Visuals.__index = Visuals
    function Visuals.new()
        return setmetatable({ _highlight=nil, _espGui=nil, _trajPool={}, _playerGuis={}, _frame=0 }, Visuals)
    end
    function Visuals:initTrajectory()
        local old = workspace:FindFirstChild("BB_Suite_Trajectory")
        if old then old:Destroy() end
        local folder = Instance.new("Folder"); folder.Name = "BB_Suite_Trajectory"; folder.Parent = workspace
        self._trajFolder = folder; self._trajPool = {}
        for i = 1, 8 do
            local p = Instance.new("Part")
            p.Shape = Enum.PartType.Ball
            p.Size = Vector3.new(0.3, 0.3, 0.3)
            p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
            p.Material = Enum.Material.Neon
            p.Color = Color3.fromRGB(255, 140, 0); p.Transparency = 1
            p.Parent = folder
            table.insert(self._trajPool, p)
        end
    end
    function Visuals:updateBallHighlight()
        local ball = State.currentBall
        if not ball or not config:get("ballHighlight") then
            if self._highlight then self._highlight:Destroy() self._highlight = nil end
            return
        end
        if not self._highlight or self._highlight.Parent ~= ball then
            if self._highlight then self._highlight:Destroy() end
            local hl = Instance.new("Highlight")
            hl.FillTransparency = 0.6; hl.OutlineTransparency = 0.2
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent = ball
            self._highlight = hl
        end
        local d = State.ballDistance
        if d < 15 then self._highlight.FillColor = Color3.fromRGB(255, 50, 50)
        elseif d < 40 then self._highlight.FillColor = Color3.fromRGB(255, 180, 0)
        else self._highlight.FillColor = Color3.fromRGB(0, 200, 100) end
        self._highlight.OutlineColor = self._highlight.FillColor:Lerp(Color3.new(1,1,1), 0.4)
    end
    function Visuals:updateBallESP()
        local ball = State.currentBall
        if not ball or not config:get("ballESP") then
            if self._espGui then self._espGui:Destroy() self._espGui = nil end
            return
        end
        if not self._espGui or self._espGui.Parent ~= ball then
            if self._espGui then self._espGui:Destroy() end
            local gui = Instance.new("BillboardGui")
            gui.Name = "BallESP"; gui.Size = UDim2.new(0, 150, 0, 40)
            gui.StudsOffset = Vector3.new(0, 3, 0); gui.AlwaysOnTop = true; gui.Parent = ball
            local lbl = Instance.new("TextLabel")
            lbl.Name = "InfoLabel"; lbl.Size = UDim2.new(1,0,1,0)
            lbl.BackgroundTransparency = 1; lbl.TextSize = 14
            lbl.Font = Enum.Font.GothamBold; lbl.TextStrokeTransparency = 0.5; lbl.Parent = gui
            self._espGui = gui
        end
        local parts = {}
        if config:get("showDistance") then table.insert(parts, string.format("Dist: %.0f", State.ballDistance)) end
        if config:get("showSpeed")    then table.insert(parts, string.format("Spd: %.0f", State.ballSpeed)) end
        if #parts == 0 then table.insert(parts, "BALL") end
        local lbl = self._espGui:FindFirstChild("InfoLabel")
        if lbl then
            lbl.Text = table.concat(parts, " | ")
            if State.ballDistance < 15 then lbl.TextColor3 = Color3.fromRGB(255,60,60)
            elseif State.ballDistance < 40 then lbl.TextColor3 = Color3.fromRGB(255,200,0)
            else lbl.TextColor3 = Color3.fromRGB(100,255,100) end
        end
    end
    function Visuals:updateTrajectory()
        if not self._trajPool then return end
        local show = config:get("showTrajectory")
        local ball, hrp = State.currentBall, State.localHRP
        if not show or not ball or not hrp then
            for _, p in ipairs(self._trajPool) do p.Transparency = 1 end
            return
        end
        local dir = hrp.Position - State.ballPosition
        local dist = dir.Magnitude
        if dist < 1 then
            for _, p in ipairs(self._trajPool) do p.Transparency = 1 end
            return
        end
        dir = dir.Unit
        local steps = math.min(#self._trajPool, math.floor(dist / 5))
        for i = 1, #self._trajPool do
            local p = self._trajPool[i]
            if i <= steps then
                p.Position = State.ballPosition + dir * (dist * i / (steps + 1))
                p.Transparency = 0.4
            else
                p.Transparency = 1
            end
        end
    end
    function Visuals:updatePlayerESP()
        for plr, gui in pairs(self._playerGuis) do
            if not plr.Parent or not plr.Character then
                gui:Destroy(); self._playerGuis[plr] = nil
            end
        end
        if not config:get("playerESP") then
            for plr, gui in pairs(self._playerGuis) do gui:Destroy() self._playerGuis[plr] = nil end
            return
        end
        local hrp = State.localHRP
        if not hrp then return end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local char = plr.Character
                local head = char and char:FindFirstChild("Head")
                if not head then
                    if self._playerGuis[plr] then
                        self._playerGuis[plr]:Destroy(); self._playerGuis[plr] = nil
                    end
                else
                    if not self._playerGuis[plr] or self._playerGuis[plr].Parent ~= head then
                        if self._playerGuis[plr] then self._playerGuis[plr]:Destroy() end
                        local gui = Instance.new("BillboardGui")
                        gui.Name = "PlayerESP"; gui.Size = UDim2.new(0, 120, 0, 30)
                        gui.StudsOffset = Vector3.new(0, 2.5, 0); gui.AlwaysOnTop = true; gui.Parent = head
                        local lbl = Instance.new("TextLabel")
                        lbl.Name = "InfoLabel"; lbl.Size = UDim2.new(1,0,1,0)
                        lbl.BackgroundTransparency = 1; lbl.TextSize = 12
                        lbl.Font = Enum.Font.Gotham; lbl.TextStrokeTransparency = 0.5; lbl.Parent = gui
                        self._playerGuis[plr] = gui
                    end
                    local pRoot = char:FindFirstChild("HumanoidRootPart")
                    if pRoot then
                        local dist = (hrp.Position - pRoot.Position).Magnitude
                        local lbl = self._playerGuis[plr]:FindFirstChild("InfoLabel")
                        if lbl then
                            lbl.Text = string.format("%s [%.0f]", plr.Name, dist)
                            lbl.TextColor3 = (State.ballTarget == plr.Name)
                                and Color3.fromRGB(255, 80, 80) or Color3.new(1,1,1)
                        end
                    end
                end
            end
        end
    end
    function Visuals:start()
        self:initTrajectory()
        track(RunService.RenderStepped:Connect(function()
            self._frame += 1
            if State.localHRP and State.currentBall then
                State.ballDistance = (State.localHRP.Position - State.ballPosition).Magnitude
            end
            self:updateBallHighlight()
            self:updateBallESP()
            self:updateTrajectory()
            if self._frame % 2 == 0 then self:updatePlayerESP() end
        end))
    end
    local visuals = Visuals.new()

    -- ═══════════════ UI CORE ═══════════════
    local COLORS = {
        bg=Color3.fromRGB(18,18,22), panel=Color3.fromRGB(25,25,32),
        panelAlt=Color3.fromRGB(32,32,40), accent=Color3.fromRGB(255,140,0),
        text=Color3.fromRGB(230,230,240), textDim=Color3.fromRGB(140,140,160),
        green=Color3.fromRGB(50,200,100), red=Color3.fromRGB(220,60,60),
        border=Color3.fromRGB(50,50,65),
    }
    local DIMS_DESKTOP = {
        windowW=420, windowH=350, titleBarH=30, tabBarH=32,
        tabBtnW=74, tabBtnH=22, rowToggleH=28,
        toggleTrackW=36, toggleTrackH=17, toggleKnob=13,
        sliderH=44, sliderTrackH=5, sliderDragH=16, inputH=32,
        btnRowH=26, scrollThickness=4,
        titleFont=12, labelFont=11, btnFont=10, pad=10,
    }
    local DIMS_TOUCH = {
        windowW=440, windowH=380, titleBarH=42, tabBarH=44,
        tabBtnW=88, tabBtnH=32, rowToggleH=44,
        toggleTrackW=48, toggleTrackH=25, toggleKnob=21,
        sliderH=62, sliderTrackH=9, sliderDragH=34, inputH=44,
        btnRowH=40, scrollThickness=7,
        titleFont=14, labelFont=13, btnFont=12, pad=12,
    }
    local D = DIMS_DESKTOP
    local function isTouch() return UserInputService.TouchEnabled end
    local function getViewport()
        local cam = workspace.CurrentCamera
        return cam and cam.ViewportSize or Vector2.new(1280, 720)
    end
    local function computeUIScale(vp)
        local fit = math.min((vp.X * 0.94) / DIMS_DESKTOP.windowW, (vp.Y * 0.92) / DIMS_DESKTOP.windowH)
        if isTouch() then return math.clamp(fit, 0.85, 1.35) end
        return math.clamp(fit, 0.65, 0.9)
    end

    local UICore = {}
    UICore.__index = UICore
    function UICore.new() return setmetatable({}, UICore) end
    function UICore:_create(cls, props, parent)
        local obj = Instance.new(cls)
        for k, v in pairs(props or {}) do
            if k ~= "Parent" then pcall(function() obj[k] = v end) end
        end
        if parent then obj.Parent = parent end
        return obj
    end
    function UICore:_createToggle(parent, labelText, configKey, callback)
        local frame = self:_create("Frame", {
            Name = "Toggle_" .. configKey, Size = UDim2.new(1, -20, 0, D.rowToggleH),
            BackgroundColor3 = COLORS.panelAlt, BorderSizePixel = 0,
        }, parent)
        self:_create("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)
        self:_create("TextLabel", {
            Size = UDim2.new(1, -(D.toggleTrackW + 30), 1, 0), Position = UDim2.new(0, D.pad, 0, 0),
            BackgroundTransparency = 1, Text = labelText, TextColor3 = COLORS.text,
            TextSize = D.labelFont, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
        }, frame)
        local track2 = self:_create("Frame", {
            Size = UDim2.new(0, D.toggleTrackW, 0, D.toggleTrackH),
            Position = UDim2.new(1, -(D.toggleTrackW + D.pad), 0.5, -D.toggleTrackH/2),
            BackgroundColor3 = COLORS.border, BorderSizePixel = 0,
        }, frame)
        self:_create("UICorner", { CornerRadius = UDim.new(1, 0) }, track2)
        local knob = self:_create("Frame", {
            Size = UDim2.new(0, D.toggleKnob, 0, D.toggleKnob),
            Position = UDim2.new(0, 3, 0.5, -D.toggleKnob/2),
            BackgroundColor3 = COLORS.textDim, BorderSizePixel = 0,
        }, track2)
        self:_create("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
        local btn = self:_create("TextButton", { Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, Text = "" }, frame)
        local onX = D.toggleTrackW - D.toggleKnob - 3
        local state = config:get(configKey) or false
        local function updateVisual(on)
            TweenService:Create(track2, TweenInfo.new(0.2), { BackgroundColor3 = on and COLORS.accent or COLORS.border }):Play()
            TweenService:Create(knob, TweenInfo.new(0.2), {
                Position = UDim2.new(0, on and onX or 3, 0.5, -D.toggleKnob/2),
                BackgroundColor3 = on and Color3.new(1,1,1) or COLORS.textDim }):Play()
        end
        updateVisual(state)
        btn.MouseButton1Click:Connect(function()
            state = not state; config:set(configKey, state); updateVisual(state)
            if callback then pcall(callback, state) end
        end)
        return frame
    end
    function UICore:_createSlider(parent, labelText, configKey, min, max, suffix)
        suffix = suffix or ""
        local frame = self:_create("Frame", {
            Size = UDim2.new(1, -20, 0, D.sliderH), BackgroundColor3 = COLORS.panelAlt, BorderSizePixel = 0,
        }, parent)
        self:_create("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)
        self:_create("TextLabel", {
            Size = UDim2.new(0.6, 0, 0, 20), Position = UDim2.new(0, D.pad, 0, 6),
            BackgroundTransparency = 1, Text = labelText, TextColor3 = COLORS.text,
            TextSize = D.labelFont, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
        }, frame)
        local valueLabel = self:_create("TextLabel", {
            Size = UDim2.new(0.35, 0, 0, 20), Position = UDim2.new(0.62, 0, 0, 6),
            BackgroundTransparency = 1, Text = tostring(config:get(configKey)) .. suffix,
            TextColor3 = COLORS.accent, TextSize = D.labelFont, Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Right,
        }, frame)
        local trackBg = self:_create("Frame", {
            Size = UDim2.new(1, -D.pad*2, 0, D.sliderTrackH),
            Position = UDim2.new(0, D.pad, 1, -(D.sliderTrackH + 10)),
            BackgroundColor3 = COLORS.border, BorderSizePixel = 0,
        }, frame)
        self:_create("UICorner", { CornerRadius = UDim.new(1, 0) }, trackBg)
        local fill = self:_create("Frame", { Size = UDim2.new(0,0,1,0), BackgroundColor3 = COLORS.accent, BorderSizePixel = 0 }, trackBg)
        self:_create("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
        local dragBtn = self:_create("TextButton", {
            Size = UDim2.new(1, D.pad*2, 0, D.sliderDragH),
            Position = UDim2.new(0, -D.pad, 0.5, -D.sliderDragH/2),
            BackgroundTransparency = 1, Text = "",
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
            local tp, ts = trackBg.AbsolutePosition, trackBg.AbsoluteSize
            local pct = math.clamp((input.Position.X - tp.X) / math.max(ts.X, 1), 0, 1)
            updateFromValue(math.floor(min + (max - min) * pct))
        end
        dragBtn.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then dragging = true; processInput(i) end
        end)
        track(UserInputService.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then processInput(i) end
        end))
        track(UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end))
        return frame
    end
    function UICore:_createInput(parent, labelText, configKey, placeholder, isKeybind)
        local frame = self:_create("Frame", {
            Size = UDim2.new(1, -20, 0, D.inputH), BackgroundColor3 = COLORS.panelAlt, BorderSizePixel = 0,
        }, parent)
        self:_create("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)
        self:_create("TextLabel", {
            Size = UDim2.new(0.55, 0, 1, 0), Position = UDim2.new(0, D.pad, 0, 0),
            BackgroundTransparency = 1, Text = labelText, TextColor3 = COLORS.text,
            TextSize = D.labelFont, Font = Enum.Font.Gotham, TextXAlignment = Enum
