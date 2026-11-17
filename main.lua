--[[
GROWBLOX AUTO PUT + BREAK V4
- Fase 1: PUT ke semua target. Fase 2: BREAK semua hasil PUT. Ulangi terus.
- Pilih item di INVENTORY game, lalu tekan LOCK SELECTED.
- Delay PUT, delay antar-hit BREAK, jeda awal BREAK, dan jeda antar-siklus dapat diatur (ms).
]]

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then warn("[APB] LocalPlayer tidak ditemukan") return end

local getconsts = (debug and debug.getconstants) or getconstants
local function raw(t, k)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(rawget, t, k)
    return ok and v or nil
end
local function log(...) print("[APB]", ...) end

if type(getgc) ~= "function" or type(getconsts) ~= "function"
    or not (debug and debug.info) then
    warn("[APB] Executor tidak menyediakan getgc/getconstants/debug.info")
    return
end

-- UI
local parent
if type(gethui) == "function" then
    local ok, result = pcall(gethui)
    if ok and result then parent = result end
end
parent = parent or CoreGui
local old = parent:FindFirstChild("GrowBloxAutoPutBreak")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "GrowBloxAutoPutBreak"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(370, 590)
main.Position = UDim2.new(0, 25, 0.5, -252)
main.BackgroundColor3 = Color3.fromRGB(25, 29, 38)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

local function label(txt, y, h, size)
    local o = Instance.new("TextLabel")
    o.BackgroundTransparency = 1
    o.Position = UDim2.fromOffset(12, y)
    o.Size = UDim2.new(1, -24, 0, h)
    o.Font = Enum.Font.Gotham
    o.TextSize = size or 11
    o.TextColor3 = Color3.fromRGB(235, 238, 245)
    o.TextXAlignment = Enum.TextXAlignment.Left
    o.TextYAlignment = Enum.TextYAlignment.Center
    o.TextWrapped = true
    o.Text = txt
    o.Parent = main
    return o
end

local function button(txt, x, y, w, h, color)
    local b = Instance.new("TextButton")
    b.Position = UDim2.fromOffset(x, y)
    b.Size = UDim2.fromOffset(w, h)
    b.BackgroundColor3 = color or Color3.fromRGB(55, 95, 150)
    b.BorderSizePixel = 0
    b.Text = txt
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.Parent = main
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local title = label("GROWBLOX AUTO PUT + BREAK  |  V2", 7, 25, 14)
title.Font = Enum.Font.GothamBold
local status = label("Status: menyiapkan scan...", 35, 34, 11)
local selectedLabel = label("Inventory selected: belum terbaca", 70, 28, 11)
local info = label("Anchor: tile tempat player berdiri | area 5 x 3", 99, 25, 10)

local lockBtn = button("LOCK SELECTED", 12, 132, 166, 32)
local scanBtn = button("SCAN ULANG", 190, 132, 166, 32, Color3.fromRGB(75, 95, 75))

local grid = Instance.new("Frame")
grid.BackgroundTransparency = 1
grid.Position = UDim2.fromOffset(66, 178)
grid.Size = UDim2.fromOffset(236, 142)
grid.Parent = main
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(44, 44)
gridLayout.CellPadding = UDim2.fromOffset(4, 4)
gridLayout.Parent = grid

local previewBtn = button("PREVIEW TARGET", 12, 333, 166, 32, Color3.fromRGB(75, 105, 145))
local startBtn = button("START PUT → BREAK LOOP", 190, 333, 166, 32, Color3.fromRGB(35, 135, 80))
local stopBtn = button("STOP", 12, 375, 166, 32, Color3.fromRGB(165, 55, 55))
local closeBtn = button("CLOSE UI", 190, 375, 166, 32, Color3.fromRGB(75, 78, 88))
label("PENGATURAN JEDA (milidetik / ms)", 414, 22, 11).Font = Enum.Font.GothamBold

