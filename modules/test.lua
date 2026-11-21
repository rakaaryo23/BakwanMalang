--==================================================
-- MAIN MODULE: MODUL FUNGSI UTAMA
-- Satu Hub.RegisterTab yang berisi dua panel/submodule:
-- 1) PUT + BREAK + COLLECT
-- 2) MOVEMENT
-- Semua penanda struktur di bawah ini adalah komentar saja.
--==================================================

return function(Hub)

    Hub.RegisterTab("MODUL FUNGSI UTAMA", function(page)
 
        --==================================================
        -- MAIN HUB TAB / ROOT CONTAINER
        -- Ini adalah satu-satunya Hub.RegisterTab pada file ini.
        -- Panel PNB dan Movement di bawahnya bukan Hub tab terpisah.
        --==================================================

        --==================================================
        -- [01] SHARED CONFIGURATION & STATE (PNB + MOVEMENT)
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
        local moveCleanup -- diisi oleh submenu MOVEMENT di bagian bawah.
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
        -- [02] SHARED UI HELPERS
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
        -- [03] SUBMODULE 1: PUT + BREAK + COLLECT | UI
        -- UI saja yang diatur ulang. Referensi tombol dan TextBox
        -- tetap dipakai oleh event serta logic automation di bawah.
        --==================================================

        local list = create("UIListLayout", {
            Padding = UDim.new(0, 7),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, page)

        -- Tombol judul menjadi satu-satunya kontrol buka/tutup.
        local mainToggle = makeButton(
            "PUT + BREAK + COLLECT - SAMPAI INVEN HABIS  ▼", 36, page, Theme.PanelDark
        )
        mainToggle.TextColor3 = Theme.Text
        mainToggle.LayoutOrder = 1
        mainToggle.TextSize = 11

        -- Semua isi submenu berada di dalam panel ini.
        local mainPanel = create("Frame", {
            Name = "PutBreakInventoryPanel",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            Visible = false,
            LayoutOrder = 2,
        }, page)
        corner(mainPanel, 8)

        create("UIPadding", {
            PaddingTop = UDim.new(0, 8),
            PaddingBottom = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 8),
            PaddingRight = UDim.new(0, 8),
        }, mainPanel)

        create("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, mainPanel)

        statusLabel = makeLabel(
            "Status: idle | menunggu perintah", 34, mainPanel
        )
        statusLabel.LayoutOrder = 1

        selectedLabel = makeLabel(
            "Inventory: tekan MANUAL SCAN INVENTORY", 28, mainPanel
        )
        selectedLabel.LayoutOrder = 2

        local areaLabel = makeLabel(
            "TARGET TILE: 7, 8, 9 | default ON", 24, mainPanel
        )
        areaLabel.LayoutOrder = 3

        -- Dua baris tombol memakai tinggi yang sama.
        -- Tinggi dibuat cukup untuk teks panjang pada baris pertama.
        local buttonRowHeight = 58
        local buttonGap = 6

        local rowOne = create("Frame", {
            Name = "PrimaryButtonRow",
            Size = UDim2.new(1, 0, 0, buttonRowHeight),
            BackgroundTransparency = 1,
            LayoutOrder = 4,
        }, mainPanel)

        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, buttonGap),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, rowOne)

        local rowTwo = create("Frame", {
            Name = "SecondaryButtonRow",
            Size = UDim2.new(1, 0, 0, buttonRowHeight),
            BackgroundTransparency = 1,
            LayoutOrder = 5,
        }, mainPanel)

        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, buttonGap),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, rowTwo)

        local function makeRowButton(text, parent, color, order)
            local b = makeButton(text, buttonRowHeight, parent, color)
            b.Size = UDim2.new(1 / 3, -4, 1, 0)
            b.TextSize = 9
            b.TextWrapped = true
            b.LayoutOrder = order
            return b
        end

        tileButton = makeRowButton(
            "SELECT TILE: 7 ON | 8 ON | 9 ON",
            rowOne, Theme.PanelDark, 1
        )
        tileButton.TextColor3 = Theme.Text

        local scanButton = makeRowButton(
            "MANUAL SCAN INVENTORY",
            rowOne, Theme.PanelDark, 2
        )
        scanButton.TextColor3 = Theme.Text

        local lockButton = makeRowButton(
            "LOCK SELECTED",
            rowOne, Theme.PanelDark, 3
        )
        lockButton.TextColor3 = Theme.Text

        local previewButton = makeRowButton(
            "PREVIEW TARGET",
            rowTwo, Theme.PanelDark, 1
        )
        previewButton.TextColor3 = Theme.Text

        local startButton = makeRowButton(
            "START LOOP",
            rowTwo, Theme.Green, 2
        )

        local stopButton = makeRowButton(
            "STOP LOOP",
            rowTwo, Theme.Red, 3
        )

        -- Panel delay langsung terlihat saat panel utama dibuka.
        local settingsFrame = create("Frame", {
            Name = "DelaySettings",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.PanelDark,
            BorderSizePixel = 0,
            Visible = true,
            LayoutOrder = 6,
        }, mainPanel)
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

        track(mainToggle.Activated:Connect(function()
            mainPanel.Visible = not mainPanel.Visible
            mainToggle.Text = mainPanel.Visible
                and "PUT AND BREAK - INVENTORY HABIS  ▲"
                or "PUT AND BREAK - INVENTORY HABIS  ▼"
        end))

        --==================================================
        --==================================================
        -- SUBMODULE 1: PUT + BREAK + COLLECT
        -- UI panel PNB + seluruh logic farming sampai cleanup [14].
        --==================================================
        -- [04] SUBMODULE 1: PUT + BREAK + COLLECT | TARGET TILE + POPUP UI
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
                Position = UDim2.new(0, 0, 1, 4),
                BackgroundColor3 = Theme.Background,
                BorderSizePixel = 0,
                ZIndex = 20,
            }, tileButton)
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
        -- [05] SUBMODULE 1: PUT + BREAK + COLLECT | DISCOVERY
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
        -- [06] SUBMODULE 1: PUT + BREAK + COLLECT | INVENTORY / WORLD HELPERS
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
        -- [07] SUBMODULE 1: PUT + BREAK + COLLECT | BUILD PLAN
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
        -- [08] SUBMODULE 1: PUT + BREAK + COLLECT | PUT LOGIC
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
        -- [09] SUBMODULE 1: PUT + BREAK + COLLECT | BREAK LOGIC
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
        -- [10] SUBMODULE 1: PUT + BREAK + COLLECT | AUTO COLLECT
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
        -- [11] SUBMODULE 1: PUT + BREAK + COLLECT | DELAY VALIDATION
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
        -- [12] SUBMODULE 1: PUT + BREAK + COLLECT | BUTTON EVENTS
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
        -- [13] SUBMODULE 1: PUT + BREAK + COLLECT | MAIN AUTOMATION FUNCTION
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
        -- [14] SUBMODULE 1: PUT + BREAK + COLLECT | CLEANUP
        --==================================================

        local function cleanup()
            if destroyed then return end

            destroyed = true
            running = false
            closePopup()

            if moveCleanup then
                pcall(moveCleanup)
            end

            for _, connection in ipairs(connections) do
                pcall(function()
                    connection:Disconnect()
                end)
            end
            table.clear(connections)
        end

        Hub.RegisterCleanup(cleanup)
        print("[APB+COLLECT] PUT + BREAK + COLLECT submenu loaded.")


        --==================================================
        --==================================================
        -- SUBMODULE 2: MOVEMENT
        -- Logic scan/state/hook/input, UI panel, reconnect, watchdog.
        --==================================================
        -- [15] SUBMODULE 2: MOVEMENT | CONTROLLER
        -- Diintegrasikan sebagai submenu kedua setelah PUT + BREAK + COLLECT.
        -- Logic scan, state reader, hook, virtual input, dan reconnect manual
        -- mengikuti script standalone MOVEMENT yang diberikan.
        --==================================================

        local moveENV = (type(getgenv) == "function" and getgenv()) or _G
        if type(moveENV.GB_MOVEMENT_STOP) == "function" then
            pcall(moveENV.GB_MOVEMENT_STOP)
        end

        local UIS = game:GetService("UserInputService")
        local moveRunning = true
        local moveScanning = false
        local moveConnected = false
        local moveScanCount = 0
        local moveLastError = "Belum melakukan scan"

        local moveRefs = {
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

        local moveInput = {
            left = false,
            right = false,
            jump = false,
            down = false,
        }

        local moveButtons = {}
        local moveHeld = { left = {}, right = {}, jump = {}, down = {} }
        local moveConnections = {}
        local moveStatusLabel

        local function moveTrack(connection)
            table.insert(moveConnections, connection)
            return connection
        end

        local function moveLog(...)
            print("[GB AUTO MOVEMENT]", ...)
        end

        local function moveSetStatus(message)
            moveLastError = tostring(message or "-")
            if moveStatusLabel and moveStatusLabel.Parent then
                local player = moveRefs.player or Players.LocalPlayer
                local account = player and player.Name or "belum tersedia"
                local worldText = moveRefs.world
                    and (tostring(moveRefs.world.w) .. "x" .. tostring(moveRefs.world.h))
                    or "belum"
                local stateText = "belum"
                if moveRefs.state then
                    stateText = string.format(
                        "X %.2f | Y %.2f | VX %.2f | VY %.2f",
                        moveRefs.state.x or 0,
                        moveRefs.state.y or 0,
                        moveRefs.state.vx or 0,
                        moveRefs.state.vy or 0
                    )
                end
                moveStatusLabel.Text = string.format(
                    "AKUN: %s\nWORLD: %s | STATE: %s\nMOVEMENT: %s\nSCAN: %d | %s",
                    tostring(account),
                    tostring(worldText),
                    tostring(stateText),
                    moveConnected and "TERHUBUNG" or "MENCARI / TERPUTUS",
                    moveScanCount,
                    moveLastError
                )
            end
        end

        local function moveSafeRaw(t, key)
            if type(t) ~= "table" then return nil end
            local ok, value = pcall(rawget, t, key)
            if ok then return value end
            return nil
        end

        local function moveReadPlayerState(fn)
            if type(fn) ~= "function" then return nil end
            local ok, value = pcall(fn)
            if not ok or type(value) ~= "table" then return nil end
            if type(value.x) ~= "number" or type(value.y) ~= "number" then return nil end
            if value.facing == nil or value.vx == nil then return nil end
            if value.active == false then return nil end
            return value
        end

        local function moveValidWorld(t)
            return type(t) == "table"
                and type(moveSafeRaw(t, "fg")) == "table"
                and type(moveSafeRaw(t, "bg")) == "table"
                and type(moveSafeRaw(t, "w")) == "number"
                and type(moveSafeRaw(t, "h")) == "number"
                and moveSafeRaw(t, "spawn") ~= nil
        end

        local function moveValidKeys(keys)
            if type(keys) ~= "table" then return false end
            local jump = moveSafeRaw(keys, 2)
            local left = moveSafeRaw(keys, 3)
            local right = moveSafeRaw(keys, 4)
            local down = moveSafeRaw(keys, 5)
            return type(jump) == "table" and jump[1] == "keyJump"
                and type(left) == "table" and left[1] == "keyLeft"
                and type(right) == "table" and right[1] == "keyRight"
                and type(down) == "table" and down[1] == "keyDown"
        end

        local function moveValidMovementTable(t)
            if type(t) ~= "table" then return false end
            local isDown = moveSafeRaw(t, "isDown")
            local spaceJumps = moveSafeRaw(t, "spaceJumps")
            local keys = moveSafeRaw(t, "KEYS")
            return type(isDown) == "function"
                and type(spaceJumps) == "function"
                and moveValidKeys(keys)
        end

        local function moveGetGC()
            if type(getgc) ~= "function" then
                return nil, "Executor tidak menyediakan getgc"
            end
            local ok, objects = pcall(getgc, true)
            if not ok or type(objects) ~= "table" then
                return nil, "getgc(true) gagal: " .. tostring(objects)
            end
            return objects
        end

        -- Scan ulang dari awal: world, player state, dan movement table.
        local function moveScanFromZero()
            moveScanCount += 1
            local objects, gcError = moveGetGC()
            if not objects then return false, gcError end

            local foundWorld, foundStateFn, foundState, foundMovement

            for _, object in ipairs(objects) do
                if type(object) == "table" then
                    if not foundWorld and moveValidWorld(object) then
                        foundWorld = object
                    end

                    if not foundStateFn then
                        local candidateState = moveSafeRaw(object, "state")
                        local stateValue = moveReadPlayerState(candidateState)
                        if stateValue then
                            foundStateFn = candidateState
                            foundState = stateValue
                        end
                    end

                    if not foundMovement and moveValidMovementTable(object) then
                        foundMovement = object
                    end

                    if foundWorld and foundStateFn and foundMovement then
                        break
                    end
                end
            end

            if foundWorld then moveRefs.world = foundWorld end
            if foundStateFn then
                moveRefs.stateFn = foundStateFn
                moveRefs.state = foundState
            end

            if foundMovement then
                moveRefs.movement = foundMovement
                moveRefs.originalIsDown = moveSafeRaw(foundMovement, "isDown")
                moveRefs.keys = moveSafeRaw(foundMovement, "KEYS")
                moveRefs.source = "DIRECT TABLE (isDown + spaceJumps + KEYS)"
            end

            if not foundWorld then
                moveLog("WORLD BELUM DITEMUKAN")
            else
                moveLog("WORLD OK", foundWorld.w, foundWorld.h)
            end

            if not foundStateFn then
                moveLog("PLAYER STATE BELUM DITEMUKAN")
            else
                moveLog("PLAYER STATE OK", foundState.x, foundState.y, foundState.vx)
            end

            if not foundMovement then
                moveLog("MOVEMENT TABLE BELUM DITEMUKAN PADA SCAN INI")
            else
                moveLog("MOVEMENT SOURCE:", moveRefs.source)
                moveLog("isDown:", tostring(moveSafeRaw(foundMovement, "isDown")))
                moveLog("spaceJumps:", tostring(moveSafeRaw(foundMovement, "spaceJumps")))
                moveLog("KEYS:", tostring(moveRefs.keys))
            end

            return foundWorld ~= nil and foundStateFn ~= nil and foundMovement ~= nil,
                "world=" .. tostring(foundWorld ~= nil)
                .. ", state=" .. tostring(foundStateFn ~= nil)
                .. ", movement=" .. tostring(foundMovement ~= nil)
        end

        local function moveReleaseAll()
            for key in pairs(moveInput) do
                moveInput[key] = false
                moveHeld[key] = {}
                local button = moveButtons[key]
                if button and button.Parent then
                    button.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
                end
            end
        end

        local function moveAnyVirtualInput()
            return moveInput.left or moveInput.right
                or moveInput.jump or moveInput.down
        end

        local function moveBuildWrapper(original)
            return function(saved, key, ...)
                -- Fungsi asli selalu dipanggil agar keyboard fisik tetap bekerja.
                local physical = false
                if type(original) == "function" then
                    local ok, result = pcall(original, saved, key, ...)
                    if ok then physical = result end
                end

                -- Input virtual digabung dengan input fisik, bukan menggantikannya.
                if key == "keyLeft" then
                    return (physical == true) or moveInput.left
                elseif key == "keyRight" then
                    return (physical == true) or moveInput.right
                elseif key == "keyJump" then
                    return (physical == true) or moveInput.jump
                elseif key == "keyDown" then
                    return (physical == true) or moveInput.down
                end

                return physical
            end
        end

        local function moveUnhookOld()
            local module = moveRefs.movement
            local original = moveRefs.originalIsDown
            local wrapper = moveRefs.wrapper
            if module and original and wrapper
                and moveSafeRaw(module, "isDown") == wrapper then
                pcall(function() module.isDown = original end)
                moveLog("HOOK LAMA DIKEMBALIKAN KE FUNGSI ASLI")
            end
            moveRefs.wrapper = nil
            moveRefs.originalIsDown = nil
            moveConnected = false
        end

        local function moveInstallHook()
            local module = moveRefs.movement
            if not moveValidMovementTable(module) then
                return false, "Movement table tidak valid"
            end

            local current = moveSafeRaw(module, "isDown")
            if moveRefs.wrapper and current == moveRefs.wrapper then
                moveConnected = true
                return true, "Hook masih aktif"
            end

            local original = current
            if type(original) ~= "function" then
                return false, "isDown bukan function"
            end

            local wrapper = moveBuildWrapper(original)
            local ok, err = pcall(function()
                module.isDown = wrapper
            end)
            if not ok or moveSafeRaw(module, "isDown") ~= wrapper then
                return false, "Gagal memasang hook: " .. tostring(err)
            end

            moveRefs.originalIsDown = original
            moveRefs.wrapper = wrapper
            moveConnected = true
            moveLog("HOOK MOVEMENT TERPASANG")
            return true, "isDown berhasil di-hook"
        end

        local function moveConnectCycle()
            if moveScanning or not moveRunning then return end
            moveScanning = true
            moveSetStatus("Scan dimulai dari objek game yang aktif...")

            local success = false
            local message = "Belum ditemukan"
            for attempt = 1, 30 do
                if not moveRunning then break end
                local ok, result = moveScanFromZero()
                message = result
                if ok then
                    local hookOK, hookMessage = moveInstallHook()
                    if hookOK then
                        success = true
                        message = hookMessage
                        break
                    end
                    message = hookMessage
                end
                moveSetStatus(
                    "Menunggu komponen game... percobaan "
                    .. attempt .. "/30 | " .. message
                )
                task.wait(0.5)
            end

            moveScanning = false
            if success then
                moveConnected = true
                moveLog("SEMUA KOMPONEN SIAP")
                moveSetStatus("CONNECTED - input fisik + virtual aktif")
            else
                moveConnected = false
                moveSetStatus("Belum tersambung: " .. tostring(message))
                warn("[GB AUTO MOVEMENT] Scan belum berhasil: " .. tostring(message))
            end
        end

        local function moveSetInput(key, value)
            if not moveRunning then return end
            moveInput[key] = value == true
            local button = moveButtons[key]
            if button and button.Parent then
                button.BackgroundColor3 = moveInput[key]
                    and Color3.fromRGB(35, 135, 90)
                    or Color3.fromRGB(45, 45, 55)
            end
        end

        -- [15A] MOVEMENT | VIRTUAL BUTTON UI HELPER
        local function moveMakeButton(parent, key, label, xScale)
            local button = create("TextButton", {
                Name = "GB_" .. key,
                Size = UDim2.new(0.24, -5, 0, 48),
                Position = UDim2.new(xScale, 0, 0, 0),
                BackgroundColor3 = Color3.fromRGB(45, 45, 55),
                BorderSizePixel = 0,
                Text = label,
                TextColor3 = Theme.White,
                TextSize = 12,
                Font = Enum.Font.GothamBold,
                AutoButtonColor = false,
                Active = true,
            }, parent)
            corner(button, 8)
            moveButtons[key] = button

            moveTrack(button.InputBegan:Connect(function(obj)
                if obj.UserInputType == Enum.UserInputType.Touch
                    or obj.UserInputType == Enum.UserInputType.MouseButton1 then
                    moveHeld[key][obj] = true
                    moveSetInput(key, true)
                end
            end))
            return button
        end

        -- [15B] MOVEMENT | EXPAND/COLLAPSE PANEL + UI LAYOUT
        -- Header MOVEMENT adalah expand/collapse baris kedua pada halaman ini.
        local moveToggle = makeButton(
            "MOVEMENT - MANUAL SCAN  ▼", 36, page, Theme.PanelDark
        )
        moveToggle.Name = "MovementExpandToggle"
        moveToggle.LayoutOrder = 3
        moveToggle.TextColor3 = Theme.Text
        moveToggle.TextSize = 11

        local movePanel = create("Frame", {
            Name = "MovementControllerPanel",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            Visible = false,
            LayoutOrder = 4,
        }, page)
        corner(movePanel, 8)

        create("UIPadding", {
            PaddingTop = UDim.new(0, 8),
            PaddingBottom = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 8),
            PaddingRight = UDim.new(0, 8),
        }, movePanel)

        create("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, movePanel)

        moveStatusLabel = create("TextLabel", {
            Name = "MovementStatus",
            Size = UDim2.new(1, 0, 0, 78),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            TextColor3 = Theme.Text,
            TextSize = 10,
            Font = Enum.Font.Code,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = 1,
        }, movePanel)
        corner(moveStatusLabel, 6)

        local moveButtonRow = create("Frame", {
            Name = "MovementInputButtons",
            Size = UDim2.new(1, 0, 0, 48),
            BackgroundTransparency = 1,
            LayoutOrder = 2,
        }, movePanel)

        moveMakeButton(moveButtonRow, "left", "KIRI", 0)
        moveMakeButton(moveButtonRow, "right", "KANAN", 0.25)
        moveMakeButton(moveButtonRow, "jump", "JUMP", 0.50)
        moveMakeButton(moveButtonRow, "down", "TURUN", 0.75)

        local moveActionRow = create("Frame", {
            Name = "MovementActions",
            Size = UDim2.new(1, 0, 0, 32),
            BackgroundTransparency = 1,
            LayoutOrder = 3,
        }, movePanel)

        local moveReconnect = makeButton(
            "SCAN / CONNECT ULANG", 30, moveActionRow, Theme.Accent
        )
        moveReconnect.Name = "MovementReconnect"
        moveReconnect.Size = UDim2.new(1, 0, 0, 30)
        moveReconnect.Position = UDim2.fromOffset(0, 0)
        moveReconnect.TextSize = 10

        -- [15C] MOVEMENT | UI EVENTS + INPUT EVENTS
        moveTrack(moveToggle.Activated:Connect(function()
            movePanel.Visible = not movePanel.Visible
            moveToggle.Text = movePanel.Visible
                and "MOVEMENT - MANUAL SCAN  ▲"
                or "MOVEMENT - MANUAL SCAN  ▼"
        end))

        moveTrack(moveReconnect.Activated:Connect(function()
            if moveConnected then
                moveUnhookOld()
            end
            moveReleaseAll()
            task.spawn(moveConnectCycle)
        end))

        -- Lepas input virtual saat jari dilepas di luar tombol.
        moveTrack(UIS.InputEnded:Connect(function(obj)
            for key, map in pairs(moveHeld) do
                if map[obj] then
                    map[obj] = nil
                    moveSetInput(key, next(map) ~= nil)
                end
            end
        end))

        pcall(function()
            moveTrack(UIS.WindowFocusReleased:Connect(moveReleaseAll))
        end)

        if LocalPlayer then
            moveTrack(LocalPlayer.CharacterAdded:Connect(function()
                moveReleaseAll()
                task.delay(1, function()
                    if moveRunning then task.spawn(moveConnectCycle) end
                end)
            end))
            moveTrack(LocalPlayer.CharacterRemoving:Connect(function()
                moveReleaseAll()
            end))
        end

        -- [15D] MOVEMENT | CLEANUP / RESTORE HOOK
        moveCleanup = function()
            if not moveRunning then return end
            moveRunning = false
            moveReleaseAll()
            moveUnhookOld()

            for _, connection in ipairs(moveConnections) do
                pcall(function()
                    connection:Disconnect()
                end)
            end
            table.clear(moveConnections)

            if moveENV.GB_MOVEMENT_STOP == moveCleanup then
                moveENV.GB_MOVEMENT_STOP = nil
            end
            moveLog("CONTROLLER DIHENTIKAN DAN HOOK DIPULIHKAN")
        end

        moveENV.GB_MOVEMENT_STOP = moveCleanup

        -- [15E] MOVEMENT | INITIAL SCAN
        -- Scan otomatis hanya sekali saat modul dimuat.
        -- Jika hook terputus setelahnya, pengguna menekan SCAN / CONNECT ULANG.
        moveSetStatus("Controller dibuat; mulai scan dari nol...")
        moveLog("MEMULAI SCAN DARI NOL")
        moveLog("ACCOUNT:", LocalPlayer and LocalPlayer.Name or "tidak tersedia")
        moveLog("USER ID:", LocalPlayer and LocalPlayer.UserId or "tidak tersedia")
        task.spawn(moveConnectCycle)

        print("[GB AUTO MOVEMENT] MOVEMENT submenu loaded.")

        --==================================================
        -- [16] SUBMODULE 3: DIRT FARM PATHFINDING
        -- Menggunakan controller MOVEMENT yang sudah ada.
        -- Tidak memasang hook isDown kedua agar tidak bentrok.
        --==================================================

        do
            local pathRunning = true
            local pathGoRunning = false
            local pathStopRequested = false
            local pathLockedTarget = nil
            local pathConnections = {}

            local function pathTrack(connection)
                pathConnections[#pathConnections + 1] = connection
                return connection
            end

            local function pathLog(...)
                print("[DIRT FARM PATHFINDING]", ...)
            end

            local pathStatusLabel
            local pathTargetLabel
            local pathPositionLabel
            local pathDirectionLabel

            local function pathSetStatus(message)
                message = tostring(message or "-")
                if pathStatusLabel and pathStatusLabel.Parent then
                    pathStatusLabel.Text = "STATUS: " .. message
                end
                pathLog(message)
            end

            local function pathSetInput(key, value)
                if not pathRunning then return end
                moveSetInput(key, value)
                if pathDirectionLabel and pathDirectionLabel.Parent then
                    local active = {}
                    for _, name in ipairs({"left", "right", "jump", "down"}) do
                        if moveInput[name] then
                            active[#active + 1] = string.upper(name)
                        end
                    end
                    pathDirectionLabel.Text = "INPUT: "
                        .. (#active > 0 and table.concat(active, " + ") or "NONE")
                end
            end

            local function pathReleaseAll()
                for _, key in ipairs({"left", "right", "jump", "down"}) do
                    pathSetInput(key, false)
                end
                if pathDirectionLabel and pathDirectionLabel.Parent then
                    pathDirectionLabel.Text = "INPUT: NONE"
                end
            end

            local function pathCurrentState()
                local state = moveReadPlayerState(moveRefs.stateFn)
                if state then moveRefs.state = state end
                return state
            end

            local function pathPlayerTileY(state)
                return math.floor(state.y - 0.475)
            end

            local function pathGetEmptyTiles(rowY)
                local world = moveRefs.world
                if not world then return nil, "World belum tersedia" end

                local fgRow = world.fg and world.fg[rowY]
                local bgRow = world.bg and world.bg[rowY]
                if type(fgRow) ~= "table" or type(bgRow) ~= "table" then
                    return nil, "Data baris Y=" .. tostring(rowY) .. " tidak terbaca"
                end

                local empty = {}
                for x = 0, world.w - 1 do
                    if fgRow[x] == 0 and bgRow[x] == 0 then
                        empty[#empty + 1] = x
                    end
                end

                if #empty == 0 then
                    return nil, "Tidak ada tile kosong FG=0 dan BG=0 pada Y="
                        .. tostring(rowY)
                end
                return empty
            end

            local function pathChooseNearestX(candidates, playerX)
                local bestX, bestDistance
                for _, x in ipairs(candidates) do
                    local distance = math.abs((x + 0.5) - playerX)
                    if bestDistance == nil or distance < bestDistance then
                        bestX, bestDistance = x, distance
                    end
                end
                return bestX
            end

            local function pathWaitStep()
                task.wait(0.04)
                if not pathRunning or pathStopRequested or not pathGoRunning then
                    return nil
                end
                return pathCurrentState()
            end

            local function pathMoveHorizontalTo(xGoal, tolerance)
                tolerance = tolerance or 0.12
                while pathGoRunning and not pathStopRequested do
                    local state = pathCurrentState()
                    if not state then return false, "PlayerState tidak terbaca" end
                    pathPositionLabel.Text = string.format(
                        "POSISI: X %.2f | Y %.2f", state.x, state.y
                    )
                    local dx = xGoal - state.x
                    if math.abs(dx) <= tolerance then
                        pathReleaseAll()
                        return true
                    end
                    if dx > 0 then
                        pathSetInput("left", false)
                        pathSetInput("right", true)
                    else
                        pathSetInput("right", false)
                        pathSetInput("left", true)
                    end
                    if not pathWaitStep() then
                        return false, "GO dihentikan atau state hilang"
                    end
                end
                return false, "GO dihentikan"
            end

            local function pathCrossOneFarmRow(direction)
                local state = pathCurrentState()
                if not state then return false, "PlayerState tidak terbaca" end

                local startRow = pathPlayerTileY(state)
                local scanRow = direction == "UP" and (startRow - 1) or (startRow + 1)
                local candidates, scanError = pathGetEmptyTiles(scanRow)
                if not candidates then return false, scanError end

                local corridorTileX
                if direction == "UP" then
                    local leftEdge, rightEdge = nil, nil
                    for _, x in ipairs(candidates) do
                        if x == 0 then leftEdge = x end
                        if x == moveRefs.world.w - 1 then rightEdge = x end
                    end

                    if leftEdge ~= nil and rightEdge ~= nil then
                        corridorTileX = pathChooseNearestX(
                            {leftEdge, rightEdge}, state.x
                        )
                    else
                        corridorTileX = leftEdge or rightEdge
                    end

                    if corridorTileX == nil then
                        return false,
                            "Tile kosong di ujung kiri/kanan tidak ditemukan pada Y="
                            .. tostring(scanRow)
                    end
                else
                    corridorTileX = pathChooseNearestX(candidates, state.x)
                end

                local corridorCenter = corridorTileX + 0.5
                pathSetStatus(string.format(
                    "SCAN %s | ROW %d | TILE KOSONG X=%d | FG=0 BG=0",
                    direction, scanRow, corridorTileX
                ))

                local reached, moveError = pathMoveHorizontalTo(corridorCenter, 0.16)
                if not reached then return false, moveError end

                local inwardKey, oppositeKey
                if direction == "UP" then
                    inwardKey = corridorTileX == 0 and "right" or "left"
                    oppositeKey = inwardKey == "left" and "right" or "left"

                    pathReleaseAll()
                    pathSetStatus(string.format(
                        "SIAP NAIK | BERHENTI DI X=%d | MENYIAPKAN LOMPAT",
                        corridorTileX
                    ))
                    task.wait(0.70)

                    pathSetInput("down", false)
                    pathSetInput(oppositeKey, false)
                    pathSetInput("jump", true)
                    task.wait(0.20)

                    pathSetStatus(string.format(
                        "JUMP + HOLD %s DARI X=%d",
                        string.upper(inwardKey), corridorTileX
                    ))
                    pathSetInput(inwardKey, true)
                    task.wait(0.50)
                else
                    pathSetStatus(string.format(
                        "TURUN | MENUNGGU JATUH DARI TILE KOSONG X=%d",
                        corridorTileX
                    ))
                    pathSetInput("jump", false)
                    pathSetInput("left", false)
                    pathSetInput("right", false)
                    pathSetInput("down", false)
                end

                if direction == "UP" then
                    pathSetInput("jump", false)
                    task.wait(0.08)
                end

                local changed = false
                local startedAt = os.clock()
                while pathGoRunning and not pathStopRequested do
                    local now = pathCurrentState()
                    if not now then
                        pathReleaseAll()
                        return false, "PlayerState hilang saat berpindah baris"
                    end

                    local nowRow = pathPlayerTileY(now)
                    pathPositionLabel.Text = string.format(
                        "POSISI: X %.2f | Y %.2f | ROW %d",
                        now.x, now.y, nowRow
                    )

                    if (direction == "UP" and nowRow < startRow)
                        or (direction == "DOWN" and nowRow > startRow) then
                        changed = true
                        break
                    end

                    if os.clock() - startedAt > 3.5 then
                        break
                    end
                    if not pathWaitStep() then break end
                end

                pathReleaseAll()
                if not changed then
                    return false,
                        "Perpindahan baris tidak terdeteksi dari Y="
                        .. tostring(startRow)
                end

                task.wait(0.12)
                local after = pathCurrentState()
                if not after then
                    return false, "PlayerState tidak terbaca setelah pindah baris"
                end
                pathSetStatus(string.format(
                    "BERHASIL PINDAH BARIS | ROW %d -> %d",
                    startRow, pathPlayerTileY(after)
                ))
                return true
            end

            local function pathMoveHorizontalStableTo(xGoal, tolerance)
                tolerance = tolerance or 0.16
                local preciseTolerance = 0.08
                local stableSince = nil
                local startedAt = os.clock()

                while pathGoRunning and not pathStopRequested do
                    local state = pathCurrentState()
                    if not state then
                        return false, "PlayerState tidak terbaca"
                    end

                    pathPositionLabel.Text = string.format(
                        "POSISI: X %.2f | Y %.2f", state.x, state.y
                    )
                    local dx = xGoal - state.x
                    local distance = math.abs(dx)

                    if distance <= preciseTolerance then
                        pathSetInput("left", false)
                        pathSetInput("right", false)

                        if not stableSince then
                            stableSince = os.clock()
                            pathSetStatus(
                                "X HAMPIR TEPAT | VERIFIKASI POSISI 0.5 DETIK"
                            )
                        elseif os.clock() - stableSince >= 0.5 then
                            pathReleaseAll()
                            return true
                        end

                    elseif distance < 3 then
                        stableSince = nil
                        local tapKey = dx > 0 and "right" or "left"
                        pathSetInput(
                            tapKey == "right" and "left" or "right", false
                        )
                        pathSetInput(tapKey, true)
                        task.wait(0.06)
                        pathSetInput(tapKey, false)
                        task.wait(0.07)
                    else
                        stableSince = nil
                        if dx > 0 then
                            pathSetInput("left", false)
                            pathSetInput("right", true)
                        else
                            pathSetInput("right", false)
                            pathSetInput("left", true)
                        end
                        if not pathWaitStep() then
                            return false,
                                "GO dihentikan saat bergerak ke X target"
                        end
                    end

                    if os.clock() - startedAt > 15 then
                        return false, "Timeout saat mengunci posisi X akhir"
                    end
                    if not pathRunning or pathStopRequested or not pathGoRunning then
                        return false, "GO dihentikan saat verifikasi X akhir"
                    end
                end

                return false, "GO dihentikan"
            end

            local function pathNavigateToLocked()
                if not pathLockedTarget then
                    pathSetStatus(
                        "BELUM ADA KOORDINAT LOCK. TEKAN LOCK COORDINAT."
                    )
                    return
                end
                if not moveConnected or not moveRefs.stateFn or not moveRefs.world then
                    pathSetStatus(
                        "MOVEMENT BELUM TERHUBUNG. SCAN / CONNECT ULANG DULU."
                    )
                    return
                end
                if pathGoRunning then return end

                pathGoRunning = true
                pathStopRequested = false
                local target = {
                    x = pathLockedTarget.x,
                    y = pathLockedTarget.y
                }
                pathSetStatus(string.format(
                    "GO DIMULAI | TARGET X %.2f Y %.2f",
                    target.x, target.y
                ))

                task.spawn(function()
                    local success, reason = pcall(function()
                        local tolerance = 0.16
                        local maxTransitions = math.max(1, moveRefs.world.h + 2)
                        local transitions = 0

                        while pathGoRunning and not pathStopRequested do
                            local state = pathCurrentState()
                            if not state then error("PlayerState tidak terbaca") end

                            pathPositionLabel.Text = string.format(
                                "POSISI: X %.2f | Y %.2f", state.x, state.y
                            )
                            local currentRow = pathPlayerTileY(state)
                            local targetRow = pathPlayerTileY(target)

                            if currentRow == targetRow then
                                local moved, moveError =
                                    pathMoveHorizontalStableTo(target.x, tolerance)
                                if not moved then error(moveError) end

                                local finalStableSince = nil
                                while pathGoRunning and not pathStopRequested do
                                    local finalState = pathCurrentState()
                                    if not finalState then
                                        error(
                                            "PlayerState tidak terbaca saat verifikasi tujuan"
                                        )
                                    end
                                    pathPositionLabel.Text = string.format(
                                        "POSISI: X %.2f | Y %.2f",
                                        finalState.x, finalState.y
                                    )
                                    local dx = math.abs(finalState.x - target.x)
                                    local dy = math.abs(finalState.y - target.y)

                                    if dx <= 0.08 and dy <= 0.12 then
                                        pathReleaseAll()
                                        if not finalStableSince then
                                            finalStableSince = os.clock()
                                            pathSetStatus(
                                                "POSISI HAMPIR TEPAT | MEMASTIKAN STABIL 0.5 DETIK"
                                            )
                                        elseif os.clock() - finalStableSince >= 0.5 then
                                            pathSetStatus(string.format(
                                                "TUJUAN TERCAPAI | X %.2f Y %.2f",
                                                finalState.x, finalState.y
                                            ))
                                            return
                                        end
                                    else
                                        finalStableSince = nil
                                        if dx > 0.08 then
                                            local ok, err =
                                                pathMoveHorizontalStableTo(
                                                    target.x, tolerance
                                                )
                                            if not ok then error(err) end
                                        end
                                    end

                                    if not pathWaitStep() then break end
                                end
                                if pathStopRequested then return end
                                error("Posisi belum mencapai koordinat LOCK")
                            end

                            transitions += 1
                            if transitions > maxTransitions then
                                error("Batas perpindahan baris terlampaui")
                            end

                            local direction =
                                targetRow < currentRow and "UP" or "DOWN"
                            local crossed, crossError =
                                pathCrossOneFarmRow(direction)
                            if not crossed then error(crossError) end
                        end
                    end)

                    pathReleaseAll()
                    pathGoRunning = false
                    pathStopRequested = false
                    if not success then
                        pathSetStatus("GO BERHENTI: " .. tostring(reason))
                    end
                end)
            end

            -- UI pathfinder berada di dalam tab utama yang sama.
            local pathToggle = makeButton(
                "DIRT FARM PATHFINDING  ▼", 36, page, Theme.PanelDark
            )
            pathToggle.Name = "DirtFarmPathfindingExpandToggle"
            pathToggle.TextColor3 = Theme.Text
            pathToggle.LayoutOrder = 5

            local pathPanel = create("Frame", {
                Name = "DirtFarmPathfindingPanel",
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.Panel,
                BorderSizePixel = 0,
                Visible = false,
                LayoutOrder = 6,
            }, page)
            corner(pathPanel, 8)

            create("UIPadding", {
                PaddingTop = UDim.new(0, 8),
                PaddingBottom = UDim.new(0, 8),
                PaddingLeft = UDim.new(0, 8),
                PaddingRight = UDim.new(0, 8),
            }, pathPanel)

            create("UIListLayout", {
                Padding = UDim.new(0, 6),
                SortOrder = Enum.SortOrder.LayoutOrder,
            }, pathPanel)

            pathStatusLabel = create("TextLabel", {
                Size = UDim2.new(1, 0, 0, 42),
                BackgroundColor3 = Theme.Background,
                BorderSizePixel = 0,
                Text = "STATUS: Menunggu Movement...",
                TextColor3 = Theme.Text,
                Font = Enum.Font.Gotham,
                TextSize = 10,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = 1,
            }, pathPanel)
            corner(pathStatusLabel, 6)

            pathTargetLabel = makeLabel(
                "TARGET LOCK: BELUM ADA", 25, pathPanel
            )
            pathTargetLabel.LayoutOrder = 2

            pathPositionLabel = makeLabel(
                "POSISI: BELUM TERBACA", 25, pathPanel
            )
            pathPositionLabel.LayoutOrder = 3

            pathDirectionLabel = makeLabel("INPUT: NONE", 22, pathPanel)
            pathDirectionLabel.LayoutOrder = 4

            local pathLockButton = makeButton(
                "LOCK COORDINAT", 38, pathPanel, Theme.Accent
            )
            pathLockButton.LayoutOrder = 5

            local pathGoButton = makeButton(
                "GO", 38, pathPanel, Theme.Green
            )
            pathGoButton.LayoutOrder = 6

            local pathStopButton = makeButton(
                "STOP", 38, pathPanel, Theme.Red
            )
            pathStopButton.LayoutOrder = 7

            local pathScanButton = makeButton(
                "SCAN / CONNECT ULANG", 32, pathPanel, Theme.PanelDark
            )
            pathScanButton.TextColor3 = Theme.Text
            pathScanButton.LayoutOrder = 8

            pathTrack(pathToggle.Activated:Connect(function()
                pathPanel.Visible = not pathPanel.Visible
                pathToggle.Text = pathPanel.Visible
                    and "DIRT FARM PATHFINDING  ▲"
                    or "DIRT FARM PATHFINDING  ▼"
            end))

            pathTrack(pathLockButton.Activated:Connect(function()
                if not moveConnected then
                    pathSetStatus("LOCK GAGAL: MOVEMENT BELUM TERHUBUNG")
                    return
                end
                local state = pathCurrentState()
                if not state then
                    pathSetStatus("LOCK GAGAL: PLAYERSTATE TIDAK TERBACA")
                    return
                end
                pathLockedTarget = { x = state.x, y = state.y }
                pathTargetLabel.Text = string.format(
                    "TARGET LOCK: X %.3f | Y %.3f",
                    pathLockedTarget.x, pathLockedTarget.y
                )
                pathSetStatus(
                    "KOORDINAT TERKUNCI. NILAI TARGET TIDAK BERUBAH SAAT PLAYER BERGERAK."
                )
            end))

            pathTrack(pathGoButton.Activated:Connect(pathNavigateToLocked))

            pathTrack(pathStopButton.Activated:Connect(function()
                pathStopRequested = true
                pathGoRunning = false
                pathReleaseAll()
                pathSetStatus(
                    "STOP DIMINTA. INPUT DILEPAS DAN LOOP STATE DIHENTIKAN."
                )
            end))

            pathTrack(pathScanButton.Activated:Connect(function()
                if pathGoRunning then
                    pathSetStatus(
                        "STOP GO TERLEBIH DAHULU SEBELUM SCAN ULANG"
                    )
                    return
                end
                if moveConnected then moveUnhookOld() end
                moveReleaseAll()
                task.spawn(moveConnectCycle)
                pathSetStatus(
                    "SCAN MOVEMENT DIMULAI ULANG. TUNGGU STATUS TERHUBUNG."
                )
            end))

            pathTrack(UIS.WindowFocusReleased:Connect(function()
                if pathGoRunning then
                    pathStopRequested = true
                    pathGoRunning = false
                    pathReleaseAll()
                    pathSetStatus("WINDOW FOCUS HILANG. GO DIHENTIKAN.")
                end
            end))

            if LocalPlayer then
                pathTrack(LocalPlayer.CharacterRemoving:Connect(function()
                    pathStopRequested = true
                    pathGoRunning = false
                    pathReleaseAll()
                end))
            end

            local function pathCleanup()
                if not pathRunning then return end
                pathRunning = false
                pathStopRequested = true
                pathGoRunning = false
                for _, key in ipairs({"left", "right", "jump", "down"}) do
                    moveInput[key] = false
                end
                for _, connection in ipairs(pathConnections) do
                    pcall(function() connection:Disconnect() end)
                end
                table.clear(pathConnections)
                pathLog("SUBMODULE DITUTUP; INPUT PATHFINDER DILEPAS")
            end

            Hub.RegisterCleanup(pathCleanup)
            pathSetStatus(
                "Submodule dimuat. Menggunakan koneksi MOVEMENT dari modul utama."
            )
            pathLog("Submodule loaded.")
        end

        --==================================================
        -- [17] SUBMODULE 4: DROP SELECTED INVENTORY
        -- Menggunakan HUD.onDrop milik game seperti K.lua.
        -- Tidak memasang hook movement baru; arah dibantu controller MOVEMENT.
        --==================================================
        do
            local dropAlive = true
            local dropBusy = false
            local dropHud = nil
            local dropOnDrop = nil
            local dropSelected = {}
            local dropRows = {}
            local dropConnections = {}
            local dropRowConnections = {}

            local function dropTrack(connection)
                dropConnections[#dropConnections + 1] = connection
                return connection
            end

            local dropStatusLabel
            local function dropStatus(message)
                message = tostring(message or "-")
                if dropStatusLabel and dropStatusLabel.Parent then
                    dropStatusLabel.Text = "STATUS: " .. message
                end
                print("[GB DROP INVENTORY]", message)
            end

            local dropToggle = makeButton(
                "DROP SELECTED INVENTORY  ▼", 34, page, Theme.Accent
            )
            dropToggle.LayoutOrder = 4

            local dropPanel = create("Frame", {
                Name = "DropSelectedInventoryPanel",
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.Panel,
                BorderSizePixel = 0,
                Visible = false,
                LayoutOrder = 5,
            }, page)
            corner(dropPanel, 8)

            create("UIPadding", {
                PaddingTop = UDim.new(0, 8),
                PaddingBottom = UDim.new(0, 8),
                PaddingLeft = UDim.new(0, 8),
                PaddingRight = UDim.new(0, 8),
            }, dropPanel)

            create("UIListLayout", {
                Padding = UDim.new(0, 6),
                SortOrder = Enum.SortOrder.LayoutOrder,
            }, dropPanel)

            dropStatusLabel = makeLabel(
                "STATUS: tekan SCAN SELECTED INVENTORY", 30, dropPanel
            )
            dropStatusLabel.LayoutOrder = 1

            local dropSummaryLabel = makeLabel(
                "ITEM TERBACA: 0 | ITEM DIPILIH: 0", 24, dropPanel
            )
            dropSummaryLabel.LayoutOrder = 2

            local dropScanButton = makeButton(
                "SCAN SELECTED INVENTORY", 32, dropPanel, Theme.PanelDark
            )
            dropScanButton.TextColor3 = Theme.Text
            dropScanButton.LayoutOrder = 3

            local dropSelectAllButton = makeButton(
                "PILIH SEMUA ITEM", 30, dropPanel, Theme.PanelDark
            )
            dropSelectAllButton.TextColor3 = Theme.Text
            dropSelectAllButton.LayoutOrder = 4

            local dropList = create("ScrollingFrame", {
                Name = "DropInventoryList",
                Size = UDim2.new(1, 0, 0, 170),
                BackgroundColor3 = Theme.Background,
                BorderSizePixel = 0,
                ScrollBarThickness = 5,
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollingDirection = Enum.ScrollingDirection.Y,
                LayoutOrder = 5,
            }, dropPanel)
            corner(dropList, 6)

            create("UIPadding", {
                PaddingTop = UDim.new(0, 5),
                PaddingBottom = UDim.new(0, 5),
                PaddingLeft = UDim.new(0, 5),
                PaddingRight = UDim.new(0, 5),
            }, dropList)

            local dropListLayout = create("UIListLayout", {
                Padding = UDim.new(0, 4),
                SortOrder = Enum.SortOrder.LayoutOrder,
            }, dropList)

            dropTrack(dropListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                dropList.CanvasSize = UDim2.new(0, 0, 0, dropListLayout.AbsoluteContentSize.Y + 10)
            end))

            local dropButton = makeButton(
                "DROP SEMUA JUMLAH ITEM TERPILIH", 36, dropPanel, Theme.Green
            )
            dropButton.LayoutOrder = 6

            local function dropInventoryCount(id)
                return countItem(id)
            end

            local function dropUpdateSummary(itemCount)
                local selectedCount = 0
                for id in pairs(dropSelected) do
                    if dropSelected[id] then selectedCount += 1 end
                end
                dropSummaryLabel.Text = ("ITEM TERBACA: %d | ITEM DIPILIH: %d"):format(
                    itemCount or #dropRows, selectedCount
                )
            end

            local function dropRenderRows()
                for _, connection in ipairs(dropRowConnections) do
                    pcall(function() connection:Disconnect() end)
                end
                table.clear(dropRowConnections)
                for _, row in ipairs(dropRows) do
                    if row.button and row.button.Parent then
                        row.button:Destroy()
                    end
                end
                table.clear(dropRows)

                local slots = raw(refs.Inv, "slots")
                if type(slots) ~= "table" then
                    dropStatus("INVENTORY BELUM TERBACA. TEKAN SCAN.")
                    dropUpdateSummary(0)
                    return
                end

                local totals = {}
                for _, slot in pairs(slots) do
                    if type(slot) == "table" then
                        local id = tonumber(raw(slot, "id"))
                        local amount = tonumber(raw(slot, "n")) or 0
                        if id and id > 0 and amount > 0 then
                            id = math.floor(id)
                            totals[id] = (totals[id] or 0) + amount
                        end
                    end
                end

                local ids = {}
                for id in pairs(totals) do ids[#ids + 1] = id end
                table.sort(ids)

                for index, id in ipairs(ids) do
                    local amount = totals[id]
                    local selected = dropSelected[id] == true
                    local button = create("TextButton", {
                        Name = "DropItem_" .. tostring(id),
                        Size = UDim2.new(1, -2, 0, 29),
                        BackgroundColor3 = selected and Theme.Green or Theme.PanelDark,
                        BorderSizePixel = 0,
                        Text = (selected and "[✓] " or "[ ] ")
                            .. ("ITEM ID %d  |  JUMLAH %d"):format(id, amount),
                        TextColor3 = selected and Theme.White or Theme.Text,
                        Font = Enum.Font.GothamBold,
                        TextSize = 10,
                        AutoButtonColor = true,
                        LayoutOrder = index,
                    }, dropList)
                    corner(button, 5)
                    dropRows[#dropRows + 1] = { id = id, amount = amount, button = button }

                    dropRowConnections[#dropRowConnections + 1] = button.Activated:Connect(function()
                        if dropBusy or not dropAlive then return end
                        dropSelected[id] = not dropSelected[id] or nil
                        button.BackgroundColor3 = dropSelected[id] and Theme.Green or Theme.PanelDark
                        button.TextColor3 = dropSelected[id] and Theme.White or Theme.Text
                        button.Text = (dropSelected[id] and "[✓] " or "[ ] ")
                            .. ("ITEM ID %d  |  JUMLAH %d"):format(id, dropInventoryCount(id))
                        dropUpdateSummary(#ids)
                    end)
                end

                -- Hapus pilihan yang sudah tidak ada dalam inventory.
                local available = {}
                for _, id in ipairs(ids) do available[id] = true end
                for id in pairs(dropSelected) do
                    if not available[id] then dropSelected[id] = nil end
                end

                dropUpdateSummary(#ids)
                if #ids == 0 then
                    dropStatus("INVENTORY KOSONG.")
                else
                    dropStatus(("SCAN SELESAI. %d JENIS ITEM DITEMUKAN."):format(#ids))
                end
            end

            local function dropScan()
                if dropBusy then
                    dropStatus("TUNGGU PROSES DROP SELESAI.")
                    return false
                end
                if type(getgc) ~= "function" then
                    dropStatus("EXECUTOR TIDAK MENYEDIAKAN getgc.")
                    return false
                end

                dropStatus("MEMINDAI INVENTORY DAN HUD GAME...")
                local ok, objects = pcall(getgc, true)
                if not ok or type(objects) ~= "table" then
                    dropStatus("getgc(true) GAGAL: " .. tostring(objects))
                    return false
                end

                local bestInv
                local foundHud
                for _, object in ipairs(objects) do
                    if type(object) == "table" then
                        local candidate = inventoryCandidate(object)
                        if candidate and (not bestInv or candidate.score > bestInv.score) then
                            bestInv = candidate
                        end

                        if not foundHud
                            and type(raw(object, "punchRange")) == "function"
                            and type(raw(object, "handPower")) == "function"
                            and type(raw(object, "onDrop")) == "function" then
                            foundHud = object
                        end
                    end
                end

                if bestInv then refs.Inv = bestInv.ref end
                dropHud = foundHud
                dropOnDrop = foundHud and raw(foundHud, "onDrop") or nil

                if not refs.Inv then
                    dropStatus("INVENTORY TIDAK DITEMUKAN.")
                    return false
                end
                if type(dropOnDrop) ~= "function" then
                    dropStatus("HUD DITEMUKAN/TIDAK: FUNGSI onDrop TIDAK DITEMUKAN.")
                    dropRenderRows()
                    return false
                end

                dropRenderRows()
                dropStatus("SCAN SELESAI. HUD.onDrop SIAP.")
                return true
            end

            local function dropOneItem(id, requested)
                local left = math.min(math.max(0, math.floor(tonumber(requested) or 0)),
                    dropInventoryCount(id))
                local initial = left
                local flipped = false

                while left > 0 and dropAlive and not destroyed and not Hub.IsClosing() do
                    local before = dropInventoryCount(id)
                    local amount = math.min(left, 200)
                    local ok, err = pcall(dropOnDrop, id, amount)
                    if not ok then
                        return initial - left, "onDrop error: " .. tostring(err)
                    end

                    task.wait(0.7)
                    local after = dropInventoryCount(id)
                    local got = before - after
                    if got > 0 then
                        left = math.max(0, left - got)
                        flipped = false
                    elseif not flipped then
                        -- Sama seperti K.lua: bila sisi depan terhalang, balik arah sekali.
                        local state = nil
                        if type(refs.State) == "function" then
                            local good, value = pcall(refs.State)
                            if good then state = value end
                        end
                        local right = state and (state.facing or 1) < 0 or false
                        if moveConnected then
                            moveSetInput("right", right)
                            moveSetInput("left", not right)
                            task.wait(0.06)
                            moveSetInput("right", false)
                            moveSetInput("left", false)
                        end
                        task.wait(0.3)
                        flipped = true
                    else
                        return initial - left, "tidak bisa drop di posisi ini"
                    end
                end

                return initial - left, nil
            end

            dropTrack(dropToggle.Activated:Connect(function()
                dropPanel.Visible = not dropPanel.Visible
                dropToggle.Text = dropPanel.Visible
                    and "DROP SELECTED INVENTORY  ▲"
                    or "DROP SELECTED INVENTORY  ▼"
            end))

            dropTrack(dropScanButton.Activated:Connect(function()
                if dropScan() then
                    dropStatus("SCAN SELESAI. PILIH ITEM YANG AKAN DI-DROP.")
                end
            end))

            dropTrack(dropSelectAllButton.Activated:Connect(function()
                if dropBusy then return end
                if #dropRows == 0 then
                    dropStatus("SCAN INVENTORY TERLEBIH DAHULU.")
                    return
                end
                for _, row in ipairs(dropRows) do
                    dropSelected[row.id] = true
                    if row.button and row.button.Parent then
                        row.button.BackgroundColor3 = Theme.Green
                        row.button.TextColor3 = Theme.White
                        row.button.Text = "[✓] " .. ("ITEM ID %d  |  JUMLAH %d"):format(
                            row.id, dropInventoryCount(row.id)
                        )
                    end
                end
                dropUpdateSummary(#dropRows)
                dropStatus("SEMUA ITEM INVENTORY DIPILIH.")
            end))

            dropTrack(dropButton.Activated:Connect(function()
                if dropBusy then return end
                if not refs.Inv or type(dropOnDrop) ~= "function" then
                    dropStatus("TEKAN SCAN SELECTED INVENTORY TERLEBIH DAHULU.")
                    return
                end

                local selectedIds = {}
                for id, selected in pairs(dropSelected) do
                    if selected and dropInventoryCount(id) > 0 then
                        selectedIds[#selectedIds + 1] = id
                    end
                end
                table.sort(selectedIds)
                if #selectedIds == 0 then
                    dropStatus("BELUM ADA ITEM YANG DIPILIH.")
                    return
                end

                dropBusy = true
                dropButton.Active = false
                dropStatus(("MULAI DROP %d JENIS ITEM..."):format(#selectedIds))

                task.spawn(function()
                    local totalDropped = 0
                    local failed = {}
                    for _, id in ipairs(selectedIds) do
                        if not dropAlive or destroyed or Hub.IsClosing() then break end
                        local amount = dropInventoryCount(id)
                        if amount > 0 then
                            dropStatus(("DROP ITEM ID %d | JUMLAH %d..."):format(id, amount))
                            local got, err = dropOneItem(id, amount)
                            totalDropped += got
                            if err then
                                failed[#failed + 1] = ("ID %d: %s"):format(id, tostring(err))
                            end
                        end
                    end

                    dropBusy = false
                    if dropButton and dropButton.Parent then dropButton.Active = true end
                    dropRenderRows()
                    if #failed > 0 then
                        dropStatus(("SELESAI SEBAGIAN. TOTAL DROP %d. GAGAL: %s"):format(
                            totalDropped, table.concat(failed, " | ")
                        ))
                    else
                        dropStatus(("SELESAI. TOTAL ITEM BERHASIL DI-DROP: %d."):format(
                            totalDropped
                        ))
                    end
                end)
            end))

            local function dropCleanup()
                if not dropAlive then return end
                dropAlive = false
                for _, connection in ipairs(dropConnections) do
                    pcall(function() connection:Disconnect() end)
                end
                table.clear(dropConnections)
                for _, connection in ipairs(dropRowConnections) do
                    pcall(function() connection:Disconnect() end)
                end
                table.clear(dropRowConnections)
                dropSelected = {}
                dropRows = {}
                dropHud = nil
                dropOnDrop = nil
            end

            Hub.RegisterCleanup(dropCleanup)
            dropStatus("SUBMODULE DIMUAT. TEKAN SCAN UNTUK MEMBACA INVENTORY.")
            print("[GB DROP INVENTORY] Submodule loaded.")
        end
    end)

end -- return function(Hub)

--==================================================
-- END MODULE: AUTO PUT + BREAK + COLLECT
--==================================================
