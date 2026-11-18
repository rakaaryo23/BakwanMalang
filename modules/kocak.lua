-- GemsValue_Recorder.lua
-- Modul pengamatan perubahan angka di tabel/upvalue game.
-- Tujuan: bandingkan kondisi sebelum dan sesudah mengambil gems secara manual.
-- Tidak memanggil fungsi takeDrop, tidak mengubah inventory, dan tidak mengirim remote.

return function(Hub)
    assert(Hub and type(Hub.RegisterTab) == "function", "Hub.RegisterTab tidak ditemukan")

    Hub.RegisterTab("Gems Recorder", function(page, Hub)
        local destroyed = false
        local connections = {}
        local baseline = nil
        local latest = nil
        local logLines = {}
        local status

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

        local function addLog(s)
            local line = os.date("%H:%M:%S") .. " | " .. tostring(s)
            logLines[#logLines + 1] = line
            print("[GEMS RECORDER] " .. line)
        end

        local function getGC()
            if type(getgc) ~= "function" then
                return nil, "getgc tidak tersedia"
            end
            local ok, objects = pcall(getgc, true)
            if not ok or type(objects) ~= "table" then
                return nil, "getgc(true) gagal: " .. tostring(objects)
            end
            return objects
        end

        local function getFunctionUpvalues(fn)
            local out = {}
            if debug and type(debug.getupvalues) == "function" then
                local ok, values = pcall(debug.getupvalues, fn)
                if ok and type(values) == "table" then
                    for k, v in pairs(values) do out[k] = v end
                end
            else
                local getter = (debug and debug.getupvalue) or getupvalue
                if type(getter) == "function" then
                    for i = 1, 80 do
                        local ok, name, value = pcall(getter, fn, i)
                        if not ok or name == nil then break end
                        out[name .. "#" .. i] = value
                    end
                end
            end
            return out
        end

        -- Snapshot menyimpan angka yang ditemukan di tabel GC dan upvalue fungsi.
        -- Referensi owner dipertahankan agar nilai sebelum/sesudah bisa dibandingkan.
        local function takeSnapshot(label)
            local objects, err = getGC()
            if not objects then return nil, err end

            local snap = {
                label = label,
                time = os.clock(),
                values = {},
                tablesSeen = 0,
                functionsSeen = 0,
                numbersSeen = 0,
            }

            local function put(owner, key, value, path)
                if type(value) ~= "number" then return end
                local bucket = snap.values[owner]
                if not bucket then
                    bucket = {}
                    snap.values[owner] = bucket
                end
                bucket[key] = { value = value, path = path }
                snap.numbersSeen = snap.numbersSeen + 1
            end

            local function scanTable(root, rootName)
                if type(root) ~= "table" then return end
                local visited = {}
                local function walk(t, path, depth)
                    if type(t) ~= "table" or visited[t] or depth > 3 then return end
                    visited[t] = true
                    snap.tablesSeen = snap.tablesSeen + 1

                    local ok, entries = pcall(function()
                        local copy = {}
                        for k, v in pairs(t) do
                            copy[#copy + 1] = {k, v}
                        end
                        return copy
                    end)
                    if not ok or type(entries) ~= "table" then return end

                    for _, pair in ipairs(entries) do
                        local k, v = pair[1], pair[2]
                        local keyText = tostring(k)
                        local itemPath = path .. "[" .. keyText .. "]"
                        if type(v) == "number" then
                            put(t, k, v, itemPath)
                        elseif type(v) == "table" then
                            walk(v, itemPath, depth + 1)
                        end
                    end
                end
                walk(root, rootName, 1)
            end

            for index, obj in ipairs(objects) do
                if type(obj) == "table" then
                    scanTable(obj, "GC_TABLE#" .. index)
                elseif type(obj) == "function" then
                    snap.functionsSeen = snap.functionsSeen + 1
                    local ups = getFunctionUpvalues(obj)
                    for key, value in pairs(ups) do
                        if type(value) == "number" then
                            put(obj, "UPVALUE:" .. tostring(key), value,
                                "FUNCTION#" .. index .. ".upvalue[" .. tostring(key) .. "]")
                        elseif type(value) == "table" then
                            scanTable(value, "FUNCTION#" .. index .. ".upvalue[" .. tostring(key) .. "]")
                        end
                    end
                end
            end

            return snap
        end

        local function setStatus(s)
            if status then status.Text = "Status: " .. s end
        end

        local function captureBaseline()
            setStatus("mengambil baseline... tunggu sebentar")
            task.spawn(function()
                local snap, err = takeSnapshot("BEFORE")
                if destroyed then return end
                if not snap then
                    setStatus("gagal: " .. tostring(err))
                    return
                end
                baseline = snap
                latest = nil
                logLines = {}
                addLog(("BASELINE tersimpan | tables=%d functions=%d numeric=%d")
                    :format(snap.tablesSeen, snap.functionsSeen, snap.numbersSeen))
                setStatus(("baseline siap | %d angka dipantau. Sekarang ambil 1 gems secara manual.")
                    :format(snap.numbersSeen))
            end)
        end

        local function captureAfter()
            if not baseline then
                setStatus("ambil BASELINE dulu")
                return
            end
            setStatus("merekam kondisi sesudah... tunggu sebentar")
            task.spawn(function()
                local snap, err = takeSnapshot("AFTER")
                if destroyed then return end
                if not snap then
                    setStatus("gagal: " .. tostring(err))
                    return
                end
                latest = snap
                local changes, added, removed = {}, 0, 0

                for owner, beforeBucket in pairs(baseline.values) do
                    local afterBucket = snap.values[owner]
                    for key, beforeEntry in pairs(beforeBucket) do
                        local afterEntry = afterBucket and afterBucket[key]
                        if afterEntry and afterEntry.value ~= beforeEntry.value then
                            changes[#changes + 1] = {
                                path = afterEntry.path or beforeEntry.path,
                                before = beforeEntry.value,
                                after = afterEntry.value,
                                delta = afterEntry.value - beforeEntry.value,
                            }
                        elseif not afterEntry then
                            removed = removed + 1
                        end
                    end
                end

                for owner, afterBucket in pairs(snap.values) do
                    local beforeBucket = baseline.values[owner]
                    for key, afterEntry in pairs(afterBucket) do
                        if not (beforeBucket and beforeBucket[key]) then
                            added = added + 1
                        end
                    end
                end

                addLog(("AFTER tersimpan | tables=%d functions=%d numeric=%d")
                    :format(snap.tablesSeen, snap.functionsSeen, snap.numbersSeen))
                addLog(("PERUBAHAN ANGKA: %d | field hilang: %d | field baru: %d")
                    :format(#changes, removed, added))

                table.sort(changes, function(a, b)
                    return math.abs(a.delta) > math.abs(b.delta)
                end)

                local limit = math.min(#changes, 150)
                for i = 1, limit do
                    local c = changes[i]
                    addLog(("%03d | %s | %s -> %s | delta=%s")
                        :format(i, c.path, tostring(c.before), tostring(c.after), tostring(c.delta)))
                end
                if #changes > limit then
                    addLog(("... %d perubahan lain tidak ditampilkan"):format(#changes - limit))
                end

                if #changes == 0 then
                    setStatus("tidak ada angka yang berubah. Coba ulangi dengan baseline baru.")
                else
                    setStatus(("%d perubahan angka ditemukan. Tekan COPY LOG untuk menyalin.")
                        :format(#changes))
                end
            end)
        end

        local function copyLog()
            local text = table.concat(logLines, "\n")
            if text == "" then
                setStatus("belum ada log")
                return
            end
            if type(setclipboard) == "function" then
                local ok = pcall(setclipboard, text)
                setStatus(ok and "log disalin ke clipboard" or "gagal menyalin clipboard")
            elseif type(toclipboard) == "function" then
                local ok = pcall(toclipboard, text)
                setStatus(ok and "log disalin ke clipboard" or "gagal menyalin clipboard")
            else
                setStatus("clipboard tidak didukung executor; log tersedia di console")
            end
        end

        create("TextLabel", {
            Size = UDim2.new(1, -12, 0, 28),
            BackgroundTransparency = 1,
            Text = "GEMS VALUE RECORDER",
            TextColor3 = Color3.fromRGB(240, 242, 248),
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, page)

        status = create("TextLabel", {
            Position = UDim2.fromOffset(0, 32),
            Size = UDim2.new(1, -12, 0, 48),
            BackgroundTransparency = 1,
            Text = "Status: siap | ambil baseline sebelum mengambil gems",
            TextColor3 = Color3.fromRGB(190, 195, 205),
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, page)

        local beforeButton = create("TextButton", {
            Position = UDim2.fromOffset(0, 88),
            Size = UDim2.fromOffset(145, 36),
            BackgroundColor3 = Color3.fromRGB(35, 115, 170),
            BorderSizePixel = 0,
            Text = "1. BASELINE",
            TextColor3 = Color3.new(1, 1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
        }, page)

        local afterButton = create("TextButton", {
            Position = UDim2.fromOffset(153, 88),
            Size = UDim2.fromOffset(145, 36),
            BackgroundColor3 = Color3.fromRGB(35, 145, 92),
            BorderSizePixel = 0,
            Text = "2. AFTER TAKE",
            TextColor3 = Color3.new(1, 1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
        }, page)

        local copyButton = create("TextButton", {
            Position = UDim2.fromOffset(0, 132),
            Size = UDim2.fromOffset(145, 34),
            BackgroundColor3 = Color3.fromRGB(75, 80, 95),
            BorderSizePixel = 0,
            Text = "COPY LOG",
            TextColor3 = Color3.new(1, 1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
        }, page)

        for _, button in ipairs({beforeButton, afterButton, copyButton}) do
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 6)
            c.Parent = button
        end

        track(beforeButton.Activated:Connect(captureBaseline))
        track(afterButton.Activated:Connect(captureAfter))
        track(copyButton.Activated:Connect(copyLog))

        local function cleanup()
            if destroyed then return end
            destroyed = true
            for _, c in ipairs(connections) do
                pcall(function() c:Disconnect() end)
            end
            table.clear(connections)
        end

        if type(Hub.RegisterCleanup) == "function" then
            Hub.RegisterCleanup(cleanup)
        end
    end)
end
