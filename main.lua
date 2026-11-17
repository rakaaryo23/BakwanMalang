--[[
GROWBLOX HUB - UI FOUNDATION V2
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
    Size = UDim2.fromOffset(760, 460),
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
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    IsDragging = true
    ActiveTouch = input.UserInputType == Enum.UserInputType.Touch and input or nil
    DragStart = input.Position
    StartPosition = Main.Position

    input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            IsDragging = false
            ActiveTouch = nil
        end
    end)
end

Header.InputBegan:Connect(BeginWindowDrag)

local DragBorderSize = 16

local function CreateDragHandle(name, position, size)
    local handle = Create("TextButton", {
        Name = name,
        Position = position,
        Size = size,
        BackgroundTransparency = 1,
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Active = true,
        Selectable = false,
        ZIndex = 1000,
    }, Main)

    handle.InputBegan:Connect(BeginWindowDrag)
    return handle
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

local DragInputConnection = UserInputService.InputChanged:Connect(function(input)
    if IsClosed or not IsDragging then
        return
    end

    local isMouseMove = input.UserInputType == Enum.UserInputType.MouseMovement
    local isActiveTouchMove = ActiveTouch ~= nil
        and input == ActiveTouch

    if isMouseMove or isActiveTouchMove then
        local delta = input.Position - DragStart
        Main.Position = UDim2.new(
            StartPosition.X.Scale,
            StartPosition.X.Offset + delta.X,
            StartPosition.Y.Scale,
            StartPosition.Y.Offset + delta.Y
        )
    end
end)

--==================================================
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

local IsClosed = false
local CleanupCallbacks = {}

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

Hub.RegisterTab("Menu 1", function(page)
    -- Isi Menu 1 nanti diganti dengan UI dan fungsi fitur pertama.
end)

Hub.RegisterTab("Menu 2", function(page)
    -- Isi Menu 2 nanti diganti dengan UI dan fungsi fitur kedua.
end)

--==================================================
-- [12] MINIMIZE / RESTORE
--==================================================

local IsMinimized = false
local NormalSize = UDim2.fromOffset(700, 380)

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

    if _G.GrowBloxHub == Hub then
        _G.GrowBloxHub = nil
    end

    ScreenGui:Destroy()
end

CloseButton.Activated:Connect(CloseHub)

--==================================================
-- [13] MODULE BRIDGE
--==================================================

_G.GrowBloxHub = Hub

print("[GrowBlox Hub] UI Foundation V2 loaded.")
