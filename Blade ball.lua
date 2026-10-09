--[[ BLADE BALL SUITE — v5.1 "GHOST-FULL"
     BAC roda getfenv(1..10) no parry -> agora varremos todos os frames.
     cleanClick usa chunk anônimo com env vazio + DataModel por upvalue.
     hideGlobals cobre down E release (env limpo durante todo o clique).
     REG via rawget/rawset -> sem referência viva a getgenv nas closures.
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

    -- [MOD 1] REG via _G puro (sem getgenv vivo nas closures depois do boot)
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

    -- [MOD 2] cleanClick: chunk anônimo, env vazio, DataModel por upvalue (sem 'game')
    function AntiDetect.buildCleanClick()
        local src = [[local DataModel = ... ; return function(x, y, down)
            DataModel:GetService("VirtualInputManager"):SendMouseButtonEvent(x, y, 0, down, DataModel, 0)
        end]]
        local ok, fn = pcall(function()
            local chunk = loadstring(src, "")   -- nome anônimo = "?" no traceback
            if chunk then return chunk(game) end
        end)
        if ok and type(fn) == "function" then
            pcall(setfenv, fn, {})   -- env mínimo: só o DataModel como upvalue
            return fn
        end
        return function(x, y, down)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, down, game, 0)
        end
    end

    -- [MOD 3] varre TODOS os frames (igual o BAC) e esconde as globais
    function AntiDetect.hideGlobals()
        if not config:get("hideGlobals") then return end
        _savedGlobals = {}
        for depth = 1, 10 do
            local ok, env = pcall(getfenv, depth)
            if not ok or not env then break end
            _savedGlobals[depth] = {}
            for _, k in ipairs(HIDE_LIST) do
                local ok2, v = pcall(function() return env[k] end)
                if ok2 and v ~= nil then
                    _savedGlobals[depth][k] = v
                    pcall(function() env[k] = nil end)
                end
            end
        end
    end
    function AntiDetect.restoreGlobals()
        if not _savedGlobals then return end
        for depth, tbl in pairs(_savedGlobals) do
            local ok, env = pcall(getfenv, depth)
            if ok and env then
                for k, v in pairs(tbl) do pcall(function() env[k] = v end) end
            end
        end
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
   
