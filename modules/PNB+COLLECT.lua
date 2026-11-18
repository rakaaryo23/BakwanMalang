--==================================================
-- MODULE: AUTO PUT + BREAK + COLLECT (TILES 7-9)
-- File ini hanya berisi submenu. Tempel/ganti satu blok menu
-- pada script GrowBlox Hub yang sudah memiliki Hub.RegisterTab.
--==================================================

return function(Hub)

    Hub.RegisterTab("PUT + BREAK + COLLECT", function(page)

    --==================================================
    -- [A] CONFIGURATION & STATE
    --==================================================

    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = Players.LocalPlayer

    local CFG = {
        PutDelay = 80,
        BreakDelay = 140,
        BreakStartDelay = 150,
        CycleDelay = 150,
    }

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
    }

    local running = false
    local destroyed = false
    local confirmedId = nil

    local refs = {
        Inv = nil,
        World = nil,
        State = nil,
        SetTile = nil,
        Hit = nil,
    }

    local enabled = { ["-1,-1"] = true, ["0,-1"] = true, ["1,-1"] = true }
    local connections = {}
    local popup = nil
    local Drops = { list = nil, update = nil }
    local DropFailUntil = {}
    local WorldRemotes = ReplicatedStorage:FindFirstChild("WorldRemotes")
    local TakeDropRemote = WorldRemotes and WorldRemotes:FindFirstChild("TakeDrop")

    -- Forward declaration is IMPORTANT:
    -- report() must reference this local, not a global nil.
    local statusLabel
    local selectedLabel
    local tileButton

    local function report(message)
        message = tostring(message)
        if statusLabel and statusLabel.Parent then
            statusLabel.Text = "Status: " .. message
        end
        print("[APB+COLLECT]", message)
    end

    local function track(connection)
        table.insert(connections, connection)
        return connection
    end

    --==================================================
    -- [B] UI HELPERS
    --==================================================

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
        }, parent or page)
    end

    local function makeButton(text, height, parent, color)
        local b = create("TextButton", {
            Size = UDim2.new(1, 0, 0, height or 32),
            BackgroundColor3 = color or Theme.Accent,
            BorderSizePixel = 0,
            Text = text,
            TextColor3 = Theme.White,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            AutoButtonColor = true,
        }, parent or page)
        corner(b, 7)
        return b
    end

    local function makeDelayBox(caption, value, parent)
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, 42),
            BackgroundTransparency = 1,
        }, parent)

        create("TextLabel", {
            Size = UDim2.new(0.58, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = caption,
            TextColor3 = Theme.Text,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)

        local box = create("TextBox", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0.38, 0, 0, 29),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            Text = tostring(value),
            PlaceholderText = "ms",
            TextColor3 = Theme.Text,
            PlaceholderColor3 = Theme.Muted,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            ClearTextOnFocus = false,
        }, row)
        corner(box, 6)
        return box
    end

    --==================================================
    -- [C] MAIN SUBMENU UI
    --==================================================

    local list = create("UIListLayout", {
        Padding = UDim.new(0, 7),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, page)

    statusLabel = makeLabel("Status: menyiapkan scan...", 34)
    statusLabel.LayoutOrder = 1

    selectedLabel = makeLabel("Inventory selected: belum terbaca", 28)
    selectedLabel.LayoutOrder = 2

    local areaLabel = makeLabel(
        "TARGET FIX: 7, 8, 9 | Player di tile 13",
        24
    )
    areaLabel.LayoutOrder = 3

    tileButton = makeButton("TARGET TERKUNCI: TILE 7, 8, 9", 34, page, Theme.PanelDark)
    tileButton.TextColor3 = Theme.Text
    tileButton.Active = false
    tileButton.AutoButtonColor = false
    tileButton.LayoutOrder = 4

    local scanButton = makeButton(
        "SCAN ULANG", 32, page, Theme.PanelDark
    )
    scanButton.TextColor3 = Theme.Text
    scanButton.LayoutOrder = 5

    local lockButton = makeButton("LOCK SELECTED", 32)
    lockButton.LayoutOrder = 6

    local previewButton = makeButton(
        "PREVIEW TARGET", 32, page, Theme.PanelDark
    )
    previewButton.TextColor3 = Theme.Text
    previewButton.LayoutOrder = 7

    local startButton = makeButton(
        "START PUT → BREAK → COLLECT", 36, page, Theme.Green
    )
    startButton.LayoutOrder = 8

    local stopButton = makeButton("STOP", 32, page, Theme.Red)
    stopButton.LayoutOrder = 9

    local settingsButton = makeButton(
        "PENGATURAN DELAY  ▼", 30, page, Theme.PanelDark
    )
    settingsButton.TextColor3 = Theme.Text
    settingsButton.LayoutOrder = 10

    local settingsFrame = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        Visible = false,
        LayoutOrder = 11,
    }, page)
    corner(settingsFrame, 8)

    create("UIPadding", {
        PaddingTop = UDim.new(0, 7),
        PaddingBottom = UDim.new(0, 7),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }, settingsFrame)

    create("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, settingsFrame)

    local putDelayBox = makeDelayBox(
        "Jeda antar PUT (ms)", CFG.PutDelay, settingsFrame
    )
    local breakDelayBox = makeDelayBox(
        "Jeda antar HIT BREAK (ms)", CFG.BreakDelay, settingsFrame
    )
    local breakStartBox = makeDelayBox(
        "Jeda awal BREAK (ms)", CFG.BreakStartDelay, settingsFrame
    )
    local cycleDelayBox = makeDelayBox(
        "Jeda antar siklus (ms)", CFG.CycleDelay, settingsFrame
    )

    track(settingsButton.Activated:Connect(function()
        settingsFrame.Visible = not settingsFrame.Visible
        settingsButton.Text = settingsFrame.Visible
            and "PENGATURAN DELAY  ▲"
            or "PENGATURAN DELAY  ▼"
    end))

    --==================================================
    -- [D] TARGET FIXED: TILE 7, 8, 9
    --==================================================

    local function closePopup()
        if popup then popup:Destroy(); popup = nil end
    end

    --==================================================
    -- [E] APB V4 DISCOVERY (SAME WORKING SCAN LOGIC)
    --==================================================

    local getconsts = (debug and debug.getconstants) or getconstants

    local function raw(t, k)
        if type(t) ~= "table" then return nil end
        local ok, value = pcall(rawget, t, k)
        return ok and value or nil
    end

    local function inventoryCandidate(t)
        if type(t) ~= "table" then return nil end

        local slots = raw(t, "slots")
        local cap = raw(t, "capacity")

        if type(slots) ~= "table" or type(cap) ~= "number"
            or cap < 0 or cap > 10000 then
            return nil
        end

        local valid, populated = 0, 0
        for k, slot in pairs(slots) do
            if type(k) == "number" and k > 0 and k % 1 == 0
                and type(slot) == "table" then
                local id = raw(slot, "id")
                local n = raw(slot, "n")
                if id ~= nil or n ~= nil then valid += 1 end
                if id ~= nil then populated += 1 end
            end
        end

        if valid == 0 and next(slots) ~= nil then return nil end
        return {
            ref = t,
            score = valid * 100 + populated + math.min(cap, 100)
        }
    end

    local function findSetTile(objects)
        for _, fn in ipairs(objects) do
            if type(fn) == "function" then
                local okN, name = pcall(debug.info, fn, "n")
                local okA, params, variadic = pcall(debug.info, fn, "a")

                if okN and okA and name == "setTile"
                    and params == 6 and variadic == false then
                    local okC, constants = pcall(getconsts, fn)

                    if okC and type(constants) == "table" then
                        local found = {}
                        for _, value in pairs(constants) do
                            found[value] = true
                        end

                        if found.tile and found.send and found.layer
                            and found.x and found.y and found.id
                            and found.flip and found.placedAt and found.flips then
                            return fn
                        end
                    end
                end
            end
        end
    end

    local function findHit(objects)
        for _, fn in ipairs(objects) do
            if type(fn) == "function" then
                local okN, name = pcall(debug.info, fn, "n")
                local okA, params = pcall(debug.info, fn, "a")

                if okN and okA and name == "hit" and params == 4 then
                    local okC, constants = pcall(getconsts, fn)

                    if okC and type(constants) == "table" then
                        local found = {}
                        for _, value in pairs(constants) do
                            found[value] = true
                        end

                        if found.sendHit and found.punchEvent
                            and found.newCrack then
                            return fn
                        end
                    end
                end
            end
        end
    end

    local function discover()
        if type(getgc) ~= "function"
            or type(getconsts) ~= "function"
            or not (debug and debug.info) then
            return false,
                "Executor tidak menyediakan getgc/getconstants/debug.info"
        end

        local ok, objects = pcall(getgc, true)
        if not ok or type(objects) ~= "table" then
            return false, "getgc(true) gagal: " .. tostring(objects)
        end

        refs.Inv, refs.World, refs.State = nil, nil, nil
        refs.SetTile, refs.Hit = nil, nil

        local bestInv

        for _, obj in ipairs(objects) do
            if type(obj) == "table" then
                local candidate = inventoryCandidate(obj)
                if candidate and (
                    not bestInv or candidate.score > bestInv.score
                ) then
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
        refs.SetTile = findSetTile(objects)
        refs.Hit = findHit(objects)

        local missing = {}
        for _, key in ipairs({"Inv", "World", "State", "SetTile", "Hit"}) do
            if not refs[key] then
                table.insert(missing, key)
            end
        end

        if #missing > 0 then
            return false, "Referensi belum lengkap: "
                .. table.concat(missing, ", ")
        end

        return true,
            "Scan berhasil: Inventory, World, State, setTile, hit ditemukan."
    end

    --==================================================
    -- [F] INVENTORY / WORLD HELPERS
    --==================================================

    local function selectedId()
        local id = tonumber(raw(refs.Inv, "selected"))
        if id and id > 0 then return math.floor(id) end
    end

    local function countItem(id)
        local total = 0
        local slots = raw(refs.Inv, "slots")
        if type(slots) ~= "table" then return 0 end

        for _, slot in pairs(slots) do
            if type(slot) == "table"
                and tonumber(raw(slot, "id")) == id then
                total += tonumber(raw(slot, "n")) or 0
            end
        end
        return total
    end

    local function playerTile()
        local ok, state = pcall(refs.State)
        if not ok or type(state) ~= "table"
            or type(state.x) ~= "number"
            or type(state.y) ~= "number" then
            return nil
        end

        if state.active == false then return nil end
        return math.floor(state.x), math.floor(state.y - 0.475)
    end

    local function tileAt(layer, x, y)
        local world = refs.World
        if not world or x < 0 or y < 0
            or x >= world.w or y >= world.h then
            return nil
        end

        local row = world[layer] and world[layer][y]
        if not row then return nil end
        return row[x] or 0
    end

    --==================================================
    -- [G] BUILD PLAN
    --==================================================

    local function buildPlan()
        local px, py = playerTile()
        if not px then return nil, "Posisi player tidak terbaca." end

        local plan = {}
        -- Grid 5x5 bernomor: target 7,8,9 = dx -1,0,1 dan dy -1.
        for dx = -1, 1 do
            local x, y = px + dx, py - 1
            if x < 0 or y < 0 or x >= refs.World.w or y >= refs.World.h then
                return nil, ("Koordinat tile %d di luar world."):format(dx + 8)
            end
            plan[#plan + 1] = { x = x, y = y, dx = dx, dy = -1, tileNo = dx + 8 }
        end
        return plan, px, py
    end

    --==================================================
    -- [H] PUT
    --==================================================

    local function putOne(x, y, id)
        local fg = tileAt("fg", x, y)
        local bg = tileAt("bg", x, y)

        if fg == nil or bg == nil then
            return false, "koordinat di luar world"
        end

        if fg ~= 0 or bg ~= 0 then
            return false, ("petak tidak kosong (FG=%s, BG=%s)"):format(
                tostring(fg), tostring(bg)
            )
        end

        if countItem(id) <= 0 then
            return false, "item inventory habis"
        end

        local ok, err = pcall(
            refs.SetTile, "fg", x, y, id, false, false
        )

        if not ok then
            for _ = 1, 20 do
                if not running or destroyed or Hub.IsClosing() then
                    return false, "proses dihentikan"
                end

                task.wait(0.05)
                local nowFg, nowBg = tileAt("fg", x, y), tileAt("bg", x, y)

                if nowFg == id and nowBg == 0 then
                    return true, "PUT terdeteksi setelah SetTile error"
                end
                if nowFg == nil or nowBg == nil then break end
            end

            return false, "setTile error: " .. tostring(err)
        end

        for _ = 1, 60 do
            if not running or destroyed or Hub.IsClosing() then
                return false, "dihentikan saat verifikasi PUT"
            end

            task.wait(0.05)
            local nowFg, nowBg = tileAt("fg", x, y), tileAt("bg", x, y)

            if nowFg == nil or nowBg == nil then
                return false, "tile keluar dari world saat verifikasi PUT"
            end

            if nowFg == id and nowBg == 0 then
                return true, "PUT terkonfirmasi"
            end
        end

        local finalFg, finalBg = tileAt("fg", x, y), tileAt("bg", x, y)
        return false, ("PUT tidak terkonfirmasi (FG=%s, BG=%s)"):format(
            tostring(finalFg), tostring(finalBg)
        )
    end

    --==================================================
    -- [I] BREAK
    --==================================================

    local function breakOne(x, y, startDelayMs, hitDelayMs)
        task.wait(math.max(0, startDelayMs) / 1000)

        local function readLayers()
            return tileAt("fg", x, y), tileAt("bg", x, y)
        end

        local function confirmEmpty()
            local consecutive = 0

            for _ = 1, 20 do
                if not running or destroyed or Hub.IsClosing() then
                    return false
                end

                task.wait(0.05)
                local fg, bg = readLayers()

                if fg == nil or bg == nil then
                    return false
                end

                if fg == 0 and bg == 0 then
                    consecutive += 1
                    if consecutive >= 3 then return true end
                else
                    consecutive = 0
                    return false
                end
            end

            return false
        end

        local fg, bg = readLayers()
        if fg == nil or bg == nil then
            return false, "koordinat tidak valid"
        end

        if fg == 0 and bg == 0 and confirmEmpty() then
            return true, "FG dan BG sudah kosong (terkonfirmasi 3x)"
        end

        for hitNo = 1, 60 do
            if not running or destroyed or Hub.IsClosing() then
                return false, "dihentikan"
            end

            fg, bg = readLayers()
            if fg == nil or bg == nil then
                return false, "koordinat tidak valid"
            end

            if fg == 0 and bg == 0 and confirmEmpty() then
                return true, ("tile kosong stabil setelah %d hit"):format(hitNo - 1)
            end

            local ok, err = pcall(refs.Hit, x, y, nil, nil)
            if not ok then
                return false, "hit error: " .. tostring(err)
            end

            task.wait(math.max(0, hitDelayMs) / 1000)

            local afterFg, afterBg = readLayers()
            if afterFg == nil or afterBg == nil then
                return false, "koordinat tidak valid setelah hit"
            end

            if afterFg == 0 and afterBg == 0 and confirmEmpty() then
                return true, ("tile kosong stabil setelah %d hit"):format(hitNo)
            end
        end

        local finalFg, finalBg = readLayers()
        return false, (
            "BREAK belum terkonfirmasi setelah 60 hit (FG=%s, BG=%s)"
        ):format(tostring(finalFg), tostring(finalBg))
    end

    --==================================================
    -- [J] AUTO COLLECT | HANYA TILE 7, 8, 9
    -- Mekanisme remote dan update drop mengikuti uhuy.lua.
    --==================================================

    local function getUpvalues(fn)
        if debug and debug.getupvalues then
            local ok, ups = pcall(debug.getupvalues, fn)
            if ok and type(ups) == "table" then return ups end
        end
        local out = {}
        local gu = (debug and debug.getupvalue) or getupvalue
        if gu then
            for i = 1, 60 do
                local ok, name, value = pcall(gu, fn, i)
                if not ok or name == nil then break end
                out[i] = value
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

    local function findDropRefs()
        local world = refs.World
        local dropListFn = world and raw(world, "dropList")
        if type(dropListFn) == "function" then
            local ok, listRef = pcall(dropListFn)
            if ok and isDropList(listRef) then
                if Drops.list ~= listRef then Drops.update = nil end
                Drops.list = listRef
            end
        end

        if not Drops.list then
            local dropTaken = world and raw(world, "dropTaken")
            if type(dropTaken) == "function" then
                for _, upvalue in pairs(getUpvalues(dropTaken)) do
                    if not Drops.list and isDropList(upvalue) then
                        Drops.list = upvalue
                    elseif not Drops.update and type(upvalue) == "function" then
                        for _, nested in pairs(getUpvalues(upvalue)) do
                            if type(nested) == "table" and isDropList(nested) then
                                Drops.list = nested
                                Drops.update = upvalue
                                break
                            end
                        end
                    end
                end
            end
        end

        if Drops.list and not Drops.update then
            local dropTaken = world and raw(world, "dropTaken")
            if type(dropTaken) == "function" then
                for _, upvalue in pairs(getUpvalues(dropTaken)) do
                    if type(upvalue) == "function" then
                        for _, nested in pairs(getUpvalues(upvalue)) do
                            if rawequal(nested, Drops.list) then
                                Drops.update = upvalue
                                break
                            end
                        end
                    end
                    if Drops.update then break end
                end
            end
        end

        -- Fallback yang juga dipakai modul uhuy.lua: cari drop list dari
        -- listener event DropTaken bila World.dropList/upvalue tidak tersedia.
        if not Drops.list and getconnections then
            local remotes = ReplicatedStorage:FindFirstChild("WorldRemotes")
            local event = remotes and remotes:FindFirstChild("DropTaken")
            if event then
                local ok, listeners = pcall(getconnections, event.OnClientEvent)
                if ok and type(listeners) == "table" then
                    for _, connection in ipairs(listeners) do
                        local got, callback = pcall(function() return connection.Function end)
                        if got and type(callback) == "function" then
                            for _, upvalue in pairs(getUpvalues(callback)) do
                                if not Drops.list and isDropList(upvalue) then
                                    Drops.list = upvalue
                                elseif not Drops.update and type(upvalue) == "function" then
                                    for _, nested in pairs(getUpvalues(upvalue)) do
                                        if Drops.list and rawequal(nested, Drops.list) then
                                            Drops.update = upvalue
                                            break
                                        end
                                    end
                                end
                            end
                        end
                        if Drops.list then break end
                    end
                end
            end
        end
        return Drops.list ~= nil
    end

    local function applyTaken(drop, left)
        local listRef = Drops.list
        if not listRef or not table.find(listRef, drop) then return end
        if Drops.update then
            local ok = pcall(Drops.update, drop, left)
            if ok then
                if left > 0 then
                    drop.flown = nil
                    if typeof(drop.frame) == "Instance" then
                        pcall(function() drop.frame.Visible = not drop.culled end)
                    end
                end
                return
            end
        end
        drop.n = left
        if left > 0 then
            drop.flown = nil
            if typeof(drop.frame) == "Instance" then
                pcall(function() drop.frame.Visible = not drop.culled end)
            end
        else
            local index = table.find(listRef, drop)
            if index then table.remove(listRef, index) end
            if typeof(drop.frame) == "Instance" then
                pcall(function() drop.frame:Destroy() end)
            end
        end
    end

    local function inTargetTile(drop, target)
        return type(drop.x) == "number" and type(drop.y) == "number"
            and drop.x >= target.x - 0.15 and drop.x < target.x + 1.15
            and drop.y >= target.y - 0.15 and drop.y < target.y + 1.15
    end

    local function takeDrop(drop)
        local worldTake = refs.World and raw(refs.World, "takeDrop")
        if type(worldTake) ~= "function" and not TakeDropRemote then
            return false, "fungsi takeDrop/remote tidak ditemukan"
        end
        if drop.taking or drop.pending or drop.display or (drop.n or 0) <= 0 then
            return false, "drop sedang diproses atau kosong"
        end
        if drop.armed == false and drop.id ~= 112 then
            return false, "drop tidak eligible (armed=false)"
        end

        local now = os.clock()
        if DropFailUntil[drop.uid] and now < DropFailUntil[drop.uid] then
            return false, "UID masih dalam cooldown gagal"
        end

        local amount = drop.n
        if drop.id ~= 112 and refs.Inv then
            local roomOk, room = pcall(function() return refs.Inv:room(drop.id) end)
            if roomOk and type(room) == "number" then amount = math.min(amount, room) end
        end
        if amount <= 0 then
            DropFailUntil[drop.uid] = now + 1
            return false, "inventory penuh"
        end

        local beforeN = tonumber(drop.n) or 0
        drop.taking = true
        if typeof(drop.frame) == "Instance" then
            pcall(function() drop.frame.Visible = false end)
        end

        local ok, taken
        if type(worldTake) == "function" then
            ok, taken = pcall(worldTake, drop.uid, amount)
        else
            ok, taken = pcall(TakeDropRemote.InvokeServer, TakeDropRemote, drop.uid, amount)
        end
        drop.taking = false

        if not (ok and type(taken) == "number" and taken > 0) then
            drop.refused = os.clock()
            drop.failN = (drop.failN or 0) + 1
            DropFailUntil[drop.uid] = os.clock() + math.min(8, drop.failN)
            drop.flown = nil
            if typeof(drop.frame) == "Instance" then
                pcall(function() drop.frame.Visible = not drop.culled end)
            end
            return false, ok and ("server return: " .. tostring(taken)) or tostring(taken)
        end

        DropFailUntil[drop.uid] = nil
        if drop.id ~= 112 and refs.Inv then
            pcall(function() refs.Inv:add(drop.id, taken) end)
        end
        applyTaken(drop, math.max(0, beforeN - taken))
        return true, ("UID %s taken %d/%d"):format(tostring(drop.uid), taken, beforeN)
    end

    local function dropsAtTarget(target)
        local found = {}
        local listRef = Drops.list
        if type(listRef) ~= "table" then return found end
        for _, drop in ipairs(listRef) do
            if type(drop) == "table" and (tonumber(drop.n) or 0) > 0
                and inTargetTile(drop, target) then
                found[#found + 1] = drop
            end
        end
        return found
    end

    local function collectTarget(target, timeoutSeconds, anchorX, anchorY)
        local deadline = os.clock() + timeoutSeconds
        local attempts = 0
        while running and not destroyed and not Hub.IsClosing() do
            local currentX, currentY = playerTile()
            if not currentX or currentX ~= anchorX or currentY ~= anchorY then
                return false, "posisi player berubah dari anchor"
            end
            if not Drops.list and not findDropRefs() then
                task.wait(0.2)
            else
                local found = dropsAtTarget(target)
                if #found == 0 then
-- Validasi tile kosong selama 0.4 detik.
local stable = true
for _ = 1, 2 do
    task.wait(0.2)
    if #dropsAtTarget(target) > 0 then
        stable = false
        break
    end
end
if stable then
    return true, "tile bersih; tidak ada drop tersisa"
end
                else
                    for _, drop in ipairs(found) do
                        if not running or destroyed or Hub.IsClosing() then
                            return false, "collect dihentikan"
                        end
                        attempts += 1
                        local ok, message = takeDrop(drop)
                        if not ok and (drop.n or 0) > 0 then
                            -- Jangan tandai tile selesai jika drop masih terlihat.
                            report(("COLLECT TILE %d: menunggu UID %s | %s"):format(
                                target.tileNo, tostring(drop.uid), tostring(message)
                            ))
                        end
                        task.wait(0.12)
                    end
                end
            end

            if os.clock() >= deadline then
                local remaining = #dropsAtTarget(target)
                return false, ("timeout; %d drop masih ada setelah %d percobaan"):format(remaining, attempts)
            end
        end
        return false, "collect dihentikan"
    end

    local function collectPhase(plan, anchorX, anchorY)
        if not findDropRefs() then
            return false, "daftar drop tidak ditemukan"
        end
        for _, target in ipairs(plan) do
            if not running or destroyed or Hub.IsClosing() then
                return false, "collect dihentikan"
            end
            report(("COLLECT TILE %d (%d,%d)"):format(target.tileNo, target.x, target.y))
            local ok, message = collectTarget(target, 15, anchorX, anchorY)
            if not ok then
                return false, ("tile %d gagal: %s"):format(target.tileNo, tostring(message))
            end
            report(("COLLECT TILE %d OK: %s"):format(target.tileNo, tostring(message)))
        end
        return true, "semua drop pada tile 7, 8, 9 sudah diambil"
    end

    --==================================================
    -- [K] DELAY VALIDATION
    --==================================================

    local function readDelay(box, minimum, maximum)
        local n = tonumber(box.Text)
        if not n then return nil, "Isi jeda harus berupa angka (ms)." end

        n = math.floor(n)
        if n < minimum or n > maximum then
            return nil, ("Jeda harus %d sampai %d ms."):format(minimum, maximum)
        end
        return n
    end

    --==================================================
    -- [L] BUTTON EVENTS
    --==================================================

    track(scanButton.Activated:Connect(function()
        if running then
            report("Stop proses sebelum scan ulang.")
            return
        end

        confirmedId = nil
        selectedLabel.Text = "Inventory selected: sedang scan..."

        task.spawn(function()
            local ok, message = discover()
            if destroyed or Hub.IsClosing() then return end

            report(ok and message or ("SCAN GAGAL: " .. message))

            if refs.Inv then
                local id = selectedId()
                selectedLabel.Text = id
                    and ("Inventory selected: ID %d | jumlah: %d"):format(
                        id, countItem(id)
                    )
                    or "Inventory selected: tidak ada"
            else
                selectedLabel.Text = "Inventory selected: tidak ditemukan"
            end
        end)
    end))

    track(lockButton.Activated:Connect(function()
        if not refs.Inv then
            report("Inventory belum ditemukan. Tekan SCAN ULANG.")
            return
        end

        local id = selectedId()
        if not id then
            confirmedId = nil
            selectedLabel.Text = "Inventory selected: tidak ada item terpilih"
            report("Pilih item di inventory game terlebih dahulu.")
            return
        end

        if countItem(id) <= 0 then
            confirmedId = nil
            report("Selected ID " .. id .. " tidak memiliki jumlah item.")
            return
        end

        confirmedId = id
        selectedLabel.Text = ("LOCKED ID: %d | jumlah: %d"):format(
            id, countItem(id)
        )
        report("Item inventory dikunci: ID " .. id)
    end))

    track(previewButton.Activated:Connect(function()
        if not refs.World or not refs.State then
            report("World/State belum siap.")
            return
        end

        local plan, px, py = buildPlan()
        if not plan then
            report("PREVIEW GAGAL: " .. tostring(px))
            return
        end

        local coords = {}
        for i, p in ipairs(plan) do
            coords[#coords + 1] = ("%d:(%d,%d)"):format(i, p.x, p.y)
        end

        report(("Anchor player %d,%d | %d target | %s"):format(
            px, py, #plan, table.concat(coords, " ")
        ))
    end))

    track(stopButton.Activated:Connect(function()
        running = false
        report("STOP diminta.")
    end))

    track(startButton.Activated:Connect(function()
        if running then return end

        if not (refs.Inv and refs.World and refs.State
            and refs.SetTile and refs.Hit) then
            report("Referensi belum lengkap. Tekan SCAN ULANG.")
            return
        end

        if not confirmedId then
            report("Pilih item di inventory lalu LOCK SELECTED.")
            return
        end

        local putMs, e1 = readDelay(putDelayBox, 0, 10000)
        local hitMs, e2 = readDelay(breakDelayBox, 1, 10000)
        local startMs, e3 = readDelay(breakStartBox, 50, 10000)
        local cycleMs, e4 = readDelay(cycleDelayBox, 0, 60000)

        if not putMs then report(e1) return end
        if not hitMs then report(e2) return end
        if not startMs then report(e3) return end
        if not cycleMs then report(e4) return end

        local plan, px, py = buildPlan()
        if not plan then
            report("START dibatalkan: " .. tostring(px))
            return
        end
        if not findDropRefs() then
            report("START dibatalkan: daftar drop belum ditemukan.")
            return
        end

        closePopup()
        running = true

        task.spawn(function()
            local cycle = 0

            report(("LOOP START | anchor %d,%d | ID %d | %d target"):format(
                px, py, confirmedId, #plan
            ))

            while running and not destroyed and not Hub.IsClosing() do
                cycle += 1

                local breakQueue = {}
                local hasEmptyTargetWithoutItem = false

                report(("SIKLUS %d | FASE PUT / CEK TILE"):format(cycle))

                for index, p in ipairs(plan) do
                    if not running or destroyed or Hub.IsClosing() then break end

                    local cx, cy = playerTile()
                    if not cx or cx ~= px or cy ~= py then
                        running = false
                        report("STOP AMAN: posisi player berubah dari anchor.")
                        break
                    end

                    local currentFg = tileAt("fg", p.x, p.y)
                    local currentBg = tileAt("bg", p.x, p.y)

                    if currentFg == nil or currentBg == nil then
                        report(("SKIP (%d,%d): koordinat tidak valid"):format(
                            p.x, p.y
                        ))
                    elseif currentFg ~= 0 or currentBg ~= 0 then
                        breakQueue[#breakQueue + 1] = p
                        report(("MASUK ANTREAN BREAK (%d,%d)"):format(p.x, p.y))
                    else
                        if countItem(confirmedId) <= 0 then
                            hasEmptyTargetWithoutItem = true
                            report(("PUT TUNDA (%d,%d): item LOCKED habis"):format(
                                p.x, p.y
                            ))
                        else
                            local placed, putMessage = putOne(
                                p.x, p.y, confirmedId
                            )

                            if placed then
                                breakQueue[#breakQueue + 1] = p
                                report(("SIKLUS %d | PUT %d/%d OK (%d,%d)"):format(
                                    cycle, index, #plan, p.x, p.y
                                ))
                            else
                                local checkFg = tileAt("fg", p.x, p.y)
                                local checkBg = tileAt("bg", p.x, p.y)

                                if checkFg ~= nil and checkBg ~= nil
                                    and (checkFg ~= 0 or checkBg ~= 0) then
                                    breakQueue[#breakQueue + 1] = p
                                    report(("PUT TIDAK TERKONFIRMASI, TILE TERISI (%d,%d)"):format(
                                        p.x, p.y
                                    ))
                                else
                                    report(("PUT GAGAL (%d,%d): %s"):format(
                                        p.x, p.y, tostring(putMessage)
                                    ))
                                end
                            end
                        end
                    end

                    if putMs > 0 then task.wait(putMs / 1000) end
                end

                if not running or destroyed or Hub.IsClosing() then break end

                if #breakQueue == 0 then
                    running = false
                    if hasEmptyTargetWithoutItem then
                        report("STOP: tile kosong menunggu PUT, tetapi item LOCKED habis.")
                    else
                        report("STOP: tidak ada tile berisi yang perlu di-BREAK dan tidak ada PUT berhasil.")
                    end
                    break
                end

                report(("SIKLUS %d | FASE BREAK: %d tile"):format(
                    cycle, #breakQueue
                ))

                for index, p in ipairs(breakQueue) do
                    if not running or destroyed or Hub.IsClosing() then break end

                    local cx, cy = playerTile()
                    if not cx or cx ~= px or cy ~= py then
                        running = false
                        report("STOP AMAN: posisi player berubah dari anchor.")
                        break
                    end

                    local broken, breakMessage = breakOne(
                        p.x, p.y, startMs, hitMs
                    )

                    report(("SIKLUS %d | BREAK %d/%d %s (%d,%d): %s"):format(
                        cycle, index, #breakQueue,
                        broken and "OK" or "GAGAL",
                        p.x, p.y, tostring(breakMessage)
                    ))

                    if not broken then
                        running = false
                        break
                    end
                end

                if running and not destroyed and not Hub.IsClosing() then
                    report(("SIKLUS %d | FASE COLLECT: TILE 7, 8, 9"):format(cycle))
                    local collected, collectMessage = collectPhase(plan, px, py)
                    if not collected then
                        running = false
                        report(("STOP AMAN | COLLECT BELUM TUNTAS: %s"):format(tostring(collectMessage)))
                        break
                    end
                    report(("SIKLUS %d | COLLECT SELESAI: %s"):format(cycle, tostring(collectMessage)))
                end

                if running and cycleMs > 0 then
                    task.wait(cycleMs / 1000)
                end
            end

            running = false
            if not destroyed then report("LOOP BERHENTI.") end
        end)
    end))

    --==================================================
    -- [M] INITIAL SCAN + INVENTORY DISPLAY
    --==================================================

    task.spawn(function()
        task.wait(0.5)
        if destroyed or Hub.IsClosing() then return end

        -- Protect the scan task so an unexpected error is shown in Status,
        -- instead of leaving the UI permanently at "menyiapkan scan...".
        local callOk, scanOk, message = pcall(discover)

        if destroyed or Hub.IsClosing() then return end

        if not callOk then
            report("ERROR SAAT SCAN: " .. tostring(scanOk))
            selectedLabel.Text = "Inventory selected: scan error"
            return
        end

        report(scanOk and message or ("SCAN GAGAL: " .. tostring(message)))

        if refs.Inv then
            local id = selectedId()
            selectedLabel.Text = id
                and ("Inventory selected: ID %d | jumlah: %d"):format(
                    id, countItem(id)
                )
                or "Inventory selected: tidak ada"
        else
            selectedLabel.Text = "Inventory selected: tidak ditemukan"
        end
    end)

    task.spawn(function()
        while not destroyed and not Hub.IsClosing() and page.Parent do
            if refs.Inv then
                if not confirmedId then
                    local id = selectedId()
                    selectedLabel.Text = id
                        and ("Inventory selected: ID %d | jumlah: %d"):format(
                            id, countItem(id)
                        )
                        or "Inventory selected: tidak ada"
                else
                    local current = selectedId()
                    selectedLabel.Text = (
                        "LOCKED ID: %d | jumlah: %d%s"
                    ):format(
                        confirmedId,
                        countItem(confirmedId),
                        current ~= confirmedId
                            and (" | SELECTED BERUBAH: " .. tostring(current))
                            or ""
                    )

                    if countItem(confirmedId) <= 0 and running then
                        running = false
                        report("STOP: item LOCKED habis.")
                    end
                end
            end
            task.wait(0.25)
        end
    end)

    --==================================================
    -- [N] CLEANUP
    --==================================================

    local function cleanup()
        if destroyed then return end

        destroyed = true
        running = false
        closePopup()

        for _, connection in ipairs(connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        table.clear(connections)
    end

    Hub.RegisterCleanup(cleanup)
    print("[APB+COLLECT] PUT + BREAK + COLLECT submenu loaded.")

    end)

end -- return function(Hub)

--==================================================
-- END MODULE: AUTO PUT + BREAK + COLLECT
--==================================================
