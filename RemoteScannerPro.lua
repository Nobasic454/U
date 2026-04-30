-- ============================================================
-- Remote Scanner Pro v1.0
-- Только RemoteEvent / RemoteFunction
-- Режимы: Fast / Quick / Scan / Deep
-- Просмотр кода ремоута (decompile / getscripts)
-- ============================================================

local Players      = game:GetService("Players")
local CoreGui      = game:GetService("CoreGui")
local LocalPlayer  = Players.LocalPlayer

-- ============================================================
-- УТИЛИТЫ
-- ============================================================

local function safeGet(t, k)
    local ok, v = pcall(function() return t[k] end)
    return ok and v or nil
end

-- Попытка получить исходник скрипта через decompile / getscriptbytecode
local function tryGetSource(remote)
    -- 1. Ищем Script / LocalScript внутри ремоута
    local src = nil
    pcall(function()
        for _, c in ipairs(remote:GetDescendants()) do
            local cls = safeGet(c, "ClassName")
            if cls == "LocalScript" or cls == "Script" or cls == "ModuleScript" then
                if decompile then
                    local ok, code = pcall(decompile, c)
                    if ok and type(code) == "string" and #code > 0 then
                        src = "-- [decompile] " .. c:GetFullName() .. "\n" .. code
                        return
                    end
                end
                if getscriptbytecode then
                    local ok2, bc = pcall(getscriptbytecode, c)
                    if ok2 and type(bc) == "string" then
                        src = "-- [bytecode len=" .. #bc .. "] " .. c:GetFullName()
                        return
                    end
                end
                src = "-- [script found, no decompile] " .. c:GetFullName()
                return
            end
        end
    end)
    if src then return src end

    -- 2. Ищем debug.getinfo на метаметодах
    pcall(function()
        local meta = getrawmetatable and getrawmetatable(remote)
        if not meta then return end
        local keys = {"__namecall", "__index", "__newindex", "__call"}
        for _, k in ipairs(keys) do
            local raw = rawget(meta, k)
            if raw and type(raw) == "function" then
                local info = debug.getinfo and debug.getinfo(raw, "S")
                if info and info.short_src and info.short_src ~= "[C]" then
                    src = "-- [metamethod hook: " .. k .. "]\n-- source: " .. info.short_src
                    if info.linedefined then
                        src = src .. "\n-- line: " .. info.linedefined
                    end
                    if decompile then
                        local ok, code = pcall(decompile, raw)
                        if ok and type(code) == "string" and #code > 0 then
                            src = src .. "\n\n" .. code
                        end
                    end
                    return
                end
            end
        end
    end)
    if src then return src end

    return "-- Нет доступного исходника\n-- Remote: " .. remote:GetFullName() .. "\n-- Class: " .. (safeGet(remote, "ClassName") or "?")
end

-- ============================================================
-- ЯДРО СКАНЕРА
-- ============================================================

-- Конфиги режимов сканирования
local SCAN_MODES = {
    Fast  = { depth = 2, checkMeta = false, metaKeys = {},                                                      label = "FAST",  color = Color3.fromRGB(80, 220, 80)   },
    Quick = { depth = 4, checkMeta = true,  metaKeys = {"__namecall", "__index"},                               label = "QUICK", color = Color3.fromRGB(80, 180, 255)  },
    Scan  = { depth = 6, checkMeta = true,  metaKeys = {"__namecall","__index","__newindex","__call","__len"},  label = "SCAN",  color = Color3.fromRGB(220, 180, 60)   },
    Deep  = { depth = 10, checkMeta = true, metaKeys = {                                                        label = "DEEP",  color = Color3.fromRGB(255, 80, 80)    },
        "__namecall","__index","__newindex","__call","__len",
        "__concat","__tostring","__eq","__lt","__le",
        "__add","__sub","__mul","__div","__mod",
        "__pow","__unm","__metatable",
    },
}
-- починим Deep (metaKeys внутри конструктора)
SCAN_MODES.Deep.metaKeys = {
    "__namecall","__index","__newindex","__call","__len",
    "__concat","__tostring","__eq","__lt","__le",
    "__add","__sub","__mul","__div","__mod",
    "__pow","__unm","__metatable",
}

