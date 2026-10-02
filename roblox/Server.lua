-- UNDERDOG (Roblox prototype) - SERVER SCRIPT
-- Builds the Freight Yard map, runs the round loop, weapons and power cards.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

-- if anything goes wrong, show the error ON SCREEN (a blue message box) so it can be read without the Output panel
local function showErr(err)
	warn("Underdog error: " .. tostring(err))
	local m = Instance.new("Message")
	m.Text = "UNDERDOG ERROR - take a photo and send it:\n" .. string.sub(tostring(err), 1, 600)
	m.Parent = Workspace
end
local booting = Instance.new("Message")
booting.Text = "Underdog server script is running..."
booting.Parent = Workspace
print("Underdog server started")

local function main()
local WINS_TO_WIN = 5
local ROUND_TIME = 120
local MIN_PLAYERS = 2

------------------------------------------------------------------ remotes
local old = RS:FindFirstChild("UnderdogRemotes")
if old then old:Destroy() end
local R = Instance.new("Folder")
R.Name = "UnderdogRemotes"
R.Parent = RS
local function remote(name)
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = R
	return e
end
local FireEv, ReloadEv, SwitchEv, PickEv = remote("Fire"), remote("Reload"), remote("Switch"), remote("Pick")
local OfferEv, MsgEv, HitEv, TimerEv = remote("Offer"), remote("Msg"), remote("Hit"), remote("Timer")

------------------------------------------------------------------ give every player the client script
local template = script.Parent:FindFirstChild("Client")
if template then
	local old2 = StarterGui:FindFirstChild("UnderdogClientHost")
	if old2 then old2:Destroy() end
	local host = Instance.new("ScreenGui")
	host.Name = "UnderdogClientHost"
	host.ResetOnSpawn = false
	local c = template:Clone()
	c.Disabled = false
	c.Parent = host
	host.Parent = StarterGui
	for _, pl in ipairs(Players:GetPlayers()) do
		local h2 = host:Clone()
		h2.Parent = pl:WaitForChild("PlayerGui")
	end
else
	warn("Underdog: the 'Client' LocalScript is missing next to this Script")
end

------------------------------------------------------------------ weapons
local WEAPONS = {
	rifle   = { name = "Assault Rifle", dmg = 17, interval = 0.11, mag = 28, reload = 1.7, spread = 0.012, pellets = 1, range = 400, auto = true,  hs = 1.5 },
	sniper  = { name = "Sniper",        dmg = 95, interval = 1.1,  mag = 5,  reload = 2.5, spread = 0,     pellets = 1, range = 900, auto = false, hs = 1.6 },
	shotgun = { name = "Shotgun",       dmg = 12, interval = 0.75, mag = 6,  reload = 2.3, spread = 0.07,  pellets = 8, range = 70,  auto = false, hs = 1.3 },
}
local ORDER = { "rifle", "sniper", "shotgun" }

------------------------------------------------------------------ power cards (the underdog gets to pick one after losing a round)
local CARDS = {
	{ name = "Heavy Armor",   desc = "+40 max health",         fn = function(s) s.hpAdd = s.hpAdd + 40 end },
	{ name = "Hollow Points", desc = "+15% damage",            fn = function(s) s.dmgMul = s.dmgMul * 1.15 end },
	{ name = "Quick Hands",   desc = "+20% fire rate",         fn = function(s) s.rateMul = s.rateMul * 1.2 end },
	{ name = "Sprinter",      desc = "+12% move speed",        fn = function(s) s.speedMul = s.speedMul * 1.12 end },
	{ name = "Moon Boots",    desc = "+25% jump height",       fn = function(s) s.jumpMul = s.jumpMul * 1.25 end },
	{ name = "Extra Mags",    desc = "+50% magazine size",     fn = function(s) s.magMul = s.magMul * 1.5 end },
	{ name = "Vampire",       desc = "Heal 25 on every kill",  fn = function(s) s.healOnKill = s.healOnKill + 25 end },
	{ name = "Bulletproof",   desc = "Take 12% less damage",   fn = function(s) s.dmgTaken = s.dmgTaken * 0.88 end },
}

