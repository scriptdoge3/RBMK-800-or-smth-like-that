--!nonstrict
-- Builds the control room shell on the server: floor, walls, lighting, the
-- run of benchboard cabinets and the operators' desk. The cabinet faces are
-- plain parts with known names; each client dresses them with instruments
-- and controls from the shared layout.
--
-- The look follows an American boiling-water-reactor control room of the
-- late 1970s and early 1980s: cream boards with wood trim, an L of panels
-- meeting at a square corner, annunciator boxes along the top, a dark
-- ceiling with fluorescent troffers, and an operators' desk with the things
-- of the period on it: a green-screen terminal, an alarm teleprinter,
-- telephones, binders and logbooks. Nothing here is later than 1985.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local PanelLayout = require(Shared.PanelLayout)

local RoomBuilder = {}

local PANEL_COLOR = Color3.fromRGB(226, 212, 172)
local BENCH_COLOR = Color3.fromRGB(224, 209, 168)
local CABINET_COLOR = Color3.fromRGB(208, 194, 156)
local ANN_COLOR = Color3.fromRGB(44, 40, 38)
local WOOD = Color3.fromRGB(116, 62, 42)
local DARK = Color3.fromRGB(40, 38, 38)
local CARPET = Color3.fromRGB(104, 44, 40)
local DESK = Color3.fromRGB(214, 200, 164)
local CRT = Color3.fromRGB(205, 198, 178)

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

-- A swivel chair: seat, back, column and a five-star base.
local function chair(parent: Instance, at: CFrame)
	local fabric = Color3.fromRGB(70, 74, 86)
	prop(parent, "ChairSeat", Vector3.new(2.1, 0.4, 2.1), at * CFrame.new(0, 2.0, 0), fabric, Enum.Material.Fabric)
	prop(parent, "ChairBack", Vector3.new(2.0, 2.4, 0.35), at * CFrame.new(0, 3.5, 1.05) * CFrame.Angles(math.rad(-8), 0, 0), fabric, Enum.Material.Fabric)
	prop(parent, "ChairArm", Vector3.new(0.25, 0.2, 1.6), at * CFrame.new(-1.15, 2.75, 0.1), DARK)
	prop(parent, "ChairArm", Vector3.new(0.25, 0.2, 1.6), at * CFrame.new(1.15, 2.75, 0.1), DARK)
	prop(parent, "ChairColumn", Vector3.new(0.3, 1.5, 0.3), at * CFrame.new(0, 1.05, 0), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
	for k = 0, 4 do
		prop(parent, "ChairLeg", Vector3.new(0.25, 0.18, 1.3), at * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, k * math.pi * 2 / 5, 0) * CFrame.new(0, 0, 0.65), DARK)
	end
end

-- A late-1970s video terminal: one moulded case with the keyboard built in
-- and a small green-phosphor tube. The client puts live data on the screen.
local function terminal(parent: Instance, at: CFrame, index: number)
	local case = Color3.fromRGB(198, 190, 168)
	prop(parent, "TerminalCase", Vector3.new(3.4, 2.6, 2.6), at * CFrame.new(0, 1.6, -0.3), case)
	prop(parent, "TerminalKeys", Vector3.new(3.4, 0.6, 1.8), at * CFrame.new(0, 0.3, 1.5), case)
	prop(parent, "TerminalKeyboard", Vector3.new(2.8, 0.12, 1.2), at * CFrame.new(0, 0.66, 1.55) * CFrame.Angles(math.rad(6), 0, 0), Color3.fromRGB(60, 58, 54))
	prop(parent, "TerminalBezel", Vector3.new(2.7, 2.0, 0.12), at * CFrame.new(0, 1.7, 1.02), Color3.fromRGB(46, 44, 42))
	local screen = prop(parent, "DeskScreen" .. index, Vector3.new(2.3, 1.6, 0.1), at * CFrame.new(0, 1.7, 1.06) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(8, 20, 12))
	screen:SetAttribute("DeskScreen", index)
end

