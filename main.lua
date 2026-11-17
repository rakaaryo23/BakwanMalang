--[[
GROWBLOX HUB UI FOUNDATION
UI framework only - belum berisi logic Auto PUT / BREAK.
Designed for modular feature tabs and future feature modules.

Executor: requires an executor that can create ScreenGui under gethui() or CoreGui.
]]

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[GrowBlox Hub] LocalPlayer tidak ditemukan.")
    return
end

-- Remove previous UI instance
local parent
if type(gethui) == "function" then
    local ok, result = pcall(gethui)
    if ok and result then parent = result end
end
parent = parent or CoreGui

local old = parent:FindFirstChild("GrowBloxHubUI")
if old then old:Destroy() end

-- Theme
local C = {
    background = Color3.fromRGB(250, 218, 226),
    surface = Color3.fromRGB(255, 232, 237),
    panel = Color3.fromRGB(238, 190, 203),
    panelDark = Color3.fromRGB(224, 166, 184),
    accent = Color3.fromRGB(171, 91, 119),
    accentDark = Color3.fromRGB(116, 55, 78),
    text = Color3.fromRGB(75, 42, 56),
    muted = Color3.fromRGB(137, 91, 108),
    white = Color3.fromRGB(255, 248, 250),
    green = Color3.fromRGB(75, 143, 103),
    red = Color3.fromRGB(174, 75, 87),
}

local function corner(obj, radius)
    local u = Instance.new("UICorner")
    u.CornerRadius = UDim.new(0, radius or 10)
    u.Parent = obj
    return u
end