local state = {}
local function freshState()
	return { hpAdd = 0, dmgMul = 1, rateMul = 1, speedMul = 1, jumpMul = 1, magMul = 1, healOnKill = 0, dmgTaken = 1,
		weapon = "rifle", ammo = {}, last = 0, reloading = false, reloadId = 0, offer = nil, alive = false }
end
local function S(pl)
	if not state[pl] then state[pl] = freshState() end
	return state[pl]
end
local function magOf(pl, w)
	return math.floor(WEAPONS[w].mag * S(pl).magMul + 0.5)
end
local function setAttrs(pl)
	local s = S(pl)
	pl:SetAttribute("Weapon", s.weapon)
	pl:SetAttribute("WeaponName", WEAPONS[s.weapon].name)
	pl:SetAttribute("Ammo", s.ammo[s.weapon] or 0)
	pl:SetAttribute("Mag", magOf(pl, s.weapon))
	pl:SetAttribute("Reloading", s.reloading)
end

------------------------------------------------------------------ lighting: sunset harbour
Lighting.ClockTime = 17.4
Lighting.Brightness = 2.2
Lighting.Ambient = Color3.fromRGB(70, 60, 90)
Lighting.OutdoorAmbient = Color3.fromRGB(110, 90, 120)
Lighting.GlobalShadows = true
Lighting.ExposureCompensation = 0.1
for _, n in ipairs({ "UD_Atmo", "UD_Bloom", "UD_CC", "UD_Rays" }) do
	local o = Lighting:FindFirstChild(n)
	if o then o:Destroy() end
end
local atmo = Instance.new("Atmosphere")
atmo.Name = "UD_Atmo"
atmo.Density = 0.32
atmo.Offset = 0.25
atmo.Color = Color3.fromRGB(235, 175, 150)
atmo.Decay = Color3.fromRGB(150, 90, 120)
atmo.Glare = 0.4
atmo.Haze = 1.6
atmo.Parent = Lighting
local bloom = Instance.new("BloomEffect")
bloom.Name = "UD_Bloom"
bloom.Intensity = 0.5
bloom.Size = 30
bloom.Threshold = 1.6
bloom.Parent = Lighting
local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "UD_CC"
cc.Saturation = 0.15
cc.Contrast = 0.1
cc.TintColor = Color3.fromRGB(255, 235, 225)
cc.Parent = Lighting
local rays = Instance.new("SunRaysEffect")
rays.Name = "UD_Rays"
rays.Intensity = 0.12
rays.Parent = Lighting

------------------------------------------------------------------ map: Freight Yard
-- the place file already contains the baked map; only build a fresh one if it is missing
local baked = Workspace:FindFirstChild("FreightYard")
local MAP = Instance.new("Model")
MAP.Name = "FreightYard"
if not baked then MAP.Parent = Workspace end

local function part(name, size, pos, color, material, ry)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(ry or 0), 0)
	p.Parent = MAP
	return p
end
local function block(size, pos, color, material, ry)
	return part("Block", size, pos, color, material, ry)
end

local HALF_X, HALF_Z = 70, 40
-- ground (top at y = 0)
block(Vector3.new(HALF_X * 2 + 6, 2, HALF_Z * 2 + 6), Vector3.new(0, -1, 0), Color3.fromRGB(70, 68, 78), Enum.Material.Concrete)
-- lane markings
for x = -60, 60, 20 do
	block(Vector3.new(8, 0.06, 0.6), Vector3.new(x, 0.04, 0), Color3.fromRGB(230, 190, 40), Enum.Material.SmoothPlastic)
end
for _, z in ipairs({ -34, 34 }) do
	block(Vector3.new(HALF_X * 2, 0.06, 0.8), Vector3.new(0, 0.04, z), Color3.fromRGB(230, 190, 40), Enum.Material.SmoothPlastic)
