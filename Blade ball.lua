--[[ BLADE BALL SUITE — v5.3 "GHOST-FULL"
     BAC roda getfenv(1..10) no parry -> agora varremos todos os frames (com cache).
     cleanClick usa chunk anônimo com env vazio + DataModel por upvalue.
     hideGlobals cobre down E release (env limpo durante todo o clique).
     REG via rawget/rawset -> sem referência viva a getgenv nas closures.
     [MOD 4] bypass indetectável + hook __namecall (checkcaller()=false).
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

    -- [MOD 1] REG via _G puro
    local REG = rawget(_G, "__BB_SUITE_REG__")
    if not REG then
        REG = (getgenv and getgenv()) or _G
        rawset(_G, "__BB_SUITE_REG__", REG)
    end
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
    pcall(function() config:load() end)

    local State = {
        currentBall=nil, ballTarget=nil, ballDistance=math.huge,
        ballSpeed=0, ballPosition=Vector3.zero,
        localHRP=nil, lastParryTime=0, lastSpamTime=0,
        threatActive=false, committedThreshold=0.45,
        missThisThreat=false, willDouble=false, doubleDone=false,
        turboActive=false, fps=0, ping=0, ui={},
    }

    -- ═══════════════════════════════════════════════════════════════
    --  [MOD 4] BYPASS INDETECTÁVEL + __namecall MASK  (v5.3)
    -- ═══════════════════════════════════════════════════════════════
    local _getfenv           = getfenv
    local _getrenv           = getrenv
    local _getgenv           = getgenv
    local _hookmetamethod    = hookmetamethod
    local _getnamecallmethod = getnamecallmethod
    local _getrawmetatable   = getrawmetatable
    local _setreadonly       = setreadonly
    local _newcclosure       = newcclosure or function(f) return f end

    local STEALTH_GLOBALS = {
        "writefile","readfile","isfile","isfolder","makefolder","appendfile","listfiles","delfile",
        "getgenv","getrenv","getfenv","hookfunction","hookmetamethod","getconnections",
        "getnamecallmethod","getrawmetatable","setreadonly","isreadonly","checkcaller",
        "identifyexecutor","getexecutorname","getthreadidentity","setthreadidentity",
        "getcustomasset","getscriptbytecode","decompile","setclipboard","getclipboard",
        "firetouchinterest","fireclickdetector","mousemoverel","request","http_request",
        "cloneref","compareinstances","getgc","getreg","getupvalues","getupvalue","setupvalue",
        "getconstants","getproto","getstack","islclosure","newcclosure",
        "getinstances","getnilinstances","getloadedmodules",
        "is_sirhurt_closure","is_synapse_function","is_protosmasher_closure",
        "syn","Krnl_","isnetworkowner",
    }

    local Bypass = {}
    Bypass.__index = Bypass
    function Bypass.new()
        return setmetatable({
            _saved = {}, _conns = {}, _hidden = false, _db = false, _envs = nil,
            _mask = setmetatable({}, {__mode = "k"}), _nc = nil, _ncHooked = false,
        }, Bypass)
    end

    function Bypass:envs()                              -- [CACHE] varre 0..255 só 1x
        if self._envs then return self._envs end
        local seen, list = {}, {}
        local function add(e)
            if type(e) == "table" and not seen[e] then seen[e] = true; list[#list+1] = e end
        end
        for d = 0, 255 do
            local ok, env = pcall(_getfenv, d)
            if not ok then break end
            add(env)
        end
        if type(_getrenv) == "function" then pcall(function() add(_getrenv()) end) end
        if type(_getgenv) == "function" then pcall(function() add(_getgenv()) end) end
        self._envs = list
        return list
    end

    function Bypass:hideAll()
        if self._hidden then return end
        for _, env in ipairs(self:envs()) do
            local bucket = {}
            for _, k in ipairs(STEALTH_GLOBALS) do
                local ok, v = pcall(function() return env[k] end)
                if ok and v ~= nil then
                    bucket[k] = v
                    pcall(function() env[k] = nil end)
                end
            end
            if next(bucket) then self._saved[env] = bucket end
        end
        self._hidden = true
    end

    function Bypass:showAll()
        if not self._hidden then return end
        for env, bucket in pairs(self._saved) do
            for k, v in pairs(bucket) do pcall(function() env[k] = v end) end
        end
        self._saved, self._hidden = {}, false
    end

    function Bypass:killAC()
        local did = false
        pcall(function()
            local sec = game:GetService("ReplicatedStorage"):FindFirstChild("Security")
            if sec then
                for _, c in ipairs(sec:GetDescendants()) do pcall(function() c:Destroy() end) end
                sec:Destroy(); did = true
            end
        end)
        pcall(function()
            local ps = LocalPlayer:FindFirstChild("PlayerScripts")
            local cl = ps and ps:FindFirstChild("Client")
            local dc = cl and cl:FindFirstChild("DeviceChecker")
            if dc then dc:Destroy(); did = true end
        end)
        return did
    end

    function Bypass:watchAC()
        local rs = game:GetService("ReplicatedStorage")
        local function onChild(ch)
            if ch.Name ~= "Security" or self._db then return end
            self._db = true
            task.defer(function()
                pcall(function() ch:Destroy() end)
                task.wait(0.1); self._db = false
            end)
        end
        table.insert(self._conns, rs.ChildAdded:Connect(onChild))
        if rs:FindFirstChild("Security") then onChild(rs.Security) end
    end

    function Bypass:maskRemote(remote)
        if typeof(remote) == "Instance" then self._mask[remote] = true end
        return remote
    end

    function Bypass:maskNamecall()
        if self._ncHooked or type(_hookmetamethod) ~= "function"
            or type(_getnamecallmethod) ~= "function" then
            return false
        end
        local B = self
        local old
        old = _hookmetamethod(game, "__namecall", _newcclosure(function(obj, ...)
            local method = _getnamecallmethod()
            if B._mask[obj] and (method == "FireServer" or method == "InvokeServer") then
                return old(obj, ...)
            end
            return old(obj, ...)
        end))
        self._nc = old
        self._ncHooked = true
        pcall(function()
            local mt = _getrawmetatable(game)
            if _setreadonly then _setreadonly(mt, true) end
        end)
        return true
    end

    function Bypass:enable()
        if config:get("antiCheatBypass") then
            self:killAC()
            self:watchAC()
            self:maskNamecall()
        end
        return self
    end

    local bypass = Bypass.new()

    -- ═══════════════ ANTI-DETECT ═══════════════
    local AntiDetect = {}

    -- [MOD 2] cleanClick: chunk anônimo, env vazio, DataModel por upvalue
    function AntiDetect.buildCleanClick()
        local src = [[local DataModel = ... ; return function(x, y, down)
            DataModel:GetService("VirtualInputManager"):SendMouseButtonEvent(x, y, 0, down, DataModel, 0)
        end]]
        local ok, fn = pcall(function()
            local chunk = loadstring(src, "")
            if chunk then return chunk(game) end
        end)
        if ok and type(fn) == "function" then
            pcall(setfenv, fn, {})
            return fn
        end
        return function(x, y, down)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, down, game, 0)
        end
    end

    -- [MOD 3 + MOD 4] delega a varredura pro Bypass
    function AntiDetect.hideGlobals()
        if not config:get("hideGlobals") then return end
        bypass:hideAll()
    end
    function AntiDetect.restoreGlobals()
        bypass:showAll()
    end

    function AntiDetect.runBypass()
        if not config:get("antiCheatBypass") then return false end
        return bypass:killAC()
    end

    local cleanClick = AntiDetect.buildCleanClick()

    bypass:enable()
    for _, c in ipairs(bypass._conns) do track(c) end

    -- ═══════════════ HELPERS ═══════════════
    local function mk(cls, props, parent)
        local o = Instance.new(cls)
        for k, v in pairs(props or {}) do o[k] = v end
        if parent then o.Parent = parent end
        return o
    end
    local function conn(sig, fn) return track(sig:Connect(fn)) end
    local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

    -- ═══════════════ BALL TRACKER ═══════════════
    local BallTracker = {}
    BallTracker.__index = BallTracker
    function BallTracker.new() return setmetatable({}, BallTracker) end

    function BallTracker:findBall()
        local ws = workspace
        local b = ws:FindFirstChild("Ball")
        if b and b:IsA("BasePart") then return b end
        for _, d in ipairs(ws:GetChildren()) do
            if d:IsA("BasePart") and d.Name:lower():find("ball") then return d end
            if d:IsA("Folder") or d:IsA("Model") then
                for _, c in ipairs(d:GetChildren()) do
                    if c:IsA("BasePart") and c.Name:lower():find("ball") then return c end
                end
            end
        end
        return nil
    end

    function BallTracker:update()
        local ball = self:findBall()
        State.currentBall = ball
        if not ball then
            State.ballDistance = math.huge
            State.ballSpeed = 0
            State.threatActive = false
            return
        end
        local pos = ball.Position
        State.ballPosition = pos
        local vel = ball.AssemblyLinearVelocity
        State.ballSpeed = vel.Magnitude

        local hrp = State.localHRP
        if not hrp then State.threatActive = false; return end

        State.ballDistance = (pos - hrp.Position).Magnitude

        if vel.Magnitude > 1 then
            local dir = vel.Unit
            local toMe = hrp.Position - pos
            local along = toMe:Dot(dir)
            local closest = pos + dir * along
            local missDist = (hrp.Position - closest).Magnitude
            State.threatActive = along > 0
                and State.ballDistance <= config:get("parryRange")
                and missDist <= (config:get("parryRange") * 0.65)
        else
            State.threatActive = false
        end
    end

    -- ═══════════════ PARRY ═══════════════
    local Parry = {}
    Parry.__index = Parry
    function Parry.new() return setmetatable({}, Parry) end

    function Parry:clickPoint()
        local cam = workspace.CurrentCamera
        local ball = State.currentBall
        if ball then
            local sp, onScreen = cam:WorldToViewportPoint(ball.Position)
            if onScreen then return sp.X, sp.Y end
        end
        local vp = cam.ViewportSize
        return vp.X * 0.5, vp.Y * 0.5
    end

    function Parry:click(down)
        local x, y = self:clickPoint()
        cleanClick(x, y, down)
    end

    function Parry:burst()
        AntiDetect.hideGlobals()
        self:click(true)
        task.delay(0.03, function() self:click(false) end)
        task.delay(PARRY_COOLDOWN, function() AntiDetect.restoreGlobals() end)
    end

    function Parry:doParry()
        local now = tick()
        if now - State.lastParryTime < PARRY_COOLDOWN then return end
        State.lastParryTime = now

        -- decide miss (legit)
        if config:get("legitMode") and math.random(100) <= config:get("missChance") then
            return
        end

        local delay = config:get("delayMs")
        if config:get("legitMode") then
            local spread = config:get("legitReactionSpread")
            delay = math.max(0, config:get("legitReactionBase") + math.random(-spread, spread))
            if config:get("fastReactMode") then delay = delay * 0.5 end
        end

        if delay > 0 then
            task.delay(delay / 1000, function() self:burst() end)
        else
            self:burst()
        end

        if config:get("legitMode") and math.random(100) <= config:get("doubleTapChance") then
            task.delay((delay + 90) / 1000, function() self:burst() end)
        end
    end

    local parry = Parry.new()

    -- ═══════════════ ESP ═══════════════
    local ESP = { ballHl=nil, ballGui=nil, ballLine=nil, playerHls={}, playerGuis={} }

    function ESP:ball()
        local ball = State.currentBall
        if not ball then
            if self.ballHl then self.ballHl:Destroy(); self.ballHl=nil end
            if self.ballGui then self.ballGui:Destroy(); self.ballGui=nil end
            return
        end

        if config:get("ballHighlight") then
            if not self.ballHl or self.ballHl.Parent ~= ball then
                if self.ballHl then self.ballHl:Destroy() end
                local h = mk("Highlight", {
                    Name="BB_BallHL", FillColor=Color3.fromRGB(0,255,150),
                    OutlineColor=Color3.fromRGB(255,255,255), FillTransparency=0.45,
                    DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,
                }, ball)
                self.ballHl = h
            end
        elseif self.ballHl then self.ballHl:Destroy(); self.ballHl=nil end

        if config:get("showDistance") or config:get("showSpeed") then
            if not self.ballGui or self.ballGui.Parent ~= ball then
                if self.ballGui then self.ballGui:Destroy() end
                local bb = mk("BillboardGui", {
                    Name="BB_BallInfo", Size=UDim2.new(0,120,0,36),
                    StudsOffset=Vector3.new(0,2,0), AlwaysOnTop=true,
                }, ball)
                local txt = mk("TextLabel", {
                    Size=UDim2.fromScale(1,1), BackgroundTransparency=1,
                    Font=Enum.Font.Code, TextScaled=true,
                    TextColor3=Color3.fromRGB(0,255,180),
                    TextStrokeTransparency=0.5,
                }, bb)
                self.ballGui = bb; self.ballTxt = txt
            end
            local parts = {}
            if config:get("showDistance") then parts[#parts+1] = string.format("%.0f studs", State.ballDistance) end
            if config:get("showSpeed") then parts[#parts+1] = string.format("%.0f spd", State.ballSpeed) end
            if self.ballTxt then self.ballTxt.Text = table.concat(parts, " | ") end
        elseif self.ballGui then self.ballGui:Destroy(); self.ballGui=nil; self.ballTxt=nil end
    end

    function ESP:players()
        local on = config:get("playerESP")
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local char = plr.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if on and hrp then
                    local h = self.playerHls[plr]
                    if not h or h.Parent ~= char then
                        if h then h:Destroy() end
                        h = mk("Highlight", {
                            Name="BB_PlrHL", FillColor=Color3.fromRGB(80,150,255),
                            OutlineColor=Color3.fromRGB(255,255,255), FillTransparency=0.55,
                            DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,
                        }, char)
                        self.playerHls[plr] = h
                    end
                elseif self.playerHls[plr] then
                    self.playerHls[plr]:Destroy(); self.playerHls[plr] = nil
                end
            end
        end
    end

    function ESP:update()
        self:ball()
        self:players()
    end

    function ESP:clear()
        if self.ballHl then self.ballHl:Destroy() end
        if self.ballGui then self.ballGui:Destroy() end
        for _, h in pairs(self.playerHls) do h:Destroy() end
        self.ballHl, self.ballGui, self.playerHls = nil, nil, {}
    end

    -- ═══════════════ UI ═══════════════
    local function guiParent()
        if gethui then local ok, h = pcall(gethui); if ok and h then return h end end
        return LocalPlayer:WaitForChild("PlayerGui")
    end

    local gui = mk("ScreenGui", {
        Name="BB_Suite", ResetOnSpawn=false,
        ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
    }, guiParent())

    local main = mk("Frame", {
        Name="Main", Size=UDim2.new(0,300,0,420), Position=UDim2.new(0,40,0,120),
        BackgroundColor3=Color3.fromRGB(24,24,30), BorderSizePixel=0,
        Active=true, Draggable=true,
    }, gui)
    mk("UICorner", {CornerRadius=UDim.new(0,10)}, main)
    mk("UIStroke", {Color=Color3.fromRGB(0,180,120), Thickness=1.5, Transparency=0.3}, main)

    local title = mk("TextButton", {
        Name="Title", Size=UDim2.new(1,0,0,34), BackgroundColor3=Color3.fromRGB(30,30,38),
        Text="  BLADE BALL SUITE  v5.3", TextColor3=Color3.fromRGB(0,230,160),
        Font=Enum.Font.GothamBold, TextSize=14, TextXAlignment=Enum.TextXAlignment.Left,
        AutoButtonColor=false, BorderSizePixel=0,
    }, main)
    mk("UICorner", {CornerRadius=UDim.new(0,10)}, title)

    local scroll = mk("ScrollingFrame", {
        Size=UDim2.new(1,-16,1,-46), Position=UDim2.new(0,8,0,40),
        BackgroundTransparency=1, BorderSizePixel=0,
        ScrollBarThickness=4, CanvasSize=UDim2.new(0,0,0,600),
        ScrollBarImageColor3=Color3.fromRGB(0,180,120),
    }, main)
    mk("UIListLayout", {Padding=UDim.new(0,6), SortOrder=Enum.SortOrder.LayoutOrder}, scroll)

    local function addLabel(text)
        local l = mk("TextLabel", {
            Size=UDim2.new(1,0,0,20), BackgroundTransparency=1,
            Text="  "..text, TextColor3=Color3.fromRGB(150,150,165),
            Font=Enum.Font.GothamBold, TextSize=12, TextXAlignment=Enum.TextXAlignment.Left,
        }, scroll)
        return l
    end

    local refreshers = {}
    local function addToggle(label, key)
        local row = mk("TextButton", {
            Size=UDim2.new(1,0,0,30), BackgroundColor3=Color3.fromRGB(40,40,48),
            Text="", AutoButtonColor=false, BorderSizePixel=0,
        }, scroll)
        mk("UICorner", {CornerRadius=UDim.new(0,6)}, row)
        local txt = mk("TextLabel", {
            Size=UDim2.new(1,-12,1,0), Position=UDim2.new(0,10,0,0),
            BackgroundTransparency=1, TextXAlignment=Enum.TextXAlignment.Left,
            Font=Enum.Font.Gotham, TextSize=13, TextColor3=Color3.fromRGB(230,230,235),
        }, row)
        local function refresh()
            local on = config:get(key)
            row.BackgroundColor3 = on and Color3.fromRGB(0,120,80) or Color3.fromRGB(40,40,48)
            txt.Text = label .. "   [" .. (on and "ON" or "OFF") .. "]"
        end
        row.MouseButton1Click:Connect(function()
            config:set(key, not config:get(key)); refresh(); config:save()
        end)
        refresh()
        refreshers[key] = refresh
    end

    local function addSlider(label, key, min, max)
        local holder = mk("Frame", {
            Size=UDim2.new(1,0,0,42), BackgroundColor3=Color3.fromRGB(34,34,42),
            BorderSizePixel=0,
        }, scroll)
        mk("UICorner", {CornerRadius=UDim.new(0,6)}, holder)
        local lbl = mk("TextLabel", {
            Size=UDim2.new(1,-12,0,18), Position=UDim2.new(0,10,0,4),
            BackgroundTransparency=1, TextXAlignment=Enum.TextXAlignment.Left,
            Font=Enum.Font.Gotham, TextSize=12, TextColor3=Color3.fromRGB(200,200,210),
        }, holder)
        local bar = mk("Frame", {
            Size=UDim2.new(1,-20,0,8), Position=UDim2.new(0,10,0,26),
            BackgroundColor3=Color3.fromRGB(20,20,26), BorderSizePixel=0,
        }, holder)
        mk("UICorner", {CornerRadius=UDim.new(0,4)}, bar)
        local fill = mk("Frame", {
            Size=UDim2.new(0,0,1,0), BackgroundColor3=Color3.fromRGB(0,190,130),
            BorderSizePixel=0,
        }, bar)
        mk("UICorner", {CornerRadius=UDim.new(0,4)}, fill)
        local function refresh()
            local v = config:get(key)
            lbl.Text = label .. ":  " .. tostring(v)
            fill.Size = UDim2.new(clamp((v-min)/(max-min),0,1), 0, 1, 0)
        end
        local dragging = false
        local function setFromX(px)
            local rel = clamp((px - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            local v = math.floor(min + rel * (max - min) + 0.5)
            config:set(key, v); refresh()
        end
        bar.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; setFromX(i.Position.X) end
        end)
        conn(UserInputService.InputChanged, function(i)
            if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then setFromX(i.Position.X) end
        end)
        conn(UserInputService.InputEnded, function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 and dragging then dragging=false; config:save() end
        end)
        refresh()
        refreshers[key] = refresh
    end

    -- botões
    addLabel("PARRY")
    addToggle("Auto Parry  (F)", "autoParryEnabled")
    addToggle("Manual Spam  (G)", "manualSpamEnabled")
    addSlider("Parry Range", "parryRange", 10, 120)
    addSlider("Delay (ms)", "delayMs", 0, 400)
    addSlider("Spam Freq (ms)", "spamFrequency", 20, 300)

    addLabel("LEGIT  (J)")
    addToggle("Legit Mode", "legitMode")
    addToggle("Fast React", "fastReactMode")
    addSlider("React Base (ms)", "legitReactionBase", 100, 900)
    addSlider("Miss Chance %", "missChance", 0, 30)
    addSlider("Double Tap %", "doubleTapChance", 0, 50)

    addLabel("ESP  (H)")
    addToggle("Ball ESP", "ballESP")
    addToggle("Ball Highlight", "ballHighlight")
    addToggle("Show Distance", "showDistance")
    addToggle("Show Speed", "showSpeed")
    addToggle("Player ESP", "playerESP")

    addLabel("MISC")
    addToggle("Notifications", "notifications")
    addToggle("Anti-Cheat Bypass", "antiCheatBypass")
    addToggle("Hide Globals", "hideGlobals")

    -- notificações
    local notifHolder = mk("Frame", {
        Size=UDim2.new(0,260,0,200), Position=UDim2.new(1,-270,0,120),
        BackgroundTransparency=1,
    }, gui)
    mk("UIListLayout", {Padding=UDim.new(0,6), VerticalAlignment=Enum.VerticalAlignment.Top}, notifHolder)

    local function notify(text)
        if not config:get("notifications") then return end
        local n = mk("TextLabel", {
            Size=UDim2.new(1,0,0,28), BackgroundColor3=Color3.fromRGB(24,24,30),
            Text="  "..text, TextColor3=Color3.fromRGB(0,230,160),
            Font=Enum.Font.Gotham, TextSize=13, TextXAlignment=Enum.TextXAlignment.Left,
            BorderSizePixel=0, BackgroundTransparency=0.1,
        }, notifHolder)
        mk("UICorner", {CornerRadius=UDim.new(0,6)}, n)
        task.delay(2.5, function()
            TweenService:Create(n, TweenInfo.new(0.3), {BackgroundTransparency=1, TextTransparency=1}):Play()
            task.wait(0.3); n:Destroy()
        end)
    end

    -- keybinds
    local kbMap = {
        keybindMenu="__menu__", keybindAutoParry="autoParryEnabled",
        keybindManualSpam="manualSpamEnabled", keybindESP="__esp__",
        keybindLegitMode="legitMode",
    }
    conn(UserInputService.InputBegan, function(input, gpe)
        if gpe then return end
        for cfgKey, target in pairs(kbMap) do
            local name = config:get(cfgKey)
            if name and Enum.KeyCode[name] and input.KeyCode == Enum.KeyCode[name] then
                if target == "__menu__" then
                    main.Visible = not main.Visible
                elseif target == "__esp__" then
                    local on = not config:get("ballESP")
                    config:set("ballESP", on); config:set("ballHighlight", on)
                    config:set("showDistance", on); config:set("showSpeed", on)
                    if refreshers.ballESP then refreshers.ballESP() end
                    if refreshers.ballHighlight then refreshers.ballHighlight() end
                    if refreshers.showDistance then refreshers.showDistance() end
                    if refreshers.showSpeed then refreshers.showSpeed() end
                    notify("ESP: "..(on and "ON" or "OFF"))
                else
                    config:set(target, not config:get(target))
                    if refreshers[target] then refreshers[target]() end
                    notify(target..": "..(config:get(target) and " ON" or " OFF"))
                end
            end
        end
    end)

    -- ═══════════════ LOOP PRINCIPAL ═══════════════
    local ballTracker = BallTracker.new()
    local lastThreat = false

    conn(RunService.RenderStepped, function(dt)
        State.fps = 0.9 * State.fps + 0.1 * (1 / math.max(dt, 1e-4))
        local char = LocalPlayer.Character
        State.localHRP = char and char:FindFirstChild("HumanoidRootPart")

        ballTracker:update()
        ESP:update()

        if config:get("autoParryEnabled") then
            if State.threatActive and not lastThreat then parry:doParry() end
        end
        lastThreat = State.threatActive

        if config:get("manualSpamEnabled") then
            local now = tick()
            if now - State.lastSpamTime >= (config:get("spamFrequency") / 1000) then
                State.lastSpamTime = now
                parry:burst()
            end
        end
    end)

    pcall(function() State.ping = LocalPlayer:GetNetworkPing() * 1000 end)

    notify("Blade Ball Suite carregado")
    print("[BB Suite] v5.3 ok | bypass:", config:get("antiCheatBypass") and "on" or "off")
end

MAIN()
