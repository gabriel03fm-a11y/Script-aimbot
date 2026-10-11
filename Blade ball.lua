
--[[ BLADE BALL SUITE v5.4 "GHOST-FULL + TOUCH" ]]
local function MAIN()
    local Players=game:GetService("Players")
    local RunService=game:GetService("RunService")
    local UIS=game:GetService("UserInputService")
    local VIM=game:GetService("VirtualInputManager")
    local Tween=game:GetService("TweenService")
    local Http=game:GetService("HttpService")
    local LP=Players.LocalPlayer
    if not LP then error("LocalPlayer indisponível") end

    local REG=rawget(_G,"__BB_SUITE_REG__")
    if not REG then REG=(getgenv and getgenv()) or _G; rawset(_G,"__BB_SUITE_REG__",REG) end
    if REG.BB_Suite_Conns then for _,c in ipairs(REG.BB_Suite_Conns) do pcall(function() c:Disconnect() end) end end
    REG.BB_Suite_Conns={}
    local function track(c) table.insert(REG.BB_Suite_Conns,c); return c end

    local CONFIG_FOLDER="BladeBallSuite"
    local PARRY_COOLDOWN=0.5
    local DEFAULT_CONFIG={
        autoParryEnabled=false,manualSpamEnabled=false,delayMs=0,parryRange=40,sensitivity=50,
        legitMode=false,fastReactMode=false,antiRepeatEnabled=true,stealthMode=true,missChance=4,
        legitReactionBase=450,legitReactionSpread=120,doubleTapChance=10,readingNoise=2,
        antiCheatBypass=true,hideGlobals=true,parryMethod="VIM",useRemoteParry=false,
        ballESP=false,ballHighlight=false,showTrajectory=false,showDistance=false,showSpeed=false,
        playerESP=false,playerHighlight=false,showThreatIndicator=true,
        uiScale=1.0,notifications=true,theme="Dark",
        keybindMenu="RightShift",keybindAutoParry="F",keybindManualSpam="G",keybindESP="H",keybindLegitMode="J",
        spamFrequency=50,
    }

    local CM={}; CM.__index=CM
    function CM.new() local s=setmetatable({},CM); s.currentProfile="default"; s.data={}
        for k,v in pairs(DEFAULT_CONFIG) do s.data[k]=v end; return s end
    function CM:set(k,v) self.data[k]=v end
    function CM:get(k) return self.data[k] end
    local function hasFS() return type(isfolder)=="function" and type(writefile)=="function" end
    function CM:save(p) if not hasFS() then return false end; p=p or self.currentProfile
        return pcall(function() if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
            writefile(CONFIG_FOLDER.."/"..p..".json",Http:JSONEncode(self.data)) end) end
    function CM:load(p) if not hasFS() then return false end; p=p or self.currentProfile
        local ok,d=pcall(function() local f=CONFIG_FOLDER.."/"..p..".json"
            if isfile(f) then return Http:JSONDecode(readfile(f)) end end)
        if ok and d then for k,v in pairs(d) do if DEFAULT_CONFIG[k]~=nil then self.data[k]=v end end; return true end
        return false end
    function CM:reset() for k,v in pairs(DEFAULT_CONFIG) do self.data[k]=v end; self:save() end
    local config=CM.new(); pcall(function() config:load() end)

    local State={currentBall=nil,ballDistance=math.huge,ballSpeed=0,ballPosition=Vector3.zero,
        localHRP=nil,lastParryTime=0,lastSpamTime=0,threatActive=false,fps=0,ping=0}

    -- ═══════ [MOD 4] BYPASS ═══════
    local _getfenv,_getrenv,_getgenv=getfenv,getrenv,getgenv
    local _hookmetamethod,_getnamecallmethod=hookmetamethod,getnamecallmethod
    local _getrawmetatable,_setreadonly=getrawmetatable,setreadonly
    local _newcclosure=newcclosure or function(f) return f end
    local STEALTH_GLOBALS={
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
        "syn","Krnl_","isnetworkowner"}

    local Bypass={}; Bypass.__index=Bypass
    function Bypass.new() return setmetatable({_saved={},_conns={},_hidden=false,_db=false,_envs=nil,
        _mask=setmetatable({},{__mode="k"}),_nc=nil,_ncHooked=false},Bypass) end
    function Bypass:envs()
        if self._envs then return self._envs end
        local seen,list={},{}
        local function add(e) if type(e)=="table" and not seen[e] then seen[e]=true; list[#list+1]=e end end
        for d=0,255 do local ok,env=pcall(_getfenv,d); if not ok then break end; add(env) end
        if type(_getrenv)=="function" then pcall(function() add(_getrenv()) end) end
        if type(_getgenv)=="function" then pcall(function() add(_getgenv()) end) end
        self._envs=list; return list end
    function Bypass:hideAll()
        if self._hidden then return end
        for _,env in ipairs(self:envs()) do
            local bucket={}
            for _,k in ipairs(STEALTH_GLOBALS) do
                local ok,v=pcall(function() return env[k] end)
                if ok and v~=nil then bucket[k]=v; pcall(function() env[k]=nil end) end
            end
            if next(bucket) then self._saved[env]=bucket end
        end
        self._hidden=true end
    function Bypass:showAll()
        if not self._hidden then return end
        for env,b in pairs(self._saved) do for k,v in pairs(b) do pcall(function() env[k]=v end) end end
        self._saved,self._hidden={},false end
    function Bypass:killAC()
        local did=false
        pcall(function() local sec=game:GetService("ReplicatedStorage"):FindFirstChild("Security")
            if sec then for _,c in ipairs(sec:GetDescendants()) do pcall(function() c:Destroy() end) end
                sec:Destroy(); did=true end end)
        pcall(function() local ps=LP:FindFirstChild("PlayerScripts"); local cl=ps and ps:FindFirstChild("Client")
            local dc=cl and cl:FindFirstChild("DeviceChecker"); if dc then dc:Destroy(); did=true end end)
        return did end
    function Bypass:watchAC()
        local rs=game:GetService("ReplicatedStorage")
        local function onChild(ch) if ch.Name~="Security" or self._db then return end
            self._db=true; task.defer(function() pcall(function() ch:Destroy() end); task.wait(0.1); self._db=false end) end
        table.insert(self._conns,rs.ChildAdded:Connect(onChild))
        if rs:FindFirstChild("Security") then onChild(rs.Security) end end
    function Bypass:maskRemote(r) if typeof(r)=="Instance" then self._mask[r]=true end; return r end
    function Bypass:maskNamecall()
        if self._ncHooked or type(_hookmetamethod)~="function" or type(_getnamecallmethod)~="function" then return false end
        local B=self; local old
        old=_hookmetamethod(game,"__namecall",_newcclosure(function(obj,...)
            local m=_getnamecallmethod()
            if B._mask[obj] and (m=="FireServer" or m=="InvokeServer") then return old(obj,...) end
            return old(obj,...) end))
        self._nc=old; self._ncHooked=true
        pcall(function() local mt=_getrawmetatable(game); if _setreadonly then _setreadonly(mt,true) end end)
        return true end
    function Bypass:enable()
        if config:get("antiCheatBypass") then self:killAC(); self:watchAC(); self:maskNamecall() end
        return self end
    local bypass=Bypass.new()

    -- ═══════ ANTI-DETECT ═══════
    local AntiDetect={}
    function AntiDetect.buildCleanClick()
        local src=[[local D=... ; return function(x,y,d) D:GetService("VirtualInputManager"):SendMouseButtonEvent(x,y,0,d,D,0) end]]
        local ok,fn=pcall(function() local ch=loadstring(src,""); if ch then return ch(game) end end)
        if ok and type(fn)=="function" then pcall(setfenv,fn,{}); return fn end
        return function(x,y,d) VIM:SendMouseButtonEvent(x,y,0,d,game,0) end end
    function AntiDetect.hideGlobals() if config:get("hideGlobals") then bypass:hideAll() end end
    function AntiDetect.restoreGlobals() bypass:showAll() end
    function AntiDetect.runBypass() if not config:get("antiCheatBypass") then return false end; return bypass:killAC() end
    local cleanClick=AntiDetect.buildCleanClick()
    bypass:enable()
    for _,c in ipairs(bypass._conns) do track(c) end

    -- ═══════ HELPERS ═══════
    local function mk(cls,p,parent) local o=Instance.new(cls)
        for k,v in pairs(p or {}) do o[k]=v end; if parent then o.Parent=parent end; return o end
    local function conn(s,f) return track(s:Connect(f)) end
    local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
    local function isPtr(i) return i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch end
    local function makeDraggable(frame,handle)
        local drag,ds,sp
        handle.InputBegan:Connect(function(i) if isPtr(i) then drag=true; ds=i.Position; sp=frame.Position
            local c; c=i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then drag=false; c:Disconnect() end end) end end)
        handle.InputChanged:Connect(function(i) if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local d=i.Position-ds; frame.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y) end end) end

    -- ═══════ BALL TRACKER ═══════
    local BT={}; BT.__index=BT
    function BT.new() return setmetatable({},BT) end
    function BT:find()
        local ws=workspace; local b=ws:FindFirstChild("Ball")
        if b and b:IsA("BasePart") then return b end
        for _,d in ipairs(ws:GetChildren()) do
            if d:IsA("BasePart") and d.Name:lower():find("ball") then return d end
            if d:IsA("Folder") or d:IsA("Model") then
                for _,c in ipairs(d:GetChildren()) do if c:IsA("BasePart") and c.Name:lower():find("ball") then return c end end
            end
        end
        return nil end
    function BT:update()
        local ball=self:find(); State.currentBall=ball
        if not ball then State.ballDistance=math.huge; State.ballSpeed=0; State.threatActive=false; return end
        State.ballPosition=ball.Position
        local vel=ball.AssemblyLinearVelocity; State.ballSpeed=vel.Magnitude
        local hrp=State.localHRP; if not hrp then State.threatActive=false; return end
        State.ballDistance=(ball.Position-hrp.Position).Magnitude
        if vel.Magnitude>1 then
            local dir=vel.Unit; local along=(hrp.Position-ball.Position):Dot(dir)
            local closest=ball.Position+dir*along; local miss=(hrp.Position-closest).Magnitude
            State.threatActive=along>0 and State.ballDistance<=config:get("parryRange") and miss<=(config:get("parryRange")*0.65)
        else State.threatActive=false end end

    -- ═══════ PARRY ═══════
    local Parry={}; Parry.__index=Parry
    function Parry.new() return setmetatable({},Parry) end
    function Parry:pt() local cam=workspace.CurrentCamera; local b=State.currentBall
        if b then local sp,on=cam:WorldToViewportPoint(b.Position); if on then return sp.X,sp.Y end end
        local vp=cam.ViewportSize; return vp.X*0.5,vp.Y*0.5 end
    function Parry:click(d) local x,y=self:pt(); cleanClick(x,y,d) end
    function Parry:burst() AntiDetect.hideGlobals(); self:click(true)
        task.delay(0.03,function() self:click(false) end)
        task.delay(PARRY_COOLDOWN,function() AntiDetect.restoreGlobals() end) end
    function Parry:doParry()
        local now=tick(); if now-State.lastParryTime<PARRY_COOLDOWN then return end; State.lastParryTime=now
        if config:get("legitMode") and math.random(100)<=config:get("missChance") then return end
        local delay=config:get("delayMs")
        if config:get("legitMode") then local s=config:get("legitReactionSpread")
            delay=math.max(0,config:get("legitReactionBase")+math.random(-s,s))
            if config:get("fastReactMode") then delay=delay*0.5 end end
        if delay>0 then task.delay(delay/1000,function() self:burst() end) else self:burst() end
        if config:get("legitMode") and math.random(100)<=config:get("doubleTapChance") then
            task.delay((delay+90)/1000,function() self:burst() end) end end
    local parry=Parry.new()

    -- ═══════ ESP ═══════
    local ESP={ballHl=nil,ballGui=nil,playerHls={}}
    function ESP:ball()
        local b=State.currentBall
        if not b then if self.ballHl then self.ballHl:Destroy(); self.ballHl=nil end
            if self.ballGui then self.ballGui:Destroy(); self.ballGui=nil end; return end
        if config:get("ballHighlight") then
            if not self.ballHl or self.ballHl.Parent~=b then if self.ballHl then self.ballHl:Destroy() end
                self.ballHl=mk("Highlight",{Name="BB_BallHL",FillColor=Color3.fromRGB(0,255,150),
                    OutlineColor=Color3.fromRGB(255,255,255),FillTransparency=0.45,
                    DepthMode=Enum.HighlightDepthMode.AlwaysOnTop},b) end
        elseif self.ballHl then self.ballHl:Destroy(); self.ballHl=nil end
        if config:get("showDistance") or config:get("showSpeed") then
            if not self.ballGui or self.ballGui.Parent~=b then if self.ballGui then self.ballGui:Destroy() end
                local bb=mk("BillboardGui",{Name="BB_Info",Size=UDim2.new(0,140,0,40),StudsOffset=Vector3.new(0,2,0),AlwaysOnTop=true},b)
                self.ballTxt=mk("TextLabel",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
                    Font=Enum.Font.Code,TextScaled=true,TextColor3=Color3.fromRGB(0,255,180),TextStrokeTransparency=0.5},bb)
                self.ballGui=bb end
            local t={}; if config:get("showDistance") then t[#t+1]=string.format("%.0f studs",State.ballDistance) end
            if config:get("showSpeed") then t[#t+1]=string.format("%.0f spd",State.ballSpeed) end
            if self.ballTxt then self.ballTxt.Text=table.concat(t," | ") end
        elseif self.ballGui then self.ballGui:Destroy(); self.ballGui=nil end end
    function ESP:players()
        local on=config:get("playerESP")
        for _,plr in ipairs(Players:GetPlayers()) do if plr~=LP then
            local char=plr.Character; local hrp=char and char:FindFirstChild("HumanoidRootPart")
            if on and hrp then
                local h=self.playerHls[plr]
                if not h or h.Parent~=char then if h then h:Destroy() end
                    h=mk("Highlight",{Name="BB_PlrHL",FillColor=Color3.fromRGB(80,150,255),
                        OutlineColor=Color3.fromRGB(255,255,255),FillTransparency=0.55,
                        DepthMode=Enum.HighlightDepthMode.AlwaysOnTop},char)
                    self.playerHls[plr]=h end
            elseif self.playerHls[plr] then self.playerHls[plr]:Destroy(); self.playerHls[plr]=nil end
        end end end
    function ESP:update() self:ball(); self:players() end

    -- ═══════ [MOD 5] UI TOUCH ═══════
    local function guiParent() if gethui then local ok,h=pcall(gethui); if ok and h then return h end end
        return LP:WaitForChild("PlayerGui") end
    local gui=mk("ScreenGui",{Name="BB_Suite",ResetOnSpawn=false,IgnoreGuiInset=true,
        ZIndexBehavior=Enum.ZIndexBehavior.Sibling},guiParent())

    -- botão flutuante abrir/fechar
    local fab=mk("TextButton",{Name="FAB",Size=UDim2.new(0,58,0,58),Position=UDim2.new(1,-76,0,150),
        BackgroundColor3=Color3.fromRGB(0,150,100),Text="BB",TextColor3=Color3.fromRGB(255,255,255),
        Font=Enum.Font.GothamBold,TextSize=18,BorderSizePixel=0,ZIndex=20},gui)
    mk("UICorner",{CornerRadius=UDim.new(1,0)},fab)
    mk("UIStroke",{Color=Color3.fromRGB(0,230,160),Thickness=1.5},fab)
    makeDraggable(fab,fab)

    local main=mk("Frame",{Name="Main",Size=UDim2.new(0,300,0,430),Position=UDim2.new(0,40,0,120),
        BackgroundColor3=Color3.fromRGB(24,24,30),BorderSizePixel=0,Active=true},gui)
    mk("UICorner",{CornerRadius=UDim.new(0,10)},main)
    mk("UIStroke",{Color=Color3.fromRGB(0,180,120),Thickness=1.5,Transparency=0.3},main)
    local scale=mk("UIScale",{Scale=config:get("uiScale")},main)

    local title=mk("TextButton",{Name="Title",Size=UDim2.new(1,0,0,44),BackgroundColor3=Color3.fromRGB(30,30,38),
        Text="   BLADE BALL SUITE  v5.4",TextColor3=Color3.fromRGB(0,230,160),Font=Enum.Font.GothamBold,
        TextSize=15,TextXAlignment=Enum.TextXAlignment.Left,AutoButtonColor=false,BorderSizePixel=0},main)
    mk("UICorner",{CornerRadius=UDim.new(0,10)},title)
    local close=mk("TextButton",{Name="Close",Size=UDim2.new(0,44,1,0),Position=UDim2.new(1,-44,0,0),
        BackgroundColor3=Color3.fromRGB(180,50,50),Text="X",TextColor3=Color3.fromRGB(255,255,255),
        Font=Enum.Font.GothamBold,TextSize=18,BorderSizePixel=0},title)
    mk("UICorner",{CornerRadius=UDim.new(0,10)},close)
    close.MouseButton1Click:Connect(function() main.Visible=false end)
    makeDraggable(main,title)

    fab.MouseButton1Click:Connect(function() main.Visible=not main.Visible end)

    local scroll=mk("ScrollingFrame",{Size=UDim2.new(1,-16,1,-56),Position=UDim2.new(0,8,0,50),
        BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=8,
        ScrollBarImageColor3=Color3.fromRGB(0,180,120),CanvasSize=UDim2.new(0,0,0,760)},main)
    mk("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},scroll)

    local refreshers={}
    local function addLabel(t) mk("TextLabel",{Size=UDim2.new(1,0,0,22),BackgroundTransparency=1,
        Text="  "..t,TextColor3=Color3.fromRGB(150,150,165),Font=Enum.Font.GothamBold,TextSize=13,
        TextXAlignment=Enum.TextXAlignment.Left},scroll) end
    local function addToggle(label,key)
        local row=mk("TextButton",{Size=UDim2.new(1,0,0,44),BackgroundColor3=Color3.fromRGB(40,40,48),
            Text="",AutoButtonColor=false,BorderSizePixel=0},scroll)
        mk("UICorner",{CornerRadius=UDim.new(0,8)},row)
        local txt=mk("TextLabel",{Size=UDim2.new(1,-16,1,0),Position=UDim2.new(0,14,0,0),BackgroundTransparency=1,
            TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.Gotham,TextSize=15,TextColor3=Color3.fromRGB(230,230,235)},row)
        local function rf() local on=config:get(key)
            row.BackgroundColor3=on and Color3.fromRGB(0,120,80) or Color3.fromRGB(40,40,48)
            txt.Text=label.."   ["..(on and "ON" or "OFF").."]" end
        row.MouseButton1Click:Connect(function() config:set(key,not config:get(key)); rf(); config:save() end)
        rf(); refreshers[key]=rf end
    local function addSlider(label,key,min,max)
        local h=mk("Frame",{Size=UDim2.new(1,0,0,56),BackgroundColor3=Color3.fromRGB(34,34,42),BorderSizePixel=0},scroll)
        mk("UICorner",{CornerRadius=UDim.new(0,8)},h)
        local lbl=mk("TextLabel",{Size=UDim2.new(1,-16,0,22),Position=UDim2.new(0,14,0,6),BackgroundTransparency=1,
            TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.Gotham,TextSize=14,TextColor3=Color3.fromRGB(200,200,210)},h)
        local bar=mk("Frame",{Size=UDim2.new(1,-28,0,14),Position=UDim2.new(0,14,0,32),
            BackgroundColor3=Color3.fromRGB(20,20,26),BorderSizePixel=0},h)
        mk("UICorner",{CornerRadius=UDim.new(0,7)},bar)
        local fill=mk("Frame",{Size=UDim2.new(0,0,1,0),BackgroundColor3=Color3.fromRGB(0,190,130),BorderSizePixel=0},bar)
        mk("UICorner",{CornerRadius=UDim.new(0,7)},fill)
        local function rf() local v=config:get(key); lbl.Text=label..":  "..tostring(v)
            fill.Size=UDim2.new(clamp((v-min)/(max-min),0,1),0,1,0) end
        local drag=false
        local function setX(px) local rel=clamp((px-bar.AbsolutePosition.X)/bar.AbsoluteSize.X,0,1)
            config:set(key,math.floor(min+rel*(max-min)+0.5)); rf() end
        bar.InputBegan:Connect(function(i) if isPtr(i) then drag=true; setX(i.Position.X) end end)
        conn(UIS.InputChanged,function(i) if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then setX(i.Position.X) end end)
        conn(UIS.InputEnded,function(i) if drag and isPtr(i) then drag=false; config:save() end end)
        rf(); refreshers[key]=rf end

    addLabel("PARRY")
    addToggle("Auto Parry  (F)","autoParryEnabled")
    addToggle("Manual Spam  (G)","manualSpamEnabled")
    addSlider("Parry Range","parryRange",10,120)
    addSlider("Delay (ms)","delayMs",0,400)
    addSlider("Spam Freq (ms)","spamFrequency",20,300)
    addLabel("LEGIT  (J)")
    addToggle("Legit Mode","legitMode")
    addToggle("Fast React","fastReactMode")
    addSlider("React Base (ms)","legitReactionBase",100,900)
    addSlider("Miss Chance %","missChance",0,30)
    addSlider("Double Tap %","doubleTapChance",0,50)
    addLabel("ESP  (H)")
    addToggle("Ball ESP","ballESP")
    addToggle("Ball Highlight","ballHighlight")
    addToggle("Show Distance","showDistance")
    addToggle("Show Speed","showSpeed")
    addToggle("Player ESP","playerESP")
    addLabel("MISC")
    addToggle("Notifications","notifications")
    addToggle("Anti-Cheat Bypass","antiCheatBypass")
    addToggle("Hide Globals","hideGlobals")
    addSlider("UI Scale","uiScale",0.7,1.6)

    local nHolder=mk("Frame",{Size=UDim2.new(0,260,0,200),Position=UDim2.new(1,-270,0,120),BackgroundTransparency=1},gui)
    mk("UIListLayout",{Padding=UDim.new(0,6)},nHolder)
    local function notify(t) if not config:get("notifications") then return end
        local n=mk("TextLabel",{Size=UDim2.new(1,0,0,30),BackgroundColor3=Color3.fromRGB(24,24,30),
            Text="  "..t,TextColor3=Color3.fromRGB(0,230,160),Font=Enum.Font.Gotham,TextSize=14,
            TextXAlignment=Enum.TextXAlignment.Left,BorderSizePixel=0,BackgroundTransparency=0.1},nHolder)
        mk("UICorner",{CornerRadius=UDim.new(0,6)},n)
        task.delay(2.5,function() Tween:Create(n,TweenInfo.new(0.3),{BackgroundTransparency=1,TextTransparency=1}):Play()
            task.wait(0.3); n:Destroy() end) end

    local kbMap={keybindMenu="__menu__",keybindAutoParry="autoParryEnabled",
        keybindManualSpam="manualSpamEnabled",keybindESP="__esp__",keybindLegitMode="legitMode"}
    conn(UIS.InputBegan,function(input,gpe) if gpe then return end
        for ck,target in pairs(kbMap) do local name=config:get(ck)
            if name and Enum.KeyCode[name] and input.KeyCode==Enum.KeyCode[name] then
                if target=="__menu__" then main.Visible=not main.Visible
                elseif target=="__esp__" then
                    local on=not config:get("ballESP")
                    for _,k in ipairs({"ballESP","ballHighlight","showDistance","showSpeed"}) do config:set(k,on) end
                    for _,k in ipairs({"ballESP","ballHighlight","showDistance","showSpeed"}) do if refreshers[k] then refreshers[k]() end end
                    notify("ESP: "..(on and "ON" or "OFF"))
                else config:set(target,not config:get(target))
                    if refreshers[target] then refreshers[target]() end
                    notify(target..(config:get(target) and " ON" or " OFF")) end
            end end end)

    -- ═══════ LOOP ═══════
    local bt=BT.new(); local lastThreat=false
    conn(RunService.RenderStepped,function(dt)
        State.fps=0.9*State.fps+0.1*(1/math.max(dt,1e-4))
        local ch=LP.Character; State.localHRP=ch and ch:FindFirstChild("HumanoidRootPart")
        bt:update(); ESP:update()
        if config:get("autoParryEnabled") and State.threatActive and not lastThreat then parry:doParry() end
        lastThreat=State.threatActive
        if config:get("manualSpamEnabled") then local now=tick()
            if now-State.lastSpamTime>=config:get("spamFrequency")/1000 then State.lastSpamTime=now; parry:burst() end end
    end)
    pcall(function() State.ping=LP:GetNetworkPing()*1000 end)

    notify("Blade Ball Suite v5.4 carregado")
    print("[BB Suite] v5.4 ok | bypass:",config:get("antiCheatBypass") and "on" or "off")
end

MAIN()
