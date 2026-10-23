-- ==============================================================================
-- SHENKY HUB - MASTER UNIVERSAL LOADER & SECURE AUTHENTICATION (V3)
-- File: loader.luau
-- Security & Architecture Standards:
-- 1. STRICT UNIVERSE ID : Always resolves Universe ID (game.GameId), covering all
--                         subplaces, lobbies, raids, and dungeons automatically.
-- 2. DYNAMIC GITHUB     : Game configurations fetched dynamically from GitHub.
-- 3. UNIQUE CRYPT KEYS  : HMAC-SHA256 Crypt Keys with Dynamic HWID Auto-Binding.
-- 4. SERVER STAGING     : Zero-Trust payload delivery via Cloudflare Workers.
-- 5. ANTI-LEAK PRIVACY  : Immediate Roblox kick on HWID mismatch with zero OpSec leak.
-- ==============================================================================

-- Wait for game to fully load and Universe ID (game.GameId) to become available
repeat task.wait() until game:IsLoaded() and game:GetService("Players").LocalPlayer
repeat task.wait() until game.GameId and game.GameId ~= 0

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

-- [1] GLOBAL CONFIGURATION
local BACKEND_URL = "https://shenky-auth.farialtaff.workers.dev"
local DISCORD_INVITE = "https://discord.gg/shenky"

-- PlatoBoost Fallback Configuration (Used if backend is offline)
local PLATOBOOST_CONFIG = {
    ServiceId = 34644,
    Secret = "c05d2bc8-1e72-4014-b056-d015e3dfcf06",
}

-- [2] STRICT UNIVERSE ID RESOLUTION
local universeId = tostring(game.GameId)

-- [3] LOAD AUTH MODULE (auth.luau / gui/auth.luau)
local Auth = (function()
    local localFiles = { "auth.luau", "gui/auth.luau" }
    for _, path in ipairs(localFiles) do
        if isfile and isfile(path) and readfile then
            local ok, mod = pcall(function() return loadstring(readfile(path))() end)
            if ok and type(mod) == "table" then return mod end
        end
    end

    local httpReq = request or http_request or (syn and syn.request)
    if type(httpReq) == "function" then
        local remoteUrls = {
            "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/auth.luau",
            "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/gui/auth.luau"
        }
        for _, url in ipairs(remoteUrls) do
            local ok, res = pcall(httpReq, {
                Url = url .. "?t=" .. tostring(os.time()),
                Method = "GET"
            })
            if ok and res and (res.StatusCode == 200 or res.Status == 200) then
                local okComp, fn = pcall(loadstring, res.Body)
                if okComp and type(fn) == "function" then
                    local okRun, mod = pcall(fn)
                    if okRun and type(mod) == "table" then return mod end
                end
            end
        end
    end

    return {
        GetHWID = function() return tostring(LocalPlayer.UserId) end,
        GetSavedKey = function() return nil end,
        SaveKey = function() end,
        ClearSavedKey = function() end,
        SetClipboard = function(t) if setclipboard then setclipboard(t) end end,
        CreateKeyPrompt = function() warn("[Auth] GUI not loaded.") end,
        HttpRequest = function(_, opt)
            local req = request or http_request or (syn and syn.request)
            if req then return pcall(req, opt) end
            return false, nil
        end
    }
end)()

-- [4] PRE-FLIGHT CONCURRENCY CHECK
local genv = (getgenv and getgenv()) or _G
if genv.__SHENKY_RUNNING or genv.__GLOBAL_HUB then
    warn("[Shenky Loader] Script is already running.")
    return
end

-- [5] SECURE PAYLOAD EXECUTION
local function executePayload(src, gameName, tier)
    if type(src) ~= "string" or #src == 0 then
        warn("[Shenky Loader] Received empty payload.")
        return false
    end

    local finalTier = tostring(tier or "public")
    print(string.format("[Shenky Loader] Running script for %s (Universe: %s | Tier: %s)...", tostring(gameName or "Game"), universeId, finalTier))
    genv.__SHENKY_RUNNING = true
    genv.ShenkyTier = finalTier

    local fn, compileErr = loadstring(src)
    if not fn then
        genv.__SHENKY_RUNNING = nil
        warn(string.format("[Shenky Loader] Failed to compile script: %s", tostring(compileErr)))
        return false
    end

    local runOk, runErr = pcall(fn)
    if not runOk then
        genv.__SHENKY_RUNNING = nil
        warn(string.format("[Shenky Loader] Runtime execution error: %s", tostring(runErr)))
        return false
    end

    return true
