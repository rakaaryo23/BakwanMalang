--==================================================
-- MODULE: PLAYER / WORLD / PLAYER STATE READER
-- Module mandiri untuk diagnostik akun, world, dan PlayerState.
--
-- FITUR:
-- 1. Menampilkan akun LocalPlayer.
-- 2. Menemukan referensi World dan PlayerState.state melalui getgc(true).
-- 3. Menampilkan data World yang berhasil divalidasi.
-- 4. Membaca PlayerState secara real-time, termasuk nilai RAW facing.
-- 5. Tidak memasang hook, tidak mengubah input, dan tidak mengubah state game.
--
-- CATATAN:
-- Nilai facing sengaja ditampilkan apa adanya (tostring + tipe data).
-- Module ini TIDAK mengasumsikan 1=LEFT, 2=RIGHT atau pemetaan lainnya.
--==================================================

return function(Hub)

    Hub.RegisterTab("PLAYER STATE READER", function(page)

        --==================================================
        -- [01] SERVICES & STATE
        --==================================================

        local Players = game:GetService("Players")
        local LocalPlayer = Players.LocalPlayer

        local running = true
        local scanning = false
        local connected = false
        local stateFn = nil
        local worldRef = nil
        local lastScanMessage = "Belum melakukan scan."
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

        --==================================================
        -- [02] UI HELPERS
        --==================================================

        local function create(className, properties, parent)
            local object = Instance.new(className)
            for property, value in pairs(properties or {}) do
                object[property] = value
            end
            object.Parent = parent or page
            return object
        end

        local function corner(object, radius)
            local item = Instance.new("UICorner")
            item.CornerRadius = UDim.new(0, radius or 7)
            item.Parent = object
            return item
        end

        local function makeLabel(text, height, parent, color, size)
            return create("TextLabel", {
                Size = UDim2.new(1, 0, 0, height or 24),
                BackgroundTransparency = 1,
                Text = text or "",
                TextColor3 = color or Theme.Text,
                Font = Enum.Font.Gotham,
                TextSize = size or 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Center,
                TextWrapped = true,
            }, parent)
        end

        local function makeSection(titleText)
            local frame = create("Frame", {
                Size = UDim2.new(1, 0, 0, 10),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.Panel,
                BorderSizePixel = 0,
            }, page)
            corner(frame, 8)

            local padding = Instance.new("UIPadding")
            padding.PaddingTop = UDim.new(0, 8)
            padding.PaddingBottom = UDim.new(0, 8)
            padding.PaddingLeft = UDim.new(0, 10)
            padding.PaddingRight = UDim.new(0, 10)
            padding.Parent = frame

            local layout = Instance.new("UIListLayout")
            layout.Padding = UDim.new(0, 3)
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.Parent = frame

            makeLabel(titleText, 22, frame, Theme.Accent, 12).Font = Enum.Font.GothamBold
            return frame
        end

        local function makeButton(text, parent)
            local button = create("TextButton", {
                Size = UDim2.new(1, 0, 0, 34),
                BackgroundColor3 = Theme.Accent,
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

        local pageLayout = Instance.new("UIListLayout")
        pageLayout.Padding = UDim.new(0, 8)
        pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
        pageLayout.Parent = page

        --==================================================
        -- [03] ACCOUNT PANEL
        --==================================================

        local accountPanel = makeSection("ACCOUNT")
        local accountNameLabel = makeLabel("-", 22, accountPanel)
        local displayNameLabel = makeLabel("-", 22, accountPanel)
        local userIdLabel = makeLabel("-", 22, accountPanel)

        local function updateAccount()
            if not LocalPlayer then
                accountNameLabel.Text = "Username: LocalPlayer tidak tersedia"
                displayNameLabel.Text = "DisplayName: -"
                userIdLabel.Text = "UserId: -"
                return
            end

            accountNameLabel.Text = "Username: " .. tostring(LocalPlayer.Name)
            displayNameLabel.Text = "DisplayName: " .. tostring(LocalPlayer.DisplayName)
            userIdLabel.Text = "UserId: " .. tostring(LocalPlayer.UserId)
        end

        --==================================================
        -- [04] WORLD DISCOVERY & DISPLAY
        --==================================================

        local worldPanel = makeSection("WORLD")
        local worldStatusLabel = makeLabel("Status: belum discan", 22, worldPanel)
        local worldNameLabel = makeLabel("Nama/identifier: -", 22, worldPanel)
        local worldSizeLabel = makeLabel("Ukuran: -", 22, worldPanel)
        local worldSpawnLabel = makeLabel("Spawn: -", 22, worldPanel)

        local function safeRaw(object, key)
            if type(object) ~= "table" then return nil end
            local ok, value = pcall(rawget, object, key)
            if ok then return value end
            return nil
        end

        local function validWorld(object)
            return type(object) == "table"
                and type(safeRaw(object, "fg")) == "table"
                and type(safeRaw(object, "bg")) == "table"
                and type(safeRaw(object, "w")) == "number"
                and type(safeRaw(object, "h")) == "number"
                and safeRaw(object, "spawn") ~= nil
        end

        local function firstReadableField(object, keys)
            for _, key in ipairs(keys) do
                local value = safeRaw(object, key)
                if type(value) == "string" or type(value) == "number" then
                    if tostring(value) ~= "" then
                        return key .. "=" .. tostring(value)
                    end
                end
            end
            return nil
        end

        local function updateWorldDisplay()
            if not worldRef then
                worldStatusLabel.Text = "Status: World belum ditemukan"
                worldNameLabel.Text = "Nama/identifier: -"
                worldSizeLabel.Text = "Ukuran: -"
                worldSpawnLabel.Text = "Spawn: -"
                return
            end

            local w = safeRaw(worldRef, "w")
            local h = safeRaw(worldRef, "h")
            local spawn = safeRaw(worldRef, "spawn")
            local nameInfo = firstReadableField(worldRef, {
                "name", "worldName", "world", "id", "worldId"
            })

            worldStatusLabel.Text = "Status: World ditemukan"
            worldNameLabel.Text = "Nama/identifier: " .. (nameInfo or "field nama belum diketahui")
            worldSizeLabel.Text = string.format(
                "Ukuran: %s x %s tile",
                tostring(w), tostring(h)
            )
            worldSpawnLabel.Text = "Spawn: " .. tostring(spawn)
        end

        --==================================================
        -- [05] PLAYER STATE DISCOVERY
        --==================================================

        local statePanel = makeSection("PLAYER STATE | REAL-TIME")
        local stateStatusLabel = makeLabel("Status: belum discan", 22, statePanel)
        local positionLabel = makeLabel("Posisi: -", 22, statePanel)
        local velocityLabel = makeLabel("Velocity: -", 22, statePanel)
        local facingLabel = makeLabel("FACING RAW: -", 30, statePanel, Theme.Accent, 14)
        local facingTypeLabel = makeLabel("Tipe facing: -", 22, statePanel)
        local activeLabel = makeLabel("Active: -", 22, statePanel)
        local stateOtherLabel = makeLabel("Field tambahan: -", 22, statePanel, Theme.Muted)

        local function validPlayerStateFunction(candidate)
            if type(candidate) ~= "function" then return nil end

            local ok, state = pcall(candidate)
            if not ok or type(state) ~= "table" then return nil end

            if type(state.x) ~= "number"
                or type(state.y) ~= "number"
                or state.facing == nil
                or state.vx == nil then
                return nil
            end

            if state.active == false then return nil end
            return state
        end

        local function scanRuntime()
            if scanning then return end
            scanning = true
            connected = false
            stateFn = nil
            worldRef = nil

            if type(getgc) ~= "function" then
                lastScanMessage = "Executor tidak menyediakan getgc."
                scanning = false
                updateWorldDisplay()
                stateStatusLabel.Text = "Status: " .. lastScanMessage
                return
            end

            local ok, objects = pcall(getgc, true)
            if not ok or type(objects) ~= "table" then
                lastScanMessage = "getgc(true) gagal: " .. tostring(objects)
                scanning = false
                updateWorldDisplay()
                stateStatusLabel.Text = "Status: " .. lastScanMessage
                return
            end

            for _, object in ipairs(objects) do
                if type(object) == "table" then
                    if not worldRef and validWorld(object) then
                        worldRef = object
                    end

                    if not stateFn then
                        local candidate = safeRaw(object, "state")
                        if validPlayerStateFunction(candidate) then
                            stateFn = candidate
                        end
                    end

                    if worldRef and stateFn then
                        break
                    end
                end
            end

            connected = worldRef ~= nil and stateFn ~= nil
            if connected then
                lastScanMessage = "Scan berhasil: World dan PlayerState ditemukan."
            else
                local missing = {}
                if not worldRef then table.insert(missing, "World") end
                if not stateFn then table.insert(missing, "PlayerState.state") end
                lastScanMessage = "Belum lengkap: " .. table.concat(missing, ", ")
            end

            scanning = false
            updateWorldDisplay()
            stateStatusLabel.Text = "Status: " .. lastScanMessage
        end

        --==================================================
        -- [06] REAL-TIME STATE READER
        --==================================================

        local function updatePlayerState()
            if not stateFn then
                stateStatusLabel.Text = "Status: menunggu scan PlayerState"
                positionLabel.Text = "Posisi: -"
                velocityLabel.Text = "Velocity: -"
                facingLabel.Text = "FACING RAW: -"
                facingTypeLabel.Text = "Tipe facing: -"
                activeLabel.Text = "Active: -"
                stateOtherLabel.Text = "Field tambahan: -"
                return
            end

            local ok, state = pcall(stateFn)
            if not ok or type(state) ~= "table" then
                connected = false
                stateStatusLabel.Text = "Status: gagal membaca PlayerState: " .. tostring(state)
                return
            end

            local facing = state.facing
            local vx = state.vx
            local vy = state.vy

            connected = true
            stateStatusLabel.Text = "Status: PlayerState terbaca real-time"
            positionLabel.Text = string.format(
                "Posisi: x=%s | y=%s",
                tostring(state.x), tostring(state.y)
            )
            velocityLabel.Text = string.format(
                "Velocity: vx=%s | vy=%s",
                tostring(vx), tostring(vy)
            )
            facingLabel.Text = "FACING RAW: " .. tostring(facing)
            facingTypeLabel.Text = "Tipe facing: " .. typeof(facing)
            activeLabel.Text = "Active: " .. tostring(state.active)

            local extras = {}
            for _, key in ipairs({"grounded", "onGround", "jumping", "moving"}) do
                local value = state[key]
                if value ~= nil then
                    table.insert(extras, key .. "=" .. tostring(value))
                end
            end
            stateOtherLabel.Text = "Field tambahan: "
                .. (#extras > 0 and table.concat(extras, " | ") or "tidak ada dari field yang dikenal")
        end

        --==================================================
        -- [07] CONTROLS
        --==================================================

        local controlPanel = makeSection("CONTROL")
        local scanButton = makeButton("SCAN / RE-SCAN WORLD + PLAYER STATE", controlPanel)
        local scanFeedbackLabel = makeLabel("Scan: belum dijalankan", 22, controlPanel, Theme.Muted)

        table.insert(connections, scanButton.MouseButton1Click:Connect(function()
            if not running then return end
            scanFeedbackLabel.Text = "Scan: sedang mencari objek runtime..."
            scanRuntime()
            scanFeedbackLabel.Text = "Scan: " .. lastScanMessage
        end))

        --==================================================
        -- [08] CLEANUP & UPDATE LOOP
        --==================================================

        updateAccount()
        updateWorldDisplay()

        task.spawn(function()
            while running do
                updatePlayerState()
                task.wait(0.1)
            end
        end)

        local function cleanup()
            if not running then return end
            running = false
            for _, connection in ipairs(connections) do
                pcall(function()
                    connection:Disconnect()
                end)
            end
            table.clear(connections)
        end

        Hub.RegisterCleanup(cleanup)

        print("[PLAYER STATE READER] Module loaded.")
    end)

end
