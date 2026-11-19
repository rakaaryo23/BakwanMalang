--==============================================================
-- MODULE: GERAK MANUAL - GROWBLOX HUB
-- Standalone module untuk Hub.RegisterTab.
--
-- Dasar implementasi:
--   1. Movement input mengikuti mekanisme asli k(8).lua:
--      AutoInput.active + left/right/jump/down
--      GameGui.WorldMenu.isDown(saved, key, ...)
--   2. Pengenalan world dan state mengikuti pola findRefs/discover PNB:
--      getgc(true), tabel world (fg/bg/w/h/spawn), dan state holder
--      yang memiliki state() -> {x, y, facing, vx, ...}.
--
-- Modul ini tidak melakukan login/teleport. Akun harus sudah masuk ke game.
-- Modul membaca sesi LocalPlayer yang sedang aktif.
--==============================================================

return function(Hub)
    assert(Hub and type(Hub.RegisterTab) == "function", "Hub.RegisterTab tidak tersedia")
    assert(type(Hub.RegisterCleanup) == "function", "Hub.RegisterCleanup tidak tersedia")

    Hub.RegisterTab("Gerak", function(page)
        --------------------------------------------------------------
        -- SERVICES & STATE
        --------------------------------------------------------------
        local Players = game:GetService("Players")
        local UserInputService = game:GetService("UserInputService")
        local LocalPlayer = Players.LocalPlayer

        local AutoInput = {
            active = false,
            left = false,
            right = false,
            jump = false,
            down = false,
        }

        local refs = {
            Player = nil,
            Character = nil,
            Humanoid = nil,
            Root = nil,
            PlayerGui = nil,
            GameGui = nil,
            WorldMenuInstance = nil,
            MenuModule = nil,
            World = nil,
            State = nil,
        }

        local OrigIsDown = nil
        local isDownWrapper = nil
        local hookReady = false
        local scanReady = false
        local destroyed = false
        local scanning = false
        local connections = {}
        local heldInputs = { left = {}, right = {}, jump = {} }
        local buttons = {}
        local readCount = 0
        local menuCallCount = 0
        local lastKey = "-"
        local lastState = nil
        local lastError = "Belum dilakukan inisialisasi."
        local lastWorldName = "-"
        local lastWorldSize = "-"

        local Theme = {
            Accent = Color3.fromRGB(20, 20, 20),
            Active = Color3.fromRGB(55, 55, 55),
            Text = Color3.fromRGB(76, 43, 57),
            White = Color3.fromRGB(255, 249, 251),
            Muted = Color3.fromRGB(139, 96, 111),
            Panel = Color3.fromRGB(250, 232, 238),
            Good = Color3.fromRGB(55, 55, 55),
            Bad = Color3.fromRGB(180, 65, 75),
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

        --------------------------------------------------------------
        -- UI
        --------------------------------------------------------------
        local panel = create("Frame", {
            Name = "GerakPanel",
            Size = UDim2.new(1, 0, 0, 284),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        })

        create("TextLabel", {
            Name = "AccountLabel",
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            Text = "AKUN: memeriksa...",
            TextColor3 = Theme.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, panel)

        local status = create("TextLabel", {
            Name = "GerakStatus",
            Position = UDim2.fromOffset(0, 25),
            Size = UDim2.new(1, 0, 0, 118),
            BackgroundColor3 = Theme.Panel,
            BackgroundTransparency = 0.12,
            BorderSizePixel = 0,
            Text = "INISIALISASI...",
            TextColor3 = Theme.Text,
            Font = Enum.Font.Code,
            TextSize = 10,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
        }, panel)
        addCorner(status, 7)

        local buttonRow = create("Frame", {
            Name = "MovementButtons",
            Position = UDim2.fromOffset(0, 151),
            Size = UDim2.new(1, 0, 0, 44),
            BackgroundTransparency = 1,
        }, panel)

        create("UIGridLayout", {
            CellSize = UDim2.new(1 / 3, -6, 1, 0),
            CellPadding = UDim2.fromOffset(6, 0),
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, buttonRow)

        local function updateStatus(extra)
            if destroyed or not status or not status.Parent then return end
            local player = refs.Player or LocalPlayer
            local accountText = "AKUN: belum terdeteksi"
            if player then
                accountText = string.format("AKUN: %s | UserId: %s",
                    tostring(player.Name), tostring(player.UserId))
            end

            local characterText = refs.Character and "OK" or "BELUM"
            local humanoidText = refs.Humanoid and "OK" or "-"
            local rootText = refs.Root and "OK" or "-"
            local worldText = refs.World and "OK" or "BELUM"
            local stateText = lastState and string.format("OK (X=%.2f Y=%.2f)",
                lastState.x, lastState.y) or "BELUM"
            local menuText = hookReady and "HOOK AKTIF" or "BELUM"
            local inputText = AutoInput.active and "DITAHAN" or "LEPAS"

            local lines = {
                "AKUN: " .. accountText,
                string.format("KARAKTER: %s | Humanoid: %s | Root: %s", characterText, humanoidText, rootText),
                "WORLD: " .. worldText .. " | Nama: " .. tostring(lastWorldName) .. " | Ukuran: " .. tostring(lastWorldSize),
                "STATE PLAYER: " .. stateText,
                "WORLDMENU: " .. menuText,
                string.format("INPUT: %s | isDown dipanggil: %d | key dikenali: %s (%d)", inputText, menuCallCount, tostring(lastKey), readCount),
            }
            if extra and extra ~= "" then lines[#lines + 1] = "INFO: " .. tostring(extra) end
            if lastError and lastError ~= "" and not (scanReady and hookReady) then
                lines[#lines + 1] = "DETAIL: " .. tostring(lastError)
            end

            status.Text = table.concat(lines, "\n")
            local accountLabel = panel:FindFirstChild("AccountLabel")
            if accountLabel then accountLabel.Text = accountText end
        end

        --------------------------------------------------------------
        -- PLAYER / CHARACTER RECOGNITION
        --------------------------------------------------------------
        local function refreshCharacter()
            refs.Player = Players.LocalPlayer
            if not refs.Player then
                refs.Character, refs.Humanoid, refs.Root = nil, nil, nil
                return false, "Players.LocalPlayer belum tersedia"
            end

            refs.Character = refs.Player.Character
            if not refs.Character then
                refs.Humanoid, refs.Root = nil, nil
                return false, "Akun terdeteksi, karakter belum spawn"
            end

            refs.Humanoid = refs.Character:FindFirstChildOfClass("Humanoid")
            refs.Root = refs.Character:FindFirstChild("HumanoidRootPart")
                or refs.Character:FindFirstChild("RootPart")
            return true, "Akun dan karakter terdeteksi"
        end

        --------------------------------------------------------------
        -- WORLD + PLAYER STATE DISCOVERY (POLA PNB / k(8).lua)
        -- PNB memakai getgc(true), lalu mengenali tabel world dengan
        -- fg/bg/w/h/spawn dan state holder dengan fungsi state().
        --------------------------------------------------------------
        local function raw(t, key)
            if type(t) ~= "table" then return nil end
            local ok, value = pcall(rawget, t, key)
            return ok and value or nil
        end

        local function isWorldTable(value)
            return type(value) == "table"
                and type(raw(value, "fg")) == "table"
                and type(raw(value, "bg")) == "table"
                and type(raw(value, "w")) == "number"
                and type(raw(value, "h")) == "number"
                and raw(value, "spawn") ~= nil
        end

        local function readState(stateFn)
            if type(stateFn) ~= "function" then return nil end
            local ok, state = pcall(stateFn)
            if not ok or type(state) ~= "table" then return nil end
            if type(state.x) ~= "number" or type(state.y) ~= "number"
                or state.facing == nil or state.vx == nil then
                return nil
            end
            if state.active == false then return nil end
            return state
        end

        local function discoverWorldAndState()
            if type(getgc) ~= "function" then
                return false, "Executor tidak menyediakan getgc(true); world/state belum dapat dipindai"
            end

            local ok, objects = pcall(getgc, true)
            if not ok or type(objects) ~= "table" then
                return false, "getgc(true) gagal: " .. tostring(objects)
            end

            local foundWorld = nil
            local foundStateFn = nil
            local foundState = nil

            for _, object in ipairs(objects) do
                if type(object) == "table" then
                    if not foundWorld and isWorldTable(object) then
                        foundWorld = object
                    end

                    if not foundStateFn then
                        local stateFn = raw(object, "state")
                        local state = readState(stateFn)
                        if state then
                            foundStateFn = stateFn
                            foundState = state
                        end
                    end

                    if foundWorld and foundStateFn then break end
                end
            end

            refs.World = foundWorld
            refs.State = foundStateFn
            lastState = foundState

            if foundWorld then
                local name = raw(foundWorld, "name")
                lastWorldName = (name ~= nil and tostring(name) ~= "") and tostring(name) or "nama tidak tersedia"
                lastWorldSize = string.format("%sx%s", tostring(raw(foundWorld, "w")), tostring(raw(foundWorld, "h")))
            else
                lastWorldName = "belum ditemukan"
                lastWorldSize = "-"
            end

            if not foundWorld and not foundStateFn then
                return false, "World dan state player belum ditemukan melalui getgc(true)"
            elseif not foundWorld then
                return false, "State player ditemukan, tetapi data world belum ditemukan"
            elseif not foundStateFn then
                return false, "Data world ditemukan, tetapi state player belum ditemukan"
            end

            return true, "World dan state player berhasil dikenali"
        end

        --------------------------------------------------------------
        -- WORLDMENU LOOKUP: HIERARCHY SESUAI k(8).lua
        -- Cek langsung dahulu; jika belum ada, WaitForChild berbatas waktu.
        --------------------------------------------------------------
        local function getChild(parent, name, timeout)
            if not parent then return nil end
            local child = parent:FindFirstChild(name)
            if child then return child end
            local ok, result = pcall(function()
                return parent:WaitForChild(name, timeout or 5)
            end)
            if ok then return result end
            return nil
        end

        --------------------------------------------------------------
        -- MOVEMENT HOOK: WRAPPER SAMA DENGAN k(8).lua
        --------------------------------------------------------------
        local function movementIsDown(saved, key, ...)
            menuCallCount += 1
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
            if not OrigIsDown then return false end
            return OrigIsDown(saved, key, ...)
        end
        isDownWrapper = movementIsDown

        local function installMovementHook()
            if destroyed or (Hub.IsClosing and Hub.IsClosing()) then
                return false, "Hub sedang ditutup"
            end
            refs.Player = Players.LocalPlayer
            if not refs.Player then
                return false, "Players.LocalPlayer belum tersedia"
            end

            lastError = "Akun terdeteksi; mencari LocalPlayer.PlayerGui..."
            updateStatus(lastError)
            local playerGui = refs.Player:FindFirstChild("PlayerGui")
                or getChild(refs.Player, "PlayerGui", 2)
            if not playerGui then
                return false, "PlayerGui tidak ditemukan pada LocalPlayer"
            end
            refs.PlayerGui = playerGui

            lastError = "PlayerGui ditemukan; mencari PlayerGui.GameGui..."
            updateStatus(lastError)
            local gameGui = playerGui:FindFirstChild("GameGui")
                or getChild(playerGui, "GameGui", 2)
            if not gameGui then
                return false, "GameGui tidak ditemukan di PlayerGui"
            end
            refs.GameGui = gameGui

            lastError = "GameGui ditemukan; mencari GameGui.WorldMenu..."
            updateStatus(lastError)
            local worldMenu = gameGui:FindFirstChild("WorldMenu")
                or getChild(gameGui, "WorldMenu", 2)
            if not worldMenu then
                local children = {}
                for _, child in ipairs(gameGui:GetChildren()) do
                    children[#children + 1] = child.Name .. " [" .. child.ClassName .. "]"
                end
                return false, "WorldMenu tidak ditemukan di GameGui. Child: " .. (#children > 0 and table.concat(children, ", ") or "(kosong)")
            end
            if not worldMenu:IsA("ModuleScript") then
                return false, "GameGui.WorldMenu bukan ModuleScript: " .. worldMenu.ClassName
            end

            local ok, menu = pcall(require, worldMenu)
            if destroyed or (Hub.IsClosing and Hub.IsClosing()) then
                return false, "Hub sedang ditutup"
            end
            if not ok then
                return false, "require(GameGui.WorldMenu) gagal: " .. tostring(menu)
            end
            if type(menu) ~= "table" or type(rawget(menu, "isDown")) ~= "function" then
                return false, "WorldMenu tidak menyediakan fungsi isDown"
            end

            -- Sudah terpasang pada modul yang sama.
            if refs.MenuModule == menu and rawget(menu, "isDown") == isDownWrapper then
                hookReady = true
                refs.WorldMenuInstance = worldMenu
                return true, "WorldMenu.isDown sudah terhubung"
            end

            -- Pulihkan hook sebelumnya milik modul ini jika modul berubah.
            if refs.MenuModule and OrigIsDown
                and rawget(refs.MenuModule, "isDown") == isDownWrapper then
                pcall(function() refs.MenuModule.isDown = OrigIsDown end)
            end

            refs.MenuModule = menu
            refs.WorldMenuInstance = worldMenu
            OrigIsDown = rawget(menu, "isDown")

            local assigned, assignError = pcall(function()
                menu.isDown = isDownWrapper
            end)
            if not assigned or rawget(menu, "isDown") ~= isDownWrapper then
                hookReady = false
                return false, "Gagal memasang wrapper WorldMenu.isDown: " .. tostring(assignError)
            end

            hookReady = true
            return true, "WorldMenu.isDown berhasil dipasang"
        end

        --------------------------------------------------------------
        -- INPUT BUTTONS (HOLD)
        --------------------------------------------------------------
        local function syncActive()
            AutoInput.active = AutoInput.left or AutoInput.right
                or AutoInput.jump or AutoInput.down
        end

        local function setPressed(key, value)
            if destroyed then return end
            if value == true and not (scanReady and hookReady) then
                updateStatus("Gerak belum diaktifkan: tunggu akun, world, state, dan WorldMenu terhubung")
                return
            end
            AutoInput[key] = value == true
            syncActive()
            local button = buttons[key]
            if button and button.Parent then
                button.BackgroundColor3 = AutoInput[key] and Theme.Good or Theme.Accent
            end
            updateStatus()
        end

        local function releaseAll()
            for _, key in ipairs({ "left", "right", "jump" }) do
                AutoInput[key] = false
                heldInputs[key] = {}
                local button = buttons[key]
                if button and button.Parent then button.BackgroundColor3 = Theme.Accent end
            end
            AutoInput.down = false
            syncActive()
            updateStatus()
        end

        local function makeHoldButton(key, title, order)
            local button = create("TextButton", {
                Name = title .. "Button",
                LayoutOrder = order,
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
                local kind = input.UserInputType
                if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
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

        track(UserInputService.InputEnded:Connect(function(input)
            for _, key in ipairs({ "left", "right", "jump" }) do
                if heldInputs[key][input] then
                    heldInputs[key][input] = nil
                    setPressed(key, next(heldInputs[key]) ~= nil)
                end
            end
        end))

        pcall(function()
            track(UserInputService.WindowFocusReleased:Connect(releaseAll))
        end)

        --------------------------------------------------------------
        -- CONNECT / SCAN BUTTON: EXPLICIT PROOF OF ACCOUNT-WORLD-HOOK
        --------------------------------------------------------------
        local connectButton = create("TextButton", {
            Name = "ConnectScanButton",
            Position = UDim2.fromOffset(0, 202),
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Text = "HUBUNGKAN / SCAN ULANG GAME",
            TextColor3 = Theme.White,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            AutoButtonColor = true,
        }, panel)
        addCorner(connectButton, 8)

        local function connectAndScan()
            if destroyed or scanning then return end
            scanning = true
            lastError = "Memeriksa akun, karakter, world, state, dan WorldMenu..."
            updateStatus(lastError)

            task.spawn(function()
                local okPlayer, playerMessage = refreshCharacter()
                updateStatus(playerMessage)

                local scanOk, scanMessage = discoverWorldAndState()
                if destroyed or (Hub.IsClosing and Hub.IsClosing()) then
                    scanning = false
                    return
                end
                scanReady = scanOk
                if not scanOk then lastError = scanMessage end
                updateStatus(scanMessage)

                local hookOk, hookMessage = installMovementHook()
                if destroyed or (Hub.IsClosing and Hub.IsClosing()) then
                    scanning = false
                    return
                end
                hookReady = hookOk
                if not hookOk then lastError = hookMessage end

                if scanOk and hookOk and okPlayer then
                    lastError = "SIAP: akun, karakter, world, state player, dan WorldMenu terhubung. Tahan tombol untuk uji input."
                elseif scanOk and hookOk then
                    lastError = "SIAP: akun, world, state player, dan WorldMenu terhubung. Karakter Roblox belum tersedia; input game tetap diuji lewat state player."
                elseif scanOk then
                    lastError = "World/state dikenali; movement hook belum aktif: " .. tostring(hookMessage)
                elseif hookOk then
                    lastError = "WorldMenu terhubung; world/state belum dikenali: " .. tostring(scanMessage)
                else
                    lastError = "Koneksi belum lengkap. Scan ulang setelah game/world siap."
                end

                scanning = false
                updateStatus(lastError)
                print("[Gerak] " .. tostring(lastError))
            end)
        end

        track(connectButton.Activated:Connect(connectAndScan))

        --------------------------------------------------------------
        -- COPY FEEDBACK: SALIN DIAGNOSTIK UNTUK DIKIRIM KE CHAT
        --------------------------------------------------------------
        local feedbackButton = create("TextButton", {
            Name = "CopyFeedbackButton",
            Position = UDim2.fromOffset(0, 242),
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Text = "COPY FEEDBACK / DIAGNOSTIK",
            TextColor3 = Theme.White,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            AutoButtonColor = true,
        }, panel)
        addCorner(feedbackButton, 8)

        local function makeFeedback()
            local player = refs.Player or Players.LocalPlayer
            local state = lastState
            local stateText = "tidak tersedia"
            if state then
                stateText = string.format(
                    "X=%s | Y=%s | facing=%s | vx=%s",
                    tostring(state.x), tostring(state.y),
                    tostring(state.facing), tostring(state.vx)
                )
            end

            local menuClass = refs.WorldMenuInstance
                and refs.WorldMenuInstance.ClassName or "tidak ditemukan"
            local menuName = refs.WorldMenuInstance
                and refs.WorldMenuInstance:GetFullName() or "tidak ditemukan"

            local lines = {
                "=== GROWBLOX GERAK - FEEDBACK DIAGNOSTIK ===",
                "Akun: " .. (player and tostring(player.Name) or "tidak terdeteksi"),
                "Character: " .. (refs.Character and "ADA" or "TIDAK ADA"),
                "Humanoid: " .. (refs.Humanoid and "ADA" or "TIDAK ADA"),
                "RootPart: " .. (refs.Root and "ADA" or "TIDAK ADA"),
                "PlayerGui: " .. (refs.PlayerGui and "DITEMUKAN" or "BELUM"),
                "GameGui: " .. (refs.GameGui and "DITEMUKAN" or "BELUM"),
                "WorldMenu instance: " .. menuClass .. " | " .. menuName,
                "WorldMenu module: " .. (refs.MenuModule and "BERHASIL REQUIRE" or "BELUM"),
                "isDown hook: " .. (hookReady and "AKTIF" or "BELUM AKTIF"),
                "World table: " .. (refs.World and "DITEMUKAN" or "BELUM"),
                "Nama world: " .. tostring(lastWorldName),
                "Ukuran world: " .. tostring(lastWorldSize),
                "Player state function: " .. (refs.State and "DITEMUKAN" or "BELUM"),
                "Player state: " .. stateText,
                "getgc tersedia: " .. (type(getgc) == "function" and "YA" or "TIDAK"),
                "Scan ready: " .. tostring(scanReady),
                "Hook ready: " .. tostring(hookReady),
                "Sedang scan: " .. tostring(scanning),
                "Input aktif: " .. tostring(AutoInput.active),
                "Kiri/Kanan/Jump: " .. tostring(AutoInput.left) .. "/" .. tostring(AutoInput.right) .. "/" .. tostring(AutoInput.jump),
                "isDown dipanggil: " .. tostring(menuCallCount),
                "Key dikenali: " .. tostring(readCount),
                "Key terakhir: " .. tostring(lastKey),
                "Pesan/error terakhir: " .. tostring(lastError),
                "Status tambahan: " .. (status and status.Text or "tidak tersedia"),
                "=== AKHIR FEEDBACK ===",
            }
            return table.concat(lines, "\n")
        end

        track(feedbackButton.Activated:Connect(function()
            if destroyed then return end
            local feedbackText = makeFeedback()

            local clipboardFunction = nil
            if type(setclipboard) == "function" then
                clipboardFunction = setclipboard
            elseif type(toclipboard) == "function" then
                clipboardFunction = toclipboard
            end

            if clipboardFunction then
                local ok, err = pcall(clipboardFunction, feedbackText)
                if ok then
                    feedbackButton.Text = "FEEDBACK BERHASIL DISALIN"
                    updateStatus("Feedback diagnostik sudah disalin. Tempelkan hasilnya di chat.")
                else
                    feedbackButton.Text = "GAGAL MENYALIN - CEK CONSOLE"
                    warn("[Gerak] Gagal menyalin feedback: " .. tostring(err))
                    print(feedbackText)
                    updateStatus("Clipboard gagal; feedback dicetak ke console.")
                end
            else
                feedbackButton.Text = "CLIPBOARD TIDAK TERSEDIA"
                print(feedbackText)
                updateStatus("Fungsi clipboard tidak tersedia; feedback dicetak ke console.")
            end

            task.delay(2.5, function()
                if feedbackButton and feedbackButton.Parent and not destroyed then
                    feedbackButton.Text = "COPY FEEDBACK / DIAGNOSTIK"
                end
            end)
        end))

        --------------------------------------------------------------
        -- CHARACTER EVENTS + CLEANUP
        --------------------------------------------------------------
        if LocalPlayer then
            track(LocalPlayer.CharacterAdded:Connect(function(character)
                refs.Character = character
                task.spawn(function()
                    task.wait(0.5)
                    refreshCharacter()
                    updateStatus("Karakter baru terdeteksi; menyegarkan pengenalan world/state...")
                    connectAndScan()
                end)
            end))
            track(LocalPlayer.CharacterRemoving:Connect(function()
                refs.Character, refs.Humanoid, refs.Root = nil, nil, nil
                lastState = nil
                scanReady = false
                releaseAll()
                updateStatus("Karakter keluar; menunggu karakter/world aktif kembali")
            end))
        end

        local function cleanup()
            if destroyed then return end
            releaseAll()
            destroyed = true

            if refs.MenuModule and OrigIsDown and isDownWrapper
                and rawget(refs.MenuModule, "isDown") == isDownWrapper then
                pcall(function() refs.MenuModule.isDown = OrigIsDown end)
            end

            for _, connection in ipairs(connections) do
                pcall(function() connection:Disconnect() end)
            end
            table.clear(connections)
        end

        Hub.RegisterCleanup(cleanup)

        --------------------------------------------------------------
        -- AUTO INITIALIZATION (SATU KALI)
        -- Status sengaja tidak diperbarui terus-menerus agar mudah dibaca
        -- dan di-screenshot. Scan ulang hanya saat tombol ditekan atau
        -- karakter respawn.
        --------------------------------------------------------------
        updateStatus("Modul aktif; menjalankan satu kali scan. Tekan HUBUNGKAN / SCAN ULANG GAME untuk mencoba lagi.")
        task.defer(connectAndScan)
        print("[Gerak] Tab Gerak dibuat. Menjalankan pengenalan akun/world dan movement hook.")
    end)
end
