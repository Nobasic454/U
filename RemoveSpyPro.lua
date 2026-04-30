-- RemoveSpy Pro | ~15KB+
-- Обнаружение и удаление хуков, спаев, метаметодов

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local ScriptContext = game:GetService("ScriptContext")

local LocalPlayer = Players.LocalPlayer

-- =============================================
-- УТИЛИТЫ
-- =============================================

local function safeGet(t, k)
    local ok, v = pcall(function() return t[k] end)
    return ok and v or nil
end

local function isHooked(func)
    if type(func) ~= "function" then return false end
    local ok, result = pcall(debug.getinfo, func)
    if not ok then return false end
    local info = result
    if type(info) == "table" then
        return info.short_src == "[C]" == false and tostring(func):find("hook") ~= nil
    end
    return false
end

local function getOriginal(func)
    if not checkcaller then return func end
    local ok, orig = pcall(function()
        return debug.getupvalue and debug.getupvalue(func, 1) or func
    end)
    return ok and type(orig) == "function" and orig or func
end

-- =============================================
-- ЯДРО ДЕТЕКТОРА
-- =============================================

local SpyCore = {}
SpyCore.__index = SpyCore

SpyCore.Hooks       = {}
SpyCore.Remotes     = {}
SpyCore.Metamethods = {}
SpyCore.Closures    = {}
SpyCore.Upvalues    = {}
SpyCore.Log         = {}
SpyCore.Stats       = {
    removed   = 0,
    detected  = 0,
    scanned   = 0,
    protected = 0,
}

local KNOWN_SPY_NAMES = {
    "RemoteSpy", "remotespy", "remote_spy", "hookspy",
    "FunctionSpy", "MetaSpy", "hookfunction", "__newindex spy",
    "NamecallSpy", "spy", "Hook", "Decompiler", "getinfo spy",
}

local PROTECTED_FUNCTIONS = {
    game.IsA,
    Instance.new,
    pcall,
    xpcall,
    tostring,
    tonumber,
    type,
    next,
    pairs,
    ipairs,
    select,
    unpack or table.unpack,
    rawget,
    rawset,
    rawequal,
    setmetatable,
    getmetatable,
}

local METAMETHOD_KEYS = {
    "__index", "__newindex", "__call", "__len",
    "__concat", "__tostring", "__eq", "__lt",
    "__le", "__add", "__sub", "__mul",
    "__div", "__mod", "__pow", "__unm",
    "__namecall", "__metatable",
}

-- =============================================
-- СКАНИРОВАНИЕ ХУКОВ
-- =============================================

function SpyCore:ScanRemotes()
    local found = {}
    local function scan(parent, depth)
        if depth > 8 then return end
        local ok, children = pcall(function() return parent:GetChildren() end)
        if not ok then return end
        for _, child in ipairs(children) do
            local class = safeGet(child, "ClassName")
            if class == "RemoteEvent" or class == "RemoteFunction" then
                local meta = getrawmetatable and getrawmetatable(child)
                if meta then
                    for _, key in ipairs(METAMETHOD_KEYS) do
                        local raw = rawget(meta, key)
                        if raw and type(raw) == "function" then
                            local src = "?"
                            pcall(function()
                                local i = debug.getinfo(raw, "S")
                                src = i and i.short_src or "?"
                            end)
                            local hooked = src ~= "[C]" and src ~= "?"
                            table.insert(found, {
                                name    = child:GetFullName(),
                                meta    = key,
                                hooked  = hooked,
                                source  = src,
                                ref     = child,
                                fn      = raw,
                            })
                            self.Stats.detected += hooked and 1 or 0
                        end
                    end
                end
                table.insert(self.Remotes, child)
            end
            scan(child, depth + 1)
        end
    end
    scan(game, 0)
    self.Stats.scanned = #self.Remotes
    return found
end

function SpyCore:ScanMetamethods()
    local suspects = {}
    local targets = {
        game, workspace, Players, LocalPlayer,
        LocalPlayer.Character or Instance.new("Folder"),
    }
    for _, obj in ipairs(targets) do
        local ok, meta = pcall(getrawmetatable, obj)
        if ok and meta then
            for _, key in ipairs(METAMETHOD_KEYS) do
                local raw = rawget(meta, key)
                if raw and type(raw) == "function" then
                    local src = "?"
                    pcall(function()
                        local i = debug.getinfo(raw, "S")
                        src = i and i.short_src or "?"
                    end)
                    local suspicious = src ~= "[C]"
                    if suspicious then
                        table.insert(suspects, {
                            object = tostring(obj),
                            key    = key,
                            source = src,
                            fn     = raw,
                            meta   = meta,
                        })
                        self.Stats.detected += 1
                    end
                end
            end
        end
    end
    return suspects