local Scanner = {}

-- Основная функция сканирования с заданным режимом
function Scanner.run(modeName, onItem, onDone)
    local cfg = SCAN_MODES[modeName]
    if not cfg then onDone(0) return end

    local found   = 0
    local visited = {}

    -- Итеративный обход через очередь (быстрее рекурсии, нет stack overflow)
    local queue = { { inst = game, depth = 0 } }

    local function processChunk()
        local CHUNK = 200          -- обрабатываем N инстансов за один шаг
        local processed = 0

        while #queue > 0 and processed < CHUNK do
            local item  = table.remove(queue, 1)
            local inst  = item.inst
            local depth = item.depth
            processed   = processed + 1

            if depth > cfg.depth then goto continue end

            local id = tostring(inst)
            if visited[id] then goto continue end
            visited[id] = true

            local cls = safeGet(inst, "ClassName")
            if cls == "RemoteEvent" or cls == "RemoteFunction" then
                found = found + 1
                local entry = {
                    ref      = inst,
                    name     = inst:GetFullName(),
                    class    = cls,
                    hooks    = {},
                    hooked   = false,
                }

                -- Проверяем метаметоды
                if cfg.checkMeta then
                    pcall(function()
                        local meta = getrawmetatable and getrawmetatable(inst)
                        if not meta then return end
                        for _, key in ipairs(cfg.metaKeys) do
                            local raw = rawget(meta, key)
                            if raw and type(raw) == "function" then
                                local src = "?"
                                pcall(function()
                                    local i = debug.getinfo(raw, "S")
                                    src = i and i.short_src or "?"
                                end)
                                local isHooked = src ~= "[C]" and src ~= "?"
                                if isHooked then
                                    entry.hooked = true
                                    table.insert(entry.hooks, {
                                        key    = key,
                                        source = src,
                                        fn     = raw,
                                    })
                                end
                            end
                        end
                    end)
                end

                onItem(entry)
            end

            -- Добавляем детей в очередь
            if depth < cfg.depth then
                pcall(function()
                    for _, child in ipairs(inst:GetChildren()) do
                        table.insert(queue, { inst = child, depth = depth + 1 })
                    end
                end)
            end

            ::continue::
        end

        if #queue > 0 then
            -- Следующий чанк без зависания
            task.defer(processChunk)
        else
            onDone(found)
        end
    end

    task.defer(processChunk)
end

-- ============================================================
-- GUI
-- ============================================================

local existing = CoreGui:FindFirstChild("RemoteScannerPro")
if existing then existing:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name            = "RemoteScannerPro"
ScreenGui.ResetOnSpawn    = false
ScreenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent          = CoreGui

-- ===== ГЛАВНОЕ ОКНО =====
local Main = Instance.new("Frame")
Main.Name              = "Main"
Main.Size              = UDim2.new(0, 560, 0, 480)
Main.Position          = UDim2.new(0.5, -280, 0.5, -240)
Main.BackgroundColor3  = Color3.fromRGB(12, 12, 18)
Main.BorderSizePixel   = 0
Main.Active            = true
Main.Draggable         = true
Main.ClipsDescendants  = true
Main.Parent            = ScreenGui

do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = Main
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(70,60,110); s.Thickness = 1; s.Parent = Main
end

-- TitleBar
local TitleBar = Instance.new("Frame")
TitleBar.Size              = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3  = Color3.fromRGB(18, 18, 28)
TitleBar.BorderSizePixel   = 0
TitleBar.Parent            = Main
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = TitleBar
    local fix = Instance.new("Frame")
    fix.Size = UDim2.new(1,0,0,8); fix.Position = UDim2.new(0,0,1,-8)
    fix.BackgroundColor3 = Color3.fromRGB(18,18,28); fix.BorderSizePixel = 0; fix.Parent = TitleBar
