--[[
GROWBLOX HUB - UI FOUNDATION OPTIMIZED
UI dasar saja. Belum ada fungsi game / Auto PUT / BREAK.
Tab contoh hanya "Menu 1" dan "Menu 2".
]]

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[GrowBlox Hub] LocalPlayer tidak ditemukan.")
    return
end

--==================================================
-- [01] GUI PARENT
--==================================================

local guiParent
if type(gethui) == "function" then
    local ok, result = pcall(gethui)
    if ok and result then
        guiParent = result
    end
end
guiParent = guiParent or CoreGui

-- Shut down the previous copy before creating a new one.
local previousHub = _G.GrowBloxHub
if type(previousHub) == "table" and type(previousHub.Close) == "function" then
    pcall(previousHub.Close)
end

local oldGui = guiParent:FindFirstChild("GrowBloxHubUI")
if oldGui then
    oldGui:Destroy()
end

--==================================================
-- [02] THEME
--==================================================

local Theme = {
    Background = Color3.fromRGB(250, 220, 228),
    Header = Color3.fromRGB(255, 235, 239),
    Panel = Color3.fromRGB(239, 194, 207),
    PanelDark = Color3.fromRGB(222, 164, 183),
    Accent = Color3.fromRGB(171, 91, 119),
    Text = Color3.fromRGB(76, 43, 57),
    Muted = Color3.fromRGB(139, 96, 111),
    White = Color3.fromRGB(255, 249, 251),
}

--==================================================
-- [03] UI HELPERS
--==================================================

local function Create(className, properties, parent)
    local object = Instance.new(className)
    for property, value in pairs(properties or {}) do
        object[property] = value
    end
    object.Parent = parent
    return object
end

local function AddCorner(object, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 9)
    corner.Parent = object
    return corner
end

local function AddStroke(object, color, transparency)
    local outline = Instance.new("UIStroke")
    outline.Color = color or Theme.PanelDark
    outline.Transparency = transparency or 0.25
    outline.Thickness = 1
    outline.Parent = object
    return outline
end

--==================================================
-- [04] ROOT WINDOW
--==================================================

local ScreenGui = Create("ScreenGui", {
    Name = "GrowBloxHubUI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent)

local Main = Create("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(600, 300),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Active = true,
}, ScreenGui)
AddCorner(Main, 15)
AddStroke(Main, Theme.Accent, 0.2)

-- Keep the window compact on different screen sizes.
Create("UISizeConstraint", {
    -- Allow the minimized window to shrink to the small square button.
    MinSize = Vector2.new(34, 34),
    MaxSize = Vector2.new(900, 620),
}, Main)

--==================================================
-- [05] HEADER
--==================================================

local Header = Create("Frame", {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, 52),
    BackgroundColor3 = Theme.Header,
    BorderSizePixel = 0,
    Active = true,
}, Main)

local Title = Create("TextLabel", {
    Position = UDim2.fromOffset(18, 0),
    Size = UDim2.new(1, -150, 1, 0),
    BackgroundTransparency = 1,
    Text = "GrowBlox Hub",
    TextColor3 = Theme.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 19,
    TextXAlignment = Enum.TextXAlignment.Left,
}, Header)

local MinimizeButton = Create("TextButton", {
    Name = "MinimizeButton",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -12, 0.5, 0),
    Size = UDim2.fromOffset(38, 32),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    Text = "—",
    TextColor3 = Theme.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    AutoButtonColor = true,
}, Header)
AddCorner(MinimizeButton, 8)

local CloseButton = Create("TextButton", {
    Name = "CloseButton",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -58, 0.5, 0),
    Size = UDim2.fromOffset(38, 32),
    BackgroundColor3 = Color3.fromRGB(205, 112, 132),
    BorderSizePixel = 0,
    Text = "X",
    TextColor3 = Theme.White,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    AutoButtonColor = true,
}, Header)
AddCorner(CloseButton, 8)

-- Shared lifecycle state, declared before input callbacks.
local IsClosed = false
local CleanupCallbacks = {}

--==================================================
-- [06] DRAG WINDOW
-- Header + tiga sisi window. Drag handles memakai TextButton
-- transparan dengan ZIndex tinggi agar tidak tertutup konten.
--==================================================

local IsDragging = false
local DragStart = nil
local StartPosition = nil
local ActiveTouch = nil

local function BeginWindowDrag(input)
    if IsClosed then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    IsDragging = true
    ActiveTouch = input.UserInputType == Enum.UserInputType.Touch and input or nil
    DragStart = input.Position
    StartPosition = Main.Position
end

Header.InputBegan:Connect(BeginWindowDrag)

local DragBorderSize = 16

local function CreateDragHandle(name, position, size)
    local handle = Create("TextButton", {
        Name = name,
        Position = position,
        Size = size,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Active = true,
        Selectable = false,
        ZIndex = 1000,
    }, Main)

    handle.InputBegan:Connect(BeginWindowDrag)
end

CreateDragHandle(
    "LeftDragHandle",
    UDim2.fromOffset(0, 52),
    UDim2.new(0, DragBorderSize, 1, -52)
)

CreateDragHandle(
    "RightDragHandle",
    UDim2.new(1, -DragBorderSize, 0, 52),
    UDim2.new(0, DragBorderSize, 1, -52)
)

