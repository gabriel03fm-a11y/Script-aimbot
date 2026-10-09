--[[
    BLADE BALL SUITE — v4.2 "DELTA-READY"
    Anti-detect mantido + compat total com Delta (Android/iOS)
    - sem setfenv obrigatório
    - getfenv(n) só se o Delta suportar (auto-probe)
    - rawget em _G opcional
    - clique via ambiente isolado quando possível
]]

-- REG compatível
local REG
pcall(function() REG = rawget(_G, "__BB_SUITE_REG__") end)
if not REG then
    REG = (getgenv and getgenv()) or _G
    pcall(function() rawset(_G, "__BB_SUITE_REG__", REG) end)
end
if REG.BB_Suite_Conns then
    for _, c in ipairs(REG.BB_Suite_Conns) do pcall(function() c:Disconnect() end) end
end
REG.BB_Suite_Conns = {}
local function track(c) table.insert(REG.BB_Suite_Conns, c); return c end

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local UserInputService    = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService        = game:GetService("TweenService")
local HttpService         = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then error("LocalPlayer indisponível") end

-- ═══════════════ CONFIG ═══════════════
local CONFIG_FOLDER = "BladeBallSuite"

local DEFAULT_CONFIG = {
    autoParryEnabled=false, manualSpamEnabled=false,
    delayMs=0, parryRange=40, sensitivity=50,
    legitMode=false, fastReactMode=false, antiRepeatEnabled=true,
    stealthMode=true, missChance=4,
    legitReactionBase=450, legitReactionSpread=120,
    doubleTapChance=10, readingNoise=2,
    antiCheatBypass=true, parryMethod="VIM",
    ballESP=false, ballHighlight=false, showTrajectory=false,
    showDistance=false, showSpeed=false, playerESP=false,
    playerHighlight=false, showThreatIndicator=true,
    uiScale=1.0, notifications=true, theme="Dark",
    keybindMenu="RightShift", keybindAutoParry="F",
    keybindManualSpam="G", keybindESP="H", keybindLegitMode="J",
    spamFrequency=50,
}

local function hasFS()
    return type(isfolder) == "function" and type(writefile) == "function"
end

local Config = { data = {} }
for k, v in pairs(DEFAULT_CONFIG) do Config.data[k] = v end
function Config:set(k, v) self.data[k] = v end
function Config:get(k) return self.data[k] end
function Config:save(profile)
    if not hasFS() then return false end
    profile = profile or "default"
    return pcall(function()
        if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
        writefile(CONFIG_FOLDER .. "/" .. profile .. ".json", HttpService:JSONEncode(self.data))
    end)
end
function Config:load(profile)
    if not hasFS() then return false end
    profile = profile or "default"
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
Config:load()

local State = {
    currentBall=nil, ballDistance=math.huge, ballSpeed=0,
    lastParryTime=0, threatActive=false,
    missThisThreat=false, committedThreshold=0.45,
}

-- ═══════════════ ANTI-DETECT ═══════════════
local AntiDetect = {}

-- clique "limpo": tenta ambiente isolado, senão usa o VIM direto
local cleanClick
do
    local fn
    pcall(function()
        local chunk = loadstring([[
            local D = ...
            return function(x, y, down)
                D:GetService("VirtualInputManager"):SendMouseButtonEvent(x, y, 0, down, D, 0)
            end
        ]])
        if chunk then fn = chunk(game) end
    end)
    if type(fn) == "function" then
        cleanClick = fn
    else
        cleanClick = function(x, y, down)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, down, game, 0)
        end
    end
end

local HIDE_LIST = {"writefile","readfile","isfile","isfolder","makefolder",
    "getgenv","getrenv","hookfunction","getconnections","getnamecallmethod",
    "getrawmetatable","setreadonly","identifyexecutor","getcustomasset",
    "getscriptbytecode","decompile","setclipboard","loadstring"}

local _savedGlobals = {}
local _getfenvOK = nil

local function probeGetfenv()
    if _getfenvOK ~= nil then return _getfenvOK end
    local ok, env = pcall(getfenv, 1)
    _getfenvOK = (ok and type(env) == "table")
    return _getfenvOK
end

local function hideGlobals()
    _savedGlobals = {}
    if not config_stealth() then return end
    if not probeGetfenv() then return end
    for depth = 1, 10 do
        local ok, env = pcall(getfenv, depth)
        if not ok or type(env) ~= "table" then break end
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

local function restoreGlobals()
    if not next(_savedGlobals) then return end
    for depth, t in pairs(_savedGlobals) do
        local ok, env = pcall(getfenv, depth)
        if ok and type(env) == "table" then
            for k, v in pairs(t) do pcall(function() env[k] = v end) end
        end
    end
    _savedGlobals = {}
end

-- helper porque hideGlobals é definido antes do Config no arquivo real
local function config_stealth()
    return Config and Config.data and Config.data.stealthMode
end

-- ═══════════════ BALL TRACKER ═══════════════
local BallTracker = {}

function BallTracker:getActiveBall()
    local f = workspace:FindFirstChild("Balls")
    if not f then return nil end
    for _, b in ipairs(f:GetChildren()) do
        if b:GetAttribute("realBall") then return b end
    end
    return nil
end

function BallTracker:update()
    local ball = self:getActiveBall()
    State.currentBall = ball
    if not ball then
        State.threatActive = false
        State.ballDistance = math.huge
        return
    end
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local bpos = ball.Position
    State.ballDistance = (bpos - hrp.Position).Magnitude
end

-- ═══════════════ PARRY ═══════════════
local ParryEngine = {}

function ParryEngine:getCooldown()
    return 0.5
end

function ParryEngine:getParryRange()
    return Config:get("parryRange")
end

function ParryEngine:executeParry(force)
    local now = tick()
    if not force then
        if now - State.lastParryTime < self:getCooldown() then return false end
    end
    State.lastParryTime = now

    if Config:get("parryMethod") == "Remote" then
