--==================================================
-- MODULE: WORLD PLACED BLOCK SCANNER
-- Tab mandiri: menampilkan grid world 100 x 60.
-- Tap tile untuk membaca FG ID dan BG ID pada koordinat itu.
-- Menggunakan struktur world.fg / world.bg yang sama dengan
-- module utama dan module DIRT FARM PATHFINDING.
-- Tidak memasang hook dan tidak mengubah module lain.
--==================================================

return function(Hub)
    Hub.RegisterTab("WORLD SCANNER", function(page)
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
            Empty = Color3.fromRGB(54, 54, 62),
            FG = Color3.fromRGB(171, 91, 119),
            BG = Color3.fromRGB(65, 125, 190),
            Both = Color3.fromRGB(133, 88, 160),
            Selected = Color3.fromRGB(255, 220, 70),
        }

        local EXPECTED_W = 100
        local EXPECTED_H = 60
        local CELL_SIZE = 12
        local CELL_GAP = 1

        local running = true
        local scanning = false
        local refreshing = false
        local worldRef = nil
        local connections = {}
        local tileButtons = {}
        local selected = nil
        local gridBuilt = false

        local function create(className, properties, parent)
            local object = Instance.new(className)
            for property, value in pairs(properties or {}) do
                object[property] = value
            end
            object.Parent = parent or page
            return object
        end

        local function corner(object, radius)
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, radius or 7)
            c.Parent = object
            return c
        end

        local function track(connection)
            connections[#connections + 1] = connection
            return connection
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
            }, parent)
        end

        local function makeButton(text, height, parent, color)
            local button = create("TextButton", {
                Size = UDim2.new(1, 0, 0, height or 34),
                BackgroundColor3 = color or Theme.Accent,
                BorderSizePixel = 0,
                Text = text,
                TextColor3 = Theme.White,
                Font = Enum.Font.GothamBold,
                TextSize = 10,
                AutoButtonColor = true,
            }, parent)
            corner(button, 6)
            return button
        end

        local function log(...)
            print("[WORLD SCANNER]", ...)
        end

        local statusLabel
        local selectedLabel
        local mapScroll
        local mapGrid

        local function setStatus(message)
            message = tostring(message or "-")
            if statusLabel and statusLabel.Parent then
                statusLabel.Text = "STATUS: " .. message
            end
            log(message)
        end

        local function safeRaw(t, key)
            if type(t) ~= "table" then return nil end
            local ok, value = pcall(rawget, t, key)
            return ok and value or nil
        end

        local function validWorld(t)
            return type(t) == "table"
                and type(safeRaw(t, "fg")) == "table"
                and type(safeRaw(t, "bg")) == "table"
                and type(safeRaw(t, "w")) == "number"
                and type(safeRaw(t, "h")) == "number"
                and safeRaw(t, "spawn") ~= nil
        end

        local function scanWorldOnce()
            if type(getgc) ~= "function" then
                return false, "Executor tidak menyediakan getgc"
            end

            local ok, objects = pcall(getgc, true)
            if not ok or type(objects) ~= "table" then
                return false, "getgc(true) gagal: " .. tostring(objects)
            end

            local found
            for _, object in ipairs(objects) do
                if type(object) == "table" and validWorld(object) then
                    found = object
                    break
                end
            end

            if not found then
                return false, "Tabel World (fg/bg/w/h/spawn) belum ditemukan"
            end

            worldRef = found
            local width = tonumber(safeRaw(found, "w"))
            local height = tonumber(safeRaw(found, "h"))
            if width ~= EXPECTED_W or height ~= EXPECTED_H then
                return false, string.format(
                    "World ditemukan, tetapi ukurannya %sx%s (diharapkan %dx%d)",
                    tostring(width), tostring(height), EXPECTED_W, EXPECTED_H
                )
            end

            return true, string.format("World ditemukan: %dx%d", width, height)
        end

        -- Mengikuti indeks tile pada module utama: world[layer][y][x].
        -- Koordinat X dan Y dimulai dari 0.
        local function readTile(x, y)
            local world = worldRef
            if not world or x < 0 or y < 0
                or x >= EXPECTED_W or y >= EXPECTED_H then
                return nil, nil
            end

            local fgLayer = safeRaw(world, "fg")
            local bgLayer = safeRaw(world, "bg")
            local fgRow = type(fgLayer) == "table" and fgLayer[y] or nil
            local bgRow = type(bgLayer) == "table" and bgLayer[y] or nil
            if type(fgRow) ~= "table" or type(bgRow) ~= "table" then
                return nil, nil
            end

            local fg = fgRow[x]
            local bg = bgRow[x]
            if fg == nil then fg = 0 end
            if bg == nil then bg = 0 end
            return fg, bg
        end

        local function tileColor(fg, bg)
            local hasFG = tonumber(fg) ~= nil and tonumber(fg) ~= 0
            local hasBG = tonumber(bg) ~= nil and tonumber(bg) ~= 0
            if hasFG and hasBG then return Theme.Both end
            if hasFG then return Theme.FG end
            if hasBG then return Theme.BG end
            return Theme.Empty
        end

        local function updateTileButton(x, y)
            local row = tileButtons[y]
            local button = row and row[x]
            if not button or not button.Parent then return end

            local fg, bg = readTile(x, y)
            if fg == nil or bg == nil then
                button.BackgroundColor3 = Theme.Empty
                button.Text = "?"
            else
                button.BackgroundColor3 = tileColor(fg, bg)
                button.Text = ""
            end

            if selected and selected.x == x and selected.y == y then
                button.BorderSizePixel = 2
                button.BorderColor3 = Theme.Selected
            else
                button.BorderSizePixel = 0
            end
        end

        local function showTileInfo(x, y)
            local fg, bg = readTile(x, y)
            if fg == nil or bg == nil then
                selected = { x = x, y = y }
                selectedLabel.Text = string.format(
                    "TILE X:%d Y:%d  |  FG: TIDAK TERBACA  |  BG: TIDAK TERBACA", x, y
                )
                updateTileButton(x, y)
                setStatus("Data tile tidak terbaca pada koordinat tersebut")
                return
            end

            local old = selected
            selected = { x = x, y = y }
            if old then updateTileButton(old.x, old.y) end
            updateTileButton(x, y)

            selectedLabel.Text = string.format(
                "TILE X:%d Y:%d  |  FG ID: %s  |  BG ID: %s",
                x, y, tostring(fg), tostring(bg)
            )
            setStatus(string.format("Tile (%d,%d) dipilih | FG=%s | BG=%s", x, y, tostring(fg), tostring(bg)))
        end

        local function buildGrid()
            if gridBuilt or not running then return end
            setStatus("Membuat 6.000 tile UI...")

            for y = 0, EXPECTED_H - 1 do
                tileButtons[y] = {}
                for x = 0, EXPECTED_W - 1 do
                    local tileX, tileY = x, y
                    local button = create("TextButton", {
                        Name = string.format("Tile_%d_%d", tileX, tileY),
                        Size = UDim2.fromOffset(CELL_SIZE, CELL_SIZE),
                        BackgroundColor3 = Theme.Empty,
                        BorderSizePixel = 0,
                        Text = "",
                        TextColor3 = Theme.White,
                        Font = Enum.Font.GothamBold,
                        TextSize = 7,
                        AutoButtonColor = true,
                        LayoutOrder = tileY * EXPECTED_W + tileX + 1,
                    }, mapScroll)
                    tileButtons[tileY][tileX] = button
                    track(button.Activated:Connect(function()
                        if running then showTileInfo(tileX, tileY) end
                    end))
                end
                if y % 5 == 4 then task.wait() end
                if not running then return end
            end

            gridBuilt = true
            setStatus("Grid 100x60 siap. Memuat data FG/BG...")
        end

        local function refreshMap()
            if refreshing or not running then return end
            if not worldRef then
                setStatus("World belum ditemukan. Tekan SCAN WORLD.")
                return
            end
            if not gridBuilt then
                buildGrid()
            end
            if not gridBuilt then return end

            refreshing = true
            setStatus("Memperbarui data 6.000 tile...")
            local count = 0
            for y = 0, EXPECTED_H - 1 do
                for x = 0, EXPECTED_W - 1 do
                    updateTileButton(x, y)
                    count += 1
                end
                if y % 3 == 2 then task.wait() end
                if not running then
                    refreshing = false
                    return
                end
            end
            refreshing = false
            setStatus("Refresh selesai: 100x60 tile | 6.000 tile diperiksa")
            if selected then showTileInfo(selected.x, selected.y) end
        end

        local function scanCycle()
            if scanning or not running then return end
            scanning = true
            local found, message = false, "World belum ditemukan"
            for attempt = 1, 30 do
                if not running then break end
                found, message = scanWorldOnce()
                if found then break end
                setStatus(string.format("Scan World %d/30 | %s", attempt, tostring(message)))
                task.wait(0.5)
            end
            scanning = false

            if found then
                setStatus(message .. " | menyiapkan peta")
                refreshMap()
            else
                setStatus("SCAN GAGAL: " .. tostring(message))
            end
        end

        --==================================================
        -- UI
        --==================================================
        create("UIListLayout", {
            Padding = UDim.new(0, 7),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, page)

        local header = makeButton("WORLD SCANNER - PLACED BLOCK", 36, page, Theme.PanelDark)
        header.TextColor3 = Theme.Text
        header.LayoutOrder = 1

        local panel = create("Frame", {
            Name = "WorldPlacedBlockScannerPanel",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            LayoutOrder = 2,
        }, page)
        corner(panel, 8)
        create("UIPadding", {
            PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
        }, panel)
        create("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, panel)

        statusLabel = makeLabel("STATUS: Menunggu scan world...", 34, panel)
        statusLabel.LayoutOrder = 1

        selectedLabel = makeLabel("TILE: belum dipilih | FG ID: - | BG ID: -", 38, panel)
        selectedLabel.LayoutOrder = 2

        local legend = create("Frame", {
            Name = "WorldScannerLegend",
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 1,
            LayoutOrder = 3,
        }, panel)
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 10),
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, legend)

        local function legendItem(label, color)
            local item = create("Frame", {
                Size = UDim2.fromOffset(76, 18),
                BackgroundTransparency = 1,
            }, legend)
            create("Frame", {
                Position = UDim2.fromOffset(0, 3),
                Size = UDim2.fromOffset(12, 12),
                BackgroundColor3 = color,
                BorderSizePixel = 0,
            }, item)
            create("TextLabel", {
                Position = UDim2.fromOffset(16, 0),
                Size = UDim2.fromOffset(60, 18),
                BackgroundTransparency = 1,
                Text = label,
                TextColor3 = Theme.Text,
                Font = Enum.Font.Gotham,
                TextSize = 9,
                TextXAlignment = Enum.TextXAlignment.Left,
            }, item)
            return item
        end

        legendItem("Kosong", Theme.Empty)
        legendItem("FG", Theme.FG)
        legendItem("BG", Theme.BG)
        legendItem("FG+BG", Theme.Both)

        local actionRow = create("Frame", {
            Name = "WorldScannerActions",
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundTransparency = 1,
            LayoutOrder = 4,
        }, panel)
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, actionRow)

        local scanButton = makeButton("SCAN WORLD", 32, actionRow, Theme.Accent)
        scanButton.Size = UDim2.new(0.34, -4, 1, 0)
        scanButton.LayoutOrder = 1
        local refreshButton = makeButton("REFRESH MAP", 32, actionRow, Theme.Green)
        refreshButton.Size = UDim2.new(0.33, -4, 1, 0)
        refreshButton.LayoutOrder = 2
        local clearButton = makeButton("CLEAR SELECT", 32, actionRow, Theme.PanelDark)
        clearButton.TextColor3 = Theme.Text
        clearButton.Size = UDim2.new(0.33, -4, 1, 0)
        clearButton.LayoutOrder = 3

        mapScroll = create("ScrollingFrame", {
            Name = "WorldScannerMapScroll",
            Size = UDim2.new(1, 0, 0, 390),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            ScrollBarThickness = 8,
            ScrollingDirection = Enum.ScrollingDirection.XY,
            CanvasSize = UDim2.fromOffset(
                EXPECTED_W * CELL_SIZE + (EXPECTED_W - 1) * CELL_GAP,
                EXPECTED_H * CELL_SIZE + (EXPECTED_H - 1) * CELL_GAP
            ),
            LayoutOrder = 5,
        }, panel)
        corner(mapScroll, 5)

        mapGrid = create("UIGridLayout", {
            CellSize = UDim2.fromOffset(CELL_SIZE, CELL_SIZE),
            CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP),
            FillDirection = Enum.FillDirection.Horizontal,
            FillDirectionMaxCells = EXPECTED_W,
            SortOrder = Enum.SortOrder.LayoutOrder,
            StartCorner = Enum.StartCorner.TopLeft,
        }, mapScroll)

        track(header.Activated:Connect(function()
            panel.Visible = not panel.Visible
            header.Text = panel.Visible and "WORLD SCANNER - PLACED BLOCK  ▲"
                or "WORLD SCANNER - PLACED BLOCK  ▼"
        end))

        track(scanButton.Activated:Connect(function()
            if refreshing then
                setStatus("Tunggu refresh selesai sebelum scan ulang")
                return
            end
            worldRef = nil
            task.spawn(scanCycle)
        end))

        track(refreshButton.Activated:Connect(function()
            if not worldRef then
                task.spawn(scanCycle)
            else
                task.spawn(refreshMap)
            end
        end))

        track(clearButton.Activated:Connect(function()
            local old = selected
            selected = nil
            if old then updateTileButton(old.x, old.y) end
            selectedLabel.Text = "TILE: belum dipilih | FG ID: - | BG ID: -"
            setStatus("Pilihan tile dibersihkan")
        end))

        local function cleanup()
            if not running then return end
            running = false
            for _, connection in ipairs(connections) do
                pcall(function() connection:Disconnect() end)
            end
            table.clear(connections)
            table.clear(tileButtons)
            worldRef = nil
            log("MODULE DITUTUP; seluruh koneksi UI diputus")
        end

        Hub.RegisterCleanup(cleanup)
        setStatus("Module dimuat. Memulai scan world...")
        task.spawn(scanCycle)
        print("[WORLD SCANNER] Module loaded.")
    end)
end

--==================================================
-- END MODULE: WORLD PLACED BLOCK SCANNER
--==================================================
