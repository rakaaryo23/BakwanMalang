--==================================================
-- MODULE: AUTO COLLECT SCANNER (GROWBLOX HUB)
-- Read-only diagnostic scanner.
-- Does NOT invoke game functions or fire remotes.
--==================================================

return function(Hub)
    Hub.RegisterTab("AutoCollect Scanner", function(page)
        local Players = game:GetService("Players")
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local Workspace = game:GetService("Workspace")
        local LocalPlayer = Players.LocalPlayer

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

        local destroyed = false
        local lines = {}
        local output
        local MAX_LOG_LINES = 500
        local MAX_GC_OBJECTS = 30000
        local MAX_DESCENDANTS = 15000

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

        local function append(message)
            if destroyed or Hub.IsClosing() then return end
            local stamp = os.date("%H:%M:%S")
            table.insert(lines, ("[%s] %s"):format(stamp, tostring(message)))
            while #lines > MAX_LOG_LINES do
                table.remove(lines, 1)
            end
            if output and output.Parent then
                output.Text = table.concat(lines, "\n")
                output.CursorPosition = -1
            end
            print("[AC-SCANNER] " .. tostring(message))
        end

        local function clearLog()
            table.clear(lines)
            if output and output.Parent then output.Text = "" end
            append("Log dibersihkan.")
        end

        local function makeButton(label, color, parent)
            local b = create("TextButton", {
                Size = UDim2.new(1, 0, 0, 34),
                BackgroundColor3 = color or Theme.Accent,
                BorderSizePixel = 0,
                Text = label,
                TextColor3 = Theme.White,
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                AutoButtonColor = true,
            }, parent or page)
            corner(b, 7)
            return b
        end

        local layout = create("UIListLayout", {
            Padding = UDim.new(0, 7),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, page)

        local intro = create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 48),
            BackgroundTransparency = 1,
            Text = "READ-ONLY SCANNER | Mencari petunjuk fungsi, remote, dan objek dropped item. Tidak menjalankan remote apa pun.",
            TextColor3 = Theme.Text,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
        }, page)

        local status = create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 25),
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            Text = "Status: siap",
            TextColor3 = Theme.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, page)
        corner(status, 6)

        output = create("TextBox", {
            Size = UDim2.new(1, 0, 0, 260),
            BackgroundColor3 = Color3.fromRGB(255, 245, 248),
            BorderSizePixel = 0,
            Text = "[AC-SCANNER] Siap. Tekan salah satu tombol scan.\n",
            TextColor3 = Theme.Text,
            PlaceholderColor3 = Theme.Muted,
            Font = Enum.Font.Code,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = false,
            MultiLine = true,
            ClearTextOnFocus = false,
            TextEditable = false,
        }, page)
        corner(output, 7)

        local function setStatus(value)
            status.Text = "Status: " .. tostring(value)
        end

        local function getConstants(fn)
            local getter = (debug and debug.getconstants) or getconstants or getconsts
            if type(getter) ~= "function" then return nil end
            local ok, result = pcall(getter, fn)
            return ok and type(result) == "table" and result or nil
        end

        local function getUpvalues(fn)
            local getter = (debug and debug.getupvalues) or getupvalues or getupvals
            if type(getter) ~= "function" then return nil end
            local ok, result = pcall(getter, fn)
            return ok and type(result) == "table" and result or nil
        end

        local function functionInfo(fn)
            local name, params, variadic = "?", "?", "?"
            if debug and type(debug.info) == "function" then
                local okN, n = pcall(debug.info, fn, "n")
                local okA, a, v = pcall(debug.info, fn, "a")
                if okN and n ~= nil and n ~= "" then name = tostring(n) end
                if okA then
                    params = tostring(a)
                    variadic = tostring(v)
                end
            end
            return name, params, variadic
        end

        local KEYWORDS = {
            "collect", "pickup", "pick_up", "take", "grab", "loot",
            "drop", "dropped", "item", "gem", "seed", "harvest",
            "touch", "proximity", "inventory", "remove", "claim",
            "receive", "reward", "spawn", "worlditem", "world_item",
        }

        local function keywordHits(value)
            local s = string.lower(tostring(value))
            local hits = {}
            for _, word in ipairs(KEYWORDS) do
                if string.find(s, word, 1, true) then
                    hits[#hits + 1] = word
                end
            end
            return hits
        end

        local function safeString(value, limit)
            local ok, result = pcall(tostring, value)
            if not ok then return "<tostring error>" end
            result = result:gsub("\n", " "):gsub("\r", " ")
            limit = limit or 110
            if #result > limit then result = result:sub(1, limit) .. "..." end
            return result
        end

        local function scanCapabilities()
            append("=== EXECUTOR CAPABILITIES ===")
            local checks = {
                "getgc", "getconstants", "getconsts", "getupvalues",
                "getupvals", "setclipboard", "toclipboard", "gethui",
            }
            for _, name in ipairs(checks) do
                local value = (getgenv and getgenv()[name]) or _G[name]
                append(name .. " = " .. (type(value) == "function" and "AVAILABLE" or "not found"))
            end
            append("debug.info = " .. tostring(debug and type(debug.info) == "function"))
            append("debug.getconstants = " .. tostring(debug and type(debug.getconstants) == "function"))
        end

        local function scanRemotes()
            append("=== REMOTE INSTANCE SCAN ===")
            local total, matched = 0, 0
            local ok, descendants = pcall(function() return game:GetDescendants() end)
            if not ok or type(descendants) ~= "table" then
                append("GAGAL membaca game:GetDescendants(): " .. safeString(descendants))
                return
            end
            for _, obj in ipairs(descendants) do
                total += 1
                if total > MAX_DESCENDANTS then
                    append("Batas descendant tercapai: " .. MAX_DESCENDANTS)
                    break
                end
                if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                    matched += 1
                    local path = "?"
                    pcall(function() path = obj:GetFullName() end)
                    append(("REMOTE %s | %s | %s"):format(obj.ClassName, obj.Name, path))
                end
            end
            append(("Remote ditemukan: %d | descendant diperiksa: %d"):format(matched, math.min(total, MAX_DESCENDANTS)))
            append("Catatan: nama remote saja tidak membuktikan remote tersebut untuk collect.")
        end

        local function scanFunctions()
            append("=== GC FUNCTION SCAN ===")
            local gc = getgc
            if type(gc) ~= "function" then
                append("getgc tidak tersedia di executor ini.")
                return
            end
            local ok, objects = pcall(gc, true)
            if not ok or type(objects) ~= "table" then
                append("getgc(true) gagal: " .. safeString(objects))
                return
            end

            local scanned, matched = 0, 0
            for _, obj in ipairs(objects) do
                if scanned >= MAX_GC_OBJECTS then
                    append("Batas GC tercapai: " .. MAX_GC_OBJECTS)
                    break
                end
                if type(obj) == "function" then
                    scanned += 1
                    local name, params, variadic = functionInfo(obj)
                    local constants = getConstants(obj)
                    local upvalues = getUpvalues(obj)
                    local hits, evidence = {}, {}

                    for _, value in pairs(constants or {}) do
                        local found = keywordHits(value)
                        for _, word in ipairs(found) do hits[word] = true end
                        if #found > 0 then
                            evidence[#evidence + 1] = "const=" .. safeString(value, 70)
                        end
                    end
                    for key, value in pairs(upvalues or {}) do
                        local keyHits = keywordHits(key)
                        local valueHits = keywordHits(value)
                        for _, word in ipairs(keyHits) do hits[word] = true end
                        for _, word in ipairs(valueHits) do hits[word] = true end
                        if #keyHits > 0 or #valueHits > 0 then
                            evidence[#evidence + 1] = "upvalue[" .. safeString(key, 35) .."]=" .. safeString(value, 70)
                        end
                    end
                    for word in pairs(keywordHits(name)) do hits[word] = true end

                    local hitList = {}
                    for word in pairs(hits) do hitList[#hitList + 1] = word end
                    table.sort(hitList)
                    if #hitList > 0 then
                        matched += 1
                        append(("FUNC #%d name=%s args=%s variadic=%s | hits=%s"):format(
                            scanned, name, params, variadic, table.concat(hitList, ",")
                        ))
                        for i = 1, math.min(#evidence, 5) do
                            append("  " .. evidence[i])
                        end
                    end
                end
            end
            append(("Function diperiksa: %d | kandidat keyword: %d"):format(scanned, matched))
            append("Kandidat hanya petunjuk dari nama/constant/upvalue, bukan bukti fungsi collect.")
        end

        local function scanDroppedObjects()
            append("=== WORLD DROPPED-OBJECT NAME SCAN ===")
            local total, matched = 0, 0
            local ok, descendants = pcall(function() return Workspace:GetDescendants() end)
            if not ok or type(descendants) ~= "table" then
                append("GAGAL membaca Workspace: " .. safeString(descendants))
                return
            end
            for _, obj in ipairs(descendants) do
                total += 1
                if total > MAX_DESCENDANTS then
                    append("Batas object Workspace tercapai: " .. MAX_DESCENDANTS)
                    break
                end
                local hits = keywordHits(obj.Name)
                if #hits > 0 then
                    matched += 1
                    local path = "?"
                    pcall(function() path = obj:GetFullName() end)
                    local position = "n/a"
                    pcall(function()
                        if obj:IsA("BasePart") then
                            local p = obj.Position
                            position = ("%.2f, %.2f, %.2f"):format(p.X, p.Y, p.Z)
                        elseif obj:IsA("Model") and obj.PrimaryPart then
                            local p = obj.PrimaryPart.Position
                            position = ("%.2f, %.2f, %.2f"):format(p.X, p.Y, p.Z)
                        end
                    end)
                    append(("OBJECT %s | %s | pos=%s | %s"):format(
                        obj.ClassName, obj.Name, position, path
                    ))
                end
            end
            append(("Object bernama relevan: %d | Workspace diperiksa: %d"):format(
                matched, math.min(total, MAX_DESCENDANTS)
            ))
            append("Catatan: dropped item bisa disimpan sebagai data Lua, bukan Instance bernama di Workspace.")
        end

        local function runScan(label, callback)
            if destroyed or Hub.IsClosing() then return end
            setStatus("scan " .. label .. "...")
            append("----------------------------------------")
            append("MULAI: " .. label)
            task.spawn(function()
                local ok, err = pcall(callback)
                if not ok then append("SCAN ERROR: " .. safeString(err, 300)) end
                if not destroyed and not Hub.IsClosing() then
                    append("SELESAI: " .. label)
                    setStatus("selesai - " .. label)
                end
            end)
        end

        local scanAll = makeButton("SCAN ALL (CAPABILITIES + REMOTES + FUNCTIONS + WORLD)", Theme.Green)
        local scanRemoteButton = makeButton("SCAN REMOTE EVENT / FUNCTION", Theme.Accent)
        local scanFunctionButton = makeButton("SCAN GC FUNCTIONS + CONSTANTS", Theme.Accent)
        local scanWorldButton = makeButton("SCAN WORLD DROPPED-OBJECT NAMES", Theme.Accent)
        local copyButton = makeButton("COPY FEEDBACK", Theme.PanelDark)
        copyButton.TextColor3 = Theme.Text
        local clearButton = makeButton("CLEAR FEEDBACK", Theme.PanelDark)
        clearButton.TextColor3 = Theme.Text

        scanAll.Activated:Connect(function()
            runScan("ALL", function()
                scanCapabilities()
                scanRemotes()
                scanFunctions()
                scanDroppedObjects()
            end)
        end)
        scanRemoteButton.Activated:Connect(function()
            runScan("REMOTES", scanRemotes)
        end)
        scanFunctionButton.Activated:Connect(function()
            runScan("FUNCTIONS", scanFunctions)
        end)
        scanWorldButton.Activated:Connect(function()
            runScan("WORLD OBJECTS", scanDroppedObjects)
        end)
        clearButton.Activated:Connect(clearLog)
        copyButton.Activated:Connect(function()
            local content = table.concat(lines, "\n")
            local copied = false
            if type(setclipboard) == "function" then
                copied = pcall(setclipboard, content)
            elseif type(toclipboard) == "function" then
                copied = pcall(toclipboard, content)
            end
            if copied then
                setStatus("feedback berhasil disalin")
                append("Feedback disalin ke clipboard.")
            else
                setStatus("clipboard API tidak tersedia - salin manual dari kotak output")
                append("Clipboard API tidak tersedia. Tekan lama kotak output untuk menyalin manual jika executor mendukung.")
            end
        end)

        append("Module AutoCollect Scanner aktif.")
        append("Mode READ-ONLY: tidak memanggil fungsi game dan tidak mengirim remote.")
        append("Player: " .. (LocalPlayer and LocalPlayer.Name or "tidak diketahui"))
        append("Tekan SCAN ALL, lalu COPY FEEDBACK dan kirim hasilnya ke chat.")

        local function cleanup()
            if destroyed then return end
            destroyed = true
        end
        Hub.RegisterCleanup(cleanup)
        print("[AutoCollect Scanner] Module loaded.")
    end)
end

--==================================================
-- END MODULE: AUTO COLLECT SCANNER
--==================================================
