-- Communicate Spy v3
-- hookmetamethod + checkcaller (не ломает инпуты)
-- Stop / Select / Copy / Smart Clear

local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")

------------------------------------------------
-- Serialize
------------------------------------------------
local function serialize(v, depth)
    depth = depth or 0
    if depth > 3 then return "..." end
    local t = typeof(v)
    if t == "table" then
        local parts = {}
        for k, val in pairs(v) do
            local key = type(k) == "string" and k or ("["..tostring(k).."]")
            parts[#parts+1] = key.." = "..serialize(val, depth+1)
        end
        return "{ "..table.concat(parts, ", ").." }"
    elseif t == "EnumItem" then
        return "Enum."..tostring(v.EnumType).."."..v.Name
    elseif t == "Instance" then
        return v.ClassName..'("'..v.Name..'")'
    elseif t == "string" then return '"'..v..'"'
    elseif t == "Vector3" then
        return string.format("V3(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
    elseif t == "CFrame" then
        return string.format("CF(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
    else return tostring(v)
    end
end

local function fmtArgs(args)
    local p = {}
    for i, v in ipairs(args) do p[i] = serialize(v) end
    return table.concat(p, ",  ")
end

local function ts()
    return string.format("[%06.2f]", tick() % 1000)
end

------------------------------------------------
-- State
------------------------------------------------
local logs      = {}
local paused    = false   -- Stop button
local selected  = nil     -- selected log entry index
local dirty     = true

local function pushLog(tag, remoteName, argsStr, source, goal)
    if paused then return end
    table.insert(logs, 1, {
        tag = tag, remote = remoteName,
        args = argsStr, source = source,
        goal = goal, time = ts(),
        raw  = string.format('%s\n  args: %s', source, argsStr),
    })
    if #logs > 400 then table.remove(logs) end
    -- shift selected index if needed
    if selected then selected = selected + 1 end
    dirty = true
end

------------------------------------------------
-- hookmetamethod — не ломает инпуты
------------------------------------------------
local OldNamecall
OldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if not checkcaller() then
        if method == "FireServer" and typeof(self) == "Instance" and self:IsA("RemoteEvent") then
            local args = {...}
            task.spawn(function()
                local goal = (type(args[1]) == "table" and args[1].Goal) and tostring(args[1].Goal) or nil
                pushLog("OUT ▲", self.Name, fmtArgs(args), LocalPlayer.Name, goal)
            end)
        elseif method == "InvokeServer" and typeof(self) == "Instance" and self:IsA("RemoteFunction") then
            local args = {...}
            task.spawn(function()
                pushLog("OUT ▲ RF", self.Name, fmtArgs(args), LocalPlayer.Name, nil)
            end)
        end
    end
    return OldNamecall(self, ...)
end)

------------------------------------------------
-- OnClientEvent — что сервер шлёт тебе
------------------------------------------------
local hooked = {}
local function hookRemote(remote, label)
    if hooked[remote] then return end
    hooked[remote] = true
    remote.OnClientEvent:Connect(function(...)
        local args = {...}
        task.spawn(function()
            local goal = (type(args[1]) == "table" and args[1].Goal) and tostring(args[1].Goal) or nil
            pushLog("IN  ▼", remote.Name, fmtArgs(args), "Server→"..label, goal)
        end)
    end)
end

local function scanRemotes(parent)
    for _, v in ipairs(parent:GetDescendants()) do
        if v:IsA("RemoteEvent") then hookRemote(v, v:GetFullName()) end
    end
    parent.DescendantAdded:Connect(function(v)
        if v:IsA("RemoteEvent") then task.wait(0.1); hookRemote(v, v:GetFullName()) end
    end)
end

local function onChar(char)
    local rem = char:WaitForChild("Communicate", 10)
    if rem then hookRemote(rem, LocalPlayer.Name.."(self)") end
end
if LocalPlayer.Character then onChar(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(onChar)

scanRemotes(game:GetService("ReplicatedStorage"))
scanRemotes(workspace)

------------------------------------------------
-- GUI
------------------------------------------------
local gethui    = (gethui and gethui()) or game:GetService("CoreGui")

local SG = Instance.new("ScreenGui")
SG.Name            = "CommSpyV3"
SG.ResetOnSpawn    = false
SG.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
SG.Parent          = gethui

-- Root frame
local F = Instance.new("Frame")
F.Size              = UDim2.new(0, 460, 0, 300)
F.Position          = UDim2.new(0, 10, 0.5, -200)
F.BackgroundColor3  = Color3.fromRGB(9, 9, 13)
F.BorderSizePixel   = 0
F.Parent            = SG
Instance.new("UICorner", F).CornerRadius = UDim.new(0, 6)

-- Drag — только через Header чтобы кнопки и scroll не съедали инпут
do
    local drag, ds, sp
    H.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            drag = true; ds = i.Position; sp = F.Position
        end
    end)
    H.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
    end)
    UIS.InputChanged:Connect(function(i)
        if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = i.Position - ds
            F.Position = UDim2.new(sp.X.Scale, sp.X.Offset+d.X, sp.Y.Scale, sp.Y.Offset+d.Y)
        end
    end)
end

-- ── Header ──────────────────────────────────────────────────────────────────
local H = Instance.new("Frame")
H.Size             = UDim2.new(1, 0, 0, 30)
H.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
H.BorderSizePixel  = 0
H.Parent           = F
Instance.new("UICorner", H).CornerRadius = UDim.new(0, 6)

local Ttl = Instance.new("TextLabel")
Ttl.Size               = UDim2.new(1, -10, 1, 0)
Ttl.Position           = UDim2.new(0, 10, 0, 0)
Ttl.BackgroundTransparency = 1
Ttl.Text               = "◈ CommSpy v3"
Ttl.TextColor3         = Color3.fromRGB(160, 185, 255)
Ttl.TextSize           = 13
Ttl.Font               = Enum.Font.Code
Ttl.TextXAlignment     = Enum.TextXAlignment.Left
Ttl.Parent             = H

-- ── Toolbar ─────────────────────────────────────────────────────────────────
local TB = Instance.new("Frame")
TB.Size             = UDim2.new(1, 0, 0, 28)
TB.Position         = UDim2.new(0, 0, 0, 30)
TB.BackgroundColor3 = Color3.fromRGB(13, 13, 20)
TB.BorderSizePixel  = 0
TB.Parent           = F

local function makeBtn(text, xOff, color, textColor)
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0, 60, 0, 20)
    b.Position         = UDim2.new(0, xOff, 0, 4)
    b.BackgroundColor3 = color or Color3.fromRGB(30, 30, 45)
    b.BorderSizePixel  = 0
    b.Text             = text
    b.TextColor3       = textColor or Color3.fromRGB(200, 205, 230)
    b.TextSize         = 11
    b.Font             = Enum.Font.Code
    b.Parent           = TB
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 3)
    return b
