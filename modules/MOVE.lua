--==================================================
-- MODULE: INPUT RECORDER - GROWBLOX HUB
-- Merekam input keyboard/touch dan GUI yang disentuh.
-- Standalone: tidak membutuhkan k.lua, Gerak.lua, atau WorldMenu.
--==================================================

return function(Hub)
    assert(Hub and type(Hub.RegisterTab) == "function",
        "InputRecorder membutuhkan Hub.RegisterTab")

    Hub.RegisterTab("Input Recorder", function(page)
        local Players = game:GetService("Players")
        local UIS = game:GetService("UserInputService")
        local player = Players.LocalPlayer
        local playerGui = player:WaitForChild("PlayerGui")

        local alive = true
        local recording = false
        local connections = {}
        local startedAt = 0
        local records = {}
        local sequence = 0
        local activeInputs = {}
        local maxLines = 80

        local C = {
            accent = Color3.fromRGB(171, 91, 119),
            active = Color3.fromRGB(65, 155, 105),
            panel = Color3.fromRGB(38, 38, 45),
            text = Color3.fromRGB(245, 240, 243),
            muted = Color3.fromRGB(180, 170, 178),
            red = Color3.fromRGB(170, 70, 75),
        }

        local function track(conn)
            table.insert(connections, conn)
            return conn
        end

        local function make(className, props, parent)
            local obj = Instance.new(className)
            for k, v in pairs(props or {}) do obj[k] = v end
            obj.Parent = parent or page
            return obj
        end

        local function round(obj, radius)
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, radius or 8)
            c.Parent = obj
        end

        local root = make("Frame", {
            Name = "InputRecorderPanel",
            Size = UDim2.new(1, 0, 0, 390),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        })

        make("TextLabel", {
            Name = "Description",
            Size = UDim2.new(1, 0, 0, 38),
            BackgroundTransparency = 1,
            Text = "Rekam keyboard, sentuhan, dan tombol GUI yang disentuh.",
            TextColor3 = C.text,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, root)

        local status = make("TextLabel", {
            Name = "RecorderStatus",
            Position = UDim2.fromOffset(0, 38),
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 1,
            Text = "Status: berhenti | Event: 0",
            TextColor3 = C.muted,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, root)

        local controls = make("Frame", {
            Position = UDim2.fromOffset(0, 66),
            Size = UDim2.new(1, 0, 0, 38),
            BackgroundTransparency = 1,
        }, root)
        make("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, controls)

        local function actionButton(name, caption, color, order)
            local b = make("TextButton", {
                Name = name,
                Size = UDim2.new(0.333, -5, 1, 0),
                BackgroundColor3 = color,
                BorderSizePixel = 0,
                Text = caption,
                TextColor3 = C.text,
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                LayoutOrder = order,
                AutoButtonColor = true,
            }, controls)
            round(b, 7)
            return b
        end

        local startButton = actionButton("StartRecord", "MULAI REKAM", C.active, 1)
        local stopButton = actionButton("StopRecord", "STOP", C.red, 2)
        local clearButton = actionButton("ClearRecord", "BERSIHKAN", C.accent, 3)

        local log = make("ScrollingFrame", {
            Name = "InputLog",
            Position = UDim2.fromOffset(0, 112),
            Size = UDim2.new(1, 0, 0, 232),
            BackgroundColor3 = C.panel,
            BorderSizePixel = 0,
            ScrollBarThickness = 5,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
        }, root)
        round(log, 7)
        make("UIPadding", {
            PaddingTop = UDim.new(0, 6),
            PaddingBottom = UDim.new(0, 6),
            PaddingLeft = UDim.new(0, 8),
            PaddingRight = UDim.new(0, 8),
        }, log)
        make("UIListLayout", {
            Padding = UDim.new(0, 3),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, log)

        local exportButton = make("TextButton", {
            Name = "CopyLog",
            Position = UDim2.fromOffset(0, 352),
            Size = UDim2.new(1, 0, 0, 32),
            BackgroundColor3 = C.accent,
            BorderSizePixel = 0,
            Text = "SALIN LOG KE CONSOLE",
            TextColor3 = C.text,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
        }, root)
        round(exportButton, 7)

        local function elapsed()
            if not recording then return 0 end
            return math.max(0, os.clock() - startedAt)
        end

        local function formatTime(seconds)
            return string.format("%07.3f", seconds)
        end

        local function updateStatus()
            status.Text = string.format("Status: %s | Event: %d",
                recording and "MEREKAM" or "berhenti", #records)
            status.TextColor3 = recording and C.active or C.muted
        end

        local function addRecord(kind, input, target, extra)
            if not recording then return end
            sequence += 1
            local userInputType = input and input.UserInputType and input.UserInputType.Name or "?"
            local keyCode = input and input.KeyCode and input.KeyCode.Name or "Unknown"
            local line = string.format("[%s] %s | Type=%s | Key=%s",
                formatTime(elapsed()), kind, userInputType, keyCode)
            if target and target ~= "" then line ..= " | Target=" .. target end
            if extra and extra ~= "" then line ..= " | " .. extra end

            table.insert(records, {
                time = elapsed(), kind = kind, inputType = userInputType,
                keyCode = keyCode, target = target or "", line = line,
            })

            local label = make("TextLabel", {
                Name = "Event_" .. sequence,
                Size = UDim2.new(1, -4, 0, 30),
                BackgroundTransparency = 1,
                Text = line,
                TextColor3 = C.text,
                Font = Enum.Font.Code,
                TextSize = 10,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = sequence,
            }, log)
            if #records > maxLines then
                local oldest = log:FindFirstChild("Event_" .. (sequence - maxLines))
                if oldest then oldest:Destroy() end
            end
            updateStatus()
            task.defer(function()
                if log and log.Parent then
                    log.CanvasPosition = Vector2.new(0, math.max(0, log.AbsoluteCanvasSize.Y))
                end
            end)
        end

        local function isRecorderObject(obj)
            return obj == root or obj:IsDescendantOf(root)
        end

        -- Cari elemen GUI paling atas tepat di koordinat sentuhan.
        local function guiAt(position)
            local bestButton, bestButtonZ = nil, -math.huge
            local bestObject, bestObjectZ = nil, -math.huge
            for _, obj in ipairs(playerGui:GetDescendants()) do
                if obj:IsA("GuiObject") and obj.Visible and not isRecorderObject(obj) then
                    local ok, inside = pcall(function()
                        local p, s = obj.AbsolutePosition, obj.AbsoluteSize
                        return position.X >= p.X and position.X <= p.X + s.X
                            and position.Y >= p.Y and position.Y <= p.Y + s.Y
                    end)
                    if ok and inside then
                        local z = obj.ZIndex
                        if z >= bestObjectZ then bestObject, bestObjectZ = obj, z end
                        if obj:IsA("GuiButton") and z >= bestButtonZ then
                            bestButton, bestButtonZ = obj, z
                        end
                    end
                end
            end
            -- Prioritaskan tombol yang benar-benar dapat ditekan; bila kontrol
            -- memakai joystick/frame, tampilkan GuiObject teratas sebagai fallback.
            local best = bestButton or bestObject
            if best then return best:GetFullName() .. " [" .. best.ClassName .. "]" end
            return "GUI tidak teridentifikasi"
        end

        local function inputId(input)
            return tostring(input)
        end

        track(UIS.InputBegan:Connect(function(input, gameProcessed)
            if not recording then return end
            local target = ""
            if input.UserInputType == Enum.UserInputType.Touch then
                target = guiAt(Vector2.new(input.Position.X, input.Position.Y))
            elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
                local mouse = UIS:GetMouseLocation()
                target = guiAt(mouse)
            end
            activeInputs[inputId(input)] = os.clock()
            addRecord("DOWN", input, target,
                gameProcessed and "GameProcessed=true" or "GameProcessed=false")
        end))

        track(UIS.InputEnded:Connect(function(input, gameProcessed)
            if not recording then return end
            local id = inputId(input)
            local began = activeInputs[id]
            local duration = began and (os.clock() - began) or nil
            activeInputs[id] = nil
            addRecord("UP", input, "", duration and string.format("Held=%.3fs", duration)
                or (gameProcessed and "GameProcessed=true" or "GameProcessed=false"))
        end))

        track(startButton.Activated:Connect(function()
            if recording then return end
            records = {}
            sequence = 0
            activeInputs = {}
            for _, child in ipairs(log:GetChildren()) do
                if child:IsA("TextLabel") then child:Destroy() end
            end
            startedAt = os.clock()
            recording = true
            updateStatus()
            print("[InputRecorder] RECORDING START")
        end))

        track(stopButton.Activated:Connect(function()
            if not recording then return end
            recording = false
            activeInputs = {}
            updateStatus()
            print("[InputRecorder] RECORDING STOP | events=" .. #records)
        end))

        track(clearButton.Activated:Connect(function()
            recording = false
            records = {}
            sequence = 0
            activeInputs = {}
            for _, child in ipairs(log:GetChildren()) do
                if child:IsA("TextLabel") then child:Destroy() end
            end
            updateStatus()
        end))

        track(exportButton.Activated:Connect(function()
            print("========== INPUT RECORDER LOG ==========")
            for _, item in ipairs(records) do print(item.line) end
            print("========== END INPUT RECORDER LOG ==========")
        end))

        local function cleanup()
            if not alive then return end
            alive = false
            recording = false
            for _, conn in ipairs(connections) do
                pcall(function() conn:Disconnect() end)
            end
            table.clear(connections)
        end

        if type(Hub.RegisterCleanup) == "function" then
            Hub.RegisterCleanup(cleanup)
        end

        updateStatus()
        print("[InputRecorder] Tab siap. Tekan MULAI REKAM, lalu sentuh tombol kontrol game.")
    end)
end
