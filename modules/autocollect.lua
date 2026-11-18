--==================================================
-- MODULE: AUTOCOLLECT FUNCTION TRACER (READ-ONLY)
-- Snapshots GC function metadata/upvalues before and after
-- one Dirt Seed pickup. Does NOT hook, call, or fire game functions.
--==================================================
return function(Hub)
    Hub.RegisterTab("AutoCollect Function Tracer", function(page)
        local Theme = {
            Panel = Color3.fromRGB(239,194,207), Accent = Color3.fromRGB(171,91,119),
            Text = Color3.fromRGB(76,43,57), Muted = Color3.fromRGB(139,96,111),
            White = Color3.fromRGB(255,249,251), Green = Color3.fromRGB(55,140,90),
            Red = Color3.fromRGB(180,65,75)
        }
        local destroyed, recording = false, false
        local lines, connections = {}, {}
        local output, status, startButton, stopButton
        local before, stateRef, inventoryRef, lastCount
        local startedAt, lastSample = 0, 0
        local initialCount
        local ITEM_ID, MAX_FUNCTIONS, SAMPLE_INTERVAL = 3, 12000, 0.20
        local keywords = {"collect","pickup","pick_up","take","grab","item","drop","loot","interact","touch","claim","receive","inventory","seed","gem"}

        local function create(class, props, parent)
            local o = Instance.new(class)
            for k,v in pairs(props or {}) do o[k] = v end
            o.Parent = parent
            return o
        end
        local function corner(o, r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 7); c.Parent=o end
        local function safe(v)
            local ok,s=pcall(tostring,v); if not ok then return "?" end
            return s:gsub("\n"," "):gsub("\r"," "):sub(1,150)
        end
        local function log(msg)
            local prefix = recording and ("+%.2fs"):format(os.clock()-startedAt) or os.date("%H:%M:%S")
            lines[#lines+1] = prefix .. " | " .. safe(msg)
            while #lines > 1800 do table.remove(lines,1) end
            if output and output.Parent then output.Text=table.concat(lines,"\n"); output.CursorPosition=-1 end
            print("[AC-FTRACE] " .. lines[#lines])
        end
        local function statusText(s, color) status.Text="Status: "..s; status.TextColor3=color or Theme.Text end
        local function raw(t,k) if type(t)~="table" then return nil end; local ok,v=pcall(rawget,t,k); return ok and v or nil end
        local function getUpvalues(fn)
            local getter = (debug and debug.getupvalues) or getupvalues
            if type(getter)~="function" then return nil end
            local ok, vals=pcall(getter,fn); if ok and type(vals)=="table" then return vals end
            return nil
        end
        local function getConstants(fn)
            local getter=(debug and debug.getconstants) or getconstants
            if type(getter)~="function" then return nil end
            local ok,vals=pcall(getter,fn); if ok and type(vals)=="table" then return vals end
            return nil
        end
        local function valueSig(v)
            local t=type(v)
            if t=="nil" or t=="number" or t=="string" or t=="boolean" then return t..":"..safe(v) end
            if t=="table" then
                local n=0; local sample={}
                for k,x in pairs(v) do
                    n+=1
                    if #sample<5 then sample[#sample+1]=safe(k).."="..(type(x)=="table" and "<table>" or safe(x)) end
                    if n>=5000 then break end
                end
                table.sort(sample)
                return "table#"..n.."{"..table.concat(sample,";").."}"
            end
            return t..":"..safe(v)
        end
        local function containsKeyword(s)
            s=string.lower(safe(s))
            for _,kw in ipairs(keywords) do if string.find(s,kw,1,true) then return true end end
            return false
        end
        local function discoverStateAndInventory()
            stateRef, inventoryRef=nil,nil
            if type(getgc)~="function" then return end
            local ok,objs=pcall(getgc,true); if not ok or type(objs)~="table" then return end
            local bestScore=-1
            for _,obj in ipairs(objs) do
                if type(obj)=="table" then
                    local sf=raw(obj,"state")
                    if not stateRef and type(sf)=="function" then
                        local good,st=pcall(sf)
                        if good and type(st)=="table" and type(st.x)=="number" and type(st.y)=="number" and st.facing~=nil and st.vx~=nil then stateRef=sf end
                    end
                    local slots,cap=raw(obj,"slots"),raw(obj,"capacity")
                    if type(slots)=="table" and type(cap)=="number" and cap>=0 and cap<=10000 then
                        local score=0
                        for _,slot in pairs(slots) do if type(slot)=="table" and tonumber(raw(slot,"id")) then score+=2 end end
                        if score>bestScore then bestScore=score; inventoryRef=obj end
                    end
                end
            end
        end
        local function count3()
            if not inventoryRef then return nil end
            local slots=raw(inventoryRef,"slots"); if type(slots)~="table" then return nil end
            local n=0
            for _,slot in pairs(slots) do if type(slot)=="table" and tonumber(raw(slot,"id"))==ITEM_ID then n+=tonumber(raw(slot,"n")) or 0 end end
            return n
        end
        local function snapshotFunctions()
            local snap, total={},0
            if type(getgc)~="function" then return snap,0,"getgc tidak tersedia" end
            local ok,objs=pcall(getgc,true); if not ok or type(objs)~="table" then return snap,0,"getgc(true) gagal" end
            local info=(debug and debug.info) or (debug and debug.getinfo)
            if type(info)~="function" then return snap,0,"debug.info/getinfo tidak tersedia" end
            for _,fn in ipairs(objs) do
                if type(fn)=="function" and total<MAX_FUNCTIONS then
                    total+=1
                    local okN,name=pcall(info,fn,"n"); if not okN then name="?" end
                    local okA,args,vararg=pcall(info,fn,"a"); if not okA then args="?"; vararg="?" end
                    local consts=getConstants(fn) or {}
                    local ups=getUpvalues(fn) or {}
                    local cparts, uparts={},{}
                    local hit=false
                    for _,v in pairs(consts) do
                        local sv=safe(v); cparts[#cparts+1]=sv
                        if containsKeyword(sv) then hit=true end
                    end
                    for k,v in pairs(ups) do
                        uparts[safe(k)]=valueSig(v)
                        if containsKeyword(k) or containsKeyword(v) then hit=true end
                    end
                    local fname=safe(name)
                    if containsKeyword(fname) then hit=true end
                    table.sort(cparts)
                    local key=tostring(fn)
                    snap[key]={fn=fn,name=fname,args=safe(args),vararg=safe(vararg),constants=table.concat(cparts,"|"),upvalues=uparts,keyword=hit}
                end
            end
            return snap,total,nil
        end
        local function reportSnapshotDiff()
            local after,total,err=snapshotFunctions()
            if err then log("POST-SCAN ERROR: "..err); return end
            local changed, candidates, added=0,0,0
            for key,a in pairs(after) do
                local b=before and before[key]
                if not b then
                    added+=1
                    if a.keyword then log(("NEW FUNCTION CANDIDATE name=%s args=%s const={%s}"):format(a.name,a.args,a.constants:sub(1,260))); candidates+=1 end
                else
                    local diffs={}
                    if a.keyword then candidates+=1 end
                    for uk,av in pairs(a.upvalues) do
                        local bv=b.upvalues[uk]
                        if bv~=av then diffs[#diffs+1]=uk..": "..safe(bv or "<absent>").." -> "..safe(av) end
                    end
                    for uk,bv in pairs(b.upvalues) do if a.upvalues[uk]==nil then diffs[#diffs+1]=uk..": "..safe(bv).." -> <absent>" end end
                    if #diffs>0 then
                        changed+=1
                        log(("UPVALUE CHANGED | %s | args=%s | %s"):format(a.name,a.args,table.concat(diffs," ; "):sub(1,650)))
                    end
                end
            end
            log(("POST-SCAN SUMMARY | functions=%d | changed-upvalue-functions=%d | new-functions=%d | keyword-candidates=%d"):format(total,changed,added,candidates))
            log("CATATAN: perubahan upvalue/kandidat bukan bukti fungsi dipanggil; ini petunjuk observasional, bukan call trace.")
        end
        local function start()
            if recording then return end
            lines={}; output.Text=""; startedAt=os.clock(); lastSample=0
            discoverStateAndInventory()
            local n, count, err=snapshotFunctions()
            before=n
            log("BASELINE: function snapshot="..count..(err and (" | "..err) or ""))
            log("debug.getconstants="..tostring(type((debug and debug.getconstants) or getconstants)=="function").." | debug.getupvalues="..tostring(type((debug and debug.getupvalues) or getupvalues)=="function"))
            log("state()="..tostring(stateRef~=nil).." | inventory="..tostring(inventoryRef~=nil))
            lastCount=count3(); initialCount=lastCount; log("INVENTORY ID 3 BEFORE="..tostring(initialCount))
            recording=true; statusText("RECORDING - ambil SATU Dirt Seed ID 3",Theme.Green)
            log("=== ACTION WINDOW OPEN ===")
            log("Sekarang lakukan satu kali take item. Setelah inventory bertambah, tekan STOP + ANALYZE.")
            startButton.Text="RECORDING..."
        end
        local function stop()
            if not recording then return end
            recording=false; statusText("ANALYZING",Theme.Red); stopButton.Text="ANALYZING..."
            log("=== ACTION WINDOW CLOSED ===")
            local now=count3(); log("INVENTORY ID 3 AFTER="..tostring(now).." | delta="..tostring(now and initialCount and (now-initialCount) or "unknown"))
            reportSnapshotDiff()
            statusText("STOPPED - hasil analisis tersedia",Theme.Green)
            startButton.Text="START NEW TEST"; stopButton.Text="STOP + ANALYZE"
        end

        create("UIListLayout",{Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder},page)
        create("TextLabel",{Size=UDim2.new(1,0,0,58),BackgroundTransparency=1,Text="FUNCTION TRACER | Snapshot fungsi GC + constants + upvalues sebelum/sesudah take Dirt Seed ID 3. Tidak memasang hook, tidak memanggil fungsi game, tidak mengirim remote.",TextColor3=Theme.Text,Font=Enum.Font.Gotham,TextSize=10,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left},page)
        status=create("TextLabel",{Size=UDim2.new(1,0,0,27),BackgroundColor3=Theme.Panel,BorderSizePixel=0,Text="Status: siap",TextColor3=Theme.Text,Font=Enum.Font.GothamBold,TextSize=10,TextXAlignment=Enum.TextXAlignment.Left},page); corner(status,6)
        startButton=create("TextButton",{Size=UDim2.new(1,0,0,36),BackgroundColor3=Theme.Green,BorderSizePixel=0,Text="START RECORDING",TextColor3=Theme.White,Font=Enum.Font.GothamBold,TextSize=11},page); corner(startButton,7)
        stopButton=create("TextButton",{Size=UDim2.new(1,0,0,36),BackgroundColor3=Theme.Red,BorderSizePixel=0,Text="STOP + ANALYZE",TextColor3=Theme.White,Font=Enum.Font.GothamBold,TextSize=11},page); corner(stopButton,7)
        local copyButton=create("TextButton",{Size=UDim2.new(1,0,0,36),BackgroundColor3=Theme.Accent,BorderSizePixel=0,Text="COPY FEEDBACK",TextColor3=Theme.White,Font=Enum.Font.GothamBold,TextSize=11},page); corner(copyButton,7)
        local clearButton=create("TextButton",{Size=UDim2.new(1,0,0,32),BackgroundColor3=Theme.Panel,BorderSizePixel=0,Text="CLEAR FEEDBACK",TextColor3=Theme.Text,Font=Enum.Font.GothamBold,TextSize=10},page); corner(clearButton,7)
        output=create("TextBox",{Size=UDim2.new(1,0,0,340),BackgroundColor3=Color3.fromRGB(255,245,248),BorderSizePixel=0,Text="Tekan START, ambil 1 Dirt Seed ID 3, lalu STOP + ANALYZE dan COPY FEEDBACK.",TextColor3=Theme.Text,PlaceholderColor3=Theme.Muted,Font=Enum.Font.Code,TextSize=10,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,TextWrapped=false,MultiLine=true,ClearTextOnFocus=false,TextEditable=false},page); corner(output,7)
        connections[#connections+1]=startButton.Activated:Connect(start)
        connections[#connections+1]=stopButton.Activated:Connect(stop)
        connections[#connections+1]=copyButton.Activated:Connect(function()
            local copier=setclipboard or toclipboard
            if type(copier)=="function" then local ok,err=pcall(copier,table.concat(lines,"\n")); statusText(ok and "feedback copied" or ("copy gagal: "..safe(err)),ok and Theme.Green or Theme.Red) else statusText("clipboard tidak tersedia",Theme.Red) end
        end)
        connections[#connections+1]=clearButton.Activated:Connect(function() if recording then recording=false end; lines={}; output.Text=""; statusText("feedback cleared") end)
        task.spawn(function()
            while not destroyed and not Hub.IsClosing() do
                if recording and os.clock()-lastSample>=SAMPLE_INTERVAL then
                    lastSample=os.clock()
                    local current=count3()
                    if current~=nil and lastCount~=nil and current~=lastCount then
                        log(("INVENTORY CHANGE ID 3 | %d -> %d | delta=%+d"):format(lastCount,current,current-lastCount))
                    end
                    lastCount=current
                    if stateRef then
                        local ok,s=pcall(stateRef)
                        if ok and type(s)=="table" and type(s.x)=="number" and type(s.y)=="number" then
                            log(("PLAYER SAMPLE X=%.4f Y=%.4f VEL=%s,%s facing=%s"):format(s.x,s.y,safe(s.vx),safe(s.vy),safe(s.facing)))
                        end
                    end
                end
                task.wait(0.05)
            end
        end)
        local function cleanup()
            if destroyed then return end; destroyed=true; recording=false
            for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
            table.clear(connections)
        end
        Hub.RegisterCleanup(cleanup)
        log("Module aktif. Catatan: tanpa hooking/tracing runtime, executor Lua biasa tidak bisa menjamin nama fungsi yang benar-benar dieksekusi. Script ini membandingkan metadata/upvalues sebelum dan sesudah pickup.")
    end)
end
