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
	if genv.__GLOBAL_HUB then
		warn("[Autoexec] Hub is already running in this session.")
		return
	end

	print("[Autoexec] Game supported! Loading script...")
	local ok, err = pcall(function()
		local src = target:match("^http") and game:HttpGet(target) or readfile(target)
		loadstring(src)()
	end)
	if not ok then
		warn(string.format("[Autoexec] Failed to load %s: %s", tostring(target), tostring(err)))
	end
else
	warn(string.format("[Autoexec] Unsupported game. PlaceId: %s | GameId: %s", tostring(placeId), tostring(gameId)))
end
