-- ============================================================
-- Player Action Watcher
-- Следит за всеми игроками через workspace (публичные данные)
-- Показывает объекты добавленные в Character -> действия
-- ============================================================

local Players    = game:GetService("Players")
local CoreGui    = game:GetService("CoreGui")
local LP         = Players.LocalPlayer

-- ============================================================
-- СЛОВАРЬ ДЕЙСТВИЙ
-- Если имя объекта совпадает -> показываем человеческое название
-- ============================================================

local ACTION_MAP = {
    -- Боевые
    ["Blocking"]       = { label = "🛡 Blocking",       color = Color3.fromRGB(100, 180, 255) },
    ["RagdollCancel"]  = { label = "⚡ Evasive/Dodge",   color = Color3.fromRGB(255, 220, 60)  },
    ["Ragdoll"]        = { label = "💀 Ragdoll",         color = Color3.fromRGB(255, 80,  80)  },
    ["Stunned"]        = { label = "😵 Stunned",         color = Color3.fromRGB(255, 140, 60)  },
    ["Parried"]        = { label = "⚔️ Parried",         color = Color3.fromRGB(255, 200, 80)  },
    ["Guard"]          = { label = "🔰 Guard",           color = Color3.fromRGB(80,  200, 120) },
    ["Invincible"]     = { label = "✨ Invincible",      color = Color3.fromRGB(200, 200, 255) },
    ["Knockback"]      = { label = "💥 Knockback",       color = Color3.fromRGB(255, 100, 60)  },
    ["Sprint"]         = { label = "🏃 Sprinting",       color = Color3.fromRGB(120, 220, 120) },
    ["Dash"]           = { label = "💨 Dashing",         color = Color3.fromRGB(80,  220, 220) },
    ["Attack"]         = { label = "⚔️ Attacking",       color = Color3.fromRGB(255, 80,  120) },
    ["Combo"]          = { label = "🔥 Combo",           color = Color3.fromRGB(255, 120, 60)  },
    ["Dead"]           = { label = "💀 Dead",            color = Color3.fromRGB(180, 50,  50)  },
    ["Skill"]          = { label = "✴️ Skill",           color = Color3.fromRGB(180, 100, 255) },
    ["Ultimate"]       = { label = "💫 Ultimate",        color = Color3.fromRGB(255, 200, 255) },
    ["Evasive"]        = { label = "💨 Evasive",         color = Color3.fromRGB(60,  220, 255) },
    ["Communicate"]    = { label = "📡 Communicate",     color = Color3.fromRGB(200, 200, 80)  },
    -- Статусы
    ["Burning"]        = { label = "🔥 Burning",         color = Color3.fromRGB(255, 140, 40)  },
    ["Frozen"]         = { label = "❄️ Frozen",          color = Color3.fromRGB(140, 200, 255) },
    ["Poisoned"]       = { label = "☠️ Poisoned",        color = Color3.fromRGB(100, 220, 80)  },
    -- Communicate значения
    ["f"]              = { label = "[ f ] action",       color = Color3.fromRGB(255, 180, 80)  },
    ["h"]              = { label = "[ h ] block/hold",   color = Color3.fromRGB(100, 180, 255) },
    ["q"]              = { label = "[ q ] evade",        color = Color3.fromRGB(60,  220, 255) },
    ["e"]              = { label = "[ e ] interact",     color = Color3.fromRGB(120, 255, 120) },
    ["r"]              = { label = "[ r ] skill",        color = Color3.fromRGB(200, 100, 255) },
    ["g"]              = { label = "[ g ] grab",         color = Color3.fromRGB(255, 150, 60)  },
    ["m1"]             = { label = "[ M1 ] attack",      color = Color3.fromRGB(255, 80,  80)  },
    ["m2"]             = { label = "[ M2 ] heavy",       color = Color3.fromRGB(255, 50,  50)  },
}

-- ============================================================
-- УТИЛИТЫ
-- ============================================================

local function getAction(name)
    -- Прямое совпадение
    local exact = ACTION_MAP[name]
    if exact then return exact end
    -- Частичное (case-insensitive)
    local low = name:lower()
    for key, val in next, ACTION_MAP do
        if low:find(key:lower(), 1, true) then return val end
    end
    -- Неизвестный объект
    return { label = "? " .. name, color = Color3.fromRGB(140, 140, 160) }
end