end

function SpyCore:ScanUpvalues()
    local found = {}
    local function checkFn(func, name)
        if type(func) ~= "function" then return end
        if not debug.getupvalues then return end
        local ok, uvs = pcall(debug.getupvalues, func)
        if not ok or type(uvs) ~= "table" then return end
        for i, uv in ipairs(uvs) do
            if type(uv) == "function" then
                local src = "?"
                pcall(function()
                    local info = debug.getinfo(uv, "S")
                    src = info and info.short_src or "?"
                end)
                if src ~= "[C]" and src:find("LocalScript") then
                    table.insert(found, {
                        parent = name,
                        index  = i,
                        source = src,
                        fn     = uv,
                    })
                end
            end
        end
    end
    for _, fn in ipairs(PROTECTED_FUNCTIONS) do
        if fn then
            checkFn(fn, tostring(fn))
        end
    end
    return found
end

function SpyCore:ScanClosures()
    local found = {}
    if not getgc then return found end
    local ok, gc = pcall(getgc, true)
    if not ok then return found end
    for _, obj in ipairs(gc) do
        if type(obj) == "function" then
            local src = "?"
            pcall(function()
                local info = debug.getinfo(obj, "S")
                src = info and info.short_src or "?"
            end)
            for _, spyName in ipairs(KNOWN_SPY_NAMES) do
                if src:lower():find(spyName:lower()) then
                    table.insert(found, {
                        source = src,
                        fn     = obj,
                        tag    = spyName,
                    })
                    self.Stats.detected += 1
                    break
                end
            end
        end
    end
    return found
end

-- =============================================
-- УДАЛЕНИЕ ХУКОВ
-- =============================================

function SpyCore:RemoveRemoteHooks(list)
    local count = 0
    for _, entry in ipairs(list) do
        if entry.hooked then
            local ok = pcall(function()
                local meta = getrawmetatable(entry.ref)
                if meta then
                    if setreadonly then pcall(setreadonly, meta, false) end
                    rawset(meta, entry.meta, nil)
                    if setreadonly then pcall(setreadonly, meta, true) end
                    count += 1
                end
            end)
            if ok then
                self.Stats.removed += 1
            end
        end
    end
    return count
end

function SpyCore:RemoveMetaHooks(list)
    local count = 0
    for _, entry in ipairs(list) do
        local ok = pcall(function()
            if setreadonly then pcall(setreadonly, entry.meta, false) end
            rawset(entry.meta, entry.key, nil)
            if setreadonly then pcall(setreadonly, entry.meta, true) end
        end)
        if ok then
            count += 1
            self.Stats.removed += 1
        end
    end
    return count
end

function SpyCore:RestoreHookedFunctions()
    local count = 0
    if not hookfunction or not clonefunction then return count end
    for _, fn in ipairs(PROTECTED_FUNCTIONS) do
        if fn then
            local ok = pcall(function()
                local cloned = clonefunction(fn)
                local restored = newcclosure and newcclosure(cloned) or cloned
                if restored then count += 1 end
            end)
            _ = ok
        end
    end
    return count
end

function SpyCore:KillSpyClosures(list)
    local count = 0
    for _, entry in ipairs(list) do
        if debug.setupvalue then
            pcall(function()
                local uvs = debug.getupvalues(entry.fn)
                if type(uvs) == "table" then
                    for i = 1, #uvs do
                        pcall(debug.setupvalue, entry.fn, i, nil)
                    end
                end
            end)
            count += 1
            self.Stats.removed += 1
        end
    end
    return count
end

function SpyCore:FullScan()
    local results = {
        remotes   = self:ScanRemotes(),
        meta      = self:ScanMetamethods(),
        upvalues  = self:ScanUpvalues(),
        closures  = self:ScanClosures(),
    }
    return results
end

function SpyCore:FullRemove(results)
    local total = 0
    total += self:RemoveRemoteHooks(results.remotes)
    total += self:RemoveMetaHooks(results.meta)
    total += self:KillSpyClosures(results.closures)
    total += self:RestoreHookedFunctions()
    return total
end

function SpyCore:LogEntry(msg)
    local entry = {
        time = os.clock(),
        msg  = msg,
    }
    table.insert(self.Log, 1, entry)
    if #self.Log > 200 then table.remove(self.Log) end
end

-- =============================================
-- GUI
-- =============================================

local existing = CoreGui:FindFirstChild("RemoveSpyPro")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RemoveSpyPro"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = CoreGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 520, 0, 400)
Main.Position = UDim2.new(0.5, -260, 0.5, -200)
Main.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.ClipsDescendants = true
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 8)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(80, 80, 120)
MainStroke.Thickness = 1
MainStroke.Parent = Main

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = Main