CreateDragHandle(
    "BottomDragHandle",
    UDim2.new(0, 0, 1, -DragBorderSize),
    UDim2.new(1, 0, 0, DragBorderSize)
)

-- One global movement listener and one release listener.
-- No new global connections are created on each drag attempt.
local DragInputConnection = UserInputService.InputChanged:Connect(function(input)
    if IsClosed or not IsDragging then return end

    local isMouseMove = input.UserInputType == Enum.UserInputType.MouseMovement
    local isTouchMove = ActiveTouch ~= nil
        and input.UserInputType == Enum.UserInputType.Touch

    if isMouseMove or isTouchMove then
        local delta = input.Position - DragStart
        Main.Position = UDim2.new(
            StartPosition.X.Scale,
            StartPosition.X.Offset + delta.X,
            StartPosition.Y.Scale,
            StartPosition.Y.Offset + delta.Y
        )
    end
end)

local DragEndConnection = UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or (ActiveTouch ~= nil and input == ActiveTouch) then
        IsDragging = false
        ActiveTouch = nil
    end
end)

-- [07] BODY CONTAINER
--==================================================

local Body = Create("Frame", {
    Name = "Body",
    Position = UDim2.fromOffset(12, 62),
    Size = UDim2.new(1, -24, 1, -74),
    BackgroundTransparency = 1,
}, Main)

--==================================================
-- [08] HORIZONTAL TAB BAR
--==================================================

local TabBar = Create("ScrollingFrame", {
    Name = "TabBar",
    Size = UDim2.new(1, 0, 0, 42),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.Accent,
    ScrollingDirection = Enum.ScrollingDirection.X,
    CanvasSize = UDim2.fromOffset(0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.X,
}, Body)
AddCorner(TabBar, 9)

Create("UIPadding", {
    PaddingLeft = UDim.new(0, 6),
    PaddingRight = UDim.new(0, 6),
    PaddingTop = UDim.new(0, 5),
    PaddingBottom = UDim.new(0, 5),
}, TabBar)

Create("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 6),
}, TabBar)

--==================================================
-- [09] PAGE DISPLAY
--==================================================