end

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size               = UDim2.new(1,-80,1,0)
TitleLabel.Position           = UDim2.new(0,12,0,0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text               = "Remote Scanner Pro  |  Fast / Quick / Scan / Deep"
TitleLabel.TextColor3         = Color3.fromRGB(180,180,255)
TitleLabel.TextSize           = 13
TitleLabel.Font               = Enum.Font.GothamBold
TitleLabel.TextXAlignment     = Enum.TextXAlignment.Left
TitleLabel.Parent             = TitleBar

-- Кнопка закрыть
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size             = UDim2.new(0,28,0,28)
CloseBtn.Position         = UDim2.new(1,-32,0,4)
CloseBtn.BackgroundColor3 = Color3.fromRGB(180,50,50)
CloseBtn.Text             = "X"
CloseBtn.TextColor3       = Color3.new(1,1,1)
CloseBtn.TextSize         = 13
CloseBtn.Font             = Enum.Font.GothamBold
CloseBtn.BorderSizePixel  = 0
CloseBtn.Parent           = TitleBar
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = CloseBtn end
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

-- ===== КНОПКИ РЕЖИМОВ =====
local BtnBar = Instance.new("Frame")
BtnBar.Size             = UDim2.new(1,0,0,44)
BtnBar.Position         = UDim2.new(0,0,0,36)
BtnBar.BackgroundColor3 = Color3.fromRGB(16,16,24)
BtnBar.BorderSizePixel  = 0
BtnBar.Parent           = Main

local BtnLayout = Instance.new("UIListLayout")
BtnLayout.FillDirection  = Enum.FillDirection.Horizontal
BtnLayout.Padding        = UDim.new(0,6)
BtnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
BtnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
BtnLayout.Parent         = BtnBar

local BTNS = {
    { mode = "Fast",  label = "⚡ FAST",  color = Color3.fromRGB(40,140,40)  },
    { mode = "Quick", label = "🔍 QUICK", color = Color3.fromRGB(30,80,180)  },
    { mode = "Scan",  label = "📡 SCAN",  color = Color3.fromRGB(140,100,20) },
    { mode = "Deep",  label = "🧬 DEEP",  color = Color3.fromRGB(140,30,30)  },
}

-- Строка статуса
local StatusBar = Instance.new("Frame")
StatusBar.Size             = UDim2.new(1,0,0,26)
StatusBar.Position         = UDim2.new(0,0,0,80)
StatusBar.BackgroundColor3 = Color3.fromRGB(14,14,22)
StatusBar.BorderSizePixel  = 0
StatusBar.Parent           = Main

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size                  = UDim2.new(1,-12,1,0)
StatusLabel.Position              = UDim2.new(0,8,0,0)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text                  = "Выбери режим скана  —  кликни кнопку выше"
StatusLabel.TextColor3            = Color3.fromRGB(120,120,160)
StatusLabel.TextSize              = 11
StatusLabel.Font                  = Enum.Font.Gotham
StatusLabel.TextXAlignment        = Enum.TextXAlignment.Left
StatusLabel.Parent                = StatusBar

-- Счётчик
local CountLabel = Instance.new("TextLabel")
CountLabel.Size                   = UDim2.new(0,120,1,0)
CountLabel.Position               = UDim2.new(1,-124,0,0)
CountLabel.BackgroundTransparency = 1
CountLabel.Text                   = ""
CountLabel.TextColor3             = Color3.fromRGB(80,220,120)
CountLabel.TextSize               = 11
CountLabel.Font                   = Enum.Font.GothamBold
CountLabel.TextXAlignment         = Enum.TextXAlignment.Right
CountLabel.Parent                 = StatusBar

-- ===== СПИСОК РЕМОУТОВ =====
local ListBox = Instance.new("Frame")
ListBox.Size             = UDim2.new(1,-16,0,240)
ListBox.Position         = UDim2.new(0,8,0,112)
ListBox.BackgroundColor3 = Color3.fromRGB(10,10,16)
ListBox.BorderSizePixel  = 0
ListBox.ClipsDescendants = true
ListBox.Parent           = Main
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = ListBox end
do local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(40,40,70); s.Thickness = 1; s.Parent = ListBox end

local ListScroll = Instance.new("ScrollingFrame")
ListScroll.Size                  = UDim2.new(1,0,1,0)
ListScroll.BackgroundTransparency = 1
ListScroll.BorderSizePixel       = 0
ListScroll.ScrollBarThickness    = 4
ListScroll.ScrollBarImageColor3  = Color3.fromRGB(80,80,130)
ListScroll.CanvasSize            = UDim2.new(0,0,0,0)
ListScroll.Parent                = ListBox

local ListLayout = Instance.new("UIListLayout")
ListLayout.SortOrder  = Enum.SortOrder.LayoutOrder
ListLayout.Padding    = UDim.new(0,2)
ListLayout.Parent     = ListScroll

local ListPad = Instance.new("UIPadding")
ListPad.PaddingAll = UDim.new(0,4)
ListPad.Parent     = ListScroll

ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    ListScroll.CanvasSize = UDim2.new(0,0,0, ListLayout.AbsoluteContentSize.Y + 8)
end)

