--==================================================
-- MODULE: SCAN 1 BLOCK ABOVE PLAYER
-- Membaca FG dan BG pada tile tepat 1 block di atas player.
-- Sumber posisi/world mengikuti pola discovery pada main.lua:
--   state() -> {x, y, facing, vx, ...}
--   world.fg[y][x], world.bg[y][x]
-- Koordinat world menggunakan index 0-based.
--==================================================

return function(Hub)
    Hub.RegisterTab("SCAN ABOVE PLAYER", function(page)
        local Players = game:GetService("Players")
        local LocalPlayer = Players.LocalPlayer

        local destroyed = false
        local live = false
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
                Size = UDim2.new(1, 0, 0, 34),
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
            Name = "ScanAbovePlayerPanel",
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

        local title = makeLabel("SCAN 1 BLOCK ABOVE PLAYER", 25, container, true)
        title.LayoutOrder = 1

        local infoLabel = makeLabel(
            "Player: menunggu scan\nTile atas: -\nFG ID: - | BG ID: -",
            68, container
        )
        infoLabel.LayoutOrder = 2

        local statusLabel = makeLabel("Status: belum scan", 30, container)
        statusLabel.TextColor3 = Theme.Muted
        statusLabel.LayoutOrder = 3

        local scanButton = makeButton("SCAN ABOVE PLAYER", container, Theme.Accent)
        scanButton.LayoutOrder = 4

        local liveButton = makeButton("LIVE SCAN: OFF", container, Theme.PanelDark)
        liveButton.TextColor3 = Theme.Text
        liveButton.LayoutOrder = 5

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

            return true, "World dan playerState ditemukan"
        end

        local function readTile(layer, x, y)
            local world = refs.world
            if not world then return nil end

            local width = tonumber(safeRaw(world, "w"))
            local height = tonumber(safeRaw(world, "h"))
            if not width or not height
                or x < 0 or y < 0 or x >= width or y >= height then
                return nil
            end

            local layerTable = safeRaw(world, layer)
            local row = type(layerTable) == "table" and safeRaw(layerTable, y)
            if type(row) ~= "table" then return 0 end

            local value = safeRaw(row, x)
            if value == nil then return 0 end
            return value
        end

        local function scanAbovePlayer()
            if not refs.world or not refs.stateFn then
                local ok, message = discoverRefs()
                if not ok then
                    return false, message
                end
            end

            local state = readState(refs.stateFn)
            if not state then
                refs.stateFn = nil
                return false, "Player state tidak terbaca; tekan SCAN lagi"
            end

            -- Formula tile player sama seperti main.lua:
            -- X = floor(state.x), Y = floor(state.y - 0.475)
            local playerX = math.floor(state.x)
            local playerY = math.floor(state.y - 0.475)

            -- Target adalah tepat satu tile di atas tile player.
            local targetX = playerX
            local targetY = playerY - 1

            local fg = readTile("fg", targetX, targetY)
            local bg = readTile("bg", targetX, targetY)

            if fg == nil or bg == nil then
                return false, ("Tile (%d,%d) di luar world / tidak terbaca")
                    :format(targetX, targetY)
            end

            infoLabel.Text = string.format(
                "Player State: X %.3f | Y %.3f\n"
                .. "Player Tile: X %d | Y %d\n"
                .. "1 Block Above: X %d | Y %d\n"
                .. "FG ID: %s | BG ID: %s",
                state.x, state.y,
                playerX, playerY,
                targetX, targetY,
                tostring(fg), tostring(bg)
            )

            statusLabel.Text = "Status: scan berhasil"
            statusLabel.TextColor3 = Theme.Green
            return true, string.format(
                "Tile (%d,%d) | FG=%s | BG=%s",
                targetX, targetY, tostring(fg), tostring(bg)
            )
        end

        track(scanButton.Activated:Connect(function()
            local ok, message = scanAbovePlayer()
            statusLabel.Text = "Status: " .. tostring(message)
            if not ok then statusLabel.TextColor3 = Theme.Red end
            print("[SCAN ABOVE PLAYER]", message)
        end))

        track(liveButton.Activated:Connect(function()
            live = not live
            liveButton.Text = live and "LIVE SCAN: ON" or "LIVE SCAN: OFF"
            liveButton.BackgroundColor3 = live and Theme.Green or Theme.PanelDark
            liveButton.TextColor3 = live and Theme.White or Theme.Text

            if live then
                task.spawn(function()
                    while live and not destroyed
                        and not Hub.IsClosing()
                        and page.Parent do
                        local ok, message = scanAbovePlayer()
                        if not ok then
                            statusLabel.Text = "Status: " .. tostring(message)
                            statusLabel.TextColor3 = Theme.Red
                        end
                        task.wait(0.2)
                    end
                end)
            end
        end))

        local function cleanup()
            if destroyed then return end
            destroyed = true
            live = false

            for _, connection in ipairs(connections) do
                pcall(function()
                    connection:Disconnect()
                end)
            end
            table.clear(connections)
        end

        Hub.RegisterCleanup(cleanup)
        print("[SCAN ABOVE PLAYER] Module loaded.")
    end)
end