-- The alarm typer: a teleprinter that prints every event on fan-fold paper.
-- The client prints the unit's event log on the sheet.
local function teleprinter(parent: Instance, at: CFrame)
	local case = Color3.fromRGB(150, 156, 150)
	prop(parent, "PrinterBody", Vector3.new(4.2, 1.3, 3.2), at * CFrame.new(0, 0.65, 0), case)
	prop(parent, "PrinterCover", Vector3.new(4.2, 0.5, 1.4), at * CFrame.new(0, 1.5, -0.9), Color3.fromRGB(70, 74, 72))
	prop(parent, "PrinterPlaten", Vector3.new(3.6, 0.3, 0.3), at * CFrame.new(0, 1.42, -0.1), Color3.fromRGB(30, 30, 32))
	prop(parent, "PrinterKeys", Vector3.new(3.4, 0.2, 1.0), at * CFrame.new(0, 1.36, 0.95) * CFrame.Angles(math.rad(8), 0, 0), Color3.fromRGB(52, 54, 52))
	-- The sheet rises out of the platen and leans back over the cover.
	local paper = prop(parent, "PrinterPaper", Vector3.new(3.3, 2.6, 0.04), at * CFrame.new(0, 2.6, -0.55) * CFrame.Angles(math.rad(-14), math.pi, 0), Color3.fromRGB(240, 238, 224))
	paper:SetAttribute("PrinterPaper", true)
	prop(parent, "PaperStack", Vector3.new(3.4, 0.5, 2.4), at * CFrame.new(0, 0.25, -3.2), Color3.fromRGB(236, 234, 220))
end

