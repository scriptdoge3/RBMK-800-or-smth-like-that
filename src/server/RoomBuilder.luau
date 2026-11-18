--!nonstrict
-- Builds the control room shell on the server: floor, walls, ceiling, the
-- run of benchboard cabinets and the operators' console. The cabinet faces
-- are plain parts with known names; each client dresses them with
-- instruments and controls from the shared layout.
--
-- The look is an American-built control room of 1979, laid out and
-- furnished like a General Electric boiling-water-reactor plant of the day
-- and adapted to the RBMK: pale gray-green benchboards with black rubber
-- trim in an L around a square corner, the reactor panel set across the
-- corner itself, annunciator windows along the top, a waxed vinyl tile
-- floor, an acoustic tile ceiling with fluorescent troffers, and steel
-- office furniture: two operators' desks with key telephones, the process
-- computer's console with its two CRTs, a GE TermiNet alarm typer, the
-- shift supervisor's desk, steel shelving of procedures and a chalkboard.
-- Nothing in the room is later than 1979.
--
-- Everything is laid out in board units (see PanelLayout) and scaled to
-- studs at the end, so the room comes out life-size around a standard
-- character: bench front at hip height, desks at 0.76 m, ceiling at 3.8 m.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local PanelLayout = require(Shared.PanelLayout)

local RoomBuilder = {}

-- Board units per metre.
local M = 5.5

-- Benchboards in the pale gray-green GE used in the 1970s, with a black
-- rubber bumper along the bench and a black kick strip.
local PANEL_COLOR = Color3.fromRGB(178, 191, 180)
local BENCH_COLOR = Color3.fromRGB(184, 196, 186)
local CABINET_COLOR = Color3.fromRGB(162, 175, 165)
local BASE_COLOR = Color3.fromRGB(150, 163, 153)
local CAP_COLOR = Color3.fromRGB(122, 134, 126)
local RUBBER = Color3.fromRGB(34, 34, 36)
local ANN_COLOR = Color3.fromRGB(44, 44, 44)
local WOOD = Color3.fromRGB(104, 70, 46)
local DARK = Color3.fromRGB(40, 38, 38)
local FLOOR_TILE = Color3.fromRGB(186, 180, 164)
local WALL = Color3.fromRGB(226, 222, 208)
local TILE = Color3.fromRGB(232, 230, 222)
-- Steel office furniture: gray enamel with tan laminate tops.
local LAMINATE = Color3.fromRGB(204, 188, 150)
local DESK_STEEL = Color3.fromRGB(128, 132, 128)
local STEEL = Color3.fromRGB(150, 152, 150)
local CHROME = Color3.fromRGB(196, 198, 200)

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

