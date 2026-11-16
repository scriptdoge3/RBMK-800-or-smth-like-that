--!nonstrict
-- Builds the control room shell on the server: floor, walls, lighting and
-- the six benchboard cabinets. The cabinet faces are plain parts with known
-- names; each client dresses them with instruments and controls from the
-- shared layout.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local PanelLayout = require(Shared.PanelLayout)

local RoomBuilder = {}

local PANEL_COLOR = Color3.fromRGB(172, 182, 168)
local BENCH_COLOR = Color3.fromRGB(196, 196, 184)
local CABINET_COLOR = Color3.fromRGB(120, 128, 120)
local ANN_COLOR = Color3.fromRGB(40, 40, 42)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function RoomBuilder.build(): Folder
	local room = Instance.new("Folder")
	room.Name = "ControlRoom"

	-- Shell.
	local floorCenter = Vector3.new(0, 0, -14)
	part(room, "Floor", Vector3.new(120, 1, 92), CFrame.new(floorCenter + Vector3.new(0, -0.5, 0)), Color3.fromRGB(74, 80, 88), Enum.Material.Fabric)
	local height = 22
	part(room, "Ceiling", Vector3.new(120, 1, 92), CFrame.new(floorCenter + Vector3.new(0, height + 0.5, 0)), Color3.fromRGB(214, 214, 208))
	local wallColor = Color3.fromRGB(188, 186, 176)
	part(room, "WallNorth", Vector3.new(120, height, 1), CFrame.new(floorCenter + Vector3.new(0, height / 2, -46.5)), wallColor)
	part(room, "WallSouth", Vector3.new(120, height, 1), CFrame.new(floorCenter + Vector3.new(0, height / 2, 46.5)), wallColor)
	part(room, "WallWest", Vector3.new(1, height, 92), CFrame.new(floorCenter + Vector3.new(-60.5, height / 2, 0)), wallColor)
	part(room, "WallEast", Vector3.new(1, height, 92), CFrame.new(floorCenter + Vector3.new(60.5, height / 2, 0)), wallColor)
	-- Ceiling light panels.
	for ix = -2, 2 do
		for iz = -1, 1 do
			local light = part(room, "Light", Vector3.new(10, 0.3, 5), CFrame.new(floorCenter + Vector3.new(ix * 22, height - 0.2, iz * 26)), Color3.fromRGB(255, 252, 240), Enum.Material.Neon)
			light.CanCollide = false
			local glow = Instance.new("PointLight")
			glow.Range = 48
			glow.Brightness = 0.9
			glow.Color = Color3.fromRGB(255, 250, 235)
			glow.Shadows = false
			glow.Parent = light
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.2, 8)
	spawn.CFrame = CFrame.new(0, 0.1, 8)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Parent = room

	-- Shift supervisor's desk in the middle of the horseshoe.
	part(room, "DeskTop", Vector3.new(14, 0.4, 5), CFrame.new(0, 3.2, -6), Color3.fromRGB(110, 88, 66), Enum.Material.Wood)
	part(room, "DeskBody", Vector3.new(13, 3, 4), CFrame.new(0, 1.5, -6), Color3.fromRGB(96, 100, 104))

	-- Benchboards.
	local up = Vector3.new(0, 1, 0)
	local s = PanelLayout.BENCH_SLOPE
	local depth = PanelLayout.BENCH_DEPTH
	local h0 = PanelLayout.BENCH_FRONT_HEIGHT
	local W = PanelLayout.PANEL_WIDTH
	local T = PanelLayout.FACE_THICKNESS
	local backY = h0 + depth * math.sin(s)
	local backZ = depth * math.cos(s)
	local top = backY + PanelLayout.VERT_HEIGHT + PanelLayout.ANN_HEIGHT
	for _, p in PanelLayout.panels do
		local origin, right, back = PanelLayout.panelFrame(p.index)
		local function frame(x: number, y: number, z: number): CFrame
			return CFrame.fromMatrix(origin + right * x + up * y + back * z, right, up, back)
		end
		-- Cabinet: a base under the bench and a tall box behind it.
		part(room, p.id .. "_base", Vector3.new(W, h0, backZ), frame(0, h0 / 2, -backZ / 2), CABINET_COLOR)
		part(room, p.id .. "_cabinet", Vector3.new(W, top, 3), frame(0, top / 2, -backZ - 1.5 - T / 2), CABINET_COLOR)
		-- A slab under the sloping bench closes the gap at the sides.
		local bench = PanelLayout.face(p.index, "bench")
		local benchCF = PanelLayout.faceCFrame(bench)
		part(room, p.id .. "_slab", Vector3.new(W, depth, 1.6), benchCF * CFrame.new(0, 0, T / 2 + 0.8), CABINET_COLOR)
		for _, faceName in { "bench", "vert", "ann" } do
			local f = PanelLayout.face(p.index, faceName)
			local color = if faceName == "bench" then BENCH_COLOR elseif faceName == "ann" then ANN_COLOR else PANEL_COLOR
			local facePart = part(room, p.id .. "_" .. faceName, Vector3.new(f.width, f.height, T), PanelLayout.faceCFrame(f), color)
			facePart:SetAttribute("Panel", p.id)
			facePart:SetAttribute("Face", faceName)
		end
	end

	room.Parent = workspace
	return room
end

return RoomBuilder
