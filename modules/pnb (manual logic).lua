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
            PutDelay = 85,
            BreakDelay = 155,
            BreakStartDelay = 100,
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

        statusLabel = makeLabel("Status: idle | menunggu perintah", 34)
        statusLabel.LayoutOrder = 1

        selectedLabel = makeLabel("Inventory: tekan MANUAL SCAN INVENTORY", 28)
        selectedLabel.LayoutOrder = 2

        local areaLabel = makeLabel(
            "TARGET TILE: 7, 8, 9 | default ON",
            24
        )
        areaLabel.LayoutOrder = 3

        tileButton = makeButton("SELECT TILE: 7 ON | 8 ON | 9 ON", 34, page, Theme.PanelDark)
        tileButton.TextColor3 = Theme.Text
        tileButton.LayoutOrder = 4

        local scanButton = makeButton(
            "MANUAL SCAN INVENTORY", 32, page, Theme.PanelDark
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
            "START LOOP", 36, page, Theme.Green
        )
        startButton.LayoutOrder = 8

        local stopButton = makeButton("STOP LOOP", 32, page, Theme.Red)
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
            "Jeda awal BREAK TILE (ms)", CFG.BreakStartDelay, settingsFrame
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

        local function updateTileButton()
            local parts = {}
            for _, tileNo in ipairs({7, 8, 9}) do
                local dx = tileNo - 8
                local key = tostring(dx) .. ",-1"
                parts[#parts + 1] = tostring(tileNo) .. (enabled[key] and " ON" or " OFF")
            end
            tileButton.Text = "SELECT TILE: " .. table.concat(parts, " | ")
        end

        local function openTilePopup()
            closePopup()
            popup = create("Frame", {
                Name = "TileSelectPopup",
                Size = UDim2.new(1, -12, 0, 150),
                Position = UDim2.new(0, 6, 0, 6),
                BackgroundColor3 = Theme.Background,
                BorderSizePixel = 0,
                ZIndex = 20,
            }, page)
            corner(popup, 8)

            create("TextLabel", {
                Size = UDim2.new(1, -12, 0, 28),
                Position = UDim2.new(0, 6, 0, 4),
                BackgroundTransparency = 1,
                Text = "PILIH TILE TARGET",
                TextColor3 = Theme.Text,
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                ZIndex = 21,
            }, popup)

            for index, tileNo in ipairs({7, 8, 9}) do
                local dx = tileNo - 8
                local key = tostring(dx) .. ",-1"
                local b = makeButton("", 28, popup, enabled[key] and Theme.Green or Theme.PanelDark)
                b.Position = UDim2.new(0, 8, 0, 34 + (index - 1) * 32)
                b.Size = UDim2.new(1, -16, 0, 28)
                b.ZIndex = 21
                b.Text = "TILE " .. tileNo .. (enabled[key] and " : ON" or " : OFF")
                b.TextColor3 = enabled[key] and Theme.White or Theme.Text
                track(b.Activated:Connect(function()
                    enabled[key] = not enabled[key]
                    b.BackgroundColor3 = enabled[key] and Theme.Green or Theme.PanelDark
                    b.TextColor3 = enabled[key] and Theme.White or Theme.Text
                    b.Text = "TILE " .. tileNo .. (enabled[key] and " : ON" or " : OFF")
                    updateTileButton()
                end))
            end

            local done = makeButton("SELESAI", 26, popup, Theme.Accent)
            done.Position = UDim2.new(0, 8, 1, -30)
            done.Size = UDim2.new(1, -16, 0, 24)
            done.ZIndex = 21
            track(done.Activated:Connect(closePopup))
        end

        updateTileButton()
        track(tileButton.Activated:Connect(openTilePopup))

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
            for dx = -1, 1 do
                local key = tostring(dx) .. ",-1"
                if enabled[key] then
                    local x, y = px + dx, py - 1
                    if x < 0 or y < 0 or x >= refs.World.w or y >= refs.World.h then
                        return nil, ("Koordinat tile %d di luar world."):format(dx + 8)
                    end
                    plan[#plan + 1] = {
                        x = x, y = y, dx = dx, dy = -1, tileNo = dx + 8
                    }
                end
            end

            if #plan == 0 then
                return nil, "Tidak ada tile yang diaktifkan."
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

            for _ = 1, 5 do
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

-- LANGSUNG AMBIL SESUAI JUMLAH DROP.
-- Tidak melakukan pengecekan kapasitas inventory.
local amount = tonumber(drop.n) or 0

if amount <= 0 then
    return false, "drop kosong"
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

        local function collectTargetParallel(target, anchorX, anchorY)
            while running and not destroyed and not Hub.IsClosing() do
                local currentX, currentY = playerTile()
                if not currentX or currentX ~= anchorX or currentY ~= anchorY then
                    return false, "posisi player berubah dari anchor"
                end

                local found = dropsAtTarget(target)
                if #found > 0 then
                    -- Semua drop yang terlihat pada tile ini diproses bersamaan.
                    for _, drop in ipairs(found) do
                        task.spawn(function()
                            if running and not destroyed and not Hub.IsClosing() then
                                local ok, message = takeDrop(drop)
                                if not ok and (drop.n or 0) > 0 then
                                    report(("COLLECT TILE %d UID %s: %s"):format(
                                        target.tileNo, tostring(drop.uid), tostring(message)
                                    ))
                                end
                            end
                        end)
                    end
                    task.wait(0.1)
                else
                    -- Validasi dua kali, masing-masing berjarak 0,1 detik.
                    task.wait(0.2)
                    if #dropsAtTarget(target) == 0 then
                        task.wait(0.2)
                        if #dropsAtTarget(target) == 0 then
                            return true, "drop tile sudah diambil (validasi 2x)"
                        end
                    end
                end
            end
            return false, "collect dihentikan"
        end

        local function collectPhaseParallel(plan, anchorX, anchorY)
            if not Drops.list and not findDropRefs() then
                return false, "daftar drop tidak ditemukan"
            end

            local remaining = #plan
            local results = {}

            -- Worker semua tile dimulai bersamaan, bukan tile 7 lalu 8 lalu 9.
            for index, target in ipairs(plan) do
                task.spawn(function()
                    report(("COLLECT TILE %d DIMULAI (PARALEL)"):format(target.tileNo))
                    local callOk, ok, message = pcall(
                        collectTargetParallel, target, anchorX, anchorY
                    )
                    if not callOk then
                        results[index] = {
                            ok = false, message = ok, tileNo = target.tileNo
                        }
                    else
                        results[index] = {
                            ok = ok, message = message, tileNo = target.tileNo
                        }
                    end
                    remaining -= 1
                end)
            end

            while remaining > 0 and running and not destroyed and not Hub.IsClosing() do
                task.wait(0.05)
            end

            if not running or destroyed or Hub.IsClosing() then
                return false, "collect dihentikan"
            end

            for _, result in ipairs(results) do
                if not result or not result.ok then
                    return false, ("tile %s gagal: %s"):format(
                        tostring(result and result.tileNo or "?"),
                        tostring(result and result.message or "worker tidak selesai")
                    )
                end
            end
            return true, "semua tile aktif selesai collect paralel"
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
        -- [L] BUTTON EVENTS + MAIN LOOP
        --==================================================

        track(scanButton.Activated:Connect(function()
            if running then
                report("STOP LOOP SEBELUM MANUAL SCAN INVENTORY.")
                return
            end
            if confirmedId then
                report("ID SUDAH DI-LOCK. SCAN INVENTORY TIDAK BERJALAN LAGI.")
                return
            end

            selectedLabel.Text = "Inventory: manual scan sedang berjalan..."
            report("MANUAL SCAN INVENTORY...")
            task.spawn(function()
                local ok, message = discover()
                if destroyed or Hub.IsClosing() then return end
                report(ok and message or ("SCAN GAGAL: " .. tostring(message)))

                if refs.Inv then
                    local id = selectedId()
                    selectedLabel.Text = id
                        and ("SELECTED ID: %d | JUMLAH: %d"):format(id, countItem(id))
                        or "SELECTED INVENTORY: TIDAK ADA ITEM"
                else
                    selectedLabel.Text = "INVENTORY TIDAK DITEMUKAN"
                end
            end)
        end))

        track(lockButton.Activated:Connect(function()
            if not refs.Inv then
                report("TEKAN MANUAL SCAN INVENTORY TERLEBIH DAHULU.")
                return
            end

            local id = selectedId()
            if not id then
                report("TIDAK ADA ITEM SELECTED UNTUK DI-LOCK.")
                return
            end
            if countItem(id) <= 0 then
                report("SELECTED ID " .. id .. " TIDAK MEMILIKI ITEM.")
                return
            end

            confirmedId = id
            selectedLabel.Text = ("LOCKED ID: %d"):format(id)
            report("ID ITEM TERKUNCI: " .. id .. " | MONITOR SELECTED DIHENTIKAN.")
        end))

        track(previewButton.Activated:Connect(function()
            if not refs.World or not refs.State then
                report("WORLD/STATE BELUM SIAP. LAKUKAN MANUAL SCAN.")
                return
            end
            local plan, px, py = buildPlan()
            if not plan then
                report("PREVIEW GAGAL: " .. tostring(px))
                return
            end
            local coords = {}
            for _, target in ipairs(plan) do
                coords[#coords + 1] = ("%d:(%d,%d)"):format(
                    target.tileNo, target.x, target.y
                )
            end
            report(("ANCHOR %d,%d | TARGET AKTIF %d | %s"):format(
                px, py, #plan, table.concat(coords, " ")
            ))
        end))

        track(stopButton.Activated:Connect(function()
            running = false
            report("STOP LOOP DIMINTA.")
        end))

        --==================================================
        -- [L1] PNB MAIN AUTOMATION FUNCTION
        -- Pemanggilan tunggal: PNB["PNB-UNTIL INVENTORY EMPTY"](...)
        -- Isi dan urutan proses farming dipertahankan.
        --==================================================

        local PNB = {}

        PNB["PNB-UNTIL INVENTORY EMPTY"] = function(
            plan, px, py, targetId, putMs, hitMs, startMs
        )
            local function stillRunning()
                return running and not destroyed and not Hub.IsClosing()
            end

            local function breakUntilClear(target, phaseName)
                while stillRunning() do
                    local broken, message = breakOne(
                        target.x, target.y, startMs, hitMs
                    )
                    report(("%s BREAK TILE %d: %s | %s"):format(
                        phaseName, target.tileNo,
                        broken and "OK" or "BELUM BERHASIL",
                        tostring(message)
                    ))
                    if broken then return true end
                    task.wait(0.05)
                end
                return false
            end

            report(("START | ID LOCKED %d | %d TILE AKTIF | ANCHOR %d,%d"):format(
                targetId, #plan, px, py
            ))

            -- FASE AWAL: hanya sekali ketika START ditekan.
            report("FASE AWAL: SCAN PLACED BLOCK FG/BG.")
            local occupied = {}
            for _, target in ipairs(plan) do
                local fg = tileAt("fg", target.x, target.y)
                local bg = tileAt("bg", target.x, target.y)
                if fg == nil or bg == nil then
                    running = false
                    report(("STOP: TILE %d TIDAK VALID."):format(target.tileNo))
                    break
                elseif fg ~= 0 or bg ~= 0 then
                    occupied[#occupied + 1] = target
                end
            end

            if stillRunning() then
                for _, target in ipairs(occupied) do
                    if not stillRunning() then break end
                    if not breakUntilClear(target, "AWAL") then break end
                end
            end

            if stillRunning() then
                if #occupied > 0 then
                    report("COLLECT DROP HASIL BREAK AWAL SECARA PARALEL.")
                    local collected, collectMessage = collectPhaseParallel(plan, px, py)
                    if not collected then
                        running = false
                        report("STOP: COLLECT AWAL GAGAL: " .. tostring(collectMessage))
                    end
                else
                    report("TILE AWAL KOSONG. LANGSUNG KE PUT.")
                end
            end

            -- LOOP UTAMA: PUT -> BREAK -> COLLECT.
            -- Jika inventory habis saat fase PUT, tetap coba PUT semua tile,
            -- lanjut BREAK semua tile, lalu berhenti tanpa COLLECT/loop berikutnya.
            local cycle = 0
            while stillRunning() do
                cycle += 1
                report(("LOOP %d | FASE PUT"):format(cycle))
                local inventoryEmpty = false

                for _, target in ipairs(plan) do
                    if not stillRunning() then break end

                    local placed, putMessage = putOne(
                        target.x, target.y, targetId
                    )

                    -- Cek jumlah inventory setelah SETIAP percobaan PUT,
                    -- terlepas dari PUT berhasil atau ditolak.
                    if countItem(targetId) <= 0 then
                        inventoryEmpty = true
                        report(("INVENTORY ID %d HABIS SETELAH PUT TILE %d."):format(
                            targetId, target.tileNo
                        ))
                    end

                    if placed then
                        report(("LOOP %d | PUT TILE %d OK"):format(cycle, target.tileNo))
                    else
                        report(("LOOP %d | PUT TILE %d DICOBA (GAGAL/DITOLAK): %s"):format(
                            cycle, target.tileNo, tostring(putMessage)
                        ))
                    end

                    if placed and putMs > 0 then
                        task.wait(putMs / 1000)
                    end
                end

                if not stillRunning() then break end

                report(("LOOP %d | FASE BREAK SEMUA TILE AKTIF"):format(cycle))
                for _, target in ipairs(plan) do
                    if not stillRunning() then break end
                    if not breakUntilClear(target, "LOOP") then break end
                end

                if not stillRunning() then break end

                -- COLLECT selalu dijalankan setelah BREAK, termasuk saat
                -- inventory target sudah habis. Fungsi ini mencakup validasi.
                report(("LOOP %d | FASE COLLECT PARALEL"):format(cycle))
                local collected, collectMessage = collectPhaseParallel(plan, px, py)
                if not collected then
                    running = false
                    report("STOP: COLLECT BELUM TUNTAS: " .. tostring(collectMessage))
                    break
                end
                report(("LOOP %d | COLLECT SELESAI: %s"):format(
                    cycle, tostring(collectMessage)
                ))

                -- Jika inventory habis saat PUT, berhenti SETELAH seluruh
                -- COLLECT dan validasinya selesai. Jangan mulai loop berikutnya.
                if inventoryEmpty then
                    running = false
                    report("LOOP BERHENTI: INVENTORY ID LOCKED HABIS. PUT, BREAK, COLLECT, DAN VALIDASI SELESAI.")
                    break
                end
            end

            running = false
            if not destroyed then report("LOOP BERHENTI.") end
        end

        track(startButton.Activated:Connect(function()
            if running then return end
            if not (refs.Inv and refs.World and refs.State and refs.SetTile and refs.Hit) then
                report("REFERENSI BELUM LENGKAP. TEKAN MANUAL SCAN INVENTORY.")
                return
            end
            if not confirmedId then
                report("PILIH ITEM DI INVENTORY, MANUAL SCAN, LALU LOCK SELECTED.")
                return
            end

            local putMs, e1 = readDelay(putDelayBox, 0, 10000)
            local hitMs, e2 = readDelay(breakDelayBox, 1, 10000)
            local startMs, e3 = readDelay(breakStartBox, 0, 10000)
            if not putMs then report(e1) return end
            if not hitMs then report(e2) return end
            if not startMs then report(e3) return end

            local plan, px, py = buildPlan()
            if not plan then
                report("START DIBATALKAN: " .. tostring(px))
                return
            end
            if not findDropRefs() then
                report("START DIBATALKAN: DAFTAR DROP TIDAK DITEMUKAN.")
                return
            end

            closePopup()
            running = true
            local targetId = confirmedId

            task.spawn(
                PNB["PNB-UNTIL INVENTORY EMPTY"],
                plan, px, py, targetId, putMs, hitMs, startMs
            )
        end))

        -- Monitor hanya selected item sebelum ID dikunci.
        -- Tidak ada discover/scan otomatis dan monitor berhenti setelah LOCK.
        task.spawn(function()
            while not destroyed and not Hub.IsClosing() and page.Parent do
                if not confirmedId and refs.Inv then
                    local id = selectedId()
                    selectedLabel.Text = id
                        and ("SELECTED ID: %d | JUMLAH: %d"):format(id, countItem(id))
                        or "SELECTED INVENTORY: TIDAK ADA ITEM"
                end
                if confirmedId then break end
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