local function delayBox(caption, value, x, y)
    local cap = label(caption, y, 20, 10)
    cap.Size = UDim2.fromOffset(165, 20)
    local box = Instance.new("TextBox")
    box.Position = UDim2.fromOffset(x, y + 20)
    box.Size = UDim2.fromOffset(165, 30)
    box.BackgroundColor3 = Color3.fromRGB(42, 47, 59)
    box.BorderSizePixel = 0
    box.TextColor3 = Color3.new(1, 1, 1)
    box.PlaceholderColor3 = Color3.fromRGB(170, 175, 185)
    box.Font = Enum.Font.Gotham
    box.TextSize = 12
    box.ClearTextOnFocus = false
    box.Text = tostring(value)
    box.Parent = main
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)
    return box
end

local putDelayBox = delayBox("Jeda antar PUT", 80, 12, 438)
local breakDelayBox = delayBox("Jeda antar HIT BREAK", 140, 190, 438)
local breakStartBox = delayBox("Jeda awal sebelum BREAK", 150, 12, 492)
local cycleDelayBox = delayBox("Jeda sebelum siklus ulang", 150, 190, 492)
label("Pilih item lalu LOCK. Selected boleh berubah setelah item di-lock.", 548, 28, 9)
gui.Parent = parent

local running = false
local confirmedId = nil
local refs = {Inv=nil, World=nil, State=nil, SetTile=nil, Hit=nil}
local enabled = {}
local cells = {}

local function report(msg)
    status.Text = "Status: " .. tostring(msg)
    log(msg)
end

-- Inventory candidate sesuai pola Item ID Reader V2:
-- Inv.slots[index] = {id=..., n=...}, Inv.capacity, Inv.selected.
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
    return {ref=t, score=valid*100 + populated + math.min(cap, 100)}
end

local function findSetTile(objects)
    for _, fn in ipairs(objects) do
        if type(fn) == "function" then
            local okN, name = pcall(debug.info, fn, "n")
            local okA, params, variadic = pcall(debug.info, fn, "a")
            if okN and okA and name == "setTile"
                and params == 6 and variadic == false then
                local okC, c = pcall(getconsts, fn)
                if okC and type(c) == "table" then
                    local f = {}
                    for _, v in pairs(c) do f[v] = true end
                    if f.tile and f.send and f.layer and f.x and f.y
                        and f.id and f.flip and f.placedAt and f.flips then
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
                local okC, c = pcall(getconsts, fn)
                if okC and type(c) == "table" then
                    local f = {}
                    for _, v in pairs(c) do f[v] = true end
                    if f.sendHit and f.punchEvent and f.newCrack then
                        return fn
                    end
                end
            end
        end
    end
end

local function discover()
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
                    local good, s = pcall(stateFn)
                    if good and type(s) == "table"
                        and type(s.x) == "number" and type(s.y) == "number"
                        and s.facing ~= nil and s.vx ~= nil then
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
        if not refs[key] then table.insert(missing, key) end
    end
    if #missing > 0 then
        return false, "Referensi belum lengkap: " .. table.concat(missing, ", ")
    end
    return true, "Scan berhasil: Inventory, World, State, setTile, hit ditemukan."
end

local function selectedId()
    local id = tonumber(raw(refs.Inv, "selected"))
    if id and id > 0 then return math.floor(id) end
end

local function countItem(id)
    local total, slots = 0, raw(refs.Inv, "slots")
    if type(slots) ~= "table" then return 0 end
    for _, slot in pairs(slots) do
        if type(slot) == "table" and tonumber(raw(slot, "id")) == id then
            total += tonumber(raw(slot, "n")) or 0
        end
    end
    return total
end

local function playerTile()
    local ok, s = pcall(refs.State)
    if not ok or type(s) ~= "table"
        or type(s.x) ~= "number" or type(s.y) ~= "number" then
        return nil
    end
    if s.active == false then return nil end
    -- Rumus yang sudah terbukti pada script PUT102.
    return math.floor(s.x), math.floor(s.y - 0.475)