local function prop(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = part(parent, name, size, cf, color, material)
	p.CanCollide = false
	return p
end

local function cylinderProp(parent: Instance, name: string, diameter: number, length: number, cf: CFrame, color: Color3, material: Enum.Material?): Part
	-- A cylinder's axis is its X axis.
	local p = prop(parent, name, Vector3.new(length, diameter, diameter), cf, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Text on the front of a part.
local function sign(target: BasePart, str: string, textSize: number, color: Color3, pixelsPerUnit: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerUnit or 30
	gui.LightInfluence = 0.6
	gui.Parent = target
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.SourceSansBold
	t.TextSize = textSize
	t.TextColor3 = color
	t.TextWrapped = true
	t.Text = str
	t.Parent = gui
	return t
end

-- An office swivel chair: upholstered seat and back, arms, a gas column and
-- a five-star base. `at` is the floor point under the seat; the sitter
-- faces -Z.
local function chair(parent: Instance, at: CFrame, fabric: Color3?)
	fabric = fabric or Color3.fromRGB(176, 92, 36)
	local seatY = 0.47 * M
	prop(parent, "ChairSeat", Vector3.new(0.48 * M, 0.08 * M, 0.46 * M), at * CFrame.new(0, seatY - 0.04 * M, 0), fabric, Enum.Material.Fabric)
	prop(parent, "ChairBack", Vector3.new(0.44 * M, 0.5 * M, 0.07 * M), at * CFrame.new(0, seatY + 0.33 * M, 0.25 * M) * CFrame.Angles(math.rad(-10), 0, 0), fabric, Enum.Material.Fabric)
	for _, side in { -1, 1 } do
		prop(parent, "ChairArm", Vector3.new(0.05 * M, 0.04 * M, 0.3 * M), at * CFrame.new(side * 0.26 * M, seatY + 0.2 * M, 0.02 * M), DARK)
		prop(parent, "ChairArmPost", Vector3.new(0.04 * M, 0.2 * M, 0.04 * M), at * CFrame.new(side * 0.26 * M, seatY + 0.1 * M, 0.08 * M), DARK)
	end
	prop(parent, "ChairColumn", Vector3.new(0.06 * M, seatY - 0.1 * M, 0.06 * M), at * CFrame.new(0, (seatY - 0.1 * M) / 2 + 0.05 * M, 0), CHROME, Enum.Material.Metal)
	for k = 0, 4 do
		prop(parent, "ChairLeg", Vector3.new(0.05 * M, 0.04 * M, 0.32 * M), at * CFrame.new(0, 0.06 * M, 0) * CFrame.Angles(0, k * math.pi * 2 / 5, 0) * CFrame.new(0, 0, 0.16 * M), DARK)
		prop(parent, "ChairCaster", Vector3.new(0.05 * M, 0.05 * M, 0.05 * M), at * CFrame.new(0, 0.025 * M, 0) * CFrame.Angles(0, k * math.pi * 2 / 5, 0) * CFrame.new(0, 0, 0.3 * M), DARK)
	end
end

-- The process computer's operator console: a gray steel desk-height
-- cabinet with a sloping keyboard shelf and a hood carrying two
-- green-phosphor CRTs. The client puts the unit summary on the left screen
-- and the alarm summary on the right. `at` is the floor point under the
-- middle of its front edge; the operator stands or sits on its +Z side.
local function computerConsole(parent: Instance, at: CFrame)
	local w, d = 1.5 * M, 0.75 * M
	local body = Color3.fromRGB(150, 154, 150)
	prop(parent, "ComputerBase", Vector3.new(w, 0.72 * M, d), at * CFrame.new(0, 0.36 * M, -d / 2), body)
	prop(parent, "ComputerKick", Vector3.new(w - 0.04 * M, 0.08 * M, d - 0.06 * M), at * CFrame.new(0, 0.04 * M, -d / 2 - 0.02 * M), RUBBER)
	-- Keyboard shelf, sloping toward the operator.
	prop(parent, "ComputerShelf", Vector3.new(w, 0.04 * M, 0.34 * M), at * CFrame.new(0, 0.76 * M, -0.17 * M) * CFrame.Angles(math.rad(-8), 0, 0), Color3.fromRGB(90, 92, 90))
	for k, x in { -0.37 * M, 0.37 * M } do
		prop(parent, "ComputerKeyboard", Vector3.new(0.5 * M, 0.035 * M, 0.2 * M), at * CFrame.new(x, 0.8 * M, -0.17 * M) * CFrame.Angles(math.rad(-8), 0, 0), Color3.fromRGB(196, 190, 170))
		prop(parent, "ComputerKeys", Vector3.new(0.44 * M, 0.012 * M, 0.15 * M), at * CFrame.new(x, 0.822 * M, -0.17 * M) * CFrame.Angles(math.rad(-8), 0, 0), Color3.fromRGB(70, 66, 60))
		-- The CRT in its hood, tipped back toward the operator's eyes.
		local hood = at * CFrame.new(x, 1.06 * M, -0.52 * M) * CFrame.Angles(math.rad(-12), 0, 0)
		prop(parent, "ComputerHood", Vector3.new(0.7 * M, 0.5 * M, 0.42 * M), hood, body)
		prop(parent, "ComputerBezel", Vector3.new(0.5 * M, 0.38 * M, 0.02 * M), hood * CFrame.new(0, 0, 0.21 * M), Color3.fromRGB(36, 36, 38))
		local screen = prop(parent, "DeskScreen" .. k, Vector3.new(0.34 * M, 0.26 * M, 0.01 * M), hood * CFrame.new(0, 0, 0.222 * M) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(8, 22, 12))
		screen:SetAttribute("DeskScreen", k)
	end
	local tag = prop(parent, "ComputerTag", Vector3.new(0.9 * M, 0.06 * M, 0.01 * M), at * CFrame.new(0, 1.36 * M, -0.36 * M) * CFrame.Angles(math.rad(-12), math.pi, 0), Color3.fromRGB(24, 24, 26))
	sign(tag, "PLANT PROCESS COMPUTER", 14, Color3.fromRGB(236, 236, 228), 60)
end

-- A steel office desk: tan laminate top with an aluminium edge, a gray
-- enamel body, a modesty panel and a three-drawer pedestal on the right.
-- `at` is the floor point under the middle of the desk; the user sits on
-- its +Z side.
local function steelDesk(parent: Instance, at: CFrame, length: number, depth: number)
	local h = 0.74 * M
	local top = 0.03 * M
	prop(parent, "DeskTop", Vector3.new(length, top, depth), at * CFrame.new(0, h - top / 2, 0), LAMINATE).CanCollide = true
	prop(parent, "DeskEdge", Vector3.new(length + 0.01 * M, top + 0.004 * M, 0.012 * M), at * CFrame.new(0, h - top / 2, depth / 2), CHROME, Enum.Material.Metal)
	prop(parent, "DeskModesty", Vector3.new(length - 0.04 * M, h - top - 0.12 * M, 0.02 * M), at * CFrame.new(0, (h - top) / 2 + 0.06 * M, -depth / 2 + 0.04 * M), DESK_STEEL, Enum.Material.Metal)
	local pw = 0.4 * M
	local px = length / 2 - pw / 2
	part(parent, "DeskPedestal", Vector3.new(pw, h - top, depth - 0.02 * M), at * CFrame.new(px, (h - top) / 2, 0), DESK_STEEL, Enum.Material.Metal)
	prop(parent, "DeskLeg", Vector3.new(0.04 * M, h - top, depth - 0.04 * M), at * CFrame.new(-length / 2 + 0.02 * M, (h - top) / 2, 0), DESK_STEEL, Enum.Material.Metal)
	for k = 0, 2 do
		prop(parent, "DrawerFront", Vector3.new(pw - 0.04 * M, 0.2 * M, 0.012 * M), at * CFrame.new(px, 0.13 * M + k * 0.22 * M, depth / 2 - 0.004 * M), Color3.fromRGB(140, 144, 140), Enum.Material.Metal)
		prop(parent, "DrawerPull", Vector3.new(0.14 * M, 0.02 * M, 0.02 * M), at * CFrame.new(px, 0.19 * M + k * 0.22 * M, depth / 2 + 0.006 * M), CHROME, Enum.Material.Metal)
	end
end

-- A key telephone of the period: a squat body with a rotary dial, a row of
-- clear line buttons along the front and the handset across the cradle.
-- The red one is the direct line, with no dial. `at` is the desk-top point
-- under it; it faces +Z.
local function telephone(parent: Instance, at: CFrame, color: Color3, hotline: boolean?)
	prop(parent, "Phone", Vector3.new(0.22 * M, 0.08 * M, 0.24 * M), at * CFrame.new(0, 0.04 * M, 0), color)
	if not hotline then
		cylinderProp(parent, "PhoneDial", 0.11 * M, 0.01 * M, at * CFrame.new(0, 0.085 * M, 0.03 * M) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(226, 224, 214))
		for i = 0, 5 do
			prop(parent, "PhoneKey", Vector3.new(0.022 * M, 0.025 * M, 0.02 * M), at * CFrame.new(-0.075 * M + i * 0.03 * M, 0.05 * M, 0.125 * M), if i == 5 then Color3.fromRGB(200, 40, 34) else Color3.fromRGB(236, 236, 228))
		end
	end
	prop(parent, "PhoneHandset", Vector3.new(0.22 * M, 0.05 * M, 0.06 * M), at * CFrame.new(0, 0.11 * M, -0.06 * M), color)
	prop(parent, "PhoneCord", Vector3.new(0.02 * M, 0.02 * M, 0.12 * M), at * CFrame.new(-0.12 * M, 0.06 * M, -0.08 * M), color)
end

-- The alarm typer: a GE TermiNet printing terminal on its pedestal, which
-- prints every event on fan-fold paper. `at` is the floor point under it;
-- the keyboard faces +Z.
local function teleprinter(parent: Instance, at: CFrame)
	local case = Color3.fromRGB(214, 208, 190)
	local h = 0.72 * M
	prop(parent, "PrinterStand", Vector3.new(0.7 * M, h, 0.55 * M), at * CFrame.new(0, h / 2, 0), Color3.fromRGB(84, 80, 74))
	prop(parent, "PrinterBody", Vector3.new(0.72 * M, 0.16 * M, 0.6 * M), at * CFrame.new(0, h + 0.08 * M, 0), case)
	prop(parent, "PrinterCover", Vector3.new(0.68 * M, 0.08 * M, 0.26 * M), at * CFrame.new(0, h + 0.2 * M, -0.14 * M), Color3.fromRGB(96, 88, 78))
	local badge = prop(parent, "PrinterBadge", Vector3.new(0.2 * M, 0.04 * M, 0.005 * M), at * CFrame.new(0.2 * M, h + 0.11 * M, 0.302 * M) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(40, 40, 40))
	sign(badge, "GE TermiNet", 12, Color3.fromRGB(230, 230, 220), 120)
	prop(parent, "PrinterKeys", Vector3.new(0.56 * M, 0.02 * M, 0.18 * M), at * CFrame.new(0, h + 0.17 * M, 0.18 * M) * CFrame.Angles(math.rad(8), 0, 0), Color3.fromRGB(52, 54, 52))
	-- The sheet rises out of the platen and leans back over the cover.
	local paper = prop(parent, "PrinterPaper", Vector3.new(0.58 * M, 0.42 * M, 0.005 * M), at * CFrame.new(0, h + 0.44 * M, -0.12 * M) * CFrame.Angles(math.rad(-12), math.pi, 0), Color3.fromRGB(240, 238, 224))
	paper:SetAttribute("PrinterPaper", true)
	prop(parent, "PaperStack", Vector3.new(0.6 * M, 0.12 * M, 0.42 * M), at * CFrame.new(0, 0.06 * M, -0.05 * M), Color3.fromRGB(236, 234, 220))
end

-- A row of upright binders on a surface, `at` under the first one; the
-- spines face +Z.
local function binders(parent: Instance, at: CFrame, count: number, seed: number)
	local colors = { Color3.fromRGB(30, 54, 110), Color3.fromRGB(150, 30, 30), Color3.fromRGB(28, 28, 30), Color3.fromRGB(30, 90, 60), Color3.fromRGB(96, 60, 30), Color3.fromRGB(40, 40, 46), Color3.fromRGB(200, 200, 190) }
	local x = 0
	for i = 1, count do
		local w = (0.05 + ((i * 7 + seed) % 4) * 0.012) * M
		local h = (0.29 + ((i * 3 + seed) % 2) * 0.03) * M
		prop(parent, "Binder", Vector3.new(w, h, 0.26 * M), at * CFrame.new(x + w / 2, h / 2, 0), colors[(i * 5 + seed) % #colors + 1])
		x += w + 0.004 * M
	end
end

-- Scale every part, light and sign in the room by `k` about the origin.
local function scaleRoom(room: Instance, k: number)
	for _, d in room:GetDescendants() do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			d.Size *= k
			d.CFrame = cf - cf.Position + cf.Position * k
		elseif d:IsA("SurfaceLight") or d:IsA("PointLight") or d:IsA("SpotLight") then
			d.Range *= k
		elseif d:IsA("SurfaceGui") and d.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud then
			d.PixelsPerStud /= k
		end
	end
end

function RoomBuilder.build(): Folder
	local room = Instance.new("Folder")
	room.Name = "ControlRoom"

	-- Shell: about 15 by 14 metres and 3.8 metres to the ceiling tiles.
	local west, east, north, south = -50, 34, -50, 28
	local width, length, height = east - west, south - north, 3.8 * M
	local cx, cz = (west + east) / 2, (north + south) / 2
	local floor = part(room, "Floor", Vector3.new(width, 1, length), CFrame.new(cx, -0.5, cz), FLOOR_TILE)
	floor.Reflectance = 0.04
	-- Twelve-inch vinyl tile joints.
	local tileJoint = Color3.fromRGB(160, 154, 138)
	local ft = 0.305 * M
	for x = west + ft, east - 0.1, ft do
		prop(room, "FloorJoint", Vector3.new(0.05, 0.02, length), CFrame.new(x, 0.01, cz), tileJoint)
	end
	for z = north + ft, south - 0.1, ft do
		prop(room, "FloorJoint", Vector3.new(width, 0.02, 0.05), CFrame.new(cx, 0.01, z), tileJoint)
	end
	part(room, "Ceiling", Vector3.new(width, 1, length), CFrame.new(cx, height + 0.5, cz), TILE, Enum.Material.Plaster)
	part(room, "WallNorth", Vector3.new(width, height, 1), CFrame.new(cx, height / 2, north - 0.5), WALL, Enum.Material.Plaster)
	part(room, "WallSouth", Vector3.new(width, height, 1), CFrame.new(cx, height / 2, south + 0.5), WALL, Enum.Material.Plaster)
	-- Walnut paneling on the south wall, in vertical boards.
	part(room, "Paneling", Vector3.new(width, height, 0.1), CFrame.new(cx, height / 2, south - 0.05), WOOD, Enum.Material.Wood)
	for x = west + 0.4 * M, east - 0.1, 0.4 * M do
		prop(room, "PanelGroove", Vector3.new(0.05, height, 0.02), CFrame.new(x, height / 2, south - 0.11), Color3.fromRGB(70, 46, 30))
	end
	part(room, "WallWest", Vector3.new(1, height, length), CFrame.new(west - 0.5, height / 2, cz), WALL, Enum.Material.Plaster)
	part(room, "WallEast", Vector3.new(1, height, length), CFrame.new(east + 0.5, height / 2, cz), WALL, Enum.Material.Plaster)
	-- Black rubber cove base.
	for _, z in { north + 0.06, south - 0.16 } do
		prop(room, "Skirting", Vector3.new(width, 0.55, 0.12), CFrame.new(cx, 0.275, z), RUBBER, Enum.Material.Rubber)
	end
	for _, x in { west + 0.06, east - 0.06 } do
		prop(room, "Skirting", Vector3.new(0.12, 0.55, length), CFrame.new(x, 0.275, cz), RUBBER, Enum.Material.Rubber)
	end

	-- Suspended ceiling: two-foot acoustic tiles in a white T-bar grid, with
	-- two-by-four fluorescent troffers.
	local tileSize = 0.61 * M
	local grid = Color3.fromRGB(214, 214, 208)
	for x = west + tileSize, east - 0.1, tileSize do
		prop(room, "CeilingGrid", Vector3.new(0.12, 0.08, length), CFrame.new(x, height - 0.04, cz), grid)
	end
	for z = north + tileSize, south - 0.1, tileSize do
		prop(room, "CeilingGrid", Vector3.new(width, 0.08, 0.12), CFrame.new(cx, height - 0.04, z), grid)
	end
	for ix = 0, 6 do
		for iz = 0, 5 do
			local x = west + tileSize * (1.5 + ix * 4)
			local z = north + tileSize * (2 + iz * 4)
			if x < east - tileSize and z < south - tileSize then
				prop(room, "TrofferFrame", Vector3.new(tileSize + 0.1, 0.1, 2 * tileSize + 0.1), CFrame.new(x, height - 0.05, z), Color3.fromRGB(236, 236, 230))
				local light = prop(room, "Light", Vector3.new(tileSize - 0.4, 0.06, 2 * tileSize - 0.4), CFrame.new(x, height - 0.1, z), Color3.fromRGB(255, 248, 232), Enum.Material.Neon)
				local glow = Instance.new("SurfaceLight")
				glow.Face = Enum.NormalId.Bottom
				glow.Angle = 140
				glow.Range = 34
				glow.Brightness = 1.15
				glow.Color = Color3.fromRGB(255, 246, 228)
				glow.Shadows = false
				glow.Parent = light
			end
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.2, 8)
	spawn.CFrame = CFrame.new(14, 0.1, 18)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Parent = room

	-- The door, a sign over it, and a clock above the boards.
	local doorX = 22
	part(room, "Door", Vector3.new(0.9 * M, 2.1 * M, 0.25), CFrame.new(doorX, 1.05 * M, south - 0.12), Color3.fromRGB(126, 96, 70), Enum.Material.Wood)
	prop(room, "DoorFrame", Vector3.new(1.0 * M, 2.16 * M, 0.15), CFrame.new(doorX, 1.08 * M, south - 0.12), DARK)
	cylinderProp(room, "DoorHandle", 0.05 * M, 0.1 * M, CFrame.new(doorX - 0.36 * M, 1.0 * M, south - 0.3) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(190, 180, 150), Enum.Material.Metal)
	local doorSign = prop(room, "DoorSign", Vector3.new(1.4 * M, 0.25 * M, 0.08), CFrame.new(doorX, 2.85 * M, south - 0.2) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(24, 24, 26))
	sign(doorSign, "UNIT 1 MAIN CONTROL ROOM", 22, Color3.fromRGB(240, 240, 230))
	local clockX, clockY, clockZ = -6, 3.25 * M, north + 0.1
	cylinderProp(room, "WallClockRim", 0.4 * M, 0.06 * M, CFrame.new(clockX, clockY, clockZ) * CFrame.Angles(0, math.pi / 2, 0), DARK)
	cylinderProp(room, "WallClock", 0.36 * M, 0.08 * M, CFrame.new(clockX, clockY, clockZ + 0.02) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(242, 240, 230))
	for i = 0, 11 do
		local a = i * math.pi / 6
		prop(room, "ClockMark", Vector3.new(0.03 * M, if i % 3 == 0 then 0.04 * M else 0.025 * M, 0.02), CFrame.new(clockX + math.sin(a) * 0.15 * M, clockY + math.cos(a) * 0.15 * M, clockZ + 0.27) * CFrame.Angles(0, 0, -a), DARK)
	end
	prop(room, "ClockHand", Vector3.new(0.02 * M, 0.12 * M, 0.02), CFrame.new(clockX, clockY + 0.05 * M, clockZ + 0.3), DARK)
	prop(room, "ClockHand", Vector3.new(0.09 * M, 0.02 * M, 0.02), CFrame.new(clockX + 0.04 * M, clockY, clockZ + 0.3), DARK)

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
	local cabinetDepth = 3.2
	local n = #PanelLayout.panels
	for _, p in PanelLayout.panels do
		local origin, right, back = PanelLayout.designFrame(p.index)
		local function frame(x: number, y: number, z: number): CFrame
			return CFrame.fromMatrix(origin + right * x + up * y + back * z, right, up, back)
		end
		-- Cabinet: a base under the bench, a tall box behind it, and a
		-- slab under the sloping bench that closes the gap at the sides.
		part(room, p.id .. "_base", Vector3.new(W, h0 - 0.5, backZ - 0.3), frame(0, 0.5 + (h0 - 0.5) / 2, -backZ / 2 - 0.15), BASE_COLOR)
		part(room, p.id .. "_kick", Vector3.new(W, 0.5, backZ - 0.6), frame(0, 0.25, -backZ / 2 - 0.3), RUBBER, Enum.Material.Rubber)
		part(room, p.id .. "_cabinet", Vector3.new(W, top, cabinetDepth), frame(0, top / 2, -backZ - cabinetDepth / 2 - T / 2), CABINET_COLOR)
		local bench = PanelLayout.designFace(p.index, "bench")
		part(room, p.id .. "_slab", Vector3.new(W, depth, 1.6), PanelLayout.faceCFrame(bench) * CFrame.new(0, 0, T / 2 + 0.8), CABINET_COLOR)
		-- Trim: a black rubber bumper along the bench front and a darker
		-- cap over the annunciators.
		part(room, p.id .. "_lip", Vector3.new(W, 0.4, 0.45), frame(0, h0 - 0.1, 0.12), RUBBER, Enum.Material.Rubber)
		prop(room, p.id .. "_cap", Vector3.new(W, 0.3, cabinetDepth + 1.4), frame(0, top + 0.15, -backZ - cabinetDepth / 2 + 0.55), CAP_COLOR)
		-- A dark reveal between the board and the annunciator box.
		prop(room, p.id .. "_reveal", Vector3.new(W, 0.12, 0.2), frame(0, backY + PanelLayout.VERT_HEIGHT, -backZ + T / 2 + 0.06), DARK)
		for _, faceName in { "bench", "vert", "ann" } do
			local f = PanelLayout.designFace(p.index, faceName)
			local color = if faceName == "bench" then BENCH_COLOR elseif faceName == "ann" then ANN_COLOR else PANEL_COLOR
			local facePart = part(room, p.id .. "_" .. faceName, Vector3.new(f.width, f.height, T), PanelLayout.faceCFrame(f), color)
			facePart:SetAttribute("Panel", p.id)
			facePart:SetAttribute("Face", faceName)
		end

		-- Joint with the next panel: a seam strip where the run is straight,
		-- a corner filler where it turns.
		if p.index < n then
			local nOrigin, nRight, nBack = PanelLayout.designFrame(p.index + 1)
			local joint = origin + right * (W / 2)
			local turn = math.acos(math.clamp(back:Dot(nBack), -1, 1))
			if turn < 0.01 then
				prop(room, p.id .. "_seam", Vector3.new(0.1, PanelLayout.VERT_HEIGHT, 0.06), CFrame.fromMatrix(joint + up * (backY + PanelLayout.VERT_HEIGHT / 2) - back * (backZ - T / 2 - 0.03), right, up, back), DARK)
			else
				-- An inside corner. Each cabinet is carried on, blank, past
				-- the joint until it meets the other one: boards, bench,
				-- annunciator box and all. Where the two benches overlap, the
				-- higher one shows, which is exactly the mitred valley a real
				-- corner joint has.
				local half = turn / 2
				local ext = backZ * math.tan(half)
				local extCab = (backZ + cabinetDepth + T) * math.tan(half)
				for _, side in { { origin, right, back, 1 }, { nOrigin, nRight, nBack, -1 } } do
					local o, r, b, dir = side[1], side[2], side[3], side[4]
					local tag = p.id .. (if dir > 0 then "_cornerA" else "_cornerB")
					local function at(x: number, y: number, z: number): CFrame
						return CFrame.fromMatrix(o + r * (dir * (W / 2 + x)) + up * y + b * z, r, up, b)
					end
					part(room, tag .. "Cabinet", Vector3.new(extCab, top, cabinetDepth), at(extCab / 2, top / 2, -backZ - cabinetDepth / 2 - T / 2), CABINET_COLOR)
					part(room, tag .. "Board", Vector3.new(ext, PanelLayout.VERT_HEIGHT, T), at(ext / 2, backY + PanelLayout.VERT_HEIGHT / 2, -backZ), PANEL_COLOR)
					part(room, tag .. "Ann", Vector3.new(ext, PanelLayout.ANN_HEIGHT, T), at(ext / 2, backY + PanelLayout.VERT_HEIGHT + PanelLayout.ANN_HEIGHT / 2, -backZ), ANN_COLOR)
					prop(room, tag .. "Reveal", Vector3.new(ext, 0.12, 0.2), at(ext / 2, backY + PanelLayout.VERT_HEIGHT, -backZ + T / 2 + 0.06), DARK)
					part(room, tag .. "Base", Vector3.new(ext, h0 - 0.1, backZ), at(ext / 2, (h0 - 0.1) / 2, -backZ / 2), BASE_COLOR)
					prop(room, tag .. "Cap", Vector3.new(extCab, 0.3, cabinetDepth + 1.4), at(extCab / 2, top + 0.15, -backZ - cabinetDepth / 2 + 0.55), CAP_COLOR)
					-- Bench carried on at the same slope.
					local slopeUp = up * math.sin(s) - b * math.cos(s)
					local slopeNormal = up * math.cos(s) + b * math.sin(s)
					local centre = o + r * (dir * (W / 2 + ext / 2)) + up * (h0 + depth / 2 * math.sin(s)) - b * (depth / 2 * math.cos(s)) - slopeNormal * 0.6
					part(room, tag .. "Bench", Vector3.new(ext, depth, 1.2 + T), CFrame.fromMatrix(centre, slopeUp:Cross(-slopeNormal), slopeUp, -slopeNormal), BENCH_COLOR)
				end
			end
		end
	end

	-- Behind the corner section: the triangle between its cabinet and the
	-- square corner where the backs of the two runs meet is filled solid and
	-- capped, so the boards read as one L with a square back corner.
	do
		local cabinetBack = backZ + T / 2 + cabinetDepth
		local cOrigin, _, cBack = PanelLayout.designFrame(PanelLayout.CORNER_PANEL)
		local x0 = PanelLayout.CORNER_X - cabinetBack
		local z0 = PanelLayout.BACK_WALL_Z - cabinetBack
		-- The corner cabinet's back plane is p . cBack = k; find where it
		-- crosses the back planes of the two runs. A little extra pushes the
		-- long face of the filler inside the corner cabinet.
		local k = cOrigin:Dot(cBack) - cabinetBack
		local legX = (k - z0 * cBack.Z) / cBack.X - x0 + 0.2
		local legZ = (k - x0 * cBack.X) / cBack.Z - z0 + 0.2
		local function filler(name: string, y0: number, fillHeight: number, color: Color3, material: Enum.Material?)
			-- A wedge's right angle is at its bottom back edge; stand it on end
			-- so that edge is the vertical line of the square corner.
			local w = Instance.new("WedgePart")
			w.Name = name
			w.Anchored = true
			w.Size = Vector3.new(fillHeight, legX, legZ)
			w.CFrame = CFrame.fromMatrix(Vector3.new(x0 + legX / 2, y0 + fillHeight / 2, z0 + legZ / 2), Vector3.new(0, 1, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, -1))
			w.Color = color
			w.Material = material or Enum.Material.SmoothPlastic
			w.TopSurface = Enum.SurfaceType.Smooth
			w.BottomSurface = Enum.SurfaceType.Smooth
			w.Parent = room
		end
		filler("CornerFill", 0, top, CABINET_COLOR)
		filler("CornerCap", top, 0.3, CAP_COLOR)
	end

	-- The operators' area, facing the corner so the reactor panel is straight
	-- ahead: two steel desks side by side, the process computer's console
	-- to their left and the alarm typer to their right.
	local area = CFrame.new(PanelLayout.DESK_X, 0, PanelLayout.DESK_Z) * CFrame.Angles(0, PanelLayout.DESK_YAW, 0)
	local deskL, deskD, deskH = 1.52 * M, 0.76 * M, 0.74 * M
	for k, x in { -0.8 * M, 0.8 * M } do
		local at = area * CFrame.new(x, 0, 0)
		steelDesk(room, at, deskL, deskD)
		local top = at * CFrame.new(0, deskH, 0)
		telephone(room, top * CFrame.new(-0.5 * M, 0, -0.2 * M) * CFrame.Angles(0, 0.15, 0), Color3.fromRGB(28, 28, 30))
		if k == 1 then
			telephone(room, top * CFrame.new(0.05 * M, 0, -0.22 * M), Color3.fromRGB(160, 30, 28), true)
			prop(room, "Logbook", Vector3.new(0.3 * M, 0.03 * M, 0.38 * M), top * CFrame.new(0.15 * M, 0.015 * M, 0.12 * M) * CFrame.Angles(0, 0.1, 0), Color3.fromRGB(36, 60, 44))
			prop(room, "Papers", Vector3.new(0.21 * M, 0.006 * M, 0.3 * M), top * CFrame.new(0.55 * M, 0.003 * M, 0.05 * M) * CFrame.Angles(0, -0.12, 0), Color3.fromRGB(240, 238, 226))
			cylinderProp(room, "Mug", 0.08 * M, 0.1 * M, top * CFrame.new(-0.2 * M, 0.05 * M, 0.2 * M) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(230, 230, 226))
		else
			binders(room, top * CFrame.new(0.25 * M, 0, -0.24 * M), 6, 2)
			prop(room, "Logbook", Vector3.new(0.3 * M, 0.03 * M, 0.38 * M), top * CFrame.new(-0.05 * M, 0.015 * M, 0.12 * M) * CFrame.Angles(0, -0.15, 0), Color3.fromRGB(110, 32, 30))
			prop(room, "Clipboard", Vector3.new(0.23 * M, 0.01 * M, 0.32 * M), top * CFrame.new(-0.5 * M, 0.005 * M, 0.15 * M) * CFrame.Angles(0, 0.1, 0), Color3.fromRGB(150, 110, 70), Enum.Material.Wood)
		end
		cylinderProp(room, "Ashtray", 0.13 * M, 0.025 * M, top * CFrame.new(0.62 * M, 0.0125 * M, -0.22 * M) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(120, 86, 40), Enum.Material.Glass).Transparency = 0.2
		chair(room, at * CFrame.new(-0.1 * M, 0, deskD / 2 + 0.4 * M))
	end
	computerConsole(room, area * CFrame.new(-2.45 * M, 0, 0.55 * M) * CFrame.Angles(0, 0.45, 0))
	chair(room, area * CFrame.new(-2.2 * M, 0, 1.15 * M) * CFrame.Angles(0, 0.45, 0))
	teleprinter(room, area * CFrame.new(2.3 * M, 0, 0.35 * M) * CFrame.Angles(0, -0.5, 0))
	-- A floor-standing ashtray between the desks and the typer.
	do
		local stand = area * CFrame.new(1.75 * M, 0, 0.95 * M)
		cylinderProp(room, "SmokingStandBase", 0.3 * M, 0.03 * M, stand * CFrame.new(0, 0.015 * M, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(40, 40, 42))
		cylinderProp(room, "SmokingStandPost", 0.04 * M, 0.6 * M, stand * CFrame.new(0, 0.32 * M, 0) * CFrame.Angles(0, 0, math.pi / 2), CHROME, Enum.Material.Metal)
		cylinderProp(room, "SmokingStandTray", 0.22 * M, 0.05 * M, stand * CFrame.new(0, 0.64 * M, 0) * CFrame.Angles(0, 0, math.pi / 2), CHROME, Enum.Material.Metal)
	end

	-- The shift supervisor's desk behind the operators, facing the boards.
	do
		local ss = CFrame.new(10, 0, 10) * CFrame.Angles(0, PanelLayout.DESK_YAW, 0)
		steelDesk(room, ss, 1.52 * M, 0.76 * M)
		local top2 = ss * CFrame.new(0, deskH, 0)
		telephone(room, top2 * CFrame.new(0.5 * M, 0, -0.18 * M), Color3.fromRGB(28, 28, 30))
		prop(room, "Logbook", Vector3.new(0.3 * M, 0.03 * M, 0.38 * M), top2 * CFrame.new(-0.1 * M, 0.015 * M, 0.08 * M) * CFrame.Angles(0, 0.15, 0), Color3.fromRGB(30, 54, 110))
		prop(room, "InTray", Vector3.new(0.26 * M, 0.06 * M, 0.34 * M), top2 * CFrame.new(-0.52 * M, 0.03 * M, -0.12 * M), Color3.fromRGB(60, 60, 64))
		prop(room, "LampBase", Vector3.new(0.14 * M, 0.03 * M, 0.14 * M), top2 * CFrame.new(-0.25 * M, 0.015 * M, -0.27 * M), DARK)
		prop(room, "LampArm", Vector3.new(0.02 * M, 0.38 * M, 0.02 * M), top2 * CFrame.new(-0.25 * M, 0.2 * M, -0.27 * M), DARK)
		prop(room, "LampShade", Vector3.new(0.18 * M, 0.08 * M, 0.12 * M), top2 * CFrame.new(-0.25 * M, 0.38 * M, -0.2 * M) * CFrame.Angles(math.rad(25), 0, 0), Color3.fromRGB(40, 70, 50))
		chair(room, ss * CFrame.new(-0.1 * M, 0, 0.78 * M), Color3.fromRGB(96, 62, 40))
	end

	-- Along the south wall: steel shelving of procedures and two file
	-- cabinets.
	do
		local bx, bz = -32, south - 0.2 * M - 0.1
		local bw, bh, bd = 1.8 * M, 1.95 * M, 0.35 * M
		local shelving = Color3.fromRGB(140, 144, 138)
		local case = CFrame.new(bx, 0, bz) * CFrame.Angles(0, math.pi, 0)
		part(room, "ShelvingBack", Vector3.new(bw, bh, 0.02 * M), case * CFrame.new(0, bh / 2, bd / 2 - 0.01 * M), shelving, Enum.Material.Metal)
		for _, side in { -1, 1 } do
			part(room, "ShelvingSide", Vector3.new(0.02 * M, bh, bd), case * CFrame.new(side * (bw / 2 - 0.01 * M), bh / 2, 0), shelving, Enum.Material.Metal)
		end
		for shelf = 0, 5 do
			local y = 0.08 * M + shelf * 0.37 * M
			part(room, "Shelf", Vector3.new(bw, 0.02 * M, bd), case * CFrame.new(0, y, 0), shelving, Enum.Material.Metal)
			if shelf < 5 then
				binders(room, case * CFrame.new(-bw / 2 + 0.04 * M, y + 0.01 * M, 0.02 * M), 14 + shelf % 3, shelf * 3)
			end
		end
		for i = 0, 1 do
			local fx = bx + bw / 2 + 0.6 * M + i * 0.5 * M
			local cab = CFrame.new(fx, 0, south - 0.36 * M - 0.1) * CFrame.Angles(0, math.pi, 0)
			part(room, "FileCabinet", Vector3.new(0.46 * M, 1.33 * M, 0.7 * M), cab * CFrame.new(0, 0.665 * M, 0), Color3.fromRGB(150, 140, 112), Enum.Material.Metal)
			for d = 0, 3 do
				prop(room, "FilePull", Vector3.new(0.12 * M, 0.03 * M, 0.03 * M), cab * CFrame.new(0, 0.25 * M + d * 0.31 * M, -0.36 * M), CHROME, Enum.Material.Metal)
			end
		end
	end

	-- On the east wall: the shift chalkboard. By the door: a fire
	-- extinguisher and a lit exit sign.
	do
		local board = prop(room, "StatusBoard", Vector3.new(2.4 * M, 1.2 * M, 0.05 * M), CFrame.new(east - 0.2, 1.55 * M, -10) * CFrame.Angles(0, -math.pi / 2, 0), Color3.fromRGB(44, 72, 56))
		board:SetAttribute("StatusBoard", true)
		prop(room, "StatusBoardFrame", Vector3.new(2.46 * M, 1.26 * M, 0.03 * M), CFrame.new(east - 0.08, 1.55 * M, -10) * CFrame.Angles(0, -math.pi / 2, 0), Color3.fromRGB(176, 178, 176), Enum.Material.Metal)
		prop(room, "ChalkTray", Vector3.new(2.4 * M, 0.03 * M, 0.06 * M), CFrame.new(east - 0.35, 0.93 * M, -10) * CFrame.Angles(0, -math.pi / 2, 0), Color3.fromRGB(176, 178, 176), Enum.Material.Metal)
		prop(room, "Chalk", Vector3.new(0.08 * M, 0.012 * M, 0.012 * M), CFrame.new(east - 0.35, 0.95 * M, -12) * CFrame.Angles(0, -math.pi / 2, 0), Color3.fromRGB(246, 246, 240))
		prop(room, "Eraser", Vector3.new(0.13 * M, 0.03 * M, 0.05 * M), CFrame.new(east - 0.35, 0.96 * M, -7) * CFrame.Angles(0, -math.pi / 2, 0), Color3.fromRGB(120, 92, 60))
		local ex = CFrame.new(doorX - 1.0 * M, 0, south - 0.15 * M - 0.1)
		cylinderProp(room, "Extinguisher", 0.16 * M, 0.5 * M, ex * CFrame.new(0, 0.65 * M, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(190, 24, 20))
		prop(room, "ExtinguisherHead", Vector3.new(0.06 * M, 0.1 * M, 0.06 * M), ex * CFrame.new(0, 0.95 * M, 0), DARK)
		local fireSign = prop(room, "FireSign", Vector3.new(0.3 * M, 0.15 * M, 0.02 * M), ex * CFrame.new(0, 1.3 * M, 0.12 * M) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(190, 24, 20))
		sign(fireSign, "FIRE", 18, Color3.fromRGB(255, 255, 255))
		local exit = prop(room, "ExitSign", Vector3.new(0.36 * M, 0.18 * M, 0.06 * M), CFrame.new(doorX, 2.32 * M, south - 0.25) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(236, 232, 220))
		local exitText = sign(exit, "EXIT", 26, Color3.fromRGB(230, 30, 24), 60)
		exitText.Parent.LightInfluence = 0
	end

	scaleRoom(room, PanelLayout.SCALE)
	room.Parent = workspace
	return room
end

return RoomBuilder