-- ===== КНОПКИ ДЕЙСТВИЙ =====
local ActionBar = Instance.new("Frame")
ActionBar.Size             = UDim2.new(1,-16,0,36)
ActionBar.Position         = UDim2.new(0,8,0,360)
ActionBar.BackgroundTransparency = 1
ActionBar.Parent           = Main

local ActLayout = Instance.new("UIListLayout")
ActLayout.FillDirection = Enum.FillDirection.Horizontal
ActLayout.Padding        = UDim.new(0,6)
ActLayout.Parent         = ActionBar

local function makeActionBtn(text, color)
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0,170,0,34)
    b.BackgroundColor3 = color
    b.Text             = text
    b.TextColor3       = Color3.new(1,1,1)
    b.TextSize         = 11
    b.Font             = Enum.Font.GothamBold
    b.BorderSizePixel  = 0
    b.Parent           = ActionBar
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = b
    return b
end

local ClearBtn  = makeActionBtn("🗑  Очистить список",      Color3.fromRGB(50,30,30))
local NukeBtn   = makeActionBtn("☢  Nuке хуки (найденные)", Color3.fromRGB(120,20,20))
local ExportBtn = makeActionBtn("📋 Копировать в буфер",     Color3.fromRGB(30,60,110))

-- ===== ОКНО ПРОСМОТРА КОДА =====
local CodeWin = Instance.new("Frame")
CodeWin.Name             = "CodeViewer"
CodeWin.Size             = UDim2.new(0,580,0,420)
CodeWin.Position         = UDim2.new(0.5,-290,0.5,-210)
CodeWin.BackgroundColor3 = Color3.fromRGB(8,8,14)
CodeWin.BorderSizePixel  = 0
CodeWin.Active           = true
CodeWin.Draggable        = true
CodeWin.Visible          = false
CodeWin.ZIndex           = 10
CodeWin.Parent           = ScreenGui
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = CodeWin
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(100,60,180); s.Thickness = 1; s.Parent = CodeWin
end

local CodeTitle = Instance.new("Frame")
CodeTitle.Size             = UDim2.new(1,0,0,32)
CodeTitle.BackgroundColor3 = Color3.fromRGB(20,14,34)
CodeTitle.BorderSizePixel  = 0
CodeTitle.Parent           = CodeWin
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = CodeTitle
    local fix = Instance.new("Frame"); fix.Size = UDim2.new(1,0,0,8); fix.Position = UDim2.new(0,0,1,-8)
    fix.BackgroundColor3 = Color3.fromRGB(20,14,34); fix.BorderSizePixel = 0; fix.Parent = CodeTitle
end

local CodeTitleLabel = Instance.new("TextLabel")
CodeTitleLabel.Size               = UDim2.new(1,-40,1,0)
CodeTitleLabel.Position           = UDim2.new(0,10,0,0)
CodeTitleLabel.BackgroundTransparency = 1
CodeTitleLabel.Text               = "Code Viewer"
CodeTitleLabel.TextColor3         = Color3.fromRGB(180,140,255)
CodeTitleLabel.TextSize           = 12
CodeTitleLabel.Font               = Enum.Font.GothamBold
CodeTitleLabel.TextXAlignment     = Enum.TextXAlignment.Left
CodeTitleLabel.Parent             = CodeTitle