end
-- outer ground
block(Vector3.new(900, 2, 900), Vector3.new(0, -3, 0), Color3.fromRGB(50, 46, 54), Enum.Material.Asphalt)

-- boundary: low concrete barriers you can see, plus tall invisible walls so nobody leaves
local function wall(size, pos)
	local w = block(size, pos, Color3.fromRGB(150, 148, 140), Enum.Material.Concrete)
	return w
end
wall(Vector3.new(HALF_X * 2 + 4, 4, 2), Vector3.new(0, 2, -HALF_Z - 1))
wall(Vector3.new(HALF_X * 2 + 4, 4, 2), Vector3.new(0, 2, HALF_Z + 1))
wall(Vector3.new(2, 4, HALF_Z * 2), Vector3.new(-HALF_X - 1, 2, 0))
wall(Vector3.new(2, 4, HALF_Z * 2), Vector3.new(HALF_X + 1, 2, 0))
local function invisible(size, pos)
	local w = part("Wall", size, pos, Color3.new(1, 1, 1))
	w.Transparency = 1
	w.CanQuery = false
end
invisible(Vector3.new(HALF_X * 2 + 4, 80, 2), Vector3.new(0, 40, -HALF_Z - 1))
invisible(Vector3.new(HALF_X * 2 + 4, 80, 2), Vector3.new(0, 40, HALF_Z + 1))
invisible(Vector3.new(2, 80, HALF_Z * 2), Vector3.new(-HALF_X - 1, 40, 0))
invisible(Vector3.new(2, 80, HALF_Z * 2), Vector3.new(HALF_X + 1, 40, 0))

