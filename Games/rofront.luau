-- ==============================================================================
-- Game: RoFront [World PvP]
-- Script: main.luau
-- Purpose: Senior-grade client-side automation, RTS optimization & Smart Auto Play
-- Repository Convention: Follows AGENTS.md standards & Shenky Hub loader
-- ==============================================================================

local HUB_URL = "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/hub.luau?t=" .. tostring(os.time())
local Hub = (function()
	local env = getfenv()

	-- 1. Check local gui/hub.luau first (instant for local dev/testing)
	if env.readfile then
		local okLocal, localSrc = pcall(env.readfile, "gui/hub.luau")
		if okLocal and type(localSrc) == "string" and #localSrc > 0 then
			local fn = loadstring(localSrc)
			if fn then
				local runOk, hubObj = pcall(fn)
				if runOk and type(hubObj) == "table" and type(hubObj.CreateWindow) == "function" then
					return hubObj
				end
			end
		end
	end

	-- 2. Try online loader via request/http_request/syn
	local httpReq = env.request or env.http_request or (env.syn and env.syn.request)
	if type(httpReq) == "function" then
		local okReq, res = pcall(httpReq, { Url = HUB_URL, Method = "GET" })
		if okReq and type(res) == "table" and (res.StatusCode == 200 or res.Status == 200) then
			local b = res.Body or res.body
			if type(b) == "string" and #b > 0 then
				local fn = loadstring(b)
				if fn then
					local runOk, hubObj = pcall(fn)
					if runOk and type(hubObj) == "table" and type(hubObj.CreateWindow) == "function" then
						return hubObj
					end
				end
			end
		end
	end

	-- 3. Try online loader via game:HttpGet
	local okGet, resGet = pcall(game.HttpGet, game, HUB_URL)
	if okGet and type(resGet) == "string" and #resGet > 0 then
		local fn = loadstring(resGet)
		if fn then
			local runOk, hubObj = pcall(fn)
			if runOk and type(hubObj) == "table" and type(hubObj.CreateWindow) == "function" then
				return hubObj
			end
		end
	end

	error("[Shenky Hub] Failed to fetch or initialize hub.luau from GitHub or local storage!")
end)()

rawset(_G, "RoFrontHub", Hub)

-- ==============================================================================
-- [1] SERVICES & NATIVE GAME MODULE ADAPTER
-- ==============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local Adapter = {
	Main = nil,
	Session = nil,
	World = nil,
	UI = nil,
	State = nil,
	Rules = nil,
	Defs = nil,
	AirfrontNet = nil,
	ToServer = nil,
	LastResolve = 0,
}

function Adapter:Resolve()
	local now = os.clock()
	if now - self.LastResolve < 0.5 then
		return self.Session ~= nil and self.State ~= nil
	end
	self.LastResolve = now

	pcall(function()
		local dynamicRequire = getfenv().require or require
		local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
		if playerScripts then
			local clientFolder = playerScripts:FindFirstChild("AirfrontClient")
			if clientFolder and clientFolder:FindFirstChild("Main") then
				self.Main = dynamicRequire(clientFolder.Main)
				self.Session = self.Main and self.Main.session
				self.World = self.Main and self.Main.world
				self.UI = self.Main and self.Main.ui
				self.State = self.Session and self.Session.state
			end
		end

		local airfront = ReplicatedStorage:FindFirstChild("Airfront")
		if airfront then
			local core = airfront:FindFirstChild("Core")
			if core then
				if core:FindFirstChild("Rules") then
					self.Rules = dynamicRequire(core.Rules)
				end
				if core:FindFirstChild("Defs") then
					self.Defs = dynamicRequire(core.Defs)
				end
			end
		end

		local netFolder = ReplicatedStorage:FindFirstChild("AirfrontNet")
		if netFolder then
			self.AirfrontNet = netFolder
			self.ToServer = netFolder:FindFirstChild("ToServer")
		end
	end)

	return self.Session ~= nil and self.State ~= nil
end

function Adapter:GetMe()
	if not self:Resolve() then return nil end
	local state = self.State
	if not state or not state.local_owner or state.local_owner == 0 then return nil end
	return state.owners and state.owners[state.local_owner]
end

function Adapter:SendIntent(intentTable)
	if not self:Resolve() then return false end
	if not self.Session or type(self.Session.send_intent) ~= "function" then return false end
	local success, err = pcall(function()
		self.Session:send_intent(intentTable)
	end)
	return success
end

function Adapter:GetBorders()
	if not self:Resolve() then return nil end
	local ui = self.UI
	local interact = ui and ui.interact
	local ctx = interact and interact.ctx
	return ctx and ctx.borders
end

function Adapter:GetContext()
	if not self:Resolve() then return nil end
	local ui = self.UI
	local interact = ui and ui.interact
	return interact and interact.ctx
end

function Adapter:ResolveAttack(targetTile, ratio)
	if not self:Resolve() then return false end
	local ctx = self:GetContext()
	local rules = ctx and ctx.rules
	if not rules then
		return self:SendIntent({ type = "attack", tile = targetTile, ratio = ratio })
	end

	-- HELPER: Hard troop ceiling on amphibious naval transport boats.
	-- A transport boat only needs enough troops to capture 1 single beachhead tile (10k-35k troops).
	-- Once established, all subsequent expansion on that continent is done via land attacks with 0 warship risk!
	-- Capping boat troops prevents catastrophic multi-million troop bleed into enemy warship ambushes.
	local function getCappedRatio(rawRatio, isBoat)
		if not isBoat then return rawRatio end
		local me = self:GetMe()
		local curTroops = (me and me.troops) or 0
		if curTroops <= 0 then return math.min(rawRatio, 0.05) end
		local desiredTroops = math.clamp(curTroops * 0.15, 5000, 35000)
		local boatRatio = math.clamp(desiredTroops / math.max(1, curTroops), 0.0001, 0.25)
		return math.min(rawRatio, boatRatio)
	end

	local prim = rules:primary(targetTile)
	if prim and prim.ok then
		if prim.type == "attack" or prim.type == "boat" or prim.type == "expand" then
			local intent = rules:primary_intent(targetTile, prim)
			if intent and next(intent) then
				local isBoat = (intent.type == "boat") or (prim.type == "boat")
				intent.ratio = getCappedRatio(ratio, isBoat)
				return self:SendIntent(intent)
			end
		end
	end

	-- Fallback: check if we border target
	local borders = self:GetBorders()
	local state = self.State
	local targetOwner = state and state:tile_owner(targetTile)
	local hasSharedBorder = (borders and targetOwner and borders:borders_owner(targetOwner))
	local landing = if not hasSharedBorder then rules:boat_landing(targetTile) else -1

	local intentType = if not hasSharedBorder and landing >= 0 then "boat" else "attack"
	local finalTile = if intentType == "boat" and landing >= 0 then landing else targetTile

	return self:SendIntent({
		type = intentType,
		tile = finalTile,
		ratio = getCappedRatio(ratio, intentType == "boat"),
	})
end

local findCitySite, findPortSite, findFactorySite, findDefensePostSite, findSiloSite

function Adapter:BuildStructure(kind, specificTile)
	if not self:Resolve() then return false end
	local ctx = self:GetContext()
	local rules = ctx and ctx.rules
	if not rules then return false end

	local avail = rules:availability(kind)
	if not avail or not avail.ok then return false end

	local targetTile = specificTile
	if not targetTile or targetTile <= 0 then
		if kind == "city" and findCitySite then
			targetTile = findCitySite()
		elseif kind == "port" and findPortSite then
			targetTile = findPortSite()
		elseif kind == "factory" and findFactorySite then
			targetTile = findFactorySite()
		elseif kind == "defense" and findDefensePostSite then
			targetTile = findDefensePostSite()
		elseif kind == "silo" and findSiloSite then
			targetTile = findSiloSite()
		elseif kind == "sam" and findUnprotectedEconomicCluster then
			targetTile = findUnprotectedEconomicCluster()
		end
	end

	if not targetTile or targetTile <= 0 then return false end

	local place = rules:placement(kind, targetTile)
	if place and (place.ok or place.reason == "gold") then
		local finalTile = place.tile or targetTile
		return self:SendIntent({ type = "build", kind = kind, tile = finalTile })
	end

	return false
end

function Adapter:BuildWarship()
	if not self:Resolve() then return false end
	local ctx = self:GetContext()
	local rules = ctx and ctx.rules
	local state = self.State
	local meId = state and state.local_owner
	local map = state and state.map
	if not rules or not state or not meId or not map then return false end

	local avail = rules:availability("warship")
	if not avail or not avail.ok then return false end

	-- Find our ports
	local myPorts = {}
	for _, s in pairs(state.structures or {}) do
		if s.owner == meId and (s.kind == 1 or (Adapter.Defs and s.kind == Adapter.Defs.S_PORT)) then
			table.insert(myPorts, s.tile)
		end
	end
	if #myPorts == 0 then return false end

	local W = map.W or 2000
	for _, pTile in ipairs(myPorts) do
		local px = pTile % W
		local py = math.floor(pTile / W)
		for dy = -10, 10, 3 do
			for dx = -10, 10, 3 do
				local nx = px + dx
				local ny = py + dy
				local t = ny * W + nx
				if not map:is_land(t) then
					local place = rules:placement("warship", t)
					if place and place.ok then
						return self:SendIntent({ type = "build", kind = "warship", tile = place.tile })
					end
				end
			end
		end
	end
	return false
end

function Adapter:LaunchNuke(kind, targetTile)
	if not self:Resolve() then return false end
	if not self.Session or type(self.Session.send_intent) ~= "function" then return false end
	local ctx = self:GetContext()
	local rules = ctx and ctx.rules
	if not rules then return false end

	local avail = rules:availability(kind)
	if not avail or not avail.ok then return false end

	local success, err = pcall(function()
		self.Session:send_intent({
			type = "nuke",
			kind = kind,
			tile = targetTile,
		})
	end)
	return success
end

-- ==============================================================================
-- [2] RUNTIME AUTOMATION STATE
-- ==============================================================================
Hub.State.SmartAutoPlay = false
Hub.State.StrategyMode = "Neutral First"
Hub.State.AutoReinforce = false
Hub.State.AutoExpandNeutral = false
Hub.State.AutoInvadeEnemies = false
Hub.State.AutoCapitalSnipe = false
Hub.State.AutoNuke = false
Hub.State.AutoBuildSilos = false
Hub.State.AutoDefensePosts = false
Hub.State.AutoSAMShield = false
Hub.State.AutoBuildCities = false
Hub.State.AutoBuildPorts = false
Hub.State.AutoBuildFactories = false
Hub.State.AutoJoinMatch = false
Hub.State.AutoPlayAgain = false
Hub.State.AutoSpawnCapital = false
Hub.State.AutoTakeover = false
Hub.State.AutoOpenCrates = false

-- Sliders & Config Values
Hub.State.AttackRatio = 0.20        -- 20% decisive combat pulse ratio
Hub.State.AttackDelay = 1.20        -- 1.20s pacing between outbound waves (prevents instant troop bleed)
Hub.State.MinReserveRatio = 0.25    -- 25% homeland reserve floor (dynamic: bypassed when troops >= 200k or > neighbors)
Hub.State.MaxActiveWaves = 4        -- Up to 4 concurrent waves worldwide (max 2 overseas)
Hub.State.MinGoldReserve = 500000   -- 500k liquid cushion
Hub.State.MaxDefensePosts = 1       -- Hard cap of 1 defense post max across borders (prevents gold waste)
Hub.State.MaxSAMBatteries = 6        -- Distributed SAM batteries across empire clusters
Hub.State.MaxSAMLevel = 2            -- Hard cap per battery (stops level 90 gold sink)
Hub.State.BuildDelay = 1.5          -- 1.5s pacing interval between infrastructure builds
Hub.State.MinGoldCity = 125000      -- Starts at 125k
Hub.State.MinGoldDefense = 50000    -- Starts at 50k
Hub.State.MinGoldSAM = 1500000      -- Starts at 1.5M
Hub.State.TargetEnemyCapital = "Auto Weakest"

-- Telemetry Tracker
local RuntimeStats = {
	Status = "Idle",
	Nation = "-",
	Phase = "Lobby",
	Tiles = 0,
	Troops = 0,
	Cap = 0,
	Gold = 0,
	Income = 0,
	AttacksSent = 0,
	CitiesBuilt = 0,
	DefenseBuilt = 0,
	SAMBuilt = 0,
	NukesLaunched = 0,
	ReinforceTime = "Ready",
	LastAction = "None",
}
Hub.RuntimeStats = RuntimeStats

-- ==============================================================================
-- [3] TARGETING & LOGIC RESOLVER HELPERS
-- ==============================================================================
local function getAdjacentTiles(tile, width, height)
	local x = tile % width
	local y = math.floor(tile / width)
	local neighbors = {}
	if x > 0 then table.insert(neighbors, tile - 1) end
	if x < width - 1 then table.insert(neighbors, tile + 1) end
	if y > 0 then table.insert(neighbors, tile - width) end
	if y < height - 1 then table.insert(neighbors, tile + width) end
	return neighbors
end

findPortSite = function()
	if not Adapter:Resolve() then return nil end
	local state = Adapter.State
	local meId = state and state.local_owner
	local map = state and state.map
	local defs = Adapter.Defs
	local ctx = Adapter:GetContext()
	local rules = ctx and ctx.rules
	local borders = Adapter:GetBorders()
	if not state or not meId or meId == 0 or not map or not defs or not rules or not borders then return nil end

	local existingPorts = {}
	if state.structures then
		for _, s in pairs(state.structures) do
			if s.owner == meId and not s.dead and (s.kind == 1 or (defs and s.kind == defs.S_PORT)) then
				table.insert(existingPorts, s.tile)
			end
		end
	end

	local count = 0
	for bTile in pairs(borders.border or {}) do
		count = count + 1
		local bNum = tonumber(bTile)
		if bNum and map:is_land(bNum) and map:is_coastal(bNum) and state:tile_owner(bNum) == meId then
			local tooClose = false
			for _, pTile in ipairs(existingPorts) do
				if defs.tile_distance(bNum, pTile) < 18 then
					tooClose = true
					break
				end
			end
			if not tooClose then
				local place = rules:placement("port", bNum)
				if place and (place.ok or place.reason == "gold") and not (place.upgrade_sid and place.upgrade_sid > 0) then
					return place.tile or bNum
				end
			end
		end
		if count >= 350 then break end
	end
	return nil
end

findFactorySite = function()
	if not Adapter:Resolve() then return nil end
	local state = Adapter.State
	local meId = state and state.local_owner
	local me = Adapter:GetMe()
	local map = state and state.map
	local defs = Adapter.Defs
	local ctx = Adapter:GetContext()
	local rules = ctx and ctx.rules
	local borders = Adapter:GetBorders()
	if not state or not meId or meId == 0 or not map or not defs or not rules or not borders then return nil end

	local existingFactories = {}
	local existingCities = {}
	if state.structures then
		for _, s in pairs(state.structures) do
			if s.owner == meId and not s.dead then
				if s.kind == 2 or (defs and s.kind == defs.S_FACTORY) then
					table.insert(existingFactories, s.tile)
				elseif s.kind == 0 or (defs and s.kind == defs.S_CITY) then
					table.insert(existingCities, s.tile)
				end
			end
		end
	end

	local anchor = existingCities[1] or (me and me.spawn_tile)
	local candidates = {}
	local count = 0

	for bTile in pairs(borders.border or {}) do
		count = count + 1
		local bNum = tonumber(bTile)
		if bNum and map:is_land(bNum) and state:tile_owner(bNum) == meId then
			local tooClose = false
			for _, fTile in ipairs(existingFactories) do
				if defs.tile_distance(bNum, fTile) < 18 then
					tooClose = true
					break
				end
			end
			if not tooClose then
				local place = rules:placement("factory", bNum)
				if place and (place.ok or place.reason == "gold") and not (place.upgrade_sid and place.upgrade_sid > 0) then
					local t = place.tile or bNum
					local distToAnchor = if anchor and anchor > 0 then defs.tile_distance(t, anchor) else 50
					table.insert(candidates, { tile = t, dist = distToAnchor })
					if #candidates >= 5 then break end
				end
			end
		end
		if count >= 350 then break end
	end

	if #candidates > 0 then
		table.sort(candidates, function(a, b) return (a.dist or 0) < (b.dist or 0) end)
		return candidates[1].tile
	end
	return nil
