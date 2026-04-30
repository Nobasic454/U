-- Communicate Spy v2
-- FireServer hook через hookmetamethod (не ломает инпуты)
-- checkcaller() = не трогаем собственные вызовы эксплойта

local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService  = game:GetService("RunService")

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
        return "{\n"..string.rep("  ", depth+1)..table.concat(parts, ",\n"..string.rep("  ", depth+1)).."\n"..string.rep("  ", depth).."}"
    elseif t == "EnumItem" then
        return "Enum."..tostring(v.EnumType).."."..v.Name
    elseif t == "Instance" then
        return v.ClassName..'("'..v.Name..'")'
    elseif t == "string" then
        return '"'..v..'"'
    elseif t == "Vector3" then
        return string.format("Vector3(%.2f,%.2f,%.2f)", v.X, v.Y, v.Z)
    elseif t == "CFrame" then
        return string.format("CFrame(%.2f,%.2f,%.2f)", v.X, v.Y, v.Z)
    else
        return tostring(v)
    end
end

local function formatArgs(args)
    local parts = {}
    for i, v in ipairs(args) do parts[i] = serialize(v) end
    return table.concat(parts, ", ")
end

local function ts()
    return string.format("[%06.2f]", tick() % 1000)
end

------------------------------------------------
-- Лог
------------------------------------------------
local logs = {}

local function pushLog(tag, remoteName, argsStr, source, goal)
    table.insert(logs, 1, {
        tag = tag, remote = remoteName,
        args = argsStr, source = source,
        goal = goal, time = ts()
    })
    if #logs > 300 then table.remove(logs) end
    local g = goal and ("  Goal="..goal) or ""
    print(string.format("%s [%s] %s | %s%s\n  %s", ts(), tag, remoteName, source, g, argsStr))
end

------------------------------------------------
-- FireServer hook (ПРАВИЛЬНЫЙ способ)
-- hookmetamethod + checkcaller() чтобы не трогать свои вызовы
------------------------------------------------
local OldNamecall
OldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()

    -- checkcaller() = это наш эксплойт-код → не логируем, не мешаем
    if not checkcaller() then
        if method == "FireServer" and typeof(self) == "Instance" and self:IsA("RemoteEvent") then
            local args = {...}
            local ok, result = pcall(function()
                local goal = (type(args[1]) == "table" and args[1].Goal) and tostring(args[1].Goal) or nil
                pushLog("OUT ▲", self.Name, formatArgs(args), LocalPlayer.Name, goal)
            end)
        end

        if method == "InvokeServer" and typeof(self) == "Instance" and self:IsA("RemoteFunction") then
            local args = {...}
            pcall(function()
                pushLog("OUT ▲ RF", self.Name, formatArgs(args), LocalPlayer.Name, nil)
            end)
        end
    end

    return OldNamecall(self, ...)
end)

------------------------------------------------
-- OnClientEvent — только то что ТЕБЕ шлёт сервер
-- (чужие клиенты недоступны с нашей стороны)
------------------------------------------------
local hooked = {}

local function hookRemote(remote, label)
    if hooked[remote] then return end
    hooked[remote] = true

    remote.OnClientEvent:Connect(function(...)
        local args = {...}
        pcall(function()
            local goal = (type(args[1]) == "table" and args[1].Goal) and tostring(args[1].Goal) or nil
            pushLog("IN  ▼", remote.Name, formatArgs(args), "Server → "..label, goal)
        end)
    end)
end

-- Communicate своего персонажа
local function onChar(char)
    local rem = char:WaitForChild("Communicate", 10)
    if rem then hookRemote(rem, LocalPlayer.Name.." (self)") end
end
if LocalPlayer.Character then onChar(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(onChar)

-- Все RemoteEvent в игре (опционально — можно закомментировать если слишком много шума)
local function scanRemotes(parent)
    for _, v in ipairs(parent:GetDescendants()) do
        if v:IsA("RemoteEvent") then
            hookRemote(v, v:GetFullName())
        end
    end
    parent.DescendantAdded:Connect(function(v)
        if v:IsA("RemoteEvent") then
            task.wait(0.1)
            hookRemote(v, v:GetFullName())
        end
    end)
end
scanRemotes(game:GetService("ReplicatedStorage"))
scanRemotes(workspace)

------------------------------------------------
-- GUI
------------------------------------------------
local CoreGui   = game:GetService("CoreGui")
local gethui    = (gethui and gethui()) or CoreGui

local SG = Instance.new("ScreenGui")
SG.Name = "CommSpyV2"
SG.ResetOnSpawn = false
SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SG.Parent = gethui

-- Main frame
local F = Instance.new("Frame")
F.Size = UDim2.new(0, 540, 0, 360)
F.Position = UDim2.new(0, 10, 0.5, -180)
F.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
F.BorderSizePixel = 0
F.Parent = SG
Instance.new("UICorner", F).CornerRadius = UDim.new(0, 6)

-- Drag
do
    local dragging, dragStart, startPos
    F.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; dragStart = i.Position; startPos = F.Position
        end
    end)
    F.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    game:GetService("UserInputService").InputChanged:Connect(function(i)
        if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = i.Position - dragStart
            F.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

-- Header
local H = Instance.new("Frame")
H.Size = UDim2.new(1, 0, 0, 28)
H.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
H.BorderSizePixel = 0
H.Parent = F

local Ttl = Instance.new("TextLabel")
Ttl.Size = UDim2.new(1, -110, 1, 0)
Ttl.Position = UDim2.new(0, 10, 0, 0)
Ttl.BackgroundTransparency = 1
Ttl.Text = "◈ Communicate Spy v2"
Ttl.TextColor3 = Color3.fromRGB(170, 190, 255)
Ttl.TextSize = 13
Ttl.Font = Enum.Font.Code
Ttl.TextXAlignment = Enum.TextXAlignment.Left
Ttl.Parent = H

local function makeBtn(text, x, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 48, 0, 20)
    b.Position = UDim2.new(1, x, 0, 4)
    b.BackgroundColor3 = color or Color3.fromRGB(35, 35, 50)
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.fromRGB(200, 200, 220)
    b.TextSize = 11
    b.Font = Enum.Font.Code
    b.Parent = H
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 3)
    return b