-- a shipping container: body, ribs, door end. sx = length along X before rotation.
local CONT_COLORS = {
	Color3.fromRGB(168, 58, 38), Color3.fromRGB(42, 90, 138), Color3.fromRGB(58, 122, 68),
	Color3.fromRGB(200, 138, 26), Color3.fromRGB(216, 208, 198), Color3.fromRGB(42, 122, 122), Color3.fromRGB(138, 90, 58),
}
local ccount = 0
local function container(x, y, z, ry, color)
	ccount = ccount + 1
	color = color or CONT_COLORS[(ccount % #CONT_COLORS) + 1]
	local L, H, W = 20, 8.4, 8
	local body = part("Container", Vector3.new(L, H, W), Vector3.new(x, y + H / 2, z), color, Enum.Material.CorrugatedMetal, ry)
	local cf = body.CFrame
	local function child(size, off, col, mat)
		local p = part("Detail", size, Vector3.new(0, 0, 0), col, mat)
		p.CFrame = cf * CFrame.new(off)
		p.CanCollide = false
		return p
	end
	for i = -4, 4 do
		child(Vector3.new(0.4, H - 0.4, W + 0.3), Vector3.new(i * 2.2, 0, 0), Color3.fromRGB(26, 26, 30), Enum.Material.Metal)
	end
	child(Vector3.new(0.5, H, W + 0.2), Vector3.new(L / 2, 0, 0), Color3.fromRGB(26, 26, 30), Enum.Material.Metal)
	child(Vector3.new(0.5, H, W + 0.2), Vector3.new(-L / 2, 0, 0), Color3.fromRGB(26, 26, 30), Enum.Material.Metal)
	child(Vector3.new(0.3, H - 1, 3.4), Vector3.new(L / 2 + 0.3, 0, -2), Color3.fromRGB(110, 114, 126), Enum.Material.Metal)
	child(Vector3.new(0.3, H - 1, 3.4), Vector3.new(L / 2 + 0.3, 0, 2), Color3.fromRGB(110, 114, 126), Enum.Material.Metal)
	child(Vector3.new(0.2, 1.4, 6), Vector3.new(-4, H / 2 - 1.8, W / 2 + 0.2), Color3.fromRGB(240, 236, 224), Enum.Material.SmoothPlastic)
	return body
end
local function stack(x, z, ry, levels, colors)
	for i = 1, levels do
		container(x, (i - 1) * 8.4, z, ry, colors and colors[i] or nil)
	end
end

-- container layout (mirrored left and right)
local layout = {
	{ -50, -24, 0, 2 }, { -50, 24, 0, 1 }, { -32, -18, 90, 1 }, { -30, 28, 0, 2 }, { -14, -28, 0, 1 }, { -12, 18, 90, 1 },
	{ 0, -18, 90, 1 },
}
for _, c in ipairs(layout) do
	stack(c[1], c[2], c[3], c[4])
	stack(-c[1], -c[2], c[3], c[4])
end

-- central raised catwalk with stairs and rails (height 14)
local CW_H = 14
local deck = block(Vector3.new(34, 1, 12), Vector3.new(0, CW_H, 0), Color3.fromRGB(96, 98, 110), Enum.Material.DiamondPlate)
for _, sz in ipairs({ -1, 1 }) do
	block(Vector3.new(34, 3, 0.4), Vector3.new(0, CW_H + 2, sz * 5.8), Color3.fromRGB(232, 176, 28), Enum.Material.Metal)
end
for _, sx in ipairs({ -1, 1 }) do
	block(Vector3.new(0.4, 3, 12), Vector3.new(sx * 16.8, CW_H + 2, 0), Color3.fromRGB(232, 176, 28), Enum.Material.Metal)
	-- support legs
	for _, sz in ipairs({ -1, 1 }) do
		block(Vector3.new(1.4, CW_H, 1.4), Vector3.new(sx * 15, CW_H / 2, sz * 5), Color3.fromRGB(232, 176, 28), Enum.Material.Metal)
	end
end
-- stairs at each end: 14 steps of 1 stud rise
for _, sx in ipairs({ -1, 1 }) do
	local gap = block(Vector3.new(0.4, 3, 12), Vector3.new(sx * 16.8, CW_H + 2, 0), Color3.fromRGB(232, 176, 28), Enum.Material.Metal)
	gap:Destroy()
	for i = 1, CW_H do
		block(Vector3.new(1.6, 1, 6), Vector3.new(sx * (17 + (CW_H - i) * 1.6 + 0.8), i - 0.5, 0), Color3.fromRGB(96, 98, 110), Enum.Material.DiamondPlate)
	end
	for _, sz in ipairs({ -1, 1 }) do
		-- stair rail follows the slope
		local len = CW_H * 1.6
		local rail = part("Rail", Vector3.new(len + 4, 0.4, 0.4), Vector3.new(0, 0, 0), Color3.fromRGB(232, 176, 28), Enum.Material.Metal)
		rail.CFrame = CFrame.new(sx * (17 + len / 2), CW_H / 2 + 2.5, sz * 3.1) * CFrame.Angles(0, 0, -sx * math.atan2(CW_H, len))
	end
end

-- gantry cranes in the background (visual)
local function gantry(x, z)
	local y = Color3.fromRGB(232, 176, 28)
	for _, a in ipairs({ -26, 26 }) do
		for _, b in ipairs({ -14, 14 }) do
			block(Vector3.new(2.6, 70, 2.6), Vector3.new(x + a, 35, z + b), y, Enum.Material.Metal).CanCollide = false
		end
	end
	block(Vector3.new(60, 4, 4), Vector3.new(x, 70, z - 14), y, Enum.Material.Metal).CanCollide = false
	block(Vector3.new(60, 4, 4), Vector3.new(x, 70, z + 14), y, Enum.Material.Metal).CanCollide = false
	block(Vector3.new(6, 6, 30), Vector3.new(x - 10, 66, z), Color3.fromRGB(60, 62, 72), Enum.Material.Metal).CanCollide = false
end
gantry(0, -130)
gantry(-120, 140)
gantry(130, 150)

-- harbour skyline
local skylineSeed = Random.new(7)
for i = 1, 36 do
	local a = (i / 36) * math.pi * 2
	local r = 520 + skylineSeed:NextNumber(0, 160)
	local w, d = skylineSeed:NextNumber(30, 70), skylineSeed:NextNumber(30, 70)
	local h = skylineSeed:NextNumber(90, 340)
	local b = block(Vector3.new(w, h, d), Vector3.new(math.cos(a) * r, h / 2 - 3, math.sin(a) * r), Color3.fromRGB(88 + skylineSeed:NextInteger(0, 30), 92 + skylineSeed:NextInteger(0, 24), 118), Enum.Material.Concrete)
	b.CanCollide = false
	for k = 1, 5 do
		local win = part("Windows", Vector3.new(w + 0.2, h * 0.05, d + 0.2), Vector3.new(b.Position.X, k * h / 6 - 3, b.Position.Z), Color3.fromRGB(255, 214, 140), Enum.Material.Neon)
		win.CanCollide = false
		win.Transparency = 0.55
		win.CFrame = b.CFrame * CFrame.new(0, -h / 2 + k * h / 6, 0)
	end
end

-- light poles
for _, x in ipairs({ -60, -20, 20, 60 }) do
	for _, z in ipairs({ -36, 36 }) do
		block(Vector3.new(0.8, 18, 0.8), Vector3.new(x, 9, z), Color3.fromRGB(90, 94, 104), Enum.Material.Metal)
		local lamp = block(Vector3.new(3, 0.8, 1.6), Vector3.new(x, 18.4, z), Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
		lamp.CanCollide = false
		local pl = Instance.new("PointLight")
		pl.Range = 38
		pl.Brightness = 1.2
		pl.Color = Color3.fromRGB(255, 220, 170)
		pl.Parent = lamp
	end
end

-- ground clutter: crates, barrels, cones
local rng = Random.new(21)
for i = 1, 22 do
	local x, z = rng:NextNumber(-62, 62), rng:NextNumber(-34, 34)
	if math.abs(x) > 8 or math.abs(z) > 10 then
		if rng:NextNumber() < 0.5 then
			local s = rng:NextNumber(2.4, 3.6)
			part("Crate", Vector3.new(s, s, s), Vector3.new(x, s / 2, z), Color3.fromRGB(150, 112, 70), Enum.Material.Wood, rng:NextNumber(0, 90))
		else
			local b = part("Barrel", Vector3.new(2.4, 3.4, 2.4), Vector3.new(x, 1.7, z), ({ Color3.fromRGB(196, 42, 30), Color3.fromRGB(42, 90, 138), Color3.fromRGB(216, 160, 32) })[rng:NextInteger(1, 3)], Enum.Material.Metal)
			b.Shape = Enum.PartType.Cylinder
			b.CFrame = CFrame.new(x, 1.7, z) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
end

-- spawn pads
local SPAWNS = {
	Vector3.new(-62, 4, -2), Vector3.new(62, 4, 2), Vector3.new(-62, 4, 20), Vector3.new(62, 4, -20),
	Vector3.new(-44, 4, 34), Vector3.new(44, 4, -34), Vector3.new(-34, 4, -33), Vector3.new(34, 4, 33),
}

------------------------------------------------------------------ characters
Players.CharacterAutoLoads = false

local function giveGun(char, wid)
	local old3 = char:FindFirstChild("UD_Gun")
	if old3 then old3:Destroy() end
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if not hand then return end
	local g = Instance.new("Part")
	g.Name = "UD_Gun"
	g.CanCollide = false
	g.Massless = true
	g.Color = Color3.fromRGB(40, 40, 48)
	g.Material = Enum.Material.Metal
	local len = (wid == "sniper") and 4.4 or ((wid == "shotgun") and 3.4 or 3)
	g.Size = Vector3.new(0.45, 0.6, len)
	g.CFrame = hand.CFrame * CFrame.new(0, -0.1, -len / 2 + 0.4)
	g.Parent = char
	local w = Instance.new("WeldConstraint")
	w.Part0 = hand
	w.Part1 = g
	w.Parent = g
	local sight = Instance.new("Part")
	sight.CanCollide = false
	sight.Massless = true
	sight.Size = Vector3.new(0.3, 0.3, 0.9)
	sight.Color = Color3.fromRGB(200, 60, 40)
	sight.Material = Enum.Material.Neon
	sight.CFrame = g.CFrame * CFrame.new(0, 0.45, -0.3)
	sight.Parent = g
	local w2 = Instance.new("WeldConstraint")
	w2.Part0 = g
	w2.Part1 = sight
	w2.Parent = sight
end

local function applyStats(pl, char)
	local s = S(pl)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	hum.MaxHealth = 100 + s.hpAdd
	hum.Health = hum.MaxHealth
	hum.WalkSpeed = 17 * s.speedMul
	hum.UseJumpPower = true
	hum.JumpPower = 52 * s.jumpMul
	hum.BreakJointsOnDeath = true
end

local roundActive = false
local aliveCount = 0

local function spawnPlayer(pl, idx)
	local s = S(pl)
	s.ammo = {}
	for _, w in ipairs(ORDER) do s.ammo[w] = magOf(pl, w) end
	s.reloading = false
	s.reloadId = s.reloadId + 1
	s.weapon = s.weapon or "rifle"
	pl:LoadCharacter()
	local char = pl.Character or pl.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart")
	char:PivotTo(CFrame.new(SPAWNS[((idx - 1) % #SPAWNS) + 1]) * CFrame.Angles(0, (SPAWNS[((idx - 1) % #SPAWNS) + 1].X < 0) and math.rad(-90) or math.rad(90), 0))
	applyStats(pl, char)
	giveGun(char, s.weapon)
	s.alive = true
	setAttrs(pl)
	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(function()
		if s.alive then
			s.alive = false
			aliveCount = aliveCount - 1
		end
	end)
	return char
end

local function freeze(pl, on)
	local char = pl.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		local s = S(pl)
		hum.WalkSpeed = on and 0 or (17 * s.speedMul)
		hum.JumpPower = on and 0 or (52 * s.jumpMul)
	end
end

------------------------------------------------------------------ shooting
local function findHumanoid(inst)
	local m = inst
	while m and m ~= Workspace do
		local h = m:FindFirstChildOfClass("Humanoid")
		if h then return h, m end
		m = m.Parent
	end
	return nil, nil
end

local rand = Random.new()
local startReload
FireEv.OnServerEvent:Connect(function(pl, dir)
	if not roundActive then return end
	local s = S(pl)
	local char = pl.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local head = char and char:FindFirstChild("Head")
	if not (s.alive and hum and hum.Health > 0 and head) then return end
	if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.1 then return end
	local w = WEAPONS[s.weapon]
	local now = os.clock()
	if s.reloading then return end
	if now - s.last < (w.interval / s.rateMul) - 0.03 then return end
	if (s.ammo[s.weapon] or 0) <= 0 then return end
	s.last = now
	s.ammo[s.weapon] = s.ammo[s.weapon] - 1
	pl:SetAttribute("Ammo", s.ammo[s.weapon])
	dir = dir.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local origin = head.Position
	local hitAny, killed, headshot = false, false, false
	for _ = 1, w.pellets do
		local d = dir
		if w.spread > 0 then
			local right = d:Cross(Vector3.new(0, 1, 0))
			if right.Magnitude < 0.01 then right = Vector3.new(1, 0, 0) end
			right = right.Unit
			local up = right:Cross(d).Unit
			d = (d + right * rand:NextNumber(-w.spread, w.spread) + up * rand:NextNumber(-w.spread, w.spread)).Unit
		end
		local res = Workspace:Raycast(origin, d * w.range, params)
		local endPos = res and res.Position or (origin + d * w.range)
		-- tracer
		local len = (endPos - origin).Magnitude
		local t = Instance.new("Part")
		t.Anchored = true
		t.CanCollide = false
		t.CanQuery = false
		t.CanTouch = false
		t.Material = Enum.Material.Neon
		t.Color = Color3.fromRGB(255, 220, 140)
		t.Size = Vector3.new(0.12, 0.12, math.max(len - 2, 0.1))
		t.CFrame = CFrame.lookAt(origin + d * 2, endPos) * CFrame.new(0, 0, -math.max(len - 2, 0.1) / 2)
		t.Parent = Workspace
		Debris:AddItem(t, 0.07)
		if res then
			local th, tm = findHumanoid(res.Instance)
			if th and th.Health > 0 and tm ~= char then
				local target = Players:GetPlayerFromCharacter(tm)
				local dmg = w.dmg * s.dmgMul
				if res.Instance.Name == "Head" then
					dmg = dmg * w.hs
					headshot = true
				end
				if target then dmg = dmg * S(target).dmgTaken end
				local before = th.Health
				th:TakeDamage(dmg)
				hitAny = true
				if before > 0 and th.Health <= 0 then
					killed = true
				end
			end
		end
	end
	if killed and s.healOnKill > 0 and hum.Health > 0 then
		hum.Health = math.min(hum.MaxHealth, hum.Health + s.healOnKill)
	end
	if hitAny then HitEv:FireClient(pl, headshot, killed) end
	if s.ammo[s.weapon] == 0 then
		-- auto reload
		startReload(pl)
	end
end)

startReload = function(pl)
	local s = S(pl)
	if not s.alive or s.reloading then return end
	local wid = s.weapon
	local w = WEAPONS[wid]
	if (s.ammo[wid] or 0) >= magOf(pl, wid) then return end
	s.reloading = true
	s.reloadId = s.reloadId + 1
	local id = s.reloadId
	pl:SetAttribute("Reloading", true)
	task.delay(w.reload, function()
		if s.reloadId == id and s.alive then
			s.ammo[wid] = magOf(pl, wid)
			s.reloading = false
			pl:SetAttribute("Ammo", s.ammo[s.weapon] or 0)
			pl:SetAttribute("Reloading", false)
		end
	end)
end
ReloadEv.OnServerEvent:Connect(startReload)

SwitchEv.OnServerEvent:Connect(function(pl, wid)
	local s = S(pl)
	if not s.alive or not WEAPONS[wid] or s.weapon == wid then return end
	s.weapon = wid
	s.reloading = false
	s.reloadId = s.reloadId + 1
	if pl.Character then giveGun(pl.Character, wid) end
	setAttrs(pl)
end)

------------------------------------------------------------------ cards
local function offerCards(pl)
	local s = S(pl)
	local pool = {}
	for i = 1, #CARDS do pool[i] = i end
	local picks = {}
	for _ = 1, 3 do
		local k = rand:NextInteger(1, #pool)
		table.insert(picks, pool[k])
		table.remove(pool, k)
	end
	s.offer = picks
	local out = {}
	for _, i in ipairs(picks) do table.insert(out, { name = CARDS[i].name, desc = CARDS[i].desc }) end
	OfferEv:FireClient(pl, out)
end
PickEv.OnServerEvent:Connect(function(pl, idx)
	local s = S(pl)
	if not s.offer or type(idx) ~= "number" then return end
	local ci = s.offer[idx]
	if not ci then return end
	s.offer = nil
	CARDS[ci].fn(s)
	MsgEv:FireClient(pl, "You took: " .. CARDS[ci].name)
	OfferEv:FireClient(pl, nil)
end)

------------------------------------------------------------------ round loop
local wins = {}
local function broadcast(text)
	MsgEv:FireAllClients(text)
end
local function scoreText()
	local parts = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		table.insert(parts, pl.Name .. " " .. tostring(wins[pl] or 0))
	end
	return table.concat(parts, "   |   ")
end
local function publishScore()
	for _, pl in ipairs(Players:GetPlayers()) do
		pl:SetAttribute("Wins", wins[pl] or 0)
	end
	TimerEv:FireAllClients(-1, scoreText())
end

Players.PlayerAdded:Connect(function(pl)
	S(pl)
	wins[pl] = 0
	setAttrs(pl)
	pl.CharacterAdded:Connect(function(char)
		-- strip default tools if any
	end)
end)
Players.PlayerRemoving:Connect(function(pl)
	state[pl] = nil
	wins[pl] = nil
end)
for _, pl in ipairs(Players:GetPlayers()) do
	S(pl)
	wins[pl] = 0
end

local function resetMatch()
	for _, pl in ipairs(Players:GetPlayers()) do
		state[pl] = freshState()
		wins[pl] = 0
	end
end

local function countdown(n)
	for i = n, 1, -1 do
		broadcast(tostring(i))
		task.wait(1)
	end
	broadcast("FIGHT!")
end

task.spawn(function()
	local ok0, err0 = xpcall(function()
	while true do
		-- wait for enough players
		while #Players:GetPlayers() < MIN_PLAYERS do
			broadcast("Waiting for players... (" .. #Players:GetPlayers() .. "/" .. MIN_PLAYERS .. ")")
			task.wait(2)
		end
		resetMatch()
		publishScore()
		local matchOn = true
		local roundNo = 0
		while matchOn do
			roundNo = roundNo + 1
			if #Players:GetPlayers() < MIN_PLAYERS then break end
			roundActive = false
			broadcast("Round " .. roundNo)
			local list = Players:GetPlayers()
			aliveCount = 0
			for i, pl in ipairs(list) do
				spawnPlayer(pl, i)
				aliveCount = aliveCount + 1
			end
			for _, pl in ipairs(list) do freeze(pl, true) end
			countdown(3)
			for _, pl in ipairs(list) do freeze(pl, false) end
			roundActive = true
			local t0 = os.clock()
			while roundActive do
				local left = ROUND_TIME - (os.clock() - t0)
				TimerEv:FireAllClients(math.max(0, math.floor(left)), scoreText())
				if aliveCount <= 1 or left <= 0 or #Players:GetPlayers() < MIN_PLAYERS then break end
				task.wait(0.5)
			end
			roundActive = false
			-- winner = last alive (or most health on timeout)
			local winner, best = nil, -1
			for _, pl in ipairs(list) do
				local hum = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > best and S(pl).alive then
					best = hum.Health
					winner = pl
				end
			end
			if winner then
				wins[winner] = (wins[winner] or 0) + 1
				broadcast(winner.Name .. " wins the round!")
			else
				broadcast("Draw!")
			end
			publishScore()
			task.wait(2.5)
			if winner and wins[winner] >= WINS_TO_WIN then
				broadcast(winner.Name .. " WINS THE MATCH!")
				task.wait(5)
				matchOn = false
			else
				-- the underdogs choose a power card
				local any = false
				for _, pl in ipairs(list) do
					if pl ~= winner and pl.Parent then
						offerCards(pl)
						any = true
					end
				end
				if any then
					broadcast("Underdogs: pick a power card!")
					local t1 = os.clock()
					while os.clock() - t1 < 12 do
						local pending = false
						for _, pl in ipairs(list) do
							if pl.Parent and S(pl).offer then pending = true end
						end
						if not pending then break end
						task.wait(0.25)
					end
					for _, pl in ipairs(list) do
						local s = S(pl)
						if pl.Parent and s.offer then
							local pick = s.offer[rand:NextInteger(1, #s.offer)]
							s.offer = nil
							CARDS[pick].fn(s)
							OfferEv:FireClient(pl, nil)
							MsgEv:FireClient(pl, "Auto-picked: " .. CARDS[pick].name)
						end
					end
				end
			end
		end
	end
end, debug.traceback)
	if not ok0 then showErr(err0) end
end)

booting:Destroy()
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
	booting:Destroy()
	showErr(err)
end
