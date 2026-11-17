-- Collect Experiment: 1 drop above player
-- Minimal diagnostic. Does NOT call World.takeDrop or any pickup Remote.
-- Test: stand directly below one visible drop, then press the button.

return function(Hub)
    assert(Hub and type(Hub.RegisterTab) == "function", "Hub.RegisterTab tidak ditemukan")

    Hub.RegisterTab("Collect Experiment", function(page)
        local Players = game:GetService("Players")
        local VIM = game:GetService("VirtualInputManager")
        local player = Players.LocalPlayer
        local running = false

        local function raw(t, k)
            if type(t) ~= "table" then return nil end
            local ok, v = pcall(rawget, t, k)
            return ok and v or nil
        end

        local function discover()
            if type(getgc) ~= "function" then
                return nil, nil, "getgc tidak tersedia"
            end

            local ok, objects = pcall(getgc, true)
            if not ok or type(objects) ~= "table" then
                return nil, nil, "getgc(true) gagal"
            end

            local world, stateFn
            for _, obj in ipairs(objects) do
                if type(obj) == "table" then
                    if not world
                        and type(raw(obj, "fg")) == "table"
                        and type(raw(obj, "bg")) == "table"
                        and type(raw(obj, "w")) == "number"
                        and type(raw(obj, "h")) == "number"
                        and raw(obj, "spawn") ~= nil
                        and type(raw(obj, "dropList")) == "function" then
                        world = obj
                    end

                    if not stateFn then
                        local fn = raw(obj, "state")
                        if type(fn) == "function" then
                            local good, state = pcall(fn)
                            if good and type(state) == "table"
                                and type(state.x) == "number"
                                and type(state.y) == "number"
                                and state.facing ~= nil and state.vx ~= nil then
                                stateFn = fn
                            end
                        end
                    end
                end
                if world and stateFn then break end
            end

            if not world then return nil, nil, "World dengan dropList() tidak ditemukan" end
            if not stateFn then return nil, nil, "fungsi player state tidak ditemukan" end
            return world, stateFn
        end

        local function inventorySnapshot()
            local char = player.Character
            local stats = player:FindFirstChild("leaderstats")
            local values = {}
            if stats then
                for _, v in ipairs(stats:GetChildren()) do
                    if v:IsA("IntValue") or v:IsA("NumberValue") then
                        values[v.Name] = v.Value
                    end
                end
            end
            return values
        end

        local function snapshotText(before, after)
            local changes = {}
            for name, value in pairs(after) do
                local old = before[name]
                if old ~= nil and old ~= value then
                    changes[#changes + 1] = name .. ": " .. tostring(old) .. " -> " .. tostring(value)
                end
            end
            return #changes > 0 and table.concat(changes, ", ") or "Tidak ada perubahan leaderstats yang terbaca"
        end

        local function notify(msg)
            status.Text = tostring(msg)
            pcall(function()
                game:GetService("StarterGui"):SetCore("SendNotification", {
                    Title = "Collect Experiment",
                    Text = tostring(msg),
                    Duration = 6
                })
            end)
            print("[Collect Experiment] " .. tostring(msg))
        end

        local function make(class, props, parent)
            local obj = Instance.new(class)
            for k, v in pairs(props) do obj[k] = v end
            obj.Parent = parent
            return obj
        end

        local status = make("TextLabel", {
            Name = "CollectExperimentStatus",
            Position = UDim2.fromOffset(0, 4),
            Size = UDim2.new(1, -12, 0, 54),
            BackgroundTransparency = 1,
            Text = "Siapkan 1 drop tepat di atas player, lalu tekan TEST.",
            TextColor3 = Color3.fromRGB(220, 225, 235),
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
        }, page)

        local testButton = make("TextButton", {
            Name = "TestOneDropAbovePlayer",
            Position = UDim2.fromOffset(0, 62),
            Size = UDim2.fromOffset(220, 38),
            BackgroundColor3 = Color3.fromRGB(35, 145, 92),
            BorderSizePixel = 0,
            Text = "TEST 1 DROP DI ATAS PLAYER",
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            AutoButtonColor = true,
        }, page)
        local buttonCorner = Instance.new("UICorner")
        buttonCorner.CornerRadius = UDim.new(0, 7)
        buttonCorner.Parent = testButton

        local function runOneDropTest()
            if running then return end
            running = true

            task.spawn(function()
                local ok, result = pcall(function()
                    local world, stateFn, err = discover()
                    assert(world and stateFn, err or "Referensi game tidak lengkap")

                    local good, state = pcall(stateFn)
                    assert(good and type(state) == "table", "Gagal membaca posisi player")
                    assert(state.active ~= false and not state.dead, "Player tidak aktif/alive")

                    local listOk, drops = pcall(world.dropList)
                    assert(listOk and type(drops) == "table", "World.dropList() gagal")

                    -- Source k(5).lua: drop di atas kepala berada dalam rentang 0.9–2.6 tile.
                    -- Pilih satu drop terdekat yang hampir tepat di atas posisi player.
                    local target, bestScore
                    for _, d in ipairs(drops) do
                        if type(d) == "table"
                            and type(d.x) == "number"
                            and type(d.y) == "number"
                            and (d.n or 0) > 0
                            and d.armed ~= false
                            and not d.taking then
                            local dx = math.abs(d.x - state.x)
                            local dy = state.y - d.y
                            if dx <= 0.6 and dy > 0.9 and dy <= 2.6 then
                                local score = dx * dx + math.abs(dy - 1.5) * 0.2
                                if not bestScore or score < bestScore then
                                    target, bestScore = d, score
                                end
                            end
                        end
                    end

                    assert(target, "Tidak ada drop 1–2.6 tile di atas player. Posisikan player tepat di bawah satu drop.")

                    local uid = target.uid
                    local amountBefore = target.n
                    local invBefore = inventorySnapshot()

                    notify(("Target UID %s | item %s | stack %s. Melompat..."):format(
                        tostring(uid), tostring(target.id), tostring(amountBefore)
                    ))

                    -- Satu kali tap jump. Tidak memindahkan CFrame/posisi karakter,
                    -- tidak memanggil fungsi pickup atau Remote.
                    VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                    task.wait(0.25)
                    VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)

                    -- Tunggu balasan server dan pembaruan daftar drop.
                    task.wait(1.5)

                    local stillThere, remaining
                    local checkOk, freshDrops = pcall(world.dropList)
                    if checkOk and type(freshDrops) == "table" then
                        for _, d in ipairs(freshDrops) do
                            if type(d) == "table" and d.uid == uid then
                                stillThere = true
                                remaining = d.n
                                break
                            end
                        end
                    end

                    local invAfter = inventorySnapshot()
                    local invChange = snapshotText(invBefore, invAfter)

                    if not stillThere then
                        return ("HASIL: UID %s hilang dari dropList setelah jump. Inventori/leaderstats: %s"):format(
                            tostring(uid), invChange
                        )
                    elseif type(remaining) == "number" and remaining < amountBefore then
                        return ("HASIL: UID %s berkurang %s -> %s. Inventori/leaderstats: %s"):format(
                            tostring(uid), tostring(amountBefore), tostring(remaining), invChange
                        )
                    else
                        return ("HASIL: UID %s masih ada (stack %s). Inventori/leaderstats: %s"):format(
                            tostring(uid), tostring(remaining or amountBefore), invChange
                        )
                    end
                end)

                running = false
                if ok then
                    notify(result)
                else
                    notify("TEST GAGAL: " .. tostring(result))
                end
            end)
        end

        testButton.MouseButton1Click:Connect(runOneDropTest)
    end)
end

