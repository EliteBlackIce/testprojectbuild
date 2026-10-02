-- UNDERDOG (Roblox prototype) - CLIENT SCRIPT (LocalScript)
-- First person camera, HUD, shooting input, power-card picker.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local R = RS:WaitForChild("UnderdogRemotes")
local FireEv, ReloadEv, SwitchEv, PickEv = R:WaitForChild("Fire"), R:WaitForChild("Reload"), R:WaitForChild("Switch"), R:WaitForChild("Pick")
local OfferEv, MsgEv, HitEv, TimerEv = R:WaitForChild("Offer"), R:WaitForChild("Msg"), R:WaitForChild("Hit"), R:WaitForChild("Timer")

player.CameraMode = Enum.CameraMode.LockFirstPerson
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)
UIS.MouseIconEnabled = false

local pg = player:WaitForChild("PlayerGui")
local oldHud = pg:FindFirstChild("UnderdogHUD")
if oldHud then oldHud:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = "UnderdogHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = pg

local FONT = Enum.Font.Arcade
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent or gui
	return o
end
local function label(props, parent)
	props.BackgroundTransparency = 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextStrokeTransparency = 0.3
	return make("TextLabel", props, parent)
end

-- crosshair
local cross = make("Frame", { Size = UDim2.fromOffset(0, 0), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1 })
for _, d in ipairs({ { -2, -14, 4, 8 }, { -2, 6, 4, 8 }, { -14, -2, 8, 4 }, { 6, -2, 8, 4 } }) do
	make("Frame", { Position = UDim2.fromOffset(d[1], d[2]), Size = UDim2.fromOffset(d[3], d[4]), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0 }, cross)
end
make("Frame", { Position = UDim2.fromOffset(-1, -1), Size = UDim2.fromOffset(2, 2), BackgroundColor3 = Color3.fromRGB(255, 80, 60), BorderSizePixel = 0 }, cross)

-- hit marker
local hit = make("Frame", { Size = UDim2.fromOffset(0, 0), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, Visible = false })
local hitBars = {}
for _, rot in ipairs({ 45, -45 }) do
	local b = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(26, 3), Rotation = rot, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, hit)
	table.insert(hitBars, b)
end
HitEv.OnClientEvent:Connect(function(headshot, killed)
	local c = killed and Color3.fromRGB(255, 60, 50) or (headshot and Color3.fromRGB(255, 220, 60) or Color3.new(1, 1, 1))
	for _, b in ipairs(hitBars) do b.BackgroundColor3 = c end
	hit.Visible = true
	task.delay(killed and 0.35 or 0.12, function() hit.Visible = false end)
end)

-- scope overlay
local scope = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, scope)
make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, scope)
for _, e in ipairs({ { 0, 0, 1, 0.12 }, { 0, 0.88, 1, 0.12 }, { 0, 0, 0.2, 1 }, { 0.8, 0, 0.2, 1 } }) do
	make("Frame", { Position = UDim2.fromScale(e[1], e[2]), Size = UDim2.fromScale(e[3], e[4]), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, scope)
end

-- health
local hpBack = make("Frame", { Position = UDim2.new(0, 24, 1, -64), Size = UDim2.fromOffset(280, 26), BackgroundColor3 = Color3.fromRGB(20, 18, 28), BorderSizePixel = 0 })
make("UIStroke", { Color = Color3.fromRGB(10, 8, 14), Thickness = 3 }, hpBack)
local hpFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(80, 220, 110), BorderSizePixel = 0 }, hpBack)
local hpText = label({ Size = UDim2.fromScale(1, 1), Text = "100", TextSize = 20 }, hpBack)

-- ammo / weapon
local ammoText = label({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -28, 1, -40), Size = UDim2.fromOffset(240, 44), Text = "", TextSize = 40, TextXAlignment = Enum.TextXAlignment.Right })
local wepText = label({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -28, 1, -84), Size = UDim2.fromOffset(300, 24), Text = "", TextSize = 20, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(255, 220, 140) })
label({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -28, 1, -14), Size = UDim2.fromOffset(420, 18), Text = "1 Rifle   2 Sniper   3 Shotgun   R Reload   RMB Aim", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(200, 200, 215) })

-- timer / score
local timerText = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(500, 34), Text = "", TextSize = 32 })
local scoreText = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(700, 22), Text = "", TextSize = 18, TextColor3 = Color3.fromRGB(255, 220, 140) })
TimerEv.OnClientEvent:Connect(function(t, txt)
	if t and t >= 0 then
		timerText.Text = string.format("%d:%02d", math.floor(t / 60), t % 60)
	end
	scoreText.Text = txt or ""
end)