local function getProps(obj)
    -- Пробуем достать значение объекта (IntValue, StringValue и т.д.)
    local info = ""
    pcall(function()
        local cls = obj.ClassName
        if cls == "StringValue" or cls == "IntValue" or cls == "NumberValue"
        or cls == "BoolValue" or cls == "ObjectValue" then
            info = " = " .. tostring(obj.Value)
        end
    end)
    -- Дочерние объекты (Communicate { Dash=W, Key=Q, Goal=... })
    pcall(function()
        local kids = {}
        for _, c in ipairs(obj:GetChildren()) do
            local v = ""
            pcall(function() v = tostring(c.Value) end)
            table.insert(kids, c.Name .. (v ~= "" and ("=" .. v) or ""))
        end
        if #kids > 0 then
            info = info .. "  { " .. table.concat(kids, ", ") .. " }"
        end
    end)
    return info
end

local function timeStr()
    return string.format("[%05.1f]", os.clock() % 100000)
end

local function isCharacterOf(obj, player)
    return player.Character and obj == player.Character
end

-- ============================================================
-- GUI
-- ============================================================

local existing = CoreGui:FindFirstChild("PlayerWatcher")
if existing then existing:Destroy() end

local SG = Instance.new("ScreenGui")
SG.Name           = "PlayerWatcher"
SG.ResetOnSpawn   = false
SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SG.Parent         = CoreGui

local function corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 6); c.Parent = p
end
local function stroke(p, col, th)
    local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th or 1; s.Parent = p
end

-- Главное окно
local Main = Instance.new("Frame")
Main.Name             = "Main"
Main.Size             = UDim2.new(0, 580, 0, 500)
Main.Position         = UDim2.new(0.5, -290, 0.5, -250)
Main.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
Main.BorderSizePixel  = 0
Main.Active           = true
Main.Draggable        = true
Main.ClipsDescendants = true
Main.Parent           = SG
corner(Main, 8)
stroke(Main, Color3.fromRGB(60, 50, 100))

-- TitleBar
local TitleBar = Instance.new("Frame")
TitleBar.Size             = UDim2.new(1, 0, 0, 34)
TitleBar.BackgroundColor3 = Color3.fromRGB(15, 15, 24)
TitleBar.BorderSizePixel  = 0
TitleBar.Parent           = Main
corner(TitleBar, 8)
local fix = Instance.new("Frame")
fix.Size = UDim2.new(1,0,0,8); fix.Position = UDim2.new(0,0,1,-8)
fix.BackgroundColor3 = Color3.fromRGB(15,15,24); fix.BorderSizePixel = 0; fix.Parent = TitleBar

local TitleLbl = Instance.new("TextLabel")
TitleLbl.Size               = UDim2.new(1,-80,1,0)
TitleLbl.Position           = UDim2.new(0,12,0,0)
TitleLbl.BackgroundTransparency = 1
TitleLbl.Text               = "Player Watcher  |  workspace реплика"
TitleLbl.TextColor3         = Color3.fromRGB(180,180,255)
TitleLbl.TextSize           = 12
TitleLbl.Font               = Enum.Font.GothamBold
TitleLbl.TextXAlignment     = Enum.TextXAlignment.Left
TitleLbl.Parent             = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size             = UDim2.new(0,26,0,26)
CloseBtn.Position         = UDim2.new(1,-30,0,4)
CloseBtn.BackgroundColor3 = Color3.fromRGB(180,50,50)
CloseBtn.Text             = "X"; CloseBtn.TextColor3 = Color3.new(1,1,1)
CloseBtn.TextSize         = 12; CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.BorderSizePixel  = 0; CloseBtn.Parent = TitleBar
corner(CloseBtn, 5)
CloseBtn.MouseButton1Click:Connect(function() SG:Destroy() end)

-- Фильтры / контролы
local CtrlBar = Instance.new("Frame")
CtrlBar.Size             = UDim2.new(1,0,0,34)
CtrlBar.Position         = UDim2.new(0,0,0,34)
CtrlBar.BackgroundColor3 = Color3.fromRGB(13,13,21)
CtrlBar.BorderSizePixel  = 0
CtrlBar.Parent           = Main
local CL = Instance.new("UIListLayout")
CL.FillDirection = Enum.FillDirection.Horizontal
CL.Padding = UDim.new(0,5)
CL.VerticalAlignment = Enum.VerticalAlignment.Center
CL.Parent = CtrlBar
local CP = Instance.new("UIPadding"); CP.PaddingLeft = UDim.new(0,6); CP.Parent = CtrlBar

