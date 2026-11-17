-- MODULE: COLLECT TEST - ONE BLOCK ABOVE PLAYER
-- Integrasi: jalankan module ini dengan pola require(...)(Hub) milik GrowBlox Hub.
-- Tombol TEST hanya mencoba SATU drop UID pada tile tepat di atas player.

return function(Hub)
    Hub.RegisterTab("Collect Test", function(page)
        local Players = game:GetService("Players")
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local LocalPlayer = Players.LocalPlayer
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
        local WorldRemotes = ReplicatedStorage:WaitForChild("WorldRemotes")
        local TakeDropRemote = WorldRemotes:FindFirstChild("TakeDrop")

        local destroyed = false
        local refs = { World = nil, State = nil, Drops = nil }
        local selectedDrop = nil
        local connections = {}

        local function create(className, props)
            local obj = Instance.new(className)
            for k, v in pairs(props or {}) do obj[k] = v end
            obj.Parent = page
            return obj
        end

        local layout = create("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })

        local function label(text, height)
            return create("TextLabel", {
                Size = UDim2.new(1, 0, 0, height or 28),
                BackgroundTransparency = 1,
                Text = text,
                TextColor3 = Color3.fromRGB(65, 45, 55),
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                AutomaticSize = Enum.AutomaticSize.Y,
            })
        end

        local status = label("Status: Siap. Tekan SCAN.", 38)
        local detail = label("Player: - | Target: - | Drop: -", 48)

        local function report(msg)
            if status and status.Parent then status.Text = "Status: " .. tostring(msg) end
            print("[Collect Test] " .. tostring(msg))
        end

        local function button(text, callback)
            local b = create("TextButton", {
                Size = UDim2.new(1, 0, 0, 34),
                BackgroundColor3 = Color3.fromRGB(222, 164, 183),
                BorderSizePixel = 0,
                Text = text,
                TextColor3 = Color3.fromRGB(76, 43, 57),
                Font = Enum.Font.GothamSemibold,
                TextSize = 12,
                AutoButtonColor = true,
            })
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 7)
            c.Parent = b
            table.insert(connections, b.Activated:Connect(function()
                if destroyed or (Hub.IsClosing and Hub.IsClosing()) then return end
                local ok, err = pcall(callback)
                if not ok then report("ERROR: " .. tostring(err)) end
            end))
            return b
        end

        local function getUpvalues(fn)
            local dbg = debug
            if dbg and type(dbg.getupvalues) == "function" then
                local ok, values = pcall(dbg.getupvalues, fn)
                if ok and type(values) == "table" then return values end
            end
            local getter = (dbg and dbg.getupvalue) or getupvalue
            local out = {}
            if type(getter) == "function" then
                for i = 1, 60 do
                    local ok, value = pcall(getter, fn, i)
                    if not ok or value == nil then break end
                    out[i] = value
                end
            end
            return out
        end

        local function isWorld(t)
            return type(t) == "table"
                and type(rawget(t, "fg")) == "table"
                and type(rawget(t, "bg")) == "table"
                and type(rawget(t, "w")) == "number"
                and type(rawget(t, "h")) == "number"
                and rawget(t, "spawn") ~= nil
        end

        local function isDropList(t)
            if type(t) ~= "table" or t == refs.World then return false end
            local first = rawget(t, 1)
            if first == nil then return next(t) == nil end
            return type(first) == "table"
                and rawget(first, "uid") ~= nil
                and rawget(first, "frame") ~= nil
        end

        local function discoverRefs()
            if type(getgc) ~= "function" then
                return false, "Executor tidak menyediakan getgc()."
            end
            local ok, objects = pcall(getgc, true)
            if not ok or type(objects) ~= "table" then
                return false, "getgc(true) gagal: " .. tostring(objects)
            end

            refs.World, refs.State = nil, nil
            for _, obj in ipairs(objects) do
                if type(obj) == "table" then
                    if not refs.World and isWorld(obj) then refs.World = obj end
                    if not refs.State then
                        local stateFn = rawget(obj, "state")
                        if type(stateFn) == "function" then
                            local stateOk, state = pcall(stateFn)
                            if stateOk and type(state) == "table"
                                and type(state.x) == "number" and type(state.y) == "number" then
                                refs.State = stateFn
                            end
                        end
                    end
                    if refs.World and refs.State then break end
                end
            end
            return refs.World ~= nil and refs.State ~= nil,
                (refs.World and "World ditemukan" or "World tidak ditemukan") .. " | " ..
                (refs.State and "State ditemukan" or "State tidak ditemukan")
        end

        local function findDropList()
            if not refs.World then return false, "World belum ditemukan. Tekan SCAN REFS dulu." end
            local dropListFn = rawget(refs.World, "dropList")
            if type(dropListFn) == "function" then
                local ok, list = pcall(dropListFn)
                if ok and isDropList(list) then
                    refs.Drops = list
                    return true, "Daftar drop ditemukan lewat World.dropList()."
                end
            end

            local dropTakenFn = rawget(refs.World, "dropTaken")
            if type(dropTakenFn) == "function" then
                for _, value in pairs(getUpvalues(dropTakenFn)) do
                    if isDropList(value) then
                        refs.Drops = value
                        return true, "Daftar drop ditemukan dari upvalue World.dropTaken."
                    end
                end
            end

            -- Fallback getgc hanya untuk mengenali bentuk tabel drop yang dipakai K.lua.
            if type(getgc) == "function" then
                local ok, objects = pcall(getgc, true)
                if ok and type(objects) == "table" then
                    for _, obj in ipairs(objects) do
                        if isDropList(obj) then
                            refs.Drops = obj
                            return true, "Daftar drop ditemukan lewat pola UID + frame."
                        end
                    end
                end
            end
            return false, "Daftar drop tidak ditemukan."
        end

        local function playerAndTarget()
            if not refs.State then return nil, nil, "State belum ditemukan. Tekan SCAN REFS." end
            local ok, s = pcall(refs.State)
            if not ok or type(s) ~= "table" or type(s.x) ~= "number" or type(s.y) ~= "number" then
                return nil, nil, "State player gagal dibaca."
            end
            if s.active == false then return nil, nil, "Player tidak aktif di world." end
            local px = math.floor(s.x)
            local py = math.floor(s.y - 0.475)
            return { x = px, y = py }, { x = px, y = py + 1 }, nil
        end

        local function inTile(tile, x, y)
            return type(x) == "number" and type(y) == "number"
                and x >= tile.x - 0.15 and x < tile.x + 1.15
                and y >= tile.y - 0.15 and y < tile.y + 1.15
        end

        local function scan()
            selectedDrop = nil
            local player, target, err = playerAndTarget()
            if err then report(err); return end
            if not refs.Drops then
                local found, message = findDropList()
                if not found then report(message); return end
            end

            local matches = {}
            for _, d in ipairs(refs.Drops) do
                if type(d) == "table" and d.uid ~= nil
                    and inTile(target, d.x, d.y) and (d.n or 0) > 0 then
                    table.insert(matches, d)
                end
            end
            table.sort(matches, function(a, b)
                return tostring(a.uid) < tostring(b.uid)
            end)
            selectedDrop = matches[1]

            local p = ("Player (%d,%d) | Target (%d,%d)"):format(player.x, player.y, target.x, target.y)
            if selectedDrop then
                detail.Text = p .. ("\nDrop: UID %s | Item ID %s | Qty %s | Pos %.2f, %.2f | Total di tile: %d"):
                    format(tostring(selectedDrop.uid), tostring(selectedDrop.id), tostring(selectedDrop.n),
                        selectedDrop.x, selectedDrop.y, #matches)
                report("SCAN OK. Dipilih UID " .. tostring(selectedDrop.uid) .. ".")
            else
                detail.Text = p .. "\nDrop: tidak ada di tile satu blok di atas player."
                report("Tidak ada drop di target tile.")
            end
        end

        local function currentDrop()
            if not selectedDrop then scan() end
            if not selectedDrop then return nil end
            local player, target, err = playerAndTarget()
            if err then report(err); return nil end
            if not inTile(target, selectedDrop.x, selectedDrop.y) then
                selectedDrop = nil
                report("Target berubah. SCAN ulang sebelum TEST.")
                return nil
            end
            if not table.find(refs.Drops or {}, selectedDrop) then
                selectedDrop = nil
                report("Drop sudah tidak ada di daftar. SCAN ulang.")
                return nil
            end
            return selectedDrop
        end

        local function testTake(method)
            local d = currentDrop()
            if not d then return end
            if d.taking or d.pending or d.display then
                report("Drop sedang diproses / tidak siap.")
                return
            end
            if d.armed == false and d.id ~= 112 then
                report("Drop armed=false; K.lua melewati drop ini (kecuali gems ID 112).")
                return
            end
            local amount = tonumber(d.n) or 0
            if amount <= 0 then report("Qty drop tidak valid."); return end

            local fn, remote
            if method == "World.takeDrop" then
                fn = refs.World and rawget(refs.World, "takeDrop")
                if type(fn) ~= "function" then report("World.takeDrop tidak ditemukan."); return end
            elseif method == "TakeDrop Remote" then
                remote = TakeDropRemote
                if not remote then report("Remote TakeDrop tidak ditemukan."); return end
                if not remote:IsA("RemoteFunction") then
                    report("TakeDrop ditemukan, tetapi bukan RemoteFunction.")
                    return
                end
            end

            local beforeUid, beforeQty = d.uid, d.n
            report("Mencoba " .. method .. " | UID " .. tostring(beforeUid) .. " | qty " .. tostring(amount) .. " ...")
            d.taking = true
            local ok, result
            if fn then
                ok, result = pcall(fn, beforeUid, amount)
            else
                ok, result = pcall(function()
                    return remote:InvokeServer(beforeUid, amount)
                end)
            end
            d.taking = false

            if not ok then
                report(method .. " ERROR: " .. tostring(result))
                return
            end
            if type(result) == "number" and result > 0 then
                report(method .. " BERHASIL menurut return server: " .. tostring(result) ..
                    " | UID " .. tostring(beforeUid) .. ". SCAN ulang untuk cek sisa drop.")
            else
                report(method .. " dipanggil, tetapi return bukan angka > 0: " .. tostring(result) ..
                    ". Belum bisa dinyatakan berhasil.")
            end
        end

        button("1. SCAN REFS (World + Player State)", function()
            local ok, message = discoverRefs()
            report(message)
            if ok then
                local found, dropMessage = findDropList()
                report(message .. " | " .. dropMessage)
            end
        end)
        button("2. SCAN DROP DI TILE Y+1", scan)
        button("3. TEST World.takeDrop(uid, qty)", function() testTake("World.takeDrop") end)
        button("4. TEST TakeDrop:InvokeServer(uid, qty)", function() testTake("TakeDrop Remote") end)
        button("5. CLEAR PILIHAN UID", function()
            selectedDrop = nil
            detail.Text = "Player: - | Target: - | Drop: -"
            report("Pilihan UID dibersihkan.")
        end)

        Hub.RegisterCleanup(function()
            destroyed = true
            for _, connection in ipairs(connections) do
                pcall(function() connection:Disconnect() end)
            end
            table.clear(connections)
        end)
    end)
end