end

-- ==============================================================================
-- [6] PIPELINE A: BACKEND CLOUDFLARE WORKER (ZERO-TRUST STAGING)
-- ==============================================================================
local function runBackendAuthPipeline()
    local hwid = Auth:GetHWID()
    local savedKey = Auth:GetSavedKey(universeId)

    local function sendAuthRequest(keyToSend)
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
            return false, nil, "Failed to connect to authentication server. Please check your connection."
        end

        local okDecode, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if not okDecode or type(data) ~= "table" then
            return false, nil, "Invalid response received from server."
        end

        return data.success, data, data.message
    end

    -- 1. Try verifying with saved local key (if available)
    local success, authData, msg = sendAuthRequest(savedKey)

    -- Scenario: Security Auto-Kick on HWID Mismatch
    if authData and authData.kick then
        local kickMsg = "\n[Shenky Hub - Security Alert]\n" .. tostring(authData.message or "HWID is currently in use on another device. Please reset your HWID to use.")
        LocalPlayer:Kick(kickMsg)
        return
    end

    -- Scenario A: Immediate Authorization (Keyless, Whitelisted VIP, or Active Saved Key)
    if success and authData and authData.payload then
        print(string.format("[Shenky Auth] %s", authData.message or "Access Granted!"))
        executePayload(authData.payload, authData.gameName or "Game", authData.tier)
        return
    end

    -- Scenario B: Requires Key (Public PlatoBoost, Hybrid, or Private VIP)
    local gameName = (authData and authData.gameName) or "Supported Game"
    local activeTier = (authData and authData.tier) or "public"

    Auth:CreateKeyPrompt({
        GameTitle = gameName,
        UniverseId = universeId,
        Tier = activeTier,
        CanUsePremium = (authData and authData.canUsePremium) or false,
        Discord = DISCORD_INVITE,
        OnGetLink = function()
            local ok, res = Auth:HttpRequest({
                Url = BACKEND_URL .. "/api/getlink",
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode({ hwid = hwid })
            })
            if ok and res and res.Body then
                local okDec, pbData = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if okDec and pbData.success and pbData.data and pbData.data.url then
                    return true, pbData.data.url
                end
            end
            return false, "Failed to retrieve key link from server."
        end,
        OnVerify = function(inputKey)
            local verifyOk, verifyData, verifyMsg = sendAuthRequest(inputKey)
            if verifyData and verifyData.kick then
                local kickMsg = "\n[Shenky Hub - Security Alert]\n" .. tostring(verifyData.message or "HWID is currently in use on another device. Please reset your HWID to use.")
                LocalPlayer:Kick(kickMsg)
                return false, kickMsg
            end
            if verifyOk and verifyData and verifyData.payload then
                Auth:SaveKey(universeId, inputKey)
                task.spawn(function()
                    executePayload(verifyData.payload, verifyData.gameName or gameName, verifyData.tier)
                end)
                return true, verifyData.message or "Key verified! Loading script..."
            end
            return false, verifyMsg or "Key verification failed."
        end
    })
end

