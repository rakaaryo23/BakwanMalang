--==================================================
-- MODULE: AUTO COLLECT ACTION RECORDER
-- Read-only recorder for player movement, user input,
-- and inventory delta for item ID 3 (Dirt Seed).
-- Does NOT fire remotes or call game collect functions.
--==================================================

return function(Hub)
    Hub.RegisterTab("AutoCollect Recorder", function(page)
        local Players = game:GetService("Players")
        local UserInputService = game:GetService("UserInputService")
        local LocalPlayer = Players.LocalPlayer

        local Theme = {
            Background = Color3.fromRGB(250, 220, 228),
            Panel = Color3.fromRGB(239, 194, 207),
            Accent = Color3.fromRGB(171, 91, 119),
            Text = Color3.fromRGB(76, 43, 57),
            Muted = Color3.fromRGB(139, 96, 111),
            White = Color3.fromRGB(255, 249, 251),
            Green = Color3.fromRGB(55, 140, 90),
            Red = Color3.fromRGB(180, 65, 75),
        }

        local destroyed = false
        local recording = false
        local lines = {}
        local output
        local connections = {}
        local recordStarted = 0
        local lastSample = 0
        local lastPosition
        local stateRef
        local lastInventoryCount
        local inventoryRef
        local ITEM_ID = 3
        local SAMPLE_INTERVAL = 0.20
        local MAX_LINES = 1200

        local function create(className, properties, parent)
            local object = Instance.new(className)
            for property, value in pairs(properties or {}) do object[property] = value end
            object.Parent = parent
            return object
        end

        local function corner(object, radius)
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, radius or 7)
            c.Parent = object
        end

        local function safeString(value)
            local ok, result = pcall(tostring, value)
            if not ok then return "?" end
            return result:gsub("\n", " "):gsub("\r", " ")
        end

        local function elapsed()
            return string.format("+%.2fs", math.max(0, os.clock() - recordStarted))
        end

        local function append(message)
            if destroyed or Hub.IsClosing() then return end
            local line = (recording and elapsed() or os.date("%H:%M:%S")) .. " | " .. safeString(message)
            lines[#lines + 1] = line
            while #lines > MAX_LINES do table.remove(lines, 1) end
            if output and output.Parent then
                output.Text = table.concat(lines, "\n")
                output.CursorPosition = -1
            end
            print("[AC-RECORDER] " .. line)
        end

        local function setStatus(value, color)
            status.Text = "Status: " .. value
            if color then status.TextColor3 = color end
        end

        local function raw(t, key)
            if type(t) ~= "table" then return nil end
            local ok, value = pcall(rawget, t, key)
            return ok and value or nil
        end

        local function isInventoryCandidate(t)
            if type(t) ~= "table" then return false end
            local slots, capacity = raw(t, "slots"), raw(t, "capacity")
            if type(slots) ~= "table" or type(capacity) ~= "number" or capacity < 0 or capacity > 10000 then
                return false
            end
            local valid = 0
            for key, slot in pairs(slots) do
                if type(key) == "number" and type(slot) == "table"
                    and (raw(slot, "id") ~= nil or raw(slot, "n") ~= nil) then
                    valid += 1
                    if valid >= 2 then break end
                end
            end
            return valid > 0 or next(slots) == nil
        end

        local function findInventory()
            if inventoryRef and isInventoryCandidate(inventoryRef) then return inventoryRef end
            inventoryRef = nil
            local getter = getgc
            if type(getter) ~= "function" then return nil end
            local ok, objects = pcall(getter, true)
            if not ok or type(objects) ~= "table" then return nil end
            local best, bestScore = nil, -1
            for _, object in ipairs(objects) do
                if isInventoryCandidate(object) then
                    local slots = raw(object, "slots")
                    local score = 0
                    for _, slot in pairs(slots) do
                        if type(slot) == "table" and tonumber(raw(slot, "id")) then score += 2 end
                    end
                    score += math.min(tonumber(raw(object, "capacity")) or 0, 100) / 100
                    if score > bestScore then best, bestScore = object, score end
                end
            end
            inventoryRef = best
            return best
        end

        local function countItem3()
            local inv = findInventory()
            if not inv then return nil end
            local slots = raw(inv, "slots")
            local total = 0
            for _, slot in pairs(slots) do
                if type(slot) == "table" and tonumber(raw(slot, "id")) == ITEM_ID then
                    total += tonumber(raw(slot, "n")) or 0
                end
            end
            return total
        end

        -- GrowBlox tidak selalu memakai Character/HumanoidRootPart Roblox standar.
        -- APB V4 menemukan state player melalui tabel GC yang memiliki state() -> {x,y,facing,vx,...}.
        local function findGameState()
            stateRef = nil
            if type(getgc) ~= "function" then return nil, "getgc tidak tersedia" end
            local ok, objects = pcall(getgc, true)
            if not ok or type(objects) ~= "table" then
                return nil, "getgc(true) gagal"
            end
            for _, obj in ipairs(objects) do
                if type(obj) == "table" then
                    local candidate = raw(obj, "state")
                    if type(candidate) == "function" then
                        local good, state = pcall(candidate)
                        if good and type(state) == "table"
                            and type(state.x) == "number"
                            and type(state.y) == "number"
                            and state.facing ~= nil and state.vx ~= nil then
                            stateRef = candidate
                            return stateRef, "state() GrowBlox ditemukan"
                        end
                    end
                end
            end
            return nil, "fungsi state() GrowBlox tidak ditemukan"
        end

        local function getCharacterState()
            if not stateRef then return nil end
            local ok, state = pcall(stateRef)
            if not ok or type(state) ~= "table"
                or type(state.x) ~= "number"
                or type(state.y) ~= "number" then
                return nil
            end
            if state.active == false then return nil end
            return {
                x = state.x, y = state.y,
                vx = tonumber(state.vx) or 0,
                vy = tonumber(state.vy) or 0,
                facing = safeString(state.facing),
                active = safeString(state.active),
            }
        end

        local function round(n)
            return math.floor((n or 0) * 100 + 0.5) / 100
        end

        local function recordMovement(state)
            if not state then
                append("PLAYER STATE unavailable (state() GrowBlox belum terbaca)")
                return
            end
            if not lastPosition then
                append(("POS awal tile/world X=%.3f Y=%.3f | VEL %.3f, %.3f | facing=%s")
                    :format(state.x, state.y, state.vx, state.vy, state.facing))
            else
                local dx, dy = state.x - lastPosition.x, state.y - lastPosition.y
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance >= 0.003 then
                    append(("MOVE Δ=%.4f | POS %.3f, %.3f | ΔX=%.4f ΔY=%.4f | VEL %.3f, %.3f | facing=%s")
                        :format(distance, state.x, state.y, dx, dy, state.vx, state.vy, state.facing))
                end
            end
            lastPosition = {x = state.x, y = state.y}
        end

        local function stopRecording(reason)
            if not recording then return end
            recording = false
            setStatus("STOPPED - " .. (reason or "manual"), Theme.Red)
            append("=== RECORDING STOP === " .. (reason or "manual"))
            append("Total baris feedback: " .. tostring(#lines))
            stopButton.Text = "RECORDING STOPPED"
            startButton.Text = "START RECORDING"
        end

        local function startRecording()
            if recording then return end
            lines = {}
            output.Text = ""
            recordStarted = os.clock()
            lastSample = 0
            lastPosition = nil
            inventoryRef = nil
            local foundState, stateMessage = findGameState()
            append("PLAYER SCAN: " .. stateMessage)
            lastPosition = nil
            lastInventoryCount = countItem3()
            recording = true
            setStatus("RECORDING - ambil 1 Dirt Seed (ID 3)", Theme.Green)
            append("=== RECORDING START ===")
            append("Target item: Dirt Seed | ID=" .. ITEM_ID)
            append("Inventory count awal ID 3 = " .. (lastInventoryCount == nil and "TIDAK TERBACA" or tostring(lastInventoryCount)))
            append("Lakukan satu kali take/pickup, lalu tekan STOP RECORDING.")
            startButton.Text = "RECORDING..."
        end

        local layout = create("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, page)
        local intro = create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 55), BackgroundTransparency = 1,
            Text = "ACTION RECORDER V2 | Membaca state() internal GrowBlox (bukan HumanoidRootPart), input klik/tap, dan perubahan jumlah Dirt Seed ID 3. READ-ONLY.",
            TextColor3 = Theme.Text, Font = Enum.Font.Gotham, TextSize = 10,
            TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
        }, page)

        local status = create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 27), BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0, Text = "Status: siap", TextColor3 = Theme.Text,
            Font = Enum.Font.GothamBold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
        }, page)
        corner(status, 6)

        local startButton = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Theme.Green,
            BorderSizePixel = 0, Text = "START RECORDING", TextColor3 = Theme.White,
            Font = Enum.Font.GothamBold, TextSize = 11,
        }, page)
        corner(startButton, 7)

        local stopButton = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Theme.Red,
            BorderSizePixel = 0, Text = "STOP RECORDING", TextColor3 = Theme.White,
            Font = Enum.Font.GothamBold, TextSize = 11,
        }, page)
        corner(stopButton, 7)

        local copyButton = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0, Text = "COPY FEEDBACK", TextColor3 = Theme.White,
            Font = Enum.Font.GothamBold, TextSize = 11,
        }, page)
        corner(copyButton, 7)

        local clearButton = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0, Text = "CLEAR FEEDBACK", TextColor3 = Theme.Text,
            Font = Enum.Font.GothamBold, TextSize = 10,
        }, page)
        corner(clearButton, 7)

        output = create("TextBox", {
            Size = UDim2.new(1, 0, 0, 300), BackgroundColor3 = Color3.fromRGB(255, 245, 248),
            BorderSizePixel = 0, Text = "V2: Tekan START RECORDING, ambil tepat 1 Dirt Seed (ID 3), lalu STOP dan COPY FEEDBACK.",
            TextColor3 = Theme.Text, PlaceholderColor3 = Theme.Muted,
            Font = Enum.Font.Code, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = false,
            MultiLine = true, ClearTextOnFocus = false, TextEditable = false,
        }, page)
        corner(output, 7)

        connections[#connections + 1] = startButton.Activated:Connect(startRecording)
        connections[#connections + 1] = stopButton.Activated:Connect(function() stopRecording("manual") end)
        connections[#connections + 1] = copyButton.Activated:Connect(function()
            local text = table.concat(lines, "\n")
            local copier = setclipboard or toclipboard
            if type(copier) == "function" then
                local ok, err = pcall(copier, text)
                if ok then setStatus("feedback berhasil dicopy", Theme.Green); append("Feedback disalin ke clipboard.")
                else setStatus("copy gagal: " .. safeString(err), Theme.Red) end
            else
                setStatus("executor tidak menyediakan clipboard", Theme.Red)
            end
        end)
        connections[#connections + 1] = clearButton.Activated:Connect(function()
            if recording then stopRecording("log dibersihkan") end
            lines = {}
            output.Text = ""
            append("Feedback dikosongkan.")
            setStatus("siap", Theme.Text)
        end)

        connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input, processed)
            if not recording or processed then return end
            local inputType = safeString(input.UserInputType)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                local pos = input.Position
                append(("INPUT %s at X=%d Y=%d"):format(inputType, math.floor(pos.X), math.floor(pos.Y)))
            elseif input.UserInputType == Enum.UserInputType.Keyboard then
                append("KEY " .. safeString(input.KeyCode))
            end
        end)

        task.spawn(function()
            while not destroyed and not Hub.IsClosing() do
                if recording and os.clock() - lastSample >= SAMPLE_INTERVAL then
                    lastSample = os.clock()
                    local state = getCharacterState()
                    recordMovement(state)
                    local currentCount = countItem3()
                    if currentCount == nil then
                        if lastInventoryCount ~= nil then append("INVENTORY scan tidak terbaca pada sample ini") end
                    elseif lastInventoryCount == nil then
                        append("INVENTORY ID 3 sekarang = " .. tostring(currentCount))
                    elseif currentCount ~= lastInventoryCount then
                        local delta = currentCount - lastInventoryCount
                        append(("INVENTORY CHANGE itemID=3 | %d -> %d | delta=%+d"):format(lastInventoryCount, currentCount, delta))
                        if delta > 0 then append("POTENTIAL PICKUP: jumlah Dirt Seed ID 3 bertambah " .. tostring(delta)) end
                    end
                    lastInventoryCount = currentCount
                end
                task.wait(0.05)
            end
        end)

        local function cleanup()
            if destroyed then return end
            destroyed = true
            recording = false
            for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
            table.clear(connections)
        end
        Hub.RegisterCleanup(cleanup)
        append("Module V2 aktif. Posisi dibaca melalui state() internal GrowBlox seperti APB V4. Pastikan inventory awal item ID 3 terlihat sebelum mulai.")
    end)
end
