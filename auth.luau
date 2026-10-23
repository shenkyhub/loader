-- ==============================================================================
-- SHENKY HUB - UNIVERSAL CLIENT AUTH & KEY SYSTEM LIBRARY
-- File: gui/auth.luau
-- Handles 3 Tier Access Verifications:
-- 1. Keyless Script  : Loads instantly without key prompts
-- 2. Public Script   : Requires PlatoBoost Key (with local caching)
-- 3. Private Script  : Requires VIP Crypt Key (with dynamic HWID auto-binding)
-- ==============================================================================

local Auth = {}
Auth.__index = Auth

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

-- [1] SHA-256 IMPLEMENTATION (FALLBACK PURE LUA)
local function getSha256(str)
    local cryptObj = crypt or (syn and syn.crypt)
    if cryptObj and type(cryptObj.hash) == "function" then
        local ok, h = pcall(cryptObj.hash, str, "sha256")
        if ok and type(h) == "string" then return h end
    end
    if type(sha256) == "function" then
        local ok, h = pcall(sha256, str)
        if ok and type(h) == "string" then return h end
    end

    local a=2^32;local b=a-1;local function c(d,e)local f,g=0,1;while d~=0 or e~=0 do local h,i=d%2,e%2;local j=(h+i)%2;f=f+j*g;d=math.floor(d/2)e=math.floor(e/2)g=g*2 end;return f%a end
    local function k(d,e,l,...)local m;if e then d=d%a;e=e%a;m=c(d,e)if l then m=k(m,l,...)end;return m elseif d then return d%a else return 0 end end
    local function n(d,e,l,...)local m;if e then d=d%a;e=e%a;m=(d+e-c(d,e))/2;if l then m=n(m,l,...)end;return m elseif d then return d%a else return b end end
    local function o(p)return b-p end
    local function q(d,r)if r<0 then return d*2^(-r)%2^32 end;return math.floor(d%2^32/2^r)end
    local function s(p,r)if r>31 or r<-31 then return 0 end;return q(p%a,r)end
    local function lshift(d,r)if r<0 then return s(d,-r)end;return d*2^r%2^32 end
    local function t(p,r)p=p%a;r=r%32;local u=n(p,2^r-1)return s(p,r)+lshift(u,32-r)end
    local v={0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
    local function w(x)return string.gsub(x,".",function(l)return string.format("%02x",string.byte(l))end)end
    local function y(z,A)local x=""for B=1,A do local C=z%256;x=string.char(C)..x;z=(z-C)/256 end;return x end
    local function D(x,B)local A=0;for B=B,B+3 do A=A*256+string.byte(x,B)end;return A end
    local function E(F,G)local H=64-(G+9)%64;G=y(8*G,8)F=F.."\128"..string.rep("\0",H)..G;return F end
    local function I(J)J[1]=0x6a09e667;J[2]=0xbb67ae85;J[3]=0x3c6ef372;J[4]=0xa54ff53a;J[5]=0x510e527f;J[6]=0x9b05688c;J[7]=0x1f83d9ab;J[8]=0x5be0cd19;return J end
    local function K(F,B,J)
        local L={}
        for M=1,16 do L[M]=D(F,B+(M-1)*4)end
        for M=17,64 do
            local N=L[M-15]
            local O=k(t(N,7),t(N,18),s(N,3))
            N=L[M-2]
            L[M]=(L[M-16]+O+L[M-7]+k(t(N,17),t(N,19),s(N,10)))%a
        end
        local d,e,l,P,Q,R,S,T=J[1],J[2],J[3],J[4],J[5],J[6],J[7],J[8]
        for B=1,64 do
            local O=k(t(d,2),t(d,13),t(d,22))
            local U=k(n(d,e),n(d,l),n(e,l))
            local V=(O+U)%a
            local W=k(t(Q,6),t(Q,11),t(Q,25))
            local X=k(n(Q,R),n(o(Q),S))
            local Y=(T+W+X+v[B]+L[B])%a
            T=S;S=R;R=Q;Q=(P+Y)%a;P=l;l=e;e=d;d=(Y+V)%a
        end
        J[1]=(J[1]+d)%a;J[2]=(J[2]+e)%a;J[3]=(J[3]+l)%a;J[4]=(J[4]+P)%a
        J[5]=(J[5]+Q)%a;J[6]=(J[6]+R)%a;J[7]=(J[7]+S)%a;J[8]=(J[8]+T)%a
    end
    local function Z(F)
        F=E(F,#F)
        local J=I({})
        for B=1,#F,64 do K(F,B,J)end
        return w(y(J[1],4)..y(J[2],4)..y(J[3],4)..y(J[4],4)..y(J[5],4)..y(J[6],4)..y(J[7],4)..y(J[8],4))
    end
    return Z(str)
end

Auth.Sha256 = getSha256

-- [2] HWID RESOLVER
function Auth:GetHWID()
    local hwidFn = gethwid or (syn and syn.get_hwid) or (fluxus and fluxus.get_hwid)
    if type(hwidFn) == "function" then
        local ok, val = pcall(hwidFn)
        if ok and val and #tostring(val) > 4 then
            return tostring(val)
        end
    end
    local okAnalytics, rbxId = pcall(function()
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end)
    if okAnalytics and rbxId and #rbxId > 4 then
        return tostring(rbxId)
    end
    local lp = Players.LocalPlayer
    return "RBX_USER_" .. tostring(lp and lp.UserId or "0")
end

-- [3] KEY CACHING (Executor File System)
local CACHE_DIR = "Shenky"
local KEYS_DIR = CACHE_DIR .. "/keys"

function Auth:GetSavedKey(universeId)
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return nil end
    local filePath = string.format("%s/%s.txt", KEYS_DIR, tostring(universeId))
    local ok, exists = pcall(isfile, filePath)
    if ok and exists then
        local okRead, content = pcall(readfile, filePath)
        if okRead and type(content) == "string" then
            local clean = content:gsub("%s+", "")
            if #clean > 0 then return clean end
        end
    end
    return nil
end

function Auth:SaveKey(universeId, key)
    if type(writefile) ~= "function" or type(makefolder) ~= "function" then return end
    pcall(function()
        if not isfolder(CACHE_DIR) then makefolder(CACHE_DIR) end
        if not isfolder(KEYS_DIR) then makefolder(KEYS_DIR) end
        writefile(string.format("%s/%s.txt", KEYS_DIR, tostring(universeId)), tostring(key))
    end)
end

function Auth:ClearSavedKey(universeId)
    if type(delfile) == "function" and type(isfile) == "function" then
        local filePath = string.format("%s/%s.txt", KEYS_DIR, tostring(universeId))
        pcall(function()
            if isfile(filePath) then delfile(filePath) end
        end)
    end
end

-- [4] CLIPBOARD HELPER
function Auth:SetClipboard(text)
    local setcb = setclipboard or toclipboard or (syn and syn.write_clipboard)
    if type(setcb) == "function" then
        pcall(setcb, tostring(text))
        return true
    end
    return false
end

-- [5] HTTP REQUEST WRAPPER
function Auth:HttpRequest(options)
    local req = request or http_request or (syn and syn.request) or (http and http.request)
    if type(req) ~= "function" then
        return false, { StatusCode = 0, Body = "Executor does not support HTTP requests." }
    end
    local ok, res = pcall(req, options)
    if not ok then
        return false, { StatusCode = 0, Body = tostring(res) }
    end
    return true, res
end

-- [6] STANDALONE PLATOBOOST VERIFICATION (CLIENT-SIDE FALLBACK)
function Auth:VerifyPlatoBoostDirect(serviceId, secret, userKey, hwid)
    local nonce = ""
    for _ = 1, 16 do
        nonce = nonce .. string.char(math.random(97, 122))
    end

    local identifier = getSha256(hwid)
    local host = "https://api.platoboost.net"
    local endpoint = string.format("%s/public/whitelist/%s?identifier=%s&key=%s&nonce=%s",
        host, tostring(serviceId), identifier, tostring(userKey), nonce)

    local ok, res = self:HttpRequest({ Url = endpoint, Method = "GET" })
    if not ok or not res or res.StatusCode ~= 200 then
        return false, "Unable to connect to verification gateway."
    end

    local okDecode, decoded = pcall(HttpService.JSONDecode, HttpService, res.Body)
    if not okDecode or not decoded or decoded.success ~= true then
        return false, (decoded and decoded.message) or "Access key verification failed."
    end

    if decoded.data and decoded.data.valid == true then
        local expectedHash = getSha256("true-" .. nonce .. "-" .. secret)
        if decoded.data.hash == expectedHash then
            return true, "Access key verified successfully."
        else
            return false, "Gateway signature integrity verification failed."
        end
    end

    return false, "Access key is invalid or checkpoint pending completion."
end

function Auth:GetPlatoBoostLinkDirect(serviceId, hwid)
    local identifier = getSha256(hwid)
    local host = "https://api.platoboost.net"
    local ok, res = self:HttpRequest({
        Url = host .. "/public/start",
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode({
            service = serviceId,
            identifier = identifier
        })
    })

    if ok and res and res.StatusCode == 200 then
        local okDecode, decoded = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if okDecode and decoded.success and decoded.data and decoded.data.url then
            return true, decoded.data.url
        end
    end
    return false, "Unable to retrieve verification gateway link."
end

-- [7] MODERN KEY SYSTEM GUI (SHENKY HUB THEME)
function Auth:CreateKeyPrompt(config)
    pcall(function()
        local old = CoreGui:FindFirstChild("ShenkyAuthPrompt")
        if old then old:Destroy() end
    end)

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "ShenkyAuthPrompt"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local guiParent = (gethui and gethui()) or CoreGui or LocalPlayer:WaitForChild("PlayerGui")
    ScreenGui.Parent = guiParent

    -- Backdrop
    local Backdrop = Instance.new("Frame")
    Backdrop.Size = UDim2.fromScale(1, 1)
    Backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    Backdrop.BackgroundTransparency = 0.5
    Backdrop.Parent = ScreenGui

    -- Main Container
    local Container = Instance.new("Frame")
    Container.Size = UDim2.fromOffset(420, 310)
    Container.Position = UDim2.new(0.5, -210, 0.5, -155)
    Container.BackgroundColor3 = Color3.fromRGB(15, 12, 26)
    Container.BorderSizePixel = 0
    Container.ClipsDescendants = true
    Container.Parent = ScreenGui

    local ContainerCorner = Instance.new("UICorner")
    ContainerCorner.CornerRadius = UDim.new(0, 12)
    ContainerCorner.Parent = Container

    local ContainerStroke = Instance.new("UIStroke")
    ContainerStroke.Color = Color3.fromRGB(115, 85, 220)
    ContainerStroke.Thickness = 1.5
    ContainerStroke.Parent = Container

    -- Top Gradient Bar
    local TopBar = Instance.new("Frame")
    TopBar.Size = UDim2.new(1, 0, 0, 4)
    TopBar.BackgroundColor3 = Color3.fromRGB(140, 100, 255)
    TopBar.BorderSizePixel = 0
    TopBar.Parent = Container

    local TopGradient = Instance.new("UIGradient")
    TopGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(160, 130, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(115, 85, 220)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(236, 72, 153))
    })
    TopGradient.Parent = TopBar

    -- Draggable Window
    local dragging, dragStart, startPos = false, nil, nil
    Container.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Container.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            Container.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- Brand Title
    local BrandLabel = Instance.new("TextLabel")
    BrandLabel.Size = UDim2.new(1, -40, 0, 28)
    BrandLabel.Position = UDim2.new(0, 20, 0, 16)
    BrandLabel.BackgroundTransparency = 1
    BrandLabel.Text = "SHENKY HUB"
    BrandLabel.TextColor3 = Color3.fromRGB(240, 230, 255)
    BrandLabel.Font = Enum.Font.GothamBold
    BrandLabel.TextSize = 18
    BrandLabel.TextXAlignment = Enum.TextXAlignment.Left
    BrandLabel.Parent = Container

    -- Tier Badge
    local isPrivate = (config.Tier == "private")
    local isHybrid = (config.Tier == "hybrid" or config.CanUsePremium == true)

    local Badge = Instance.new("TextLabel")
    Badge.Size = UDim2.fromOffset(isPrivate and 90 or (isHybrid and 125 or 120), 20)
    Badge.Position = UDim2.new(1, isPrivate and -110 or (isHybrid and -145 or -140), 0, 20)
    Badge.BackgroundColor3 = isPrivate and Color3.fromRGB(225, 29, 72) or (isHybrid and Color3.fromRGB(147, 51, 234) or Color3.fromRGB(37, 99, 235))
    Badge.Text = isPrivate and "PREMIUM" or (isHybrid and "FREE / PREMIUM" or "KEY SYSTEM")
    Badge.TextColor3 = Color3.fromRGB(255, 255, 255)
    Badge.Font = Enum.Font.GothamBold
    Badge.TextSize = 10
    Badge.Parent = Container
    Instance.new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = Badge })

    -- Subtitle / Game Name & Universe ID
    local SubLabel = Instance.new("TextLabel")
    SubLabel.Size = UDim2.new(1, -40, 0, 18)
    SubLabel.Position = UDim2.new(0, 20, 0, 44)
    SubLabel.BackgroundTransparency = 1
    SubLabel.Text = string.format("%s (Universe: %s)", tostring(config.GameTitle or "Supported Game"), tostring(config.UniverseId or "-"))
    SubLabel.TextColor3 = Color3.fromRGB(160, 150, 180)
    SubLabel.Font = Enum.Font.GothamMedium
    SubLabel.TextSize = 12
    SubLabel.TextXAlignment = Enum.TextXAlignment.Left
    SubLabel.Parent = Container

    -- Description Box
    local DescLabel = Instance.new("TextLabel")
    DescLabel.Size = UDim2.new(1, -40, 0, 32)
    DescLabel.Position = UDim2.new(0, 20, 0, 68)
    DescLabel.BackgroundTransparency = 1
    if isPrivate then
        DescLabel.Text = "This script is Premium. Enter your Premium Key below, or click 'Copy HWID' to request access."
    elseif isHybrid then
        DescLabel.Text = "Enter your Premium Key (SHK_...), or click 'Get Key' to use the free tier via checkpoint."
    else
        DescLabel.Text = "Click 'Get Key' to copy the key link to clipboard, complete the steps, then paste your key below."
    end
    DescLabel.TextColor3 = Color3.fromRGB(140, 145, 155)
    DescLabel.Font = Enum.Font.Gotham
    DescLabel.TextSize = 11
    DescLabel.TextWrapped = true
    DescLabel.TextXAlignment = Enum.TextXAlignment.Left
    DescLabel.Parent = Container

    -- Input Frame
    local InputFrame = Instance.new("Frame")
    InputFrame.Size = UDim2.new(1, -40, 0, 42)
    InputFrame.Position = UDim2.new(0, 20, 0, 108)
    InputFrame.BackgroundColor3 = Color3.fromRGB(25, 20, 42)
    InputFrame.BorderSizePixel = 0
    InputFrame.Parent = Container

    local InputCorner = Instance.new("UICorner")
    InputCorner.CornerRadius = UDim.new(0, 8)
    InputCorner.Parent = InputFrame

    local InputStroke = Instance.new("UIStroke")
    InputStroke.Color = Color3.fromRGB(60, 48, 90)
    InputStroke.Thickness = 1
    InputStroke.Parent = InputFrame

    local KeyInput = Instance.new("TextBox")
    KeyInput.Size = UDim2.new(1, -20, 1, 0)
    KeyInput.Position = UDim2.new(0, 10, 0, 0)
    KeyInput.BackgroundTransparency = 1
    KeyInput.PlaceholderText = isPrivate and "Paste Premium Key (SHK_...) here..." or (isHybrid and "Paste Key (PlatoBoost or Premium)..." or "Paste Key here...")
    KeyInput.PlaceholderColor3 = Color3.fromRGB(100, 95, 120)
    KeyInput.TextColor3 = Color3.fromRGB(255, 255, 255)
    KeyInput.Font = Enum.Font.Gotham
    KeyInput.TextSize = 13
    KeyInput.ClearTextOnFocus = false
    KeyInput.Parent = InputFrame

    -- Status Feedback Label
    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.Size = UDim2.new(1, -40, 0, 20)
    StatusLabel.Position = UDim2.new(0, 20, 0, 155)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Text = ""
    StatusLabel.TextColor3 = Color3.fromRGB(244, 63, 94)
    StatusLabel.Font = Enum.Font.GothamMedium
    StatusLabel.TextSize = 11
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Center
    StatusLabel.Parent = Container

    -- Button Row (Get Key & Verify)
    local GetKeyBtn = Instance.new("TextButton")
    GetKeyBtn.Size = UDim2.new(0.48, -25, 0, 40)
    GetKeyBtn.Position = UDim2.new(0, 20, 0, 185)
    GetKeyBtn.BackgroundColor3 = Color3.fromRGB(38, 30, 62)
    GetKeyBtn.TextColor3 = Color3.fromRGB(240, 230, 255)
    GetKeyBtn.Text = isPrivate and "Copy HWID" or "Get Key"
    GetKeyBtn.Font = Enum.Font.GothamBold
    GetKeyBtn.TextSize = 13
    GetKeyBtn.Parent = Container
    Instance.new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = GetKeyBtn })

    local VerifyBtn = Instance.new("TextButton")
    VerifyBtn.Size = UDim2.new(0.48, -25, 0, 40)
    VerifyBtn.Position = UDim2.new(0.52, 5, 0, 185)
    VerifyBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
    VerifyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    VerifyBtn.Text = "Verify Key"
    VerifyBtn.Font = Enum.Font.GothamBold
    VerifyBtn.TextSize = 13
    VerifyBtn.Parent = Container
    Instance.new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = VerifyBtn })

    -- Discord Button
    local DiscordBtn = Instance.new("TextButton")
    DiscordBtn.Size = UDim2.new(1, -40, 0, 36)
    DiscordBtn.Position = UDim2.new(0, 20, 0, 240)
    DiscordBtn.BackgroundColor3 = Color3.fromRGB(28, 22, 46)
    DiscordBtn.TextColor3 = Color3.fromRGB(180, 150, 255)
    DiscordBtn.Text = "Join Shenky Discord (Support & Premium)"
    DiscordBtn.Font = Enum.Font.Gotham
    DiscordBtn.TextSize = 12
    DiscordBtn.Parent = Container
    Instance.new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = DiscordBtn })

    -- Event Handlers
    GetKeyBtn.MouseButton1Click:Connect(function()
        if isPrivate then
            local myHwid = self:GetHWID()
            self:SetClipboard(myHwid)
            StatusLabel.TextColor3 = Color3.fromRGB(34, 197, 94)
            StatusLabel.Text = "HWID copied to Clipboard! Send it to owner/bot."
            return
        end

        StatusLabel.TextColor3 = Color3.fromRGB(56, 189, 248)
        StatusLabel.Text = "Fetching key link..."
        task.spawn(function()
            if config.OnGetLink then
                local ok, link = config.OnGetLink()
                if ok and link then
                    self:SetClipboard(link)
                    StatusLabel.TextColor3 = Color3.fromRGB(34, 197, 94)
                    StatusLabel.Text = "Key link copied to Clipboard!"
                else
                    StatusLabel.TextColor3 = Color3.fromRGB(239, 68, 68)
                    StatusLabel.Text = tostring(link or "Failed to fetch key link.")
                end
            end
        end)
    end)

    VerifyBtn.MouseButton1Click:Connect(function()
        local inputKey = KeyInput.Text:gsub("%s+", "")
        if #inputKey == 0 then
            StatusLabel.TextColor3 = Color3.fromRGB(239, 68, 68)
            StatusLabel.Text = "Please enter your key first!"
            return
        end

        StatusLabel.TextColor3 = Color3.fromRGB(234, 179, 8)
        StatusLabel.Text = "Checking key..."
        VerifyBtn.Active = false

        task.spawn(function()
            if config.OnVerify then
                local success, message = config.OnVerify(inputKey)
                if success then
                    StatusLabel.TextColor3 = Color3.fromRGB(34, 197, 94)
                    StatusLabel.Text = message or "Key verified! Loading script..."
                    task.wait(0.6)
                    ScreenGui:Destroy()
                else
                    StatusLabel.TextColor3 = Color3.fromRGB(239, 68, 68)
                    StatusLabel.Text = message or "Invalid key!"
                    VerifyBtn.Active = true
                end
            end
        end)
    end)

    DiscordBtn.MouseButton1Click:Connect(function()
        self:SetClipboard(config.Discord or "https://discord.gg/shenky")
        StatusLabel.TextColor3 = Color3.fromRGB(180, 150, 255)
        StatusLabel.Text = "Discord invite copied to Clipboard!"
    end)

    return ScreenGui
end

return Auth