end

-- Buttons: Stop | Copy | Clear | Close
local BtnStop  = makeBtn("■ Stop",  6,   Color3.fromRGB(50, 20, 20),  Color3.fromRGB(255, 100, 100))
local BtnCopy  = makeBtn("⎘ Copy",  70,  Color3.fromRGB(20, 35, 50),  Color3.fromRGB(100, 180, 255))
local BtnClear = makeBtn("✕ Clear", 134, Color3.fromRGB(30, 30, 45),  Color3.fromRGB(200, 200, 220))
local BtnClose = makeBtn("Close",   198, Color3.fromRGB(45, 20, 20),  Color3.fromRGB(220, 120, 120))

-- Status label (right side)
local StatusLbl = Instance.new("TextLabel")
StatusLbl.Size              = UDim2.new(0, 200, 1, 0)
StatusLbl.Position          = UDim2.new(1, -205, 0, 0)
StatusLbl.BackgroundTransparency = 1
StatusLbl.Text              = "● recording"
StatusLbl.TextColor3        = Color3.fromRGB(80, 220, 100)
StatusLbl.TextSize          = 11
StatusLbl.Font              = Enum.Font.Code
StatusLbl.TextXAlignment    = Enum.TextXAlignment.Right
StatusLbl.Parent            = TB

-- ── Filter ──────────────────────────────────────────────────────────────────
local FB = Instance.new("Frame")
FB.Size             = UDim2.new(1, 0, 0, 24)
FB.Position         = UDim2.new(0, 0, 0, 58)
FB.BackgroundColor3 = Color3.fromRGB(11, 11, 18)
FB.BorderSizePixel  = 0
FB.Parent           = F

local FI = Instance.new("TextBox")
FI.Size                 = UDim2.new(1, -10, 1, -6)
FI.Position             = UDim2.new(0, 5, 0, 3)
FI.BackgroundColor3     = Color3.fromRGB(20, 20, 30)
FI.BorderSizePixel      = 0
FI.PlaceholderText      = "Filter: remote name / Goal / source..."
FI.PlaceholderColor3    = Color3.fromRGB(70, 70, 95)
FI.Text                 = ""
FI.TextColor3           = Color3.fromRGB(200, 210, 240)
FI.TextSize             = 11
FI.Font                 = Enum.Font.Code
FI.TextXAlignment       = Enum.TextXAlignment.Left
FI.ClearTextOnFocus     = false
FI.Parent               = FB
Instance.new("UICorner", FI).CornerRadius = UDim.new(0, 3)
local FPad = Instance.new("UIPadding", FI); FPad.PaddingLeft = UDim.new(0, 5)

