--==================================================
-- MODULE: GERAK KANAN / KIRI / JUMP
-- Untuk GrowBlox Hub
-- Letakkan file ini langsung di folder: modules/
--
-- FIX:
-- - Tidak memakai WaitForChild pada jalur pemuatan utama.
-- - Pencarian WorldMenu berjalan di task terpisah.
-- - Tidak menahan LoadAllModules() milik main.lua.
-- - Cleanup mengembalikan WorldMenu.isDown jika masih memakai wrapper.
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
        local heldInputs = {
            left = nil,
            right = nil,
            jump = nil,
        }
        local pressed = {
            left = false,
            right = false,
            jump = false,
        }

        local menuModule = nil
        local originalIsDown = nil
        local movementWrapper = nil
        local movementReady = false

        local Theme = {
            Accent = Color3.fromRGB(171, 91, 119),
            Active = Color3.fromRGB(65, 155, 105),
            Text = Color3.fromRGB(76, 43, 57),
            Muted = Color3.fromRGB(139, 96, 111),
            White = Color3.fromRGB(255, 249, 251),
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

        local function label(text, height)
            return create("TextLabel", {
                Size = UDim2.new(1, 0, 0, height or 28),
                BackgroundTransparency = 1,
                Text = text,
                TextColor3 = Theme.Text,
                Font = Enum.Font.Gotham,
                TextSize = 11,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
            })
        end

        local status = label("Status: mencari kontrol gerak game...", 34)
        label("Tekan dan tahan tombol untuk bergerak. Lepaskan untuk berhenti.", 34)

        local buttonRow = create("Frame", {
            Size = UDim2.new(1, 0, 0, 58),
            BackgroundTransparency = 1,
        })

        create("UIGridLayout", {
            CellSize = UDim2.new(1 / 3, -6, 0, 48),
            CellPadding = UDim2.fromOffset(6, 0),
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, buttonRow)

        local buttons = {}

        local function setPressed(key, value)
            if destroyed then return end

            pressed[key] = value == true

            local button = buttons[key]
            if button and button.Parent then
                button.BackgroundColor3 = pressed[key]
                    and Theme.Active or Theme.Accent
            end
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
            }, buttonRow)
            corner(button, 8)
            buttons[key] = button

            track(button.InputBegan:Connect(function(input)
                if destroyed then return end

                local inputType = input.UserInputType
                if inputType == Enum.UserInputType.MouseButton1
                    or inputType == Enum.UserInputType.Touch then
                    heldInputs[key] = input
                    setPressed(key, true)
                end
            end))

            track(button.InputEnded:Connect(function(input)
                if heldInputs[key] == input then
                    heldInputs[key] = nil
                    setPressed(key, false)
                end
            end))
        end

        makeHoldButton("left", "KIRI")
        makeHoldButton("right", "KANAN")
        makeHoldButton("jump", "JUMP")

        track(UserInputService.InputEnded:Connect(function(input)
            for key, held in pairs(heldInputs) do
                if held == input then
                    heldInputs[key] = nil
                    setPressed(key, false)
                end
            end
        end))

        pcall(function()
            track(UserInputService.WindowFocusReleased:Connect(function()
                for key in pairs(pressed) do
                    heldInputs[key] = nil
                    setPressed(key, false)
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
        end

        local function cleanup()
            if destroyed then return end

            releaseAll()
            destroyed = true

            if menuModule and originalIsDown
                and movementWrapper
                and rawget(menuModule, "isDown") == movementWrapper then
                pcall(function()
                    menuModule.isDown = originalIsDown
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

        -- PENTING: pencarian game module dilakukan di task terpisah.
        -- Tidak ada WaitForChild yang dapat menahan loader main.lua.
        task.spawn(function()
            local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
            local gameGui = playerGui and playerGui:FindFirstChild("GameGui")
            local worldMenu = gameGui and gameGui:FindFirstChild("WorldMenu")

            -- Jika UI game belum siap, tunggu terbatas hanya di task ini.
            for _ = 1, 100 do
                if destroyed or Hub.IsClosing() then return end

                if not playerGui then
                    playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
                end
                if playerGui and not gameGui then
                    gameGui = playerGui:FindFirstChild("GameGui")
                end
                if gameGui and not worldMenu then
                    worldMenu = gameGui:FindFirstChild("WorldMenu")
                end

                if worldMenu then break end
                task.wait(0.1)
            end

            if destroyed or Hub.IsClosing() then return end

            if not worldMenu then
                if status and status.Parent then
                    status.Text = "Status: WorldMenu tidak ditemukan (timeout)."
                end
                warn("[Gerak] WorldMenu tidak ditemukan; UI Hub tetap berjalan.")
                return
            end

            local ok, result = pcall(require, worldMenu)
            if not ok or type(result) ~= "table"
                or type(rawget(result, "isDown")) ~= "function" then
                if status and status.Parent then
                    status.Text = "Status: gagal menghubungkan WorldMenu.isDown."
                end
                warn("[Gerak] Gagal require WorldMenu:", result)
                return
            end

            if destroyed or Hub.IsClosing() then return end

            menuModule = result
            originalIsDown = rawget(menuModule, "isDown")

            local function movementIsDown(saved, key, ...)
                if key == "keyLeft" and pressed.left then
                    return true
                elseif key == "keyRight" and pressed.right then
                    return true
                elseif key == "keyJump" and pressed.jump then
                    return true
                end

                return originalIsDown(saved, key, ...)
            end

            movementWrapper = movementIsDown

            local assigned, assignError = pcall(function()
                menuModule.isDown = movementWrapper
            end)

            if not assigned then
                menuModule = nil
                originalIsDown = nil
                movementWrapper = nil

                if status and status.Parent then
                    status.Text = "Status: gagal memasang kontrol gerak."
                end
                warn("[Gerak] Gagal memasang wrapper:", assignError)
                return
            end

            movementReady = true
            if status and status.Parent then
                status.Text = "Status: kontrol KIRI / KANAN / JUMP terhubung."
            end
            print("[Gerak] Kontrol Kiri / Kanan / Jump terhubung.")
        end)

        print("[Gerak] Tab dibuat; pencarian kontrol berjalan terpisah.")
    end)
end
