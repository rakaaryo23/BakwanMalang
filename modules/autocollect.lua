--==================================================
-- MODULE: COLLECT EXPERIMENT - ONE DROP ABOVE PLAYER
-- UI/event pattern copied from Auto_PUT_BREAK_Submenu_Fixed(1).lua
-- Test target: one drop directly above the player.
-- Does not call World.takeDrop or any pickup Remote.
--==================================================

return function(Hub)
    assert(Hub and type(Hub.RegisterTab) == "function", "Hub.RegisterTab tidak ditemukan")

    Hub.RegisterTab("Collect Experiment", function(page)
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer

    local running = false
    local statusLabel
    local testButton

    local function create(className, properties, parent)
        local object = Instance.new(className)
        for property, value in pairs(properties or {}) do
            object[property] = value
        end
        object.Parent = parent
        return object
    end

    local function corner(object, radius)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, radius or 7)
        c.Parent = object
    end

    local function report(message)
        message = tostring(message)
        if statusLabel and statusLabel.Parent then
            statusLabel.Text = "STATUS: " .. message
        end
        print("[Collect Experiment] " .. message)
    end

    local function makeLabel(text, height)
        return create("TextLabel", {
            Size = UDim2.new(1, 0, 0, height or 34),
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = Color3.fromRGB(76, 43, 57),
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextWrapped = true,
        }, page)
    end

    local function makeButton(text, height, color)
        local b = create("TextButton", {
            Size = UDim2.new(1, 0, 0, height or 36),
            BackgroundColor3 = color or Color3.fromRGB(171, 91, 119),
            BorderSizePixel = 0,
            Text = text,
            TextColor3 = Color3.fromRGB(255, 249, 251),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            AutoButtonColor = true,
            Active = true,
            Selectable = true,
        }, page)
        corner(b, 7)
        return b
    end

    create("UIListLayout", {
        Padding = UDim.new(0, 7),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, page)

    statusLabel = makeLabel(
        "STATUS: SIAP. Berdiri tepat di bawah satu drop, lalu tekan tombol. World discovery sudah disesuaikan dengan k(5).lua.",
        58
    )
    statusLabel.LayoutOrder = 1

    testButton = makeButton(
        "TEST 1 DROP DI ATAS PLAYER",
        42,
        Color3.fromRGB(55, 140, 90)
    )
    testButton.LayoutOrder = 2

    local function raw(t, k)
        if type(t) ~= "table" then return nil end
        local ok, value = pcall(rawget, t, k)
        if ok then return value end
        return nil
    end

    local function getUpvalues(fn)
        local out = {}
        local dbg = debug
        local all = dbg and dbg.getupvalues
        if type(all) == "function" then
            local ok, values = pcall(all, fn)
            if ok and type(values) == "table" then return values end
        end
        local one = (dbg and dbg.getupvalue) or getupvalue
        if type(one) == "function" then
            for i = 1, 60 do
                local ok, value = pcall(one, fn, i)
                if not ok then break end
                out[i] = value
            end
        end
        return out
    end

    local function isWorldTable(value)
        return type(value) == "table"
            and type(raw(value, "fg")) == "table"
            and type(raw(value, "bg")) == "table"
            and type(raw(value, "w")) == "number"
            and type(raw(value, "h")) == "number"
            and raw(value, "spawn") ~= nil
    end

    local function isDropList(value)
        if type(value) ~= "table" then return false end
        local first = raw(value, 1)
        if first == nil then return next(value) == nil end
        return type(first) == "table"
            and raw(first, "uid") ~= nil
            and raw(first, "frame") ~= nil
    end

    local function discoverWorldAndState()
        if type(getgc) ~= "function" then
            return nil, nil, nil, "getgc tidak tersedia"
        end

        local ok, objects = pcall(getgc, true)
        if not ok or type(objects) ~= "table" then
            return nil, nil, nil, "getgc(true) gagal"
        end

        local world, stateFunction
        for _, obj in ipairs(objects) do
            if type(obj) == "table" then
                if not world and isWorldTable(obj) then
                    world = obj
                end

                if not stateFunction then
                    local candidate = raw(obj, "state")
                    if type(candidate) == "function" then
                        local stateOk, state = pcall(candidate)
                        if stateOk and type(state) == "table"
                            and type(state.x) == "number"
                            and type(state.y) == "number"
                            and state.facing ~= nil
                            and state.vx ~= nil then
                            stateFunction = candidate
                        end
                    end
                end
            end
            if world and stateFunction then break end
        end

        if not world then
            return nil, stateFunction, nil,
                "World tidak ditemukan memakai kriteria asli k(5).lua (fg/bg/w/h/spawn)"
        end
        if not stateFunction then
            return world, nil, nil, "Fungsi Refs.State tidak ditemukan"
        end

        -- k(5).lua tidak mewajibkan dropList menjadi field World saat menemukan World.
        -- Daftar drop dicari terpisah, persis seperti findDropRefs().
        local dropList
        local dropListFn = raw(world, "dropList")
        if type(dropListFn) == "function" then
            local listOk, list = pcall(dropListFn)
            if listOk and isDropList(list) then
                dropList = list
            end
        end

        if not dropList then
            local dropTaken = raw(world, "dropTaken")
            if type(dropTaken) == "function" then
                for _, upvalue in pairs(getUpvalues(dropTaken)) do
                    if isDropList(upvalue) then
                        dropList = upvalue
                        break
                    end
                end
            end
        end

        if not dropList then
            return world, stateFunction, nil,
                "World dan State ditemukan, tetapi daftar drop belum ditemukan dari World.dropList/dropTaken. Ini berbeda dari error sebelumnya."
        end

        return world, stateFunction, dropList
    end

    local function inventorySnapshot()
        local result = {}
        local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
        if leaderstats then
            for _, value in ipairs(leaderstats:GetChildren()) do
                if value:IsA("IntValue") or value:IsA("NumberValue") then
                    result[value.Name] = value.Value
                end
            end
        end
        return result
    end

    local function inventoryDiff(before, after)
        local changes = {}
        for name, value in pairs(after) do
            if before[name] ~= nil and before[name] ~= value then
                changes[#changes + 1] = name .. " " .. tostring(before[name]) .. " -> " .. tostring(value)
            end
        end
        return #changes > 0 and table.concat(changes, ", ") or "tidak ada perubahan leaderstats"
    end

    local function runTest()
        if running then
            report("TEST masih berjalan.")
            return
        end

        running = true
        testButton.Text = "SEDANG MENGUJI..."
        testButton.BackgroundColor3 = Color3.fromRGB(130, 105, 75)
        report("TOMBOL TERTEKAN. Mencari satu drop di atas player...")

        task.spawn(function()
            local ok, message = pcall(function()
                local world, stateFunction, dropList, err = discoverWorldAndState()
                assert(world and stateFunction and dropList, err or "Referensi tidak lengkap")

                local stateOk, state = pcall(stateFunction)
                assert(stateOk and type(state) == "table", "Gagal membaca state player")
                assert(type(state.x) == "number" and type(state.y) == "number", "Koordinat player tidak valid")

                local drops = dropList
                assert(type(drops) == "table", "Daftar drop tidak valid")

                local target, bestScore
                for _, drop in ipairs(drops) do
                    if type(drop) == "table"
                        and type(drop.x) == "number"
                        and type(drop.y) == "number"
                        and type(drop.n) == "number"
                        and drop.n > 0
                        and drop.armed ~= false
                        and not drop.taking then
                        local dx = math.abs(drop.x - state.x)
                        local dy = state.y - drop.y
                        if dx <= 0.6 and dy > 0.9 and dy <= 2.6 then
                            local score = dx * dx + math.abs(dy - 1.5) * 0.2
                            if not bestScore or score < bestScore then
                                target, bestScore = drop, score
                            end
                        end
                    end
                end

                assert(target, "Tidak ada drop 0.9–2.6 tile di atas player. Atur posisi lalu coba lagi.")

                local uid = target.uid
                local beforeCount = target.n
                local invBefore = inventorySnapshot()

                report(("Target ditemukan: UID %s | ID %s | stack %s. Menguji input lompat..."):format(
                    tostring(uid), tostring(target.id), tostring(beforeCount)
                ))

                -- Trigger normal Humanoid jump from the client (no remote pickup).
                local character = LocalPlayer.Character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                assert(humanoid, "Humanoid tidak ditemukan")
                humanoid.Jump = true
                task.wait(0.15)
                humanoid.Jump = false

                task.wait(1.5)

                local stillThere, afterCount = false, nil
                local freshDrops = dropList
                if type(freshDrops) == "table" then
                    for _, drop in ipairs(freshDrops) do
                        if type(drop) == "table" and drop.uid == uid then
                            stillThere = true
                            afterCount = drop.n
                            break
                        end
                    end
                end

                local invAfter = inventorySnapshot()
                local invResult = inventoryDiff(invBefore, invAfter)

                if not stillThere then
                    return ("UID %s HILANG dari dropList. Inventori: %s"):format(tostring(uid), invResult)
                elseif type(afterCount) == "number" and afterCount < beforeCount then
                    return ("UID %s BERKURANG %s -> %s. Inventori: %s"):format(
                        tostring(uid), tostring(beforeCount), tostring(afterCount), invResult
                    )
                end
                return ("UID %s MASIH ADA (stack %s). Inventori: %s"):format(
                    tostring(uid), tostring(afterCount or beforeCount), invResult
                )
            end)

            running = false
            testButton.Text = "TEST 1 DROP DI ATAS PLAYER"
            testButton.BackgroundColor3 = Color3.fromRGB(55, 140, 90)

            if ok then
                report(message)
            else
                report("GAGAL: " .. tostring(message))
            end
        end)
    end

    -- Same mobile-friendly event pattern as the working Auto PUT + BREAK module.
    testButton.Activated:Connect(runTest)
end)
end