local function stroke(obj, color, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or C.panelDark
    s.Transparency = transparency or 0.25
    s.Thickness = 1
    s.Parent = obj
    return s
end

local function make(className, props, parentObject)
    local obj = Instance.new(className)
    for k, v in pairs(props or {}) do
        obj[k] = v
    end
    obj.Parent = parentObject
    return obj
end

local gui = make("ScreenGui", {
    Name = "GrowBloxHubUI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, parent)

local main = make("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(0.88, 0, 0.78, 0),
    BackgroundColor3 = C.background,
    BorderSizePixel = 0,
    Active = true,
}, gui)
main.Size = UDim2.fromOffset(900, 570)
main.Position = UDim2.new(0.5, 0, 0.5, 0)
main.ClipsDescendants = true
corner(main, 16)
stroke(main, C.accent, 0.2)

local sizeLimit = make("UISizeConstraint", {
    MinSize = Vector2.new(560, 390),
    MaxSize = Vector2.new(1120, 760),
}, main)

-- Drag window from header
local dragging, dragStart, startPos
local header = make("Frame", {
    Name = "Header",
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, 0, 0, 58),
    BackgroundColor3 = C.surface,
    BorderSizePixel = 0,
}, main)

local title = make("TextLabel", {
    Name = "Title",
    Position = UDim2.fromOffset(22, 0),
    Size = UDim2.new(0.55, 0, 1, 0),
    BackgroundTransparency = 1,
    Text = "GrowBlox Hub",
    TextColor3 = C.text,
    Font = Enum.Font.GothamBold,
    TextSize = 21,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local subtitle = make("TextLabel", {
    Position = UDim2.fromOffset(168, 2),
    Size = UDim2.fromOffset(220, 54),
    BackgroundTransparency = 1,
    Text = "MODULAR CONTROL PANEL",
    TextColor3 = C.muted,
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local minimize = make("TextButton", {
    Name = "Minimize",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -18, 0.5, 0),
    Size = UDim2.fromOffset(42, 34),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0,
    Text = "—",
    TextColor3 = C.text,
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    AutoButtonColor = true,
}, header)
corner(minimize, 9)

header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

game:GetService("UserInputService").InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

-- Horizontal tab navigation
local nav = make("ScrollingFrame", {
    Name = "TabNavigation",
    Position = UDim2.fromOffset(14, 68),
    Size = UDim2.new(1, -28, 0, 48),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = C.accent,
    ScrollingDirection = Enum.ScrollingDirection.X,
    CanvasSize = UDim2.fromOffset(0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.X,
}, main)
corner(nav, 11)

local navPadding = make("UIPadding", {
    PaddingLeft = UDim.new(0, 7),
    PaddingRight = UDim.new(0, 7),
    PaddingTop = UDim.new(0, 6),
    PaddingBottom = UDim.new(0, 6),
}, nav)

local navLayout = make("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 6),
}, nav)

-- Main content and right status column
local contentArea = make("Frame", {
    Name = "ContentArea",
    Position = UDim2.fromOffset(14, 126),
    Size = UDim2.new(1, -300, 1, -142),
    BackgroundColor3 = C.surface,
    BorderSizePixel = 0,
}, main)
corner(contentArea, 12)
stroke(contentArea, C.panelDark, 0.5)

local contentTitle = make("TextLabel", {
    Position = UDim2.fromOffset(18, 12),
    Size = UDim2.new(1, -36, 0, 28),
    BackgroundTransparency = 1,
    Text = "Home",
    TextColor3 = C.text,
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextXAlignment = Enum.TextXAlignment.Left,
}, contentArea)

local contentSubtitle = make("TextLabel", {
    Position = UDim2.fromOffset(18, 41),
    Size = UDim2.new(1, -36, 0, 22),
    BackgroundTransparency = 1,
    Text = "Pilih tab untuk membuka modul.",
    TextColor3 = C.muted,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, contentArea)

local pageHolder = make("Frame", {
    Name = "PageHolder",
    Position = UDim2.fromOffset(14, 72),
    Size = UDim2.new(1, -28, 1, -86),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
}, contentArea)

local statusPanel = make("Frame", {
    Name = "StatusPanel",
    Position = UDim2.new(1, -272, 0, 126),
    Size = UDim2.new(0, 258, 1, -142),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0,
}, main)
corner(statusPanel, 12)
stroke(statusPanel, C.panelDark, 0.45)

local statusHeader = make("TextLabel", {
    Position = UDim2.fromOffset(16, 12),
    Size = UDim2.new(1, -32, 0, 27),
    BackgroundTransparency = 1,
    Text = "SESSION STATUS",
    TextColor3 = C.text,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left,
}, statusPanel)

local statusText = make("TextLabel", {
    Name = "StatusText",
    Position = UDim2.fromOffset(16, 48),
    Size = UDim2.new(1, -32, 1, -62),
    BackgroundTransparency = 1,
    Text = "Mengambil informasi sesi...",
    TextColor3 = C.text,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextWrapped = true,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextXAlignment = Enum.TextXAlignment.Left,
}, statusPanel)

-- Footer
local footer = make("TextLabel", {
    Position = UDim2.new(0, 14, 1, -23),
    Size = UDim2.new(1, -28, 0, 16),
    BackgroundTransparency = 1,
    Text = "GrowBlox Hub  •  Modular UI Foundation",
    TextColor3 = C.muted,
    Font = Enum.Font.Gotham,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Center,
}, main)

-- Page and tab system
local pages = {}
local tabButtons = {}
local selectedTab = nil
local api = {}

local function createPage(name)
    local page = make("ScrollingFrame", {
        Name = name .. "Page",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = C.accent,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }, pageHolder)
    make("UIPadding", {
        PaddingRight = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
    }, page)
    make("UIListLayout", {
        Padding = UDim.new(0, 9),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, page)
    return page
end

local function addInfoCard(page, heading, description)
    local card = make("Frame", {
        Size = UDim2.new(1, -4, 0, 82),
        BackgroundColor3 = C.white,
        BorderSizePixel = 0,
    }, page)
    corner(card, 9)
    make("TextLabel", {
        Position = UDim2.fromOffset(13, 9),
        Size = UDim2.new(1, -26, 0, 22),
        BackgroundTransparency = 1,
        Text = heading,
        TextColor3 = C.text,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    make("TextLabel", {
        Position = UDim2.fromOffset(13, 33),
        Size = UDim2.new(1, -26, 0, 40),
        BackgroundTransparency = 1,
        Text = description,
        TextColor3 = C.muted,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, card)
    return card
end

function api.RegisterTab(name, description, buildCallback)
    assert(type(name) == "string" and name ~= "", "Nama tab wajib diisi.")
    if pages[name] then
        warn("[GrowBlox Hub] Tab sudah terdaftar: " .. name)
        return pages[name]
    end

    local page = createPage(name)
    pages[name] = {
        page = page,
        description = description or "",
        build = buildCallback,
    }

    local tab = make("TextButton", {
        Name = name .. "Tab",
        Size = UDim2.fromOffset(math.max(112, #name * 9 + 28), 34),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
        Text = name,
        TextColor3 = C.text,
        Font = Enum.Font.GothamSemibold,
        TextSize = 11,
        AutoButtonColor = true,
        LayoutOrder = #tabButtons + 1,
    }, nav)
    corner(tab, 8)
    tabButtons[name] = tab

    tab.Activated:Connect(function()
        api.SelectTab(name)
    end)

    if type(buildCallback) == "function" then
        local ok, err = pcall(buildCallback, page, api)
        if not ok then
            warn("[GrowBlox Hub] Gagal membangun tab " .. name .. ": " .. tostring(err))
        end
    end

    if not selectedTab then
        api.SelectTab(name)
    end
    return page
end

function api.SelectTab(name)
    if not pages[name] then return false end
    selectedTab = name
    for tabName, data in pairs(pages) do
        data.page.Visible = tabName == name
        local button = tabButtons[tabName]
        if button then
            button.BackgroundColor3 = tabName == name and C.accent or C.surface
            button.TextColor3 = tabName == name and C.white or C.text
        end
    end
    contentTitle.Text = name
    contentSubtitle.Text = pages[name].description
    return true
end

function api.SetStatus(text)
    statusText.Text = tostring(text)
end

function api.AddInfoCard(page, heading, description)
    return addInfoCard(page, heading, description)
end

function api.GetGui()
    return gui
end

function api.GetMain()
    return main
end

-- Default pages
api.RegisterTab("Home", "Ringkasan sesi dan informasi GrowBlox.", function(page)
    addInfoCard(page, "UI Foundation siap", "Ini adalah kerangka UI. Modul Auto PUT & BREAK akan dipindahkan ke tab tersendiri pada tahap berikutnya.")
    addInfoCard(page, "Sistem modular", "Setiap fitur akan memiliki bagian kode sendiri. Penambahan tab baru tidak perlu mengubah sistem navigasi utama.")
    addInfoCard(page, "Navigasi", "Jika tab lebih banyak daripada lebar panel, geser bar navigasi ke kiri atau kanan.")
end)

api.RegisterTab("Auto PUT & BREAK", "Modul ini akan diintegrasikan setelah UI dasar disetujui.", function(page)
    addInfoCard(page, "Belum diintegrasikan", "Tempat untuk kontrol LOCK SELECTED, SCAN, PREVIEW, START, STOP, dan pengaturan delay APB V4.")
end)

api.RegisterTab("Auto Farm", "Slot untuk modul Auto Farm.", function(page)
    addInfoCard(page, "Auto Farm", "Modul belum dipasang.")
end)

api.RegisterTab("Auto Clear", "Slot untuk modul Auto Clear.", function(page)
    addInfoCard(page, "Auto Clear", "Modul belum dipasang.")
end)

api.RegisterTab("Settings", "Pengaturan tampilan dan informasi sesi.", function(page)
    addInfoCard(page, "Informasi", "Nama akun, UserId, PlaceId, JobId, serta data world akan ditampilkan pada panel status.")
end)

-- Account / game session integration
local function updateSession()
    local accountName = LocalPlayer.Name or "?"
    local displayName = LocalPlayer.DisplayName or "?"
    local userId = tostring(LocalPlayer.UserId or "?")
    local placeId = tostring(game.PlaceId or "?")
    local jobId = tostring(game.JobId or "")
    if jobId == "" then jobId = "(belum tersedia)" end

    statusText.Text = table.concat({
        "ACCOUNT",
        accountName,
        "Display: " .. displayName,
        "UserId: " .. userId,
        "",
        "GAME SESSION",
        "PlaceId: " .. placeId,
        "JobId: " .. jobId,
        "",
        "WORLD",
        "Menunggu modul pembaca World.",
        "",
        "STATUS",
        "UI aktif",
    }, "\n")
end
updateSession()

-- Minimize / restore
local minimized = false
minimize.Activated:Connect(function()
    minimized = not minimized
    nav.Visible = not minimized
    contentArea.Visible = not minimized
    statusPanel.Visible = not minimized
    footer.Visible = not minimized
    main.Size = minimized and UDim2.fromOffset(300, 58) or UDim2.fromOffset(900, 570)
    minimize.Text = minimized and "+" or "—"
end)

-- Expose a small global bridge for future feature modules.
-- Example: _G.GrowBloxHub.RegisterTab("New Feature", "Description", function(page, ui) ... end)
_G.GrowBloxHub = api

print("[GrowBlox Hub] UI Foundation loaded.")
