--==================================================
-- MODULE: GERAK KANAN / KIRI / JUMP
-- Untuk GrowBlox Hub
-- Letakkan file ini langsung di folder: modules/
--==================================================

return function(Hub)
    assert(Hub and type(Hub.RegisterTab) == "function",
        "Module Gerak membutuhkan Hub.RegisterTab")

    Hub.RegisterTab("Gerak", function(page)
        local Players = game:GetService("Players")
        local UserInputService = game:GetService("UserInputService")

        local LocalPlayer = Players.LocalPlayer
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
        local GameGui = PlayerGui:WaitForChild("GameGui")

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

        -- Hubungkan ke kontrol gerak asli GrowBlox.
        local menuModule
        local originalIsDown
        local movementWrapper
        local movementReady = false

        local moduleOK, result = pcall(function()
            return require(GameGui:WaitForChild("WorldMenu"))
        end)

        if moduleOK and type(result) == "table"
            and type(rawget(result, "isDown")) == "function" then

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
            menuModule.isDown = movementWrapper
            movementReady = true
        end

        local Theme = {
            Background = Color3.fromRGB(250, 220, 228),
            Panel = Color3.fromRGB(239, 194, 207),
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

        local buttons = {}

        local status = label(
            movementReady
                and "Status: kontrol gerak terhubung."
                or "Status: WorldMenu.isDown tidak ditemukan.",
            34
        )

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

        local function setPressed(key, value)
            if destroyed or not movementReady then return end

            pressed[key] = value == true

            local button = buttons and buttons[key]
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
                Active = movementReady,
            }, buttonRow)
            corner(button, 8)
            buttons[key] = button

            if not movementReady then
                button.BackgroundColor3 = Theme.Muted
                button.TextTransparency = 0.25
                return
            end

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

        -- Pastikan tombol dilepas walau jari/mouse dilepas di luar tombol.
        track(UserInputService.InputEnded:Connect(function(input)
            for key, held in pairs(heldInputs) do
                if held == input then
                    heldInputs[key] = nil
                    setPressed(key, false)
                end
            end
        end))

        -- Lepas input jika jendela kehilangan fokus.
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
                and rawget(menuModule, "isDown") == movementWrapper then
                menuModule.isDown = originalIsDown
            end

            for _, connection in ipairs(connections) do
                pcall(function()
                    connection:Disconnect()
                end)
            end
            table.clear(connections)
        end

        Hub.RegisterCleanup(cleanup)

        print("[Gerak] Module Kiri / Kanan / Jump dimuat.")
    end)
end