end

local function tileAt(layer, x, y)
    local w = refs.World
    if not w or x < 0 or y < 0 or x >= w.w or y >= w.h then return nil end
    local row = w[layer] and w[layer][y]
    if not row then return nil end
    return row[x] or 0
end

-- Grid offsets: 5 kolom x 3 baris; player berada di tengah baris terbawah.
-- Offset (0,0) tidak pernah diproses.
local function drawGrid()
    for _, child in ipairs(grid:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    table.clear(cells)
    for dy = -2, 0 do
        for dx = -2, 2 do
            local b = Instance.new("TextButton")
            b.Font = Enum.Font.GothamBold
            b.TextSize = 11
            b.Parent = grid
            if dx == 0 and dy == 0 then
                b.Text = "YOU"
                b.BackgroundColor3 = Color3.fromRGB(100, 100, 110)
                b.TextColor3 = Color3.new(1, 1, 1)
                b.AutoButtonColor = false
            else
                local key = dx .. "," .. dy
                if enabled[key] == nil then enabled[key] = true end
                local function paint()
                    b.Text = enabled[key] and "ON" or "OFF"
                    b.BackgroundColor3 = enabled[key]
                        and Color3.fromRGB(40, 135, 80)
                        or Color3.fromRGB(65, 68, 75)
                    b.TextColor3 = Color3.new(1, 1, 1)
                end
                paint()
                b.MouseButton1Click:Connect(function()
                    if running then return end
                    enabled[key] = not enabled[key]
                    paint()
                end)
                cells[key] = b
            end
        end
    end
end
drawGrid()

local function buildPlan()
    local px, py = playerTile()
    if not px then return nil, "Posisi player tidak terbaca." end
    local plan = {}
    for dy = -2, 0 do
        for dx = -2, 2 do
            local key = dx .. "," .. dy
            if not (dx == 0 and dy == 0) and enabled[key] then
                local x, y = px + dx, py + dy
                if x < 0 or y < 0 or x >= refs.World.w or y >= refs.World.h then
                    return nil, ("Koordinat %d,%d di luar world."):format(x, y)
                end
                plan[#plan + 1] = {x=x, y=y, dx=dx, dy=dy}
            end
        end
    end
    if #plan == 0 then return nil, "Tidak ada koordinat aktif." end
    return plan, px, py
end

local function putOne(x, y, id)
    local fg = tileAt("fg", x, y)
    local bg = tileAt("bg", x, y)
    if fg == nil or bg == nil then
        return false, "koordinat di luar world"
    end

    -- Petak hanya boleh dipakai jika KEDUA layer kosong.
    if fg ~= 0 or bg ~= 0 then
        return false, ("petak tidak kosong (FG=%s, BG=%s)"):format(
            tostring(fg), tostring(bg))
    end
    if countItem(id) <= 0 then return false, "item inventory habis" end

    local ok, err = pcall(refs.SetTile, "fg", x, y, id, false, false)
    if not ok then
        -- Jangan langsung menganggap gagal: server mungkin sudah menerima request.
        for _ = 1, 20 do
            task.wait(0.05)
            local nowFg, nowBg = tileAt("fg", x, y), tileAt("bg", x, y)
            if nowFg == id and nowBg == 0 then return true, "PUT terdeteksi setelah SetTile error" end
            if nowFg == nil or nowBg == nil then break end
        end
        return false, "setTile error: " .. tostring(err)
    end

    -- Konfirmasi berdasarkan cache World, bukan hanya keberhasilan pemanggilan fungsi.
    for _ = 1, 60 do
        if not running then return false, "dihentikan saat verifikasi PUT" end
        task.wait(0.05)
        local nowFg, nowBg = tileAt("fg", x, y), tileAt("bg", x, y)
        if nowFg == nil or nowBg == nil then
            return false, "tile keluar dari world saat verifikasi PUT"
        end
        if nowFg == id and nowBg == 0 then return true, "PUT terkonfirmasi" end
        -- Jika server menolak PUT dan petak tetap kosong, tunggu sampai batas
        -- konfirmasi selesai; jangan masukkan tile ini ke antrean BREAK.
    end

    local finalFg, finalBg = tileAt("fg", x, y), tileAt("bg", x, y)
    if finalFg == id and finalBg == 0 then
        return true, "PUT terkonfirmasi pada pemeriksaan akhir"
    end
    return false, ("PUT tidak terkonfirmasi (FG=%s, BG=%s)"):format(
        tostring(finalFg), tostring(finalBg))
end

local function breakOne(x, y, id, startDelayMs, hitDelayMs)
    -- Delay awal memberi waktu server memperbarui PlacedAt sebelum hit pertama.
    task.wait(math.max(0, startDelayMs) / 1000)

    local function readLayers()
        local fg = tileAt("fg", x, y)
        local bg = tileAt("bg", x, y)
        return fg, bg
    end

    local function confirmEmpty()
        -- Wajib 3 pembacaan berturut-turut: FG=0 dan BG=0.
        local consecutive = 0
        for _ = 1, 20 do
            if not running then return false, "dihentikan saat verifikasi tile kosong" end
            task.wait(0.05)
            local fg, bg = readLayers()
            if fg == nil or bg == nil then
                return false, "koordinat tidak valid saat verifikasi"
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
    if fg == nil or bg == nil then return false, "koordinat tidak valid" end
    if fg == 0 and bg == 0 then
        local empty = confirmEmpty()
        if empty then return true, "FG dan BG sudah kosong (terkonfirmasi 3x)" end
    end

    for hitNo = 1, 60 do
        if not running then return false, "dihentikan" end

        fg, bg = readLayers()
        if fg == nil or bg == nil then return false, "koordinat tidak valid" end

        -- Tidak memfilter ID block. Semua isi tile target harus dibersihkan,
        -- termasuk block dengan ID berbeda dari item yang di-LOCK.
        -- Punch asli game mengatur urutan FG lalu BG.

        if fg == 0 and bg == 0 then
            local empty = confirmEmpty()
            if empty then
                return true, ("FG dan BG kosong stabil setelah %d hit"):format(hitNo - 1)
            end
        end

        local ok, err = pcall(refs.Hit, x, y, nil, nil)
        if not ok then return false, "hit error: " .. tostring(err) end

        task.wait(math.max(0, hitDelayMs) / 1000)

        -- Baca ulang kedua layer. Jika belum kosong, tetap di tile ini.
        local afterFg, afterBg = readLayers()
        if afterFg == nil or afterBg == nil then
            return false, "koordinat tidak valid setelah hit"
        end
        if afterFg == 0 and afterBg == 0 then
            local empty = confirmEmpty()
            if empty then
                return true, ("FG dan BG kosong stabil setelah %d hit"):format(hitNo)
            end
        end
    end

    local finalFg, finalBg = readLayers()
    return false, ("BREAK belum terkonfirmasi setelah 60 hit (FG=%s, BG=%s); tidak lanjut ke tile berikutnya"):format(
        tostring(finalFg), tostring(finalBg))
end

local function readDelay(box, defaultValue, minimum, maximum)
    local n = tonumber(box.Text)
    if not n then return nil, "Isi jeda harus berupa angka (ms)." end
    n = math.floor(n)
    if n < minimum or n > maximum then
        return nil, ("Jeda harus %d sampai %d ms."):format(minimum, maximum)
    end
    return n
end

lockBtn.MouseButton1Click:Connect(function()
    if not refs.Inv then report("Inventory belum ditemukan. Tekan SCAN ULANG.") return end
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
    selectedLabel.Text = ("LOCKED ID: %d | jumlah: %d"):format(id, countItem(id))
    report("Item inventory dikunci: ID " .. id)
end)

scanBtn.MouseButton1Click:Connect(function()
    if running then report("Stop proses sebelum scan ulang.") return end
    task.spawn(function()
        confirmedId = nil
        local ok, msg = discover()
        report(ok and msg or ("SCAN GAGAL: " .. msg))
        if refs.Inv then
            local id = selectedId()
            selectedLabel.Text = id
                and ("Inventory selected: ID %d | jumlah: %d"):format(id, countItem(id))
                or "Inventory selected: tidak ada"
        end
    end)
end)

previewBtn.MouseButton1Click:Connect(function()
    if not refs.World or not refs.State then report("World/State belum siap.") return end
    local plan, a, b = buildPlan()
    if not plan then report("PREVIEW GAGAL: " .. tostring(a)) return end
    local coords = {}
    for i, p in ipairs(plan) do
        coords[#coords + 1] = ("%d:(%d,%d)"):format(i, p.x, p.y)
    end
    report(("Anchor player %d,%d | %d target | %s"):format(a, b, #plan, table.concat(coords, " ")))
end)

stopBtn.MouseButton1Click:Connect(function()
    running = false
    report("STOP diminta.")
end)

closeBtn.MouseButton1Click:Connect(function()
    running = false
    gui:Destroy()
end)

startBtn.MouseButton1Click:Connect(function()
    if running then return end
    if not (refs.Inv and refs.World and refs.State and refs.SetTile and refs.Hit) then
        report("Referensi belum lengkap. Tekan SCAN ULANG.")
        return
    end
    if not confirmedId then report("Pilih item di inventory lalu LOCK SELECTED.") return end
    local putMs, e1 = readDelay(putDelayBox, 80, 0, 10000)
    local hitMs, e2 = readDelay(breakDelayBox, 140, 1, 10000)
    local startMs, e3 = readDelay(breakStartBox, 150, 50, 10000)
    local cycleMs, e4 = readDelay(cycleDelayBox, 150, 0, 60000)
    if not putMs then report(e1) return end
    if not hitMs then report(e2) return end
    if not startMs then report(e3) return end
    if not cycleMs then report(e4) return end

    local plan, px, py = buildPlan()
    if not plan then report("START dibatalkan: " .. tostring(px)) return end

    running = true
    task.spawn(function()
        local cycle = 0
        report(("LOOP START | anchor %d,%d | ID %d | %d target"):format(
            px, py, confirmedId, #plan))

        while running do
            cycle += 1
            -- Antrean ini berisi SEMUA tile yang harus dibersihkan:
            -- block lama apa pun ID-nya, serta block yang baru berhasil di-PUT.
            local breakQueue = {}
            local hasEmptyTargetWithoutItem = false
            report(("SIKLUS %d | FASE PUT / CEK TILE"):format(cycle))

            -- FASE 1: tile berisi apa pun masuk antrean BREAK.
            -- Tile kosong baru diisi item LOCKED.
            for index, p in ipairs(plan) do
                if not running then break end
                local cx, cy = playerTile()
                if not cx or cx ~= px or cy ~= py then
                    running = false
                    report("STOP AMAN: posisi player berubah dari anchor.")
                    break
                end
                local currentFg = tileAt("fg", p.x, p.y)
                local currentBg = tileAt("bg", p.x, p.y)

                if currentFg == nil or currentBg == nil then
                    report(("SKIP (%d,%d): koordinat tidak valid"):format(p.x, p.y))

                elseif currentFg ~= 0 or currentBg ~= 0 then
                    -- Tidak peduli block ID sama atau berbeda dari item LOCKED.
                    breakQueue[#breakQueue + 1] = p
                    report(("MASUK ANTREAN BREAK (%d,%d): FG=%s BG=%s"):format(
                        p.x, p.y, tostring(currentFg), tostring(currentBg)))

                else
                    -- Tile kosong: baru perlu item untuk melakukan PUT.
                    if countItem(confirmedId) <= 0 then
                        hasEmptyTargetWithoutItem = true
                        report(("PUT TUNDA (%d,%d): item LOCKED habis"):format(p.x, p.y))
                    else
                        local placed, putMsg = putOne(p.x, p.y, confirmedId)
                        if placed then
                            breakQueue[#breakQueue + 1] = p
                            report(("SIKLUS %d | PUT %d/%d OK (%d,%d): masuk antrean BREAK"):format(
                                cycle, index, #plan, p.x, p.y))
                        else
                            -- Jika request PUT sebenarnya berhasil tetapi respons/cache
                            -- terlambat, tile yang kini berisi tetap wajib di-BREAK.
                            local checkFg = tileAt("fg", p.x, p.y)
                            local checkBg = tileAt("bg", p.x, p.y)
                            if checkFg ~= nil and checkBg ~= nil
                                and (checkFg ~= 0 or checkBg ~= 0) then
                                breakQueue[#breakQueue + 1] = p
                                report(("PUT TIDAK TERKONFIRMASI, ISI TILE TERDETEKSI (%d,%d): antre BREAK"):format(
                                    p.x, p.y))
                            else
                                report(("PUT GAGAL (%d,%d): %s | FG=%s BG=%s"):format(
                                    p.x, p.y, tostring(putMsg),
                                    tostring(checkFg), tostring(checkBg)))
                            end
                        end
                    end
                end

                if putMs > 0 then task.wait(putMs / 1000) end
            end

            if not running then break end

            if #breakQueue == 0 then
                running = false
                if hasEmptyTargetWithoutItem then
                    report("STOP: tile kosong menunggu PUT, tetapi item LOCKED habis.")
                else
                    report("STOP: tidak ada tile berisi yang perlu di-BREAK dan tidak ada PUT berhasil.")
                end
                break
            end

            -- FASE 2: bersihkan semua tile dalam antrean.
            -- Tile lama dengan ID berbeda juga dipukul sampai FG dan BG kosong.
            report(("SIKLUS %d | FASE BREAK: %d tile"):format(cycle, #breakQueue))
            for index, p in ipairs(breakQueue) do
                if not running then break end
                local cx, cy = playerTile()
                if not cx or cx ~= px or cy ~= py then
                    running = false
                    report("STOP AMAN: posisi player berubah dari anchor.")
                    break
                end
                local broken, breakMsg = breakOne(p.x, p.y, confirmedId, startMs, hitMs)
                report(("SIKLUS %d | BREAK %d/%d %s (%d,%d): %s"):format(
                    cycle, index, #breakQueue, broken and "OK" or "GAGAL",
                    p.x, p.y, tostring(breakMsg)))
                if not broken then
                    running = false
                    break
                end
            end

            if running then
                report(("SIKLUS %d SELESAI | ulang PUT dalam %d ms"):format(cycle, cycleMs))
                if cycleMs > 0 then task.wait(cycleMs / 1000) end
            end
        end
        report("LOOP BERHENTI.")
    end)
end)

task.spawn(function()
    task.wait(0.5)
    local ok, msg = discover()
    report(ok and msg or ("SCAN: " .. msg))
    if refs.Inv then
        local id = selectedId()
        selectedLabel.Text = id
            and ("Inventory selected: ID %d | jumlah: %d"):format(id, countItem(id))
            or "Inventory selected: tidak ada"
    end
end)

task.spawn(function()
    while gui.Parent do
        if refs.Inv and not confirmedId then
            local id = selectedId()
            selectedLabel.Text = id
                and ("Inventory selected: ID %d | jumlah: %d"):format(id, countItem(id))
                or "Inventory selected: tidak ada"
        elseif refs.Inv and confirmedId then
            local current = selectedId()
            selectedLabel.Text = ("LOCKED ID: %d | jumlah: %d%s"):format(
                confirmedId, countItem(confirmedId),
                current ~= confirmedId and (" | SELECTED BERUBAH: " .. tostring(current)) or "")
        end
        task.wait(0.25)
    end
end)

print("[APB V4] UI loaded.")
