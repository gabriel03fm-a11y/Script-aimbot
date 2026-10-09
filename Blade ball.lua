--[[ BLADE BALL SUITE — v5.0 "GHOST-FULL"
     BAC (Blade Ball Anti Cheat) roda getfenv(1..10) no sender do parry e
     reporta se achar 'writefile' em qualquer frame da stack -> kick.
     Defesa: esconde globais de executor durante o clique + env limpo + sem hooks.
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
        antiCheatBypass=true, hideGlobals=true, parryMethod="VIM",
        useRemoteParry=false,
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
        self.currentProfile = "default"; self.data = {}
        for k, v in pairs(DEFAULT_CONFIG) do self.data[k] = v end
        return self
    end
    function ConfigManager:set(k, v) self.data[k] = v end
    function ConfigManager:get(k) return self.data[k] end
    local function hasFS() return type(isfolder)=="function" and type(writefile)=="function" end
    function ConfigManager:save(profile)
        if not hasFS() then return false end
        profile = profile or self.currentProfile
        return pcall(function()
            if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
            writefile(CONFIG_FOLDER.."/"..profile..".json", HttpService:JSONEncode(self.data))
        end)
    end
    function ConfigManager:load(profile)
        if not hasFS() then return false end
        profile = profile or self.currentProfile
        local ok, data = pcall(function()
            local p = CONFIG_FOLDER.."/"..profile..".json"
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

    local State = {
        currentBall=nil, ballTarget=nil, ballDistance=math.huge,
        ballSpeed=0, ballPosition=Vector3.zero,
        localHRP=nil, lastParryTime=0,
        threatActive=false, committedThreshold=0.45,
        missThisThreat=false, willDouble=false, doubleDone=false,
        turboActive=false, fps=0, ping=0, ui={},
    }

    -- ═══════════════ ANTI-DETECT ═══════════════
    local AntiDetect = {}
    local HIDE_LIST = {
        "writefile","readfile","isfile","isfolder","makefolder",
        "getgenv","getrenv","hookfunction","getconnections","getnamecallmethod",
        "getrawmetatable","setreadonly","identifyexecutor","getcustomasset",
        "getscriptbytecode","decompile","setclipboard",
    }
    local _savedGlobals

    function AntiDetect.buildCleanClick()
        local src = [[return function(x, y, down)
            game:GetService("VirtualInputManager"):SendMouseButtonEvent(x, y, 0, down, game, 0)
        end]]
        local ok, fn = pcall(function()
            local chunk = loadstring(src, "=ReplicatedStorage.Packages._Index.sleitnick_net@0.1.0.net")
            if chunk then return chunk() end
        end)
        if ok and type(fn) == "function" then
            pcall(function() setfenv(fn, { game = game }) end)
            return fn
        end
        return function(x, y, down)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, down, game, 0)
        end
    end

    function AntiDetect.hideGlobals()
        if not config:get("hideGlobals") then return end
        _savedGlobals = {}
        local env = getfenv(1)
        for _, k in ipairs(HIDE_LIST) do
            if env[k] ~= nil then _savedGlobals[k] = env[k]; env[k] = nil end
        end
    end
    function AntiDetect.restoreGlobals()
        if not _savedGlobals then return end
        local env = getfenv(1)
        for k, v in pairs(_savedGlobals) do env[k] = v end
        _savedGlobals = nil
    end

    function AntiDetect.runBypass()
        if not config:get("antiCheatBypass") then return false end
        local did = false
        pcall(function()
            local rs = game:GetService("ReplicatedStorage")
            local sec = rs:FindFirstChild("Security")
            if sec then
                for _, c in ipairs(sec:GetChildren()) do pcall(function() c:Destroy() end) end
                pcall(function() sec:Destroy() end); did = true
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

    -- ═══════════════ STEALTH ═══════════════
    local Stealth = {}
    function Stealth.gauss()
        local u1 = math.max(math.random(), 1e-6); local u2 = math.random()
        return math.sqrt(-2*math.log(u1))*math.cos(2*math.pi*u2)
    end
    local function gclamp(mean, sd, lo, hi) return math.clamp(mean+Stealth.gauss()*sd, lo, hi) end
    function Stealth.clickPoint()
        local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280,720)
        if not config:get("stealthMode") then return math.floor(vp.X/2), math.floor(vp.Y/2) end
        local sx, sy = vp.X*0.05, vp.Y*0.05
        local x = vp.X/2 + Stealth.gauss()*sx; local y = vp.Y/2 + Stealth.gauss()*sy
        return math.floor(math.clamp(x,4,vp.X-4)), math.floor(math.clamp(y,4,vp.Y-4))
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
        local dist = (hrpPos - ballPos).Magnitude
        if config:get("stealthMode") then
            dist = dist * (1 + Stealth.gauss()*((cfg.readingNoise or 2)/100))
        end
        local speed = State.ballSpeed
        if dist > cfg.parryRange or speed < 5 then return false, dist, math.huge end
        local z = ball:FindFirstChild("zoomies")
        if z and z:IsA("BodyVelocity") and z.VectorVelocity.Magnitude > 0.01 then
            if z.VectorVelocity.Unit:Dot((hrpPos-ballPos).Unit) < 0.3 then return false, dist, math.huge end
        end
        return true, dist, dist/math.max(speed,0.1)
    end
    function ThreatAnalyzer:getParryThreshold(cfg)
        local base = (cfg.legitReactionBase or 450)/1000
        base = base + ((50-cfg.sensitivity)/100)*0.15 + (cfg.delayMs/1000)
        if cfg.fastReactMode then base = base*0.7 end
        if config:get("legitMode") then base = base + 0.03 end
        if config:get("stealthMode") then base = base + Stealth.gauss()*((cfg.legitReactionSpread or 120)/1000) end
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
        _parryRemote = r; return r
    end

    local ParryEngine = {}
    ParryEngine.__index = ParryEngine
    function ParryEngine.new() return setmetatable({}, ParryEngine) end
    function ParryEngine:getCooldown()
        if State.turboActive then
            local c = 0.035
            if config:get("stealthMode") then c = c*(1+Stealth.gauss()*0.18) end
            return math.max(c, 0.02)
        end
        local cd = config:get("manualSpamEnabled") and (config:get("spamFrequency")/1000) or PARRY_COOLDOWN
        if config:get("stealthMode") then cd = cd*(1+Stealth.gauss()*0.12) end
        return math.max(cd, 0.02)
    end

    function ParryEngine:executeParry(force)
        local now = tick()
        if not force then
            if now - State.lastParryTime < ParryEngine:getCooldown() then return false end
            if config:get("antiRepeatEnabled") and (now - State.lastParryTime) < 0.05 then return false end
        end
        State.lastParryTime = now

        if config:get("parryMethod") == "Remote" then
            local r = getParryRemote()
            if r then
                return pcall(function()
                    if r:IsA("RemoteEvent") then r:FireServer() else r:Fire() end
                end)
            end
        end

        local cx, cy = Stealth.clickPoint()
        local hold   = Stealth.holdTime()
        return pcall(function()
            -- esconde globais de executor -> stack limpa no instante do envio do parry
            AntiDetect.hideGlobals()
            cleanClick(cx, cy, true)
            AntiDetect.restoreGlobals()
            task.wait(hold)
            cleanClick(cx, cy, false)
        end)
    end

    function ParryEngine:update()
        if not State.localHRP then return end
        if config:get("manualSpamEnabled") or State.turboActive then ParryEngine:executeParry() end
        if not config:get("autoParryEnabled") then
            if State.threatActive then
                State.threatActive = false; State.willDouble = false; State.doubleDone = false
                if State.ui.threatIndicator then State.ui.threatIndicator.Visible = false end
            end
            return
        end
        local isThreat, _, tti = threatAnalyzer:isThreat(config.data)
        if isThreat and not State.threatActive then
            State.threatActive = true; State.doubleDone = false
            State.committedThreshold = threatAnalyzer:getParryThreshold(config.data)
            State.missThisThreat = config:get("stealthMode") and (math.random()*100 < (config:get("missChance") or 0))
            local spam = config:get("manualSpamEnabled") or State.turboActive
            State.willDouble = config:get("stealthMode") and not spam
                              and (math.random()*100 < (config:get("doubleTapChance") or 0))
            if State.ui.threatIndicator and config:get("showThreatIndicator") then
                State.ui.threatIndicator.Visible = true
            end
        elseif not isThreat and State.threatActive then
            State.threatActive = false; State.willDouble = false; State.doubleDone = false
            if State.ui.threatIndicator then State.ui.threatIndicator.Visible = false end
        end
        if isThreat and not State.missThisThreat and tti <= State.committedThreshold then
            ParryEngine:executeParry()
            if State.willDouble and not State.doubleDone then
                State.doubleDone = true
                task.delay(math.random(55,130)/1000, function() ParryEngine:executeParry(true) end)
            end
        end
    end
    local parryEngine = ParryEngine.new()

    -- ═══════════════ MANUAL SPAM OVERLAY ═══════════════
    local ManualSpam = {}
    ManualSpam.__index = ManualSpam
    function ManualSpam.new() return setmetatable({ _mode="AP" }, ManualSpam) end
    function ManualSpam:create(parent, touch)
        local w, h = touch and 118 or 96, touch and 46 or 32
        local modeW = touch and 42 or 34
        local frame = Instance.new("Frame")
        frame.Name = "ManualSpamButton"; frame.Size = UDim2.new(0,w,0,h)
        frame.Position = UDim2.new(0.5,-w/2,0.86,0); frame.BackgroundColor3 = Color3.fromRGB(255,140,0)
        frame.BorderSizePixel = 0; frame.Visible = false; frame.ZIndex = 50; frame.Parent = parent
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,8); corner.Parent = frame
        local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(255,180,50)
        stroke.Thickness = 1.2; stroke.Parent = frame
        self._frame, self._stroke = frame, stroke
        local action = Instance.new("TextButton"); action.Size = UDim2.new(1,-modeW,1,0)
        action.BackgroundTransparency = 1; action.Text = ""; action.Parent = frame
        local label = Instance.new("TextLabel"); label.Size = UDim2.new(1,0,1,0)
        label.BackgroundTransparency = 1; label.Text = "AP"; label.TextColor3 = Color3.new(1,1,1)
        label.TextScaled = true; label.Font = Enum.Font.GothamBold; label.Parent = action
        local modeBtn = Instance.new("TextButton"); modeBtn.Size = UDim2.new(0,modeW,1,0)
        modeBtn.Position = UDim2.new(1,-modeW,0,0); modeBtn.BackgroundColor3 = Color3.fromRGB(0,0,0)
        modeBtn.BackgroundTransparency = 0.75; modeBtn.Text = "⇄"; modeBtn.TextColor3 = Color3.new(1,1,1)
        modeBtn.TextSize = touch and 16 or 13; modeBtn.Font = Enum.Font.GothamBold; modeBtn.Parent = frame
        local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0,8); mc.Parent = modeBtn
        local function applyMode()
            if self._mode == "AP" then label.Text = "AP"
                frame.BackgroundColor3 = Color3.fromRGB(255,140,0); stroke.Color = Color3.fromRGB(255,180,50)
            else label.Text = "TB"
                frame.BackgroundColor3 = Color3.fromRGB(0,120,215); stroke.Color = Color3.fromRGB(0,160,255) end
        end
        applyMode()
        modeBtn.MouseButton1Click:Connect(function()
            self._mode = (self._mode=="AP") and "TB" or "AP"; State.turboActive = false; applyMode()
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
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
            end
        end))
        action.InputEnded:Connect(function(i)
            if not dragging then return end
            dragging = false
            if self._mode == "TB" then State.turboActive = false
            else
                if (i.Position-downPos).Magnitude <= 10 and (tick()-downTime) < 0.5 then
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
    function Visuals.new() return setmetatable({ _trajPool={}, _playerGuis={}, _frame=0 }, Visuals) end
    function Visuals:initTrajectory()
        local old = workspace:FindFirstChild("BB_Suite_Trajectory"); if old then old:Destroy() end
        local folder = Instance.new("Folder"); folder.Name = "BB_Suite_Trajectory"; folder.Parent = workspace
        self._trajFolder = folder; self._trajPool = {}
        for _ = 1, 8 do
            local p = Instance.new("Part"); p.Shape = Enum.PartType.Ball
            p.Size = Vector3.new(0.3,0.3,0.3); p.Anchored = true; p.CanCollide = false
            p.CanQuery = false; p.CanTouch = false; p.Material = Enum.Material.Neon
            p.Color = Color3.fromRGB(255,140,0); p.Transparency = 1; p.Parent = folder
            table.insert(self._trajPool, p)
        end
    end
    function Visuals:updateBallHighlight()
        local ball = State.currentBall
        if not ball or not config:get("ballHighlight") then
            if self._highlight then self._highlight:Destroy() self._highlight = nil end; return
        end
        if not self._highlight or self._highlight.Parent ~= ball then
            if self._highlight then self._highlight:Destroy() end
            local hl = Instance.new("Highlight"); hl.FillTransparency = 0.6
            hl.OutlineTransparency = 0.2; hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent = ball; self._highlight = hl
        end
        local d = State.ballDistance
        if d < 15 then self._highlight.FillColor = Color3.fromRGB(255,50,50)
        elseif d < 40 then self._highlight.FillColor = Color3.fromRGB(255,180,0)
        else self._highlight.FillColor = Color3.fromRGB(0,200,100) end
        self._highlight.OutlineColor = self._highlight.FillColor:Lerp(Color3.new(1,1,1),0.4)
    end
    function Visuals:updateBallESP()
        local ball = State.currentBall
        if not ball or not config:get("ballESP") then
            if self._espGui then self._espGui:Destroy() self._espGui = nil end; return
        end
        if not self._espGui or self._espGui.Parent ~= ball then
            if self._espGui then self._espGui:Destroy() end
            local gui = Instance.new("BillboardGui"); gui.Name = "BallESP"
            gui.Size = UDim2.new(0,150,0,40); gui.StudsOffset = Vector3.new(0,3,0)
            gui.AlwaysOnTop = true; gui.Parent = ball
            local lbl = Instance.new("TextLabel"); lbl.Name = "InfoLabel"
            lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1; lbl.TextSize = 14
            lbl.Font = Enum.Font.GothamBold; lbl.TextStrokeTransparency = 0.5; lbl.Parent = gui
            self._espGui = gui
        end
        local parts = {}
        if config:get("showDistance") then table.insert(parts, string.format("Dist: %.0f", State.ballDistance)) end
        if config:get("showSpeed") then table.insert(parts, string.format("Spd: %.0f", State.ballSpeed)) end
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
            for _, p in ipairs(self._trajPool) do p.Transparency = 1 end; return
        end
        local dir = hrp.Position - State.ballPosition; local dist = dir.Magnitude
        if dist < 1 then for _, p in ipairs(self._trajPool) do p.Transparency = 1 end; return end
        dir = dir.Unit; local steps = math.min(#self._trajPool, math.floor(dist/5))
        for i = 1, #self._trajPool do
            local p = self._trajPool[i]
            if i <= steps then
                p.Position = State.ballPosition + dir*(dist*i/(steps+1)); p.Transparency = 0.4
            else p.Transparency = 1 end
        end
    end
    function Visuals:updatePlayerESP()
        for plr, gui in pairs(self._playerGuis) do
            if not plr.Parent or not plr.Character then gui:Destroy(); self._playerGuis[plr] = nil end
        end
        if not config:get("playerESP") then
            for plr, gui in pairs(self._playerGuis) do gui:Destroy() self._playerGuis[plr] = nil end; return
        end
        local hrp = State.localHRP; if not hrp then return end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local char = plr.Character; local head = char and char:FindFirstChild("Head")
                if not head then
                    if self._playerGuis[plr] then self._playerGuis[plr]:Destroy(); self._playerGuis[plr] = nil end
                else
                    if not self._playerGuis[plr] or self._playerGuis[plr].Parent ~= head then
                        if self._playerGuis[plr] then self._playerGuis[plr]:Destroy() end
                        local gui = Instance.new("BillboardGui"); gui.Name = "PlayerESP"
                        gui.Size = UDim2.new(0,120,0,30); gui.StudsOffset = Vector3.new(0,2.5,0)
                        gui.AlwaysOnTop = true; gui.Parent = head
                        local lbl = Instance.new("TextLabel"); lbl.Name = "InfoLabel"
                        lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1; lbl.TextSize = 12
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
                                and Color3.fromRGB(255,80,80) or Color3.new(1,1,1)
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
            self:updateBallHighlight(); self:updateBallESP(); self:updateTrajectory()
            if self._frame % 2 == 0 then self:updatePlayerESP() end
        end))
    end
    local visuals = Visuals.new()

    -- ═══════════════ UI ═══════════════
    local COLORS = {
        bg=Color3.fromRGB(18,18,22), panel=Color3.fromRGB(25,25,32),
        panelAlt=Color3.fromRGB(32,32,40), accent=Color3.fromRGB(255,140,0),
        text=Color3.fromRGB(230,230,240), textDim=Color3.fromRGB(140,140,160),
        green=Color3.fromRGB(50,200,100), red=Color3.fromRGB(220,60,60),
        border=Color3.fromRGB(50,50,65),
    }
    local DIMS_DESKTOP = {
        windowW=420, windowH=350, titleBarH=30, tabBarH=32, tabBtnW=74, tabBtnH=22,
        rowToggleH=28, toggleTrackW=36, toggleTrackH=17, toggleKnob=13,
        sliderH=44, sliderTrackH=5, sliderDragH=16, inputH=32, btnRowH=26,
        scrollThickness=4, titleFont=12, labelFont=11, btnFont=10, pad=10,
    }
    local DIMS_TOUCH = {
        windowW=440, windowH=380, titleBarH=42, tabBarH=44, tabBtnW=88, tabBtnH=32,
        rowToggleH=44, toggleTrackW=48, toggleTrackH=25, toggleKnob=21,
        sliderH=62, sliderTrackH=9, sliderDragH=34, inputH=44, btnRowH=40,
        scrollThickness=7, titleFont=14, labelFont=13, btnFont=12, pad=12,
    }
    local D = DIMS_DESKTOP
    local function isTouch() return UserInputService.TouchEnabled end
    local function getViewport()
        local cam = workspace.CurrentCamera; return cam and cam.ViewportSize or Vector2.new(1280,720)
    end
    local function computeUIScale(vp)
        local fit = math.min((vp.X*0.94)/DIMS_DESKTOP.windowW, (vp.Y*0.92)/DIMS_DESKTOP.windowH)
        if isTouch() then return math.clamp(fit,0.85,1.35) end
        return math.clamp(fit,0.65,0.9)
    end
    local UICore = {}
    UICore.__index = UICore
    function UICore.new() return setmetatable({}, UICore) end
    function UICore:_create(cls, props, parent)
        local obj = Instance.new(cls)
        for k, v in pairs(props or {}) do if k ~= "Parent" then pcall(function() obj[k]=v end) end end
        if parent then obj.Parent = parent end
        return obj
    end
    function UICore:_createToggle(parent, labelText, configKey, callback)
        local frame = self:_create("Frame", {
            Name = "Toggle_"..configKey, Size = UDim2.new(1,-20,0,D.rowToggleH),
            BackgroundColor3 = COLORS.panelAlt, BorderSizePixel = 0 }, parent)
        self:_create("UICorner", { CornerRadius = UDim.new(0,6) }, frame)
        self:_create("TextLabel", {
            Size = UDim2.new(1,-(D.toggleTrackW+30),1,0), Position = UDim2.new(0,D.pad,0,0),
            BackgroundTransparency = 1, Text = labelText, TextColor3 = COLORS.text,
            TextSize = D.labelFont, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left }, frame)
        local tr = self:_create("Frame", {
            Size = UDim2.new(0,D.toggleTrackW,0,D.toggleTrackH),
            Position = UDim2.new(1,-(D.toggleTrackW+D.pad),0.5,-D.toggleTrackH/2),
            BackgroundColor3 = COLORS.border, BorderSizePixel = 0 }, frame)
        self:_create("UICorner", { CornerRadius = UDim.new(1,0) }, tr)
        local knob = self:_create("Frame", {
            Size = UDim2.new(0,D.toggleKnob,0,D.toggleKnob),
            Position = UDim2.new(0,3,0.5,-D.toggleKnob/2),
            BackgroundColor3 = COLORS.textDim, BorderSizePixel = 0 }, tr)
        self:_create("UICorner", { CornerRadius = UDim.new(1,0) }, knob)
        local btn = self:_create("TextButton", { Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, Text = "" }, frame)
        local onX = D.toggleTrackW - D.toggleKnob - 3
        local state = config:get(configKey) or false
        local function upd(on)
            TweenService:Create(tr, TweenInfo.new(0.2), { BackgroundColor3 = on and COLORS.accent or COLORS.border }):Play()
            TweenService:Create(knob, TweenInfo.new(0.2), {
                Position = UDim2.new(0, on and onX or 3, 0.5, -D.toggleKnob/2),
                BackgroundColor3 = on and Color3.new(1,1,1) or COLORS.textDim }):Play()
        end
        upd(state)
        btn.MouseButton1Click:Connect(function()
            state = not state; config:set(configKey, state); upd(state)
            if callback then pcall(callback, state) end
        end)
        return frame
    end
    function UICore:_createSlider(parent, labelText, configKey, min, max, suffix)
        suffix = suffix or ""
        local frame = self:_create("Frame", {
            Size = UDim2.new(1,-20,0,D.sliderH), BackgroundColor3 = COLORS.panelAlt, BorderSizePixel = 0 }, parent)
        self:_create("UICorner", { CornerRadius = UDim.new(0,6) }, frame)
        self:_create("TextLabel", {
            Size = UDim2.new(0.6,0,0,20), Position = UDim2.new(0,D.pad,0,6), BackgroundTransparency = 1,
            Text = labelText, TextColor3 = COLORS.text, TextSize = D.labelFont,
            Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left }, frame)
        local valueLabel = self:_create("TextLabel", {
            Size = UDim2.new(0.35,0,0,20), Position = UDim2.new(0.62,0,0,6), BackgroundTransparency = 1,
            Text = tostring(config:get(configKey))..suffix, TextColor3 = COLORS.accent,
            TextSize = D.labelFont, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Right }, frame)
        local trackBg = self:_create("Frame", {
            Size = UDim2.new(1,-D.pad*2,0,D.sliderTrackH),
            Position = UDim2.new(0,D.pad,1,-(D.sliderTrackH+10)),
            BackgroundColor3 = COLORS.border, BorderSizePixel = 0 }, frame)
        self:_create("UICorner", { CornerRadius = UDim.new(1,0) }, trackBg)
        local fill = self:_create("Frame", { Size = UDim2.new(0,0,1,0), BackgroundColor3 = COLORS.accent, BorderSizePixel = 0 }, trackBg)
        self:_create("UICorner", { CornerRadius = UDim.new(1,0) }, fill)
        local dragBtn = self:_create("TextButton", {
            Size = UDim2.new(1,D.pad*2,0,D.sliderDragH),
            Position = UDim2.new(0,-D.pad,0.5,-D.sliderDragH/2), BackgroundTransparency = 1, Text = "" }, trackBg)
        local function upd(val)
            val = math.clamp(val, min, max)
            fill.Size = UDim2.new((val-min)/math.max(max-min,0.0001),0,1,0)
            valueLabel.Text = tostring(val)..suffix; config:set(configKey, val)
        end
        upd(config:get(configKey) or min)
        local dragging = false
        local function proc(i)
            local tp, ts = trackBg.AbsolutePosition, trackBg.AbsoluteSize
            upd(math.floor(min + (max-min)*math.clamp((i.Position.X-tp.X)/math.max(ts.X,1),0,1)))
        end
        dragBtn.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then dragging = true; proc(i) end
        end)
        track(UserInputService.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then proc(i) end
        end))
        track(UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end))
        return frame
    end
    function UICore:_createInput(parent, labelText, configKey, placeholder, isKeybind)
        local frame = self:_create("Frame", {
            Size = UDim2.new(1,-20,0,D.inputH), BackgroundColor3 = COLORS.panelAlt, BorderSizePixel = 0 }, parent)
        self:_create("UICorner", { CornerRadius = UDim.new(0,6) }, frame)
        self:_create("TextLabel", {
            Size = UDim2.new(0.55,0,1,0), Position = UDim2.new(0,D.pad,0,0), BackgroundTransparency = 1,
            Text = labelText, TextColor3 = COLORS.text, TextSize = D.labelFont,
            Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left }, frame)
        local boxW = isTouch() and 96 or 72
        local box = self:_create("TextBox", {
            Size = UDim2.new(0,boxW,0,D.inputH-12),
            Position = UDim2.new(1,-(boxW+D.pad),0.5,-(D.inputH-12)/2),
            BackgroundColor3 = COLORS.bg, Text = tostring(config:get(configKey) or ""),
            TextColor3 = COLORS.accent, TextSize = D.labelFont, Font = Enum.Font.GothamBold,
            PlaceholderText = placeholder or "", PlaceholderColor3 = COLORS.textDim, ClearTextOnFocus = false }, frame)
        self:_create("UICorner", { CornerRadius = UDim.new(0,5) }, box)
        box.FocusLost:Connect(function()
            local txt = box.Text
            if isKeybind then config:set(configKey, (txt ~= "" and txt) or (placeholder or ""))
            else config:set(configKey, tonumber(txt) or txt) end
        end)
        return frame
    end
    function UICore:notify(title, text, duration)
        if not config:get("notifications") or not self.screenGui then return end
        duration = duration or 3
        if not self._notifContainer or not self._notifContainer.Parent then
            local touch = isTouch()
            self._notifContainer = self:_create("Frame", {
                Name = "Notifications",
                Size = touch and UDim2.new(1,-20,0,320) or UDim2.new(0,240,1,-20),
                Position = touch and UDim2.new(0,10,0,10) or UDim2.new(1,-250,0,10),
                BackgroundTransparency = 1, ZIndex = 500 }, self.screenGui)
            self:_create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0,5),
                HorizontalAlignment = touch and Enum.HorizontalAlignment.Center or Enum.HorizontalAlignment.Right },
                self._notifContainer)
        end
        local notif = self:_create("Frame", {
            Size = UDim2.new(1,0,0,42), BackgroundColor3 = COLORS.panel, BorderSizePixel = 0 }, self._notifContainer)
        self:_create("UICorner", { CornerRadius = UDim.new(0,6) }, notif)
        self:_create("UIStroke", { Color = COLORS.accent, Thickness = 1, Transparency = 0.6 }, notif)
        self:_create("TextLabel", {
            Size = UDim2.new(1,-20,0,18), Position = UDim2.new(0,12,0,4), BackgroundTransparency = 1,
            Text = title, TextColor3 = COLORS.accent, TextSize = math.max(D.labelFont-1,10),
            Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left }, notif)
        self:_create("TextLabel", {
            Size = UDim2.new(1,-20,0,16), Position = UDim2.new(0,12,0,22), BackgroundTransparency = 1,
            Text = text, TextColor3 = COLORS.textDim, TextSize = math.max(D.labelFont-2,9),
            Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left }, notif)
        local touch = isTouch()
        local startPos = touch and UDim2.new(0,0,0,-50) or UDim2.new(1,40,0,0)
        notif.Position = startPos
        TweenService:Create(notif, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            { Position = UDim2.new(0,0,0,0) }):Play()
        task.delay(duration, function()
            if notif and notif.Parent then
                local tw = TweenService:Create(notif, TweenInfo.new(0.3), { Position = startPos, BackgroundTransparency = 1 })
                tw:Play(); tw.Completed:Connect(function() notif:Destroy() end)
            end
        end)
    end
    function UICore:build()
        D = isTouch() and DIMS_TOUCH or DIMS_DESKTOP
        local pg = LocalPlayer:WaitForChild("PlayerGui", 10)
        if not pg then error("PlayerGui não encontrado") end
        local existing = pg:FindFirstChild("BladeBallSuite"); if existing then existing:Destroy() end
        self.screenGui = self:_create("ScreenGui", {
            Name = "BladeBallSuite", ResetOnSpawn = false,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = not isTouch() }, pg)
        State.ui.screenGui = self.screenGui
        local main = self:_create("Frame", {
            Name = "MainWindow", Size = UDim2.new(0,D.windowW,0,D.windowH),
            AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.new(0.5,0,0.5,0),
            BackgroundColor3 = COLORS.bg, BorderSizePixel = 0, ClipsDescendants = true }, self.screenGui)
        self.mainFrame = main
        self:_create("UICorner", { CornerRadius = UDim.new(0,10) }, main)
        self:_create("UIStroke", { Color = COLORS.border, Thickness = 1 }, main)
        local uiscl = Instance.new("UIScale"); uiscl.Scale = computeUIScale(getViewport()); uiscl.Parent = main
        local cam = workspace.CurrentCamera
        if cam then
            track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                if uiscl and uiscl.Parent then uiscl.Scale = computeUIScale(getViewport()) end
            end))
        end
        local titleBar = self:_create("Frame", {
            Name = "TitleBar", Size = UDim2.new(1,0,0,D.titleBarH),
            BackgroundColor3 = COLORS.panel, BorderSizePixel = 0 }, main)
        self:_create("UICorner", { CornerRadius = UDim.new(0,10) }, titleBar)
        self:_create("Frame", {
            Size = UDim2.new(1,0,0,10), Position = UDim2.new(0,0,1,-10),
            BackgroundColor3 = COLORS.panel, BorderSizePixel = 0 }, titleBar)
        self:_create("TextLabel", {
            Size = UDim2.new(1,-70,1,0), Position = UDim2.new(0,12,0,0), BackgroundTransparency = 1,
            Text = "⚔  BLADE BALL SUITE", TextColor3 = COLORS.accent, TextSize = D.titleFont,
            Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left }, titleBar)
        local closeSize = isTouch() and 30 or 22
        local closeBtn = self:_create("TextButton", {
            Size = UDim2.new(0,closeSize,0,closeSize),
            Position = UDim2.new(1,-(closeSize+8),0.5,-closeSize/2),
            BackgroundColor3 = COLORS.red, Text = "✕", TextColor3 = Color3.new(1,1,1),
            TextSize = isTouch() and 16 or 12, Font = Enum.Font.GothamBold }, titleBar)
        self:_create("UICorner", { CornerRadius = UDim.new(0,6) }, closeBtn)
        closeBtn.MouseButton1Click:Connect(function()
            main.Visible = false; if State.ui.floatingBtn then State.ui.floatingBtn.Visible = true end end)
        local titleDrag = self:_create("TextButton", {
            Size = UDim2.new(1,-(closeSize+20),1,0), BackgroundTransparency = 1, Text = "" }, titleBar)
        local dragging, dragStart, startPos
        titleDrag.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                dragging = true; dragStart = i.Position; startPos = main.Position end
        end)
        track(UserInputService.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then
                local d = i.Position - dragStart
                main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
            end
        end))
        track(UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end))
        local tabBar = self:_create("Frame", {
            Name = "TabBar", Size = UDim2.new(1,0,0,D.tabBarH), Position = UDim2.new(0,0,0,D.titleBarH),
            BackgroundColor3 = COLORS.panel, BorderSizePixel = 0 }, main)
        self:_create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0,5),
            VerticalAlignment = Enum.VerticalAlignment.Center }, tabBar)
        self:_create("UIPadding", { PaddingLeft = UDim.new(0,10) }, tabBar)
        local content = self:_create("Frame", {
            Name = "Content", Size = UDim2.new(1,0,1,-(D.titleBarH+D.tabBarH)),
            Position = UDim2.new(0,0,0,D.titleBarH+D.tabBarH), BackgroundTransparency = 1 }, main)
        local tabNames = { "Combat", "Visuals", "Settings" }
        local tabContents, tabButtons = {}, {}
        for i, name in ipairs(tabNames) do
            local tabBtn = self:_create("TextButton", {
                Name = "Tab_"..name, Size = UDim2.new(0,D.tabBtnW,0,D.tabBtnH),
                BackgroundColor3 = (i==1) and COLORS.accent or COLORS.panelAlt, Text = name,
                TextColor3 = (i==1) and Color3.new(1,1,1) or COLORS.textDim,
                TextSize = D.btnFont, Font = Enum.Font.GothamBold }, tabBar)
            self:_create("UICorner", { CornerRadius = UDim.new(0,6) }, tabBtn)
            tabButtons[name] = tabBtn
            local scroll = self:_create("ScrollingFrame", {
                Name = "Scroll_"..name, Size = UDim2.new(1,-16,1,-8), Position = UDim2.new(0,8,0,4),
                BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = D.scrollThickness,
                ScrollBarImageColor3 = COLORS.accent, CanvasSize = UDim2.new(0,0,0,0), Visible = (i==1) }, content)
            self:_create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0,5) }, scroll)
            tabContents[name] = scroll
            tabBtn.MouseButton1Click:Connect(function()
                for _, o in pairs(tabButtons) do o.BackgroundColor3 = COLORS.panelAlt; o.TextColor3 = COLORS.textDim end
                tabBtn.BackgroundColor3 = COLORS.accent; tabBtn.TextColor3 = Color3.new(1,1,1)
                for _, sc in pairs(tabContents) do sc.Visible = false end
                scroll.Visible = true
            end)
        end
        for _, scroll in pairs(tabContents) do
            local layout = scroll:FindFirstChildOfClass("UIListLayout")
            local function upd() if layout then scroll.CanvasSize = UDim2.new(0,0,0,layout.AbsoluteContentSize.Y+10) end end
            if layout then track(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(upd)) end
            track(scroll.ChildAdded:Connect(function() task.defer(upd) end))
            track(scroll.ChildRemoved:Connect(function() task.defer(upd) end))
            task.defer(upd)
        end
        local combat = tabContents["Combat"]
        self:_create("TextLabel", { Size = UDim2.new(1,-16,0,20), BackgroundTransparency = 1, Text = "⚔  COMBAT",
            TextColor3 = COLORS.accent, TextSize = D.titleFont, Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left }, combat)
        self:_createToggle(combat, "Auto Parry", "autoParryEnabled")
        self:_createToggle(combat, "Manual Spam (AP / TB)", "manualSpamEnabled", function(on)
            if State.ui.manualSpamBtn then State.ui.manualSpamBtn:setVisible(on) end end)
        self:_createSlider(combat, "Delay (ms)", "delayMs", -100, 200, " ms")
        self:_createSlider(combat, "Range", "parryRange", 5, 80, " studs")
        self:_createSlider(combat, "Sensitivity", "sensitivity", 0, 100, "%")
        self:_createToggle(combat, "Legit Mode", "legitMode")
        self:_createToggle(combat, "Fast React", "fastReactMode")
        self:_createToggle(combat, "Anti-Repeat", "antiRepeatEnabled")
        self:_createSlider(combat, "Spam Frequency", "spamFrequency", 10, 500, " ms")
        self:_createToggle(combat, "Stealth Mode", "stealthMode")
        self:_createSlider(combat, "Miss Chance", "missChance", 0, 15, "%")
        self:_createSlider(combat, "Parry Timing", "legitReactionBase", 150, 900, " ms")
        self:_createSlider(combat, "Timing Spread", "legitReactionSpread", 20, 300, " ms")
        self:_createSlider(combat, "Double Tap", "doubleTapChance", 0, 40, "%")
        self:_createSlider(combat, "Reading Noise", "readingNoise", 0, 10, "%")
        local vis = tabContents["Visuals"]
        self:_create("TextLabel", { Size = UDim2.new(1,-16,0,20), BackgroundTransparency = 1, Text = "👁  VISUALS",
            TextColor3 = COLORS.accent, TextSize = D.titleFont, Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left }, vis)
        self:_createToggle(vis, "Ball ESP", "ballESP")
        self:_createToggle(vis, "Ball Highlight", "ballHighlight")
        self:_createToggle(vis, "Show Trajectory", "showTrajectory")
        self:_createToggle(vis, "Show Distance", "showDistance")
        self:_createToggle(vis, "Show Speed", "showSpeed")
        self:_createToggle(vis, "Player ESP", "playerESP")
        self:_createToggle(vis, "Threat Indicator", "showThreatIndicator")
        local st = tabContents["Settings"]
        self:_create("TextLabel", { Size = UDim2.new(1,-16,0,20), BackgroundTransparency = 1, Text = "⚙  SETTINGS",
            TextColor3 = COLORS.accent, TextSize = D.titleFont, Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Left }, st)
        self:_createToggle(st, "Notificações", "notifications")
        self:_createToggle(st, "AC Bypass (Security)", "antiCheatBypass", function(on)
            if on then AntiDetect.runBypass() end end)
        self:_createToggle(st, "Hide Globals (anti-getfenv)", "hideGlobals")
        self:_createToggle(st, "Remote Parry (off = VIM)", "useRemoteParry", function(on)
            config:set("parryMethod", on and "Remote" or "VIM") end)
        self:_createInput(st, "Tecla — Menu", "keybindMenu", "RightShift", true)
        self:_createInput(st, "Tecla — Auto Parry", "keybindAutoParry", "F", true)
        self:_createInput(st, "Tecla — Manual Spam", "keybindManualSpam", "G", true)
        self:_createInput(st, "Tecla — ESP", "keybindESP", "H", true)
        self:_createInput(st, "Tecla — Legit Mode", "keybindLegitMode", "J", true)
        local btnRow = self:_create("Frame", { Size = UDim2.new(1,-16,0,D.btnRowH), BackgroundTransparency = 1 }, st)
        local function mk(label, color, x, fn)
            local b = self:_create("TextButton", {
                Size = UDim2.new(0.32,-4,1,0), Position = UDim2.new(x,0,0,0), BackgroundColor3 = color,
                Text = label, TextColor3 = Color3.new(1,1,1), TextSize = D.btnFont, Font = Enum.Font.GothamBold }, btnRow)
            self:_create("UICorner", { CornerRadius = UDim.new(0,6) }, b)
            b.MouseButton1Click:Connect(fn)
        end
        mk("Salvar", COLORS.green, 0.00, function() self:notify("Config", config:save() and "Salvo!" or "Falha.", 2) end)
        mk("Carregar", Color3.fromRGB(60,120,200), 0.34, function() self:notify("Config", config:load() and "Carregado!" or "Nada salvo.", 2) end)
        mk("Reset", COLORS.red, 0.68, function() config:reset(); self:notify("Config", "Restaurado.", 2) end)
        local fbSize = isTouch() and 50 or 38
        local floatingBtn = self:_create("TextButton", {
            Name = "FloatingButton", Size = UDim2.new(0,fbSize,0,fbSize), Position = UDim2.new(0,16,0.5,-fbSize/2),
            BackgroundColor3 = COLORS.accent, Text = "⚔", TextColor3 = Color3.new(1,1,1),
            TextSize = isTouch() and 24 or 18, Font = Enum.Font.GothamBold, Visible = false, ZIndex = 10 }, self.screenGui)
        self:_create("UICorner", { CornerRadius = UDim.new(1,0) }, floatingBtn)
        floatingBtn.MouseButton1Click:Connect(function() main.Visible = true; floatingBtn.Visible = false end)
        State.ui.floatingBtn = floatingBtn; State.ui.mainWindow = main
        local tw, th = isTouch() and 160 or 110, isTouch() and 26 or 20
        local threat = self:_create("Frame", {
            Name = "ThreatIndicator", Size = UDim2.new(0,tw,0,th), Position = UDim2.new(0.5,-tw/2,0,8),
            BackgroundColor3 = Color3.fromRGB(255,40,40), BorderSizePixel = 0, Visible = false, ZIndex = 100 }, self.screenGui)
        self:_create("UICorner", { CornerRadius = UDim.new(0,6) }, threat)
        self:_create("TextLabel", { Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, Text = "⚠ THREAT DETECTED",
            TextColor3 = Color3.new(1,1,1), TextSize = isTouch() and 12 or 10, Font = Enum.Font.GothamBold }, threat)
        State.ui.threatIndicator = threat
        local sw, sh = isTouch() and 250 or 210, isTouch() and 20 or 18
        local stats = self:_create("Frame", {
            Name = "Stats", Size = UDim2.new(0,sw,0,sh), Position = UDim2.new(1,-(sw+8),1,-(sh+8)),
            BackgroundColor3 = COLORS.panel, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 5 }, self.screenGui)
        self:_create("UICorner", { CornerRadius = UDim.new(0,5) }, stats)
        State.ui.statsLabel = self:_create("TextLabel", { Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1,
            Text = "FPS: -- | Ping: -- | AP: OFF", TextColor3 = COLORS.textDim,
            TextSize = isTouch() and 10 or 9, Font = Enum.Font.Gotham }, stats)
        State.ui.manualSpamBtn = ManualSpam.new(); State.ui.manualSpamBtn:create(self.screenGui, isTouch())
        return self
    end
    function UICore:startStatsLoop()
        local frames, lastTime = 0, tick()
        track(RunService.RenderStepped:Connect(function()
            frames = frames + 1; local now = tick()
            if now - lastTime >= 1 then State.fps = frames; frames = 0; lastTime = now end
        end))
        task.spawn(function()
            while task.wait(0.5) do
                pcall(function()
                    if State.ui.statsLabel then
                        State.ui.statsLabel.Text = string.format("FPS: %d | AP: %s | MS: %s | Glob: %s",
                            State.fps, config:get("autoParryEnabled") and "ON" or "OFF",
                            config:get("manualSpamEnabled") and "ON" or "OFF",
                            config:get("hideGlobals") and "ON" or "OFF")
                    end
                end)
            end
        end)
    end
    local ui = UICore.new()

    track(UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        local key = input.KeyCode.Name
        local function m(k) local b = config:get(k); return type(b)=="string" and key:lower()==b:lower() end
        if m("keybindMenu") then
            if State.ui.mainWindow then
                State.ui.mainWindow.Visible = not State.ui.mainWindow.Visible
                if State.ui.floatingBtn then State.ui.floatingBtn.Visible = not State.ui.mainWindow.Visible end
            end
        elseif m("keybindAutoParry") then
            local s = not config:get("autoParryEnabled"); config:set("autoParryEnabled", s)
            ui:notify("Auto Parry", s and "Ativado" or "Desativado", 2)
        elseif m("keybindManualSpam") then
            local s = not config:get("manualSpamEnabled"); config:set("manualSpamEnabled", s)
            if State.ui.manualSpamBtn then State.ui.manualSpamBtn:setVisible(s) end
            ui:notify("Manual Spam", s and "Ativado" or "Desativado", 2)
        elseif m("keybindESP") then
            local s = not config:get("ballESP"); config:set("ballESP", s); config:set("ballHighlight", s)
            ui:notify("ESP", s and "Ativado" or "Desativado", 2)
        elseif m("keybindLegitMode") then
            local s = not config:get("legitMode"); config:set("legitMode", s)
            ui:notify("Legit Mode", s and "Ativado" or "Desativado", 2)
        end
    end))

    local function bindChar(char)
        local hrp = char:WaitForChild("HumanoidRootPart", 10); if hrp then State.localHRP = hrp end
    end
    if LocalPlayer.Character then bindChar(LocalPlayer.Character) end
    track(LocalPlayer.CharacterAdded:Connect(bindChar))
    track(LocalPlayer.CharacterRemoving:Connect(function() State.localHRP = nil end))

    config:load()
    AntiDetect.runBypass()
    ui:build()
    ui:startStatsLoop()
    ballTracker:start()
    visuals:start()
    track(RunService.PreSimulation:Connect(function()
        pcall(function() parryEngine:update() end)
    end))

    task.wait(0.5)
    ui:notify("Blade Ball Suite", "Pronto! RightShift para abrir.", 4)
    print("[BB] Script inicializado.")
end

local ok, err = xpcall(MAIN, function(e) return tostring(e).."\n"..debug.traceback("", 2) end)
if not ok then warn("[BB] ERRO FATAL:\n"..tostring(err)); print("[BB] ERRO FATAL:\n"..tostring(err)) end