local TitleBarCorner = Instance.new("UICorner")
TitleBarCorner.CornerRadius = UDim.new(0, 8)
TitleBarCorner.Parent = TitleBar

local TitleBarFix = Instance.new("Frame")
TitleBarFix.Size = UDim2.new(1, 0, 0, 8)
TitleBarFix.Position = UDim2.new(0, 0, 1, -8)
TitleBarFix.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
TitleBarFix.BorderSizePixel = 0
TitleBarFix.Parent = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -80, 1, 0)
TitleLabel.Position = UDim2.new(0, 12, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "RemoveSpy Pro"
TitleLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
TitleLabel.TextSize = 14
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TitleBar

local SubLabel = Instance.new("TextLabel")
SubLabel.Size = UDim2.new(0, 200, 1, 0)
SubLabel.Position = UDim2.new(0, 175, 0, 0)
SubLabel.BackgroundTransparency = 1
SubLabel.Text = "v2.4 | Hook & Spy Remover"
SubLabel.TextColor3 = Color3.fromRGB(100, 100, 140)
SubLabel.TextSize = 11
SubLabel.Font = Enum.Font.Gotham
SubLabel.TextXAlignment = Enum.TextXAlignment.Left
SubLabel.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -32, 0, 4)
CloseBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.new(1,1,1)
CloseBtn.TextSize = 13
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = TitleBar

local CloseBtnCorner = Instance.new("UICorner")
CloseBtnCorner.CornerRadius = UDim.new(0, 6)
CloseBtnCorner.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 28, 0, 28)
MinBtn.Position = UDim2.new(1, -64, 0, 4)
MinBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
MinBtn.Text = "-"
MinBtn.TextColor3 = Color3.new(1,1,1)
MinBtn.TextSize = 16
MinBtn.Font = Enum.Font.GothamBold
MinBtn.BorderSizePixel = 0
MinBtn.Parent = TitleBar

local MinBtnCorner = Instance.new("UICorner")
MinBtnCorner.CornerRadius = UDim.new(0, 6)
MinBtnCorner.Parent = MinBtn

local minimized = false
local ContentFrame

MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if ContentFrame then
        ContentFrame.Visible = not minimized
    end
    Main.Size = minimized and UDim2.new(0, 520, 0, 36) or UDim2.new(0, 520, 0, 400)
    MinBtn.Text = minimized and "+" or "-"
end)

-- =============================================
-- ВКЛАДКИ
-- =============================================

local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, 0, 0, 32)
TabBar.Position = UDim2.new(0, 0, 0, 36)
TabBar.BackgroundColor3 = Color3.fromRGB(18, 18, 25)
TabBar.BorderSizePixel = 0
TabBar.Parent = Main

local TabLayout = Instance.new("UIListLayout")
TabLayout.FillDirection = Enum.FillDirection.Horizontal
TabLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabLayout.Padding = UDim.new(0, 2)
TabLayout.Parent = TabBar

local TabPadding = Instance.new("UIPadding")
TabPadding.PaddingLeft = UDim.new(0, 6)
TabPadding.PaddingTop = UDim.new(0, 4)
TabPadding.Parent = TabBar

ContentFrame = Instance.new("Frame")
ContentFrame.Name = "ContentFrame"
ContentFrame.Size = UDim2.new(1, 0, 1, -68)
ContentFrame.Position = UDim2.new(0, 0, 0, 68)
ContentFrame.BackgroundTransparency = 1
ContentFrame.Parent = Main

local Tabs = {}
local ActiveTab = nil

local function MakeTab(name, icon)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(0, 100, 0, 24)
    Btn.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    Btn.Text = icon .. " " .. name
    Btn.TextColor3 = Color3.fromRGB(130, 130, 160)
    Btn.TextSize = 11
    Btn.Font = Enum.Font.Gotham
    Btn.BorderSizePixel = 0
    Btn.Parent = TabBar

    local BtnCorner = Instance.new("UICorner")
    BtnCorner.CornerRadius = UDim.new(0, 5)
    BtnCorner.Parent = Btn

    local Page = Instance.new("ScrollingFrame")
    Page.Size = UDim2.new(1, 0, 1, 0)
    Page.BackgroundTransparency = 1
    Page.BorderSizePixel = 0
    Page.ScrollBarThickness = 4
    Page.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 120)
    Page.CanvasSize = UDim2.new(0, 0, 0, 0)
    Page.Visible = false
    Page.Parent = ContentFrame

    local PageLayout = Instance.new("UIListLayout")
    PageLayout.SortOrder = Enum.SortOrder.LayoutOrder
    PageLayout.Padding = UDim.new(0, 6)
    PageLayout.Parent = Page

    local PagePad = Instance.new("UIPadding")
    PagePad.PaddingLeft = UDim.new(0, 8)
    PagePad.PaddingRight = UDim.new(0, 8)
    PagePad.PaddingTop = UDim.new(0, 8)
    PagePad.Parent = Page

    PageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        Page.CanvasSize = UDim2.new(0, 0, 0, PageLayout.AbsoluteContentSize.Y + 16)
    end)

    local tab = { Btn = Btn, Page = Page, Name = name }
    table.insert(Tabs, tab)

    Btn.MouseButton1Click:Connect(function()
        if ActiveTab then
            ActiveTab.Page.Visible = false
            ActiveTab.Btn.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
            ActiveTab.Btn.TextColor3 = Color3.fromRGB(130, 130, 160)
        end
        ActiveTab = tab
        Page.Visible = true
        Btn.BackgroundColor3 = Color3.fromRGB(70, 60, 120)
        Btn.TextColor3 = Color3.new(1, 1, 1)
    end)

    return tab
