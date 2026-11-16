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

	-- Unit nameplate on the back wall, skirting, and a door.
	local plate = part(room, "Nameplate", Vector3.new(30, 3, 0.3), CFrame.new(floorCenter + Vector3.new(0, 18.5, -45.8)), Color3.fromRGB(30, 44, 70))
	local plateGui = Instance.new("SurfaceGui")
	plateGui.Face = Enum.NormalId.Back
	plateGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	plateGui.PixelsPerStud = 30
	plateGui.LightInfluence = 0
	plateGui.Parent = plate
	local plateText = Instance.new("TextLabel")
	plateText.Size = UDim2.fromScale(1, 1)
	plateText.BackgroundTransparency = 1
	plateText.Font = Enum.Font.SourceSansBold
	plateText.TextSize = 64
	plateText.TextColor3 = Color3.fromRGB(235, 235, 225)
	plateText.Text = "UNIT 1  -  RBMK-800  -  MAIN CONTROL ROOM"
	plateText.Parent = plateGui
	part(room, "Door", Vector3.new(6, 11, 0.4), CFrame.new(floorCenter + Vector3.new(30, 5.5, 45.9)), Color3.fromRGB(96, 104, 112), Enum.Material.Metal)
	part(room, "DoorFrame", Vector3.new(7, 11.6, 0.3), CFrame.new(floorCenter + Vector3.new(30, 5.8, 46.05)), Color3.fromRGB(60, 62, 66))
	for _, z in { -45.9, 45.9 } do
		part(room, "Skirting", Vector3.new(120, 0.8, 0.2), CFrame.new(floorCenter + Vector3.new(0, 0.4, z)), Color3.fromRGB(70, 72, 76))
	end
	-- Ceiling beams give the room some depth overhead.
	for ix = -3, 3 do
		part(room, "Beam", Vector3.new(1.2, 1.4, 92), CFrame.new(floorCenter + Vector3.new(ix * 17, height - 0.7, 0)), Color3.fromRGB(186, 186, 180)).CanCollide = false
	end

	-- Shift supervisor's desk in the middle of the horseshoe.
	part(room, "DeskTop", Vector3.new(14, 0.4, 5), CFrame.new(0, 3.2, -6), Color3.fromRGB(110, 88, 66), Enum.Material.Wood)
	part(room, "DeskBody", Vector3.new(13, 3, 4), CFrame.new(0, 1.5, -6), Color3.fromRGB(96, 100, 104))
	part(room, "DeskBinder", Vector3.new(1.6, 0.25, 2.1), CFrame.new(-3.5, 3.52, -6) * CFrame.Angles(0, 0.3, 0), Color3.fromRGB(160, 40, 36))
	part(room, "DeskPhone", Vector3.new(1.3, 0.5, 1.6), CFrame.new(4, 3.65, -6.4), Color3.fromRGB(36, 36, 40))
	part(room, "DeskLogbook", Vector3.new(2.2, 0.15, 1.6), CFrame.new(0.5, 3.48, -5.4) * CFrame.Angles(0, -0.15, 0), Color3.fromRGB(230, 228, 214))

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
		-- Hood over the annunciators, a kick rail along the bench front and
		-- a nameplate strip under the bench lip.
		part(room, p.id .. "_hood", Vector3.new(W + 0.2, 0.25, 2.2), frame(0, top + 0.12, -backZ + 0.75), CABINET_COLOR)
		part(room, p.id .. "_lip", Vector3.new(W, 0.35, 0.3), frame(0, h0 - 0.12, 0.1), Color3.fromRGB(60, 62, 64))
		local rail = part(room, p.id .. "_rail", Vector3.new(W - 1, 0.18, 0.18), frame(0, 1.0, 0.55), Color3.fromRGB(150, 150, 152), Enum.Material.Metal)
		rail.CanCollide = false
		for _, side in { -1, 1 } do
			part(room, p.id .. "_post", Vector3.new(0.18, 1.0, 0.18), frame(side * (W / 2 - 0.6), 0.5, 0.55), Color3.fromRGB(150, 150, 152), Enum.Material.Metal).CanCollide = false
		end
		-- Operator's chair in front of the bench.
		local seatColor = Color3.fromRGB(52, 58, 70)
		local chair = { { Vector3.new(2.0, 0.35, 2.0), 2.0, 5.2 }, { Vector3.new(2.0, 2.2, 0.3), 3.2, 6.2 }, { Vector3.new(0.3, 1.8, 0.3), 0.95, 5.2 }, { Vector3.new(1.8, 0.2, 1.8), 0.1, 5.2 } }
		for n, c in chair do
			local piece = part(room, p.id .. "_chair" .. n, c[1], frame(if p.index % 2 == 0 then -3 else 3, c[2], c[3]), if n <= 2 then seatColor else Color3.fromRGB(40, 40, 42))
			piece.CanCollide = n == 4
		end
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
