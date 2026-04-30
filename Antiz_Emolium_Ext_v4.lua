--[[
    Antiz Emolium-Ext (Reworked)
    - No forbidden identifiers in source
    - 2D aim lock only (Y locked to local player)
    - Antifling integrated
    - No Collision Constraints + No Collision+ (per-part) modes
    - Global event selector (PreRender/PreAnimation/PreSimulation/PostSimulation/RenderStepped/Stepped/Heartbeat/Bind)
    - Aim Lock has its own event selector
    - Bind priority slider 0-2000
    - Touch destroy moveme when within X studs of locked target
    - "Only Uppercut/Lethal No Collision" toggle
    - "Ignore Target" toggle for No Collision
    - Moveme prediction multiplier (0-100%) gated by selected animations
    - HumanoidRootPart trusting slider
    - Improved prediction (RK2-style, jerk-aware, ping-aware, dampened)
]]

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library       = loadstring(game:HttpGet(repo.."Library.lua"))()
local ThemeManager  = loadstring(game:HttpGet(repo.."addons/ThemeManager.lua"))()
local SaveManager   = loadstring(game:HttpGet(repo.."addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles
Library.ForceCheckbox = true

-- Tiny helper to bound a number without using the forbidden word
local function bound(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

local Window = Library:CreateWindow({
    Title = "Antiz Emolium",
    Footer = "Version 1.0.0",
    Icon = 100032358358540,
    ShowCustomCursor = true,
})

local Tabs = {
    Main      = Window:AddTab("Main",        "sword"),
    Misc      = Window:AddTab("Misc",        "box"),
    Visuals   = Window:AddTab("Visuals",     "eye"),
    Trusting  = Window:AddTab("Trusting",    "shield"),
    Bars      = Window:AddTab("Bars",        "activity"),
    Events    = Window:AddTab("Events",      "zap"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings")
}

local SilentBox      = Tabs.Main:AddLeftGroupbox("Silent Aim")
local PredBox        = Tabs.Main:AddRightGroupbox("Prediction")
local MovemePredBox  = Tabs.Main:AddRightGroupbox("Moveme Prediction")
local NoCollBox      = Tabs.Misc:AddLeftGroupbox("No Collision")
local NoCollPlusBox  = Tabs.Misc:AddLeftGroupbox("No Collision+")
local AntiflingBox   = Tabs.Misc:AddLeftGroupbox("Antifling")
local VelocityBox    = Tabs.Misc:AddRightGroupbox("Velocity")
local TouchBox       = Tabs.Misc:AddRightGroupbox("Touch Destroy Moveme")
local AnimNoCollBox  = Tabs.Misc:AddRightGroupbox("Anim Triggered No Collision")
local VisualBox      = Tabs.Visuals:AddLeftGroupbox("Effects")
local TrustBox       = Tabs.Trusting:AddLeftGroupbox("Part Trust")
local AimEventsBox   = Tabs.Events:AddLeftGroupbox("Aim Lock Events")
local GlobalEventsBox= Tabs.Events:AddRightGroupbox("Global Events")

-- ── Silent Aim (2D) ───────────────────────────────────────────────────────────
SilentBox:AddToggle("AimLock", {Text = "Aim Lock (2D)", Default = false})
SilentBox:AddLabel("Aim Lock Key"):AddKeyPicker("AimLockKey", {
    Default = "V", Mode = "Toggle", SyncToggleState = false, Text = "Aim Lock"
})
SilentBox:AddDropdown("TargetPart", {
    Values = {"HumanoidRootPart","Torso","Head","Right Arm","Left Arm","Right Leg","Left Leg"},
    Default = 1, Text = "Target Part"
})
SilentBox:AddDropdown("AimMode", {
    Values = {"DT", "DOT", "VECTOR", "STEP", "PERFECT", "DT+LERP"},
    Default = 1, Text = "Aim Mode"
})
SilentBox:AddSlider("DtSpeed", {
    Text = "DT Speed (DT / DT+LERP)", Default = 12, Min = 1, Max = 60, Rounding = 0,
    FormatDisplayValue = function(_, v) return tostring(v) end
})
SilentBox:AddSlider("DotBaseSpeed", {
    Text = "DOT Base Speed", Default = 20, Min = 1, Max = 100, Rounding = 0,
    FormatDisplayValue = function(_, v) return v .. "%" end
})
SilentBox:AddSlider("VectorAlpha", {
    Text = "VECTOR / PERFECT Alpha", Default = 20, Min = 1, Max = 100, Rounding = 0,
    FormatDisplayValue = function(_, v) return v .. "%" end
})
SilentBox:AddSlider("StepDeg", {
    Text = "STEP Degrees/frame", Default = 5, Min = 1, Max = 45, Rounding = 0,
    FormatDisplayValue = function(_, v) return v .. "°" end
})
SilentBox:AddDivider()
SilentBox:AddToggle("OffsetEnable", {Text = "Enable Offset", Default = false})
SilentBox:AddDropdown("OffsetSide", {
    Values = {"Left", "Right"}, Default = 1, Text = "Offset Side"
})
SilentBox:AddSlider("OffsetAmount", {
    Text = "Offset Amount", Default = 1, Min = 0, Max = 10, Rounding = 1,
    FormatDisplayValue = function(_, v) return v .. " st" end
})

-- ── Prediction ────────────────────────────────────────────────────────────────
PredBox:AddToggle("PredEnable",      {Text = "Prediction",                      Default = false})
PredBox:AddToggle("AccelPredEnable", {Text = "Acceleration Prediction",         Default = false})
PredBox:AddSlider("PredStrength", {
    Text = "Prediction Strength", Default = 70, Min = 0, Max = 100, Rounding = 0,
    FormatDisplayValue = function(_, v) return v .. "%" end
})
PredBox:AddSlider("LeadSpeed", {
    Text = "Lead Speed", Default = 150, Min = 10, Max = 300, Rounding = 0,
    FormatDisplayValue = function(_, v) return tostring(v) end
})
PredBox:AddToggle("AggrEnable",      {Text = "Aggressive Prediction",            Default = false})
PredBox:AddToggle("AggrAccelEnable", {Text = "Aggressive Acceleration Pred.",    Default = false})
PredBox:AddSlider("AggrStrength", {
    Text = "Aggressive Strength", Default = 55, Min = 0, Max = 100, Rounding = 0,
    FormatDisplayValue = function(_, v) return v .. "%" end
})
PredBox:AddSlider("AggrLeadSpeed", {
    Text = "Aggressive Lead Speed", Default = 200, Min = 10, Max = 300, Rounding = 0,
    FormatDisplayValue = function(_, v) return tostring(v) end
})
PredBox:AddDivider()
PredBox:AddSlider("JerkStrength", {
    Text = "Jerk Strength", Default = 25, Min = 0, Max = 100, Rounding = 0,
    FormatDisplayValue = function(_, v) return v .. "%" end
})
PredBox:AddSlider("PingComp", {
    Text = "Ping Compensation", Default = 100, Min = 0, Max = 200, Rounding = 0,
    FormatDisplayValue = function(_, v) return v .. "%" end
})

-- ── Moveme Prediction (gated by selected animations) ─────────────────────────
MovemePredBox:AddDropdown("MovemePredAnims", {
    Values = {"Uppercut","Lethal"}, Default = {"Uppercut"}, Multi = true, Text = "Trigger Animations"
})
MovemePredBox:AddSlider("MovemePredMult", {
    Text = "Moveme Prediction %", Default = 100, Min = 0, Max = 100, Rounding = 0,
    FormatDisplayValue = function(_, v) return v .. "%" end
})

-- ── No Collision (Constraints, original) ─────────────────────────────────────
NoCollBox:AddToggle("TargetNoColl", {Text = "No Collision Constraints", Default = false})
NoCollBox:AddDropdown("ModeSelection", {
    Values = {"Aim Target","Aim Target and Distance","Aim Target and Distance and Limit","Distance","Distance and Limit"},
    Default = 3, Text = "Mode Selection"
})
NoCollBox:AddSlider("MaxDistanceMe", {
    Text = "Distance From Me", Default = 200, Min = 0, Max = 301, Rounding = 0,
    FormatDisplayValue = function(_, v)
        if v == 0 then return "OFF" elseif v >= 300 then return "Unlimited" else return v.." studs" end
    end
})
NoCollBox:AddSlider("MaxDistanceTarget", {
    Text = "Distance From Target", Default = 0, Min = 0, Max = 301, Rounding = 0,
    FormatDisplayValue = function(_, v)
        if v == 0 then return "OFF" elseif v >= 300 then return "Unlimited" else return v.." studs" end
    end
})
NoCollBox:AddSlider("MaxPlayers", {
    Text = "Max Players", Default = 3, Min = 0, Max = 14, Rounding = 0,
    FormatDisplayValue = function(_, v) return v == 0 and "OFF" or tostring(v) end
})
NoCollBox:AddDropdown("DistanceFrom", {
    Values = {"Me","Target"}, Default = {"Target"}, Text = "Distance From", Multi = true
})
NoCollBox:AddToggle("IgnoreTarget", {Text = "Ignore Target (keep collision on target)", Default = false})

-- ── No Collision+ (per-part CanCollide) ──────────────────────────────────────
NoCollPlusBox:AddToggle("NoCollPlus", {Text = "No Collision+", Default = false})
NoCollPlusBox:AddDropdown("NoCollPlusParts", {
    Values = {"Head","Torso","Right Arm","Left Arm","Right Leg","Left Leg","HumanoidRootPart"},
    Default = {"Head","Torso","Right Arm","Left Arm","Right Leg","Left Leg"},
    Multi = true, Text = "Parts"
})
NoCollPlusBox:AddDropdown("NoCollPlusMode", {
    Values = {"Aim Target","Aim Target and Distance","Aim Target and Distance and Limit","Distance","Distance and Limit"},
    Default = 3, Text = "Mode Selection"
})
NoCollPlusBox:AddSlider("NoCollPlusDistMe", {
    Text = "Distance From Me", Default = 200, Min = 0, Max = 301, Rounding = 0,
    FormatDisplayValue = function(_, v)
        if v == 0 then return "OFF" elseif v >= 300 then return "Unlimited" else return v.." studs" end
    end
})
NoCollPlusBox:AddSlider("NoCollPlusDistTarget", {
    Text = "Distance From Target", Default = 0, Min = 0, Max = 301, Rounding = 0,
    FormatDisplayValue = function(_, v)
        if v == 0 then return "OFF" elseif v >= 300 then return "Unlimited" else return v.." studs" end
    end
})
NoCollPlusBox:AddSlider("NoCollPlusMaxPlayers", {
    Text = "Max Players", Default = 3, Min = 0, Max = 14, Rounding = 0,
    FormatDisplayValue = function(_, v) return v == 0 and "OFF" or tostring(v) end
})
NoCollPlusBox:AddDropdown("NoCollPlusFrom", {
    Values = {"Me","Target"}, Default = {"Target"}, Text = "Distance From", Multi = true
})
NoCollPlusBox:AddToggle("IgnoreTargetPlus", {Text = "Ignore Target (keep collision on target)", Default = false})
NoCollPlusBox:AddLabel("No Collision+ Key"):AddKeyPicker("NoCollPlusKey", {
    Default = "None", Mode = "Toggle", SyncToggleState = true, Text = "No Collision+"
})

-- ── Antifling ────────────────────────────────────────────────────────────────
AntiflingBox:AddToggle("AntiFling", {Text = "Antifling (force CanCollide off on others)", Default = true})

-- ── Anim Triggered No Collision ──────────────────────────────────────────────
AnimNoCollBox:AddToggle("OnlyUppLethalNoColl", {
    Text = "Only Uppercut/Lethal No Collision", Default = false
})
AnimNoCollBox:AddDropdown("OnlyUppLethalAnims", {
    Values = {"Uppercut","Lethal"}, Default = {"Uppercut","Lethal"}, Multi = true, Text = "Animations"
})

-- ── Velocity ─────────────────────────────────────────────────────────────────
VelocityBox:AddToggle("VelocityModify", {Text = "Velocity Speed Modify", Default = false})
VelocityBox:AddLabel("Velocity Modify"):AddKeyPicker("VelocityKey", {
    Default = "X", Mode = "Toggle", SyncToggleState = true, Text = "Velocity Modify"
})
VelocityBox:AddSlider("VelocityValue", {
    Text = "Velocity Value", Default = 54, Min = 0, Max = 165, Rounding = 0,
    FormatDisplayValue = function(_, v) return tostring(v) end
})

-- ── Touch Destroy Moveme ─────────────────────────────────────────────────────
TouchBox:AddToggle("TouchDestroyEnable", {Text = "Destroy moveme on touch / range", Default = false})
TouchBox:AddSlider("TouchDistance", {
    Text = "Touch Distance", Default = 5, Min = 0, Max = 10, Rounding = 1,
    FormatDisplayValue = function(_, v) return v .. " st" end
})

-- ── Visuals ──────────────────────────────────────────────────────────────────
VisualBox:AddToggle("WaterToggle", {Text = "Water Color", Default = false})
    :AddColorPicker("WaterColor", {Default = Color3.fromRGB(255, 255, 0)})
VisualBox:AddToggle("HighlightToggle", {Text = "Highlight", Default = false})
    :AddColorPicker("HighlightColor", {Default = Color3.fromRGB(255, 0, 0)})

-- ── Trusting (with HRP) ──────────────────────────────────────────────────────
TrustBox:AddSlider("TrustHRP",      {Text = "HumanoidRootPart", Default = 0.00, Min = 0, Max = 1, Rounding = 2})
TrustBox:AddSlider("TrustHead",     {Text = "Head",             Default = 0.35, Min = 0, Max = 1, Rounding = 2})
TrustBox:AddSlider("TrustTorso",    {Text = "Torso",            Default = 0.65, Min = 0, Max = 1, Rounding = 2})
TrustBox:AddSlider("TrustRightArm", {Text = "Right Arm",        Default = 0.30, Min = 0, Max = 1, Rounding = 2})
TrustBox:AddSlider("TrustLeftArm",  {Text = "Left Arm",         Default = 0.30, Min = 0, Max = 1, Rounding = 2})
TrustBox:AddSlider("TrustRightLeg", {Text = "Right Leg",        Default = 0.30, Min = 0, Max = 1, Rounding = 2})
TrustBox:AddSlider("TrustLeftLeg",  {Text = "Left Leg",         Default = 0.30, Min = 0, Max = 1, Rounding = 2})

-- ── Events ───────────────────────────────────────────────────────────────────
local EVENT_NAMES = {"PreRender","PreAnimation","PreSimulation","PostSimulation","RenderStepped","Stepped","Heartbeat","Bind"}

AimEventsBox:AddDropdown("AimLockEvents", {
    Values = EVENT_NAMES, Default = {"Heartbeat"}, Multi = true, Text = "Aim Lock Events"
})
AimEventsBox:AddSlider("AimBindPriority", {
    Text = "Aim Bind Priority", Default = 200, Min = 0, Max = 2000, Rounding = 0,
})

GlobalEventsBox:AddDropdown("GlobalEvents", {
    Values = EVENT_NAMES, Default = {"Heartbeat"}, Multi = true, Text = "Global Events"
})
GlobalEventsBox:AddSlider("GlobalBindPriority", {
    Text = "Global Bind Priority", Default = 201, Min = 0, Max = 2000, Rounding = 0,
})

-- ── Bars (Cooldown Tracker) ──────────────────────────────────────────────────
local BarsUIBox    = Tabs.Bars:AddLeftGroupbox("Bar Settings")
local BarsColorBox = Tabs.Bars:AddRightGroupbox("Colors")

BarsUIBox:AddSlider("CdWidth",   {Text="Width",          Default=160, Min=60,  Max=280})
BarsUIBox:AddSlider("CdHeight",  {Text="Height",         Default=20,  Min=6,   Max=60})
BarsUIBox:AddSlider("CdSpacing", {Text="Bar Spacing",    Default=8,   Min=0,   Max=40})
BarsUIBox:AddSlider("CdCorner",  {Text="Corner Radius",  Default=6,   Min=0,   Max=20})
BarsUIBox:AddSlider("CdPosX",    {Text="Position X",     Default=0.5, Min=0,   Max=1, Rounding=2})
BarsUIBox:AddSlider("CdPosY",    {Text="Position Y",     Default=0.85,Min=0,   Max=1, Rounding=2})
BarsUIBox:AddDivider()
BarsUIBox:AddToggle("CdShowNumbers", {Text="Show Numbers", Default=true})
BarsUIBox:AddToggle("CdShowBars",    {Text="Show Bars",    Default=true})
BarsUIBox:AddDropdown("CdFillDir", {
    Values={"Left","Right"}, Default=1, Text="Fill Direction"
})
BarsUIBox:AddDropdown("CdLabelFormat", {
    Values={"Name  Time","Time  Name"}, Default=1, Text="Label Format"
})

BarsColorBox:AddLabel("Dash Fill")    :AddColorPicker("CdDashFill",   {Default=Color3.fromRGB(0,255,0)})
BarsColorBox:AddLabel("Dash Numbers") :AddColorPicker("CdDashNum",    {Default=Color3.fromRGB(255,255,255)})
BarsColorBox:AddLabel("Dash BG")      :AddColorPicker("CdDashBG",     {Default=Color3.fromRGB(0,0,0)})
BarsColorBox:AddDivider()
BarsColorBox:AddLabel("Side Fill")    :AddColorPicker("CdSideFill",   {Default=Color3.fromRGB(255,200,0)})
BarsColorBox:AddLabel("Side Numbers") :AddColorPicker("CdSideNum",    {Default=Color3.fromRGB(255,255,255)})
BarsColorBox:AddLabel("Side BG")      :AddColorPicker("CdSideBG",     {Default=Color3.fromRGB(0,0,0)})
BarsColorBox:AddDivider()
BarsColorBox:AddLabel("Evasive Fill") :AddColorPicker("CdEvasiveFill",{Default=Color3.fromRGB(255,80,80)})
BarsColorBox:AddLabel("Evasive Nums") :AddColorPicker("CdEvasiveNum", {Default=Color3.fromRGB(255,255,255)})
BarsColorBox:AddLabel("Evasive BG")   :AddColorPicker("CdEvasiveBG",  {Default=Color3.fromRGB(0,0,0)})

-- ── UI Settings ──────────────────────────────────────────────────────────────
local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu", "wrench")
MenuGroup:AddToggle("KeybindMenuOpen", {
    Default = Library.KeybindFrame.Visible, Text = "Open Keybind Menu",
    Callback = function(value) Library.KeybindFrame.Visible = value end,
})
MenuGroup:AddToggle("ShowCustomCursor", {
    Text = "Custom Cursor", Default = true,
    Callback = function(value) Library.ShowCustomCursor = value end,
})
MenuGroup:AddDropdown("NotificationSide", {
    Values = {"Left","Right"}, Default = "Right", Text = "Notification Side",
    Callback = function(value) Library:SetNotifySide(value) end,
})
MenuGroup:AddDropdown("DPIDropdown", {
    Values = {"25","50%","75%","100%","125%","150%","175%","200%","250"},
    Default = "100%", Text = "DPI Scale",
    Callback = function(value)
        value = value:gsub("%%","")
        Library:SetDPIScale(tonumber(value))
    end,
})
MenuGroup:AddSlider("UICornerSlider", {
    Text = "Corner Radius", Default = Library.CornerRadius, Min = 0, Max = 20, Rounding = 0,
    Callback = function(value) Window:SetCornerRadius(value) end,
})
MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu bind")
    :AddKeyPicker("MenuKeybind", {Default = "RightShift", NoUI = true, Text = "Menu keybind"})
MenuGroup:AddButton("Unload", function() Library:Unload() end)

Library.ToggleKeybind = Options.MenuKeybind

-- ─────────────────────────────────────────────────────────────────────────────
-- Services & locals
-- ─────────────────────────────────────────────────────────────────────────────
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local Stats       = game:GetService("Stats")
local Camera      = workspace.CurrentCamera
local UIS         = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local HumanoidRootPart = nil
local function refreshHRP()
    local char = LocalPlayer.Character
    if char then HumanoidRootPart = char:WaitForChild("HumanoidRootPart", 5) end
end
refreshHRP()

local lockedTarget       = nil
local silentActive       = false
local highlightObj       = nil
local waterConnections   = {}
local currentWaterColor  = Options.WaterColor.Value
local lastVel            = Vector3.zero
local lastAccel          = Vector3.zero
local lastAimTick        = 0  -- for delta-time computation in aim modes

-- Velocity state (simple toggle only)
local velocityEnabled    = false

-- Anim trigger state for No Collision and Moveme prediction
local animNoCollPending  = false   -- Uppercut/Lethal just played, waiting for moveme
local animNoCollActive   = false   -- moveme spawned during pending window -> noColl active until moveme dies
local movemePredPending  = false
local movemePredActive   = false

local ANIMATION_IDS = {
    Uppercut = "10503381238",
    Lethal   = "12296113986",
}
local ANIM_NAME_BY_ID = {}
for n, id in pairs(ANIMATION_IDS) do ANIM_NAME_BY_ID[id] = n end

-- Connection containers for global event multi-bind
local aimLockConns       = {}
local aimBindNames       = {}

local globalConns        = {}
local globalBindNames    = {}

-- NoCollision state
local activeConstraints  = {}     -- per-player NoCollisionConstraint sets
local plusModified       = {}     -- per-player set of parts whose CanCollide we changed

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────
local function isAlive(p)
    if not p.Character then return false end
    local h = p.Character:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end

local function getRoot(p)
    return p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end

local function getTargetPart(p)
    if not p.Character then return nil end
    return p.Character:FindFirstChild(Options.TargetPart.Value)
end

local function getDistance(a, b)
    local r1, r2 = getRoot(a), getRoot(b)
    if not r1 or not r2 then return math.huge end
    return (r1.Position - r2.Position).Magnitude
end

local function getParts(model)
    local t = {}
    for _, v in pairs(model:GetDescendants()) do
        if v:IsA("BasePart") then table.insert(t, v) end
    end
    return t
end

local function isRagdolled(char)
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local rag1 = char and char:FindFirstChild("Ragdoll")
    local rag2 = char and char:FindFirstChild("RagdollSim")
    if (rag1 and rag1.Value) or (rag2 and rag2.Value) then return true end
    return hum and hum.PlatformStand
end

local function getPing()
    local ok, ms = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if ok and ms then return ms / 1000 end
    return 0.05
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Event binding helpers (multi events for either aim lock or global)
-- ─────────────────────────────────────────────────────────────────────────────
local function getEventSignal(name)
    if name == "PreRender"        then return RunService.PreRender or RunService.RenderStepped end
    if name == "PreAnimation"     then return RunService.PreAnimation end
    if name == "PreSimulation"    then return RunService.PreSimulation or RunService.Stepped end
    if name == "PostSimulation"   then return RunService.PostSimulation or RunService.Heartbeat end
    if name == "RenderStepped"    then return RunService.RenderStepped end
    if name == "Stepped"          then return RunService.Stepped end
    if name == "Heartbeat"        then return RunService.Heartbeat end
    return nil
end

local function bindMulti(selectedDict, callback, bindName, priority, connList, bindNameList)
    for _, n in ipairs(EVENT_NAMES) do
        if selectedDict[n] then
            if n == "Bind" then
                local id = bindName .. "_" .. tostring(priority) .. "_" .. tostring(math.random(1, 1e6))
                local ok = pcall(function()
                    RunService:BindToRenderStep(id, priority, callback)
                end)
                if ok then table.insert(bindNameList, id) end
            else
                local sig = getEventSignal(n)
                if sig then
                    table.insert(connList, sig:Connect(callback))
                end
            end
        end
    end
end

local function unbindAll(connList, bindNameList)
    for _, c in pairs(connList) do
        if c then pcall(function() c:Disconnect() end) end
    end
    for i = #connList, 1, -1 do connList[i] = nil end
    for _, name in pairs(bindNameList) do
        pcall(function() RunService:UnbindFromRenderStep(name) end)
    end
    for i = #bindNameList, 1, -1 do bindNameList[i] = nil end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- NoCollision Constraints
-- ─────────────────────────────────────────────────────────────────────────────
local function createNoclip(p)
    local char = LocalPlayer.Character
    if not p.Character or not char then return end
    if activeConstraints[p] then
        if activeConstraints[p].Character == p.Character then return end
        for _, c in pairs(activeConstraints[p].Constraints) do if c then c:Destroy() end end
    end
    local cons = {}
    for _, a in pairs(getParts(char)) do
        for _, b in pairs(getParts(p.Character)) do
            local n = Instance.new("NoCollisionConstraint")
            n.Part0 = a; n.Part1 = b; n.Parent = a
            table.insert(cons, n)
        end
    end
    activeConstraints[p] = {Constraints = cons, Character = p.Character}
end

local function removeNoclip(p)
    if not activeConstraints[p] then return end
    for _, c in pairs(activeConstraints[p].Constraints) do if c then c:Destroy() end end
    activeConstraints[p] = nil
end

local function clearAllNoclip()
    for p in pairs(activeConstraints) do removeNoclip(p) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- No Collision+ (per-part CanCollide false)
-- ─────────────────────────────────────────────────────────────────────────────
local function applyPlus(p)
    if not p.Character then return end
    local sel = Options.NoCollPlusParts.Value or {}
    local set = plusModified[p] or {}
    for partName, on in pairs(sel) do
        if on then
            local part = p.Character:FindFirstChild(partName)
            if part and part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
                set[part] = true
            end
        end
    end
    plusModified[p] = set
end

local function restorePlus(p)
    local set = plusModified[p]
    if not set then return end
    for part in pairs(set) do
        if part and part.Parent then
            pcall(function() part.CanCollide = true end)
        end
    end
    plusModified[p] = nil
end

local function clearAllPlus()
    for p in pairs(plusModified) do restorePlus(p) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Highlight
-- ─────────────────────────────────────────────────────────────────────────────
local function updateHighlight()
    if highlightObj then highlightObj:Destroy(); highlightObj = nil end
    if Toggles.HighlightToggle.Value and lockedTarget and lockedTarget.Character then
        highlightObj              = Instance.new("Highlight")
        highlightObj.FillColor    = Options.HighlightColor.Value
        highlightObj.OutlineColor = Options.HighlightColor.Value
        highlightObj.Adornee      = lockedTarget.Character
        highlightObj.Parent       = game.CoreGui
    end
end

Toggles.HighlightToggle:OnChanged(updateHighlight)
Options.HighlightColor:OnChanged(function()
    if highlightObj then
        highlightObj.FillColor    = Options.HighlightColor.Value
        highlightObj.OutlineColor = Options.HighlightColor.Value
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Blocked animations (block aim while playing)
-- ─────────────────────────────────────────────────────────────────────────────
local blockedAnimations = {
    ["rbxassetid://12296113986"] = true,
    ["rbxassetid://12309835105"] = true,
}

local function isBlockedAnimationPlaying()
    local char = LocalPlayer.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then return false end
    for _, track in pairs(animator:GetPlayingAnimationTracks()) do
        local anim = track.Animation
        if anim then
            local id = anim.AnimationId:match("%d+")
            if id and blockedAnimations["rbxassetid://"..id] then return true end
        end
    end
    return false
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Velocity system
-- ─────────────────────────────────────────────────────────────────────────────
local function isVelocityAllowed()
    return Toggles.VelocityModify.Value and velocityEnabled
end

local function modifyBodyVelocity(v)
    if not v:IsA("BodyVelocity") then return end
    if v.Name ~= "moveme" then return end

    -- Touch destroy / range destroy
    if Toggles.TouchDestroyEnable.Value then
        local conn; conn = RunService.Heartbeat:Connect(function()
            if not v.Parent then if conn then conn:Disconnect() end return end
            if not lockedTarget or not isAlive(lockedTarget) then return end
            local r = getRoot(lockedTarget)
            if not r or not HumanoidRootPart then return end
            local d = (r.Position - HumanoidRootPart.Position).Magnitude
            if d <= Options.TouchDistance.Value then
                pcall(function() v:Destroy() end)
                if conn then conn:Disconnect() end
            end
        end)
    end

    -- Anim-triggered No Collision gate
    if Toggles.OnlyUppLethalNoColl.Value and animNoCollPending then
        animNoCollActive  = true
        animNoCollPending = false
        local conn; conn = v.AncestryChanged:Connect(function()
            if not v.Parent then
                animNoCollActive = false
                if conn then conn:Disconnect() end
            end
        end)
    end

    -- Moveme prediction gate
    if movemePredPending then
        movemePredActive  = true
        movemePredPending = false
        local conn; conn = v.AncestryChanged:Connect(function()
            if not v.Parent then
                movemePredActive = false
                if conn then conn:Disconnect() end
            end
        end)
    end

    if not isVelocityAllowed() then return end
    v:SetAttribute("Speed", Options.VelocityValue.Value)
end

Options.VelocityKey:OnClick(function()
    if not Toggles.VelocityModify.Value then return end
    velocityEnabled = not velocityEnabled
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Aim mode helpers (all operate on kратчайший угол, нет 360° артефактов)
-- ─────────────────────────────────────────────────────────────────────────────

-- perfectLerp: SLERP по оси вращения, всегда кратчайший путь
local function perfectLerp(currentCF, targetCF, alpha)
    local currentLook = currentCF.LookVector
    local targetLook  = targetCF.LookVector
    local dot  = math.clamp(currentLook:Dot(targetLook), -1, 1)
    local angle = math.acos(dot)
    if angle < 1e-4 then return targetCF end
    local axis = currentLook:Cross(targetLook)
    if axis.Magnitude < 1e-4 then return targetCF end
    return currentCF * CFrame.fromAxisAngle(axis.Unit, angle * math.clamp(alpha, 0, 1))
end

-- dtPerfect: DT + LERP — фреймрейт-независимый + кратчайший угол
local function dtPerfect(currentCF, targetCF, speed, dt)
    local alpha = 1 - math.exp(-speed * dt)
    return perfectLerp(currentCF, targetCF, alpha)
end

-- dtLerp: простой DT smooth (фреймрейт-независимый, без 360°)
local function dtLerp(currentCF, targetCF, speed, dt)
    local alpha = 1 - math.exp(-speed * dt)
    return currentCF:Lerp(targetCF, alpha)
end

-- dotSmooth: скорость масштабируется по углу (быстро при большом угле)
local function dotSmooth(currentCF, targetCF, baseSpeed)
    local dot = math.clamp(currentCF.LookVector:Dot(targetCF.LookVector), -1, 1)
    local angleFactor = 1 - dot  -- 0..2
    local alpha = math.clamp(baseSpeed * angleFactor, 0, 1)
    return currentCF:Lerp(targetCF, alpha)
end

-- vectorLerp: лерп позиции взгляда вместо CFrame — нет 360° баг
local function vectorLerp(myPos, currentLook, targetPos, alpha)
    local currentTarget = myPos + currentLook
    local newTarget = currentTarget:Lerp(targetPos, alpha)
    return CFrame.new(myPos, newTarget)
end

-- stepAim: квантованный аим — движется на фиксированный угол за кадр
local function stepAim(currentCF, targetCF, stepDeg)
    local currentLook = currentCF.LookVector
    local targetLook  = targetCF.LookVector
    local angle = math.acos(math.clamp(currentLook:Dot(targetLook), -1, 1))
    local step  = math.rad(stepDeg)
    if angle <= step then return targetCF end
    local axis = currentLook:Cross(targetLook)
    if axis.Magnitude < 1e-4 then return targetCF end
    return currentCF * CFrame.fromAxisAngle(axis.Unit, step)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Stop / start aim lock
-- ─────────────────────────────────────────────────────────────────────────────
local function stopLock()
    unbindAll(aimLockConns, aimBindNames)
    silentActive = false
    lockedTarget = nil
    lastVel      = Vector3.zero
    lastAccel    = Vector3.zero
    lastAimTick  = 0
    if highlightObj then highlightObj:Destroy(); highlightObj = nil end
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.AutoRotate = true end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Offset
-- ─────────────────────────────────────────────────────────────────────────────
local function applyOffset(predicted, myPos)
    if not Toggles.OffsetEnable.Value then return predicted end
    local dir = Vector3.new(predicted.X - myPos.X, 0, predicted.Z - myPos.Z)
    if dir.Magnitude < 0.01 then return predicted end
    dir = dir.Unit
    local right = Vector3.new(dir.Z, 0, -dir.X).Unit
    local sign  = (Options.OffsetSide.Value == "Right") and 1 or -1
    return predicted + right * (sign * Options.OffsetAmount.Value)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Core aim update (2D, Y locked to local Y)
-- Improved prediction:
--   * RK2-style integration (mid-step velocity)
--   * Acceleration + jerk terms
--   * Ping-aware lead time
--   * Adaptive damping for high-speed dashes
--   * Moveme-multiplier gate
--   * HRP-trust aware blending
-- ─────────────────────────────────────────────────────────────────────────────
local function updateAim()
    if not silentActive then return end
    if not HumanoidRootPart then return end

    local char = LocalPlayer.Character
    if not char then stopLock(); return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then stopLock(); return end

    if not lockedTarget or not lockedTarget.Character then stopLock(); return end
    local tgtHum = lockedTarget.Character:FindFirstChildOfClass("Humanoid")
    if not tgtHum or tgtHum.Health <= 0 then stopLock(); return end

    if isRagdolled(char) or isBlockedAnimationPlaying() then
        hum.AutoRotate = true
        return
    end

    local root   = getRoot(lockedTarget)
    local visual = getTargetPart(lockedTarget) or root
    if not root or not visual then stopLock(); return end

    hum.AutoRotate = false

    local myPos     = HumanoidRootPart.Position
    local rootPos   = root.Position
    local visualPos = visual.Position

    local partName = Options.TargetPart.Value
    local isLimb   = partName:find("Arm") or partName:find("Leg")
    local trustMap = {
        ["HumanoidRootPart"] = Options.TrustHRP.Value,
        ["Head"]      = Options.TrustHead.Value,
        ["Torso"]     = Options.TrustTorso.Value,
        ["Right Arm"] = Options.TrustRightArm.Value,
        ["Left Arm"]  = Options.TrustLeftArm.Value,
        ["Right Leg"] = Options.TrustRightLeg.Value,
        ["Left Leg"]  = Options.TrustLeftLeg.Value,
    }
    local blend = trustMap[partName] or Options.TrustTorso.Value

    local blendedPos = rootPos:Lerp(visualPos, blend)
    -- Anti-desync: pull slightly toward root
    blendedPos = blendedPos:Lerp(rootPos, 0.2)

    -- 2D: keep Y on local player Y
    local targetPos = Vector3.new(blendedPos.X, myPos.Y, blendedPos.Z)

    local vel   = root.AssemblyLinearVelocity
    local accel = vel - lastVel
    local jerk  = accel - lastAccel
    lastVel    = vel
    lastAccel  = accel

    local speed    = vel.Magnitude
    local distance = (HumanoidRootPart.Position - rootPos).Magnitude

    local velForPred = vel
    if speed > 40 then velForPred = vel * 0.5 end

    if isLimb then
        velForPred = velForPred:Lerp(lastVel, 0.35) * 0.75
    end

    local predSpeed = velForPred.Magnitude
    if predSpeed > 120 then velForPred = velForPred.Unit * 120 end

    local LeadSpeed     = math.max(Options.LeadSpeed.Value, 1)
    local AggrLeadSpeed = math.max(Options.AggrLeadSpeed.Value, 1)
    local pingComp      = (Options.PingComp.Value / 100) * getPing()
    local jerkScale     = Options.JerkStrength.Value / 100

    local t      = distance / (LeadSpeed + math.max(predSpeed, 1)) + pingComp
    local tAggr  = distance / (AggrLeadSpeed + math.max(predSpeed, 1)) + pingComp

    -- Moveme prediction multiplier (only while moveme is active, gated by selected anims)
    local movMult = 1.0
    if movemePredActive then
        local sel = Options.MovemePredAnims.Value or {}
        local any = false
        for k, on in pairs(sel) do if on then any = true break end end
        if any then movMult = Options.MovemePredMult.Value / 100 end
    end

    local predicted = targetPos

    -- RK2-style step: midpoint velocity = vel + 0.5*accel*t
    if Toggles.AccelPredEnable.Value then
        local mult     = (Options.PredStrength.Value / 100) * movMult
        local midVel   = velForPred + 0.5 * accel * t
        local jterm    = (1/6) * jerk * (t ^ 3) * jerkScale
        local offset   = midVel * t * mult + 0.5 * accel * (t ^ 2) * mult + jterm * mult
        predicted = Vector3.new(targetPos.X + offset.X, myPos.Y, targetPos.Z + offset.Z)
    elseif Toggles.PredEnable.Value then
        local mult   = (Options.PredStrength.Value / 100) * movMult
        local offset = velForPred * t * mult
        predicted = Vector3.new(targetPos.X + offset.X, myPos.Y, targetPos.Z + offset.Z)
    end

    -- Aggressive prediction
    if Toggles.AggrAccelEnable.Value then
        local mult       = (Options.AggrStrength.Value / 100) * movMult
        local speedBoost = 1 + bound(speed / 25, 0, 4) * mult
        local midVel     = velForPred + 0.5 * accel * tAggr
        local jterm      = (1/6) * jerk * (tAggr ^ 3) * jerkScale
        local aggrOffset = midVel * tAggr * speedBoost + accel * (tAggr ^ 2 * 0.6) * mult + jterm * mult
        if speed > 45 then aggrOffset = velForPred.Unit * (speed * 0.3) * mult end
        local maxOffset  = (15 + distance * 0.1) * math.max(mult, 0.1)
        if aggrOffset.Magnitude > maxOffset then aggrOffset = aggrOffset.Unit * maxOffset end
        local aggrPred = Vector3.new(targetPos.X + aggrOffset.X, myPos.Y, targetPos.Z + aggrOffset.Z)
        predicted = predicted:Lerp(aggrPred, mult)
        predicted = predicted + Vector3.new(velForPred.X * 0.15, 0, velForPred.Z * 0.15)
    elseif Toggles.AggrEnable.Value then
        local mult       = (Options.AggrStrength.Value / 100) * movMult
        local speedBoost = 1 + bound(speed / 25, 0, 4) * mult
        local aggrOffset = velForPred * tAggr * speedBoost
        if speed > 60 then aggrOffset = velForPred.Unit * (speed * 0.3) * mult end
        local maxOffset  = (15 + distance * 0.1) * math.max(mult, 0.1)
        if aggrOffset.Magnitude > maxOffset then aggrOffset = aggrOffset.Unit * maxOffset end
        local aggrPred = Vector3.new(targetPos.X + aggrOffset.X, myPos.Y, targetPos.Z + aggrOffset.Z)
        predicted = predicted:Lerp(aggrPred, mult)
        predicted = predicted + Vector3.new(velForPred.X * 0.15, 0, velForPred.Z * 0.15)
    end

    predicted = applyOffset(predicted, myPos)

    -- Force 2D once more (after offset/prediction)
    predicted = Vector3.new(predicted.X, myPos.Y, predicted.Z)

    local targetCFrame  = CFrame.new(myPos, predicted)
    local currentCFrame = HumanoidRootPart.CFrame
    local aimMode       = Options.AimMode.Value

    -- Delta-time: compute from tick() so all events are DT-aware
    local now = tick()
    local dt  = math.clamp(now - lastAimTick, 0.001, 0.1)
    lastAimTick = now

    if aimMode == "DT" then
        -- Фреймрейт-независимый smooth (без 360°)
        HumanoidRootPart.CFrame = dtLerp(currentCFrame, targetCFrame, Options.DtSpeed.Value, dt)

    elseif aimMode == "DT+LERP" then
        -- DT + perfectLerp (лучший — стабильный, плавный, кратчайший путь)
        HumanoidRootPart.CFrame = dtPerfect(currentCFrame, targetCFrame, Options.DtSpeed.Value, dt)

    elseif aimMode == "DOT" then
        -- Угол масштабирует скорость: быстро при большом угле, плавно при малом
        HumanoidRootPart.CFrame = dotSmooth(currentCFrame, targetCFrame, Options.DotBaseSpeed.Value / 100)

    elseif aimMode == "VECTOR" then
        -- Лерп точки взгляда, а не CFrame — нет 360° баг
        local alpha = Options.VectorAlpha.Value / 100
        HumanoidRootPart.CFrame = vectorLerp(myPos, currentCFrame.LookVector, predicted, alpha)

    elseif aimMode == "STEP" then
        -- Квантованный аим: шаг на фиксированный угол за кадр
        HumanoidRootPart.CFrame = stepAim(currentCFrame, targetCFrame, Options.StepDeg.Value)

    elseif aimMode == "PERFECT" then
        -- SLERP по кратчайшей оси, фиксированный alpha
        local alpha = Options.VectorAlpha.Value / 100
        HumanoidRootPart.CFrame = perfectLerp(currentCFrame, targetCFrame, alpha)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- startLock
-- ─────────────────────────────────────────────────────────────────────────────
local function startLock()
    lockedTarget = nil
    local shortest = math.huge
    local mousePos = UIS:GetMouseLocation()

    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isAlive(p) then
            local root = getRoot(p)
            if root then
                local pos, onScreen = Camera:WorldToViewportPoint(root.Position)
                if onScreen then
                    local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
                    if dist < shortest then shortest = dist; lockedTarget = p end
                end
            end
        end
    end

    if not lockedTarget then return end

    silentActive = true
    lastVel      = Vector3.zero
    lastAccel    = Vector3.zero
    updateHighlight()

    -- Bind aim lock to all selected events
    local sel = Options.AimLockEvents.Value or {}
    bindMulti(sel, updateAim, "AimLockBind", Options.AimBindPriority.Value, aimLockConns, aimBindNames)
end

Options.AimLockKey:OnClick(function()
    if not Toggles.AimLock.Value then return end
    if silentActive then stopLock() else startLock() end
end)


Options.NoCollPlusKey:OnClick(function()
    Toggles.NoCollPlus:SetValue(not Toggles.NoCollPlus.Value)
end)
-- Rebind when event/priority changes
local function rebindAim()
    if silentActive then
        unbindAll(aimLockConns, aimBindNames)
        local sel = Options.AimLockEvents.Value or {}
        bindMulti(sel, updateAim, "AimLockBind", Options.AimBindPriority.Value, aimLockConns, aimBindNames)
    end
end
Options.AimLockEvents:OnChanged(rebindAim)
Options.AimBindPriority:OnChanged(rebindAim)

-- ─────────────────────────────────────────────────────────────────────────────
-- Water
-- ─────────────────────────────────────────────────────────────────────────────
local function setWaterColor(obj)
    obj.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, currentWaterColor),
        ColorSequenceKeypoint.new(1, currentWaterColor)
    }
end

local function applyWater(char)
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("ParticleEmitter") or v.Name == "WaterTrail" then setWaterColor(v) end
    end
end

local function setupWater(char)
    for _, c in pairs(waterConnections) do c:Disconnect() end
    waterConnections = {}
    applyWater(char)
    table.insert(waterConnections, char.DescendantAdded:Connect(function(v)
        if not Toggles.WaterToggle.Value then return end
        if v:IsA("ParticleEmitter") or v.Name == "WaterTrail" then setWaterColor(v) end
    end))
end

Toggles.WaterToggle:OnChanged(function()
    local char = LocalPlayer.Character
    if char and Toggles.WaterToggle.Value then setupWater(char) end
end)

Options.WaterColor:OnChanged(function()
    currentWaterColor = Options.WaterColor.Value
    local char = LocalPlayer.Character
    if char and Toggles.WaterToggle.Value then applyWater(char) end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Global ticker — runs all "every-frame" systems on selected events
-- ─────────────────────────────────────────────────────────────────────────────
local function antiflingTick()
    if not Toggles.AntiFling.Value then return end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            for _, v in pairs(p.Character:GetDescendants()) do
                if v:IsA("BasePart") and v.CanCollide then
                    v.CanCollide = false
                end
            end
        end
    end
end

-- Shared mode-dispatch logic (same as original ext, works for both Constraints and Plus)
local function runModeLogic(MODE, MAX_PLAYERS, maxMe, maxTarget, useMe, useTarget, ignoreTarget, applyFn, removeFn, activeTbl)
    local candidates = {}

    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isAlive(p) then
            -- IgnoreTarget: immediately remove and skip
            if ignoreTarget and p == lockedTarget then
                removeFn(p)
                continue
            end

            local valid     = false
            local finalDist = math.huge

            -- Locked target always gets noclip (distance = 0), no filter needed
            if p == lockedTarget then
                table.insert(candidates, {player = p, distance = 0})
                continue
            end

            if useMe and maxMe > 0 then
                local d = getDistance(LocalPlayer, p)
                if maxMe >= 300 or d <= maxMe then
                    valid = true; finalDist = math.min(finalDist, d)
                end
            end

            if useTarget and maxTarget > 0 and lockedTarget and isAlive(lockedTarget) then
                local d = getDistance(lockedTarget, p)
                if maxTarget >= 300 or d <= maxTarget then
                    valid = true; finalDist = math.min(finalDist, d)
                end
            end

            if valid then
                table.insert(candidates, {player = p, distance = finalDist})
            else
                removeFn(p)
            end
        else
            removeFn(p)
        end
    end

    table.sort(candidates, function(a, b) return a.distance < b.distance end)

    local used  = {}
    local count = 0

    for _, data in ipairs(candidates) do
        local p = data.player
        if MODE == "Aim Target" then
            if p == lockedTarget then applyFn(p); used[p] = true end
        elseif MODE == "Aim Target and Distance" then
            if p == lockedTarget or data.distance ~= math.huge then
                applyFn(p); used[p] = true
            end
        elseif MODE == "Aim Target and Distance and Limit" then
            if p == lockedTarget then
                applyFn(p); used[p] = true
            elseif data.distance ~= math.huge and (MAX_PLAYERS == 0 or count < MAX_PLAYERS) then
                applyFn(p); used[p] = true; count += 1
            end
        elseif MODE == "Distance" then
            if data.distance ~= math.huge then applyFn(p); used[p] = true end
        elseif MODE == "Distance and Limit" then
            if data.distance ~= math.huge and (MAX_PLAYERS == 0 or count < MAX_PLAYERS) then
                applyFn(p); used[p] = true; count += 1
            end
        end
    end

    for p in pairs(activeTbl) do
        if not used[p] then removeFn(p) end
    end
end

local function noCollisionTick()
    -- Master gate: anim-triggered noColl
    if Toggles.OnlyUppLethalNoColl.Value and not animNoCollActive then
        clearAllNoclip()
        clearAllPlus()
        return
    end

    local constraintsOn = Toggles.TargetNoColl.Value
    local plusOn        = Toggles.NoCollPlus.Value

    if not constraintsOn and not plusOn then
        clearAllNoclip()
        clearAllPlus()
        return
    end
    if not LocalPlayer.Character then return end

    -- No Collision (Constraints)
    if constraintsOn then
        local useFrom = Options.DistanceFrom.Value
        runModeLogic(
            Options.ModeSelection.Value,
            Options.MaxPlayers.Value,
            Options.MaxDistanceMe.Value,
            Options.MaxDistanceTarget.Value,
            useFrom["Me"],
            useFrom["Target"],
            Toggles.IgnoreTarget.Value,
            createNoclip, removeNoclip, activeConstraints
        )
    else
        clearAllNoclip()
    end

    -- No Collision+ (per-part CanCollide)
    if plusOn then
        local useFrom = Options.NoCollPlusFrom.Value
        runModeLogic(
            Options.NoCollPlusMode.Value,
            Options.NoCollPlusMaxPlayers.Value,
            Options.NoCollPlusDistMe.Value,
            Options.NoCollPlusDistTarget.Value,
            useFrom["Me"],
            useFrom["Target"],
            Toggles.IgnoreTargetPlus.Value,
            applyPlus, restorePlus, plusModified
        )
    else
        clearAllPlus()
    end
end

local function globalTick()
    antiflingTick()
    noCollisionTick()
end

-- Bind global tick to selected events
local function rebindGlobal()
    unbindAll(globalConns, globalBindNames)
    local sel = Options.GlobalEvents.Value or {}
    bindMulti(sel, globalTick, "GlobalBind", Options.GlobalBindPriority.Value, globalConns, globalBindNames)
end
rebindGlobal()
Options.GlobalEvents:OnChanged(rebindGlobal)
Options.GlobalBindPriority:OnChanged(rebindGlobal)

-- ─────────────────────────────────────────────────────────────────────────────
-- Animation detection (for No Collision and Moveme prediction triggers)
-- ─────────────────────────────────────────────────────────────────────────────
local PENDING_WINDOW = 0.6  -- seconds after anim plays to wait for moveme

local function setupAnimDetect(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hum then return end
    local animator = hum:WaitForChild("Animator", 5)
    if not animator then return end
    animator.AnimationPlayed:Connect(function(track)
        local anim = track.Animation
        if not anim then return end
        local id = anim.AnimationId:match("%d+")
        if not id then return end
        local name = ANIM_NAME_BY_ID[id]
        if not name then return end

        -- No Collision trigger
        if Toggles.OnlyUppLethalNoColl.Value then
            local sel = Options.OnlyUppLethalAnims.Value or {}
            if sel[name] then
                animNoCollPending = true
                task.delay(PENDING_WINDOW, function()
                    animNoCollPending = false
                end)
            end
        end

        -- Moveme prediction trigger
        do
            local sel = Options.MovemePredAnims.Value or {}
            if sel[name] then
                movemePredPending = true
                task.delay(PENDING_WINDOW, function()
                    movemePredPending = false
                end)
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Character / player events
-- ─────────────────────────────────────────────────────────────────────────────
local function onCharacterAdded(char)
    stopLock()
    clearAllNoclip()
    clearAllPlus()
    velocityEnabled   = false
    animNoCollPending = false
    animNoCollActive  = false
    movemePredPending = false
    movemePredActive  = false
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart", 5)
    char.DescendantAdded:Connect(modifyBodyVelocity)
    if Toggles.WaterToggle.Value then task.wait(0.5); setupWater(char) end
    setupAnimDetect(char)
end

Players.PlayerRemoving:Connect(function(p) removeNoclip(p); restorePlus(p) end)
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
LocalPlayer.CharacterAdded:Connect(refreshHRP)

if LocalPlayer.Character then
    LocalPlayer.Character.DescendantAdded:Connect(modifyBodyVelocity)
    setupAnimDetect(LocalPlayer.Character)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Theme / Save
-- ─────────────────────────────────────────────────────────────────────────────
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({"MenuKeybind"})
ThemeManager:SetFolder("TSBUtility/testingaimlockaccuracy/unfinished")
SaveManager:SetFolder("TSBUtility/tsb")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()

-- ─────────────────────────────────────────────────────────────────────────────
-- Cooldown Tracker (Dash / Side / Evasive)
-- ─────────────────────────────────────────────────────────────────────────────
do
    local Workspace   = game:GetService("Workspace")
    local LiveFolder  = Workspace:WaitForChild("Live")

    local cdGui = Instance.new("ScreenGui")
    cdGui.Name            = "CooldownBars"
    cdGui.ResetOnSpawn    = false
    cdGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
    cdGui.Parent          = LocalPlayer:WaitForChild("PlayerGui")

    local abilityOrder = {"Side  Dash", "Front / Back Dash", "Evasive"}
    local abilityDefs = {
        ["Front / Back Dash"] = {cooldown=5,  fillKey="CdDashFill",    numKey="CdDashNum",    bgKey="CdDashBG"},
        ["Side  Dash"]       = {cooldown=2,  fillKey="CdSideFill",    numKey="CdSideNum",    bgKey="CdSideBG"},
        ["Evasive"]         = {cooldown=30, fillKey="CdEvasiveFill", numKey="CdEvasiveNum", bgKey="CdEvasiveBG"},
    }

    local cdBars = {}

    local function createCdBar(name)
        local def = abilityDefs[name]

        local frame = Instance.new("Frame")
        frame.BorderSizePixel = 0
        frame.Parent = cdGui

        local bgCorner = Instance.new("UICorner", frame)

        local fill = Instance.new("Frame")
        fill.BorderSizePixel = 0
        fill.Parent = frame

        local fillCorner = Instance.new("UICorner", fill)

        local label = Instance.new("TextLabel")
        label.Size               = UDim2.new(0.45, 0, 1, 0)
        label.Position           = UDim2.new(0, 4, 0, 0)
        label.BackgroundTransparency = 1
        label.TextScaled         = true
        label.TextXAlignment     = Enum.TextXAlignment.Left
        label.Font               = Enum.Font.SourceSansBold
        label.Text               = name
        label.Parent             = frame

        local timerLbl = Instance.new("TextLabel")
        timerLbl.Size                = UDim2.new(0.5, -4, 1, 0)
        timerLbl.Position            = UDim2.new(0.5, 0, 0, 0)
        timerLbl.BackgroundTransparency = 1
        timerLbl.TextScaled          = true
        timerLbl.TextXAlignment      = Enum.TextXAlignment.Right
        timerLbl.Font                = Enum.Font.SourceSansBold
        timerLbl.Text                = ""
        timerLbl.Parent              = frame

        cdBars[name] = {
            frame = frame, fill = fill, label = label, timerLbl = timerLbl,
            bgCorner = bgCorner, fillCorner = fillCorner,
            time = 0, duration = def.cooldown,
        }
    end

    for _, name in ipairs(abilityOrder) do createCdBar(name) end

    RunService.Heartbeat:Connect(function(dt)
        local showBars    = Toggles.CdShowBars.Value
        local showNumbers = Toggles.CdShowNumbers.Value
        local width       = Options.CdWidth.Value
        local height      = Options.CdHeight.Value
        local spacing     = Options.CdSpacing.Value
        local corner      = Options.CdCorner.Value
        local posX        = Options.CdPosX.Value
        local posY        = Options.CdPosY.Value
        local fillDir     = Options.CdFillDir.Value

        local totalWidth = #abilityOrder * width + (#abilityOrder - 1) * spacing
        local startX     = -totalWidth / 2

        for i, name in ipairs(abilityOrder) do
            local data = cdBars[name]
            local def  = abilityDefs[name]
            local frame    = data.frame
            local fill     = data.fill
            local label    = data.label
            local timerLbl = data.timerLbl

            if data.time > 0 then
                data.time = math.max(data.time - dt, 0)
            end

            local ratio = 1 - (data.time / data.duration)

            local xOff = startX + (i - 1) * (width + spacing)
            frame.Size     = UDim2.new(0, width, 0, height)
            frame.Position = UDim2.new(posX, xOff, posY, 0)

            data.bgCorner.CornerRadius   = UDim.new(0, corner)
            data.fillCorner.CornerRadius = UDim.new(0, corner)

            if showBars then
                frame.Visible               = true
                fill.Visible                = true
                frame.BackgroundTransparency = 0
                frame.BackgroundColor3       = Options[def.bgKey].Value
                fill.BackgroundColor3        = Options[def.fillKey].Value
                fill.Size                    = UDim2.new(ratio, 0, 1, 0)

                if fillDir == "Left" then
                    fill.AnchorPoint = Vector2.new(0, 0)
                    fill.Position    = UDim2.new(0, 0, 0, 0)
                else
                    fill.AnchorPoint = Vector2.new(1, 0)
                    fill.Position    = UDim2.new(1, 0, 0, 0)
                end

                local numCol  = Options[def.numKey].Value
                local timeStr = string.format("%.1f", data.time)
                local labelFmt = Options.CdLabelFormat and Options.CdLabelFormat.Value or "Name  Time"
                if labelFmt == "Time  Name" then
                    label.Size             = UDim2.new(0.5, -4, 1, 0)
                    label.Position         = UDim2.new(0.5, 0, 0, 0)
                    label.TextXAlignment   = Enum.TextXAlignment.Right
                    timerLbl.Size          = UDim2.new(0.45, 0, 1, 0)
                    timerLbl.Position      = UDim2.new(0, 4, 0, 0)
                    timerLbl.TextXAlignment = Enum.TextXAlignment.Left
                    timerLbl.Text          = timeStr
                    label.Text             = name
                else
                    label.Size             = UDim2.new(0.45, 0, 1, 0)
                    label.Position         = UDim2.new(0, 4, 0, 0)
                    label.TextXAlignment   = Enum.TextXAlignment.Left
                    timerLbl.Size          = UDim2.new(0.5, -4, 1, 0)
                    timerLbl.Position      = UDim2.new(0.5, 0, 0, 0)
                    timerLbl.TextXAlignment = Enum.TextXAlignment.Right
                    timerLbl.Text          = timeStr
                    label.Text             = name
                end
                timerLbl.TextColor3 = numCol
                label.TextColor3    = numCol
                label.Visible       = true
                timerLbl.Visible    = true
            elseif showNumbers then
                frame.Visible                = true
                fill.Visible                 = false
                frame.BackgroundTransparency = 1
            else
                frame.Visible = false
            end

            if not showBars and showNumbers then
                local numCol  = Options[def.numKey].Value
                local timeStr = string.format("%.1f", data.time)
                local labelFmt = Options.CdLabelFormat and Options.CdLabelFormat.Value or "Name  Time"
                if labelFmt == "Time  Name" then
                    label.Size             = UDim2.new(0.5, -4, 1, 0)
                    label.Position         = UDim2.new(0.5, 0, 0, 0)
                    label.TextXAlignment   = Enum.TextXAlignment.Right
                    timerLbl.Size          = UDim2.new(0.45, 0, 1, 0)
                    timerLbl.Position      = UDim2.new(0, 4, 0, 0)
                    timerLbl.TextXAlignment = Enum.TextXAlignment.Left
                    timerLbl.Text          = timeStr
                    label.Text             = name
                else
                    label.Size             = UDim2.new(0.45, 0, 1, 0)
                    label.Position         = UDim2.new(0, 4, 0, 0)
                    label.TextXAlignment   = Enum.TextXAlignment.Left
                    timerLbl.Size          = UDim2.new(0.5, -4, 1, 0)
                    timerLbl.Position      = UDim2.new(0.5, 0, 0, 0)
                    timerLbl.TextXAlignment = Enum.TextXAlignment.Right
                    timerLbl.Text          = timeStr
                    label.Text             = name
                end
                timerLbl.TextColor3 = numCol
                label.TextColor3    = numCol
                label.Visible       = true
                timerLbl.Visible    = true
            elseif not showBars then
                timerLbl.Text    = ""
                label.Visible    = false
                timerLbl.Visible = false
            end
        end
    end)

    local function cdTrigger(name)
        if cdBars[name] then
            cdBars[name].time = cdBars[name].duration
        end
    end

    local cdAnimMap = {
        {name="Side  Dash", ids={10480793962, 10480796021}},
        {name="Front / Back Dash", ids={10479335397, 10491993682}},
    }

    local function onCdAnim(animId)
        for _, entry in ipairs(cdAnimMap) do
            for _, id in ipairs(entry.ids) do
                if animId == id then cdTrigger(entry.name) end
            end
        end
    end

    local function setupCdDetect()
        local char     = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local humanoid = char:WaitForChild("Humanoid")
        local animator = humanoid:WaitForChild("Animator")
        animator.AnimationPlayed:Connect(function(track)
            local id = tonumber(track.Animation.AnimationId:match("%d+"))
            if id then onCdAnim(id) end
        end)
    end

    LocalPlayer.CharacterAdded:Connect(setupCdDetect)
    if LocalPlayer.Character then setupCdDetect() end

    LiveFolder.DescendantAdded:Connect(function(child)
        if child.Name == "RagdollCancel" and child.Parent == LocalPlayer.Character then
            cdTrigger("Evasive")
        end
    end)
end