-- ── Scroll ───────────────────────────────────────────────────────────────────
local Scroll = Instance.new("ScrollingFrame")
Scroll.Size                 = UDim2.new(1, 0, 1, -82)
Scroll.Position             = UDim2.new(0, 0, 0, 82)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel      = 0
Scroll.ScrollBarThickness   = 4
Scroll.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 100)
Scroll.AutomaticCanvasSize  = Enum.AutomaticSize.Y
Scroll.CanvasSize           = UDim2.new(0, 0, 0, 0)
Scroll.Parent               = F

local Layout = Instance.new("UIListLayout")
Layout.SortOrder  = Enum.SortOrder.LayoutOrder
Layout.Padding    = UDim.new(0, 1)
Layout.Parent     = Scroll

-- ── Selected info bar ────────────────────────────────────────────────────────
local SelBar = Instance.new("Frame")
SelBar.Size             = UDim2.new(1, 0, 0, 0)  -- hidden by default
SelBar.Position         = UDim2.new(0, 0, 1, -0)
SelBar.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
SelBar.BorderSizePixel  = 0
SelBar.ClipsDescendants = true
SelBar.Parent           = F

local SelLbl = Instance.new("TextLabel")
SelLbl.Size             = UDim2.new(1, -10, 1, 0)
SelLbl.Position         = UDim2.new(0, 6, 0, 0)
SelLbl.BackgroundTransparency = 1
SelLbl.Text             = ""
SelLbl.TextColor3       = Color3.fromRGB(130, 175, 255)
SelLbl.TextSize         = 10
SelLbl.Font             = Enum.Font.Code
SelLbl.TextXAlignment   = Enum.TextXAlignment.Left
SelLbl.TextTruncate     = Enum.TextTruncate.AtEnd
SelLbl.Parent           = SelBar

local function setSelBarVisible(show)
    if show then
        F.Size       = UDim2.new(0, 460, 0, 320)
        Scroll.Size  = UDim2.new(1, 0, 1, -102)
        SelBar.Size  = UDim2.new(1, 0, 0, 20)
        SelBar.Position = UDim2.new(0, 0, 1, -20)
    else
        F.Size       = UDim2.new(0, 460, 0, 300)
        Scroll.Size  = UDim2.new(1, 0, 1, -82)
        SelBar.Size  = UDim2.new(1, 0, 0, 0)
    end
end

------------------------------------------------
-- Button logic
------------------------------------------------
-- Stop / Resume
BtnStop.MouseButton1Click:Connect(function()
    paused = not paused
    if paused then
        BtnStop.Text            = "▶ Resume"
        BtnStop.BackgroundColor3 = Color3.fromRGB(20, 45, 20)
        BtnStop.TextColor3      = Color3.fromRGB(100, 255, 120)
        StatusLbl.Text          = "■ paused"
        StatusLbl.TextColor3    = Color3.fromRGB(220, 100, 100)
    else
        BtnStop.Text            = "■ Stop"
        BtnStop.BackgroundColor3 = Color3.fromRGB(50, 20, 20)
        BtnStop.TextColor3      = Color3.fromRGB(255, 100, 100)
        StatusLbl.Text          = "● recording"
        StatusLbl.TextColor3    = Color3.fromRGB(80, 220, 100)
    end
end)

-- Copy selected entry to clipboard
BtnCopy.MouseButton1Click:Connect(function()
    if not selected or not logs[selected] then
        -- nothing selected — show hint
        StatusLbl.Text       = "select a row first"
        StatusLbl.TextColor3 = Color3.fromRGB(255, 200, 60)
        task.delay(2, function()
            if not paused then
                StatusLbl.Text       = "● recording"
                StatusLbl.TextColor3 = Color3.fromRGB(80, 220, 100)
            end
        end)
        return
    end
    local e   = logs[selected]
    local txt = string.format(
        "-- %s [%s] %s | %s%s\nlocal args = { %s }\n-- remote: %s",
        e.time, e.tag, e.remote, e.source,
        e.goal and ("  Goal="..e.goal) or "",
        e.args,
        e.remote
    )
    setclipboard(txt)
    StatusLbl.Text       = "✓ copied!"
    StatusLbl.TextColor3 = Color3.fromRGB(100, 255, 140)
    task.delay(1.5, function()
        if not paused then
            StatusLbl.Text       = "● recording"
            StatusLbl.TextColor3 = Color3.fromRGB(80, 220, 100)
        end
    end)
end)