-- big message
local msg = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(900, 80), Text = "", TextSize = 56, TextTransparency = 1 })
local msgId = 0
MsgEv.OnClientEvent:Connect(function(text)
	msgId = msgId + 1
	local id = msgId
	msg.Text = text
	msg.TextTransparency = 0
	msg.TextStrokeTransparency = 0.2
	task.delay(1.6, function()
		if id == msgId then
			TweenService:Create(msg, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end)

-- power cards
local cardFrame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(720, 240), BackgroundTransparency = 1, Visible = false })
local cardTitle = label({ Position = UDim2.new(0, 0, 0, -44), Size = UDim2.fromOffset(720, 36), Text = "YOU'RE THE UNDERDOG - PICK A POWER CARD (1 / 2 / 3)", TextSize = 24, TextColor3 = Color3.fromRGB(255, 220, 140) }, cardFrame)
local cardButtons = {}
local offerActive = false
for i = 1, 3 do
	local b = make("TextButton", { Position = UDim2.fromOffset((i - 1) * 245, 0), Size = UDim2.fromOffset(230, 240), BackgroundColor3 = Color3.fromRGB(34, 30, 52), BorderSizePixel = 0, Text = "", AutoButtonColor = true, Modal = true }, cardFrame)
	make("UIStroke", { Color = Color3.fromRGB(255, 200, 80), Thickness = 3 }, b)
	local nameL = label({ Position = UDim2.fromOffset(8, 24), Size = UDim2.fromOffset(214, 60), Text = "", TextSize = 24, TextWrapped = true, TextColor3 = Color3.fromRGB(255, 230, 160) }, b)
	local descL = label({ Position = UDim2.fromOffset(12, 100), Size = UDim2.fromOffset(206, 100), Text = "", TextSize = 20, TextWrapped = true }, b)
	label({ Position = UDim2.fromOffset(0, 206), Size = UDim2.fromOffset(230, 26), Text = "[" .. i .. "]", TextSize = 22, TextColor3 = Color3.fromRGB(160, 160, 190) }, b)
	b.MouseButton1Click:Connect(function()
		if offerActive then PickEv:FireServer(i) end
	end)
	cardButtons[i] = { b = b, name = nameL, desc = descL }
end
OfferEv.OnClientEvent:Connect(function(cards)
	if not cards then
		offerActive = false
		cardFrame.Visible = false
		return
	end
	offerActive = true
	for i = 1, 3 do
		local c = cards[i]
		cardButtons[i].name.Text = c and string.upper(c.name) or ""
		cardButtons[i].desc.Text = c and c.desc or ""
	end
	cardFrame.Visible = true
end)

-- HUD update
local lastHp = 100
RunService.RenderStepped:Connect(function()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		local f = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
		hpFill.Size = UDim2.fromScale(f, 1)
		hpFill.BackgroundColor3 = Color3.fromRGB(255 * (1 - f) + 80 * f, 220 * f + 60 * (1 - f), 80)
		hpText.Text = tostring(math.ceil(hum.Health))
	end
	local ammo, mag = player:GetAttribute("Ammo"), player:GetAttribute("Mag")
	if ammo then
		ammoText.Text = player:GetAttribute("Reloading") and "RELOADING" or (ammo .. " / " .. tostring(mag))
		ammoText.TextColor3 = (ammo == 0) and Color3.fromRGB(255, 90, 70) or Color3.new(1, 1, 1)
	end
	wepText.Text = string.upper(tostring(player:GetAttribute("WeaponName") or ""))
end)

-- input
local WEAPON_KEYS = { [Enum.KeyCode.One] = "rifle", [Enum.KeyCode.Two] = "sniper", [Enum.KeyCode.Three] = "shotgun" }
local AUTO = { rifle = true }
local firing, scoped = false, false
local lastShot = 0

local function shoot()
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local cam = Workspace.CurrentCamera
	if not (head and cam) then return end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local res = Workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 1000, params)
	local target = res and res.Position or (cam.CFrame.Position + cam.CFrame.LookVector * 1000)
	FireEv:FireServer((target - head.Position).Unit)
end

UIS.InputBegan:Connect(function(input, gp)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if offerActive then return end
		firing = true
		shoot()
		lastShot = os.clock()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		scoped = true
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		if offerActive then
			local idx = (input.KeyCode == Enum.KeyCode.One and 1) or (input.KeyCode == Enum.KeyCode.Two and 2) or (input.KeyCode == Enum.KeyCode.Three and 3)
			if idx then PickEv:FireServer(idx) end
			return
		end
		if WEAPON_KEYS[input.KeyCode] then
			SwitchEv:FireServer(WEAPON_KEYS[input.KeyCode])
		elseif input.KeyCode == Enum.KeyCode.R then
			ReloadEv:FireServer()
		end
	end
end)
UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		scoped = false
	end
end)

RunService.Heartbeat:Connect(function()
	local w = player:GetAttribute("Weapon")
	if firing and AUTO[w] and os.clock() - lastShot >= 0.1 then
		lastShot = os.clock()
		shoot()
	end
	local cam = Workspace.CurrentCamera
	if cam then
		local fov = 75
		if scoped then fov = (w == "sniper") and 14 or 50 end
		cam.FieldOfView = cam.FieldOfView + (fov - cam.FieldOfView) * 0.35
	end
	scope.Visible = scoped and w == "sniper"
	cross.Visible = not (scoped and w == "sniper")
end)