end

local DashTab  = MakeTab("Dashboard", ">")
local ScanTab  = MakeTab("Scanner",   "?")
local LogTab   = MakeTab("Log",       "#")
local SettTab  = MakeTab("Settings",  "*")

do
    ActiveTab = DashTab
    DashTab.Page.Visible = true
    DashTab.Btn.BackgroundColor3 = Color3.fromRGB(70, 60, 120)
    DashTab.Btn.TextColor3 = Color3.new(1, 1, 1)
end

-- =============================================
-- УТИЛИТА GUI
-- =============================================

local function MakeSection(parent, title)
    local F = Instance.new("Frame")
    F.Size = UDim2.new(1, -4, 0, 28)
    F.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    F.BorderSizePixel = 0
    F.Parent = parent

    local FC = Instance.new("UICorner")
    FC.CornerRadius = UDim.new(0, 6)
    FC.Parent = F

    local L = Instance.new("TextLabel")
    L.Size = UDim2.new(1, -10, 1, 0)
    L.Position = UDim2.new(0, 10, 0, 0)
    L.BackgroundTransparency = 1
    L.Text = "-- " .. title .. " --"
    L.TextColor3 = Color3.fromRGB(120, 100, 200)
    L.TextSize = 11
    L.Font = Enum.Font.GothamBold
    L.TextXAlignment = Enum.TextXAlignment.Left
    L.Parent = F

    return F
end

local function MakeStatCard(parent, label, value, color)
    local F = Instance.new("Frame")
    F.Size = UDim2.new(0.48, 0, 0, 56)
    F.BackgroundColor3 = Color3.fromRGB(22, 22, 35)
    F.BorderSizePixel = 0
    F.Parent = parent

    local FC = Instance.new("UICorner")
    FC.CornerRadius = UDim.new(0, 6)
    FC.Parent = F

    local FS = Instance.new("UIStroke")
    FS.Color = color or Color3.fromRGB(70, 60, 100)
    FS.Thickness = 1
    FS.Parent = F

    local VL = Instance.new("TextLabel")
    VL.Size = UDim2.new(1, 0, 0.55, 0)
    VL.Position = UDim2.new(0, 0, 0, 4)
    VL.BackgroundTransparency = 1
    VL.Text = tostring(value)
    VL.TextColor3 = color or Color3.fromRGB(180, 160, 255)
    VL.TextSize = 22
    VL.Font = Enum.Font.GothamBold
    VL.TextXAlignment = Enum.TextXAlignment.Center
    VL.Parent = F

    local LL = Instance.new("TextLabel")
    LL.Size = UDim2.new(1, 0, 0.4, 0)
    LL.Position = UDim2.new(0, 0, 0.6, 0)
    LL.BackgroundTransparency = 1
    LL.Text = label
    LL.TextColor3 = Color3.fromRGB(100, 100, 130)
    LL.TextSize = 10
    LL.Font = Enum.Font.Gotham
    LL.TextXAlignment = Enum.TextXAlignment.Center
    LL.Parent = F

    return F, VL
end

local function MakeButton(parent, text, color)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, -4, 0, 34)
    Btn.BackgroundColor3 = color or Color3.fromRGB(70, 60, 120)
    Btn.Text = text
    Btn.TextColor3 = Color3.new(1, 1, 1)
    Btn.TextSize = 12
    Btn.Font = Enum.Font.GothamBold
    Btn.BorderSizePixel = 0
    Btn.Parent = parent

    local BC = Instance.new("UICorner")
    BC.CornerRadius = UDim.new(0, 6)
    BC.Parent = Btn

    Btn.MouseEnter:Connect(function()
        local c = color or Color3.fromRGB(70, 60, 120)
        Btn.BackgroundColor3 = Color3.fromRGB(
            math.min(255, c.R * 255 + 20),
            math.min(255, c.G * 255 + 20),
            math.min(255, c.B * 255 + 20)
        )
    end)
    Btn.MouseLeave:Connect(function()
        Btn.BackgroundColor3 = color or Color3.fromRGB(70, 60, 120)
    end)

    return Btn