local CodeCloseBtn = Instance.new("TextButton")
CodeCloseBtn.Size             = UDim2.new(0,26,0,26)
CodeCloseBtn.Position         = UDim2.new(1,-30,0,3)
CodeCloseBtn.BackgroundColor3 = Color3.fromRGB(160,40,40)
CodeCloseBtn.Text             = "X"
CodeCloseBtn.TextColor3       = Color3.new(1,1,1)
CodeCloseBtn.TextSize         = 11
CodeCloseBtn.Font             = Enum.Font.GothamBold
CodeCloseBtn.BorderSizePixel  = 0
CodeCloseBtn.Parent           = CodeTitle
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,5); c.Parent = CodeCloseBtn end
CodeCloseBtn.MouseButton1Click:Connect(function() CodeWin.Visible = false end)

local CodeScroll = Instance.new("ScrollingFrame")
CodeScroll.Size                  = UDim2.new(1,-8,1,-38)
CodeScroll.Position              = UDim2.new(0,4,0,34)
CodeScroll.BackgroundTransparency = 1
CodeScroll.BorderSizePixel       = 0
CodeScroll.ScrollBarThickness    = 4
CodeScroll.ScrollBarImageColor3  = Color3.fromRGB(100,60,200)
CodeScroll.CanvasSize            = UDim2.new(0,0,0,0)
CodeScroll.Parent                = CodeWin

local CodeText = Instance.new("TextLabel")
CodeText.Size                  = UDim2.new(1,0,0,0)
CodeText.BackgroundTransparency = 1
CodeText.TextColor3            = Color3.fromRGB(200,200,220)
CodeText.TextSize              = 11
CodeText.Font                  = Enum.Font.Code
CodeText.TextXAlignment        = Enum.TextXAlignment.Left
CodeText.TextYAlignment        = Enum.TextYAlignment.Top
CodeText.TextWrapped           = true
CodeText.RichText              = false
CodeText.Text                  = ""
CodeText.AutomaticSize         = Enum.AutomaticSize.Y
CodeText.Parent                = CodeScroll

CodeText:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    CodeScroll.CanvasSize = UDim2.new(0,0,0, CodeText.AbsoluteSize.Y + 10)
end)

local function showCode(remote)
    CodeTitleLabel.Text = "Code Viewer  —  " .. remote:GetFullName()
    CodeText.Text       = "-- Загружаю исходник..."
    CodeWin.Visible     = true
    task.defer(function()
        local src = tryGetSource(remote)
        CodeText.Text = src
    end)
end

-- ============================================================
-- РЕНДЕР СТРОКИ РЕМОУТА
-- ============================================================

local remoteEntries = {}   -- { entry }
local remoteCount   = 0

local function clearList()
    for _, c in ipairs(ListScroll:GetChildren()) do
        if c:IsA("Frame") or c:IsA("TextButton") then c:Destroy() end
    end
    remoteEntries = {}
    remoteCount   = 0
    CountLabel.Text = ""
end