end

local BtnClear  = makeBtn("Clear",  -106)
local BtnClose  = makeBtn("Close",  -54, Color3.fromRGB(60, 25, 25))

BtnClear.MouseButton1Click:Connect(function() logs = {} end)
BtnClose.MouseButton1Click:Connect(function() SG:Destroy() end)

-- Filter bar
local FilterBar = Instance.new("Frame")
FilterBar.Size = UDim2.new(1, 0, 0, 24)
FilterBar.Position = UDim2.new(0, 0, 0, 28)
FilterBar.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
FilterBar.BorderSizePixel = 0
FilterBar.Parent = F

local FilterInput = Instance.new("TextBox")
FilterInput.Size = UDim2.new(1, -10, 1, -6)
FilterInput.Position = UDim2.new(0, 5, 0, 3)
FilterInput.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
FilterInput.BorderSizePixel = 0
FilterInput.PlaceholderText = "Filter by Goal / remote name..."
FilterInput.PlaceholderColor3 = Color3.fromRGB(80, 80, 100)
FilterInput.Text = ""
FilterInput.TextColor3 = Color3.fromRGB(200, 210, 240)
FilterInput.TextSize = 11
FilterInput.Font = Enum.Font.Code
FilterInput.TextXAlignment = Enum.TextXAlignment.Left
FilterInput.ClearTextOnFocus = false
FilterInput.Parent = FilterBar
Instance.new("UICorner", FilterInput).CornerRadius = UDim.new(0, 3)
local FPad = Instance.new("UIPadding", FilterInput)
FPad.PaddingLeft = UDim.new(0, 4)

-- Scroll
local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, 0, 1, -52)
Scroll.Position = UDim2.new(0, 0, 0, 52)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 4
Scroll.ScrollBarImageColor3 = Color3.fromRGB(70, 70, 110)
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.Parent = F

local Layout = Instance.new("UIListLayout")
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Padding = UDim.new(0, 1)
Layout.Parent = Scroll

-- Render loop
local lastCount = -1
local lastFilter = ""

RunService.Heartbeat:Connect(function()
    local filter = FilterInput.Text:lower()
    if #logs == lastCount and filter == lastFilter then return end
    lastCount = #logs
    lastFilter = filter

    -- Clear rows
    for _, c in ipairs(Scroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end

    local order = 0
    for _, e in ipairs(logs) do
        -- filter
        if filter ~= "" then
            local haystack = (e.remote.."|"..(e.goal or "").."|"..e.source):lower()
            if not haystack:find(filter, 1, true) then continue end
        end

        local isOut = e.tag:find("OUT")
        local row   = Instance.new("Frame")
        row.LayoutOrder = order; order += 1
        row.Size = UDim2.new(1, 0, 0, 0)
        row.AutomaticSize = Enum.AutomaticSize.Y
        row.BackgroundColor3 = isOut and Color3.fromRGB(16, 26, 16) or Color3.fromRGB(16, 16, 30)
        row.BorderSizePixel = 0
        row.Parent = Scroll

        -- left color bar
        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(0, 3, 1, 0)
        bar.BackgroundColor3 = isOut and Color3.fromRGB(80, 200, 100) or Color3.fromRGB(80, 120, 255)
        bar.BorderSizePixel = 0
        bar.Parent = row

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -12, 0, 0)
        lbl.Position = UDim2.new(0, 8, 0, 3)
        lbl.AutomaticSize = Enum.AutomaticSize.Y
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = isOut and Color3.fromRGB(140, 255, 155) or Color3.fromRGB(130, 170, 255)
        lbl.TextSize = 11
        lbl.Font = Enum.Font.Code
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextWrapped = true
        lbl.RichText = false

        -- header line
        local goal = e.goal and ("  Goal: "..e.goal) or ""
        lbl.Text = string.format("%s [%s] %s  |  %s%s\n  %s",
            e.time, e.tag, e.remote, e.source, goal, e.args)
        lbl.Parent = row

        local pad = Instance.new("UIPadding", row)
        pad.PaddingBottom = UDim.new(0, 4)
    end
end)

print("[CommSpy v2] Loaded. hookmetamethod active.")
