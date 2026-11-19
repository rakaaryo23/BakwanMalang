--==============================================================
-- GROWBLOX - STANDALONE MOVEMENT CONTROLLER + AUTO RECONNECT
-- Android / Delta Executor
--
-- Scan dari awal:
--   1. LocalPlayer / account
--   2. World table: fg, bg, w, h, spawn
--   3. Player state function: state() -> x, y, facing, vx
--   4. Movement table: isDown + spaceJumps + KEYS
--   5. Hook isDown dan buat tombol virtual
--
-- Input fisik tetap diteruskan ke isDown asli. Input virtual digabung
-- dengan input fisik (OR), bukan menggantikan input fisik.
-- Auto reconnect berlaku selama script/controller masih hidup.
--==============================================================

local function MAIN()
    -- Hentikan instance script sebelumnya jika masih aktif.
    local ENV = (type(getgenv) == "function" and getgenv()) or _G
    if type(ENV.GB_MOVEMENT_STOP) == "function" then
        pcall(ENV.GB_MOVEMENT_STOP)
    end

    local Players = game:GetService("Players")
    local UIS = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer
    local CoreGui = game:GetService("CoreGui")

    local PREFIX = "[GB AUTO MOVEMENT] "
    local running = true
    local scanning = false
    local connected = false
    local lastScan = 0
    local scanCount = 0
    local lastError = "Belum melakukan scan"

    local refs = {
        player = LocalPlayer,
        world = nil,
        stateFn = nil,
        state = nil,
        movement = nil,
        originalIsDown = nil,
        wrapper = nil,
        keys = nil,
        source = "belum ditemukan",
    }

    local input = {
        left = false,
        right = false,
        jump = false,
        down = false,
    }

    local buttons = {}
    local held = { left = {}, right = {}, jump = {}, down = {} }
    local gui, panel, statusLabel

    local function log(...)
        print(PREFIX, ...)
    end

    local function setStatus(message)
        lastError = tostring(message or "-")
        if statusLabel and statusLabel.Parent then
            local p = refs.player or Players.LocalPlayer
            local account = p and p.Name or "belum tersedia"
            local worldText = refs.world and (tostring(refs.world.w) .. "x" .. tostring(refs.world.h)) or "belum"
            local stateText = "belum"
            if refs.state then
                stateText = string.format("X %.2f | Y %.2f | VX %.2f | VY %.2f",
                    refs.state.x or 0, refs.state.y or 0,
                    refs.state.vx or 0, refs.state.vy or 0)
            end
            statusLabel.Text = string.format(
                "AKUN: %s\nWORLD: %s | STATE: %s\nMOVEMENT: %s\nSCAN: %d | %s",
                tostring(account), tostring(worldText), tostring(stateText),
                connected and "TERHUBUNG" or "MENCARI / TERPUTUS",
                scanCount, lastError
            )
        end
    end

    local function safeRaw(t, k)
        if type(t) ~= "table" then return nil end
        local ok, value = pcall(rawget, t, k)
        if ok then return value end
        return nil
    end

    local function readPlayerState(fn)
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn)
        if not ok or type(value) ~= "table" then return nil end
        if type(value.x) ~= "number" or type(value.y) ~= "number" then return nil end
        if value.facing == nil or value.vx == nil then return nil end
        if value.active == false then return nil end
        return value
    end

    local function validWorld(t)
        return type(t) == "table"
            and type(safeRaw(t, "fg")) == "table"
            and type(safeRaw(t, "bg")) == "table"
            and type(safeRaw(t, "w")) == "number"
            and type(safeRaw(t, "h")) == "number"
            and safeRaw(t, "spawn") ~= nil
    end

    local function validKeys(keys)
        if type(keys) ~= "table" then return false end
        local jump = safeRaw(keys, 2)
        local left = safeRaw(keys, 3)
        local right = safeRaw(keys, 4)
        local down = safeRaw(keys, 5)
        return type(jump) == "table" and jump[1] == "keyJump"
            and type(left) == "table" and left[1] == "keyLeft"
            and type(right) == "table" and right[1] == "keyRight"
            and type(down) == "table" and down[1] == "keyDown"
    end

    local function validMovementTable(t)
        if type(t) ~= "table" then return false end
        local isDown = safeRaw(t, "isDown")
        local spaceJumps = safeRaw(t, "spaceJumps")
        local keys = safeRaw(t, "KEYS")
        return type(isDown) == "function"
            and type(spaceJumps) == "function"
            and validKeys(keys)
    end

    local function getGC()
        if type(getgc) ~= "function" then
            return nil, "Executor tidak menyediakan getgc"
        end
        local ok, objects = pcall(getgc, true)
        if not ok or type(objects) ~= "table" then
            return nil, "getgc(true) gagal: " .. tostring(objects)
        end
        return objects
    end

    -- Scan semua objek GC satu kali dan cari tiga jenis referensi.
    -- Movement dipilih dengan signature gabungan isDown/spaceJumps/KEYS,
    -- bukan hanya nama fungsi yang kebetulan sama.
    local function scanFromZero()
        scanCount += 1
        local objects, gcError = getGC()
        if not objects then return false, gcError end

        local foundWorld, foundStateFn, foundState, foundMovement

        for _, object in ipairs(objects) do
            if type(object) == "table" then
                if not foundWorld and validWorld(object) then
                    foundWorld = object
                end

                if not foundStateFn then
                    local candidateState = safeRaw(object, "state")
                    local stateValue = readPlayerState(candidateState)
                    if stateValue then
                        foundStateFn = candidateState
                        foundState = stateValue
                    end
                end

                if not foundMovement and validMovementTable(object) then
                    foundMovement = object
                end

                if foundWorld and foundStateFn and foundMovement then
                    break
                end
            end
        end

        if foundWorld then refs.world = foundWorld end
        if foundStateFn then
            refs.stateFn = foundStateFn
            refs.state = foundState
        end

        if foundMovement then
            refs.movement = foundMovement
            refs.originalIsDown = safeRaw(foundMovement, "isDown")
            refs.keys = safeRaw(foundMovement, "KEYS")
            refs.source = "DIRECT TABLE (isDown + spaceJumps + KEYS)"
        end

        if not foundWorld then
            log("WORLD BELUM DITEMUKAN")
        else
            log("WORLD OK", foundWorld.w, foundWorld.h)
        end

        if not foundStateFn then
            log("PLAYER STATE BELUM DITEMUKAN")
        else
            log("PLAYER STATE OK", foundState.x, foundState.y, foundState.vx)
        end

        if not foundMovement then
            log("MOVEMENT TABLE BELUM DITEMUKAN PADA SCAN INI")
        else
            log("MOVEMENT SOURCE:", refs.source)
            log("isDown:", tostring(safeRaw(foundMovement, "isDown")))
            log("spaceJumps:", tostring(safeRaw(foundMovement, "spaceJumps")))
            log("KEYS:", tostring(refs.keys))
        end

        return foundWorld ~= nil and foundStateFn ~= nil and foundMovement ~= nil,
            "world=" .. tostring(foundWorld ~= nil)
            .. ", state=" .. tostring(foundStateFn ~= nil)
            .. ", movement=" .. tostring(foundMovement ~= nil)
    end

    local function releaseAll()
        for key, _ in pairs(input) do
            input[key] = false
            held[key] = {}
            local button = buttons[key]
            if button and button.Parent then
                button.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
            end
        end
    end

    local function anyVirtualInput()
        return input.left or input.right or input.jump or input.down
    end

    local function buildWrapper(original)
        return function(saved, key, ...)
            -- Penting: panggil fungsi asli SELALU, agar keyboard fisik tetap bekerja.
            local physical = false
            if type(original) == "function" then
                local ok, result = pcall(original, saved, key, ...)
                if ok then physical = result end
            end

            -- Input virtual hanya ditambahkan. Tidak menggantikan input fisik.
            if key == "keyLeft" then
                return (physical == true) or input.left
            elseif key == "keyRight" then
                return (physical == true) or input.right
            elseif key == "keyJump" then
                return (physical == true) or input.jump
            elseif key == "keyDown" then
                return (physical == true) or input.down
            end

            -- Tombol lain tetap mengikuti fungsi asli.
            return physical
        end
    end

    local function unhookOld()
        local module = refs.movement
        local original = refs.originalIsDown
        local wrapper = refs.wrapper
        if module and original and wrapper
            and safeRaw(module, "isDown") == wrapper then
            pcall(function() module.isDown = original end)
            log("HOOK LAMA DIKEMBALIKAN KE FUNGSI ASLI")
        end
        refs.wrapper = nil
        refs.originalIsDown = nil
        connected = false
    end

    local function installHook()
        local module = refs.movement
        if not validMovementTable(module) then
            return false, "Movement table tidak valid"
        end

        local current = safeRaw(module, "isDown")
        if refs.wrapper and current == refs.wrapper then
            connected = true
            return true, "Hook masih aktif"
        end

        -- Jika game mengganti isDown pada tabel yang sama, gunakan fungsi baru.
        local original = current
        if type(original) ~= "function" then
            return false, "isDown bukan function"
        end

        local wrapper = buildWrapper(original)
        local ok, err = pcall(function()
            module.isDown = wrapper
        end)
        if not ok or safeRaw(module, "isDown") ~= wrapper then
            return false, "Gagal memasang hook: " .. tostring(err)
        end

        refs.originalIsDown = original
        refs.wrapper = wrapper
        connected = true
        log("HOOK MOVEMENT TERPASANG")
        return true, "isDown berhasil di-hook"
    end

    local function refreshState()
        if refs.stateFn then
            local value = readPlayerState(refs.stateFn)
            if value then
                refs.state = value
                return true
            end
        end
        return false
    end

    local function connectCycle()
        if scanning or not running then return end
        scanning = true
        setStatus("Scan dimulai dari objek game yang aktif...")

        -- Beberapa game menyiapkan world/module beberapa saat setelah spawn.
        local success = false
        local message = "Belum ditemukan"
        for attempt = 1, 30 do
            if not running then break end
            local ok, result = scanFromZero()
            message = result
            if ok then
                local hookOK, hookMessage = installHook()
                if hookOK then
                    success = true
                    message = hookMessage
                    break
                end
                message = hookMessage
            end
            setStatus("Menunggu komponen game... percobaan " .. attempt .. "/30 | " .. message)
            task.wait(0.5)
        end

        scanning = false
        if success then
            connected = true
            log("SEMUA KOMPONEN SIAP")
            setStatus("CONNECTED - input fisik + virtual aktif")
        else
            connected = false
            setStatus("Belum tersambung: " .. tostring(message))
            warn(PREFIX .. "Scan belum berhasil: " .. tostring(message))
        end
    end

    local function setInput(key, value)
        if not running then return end
        input[key] = value == true
        local button = buttons[key]
        if button and button.Parent then
            button.BackgroundColor3 = input[key]
                and Color3.fromRGB(35, 135, 90)
                or Color3.fromRGB(45, 45, 55)
        end
    end

    local function makeButton(parent, key, label, xScale, xOffset)
        local button = Instance.new("TextButton")
        button.Name = "GB_" .. key
        button.Size = UDim2.new(0.24, -5, 0, 48)
        button.Position = UDim2.new(xScale, xOffset, 0, 0)
        button.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
        button.BorderSizePixel = 0
        button.Text = label
        button.TextColor3 = Color3.new(1, 1, 1)
        button.TextSize = 14
        button.Font = Enum.Font.GothamBold
        button.AutoButtonColor = false
        button.Active = true
        button.Parent = parent
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = button
        buttons[key] = button

        button.InputBegan:Connect(function(obj)
            if obj.UserInputType == Enum.UserInputType.Touch
                or obj.UserInputType == Enum.UserInputType.MouseButton1 then
                held[key][obj] = true
                setInput(key, true)
            end
        end)
        return button
    end

    local function createUI()
        local parent
        if type(gethui) == "function" then
            local ok, value = pcall(gethui)
            if ok then parent = value end
        end
        if not parent then
            local ok, value = pcall(function() return CoreGui end)
            if ok then parent = value end
        end
        if not parent then parent = LocalPlayer:WaitForChild("PlayerGui") end

        gui = Instance.new("ScreenGui")
        gui.Name = "GB_Movement_AutoReconnect"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.Parent = parent

        panel = Instance.new("Frame")
        panel.Name = "Panel"
        panel.Size = UDim2.fromOffset(300, 190)
        panel.Position = UDim2.new(0.5, -150, 0.68, -95)
        panel.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
        panel.BorderSizePixel = 0
        panel.Active = true
        panel.Parent = gui
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = panel

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -12, 0, 25)
        title.Position = UDim2.fromOffset(8, 4)
        title.BackgroundTransparency = 1
        title.Text = "GROWBLOX MOVEMENT AUTO-RECONNECT"
        title.TextColor3 = Color3.new(1, 1, 1)
        title.TextSize = 12
        title.Font = Enum.Font.GothamBold
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = panel

        statusLabel = Instance.new("TextLabel")
        statusLabel.Size = UDim2.new(1, -16, 0, 66)
        statusLabel.Position = UDim2.fromOffset(8, 31)
        statusLabel.BackgroundColor3 = Color3.fromRGB(37, 37, 46)
        statusLabel.BorderSizePixel = 0
        statusLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
        statusLabel.TextSize = 10
        statusLabel.Font = Enum.Font.Code
        statusLabel.TextWrapped = true
        statusLabel.TextXAlignment = Enum.TextXAlignment.Left
        statusLabel.TextYAlignment = Enum.TextYAlignment.Top
        statusLabel.Parent = panel
        local sc = Instance.new("UICorner")
        sc.CornerRadius = UDim.new(0, 6)
        sc.Parent = statusLabel

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -16, 0, 48)
        row.Position = UDim2.fromOffset(8, 105)
        row.BackgroundTransparency = 1
        row.Parent = panel

        makeButton(row, "left", "KIRI", 0, 0)
        makeButton(row, "right", "KANAN", 0.25, 0)
        makeButton(row, "jump", "JUMP", 0.50, 0)
        makeButton(row, "down", "TURUN", 0.75, 0)

        local reconnect = Instance.new("TextButton")
        reconnect.Size = UDim2.new(0.62, -6, 0, 27)
        reconnect.Position = UDim2.fromOffset(8, 157)
        reconnect.BackgroundColor3 = Color3.fromRGB(55, 85, 135)
        reconnect.BorderSizePixel = 0
        reconnect.Text = "SCAN / CONNECT ULANG"
        reconnect.TextColor3 = Color3.new(1, 1, 1)
        reconnect.TextSize = 10
        reconnect.Font = Enum.Font.GothamBold
        reconnect.Parent = panel
        reconnect.Activated:Connect(function()
            if connected then
                unhookOld()
            end
            releaseAll()
            task.spawn(connectCycle)
        end)
        local rc = Instance.new("UICorner")
        rc.CornerRadius = UDim.new(0, 6)
        rc.Parent = reconnect

        local stop = Instance.new("TextButton")
        stop.Size = UDim2.new(0.38, -6, 0, 27)
        stop.Position = UDim2.new(0.62, 6, 0, 157)
        stop.BackgroundColor3 = Color3.fromRGB(145, 55, 60)
        stop.BorderSizePixel = 0
        stop.Text = "STOP"
        stop.TextColor3 = Color3.new(1, 1, 1)
        stop.TextSize = 10
        stop.Font = Enum.Font.GothamBold
        stop.Parent = panel
        local stc = Instance.new("UICorner")
        stc.CornerRadius = UDim.new(0, 6)
        stc.Parent = stop
        stop.Activated:Connect(function()
            if type(ENV.GB_MOVEMENT_STOP) == "function" then
                ENV.GB_MOVEMENT_STOP()
            end
        end)

        -- Geser panel dari area judul.
        local dragging, dragInput, dragStart, startPos
        title.InputBegan:Connect(function(obj)
            if obj.UserInputType == Enum.UserInputType.Touch
                or obj.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = obj.Position
                startPos = panel.Position
                obj.Changed:Connect(function()
                    if obj.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        title.InputChanged:Connect(function(obj)
            if obj.UserInputType == Enum.UserInputType.Touch
                or obj.UserInputType == Enum.UserInputType.MouseMovement then
                dragInput = obj
            end
        end)
        UIS.InputChanged:Connect(function(obj)
            if dragging and obj == dragInput then
                local delta = obj.Position - dragStart
                panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
    end

    -- Lepas tombol virtual walau jari dilepas di luar tombol.
    UIS.InputEnded:Connect(function(obj)
        for key, map in pairs(held) do
            if map[obj] then
                map[obj] = nil
                local stillHeld = next(map) ~= nil
                setInput(key, stillHeld)
            end
        end
    end)

    pcall(function()
        UIS.WindowFocusReleased:Connect(releaseAll)
    end)

    local function cleanup()
        if not running then return end
        running = false
        releaseAll()
        unhookOld()
        if gui then pcall(function() gui:Destroy() end) end
        log("CONTROLLER DIHENTIKAN DAN HOOK DIPULIHKAN")
    end
    ENV.GB_MOVEMENT_STOP = cleanup

    -- Character respawn biasanya menandakan state/world mungkin sedang dibangun ulang.
    if LocalPlayer then
        LocalPlayer.CharacterAdded:Connect(function()
            releaseAll()
            task.delay(1, function()
                if running then task.spawn(connectCycle) end
            end)
        end)
        LocalPlayer.CharacterRemoving:Connect(function()
            releaseAll()
        end)
    end

    createUI()
    setStatus("Controller dibuat; mulai scan dari nol...")
    log("MEMULAI SCAN DARI NOL")
    log("ACCOUNT:", LocalPlayer and LocalPlayer.Name or "tidak tersedia")
    log("USER ID:", LocalPlayer and LocalPlayer.UserId or "tidak tersedia")
    task.spawn(connectCycle)

    -- Watchdog: jika hook hilang/module diganti saat world reload, sambungkan ulang.
    task.spawn(function()
        while running do
            task.wait(1.25)
            if not running then break end

            local module = refs.movement
            local wrapper = refs.wrapper
            local hookStillInstalled = module and wrapper
                and safeRaw(module, "isDown") == wrapper

            if connected and not hookStillInstalled then
                log("HOOK / MODULE BERUBAH - INPUT DILEPAS, SCAN ULANG")
                releaseAll()
                refs.movement = nil
                refs.originalIsDown = nil
                refs.wrapper = nil
                connected = false
                task.spawn(connectCycle)
            elseif not connected and not scanning then
                task.spawn(connectCycle)
            elseif connected then
                refreshState()
                setStatus("Terhubung; input fisik + virtual aktif")
            end
        end
    end)
end

local ok, err = pcall(MAIN)
if not ok then
    warn("[GB AUTO MOVEMENT] FATAL: " .. tostring(err))
end