function RoomBuilder.build(): Folder
	local room = Instance.new("Folder")
	room.Name = "ControlRoom"

	-- Shell.
	local centre = Vector3.new(-2, 0, -9)
	local width, length, height = 92, 80, 18
	part(room, "Floor", Vector3.new(width, 1, length), CFrame.new(centre + Vector3.new(0, -0.5, 0)), CARPET, Enum.Material.Fabric)
	part(room, "Ceiling", Vector3.new(width, 1, length), CFrame.new(centre + Vector3.new(0, height + 0.5, 0)), Color3.fromRGB(62, 60, 58))
	local wallColor = Color3.fromRGB(206, 196, 172)
	local north, south = centre.Z - length / 2, centre.Z + length / 2
	local west, east = centre.X - width / 2, centre.X + width / 2
	part(room, "WallNorth", Vector3.new(width, height, 1), CFrame.new(centre.X, height / 2, north - 0.5), wallColor)
	part(room, "WallSouth", Vector3.new(width, height, 1), CFrame.new(centre.X, height / 2, south + 0.5), wallColor)
	part(room, "WallWest", Vector3.new(1, height, length), CFrame.new(west - 0.5, height / 2, centre.Z), wallColor)
	part(room, "WallEast", Vector3.new(1, height, length), CFrame.new(east + 0.5, height / 2, centre.Z), wallColor)
	for _, z in { north + 0.1, south - 0.1 } do
		prop(room, "Skirting", Vector3.new(width, 0.9, 0.2), CFrame.new(centre.X, 0.45, z), WOOD, Enum.Material.Wood)
	end
	for _, x in { west + 0.1, east - 0.1 } do
		prop(room, "Skirting", Vector3.new(0.2, 0.9, length), CFrame.new(x, 0.45, centre.Z), WOOD, Enum.Material.Wood)
	end
	-- Suspended ceiling grid with fluorescent troffers.
	for ix = -2, 2 do
		prop(room, "CeilingRib", Vector3.new(0.5, 0.5, length), CFrame.new(centre.X + ix * 18, height - 0.25, centre.Z), Color3.fromRGB(44, 42, 40))
	end
	for iz = -2, 2 do
		prop(room, "CeilingRib", Vector3.new(width, 0.5, 0.5), CFrame.new(centre.X, height - 0.25, centre.Z + iz * 16), Color3.fromRGB(44, 42, 40))
	end
	for ix = -2, 2 do
		for iz = -2, 1 do
			local light = prop(room, "Light", Vector3.new(9, 0.25, 4.5), CFrame.new(centre.X + ix * 18, height - 0.14, centre.Z + iz * 16 + 8), Color3.fromRGB(255, 244, 214), Enum.Material.Neon)
			local glow = Instance.new("SurfaceLight")
			glow.Face = Enum.NormalId.Bottom
			glow.Angle = 150
			glow.Range = 34
			glow.Brightness = 1.6
			glow.Color = Color3.fromRGB(255, 240, 210)
			glow.Shadows = false
			glow.Parent = light
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.2, 8)
	spawn.CFrame = CFrame.new(4, 0.1, 14)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Parent = room

	-- Unit nameplate and a door on the south wall.
	local plate = part(room, "Nameplate", Vector3.new(34, 2.6, 0.3), CFrame.new(centre.X, height - 2.4, south - 0.2), Color3.fromRGB(24, 24, 26))
	local plateGui = Instance.new("SurfaceGui")
	plateGui.Face = Enum.NormalId.Front
	plateGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	plateGui.PixelsPerStud = 30
	plateGui.LightInfluence = 0
	plateGui.Parent = plate
	local plateText = Instance.new("TextLabel")
	plateText.Size = UDim2.fromScale(1, 1)
	plateText.BackgroundTransparency = 1
	plateText.Font = Enum.Font.SourceSansBold
	plateText.TextSize = 56
	plateText.TextColor3 = Color3.fromRGB(240, 240, 230)
	plateText.Text = "UNIT 1    RBMK-800    MAIN CONTROL ROOM"
	plateText.Parent = plateGui
	part(room, "Door", Vector3.new(6, 11, 0.4), CFrame.new(east - 12, 5.5, south - 0.2), Color3.fromRGB(126, 96, 70), Enum.Material.Wood)
	prop(room, "DoorFrame", Vector3.new(7, 11.6, 0.3), CFrame.new(east - 12, 5.8, south - 0.05), DARK)
	-- A plain round wall clock over the door.
	local clock = prop(room, "WallClock", Vector3.new(0.3, 3, 3), CFrame.new(east - 12, 14, south - 0.2) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(240, 238, 228))
	clock.Shape = Enum.PartType.Cylinder
	local rim = prop(room, "WallClockRim", Vector3.new(0.2, 3.3, 3.3), CFrame.new(east - 12, 14, south - 0.12) * CFrame.Angles(0, math.pi / 2, 0), DARK)
	rim.Shape = Enum.PartType.Cylinder
	prop(room, "ClockHand", Vector3.new(0.12, 1.2, 0.05), CFrame.new(east - 12, 14.5, south - 0.38), DARK)
	prop(room, "ClockHand", Vector3.new(0.9, 0.12, 0.05), CFrame.new(east - 12.4, 14, south - 0.38), DARK)

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
		local origin, right, back = PanelLayout.panelFrame(p.index)
		local function frame(x: number, y: number, z: number): CFrame
			return CFrame.fromMatrix(origin + right * x + up * y + back * z, right, up, back)
		end
		-- Cabinet: a base under the bench, a tall box behind it, and a
		-- slab under the sloping bench that closes the gap at the sides.
		part(room, p.id .. "_base", Vector3.new(W, h0 - 0.5, backZ - 0.3), frame(0, 0.5 + (h0 - 0.5) / 2, -backZ / 2 - 0.15), CABINET_COLOR)
		part(room, p.id .. "_kick", Vector3.new(W, 0.5, backZ - 0.6), frame(0, 0.25, -backZ / 2 - 0.3), WOOD, Enum.Material.Wood)
		part(room, p.id .. "_cabinet", Vector3.new(W, top, cabinetDepth), frame(0, top / 2, -backZ - cabinetDepth / 2 - T / 2), CABINET_COLOR)
		local bench = PanelLayout.face(p.index, "bench")
		part(room, p.id .. "_slab", Vector3.new(W, depth, 1.6), PanelLayout.faceCFrame(bench) * CFrame.new(0, 0, T / 2 + 0.8), CABINET_COLOR)
		-- Wood trim: a lip along the bench front and a cap over the annunciators.
		part(room, p.id .. "_lip", Vector3.new(W, 0.4, 0.45), frame(0, h0 - 0.1, 0.12), WOOD, Enum.Material.Wood)
		prop(room, p.id .. "_cap", Vector3.new(W, 0.3, cabinetDepth + 1.4), frame(0, top + 0.15, -backZ - cabinetDepth / 2 + 0.55), WOOD, Enum.Material.Wood)
		-- A dark reveal between the board and the annunciator box.
		prop(room, p.id .. "_reveal", Vector3.new(W, 0.12, 0.2), frame(0, backY + PanelLayout.VERT_HEIGHT, -backZ + T / 2 + 0.06), DARK)
		for _, faceName in { "bench", "vert", "ann" } do
			local f = PanelLayout.face(p.index, faceName)
			local color = if faceName == "bench" then BENCH_COLOR elseif faceName == "ann" then ANN_COLOR else PANEL_COLOR
			local facePart = part(room, p.id .. "_" .. faceName, Vector3.new(f.width, f.height, T), PanelLayout.faceCFrame(f), color)
			facePart:SetAttribute("Panel", p.id)
			facePart:SetAttribute("Face", faceName)
		end

		-- Joint with the next panel: a seam strip where the run is straight,
		-- a corner filler where it turns.
		if p.index < n then
			local nOrigin, nRight, nBack = PanelLayout.panelFrame(p.index + 1)
			local joint = origin + right * (W / 2)
			local turn = math.acos(math.clamp(back:Dot(nBack), -1, 1))
			if turn < 0.01 then
				prop(room, p.id .. "_seam", Vector3.new(0.1, PanelLayout.VERT_HEIGHT, 0.06), CFrame.fromMatrix(joint + up * (backY + PanelLayout.VERT_HEIGHT / 2) - back * (backZ - T / 2 - 0.03), right, up, back), DARK)
			else
				-- A square inside corner. Each cabinet is carried on, blank,
				-- past the joint until it meets the other one: boards, bench,
				-- annunciator box and all. Where the two benches overlap, the
				-- higher one shows, which is exactly the mitred valley a real
				-- corner section has.
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
					part(room, tag .. "Base", Vector3.new(ext, h0 - 0.1, backZ), at(ext / 2, (h0 - 0.1) / 2, -backZ / 2), CABINET_COLOR)
					prop(room, tag .. "Cap", Vector3.new(extCab, 0.3, cabinetDepth + 1.4), at(extCab / 2, top + 0.15, -backZ - cabinetDepth / 2 + 0.55), WOOD, Enum.Material.Wood)
					-- Bench carried on at the same slope.
					local slopeUp = up * math.sin(s) - b * math.cos(s)
					local slopeNormal = up * math.cos(s) + b * math.sin(s)
					local centre = o + r * (dir * (W / 2 + ext / 2)) + up * (h0 + depth / 2 * math.sin(s)) - b * (depth / 2 * math.cos(s)) - slopeNormal * 0.6
					part(room, tag .. "Bench", Vector3.new(ext, depth, 1.2 + T), CFrame.fromMatrix(centre, slopeUp:Cross(-slopeNormal), slopeUp, -slopeNormal), BENCH_COLOR)
				end
			end
		end
	end

	-- Operators' desk in the middle of the room, facing the back wall, with
	-- a return at each end.
	local deskX, deskZ = -4, -13
	local deskTop = 3.0
	local onDesk = CFrame.new(deskX, deskTop, deskZ)
	local function desk(name: string, size: Vector3, x: number, y: number, z: number, color: Color3, material: Enum.Material?): Part
		return part(room, name, size, CFrame.new(deskX + x, y, deskZ + z), color, material)
	end
	desk("DeskTop", Vector3.new(34, 0.3, 5), 0, deskTop - 0.15, 0, DESK)
	desk("DeskEdge", Vector3.new(34.2, 0.34, 0.3), 0, deskTop - 0.15, 2.6, WOOD, Enum.Material.Wood).CanCollide = false
	desk("DeskModesty", Vector3.new(34, deskTop - 0.3, 0.4), 0, (deskTop - 0.3) / 2, -2.2, DESK)
	for _, side in { -1, 1 } do
		desk("DeskReturn", Vector3.new(5, 0.3, 9), side * 14.5, deskTop - 0.15, 7, DESK)
		desk("DeskPedestal", Vector3.new(4.6, deskTop - 0.3, 3), side * 14.5, (deskTop - 0.3) / 2, 9.8, DESK)
		for d = 0, 2 do
			desk("DrawerPull", Vector3.new(1.4, 0.12, 0.12), side * 14.5, 0.6 + d * 0.8, 11.35, DARK).CanCollide = false
		end
		desk("DeskPedestal", Vector3.new(3, deskTop - 0.3, 4.4), side * 9, (deskTop - 0.3) / 2, 0, DESK)
	end
	terminal(room, onDesk * CFrame.new(-1.5, 0, -0.9), 1)
	teleprinter(room, onDesk * CFrame.new(-14.3, 0, 7.4) * CFrame.Angles(0, math.pi / 2, 0))
	-- Desk telephones: squat bodies with the handset across the cradle.
	for i, x in { -7.5, 6.5, 12.5 } do
		local turn = CFrame.Angles(0, (i - 2) * 0.25, 0)
		local body = if i == 2 then Color3.fromRGB(150, 30, 28) else Color3.fromRGB(28, 28, 30)
		prop(room, "Phone", Vector3.new(1.6, 0.5, 1.8), onDesk * CFrame.new(x, 0.25, 0.5) * turn, body)
		prop(room, "PhoneDial", Vector3.new(0.16, 0.9, 0.9), onDesk * CFrame.new(x, 0.5, 0.75) * turn * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(210, 208, 196)).Shape = Enum.PartType.Cylinder
		prop(room, "PhoneHandset", Vector3.new(1.9, 0.32, 0.42), onDesk * CFrame.new(x, 0.72, -0.05) * turn, body)
	end
	local binderColors = { Color3.fromRGB(30, 54, 110), Color3.fromRGB(150, 30, 30), Color3.fromRGB(28, 28, 30), Color3.fromRGB(30, 90, 60), Color3.fromRGB(96, 60, 30), Color3.fromRGB(40, 40, 46) }
	for i, color in binderColors do
		prop(room, "Binder", Vector3.new(0.5, 2.1, 1.7), onDesk * CFrame.new(13.6 + i * 0.52, 1.05, -1.3), color)
	end
	prop(room, "Bookend", Vector3.new(0.12, 1.6, 1.5), onDesk * CFrame.new(13.75, 0.8, -1.3), DARK)
	prop(room, "Logbook", Vector3.new(2.4, 0.18, 1.8), onDesk * CFrame.new(3.4, 0.09, 1.0) * CFrame.Angles(0, 0.12, 0), Color3.fromRGB(36, 60, 44))
	prop(room, "Logbook", Vector3.new(2.4, 0.18, 1.8), onDesk * CFrame.new(9.6, 0.09, 1.1) * CFrame.Angles(0, -0.2, 0), Color3.fromRGB(110, 32, 30))
	prop(room, "Papers", Vector3.new(1.7, 0.05, 2.2), onDesk * CFrame.new(-5.2, 0.03, 1.2) * CFrame.Angles(0, -0.12, 0), Color3.fromRGB(240, 238, 226))
	prop(room, "Papers", Vector3.new(1.7, 0.05, 2.2), onDesk * CFrame.new(5.9, 0.03, 0.2) * CFrame.Angles(0, 0.3, 0), Color3.fromRGB(240, 238, 226))
	prop(room, "Clipboard", Vector3.new(1.6, 0.08, 2.2), onDesk * CFrame.new(-10.6, 0.04, 1.0) * CFrame.Angles(0, 0.1, 0), Color3.fromRGB(150, 110, 70), Enum.Material.Wood)
	prop(room, "Mug", Vector3.new(0.5, 0.6, 0.5), onDesk * CFrame.new(1.6, 0.3, 1.6), Color3.fromRGB(230, 230, 226))
	local ashtray = prop(room, "Ashtray", Vector3.new(0.18, 0.9, 0.9), onDesk * CFrame.new(11.2, 0.1, 1.5) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(120, 86, 40))
	ashtray.Shape = Enum.PartType.Cylinder
	ashtray.Transparency = 0.25
	for _, x in { -8.5, 0.5, 9 } do
		chair(room, CFrame.new(deskX + x, 0, deskZ + 5.2) * CFrame.Angles(0, (x / 9) * 0.22, 0))
	end

	room.Parent = workspace
	return room
end

return RoomBuilder