end

findCitySite = function()
	if not Adapter:Resolve() then return nil, false end
	local state = Adapter.State
	local meId = state and state.local_owner
	local me = Adapter:GetMe()
	local map = state and state.map
	local defs = Adapter.Defs
	local ctx = Adapter:GetContext()
	local rules = ctx and ctx.rules
	local borders = Adapter:GetBorders()
	if not state or not meId or meId == 0 or not map or not defs or not rules or not borders then return nil, false end

	local existingCities = {}
	if state.structures then
		for _, s in pairs(state.structures) do
			if s.owner == meId and not s.dead and (s.kind == 0 or (defs and s.kind == defs.S_CITY)) then
				table.insert(existingCities, s)
			end
		end
	end

	-- 1. Try to plant a NEW city in the SAFE INTERIOR of our homeland (around spawn_tile / core)
	local W = map.W or 2000
	local H = map.H or 1000
	local anchor = (me and me.spawn_tile) or (existingCities[1] and existingCities[1].tile)
	if anchor and anchor > 0 then
		local cx = anchor % W
		local cy = math.floor(anchor / W)
		for r = 16, 120, 12 do
			for dy = -r, r, 6 do
				for dx = -r, r, 6 do
					local d2 = dx * dx + dy * dy
					if d2 >= (r - 6) * (r - 6) and d2 <= r * r then
						local nx = (cx + dx) % W
						local ny = cy + dy
						if ny >= 0 and ny < H then
							local t = ny * W + nx
							if state:tile_owner(t) == meId and map:is_land(t) then
								local tooClose = false
								for _, c in ipairs(existingCities) do
									if defs.tile_distance(t, c.tile) < 18 then
										tooClose = true
										break
									end
								end
								if not tooClose then
									local place = rules:placement("city", t)
									if place and (place.ok or place.reason == "gold") and not (place.upgrade_sid and place.upgrade_sid > 0) then
										return place.tile or t, false
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- Fallback: Scan borders for new city site
	local count = 0
	for bTile in pairs(borders.border or {}) do
		count = count + 1
		local bNum = tonumber(bTile)
		if bNum and map:is_land(bNum) and state:tile_owner(bNum) == meId then
			local tooClose = false
			for _, c in ipairs(existingCities) do
				if defs.tile_distance(bNum, c.tile) < 18 then
					tooClose = true
					break
				end
			end
			if not tooClose then
				local place = rules:placement("city", bNum)
				if place and (place.ok or place.reason == "gold") and not (place.upgrade_sid and place.upgrade_sid > 0) then
					return place.tile or bNum, false
				end
			end
		end
		if count >= 60 then break end
	end

	-- 2. Upgrade fallback: If all territory is packed, upgrade existing level 1 city to level 2
	for _, c in ipairs(existingCities) do
		local lvl = c.level or 1
		if lvl < 2 then
			local place = rules:placement("city", c.tile)
			if place and (place.ok or place.reason == "gold") and (place.upgrade_sid and place.upgrade_sid > 0) then
				return place.tile or c.tile, true
			end
		end
	end

	return nil, false
end

