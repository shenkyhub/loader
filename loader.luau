repeat task.wait() until game:IsLoaded() and game:GetService("Players").LocalPlayer

local placeId = game.PlaceId
local gameId = game.GameId

local games = {
	[10526463655]     = "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/Games/8ball-duels.luau", -- 8 Ball Duels
	[10767928510]     = "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/Games/pixel-lineage.luau", -- Pixel Lineage
	[10766845655]     = "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/Games/piano-rhythm-tiles.luau", -- Piano Rhythm Tiles
}

local target = games[placeId] or games[gameId]

if target then
	local genv = (getgenv and getgenv()) or _G
	if genv.__SHENKY_RUNNING or genv.__GLOBAL_HUB then
		warn("[Autoexec] Script is already loading or running.")
		return
	end
	genv.__SHENKY_RUNNING = true

	-- Clean up any lingering duplicate ScreenGui in CoreGui
	pcall(function()
		local CoreGui = game:GetService("CoreGui")
		for _, c in ipairs(CoreGui:GetChildren()) do
			if c:IsA("ScreenGui") and c.Name == "ScreenGui" and c:FindFirstChild("Base") then
				c:Destroy()
			end
		end
	end)

	print("[Autoexec] Game supported! Loading script...")
	local ok, err = pcall(function()
		local src = target:match("^http") and game:HttpGet(target) or readfile(target)
		loadstring(src)()
	end)
	if not ok then
		genv.__SHENKY_RUNNING = nil
		warn(string.format("[Autoexec] Failed to load %s: %s", tostring(target), tostring(err)))
	end
else
	warn(string.format("[Autoexec] Unsupported game. PlaceId: %s | GameId: %s", tostring(placeId), tostring(gameId)))
end
