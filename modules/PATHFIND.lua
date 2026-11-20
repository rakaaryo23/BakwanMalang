--==================================================
-- MODULE: DIRT FARM PATHFINDING
-- Tab mandiri: LOCK COORDINAT -> GO -> STOP
-- Menggunakan playerState + movement hook dari game.
-- Tidak mengubah module lain.
--==================================================

return function(Hub)
    Hub.RegisterTab("DIRT FARM PATHFINDING", function(page)
        local Players = game:GetService("Players")
        local UIS = game:GetService("UserInputService")
        local LocalPlayer = Players.LocalPlayer

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
            Dark = Color3.fromRGB(45, 45, 55),
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

        local function makeLabel(text, height, parent)
            return create("TextLabel", {
                Size = UDim2.new(1, 0, 0, height or 25),
                BackgroundTransparency = 1,
                Text = text or "",
                TextColor3 = Theme.Text,
                Font = Enum.Font.Gotham,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Center,
                TextWrapped = true,
            }, parent)
        end

        local function makeButton(text, height, parent, color)
            local b = create("TextButton", {
                Size = UDim2.new(1, 0, 0, height or 34),
                BackgroundColor3 = color or Theme.Accent,
                BorderSizePixel = 0,
                Text = text,
                TextColor3 = Theme.White,
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                AutoButtonColor = true,
            }, parent)
            corner(b, 7)
            return b
        end

        local connections = {}
        local function track(connection)
            connections[#connections + 1] = connection
            return connection
        end

        local running = true
        local connected = false
        local scanning = false
        local goRunning = false
        local stopRequested = false
        local scanCount = 0
        local lastMessage = "Belum melakukan scan"
        local lockedTarget = nil
        local activeDirection = nil

        local refs = {
            world = nil,
            stateFn = nil,
            state = nil,
            movement = nil,
            originalIsDown = nil,
            wrapper = nil,
            keys = nil,
        }

        local input = { left = false, right = false, jump = false, down = false }

        local function log(...)
            print("[DIRT FARM PATHFINDING]", ...)
        end

        local statusLabel
        local targetLabel
        local positionLabel
        local directionLabel

        local function setStatus(message)
            lastMessage = tostring(message or "-")
            if statusLabel and statusLabel.Parent then
                statusLabel.Text = "STATUS: " .. lastMessage
            end
            log(lastMessage)
        end

        local function safeRaw(t, key)
            if type(t) ~= "table" then return nil end
            local ok, value = pcall(rawget, t, key)
            return ok and value or nil
        end

        local function readState(fn)
            if type(fn) ~= "function" then return nil end
            local ok, value = pcall(fn)
            if not ok or type(value) ~= "table" then return nil end
            if type(value.x) ~= "number" or type(value.y) ~= "number" then return nil end
            if value.facing == nil or value.vx == nil or value.active == false then return nil end
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

        local function validMovement(t)
            if type(t) ~= "table" then return false end
            return type(safeRaw(t, "isDown")) == "function"
                and type(safeRaw(t, "spaceJumps")) == "function"
                and validKeys(safeRaw(t, "KEYS"))
        end

        local function getGC()
            if type(getgc) ~= "function" then return nil, "Executor tidak menyediakan getgc" end
            local ok, objects = pcall(getgc, true)
            if not ok or type(objects) ~= "table" then
                return nil, "getgc(true) gagal: " .. tostring(objects)
            end
            return objects
        end

        local function scanFromZero()
            scanCount += 1
            local objects, err = getGC()
            if not objects then return false, err end

            local foundWorld, foundStateFn, foundState, foundMovement
            for _, object in ipairs(objects) do
                if type(object) == "table" then
                    if not foundWorld and validWorld(object) then
                        foundWorld = object
                    end
                    if not foundStateFn then
                        local candidate = safeRaw(object, "state")
                        local value = readState(candidate)
                        if value then
                            foundStateFn, foundState = candidate, value
                        end
                    end
                    if not foundMovement and validMovement(object) then
                        foundMovement = object
                    end
                    if foundWorld and foundStateFn and foundMovement then break end
                end
            end

            if foundWorld then refs.world = foundWorld end
            if foundStateFn then refs.stateFn, refs.state = foundStateFn, foundState end
            if foundMovement then
                refs.movement = foundMovement
                refs.originalIsDown = safeRaw(foundMovement, "isDown")
                refs.keys = safeRaw(foundMovement, "KEYS")
            end

            local ok = refs.world ~= nil and refs.stateFn ~= nil and refs.movement ~= nil
            return ok, string.format("world=%s | state=%s | movement=%s",
                tostring(refs.world ~= nil), tostring(refs.stateFn ~= nil), tostring(refs.movement ~= nil))
        end

        local function releaseAll()
            for key in pairs(input) do input[key] = false end
            activeDirection = nil
            if directionLabel and directionLabel.Parent then
                directionLabel.Text = "INPUT: NONE"
            end
        end

        local function setInput(key, value)
            if not running then return end
            input[key] = value == true
            if directionLabel and directionLabel.Parent then
                local active = {}
                for k, v in pairs(input) do
                    if v then active[#active + 1] = string.upper(k) end
                end
                directionLabel.Text = "INPUT: " .. (#active > 0 and table.concat(active, " + ") or "NONE")
            end
        end

        local function buildWrapper(original)
            return function(saved, key, ...)
                local physical = false
                if type(original) == "function" then
                    local ok, result = pcall(original, saved, key, ...)
                    if ok then physical = result end
                end
                if key == "keyLeft" then return physical == true or input.left end
                if key == "keyRight" then return physical == true or input.right end
                if key == "keyJump" then return physical == true or input.jump end
                if key == "keyDown" then return physical == true or input.down end
                return physical
            end
        end

        local function unhook()
            local module = refs.movement
            local original = refs.originalIsDown
            local wrapper = refs.wrapper
            if module and original and wrapper and safeRaw(module, "isDown") == wrapper then
                pcall(function() module.isDown = original end)
            end
            refs.wrapper = nil
            refs.originalIsDown = nil
            connected = false
        end

        local function installHook()
            if not validMovement(refs.movement) then return false, "Movement table tidak valid" end
            local current = safeRaw(refs.movement, "isDown")
            if refs.wrapper and current == refs.wrapper then
                connected = true
                return true, "Hook masih aktif"
            end
            if type(current) ~= "function" then return false, "isDown bukan function" end
            local wrapper = buildWrapper(current)
            local ok, err = pcall(function() refs.movement.isDown = wrapper end)
            if not ok or safeRaw(refs.movement, "isDown") ~= wrapper then
                return false, "Gagal memasang hook: " .. tostring(err)
            end
            refs.originalIsDown = current
            refs.wrapper = wrapper
            connected = true
            return true, "Movement hook terpasang"
        end

        local function connectCycle()
            if scanning or not running then return end
            scanning = true
            setStatus("Scan komponen game...")
            local success, message = false, "Belum ditemukan"
            for attempt = 1, 30 do
                if not running then break end
                local ok, result = scanFromZero()
                message = result
                if ok then
                    local hookOK, hookMessage = installHook()
                    if hookOK then success, message = true, hookMessage break end
                    message = hookMessage
                end
                setStatus("Menunggu komponen game " .. attempt .. "/30 | " .. tostring(message))
                task.wait(0.5)
            end
            scanning = false
            if success then
                connected = true
                setStatus("TERHUBUNG. LOCK COORDINAT sudah bisa digunakan.")
            else
                connected = false
                setStatus("SCAN BELUM BERHASIL: " .. tostring(message))
            end
        end

        local function currentState()
            local state = readState(refs.stateFn)
            if state then refs.state = state end
            return state
        end

        local function playerTileY(state)
            -- Mengikuti konvensi tile player dari module utama.
            return math.floor(state.y - 0.475)
        end

        local function getRowBounds(rowY)
            local world = refs.world
            if not world then return nil end
            local row = world.fg and world.fg[rowY]
            if type(row) ~= "table" then return nil end

            local minX, maxX, count
            count = 0
            for x = 0, world.w - 1 do
                local id = row[x]
                if id ~= nil and id ~= 0 then
                    count += 1
                    if minX == nil or x < minX then minX = x end
                    if maxX == nil or x > maxX then maxX = x end
                end
            end
            if not minX then return nil end
            return minX, maxX, count
        end

        local function waitStep()
            task.wait(0.04)
            if not running or stopRequested or not goRunning then return nil end
            return currentState()
        end

        local function moveHorizontalTo(xGoal, tolerance)
            tolerance = tolerance or 0.12
            while goRunning and not stopRequested do
                local state = currentState()
                if not state then return false, "PlayerState tidak terbaca" end
                positionLabel.Text = string.format("POSISI: X %.2f | Y %.2f", state.x, state.y)
                local dx = xGoal - state.x
                if math.abs(dx) <= tolerance then
                    releaseAll()
                    return true
                end
                if dx > 0 then
                    setInput("left", false)
                    setInput("right", true)
                else
                    setInput("right", false)
                    setInput("left", true)
                end
                if not waitStep() then return false, "GO dihentikan atau state hilang" end
            end
            return false, "GO dihentikan"
        end

        local function crossOneFarmRow(direction)
            local state = currentState()
            if not state then return false, "PlayerState tidak terbaca" end
            local rowY = playerTileY(state)
            local minX, maxX = getRowBounds(rowY)
            if not minX then
                return false, "Barisan FG tidak ditemukan pada Y=" .. tostring(rowY)
            end

            local corridorTileX
            if direction == "UP" then
                -- Aturan Dirt Farm: perpindahan naik melalui lorong kanan.
                corridorTileX = maxX + 1
            else
                -- Aturan Dirt Farm: perpindahan turun melalui lorong kiri.
                corridorTileX = minX - 1
            end

            if corridorTileX < 0 or corridorTileX >= refs.world.w then
                return false, "Lorong " .. direction .. " berada di luar batas world"
            end

            local corridorCenter = corridorTileX + 0.5
            setStatus(string.format("MENUJU LORONG %s | ROW %d | X %.1f", direction, rowY, corridorCenter))
            local reached, moveError = moveHorizontalTo(corridorCenter, 0.16)
            if not reached then return false, moveError end

            local startRow = rowY
            setStatus("MELINTASI LORONG " .. direction .. " | ROW " .. startRow)
            if direction == "UP" then
                setInput("jump", true)
                setInput("down", false)
            else
                setInput("jump", false)
                setInput("down", true)
            end

            local changed = false
            while goRunning and not stopRequested do
                local now = currentState()
                if not now then
                    releaseAll()
                    return false, "PlayerState hilang saat melewati lorong"
                end
                local nowRow = playerTileY(now)
                positionLabel.Text = string.format("POSISI: X %.2f | Y %.2f | ROW %d", now.x, now.y, nowRow)
                if direction == "UP" and nowRow < startRow then
                    changed = true
                    break
                elseif direction == "DOWN" and nowRow > startRow then
                    changed = true
                    break
                end
                if not waitStep() then break end
            end

            releaseAll()
            if not changed then return false, "Perpindahan baris tidak terdeteksi" end
            task.wait(0.08)
            return true
        end

        local function navigateToLocked()
            if not lockedTarget then
                setStatus("BELUM ADA KOORDINAT LOCK. TEKAN LOCK COORDINAT.")
                return
            end
            if not connected or not refs.stateFn or not refs.world then
                setStatus("MOVEMENT BELUM TERHUBUNG. SCAN / CONNECT ULANG DULU.")
                return
            end
            if goRunning then return end

            goRunning = true
            stopRequested = false
            local target = { x = lockedTarget.x, y = lockedTarget.y }
            setStatus(string.format("GO DIMULAI | TARGET X %.2f Y %.2f", target.x, target.y))

            task.spawn(function()
                local success, reason = pcall(function()
                    local tolerance = 0.16
                    local maxTransitions = math.max(1, refs.world.h + 2)
                    local transitions = 0

                    while goRunning and not stopRequested do
                        local state = currentState()
                        if not state then error("PlayerState tidak terbaca") end

                        positionLabel.Text = string.format("POSISI: X %.2f | Y %.2f", state.x, state.y)
                        local currentRow = playerTileY(state)
                        local targetRow = playerTileY(target)

                        if currentRow == targetRow then
                            local moved, moveError = moveHorizontalTo(target.x, tolerance)
                            if not moved then error(moveError) end

                            -- Tunggu posisi state mendekati koordinat LOCK, bukan hanya tile yang sama.
                            while goRunning and not stopRequested do
                                local finalState = currentState()
                                if not finalState then error("PlayerState tidak terbaca saat verifikasi tujuan") end
                                positionLabel.Text = string.format("POSISI: X %.2f | Y %.2f", finalState.x, finalState.y)
                                local dx = math.abs(finalState.x - target.x)
                                local dy = math.abs(finalState.y - target.y)
                                if dx <= tolerance and dy <= 0.22 then
                                    releaseAll()
                                    setStatus(string.format("TUJUAN TERCAPAI | X %.2f Y %.2f", finalState.x, finalState.y))
                                    return
                                end
                                if dx > tolerance then
                                    local ok, err = moveHorizontalTo(target.x, tolerance)
                                    if not ok then error(err) end
                                end
                                if not waitStep() then break end
                            end
                            if stopRequested then return end
                            error("Posisi belum mencapai koordinat LOCK")
                        end

                        transitions += 1
                        if transitions > maxTransitions then error("Batas perpindahan baris terlampaui") end

                        local direction = targetRow < currentRow and "UP" or "DOWN"
                        local crossed, crossError = crossOneFarmRow(direction)
                        if not crossed then error(crossError) end
                    end
                end)

                releaseAll()
                goRunning = false
                stopRequested = false
                if not success then
                    setStatus("GO BERHENTI: " .. tostring(reason))
                end
            end)
        end

        --==================================================
        -- UI
        --==================================================
        local layout = create("UIListLayout", {
            Padding = UDim.new(0, 7),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, page)

        local header = makeButton("DIRT FARM PATHFINDING", 36, page, Theme.PanelDark)
        header.TextColor3 = Theme.Text
        header.LayoutOrder = 1

        local panel = create("Frame", {
            Name = "DirtFarmPathfindingPanel",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            LayoutOrder = 2,
        }, page)
        corner(panel, 8)
        create("UIPadding", {
            PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
        }, panel)
        create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, panel)

        statusLabel = create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 42),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            Text = "STATUS: Menunggu scan...",
            TextColor3 = Theme.Text,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = 1,
        }, panel)
        corner(statusLabel, 6)

        targetLabel = makeLabel("TARGET LOCK: BELUM ADA", 25, panel)
        targetLabel.LayoutOrder = 2
        positionLabel = makeLabel("POSISI: BELUM TERBACA", 25, panel)
        positionLabel.LayoutOrder = 3
        directionLabel = makeLabel("INPUT: NONE", 22, panel)
        directionLabel.LayoutOrder = 4

        local lockButton = makeButton("LOCK COORDINAT", 38, panel, Theme.Accent)
        lockButton.LayoutOrder = 5
        local goButton = makeButton("GO", 38, panel, Theme.Green)
        goButton.LayoutOrder = 6
        local stopButton = makeButton("STOP", 38, panel, Theme.Red)
        stopButton.LayoutOrder = 7
        local scanButton = makeButton("SCAN / CONNECT ULANG", 32, panel, Theme.PanelDark)
        scanButton.TextColor3 = Theme.Text
        scanButton.LayoutOrder = 8

        track(header.Activated:Connect(function()
            panel.Visible = not panel.Visible
            header.Text = panel.Visible and "DIRT FARM PATHFINDING  ▲" or "DIRT FARM PATHFINDING  ▼"
        end))

        track(lockButton.Activated:Connect(function()
            if not connected then
                setStatus("LOCK GAGAL: MOVEMENT BELUM TERHUBUNG")
                return
            end
            local state = currentState()
            if not state then
                setStatus("LOCK GAGAL: PLAYERSTATE TIDAK TERBACA")
                return
            end
            lockedTarget = { x = state.x, y = state.y }
            targetLabel.Text = string.format("TARGET LOCK: X %.3f | Y %.3f", lockedTarget.x, lockedTarget.y)
            setStatus("KOORDINAT TERKUNCI. NILAI TARGET TIDAK BERUBAH SAAT PLAYER BERGERAK.")
        end))

        track(goButton.Activated:Connect(navigateToLocked))

        track(stopButton.Activated:Connect(function()
            stopRequested = true
            goRunning = false
            releaseAll()
            setStatus("STOP DIMINTA. INPUT DILEPAS DAN LOOP STATE DIHENTIKAN.")
        end))

        track(scanButton.Activated:Connect(function()
            if goRunning then
                setStatus("STOP GO TERLEBIH DAHULU SEBELUM SCAN ULANG")
                return
            end
            if connected then unhook() end
            releaseAll()
            task.spawn(connectCycle)
        end))

        -- Tidak ada polling state permanen. State hanya dibaca saat LOCK atau selama GO.
        local function cleanup()
            if not running then return end
            running = false
            stopRequested = true
            goRunning = false
            releaseAll()
            unhook()
            for _, connection in ipairs(connections) do
                pcall(function() connection:Disconnect() end)
            end
            table.clear(connections)
            log("MODULE DITUTUP; INPUT DILEPAS DAN HOOK DIPULIHKAN")
        end

        track(UIS.WindowFocusReleased:Connect(function()
            if goRunning then
                stopRequested = true
                goRunning = false
                releaseAll()
                setStatus("WINDOW FOCUS HILANG. GO DIHENTIKAN.")
            end
        end))

        if LocalPlayer then
            track(LocalPlayer.CharacterRemoving:Connect(function()
                stopRequested = true
                goRunning = false
                releaseAll()
            end))
        end

        Hub.RegisterCleanup(cleanup)
        setStatus("Module dimuat. Memulai scan awal untuk mengaktifkan Movement.")
        task.spawn(connectCycle)
        print("[DIRT FARM PATHFINDING] Module loaded.")
    end)
end

--==================================================
-- END MODULE: DIRT FARM PATHFINDING
--==================================================
