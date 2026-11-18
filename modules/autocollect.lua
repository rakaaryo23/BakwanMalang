-- DropList_Scanner.lua
-- Read-only scanner untuk daftar drop GrowBlox.
-- Tidak mengambil drop, tidak mengubah inventory, dan tidak memanggil remote.

return function(Hub)
    assert(Hub and type(Hub.RegisterTab) == "function", "Hub.RegisterTab tidak ditemukan")

    Hub.RegisterTab("Drop Scanner", function(page, Hub)
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local destroyed = false
        local connections = {}
        local refs = { World = nil }
        local Drops = { list = nil, update = nil }
        local rows = {}
        local lastText = ""
        local status, result

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

        local function raw(t, k)
            if type(t) ~= "table" then return nil end
            local ok, value = pcall(rawget, t, k)
            return ok and value or nil
        end

        local function getUpvalues(fn)
            if debug and debug.getupvalues then
                local ok, ups = pcall(debug.getupvalues, fn)
                if ok and type(ups) == "table" then return ups end
            end
            local out = {}
            local getter = (debug and debug.getupvalue) or getupvalue
            if type(getter) == "function" then
                for i = 1, 80 do
                    local ok, name, value = pcall(getter, fn, i)
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

        local function discoverWorld()
            if type(getgc) ~= "function" then
                return false, "Executor tidak menyediakan getgc"
            end
            local ok, objects = pcall(getgc, true)
            if not ok or type(objects) ~= "table" then
                return false, "getgc(true) gagal: " .. tostring(objects)
            end

            refs.World = nil
            for _, obj in ipairs(objects) do
                if type(obj) == "table"
                    and type(raw(obj, "fg")) == "table"
                    and type(raw(obj, "bg")) == "table"
                    and type(raw(obj, "w")) == "number"
                    and type(raw(obj, "h")) == "number"
                    and raw(obj, "spawn") ~= nil then
                    refs.World = obj
                    break
                end
            end

            if not refs.World then
                return false, "World table tidak ditemukan"
            end
            return true, "World ditemukan"
        end

        local function findDropRefs()
            local w = refs.World
            local dropListFn = w and rawget(w, "dropList")
            if type(dropListFn) == "function" then
                local good, list = pcall(dropListFn)
                if good and type(list) == "table" then
                    Drops.list = list
                    return true
                end
            end

            Drops.list = nil
            local dropTaken = w and rawget(w, "dropTaken")
            if type(dropTaken) == "function" then
                for _, upvalue in pairs(getUpvalues(dropTaken)) do
                    if isDropList(upvalue) then
                        Drops.list = upvalue
                        break
                    end
                end
            end

            if not Drops.list then
                local remotes = ReplicatedStorage:FindFirstChild("WorldRemotes")
                local event = remotes and remotes:FindFirstChild("DropTaken")
                if event and getconnections then
                    local good, cons = pcall(getconnections, event.OnClientEvent)
                    if good and type(cons) == "table" then
                        for _, connection in ipairs(cons) do
                            local okf, fn = pcall(function() return connection.Function end)
                            if okf and type(fn) == "function" then
                                for _, upvalue in pairs(getUpvalues(fn)) do
                                    if isDropList(upvalue) then
                                        Drops.list = upvalue
                                        break
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

        local function value(v)
            if v == nil then return "nil" end
            local t = typeof(v)
            if t == "Vector2" or t == "Vector3" then
                return tostring(v)
            end
            if t == "Instance" then
                return v.ClassName .. ":" .. v.Name
            end
            return tostring(v)
        end

        local function scan()
            status.Text = "Status: mencari World..."
            local ok, message = discoverWorld()
            if not ok then
                status.Text = "Status: " .. message
                return
            end

            if not findDropRefs() then
                status.Text = "Status: daftar drop tidak ditemukan"
                return
            end

            local list = Drops.list
            local output = {}
            local counts = {}
            local total = 0

            for index, d in ipairs(list) do
                if type(d) == "table" then
                    total = total + 1
                    local id = raw(d, "id")
                    local n = raw(d, "n")
                    local uid = raw(d, "uid")
                    local x = raw(d, "x")
                    local y = raw(d, "y")
                    local key = tostring(id)
                    counts[key] = (counts[key] or 0) + 1

                    local line = ("#%d | UID=%s | ID=%s | QTY=%s | X=%s | Y=%s | armed=%s | taking=%s | pending=%s | display=%s")
                        :format(index, value(uid), value(id), value(n), value(x), value(y),
                            value(raw(d, "armed")), value(raw(d, "taking")),
                            value(raw(d, "pending")), value(raw(d, "display")))
                    output[#output + 1] = line
                end
            end

            local summary = {}
            for id, count in pairs(counts) do
                summary[#summary + 1] = "ID " .. id .. ": " .. count
            end
            table.sort(summary)

            local lines = {
                "DROP SCAN | total=" .. total,
                "Ringkasan: " .. (#summary > 0 and table.concat(summary, " ; ") or "(kosong)"),
                "----------------------------------------",
            }
            for _, line in ipairs(output) do
                lines[#lines + 1] = line
            end

            lastText = table.concat(lines, "\n")
            result.Text = lastText
            status.Text = ("Status: scan selesai | %d drop ditemukan"):format(total)
            print("[DROP SCANNER]\n" .. lastText)
        end

        local function copyResults()
            if lastText == "" then
                status.Text = "Status: scan dulu sebelum copy"
                return
            end
            local clipboard = setclipboard or toclipboard
            if type(clipboard) == "function" then
                local ok = pcall(clipboard, lastText)
                status.Text = ok and "Status: hasil scan disalin" or "Status: gagal menyalin"
            else
                status.Text = "Status: clipboard tidak tersedia; hasil ada di console"
            end
        end

        create("TextLabel", {
            Size = UDim2.new(1, -12, 0, 28),
            BackgroundTransparency = 1,
            Text = "DROP LIST SCANNER | READ ONLY",
            TextColor3 = Color3.fromRGB(240, 242, 248),
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, page)

        status = create("TextLabel", {
            Position = UDim2.fromOffset(0, 31),
            Size = UDim2.new(1, -12, 0, 34),
            BackgroundTransparency = 1,
            Text = "Status: siap scan",
            TextColor3 = Color3.fromRGB(185, 190, 202),
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, page)

        local scanButton = create("TextButton", {
            Position = UDim2.fromOffset(0, 70),
            Size = UDim2.fromOffset(140, 34),
            BackgroundColor3 = Color3.fromRGB(35, 115, 170),
            BorderSizePixel = 0,
            Text = "SCAN DROP LIST",
            TextColor3 = Color3.new(1, 1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
        }, page)

        local copyButton = create("TextButton", {
            Position = UDim2.fromOffset(148, 70),
            Size = UDim2.fromOffset(140, 34),
            BackgroundColor3 = Color3.fromRGB(75, 80, 95),
            BorderSizePixel = 0,
            Text = "COPY RESULTS",
            TextColor3 = Color3.new(1, 1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
        }, page)

        local scroll = create("ScrollingFrame", {
            Position = UDim2.fromOffset(0, 112),
            Size = UDim2.new(1, -12, 1, -118),
            BackgroundColor3 = Color3.fromRGB(25, 28, 35),
            BorderSizePixel = 0,
            ScrollBarThickness = 6,
            CanvasSize = UDim2.fromOffset(0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
        }, page)

        result = create("TextLabel", {
            Size = UDim2.new(1, -12, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Position = UDim2.fromOffset(6, 6),
            BackgroundTransparency = 1,
            Text = "Belum ada hasil.\nTekan SCAN DROP LIST.",
            TextColor3 = Color3.fromRGB(225, 228, 235),
            Font = Enum.Font.Code,
            TextSize = 11,
            TextWrapped = false,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
        }, scroll)

        for _, button in ipairs({scanButton, copyButton}) do
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 6)
            corner.Parent = button
        end

        track(scanButton.Activated:Connect(function()
            if destroyed then return end
            local ok, err = pcall(scan)
            if not ok then status.Text = "Status: scan error - " .. tostring(err) end
        end))
        track(copyButton.Activated:Connect(copyResults))

        local function cleanup()
            if destroyed then return end
            destroyed = true
            for _, connection in ipairs(connections) do
                pcall(function() connection:Disconnect() end)
            end
            table.clear(connections)
        end

        if type(Hub.RegisterCleanup) == "function" then
            Hub.RegisterCleanup(cleanup)
        end
    end)
end