local function addRemoteRow(entry)
    local Row = Instance.new("Frame")
    Row.Size             = UDim2.new(1,-4,0,22)
    Row.BackgroundColor3 = entry.hooked
        and Color3.fromRGB(50,16,16)
        or  Color3.fromRGB(18,22,18)
    Row.BorderSizePixel  = 0
    Row.Parent           = ListScroll
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = Row end

    -- Тег
    local Tag = Instance.new("TextLabel")
    Tag.Size               = UDim2.new(0,54,1,0)
    Tag.BackgroundTransparency = 1
    Tag.Text               = entry.hooked and " [HOOK]" or " [OK]  "
    Tag.TextColor3         = entry.hooked and Color3.fromRGB(255,90,70) or Color3.fromRGB(70,200,90)
    Tag.TextSize           = 10
    Tag.Font               = Enum.Font.Code
    Tag.TextXAlignment     = Enum.TextXAlignment.Left
    Tag.Parent             = Row

    -- Тип (RE/RF)
    local TypeTag = Instance.new("TextLabel")
    TypeTag.Size               = UDim2.new(0,28,1,0)
    TypeTag.Position           = UDim2.new(0,54,0,0)
    TypeTag.BackgroundTransparency = 1
    TypeTag.Text               = entry.class == "RemoteEvent" and "RE" or "RF"
    TypeTag.TextColor3         = entry.class == "RemoteEvent"
        and Color3.fromRGB(100,160,255)
        or  Color3.fromRGB(255,160,100)
    TypeTag.TextSize           = 10
    TypeTag.Font               = Enum.Font.GothamBold
    TypeTag.TextXAlignment     = Enum.TextXAlignment.Left
    TypeTag.Parent             = Row

    -- Имя
    local NameLabel = Instance.new("TextLabel")
    NameLabel.Size               = UDim2.new(1,-170,1,0)
    NameLabel.Position           = UDim2.new(0,84,0,0)
    NameLabel.BackgroundTransparency = 1
    NameLabel.Text               = entry.name
    NameLabel.TextColor3         = Color3.fromRGB(200,200,220)
    NameLabel.TextSize           = 10
    NameLabel.Font               = Enum.Font.Code
    NameLabel.TextXAlignment     = Enum.TextXAlignment.Left
    NameLabel.TextTruncate       = Enum.TextTruncate.AtEnd
    NameLabel.Parent             = Row

    -- Кнопка [CODE]
    local CodeBtn = Instance.new("TextButton")
    CodeBtn.Size             = UDim2.new(0,54,0,18)
    CodeBtn.Position         = UDim2.new(1,-120,0.5,-9)
    CodeBtn.BackgroundColor3 = Color3.fromRGB(60,40,100)
    CodeBtn.Text             = "< CODE >"
    CodeBtn.TextColor3       = Color3.fromRGB(200,160,255)
    CodeBtn.TextSize         = 9
    CodeBtn.Font             = Enum.Font.GothamBold
    CodeBtn.BorderSizePixel  = 0
    CodeBtn.Parent           = Row
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = CodeBtn end

    -- Кнопка [NUKE]
    local NukeBtnRow = Instance.new("TextButton")
    NukeBtnRow.Size             = UDim2.new(0,50,0,18)
    NukeBtnRow.Position         = UDim2.new(1,-60,0.5,-9)
    NukeBtnRow.BackgroundColor3 = entry.hooked and Color3.fromRGB(120,20,20) or Color3.fromRGB(30,30,30)
    NukeBtnRow.Text             = "NUKE"
    NukeBtnRow.TextColor3       = entry.hooked and Color3.fromRGB(255,120,100) or Color3.fromRGB(80,80,80)
    NukeBtnRow.TextSize         = 9
    NukeBtnRow.Font             = Enum.Font.GothamBold
    NukeBtnRow.BorderSizePixel  = 0
    NukeBtnRow.Active           = entry.hooked
    NukeBtnRow.Parent           = Row
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = NukeBtnRow end

    CodeBtn.MouseButton1Click:Connect(function()
        showCode(entry.ref)
    end)

    NukeBtnRow.MouseButton1Click:Connect(function()
        if not entry.hooked then return end
        pcall(function()
            local meta = getrawmetatable(entry.ref)
            if not meta then return end
            if setreadonly then pcall(setreadonly, meta, false) end
            for _, h in ipairs(entry.hooks) do
                pcall(rawset, meta, h.key, nil)
            end
            if setreadonly then pcall(setreadonly, meta, true) end
        end)
        entry.hooked = false
        entry.hooks  = {}
        Row.BackgroundColor3    = Color3.fromRGB(18,22,18)
        Tag.Text                = " [OK]  "
        Tag.TextColor3          = Color3.fromRGB(70,200,90)
        NukeBtnRow.BackgroundColor3 = Color3.fromRGB(30,30,30)
        NukeBtnRow.TextColor3       = Color3.fromRGB(80,80,80)
        NukeBtnRow.Active       = false
        StatusLabel.Text        = "Нукнули: " .. entry.name
        StatusLabel.TextColor3  = Color3.fromRGB(80,220,120)
    end)

    table.insert(remoteEntries, entry)