local PageFrame = Create("Frame", {
    Name = "PageFrame",
    Position = UDim2.fromOffset(0, 52),
    Size = UDim2.new(1, 0, 1, -52),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, Body)
AddCorner(PageFrame, 10)
AddStroke(PageFrame, Theme.PanelDark, 0.5)

--==================================================
-- [10] TAB SYSTEM
--==================================================

local Tabs = {}
local SelectedTab = nil
local TabOrder = {}

local Hub = {}

--==================================================
-- [10A] LIFECYCLE / CLEANUP REGISTRY
-- Setiap modul fitur wajib mendaftarkan cleanup agar prosesnya
-- ikut dihentikan saat tombol CLOSE ditekan.
--==================================================

function Hub.IsClosing()
    return IsClosed
end

function Hub.RegisterCleanup(callback)
    assert(type(callback) == "function", "Cleanup harus berupa function.")

    if IsClosed then
        pcall(callback)
        return
    end

    table.insert(CleanupCallbacks, callback)
end

local function RunAllCleanups()
    if IsClosed then
        return
    end

    IsClosed = true

    -- Jalankan cleanup dalam urutan terbalik (terakhir didaftarkan,
    -- pertama dihentikan), agar modul yang bergantung pada modul lain aman.
    for index = #CleanupCallbacks, 1, -1 do
        local callback = CleanupCallbacks[index]
        local ok, err = pcall(callback)
        if not ok then
            warn("[GrowBlox Hub] Cleanup error: " .. tostring(err))
        end
    end

    table.clear(CleanupCallbacks)
end

function Hub.RegisterTab(tabName, buildFunction)
    assert(type(tabName) == "string" and tabName ~= "", "Tab name is required.")

    if Tabs[tabName] then
        warn("[GrowBlox Hub] Tab already exists: " .. tabName)
        return Tabs[tabName].Page
    end

    local Page = Create("ScrollingFrame", {
        Name = tabName .. "Page",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.Accent,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }, PageFrame)

    Create("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
    }, Page)

    local TabButton = Create("TextButton", {
        Name = tabName .. "Button",
        Size = UDim2.fromOffset(math.max(100, #tabName * 9 + 26), 30),
        BackgroundColor3 = Theme.Header,
        BorderSizePixel = 0,
        Text = tabName,
        TextColor3 = Theme.Text,
        Font = Enum.Font.GothamSemibold,
        TextSize = 11,
        AutoButtonColor = true,
        LayoutOrder = #TabOrder + 1,
    }, TabBar)
    AddCorner(TabButton, 7)

    Tabs[tabName] = {
        Page = Page,
        Button = TabButton,
    }
    table.insert(TabOrder, tabName)

    TabButton.Activated:Connect(function()
        Hub.SelectTab(tabName)
    end)

    if type(buildFunction) == "function" then
        local ok, err = pcall(buildFunction, Page, Hub)
        if not ok then
            warn("[GrowBlox Hub] Error building " .. tabName .. ": " .. tostring(err))
        end
    end

    if not SelectedTab then
        Hub.SelectTab(tabName)
    end

    return Page
end

function Hub.SelectTab(tabName)
    if not Tabs[tabName] then
        return false
    end

    SelectedTab = tabName

    for name, data in pairs(Tabs) do
        local active = name == tabName
        data.Page.Visible = active
        data.Button.BackgroundColor3 = active and Theme.Accent or Theme.Header
        data.Button.TextColor3 = active and Theme.White or Theme.Text
    end

    return true
end

function Hub.GetPage(tabName)
    return Tabs[tabName] and Tabs[tabName].Page or nil
end

function Hub.GetWindow()
    return Main
end

function Hub.GetGui()
    return ScreenGui
end

--==================================================
-- [11] SAMPLE TABS
-- Placeholder only. Replace these blocks when adding real features.
--==================================================


--==================================================
-- MODULE: AUTO PUT + BREAK V4
--==================================================

Hub.RegisterTab("Auto PUT + BREAK", function(page, Hub)

    --==================================================
    -- [A] CONFIGURATION
    --==================================================

    local CFG = {
        PutDelay = 80,
        BreakDelay = 140,
        BreakStartDelay = 150,
        CycleDelay = 150,

        MinDelay = 0,
        MaxDelay = 10000,

        GridColumns = 5,
        GridRows = 3,
    }

    --==================================================
    -- [B] VARIABLES
    --==================================================

    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer

    local running = false
    local destroyed = false

    local confirmedId = nil

    local refs = {
        Inv = nil,
        World = nil,
        State = nil,
        SetTile = nil,
        Hit = nil,
    }

    local enabled = {}
    local connections = {}
    local popup = nil

    local function track(connection)
        table.insert(connections, connection)
        return connection
    end

    --==================================================
    -- [C] THEME / UI HELPERS
    --==================================================

    local Theme = {
        Background = Color3.fromRGB(250, 220, 228),
        Panel = Color3.fromRGB(239, 194, 207),
        PanelDark = Color3.fromRGB(222, 164, 183),
        Accent = Color3.fromRGB(171, 91, 119),
        Text = Color3.fromRGB(76, 43, 57),
        Muted = Color3.fromRGB(139, 96, 111),
        White = Color3.fromRGB(255, 249, 251),
        Green = Color3.fromRGB(55, 140, 90),
        Red = Color3.fromRGB(180, 65, 75),
    }

    local function create(className, properties, parent)
        local object = Instance.new(className)

        for property, value in pairs(properties or {}) do
            object[property] = value
        end

        object.Parent = parent
        return object
    end

    local function corner(object, radius)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, radius or 7)
        c.Parent = object
        return c
    end

    local function label(text, height, parent)
        return create("TextLabel", {
            Size = UDim2.new(1, 0, 0, height or 25),
            BackgroundTransparency = 1,
            Text = text or "",
            TextColor3 = Theme.Text,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
        }, parent or page)
    end

    local function button(text, height, parent, color)
        local b = create("TextButton", {
            Size = UDim2.new(1, 0, 0, height or 32),
            BackgroundColor3 = color or Theme.Accent,
            BorderSizePixel = 0,
            Text = text,
            TextColor3 = Theme.White,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            AutoButtonColor = true,
        }, parent or page)

        corner(b, 7)
        return b
    end

    local function textbox(value, parent)
        local box = create("TextBox", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            Text = tostring(value),
            PlaceholderText = "Masukkan delay (ms)",
            TextColor3 = Theme.Text,
            PlaceholderColor3 = Theme.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            ClearTextOnFocus = false,
        }, parent or page)

        corner(box, 6)
        return box
    end

    local function report(message)
        if destroyed then return end

        statusLabel.Text = "Status: " .. tostring(message)
        print("[APB]", message)
    end

    --==================================================
    -- [D] MAIN UI
    --==================================================

    local layout = create("UIListLayout", {
        Padding = UDim.new(0, 7),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, page)

    local statusLabel = label("Status: menyiapkan scan...", 34)
    statusLabel.LayoutOrder = 1

    local selectedLabel = label(
        "Inventory selected: belum terbaca", 28
    )
    selectedLabel.LayoutOrder = 2

    local areaInfo = label(
        "Area target: 5 x 3 | YOU berada di tengah baris bawah",
        25
    )
    areaInfo.LayoutOrder = 3

    local tileButton = button("PILIH TILE  |  14 TARGET AKTIF", 34)
    tileButton.LayoutOrder = 4

    local scanButton = button(
        "SCAN ULANG", 32, page, Theme.PanelDark
    )
    scanButton.TextColor3 = Theme.Text
    scanButton.LayoutOrder = 5

    local lockButton = button("LOCK SELECTED", 32)
    lockButton.LayoutOrder = 6

    local previewButton = button(
        "PREVIEW TARGET", 32, page, Theme.PanelDark
    )
    previewButton.TextColor3 = Theme.Text
    previewButton.LayoutOrder = 7

    local startButton = button(
        "START PUT → BREAK LOOP", 36, page, Theme.Green
    )
    startButton.LayoutOrder = 8

    local stopButton = button("STOP", 32, page, Theme.Red)
    stopButton.LayoutOrder = 9

    --==================================================
    -- [E] DELAY SETTINGS
    --==================================================

    local settingsButton = button(
        "PENGATURAN DELAY  ▼", 30, page, Theme.PanelDark
    )
    settingsButton.TextColor3 = Theme.Text
    settingsButton.LayoutOrder = 10

    local settingsFrame = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        Visible = false,
        LayoutOrder = 11,
    }, page)

    corner(settingsFrame, 8)

    local settingsPadding = create("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }, settingsFrame)

    local settingsLayout = create("UIListLayout", {
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, settingsFrame)

    local function delaySetting(caption, value)
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, 48),
            BackgroundTransparency = 1,
        }, settingsFrame)

        create("TextLabel", {
            Size = UDim2.new(0.55, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = caption,
            TextColor3 = Theme.Text,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)

        local box = create("TextBox", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0.4, 0, 0, 30),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            Text = tostring(value),
            TextColor3 = Theme.Text,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            ClearTextOnFocus = false,
        }, row)

        corner(box, 6)
        return box
    end

    local putDelayBox = delaySetting(
        "Jeda antar PUT (ms)", CFG.PutDelay
    )

    local breakDelayBox = delaySetting(
        "Jeda antar HIT BREAK (ms)", CFG.BreakDelay
    )

    local breakStartBox = delaySetting(
        "Jeda awal BREAK (ms)", CFG.BreakStartDelay
    )

    local cycleDelayBox = delaySetting(
        "Jeda antar siklus (ms)", CFG.CycleDelay
    )

    track(settingsButton.Activated:Connect(function()
        settingsFrame.Visible = not settingsFrame.Visible
        settingsButton.Text = settingsFrame.Visible
            and "PENGATURAN DELAY  ▲"
            or "PENGATURAN DELAY  ▼"
    end))

    --==================================================
    -- [F] TILE SELECT POPUP
    --==================================================

    local function activeTileCount()
        local count = 0

        for dy = -2, 0 do
            for dx = -2, 2 do
                if not (dx == 0 and dy == 0) then
                    if enabled[dx .. "," .. dy] ~= false then
                        count += 1
                    end
                end
            end
        end

        return count
    end

    local function updateTileButton()
        tileButton.Text = (
            "PILIH TILE  |  %d TARGET AKTIF"
        ):format(activeTileCount())
    end

    local function closePopup()
        if popup then
            popup:Destroy()
            popup = nil
        end
    end

    local function openPopup()
        if destroyed or popup then return end

        popup = create("Frame", {
            Name = "TilePopup",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(290, 265),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            ZIndex = 50,
        }, Hub.GetGui())

        corner(popup, 10)

        local popupTitle = create("TextLabel", {
            Position = UDim2.fromOffset(10, 5),
            Size = UDim2.new(1, -55, 0, 30),
            BackgroundTransparency = 1,
            Text = "PILIH TILE TARGET",
            TextColor3 = Theme.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 51,
        }, popup)

        local close = create("TextButton", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -8, 0, 7),
            Size = UDim2.fromOffset(30, 27),
            BackgroundColor3 = Theme.Red,
            BorderSizePixel = 0,
            Text = "X",
            TextColor3 = Theme.White,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            ZIndex = 51,
        }, popup)

        corner(close, 6)

        local grid = create("Frame", {
            Position = UDim2.fromOffset(18, 45),
            Size = UDim2.fromOffset(254, 158),
            BackgroundTransparency = 1,
            ZIndex = 51,
        }, popup)

        local gridLayout = create("UIGridLayout", {
            CellSize = UDim2.fromOffset(48, 48),
            CellPadding = UDim2.fromOffset(3, 3),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, grid)

        for dy = -2, 0 do
            for dx = -2, 2 do
                local b = create("TextButton", {
                    BackgroundColor3 = Theme.Green,
                    BorderSizePixel = 0,
                    Text = "",
                    TextColor3 = Theme.White,
                    Font = Enum.Font.GothamBold,
                    TextSize = 10,
                    ZIndex = 52,
                }, grid)

                corner(b, 6)

                if dx == 0 and dy == 0 then
                    b.Text = "YOU"
                    b.BackgroundColor3 = Theme.PanelDark
                    b.Active = false
                    b.AutoButtonColor = false
                else
                    local key = dx .. "," .. dy

                    if enabled[key] == nil then
                        enabled[key] = true
                    end

                    local function paint()
                        local on = enabled[key] ~= false
                        b.Text = on and "ON" or "OFF"
                        b.BackgroundColor3 = on
                            and Theme.Green
                            or Theme.PanelDark
                    end

                    paint()

                    track(b.Activated:Connect(function()
                        if running or destroyed then return end

                        enabled[key] = not (enabled[key] ~= false)
                        paint()
                        updateTileButton()
                    end))
                end
            end
        end

        local footer = create("TextLabel", {
            Position = UDim2.new(0, 10, 1, -35),
            Size = UDim2.new(1, -20, 0, 25),
            BackgroundTransparency = 1,
            Text = "Hijau = aktif | Abu-abu = nonaktif",
            TextColor3 = Theme.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 9,
            ZIndex = 51,
        }, popup)

        track(close.Activated:Connect(closePopup))
    end

    track(tileButton.Activated:Connect(openPopup))

    --==================================================
    -- [G] CORE DISCOVERY
    --==================================================

    local getconsts = (debug and debug.getconstants) or getconstants

    local function raw(t, k)
        if type(t) ~= "table" then return nil end

        local ok, value = pcall(rawget, t, k)
        return ok and value or nil
    end

    local function inventoryCandidate(t)
        if type(t) ~= "table" then return nil end

        local slots = raw(t, "slots")
        local cap = raw(t, "capacity")

        if type(slots) ~= "table"
            or type(cap) ~= "number"
            or cap < 0 or cap > 10000 then
            return nil
        end

        local valid, populated = 0, 0

        for k, slot in pairs(slots) do
            if type(k) == "number"
                and k > 0
                and k % 1 == 0
                and type(slot) == "table" then

                local id = raw(slot, "id")
                local n = raw(slot, "n")

                if id ~= nil or n ~= nil then
                    valid += 1
                end

                if id ~= nil then
                    populated += 1
                end
            end
        end

        if valid == 0 and next(slots) ~= nil then
            return nil
        end

        return {
            ref = t,
            score = valid * 100 + populated + math.min(cap, 100)
        }
    end

    local function findSetTile(objects)
        for _, fn in ipairs(objects) do
            if type(fn) == "function" then
                local okN, name = pcall(debug.info, fn, "n")
                local okA, params, variadic = pcall(debug.info, fn, "a")

                if okN and okA
                    and name == "setTile"
                    and params == 6
                    and variadic == false then

                    local okC, constants = pcall(getconsts, fn)

                    if okC and type(constants) == "table" then
                        local found = {}

                        for _, value in pairs(constants) do
                            found[value] = true
                        end

                        if found.tile and found.send
                            and found.layer and found.x
                            and found.y and found.id
                            and found.flip and found.placedAt
                            and found.flips then
                            return fn
                        end
                    end
                end
            end
        end
    end

    local function findHit(objects)
        for _, fn in ipairs(objects) do
            if type(fn) == "function" then
                local okN, name = pcall(debug.info, fn, "n")
                local okA, params = pcall(debug.info, fn, "a")

                if okN and okA and name == "hit" and params == 4 then
                    local okC, constants = pcall(getconsts, fn)

                    if okC and type(constants) == "table" then
                        local found = {}

                        for _, value in pairs(constants) do
                            found[value] = true
                        end

                        if found.sendHit and found.punchEvent
                            and found.newCrack then
                            return fn
                        end
                    end
                end
            end
        end
    end

    local function discover()
        if type(getgc) ~= "function"
            or type(getconsts) ~= "function"
            or not (debug and debug.info) then
            return false, "Executor tidak menyediakan API discovery."
        end

        local ok, objects = pcall(getgc, true)

        if not ok or type(objects) ~= "table" then
            return false, "getgc(true) gagal: " .. tostring(objects)
        end

        refs.Inv = nil
        refs.World = nil
        refs.State = nil
        refs.SetTile = nil
        refs.Hit = nil

        local bestInv

        for _, obj in ipairs(objects) do
            if type(obj) == "table" then
                local candidate = inventoryCandidate(obj)

                if candidate and (
                    not bestInv or candidate.score > bestInv.score
                ) then
                    bestInv = candidate
                end

                if not refs.World
                    and type(raw(obj, "fg")) == "table"
                    and type(raw(obj, "bg")) == "table"
                    and type(raw(obj, "w")) == "number"
                    and type(raw(obj, "h")) == "number"
                    and raw(obj, "spawn") ~= nil then
                    refs.World = obj
                end

                if not refs.State then
                    local stateFn = raw(obj, "state")

                    if type(stateFn) == "function" then
                        local good, state = pcall(stateFn)

                        if good and type(state) == "table"
                            and type(state.x) == "number"
                            and type(state.y) == "number"
                            and state.facing ~= nil
                            and state.vx ~= nil then
                            refs.State = stateFn
                        end
                    end
                end
            end
        end

        refs.Inv = bestInv and bestInv.ref or nil
        refs.SetTile = findSetTile(objects)
        refs.Hit = findHit(objects)

        local missing = {}

        for _, key in ipairs({
            "Inv", "World", "State", "SetTile", "Hit"
        }) do
            if not refs[key] then
                table.insert(missing, key)
            end
        end

        if #missing > 0 then
            return false,
                "Referensi belum lengkap: " .. table.concat(missing, ", ")
        end

        return true, "Scan berhasil: semua referensi ditemukan."
    end

    --==================================================
    -- [H] INVENTORY / WORLD HELPERS
    --==================================================

    local function selectedId()
        local id = tonumber(raw(refs.Inv, "selected"))

        if id and id > 0 then
            return math.floor(id)
        end
    end

    local function countItem(id)
        local total = 0
        local slots = raw(refs.Inv, "slots")

        if type(slots) ~= "table" then
            return 0
        end

        for _, slot in pairs(slots) do
            if type(slot) == "table"
                and tonumber(raw(slot, "id")) == id then
                total += tonumber(raw(slot, "n")) or 0
            end
        end

        return total
    end

    local function playerTile()
        local ok, state = pcall(refs.State)

        if not ok or type(state) ~= "table"
            or type(state.x) ~= "number"
            or type(state.y) ~= "number" then
            return nil
        end

        if state.active == false then
            return nil
        end

        return math.floor(state.x), math.floor(state.y - 0.475)
    end

    local function tileAt(layer, x, y)
        local world = refs.World

        if not world or x < 0 or y < 0
            or x >= world.w or y >= world.h then
            return nil
        end

        local row = world[layer] and world[layer][y]

        if not row then
            return nil
        end

        return row[x] or 0
    end

    --==================================================
    -- [I] BUILD TARGET PLAN
    --==================================================

    local function buildPlan()
        local px, py = playerTile()

        if not px then
            return nil, "Posisi player tidak terbaca."
        end

        local plan = {}

        for dy = -2, 0 do
            for dx = -2, 2 do
                local key = dx .. "," .. dy

                if not (dx == 0 and dy == 0)
                    and enabled[key] ~= false then

                    local x = px + dx
                    local y = py + dy

                    if x < 0 or y < 0
                        or x >= refs.World.w
                        or y >= refs.World.h then
                        return nil, (
                            "Koordinat %d,%d di luar world."
                        ):format(x, y)
                    end

                    plan[#plan + 1] = {
                        x = x,
                        y = y,
                        dx = dx,
                        dy = dy,
                    }
                end
            end
        end

        if #plan == 0 then
            return nil, "Tidak ada koordinat aktif."
        end

        return plan, px, py
    end

    --==================================================
    -- [J] PUT
    --==================================================

    local function putOne(x, y, id)
        local fg = tileAt("fg", x, y)
        local bg = tileAt("bg", x, y)

        if fg == nil or bg == nil then
            return false, "koordinat di luar world"
        end

        if fg ~= 0 or bg ~= 0 then
            return false, "petak tidak kosong"
        end

        if countItem(id) <= 0 then
            return false, "item inventory habis"
        end

        local ok, err = pcall(
            refs.SetTile, "fg", x, y, id, false, false
        )

        if not ok then
            for _ = 1, 20 do
                if not running or destroyed then
                    return false, "proses dihentikan"
                end

                task.wait(0.05)

                local nowFg = tileAt("fg", x, y)
                local nowBg = tileAt("bg", x, y)

                if nowFg == id and nowBg == 0 then
                    return true, "PUT terdeteksi setelah error"
                end

                if nowFg == nil or nowBg == nil then
                    break
                end
            end

            return false, "setTile error: " .. tostring(err)
        end

        for _ = 1, 60 do
            if not running or destroyed then
                return false, "PUT dihentikan"
            end

            task.wait(0.05)

            local nowFg = tileAt("fg", x, y)
            local nowBg = tileAt("bg", x, y)

            if nowFg == nil or nowBg == nil then
                return false, "tile keluar dari world"
            end

            if nowFg == id and nowBg == 0 then
                return true, "PUT terkonfirmasi"
            end
        end

        return false, "PUT tidak terkonfirmasi"
    end

    --==================================================
    -- [K] BREAK
    --==================================================

    local function breakOne(x, y, startDelayMs, hitDelayMs)
        task.wait(math.max(0, startDelayMs) / 1000)

        local function readLayers()
            return tileAt("fg", x, y), tileAt("bg", x, y)
        end

        local function confirmEmpty()
            local consecutive = 0

            for _ = 1, 20 do
                if not running or destroyed then
                    return false
                end

                task.wait(0.05)

                local fg, bg = readLayers()

                if fg == nil or bg == nil then
                    return false
                end

                if fg == 0 and bg == 0 then
                    consecutive += 1

                    if consecutive >= 3 then
                        return true
                    end
                else
                    consecutive = 0
                    return false
                end
            end

            return false
        end

        local fg, bg = readLayers()

        if fg == nil or bg == nil then
            return false, "koordinat tidak valid"
        end

        if fg == 0 and bg == 0 and confirmEmpty() then
            return true, "tile sudah kosong"
        end

        for hitNo = 1, 60 do
            if not running or destroyed then
                return false, "dihentikan"
            end

            fg, bg = readLayers()

            if fg == nil or bg == nil then
                return false, "koordinat tidak valid"
            end

            if fg == 0 and bg == 0 and confirmEmpty() then
                return true, "tile kosong terkonfirmasi"
            end

            local ok, err = pcall(refs.Hit, x, y, nil, nil)

            if not ok then
                return false, "hit error: " .. tostring(err)
            end

            task.wait(math.max(0, hitDelayMs) / 1000)

            local afterFg, afterBg = readLayers()

            if afterFg == nil or afterBg == nil then
                return false, "koordinat tidak valid setelah hit"
            end

            if afterFg == 0 and afterBg == 0
                and confirmEmpty() then
                return true, (
                    "tile kosong setelah %d hit"
                ):format(hitNo)
            end
        end

        return false, "BREAK belum terkonfirmasi setelah 60 hit"
    end

    --==================================================
    -- [L] DELAY VALIDATION
    --==================================================

    local function readDelay(box, minimum, maximum)
        local n = tonumber(box.Text)

        if not n then
            return nil, "Delay harus berupa angka."
        end

        n = math.floor(n)

        if n < minimum or n > maximum then
            return nil, (
                "Delay harus %d sampai %d ms."
            ):format(minimum, maximum)
        end

        return n
    end

    --==================================================
    -- [M] BUTTON EVENTS
    --==================================================

    track(scanButton.Activated:Connect(function()
        if running then
            report("Stop proses sebelum scan ulang.")
            return
        end

        confirmedId = nil

        task.spawn(function()
            local ok, message = discover()

            if destroyed then return end

            report(ok and message or ("SCAN GAGAL: " .. message))

            if refs.Inv then
                local id = selectedId()

                selectedLabel.Text = id
                    and ("Inventory selected: ID %d | jumlah: %d"):format(
                        id, countItem(id)
                    )
                    or "Inventory selected: tidak ada"
            end
        end)
    end))

    track(lockButton.Activated:Connect(function()
        if not refs.Inv then
            report("Inventory belum ditemukan. Tekan SCAN ULANG.")
            return
        end

        local id = selectedId()

        if not id then
            confirmedId = nil
            report("Pilih item di inventory game terlebih dahulu.")
            return
        end

        if countItem(id) <= 0 then
            confirmedId = nil
            report("Item selected tidak memiliki jumlah.")
            return
        end

        confirmedId = id

        selectedLabel.Text = (
            "LOCKED ID: %d | jumlah: %d"
        ):format(id, countItem(id))

        report("Item inventory dikunci: ID " .. id)
    end))

    track(previewButton.Activated:Connect(function()
        if not refs.World or not refs.State then
            report("World/State belum siap.")
            return
        end

        local plan, px, py = buildPlan()

        if not plan then
            report("PREVIEW GAGAL: " .. tostring(px))
            return
        end

        local coords = {}

        for i, p in ipairs(plan) do
            coords[#coords + 1] = (
                "%d:(%d,%d)"
            ):format(i, p.x, p.y)
        end

        report((
            "Anchor %d,%d | %d target | %s"
        ):format(px, py, #plan, table.concat(coords, " ")))
    end))

    track(stopButton.Activated:Connect(function()
        running = false
        report("STOP diminta.")
    end))

    track(startButton.Activated:Connect(function()
        if running then return end

        if not (
            refs.Inv and refs.World and refs.State
            and refs.SetTile and refs.Hit
        ) then
            report("Referensi belum lengkap. Tekan SCAN ULANG.")
            return
        end

        if not confirmedId then
            report("Pilih item di inventory lalu LOCK SELECTED.")
            return
        end

        local putMs, e1 = readDelay(putDelayBox, 0, 10000)
        local hitMs, e2 = readDelay(breakDelayBox, 1, 10000)
        local startMs, e3 = readDelay(breakStartBox, 50, 10000)
        local cycleMs, e4 = readDelay(cycleDelayBox, 0, 60000)

        if not putMs then report(e1) return end
        if not hitMs then report(e2) return end
        if not startMs then report(e3) return end
        if not cycleMs then report(e4) return end

        local plan, px, py = buildPlan()

        if not plan then
            report("START dibatalkan: " .. tostring(px))
            return
        end

        closePopup()

        running = true

        task.spawn(function()
            local cycle = 0

            report((
                "LOOP START | anchor %d,%d | ID %d | %d target"
            ):format(px, py, confirmedId, #plan))

            while running and not destroyed and not Hub.IsClosing() do
                cycle += 1

                local breakQueue = {}
                local hasEmptyTargetWithoutItem = false

                report(("SIKLUS %d | FASE PUT"):format(cycle))

                for index, p in ipairs(plan) do
                    if not running or destroyed or Hub.IsClosing() then
                        break
                    end

                    local cx, cy = playerTile()

                    if not cx or cx ~= px or cy ~= py then
                        running = false
                        report("STOP AMAN: posisi player berubah.")
                        break
                    end

                    local currentFg = tileAt("fg", p.x, p.y)
                    local currentBg = tileAt("bg", p.x, p.y)

                    if currentFg == nil or currentBg == nil then
                        report("Koordinat tidak valid.")

                    elseif currentFg ~= 0 or currentBg ~= 0 then
                        breakQueue[#breakQueue + 1] = p

                    else
                        if countItem(confirmedId) <= 0 then
                            hasEmptyTargetWithoutItem = true
                            report("Item LOCKED habis.")
                        else
                            local placed, putMessage = putOne(
                                p.x, p.y, confirmedId
                            )

                            if placed then
                                breakQueue[#breakQueue + 1] = p
                                report((
                                    "PUT %d/%d OK (%d,%d)"
                                ):format(index, #plan, p.x, p.y))
                            else
                                local checkFg = tileAt("fg", p.x, p.y)
                                local checkBg = tileAt("bg", p.x, p.y)

                                if checkFg ~= nil and checkBg ~= nil
                                    and (checkFg ~= 0 or checkBg ~= 0) then
                                    breakQueue[#breakQueue + 1] = p
                                else
                                    report((
                                        "PUT GAGAL (%d,%d): %s"
                                    ):format(p.x, p.y, tostring(putMessage)))
                                end
                            end
                        end
                    end

                    if putMs > 0 then
                        task.wait(putMs / 1000)
                    end
                end

                if not running or destroyed or Hub.IsClosing() then
                    break
                end

                if #breakQueue == 0 then
                    running = false

                    report(hasEmptyTargetWithoutItem
                        and "STOP: item LOCKED habis."
                        or "STOP: tidak ada tile untuk BREAK.")

                    break
                end

                report((
                    "SIKLUS %d | FASE BREAK: %d tile"
                ):format(cycle, #breakQueue))

                for index, p in ipairs(breakQueue) do
                    if not running or destroyed or Hub.IsClosing() then
                        break
                    end

                    local cx, cy = playerTile()

                    if not cx or cx ~= px or cy ~= py then
                        running = false
                        report("STOP AMAN: posisi player berubah.")
                        break
                    end

                    local broken, breakMessage = breakOne(
                        p.x, p.y, startMs, hitMs
                    )

                    report((
                        "BREAK %d/%d (%d,%d): %s"
                    ):format(
                        index, #breakQueue,
                        p.x, p.y, tostring(breakMessage)
                    ))

                    if not broken then
                        running = false
                        break
                    end
                end

                if running and not destroyed and cycleMs > 0 then
                    task.wait(cycleMs / 1000)
                end
            end

            running = false

            if not destroyed then
                report("LOOP BERHENTI.")
            end
        end)
    end))

    --==================================================
    -- [N] INVENTORY DISPLAY LOOP
    --==================================================

    task.spawn(function()
        task.wait(0.5)

        if destroyed or Hub.IsClosing() then return end

        local ok, message = discover()

        if destroyed or Hub.IsClosing() then return end

        report(ok and message or ("SCAN: " .. message))
    end)

    task.spawn(function()
        while not destroyed
            and not Hub.IsClosing()
            and page.Parent do

            if refs.Inv then
                if not confirmedId then
                    local id = selectedId()

                    selectedLabel.Text = id
                        and ("Inventory selected: ID %d | jumlah: %d"):format(
                            id, countItem(id)
                        )
                        or "Inventory selected: tidak ada"
                else
                    local current = selectedId()

                    selectedLabel.Text = (
                        "LOCKED ID: %d | jumlah: %d%s"
                    ):format(
                        confirmedId,
                        countItem(confirmedId),
                        current ~= confirmedId
                            and (" | SELECTED BERUBAH: " .. tostring(current))
                            or ""
                    )

                    if countItem(confirmedId) <= 0 and running then
                        running = false
                        report("STOP: item LOCKED habis.")
                    end
                end
            end

            task.wait(0.25)
        end
    end)

    --==================================================
    -- [O] CLEANUP
    --==================================================

    local function cleanup()
        if destroyed then return end

        destroyed = true
        running = false

        closePopup()

        for _, connection in ipairs(connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end

        table.clear(connections)
    end

    Hub.RegisterCleanup(cleanup)

    -- Default semua tile aktif kecuali posisi YOU.
    updateTileButton()

    print("[APB] Auto PUT + BREAK module loaded.")

end)

--==================================================
-- END MODULE: AUTO PUT + BREAK V4
--==================================================


Hub.RegisterTab("Menu 2", function(page)
    -- Isi Menu 2 nanti diganti dengan UI dan fungsi fitur kedua.
end)


--==================================================
-- [12] MINIMIZE / RESTORE
--==================================================

local IsMinimized = false
local NormalSize = UDim2.fromOffset(600, 300)

MinimizeButton.Activated:Connect(function()
    if IsClosed then return end

    IsMinimized = not IsMinimized

    if IsMinimized then
        -- Jadikan UI sebuah kotak kecil yang menempel di sisi paling atas layar.
        Body.Visible = false
        Title.Visible = false
        CloseButton.Visible = false

        Header.Size = UDim2.fromScale(1, 1)
        Main.Size = UDim2.fromOffset(34, 34)
        Main.Position = UDim2.new(0.5, 0, 0, 17)

        MinimizeButton.AnchorPoint = Vector2.new(0.5, 0.5)
        MinimizeButton.Position = UDim2.fromScale(0.5, 0.5)
        MinimizeButton.Size = UDim2.fromOffset(30, 30)
        MinimizeButton.Text = ""
        MinimizeButton.BackgroundColor3 = Theme.Accent
    else
        -- Kembalikan UI ke posisi dan ukuran normal.
        Main.Size = NormalSize
        Main.Position = UDim2.fromScale(0.5, 0.5)

        Header.Size = UDim2.new(1, 0, 0, 52)
        Title.Visible = true
        CloseButton.Visible = true

        MinimizeButton.AnchorPoint = Vector2.new(1, 0.5)
        MinimizeButton.Position = UDim2.new(1, -12, 0.5, 0)
        MinimizeButton.Size = UDim2.fromOffset(38, 32)
        MinimizeButton.Text = "—"
        MinimizeButton.BackgroundColor3 = Theme.Panel

        Body.Visible = true
    end
end)

-- CLOSE = hentikan semua modul terdaftar, putus koneksi global,
-- hapus bridge, lalu hancurkan seluruh UI.
local function CloseHub()
    if IsClosed then return end

    RunAllCleanups()

    IsDragging = false
    ActiveTouch = nil

    if DragInputConnection then
        DragInputConnection:Disconnect()
        DragInputConnection = nil
    end

    if DragEndConnection then
        DragEndConnection:Disconnect()
        DragEndConnection = nil
    end

    if _G.GrowBloxHub == Hub then
        _G.GrowBloxHub = nil
    end

    ScreenGui:Destroy()
end

CloseButton.Activated:Connect(CloseHub)
Hub.Close = CloseHub

--==================================================
-- [13] MODULE BRIDGE
--==================================================

_G.GrowBloxHub = Hub

print("[GrowBlox Hub] Optimized UI Foundation loaded.")