local function makeBtn(text, col, w)
    local B = Instance.new("TextButton")
    B.Size = UDim2.new(0, w or 110, 0, 26)
    B.BackgroundColor3 = col
    B.Text = text; B.TextColor3 = Color3.new(1,1,1)
    B.TextSize = 10; B.Font = Enum.Font.GothamBold
    B.BorderSizePixel = 0; B.Parent = CtrlBar
    corner(B, 5)
    return B
end

local StartBtn   = makeBtn("▶ WATCH ON",   Color3.fromRGB(30,130,50), 110)
local StopBtn    = makeBtn("■ WATCH OFF",  Color3.fromRGB(120,20,20), 110)
local ClearBtn   = makeBtn("🗑 Очистить",  Color3.fromRGB(35,20,35),  100)
local CopyBtn    = makeBtn("📋 Копировать",Color3.fromRGB(25,50,100), 110)

-- Настройки
local SettBar = Instance.new("Frame")
SettBar.Size             = UDim2.new(1,-12,0,28)
SettBar.Position         = UDim2.new(0,6,0,70)
SettBar.BackgroundColor3 = Color3.fromRGB(13,13,21)
SettBar.BorderSizePixel  = 0
SettBar.Parent           = Main
corner(SettBar, 5)
local SL = Instance.new("UIListLayout")
SL.FillDirection = Enum.FillDirection.Horizontal
SL.Padding = UDim.new(0,6)
SL.VerticalAlignment = Enum.VerticalAlignment.Center
SL.Parent = SettBar
local SP = Instance.new("UIPadding"); SP.PaddingLeft = UDim.new(0,8); SP.Parent = SettBar

-- toggle helpers
local function makeToggle(parent, text, default, w)
    local state = default
    local B = Instance.new("TextButton")
    B.Size = UDim2.new(0, w or 140, 0, 22)
    B.BackgroundColor3 = default and Color3.fromRGB(30,120,50) or Color3.fromRGB(60,30,30)
    B.Text = text .. ": " .. (default and "ON" or "OFF")
    B.TextColor3 = Color3.new(1,1,1)
    B.TextSize = 9; B.Font = Enum.Font.GothamBold
    B.BorderSizePixel = 0; B.Parent = parent
    corner(B, 4)
    B.MouseButton1Click:Connect(function()
        state = not state
        B.BackgroundColor3 = state and Color3.fromRGB(30,120,50) or Color3.fromRGB(60,30,30)
        B.Text = text .. ": " .. (state and "ON" or "OFF")
    end)
    return B, function() return state end
end

local _, getShowSelf    = makeToggle(SettBar, "Показывать себя", false, 150)
local _, getShowUnknown = makeToggle(SettBar, "Неизвестные obj", true,  155)
local _, getShowRemoved = makeToggle(SettBar, "Removed события", false, 155)

-- Статус
local StatBar = Instance.new("Frame")
StatBar.Size             = UDim2.new(1,-12,0,22)
StatBar.Position         = UDim2.new(0,6,0,102)
StatBar.BackgroundColor3 = Color3.fromRGB(11,11,18)
StatBar.BorderSizePixel  = 0
StatBar.Parent           = Main
corner(StatBar, 5)

local StatLbl = Instance.new("TextLabel")
StatLbl.Size               = UDim2.new(1,-70,1,0)
StatLbl.Position           = UDim2.new(0,8,0,0)
StatLbl.BackgroundTransparency = 1
StatLbl.Text               = "Нажми ▶ WATCH ON"
StatLbl.TextColor3         = Color3.fromRGB(110,110,150)
StatLbl.TextSize           = 10; StatLbl.Font = Enum.Font.Gotham
StatLbl.TextXAlignment     = Enum.TextXAlignment.Left
StatLbl.Parent             = StatBar

local CountLbl = Instance.new("TextLabel")
CountLbl.Size               = UDim2.new(0,60,1,0)
CountLbl.Position           = UDim2.new(1,-64,0,0)
CountLbl.BackgroundTransparency = 1
CountLbl.Text               = "0 событий"
CountLbl.TextColor3         = Color3.fromRGB(80,200,120)
CountLbl.TextSize           = 10; CountLbl.Font = Enum.Font.GothamBold
CountLbl.TextXAlignment     = Enum.TextXAlignment.Right
CountLbl.Parent             = StatBar

