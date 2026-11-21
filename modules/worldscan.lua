--==================================================
-- MODULE: SCAN FULL ROW ABOVE / BELOW PLAYER
-- Scan seluruh tile dalam satu baris world (biasanya 100 tile).
-- Tombol terpisah:
--   1) SCAN BARIS DI ATAS PLAYER
--   2) SCAN BARIS DI BAWAH PLAYER
-- Menampilkan koordinat tile dengan FG=0 dan BG=0.
--
-- Referensi mengikuti main.lua:
--   state() -> {x, y, facing, vx, ...}
--   world.fg[y][x], world.bg[y][x]
-- Koordinat world 0-based.
--==================================================

return function(Hub)
    Hub.RegisterTab("SCAN BARIS PLAYER", function(page)
        local destroyed = false
        local refs = {
            world = nil,
            stateFn = nil,
        }
        local connections = {}

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
            table.insert(connections, connection)
            return connection
        end

        local function safeRaw(t, key)
            if type(t) ~= "table" then return nil end
            local ok, value = pcall(rawget, t, key)
            return ok and value or nil
        end

        local function makeLabel(text, height, parent, bold)
            return create("TextLabel", {
                Size = UDim2.new(1, 0, 0, height or 28),
                BackgroundTransparency = 1,
                Text = text or "",
                TextColor3 = Theme.Text,
                Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Center,
                TextWrapped = true,
            }, parent)
        end

        local function makeButton(text, parent, color)
            local button = create("TextButton", {
                Size = UDim2.new(1, 0, 0, 36),
                BackgroundColor3 = color or Theme.Accent,
                BorderSizePixel = 0,
                Text = text,
                TextColor3 = Theme.White,
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                AutoButtonColor = true,
            }, parent)
            corner(button, 7)
            return button
        end

        local container = create("Frame", {
            Name = "ScanPlayerRowsPanel",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
        }, page)
        corner(container, 8)

        create("UIPadding", {
            PaddingTop = UDim.new(0, 8),
            PaddingBottom = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 8),
            PaddingRight = UDim.new(0, 8),
        }, container)

        create("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, container)

        local title = makeLabel("SCAN FULL ROW PLAYER", 25, container, true)
        title.LayoutOrder = 1

        local playerLabel = makeLabel(
            "Player State: menunggu scan\nPlayer Tile: -",
            42, container
        )
        playerLabel.LayoutOrder = 2

        local aboveButton = makeButton(
            "SCAN 100 TILE DI ATAS PLAYER", container, Theme.Accent
        )
        aboveButton.LayoutOrder = 3

        local belowButton = makeButton(
            "SCAN 100 TILE DI BAWAH PLAYER", container, Theme.PanelDark
        )
        belowButton.TextColor3 = Theme.Text
        belowButton.LayoutOrder = 4

        local resultTitle = makeLabel(
            "HASIL: belum ada scan", 28, container, true
        )
        resultTitle.LayoutOrder = 5

        local resultFrame = create("ScrollingFrame", {
            Name = "EmptyTileCoordinates",
            Size = UDim2.new(1, 0, 0, 180),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            ScrollBarThickness = 5,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
        }, container)
        resultFrame.LayoutOrder = 6
        corner(resultFrame, 6)

        create("UIPadding", {
            PaddingTop = UDim.new(0, 6),
            PaddingBottom = UDim.new(0, 6),
            PaddingLeft = UDim.new(0, 7),
            PaddingRight = UDim.new(0, 7),
        }, resultFrame)

        local resultLayout = create("UIListLayout", {
            Padding = UDim.new(0, 3),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, resultFrame)

        local resultText = makeLabel(
            "Koordinat tile FG=0 dan BG=0 akan muncul di sini.",
            40, resultFrame
        )
        resultText.AutomaticSize = Enum.AutomaticSize.Y
        resultText.Size = UDim2.new(1, -4, 0, 0)
        resultText.TextYAlignment = Enum.TextYAlignment.Top
        resultText.TextWrapped = true
        resultText.LayoutOrder = 1

        local function validWorld(candidate)
            return type(candidate) == "table"
                and type(safeRaw(candidate, "fg")) == "table"
                and type(safeRaw(candidate, "bg")) == "table"
                and type(safeRaw(candidate, "w")) == "number"
                and type(safeRaw(candidate, "h")) == "number"
                and safeRaw(candidate, "spawn") ~= nil
        end

        local function readState(fn)
            if type(fn) ~= "function" then return nil end
            local ok, value = pcall(fn)
            if not ok or type(value) ~= "table" then return nil end
            if type(value.x) ~= "number" or type(value.y) ~= "number" then
                return nil
            end
            if value.facing == nil or value.vx == nil then return nil end
            if value.active == false then return nil end
            return value
        end

        local function discoverRefs()
            if type(getgc) ~= "function" then
                return false, "Executor tidak menyediakan getgc"
            end

            local ok, objects = pcall(getgc, true)
            if not ok or type(objects) ~= "table" then
                return false, "getgc(true) gagal: " .. tostring(objects)
            end

            local foundWorld, foundStateFn
            for _, object in ipairs(objects) do
                if type(object) == "table" then
                    if not foundWorld and validWorld(object) then
                        foundWorld = object
                    end

                    if not foundStateFn then
                        local candidateFn = safeRaw(object, "state")
                        if readState(candidateFn) then
                            foundStateFn = candidateFn
                        end
                    end

                    if foundWorld and foundStateFn then
                        break
                    end
                end
            end

            if foundWorld then refs.world = foundWorld end
            if foundStateFn then refs.stateFn = foundStateFn end

            if not refs.world or not refs.stateFn then
                return false,
                    "Referensi belum lengkap: world="
                    .. tostring(refs.world ~= nil)
                    .. ", playerState="
                    .. tostring(refs.stateFn ~= nil)
            end

            return true
        end

        local function getPlayerAndWorld()
            if not refs.world or not refs.stateFn then
                local ok, message = discoverRefs()
                if not ok then return nil, nil, nil, nil, message end
            end

            local state = readState(refs.stateFn)
            if not state then
                refs.stateFn = nil
                local ok, message = discoverRefs()
                if not ok then return nil, nil, nil, nil, message end
                state = readState(refs.stateFn)
            end

            if not state then
                return nil, nil, nil, nil, "Player state tidak terbaca"
            end

            local world = refs.world
            local width = tonumber(safeRaw(world, "w"))
            local height = tonumber(safeRaw(world, "h"))
            if not width or not height then
                refs.world = nil
                return nil, nil, nil, nil, "Ukuran world tidak valid"
            end

            -- Formula tile player disamakan dengan main.lua.
            local playerX = math.floor(state.x)
            local playerY = math.floor(state.y - 0.475)

            playerLabel.Text = string.format(
                "Player State: X %.3f | Y %.3f\nPlayer Tile: X %d | Y %d | World: %dx%d",
                state.x, state.y, playerX, playerY, width, height
            )

            return playerX, playerY, width, height
        end

        local function getTileValue(layer, x, y)
            local world = refs.world
            local layerTable = safeRaw(world, layer)
            if type(layerTable) ~= "table" then return nil end

            local row = safeRaw(layerTable, y)
            if type(row) ~= "table" then return nil end

            local value = safeRaw(row, x)
            if value == nil then return 0 end
            return value
        end

        local function setResults(lines)
            resultText.Text = table.concat(lines, "\n")
            resultFrame.CanvasPosition = Vector2.new(0, 0)
        end

        local function scanFullRow(direction)
            if destroyed or Hub.IsClosing() then return end

            local playerX, playerY, width, height, errorMessage =
                getPlayerAndWorld()

            if not playerX then
                resultTitle.Text = "SCAN GAGAL"
                setResults({ tostring(errorMessage or "Player/world tidak terbaca") })
                warn("[SCAN PLAYER ROW]", errorMessage)
                return
            end

            -- Satu baris penuh: Y player - 1 untuk atas, Y player + 1 untuk bawah.
            local targetY = playerY + direction
            local rowName = direction < 0 and "DI ATAS" or "DI BAWAH"

            if targetY < 0 or targetY >= height then
                resultTitle.Text = "SCAN GAGAL"
                setResults({
                    ("Baris Y=%d berada di luar world (tinggi %d).")
                        :format(targetY, height)
                })
                return
            end

            local emptyCoordinates = {}
            local unreadable = {}
            local checked = 0

            for x = 0, width - 1 do
                local fg = getTileValue("fg", x, targetY)
                local bg = getTileValue("bg", x, targetY)

                if fg == nil or bg == nil then
                    unreadable[#unreadable + 1] = x
                else
                    checked += 1
                    if fg == 0 and bg == 0 then
                        emptyCoordinates[#emptyCoordinates + 1] = x
                    end
                end
            end

            local lines = {}
            lines[#lines + 1] = string.format(
                "BARIS %s | Y=%d | DICEK %d/%d TILE",
                rowName, targetY, checked, width
            )
            lines[#lines + 1] = string.format(
                "TILE KOSONG (FG=0, BG=0): %d",
                #emptyCoordinates
            )

            if #emptyCoordinates > 0 then
                lines[#lines + 1] = "KOORDINAT (X,Y):"
                local coordinateParts = {}
                for _, x in ipairs(emptyCoordinates) do
                    coordinateParts[#coordinateParts + 1] =
                        string.format("(%d,%d)", x, targetY)
                end

                -- Pecah menjadi beberapa baris agar hasil tetap terbaca.
                for startIndex = 1, #coordinateParts, 8 do
                    local chunk = {}
                    for i = startIndex, math.min(startIndex + 7, #coordinateParts) do
                        chunk[#chunk + 1] = coordinateParts[i]
                    end
                    lines[#lines + 1] = table.concat(chunk, "  ")
                end
            else
                lines[#lines + 1] = "Tidak ditemukan tile dengan FG=0 dan BG=0."
            end

            if #unreadable > 0 then
                lines[#lines + 1] = "BARIS TIDAK TERBACA PADA X:"
                local parts = {}
                for _, x in ipairs(unreadable) do
                    parts[#parts + 1] = tostring(x)
                end
                lines[#lines + 1] = table.concat(parts, ", ")
            end

            resultTitle.Text = string.format(
                "HASIL %s | Y=%d | EMPTY %d",
                rowName, targetY, #emptyCoordinates
            )
            resultTitle.TextColor3 =
                (#emptyCoordinates > 0) and Theme.Green or Theme.Text

            setResults(lines)
            print(
                "[SCAN PLAYER ROW]",
                rowName,
                "Y=" .. tostring(targetY),
                "EMPTY=" .. tostring(#emptyCoordinates),
                table.concat(emptyCoordinates, ",")
            )
        end

        track(aboveButton.Activated:Connect(function()
            scanFullRow(-1)
        end))

        track(belowButton.Activated:Connect(function()
            scanFullRow(1)
        end))

        local function cleanup()
            if destroyed then return end
            destroyed = true

            for _, connection in ipairs(connections) do
                pcall(function()
                    connection:Disconnect()
                end)
            end
            table.clear(connections)
        end

        Hub.RegisterCleanup(cleanup)
        print("[SCAN PLAYER ROW] Module loaded.")
    end)
end