findDefensePostSite = function()
	if not Adapter:Resolve() then return nil end
	local state = Adapter.State
	local meId = state and state.local_owner
	local me = Adapter:GetMe()
	local map = state and state.map
	local defs = Adapter.Defs
	local ctx = Adapter:GetContext()
	local rules = ctx and ctx.rules
	local borders = Adapter:GetBorders()
	if not state or not meId or meId == 0 or not me or not map or not defs or not rules or not borders then return nil end

	-- Guard 1: Must already have at least 1 City and treasury >= 100k gold!
	-- Matches SimAIEconomy: never starve City / Port / Factory economic development for early defense!
	local curGold = me.gold or 0
	if curGold < 100000 then return nil end

	local myCityCount = 0
	local existingDefenses = {}
	if state.structures then
		for _, s in pairs(state.structures) do
			if s.owner == meId and not s.dead then
				if s.kind == 0 or (defs and s.kind == defs.S_CITY) then
					myCityCount = myCityCount + 1
				elseif s.kind == 3 or (defs and s.kind == defs.S_DEFENSE) then
					table.insert(existingDefenses, s.tile)
				end
			end
		end
	end
	if myCityCount == 0 then return nil end

	-- Guard 2: Strict Defense Post Cap to preserve gold for Cities & Silos
	-- 1 Defense Post provides 5x defense multiplier on our main border.
	-- Never waste gold on a 2nd defense post until we have at least 3 Cities and 35k tiles!
	local myTiles = (me and me.tiles) or 0
	local maxDefense = if myTiles >= 70000 and myCityCount >= 5 then 4
		elseif myTiles >= 35000 and myCityCount >= 3 then 2
		else 1
	maxDefense = math.max(maxDefense, Hub.State.MaxDefensePosts or 1)
	if #existingDefenses >= maxDefense then return nil end

	-- Guard 3: Strict Frontline Threat Verification (ONLY build on borders facing REAL threats!)
	-- A neighbor is a threat IF they outnumber us (>= 0.75x our army or >= 60k troops), or are actively attacking us!
	local curTroops = me.troops or 0
	local uncoveredFrontlineCenter = nil

	if borders.neighbour_ids and state.owners then
		for _, nId in ipairs(borders:neighbour_ids()) do
			local o = state.owners[nId]
			if o and o.alive and not state:are_allies(meId, nId) then
				local oTroops = o.troops or 0
				local isThreat = (oTroops >= curTroops * 0.75) or (oTroops >= 60000)

				-- Check if this neighbor is actively attacking our territory
				if not isThreat and state.attacks then
					for _, atk in pairs(state.attacks) do
						if type(atk) == "table" and not atk.dead and not atk.retreating then
							if (atk.attacker or atk.owner) == nId and atk.target == meId then
								isThreat = true
								break
							end
						end
					end
				end

				if isThreat then
					local frontlineTiles = {}
					local checked = {}
					local count = 0
					for bTile in pairs(borders.border or {}) do
						count = count + 1
						local bNum = tonumber(bTile)
						if bNum and borders._neighbours4 then
							borders:_neighbours4(bNum)
							for i = 1, borders._nn or #borders._nb do
								local nTile = borders._nb[i]
								if not checked[nTile] and map:is_contestable(nTile) then
									checked[nTile] = true
									if state:tile_owner(nTile) == nId then
										table.insert(frontlineTiles, bNum)
										break
									end
								end
							end
						end
						if #frontlineTiles >= 25 or count >= 350 then break end
					end

					if #frontlineTiles > 0 then
						-- Check if center of this specific frontline sector is already defended within 24 tiles (DEFENSE_RADIUS)
						local centerF = frontlineTiles[math.ceil(#frontlineTiles / 2)]
						local isCovered = false
						for _, dTile in ipairs(existingDefenses) do
							if defs.tile_distance(dTile, centerF) <= 24 then
								isCovered = true
								break
							end
						end
						if not isCovered then
							uncoveredFrontlineCenter = centerF
							break
						end
					end
				end
			end
		end
	end

	if not uncoveredFrontlineCenter then return nil end

	-- Place Defense Post strictly at the border chokepoint facing that threat
	local place = rules:placement("defense", uncoveredFrontlineCenter)
	if place and (place.ok or place.reason == "gold") and not (place.upgrade_sid and place.upgrade_sid > 0) then
		local d = defs.tile_distance(place.tile, uncoveredFrontlineCenter)
		-- Strict border validation: Must be within 8 tiles of the actual contact frontline!
		-- Never allows placement deep in the interior/middle!
		if d <= 8 then
			return place.tile
		end
	end

	return nil
end

findSiloSite = function()
	if not Adapter:Resolve() then return nil end
	local state = Adapter.State
	local meId = state and state.local_owner
	local me = Adapter:GetMe()
	local map = state and state.map
	local defs = Adapter.Defs
	local ctx = Adapter:GetContext()
	local rules = ctx and ctx.rules
	local borders = Adapter:GetBorders()
	if not state or not meId or meId == 0 or not map or not defs or not rules or not borders then return nil end

	if state.structures then
		for _, s in pairs(state.structures) do
			if s.owner == meId and not s.dead and (s.kind == 5 or (defs and s.kind == defs.S_SILO)) then
				return nil
			end
		end
	end

	-- [VITAL REFINEMENT] SAFE HOMELAND INTERIOR PLACEMENT:
	-- Never build the Missile Silo on the contested frontline perimeter!
	-- Place near capital spawn tile in the deep interior of our nation!
	local sp = me and me.spawn_tile
	if sp and sp > 0 and state:tile_owner(sp) == meId then
		local place = rules:placement("silo", sp)
		if place and (place.ok or place.reason == "gold") and not (place.upgrade_sid and place.upgrade_sid > 0) then
			return place.tile or sp
		end

		-- Safe interior ring search around Capital (r = 2 to 25 tiles)
		local W = map.W or 2000
		local H = map.H or 1000
		local cx = sp % W
		local cy = math.floor(sp / W)
		for r = 2, 25 do
			for dy = -r, r, 2 do
				for dx = -r, r, 2 do
					local nx = cx + dx
					local ny = cy + dy
					if nx >= 0 and nx < W and ny >= 0 and ny < H then
						local t = ny * W + nx
						if state:tile_owner(t) == meId and map:is_contestable(t) then
							local p = rules:placement("silo", t)
							if p and (p.ok or p.reason == "gold") and not (p.upgrade_sid and p.upgrade_sid > 0) then
								return p.tile or t
							end
						end
					end
				end
			end
		end
	end

	return nil
end

local function findUnprotectedEconomicCluster()
	if not Adapter:Resolve() then return nil end
	local state = Adapter.State
	local meId = state and state.local_owner
	local me = Adapter:GetMe()
	local defs = Adapter.Defs
	local map = state and state.map
	local ctx = Adapter:GetContext()
	local rules = ctx and ctx.rules
	if not state or not meId or meId == 0 or not defs or not map or not rules then return nil end

	local W = map.W or 2000
	local H = map.H or 1000

	-- Collect our SAMs and economic hubs
	local mySams = {}
	local myEcon = {}

	for sid, sData in pairs(state.structures or {}) do
		if sData.owner == meId then
			local k = sData.kind
			if k == defs.S_SAM or k == 4 then
				table.insert(mySams, sData.tile)
			elseif k == defs.S_CITY or k == defs.S_PORT or k == defs.S_FACTORY or k == 0 or k == 1 or k == 2 then
				table.insert(myEcon, { sid = sid, kind = k, tile = sData.tile, level = sData.level or 1 })
			end
		end
	end

	-- Rank economic hubs by density & wealth (Cluster Score)
	-- Primary Mega-City / Wealth Center gets #1 priority SAM dome!
	for _, hub in ipairs(myEcon) do
		local score = hub.level or 1
		for _, other in ipairs(myEcon) do
			if other.sid ~= hub.sid then
				local d = defs.tile_distance(hub.tile, other.tile)
				if d <= 35 then
					score = score + (other.level or 1)
				end
			end
		end
		hub.score = score
	end

	table.sort(myEcon, function(a, b) return (a.score or 0) > (b.score or 0) end)

	-- 1. Find the highest-scoring unprotected economic hub
	-- If no SAM exists yet (#mySams == 0), SAM #1 MUST protect our Capital Spawn Tile!
	local sp = me and me.spawn_tile
	local targetHub = nil
	if #mySams == 0 and sp and sp > 0 and state:tile_owner(sp) == meId then
		targetHub = sp
	end

	if not targetHub then
		for _, hub in ipairs(myEcon) do
			local protected = false
			for _, samTile in ipairs(mySams) do
				if defs.tile_distance(hub.tile, samTile) <= 60 then
					protected = true
					break
				end
			end
			if not protected then
				targetHub = hub.tile
				break
			end
		end
	end

	-- Search tight ring around targetHub for open, owned SAM placement site
	if targetHub then
		local cx = targetHub % W
		local cy = math.floor(targetHub / W)
		for r = 2, 12 do
			for dy = -r, r do
				for dx = -r, r do
					if math.abs(dx) == r or math.abs(dy) == r then
						local nx = cx + dx
						local ny = cy + dy
						if nx >= 0 and nx < W and ny >= 0 and ny < H then
							local t = ny * W + nx
							if state:tile_owner(t) == meId and map:is_contestable(t) then
								local p = rules:placement("sam", t)
								if p and (p.ok or p.reason == "gold") and not (p.upgrade_sid and p.upgrade_sid > 0) then
									return p.tile or t
								end
							end
						end
					end
				end
			end
		end
	end

	-- 2. Interceptor Corridors (Flight Path Shield):
	-- Fast 2-step threat vector: find closest hostile capital, then sample 50 border tiles toward it!
	local borders = Adapter:GetBorders()
	local me = Adapter:GetMe()
	if borders and borders.border and #mySams < (Hub.State.MaxSAMBatteries or 6) then
		local closestThreatCap = nil
		local minCapDist = math.huge
		local mySpawn = (me and me.spawn_tile) or 0

		for id, oData in pairs(state.owners or {}) do
			if id ~= meId and oData.alive and not state:are_allies(meId, id) then
				local cap = oData.spawn_tile
				if cap and cap > 0 then
					local d = if mySpawn > 0 then defs.tile_distance(mySpawn, cap) else 99999
					if d < minCapDist then
						minCapDist = d
						closestThreatCap = cap
					end
				end
			end
		end

		local closestThreatTile = nil
		if closestThreatCap then
			local minBDist = math.huge
			local count = 0
			for bTile in pairs(borders.border) do
				count = count + 1
				if count % 6 == 0 then -- Stride 6 fast sampling: reduces 10,000 checks down to 1,600
					local d = defs.tile_distance(bTile, closestThreatCap)
					if d < minBDist then
						minBDist = d
						closestThreatTile = bTile
					end
				end
			end
		end

		if closestThreatTile then
			local cx = closestThreatTile % W
			local cy = math.floor(closestThreatTile / W)
			for r = 2, 8 do
				for dy = -r, r do
					for dx = -r, r do
						local nx = cx + dx
						local ny = cy + dy
						if nx >= 0 and nx < W and ny >= 0 and ny < H then
							local t = ny * W + nx
							if state:tile_owner(t) == meId and map:is_contestable(t) then
								local p = rules:placement("sam", t)
								if p and (p.ok or p.reason == "gold") and not (p.upgrade_sid and p.upgrade_sid > 0) then
									return p.tile or t
								end
							end
						end
					end
				end
			end
		end
	end

	return nil
end

local function findNeutralBorderTile()
	if not Adapter:Resolve() then return nil end
	local state = Adapter.State
	local borders = Adapter:GetBorders()
	if not borders or not borders.border then return nil end

	-- O(1) PRE-FLIGHT GUARD: If our borders do not touch any neutral territory, exit instantly!
	-- Eliminates thousands of redundant tile iterations on every single frame.
	if borders.borders_owner and not borders:borders_owner(0) then
		return nil
	end

	local map = state.map
	if not map then return nil end

	local falloutCandidates = {}
	local normalCandidates = {}

	-- Scan direct land border tiles using native _neighbours4
	for bTile in pairs(borders.border) do
		local bNum = tonumber(bTile)
		if bNum and borders._neighbours4 then
			borders:_neighbours4(bNum)
			for i = 1, borders._nn or #borders._nb do
				local nTile = borders._nb[i]
				if map:is_contestable(nTile) then
					if state:tile_owner(nTile) == 0 then
						if state:has_fallout(nTile) then
							table.insert(falloutCandidates, nTile)
						else
							table.insert(normalCandidates, nTile)
						end
					end
				end
			end
		end
		if #falloutCandidates >= 50 or #normalCandidates >= 150 then break end
	end

	local me = Adapter:GetMe()
	local mySpawn = (me and me.spawn_tile) or 0
	local defs = Adapter.Defs

	-- Reclaim fallout zones FIRST to heal border fractures (closest to homeland core first)!
	if #falloutCandidates > 0 then
		if mySpawn > 0 and defs and #falloutCandidates > 1 then
			table.sort(falloutCandidates, function(a, b)
				local da = if (a and a > 0) then defs.tile_distance(a, mySpawn) else 99999
				local db = if (b and b > 0) then defs.tile_distance(b, mySpawn) else 99999
				return (da or 99999) < (db or 99999)
			end)
		end
		return falloutCandidates[1]
	end

	-- Sweep adjacent neutral land (closest to homeland core first)!
	if #normalCandidates > 0 then
		if mySpawn > 0 and defs and #normalCandidates > 1 then
			table.sort(normalCandidates, function(a, b)
				local da = if (a and a > 0) then defs.tile_distance(a, mySpawn) else 99999
				local db = if (b and b > 0) then defs.tile_distance(b, mySpawn) else 99999
				return (da or 99999) < (db or 99999)
			end)
		end
		return normalCandidates[1]
	end

	return nil
end

local function getLiveUnitTile(u)
	if not u or u.dead then return -1 end
	local path = u.path
	local pathLen = path and #path or 0
	if pathLen > 0 then
		local state = Adapter.State
		local curTick = (state and state.tick) or 0
		local startTick = u.start_tick or 0
		local tpt = u.tpt or 1
		if tpt < 1 then tpt = 1 end
		local idx = math.floor((curTick - startTick) * 100 / tpt)
		if idx < 0 then
			idx = 0
		elseif idx >= pathLen then
			idx = pathLen - 1
		end
		return path[idx + 1] or -1
	end
	return u.patrol_tile or u.prev_tile or u.target_tile or -1
end

local cachedWarshipTiles = nil
local cachedWarshipTime = 0

local function getHostileWarshipTiles()
	local now = os.clock()
	if cachedWarshipTiles and (now - cachedWarshipTime < 1.0) then
		return cachedWarshipTiles
	end
	cachedWarshipTiles = {}
	cachedWarshipTime = now

	if not Adapter:Resolve() then return cachedWarshipTiles end
	local state = Adapter.State
	local meId = state and state.local_owner
	local defs = Adapter.Defs
	if not state or not state.units or not meId or not defs then return cachedWarshipTiles end

	local warshipKind = (defs and defs.U_WARSHIP) or 2
	for _, u in pairs(state.units) do
		if type(u) == 'table' and not u.dead and u.kind == warshipKind and u.owner ~= meId and not state:are_allies(meId, u.owner) then
			local wTile = getLiveUnitTile(u)
			if wTile and wTile > 0 then
				table.insert(cachedWarshipTiles, wTile)
			end
		end
	end
	return cachedWarshipTiles
end

local function hasHostileWarshipNear(targetTile, radius)
	local defs = Adapter.Defs
	if not defs then return false end
	local rad = radius or 135
	local hostileWarships = getHostileWarshipTiles()
	for _, wTile in ipairs(hostileWarships) do
		if defs.tile_distance(wTile, targetTile) <= rad then
			return true
		end
	end
	return false
end

local function isCorridorSafeFromWarships(departureTile, landingTile, clearanceRadius, precomputedWarships)
	if not Adapter:Resolve() then return true end
	local state = Adapter.State
	local defs = Adapter.Defs
	local map = state and state.map
	if not defs or not map then return true end

	local clearance = clearanceRadius or 135
	local hostileWarships = precomputedWarships or getHostileWarshipTiles()
	if #hostileWarships == 0 then return true end

	-- 1. Check destination landing tile
	for _, wTile in ipairs(hostileWarships) do
		if defs.tile_distance(wTile, landingTile) <= clearance then
			return false
		end
	end

	-- 2. Check departure coast and line-of-transit corridor
	if departureTile and departureTile > 0 then
		for _, wTile in ipairs(hostileWarships) do
			if defs.tile_distance(wTile, departureTile) <= clearance then
				return false
			end
		end

		local x0, y0 = map:tile_x(departureTile), map:tile_y(departureTile)
		local x1, y1 = map:tile_x(landingTile), map:tile_y(landingTile)
		for _, frac in ipairs({ 0.20, 0.40, 0.60, 0.80 }) do
			local px = math.floor(x0 + (x1 - x0) * frac)
			local py = math.floor(y0 + (y1 - y0) * frac)
			local pTile = map:point_tile(px, py)
			if pTile and pTile > 0 then
				for _, wTile in ipairs(hostileWarships) do
					if defs.tile_distance(wTile, pTile) <= clearance then
						return false
					end
				end
			end
		end
	end

	return true
end

local function findEnemyLandBorderTile(targetMode, filterOwner)
	if not Adapter:Resolve() then return nil, nil, nil, 0, false, 99999, false end
	local state = Adapter.State
	local meId = state.local_owner
	local borders = Adapter:GetBorders()
	if not borders or not borders.border or not meId or meId == 0 then return nil, nil, nil, 0, false, 99999, false end

	local me = Adapter:GetMe()
	local myTroops = (me and me.troops) or 0
	local mySpawn = (me and me.spawn_tile) or 0
	local map = state.map
	local defs = Adapter.Defs
	if not map or not defs then return nil, nil, nil, 0, false, 99999, false end
	local W = borders.W or map.W or 2000
	local H = borders.H or map.H or 1000

	local candidates = {}
	local checkedTiles = {}

	for bTile in pairs(borders.border) do
		local bNum = tonumber(bTile)
		if bNum and borders._neighbours4 then
			borders:_neighbours4(bNum)
			for i = 1, borders._nn or #borders._nb do
				local nTile = borders._nb[i]
				if not checkedTiles[nTile] and map:is_contestable(nTile) then
					checkedTiles[nTile] = true
					local owner = state:tile_owner(nTile)
					if owner ~= 0 and owner ~= meId and not state:are_allies(meId, owner) then
						if not filterOwner or owner == filterOwner then
							local oData = state.owners and state.owners[owner]
							local enemyTroops = (oData and oData.troops) or 0
							local kind = (oData and oData.kind) or 0
							local dist = if mySpawn > 0 then defs.tile_distance(nTile, mySpawn) else 0

							local isBeatable = false
							if kind == 1 and myTroops >= 3000 then
								isBeatable = true
							elseif enemyTroops <= 6000 and myTroops >= 7500 then
								isBeatable = true
							elseif myTroops >= 2000000 then
								isBeatable = (myTroops >= enemyTroops * 0.95)
							elseif myTroops >= 200000 then
								isBeatable = (myTroops >= enemyTroops * 1.25)
							else
								isBeatable = (myTroops >= enemyTroops * 1.60)
							end

							local isCapitulate = (kind ~= 1 and myTroops >= enemyTroops * 8.0)
							local isEasy = (kind == 1)
								or isCapitulate
								or (enemyTroops <= myTroops * 0.25)
								or (enemyTroops <= 3000)

							table.insert(candidates, {
								tile = nTile,
								owner = owner,
								troops = enemyTroops,
								tiles = (oData and oData.tiles) or 0,
								kind = kind,
								name = state:owner_name(owner),
								dist = dist,
								isBeatable = isBeatable,
								isCapitulate = isCapitulate,
								isEasy = isEasy,
							})
						end
					end
				end
			end
		elseif bNum then
			local neighbors = getAdjacentTiles(bNum, W, H)
			for _, nTile in ipairs(neighbors) do
				if not checkedTiles[nTile] and map:is_contestable(nTile) then
					checkedTiles[nTile] = true
					local owner = state:tile_owner(nTile)
					if owner ~= 0 and owner ~= meId and not state:are_allies(meId, owner) then
						if not filterOwner or owner == filterOwner then
							local oData = state.owners and state.owners[owner]
							local enemyTroops = (oData and oData.troops) or 0
							local kind = (oData and oData.kind) or 0
							local dist = if mySpawn > 0 then defs.tile_distance(nTile, mySpawn) else 0

							local isBeatable = false
							if kind == 1 and myTroops >= 3000 then
								isBeatable = true
							elseif enemyTroops <= 6000 and myTroops >= 7500 then
								isBeatable = true
							elseif myTroops >= 2000000 then
								isBeatable = (myTroops >= enemyTroops * 0.95)
							elseif myTroops >= 200000 then
								isBeatable = (myTroops >= enemyTroops * 1.25)
							else
								isBeatable = (myTroops >= enemyTroops * 1.60)
							end

							-- Capitulation threshold (SimAI: outnumbering a bot >= 8:1 triggers immediate full surrender!)
							local isCapitulate = (kind ~= 1 and myTroops >= enemyTroops * 8.0)

							local isEasy = (kind == 1)
								or isCapitulate
								or (enemyTroops <= myTroops * 0.25)
								or (enemyTroops <= 3000)

							table.insert(candidates, {
								tile = nTile,
								owner = owner,
								troops = enemyTroops,
								tiles = (oData and oData.tiles) or 0,
								kind = kind,
								name = state:owner_name(owner),
								dist = dist,
								isBeatable = isBeatable,
								isCapitulate = isCapitulate,
								isEasy = isEasy,
							})
						end
					end
				end
			end
		end
		if #candidates >= 500 then break end
	end

	if #candidates == 0 then return nil, nil, nil, 0, false, 99999, false end

	-- HIERARCHICAL TARGET SELECTION (Defeat in Detail Doctrine):
	-- 1. STRICTLY BEATABLE / EASY FIRST: Never send infantry into an enemy that outnumbers us!
	-- 2. Capitulation targets (8:1 troop advantage triggers instant total surrender!)
	-- 3. Easy / Weak targets first (Tribes or heavily outnumbered nations)
	-- 4. Lowest enemy troops (Eliminate the smallest neighbor first to absorb their cities and close fronts!)
	-- 5. Proximity to homeland core (Shorter travel time & less border attrition)
	table.sort(candidates, function(a, b)
		if targetMode == "Tribes Only" then
			local ak = a.kind or 0
			local bk = b.kind or 0
			if ak ~= bk then return ak == 1 end
		end

		-- 1. Beatable over non-beatable STRICTLY
		local aB = not not (a.isBeatable or a.isEasy)
		local bB = not not (b.isBeatable or b.isEasy)
		if aB ~= bB then
			return aB
		end

		-- 2. Capitulation targets (8:1 advantage = instant annexation)
		local aC = not not a.isCapitulate
		local bC = not not b.isCapitulate
		if aC ~= bC then
			return aC
		end

		-- 3. Easy / Tribes first
		local aE = not not a.isEasy
		local bE = not not b.isEasy
		if aE ~= bE then
			return aE
		end

		-- 4. LOWEST ENEMY TROOPS: Always crush the weakest opponent first!
		-- Never pick a 1M-troop superpower when there is an 80k-troop minor neighbor!
		local at = a.troops or 0
		local bt = b.troops or 0
		if math.abs(at - bt) > 10000 then
			return at < bt
		end

		-- 5. Distance from homeland core
		local da = a.dist or 0
		local db = b.dist or 0
		if math.abs(da - db) > 25 then
			return da < db
		end

		return at < bt
	end)

	local chosen = candidates[1]
	-- STRICT FILTER: If even the best candidate is NOT beatable and NOT easy, do not attack!
	-- If filterOwner is specified (repelling invader or finishing war target), proceed with contact tile.
	if not chosen or ((not filterOwner) and not chosen.isBeatable and not chosen.isEasy) then
		return nil, nil, nil, 0, false, 99999, false
	end
	return chosen.tile, chosen.name, chosen.owner, chosen.troops, chosen.isBeatable, chosen.dist, chosen.isEasy
end

local cachedBeachheadResult = nil
local cachedBeachheadTime = 0

local function findOverseasLandingBeachhead()
	if not Adapter:Resolve() then return nil, nil, nil, 0 end
	local state = Adapter.State
	local meId = state.local_owner
	local me = Adapter:GetMe()
	local ctx = Adapter:GetContext()
	local rules = ctx and ctx.rules
	local borders = Adapter:GetBorders()
	local map = state.map
	local defs = Adapter.Defs
	if not state.owners or not meId or meId == 0 or not rules or not me or not borders or not map or not defs then
		return nil, nil, nil, 0
	end

	-- 0. CACHED RESULT VALIDATION (2.5s TTL):
	-- Avoids massive multi-directional raycasts on every 300ms tick when holding an overseas target.
	local now = os.clock()
	if cachedBeachheadResult and (now - cachedBeachheadTime < 2.5) then
		local cachedTile = cachedBeachheadResult[1]
		if cachedTile and map:is_land(cachedTile) and map:is_contestable(cachedTile) then
			local owner = state:tile_owner(cachedTile)
			if owner ~= meId and not state:are_allies(meId, owner) then
				return table.unpack(cachedBeachheadResult)
			end
		end
		cachedBeachheadResult = nil
	end

	-- 1. Gather friendly coastal border tiles across perimeter (sample max 40 evenly)
	local allCoasts = {}
	for bTile in pairs(borders.border or {}) do
		local bNum = tonumber(bTile)
		if bNum and map:is_coastal(bNum) then
			table.insert(allCoasts, bNum)
		end
	end
	local myCoasts = {}
	if #allCoasts <= 40 then
		myCoasts = allCoasts
	else
		local stride = math.ceil(#allCoasts / 40)
		for i = 1, #allCoasts, stride do
			table.insert(myCoasts, allCoasts[i])
			if #myCoasts >= 40 then break end
		end
	end
	if #myCoasts == 0 then
		local sp = me.spawn_tile
		if sp and sp > 0 then
			table.insert(myCoasts, sp)
		else
			return nil, nil, nil, 0
		end
	end

	local candidates = {}
	local W = borders.W or map.W or 2000
	local H = borders.H or map.H or 1000
	local hostileWarships = getHostileWarshipTiles()

	-- 2. SHORTEST-CROSSING PRINCIPLE (Prinsip Penyeberangan Terpendek):
	-- Shoot 8-direction rays across open water from each friendly coastal tile.
	-- Step by 4 for fast ray traversal. First land tile is the CLOSEST BEACHHEAD!
	local dirs = {
		{1, 0}, {-1, 0}, {0, 1}, {0, -1},
		{1, 1}, {-1, -1}, {1, -1}, {-1, 1}
	}

	local checkedTargets = {}

	for _, cTile in ipairs(myCoasts) do
		local cx = cTile % W
		local cy = math.floor(cTile / W)
		for _, dir in ipairs(dirs) do
			for step = 4, 250, 4 do
				local nx = cx + dir[1] * step
				local ny = cy + dir[2] * step
				if nx >= 0 and nx < W and ny >= 0 and ny < H then
					local t = ny * W + nx
					if map:is_land(t) and map:is_contestable(t) then
						-- First land tile reached on this vector!
						local owner = state:tile_owner(t)
						if owner ~= meId and not state:are_allies(meId, owner) then
							local isDirectLandBorder = borders.borders_owner and (owner ~= 0 and borders:borders_owner(owner))
							if not isDirectLandBorder and not checkedTargets[t] then
								checkedTargets[t] = true
								local prim = rules:primary(t)
								if prim and prim.ok and (prim.type == "boat" or prim.type == "attack" or prim.type == "expand") then
									local oData = state.owners and state.owners[owner]
									local enemyTroops = (oData and oData.troops) or 0
									local kind = if owner == 0 then 1 else ((oData and oData.kind) or 0)
									local name = if owner == 0 then "Neutral Island" else state:owner_name(owner)
									local actualDist = defs.tile_distance(cTile, t)
									local isSafe = isCorridorSafeFromWarships(cTile, t, 135, hostileWarships)

									table.insert(candidates, {
										id = owner,
										name = name,
										kind = kind,
										troops = enemyTroops,
										tiles = (oData and oData.tiles) or 0,
										beachheadTroops = prim.troops or enemyTroops,
										tile = t,
										isSafe = isSafe,
										dist = actualDist,
									})
								end
							end
						end
						-- Break immediately on first land contact so we never target deeper inland tiles
						break
					end
				end
			end
		end
		if #candidates >= 100 then break end
	end

	-- 3. Long-range transoceanic expeditions (when our army >= 300,000 troops, expand to distant continents!)
	local curTroops = (me and me.troops) or 0
	if curTroops >= 300000 then
		for id, oData in pairs(state.owners) do
			if id ~= meId and oData.alive and not state:are_allies(meId, id) then
				local isDirectLandBorder = borders.borders_owner and borders:borders_owner(id)
				if not isDirectLandBorder and oData.tiles and oData.tiles > 0 then
					local closestPoint = nil
					local minD = 99999
					local bestDeparture = nil

					-- Scan enemy structures to find the closest coastal structure
					if state.structures then
						for _, s in pairs(state.structures) do
							if type(s) == 'table' and s.owner == id and not s.dead then
								local landing = rules:boat_landing(s.tile)
								local t = if landing >= 0 then landing else s.tile
								local prim = rules:primary(t)
								if prim and prim.ok and (prim.type == "boat" or prim.type == "attack") then
									for _, c in ipairs(myCoasts) do
										local d = defs.tile_distance(c, t)
										if d < minD then
											minD = d
											closestPoint = t
											bestDeparture = c
										end
									end
								end
							end
						end
					end

					if closestPoint and minD <= 750 then
						local isSafe = isCorridorSafeFromWarships(bestDeparture, closestPoint, 135, hostileWarships)
						table.insert(candidates, {
							id = id,
							name = oData.name,
							kind = oData.kind or 0,
							troops = oData.troops or 0,
							tiles = oData.tiles or 0,
							beachheadTroops = oData.troops or 0,
							tile = closestPoint,
							isSafe = isSafe,
							dist = minD,
						})
					end
				end
			end
		end
	end

	if #candidates == 0 then return nil, nil, nil, 0 end

	-- Sorting hierarchy:
	-- 1. STRICT SAFETY FIRST: Never launch boats into active hostile warship killzones!
	-- 2. Superpower Late-Game (curTroops >= 400k): Prioritize major overseas nations over tiny reefs!
	-- 3. Shortest Sea Crossing: Minimum transit time & lower interception risk.
	-- 4. Tribes / Neutral land: 0 casualties, instant beachhead.
	-- 5. Lowest troops.
	table.sort(candidates, function(a, b)
		local aSafe = not not a.isSafe
		local bSafe = not not b.isSafe
		if aSafe ~= bSafe then
			return aSafe
		end
		if curTroops >= 400000 then
			local aTiles = a.tiles or 0
			local bTiles = b.tiles or 0
			if math.abs(aTiles - bTiles) > 200 then
				return aTiles > bTiles
			end
		end
		local da = a.dist or 0
		local db = b.dist or 0
		if math.abs(da - db) > 15 then
			return da < db
		end
		local ak = a.kind or 0
		local bk = b.kind or 0
		if ak ~= bk then
			return ak == 1
		end
		return (a.troops or 0) < (b.troops or 0)
	end)

	local best = candidates[1]
	-- STRICT CORRIDOR CHECK: If top candidate is unsafe, NO candidate is safe!
	-- Under no circumstances should transport boats commit suicide against warships!
	if not best or not best.isSafe then
		return nil, nil, nil, 0
	end

	local maxLeap = if curTroops >= 300000 then 750 else 260
	if (best.dist or 0) > maxLeap then
		return nil, nil, nil, 0
	end

	cachedBeachheadResult = { best.tile, best.name, best.id, best.beachheadTroops }
	cachedBeachheadTime = now
	return best.tile, best.name, best.id, best.beachheadTroops
end

local function findEnemyBorderTile(targetMode)
	local t, n, id = findEnemyLandBorderTile(targetMode)
	if not t then
		t, n, id = findOverseasLandingBeachhead()
	end
	return t, n, id
end

local function findEnemyCapitalTarget(availableSurplus)
	if not Adapter:Resolve() then return nil, nil, nil end
	local state = Adapter.State
	local meId = state.local_owner
	local me = Adapter:GetMe()
	local ctx = Adapter:GetContext()
	local rules = ctx and ctx.rules
	local borders = Adapter:GetBorders()
	local map = state.map
	local defs = Adapter.Defs
	if not state.owners or not meId or meId == 0 or not rules or not me or not borders or not map or not defs then return nil, nil, nil end

	-- Gather friendly coastal border tiles for distance measurement
	local myCoasts = {}
	for bTile in pairs(borders.border or {}) do
		local bNum = tonumber(bTile)
		if bNum and map:is_coastal(bNum) then
			table.insert(myCoasts, bNum)
			if #myCoasts >= 100 then break end
		end
	end
	if #myCoasts == 0 and me.spawn_tile and me.spawn_tile > 0 then
		table.insert(myCoasts, me.spawn_tile)
	end

	local candidates = {}
	local anyLandEnemy = findEnemyLandBorderTile("All")
	local curTroops = (me and me.troops) or 0

	for id, oData in pairs(state.owners) do
		if id ~= meId and oData.alive and oData.spawned and not state:are_allies(meId, id) then
			local capital = oData.spawn_tile
			if capital and capital > 0 and state:tile_owner(capital) == id then
				local enemyTroops = oData.troops or 0
				if (not availableSurplus) or availableSurplus >= (enemyTroops * 0.85) or (curTroops >= enemyTroops * 1.20) or (enemyTroops <= 15000) then
					local landing = rules:boat_landing(capital)
					local targetTile = if landing >= 0 then landing else capital
					local prim = rules:primary(targetTile)
					if prim and prim.ok and (prim.type == "attack" or prim.type == "boat") then
						local isDirect = borders.borders_owner and borders:borders_owner(id)
						-- STRICT "ONE LANDMASS CONQUEST" DOCTRINE:
						-- While our home continent is contested, only snipe direct land borders.
						-- Once home continent is unified, allow amphibious decapitations against nearby coastal capitals!
						local allowOverseasSnipe = (anyLandEnemy == nil) and (prim.type == "boat") and (curTroops >= 400000)

						if isDirect or allowOverseasSnipe then
							local mySpawn = me.spawn_tile or 0
							local dist = if mySpawn > 0 then defs.tile_distance(mySpawn, targetTile) else 0
							local maxDist = if curTroops >= 400000 then 850 else 180
							if dist <= maxDist then
								local isSafe = true
								if prim.type == "boat" then
									isSafe = isCorridorSafeFromWarships(nil, targetTile, 135)
								end
								if isSafe then
									table.insert(candidates, {
										id = id,
										name = oData.name,
										troops = enemyTroops,
										tiles = oData.tiles or 0,
										tile = targetTile,
										dist = dist,
										isDirect = isDirect,
										isSafe = isSafe,
									})
								end
							end
						end
					end
				end
			end
		end
	end

	if #candidates == 0 then return nil, nil, nil end

	table.sort(candidates, function(a, b)
		local aSafe = not not a.isSafe
		local bSafe = not not b.isSafe
		if aSafe ~= bSafe then
			return aSafe
		end
		local aDir = not not a.isDirect
		local bDir = not not b.isDirect
		if aDir ~= bDir then
			return aDir
		end
		-- In Late Game (curTroops >= 400k), prefer capitulating major nations (high tile count)
		local myCurTroops = (me and me.troops) or 0
		if myCurTroops >= 400000 then
			local aTiles = a.tiles or 0
			local bTiles = b.tiles or 0
			if math.abs(aTiles - bTiles) > 200 then
				return aTiles > bTiles
			end
		end
		local da = a.dist or 0
		local db = b.dist or 0
		if math.abs(da - db) > 20 then
			return da < db
		end
		return (a.troops or 0) < (b.troops or 0)
	end)

	local best = candidates[1]
	return best.tile, best.name, best.id
end

local function getActiveOutboundWavesBreakdown()
	if not Adapter:Resolve() then return 0, 0 end
	local state = Adapter.State
	local meId = state and state.local_owner
	if not state or not meId or meId == 0 then return 0, 0 end

	local totalCount = 0
	local overseasCount = 0

	if state.attacks then
		for _, atk in pairs(state.attacks) do
			if type(atk) == "table" then
				local attackerId = atk.attacker or atk.owner
				if attackerId == meId and not atk.retreating then
					totalCount = totalCount + 1
				end
			end
		end
	end

	if state.units then
		for _, u in pairs(state.units) do
			if type(u) == "table" then
				if u.owner == meId and not u.dead then
					if u.kind == 0 or (Adapter.Defs and u.kind == Adapter.Defs.U_TRANSPORT) then
						totalCount = totalCount + 1
						overseasCount = overseasCount + 1
					end
				end
			end
		end
	end

	return totalCount, overseasCount
end

local function getActiveOutboundWaves()
	local total, _ = getActiveOutboundWavesBreakdown()
	return total
end

local function getActiveAttackAgainst(defenderId)
	if not Adapter:Resolve() then return nil, 0 end
	local state = Adapter.State
	local meId = state and state.local_owner
	if not state or not state.attacks or not meId or meId == 0 or not defenderId then return nil, 0 end
	local totalTroops = 0
	local firstAtk = nil
	for _, atk in pairs(state.attacks) do
		if type(atk) == "table" and not atk.dead and not atk.retreating then
			local aId = atk.attacker or atk.owner
			local tId = atk.target
			if aId == meId and tId == defenderId then
				firstAtk = firstAtk or atk
				totalTroops = totalTroops + (atk.troops or 0)
			end
		end
	end
	return firstAtk, totalTroops
end

local function findBorderContactTile(filterOwner)
	if not Adapter:Resolve() then return nil end
	local state = Adapter.State
	local meId = state and state.local_owner
	local borders = Adapter:GetBorders()
	local map = state and state.map
	if not borders or not borders.border or not meId or meId == 0 or not map or not filterOwner then return nil end

	for bTile in pairs(borders.border) do
		local bNum = tonumber(bTile)
		if bNum and borders._neighbours4 then
			borders:_neighbours4(bNum)
			for i = 1, borders._nn or #borders._nb do
				local nTile = borders._nb[i]
				if map:is_contestable(nTile) and state:tile_owner(nTile) == filterOwner then
					return nTile
				end
			end
		end
	end
	return nil
end

local function isHomelandUnderAttack()
	if not Adapter:Resolve() then return false, nil, nil, nil, 0, nil end
	local state = Adapter.State
	local meId = state and state.local_owner
	if not state or not meId or meId == 0 then return false, nil, nil, nil, 0, nil end

	local maxEnemyTroops = 0
	local worstAttackerId = nil
	local worstAttackerName = nil
	local worstAnchorTile = nil
	local worstAtkObj = nil

	-- 1. Scan land / air attack waves
	if state.attacks then
		for _, atk in pairs(state.attacks) do
			if type(atk) == "table" and not atk.dead and not atk.retreating then
				local attackerId = atk.attacker or atk.owner
				if attackerId and attackerId ~= meId and atk.target == meId then
					local tr = atk.troops or 0
					if tr > maxEnemyTroops then
						maxEnemyTroops = tr
						worstAttackerId = attackerId
						worstAttackerName = state:owner_name(attackerId)
						worstAnchorTile = atk.anchor_tile or atk.head or atk.last_tile
						worstAtkObj = atk
					end
				end
			end
		end
	end

	-- 2. Scan amphibious naval transport boats landing on our shores
	if state.units then
		for _, u in pairs(state.units) do
			if type(u) == "table" and not u.dead and (u.kind == 0 or (Adapter.Defs and u.kind == Adapter.Defs.U_TRANSPORT)) then
				local attackerId = u.owner
				if attackerId and attackerId ~= meId and u.target_tile and state:tile_owner(u.target_tile) == meId then
					local tr = u.troops or 0
					if tr > maxEnemyTroops then
						maxEnemyTroops = tr
						worstAttackerId = attackerId
						worstAttackerName = state:owner_name(attackerId)
						worstAnchorTile = u.target_tile
						worstAtkObj = u
					end
				end
			end
		end
	end

	if worstAttackerId then
		return true, worstAttackerName, worstAttackerId, worstAnchorTile, maxEnemyTroops, worstAtkObj
	end

	return false, nil, nil, nil, 0, nil
end

local function findStrategicSpawnTile()
	if not Adapter:Resolve() then return nil end
	local state = Adapter.State
	local map = state and state.map
	local defs = Adapter.Defs
	if not map or not state or not defs then return nil end

	local W = map.W or 2000
	local H = map.H or 1000
	local meId = state.local_owner or 0

	-- 1. Scan all spawned nations and active human rivals
	local humanSpawns = {}
	local allSpawns = {}
	if state.owners then
		for id, oData in pairs(state.owners) do
			if oData.alive and oData.spawn_tile and oData.spawn_tile > 0 then
				table.insert(allSpawns, { tile = oData.spawn_tile, kind = oData.kind or 0, name = oData.name })
				local isHuman = (oData.kind == defs.KIND_HUMAN) or (oData.user_id and oData.user_id > 0)
				if isHuman and id ~= meId then
					table.insert(humanSpawns, oData.spawn_tile)
				end
			end
		end
	end

	-- 2. Fast global coastal sweep using native map.coast_list buffer
	local coastList = map.coast_list
	local coastCount = map.coast_count or 0
	local readi32 = buffer.readi32

	local candidates = {}
	local step = math.max(1, math.floor(coastCount / 1200))

	for i = 0, coastCount - 1, step do
		local cTile = readi32(coastList, i * 4)
		if map:is_contestable(cTile) and not state:has_fallout(cTile) and state:tile_owner(cTile) == 0 then
			-- [A] HUMAN DISTANCE FILTER (Strict Non-Aggression Moat)
			-- Never spawn within 160 tiles of another human player!
			local tooCloseToHuman = false
			local minHumanDist = 99999
			for _, hTile in ipairs(humanSpawns) do
				local d = defs.tile_distance(cTile, hTile)
				if d < 160 then
					tooCloseToHuman = true
					break
				end
				if d < minHumanDist then
					minHumanDist = d
				end
			end

			if not tooCloseToHuman then
				-- [B] BOT & NATION CROWDING DENSITY
				-- Count hostile capitals and tribes within 80 tiles
				local nearbyBots = 0
				local nearbyTribes = 0
				local closestBotDist = 99999
				for _, s in ipairs(allSpawns) do
					local d = defs.tile_distance(cTile, s.tile)
					if d < closestBotDist then closestBotDist = d end
					if d <= 80 then
						if s.kind == 1 then
							nearbyTribes = nearbyTribes + 1
						else
							nearbyBots = nearbyBots + 1
						end
					end
				end

				-- Immediate buffer: reject if another nation capital is within 25 tiles (spawn blockage)
				if closestBotDist >= 25 then
					-- [C] DEFENSIVE WATER MOAT & PENINSULA GEOGRAPHY (r = 15 tiles)
					local cx = cTile % W
					local cy = math.floor(cTile / W)
					local waterCount = 0
					local landCount = 0
					local freeLandCount = 0

					for dy = -15, 15, 5 do
						for dx = -15, 15, 5 do
							local nx = (cx + dx) % W
							local ny = cy + dy
							if ny >= 0 and ny < H then
								local t = ny * W + nx
								if map:is_land(t) then
									landCount = landCount + 1
									if state:tile_owner(t) == 0 and map:is_contestable(t) then
										freeLandCount = freeLandCount + 1
									end
								else
									waterCount = waterCount + 1
								end
							end
						end
					end

					local totalSampled = waterCount + landCount
					local waterPct = if totalSampled > 0 then (waterCount / totalSampled) else 0

					-- [D] MULTI-FACTOR STRATEGIC SCORING:
					local score = 100

					-- 1. Natural Water Defensibility (Peninsulas, Corners, Island Bastions):
					-- 45% - 75% water provides natural water shields on 2-3 sides, leaving only 1 narrow land border to defend!
					if waterPct >= 0.45 and waterPct <= 0.75 then
						score = score + 50 -- Prime peninsula / coastal corner
					elseif waterPct > 0.75 and waterPct <= 0.88 then
						score = score + 35 -- Island bastion (Great Britain, Japan, Australia)
					elseif waterPct < 0.25 then
						score = score - 30 -- Flatland inland (exposed to 360-degree multi-front war)
					elseif waterPct > 0.90 then
						score = score - 50 -- Isolated atoll with zero landmass
					end

					-- 2. Crowding Factor (Peaceful Frontier vs War-Torn Death Trap):
					if nearbyBots == 0 then
						score = score + 60 -- Uncontested frontier (Oceania, Patagonia, Southern Africa)!
					elseif nearbyBots == 1 then
						score = score + 40
					elseif nearbyBots == 2 then
						score = score + 20
					elseif nearbyBots >= 5 then
						score = score - (nearbyBots * 15) -- Heavily crowded (Central Europe, Balkans)
					end

					-- 3. Human Isolation Bonus:
					if minHumanDist >= 400 then
						score = score + 40 -- Entire continent between us and human rivals
					elseif minHumanDist >= 250 then
						score = score + 20
					end

					-- 4. Free Expansion Room & Tribal Prey:
					score = score + (freeLandCount * 2.5) -- Unclaimed neutral land ready for rapid blitz
					score = score + (nearbyTribes * 15)   -- Weak tribes ready for instant free absorption

					table.insert(candidates, {
						tile = cTile,
						score = score,
						x = cx,
						y = cy,
						nearbyBots = nearbyBots,
						waterPct = math.floor(waterPct * 100),
					})
				end
			end
		end
	end

	if #candidates == 0 then return nil end

	table.sort(candidates, function(a, b) return (a.score or 0) > (b.score or 0) end)
	local chosen = candidates[1]
	return chosen.tile
end

local function getFriendlySiloTile()
	if not Adapter:Resolve() then return nil end
	local state = Adapter.State
	local meId = state and state.local_owner
	local defs = Adapter.Defs
	if not state or not state.structures or not meId or not defs then return nil end
	local siloKind = (defs and defs.S_SILO) or 5
	for _, s in pairs(state.structures) do
		if type(s) == 'table' and s.owner == meId and not s.dead and (s.kind == siloKind or s.kind == 5) then
			return s.tile
		end
	end
	local me = Adapter:GetMe()
	return me and me.spawn_tile
end

local function isBlastZoneSafeFromFriendlyFire(targetTile, blastRadius)
	if not Adapter:Resolve() then return false end
	local state = Adapter.State
	local meId = state and state.local_owner
	local defs = Adapter.Defs
	local map = state and state.map
	if not state or not meId or meId == 0 or not defs or not map then return false end

	local radius = blastRadius or 100
	local safetyClearance = radius + 15 -- 115 tiles safety margin for friendly structures

	-- 1. CRITICAL: Friendly structures must NEVER be within the blast circle!
	if state.structures then
		for _, s in pairs(state.structures) do
		if type(s) == 'table' and s.owner == meId and not s.dead then
				if defs.tile_distance(s.tile, targetTile) <= safetyClearance then
					return false
				end
			end
		end
	end

	-- 2. Friendly capital core check
	local me = Adapter:GetMe()
	if me and me.spawn_tile and me.spawn_tile > 0 then
		if defs.tile_distance(me.spawn_tile, targetTile) <= safetyClearance then
			return false
		end
	end

	-- 3. Friendly territory encroachment check
	-- If our own borders or land tiles are heavily caught in the blast, reject!
	local W = map.W or 2000
	local H = map.H or 1000
	local tx = targetTile % W
	local ty = math.floor(targetTile / W)
	local friendlyTilesInBlast = 0
	local step = 10
	for dy = -radius, radius, step do
		for dx = -radius, radius, step do
			if dx * dx + dy * dy <= radius * radius then
				local nx = tx + dx
				local ny = ty + dy
				if nx >= 0 and nx < W and ny >= 0 and ny < H then
					local t = ny * W + nx
					if state:tile_owner(t) == meId then
						friendlyTilesInBlast = friendlyTilesInBlast + 1
						if friendlyTilesInBlast >= 6 then
							return false -- Too much friendly territory would be nuked!
						end
					end
				end
			end
		end
	end

	return true
end

local function countHostileSAMsAlongFlightPath(fromTile, toTile)
	if not Adapter:Resolve() then return 0, 0 end
	local state = Adapter.State
	local meId = state and state.local_owner
	local defs = Adapter.Defs
	local map = state and state.map
	if not state or not state.structures or not meId or not defs or not map then return 0, 0 end
	if not fromTile or fromTile <= 0 or not toTile or toTile <= 0 then return 0, 0 end

	local samKind = (defs and defs.S_SAM) or 4
	local totalMissiles = 0
	local samCount = 0

	-- In SimNukes engine:
	-- SAMs can ONLY intercept during terminal descent (within NUKE_TARGETABLE_OF = 150 tiles of toTile)
	-- or near departure (within 150 tiles of fromTile).
	-- During mid-flight (> 150 tiles), the missile flies in sub-orbital arc out of reach!
	for _, s in pairs(state.structures) do
		if type(s) == 'table' and s.owner ~= meId and s.owner ~= 0 and (s.kind == samKind or s.kind == 4) and not s.dead and not state:are_allies(meId, s.owner) then
			local sTile = s.tile
			local distToTarget = defs.tile_distance(sTile, toTile)
			local lvl = s.level or 1
			-- sam_range per level: 1 = 70, 2 = 81.4, 3 = 90, 4 = 96.6, 5 = 102
			local effectiveSamRange = 70 + (lvl - 1) * 12

			-- A SAM can intercept if its coverage circle touches the descent target or arrival corridor (150 tiles)
			if distToTarget <= (effectiveSamRange + 15) or (distToTarget <= 150 and defs.tile_distance(sTile, fromTile) <= effectiveSamRange) then
				samCount = samCount + 1
				totalMissiles = totalMissiles + lvl
			end
		end
	end

	return totalMissiles, samCount
end

local function countEnemySAMsCovering(targetTile)
	local mySilo = getFriendlySiloTile()
	if mySilo then
		return countHostileSAMsAlongFlightPath(mySilo, targetTile)
	end
	return 0, 0
end

local recentlyNukedTiles = {}

local function isRecentlyNuked(tile, clearance)
	local now = os.clock()
	local distCl = clearance or 70
	local defs = Adapter.Defs
	if not defs then return false end
	for t, tTime in pairs(recentlyNukedTiles) do
		if now - tTime < 90.0 then
			if defs.tile_distance(t, tile) <= distCl then
				return true
			end
		else
			recentlyNukedTiles[t] = nil
		end
	end
	return false
end

local function findSmartNukeTarget()
	if not Adapter:Resolve() then return nil end
	local state = Adapter.State
	local meId = state.local_owner
	local me = Adapter:GetMe()
	local defs = Adapter.Defs
	local map = state.map
	if not state.owners or not meId or meId == 0 or not me or not defs or not map then return nil end

	local mySilo = getFriendlySiloTile()
	if not mySilo then return nil end

	local enemyStructs = {}
	if state.structures then
		for _, s in pairs(state.structures) do
		if type(s) == 'table' and s.owner ~= meId and s.owner ~= 0 and not s.dead and not state:are_allies(meId, s.owner) then
				local oData = state.owners[s.owner]
				-- Prioritize major powers and growing threats (>= 2,000 tiles), skip dead remnants
				if oData and (oData.tiles or 0) >= 2000 then
					table.insert(enemyStructs, s)
				end
			end
		end
	end

	if #enemyStructs == 0 then return nil end

	local candidates = {}
	local checkedClusters = {}
	local W = map.W or 2000

	-- Evaluate clusters centered on each candidate enemy structure
	for _, center in ipairs(enemyStructs) do
		local cTile = center.tile
		local clusterKey = math.floor((cTile % W) / 40) .. "_" .. math.floor(cTile / W / 40)
		if not checkedClusters[clusterKey] and not state:has_fallout(cTile) and not isRecentlyNuked(cTile, 70) then
			checkedClusters[clusterKey] = true

			-- STRICT SAFETY GUARD: Blast zone (100 tiles) MUST NOT damage our own structures or land!
			if isBlastZoneSafeFromFriendlyFire(cTile, 100) then
				local oData = state.owners[center.owner]
				local enemyTiles = oData and oData.tiles or 0
				local enemyTroops = oData and oData.troops or 0

				-- Count high-value facilities within 90-tile radius of this epicenter
				local count = 0
				local score = 0
				local hasSilo = false
				local hasCapital = false
				local cityCount = 0

				for _, s in ipairs(enemyStructs) do
					local d = defs.tile_distance(s.tile, cTile)
					if d <= 90 then
						count = count + 1
						local k = s.kind
						local lvl = s.level or 1
						if k == 5 or k == defs.S_SILO then
							score = score + 35
							hasSilo = true
						elseif k == 4 or k == defs.S_SAM then
							score = score + 20 * lvl
						elseif k == 0 or k == defs.S_CITY then
							score = score + 12 * lvl
							cityCount = cityCount + 1
						elseif k == 1 or k == defs.S_PORT then
							score = score + 10 * lvl
						elseif k == 2 or k == defs.S_FACTORY then
							score = score + 10 * lvl
						else
							score = score + 5
						end
					end
				end

				-- Check if any enemy capital is caught in this cluster
				for id, o in pairs(state.owners) do
					if id ~= meId and o.alive and not state:are_allies(meId, id) then
						local cap = o.spawn_tile
						if cap and cap > 0 and state:tile_owner(cap) == id then
							if defs.tile_distance(cap, cTile) <= 90 then
								score = score + 30
								hasCapital = true
							end
						end
					end
				end

				-- Major Power Scale Multiplier (focus superweapons on rival superpowers):
				local scaleMult = if enemyTiles >= 50000 then 1.5
					elseif enemyTiles >= 20000 then 1.25
					elseif enemyTiles >= 8000 then 1.0
					else 0.4

				score = math.floor(score * scaleMult)

				-- Minimum Viability Filter:
				-- A 5M Hydrogen Bomb must hit at least 2+ structures, OR a Missile Silo, OR a National Capital!
				-- NEVER waste a 5M bomb on a lone empty building in the desert!
				if count >= 2 or hasSilo or hasCapital or score >= 35 then
					local samMissiles, samCount = countHostileSAMsAlongFlightPath(mySilo, cTile)

					table.insert(candidates, {
						owner = center.owner,
						name = oData and oData.name or "Rival Superpower",
						tile = cTile,
						score = score,
						count = count,
						cityCount = cityCount,
						hasSilo = hasSilo,
						hasCapital = hasCapital,
						samMissiles = samMissiles,
						samCount = samCount,
						tiles = enemyTiles,
						troops = enemyTroops,
						kindName = string.format("Cluster (%d Facilities, %d Cities)", count, cityCount)
					})
				end
			end
		end
	end

	if #candidates == 0 then return nil end

	-- Prioritize:
	-- 1. Highest Strategic Score (Dense clusters with Silos, SAMs, and Cities first!)
	-- 2. Lower SAM Interceptors (Lethal bypass guaranteed)
	-- 3. Largest enemy empire
	table.sort(candidates, function(a, b)
		local sa = a.score or 0
		local sb = b.score or 0
		if math.abs(sa - sb) > 25 then
			return sa > sb
		end
		local ma = a.samMissiles or 0
		local mb = b.samMissiles or 0
		if ma ~= mb then
			return ma < mb
		end
		return (a.tiles or 0) > (b.tiles or 0)
	end)

	return candidates[1]
end

-- ==============================================================================
-- [4] RUNTIME FEATURE LOOPS
-- ==============================================================================

-- 4.1 Master Smart Auto Play Decision Loop
local lastAttackTick = 0
local lastBuildTick = 0
local lastNukeTick = 0
local matchOverTick = nil
local eliminatedTick = nil
local currentWarTargetId = nil
local currentWarTargetName = "None"

local function triggerPlayAgain()
	if not Adapter:Resolve() then return false end
	local session = Adapter.Session
	local client = Adapter.Client
	local ui = client and client.ui

	-- 1. Official in-game Play Again button if visible or available
	if ui and ui._spec_again and ui._spec_again.pressed and ui._spec_again.pressed.Fire then
		ui._spec_again.pressed:Fire()
		RuntimeStats.Status = "Playing Again..."
		Hub:Notify("Match Over", "Auto Play Again triggered!", "refresh-cw")
		return true
	end

	-- 2. If in solo simulation, restart solo match
	if session and session.mode == 1 then
		session:start_solo(session.difficulty or 1, session.map_id)
		RuntimeStats.Status = "Restarting Solo Match..."
		Hub:Notify("Solo Match", "Restarting solo match...", "refresh-cw")
		return true
	end

	-- 3. If in multiplayer, join multiplayer queue
	if session and session:multiplayer_available() then
		session:join_multiplayer()
		RuntimeStats.Status = "Requeueing Match..."
		Hub:Notify("Multiplayer", "Requeueing fresh match...", "refresh-cw")
		return true
	end

	return false
end

local function bodySmartAutoPlay()
	if not Adapter:Resolve() then
		RuntimeStats.Status = "Resolving Game State..."
		return
	end

	local session = Adapter.Session
	local state = Adapter.State

	-- Phase 1: Lobby & Spectator Handling
	local isLobby = (session.mode == 0) or (not state) or (not state.local_owner) or (state.local_owner == 0)
	if isLobby then
		local client = Adapter.Client
		local ui = client and client.ui
		local isSpectating = ui and ui._spec_again and ui._spec_again.visible

		if isSpectating and Hub.State.AutoPlayAgain then
			local now = os.clock()
			if not eliminatedTick then eliminatedTick = now end
			if now - eliminatedTick >= 3.0 then
				eliminatedTick = now + 999
				triggerPlayAgain()
			end
			return
		end

		RuntimeStats.Phase = "Lobby / Title"
		RuntimeStats.Status = "In Lobby"
		-- Only auto-join if the user explicitly enabled the dedicated 'Auto Join Match' toggle in Lobby & Meta tab
		if Hub.State.AutoJoinMatch and session:multiplayer_available() then
			RuntimeStats.Status = "Joining Match..."
			session:join_multiplayer()
			task.wait(1.0)
		end
		return
	end

	-- Phase 1.5: Match Over / Victory State
	if state.phase == 2 then
		local winName = if state.winner and state.winner > 0 then state:owner_name(state.winner) else "None"
		RuntimeStats.Phase = "Match Ended"
		RuntimeStats.Status = "Winner: " .. tostring(winName)
		if Hub.State.AutoPlayAgain then
			local now = os.clock()
			if not matchOverTick then matchOverTick = now end
			if now - matchOverTick >= 4.0 then
				matchOverTick = now + 999
				triggerPlayAgain()
			end
		end
		return
	else
		matchOverTick = nil
	end

	-- Phase 2: Spawn Selection
	local me = Adapter:GetMe()
	local needsSpawn = (me == nil) or (not me.spawned)
	if needsSpawn then
		RuntimeStats.Phase = "Capital Selection"
		if Hub.State.AutoSpawnCapital or Hub.State.SmartAutoPlay then
			RuntimeStats.Status = "Finding Strategic Coast..."
			local spawnTile = findStrategicSpawnTile()
			if spawnTile then
				Adapter:SendIntent({ type = "spawn", tile = spawnTile })
				RuntimeStats.LastAction = "Capital Placed @ " .. tostring(spawnTile)
				RuntimeStats.Status = "Capital Placed - Initializing"
				task.wait(0.5)
			end
		end
		return
	end

	-- Phase 3: Active Combat & Match Management
	if not me or not me.alive then
		RuntimeStats.Phase = "Eliminated"
		RuntimeStats.Status = "Seeking AI Takeover..."
		local tookOver = false
		if (Hub.State.AutoTakeover or Hub.State.SmartAutoPlay) and session.take_over then
			for id, oData in pairs(state.owners) do
				if oData.alive and oData.kind == 1 and (oData.tiles or 0) > 100 then
					if session:can_take_over(id) then
						session:take_over(id)
						RuntimeStats.LastAction = "Adopted Nation " .. tostring(oData.name)
						tookOver = true
						task.wait(1.0)
						break
					end
				end
			end
		end
		if not tookOver and Hub.State.AutoPlayAgain then
			local now = os.clock()
			if not eliminatedTick then eliminatedTick = now end
			if now - eliminatedTick >= 3.0 then
				eliminatedTick = now + 999
				triggerPlayAgain()
			end
		else
			eliminatedTick = nil
		end
		return
	else
		eliminatedTick = nil
	end

	RuntimeStats.Phase = "Active Combat"
	RuntimeStats.Nation = tostring(me.name or "Roi")
	RuntimeStats.Tiles = me.tiles or 0
	RuntimeStats.Troops = me.troops or 0
	RuntimeStats.Cap = me.max_troops or 0
	RuntimeStats.Gold = me.gold or 0
	RuntimeStats.Income = me.income or 0

	if RuntimeStats.Status == "Finding Strategic Coast..." or RuntimeStats.Status == "Capital Placed - Initializing" or RuntimeStats.Status == "In Lobby" then
		RuntimeStats.Status = "Expanding Territory"
	end

	-- [A] PRIORITY 1: AUTO REINFORCE (+20% Instant Troops)
	local canReinforce = type(session.has_unlock) == "function" and session:has_unlock("reinforce")
	if canReinforce then
		local readyTick = (state.reinforce_ready and state.reinforce_ready[me.id]) or 0
		local ticksLeft = readyTick - (state.tick or 0)
		if ticksLeft <= 0 then
			RuntimeStats.ReinforceTime = "Ready"
			if (Hub.State.AutoReinforce or Hub.State.SmartAutoPlay) and (tonumber(me.troops) or 0) < (tonumber(me.max_troops) or 0) then
				Adapter:SendIntent({ type = "reinforce" })
				RuntimeStats.LastAction = "Claimed +20% Reinforcements"
				RuntimeStats.ReinforceTime = "120s"
			end
		else
			RuntimeStats.ReinforceTime = string.format("%ds", math.ceil(ticksLeft / 10))
		end
	else
		RuntimeStats.ReinforceTime = "Locked"
	end

	-- [B] PRIORITY 2: SMART MILITARY-INDUSTRIAL ECONOMY & SUPERWEAPONS
	local now = os.clock()
	if now - lastBuildTick >= (Hub.State.BuildDelay or 1.5) then
		lastBuildTick = now
		local mySpawn = me.spawn_tile
		local curGold = me.gold or 0
		local curTroops = me.troops or 0
		local myTiles = me.tiles or 0

		-- Count existing friendly structures
		local myCityCount = 0
		local myPortCount = 0
		local myFactoryCount = 0
		local mySiloCount = 0
		local mySamCount = 0
		local myDefenseCount = 0

		if state.structures then
			for _, s in pairs(state.structures) do
				if type(s) == "table" and s.owner == me.id and not s.dead then
					local k = s.kind
					if k == 0 or (Adapter.Defs and k == Adapter.Defs.S_CITY) then
						myCityCount = myCityCount + 1
					elseif k == 1 or (Adapter.Defs and k == Adapter.Defs.S_PORT) then
						myPortCount = myPortCount + 1
					elseif k == 2 or (Adapter.Defs and k == Adapter.Defs.S_FACTORY) then
						myFactoryCount = myFactoryCount + 1
					elseif k == 3 or (Adapter.Defs and k == Adapter.Defs.S_DEFENSE) then
						myDefenseCount = myDefenseCount + 1
					elseif k == 4 or (Adapter.Defs and k == Adapter.Defs.S_SAM) then
						mySamCount = mySamCount + 1
					elseif k == 5 or (Adapter.Defs and k == Adapter.Defs.S_SILO) then
						mySiloCount = mySiloCount + 1
					end
				end
			end
		end

		RuntimeStats.SAMBuilt = mySamCount
		RuntimeStats.CitiesBuilt = myCityCount

		-- Determine Macro Stage:
		-- Stage 1 (Opening / Early): Land < 30k tiles and Gold < 1.5M -> Compound Cities & Ports
		-- Stage 2 (Midgame): Land 30k - 100k tiles -> Distributed SAM Shield + 1 Silo + Warships
		-- Stage 3 (Endgame Rivalry): Land > 90k or Gold > 10M -> TREASURY STOCKPILE LOCK for MIRV/Hydrogen
		-- Macro Stage:
		local isMidGame = (myTiles >= 25000) or (curTroops >= 200000) or (myCityCount >= 3)
		local isEndGame = (myTiles >= 90000) or (curGold >= 10000000)
		local savingForSilo = isMidGame and (mySamCount == 0 or mySiloCount == 0) and myCityCount >= 4 and myPortCount >= 1 and curGold < 1550000

		local ctx = Adapter:GetContext()
		local rules = ctx and ctx.rules

		-- [STEP 1] FOUNDATION FARMS: Early Gold Farming (Port / Factory First!)
		-- Sesuai SimAIEconomy: Port jika punya pantai (trade ships), Factory jika landlocked (trade trucks).
		if (Hub.State.AutoBuildPorts or Hub.State.SmartAutoPlay) and myPortCount < 1 and not isEndGame then
			local portAvail = rules and rules:availability("port")
			if portAvail and portAvail.ok then
				local portTile = findPortSite()
				if portTile then
					local built = Adapter:BuildStructure("port", portTile)
					if built then
						myPortCount = myPortCount + 1
						RuntimeStats.LastAction = "Built Port #1 (Sea Trade Gold Farm)"
					end
				end
			end
		end

		if (Hub.State.AutoBuildFactories or Hub.State.SmartAutoPlay) and myFactoryCount < 1 and not isEndGame then
			local factAvail = rules and rules:availability("factory")
			if factAvail and factAvail.ok then
				local factTile = findFactorySite()
				if factTile then
					local built = Adapter:BuildStructure("factory", factTile)
					if built then
						myFactoryCount = myFactoryCount + 1
						RuntimeStats.LastAction = "Built Factory #1 (Road Truck Gold Farm)"
					end
				end
			end
		end

		-- [STEP 2] CORE EXPANSION: City Stacking (+250k Troop Cap per City!)
		-- Early Game: Bangun City 1, 2, 3 sesegera mungkin agar cap troops tembus 750k+!
		-- Mid Game: Kembangkan hingga 6-10 Cities, namun prioritaskan Silo (1M gold) saat midgame!
		local maxCities = if not isMidGame then 4 elseif savingForSilo then 5 elseif not isEndGame then 8 else 12
		if (Hub.State.AutoBuildCities or Hub.State.SmartAutoPlay) and myCityCount < maxCities then
			local cityAvail = rules and rules:availability("city")
			if cityAvail and cityAvail.ok then
				local cityTile, isUpgrade = findCitySite()
				if cityTile then
					local built = Adapter:BuildStructure("city", cityTile)
					if built then
						myCityCount = myCityCount + 1
						RuntimeStats.LastAction = if isUpgrade then "Upgraded City (Faster Growth)" else string.format("Built City #%d (+250k Cap)", myCityCount)
					end
				end
			end
		end

		-- [STEP 3] SECONDARY ECONOMY: Port #2 & Factory #2 (Melipatgandakan penghasilan)
		if (Hub.State.AutoBuildPorts or Hub.State.SmartAutoPlay) and myPortCount < 2 and myCityCount >= 2 and not isEndGame then
			local portAvail = rules and rules:availability("port")
			if portAvail and portAvail.ok then
				local portTile = findPortSite()
				if portTile then
					Adapter:BuildStructure("port", portTile)
				end
			end
		end

		if (Hub.State.AutoBuildFactories or Hub.State.SmartAutoPlay) and myFactoryCount < 2 and myCityCount >= 2 and not isEndGame then
			local factAvail = rules and rules:availability("factory")
			if factAvail and factAvail.ok then
				local factTile = findFactorySite()
				if factTile then
					Adapter:BuildStructure("factory", factTile)
				end
			end
		end

		-- [STEP 4] BORDER CHOKEPOINT DEFENSE: Menahan musuh kuat HANYA di perbatasan aktif
		-- Matches SimAIEconomy: hanya dibangun saat ada ancaman nyata, gold >= 100k, dan ekonomi berjalan!
		-- Saat savingForSilo aktif, tahan pembuatan Defense Post tambahan agar treasury cepat tembus 1M!
		local maxAllowedDef = if myTiles >= 70000 and myCityCount >= 5 then 4 elseif myTiles >= 35000 and myCityCount >= 3 then 2 else 1
		maxAllowedDef = math.max(maxAllowedDef, Hub.State.MaxDefensePosts or 1)
		if (Hub.State.AutoDefensePosts or Hub.State.SmartAutoPlay) and not savingForSilo and myCityCount >= 1 and curGold >= 100000 and (myPortCount >= 1 or myFactoryCount >= 1) and myDefenseCount < maxAllowedDef then
			local defAvail = rules and rules:availability("defense")
			if defAvail and defAvail.ok then
				local defenseTile = findDefensePostSite()
				if defenseTile then
					local built = Adapter:BuildStructure("defense", defenseTile)
					if built then
						myDefenseCount = myDefenseCount + 1
						RuntimeStats.LastAction = "Built Defense Post on Border Chokepoint (5x Bonus)"
					end
				end
			end
		end

		-- [STEP 5] NAVAL PATROL FLEET: Menjaga pantai & memburu perahu serbu musuh
		local myWarshipCount = 0
		if state.units then
			for _, u in pairs(state.units) do
				if type(u) == "table" and u.owner == me.id and u.kind == 2 and not u.dead then
					myWarshipCount = myWarshipCount + 1
				end
			end
		end
		if myWarshipCount < 2 and curGold >= (if savingForSilo then 1300000 else 300000) and myPortCount >= 1 and (Hub.State.AutoBuildPorts or Hub.State.SmartAutoPlay) then
			local warshipAvail = rules and rules:availability("warship")
			if warshipAvail and warshipAvail.ok then
				local built = Adapter:BuildWarship()
				if built then
					RuntimeStats.LastAction = string.format("Commissioned Warship #%d", myWarshipCount + 1)
				end
			end
		end

		-- [STEP 6] ANTI-BALLISTIC MISSILE DOME (SAM Battery #1 melindungi Capital Spawn Tile!)
		-- Wajib dibangun sesegera mungkin di midgame agar Capital & Cities kebal dari serangan nuke bot!
		local maxSams = Hub.State.MaxSAMBatteries or 6
		if (Hub.State.AutoSAMShield or Hub.State.SmartAutoPlay) and mySamCount < maxSams and (isMidGame or myCityCount >= 2) then
			local samAvail = rules and rules:availability("sam")
			if samAvail and samAvail.ok then
				local clusterTile = findUnprotectedEconomicCluster()
				if clusterTile then
					local built = Adapter:BuildStructure("sam", clusterTile)
					if built then
						mySamCount = mySamCount + 1
						RuntimeStats.LastAction = string.format("Deployed SAM Battery #%d (Anti-Nuke Umbrella)", mySamCount)
					end
				end
			end
		end

		-- [STEP 7] MISSILE SILO (1 Silo di pedalaman terlindungi SAM)
		if (Hub.State.AutoBuildSilos or Hub.State.SmartAutoPlay) and mySiloCount < 1 and isMidGame then
			local siloAvail = rules and rules:availability("silo")
			if siloAvail and siloAvail.ok then
				local siloTile = findSiloSite()
				if siloTile then
					local built = Adapter:BuildStructure("silo", siloTile)
					if built then
						mySiloCount = 1
						RuntimeStats.LastAction = "Constructed Missile Silo"
					end
				end
			end
		end

		-- 7. SUPERWEAPON PREEMPTIVE ARSENAL (MIRV & HYDROGEN BOMBS):
		-- If we have Silo and treasury, find rival superpower and vaporize them!
		if (Hub.State.AutoNuke or Hub.State.SmartAutoPlay) and mySiloCount >= 1 and (now - lastNukeTick >= 8.0) then
			local target = findSmartNukeTarget()
			if target then
				local ctx = Adapter:GetContext()
				local rules = ctx and ctx.rules
				local mirvAvail = rules and rules:availability("mirv")
				local hydAvail = rules and rules:availability("hydrogen")
				local atomAvail = rules and rules:availability("atom")

				local mirvCost = (mirvAvail and mirvAvail.cost) or 25000000
				local hydCost = (hydAvail and hydAvail.cost) or 5000000
				local atomCost = (atomAvail and atomAvail.cost) or 750000

				-- Option A: MIRV (25M base) - Saturates & bypasses heavy SAM networks (3+ SAMs or dense mega-clusters)
				local useMirv = curGold >= mirvCost and (target.samMissiles >= 3 or target.score >= 120 or curGold >= 35000000) and (mirvAvail == nil or mirvAvail.ok)
				if useMirv then
					local launched = Adapter:LaunchNuke("mirv", target.tile)
					if launched then
						lastNukeTick = now
						recentlyNukedTiles[target.tile] = now
						RuntimeStats.NukesLaunched = (RuntimeStats.NukesLaunched or 0) + 1
						RuntimeStats.LastAction = string.format("MIRV Barrage hit %s [%s]", target.name, target.kindName)
						Hub:Notify("Superweapon Fired", string.format("MIRV Barrage launched at %s [%s]!", target.name, target.kindName), 4)
					end
				-- Option B: Hydrogen Bomb (5M) with dynamic Atom Baits matching exact SAM interceptor capacity
				elseif curGold >= hydCost and (hydAvail == nil or hydAvail.ok) then
					local samCount = target.samMissiles or 0
					local totalSalvoCost = hydCost + atomCost * samCount

					if samCount == 0 then
						-- 0 SAM missiles: Direct lethal Hydrogen strike!
						local launched = Adapter:LaunchNuke("hydrogen", target.tile)
						if launched then
							lastNukeTick = now
							recentlyNukedTiles[target.tile] = now
							RuntimeStats.NukesLaunched = (RuntimeStats.NukesLaunched or 0) + 1
							RuntimeStats.LastAction = string.format("Hydrogen Nuked %s [%s, 0 SAM]", target.name, target.kindName)
							Hub:Notify("Nuke Fired", string.format("Hydrogen bomb detonating on %s [%s]!", target.name, target.kindName), 4)
						end
					elseif samCount <= 3 and curGold >= totalSalvoCost then
						-- Fire exact number of Atom baits to drain all hostile SAM interceptors
						for b = 1, samCount do
							Adapter:LaunchNuke("atom", target.tile)
							task.wait(0.35)
						end
						local launched = Adapter:LaunchNuke("hydrogen", target.tile)
						if launched then
							lastNukeTick = now
							recentlyNukedTiles[target.tile] = now
							RuntimeStats.NukesLaunched = (RuntimeStats.NukesLaunched or 0) + (samCount + 1)
							RuntimeStats.LastAction = string.format("%d-Bait Salvo Nuked %s [%s]", samCount, target.name, target.kindName)
							Hub:Notify("Salvo Fired", string.format("Salvo (%d Atom Baits + H) wiped out SAM at %s!", samCount, target.name), 4)
						end
					end
				-- Option C: Atom Bomb (750k) - Fast surgical strike on 0-SAM enemy capitals or clusters
				elseif curGold >= atomCost and (target.samMissiles or 0) == 0 and (atomAvail == nil or atomAvail.ok) then
					local launched = Adapter:LaunchNuke("atom", target.tile)
					if launched then
						lastNukeTick = now
						recentlyNukedTiles[target.tile] = now
						RuntimeStats.NukesLaunched = (RuntimeStats.NukesLaunched or 0) + 1
						RuntimeStats.LastAction = string.format("Atom Nuked %s [%s]", target.name, target.kindName or "Cluster")
						Hub:Notify("Nuke Fired", string.format("Atom bomb detonated on %s!", target.name), 4)
					end
				end
			end
		end
	end

	-- [C] PRIORITY 3: CONDITION-DRIVEN EXPANSION & WAR MACHINE (FAST EARLY-GAME PACING)
	local curTroops = me.troops or 0
	local maxTroops = (me.max_troops and me.max_troops > 0) and me.max_troops or 1
	local troopFillRatio = curTroops / maxTroops
	local userDelay = Hub.State.AttackDelay or 1.10
	local myTiles = me.tiles or 0

	-- DYNAMIC ATTACK PACING & ARMY ACCUMULATION DOCTRINE:
	-- Troop growth in Rules.luau scales with (curTroops ^ 0.73).
	-- Resting when army is below 40% capacity allows troops to compound exponentially without attrition!
	local isArmyRecovering = (myTiles >= 8000) and (curTroops < maxTroops * 0.40) and (curTroops < 500000)
	local dynamicDelay = if isArmyRecovering then 2.50
		elseif currentWarTargetId then 2.00
		elseif curTroops >= 1000000 then userDelay
		elseif curTroops >= 200000 then userDelay
		elseif curTroops < 20000 and troopFillRatio < 0.20 then math.max(1.35, userDelay)
		else math.max(1.10, userDelay)

	if now - lastAttackTick >= dynamicDelay then
		lastAttackTick = now

		-- Responsive Dynamic Concurrency Limits:
		-- Allows rapid early-game expansion (3 waves when troops >= 20k) to gobble up land before rivals
		local totalActiveWaves, overseasWaves = getActiveOutboundWavesBreakdown()
		local maxWaves = if curTroops >= 1000000 then 5
			elseif curTroops >= 200000 then 4
			elseif curTroops >= 20000 then 3
			else 2

		if totalActiveWaves >= maxWaves then
			RuntimeStats.Status = string.format("Waves Advancing (%d/%d)", totalActiveWaves, maxWaves)
			return
		end

		local targetTile = nil
		local targetAction = "None"
		local targetRatio = Hub.State.AttackRatio or 0.20
		local targetOwner = 0

		-- DYNAMIC THREAT ASSESSMENT & ABSOLUTE RESERVE RULES:
		-- Find strongest direct land neighbor threatening our homeland
		local strongestNeighborTroops = 0
		local strongestNeighborName = "None"
		local stateOwners = state.owners
		local borders = Adapter:GetBorders()
		if stateOwners and borders then
			if borders.neighbour_ids then
				for _, id in ipairs(borders:neighbour_ids()) do
					local oData = stateOwners[id]
					if oData and oData.alive and not state:are_allies(me.id, id) then
						local oTroops = oData.troops or 0
						if oTroops > strongestNeighborTroops then
							strongestNeighborTroops = oTroops
							strongestNeighborName = oData.name or "Hostile Neighbor"
						end
					end
				end
			elseif borders.borders_owner then
				for id, oData in pairs(stateOwners) do
					if id ~= me.id and oData.alive and not state:are_allies(me.id, id) and borders:borders_owner(id) then
						local oTroops = oData.troops or 0
						if oTroops > strongestNeighborTroops then
							strongestNeighborTroops = oTroops
							strongestNeighborName = oData.name or "Hostile Neighbor"
						end
					end
				end
			end
		end

		-- DYNAMIC THREAT ASSESSMENT & RESILIENT HOMELAND RESERVE:
		-- Structural reserve: retain at least 30% of max troops or 5k troops for defense & compounding
		local structuralReserve = math.max(5000, maxTroops * 0.30)
		local isHomelandSecure = curTroops >= structuralReserve
		local isArmyFragile = (curTroops < 15000 and strongestNeighborTroops >= 30000)

		-- CONDITION 1: HOMELAND DEFENSE & EMERGENCY REPEL (Top Priority)
		-- Adapts native SimAI._defend formula:
		-- 1. If raid is tiny (< 2% our troops), passive border defense crushes it with 0 casualties!
		-- 2. FORTRESS DEFENSE: If enemy wave outnumbers us (curTroops < enemyAttackTroops * 1.10),
		--    NEVER attack into them in the field! Stay stationed on homeland territory where Defense Posts
		--    give 5x multiplier (DEFENSE_POST_MAG = 5), inflicting 500% casualties on attackers!
		-- 3. DECISIVE REPEL: When curTroops >= enemyAttackTroops * 1.10, launch a single counter-wave
		--    with 1.25x enemy troops, crushing the invasion while keeping 65%+ troops at home!
		local underAttack, attackerName, attackerId, attackAnchor, enemyAttackTroops, attackObj = isHomelandUnderAttack()
		local isMajorInvasion = underAttack and (enemyAttackTroops >= math.max(6000, curTroops * 0.05))
		local allowOtherOffenses = not isMajorInvasion

		if underAttack and curTroops >= 3000 then
			if enemyAttackTroops < curTroops * 0.05 then
				-- Minor raid (< 5% our army): Passive perimeter defense absorbs it with 0 casualties, allow other expansion!
				RuntimeStats.Status = string.format("Holding Perimeter vs %s (Raid: %d troops)", tostring(attackerName), enemyAttackTroops)
			elseif curTroops < enemyAttackTroops * 1.10 then
				RuntimeStats.Status = string.format("Fortress Defense vs %s (%d invaders, 5x Bonus)", tostring(attackerName), enemyAttackTroops)
			else
				local activeCounter, counterTroops = getActiveAttackAgainst(attackerId)
				if activeCounter and counterTroops >= enemyAttackTroops * 0.80 then
					RuntimeStats.Status = string.format("Repelling %s (%d troops engaging)", tostring(attackerName), counterTroops)
				else
					local repelTile = findBorderContactTile(attackerId) or attackAnchor
					if repelTile and repelTile > 0 then
						targetTile = repelTile
						targetOwner = attackerId
						local neededRatio = math.clamp((enemyAttackTroops * 1.25) / math.max(1, curTroops), 0.05, 0.35)
						targetRatio = neededRatio
						targetAction = string.format("Repelling %s (%d invaders with %d troops)", tostring(attackerName), enemyAttackTroops, math.floor(curTroops * targetRatio))
					end
				end
			end
		end

		-- CONDITION 2: ZERO-CASUALTY LAND EXPANSION & FALLOUT RECLAMATION
		-- Only permitted when NOT under attack, ensuring 100% focus on survival during invasions!
		if not targetTile and allowOtherOffenses and (Hub.State.AutoExpandNeutral or Hub.State.SmartAutoPlay) and curTroops >= 1500 then
			local nTile = findNeutralBorderTile()
			if nTile then
				targetTile = nTile
				targetOwner = 0
				targetRatio = 0.10
				targetAction = if state:has_fallout(nTile) then "Restoring Fallout Zone" else "Claiming Neutral Land"
			end
		end

		-- CONDITION 3: 1-HIT CAPITAL DECAPITATION (High Priority Strategic Execution)
		-- Snipes accessible hostile capitals when we have decisive army advantage
		if not targetTile and allowOtherOffenses and (Hub.State.AutoCapitalSnipe or Hub.State.SmartAutoPlay) and isHomelandSecure and not isArmyFragile then
			local capTile, capName, capOwner = findEnemyCapitalTarget()
			if capTile then
				local capOwnerData = state.owners and state.owners[capOwner]
				local capTroops = (capOwnerData and capOwnerData.troops) or 0
				local hasAdvantage = (curTroops >= capTroops * 1.25) or (capTroops <= 15000) or (curTroops >= 250000)
				if hasAdvantage then
					targetTile = capTile
					targetOwner = capOwner or state:tile_owner(capTile)
					local neededRatio = math.clamp((capTroops * 1.25) / math.max(1, curTroops), 0.10, 0.25)
					targetRatio = math.clamp(Hub.State.AttackRatio or 0.20, 0.10, neededRatio)
					targetAction = "Decapitating Capital: " .. tostring(capName)
				end
			end
		end

		-- CONDITION 4: FRONTLINE LAND COMBAT (SINGLE-TARGET WAR LOCK & DEFEAT IN DETAIL)
		local hasLandTarget = false
		if not targetTile and allowOtherOffenses and (Hub.State.AutoInvadeEnemies or Hub.State.SmartAutoPlay) and not isArmyRecovering then
			-- Single-Target War Lock validation:
			if currentWarTargetId then
				local tData = stateOwners and stateOwners[currentWarTargetId]
				local stillAlive = tData and tData.alive and (tData.tiles or 0) > 0
				local stillBorders = borders and borders.borders_owner and borders:borders_owner(currentWarTargetId)
				if not stillAlive or not stillBorders then
					currentWarTargetId = nil
					currentWarTargetName = "None"
				end
			end

			local eLandTile, eName, eOwner, eTroops, isBeatable, dist, isEasy = nil, nil, nil, 0, false, 0, false

			-- If already waging war against a target, finish them off completely first!
			if currentWarTargetId then
				eLandTile, eName, eOwner, eTroops, isBeatable, dist, isEasy = findEnemyLandBorderTile(Hub.State.StrategyMode, currentWarTargetId)
			end
			-- If no active target or target no longer has a border, pick new weakest beatable target!
			if not eLandTile then
				eLandTile, eName, eOwner, eTroops, isBeatable, dist, isEasy = findEnemyLandBorderTile(Hub.State.StrategyMode)
				if eLandTile and eOwner and eOwner ~= 0 then
					currentWarTargetId = eOwner
					currentWarTargetName = eName or "Hostile Nation"
				end
			end

			if eLandTile then
				hasLandTarget = true
				local enemyTroops = eTroops or 0

				-- SAFE ATTACK VALIDATION (Defeat in Detail Doctrine):
				-- 1. Easy targets / Tribes / Capitulation (8:1): ALWAYS safe to crush!
				-- 2. Peer targets: Attack if we outnumber them (curTroops >= enemyTroops * 1.15) and homeland has base reserve!
				local canSafelyAttack = isEasy
					or (isBeatable and isHomelandSecure and curTroops >= enemyTroops * 1.15)
					or (curTroops >= 300000 and curTroops >= enemyTroops * 1.10)

				if canSafelyAttack then
					-- Redundant Assault Wave Check (Matches SimAI line 108):
					-- If an active assault wave against this target already has >= 80% of enemy troops, DO NOT SPAM MORE WAVES!
					local activeWarAtk, activeWarTroops = getActiveAttackAgainst(eOwner)
					if activeWarAtk and activeWarTroops >= enemyTroops * 0.80 then
						RuntimeStats.Status = string.format("Assaulting %s (%d troops advancing)", tostring(eName), activeWarTroops)
					else
						targetTile = eLandTile
						targetOwner = eOwner
						-- Safe Attack Ratio: Spend at most 20% of army in one wave, retaining 80%+ at home for defense & compounding!
						local desiredRatio = if isEasy then 0.15 else math.clamp((enemyTroops * 1.20) / math.max(1, curTroops), 0.08, 0.20)
						targetRatio = math.clamp(Hub.State.AttackRatio or 0.20, 0.05, desiredRatio)
						targetAction = string.format("Conquering %s (Army: %d vs %d, Ratio: %.0f%%)", tostring(eName), curTroops, enemyTroops, targetRatio * 100)
					end
				else
					if isArmyFragile or curTroops < structuralReserve then
						RuntimeStats.Status = string.format("Holding Border vs %s (Army: %d, Reserve: %d)", tostring(eName), curTroops, math.floor(structuralReserve))
					else
						RuntimeStats.Status = string.format("Recruiting Army vs %s (%d vs %d)", tostring(eName), curTroops, enemyTroops)
					end
				end
			end
		elseif not targetTile and isArmyRecovering then
			RuntimeStats.Status = string.format("Compounding Army (%d/%d - %d%%)", curTroops, math.floor(maxTroops * 0.40), math.floor(troopFillRatio * 100))
		end

		-- CONDITION 5: AMPHIBIOUS ISLAND-HOPPING (Strict Nearest Island)
		-- Initiate overseas hopping if our land continent has no hostile neighbors OR if all land neighbors
		-- are currently too strong to attack safely (allowing us to bypass them and expand via islands)!
		if not targetTile and allowOtherOffenses and (Hub.State.AutoInvadeEnemies or Hub.State.SmartAutoPlay) then
			local anyLandEnemy, _, _, _, isLandBeatable = findEnemyLandBorderTile("All")
			local isContinentSecured = (anyLandEnemy == nil) or (not isLandBeatable)

			local maxOverseas = if curTroops >= 1000000 then 3 elseif curTroops >= 300000 then 2 else 1
			if isContinentSecured and overseasWaves < maxOverseas and not isArmyFragile then
				local oTile, oName, oOwner, oTroops = findOverseasLandingBeachhead()
				if oTile then
					local desiredTroops = math.clamp(curTroops * 0.20, 8000, 45000)
					local boatRatio = math.clamp(desiredTroops / math.max(1, curTroops), 0.0001, 0.25)
					local hasNavalAdvantage = (not oTroops) or (oTroops == 0)
						or (curTroops >= 250000)
						or (curTroops >= (oTroops or 0) * 0.85)
						or (desiredTroops >= (oTroops or 0) * 0.5)
					if hasNavalAdvantage then
						targetTile = oTile
						targetOwner = oOwner
						targetRatio = boatRatio
						targetAction = string.format("Amphibious Fleet Landing: %s (%d troops)", tostring(oName), math.floor(curTroops * boatRatio))
					else
						RuntimeStats.Status = string.format("Gathering Fleet for %s", tostring(oName))
					end
				end
			elseif not isContinentSecured then
				if anyLandEnemy then
					RuntimeStats.Status = "Consolidating Border vs Land Neighbors"
				end
			else
				RuntimeStats.Status = "Naval Fleet in Transit..."
			end
		end

		-- DISPATCH ATTACK INTENT:
		if targetTile then
			local ok = Adapter:ResolveAttack(targetTile, targetRatio)
			if ok then
				RuntimeStats.AttacksSent = (RuntimeStats.AttacksSent or 0) + 1
				RuntimeStats.Status = "Conquering Territory"
				RuntimeStats.LastAction = targetAction
			end
		else
			if RuntimeStats.Status == "Idle" or RuntimeStats.Status == "Conquering Territory" or RuntimeStats.Status == "Expanding Territory" then
				RuntimeStats.Status = "Dominating Global Front"
			end
		end
	end
end

local function checkLoopLifecycle()
	local anyActive = Hub.State.SmartAutoPlay
		or Hub.State.AutoReinforce
		or Hub.State.AutoExpandNeutral
		or Hub.State.AutoInvadeEnemies
		or Hub.State.AutoCapitalSnipe
		or Hub.State.AutoNuke
		or Hub.State.AutoBuildSilos
		or Hub.State.AutoDefensePosts
		or Hub.State.AutoSAMShield
		or Hub.State.AutoBuildCities
		or Hub.State.AutoBuildPorts
		or Hub.State.AutoBuildFactories
		or Hub.State.AutoJoinMatch
		or Hub.State.AutoPlayAgain
		or Hub.State.AutoSpawnCapital
		or Hub.State.AutoTakeover

	if anyActive then
		Hub.State.MainCycle = true
		local lastCycleErr = 0
		Hub:Loop("MainCycle", function()
			local ok, err = xpcall(bodySmartAutoPlay, function(e)
				return tostring(e) .. "\n" .. debug.traceback("", 2)
			end)
			if not ok then
				local now = os.clock()
				if now - lastCycleErr > 3.0 then
					lastCycleErr = now
					warn("[MainCycle Traceback] " .. tostring(err))
				end
			end
		end, 0.30)
	else
		Hub.State.MainCycle = false
		Hub:StopLoop("MainCycle")
		RuntimeStats.Status = "Idle"
	end
end
Hub.CheckLoopLifecycle = checkLoopLifecycle

Hub._onStopAll = function()
	Hub.State.MainCycle = false
	Hub:StopLoop("MainCycle")
	currentWarTargetId = nil
	currentWarTargetName = "None"
	RuntimeStats.Status = "Idle"
end

local function updateLiveTelemetry()
	if not Adapter:Resolve() then return end
	local session = Adapter.Session
	local state = Adapter.State
	if not session or not state then return end

	local isLobby = (session.mode == 0) or (not state) or (not state.local_owner) or (state.local_owner == 0)
	if isLobby then
		RuntimeStats.Phase = "Lobby / Title"
		if not Hub.State.AutoJoinMatch then
			RuntimeStats.Status = "In Lobby"
		end
	elseif state.phase == 2 then
		local winName = if state.winner and state.winner > 0 then state:owner_name(state.winner) else "None"
		RuntimeStats.Phase = "Match Ended"
		RuntimeStats.Status = "Winner: " .. tostring(winName)
	else
		local me = Adapter:GetMe()
		if not me or not me.spawned then
			RuntimeStats.Phase = "Capital Selection"
		elseif not me.alive then
			RuntimeStats.Phase = "Eliminated"
		else
			RuntimeStats.Phase = "Active Combat"
			RuntimeStats.Nation = tostring(me.name or "Roi")
			RuntimeStats.Tiles = me.tiles or 0
			RuntimeStats.Troops = me.troops or 0
			RuntimeStats.Cap = me.max_troops or 0
			RuntimeStats.Gold = me.gold or 0
			RuntimeStats.Income = me.income or 0

			if not Hub.State.SmartAutoPlay and (RuntimeStats.Status == "Finding Strategic Coast..." or RuntimeStats.Status == "Capital Placed - Initializing") then
				RuntimeStats.Status = "Idle (Autoplay OFF)"
			end

			local canReinforce = type(session.has_unlock) == "function" and session:has_unlock("reinforce")
			if canReinforce then
				local readyTick = (state.reinforce_ready and state.reinforce_ready[me.id]) or 0
				local ticksLeft = readyTick - (state.tick or 0)
				if ticksLeft <= 0 then
					RuntimeStats.ReinforceTime = "Ready"
				else
					RuntimeStats.ReinforceTime = string.format("%ds", math.ceil(ticksLeft / 10))
				end
			else
				RuntimeStats.ReinforceTime = "Locked"
			end
		end
	end
end

-- ==============================================================================
-- [5] PRESENTATION LAYER (GUI VIA SHENKY HUB)
-- ==============================================================================
local Window = Hub:CreateWindow({
	SubTitle = "RoFront [World PvP]",
	Folder = "RoFrontWorldPvP",
	ToggleKey = Enum.KeyCode.RightControl,
})

-- ------------------------------------------------------------------------------
-- TAB 1: AUTOMATION (Unified Master Controller & Strategy Preset)
-- ------------------------------------------------------------------------------
local AutoTab = Window:Tab({ Title = "Auto Play", Icon = "zap" })
local MasterSec = AutoTab:Section({ Title = "Master Autopilot" })

MasterSec:Toggle({
	Title = "Smart Auto Play",
	Desc = "Fully closed-loop RTS automation: expand, reinforce, build & conquer",
	Default = false,
	Callback = function(state)
		Hub.State.SmartAutoPlay = state
		checkLoopLifecycle()
		if state then
			Hub:Notify("Smart Auto Play", "Autopilot engaged: 99% winrate pipeline active", "zap")
		else
			RuntimeStats.Status = "Idle"
		end
	end,
})

MasterSec:Dropdown({
	Title = "Strategy Mode",
	Desc = "Primary targeting doctrine for frontline army expansion",
	Options = { "Neutral First", "Tribes Only", "Aggressive" },
	Default = "Neutral First",
	Callback = function(opt)
		Hub.State.StrategyMode = opt
	end,
})

local masterTelemetryLabel = MasterSec:SubLabel({
	Text = Hub:FormatTelemetry({
		{ "Status", "Idle", Hub.Colors.Blue },
		{ "Phase", "Lobby", Hub.Colors.Yellow },
		{ "Reinforce", "Ready", Hub.Colors.Green },
		{ "Action", "None", Hub.Colors.Purple },
	}),
})

-- ------------------------------------------------------------------------------
-- TAB 2: CONQUEST (Expansion, Micro-Pulse & Capital Decapitation)
-- ------------------------------------------------------------------------------
local WarTab = Window:Tab({ Title = "Conquest", Icon = "crosshair" })
local AttackSec = WarTab:Section({ Title = "Offensive Operations" })

AttackSec:Toggle({
	Title = "Auto Expand Neutral",
	Desc = "Sweeps all adjacent unclaimed land with minimal troop casualties",
	Default = false,
	Callback = function(state)
		Hub.State.AutoExpandNeutral = state
		checkLoopLifecycle()
	end,
})

AttackSec:Toggle({
	Title = "Auto Invade Enemies",
	Desc = "Engages hostile nation and tribe borders using optimal troop ratios",
	Default = false,
	Callback = function(state)
		Hub.State.AutoInvadeEnemies = state
		checkLoopLifecycle()
	end,
})

AttackSec:Toggle({
	Title = "Auto Capital Snipe",
	Desc = "Directs invasion forces straight to enemy capitals for 1-hit nation collapse",
	Default = false,
	Callback = function(state)
		Hub.State.AutoCapitalSnipe = state
		checkLoopLifecycle()
	end,
})

AttackSec:Slider({
	Title = "Troop Ratio %",
	Desc = "Surplus troop fraction sent per attack pulse (optimal: 15% - 25%)",
	Value = { Min = 5, Max = 50, Default = 20 },
	Step = 5,
	Callback = function(val)
		Hub.State.AttackRatio = val / 100
	end,
})

AttackSec:Slider({
	Title = "Reserve Cap %",
	Desc = "Homeland defense reserve floor; attacks halt below this % of max cap",
	Value = { Min = 10, Max = 60, Default = 25 },
	Step = 5,
	Callback = function(val)
		Hub.State.MinReserveRatio = val / 100
	end,
})

AttackSec:Slider({
	Title = "Max Waves",
	Desc = "Maximum concurrent army waves allowed in transit simultaneously",
	Value = { Min = 1, Max = 8, Default = 4 },
	Step = 1,
	Callback = function(val)
		Hub.State.MaxActiveWaves = val
	end,
})

AttackSec:Slider({
	Title = "Attack Delay",
	Desc = "Pacing interval between outbound attack pulses in seconds",
	Value = { Min = 0.20, Max = 3.0, Default = 1.20 },
	Step = 0.10,
	Callback = function(val)
		Hub.State.AttackDelay = val
	end,
})

local attackTelemetryLabel = AttackSec:SubLabel({
	Text = Hub:FormatTelemetry({
		{ "Attacks Sent", "0 Waves", Hub.Colors.Sky },
		{ "Territory", "0 Tiles", Hub.Colors.Green },
		{ "Troops", "0 / 0", Hub.Colors.Amber },
	}),
})

-- ------------------------------------------------------------------------------
-- TAB 3: MILITARY (Survival, Defense Grid, Anti-Nuke SAM & Takeover)
-- ------------------------------------------------------------------------------
local DefenseTab = Window:Tab({ Title = "Military", Icon = "shield" })
local DefSec = DefenseTab:Section({ Title = "Defense & Survival" })

DefSec:Toggle({
	Title = "Auto Reinforce",
	Desc = "Frame-perfect instant claim of +20% max troops every 120s cycle",
	Default = false,
	Callback = function(state)
		Hub.State.AutoReinforce = state
		checkLoopLifecycle()
	end,
})

DefSec:Toggle({
	Title = "Auto Defense Posts",
	Desc = "Constructs Defense Posts on border tiles (inflicts 5x casualties on attackers)",
	Default = false,
	Callback = function(state)
		Hub.State.AutoDefensePosts = state
		checkLoopLifecycle()
	end,
})

DefSec:Slider({
	Title = "Max Posts",
	Desc = "Maximum defense posts allowed across borders to prevent gold waste",
	Value = { Min = 1, Max = 4, Default = 1 },
	Step = 1,
	Callback = function(val)
		Hub.State.MaxDefensePosts = val
	end,
})

DefSec:Toggle({
	Title = "Auto SAM Shield",
	Desc = "Constructs distributed SAM Launchers protecting economic clusters",
	Default = false,
	Callback = function(state)
		Hub.State.AutoSAMShield = state
		checkLoopLifecycle()
	end,
})

DefSec:Slider({
	Title = "Max SAM Bat.",
	Desc = "Maximum distributed SAM batteries placed across empire clusters",
	Value = { Min = 2, Max = 8, Default = 6 },
	Step = 1,
	Callback = function(val)
		Hub.State.MaxSAMBatteries = val
	end,
})

DefSec:Slider({
	Title = "Max SAM Lvl",
	Desc = "Hard cap on SAM upgrade level to prevent single-battery level 90 gold waste",
	Value = { Min = 1, Max = 4, Default = 2 },
	Step = 1,
	Callback = function(val)
		Hub.State.MaxSAMLevel = val
	end,
})

DefSec:Toggle({
	Title = "Auto Superweapons",
	Desc = "Preemptively fires Hydrogen Bombs (5M) or MIRVs (55M) at rival superpowers",
	Default = false,
	Callback = function(state)
		Hub.State.AutoNuke = state
		checkLoopLifecycle()
	end,
})

DefSec:Toggle({
	Title = "Auto Build Silos",
	Desc = "Constructs Missile Silos when treasury permits to enable nuclear warfare",
	Default = false,
	Callback = function(state)
		Hub.State.AutoBuildSilos = state
		checkLoopLifecycle()
	end,
})

DefSec:Toggle({
	Title = "Auto Takeover AI",
	Desc = "If eliminated, instantly seizes control of the strongest surviving bot nation",
	Default = false,
	Callback = function(state)
		Hub.State.AutoTakeover = state
		checkLoopLifecycle()
	end,
})

local defTelemetryLabel = DefSec:SubLabel({
	Text = Hub:FormatTelemetry({
		{ "Reinforce Timer", "Ready", Hub.Colors.Green },
		{ "SAM Shield", "0 Active", Hub.Colors.Purple },
		{ "Nukes Fired", "0 Launches", Hub.Colors.Red },
	}),
})

-- ------------------------------------------------------------------------------
-- TAB 4: ECONOMY (City Stacking, Ports & Logistics)
-- ------------------------------------------------------------------------------
local EcoTab = Window:Tab({ Title = "Economy", Icon = "coins" })
local EcoSec = EcoTab:Section({ Title = "Infrastructure Construction" })

EcoSec:Toggle({
	Title = "Auto Build Cities",
	Desc = "Spams Cities every time gold is ready (+250,000 max troops per city)",
	Default = false,
	Callback = function(state)
		Hub.State.AutoBuildCities = state
		checkLoopLifecycle()
	end,
})

EcoSec:Toggle({
	Title = "Auto Build Ports",
	Desc = "Constructs coastal ports for trade ship income and warship construction",
	Default = false,
	Callback = function(state)
		Hub.State.AutoBuildPorts = state
		checkLoopLifecycle()
	end,
})

EcoSec:Toggle({
	Title = "Auto Build Factories",
	Desc = "Constructs land factories for trade truck supply routes and gold income",
	Default = false,
	Callback = function(state)
		Hub.State.AutoBuildFactories = state
		checkLoopLifecycle()
	end,
})

EcoSec:Input({
	Title = "Reserve Gold",
	Desc = "Safe treasury floor; bot never spends gold if balance is below this amount",
	Value = "500000",
	Callback = function(text)
		local num = tonumber(text)
		if num and num >= 0 then
			Hub.State.MinGoldReserve = num
		end
	end,
})

EcoSec:Slider({
	Title = "Build Delay",
	Desc = "Pacing interval between structure construction attempts in seconds",
	Value = { Min = 0.5, Max = 10.0, Default = 1.5 },
	Step = 0.5,
	Callback = function(val)
		Hub.State.BuildDelay = val
	end,
})

local ecoTelemetryLabel = EcoSec:SubLabel({
	Text = Hub:FormatTelemetry({
		{ "Gold Treasury", "0 G", Hub.Colors.Yellow },
		{ "Income", "0 G/sec", Hub.Colors.Green },
		{ "Cities Built", "0", Hub.Colors.Sky },
	}),
})

-- ------------------------------------------------------------------------------
-- TAB 5: LOBBY & META (Auto Join, Safe Spawn & Cosmetics)
-- ------------------------------------------------------------------------------
local MetaTab = Window:Tab({ Title = "Lobby & Meta", Icon = "refresh-cw" })
local MetaSec = MetaTab:Section({ Title = "Match Automation" })

MetaSec:Toggle({
	Title = "Auto Play Again",
	Desc = "Automatically clicks Play Again / requeues when a match ends or upon elimination",
	Default = false,
	Callback = function(state)
		Hub.State.AutoPlayAgain = state
		checkLoopLifecycle()
	end,
})

MetaSec:Toggle({
	Title = "Auto Join Match",
	Desc = "Automatically queues and enters multiplayer matches from the lobby",
	Default = false,
	Callback = function(state)
		Hub.State.AutoJoinMatch = state
		checkLoopLifecycle()
	end,
})

MetaSec:Toggle({
	Title = "Auto Spawn Capital",
	Desc = "Picks high-yield coastal corner spawn points during capital selection",
	Default = false,
	Callback = function(state)
		Hub.State.AutoSpawnCapital = state
		checkLoopLifecycle()
	end,
})

MetaSec:Button({
	Title = "Play Again Now",
	Desc = "Instantly clicks Play Again or starts a fresh match",
	Callback = function()
		triggerPlayAgain()
	end,
})

MetaSec:Button({
	Title = "Join Match Now",
	Desc = "Manually triggers multiplayer lobby connection",
	Callback = function()
		if Adapter:Resolve() and Adapter.Session then
			Adapter.Session:join_multiplayer()
			Hub:Notify("Multiplayer", "Connecting to multiplayer lobby...", "refresh-cw")
		end
	end,
})

local metaTelemetryLabel = MetaSec:SubLabel({
	Text = Hub:FormatTelemetry({
		{ "Mode", "Multiplayer", Hub.Colors.Blue },
		{ "Match State", "Ready", Hub.Colors.Green },
		{ "Play Again", "Disabled", Hub.Colors.Yellow },
	}),
})

-- ==============================================================================
-- [6] TELEMETRY REFRESH LOOP
-- ==============================================================================
Hub:Loop("TelemetryUpdater", function()
	pcall(function()
		updateLiveTelemetry()

		masterTelemetryLabel:SetText(Hub:FormatTelemetry({
			{ "Status", RuntimeStats.Status, Hub.Colors.Blue },
			{ "Phase", RuntimeStats.Phase, Hub.Colors.Yellow },
			{ "Nation", RuntimeStats.Nation, Hub.Colors.Sky },
			{ "Reinforce", RuntimeStats.ReinforceTime, RuntimeStats.ReinforceTime == "Ready" and Hub.Colors.Green or Hub.Colors.Amber },
			{ "Last Action", RuntimeStats.LastAction, Hub.Colors.Purple },
		}))

		attackTelemetryLabel:SetText(Hub:FormatTelemetry({
			{ "Attacks Sent", string.format("%d Waves", RuntimeStats.AttacksSent), Hub.Colors.Sky },
			{ "Territory", string.format("%d Tiles", RuntimeStats.Tiles), Hub.Colors.Green },
			{ "Army Count", string.format("%d / %d", RuntimeStats.Troops, RuntimeStats.Cap), Hub.Colors.Amber },
		}))

		defTelemetryLabel:SetText(Hub:FormatTelemetry({
			{ "Reinforce Timer", RuntimeStats.ReinforceTime, Hub.Colors.Green },
			{ "SAM Batteries", string.format("%d / %d Bat.", RuntimeStats.SAMBuilt, Hub.State.MaxSAMBatteries or 6), Hub.Colors.Purple },
			{ "Nukes Fired", string.format("%d Launches", RuntimeStats.NukesLaunched or 0), Hub.Colors.Red },
		}))

		ecoTelemetryLabel:SetText(Hub:FormatTelemetry({
			{ "Gold Treasury", string.format("%d G", RuntimeStats.Gold), Hub.Colors.Yellow },
			{ "Passive Income", string.format("+%d G/s", RuntimeStats.Income), Hub.Colors.Green },
			{ "Cities Added", string.format("%d Cities", RuntimeStats.CitiesBuilt), Hub.Colors.Sky },
		}))

		metaTelemetryLabel:SetText(Hub:FormatTelemetry({
			{ "Match State", RuntimeStats.Phase, Hub.Colors.Green },
			{ "Play Again", Hub.State.AutoPlayAgain and "Active" or "Disabled", Hub.State.AutoPlayAgain and Hub.Colors.Green or Hub.Colors.Yellow },
			{ "Auto Join", Hub.State.AutoJoinMatch and "Active" or "Disabled", Hub.State.AutoJoinMatch and Hub.Colors.Green or Hub.Colors.Yellow },
		}))
	end)
end, 0.5)

-- Notification on initial load
Hub:Notify("RoFront [World PvP]", "Smart Auto Play script loaded — all features OFF by default.", "zap")