-- Лог
local LogBox = Instance.new("Frame")
LogBox.Size             = UDim2.new(1,-12,0,355)
LogBox.Position         = UDim2.new(0,6,0,128)
LogBox.BackgroundColor3 = Color3.fromRGB(7,7,13)
LogBox.BorderSizePixel  = 0
LogBox.ClipsDescendants = true
LogBox.Parent           = Main
corner(LogBox, 6)
stroke(LogBox, Color3.fromRGB(45,35,80))

local LogScroll = Instance.new("ScrollingFrame")
LogScroll.Size                  = UDim2.new(1,0,1,0)
LogScroll.BackgroundTransparency = 1
LogScroll.BorderSizePixel       = 0
LogScroll.ScrollBarThickness    = 4
LogScroll.ScrollBarImageColor3  = Color3.fromRGB(100,60,180)
LogScroll.CanvasSize            = UDim2.new(0,0,0,0)
LogScroll.Parent                = LogBox

local LogLayout = Instance.new("UIListLayout")
LogLayout.Padding = UDim.new(0,2)
LogLayout.Parent  = LogScroll
local LogPad = Instance.new("UIPadding"); LogPad.PaddingAll = UDim.new(0,4); LogPad.Parent = LogScroll

LogLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    LogScroll.CanvasSize = UDim2.new(0,0,0, LogLayout.AbsoluteContentSize.Y + 8)
end)

-- ============================================================
-- ЛОГ СТРОКИ
-- ============================================================

local eventCount = 0
local logLines   = {}   -- для копирования

local function addEvent(player, child, isRemoved)
    eventCount = eventCount + 1
    CountLbl.Text = tostring(eventCount) .. " ев."

    local action  = getAction(child.Name)
    local props   = getProps(child)
    local ts      = timeStr()
    local isSelf  = player == LP
    local removed = isRemoved and " [-]" or " [+]"

    local displayName = isSelf and ("● " .. player.Name .. " (ты)") or ("○ " .. player.Name)
    local lineText    = string.format("%s%s  %s  %s%s  %s",
        ts, removed, displayName, action.label, props, child:GetFullName())

    table.insert(logLines, lineText)

    -- GUI строка
    local Row = Instance.new("Frame")
    Row.Size             = UDim2.new(1,-4,0,0)
    Row.AutomaticSize    = Enum.AutomaticSize.Y
    Row.BackgroundColor3 = isRemoved
        and Color3.fromRGB(30,12,12)
        or (isSelf and Color3.fromRGB(14,20,14) or Color3.fromRGB(12,12,22))
    Row.BorderSizePixel  = 0
    Row.Parent           = LogScroll
    corner(Row, 3)

    -- Полоска слева по цвету действия
    local Bar = Instance.new("Frame")
    Bar.Size             = UDim2.new(0,3,1,0)
    Bar.BackgroundColor3 = isRemoved and Color3.fromRGB(120,40,40) or action.color
    Bar.BorderSizePixel  = 0
    Bar.Parent           = Row
    corner(Bar, 2)

    -- Время
    local TimeLbl = Instance.new("TextLabel")
    TimeLbl.Size               = UDim2.new(0,54,0,16)
    TimeLbl.Position           = UDim2.new(0,7,0,2)
    TimeLbl.BackgroundTransparency = 1
    TimeLbl.Text               = ts .. removed
    TimeLbl.TextColor3         = Color3.fromRGB(90,90,120)
    TimeLbl.TextSize           = 9; TimeLbl.Font = Enum.Font.Code
    TimeLbl.TextXAlignment     = Enum.TextXAlignment.Left
    TimeLbl.Parent             = Row

    -- Имя игрока
    local PlayerLbl = Instance.new("TextLabel")
    PlayerLbl.Size               = UDim2.new(0,130,0,16)
    PlayerLbl.Position           = UDim2.new(0,64,0,2)
    PlayerLbl.BackgroundTransparency = 1
    PlayerLbl.Text               = displayName
    PlayerLbl.TextColor3         = isSelf
        and Color3.fromRGB(80,220,120)
        or  Color3.fromRGB(180,160,255)
    PlayerLbl.TextSize           = 10; PlayerLbl.Font = Enum.Font.GothamBold
    PlayerLbl.TextXAlignment     = Enum.TextXAlignment.Left
    PlayerLbl.Parent             = Row

    -- Действие
    local ActLbl = Instance.new("TextLabel")
    ActLbl.Size               = UDim2.new(0,160,0,16)
    ActLbl.Position           = UDim2.new(0,196,0,2)
    ActLbl.BackgroundTransparency = 1
    ActLbl.Text               = action.label
    ActLbl.TextColor3         = isRemoved and Color3.fromRGB(150,80,80) or action.color
    ActLbl.TextSize           = 10; ActLbl.Font = Enum.Font.GothamBold
    ActLbl.TextXAlignment     = Enum.TextXAlignment.Left
    ActLbl.Parent             = Row

    -- Пропсы/значения
    if props ~= "" then
        local PropsLbl = Instance.new("TextLabel")
        PropsLbl.Size               = UDim2.new(1,-12,0,0)
        PropsLbl.Position           = UDim2.new(0,10,0,18)
        PropsLbl.AutomaticSize      = Enum.AutomaticSize.Y
        PropsLbl.BackgroundTransparency = 1
        PropsLbl.Text               = props
        PropsLbl.TextColor3         = Color3.fromRGB(160,160,180)
        PropsLbl.TextSize           = 9; PropsLbl.Font = Enum.Font.Code
        PropsLbl.TextXAlignment     = Enum.TextXAlignment.Left
        PropsLbl.TextWrapped        = true
        PropsLbl.Parent             = Row
    end

    -- Авто-скролл
    task.defer(function()
        LogScroll.CanvasPosition = Vector2.new(0, LogScroll.AbsoluteCanvasSize.Y)
    end)