-- Clear — if something selected: deselect only. If nothing selected: clear all.
BtnClear.MouseButton1Click:Connect(function()
    if selected then
        selected = nil
        setSelBarVisible(false)
        SelLbl.Text = ""
        dirty = true
    else
        logs    = {}
        selected = nil
        setSelBarVisible(false)
        dirty = true
    end
end)

BtnClose.MouseButton1Click:Connect(function() SG:Destroy() end)

------------------------------------------------
-- Render
------------------------------------------------
local rowCache  = {}
local lastCount = -1
local lastFilt  = ""
local lastSel   = nil

local COLORS = {
    OUT_BG   = Color3.fromRGB(14, 24, 14),
    IN_BG    = Color3.fromRGB(14, 14, 28),
    OUT_BAR  = Color3.fromRGB(70, 200, 90),
    IN_BAR   = Color3.fromRGB(70, 110, 255),
    OUT_TEXT = Color3.fromRGB(130, 255, 150),
    IN_TEXT  = Color3.fromRGB(120, 165, 255),
    SEL_BG   = Color3.fromRGB(35, 45, 70),
    SEL_OUT  = Color3.fromRGB(160, 255, 175),
    SEL_IN   = Color3.fromRGB(155, 195, 255),
}

local function getRow()
    if #rowCache > 0 then return table.remove(rowCache) end
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, 0)
    f.AutomaticSize = Enum.AutomaticSize.Y
    f.BorderSizePixel = 0
    -- side bar
    local bar = Instance.new("Frame")
    bar.Name = "Bar"
    bar.Size = UDim2.new(0, 3, 1, 0)
    bar.BorderSizePixel = 0
    bar.Parent = f
    -- label
    local lbl = Instance.new("TextLabel")
    lbl.Name = "Lbl"
    lbl.Size = UDim2.new(1, -12, 0, 0)
    lbl.Position = UDim2.new(0, 8, 0, 3)
    lbl.AutomaticSize = Enum.AutomaticSize.Y
    lbl.BackgroundTransparency = 1
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Code
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextWrapped = true
    lbl.Parent = f
    local pad = Instance.new("UIPadding", f)
    pad.PaddingBottom = UDim.new(0, 4)
    pad.PaddingTop    = UDim.new(0, 2)
    f._bar = bar; f._lbl = lbl
    return f
end

RunService.Heartbeat:Connect(function()
    local filter = FI.Text:lower()
    if not dirty and #logs == lastCount and filter == lastFilt and selected == lastSel then return end
    dirty = false; lastCount = #logs; lastFilt = filter; lastSel = selected

    -- recycle rows
    for _, c in ipairs(Scroll:GetChildren()) do
        if c:IsA("Frame") then
            c.Parent = nil
            c.Visible = true
            table.insert(rowCache, c)
        end
    end

    local order = 0
    for idx, e in ipairs(logs) do
        if filter ~= "" then
            local hay = (e.remote.."|"..(e.goal or "").."|"..e.source):lower()
            if not hay:find(filter, 1, true) then continue end
        end

        local isOut = e.tag:sub(1,3) == "OUT"
        local isSel = (idx == selected)

        local row = getRow()
        row.LayoutOrder      = order; order += 1
        row.BackgroundColor3 = isSel and COLORS.SEL_BG or (isOut and COLORS.OUT_BG or COLORS.IN_BG)
        row._bar.BackgroundColor3 = isOut and COLORS.OUT_BAR or COLORS.IN_BAR
        row._lbl.TextColor3       = isSel and (isOut and COLORS.SEL_OUT or COLORS.SEL_IN)
                                           or (isOut and COLORS.OUT_TEXT or COLORS.IN_TEXT)

        local goal = e.goal and ("  Goal:"..e.goal) or ""
        row._lbl.Text = string.format("%s [%s] %s  |  %s%s\n    %s",
            e.time, e.tag, e.remote, e.source, goal, e.args)
        row.Parent = Scroll

        -- click to select
        local captureIdx = idx
        row.InputBegan:Connect(function(inp)
            if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            if selected == captureIdx then
                -- деселект
                selected = nil
                setSelBarVisible(false)
                SelLbl.Text = ""
            else
                selected = captureIdx
                local en = logs[captureIdx]
                if en then
                    SelLbl.Text = string.format("[%s] %s | %s | %s",
                        en.tag, en.remote, en.source, en.args)
                    setSelBarVisible(true)
                end
            end
            dirty = true
        end)
    end
end)

print("[CommSpy v3] ready  —  hookmetamethod active, paused="..tostring(paused))
