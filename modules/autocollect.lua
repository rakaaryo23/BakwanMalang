--==================================================
-- MODULE: AUTO COLLECT 5x5 REMOTE (GROWBLOX HUB)
-- Disamakan 100% dengan struktur & pola APB_2.lua
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
        World = nil,
        State = nil,
        Drops = nil,
        TakeFn = nil,
    }

    local enabled = {}
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

    statusLabel = makeLabel("Status: menyiapkan scan...", 34)
    statusLabel.LayoutOrder = 1

    local areaLabel = makeLabel("Area target: 5 x 5 | Player berada di tengah", 24)
    areaLabel.LayoutOrder = 2

    tileButton = makeButton("PILIH TILE  |  25 TARGET AKTIF", 34)
    tileButton.LayoutOrder = 3

    local scanButton = makeButton("SCAN ULANG", 32, page, Theme.PanelDark)
    scanButton.TextColor3 = Theme.Text
    scanButton.LayoutOrder = 4

    local startButton = makeButton("START AUTO COLLECT", 36, page, Theme.Green)
    startButton.LayoutOrder = 5

    local stopButton = makeButton("STOP", 32, page, Theme.Red)
    stopButton.LayoutOrder = 6

    local settingsButton = makeButton("PENGATURAN DELAY  ▼", 30, page, Theme.PanelDark)
    settingsButton.TextColor3 = Theme.Text
    settingsButton.LayoutOrder = 7

    local settingsFrame = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        Visible = false,
        LayoutOrder = 8,
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

    local collectDelayBox = makeDelayBox("Jeda antar Collect (ms)", 50, settingsFrame)

    track(settingsButton.Activated:Connect(function()
        settingsFrame.Visible = not settingsFrame.Visible
        settingsButton.Text = settingsFrame.Visible and "PENGATURAN DELAY  ▲" or "PENGATURAN DELAY  ▼"
    end))

    --==================================================
    -- [D] TILE SELECT POPUP (5x5 DENGAN TOMBOL X)
    --==================================================

    local function activeTileCount()
        local count = 0
        for dy = -2, 2 do
            for dx = -2, 2 do
                if not (dx == 0 and dy == 0) and enabled[dx .. "," .. dy] ~= false then
                    count += 1
                end
            end
        end
        return count
    end

    local function updateTileButton()
        if tileButton and tileButton.Parent then
            tileButton.Text = ("PILIH TILE  |  %d TARGET AKTIF"):format(activeTileCount() + 1)
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
                        b.BackgroundColor3 = on and Theme.Green or Theme.PanelDark
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

        create("TextLabel", {
            Position = UDim2.new(0, 10, 1, -35),
            Size = UDim2.new(1, -20, 0, 25),
            BackgroundTransparency = 1,
            Text = "Hijau = aktif | Abu-abu = nonaktif",
            TextColor3 = Theme.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 9,
            ZIndex = 201,
        }, popup)

        track(closeButton.Activated:Connect(closePopup))
    end

    track(tileButton.Activated:Connect(openPopup))

    --==================================================
    -- [E] DISCOVERY LOGIC (PERSIS POLA APB)
    --==================================================

    local function raw(t, k)
        if type(t) ~= "table" then return nil end
        local ok, value = pcall(rawget, t, k)
        return ok and value or nil
    end

    local function findTakeFn(objects)
        for _, fn in ipairs(objects) do
            if type(fn) == "function" then
                local okN, name = pcall(debug.info, fn, "n")
                if okN and (name == "take" or name == "takeDrop" or name == "worldTake") then
                    return fn
                end
            end
        end
        return rawget(_G, "worldTake") or (getgenv and rawget(getgenv(), "worldTake"))
    end

    local function discover()
        if type(getgc) ~= "function" or not (debug and debug.info) then
            return false, "Executor tidak mendukung getgc/debug.info"
        end

        local ok, objects = pcall(getgc, true)
        if not ok or type(objects) ~= "table" then
            return false, "getgc(true) gagal"
        end

        refs.State, refs.Drops = nil, nil

        for _, obj in ipairs(objects) do
            if type(obj) == "table" then
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

                if not refs.Drops then
                    local list = raw(obj, "list")
                    if type(list) == "table" then
                        for _, item in pairs(list) do
                            if type(item) == "table" and raw(item, "x") and raw(item, "y") and (raw(item, "uid") or raw(item, "id")) then
                                refs.Drops = obj
                                break
                            end
                        end
                    end
                end
            end
        end

        refs.TakeFn = findTakeFn(objects)

        if not refs.State then
            return false, "Referensi State player tidak ditemukan"
        end

        return true, "Scan berhasil: State & Drops siap."
    end

    local function playerTile()
        local ok, state = pcall(refs.State)
        if not ok or type(state) ~= "table"
            or type(state.x) ~= "number"
            or type(state.y) ~= "number" then
            return nil, nil
        end
        return math.floor(state.x), math.floor(state.y - 0.475)
    end

    local function getDropsList()
        if refs.Drops and type(raw(refs.Drops, "list")) == "table" then
            return refs.Drops.list
        end
        if rawget(_G, "Drops") and type(_G.Drops.list) == "table" then
            return _G.Drops.list
        end
        if getgenv and getgenv().Drops and type(getgenv().Drops.list) == "table" then
            return getgenv().Drops.list
        end
        return nil
    end

    --==================================================
    -- [F] BUTTON EVENTS & LOOP UTAMA (REMOTE MODE)
    --==================================================

    track(scanButton.Activated:Connect(function()
        if running then
            report("Stop proses sebelum scan ulang.")
            return
        end

        task.spawn(function()
            local ok, message = discover()
            if destroyed or Hub.IsClosing() then return end
            report(ok and message or ("SCAN GAGAL: " .. message))
        end)
    end))

    track(stopButton.Activated:Connect(function()
        running = false
        report("STOP diminta.")
    end))

    track(startButton.Activated:Connect(function()
        if running then return end

        local okScan, msgScan = discover()
        if not okScan then
            report("Gagal Start: " .. msgScan)
            return
        end

        local delayMs = tonumber(collectDelayBox.Text)
        if not delayMs or delayMs < 0 then
            report("Jeda collect harus berupa angka valid (ms).")
            return
        end

        closePopup()
        running = true

        task.spawn(function()
            report("AUTO COLLECT RUNNING (Remote Mode)...")

            while running and not destroyed and not Hub.IsClosing() do
                local px, py = playerTile()
                if not px then
                    report("STATUS: Error - Posisi player tidak terbaca.")
                    task.wait(0.5)
                    continue
                end

                pcall(function()
                    local dropsList = getDropsList()
                    if type(dropsList) == "table" then
                        for _, drop in ipairs(dropsList) do
                            if drop and drop.x and drop.y then
                                local uid = drop.uid or drop.id
                                if uid then
                                    local dx = drop.x - px
                                    local dy = drop.y - py

                                    if dx >= -2 and dx <= 2 and dy >= -2 and dy <= 2 then
                                        local key = dx .. "," .. dy
                                        if dx == 0 and dy == 0 or enabled[key] ~= false then
                                            task.spawn(function()
                                                if refs.TakeFn and type(refs.TakeFn) == "function" then
                                                    pcall(refs.TakeFn, uid, drop.amount or 1)
                                                elseif worldTake then
                                                    pcall(worldTake, uid, drop.amount or 1)
                                                elseif TakeDropRemote then
                                                    pcall(function() TakeDropRemote:InvokeServer(uid, drop.amount or 1) end)
                                                end
                                            end)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end)

                task.wait(delayMs / 1000)
            end

            running = false
            if not destroyed then report("AUTO COLLECT BERHENTI.") end
        end)
    end))

    --==================================================
    -- [G] INITIAL SCAN & CLEANUP
    --==================================================

    task.spawn(function()
        task.wait(0.5)
        if destroyed or Hub.IsClosing() then return end
        local callOk, scanOk, message = pcall(discover)
        if destroyed or Hub.IsClosing() then return end
        if not callOk then
            report("ERROR SAAT SCAN: " .. tostring(scanOk))
            return
        end
        report(scanOk and message or ("SCAN GAGAL: " .. tostring(message)))
    end)

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

    print("[AutoCollect] Submenu loaded successfully.")

    end)

end