end

-- ============================================================
-- WATCHER ENGINE
-- ============================================================

local watchActive   = false
local connections   = {}

local function stopWatch()
    watchActive = false
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    connections = {}
    StatLbl.Text       = "Watcher остановлен"
    StatLbl.TextColor3 = Color3.fromRGB(180,80,80)
end

local function startWatch()
    if watchActive then stopWatch() end
    watchActive = true
    StatLbl.Text       = "Watching..."
    StatLbl.TextColor3 = Color3.fromRGB(80,220,120)

    -- workspace.DescendantAdded -> смотрим все изменения Character
    local c1 = workspace.DescendantAdded:Connect(function(child)
        if not watchActive then return end
        -- Находим игрока которому принадлежит этот Character
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character and child.Parent == player.Character then
                -- Фильтр: себя показывать?
                if player == LP and not getShowSelf() then return end
                -- Фильтр: неизвестные?
                local action = getAction(child.Name)
                if action.label:sub(1,1) == "?" and not getShowUnknown() then return end
                task.defer(function()
                    addEvent(player, child, false)
                end)
                return
            end
        end
    end)
    table.insert(connections, c1)

    -- workspace.DescendantRemoving -> когда действие закончилось
    local c2 = workspace.DescendantRemoving:Connect(function(child)
        if not watchActive then return end
        if not getShowRemoved() then return end
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character and child.Parent == player.Character then
                if player == LP and not getShowSelf() then return end
                local action = getAction(child.Name)
                if action.label:sub(1,1) == "?" and not getShowUnknown() then return end
                task.defer(function()
                    addEvent(player, child, true)
                end)
                return
            end
        end
    end)
    table.insert(connections, c2)

    -- Следим за новыми игроками которые заходят
    local c3 = Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(char)
            StatLbl.Text = "Новый: " .. player.Name .. " зашёл"
        end)
    end)
    table.insert(connections, c3)
end

-- ============================================================
-- КНОПКИ
-- ============================================================

StartBtn.MouseButton1Click:Connect(startWatch)
StopBtn.MouseButton1Click:Connect(stopWatch)

ClearBtn.MouseButton1Click:Connect(function()
    for _, c in ipairs(LogScroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    logLines = {}; eventCount = 0; CountLbl.Text = "0 ев."
end)

CopyBtn.MouseButton1Click:Connect(function()
    if setclipboard and #logLines > 0 then
        pcall(setclipboard, table.concat(logLines, "\n"))
        StatLbl.Text       = "Скопировано " .. #logLines .. " событий"
        StatLbl.TextColor3 = Color3.fromRGB(100,180,255)
    end
end)

-- ============================================================

print("[Player Watcher] Loaded. Нажми ▶ WATCH ON")