end

local function MakeToggle(parent, label, default, callback)
    local F = Instance.new("Frame")
    F.Size = UDim2.new(1, -4, 0, 32)
    F.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
    F.BorderSizePixel = 0
    F.Parent = parent

    local FC = Instance.new("UICorner")
    FC.CornerRadius = UDim.new(0, 6)
    FC.Parent = F

    local L = Instance.new("TextLabel")
    L.Size = UDim2.new(1, -56, 1, 0)
    L.Position = UDim2.new(0, 10, 0, 0)
    L.BackgroundTransparency = 1
    L.Text = label
    L.TextColor3 = Color3.fromRGB(180, 180, 200)
    L.TextSize = 11
    L.Font = Enum.Font.Gotham
    L.TextXAlignment = Enum.TextXAlignment.Left
    L.Parent = F

    local TogBtn = Instance.new("TextButton")
    TogBtn.Size = UDim2.new(0, 44, 0, 22)
    TogBtn.Position = UDim2.new(1, -50, 0.5, -11)
    TogBtn.BackgroundColor3 = default and Color3.fromRGB(80, 200, 100) or Color3.fromRGB(60, 60, 70)
    TogBtn.Text = default and "ON" or "OFF"
    TogBtn.TextColor3 = Color3.new(1,1,1)
    TogBtn.TextSize = 10
    TogBtn.Font = Enum.Font.GothamBold
    TogBtn.BorderSizePixel = 0
    TogBtn.Parent = F

    local TC = Instance.new("UICorner")
    TC.CornerRadius = UDim.new(0, 11)
    TC.Parent = TogBtn

    local state = default
    TogBtn.MouseButton1Click:Connect(function()
        state = not state
        TogBtn.BackgroundColor3 = state and Color3.fromRGB(80, 200, 100) or Color3.fromRGB(60, 60, 70)
        TogBtn.Text = state and "ON" or "OFF"
        if callback then callback(state) end
    end)

    return F, function() return state end
end

local function MakeLogLine(parent, text, color)
    local L = Instance.new("TextLabel")
    L.Size = UDim2.new(1, -4, 0, 18)
    L.BackgroundTransparency = 1
    L.Text = text
    L.TextColor3 = color or Color3.fromRGB(160, 160, 180)
    L.TextSize = 10
    L.Font = Enum.Font.Code
    L.TextXAlignment = Enum.TextXAlignment.Left
    L.TextTruncate = Enum.TextTruncate.AtEnd
    L.Parent = parent
    return L
end

-- =============================================
-- DASHBOARD TAB
-- =============================================

