--==================================================
-- MAIN MODULE: MODUL FUNGSI UTAMA
-- Satu Hub.RegisterTab dengan dua submodule aktif dan terpisah:
-- 1) PUT + BREAK + COLLECT
-- 2) DIRT FARM PATHFINDING (termasuk backend discovery + hook movement)
-- Masing-masing memiliki state, event, dan cleanup dalam scope sendiri.
-- Shared root hanya berisi service/configuration dan helper UI generik.
-- Movement Testing dan Drop Selected Inventory hanya tersimpan sebagai arsip.
--==================================================

return function(Hub)

    Hub.RegisterTab("MODUL FUNGSI UTAMA", function(page)
 
        --==================================================
        -- MAIN HUB TAB / ROOT CONTAINER
        -- Ini adalah satu-satunya Hub.RegisterTab pada file ini.
        -- Panel PNB dan Pathfinding di bawahnya bukan Hub tab terpisah.
        --==================================================

        --==================================================
        -- [01] ROOT SERVICES, CONFIGURATION & SHARED UI HELPERS
        --==================================================
        --
        -- DEPENDENCY / IMPORT MAP:
        -- Roblox services:
        --   Players, ReplicatedStorage, UserInputService (khusus Pathfinding).
        -- Hub API:
        --   Hub.RegisterTab, Hub.RegisterCleanup, Hub.IsClosing.
        -- Shared Luau/Roblox APIs:
        --   Instance, task, pcall, type, pairs, ipairs, table, rawget,
        --   typeof, os.clock, Color3, UDim, UDim2, Enum.
        -- Executor/runtime capabilities yang diperlukan:
        --   getgc(true)                 : discovery object/function runtime.
        --   debug.info                  : nama dan jumlah parameter function PNB.
        --   debug.getconstants/getconstants : validasi konstanta setTile/hit.
        --   getgenv()                   : stop bridge Pathfinding (fallback _G).
        -- Optional untuk fallback Auto Collect:
        --   debug.getupvalues atau debug.getupvalue/getupvalue,
        --   getconnections.
        --
        -- CATATAN HOOK:
        -- Pathfinding tidak memakai hookfunction. Hook dilakukan dengan
        -- mengganti field movementTable.isDown memakai wrapper, lalu restore
        -- fungsi asli saat cleanup. Jangan memasang wrapper kedua pada field sama.
        --
        -- KETERGANTUNGAN GAME:
        -- PNB: Inventory(slots/capacity/selected), World(fg/bg/w/h/spawn),
        --      PlayerState.state, setTile, hit, serta dropList/dropTaken/
        --      takeDrop atau WorldRemotes.TakeDrop untuk Auto Collect.
        -- Pathfinding: World, PlayerState.state, Movement(isDown/spaceJumps/KEYS).
        --
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



        --==================================================
        -- [02] SHARED UI HELPERS
        -- Hanya helper UI generik; state runtime dideklarasikan per submodule.
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
        -- [03] SUBMODULE MAP
        --   SUBMODULE 1: PUT + BREAK + COLLECT
        --       discovery -> inventory/world helpers -> plan -> put/break
        --       -> auto collect -> orchestrator -> UI events -> cleanup.
        --   SUBMODULE 2: DIRT FARM PATHFINDING
        --       discovery -> World/PlayerState/Movement -> hook isDown
        --       -> state reader/input adapter -> path algorithm -> UI -> cleanup.
        --   Archived only: Movement Testing UI, Drop Selected Inventory.
        --==================================================
        -- SUBMODULE 1 SCOPE: PUT + BREAK + COLLECT
        -- State, discovery, proses, event, dan cleanup PNB terisolasi.
        --==================================================
        do
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

        -- Forward declaration: report() memakai statusLabel lokal submodule ini.
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
        -- Hanya menghentikan worker, popup, dan koneksi milik PNB.
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

        -- PNB mendaftarkan cleanup sendiri; tidak mematikan Pathfinding.
        Hub.RegisterCleanup(cleanup)
        print("[APB+COLLECT] PUT + BREAK + COLLECT submenu loaded.")
        end -- SUBMODULE 1: PUT + BREAK + COLLECT scope



        --==================================================
        -- SUBMODULE 2 SCOPE: DIRT FARM PATHFINDING
        -- Discovery, hook movement, navigasi, event, dan cleanup berada
        -- dalam satu scope. PNB tidak bergantung pada backend ini.
        --==================================================
        do
            local moveCleanup -- cleanup hook/input milik Pathfinding.
            local pathSetStatus -- forward declaration for backend status updates.
        --==================================================
        -- PATHFINDING INTERNAL BACKEND
        -- Backend discovery World/PlayerState/Movement, hook isDown,
        -- state reader, input virtual, dan restore hook milik Pathfinding.
        -- [15] PATHFINDING BACKEND | DISCOVERY + STATE + HOOK
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

        local moveConnections = {}

        local function moveTrack(connection)
            table.insert(moveConnections, connection)
            return connection
        end

        local function moveLog(...)
            print("[GB PATHFINDING BACKEND]", ...)
        end

        local function moveSetStatus(message)
            moveLastError = tostring(message or "-")
            moveLog("STATUS:", moveLastError)
            if type(pathSetStatus) == "function" then
                pathSetStatus("MOVEMENT BACKEND: " .. moveLastError)
            end
        end

        local function moveSafeRaw(t, key)
            if type(t) ~= "table" then return nil end
            local ok, value = pcall(rawget, t, key)
            if ok then return value end
            return nil
        end

        --==================================================
        -- CATATAN PLAYER FACING (HASIL PENGUJIAN REAL-TIME)
        --==================================================
        -- SUMBER NILAI RAW:
        --   PlayerState disimpan sebagai function pada moveRefs.stateFn.
        --   Panggil function tersebut untuk memperoleh state terbaru:
        --       local state = moveReadPlayerState(moveRefs.stateFn)
        --       local facingRaw = state and state.facing
        --
        -- HASIL PENGUJIAN YANG SUDAH DIKONFIRMASI:
        --       facingRaw ==  1  -> player menghadap KANAN
        --       facingRaw == -1  -> player menghadap KIRI
        --
        -- PENERJEMAHAN NILAI (CONTOH KONSEPTUAL, BUKAN KODE AKTIF):
        --       if facingRaw == 1 then
        --           facingName = "KANAN"
        --       elseif facingRaw == -1 then
        --           facingName = "KIRI"
        --       else
        --           facingName = "TIDAK DIKENAL"
        --       end
        --
        -- PEMBACAAN REAL-TIME:
        --   Ambil state dengan memanggil moveRefs.stateFn kembali setiap kali
        --   arah hadap perlu diperiksa. Jangan hanya memakai moveRefs.state
        --   hasil scan awal karena nilai tersebut bisa menjadi data lama.
        --
        -- CATATAN UNTUK FITUR DROP DI MASA DEPAN:
        --   Bandingkan posisi tile target dengan posisi player untuk
        --   menentukan arah yang dibutuhkan. Sebelum drop, baca facingRaw
        --   terbaru dan pastikan nilainya sesuai:
        --       target di kanan -> facingRaw harus 1
        --       target di kiri  -> facingRaw harus -1
        --   Catatan ini hanya dokumentasi; belum ada koreksi arah maupun
        --   pemanggilan drop yang ditambahkan pada module ini.
        --==================================================

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

        -- DISCOVERY MOVEMENT:
        -- moveGetGC() mengambil snapshot objek Lua aktif dengan getgc(true).
        -- moveScanFromZero() memeriksa setiap tabel untuk tiga komponen:
        --   WORLD: fg/bg berupa tabel, w/h berupa angka, dan spawn tersedia.
        --   PLAYER STATE: field state berisi function yang saat dipanggil
        --     mengembalikan tabel dengan x, y, facing, vx (active tidak false).
        --   MOVEMENT TABLE: memiliki isDown function, spaceJumps function,
        --     dan KEYS dengan keyJump/keyLeft/keyRight/keyDown pada indeks
        --     yang diharapkan.
        -- Referensi yang lolos validasi disimpan ke moveRefs. Ini adalah
        -- pengambilan referensi dari objek runtime, bukan pemanggilan gerak.
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
            end
        end


        -- PEMBUNGKUS HOOK:
        -- moveBuildWrapper(original) membuat fungsi pengganti untuk isDown.
        -- Saat game bertanya apakah suatu tombol ditekan, wrapper:
        --   1. Memanggil fungsi isDown asli dengan argumen yang sama.
        --   2. Menyimpan hasil input fisik (keyboard/game input asli).
        --   3. Untuk keyLeft/keyRight/keyJump/keyDown, menggabungkan hasil
        --      fisik dengan flag moveInput yang diisi Pathfinding.
        -- Dengan OR, input virtual menambah input fisik, bukan mematikannya.
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

        -- PEMASANGAN HOOK:
        -- moveInstallHook() mengambil moveRefs.movement.isDown sebagai fungsi
        -- asli, membuat wrapper, lalu mengganti field module.isDown.
        -- Setelah assignment, fungsi memeriksa ulang bahwa field benar-benar
        -- berisi wrapper. Referensi original dan wrapper disimpan agar hook
        -- dapat dikenali dan dipulihkan. Fungsi ini tidak memanggil gerakan
        -- secara langsung; ia mengubah jalur pembacaan status tombol.
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

        -- SIKLUS CONNECT:
        -- moveConnectCycle() mengulang scan hingga 30 kali dengan jeda 0,5 s.
        -- Jika World + PlayerState + Movement table ditemukan, ia memasang
        -- hook isDown. Pathfinding menunggu moveConnected=true sebelum GO.
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
                warn("[GB PATHFINDING BACKEND] Scan belum berhasil: " .. tostring(message))
            end
        end

        local function moveSetInput(key, value)
            if not moveRunning then return end
            if moveInput[key] == nil then return end
            moveInput[key] = value == true
        end


        -- BACKEND MOVEMENT | LIFECYCLE TANPA PANEL TESTING
        -- Input virtual hanya diset oleh Pathfinding melalui moveSetInput().
        -- Tidak ada tombol Movement yang dibuat pada UI.
        --
        -- WindowFocusReleased dan CharacterRemoving melepas seluruh flag
        -- input agar tombol virtual tidak tertahan saat fokus/karakter hilang.
        moveTrack(UIS.WindowFocusReleased:Connect(moveReleaseAll))

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

        -- Cleanup backend: hentikan scan, lepaskan input, pulihkan isDown asli,
        -- putus semua koneksi, dan hapus global stop bridge.
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
            moveLog("BACKEND MOVEMENT DIHENTIKAN DAN HOOK DIPULIHKAN")
        end

        moveENV.GB_MOVEMENT_STOP = moveCleanup

        -- Scan awal dipertahankan agar Pathfinding dapat langsung memakai
        -- backend setelah referensi game tersedia. Scan ulang juga tersedia
        -- dari tombol SCAN / CONNECT ULANG milik panel Pathfinding.
        moveLog("BACKEND MOVEMENT: MEMULAI SCAN DARI NOL")
        moveLog("ACCOUNT:", LocalPlayer and LocalPlayer.Name or "tidak tersedia")
        moveLog("USER ID:", LocalPlayer and LocalPlayer.UserId or "tidak tersedia")
        task.spawn(moveConnectCycle)

        print("[GB PATHFINDING BACKEND] Internal backend loaded.")

        --==================================================
        -- [16] SUBMODULE 2: DIRT FARM PATHFINDING
        -- Discovery dan hook movement berada di scope Pathfinding.
        -- Satu hook isDown dipasang/dipulihkan oleh lifecycle Pathfinding.
        --==================================================

            -- RINGKASAN LOGIKA PATHFINDING:
            -- 1. LOCK menyimpan koordinat state.x/state.y saat ini sebagai target.
            -- 2. GO membaca state aktual dan mengubah posisi Y menjadi baris tile.
            -- 3. Jika baris berbeda, pathCrossOneFarmRow() mencari koridor tile
            --    kosong FG=0 dan BG=0 pada baris berikutnya.
            -- 4. Player diarahkan ke koridor, lalu input JUMP/DOWN dipakai untuk
            --    melewati satu baris farm sesuai arah tujuan.
            -- 5. Jika sudah satu baris dengan target, gerak horizontal dikoreksi.
            -- 6. Tujuan dianggap tercapai setelah toleransi X/Y terpenuhi dan
            --    posisi stabil selama 0,5 detik.
            -- STOP/focus hilang/karakter hilang melepas seluruh input.
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

            pathSetStatus = function(message)
                message = tostring(message or "-")
                if pathStatusLabel and pathStatusLabel.Parent then
                    pathStatusLabel.Text = "STATUS: " .. message
                end
                pathLog(message)
            end

            -- ADAPTER INPUT PATHFINDING -> MOVEMENT BACKEND:
            -- Pathfinding tidak memanggil game movement function secara langsung.
            -- Ia mengubah moveInput melalui moveSetInput(); wrapper isDown yang
            -- sudah terpasang akan membaca flag tersebut saat game meminta
            -- status keyLeft/keyRight/keyJump/keyDown.
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

            -- STATE READER PATHFINDING:
            -- Memanggil fungsi stateFn yang ditemukan backend, memvalidasi
            -- hasilnya, lalu memperbarui cache moveRefs.state.
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

            -- ORKESTRATOR PATHFINDING:
            -- Membandingkan baris player dan target, memilih lintasan baris
            -- melalui tile kosong, lalu mengoreksi posisi horizontal.
            -- Semua perintah arah masuk melalui pathSetInput() -> moveInput
            -- -> wrapper isDown. State aktual selalu dibaca ulang dari stateFn.
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
                moveReleaseAll()
                if moveCleanup then
                    pcall(moveCleanup)
                end
                for _, connection in ipairs(pathConnections) do
                    pcall(function() connection:Disconnect() end)
                end
                table.clear(pathConnections)
                pathLog("SUBMODULE DITUTUP; INPUT PATHFINDER DILEPAS")
            end

            -- Pathfinding cleanup juga memulihkan hook backend miliknya.
            Hub.RegisterCleanup(pathCleanup)
            if moveConnected then
                pathSetStatus("MOVEMENT BACKEND TERHUBUNG. PATHFINDING SIAP.")
            else
                pathSetStatus(
                    "Pathfinding dimuat. Menunggu backend movement internal terhubung."
                )
            end
            pathLog("Submodule loaded.")
        end -- SUBMODULE 2: DIRT FARM PATHFINDING scope

        --==================================================
        -- [17] ARSIP FITUR NONAKTIF: MOVEMENT TESTING
        -- UI testing/tombol manual dihapus; backend hook tetap dipakai Pathfinding.
        --==================================================
        --
        -- TUJUAN SUBMODULE LAMA:
        -- Menampilkan status akun/world/player state, menyediakan tombol
        -- KIRI/KANAN/JUMP/TURUN, serta tombol scan/connect ulang untuk menguji hook.
        --
        -- KOMPONEN YANG DITEMUKAN:
        -- 1. getgc(true): daftar objek runtime.
        -- 2. Movement table:
        --      isDown      = function
        --      spaceJumps  = function
        --      KEYS        = table
        -- 3. KEYS:
        --      [2][1] = "keyJump"
        --      [3][1] = "keyLeft"
        --      [4][1] = "keyRight"
        --      [5][1] = "keyDown"
        -- 4. PlayerState: object.state function mengembalikan x, y, facing, vx.
        -- 5. World: tabel dengan fg, bg, w, h, dan spawn.
        --
        -- CARA HOOK:
        -- moveScanFromZero() mencari World, PlayerState, dan Movement table.
        -- moveInstallHook() menyimpan isDown asli, membuat wrapper, lalu
        -- mengganti movementTable.isDown dengan wrapper tersebut.
        -- Wrapper tetap memanggil fungsi asli dan menggabungkan hasil input
        -- fisik dengan flag virtual untuk keyLeft/keyRight/keyJump/keyDown.
        --
        -- INPUT VIRTUAL:
        -- UI lama mengubah moveInput melalui moveSetInput().
        -- Sekarang Pathfinding menjadi satu-satunya pemakai moveSetInput().
        -- Alur: pathSetInput -> moveSetInput -> moveInput -> wrapper isDown.
        --
        -- PEMULIHAN:
        -- moveUnhookOld() mengembalikan isDown asli hanya jika field masih
        -- berisi wrapper milik script ini. moveCleanup() melepas input,
        -- memulihkan hook, dan memutus koneksi backend.
        --
        --==================================================
        --==================================================
        -- [18] ARSIP FITUR NONAKTIF: DROP SELECTED INVENTORY
        -- SUBMODULE AKTIF DIHAPUS; BAGIAN INI HANYA CATATAN PENGEMBANGAN.
        --==================================================
        --
        -- TUJUAN FITUR LAMA:
        -- Mengambil item yang sedang dipilih pada Inventory, menghitung total
        -- jumlah item tersebut, lalu memanggil HUD.onDrop(id, amount) satu kali.
        --
        -- URUTAN PENGAMBILAN FUNGSI / DATA:
        -- 1. getgc(true)
        --    Mengambil daftar objek runtime yang sedang aktif. Hasilnya berupa
        --    tabel `objects` yang dipakai untuk mencari Inventory dan HUD.
        --
        -- 2. OBJEK INVENTORY AKTIF (`liveInventory`)
        --    Kandidat dicari sebagai tabel yang memiliki:
        --      - slots: tabel slot inventory.
        --      - capacity: angka kapasitas inventory.
        --      - selected: ID item terpilih dengan nilai > 0.
        --    Catatan: kode lama sengaja mencari ulang Inventory saat tombol
        --    ditekan, bukan memakai refs.Inv hasil discovery PNB, karena
        --    kandidat Inventory generik PNB belum tentu memiliki selected
        --    yang sesuai dengan inventory aktif.
        --
        -- 3. ID ITEM TERPILIH (`id`)
        --    Dibaca dari liveInventory.selected, dikonversi ke number, lalu
        --    dibulatkan dengan math.floor().
        --
        -- 4. JUMLAH ITEM (`amount`)
        --    Ambil liveInventory.slots. Untuk setiap slot, cocokkan:
        --      slot.id == id
        --    lalu jumlahkan slot.n. Jadi komponen slot yang diperlukan adalah:
        --      slot.id : ID item pada slot.
        --      slot.n  : jumlah item pada slot.
        --
        -- 5. OBJEK HUD DAN FUNGSI onDrop
        --    Dari daftar `objects`, cari tabel HUD yang memiliki:
        --      punchRange : function
        --      handPower  : function
        --      onDrop     : function
        --    Dua function pertama dipakai sebagai ciri kandidat HUD; fungsi
        --    yang benar-benar dipanggil adalah onDrop.
        --
        -- 6. PEMANGGILAN DROP
        --    pcall(onDrop, id, amount)
        --    Artinya fungsi menerima dua argumen: ID item dan jumlah item.
        --    Versi lama hanya memanggil satu kali; tidak ada loop, retry,
        --    batch, atau pemilihan item tambahan.
        --
        -- DAFTAR VARIABLE / KOMPONEN YANG DIPERLUKAN JIKA FITUR DIBANGUN ULANG:
        --   objects       = hasil getgc(true)
        --   liveInventory = tabel inventory aktif
        --   slots         = liveInventory.slots
        --   capacity      = liveInventory.capacity (validasi kandidat)
        --   selected      = liveInventory.selected
        --   id            = ID item terpilih
        --   slot          = setiap entri di slots
        --   amount        = total slot.n untuk slot.id yang cocok dengan id
        --   HUD candidate = tabel dengan punchRange, handPower, onDrop
        --   onDrop        = fungsi HUD yang dipanggil
        --
        -- PENTING:
        -- Fitur DROP SELECTED INVENTORY berbeda dari AUTO COLLECT PNB.
        -- AUTO COLLECT mengambil drop yang sudah berada di world melalui
        -- World.takeDrop / TakeDropRemote. DROP SELECTED INVENTORY meminta HUD
        -- menjatuhkan item dari inventory melalui HUD.onDrop.
        --
        --==================================================
    end)

end -- return function(Hub)

--==================================================
-- END MODULE: PUT + BREAK + COLLECT + PATHFINDING
--==================================================
