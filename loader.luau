repeat task.wait() until game:IsLoaded() and game:GetService("Players").LocalPlayer
repeat task.wait() until game.GameId and game.GameId ~= 0

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local BACKEND_URL = "https://shenky-auth.farialtaff.workers.dev"
local DISCORD_INVITE = "https://discord.gg/shenky"
local universeId = tostring(game.GameId)

local genv = (getgenv and getgenv()) or _G
if genv.__SHENKY_RUNNING then
    local prevHub = genv.__GLOBAL_HUB
    if prevHub and not prevHub._destroyed then
        warn("[Shenky Loader] Previous session detected. Cleaning up before reload...")
        pcall(function()
            if type(prevHub.Destroy) == "function" then
                prevHub:Destroy()
            end
        end)
        task.wait(0.1)
    end
    genv.__SHENKY_RUNNING = nil
end

local Auth = (function()
    local remoteUrls = {
        "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/auth.luau",
    }

    local httpReq = request or http_request or (syn and syn.request)
    for _, url in ipairs(remoteUrls) do
        local body = nil
        if type(httpReq) == "function" then
            local ok, res = pcall(httpReq, { Url = url .. "?t=" .. tostring(os.time()), Method = "GET" })
            if ok and res and (res.StatusCode == 200 or res.Status == 200) then
                body = res.Body or res.body
            end
        end
        if not body then
            local okGet, resGet = pcall(game.HttpGet, game, url .. "?t=" .. tostring(os.time()))
            if okGet and type(resGet) == "string" and #resGet > 0 then
                body = resGet
            end
        end
        if type(body) == "string" and #body > 0 then
            local okComp, fn = pcall(loadstring, body)
            if okComp and type(fn) == "function" then
                local okRun, mod = pcall(fn)
                if okRun and type(mod) == "table" then return mod end
            end
        end
    end
    error("[Shenky Loader] Failed to load authentication library.")
end)()

local hwid = Auth:GetHWID()
local savedKey = Auth:GetSavedKey(universeId)

local function sendAuth(keyToSend)
    local ok, res = Auth:HttpRequest({
        Url = BACKEND_URL .. "/api/auth",
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode({
            universeId = universeId,
            hwid = hwid,
            key = keyToSend or "",
            userId = LocalPlayer.UserId
        })
    })
    if not ok or not res or not res.Body then
        return false, nil, "Failed to connect to authentication server."
    end
    local okDec, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
    if not okDec or type(data) ~= "table" then
        return false, nil, "Invalid server response."
    end
    return data.success, data, data.message
end

local function executePayload(src, gameName, tier)
    genv.__SHENKY_RUNNING = true
    genv.ShenkyTier = tostring(tier or "public")
    local fn, compileErr = loadstring(src)
    if fn then
        task.spawn(fn)
    else
        genv.__SHENKY_RUNNING = nil
        warn("[Shenky Loader] Compile error: " .. tostring(compileErr))
    end
end

local success, authData, msg = sendAuth(savedKey)

if authData and authData.kick then
    LocalPlayer:Kick("\n[Shenky Hub]\n" .. tostring(authData.message or "HWID is currently in use on another device."))
    return
end

if success and authData and authData.payload then
    executePayload(authData.payload, authData.gameName or "Game", authData.tier)
    return
end

if authData and authData.keyInvalid then
    Auth:ClearSavedKey(universeId)
end

-- Stop execution immediately if the game is not registered / does not require key
if not authData or not authData.requireKey then
    local errMsg = (authData and authData.message) or msg or "Game is not supported by Shenky Hub."
    warn(string.format("[Shenky Hub] %s (UniverseId: %s)", tostring(errMsg), tostring(universeId)))
    return
end

Auth:CreateKeyPrompt({
    GameTitle = (authData and authData.gameName) or "Supported Game",
    Subtitle = (authData and authData.gameName and ("Access key required for " .. tostring(authData.gameName))) or "Click 'Get Key' to generate your access key",
    Discord = DISCORD_INVITE,
    OnGetLink = function()
        local ok, res = Auth:HttpRequest({
            Url = BACKEND_URL .. "/api/getlink",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({ hwid = hwid })
        })
        if ok and res then
            local rawBody = res.Body or res.body
            if rawBody then
                local okDec, pbData = pcall(HttpService.JSONDecode, HttpService, rawBody)
                if okDec and pbData then
                    if pbData.success and pbData.data and pbData.data.url then
                        return pbData.data.url
                    end
                    if pbData.message then
                        return false, tostring(pbData.message)
                    end
                end
            end
        end
        return false, "Failed to retrieve key link from server."
    end,
    OnVerify = function(inputKey)
        local verifyOk, verifyData, verifyMsg = sendAuth(inputKey)
        if verifyData and verifyData.kick then
            local kickMsg = "\n[Shenky Hub]\n" .. tostring(verifyData.message or "HWID is currently in use on another device.")
            LocalPlayer:Kick(kickMsg)
            return false, kickMsg
        end
        if verifyOk and verifyData and verifyData.payload then
            Auth:SaveKey(universeId, inputKey)
            task.spawn(function()
                executePayload(verifyData.payload, verifyData.gameName or "Game", verifyData.tier)
            end)
            return true, verifyData.message or "Key verified!"
        end
        return false, verifyMsg or "Invalid key!"
    end
})
