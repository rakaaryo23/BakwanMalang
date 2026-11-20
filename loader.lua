
local URL = "https://raw.githubusercontent.com/rakaaryo23/BakwanMalang/main/main.lua"

local success, source = pcall(function()
    return game:HttpGet(URL)
end)

if not success then
    warn("[APB Loader] Gagal mengambil script: " .. tostring(source))
    return
end

local compileSuccess, scriptFunction = pcall(loadstring, source)

if not compileSuccess or type(scriptFunction) ~= "function" then
    warn("[APB Loader] Gagal memuat kode: " .. tostring(scriptFunction))
    return
end

local runSuccess, runError = pcall(scriptFunction)

if not runSuccess then
    warn("[APB Loader] Error saat menjalankan script: " .. tostring(runError))
end