end

-- ============================================================
-- ЗАПУСК СКАНА
-- ============================================================

local scanning = false

local function runScan(modeName)
    if scanning then return end
    scanning = true

    clearList()
    local cfg = SCAN_MODES[modeName]
    StatusLabel.Text       = "[ " .. cfg.label .. " ] Сканирую..."
    StatusLabel.TextColor3 = cfg.color
    CountLabel.Text        = ""

    local startTime = os.clock()
    local total     = 0

    Scanner.run(modeName, function(entry)
        total = total + 1
        addRemoteRow(entry)
        CountLabel.Text = tostring(total) .. " ремоутов"
    end, function(count)
        local elapsed = string.format("%.2f", os.clock() - startTime)
        StatusLabel.Text = string.format(
            "[ %s ] Готово — %d ремоутов за %sс",
            cfg.label, count, elapsed
        )
        StatusLabel.TextColor3 = Color3.fromRGB(80, 220, 120)
        CountLabel.Text        = tostring(count) .. " ремоутов"
        scanning = false
    end)
end

-- ============================================================
-- КНОПКИ РЕЖИМОВ (создаём ПОСЛЕ функции runScan)
-- ============================================================

for _, info in ipairs(BTNS) do
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0,120,0,32)
    b.BackgroundColor3 = info.color
    b.Text             = info.label
    b.TextColor3       = Color3.new(1,1,1)
    b.TextSize         = 12
    b.Font             = Enum.Font.GothamBold
    b.BorderSizePixel  = 0
    b.Parent           = BtnBar
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = b end

    local mode = info.mode
    b.MouseButton1Click:Connect(function()
        runScan(mode)
    end)
end

-- ============================================================
-- КНОПКИ ДЕЙСТВИЙ
-- ============================================================

ClearBtn.MouseButton1Click:Connect(function()
    clearList()
    StatusLabel.Text       = "Список очищен"
    StatusLabel.TextColor3 = Color3.fromRGB(120,120,160)
end)

NukeBtn.MouseButton1Click:Connect(function()
    local nuked = 0
    for _, entry in ipairs(remoteEntries) do
        if entry.hooked then
            pcall(function()
                local meta = getrawmetatable(entry.ref)
                if not meta then return end
                if setreadonly then pcall(setreadonly, meta, false) end
                for _, h in ipairs(entry.hooks) do
                    pcall(rawset, meta, h.key, nil)
                end
                if setreadonly then pcall(setreadonly, meta, true) end
            end)
            nuked = nuked + 1
            entry.hooked = false
            entry.hooks  = {}
        end
    end
    StatusLabel.Text       = string.format("Нукнуто %d хуков", nuked)
    StatusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
end)

ExportBtn.MouseButton1Click:Connect(function()
    local lines = {}
    for _, entry in ipairs(remoteEntries) do
        local tag = entry.hooked and "[HOOK]" or "[ok]"
        table.insert(lines, tag .. " " .. entry.name)
        for _, h in ipairs(entry.hooks) do
            table.insert(lines, "  -> " .. h.key .. " @ " .. h.source)
        end
    end
    local text = table.concat(lines, "\n")
    if setclipboard then
        pcall(setclipboard, text)
        StatusLabel.Text       = "Скопировано в буфер (" .. #remoteEntries .. " ремоутов)"
        StatusLabel.TextColor3 = Color3.fromRGB(100,180,255)
    else
        StatusLabel.Text       = "setclipboard недоступен в этом экзекуторе"
        StatusLabel.TextColor3 = Color3.fromRGB(255,160,60)
    end
end)

-- ============================================================
-- АВТО-ЗАПУСК
-- ============================================================

print("[Remote Scanner Pro] Loaded. GUI открыт.")
-- Авто-запуск Quick скана при старте
task.delay(0.5, function()
    runScan("Quick")
end)
