--==================================================
-- MODULE: GERAK KIRI / KANAN / JUMP
-- Standalone untuk GrowBlox Hub.
--
-- Mekanisme input mengikuti pola k(8).lua:
--   AutoInput.active + AutoInput.left/right/jump/down
--   WorldMenu.isDown(saved, key, ...)
--
-- Tidak membaca state dari k.lua dan tidak menjalankan k.lua.
--==================================================

return function(Hub)
    assert(Hub and type(Hub.RegisterTab) == "function",
        "Module Gerak membutuhkan Hub.RegisterTab")
    assert(type(Hub.RegisterCleanup) == "function",
        "Hub.RegisterCleanup tidak tersedia")

    Hub.RegisterTab("Gerak", function(page)
        local Players = game:GetService("Players")
        local UserInputService = game:GetService("UserInputService")
        local LocalPlayer = Players.LocalPlayer

        -- State virtual milik modul ini sendiri.
        -- Bentuk dan nama field mengikuti AutoInput pada k(8).lua.
        local AutoInput = {
            active = false,
            left = false,
            right = false,
            jump = false,
            down = false,
        }

        local destroyed = false
        local connections = {}
        local heldInputs = {
            left = {},
            right = {},
            jump = {},
        }
        local buttons = {}

        local MenuModule = nil
        local OrigIsDown = nil
        local isDownWrapper = nil
        local hookReady = false
        local readCount = 0
        local lastKey = "belum ada"

        local Theme = {
            Accent = Color3.fromRGB(171, 91, 119),
            Active = Color3.fromRGB(65, 155, 105),
            Text = Color3.fromRGB(76, 43, 57),
            White = Color3.fromRGB(255, 249, 251),
            Muted = Color3.fromRGB(139, 96, 111),
        }

        local function track(connection)
            table.insert(connections, connection)
            return connection
        end

        local function create(className, properties, parent)
            local object = Instance.new(className)
            for property, value in pairs(properties or {}) do
                object[property] = value
            end
            object.Parent = parent or page
            return object
        end

        local function addCorner(object, radius)
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, radius or 8)
            corner.Parent = object
        end

        local panel = create("Frame", {
            Name = "GerakPanel",
            Size = UDim2.new(1, 0, 0, 116),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        })

        local buttonRow = create("Frame", {
            Name = "ButtonRow",
            Size = UDim2.new(1, 0, 0, 48),
            BackgroundTransparency = 1,
        }, panel)

        create("UIGridLayout", {
            CellSize = UDim2.new(1 / 3, -6, 1, 0),
            CellPadding = UDim2.fromOffset(6, 0),
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, buttonRow)

        local status = create("TextLabel", {
            Name = "GerakStatus",
            Position = UDim2.fromOffset(0, 54),
            Size = UDim2.new(1, 0, 0, 58),
            BackgroundTransparency = 1,
            Text = "Status: mencari GameGui.WorldMenu...",
            TextColor3 = Theme.Text,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
        }, panel)

        local function updateStatus(message)
            if not status or not status.Parent then return end
            local mode = AutoInput.active and "virtual input aktif" or "input game normal"
            status.Text = string.format(
                "Status: %s\nMode: %s | Dibaca game: %s (%d)",
                message or (hookReady and "WorldMenu terhubung" or "menunggu WorldMenu"),
                mode,
                lastKey,
                readCount
            )
        end

        local function anyPressed()
            return AutoInput.left or AutoInput.right or AutoInput.jump or AutoInput.down
        end

        local function syncActive()
            -- Saat tidak ada tombol virtual ditekan, fungsi asli game berjalan
            -- tanpa intervensi. Saat ada tombol ditekan, wrapper mengambil alih
            -- keempat key logical sama seperti AutoInput.active di k(8).lua.
            AutoInput.active = anyPressed()
        end

        local function setPressed(key, value)
            if destroyed then return end

            AutoInput[key] = value == true
            syncActive()

            local button = buttons[key]
            if button and button.Parent then
                button.BackgroundColor3 = AutoInput[key] and Theme.Active or Theme.Accent
            end
            updateStatus()
        end

        local function releaseAll()
            for _, key in ipairs({ "left", "right", "jump" }) do
                AutoInput[key] = false
                heldInputs[key] = {}
                local button = buttons[key]
                if button and button.Parent then
                    button.BackgroundColor3 = Theme.Accent
                end
            end
            AutoInput.down = false
            syncActive()
            updateStatus()
        end

        -- Salinan pola wrapper k(8).lua. Nama argumen dan urutan pemeriksaan
        -- sengaja dipertahankan: saved, key, ...
        local function installMovementHook()
            local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
            local gameGui = playerGui and playerGui:FindFirstChild("GameGui")
            local worldMenu = gameGui and gameGui:FindFirstChild("WorldMenu")

            if not worldMenu or not worldMenu:IsA("ModuleScript") then
                return false, "GameGui.WorldMenu belum ditemukan"
            end

            local ok, result = pcall(require, worldMenu)
            if not ok then
                return false, "require WorldMenu gagal: " .. tostring(result)
            end
            if type(result) ~= "table" then
                return false, "WorldMenu tidak mengembalikan table"
            end
            if type(rawget(result, "isDown")) ~= "function" then
                return false, "WorldMenu.isDown bukan function"
            end

            -- Hindari membungkus fungsi yang sama berulang kali.
            if MenuModule == result and result.isDown == isDownWrapper then
                hookReady = true
                return true
            end

            MenuModule = result
            OrigIsDown = rawget(MenuModule, "isDown")

            local function movementIsDown(saved, key, ...)
                if AutoInput.active then
                    if key == "keyLeft" then
                        readCount += 1
                        lastKey = key
                        return AutoInput.left
                    end
                    if key == "keyRight" then
                        readCount += 1
                        lastKey = key
                        return AutoInput.right
                    end
                    if key == "keyJump" then
                        readCount += 1
                        lastKey = key
                        return AutoInput.jump
                    end
                    if key == "keyDown" then
                        readCount += 1
                        lastKey = key
                        return AutoInput.down
                    end
                end

                return OrigIsDown(saved, key, ...)
            end

            isDownWrapper = movementIsDown

            local assigned, assignError = pcall(function()
                MenuModule.isDown = isDownWrapper
            end)
            if not assigned or rawget(MenuModule, "isDown") ~= isDownWrapper then
                hookReady = false
                return false, "gagal memasang WorldMenu.isDown: " .. tostring(assignError)
            end

            hookReady = true
            updateStatus("WorldMenu.isDown berhasil dipasang")
            print("[Gerak] WorldMenu.isDown terhubung memakai pola AutoInput k(8).lua.")
            return true
        end

        local function makeHoldButton(key, title)
            local button = create("TextButton", {
                Name = title .. "Button",
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                Text = title,
                TextColor3 = Theme.White,
                Font = Enum.Font.GothamBold,
                TextSize = 13,
                AutoButtonColor = false,
                Active = true,
                Selectable = false,
            }, buttonRow)
            addCorner(button, 8)
            buttons[key] = button

            track(button.InputBegan:Connect(function(input)
                if destroyed then return end
                local inputType = input.UserInputType
                if inputType == Enum.UserInputType.MouseButton1
                    or inputType == Enum.UserInputType.Touch then
                    heldInputs[key][input] = true
                    setPressed(key, true)
                end
            end))

            track(button.InputEnded:Connect(function(input)
                if heldInputs[key][input] then
                    heldInputs[key][input] = nil
                    setPressed(key, next(heldInputs[key]) ~= nil)
                end
            end))
        end

        makeHoldButton("left", "KIRI")
        makeHoldButton("right", "KANAN")
        makeHoldButton("jump", "JUMP")

        -- Menangani jari/mouse yang dilepas di luar area tombol.
        track(UserInputService.InputEnded:Connect(function(input)
            for _, key in ipairs({ "left", "right", "jump" }) do
                if heldInputs[key][input] then
                    heldInputs[key][input] = nil
                    setPressed(key, next(heldInputs[key]) ~= nil)
                end
            end
        end))

        pcall(function()
            track(UserInputService.WindowFocusReleased:Connect(function()
                releaseAll()
            end))
        end)

        local function cleanup()
            if destroyed then return end
            releaseAll()
            destroyed = true

            -- Kembalikan fungsi asli hanya jika wrapper modul ini masih terpasang.
            if MenuModule and OrigIsDown and isDownWrapper
                and rawget(MenuModule, "isDown") == isDownWrapper then
                pcall(function()
                    MenuModule.isDown = OrigIsDown
                end)
            end

            for _, connection in ipairs(connections) do
                pcall(function()
                    connection:Disconnect()
                end)
            end
            table.clear(connections)
        end

        Hub.RegisterCleanup(cleanup)

        -- Pencarian modul dilakukan di task terpisah supaya tidak menahan loader Hub.
        task.spawn(function()
            local lastError = "WorldMenu belum siap"
            for _ = 1, 150 do
                if destroyed or (Hub.IsClosing and Hub.IsClosing()) then return end

                local ok, err = installMovementHook()
                if ok then return end
                lastError = err or lastError
                task.wait(0.1)
            end

            if not destroyed then
                updateStatus(lastError)
                warn("[Gerak] " .. tostring(lastError))
            end
        end)

        -- Status diagnostik: membedakan hook terpasang dengan fungsi yang benar-benar
        -- sedang dipanggil game saat tombol virtual ditekan.
        task.spawn(function()
            while not destroyed and not (Hub.IsClosing and Hub.IsClosing()) do
                if hookReady then
                    if AutoInput.active and readCount > 0 then
                        updateStatus("game memanggil isDown; input virtual sedang dibaca")
                    elseif AutoInput.active then
                        updateStatus("tombol ditekan; menunggu game membaca isDown")
                    else
                        updateStatus("WorldMenu terhubung; siap menerima tombol")
                    end
                end
                task.wait(0.5)
            end
        end)

        print("[Gerak] Tab Gerak standalone dibuat.")
    end)
end