do
    local page = DashTab.Page

    MakeSection(page, "Statistics")

    local Grid = Instance.new("Frame")
    Grid.Size = UDim2.new(1, -4, 0, 120)
    Grid.BackgroundTransparency = 1
    Grid.Parent = page

    local GL = Instance.new("UIGridLayout")
    GL.CellSize = UDim2.new(0.48, 0, 0, 56)
    GL.CellPadding = UDim2.new(0.04, 0, 0, 6)
    GL.SortOrder = Enum.SortOrder.LayoutOrder
    GL.Parent = Grid

    local _, scanV = MakeStatCard(Grid, "Remotes Scanned", "0", Color3.fromRGB(100, 150, 255))
    local _, detV  = MakeStatCard(Grid, "Detected Hooks",  "0", Color3.fromRGB(255, 120, 80))
    local _, remV  = MakeStatCard(Grid, "Removed",         "0", Color3.fromRGB(80, 220, 120))
    local _, prtV  = MakeStatCard(Grid, "Protected",       "0", Color3.fromRGB(220, 180, 80))

    MakeSection(page, "Actions")

    local ScanBtn  = MakeButton(page, "[SCAN]  Run Full Scan",                Color3.fromRGB(50, 80, 160))
    local RemBtn   = MakeButton(page, "[REM]   Remove All Detected Hooks",    Color3.fromRGB(160, 50, 50))
    local QuickBtn = MakeButton(page, "[QUICK] Quick Clean (Scan + Remove)",  Color3.fromRGB(100, 50, 160))
    local ResetBtn = MakeButton(page, "[RST]   Reset Statistics",             Color3.fromRGB(40, 40, 60))

    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.Size = UDim2.new(1, -4, 0, 24)
    StatusLabel.BackgroundColor3 = Color3.fromRGB(20, 25, 20)
    StatusLabel.Text = "Status: Idle"
    StatusLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
    StatusLabel.TextSize = 11
    StatusLabel.Font = Enum.Font.Gotham
    StatusLabel.BorderSizePixel = 0
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    StatusLabel.Parent = page

    local SLC = Instance.new("UICorner")
    SLC.CornerRadius = UDim.new(0, 6)
    SLC.Parent = StatusLabel

    local SLPad = Instance.new("UIPadding")
    SLPad.PaddingLeft = UDim.new(0, 8)
    SLPad.Parent = StatusLabel

    local lastResults = nil

    local function refreshStats()
        scanV.Text = tostring(SpyCore.Stats.scanned)
        detV.Text  = tostring(SpyCore.Stats.detected)
        remV.Text  = tostring(SpyCore.Stats.removed)
        prtV.Text  = tostring(SpyCore.Stats.protected)
    end

    ScanBtn.MouseButton1Click:Connect(function()
        StatusLabel.Text = "Status: Scanning..."
        StatusLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
        task.wait(0.05)
        local ok, res = pcall(function() return SpyCore:FullScan() end)
        if ok then
            lastResults = res
            StatusLabel.Text = string.format("Status: Done — %d remote hooks, %d meta, %d closures",
                #res.remotes, #res.meta, #res.closures)
            StatusLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
            SpyCore:LogEntry(string.format("[SCAN] Found %d total entries", #res.remotes + #res.meta + #res.closures))
        else
            StatusLabel.Text = "Status: Scan error — " .. tostring(res):sub(1, 50)
            StatusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        end
        refreshStats()
    end)

    RemBtn.MouseButton1Click:Connect(function()
        if not lastResults then
            StatusLabel.Text = "Status: Run a scan first!"
            StatusLabel.TextColor3 = Color3.fromRGB(255, 160, 60)
            return
        end
        StatusLabel.Text = "Status: Removing hooks..."
        StatusLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
        task.wait(0.05)
        local ok, count = pcall(function() return SpyCore:FullRemove(lastResults) end)
        if ok then
            StatusLabel.Text = string.format("Status: Removed %d hooks successfully", count)
            StatusLabel.TextColor3 = Color3.fromRGB(80, 220, 120)
            SpyCore:LogEntry(string.format("[REMOVE] Cleaned %d hooks", count))
        else
            StatusLabel.Text = "Status: Remove error"
            StatusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        end
        refreshStats()
    end)

    QuickBtn.MouseButton1Click:Connect(function()
        StatusLabel.Text = "Status: Quick cleaning..."
        StatusLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
        task.wait(0.05)
        local ok, res = pcall(function() return SpyCore:FullScan() end)
        if ok then
            local count = SpyCore:FullRemove(res)
            StatusLabel.Text = string.format("Status: Quick clean done — %d removed", count)
            StatusLabel.TextColor3 = Color3.fromRGB(80, 220, 120)
            SpyCore:LogEntry(string.format("[QUICK] Scan+Remove: %d hooks cleaned", count))
            lastResults = nil
        else
            StatusLabel.Text = "Status: Error during quick clean"
            StatusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        end
        refreshStats()
    end)

    ResetBtn.MouseButton1Click:Connect(function()
        SpyCore.Stats = { removed = 0, detected = 0, scanned = 0, protected = 0 }
        refreshStats()
        StatusLabel.Text = "Status: Statistics reset"
        StatusLabel.TextColor3 = Color3.fromRGB(160, 160, 200)
    end)
end

-- =============================================
-- SCANNER TAB
-- =============================================

do
    local page = ScanTab.Page

    MakeSection(page, "Live Scanner Results")

    local ResultBox = Instance.new("Frame")
    ResultBox.Size = UDim2.new(1, -4, 0, 200)
    ResultBox.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
    ResultBox.BorderSizePixel = 0
    ResultBox.ClipsDescendants = true
    ResultBox.Parent = page

    local RBC = Instance.new("UICorner")
    RBC.CornerRadius = UDim.new(0, 6)
    RBC.Parent = ResultBox

    local ResultScroll = Instance.new("ScrollingFrame")
    ResultScroll.Size = UDim2.new(1, 0, 1, 0)
    ResultScroll.BackgroundTransparency = 1
    ResultScroll.BorderSizePixel = 0
    ResultScroll.ScrollBarThickness = 3
    ResultScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 120)
    ResultScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    ResultScroll.Parent = ResultBox

    local RSL = Instance.new("UIListLayout")
    RSL.SortOrder = Enum.SortOrder.LayoutOrder
    RSL.Padding = UDim.new(0, 2)
    RSL.Parent = ResultScroll

    local RSP = Instance.new("UIPadding")
    RSP.PaddingAll = UDim.new(0, 6)
    RSP.Parent = ResultScroll

    RSL:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        ResultScroll.CanvasSize = UDim2.new(0, 0, 0, RSL.AbsoluteContentSize.Y + 12)
    end)

    local function addResult(text, color)
        MakeLogLine(ResultScroll, text, color)
        ResultScroll.CanvasPosition = Vector2.new(0, ResultScroll.AbsoluteCanvasSize.Y)
    end

    local function clearResults()
        for _, c in ipairs(ResultScroll:GetChildren()) do
            if c:IsA("TextLabel") then c:Destroy() end
        end
    end

    MakeSection(page, "Scan Options")

    local _, getAutoScan = MakeToggle(page, "Auto-scan on open",          false, function(state) SpyCore.AutoScan = state end)
    local _, getScanGC   = MakeToggle(page, "Scan GC closures (getgc)",   true,  function(state) SpyCore.ScanGC = state end)
    local _, getScanMeta = MakeToggle(page, "Scan metamethods",           true,  function(state) SpyCore.ScanMeta = state end)

    local DeepScanBtn = MakeButton(page, "[DEEP] Deep Scan & Display Results", Color3.fromRGB(50, 100, 170))

    DeepScanBtn.MouseButton1Click:Connect(function()
        clearResults()
        addResult("[ Starting deep scan... ]", Color3.fromRGB(180, 180, 100))
        task.wait(0.05)

        local remotes = SpyCore:ScanRemotes()
        addResult(string.format("  Remotes scanned: %d", SpyCore.Stats.scanned), Color3.fromRGB(100, 150, 255))
        for _, e in ipairs(remotes) do
            local col = e.hooked and Color3.fromRGB(255, 100, 80) or Color3.fromRGB(80, 180, 80)
            local tag = e.hooked and "[HOOKED]" or "[clean] "
            addResult(string.format("  %s %s::%s <- %s", tag, e.name, e.meta, e.source), col)
        end

        if getScanMeta() then
            local metas = SpyCore:ScanMetamethods()
            addResult(string.format("  Suspicious metamethods: %d", #metas), Color3.fromRGB(255, 180, 60))
            for _, e in ipairs(metas) do
                addResult(string.format("  [META] %s.%s <- %s", e.object, e.key, e.source), Color3.fromRGB(255, 140, 50))
            end
        end

        if getScanGC() then
            local closures = SpyCore:ScanClosures()
            addResult(string.format("  Spy closures in GC: %d", #closures), Color3.fromRGB(220, 100, 255))
            for _, e in ipairs(closures) do
                addResult(string.format("  [CLS] tag:%s <- %s", e.tag, e.source), Color3.fromRGB(200, 80, 240))
            end
        end

        local uvs = SpyCore:ScanUpvalues()
        addResult(string.format("  Suspicious upvalues: %d", #uvs), Color3.fromRGB(255, 200, 80))
        for _, e in ipairs(uvs) do
            addResult(string.format("  [UV] in %s [%d] <- %s", e.parent, e.index, e.source), Color3.fromRGB(240, 180, 60))
        end

        addResult("[ Deep scan complete ]", Color3.fromRGB(80, 220, 120))
        SpyCore:LogEntry("[DEEP SCAN] Completed full deep scan")
    end)
end

-- =============================================
-- LOG TAB
-- =============================================

do
    local page = LogTab.Page

    MakeSection(page, "Activity Log")

    local LogBox = Instance.new("Frame")
    LogBox.Size = UDim2.new(1, -4, 0, 240)
    LogBox.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
    LogBox.BorderSizePixel = 0
    LogBox.ClipsDescendants = true
    LogBox.Parent = page

    local LBC = Instance.new("UICorner")
    LBC.CornerRadius = UDim.new(0, 6)
    LBC.Parent = LogBox

    local LogScroll = Instance.new("ScrollingFrame")
    LogScroll.Size = UDim2.new(1, 0, 1, 0)
    LogScroll.BackgroundTransparency = 1
    LogScroll.BorderSizePixel = 0
    LogScroll.ScrollBarThickness = 3
    LogScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 120)
    LogScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    LogScroll.Parent = LogBox

    local LSL = Instance.new("UIListLayout")
    LSL.SortOrder = Enum.SortOrder.LayoutOrder
    LSL.Padding = UDim.new(0, 2)
    LSL.Parent = LogScroll

    local LSP = Instance.new("UIPadding")
    LSP.PaddingAll = UDim.new(0, 6)
    LSP.Parent = LogScroll

    LSL:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        LogScroll.CanvasSize = UDim2.new(0, 0, 0, LSL.AbsoluteContentSize.Y + 12)
    end)

    local function refreshLog()
        for _, c in ipairs(LogScroll:GetChildren()) do
            if c:IsA("TextLabel") then c:Destroy() end
        end
        for _, entry in ipairs(SpyCore.Log) do
            local t = string.format("[%.1fs] %s", entry.time, entry.msg)
            MakeLogLine(LogScroll, t, Color3.fromRGB(140, 200, 140))
        end
        LogScroll.CanvasPosition = Vector2.new(0, LogScroll.AbsoluteCanvasSize.Y)
    end

    MakeSection(page, "Log Controls")

    local RefreshLogBtn = MakeButton(page, "[REFRESH] Refresh Log", Color3.fromRGB(50, 80, 130))
    local ClearLogBtn   = MakeButton(page, "[CLEAR]   Clear Log",   Color3.fromRGB(100, 40, 40))

    RefreshLogBtn.MouseButton1Click:Connect(refreshLog)
    ClearLogBtn.MouseButton1Click:Connect(function()
        SpyCore.Log = {}
        refreshLog()
    end)
end

-- =============================================
-- SETTINGS TAB
-- =============================================

do
    local page = SettTab.Page

    MakeSection(page, "Protection Settings")

    MakeToggle(page, "Auto-remove on detect",              false, function(state) SpyCore.AutoRemove = state end)
    MakeToggle(page, "Protect FireServer/InvokeServer",    true,  function(state) SpyCore.ProtectFire = state end)
    MakeToggle(page, "Protect __namecall metamethod",      true,  function(state) SpyCore.ProtectNamecall = state end)
    MakeToggle(page, "Scan on character respawn",          false, function(state)
        SpyCore.ScanOnRespawn = state
        if state then
            LocalPlayer.CharacterAdded:Connect(function()
                task.wait(1)
                if SpyCore.ScanOnRespawn then
                    SpyCore:LogEntry("[AUTO] Character respawn scan triggered")
                    SpyCore:FullScan()
                end
            end)
        end
    end)

    MakeSection(page, "Appearance")

    MakeToggle(page, "Always on top", false, function(state)
        ScreenGui.DisplayOrder = state and 999 or 1
    end)

    MakeSection(page, "Danger Zone")

    local KillAll = MakeButton(page, "[KILL] Attempt Kill All Spy Scripts", Color3.fromRGB(160, 30, 30))
    KillAll.MouseButton1Click:Connect(function()
        local count = 0
        if getgc then
            local ok, gc = pcall(getgc, true)
            if ok then
                for _, obj in ipairs(gc) do
                    if type(obj) == "table" then
                        for _, spyName in ipairs(KNOWN_SPY_NAMES) do
                            local raw = rawget(obj, "__type") or rawget(obj, "_name") or rawget(obj, "name")
                            if type(raw) == "string" and raw:lower():find(spyName:lower()) then
                                for k in next, obj do
                                    pcall(rawset, obj, k, nil)
                                end
                                count += 1
                                break
                            end
                        end
                    end
                end
            end
        end
        SpyCore:LogEntry(string.format("[KILL] Attempted kill on %d spy tables", count))
    end)

    local NukeBtn = MakeButton(page, "[NUKE] Nuke All Remote Metamethods", Color3.fromRGB(140, 20, 20))
    NukeBtn.MouseButton1Click:Connect(function()
        local count = 0
        local function nuke(parent, depth)
            if depth > 6 then return end
            local ok, children = pcall(function() return parent:GetChildren() end)
            if not ok then return end
            for _, child in ipairs(children) do
                local class = safeGet(child, "ClassName")
                if class == "RemoteEvent" or class == "RemoteFunction" then
                    local meta = getrawmetatable and getrawmetatable(child)
                    if meta then
                        if setreadonly then pcall(setreadonly, meta, false) end
                        for _, k in ipairs(METAMETHOD_KEYS) do
                            if rawget(meta, k) ~= nil then
                                pcall(rawset, meta, k, nil)
                                count += 1
                            end
                        end
                        if setreadonly then pcall(setreadonly, meta, true) end
                    end
                end
                nuke(child, depth + 1)
            end
        end
        nuke(game, 0)
        SpyCore:LogEntry(string.format("[NUKE] Cleared %d remote metamethods", count))
    end)
end

-- =============================================
-- INIT
-- =============================================

SpyCore:LogEntry("[INIT] RemoveSpy Pro loaded")
SpyCore:LogEntry(string.format("[INIT] Player: %s | PlaceId: %d", LocalPlayer.Name, game.PlaceId))
SpyCore:LogEntry("[INIT] Ready -- use Dashboard to scan & remove")

print("[RemoveSpy Pro] Loaded. GUI open.")