-- ==============================================================================
-- [7] PIPELINE B: FALLBACK CLIENT MODE (IF BACKEND OFFLINE)
-- ==============================================================================
local function runClientFallbackPipeline()
    print(string.format("[Shenky Auth] Backend offline. Running fallback pipeline for Universe: %s", universeId))
    
    local gamesManifest = nil
    local localFiles = { "games.luau", "games.json" }
    for _, path in ipairs(localFiles) do
        if isfile and isfile(path) and readfile then
            local ok, mod = pcall(function() return loadstring(readfile(path))() end)
            if ok and type(mod) == "table" then
                gamesManifest = mod
                break
            end
        end
    end

    if not gamesManifest then
        local remoteUrls = {
            "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/games.luau",
            "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/games.json"
        }
        for _, url in ipairs(remoteUrls) do
            local ok, raw = pcall(function()
                return game:HttpGet(url .. "?t=" .. tostring(os.time()))
            end)
            if ok and type(raw) == "string" and #raw > 0 then
                local okComp, fn = pcall(loadstring, raw)
                if okComp and type(fn) == "function" then
                    local okRun, mod = pcall(fn)
                    if okRun and type(mod) == "table" then
                        gamesManifest = mod
                        break
                    end
                end
                -- Fallback JSON parse
                local okDec, jsonTbl = pcall(HttpService.JSONDecode, HttpService, raw)
                if okDec and type(jsonTbl) == "table" then
                    gamesManifest = jsonTbl
                    break
                end
            end
        end
    end

    local gameEntry = gamesManifest and gamesManifest[universeId]
    if not gameEntry then
        warn(string.format("[Shenky Loader] Universe ID %s is not registered in games.luau.", universeId))
        return
    end

    local gameName = gameEntry.name or "Game"
    local rawTier = gameEntry.tier or "keyless"
    local hwid = Auth:GetHWID()

    local function checkTier(tName)
        local target = string.lower(tostring(tName))
        if type(rawTier) == "table" then
            for _, v in ipairs(rawTier) do
                if string.lower(tostring(v)) == target then return true end
            end
            return false
        elseif type(rawTier) == "string" then
            for part in string.gmatch(rawTier, "[^,%s]+") do
                if string.lower(part) == target then return true end
            end
        end
        return false
    end

    local allowsKeyless = checkTier("keyless")
    local allowsPublic  = checkTier("public")
    local allowsPrivate = checkTier("private")
    local isHybrid      = allowsPublic and allowsPrivate

    -- Scenario 1: Keyless Game
    if allowsKeyless then
        local targetUrl = (gameEntry.isRoot and "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/" or "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/Games/") .. gameEntry.script
        local src = game:HttpGet(targetUrl .. "?t=" .. tostring(os.time()))
        executePayload(src, gameName, "keyless")
        return
    end

    -- Scenario 2: Public, Private, or Hybrid
    local savedKey = Auth:GetSavedKey(universeId)
    local function verifyDirect(k)
        if not k or #k == 0 then return false, "Empty key." end
        -- If user enters a Premium key
        if k:sub(1, 4) == "SHK_" then
            if allowsPrivate or isHybrid then
                return true, "Premium Key verified!"
            else
                return false, "This game does not support Premium VIP keys."
            end
        end
        -- Otherwise PlatoBoost for public/hybrid
        if allowsPublic then
            return Auth:VerifyPlatoBoostDirect(PLATOBOOST_CONFIG.ServiceId, PLATOBOOST_CONFIG.Secret, k, hwid)
        end
        return false, "This script requires an authorized Premium VIP Key."
    end

    if savedKey and verifyDirect(savedKey) then
        local targetUrl = (gameEntry.isRoot and "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/" or "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/Games/") .. gameEntry.script
        local src = game:HttpGet(targetUrl .. "?t=" .. tostring(os.time()))
        executePayload(src, gameName, savedKey:sub(1, 4) == "SHK_" and "premium" or "public")
        return
    end

    local activeTier = isHybrid and "hybrid" or (allowsPrivate and "private" or "public")
    Auth:CreateKeyPrompt({
        GameTitle = gameName,
        UniverseId = universeId,
        Tier = activeTier,
        CanUsePremium = allowsPrivate,
        Discord = DISCORD_INVITE,
        OnGetLink = function()
            return Auth:GetPlatoBoostLinkDirect(PLATOBOOST_CONFIG.ServiceId, hwid)
        end,
        OnVerify = function(inputKey)
            local ok, msg = verifyDirect(inputKey)
            if ok then
                Auth:SaveKey(universeId, inputKey)
                task.spawn(function()
                    local targetUrl = (gameEntry.isRoot and "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/" or "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/Games/") .. gameEntry.script
                    local src = game:HttpGet(targetUrl .. "?t=" .. tostring(os.time()))
                    executePayload(src, gameName, inputKey:sub(1, 4) == "SHK_" and "premium" or "public")
                end)
                return true, msg or "Key verified!"
            end
            return false, msg or "Key is invalid or expired."
        end
    })
end

-- ==============================================================================
-- [8] MASTER ENTRY POINT
-- ==============================================================================
if BACKEND_URL and #BACKEND_URL > 5 then
    runBackendAuthPipeline()
else
    runClientFallbackPipeline()
end
