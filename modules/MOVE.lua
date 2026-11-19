--==================================================
-- MODULE: GERAK KANAN / KIRI / JUMP - STANDALONE
-- Tidak membutuhkan k.lua / k(7).lua atau module lain.
-- Menghubungkan tombol Hub langsung ke WorldMenu.isDown milik game.
--==================================================

return function(Hub)
    assert(Hub and type(Hub.RegisterTab) == "function",
        "Module Gerak membutuhkan Hub.RegisterTab")

    Hub.RegisterTab("Gerak", function(page)
        local Players = game:GetService("Players")
        local UserInputService = game:GetService("UserInputService")
        local LocalPlayer = Players.LocalPlayer

        local destroyed = false
        local connections = {}
        local heldInputs = { left = nil, right = nil, jump = nil }
        local pressed = { left = false, right = false, jump = false }
        local buttons = {}

        local menuModule = nil
        local originalIsDown = nil
        local movementWrapper = nil
        local hookReady = false
        local calls = 0
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

        local function corner(object, radius)
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, radius or 8)
            c.Parent = object
        end

        local panel = create("Frame", {
            Name = "GerakPanel",
            Size = UDim2.new(1, 0, 0, 112),
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
            Size = UDim2.new(1, 0, 0, 52),
            BackgroundTransparency = 1,
            Text = "Status: mencari kontrol gerak game...",
            TextColor3 = Theme.Text,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
        }, panel)

        local function updateStatus(extra)
            if not status or not status.Parent then return end
            status.Text = string.format(
                "Status: %s\nGame membaca: %s | Input: K:%s Kn:%s J:%s",
                extra or (hookReady and "kontrol terpasang" or "menunggu kontrol"),
                lastKey,
                pressed.left and "ON" or "OFF",
                pressed.right and "ON" or "OFF",
                pressed.jump and "ON" or "OFF"
            )
        end

        -- Wrapper ini milik module Gerak sendiri. Ia membungkus fungsi asli
        -- game dan tidak memakai AutoInput / state dari script lain.
        local function installMovementHook()
            local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
            local gameGui = playerGui and playerGui:FindFirstChild("GameGui")
            local worldMenu = gameGui and gameGui:FindFirstChild("WorldMenu")
            if not worldMenu or not worldMenu:IsA("ModuleScript") then
                return false, "ModuleScript GameGui.WorldMenu belum ditemukan"
            end

            local ok, result = pcall(require, worldMenu)
            if not ok then
                return false, "require WorldMenu gagal: " .. tostring(result)
            end
            if type(result) ~= "table" then
                return false, "WorldMenu tidak mengembalikan table"
            end

            local currentIsDown = result.isDown
            if type(currentIsDown) ~= "function" then
                return false, "WorldMenu.isDown bukan function"
            end

            menuModule = result
            originalIsDown = currentIsDown

            movementWrapper = function(...)
                local args = table.pack(...)
                local key = nil

                -- Mendukung pemanggilan method (module:isDown(key)) maupun
                -- function biasa (module.isDown(key)).
                for i = 1, args.n do
                    local value = args[i]
                    if value == "keyLeft" or value == "keyRight" or value == "keyJump" then
                        key = value
                        break
                    end
                end

                if key then
                    calls += 1
                    lastKey = key
                    if key == "keyLeft" then return pressed.left end
                    if key == "keyRight" then return pressed.right end
                    if key == "keyJump" then return pressed.jump end
                end

                return originalIsDown(table.unpack(args, 1, args.n))
            end

            result.isDown = movementWrapper
            hookReady = result.isDown == movementWrapper
            if hookReady then
                updateStatus("kontrol gerak game terpasang; menunggu game membaca input")
                print("[Gerak] Hook WorldMenu.isDown berhasil dipasang secara mandiri.")
                return true
            end
            return false, "Gagal memasang wrapper WorldMenu.isDown"
        end

        local function applyButton(key, isDown)
            if destroyed then return end
            pressed[key] = isDown == true
            local button = buttons[key]
            if button and button.Parent then
                button.BackgroundColor3 = pressed[key] and Theme.Active or Theme.Accent
            end
            updateStatus(hookReady and "kontrol gerak game terpasang" or "kontrol belum terpasang")
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
            corner(button, 8)
            buttons[key] = button

            track(button.InputBegan:Connect(function(input)
                local inputType = input.UserInputType
                if inputType == Enum.UserInputType.MouseButton1
                    or inputType == Enum.UserInputType.Touch then
                    heldInputs[key] = input
                    applyButton(key, true)
                end
            end))

            track(button.InputEnded:Connect(function(input)
                if heldInputs[key] == input then
                    heldInputs[key] = nil
                    applyButton(key, false)
                end
            end))
        end

        makeHoldButton("left", "KIRI")
        makeHoldButton("right", "KANAN")
        makeHoldButton("jump", "JUMP")

        -- Global release diperlukan karena sentuhan/mouse dapat berakhir di luar tombol.
        track(UserInputService.InputEnded:Connect(function(input)
            for key, held in pairs(heldInputs) do
                if held == input then
                    heldInputs[key] = nil
                    applyButton(key, false)
                end
            end
        end))

        pcall(function()
            track(UserInputService.WindowFocusReleased:Connect(function()
                for key in pairs(pressed) do
                    heldInputs[key] = nil
                    applyButton(key, false)
                end
            end))
        end)

        local function releaseAll()
            for key in pairs(pressed) do
                heldInputs[key] = nil
                pressed[key] = false
                local button = buttons[key]
                if button and button.Parent then
                    button.BackgroundColor3 = Theme.Accent
                end
            end
            updateStatus()
        end

        local function cleanup()
            if destroyed then return end
            releaseAll()
            destroyed = true

            -- Jangan timpa hook milik sistem lain jika sudah diganti setelah kita.
            if menuModule and originalIsDown and movementWrapper
                and menuModule.isDown == movementWrapper then
                menuModule.isDown = originalIsDown
            end

            for _, connection in ipairs(connections) do
                pcall(function() connection:Disconnect() end)
            end
            table.clear(connections)
        end

        Hub.RegisterCleanup(cleanup)

        -- Tunggu GameGui/WorldMenu siap. Tidak memblokir proses load Hub.
        task.spawn(function()
            local lastError = "WorldMenu belum siap"
            for _ = 1, 150 do
                if destroyed or (Hub.IsClosing and Hub.IsClosing()) then return end
                local ok, err = installMovementHook()
                if ok then return end
                lastError = err or lastError
                task.wait(0.1)
            end
            updateStatus(lastError)
            warn("[Gerak] " .. tostring(lastError))
        end)

        -- Tampilkan apakah fungsi kontrol benar-benar dipanggil game.
        task.spawn(function()
            while not destroyed and not (Hub.IsClosing and Hub.IsClosing()) do
                if hookReady then
                    updateStatus(calls > 0
                        and ("kontrol aktif; game membaca " .. lastKey)
                        or "hook terpasang; game belum memanggil isDown")
                end
                task.wait(0.5)
            end
        end)

        print("[Gerak] Tab Gerak standalone dibuat.")
    end)
end
