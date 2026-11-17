-- AutoCollect_Remote.lua
-- Modul mandiri untuk Hub.RegisterTab.
-- Mekanisme pengambilan drop/remote dan pembaruan drop diadaptasi dari k(5).lua.
-- Discovery Inventory/World/State dan rumus posisi player diadaptasi dari APB(2).lua.

return function(Hub)
    assert(Hub and type(Hub.RegisterTab) == "function", "Hub.RegisterTab tidak ditemukan")

    Hub.RegisterTab("Auto Collect", function(page, Hub)
        local Players = game:GetService("Players")
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local LocalPlayer = Players.LocalPlayer

        local destroyed, running = false, false
        local connections = {}
        local refs = { Inv = nil, World = nil, State = nil }
        local Drops = { list = nil, update = nil, nextScan = 0 }
        local DropFailUntil = {}
        local enabled = {}
        local popup

        local Theme = {
            Background = Color3.fromRGB(22, 24, 30),
            Panel = Color3.fromRGB(32, 35, 43),
            PanelDark = Color3.fromRGB(52, 56, 66),
            Text = Color3.fromRGB(240, 242, 248),
            Muted = Color3.fromRGB(165, 171, 184),
            Green = Color3.fromRGB(35, 145, 92),
            Red = Color3.fromRGB(170, 55, 60),
            White = Color3.fromRGB(255, 255, 255),
        }

        local function track(c)
            connections[#connections + 1] = c
            return c
        end

        local function create(class, props, parent)
            local obj = Instance.new(class)
            for k, v in pairs(props) do obj[k] = v end
            obj.Parent = parent
            return obj
        end

        local function corner(obj, radius)
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, radius or 6)
            c.Parent = obj
            return c
        end

        local function raw(t, k)
            if type(t) ~= "table" then return nil end
            local ok, value = pcall(rawget, t, k)
            return ok and value or nil
        end

        -- APB(2).lua: identifikasi tabel inventory dengan struktur slots/capacity.
        local function inventoryCandidate(t)
            if type(t) ~= "table" then return nil end
            local slots, cap = raw(t, "slots"), raw(t, "capacity")
            if type(slots) ~= "table" or type(cap) ~= "number"
                or cap < 0 or cap > 10000 then return nil end

            local valid, populated = 0, 0
            for k, slot in pairs(slots) do
                if type(k) == "number" and k > 0 and k % 1 == 0
                    and type(slot) == "table" then
                    local id, n = raw(slot, "id"), raw(slot, "n")
                    if id ~= nil or n ~= nil then valid += 1 end
                    if id ~= nil then populated += 1 end
                end
            end
            if valid == 0 and next(slots) ~= nil then return nil end
            return { ref = t, score = valid * 100 + populated + math.min(cap, 100) }
        end

        local function discover()
            local getconsts = (debug and debug.getconstants) or getconstants
            if type(getgc) ~= "function" or type(getconsts) ~= "function"
                or not (debug and debug.info) then
                return false, "Executor tidak menyediakan getgc/getconstants/debug.info"
            end

            local ok, objects = pcall(getgc, true)
            if not ok or type(objects) ~= "table" then
                return false, "getgc(true) gagal: " .. tostring(objects)
            end

            refs.Inv, refs.World, refs.State = nil, nil, nil
            local bestInv

            for _, obj in ipairs(objects) do
                if type(obj) == "table" then
                    local candidate = inventoryCandidate(obj)
                    if candidate and (not bestInv or candidate.score > bestInv.score) then
                        bestInv = candidate
                    end

                    if not refs.World
                        and type(raw(obj, "fg")) == "table"
                        and type(raw(obj, "bg")) == "table"
                        and type(raw(obj, "w")) == "number"
                        and type(raw(obj, "h")) == "number"
                        and raw(obj, "spawn") ~= nil then
                        refs.World = obj
                    end

                    if not refs.State then
                        local stateFn = raw(obj, "state")
                        if type(stateFn) == "function" then
                            local good, state = pcall(stateFn)
                            if good and type(state) == "table"
                                and type(state.x) == "number"
                                and type(state.y) == "number"
                                and state.facing ~= nil and state.vx ~= nil then
                                refs.State = stateFn
                            end
                        end
                    end
                end
            end

            refs.Inv = bestInv and bestInv.ref or nil
            local missing = {}
            for _, key in ipairs({"Inv", "World", "State"}) do
                if not refs[key] then table.insert(missing, key) end
            end
            if #missing > 0 then
                return false, "Referensi belum lengkap: " .. table.concat(missing, ", ")
            end
            return true, "Scan berhasil: Inventory, World, dan State ditemukan."
        end

        -- Rumus playerTile sama dengan APB(2).lua.
        local function playerTile()
            if not refs.State then return nil end
            local ok, state = pcall(refs.State)
            if not ok or type(state) ~= "table"
                or type(state.x) ~= "number" or type(state.y) ~= "number"
                or state.active == false then return nil end
            return math.floor(state.x), math.floor(state.y - 0.475)
        end

        local function getUpvalues(fn)
            if debug and debug.getupvalues then
                local ok, ups = pcall(debug.getupvalues, fn)
                if ok and type(ups) == "table" then return ups end
            end
            local out = {}
            local gu = (debug and debug.getupvalue) or getupvalue
            if gu then
                for i = 1, 60 do
                    local ok, v = pcall(gu, fn, i)
                    if not ok then break end
                    out[i] = v
                end
            end
            return out
        end

        local function isDropList(t)
            if type(t) ~= "table" or t == refs.World then return false end
            local first = rawget(t, 1)
            if first == nil then return next(t) == nil end
            return type(first) == "table"
                and rawget(first, "uid") ~= nil
                and rawget(first, "frame") ~= nil
        end

        function Drops.findUpdate()
            local w, list = refs.World, Drops.list
            local wd = w and rawget(w, "dropTaken")
            if type(wd) ~= "function" or not list then return false end
            for _, u in pairs(getUpvalues(wd)) do
                if type(u) == "function" then
                    for _, uu in pairs(getUpvalues(u)) do
                        if rawequal(uu, list) then
                            Drops.update = u
                            return true
                        end
                    end
                end
            end
            return false
        end

        local function findDropRefs()
            local w = refs.World
            local dl = w and rawget(w, "dropList")
            if type(dl) == "function" then
                local good, list = pcall(dl)
                if good and isDropList(list) then
                    if Drops.list ~= list then Drops.update = nil end
                    Drops.list = list
                    if not Drops.update then Drops.findUpdate() end
                    return true
                end
            end

            if Drops.list then return true end
            Drops.list, Drops.update = nil, nil

            local wd = refs.World and rawget(refs.World, "dropTaken")
            if type(wd) == "function" then
                for _, u in pairs(getUpvalues(wd)) do
                    if not Drops.list and isDropList(u) then
                        Drops.list = u
                    elseif not Drops.update and type(u) == "function" then
                        Drops.update = u
                    end
                end
            end

            local remotes = ReplicatedStorage:FindFirstChild("WorldRemotes")
            local ev = remotes and remotes:FindFirstChild("DropTaken")
            if not Drops.list and ev and getconnections then
                local good, conns = pcall(getconnections, ev.OnClientEvent)
                if good and type(conns) == "table" then
                    for _, c in ipairs(conns) do
                        local okf, fn = pcall(function() return c.Function end)
                        if okf and type(fn) == "function" then
                            for _, u in pairs(getUpvalues(fn)) do
                                if not Drops.list and isDropList(u) then
                                    Drops.list = u
                                elseif not Drops.update and type(u) == "function" then
                                    Drops.update = u
                                end
                            end
                        end
                        if Drops.list then break end
                    end
                end
            end
            return Drops.list ~= nil
        end

        -- Drops.applyTaken disalin dari k(5).lua.
        function Drops.applyTaken(d, left)
            local list = Drops.list
            if not list or not table.find(list, d) then return end
            if not Drops.update then Drops.findUpdate() end
            if Drops.update then
                local ok = pcall(Drops.update, d, left)
                if ok then
                    if left > 0 then
                        d.flown = nil
                        if typeof(d.frame) == "Instance" then
                            pcall(function() d.frame.Visible = not d.culled end)
                        end
                    end
                    return
                end
            end
            d.n = left
            if left > 0 then
                pcall(function()
                    if d.setGem then
                        d.setGem(left)
                    elseif d.count then
                        d.count:set(left > 1 and tostring(left) or "")
                    end
                end)
                d.flown = nil
                if typeof(d.frame) == "Instance" then
                    pcall(function() d.frame.Visible = not d.culled end)
                end
            else
                local idx = table.find(list, d)
                if idx then table.remove(list, idx) end
                if typeof(d.frame) == "Instance" then
                    pcall(function() d.frame:Destroy() end)
                end
            end
        end

        -- Fungsi takeDrop mengikuti k(5).lua; counter/UI statistik utama tidak
        -- disertakan karena modul ini berdiri sendiri dan tidak berbagi State/Stats utama.
        local function takeDrop(d)
            local worldTake = refs.World and rawget(refs.World, "takeDrop")
            if type(worldTake) ~= "function" then return false end
            if d.taking or d.pending or d.display or (d.n or 0) <= 0 then return false end
            if d.armed == false and d.id ~= 112 then return false end

            local now = os.clock()
            if DropFailUntil[d.uid] and now < DropFailUntil[d.uid] then return false end

            local amount = d.n
            if d.id ~= 112 and refs.Inv then
                local okr, room = pcall(function() return refs.Inv:room(d.id) end)
                if okr and type(room) == "number" then amount = math.min(amount, room) end
            end
            if amount <= 0 then
                DropFailUntil[d.uid] = now + 1
                return false
            end

            d.taking = true
            if typeof(d.frame) == "Instance" then
                pcall(function() d.frame.Visible = false end)
            end

            local ok, taken = pcall(worldTake, d.uid, amount)
            d.taking = false

            if not (ok and type(taken) == "number" and taken > 0) then
                d.refused = os.clock()
                d.failN = (d.failN or 0) + 1
                DropFailUntil[d.uid] = os.clock() + math.min(8, d.failN)
                d.flown = nil
                if typeof(d.frame) == "Instance" then
                    pcall(function() d.frame.Visible = not d.culled end)
                end
                return false
            end

            DropFailUntil[d.uid] = nil
            if d.id ~= 112 and refs.Inv then
                pcall(function() refs.Inv:add(d.id, taken) end)
            end
            Drops.applyTaken(d, math.max(0, (d.n or 0) - taken))
            return true
        end

        -- Batas tile persis dari inTile() k(5).lua.
        local function inTile(t, x, y)
            return x >= t.x - 0.15 and x < t.x + 1.15
                and y >= t.y - 0.15 and y < t.y + 1.15
        end

        local function canTry(d, now)
            if type(d) ~= "table" or d.taking or (d.n or 0) <= 0
                or type(d.x) ~= "number" then return false end
            if d.armed == false and d.id ~= 112 then return false end
            local fail = DropFailUntil[d.uid]
            return not (fail and now < fail)
        end

        -- Cari satu objek drop pada tile tertentu.
        -- Satu objek UID = satu titik drop; d.n boleh berisi stack sampai 200.
        local function findDropAtTile(tileX, tileY)
            findDropRefs() -- refresh daftar drop sebelum setiap pemeriksaan
            local list = Drops.list
            if type(list) ~= "table" then return nil, false end

            local now = os.clock()
            local firstBlocked = nil

            -- Satu objek dipilih per iterasi; tidak ada task.spawn massal.
            for i = #list, 1, -1 do
                local d = list[i]
                if type(d) == "table"
                    and (d.n or 0) > 0
                    and type(d.x) == "number"
                    and type(d.y) == "number"
                    and inTile({x = tileX, y = tileY}, d.x, d.y) then

                    if canTry(d, now) then
                        return d, true
                    end

                    -- Drop masih ada tetapi sedang pending/cooldown/tidak armed.
                    -- Tile tidak dianggap bersih selama objek ini masih tercatat.
                    firstBlocked = firstBlocked or d
                end
            end

            if firstBlocked then
                return firstBlocked, true
            end
            return nil, false
        end

        local function collectOneTile(dx, dy)
            local key = dx .. "," .. dy
            if enabled[key] ~= true then return true end

            while running and not destroyed do
                local px, py = playerTile()
                if not px then
                    status.Text = "Status: posisi player belum terbaca"
                    task.wait(0.15)
                else
                    local tx, ty = px + dx, py + dy
                    local drop, stillHasDrop = findDropAtTile(tx, ty)

                    if not stillHasDrop then
                        -- Tile baru dianggap bersih setelah hasil scan real-time kosong.
                        return true
                    end

                    if drop and canTry(drop, os.clock()) then
                        status.Text = ("Status: mengambil tile (%d,%d) | UID %s")
                            :format(dx, dy, tostring(drop.uid))
                        takeDrop(drop) -- tunggu hasilnya; jangan spawn paralel
                    else
                        status.Text = ("Status: menunggu tile (%d,%d) | drop masih ada")
                            :format(dx, dy)
                    end

                    -- Beri waktu event/server memperbarui daftar, lalu scan tile
                    -- yang SAMA lagi. Tidak pindah sebelum benar-benar kosong.
                    task.wait(0.1)
                end
            end

            return false
        end

        local function remoteTick()
            -- Urutan tetap: baris atas ke bawah, kiri ke kanan.
            -- Satu tile diselesaikan dulu sebelum tile berikutnya dimulai.
            for dy = -2, 2 do
                for dx = -2, 2 do
                    if not running or destroyed then return end
                    local key = dx .. "," .. dy
                    if enabled[key] == true then
                        local clean = collectOneTile(dx, dy)
                        if not clean then return end
                    end
                end
            end
            -- Setelah semua tile terpilih selesai, putaran berikutnya dimulai
            -- dari tile pertama; semua tile dipindai lagi secara real-time.
        end

        -- UI dasar.
        local root = page
        local title = create("TextLabel", {
            Name = "AutoCollectTitle",
            Size = UDim2.new(1, -12, 0, 28),
            BackgroundTransparency = 1,
            Text = "AUTO COLLECT | REMOTE",
            TextColor3 = Theme.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, root)

        local status = create("TextLabel", {
            Name = "AutoCollectStatus",
            Position = UDim2.fromOffset(0, 30),
            Size = UDim2.new(1, -12, 0, 34),
            BackgroundTransparency = 1,
            Text = "Status: menunggu scan",
            TextColor3 = Theme.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, root)

        local tileButton = create("TextButton", {
            Position = UDim2.fromOffset(0, 70),
            Size = UDim2.fromOffset(190, 34),
            BackgroundColor3 = Theme.PanelDark,
            BorderSizePixel = 0,
            Text = "PILIH TILE (0 AKTIF)",
            TextColor3 = Theme.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
        }, root)
        corner(tileButton, 7)

        local toggle = create("TextButton", {
            Position = UDim2.fromOffset(198, 70),
            Size = UDim2.fromOffset(100, 34),
            BackgroundColor3 = Theme.Green,
            BorderSizePixel = 0,
            Text = "START",
            TextColor3 = Theme.White,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
        }, root)
        corner(toggle, 7)

        local function activeCount()
            local n = 0
            for _, v in pairs(enabled) do if v then n += 1 end end
            return n
        end

        local function updateTileButton()
            tileButton.Text = ("PILIH TILE (%d AKTIF)"):format(activeCount())
        end

        local function closePopup()
            if popup then popup:Destroy(); popup = nil end
        end

        local function openPopup()
            if destroyed or popup then return end
            local gui = Hub.GetGui and Hub.GetGui()
            if not gui then
                status.Text = "Status: ScreenGui Hub tidak ditemukan"
                return
            end

            popup = create("Frame", {
                Name = "AutoCollectTilePopup",
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(292, 310),
                BackgroundColor3 = Theme.Background,
                BorderSizePixel = 0,
                ZIndex = 200,
            }, gui)
            corner(popup, 10)

            create("TextLabel", {
                Position = UDim2.fromOffset(10, 5),
                Size = UDim2.new(1, -50, 0, 28),
                BackgroundTransparency = 1,
                Text = "PILIH TILE TARGET (5 x 5)",
                TextColor3 = Theme.Text,
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 201,
            }, popup)

            local close = create("TextButton", {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -8, 0, 7),
                Size = UDim2.fromOffset(28, 25),
                BackgroundColor3 = Theme.Red,
                BorderSizePixel = 0,
                Text = "X",
                TextColor3 = Theme.White,
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                ZIndex = 202,
            }, popup)
            corner(close, 5)

            local grid = create("Frame", {
                Position = UDim2.fromOffset(16, 42),
                Size = UDim2.fromOffset(260, 260),
                BackgroundTransparency = 1,
                ZIndex = 201,
            }, popup)
            create("UIGridLayout", {
                CellSize = UDim2.fromOffset(49, 49),
                CellPadding = UDim2.fromOffset(3, 3),
                SortOrder = Enum.SortOrder.LayoutOrder,
            }, grid)

            for dy = -2, 2 do
                for dx = -2, 2 do
                    local key = dx .. "," .. dy
                    if enabled[key] == nil then enabled[key] = true end
                    local b = create("TextButton", {
                        BackgroundColor3 = enabled[key] and Theme.Green or Theme.PanelDark,
                        BorderSizePixel = 0,
                        Text = (dx == 0 and dy == 0) and "YOU" or (enabled[key] and "ON" or "OFF"),
                        TextColor3 = Theme.White,
                        Font = Enum.Font.GothamBold,
                        TextSize = 10,
                        ZIndex = 202,
                    }, grid)
                    corner(b, 6)
                    track(b.Activated:Connect(function()
                        if destroyed then return end
                        enabled[key] = not enabled[key]
                        b.Text = (dx == 0 and dy == 0) and (enabled[key] and "YOU ON" or "YOU OFF")
                            or (enabled[key] and "ON" or "OFF")
                        b.BackgroundColor3 = enabled[key] and Theme.Green or Theme.PanelDark
                        updateTileButton()
                    end))
                end
            end

            track(close.Activated:Connect(closePopup))
        end

        track(tileButton.Activated:Connect(openPopup))

        local function setRunning(value)
            running = value
            toggle.Text = running and "STOP" or "START"
            toggle.BackgroundColor3 = running and Theme.Red or Theme.Green
            if running then
                status.Text = "Status: aktif | Remote | satu drop bergiliran | scan sampai tile bersih"
            else
                status.Text = "Status: berhenti"
            end
        end

        track(toggle.Activated:Connect(function()
            if destroyed then return end
            if not running then
                if activeCount() == 0 then
                    status.Text = "Status: pilih minimal satu tile"
                    return
                end
                if not refs.World or not refs.Inv or not refs.State then
                    local ok, message = discover()
                    if not ok then
                        status.Text = "Status: scan gagal - " .. tostring(message)
                        return
                    end
                end
                if not findDropRefs() then
                    status.Text = "Status: daftar drop belum ditemukan"
                    return
                end
                setRunning(true)
            else
                setRunning(false)
            end
        end))

        task.spawn(function()
            task.wait(0.4)
            if destroyed or (Hub.IsClosing and Hub.IsClosing()) then return end
            local ok, message = pcall(discover)
            if not ok then
                status.Text = "Status: scan error - " .. tostring(message)
            elseif message then
                status.Text = "Status: " .. tostring(message)
            end
            if ok and refs.World then
                findDropRefs()
            end
        end)

        task.spawn(function()
            while not destroyed and not (Hub.IsClosing and Hub.IsClosing()) do
                if running then
                    local ok, err = pcall(remoteTick)
                    if not ok then
                        status.Text = "Status: error collect - " .. tostring(err)
                        task.wait(0.25)
                    end
                else
                    task.wait(0.1)
                end
            end
        end)

        local function cleanup()
            if destroyed then return end
            destroyed = true
            running = false
            closePopup()
            for _, c in ipairs(connections) do
                pcall(function() c:Disconnect() end)
            end
            table.clear(connections)
        end

        Hub.RegisterCleanup(cleanup)
        updateTileButton()
    end)
end
