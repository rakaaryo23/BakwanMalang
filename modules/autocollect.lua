--==================================================
-- MODULE: AUTO COLLECT 5x5 REMOTE (GROWBLOX HUB)
-- Menggunakan mekanisme remote ala k.lua dengan area 5x5
--==================================================

return function(Hub)

    Hub.RegisterTab("Auto Collect", function(page)

    --==================================================
    -- [A] CONFIGURATION & STATE
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

    local running = false
    local destroyed = false

    local refs = {
        Inv = nil,
        World = nil,
        State = nil,
    }

    -- Grid 5x5: key format "dx,dy", value true/false (Default semua aktif)
    local enabledTiles = {}
    for dx = -2, 2 do
        for dy = -2, 2 do
            enabledTiles[dx .. "," .. dy] = true
        end
    end

    local connections = {}
    local popup = nil
    local statusLabel
    local tileButton

    local function report(message)
        message = tostring(message)
        if statusLabel and statusLabel.Parent then
            statusLabel.Text = "Status: " .. message
        end
        print("[AutoCollect]", message)
    end

    local function track(connection)
        table.insert(connections, connection)
        return connection
    end

    --==================================================
    -- [B] UI HELPERS
    --==================================================

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

    local function makeLabel(text, height, parent)
        return create("TextLabel", {
            Size = UDim2.new(1, 0, 0, height or 25),
            BackgroundTransparency = 1,
            Text = text or "",
            TextColor3 = Theme.Text,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextWrapped = true,
        }, parent or page)
    end

    local function makeButton(text, height, parent, color)
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

    local function makeDelayBox(caption, value, parent)
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, 42),
            BackgroundTransparency = 1,
        }, parent)

        create("TextLabel", {
            Size = UDim2.new(0.58, 0, 1, 0),
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
            Size = UDim2.new(0.38, 0, 0, 29),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            Text = tostring(value),
            PlaceholderText = "ms",
            TextColor3 = Theme.Text,
            PlaceholderColor3 = Theme.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            ClearTextOnFocus = false,
        }, row)
        corner(box, 6)
        return box
    end

    --==================================================
    -- [C] MAIN SUBMENU UI
    --==================================================

    create("UIListLayout", {
        Padding = UDim.new(0, 7),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, page)

    statusLabel = makeLabel("Status: siap", 34)
    statusLabel.LayoutOrder = 1

    local areaLabel = makeLabel("Area target: 5 x 5 (Termasuk player di tengah)", 24)
    areaLabel.LayoutOrder = 2

    tileButton = makeButton("PILIH TILE  |  25 TARGET AKTIF", 34)
    tileButton.LayoutOrder = 3

    local startButton = makeButton("START AUTO COLLECT", 36, page, Theme.Green)
    startButton.LayoutOrder = 4

    local stopButton = makeButton("STOP", 32, page, Theme.Red)
    stopButton.LayoutOrder = 5

    local settingsButton = makeButton("PENGATURAN DELAY  ▼", 30, page, Theme.PanelDark)
    settingsButton.TextColor3 = Theme.Text
    settingsButton.LayoutOrder = 6

    local settingsFrame = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        Visible = false,
        LayoutOrder = 7,
    }, page)
    corner(settingsFrame, 8)

    create("UIPadding", {
        PaddingTop = UDim.new(0, 7),
        PaddingBottom = UDim.new(0, 7),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }, settingsFrame)

    create("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, settingsFrame)

    -- Delay default ala k.lua (0.05s atau 50ms sebagai opsi standar cepat & stabil)
    local collectDelayBox = makeDelayBox("Jeda antar Collect (ms)", 50, settingsFrame)

    track(settingsButton.Activated:Connect(function()
        settingsFrame.Visible = not settingsFrame.Visible
        settingsButton.Text = settingsFrame.Visible and "PENGATURAN DELAY  ▲" or "PENGATURAN DELAY  ▼"
    end))

    --==================================================
    -- [D] TILE SELECT POPUP (DENGAN TOMBOL SILANG / X)
    --==================================================

    local function activeTileCount()
        local count = 0
        for dy = -2, 2 do
            for dx = -2, 2 do
                if enabledTiles[dx .. "," .. dy] ~= false then
                    count += 1
                end
            end
        end
        return count
    end

    local function updateTileButton()
        if tileButton and tileButton.Parent then
            tileButton.Text = ("PILIH TILE  |  %d TARGET AKTIF"):format(activeTileCount())
        end
    end

    local function closePopup()
        if popup then
            popup:Destroy()
            popup = nil
        end
    end

    local function openPopup()
        if destroyed or popup then return end

        local screenGui = Hub.GetGui()
        if not screenGui then
            report("ScreenGui Hub tidak ditemukan.")
            return
        end

        popup = create("Frame", {
            Name = "AutoCollectPopup",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(290, 290),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            ZIndex = 200,
        }, screenGui)
        corner(popup, 10)

        create("TextLabel", {
            Position = UDim2.fromOffset(10, 5),
            Size = UDim2.new(1, -55, 0, 30),
            BackgroundTransparency = 1,
            Text = "PILIH TILE COLLECT (5x5)",
            TextColor3 = Theme.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 201,
        }, popup)

        -- Tombol Close (Tanda Silang / X)
        local closeButton = create("TextButton", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -8, 0, 7),
            Size = UDim2.fromOffset(30, 27),
            BackgroundColor3 = Theme.Red,
            BorderSizePixel = 0,
            Text = "X",
            TextColor3 = Theme.White,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            ZIndex = 201,
        }, popup)
        corner(closeButton, 6)

        local grid = create("Frame", {
            Position = UDim2.fromOffset(18, 45),
            Size = UDim2.fromOffset(254, 185),
            BackgroundTransparency = 1,
            ZIndex = 201,
        }, popup)

        create("UIGridLayout", {
            CellSize = UDim2.fromOffset(48, 33),
            CellPadding = UDim2.fromOffset(3, 3),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, grid)

        for dy = -2, 2 do
            for dx = -2, 2 do
                local b = create("TextButton", {
                    BackgroundColor3 = Theme.Green,
                    BorderSizePixel = 0,
                    Text = "",
                    TextColor3 = Theme.White,
                    Font = Enum.Font.GothamBold,
                    TextSize = 10,
                    ZIndex = 202,
                }, grid)
                corner(b, 6)

                if dx == 0 and dy == 0 then
                    b.Text = "YOU"
                    b.BackgroundColor3 = Theme.PanelDark
                end

                local key = dx .. "," .. dy
                if enabledTiles[key] == nil then
                    enabledTiles[key] = true
                end

                local function paint()
                    local on = enabledTiles[key] ~= false
                    if dx == 0 and dy == 0 then
                        b.Text = "YOU"
                    else
                        b.Text = on and "ON" or "OFF"
                    end
                    b.BackgroundColor3 = on and Theme.Green or Theme.PanelDark
                end
                paint()

                track(b.Activated:Connect(function()
                    if running or destroyed then return end
                    enabledTiles[key] = not (enabledTiles[key] ~= false)
                    paint()
                    updateTileButton()
                end))
            end
        end

        create("TextLabel", {
            Position = UDim2.new(0, 10, 1, -35),
            Size = UDim2.new(1, -20, 0, 25),
            BackgroundTransparency = 1,
            Text = "Hijau = aktif (diambil) | Abu = nonaktif",
            TextColor3 = Theme.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 9,
            ZIndex = 201,
        }, popup)

        track(closeButton.Activated:Connect(closePopup))
    end

    track(tileButton.Activated:Connect(openPopup))

    --==================================================
    -- [E] DISCOVERY & GAME HELPERS (REMOTE MODE ALA K.LUA)
    --==================================================

    local function raw(t, k)
        if type(t) ~= "table" then return nil end
        local ok, value = pcall(rawget, t, k)
        return ok and value or nil
    end

    local function discover()
        local ok, objects = pcall(getgc, true)
        if not ok or type(objects) ~= "table" then
            return false, "getgc gagal"
        end

        refs.Inv, refs.World, refs.State = nil, nil, nil

        for _, obj in ipairs(objects) do
            if type(obj) == "table" then
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
                            and type(state.y) == "number" then
                            refs.State = stateFn
                        end
                    end
                end
            end
        end

        return true, "Scan Berhasil"
    end

    local function playerTile()
        if not refs.State then return nil, nil end
        local ok, state = pcall(refs.State)
        if not ok or type(state) ~= "table" or type(state.x) ~= "number" then
            return nil, nil
        end
        return math.floor(state.x), math.floor(state.y - 0.475)
    end

    --==================================================
    -- [F] BUTTON EVENTS & LOOP UTAMA (REMOTE COLLECTION)
    --==================================================

    track(stopButton.Activated:Connect(function()
        running = false
        report("STOP diminta.")
    end))

    track(startButton.Activated:Connect(function()
        if running then return end

        discover()

        local delayMs = tonumber(collectDelayBox.Text)
        if not delayMs or delayMs < 0 then
            report("Error: Jeda collect harus berupa angka valid.")
            return
        end

        closePopup()
        running = true
        report("Auto Collect aktif (Remote Mode)...")

        task.spawn(function()
            while running and not destroyed and not Hub.IsClosing() do
                local px, py = playerTile()
                if not px or not py then
                    report("Error: Posisi player tidak terbaca.")
                    task.wait(0.5)
                    continue
                end

                local success, err = pcall(function()
                    -- Ambil daftar global drop di game (Drops.list)
                    local dropsList = rawget(_G, "Drops") and rawget(_G, "Drops").list 
                        or (getgenv and rawget(getgenv(), "Drops") and getgenv().Drops.list)
                        or (Drops and Drops.list)

                    if type(dropsList) == "table" then
                        for _, drop in ipairs(dropsList) do
                            if drop and drop.x and drop.y and drop.uid then
                                local dx = drop.x - px
                                local dy = drop.y - py

                                -- Cek apakah masuk dalam area 5x5 (-2 s/d 2) dan aktif di menu popup
                                if dx >= -2 and dx <= 2 and dy >= -2 and dy <= 2 then
                                    local key = dx .. "," .. dy
                                    if enabledTiles[key] ~= false then
                                        -- Eksekusi Remote Mode ala k.lua secara instan / paralel
                                        task.spawn(function()
                                            if worldTake then
                                                pcall(worldTake, drop.uid, drop.amount or 1)
                                            elseif TakeDropRemote then
                                                pcall(function() TakeDropRemote:InvokeServer(drop.uid, drop.amount or 1) end)
                                            end
                                        end)
                                    end
                                end
                            end
                        end
                    end
                end)

                if not success then
                    report("Error saat collect: " .. tostring(err))
                end

                task.wait(delayMs / 1000)
            end

            running = false
            if not destroyed then report("Auto Collect berhenti.") end
        end)
    end))

    --==================================================
    -- [G] CLEANUP
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
    updateTileButton()

    print("[AutoCollect] Module loaded successfully.")

    end)

end
