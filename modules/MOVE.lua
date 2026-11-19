--==============================================================
-- MODULE: GERAK MANUAL
-- Standalone untuk GrowBlox Hub.
--
-- Mekanisme input mengikuti sumber k(8).lua secara langsung:
--   AutoInput = { active, left, right, jump, down }
--   WorldMenu.isDown(saved, key, ...)
--
-- Modul ini HANYA menyediakan input karakter manual (KIRI/KANAN/JUMP).
-- Tidak ada A*, koordinat, target, auto-farm, atau logika navigasi.
--==============================================================

return function(Hub)
    assert(Hub and type(Hub.RegisterTab) == "function", "Hub.RegisterTab tidak tersedia")
    assert(type(Hub.RegisterCleanup) == "function", "Hub.RegisterCleanup tidak tersedia")

    Hub.RegisterTab("Gerak", function(page)
        ----------------------------------------------------------------
        -- IMPORT / SERVICES YANG DIPERLUKAN UNTUK INPUT MOVEMENT
        -- Mengikuti cara akses service dan PlayerGui pada k(8).lua.
        ----------------------------------------------------------------
        local Players = game:GetService("Players")
        local UserInputService = game:GetService("UserInputService")
        local LocalPlayer = Players.LocalPlayer

        ----------------------------------------------------------------
        -- AUTO INPUT: bentuk dan nama field sama seperti k(8).lua.
        ----------------------------------------------------------------
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
        local hookError = "menunggu PlayerGui"

        local Theme = {
            Accent = Color3.fromRGB(171, 91, 119),
            Active = Color3.fromRGB(65, 155, 105),
            Text = Color3.fromRGB(76, 43, 57),
            White = Color3.fromRGB(255, 249, 251),
            Muted = Color3.fromRGB(139, 96, 111),
        }

        local function track(connection)
            connections[#connections + 1] = connection
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

        ----------------------------------------------------------------
        -- UI
        ----------------------------------------------------------------
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
            status.Text = string.format(
                "Status: %s\nMode: %s | Dibaca game: %s (%d)",
                message or (hookReady and "WorldMenu terhubung" or hookError),
                AutoInput.active and "virtual input aktif" or "input game normal",
                lastKey,
                readCount
            )
        end

        ----------------------------------------------------------------
        -- INPUT STATE
        -- Saat AutoInput.active true, wrapper mengambil alih empat key
        -- logical persis seperti fungsi isDownWrapper di k(8).lua.
        ----------------------------------------------------------------
        local function syncActive()
            AutoInput.active = AutoInput.left or AutoInput.right
                or AutoInput.jump or AutoInput.down
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

        local function releaseInput()
            AutoInput.left = false
            AutoInput.right = false
            AutoInput.jump = false
            AutoInput.down = false
            for _, key in ipairs({ "left", "right", "jump" }) do
                heldInputs[key] = {}
                local button = buttons[key]
                if button and button.Parent then
                    button.BackgroundColor3 = Theme.Accent
                end
            end
            syncActive()
            updateStatus()
        end

        ----------------------------------------------------------------
        -- MOVEMENT HOOK: urutan dan perilaku wrapper disalin dari k(8).lua.
        -- Perbedaan yang disengaja hanya pengambilan referensi modul: dilakukan
        -- di task terpisah, tetapi tetap memakai WaitForChild seperti sumber.
        ----------------------------------------------------------------
        local function isDownWrapper(saved, key, ...)
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

        local function installMovementHook()
            if destroyed or (Hub.IsClosing and Hub.IsClosing()) then
                return false, "Hub sedang ditutup"
            end
            if not LocalPlayer then
                return false, "Players.LocalPlayer tidak tersedia"
            end

            -- Ikuti hierarchy k(8).lua, jangan FindFirstChild instan.
            local playerGui = LocalPlayer:WaitForChild("PlayerGui")
            if not playerGui then
                return false, "PlayerGui tidak ditemukan"
            end
            local gameGui = playerGui:WaitForChild("GameGui")
            if not gameGui then
                return false, "PlayerGui.GameGui tidak ditemukan"
            end
            local worldMenu = gameGui:WaitForChild("WorldMenu")
            if not worldMenu then
                return false, "GameGui.WorldMenu tidak ditemukan"
            end
            if not worldMenu:IsA("ModuleScript") then
                return false, "GameGui.WorldMenu bukan ModuleScript (Class: " .. worldMenu.ClassName .. ")"
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

            -- Jangan pasang wrapper kedua kali pada modul yang sama.
            if MenuModule == result and rawget(MenuModule, "isDown") == isDownWrapper then
                hookReady = true
                hookError = "WorldMenu.isDown berhasil dipasang"
                updateStatus(hookError)
                return true
            end

            -- Jika referensi modul berubah, pulihkan hook lama milik modul ini.
            if MenuModule and OrigIsDown and isDownWrapper
                and rawget(MenuModule, "isDown") == isDownWrapper then
                pcall(function()
                    MenuModule.isDown = OrigIsDown
                end)
            end

            MenuModule = result
            OrigIsDown = rawget(MenuModule, "isDown")
            local assigned, assignError = pcall(function()
                MenuModule.isDown = isDownWrapper
            end)

            if not assigned or rawget(MenuModule, "isDown") ~= isDownWrapper then
                hookReady = false
                return false, "gagal memasang WorldMenu.isDown: " .. tostring(assignError)
            end

            hookReady = true
            hookError = "WorldMenu.isDown berhasil dipasang"
            updateStatus(hookError)
            print("[Gerak] WorldMenu.isDown terhubung memakai mekanisme k(8).lua.")
            return true
        end

        ----------------------------------------------------------------
        -- HOLD BUTTONS: tahan untuk bergerak, lepas untuk berhenti.
        ----------------------------------------------------------------
        local function makeHoldButton(key, title, layoutOrder)
            local button = create("TextButton", {
                Name = title .. "Button",
                LayoutOrder = layoutOrder,
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

        makeHoldButton("left", "KIRI", 1)
        makeHoldButton("right", "KANAN", 2)
        makeHoldButton("jump", "JUMP", 3)

        -- Lepas tombol tetap terdeteksi walau jari/mouse keluar dari tombol.
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
                releaseInput()
            end))
        end)

        ----------------------------------------------------------------
        -- CLEANUP: selalu lepas input dan pulihkan isDown asli.
        ----------------------------------------------------------------
        local function cleanup()
            if destroyed then return end
            releaseInput()
            destroyed = true

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

        ----------------------------------------------------------------
        -- INITIALIZE HOOK ASYNCHRONOUSLY.
        -- WaitForChild mengikuti source; task.spawn agar tab/loader tidak freeze.
        ----------------------------------------------------------------
        task.spawn(function()
            local callOk, installed, detail = pcall(installMovementHook)
            if not callOk then
                hookReady = false
                hookError = "Kesalahan saat memasang movement hook: " .. tostring(installed)
                updateStatus(hookError)
                warn("[Gerak] " .. hookError)
                return
            end
            if not installed then
                hookReady = false
                hookError = tostring(detail or "Movement hook tidak berhasil dipasang")
                updateStatus(hookError)
                warn("[Gerak] " .. hookError)
            end
        end)

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

        print("[Gerak] Tab Gerak manual siap.")
    end)
end
