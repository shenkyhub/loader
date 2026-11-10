-- ============================================================================
-- [Shenky Hub] Compiled Hub Core Engine
-- Bundled from src-hub/ via Shenky Hub Bundler
-- Generated: 2026-11-10T07:52:59.749Z
-- ============================================================================

local __modules = {}
local __cache = {}

local function __require(modName)
	if __cache[modName] ~= nil then
		return __cache[modName]
	end
	local modFn = __modules[modName]
	if not modFn then
		error("[Shenky Bundler] Module not found: " .. tostring(modName), 2)
	end
	local result = modFn()
	__cache[modName] = result
	return result
end

-- Module: core/base
__modules["core/base"] = function()
-- core/base.luau
-- Shenky Hub Base Runtime: State, Loops, Telemetry & Lifecycle

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

local Hub = {}

-- Bersihkan hub lama sebelum membuat instance Shenky UI baru.
local PreviousHub = getgenv().__GLOBAL_HUB
local PreviousGen = PreviousHub and PreviousHub._Gen or 0
if PreviousHub then
	pcall(function()
		PreviousHub:Destroy()
	end)
end
pcall(function()
	if PreviousHub and PreviousHub.Disable3dRenderingEnabled then
		pcall(function() game:GetService("RunService"):Set3dRenderingEnabled(true) end)
	end
	local function wipeGui(container)
		if not container then return end
		for _, c in ipairs(container:GetChildren()) do
			if c.Name == "ShenkyHubMobileToggle" or c.Name == "ShenkyHub" or c.Name == "ShenkyGpuSaver" or c.Name == "ShenkyESP" then
				pcall(c.Destroy, c)
			end
		end
	end
	local okHui, h = pcall(gethui)
	if okHui and h and typeof(h) == "Instance" then
		wipeGui(h)
	else
		local okCg, cg = pcall(game.GetService, game, "CoreGui")
		if okCg and cg then
			local okAccess = pcall(function() return cg:GetChildren() end)
			if okAccess then wipeGui(cg) end
		end
	end
	local lp = Players.LocalPlayer
	if lp then
		local pg = lp:FindFirstChild("PlayerGui")
		if pg then wipeGui(pg) end
	end

	-- Bersihkan efek blur atau sisa DepthOfField/glass parts dari session sebelumnya
	local okLight, Lighting = pcall(game.GetService, game, "Lighting")
	if okLight and Lighting then
		for _, child in ipairs(Lighting:GetChildren()) do
			if child:IsA("DepthOfFieldEffect") and (child:HasTag(".") or child.NearIntensity == 1) then
				pcall(function() child.Enabled = false; child:Destroy() end)
			end
		end
	end
	local cam = workspace.CurrentCamera
	if cam then
		for _, child in ipairs(cam:GetChildren()) do
			if child:IsA("DepthOfFieldEffect") or (child:IsA("BasePart") and child.Material == Enum.Material.Glass) then
				pcall(function() child:Destroy() end)
			end
		end
	end
end)


-- ==== Hub:Notify(title, content, icon) ====
function Hub:Notify(title, content, _icon, toastType)
	local Toast = self.Components and self.Components.Toast or (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Toast)
	if Toast and Toast.Show then
		return Toast:Show(title, content, toastType or _icon, nil)
	end

	local MacWindow = self._MacWindow
	if not MacWindow then return end

	local sTitle = tostring(title or "Hub")
	local sContent = tostring(content or "")

	-- Anti-spam debounce: cegah penumpukan notifikasi identik dalam interval < 1.0s
	self._notifCache = self._notifCache or {}
	local notifKey = sTitle .. "::" .. sContent
	local now = os.clock()
	if self._notifCache[notifKey] and (now - self._notifCache[notifKey]) < 1.0 then
		return
	end
	self._notifCache[notifKey] = now

	-- Bounded notification cache: bersihkan entri kadaluarsa jika cache melebihi batas
	self._notifCount = (self._notifCount or 0) + 1
	if self._notifCount > 50 then
		self._notifCount = 0
		for k, t in pairs(self._notifCache) do
			if (now - t) >= 1.5 then
				self._notifCache[k] = nil
			end
		end
	end

	pcall(function()
		MacWindow:Notify({
			Title = sTitle,
			Description = sContent,
			Lifetime = 4,
		})
	end)
end

-- ==== State + loop management ====
Hub.State = {}
Hub._loops = {}
Hub._toggles = {}
Hub._usedFlags = {}
Hub._loopTokens = {}
Hub._registeredFeatures = {}

function Hub:RegisterFeature(info)
	if type(info) ~= "table" or not info.Name then return end
	table.insert(self._registeredFeatures, info)
	if self._onFeatureRegistered then
		pcall(self._onFeatureRegistered, info)
	end
end

function Hub:Loop(name, arg2, arg3)
	if not self._loopsSet then
		self._loopsSet = {}
		for _, v in ipairs(self._loops) do
			self._loopsSet[v] = true
		end
	end
	if not self._loopsSet[name] then
		self._loopsSet[name] = true
		table.insert(self._loops, name)
	end
	local generation = self._Gen
	local token = (self._loopTokens[name] or 0) + 1
	self._loopTokens[name] = token

	local body, waitTime
	if type(arg2) == "function" then
		body = arg2
		waitTime = tonumber(arg3) or 0.1
	elseif type(arg3) == "function" then
		body = arg3
		waitTime = tonumber(arg2) or 0.1
	else
		warn("[Hub:Loop] No valid callback function provided for loop: " .. tostring(name))
		return
	end

	self.State[name] = true

	local lastWarnTime = 0
	task.spawn(function()
		while self._Gen == generation and self._loopTokens[name] == token and self.State[name] do
			local errTrace = nil
			local ok, res = xpcall(body, function(e)
				errTrace = tostring(e) .. '\n' .. debug.traceback('', 2)
				return e
			end)
			if not ok then
				local now = os.clock()
				if (now - lastWarnTime) > 3.0 then
					lastWarnTime = now
					warn("[Hub:" .. tostring(name) .. "] " .. tostring(errTrace or res))
				end
			end
			task.wait(waitTime)
		end
	end)
end

Hub.Colors = {
	Label = "#94a3b8",
	Green = "#4ade80",
	Red = "#ef4444",
	Rose = "#f87171",
	Yellow = "#fbbf24",
	Amber = "#f59e0b",
	Blue = "#38bdf8",
	Sky = "#60a5fa",
	Purple = "#a855f7",
	Violet = "#a78bfa",
	Pink = "#ec4899",
	White = "#f8fafc",
}

function Hub:FormatRow(label, value, color)
	local valStr = tostring(value or "")
	if color and type(color) == "string" and color ~= "" then
		valStr = string.format('<font color="%s"><b>%s</b></font>', color, valStr)
	else
		valStr = string.format('<b>%s</b>', valStr)
	end
	return string.format('<font color="%s">%s:</font> %s', self.Colors.Label, tostring(label or ""), valStr)
end

function Hub:FormatTelemetry(rows)
	local lines = {}
	if type(rows) == "table" then
		for _, row in ipairs(rows) do
			if type(row) == "string" then
				table.insert(lines, row)
			elseif type(row) == "table" then
				local label = row[1] or row.Label or row.label or ""
				local val = row[2] or row.Value or row.value or ""
				local col = row[3] or row.Color or row.color
				table.insert(lines, self:FormatRow(label, val, col))
			end
		end
	end
	return table.concat(lines, "\n")
end

function Hub:StopLoop(name)
	if not name then return end
	self.State[name] = false
	self._loopTokens = self._loopTokens or {}
	self._loopTokens[name] = (self._loopTokens[name] or 0) + 1
end

Hub.Stop = Hub.StopLoop

-- ==== Hub:SendWebhook(cfg) ====

function Hub:CloseDropdowns()
	-- Shenky UI memakai inline accordion dropdown di dalam section sehingga tidak
	-- meninggalkan floating popup saat di-scroll atau di-minimize.
end


function Hub:StopAll()
	for k in pairs(self.State) do
		self.State[k] = false
	end
	if type(self._loopTokens) == "table" then
		for name, token in pairs(self._loopTokens) do
			self._loopTokens[name] = token + 1
		end
	end
	if type(self._toggles) == "table" then
		for _, toggleWrapper in ipairs(self._toggles) do
			pcall(function()
				toggleWrapper:Set(false)
			end)
		end
	end
	if self.PlayerRuntime then
		pcall(function()
			self.PlayerRuntime:ResetMovement()
		end)
	end
	if self.RenderRuntime and self.RenderRuntime.Disable3dRenderingEnabled then
		pcall(function() self.RenderRuntime:SetDisable3dRendering(false) end)
	end
	if type(self._onStopAll) == "function" then
		pcall(self._onStopAll)
	end
end

function Hub:Destroy()
	if self._destroyed then return end
	self._destroyed = true

	-- 1. Jalankan callback OnClose dari game script terlebih dahulu sebelum subsistem dihentikan
	if self.Window and type(self.Window._onCloseCallbacks) == "table" then
		for i = #self.Window._onCloseCallbacks, 1, -1 do
			local cb = self.Window._onCloseCallbacks[i]
			if type(cb) == "function" then
				pcall(cb)
			end
		end
		table.clear(self.Window._onCloseCallbacks)
	end

	-- 2. Hentikan semua otomasi aktif
	self:StopAll()
	self._Gen = (self._Gen or 0) + 1

	-- 3. Hancurkan runtime Player, Render, dan Server
	if self.PlayerRuntime then
		pcall(function() self.PlayerRuntime:Destroy() end)
		self.PlayerRuntime = nil
	end
	if self.RenderRuntime then
		pcall(function() self.RenderRuntime:Destroy() end)
		self.RenderRuntime = nil
	end
	if self.ServerRuntime then
		pcall(function() self.ServerRuntime:Destroy() end)
		self.ServerRuntime = nil
	end

	-- 4. Bersihkan ESP & anti-AFK
	self:ClearAllESP()
	if self._antiAfkConn then
		pcall(function() self._antiAfkConn:Disconnect() end)
		self._antiAfkConn = nil
	end

	-- 5. Bersihkan Mobile Toggle GUI
	if self._mobileToggleLoopStop then
		pcall(self._mobileToggleLoopStop)
		self._mobileToggleLoopStop = nil
	end
	if self._mobileToggleGui then
		pcall(function()
			self._mobileToggleGui:Destroy()
		end)
		self._mobileToggleGui = nil
	end
	if self._mobileToggleConns then
		for _, conn in ipairs(self._mobileToggleConns) do
			pcall(function()
				conn:Disconnect()
			end)
		end
		self._mobileToggleConns = nil
	end

	-- 6. Hancurkan Window dan Shenky UI
	if self.Window then
		pcall(function()
			self.Window:Destroy()
		end)
		self.Window = nil
	end
	local win = self._Window or self._MacWindow
	if win and type(win.Unload) == "function" then
		pcall(function()
			win:Unload()
		end)
	end
	self._Window = nil
	self._MacWindow = nil
	self.PlayerTab = nil
	self.ServerTab = nil
	self.ConfigTab = nil
	if type(self._registeredFeatures) == "table" then
		table.clear(self._registeredFeatures)
	end

	-- 7. Sapu bersih semua sisa GUI Shenky di CoreGui, gethui(), dan PlayerGui
	pcall(function()
		local function wipeGui(container)
			if not container then return end
			for _, c in ipairs(container:GetChildren()) do
				if c.Name == "ShenkyHubMobileToggle" or c.Name == "ShenkyHub" or c.Name == "ShenkyGpuSaver" or c.Name == "ShenkyESP" or c.Name == "macLib" then
					pcall(c.Destroy, c)
				end
			end
		end
		local okHui, h = pcall(gethui)
		if okHui and h and typeof(h) == "Instance" then
			wipeGui(h)
		else
			local okCg, cg = pcall(game.GetService, game, "CoreGui")
			if okCg and cg then
				local okAccess = pcall(function() return cg:GetChildren() end)
				if okAccess then wipeGui(cg) end
			end
		end
		local lp = Players.LocalPlayer
		if lp then
			local pg = lp:FindFirstChild("PlayerGui")
			if pg then wipeGui(pg) end
		end
	end)

	-- 8. Pastikan 3D rendering aktif kembali & purge sisa blur/DepthOfField/glass di Lighting dan Camera
	pcall(function()
		pcall(function() game:GetService("RunService"):Set3dRenderingEnabled(true) end)
		local okLight, Lighting = pcall(game.GetService, game, "Lighting")
		if okLight and Lighting then
			for _, child in ipairs(Lighting:GetChildren()) do
				if child:IsA("DepthOfFieldEffect") and (child:HasTag(".") or child.NearIntensity == 1) then
					pcall(function() child.Enabled = false; child:Destroy() end)
				end
			end
		end
		local cam = workspace.CurrentCamera
		if cam then
			for _, child in ipairs(cam:GetChildren()) do
				if child:IsA("DepthOfFieldEffect") or (child:IsA("BasePart") and child.Material == Enum.Material.Glass) then
					pcall(function() child:Destroy() end)
				end
			end
		end
	end)

	if getgenv().__GLOBAL_HUB == self then
		getgenv().__GLOBAL_HUB = nil
	end
end

Hub._Gen = (PreviousGen > 0 and PreviousGen or 0) + 1
getgenv().__GLOBAL_HUB = Hub

return Hub


end

-- Module: components/init
__modules["components/init"] = function()
-- components/init.luau
-- Central Component Registry for Shenky Hub Design System (Modular OOP Architecture)

local Theme = __require("components/Theme")
local Button = __require("components/Button")
local Dropdown = __require("components/Dropdown")
local Toggle = __require("components/Toggle")
local Slider = __require("components/Slider")
local ProgressBar = __require("components/ProgressBar")
local Checkbox = __require("components/Checkbox")
local Input = __require("components/Input")
local Sidebar = __require("components/Sidebar")
local Category = __require("components/Category")
local Channel = __require("components/Channel")
local MetricGrid = __require("components/MetricGrid")
local Toast = __require("components/Toast")
local SegmentedControl = __require("components/SegmentedControl")
local Badge = __require("components/Badge")
local Tooltip = __require("components/Tooltip")
local Keybind = __require("components/Keybind")
local Colorpicker = __require("components/Colorpicker")
local History = __require("components/History")

local Components = {
	Theme = Theme,
	Button = Button,
	Dropdown = Dropdown,
	Toggle = Toggle,
	Slider = Slider,
	ProgressBar = ProgressBar,
	Checkbox = Checkbox,
	Input = Input,
	Sidebar = Sidebar,
	Category = Category,
	Channel = Channel,
	MetricGrid = MetricGrid,
	Toast = Toast,
	SegmentedControl = SegmentedControl,
	Badge = Badge,
	Tooltip = Tooltip,
	Keybind = Keybind,
	Colorpicker = Colorpicker,
	History = History,
}

-- Expose to global environment so engine chunks can resolve them cleanly
if getgenv then
	getgenv().__SHENKY_COMPONENTS = Components
end

return Components

end

-- Module: components/Theme
__modules["components/Theme"] = function()
-- components/Theme.luau
-- Centralized Single Source of Truth for Shenky Hub Design System Tokens

local TweenService = game:GetService("TweenService")

local Theme = {}

-- Typography
Theme.FontFamily = "rbxassetid://12187365364" -- Inter font family

function Theme.GetFont(weight, style)
	return Font.new(
		Theme.FontFamily,
		weight or Enum.FontWeight.Regular,
		style or Enum.FontStyle.Normal
	)
end

-- Web-Standard Typography Token Hierarchy (H1, H2, H3, Body, BodyMedium, Caption, Badge, Code)
Theme.Typography = {
	H1 = {
		Size = 15,
		Weight = Enum.FontWeight.Bold,
		Color = Color3.fromRGB(255, 255, 255),
		Transparency = 0.0,
		Role = "Window Brand title ('Shenky Hub'), Major modal header",
	},
	H2 = {
		Size = 13,
		Weight = Enum.FontWeight.SemiBold,
		Color = Color3.fromRGB(240, 245, 255),
		Transparency = 0.15,
		Role = "Content Card / Section header (always paired with icon)",
	},
	H3 = {
		Size = 12,
		Weight = Enum.FontWeight.SemiBold,
		Color = Color3.fromRGB(160, 175, 205),
		Transparency = 0.30,
		Role = "Sidebar Category accordion group headers",
	},
	Body = {
		Size = 12,
		Weight = Enum.FontWeight.Medium,
		Color = Color3.fromRGB(235, 240, 250),
		Transparency = 0.20,
		Role = "Interactive control labels (Checkbox, Toggle, Channel switcher)",
	},
	BodyMedium = {
		Size = 12,
		Weight = Enum.FontWeight.SemiBold,
		Color = Color3.fromRGB(245, 248, 255),
		Transparency = 0.10,
		Role = "Action buttons ('Server Hop'), active dropdown selection",
	},
	Caption = {
		Size = 11,
		Weight = Enum.FontWeight.Regular,
		Color = Color3.fromRGB(140, 145, 165),
		Transparency = 0.45,
		Role = "Helper text, subtext, descriptions, user tag (@HalyxRoi)",
	},
	Badge = {
		Size = 11,
		Weight = Enum.FontWeight.SemiBold,
		Color = Color3.fromRGB(160, 185, 255),
		Transparency = 0.10,
		Role = "Floating pill status text, micro version tags",
	},
	Code = {
		Size = 12,
		Weight = Enum.FontWeight.Medium,
		Color = Color3.fromRGB(240, 245, 255),
		Transparency = 0.10,
		Role = "Slider values ('32'), health, hex values, ping/fps",
	},
}

-- Pre-generate Fonts for each token for 0 runtime allocation overhead
for _, token in pairs(Theme.Typography) do
	token.Font = Font.new(Theme.FontFamily, token.Weight, Enum.FontStyle.Normal)
end
Theme.Typography.Numeric = Theme.Typography.Code

-- Helper method to apply typography class directly to any TextLabel, TextButton, or TextBox
function Theme.Typography.Apply(instance, tokenName)
	local token = Theme.Typography[tokenName]
	if not token then
		warn("[Theme.Typography] Unknown token: " .. tostring(tokenName))
		return
	end
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		instance.TextSize = token.Size
		instance.FontFace = token.Font
		instance.TextColor3 = token.Color
		instance.TextTransparency = token.Transparency
	end
end
Theme.ApplyTypography = Theme.Typography.Apply

-- Color Palette
Theme.Colors = {
	-- Cards & Surfaces
	CardBg = Color3.fromRGB(255, 255, 255),
	CardTransIdle = 0.94,
	CardTransHover = 0.88,
	CardTransActive = 0.84,

	-- Strokes & Borders
	StrokeColor = Color3.fromRGB(255, 255, 255),
	StrokeTransIdle = 0.90,
	StrokeColorHover = Color3.fromRGB(160, 190, 255), -- Soft Ice Blue
	StrokeTransHover = 0.70,

	-- Text Colors
	TextPrimary = Color3.fromRGB(245, 248, 255),
	TextHover = Color3.fromRGB(160, 185, 255),
	TextMuted = Color3.fromRGB(150, 155, 175),
	TextDisabled = Color3.fromRGB(110, 115, 130),

	-- Accents
	AccentBrand = Color3.fromRGB(160, 185, 255), -- #A0B9FF Soft Lavender (Shenky Hub Luxury Signature Accent)
	AccentLavender = Color3.fromRGB(160, 185, 255),
	AccentCobalt = Color3.fromRGB(0, 81, 255),
	AccentCyan = Color3.fromRGB(0, 229, 255), -- #00E5FF Icy Cyan
	AccentIceBlue = Color3.fromRGB(160, 190, 255),

	-- Dropdowns & Selections
	SelectedPillBg = Color3.fromRGB(255, 255, 255),
	SelectedPillTrans = 0.93,
	SelectedText = Color3.fromRGB(160, 185, 255),
	UnselectedText = Color3.fromRGB(220, 225, 235),
	UnselectedTextTrans = 0.35,
	UnselectedHoverTrans = 0.15,
	DropdownOpenStroke = Color3.fromRGB(160, 190, 255),
}

-- Geometry & Sizing
Theme.Geometry = {
	ButtonHeight = 26,
	ButtonCorner = 6,
	DropdownHeight = 28,
	DropdownOptionHeight = 24,
	TriggerCorner = 6,
	OptionCorner = 5,
	StrokeThickness = 1.0,
}

-- Icon Assets
Theme.Icons = {
	DropdownChevron = "rbxassetid://10709797508", -- Lucide chevrons-up-down
	Checkmark = "rbxassetid://10709790644",       -- Lucide check
}

-- Motion & Tweens
function Theme.Tween(instance, tweenInfo, properties)
	local tw = TweenService:Create(instance, tweenInfo, properties)
	tw:Play()
	return tw
end

return Theme

end

-- Module: components/Button
__modules["components/Button"] = function()
-- components/Button.luau
-- Standalone, Modular Button Component for Shenky Hub (OOP Class Architecture)

local Theme = __require("components/Theme")

local Button = {}
Button.__index = Button



function Button.new(parent, settings, flag, library)
	local self = setmetatable({}, Button)
	self.Settings = settings or {}
	self.Flag = flag
	self.Class = "Button"

	local name = self.Settings.Name or self.Settings.Title or "Button"
	local desc = self.Settings.Description or self.Settings.Desc or self.Settings.SubTitle
	local hasDesc = (type(desc) == "string" and desc ~= "")

	-- Container Frame
	local container = Instance.new("Frame")
	container.Name = "Button"
	container.BorderSizePixel = 0
	container.BackgroundTransparency = 1
	container.Parent = parent

	if hasDesc then
		container.AutomaticSize = Enum.AutomaticSize.Y
		container.Size = UDim2.new(1, 0, 0, 0)

		local layout = Instance.new("UIListLayout")
		layout.Name = "ButtonListLayout"
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 3)
		layout.Parent = container
	else
		container.AutomaticSize = Enum.AutomaticSize.None
		container.Size = UDim2.new(1, 0, 0, Theme.Geometry.ButtonHeight)
	end

	-- Interactive Pill Button
	local interact = Instance.new("TextButton")
	interact.Name = "ButtonInteract"
	interact.AutoButtonColor = false
	interact.BackgroundColor3 = Theme.Colors.CardBg
	interact.BackgroundTransparency = Theme.Colors.CardTransIdle
	interact.BorderSizePixel = 0
	interact.Size = UDim2.new(1, 0, 0, Theme.Geometry.ButtonHeight)
	interact.FontFace = Theme.GetFont(Enum.FontWeight.SemiBold)
	interact.RichText = true
	interact.TextColor3 = Theme.Colors.TextPrimary
	interact.TextSize = 12
	interact.TextTransparency = 0.1
	interact.TextTruncate = Enum.TextTruncate.AtEnd
	interact.TextXAlignment = Enum.TextXAlignment.Center
	interact.TextYAlignment = Enum.TextYAlignment.Center
	interact.LayoutOrder = 1
	interact.Text = name
	interact.Parent = container

	local corner = Instance.new("UICorner")
	corner.Name = "ButtonUICorner"
	corner.CornerRadius = UDim.new(0, Theme.Geometry.ButtonCorner)
	corner.Parent = interact

	local stroke = Instance.new("UIStroke")
	stroke.Name = "ButtonUIStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = Theme.Geometry.StrokeThickness
	stroke.Color = Theme.Colors.StrokeColor
	stroke.Transparency = Theme.Colors.StrokeTransIdle
	stroke.Parent = interact

	local scale = Instance.new("UIScale")
	scale.Name = "ButtonUIScale"
	scale.Parent = interact

	-- Subtitle TextLabel
	if hasDesc then
		local subLabel = Instance.new("TextLabel")
		subLabel.Name = "ButtonDescription"
		subLabel.BackgroundTransparency = 1
		subLabel.BorderSizePixel = 0
		subLabel.LayoutOrder = 2
		subLabel.Size = UDim2.new(1, -4, 0, 0)
		subLabel.AutomaticSize = Enum.AutomaticSize.Y
		subLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
		subLabel.Text = desc
		subLabel.TextColor3 = Theme.Colors.TextMuted
		subLabel.TextTransparency = 0.35
		subLabel.TextSize = 11
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextYAlignment = Enum.TextYAlignment.Top
		subLabel.TextWrapped = true
		subLabel.Parent = container

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 4)
		pad.PaddingTop = UDim.new(0, 2)
		pad.PaddingBottom = UDim.new(0, 9)
		pad.Parent = subLabel
		self.SubLabel = subLabel
	end

	-- Hover & Click Interactions
	local function setState(state)
		if state == "Idle" then
			Theme.Tween(interact, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
				BackgroundTransparency = Theme.Colors.CardTransIdle,
				TextColor3 = Theme.Colors.TextPrimary,
				TextTransparency = 0.1,
			})
			Theme.Tween(stroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
				Color = Theme.Colors.StrokeColor,
				Transparency = Theme.Colors.StrokeTransIdle,
			})
		elseif state == "Hover" then
			Theme.Tween(interact, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
				BackgroundTransparency = Theme.Colors.CardTransHover,
				TextColor3 = Theme.Colors.TextHover,
				TextTransparency = 0,
			})
			Theme.Tween(stroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
				Color = Theme.Colors.StrokeColorHover,
				Transparency = Theme.Colors.StrokeTransHover,
			})
		end
	end

	interact.MouseEnter:Connect(function() setState("Hover") end)
	interact.MouseLeave:Connect(function() setState("Idle") end)

	interact.MouseButton1Down:Connect(function()
		Theme.Tween(scale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.97 })
	end)
	interact.MouseButton1Up:Connect(function()
		Theme.Tween(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.0 })
	end)

	interact.MouseButton1Click:Connect(function()
		if type(self.Settings.Callback) == "function" then
			task.spawn(self.Settings.Callback)
		end
	end)

	self.Instance = container
	self.Button = interact
	self.Stroke = stroke
	self.Corner = corner
	self.Scale = scale

	if flag and library and type(library.Options) == "table" then
		library.Options[flag] = self
	end

	return self
end

function Button:UpdateName(newName)
	if self.Button then
		self.Button.Text = newName
	end
end

function Button:SetVisibility(state)
	if self.Instance then
		self.Instance.Visible = state
	end
end

function Button:Destroy()
	if self.Instance then
		self.Instance:Destroy()
	end
end

return Button

end

-- Module: components/Dropdown
__modules["components/Dropdown"] = function()
-- components/Dropdown.luau
-- Standalone, Modular Dropdown Component for Shenky Hub (Shenky Hub Luxury Style)

local Theme = __require("components/Theme")

local Dropdown = {}
Dropdown.__index = Dropdown



function Dropdown.new(parent, settings, flag, library)
	local self = setmetatable({}, Dropdown)
	self.Settings = settings or {}
	self.Flag = flag
	self.Class = "Dropdown"
	self.Selected = {}
	self.OptionObjs = {}
	self.IsOpen = false
	self.Value = nil

	local isMulti = self.Settings.Multi == true
	local isRequired = self.Settings.Required == true

	local titleText = self.Settings.Name or self.Settings.Title or "Dropdown"
	local descText = self.Settings.Description or self.Settings.Desc
	if not descText and self.Settings.SubTitle and self.Settings.SubTitle ~= titleText then
		descText = self.Settings.SubTitle
	end

	-- 1. Title Label above trigger box
	if titleText and titleText ~= "" then
		local titleFrame = Instance.new("Frame")
		titleFrame.Name = "DropdownTitle"
		titleFrame.BackgroundTransparency = 1
		titleFrame.BorderSizePixel = 0
		titleFrame.Size = UDim2.new(1, 0, 0, 16)
		titleFrame.Parent = parent

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "DropdownTitleText"
		titleLabel.BackgroundTransparency = 1
		titleLabel.BorderSizePixel = 0
		titleLabel.Size = UDim2.fromScale(1, 1)
		titleLabel.FontFace = Theme.GetFont(Enum.FontWeight.Medium)
		titleLabel.Text = titleText
		titleLabel.TextColor3 = Theme.Colors.TextPrimary
		titleLabel.TextSize = 12
		titleLabel.TextTransparency = 0.25
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.Parent = titleFrame
		self.TitleLabel = titleFrame
	end

	-- 2. Dropdown Main Trigger Frame
	local dropdown = Instance.new("Frame")
	dropdown.Name = "Dropdown"
	dropdown.BackgroundColor3 = Theme.Colors.CardBg
	dropdown.BackgroundTransparency = 0.98
	dropdown.BorderSizePixel = 0
	dropdown.Size = UDim2.new(1, 0, 0, Theme.Geometry.DropdownHeight)
	dropdown.ClipsDescendants = true
	dropdown.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Name = "DropdownUIStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = Theme.Geometry.StrokeThickness
	stroke.Color = Theme.Colors.StrokeColor
	stroke.Transparency = Theme.Colors.StrokeTransIdle
	stroke.Parent = dropdown

	local corner = Instance.new("UICorner")
	corner.Name = "DropdownUICorner"
	corner.CornerRadius = UDim.new(0, Theme.Geometry.TriggerCorner)
	corner.Parent = dropdown

	-- Trigger Click Surface
	local interact = Instance.new("TextButton")
	interact.Name = "Interact"
	interact.AutoButtonColor = false
	interact.BackgroundTransparency = 1
	interact.BorderSizePixel = 0
	interact.Size = UDim2.new(1, 0, 0, Theme.Geometry.DropdownHeight)
	interact.Text = ""
	interact.Parent = dropdown

	-- Value Display TextLabel (shows active value, starts at 10px from border)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "DropdownName"
	nameLabel.FontFace = Theme.GetFont(Enum.FontWeight.Medium)
	nameLabel.RichText = true
	nameLabel.TextColor3 = Theme.Colors.UnselectedText
	nameLabel.TextSize = 12
	nameLabel.TextTransparency = 0.1
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.BackgroundTransparency = 1
	nameLabel.BorderSizePixel = 0
	nameLabel.Position = UDim2.new(0, 10, 0, 0)
	nameLabel.Size = UDim2.new(1, -36, 0, Theme.Geometry.DropdownHeight)
	nameLabel.Text = "Select an option..."
	nameLabel.Parent = dropdown

	-- Natural Chevron Icon (Lucide 14x14px, snug at right edge)
	local chevron = Instance.new("ImageLabel")
	chevron.Name = "DropdownImage"
	chevron.Image = Theme.Icons.DropdownChevron
	chevron.ImageTransparency = 0.4
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, -10, 0, math.floor(Theme.Geometry.DropdownHeight / 2))
	chevron.Size = UDim2.fromOffset(14, 14)
	chevron.BackgroundTransparency = 1
	chevron.BorderSizePixel = 0
	chevron.Parent = dropdown

	-- 3. Options Container Frame
	local frame = Instance.new("Frame")
	frame.Name = "DropdownFrame"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Visible = false
	frame.Parent = dropdown

	local framePadding = Instance.new("UIPadding")
	framePadding.Name = "DropdownFrameUIPadding"
	framePadding.PaddingTop = UDim.new(0, Theme.Geometry.DropdownHeight + 4)
	framePadding.PaddingBottom = UDim.new(0, 6)
	framePadding.PaddingLeft = UDim.new(0, 4)
	framePadding.PaddingRight = UDim.new(0, 4)
	framePadding.Parent = frame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Name = "DropdownFrameUIListLayout"
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 2)
	listLayout.Parent = frame

	-- 3. Optional Description below trigger box
	if descText and descText ~= "" then
		local descFrame = Instance.new("Frame")
		descFrame.Name = "DropdownDescription"
		descFrame.BackgroundTransparency = 1
		descFrame.BorderSizePixel = 0
		descFrame.Size = UDim2.new(1, -4, 0, 0)
		descFrame.AutomaticSize = Enum.AutomaticSize.Y
		descFrame.Parent = parent

		local descLabel = Instance.new("TextLabel")
		descLabel.Name = "DescriptionText"
		descLabel.BackgroundTransparency = 1
		descLabel.BorderSizePixel = 0
		descLabel.Size = UDim2.new(1, 0, 0, 0)
		descLabel.AutomaticSize = Enum.AutomaticSize.Y
		descLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
		descLabel.Text = descText
		descLabel.TextColor3 = Theme.Colors.TextMuted
		descLabel.TextSize = 11
		descLabel.TextTransparency = 0.35
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.TextWrapped = true
		descLabel.Parent = descFrame

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 2)
		pad.PaddingBottom = UDim.new(0, 4)
		pad.Parent = descLabel
		self.DescFrame = descFrame
	end

	self.Instance = dropdown
	self.Trigger = interact
	self.NameLabel = nameLabel
	self.Chevron = chevron
	self.Stroke = stroke
	self.Frame = frame
	self.FramePadding = framePadding
	self.ListLayout = listLayout

	-- Helper: update header display text
	local function updateDisplayText()
		if #self.Selected == 0 then
			nameLabel.Text = self.Settings.Placeholder or "Select options..."
		elseif isMulti then
			if #self.Selected > 2 then
				nameLabel.Text = tostring(#self.Selected) .. " selected"
			else
				nameLabel.Text = table.concat(self.Selected, ", ")
			end
		else
			nameLabel.Text = tostring(self.Selected[1])
		end
	end

	-- Helper: calculate full expanded dropdown height
	local function calculateHeight()
		local total = framePadding.PaddingTop.Offset + framePadding.PaddingBottom.Offset
		local count = 0
		for _, child in ipairs(frame:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible then
				total += child.AbsoluteSize.Y > 0 and child.AbsoluteSize.Y or Theme.Geometry.DropdownOptionHeight
				count += 1
			end
		end
		if count > 1 then
			total += (count - 1) * listLayout.Padding.Offset
		end
		return total
	end

	-- Helper: toggle dropdown open/close
	local function setOpen(open)
		self.IsOpen = open
		frame.Visible = open

		if open then
			local targetH = calculateHeight()
			Theme.Tween(dropdown, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Size = UDim2.new(1, 0, 0, targetH),
			})
			Theme.Tween(chevron, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Rotation = 180,
				ImageTransparency = 0.1,
			})
			Theme.Tween(stroke, TweenInfo.new(0.22, Enum.EasingStyle.Quart), {
				Color = Theme.Colors.DropdownOpenStroke,
				Transparency = Theme.Colors.StrokeTransHover,
			})
		else
			Theme.Tween(dropdown, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Size = UDim2.new(1, 0, 0, Theme.Geometry.DropdownHeight),
			})
			Theme.Tween(chevron, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Rotation = 0,
				ImageTransparency = 0.4,
			})
			Theme.Tween(stroke, TweenInfo.new(0.18, Enum.EasingStyle.Quart), {
				Color = Theme.Colors.StrokeColor,
				Transparency = Theme.Colors.StrokeTransIdle,
			})
		end
	end

	interact.MouseButton1Click:Connect(function()
		setOpen(not self.IsOpen)
	end)

	-- 4. Option Builder
	local function createOption(optName)
		if self.OptionObjs[optName] then return end

		local optBtn = Instance.new("TextButton")
		optBtn.Name = optName
		optBtn.AutoButtonColor = false
		optBtn.BackgroundColor3 = Theme.Colors.SelectedPillBg
		optBtn.BackgroundTransparency = 1
		optBtn.BorderSizePixel = 0
		optBtn.Size = UDim2.new(1, 0, 0, Theme.Geometry.DropdownOptionHeight)
		optBtn.Text = ""
		optBtn.Parent = frame

		local optCorner = Instance.new("UICorner")
		optCorner.Name = "OptionUICorner"
		optCorner.CornerRadius = UDim.new(0, Theme.Geometry.OptionCorner)
		optCorner.Parent = optBtn

		-- Text aligns 100% pixel-perfect with trigger box text (4px pad + 6px = 10px)
		local optText = Instance.new("TextLabel")
		optText.Name = "OptionName"
		optText.BackgroundTransparency = 1
		optText.BorderSizePixel = 0
		optText.Position = UDim2.new(0, 6, 0, 0)
		optText.Size = UDim2.new(1, -32, 1, 0)
		optText.FontFace = Theme.GetFont(Enum.FontWeight.Medium)
		optText.Text = optName
		optText.TextColor3 = Theme.Colors.UnselectedText
		optText.TextSize = 12
		optText.TextTransparency = Theme.Colors.UnselectedTextTrans
		optText.TextTruncate = Enum.TextTruncate.AtEnd
		optText.TextXAlignment = Enum.TextXAlignment.Left
		optText.Parent = optBtn

		local checkmark = Instance.new("ImageLabel")
		checkmark.Name = "Checkmark"
		checkmark.Image = Theme.Icons.Checkmark
		checkmark.ImageColor3 = Theme.Colors.SelectedText
		checkmark.ImageTransparency = 1
		checkmark.AnchorPoint = Vector2.new(1, 0.5)
		checkmark.Position = UDim2.new(1, -8, 0.5, 0)
		checkmark.Size = UDim2.fromOffset(13, 13)
		checkmark.BackgroundTransparency = 1
		checkmark.BorderSizePixel = 0
		checkmark.Parent = optBtn

		local optData = {
			Button = optBtn,
			TextLabel = optText,
			Checkmark = checkmark,
			Name = optName,
		}
		self.OptionObjs[optName] = optData

		local function updateVisual(selected)
			if selected then
				Theme.Tween(optBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
					BackgroundTransparency = Theme.Colors.SelectedPillTrans,
				})
				Theme.Tween(optText, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
					TextColor3 = Theme.Colors.SelectedText,
					TextTransparency = 0,
				})
				Theme.Tween(checkmark, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
					ImageTransparency = 0,
				})
			else
				Theme.Tween(optBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
					BackgroundTransparency = 1,
				})
				Theme.Tween(optText, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
					TextColor3 = Theme.Colors.UnselectedText,
					TextTransparency = Theme.Colors.UnselectedTextTrans,
				})
				Theme.Tween(checkmark, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
					ImageTransparency = 1,
				})
			end
		end

		optBtn.MouseEnter:Connect(function()
			local isSel = table.find(self.Selected, optName) ~= nil
			if not isSel then
				Theme.Tween(optBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
					BackgroundTransparency = 0.96,
				})
				Theme.Tween(optText, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
					TextTransparency = Theme.Colors.UnselectedHoverTrans,
				})
			end
		end)

		optBtn.MouseLeave:Connect(function()
			local isSel = table.find(self.Selected, optName) ~= nil
			if not isSel then
				Theme.Tween(optBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
					BackgroundTransparency = 1,
				})
				Theme.Tween(optText, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
					TextTransparency = Theme.Colors.UnselectedTextTrans,
				})
			end
		end)

		optBtn.MouseButton1Click:Connect(function()
			local idx = table.find(self.Selected, optName)
			if isMulti then
				if idx then
					if not isRequired or #self.Selected > 1 then
						table.remove(self.Selected, idx)
						updateVisual(false)
					end
				else
					table.insert(self.Selected, optName)
					updateVisual(true)
				end
				self.Value = self.Selected
			else
				for name, item in pairs(self.OptionObjs) do
					if name == optName then
						updateVisual(true)
					else
						Theme.Tween(item.Button, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 })
						Theme.Tween(item.TextLabel, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
							TextColor3 = Theme.Colors.UnselectedText,
							TextTransparency = Theme.Colors.UnselectedTextTrans,
						})
						Theme.Tween(item.Checkmark, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { ImageTransparency = 1 })
					end
				end
				self.Selected = { optName }
				self.Value = optName
				setOpen(false)
			end

			updateDisplayText()
			if type(self.Settings.Callback) == "function" then
				task.spawn(self.Settings.Callback, self.Value)
			end
		end)

		-- Initialize visually if already selected
		if table.find(self.Selected, optName) then
			updateVisual(true)
		end
	end

	-- 5. Populate initial options
	if type(self.Settings.Options) == "table" then
		for _, opt in ipairs(self.Settings.Options) do
			createOption(tostring(opt))
		end
	end

	-- 6. Apply Default Selection (supports string name, index number, or array)
	if self.Settings.Default ~= nil then
		local def = self.Settings.Default
		if isMulti then
			if type(def) == "table" then
				for _, v in ipairs(def) do
					local str = (type(v) == "number" and self.Settings.Options and self.Settings.Options[v]) or tostring(v)
					if str and self.OptionObjs[str] and not table.find(self.Selected, str) then
						table.insert(self.Selected, str)
					end
				end
			elseif type(def) == "string" and self.OptionObjs[def] then
				table.insert(self.Selected, def)
			end
			self.Value = self.Selected
		else
			local resolved = nil
			if type(def) == "number" and self.Settings.Options and self.Settings.Options[def] then
				resolved = tostring(self.Settings.Options[def])
			elseif type(def) == "string" and self.OptionObjs[def] then
				resolved = def
			end
			if resolved and self.OptionObjs[resolved] then
				self.Selected = { resolved }
				self.Value = resolved
			end
		end
		for name, item in pairs(self.OptionObjs) do
			local isSel = table.find(self.Selected, name) ~= nil
			item.Button.BackgroundTransparency = isSel and Theme.Colors.SelectedPillTrans or 1
			item.TextLabel.TextColor3 = isSel and Theme.Colors.SelectedText or Theme.Colors.UnselectedText
			item.TextLabel.TextTransparency = isSel and 0 or Theme.Colors.UnselectedTextTrans
			item.Checkmark.ImageTransparency = isSel and 0 or 1
		end
		updateDisplayText()
	end

	self._createOption = createOption
	self._updateDisplayText = updateDisplayText

	if flag and library and type(library.Options) == "table" then
		library.Options[flag] = self
	end

	return self
end

function Dropdown:UpdateName(newName)
	if self.SubLabel and self.SubLabel:FindFirstChild("SubLabelText") then
		self.SubLabel.SubLabelText.Text = newName
	end
end

function Dropdown:SetVisibility(state)
	if self.SubLabel then
		self.SubLabel.Visible = state
	end
	if self.Instance then
		self.Instance.Visible = state
	end
end

function Dropdown:InsertOptions(newOptions)
	if type(newOptions) == "table" then
		for _, opt in ipairs(newOptions) do
			self._createOption(tostring(opt))
		end
	end
end

function Dropdown:ClearOptions()
	for _, opt in pairs(self.OptionObjs) do
		if opt.Button then opt.Button:Destroy() end
	end
	self.OptionObjs = {}
	self.Selected = {}
	self.Value = nil
	self._updateDisplayText()
end

function Dropdown:GetOptions()
	local res = {}
	for name in pairs(self.OptionObjs) do
		table.insert(res, name)
	end
	return res
end

function Dropdown:IsOption(option)
	return self.OptionObjs[tostring(option)] ~= nil
end

function Dropdown:RemoveOptions(options)
	if type(options) == "table" then
		for _, opt in ipairs(options) do
			local str = tostring(opt)
			if self.OptionObjs[str] then
				self.OptionObjs[str].Button:Destroy()
				self.OptionObjs[str] = nil
				local idx = table.find(self.Selected, str)
				if idx then
					table.remove(self.Selected, idx)
				end
			end
		end
		self._updateDisplayText()
	end
end

function Dropdown:UpdateSelection(value)
	return self:Set(value)
end

function Dropdown:Select(value)
	return self:Set(value)
end

function Dropdown:UpdateOptions(options)
	return self:Refresh(options, true)
end

function Dropdown:Set(value)
	if self.Settings.Multi then
		self.Selected = {}
		if type(value) == "table" then
			for _, v in ipairs(value) do
				local str = tostring(v)
				if self.OptionObjs[str] then
					table.insert(self.Selected, str)
				end
			end
		end
		self.Value = self.Selected
	else
		local str = tostring(value)
		if self.OptionObjs[str] then
			self.Selected = { str }
			self.Value = str
		else
			self.Selected = {}
			self.Value = nil
		end
	end
	for name, item in pairs(self.OptionObjs) do
		local isSel = table.find(self.Selected, name) ~= nil
		item.Button.BackgroundTransparency = isSel and Theme.Colors.SelectedPillTrans or 1
		item.TextLabel.TextColor3 = isSel and Theme.Colors.SelectedText or Theme.Colors.UnselectedText
		item.TextLabel.TextTransparency = isSel and 0 or Theme.Colors.UnselectedTextTrans
		item.Checkmark.ImageTransparency = isSel and 0 or 1
	end
	self._updateDisplayText()
	if type(self.Settings.Callback) == "function" then
		task.spawn(self.Settings.Callback, self.Value)
	end
end

function Dropdown:Refresh(options, deleteOld)
	if deleteOld ~= false then
		self:ClearOptions()
	end
	self:InsertOptions(options)
end

function Dropdown:Destroy()
	if self.SubLabel then self.SubLabel:Destroy() end
	if self.Instance then self.Instance:Destroy() end
end

return Dropdown

end

-- Module: components/Toggle
__modules["components/Toggle"] = function()
-- components/Toggle.luau
-- Standalone, Modular Toggle Component for Shenky Hub (OOP Class Architecture)

local Theme = __require("components/Theme")

local Toggle = {}
Toggle.__index = Toggle



function Toggle.new(parent, settings, flag, library)
	local self = setmetatable({}, Toggle)
	self.Settings = settings or {}
	self.Flag = flag
	self.Class = "Toggle"
	self.State = if settings.Default ~= nil then settings.Default elseif settings.Value ~= nil then settings.Value else false

	local name = self.Settings.Name or self.Settings.Title or "Toggle"
	local desc = self.Settings.Description or self.Settings.Desc or self.Settings.SubTitle
	local hasDesc = (type(desc) == "string" and desc ~= "")

	-- Container Frame
	local container = Instance.new("Frame")
	container.Name = "Toggle"
	container.BorderSizePixel = 0
	container.BackgroundTransparency = 1
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Size = UDim2.new(1, 0, 0, 0)
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Name = "ToggleListLayout"
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = container

	-- Interactive Row
	local row = Instance.new("TextButton")
	row.Name = "ToggleRow"
	row.AutoButtonColor = false
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 24)
	row.Text = ""
	row.LayoutOrder = 1
	row.Parent = container

	-- Label
	local label = Instance.new("TextLabel")
	label.Name = "ToggleName"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, 0, 0.5, 0)
	label.Size = UDim2.new(1, -44, 1, 0)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = Theme.GetFont(Enum.FontWeight.Medium)
	label.RichText = true
	label.Text = name
	label.TextColor3 = Theme.Colors.TextPrimary
	label.TextSize = 12
	label.TextTransparency = 0.25
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = row

	-- Switch Pill
	local switch = Instance.new("Frame")
	switch.Name = "ToggleSwitch"
	switch.AnchorPoint = Vector2.new(1, 0.5)
	switch.Position = UDim2.new(1, 0, 0.5, 0)
	switch.Size = UDim2.fromOffset(34, 18)
	switch.BackgroundColor3 = if self.State then Theme.Colors.AccentBrand else Color3.fromRGB(36, 38, 44)
	switch.BorderSizePixel = 0
	switch.Parent = row

	local switchCorner = Instance.new("UICorner")
	switchCorner.Name = "SwitchCorner"
	switchCorner.CornerRadius = UDim.new(1, 0)
	switchCorner.Parent = switch

	local switchStroke = Instance.new("UIStroke")
	switchStroke.Name = "SwitchStroke"
	switchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	switchStroke.Thickness = 1
	switchStroke.Color = Theme.Colors.StrokeColor
	switchStroke.Transparency = if self.State then 0.70 else 0.88
	switchStroke.Parent = switch
	self.SwitchStroke = switchStroke

	-- Knob
	local knob = Instance.new("Frame")
	knob.Name = "ToggleKnob"
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = if self.State then UDim2.new(1, -15, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
	knob.Size = UDim2.fromOffset(12, 12)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Parent = switch

	local knobCorner = Instance.new("UICorner")
	knobCorner.Name = "KnobCorner"
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	-- Subtitle TextLabel
	if hasDesc then
		local subLabel = Instance.new("TextLabel")
		subLabel.Name = "ToggleDescription"
		subLabel.BackgroundTransparency = 1
		subLabel.BorderSizePixel = 0
		subLabel.LayoutOrder = 2
		subLabel.Size = UDim2.new(1, -4, 0, 0)
		subLabel.AutomaticSize = Enum.AutomaticSize.Y
		subLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
		subLabel.Text = desc
		subLabel.TextColor3 = Theme.Colors.TextMuted
		subLabel.TextTransparency = 0.35
		subLabel.TextSize = 11
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextYAlignment = Enum.TextYAlignment.Top
		subLabel.TextWrapped = true
		subLabel.Parent = container

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 4)
		pad.Parent = subLabel
		self.SubLabel = subLabel
	end

	local function updateVisuals(anim)
		local targetPos = if self.State then UDim2.new(1, -15, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
		local targetColor = if self.State then Theme.Colors.AccentBrand else Color3.fromRGB(36, 38, 44)
		local targetStrokeTrans = if self.State then 0.70 else 0.88

		if anim then
			Theme.Tween(knob, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = targetPos,
			})
			Theme.Tween(switch, TweenInfo.new(0.20, Enum.EasingStyle.Quad), {
				BackgroundColor3 = targetColor,
			})
			Theme.Tween(switchStroke, TweenInfo.new(0.20, Enum.EasingStyle.Quad), {
				Transparency = targetStrokeTrans,
			})
		else
			knob.Position = targetPos
			switch.BackgroundColor3 = targetColor
			switchStroke.Transparency = targetStrokeTrans
		end
	end

	-- Hover Interactions
	row.MouseEnter:Connect(function()
		Theme.Tween(label, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			TextTransparency = 0.05,
		})
		Theme.Tween(switchStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			Transparency = if self.State then 0.55 else 0.75,
		})
	end)

	row.MouseLeave:Connect(function()
		Theme.Tween(label, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			TextTransparency = 0.25,
		})
		Theme.Tween(switchStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			Transparency = if self.State then 0.70 else 0.88,
		})
	end)

	local function trigger()
		self.State = not self.State
		updateVisuals(true)
		if type(self.Settings.Callback) == "function" then
			task.spawn(self.Settings.Callback, self.State)
		end
	end

	row.MouseButton1Click:Connect(trigger)

	self.Instance = container
	self.Row = row
	self.Label = label
	self.Switch = switch
	self.Knob = knob

	if flag and library and type(library.Options) == "table" then
		library.Options[flag] = self
	end

	return self
end

function Toggle:Toggle()
	self.State = not self.State
	self:UpdateState(self.State)
end

function Toggle:Set(newState, ignoreCallback)
	self.State = newState
	if self.Knob and self.Switch then
		local targetPos = if self.State then UDim2.new(1, -15, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
		local targetColor = if self.State then Theme.Colors.AccentBrand else Color3.fromRGB(36, 38, 44)
		local targetStrokeTrans = if self.State then 0.70 else 0.88
		pcall(function()
			Theme.Tween(self.Knob, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = targetPos,
			})
			Theme.Tween(self.Switch, TweenInfo.new(0.20, Enum.EasingStyle.Quad), {
				BackgroundColor3 = targetColor,
			})
			if self.SwitchStroke then
				Theme.Tween(self.SwitchStroke, TweenInfo.new(0.20, Enum.EasingStyle.Quad), {
					Transparency = targetStrokeTrans,
				})
			end
		end)
	end
	if not ignoreCallback and type(self.Settings.Callback) == "function" then
		task.spawn(self.Settings.Callback, self.State)
	end
end

Toggle.UpdateState = Toggle.Set
Toggle.SetState = Toggle.Set
Toggle.SetValue = Toggle.Set
Toggle.Get = Toggle.GetState
Toggle.GetValue = Toggle.GetState

function Toggle:GetState()
	return self.State
end

function Toggle:UpdateName(newName)
	if self.Label then
		self.Label.Text = newName
	end
end

function Toggle:SetVisibility(state)
	if self.Instance then
		self.Instance.Visible = state
	end
end

function Toggle:Destroy()
	if self.Instance then
		self.Instance:Destroy()
	end
end

return Toggle

end

-- Module: components/Slider
__modules["components/Slider"] = function()
-- components/Slider.luau
-- Standalone, Modular Slider Component for Shenky Hub (OOP Class Architecture)
-- Modern 2-Row Layout: Header (Label + Interactive Textbox Badge) + Full-Width Track + Subtitle

local UserInputService = game:GetService("UserInputService")
local Theme = __require("components/Theme")

local Slider = {}
Slider.__index = Slider



function Slider.new(parent, settings, flag, library)
	local self = setmetatable({}, Slider)
	self.Settings = settings or {}
	self.Flag = flag
	self.Class = "Slider"

	local valTable = (type(self.Settings.Value) == "table" and self.Settings.Value) or nil
	self.Min = self.Settings.Min or (self.Settings ).Minimum or (valTable and (valTable.Min or valTable.Minimum)) or 0
	self.Max = self.Settings.Max or (self.Settings ).Maximum or (valTable and (valTable.Max or valTable.Maximum)) or 100
	self.Precision = self.Settings.Precision or (valTable and valTable.Precision) or 0
	self.Value = self.Settings.Default or (valTable and valTable.Default) or (type(self.Settings.Value) == "number" and self.Settings.Value) or self.Min
	self.Prefix = self.Settings.Prefix or ""
	self.Suffix = self.Settings.Suffix or ""

	-- Clamp initial value
	self.Value = math.clamp(self.Value, self.Min, self.Max)

	local name = self.Settings.Name or self.Settings.Title or "Slider"
	local desc = self.Settings.Description or self.Settings.Desc or self.Settings.SubTitle
	local hasDesc = (type(desc) == "string" and desc ~= "")

	-- Container Frame
	local container = Instance.new("Frame")
	container.Name = "Slider"
	container.BorderSizePixel = 0
	container.BackgroundTransparency = 1
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Size = UDim2.new(1, 0, 0, 0)
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Name = "SliderListLayout"
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = container

	-- Row 1: Header (Label + Interactive Value Badge TextBox)
	local headerRow = Instance.new("Frame")
	headerRow.Name = "SliderHeader"
	headerRow.BackgroundTransparency = 1
	headerRow.BorderSizePixel = 0
	headerRow.Size = UDim2.new(1, 0, 0, 18)
	headerRow.LayoutOrder = 1
	headerRow.Parent = container

	local label = Instance.new("TextLabel")
	label.Name = "SliderName"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, 0, 0.5, 0)
	label.Size = UDim2.new(1, -68, 1, 0)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = Theme.GetFont(Enum.FontWeight.Medium)
	label.RichText = true
	label.Text = name
	label.TextColor3 = Theme.Colors.TextPrimary
	label.TextSize = 12
	label.TextTransparency = 0.25
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = headerRow

	-- Interactive Value Badge Frame
	local valueContainer = Instance.new("Frame")
	valueContainer.Name = "SliderValueContainer"
	valueContainer.AnchorPoint = Vector2.new(1, 0.5)
	valueContainer.Position = UDim2.new(1, 0, 0.5, 0)
	valueContainer.Size = UDim2.new(0, 48, 0, 18)
	valueContainer.AutomaticSize = Enum.AutomaticSize.X
	valueContainer.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
	valueContainer.BorderSizePixel = 0
	valueContainer.Parent = headerRow

	local valueCorner = Instance.new("UICorner")
	valueCorner.Name = "ValueCorner"
	valueCorner.CornerRadius = UDim.new(0, 4)
	valueCorner.Parent = valueContainer

	local valueStroke = Instance.new("UIStroke")
	valueStroke.Name = "ValueStroke"
	valueStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	valueStroke.Thickness = 1
	valueStroke.Color = Theme.Colors.StrokeColor
	valueStroke.Transparency = 0.80
	valueStroke.Parent = valueContainer

	local valuePad = Instance.new("UIPadding")
	valuePad.Name = "ValuePadding"
	valuePad.PaddingLeft = UDim.new(0, 6)
	valuePad.PaddingRight = UDim.new(0, 6)
	valuePad.PaddingTop = UDim.new(0, 1)
	valuePad.PaddingBottom = UDim.new(0, 1)
	valuePad.Parent = valueContainer

	local valueInput = Instance.new("TextBox")
	valueInput.Name = "SliderInput"
	valueInput.AnchorPoint = Vector2.new(0.5, 0.5)
	valueInput.Position = UDim2.new(0.5, 0, 0.5, 0)
	valueInput.Size = UDim2.new(1, 0, 1, 0)
	valueInput.AutomaticSize = Enum.AutomaticSize.X
	valueInput.BackgroundTransparency = 1
	valueInput.BorderSizePixel = 0
	valueInput.ClearTextOnFocus = false
	valueInput.FontFace = Theme.GetFont(Enum.FontWeight.SemiBold)
	valueInput.TextColor3 = Theme.Colors.TextPrimary
	valueInput.TextSize = 11
	valueInput.TextTransparency = 0.15
	valueInput.TextXAlignment = Enum.TextXAlignment.Center
	valueInput.TextYAlignment = Enum.TextYAlignment.Center
	valueInput.Parent = valueContainer

	-- Row 2: Full-Width Slider Track Row
	local trackRow = Instance.new("TextButton")
	trackRow.Name = "SliderTrackContainer"
	trackRow.AutoButtonColor = false
	trackRow.BackgroundTransparency = 1
	trackRow.BorderSizePixel = 0
	trackRow.Size = UDim2.new(1, 0, 0, 14)
	trackRow.Text = ""
	trackRow.LayoutOrder = 2
	trackRow.Parent = container

	local trackBg = Instance.new("Frame")
	trackBg.Name = "TrackBackground"
	trackBg.AnchorPoint = Vector2.new(0, 0.5)
	trackBg.Position = UDim2.new(0, 0, 0.5, 0)
	trackBg.Size = UDim2.new(1, 0, 0, 4)
	trackBg.BackgroundColor3 = Color3.fromRGB(36, 38, 44)
	trackBg.BorderSizePixel = 0
	trackBg.Parent = trackRow

	local trackCorner = Instance.new("UICorner")
	trackCorner.Name = "TrackCorner"
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = trackBg

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Name = "TrackStroke"
	trackStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	trackStroke.Thickness = 1
	trackStroke.Color = Theme.Colors.StrokeColor
	trackStroke.Transparency = 0.90
	trackStroke.Parent = trackBg

	local fill = Instance.new("Frame")
	fill.Name = "TrackFill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.new(0, 0, 0.5, 0)
	fill.Size = UDim2.new(0, 0, 0, 4)
	fill.BackgroundColor3 = Theme.Colors.AccentBrand
	fill.BorderSizePixel = 0
	fill.Parent = trackRow

	local fillCorner = Instance.new("UICorner")
	fillCorner.Name = "FillCorner"
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local thumb = Instance.new("ImageButton")
	thumb.Name = "SliderThumb"
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Position = UDim2.new(0, 0, 0.5, 0)
	thumb.Size = UDim2.fromOffset(12, 12)
	thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	thumb.BorderSizePixel = 0
	thumb.AutoButtonColor = false
	thumb.Parent = trackRow

	local thumbCorner = Instance.new("UICorner")
	thumbCorner.Name = "ThumbCorner"
	thumbCorner.CornerRadius = UDim.new(1, 0)
	thumbCorner.Parent = thumb

	local thumbScale = Instance.new("UIScale")
	thumbScale.Name = "ThumbScale"
	thumbScale.Parent = thumb

	-- Row 3: Subtitle TextLabel
	if hasDesc then
		local subLabel = Instance.new("TextLabel")
		subLabel.Name = "SliderDescription"
		subLabel.BackgroundTransparency = 1
		subLabel.BorderSizePixel = 0
		subLabel.LayoutOrder = 3
		subLabel.Size = UDim2.new(1, -4, 0, 0)
		subLabel.AutomaticSize = Enum.AutomaticSize.Y
		subLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
		subLabel.Text = desc
		subLabel.TextColor3 = Theme.Colors.TextMuted
		subLabel.TextTransparency = 0.35
		subLabel.TextSize = 11
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextYAlignment = Enum.TextYAlignment.Top
		subLabel.TextWrapped = true
		subLabel.Parent = container

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 2)
		pad.PaddingTop = UDim.new(0, 2)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.Parent = subLabel
		self.SubLabel = subLabel
	end

	local function formatDisplay(val, withSuffix)
		local numStr
		if self.Precision > 0 then
			numStr = string.format("%." .. self.Precision .. "f", val)
		else
			numStr = tostring(math.round(val))
		end
		if withSuffix then
			return (self.Prefix or "") .. numStr .. (self.Suffix or "")
		end
		return numStr
	end

	local function updateVisuals(anim)
		local ratio = math.clamp((self.Value - self.Min) / (self.Max - self.Min), 0, 1)
		if not valueInput:IsFocused() then
			valueInput.Text = formatDisplay(self.Value, true)
		end

		local targetFill = UDim2.new(ratio, 0, 0, 4)
		local targetThumb = UDim2.new(ratio, 0, 0.5, 0)

		if anim then
			Theme.Tween(fill, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = targetFill })
			Theme.Tween(thumb, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = targetThumb })
		else
			fill.Size = targetFill
			thumb.Position = targetThumb
		end
	end

	updateVisuals(false)

	-- Value Input TextBox interactions
	valueInput.Focused:Connect(function()
		Theme.Tween(valueStroke, TweenInfo.new(0.15), {
			Color = Theme.Colors.AccentBrand,
			Transparency = 0.20,
		})
		-- Display bare number during editing for hassle-free typing
		valueInput.Text = formatDisplay(self.Value, false)
	end)

	valueInput.FocusLost:Connect(function(_enterPressed)
		Theme.Tween(valueStroke, TweenInfo.new(0.15), {
			Color = Theme.Colors.StrokeColor,
			Transparency = 0.80,
		})

		local inputText = tostring(valueInput.Text or "")
		local numStr = inputText:match("%-?%d+%.?%d*")
		local num = numStr and tonumber(numStr)

		if num then
			local step = 10 ^ (-self.Precision)
			local snapped = math.round(num / step) * step
			snapped = math.clamp(snapped, self.Min, self.Max)
			self:SetValue(snapped)
			if type((self.Settings ).onInputComplete) == "function" then
				task.spawn((self.Settings ).onInputComplete, self.Value)
			end
		else
			valueInput.Text = formatDisplay(self.Value, true)
		end
	end)

	valueContainer.MouseEnter:Connect(function()
		if not valueInput:IsFocused() then
			Theme.Tween(valueStroke, TweenInfo.new(0.15), {
				Transparency = 0.50,
				Color = Theme.Colors.AccentBrand,
			})
		end
	end)

	valueContainer.MouseLeave:Connect(function()
		if not valueInput:IsFocused() then
			Theme.Tween(valueStroke, TweenInfo.new(0.15), {
				Transparency = 0.80,
				Color = Theme.Colors.StrokeColor,
			})
		end
	end)

	-- Dragging Logic
	local dragging = false

	local function updateFromInput(input)
		local barWidth = trackRow.AbsoluteSize.X
		if barWidth <= 0 then return end
		local mouseX = input.Position.X
		local startX = trackRow.AbsolutePosition.X
		local ratio = math.clamp((mouseX - startX) / barWidth, 0, 1)
		local rawVal = self.Min + ratio * (self.Max - self.Min)

		local step = 10 ^ (-self.Precision)
		local snappedVal = math.round(rawVal / step) * step
		snappedVal = math.clamp(snappedVal, self.Min, self.Max)

		if snappedVal ~= self.Value then
			self.Value = snappedVal
			updateVisuals(false)
			if type(self.Settings.Callback) == "function" then
				task.spawn(self.Settings.Callback, self.Value)
			end
		end
	end

	local moveConn = nil
	local endConn = nil

	local function stopDrag()
		if not dragging then return end
		dragging = false
		if moveConn then moveConn:Disconnect(); moveConn = nil end
		if endConn then endConn:Disconnect(); endConn = nil end

		Theme.Tween(thumbScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 1.0 })
		Theme.Tween(trackStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Transparency = 0.90 })
		Theme.Tween(label, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { TextTransparency = 0.25 })
		if type((self.Settings ).onInputComplete) == "function" then
			task.spawn((self.Settings ).onInputComplete, self.Value)
		end
	end

	local function startDrag(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			Theme.Tween(thumbScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1.25 })
			Theme.Tween(trackStroke, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Transparency = 0.70 })
			Theme.Tween(label, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { TextTransparency = 0.05 })
			updateFromInput(input)

			if moveConn then moveConn:Disconnect() end
			if endConn then endConn:Disconnect() end

			moveConn = UserInputService.InputChanged:Connect(function(moveInput)
				if dragging and (moveInput.UserInputType == Enum.UserInputType.MouseMovement or moveInput.UserInputType == Enum.UserInputType.Touch) then
					updateFromInput(moveInput)
				end
			end)

			endConn = UserInputService.InputEnded:Connect(function(endInput)
				if endInput.UserInputType == Enum.UserInputType.MouseButton1 or endInput.UserInputType == Enum.UserInputType.Touch then
					stopDrag()
				end
			end)
		end
	end

	trackRow.InputBegan:Connect(startDrag)
	thumb.InputBegan:Connect(startDrag)

	-- Hover on row
	trackRow.MouseEnter:Connect(function()
		Theme.Tween(label, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { TextTransparency = 0.05 })
		Theme.Tween(trackStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Transparency = 0.78 })
	end)

	trackRow.MouseLeave:Connect(function()
		if not dragging then
			Theme.Tween(label, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { TextTransparency = 0.25 })
			Theme.Tween(trackStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Transparency = 0.90 })
		end
	end)

	self.Instance = container
	self.Label = label
	self.ValueLabel = valueInput
	self.ValueInput = valueInput
	self.ValueContainer = valueContainer
	self.Fill = fill
	self.Thumb = thumb

	if flag and library and type(library.Options) == "table" then
		library.Options[flag] = self
	end

	return self
end

function Slider:SetValue(val, ignoreCallback)
	val = math.clamp(val, self.Min, self.Max)
	local step = 10 ^ (-self.Precision)
	val = math.round(val / step) * step
	self.Value = val

	local ratio = math.clamp((self.Value - self.Min) / (self.Max - self.Min), 0, 1)
	if self.ValueInput and not self.ValueInput:IsFocused() then
		local numStr = if self.Precision > 0
			then string.format("%." .. self.Precision .. "f", self.Value)
			else tostring(math.round(self.Value))
		self.ValueInput.Text = (self.Prefix or "") .. numStr .. (self.Suffix or "")
	end

	if self.Fill and self.Thumb then
		pcall(function()
			Theme.Tween(self.Fill, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Size = UDim2.new(ratio, 0, 0, 4) })
			Theme.Tween(self.Thumb, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Position = UDim2.new(ratio, 0, 0.5, 0) })
		end)
	end

	if not ignoreCallback and type(self.Settings.Callback) == "function" then
		task.spawn(self.Settings.Callback, self.Value)
	end
end

Slider.UpdateValue = Slider.SetValue
Slider.Set = Slider.SetValue
Slider.Get = Slider.GetValue

function Slider:GetValue()
	return self.Value
end

function Slider:UpdateName(newName)
	if self.Label then
		self.Label.Text = newName
	end
end

function Slider:SetVisibility(state)
	if self.Instance then
		self.Instance.Visible = state
	end
end

function Slider:Destroy()
	if self.Instance then
		self.Instance:Destroy()
	end
end

return Slider

end

-- Module: components/ProgressBar
__modules["components/ProgressBar"] = function()
-- components/ProgressBar.luau
-- Standalone, Modular Progress Bar Component for Shenky Hub (Shenky Hub Luxury Style)

local Theme = __require("components/Theme")

local ProgressBar = {}
ProgressBar.__index = ProgressBar



function ProgressBar.new(parent, settings, flag, library)
	local self = setmetatable({}, ProgressBar)
	self.Settings = settings or {}
	self.Flag = flag
	self.Class = "ProgressBar"

	self.Min = self.Settings.Min or 0
	self.Max = self.Settings.Max or 100
	self.Value = self.Settings.Value or self.Settings.Default or self.Min
	self.Value = math.clamp(self.Value, self.Min, self.Max)

	self.ShowPercent = if self.Settings.ShowPercent ~= nil then self.Settings.ShowPercent else true
	self.ShowValues = if self.Settings.ShowValues ~= nil then self.Settings.ShowValues else true
	self.FillColor = self.Settings.Color or Theme.Colors.SelectedText or Color3.fromRGB(160, 185, 255)

	local name = self.Settings.Name or self.Settings.Title or "Progress"
	local desc = self.Settings.Description or self.Settings.Desc or self.Settings.SubTitle
	local hasDesc = (type(desc) == "string" and desc ~= "")

	-- Container Frame
	local container = Instance.new("Frame")
	container.Name = "ProgressBar"
	container.BorderSizePixel = 0
	container.BackgroundTransparency = 1
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Size = UDim2.new(1, 0, 0, 0)
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Name = "ProgressListLayout"
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = container

	-- Row 1: Header Row (Title on Left, Formatted Value & Percent on Right)
	local headerRow = Instance.new("Frame")
	headerRow.Name = "ProgressHeader"
	headerRow.BackgroundTransparency = 1
	headerRow.BorderSizePixel = 0
	headerRow.Size = UDim2.new(1, 0, 0, 16)
	headerRow.LayoutOrder = 1
	headerRow.Parent = container

	local label = Instance.new("TextLabel")
	label.Name = "ProgressName"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, 0, 0.5, 0)
	label.Size = UDim2.new(0.5, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = Theme.GetFont(Enum.FontWeight.Medium)
	label.RichText = true
	label.Text = name
	label.TextColor3 = Theme.Colors.TextPrimary
	label.TextSize = 12
	label.TextTransparency = 0.25
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = headerRow

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "ProgressValue"
	valueLabel.AnchorPoint = Vector2.new(1, 0.5)
	valueLabel.Position = UDim2.new(1, 0, 0.5, 0)
	valueLabel.Size = UDim2.new(0.5, 0, 1, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.BorderSizePixel = 0
	valueLabel.FontFace = Theme.GetFont(Enum.FontWeight.SemiBold)
	valueLabel.RichText = true
	valueLabel.TextSize = 11
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.TextYAlignment = Enum.TextYAlignment.Center
	valueLabel.Parent = headerRow

	-- Row 2: Track Bar Container
	local trackRow = Instance.new("Frame")
	trackRow.Name = "ProgressTrackRow"
	trackRow.BackgroundTransparency = 1
	trackRow.BorderSizePixel = 0
	trackRow.Size = UDim2.new(1, 0, 0, 6)
	trackRow.LayoutOrder = 2
	trackRow.Parent = container

	local trackBg = Instance.new("Frame")
	trackBg.Name = "TrackBackground"
	trackBg.AnchorPoint = Vector2.new(0, 0.5)
	trackBg.Position = UDim2.new(0, 0, 0.5, 0)
	trackBg.Size = UDim2.new(1, 0, 0, 4)
	trackBg.BackgroundColor3 = Color3.fromRGB(36, 38, 44)
	trackBg.BorderSizePixel = 0
	trackBg.Parent = trackRow

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = trackBg

	local trackStroke = Instance.new("UIStroke")
	trackStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	trackStroke.Thickness = 1
	trackStroke.Color = Theme.Colors.StrokeColor
	trackStroke.Transparency = 0.92
	trackStroke.Parent = trackBg

	local fill = Instance.new("Frame")
	fill.Name = "TrackFill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.new(0, 0, 0.5, 0)
	fill.Size = UDim2.new(0, 0, 0, 4)
	fill.BackgroundColor3 = self.FillColor
	fill.BorderSizePixel = 0
	fill.Parent = trackRow

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	-- Row 3: Subtitle TextLabel
	if hasDesc then
		local subLabel = Instance.new("TextLabel")
		subLabel.Name = "ProgressDescription"
		subLabel.BackgroundTransparency = 1
		subLabel.BorderSizePixel = 0
		subLabel.LayoutOrder = 3
		subLabel.Size = UDim2.new(1, -4, 0, 0)
		subLabel.AutomaticSize = Enum.AutomaticSize.Y
		subLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
		subLabel.Text = desc
		subLabel.TextColor3 = Theme.Colors.TextMuted
		subLabel.TextTransparency = 0.35
		subLabel.TextSize = 11
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextYAlignment = Enum.TextYAlignment.Top
		subLabel.TextWrapped = true
		subLabel.Parent = container

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 2)
		pad.PaddingBottom = UDim.new(0, 4)
		pad.Parent = subLabel
		self.SubLabel = subLabel
	end

	local function formatText(val, max)
		local ratio = if max > 0 then math.clamp(val / max, 0, 1) else 0
		local pct = math.round(ratio * 100)
		local pieces = {}

		if self.ShowValues then
			table.insert(pieces, string.format('<font color="rgb(160, 165, 180)">%s / %s</font>', tostring(math.round(val)), tostring(math.round(max))))
		end

		if self.ShowPercent then
			local r = math.round(self.FillColor.R * 255)
			local g = math.round(self.FillColor.G * 255)
			local b = math.round(self.FillColor.B * 255)
			table.insert(pieces, string.format('<font color="rgb(%d, %d, %d)"><b>%d%%</b></font>', r, g, b, pct))
		end

		return table.concat(pieces, " ")
	end

	local function updateVisuals(anim)
		local ratio = if self.Max > self.Min then math.clamp((self.Value - self.Min) / (self.Max - self.Min), 0, 1) else 0
		valueLabel.Text = formatText(self.Value, self.Max)

		local targetFill = UDim2.new(ratio, 0, 0, 4)
		if anim then
			Theme.Tween(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = targetFill })
		else
			fill.Size = targetFill
		end
	end

	updateVisuals(false)

	self.Instance = container
	self.Label = label
	self.ValueLabel = valueLabel
	self.Fill = fill
	self.UpdateVisuals = updateVisuals

	if flag and library and type(library.Options) == "table" then
		library.Options[flag] = self
	end

	return self
end

function ProgressBar:SetProgress(val, newMax, customText)
	if newMax ~= nil then
		self.Max = newMax
	end
	self.Value = math.clamp(val, self.Min, self.Max)

	if customText then
		self.ValueLabel.Text = customText
		local ratio = if self.Max > self.Min then math.clamp((self.Value - self.Min) / (self.Max - self.Min), 0, 1) else 0
		Theme.Tween(self.Fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(ratio, 0, 0, 4) })
	else
		self.UpdateVisuals(true)
	end
end

function ProgressBar:SetColor(newColor)
	self.FillColor = newColor
	self.Fill.BackgroundColor3 = newColor
	self.UpdateVisuals(false)
end

function ProgressBar:UpdateName(newName)
	if self.Label then
		self.Label.Text = newName
	end
end

function ProgressBar:SetVisibility(state)
	if self.Instance then
		self.Instance.Visible = state
	end
end

function ProgressBar:Destroy()
	if self.Instance then
		self.Instance:Destroy()
	end
end

return ProgressBar

end

-- Module: components/Checkbox
__modules["components/Checkbox"] = function()
-- components/Checkbox.luau
-- Standalone, Modular Checkbox Component for Shenky Hub (Shenky Hub)

local Theme = __require("components/Theme")

local Checkbox = {}
Checkbox.__index = Checkbox



function Checkbox.new(parent, settings, flag, library)
	local self = setmetatable({}, Checkbox)
	self.Settings = settings or {}
	self.Flag = flag
	self.Class = "Checkbox"
	self.State = if settings.Value ~= nil then settings.Value else (if settings.Default ~= nil then settings.Default else false)

	local name = self.Settings.Name or self.Settings.Title or "Checkbox"
	local desc = self.Settings.Description or self.Settings.Desc or self.Settings.SubTitle
	local hasDesc = (type(desc) == "string" and desc ~= "")

	-- Container Frame
	local container = Instance.new("Frame")
	container.Name = "Checkbox"
	container.BorderSizePixel = 0
	container.BackgroundTransparency = 1
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Size = UDim2.new(1, 0, 0, 0)
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Name = "CheckboxListLayout"
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = container

	-- Interactive Row
	local row = Instance.new("TextButton")
	row.Name = "CheckboxRow"
	row.AutoButtonColor = false
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 22)
	row.Text = ""
	row.LayoutOrder = 1
	row.Parent = container

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.Name = "RowLayout"
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.Parent = row

	-- Checkbox Square Box
	local box = Instance.new("Frame")
	box.Name = "CheckmarkBox"
	box.LayoutOrder = 1
	box.Size = UDim2.fromOffset(16, 16)
	box.BorderSizePixel = 0
	box.Parent = row

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 4)
	boxCorner.Parent = box

	local boxStroke = Instance.new("UIStroke")
	boxStroke.Name = "BoxStroke"
	boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	boxStroke.Thickness = 1
	boxStroke.Parent = box

	local checkIcon = Instance.new("ImageLabel")
	checkIcon.Name = "CheckIcon"
	checkIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	checkIcon.Position = UDim2.fromScale(0.5, 0.5)
	checkIcon.Size = UDim2.fromOffset(11, 11)
	checkIcon.BackgroundTransparency = 1
	checkIcon.BorderSizePixel = 0
	checkIcon.Image = Theme.Icons.Checkmark
	checkIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
	checkIcon.Parent = box

	local boxScale = Instance.new("UIScale")
	boxScale.Name = "BoxScale"
	boxScale.Parent = box

	-- Label
	local label = Instance.new("TextLabel")
	label.Name = "CheckboxTitle"
	label.LayoutOrder = 2
	label.Size = UDim2.new(0, 0, 1, 0)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = Theme.GetFont(Enum.FontWeight.Medium)
	label.RichText = true
	label.Text = name
	label.TextColor3 = Theme.Colors.TextPrimary
	label.TextSize = 12
	label.TextTransparency = 0.25
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = row

	-- Subtitle TextLabel
	if hasDesc then
		local subLabel = Instance.new("TextLabel")
		subLabel.Name = "CheckboxDescription"
		subLabel.BackgroundTransparency = 1
		subLabel.BorderSizePixel = 0
		subLabel.LayoutOrder = 2
		subLabel.Size = UDim2.new(1, -4, 0, 0)
		subLabel.AutomaticSize = Enum.AutomaticSize.Y
		subLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
		subLabel.Text = desc
		subLabel.TextColor3 = Theme.Colors.TextMuted
		subLabel.TextTransparency = 0.35
		subLabel.TextSize = 11
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextYAlignment = Enum.TextYAlignment.Top
		subLabel.TextWrapped = true
		subLabel.Parent = container

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 2)
		pad.PaddingTop = UDim.new(0, 1)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.Parent = subLabel
		self.SubLabel = subLabel
	end

	local function updateVisuals(anim)
		local activeBg = Theme.Colors.SelectedText or Color3.fromRGB(150, 140, 255)
		local inactiveBg = Theme.Colors.CardBg
		local targetBg = if self.State then activeBg else inactiveBg
		local targetTrans = if self.State then 0.05 else 0.94
		local targetStrokeCol = if self.State then Color3.fromRGB(180, 175, 255) else Theme.Colors.StrokeColor
		local targetStrokeTrans = if self.State then 0.50 else 0.88
		local targetIconTrans = if self.State then 0 else 1

		if anim then
			Theme.Tween(box, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
				BackgroundColor3 = targetBg,
				BackgroundTransparency = targetTrans,
			})
			Theme.Tween(boxStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
				Color = targetStrokeCol,
				Transparency = targetStrokeTrans,
			})
			Theme.Tween(checkIcon, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
				ImageTransparency = targetIconTrans,
			})
		else
			box.BackgroundColor3 = targetBg
			box.BackgroundTransparency = targetTrans
			boxStroke.Color = targetStrokeCol
			boxStroke.Transparency = targetStrokeTrans
			checkIcon.ImageTransparency = targetIconTrans
		end
	end

	updateVisuals(false)

	-- Hover Interactions
	row.MouseEnter:Connect(function()
		Theme.Tween(label, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { TextTransparency = 0.05 })
		Theme.Tween(boxStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			Transparency = if self.State then 0.35 else 0.70,
		})
	end)

	row.MouseLeave:Connect(function()
		Theme.Tween(label, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { TextTransparency = 0.25 })
		Theme.Tween(boxStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			Transparency = if self.State then 0.50 else 0.88,
		})
	end)

	local function trigger()
		self.State = not self.State
		Theme.Tween(boxScale, TweenInfo.new(0.08, Enum.EasingStyle.Quad), { Scale = 0.88 })
		task.delay(0.08, function()
			Theme.Tween(boxScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.0 })
		end)
		updateVisuals(true)
		if type(self.Settings.Callback) == "function" then
			task.spawn(self.Settings.Callback, self.State)
		end
	end

	row.MouseButton1Click:Connect(trigger)

	self.Instance = container
	self.Row = row
	self.Box = box
	self.CheckIcon = checkIcon
	self.Label = label

	if flag and library and type(library.Options) == "table" then
		library.Options[flag] = self
	end

	return self
end

function Checkbox:Toggle()
	self.State = not self.State
	self:UpdateState(self.State)
end

function Checkbox:UpdateState(newState)
	self.State = newState
	local activeBg = Theme.Colors.SelectedText or Color3.fromRGB(150, 140, 255)
	local targetBg = if self.State then activeBg else Theme.Colors.CardBg
	local targetTrans = if self.State then 0.05 else 0.94
	Theme.Tween(self.Box, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
		BackgroundColor3 = targetBg,
		BackgroundTransparency = targetTrans,
	})
	Theme.Tween(self.CheckIcon, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
		ImageTransparency = if self.State then 0 else 1,
	})
	if type(self.Settings.Callback) == "function" then
		task.spawn(self.Settings.Callback, self.State)
	end
end

function Checkbox:GetState()
	return self.State
end

function Checkbox:UpdateName(newName)
	if self.Label then
		self.Label.Text = newName
	end
end

function Checkbox:SetVisibility(state)
	if self.Instance then
		self.Instance.Visible = state
	end
end

function Checkbox:Destroy()
	if self.Instance then
		self.Instance:Destroy()
	end
end

return Checkbox

end

-- Module: components/Input
__modules["components/Input"] = function()
-- components/Input.luau
-- Standalone, Modular Input (Textfield) Component for Shenky Hub (Shenky Hub Luxury Style)
-- 3-Row Stacked Layout: Title -> Full-Width 26px Field (Focus Glow) -> Universal Subtitle

local Theme = __require("components/Theme")

local Input = {}
Input.__index = Input



function Input.new(parent, settings, flag, library)
	local self = setmetatable({}, Input)
	self.Settings = settings or {}
	self.Flag = flag
	self.Class = "Input"
	self.Value = self.Settings.Value or self.Settings.Default or ""

	local name = self.Settings.Name or self.Settings.Title or "Input"
	local placeholder = self.Settings.Placeholder or "Type here..."
	local clearOnFocus = if self.Settings.ClearTextOnFocus ~= nil then self.Settings.ClearTextOnFocus else false
	local desc = self.Settings.Description or self.Settings.Desc or self.Settings.SubTitle
	local hasDesc = (type(desc) == "string" and desc ~= "")

	-- Container Frame (Vertical Stack with 3px internal gap)
	local container = Instance.new("Frame")
	container.Name = "Input"
	container.BorderSizePixel = 0
	container.BackgroundTransparency = 1
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Size = UDim2.new(1, 0, 0, 0)
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Name = "InputListLayout"
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = container

	-- Row 1: Feature Title Label
	local label = Instance.new("TextLabel")
	label.Name = "InputName"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.new(1, 0, 0, 16)
	label.FontFace = Theme.GetFont(Enum.FontWeight.Medium)
	label.RichText = true
	label.Text = name
	label.TextColor3 = Theme.Colors.TextPrimary
	label.TextSize = 12
	label.TextTransparency = 0.25
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.LayoutOrder = 1
	label.Parent = container

	-- Row 2: Full-Width Input Box Card
	local boxCard = Instance.new("Frame")
	boxCard.Name = "InputBoxCard"
	boxCard.Size = UDim2.new(1, 0, 0, Theme.Geometry.ButtonHeight or 26)
	boxCard.BackgroundColor3 = Theme.Colors.CardBg
	boxCard.BackgroundTransparency = Theme.Colors.CardTransIdle
	boxCard.BorderSizePixel = 0
	boxCard.LayoutOrder = 2
	boxCard.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Geometry.ButtonCorner or 6)
	corner.Parent = boxCard

	local stroke = Instance.new("UIStroke")
	stroke.Name = "InputStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.StrokeColor
	stroke.Thickness = Theme.Geometry.StrokeThickness or 1.0
	stroke.Transparency = Theme.Colors.StrokeTransIdle
	stroke.Parent = boxCard

	-- Inner TextBox
	local textBox = Instance.new("TextBox")
	textBox.Name = "TextBox"
	textBox.AnchorPoint = Vector2.new(0, 0.5)
	textBox.Position = UDim2.new(0, 8, 0.5, 0)
	textBox.Size = UDim2.new(1, -16, 1, 0)
	textBox.BackgroundTransparency = 1
	textBox.BorderSizePixel = 0
	textBox.ClearTextOnFocus = clearOnFocus
	textBox.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
	textBox.PlaceholderColor3 = Theme.Colors.TextDisabled or Color3.fromRGB(120, 130, 150)
	textBox.PlaceholderText = placeholder
	textBox.Text = self.Value
	textBox.TextColor3 = Theme.Colors.TextPrimary
	textBox.TextSize = 11
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.TextYAlignment = Enum.TextYAlignment.Center
	textBox.TextTruncate = Enum.TextTruncate.None
	textBox.Parent = boxCard

	-- Numeric / Character filter handling
	if self.Settings.Numeric then
		textBox:GetPropertyChangedSignal("Text"):Connect(function()
			local filtered = textBox.Text:gsub("[^%d%.%-]", "")
			if filtered ~= textBox.Text then
				textBox.Text = filtered
			end
		end)
	end

	-- Row 3: Subtitle / Description (Underneath Input Box)
	local descLabel = nil
	if hasDesc then
		descLabel = Instance.new("TextLabel")
		descLabel.Name = "InputDescription"
		descLabel.BackgroundTransparency = 1
		descLabel.BorderSizePixel = 0
		descLabel.AutomaticSize = Enum.AutomaticSize.Y
		descLabel.Size = UDim2.new(1, 0, 0, 0)
		descLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
		descLabel.RichText = true
		descLabel.Text = desc
		descLabel.TextColor3 = Theme.Colors.TextMuted
		descLabel.TextSize = 11
		descLabel.TextTransparency = 0.35
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.LayoutOrder = 3
		descLabel.Parent = container

		local descPad = Instance.new("UIPadding")
		descPad.PaddingLeft = UDim.new(0, 1)
		descPad.PaddingTop = UDim.new(0, 1)
		descPad.Parent = descLabel
	end

	-- State & Hover Animations
	local isFocused = false
	local isHovered = false

	local function updateVisuals()
		local ease = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		if isFocused then
			Theme.Tween(boxCard, ease, {
				BackgroundTransparency = Theme.Colors.CardTransHover or 0.88,
			})
			Theme.Tween(stroke, ease, {
				Color = Theme.Colors.SelectedText or Color3.fromRGB(160, 185, 255),
				Transparency = 0.40,
			})
		elseif isHovered then
			Theme.Tween(boxCard, ease, {
				BackgroundTransparency = Theme.Colors.CardTransHover or 0.88,
			})
			Theme.Tween(stroke, ease, {
				Color = Theme.Colors.StrokeColorHover or Color3.fromRGB(160, 190, 255),
				Transparency = Theme.Colors.StrokeTransHover or 0.70,
			})
		else
			Theme.Tween(boxCard, ease, {
				BackgroundTransparency = Theme.Colors.CardTransIdle or 0.94,
			})
			Theme.Tween(stroke, ease, {
				Color = Theme.Colors.StrokeColor,
				Transparency = Theme.Colors.StrokeTransIdle or 0.90,
			})
		end
	end

	textBox.Focused:Connect(function()
		isFocused = true
		updateVisuals()
	end)

	textBox.FocusLost:Connect(function(enterPressed)
		isFocused = false
		updateVisuals()
		self.Value = textBox.Text

		if library and library.Options and flag then
			library.Options[flag] = self.Value
		end

		if self.Settings.Callback then
			task.spawn(function()
				local ok, err = pcall(self.Settings.Callback, self.Value, enterPressed)
				if not ok then
					warn(string.format("[Shenky Hub Input Callback Error] %s: %s", name, tostring(err)))
				end
			end)
		end
	end)

	boxCard.MouseEnter:Connect(function()
		isHovered = true
		updateVisuals()
	end)

	boxCard.MouseLeave:Connect(function()
		isHovered = false
		updateVisuals()
	end)

	-- Store instances
	self.Instance = container
	self.BoxCard = boxCard
	self.TextBox = textBox
	self.NameLabel = label
	self.DescLabel = descLabel
	self.Stroke = stroke

	-- Register in library if provided
	if library and library.Options and flag then
		library.Options[flag] = self.Value
	end

	return self
end

-- OOP Methods
function Input:SetText(text, fireCallback)
	self.Value = tostring(text or "")
	if self.TextBox then
		self.TextBox.Text = self.Value
	end

	if self.Flag and getgenv and getgenv().ShenkyHub and getgenv().ShenkyHub.Options then
		getgenv().ShenkyHub.Options[self.Flag] = self.Value
	end

	if fireCallback and self.Settings.Callback then
		task.spawn(function()
			pcall(self.Settings.Callback, self.Value, false)
		end)
	end
end

function Input:GetText()
	return self.Value
end

function Input:UpdateText(text)
	self:SetText(text, true)
end

function Input:GetInput()
	return self:GetText()
end

function Input:Set(text)
	self:SetText(text, true)
end

function Input:UpdateName(name)
	self.Settings.Name = name
	if self.NameLabel then
		self.NameLabel.Text = tostring(name)
	end
end

function Input:UpdateDescription(desc)
	self.Settings.Description = desc
	if self.DescLabel then
		self.DescLabel.Text = tostring(desc)
		self.DescLabel.Visible = (desc ~= "" and desc ~= nil)
	end
end

function Input:SetVisibility(state)
	if self.Instance then
		self.Instance.Visible = state
	end
end

function Input:Destroy()
	if self.Instance then
		self.Instance:Destroy()
		self.Instance = nil
	end
end

return Input

end

-- Module: components/Sidebar
__modules["components/Sidebar"] = function()
-- components/Sidebar.luau
-- Standalone, Modular Sidebar Navigation System for Shenky Hub
-- Orchestrates the sidebar container, scrolling list, categories, and user profile card

local Players = game:GetService("Players")

local Category = __require("components/Category")
local Channel = __require("components/Channel")

local function maskText(str)
	str = tostring(str or "")
	local len = #str
	if len <= 1 then
		return "*"
	elseif len == 2 then
		return string.sub(str, 1, 1) .. "*"
	else
		return string.sub(str, 1, 2) .. string.rep("*", len - 2)
	end
end

local function maskUsername(u)
	u = tostring(u or "")
	if string.sub(u, 1, 1) == "@" then
		return "@" .. maskText(string.sub(u, 2))
	else
		return "@" .. maskText(u)
	end
end

local Sidebar = {}
Sidebar.__index = Sidebar

function Sidebar.new(window, hub, config)
	local self = setmetatable({}, Sidebar)
	self.Window = window
	self.Hub = hub
	self._hub = hub
	self.Settings = config or {}
	self.Categories = {}
	self.Channels = {}
	self.Tabs = self.Channels -- Alias for backward compatibility
	self.ActiveChannel = nil
	self.ActiveTab = nil
	self._FirstTab = nil
	self._currentCategory = nil
	self._originalProfile = nil
	self._anonymousMode = false

	local rawWin = (type(window) == "table" and (window._raw or window)) or window
	self._rawWindow = rawWin

	-- Locate base UI frames
	self._base = nil
	self._sidebarFrame = nil
	self._sidebarGroup = nil
	self._tabSwitchers = nil
	self._scrollingFrame = nil
	self._userInfo = nil
	self._defaultGhostSection = nil

	pcall(function()
		local base = rawWin.Base or (rawWin.base) or nil
		if not base and rawWin.GetBase then
			base = rawWin:GetBase()
		end
		self._base = base
		if base then
			self._sidebarFrame = base:FindFirstChild("Sidebar")
			if self._sidebarFrame then
				self._sidebarGroup = self._sidebarFrame:FindFirstChild("SidebarGroup")
				if self._sidebarGroup then
					self._tabSwitchers = self._sidebarGroup:FindFirstChild("TabSwitchers")
					self._userInfo = self._sidebarFrame:FindFirstChild("UserInfo") or self._sidebarGroup:FindFirstChild("UserInfo")
					if self._tabSwitchers then
						self._scrollingFrame = self._tabSwitchers:FindFirstChild("TabSwitchersScrollingFrame")
					end
				end
			end
		end
	end)

	-- Default un-categorized tab group
	local defaultRawGroup = rawWin:TabGroup()
	self._defaultRawGroup = defaultRawGroup

	pcall(function()
		if debug and debug.getupvalue then
			self._defaultGhostSection = debug.getupvalue(defaultRawGroup.Tab, 3)
		end
	end)

	local defaultCategory = Category.new(self, defaultRawGroup, { Title = "" })
	self._defaultCategory = defaultCategory
	self._currentCategory = defaultCategory

	pcall(function()
		self:_CaptureOriginalProfile()
	end)

	return self
end

function Sidebar:Category(groupCfg)
	local title = ""
	local initialCollapsed = false
	if type(groupCfg) == "string" then
		title = groupCfg
	elseif type(groupCfg) == "table" then
		title = groupCfg.Title or groupCfg.Name or groupCfg.Text or ""
		if groupCfg.Collapsed == true or groupCfg.Expanded == false then
			initialCollapsed = true
		end
	end

	-- Reuse existing category if already created with this title
	if title ~= "" then
		local existing = self:GetCategory(title)
		if existing then
			self._currentCategory = existing
			return existing
		end
	end

	-- Clean up default empty ghost section if this is the first custom category
	if self._defaultGhostSection and self._defaultGhostSection.Parent then
		pcall(function()
			self._defaultGhostSection.Parent.Visible = false
			self._defaultGhostSection.Parent.Size = UDim2.new(0, 0, 0, 0)
		end)
	end

	local rawGroup = self._rawWindow:TabGroup()
	local cat = Category.new(self, rawGroup, {
		Title = title,
		Collapsed = initialCollapsed,
	})

	table.insert(self.Categories, cat)
	self._currentCategory = cat
	return cat
end

function Sidebar:CreateCategory(groupCfg)
	return self:Category(groupCfg)
end

function Sidebar:GetCategory(title)
	for _, c in ipairs(self.Categories) do
		if c.Title == title then
			return c
		end
	end
	return nil
end

function Sidebar:GetCategories()
	return self.Categories
end

function Sidebar:Channel(config)
	config = config or {}
	local targetCat = self._currentCategory
	if not targetCat or targetCat.Title == "" then
		targetCat = self:GetCategory("Main") or self:Category("Main")
	end
	if not config.Category and targetCat and targetCat.Title ~= "" then
		config.Category = targetCat.Title
	end
	return targetCat:Channel(config)
end

function Sidebar:Tab(config)
	return self:Channel(config)
end

function Sidebar:CreateChannel(config)
	return self:Channel(config)
end

function Sidebar:CreateTab(config)
	return self:Channel(config)
end

function Sidebar:SelectChannel(channelItem)
	if type(channelItem) == "table" and type(channelItem.Select) == "function" then
		pcall(function()
			channelItem:Select()
		end)
	end
end

function Sidebar:SelectTab(tabWrapper)
	return self:SelectChannel(tabWrapper)
end

function Sidebar:_CaptureOriginalProfile()
	if self._originalProfile then return end
	local info = self._userInfo
	if not info and self._sidebarFrame then
		info = self._sidebarFrame:FindFirstChild("UserInfo") or (self._sidebarGroup and self._sidebarGroup:FindFirstChild("UserInfo"))
		self._userInfo = info
	end
	local lp = Players.LocalPlayer
	local origName = maskText((lp and lp.DisplayName) or "Player")
	local origUser = maskUsername((lp and lp.Name) or "Player")
	local origImg = (lp and ("rbxthumb://type=AvatarBust&id=" .. tostring(lp.UserId) .. "&w=48&h=48")) or ""

	if info then
		local infoGroup = info:FindFirstChild("InformationGroup")
		if infoGroup then
			local headshot = infoGroup:FindFirstChild("Headshot")
			if headshot and headshot:IsA("ImageLabel") and headshot.Image ~= "" then
				origImg = headshot.Image
			end
			local userFrame = infoGroup:FindFirstChild("UserAndDisplayFrame")
			if userFrame then
				local dn = userFrame:FindFirstChild("DisplayName")
				if dn and dn:IsA("TextLabel") and dn.Text ~= "" then
					if not string.find(dn.Text, "*", 1, true) then
						origName = maskText(dn.Text)
					else
						origName = dn.Text
					end
					dn.Text = origName
				end
				local un = userFrame:FindFirstChild("Username")
				if un and un:IsA("TextLabel") and un.Text ~= "" then
					if not string.find(un.Text, "*", 1, true) then
						origUser = maskUsername(un.Text)
					else
						origUser = un.Text
					end
					un.Text = origUser
				end
			end
		end
	end

	self._originalProfile = {
		DisplayName = origName,
		Username = origUser,
		Image = origImg,
	}
end

function Sidebar:SetUserProfile(profileCfg)
	if not profileCfg then return end
	if profileCfg.State ~= nil and self._rawWindow and self._rawWindow.SetUserInfoState then
		pcall(function()
			self._rawWindow:SetUserInfoState(profileCfg.State)
		end)
	end

	self:_CaptureOriginalProfile()
	if profileCfg.DisplayName and self._originalProfile then
		self._originalProfile.DisplayName = profileCfg.DisplayName
	end
	if profileCfg.Username and self._originalProfile then
		self._originalProfile.Username = profileCfg.Username
	end
	if profileCfg.Image and self._originalProfile then
		self._originalProfile.Image = profileCfg.Image
	end

	if not self._anonymousMode and self._userInfo then
		local infoGroup = self._userInfo:FindFirstChild("InformationGroup")
		if infoGroup then
			if profileCfg.Image then
				local headshot = infoGroup:FindFirstChild("Headshot")
				if headshot and headshot:IsA("ImageLabel") then headshot.Image = profileCfg.Image end
			end
			local userFrame = infoGroup:FindFirstChild("UserAndDisplayFrame")
			if userFrame then
				if profileCfg.DisplayName then
					local dn = userFrame:FindFirstChild("DisplayName")
					if dn and dn:IsA("TextLabel") then dn.Text = profileCfg.DisplayName end
				end
				if profileCfg.Username then
					local un = userFrame:FindFirstChild("Username")
					if un and un:IsA("TextLabel") then un.Text = profileCfg.Username end
				end
			end
		end
	end
end

function Sidebar:SetAnonymousMode(enabled)
	self._anonymousMode = enabled == true
	self:_CaptureOriginalProfile()

	local info = self._userInfo
	if not info and self._sidebarFrame then
		info = self._sidebarFrame:FindFirstChild("UserInfo") or (self._sidebarGroup and self._sidebarGroup:FindFirstChild("UserInfo"))
		self._userInfo = info
	end
	if not info then return end

	local infoGroup = info:FindFirstChild("InformationGroup")
	if not infoGroup then return end
	local headshot = infoGroup:FindFirstChild("Headshot")
	local userFrame = infoGroup:FindFirstChild("UserAndDisplayFrame")
	local dn = userFrame and userFrame:FindFirstChild("DisplayName")
	local un = userFrame and userFrame:FindFirstChild("Username")

	if self._anonymousMode then
		local hubObj = self.Hub or self._hub
		local logoAsset = (hubObj and hubObj.LogoAsset)
			or (typeof(getgenv) == "function" and typeof(getgenv().__SHENKY_LOGO_ASSET) == "string" and getgenv().__SHENKY_LOGO_ASSET)
			or "rbxassetid://10734886300"
		if headshot and headshot:IsA("ImageLabel") and logoAsset then
			headshot.Image = logoAsset
		end
		if dn and dn:IsA("TextLabel") then
			dn.Text = "Shenky Hub"
		end
		if un and un:IsA("TextLabel") then
			un.Text = "@shenkyhub"
		end
	else
		local orig = self._originalProfile
		if orig then
			if headshot and headshot:IsA("ImageLabel") and orig.Image then
				headshot.Image = orig.Image
			end
			if dn and dn:IsA("TextLabel") and orig.DisplayName then
				dn.Text = orig.DisplayName
			end
			if un and un:IsA("TextLabel") and orig.Username then
				un.Text = orig.Username
			end
		end
	end
end

function Sidebar:GetAnonymousMode()
	return self._anonymousMode == true
end

return Sidebar

end

-- Module: components/Category
__modules["components/Category"] = function()
-- components/Category.luau
-- Standalone, Modular Accordion Category Group Component for Shenky Hub
-- Manages collapsible channel groups, Lucide rotating chevrons, and child channel lifecycles

local TweenService = game:GetService("TweenService")

local Theme = __require("components/Theme")
local icons = __require("assets/icons")
local Wrapper = __require("core/wrapper")
local Channel = __require("components/Channel")

local resolveIcon = icons.Resolve
local wrapTab = Wrapper.wrapTab



local Category = {}
Category.__index = Category

function Category.new(sidebar, rawGroup, config)
	local self = setmetatable({}, Category)
	self.Sidebar = sidebar
	self.RawGroup = rawGroup
	self.Channels = {}
	self.Tabs = self.Channels -- Alias for backward compatibility

	-- Resolve title & initial collapsed state
	local title = "Category"
	local initialCollapsed = false
	if type(config) == "string" then
		title = config
	elseif type(config) == "table" then
		title = config.Title or config.Name or config.Text or "Category"
		if config.Collapsed == true or config.Expanded == false then
			initialCollapsed = true
		end
	end

	self.Title = title
	self.IsExpanded = not initialCollapsed
	self._headerButton = nil
	self._chevron = nil
	self._label = nil
	self._secSwitchersRef = nil

	-- Locate the SectionTabSwitchers container for this group
	self:_FindContainer()

	-- Build accordion header
	self:_BuildHeader()

	return self
end

function Category:_FindContainer()
	local sec = nil
	if debug and debug.getupvalue and self.RawGroup and self.RawGroup.Tab then
		pcall(function()
			sec = debug.getupvalue(self.RawGroup.Tab, 3)
		end)
	end
	if not sec and self.Sidebar and self.Sidebar._scrollingFrame then
		local sf = self.Sidebar._scrollingFrame
		local children = sf:GetChildren()
		for i = #children, 1, -1 do
			local ch = children[i]
			if ch.Name == "Section" and ch:FindFirstChild("SectionTabSwitchers") then
				sec = ch.SectionTabSwitchers
				break
			end
		end
	end
	self._secSwitchersRef = sec
end

function Category:_BuildHeader()
	if not self.Title or self.Title == "" then return end
	if not self._secSwitchersRef then
		self:_FindContainer()
	end
	local secSwitchers = self._secSwitchersRef
	if not secSwitchers then return end
	if secSwitchers:FindFirstChild("CategoryHeader") then
		self._headerButton = secSwitchers.CategoryHeader
		self._label = self._headerButton:FindFirstChild("CategoryLabel")
		self._chevron = self._headerButton:FindFirstChild("ChevronIcon")
		return
	end

	-- Header Button
	local btn = Instance.new("TextButton")
	btn.Name = "CategoryHeader"
	btn.Size = UDim2.new(1, 0, 0, 22)
	btn.Position = UDim2.new(0, 0, 0, 0)
	btn.AnchorPoint = Vector2.new(0, 0)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.LayoutOrder = 0

	local lbl = Instance.new("TextLabel")
	lbl.Name = "CategoryLabel"
	lbl.Size = UDim2.new(1, -22, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Text = tostring(self.Title)
	lbl.TextSize = 11
	lbl.FontFace = Theme.GetFont(Enum.FontWeight.SemiBold)
	lbl.TextColor3 = Color3.fromRGB(130, 138, 160)
	lbl.TextTransparency = 0.25
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Parent = btn

	local chev = Instance.new("ImageLabel")
	chev.Name = "ChevronIcon"
	chev.AnchorPoint = Vector2.new(1, 0.5)
	chev.Position = UDim2.new(1, 0, 0.5, 0)
	chev.Size = UDim2.fromOffset(12, 12)
	chev.BackgroundTransparency = 1
	chev.BorderSizePixel = 0
	chev.Image = "rbxassetid://10709790948" -- Lucide chevron-down
	chev.ImageColor3 = Color3.fromRGB(140, 148, 168)
	chev.ImageTransparency = 0.4
	chev.Rotation = self.IsExpanded and 0 or -90
	chev.Parent = btn

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 4)
	pad.PaddingTop = UDim.new(0, 0)
	pad.PaddingBottom = UDim.new(0, 0)
	pad.Parent = btn

	-- Hover Micro-interactions
	btn.MouseEnter:Connect(function()
		TweenService:Create(lbl, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			TextColor3 = Color3.fromRGB(220, 230, 255),
			TextTransparency = 0,
		}):Play()
		TweenService:Create(chev, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			ImageColor3 = Color3.fromRGB(200, 215, 255),
			ImageTransparency = 0.1,
		}):Play()
	end)

	btn.MouseLeave:Connect(function()
		TweenService:Create(lbl, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			TextColor3 = Color3.fromRGB(130, 138, 160),
			TextTransparency = 0.25,
		}):Play()
		TweenService:Create(chev, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			ImageColor3 = Color3.fromRGB(140, 148, 168),
			ImageTransparency = 0.4,
		}):Play()
	end)

	-- Click to toggle accordion
	btn.MouseButton1Click:Connect(function()
		self:Toggle(true)
	end)

	btn.Parent = secSwitchers
	self._headerButton = btn
	self._label = lbl
	self._chevron = chev

	self:_UpdateVisuals(false)
end

function Category:_UpdateVisuals(animate)
	local targetRot = self.IsExpanded and 0 or -90
	if self._chevron then
		if animate then
			TweenService:Create(self._chevron, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Rotation = targetRot,
			}):Play()
		else
			self._chevron.Rotation = targetRot
		end
	end

	-- Update visibility of child channel buttons
	if self._secSwitchersRef then
		for _, child in ipairs(self._secSwitchersRef:GetChildren()) do
			if child:IsA("TextButton") and child.Name == "TabSwitcher" then
				child.Visible = self.IsExpanded
			end
		end
	end
end

function Category:SetExpanded(expanded, animate)
	self.IsExpanded = (expanded == true)
	self:_UpdateVisuals(animate ~= false)
end

function Category:Toggle(animate)
	self.IsExpanded = not self.IsExpanded
	self:_UpdateVisuals(animate ~= false)
end

function Category:Channel(config)
	config = config or {}
	local channelTitle = tostring(config.Title or config.Name or "Channel")
	local channelCategory = config.Category or self.Title
	local channelIcon = resolveIcon(config.Icon or config.Image)

	local rawTab = self.RawGroup:Tab({
		Name = channelTitle,
		Image = channelIcon,
		Category = channelCategory,
	})

	-- Ensure header is attached
	self:_BuildHeader()

	-- Locate the created TabSwitcher button
	local switcherBtn = nil
	if self._secSwitchersRef then
		for _, child in ipairs(self._secSwitchersRef:GetChildren()) do
			if child:IsA("TextButton") and child.Name == "TabSwitcher" then
				local nameLbl = child:FindFirstChild("TabSwitcherName", true)
				if nameLbl and nameLbl.Text == channelTitle then
					switcherBtn = child
				end
			end
		end
		if not switcherBtn then
			local chs = self._secSwitchersRef:GetChildren()
			for i = #chs, 1, -1 do
				if chs[i]:IsA("TextButton") and chs[i].Name == "TabSwitcher" then
					switcherBtn = chs[i]
					break
				end
			end
		end
	end

	-- Enforce visibility based on current accordion state
	if not self.IsExpanded and switcherBtn then
		switcherBtn.Visible = false
	end

	local hub = self.Sidebar and self.Sidebar.Hub
	local wrappedTab = wrapTab(hub, rawTab, channelTitle)
	local channelItem = Channel.new(self, rawTab, wrappedTab, config, switcherBtn)

	table.insert(self.Channels, channelItem)
	if self.Sidebar then
		table.insert(self.Sidebar.Channels, channelItem)
		table.insert(self.Sidebar.Tabs, channelItem)

		-- Select the very first channel/tab in the window automatically
		if not self.Sidebar._FirstTab then
			self.Sidebar._FirstTab = wrappedTab
			pcall(function()
				rawTab:Select()
			end)
		end
	end

	return wrappedTab
end

function Category:Tab(config)
	return self:Channel(config)
end

function Category:CreateChannel(config)
	return self:Channel(config)
end

function Category:CreateTab(config)
	return self:Channel(config)
end

function Category:GetChannels()
	return self.Channels
end

function Category:GetTabs()
	return self.Channels
end

function Category:FindChannel(name)
	for _, ch in ipairs(self.Channels) do
		if ch.Title == name then
			return ch
		end
	end
	return nil
end

function Category:FindTab(name)
	return self:FindChannel(name)
end

return Category

end

-- Module: assets/icons
__modules["assets/icons"] = function()
-- assets/icons.luau
-- Complete Lucide Icons Database (847 Unique Roblox Lucide Icons)

-- Database Lengkap Lucide Icons (840+ Icon Resmi Roblox Lucide)
local ICON_MAP = {
	accessibility = 10709751939,
	activity = 10709752035,
	["air-vent"] = 10709752131,
	airplay = 10709752254,
	["alarm-check"] = 10709752405,
	["alarm-clock"] = 10709752630,
	["alarm-clock-off"] = 10709752508,
	["alarm-minus"] = 10709752732,
	["alarm-plus"] = 10709752825,
	album = 10709752906,
	["alert-circle"] = 10709752996,
	["alert-octagon"] = 10709753064,
	["alert-triangle"] = 10709753149,
	["align-center"] = 10709753570,
	["align-center-horizontal"] = 10709753272,
	["align-center-vertical"] = 10709753421,
	["align-end-horizontal"] = 10709753692,
	["align-end-vertical"] = 10709753808,
	["align-horizonal-distribute-center"] = 8997381028,
	["align-horizonal-distribute-end"] = 8997381144,
	["align-horizonal-distribute-start"] = 8997381290,
	["align-horizontal-distribute-center"] = 10747779791,
	["align-horizontal-distribute-end"] = 10747784534,
	["align-horizontal-distribute-start"] = 10709754118,
	["align-horizontal-justify-center"] = 10709754204,
	["align-horizontal-justify-end"] = 10709754317,
	["align-horizontal-justify-start"] = 10709754436,
	["align-horizontal-space-around"] = 10709754590,
	["align-horizontal-space-between"] = 10709754749,
	["align-justify"] = 10709759610,
	["align-left"] = 10709759764,
	["align-right"] = 10709759895,
	["align-start-horizontal"] = 10709760051,
	["align-start-vertical"] = 10709760244,
	["align-vertical-distribute-center"] = 10709760351,
	["align-vertical-distribute-end"] = 10709760434,
	["align-vertical-distribute-start"] = 10709760612,
	["align-vertical-justify-center"] = 10709760814,
	["align-vertical-justify-end"] = 10709761003,
	["align-vertical-justify-start"] = 10709761176,
	["align-vertical-space-around"] = 10709761324,
	["align-vertical-space-between"] = 10709761434,
	anchor = 10709761530,
	angry = 10709761629,
	annoyed = 10709761722,
	aperture = 10709761813,
	apple = 10709761889,
	archive = 10709762233,
	["archive-restore"] = 10709762058,
	armchair = 10709762327,
	["arrow-big-down"] = 10747796644,
	["arrow-big-left"] = 10709762574,
	["arrow-big-right"] = 10709762727,
	["arrow-big-up"] = 10709762879,
	["arrow-down"] = 10709767827,
	["arrow-down-circle"] = 10709763034,
	["arrow-down-left"] = 10709767656,
	["arrow-down-right"] = 10709767750,
	["arrow-left"] = 10709768114,
	["arrow-left-circle"] = 10709767936,
	["arrow-left-right"] = 10709768019,
	["arrow-right"] = 10709768347,
	["arrow-right-circle"] = 10709768226,
	["arrow-up"] = 10709768939,
	["arrow-up-circle"] = 10709768432,
	["arrow-up-down"] = 10709768538,
	["arrow-up-left"] = 10709768661,
	["arrow-up-right"] = 10709768787,
	asterisk = 10709769095,
	["at-sign"] = 10709769286,
	award = 10709769406,
	axe = 10709753149,
	["axis-3d"] = 10709769598,
	baby = 10709769732,
	backpack = 10709789947,
	bag = 10709789947,
	["baggage-claim"] = 10709769935,
	banana = 10709770005,
	banknote = 10709770178,
	["bar-chart"] = 10709773755,
	["bar-chart-2"] = 10709770317,
	["bar-chart-3"] = 10709770431,
	["bar-chart-4"] = 10709770560,
	["bar-chart-horizontal"] = 10709773669,
	barcode = 10747360675,
	baseline = 10709773863,
	bath = 10709773963,
	battery = 10709774640,
	["battery-charging"] = 10709774068,
	["battery-full"] = 10709774206,
	["battery-low"] = 10709774370,
	["battery-medium"] = 10709774513,
	beaker = 10709774756,
	bed = 10709775036,
	["bed-double"] = 10709774864,
	["bed-single"] = 10709774968,
	beer = 10709775167,
	bell = 10709775704,
	["bell-minus"] = 10709775241,
	["bell-off"] = 10709775320,
	["bell-plus"] = 10709775448,
	["bell-ring"] = 10709775560,
	bike = 10709775894,
	binary = 10709776050,
	bitcoin = 10709776126,
	bluetooth = 10709776655,
	["bluetooth-connected"] = 10709776240,
	["bluetooth-off"] = 10709776344,
	["bluetooth-searching"] = 10709776501,
	bold = 10747813908,
	bomb = 10709781460,
	bone = 10709781605,
	book = 10709781824,
	["book-open"] = 10709781717,
	bookmark = 10709782154,
	["bookmark-minus"] = 10709781919,
	["bookmark-plus"] = 10709782044,
	bot = 10709782230,
	box = 10709782497,
	["box-select"] = 10709782342,
	boxes = 10709782582,
	briefcase = 10709782662,
	brush = 10709782758,
	bug = 10709782845,
	building = 10709783051,
	["building-2"] = 10709782939,
	bus = 10709783137,
	cake = 10709783217,
	calculator = 10709783311,
	calendar = 10709789505,
	["calendar-check"] = 10709783474,
	["calendar-check-2"] = 10709783392,
	["calendar-clock"] = 10709783577,
	["calendar-days"] = 10709783673,
	["calendar-heart"] = 10709783835,
	["calendar-minus"] = 10709783959,
	["calendar-off"] = 10709788784,
	["calendar-plus"] = 10709788937,
	["calendar-range"] = 10709789053,
	["calendar-search"] = 10709789200,
	["calendar-x"] = 10709789407,
	["calendar-x-2"] = 10709789329,
	camera = 10709789686,
	["camera-off"] = 10747822677,
	car = 10709789810,
	carrot = 10709789960,
	cart = 10734952273,
	cast = 10709790097,
	cd = 7734110220,
	charge = 10709790202,
	check = 10709790644,
	["check-circle"] = 10709790387,
	["check-circle-2"] = 10709790298,
	["check-square"] = 10709790537,
	["chef-hat"] = 10709790757,
	cherry = 10709790875,
	["chevron-down"] = 10709790948,
	["chevron-first"] = 10709791015,
	["chevron-last"] = 10709791130,
	["chevron-left"] = 10709791281,
	["chevron-right"] = 10709791437,
	["chevron-up"] = 10709791523,
	["chevrons-down"] = 10709796864,
	["chevrons-down-up"] = 10709791632,
	["chevrons-left"] = 10709797151,
	["chevrons-left-right"] = 10709797006,
	["chevrons-right"] = 10709797382,
	["chevrons-right-left"] = 10709797274,
	["chevrons-up"] = 10709797622,
	["chevrons-up-down"] = 10709797508,
	chrome = 10709797725,
	circle = 10709798174,
	["circle-dot"] = 10709797837,
	["circle-ellipsis"] = 10709797985,
	["circle-slashed"] = 10709798100,
	citrus = 10709798276,
	clapperboard = 10709798350,
	clipboard = 10709799288,
	["clipboard-check"] = 10709798443,
	["clipboard-copy"] = 10709798574,
	["clipboard-edit"] = 10709798682,
	["clipboard-list"] = 10709798792,
	["clipboard-signature"] = 10709798890,
	["clipboard-type"] = 10709798999,
	["clipboard-x"] = 10709799124,
	clock = 10709805144,
	["clock-1"] = 10709799535,
	["clock-10"] = 10709799718,
	["clock-11"] = 10709799818,
	["clock-12"] = 10709799962,
	["clock-2"] = 10709803876,
	["clock-3"] = 10709803989,
	["clock-4"] = 10709804164,
	["clock-5"] = 10709804291,
	["clock-6"] = 10709804435,
	["clock-7"] = 10709804599,
	["clock-8"] = 10709804784,
	["clock-9"] = 10709804996,
	cloud = 10709806740,
	["cloud-cog"] = 10709805262,
	["cloud-drizzle"] = 10709805371,
	["cloud-fog"] = 10709805477,
	["cloud-hail"] = 10709805596,
	["cloud-lightning"] = 10709805727,
	["cloud-moon"] = 10709805942,
	["cloud-moon-rain"] = 10709805838,
	["cloud-off"] = 10709806060,
	["cloud-rain"] = 10709806277,
	["cloud-rain-wind"] = 10709806166,
	["cloud-snow"] = 10709806374,
	["cloud-sun"] = 10709806631,
	["cloud-sun-rain"] = 10709806475,
	cloudy = 10709806859,
	clover = 10709806995,
	code = 10709810463,
	["code-2"] = 10709807111,
	codepen = 10709810534,
	codesandbox = 10709810676,
	coffee = 10709810814,
	cog = 10709810948,
	coins = 10709811110,
	columns = 10709811261,
	combat = 10734975692,
	command = 10709811365,
	compass = 10709811445,
	component = 10709811595,
	["concierge-bell"] = 10709811706,
	connection = 10747361219,
	contact = 10709811834,
	contrast = 10709811939,
	cookie = 10709812067,
	copy = 10709812159,
	copyleft = 10709812251,
	copyright = 10709812311,
	["corner-down-left"] = 10709812396,
	["corner-down-right"] = 10709812485,
	["corner-left-down"] = 10709812632,
	["corner-left-up"] = 10709812784,
	["corner-right-down"] = 10709812939,
	["corner-right-up"] = 10709813094,
	["corner-up-left"] = 10709813185,
	["corner-up-right"] = 10709813281,
	cpu = 10709813383,
	croissant = 10709818125,
	crop = 10709818245,
	cross = 10709818399,
	crosshair = 10709818534,
	crown = 10709818626,
	["cup-soda"] = 10709818763,
	["curly-braces"] = 10709818847,
	currency = 10709818931,
	database = 10709818996,
	delete = 10709819059,
	diamond = 10709819149,
	["dice-1"] = 10709819266,
	["dice-2"] = 10709819361,
	["dice-3"] = 10709819508,
	["dice-4"] = 10709819670,
	["dice-5"] = 10709819801,
	["dice-6"] = 10709819896,
	dices = 10723343321,
	diff = 10723343416,
	disc = 10723343537,
	divide = 10723343805,
	["divide-circle"] = 10723343636,
	["divide-square"] = 10723343737,
	["dollar-sign"] = 10723343958,
	download = 10723344270,
	["download-cloud"] = 10723344088,
	dribbble = 7733770843,
	droplet = 10723344432,
	droplets = 10734883356,
	drumstick = 10723344737,
	edit = 10734883598,
	["edit-2"] = 10723344885,
	["edit-3"] = 10723345088,
	egg = 10723345518,
	["egg-fried"] = 10723345347,
	electricity = 10723345749,
	["electricity-off"] = 10723345643,
	equal = 10723345990,
	["equal-not"] = 10723345866,
	eraser = 10723346158,
	euro = 10723346372,
	expand = 10723346553,
	["external-link"] = 10723346684,
	eye = 10723346959,
	["eye-off"] = 10723346871,
	factory = 10723347051,
	fan = 10723354359,
	farm = 10709753149,
	["fast-forward"] = 10723354521,
	feather = 10723354671,
	figma = 10723354801,
	file = 10723374641,
	["file-archive"] = 10723354921,
	["file-audio"] = 10723355148,
	["file-audio-2"] = 10723355026,
	["file-axis-3d"] = 10723355272,
	["file-badge"] = 10723355622,
	["file-badge-2"] = 10723355451,
	["file-bar-chart"] = 10723355887,
	["file-bar-chart-2"] = 10723355746,
	["file-box"] = 10723355989,
	["file-check"] = 10723356210,
	["file-check-2"] = 10723356100,
	["file-clock"] = 10723356329,
	["file-code"] = 10723356507,
	["file-cog"] = 10723356830,
	["file-cog-2"] = 10723356676,
	["file-diff"] = 10723357039,
	["file-digit"] = 10723357151,
	["file-down"] = 10723357322,
	["file-edit"] = 10723357495,
	["file-heart"] = 10723357637,
	["file-image"] = 10723357790,
	["file-input"] = 10723357933,
	["file-json"] = 10723364435,
	["file-json-2"] = 10723364361,
	["file-key"] = 10723364605,
	["file-key-2"] = 10723364515,
	["file-line-chart"] = 10723364725,
	["file-lock"] = 10723364957,
	["file-lock-2"] = 10723364861,
	["file-minus"] = 10723365254,
	["file-minus-2"] = 10723365086,
	["file-output"] = 10723365457,
	["file-pie-chart"] = 10723365598,
	["file-plus"] = 10723365877,
	["file-plus-2"] = 10723365766,
	["file-question"] = 10723365987,
	["file-scan"] = 10723366167,
	["file-search"] = 10723366550,
	["file-search-2"] = 10723366340,
	["file-signature"] = 10723366741,
	["file-spreadsheet"] = 10723366962,
	["file-symlink"] = 10723367098,
	["file-terminal"] = 10723367244,
	["file-text"] = 10723367380,
	["file-type"] = 10723367606,
	["file-type-2"] = 10723367509,
	["file-up"] = 10723367734,
	["file-video"] = 10723373884,
	["file-video-2"] = 10723367834,
	["file-volume"] = 10723374172,
	["file-volume-2"] = 10723374030,
	["file-warning"] = 10723374276,
	["file-x"] = 10723374544,
	["file-x-2"] = 10723374378,
	files = 10723374759,
	film = 10723374981,
	filter = 10723375128,
	fingerprint = 10723375250,
	fish = 10723396402,
	fishing = 10723396402,
	flag = 10723375890,
	["flag-off"] = 10723375443,
	["flag-triangle-left"] = 10723375608,
	["flag-triangle-right"] = 10723375727,
	flame = 10723376114,
	flashlight = 10723376471,
	["flashlight-off"] = 10723376365,
	["flask-conical"] = 10734883986,
	["flask-round"] = 10723376614,
	["flip-horizontal"] = 10723376884,
	["flip-horizontal-2"] = 10723376745,
	["flip-vertical"] = 10723377138,
	["flip-vertical-2"] = 10723377026,
	flower = 10747830374,
	["flower-2"] = 10723377305,
	focus = 10723377537,
	folder = 10723387563,
	["folder-archive"] = 10723384478,
	["folder-check"] = 10723384605,
	["folder-clock"] = 10723384731,
	["folder-closed"] = 10723384893,
	["folder-cog"] = 10723385213,
	["folder-cog-2"] = 10723385036,
	["folder-down"] = 10723385338,
	["folder-edit"] = 10723385445,
	["folder-heart"] = 10723385545,
	["folder-input"] = 10723385721,
	["folder-key"] = 10723385848,
	["folder-lock"] = 10723386005,
	["folder-minus"] = 10723386127,
	["folder-open"] = 10723386277,
	["folder-output"] = 10723386386,
	["folder-plus"] = 10723386531,
	["folder-search"] = 10723386787,
	["folder-search-2"] = 10723386674,
	["folder-symlink"] = 10723386930,
	["folder-tree"] = 10723387085,
	["folder-up"] = 10723387265,
	["folder-x"] = 10723387448,
	folders = 10723387721,
	["form-input"] = 10723387841,
	forward = 10723388016,
	frame = 10723394389,
	framer = 10723394565,
	frown = 10723394681,
	fuel = 10723394846,
	["function-square"] = 10723395041,
	gamepad = 10723395457,
	["gamepad-2"] = 10723395215,
	gauge = 10723395708,
	gavel = 10723395896,
	gem = 10723396000,
	ghost = 10723396107,
	gift = 10723396402,
	["gift-card"] = 10723396225,
	["git-branch"] = 10723396676,
	["git-branch-plus"] = 10723396542,
	["git-commit"] = 10723396812,
	["git-compare"] = 10723396954,
	["git-fork"] = 10723397049,
	["git-merge"] = 10723397165,
	["git-pull-request"] = 10723397431,
	["git-pull-request-closed"] = 10723397268,
	["git-pull-request-draft"] = 10734884302,
	github = 7733954058,
	gitlab = 7733954246,
	glass = 10723397788,
	["glass-2"] = 10723397529,
	["glass-water"] = 10723397678,
	glasses = 10723397895,
	globe = 10723404337,
	["globe-2"] = 10723398002,
	grab = 10723404472,
	["graduation-cap"] = 10723404691,
	grape = 10723404822,
	grid = 10723404936,
	["grip-horizontal"] = 10723405089,
	["grip-vertical"] = 10723405236,
	hammer = 10723405360,
	hand = 10723405649,
	["hand-metal"] = 10723405508,
	["hard-drive"] = 10723405749,
	["hard-hat"] = 10723405859,
	hash = 10723405975,
	haze = 10723406078,
	headphones = 10723406165,
	heart = 10723406885,
	["heart-crack"] = 10723406299,
	["heart-handshake"] = 10723406480,
	["heart-off"] = 10723406662,
	["heart-pulse"] = 10723406795,
	["help-circle"] = 10723406988,
	hexagon = 10723407092,
	highlighter = 10723407192,
	history = 10723407335,
	home = 10723407389,
	hourglass = 10723407498,
	["ice-cream"] = 10723414308,
	image = 10723415040,
	["image-minus"] = 10723414487,
	["image-off"] = 10723414677,
	["image-plus"] = 10723414827,
	import = 10723415205,
	inbox = 10723415335,
	indent = 10723415494,
	["indian-rupee"] = 10723415642,
	infinity = 10723415766,
	info = 10723415903,
	inspect = 10723416057,
	inventory = 10709789947,
	italic = 10723416195,
	["japanese-yen"] = 10723416363,
	["jersey-pound"] = 7733965029,
	joystick = 10723416527,
	key = 10723416652,
	keyboard = 10723416765,
	lamp = 10723417513,
	["lamp-ceiling"] = 10723416922,
	["lamp-desk"] = 10723417016,
	["lamp-floor"] = 10723417131,
	["lamp-wall-down"] = 10723417240,
	["lamp-wall-up"] = 10723417356,
	landmark = 10723417608,
	languages = 10723417703,
	laptop = 10723423881,
	["laptop-2"] = 10723417797,
	lasso = 10723424235,
	["lasso-select"] = 10723424058,
	laugh = 10723424372,
	layers = 10723424505,
	layout = 10723425376,
	["layout-dashboard"] = 10723424646,
	["layout-grid"] = 10723424838,
	["layout-list"] = 10723424963,
	["layout-template"] = 10723425187,
	leaderboard = 10734983390,
	leaf = 10723425539,
	library = 10723425615,
	["life-buoy"] = 10723425685,
	lightbulb = 10723425852,
	["lightbulb-off"] = 10723425762,
	lightning = 10747384394,
	["line-chart"] = 10723426393,
	link = 10723426722,
	["link-2"] = 10723426595,
	["link-2-off"] = 10723426513,
	list = 10723433811,
	["list-checks"] = 10734884548,
	["list-end"] = 10723426886,
	["list-minus"] = 10723426986,
	["list-music"] = 10723427081,
	["list-ordered"] = 10723427199,
	["list-plus"] = 10723427334,
	["list-start"] = 10723427494,
	["list-video"] = 10723427619,
	["list-x"] = 10723433655,
	loader = 10723434070,
	["loader-2"] = 10723433935,
	locate = 10723434557,
	["locate-fixed"] = 10723434236,
	["locate-off"] = 10723434379,
	lock = 10723434711,
	["log-in"] = 10723434830,
	["log-out"] = 10723434906,
	luggage = 10723434993,
	magnet = 10723435069,
	mail = 10734885430,
	["mail-check"] = 10723435182,
	["mail-minus"] = 10723435261,
	["mail-open"] = 10723435342,
	["mail-plus"] = 10723435443,
	["mail-question"] = 10723435515,
	["mail-search"] = 10734884739,
	["mail-warning"] = 10734885015,
	["mail-x"] = 10734885247,
	mails = 10734885614,
	map = 10734886202,
	["map-pin"] = 10734886004,
	["map-pin-off"] = 10734885803,
	maximize = 10734886735,
	["maximize-2"] = 10734886496,
	medal = 10734887072,
	megaphone = 10734887454,
	["megaphone-off"] = 10734887311,
	meh = 10734887603,
	menu = 10734887784,
	["message-circle"] = 10734888000,
	["message-square"] = 10734888228,
	mic = 10734888864,
	["mic-2"] = 10734888430,
	["mic-off"] = 10734888646,
	microscope = 10734889106,
	microwave = 10734895076,
	milestone = 10734895310,
	minimize = 10734895698,
	["minimize-2"] = 10734895530,
	minus = 10734896206,
	["minus-circle"] = 10734895856,
	["minus-square"] = 10734896029,
	monitor = 10734896881,
	["monitor-off"] = 10734896360,
	["monitor-speaker"] = 10734896512,
	moon = 10734897102,
	["more-horizontal"] = 10734897250,
	["more-vertical"] = 10734897387,
	mountain = 10734897956,
	["mountain-snow"] = 10734897665,
	mouse = 10734898592,
	["mouse-pointer"] = 10734898476,
	["mouse-pointer-2"] = 10734898194,
	["mouse-pointer-click"] = 10734898355,
	move = 10734900011,
	["move-3d"] = 10734898756,
	["move-diagonal"] = 10734899164,
	["move-diagonal-2"] = 10734898934,
	["move-horizontal"] = 10734899414,
	["move-vertical"] = 10734899821,
	music = 10734905958,
	["music-2"] = 10734900215,
	["music-3"] = 10734905665,
	["music-4"] = 10734905823,
	navigation = 10734906744,
	["navigation-2"] = 10734906332,
	["navigation-2-off"] = 10734906144,
	["navigation-off"] = 10734906580,
	network = 10734906975,
	newspaper = 10734907168,
	no_entry = 7734021118,
	octagon = 10734907361,
	["on-charge"] = 7734021231,
	option = 10734907649,
	outdent = 10734907933,
	package = 10734909540,
	["package-2"] = 10734908151,
	["package-check"] = 10734908384,
	["package-minus"] = 10734908626,
	["package-open"] = 10734908793,
	["package-plus"] = 10734909016,
	["package-search"] = 10734909196,
	["package-x"] = 10734909375,
	["paint-bucket"] = 10734909847,
	paintbrush = 10734910187,
	["paintbrush-2"] = 10734910030,
	palette = 10734910430,
	palmtree = 10734910680,
	paperclip = 10734910927,
	["party-popper"] = 10734918735,
	pause = 10734919336,
	["pause-circle"] = 10735024209,
	["pause-octagon"] = 10734919143,
	["pen-tool"] = 10734919503,
	pencil = 10734919691,
	percent = 10734919919,
	["person-standing"] = 10734920149,
	phone = 10734921524,
	["phone-call"] = 10734920305,
	["phone-forwarded"] = 10734920508,
	["phone-incoming"] = 10734920694,
	["phone-missed"] = 10734920845,
	["phone-off"] = 10734921077,
	["phone-outgoing"] = 10734921288,
	pickaxe = 10723396000,
	["pie-chart"] = 10734921727,
	["piggy-bank"] = 10734921935,
	pin = 10734922324,
	["pin-off"] = 10734922180,
	pipette = 10734922497,
	pizza = 10734922774,
	plane = 10734922971,
	play = 10734923549,
	["play-circle"] = 10734923214,
	plus = 10734924532,
	["plus-circle"] = 10734923868,
	["plus-square"] = 10734924219,
	pocket = 7734042139,
	podcast = 10734929553,
	pointer = 10734929723,
	["pound-sterling"] = 10734929981,
	power = 10734930466,
	["power-off"] = 10734930257,
	printer = 10734930632,
	puzzle = 10734930886,
	["qr-code"] = 7743871575,
	quote = 10734931234,
	radar = 10709769841,
	radio = 10734931596,
	["radio-receiver"] = 10734931402,
	["rectangle-horizontal"] = 10734931777,
	["rectangle-vertical"] = 10734932081,
	recycle = 10734932295,
	redo = 10734932822,
	["redo-2"] = 10734932586,
	["refresh-ccw"] = 10734933056,
	["refresh-cw"] = 10734933222,
	refrigerator = 10734933465,
	regex = 10734933655,
	["repeat"] = 10734933966,
	["repeat-1"] = 10734933826,
	reply = 10734934252,
	["reply-all"] = 10734934132,
	rewind = 10734934347,
	rocket = 10734934585,
	["rocking-chair"] = 10734939942,
	["rotate-3d"] = 10734940107,
	["rotate-ccw"] = 10734940376,
	["rotate-cw"] = 10734940654,
	rss = 10734940825,
	ruler = 10734941018,
	["russian-ruble"] = 10734941199,
	sailboat = 10734941354,
	save = 10734941499,
	scale = 10734941912,
	["scale-3d"] = 10734941739,
	scaling = 10734942072,
	scan = 10734942565,
	["scan-face"] = 10734942198,
	["scan-line"] = 10734942351,
	scissors = 10734942778,
	["screen-share"] = 10734943193,
	["screen-share-off"] = 10734942967,
	scroll = 10734943448,
	search = 10734943674,
	send = 10734943902,
	["separator-horizontal"] = 10734944115,
	["separator-vertical"] = 10734944326,
	server = 10734949856,
	["server-cog"] = 10734944444,
	["server-crash"] = 10734944554,
	["server-off"] = 10734944668,
	settings = 10734950309,
	["settings-2"] = 10734950020,
	share = 10734950813,
	["share-2"] = 10734950553,
	sheet = 10734951038,
	shield = 10734951847,
	["shield-alert"] = 10734951173,
	["shield-check"] = 10734951367,
	["shield-close"] = 10734951535,
	["shield-off"] = 10734951684,
	shirt = 10734952036,
	shop = 10734952273,
	["shopping-bag"] = 10734952273,
	["shopping-cart"] = 10734952273,
	shovel = 10734952773,
	["shower-head"] = 10734952942,
	shrink = 10734953073,
	shrub = 10734953241,
	shuffle = 10734953451,
	sidebar = 10734954301,
	["sidebar-close"] = 10734953715,
	["sidebar-open"] = 10734954000,
	sigma = 10734954538,
	signal = 10734961133,
	["signal-high"] = 10734954807,
	["signal-low"] = 10734955080,
	["signal-medium"] = 10734955336,
	["signal-zero"] = 10734960878,
	siren = 10734961284,
	["skip-back"] = 10734961526,
	["skip-forward"] = 10734961809,
	skull = 10734962068,
	slack = 10734962339,
	slash = 10734962600,
	slice = 10734963024,
	sliders = 10734963400,
	["sliders-horizontal"] = 10734963191,
	smartphone = 10734963940,
	["smartphone-charging"] = 10734963671,
	smile = 10734964441,
	["smile-plus"] = 10734964188,
	snowflake = 10734964600,
	sofa = 10734964852,
	["sort-asc"] = 10734965115,
	["sort-desc"] = 10734965287,
	sparkle = 10734966248,
	sparkles = 10734966248,
	speaker = 10734965419,
	sprout = 10734965572,
	square = 10734965702,
	star = 10734966248,
	["star-half"] = 10734965897,
	["star-off"] = 10734966097,
	stethoscope = 10734966384,
	sticker = 10734972234,
	["sticky-note"] = 10734972463,
	["stop-circle"] = 10734972621,
	["stretch-horizontal"] = 10734972862,
	["stretch-vertical"] = 10734973130,
	strikethrough = 10734973290,
	subscript = 10734973457,
	sun = 10734974297,
	["sun-dim"] = 10734973645,
	["sun-medium"] = 10734973778,
	["sun-moon"] = 10734973999,
	["sun-snow"] = 10734974130,
	sunrise = 10734974522,
	sunset = 10734974689,
	superscript = 10734974850,
	["swiss-franc"] = 10734975024,
	["switch-camera"] = 10734975214,
	sword = 10734975486,
	swords = 10734975692,
	syringe = 10734975932,
	table = 10734976230,
	["table-2"] = 10734976097,
	tablet = 10734976394,
	tag = 10734976528,
	tags = 10734976739,
	target = 10734977012,
	tent = 10734981750,
	terminal = 10734982144,
	["terminal-square"] = 10734981995,
	["text-cursor"] = 10734982395,
	["text-cursor-input"] = 10734982297,
	thermometer = 10734983134,
	["thermometer-snowflake"] = 10734982571,
	["thermometer-sun"] = 10734982771,
	["thumbs-down"] = 10734983359,
	["thumbs-up"] = 10734983629,
	ticket = 10734983868,
	timer = 10734984606,
	["timer-off"] = 10734984138,
	["timer-reset"] = 10734984355,
	["toggle-left"] = 10734984834,
	["toggle-right"] = 10734985040,
	tornado = 10734985247,
	["toy-brick"] = 10747361919,
	train = 10747362105,
	trash = 10747362393,
	["trash-2"] = 10747362241,
	tree = 10734982144,
	["tree-deciduous"] = 10747362534,
	["tree-pine"] = 10734982144,
	trees = 10734982260,
	trello = 7743873996,
	["trending-down"] = 10747363205,
	["trending-up"] = 10747363465,
	triangle = 10747363621,
	trophy = 10734983390,
	truck = 10747364031,
	tv = 10747364593,
	["tv-2"] = 10747364302,
	type = 10747364761,
	umbrella = 10747364971,
	underline = 10747365191,
	undo = 10747365484,
	["undo-2"] = 10747365359,
	unlink = 10747365771,
	["unlink-2"] = 10747397871,
	unlock = 10747366027,
	upload = 10747366434,
	["upload-cloud"] = 10747366266,
	usb = 10747366606,
	user = 10747373176,
	["user-check"] = 10747371901,
	["user-cog"] = 10747372167,
	["user-minus"] = 10747372346,
	["user-plus"] = 10747372702,
	["user-x"] = 10747372992,
	users = 10747373426,
	utensils = 10747373821,
	["utensils-crossed"] = 10747373629,
	["venetian-mask"] = 10747374003,
	verified = 10747374131,
	vibrate = 10747374489,
	["vibrate-off"] = 10747374269,
	video = 10747374938,
	["video-off"] = 10747374721,
	view = 10747375132,
	vip = 10709768652,
	voicemail = 10747375281,
	volume = 10747376008,
	["volume-1"] = 10747375450,
	["volume-2"] = 10747375679,
	["volume-x"] = 10747375880,
	wallet = 10747376205,
	wand = 10747376565,
	["wand-2"] = 10747376349,
	watch = 10747376722,
	waves = 10747376931,
	webcam = 10747381992,
	wifi = 10747382504,
	["wifi-off"] = 10747382268,
	wind = 10747382750,
	["wrap-text"] = 10747383065,
	wrench = 10747383470,
	x = 10747384394,
	["x-circle"] = 10747383819,
	["x-octagon"] = 10747384037,
	["x-square"] = 10747384217,
	zap = 10747384394,
	["zoom-in"] = 10747384552,
	["zoom-out"] = 10747384679,
}
local DEFAULT_TAB_ICON = "rbxassetid://10734966248"
local _iconCache = {}

local function resolveIcon(icon)
	if type(icon) ~= "string" or icon == "" then
		return DEFAULT_TAB_ICON
	end
	local cached = _iconCache[icon]
	if cached then
		return cached
	end
	if string.find(icon, "^rbxassetid://") or string.find(icon, "^rbxthumb://") or string.find(icon, "^http") then
		_iconCache[icon] = icon
		return icon
	end
	local key = string.lower(icon)
	if string.sub(key, 1, 7) == "lucide-" then
		key = string.sub(key, 8)
	end
	local id = ICON_MAP[key] or ICON_MAP["lucide-" .. key]
	local res
	if type(id) == "number" then
		res = "rbxassetid://" .. tostring(id)
	elseif type(id) == "string" and id ~= "" then
		res = id
	else
		res = DEFAULT_TAB_ICON
	end
	_iconCache[icon] = res
	return res
end

return {
	Map = ICON_MAP,
	Resolve = resolveIcon,
}

end

-- Module: core/wrapper
__modules["core/wrapper"] = function()
-- core/wrapper.luau
-- Unified Section, Tab, and Element Wrappers for Shenky UI (High-Performance OOP Metatables)

local Icons = __require("assets/icons")
local resolveIcon = Icons.Resolve

local function normalizeOptions(rawList)
	local out = {}
	local seen = {}
	if type(rawList) == "table" then
		for _, item in ipairs(rawList) do
			local str = tostring(item)
			if str ~= "" and not seen[str] then
				seen[str] = true
				table.insert(out, str)
			end
		end
	end
	return out
end

local function normKey(s)
	local c = string.lower(tostring(s or ""))
	while string.find(c, "^%s*%b[]%s*") do
		c = string.gsub(c, "^%s*%b[]%s*", "", 1)
	end
	c = string.gsub(c, "^%s*ultra%s*:%s*", "")
	return (string.gsub(c, "[%s%p]", ""))
end

-- ============================================================
-- ELEMENT WRAPPER PROTOTYPES (Shared across all control instances)
-- ============================================================

-- SubLabel Prototype
local SubLabelWrapperProto = {}
SubLabelWrapperProto.__index = SubLabelWrapperProto

function SubLabelWrapperProto:SetTitle(newText)
	pcall(function() self._raw:UpdateName(tostring(newText or "")) end)
end
function SubLabelWrapperProto:SetText(newText)
	pcall(function() self._raw:UpdateName(tostring(newText or "")) end)
end
function SubLabelWrapperProto:UpdateText(newText)
	pcall(function() self._raw:UpdateName(tostring(newText or "")) end)
end
function SubLabelWrapperProto:UpdateName(newText)
	pcall(function() self._raw:UpdateName(tostring(newText or "")) end)
end
function SubLabelWrapperProto:SetDesc(newText)
	pcall(function() self._raw:UpdateName(tostring(newText or "")) end)
end
function SubLabelWrapperProto:SetContent(newText)
	pcall(function() self._raw:UpdateName(tostring(newText or "")) end)
end
function SubLabelWrapperProto:SetVisibility(state)
	pcall(function() self._raw:SetVisibility(state == true) end)
end

-- Paragraph Prototype
local ParagraphWrapperProto = {}
ParagraphWrapperProto.__index = ParagraphWrapperProto

function ParagraphWrapperProto:SetTitle(newHeader)
	pcall(function() self._raw:UpdateHeader(tostring(newHeader or "")) end)
end
function ParagraphWrapperProto:SetDesc(newBody)
	pcall(function() self._raw:UpdateBody(tostring(newBody or "")) end)
end
function ParagraphWrapperProto:SetContent(newBody)
	pcall(function() self._raw:UpdateBody(tostring(newBody or "")) end)
end
function ParagraphWrapperProto:UpdateHeader(newHeader)
	pcall(function() self._raw:UpdateHeader(tostring(newHeader or "")) end)
end
function ParagraphWrapperProto:UpdateBody(newBody)
	pcall(function() self._raw:UpdateBody(tostring(newBody or "")) end)
end
function ParagraphWrapperProto:SetVisibility(state)
	pcall(function() self._raw:SetVisibility(state == true) end)
end

-- MetricGrid Prototype
local MetricGridWrapperProto = {}
MetricGridWrapperProto.__index = MetricGridWrapperProto

function MetricGridWrapperProto:Update(keyOrIndex, newVal, newLabel)
	if self._raw and self._raw.Update then
		return self._raw:Update(keyOrIndex, newVal, newLabel)
	end
end

function MetricGridWrapperProto:Set(keyOrIndex, newVal)
	if self._raw and self._raw.Set then
		return self._raw:Set(keyOrIndex, newVal)
	end
end

function MetricGridWrapperProto:GetTile(keyOrIndex)
	if self._raw and self._raw.GetTile then
		return self._raw:GetTile(keyOrIndex)
	end
end

function MetricGridWrapperProto:SetVisibility(state)
	if self._raw and self._raw.SetVisibility then
		self._raw:SetVisibility(state == true)
	end
end

-- ButtonRow Prototype
local ButtonRowWrapperProto = {}
ButtonRowWrapperProto.__index = ButtonRowWrapperProto

function ButtonRowWrapperProto:SetVisibility(state)
	if self._raw and self._raw.SetVisibility then
		self._raw:SetVisibility(state == true)
	end
end

-- Button Prototype
local ButtonWrapperProto = {}
ButtonWrapperProto.__index = ButtonWrapperProto

function ButtonWrapperProto:SetTitle(newName)
	pcall(function() self._raw:UpdateName(tostring(newName or "")) end)
end
function ButtonWrapperProto:UpdateName(newName)
	pcall(function() self._raw:UpdateName(tostring(newName or "")) end)
end
function ButtonWrapperProto:SetVisibility(state)
	pcall(function() self._raw:SetVisibility(state == true) end)
end

-- Toggle Prototype
local ToggleWrapperProto = {}
ToggleWrapperProto.__index = ToggleWrapperProto

function ToggleWrapperProto:Set(bool)
	local target = (bool == true)
	pcall(function()
		if self._raw:GetState() ~= target then
			self._raw:UpdateState(target)
		end
	end)
end
function ToggleWrapperProto:UpdateState(bool)
	self:Set(bool)
end
function ToggleWrapperProto:GetState()
	local ok, st = pcall(function() return self._raw:GetState() end)
	return ok and st == true or false
end
ToggleWrapperProto.Get = ToggleWrapperProto.GetState
ToggleWrapperProto.GetValue = ToggleWrapperProto.GetState
function ToggleWrapperProto:SetTitle(newName)
	pcall(function() self._raw:UpdateName(tostring(newName or "")) end)
end
function ToggleWrapperProto:UpdateName(newName)
	pcall(function() self._raw:UpdateName(tostring(newName or "")) end)
end
function ToggleWrapperProto:SetVisibility(state)
	pcall(function() self._raw:SetVisibility(state == true) end)
end

-- Checkbox Prototype
local CheckboxWrapperProto = {}
CheckboxWrapperProto.__index = CheckboxWrapperProto

function CheckboxWrapperProto:Set(bool)
	local target = (bool == true)
	pcall(function()
		if self._raw:GetState() ~= target then
			self._raw:UpdateState(target)
		end
	end)
end
function CheckboxWrapperProto:UpdateState(bool)
	self:Set(bool)
end
function CheckboxWrapperProto:GetState()
	local ok, st = pcall(function() return self._raw:GetState() end)
	return ok and st == true or false
end
CheckboxWrapperProto.Get = CheckboxWrapperProto.GetState
CheckboxWrapperProto.GetValue = CheckboxWrapperProto.GetState
function CheckboxWrapperProto:SetTitle(newName)
	pcall(function() self._raw:UpdateName(tostring(newName or "")) end)
end
function CheckboxWrapperProto:UpdateName(newName)
	pcall(function() self._raw:UpdateName(tostring(newName or "")) end)
end
function CheckboxWrapperProto:SetVisibility(state)
	pcall(function() self._raw:SetVisibility(state == true) end)
end

-- ProgressBar Prototype
local ProgressBarWrapperProto = {}
ProgressBarWrapperProto.__index = ProgressBarWrapperProto

function ProgressBarWrapperProto:SetProgress(val, max, customText)
	pcall(function()
		self._raw:SetProgress(val, max, customText)
	end)
end
function ProgressBarWrapperProto:Set(val)
	self:SetProgress(val)
end
function ProgressBarWrapperProto:Get()
	local ok, v = pcall(function() return self._raw:GetProgress() end)
	return ok and v or 0
end
function ProgressBarWrapperProto:SetColor(color)
	pcall(function() self._raw:SetColor(color) end)
end
function ProgressBarWrapperProto:UpdateName(newName)
	pcall(function() self._raw:UpdateName(tostring(newName or "")) end)
end
function ProgressBarWrapperProto:SetVisibility(state)
	pcall(function() self._raw:SetVisibility(state == true) end)
end

-- Slider Prototype
local SliderWrapperProto = {}
SliderWrapperProto.__index = SliderWrapperProto

function SliderWrapperProto:Set(val)
	local num = tonumber(val)
	if not num then return end
	num = math.clamp(num, self._minVal, self._maxVal)
	self._suppressCallback = true
	pcall(function()
		self._raw:UpdateValue(num)
	end)
	self._suppressCallback = false
end
function SliderWrapperProto:SetValue(val)
	self:Set(val)
end
function SliderWrapperProto:UpdateValue(val)
	self:Set(val)
end
function SliderWrapperProto:GetValue()
	local ok, v = pcall(function() return self._raw:GetValue() end)
	return ok and tonumber(v) or self._defVal
end
SliderWrapperProto.Get = SliderWrapperProto.GetValue
function SliderWrapperProto:SetVisibility(state)
	pcall(function() self._raw:SetVisibility(state == true) end)
end

-- Input Prototype
local InputWrapperProto = {}
InputWrapperProto.__index = InputWrapperProto

function InputWrapperProto:Set(text)
	self._suppressCallback = true
	pcall(function()
		self._raw:UpdateText(tostring(text or ""))
	end)
	self._suppressCallback = false
end
function InputWrapperProto:SetValue(text)
	self:Set(text)
end
function InputWrapperProto:UpdateText(text)
	self:Set(text)
end
function InputWrapperProto:GetInput()
	local ok, t = pcall(function() return self._raw:GetInput() end)
	return ok and tostring(t or "") or ""
end
InputWrapperProto.Get = InputWrapperProto.GetInput
function InputWrapperProto:SetVisibility(state)
	pcall(function() self._raw:SetVisibility(state == true) end)
end

-- Dropdown Prototype
local DropdownWrapperProto = {}
DropdownWrapperProto.__index = DropdownWrapperProto

function DropdownWrapperProto:Refresh(newValues)
	local rawList = newValues
	if type(newValues) == "table" and (newValues.Values or newValues.Options or newValues.Items) then
		rawList = newValues.Values or newValues.Options or newValues.Items
	end
	self._options = normalizeOptions(rawList)
	local options = self._options
	local rawDropdown = self._raw
	local isMulti = self._isMulti

	pcall(function()
		if isMulti then
			if type(rawDropdown.Value) == "table" then
				for _, v in ipairs(rawDropdown.Value) do
					if type(v) == "string" and not self._currentMultiSelection[v] then
						self._currentMultiSelection[v] = true
						table.insert(self._currentMultiOrder, v)
					end
				end
				for k, v in pairs(rawDropdown.Value) do
					if v == true and type(k) == "string" and not self._currentMultiSelection[k] then
						self._currentMultiSelection[k] = true
						table.insert(self._currentMultiOrder, k)
					end
				end
			end
			local optSet = {}
			local optByNorm = {}
			for _, opt in ipairs(options) do
				optSet[opt] = true
				local nk = normKey(opt)
				if nk ~= "" and not optByNorm[nk] then
					optByNorm[nk] = opt
				end
			end
			local gCanon = getgenv and (getgenv().__HUB_CANONICAL_OPTIONS or getgenv().__PIXEL_LINEAGE_CANONICAL_SKILLS)
			if type(gCanon) == "table" then
				for _, canonName in pairs(gCanon) do
					if type(canonName) == "string" and canonName ~= "" then
						optSet[canonName] = true
						local nk = normKey(canonName)
						if nk ~= "" and not optByNorm[nk] then
							optByNorm[nk] = canonName
						end
					end
				end
			end
			local updatedMulti = {}
			local updatedOrder = {}
			for _, opt in ipairs(self._currentMultiOrder) do
				local resolved = optSet[opt] and opt or nil
				if not resolved then
					local nk = normKey(opt)
					if nk ~= "" and optByNorm[nk] then
						resolved = optByNorm[nk]
					end
				end
				if not resolved and type(gCanon) == "table" then
					local nk = normKey(opt)
					if nk ~= "" and type(gCanon[nk]) == "string" then
						resolved = gCanon[nk]
					end
				end
				if resolved and not updatedMulti[resolved] then
					updatedMulti[resolved] = true
					table.insert(updatedOrder, resolved)
				end
			end
			for opt in pairs(self._currentMultiSelection) do
				local resolved = optSet[opt] and opt or nil
				if not resolved then
					local nk = normKey(opt)
					if nk ~= "" and optByNorm[nk] then
						resolved = optByNorm[nk]
					end
				end
				if not resolved and type(gCanon) == "table" then
					local nk = normKey(opt)
					if nk ~= "" and type(gCanon[nk]) == "string" then
						resolved = gCanon[nk]
					end
				end
				if resolved and not updatedMulti[resolved] then
					updatedMulti[resolved] = true
					table.insert(updatedOrder, resolved)
				end
			end
			self._currentMultiSelection = updatedMulti
			self._currentMultiOrder = updatedOrder
		else
			local optSet = {}
			local optByNorm = {}
			for _, opt in ipairs(options) do
				optSet[opt] = true
				local nk = normKey(opt)
				if nk ~= "" and not optByNorm[nk] then
					optByNorm[nk] = opt
				end
			end
			local gCanon = getgenv and (getgenv().__HUB_CANONICAL_OPTIONS or getgenv().__PIXEL_LINEAGE_CANONICAL_SKILLS)
			if type(gCanon) == "table" then
				for _, canonName in pairs(gCanon) do
					if type(canonName) == "string" and canonName ~= "" then
						optSet[canonName] = true
						local nk = normKey(canonName)
						if nk ~= "" and not optByNorm[nk] then
							optByNorm[nk] = canonName
						end
					end
				end
			end
			local resolvedSingle = nil
			if self._currentSingleSelection then
				if optSet[self._currentSingleSelection] then
					resolvedSingle = self._currentSingleSelection
				else
					local nk = normKey(self._currentSingleSelection)
					if nk ~= "" and optByNorm[nk] then
						resolvedSingle = optByNorm[nk]
					elseif type(gCanon) == "table" and nk ~= "" and type(gCanon[nk]) == "string" then
						resolvedSingle = gCanon[nk]
					end
				end
			end
			self._currentSingleSelection = resolvedSingle
		end

		if type(rawDropdown.ClearOptions) == "function" then
			rawDropdown:ClearOptions()
		end
		if type(rawDropdown.InsertOptions) == "function" then
			rawDropdown:InsertOptions(options)
		end

		if isMulti then
			if #self._currentMultiOrder > 0 and type(rawDropdown.UpdateSelection) == "function" then
				rawDropdown:UpdateSelection(self._currentMultiOrder)
			end
		else
			if self._currentSingleSelection and type(rawDropdown.UpdateSelection) == "function" then
				rawDropdown:UpdateSelection(self._currentSingleSelection)
			end
		end
	end)
end

function DropdownWrapperProto:Select(selection)
	local rawDropdown = self._raw
	local isMulti = self._isMulti
	pcall(function()
		if isMulti then
			local list = {}
			local newMap = {}
			if type(selection) == "table" then
				for _, v in ipairs(selection) do
					if type(v) == "string" and not newMap[v] then
						table.insert(list, v)
						newMap[v] = true
					end
				end
				for k, v in pairs(selection) do
					if v == true and type(k) == "string" and not newMap[k] then
						table.insert(list, k)
						newMap[k] = true
					end
				end
			elseif type(selection) == "string" then
				table.insert(list, selection)
				newMap[selection] = true
			end
			self._currentMultiSelection = newMap
			self._currentMultiOrder = list
			rawDropdown:UpdateSelection(list)
		else
			self._currentSingleSelection = type(selection) == "string" and selection or nil
			if selection ~= nil then
				rawDropdown:UpdateSelection(selection)
			end
		end
	end)
end

function DropdownWrapperProto:Set(selection)
	self:Select(selection)
end

function DropdownWrapperProto:UpdateSelection(selection)
	self:Select(selection)
end

function DropdownWrapperProto:SetVisibility(state)
	local rawDropdown = self._raw
	pcall(function()
		if type(rawDropdown.SetVisibility) == "function" then
			rawDropdown:SetVisibility(state == true)
		elseif type(rawDropdown.SetVisiblity) == "function" then
			rawDropdown:SetVisiblity(state == true)
		end
	end)
end

function DropdownWrapperProto:UpdateName(newTitle)
	local rawDropdown = self._raw
	pcall(function()
		if type(rawDropdown.UpdateName) == "function" then
			rawDropdown:UpdateName(newTitle)
		end
	end)
end

function DropdownWrapperProto:UpdateTitle(newTitle)
	self:UpdateName(newTitle)
end

function DropdownWrapperProto:SetOptions(newValues)
	self:Refresh(newValues)
end
function DropdownWrapperProto:GetValue()
	if self._isMulti then
		return self._currentMultiOrder
	else
		return self._currentSingleSelection
	end
end
DropdownWrapperProto.Get = DropdownWrapperProto.GetValue

-- Colorpicker Prototype
local ColorpickerWrapperProto = {}
ColorpickerWrapperProto.__index = ColorpickerWrapperProto

function ColorpickerWrapperProto:Set(col, alpha)
	pcall(function()
		if col and self._raw.SetColor then
			self._raw:SetColor(col)
		end
		if alpha and self._raw.SetAlpha then
			self._raw:SetAlpha(alpha)
		end
	end)
end
function ColorpickerWrapperProto:SetColor(col)
	pcall(function()
		if self._raw.SetColor then
			self._raw:SetColor(col)
		end
	end)
end
function ColorpickerWrapperProto:SetAlpha(alpha)
	pcall(function()
		if self._raw.SetAlpha then
			self._raw:SetAlpha(alpha)
		end
	end)
end
function ColorpickerWrapperProto:GetColor()
	if self._raw and self._raw.Color then
		return self._raw.Color, self._raw.Alpha or 1
	end
	return Color3.fromRGB(255, 255, 255), 1
end
function ColorpickerWrapperProto:GetValue()
	return self:GetColor()
end
function ColorpickerWrapperProto:SetVisibility(state)
	pcall(function() self._raw:SetVisibility(state == true) end)
end

-- Keybind Prototype
local KeybindWrapperProto = {}
KeybindWrapperProto.__index = KeybindWrapperProto

function KeybindWrapperProto:Bind(key)
	pcall(function() self._raw:Bind(key) end)
end
function KeybindWrapperProto:Set(key)
	pcall(function() self._raw:Set(key) end)
end
function KeybindWrapperProto:Get()
	local ok, v = pcall(function() return self._raw:Get() end)
	return ok and v or Enum.KeyCode.Unknown
end
function KeybindWrapperProto:GetValue()
	return self:Get()
end
function KeybindWrapperProto:SetVisibility(state)
	pcall(function() self._raw:SetVisibility(state == true) end)
end
function KeybindWrapperProto:Destroy()
	pcall(function() self._raw:Destroy() end)
end

-- SegmentedControl Prototype
local SegmentedControlWrapperProto = {}
SegmentedControlWrapperProto.__index = SegmentedControlWrapperProto

function SegmentedControlWrapperProto:Set(val, skipCallback)
	pcall(function() self._raw:Set(val, skipCallback) end)
end
function SegmentedControlWrapperProto:Get()
	local ok, v = pcall(function() return self._raw:Get() end)
	return ok and v or nil
end
function SegmentedControlWrapperProto:GetValue()
	return self:Get()
end
function SegmentedControlWrapperProto:UpdateOptions(newOptions)
	pcall(function() self._raw:UpdateOptions(newOptions) end)
end
function SegmentedControlWrapperProto:SetVisibility(state)
	pcall(function() self._raw:SetVisibility(state == true) end)
end
function SegmentedControlWrapperProto:Destroy()
	pcall(function() self._raw:Destroy() end)
end

-- Badge Prototype
local BadgeWrapperProto = {}
BadgeWrapperProto.__index = BadgeWrapperProto

function BadgeWrapperProto:SetText(text)
	pcall(function() self._raw:SetText(text) end)
end
function BadgeWrapperProto:SetVariant(variant)
	pcall(function() self._raw:SetVariant(variant) end)
end
function BadgeWrapperProto:Destroy()
	pcall(function() self._raw:Destroy() end)
end

-- History Prototype
local HistoryWrapperProto = {}
HistoryWrapperProto.__index = HistoryWrapperProto

function HistoryWrapperProto:SetHistory(items)
	if self._raw and self._raw.SetHistory then
		self._raw:SetHistory(items)
	end
end

function HistoryWrapperProto:Update(items)
	if self._raw and self._raw.Update then
		self._raw:Update(items)
	end
end

-- Micro-UX UX Attach Helpers (Tooltip & Badge)
local function attachTooltip(rawObj, tooltipText)
	if not tooltipText or tooltipText == "" or not rawObj then return end
	local target = rawObj.Instance or rawObj.Frame or rawObj.button or rawObj.toggle or rawObj.slider or rawObj.dropdown or rawObj.binderBox or rawObj.Pill
	if target and typeof(target) == "Instance" then
		local TooltipClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Tooltip)
		if TooltipClass and type(TooltipClass.Attach) == "function" then
			TooltipClass.Attach(target, tooltipText)
		end
	end
end

local function attachBadge(rawObj, badgeCfg)
	if not badgeCfg or not rawObj then return end
	local BadgeClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Badge)
	if not BadgeClass then return end
	local target = rawObj.Instance or rawObj.Frame
	if target and typeof(target) == "Instance" then
		local titleLabel = nil
		for _, child in ipairs(target:GetDescendants()) do
			if child:IsA("TextLabel") and (child.Name:find("Title") or child.Name:find("Name")) then
				titleLabel = child
				break
			end
		end

		if titleLabel and titleLabel.Parent then
			local parentFrame = titleLabel.Parent
			if parentFrame.Name == "TitleRow" then
				BadgeClass.new(parentFrame, badgeCfg)
			else
				local titleRow = Instance.new("Frame")
				titleRow.Name = "TitleRow"
				titleRow.LayoutOrder = titleLabel.LayoutOrder
				titleRow.BackgroundTransparency = 1
				titleRow.BorderSizePixel = 0
				titleRow.Size = UDim2.new(1, 0, 0, 16)
				titleRow.AutomaticSize = Enum.AutomaticSize.Y
				titleRow.Parent = parentFrame

				local rowLayout = Instance.new("UIListLayout")
				rowLayout.FillDirection = Enum.FillDirection.Horizontal
				rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
				rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
				rowLayout.Padding = UDim.new(0, 6)
				rowLayout.Parent = titleRow

				titleLabel.Parent = titleRow
				titleLabel.Size = UDim2.new(0, 0, 0, 16)
				titleLabel.AutomaticSize = Enum.AutomaticSize.X
				titleLabel.LayoutOrder = 1

				local badge = BadgeClass.new(titleRow, badgeCfg)
				if badge and badge.Instance then
					badge.Instance.LayoutOrder = 2
				end
			end
		else
			local header = target:FindFirstChild("HeaderFrame") or target:FindFirstChild("LeftLabels") or target
			BadgeClass.new(header, badgeCfg)
		end
	end
end

-- ============================================================
-- SECTION WRAPPER PROTOTYPE
-- ============================================================
local SectionWrapperProto = {}
SectionWrapperProto.__index = SectionWrapperProto

function SectionWrapperProto:_ResolveFlag(cfg, title)
	if cfg and cfg.IgnoreConfig == true then
		return nil
	end
	local rawFlag = cfg and cfg.Flag
	if type(rawFlag) ~= "string" or rawFlag == "" then
		if self._currentSectionHeader ~= "" then
			rawFlag = self._currentSectionHeader .. "::" .. tostring(title or "Control")
		else
			rawFlag = tostring(title or "Control")
		end
	end
	local hub = self._hub
	hub._usedFlags = hub._usedFlags or {}
	local finalFlag = rawFlag
	local count = 1
	while hub._usedFlags[finalFlag] do
		count = count + 1
		finalFlag = rawFlag .. "_" .. tostring(count)
	end
	hub._usedFlags[finalFlag] = true
	return finalFlag
end

function SectionWrapperProto:Header(cfg)
	local text = tostring(type(cfg) == "table" and (cfg.Title or cfg.Text or cfg.Name) or (cfg or ""))
	local icon = type(cfg) == "table" and (cfg.Icon or cfg.Image) or nil
	if text ~= "" then
		self._currentSectionHeader = text
	end
	return self._raw:Header({
		Name = text,
		Text = text,
		Icon = icon,
	})
end

function SectionWrapperProto:Divider()
	return self._raw:Divider()
end

function SectionWrapperProto:Spacer()
	return self._raw:Spacer()
end

function SectionWrapperProto:Label(cfg)
	local text = type(cfg) == "table" and (cfg.Title or cfg.Text or cfg.Name or cfg.Content) or tostring(cfg or "")
	return self._raw:Label({
		Text = tostring(text or ""),
	})
end

function SectionWrapperProto:SubLabel(cfg)
	local text = type(cfg) == "table" and (cfg.Title or cfg.Text or cfg.Name or cfg.Content) or tostring(cfg or "")
	local rawSub = self._raw:SubLabel({
		Text = tostring(text or ""),
	})
	return setmetatable({ _raw = rawSub }, SubLabelWrapperProto)
end

function SectionWrapperProto:Paragraph(cfg)
	cfg = cfg or {}
	local header = tostring(cfg.Title or cfg.Header or cfg.Name or "")
	local body = tostring(cfg.Desc or cfg.Body or cfg.Text or cfg.Content or "")
	local rawPar = self._raw:Paragraph({
		Header = header,
		Body = body,
	})
	return setmetatable({ _raw = rawPar }, ParagraphWrapperProto)
end

function SectionWrapperProto:MetricGrid(cfg)
	cfg = cfg or {}
	local rawGrid = self._raw:MetricGrid(cfg)
	local wrapper = setmetatable({ _raw = rawGrid }, MetricGridWrapperProto)
	return wrapper
end

function SectionWrapperProto:StatGrid(cfg)
	return self:MetricGrid(cfg)
end

function SectionWrapperProto:ButtonRow(buttonsList)
	local rawRow = self._raw:ButtonRow(buttonsList or {})
	local wrapper = setmetatable({ _raw = rawRow }, ButtonRowWrapperProto)
	return wrapper
end

function SectionWrapperProto:Button(cfg)
	cfg = cfg or {}
	local title = tostring(cfg.Title or cfg.Name or "Button")
	local desc = cfg.Description or cfg.Desc or cfg.SubTitle or cfg.SubText
	local userCallback = cfg.Callback
	local rawBtn = self._raw:Button({
		Name = title,
		Description = desc,
		Callback = function()
			if type(userCallback) == "function" then
				userCallback()
			end
		end,
	})
	local wrapper = setmetatable({ _raw = rawBtn }, ButtonWrapperProto)
	attachTooltip(rawBtn, cfg.Tooltip)
	attachBadge(rawBtn, cfg.Badge)
	if not cfg._isInternalConfig and self._hub and type(self._hub.RegisterFeature) == "function" then
		self._hub:RegisterFeature({
			Name = title,
			Type = "Button",
			TabTitle = self._tabTitle or "General",
			Tab = self._tab,
			SectionTitle = self._currentSectionHeader or "Main",
			Wrapper = wrapper,
			Raw = rawBtn,
			Execute = function()
				if type(userCallback) == "function" then
					userCallback()
				end
			end,
		})
	end
	return wrapper
end

function SectionWrapperProto:Toggle(cfg)
	cfg = cfg or {}
	local title = tostring(cfg.Title or cfg.Name or "Toggle")
	local desc = cfg.Description or cfg.Desc or cfg.SubTitle or cfg.SubText
	local defaultVal = (cfg.Value == true) or (cfg.Default == true)
	local userCallback = cfg.Callback
	local flag = self:_ResolveFlag(cfg, title)

	local rawToggle = self._raw:Toggle({
		Name = title,
		Description = desc,
		Default = defaultVal,
		Callback = function(val)
			if type(userCallback) == "function" then
				userCallback(val == true)
			end
		end,
	}, flag)

	local wrapper = setmetatable({ _raw = rawToggle, Flag = flag }, ToggleWrapperProto)
	attachTooltip(rawToggle, cfg.Tooltip)
	attachBadge(rawToggle, cfg.Badge)
	if cfg._isInternalConfigToggle then
		rawToggle._isInternalConfig = true
		rawToggle._isInternalConfigToggle = true
	else
		table.insert(self._hub._toggles, wrapper)
		if self._hub and type(self._hub.RegisterFeature) == "function" then
			self._hub:RegisterFeature({
				Name = title,
				Type = "Toggle",
				TabTitle = self._tabTitle or "General",
				Tab = self._tab,
				SectionTitle = self._currentSectionHeader or "Main",
				Wrapper = wrapper,
				Raw = rawToggle,
				GetState = function() return wrapper:Get() end,
				SetState = function(v) wrapper:Set(v) end,
			})
		end
	end
	return wrapper
end

function SectionWrapperProto:Slider(cfg)
	cfg = cfg or {}
	local title = tostring(cfg.Title or cfg.Name or "Slider")
	local desc = cfg.Description or cfg.Desc or cfg.SubTitle or cfg.SubText
	local valTbl = type(cfg.Value) == "table" and cfg.Value or nil
	local minVal = tonumber(valTbl and (valTbl.Min or valTbl.Minimum) or cfg.Min or cfg.Minimum) or 0
	local maxVal = tonumber(valTbl and (valTbl.Max or valTbl.Maximum) or cfg.Max or cfg.Maximum) or 100
	local defVal = tonumber(valTbl and (valTbl.Default or valTbl.Value) or (type(cfg.Value) == "number" and cfg.Value) or cfg.Default) or minVal
	defVal = math.clamp(defVal, minVal, maxVal)

	local step = tonumber(cfg.Step) or 1
	local precision = tonumber(cfg.Precision)
	if precision == nil then
		if step < 0.1 then
			precision = 2
		elseif step < 1 then
			precision = 1
		else
			precision = 0
		end
	end

	local userCallback = cfg.Callback
	local flag = self:_ResolveFlag(cfg, title)
	local wrapper = setmetatable({
		_raw = nil,
		Flag = flag,
		_minVal = minVal,
		_maxVal = maxVal,
		_defVal = defVal,
		_suppressCallback = true,
	}, SliderWrapperProto)

	local rawSlider = self._raw:Slider({
		Name = title,
		Description = desc,
		Default = defVal,
		Minimum = minVal,
		Maximum = maxVal,
		DisplayMethod = cfg.DisplayMethod or "Value",
		Precision = precision,
		Suffix = cfg.Suffix,
		Prefix = cfg.Prefix,
		Callback = function(val)
			if wrapper._suppressCallback then return end
			if type(userCallback) == "function" then
				userCallback(tonumber(val) or defVal)
			end
		end,
	}, flag)

	wrapper._raw = rawSlider
	wrapper._suppressCallback = false
	if not cfg._isInternalConfig and self._hub and type(self._hub.RegisterFeature) == "function" then
		self._hub:RegisterFeature({
			Name = title,
			Type = "Slider",
			TabTitle = self._tabTitle or "General",
			Tab = self._tab,
			SectionTitle = self._currentSectionHeader or "Main",
			Wrapper = wrapper,
			Raw = rawSlider,
			GetValue = function() return wrapper:Get() end,
			SetValue = function(v) wrapper:Set(v) end,
		})
	end
	return wrapper
end

function SectionWrapperProto:Input(cfg)
	cfg = cfg or {}
	local title = tostring(cfg.Title or cfg.Name or "Input")
	local desc = cfg.Description or cfg.Desc or cfg.SubTitle or cfg.Tooltip or cfg.HoverText or cfg.Info
	local placeholder = tostring(cfg.Placeholder or cfg.Value or "")
	local initialValue = cfg.Value ~= nil and tostring(cfg.Value) or ""
	local userCallback = cfg.Callback
	local flag = self:_ResolveFlag(cfg, title)

	local wrapper = setmetatable({
		_raw = nil,
		Flag = flag,
		_suppressCallback = true,
	}, InputWrapperProto)

	local function handleInputText(text)
		if wrapper._suppressCallback then return end
		if type(userCallback) == "function" then
			userCallback(tostring(text or ""))
		end
	end

	local rawInput = self._raw:Input({
		Name = title,
		Placeholder = placeholder,
		Description = desc,
		SubTitle = desc,
		AcceptedCharacters = cfg.AcceptedCharacters or "All",
		Callback = handleInputText,
		onChanged = handleInputText,
	}, flag)

	if initialValue ~= "" then
		pcall(function()
			rawInput:UpdateText(initialValue)
		end)
	else
		pcall(function()
			rawInput:UpdateText("")
		end)
	end

	wrapper._raw = rawInput
	wrapper._suppressCallback = false
	if not cfg._isInternalConfig and self._hub and type(self._hub.RegisterFeature) == "function" then
		self._hub:RegisterFeature({
			Name = title,
			Type = "Input",
			TabTitle = self._tabTitle or "General",
			Tab = self._tab,
			SectionTitle = self._currentSectionHeader or "Main",
			Wrapper = wrapper,
			Raw = rawInput,
			GetValue = function() return wrapper:Get() end,
			SetValue = function(v) wrapper:Set(v) end,
		})
	end
	return wrapper
end

function SectionWrapperProto:Checkbox(cfg)
	cfg = cfg or {}
	local title = tostring(cfg.Title or cfg.Name or "Checkbox")
	local desc = cfg.Description or cfg.Desc or cfg.SubTitle or cfg.SubText
	local defaultVal = (cfg.Value == true) or (cfg.Default == true)
	local userCallback = cfg.Callback
	local flag = self:_ResolveFlag(cfg, title)

	local rawCheckbox = self._raw:Checkbox({
		Name = title,
		Description = desc,
		Default = defaultVal,
		Callback = function(val)
			if type(userCallback) == "function" then
				userCallback(val == true)
			end
		end,
	}, flag)

	local wrapper = setmetatable({ _raw = rawCheckbox, Flag = flag }, CheckboxWrapperProto)
	attachTooltip(rawCheckbox, cfg.Tooltip)
	attachBadge(rawCheckbox, cfg.Badge)
	if not cfg._isInternalConfigCheckbox then
		table.insert(self._hub._toggles, wrapper)
		if self._hub and type(self._hub.RegisterFeature) == "function" then
			self._hub:RegisterFeature({
				Name = title,
				Type = "Checkbox",
				TabTitle = self._tabTitle or "General",
				Tab = self._tab,
				SectionTitle = self._currentSectionHeader or "Main",
				Wrapper = wrapper,
				Raw = rawCheckbox,
				GetState = function() return wrapper:Get() end,
				SetState = function(v) wrapper:Set(v) end,
			})
		end
	end
	return wrapper
end

function SectionWrapperProto:ProgressBar(cfg)
	cfg = cfg or {}
	local title = tostring(cfg.Title or cfg.Name or "Progress")
	local desc = cfg.Description or cfg.Desc or cfg.SubTitle or cfg.SubText
	local flag = self:_ResolveFlag(cfg, title)

	local rawProgress = self._raw:ProgressBar({
		Name = title,
		Description = desc,
		Min = cfg.Min or 0,
		Max = cfg.Max or 100,
		Value = cfg.Value or cfg.Default or (cfg.Min or 0),
		ShowPercent = cfg.ShowPercent,
		ShowValues = cfg.ShowValues,
		Unit = cfg.Unit,
		Color = cfg.Color,
	}, flag)

	local wrapper = setmetatable({ _raw = rawProgress, Flag = flag }, ProgressBarWrapperProto)
	attachTooltip(rawProgress, cfg.Tooltip)
	attachBadge(rawProgress, cfg.Badge)
	return wrapper
end

function SectionWrapperProto:MultiDropdown(cfg)
	cfg = cfg or {}
	cfg.Multi = true
	return self:Dropdown(cfg)
end

function SectionWrapperProto:Dropdown(cfg)
	cfg = cfg or {}
	local title = tostring(cfg.Title or cfg.Name or "Dropdown")
	local isMulti = cfg.Multi == true
	local isSearch = (cfg.SearchBarEnabled == true) or (cfg.Search == true)
	local options = normalizeOptions(cfg.Values or cfg.Options or cfg.Items)
	local rawDefault = cfg.Value ~= nil and cfg.Value or cfg.Default
	local userCallback = cfg.Callback
	local flag = self:_ResolveFlag(cfg, title)

	local currentMultiSelection = {}
	local currentMultiOrder = {}
	local currentSingleSelection = nil

	local macDefault = nil
	if isMulti then
		local defList = {}
		if type(rawDefault) == "table" then
			for _, v in ipairs(rawDefault) do
				if type(v) == "string" and not currentMultiSelection[v] then
					table.insert(defList, v)
					table.insert(currentMultiOrder, v)
					currentMultiSelection[v] = true
				end
			end
			for k, v in pairs(rawDefault) do
				if v == true and type(k) == "string" and not currentMultiSelection[k] then
					table.insert(defList, k)
					table.insert(currentMultiOrder, k)
					currentMultiSelection[k] = true
				end
			end
		elseif type(rawDefault) == "string" and rawDefault ~= "" then
			table.insert(defList, rawDefault)
			table.insert(currentMultiOrder, rawDefault)
			currentMultiSelection[rawDefault] = true
		end
		if #defList > 0 then
			macDefault = defList
		end
	else
		if type(rawDefault) == "number" and options[rawDefault] then
			macDefault = rawDefault
			currentSingleSelection = options[rawDefault]
		elseif type(rawDefault) == "string" and rawDefault ~= "" then
			for idx, opt in ipairs(options) do
				if opt == rawDefault then
					macDefault = idx
					currentSingleSelection = opt
					break
				end
			end
		end
	end

	local wrapper = setmetatable({
		_raw = nil,
		Flag = flag,
		_isMulti = isMulti,
		_options = options,
		_currentMultiSelection = currentMultiSelection,
		_currentMultiOrder = currentMultiOrder,
		_currentSingleSelection = currentSingleSelection,
	}, DropdownWrapperProto)

	local desc = cfg.Description or cfg.Desc or cfg.SubTitle or cfg.SubText
	local rawDropdown = self._raw:Dropdown({
		Name = title,
		Description = desc,
		Search = isSearch,
		Multi = isMulti,
		Required = false,
		Options = options,
		Default = macDefault,
		SubTitle = desc,
		Placeholder = cfg.Placeholder or "Select...",
		Callback = function(val, orderedArg)
			if isMulti then
				local activeMap = {}
				local orderedList = {}
				if type(orderedArg) == "table" then
					for _, v in ipairs(orderedArg) do
						if type(v) == "string" and not activeMap[v] then
							activeMap[v] = true
							table.insert(orderedList, v)
						end
					end
				end
				if rawDropdown and type(rawDropdown.Value) == "table" then
					for _, v in ipairs(rawDropdown.Value) do
						if type(v) == "string" and (type(val) ~= "table" or val[v] == true or table.find(val, v) ~= nil) and not activeMap[v] then
							activeMap[v] = true
							table.insert(orderedList, v)
						end
					end
				end
				if type(val) == "table" then
					for _, v in ipairs(val) do
						if type(v) == "string" and not activeMap[v] then
							activeMap[v] = true
							table.insert(orderedList, v)
						end
					end
					for k, v in pairs(val) do
						if v == true and type(k) == "string" and not activeMap[k] then
							activeMap[k] = true
							table.insert(orderedList, k)
						end
					end
				end
				wrapper._currentMultiSelection = activeMap
				wrapper._currentMultiOrder = orderedList
				if type(userCallback) == "function" then
					userCallback(activeMap, orderedList)
				end
			else
				wrapper._currentSingleSelection = type(val) == "string" and val or nil
				if type(userCallback) == "function" then
					userCallback(wrapper._currentSingleSelection)
				end
			end
		end,
	}, flag)

	wrapper._raw = rawDropdown
	attachTooltip(rawDropdown, cfg.Tooltip)
	attachBadge(rawDropdown, cfg.Badge)
	if not cfg._isInternalConfig and self._hub and type(self._hub.RegisterFeature) == "function" then
		self._hub:RegisterFeature({
			Name = title,
			Type = "Dropdown",
			TabTitle = self._tabTitle or "General",
			Tab = self._tab,
			SectionTitle = self._currentSectionHeader or "Main",
			Wrapper = wrapper,
			Raw = rawDropdown,
			GetValue = function() return wrapper:Get() end,
			SetValue = function(v) wrapper:Set(v) end,
		})
	end
	return wrapper
end

function SectionWrapperProto:SegmentedControl(cfg)
	cfg = cfg or {}
	local title = cfg.Title or cfg.Name
	local desc = cfg.Description or cfg.Desc or cfg.SubTitle or cfg.SubText
	local flag = self:_ResolveFlag(cfg, title)

	local rawSegmented = self._raw:SegmentedControl({
		Name = title,
		Description = desc,
		Options = cfg.Options or cfg.Values or {},
		Default = cfg.Default or cfg.Value,
		Callback = cfg.Callback,
	}, flag)

	local wrapper = setmetatable({ _raw = rawSegmented, Flag = flag }, SegmentedControlWrapperProto)
	attachTooltip(rawSegmented, cfg.Tooltip)
	attachBadge(rawSegmented, cfg.Badge)
	return wrapper
end

function SectionWrapperProto:Badge(cfg)
	cfg = cfg or {}
	local rawBadge = self._raw:Badge(cfg)
	local wrapper = setmetatable({ _raw = rawBadge }, BadgeWrapperProto)
	return wrapper
end

function SectionWrapperProto:History(cfg)
	cfg = cfg or {}
	local items = cfg.Items or cfg.Entries or (type(cfg) == "table" and not cfg.Items and cfg) or {}
	local rawHistory = self._raw:History({
		Items = items,
		MaxEntries = cfg.MaxEntries,
	}, cfg.Flag)
	local wrapper = setmetatable({ _raw = rawHistory }, HistoryWrapperProto)
	return wrapper
end

function SectionWrapperProto:HistoryLog(cfg)
	return self:History(cfg)
end

function SectionWrapperProto:Keybind(cfg)
	cfg = cfg or {}
	local title = tostring(cfg.Title or cfg.Name or "Keybind")
	local desc = cfg.Description or cfg.Desc or cfg.SubTitle or cfg.SubText
	local defaultKey = cfg.Value or cfg.Default
	local userCallback = cfg.Callback
	local userOnBinded = cfg.onBinded
	local flag = self:_ResolveFlag(cfg, title)

	local rawKeybind = self._raw:Keybind({
		Name = title,
		Description = desc,
		Default = defaultKey,
		Callback = function(binded)
			if type(userCallback) == "function" then
				userCallback(binded)
			end
		end,
		onBinded = function(bind)
			if type(userOnBinded) == "function" then
				userOnBinded(bind)
			elseif type(userCallback) == "function" then
				userCallback(bind)
			end
		end,
	}, flag)

	local wrapper = setmetatable({ _raw = rawKeybind, Flag = flag }, KeybindWrapperProto)
	attachTooltip(rawKeybind, cfg.Tooltip)
	attachBadge(rawKeybind, cfg.Badge)
	return wrapper
end

function SectionWrapperProto:Colorpicker(cfg)
	cfg = cfg or {}
	local title = tostring(cfg.Title or cfg.Name or "Colorpicker")
	local desc = cfg.Description or cfg.Desc or cfg.SubTitle or cfg.SubText
	local defColor = cfg.Default or cfg.Value or Color3.fromRGB(255, 255, 255)
	local defAlpha = cfg.Alpha or cfg.Transparency or 1
	local userCallback = cfg.Callback
	local flag = self:_ResolveFlag(cfg, title)

	local rawCol = self._raw:Colorpicker({
		Name = title,
		Description = desc,
		Default = defColor,
		Alpha = defAlpha,
		Callback = function(col, alpha)
			if type(userCallback) == "function" then
				userCallback(col, alpha or 1)
			end
		end,
	}, flag)

	attachTooltip(rawCol, cfg.Tooltip)
	attachBadge(rawCol, cfg.Badge)
	return setmetatable({ _raw = rawCol, Flag = flag }, ColorpickerWrapperProto)
end

-- Section Factory
local function wrapSection(hub, rawSection, initialHeaderText, tabWrapper, icon)
	local currentSectionHeader = type(initialHeaderText) == "string" and initialHeaderText or ""
	if currentSectionHeader ~= "" then
		pcall(function()
			rawSection:Header({
				Name = currentSectionHeader,
				Text = currentSectionHeader,
				Icon = icon,
			})
		end)
	end

	return setmetatable({
		_hub = hub,
		_raw = rawSection,
		_tab = tabWrapper,
		_tabTitle = (tabWrapper and tabWrapper._title) or "General",
		_currentSectionHeader = currentSectionHeader,
	}, SectionWrapperProto)
end

-- ============================================================
-- TAB WRAPPER PROTOTYPE
-- ============================================================
local TabWrapperProto = {}
TabWrapperProto.__index = TabWrapperProto

function TabWrapperProto:_EnsureCurrentSection()
	if not self._currentSection then
		local side = self._nextSide
		self._nextSide = (side == "Left") and "Right" or "Left"
		local rawSec = self._raw:Section({ Side = side })
		self._currentSection = wrapSection(self._hub, rawSec, nil, self)
	end
	return self._currentSection
end

function TabWrapperProto:Section(cfg)
	cfg = cfg or {}
	local title = cfg.Title or cfg.Name or cfg.Text
	local icon = cfg.Icon or cfg.Image
	local side = cfg.Side
	if side ~= "Left" and side ~= "Right" then
		side = self._nextSide
		self._nextSide = (side == "Left") and "Right" or "Left"
	end
	local rawSec = self._raw:Section({ Side = side })
	local secWrapper = wrapSection(self._hub, rawSec, title, self, icon)
	self._currentSection = secWrapper
	return secWrapper
end

function TabWrapperProto:Select()
	pcall(function() self._raw:Select() end)
end

function TabWrapperProto:Divider()
	return self:_EnsureCurrentSection():Divider()
end

function TabWrapperProto:Spacer()
	return self:_EnsureCurrentSection():Spacer()
end

function TabWrapperProto:Header(cfg)
	return self:_EnsureCurrentSection():Header(cfg)
end

function TabWrapperProto:Label(cfg)
	return self:_EnsureCurrentSection():Label(cfg)
end

function TabWrapperProto:SubLabel(cfg)
	return self:_EnsureCurrentSection():SubLabel(cfg)
end

function TabWrapperProto:Paragraph(cfg)
	return self:_EnsureCurrentSection():Paragraph(cfg)
end

function TabWrapperProto:MetricGrid(cfg)
	return self:_EnsureCurrentSection():MetricGrid(cfg)
end

function TabWrapperProto:StatGrid(cfg)
	return self:_EnsureCurrentSection():MetricGrid(cfg)
end

function TabWrapperProto:ButtonRow(buttonsList)
	return self:_EnsureCurrentSection():ButtonRow(buttonsList)
end

function TabWrapperProto:Button(cfg)
	return self:_EnsureCurrentSection():Button(cfg)
end

function TabWrapperProto:Toggle(cfg)
	return self:_EnsureCurrentSection():Toggle(cfg)
end

function TabWrapperProto:Slider(cfg)
	return self:_EnsureCurrentSection():Slider(cfg)
end

function TabWrapperProto:Input(cfg)
	return self:_EnsureCurrentSection():Input(cfg)
end

function TabWrapperProto:MultiDropdown(cfg)
	return self:_EnsureCurrentSection():MultiDropdown(cfg)
end

function TabWrapperProto:Dropdown(cfg)
	return self:_EnsureCurrentSection():Dropdown(cfg)
end

function TabWrapperProto:Keybind(cfg)
	return self:_EnsureCurrentSection():Keybind(cfg)
end

function TabWrapperProto:Colorpicker(cfg)
	return self:_EnsureCurrentSection():Colorpicker(cfg)
end

function TabWrapperProto:Checkbox(cfg)
	return self:_EnsureCurrentSection():Checkbox(cfg)
end

function TabWrapperProto:ProgressBar(cfg)
	return self:_EnsureCurrentSection():ProgressBar(cfg)
end

function TabWrapperProto:SegmentedControl(cfg)
	return self:_EnsureCurrentSection():SegmentedControl(cfg)
end

function TabWrapperProto:Badge(cfg)
	return self:_EnsureCurrentSection():Badge(cfg)
end

function TabWrapperProto:History(cfg)
	return self:_EnsureCurrentSection():History(cfg)
end

function TabWrapperProto:HistoryLog(cfg)
	return self:_EnsureCurrentSection():History(cfg)
end

-- Tab Factory
local function wrapTab(hub, rawTab, tabTitle)
	return setmetatable({
		_hub = hub,
		_raw = rawTab,
		_title = tabTitle or "Tab",
		_nextSide = "Left",
		_currentSection = nil,
	}, TabWrapperProto)
end

return {
	wrapSection = wrapSection,
	wrapTab = wrapTab,
}

end

-- Module: components/Channel
__modules["components/Channel"] = function()
-- components/Channel.luau
-- Standalone, Modular Navigation Channel / Tab Component for Shenky Hub
-- Manages individual navigation channel items with Active Indicator Bar & Hover States

local TweenService = game:GetService("TweenService")

local Theme = __require("components/Theme")
local icons = __require("assets/icons")
local resolveIcon = icons.Resolve



local Channel = {}
Channel.__index = Channel

function Channel.new(category, rawTab, wrappedTab, config, buttonInstance)
	local self = setmetatable({}, Channel)
	self.Category = category
	self.Sidebar = category and category.Sidebar
	self.RawTab = rawTab
	self.WrappedTab = wrappedTab
	self.Title = tostring(config.Title or config.Name or "Tab")
	self.Icon = config.Icon or config.Image
	self.Button = buttonInstance
	self.IsActive = false

	-- Locate sub-elements if button is provided
	self._activeIndicator = nil
	self._tabImage = nil
	self._nameLabel = nil

	if self.Button then
		self._activeIndicator = self.Button:FindFirstChild("ActiveIndicator", true)
		self._tabImage = self.Button:FindFirstChild("TabImage", true)
		self._nameLabel = self.Button:FindFirstChild("TabSwitcherName", true)
	end

	-- Two-way binding with wrapped tab instance
	if wrappedTab then
		wrappedTab.Channel = self
		wrappedTab.TabItem = self
		wrappedTab.Select = function()
			self:Select()
		end
	end

	return self
end

function Channel:Select()
	if self.RawTab and type(self.RawTab.Select) == "function" then
		pcall(function()
			self.RawTab:Select()
		end)
	end
	if self.Sidebar then
		self.Sidebar.ActiveChannel = self
		self.Sidebar.ActiveTab = self
	end
	self.IsActive = true
end

function Channel:SetVisible(visible)
	if self.Button and self.Button:IsA("GuiObject") then
		self.Button.Visible = (visible == true)
	end
end

function Channel:SetTitle(title)
	self.Title = tostring(title)
	if self._nameLabel then
		self._nameLabel.Text = self.Title
	elseif self.Button then
		local lbl = self.Button:FindFirstChild("TabSwitcherName", true)
		if lbl and lbl:IsA("TextLabel") then
			lbl.Text = self.Title
		end
	end
end

function Channel:SetIcon(icon)
	self.Icon = icon
	local resolved = resolveIcon(icon)
	if self._tabImage then
		self._tabImage.Image = resolved
	elseif self.Button then
		local img = self.Button:FindFirstChild("TabImage", true)
		if img and img:IsA("ImageLabel") then
			img.Image = resolved
		end
	end
end

function Channel:GetContainer()
	return self.WrappedTab
end

return Channel

end

-- Module: components/MetricGrid
__modules["components/MetricGrid"] = function()
-- components/MetricGrid.luau
-- Standalone, Modular Metric Grid & Stat Tiles Component for Shenky Hub
-- Features responsive column rows, large bold numeric typography, subtle hairlines, and reactive update APIs

local Theme = __require("components/Theme")

local MetricGrid = {}
MetricGrid.__index = MetricGrid





function MetricGrid.new(parent, settings, flag, library)
	local self = setmetatable({}, MetricGrid)
	self.Settings = settings or {}
	self.Flag = flag
	self.Class = "MetricGrid"
	self.Columns = tonumber(self.Settings.Columns) or 3
	self.Tiles = {}
	self.TilesByKey = {}

	local rawItems = self.Settings.Items or self.Settings.Tiles or {}

	-- Root Container Frame (Auto-sizes vertically)
	local container = Instance.new("Frame")
	container.Name = "MetricGrid"
	container.BorderSizePixel = 0
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = parent

	local rootList = Instance.new("UIListLayout")
	rootList.Name = "MetricGridListLayout"
	rootList.SortOrder = Enum.SortOrder.LayoutOrder
	rootList.Padding = UDim.new(0, 6)
	rootList.Parent = container

	self.Instance = container
	self.RootLayout = rootList

	-- Build Tiles
	self:_BuildTiles(rawItems)

	if flag and library and type(library.Options) == "table" then
		library.Options[flag] = self
	end

	return self
end

function MetricGrid:_CreateTileInstance(itemCfg, widthScale, widthOffset, parentRow)
	local key = tostring(itemCfg.Key or itemCfg.Title or itemCfg.Label or (#self.Tiles + 1))
	local labelText = tostring(itemCfg.Title or itemCfg.Label or "")
	local valText = tostring(itemCfg.Value or "")

	local tileBtn = Instance.new("TextButton")
	tileBtn.Name = "MetricTile_" .. key
	tileBtn.AutoButtonColor = false
	tileBtn.Text = ""
	tileBtn.BackgroundColor3 = Theme.Colors.CardBg
	tileBtn.BackgroundTransparency = Theme.Colors.CardTransIdle
	tileBtn.BorderSizePixel = 0
	tileBtn.Size = UDim2.new(widthScale, widthOffset, 1, 0)
	tileBtn.Parent = parentRow

	local corner = Instance.new("UICorner")
	corner.Name = "TileUICorner"
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = tileBtn

	local stroke = Instance.new("UIStroke")
	stroke.Name = "TileUIStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = Theme.Geometry.StrokeThickness
	stroke.Color = Theme.Colors.StrokeColor
	stroke.Transparency = Theme.Colors.StrokeTransIdle
	stroke.Parent = tileBtn

	local pad = Instance.new("UIPadding")
	pad.Name = "TilePadding"
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 7)
	pad.PaddingRight = UDim.new(0, 7)
	pad.Parent = tileBtn

	local tileList = Instance.new("UIListLayout")
	tileList.Name = "TileListLayout"
	tileList.SortOrder = Enum.SortOrder.LayoutOrder
	tileList.Padding = UDim.new(0, 2)
	tileList.Parent = tileBtn

	-- Large Numeric / Status Value (Auto-scales to prevent any ellipsis truncation)
	local valLabel = Instance.new("TextLabel")
	valLabel.Name = "MetricValue"
	valLabel.LayoutOrder = 1
	valLabel.BackgroundTransparency = 1
	valLabel.BorderSizePixel = 0
	valLabel.Size = UDim2.new(1, 0, 0, 18)
	valLabel.FontFace = Theme.GetFont(Enum.FontWeight.Bold)
	valLabel.TextColor3 = Theme.Colors.TextPrimary
	valLabel.TextTransparency = 0.05
	valLabel.TextXAlignment = Enum.TextXAlignment.Left
	valLabel.TextYAlignment = Enum.TextYAlignment.Center
	valLabel.TextScaled = true
	valLabel.TextTruncate = Enum.TextTruncate.None
	valLabel.Text = valText

	local valConstraint = Instance.new("UITextSizeConstraint")
	valConstraint.Name = "MetricValueConstraint"
	valConstraint.MaxTextSize = 16
	valConstraint.MinTextSize = 9
	valConstraint.Parent = valLabel

	valLabel.Parent = tileBtn

	-- Caption Label (Auto-scales to ensure labels never truncate to ellipsis)
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "MetricLabel"
	titleLabel.LayoutOrder = 2
	titleLabel.BackgroundTransparency = 1
	titleLabel.BorderSizePixel = 0
	titleLabel.Size = UDim2.new(1, 0, 0, 14)
	titleLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
	titleLabel.TextColor3 = Theme.Colors.TextMuted
	titleLabel.TextTransparency = 0.40
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center
	titleLabel.TextScaled = true
	titleLabel.TextTruncate = Enum.TextTruncate.None
	titleLabel.Text = labelText

	local lblConstraint = Instance.new("UITextSizeConstraint")
	lblConstraint.Name = "MetricLabelConstraint"
	lblConstraint.MaxTextSize = 11
	lblConstraint.MinTextSize = 8
	lblConstraint.Parent = titleLabel

	titleLabel.Parent = tileBtn

	-- Subtle Hover Feedback
	tileBtn.MouseEnter:Connect(function()
		Theme.Tween(tileBtn, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			BackgroundTransparency = Theme.Colors.CardTransHover,
		})
		Theme.Tween(stroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			Color = Theme.Colors.StrokeColorHover,
			Transparency = Theme.Colors.StrokeTransHover,
		})
	end)

	tileBtn.MouseLeave:Connect(function()
		Theme.Tween(tileBtn, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			BackgroundTransparency = Theme.Colors.CardTransIdle,
		})
		Theme.Tween(stroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			Color = Theme.Colors.StrokeColor,
			Transparency = Theme.Colors.StrokeTransIdle,
		})
	end)

	local tileObj = {
		Key = key,
		Instance = tileBtn,
		Stroke = stroke,
		ValueLabel = valLabel,
		TitleLabel = titleLabel,
		Update = function(newVal, newLbl)
			if newVal ~= nil then
				local sVal = tostring(newVal)
				if valLabel.Text ~= sVal then
					valLabel.Text = sVal
				end
			end
			if newLbl ~= nil then
				local sLbl = tostring(newLbl)
				if titleLabel.Text ~= sLbl then
					titleLabel.Text = sLbl
				end
			end
		end,
		Set = function(newVal)
			if newVal ~= nil then
				local sVal = tostring(newVal)
				if valLabel.Text ~= sVal then
					valLabel.Text = sVal
				end
			end
		end,
	}

	table.insert(self.Tiles, tileObj)
	self.TilesByKey[key] = tileObj
	return tileObj
end

function MetricGrid:_BuildTiles(items)
	local cols = self.Columns
	local total = #items
	if total == 0 then return end

	local currentRow = nil
	local colIndex = 0
	local rowIndex = 1

	for i, item in ipairs(items) do
		colIndex = colIndex + 1
		if not currentRow or colIndex > cols then
			colIndex = 1
			currentRow = Instance.new("Frame")
			currentRow.Name = "MetricRow_" .. rowIndex
			currentRow.LayoutOrder = rowIndex
			currentRow.BorderSizePixel = 0
			currentRow.BackgroundTransparency = 1
			currentRow.Size = UDim2.new(1, 0, 0, 50)
			currentRow.Parent = self.Instance

			local rowList = Instance.new("UIListLayout")
			rowList.Name = "RowListLayout"
			rowList.FillDirection = Enum.FillDirection.Horizontal
			rowList.SortOrder = Enum.SortOrder.LayoutOrder
			rowList.Padding = UDim.new(0, 6)
			rowList.Parent = currentRow

			rowIndex = rowIndex + 1
		end

		local widthScale = 1 / cols
		local widthOffset = -math.floor(6 * (cols - 1) / cols + 0.5)
		self:_CreateTileInstance(item, widthScale, widthOffset, currentRow)
	end
end

function MetricGrid:Update(keyOrIndex, newValue, newLabel)
	local tile = nil
	if type(keyOrIndex) == "number" then
		tile = self.Tiles[keyOrIndex]
	else
		tile = self.TilesByKey[tostring(keyOrIndex)]
	end

	if tile then
		tile.Update(newValue, newLabel)
		return true
	end
	return false
end

function MetricGrid:Set(keyOrIndex, newValue)
	return self:Update(keyOrIndex, newValue)
end

function MetricGrid:GetTile(keyOrIndex)
	if type(keyOrIndex) == "number" then
		return self.Tiles[keyOrIndex]
	else
		return self.TilesByKey[tostring(keyOrIndex)]
	end
end

function MetricGrid:SetVisibility(state)
	if self.Instance then
		self.Instance.Visible = state
	end
end

function MetricGrid:Destroy()
	if self.Instance then
		self.Instance:Destroy()
	end
end

return MetricGrid

end

-- Module: components/Toast
__modules["components/Toast"] = function()
-- components/Toast.luau
-- Standalone, Luxury Toast Notification System for Shenky Hub
-- Features stacking banner notifications, status-coded accents, Lucide icon badges, animated countdown bars, and spring transitions

local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local Theme = __require("components/Theme")

local Toast = {
	_gui = nil,
	_container = nil,
	_activeToasts = {},
	_notifCache = {},
	_layoutCounter = 0,
	_watchdogConn = nil,
}

function Toast:_StartWatchdog()
	if self._watchdogConn then return end
	local RunService = game:GetService("RunService")
	self._watchdogConn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local i = 1
		while i <= #self._activeToasts do
			local item = self._activeToasts[i]
			if item and item.ExpireTime and now >= item.ExpireTime then
				if item.Dismiss then
					item.Dismiss()
				end
			end
			i = i + 1
		end
		if #self._activeToasts == 0 and self._watchdogConn then
			self._watchdogConn:Disconnect()
			self._watchdogConn = nil
		end
	end)
end

local ICONS = {
	success = "rbxassetid://10709790644",       -- check
	info = "rbxassetid://10723415903",          -- info
	warning = "rbxassetid://10709753149",       -- alert-triangle
	error = "rbxassetid://10709752996",         -- alert-circle
	bell = "rbxassetid://10709775704",          -- bell
	link = "rbxassetid://10723426722",          -- link
	close = "rbxassetid://10747384394",         -- x
}

local ACCENTS = {
	success = Color3.fromRGB(74, 222, 128),     -- Emerald Green
	info = Color3.fromRGB(160, 185, 255),        -- Soft Lavender Brand Accent
	warning = Color3.fromRGB(245, 158, 11),      -- Amber Gold
	error = Color3.fromRGB(244, 63, 94),         -- Rose Red
}

function Toast.PurgeStale()
	local function purgeToasts(p)
		if not p then return end
		pcall(function()
			for _, c in ipairs(p:GetChildren()) do
				if c.Name == "ShenkyToasts" then
					c:Destroy()
				end
			end
		end)
	end

	pcall(function()
		local cg = game:GetService("CoreGui")
		purgeToasts(cg)
		if cg then purgeToasts(cg:FindFirstChild("RobloxGui")) end
	end)
	pcall(function()
		local lp = game:GetService("Players").LocalPlayer
		if lp then purgeToasts(lp:FindFirstChild("PlayerGui")) end
	end)
	pcall(function()
		if gethui then
			local h = gethui()
			purgeToasts(h)
			if h and h.Parent then purgeToasts(h.Parent) end
		end
	end)
end

-- Immediately purge any lingering toasts from prior runs upon load
pcall(Toast.PurgeStale)

function Toast:_EnsureContainer()
	local isAlive = false
	pcall(function()
		if self._gui and self._gui.Parent and self._container and self._container.Parent then
			isAlive = true
		end
	end)
	if isAlive then
		return self._container
	end

	self._gui = nil
	self._container = nil

	self:PurgeStale()

	local targetParent = nil
	pcall(function()
		if gethui then
			local h = gethui()
			if h and typeof(h) == "Instance" then
				targetParent = h
			end
		end
	end)
	if not targetParent then
		pcall(function()
			targetParent = game:GetService("CoreGui")
		end)
	end
	if not targetParent then
		pcall(function()
			local lp = game:GetService("Players").LocalPlayer
			targetParent = lp and lp:FindFirstChild("PlayerGui")
		end)
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ShenkyToasts"
	screenGui.DisplayOrder = 999999
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local container = Instance.new("Frame")
	container.Name = "ToastStack"
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.AnchorPoint = Vector2.new(1, 0)
	container.Position = UDim2.new(1, -20, 0, 58)
	container.Size = UDim2.new(0, 310, 1, -78)
	container.ClipsDescendants = false
	container.Parent = screenGui

	local list = Instance.new("UIListLayout")
	list.Name = "ToastListLayout"
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = container

	pcall(function()
		screenGui.Parent = targetParent
	end)

	self._gui = screenGui
	self._container = container
	return container
end

-- type ToastOptions

function Toast:Show(options, desc, toastType, lifetime)
	local title = "Notification"
	local description = ""
	local tType = "info"
	local iconId = nil
	local duration = 4.0

	if type(options) == "table" then
		title = tostring(options.Title or options.Name or "Notification")
		description = tostring(options.Description or options.Desc or options.Content or "")
		local rawType = options.Type or options.Style or options.Variant or options.Status or options.Kind
		if rawType then
			tType = string.lower(tostring(rawType))
		else
			tType = "info"
		end
		if tType == "confirm" or tType == "ok" or tType == "pass" then
			tType = "success"
		elseif tType == "danger" or tType == "fatal" or tType == "critical" or tType == "err" then
			tType = "error"
		elseif tType == "warn" or tType == "alert" then
			tType = "warning"
		end
		iconId = options.Icon or options.Image
		duration = tonumber(options.Lifetime or options.Duration) or 4.0
	elseif type(options) == "string" then
		title = options
		description = tostring(desc or "")
		if toastType then
			tType = string.lower(tostring(toastType))
			if tType == "confirm" or tType == "ok" then
				tType = "success"
			elseif tType == "danger" or tType == "fatal" or tType == "err" then
			tType = "error"
			elseif tType == "warn" then
				tType = "warning"
			end
		end
		if lifetime then duration = tonumber(lifetime) or 4.0 end
	end

	-- Infer type from title if default info
	if tType == "info" then
		local lowerT = string.lower(title .. " " .. description)
		if string.find(lowerT, "copied") or string.find(lowerT, "saved") or string.find(lowerT, "success") or string.find(lowerT, "loaded") or string.find(lowerT, "enabled") then
			tType = "success"
		elseif string.find(lowerT, "fail") or string.find(lowerT, "error") or string.find(lowerT, "unable") or string.find(lowerT, "blocked") then
			tType = "error"
		elseif string.find(lowerT, "warn") or string.find(lowerT, "caution") or string.find(lowerT, "bypass") then
			tType = "warning"
		end
	end

	local accentColor = ACCENTS[tType] or ACCENTS.info

	-- Anti-spam debounce (0.75s threshold for identical message)
	local cacheKey = title .. "::" .. description
	local now = os.clock()
	if self._notifCache[cacheKey] and (now - self._notifCache[cacheKey]) < 0.75 then
		return
	end
	self._notifCache[cacheKey] = now

	local container = self:_EnsureContainer()
	if not container then return end

	-- Maximum stack capacity: dismiss oldest if > 5 toasts
	if #self._activeToasts >= 5 then
		local oldest = table.remove(self._activeToasts, 1)
		if oldest and oldest.Dismiss then
			oldest.Dismiss()
		end
	end

	self._layoutCounter = self._layoutCounter + 1

	-- 1. Outer Wrapper Card (Clips descendants so progress bar is cleanly rounded)
	local card = Instance.new("Frame")
	card.Name = "ToastCard_" .. self._layoutCounter
	card.LayoutOrder = self._layoutCounter
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	card.BackgroundTransparency = 0.06
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.Parent = container

	local corner = Instance.new("UICorner")
	corner.Name = "ToastCorner"
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Name = "ToastStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 1.0
	stroke.Color = accentColor
	stroke.Transparency = 0.65
	stroke.Parent = card

	local cardScale = Instance.new("UIScale")
	cardScale.Name = "ToastScale"
	cardScale.Scale = 0.88
	cardScale.Parent = card

	-- 2. Dedicated Inner Content Container (Guarantees bottom padding is isolated from progress bar)
	local inner = Instance.new("Frame")
	inner.Name = "ToastInner"
	inner.BackgroundTransparency = 1
	inner.BorderSizePixel = 0
	inner.Size = UDim2.new(1, 0, 0, 0)
	inner.AutomaticSize = Enum.AutomaticSize.Y
	inner.Parent = card

	local padding = Instance.new("UIPadding")
	padding.Name = "ToastPadding"
	padding.PaddingTop = UDim.new(0, 11)
	padding.PaddingBottom = UDim.new(0, 15) -- Full 15px clearance above the 2px progress bar!
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = inner

	-- Horizontal Content Row
	local contentRow = Instance.new("Frame")
	contentRow.Name = "ContentRow"
	contentRow.BackgroundTransparency = 1
	contentRow.BorderSizePixel = 0
	contentRow.Size = UDim2.new(1, 0, 0, 0)
	contentRow.AutomaticSize = Enum.AutomaticSize.Y
	contentRow.Parent = inner

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.Name = "RowLayout"
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.Parent = contentRow

	-- 3. Icon Badge Container
	local iconBadge = Instance.new("Frame")
	iconBadge.Name = "IconBadge"
	iconBadge.LayoutOrder = 1
	iconBadge.Size = UDim2.fromOffset(26, 26)
	iconBadge.BackgroundColor3 = accentColor
	iconBadge.BackgroundTransparency = 0.85
	iconBadge.BorderSizePixel = 0
	iconBadge.Parent = contentRow

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 6)
	badgeCorner.Parent = iconBadge

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = accentColor
	badgeStroke.Transparency = 0.60
	badgeStroke.Thickness = 1.0
	badgeStroke.Parent = iconBadge

	-- Resolve Icon Asset
	local resolvedIcon = ICONS[tType] or ICONS.info
	if iconId then
		if typeof(iconId) == "number" then
			resolvedIcon = "rbxassetid://" .. tostring(iconId)
		elseif typeof(iconId) == "string" and iconId ~= "" then
			if string.find(iconId, "rbxassetid://") then
				resolvedIcon = iconId
			else
				local IconsModule = (getgenv and getgenv().__SHENKY_ICONS)
				if IconsModule and IconsModule.Resolve then
					resolvedIcon = IconsModule.Resolve(iconId) or resolvedIcon
				end
			end
		end
	end

	local iconImg = Instance.new("ImageLabel")
	iconImg.Name = "Icon"
	iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
	iconImg.Position = UDim2.fromScale(0.5, 0.5)
	iconImg.Size = UDim2.fromOffset(15, 15)
	iconImg.BackgroundTransparency = 1
	iconImg.Image = resolvedIcon
	iconImg.ImageColor3 = accentColor
	iconImg.ScaleType = Enum.ScaleType.Fit
	iconImg.Parent = iconBadge

	-- 4. Text Block (Title & Description)
	local textBlock = Instance.new("Frame")
	textBlock.Name = "TextBlock"
	textBlock.LayoutOrder = 2
	textBlock.BackgroundTransparency = 1
	textBlock.BorderSizePixel = 0
	textBlock.Size = UDim2.new(1, -62, 0, 0)
	textBlock.AutomaticSize = Enum.AutomaticSize.Y
	textBlock.Parent = contentRow

	local textList = Instance.new("UIListLayout")
	textList.Name = "TextListLayout"
	textList.SortOrder = Enum.SortOrder.LayoutOrder
	textList.Padding = UDim.new(0, 3)
	textList.Parent = textBlock

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "ToastTitle"
	titleLabel.LayoutOrder = 1
	titleLabel.BackgroundTransparency = 1
	titleLabel.BorderSizePixel = 0
	titleLabel.Size = UDim2.new(1, 0, 0, 16)
	titleLabel.FontFace = Theme.GetFont(Enum.FontWeight.SemiBold)
	titleLabel.Text = title
	titleLabel.TextSize = 13
	titleLabel.TextColor3 = Theme.Colors.TextPrimary
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Parent = textBlock

	local descLabel = nil
	if description ~= "" then
		descLabel = Instance.new("TextLabel")
		descLabel.Name = "ToastDesc"
		descLabel.LayoutOrder = 2
		descLabel.BackgroundTransparency = 1
		descLabel.BorderSizePixel = 0
		descLabel.Size = UDim2.new(1, 0, 0, 0)
		descLabel.AutomaticSize = Enum.AutomaticSize.Y
		descLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
		descLabel.Text = description
		descLabel.TextSize = 11
		descLabel.TextColor3 = Theme.Colors.TextMuted
		descLabel.TextTransparency = 0.25
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextWrapped = true
		descLabel.Parent = textBlock
	end

	-- 5. Close Button (Lucide X ImageButton with crisp hover feedback)
	local closeBtn = Instance.new("ImageButton")
	closeBtn.Name = "CloseButton"
	closeBtn.LayoutOrder = 3
	closeBtn.AutoButtonColor = false
	closeBtn.BackgroundTransparency = 1
	closeBtn.BorderSizePixel = 0
	closeBtn.Size = UDim2.fromOffset(14, 14)
	closeBtn.Image = ICONS.close
	closeBtn.ImageColor3 = Theme.Colors.TextMuted
	closeBtn.ImageTransparency = 0.40
	closeBtn.Parent = contentRow

	closeBtn.MouseEnter:Connect(function()
		Theme.Tween(closeBtn, TweenInfo.new(0.15), { ImageColor3 = Theme.Colors.TextPrimary, ImageTransparency = 0.0 })
	end)
	closeBtn.MouseLeave:Connect(function()
		Theme.Tween(closeBtn, TweenInfo.new(0.15), { ImageColor3 = Theme.Colors.TextMuted, ImageTransparency = 0.40 })
	end)

	-- 6. Countdown Progress Bar at Bottom of Card (Completely separate from inner text padding)
	local progressBar = Instance.new("Frame")
	progressBar.Name = "ProgressBar"
	progressBar.BorderSizePixel = 0
	progressBar.AnchorPoint = Vector2.new(0, 1)
	progressBar.Position = UDim2.new(0, 0, 1, 0)
	progressBar.Size = UDim2.new(1, 0, 0, 2)
	progressBar.BackgroundColor3 = accentColor
	progressBar.BackgroundTransparency = 0.25
	progressBar.Parent = card

	-- Lifecycle Controller
	local isDismissed = false
	local function dismiss()
		if isDismissed then return end
		isDismissed = true

		local function cleanupActive()
			for i, v in ipairs(self._activeToasts) do
				if v.Card == card then
					table.remove(self._activeToasts, i)
					break
			end
			end
			pcall(function() card:Destroy() end)
		end

		local okTween = pcall(function()
			local twPos = TweenService:Create(card, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(1, 40, 0, 0),
			})
			local twOut = TweenService:Create(cardScale, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Scale = 0.80,
			})
			local twFade = TweenService:Create(card, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
			})
			twPos:Play()
		twOut:Play()
		twFade:Play()

			twOut.Completed:Connect(cleanupActive)
		end)

		if not okTween then
			cleanupActive()
		else
			-- Hard fallback timeout: guarantee card destruction even if Tween.Completed drops
			task.delay(0.35, cleanupActive)
		end
	end

	closeBtn.MouseButton1Click:Connect(function()
		dismiss()
	end)

	local toastItem = {
		Card = card,
		Dismiss = dismiss,
		ExpireTime = os.clock() + duration,
		Tweens = {},
	}
	table.insert(self._activeToasts, toastItem)
	self:_StartWatchdog()

	-- 7. Slide-in & Scale Animation
	card.Position = UDim2.new(1, 40, 0, 0)
	pcall(function()
		local enterTween = TweenService:Create(cardScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1.0,
		})
		local posTween = TweenService:Create(card, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, 0, 0, 0),
		})
		enterTween:Play()
		posTween:Play()
	end)
	card.Position = UDim2.new(0, 0, 0, 0)
	cardScale.Scale = 1.0

	-- 8. Progress Bar Countdown Tween (Engine-driven auto-dismiss & GC anchored)
	pcall(function()
		local progressTween = TweenService:Create(progressBar, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
			Size = UDim2.new(0, 0, 0, 2),
		})
		toastItem.Tweens.Progress = progressTween
		progressTween:Play()
		progressTween.Completed:Connect(function()
			if not isDismissed then
				dismiss()
			end
		end)
	end)

	task.delay(duration, function()
		if not isDismissed then
			dismiss()
		end
	end)

	return toastItem
end

function Toast:Success(title, desc, lifetime)
	return self:Show({ Title = title, Description = desc, Type = "success", Lifetime = lifetime })
end

function Toast:Info(title, desc, lifetime)
	return self:Show({ Title = title, Description = desc, Type = "info", Lifetime = lifetime })
end

function Toast:Warning(title, desc, lifetime)
	return self:Show({ Title = title, Description = desc, Type = "warning", Lifetime = lifetime })
end

function Toast:Error(title, desc, lifetime)
	return self:Show({ Title = title, Description = desc, Type = "error", Lifetime = lifetime })
end

return Toast

end

-- Module: components/SegmentedControl
__modules["components/SegmentedControl"] = function()
-- components/SegmentedControl.luau
-- Standalone, Luxury Segmented Control Component for Shenky Hub
-- Provides a sleek horizontal in-card pill selector with spring transitions and reactive callbacks

local Theme = __require("components/Theme")

local SegmentedControl = {}
SegmentedControl.__index = SegmentedControl



function SegmentedControl.new(parent, settings, flag, library)
	local self = setmetatable({}, SegmentedControl)
	self.Settings = settings or {}
	self.Flag = flag
	self.Class = "SegmentedControl"
	self.Options = self.Settings.Options or {}
	self.Selected = nil
	self.Buttons = {}
	self.Strokes = {}

	local titleText = self.Settings.Name or self.Settings.Title
	local descText = self.Settings.Description or self.Settings.Desc
	local hasTitle = (type(titleText) == "string" and titleText ~= "")
	local hasDesc = (type(descText) == "string" and descText ~= "")

	-- 1. Outer Container
	local container = Instance.new("Frame")
	container.Name = "SegmentedControl"
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = parent

	local rootList = Instance.new("UIListLayout")
	rootList.Name = "RootListLayout"
	rootList.SortOrder = Enum.SortOrder.LayoutOrder
	rootList.Padding = UDim.new(0, 5)
	rootList.Parent = container

	-- Header (Title & Description)
	if hasTitle or hasDesc then
		local headerFrame = Instance.new("Frame")
		headerFrame.Name = "HeaderFrame"
		headerFrame.LayoutOrder = 1
		headerFrame.BackgroundTransparency = 1
		headerFrame.BorderSizePixel = 0
		headerFrame.Size = UDim2.new(1, 0, 0, 0)
		headerFrame.AutomaticSize = Enum.AutomaticSize.Y
		headerFrame.Parent = container

		local headerList = Instance.new("UIListLayout")
		headerList.Name = "HeaderList"
		headerList.SortOrder = Enum.SortOrder.LayoutOrder
		headerList.Padding = UDim.new(0, 2)
		headerList.Parent = headerFrame

		if hasTitle then
			local titleLabel = Instance.new("TextLabel")
			titleLabel.Name = "SegmentedTitle"
			titleLabel.LayoutOrder = 1
			titleLabel.BackgroundTransparency = 1
			titleLabel.BorderSizePixel = 0
			titleLabel.Size = UDim2.new(1, 0, 0, 16)
			titleLabel.FontFace = Theme.GetFont(Enum.FontWeight.Medium)
			titleLabel.Text = titleText
			titleLabel.TextSize = 12
			titleLabel.TextColor3 = Theme.Colors.TextPrimary
			titleLabel.TextTransparency = 0.15
			titleLabel.TextXAlignment = Enum.TextXAlignment.Left
			titleLabel.Parent = headerFrame
		end

		if hasDesc then
			local descLabel = Instance.new("TextLabel")
			descLabel.Name = "SegmentedDesc"
			descLabel.LayoutOrder = 2
			descLabel.BackgroundTransparency = 1
			descLabel.BorderSizePixel = 0
			descLabel.Size = UDim2.new(1, 0, 0, 0)
			descLabel.AutomaticSize = Enum.AutomaticSize.Y
			descLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
			descLabel.Text = descText
			descLabel.TextSize = 11
			descLabel.TextColor3 = Theme.Colors.TextMuted
			descLabel.TextTransparency = 0.35
			descLabel.TextXAlignment = Enum.TextXAlignment.Left
			descLabel.TextWrapped = true
			descLabel.Parent = headerFrame
		end
	end

	-- 2. Capsule Track Container
	local track = Instance.new("Frame")
	track.Name = "SegmentedTrack"
	track.LayoutOrder = 2
	track.BackgroundColor3 = Theme.Colors.CardBg
	track.BackgroundTransparency = 0.95
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, 0, 0, 26)
	track.Parent = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 6)
	trackCorner.Parent = track

	local trackStroke = Instance.new("UIStroke")
	trackStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	trackStroke.Thickness = Theme.Geometry.StrokeThickness
	trackStroke.Color = Theme.Colors.StrokeColor
	trackStroke.Transparency = 0.90
	trackStroke.Parent = track

	local trackPadding = Instance.new("UIPadding")
	trackPadding.PaddingTop = UDim.new(0, 2)
	trackPadding.PaddingBottom = UDim.new(0, 2)
	trackPadding.PaddingLeft = UDim.new(0, 2)
	trackPadding.PaddingRight = UDim.new(0, 2)
	trackPadding.Parent = track

	local trackLayout = Instance.new("UIListLayout")
	trackLayout.Name = "TrackLayout"
	trackLayout.FillDirection = Enum.FillDirection.Horizontal
	trackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	trackLayout.Padding = UDim.new(0, 2)
	trackLayout.Parent = track

	self.Instance = container
	self.Track = track

	-- Build Options
	self:_BuildButtons()

	-- Set Initial Value
	local def = self.Settings.Default or (self.Options and self.Options[1])
	if def then
		self:Set(def, true)
	end

	if flag and library and type(library.Options) == "table" then
		library.Options[flag] = self
	end

	return self
end

function SegmentedControl:_BuildButtons()
	for _, btn in pairs(self.Buttons) do
		pcall(btn.Destroy, btn)
	end
	table.clear(self.Buttons)
	table.clear(self.Strokes)

	local count = #self.Options
	if count == 0 then return end

	for i, optName in ipairs(self.Options) do
		local btn = Instance.new("TextButton")
		btn.Name = "Opt_" .. tostring(optName)
		btn.LayoutOrder = i
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(1 / count, -2, 1, 0)
		btn.FontFace = Theme.GetFont(Enum.FontWeight.SemiBold)
		btn.Text = tostring(optName)
		btn.TextSize = 11
		btn.TextColor3 = Theme.Colors.TextMuted
		btn.TextTransparency = 0.35
		btn.TextTruncate = Enum.TextTruncate.AtEnd
		btn.Parent = self.Track

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 5)
		btnCorner.Parent = btn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		btnStroke.Thickness = 1.0
		btnStroke.Color = Theme.Colors.AccentLavender
		btnStroke.Transparency = 1
		btnStroke.Parent = btn

		btn.MouseEnter:Connect(function()
			if self.Selected ~= optName then
				Theme.Tween(btn, TweenInfo.new(0.15), {
					BackgroundTransparency = 0.96,
					TextTransparency = 0.15,
				})
			end
		end)

		btn.MouseLeave:Connect(function()
			if self.Selected ~= optName then
				Theme.Tween(btn, TweenInfo.new(0.15), {
					BackgroundTransparency = 1,
					TextTransparency = 0.35,
				})
			end
		end)

		btn.MouseButton1Click:Connect(function()
			self:Set(optName)
		end)

		self.Buttons[optName] = btn
		self.Strokes[optName] = btnStroke
	end
end

function SegmentedControl:Set(optionName, skipCallback)
	local prev = self.Selected
	self.Selected = optionName
	self.Value = optionName

	for name, btn in pairs(self.Buttons) do
		local strk = self.Strokes[name]
		if name == optionName then
			Theme.Tween(btn, TweenInfo.new(0.20, Enum.EasingStyle.Quad), {
				BackgroundTransparency = 0.88,
				TextColor3 = Theme.Colors.TextPrimary,
				TextTransparency = 0,
			})
			if strk then
				Theme.Tween(strk, TweenInfo.new(0.20, Enum.EasingStyle.Quad), {
					Transparency = 0.72,
				})
			end
		else
			Theme.Tween(btn, TweenInfo.new(0.20, Enum.EasingStyle.Quad), {
				BackgroundTransparency = 1,
				TextColor3 = Theme.Colors.TextMuted,
				TextTransparency = 0.35,
			})
			if strk then
				Theme.Tween(strk, TweenInfo.new(0.20, Enum.EasingStyle.Quad), {
					Transparency = 1,
				})
			end
		end
	end

	if not skipCallback and prev ~= optionName and type(self.Settings.Callback) == "function" then
		local idx = table.find(self.Options, optionName) or 1
		task.spawn(self.Settings.Callback, optionName, idx)
	end
end

function SegmentedControl:Get()
	return self.Selected
end

function SegmentedControl:GetValue()
	return self.Selected
end

function SegmentedControl:UpdateOptions(newOptions)
	if type(newOptions) == "table" then
		self.Options = newOptions
		self:_BuildButtons()
		local def = self.Selected or newOptions[1]
		if def and table.find(newOptions, def) then
			self:Set(def, true)
		elseif newOptions[1] then
			self:Set(newOptions[1], true)
		end
	end
end

function SegmentedControl:SetVisibility(state)
	if self.Instance then
		self.Instance.Visible = state
	end
end

function SegmentedControl:Destroy()
	if self.Instance then
		self.Instance:Destroy()
	end
end

return SegmentedControl

end

-- Module: components/Badge
__modules["components/Badge"] = function()
-- components/Badge.luau
-- Standalone and Attachable Status Badge Component for Shenky Hub Design System
-- Provides elegant luxury micro-pills (New, Beta, Risky, Safe, Hot, Custom)

local Theme = __require("components/Theme")

local Badge = {}
Badge.__index = Badge

Badge.Variants = {
	Default = {
		Color = Color3.fromRGB(160, 185, 255),
		Bg = Color3.fromRGB(160, 185, 255),
		BgTrans = 0.88,
		StrokeTrans = 0.75,
	},
	New = {
		Color = Color3.fromRGB(56, 189, 248), -- Sky 400
		Bg = Color3.fromRGB(56, 189, 248),
		BgTrans = 0.88,
		StrokeTrans = 0.70,
	},
	Beta = {
		Color = Color3.fromRGB(251, 191, 36), -- Amber 400
		Bg = Color3.fromRGB(251, 191, 36),
		BgTrans = 0.88,
		StrokeTrans = 0.70,
	},
	Risky = {
		Color = Color3.fromRGB(248, 113, 113), -- Red 400
		Bg = Color3.fromRGB(248, 113, 113),
		BgTrans = 0.88,
		StrokeTrans = 0.70,
	},
	Danger = {
		Color = Color3.fromRGB(248, 113, 113),
		Bg = Color3.fromRGB(248, 113, 113),
		BgTrans = 0.88,
		StrokeTrans = 0.70,
	},
	Safe = {
		Color = Color3.fromRGB(74, 222, 128), -- Emerald 400
		Bg = Color3.fromRGB(74, 222, 128),
		BgTrans = 0.88,
		StrokeTrans = 0.70,
	},
	Hot = {
		Color = Color3.fromRGB(217, 70, 239), -- Fuchsia 500
		Bg = Color3.fromRGB(217, 70, 239),
		BgTrans = 0.88,
		StrokeTrans = 0.70,
	},
}



function Badge.new(parent, settings)
	local self = setmetatable({}, Badge)
	local rawSettings 
	if type(settings) == "string" then
		rawSettings = { Text = settings, Variant = settings }
	else
		rawSettings = settings or { Text = "BADGE" }
	end

	local text = tostring(rawSettings.Text or rawSettings.Variant or "BADGE")
	local variantKey = rawSettings.Variant or "Default"
	local preset = Badge.Variants[variantKey] or Badge.Variants.Default
	local color = rawSettings.Color or preset.Color
	local bgTrans = preset.BgTrans
	local strokeTrans = preset.StrokeTrans

	local pill = Instance.new("Frame")
	pill.Name = "Badge_" .. text
	pill.BackgroundColor3 = color
	pill.BackgroundTransparency = bgTrans
	pill.BorderSizePixel = 0
	pill.Size = UDim2.new(0, 0, 0, 16)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.LayoutOrder = rawSettings.LayoutOrder or 99
	pill.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = pill

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 1
	stroke.Color = color
	stroke.Transparency = strokeTrans
	stroke.Parent = pill

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 5)
	padding.PaddingRight = UDim.new(0, 5)
	padding.PaddingTop = UDim.new(0, 0)
	padding.PaddingBottom = UDim.new(0, 0)
	padding.Parent = pill

	local label = Instance.new("TextLabel")
	label.Name = "BadgeText"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.new(0, 0, 1, 0)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.FontFace = Theme.GetFont(Enum.FontWeight.Bold)
	label.Text = string.upper(text)
	label.TextSize = 9
	label.TextColor3 = color
	label.TextTransparency = 0.05
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = pill

	self.Instance = pill
	self.Label = label
	self.Stroke = stroke
	self.Text = text
	return self
end

function Badge:SetText(newText)
	self.Text = tostring(newText or "")
	if self.Label then
		self.Label.Text = string.upper(self.Text)
	end
end

function Badge:SetVariant(variantName)
	local preset = Badge.Variants[variantName] or Badge.Variants.Default
	local color = preset.Color
	if self.Instance then
		self.Instance.BackgroundColor3 = color
		self.Instance.BackgroundTransparency = preset.BgTrans
	end
	if self.Stroke then
		self.Stroke.Color = color
		self.Stroke.Transparency = preset.StrokeTrans
	end
	if self.Label then
		self.Label.TextColor3 = color
	end
end

function Badge:Destroy()
	if self.Instance then
		self.Instance:Destroy()
	end
end

return Badge

end

-- Module: components/Tooltip
__modules["components/Tooltip"] = function()
-- components/Tooltip.luau
-- Global Singleton Floating Tooltip for Shenky Hub Design System
-- Provides smooth hover micro-UX with intelligent viewport clamping and glassmorphism styling

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Theme = __require("components/Theme")

local Tooltip = {}
Tooltip.__index = Tooltip

local _screenGui = nil
local _tooltipCard = nil
local _tooltipLabel = nil
local _tooltipStroke = nil
local _currentHoverTarget = nil
local _hoverToken = 0
local _isVisible = false

local HOVER_DELAY = 0.28

local function getRootGui()
	local hubGui = game:GetService("CoreGui"):FindFirstChild("ShenkyHub", true)
	if not hubGui and gethui then
		hubGui = gethui():FindFirstChild("ShenkyHub", true)
	end
	if hubGui then
		return hubGui
	end

	if _screenGui and _screenGui.Parent then
		return _screenGui
	end

	local localPlayer = Players.LocalPlayer
	local parentGui = nil

	if gethui then
		parentGui = gethui()
	elseif game:GetService("CoreGui"):FindFirstChild("RobloxGui") then
		parentGui = game:GetService("CoreGui")
	elseif localPlayer and localPlayer:FindFirstChild("PlayerGui") then
		parentGui = localPlayer.PlayerGui
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "Shenky_Tooltips"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2147483647
	gui.Parent = parentGui or game:GetService("CoreGui")

	_screenGui = gui
	return gui
end

local function initUI()
	local root = getRootGui()
	if _tooltipCard and _tooltipCard.Parent then
		if root and _tooltipCard.Parent ~= root then
			_tooltipCard.Parent = root
		end
		return
	end

	local card = Instance.new("Frame")
	card.Name = "TooltipCard"
	card.BackgroundColor3 = Color3.fromRGB(15, 17, 24)
	card.BackgroundTransparency = 0.08
	card.BorderSizePixel = 0
	card.Size = UDim2.new(0, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.XY
	card.Visible = false
	card.ZIndex = 999999
	card.Parent = root

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 1
	stroke.Color = Theme.Colors.AccentLavender
	stroke.Transparency = 0.70
	stroke.Parent = card

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.Parent = card

	local contentList = Instance.new("UIListLayout")
	contentList.FillDirection = Enum.FillDirection.Horizontal
	contentList.SortOrder = Enum.SortOrder.LayoutOrder
	contentList.VerticalAlignment = Enum.VerticalAlignment.Center
	contentList.Padding = UDim.new(0, 6)
	contentList.Parent = card

	-- Lucide Info Icon (10747377097 - info)
	local icon = Instance.new("ImageLabel")
	icon.Name = "InfoIcon"
	icon.LayoutOrder = 1
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.Size = UDim2.new(0, 13, 0, 13)
	icon.Image = "rbxassetid://10747377097"
	icon.ImageColor3 = Theme.Colors.AccentLavender
	icon.ImageTransparency = 0.20
	icon.ZIndex = 1000000
	icon.Parent = card

	local label = Instance.new("TextLabel")
	label.Name = "TooltipText"
	label.LayoutOrder = 2
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.new(0, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
	label.Text = ""
	label.TextSize = 11
	label.TextColor3 = Theme.Colors.TextPrimary
	label.TextTransparency = 0.10
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = false
	label.ZIndex = 1000000
	label.Parent = card

	_tooltipCard = card
	_tooltipLabel = label
	_tooltipStroke = stroke
end

function Tooltip.Show(text, targetGui, mousePos)
	initUI()
	if not _tooltipCard or not _tooltipLabel then return end

	_tooltipLabel.Text = tostring(text or "")
	_tooltipCard.Visible = true
	_isVisible = true

	local cardWidth = _tooltipCard.AbsoluteSize.X > 0 and _tooltipCard.AbsoluteSize.X or 180
	local cardHeight = _tooltipCard.AbsoluteSize.Y > 0 and _tooltipCard.AbsoluteSize.Y or 24

	local camera = workspace.CurrentCamera
	local screenW = camera and camera.ViewportSize.X or 1920
	local screenH = camera and camera.ViewportSize.Y or 1080

	local posX 
	local posY 

	-- Priority 1: Position adjacent to cursor if available
	local cursor = mousePos or UserInputService:GetMouseLocation()
	if cursor and cursor.X > 10 and cursor.Y > 10 then
		posX = cursor.X + 12
		posY = cursor.Y + 14

		-- Flip if overflowing right screen edge
		if (posX + cardWidth) > (screenW - 12) then
			posX = cursor.X - cardWidth - 10
		end
		-- Flip if overflowing bottom screen edge
		if (posY + cardHeight) > (screenH - 12) then
			posY = cursor.Y - cardHeight - 8
		end
	else
		-- Priority 2: Fallback to target element with proper TopBar inset adjustment
		local inset = GuiService:GetGuiInset()
		local targetScreenX = targetGui.AbsolutePosition.X + inset.X
		local targetScreenY = targetGui.AbsolutePosition.Y + inset.Y
		local targetW = targetGui.AbsoluteSize.X
		local targetH = targetGui.AbsoluteSize.Y

		posX = targetScreenX + 8
		if (posX + cardWidth) > (screenW - 12) then
			posX = screenW - cardWidth - 12
		end

		-- If element is high up, place 6px below; otherwise place 6px above
		if targetScreenY < 220 then
			posY = targetScreenY + targetH + 6
		else
			posY = targetScreenY - cardHeight - 6
		end
	end

	-- Clamp within visible viewport boundaries
	if posX < 8 then posX = 8 end
	if posY < 8 then posY = 8 end

	_tooltipCard.Position = UDim2.new(0, math.floor(posX), 0, math.floor(posY))
	_tooltipCard.BackgroundTransparency = 0.5
	if _tooltipStroke then _tooltipStroke.Transparency = 1 end
	_tooltipLabel.TextTransparency = 1

	Theme.Tween(_tooltipCard, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.08,
	})
	if _tooltipStroke then
		Theme.Tween(_tooltipStroke, TweenInfo.new(0.16), { Transparency = 0.70 })
	end
	Theme.Tween(_tooltipLabel, TweenInfo.new(0.16), { TextTransparency = 0.10 })
end

function Tooltip.Hide()
	if not _tooltipCard or not _isVisible then return end
	_isVisible = false

	local tw = Theme.Tween(_tooltipCard, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})
	if _tooltipStroke then
		Theme.Tween(_tooltipStroke, TweenInfo.new(0.12), { Transparency = 1 })
	end
	if _tooltipLabel then
		Theme.Tween(_tooltipLabel, TweenInfo.new(0.12), { TextTransparency = 1 })
	end

	tw.Completed:Connect(function()
		if not _isVisible and _tooltipCard then
			_tooltipCard.Visible = false
		end
	end)
end

function Tooltip.Attach(targetGui, tooltipText, delaySeconds)
	if not targetGui or not tooltipText or tooltipText == "" then return end
	local delayTime = delaySeconds or HOVER_DELAY

	targetGui.MouseEnter:Connect(function(x, y)
		_currentHoverTarget = targetGui
		_hoverToken += 1
		local thisToken = _hoverToken
		local initialMouse = (x and y and x > 0 and y > 0) and Vector2.new(x, y) or nil

		task.delay(delayTime, function()
			if _hoverToken == thisToken and _currentHoverTarget == targetGui then
				local currentMouse = UserInputService:GetMouseLocation()
				local pos = (currentMouse.X > 0 and currentMouse.Y > 0) and currentMouse or initialMouse
				Tooltip.Show(tooltipText, targetGui, pos)
			end
		end)
	end)

	targetGui.MouseLeave:Connect(function()
		if _currentHoverTarget == targetGui then
			_currentHoverTarget = nil
			_hoverToken += 1
			Tooltip.Hide()
		end
	end)
end

return Tooltip

end

-- Module: components/Keybind
__modules["components/Keybind"] = function()
-- components/Keybind.luau
-- Standalone, Luxury OOP Keybind Component for Shenky Hub Design System
-- Features dynamic key capture, format normalization, game input listening, and reactive callbacks

local UserInputService = game:GetService("UserInputService")
local Theme = __require("components/Theme")

local Keybind = {}
Keybind.__index = Keybind

local SHORT_KEY_NAMES = {
	[Enum.KeyCode.LeftShift] = "L-Shift",
	[Enum.KeyCode.RightShift] = "R-Shift",
	[Enum.KeyCode.LeftControl] = "L-Ctrl",
	[Enum.KeyCode.RightControl] = "R-Ctrl",
	[Enum.KeyCode.LeftAlt] = "L-Alt",
	[Enum.KeyCode.RightAlt] = "R-Alt",
	[Enum.KeyCode.PageUp] = "PgUp",
	[Enum.KeyCode.PageDown] = "PgDn",
	[Enum.KeyCode.Backspace] = "Back",
	[Enum.KeyCode.CapsLock] = "Caps",
	[Enum.KeyCode.Return] = "Enter",
	[Enum.KeyCode.Unknown] = "None",
}

local function formatKeyName(key)
	if not key or key == Enum.KeyCode.Unknown then
		return "None"
	end
	return SHORT_KEY_NAMES[key] or key.Name
end



function Keybind.new(parent, settings, flag, library)
	local self = setmetatable({}, Keybind)
	self.Settings = settings or {}
	self.Flag = flag
	self.Class = "Keybind"
	self.Listening = false
	self.Value = self.Settings.Default or self.Settings.Value or Enum.KeyCode.Unknown
	self.Connections = {}

	local titleText = self.Settings.Name or self.Settings.Title or "Keybind"
	local descText = self.Settings.Description or self.Settings.Desc
	local hasDesc = (type(descText) == "string" and descText ~= "")

	-- 1. Outer Container Row
	local container = Instance.new("Frame")
	container.Name = "KeybindRow"
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = parent

	local rowList = Instance.new("UIListLayout")
	rowList.Name = "RowListLayout"
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	rowList.VerticalAlignment = Enum.VerticalAlignment.Center
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Parent = container

	-- Left: Labels (Title & Subtitle)
	local leftFrame = Instance.new("Frame")
	leftFrame.Name = "LeftLabels"
	leftFrame.LayoutOrder = 1
	leftFrame.BackgroundTransparency = 1
	leftFrame.BorderSizePixel = 0
	leftFrame.Size = UDim2.new(1, -68, 0, 0)
	leftFrame.AutomaticSize = Enum.AutomaticSize.Y
	leftFrame.Parent = container

	local labelList = Instance.new("UIListLayout")
	labelList.SortOrder = Enum.SortOrder.LayoutOrder
	labelList.Padding = UDim.new(0, 2)
	labelList.Parent = leftFrame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "KeybindTitle"
	titleLabel.LayoutOrder = 1
	titleLabel.BackgroundTransparency = 1
	titleLabel.BorderSizePixel = 0
	titleLabel.Size = UDim2.new(1, 0, 0, 16)
	titleLabel.FontFace = Theme.GetFont(Enum.FontWeight.Medium)
	titleLabel.Text = titleText
	titleLabel.TextSize = 12
	titleLabel.TextColor3 = Theme.Colors.TextPrimary
	titleLabel.TextTransparency = 0.15
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = leftFrame

	if hasDesc then
		local descLabel = Instance.new("TextLabel")
		descLabel.Name = "KeybindDesc"
		descLabel.LayoutOrder = 2
		descLabel.BackgroundTransparency = 1
		descLabel.BorderSizePixel = 0
		descLabel.Size = UDim2.new(1, 0, 0, 0)
		descLabel.AutomaticSize = Enum.AutomaticSize.Y
		descLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
		descLabel.Text = descText
		descLabel.TextSize = 11
		descLabel.TextColor3 = Theme.Colors.TextMuted
		descLabel.TextTransparency = 0.35
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextWrapped = true
		descLabel.Parent = leftFrame
	end

	-- Right: Interactive Key Pill
	local pill = Instance.new("TextButton")
	pill.Name = "KeybindPill"
	pill.LayoutOrder = 2
	pill.AutoButtonColor = false
	pill.BackgroundColor3 = Theme.Colors.CardBg
	pill.BackgroundTransparency = 0.94
	pill.BorderSizePixel = 0
	pill.Size = UDim2.new(0, 60, 0, 24)
	pill.FontFace = Theme.GetFont(Enum.FontWeight.SemiBold)
	pill.Text = formatKeyName(self.Value)
	pill.TextSize = 11
	pill.TextColor3 = Theme.Colors.TextPrimary
	pill.TextTransparency = 0.10
	pill.Parent = container

	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(0, 5)
	pillCorner.Parent = pill

	local pillStroke = Instance.new("UIStroke")
	pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	pillStroke.Thickness = Theme.Geometry.StrokeThickness
	pillStroke.Color = Theme.Colors.StrokeColor
	pillStroke.Transparency = 0.90
	pillStroke.Parent = pill

	self.Instance = container
	self.Pill = pill
	self.Stroke = pillStroke

	-- Hover effects
	pill.MouseEnter:Connect(function()
		if not self.Listening then
			Theme.Tween(pill, TweenInfo.new(0.15), { BackgroundTransparency = 0.88 })
			Theme.Tween(pillStroke, TweenInfo.new(0.15), {
				Color = Theme.Colors.AccentLavender,
				Transparency = 0.70,
			})
		end
	end)

	pill.MouseLeave:Connect(function()
		if not self.Listening then
			Theme.Tween(pill, TweenInfo.new(0.15), { BackgroundTransparency = 0.94 })
			Theme.Tween(pillStroke, TweenInfo.new(0.15), {
				Color = Theme.Colors.StrokeColor,
				Transparency = 0.90,
			})
		end
	end)

	-- Click to listen for new key
	pill.MouseButton1Click:Connect(function()
		if self.Listening then
			self:StopListening()
		else
			self:StartListening()
		end
	end)

	-- Runtime gameplay key listening
	local gameConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if UserInputService:GetFocusedTextBox() then return end
		if not self.Listening and self.Value and self.Value ~= Enum.KeyCode.Unknown then
			if input.KeyCode == self.Value then
				if type(self.Settings.Callback) == "function" then
					task.spawn(self.Settings.Callback, self.Value)
				end
			end
		end
	end)
	table.insert(self.Connections, gameConn)

	if flag and library and type(library.Options) == "table" then
		library.Options[flag] = self
	end

	return self
end

function Keybind:StartListening()
	if self.Listening then return end
	self.Listening = true

	self.Pill.Text = "..."
	self.Pill.TextColor3 = Theme.Colors.AccentLavender
	Theme.Tween(self.Stroke, TweenInfo.new(0.20), {
		Color = Theme.Colors.AccentLavender,
		Transparency = 0.35,
	})

	local listenConn
	listenConn = UserInputService.InputBegan:Connect(function(input)
		-- Ignore mouse move
		if input.UserInputType == Enum.UserInputType.MouseMovement then return end

		local newKey = nil
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
				newKey = Enum.KeyCode.Unknown
			else
				newKey = input.KeyCode
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			newKey = Enum.KeyCode.Unknown
		end

		if newKey ~= nil then
			if listenConn then
				listenConn:Disconnect()
				listenConn = nil
			end
			self:Bind(newKey)
			self:StopListening()
		end
	end)
	table.insert(self.Connections, listenConn)
end

function Keybind:StopListening()
	self.Listening = false
	self.Pill.Text = formatKeyName(self.Value)
	self.Pill.TextColor3 = Theme.Colors.TextPrimary
	Theme.Tween(self.Stroke, TweenInfo.new(0.20), {
		Color = Theme.Colors.StrokeColor,
		Transparency = 0.90,
	})
end

function Keybind:Bind(newKey)
	self.Value = newKey or Enum.KeyCode.Unknown
	if self.Pill then
		self.Pill.Text = formatKeyName(self.Value)
	end

	if type(self.Settings.onBinded) == "function" then
		task.spawn(self.Settings.onBinded, self.Value)
	elseif type(self.Settings.Callback) == "function" then
		task.spawn(self.Settings.Callback, self.Value)
	end
end

function Keybind:Set(newKey)
	self:Bind(newKey)
end

function Keybind:Get()
	return self.Value
end

function Keybind:GetValue()
	return self.Value
end

function Keybind:SetVisibility(state)
	if self.Instance then
		self.Instance.Visible = state
	end
end

function Keybind:Destroy()
	for _, conn in pairs(self.Connections) do
		if conn and typeof(conn) == "RBXScriptConnection" then
			pcall(conn.Disconnect, conn)
		end
	end
	table.clear(self.Connections)
	if self.Instance then
		self.Instance:Destroy()
	end
end

return Keybind

end

-- Module: components/Colorpicker
__modules["components/Colorpicker"] = function()
-- components/Colorpicker.luau
-- Standalone, Luxury OOP Colorpicker Component for Shenky Hub Design System
-- Features collapsible drawer, color swatch preview, quick preset swatches, Hex input, and reactive callbacks

local UserInputService = game:GetService("UserInputService")
local Theme = __require("components/Theme")

local Colorpicker = {}
Colorpicker.__index = Colorpicker

local PRESET_PALETTE = {
	Color3.fromRGB(248, 113, 113), -- Red / Coral
	Color3.fromRGB(251, 146, 60),  -- Orange
	Color3.fromRGB(250, 204, 21),  -- Yellow / Gold
	Color3.fromRGB(74, 222, 128),  -- Emerald / Green
	Color3.fromRGB(56, 189, 248),  -- Sky / Cyan
	Color3.fromRGB(160, 185, 255), -- Lavender (Brand)
	Color3.fromRGB(217, 70, 239),  -- Fuchsia
	Color3.fromRGB(255, 255, 255), -- Pure White
}

local function toHex(color)
	return string.format("#%02X%02X%02X", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

local function fromHex(hex)
	hex = hex:gsub("#", ""):gsub("%s+", "")
	if #hex ~= 6 then return nil end
	local r = tonumber(hex:sub(1, 2), 16)
	local g = tonumber(hex:sub(3, 4), 16)
	local b = tonumber(hex:sub(5, 6), 16)
	if r and g and b then
		return Color3.fromRGB(r, g, b)
	end
	return nil
end



function Colorpicker.new(parent, settings, flag, library)
	local self = setmetatable({}, Colorpicker)
	self.Settings = settings or {}
	self.Flag = flag
	self.Class = "Colorpicker"
	self.Color = self.Settings.Default or Color3.fromRGB(160, 185, 255)
	self.Alpha = self.Settings.Alpha or 1
	self.IsOpen = false
	self.PresetButtons = {}

	local titleText = self.Settings.Name or self.Settings.Title or "Colorpicker"
	local descText = self.Settings.Description or self.Settings.Desc
	local hasDesc = (type(descText) == "string" and descText ~= "")

	-- 1. Outer Container
	local container = Instance.new("Frame")
	container.Name = "ColorpickerContainer"
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = parent

	local rootList = Instance.new("UIListLayout")
	rootList.Name = "RootList"
	rootList.SortOrder = Enum.SortOrder.LayoutOrder
	rootList.Padding = UDim.new(0, 6)
	rootList.Parent = container

	-- 2. Header Row
	local headerRow = Instance.new("Frame")
	headerRow.Name = "HeaderRow"
	headerRow.LayoutOrder = 1
	headerRow.BackgroundTransparency = 1
	headerRow.BorderSizePixel = 0
	headerRow.Size = UDim2.new(1, 0, 0, 0)
	headerRow.AutomaticSize = Enum.AutomaticSize.Y
	headerRow.Parent = container

	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.VerticalAlignment = Enum.VerticalAlignment.Center
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Parent = headerRow

	-- Left: Labels
	local leftLabels = Instance.new("Frame")
	leftLabels.Name = "LeftLabels"
	leftLabels.LayoutOrder = 1
	leftLabels.BackgroundTransparency = 1
	leftLabels.BorderSizePixel = 0
	leftLabels.Size = UDim2.new(1, -48, 0, 0)
	leftLabels.AutomaticSize = Enum.AutomaticSize.Y
	leftLabels.Parent = headerRow

	local labelList = Instance.new("UIListLayout")
	labelList.SortOrder = Enum.SortOrder.LayoutOrder
	labelList.Padding = UDim.new(0, 2)
	labelList.Parent = leftLabels

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "ColorTitle"
	titleLabel.LayoutOrder = 1
	titleLabel.BackgroundTransparency = 1
	titleLabel.BorderSizePixel = 0
	titleLabel.Size = UDim2.new(1, 0, 0, 16)
	titleLabel.FontFace = Theme.GetFont(Enum.FontWeight.Medium)
	titleLabel.Text = titleText
	titleLabel.TextSize = 12
	titleLabel.TextColor3 = Theme.Colors.TextPrimary
	titleLabel.TextTransparency = 0.15
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = leftLabels

	if hasDesc then
		local descLabel = Instance.new("TextLabel")
		descLabel.Name = "ColorDesc"
		descLabel.LayoutOrder = 2
		descLabel.BackgroundTransparency = 1
		descLabel.BorderSizePixel = 0
		descLabel.Size = UDim2.new(1, 0, 0, 0)
		descLabel.AutomaticSize = Enum.AutomaticSize.Y
		descLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
		descLabel.Text = descText
		descLabel.TextSize = 11
		descLabel.TextColor3 = Theme.Colors.TextMuted
		descLabel.TextTransparency = 0.35
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextWrapped = true
		descLabel.Parent = leftLabels
	end

	-- Right: Swatch Pill Button
	local swatchBtn = Instance.new("TextButton")
	swatchBtn.Name = "SwatchButton"
	swatchBtn.LayoutOrder = 2
	swatchBtn.AutoButtonColor = false
	swatchBtn.BackgroundColor3 = self.Color
	swatchBtn.BorderSizePixel = 0
	swatchBtn.Size = UDim2.new(0, 38, 0, 20)
	swatchBtn.Text = ""
	swatchBtn.Parent = headerRow

	local swatchCorner = Instance.new("UICorner")
	swatchCorner.CornerRadius = UDim.new(0, 5)
	swatchCorner.Parent = swatchBtn

	local swatchStroke = Instance.new("UIStroke")
	swatchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	swatchStroke.Thickness = 1.0
	swatchStroke.Color = Color3.fromRGB(255, 255, 255)
	swatchStroke.Transparency = 0.60
	swatchStroke.Parent = swatchBtn

	-- 3. Collapsible Drawer Container
	local drawer = Instance.new("Frame")
	drawer.Name = "ColorDrawer"
	drawer.LayoutOrder = 2
	drawer.BackgroundColor3 = Theme.Colors.CardBg
	drawer.BackgroundTransparency = 0.96
	drawer.BorderSizePixel = 0
	drawer.Size = UDim2.new(1, 0, 0, 0)
	drawer.AutomaticSize = Enum.AutomaticSize.Y
	drawer.Visible = false
	drawer.Parent = container

	local drawerCorner = Instance.new("UICorner")
	drawerCorner.CornerRadius = UDim.new(0, 6)
	drawerCorner.Parent = drawer

	local drawerStroke = Instance.new("UIStroke")
	drawerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	drawerStroke.Thickness = 1.0
	drawerStroke.Color = Theme.Colors.StrokeColor
	drawerStroke.Transparency = 0.90
	drawerStroke.Parent = drawer

	local drawerPadding = Instance.new("UIPadding")
	drawerPadding.PaddingTop = UDim.new(0, 8)
	drawerPadding.PaddingBottom = UDim.new(0, 8)
	drawerPadding.PaddingLeft = UDim.new(0, 8)
	drawerPadding.PaddingRight = UDim.new(0, 8)
	drawerPadding.Parent = drawer

	local drawerList = Instance.new("UIListLayout")
	drawerList.SortOrder = Enum.SortOrder.LayoutOrder
	drawerList.Padding = UDim.new(0, 8)
	drawerList.Parent = drawer

	-- Section A: Preset Swatch Palette Row
	local presetRow = Instance.new("Frame")
	presetRow.Name = "PresetRow"
	presetRow.LayoutOrder = 1
	presetRow.BackgroundTransparency = 1
	presetRow.BorderSizePixel = 0
	presetRow.Size = UDim2.new(1, 0, 0, 18)
	presetRow.Parent = drawer

	local presetList = Instance.new("UIListLayout")
	presetList.FillDirection = Enum.FillDirection.Horizontal
	presetList.SortOrder = Enum.SortOrder.LayoutOrder
	presetList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	presetList.Padding = UDim.new(0, 6)
	presetList.Parent = presetRow

	for idx, col in ipairs(PRESET_PALETTE) do
		local dot = Instance.new("TextButton")
		dot.Name = "Preset_" .. idx
		dot.LayoutOrder = idx
		dot.AutoButtonColor = false
		dot.BackgroundColor3 = col
		dot.BorderSizePixel = 0
		dot.Size = UDim2.new(0, 18, 0, 18)
		dot.Text = ""
		dot.Parent = presetRow

		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = dot

		local dotStroke = Instance.new("UIStroke")
		dotStroke.Thickness = 1
		dotStroke.Color = Color3.fromRGB(255, 255, 255)
		dotStroke.Transparency = 0.70
		dotStroke.Parent = dot

		dot.MouseButton1Click:Connect(function()
			self:Set(col)
		end)

		table.insert(self.PresetButtons, dot)
	end

	-- Section B: Hex Code Input Row
	local hexRow = Instance.new("Frame")
	hexRow.Name = "HexRow"
	hexRow.LayoutOrder = 2
	hexRow.BackgroundTransparency = 1
	hexRow.BorderSizePixel = 0
	hexRow.Size = UDim2.new(1, 0, 0, 24)
	hexRow.Parent = drawer

	local hexList = Instance.new("UIListLayout")
	hexList.FillDirection = Enum.FillDirection.Horizontal
	hexList.VerticalAlignment = Enum.VerticalAlignment.Center
	hexList.SortOrder = Enum.SortOrder.LayoutOrder
	hexList.Padding = UDim.new(0, 6)
	hexList.Parent = hexRow

	local hexTag = Instance.new("TextLabel")
	hexTag.Name = "HexTag"
	hexTag.LayoutOrder = 1
	hexTag.BackgroundTransparency = 1
	hexTag.BorderSizePixel = 0
	hexTag.Size = UDim2.new(0, 32, 1, 0)
	hexTag.FontFace = Theme.GetFont(Enum.FontWeight.SemiBold)
	hexTag.Text = "HEX"
	hexTag.TextSize = 10
	hexTag.TextColor3 = Theme.Colors.TextMuted
	hexTag.TextTransparency = 0.35
	hexTag.Parent = hexRow

	local hexBox = Instance.new("TextBox")
	hexBox.Name = "HexInputBox"
	hexBox.LayoutOrder = 2
	hexBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	hexBox.BackgroundTransparency = 0.94
	hexBox.BorderSizePixel = 0
	hexBox.Size = UDim2.new(1, -38, 1, 0)
	hexBox.FontFace = Theme.GetFont(Enum.FontWeight.Medium)
	hexBox.Text = toHex(self.Color)
	hexBox.TextSize = 11
	hexBox.TextColor3 = Theme.Colors.TextPrimary
	hexBox.TextTransparency = 0.15
	hexBox.ClearTextOnFocus = false
	hexBox.Parent = hexRow

	local hexCorner = Instance.new("UICorner")
	hexCorner.CornerRadius = UDim.new(0, 4)
	hexCorner.Parent = hexBox

	local hexStroke = Instance.new("UIStroke")
	hexStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	hexStroke.Thickness = 1.0
	hexStroke.Color = Theme.Colors.StrokeColor
	hexStroke.Transparency = 0.85
	hexStroke.Parent = hexBox

	hexBox.FocusLost:Connect(function(enterPressed)
		local parsed = fromHex(hexBox.Text)
		if parsed then
			self:Set(parsed)
		else
			hexBox.Text = toHex(self.Color)
		end
	end)

	-- Toggle drawer on swatch click
	swatchBtn.MouseButton1Click:Connect(function()
		self.IsOpen = not self.IsOpen
		drawer.Visible = self.IsOpen
		if self.IsOpen then
			Theme.Tween(swatchStroke, TweenInfo.new(0.18), {
				Color = Theme.Colors.AccentLavender,
				Transparency = 0.20,
			})
		else
			Theme.Tween(swatchStroke, TweenInfo.new(0.18), {
				Color = Color3.fromRGB(255, 255, 255),
				Transparency = 0.60,
			})
		end
	end)

	self.Instance = container
	self.Swatch = swatchBtn
	self.SwatchStroke = swatchStroke
	self.Drawer = drawer
	self.HexBox = hexBox

	if flag and library and type(library.Options) == "table" then
		library.Options[flag] = self
	end

	return self
end

function Colorpicker:Set(newColor, newAlpha, skipCallback)
	self.Color = newColor or self.Color
	if newAlpha ~= nil then
		self.Alpha = newAlpha
	end

	if self.Swatch then
		self.Swatch.BackgroundColor3 = self.Color
	end
	if self.HexBox then
		self.HexBox.Text = toHex(self.Color)
	end

	if not skipCallback and type(self.Settings.Callback) == "function" then
		task.spawn(self.Settings.Callback, self.Color, self.Alpha)
	end
end

function Colorpicker:Get()
	return self.Color
end

function Colorpicker:GetValue()
	return self.Color
end

function Colorpicker:SetVisibility(state)
	if self.Instance then
		self.Instance.Visible = state
	end
end

function Colorpicker:Destroy()
	if self.Instance then
		self.Instance:Destroy()
	end
end

return Colorpicker

end

-- Module: components/History
__modules["components/History"] = function()
-- components/History.luau
-- Standalone, Modular Update Log & Changelog Component for Shenky Hub Design System
-- Renders clean, high-performance accordion release cards matching Shenky Content Card architecture
-- Features leading header icon, version badge, title, date, and animated center-pivoting chevron

local TweenService = game:GetService("TweenService")
local Theme = __require("components/Theme")

local History = {}
History.__index = History





local TAG_CONFIGS = {
	NEW = {
		Color = Color3.fromRGB(56, 189, 248), -- Sky 400
		Label = "NEW",
	},
	FIX = {
		Color = Color3.fromRGB(251, 191, 36), -- Amber 400
		Label = "FIX",
	},
	PERF = {
		Color = Color3.fromRGB(160, 185, 255), -- Soft Lavender
		Label = "PERF",
	},
	IMP = {
		Color = Color3.fromRGB(74, 222, 128), -- Emerald 400
		Label = "IMP",
	},
	IMPROVED = {
		Color = Color3.fromRGB(74, 222, 128),
		Label = "IMP",
	},
	DEL = {
		Color = Color3.fromRGB(248, 113, 113), -- Red 400
		Label = "DEL",
	},
	REMOVED = {
		Color = Color3.fromRGB(248, 113, 113),
		Label = "DEL",
	},
}

local CHEVRON_ICON = "rbxassetid://10709790948" -- Lucide chevron-down
local TAG_ICON = "rbxassetid://10734976528"     -- Lucide tag
local SPARKLE_ICON = "rbxassetid://10734966248" -- Lucide sparkles

function History.new(parent, settings, flag, library)
	local self = setmetatable({}, History)
	self.Settings = settings or {}
	self.Flag = flag
	self.Class = "History"
	self.Parent = parent
	self.Cards = {}

	local container = Instance.new("Frame")
	container.Name = "HistoryLog"
	container.BorderSizePixel = 0
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = parent

	local rootList = Instance.new("UIListLayout")
	rootList.Name = "HistoryListLayout"
	rootList.SortOrder = Enum.SortOrder.LayoutOrder
	rootList.Padding = UDim.new(0, 6)
	rootList.Parent = container

	self.Instance = container
	self.RootLayout = rootList

	local initialItems = self.Settings.Items or self.Settings.Entries or {}
	self:_Build(initialItems)

	if flag and library and type(library.Options) == "table" then
		library.Options[flag] = self
	end

	return self
end

function History:_Build(items)
	-- Clear existing cards
	for _, child in ipairs(self.Instance:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "HistoryListLayout" then
			child:Destroy()
		end
	end
	self.Cards = {}

	if type(items) ~= "table" or #items == 0 then
		local emptyCard = Instance.new("Frame")
		emptyCard.Name = "EmptyCard"
		emptyCard.BackgroundColor3 = Theme.Colors.CardBg
		emptyCard.BackgroundTransparency = Theme.Colors.CardTransIdle
		emptyCard.BorderSizePixel = 0
		emptyCard.Size = UDim2.new(1, 0, 0, 36)
		emptyCard.Parent = self.Instance

		local eCorner = Instance.new("UICorner")
		eCorner.CornerRadius = UDim.new(0, 6)
		eCorner.Parent = emptyCard

		local eStroke = Instance.new("UIStroke")
		eStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		eStroke.Thickness = 1
		eStroke.Color = Theme.Colors.StrokeColor
		eStroke.Transparency = Theme.Colors.StrokeTransIdle
		eStroke.Parent = emptyCard

		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Name = "EmptyLabel"
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Size = UDim2.new(1, 0, 1, 0)
		emptyLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
		emptyLabel.TextSize = 12
		emptyLabel.TextColor3 = Theme.Colors.TextMuted
		emptyLabel.TextTransparency = 0.45
		emptyLabel.Text = "No update logs recorded yet."
		emptyLabel.TextXAlignment = Enum.TextXAlignment.Center
		emptyLabel.TextYAlignment = Enum.TextYAlignment.Center
		emptyLabel.Parent = emptyCard
		return
	end

	local maxCount = self.Settings.MaxEntries or 8
	local renderedCount = 0

	for idx, entry in ipairs(items) do
		if renderedCount >= maxCount then break end
		renderedCount = renderedCount + 1

		local card = self:_CreateEntryCard(entry, idx)
		card.Parent = self.Instance
		table.insert(self.Cards, card)
	end
end

function History:_CreateEntryCard(entry, index)
	local versionText = entry.Version and tostring(entry.Version) or nil
	local dateText = entry.Date and tostring(entry.Date) or ""
	local titleText = entry.Title and tostring(entry.Title) or ""
	local rawChanges = entry.Changes or {}
	local isLatest = (index == 1)

	-- Accordion State: Latest release is open by default, older releases are collapsed
	local isExpanded = isLatest

	-- Outer Card Frame
	local card = Instance.new("Frame")
	card.Name = "HistoryCard_" .. tostring(versionText or index)
	card.BackgroundColor3 = Theme.Colors.CardBg
	card.BackgroundTransparency = Theme.Colors.CardTransIdle
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = index

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = Theme.Geometry.StrokeThickness
	stroke.Color = isLatest and Theme.Colors.AccentLavender or Theme.Colors.StrokeColor
	stroke.Transparency = isLatest and 0.72 or Theme.Colors.StrokeTransIdle
	stroke.Parent = card

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 7)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 9)
	pad.PaddingRight = UDim.new(0, 9)
	pad.Parent = card

	local cardList = Instance.new("UIListLayout")
	cardList.SortOrder = Enum.SortOrder.LayoutOrder
	cardList.Padding = UDim.new(0, 5)
	cardList.Parent = card

	-- ============================================================
	-- 1. Header Container (Leading Icon + Badge/Title + Date + Animated Chevron)
	-- Identical architecture to Content Card Section Headers
	-- ============================================================
	local headerRow = Instance.new("Frame")
	headerRow.Name = "HeaderRow"
	headerRow.BackgroundTransparency = 1
	headerRow.Size = UDim2.new(1, 0, 0, 20)
	headerRow.LayoutOrder = 1
	headerRow.Parent = card

	-- 1A. Leading Icon (Tag / Sparkles icon on the left)
	local leadIcon = Instance.new("ImageLabel")
	leadIcon.Name = "LeadingIcon"
	leadIcon.Size = UDim2.fromOffset(13, 13)
	leadIcon.AnchorPoint = Vector2.new(0, 0.5)
	leadIcon.Position = UDim2.new(0, 0, 0.5, 0)
	leadIcon.BackgroundTransparency = 1
	leadIcon.Image = isLatest and SPARKLE_ICON or TAG_ICON
	leadIcon.ImageColor3 = isLatest and Theme.Colors.AccentLavender or Theme.Colors.TextMuted
	leadIcon.ImageTransparency = isLatest and 0.15 or 0.40
	leadIcon.Parent = headerRow

	-- 1B. Middle Group (Version Badge + Title)
	local middleGroup = Instance.new("Frame")
	middleGroup.Name = "MiddleGroup"
	middleGroup.BackgroundTransparency = 1
	middleGroup.Position = UDim2.new(0, 18, 0, 0)
	middleGroup.Size = UDim2.new(1, -115, 1, 0)
	middleGroup.Parent = headerRow

	local middleList = Instance.new("UIListLayout")
	middleList.FillDirection = Enum.FillDirection.Horizontal
	middleList.VerticalAlignment = Enum.VerticalAlignment.Center
	middleList.SortOrder = Enum.SortOrder.LayoutOrder
	middleList.Padding = UDim.new(0, 6)
	middleList.Parent = middleGroup

	-- Version Badge
	if versionText and #versionText > 0 then
		local badge = Instance.new("Frame")
		badge.Name = "VersionBadge"
		badge.BackgroundColor3 = Theme.Colors.AccentLavender
		badge.BackgroundTransparency = isLatest and 0.86 or 0.92
		badge.BorderSizePixel = 0
		badge.Size = UDim2.new(0, 0, 0, 16)
		badge.AutomaticSize = Enum.AutomaticSize.X
		badge.LayoutOrder = 1
		badge.Parent = middleGroup

		local bCorner = Instance.new("UICorner")
		bCorner.CornerRadius = UDim.new(0, 3)
		bCorner.Parent = badge

		local bStroke = Instance.new("UIStroke")
		bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		bStroke.Thickness = 1
		bStroke.Color = Theme.Colors.AccentLavender
		bStroke.Transparency = isLatest and 0.65 or 0.80
		bStroke.Parent = badge

		local bPad = Instance.new("UIPadding")
		bPad.PaddingLeft = UDim.new(0, 5)
		bPad.PaddingRight = UDim.new(0, 5)
		bPad.Parent = badge

		local bText = Instance.new("TextLabel")
		bText.Name = "BadgeText"
		bText.BackgroundTransparency = 1
		bText.Size = UDim2.new(0, 0, 1, 0)
		bText.AutomaticSize = Enum.AutomaticSize.X
		bText.FontFace = Theme.GetFont(Enum.FontWeight.Bold)
		bText.TextSize = 10
		bText.TextColor3 = Theme.Colors.AccentLavender
		bText.Text = versionText
		bText.TextYAlignment = Enum.TextYAlignment.Center
		bText.Parent = badge
	end

	-- Title Label (Truncates smoothly)
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "TitleLabel"
	titleLbl.BackgroundTransparency = 1
	titleLbl.Size = UDim2.new(1, - (versionText and 40 or 0), 1, 0)
	titleLbl.FontFace = Theme.GetFont(Enum.FontWeight.SemiBold)
	titleLbl.TextSize = 11
	titleLbl.TextColor3 = isLatest and Theme.Colors.TextPrimary or Color3.fromRGB(200, 205, 220)
	titleLbl.TextTransparency = isLatest and 0.05 or 0.20
	titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.TextYAlignment = Enum.TextYAlignment.Center
	titleLbl.Text = titleText
	titleLbl.LayoutOrder = 2
	titleLbl.Parent = middleGroup

	-- 1C. Date Label (Right aligned, before chevron)
	if dateText and #dateText > 0 then
		local dateLbl = Instance.new("TextLabel")
		dateLbl.Name = "DateLabel"
		dateLbl.AnchorPoint = Vector2.new(1, 0.5)
		dateLbl.Position = UDim2.new(1, -20, 0.5, 0)
		dateLbl.Size = UDim2.new(0, 75, 1, 0)
		dateLbl.BackgroundTransparency = 1
		dateLbl.FontFace = Theme.GetFont(Enum.FontWeight.Medium)
		dateLbl.TextSize = 10
		dateLbl.TextColor3 = Theme.Colors.TextMuted
		dateLbl.TextTransparency = 0.35
		dateLbl.TextXAlignment = Enum.TextXAlignment.Right
		dateLbl.TextYAlignment = Enum.TextYAlignment.Center
		dateLbl.Text = dateText
		dateLbl.Parent = headerRow
	end

	-- 1D. Trailing Animated Chevron Icon (Centered pivot for clean spin)
	local chevron = Instance.new("ImageLabel")
	chevron.Name = "ChevronIcon"
	chevron.Size = UDim2.fromOffset(13, 13)
	chevron.AnchorPoint = Vector2.new(0.5, 0.5)
	chevron.Position = UDim2.new(1, -7, 0.5, 0)
	chevron.BackgroundTransparency = 1
	chevron.Image = CHEVRON_ICON
	chevron.ImageColor3 = isLatest and Color3.fromRGB(210, 220, 245) or Theme.Colors.TextMuted
	chevron.ImageTransparency = 0.35
	chevron.Rotation = isExpanded and 0 or -90
	chevron.Parent = headerRow

	-- 1E. Full-Coverage Header Click Button (ZIndex = 5)
	local headerInteract = Instance.new("TextButton")
	headerInteract.Name = "HeaderInteract"
	headerInteract.Text = ""
	headerInteract.BackgroundTransparency = 1
	headerInteract.BorderSizePixel = 0
	headerInteract.AutoButtonColor = false
	headerInteract.Size = UDim2.fromScale(1, 1)
	headerInteract.ZIndex = 5
	headerInteract.Parent = headerRow

	-- ============================================================
	-- 2. Subtle Hairline Divider (Collapsible)
	-- ============================================================
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	divider.BackgroundTransparency = 0.93
	divider.BorderSizePixel = 0
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.LayoutOrder = 2
	divider.Visible = isExpanded
	divider.Parent = card

	-- ============================================================
	-- 3. Changes List Container (Collapsible)
	-- ============================================================
	local changesContainer = Instance.new("Frame")
	changesContainer.Name = "ChangesContainer"
	changesContainer.BackgroundTransparency = 1
	changesContainer.Size = UDim2.new(1, 0, 0, 0)
	changesContainer.AutomaticSize = Enum.AutomaticSize.Y
	changesContainer.LayoutOrder = 3
	changesContainer.Visible = isExpanded
	changesContainer.Parent = card

	local changesLayout = Instance.new("UIListLayout")
	changesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	changesLayout.Padding = UDim.new(0, 5)
	changesLayout.Parent = changesContainer

	-- Normalize Changes into a list of strings
	local changesList = {}
	if type(rawChanges) == "table" then
		for _, item in ipairs(rawChanges) do
			if item ~= nil then
				table.insert(changesList, tostring(item))
			end
		end
	elseif type(rawChanges) == "string" and #rawChanges > 0 then
		table.insert(changesList, rawChanges)
	end

	for cIdx, line in ipairs(changesList) do
		local row = self:_CreateChangeRow(line, cIdx)
		row.Parent = changesContainer
	end

	-- ============================================================
	-- 4. Smooth Easing Animation & Toggle Logic (Matches Card Content)
	-- ============================================================
	local function updateAccordionState(animate)
		divider.Visible = isExpanded
		changesContainer.Visible = isExpanded

		local targetRot = isExpanded and 0 or -90
		if animate then
			TweenService:Create(chevron, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Rotation = targetRot,
			}):Play()
		else
			chevron.Rotation = targetRot
		end
	end

	headerInteract.MouseButton1Click:Connect(function()
		isExpanded = not isExpanded
		updateAccordionState(true)
	end)

	-- Header Hover Micro-Interactions (Matches Card Content Section)
	headerInteract.MouseEnter:Connect(function()
		TweenService:Create(chevron, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {
			ImageTransparency = 0.15,
			ImageColor3 = Color3.fromRGB(255, 255, 255),
		}):Play()
		TweenService:Create(leadIcon, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {
			ImageTransparency = 0.10,
			ImageColor3 = Color3.fromRGB(240, 245, 255),
		}):Play()
		TweenService:Create(titleLbl, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTransparency = 0,
		}):Play()
	end)

	headerInteract.MouseLeave:Connect(function()
		local origTitleColor = isLatest and Theme.Colors.TextPrimary or Color3.fromRGB(200, 205, 220)
		local origIconColor = isLatest and Theme.Colors.AccentLavender or Theme.Colors.TextMuted
		TweenService:Create(chevron, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {
			ImageTransparency = 0.35,
			ImageColor3 = isLatest and Color3.fromRGB(210, 220, 245) or Theme.Colors.TextMuted,
		}):Play()
		TweenService:Create(leadIcon, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {
			ImageTransparency = isLatest and 0.15 or 0.40,
			ImageColor3 = origIconColor,
		}):Play()
		TweenService:Create(titleLbl, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {
			TextColor3 = origTitleColor,
			TextTransparency = isLatest and 0.05 or 0.20,
		}):Play()
	end)

	-- Card Hover Micro-Interactions
	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = Theme.Colors.CardTransHover,
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = isLatest and 0.55 or Theme.Colors.StrokeTransHover,
		}):Play()
	end)

	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = Theme.Colors.CardTransIdle,
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = isLatest and 0.72 or Theme.Colors.StrokeTransIdle,
		}):Play()
	end)

	return card
end

function History:_CreateChangeRow(text, order)
	local row = Instance.new("Frame")
	row.Name = "ChangeRow_" .. tostring(order)
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.LayoutOrder = order

	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.VerticalAlignment = Enum.VerticalAlignment.Top
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Padding = UDim.new(0, 6)
	rowList.Parent = row

	-- Detect tag like [NEW], [FIX], [PERF], [IMP], [DEL]
	local tag, message = string.match(text, "^%[([%a%d]+)%]%s*(.*)$")

	if tag and message and #message > 0 then
		local upperTag = string.upper(tag)
		local tagCfg = TAG_CONFIGS[upperTag] or { Color = Color3.fromRGB(160, 185, 255), Label = string.sub(upperTag, 1, 4) }
		local displayLabel = tagCfg.Label or string.sub(upperTag, 1, 4)

		-- Tag Pill Frame
		local tagPill = Instance.new("Frame")
		tagPill.Name = "TagPill"
		tagPill.BackgroundColor3 = tagCfg.Color
		tagPill.BackgroundTransparency = 0.86
		tagPill.BorderSizePixel = 0
		tagPill.Size = UDim2.new(0, 0, 0, 15)
		tagPill.AutomaticSize = Enum.AutomaticSize.X
		tagPill.LayoutOrder = 1

		local tpCorner = Instance.new("UICorner")
		tpCorner.CornerRadius = UDim.new(0, 3)
		tpCorner.Parent = tagPill

		local tpStroke = Instance.new("UIStroke")
		tpStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tpStroke.Thickness = 1
		tpStroke.Color = tagCfg.Color
		tpStroke.Transparency = 0.65
		tpStroke.Parent = tagPill

		local tpPad = Instance.new("UIPadding")
		tpPad.PaddingLeft = UDim.new(0, 5)
		tpPad.PaddingRight = UDim.new(0, 5)
		tpPad.Parent = tagPill

		local tpText = Instance.new("TextLabel")
		tpText.Name = "TagText"
		tpText.BackgroundTransparency = 1
		tpText.Size = UDim2.new(0, 0, 1, 0)
		tpText.AutomaticSize = Enum.AutomaticSize.X
		tpText.FontFace = Theme.GetFont(Enum.FontWeight.Bold)
		tpText.TextSize = 9
		tpText.TextColor3 = tagCfg.Color
		tpText.Text = displayLabel
		tpText.TextXAlignment = Enum.TextXAlignment.Center
		tpText.TextYAlignment = Enum.TextYAlignment.Center
		tpText.Parent = tagPill

		tagPill.Parent = row

		-- Message TextLabel (Flexible width with TextWrapped)
		local msgLabel = Instance.new("TextLabel")
		msgLabel.Name = "MessageLabel"
		msgLabel.BackgroundTransparency = 1
		msgLabel.Size = UDim2.new(1, -38, 0, 0)
		msgLabel.AutomaticSize = Enum.AutomaticSize.Y
		msgLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
		msgLabel.TextSize = 11
		msgLabel.LineHeight = 1.15
		msgLabel.TextColor3 = Color3.fromRGB(225, 230, 245)
		msgLabel.TextTransparency = 0.18
		msgLabel.TextWrapped = true
		msgLabel.TextXAlignment = Enum.TextXAlignment.Left
		msgLabel.TextYAlignment = Enum.TextYAlignment.Top
		msgLabel.Text = message
		msgLabel.LayoutOrder = 2
		msgLabel.Parent = row
	else
		-- Bullet Dot
		local bullet = Instance.new("TextLabel")
		bullet.Name = "Bullet"
		bullet.BackgroundTransparency = 1
		bullet.Size = UDim2.new(0, 8, 0, 15)
		bullet.FontFace = Theme.GetFont(Enum.FontWeight.Bold)
		bullet.TextSize = 13
		bullet.TextColor3 = Theme.Colors.AccentLavender
		bullet.Text = "•"
		bullet.TextXAlignment = Enum.TextXAlignment.Center
		bullet.TextYAlignment = Enum.TextYAlignment.Top
		bullet.LayoutOrder = 1
		bullet.Parent = row

		-- Message TextLabel
		local msgLabel = Instance.new("TextLabel")
		msgLabel.Name = "MessageLabel"
		msgLabel.BackgroundTransparency = 1
		msgLabel.Size = UDim2.new(1, -16, 0, 0)
		msgLabel.AutomaticSize = Enum.AutomaticSize.Y
		msgLabel.FontFace = Theme.GetFont(Enum.FontWeight.Regular)
		msgLabel.TextSize = 11
		msgLabel.LineHeight = 1.15
		msgLabel.TextColor3 = Color3.fromRGB(225, 230, 245)
		msgLabel.TextTransparency = 0.18
		msgLabel.TextWrapped = true
		msgLabel.TextXAlignment = Enum.TextXAlignment.Left
		msgLabel.TextYAlignment = Enum.TextYAlignment.Top
		msgLabel.Text = text
		msgLabel.LayoutOrder = 2
		msgLabel.Parent = row
	end

	return row
end

function History:SetHistory(items)
	self:_Build(items)
end

function History:Update(items)
	self:_Build(items)
end

return History

end

-- Module: core/logo
__modules["core/logo"] = function()
-- core/logo.luau
-- Shenky Logo Multi-Tier Asset Resolver (Square 'S' Logo & Wide Auth 'Logo_Hub')

local SHENKY_S_LOGO_B64 = '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'
local SHENKY_HUB_LOGO_B64 = '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'

local _cachedShenkyAsset = nil
local _cachedShenkyHubAsset = nil

local function decodeBase64(str)
	if type(str) ~= "string" or #str == 0 then return "" end

	local cryptObj = crypt or (syn and syn.crypt)
	if cryptObj and type(cryptObj.base64decode) == "function" then
		local ok, res = pcall(cryptObj.base64decode, str)
		if ok and type(res) == "string" and #res > 0 then return res end
	end
	if cryptObj and type(cryptObj.base64_decode) == "function" then
		local ok, res = pcall(cryptObj.base64_decode, str)
		if ok and type(res) == "string" and #res > 0 then return res end
	end
	if type(base64_decode) == "function" then
		local ok, res = pcall(base64_decode, str)
		if ok and type(res) == "string" and #res > 0 then return res end
	end

	local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local map = {}
	for i = 1, 64 do
		map[string.byte(b64chars, i)] = i - 1
	end

	local len = #str
	local maxOut = math.floor(len * 3 / 4)
	local val, bits = 0, 0
	local outIdx = 0

	if typeof(buffer) == "table" and type(buffer.create) == "function" then
		local buf = buffer.create(maxOut)
		for i = 1, len do
			local byteVal = map[string.byte(str, i)]
			if byteVal ~= nil then
				val = bit32.bor(bit32.lshift(val, 6), byteVal)
				bits = bits + 6
				if bits >= 8 then
					bits = bits - 8
					buffer.writeu8(buf, outIdx, bit32.band(bit32.rshift(val, bits), 0xFF))
					outIdx = outIdx + 1
				end
			end
		end
		return buffer.tostring(buf)
	else
		local result = table.create(maxOut)
		for i = 1, len do
			local byteVal = map[string.byte(str, i)]
			if byteVal ~= nil then
				val = bit32.bor(bit32.lshift(val, 6), byteVal)
				bits = bits + 6
				if bits >= 8 then
					bits = bits - 8
					outIdx = outIdx + 1
					result[outIdx] = string.char(bit32.band(bit32.rshift(val, bits), 0xFF))
				end
			end
		end
		return table.concat(result)
	end
end

-- 1. Resolver for the Square letter 'S' Logo (Used in Window Header, Toggle Button, Status Pill)
local function resolveLetterSLogo()
	if _cachedShenkyAsset then return _cachedShenkyAsset end

	local gca = (typeof(getcustomasset) == "function" and getcustomasset)
		or (typeof(getsynasset) == "function" and getsynasset)
	if not gca then return nil end

	-- Tier 1: Check existing local files on disk (logo.png)
	local candidatePaths = {
		"gui/single_logo.png",
		"Shenky/single_logo.png",
		"single_logo.png",
		"gui/logo.png",
		"Shenky/logo.png",
		"logo.png",
		"Shenky/shenky_logo.png",
		"gui/shenky.png"
	}
	if typeof(isfile) == "function" then
		for _, path in ipairs(candidatePaths) do
			local okExists, exists = pcall(isfile, path)
			if okExists and exists then
				local okAsset, asset = pcall(gca, path)
				if okAsset and type(asset) == "string" and #asset > 0 then
					_cachedShenkyAsset = asset
					return asset
				end
			end
		end
	end

	-- Tier 2: Decode from compact embedded Base64 (Letter 'S')
	if typeof(writefile) == "function" and #SHENKY_S_LOGO_B64 > 100 then
		local decoded = decodeBase64(SHENKY_S_LOGO_B64)
		if decoded and #decoded > 100 then
			if isfolder and makefolder and not isfolder("Shenky") then pcall(makefolder, "Shenky") end
			local okWrite = pcall(writefile, "Shenky/logo.png", decoded)
			if not okWrite then okWrite = pcall(writefile, "logo.png", decoded) end
			if okWrite then
				local okAsset, asset = pcall(gca, "Shenky/logo.png")
				if not okAsset then okAsset, asset = pcall(gca, "logo.png") end
				if okAsset and type(asset) == "string" and #asset > 0 then
					_cachedShenkyAsset = asset
					return asset
				end
			end
		end
	end

	return nil
end

-- 2. Resolver for the Wide Auth / Key System Logo (logo_hub.png)
local function resolveShenkyHubWideLogo()
	if _cachedShenkyHubAsset then return _cachedShenkyHubAsset end

	local gca = (typeof(getcustomasset) == "function" and getcustomasset)
		or (typeof(getsynasset) == "function" and getsynasset)
	if not gca then return nil end

	-- Tier 1: Check existing local files on disk (logo_hub.png)
	local candidatePaths = {
		"gui/logo_hub.png",
		"Shenky/logo_hub.png",
		"logo_hub.png"
	}
	if typeof(isfile) == "function" then
		for _, path in ipairs(candidatePaths) do
			local okExists, exists = pcall(isfile, path)
			if okExists and exists then
				local okAsset, asset = pcall(gca, path)
				if okAsset and type(asset) == "string" and #asset > 0 then
					_cachedShenkyHubAsset = asset
					return asset
				end
			end
		end
	end

	-- Tier 2: Decode from embedded Base64
	if typeof(writefile) == "function" and #SHENKY_HUB_LOGO_B64 > 100 then
		local decoded = decodeBase64(SHENKY_HUB_LOGO_B64)
		if decoded and #decoded > 100 then
			if isfolder and makefolder and not isfolder("Shenky") then pcall(makefolder, "Shenky") end
			local okWrite = pcall(writefile, "Shenky/logo_hub.png", decoded)
			if not okWrite then okWrite = pcall(writefile, "logo_hub.png", decoded) end
			if okWrite then
				local okAsset, asset = pcall(gca, "Shenky/logo_hub.png")
				if not okAsset then okAsset, asset = pcall(gca, "logo_hub.png") end
				if okAsset and type(asset) == "string" and #asset > 0 then
					_cachedShenkyHubAsset = asset
					return asset
				end
			end
		end
	end

	return nil
end

local S_LOGO_ASSET = resolveLetterSLogo()
local HUB_LOGO_ASSET = resolveShenkyHubWideLogo()

getgenv().__SHENKY_LOGO_ASSET = S_LOGO_ASSET
getgenv().__SHENKY_LOGO_HUB_ASSET = HUB_LOGO_ASSET

-- Return the primary Letter 'S' logo asset
return S_LOGO_ASSET

end

-- Module: core/ui
__modules["core/ui"] = function()
-- core/ui.luau



-- Shenky UI Engine: Source Resolver, Disk Cache & Runtime Engine











__require("core/logo")











-- Cache source Shenky UI mentah (3-Tier: Memory -> Local Disk -> Multi-tier HTTP)



-- Menghemat waktu load dari 1.0s menjadi 2ms serta 100% tahan offline / blokir ISP.



local SHENKY_UI_URL = "https://raw.githubusercontent.com/shenkyhub/loader/refs/heads/main/gui/shenky_cache.txt"



local MACLIB_FALLBACK_URL = "https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.txt"



local rawUISource = getgenv and (getgenv().__GLOBAL_SHENKY_RAW_SRC or getgenv().__GLOBAL_MACLIB_RAW_SRC or getgenv().__GLOBAL_MACLIB_SRC)











if type(rawUISource) ~= "string" or #rawUISource < 1000 then



	-- Tier 2: Cek cache disk lokal



	local cachePaths = {



		"Shenky/shenky_cache.txt",



		"shenky_cache.txt",



	}



	local isFileFunc = (typeof(isfile) == "function" and isfile) or nil



	local readFileFunc = (typeof(readfile) == "function" and readfile) or nil



	if isFileFunc and readFileFunc then



		for _, path in ipairs(cachePaths) do



			local okF, exists = pcall(function() return isFileFunc(path) end)



			if okF and exists == true then



				local okR, content = pcall(function() return readFileFunc(path) end)



				if okR and type(content) == "string" and #content > 10000 then



					rawUISource = content



					break



				end



			end



		end



	end



end











if type(rawUISource) ~= "string" or #rawUISource < 1000 then



	-- Tier 3: Unduh via HTTP (HttpGet / Request)



	local httpReq = (type(request) == "function" and request)



		or (type(http_request) == "function" and http_request)



		or (type(syn) == "table" and type(syn.request) == "function" and syn.request)



		or nil



	if httpReq then



		local ok, res = pcall(function() return httpReq({ Url = SHENKY_UI_URL, Method = "GET" }) end)



		if not (ok and type(res) == "table" and (res.StatusCode == 200 or res.Status == 200)) then



			ok, res = pcall(function() return httpReq({ Url = MACLIB_FALLBACK_URL, Method = "GET" }) end)



		end



		if ok and type(res) == "table" and (res.StatusCode == 200 or res.Status == 200) then



			local b = res.Body or res.body



			if type(b) == "string" and #b > 10000 then



				rawUISource = b



			end



		end



	end



	if type(rawUISource) ~= "string" or #rawUISource < 1000 then



		local okGet, resGet = pcall(function()



			return game:HttpGet(SHENKY_UI_URL)



		end)



		if not (okGet and type(resGet) == "string" and #resGet > 10000) then



			okGet, resGet = pcall(function() return game:HttpGet(MACLIB_FALLBACK_URL) end)



		end



		if okGet and type(resGet) == "string" and #resGet > 10000 then



			rawUISource = resGet



		end



	end











	-- Simpan ke cache disk lokal jika berhasil diunduh



	local writeFileFunc = (typeof(writefile) == "function" and writefile) or nil



	if type(rawUISource) == "string" and #rawUISource > 10000 and writeFileFunc then



		pcall(function()



			if isfolder and makefolder and not isfolder("Shenky") then



				pcall(makefolder, "Shenky")



			end



			writeFileFunc("Shenky/shenky_cache.txt", rawUISource)



			if delfile then



				if isfile("Shenky/maclib_cache.txt") then delfile("Shenky/maclib_cache.txt") end



				if isfile("maclib_cache.txt") then delfile("maclib_cache.txt") end



			end



		end)



	end



end











if type(rawUISource) ~= "string" or #rawUISource < 1000 then



	error("[Shenky Hub] Failed to load UI library source from memory, disk cache, or GitHub!", 0)



end



if getgenv then



	getgenv().__GLOBAL_SHENKY_RAW_SRC = rawUISource



	getgenv().__GLOBAL_MACLIB_RAW_SRC = rawUISource



end











local function patchShenkyUISource(src)
	src = string.gsub(src, "\r\n", "\n")
	src = string.gsub(src, "\r", "\n")



	-- 0. Hapus tuntas blok Acrylic Blur internal Maclib:



	-- Menghapus 6.188 byte kode bawaan yang membuat Part Glass + SpecialMesh di Camera,



	-- memodifikasi Lighting.DepthOfFieldEffect (NearIntensity = 1), dan loop RenderStepped.



	local blurStart = string.find(src, "local BlurTarget = base", 1, true)



	local blurEndStr = "RunService.RenderStepped:Connect(UpdateOrientation)"



	local blurEnd = string.find(src, blurEndStr, 1, true)



	if blurStart and blurEnd and blurEnd > blurStart then



		src = string.sub(src, 1, blurStart - 1) .. "-- [Shenky Hub] Acrylic blur completely excised to prevent game blur\n\tlocal function UpdateOrientation() end\n\t" .. string.sub(src, blurEnd + #blurEndStr)



	end



	src = string.gsub(src, "DepthOfField%.Parent = Lighting", "DepthOfField.Enabled = false; DepthOfField.Parent = nil")



	src = string.gsub(src, "DepthOfField%.Enabled = true", "DepthOfField.Enabled = false")



	src = string.gsub(src, "acrylicBlur = true", "acrylicBlur = false")



	-- Patch LocalPlayer safety: ensure LocalPlayer is never nil even on early execution/teleport



	src = string.gsub(



		src,



		"local LocalPlayer = Players%.LocalPlayer",



		[[local LocalPlayer = Players.LocalPlayer



if not LocalPlayer then



	local tWait = tick()



	while not Players.LocalPlayer and (tick() - tWait) < 3 do



		task.wait(0.05)



	end



	LocalPlayer = Players.LocalPlayer



end]]



	)



	src = string.gsub(



		src,



		"local userId = LocalPlayer%.UserId",



		[[local _lp = LocalPlayer or Players.LocalPlayer



	local userId = _lp and _lp.UserId or 0]]



	)



	src = string.gsub(
		src,
		"displayName%.Text = LocalPlayer%.DisplayName",
		[[local _lp = LocalPlayer or Players.LocalPlayer
	local _rawDn = tostring(_lp and _lp.DisplayName or "Player")
	local _lenDn = #_rawDn
	displayName.Text = (_lenDn <= 1 and "*") or (_lenDn == 2 and (string.sub(_rawDn, 1, 1) .. "*")) or (string.sub(_rawDn, 1, 2) .. string.rep("*", _lenDn - 2))]]
	)



	src = string.gsub(
		src,
		"username%.Text = \"@\" %.%. LocalPlayer%.Name",
		[[local _lp = LocalPlayer or Players.LocalPlayer
	local _rawUn = tostring(_lp and _lp.Name or "Player")
	local _lenUn = #_rawUn
	username.Text = "@" .. ((_lenUn <= 1 and "*") or (_lenUn == 2 and (string.sub(_rawUn, 1, 1) .. "*")) or (string.sub(_rawUn, 1, 2) .. string.rep("*", _lenUn - 2)))]]
	)



	-- 0. Patch GetService & GetGui agar ScreenGui diparenting langsung ke CoreGui (bukan RobloxGui) dan aman dari cloneref(nil) error



	src = string.gsub(



		src,



		"return cloneref and cloneref%(game:GetService%(service%)%) or game:GetService%(service%)",



		"local ok, s = pcall(game.GetService, game, service); if ok and s then return (cloneref and cloneref(s)) or s else return nil end"



	)



	src = string.gsub(



		src,



		"local parent = RunService:IsStudio%(%)[^\n]+\r?\n[^\n]+\r?\n[^\n]+\r?\n[^\n]+\r?\n%s*newGui%.Parent = parent",



		[[local parent = (function()



		local okHui, h = pcall(gethui)



		if okHui and h and typeof(h) == "Instance" then



			return h



		end



		local okCg, cg = pcall(game.GetService, game, "CoreGui")



		if okCg and cg then



			local okP = pcall(function() return cg:GetChildren() end)



			if okP then



				return (cloneref and cloneref(cg)) or cg



			end



		end



		return (LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")) or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")



	end)()



	newGui.Name = "ShenkyHub"



	if syn and type(syn.protect_gui) == "function" then



		pcall(syn.protect_gui, newGui)



	elseif typeof(protectgui) == "function" then



		pcall(protectgui, newGui)



	elseif typeof(protect_gui) == "function" then



		pcall(protect_gui, newGui)



	end



	newGui.Parent = parent]]



	)











	-- 1. Hilangkan 3 icon dot (windowControls) di kiri atas & rapatkan Sidebar/Header



	src = string.gsub(



		src,



		"windowControls%.Size = UDim2%.new%(1, 0, 0, 31%)",



		"windowControls.Size = UDim2.new(1, 0, 0, 0)\n\twindowControls.Visible = false\n\twindowControls.ClipsDescendants = true"



	)



	src = string.gsub(src, "information%.Position = UDim2%.fromOffset%(0, 31%)", "information.Position = UDim2.fromOffset(0, 0)")



	src = string.gsub(src, "information%.Size = UDim2%.new%(1, 0, 0, 60%)", "information.Size = UDim2.new(1, 0, 0, 42)")



	src = string.gsub(src, "informationHolderUIPadding%.PaddingLeft = UDim%.new%(0, 23%)", "informationHolderUIPadding.PaddingLeft = UDim.new(0, 14)")



	src = string.gsub(src, "informationHolderUIPadding%.PaddingRight = UDim%.new%(0, 22%)", "informationHolderUIPadding.PaddingRight = UDim.new(0, 12)")



	src = string.gsub(src, "divider2%.Parent = information", "divider2.Visible = false\n\tdivider2.Parent = information")



	src = string.gsub(



		src,



		"globalSettingsButton%.Size = UDim2%.fromOffset%(16,16%)",



		"globalSettingsButton.Size = UDim2.fromOffset(0, 0)\n\tglobalSettingsButton.Visible = false"



	)



	src = string.gsub(



		src,



		"titleFrame%.Size = UDim2%.fromScale%(1, 1%)",



		[[local brandLogo = Instance.new("Frame")



	brandLogo.Name = "BrandLogo"



	brandLogo.Size = UDim2.fromOffset(30, 30)



	brandLogo.AnchorPoint = Vector2.new(0, 0.5)



	brandLogo.Position = UDim2.new(0, 0, 0.5, 0)



	brandLogo.BackgroundTransparency = 1



	brandLogo.BorderSizePixel = 0











	local brandImg = Instance.new("ImageLabel")



	brandImg.Name = "Icon"



	brandImg.Size = UDim2.fromScale(1, 1)



	brandImg.BackgroundTransparency = 1



	brandImg.BorderSizePixel = 0



	brandImg.ScaleType = Enum.ScaleType.Fit



	local assetUri = typeof(getgenv().__SHENKY_LOGO_ASSET) == "string" and getgenv().__SHENKY_LOGO_ASSET or ""



	brandImg.Image = assetUri



	brandImg.Parent = brandLogo











	if assetUri == "" then



		local fallbackText = Instance.new("TextLabel")



		fallbackText.Size = UDim2.fromScale(1, 1)



		fallbackText.BackgroundTransparency = 1



		fallbackText.Text = "S"



		fallbackText.TextSize = 22



		fallbackText.FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.Bold)



		fallbackText.TextColor3 = Color3.fromRGB(0, 229, 255)



		fallbackText.Parent = brandLogo



	end











	brandLogo.Parent = informationHolder











	titleFrame.AnchorPoint = Vector2.new(0, 0.5)



	titleFrame.Position = UDim2.new(0, 36, 0.5, 0)



	titleFrame.Size = UDim2.new(1, -38, 0, 24)]]



	)



	src = string.gsub(



		src,



		"title%.Text = Settings%.Title",



		[[title.Text = "SHENKY HUB"



	title.FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.Bold, Enum.FontStyle.Normal)



	local titleGrad = Instance.new("UIGradient")
	titleGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(61, 128, 252)),   -- #3d80fc Solid Base
		ColorSequenceKeypoint.new(0.08, Color3.fromRGB(61, 128, 252)),   -- #3d80fc Leading Base
		ColorSequenceKeypoint.new(0.14, Color3.fromRGB(9, 47, 161)),     -- #092fa1 Deep Cobalt Shadow
		ColorSequenceKeypoint.new(0.22, Color3.fromRGB(0, 229, 255)),     -- #00E5FF Icy Cyan Leading Glow
		ColorSequenceKeypoint.new(0.30, Color3.fromRGB(136, 212, 252)), -- #88d4fc Soft Ice Blue Leading Slope
		ColorSequenceKeypoint.new(0.38, Color3.fromRGB(235, 246, 254)), -- #ebf6fe Glossy White Broad Core Start
		ColorSequenceKeypoint.new(0.62, Color3.fromRGB(235, 246, 254)), -- #ebf6fe Glossy White Broad Core End (24 pct Plateau)
		ColorSequenceKeypoint.new(0.70, Color3.fromRGB(136, 212, 252)), -- #88d4fc Soft Ice Blue Trailing Slope
		ColorSequenceKeypoint.new(0.78, Color3.fromRGB(0, 229, 255)),     -- #00E5FF Icy Cyan Trailing Glow
		ColorSequenceKeypoint.new(0.86, Color3.fromRGB(9, 47, 161)),     -- #092fa1 Deep Cobalt Shadow
		ColorSequenceKeypoint.new(0.92, Color3.fromRGB(61, 128, 252)),   -- #3d80fc Trailing Base
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(61, 128, 252)),   -- #3d80fc Solid Base
	})
	titleGrad.Offset = Vector2.new(-1.10, 0)
	titleGrad.Rotation = 18
	titleGrad.Parent = title

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(5, 11, 30) -- Deep Navy Outline (#050B1E)
	titleStroke.Thickness = 1.0
	titleStroke.Transparency = 0.35
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	titleStroke.Parent = title

	pcall(function()
		local ts = game:GetService("TweenService")
		local tween = ts:Create(
			titleGrad,
			TweenInfo.new(2.8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false),
			{ Offset = Vector2.new(1.10, 0) }
		)
		tween:Play()
	end)]]



	)



	src = string.gsub(src, "title%.Size = UDim2%.new%(1, %-20, 0, 0%)", "title.AutomaticSize = Enum.AutomaticSize.X\n\ttitle.Size = UDim2.new(0, 0, 1, 0)")



	src = string.gsub(src, "title%.TextTransparency = 0%.1", "title.TextTransparency = 0")



	src = string.gsub(src, "title%.TextTruncate = Enum%.TextTruncate%.SplitWord", "title.TextTruncate = Enum.TextTruncate.None")



	src = string.gsub(src, "title%.TextYAlignment = Enum%.TextYAlignment%.Top", "title.TextYAlignment = Enum.TextYAlignment.Center")



	src = string.gsub(src, "subtitle%.Size = UDim2%.new%(1, %-20, 0, 0%)", "pcall(function() subtitle:Destroy() end)")



	src = string.gsub(src, "titleFrameUIListLayout%.Padding = UDim%.new%(0, 3%)", "titleFrameUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center\n\ttitleFrameUIListLayout.Padding = UDim.new(0, 0)")



	src = string.gsub(src, "title%.TextSize = 18", "title.TextSize = 15")



	src = string.gsub(src, "subtitle%.TextSize = 12", "subtitle.TextSize = 11")



	src = string.gsub(src, "sidebarGroup%.Position = UDim2%.fromOffset%(0, 91%)", "sidebarGroup.Position = UDim2.fromOffset(0, 42)")



	src = string.gsub(src, "sidebarGroup%.Size = UDim2%.new%(1, 0, 1, %-91%)", "sidebarGroup.Size = UDim2.new(1, 0, 1, -42)")



	src = string.gsub(src, "sidebar%.Size = UDim2%.fromScale%(0%.325, 1%)", "sidebar.Size = UDim2.fromScale(0.205, 1)")



	src = string.gsub(src, "sidebarGroupUIPadding%.PaddingTop = UDim%.new%(0, 31%)", "sidebarGroupUIPadding.PaddingTop = UDim.new(0, 4)\n\tsidebarGroupUIPadding.PaddingLeft = UDim.new(0, 6)\n\tsidebarGroupUIPadding.PaddingRight = UDim.new(0, 6)")



	-- UserInfo & Profile Card Full-Width Docked Footer & Zero Hover
	src = string.gsub(src, "userInfo%.Parent = sidebarGroup", "userInfo.Parent = sidebar\n\tbase.ClipsDescendants = true")
	src = string.gsub(src, "userInfo%.Size = UDim2%.new%(1, 0, 0, 107%)", "userInfo.Position = UDim2.new(0, 0, 1, 0)\n\tuserInfo.Size = UDim2.new(1, 0, 0, 48)")
	src = string.gsub(src, "tabSwitchers%.Size = UDim2%.new%(1, 0, 1, %-107%)", "tabSwitchers.Size = UDim2.new(1, 0, 1, -48)")

	src = string.gsub(src, "userInfoUIPadding%.PaddingLeft = UDim%.new%(0, 10%)", "userInfoUIPadding.PaddingLeft = UDim.new(0, 0)")
	src = string.gsub(src, "userInfoUIPadding%.PaddingRight = UDim%.new%(0, 10%)", "userInfoUIPadding.PaddingRight = UDim.new(0, 0)")

	src = string.gsub(src, "informationGroup%.BackgroundTransparency = 1", [[informationGroup.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	informationGroup.BackgroundTransparency = 0.98
	local topDivider = Instance.new("Frame")
	topDivider.Name = "TopDivider"
	topDivider.Size = UDim2.new(1, 0, 0, 1)
	topDivider.Position = UDim2.new(0, 0, 0, 0)
	topDivider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	topDivider.BackgroundTransparency = 0.93
	topDivider.BorderSizePixel = 0
	topDivider.Parent = userInfo]])

	src = string.gsub(src, "informationGroupUIPadding%.PaddingBottom = UDim%.new%(0, 17%)", "informationGroupUIPadding.PaddingBottom = UDim.new(0, 0)\n\tinformationGroupUIPadding.PaddingTop = UDim.new(0, 0)")
	src = string.gsub(src, "informationGroupUIPadding%.PaddingLeft = UDim%.new%(0, 25%)", "informationGroupUIPadding.PaddingLeft = UDim.new(0, 12)\n\tinformationGroupUIPadding.PaddingRight = UDim.new(0, 8)")

	src = string.gsub(src, "headshot%.Size = UDim2%.fromOffset%(32, 32%)", "headshot.Size = UDim2.fromOffset(26, 26)")

	src = string.gsub(src, "userAndDisplayFrame%.Size = UDim2%.new%(1, %-42, 0, 32%)", "userAndDisplayFrame.Size = UDim2.new(1, -34, 0, 30)")
	src = string.gsub(src, "userAndDisplayFrameUIPadding%.PaddingLeft = UDim%.new%(0, 8%)", "userAndDisplayFrameUIPadding.PaddingLeft = UDim.new(0, 8)")
	src = string.gsub(src, "userAndDisplayFrameUIPadding%.PaddingTop = UDim%.new%(0, 3%)", "userAndDisplayFrameUIPadding.PaddingTop = UDim.new(0, 1)")
	src = string.gsub(src, "displayName%.TextTruncate = Enum%.TextTruncate%.SplitWord", "displayName.TextTruncate = Enum.TextTruncate.AtEnd")
	src = string.gsub(src, "username%.TextTruncate = Enum%.TextTruncate%.SplitWord", "username.TextTruncate = Enum.TextTruncate.AtEnd")


	src = string.gsub(src, "tabSwitchersScrollingFrameUIListLayout%.Padding = UDim%.new%(0, 17%)", "tabSwitchersScrollingFrameUIListLayout.Padding = UDim.new(0, 6)")



	src = string.gsub(src, "uIListLayout1%.Padding = UDim%.new%(0, 15%)", "uIListLayout1.Padding = UDim.new(0, 3)")



	src = string.gsub(src, "uIPadding1%.PaddingBottom = UDim%.new%(0, 15%)", "uIPadding1.PaddingBottom = UDim.new(0, 0)\n\tuIPadding1.PaddingTop = UDim.new(0, 0)")



	src = string.gsub(src, "tabSwitcher%.Size = UDim2%.new%(1, %-21, 0, 40%)", "tabSwitcher.Size = UDim2.new(1, -8, 0, 28)")



	src = string.gsub(src, "tabImage%.Size = UDim2%.fromOffset%(18, 18%)", "tabImage.Size = UDim2.fromOffset(14, 14)")



	src = string.gsub(src, "tabSwitcherName%.TextSize = 16", "tabSwitcherName.TextSize = 13")



	src = string.gsub(src, "tabSwitcherUIPadding%.PaddingLeft = UDim%.new%(0, 24%)", "tabSwitcherUIPadding.PaddingLeft = UDim.new(0, 12)")



	src = string.gsub(src, "tabSwitcherUIPadding%.PaddingRight = UDim%.new%(0, 35%)", "tabSwitcherUIPadding.PaddingRight = UDim.new(0, 10)")











	-- 2. Topbar & Content Area lebih rapat dan padat (seperti BigFroot)



	src = string.gsub(src, "topbar%.Size = UDim2%.new%(1, 0, 0, 63%)", "topbar.Size = UDim2.new(1, 0, 0, 40)")



	src = string.gsub(src, "divider4%.Parent = topbar", "divider4.Visible = false\n\tdivider4.Parent = topbar")

	src = string.gsub(src, "divider1%.Parent = windowControls", "divider1.Visible = false\n\tdivider1.Size = UDim2.new(0, 0, 0, 0)\n\tdivider1.Parent = windowControls")

	src = string.gsub(src, "divider3%.Parent = tabGroup", "divider3.Visible = false\n\tdivider3.Size = UDim2.new(0, 0, 0, 0)\n\tdivider3.Parent = tabGroup")



	src = string.gsub(src, "currentTab%.Size = UDim2%.fromScale%(0%.9, 0%)", "currentTab.Size = UDim2.new(1, -210, 0, 0)")



	src = string.gsub(src, "moveIcon%.Visible = not Settings%.DragStyle or Settings%.DragStyle == 1", "moveIcon.Visible = false\n\tmoveIcon.Size = UDim2.fromOffset(0, 0)")











	-- Brand Palette for Toggle Bar (Icy Cyan #00E5FF when ON, Glossy White Head #F0F8FF)



	src = string.gsub(



		src,



		"Tween%(toggle1, TweenSettings%.Info, %b{}%):Play%(%)",



		[[Tween(toggle1, TweenSettings.Info, {



							ImageTransparency = transparencyValues[1],



							ImageColor3 = State and Color3.fromRGB(160, 185, 255) or Color3.fromRGB(87, 86, 86)



						}):Play()]]



	)



	src = string.gsub(



		src,



		"local togglebool = ToggleFunctions%.Settings%.Default",



		[[local togglebool = ToggleFunctions.Settings.Default



					toggle1.ImageColor3 = togglebool and Color3.fromRGB(160, 185, 255) or Color3.fromRGB(87, 86, 86)



					togglerHead.ImageColor3 = Color3.fromRGB(240, 248, 255)]]



	)











	-- Full-Header Drag System (tidak bergantung pada button kecil, drag aktif di seluruh topbar & sidebar header)



	local dragStartIdx = string.find(src, "local dragging_ = false", 1, true)

	local dragEndIdx = string.find(src, "local currentTab = Instance.new(\"TextLabel\")", 1, true)

	if dragStartIdx and dragEndIdx and dragEndIdx > dragStartIdx then

		local newDragCode = [[local dragging_ = false

	local dragStart

	local startPos



	local function setupDragHandle(parentFrame)

		if not parentFrame then return end

		local handle = Instance.new("TextButton")

		handle.Name = "HeaderDragHandle"

		handle.Text = ""

		handle.BackgroundTransparency = 1

		handle.Size = UDim2.fromScale(1, 1)

		handle.Position = UDim2.fromScale(0, 0)

		handle.ZIndex = 0

		handle.Parent = parentFrame



		handle.InputBegan:Connect(function(input)

			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then

				dragging_ = true

				dragStart = input.Position

				startPos = base.Position



				input.Changed:Connect(function()

					if input.UserInputState == Enum.UserInputState.End then

						dragging_ = false

					end

				end)

			end

		end)

	end



	setupDragHandle(topbar)

	setupDragHandle(informationHolder)



	UserInputService.InputChanged:Connect(function(input)

		if dragging_ and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then

			local delta = input.Position - dragStart

			base.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)

		end

	end)



	UserInputService.InputEnded:Connect(function(input)

		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then

			dragging_ = false

		end

	end)]]

		src = string.sub(src, 1, dragStartIdx - 1) .. newDragCode .. "\n\n\t" .. string.sub(src, dragEndIdx)

	end

	src = string.gsub(



		src,



		"currentTab%.TextTransparency = 0%.5",



		"currentTab.TextTransparency = 0.05\n\tcurrentTab.TextColor3 = Color3.fromRGB(245, 248, 255)\n\tcurrentTab.FontFace = Font.new(\"rbxassetid://12187365364\", Enum.FontWeight.SemiBold)"



	)



	src = string.gsub(src, "elements1%.Position = UDim2%.fromOffset%(0, 63%)", "elements1.Position = UDim2.fromOffset(0, 40)")



	src = string.gsub(src, "elements1%.Size = UDim2%.new%(1, 0, 1, %-63%)", "elements1.Size = UDim2.new(1, 0, 1, -40)")



	src = string.gsub(src, "elementsUIPadding%.PaddingTop = UDim%.new%(0, 10%)", "elementsUIPadding.PaddingTop = UDim.new(0, 6)")



	src = string.gsub(src, "elementsUIPadding%.PaddingBottom = UDim%.new%(0, 10%)", "elementsUIPadding.PaddingBottom = UDim.new(0, 6)")



	src = string.gsub(src, "elementsScrollingUIListLayout%.Padding = UDim%.new%(0, 15%)", "elementsScrollingUIListLayout.Padding = UDim.new(0, 10)")



	src = string.gsub(src, "left%.Size = UDim2%.new%(0%.5, %-10, 0, 0%)", "left.Size = UDim2.new(0.5, -7, 0, 0)")



	src = string.gsub(src, "right%.Size = UDim2%.new%(0%.5, %-10, 0, 0%)", "right.Size = UDim2.new(0.5, -7, 0, 0)")



	src = string.gsub(src, "leftUIListLayout%.Padding = UDim%.new%(0, 15%)", "leftUIListLayout.Padding = UDim.new(0, 8)")



	src = string.gsub(src, "rightUIListLayout%.Padding = UDim%.new%(0, 15%)", "rightUIListLayout.Padding = UDim.new(0, 8)")











	-- 3. Section Card & Elemen Kontrol (Toggle, Slider, Button, Input, Dropdown, Header) lebih compact



	src = string.gsub(src, "sectionUIListLayout%.Padding = UDim%.new%(0, 10%)", "sectionUIListLayout.Padding = UDim.new(0, 8)")



	src = string.gsub(src, "sectionUIPadding%.PaddingBottom = UDim%.new%(0, 20%)", "sectionUIPadding.PaddingBottom = UDim.new(0, 10)")



	src = string.gsub(src, "sectionUIPadding%.PaddingLeft = UDim%.new%(0, 20%)", "sectionUIPadding.PaddingLeft = UDim.new(0, 12)")



	src = string.gsub(src, "sectionUIPadding%.PaddingRight = UDim%.new%(0, 18%)", "sectionUIPadding.PaddingRight = UDim.new(0, 12)")



	src = string.gsub(src, "sectionUIPadding%.PaddingTop = UDim%.new%(0, 22%)", "sectionUIPadding.PaddingTop = UDim.new(0, 10)")



	-- Luxury Section Header: Title Row (Lucide Icon + Text + Rotate Chevron) + Hairline Card Divider on Expand
	do
		local hStart = "function SectionFunctions:Header(Settings, Flag)"
		local hEnd = "function SectionFunctions:Label(Settings, Flag)"
		local hs = string.find(src, hStart, 1, true)
		local he = hs and string.find(src, hEnd, hs, true)
		if hs and he then
			local newHeaderCode = [[function SectionFunctions:Header(Settings, Flag)
					local HeaderFunctions = {Settings = Settings}

					local header = Instance.new("Frame")
					header.Name = "Header"
					header.AutomaticSize = Enum.AutomaticSize.Y
					header.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					header.BackgroundTransparency = 1
					header.BorderSizePixel = 0
					header.LayoutOrder = 0
					header.Size = UDim2.fromScale(1, 0)
					header.Parent = section

					local headerPadding = Instance.new("UIPadding")
					headerPadding.Name = "HeaderPadding"
					headerPadding.PaddingBottom = UDim.new(0, 4)
					headerPadding.Parent = header

					local headerList = Instance.new("UIListLayout")
					headerList.Name = "HeaderListLayout"
					headerList.SortOrder = Enum.SortOrder.LayoutOrder
					headerList.Padding = UDim.new(0, 7)
					headerList.Parent = header

					-- 1. Title Row Container (Icon + Text + Collapse Chevron)
					local headerRow = Instance.new("Frame")
					headerRow.Name = "HeaderRow"
					headerRow.BackgroundTransparency = 1
					headerRow.LayoutOrder = 1
					headerRow.Size = UDim2.new(1, 0, 0, 18)
					headerRow.Parent = header

					-- Resolve Icon
					local rawIcon = Settings.Icon or Settings.Image
					if not rawIcon or rawIcon == "" then
						local t = string.lower(tostring(Settings.Text or Settings.Name or ""))
						if string.find(t, "parry") or string.find(t, "defend") or string.find(t, "shield") or string.find(t, "guard") then
							rawIcon = "shield"
						elseif string.find(t, "counter") or string.find(t, "progress") or string.find(t, "zap") or string.find(t, "energy") then
							rawIcon = "zap"
						elseif string.find(t, "farm") or string.find(t, "boss") or string.find(t, "combat") or string.find(t, "attack") or string.find(t, "kill") or string.find(t, "sword") then
							rawIcon = "swords"
						elseif string.find(t, "time") or string.find(t, "timing") or string.find(t, "clock") or string.find(t, "delay") then
							rawIcon = "clock"
						elseif string.find(t, "target") or string.find(t, "aim") or string.find(t, "assist") or string.find(t, "crosshair") then
							rawIcon = "crosshair"
						elseif string.find(t, "move") or string.find(t, "speed") or string.find(t, "server") or string.find(t, "teleport") or string.find(t, "flight") or string.find(t, "hop") then
							rawIcon = "activity"
						elseif string.find(t, "input") or string.find(t, "text") or string.find(t, "field") or string.find(t, "spam") or string.find(t, "message") or string.find(t, "chat") then
							rawIcon = "terminal"
						elseif string.find(t, "color") or string.find(t, "theme") or string.find(t, "visual") or string.find(t, "esp") or string.find(t, "render") or string.find(t, "glow") then
							rawIcon = "palette"
						elseif string.find(t, "notif") or string.find(t, "toast") or string.find(t, "hotkey") or string.find(t, "keybind") or string.find(t, "bind") or string.find(t, "bell") or string.find(t, "alert") then
							rawIcon = "bell"
						elseif string.find(t, "player") or string.find(t, "character") or string.find(t, "user") or string.find(t, "avatar") then
							rawIcon = "user"
						elseif string.find(t, "stat") or string.find(t, "level") or string.find(t, "score") or string.find(t, "metric") or string.find(t, "chart") then
							rawIcon = "bar-chart"
						elseif string.find(t, "status") or string.find(t, "session") or string.find(t, "telemetry") or string.find(t, "ping") or string.find(t, "fps") then
							rawIcon = "clock"
						elseif string.find(t, "action") or string.find(t, "quick") or string.find(t, "button") then
							rawIcon = "zap"
						elseif string.find(t, "home") or string.find(t, "main") or string.find(t, "dashboard") then
							rawIcon = "home"
						elseif string.find(t, "config") or string.find(t, "setting") or string.find(t, "option") or string.find(t, "misc") or string.find(t, "utility") or string.find(t, "tool") then
							rawIcon = "sliders"
						else
							rawIcon = "box"
						end
					end

					local IconsModule = (getgenv and getgenv().__SHENKY_ICONS)
					local resolvedAsset = (IconsModule and IconsModule.Resolve and IconsModule.Resolve(rawIcon))
					if not resolvedAsset or resolvedAsset == "" then
						local fallbackMap = {
							shield = "rbxassetid://10734951847",
							zap = "rbxassetid://10747384394",
							swords = "rbxassetid://10734975692",
							sword = "rbxassetid://10734975486",
							clock = "rbxassetid://10709805144",
							crosshair = "rbxassetid://10709818534",
							target = "rbxassetid://10734977012",
							activity = "rbxassetid://10709752035",
							terminal = "rbxassetid://10734982144",
							palette = "rbxassetid://10734910430",
							bell = "rbxassetid://10709775704",
							user = "rbxassetid://10747373176",
							sliders = "rbxassetid://10734963400",
							box = "rbxassetid://10709782497",
						}
						resolvedAsset = fallbackMap[string.lower(tostring(rawIcon))] or "rbxassetid://10709782497"
					end

					local headerIcon = Instance.new("ImageLabel")
					headerIcon.Name = "HeaderIcon"
					headerIcon.Image = resolvedAsset
					headerIcon.Size = UDim2.fromOffset(14, 14)
					headerIcon.Position = UDim2.new(0, 0, 0.5, 0)
					headerIcon.AnchorPoint = Vector2.new(0, 0.5)
					headerIcon.BackgroundTransparency = 1
					headerIcon.ImageColor3 = Color3.fromRGB(160, 185, 255)
					headerIcon.ImageTransparency = 0.20
					headerIcon.Parent = headerRow

					local headerText = Instance.new("TextLabel")
					headerText.Name = "HeaderText"
					headerText.FontFace = Font.new(assets.interFont, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
					headerText.RichText = true
					headerText.Text = Settings.Text or Settings.Name or "Section"
					headerText.TextColor3 = Color3.fromRGB(240, 245, 255)
					headerText.TextSize = 13
					headerText.TextTransparency = 0.20
					headerText.TextXAlignment = Enum.TextXAlignment.Left
					headerText.TextTruncate = Enum.TextTruncate.AtEnd
					headerText.Position = UDim2.new(0, 21, 0.5, 0)
					headerText.AnchorPoint = Vector2.new(0, 0.5)
					headerText.Size = UDim2.new(1, -42, 1, 0)
					headerText.BackgroundTransparency = 1
					headerText.Parent = headerRow

					local collapseIcon = Instance.new("ImageLabel")
					collapseIcon.Name = "CollapseIcon"
					collapseIcon.Image = "rbxassetid://10709790948"
					collapseIcon.Size = UDim2.fromOffset(13, 13)
					collapseIcon.AnchorPoint = Vector2.new(1, 0.5)
					collapseIcon.Position = UDim2.new(1, 0, 0.5, 0)
					collapseIcon.BackgroundTransparency = 1
					collapseIcon.ImageTransparency = 0.40
					collapseIcon.ImageColor3 = Color3.fromRGB(200, 210, 230)
					collapseIcon.Parent = headerRow

					-- 2. Hairline Content Card Divider (visible on expand)
					local headerDivider = Instance.new("Frame")
					headerDivider.Name = "HeaderDivider"
					headerDivider.Size = UDim2.new(1, 0, 0, 1)
					headerDivider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					headerDivider.BackgroundTransparency = 0.90
					headerDivider.BorderSizePixel = 0
					headerDivider.LayoutOrder = 2
					headerDivider.Visible = true
					headerDivider.Parent = header

					-- Interact button covering headerRow
					local headerInteract = Instance.new("TextButton")
					headerInteract.Name = "HeaderInteract"
					headerInteract.Text = ""
					headerInteract.BackgroundTransparency = 1
					headerInteract.Size = UDim2.fromScale(1, 1)
					headerInteract.ZIndex = 3
					headerInteract.Parent = headerRow

					local isExpanded = true
					headerInteract.MouseButton1Click:Connect(function()
						isExpanded = not isExpanded
						headerDivider.Visible = isExpanded
						Tween(collapseIcon, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Rotation = isExpanded and 0 or -90
						}):Play()
						for _, child in ipairs(section:GetChildren()) do
							if child ~= header and child:IsA("GuiObject") and not child:IsA("UIStroke") and not child:IsA("UICorner") and not child:IsA("UIPadding") and not child:IsA("UIListLayout") then
								child.Visible = isExpanded
							end
						end
					end)

					headerInteract.MouseEnter:Connect(function()
						Tween(collapseIcon, TweenInfo.new(0.2, Enum.EasingStyle.Sine), { ImageTransparency = 0.15 }):Play()
						Tween(headerText, TweenInfo.new(0.2, Enum.EasingStyle.Sine), { TextTransparency = 0.05 }):Play()
						Tween(headerIcon, TweenInfo.new(0.2, Enum.EasingStyle.Sine), { ImageTransparency = 0.05 }):Play()
					end)
					headerInteract.MouseLeave:Connect(function()
						Tween(collapseIcon, TweenInfo.new(0.2, Enum.EasingStyle.Sine), { ImageTransparency = 0.40 }):Play()
						Tween(headerText, TweenInfo.new(0.2, Enum.EasingStyle.Sine), { TextTransparency = 0.20 }):Play()
						Tween(headerIcon, TweenInfo.new(0.2, Enum.EasingStyle.Sine), { ImageTransparency = 0.20 }):Play()
					end)

					function HeaderFunctions:UpdateName(New)
						headerText.Text = New
					end
					function HeaderFunctions:SetIcon(newIcon)
						local res = (IconsModule and IconsModule.Resolve and IconsModule.Resolve(newIcon)) or newIcon
						headerIcon.Image = res
					end
					function HeaderFunctions:SetVisibility(State)
						header.Visible = State
					end

					if Flag then
						MacLib.Options[Flag] = HeaderFunctions
					end
					return HeaderFunctions
				end

				]]
			src = string.sub(src, 1, hs - 1) .. newHeaderCode .. string.sub(src, he)
		end
	end











	-- Tinggi kontrol: 38px -> 26px (muat ~2x lebih banyak kontrol dalam 1 layar)



	-- Component Architecture Delegation: Button, Toggle, Slider, Dropdown (shared/src-hub/components/)
	do
		-- 1. Delegate Button to components/Button.luau
		local bStart = ":Button(Settings, Flag)\n\t\t\t\t\tlocal ButtonFunctions = {Settings = Settings}"
		local bEnd = "function SectionFunctions:Toggle(Settings, Flag)"
		local bs = string.find(src, bStart, 1, true)
		local be = bs and string.find(src, bEnd, bs, true)
		if bs and be then
			local newBtnCode = [[:Button(Settings, Flag)
					local ButtonClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Button)
					if ButtonClass then
						return ButtonClass.new(section, Settings, Flag, MacLib)
					end
				end

				function SectionFunctions:MetricGrid(Settings, Flag)
					local MetricGridClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.MetricGrid)
					if MetricGridClass then
						return MetricGridClass.new(section, Settings, Flag, MacLib)
					end
				end

				function SectionFunctions:ButtonRow(buttonsList, Flag)
					local ButtonClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Button)
					local Theme = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Theme)
					if not ButtonClass or not Theme or type(buttonsList) ~= "table" then return end

					local rowContainer = Instance.new("Frame")
					rowContainer.Name = "ButtonRow"
					rowContainer.BackgroundTransparency = 1
					rowContainer.BorderSizePixel = 0
					rowContainer.Size = UDim2.new(1, 0, 0, Theme.Geometry.ButtonHeight)
					rowContainer.Parent = section

					local rowLayout = Instance.new("UIListLayout")
					rowLayout.Name = "ButtonRowLayout"
					rowLayout.FillDirection = Enum.FillDirection.Horizontal
					rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
					rowLayout.Padding = UDim.new(0, 6)
					rowLayout.Parent = rowContainer

					local count = #buttonsList
					local btnObjects = {}
					for i, bCfg in ipairs(buttonsList) do
						local bScale = 1 / count
						local bOffset = -math.floor(6 * (count - 1) / count + 0.5)
						local btn = ButtonClass.new(rowContainer, bCfg, bCfg.Flag, MacLib)
						if btn and btn.Instance then
							btn.Instance.Size = UDim2.new(bScale, bOffset, 1, 0)
						end
						table.insert(btnObjects, btn)
					end

					return {
						Instance = rowContainer,
						Buttons = btnObjects,
						SetVisibility = function(self, state)
							rowContainer.Visible = (state == true)
						end,
						Destroy = function(self)
							rowContainer:Destroy()
						end,
					}
				end

				]]
			src = string.sub(src, 1, bs - 1) .. newBtnCode .. string.sub(src, be)
		end

		-- 2. Delegate Toggle to components/Toggle.luau
		local tStart = ":Toggle(Settings, Flag)\n\t\t\t\t\tlocal ToggleFunctions = { Settings = Settings, IgnoreConfig = false, Class = \"Toggle\" }"
		local tEnd = "function SectionFunctions:Slider(Settings, Flag)"
		local ts = string.find(src, tStart, 1, true)
		local te = ts and string.find(src, tEnd, ts, true)
		if ts and te then
			local newToggleCode = [[:Toggle(Settings, Flag)
					local ToggleClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Toggle)
					if ToggleClass then
						return ToggleClass.new(section, Settings, Flag, MacLib)
					end
				end

				]]
			src = string.sub(src, 1, ts - 1) .. newToggleCode .. string.sub(src, te)
		end

		-- 3. Delegate Slider to components/Slider.luau
		local sStart = ":Slider(Settings, Flag)\n\t\t\t\t\tlocal SliderFunctions = { Settings = Settings, IgnoreConfig = false, Class = \"Slider\" }"
		local sEnd = "function SectionFunctions:Input(Settings, Flag)"
		local ss = string.find(src, sStart, 1, true)
		local se = ss and string.find(src, sEnd, ss, true)
		if ss and se then
			local newSliderCode = [[:Slider(Settings, Flag)
					local SliderClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Slider)
					if SliderClass then
						return SliderClass.new(section, Settings, Flag, MacLib)
					end
				end

				]]
			src = string.sub(src, 1, ss - 1) .. newSliderCode .. string.sub(src, se)
		end

		-- 4. Delegate Dropdown to components/Dropdown.luau
		local dStart = ":Dropdown(Settings, Flag)\n\t\t\t\t\tlocal DropdownFunctions = { Settings = Settings, IgnoreConfig = false, Class = \"Dropdown\" }"
		local dEnd = "function SectionFunctions:Colorpicker(Settings, Flag)"
		local ds = string.find(src, dStart, 1, true)
		local de = ds and string.find(src, dEnd, ds, true)
		if ds and de then
			local newDropCode = [[:Dropdown(Settings, Flag)
					local DropdownClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Dropdown)
					if DropdownClass then
						return DropdownClass.new(section, Settings, Flag, MacLib)
					end
				end

				]]
			src = string.sub(src, 1, ds - 1) .. newDropCode .. string.sub(src, de)
		end

		-- 5. Delegate Input to components/Input.luau & add Checkbox / ProgressBar methods
		local iStart = ":Input(Settings, Flag)\n\t\t\t\t\tlocal InputFunctions = { Settings = Settings, IgnoreConfig = false, Class = \"Input\" }"
		local iEnd = "function SectionFunctions:Keybind(Settings, Flag)"
		local is = string.find(src, iStart, 1, true)
		local ie = is and string.find(src, iEnd, is, true)
		if is and ie then
			local newDelegationCode = [[:Input(Settings, Flag)
					local InputClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Input)
					if InputClass then
						return InputClass.new(section, Settings, Flag, MacLib)
					end
				end

				function SectionFunctions:Checkbox(Settings, Flag)
					local CheckboxClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Checkbox)
					if CheckboxClass then
						return CheckboxClass.new(section, Settings, Flag, MacLib)
					end
				end

				function SectionFunctions:ProgressBar(Settings, Flag)
					local ProgressBarClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.ProgressBar)
					if ProgressBarClass then
						return ProgressBarClass.new(section, Settings, Flag, MacLib)
					end
				end

				function SectionFunctions:SegmentedControl(Settings, Flag)
					local SegmentedControlClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.SegmentedControl)
					if SegmentedControlClass then
						return SegmentedControlClass.new(section, Settings, Flag, MacLib)
					end
				end

				function SectionFunctions:Badge(Settings)
					local BadgeClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Badge)
					if BadgeClass then
						return BadgeClass.new(section, Settings)
					end
				end

				function SectionFunctions:History(Settings, Flag)
					local HistoryClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.History)
					if HistoryClass then
						return HistoryClass.new(section, Settings, Flag, MacLib)
					end
				end

				function SectionFunctions:HistoryLog(Settings, Flag)
					return SectionFunctions:History(Settings, Flag)
				end

				]]
			src = string.sub(src, 1, is - 1) .. newDelegationCode .. string.sub(src, ie)
		end

		-- 6. Delegate Keybind to components/Keybind.luau
		local kStart = ":Keybind(Settings, Flag)\n\t\t\t\t\tlocal KeybindFunctions = { Settings = Settings, IgnoreConfig = false, Class = \"Keybind\" }"
		local kEnd = "function SectionFunctions:Dropdown(Settings, Flag)"
		local ks = string.find(src, kStart, 1, true)
		local ke = ks and string.find(src, kEnd, ks, true)
		if ks and ke then
			local newKeyCode = [[:Keybind(Settings, Flag)
					local KeybindClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Keybind)
					if KeybindClass then
						return KeybindClass.new(section, Settings, Flag, MacLib)
					end
				end

				]]
			src = string.sub(src, 1, ks - 1) .. newKeyCode .. string.sub(src, ke)
		end

		-- 7. Delegate Colorpicker to components/Colorpicker.luau
		local cStart = ":Colorpicker(Settings, Flag)\n\t\t\t\t\tlocal ColorpickerFunctions = { Settings = Settings, IgnoreConfig = false, Class = \"Colorpicker\" }"
		local cEnd = "function SectionFunctions:Header(Settings, Flag)"
		local cs = string.find(src, cStart, 1, true)
		local ce = cs and string.find(src, cEnd, cs, true)
		if cs and ce then
			local newColCode = [[:Colorpicker(Settings, Flag)
					local ColorpickerClass = (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Colorpicker)
					if ColorpickerClass then
						return ColorpickerClass.new(section, Settings, Flag, MacLib)
					end
				end

				]]
			src = string.sub(src, 1, cs - 1) .. newColCode .. string.sub(src, ce)
		end
	end

	-- Sidebar Redesign & Breadcrumbs: TabSwitcher height, ActiveIndicator pill, and dynamic category breadcrumbs
	do
		-- A. Tab group switcher spacing: 15px -> 3px
		src = string.gsub(src, "uIListLayout1%.Padding = UDim%.new%(0, 15%)", "uIListLayout1.Padding = UDim.new(0, 3)")
		src = string.gsub(src, "uIPadding1%.PaddingBottom = UDim%.new%(0, 15%)", "uIPadding1.PaddingBottom = UDim.new(0, 6)")

		-- B. TabSwitcher styling & ActiveIndicator pill creation
		local tsOldStart = 'local tabSwitcher = Instance.new("TextButton")\n\t\t\ttabSwitcher.Name = "TabSwitcher"'
		local tsOldEnd = 'tabSwitcher.Parent = sectionTabSwitchers'
		local tsS = string.find(src, tsOldStart, 1, true)
		local tsE = tsS and string.find(src, tsOldEnd, tsS, true)
		if tsS and tsE then
			local newTsCode = [[local tabSwitcher = Instance.new("TextButton")
			tabSwitcher.Name = "TabSwitcher"
			tabSwitcher.FontFace = Font.new(assets.interFont, Enum.FontWeight.Medium, Enum.FontStyle.Normal)
			tabSwitcher.Text = ""
			tabSwitcher.AutoButtonColor = false
			tabSwitcher.AnchorPoint = Vector2.new(0, 0)
			tabSwitcher.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			tabSwitcher.BackgroundTransparency = 1
			tabSwitcher.BorderSizePixel = 0
			tabSwitcher.Position = UDim2.new(0, 0, 0, 0)
			tabSwitcher.Size = UDim2.new(1, 0, 0, 28)

			tabIndex += 1
			tabSwitcher.LayoutOrder = tabIndex

			local tabSwitcherUICorner = Instance.new("UICorner")
			tabSwitcherUICorner.Name = "TabSwitcherUICorner"
			tabSwitcherUICorner.CornerRadius = UDim.new(0, 6)
			tabSwitcherUICorner.Parent = tabSwitcher

			local tabSwitcherUIStroke = Instance.new("UIStroke")
			tabSwitcherUIStroke.Name = "TabSwitcherUIStroke"
			tabSwitcherUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			tabSwitcherUIStroke.Color = Color3.fromRGB(255, 255, 255)
			tabSwitcherUIStroke.Transparency = 1
			tabSwitcherUIStroke.Parent = tabSwitcher

			-- Shenky Hub Signature: Left Vertical Active Indicator Bar (|) on button edge
			local activePill = Instance.new("Frame")
			activePill.Name = "ActiveIndicator"
			activePill.AnchorPoint = Vector2.new(0, 0.5)
			activePill.Position = UDim2.new(0, 0, 0.5, 0)
			activePill.Size = UDim2.new(0, 3, 0, 16)
			activePill.BackgroundColor3 = Color3.fromRGB(160, 185, 255)
			activePill.BackgroundTransparency = 1
			activePill.BorderSizePixel = 0
			activePill.Parent = tabSwitcher

			local activePillCorner = Instance.new("UICorner")
			activePillCorner.CornerRadius = UDim.new(0, 2)
			activePillCorner.Parent = activePill

			-- Inner content frame isolates list layout so activePill doesn't push the icon
			local tabContent = Instance.new("Frame")
			tabContent.Name = "TabContent"
			tabContent.BackgroundTransparency = 1
			tabContent.BorderSizePixel = 0
			tabContent.Size = UDim2.fromScale(1, 1)
			tabContent.Parent = tabSwitcher

			local tabContentUIPadding = Instance.new("UIPadding")
			tabContentUIPadding.Name = "TabContentUIPadding"
			tabContentUIPadding.PaddingLeft = UDim.new(0, 6)
			tabContentUIPadding.PaddingRight = UDim.new(0, 6)
			tabContentUIPadding.Parent = tabContent

			local tabSwitcherUIListLayout = Instance.new("UIListLayout")
			tabSwitcherUIListLayout.Name = "TabSwitcherUIListLayout"
			tabSwitcherUIListLayout.Padding = UDim.new(0, 6)
			tabSwitcherUIListLayout.FillDirection = Enum.FillDirection.Horizontal
			tabSwitcherUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
			tabSwitcherUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			tabSwitcherUIListLayout.Parent = tabContent

			local tabImage
			if Settings.Image then
				tabImage = Instance.new("ImageLabel")
				tabImage.Name = "TabImage"
				tabImage.Image = Settings.Image
				tabImage.ImageTransparency = 0.5
				tabImage.ImageColor3 = Color3.fromRGB(160, 170, 190)
				tabImage.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				tabImage.BackgroundTransparency = 1
				tabImage.BorderSizePixel = 0
				tabImage.Size = UDim2.fromOffset(15, 15)
				tabImage.Parent = tabContent
			end

			local tabSwitcherName = Instance.new("TextLabel")
			tabSwitcherName.Name = "TabSwitcherName"
			tabSwitcherName.FontFace = Font.new(
				assets.interFont,
				Enum.FontWeight.Medium,
				Enum.FontStyle.Normal
			)
			tabSwitcherName.Text = Settings.Name
			tabSwitcherName.RichText = true
			tabSwitcherName.TextColor3 = Color3.fromRGB(170, 178, 195)
			tabSwitcherName.TextSize = 12
			tabSwitcherName.TextTransparency = 0.35
			tabSwitcherName.TextTruncate = Enum.TextTruncate.SplitWord
			tabSwitcherName.TextXAlignment = Enum.TextXAlignment.Left
			tabSwitcherName.TextYAlignment = Enum.TextYAlignment.Center
			tabSwitcherName.AutomaticSize = Enum.AutomaticSize.Y
			tabSwitcherName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			tabSwitcherName.BackgroundTransparency = 1
			tabSwitcherName.BorderSizePixel = 0
			tabSwitcherName.Size = UDim2.fromScale(1, 0)
			tabSwitcherName.Parent = tabContent
			tabSwitcherName.LayoutOrder = 1

			tabSwitcher.Parent = sectionTabSwitchers]]
			src = string.sub(src, 1, tsS - 1) .. newTsCode .. string.sub(src, tsE + #tsOldEnd)
		end

		-- C. Store activePill and Category metadata in tabs table
		local tabsOld = 'tabs[tabSwitcher] = {\n\t\t\t\ttabContent = elements1,\n\t\t\t\ttabStroke = tabSwitcherUIStroke,\n\t\t\t\tswitcherImage = tabImage,\n\t\t\t\tswitcherName = tabSwitcherName,\n\t\t\t}'
		local tabsNew = [[tabs[tabSwitcher] = {
				tabContent = elements1,
				tabStroke = tabSwitcherUIStroke,
				switcherImage = tabImage,
				switcherName = tabSwitcherName,
				activePill = activePill,
				category = Settings.Category,
			}]]
		src = string.gsub(src, tabsOld, tabsNew, 1)

		-- D. Patch SelectCurrentTab() for dynamic Breadcrumbs and smooth active indicator tweening
		local sctOldStart = 'local function SelectCurrentTab()\n\t\t\t\tlocal easetime = 0.15'
		local sctOldEnd = 'tabSwitcher.MouseButton1Click:Connect(function()'
		local sctS = string.find(src, sctOldStart, 1, true)
		local sctE = sctS and string.find(src, sctOldEnd, sctS, true)
		if sctS and sctE then
			local newSctCode = [[local function SelectCurrentTab()
				local easetime = 0.15

				if currentTabInstance then
					currentTabInstance.Parent = nil
				end

				for i, tabInfo in pairs(tabs) do
					local isSelected = (i == tabSwitcher)
					Tween(i, TweenInfo.new(easetime, Enum.EasingStyle.Sine), {
						BackgroundTransparency = (isSelected and 0.94 or 1),
						BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					}):Play()

					if tabInfo.activePill then
						Tween(tabInfo.activePill, TweenInfo.new(easetime, Enum.EasingStyle.Sine), {
							BackgroundTransparency = (isSelected and 0 or 1),
						}):Play()
					end
					if tabInfo.tabStroke then
						Tween(tabInfo.tabStroke, TweenInfo.new(easetime, Enum.EasingStyle.Sine), {
							Transparency = 1,
						}):Play()
					end
					if tabInfo.switcherImage then
						Tween(tabInfo.switcherImage, TweenInfo.new(easetime, Enum.EasingStyle.Sine), {
							ImageTransparency = (isSelected and 0.05 or 0.5),
							ImageColor3 = (isSelected and Color3.fromRGB(220, 235, 255) or Color3.fromRGB(160, 170, 190)),
						}):Play()
					end
					if tabInfo.switcherName then
						Tween(tabInfo.switcherName, TweenInfo.new(easetime, Enum.EasingStyle.Sine), {
							TextTransparency = (isSelected and 0.0 or 0.35),
							TextColor3 = (isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(170, 178, 195)),
						}):Play()
					end
				end

				tabs[tabSwitcher].tabContent.Parent = content
				currentTabInstance = tabs[tabSwitcher].tabContent

				local catName = Settings.Category or (tabs[tabSwitcher] and tabs[tabSwitcher].category)
				if catName and tostring(catName) ~= "" then
					currentTab.Text = string.format("<font color=\"rgb(160, 185, 255)\"><font size=\"13\">%s</font></font>  <font color=\"rgb(100, 110, 135)\"><font size=\"12\">\u{203A}</font></font>  <font color=\"rgb(245, 248, 255)\"><font size=\"13\">%s</font></font>", tostring(catName), tostring(Settings.Name))
				else
					currentTab.Text = string.format("<font color=\"rgb(245, 248, 255)\"><font size=\"13\">%s</font></font>", tostring(Settings.Name))
				end
			end

			]]
			src = string.sub(src, 1, sctS - 1) .. newSctCode .. string.sub(src, sctE)
		end
	end

	-- Colorpicker styling: Compact 28px row, 32x17 rounded pill swatch with UIStroke & hover scale, and modernized Prompt modal
	src = string.gsub(src, "colorpicker%.Size = UDim2%.new%(1, 0, 0, 38%)", "colorpicker.Size = UDim2.new(1, 0, 0, 28)")

	-- Fix Colorpicker preview swatch opacity:
	-- MacLib treated Alpha as Transparency (1 = invisible, 0 = solid), causing swatches with Alpha=1 to render 100% transparent checkerboard.
	-- We enforce Opacity semantics: BackgroundTransparency = isAlpha and (1 - (Alpha or 1)) or 0
	src = string.gsub(
		src,
		"colorC%.BackgroundTransparency = ColorpickerFunctions%.Alpha or 0",
		"colorC.BackgroundTransparency = isAlpha and (1 - (ColorpickerFunctions.Alpha or 1)) or 0"
	)
	src = string.gsub(
		src,
		"colorC%.Transparency = alpha",
		"colorC.BackgroundTransparency = isAlpha and (1 - alpha) or 0"
	)
	src = string.gsub(
		src,
		"function ColorpickerFunctions:SetColor%(color3%)\n\t\t\t\t\t\tColorpickerFunctions%.Color = color3\n\t\t\t\t\t\tcolorC%.BackgroundColor3 = color3",
		[[function ColorpickerFunctions:SetColor(color3)
						ColorpickerFunctions.Color = color3
						colorC.BackgroundColor3 = color3
						colorC.BackgroundTransparency = isAlpha and (1 - (ColorpickerFunctions.Alpha or 1)) or 0]]
	)
	src = string.gsub(
		src,
		"colorpickerName%.TextSize = 13",
		[[colorpickerName.TextSize = 12
					colorpickerName.TextColor3 = Color3.fromRGB(240, 245, 255)
					colorpickerName.TextTransparency = 0.25
					colorpickerName.FontFace = Font.new(assets.interFont, Enum.FontWeight.Medium, Enum.FontStyle.Normal)]]
	)

	do
		local oldColorCbg = [[local colorCbg = Instance.new("ImageLabel")
					colorCbg.Name = "NewColor"
					colorCbg.Image = assets.grid
					colorCbg.ScaleType = Enum.ScaleType.Tile
					colorCbg.TileSize = UDim2.fromOffset(500, 500)
					colorCbg.AnchorPoint = Vector2.new(1, 0.5)
					colorCbg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					colorCbg.BackgroundTransparency = 1
					colorCbg.BorderColor3 = Color3.fromRGB(0, 0, 0)
					colorCbg.BorderSizePixel = 0
					colorCbg.Position = UDim2.fromScale(1, 0.5)
					colorCbg.Size = UDim2.fromOffset(21, 21)]]

		local newColorCbg = [[local colorCbg = Instance.new("ImageLabel")
					colorCbg.Name = "NewColor"
					colorCbg.Image = assets.grid
					colorCbg.ScaleType = Enum.ScaleType.Tile
					colorCbg.TileSize = UDim2.fromOffset(500, 500)
					colorCbg.AnchorPoint = Vector2.new(1, 0.5)
					colorCbg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					colorCbg.BackgroundTransparency = 1
					colorCbg.BorderSizePixel = 0
					colorCbg.Position = UDim2.fromScale(1, 0.5)
					colorCbg.Size = UDim2.fromOffset(32, 17)

					local swatchCorner = Instance.new("UICorner")
					swatchCorner.CornerRadius = UDim.new(0, 5)
					swatchCorner.Parent = colorCbg

					local swatchStroke = Instance.new("UIStroke")
					swatchStroke.Name = "SwatchStroke"
					swatchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					swatchStroke.Color = Color3.fromRGB(255, 255, 255)
					swatchStroke.Transparency = 0.82
					swatchStroke.Thickness = 1.0
					swatchStroke.Parent = colorCbg

					local swatchScale = Instance.new("UIScale")
					swatchScale.Name = "SwatchScale"
					swatchScale.Parent = colorCbg]]

		local cs, ce = string.find(src, oldColorCbg, 1, true)
		if cs and ce then
			src = string.sub(src, 1, cs - 1) .. newColorCbg .. string.sub(src, ce + 1)
		end
	end

	do
		local oldColorCorner = [[local uICorner = Instance.new("UICorner")
					uICorner.Name = "UICorner"
					uICorner.CornerRadius = UDim.new(0, 6)
					uICorner.Parent = colorC]]

		local newColorCorner = [[local uICorner = Instance.new("UICorner")
					uICorner.Name = "UICorner"
					uICorner.CornerRadius = UDim.new(0, 5)
					uICorner.Parent = colorC]]

		local cs, ce = string.find(src, oldColorCorner, 1, true)
		if cs and ce then
			src = string.sub(src, 1, cs - 1) .. newColorCorner .. string.sub(src, ce + 1)
		end
	end

	do
		local oldInteractSetup = [[colorC.Parent = colorCbg]]
		local newInteractSetup = [[colorC.Parent = colorCbg

					interact.MouseEnter:Connect(function()
						local s = colorCbg:FindFirstChild("SwatchStroke")
						local sc = colorCbg:FindFirstChild("SwatchScale")
						if s then Tween(s, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Color = Color3.fromRGB(0, 150, 255), Transparency = 0.35 }):Play() end
						if sc then Tween(sc, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Scale = 1.08 }):Play() end
						Tween(colorpickerName, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { TextTransparency = 0 }):Play()
					end)
					interact.MouseLeave:Connect(function()
						local s = colorCbg:FindFirstChild("SwatchStroke")
						local sc = colorCbg:FindFirstChild("SwatchScale")
						if s then Tween(s, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.82 }):Play() end
						if sc then Tween(sc, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Scale = 1.0 }):Play() end
						Tween(colorpickerName, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { TextTransparency = 0.25 }):Play()
					end)]]

		local cs, ce = string.find(src, oldInteractSetup, 1, true)
		if cs and ce then
			src = string.sub(src, 1, cs - 1) .. newInteractSetup .. string.sub(src, ce + 1)
		end
	end

-- Streamlined Gaming Colorpicker Modal: Compact 250px, no desktop bloat, real-time auto-apply
	src = string.gsub(src, "prompt%.Size = UDim2%.fromOffset%(420, 0%)", "prompt.Size = UDim2.fromOffset(250, 0)")
	src = string.gsub(src, "prompt%.BackgroundColor3 = Color3%.fromRGB%(15, 15, 15%)", "prompt.BackgroundColor3 = Color3.fromRGB(15, 17, 23)")
	src = string.gsub(src, "globalSettingsUIStroke%.Transparency = 0%.9", "globalSettingsUIStroke.Transparency = 0.88\n\t\t\t\t\tglobalSettingsUIStroke.Thickness = 1.0")
	src = string.gsub(src, "globalSettingsUICorner%.CornerRadius = UDim%.new%(0, 10%)", "globalSettingsUICorner.CornerRadius = UDim.new(0, 12)")
	src = string.gsub(src, "uIListLayout%.Padding = UDim%.new%(0, 10%)", "uIListLayout.Padding = UDim.new(0, 10)")

	-- Header Paragraph: sleek fixed 22px header with title and close '✕' button
	do
		local oldParaBlock = [[local paragraph = Instance.new("Frame")
					paragraph.Name = "Paragraph"
					paragraph.AutomaticSize = Enum.AutomaticSize.Y
					paragraph.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					paragraph.BackgroundTransparency = 1
					paragraph.BorderColor3 = Color3.fromRGB(0, 0, 0)
					paragraph.BorderSizePixel = 0
					paragraph.Size = UDim2.fromScale(1, 0)

					local paragraphHeader = Instance.new("TextLabel")
					paragraphHeader.Name = "ParagraphHeader"
					paragraphHeader.FontFace = Font.new(
						"rbxassetid://12187365364",
						Enum.FontWeight.SemiBold,
						Enum.FontStyle.Normal
					)
					paragraphHeader.RichText = true
					paragraphHeader.Text = ColorpickerFunctions.Settings.Name
					paragraphHeader.TextColor3 = Color3.fromRGB(255, 255, 255)
					paragraphHeader.TextSize = 18
					paragraphHeader.TextTransparency = 0.4
					paragraphHeader.TextWrapped = true
					paragraphHeader.TextYAlignment = Enum.TextYAlignment.Top
					paragraphHeader.AutomaticSize = Enum.AutomaticSize.XY
					paragraphHeader.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					paragraphHeader.BackgroundTransparency = 1
					paragraphHeader.BorderColor3 = Color3.fromRGB(0, 0, 0)
					paragraphHeader.BorderSizePixel = 0
					paragraphHeader.Size = UDim2.fromScale(1, 0)
					paragraphHeader.Parent = paragraph

					local uIListLayout9 = Instance.new("UIListLayout")
					uIListLayout9.Name = "UIListLayout"
					uIListLayout9.Padding = UDim.new(0, 15)
					uIListLayout9.HorizontalAlignment = Enum.HorizontalAlignment.Center
					uIListLayout9.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout9.Parent = paragraph

					local uIPadding4 = Instance.new("UIPadding")
					uIPadding4.Name = "UIPadding"
					uIPadding4.PaddingBottom = UDim.new(0, 15)
					uIPadding4.Parent = paragraph

					local line = Instance.new("Frame")
					line.Name = "Line"
					line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					line.BackgroundTransparency = 0.9
					line.BorderColor3 = Color3.fromRGB(0, 0, 0)
					line.BorderSizePixel = 0
					line.LayoutOrder = 1
					line.Size = UDim2.new(1, 0, 0, 1)
					line.Parent = paragraph]]

		local newParaBlock = [[local paragraph = Instance.new("Frame")
					paragraph.Name = "Paragraph"
					paragraph.AutomaticSize = Enum.AutomaticSize.None
					paragraph.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					paragraph.BackgroundTransparency = 1
					paragraph.BorderSizePixel = 0
					paragraph.Size = UDim2.new(1, 0, 0, 22)

					local paragraphHeader = Instance.new("TextLabel")
					paragraphHeader.Name = "ParagraphHeader"
					paragraphHeader.FontFace = Font.new(
						assets.interFont,
						Enum.FontWeight.SemiBold,
						Enum.FontStyle.Normal
					)
					paragraphHeader.RichText = true
					paragraphHeader.Text = ColorpickerFunctions.Settings.Name
					paragraphHeader.TextColor3 = Color3.fromRGB(245, 247, 250)
					paragraphHeader.TextSize = 13
					paragraphHeader.TextTransparency = 0
					paragraphHeader.TextTruncate = Enum.TextTruncate.AtEnd
					paragraphHeader.TextXAlignment = Enum.TextXAlignment.Left
					paragraphHeader.TextYAlignment = Enum.TextYAlignment.Center
					paragraphHeader.AnchorPoint = Vector2.new(0, 0.5)
					paragraphHeader.Position = UDim2.new(0, 0, 0.5, 0)
					paragraphHeader.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					paragraphHeader.BackgroundTransparency = 1
					paragraphHeader.BorderSizePixel = 0
					paragraphHeader.Size = UDim2.new(1, -26, 1, 0)
					paragraphHeader.Parent = paragraph

					local closeBtn = Instance.new("ImageButton")
					closeBtn.Name = "CloseBtn"
					closeBtn.Size = UDim2.fromOffset(16, 16)
					closeBtn.AnchorPoint = Vector2.new(1, 0.5)
					closeBtn.Position = UDim2.new(1, 0, 0.5, 0)
					closeBtn.BackgroundTransparency = 1
					closeBtn.Image = "rbxassetid://10747384394"
					closeBtn.ImageColor3 = Color3.fromRGB(160, 165, 180)
					closeBtn.Parent = paragraph

					closeBtn.MouseEnter:Connect(function()
						Tween(closeBtn, TweenInfo.new(0.15), { ImageColor3 = Color3.fromRGB(255, 255, 255) }):Play()
					end)
					closeBtn.MouseLeave:Connect(function()
						Tween(closeBtn, TweenInfo.new(0.15), { ImageColor3 = Color3.fromRGB(160, 165, 180) }):Play()
					end)]]

		local ps, pe = string.find(src, oldParaBlock, 1, true)
		if ps and pe then
			src = string.sub(src, 1, ps - 1) .. newParaBlock .. string.sub(src, pe + 1)
		end
	end

do
		local oldUFS = [=[					local function updateFromSettings()
						local r = math.floor(ColorpickerFunctions.Color.R * 255 + 0.5)
						local g = math.floor(ColorpickerFunctions.Color.G * 255 + 0.5)
						local b = math.floor(ColorpickerFunctions.Color.B * 255 + 0.5)
						modifierInputs.Red.Text = r
						modifierInputs.Green.Text = g
						modifierInputs.Blue.Text = b
						modifierInputs.Alpha.Text = isAlpha and ColorpickerFunctions.Alpha or 0

						local hexColor = string.format("#%02X%02X%02X", r,g,b)
						modifierInputs.Hex.Text = hexColor

						hue, saturation, value = Color3.fromRGB(r, g, b):ToHSV()

						color1.BackgroundColor3 = ColorpickerFunctions.Color
						color1.BackgroundTransparency = isAlpha and ColorpickerFunctions.Alpha or 0

						colour.BackgroundColor3 = Color3.fromRGB(r,g,b)
						colour.BackgroundTransparency = isAlpha and ColorpickerFunctions.Alpha or 0

						UpdateSlideFromValue(value)
						UpdateRingFromHSV(hue, saturation)
					end]=]
		local newUFS = [=[					local function updateFromSettings()
						local r = math.floor(ColorpickerFunctions.Color.R * 255 + 0.5)
						local g = math.floor(ColorpickerFunctions.Color.G * 255 + 0.5)
						local b = math.floor(ColorpickerFunctions.Color.B * 255 + 0.5)
						modifierInputs.Red.Text = r
						modifierInputs.Green.Text = g
						modifierInputs.Blue.Text = b
						modifierInputs.Alpha.Text = isAlpha and ColorpickerFunctions.Alpha or 0

						local hexColor = string.format("#%02X%02X%02X", r,g,b)
						modifierInputs.Hex.Text = hexColor
						if customHexBox and not customHexBox:IsFocused() then
							customHexBox.Text = string.format("%02X%02X%02X", r, g, b)
						end

						hue, saturation, value = Color3.fromRGB(r, g, b):ToHSV()

						local aVal = isAlpha and (ColorpickerFunctions.Alpha or 1) or 1
						modifierInputs.Alpha.Text = tostring(aVal)
						local transVal = isAlpha and (1 - aVal) or 0
						color1.BackgroundColor3 = ColorpickerFunctions.Color
						color1.BackgroundTransparency = transVal

						colour.BackgroundColor3 = Color3.fromRGB(r,g,b)
						colour.BackgroundTransparency = transVal

						-- Live sync row preview swatch (colorC)
						colorC.BackgroundColor3 = ColorpickerFunctions.Color
						colorC.BackgroundTransparency = transVal

						-- Sync opacity slider blend color & thumb position (Left = 0%, Right = 100%)
						if alphaSlider then
							local co = alphaSlider:FindFirstChild("ColorOverlay")
							if co then
								co.BackgroundColor3 = Color3.fromRGB(r, g, b)
							end
							if alphaSlide then
								local maxOffset = math.max(0, alphaSlider.AbsoluteSize.X - alphaSlide.AbsoluteSize.X)
								if maxOffset > 0 then
									alphaSlide.Position = UDim2.new(0, math.floor(aVal * maxOffset + 0.5), 0.5, 0)
								else
									alphaSlide.Position = UDim2.new(aVal, -math.floor(aVal * 10), 0.5, 0)
								end
							end
						end

						UpdateSlideFromValue(value)
						UpdateRingFromHSV(hue, saturation)
					end]=]
		local us, ue = string.find(src, oldUFS, 1, true)
		if us and ue then
			src = string.sub(src, 1, us - 1) .. newUFS .. string.sub(src, ue + 1)
		end
	end

	-- Ensure only 1 colorpicker modal can open at a time & add Backdrop Click Dismiss
	do
		local oldInFunc = [[local function colorpickerIn()
						transition(true)
					end

					local function colorpickerOut()
						transition(false)
					end]]

		local newInFunc = [[local function colorpickerOut(instant)
						if _G.__ShenkyActiveColorpickerOut == colorpickerOut then
							_G.__ShenkyActiveColorpickerOut = nil
						end
						if instant then
							pcall(function()
								colorPicker.Visible = false
								for _, ch in ipairs(base:GetChildren()) do
									if ch.Name == "ColorPickerCanvas" then
										ch.Visible = false
										ch:Destroy()
									end
								end
							end)
						else
							transition(false)
						end
					end

					local function colorpickerIn()
						if _G.__ShenkyActiveColorpickerOut and _G.__ShenkyActiveColorpickerOut ~= colorpickerOut then
							pcall(_G.__ShenkyActiveColorpickerOut, true)
						end
						_G.__ShenkyActiveColorpickerOut = colorpickerOut

						-- Always sync all visual states (hex, slider gradients, thumb positions) on open!
						updateFromSettings()

						transition(true)
					end]]

		local cs, ce = string.find(src, oldInFunc, 1, true)
		if cs and ce then
			src = string.sub(src, 1, cs - 1) .. newInFunc .. string.sub(src, ce + 1)
		end
	end

	-- Connect closeBtn & backdrop to colorpickerOut
	do
		local oldConnects = [[cancel.MouseButton1Click:Connect(colorpickerOut)]]
		local newConnects = [[cancel.MouseButton1Click:Connect(colorpickerOut)
					closeBtn.MouseButton1Click:Connect(colorpickerOut)

					-- Backdrop dismiss button (clicking anywhere outside the modal closes it)
					local backdropDismiss = Instance.new("TextButton")
					backdropDismiss.Name = "BackdropDismiss"
					backdropDismiss.BackgroundTransparency = 1
					backdropDismiss.BorderSizePixel = 0
					backdropDismiss.Size = UDim2.fromScale(1, 1)
					backdropDismiss.Text = ""
					backdropDismiss.ZIndex = 1
					backdropDismiss.Parent = colorPicker
					prompt.ZIndex = 2
					backdropDismiss.MouseButton1Click:Connect(colorpickerOut)]]

		local cs, ce = string.find(src, oldConnects, 1, true)
		if cs and ce then
			src = string.sub(src, 1, cs - 1) .. newConnects .. string.sub(src, ce + 1)
		end
	end

	src = string.gsub(src, "uIListLayout1%.Padding = UDim%.new%(0, 25%)", "uIListLayout1.Padding = UDim.new(0, 10)")

	-- Centered compact Wheel (148x148) & hide redundant inputs
	do
		local oldWheel = [[local wheel = Instance.new("Frame")
					wheel.Name = "Wheel"
					wheel.AutomaticSize = Enum.AutomaticSize.Y
					wheel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					wheel.BackgroundTransparency = 1
					wheel.BorderColor3 = Color3.fromRGB(0, 0, 0)
					wheel.BorderSizePixel = 0
					wheel.Size = UDim2.new(1, 0, 0, 100)]]

		local newWheel = [[local wheel = Instance.new("Frame")
					wheel.Name = "Wheel"
					wheel.AutomaticSize = Enum.AutomaticSize.None
					wheel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					wheel.BackgroundTransparency = 1
					wheel.BorderSizePixel = 0
					wheel.Size = UDim2.new(1, 0, 0, 148)]]

		local ws, we = string.find(src, oldWheel, 1, true)
		if ws and we then
			src = string.sub(src, 1, ws - 1) .. newWheel .. string.sub(src, we + 1)
		end
	end

	do
		local oldWheel1 = [[wheel1.Size = UDim2.fromOffset(220, 220)
					wheel1.SizeConstraint = Enum.SizeConstraint.RelativeYY]]

		local newWheel1 = [[wheel1.Size = UDim2.fromOffset(148, 148)
					wheel1.AnchorPoint = Vector2.new(0.5, 0.5)
					wheel1.Position = UDim2.fromScale(0.5, 0.5)
					wheel1.SizeConstraint = Enum.SizeConstraint.RelativeYY]]

		local ws, we = string.find(src, oldWheel1, 1, true)
		if ws and we then
			src = string.sub(src, 1, ws - 1) .. newWheel1 .. string.sub(src, we + 1)
		end
	end

	-- Hide redundant RGB/Alpha number boxes and set inputs invisible
	src = string.gsub(src, "inputs%.Parent = wheel", [[inputs.Visible = false
					inputs.Parent = wheel]])

	-- Value / Brightness Slider: compact 12px height with rounded pill track & thumb
	src = string.gsub(src, "value%.Size = UDim2%.new%(1, 0, 0, 15%)", "value.Size = UDim2.new(1, 0, 0, 12)")
	src = string.gsub(src, "slide%.Size = UDim2%.new%(0, 13, 1, 8%)", "slide.Size = UDim2.new(0, 10, 1, 4)")

	-- Dedicated Opacity / Alpha Slider when isAlpha is true
	do
		local oldSlideSetup = [[slide.Parent = value]]
		local newSlideSetup = [[slide.Parent = value

					local alphaSlider = nil
					local alphaSlide = nil
					if isAlpha then
						alphaSlider = Instance.new("TextButton")
						alphaSlider.Name = "AlphaSlider"
						alphaSlider.AutoButtonColor = false
						alphaSlider.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
						alphaSlider.BorderSizePixel = 0
						alphaSlider.ClipsDescendants = false
						alphaSlider.LayoutOrder = 2
						alphaSlider.Size = UDim2.new(1, 0, 0, 12)
						alphaSlider.Text = ""

						local aCorner = Instance.new("UICorner")
						aCorner.CornerRadius = UDim.new(1, 0)
						aCorner.Parent = alphaSlider

						local aStroke = Instance.new("UIStroke")
						aStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
						aStroke.Color = Color3.fromRGB(255, 255, 255)
						aStroke.Transparency = 0.9
						aStroke.Parent = alphaSlider

						-- Checkerboard transparency grid (showing through transparent areas)
						local gridBg = Instance.new("ImageLabel")
						gridBg.Name = "GridBg"
						gridBg.Size = UDim2.fromScale(1, 1)
						gridBg.Image = assets.grid
						gridBg.ScaleType = Enum.ScaleType.Tile
						gridBg.TileSize = UDim2.fromOffset(8, 8)
						gridBg.BackgroundTransparency = 1
						gridBg.BorderSizePixel = 0
						gridBg.ZIndex = 1
						gridBg.Parent = alphaSlider

						local gCorner = Instance.new("UICorner")
						gCorner.CornerRadius = UDim.new(1, 0)
						gCorner.Parent = gridBg

						-- Blend Color Overlay: Transparent checkerboard on Left (0%) fading to Solid Active Color on Right (100%)
						local colorOverlay = Instance.new("Frame")
						colorOverlay.Name = "ColorOverlay"
						colorOverlay.Size = UDim2.fromScale(1, 1)
						colorOverlay.BackgroundColor3 = ColorpickerFunctions.Color or Color3.fromRGB(160, 185, 255)
						colorOverlay.BorderSizePixel = 0
						colorOverlay.ZIndex = 2
						colorOverlay.Parent = alphaSlider

						local coCorner = Instance.new("UICorner")
						coCorner.CornerRadius = UDim.new(1, 0)
						coCorner.Parent = colorOverlay

						local coGrad = Instance.new("UIGradient")
						coGrad.Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 1), -- Left = 0% Opacity (Transparent -> shows checkerboard!)
							NumberSequenceKeypoint.new(1, 0), -- Right = 100% Opacity (Solid Active Color)
						})
						coGrad.Parent = colorOverlay

						alphaSlide = Instance.new("Frame")
						alphaSlide.Name = "Slide"
						alphaSlide.Active = false
						alphaSlide.AnchorPoint = Vector2.new(0, 0.5)
						alphaSlide.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						alphaSlide.BorderSizePixel = 0
						alphaSlide.ZIndex = 5
						local initAlpha = ColorpickerFunctions.Alpha or 1
						-- Direction: Left = 0% (Transparent), Right = 100% (Solid Active Color)
						alphaSlide.Position = UDim2.new(initAlpha, -math.floor(initAlpha * 10), 0.5, 0)
						alphaSlide.Size = UDim2.new(0, 10, 1, 4)

						local asCorner = Instance.new("UICorner")
						asCorner.CornerRadius = UDim.new(1, 0)
						asCorner.Parent = alphaSlide

						local asStroke = Instance.new("UIStroke")
						asStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
						asStroke.Transparency = 0.5
						asStroke.Parent = alphaSlide

						alphaSlide.Parent = alphaSlider
						alphaSlider.Parent = colorOptions
					end]]

		local ss, se = string.find(src, oldSlideSetup, 1, true)
		if ss and se then
			src = string.sub(src, 1, ss - 1) .. newSlideSetup .. string.sub(src, se + 1)
		end
	end

	-- Repurpose ColorWells into Sleek Bottom Bar (Hex Input + Live Color Swatch)
	do
		local oldWells = [[local colorWells = Instance.new("Frame")
					colorWells.Name = "ColorWells"
					colorWells.AutomaticSize = Enum.AutomaticSize.Y
					colorWells.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					colorWells.BackgroundTransparency = 1
					colorWells.BorderColor3 = Color3.fromRGB(0, 0, 0)
					colorWells.BorderSizePixel = 0
					colorWells.LayoutOrder = 2
					colorWells.Size = UDim2.fromScale(1, 0)

					local uIGridLayout = Instance.new("UIGridLayout")
					uIGridLayout.Name = "UIGridLayout"
					uIGridLayout.CellPadding = UDim2.fromOffset(10, 0)
					uIGridLayout.CellSize = UDim2.new(0.5, -5, 0, 30)
					uIGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
					uIGridLayout.Parent = colorWells

					local newColor = Instance.new("ImageLabel")
					newColor.Name = "NewColor"
					newColor.Image = assets.grid
					newColor.ScaleType = Enum.ScaleType.Tile
					newColor.TileSize = UDim2.fromOffset(500, 500)
					newColor.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					newColor.BackgroundTransparency = 1
					newColor.BorderColor3 = Color3.fromRGB(0, 0, 0)
					newColor.BorderSizePixel = 0
					newColor.Size = UDim2.fromOffset(100, 100)]]

		local newWells = [[local colorWells = Instance.new("Frame")
					colorWells.Name = "ColorWells"
					colorWells.AutomaticSize = Enum.AutomaticSize.None
					colorWells.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					colorWells.BackgroundTransparency = 1
					colorWells.BorderSizePixel = 0
					colorWells.LayoutOrder = 10
					colorWells.Size = UDim2.new(1, 0, 0, 28)

					-- Hex input container on the left
					local hexContainer = Instance.new("Frame")
					hexContainer.Name = "HexContainer"
					hexContainer.Size = UDim2.new(1, -56, 1, 0)
					hexContainer.Position = UDim2.new(0, 0, 0.5, 0)
					hexContainer.AnchorPoint = Vector2.new(0, 0.5)
					hexContainer.BackgroundColor3 = Color3.fromRGB(20, 23, 30)
					hexContainer.BorderSizePixel = 0
					hexContainer.Parent = colorWells

					local hCorner = Instance.new("UICorner")
					hCorner.CornerRadius = UDim.new(0, 6)
					hCorner.Parent = hexContainer

					local hStroke = Instance.new("UIStroke")
					hStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					hStroke.Color = Color3.fromRGB(255, 255, 255)
					hStroke.Transparency = 0.88
					hStroke.Parent = hexContainer

					local hashPrefix = Instance.new("TextLabel")
					hashPrefix.Name = "Hash"
					hashPrefix.BackgroundTransparency = 1
					hashPrefix.Size = UDim2.fromOffset(16, 28)
					hashPrefix.Position = UDim2.new(0, 6, 0, 0)
					hashPrefix.FontFace = Font.new(assets.interFont, Enum.FontWeight.Medium, Enum.FontStyle.Normal)
					hashPrefix.Text = "#"
					hashPrefix.TextColor3 = Color3.fromRGB(120, 130, 150)
					hashPrefix.TextSize = 12
					hashPrefix.Parent = hexContainer

					local customHexBox = Instance.new("TextBox")
					customHexBox.Name = "HexInputBox"
					customHexBox.BackgroundTransparency = 1
					customHexBox.ClearTextOnFocus = false
					customHexBox.FontFace = Font.new(assets.interFont, Enum.FontWeight.Medium, Enum.FontStyle.Normal)
					customHexBox.Size = UDim2.new(1, -24, 1, 0)
					customHexBox.Position = UDim2.new(0, 20, 0, 0)
					local cInit = ColorpickerFunctions.Color or Color3.fromRGB(255, 255, 255)
					customHexBox.Text = string.format("%02X%02X%02X",
						math.floor(cInit.R * 255 + 0.5),
						math.floor(cInit.G * 255 + 0.5),
						math.floor(cInit.B * 255 + 0.5)
					)
					customHexBox.TextColor3 = Color3.fromRGB(240, 245, 255)
					customHexBox.TextSize = 12
					customHexBox.TextXAlignment = Enum.TextXAlignment.Left
					customHexBox.Parent = hexContainer

					-- Live Preview Swatch Pill on the right
					local newColor = Instance.new("ImageLabel")
					newColor.Name = "NewColor"
					newColor.Image = assets.grid
					newColor.ScaleType = Enum.ScaleType.Tile
					newColor.TileSize = UDim2.fromOffset(500, 500)
					newColor.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					newColor.BackgroundTransparency = 1
					newColor.BorderSizePixel = 0
					newColor.AnchorPoint = Vector2.new(1, 0.5)
					newColor.Position = UDim2.new(1, 0, 0.5, 0)
					newColor.Size = UDim2.fromOffset(48, 28)]]

		local ws, we = string.find(src, oldWells, 1, true)
		if ws and we then
			src = string.sub(src, 1, ws - 1) .. newWells .. string.sub(src, we + 1)
		end
	end

	-- Swatch corners and border stroke
	src = string.gsub(src, "uICorner2%.CornerRadius = UDim%.new%(0, 6%)", [[uICorner2.CornerRadius = UDim.new(0, 6)
					local sStroke = Instance.new("UIStroke")
					sStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					sStroke.Color = Color3.fromRGB(255, 255, 255)
					sStroke.Transparency = 0.8
					sStroke.Parent = newColor]])

	-- Hide OldColor well completely
	src = string.gsub(src, "oldColor%.Parent = colorWells", [[oldColor.Visible = false
					oldColor.Parent = colorWells]])

	-- Real-time auto apply in update() & live sync with bottom bar hex & swatch
	do
		local oldUpdate = [[local function update()
						local c = fromHSV(hue, saturation, value)
						colour.BackgroundColor3 = c
						colour.BackgroundTransparency = clampInput(modifierInputs.Alpha.Text, 0, 1)

						modifierInputs.Red.Text = tostring(math.floor(c.r * 255 + 0.5))
						modifierInputs.Green.Text = tostring(math.floor(c.g * 255 + 0.5))
						modifierInputs.Blue.Text = tostring(math.floor(c.b * 255 + 0.5))
						modifierInputs.Alpha.Text = clampInput(modifierInputs.Alpha.Text, 0, 1)

						local hexColor = string.format("#%02X%02X%02X", 
							math.floor(c.r * 255 + 0.5),
							math.floor(c.g * 255 + 0.5),
							math.floor(c.b * 255 + 0.5))
						modifierInputs.Hex.Text = hexColor
					end]]

		local newUpdate = [[local function update()
						local c = fromHSV(hue, saturation, value)
						colour.BackgroundColor3 = c
						local aVal = isAlpha and clampInput(modifierInputs.Alpha.Text, 0, 1) or 1
						local transVal = isAlpha and (1 - aVal) or 0
						colour.BackgroundTransparency = transVal

						modifierInputs.Red.Text = tostring(math.floor(c.r * 255 + 0.5))
						modifierInputs.Green.Text = tostring(math.floor(c.g * 255 + 0.5))
						modifierInputs.Blue.Text = tostring(math.floor(c.b * 255 + 0.5))
						modifierInputs.Alpha.Text = tostring(aVal)

						local rawHex = string.format("%02X%02X%02X", 
							math.floor(c.r * 255 + 0.5),
							math.floor(c.g * 255 + 0.5),
							math.floor(c.b * 255 + 0.5))
						modifierInputs.Hex.Text = "#" .. rawHex
						if customHexBox and not customHexBox:IsFocused() then
							customHexBox.Text = rawHex
						end

						-- Real-time auto-apply to row swatch & callback!
						ColorpickerFunctions.Color = Color3.fromRGB(c.r * 255, c.g * 255, c.b * 255)
						ColorpickerFunctions.Alpha = isAlpha and aVal or nil
						colorC.BackgroundColor3 = ColorpickerFunctions.Color
						colorC.BackgroundTransparency = transVal

						-- Sync opacity slider blend color with active color
						if alphaSlider then
							local co = alphaSlider:FindFirstChild("ColorOverlay")
							if co then
								co.BackgroundColor3 = ColorpickerFunctions.Color
							end
						end

						if ColorpickerFunctions.Settings.Callback then
							task.spawn(function()
								ColorpickerFunctions.Settings.Callback(ColorpickerFunctions.Color, isAlpha and ColorpickerFunctions.Alpha)
							end)
						end
					end]]

		local us, ue = string.find(src, oldUpdate, 1, true)
		if us and ue then
			src = string.sub(src, 1, us - 1) .. newUpdate .. string.sub(src, ue + 1)
		end
	end

	-- Hook customHexBox FocusLost to updateFromHex and Opacity Slider dragging
	do
		local oldHook = [[modifierInputs.Hex.FocusLost:Connect(updateFromHex)]]
		local newHook = [[modifierInputs.Hex.FocusLost:Connect(updateFromHex)

					customHexBox.FocusLost:Connect(function()
						local cleaned = customHexBox.Text:gsub("#", "")
						if #cleaned == 6 then
							modifierInputs.Hex.Text = "#" .. cleaned
							updateFromHex()
						end
					end)

					if alphaSlider and alphaSlide then
						local alphaDragging = false
						local function updateAlphaFromX(iX)
							local maxOffset = math.max(1, alphaSlider.AbsoluteSize.X - alphaSlide.AbsoluteSize.X)
							local rX = iX - alphaSlider.AbsolutePosition.X - (alphaSlide.AbsoluteSize.X / 2)
							local cX = math.clamp(rX, 0, maxOffset)
							alphaSlide.Position = UDim2.new(0, cX, 0.5, 0)
							-- Direction: Left = 0% (0.0 Transparent), Right = 100% (1.0 Solid Active Color)
							local alphaFraction = math.clamp(cX / maxOffset, 0, 1)
							modifierInputs.Alpha.Text = tostring(math.floor(alphaFraction * 100 + 0.5) / 100)
							update()
						end

						alphaSlider.InputBegan:Connect(function(input)
							if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
								alphaDragging = true
								updateAlphaFromX(input.Position.X)
							end
						end)
						alphaSlider.InputEnded:Connect(function(input)
							if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
								alphaDragging = false
							end
						end)
						UserInputService.InputChanged:Connect(function(input)
							if alphaDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
								updateAlphaFromX(input.Position.X)
							end
						end)
					end]]

		local hs, he = string.find(src, oldHook, 1, true)
		if hs and he then
			src = string.sub(src, 1, hs - 1) .. newHook .. string.sub(src, he + 1)
		end
	end

	-- Hide Interactions (Confirm / Cancel)
	src = string.gsub(src, "interactions%.Parent = prompt", [[interactions.Visible = false
					interactions.Parent = prompt]])

src = string.gsub(src, "toggle%.Size = UDim2%.new%(1, 0, 0, 38%)", "toggle.Size = UDim2.new(1, 0, 0, 26)")
	src = string.gsub(src, "toggleName%.TextSize = 13", "toggleName.TextSize = 12")
	src = string.gsub(src, "toggle1%.Size = UDim2%.fromOffset%(41, 21%)", "toggle1.Size = UDim2.fromOffset(32, 16)")
	src = string.gsub(src, "togglerHead%.Size = UDim2%.fromOffset%(15, 15%)", "togglerHead.Size = UDim2.fromOffset(12, 12)")

	-- Slider 2-Row Stacked: Row 1 = Name (lebar bebas tanpa terpotong), Row 2 = Bar (panjang MAKSIMAL) + Nilai



	src = string.gsub(src, "slider%.Size = UDim2%.new%(1, 0, 0, 38%)", "slider.Size = UDim2.new(1, 0, 0, 42)")



	src = string.gsub(src, "sliderName%.TextSize = 13", "sliderName.TextSize = 12")



	src = string.gsub(



		src,



		"sliderName%.Position = UDim2%.fromScale%(1%.3e%-07, 0%.5%)",



		[[sliderName.AnchorPoint = Vector2.new(0, 0)



					sliderName.Position = UDim2.new(0, 0, 0, 2)



					sliderName.Size = UDim2.new(1, 0, 0, 16)



					sliderName.AutomaticSize = Enum.AutomaticSize.None



					sliderName.TextTruncate = Enum.TextTruncate.None



					sliderName.TextColor3 = Color3.fromRGB(240, 245, 255)



					sliderName.TextTransparency = 0.35]]



	)



	src = string.gsub(src, "sliderElements%.AnchorPoint = Vector2%.new%(1, 0%)", "sliderElements.AnchorPoint = Vector2.new(0, 0)")



	src = string.gsub(src, "sliderElements%.Position = UDim2%.fromScale%(1, 0%)", "sliderElements.Position = UDim2.new(0, 0, 0, 20)")



	src = string.gsub(src, "sliderElements%.Size = UDim2%.fromScale%(1, 1%)", "sliderElements.Size = UDim2.new(1, 0, 0, 20)")



	src = string.gsub(src, "sliderValue%.LayoutOrder = 1", "sliderValue.LayoutOrder = 2")



	src = string.gsub(src, "sliderValue%.TextSize = 12", "sliderValue.TextSize = 11")



	src = string.gsub(src, "sliderValue%.Size = UDim2%.fromOffset%(41, 21%)", "sliderValue.Size = UDim2.fromOffset(36, 18)")



	src = string.gsub(src, "sliderHead%.Size = UDim2%.fromOffset%(12, 12%)", "sliderHead.Size = UDim2.fromOffset(12, 12)")



	src = string.gsub(



		src,



		"sliderBar%.Size = UDim2%.fromOffset%(123, 3%)",



		[[sliderBar.LayoutOrder = 1



					sliderBar.Active = true



					sliderBar.Size = UDim2.fromOffset(123, 4)]]



	)



	src = string.gsub(



		src,



		"sliderHead%.InputBegan:Connect%(function%(input%)",



		[[sliderBar.InputBegan:Connect(function(input)



						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then



							dragging = true



							SetValue(input)



						end



					end)



					sliderHead.InputBegan:Connect(function(input)]]



	)











	src = string.gsub(src, "input%.Size = UDim2%.new%(1, 0, 0, 38%)", "input.Size = UDim2.new(1, 0, 0, 26)")



	src = string.gsub(src, "inputName%.TextSize = 13", "inputName.TextSize = 12")



	src = string.gsub(src, "inputBox%.TextSize = 12", "inputBox.TextSize = 11")



	src = string.gsub(src, "inputBox%.Size = UDim2%.fromOffset%(21, 21%)", "inputBox.Size = UDim2.fromOffset(21, 18)")











	src = string.gsub(src, "keybind%.Size = UDim2%.new%(1, 0, 0, 38%)", "keybind.Size = UDim2.new(1, 0, 0, 26)")



	src = string.gsub(src, "keybindName%.TextSize = 13", "keybindName.TextSize = 12")



	src = string.gsub(src, "binderBox%.TextSize = 12", "binderBox.TextSize = 11")



	src = string.gsub(src, "binderBox%.Size = UDim2%.fromOffset%(21, 21%)", "binderBox.Size = UDim2.fromOffset(21, 18)")











	src = string.gsub(src, "dropdown%.Size = UDim2%.new%(1, 0, 0, 38%)", "dropdown.Size = UDim2.new(1, 0, 0, 28)")

	src = string.gsub(
		src,
		"dropdownUIPadding%.PaddingLeft = UDim%.new%(0, 15%)\r?\n\t*dropdownUIPadding%.PaddingRight = UDim%.new%(0, 15%)",
		[[dropdownUIPadding.PaddingLeft = UDim.new(0, 0)
					dropdownUIPadding.PaddingRight = UDim.new(0, 0)]]
	)



	src = string.gsub(src, "interact%.Size = UDim2%.new%(1, 0, 0, 38%)", "interact.Size = UDim2.new(1, 0, 0, 28)")



	src = string.gsub(src, "dropdownName%.Size = UDim2%.new%(1, %-20, 0, 38%)", "dropdownName.AnchorPoint = Vector2.new(0, 0.5)\n\tdropdownName.Position = UDim2.new(0, 12, 0, 14)\n\tdropdownName.Size = UDim2.new(1, -40, 0, 28)")



	src = string.gsub(src, "dropdownName%.TextSize = 13", "dropdownName.TextSize = 12")



	src = string.gsub(src, "dropdownName%.TextTruncate = Enum%.TextTruncate%.SplitWord", "dropdownName.TextTruncate = Enum.TextTruncate.AtEnd")



	src = string.gsub(src, "dropdownName%.TextTransparency = 0%.5", "dropdownName.TextTransparency = 0.25")



	src = string.gsub(src, "subLabelText%.TextTransparency = 0%.7", "subLabelText.TextTransparency = 0.35")



	src = string.gsub(



		src,



		"subLabel%.Parent = section",



		"subLabel.Parent = section\n\t\t\t\t\tlocal subLabelPadding = Instance.new(\"UIPadding\")\n\t\t\t\t\tsubLabelPadding.PaddingLeft = UDim.new(0, 2)\n\t\t\t\t\tsubLabelPadding.PaddingTop = UDim.new(0, 3)\n\t\t\t\t\tsubLabelPadding.Parent = subLabel"



	)



	do
		local oldDropImg = [[local dropdownImage = Instance.new("ImageLabel")
					dropdownImage.Name = "DropdownImage"
					dropdownImage.Image = assets.dropdown
					dropdownImage.ImageTransparency = 0.5
					dropdownImage.AnchorPoint = Vector2.new(1, 0)
					dropdownImage.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					dropdownImage.BackgroundTransparency = 1
					dropdownImage.BorderColor3 = Color3.fromRGB(0, 0, 0)
					dropdownImage.BorderSizePixel = 0
					dropdownImage.Position = UDim2.new(1, 0, 0, 12)
					dropdownImage.Size = UDim2.fromOffset(14, 14)
					dropdownImage.Parent = dropdown]]

		local newDropImg = [[local dropdownImage = Instance.new("ImageLabel")
					dropdownImage.Name = "DropdownImage"
					dropdownImage.Image = "rbxassetid://10709797508"
					dropdownImage.Size = UDim2.fromOffset(14, 14)
					dropdownImage.AnchorPoint = Vector2.new(1, 0)
					dropdownImage.Position = UDim2.new(1, 0, 0, 12)
					dropdownImage.ImageColor3 = Color3.fromRGB(240, 245, 255)
					dropdownImage.ImageTransparency = 0.5
					dropdownImage.BackgroundTransparency = 1
					dropdownImage.BorderSizePixel = 0
					dropdownImage.Parent = dropdown]]

		local s, e = string.find(src, oldDropImg, 1, true)
		if s and e then
			src = string.sub(src, 1, s - 1) .. newDropImg .. string.sub(src, e + 1)
		end
	end

	do
		local oldTweenCode = [[local iconTween = Tween(dropdownImage, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Rotation = isDropdownOpen and -90 or 0
						})]]

		local newTweenCode = [[local strokeTween = dropdown:FindFirstChild("DropdownUIStroke") and Tween(dropdown.DropdownUIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
							Transparency = isDropdownOpen and 0.82 or 0.95,
							Color = isDropdownOpen and Color3.fromRGB(160, 190, 255) or Color3.fromRGB(255, 255, 255)
						})
						if strokeTween then strokeTween:Play() end

						local iconTween = Tween(dropdownImage, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Rotation = isDropdownOpen and 180 or 0,
							ImageTransparency = isDropdownOpen and 0.2 or 0.5,
							ImageColor3 = isDropdownOpen and Color3.fromRGB(160, 190, 255) or Color3.fromRGB(240, 245, 255),
						})
						iconTween:Play()]]

		local s, e = string.find(src, oldTweenCode, 1, true)
		if s and e then
			src = string.sub(src, 1, s - 1) .. newTweenCode .. string.sub(src, e + 1)
		end
	end

	do
		-- Redesign Dropdown Option with Shenky Hub luxury aesthetics:
		-- 1. Left-aligned option text with clean spacing
		-- 2. Far-right checkmark image (Lucide check)
		-- 3. Soft frosted translucent pill highlight (BackgroundTransparency 0.93)
		-- 4. No UIListLayout inside option so elements are anchored rock-solid
		local startPat = 'local option = Instance.new("TextButton")\n\t\t\t\t\t\toption.Name = "Option"'
		local endPat = 'checkmark.Parent = option'

		local newOptionBlock = [[local isInitialSelected = false
						if type(DropdownFunctions.Settings.Default) == "table" then
							isInitialSelected = table.find(DropdownFunctions.Settings.Default, v) ~= nil
						elseif DropdownFunctions.Settings.Default == v then
							isInitialSelected = true
						end

						local option = Instance.new("TextButton")
						option.Name = "Option"
						option.Text = ""
						option.AutoButtonColor = false
						option.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						option.BackgroundTransparency = isInitialSelected and 0.93 or 1
						option.BorderSizePixel = 0
						option.Size = UDim2.new(1, 0, 0, 24)

						local optionCorner = Instance.new("UICorner")
						optionCorner.Name = "OptionCorner"
						optionCorner.CornerRadius = UDim.new(0, 5)
						optionCorner.Parent = option

						local optionName = Instance.new("TextLabel")
						optionName.Name = "OptionName"
						optionName.FontFace = Font.new(assets.interFont)
						optionName.Text = v
						optionName.RichText = true
						optionName.TextColor3 = isInitialSelected and Color3.fromRGB(160, 185, 255) or Color3.fromRGB(220, 225, 235)
						optionName.TextSize = 12
						optionName.TextTransparency = isInitialSelected and 0 or 0.35
						optionName.TextTruncate = Enum.TextTruncate.AtEnd
						optionName.TextXAlignment = Enum.TextXAlignment.Left
						optionName.TextYAlignment = Enum.TextYAlignment.Center
						optionName.AnchorPoint = Vector2.new(0, 0.5)
						optionName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						optionName.BackgroundTransparency = 1
						optionName.BorderSizePixel = 0
						optionName.Position = UDim2.new(0, 8, 0.5, 0)
						optionName.Size = UDim2.new(1, -32, 1, 0)
						optionName.Parent = option

						local checkmark = Instance.new("TextLabel")
						checkmark.Name = "Checkmark"
						checkmark.Text = ""
						checkmark.AnchorPoint = Vector2.new(1, 0.5)
						checkmark.Position = UDim2.new(1, -8, 0.5, 0)
						checkmark.Size = UDim2.fromOffset(13, 13)
						checkmark.BackgroundTransparency = 1
						checkmark.BorderSizePixel = 0
						checkmark.TextTransparency = isInitialSelected and 0 or 1
						checkmark.Parent = option

						local lucideCheck = Instance.new("ImageLabel")
						lucideCheck.Name = "LucideCheck"
						lucideCheck.Image = "rbxassetid://10709790644"
						lucideCheck.AnchorPoint = Vector2.new(0.5, 0.5)
						lucideCheck.Position = UDim2.fromScale(0.5, 0.5)
						lucideCheck.Size = UDim2.fromOffset(13, 13)
						lucideCheck.BackgroundTransparency = 1
						lucideCheck.BorderSizePixel = 0
						lucideCheck.ImageColor3 = Color3.fromRGB(160, 185, 255)
						lucideCheck.ImageTransparency = isInitialSelected and 0 or 1
						lucideCheck.Parent = checkmark

						checkmark:GetPropertyChangedSignal("TextTransparency"):Connect(function()
							lucideCheck.ImageTransparency = checkmark.TextTransparency
						end)

						local optionUIListLayout = { Padding = UDim.new(0, 0) }

						option.MouseEnter:Connect(function()
							if not table.find(Selected, v) then
								Tween(option, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.96 }):Play()
								Tween(optionName, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { TextTransparency = 0.15 }):Play()
							end
						end)
						option.MouseLeave:Connect(function()
							if not table.find(Selected, v) then
								Tween(option, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
								Tween(optionName, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { TextTransparency = 0.35 }):Play()
							end
						end)]]

		local s1 = string.find(src, startPat, 1, true)
		local _, e1 = string.find(src, endPat, s1 or 1, true)
		if s1 and e1 then
			src = string.sub(src, 1, s1 - 1) .. newOptionBlock .. string.sub(src, e1 + 1)
		end
	end

	do
		-- Upgrade Toggle function to animate Option Button active pill highlight and far-right checkmark
		local oldToggleLoop = [[for name, opt in pairs(OptionObjs) do
									if name ~= optionName then
										Tween(opt.Checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
											Size = UDim2.new(opt.Checkmark.Size.X.Scale, tweensettings.checkSizeDecrease, opt.Checkmark.Size.Y.Scale, opt.Checkmark.Size.Y.Offset)
										}):Play()
										Tween(opt.NameLabel, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
											TextTransparency = tweensettings.transparencyOut
										}):Play()
										opt.Checkmark.TextTransparency = 1
									end
								end]]

		local newToggleLoop = [[for name, opt in pairs(OptionObjs) do
									if name ~= optionName then
										Tween(opt.Button, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), { BackgroundTransparency = 1, BackgroundColor3 = Color3.fromRGB(255, 255, 255) }):Play()
										Tween(opt.Checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), { TextTransparency = 1 }):Play()
										Tween(opt.NameLabel, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), { TextTransparency = 0.35, TextColor3 = Color3.fromRGB(220, 225, 235) }):Play()
									end
								end]]

		local s, e = string.find(src, oldToggleLoop, 1, true)
		if s and e then
			src = string.sub(src, 1, s - 1) .. newToggleLoop .. string.sub(src, e + 1)
		end
	end

	do
		local oldActiveTween = [[Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
								Size = UDim2.new(checkmark.Size.X.Scale, tweensettings.checkSizeIncrease, checkmark.Size.Y.Scale, checkmark.Size.Y.Offset)
							}):Play()
							Tween(optionNameLabel, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
								TextTransparency = tweensettings.transparencyIn
							}):Play()
							checkmark.TextTransparency = 0]]

		local newActiveTween = [[Tween(option.Button, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), { BackgroundTransparency = 0.93, BackgroundColor3 = Color3.fromRGB(255, 255, 255) }):Play()
							Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), { TextTransparency = 0 }):Play()
							Tween(optionNameLabel, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), { TextTransparency = 0, TextColor3 = Color3.fromRGB(160, 185, 255) }):Play()]]

		local s, e = string.find(src, oldActiveTween, 1, true)
		if s and e then
			src = string.sub(src, 1, s - 1) .. newActiveTween .. string.sub(src, e + 1)
		end
	end

	do
		local oldDeactTween = [[Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
								Size = UDim2.new(checkmark.Size.X.Scale, tweensettings.checkSizeDecrease, checkmark.Size.Y.Scale, checkmark.Size.Y.Offset)
							}):Play()
							Tween(optionNameLabel, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
								TextTransparency = tweensettings.transparencyOut
							}):Play()
							checkmark.TextTransparency = 1]]

		local newDeactTween = [[Tween(option.Button, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), { BackgroundTransparency = 1, BackgroundColor3 = Color3.fromRGB(255, 255, 255) }):Play()
							Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), { TextTransparency = 1 }):Play()
							Tween(optionNameLabel, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), { TextTransparency = 0.35, TextColor3 = Color3.fromRGB(220, 225, 235) }):Play()]]

		local s, e = string.find(src, oldDeactTween, 1, true)
		if s and e then
			src = string.sub(src, 1, s - 1) .. newDeactTween .. string.sub(src, e + 1)
		end
	end

	src = string.gsub(
		src,
		"dropdownFrameUIListLayout%.Padding = UDim%.new%(0, 5%)",
		"dropdownFrameUIListLayout.Padding = UDim.new(0, 2)"
	)

	src = string.gsub(
		src,
		"dropdownFrameUIPadding%.PaddingTop = UDim%.new%(0, 38%)",
		[[dropdownFrameUIPadding.PaddingTop = UDim.new(0, 32)
					dropdownFrameUIPadding.PaddingLeft = UDim.new(0, 4)
					dropdownFrameUIPadding.PaddingRight = UDim.new(0, 4)
					dropdownFrameUIPadding.PaddingBottom = UDim.new(0, 6)]]
	)



	src = string.gsub(src, "local defaultDropdownSize = 38", "local defaultDropdownSize = 28")



	src = string.gsub(src, "search%.Size = UDim2%.new%(1, 0, 0, 30%)", "search.ZIndex = 2\n\tsearch.Size = UDim2.new(1, 0, 0, 24)")



	src = string.gsub(src, "searchBox%.TextSize = 14", "searchBox.TextSize = 12")



	src = string.gsub(src, "option%.Size = UDim2%.new%(1, 0, 0, 30%)", "option.Size = UDim2.new(1, 0, 0, 24)")



	src = string.gsub(src, "optionName%.TextSize = 13", "optionName.TextSize = 12")



	src = string.gsub(src, "label%.Size = UDim2%.new%(1, 0, 0, 38%)", "label.Size = UDim2.new(1, 0, 0, 24)")



	src = string.gsub(src, "labelText%.TextSize = 13", "labelText.TextSize = 12")











	-- 4. Rapatkan jarak antara SliderBar dan kotak angka (20px -> 8px)



	src = string.gsub(



		src,



		"sliderElementsUIListLayout%.Padding = UDim%.new%(0, 20%)",



		"sliderElementsUIListLayout.Padding = UDim.new(0, 8)"



	)











	-- 5. Perhitungan lebar SliderBar 2-Row: Bar melebar MAKSIMAL mengisi sisa baris di samping kotak [25]



	src = string.gsub(



		src,



		"local newBarWidth = %(totalWidth %- %(padding %+ sliderValueWidth %+ sliderNameWidth %+ 20%)%) / baseUIScale%.Scale",



		[[local scale = (baseUIScale and baseUIScale.Scale > 0) and baseUIScale.Scale or 1



						local totalW = sliderElements.AbsoluteSize.X / scale



						local valW = sliderValue.AbsoluteSize.X / scale



						local pad = sliderElementsUIListLayout.Padding.Offset



						local newBarWidth = math.max(60, math.floor(totalW - valW - pad - 2))



						sliderBar.Size = UDim2.new(0, newBarWidth, 0, 4)]]



	)











	src = string.gsub(



		src,



		"section:GetPropertyChangedSignal%(\"AbsoluteSize\"%):Connect%(updateSliderBarSize%)",



		"section:GetPropertyChangedSignal(\"AbsoluteSize\"):Connect(updateSliderBarSize)\n\t\t\t\t\tsliderElements:GetPropertyChangedSignal(\"AbsoluteSize\"):Connect(updateSliderBarSize)\n\t\t\t\t\tbaseUIScale:GetPropertyChangedSignal(\"Scale\"):Connect(updateSliderBarSize)\n\t\t\t\t\ttask.defer(updateSliderBarSize)"



	)











	-- 6. Perbaiki tinggi buka/tutup Dropdown & batas lebar InputBox saat UIScale diubah



	src = string.gsub(



		src,



		"totalHeight %+= v%.AbsoluteSize%.Y",



		"totalHeight += (v.AbsoluteSize.Y / ((baseUIScale and baseUIScale.Scale > 0) and baseUIScale.Scale or 1))"



	)











	src = string.gsub(



		src,



		"dropdown%.Size = UDim2%.new%(1, 0, 0, CalculateDropdownSize%(%)%)\r?\n\t*end\r?\n\r?\n\t*searchBox:GetPropertyChangedSignal",



		"if dropped then dropdown.Size = UDim2.new(1, 0, 0, CalculateDropdownSize()) end\n\t\t\t\t\tend\n\n\t\t\t\t\tsearchBox:GetPropertyChangedSignal"



	)











	src = string.gsub(



		src,



		"local maxWidth = %(totalWidth %- nameWidth %- 20%) / baseUIScale%.Scale",



		"local scale = (baseUIScale and baseUIScale.Scale > 0) and baseUIScale.Scale or 1\n\t\t\t\t\t\tlocal maxWidth = (totalWidth / scale) - (nameWidth / scale) - 16"



	)











	-- 7. Perbaiki bug bawaan Maclib pada InsertConfigSection(Side) & sistem Configuration/Autoload



	src = string.gsub(



		src,



		"local configSection = TabFunctions:Section%({ Side = \"Left\" }%)",



		"local configSection = TabFunctions:Section({ Side = Side or \"Left\" })\n\t\t\t\tconfigSection:Header({ Text = \"Configuration\" })"



	)











	local function patch(pattern, replacement)



		src = string.gsub(src, pattern, function()



			return replacement



		end)



	end











	-- Censor User Info (DisplayName & Username) in Sidebar for privacy



	patch(



		"displayName%.Text = LocalPlayer%.DisplayName",



		[[displayName.Text = (function(s)



			s = tostring(s or "")



			local len = #s



			if len <= 1 then return "*"



			elseif len == 2 then return string.sub(s, 1, 1) .. "*"



			else return string.sub(s, 1, 2) .. string.rep("*", len - 2) end



		end)(LocalPlayer.DisplayName)]]



	)



	patch(



		"username%.Text = \"@\" %.%. LocalPlayer%.Name",



		[[username.Text = "@" .. (function(s)



			s = tostring(s or "")



			local len = #s



			if len <= 1 then return "*"



			elseif len == 2 then return string.sub(s, 1, 1) .. "*"



			else return string.sub(s, 1, 2) .. string.rep("*", len - 2) end



		end)(LocalPlayer.Name)]]



	)











	-- Fix ColorPicker ColorWheel asset (ganti asset 2849458409 yang dihapus/404 oleh Roblox dengan asset aktif 6020299385)



	patch(



		'colorWheel = "rbxassetid://2849458409"',



		'colorWheel = "rbxassetid://6020299385"'



	)











	-- Fix Toggle Load ketika state == false



	patch(



		"if MacLib%.Options%[Flag%] and data%.state then",



		"if MacLib.Options[Flag] and data.state ~= nil then"



	)











	-- Fix Slider rounding, text field live update & FocusLost parsing, serta UpdateValue saat LoadConfig



	patch(



		"finalValue = posXScale %* %(SliderFunctions%.Settings%.Maximum %- SliderFunctions%.Settings%.Minimum%) %+ Settings%.Minimum",



		"local rawVal = posXScale * (SliderFunctions.Settings.Maximum - SliderFunctions.Settings.Minimum) + Settings.Minimum\n\t\t\t\t\t\tlocal prec = tonumber(SliderFunctions.Settings.Precision) or 0\n\t\t\t\t\t\tlocal mult = 10 ^ prec\n\t\t\t\t\t\tfinalValue = math.clamp(math.floor(rawVal * mult + 0.5) / mult, SliderFunctions.Settings.Minimum, SliderFunctions.Settings.Maximum)"



	)



	patch(



		"sliderValue%.FocusLost:Connect%(function%(enterPressed%).-if SliderFunctions%.Settings%.onInputComplete then\r?\n\t*SliderFunctions%.Settings%.onInputComplete%(finalValue%)\r?\n\t*end\r?\n\t*end%)",



		"sliderValue:GetPropertyChangedSignal(\"Text\"):Connect(function()\n\t\t\t\t\t\tif not sliderValue:IsFocused() then return end\n\t\t\t\t\t\tlocal numStr = tostring(sliderValue.Text or \"\"):match(\"%-?%d+%.?%d*\")\n\t\t\t\t\t\tlocal val = numStr and tonumber(numStr)\n\t\t\t\t\t\tif val then\n\t\t\t\t\t\t\tlocal prec = tonumber(SliderFunctions.Settings.Precision) or 0\n\t\t\t\t\t\t\tlocal mult = 10 ^ prec\n\t\t\t\t\t\t\tval = math.clamp(math.floor(val * mult + 0.5) / mult, SliderFunctions.Settings.Minimum, SliderFunctions.Settings.Maximum)\n\t\t\t\t\t\t\tfinalValue = val\n\t\t\t\t\t\t\tSliderFunctions.Value = val\n\t\t\t\t\t\t\tlocal posXScale = (val - SliderFunctions.Settings.Minimum) / math.max(1e-6, SliderFunctions.Settings.Maximum - SliderFunctions.Settings.Minimum)\n\t\t\t\t\t\t\tsliderHead.Position = UDim2.new(math.clamp(posXScale, 0, 1), 0, 0.5, 0)\n\t\t\t\t\t\t\tif SliderFunctions.Settings.Callback then\n\t\t\t\t\t\t\t\ttask.spawn(SliderFunctions.Settings.Callback, val)\n\t\t\t\t\t\t\tend\n\t\t\t\t\t\tend\n\t\t\t\t\tend)\n\n\t\t\t\t\tsliderValue.FocusLost:Connect(function(enterPressed)\n\t\t\t\t\t\tlocal inputText = tostring(sliderValue.Text or \"\")\n\t\t\t\t\t\tlocal numStr = inputText:match(\"%-?%d+%.?%d*\")\n\t\t\t\t\t\tlocal value = numStr and tonumber(numStr)\n\t\t\t\t\t\tif value then\n\t\t\t\t\t\t\tif SliderFunctions.Settings.DisplayMethod == \"Percent\" and inputText:find(\"%\", 1, true) then\n\t\t\t\t\t\t\t\tvalue = SliderFunctions.Settings.Minimum + (value / 100) * (SliderFunctions.Settings.Maximum - SliderFunctions.Settings.Minimum)\n\t\t\t\t\t\t\tend\n\t\t\t\t\t\t\tlocal newValue = math.clamp(value, SliderFunctions.Settings.Minimum, SliderFunctions.Settings.Maximum)\n\t\t\t\t\t\t\tSetValue(newValue)\n\t\t\t\t\t\telse\n\t\t\t\t\t\t\tsliderValue.Text = (Settings.Prefix or \"\") .. ValueDisplayMethod(finalValue, SliderFunctions.Settings.Precision) .. (Settings.Suffix or \"\")\n\t\t\t\t\t\tend\n\t\t\t\t\t\tif SliderFunctions.Settings.onInputComplete then\n\t\t\t\t\t\t\tSliderFunctions.Settings.onInputComplete(finalValue)\n\t\t\t\t\t\tend\n\t\t\t\t\tend)"



	)



	patch(



		"SetValue%(tonumber%(Value%), true%)",



		"SetValue(tonumber(Value), false)"



	)











	-- Recursive parent directory creation untuk BuildFolderTree()



	patch(



		"local paths = {\r?\n\t*MacLib%.Folder,\r?\n\t*MacLib%.Folder %.%. \"/settings\"\r?\n\t*}\r?\n\r?\n\t*for i = 1, #paths do\r?\n\t*local str = paths%[i%]\r?\n\t*if not isfolder%(str%) then\r?\n\t*makefolder%(str%)\r?\n\t*end\r?\n\t*end",



		[[local function safeMakeFolder(path)



			local clean = string.gsub(path, "\\", "/")



			local parts = string.split(clean, "/")



			local current = ""



			for _, part in ipairs(parts) do



				if part ~= "" then



					current = (current == "" and part) or (current .. "/" .. part)



					if not isfolder(current) then



						pcall(makefolder, current)



					end



				end



			end



		end











		safeMakeFolder(MacLib.Folder)



		safeMakeFolder(MacLib.Folder .. "/settings")]]



	)











	-- Tambahkan method MacLib:DeleteConfig(Path)



	patch(



		"function MacLib:SaveConfig%(Path%)",



		[[function MacLib:DeleteConfig(Path)



		if isStudio or not (isfile and (delfile or (syn and syn.delfile))) then return false, "Config system or delfile unavailable." end











		if (not Path) or string.gsub(tostring(Path), "%s+", "") == "" then



			return false, "Please select a config file to delete."



		end











		local fullPath = MacLib.Folder .. "/settings/" .. tostring(Path) .. ".json"



		if not isfile(fullPath) then



			return false, "Config file does not exist: " .. tostring(Path)



		end











		local delFunc = (typeof(delfile) == "function" and delfile)



			or (typeof(syn) == "table" and typeof(syn.delfile) == "function" and syn.delfile)



		if delFunc then



			local ok, err = pcall(delFunc, fullPath)



			if not ok then



				return false, tostring(err)



			end



			return true



		end











		return false, "delfile is unavailable."



	end











	function MacLib:SaveConfig(Path)]]



	)











	-- Fix Input Save agar selalu membaca teks terbaru dari GetInput()



	patch(



		"text = data%.Text",



		"text = (data.GetInput and data:GetInput()) or data.Text or \"\""



	)











	-- Fix Keybind Save & Load agar menyimpan EnumItem dari GetBind() dan memanggil onBinded



	patch(



		"bind = %(typeof%(data%.Bind%) == \"EnumItem\" and data%.Bind%.Name%) or nil",



		"bind = (data.GetBind and typeof(data:GetBind()) == \"EnumItem\" and data:GetBind().Name) or nil"



	)



	patch(



		"function KeybindFunctions:Bind%(Key%)\r?\n\t*binded = Key\r?\n\t*binderBox%.Text = Key%.Name",



		"function KeybindFunctions:Bind(Key)\n\t\t\t\t\t\tbinded = Key\n\t\t\t\t\t\tbinderBox.Text = Key.Name\n\t\t\t\t\t\tif KeybindFunctions.Settings.onBinded then KeybindFunctions.Settings.onBinded(binded) end"



	)











	-- Fix Dropdown Toggle(optionName, false) agar tidak mereset opsi lain pada Single Dropdown & selalu mengupdate DropdownFunctions.Value



	patch(



		"if DropdownFunctions%.Settings%.Multi then\r?\n\t*local idx = table%.find%(Selected, optionName%)\r?\n\t*if idx then\r?\n\t*table%.remove%(Selected, idx%)\r?\n\t*end\r?\n\t*else\r?\n\t*Selected = {}\r?\n\t*end",



		"local idx = table.find(Selected, optionName)\n\t\t\t\t\t\t\tif idx then\n\t\t\t\t\t\t\t\ttable.remove(Selected, idx)\n\t\t\t\t\t\t\tend\n\t\t\t\t\t\t\tif DropdownFunctions.Settings.Multi then\n\t\t\t\t\t\t\t\tDropdownFunctions.Value = Selected\n\t\t\t\t\t\t\telse\n\t\t\t\t\t\t\t\tDropdownFunctions.Value = Selected[1]\n\t\t\t\t\t\t\tend"



	)











	-- Clone & normalisasi newSelection pada DropdownFunctions:UpdateSelection sebelum mereset Selected, serta auto-map opsi bertag ([Class]/[Scroll]) atau auto-insert opsi yang belum ada



	patch(



		"function DropdownFunctions:UpdateSelection%(newSelection%)\r?\n\t*if not newSelection then return end",



		"function DropdownFunctions:UpdateSelection(newSelection)\n\t\t\t\t\t\tif not newSelection then return end\n\t\t\t\t\t\tlocal function _normKey(s)\n\t\t\t\t\t\t\tlocal c = string.lower(tostring(s or \"\"))\n\t\t\t\t\t\t\twhile string.find(c, \"^%s*%b[]%s*\") do c = string.gsub(c, \"^%s*%b[]%s*\", \"\", 1) end\n\t\t\t\t\t\t\tc = string.gsub(c, \"^%s*ultra%s*:%s*\", \"\")\n\t\t\t\t\t\t\treturn (string.gsub(c, \"[%s%p]\", \"\"))\n\t\t\t\t\t\tend\n\t\t\t\t\t\tlocal function _resolveOpt(rawOpt)\n\t\t\t\t\t\t\tif OptionObjs[rawOpt] then return rawOpt end\n\t\t\t\t\t\t\tlocal nk = _normKey(rawOpt)\n\t\t\t\t\t\t\tif nk ~= \"\" and type(DropdownFunctions.Settings.Options) == \"table\" then\n\t\t\t\t\t\t\t\tfor _, cand in ipairs(DropdownFunctions.Settings.Options) do\n\t\t\t\t\t\t\t\t\tif OptionObjs[cand] and _normKey(cand) == nk then\n\t\t\t\t\t\t\t\t\t\treturn cand\n\t\t\t\t\t\t\t\t\tend\n\t\t\t\t\t\t\t\tend\n\t\t\t\t\t\t\tend\n\t\t\t\t\t\t\tlocal gCanon = getgenv and (getgenv().__HUB_CANONICAL_OPTIONS or getgenv().__PIXEL_LINEAGE_CANONICAL_SKILLS)\n\t\t\t\t\t\t\tif type(gCanon) == \"table\" and nk ~= \"\" and type(gCanon[nk]) == \"string\" then\n\t\t\t\t\t\t\t\treturn gCanon[nk]\n\t\t\t\t\t\t\tend\n\t\t\t\t\t\t\treturn rawOpt\n\t\t\t\t\t\tend\n\t\t\t\t\t\tif type(newSelection) == \"string\" and newSelection ~= \"\" then\n\t\t\t\t\t\t\tnewSelection = _resolveOpt(newSelection)\n\t\t\t\t\t\t\tif not OptionObjs[newSelection] then\n\t\t\t\t\t\t\t\tDropdownFunctions.Settings.Options = DropdownFunctions.Settings.Options or {}\n\t\t\t\t\t\t\t\ttable.insert(DropdownFunctions.Settings.Options, newSelection)\n\t\t\t\t\t\t\t\taddOption(#DropdownFunctions.Settings.Options, newSelection)\n\t\t\t\t\t\t\tend\n\t\t\t\t\t\telseif type(newSelection) == \"table\" then\n\t\t\t\t\t\t\tlocal normalized = {}\n\t\t\t\t\t\t\tlocal seenNorm = {}\n\t\t\t\t\t\t\tfor _, v in ipairs(newSelection) do\n\t\t\t\t\t\t\t\tif type(v) == \"string\" and v ~= \"\" then\n\t\t\t\t\t\t\t\t\tlocal res = _resolveOpt(v)\n\t\t\t\t\t\t\t\t\tif not seenNorm[res] then seenNorm[res] = true; table.insert(normalized, res) end\n\t\t\t\t\t\t\t\tend\n\t\t\t\t\t\t\tend\n\t\t\t\t\t\t\tfor k, v in pairs(newSelection) do\n\t\t\t\t\t\t\t\tif type(k) == \"number\" and type(v) == \"string\" and v ~= \"\" then\n\t\t\t\t\t\t\t\t\tlocal res = _resolveOpt(v)\n\t\t\t\t\t\t\t\t\tif not seenNorm[res] then seenNorm[res] = true; table.insert(normalized, res) end\n\t\t\t\t\t\t\t\telseif v == true and type(k) == \"string\" and k ~= \"\" then\n\t\t\t\t\t\t\t\t\tlocal res = _resolveOpt(k)\n\t\t\t\t\t\t\t\t\tif not seenNorm[res] then seenNorm[res] = true; table.insert(normalized, res) end\n\t\t\t\t\t\t\t\tend\n\t\t\t\t\t\t\tend\n\t\t\t\t\t\t\tnewSelection = normalized\n\t\t\t\t\t\t\tDropdownFunctions.Settings.Options = DropdownFunctions.Settings.Options or {}\n\t\t\t\t\t\t\tfor _, opt in ipairs(newSelection) do\n\t\t\t\t\t\t\t\tif not OptionObjs[opt] then\n\t\t\t\t\t\t\t\t\ttable.insert(DropdownFunctions.Settings.Options, opt)\n\t\t\t\t\t\t\t\t\taddOption(#DropdownFunctions.Settings.Options, opt)\n\t\t\t\t\t\t\t\tend\n\t\t\t\t\t\t\tend\n\t\t\t\t\t\tend"



	)



	patch(



		"elseif type%(newSelection%) == \"table\" then\r?\n\t*for option, _ in pairs%(OptionObjs%) do\r?\n\t*local isSelected = table%.find%(newSelection, option%) ~= nil\r?\n\t*Toggle%(option, isSelected%)\r?\n\t*if isSelected then\r?\n\t*table%.insert%(selectedOptions, option%)\r?\n\t*end\r?\n\t*end",



		"elseif type(newSelection) == \"table\" then\n\t\t\t\t\t\t\tfor _, option in ipairs(newSelection) do\n\t\t\t\t\t\t\t\tif OptionObjs[option] then\n\t\t\t\t\t\t\t\t\tToggle(option, true)\n\t\t\t\t\t\t\t\t\ttable.insert(selectedOptions, option)\n\t\t\t\t\t\t\t\tend\n\t\t\t\t\t\t\tend\n\t\t\t\t\t\t\tDropdownFunctions.Value = selectedOptions"



	)



	patch(



		"DropdownFunctions%.Settings%.Callback%(Return%)",



		"DropdownFunctions.Settings.Callback(Return, selectedOptions)"



	)











	-- Dropdown: Buat SubLabel sebagai sub title di atas box dropdown & di dalam box hanya tampilkan value isinya



	patch(



		"function SectionFunctions:Dropdown%(Settings, Flag%)\r?\n\t*local DropdownFunctions = %{ Settings = Settings, IgnoreConfig = false, Class = \"Dropdown\" %}\r?\n\t*local Selected = %{%}\r?\n\t*local OptionObjs = %{%}\r?\n\r?\n\t*local dropdown = Instance%.new%(\"Frame\"%)",



		[[function SectionFunctions:Dropdown(Settings, Flag)



					local DropdownFunctions = { Settings = Settings, IgnoreConfig = false, Class = "Dropdown" }



					local Selected = {}



					local OptionObjs = {}











					local subLabel = nil



					local subTitleText = Settings.SubTitle or Settings.Subtitle or Settings.Title or Settings.Name



					if subTitleText ~= false and type(subTitleText) == "string" and subTitleText ~= "" then



						subLabel = SectionFunctions:SubLabel({ Text = subTitleText })



					end











					local dropdown = Instance.new("Frame")]]



	)



	patch(



		"function DropdownFunctions:SetVisibility%(State%)\r?\n\t*dropdown%.Visible = State\r?\n\t*end",



		[[function DropdownFunctions:SetVisibility(State)



						if subLabel and type(subLabel.SetVisibility) == "function" then



							pcall(subLabel.SetVisibility, subLabel, State)



						end



						dropdown.Visible = State



					end



					function DropdownFunctions:SetVisiblity(State)



						DropdownFunctions:SetVisibility(State)



					end]]



	)



	patch(



		"function DropdownFunctions:UpdateName%(New%)\r?\n\t*dropdownName%.Text = New\r?\n\t*end",



		[[function DropdownFunctions:UpdateName(New)



						if subLabel and type(subLabel.UpdateName) == "function" then



							pcall(subLabel.UpdateName, subLabel, New)



						end



					end]]



	)



	patch(



		"dropdownName%.Text = Settings%.Default and %(DropdownFunctions%.Settings%.Name %.%. \" • \" %.%. table%.concat%(Selected, \", \"%)%) or %(DropdownFunctions%.Settings%.Name %.%. \"%.%.%.\"%)",



		[[dropdownName.Text = (Settings.Default and #Selected > 0 and table.concat(Selected, ", ")) or (Settings.Placeholder or "Select...")]]



	)



	patch(



		"dropdownName%.Text = DropdownFunctions%.Settings%.Name %.%. \" • \" %.%. table%.concat%(Selected, \", \"%)\r?\n\t*else\r?\n\t*dropdownName%.Text = DropdownFunctions%.Settings%.Name %.%. \"%.%.%.\"",



		[[dropdownName.Text = table.concat(Selected, ", ")



						else



							dropdownName.Text = Settings.Placeholder or "Select..."]]



	)











	-- Fix urutan LoadConfig (clean reset non-internal toggles, legacy flag alias resolver, non-Toggle dulu baru Toggle)



	patch(



		"for _, option in next, decoded%.objects do\r?\n\t*if ClassParser%[option%.type%] then\r?\n\t*task%.spawn%(function%(%) \r?\n\t*ClassParser%[option%.type%]%.Load%(option%.flag, option%) \r?\n\t*end%)\r?\n\t*end\r?\n\t*end",



		[=[local _aliasMap = {



			["Pengaturan Universal::Anti-AFK"] = "Universal Settings::Anti-AFK",



			["Pengaturan Universal::Custom Shortcut"] = "Universal Settings::Custom Shortcut",



			["Pengaturan Universal::UI Scale"] = "Universal Settings::UI Scale",



		}



		local userAliases = getgenv and getgenv().__HUB_CONFIG_ALIASES



		if type(userAliases) == "table" then



			for k, v in pairs(userAliases) do



				_aliasMap[k] = v



			end



		end



		if getgenv and getgenv().__PIXEL_LINEAGE_CANONICAL_SKILLS then



			_aliasMap["Navigation::Auto Vote & Proceed"] = "Run Map Navigation::Auto Vote & Proceed"



			_aliasMap["Combat Auto-Play::Smart Auto-Play"] = "Combat Auto-Play::Smart Auto Combat"



			_aliasMap["Combat Auto-Play::Auto Combat"] = "Combat Auto-Play::Auto Basic Attack"



			_aliasMap["Combat Auto-Play::Auto Use Skill"] = "Combat Auto-Play::Auto Cast Selected Skills"



			_aliasMap["Battle End & Speed::Skip Animations (Fast Mode)"] = "Battle End & Speed::Fast Battle"



			_aliasMap["Battle End & Speed::Fast Battle (Skip Animations)"] = "Battle End & Speed::Fast Battle"



			_aliasMap["Battle End & Speed::Auto Open Chest"] = "Battle End & Speed::Auto Open Boss Chest"



			_aliasMap["Battle End & Speed::Auto Continue"] = "Battle End & Speed::Auto Continue (Battle Results)"



			_aliasMap["Dungeon Loop::Auto Play Again"] = "Dungeon Loop::Auto Play Again (Solo Campaign)"



			_aliasMap["Torment & Halloween::Auto Join Best Torment"] = "Torment & Halloween::Smart Auto Farm Torment (Safe Tier)"



			_aliasMap["Torment & Halloween::Auto Farm Torment (Continuous)"] = "Torment & Halloween::Smart Auto Farm Torment (Safe Tier)"



			_aliasMap["Torment & Halloween::Auto Halloween (Random Queue)"] = "Torment & Halloween::Auto Halloween (Party Queue)"



			_aliasMap["Auto Join Solo Run::Auto Join Solo Run"] = "Auto Join Solo Run::Auto Join Solo Campaign"



			_aliasMap["Auto Sell Gear::Auto Sell Gear"] = "Auto Sell Gear::Auto Sell Junk Gear"



			_aliasMap["Auto Sell Gear::Sell Rarities"] = "Auto Sell Gear::Direct Sell Rarities (Sell All)"



			_aliasMap["Minigame QTE::Auto Perfect Minigame"] = "Minigame QTE::Auto Perfect QTE"



			_aliasMap["God-Roll Gear Protection & Stash::Auto Stash God Rolls"] = "Duplicate Filter & Gear Protection::Auto Stash Secret & Forged Gear"



			_aliasMap["God-Roll Gear Protection & Stash::Protect God Rolls"] = "Duplicate Filter & Gear Protection::Filter & Keep Best Duplicate Rarities"



			_aliasMap["Auto Potion::Potion HP %"] = "Auto Potion & Emergency Survival::Survival HP %"



			_aliasMap["Auto Potion & Emergency Survival::Survival HP % Threshold"] = "Auto Potion & Emergency Survival::Survival HP %"



		end



		local function _resolveFlag(flag)



			if MacLib.Options[flag] then return flag end



			if _aliasMap[flag] and MacLib.Options[_aliasMap[flag]] then return _aliasMap[flag] end



			local ctrlName = string.match(flag, "::(.*)$") or flag



			for cand in pairs(MacLib.Options) do



				local candCtrl = string.match(cand, "::(.*)$") or cand



				if candCtrl == ctrlName then return cand end



			end



			return flag



		end



		for optFlag, opt in pairs(MacLib.Options) do
			local isInternal = false
			if type(opt) == "table" then
				if opt._isInternalConfig or opt._isInternalConfigToggle then
					isInternal = true
				elseif type(opt.Settings) == "table" and (opt.Settings._isInternalConfig or opt.Settings._isInternalConfigToggle) then
					isInternal = true
				end
			end
			local isUniversalProtected = string.find(optFlag, "Anti-AFK", 1, true)
				or string.find(optFlag, "Mobile Toggle", 1, true)
				or string.find(optFlag, "Disable 3D", 1, true)
				or string.find(optFlag, "Low Graphics", 1, true)
				or string.find(optFlag, "Auto Reconnect", 1, true)
				or string.find(optFlag, "FPS Limiter", 1, true)
				or string.find(optFlag, "GUI Shortcut", 1, true)
				or string.find(optFlag, "Hide GUI", 1, true)
				or string.find(optFlag, "Anonymous Mode", 1, true)

			if (opt.Class == "Toggle" or opt.type == "Toggle") and not isInternal and not isUniversalProtected then
				pcall(function() opt:UpdateState(false) end)
			end
		end



		for _, option in next, decoded.objects do



			option.flag = _resolveFlag(option.flag)



			if option.type ~= "Toggle" and ClassParser[option.type] then



				pcall(ClassParser[option.type].Load, option.flag, option)



				if option.flag == "Auto Potion::Potion HP %" or option.flag == "Auto Potion & Emergency Survival::Survival HP %" or option.flag == "Auto Potion::Potion HP % (Slider)" or option.flag == "Auto Potion::Potion HP % (Text Field)" then



					local numVal = tonumber(option.value or option.text)



					if numVal then



						local opt = MacLib.Options["Auto Potion & Emergency Survival::Survival HP %"] or MacLib.Options["Auto Potion::Potion HP %"]



						if opt then pcall(function() opt:UpdateValue(numVal) end) end



						if MacLib.Options["Auto Potion::Potion HP % (Slider)"] then pcall(function() MacLib.Options["Auto Potion::Potion HP % (Slider)"]:UpdateValue(numVal) end) end



						if MacLib.Options["Auto Potion::Potion HP % (Text Field)"] then pcall(function() MacLib.Options["Auto Potion::Potion HP % (Text Field)"]:UpdateText(tostring(math.floor(numVal + 0.5))) end) end



					end



				end



			end



		end



		for _, option in next, decoded.objects do



			option.flag = _resolveFlag(option.flag)



			if option.type == "Toggle" and ClassParser[option.type] then



				task.spawn(function()



					ClassParser[option.type].Load(option.flag, option)



				end)



			end



		end]=]



	)











	-- Perbaiki UX InsertConfigSection (Required = true pada Select Config, fallback nama config untuk Load/Overwrite/Autoload)



	patch(



		"Callback = function%(input%)\r?\n\t*inputPath = input\r?\n\t*end,",



		"Callback = function(input)\n\t\t\t\t\t\tinputPath = input\n\t\t\t\t\tend,\n\t\t\t\t\tonChanged = function(input)\n\t\t\t\t\t\tinputPath = input\n\t\t\t\t\tend,"



	)



	patch(



		"Name = \"Select Config\",\r?\n\t*Multi = false,\r?\n\t*Required = false,",



		"Name = \"Select Config\",\n\t\t\t\t\tMulti = false,\n\t\t\t\t\tRequired = true,"



	)



	patch(



		"configSelection:ClearOptions%(%)\r?\n\t*configSelection:InsertOptions%(MacLib:RefreshConfigList%(%)%)\r?\n\t*end,\r?\n\t*}%)\r?\n\r?\n\t*configSection:Button%({\r?\n\t*Name = \"Load Config\"",



		[[configSelection:ClearOptions()



						configSelection:InsertOptions(MacLib:RefreshConfigList())



						pcall(function()
							if configSelection.UpdateSelection then configSelection:UpdateSelection(inputPath)
							elseif configSelection.Set then configSelection:Set(inputPath) end
						end)



					end,



				})











				local lp = LocalPlayer or (Players and Players.LocalPlayer) or (game:GetService("Players") and game:GetService("Players").LocalPlayer)



				local currentAccountOpt = "Per Account"



				local globalAccountOpt = "All Accounts"



				local userAutoloadPath = (lp and lp.UserId) and (MacLib.Folder .. "/settings/autoload_" .. tostring(lp.UserId) .. ".txt") or nil



				local globalAutoloadPath = MacLib.Folder .. "/settings/autoload.txt"



				local selectedScope = currentAccountOpt











				local function removeFileSafe(filePath)



					if not (filePath and isfile and isfile(filePath)) then return end



					pcall(function()



						if delfile then



							delfile(filePath)



						else



							writefile(filePath, "")



						end



					end)



				end











				local function getScopePath(scope)



					if scope == globalAccountOpt or not userAutoloadPath then



						return globalAutoloadPath, globalAccountOpt



					else



						return userAutoloadPath, currentAccountOpt



					end



				end











				local function getActiveAutoloadPath()



					return getScopePath(selectedScope)



				end











				local function getAutoloadForScope(scope)



					if not (isfile and readfile) then return nil end



					local path = getScopePath(scope)



					if path and isfile(path) then



						local name = readfile(path)



						if name and string.gsub(name, "%s+", "") ~= "" then



							return name



						end



					end



					return nil



				end











				local refreshAutoloadDisplay











				local function resolveTargetConfig()



					local cfgName = configSelection.Value



					if type(cfgName) == "table" then



						cfgName = cfgName[1]



					end



					if not cfgName or string.gsub(tostring(cfgName), "%s+", "") == "" then



						if inputPath and string.gsub(tostring(inputPath), "%s+", "") ~= "" then



							cfgName = inputPath



						else



							local autoName = getAutoloadForScope(selectedScope)



							if (not autoName or string.gsub(autoName, "%s+", "") == "") then



								local otherScope = (selectedScope == currentAccountOpt) and globalAccountOpt or currentAccountOpt



								autoName = getAutoloadForScope(otherScope)



							end



							if autoName and string.gsub(autoName, "%s+", "") ~= "" then



								cfgName = autoName



							end



						end



					end



					return cfgName



				end











				configSection:Button({



					Name = "Delete Config",



					Callback = function()



						local targetCfg = configSelection.Value



						if type(targetCfg) == "table" then



							targetCfg = targetCfg[1]



						end



						if (not targetCfg or string.gsub(tostring(targetCfg), "%s+", "") == "") and (inputPath and string.gsub(tostring(inputPath), "%s+", "") ~= "") then



							targetCfg = inputPath



						end











						if not targetCfg or string.gsub(tostring(targetCfg), "%s+", "") == "" then



							WindowFunctions:Notify({



								Title = "Interface",



								Description = "Please select or enter a config to delete.",



							})



							return



						end











						local success, returned = MacLib:DeleteConfig(targetCfg)



						if not success then



							WindowFunctions:Notify({



								Title = "Interface",



								Description = "Unable to delete config: " .. tostring(returned or "Failed"),



							})



							return



						end











						pcall(function()



							if isfile and readfile then



								if userAutoloadPath and isfile(userAutoloadPath) and readfile(userAutoloadPath) == targetCfg then



									removeFileSafe(userAutoloadPath)



								end



								if globalAutoloadPath and isfile(globalAutoloadPath) and readfile(globalAutoloadPath) == targetCfg then



									removeFileSafe(globalAutoloadPath)



								end



							end



						end)



						if type(refreshAutoloadDisplay) == "function" then



							refreshAutoloadDisplay()



						end











						WindowFunctions:Notify({



							Title = "Interface",



							Description = string.format("Deleted config %q", tostring(targetCfg)),



						})











						configSelection:ClearOptions()



						local updatedList = MacLib:RefreshConfigList()



						configSelection:InsertOptions(updatedList)



						local nextSelection = (#updatedList > 0 and updatedList[1]) or nil



						pcall(function()
							if configSelection.UpdateSelection then configSelection:UpdateSelection(nextSelection)
							elseif configSelection.Set then configSelection:Set(nextSelection) end
						end)



					end,



				})











				configSection:Button({



					Name = "Load Config"]]



	)



	patch(



		"local success, returned = MacLib:LoadConfig%(configSelection%.Value%)",



		"local targetCfg = resolveTargetConfig()\n\t\t\t\t\t\tlocal success, returned = MacLib:LoadConfig(targetCfg)"



	)



	patch(



		"Description = string%.format%(\"Loaded config %%q\", configSelection%.Value%)",



		"Description = string.format(\"Loaded config %q\", tostring(resolveTargetConfig() or \"\"))"



	)



	patch(



		"local success, returned = MacLib:SaveConfig%(configSelection%.Value%)",



		"local targetCfg = resolveTargetConfig()\n\t\t\t\t\t\tlocal success, returned = MacLib:SaveConfig(targetCfg)\n\t\t\t\t\t\tif success and targetCfg then configSelection:UpdateSelection(targetCfg) end"



	)



	patch(



		"Description = string%.format%(\"Overwrote config %%q\", configSelection%.Value%)",



		"Description = string.format(\"Overwrote config %q\", tostring(resolveTargetConfig() or \"\"))"



	)



	patch(



		"local autoloadLabel.-if isfile%(MacLib%.Folder %.%. \"/settings/autoload%.txt\"%) then.-autoloadLabel:UpdateName%(.-%)\r?\n\t*end",



		[[local autoloadLabel



				refreshAutoloadDisplay = function()



					if not autoloadLabel then return nil end



					local scope = selectedScope or currentAccountOpt



					local name = getAutoloadForScope(scope)



					if name then



						autoloadLabel:UpdateName("Autoload: " .. name .. " (" .. scope .. ")")



						return name



					else



						autoloadLabel:UpdateName("Autoload: None (" .. scope .. ")")



						return nil



					end



				end











				local initialScopeChoice = currentAccountOpt



				local initialAutoload = nil



				if userAutoloadPath and isfile(userAutoloadPath) then



					local u = readfile(userAutoloadPath)



					if u and string.gsub(u, "%s+", "") ~= "" then



						initialAutoload = u



						initialScopeChoice = currentAccountOpt



					end



				end



				if not initialAutoload and globalAutoloadPath and isfile(globalAutoloadPath) then



					local g = readfile(globalAutoloadPath)



					if g and string.gsub(g, "%s+", "") ~= "" then



						initialAutoload = g



						initialScopeChoice = globalAccountOpt



					end



				end



				selectedScope = initialScopeChoice











				local scopeDropdown = configSection:Dropdown({



					Name = "Config Scope",



					Multi = false,



					Required = true,



					Options = { currentAccountOpt, globalAccountOpt },



					Callback = function(v)



						selectedScope = v



						if autoloadLabel then



							autoloadLabel:UpdateName("Autoload: None (" .. v .. ")")



						end



					end,



				})



				pcall(function()
					if scopeDropdown.UpdateSelection then
						scopeDropdown:UpdateSelection(initialScopeChoice)
					elseif scopeDropdown.Set then
						scopeDropdown:Set(initialScopeChoice)
					end
				end)











				configSection:Button({



					Name = "Set as autoload",



					Callback = function()



						local targetCfg = resolveTargetConfig()



						if not targetCfg or string.gsub(tostring(targetCfg), "%s+", "") == "" then



							WindowFunctions:Notify({



								Title = "Interface",



								Description = "Please select or enter a config first.",



							})



							return



						end



						MacLib:SaveConfig(targetCfg)



						configSelection:ClearOptions()



						configSelection:InsertOptions(MacLib:RefreshConfigList())



						pcall(function()
							if configSelection.UpdateSelection then configSelection:UpdateSelection(targetCfg)
							elseif configSelection.Set then configSelection:Set(targetCfg) end
						end)











						local path, scopeName = getActiveAutoloadPath()



						-- Jika user pilih scope ini, pastikan scope lain dibersihkan (hanya ada autoload di scope yang dipilih, tidak keduanya)



						if scopeName == currentAccountOpt and globalAutoloadPath then



							removeFileSafe(globalAutoloadPath)



						elseif scopeName == globalAccountOpt and userAutoloadPath then



							removeFileSafe(userAutoloadPath)



						end











						writefile(path, targetCfg)



						refreshAutoloadDisplay()



						WindowFunctions:Notify({



							Title = "Interface",



							Description = string.format("Set %q as %s autoload", targetCfg, scopeName:lower()),



						})



					end,



				})











				autoloadLabel = configSection:Label({Text = "Autoload: None"})











				configSection:Button({



					Name = "Clear autoload",



					Callback = function()



						local path, scopeName = getActiveAutoloadPath()



						removeFileSafe(path)



						if scopeName == currentAccountOpt and globalAutoloadPath then



							removeFileSafe(globalAutoloadPath)



						elseif scopeName == globalAccountOpt and userAutoloadPath then



							removeFileSafe(userAutoloadPath)



						end



						refreshAutoloadDisplay()



						WindowFunctions:Notify({



							Title = "Interface",



							Description = string.format("Cleared %s autoload config.", scopeName:lower()),



						})



					end,



				})











				refreshAutoloadDisplay()



				if initialAutoload and isfile(MacLib.Folder .. "/settings/" .. initialAutoload .. ".json") then



					pcall(function()
						if configSelection.UpdateSelection then configSelection:UpdateSelection(initialAutoload)
						elseif configSelection.Set then configSelection:Set(initialAutoload) end
					end)



				end]]



	)



	patch(



		"function MacLib:LoadAutoLoadConfig%(%).-\r?\n\tend\r?\n",



		[[function MacLib:LoadAutoLoadConfig()



		if isStudio or not (isfile and readfile) then return "Config system unavailable." end



		local lp = LocalPlayer or (Players and Players.LocalPlayer) or (game:GetService("Players") and game:GetService("Players").LocalPlayer)



		local userPath = (lp and lp.UserId) and (MacLib.Folder .. "/settings/autoload_" .. tostring(lp.UserId) .. ".txt") or nil



		local globalPath = MacLib.Folder .. "/settings/autoload.txt"



		local targetPath = nil



		local isAccountScope = false











		if userPath and isfile(userPath) then



			local uName = readfile(userPath)



			if uName and string.gsub(uName, "%s+", "") ~= "" then



				targetPath = userPath



				isAccountScope = true



			end



		end











		if not targetPath and isfile(globalPath) then



			local gName = readfile(globalPath)



			if gName and string.gsub(gName, "%s+", "") ~= "" then



				targetPath = globalPath



			end



		end











		if targetPath and isfile(targetPath) then



			local name = readfile(targetPath)



			if not name or string.gsub(name, "%s+", "") == "" or not isfile(MacLib.Folder .. "/settings/" .. name .. ".json") then return end



			local suc, err = MacLib:LoadConfig(name)



			if not suc then



				WindowFunctions:Notify({



					Title = "Interface",



					Description = "Error loading autoload config: " .. tostring(err),



				})



				return



			end











			WindowFunctions:Notify({



				Title = "Interface",



				Description = string.format("Autoloaded config: %q (%s)", name, isAccountScope and "Per Account" or "All Accounts"),



			})



		end



	end



]]



	)











	-- 8. Fix kebocoran event listener UserInputService pada Maclib & pastikan disconnect saat Unload



	patch(



		"function MacLib:Window%(Settings%)%s*local WindowFunctions = {Settings = Settings}",



		[[function MacLib:Window(Settings)



		local WindowFunctions = {Settings = Settings}



		local _macInternalConns = {}



		local _realUIS = UserInputService



		local UserInputService = setmetatable({}, {



			__index = function(_, k)



				local val = _realUIS[k]



				if typeof(val) == "RBXScriptSignal" then



					return {



						Connect = function(_, fn)



							local c = val:Connect(fn)



							table.insert(_macInternalConns, c)



							return c



						end,



						connect = function(_, fn)



							local c = val:Connect(fn)



							table.insert(_macInternalConns, c)



							return c



						end,



						Wait = function(_)



							return val:Wait()



						end,



						wait = function(_)



							return val:Wait()



						end,



					}



				end



				return val



			end



		})]]



	)



	patch(
		"UserInputService%.InputEnded:Connect%(function%(inp, gpe%)%s*if gpe then return end%s*if inp%.KeyCode == MenuKeybind then%s*ToggleMenu%(%)%s*end%s*end%)",
		[[local menuToggleConn = nil -- Fully disabled raw MacLib InputEnded listener]]
	)

	patch(
		"local function ToggleMenu%(%)%s*local state = not WindowFunctions:GetState%(%)%s*WindowFunctions:SetState%(state%)%s*WindowFunctions:Notify%({.-}%s*%)%s*end",
		[[local function ToggleMenu()
		-- Fully disabled: Shenky Hub manages debounced toggling and clean notifications
	end]]
	)



	patch(



		"function WindowFunctions:Unload%(%)%s*if onUnloadCallback then%s*onUnloadCallback%(%)%s*end%s*macLib:Destroy%(%)%s*unloaded = true%s*end",



		[[function WindowFunctions:Unload()



		if unloaded then return end



		unloaded = true



		if menuToggleConn then



			pcall(function() menuToggleConn:Disconnect() end)



			menuToggleConn = nil



		end



		if type(_macInternalConns) == "table" then



			for _, conn in ipairs(_macInternalConns) do



				pcall(function() conn:Disconnect() end)



			end



			table.clear(_macInternalConns)



		end



		if onUnloadCallback then



			pcall(onUnloadCallback)



		end



		pcall(function() macLib:Destroy() end)



		-- Bersihkan sisa DepthOfField dan glass parts kamera



		pcall(function()



			local okLight, Lighting = pcall(game.GetService, game, "Lighting")



			if okLight and Lighting then



				for _, v in ipairs(Lighting:GetChildren()) do



					if v:IsA("DepthOfFieldEffect") and (v:HasTag(".") or v.NearIntensity == 1) then



						pcall(function() v.Enabled = false; v:Destroy() end)



					end



				end



			end



			local cam = workspace.CurrentCamera



			if cam then



				for _, v in ipairs(cam:GetChildren()) do



					if v:IsA("DepthOfFieldEffect") or (v:IsA("BasePart") and v.Material == Enum.Material.Glass) then



						pcall(function() v:Destroy() end)



					end



				end



			end



		end)



	end]]



	)











	-- Expose window elements & attach instances to element functions



	patch(



		"macLib%.Enabled = true\r?\n\t*windowState = true\r?\n\r?\n\t*return WindowFunctions",



		[[macLib.Enabled = true



	windowState = true











	WindowFunctions.Base = base



	WindowFunctions.Topbar = topbar



	WindowFunctions.Elements = elements



	WindowFunctions.Information = information



	WindowFunctions.InformationHolder = informationHolder



	WindowFunctions.MacLib = macLib











	return WindowFunctions]]



	)











	patch("return ToggleFunctions", "ToggleFunctions.Instance = toggle\n\t\t\t\t\treturn ToggleFunctions")



	patch("return SliderFunctions", "SliderFunctions.Instance = slider\n\t\t\t\t\treturn SliderFunctions")



	patch("return ButtonFunctions", "ButtonFunctions.Instance = button\n\t\t\t\t\treturn ButtonFunctions")



	patch("return DropdownFunctions", "DropdownFunctions.Instance = dropdown\n\t\t\t\t\treturn DropdownFunctions")



	patch("return InputFunctions", "InputFunctions.Instance = input\n\t\t\t\t\treturn InputFunctions")











	
-- Dropdown Checkmark already integrated in addOption
return src



end











local patchedSource = nil -- getgenv and getgenv().__GLOBAL_SHENKY_PATCHED_SRC



if type(patchedSource) ~= "string" or #patchedSource < 1000 then



	patchedSource = patchShenkyUISource(rawUISource)



	if getgenv then



		getgenv().__GLOBAL_SHENKY_PATCHED_SRC = patchedSource



		getgenv().__GLOBAL_MACLIB_PATCHED_SRC = patchedSource



	end



end











local ShenkyUI = loadstring(patchedSource)()











function ShenkyUI:DeleteConfig(Path)



	if isStudio or not (isfile and (delfile or (syn and syn.delfile))) then



		return false, "Config system or delfile unavailable."



	end



	if not Path or string.gsub(tostring(Path), "%s+", "") == "" then



		return false, "Please select a config file to delete."



	end



	local fullPath = self.Folder .. "/settings/" .. tostring(Path) .. ".json"



	if not isfile(fullPath) then



		return false, "Config file does not exist: " .. tostring(Path)



	end



	local delFunc = (typeof(delfile) == "function" and delfile)



		or (typeof(syn) == "table" and typeof(syn.delfile) == "function" and syn.delfile)



	if delFunc then



		local ok, err = pcall(delFunc, fullPath)



		if not ok then



			return false, tostring(err)



		end



		return true



	end



	return false, "delfile is unavailable."



end



















return ShenkyUI












end

-- Module: core/mobile
__modules["core/mobile"] = function()
-- core/mobile.luau
-- Premium Floating Status Pill & Draggable Mobile Toggle for Shenky Hub
-- Features: Prominent Brand Badge with Gear Icon, Dynamic Micro-Icons for Stats (FPS/Ping/Clock),
-- Slate Navy Glass Container, Native Engine Telemetry, Zero-RenderStepped Throttled Updates.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StatsService = game:GetService("Stats")
local Icons = __require("assets/icons")

local function create(className, props)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		if k == "Parent" then
			inst.Parent = v
		else
			inst[k] = v
		end
	end
	return inst
end

return function(self, WindowWrapper, cfg)
	local Hub = self
	cfg = cfg or {}

	-- 1. Teardown previous toggle instance & connections
	if self._mobileToggleLoopStop then
		pcall(self._mobileToggleLoopStop)
		self._mobileToggleLoopStop = nil
	end
	if self._mobileToggleGui then
		pcall(self._mobileToggleGui.Destroy, self._mobileToggleGui)
		self._mobileToggleGui = nil
	end
	if self._mobileToggleConns then
		for _, c in ipairs(self._mobileToggleConns) do
			pcall(c.Disconnect, c)
		end
		self._mobileToggleConns = nil
	end

	local rawWindow = self._ShenkyWindow or self._Window or (WindowWrapper and WindowWrapper._raw)
	if not rawWindow then return end

	-- 2. Resolve safe GUI parent (gethui / cloneref(CoreGui) / PlayerGui)
	local parent = (function()
		local okHui, h = pcall(gethui)
		if okHui and h and typeof(h) == "Instance" then return h end
		local okCg, cg = pcall(game.GetService, game, "CoreGui")
		if okCg and cg then
			local okP = pcall(function() return cg:GetChildren() end)
			if okP then return (cloneref and cloneref(cg)) or cg end
		end
		local lp = Players.LocalPlayer
		return (lp and lp:FindFirstChild("PlayerGui")) or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	end)()
	if not parent then return end

	local screenGui = create("ScreenGui", {
		Name = "ShenkyHubMobileToggle",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 999999,
		IgnoreGuiInset = true, -- Critical: enables positioning directly into the Roblox topbar row
		Parent = parent,
	})
	if syn and type(syn.protect_gui) == "function" then
		pcall(syn.protect_gui, screenGui)
	elseif typeof(protectgui) == "function" then
		pcall(protectgui, screenGui)
	elseif typeof(protect_gui) == "function" then
		pcall(protect_gui, screenGui)
	end

	local style = cfg.MobileToggleStyle or "Pill"
	local conns = {}
	local button = nil
	local updateVisuals = nil
	local pillScale = nil

	local logoAsset = Hub.LogoAsset or (typeof(getgenv().__SHENKY_LOGO_ASSET) == "string" and getgenv().__SHENKY_LOGO_ASSET) or Icons.Resolve("sparkles")

	if style == "Button" then
		-- Classic 50x50 Squircle Button
		button = create("ImageButton", {
			Name = "ToggleButton",
			Size = UDim2.fromOffset(50, 50),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = cfg.MobileTogglePosition or UDim2.new(0.5, 0, 0, 32),
			BackgroundColor3 = Color3.fromRGB(15, 12, 26),
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			ClipsDescendants = true,
			Parent = screenGui,
		})
		create("UICorner", { CornerRadius = UDim.new(0, 14), Parent = button })
		
		local btnStroke = create("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.fromRGB(115, 85, 220),
			Thickness = 1.5,
			Transparency = 0.2,
			Parent = button,
		})

		local logo = create("ImageLabel", {
			Name = "Logo",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScaleType = Enum.ScaleType.Fit,
			Image = logoAsset,
			Parent = button,
		})
		create("UICorner", { CornerRadius = UDim.new(0, 14), Parent = logo })

		updateVisuals = function(isOpen)
			pcall(function()
				local targetColor = isOpen and Color3.fromRGB(140, 100, 255) or Color3.fromRGB(75, 55, 140)
				local targetTrans = isOpen and 0.15 or 0.4
				TweenService:Create(btnStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Color = targetColor,
					Transparency = targetTrans,
				}):Play()
			end)
		end
	else
		-- Premium Status Pill with Prominent Badge & Micro-Icons
		local subtitleText = "Universal"
		if cfg.SubTitle or cfg.Subtitle then
			subtitleText = tostring(cfg.SubTitle or cfg.Subtitle)
		elseif cfg.Title and cfg.Title ~= "Shenky Hub" then
			subtitleText = tostring(cfg.Title)
		end

		local defaultPos = cfg.MobileTogglePosition or UDim2.new(0.5, 0, 0, 8)

		button = create("TextButton", {
			Name = "StatusPill",
			Size = UDim2.new(0, 0, 0, 32),
			AutomaticSize = Enum.AutomaticSize.X,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = defaultPos,
			BackgroundColor3 = Color3.fromRGB(15, 15, 17),
			BackgroundTransparency = 0.10,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			Text = "",
			ClipsDescendants = false,
			Parent = screenGui,
		})
		create("UICorner", { CornerRadius = UDim.new(0, 16), Parent = button })

		local pillStroke = create("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.fromRGB(255, 255, 255),
			Thickness = 1.0,
			Transparency = 0.90,
			Parent = button,
		})

		pillScale = create("UIScale", {
			Scale = 1.0,
			Parent = button,
		})

		create("UIPadding", {
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 3),
			PaddingBottom = UDim.new(0, 3),
			Parent = button,
		})

		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
			Parent = button,
		})

		-- 1. Brand Logo Badge in Obsidian / Lavender Theme Accent
		local badge = create("Frame", {
			Name = "Badge",
			Size = UDim2.new(0, 0, 0, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Color3.fromRGB(24, 27, 38),
			BorderSizePixel = 0,
			LayoutOrder = 1,
			Parent = button,
		})
		create("UICorner", { CornerRadius = UDim.new(0, 13), Parent = badge })

		create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 36, 56)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 22, 34)),
			}),
			Rotation = 90,
			Parent = badge,
		})

		local badgeStroke = create("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.fromRGB(160, 185, 255),
			Thickness = 1,
			Transparency = 0.70,
			Parent = badge,
		})

		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
			Parent = badge,
		})

		create("UIPadding", {
			PaddingLeft = UDim.new(0, 7),
			PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 2),
			PaddingBottom = UDim.new(0, 2),
			Parent = badge,
		})

		-- Shenky S Logo inside Badge
		local badgeLogo = create("ImageLabel", {
			Name = "BadgeLogo",
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScaleType = Enum.ScaleType.Fit,
			Image = logoAsset,
			LayoutOrder = 1,
			Parent = badge,
		})

		-- Bold White Title Text
		local badgeLabel = create("TextLabel", {
			Name = "BadgeLabel",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text = "Shenky Hub",
			TextColor3 = Color3.fromRGB(245, 248, 255),
			TextSize = 12,
			FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.Bold),
			TextYAlignment = Enum.TextYAlignment.Center,
			LayoutOrder = 2,
			Parent = badge,
		})

		-- 2. Game Title / Subtitle
		local gameTitle = create("TextLabel", {
			Name = "GameTitle",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text = subtitleText,
			TextColor3 = Color3.fromRGB(185, 190, 205),
			TextSize = 11,
			FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.Medium),
			TextYAlignment = Enum.TextYAlignment.Center,
			LayoutOrder = 2,
			Parent = button,
		})

		-- Helper for subtle hairline vertical dividers
		local function makeDivider(order)
			return create("Frame", {
				Name = "Divider",
				Size = UDim2.new(0, 1, 0, 12),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 0.90,
				BorderSizePixel = 0,
				LayoutOrder = order,
				Parent = button,
			})
		end

		makeDivider(3)

		-- 3. FPS Stat (Icon + Text)
		local fpsFrame = create("Frame", {
			Name = "FpsFrame",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = 4,
			Parent = button,
		})
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
			Parent = fpsFrame,
		})
		local fpsIcon = create("ImageLabel", {
			Name = "FpsIcon",
			Size = UDim2.fromOffset(13, 13),
			BackgroundTransparency = 1,
			Image = "rbxassetid://10709770317", -- bar-chart-2
			ImageColor3 = Color3.fromRGB(160, 185, 255),
			ImageTransparency = 0.15,
			ScaleType = Enum.ScaleType.Fit,
			LayoutOrder = 1,
			Parent = fpsFrame,
		})
		local fpsLabel = create("TextLabel", {
			Name = "FpsStat",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text = "-- fps",
			TextColor3 = Color3.fromRGB(225, 230, 242),
			TextSize = 11,
			FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.Medium),
			TextYAlignment = Enum.TextYAlignment.Center,
			LayoutOrder = 2,
			Parent = fpsFrame,
		})

		makeDivider(5)

		-- 4. Ping Stat (Icon + Text)
		local pingFrame = create("Frame", {
			Name = "PingFrame",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = 6,
			Parent = button,
		})
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
			Parent = pingFrame,
		})
		local pingIcon = create("ImageLabel", {
			Name = "PingIcon",
			Size = UDim2.fromOffset(13, 13),
			BackgroundTransparency = 1,
			Image = "rbxassetid://10747382504", -- wifi
			ImageColor3 = Color3.fromRGB(160, 185, 255),
			ImageTransparency = 0.15,
			ScaleType = Enum.ScaleType.Fit,
			LayoutOrder = 1,
			Parent = pingFrame,
		})
		local pingLabel = create("TextLabel", {
			Name = "PingStat",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text = "-- ms",
			TextColor3 = Color3.fromRGB(225, 230, 242),
			TextSize = 11,
			FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.Medium),
			TextYAlignment = Enum.TextYAlignment.Center,
			LayoutOrder = 2,
			Parent = pingFrame,
		})

		makeDivider(7)

		-- 5. Clock Stat (Icon + Text)
		local clockFrame = create("Frame", {
			Name = "ClockFrame",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = 8,
			Parent = button,
		})
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
			Parent = clockFrame,
		})
		local clockIcon = create("ImageLabel", {
			Name = "ClockIcon",
			Size = UDim2.fromOffset(13, 13),
			BackgroundTransparency = 1,
			Image = "rbxassetid://10709805144", -- clock
			ImageColor3 = Color3.fromRGB(160, 185, 255),
			ImageTransparency = 0.15,
			ScaleType = Enum.ScaleType.Fit,
			LayoutOrder = 1,
			Parent = clockFrame,
		})
		local clockLabel = create("TextLabel", {
			Name = "ClockStat",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text = os.date("%H:%M"),
			TextColor3 = Color3.fromRGB(225, 230, 242),
			TextSize = 11,
			FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.Medium),
			TextYAlignment = Enum.TextYAlignment.Center,
			LayoutOrder = 2,
			Parent = clockFrame,
		})

		local currentIsOpen = true
		local isHovered = false

		local function applyVisualState(animate)
			local dur = animate and 0.22 or 0
			local tInfo = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

			-- Toggle ON (Window Open): Solid Obsidian Dark (0.10) with Lavender Glow Stroke (0.65)
			-- Toggle OFF (Window Closed): Translucent Stealth Mode (0.55) with Subtle Hairline Stroke (0.88)
			local targetBgTrans = currentIsOpen and 0.10 or 0.55
			local targetStrokeColor = currentIsOpen and Color3.fromRGB(160, 185, 255) or Color3.fromRGB(255, 255, 255)
			local targetStrokeTrans = currentIsOpen and 0.65 or 0.88

			local targetBadgeBgTrans = currentIsOpen and 0.0 or 0.40
			local targetBadgeStrokeColor = currentIsOpen and Color3.fromRGB(160, 185, 255) or Color3.fromRGB(255, 255, 255)
			local targetBadgeStrokeTrans = currentIsOpen and 0.70 or 0.85

			local targetTextTrans = currentIsOpen and 0.0 or 0.25
			local targetTitleTrans = currentIsOpen and 0.0 or 0.30
			local targetIconTrans = currentIsOpen and 0.15 or 0.35

			if isHovered then
				if currentIsOpen then
					targetBgTrans = 0.04
					targetStrokeTrans = 0.45
				else
					targetBgTrans = 0.18
					targetStrokeTrans = 0.65
					targetBadgeBgTrans = 0.10
					targetTextTrans = 0.0
					targetTitleTrans = 0.0
					targetIconTrans = 0.15
				end
			end

			pcall(function()
				if dur > 0 then
					TweenService:Create(button, tInfo, { BackgroundTransparency = targetBgTrans }):Play()
					TweenService:Create(pillStroke, tInfo, { Color = targetStrokeColor, Transparency = targetStrokeTrans }):Play()
					TweenService:Create(badge, tInfo, { BackgroundTransparency = targetBadgeBgTrans }):Play()
					TweenService:Create(badgeStroke, tInfo, { Color = targetBadgeStrokeColor, Transparency = targetBadgeStrokeTrans }):Play()
					TweenService:Create(badgeLabel, tInfo, { TextTransparency = targetTextTrans }):Play()
					TweenService:Create(badgeLogo, tInfo, { ImageTransparency = targetIconTrans }):Play()
					TweenService:Create(gameTitle, tInfo, { TextTransparency = targetTitleTrans }):Play()
					TweenService:Create(fpsLabel, tInfo, { TextTransparency = targetTextTrans }):Play()
					TweenService:Create(fpsIcon, tInfo, { ImageTransparency = targetIconTrans }):Play()
					TweenService:Create(pingLabel, tInfo, { TextTransparency = targetTextTrans }):Play()
					TweenService:Create(pingIcon, tInfo, { ImageTransparency = targetIconTrans }):Play()
					TweenService:Create(clockLabel, tInfo, { TextTransparency = targetTextTrans }):Play()
					TweenService:Create(clockIcon, tInfo, { ImageTransparency = targetIconTrans }):Play()
				else
					button.BackgroundTransparency = targetBgTrans
					pillStroke.Color = targetStrokeColor
					pillStroke.Transparency = targetStrokeTrans
					badge.BackgroundTransparency = targetBadgeBgTrans
					badgeStroke.Color = targetBadgeStrokeColor
					badgeStroke.Transparency = targetBadgeStrokeTrans
					badgeLabel.TextTransparency = targetTextTrans
					badgeLogo.ImageTransparency = targetIconTrans
					gameTitle.TextTransparency = targetTitleTrans
					fpsLabel.TextTransparency = targetTextTrans
					fpsIcon.ImageTransparency = targetIconTrans
					pingLabel.TextTransparency = targetTextTrans
					pingIcon.ImageTransparency = targetIconTrans
					clockLabel.TextTransparency = targetTextTrans
					clockIcon.ImageTransparency = targetIconTrans
				end
			end)
		end

		updateVisuals = function(isOpen)
			currentIsOpen = isOpen
			applyVisualState(true)
		end

		table.insert(conns, button.MouseEnter:Connect(function()
			isHovered = true
			applyVisualState(true)
		end))

		table.insert(conns, button.MouseLeave:Connect(function()
			isHovered = false
			applyVisualState(true)
		end))
		-- Background Throttled Stats Loop (0.5s interval = 2 updates/sec, ZERO RenderStepped load)
		local loopActive = true
		self._mobileToggleLoopStop = function()
			loopActive = false
		end

		local lastFps = -1
		local lastPing = -1
		local lastClock = ""

		task.spawn(function()
			while loopActive and screenGui.Parent do
				pcall(function()
					-- Query FPS natively from engine stats (Dirty check avoids unnecessary UI relayout)
					local rawFps = 60
					local okFps, fpsVal = pcall(function() return StatsService.Workspace.Heartbeat:GetValue() end)
					if okFps and type(fpsVal) == "number" and fpsVal > 0 then
						rawFps = math.round(fpsVal)
					end
					if rawFps ~= lastFps then
						lastFps = rawFps
						fpsLabel.Text = string.format("%d fps", rawFps)
					end

					-- Query Ping natively from engine stats (Dirty check)
					local rawPing = 0
					local okPing, pingVal = pcall(function() return StatsService.Network.ServerStatsItem["Data Ping"]:GetValue() end)
					if okPing and type(pingVal) == "number" and pingVal >= 0 then
						rawPing = math.round(pingVal)
					end
					if rawPing ~= lastPing then
						lastPing = rawPing
						pingLabel.Text = string.format("%d ms", rawPing)
					end

					-- Time string (only re-sets text when minute actually changes)
					local curClock = os.date("%H:%M")
					if curClock ~= lastClock then
						lastClock = curClock
						clockLabel.Text = curClock
					end
				end)
				task.wait(1.0)
			end
		end)
	end

	-- Visual state sync (Glow on open, Dim on close)
	if type(updateVisuals) == "function" then
		local prevSetState = rawWindow.SetState
		if type(prevSetState) == "function" then
			rawWindow.SetState = function(wSelf, state)
				prevSetState(wSelf, state)
				updateVisuals(state)
			end
		end
		pcall(function() updateVisuals(rawWindow:GetState()) end)
	end

	-- Touch & Mouse Drag Logic (Bulletproof input tracking)
	local isDragging = false
	local dragStart = Vector2.zero
	local startPos = button.Position
	local moved = false
	local pressStartTime = 0
	local camera = workspace.CurrentCamera
	local dragMoveConn = nil

	table.insert(conns, button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = true
			dragStart = Vector2.new(input.Position.X, input.Position.Y)
			startPos = button.Position
			moved = false
			pressStartTime = os.clock()

			if pillScale then
				pcall(function()
					TweenService:Create(pillScale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Scale = 0.96,
					}):Play()
				end)
			end

			if dragMoveConn then dragMoveConn:Disconnect() end
			dragMoveConn = UserInputService.InputChanged:Connect(function(moveInput)
				if isDragging and (moveInput.UserInputType == Enum.UserInputType.MouseMovement or moveInput.UserInputType == Enum.UserInputType.Touch) then
					local cur = Vector2.new(moveInput.Position.X, moveInput.Position.Y)
					local delta = cur - dragStart
					if not moved and (math.abs(delta.X) > 6 or math.abs(delta.Y) > 6) then
						moved = true
					end
					if moved then
						local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
						local baseAbsX = startPos.X.Scale * vp.X + startPos.X.Offset
						local baseAbsY = startPos.Y.Scale * vp.Y + startPos.Y.Offset
						local currentAbsX = baseAbsX + delta.X
						local currentAbsY = baseAbsY + delta.Y
						
						local halfW = button.AbsoluteSize.X / 2
						local h = button.AbsoluteSize.Y
						local clampedX = math.clamp(currentAbsX, halfW + 4, math.max(halfW + 4, vp.X - halfW - 4))
						local clampedY = math.clamp(currentAbsY, 4, math.max(4, vp.Y - h - 4))
						button.Position = UDim2.fromOffset(clampedX, clampedY)
					end
				end
			end)

			local changedConn
			changedConn = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					isDragging = false
					if changedConn then
						changedConn:Disconnect()
						changedConn = nil
					end
					if dragMoveConn then
						dragMoveConn:Disconnect()
						dragMoveConn = nil
					end
					if pillScale then
						pcall(function()
							TweenService:Create(pillScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
								Scale = 1.0,
							}):Play()
						end)
					end
					if not moved and (os.clock() - pressStartTime) < 0.5 then
						pcall(function() WindowWrapper:Toggle() end)
					end
				end
			end)
		end
	end))

	table.insert(conns, UserInputService.WindowFocusReleased:Connect(function()
		isDragging = false
	end))

	screenGui.Parent = parent
	self._mobileToggleGui = screenGui
	self._mobileToggleBtn = button
	self._mobileToggleConns = conns
end

end

-- Module: core/search
__modules["core/search"] = function()
-- core/search.luau
-- Shenky Hub Interactive Search System: Header Search Bar, Live Filter, Quick Actions & Jump-to-Feature

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local function createSearchSystem(Hub, ShenkyWindow)
	if not (ShenkyWindow and ShenkyWindow.Elements and ShenkyWindow.Base) then return end

	local elements = ShenkyWindow.Elements
	local base = ShenkyWindow.Base

	-- 1. Search Bar Container in Topbar (Right-aligned)
	local searchContainer = Instance.new("Frame")
	searchContainer.Name = "SearchContainer"
	searchContainer.AnchorPoint = Vector2.new(1, 0.5)
	searchContainer.Position = UDim2.new(1, 0, 0.5, 0)
	searchContainer.Size = UDim2.new(0, 170, 0, 24)
	searchContainer.BackgroundColor3 = Color3.fromRGB(22, 23, 29)
	searchContainer.BackgroundTransparency = 0
	searchContainer.BorderSizePixel = 0
	searchContainer.ZIndex = 15

	local searchCorner = Instance.new("UICorner")
	searchCorner.CornerRadius = UDim.new(0, 6)
	searchCorner.Parent = searchContainer

	local searchStroke = Instance.new("UIStroke")
	searchStroke.Color = Color3.fromRGB(50, 54, 65)
	searchStroke.Thickness = 1
	searchStroke.Transparency = 0.5
	searchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	searchStroke.Parent = searchContainer

	-- Magnifying Glass Icon
	local searchIcon = Instance.new("ImageLabel")
	searchIcon.Name = "SearchIcon"
	searchIcon.AnchorPoint = Vector2.new(0, 0.5)
	searchIcon.Position = UDim2.new(0, 7, 0.5, 0)
	searchIcon.Size = UDim2.fromOffset(12, 12)
	searchIcon.BackgroundTransparency = 1
	searchIcon.Image = "rbxassetid://86737463322606"
	searchIcon.ImageColor3 = Color3.fromRGB(130, 135, 145)
	searchIcon.ZIndex = 16
	searchIcon.Parent = searchContainer

	-- Text Input Box
	local searchBox = Instance.new("TextBox")
	searchBox.Name = "SearchBox"
	searchBox.AnchorPoint = Vector2.new(0, 0.5)
	searchBox.Position = UDim2.new(0, 24, 0.5, 0)
	searchBox.Size = UDim2.new(1, -44, 1, 0)
	searchBox.BackgroundTransparency = 1
	searchBox.Text = ""
	searchBox.PlaceholderText = "Search features..."
	searchBox.PlaceholderColor3 = Color3.fromRGB(110, 115, 125)
	searchBox.TextColor3 = Color3.fromRGB(240, 245, 255)
	searchBox.TextSize = 11
	searchBox.FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.Regular)
	searchBox.TextXAlignment = Enum.TextXAlignment.Left
	searchBox.ClearTextOnFocus = false
	searchBox.ZIndex = 16
	searchBox.Parent = searchContainer

	-- Clear Button (Clean Lucide Icon - no missing font glyphs)
	local clearBtn = Instance.new("ImageButton")
	clearBtn.Name = "ClearButton"
	clearBtn.AnchorPoint = Vector2.new(1, 0.5)
	clearBtn.Position = UDim2.new(1, -6, 0.5, 0)
	clearBtn.Size = UDim2.fromOffset(13, 13)
	clearBtn.BackgroundTransparency = 1
	clearBtn.Image = "rbxassetid://10747383819"
	clearBtn.ImageColor3 = Color3.fromRGB(130, 135, 145)
	clearBtn.Visible = false
	clearBtn.ZIndex = 17
	clearBtn.Parent = searchContainer

	searchContainer.Parent = elements

	-- 2. Floating Search Dropdown Popup (Parented to Base window)
	local searchPopup = Instance.new("Frame")
	searchPopup.Name = "SearchPopup"
	searchPopup.AnchorPoint = Vector2.new(1, 0)
	searchPopup.Position = UDim2.new(1, -12, 0, 36)
	searchPopup.Size = UDim2.new(0, 220, 0, 210)
	searchPopup.BackgroundColor3 = Color3.fromRGB(18, 19, 25)
	searchPopup.BackgroundTransparency = 0.02
	searchPopup.BorderSizePixel = 0
	searchPopup.ClipsDescendants = true
	searchPopup.Visible = false
	searchPopup.ZIndex = 60

	local popupCorner = Instance.new("UICorner")
	popupCorner.CornerRadius = UDim.new(0, 8)
	popupCorner.Parent = searchPopup

	local popupStroke = Instance.new("UIStroke")
	popupStroke.Color = Color3.fromRGB(45, 50, 62)
	popupStroke.Thickness = 1
	popupStroke.Transparency = 0.3
	popupStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	popupStroke.Parent = searchPopup

	-- Popup Header
	local popupHeader = Instance.new("Frame")
	popupHeader.Name = "PopupHeader"
	popupHeader.Size = UDim2.new(1, 0, 0, 26)
	popupHeader.BackgroundTransparency = 1
	popupHeader.ZIndex = 61
	popupHeader.Parent = searchPopup

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "HeaderTitle"
	headerTitle.AnchorPoint = Vector2.new(0, 0.5)
	headerTitle.Position = UDim2.new(0, 10, 0.5, 0)
	headerTitle.Size = UDim2.new(0.6, 0, 1, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Text = "MATCHING FEATURES"
	headerTitle.TextColor3 = Color3.fromRGB(120, 125, 140)
	headerTitle.TextSize = 10
	headerTitle.FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.Bold)
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.ZIndex = 62
	headerTitle.Parent = popupHeader

	local headerCount = Instance.new("TextLabel")
	headerCount.Name = "HeaderCount"
	headerCount.AnchorPoint = Vector2.new(1, 0.5)
	headerCount.Position = UDim2.new(1, -10, 0.5, 0)
	headerCount.Size = UDim2.new(0.4, 0, 1, 0)
	headerCount.BackgroundTransparency = 1
	headerCount.Text = "0 found"
	headerCount.TextColor3 = Color3.fromRGB(180, 185, 200)
	headerCount.TextSize = 10
	headerCount.FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.SemiBold)
	headerCount.TextXAlignment = Enum.TextXAlignment.Right
	headerCount.ZIndex = 62
	headerCount.Parent = popupHeader

	local headerDivider = Instance.new("Frame")
	headerDivider.Name = "Divider"
	headerDivider.AnchorPoint = Vector2.new(0, 1)
	headerDivider.Position = UDim2.new(0, 0, 1, 0)
	headerDivider.Size = UDim2.new(1, 0, 0, 1)
	headerDivider.BackgroundColor3 = Color3.fromRGB(35, 38, 48)
	headerDivider.BorderSizePixel = 0
	headerDivider.ZIndex = 61
	headerDivider.Parent = popupHeader

	-- Scrolling container for results
	local resultsScroll = Instance.new("ScrollingFrame")
	resultsScroll.Name = "ResultsScroll"
	resultsScroll.Position = UDim2.new(0, 0, 0, 27)
	resultsScroll.Size = UDim2.new(1, 0, 1, -27)
	resultsScroll.BackgroundTransparency = 1
	resultsScroll.BorderSizePixel = 0
	resultsScroll.ScrollBarThickness = 3
	resultsScroll.ScrollBarImageColor3 = Color3.fromRGB(65, 70, 85)
	resultsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	resultsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	resultsScroll.ZIndex = 61
	resultsScroll.Parent = searchPopup

	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Padding = UDim.new(0, 3)
	scrollLayout.Parent = resultsScroll

	local scrollPadding = Instance.new("UIPadding")
	scrollPadding.PaddingTop = UDim.new(0, 4)
	scrollPadding.PaddingBottom = UDim.new(0, 4)
	scrollPadding.PaddingLeft = UDim.new(0, 6)
	scrollPadding.PaddingRight = UDim.new(0, 6)
	scrollPadding.Parent = resultsScroll

	-- Empty state label
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyLabel"
	emptyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	emptyLabel.Position = UDim2.new(0.5, 0, 0.5, 10)
	emptyLabel.Size = UDim2.new(1, -20, 0, 30)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = "No matching features"
	emptyLabel.TextColor3 = Color3.fromRGB(110, 115, 125)
	emptyLabel.TextSize = 11
	emptyLabel.FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.Regular)
	emptyLabel.Visible = false
	emptyLabel.ZIndex = 62
	emptyLabel.Parent = searchPopup

	searchPopup.Parent = base

	-- Register search objects to block accidental window dragging
	if type(ShenkyWindow.RegisterDragBlocker) == "function" then
		ShenkyWindow:RegisterDragBlocker(searchContainer)
		ShenkyWindow:RegisterDragBlocker(searchPopup)
	end

	-- 3. Element Highlighting Effect
	local function highlightGui(inst)
		if not (inst and typeof(inst) == "Instance") then return end
		pcall(function()
			local oldStroke = inst:FindFirstChild("ShenkySearchGlow")
			if oldStroke then oldStroke:Destroy() end
			local stroke = Instance.new("UIStroke")
			stroke.Name = "ShenkySearchGlow"
			stroke.Color = Color3.fromRGB(70, 75, 90) -- Sky cyan
			stroke.Thickness = 1.5
			stroke.Transparency = 0
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = inst

			local tween = TweenService:Create(
				stroke,
				TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = 1, Color = Color3.fromRGB(255, 255, 255) }
			)
			tween:Play()
			task.delay(1.4, function()
				pcall(function() stroke:Destroy() end)
			end)
		end)
	end

	-- 4. Result Card Builder
	local typeBadges = {
		Toggle = { Text = "TOGGLE", Bg = Color3.fromRGB(38, 42, 54), Fg = Color3.fromRGB(200, 210, 225) },
		Slider = { Text = "SLIDER", Bg = Color3.fromRGB(38, 42, 54), Fg = Color3.fromRGB(200, 210, 225) },
		Button = { Text = "BUTTON", Bg = Color3.fromRGB(5, 150, 105), Fg = Color3.fromRGB(255, 255, 255) },
		Dropdown = { Text = "DROPDOWN", Bg = Color3.fromRGB(124, 58, 237), Fg = Color3.fromRGB(255, 255, 255) },
		Input = { Text = "INPUT", Bg = Color3.fromRGB(79, 70, 229), Fg = Color3.fromRGB(255, 255, 255) },
	}

	local function renderResults(query)
		for _, child in ipairs(resultsScroll:GetChildren()) do
			if child:IsA("GuiObject") and child.Name == "ResultCard" then
				child:Destroy()
			end
		end

		query = string.lower(string.gsub(tostring(query or ""), "^%s*(.-)%s*$", "%1"))
		if query == "" then
			searchPopup.Visible = false
			clearBtn.Visible = false
			return
		end

		clearBtn.Visible = true
		searchPopup.Visible = true

		local features = Hub._registeredFeatures or {}
		local matches = {}

		for _, feat in ipairs(features) do
			local nameLower = string.lower(tostring(feat.Name or ""))
			local secLower = string.lower(tostring(feat.SectionTitle or ""))
			local tabLower = string.lower(tostring(feat.TabTitle or ""))
			if string.find(nameLower, query, 1, true) or string.find(secLower, query, 1, true) or string.find(tabLower, query, 1, true) then
				table.insert(matches, feat)
			end
		end

		headerCount.Text = tostring(#matches) .. " found"

		if #matches == 0 then
			emptyLabel.Text = string.format("No features matching %q", query)
			emptyLabel.Visible = true
			return
		else
			emptyLabel.Visible = false
		end

		for idx, feat in ipairs(matches) do
			local card = Instance.new("TextButton")
			card.Name = "ResultCard"
			card.Size = UDim2.new(1, 0, 0, 32)
			card.BackgroundColor3 = Color3.fromRGB(24, 25, 33)
			card.BorderSizePixel = 0
			card.Text = ""
			card.AutoButtonColor = false
			card.ZIndex = 62

			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, 5)
			cardCorner.Parent = card

			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = Color3.fromRGB(40, 44, 56)
			cardStroke.Thickness = 1
			cardStroke.Transparency = 0.6
			cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			cardStroke.Parent = card

			-- Feature Name & Breadcrumb (Clean compact layout without type badge)
			local titleLabel = Instance.new("TextLabel")
			titleLabel.Name = "Title"
			titleLabel.Position = UDim2.new(0, 10, 0, 2)
			titleLabel.Size = UDim2.new(1, -30, 0, 15)
			titleLabel.BackgroundTransparency = 1
			titleLabel.Text = tostring(feat.Name or "")
			titleLabel.TextColor3 = Color3.fromRGB(240, 245, 255)
			titleLabel.TextSize = 11
			titleLabel.FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.SemiBold)
			titleLabel.TextXAlignment = Enum.TextXAlignment.Left
			titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
			titleLabel.ZIndex = 63
			titleLabel.Parent = card

			local pathLabel = Instance.new("TextLabel")
			pathLabel.Name = "Path"
			pathLabel.Position = UDim2.new(0, 10, 0, 16)
			pathLabel.Size = UDim2.new(1, -30, 0, 12)
			pathLabel.BackgroundTransparency = 1
			pathLabel.Text = string.format("%s > %s", tostring(feat.TabTitle or "General"), tostring(feat.SectionTitle or "Main"))
			pathLabel.TextColor3 = Color3.fromRGB(130, 140, 155)
			pathLabel.TextSize = 9
			pathLabel.FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.Regular)
			pathLabel.TextXAlignment = Enum.TextXAlignment.Left
			pathLabel.TextTruncate = Enum.TextTruncate.AtEnd
			pathLabel.ZIndex = 63
			pathLabel.Parent = card

			-- Navigation arrow on Right (Search is pure navigation / finder)
			local arrowLabel = Instance.new("TextLabel")
			arrowLabel.Name = "NavArrow"
			arrowLabel.AnchorPoint = Vector2.new(1, 0.5)
			arrowLabel.Position = UDim2.new(1, -10, 0.5, 0)
			arrowLabel.Size = UDim2.fromOffset(14, 14)
			arrowLabel.BackgroundTransparency = 1
			arrowLabel.Text = "›"
			arrowLabel.TextColor3 = Color3.fromRGB(120, 125, 140)
			arrowLabel.TextSize = 16
			arrowLabel.FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.Bold)
			arrowLabel.ZIndex = 64
			arrowLabel.Parent = card

			-- Hover animation
			card.MouseEnter:Connect(function()
				TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(33, 35, 46) }):Play()
			end)
			card.MouseLeave:Connect(function()
				TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(24, 25, 33) }):Play()
			end)

			-- Jump to Feature on card click
			card.MouseButton1Click:Connect(function()
				searchPopup.Visible = false
				if feat.Tab and type(feat.Tab.Select) == "function" then
					pcall(function() feat.Tab:Select() end)
				end
				local inst = (feat.Raw and (feat.Raw.Instance or feat.Raw.instance)) or (feat.Wrapper and feat.Wrapper._raw and feat.Wrapper._raw.Instance)
				if inst then
					highlightGui(inst)
				end
			end)

			card.Parent = resultsScroll
		end
	end

	-- 5. Search Box Events
	local function onTextChanged()
		renderResults(searchBox.Text)
	end
	searchBox:GetPropertyChangedSignal("Text"):Connect(onTextChanged)
	searchBox.Changed:Connect(function(prop)
		if prop == "Text" then
			onTextChanged()
		end
	end)

	searchBox.Focused:Connect(function()
		if #searchBox.Text > 0 then
			renderResults(searchBox.Text)
		end
		TweenService:Create(searchStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(75, 80, 95), Transparency = 0.3 }):Play()
	end)

	searchBox.FocusLost:Connect(function()
		TweenService:Create(searchStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(50, 54, 65), Transparency = 0.5 }):Play()
	end)

	clearBtn.MouseButton1Click:Connect(function()
		searchBox.Text = ""
		searchPopup.Visible = false
		clearBtn.Visible = false
	end)

	-- 6. Outside Click & Hotkey (Ctrl + F / Escape)
	local function isWindowOpen()
		local open = false
		pcall(function()
			if ShenkyWindow and type(ShenkyWindow.GetState) == "function" then
				open = ShenkyWindow:GetState()
			end
		end)
		return open
	end

	UserInputService.InputBegan:Connect(function(input, gpe)
		-- Never process search hotkeys or capture focus if the GUI window is closed
		if not isWindowOpen() then return end

		-- Explicit parentheses: Only capture focus if user presses F while holding either LeftControl or RightControl
		if input.KeyCode == Enum.KeyCode.F and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
			searchBox:CaptureFocus()
		elseif input.KeyCode == Enum.KeyCode.Escape then
			if searchPopup.Visible or searchBox:IsFocused() then
				searchBox.Text = ""
				searchPopup.Visible = false
				clearBtn.Visible = false
				pcall(function() searchBox:ReleaseFocus() end)
			end
		elseif (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and searchPopup.Visible then
			local mousePos = UserInputService:GetMouseLocation()
			local popupPos = searchPopup.AbsolutePosition
			local popupSize = searchPopup.AbsoluteSize
			local inPopup = (mousePos.X >= popupPos.X and mousePos.X <= popupPos.X + popupSize.X and mousePos.Y >= popupPos.Y and mousePos.Y <= popupPos.Y + popupSize.Y)
			local boxPos = searchContainer.AbsolutePosition
			local boxSize = searchContainer.AbsoluteSize
			local inBox = (mousePos.X >= boxPos.X and mousePos.X <= boxPos.X + boxSize.X and mousePos.Y >= boxPos.Y and mousePos.Y <= boxPos.Y + boxSize.Y)
			if not (inPopup or inBox) then
				task.defer(function()
					if searchPopup and not searchBox:IsFocused() then
						searchPopup.Visible = false
					end
				end)
			end
		end
	end)

	local searchObj = {
		Container = searchContainer,
		Popup = searchPopup,
		SearchBox = searchBox,
		Search = function(query)
			searchBox.Text = tostring(query or "")
			renderResults(searchBox.Text)
		end,
	}
	Hub._SearchSystem = searchObj
	return searchObj
end

return createSearchSystem

end

-- Module: modules/webhook
__modules["modules/webhook"] = function()
-- modules/webhook.luau
-- Discord Webhook Integration

local HttpService = game:GetService("HttpService")

return function(Hub)
function Hub:SendWebhook(cfg)
	if type(cfg) ~= "table" then return false, "Config table required" end
	local url = cfg.Url or cfg.url or cfg.Webhook or cfg.webhook
	if not url or type(url) ~= "string" or not string.find(url, "discord%.com/api/webhooks") then
		return false, "Invalid Discord Webhook URL"
	end

	local httpReq = (type(request) == "function" and request)
		or (type(http_request) == "function" and http_request)
		or (type(syn) == "table" and type(syn.request) == "function" and syn.request)
		or nil

	if not httpReq then
		return false, "Executor does not support HTTP requests"
	end

	local HttpService = game:GetService("HttpService")
	local payload = {}

	if cfg.Content or cfg.content then
		payload.content = tostring(cfg.Content or cfg.content)
	end
	if cfg.Username or cfg.username then
		payload.username = tostring(cfg.Username or cfg.username)
	else
		payload.username = "Shenky Hub"
	end
	if cfg.AvatarUrl or cfg.avatar_url then
		payload.avatar_url = tostring(cfg.AvatarUrl or cfg.avatar_url)
	end

	local embeds = {}
	if cfg.Title or cfg.Description or cfg.Fields or cfg.Embed then
		local embed = (type(cfg.Embed) == "table" and cfg.Embed) or {}
		if cfg.Title then embed.title = tostring(cfg.Title) end
		if cfg.Description then embed.description = tostring(cfg.Description) end
		if cfg.Color then
			embed.color = tonumber(cfg.Color) or 0x38bdf8
		elseif not embed.color then
			embed.color = 0x38bdf8
		end
		if cfg.Fields then
			embed.fields = cfg.Fields
		end
		if cfg.Footer then
			embed.footer = (type(cfg.Footer) == "table" and cfg.Footer) or { text = tostring(cfg.Footer) }
		else
			embed.footer = { text = "Shenky Hub • " .. os.date("%X") }
		end
		table.insert(embeds, embed)
	end

	if #embeds > 0 then
		payload.embeds = embeds
	end

	local okJson, bodyStr = pcall(HttpService.JSONEncode, HttpService, payload)
	if not okJson then
		return false, "Failed to encode JSON payload"
	end

	local success, res = pcall(function()
		return httpReq({
			Url = url,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
			Body = bodyStr,
		})
	end)

	if not success then
		return false, tostring(res)
	end

	local status = (type(res) == "table" and (res.StatusCode or res.Status)) or 200
	if status == 200 or status == 204 then
		return true, "Webhook sent successfully"
	else
		return false, "Discord returned HTTP status " .. tostring(status)
	end
end

-- ==== Hub Universal ESP System ====
Hub._activeESPs = {}


end

end

-- Module: modules/esp
__modules["modules/esp"] = function()
-- modules/esp.luau
-- Universal ESP System with Container Caching & Auto-Teardown on Target Despawn

local Players = game:GetService("Players")

return function(Hub)
local _cachedParentFolder = nil
local function getEspParentFolder()
	if _cachedParentFolder and _cachedParentFolder.Parent then
		return _cachedParentFolder
	end
	local okHui, h = pcall(gethui)
	if okHui and h and typeof(h) == "Instance" then
		_cachedParentFolder = h
		return h
	end
	local okCg, cg = pcall(game.GetService, game, "CoreGui")
	if okCg and cg then
		local okP = pcall(function() return cg:GetChildren() end)
		if okP then
			_cachedParentFolder = cg
			return cg
		end
	end
	local lp = Players.LocalPlayer
	_cachedParentFolder = (lp and lp:FindFirstChild("PlayerGui")) or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	return _cachedParentFolder
end

function Hub:CreateESP(target, cfg)
	if not target then return nil end
	cfg = cfg or {}
	local part = (target:IsA("BasePart") and target)
		or (target:IsA("Model") and (target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")))
	if not part then return nil end

	self:RemoveESP(target)

	local text = tostring(cfg.Text or target.Name)
	local color = cfg.Color or Color3.fromRGB(56, 189, 248)
	local maxDist = tonumber(cfg.MaxDistance) or 1500

	local bb = Instance.new("BillboardGui")
	bb.Name = "ShenkyESP"
	bb.Adornee = part
	bb.Size = UDim2.fromOffset(160, 32)
	bb.StudsOffset = cfg.Offset or Vector3.new(0, 2.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = maxDist

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.TextSize = 13
	lbl.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold)
	lbl.TextStrokeTransparency = 0.2
	lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	lbl.Parent = bb

	bb.Parent = getEspParentFolder()

	-- Auto-cleanup on target despawn / deletion to prevent memory leaks
	local conn = nil
	conn = target.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if conn then
				pcall(conn.Disconnect, conn)
				conn = nil
			end
			self:RemoveESP(target)
		end
	end)

	local entry = {
		Gui = bb,
		Target = target,
		Part = part,
		Text = text,
		_conn = conn,
	}
	self._activeESPs[target] = entry

	return entry
end

function Hub:RemoveESP(target)
	if target and self._activeESPs[target] then
		local entry = self._activeESPs[target]
		if entry._conn then
			pcall(entry._conn.Disconnect, entry._conn)
			entry._conn = nil
		end
		if entry.Gui then
			pcall(entry.Gui.Destroy, entry.Gui)
		end
		self._activeESPs[target] = nil
	end
end

function Hub:ClearAllESP()
	for target, entry in pairs(self._activeESPs or {}) do
		if entry._conn then
			pcall(entry._conn.Disconnect, entry._conn)
		end
		if entry.Gui then
			pcall(entry.Gui.Destroy, entry.Gui)
		end
	end
	self._activeESPs = {}
end

end

end

-- Module: tabs/home
__modules["tabs/home"] = function()
-- tabs/home.luau
-- Universal Home Tab & Session Telemetry Runtime for Shenky Hub
-- Provides Real-time Status Telemetry, Universal Quick Actions, and In-Game Update Log
-- Game-specific Stats card is strictly opt-in via Hub:SetStats(statsList)
-- Game-specific Update Log is sourced dynamically from history.luau or Hub:SetHistory(list)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local StatsService = game:GetService("Stats")

local DISCORD_INVITE = "https://discord.gg/hvYpw59MS"

return function(Hub)
	Hub.DiscordInvite = DISCORD_INVITE

	local HomeRuntime = {
		_startTime = os.clock(),
		_lastFps = 60,
		_fpsFrames = 0,
		_fpsTimer = os.clock(),
		_fpsConn = nil,
		_statusGrid = nil,
		_statsSec = nil,
		_statsGrid = nil,
		_customStats = nil,
		_customHistory = nil,
		_historySec = nil,
		_historyLog = nil,
		_homeTab = nil,
		_tickerGen = 0,
		_executeCount = nil,
	}

	Hub._HomeRuntime = HomeRuntime

	function HomeRuntime:GetExecuteCount()
		if self._executeCount then
			return self._executeCount
		end
		local count = 1
		pcall(function()
			if isfolder and makefolder and not isfolder("Shenky") then
				makefolder("Shenky")
			end
			local path = "Shenky/executes.txt"
			if isfile and isfile(path) and readfile then
				local content = readfile(path)
				local num = tonumber(content)
				if num and num >= 1 then
					count = num + 1
				end
			end
			if writefile then
				writefile(path, tostring(count))
			end
		end)
		if count == 1 and getgenv then
			pcall(function()
				local envCount = tonumber(getgenv().__SHENKY_EXECUTE_COUNT)
				if envCount and envCount >= 1 then
					count = envCount + 1
				end
				getgenv().__SHENKY_EXECUTE_COUNT = count
			end)
		elseif getgenv then
			pcall(function()
				getgenv().__SHENKY_EXECUTE_COUNT = count
			end)
		end
		self._executeCount = count
		Hub.ExecuteCount = count
		return count
	end

	function HomeRuntime:FormatSession(elapsed)
		local totalSeconds = math.floor(elapsed)
		local hours = math.floor(totalSeconds / 3600)
		local minutes = math.floor((totalSeconds % 3600) / 60)
		local seconds = totalSeconds % 60

		if hours > 0 then
			return string.format("%dh %02dm %02ds", hours, minutes, seconds)
		else
			return string.format("%dm %02ds", minutes, seconds)
		end
	end

	function HomeRuntime:GetActiveFeaturesCount()
		local count = 0
		if type(Hub._toggles) == "table" then
			for _, tog in ipairs(Hub._toggles) do
				if tog then
					local ok, val = false, false
					if type(tog.GetState) == "function" then
						ok, val = pcall(function() return tog:GetState() end)
					elseif type(tog.GetValue) == "function" then
						ok, val = pcall(function() return tog:GetValue() end)
					elseif tog._raw and type(tog._raw.GetState) == "function" then
						ok, val = pcall(function() return tog._raw:GetState() end)
					end
					if ok and val == true then
						count = count + 1
					end
				end
			end
		end
		return count
	end

	function HomeRuntime:GetPing()
		local pingVal = 0
		pcall(function()
			local netStats = StatsService:FindFirstChild("Network")
			if netStats then
				local sItem = netStats:FindFirstChild("ServerStatsItem")
				if sItem then
					local dataPing = sItem:FindFirstChild("Data Ping")
					if dataPing and dataPing.GetValue then
						pingVal = math.floor(dataPing:GetValue() + 0.5)
					end
				end
			end
		end)

		if pingVal <= 0 then
			local lp = Players.LocalPlayer
			if lp and type(lp.GetNetworkPing) == "function" then
				pcall(function()
					pingVal = math.floor(lp:GetNetworkPing() * 1000 + 0.5)
				end)
			end
		end

		return math.max(pingVal, 0)
	end

	function HomeRuntime:GetFps()
		local okFps, fpsVal = pcall(function() return StatsService.Workspace.Heartbeat:GetValue() end)
		if okFps and type(fpsVal) == "number" and fpsVal > 0 then
			return math.round(fpsVal)
		end
		local okPhys, physVal = pcall(function() return workspace:GetRealPhysicsFPS() end)
		if okPhys and type(physVal) == "number" and physVal > 0 then
			return math.round(physVal)
		end
		return 60
	end

	function HomeRuntime:StartTicker()
		self._tickerGen = (self._tickerGen or 0) + 1
		local currentTickerGen = self._tickerGen

		-- Telemetry Background Loop (1-second tick, Zero-RenderStepped Overhead)
		task.spawn(function()
			while self._tickerGen == currentTickerGen and not Hub._destroyed do
				task.wait(1.0)
				if self._tickerGen ~= currentTickerGen or Hub._destroyed then break end

				if self._statusGrid then
					-- Session
					local elapsed = os.clock() - self._startTime
					self._statusGrid:Update("session", self:FormatSession(elapsed))

					-- Features On
					local activeCount = self:GetActiveFeaturesCount()
					self._statusGrid:Update("features", tostring(activeCount))

					-- Native Engine FPS (Zero Lua per-frame hook)
					local fpsNum = self:GetFps()
					self._statusGrid:Update("fps", tostring(fpsNum))

					-- Ping
					local pingNum = self:GetPing()
					self._statusGrid:Update("ping", tostring(pingNum) .. " ms")

					-- Players
					local curPlayers = #Players:GetPlayers()
					local maxPlayers = Players.MaxPlayers or 20
					self._statusGrid:Update("players", tostring(curPlayers) .. " / " .. tostring(maxPlayers))
				end
			end
		end)
	end

	-- Stats Card: Strictly opt-in for game-specific scripts via Hub:SetStats
	function HomeRuntime:SetStats(statsList)
		self._customStats = statsList
		if not self._statsGrid and self._homeTab and type(statsList) == "table" and #statsList > 0 then
			local StatsSec = self._homeTab:Section({
				Title = "Stats",
				Side = "Left",
				Icon = "bar-chart",
			})
			self._statsSec = StatsSec
			self._statsGrid = StatsSec:MetricGrid({
				Columns = 3,
				Items = statsList,
			})
		elseif self._statsGrid and type(statsList) == "table" then
			for _, item in ipairs(statsList) do
				local key = item.Key or item.Title or item.Label
				if key then
					self._statsGrid:Update(key, item.Value, item.Label or item.Title)
				end
			end
		end
	end

	function HomeRuntime:UpdateStat(key, value, label)
		if self._statsGrid then
			self._statsGrid:Update(key, value, label)
		end
	end

	-- Resolve History dynamically from parameters, global memory, or game disk
	function HomeRuntime:ResolveHistory(cfg)
		if type(self._customHistory) == "table" and #self._customHistory > 0 then
			return self._customHistory
		end
		if type(Hub.History) == "table" and #Hub.History > 0 then
			return Hub.History
		end
		if type(Hub.Changelog) == "table" and #Hub.Changelog > 0 then
			return Hub.Changelog
		end
		if cfg and type(cfg.History) == "table" and #cfg.History > 0 then
			return cfg.History
		end
		if cfg and type(cfg.Changelog) == "table" and #cfg.Changelog > 0 then
			return cfg.Changelog
		end
		if getgenv then
			local okG, gHistory = pcall(function() return getgenv().__SHENKY_HISTORY end)
			if okG and type(gHistory) == "table" and #gHistory > 0 then
				return gHistory
			end
		end

		-- Auto-detect from disk if isfile and readfile exist
		if isfile and readfile then
			local candidates = {}
			if cfg and cfg.Folder then
				table.insert(candidates, tostring(cfg.Folder) .. "/history.luau")
				table.insert(candidates, "games/" .. tostring(cfg.Folder) .. "/history.luau")
			end
			if cfg and (cfg.SubTitle or cfg.Subtitle) then
				local sub = tostring(cfg.SubTitle or cfg.Subtitle)
				table.insert(candidates, sub .. "/history.luau")
				table.insert(candidates, "games/" .. sub .. "/history.luau")
			end
			table.insert(candidates, "What If Disasters/history.luau")
			table.insert(candidates, "games/What If Disasters/history.luau")
			table.insert(candidates, "history.luau")

			for _, path in ipairs(candidates) do
				local okF, exists = pcall(isfile, path)
				if okF and exists then
					local okR, content = pcall(readfile, path)
					if okR and type(content) == "string" and #content > 0 then
						local okC, fn = pcall(loadstring, content)
						if okC and type(fn) == "function" then
							local okRun, res = pcall(fn)
							if okRun and type(res) == "table" and #res > 0 then
								return res
							end
						end
					end
				end
			end
		end

		return nil
	end

	function HomeRuntime:RenderHistorySection(historyList, side)
		if self._historySec or not self._homeTab or type(historyList) ~= "table" or #historyList == 0 then
			return
		end
		local targetSide = side or self._historySide or "Left"
		local HistorySec = self._homeTab:Section({
			Title = "Update log",
			Side = targetSide,
			Icon = "history",
		})
		self._historySec = HistorySec
		self._historyLog = HistorySec:History({
			Items = historyList,
		})
	end

	function HomeRuntime:SetHistory(historyList)
		self._customHistory = historyList
		if not self._historyLog and self._homeTab and type(historyList) == "table" and #historyList > 0 then
			self:RenderHistorySection(historyList)
		elseif self._historyLog and type(historyList) == "table" then
			self._historyLog:SetHistory(historyList)
		end
	end

	function Hub:SetStats(statsList)
		HomeRuntime:SetStats(statsList)
	end

	function Hub:UpdateStat(key, value, label)
		HomeRuntime:UpdateStat(key, value, label)
	end

	function Hub:SetHistory(historyList)
		HomeRuntime:SetHistory(historyList)
	end

	function Hub:SetChangelog(historyList)
		HomeRuntime:SetHistory(historyList)
	end

	-- ==== Hub:_CreateHomeTab(WindowWrapper, group, cfg) ====
	function Hub:_CreateHomeTab(WindowWrapper, group, cfg)
		local targetGroup = group or WindowWrapper:Category("Main")
		local HomeTab = targetGroup:Tab({
			Title = "Home",
			Icon = "home",
		})
		self.HomeTab = HomeTab
		HomeRuntime._homeTab = HomeTab

		-- If custom game stats were registered before CreateWindow, initialize Stats card now
		if type(self._customStats) == "table" and #self._customStats > 0 then
			HomeRuntime:SetStats(self._customStats)
		end

		-- ============================================================
		-- LEFT COLUMN: STATUS TELEMETRY (100% Universal)
		-- ============================================================

		local StatusSec = HomeTab:Section({
			Title = "Status",
			Side = "Left",
			Icon = "clock",
		})

		local initialStatus = {
			{ Key = "session", Label = "session", Value = HomeRuntime:FormatSession(os.clock() - HomeRuntime._startTime) },
			{ Key = "features", Label = "features on", Value = tostring(HomeRuntime:GetActiveFeaturesCount()) },
			{ Key = "fps", Label = "fps", Value = tostring(math.floor(HomeRuntime._lastFps + 0.5)) },
			{ Key = "ping", Label = "ping", Value = tostring(HomeRuntime:GetPing()) .. " ms" },
			{ Key = "players", Label = "players", Value = tostring(#Players:GetPlayers()) .. " / " .. tostring(Players.MaxPlayers or 20) },
			{ Key = "executes", Label = "total execute", Value = tostring(HomeRuntime:GetExecuteCount()) },
		}

		local statusGrid = StatusSec:MetricGrid({
			Columns = 3,
			Items = initialStatus,
		})
		HomeRuntime._statusGrid = statusGrid

		-- ============================================================
		-- LEFT COLUMN: UPDATE LOG (Dynamic / Sourced from history.luau)
		-- ============================================================
		local historySide = (cfg and (cfg.HistorySide or cfg.ChangelogSide)) or "Left"
		HomeRuntime._historySide = historySide
		local initialHistory = HomeRuntime:ResolveHistory(cfg)
		if initialHistory and #initialHistory > 0 then
			HomeRuntime:RenderHistorySection(initialHistory, historySide)
		end

		-- ============================================================
		-- RIGHT COLUMN: QUICK ACTIONS (100% Universal)
		-- ============================================================

		local ActionsSec = HomeTab:Section({
			Title = "Quick actions",
			Side = "Right",
			Icon = "zap",
		})

		-- Row 1: Copy Discord | Load last config
		ActionsSec:ButtonRow({
			{
				Title = "Copy Discord",
				Callback = function()
					pcall(function()
						if setclipboard then
							setclipboard(DISCORD_INVITE)
						end
					end)
					Hub:Notify("Discord", "Discord invite link copied to clipboard!", "link")
				end,
			},
			{
				Title = "Load last config",
				Callback = function()
					pcall(function()
						if Hub.ShenkyUI and Hub.ShenkyUI.LoadAutoLoadConfig then
							Hub.ShenkyUI:LoadAutoLoadConfig()
						end
					end)
					Hub:Notify("Config", "Loaded last config successfully", "file-text")
				end,
			},
		})

		-- Row 2: Rejoin | Server hop
		ActionsSec:ButtonRow({
			{
				Title = "Rejoin",
				Callback = function()
					if type(Hub.Rejoin) == "function" then
						Hub:Rejoin()
					else
						TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, Players.LocalPlayer)
					end
				end,
			},
			{
				Title = "Server hop",
				Callback = function()
					if type(Hub.ServerHop) == "function" then
						Hub:ServerHop()
					end
				end,
			},
		})

		-- Row 3: Anonymous mode toggle
		ActionsSec:Toggle({
			Title = "Anonymous mode",
			Desc = "Hides your profile and username",
			Default = false,
			_isInternalConfigToggle = true,
			Callback = function(enabled)
				if Hub.SetAnonymousMode then
					Hub:SetAnonymousMode(enabled)
				elseif WindowWrapper.Sidebar and WindowWrapper.Sidebar.SetAnonymousMode then
					WindowWrapper.Sidebar:SetAnonymousMode(enabled)
				end
				if enabled and not Hub._isBooting then
					Hub:Notify("Privacy", "Anonymous mode enabled", "eye-off")
				end
			end,
		})


		-- Start telemetry updates
		HomeRuntime:StartTicker()

		-- Clean up connection on close
		WindowWrapper:OnClose(function()
			if HomeRuntime._fpsConn then
				pcall(function() HomeRuntime._fpsConn:Disconnect() end)
				HomeRuntime._fpsConn = nil
			end
			HomeRuntime._tickerGen = HomeRuntime._tickerGen + 1
		end)

		return HomeTab
	end
end

end

-- Module: tabs/player
__modules["tabs/player"] = function()
-- tabs/player.luau
-- Universal Player Tab & PlayerRuntime (Ultra-Lightweight & Zero-Overhead Lazy Listeners)
-- Per-frame hooks (RenderStepped/Stepped) only attach when features are active, with part caching for noclip.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

return function(Hub)
-- ============================================================
-- ==== Player Runtime & Universal Player Tab ====
-- ============================================================

local PlayerRuntime = {
	_initialized = false,
	_conns = {},

	-- Lazy dynamic per-frame and event connections
	_physicsConn = nil,
	_noclipConn = nil,
	_jumpConn = nil,
	_promptShownConn = nil,
	_promptHoldConn = nil,
	_gravityConn = nil,
	_fovConn = nil,

	-- Cached character parts for zero-allocation noclip
	_cachedCharParts = nil,
	_charDescConn = nil,
	_charDescRemConn = nil,

	-- Movement states
	WalkSpeedEnabled = false,
	WalkSpeedValue = 16,
	DefaultWalkSpeed = 16,

	JumpPowerEnabled = false,
	JumpPowerValue = 50,
	DefaultJumpPower = 50,
	DefaultUseJumpPower = true,

	InfiniteJumpEnabled = false,

	GravityEnabled = false,
	GravityValue = 196.2,
	DefaultGravity = 196.2,

	-- Flight & Collision states
	FlyEnabled = false,
	FlySpeed = 50,
	FlyKey = nil,
	_flyBV = nil,
	_flyBG = nil,
	_flyToggleWrapper = nil,

	NoclipEnabled = false,
	NoclipKey = nil,
	_noclipToggleWrapper = nil,

	-- Interaction states
	InstantPromptsEnabled = false,
	_origPromptDurations = {},

	-- Camera states
	CameraZoomEnabled = false,
	MinZoom = 0.5,
	MaxZoom = 400,
	DefaultMinZoom = 0.5,
	DefaultMaxZoom = 400,

	CameraFovEnabled = false,
	FovValue = 70,
	DefaultFov = 70,
}

-- Cache character BaseParts into a flat array so Noclip never calls GetDescendants() per frame
function PlayerRuntime:_RefreshCharacterParts(char)
	char = char or (Players.LocalPlayer and Players.LocalPlayer.Character)
	if self._charDescConn then
		pcall(self._charDescConn.Disconnect, self._charDescConn)
		self._charDescConn = nil
	end
	if self._charDescRemConn then
		pcall(self._charDescRemConn.Disconnect, self._charDescRemConn)
		self._charDescRemConn = nil
	end

	if not char then
		self._cachedCharParts = nil
		return
	end

	local parts = {}
	for _, desc in ipairs(char:GetDescendants()) do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
		end
	end
	self._cachedCharParts = parts

	self._charDescConn = char.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") and self._cachedCharParts then
			table.insert(self._cachedCharParts, desc)
		end
	end)
	self._charDescRemConn = char.DescendantRemoving:Connect(function(desc)
		if desc:IsA("BasePart") and self._cachedCharParts then
			local idx = table.find(self._cachedCharParts, desc)
			if idx then
				table.remove(self._cachedCharParts, idx)
			end
		end
	end)
end

-- Dynamic RenderStepped Listener (Only runs when Fly, WalkSpeed, or JumpPower is ACTIVE)
function PlayerRuntime:_UpdatePhysicsListener()
	local active = self.FlyEnabled or self.WalkSpeedEnabled or self.JumpPowerEnabled
	if active and not self._physicsConn then
		self._physicsConn = RunService.RenderStepped:Connect(function()
			if self.FlyEnabled then
				self:ApplyFlyPhysics()
			end

			local lp = Players.LocalPlayer
			local char = lp and lp.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if not (hum and hum.Health > 0) then return end

			if self.WalkSpeedEnabled and hum.WalkSpeed ~= self.WalkSpeedValue then
				hum.WalkSpeed = self.WalkSpeedValue
			end
			if self.JumpPowerEnabled then
				if not hum.UseJumpPower then
					hum.UseJumpPower = true
				end
				if hum.JumpPower ~= self.JumpPowerValue then
					hum.JumpPower = self.JumpPowerValue
				end
			end
		end)
	elseif not active and self._physicsConn then
		pcall(self._physicsConn.Disconnect, self._physicsConn)
		self._physicsConn = nil
	end
end

-- Dynamic Stepped Listener (Zero table allocations per frame, flat loop over cached BaseParts)
function PlayerRuntime:_UpdateNoclipListener()
	if self.NoclipEnabled and not self._noclipConn then
		if not self._cachedCharParts then
			self:_RefreshCharacterParts()
		end
		self._noclipConn = RunService.Stepped:Connect(function()
			if not self.NoclipEnabled then return end
			local parts = self._cachedCharParts
			if parts then
				for i = 1, #parts do
					local part = parts[i]
					if part and part.Parent and part.CanCollide then
						part.CanCollide = false
					end
				end
			end
		end)
	elseif not self.NoclipEnabled and self._noclipConn then
		pcall(self._noclipConn.Disconnect, self._noclipConn)
		self._noclipConn = nil

		-- Restore collision on parts
		local parts = self._cachedCharParts
		if parts then
			for i = 1, #parts do
				local part = parts[i]
				if part and part.Parent and part.Name ~= "HumanoidRootPart" then
					pcall(function() part.CanCollide = true end)
				end
			end
		end
	end
end

-- Dynamic Infinite Jump Listener
function PlayerRuntime:_UpdateInfiniteJumpListener()
	if self.InfiniteJumpEnabled and not self._jumpConn then
		self._jumpConn = UserInputService.JumpRequest:Connect(function()
			if not self.InfiniteJumpEnabled then return end
			local lp = Players.LocalPlayer
			local char = lp and lp.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
			if hum and hrp and hum.Health > 0 then
				hum:ChangeState(Enum.HumanoidStateType.Jumping)
				local jp = self.JumpPowerEnabled and self.JumpPowerValue or (hum.JumpPower > 0 and hum.JumpPower or 50)
				hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, jp, hrp.AssemblyLinearVelocity.Z)
			end
		end)
	elseif not self.InfiniteJumpEnabled and self._jumpConn then
		pcall(self._jumpConn.Disconnect, self._jumpConn)
		self._jumpConn = nil
	end
end

-- Dynamic Prompt Listeners
function PlayerRuntime:_UpdatePromptListeners()
	if self.InstantPromptsEnabled and not self._promptShownConn then
		self._promptShownConn = ProximityPromptService.PromptShown:Connect(function(prompt)
			if self.InstantPromptsEnabled then
				self:PatchPrompt(prompt)
			end
		end)
		self._promptHoldConn = ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
			if self.InstantPromptsEnabled and type(fireproximityprompt) == "function" then
				pcall(fireproximityprompt, prompt)
			end
		end)
	elseif not self.InstantPromptsEnabled and self._promptShownConn then
		pcall(self._promptShownConn.Disconnect, self._promptShownConn)
		pcall(self._promptHoldConn.Disconnect, self._promptHoldConn)
		self._promptShownConn = nil
		self._promptHoldConn = nil
	end
end

-- Dynamic Gravity Listener
function PlayerRuntime:_UpdateGravityListener()
	if self.GravityEnabled and not self._gravityConn then
		self._gravityConn = workspace:GetPropertyChangedSignal("Gravity"):Connect(function()
			if self.GravityEnabled and workspace.Gravity ~= self.GravityValue then
				workspace.Gravity = self.GravityValue
			end
		end)
	elseif not self.GravityEnabled and self._gravityConn then
		pcall(self._gravityConn.Disconnect, self._gravityConn)
		self._gravityConn = nil
	end
end

-- Dynamic Camera FOV Listener
function PlayerRuntime:_UpdateFovListener()
	if self.CameraFovEnabled and not self._fovConn then
		local cam = workspace.CurrentCamera
		if cam then
			self._fovConn = cam:GetPropertyChangedSignal("FieldOfView"):Connect(function()
				if self.CameraFovEnabled and cam.FieldOfView ~= self.FovValue then
					cam.FieldOfView = self.FovValue
				end
			end)
		end
	elseif not self.CameraFovEnabled and self._fovConn then
		pcall(self._fovConn.Disconnect, self._fovConn)
		self._fovConn = nil
	end
end

function PlayerRuntime:Init()
	if self._initialized then return end
	self._initialized = true

	local lp = Players.LocalPlayer
	local function cacheDefaults(char)
		pcall(function()
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				if not self.WalkSpeedEnabled and hum.WalkSpeed > 0 then
					self.DefaultWalkSpeed = hum.WalkSpeed
				end
				if not self.JumpPowerEnabled and hum.JumpPower > 0 then
					self.DefaultJumpPower = hum.JumpPower
					self.DefaultUseJumpPower = hum.UseJumpPower
				end
			end
			if not self.GravityEnabled and workspace.Gravity > 0 then
				self.DefaultGravity = workspace.Gravity
			end
			if lp then
				if not self.CameraZoomEnabled then
					self.DefaultMinZoom = lp.CameraMinZoomDistance
					self.DefaultMaxZoom = lp.CameraMaxZoomDistance
				end
			end
			local cam = workspace.CurrentCamera
			if cam and not self.CameraFovEnabled and cam.FieldOfView > 0 then
				self.DefaultFov = cam.FieldOfView
			end
		end)
	end

	if lp then
		if lp.Character then
			cacheDefaults(lp.Character)
			self:_RefreshCharacterParts(lp.Character)
		end
		table.insert(self._conns, lp.CharacterAdded:Connect(function(char)
			local hum = char:WaitForChild("Humanoid", 5)
			task.wait(0.1)
			cacheDefaults(char)
			self:_RefreshCharacterParts(char)

			if self.WalkSpeedEnabled and hum then
				hum.WalkSpeed = self.WalkSpeedValue
			end
			if self.JumpPowerEnabled and hum then
				hum.UseJumpPower = true
				hum.JumpPower = self.JumpPowerValue
			end
			if self.FlyEnabled then
				task.defer(function()
					if self.FlyEnabled then
						self:ApplyFlyPhysics()
					end
				end)
			end
		end))
	end

	-- Keybind triggers for Noclip and Fly (Only listens for bound keys)
	table.insert(self._conns, UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

		if self.NoclipKey and self.NoclipKey ~= Enum.KeyCode.Unknown and input.KeyCode == self.NoclipKey then
			if self._noclipToggleWrapper then
				self._noclipToggleWrapper:Set(not self.NoclipEnabled)
			end
		elseif self.FlyKey and self.FlyKey ~= Enum.KeyCode.Unknown and input.KeyCode == self.FlyKey then
			if self._flyToggleWrapper then
				self._flyToggleWrapper:Set(not self.FlyEnabled)
			end
		end
	end))

	-- Camera Change listener
	table.insert(self._conns, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if self.CameraFovEnabled then
			pcall(function() self._fovConn:Disconnect() end)
			self._fovConn = nil
			self:_UpdateFovListener()
		end
	end))
end

function PlayerRuntime:ApplyFlyPhysics()
	local lp = Players.LocalPlayer
	local char = lp and lp.Character
	local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum and hum.Health > 0) then return end

	if not (self._flyBV and self._flyBV.Parent == hrp) then
		pcall(function()
			if self._flyBV then self._flyBV:Destroy() end
			if self._flyBG then self._flyBG:Destroy() end
		end)
		local bv = Instance.new("BodyVelocity")
		bv.Name = "ShenkyFlyBV"
		bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
		bv.Velocity = Vector3.zero
		bv.Parent = hrp
		self._flyBV = bv

		local bg = Instance.new("BodyGyro")
		bg.Name = "ShenkyFlyBG"
		bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
		bg.P = 9e4
		bg.CFrame = hrp.CFrame
		bg.Parent = hrp
		self._flyBG = bg
	end

	hum.PlatformStand = true

	local cam = workspace.CurrentCamera
	local camCF = cam and cam.CFrame or hrp.CFrame
	local moveDir = Vector3.zero
	local uis = game:GetService("UserInputService")
	local isTyping = uis:GetFocusedTextBox() ~= nil

	if not isTyping and uis:IsKeyDown(Enum.KeyCode.W) then
		moveDir = moveDir + camCF.LookVector
	end
	if not isTyping and uis:IsKeyDown(Enum.KeyCode.S) then
		moveDir = moveDir - camCF.LookVector
	end
	if not isTyping and uis:IsKeyDown(Enum.KeyCode.A) then
		moveDir = moveDir - camCF.RightVector
	end
	if not isTyping and uis:IsKeyDown(Enum.KeyCode.D) then
		moveDir = moveDir + camCF.RightVector
	end
	if not isTyping and uis:IsKeyDown(Enum.KeyCode.Space) then
		moveDir = moveDir + Vector3.new(0, 1, 0)
	end
	if not isTyping and (uis:IsKeyDown(Enum.KeyCode.LeftShift) or uis:IsKeyDown(Enum.KeyCode.LeftControl) or uis:IsKeyDown(Enum.KeyCode.Q)) then
		moveDir = moveDir - Vector3.new(0, 1, 0)
	end

	-- Mobile thumbstick / Gamepad fallback
	if moveDir.Magnitude == 0 and hum.MoveDirection.Magnitude > 0 then
		local flatRight = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z).Unit
		moveDir = (camCF.LookVector * math.clamp(-hum.MoveDirection.Z, -1, 1)) + (flatRight * hum.MoveDirection.X)
	end
	if hum.Jump then
		moveDir = moveDir + Vector3.new(0, 1, 0)
	end

	if moveDir.Magnitude > 0 then
		self._flyBV.Velocity = moveDir.Unit * self.FlySpeed
	else
		self._flyBV.Velocity = Vector3.zero
	end
	self._flyBG.CFrame = camCF
end

function PlayerRuntime:StopFly()
	if self._flyBV then
		pcall(function() self._flyBV:Destroy() end)
		self._flyBV = nil
	end
	if self._flyBG then
		pcall(function() self._flyBG:Destroy() end)
		self._flyBG = nil
	end
	local lp = Players.LocalPlayer
	local char = lp and lp.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
	if hum then
		hum.PlatformStand = false
	end
	if hrp then
		pcall(function()
			hrp.AssemblyLinearVelocity = Vector3.zero
		end)
	end
	self:_UpdatePhysicsListener()
end

function PlayerRuntime:PatchPrompt(prompt)
	if not prompt:IsA("ProximityPrompt") then return end
	if self._origPromptDurations[prompt] == nil then
		self._origPromptDurations[prompt] = prompt.HoldDuration
	end
	prompt.HoldDuration = 0
end

function PlayerRuntime:RestorePrompts()
	for prompt, dur in pairs(self._origPromptDurations) do
		if prompt and prompt.Parent then
			pcall(function() prompt.HoldDuration = dur end)
		end
	end
	table.clear(self._origPromptDurations)
end

function PlayerRuntime:ResetMovement()
	self.WalkSpeedEnabled = false
	self.JumpPowerEnabled = false
	self.InfiniteJumpEnabled = false
	self.GravityEnabled = false
	if self.FlyEnabled then
		self.FlyEnabled = false
		self:StopFly()
	end
	self.NoclipEnabled = false

	-- Sync UI switches visually to OFF
	if self._walkSpeedToggleWrapper then pcall(function() self._walkSpeedToggleWrapper:Set(false) end) end
	if self._jumpPowerToggleWrapper then pcall(function() self._jumpPowerToggleWrapper:Set(false) end) end
	if self._infiniteJumpToggleWrapper then pcall(function() self._infiniteJumpToggleWrapper:Set(false) end) end
	if self._gravityToggleWrapper then pcall(function() self._gravityToggleWrapper:Set(false) end) end
	if self._flyToggleWrapper then pcall(function() self._flyToggleWrapper:Set(false) end) end
	if self._noclipToggleWrapper then pcall(function() self._noclipToggleWrapper:Set(false) end) end

	local lp = Players.LocalPlayer
	local char = lp and lp.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = self.DefaultWalkSpeed or 16
		hum.UseJumpPower = self.DefaultUseJumpPower
		hum.JumpPower = self.DefaultJumpPower or 50
	end
	workspace.Gravity = self.DefaultGravity or 196.2
	self:_UpdatePhysicsListener()
	self:_UpdateNoclipListener()
	self:_UpdateInfiniteJumpListener()
	self:_UpdateGravityListener()
end

function PlayerRuntime:ResetCamera()
	self.CameraZoomEnabled = false
	self.CameraFovEnabled = false
	local lp = Players.LocalPlayer
	local cam = workspace.CurrentCamera
	if lp and self.DefaultMinZoom and self.DefaultMaxZoom then
		pcall(function()
			lp.CameraMinZoomDistance = self.DefaultMinZoom
			lp.CameraMaxZoomDistance = self.DefaultMaxZoom
		end)
	end
	if cam and self.DefaultFov then
		pcall(function()
			cam.FieldOfView = self.DefaultFov
		end)
	end
	if self._cameraZoomToggleWrapper then pcall(function() self._cameraZoomToggleWrapper:Set(false) end) end
	if self._cameraFovToggleWrapper then pcall(function() self._cameraFovToggleWrapper:Set(false) end) end
end

function PlayerRuntime:Destroy()
	for _, conn in ipairs(self._conns) do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)

	-- Disconnect all dynamic listeners
	if self._physicsConn then pcall(self._physicsConn.Disconnect, self._physicsConn); self._physicsConn = nil end
	if self._noclipConn then pcall(self._noclipConn.Disconnect, self._noclipConn); self._noclipConn = nil end
	if self._jumpConn then pcall(self._jumpConn.Disconnect, self._jumpConn); self._jumpConn = nil end
	if self._promptShownConn then pcall(self._promptShownConn.Disconnect, self._promptShownConn); self._promptShownConn = nil end
	if self._promptHoldConn then pcall(self._promptHoldConn.Disconnect, self._promptHoldConn); self._promptHoldConn = nil end
	if self._gravityConn then pcall(self._gravityConn.Disconnect, self._gravityConn); self._gravityConn = nil end
	if self._fovConn then pcall(self._fovConn.Disconnect, self._fovConn); self._fovConn = nil end
	if self._charDescConn then pcall(self._charDescConn.Disconnect, self._charDescConn); self._charDescConn = nil end
	if self._charDescRemConn then pcall(self._charDescRemConn.Disconnect, self._charDescRemConn); self._charDescRemConn = nil end
	self._cachedCharParts = nil

	self._initialized = false

	pcall(function() self:StopFly() end)
	local lp = Players.LocalPlayer
	local char = lp and lp.Character
	if char then
		for _, part in ipairs(char:GetDescendants()) do
			if part.Name == "ShenkyFlyBV" or part.Name == "ShenkyFlyBG" then
				pcall(part.Destroy, part)
			end
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			pcall(function() hum.PlatformStand = false end)
		end
	end

	if self.NoclipEnabled then
		self.NoclipEnabled = false
		if char then
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
					pcall(function() part.CanCollide = true end)
				end
			end
		end
	end

	if self.WalkSpeedEnabled and self.DefaultWalkSpeed then
		self.WalkSpeedEnabled = false
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then pcall(function() hum.WalkSpeed = self.DefaultWalkSpeed end) end
	end
	if self.JumpPowerEnabled and self.DefaultJumpPower then
		self.JumpPowerEnabled = false
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			pcall(function()
				if self.DefaultUseJumpPower ~= nil then
					hum.UseJumpPower = self.DefaultUseJumpPower
				end
				hum.JumpPower = self.DefaultJumpPower
			end)
		end
	end
	if self.GravityEnabled and self.DefaultGravity then
		self.GravityEnabled = false
		pcall(function() workspace.Gravity = self.DefaultGravity end)
	end
	if self.InstantPromptsEnabled then
		self.InstantPromptsEnabled = false
		pcall(function() self:RestorePrompts() end)
	end
	if self.CameraZoomEnabled or self.CameraFovEnabled then
		self.CameraZoomEnabled = false
		self.CameraFovEnabled = false
		pcall(function() self:ResetCamera() end)
	end
end

Hub.PlayerRuntime = PlayerRuntime

function Hub:DetectAntiCheat()
	local signatures = {
		"adonis",
		"anticheat",
		"anti_cheat",
		"nanite",
		"security",
		"movementguard",
		"speedcheck",
		"noclipcheck",
		"flycheck",
		"banservice",
	}

	-- 1. Scan ReplicatedFirst
	local rf = game:GetService("ReplicatedFirst")
	if rf then
		for _, child in ipairs(rf:GetChildren()) do
			local name = string.lower(child.Name)
			for _, sig in ipairs(signatures) do
				if string.find(name, sig, 1, true) then
					return true, "ReplicatedFirst." .. child.Name
				end
			end
		end
	end

	-- 2. Scan PlayerScripts
	local lp = Players.LocalPlayer
	local ps = lp and lp:FindFirstChild("PlayerScripts")
	if ps then
		for _, desc in ipairs(ps:GetDescendants()) do
			if desc:IsA("LocalScript") or desc:IsA("ModuleScript") then
				local name = string.lower(desc.Name)
				for _, sig in ipairs(signatures) do
					if string.find(name, sig, 1, true) then
						return true, "PlayerScripts." .. desc.Name
					end
				end
			end
		end
	end

	-- 3. Scan Character
	local char = lp and lp.Character
	if char then
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("LocalScript") or child:IsA("Script") then
				local name = string.lower(child.Name)
				for _, sig in ipairs(signatures) do
					if string.find(name, sig, 1, true) then
						return true, "Character." .. child.Name
					end
				end
			end
		end
	end

	return false, nil
end

function Hub:_CreatePlayerTab(WindowWrapper, group, mode)
	local MacWindow = self._MacWindow or self._Window or self._ShenkyWindow
	if not MacWindow then return end

	PlayerRuntime:Init()

	local targetGroup = group or WindowWrapper:TabGroup("Universal")
	local PlayerTab = targetGroup:Tab({
		Title = "Player",
		Icon = "user",
	})
	self.PlayerTab = PlayerTab

	local isSafeMode = (mode == "Safe")

	if not isSafeMode then
		-- Left Column: Movement
		local MovementSec = PlayerTab:Section({ Title = "Movement", Side = "Left" })

		PlayerRuntime._walkSpeedToggleWrapper = MovementSec:Toggle({
			Title = "Custom Walk Speed",
			Desc = "Modifies character walking speed",
			Default = false,
			Callback = function(state)
				PlayerRuntime.WalkSpeedEnabled = state
				PlayerRuntime:_UpdatePhysicsListener()
				if not state then
					local lp = Players.LocalPlayer
					local char = lp and lp.Character
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if hum then hum.WalkSpeed = PlayerRuntime.DefaultWalkSpeed or 16 end
				else
					local lp = Players.LocalPlayer
					local char = lp and lp.Character
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if hum then hum.WalkSpeed = PlayerRuntime.WalkSpeedValue end
				end
			end,
		})

		MovementSec:Slider({
			Title = "Walk Speed",
			Desc = "Walking speed value",
			Value = { Min = 16, Max = 250, Default = 16 },
			Step = 1,
			Callback = function(val)
				PlayerRuntime.WalkSpeedValue = tonumber(val) or 16
				if PlayerRuntime.WalkSpeedEnabled then
					local lp = Players.LocalPlayer
					local char = lp and lp.Character
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if hum then hum.WalkSpeed = PlayerRuntime.WalkSpeedValue end
				end
			end,
		})

		PlayerRuntime._jumpPowerToggleWrapper = MovementSec:Toggle({
			Title = "Custom Jump Power",
			Desc = "Modifies character jump power",
			Default = false,
			Callback = function(state)
				PlayerRuntime.JumpPowerEnabled = state
				PlayerRuntime:_UpdatePhysicsListener()
				local lp = Players.LocalPlayer
				local char = lp and lp.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hum then
					if state then
						hum.UseJumpPower = true
						hum.JumpPower = PlayerRuntime.JumpPowerValue
					else
						hum.UseJumpPower = PlayerRuntime.DefaultUseJumpPower
						hum.JumpPower = PlayerRuntime.DefaultJumpPower or 50
					end
				end
			end,
		})

		MovementSec:Slider({
			Title = "Jump Power",
			Desc = "Jump power value",
			Value = { Min = 50, Max = 350, Default = 50 },
			Step = 5,
			Callback = function(val)
				PlayerRuntime.JumpPowerValue = tonumber(val) or 50
				if PlayerRuntime.JumpPowerEnabled then
					local lp = Players.LocalPlayer
					local char = lp and lp.Character
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if hum then
						hum.UseJumpPower = true
						hum.JumpPower = PlayerRuntime.JumpPowerValue
					end
				end
			end,
		})

		PlayerRuntime._infiniteJumpToggleWrapper = MovementSec:Toggle({
			Title = "Infinite Jump",
			Desc = "Jump continuously in mid-air",
			Default = false,
			Callback = function(state)
				PlayerRuntime.InfiniteJumpEnabled = state
				PlayerRuntime:_UpdateInfiniteJumpListener()
			end,
		})

		PlayerRuntime._gravityToggleWrapper = MovementSec:Toggle({
			Title = "Custom Gravity",
			Desc = "Modifies world gravity",
			Default = false,
			Callback = function(state)
				PlayerRuntime.GravityEnabled = state
				PlayerRuntime:_UpdateGravityListener()
				if state then
					workspace.Gravity = PlayerRuntime.GravityValue
				else
					workspace.Gravity = PlayerRuntime.DefaultGravity or 196.2
				end
			end,
		})

		MovementSec:Slider({
			Title = "Gravity",
			Desc = "World gravity value",
			Value = { Min = 0, Max = 300, Default = 196 },
			Step = 2,
			Callback = function(val)
				PlayerRuntime.GravityValue = tonumber(val) or 196.2
				if PlayerRuntime.GravityEnabled then
					workspace.Gravity = PlayerRuntime.GravityValue
				end
			end,
		})
		MovementSec:Button({
			Title = "Reset Movement Now",
			Callback = function()
				PlayerRuntime:ResetMovement()
				self:Notify("Movement", "All movement settings restored to game defaults!", "rotate-cw")
			end,
		})
	else
		-- In Safe Mode: Security notice
		local SecuritySec = PlayerTab:Section({ Title = "Safety & Protection", Side = "Left" })
		SecuritySec:SubLabel({
			Text = string.format(
				'<font color="%s"><b>Safe Client Mode:</b></font> Movement cheats disabled (anti-cheat detected: %s)',
				self.Colors.Rose,
				tostring(self._detectedAntiCheat or "Active")
			),
		})
	end

	-- World Interaction (Left Column)
	local WorldSec = PlayerTab:Section({ Title = "World Interaction", Side = "Left" })

	WorldSec:Toggle({
		Title = "Instant Prompts",
		Desc = "Triggers proximity prompts instantly",
		Default = false,
		Callback = function(state)
			PlayerRuntime.InstantPromptsEnabled = state
			PlayerRuntime:_UpdatePromptListeners()
			if state then
				for _, obj in ipairs(workspace:GetDescendants()) do
					if obj:IsA("ProximityPrompt") then
						PlayerRuntime:PatchPrompt(obj)
					end
				end
			else
				PlayerRuntime:RestorePrompts()
			end
		end,
	})

	if not isSafeMode then
		-- Right Column: Flight & Noclip
		local FlightSec = PlayerTab:Section({ Title = "Flight & Noclip", Side = "Right" })

		local flyToggle = FlightSec:Toggle({
			Title = "Fly",
			Desc = "Fly in camera direction",
			Default = false,
			Callback = function(state)
				PlayerRuntime.FlyEnabled = state
				if state then
					PlayerRuntime:ApplyFlyPhysics()
				else
					PlayerRuntime:StopFly()
				end
				PlayerRuntime:_UpdatePhysicsListener()
			end,
		})
		PlayerRuntime._flyToggleWrapper = flyToggle

		FlightSec:Keybind({
			Title = "Fly Keybind",
			Default = Enum.KeyCode.Unknown,
			onBinded = function(bind)
				if typeof(bind) == "EnumItem" and bind.EnumType == Enum.KeyCode then
					PlayerRuntime.FlyKey = (bind ~= Enum.KeyCode.Unknown) and bind or nil
				end
			end,
		})

		FlightSec:Slider({
			Title = "Fly Speed",
			Desc = "Fly movement speed",
			Value = { Min = 10, Max = 250, Default = 50 },
			Step = 5,
			Callback = function(val)
				PlayerRuntime.FlySpeed = tonumber(val) or 50
			end,
		})

		local noclipToggle = FlightSec:Toggle({
			Title = "Noclip",
			Desc = "Walk through walls and objects",
			Default = false,
			Callback = function(state)
				PlayerRuntime.NoclipEnabled = state
				PlayerRuntime:_UpdateNoclipListener()
			end,
		})
		PlayerRuntime._noclipToggleWrapper = noclipToggle

		FlightSec:Keybind({
			Title = "Noclip Keybind",
			Default = Enum.KeyCode.Unknown,
			onBinded = function(bind)
				if typeof(bind) == "EnumItem" and bind.EnumType == Enum.KeyCode then
					PlayerRuntime.NoclipKey = (bind ~= Enum.KeyCode.Unknown) and bind or nil
				end
			end,
		})
	end

	-- Camera Settings (Right Column)
	local CameraSec = PlayerTab:Section({ Title = "Camera Settings", Side = "Right" })

	PlayerRuntime._cameraZoomToggleWrapper = CameraSec:Toggle({
		Title = "Custom Camera",
		Desc = "Unlocks camera zoom limits",
		Default = false,
		Callback = function(state)
			PlayerRuntime.CameraZoomEnabled = state
			local lp = Players.LocalPlayer
			if lp then
				if state then
					lp.CameraMinZoomDistance = PlayerRuntime.MinZoom
					lp.CameraMaxZoomDistance = PlayerRuntime.MaxZoom
				else
					lp.CameraMinZoomDistance = PlayerRuntime.DefaultMinZoom or 0.5
					lp.CameraMaxZoomDistance = PlayerRuntime.DefaultMaxZoom or 400
				end
			end
		end,
	})

	CameraSec:Slider({
		Title = "Min Zoom",
		Desc = "Min zoom distance",
		Value = { Min = 0.5, Max = 100, Default = 0.5 },
		Step = 0.5,
		Callback = function(val)
			PlayerRuntime.MinZoom = tonumber(val) or 0.5
			if PlayerRuntime.CameraZoomEnabled then
				local lp = Players.LocalPlayer
				if lp then lp.CameraMinZoomDistance = PlayerRuntime.MinZoom end
			end
		end,
	})

	CameraSec:Slider({
		Title = "Max Zoom",
		Desc = "Max zoom distance",
		Value = { Min = 10, Max = 2000, Default = 400 },
		Step = 10,
		Callback = function(val)
			PlayerRuntime.MaxZoom = tonumber(val) or 400
			if PlayerRuntime.CameraZoomEnabled then
				local lp = Players.LocalPlayer
				if lp then lp.CameraMaxZoomDistance = PlayerRuntime.MaxZoom end
			end
		end,
	})

	PlayerRuntime._cameraFovToggleWrapper = CameraSec:Toggle({
		Title = "Custom FOV",
		Desc = "Modifies field of view angle",
		Default = false,
		Callback = function(state)
			PlayerRuntime.CameraFovEnabled = state
			PlayerRuntime:_UpdateFovListener()
			local cam = workspace.CurrentCamera
			if cam then
				if state then
					cam.FieldOfView = PlayerRuntime.FovValue
				else
					cam.FieldOfView = PlayerRuntime.DefaultFov or 70
				end
			end
		end,
	})

	CameraSec:Slider({
		Title = "FOV Angle",
		Desc = "Field of view angle",
		Value = { Min = 30, Max = 120, Default = 70 },
		Step = 1,
		Callback = function(val)
			PlayerRuntime.FovValue = tonumber(val) or 70
			if PlayerRuntime.CameraFovEnabled then
				local cam = workspace.CurrentCamera
				if cam then cam.FieldOfView = PlayerRuntime.FovValue end
			end
		end,
	})

	CameraSec:Button({
		Title = "Reset Camera Now",
		Callback = function()
			PlayerRuntime:ResetCamera()
			self:Notify("Camera", "Camera has been reset to default", "rotate-cw")
		end,
	})

	return PlayerTab
end

-- ============================================================
-- ============================================================

	Hub.PlayerRuntime = PlayerRuntime
end

end

-- Module: tabs/render
__modules["tabs/render"] = function()
-- tabs/render.luau
-- Universal Render Tab & RenderRuntime

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local VirtualInputManager = game:GetService("VirtualInputManager")

return function(Hub)
-- ==== RenderRuntime (Visuals, Lighting & Performance) ====
-- ============================================================
local RenderRuntime = {
	FullBrightEnabled = false,
	NoFogEnabled = false,
	NoShadowsEnabled = false,
	NoBlurEnabled = false,
	NoEffectsEnabled = false,
	LowGraphicsEnabled = false,
	Disable3dRenderingEnabled = false,
	FpsLimiterEnabled = false,
	FpsLimitValue = 60,

	_initialized = false,
	_conns = {},
	_fullbrightConn = nil,
	_effectsConn = nil,
	_fogConn = nil,
	_fogAtmosphereConn = nil,
	_shadowConn = nil,
	_originalLighting = {},
	_disabledEffects = {},
	_originalMaterials = {},
	_originalCastShadows = {},
	_disabledParticles = {},
	_afkGui = nil,
}

function RenderRuntime:_UpdateFullBrightListener()
	if self.FullBrightEnabled and not self._fullbrightConn then
		local Lighting = game:GetService("Lighting")
		local isUpdating = false
		self._fullbrightConn = Lighting:GetPropertyChangedSignal("Ambient"):Connect(function()
			if isUpdating then return end
			if self.FullBrightEnabled then
				isUpdating = true
				pcall(function()
					Lighting.Ambient = Color3.fromRGB(255, 255, 255)
					Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
					Lighting.Brightness = 2
				end)
				isUpdating = false
			end
		end)
	elseif not self.FullBrightEnabled and self._fullbrightConn then
		pcall(self._fullbrightConn.Disconnect, self._fullbrightConn)
		self._fullbrightConn = nil
	end
end

function RenderRuntime:_UpdateEffectsListener()
	local shouldListen = self.NoBlurEnabled or self.NoEffectsEnabled
	if shouldListen and not self._effectsConn then
		local Lighting = game:GetService("Lighting")
		self._effectsConn = Lighting.DescendantAdded:Connect(function(child)
			if self.NoBlurEnabled and (child:IsA("BlurEffect") or child:IsA("DepthOfFieldEffect")) then
				if child.Enabled then
					self._disabledBlurEffects = self._disabledBlurEffects or {}
					self._disabledBlurEffects[child] = true
					pcall(function() child.Enabled = false end)
				end
			end
			if self.NoEffectsEnabled and (child:IsA("ColorCorrectionEffect") or child:IsA("BloomEffect") or child:IsA("SunRaysEffect")) then
				if child.Enabled then
					self._disabledOtherEffects = self._disabledOtherEffects or {}
					self._disabledOtherEffects[child] = true
					pcall(function() child.Enabled = false end)
				end
			end
		end)
	elseif not shouldListen and self._effectsConn then
		pcall(self._effectsConn.Disconnect, self._effectsConn)
		self._effectsConn = nil
	end
end

function RenderRuntime:Init()
	if self._initialized then return end
	self._initialized = true

	local Lighting = game:GetService("Lighting")
	self._originalLighting = {
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		GlobalShadows = Lighting.GlobalShadows,
	}

	self._originalAtmospheres = {}
	for _, v in ipairs(Lighting:GetDescendants()) do
		if v:IsA("Atmosphere") then
			self._originalAtmospheres[v] = {
				Density = v.Density,
				Offset = v.Offset,
				Haze = v.Haze,
				Glare = v.Glare,
			}
		end
	end
end

function RenderRuntime:SetFullBright(enabled)
	self.FullBrightEnabled = enabled
	self:_UpdateFullBrightListener()
	local Lighting = game:GetService("Lighting")
	if enabled then
		Lighting.Ambient = Color3.fromRGB(255, 255, 255)
		Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
		Lighting.Brightness = 2
	else
		Lighting.Ambient = self._originalLighting.Ambient or Color3.fromRGB(128, 128, 128)
		Lighting.OutdoorAmbient = self._originalLighting.OutdoorAmbient or Color3.fromRGB(128, 128, 128)
		Lighting.Brightness = self._originalLighting.Brightness or 1
	end
end

function RenderRuntime:_UpdateFogListener()
	local Lighting = game:GetService("Lighting")
	if self.NoFogEnabled then
		if not self._fogConn then
			self._fogConn = Lighting:GetPropertyChangedSignal("FogEnd"):Connect(function()
				if self.NoFogEnabled and Lighting.FogEnd < 9e8 then
					Lighting.FogEnd = 9e9
					Lighting.FogStart = 9e9
				end
			end)
		end
		if not self._fogAtmosphereConn then
			self._fogAtmosphereConn = Lighting.DescendantAdded:Connect(function(v)
				if self.NoFogEnabled and v:IsA("Atmosphere") then
					pcall(function() v.Density = 0 end)
				end
			end)
		end
	else
		if self._fogConn then
			pcall(self._fogConn.Disconnect, self._fogConn)
			self._fogConn = nil
		end
		if self._fogAtmosphereConn then
			pcall(self._fogAtmosphereConn.Disconnect, self._fogAtmosphereConn)
			self._fogAtmosphereConn = nil
		end
	end
end

function RenderRuntime:SetNoFog(enabled)
	self.NoFogEnabled = enabled
	self:_UpdateFogListener()
	local Lighting = game:GetService("Lighting")
	if enabled then
		Lighting.FogEnd = 9e9
		Lighting.FogStart = 9e9
		for _, v in ipairs(Lighting:GetDescendants()) do
			if v:IsA("Atmosphere") then
				pcall(function() v.Density = 0 end)
			end
		end
	else
		if self._originalLighting.FogEnd then
			Lighting.FogEnd = self._originalLighting.FogEnd
		end
		if self._originalLighting.FogStart then
			Lighting.FogStart = self._originalLighting.FogStart
		end
		for v, props in pairs(self._originalAtmospheres or {}) do
			if v and v.Parent then
				pcall(function()
					v.Density = props.Density or 0.3
					v.Offset = props.Offset or 0
					v.Haze = props.Haze or 0
					v.Glare = props.Glare or 0
				end)
			end
		end
	end
end

function RenderRuntime:_UpdateShadowListener()
	local Lighting = game:GetService("Lighting")
	if self.NoShadowsEnabled and not self._shadowConn then
		self._shadowConn = Lighting:GetPropertyChangedSignal("GlobalShadows"):Connect(function()
			if self.NoShadowsEnabled and Lighting.GlobalShadows ~= false then
				Lighting.GlobalShadows = false
			end
		end)
	elseif not self.NoShadowsEnabled and self._shadowConn then
		pcall(self._shadowConn.Disconnect, self._shadowConn)
		self._shadowConn = nil
	end
end

function RenderRuntime:SetNoShadows(enabled)
	self.NoShadowsEnabled = enabled
	self:_UpdateShadowListener()
	local Lighting = game:GetService("Lighting")
	if enabled then
		Lighting.GlobalShadows = false
	else
		Lighting.GlobalShadows = (self._originalLighting.GlobalShadows ~= false)
	end
end

function RenderRuntime:SetNoBlur(enabled)
	self.NoBlurEnabled = enabled
	self:_UpdateEffectsListener()
	local Lighting = game:GetService("Lighting")
	local cam = workspace.CurrentCamera
	if enabled then
		self._disabledBlurEffects = self._disabledBlurEffects or {}
		local function disable(parent)
			if not parent then return end
			for _, child in ipairs(parent:GetDescendants()) do
				if (child:IsA("BlurEffect") or child:IsA("DepthOfFieldEffect")) and child.Enabled then
					if not child:HasTag(".") and not child.Name:find("Shenky") then
						self._disabledBlurEffects[child] = true
						pcall(function() child.Enabled = false end)
					end
				end
			end
		end
		disable(Lighting)
		disable(cam)
	else
		if self._disabledBlurEffects then
			for child in pairs(self._disabledBlurEffects) do
				if child and child.Parent and not child:HasTag(".") and not child.Name:find("Shenky") then
					pcall(function() child.Enabled = true end)
				end
			end
			table.clear(self._disabledBlurEffects)
		end
	end
end

function RenderRuntime:SetNoEffects(enabled)
	self.NoEffectsEnabled = enabled
	self:_UpdateEffectsListener()
	local Lighting = game:GetService("Lighting")
	local cam = workspace.CurrentCamera
	if enabled then
		self._disabledOtherEffects = self._disabledOtherEffects or {}
		local function disable(parent)
			if not parent then return end
			for _, child in ipairs(parent:GetDescendants()) do
				if (child:IsA("ColorCorrectionEffect") or child:IsA("BloomEffect") or child:IsA("SunRaysEffect")) and child.Enabled then
					self._disabledOtherEffects[child] = true
					pcall(function() child.Enabled = false end)
				end
			end
		end
		disable(Lighting)
		disable(cam)
	else
		if self._disabledOtherEffects then
			for child in pairs(self._disabledOtherEffects) do
				if child and child.Parent then
					pcall(function() child.Enabled = true end)
				end
			end
			table.clear(self._disabledOtherEffects)
		end
	end
end

function RenderRuntime:ClearHighlights()
	local count = 0
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Highlight") and inst.Name ~= "ShenkyHighlight" then
			pcall(function()
				inst:Destroy()
				count = count + 1
			end)
		end
	end
	return count
end

function RenderRuntime:SetDisable3dRendering(enabled)
	self.Disable3dRenderingEnabled = enabled
	local RunService = game:GetService("RunService")
	pcall(function()
		RunService:Set3dRenderingEnabled(not enabled)
	end)

	if enabled then
		if not self._afkGui then
			local parent = (function()
				local okHui, h = pcall(gethui)
				if okHui and h and typeof(h) == "Instance" then return h end
				local okCg, cg = pcall(game.GetService, game, "CoreGui")
				if okCg and cg then
					local okP = pcall(function() return cg:GetChildren() end)
					if okP then return cg end
				end
				return Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
			end)()

			local gui = Instance.new("ScreenGui")
			gui.Name = "ShenkyGpuSaver"
			gui.DisplayOrder = 999999
			gui.ResetOnSpawn = false

			local bg = Instance.new("Frame")
			bg.Size = UDim2.fromScale(1, 1)
			bg.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
			bg.BorderSizePixel = 0
			bg.Parent = gui

			local titleLbl = Instance.new("TextLabel")
			titleLbl.Size = UDim2.new(1, 0, 0, 40)
			titleLbl.Position = UDim2.new(0, 0, 0.4, -30)
			titleLbl.BackgroundTransparency = 1
			titleLbl.TextColor3 = Color3.fromRGB(56, 189, 248)
			titleLbl.TextSize = 22
			titleLbl.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Heavy)
			titleLbl.Text = "Shenky Hub • AFK GPU Saver"
			titleLbl.Parent = bg

			local subLbl = Instance.new("TextLabel")
			subLbl.Size = UDim2.new(1, 0, 0, 50)
			subLbl.Position = UDim2.new(0, 0, 0.4, 15)
			subLbl.BackgroundTransparency = 1
			subLbl.TextColor3 = Color3.fromRGB(148, 163, 184)
			subLbl.TextSize = 14
			subLbl.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.SemiBold)
			subLbl.Text = "3D World Rendering is Disabled to minimize GPU heat & wattage.\nToggle off in the Render tab to restore normal view."
			subLbl.Parent = bg

			gui.Parent = parent
			self._afkGui = gui
		else
			self._afkGui.Enabled = true
		end
	else
		if self._afkGui then
			self._afkGui.Enabled = false
		end
	end
end

function RenderRuntime:ApplyFpsLimit()
	local setFps = (typeof(setfpscap) == "function" and setfpscap)
		or (typeof(set_fps_cap) == "function" and set_fps_cap)
		or (typeof(setfps) == "function" and setfps)
		or (typeof(syn) == "table" and typeof(syn.set_fps_cap) == "function" and syn.set_fps_cap)
	if not setFps then return false end
	if self.FpsLimiterEnabled then
		pcall(setFps, tonumber(self.FpsLimitValue) or 60)
	else
		pcall(setFps, 0)
	end
	return true
end

function RenderRuntime:UncapFps()
	local setFps = (typeof(setfpscap) == "function" and setfpscap)
		or (typeof(set_fps_cap) == "function" and set_fps_cap)
		or (typeof(setfps) == "function" and setfps)
		or (typeof(syn) == "table" and typeof(syn.set_fps_cap) == "function" and syn.set_fps_cap)
	if not setFps then return false end
	pcall(setFps, 999)
	return true
end

function RenderRuntime:SetLowGraphics(enabled)
	self.LowGraphicsEnabled = enabled
	if enabled then
		for _, v in ipairs(workspace:GetDescendants()) do
			if v:IsA("BasePart") and not v:IsA("MeshPart") then
				if self._originalMaterials[v] == nil then
					self._originalMaterials[v] = v.Material
				end
				if self._originalCastShadows[v] == nil then
					self._originalCastShadows[v] = v.CastShadow
				end
				v.Material = Enum.Material.SmoothPlastic
				v.CastShadow = false
			elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") then
				if v.Enabled then
					self._disabledParticles[v] = true
					v.Enabled = false
				end
			end
		end
	else
		for part, mat in pairs(self._originalMaterials) do
			if part and part.Parent then
				pcall(function() part.Material = mat end)
			end
		end
		self._originalMaterials = {}
		for part, cast in pairs(self._originalCastShadows) do
			if part and part.Parent then
				pcall(function() part.CastShadow = cast end)
			end
		end
		self._originalCastShadows = {}
		for emitter in pairs(self._disabledParticles) do
			if emitter and emitter.Parent then
				pcall(function() emitter.Enabled = true end)
			end
		end
		self._disabledParticles = {}
	end
end

function RenderRuntime:Destroy()
	if self._fullbrightConn then pcall(self._fullbrightConn.Disconnect, self._fullbrightConn); self._fullbrightConn = nil end
	if self._effectsConn then pcall(self._effectsConn.Disconnect, self._effectsConn); self._effectsConn = nil end
	for _, conn in ipairs(self._conns) do
		pcall(function() conn:Disconnect() end)
	end
	self._conns = {}

	pcall(function()
		local RunService = game:GetService("RunService")
		RunService:Set3dRenderingEnabled(true)
	end)
	if self._afkGui then
		pcall(function() self._afkGui:Destroy() end)
		self._afkGui = nil
	end

	if self.FullBrightEnabled then self:SetFullBright(false) end
	if self.NoFogEnabled then self:SetNoFog(false) end
	if self.NoShadowsEnabled then self:SetNoShadows(false) end
	if self.NoBlurEnabled then self:SetNoBlur(false) end
	if self.NoEffectsEnabled then self:SetNoEffects(false) end
	if self.LowGraphicsEnabled then self:SetLowGraphics(false) end

	if self._fullbrightConn then pcall(self._fullbrightConn.Disconnect, self._fullbrightConn); self._fullbrightConn = nil end
	if self._effectsConn then pcall(self._effectsConn.Disconnect, self._effectsConn); self._effectsConn = nil end
	if self._fogConn then pcall(self._fogConn.Disconnect, self._fogConn); self._fogConn = nil end
	if self._fogAtmosphereConn then pcall(self._fogAtmosphereConn.Disconnect, self._fogAtmosphereConn); self._fogAtmosphereConn = nil end
	if self._shadowConn then pcall(self._shadowConn.Disconnect, self._shadowConn); self._shadowConn = nil end

	local setFps = (typeof(setfpscap) == "function" and setfpscap)
		or (typeof(set_fps_cap) == "function" and set_fps_cap)
		or (typeof(setfps) == "function" and setfps)
		or (typeof(syn) == "table" and typeof(syn.set_fps_cap) == "function" and syn.set_fps_cap)
	if setFps then pcall(setFps, 0) end

	-- Purge sisa DepthOfField dan efek blur kamera bawaan library eksternal
	pcall(function()
		local okLight, Lighting = pcall(game.GetService, game, "Lighting")
		if okLight and Lighting then
			for _, v in ipairs(Lighting:GetChildren()) do
				if v:IsA("DepthOfFieldEffect") and (v:HasTag(".") or v.NearIntensity == 1) then
					pcall(function() v.Enabled = false; v:Destroy() end)
				end
			end
		end
		local cam = workspace.CurrentCamera
		if cam then
			for _, v in ipairs(cam:GetChildren()) do
				if v:IsA("DepthOfFieldEffect") or (v:IsA("BasePart") and v.Material == Enum.Material.Glass) then
					pcall(function() v:Destroy() end)
				end
			end
		end
	end)

	self._initialized = false
end

Hub.RenderRuntime = RenderRuntime


-- ==== Hub:_CreateRenderTab(WindowWrapper, group) ====
function Hub:_CreateRenderTab(WindowWrapper, group)
	local MacWindow = self._MacWindow or self._Window or self._ShenkyWindow
	if not MacWindow then return end

	RenderRuntime:Init()

	local targetGroup = group or WindowWrapper:TabGroup("Universal")
	local RenderTab = targetGroup:Tab({
		Title = "Render",
		Icon = "sun",
	})
	self.RenderTab = RenderTab

	-- Left Column: Lighting & Visuals
	local VisualSec = RenderTab:Section({ Title = "Lighting & Visuals", Side = "Left" })

	VisualSec:Toggle({
		Title = "Full Bright",
		Desc = "Brightens dark maps and night",
		Default = false,
		Callback = function(state)
			RenderRuntime:SetFullBright(state)
			-- Silent toggle to avoid startup toast spam
		end,
	})

	VisualSec:Toggle({
		Title = "No Fog",
		Desc = "Removes atmospheric fog",
		Default = false,
		Callback = function(state)
			RenderRuntime:SetNoFog(state)
			-- Silent toggle to avoid startup toast spam
		end,
	})

	VisualSec:Toggle({
		Title = "No Shadows",
		Desc = "Disables dynamic shadows",
		Default = false,
		Callback = function(state)
			RenderRuntime:SetNoShadows(state)
		end,
	})

	VisualSec:Toggle({
		Title = "No Blur",
		Desc = "Removes blur and depth of field",
		Default = false,
		Callback = function(state)
			RenderRuntime:SetNoBlur(state)
		end,
	})

	VisualSec:Toggle({
		Title = "No Screen Effects",
		Desc = "Removes bloom and sun rays",
		Default = false,
		Callback = function(state)
			RenderRuntime:SetNoEffects(state)
		end,
	})

	VisualSec:Button({
		Title = "Clear All Highlights",
		Callback = function()
			local count = RenderRuntime:ClearHighlights()
			self:Notify("Visuals", string.format("Cleared %d world highlights", count), "trash")
		end,
	})

	-- Right Column: Performance & FPS
	local PerfSec = RenderTab:Section({ Title = "Performance & FPS", Side = "Right" })

	PerfSec:Toggle({
		Title = "Disable 3D Rendering",
		Desc = "AFK mode: cuts GPU load by ~90%",
		Default = false,
		_isInternalConfigToggle = true,
		Callback = function(state)
			RenderRuntime:SetDisable3dRendering(state)
			if not self._isBooting then
				self:Notify("GPU Saver", state and "3D Rendering paused (Saving GPU)" or "3D Rendering resumed", "monitor")
			end
		end,
	})

	PerfSec:Toggle({
		Title = "Low Graphics Mode",
		Desc = "Boosts FPS on low-end devices",
		Default = false,
		_isInternalConfigToggle = true,
		Callback = function(state)
			RenderRuntime:SetLowGraphics(state)
			if not self._isBooting then
				self:Notify("Graphics", state and "Low graphics mode active" or "Restored original materials", "layers")
			end
		end,
	})

	PerfSec:Toggle({
		Title = "FPS Limiter",
		Desc = "Sets custom frame rate cap",
		Default = false,
		Callback = function(state)
			RenderRuntime.FpsLimiterEnabled = state
			RenderRuntime:ApplyFpsLimit()
		end,
	})

	PerfSec:Slider({
		Title = "FPS Limit",
		Desc = "Frame rate limit value",
		Value = {
			Min = 10,
			Max = 240,
			Default = 60,
		},
		Step = 5,
		Callback = function(val)
			RenderRuntime.FpsLimitValue = val
			if RenderRuntime.FpsLimiterEnabled then
				RenderRuntime:ApplyFpsLimit()
			end
		end,
	})

	PerfSec:Button({
		Title = "Unlock FPS Now",
		Callback = function()
			local ok = RenderRuntime:UncapFps()
			if ok then
				self:Notify("FPS Cap", "Frame rate unlocked to maximum!", "zap")
			else
				self:Notify("FPS Cap", "setfpscap is not supported by your executor.", "alert-triangle")
			end
		end,
	})

	return RenderTab
end


	Hub.RenderRuntime = RenderRuntime
end

end

-- Module: tabs/server
__modules["tabs/server"] = function()
-- tabs/server.luau
-- Universal Server Tab & ServerRuntime

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")

return function(Hub)
-- ==== Server Runtime & Universal Server Tab ====
-- ============================================================

local ServerRuntime = {
	_initialized = false,
	_conns = {},
	_reconnectConns = {},
	AutoReconnectEnabled = false,
	_reconnectPending = false,
}

Hub._ServerRuntime = ServerRuntime
function Hub:Rejoin()
	return ServerRuntime:Rejoin()
end
function Hub:ServerHop()
	return ServerRuntime:ServerHop()
end

function ServerRuntime:_TriggerReconnect()
	if not self.AutoReconnectEnabled or self._reconnectPending then return end
	self._reconnectPending = true
	local TeleportService = game:GetService("TeleportService")
	task.spawn(function()
		task.wait(2)
		pcall(function()
			if #Players:GetPlayers() <= 1 then
				TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
			else
				TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, Players.LocalPlayer)
			end
		end)
		task.wait(5)
		pcall(function()
			TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
		end)
		self._reconnectPending = false
	end)
end

function ServerRuntime:_UpdateReconnectListeners()
	if self.AutoReconnectEnabled and #self._reconnectConns == 0 then
		local GuiService = game:GetService("GuiService")
		table.insert(self._reconnectConns, GuiService.ErrorMessageChanged:Connect(function(msg)
			if msg and msg ~= "" and self.AutoReconnectEnabled then
				self:_TriggerReconnect()
			end
		end))

		pcall(function()
			local coreGui = game:GetService("CoreGui")
			local promptGui = coreGui:FindFirstChild("RobloxPromptGui")
			if promptGui then
				local overlay = promptGui:FindFirstChild("promptOverlay")
				if overlay then
					for _, child in ipairs(overlay:GetChildren()) do
						if child.Name == "ErrorPrompt" or string.find(child.Name, "Prompt") then
							self:_TriggerReconnect()
							break
						end
					end
					table.insert(self._reconnectConns, overlay.ChildAdded:Connect(function(child)
						if self.AutoReconnectEnabled and (child.Name == "ErrorPrompt" or string.find(child.Name, "Prompt")) then
							self:_TriggerReconnect()
						end
					end))
				end
			end
		end)
	elseif not self.AutoReconnectEnabled and #self._reconnectConns > 0 then
		for _, conn in ipairs(self._reconnectConns) do
			pcall(function() conn:Disconnect() end)
		end
		table.clear(self._reconnectConns)
	end
end

function ServerRuntime:Init()
	if self._initialized then return end
	self._initialized = true
end

function ServerRuntime:Rejoin()
	local TeleportService = game:GetService("TeleportService")
	local placeId = game.PlaceId
	local jobId = game.JobId
	local lp = Players.LocalPlayer

	Hub:Notify("Rejoin", "Reconnecting to server...", "refresh")
	task.defer(function()
		local ok = pcall(function()
			if jobId and jobId ~= "" then
				TeleportService:TeleportToPlaceInstance(placeId, jobId, lp)
			else
				TeleportService:Teleport(placeId, lp)
			end
		end)
		if not ok then
			pcall(function()
				TeleportService:Teleport(placeId, lp)
			end)
		end
	end)
end

function ServerRuntime:HopToLowServer()
	local TeleportService = game:GetService("TeleportService")
	local HttpService = game:GetService("HttpService")
	local lp = Players.LocalPlayer
	local placeId = game.PlaceId
	local jobId = game.JobId

	local httpReq = (type(request) == "function" and request)
		or (type(http_request) == "function" and http_request)
		or (type(syn) == "table" and type(syn.request) == "function" and syn.request)
		or nil

	local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100", tostring(placeId))

	Hub:Notify("Server Hop", "Searching for quiet / low-player server...", "search")

	task.spawn(function()
		local body = nil
		if httpReq then
			local ok, res = pcall(function() return httpReq({ Url = url, Method = "GET" }) end)
			if ok and type(res) == "table" and (res.StatusCode == 200 or res.Status == 200) then
				body = res.Body or res.body
			end
		end
		if not body and typeof(game.HttpGet) == "function" then
			pcall(function() body = game:HttpGet(url) end)
		end

		if not body or type(body) ~= "string" then
			Hub:Notify("Server Hop", "Failed to retrieve public server list.", "alert-triangle")
			return
		end

		local okDec, data = pcall(HttpService.JSONDecode, HttpService, body)
		if not okDec or type(data) ~= "table" or type(data.data) ~= "table" then
			Hub:Notify("Server Hop", "Failed to decode server list.", "alert-triangle")
			return
		end

		local candidates = {}
		for _, srv in ipairs(data.data) do
			if type(srv) == "table" and srv.id and tostring(srv.id) ~= tostring(jobId) then
				local playing = tonumber(srv.playing) or 0
				local maxP = tonumber(srv.maxPlayers) or 1
				if playing >= 1 and playing < maxP then
					table.insert(candidates, srv)
				end
			end
		end

		if #candidates == 0 then
			Hub:Notify("Server Hop", "No low-population servers found.", "info")
			return
		end

		table.sort(candidates, function(a, b)
			return (tonumber(a.playing) or 0) < (tonumber(b.playing) or 0)
		end)

		local target = candidates[1]
		Hub:Notify("Server Hop", string.format("Found server with %d players! Teleporting...", target.playing), "network")
		task.wait(0.5)
		local okTp = pcall(function()
			TeleportService:TeleportToPlaceInstance(placeId, target.id, lp)
		end)
		if not okTp then
			Hub:Notify("Server Hop", "Teleport failed, trying random...", "alert-triangle")
			pcall(function()
				TeleportService:Teleport(placeId, lp)
			end)
		end
	end)
end

function ServerRuntime:ServerHop()
	local TeleportService = game:GetService("TeleportService")
	local HttpService = game:GetService("HttpService")
	local placeId = game.PlaceId
	local currentJobId = game.JobId
	local lp = Players.LocalPlayer

	Hub:Notify("Server Hop", "Searching for available servers...", "route")

	task.spawn(function()
		local cursor = ""
		local targetServer = nil
		local apiUrl = "https://games.roblox.com/v1/games/" .. tostring(placeId) .. "/servers/Public?sortOrder=Desc&limit=100"

		local httpFunc = (type(request) == "function" and request)
			or (type(http_request) == "function" and http_request)
			or (type(syn) == "table" and type(syn.request) == "function" and syn.request)

		for _ = 1, 3 do
			local url = apiUrl .. (cursor ~= "" and ("&cursor=" .. cursor) or "")
			local rawData = nil

			if httpFunc then
				local ok, res = pcall(httpFunc, { Url = url, Method = "GET" })
				if ok and type(res) == "table" and res.StatusCode == 200 then
					rawData = res.Body or res.body
			end
			end
			if not rawData then
				local okGet, resGet = pcall(game.HttpGet, game, url)
				if okGet and type(resGet) == "string" and #resGet > 0 then
					rawData = resGet
				end
			end

			if rawData then
				local okDec, data = pcall(HttpService.JSONDecode, HttpService, rawData)
				if okDec and type(data) == "table" and type(data.data) == "table" then
					for _, srv in ipairs(data.data) do
						local sId = tostring(srv.id or "")
						local playing = tonumber(srv.playing) or 0
						local maxPlayers = tonumber(srv.maxPlayers) or 0
						if sId ~= currentJobId and playing > 0 and playing < maxPlayers then
							targetServer = sId
							break
						end
					end
					cursor = tostring(data.nextPageCursor or "")
				end
			end

			if targetServer or cursor == "" or cursor == "nil" then
				break
			end
		end

		if targetServer then
			Hub:Notify("Server Hop", "Found server! Teleporting...", "sparkles")
			local okTp = pcall(function()
				TeleportService:TeleportToPlaceInstance(placeId, targetServer, lp)
			end)
			if not okTp then
				Hub:Notify("Server Hop", "Teleport failed, trying random...", "alert-triangle")
				TeleportService:Teleport(placeId, lp)
			end
		else
			Hub:Notify("Server Hop", "No specific server found, joining random...", "route")
			pcall(function()
				TeleportService:Teleport(placeId, lp)
			end)
		end
	end)
end

function ServerRuntime:Destroy()
	if Hub and Hub._antiAfkConn then
		pcall(function() Hub._antiAfkConn:Disconnect() end)
		Hub._antiAfkConn = nil
	end
	for _, conn in ipairs(self._reconnectConns) do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._reconnectConns)
	for _, conn in ipairs(self._conns) do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	self._initialized = false
	self.AutoReconnectEnabled = false
	self._reconnectPending = false
end

Hub.ServerRuntime = ServerRuntime


function Hub:_CreateServerTab(WindowWrapper, group)
	local MacWindow = self._MacWindow or self._Window or self._ShenkyWindow
	if not MacWindow then return end

	ServerRuntime:Init()

	local targetGroup = group or WindowWrapper:TabGroup("Universal")
	local ServerTab = targetGroup:Tab({
		Title = "Server",
		Icon = "server",
	})
	self.ServerTab = ServerTab

	-- Left Column: Connection & Protection
	local ConnectionSec = ServerTab:Section({ Title = "Connection & Protection", Side = "Left" })

	ConnectionSec:Toggle({
		Title = "Anti-AFK",
		Desc = "Prevents 20-minute idle kick",
		Default = self.Config.AntiAFK ~= false,
		Value = self.Config.AntiAFK ~= false,
		_isInternalConfigToggle = true,
		Callback = function(value)
			local changed = (self.Config.AntiAFK ~= value)
			self.Config.AntiAFK = value
			if self.SaveUniversalConfig then self:SaveUniversalConfig() end
			if self._antiAfkConn then
				pcall(function() self._antiAfkConn:Disconnect() end)
				self._antiAfkConn = nil
			end
			if value then
				local function performPulse()
					pcall(function()
						local vim = game:GetService("VirtualInputManager")
						vim:SendMouseButtonEvent(0, 0, 0, true, game, 0)
						task.wait(0.02)
						vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
					end)
					pcall(function()
						local vu = game:GetService("VirtualUser")
						vu:CaptureController()
						vu:ClickButton2(Vector2.zero)
					end)
				end
				performPulse()
				local lp = Players.LocalPlayer
				if lp then
					self._antiAfkConn = lp.Idled:Connect(function()
						if self.Config.AntiAFK then
							performPulse()
						end
					end)
				end
			end
			if changed and not self._isBooting then
				self:Notify("Anti-AFK", value and "Enabled" or "Disabled", value and "shield-check" or "shield-off")
			end
		end,
	})

	ConnectionSec:Toggle({
		Title = "Auto Reconnect",
		Desc = "Rejoins automatically on disconnect",
		Default = false,
		_isInternalConfigToggle = true,
		Callback = function(state)
			ServerRuntime.AutoReconnectEnabled = state
			ServerRuntime:_UpdateReconnectListeners()
		end,
	})

	ConnectionSec:Button({
		Title = "Rejoin Server Now",
		Callback = function()
			ServerRuntime:Rejoin()
		end,
	})

	ConnectionSec:Button({
		Title = "Server Hop Now",
		Callback = function()
			ServerRuntime:ServerHop()
		end,
	})

	ConnectionSec:Button({
		Title = "Hop to Low Server",
		Callback = function()
			ServerRuntime:HopToLowServer()
		end,
	})

	-- Right Column: Server Clipboard & Utilities
	local UtilitySec = ServerTab:Section({ Title = "Server Clipboard & Utilities", Side = "Right" })

	local function copyToClipboard(text, notifTitle, notifDesc, icon)
		local clipFunc = (type(setclipboard) == "function" and setclipboard)
			or (type(toclipboard) == "function" and toclipboard)
		if clipFunc then
			pcall(clipFunc, tostring(text or ""))
			self:Notify(notifTitle, notifDesc, icon or "copy")
		else
			self:Notify(notifTitle, tostring(text or ""), "info")
		end
	end

	UtilitySec:Button({
		Title = "Copy Server ID",
		Callback = function()
			local jId = tostring(game.JobId or "")
			copyToClipboard(jId, "Server ID", "Copied Job ID to clipboard!", "copy")
		end,
	})

	UtilitySec:Button({
		Title = "Copy Server Invite",
		Callback = function()
			local placeId = tostring(game.PlaceId or "")
			local jobId = tostring(game.JobId or "")
			local inviteUrl = string.format("https://www.roblox.com/games/start?placeId=%s&gameInstanceId=%s", placeId, jobId)
			copyToClipboard(inviteUrl, "Server Invite", "Copied 1-click launch link!", "link")
		end,
	})

	UtilitySec:Button({
		Title = "Copy Place Link",
		Callback = function()
			local placeId = tostring(game.PlaceId or "")
			local placeUrl = string.format("https://www.roblox.com/games/%s", placeId)
			copyToClipboard(placeUrl, "Place Link", "Copied Roblox experience link!", "globe")
		end,
	})


	return ServerTab
end


	Hub.ServerRuntime = ServerRuntime
end

end

-- Module: tabs/config
__modules["tabs/config"] = function()
-- tabs/config.luau
-- Universal Configuration Tab

return function(Hub)
-- ==== Tab Config universal (2 Kolom: Configuration di Kiri + Pengaturan Universal di Kanan) ====
function Hub:_CreateConfigTab(WindowWrapper, group)
	local MacWindow = self._MacWindow or self._Window or self._ShenkyWindow
	if not MacWindow then return end

	local ConfigGroup = group or WindowWrapper:TabGroup("Config")
	local ConfigTab = ConfigGroup:Tab({
		Title = "Config",
		Icon = "settings",
	})
	self.ConfigTab = ConfigTab

	-- Kolom Kiri: Built-in Config Manager Shenky UI
	pcall(function()
		ConfigTab._raw:InsertConfigSection("Left")
	end)

	-- Kolom Kanan: Universal Settings
	local RightSec = ConfigTab:Section({ Title = "Universal Settings", Side = "Right" })

	RightSec:Slider({
		Title = "UI Scale",
		Value = {
			Min = 0,
			Max = 100,
			Default = math.clamp(tonumber(self.Config.Scale) or 75, 0, 100),
		},
		Suffix = "%",
		Callback = function(val)
			local percent = math.clamp(tonumber(val) or 75, 0, 100)
			self.Config.Scale = percent
			local safePercent = math.clamp(percent, 25, 100)
			local sc = safePercent / 75
			pcall(function()
				MacWindow:SetScale(sc)
			end)
			if self.SaveUniversalConfig then self:SaveUniversalConfig() end
		end,
	})

	RightSec:Keybind({
		Title = "Custom Shortcut",
		Desc = "Shortcut keyboard untuk buka/tutup GUI (R-Ctrl / L-Ctrl)",
		Default = self.Config.ToggleKey or Enum.KeyCode.RightControl,
		Value = self.Config.ToggleKey or Enum.KeyCode.RightControl,
		onBinded = function(bind)
			if typeof(bind) == "EnumItem" and bind.EnumType == Enum.KeyCode then
				local changed = (self.Config.ToggleKey ~= bind)
				self.Config.ToggleKey = bind
				if self.SaveUniversalConfig then self:SaveUniversalConfig() end
				if changed then
					self:Notify("GUI Shortcut", "Changed to " .. tostring(bind.Name), "settings")
				end
			end
		end,
	})

	local initMobile = false
	RightSec:Toggle({
		Title = "Mobile Toggle Button",
		Value = self.Config.MobileToggle ~= false,
		_isInternalConfigToggle = true,
		Callback = function(value)
			local changed = (self.Config.MobileToggle ~= value)
			self.Config.MobileToggle = value
			if self.SaveUniversalConfig then self:SaveUniversalConfig() end
			if self._mobileToggleGui then
				self._mobileToggleGui.Enabled = value
			elseif value then
				self:_CreateMobileToggle(WindowWrapper, {})
			end
			if changed and initMobile and not self._isBooting then
				self:Notify(
					"Mobile Toggle",
					value and "Button visible" or "Button hidden",
					value and "eye" or "eye-off"
				)
			end
			initMobile = true
		end,
	})

	RightSec:Toggle({
		Title = "Hide GUI on Execute",
		Desc = "Mulai GUI dalam kondisi tertutup saat script di-execute",
		Default = self.Config.HideOnExecute == true,
		Value = self.Config.HideOnExecute == true,
		_isInternalConfigToggle = true,
		Callback = function(value)
			local changed = (self.Config.HideOnExecute ~= value)
			self.Config.HideOnExecute = value
			if self.SaveUniversalConfig then self:SaveUniversalConfig() end
			if changed and not self._isBooting then
				self:Notify(
					"Hide on Execute",
					value and "GUI will start hidden on next execute" or "GUI will open normally on execute",
					value and "eye-off" or "eye"
				)
			end
		end,
	})

	RightSec:Button({
		Title = "Stop All Features",
		Callback = function()
			self:StopAll()
			self:Notify("Stop All", "All automated features stopped.", "octagon")
		end,
	})

	RightSec:Button({
		Title = "Destroy GUI",
		Callback = function()
			self:Destroy()
		end,
	})

	return ConfigTab
end


end

end

-- Entry Point: init
return (function()
-- init.luau
-- Entry point for Shenky Hub Core Engine

local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")

local Hub = __require("core/base")
local Components = __require("components/init")
local LogoAsset = __require("core/logo")
local ShenkyUI = __require("core/ui")
local Icons = __require("assets/icons")
local resolveIcon = Icons.Resolve
local Wrapper = __require("core/wrapper")
local wrapSection = Wrapper.wrapSection
local wrapTab = Wrapper.wrapTab
local createMobileToggle = __require("core/mobile")
local createSearch = __require("core/search")

Hub.Components = Components
Hub.Icons = Icons
if getgenv then getgenv().__SHENKY_ICONS = Icons end
Hub.LogoAsset = LogoAsset
Hub.LogoHubAsset = getgenv().__SHENKY_LOGO_HUB_ASSET
Hub.ShenkyUI = ShenkyUI
Hub.UI = ShenkyUI
Hub.MacLib = ShenkyUI
Hub._CreateMobileToggle = createMobileToggle
Hub.wrapSection = wrapSection
Hub.wrapTab = wrapTab

-- Register feature modules
__require("modules/webhook")(Hub)
__require("modules/esp")(Hub)

-- Register universal tabs
__require("tabs/home")(Hub)
__require("tabs/player")(Hub)
__require("tabs/render")(Hub)
__require("tabs/server")(Hub)
__require("tabs/config")(Hub)

-- ==== Hub:CreateWindow(cfg) ====
function Hub:CreateWindow(cfg)
	self._isBooting = true
	Hub._isBooting = true
	cfg = cfg or {}
	local toggleKey = cfg.ToggleKey or cfg.Keybind or Enum.KeyCode.RightControl
	local rawFolder = tostring(cfg.Folder or cfg.SubTitle or "GlobalHub")
	rawFolder = string.gsub(rawFolder, "^[/\\%s]+", "")
	rawFolder = string.gsub(rawFolder, "[/\\%s]+$", "")
	if string.lower(string.sub(rawFolder, 1, 7)) == "shenky/" or string.lower(string.sub(rawFolder, 1, 7)) == "shenky\\" then
		rawFolder = string.sub(rawFolder, 8)
	end
	if rawFolder == "" then
		rawFolder = "GlobalHub"
	end
	local folderName = "Shenky/" .. rawFolder

	-- Migrasi otomatis dari format root lama (<folder>/settings) ke format Shenky (<Shenky/folder>/settings) jika ada
	pcall(function()
		if isfolder and makefolder and isfile and readfile and writefile and listfiles then
			local oldSettings = rawFolder .. "/settings"
			local newSettings = folderName .. "/settings"
			if isfolder(oldSettings) then
				if not isfolder("Shenky") then pcall(makefolder, "Shenky") end
				if not isfolder(folderName) then pcall(makefolder, folderName) end
				if not isfolder(newSettings) then pcall(makefolder, newSettings) end
				for _, filePath in ipairs(listfiles(oldSettings)) do
					local fileName = string.match(filePath, "[^/\\]+$")
					if fileName and fileName ~= "" then
						local targetPath = newSettings .. "/" .. fileName
						if not isfile(targetPath) then
							local content = readfile(filePath)
							if content then
								writefile(targetPath, content)
							end
						end
					end
				end
			end
		end
	end)

	self._usedFlags = {}
	self._toggles = {}
	self.HomeTab = nil
	self.PlayerTab = nil
	self.RenderTab = nil
	self.ServerTab = nil
	self.ConfigTab = nil

	-- Ukuran window 720x470 pada skala 100% (1.0) dengan elemen internal yang sudah dirapatkan
	-- sehingga muat banyak menu di sidebar dan banyak kontrol di setiap kolom seperti BigFroot.
	local windowSize = cfg.Size
	if not windowSize or (windowSize.X.Offset <= 580 and windowSize.Y.Offset <= 440) then
		windowSize = UDim2.fromOffset(720, 470)
	end
	-- Baseline skala 75% (ukuran visual 720x470 saat ini dianggap 75% sebagai ukuran nyaman)
	local defaultScalePercent = 75
	if tonumber(cfg.Scale) then
		local s = tonumber(cfg.Scale)
		if s <= 2.0 then
			defaultScalePercent = math.floor(s * 100 + 0.5)
		else
			defaultScalePercent = math.floor(s + 0.5)
		end
	end
	defaultScalePercent = math.clamp(defaultScalePercent, 0, 100)

	ShenkyUI.Folder = folderName

	-- Title selalu konsisten "Shenky Hub" dari gui/hub.
	-- SubTitle (nama game) ditampilkan khusus di TopBar status toggle, tidak perlu redundan di GUI window.
	local windowTitle = "Shenky Hub"
	local gameSubtitle = "Universal"
	if cfg.SubTitle or cfg.Subtitle then
		gameSubtitle = tostring(cfg.SubTitle or cfg.Subtitle)
	elseif cfg.Title and cfg.Title ~= "Shenky Hub" then
		gameSubtitle = tostring(cfg.Title)
	end
	cfg.SubTitle = gameSubtitle

	local ShenkyWindow = ShenkyUI:Window({
		Title = windowTitle,
		Subtitle = "",
		Size = windowSize,
		DragStyle = 1,
		DisabledWindowControls = {},
		ShowUserInfo = true,
		Keybind = toggleKey,
		AcrylicBlur = false,
	})

	pcall(function()
		ShenkyUI:SetFolder(folderName)
	end)

	local initialActualScale = defaultScalePercent / 75
	if initialActualScale ~= 1.0 then
		pcall(function()
			ShenkyWindow:SetScale(initialActualScale)
		end)
	end

	self._Window = ShenkyWindow
	self._ShenkyWindow = ShenkyWindow
	self._MacWindow = ShenkyWindow

	-- Search feature di header
	pcall(function()
		self._SearchSystem = createSearch(self, ShenkyWindow)
	end)
	self.Config = {
		AntiAFK = cfg.AntiAFK ~= false,
		ToggleKey = toggleKey,
		Folder = folderName,
		Scale = defaultScalePercent,
		MobileToggle = cfg.MobileToggle ~= false,
		HideOnExecute = (cfg.HideOnExecute == true) or (cfg.HideGuiOnExecute == true),
	}

	-- Universal Config Persistence (Persistent user preferences across all games)
	local function getUniversalConfigPath()
		return "Shenky/universal_config.json"
	end

	function Hub:SaveUniversalConfig()
		pcall(function()
			if not (writefile and isfolder and makefolder) then return end
			if not isfolder("Shenky") then
				makefolder("Shenky")
			end
			local HttpService = game:GetService("HttpService")
			local keyName = "RightControl"
			if self.Config.ToggleKey and typeof(self.Config.ToggleKey) == "EnumItem" then
				keyName = self.Config.ToggleKey.Name
			end
			local payload = {
				ToggleKey = keyName,
				Scale = tonumber(self.Config.Scale) or 75,
				MobileToggle = self.Config.MobileToggle ~= false,
				AntiAFK = self.Config.AntiAFK ~= false,
				HideOnExecute = self.Config.HideOnExecute == true,
			}
			writefile(getUniversalConfigPath(), HttpService:JSONEncode(payload))
		end)
	end

	function Hub:LoadUniversalConfig()
		pcall(function()
			if not (readfile and isfile and isfile(getUniversalConfigPath())) then return end
			local HttpService = game:GetService("HttpService")
			local content = readfile(getUniversalConfigPath())
			local data = HttpService:JSONDecode(content)
			if type(data) == "table" then
				if type(data.ToggleKey) == "string" and Enum.KeyCode[data.ToggleKey] then
					self.Config.ToggleKey = Enum.KeyCode[data.ToggleKey]
				end
				if tonumber(data.Scale) then
					self.Config.Scale = math.clamp(tonumber(data.Scale), 25, 100)
				end
				if data.MobileToggle ~= nil then
					self.Config.MobileToggle = (data.MobileToggle == true)
				end
				if data.AntiAFK ~= nil then
					self.Config.AntiAFK = (data.AntiAFK == true)
				end
				if data.HideOnExecute ~= nil then
					self.Config.HideOnExecute = (data.HideOnExecute == true)
				elseif data.HideGuiOnExecute ~= nil then
					self.Config.HideOnExecute = (data.HideGuiOnExecute == true)
				end
			end
		end)
	end

	-- Load saved universal preferences
	self:LoadUniversalConfig()
	if tonumber(self.Config.Scale) and tonumber(self.Config.Scale) ~= defaultScalePercent then
		defaultScalePercent = tonumber(self.Config.Scale)
		pcall(function()
			ShenkyWindow:SetScale(defaultScalePercent / 75)
		end)
	end

	if self.Config.HideOnExecute then
		pcall(function()
			ShenkyWindow:SetState(false)
		end)
	end

	-- Global Settings di ikon Globe pojok kiri atas Shenky UI
	pcall(function()
		ShenkyWindow:GlobalSetting({
			Name = "UI Blur",
			Default = false,
			Callback = function(_state)
				-- Acrylic blur dinonaktifkan tuntas demi mencegah efek blur yang merusak game
			end,
		})
		ShenkyWindow:GlobalSetting({
			Name = "Notifications",
			Default = ShenkyWindow:GetNotificationsState(),
			Callback = function(state)
				ShenkyWindow:SetNotificationsState(state)
			end,
		})
		ShenkyWindow:GlobalSetting({
			Name = "Show User Info",
			Default = ShenkyWindow:GetUserInfoState(),
			Callback = function(state)
				ShenkyWindow:SetUserInfoState(state)
			end,
		})
	end)

	-- Initialize Modular Navigation Sidebar Component
	local SidebarComponent = Components.Sidebar
	local sidebarInstance = SidebarComponent.new(ShenkyWindow, Hub, {
		Folder = folderName,
	})
	self._Sidebar = sidebarInstance
	self._FirstTab = nil

	local WindowWrapper = {
		_raw = ShenkyWindow,
		Sidebar = sidebarInstance,
	}

	function WindowWrapper:GetSidebar()
		return self.Sidebar
	end

	function WindowWrapper:Category(groupCfg)
		return self.Sidebar:Category(groupCfg)
	end

	function WindowWrapper:CreateCategory(groupCfg)
		return self.Sidebar:Category(groupCfg)
	end

	function WindowWrapper:TabGroup(groupCfg)
		return self.Sidebar:Category(groupCfg)
	end

	function WindowWrapper:Tab(tabCfg)
		return self.Sidebar:Tab(tabCfg)
	end

	function WindowWrapper:Channel(channelCfg)
		return self.Sidebar:Channel(channelCfg)
	end

	function WindowWrapper:CreateChannel(channelCfg)
		return self.Sidebar:Channel(channelCfg)
	end

		local lastToggleTime = 0
	local isToggling = false
	function WindowWrapper:Toggle()
		local now = os.clock()
		if isToggling or (now - lastToggleTime) < 0.30 then return end
		isToggling = true
		lastToggleTime = now
		pcall(function()
			local nextState = not ShenkyWindow:GetState()
			if not nextState then
				if Hub._SearchSystem then
					pcall(function()
						if Hub._SearchSystem.SearchBox then
							Hub._SearchSystem.SearchBox:ReleaseFocus()
						end
						if Hub._SearchSystem.Popup then
							Hub._SearchSystem.Popup.Visible = false
						end
					end)
				end
			end
			ShenkyWindow:SetState(nextState)
		end)
		task.delay(0.20, function()
			isToggling = false
		end)
	end

	function WindowWrapper:Open()
		pcall(function()
			ShenkyWindow:SetState(true)
		end)
	end

	function WindowWrapper:Close()
		pcall(function()
			if Hub._SearchSystem then
				pcall(function()
					if Hub._SearchSystem.SearchBox then
						Hub._SearchSystem.SearchBox:ReleaseFocus()
					end
					if Hub._SearchSystem.Popup then
						Hub._SearchSystem.Popup.Visible = false
					end
				end)
			end
			ShenkyWindow:SetState(false)
		end)
	end

	function WindowWrapper:SelectTab(tabWrapper)
		if type(tabWrapper) == "table" and type(tabWrapper.Select) == "function" then
			pcall(function()
				tabWrapper:Select()
			end)
		end
	end

	function WindowWrapper:SetUserProfile(profileCfg)
		if self.Sidebar and self.Sidebar.SetUserProfile then
			self.Sidebar:SetUserProfile(profileCfg)
		end
	end

	function WindowWrapper:SetAnonymousMode(enabled)
		if self.Sidebar and self.Sidebar.SetAnonymousMode then
			self.Sidebar:SetAnonymousMode(enabled)
		end
	end

	function WindowWrapper:GetAnonymousMode()
		if self.Sidebar and self.Sidebar.GetAnonymousMode then
			return self.Sidebar:GetAnonymousMode()
		end
		return false
	end

	function WindowWrapper:SetHistory(historyList)
		if Hub.SetHistory then
			Hub:SetHistory(historyList)
		end
	end

	function WindowWrapper:SetChangelog(historyList)
		if Hub.SetHistory then
			Hub:SetHistory(historyList)
		end
	end

	WindowWrapper._onCloseCallbacks = {}
	function WindowWrapper:OnClose(fn)
		if type(fn) == "function" then
			table.insert(self._onCloseCallbacks, fn)
		end
	end

	pcall(function()
		ShenkyWindow.onUnloaded(function()
			for i = #WindowWrapper._onCloseCallbacks, 1, -1 do
				local cb = WindowWrapper._onCloseCallbacks[i]
				if type(cb) == "function" then
					pcall(cb)
				end
			end
			table.clear(WindowWrapper._onCloseCallbacks)
			if Hub.Watermark then
				pcall(function() Hub.Watermark:Destroy() end)
			end
			if not Hub._destroyed then
				pcall(function() Hub:Destroy() end)
			end
		end)
	end)

	-- Global Toggle Shortcut (InputBegan) with Debounce & Flexible Key Match
	local UserInputService = game:GetService("UserInputService")
	if self._toggleConn then
		pcall(self._toggleConn.Disconnect, self._toggleConn)
		self._toggleConn = nil
	end

	local function isKeyMatch(inputKey, targetKey)
		if not inputKey or not targetKey then return false end
		if inputKey == targetKey then return true end
		if (targetKey == Enum.KeyCode.RightControl or targetKey == Enum.KeyCode.LeftControl) and
		   (inputKey == Enum.KeyCode.RightControl or inputKey == Enum.KeyCode.LeftControl) then
			return true
		end
		if (targetKey == Enum.KeyCode.RightShift or targetKey == Enum.KeyCode.LeftShift) and
		   (inputKey == Enum.KeyCode.RightShift or inputKey == Enum.KeyCode.LeftShift) then
			return true
		end
		if (targetKey == Enum.KeyCode.RightAlt or targetKey == Enum.KeyCode.LeftAlt) and
		   (inputKey == Enum.KeyCode.RightAlt or inputKey == Enum.KeyCode.LeftAlt) then
			return true
		end
		return false
	end

	self._toggleConn = UserInputService.InputBegan:Connect(function(input, gpe)
		local currentKey = Hub.Config and Hub.Config.ToggleKey or Enum.KeyCode.RightControl
		if isKeyMatch(input.KeyCode, currentKey) then
			local focused = UserInputService:GetFocusedTextBox()
			if focused then
				local isSearchBox = (Hub._SearchSystem and Hub._SearchSystem.SearchBox and focused == Hub._SearchSystem.SearchBox)
				local isModifierKey = (
					input.KeyCode == Enum.KeyCode.RightControl or
					input.KeyCode == Enum.KeyCode.LeftControl or
					input.KeyCode == Enum.KeyCode.RightShift or
					input.KeyCode == Enum.KeyCode.LeftShift or
					input.KeyCode == Enum.KeyCode.RightAlt or
					input.KeyCode == Enum.KeyCode.LeftAlt
				)
				if isSearchBox or isModifierKey then
					pcall(function() focused:ReleaseFocus() end)
					WindowWrapper:Toggle()
					return
				end
				return
			end
			WindowWrapper:Toggle()
		end
	end)

	-- Disable MacLib's raw un-debounced InputEnded listener so it never double-toggles
	pcall(function()
		ShenkyWindow:SetKeybind(Enum.KeyCode.Unknown)
	end)

	function WindowWrapper:SetMobileToggleVisible(visible)
		Hub.Config.MobileToggle = (visible == true)
		if Hub._mobileToggleGui then
			Hub._mobileToggleGui.Enabled = (visible == true)
		end
	end

	function WindowWrapper:GetMobileToggleVisible()
		return Hub.Config.MobileToggle == true
	end

	function WindowWrapper:SetHideOnExecute(enabled)
		Hub.Config.HideOnExecute = (enabled == true)
		if Hub.SaveUniversalConfig then Hub:SaveUniversalConfig() end
	end

	function WindowWrapper:GetHideOnExecute()
		return Hub.Config.HideOnExecute == true
	end

	function WindowWrapper:Destroy()
		pcall(function()
			if Hub._toggleConn then
				pcall(Hub._toggleConn.Disconnect, Hub._toggleConn)
				Hub._toggleConn = nil
			end
			if Hub._antiAfkConn then
				pcall(Hub._antiAfkConn.Disconnect, Hub._antiAfkConn)
				Hub._antiAfkConn = nil
			end
			if Hub.ServerRuntime and Hub.ServerRuntime.Destroy then
				pcall(function() Hub.ServerRuntime:Destroy() end)
			end
			if Hub.PlayerRuntime and Hub.PlayerRuntime.Destroy then
				pcall(function() Hub.PlayerRuntime:Destroy() end)
			end
			if Hub.RenderRuntime and Hub.RenderRuntime.Destroy then
				pcall(function() Hub.RenderRuntime:Destroy() end)
			end
			if Components.Toast and Components.Toast.PurgeStale then
				pcall(Components.Toast.PurgeStale)
			end
			ShenkyWindow:SetKeybind(Enum.KeyCode.Unknown)
			ShenkyWindow:Unload()
		end)
	end

	function WindowWrapper:Notify(notifyCfg, desc, toastType)
		if Hub._isBooting or (self._hub and self._hub._isBooting) then
			return
		end
		local Toast = Components.Toast
		if Toast and Toast.Show then
			return Toast:Show(notifyCfg, desc, toastType)
		end
		return ShenkyWindow:Notify(notifyCfg)
	end

	WindowWrapper.Toast = Components.Toast

	function WindowWrapper:Dialog(dialogCfg)
		if type(dialogCfg) == "table" and type(dialogCfg.Buttons) == "table" then
			for _, btn in ipairs(dialogCfg.Buttons) do
				if type(btn) == "table" and not btn.Name then
					btn.Name = btn.Title or btn.Text or "Button"
				end
			end
		end
		return ShenkyWindow:Dialog(dialogCfg)
	end

	setmetatable(WindowWrapper, {
		__index = function(_, k)
			return ShenkyWindow[k]
		end,
	})

	self.Window = WindowWrapper

	-- Buat Channel Home di grup Main secara default jika diaktifkan (First tab & landing screen)
	if cfg.HomeTab ~= false and not self.HomeTab then
		local mainGroup = WindowWrapper:Category("Main")
		self:_CreateHomeTab(WindowWrapper, mainGroup, cfg)
	end

	-- Buat tombol mobile toggle mengambang jika aktif
	if self.Config.MobileToggle then
		self:_CreateMobileToggle(WindowWrapper, cfg)
	end

	if self.Config.HideOnExecute then
		pcall(function()
			WindowWrapper:Close()
		end)
	end

	-- Watermark HUD retired per user preference; Topbar Status Pill is the primary toggle widget

	-- Anti-AFK universal (Multi-Layer: VIM + VirtualUser + Disable Default Idled Listeners + 2-Min Proactive Heartbeat)
	local LocalPlayer = Players.LocalPlayer
	local function performAntiAfkPulse()
		-- Layer 1: VirtualInputManager (Native modern Roblox input simulation)
		local okVim = pcall(function()
			local vim = game:GetService("VirtualInputManager")
			vim:SendMouseButtonEvent(0, 0, 0, true, game, 0)
			task.wait(0.02)
			vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
		end)

		-- Layer 2: VirtualUser Button2 (Right-click camera fallback)
		pcall(function()
			local vu = game:GetService("VirtualUser")
			local cam = workspace.CurrentCamera
			local cf = cam and cam.CFrame or CFrame.new()
			vu:Button2Down(Vector2.zero, cf)
			task.wait(0.02)
			vu:Button2Up(Vector2.zero, cf)
		end)
	end

	if LocalPlayer then
		-- Disable CoreScripts / default Idle disconnect prompt listeners if supported
		pcall(function()
			if typeof(getconnections) == "function" then
				for _, conn in ipairs(getconnections(LocalPlayer.Idled)) do
					if typeof(conn.Disable) == "function" then
						pcall(function() conn:Disable() end)
					end
				end
			end
		end)

		-- Connect our own responsive Idled listener
		self._antiAfkConn = LocalPlayer.Idled:Connect(function()
			if not self.Config.AntiAFK then return end
			performAntiAfkPulse()
		end)

		-- Proactive heartbeat pulse every 120s (so client never even reaches 20-min idle timeout)
		local currentGen = self._Gen
		task.spawn(function()
			while self._Gen == currentGen do
				task.wait(120)
				if self._Gen ~= currentGen then break end
				if self.Config.AntiAFK then
					performAntiAfkPulse()
				end
			end
		end)
	end

	-- Buat Tab Universal (Player & Config) di grup terpisah setelah tab game selesai dibuat, lalu muat Autoload Config jika ada
	local createGen = self._Gen
	task.defer(function()
		if self._Gen == createGen and self.Window == WindowWrapper then
			local hasAnyUniversal = (cfg.PlayerTab ~= false) or (cfg.RenderTab ~= false) or (cfg.ServerTab ~= false) or (cfg.ConfigTab ~= false)
			local uniGroup = nil
			if hasAnyUniversal then
				uniGroup = WindowWrapper:TabGroup("Universal")
			end
			if cfg.PlayerTab ~= false and not self.PlayerTab and uniGroup then
				local playerMode = "Full"
				if cfg.PlayerTab == "Safe" or cfg.PlayerTab == "CameraOnly" then
					playerMode = "Safe"
				elseif cfg.PlayerTab == "Full" then
					playerMode = "Full"
				else
					local hasAc, acDetail = self:DetectAntiCheat()
					if hasAc then
						playerMode = "Safe"
						self._detectedAntiCheat = acDetail
					end
				end
				self:_CreatePlayerTab(WindowWrapper, uniGroup, playerMode)
			end
			if cfg.RenderTab ~= false and not self.RenderTab and uniGroup then
				self:_CreateRenderTab(WindowWrapper, uniGroup)
			end
			if cfg.ServerTab ~= false and not self.ServerTab and uniGroup then
				self:_CreateServerTab(WindowWrapper, uniGroup)
			end
			if cfg.ConfigTab ~= false and not self.ConfigTab and uniGroup then
				self:_CreateConfigTab(WindowWrapper, uniGroup)
			end
			if self._FirstTab then
				pcall(function()
					self._FirstTab:Select()
				end)
			end
			pcall(function()
				ShenkyUI:LoadAutoLoadConfig()
			end)
			if self.Config.HideOnExecute then
				pcall(function()
					WindowWrapper:Close()
				end)
			end
			task.delay(0.6, function()
				if self._Gen == createGen then
					self._isBooting = false
					Hub._isBooting = false
				end
			end)
		end
	end)

	task.delay(3, function()
		if self._Gen == createGen then
			self._isBooting = false
			Hub._isBooting = false
		end
	end)

	return WindowWrapper
end

function Hub:Notify(notifyCfg, desc, toastType)
	if self._isBooting or (Hub and Hub._isBooting) then
		return
	end
	local Toast = self.Components and self.Components.Toast or (getgenv and getgenv().__SHENKY_COMPONENTS and getgenv().__SHENKY_COMPONENTS.Toast)
	if Toast and Toast.Show then
		return Toast:Show(notifyCfg, desc, toastType)
	end
	if self._ShenkyWindow then
		return self._ShenkyWindow:Notify(notifyCfg)
	end
end

Hub.Toast = Components.Toast

function Hub:Dialog(dialogCfg)
	if self._ShenkyWindow then
		if type(dialogCfg) == "table" and type(dialogCfg.Buttons) == "table" then
			for _, btn in ipairs(dialogCfg.Buttons) do
				if type(btn) == "table" and not btn.Name then
					btn.Name = btn.Title or btn.Text or "Button"
				end
			end
		end
		return self._ShenkyWindow:Dialog(dialogCfg)
	end
end

function Hub:SetAnonymousMode(enabled)
	if self._Sidebar and self._Sidebar.SetAnonymousMode then
		self._Sidebar:SetAnonymousMode(enabled)
	elseif self.Window and self.Window.Sidebar and self.Window.Sidebar.SetAnonymousMode then
		self.Window.Sidebar:SetAnonymousMode(enabled)
	end
end

function Hub:GetAnonymousMode()
	if self._Sidebar and self._Sidebar.GetAnonymousMode then
		return self._Sidebar:GetAnonymousMode()
	elseif self.Window and self.Window.Sidebar and self.Window.Sidebar.GetAnonymousMode then
		return self.Window.Sidebar:GetAnonymousMode()
	end
	return false
end

function Hub:GetExecuteCount()
	if self._HomeRuntime and self._HomeRuntime.GetExecuteCount then
		return self._HomeRuntime:GetExecuteCount()
	end
	return self.ExecuteCount or 1
end

local genv = (getgenv and getgenv()) or _G
genv.__DEV_HUB = Hub

return Hub

end)()
