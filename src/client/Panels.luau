--!nonstrict
-- Dresses the benchboards: every instrument, lamp, switch and display in the
-- shared layout is drawn here, on each player's own machine. The flat
-- artwork goes on a SurfaceGui per panel face. The hardware standing proud
-- of the panel (pushbuttons and their guards, lamps, switch handles, keys,
-- knobs) is built from parts.
--
-- build() returns the list of things that need refreshing when a new
-- snapshot arrives and the list of clickable regions on each face.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("RBMK")
local PanelLayout = require(Shared.PanelLayout)
local CoreLayout = require(Shared.CoreLayout)
local AlarmList = require(Shared.AlarmList)

local Panels = {}

local PPS = PanelLayout.PIXELS_PER_STUD
-- Widgets are placed and sized in board units; parts are made in studs.
local S = PanelLayout.SCALE

local INK = Color3.fromRGB(24, 26, 28)
local PAPER = Color3.fromRGB(236, 232, 214)
-- Period hardware: numeric readouts are red LED panel meters, the unit
-- computer is a green-phosphor tube, and nothing has a colour screen.
local SCREEN = Color3.fromRGB(22, 8, 8)
local DIGIT = Color3.fromRGB(255, 62, 44)
local DIGIT_DIM = Color3.fromRGB(46, 14, 12)
local TUBE = Color3.fromRGB(8, 18, 12)
local PHOSPHOR = Color3.fromRGB(110, 255, 140)
local LAMP = {
	red = { Color3.fromRGB(255, 50, 40), Color3.fromRGB(70, 22, 20) },
	green = { Color3.fromRGB(60, 240, 90), Color3.fromRGB(20, 60, 28) },
	amber = { Color3.fromRGB(255, 180, 40), Color3.fromRGB(74, 54, 18) },
	blue = { Color3.fromRGB(80, 150, 255), Color3.fromRGB(22, 40, 78) },
	white = { Color3.fromRGB(250, 250, 240), Color3.fromRGB(80, 80, 76) },
}
local BUTTON = {
	red = Color3.fromRGB(200, 30, 26),
	green = Color3.fromRGB(40, 150, 60),
	blue = Color3.fromRGB(50, 90, 190),
	yellow = Color3.fromRGB(225, 190, 40),
	white = Color3.fromRGB(235, 235, 228),
	black = Color3.fromRGB(34, 34, 36),
}
local PEN = { red = Color3.fromRGB(200, 30, 30), blue = Color3.fromRGB(30, 60, 200), green = Color3.fromRGB(20, 140, 50), violet = Color3.fromRGB(120, 40, 150) }
-- Mimic line colours: reactor water blue, steam red, feedwater and
-- condensate green, emergency cooling orange, power black.
local MIMIC = {
	water = Color3.fromRGB(46, 84, 168),
	steam = Color3.fromRGB(190, 48, 36),
	feed = Color3.fromRGB(36, 120, 64),
	eccs = Color3.fromRGB(222, 128, 26),
	power = Color3.fromRGB(28, 28, 30),
}
local ROD_COLOR = {
	RR = Color3.fromRGB(200, 200, 200),
	AR = Color3.fromRGB(70, 220, 100),
	LAR = Color3.fromRGB(240, 210, 60),
	AZ = Color3.fromRGB(240, 70, 60),
	USP = Color3.fromRGB(90, 150, 255),
}

export type Region = {
	x: number,
	y: number,
	w: number,
	h: number,
	widget: any,
	press: ((button: number, u: number, v: number) -> any)?,
	tip: (() -> string)?,
}

export type Context = {
	get: (name: string) -> number,
	send: (name: string, value: number) -> (),
	click: () -> (),
}

local function px(studs: number): number
	return math.floor(studs * PPS + 0.5)
end

local function box(parent: Instance, x: number, y: number, w: number, h: number, color: Color3): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = UDim2.fromOffset(px(x), px(y))
	f.Size = UDim2.fromOffset(math.max(1, px(w)), math.max(1, px(h)))
	f.Parent = parent
	return f
end

local function text(parent: Instance, x: number, y: number, w: number, h: number, str: string, size: number, color: Color3?, font: Enum.Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Position = UDim2.fromOffset(px(x), px(y))
	t.Size = UDim2.fromOffset(px(w), px(h))
	t.Font = font or Enum.Font.SourceSansBold
	t.TextSize = math.max(6, px(size))
	t.TextColor3 = color or INK
	t.TextWrapped = true
	t.Text = str
	t.Parent = parent
	return t
end

-- Engraved laminate nameplates, the way every label in a real control room
-- is made: black lettering on white for each device, white on black for
-- system titles and panel numbers.
local PLATE = Color3.fromRGB(238, 236, 228)
local PLATE_TEXT = Color3.fromRGB(22, 22, 24)
local TITLE_PLATE = Color3.fromRGB(22, 22, 24)
local TITLE_TEXT = Color3.fromRGB(240, 240, 232)
local function plate(parent: Instance, x: number, y: number, w: number, h: number, str: string, size: number, dark: boolean?): TextLabel
	local t = text(parent, x, y, w, h, str, size, if dark then TITLE_TEXT else PLATE_TEXT, Enum.Font.ArialBold)
	t.BackgroundTransparency = 0
	t.BackgroundColor3 = if dark then TITLE_PLATE else PLATE
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 2)
	c.Parent = t
	if not dark then
		local edge = Instance.new("UIStroke")
		edge.Color = Color3.fromRGB(120, 116, 104)
		edge.Thickness = 1
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = t
	end
	return t
end

local function round(f: GuiObject)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
end

local function outline(f: GuiObject, color: Color3, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Parent = f
end

-- Small parts standing on a panel face.
local function basePart(folder: Instance, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size * S
	p.Parent = folder
	return p
end

local function cylinder(folder: Instance, face: PanelLayout.Face, x: number, y: number, diameter: number, height: number, color: Color3): Part
	local p = basePart(folder, Vector3.new(height, diameter, diameter), color)
	p.Shape = Enum.PartType.Cylinder
	p.CFrame = CFrame.fromMatrix(PanelLayout.toWorld(face, x, y, height / 2), face.normal, face.up, -face.right)
	return p
end

-- A block lying on the face, turned `angle` degrees clockwise as the operator sees it.
local function blockCFrame(face: PanelLayout.Face, x: number, y: number, lift: number, angle: number): CFrame
	return CFrame.fromMatrix(PanelLayout.toWorld(face, x, y, lift), face.right, face.up, face.normal) * CFrame.Angles(0, 0, -math.rad(angle))
end

local function block(folder: Instance, face: PanelLayout.Face, x: number, y: number, w: number, h: number, depth: number, color: Color3, angle: number?): Part
	local p = basePart(folder, Vector3.new(w, h, depth), color)
	p.CFrame = blockCFrame(face, x, y, depth / 2, angle or 0)
	return p
end

-- A raised rectangular frame: four bars standing around a rectangle on the face.
local function bezel(folder: Instance, face: PanelLayout.Face, x: number, y: number, w: number, h: number, depth: number, color: Color3, thickness: number?)
	local t = thickness or 0.05
	block(folder, face, x + w / 2, y - t / 2, w + 2 * t, t, depth, color)
	block(folder, face, x + w / 2, y + h + t / 2, w + 2 * t, t, depth, color)
	block(folder, face, x - t / 2, y + h / 2, t, h, depth, color)
	block(folder, face, x + w + t / 2, y + h / 2, t, h, depth, color)
end

-- ---------------------------------------------------------------- hardware
-- The hardware standing proud of the panels is built from parts in the
-- frame of each device: X to the operator's right, Y up the panel, Z out of
-- it, in board units, with the origin at the device's mounting point on the
-- panel face. Round parts are discs standing out of the panel; domes, caps
-- and handles are ellipsoids (a sphere mesh stretched to its part); rings
-- are stepped like turned metal.
local CHROME = Color3.fromRGB(200, 202, 206)
local PHENOLIC = Color3.fromRGB(20, 20, 22) -- black moulded handles and knobs
local BRASS = Color3.fromRGB(200, 168, 84)
local BEZEL = Color3.fromRGB(34, 35, 38)
local GUARD_YELLOW = Color3.fromRGB(232, 196, 40)
local GUARD_BLACK = Color3.fromRGB(30, 30, 32)
local COVER_RED = Color3.fromRGB(214, 44, 30)
local COVER_TRANSPARENCY = 0.45
local COVER_OPEN = 100 -- degrees a lifted guard cover stands open
local METAL = Enum.Material.Metal
local GLASS = Enum.Material.Glass

-- Turns a cylinder part, whose axis is its own X, to stand out of the panel.
local OUT_OF_PANEL = CFrame.Angles(0, -math.pi / 2, 0)

local function v3(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- One part of a device, centred at `at`. `kind` is "block"; "disc", a
-- cylinder standing out of the panel (size: diameter, diameter, height);
-- "rod", a cylinder lying along X (size: length, diameter, diameter); or
-- "ellipsoid". Returns the part and where it sits in the device frame.
local function piece(folder: Instance, frame: CFrame, kind: string, size: Vector3, at: Vector3, color: Color3, material: Enum.Material?, transparency: number?): (Part, CFrame)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color
	p.Transparency = transparency or 0
	local rel = CFrame.new(at * S)
	if kind == "disc" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(size.Z, size.Y, size.X) * S
		rel *= OUT_OF_PANEL
	elseif kind == "rod" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = size * S
	else
		p.Size = size * S
		if kind == "ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
	end
	p.CFrame = frame * rel
	p.Parent = folder
	return p, rel
end

-- Parts that move together in the device frame: a switch handle, a key, a
-- knob's pointer, a button's cap, a guard's cover. `move` places the whole
-- assembly by a CFrame in studs, in the device frame.
type Assembly = {
	add: (kind: string, size: Vector3, at: Vector3, color: Color3, material: Enum.Material?, transparency: number?) -> Part,
	move: (t: CFrame) -> (),
	parts: { Part },
}
local function assembly(folder: Instance, frame: CFrame): Assembly
	local parts: { Part } = {}
	local rels: { CFrame } = {}
	local self: any = { parts = parts }
	function self.add(kind: string, size: Vector3, at: Vector3, color: Color3, material: Enum.Material?, transparency: number?): Part
		local p, rel = piece(folder, frame, kind, size, at, color, material, transparency)
		table.insert(parts, p)
		table.insert(rels, rel)
		return p
	end
	function self.move(t: CFrame)
		for i, p in parts do
			p.CFrame = frame * t * rels[i]
		end
	end
	return self
end

-- A turn of `angle` degrees clockwise, as the operator sees it, about the
-- device's own axis.
local function turned(angle: number): CFrame
	return CFrame.Angles(0, 0, -math.rad(angle))
end

-- An indicating light: a coloured lens with a domed face in a stepped
-- chrome bezel, glass when dark and glowing when lit. `diameter` is the
-- lens's.
local function lens(folder: Instance, face: PanelLayout.Face, x: number, y: number, diameter: number, colors: { Color3 }): (boolean) -> ()
	local frame = blockCFrame(face, x, y, 0, 0)
	local d = diameter
	piece(folder, frame, "disc", v3(d + 0.11, d + 0.11, 0.025), v3(0, 0, 0.0125), CHROME, METAL)
	piece(folder, frame, "disc", v3(d + 0.065, d + 0.065, 0.06), v3(0, 0, 0.03), CHROME, METAL)
	local body = piece(folder, frame, "disc", v3(d, d, 0.066), v3(0, 0, 0.033), colors[2], GLASS)
	local top = piece(folder, frame, "ellipsoid", v3(d, d, d * 0.6), v3(0, 0, 0.066), colors[2], GLASS)
	return function(on: boolean)
		for _, p in { body, top } do
			p.Color = colors[if on then 1 else 2]
			p.Material = if on then Enum.Material.Neon else GLASS
		end
	end
end

-- An oiltight pushbutton standing at `frame`: a chrome locking ring with a
-- stepped edge, a dark gap, and a coloured cap with a crowned face. Returns
-- the cap, which moves in when the button is pressed.
local function pushbutton(folder: Instance, frame: CFrame, color: Color3): Assembly
	piece(folder, frame, "disc", v3(0.44, 0.44, 0.03), v3(0, 0, 0.015), CHROME, METAL)
	piece(folder, frame, "disc", v3(0.4, 0.4, 0.07), v3(0, 0, 0.035), CHROME, METAL)
	piece(folder, frame, "disc", v3(0.33, 0.33, 0.072), v3(0, 0, 0.036), PHENOLIC)
	local cap = assembly(folder, frame)
	cap.add("disc", v3(0.3, 0.3, 0.12), v3(0, 0, 0.06), color)
	cap.add("ellipsoid", v3(0.29, 0.29, 0.07), v3(0, 0, 0.12), color)
	return cap
end

-- The scram button: a large mushroom head on a stem, in a wide chrome ring.
local function mushroom(folder: Instance, frame: CFrame, color: Color3): Assembly
	piece(folder, frame, "disc", v3(0.56, 0.56, 0.03), v3(0, 0, 0.015), CHROME, METAL)
	piece(folder, frame, "disc", v3(0.48, 0.48, 0.08), v3(0, 0, 0.04), CHROME, METAL)
	piece(folder, frame, "disc", v3(0.38, 0.38, 0.082), v3(0, 0, 0.041), PHENOLIC)
	local cap = assembly(folder, frame)
	cap.add("disc", v3(0.3, 0.3, 0.2), v3(0, 0, 0.1), color)
	cap.add("ellipsoid", v3(0.66, 0.66, 0.08), v3(0, 0, 0.2), color)
	cap.add("disc", v3(0.66, 0.66, 0.05), v3(0, 0, 0.225), color)
	cap.add("ellipsoid", v3(0.66, 0.66, 0.22), v3(0, 0, 0.25), color)
	return cap
end

-- A guard for a protective pushbutton, `k` times the size of a standard
-- one: a base plate with rounded corners, two screws and hinge knuckles
-- along its top edge, under a hinged box of translucent red plastic with a
-- tab to lift it by. The button stands on the base. Returns the base's
-- thickness, the cover, and a function that swings the cover open by an
-- angle in degrees.
local function guard(folder: Instance, frame: CFrame, k: number, baseColor: Color3, coverHeight: number): (number, Assembly, (number) -> ())
	local half, base, r = 0.31 * k, 0.05 * k, 0.06 * k
	-- Two crossed blocks and four corner discs make the rounded plate.
	piece(folder, frame, "block", v3(2 * half, 2 * (half - r), base), v3(0, 0, base / 2), baseColor)
	piece(folder, frame, "block", v3(2 * (half - r), 2 * half, base), v3(0, 0, base / 2), baseColor)
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			piece(folder, frame, "disc", v3(2 * r, 2 * r, base), v3(sx * (half - r), sy * (half - r), base / 2), baseColor)
		end
		piece(folder, frame, "disc", v3(0.06 * k, 0.06 * k, 0.012 * k), v3(sx * (half - 0.075 * k), -(half - 0.075 * k), base + 0.006 * k), CHROME, METAL)
		piece(folder, frame, "rod", v3(0.11 * k, 0.06 * k, 0.06 * k), v3(sx * 0.205 * k, half, base), baseColor)
	end
	local cover = assembly(folder, frame)
	local w, h, t = 2 * half - 0.03 * k, 2 * half - 0.05 * k, 0.02 * k
	local cy = -0.012 * k
	local top = base + coverHeight
	local wallH = coverHeight - t
	local wallZ = base + wallH / 2
	local function wall(size: Vector3, at: Vector3)
		cover.add("block", size, at, COVER_RED, GLASS, COVER_TRANSPARENCY)
	end
	wall(v3(w, h, t), v3(0, cy, top - t / 2))
	wall(v3(t, h, wallH), v3(-(w - t) / 2, cy, wallZ))
	wall(v3(t, h, wallH), v3((w - t) / 2, cy, wallZ))
	wall(v3(w - 2 * t, t, wallH), v3(0, cy - (h - t) / 2, wallZ))
	wall(v3(w - 2 * t, t, wallH), v3(0, cy + (h - t) / 2, wallZ))
	-- The lifting tab, the strap out to the hinge, and the hinge barrel.
	wall(v3(0.24 * k, 0.07 * k, t), v3(0, cy - h / 2 - 0.025 * k, top - 0.03 * k))
	wall(v3(0.28 * k, 0.05 * k, t), v3(0, half - 0.03 * k, base + 0.012 * k))
	cover.add("rod", v3(0.29 * k, 0.056 * k, 0.056 * k), v3(0, half, base), COVER_RED, GLASS, COVER_TRANSPARENCY)
	local function swing(angle: number)
		local hy, hz = half * S, base * S
		cover.move(CFrame.new(0, hy, hz) * CFrame.Angles(-math.rad(angle), 0, 0) * CFrame.new(0, -hy, -hz))
	end
	return base, cover, swing
end

-- Second switch positions that mean a piece of equipment is energised,
-- running or open: these switches get red and green lamps.
local EQUIPMENT_STATES = { ON = true, OPEN = true, CLOSE = true, RUN = true, START = true }
-- Annunciator windows are milky white plastic, lit from behind.
local ANN_DARK = Color3.fromRGB(204, 200, 186)
local ANN_DARK_TEXT = Color3.fromRGB(58, 56, 50)
local ANN_SPARE = Color3.fromRGB(196, 192, 178)

local function cleanLabel(s: string?): string
	return (string.gsub(s or "", "\n", " "))
end

-- A seven-segment display of the period: each digit is drawn segment by
-- segment, with the unlit segments faintly visible behind the glass, the
-- way a gas-discharge or LED panel meter looks. Returns a function that
-- shows a formatted number, right-aligned.
local SEGMENTS = {
	["0"] = "abcdef", ["1"] = "bc", ["2"] = "abdeg", ["3"] = "abcdg", ["4"] = "bcfg",
	["5"] = "acdfg", ["6"] = "acdefg", ["7"] = "abc", ["8"] = "abcdefg", ["9"] = "abcdfg",
	["-"] = "g", ["E"] = "adefg", ["r"] = "eg",
}
local function sevenSeg(parent: Instance, x: number, y: number, w: number, h: number, cells: number, lit: Color3, unlit: Color3): (string) -> ()
	local pad = h * 0.16
	local ch = h - 2 * pad
	local pitch = math.min((w - 2 * pad) / cells, ch * 0.68)
	local cw = pitch * 0.7
	local t = math.max(ch * 0.12, 0.022)
	local x0 = x + w - pad - pitch * cells + (pitch - cw) / 2
	local y0 = y + pad
	local half = ch / 2
	local shapes = {
		a = { t * 0.6, 0, cw - 1.2 * t, t },
		g = { t * 0.6, half - t / 2, cw - 1.2 * t, t },
		d = { t * 0.6, ch - t, cw - 1.2 * t, t },
		f = { 0, t * 0.55, t, half - t * 1.05 },
		e = { 0, half + t * 0.5, t, half - t * 1.05 },
		b = { cw - t, t * 0.55, t, half - t * 1.05 },
		c = { cw - t, half + t * 0.5, t, half - t * 1.05 },
	}
	local digits = {}
	for k = 1, cells do
		local cx = x0 + (k - 1) * pitch
		local segs = {}
		for name, r in shapes do
			local f = box(parent, cx + r[1], y0 + r[2], r[3], r[4], unlit)
			f.ZIndex = 3
			segs[name] = f
		end
		local dp = box(parent, cx + cw + (pitch - cw) / 2 - t / 2, y0 + ch - t, t, t, unlit)
		dp.ZIndex = 3
		digits[k] = { segs = segs, dp = dp }
	end
	local shown = ""
	return function(str: string)
		if str == shown then
			return
		end
		shown = str
		local chars: { { c: string, dp: boolean } } = {}
		for i = 1, #str do
			local c = string.sub(str, i, i)
			if c == "." then
				if #chars > 0 then
					chars[#chars].dp = true
				else
					table.insert(chars, { c = " ", dp = true })
				end
			else
				table.insert(chars, { c = c, dp = false })
			end
		end
		if #chars > cells then
			-- Over range: the display shows dashes.
			chars = {}
			for _ = 1, cells do
				table.insert(chars, { c = "-", dp = false })
			end
		end
		local offset = cells - #chars
		for k = 1, cells do
			local cell = chars[k - offset]
			local on = if cell then SEGMENTS[cell.c] or "" else ""
			for name, f in digits[k].segs do
				f.BackgroundColor3 = if string.find(on, name, 1, true) then lit else unlit
			end
			digits[k].dp.BackgroundColor3 = if cell and cell.dp then lit else unlit
		end
	end
end

-- The channel cartogram is a mosaic of lamps, one per channel, and a lamp
-- has only a handful of states: dark, dim green, green, yellow, amber, red.
local LAMP_STEPS = {
	{ 0.10, Color3.fromRGB(34, 36, 34) },
	{ 0.30, Color3.fromRGB(26, 84, 40) },
	{ 0.50, Color3.fromRGB(58, 214, 84) },
	{ 0.65, Color3.fromRGB(238, 220, 60) },
	{ 0.80, Color3.fromRGB(255, 150, 40) },
	{ 2.00, Color3.fromRGB(255, 52, 40) },
}
local PALETTE: { Color3 } = {}
for i = 0, 31 do
	local t = (i + 0.5) / 32
	for _, step in LAMP_STEPS do
		if t < step[1] then
			PALETTE[i + 1] = step[2]
			break
		end
	end
end

function Panels.build(room: Instance, ctx: Context)
	local get = ctx.get
	local updaters: { () -> () } = {}
	local regions: { [Instance]: { Region } } = {}
	local faces: { [Instance]: PanelLayout.Face } = {}
	local annTiles: { [number]: any } = {}
	local logLines: { string } = {}
	local out: any = { updaters = updaters, regions = regions, faces = faces, annTiles = annTiles, logLines = logLines }

	local controls = Instance.new("Folder")
	controls.Name = "PanelControls"
	controls.Parent = room
	-- Displays fed from the rod section of the core map buffer.
	local rodListeners: { (buf: buffer) -> () } = {}
	-- Panels whose annunciator TEST button is held.
	local testing: { [string]: boolean } = {}

	-- A pane of glass over an instrument window.
	local function glassOver(face: PanelLayout.Face, cx: number, cy: number, w: number, h: number)
		local g = basePart(controls, Vector3.new(w, h, 0.01), Color3.fromRGB(214, 226, 236))
		g.CFrame = blockCFrame(face, cx, cy, 0.1, 0)
		g.Material = Enum.Material.Glass
		g.Transparency = 0.9
		g.Reflectance = 0.1
	end

	-- A display that gives its own light (digits, the cartogram, the
	-- computer's tube) is drawn on a thin part just in front of the board,
	-- with a GUI that ignores the room lighting; everything printed or
	-- engraved on the board itself is lit like the board. Returns a canvas
	-- placed so that face coordinates can be used for drawing on it.
	local overlayCount = 0
	local function overlay(face: PanelLayout.Face, part: Instance, x: number, y: number, w: number, h: number): Frame
		overlayCount += 1
		local p = Instance.new("Part")
		p.Name = "Display"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Size = Vector3.new(w * S, h * S, 0.02)
		local z = -face.normal
		local yv = face.up
		p.CFrame = CFrame.fromMatrix(PanelLayout.toWorld(face, x + w / 2, y + h / 2, 0.012), yv:Cross(z), yv, z)
		p:SetAttribute("Overlay", true)
		p:SetAttribute("Panel", part:GetAttribute("Panel"))
		p:SetAttribute("Face", tostring(part:GetAttribute("Face")) .. "_d" .. overlayCount)
		p.Parent = controls
		local g = Instance.new("SurfaceGui")
		g.Face = Enum.NormalId.Front
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = PPS / S
		g.LightInfluence = 0
		g.ResetOnSpawn = false
		g.Adornee = p
		g.Parent = p
		local canvas = Instance.new("Frame")
		canvas.BackgroundTransparency = 1
		canvas.BorderSizePixel = 0
		canvas.Position = UDim2.fromOffset(-px(x), -px(y))
		canvas.Size = UDim2.fromOffset(px(face.width), px(face.height))
		canvas.Parent = g
		return canvas
	end

	local builders: { [string]: (gui: SurfaceGui, face: PanelLayout.Face, part: Instance, w: any) -> () } = {}

	local function region(part: Instance, w: any, press: any, tip: any)
		table.insert(regions[part], { x = w.x, y = w.y, w = w.w, h = w.h, widget = w, press = press, tip = tip })
	end

	local function valueTip(w: any): () -> string
		return function()
			local s = string.format("%s: " .. (w.fmt or "%.1f") .. " %s", cleanLabel(w.label), get(w.sig), w.unit or "")
			if w.tip then
				s ..= "\n" .. w.tip
			end
			return s
		end
	end

	-- Group nameplate: white letters on a black plate, centred over the
	-- devices of one system. Boards of the period had no outline boxes; the
	-- grouping is carried by these plates and by the spacing.
	builders.section = function(gui, _face, _part, w)
		if w.label ~= "" then
			local pw = math.min(w.w, #w.label * 0.072 + 0.4)
			plate(gui, w.x + (w.w - pw) / 2, w.y + 0.02, pw, 0.22, w.label, 0.1, true)
		end
	end

	builders.label = function(gui, _face, _part, w)
		if w.title then
			-- The panel number and name on a modest plate centred at the top.
			local pw = math.min(w.w, #w.label * 0.15 + 0.8)
			plate(gui, w.x + (w.w - pw) / 2, w.y + 0.02, pw, w.h - 0.06, w.label, 0.22, true)
			return
		end
		local t = text(gui, w.x, w.y, w.w, w.h, w.label, if w.small then 0.16 else 0.18, INK)
		if w.small then
			t.TextXAlignment = Enum.TextXAlignment.Left
			t.TextYAlignment = Enum.TextYAlignment.Top
			t.Font = Enum.Font.SourceSans
		end
	end

	-- An edgewise meter of the GE type 180 kind: a narrow black case with a
	-- white scale behind glass, graduated in twenty divisions with figures at
	-- every fifth, the unit printed at the foot, coloured bands for the
	-- limits, and a red pointer. Its nameplate sits above it.
	builders.meter = function(gui, face, part, w)
		-- Every meter's nameplate is the same height, so a row lines up.
		local plateH = 0.3
		plate(gui, w.x - 0.02, w.y, w.w + 0.04, plateH, w.label, 0.08)
		local cy0 = w.y + plateH + 0.05
		local ch = w.h - plateH - 0.05
		box(gui, w.x, cy0, w.w, ch, Color3.fromRGB(24, 24, 26))
		local inset = 0.055
		local sx, sy, sw, sh = w.x + inset, cy0 + inset, w.w - 2 * inset, ch - 2 * inset
		box(gui, sx, sy, sw, sh, PAPER)
		local hasUnit = (w.unit or "") ~= ""
		local top, bottom = sy + 0.09, sy + sh - (if hasUnit then 0.24 else 0.09)
		local gh = bottom - top
		local span = w.hi - w.lo
		local function yOf(f: number): number
			return bottom - gh * f
		end
		local function band(from: number, to: number, color: Color3)
			local a = math.clamp((from - w.lo) / span, 0, 1)
			local b = math.clamp((to - w.lo) / span, 0, 1)
			if b > a then
				box(gui, sx + sw * 0.78, yOf(b), sw * 0.22, gh * (b - a), color)
			end
		end
		if w.amber then
			band(w.amber, w.red or w.hi, Color3.fromRGB(240, 180, 40))
		end
		if w.red then
			band(w.red, w.hi, Color3.fromRGB(214, 44, 36))
		end
		if w.low then
			band(w.lo, w.low, Color3.fromRGB(214, 44, 36))
		end
		box(gui, sx + 0.012, top, 0.01, gh, INK).ZIndex = 2
		for i = 0, 20 do
			local ty = yOf(i / 20)
			local major = i % 5 == 0
			local tick = box(gui, sx + 0.012, ty - (if major then 0.008 else 0.004), sw * (if major then 0.3 else 0.16), if major then 0.016 else 0.008, INK)
			tick.ZIndex = 2
			if major then
				local v = w.lo + span * i / 20
				local label
				if math.abs(v) >= 1000 then
					label = if v % 1000 == 0 then string.format("%.0fk", v / 1000) else string.format("%.1fk", v / 1000)
				elseif span < 2 then
					label = string.format("%.2f", v)
				elseif span < 20 and v % 1 ~= 0 then
					label = string.format("%.1f", v)
				else
					label = string.format("%.0f", v)
				end
				local n = text(gui, sx + sw * 0.36, ty - 0.065, sw * 0.5, 0.13, label, 0.074, INK, Enum.Font.Arial)
				n.TextXAlignment = Enum.TextXAlignment.Left
				n.ZIndex = 2
			end
		end
		if hasUnit then
			local u = text(gui, sx, bottom + 0.08, sw, 0.13, w.unit, 0.072, Color3.fromRGB(50, 50, 50), Enum.Font.ArialBold)
			u.ZIndex = 2
		end
		-- The case flange and the glass are parts standing off the board.
		bezel(controls, face, w.x + 0.02, cy0 + 0.02, w.w - 0.04, ch - 0.04, 0.12, BEZEL, 0.04)
		glassOver(face, sx + sw / 2, sy + sh / 2, sw, sh)
		local needle = block(controls, face, sx + sw / 2, bottom, sw + 0.02, 0.03, 0.025, Color3.fromRGB(205, 22, 22))
		local last = math.huge
		table.insert(updaters, function()
			local v = get(w.sig)
			if v ~= last then
				last = v
				local f = math.clamp((v - w.lo) / span, 0, 1)
				needle.CFrame = blockCFrame(face, sx + sw / 2, yOf(f), 0.05, 0)
			end
		end)
		region(part, w, nil, valueTip(w))
	end

	-- A horizontal edgewise meter: nameplate above, a black case with a white
	-- scale behind glass, graduated in ten, and a red pointer.
	builders.hmeter = function(gui, face, part, w)
		plate(gui, w.x + 0.04, w.y, w.w - 0.08, 0.2, w.label, 0.072)
		local mx, my, mw, mh = w.x + 0.07, w.y + 0.27, w.w - 0.14, w.h - 0.31
		box(gui, mx - 0.045, my - 0.045, mw + 0.09, mh + 0.09, Color3.fromRGB(24, 24, 26))
		box(gui, mx, my, mw, mh, PAPER)
		local span = w.hi - w.lo
		local function xOf(v: number): number
			return mx + 0.05 + (mw - 0.1) * math.clamp((v - w.lo) / span, 0, 1)
		end
		if w.red then
			box(gui, xOf(w.red), my, xOf(w.hi) - xOf(w.red), 0.05, Color3.fromRGB(214, 44, 36)).ZIndex = 2
		end
		if w.low then
			box(gui, xOf(w.lo), my, xOf(w.low) - xOf(w.lo), 0.05, Color3.fromRGB(214, 44, 36)).ZIndex = 2
		end
		for i = 0, 10 do
			local major = i % 5 == 0
			box(gui, mx + 0.05 + (mw - 0.1) * i / 10 - 0.004, my + mh - (if major then 0.12 else 0.065), 0.008, if major then 0.12 else 0.065, INK).ZIndex = 2
		end
		local lo = text(gui, mx + 0.02, my + 0.03, 0.45, 0.1, string.format("%g", w.lo), 0.068, INK, Enum.Font.Arial)
		lo.TextXAlignment = Enum.TextXAlignment.Left
		lo.ZIndex = 2
		local hi = text(gui, mx + mw - 0.47, my + 0.03, 0.45, 0.1, string.format("%g", w.hi), 0.068, INK, Enum.Font.Arial)
		hi.TextXAlignment = Enum.TextXAlignment.Right
		hi.ZIndex = 2
		if (w.unit or "") ~= "" then
			text(gui, mx + mw / 2 - 0.3, my + 0.03, 0.6, 0.1, w.unit, 0.062, Color3.fromRGB(70, 70, 70), Enum.Font.ArialBold).ZIndex = 2
		end
		bezel(controls, face, mx - 0.025, my - 0.025, mw + 0.05, mh + 0.05, 0.08, BEZEL, 0.03)
		glassOver(face, mx + mw / 2, my + mh / 2, mw, mh)
		local pointer = block(controls, face, mx, my + mh / 2, 0.022, mh + 0.01, 0.025, Color3.fromRGB(205, 22, 22))
		local last = math.huge
		table.insert(updaters, function()
			local v = get(w.sig)
			if v ~= last then
				last = v
				pointer.CFrame = blockCFrame(face, xOf(v), my + mh / 2, 0.05, 0)
			end
		end)
		region(part, w, nil, valueTip(w))
	end

	-- A digital panel meter of the late 1970s: a black bezel with red LED
	-- digits, or, with `counter`, a mechanical counter of white figures on
	-- black drums. The nameplate above gives the quantity and unit.
	builders.digital = function(gui, face, part, w)
		local name = if (w.unit or "") ~= "" then w.label .. ", " .. w.unit else w.label
		plate(gui, w.x, w.y, w.w, 0.2, name, 0.075)
		local bx, by, bw, bh = w.x, w.y + 0.24, w.w, w.h - 0.24
		local cells = w.cells or #(string.gsub(string.format(w.fmt, -8888.88), "[%.%+]", ""))
		box(gui, bx, by, bw, bh, Color3.fromRGB(26, 26, 28))
		bezel(controls, face, bx + 0.015, by + 0.015, bw - 0.03, bh - 0.03, 0.07, BEZEL, 0.03)
		local show: (string) -> ()
		if w.counter then
			-- White figures on black drums, each in its own window.
			local cw = math.min((bw - 0.12) / cells, (bh - 0.1) * 0.7)
			local x0 = bx + bw - 0.06 - cw * cells
			local drums = {}
			for k = 1, cells do
				local d = text(gui, x0 + (k - 1) * cw + 0.008, by + 0.06, cw - 0.016, bh - 0.12, "0", (bh - 0.12) * 0.8, Color3.fromRGB(236, 236, 228), Enum.Font.ArialBold)
				d.BackgroundTransparency = 0
				d.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
				d.ZIndex = 2
				drums[k] = d
			end
			show = function(str: string)
				local digits = string.gsub(str, "[^%d]", "")
				digits = string.rep("0", math.max(0, cells - #digits)) .. digits
				digits = string.sub(digits, -cells)
				for k = 1, cells do
					drums[k].Text = string.sub(digits, k, k)
				end
			end
		else
			local canvas = overlay(face, part, bx + 0.05, by + 0.05, bw - 0.1, bh - 0.1)
			box(canvas, bx + 0.05, by + 0.05, bw - 0.1, bh - 0.1, SCREEN)
			show = sevenSeg(canvas, bx + 0.05, by + 0.05, bw - 0.1, bh - 0.1, cells, DIGIT, DIGIT_DIM)
		end
		local last = math.huge
		table.insert(updaters, function()
			local v = get(w.sig)
			if v ~= last then
				last = v
				show((string.gsub(string.format(w.fmt, v), "%+", "")))
			end
		end)
		region(part, w, nil, valueTip(w))
	end

	-- An indicating light: a domed lens in a black bezel, with its legend
	-- on a nameplate beside it.
	builders.lamp = function(gui, face, part, w)
		local d = math.min(0.2, w.h - 0.1)
		local setLens = lens(controls, face, w.x + 0.05 + d / 2, w.y + w.h / 2, d, LAMP[w.color])
		plate(gui, w.x + d + 0.15, w.y + (w.h - 0.2) / 2, w.w - d - 0.17, 0.2, w.label, 0.075)
		local lastOn: boolean? = nil
		local function isOn(): boolean
			local v = get(w.sig)
			if w.eq then
				return v == w.eq
			elseif w.lt then
				return v < w.lt
			end
			return v > (w.gt or 0.5)
		end
		table.insert(updaters, function()
			local on = isOn()
			if on ~= lastOn then
				lastOn = on
				setLens(on)
			end
		end)
		region(part, w, nil, function()
			return cleanLabel(w.label) .. (if isOn() then ": ON" else ": off")
		end)
	end

	-- An oiltight pushbutton with its nameplate below. The protective
	-- functions (the scram, ECCS initiation, the turbine trips) are guarded:
	-- the button stands on a guard base under a hinged translucent cover,
	-- which has to be lifted before the button can be pressed. The scram
	-- button is a large red mushroom head in a yellow guard.
	builders.button = function(gui, face, part, w)
		local big, guarded = w.big, w.guard
		local k = if big then 1.65 else 1
		local half = 0.31 * k
		local ring = if big then 0.28 else 0.22 -- radius of the chrome ring
		local cx = w.x + w.w / 2
		local cy = if guarded then w.y + half + 0.07 else w.y + ring + 0.02
		local mount = blockCFrame(face, cx, cy, 0, 0)
		local color = BUTTON[w.color]
		local seat = mount
		local swing: (number) -> () = function(_angle: number) end
		if guarded then
			local base, cover, swingCover = guard(controls, mount, k, if big then GUARD_YELLOW else GUARD_BLACK, if big then 0.43 else 0.24)
			seat = mount * CFrame.new(0, 0, base * S)
			swing = swingCover
			cover.parts[1]:SetAttribute("Guard", w.cmd)
		end
		local cap = if big then mushroom(controls, seat, color) else pushbutton(controls, seat, color)
		local plateY = (if guarded then cy + half else cy + ring) + 0.05
		plate(gui, w.x - 0.02, plateY, w.w + 0.04, math.min(0.3, w.y + w.h - plateY), w.label, if big then 0.13 else 0.075)

		-- The cover swings about the hinge along the top edge of the guard.
		local open = false
		local angle = 0
		local swings = 0
		local function swingTo(target: number)
			swings += 1
			local mine = swings
			local from = angle
			task.spawn(function()
				for step = 1, 8 do
					if swings ~= mine then
						return
					end
					angle = from + (target - from) * step / 8
					swing(angle)
					task.wait(0.02)
				end
			end)
		end

		region(part, w, function(button: number)
			if guarded then
				if button == 2 then
					if open then
						open = false
						ctx.click()
						swingTo(0)
					end
					return nil
				elseif not open then
					open = true
					ctx.click()
					swingTo(COVER_OPEN)
					return nil
				end
			elseif button == 2 then
				return nil
			end
			ctx.click()
			cap.move(CFrame.new(0, 0, -0.05 * S))
			task.delay(0.15, function()
				cap.move(CFrame.new())
			end)
			if w.hold then
				return { hold = w.cmd, value = w.value }
			end
			ctx.send(w.cmd, w.value)
			return nil
		end, function()
			local name = cleanLabel(w.label)
			if guarded then
				return if open
					then name .. " (cover lifted)\nclick to press, right-click to close the cover"
					else name .. " (guarded)\nclick to lift the cover"
			end
			return name .. (if w.hold then " (hold)" else "")
		end)
	end

	-- A pistol-grip handle on its hub, pointing up and turned `angle`
	-- degrees, `k` times the standard size; returns a function that turns
	-- it. The moulded handle is broad over the shaft and tapers to a rounded
	-- end, the end that points at the position.
	local function pistolGrip(face: PanelLayout.Face, hx: number, hy: number, angle: number, k: number?): (number) -> ()
		local s = k or 1
		local frame = blockCFrame(face, hx, hy, 0, 0)
		piece(controls, frame, "disc", v3(0.26 * s, 0.26 * s, 0.03), v3(0, 0, 0.015), PHENOLIC)
		piece(controls, frame, "disc", v3(0.19 * s, 0.19 * s, 0.07), v3(0, 0, 0.035), PHENOLIC)
		local handle = assembly(controls, frame)
		handle.add("ellipsoid", v3(0.19 * s, 0.21 * s, 0.13 * s), v3(0, 0, 0.07 + 0.03 * s), PHENOLIC)
		handle.add("ellipsoid", v3(0.135 * s, 0.47 * s, 0.11 * s), v3(0, 0.13 * s, 0.07 + 0.035 * s), PHENOLIC)
		local function turn(a: number)
			handle.move(turned(a))
		end
		turn(angle)
		return turn
	end

	-- A control switch module: nameplate, a pair of indicating lamps, and
	-- a black escutcheon engraved with the two positions, carrying either a
	-- pistol-grip handle or a key lock. Returns a function that sets it.
	local function controlModule(gui: Instance, face: PanelLayout.Face, w: any, key: boolean?, lamps: { { Color3 } }?): (boolean) -> ()
		-- One nameplate height for every module, so a row lines up.
		local plateH = 0.28
		if w.label ~= "" then
			plate(gui, w.x + 0.02, w.y, w.w - 0.04, plateH, w.label, 0.075)
		end
		local cx = w.x + w.w / 2
		local setA, setB
		local ey = w.y + plateH + 0.06
		if lamps then
			local ly = w.y + plateH + 0.15
			setA = lens(controls, face, cx - 0.2, ly, 0.15, lamps[1])
			setB = lens(controls, face, cx + 0.2, ly, 0.15, lamps[2])
			ey = ly + 0.13
		end
		local ew = math.min(w.w - 0.06, 0.74)
		local eh = math.min(0.62, w.y + w.h - ey - 0.02)
		box(gui, cx - ew / 2, ey, ew, eh, Color3.fromRGB(22, 22, 24))
		local white = Color3.fromRGB(232, 232, 224)
		local pos = w.positions or { "OFF", "ON" }
		local left = text(gui, cx - ew / 2 + 0.03, ey + 0.025, ew / 2 - 0.03, 0.11, pos[1], 0.062, white, Enum.Font.ArialBold)
		left.TextXAlignment = Enum.TextXAlignment.Left
		left.TextWrapped = false
		local right = text(gui, cx, ey + 0.025, ew / 2 - 0.03, 0.11, pos[2], 0.062, white, Enum.Font.ArialBold)
		right.TextXAlignment = Enum.TextXAlignment.Right
		right.TextWrapped = false
		local hx, hy = cx, ey + eh * 0.62
		local set: (boolean) -> ()
		if key then
			-- A chrome lock cylinder with a brass key standing in it.
			local frame = blockCFrame(face, hx, hy, 0, 0)
			piece(controls, frame, "disc", v3(0.3, 0.3, 0.025), v3(0, 0, 0.0125), CHROME, METAL)
			piece(controls, frame, "disc", v3(0.25, 0.25, 0.07), v3(0, 0, 0.035), CHROME, METAL)
			piece(controls, frame, "disc", v3(0.16, 0.16, 0.074), v3(0, 0, 0.037), Color3.fromRGB(150, 151, 155), METAL)
			local keyParts = assembly(controls, frame)
			keyParts.add("block", v3(0.03, 0.08, 0.06), v3(0, 0, 0.1), BRASS, METAL)
			keyParts.add("block", v3(0.034, 0.13, 0.03), v3(0, 0, 0.14), BRASS, METAL)
			keyParts.add("rod", v3(0.03, 0.2, 0.2), v3(0, 0, 0.25), BRASS, METAL)
			set = function(on: boolean)
				keyParts.move(turned(if on then 45 else -45))
			end
		else
			local turn = pistolGrip(face, hx, hy, -45, 0.78)
			set = function(on: boolean)
				turn(if on then 45 else -45)
			end
		end
		return function(on: boolean)
			set(on)
			if setA then
				setA(not on)
				setB(on)
			end
		end
	end

	builders.toggle = function(gui, face, part, w)
		local lamps = nil
		if not w.key then
			local equipment = EQUIPMENT_STATES[w.positions[2]] == true
			lamps = if equipment then { LAMP.green, LAMP.red } else { LAMP.white, LAMP.white }
		end
		local set = controlModule(gui, face, w, w.key, lamps)
		local last: boolean? = nil
		table.insert(updaters, function()
			local on = get(w.sig) >= 0.5
			if on ~= last then
				last = on
				set(on)
			end
		end)
		region(part, w, function(_button: number)
			ctx.click()
			ctx.send(w.cmd, if get(w.sig) >= 0.5 then 0 else 1)
			return nil
		end, function()
			return cleanLabel(w.label) .. ": " .. (if get(w.sig) >= 0.5 then w.positions[2] else w.positions[1]) .. (if w.key then " (key switch)" else "")
		end)
	end

	-- A pump motor's breaker control switch: green lamp stopped, red running.
	builders.pump = function(gui, face, part, w)
		w.positions = w.positions or { "STOP", "START" }
		local set = controlModule(gui, face, w, false, { LAMP.green, LAMP.red })
		local last: boolean? = nil
		table.insert(updaters, function()
			local on = get(w.sig) >= 0.5
			if on ~= last then
				last = on
				set(on)
			end
		end)
		region(part, w, function(_button: number)
			ctx.click()
			ctx.send(w.cmd, if get(w.sig) >= 0.5 then 0 else 1)
			return nil
		end, function()
			return cleanLabel(w.label) .. (if get(w.sig) >= 0.5 then ": RUNNING" else ": stopped")
		end)
	end

	-- A rotary selector: a black knob with a white pointer line, and a
	-- legend window under it showing the selected position.
	builders.selector = function(gui, face, part, w)
		if w.label ~= "" then
			plate(gui, w.x + 0.03, w.y, w.w - 0.06, 0.2, w.label, 0.075)
		end
		local cx, cy = w.x + w.w / 2, w.y + 0.56
		local esc = box(gui, cx - 0.32, cy - 0.3, 0.64, 0.6, Color3.fromRGB(22, 22, 24))
		local _ = esc
		local n = #w.positions
		-- A black knob: a skirt, a body with a crowned top, and a bar across
		-- it, rounded at the ends, with a white line on the end that points.
		local frame = blockCFrame(face, cx, cy, 0, 0)
		piece(controls, frame, "disc", v3(0.44, 0.44, 0.035), v3(0, 0, 0.0175), PHENOLIC)
		piece(controls, frame, "disc", v3(0.34, 0.34, 0.11), v3(0, 0, 0.055), PHENOLIC)
		piece(controls, frame, "ellipsoid", v3(0.34, 0.34, 0.05), v3(0, 0, 0.11), PHENOLIC)
		local pointer = assembly(controls, frame)
		pointer.add("block", v3(0.08, 0.34, 0.05), v3(0, 0.02, 0.14), PHENOLIC)
		pointer.add("disc", v3(0.08, 0.08, 0.05), v3(0, 0.19, 0.14), PHENOLIC)
		pointer.add("disc", v3(0.08, 0.08, 0.05), v3(0, -0.15, 0.14), PHENOLIC)
		pointer.add("block", v3(0.024, 0.15, 0.052), v3(0, 0.105, 0.14), Color3.fromRGB(235, 235, 228))
		local readout = plate(gui, w.x + 0.08, w.y + 0.93, w.w - 0.16, 0.26, "", 0.12, true)
		local function index(): number
			return math.clamp(math.floor(get(w.sig) - w.base + 1.5), 1, n)
		end
		local last = 0
		table.insert(updaters, function()
			local i = index()
			if i ~= last then
				last = i
				local angle = if n > 1 then -120 + (i - 1) / (n - 1) * 240 else 0
				pointer.move(turned(angle))
				readout.Text = w.positions[i]
			end
		end)
		region(part, w, function(button: number)
			ctx.click()
			local i = math.clamp(index() + (if button == 2 then -1 else 1), 1, n)
			ctx.send(w.cmd, w.base + i - 1)
			return nil
		end, function()
			return cleanLabel(w.label) .. ": " .. w.positions[index()] .. "\nleft click = next, right click = previous"
		end)
	end

	-- A raise/lower control: a spring-return switch engraved LOWER and
	-- RAISE under a small horizontal position meter (or, for a setpoint, a
	-- digital readout). Hold the handle to one side; it springs back.
	builders.jog = function(gui, face, part, w)
		plate(gui, w.x + 0.04, w.y, w.w - 0.08, 0.2, w.label, 0.075)
		local suffix = if w.unit ~= "" then " " .. w.unit else ""
		local mx, my, mw, mh = w.x + 0.08, w.y + 0.27, w.w - 0.16, 0.3
		local show: (number) -> ()
		box(gui, mx - 0.04, my - 0.04, mw + 0.08, mh + 0.08, Color3.fromRGB(24, 24, 26))
		if w.digits then
			local canvas = overlay(face, part, mx, my, mw, mh)
			box(canvas, mx, my, mw, mh, SCREEN)
			local seg = sevenSeg(canvas, mx, my, mw, mh, #(string.gsub(string.format(w.fmt, -888.88), "[%.%+]", "")), DIGIT, DIGIT_DIM)
			show = function(v: number)
				seg((string.gsub(string.format(w.fmt, v), "%+", "")))
			end
		else
			box(gui, mx, my, mw, mh, PAPER)
			for i = 0, 10 do
				local major = i % 5 == 0
				box(gui, mx + 0.05 + (mw - 0.1) * i / 10 - 0.004, my + mh - (if major then 0.13 else 0.07), 0.008, if major then 0.13 else 0.07, INK).ZIndex = 2
			end
			local lo = text(gui, mx + 0.02, my + 0.015, 0.4, 0.11, string.format("%g", w.lo or 0), 0.072, INK, Enum.Font.Arial)
			lo.TextXAlignment = Enum.TextXAlignment.Left
			lo.ZIndex = 2
			local hi = text(gui, mx + mw - 0.42, my + 0.015, 0.4, 0.11, string.format("%g", w.hi or 100), 0.072, INK, Enum.Font.Arial)
			hi.TextXAlignment = Enum.TextXAlignment.Right
			hi.ZIndex = 2
			if w.unit ~= "" then
				text(gui, mx + mw / 2 - 0.3, my + 0.015, 0.6, 0.11, w.unit, 0.066, Color3.fromRGB(70, 70, 70), Enum.Font.ArialBold).ZIndex = 2
			end
			bezel(controls, face, mx - 0.02, my - 0.02, mw + 0.04, mh + 0.04, 0.08, BEZEL, 0.03)
			glassOver(face, mx + mw / 2, my + mh / 2, mw, mh)
			local pointer = block(controls, face, mx, my + mh / 2, 0.025, mh + 0.02, 0.025, Color3.fromRGB(205, 22, 22))
			local span = (w.hi or 100) - (w.lo or 0)
			show = function(v: number)
				local f = math.clamp((v - (w.lo or 0)) / span, 0, 1)
				pointer.CFrame = blockCFrame(face, mx + 0.05 + (mw - 0.1) * f, my + mh / 2, 0.05, 0)
			end
		end
		-- The spring-return switch.
		local cx = w.x + w.w / 2
		local ey = my + mh + 0.12
		local ew, eh = math.min(w.w - 0.1, 0.9), math.max(0.4, w.y + w.h - ey - 0.02)
		box(gui, cx - ew / 2, ey, ew, eh, Color3.fromRGB(22, 22, 24))
		local white = Color3.fromRGB(232, 232, 224)
		local l = text(gui, cx - ew / 2 + 0.03, ey + 0.02, ew / 2, 0.11, "LOWER", 0.062, white, Enum.Font.ArialBold)
		l.TextXAlignment = Enum.TextXAlignment.Left
		local r = text(gui, cx - 0.03, ey + 0.02, ew / 2, 0.11, "RAISE", 0.062, white, Enum.Font.ArialBold)
		r.TextXAlignment = Enum.TextXAlignment.Right
		local turn = pistolGrip(face, cx, ey + eh * 0.66, 0, 0.85)
		local last = math.huge
		table.insert(updaters, function()
			local v = get(w.sig)
			if v ~= last then
				last = v
				show(v)
			end
		end)
		region(part, w, function(_button: number, u: number)
			ctx.click()
			local up = u > cx
			turn(if up then 40 else -40)
			return {
				hold = w.cmd,
				value = if up then 1 else -1,
				onRelease = function()
					turn(0)
				end,
			}
		end, function()
			return string.format("%s: " .. w.fmt .. "%s\nhold the switch to the left to lower, to the right to raise", cleanLabel(w.label), get(w.sig), suffix)
		end)
	end

	-- A strip-chart recorder: a dark case with a glazed door, chart paper
	-- ruled in ten divisions, and pens that write along a line near the top
	-- of the window while the paper carries the trace down and away. A
	-- legend under the window names each pen and its range.
	builders.recorder = function(gui, face, part, w)
		plate(gui, w.x + 0.1, w.y, w.w - 0.2, 0.22, w.label, 0.115)
		local cx, cy, cw, ch = w.x, w.y + 0.27, w.w, w.h - 0.27
		local case = box(gui, cx, cy, cw, ch, Color3.fromRGB(58, 60, 62))
		outline(case, Color3.fromRGB(30, 30, 32), 2)
		bezel(controls, face, cx, cy, cw, ch, 0.16, Color3.fromRGB(44, 46, 48), 0.07)
		local legendH = 0.12 * #w.pens + 0.08
		local gx, gy, gw, gh = cx + 0.12, cy + 0.1, cw - 0.24, ch - 0.22 - legendH
		box(gui, gx, gy, gw, gh, Color3.fromRGB(240, 241, 230))
		bezel(controls, face, gx, gy, gw, gh, 0.05, Color3.fromRGB(24, 24, 26), 0.03)
		-- Ruling: ten value divisions, a heavier line every fifth, and time
		-- lines across the paper.
		for i = 0, 10 do
			local line = box(gui, gx + gw * i / 10 - 0.006, gy, 0.012, gh, if i % 5 == 0 then Color3.fromRGB(122, 162, 126) else Color3.fromRGB(184, 206, 184))
			line.ZIndex = 2
		end
		for i = 1, 7 do
			local line = box(gui, gx, gy + gh * i / 8, gw, 0.01, Color3.fromRGB(196, 214, 196))
			line.ZIndex = 2
		end
		-- Scale figures along the top edge, for the first pen's range.
		local first = w.pens[1]
		for i = 0, 2 do
			local v = first.lo + (first.hi - first.lo) * i / 2
			local label = text(gui, gx + gw * i / 2 - 0.3, gy + 0.02, 0.6, 0.12, string.format(if math.abs(v) >= 100 or v % 1 == 0 then "%.0f" else "%.1f", v), 0.09, Color3.fromRGB(70, 96, 72), Enum.Font.SourceSans)
			label.ZIndex = 3
		end
		-- Glass in the door.
		local glass = block(controls, face, gx + gw / 2, gy + gh / 2, gw, gh, 0.02, Color3.fromRGB(200, 220, 230))
		glass.CFrame = blockCFrame(face, gx + gw / 2, gy + gh / 2, 0.12, 0)
		glass.Material = Enum.Material.Glass
		glass.Transparency = 0.88
		glass.Reflectance = 0.08
		-- Door latch.
		cylinder(controls, face, cx + cw - 0.06, cy + ch / 2, 0.07, 0.1, Color3.fromRGB(150, 150, 150)).Material = Enum.Material.Metal
		local penY = gy + 0.16
		local N = 48
		local stepY = (gh - 0.2) / N
		local pens = {}
		for k, pen in w.pens do
			local legend = text(gui, cx + 0.12, gy + gh + 0.04 + (k - 1) * 0.12, cw - 0.24, 0.12, string.format("%s  %s  %g to %g %s", string.upper(pen.color), pen.name or "", pen.lo, pen.hi, pen.unit or ""), 0.085, Color3.fromRGB(226, 226, 218), Enum.Font.SourceSans)
			legend.TextXAlignment = Enum.TextXAlignment.Left
			legend.TextWrapped = false
			local dots = table.create(N)
			for i = 1, N do
				local d = box(gui, gx, gy, 0.03, stepY + 0.012, PEN[pen.color])
				d.Visible = false
				d.ZIndex = 4
				dots[i] = d
			end
			local index = box(gui, gx, penY - 0.07, 0.05, 0.14, PEN[pen.color])
			index.ZIndex = 5
			table.insert(pens, { def = pen, dots = dots, index = index, values = {} :: { number } })
		end
		local lastSample = -math.huge
		table.insert(updaters, function()
			local now = os.clock()
			local sample = now - lastSample >= 5
			if sample then
				lastSample = now
			end
			for _, pen in pens do
				local f = math.clamp((get(pen.def.sig) - pen.def.lo) / (pen.def.hi - pen.def.lo), 0, 1)
				pen.index.Position = UDim2.fromOffset(px(gx + gw * f - 0.025), px(penY - 0.07))
				if sample then
					local values = pen.values
					if #values == 0 then
						-- The chart has been running all along: start with a
						-- steady trace at the present value.
						for _ = 1, N - 1 do
							table.insert(values, f)
						end
					end
					table.insert(values, 1, f)
					if #values > N then
						table.remove(values)
					end
					for i, v in values do
						local d = pen.dots[i]
						d.Visible = true
						d.Position = UDim2.fromOffset(px(gx + gw * v - 0.015), px(penY + (i - 1) * stepY))
					end
				end
			end
		end)
		region(part, w, nil, function()
			local parts = { cleanLabel(w.label) }
			for _, pen in w.pens do
				table.insert(parts, string.format("%s pen, %s: %.1f %s", pen.color, pen.name or pen.sig, get(pen.sig), pen.unit or ""))
			end
			return table.concat(parts, "\n")
		end)
	end

	-- Mimic lines: coloured strips painted on the board that trace a flow
	-- path between the switches of the equipment on it.
	builders.mimic = function(gui, _face, _part, w)
		local t = w.width or 0.07
		local pts = w.pts
		for i = 1, #pts - 1 do
			local x1, y1, x2, y2 = pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]
			local seg = box(gui, math.min(x1, x2) - t / 2, math.min(y1, y2) - t / 2, math.abs(x2 - x1) + t, math.abs(y2 - y1) + t, MIMIC[w.color] or INK)
			seg.ZIndex = 0
		end
	end

	builders.ann = function(gui, face, part, w)
		local cols, rows = math.max(4, math.floor(w.w / 1.6 + 0.5)), 3
		local panelId = part:GetAttribute("Panel")
		local tw, th = w.w / cols, w.h / rows
		-- Window frames: each legend sits in its own recess.
		for c = 0, cols do
			block(controls, face, math.clamp(c * tw, 0.04, w.w - 0.04), w.h / 2, 0.08, w.h, 0.14, BEZEL)
		end
		for r = 0, rows do
			block(controls, face, w.w / 2, math.clamp(r * th, 0.04, w.h - 0.04), w.w, 0.08, 0.14, BEZEL)
		end
		for i, alarm in w.alarms do
			local c, r = (i - 1) % cols, (i - 1) // cols
			if r < rows then
				local tile = box(gui, c * tw + 0.04, r * th + 0.04, tw - 0.08, th - 0.08, ANN_DARK)
				local label = text(gui, c * tw + 0.06, r * th + 0.05, tw - 0.12, th - 0.1, alarm.text, 0.14, ANN_DARK_TEXT, Enum.Font.ArialBold)
				local index = AlarmList.index[alarm.id]
				local urgent = alarm.id == "az5" or alarm.id == "chan.rupture" or alarm.id == "core.damage" or alarm.id == "rs.press"
				annTiles[index] = { tile = tile, label = label, state = 0, urgent = urgent, panel = panelId }
			end
		end
		for i = #w.alarms + 1, cols * rows do
			local c, r = (i - 1) % cols, (i - 1) // cols
			box(gui, c * tw + 0.04, r * th + 0.04, tw - 0.08, th - 0.08, ANN_SPARE)
		end
		table.insert(regions[part], {
			x = 0,
			y = 0,
			w = w.w,
			h = w.h,
			widget = w,
			press = function()
				ctx.click()
				ctx.send("ann.ack", 1)
				return nil
			end,
			tip = function()
				return "Annunciators: click to acknowledge. Fast flash = new alarm, steady = acknowledged,\nslow flash = cleared, waiting for RESET."
			end,
		})
	end

	-- Core map: one coloured cell per lattice position.
	builders.coremap = function(gui, face, part, w)
		gui = overlay(face, part, w.x, w.y, w.w, w.h)
		bezel(controls, face, w.x, w.y, w.w, w.h, 0.14, BEZEL, 0.08)
		local L = CoreLayout.get()
		local G = L.grid
		local cell = math.floor((w.w - 0.1) * PPS / G)
		local size = cell * G
		local ox = px(w.x) + (px(w.w) - size) // 2
		local oy = px(w.y) + px(0.3)
		local back = box(gui, w.x, w.y, w.w, w.h, Color3.fromRGB(14, 14, 16))
		local _ = back
		local title = plate(gui, w.x + 0.06, w.y + 0.04, w.w - 0.12, 0.22, "CHANNEL CARTOGRAM", 0.13, true)
		local frames = table.create(L.nCells)
		local lastByte = table.create(L.nCells, -1)
		for c = 1, L.nCells do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = PALETTE[1]
			f.Position = UDim2.fromOffset(ox + (L.cellGX[c] - 1) * cell, oy + (L.cellGY[c] - 1) * cell)
			f.Size = UDim2.fromOffset(cell - 1, cell - 1)
			f.Parent = gui
			frames[c] = f
		end
		local modeNames = { "FLUX", "POWER", "DRYOUT MARGIN", "CHANNEL FLOW", "EXIT QUALITY", "FUEL TEMP", "XENON", "GRAPHITE TEMP" }
		local scales = { { 2.5, "x mean" }, { 3.2, "MW" }, { 4, "" }, { 9 * 3.6, "t/h" }, { 40, "%" }, { 2000, "C" }, { 2.5, "x equil." }, { 800, "C" } }
		local current: buffer? = nil
		out.setMap = function(buf: buffer)
			current = buf
			local mode = buffer.readu8(buf, 0)
			title.Text = string.format("CHANNEL CARTOGRAM   %s   RED LAMP = %g %s", modeNames[mode] or "?", scales[mode] and scales[mode][1] or 0, scales[mode] and scales[mode][2] or "")
			local NC = L.nCells
			for c = 1, NC do
				local v = buffer.readu8(buf, c)
				local flag = buffer.readu8(buf, NC + c)
				local key = v + flag * 256
				if key ~= lastByte[c] then
					lastByte[c] = key
					local color
					if L.cellKind[c] == 2 then
						-- Rod channel: light when withdrawn, dark when inserted, tinted by type.
						local rod = L.rods[L.cellRef[c]]
						color = ROD_COLOR[rod.kind]:Lerp(Color3.new(0, 0, 0), v / 255 * 0.8)
					elseif flag == 1 then
						color = Color3.fromRGB(255, 0, 255)
					elseif flag == 3 then
						color = Color3.fromRGB(255, 255, 255)
					else
						color = PALETTE[v // 8 + 1]
					end
					frames[c].BackgroundColor3 = color
				end
			end
		end
		table.insert(regions[part], {
			x = w.x,
			y = w.y,
			w = w.w,
			h = w.h,
			widget = w,
			tip = function()
				return "Channel cartogram: one lamp per channel, dark through green, yellow and amber to red.\nRod channels are tinted by type and darken as the rod goes in.\nMagenta = ruptured channel, white = channel in dryout."
			end,
		} :: any)
		out.mapCellAt = function(u: number, v: number): number
			local gx = (px(u) - ox) // cell + 1
			local gy = (px(v) - oy) // cell + 1
			if gx < 1 or gx > G or gy < 1 or gy > G then
				return 0
			end
			return L.gridToCell[(gy - 1) * G + gx]
		end
		out.mapInfo = function(c: number): string?
			local buf = current
			if c == 0 or not buf then
				return nil
			end
			local mode = buffer.readu8(buf, 0)
			local v = buffer.readu8(buf, c)
			local label = string.format("%02d-%02d", L.cellGX[c], L.cellGY[c])
			if L.cellKind[c] == 2 then
				local rod = L.rods[L.cellRef[c]]
				return string.format("Rod %s (%s): %.0f%% inserted", label, rod.kind, v / 255 * 100)
			end
			local sc = scales[mode]
			local flag = buffer.readu8(buf, L.nCells + c)
			local note = if flag == 1 then "  RUPTURED" elseif flag == 2 then "  FLOW RESTRICTED" elseif flag == 3 then "  DRYOUT" else ""
			return string.format("Channel %s: %s %.2f %s%s", label, modeNames[mode] or "", v / 255 * (sc and sc[1] or 1), sc and sc[2] or "", note)
		end
	end

	-- Rod select matrix: one button per rod, laid out as in the core.
	builders.rodmatrix = function(gui, face, part, w)
		bezel(controls, face, w.x, w.y, w.w, w.h, 0.1, BEZEL, 0.07)
		local L = CoreLayout.get()
		local G = L.grid
		local pitch = (w.w - 0.1) * PPS / G
		local ox, oy = px(w.x + 0.05), px(w.y + 0.3)
		local scaleY = (w.h - 0.35) * PPS / G
		local back = box(gui, w.x, w.y, w.w, w.h, Color3.fromRGB(26, 28, 30))
		outline(back, Color3.fromRGB(90, 92, 90), 2)
		local title = text(gui, w.x + 0.1, w.y + 0.03, w.w - 0.2, 0.25, "ROD SELECT   white RR  green AR  yellow LAR  red AZ  blue USP   lit = selected", 0.105, Color3.fromRGB(230, 230, 220))
		title.TextXAlignment = Enum.TextXAlignment.Left
		local size = math.max(6, math.floor(pitch * 1.9))
		local buttons = table.create(L.nRods)
		local centers = table.create(L.nRods)
		for i, rod in L.rods do
			local cx = ox + (rod.gx - 0.5) * pitch
			local cy = oy + (rod.gy - 0.5) * scaleY
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = ROD_COLOR[rod.kind]:Lerp(Color3.fromRGB(30, 30, 30), 0.5)
			f.Position = UDim2.fromOffset(math.floor(cx - size / 2), math.floor(cy - size / 2))
			f.Size = UDim2.fromOffset(size, size)
			f.Parent = gui
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.Color = Color3.fromRGB(255, 255, 255)
			stroke.Enabled = false
			stroke.Parent = f
			buttons[i] = { frame = f, stroke = stroke, flag = -1, depth = -1 }
			centers[i] = { cx / PPS, cy / PPS }
		end
		-- Each button is a backlit pushbutton tinted by rod type; it lights up
		-- when its rod is selected.
		table.insert(rodListeners, function(buf: buffer)
			local NC = L.nCells
			for i, rod in L.rods do
				local b = buttons[i]
				local flag = buffer.readu8(buf, 2 * NC + i)
				local depth = buffer.readu8(buf, rod.cell)
				if flag ~= b.flag or depth ~= b.depth then
					b.flag = flag
					b.depth = depth
					local selected = flag % 2 == 1
					b.stroke.Enabled = selected
					b.frame.BackgroundColor3 = if selected then ROD_COLOR[rod.kind]:Lerp(Color3.new(1, 1, 1), 0.55) else ROD_COLOR[rod.kind]:Lerp(Color3.fromRGB(30, 30, 30), 0.5)
				end
			end
		end)
		local function nearest(u: number, v: number): number
			local best, bestD = 0, (size / PPS) ^ 2
			for i, c in centers do
				local d = (c[1] - u) ^ 2 + (c[2] - v) ^ 2
				if d < bestD then
					best, bestD = i, d
				end
			end
			return best
		end
		table.insert(regions[part], {
			x = w.x,
			y = w.y,
			w = w.w,
			h = w.h,
			widget = w,
			press = function(_button: number, u: number, v: number)
				local i = nearest(u, v)
				if i > 0 then
					ctx.click()
					ctx.send("rod.select", i)
				end
				return nil
			end,
			tip = function()
				return "Rod select matrix: one pushbutton per rod, laid out as in the core. Click a rod to select or deselect it; a selected rod's button lights."
			end,
		} :: any)
		out.rodAt = function(u: number, v: number): string?
			local i = nearest(u, v)
			if i == 0 then
				return nil
			end
			local rod = L.rods[i]
			local b = buttons[i]
			local full = if rod.kind == "USP" then 3.5 else 6.5
			return string.format("Rod %s (%s): %.2f m inserted", rod.label, rod.kind, math.max(b.depth, 0) / 255 * full)
		end
	end

	-- The rod position board: a synchro dial for every rod, laid out as in
	-- the core, as on the RBMK. Each dial reads metres inserted, 0 at the
	-- top-left of its scale; its rim is coloured by rod type; a red lamp
	-- lights at full out and a green one at full in.
	builders.rodpos = function(gui, face, part, w)
		bezel(controls, face, w.x, w.y, w.w, w.h, 0.14, BEZEL, 0.08)
		box(gui, w.x, w.y, w.w, w.h, Color3.fromRGB(70, 76, 72))
		plate(gui, w.x + 0.06, w.y + 0.04, w.w - 0.12, 0.22, "ROD POSITION INDICATORS   METRES INSERTED", 0.115, true)
		local L = CoreLayout.get()
		local G = L.grid
		local size = math.min(w.w - 0.1, w.h - 0.36)
		local cell = size / G
		local ox, oy = w.x + (w.w - size) / 2, w.y + 0.31
		local d = cell * 2.45
		local dials = table.create(L.nRods)
		local centers = table.create(L.nRods)
		for i, rod in L.rods do
			local cx, cy = ox + (rod.gx - 0.5) * cell, oy + (rod.gy - 0.5) * cell
			local dial = box(gui, cx - d / 2, cy - d / 2, d, d, PAPER)
			round(dial)
			local rim = Instance.new("UIStroke")
			rim.Thickness = 2
			rim.Color = ROD_COLOR[rod.kind]:Lerp(Color3.fromRGB(40, 40, 40), 0.25)
			rim.Parent = dial
			local pivot = Instance.new("Frame")
			pivot.BackgroundTransparency = 1
			pivot.BorderSizePixel = 0
			pivot.AnchorPoint = Vector2.new(0.5, 0.5)
			pivot.Position = UDim2.fromOffset(px(cx), px(cy))
			pivot.Size = UDim2.fromOffset(2, math.max(4, px(d * 0.82)))
			pivot.Rotation = -135
			pivot.ZIndex = 3
			pivot.Parent = gui
			local hand = Instance.new("Frame")
			hand.BorderSizePixel = 0
			hand.BackgroundColor3 = INK
			hand.Size = UDim2.fromScale(1, 0.5)
			hand.ZIndex = 3
			hand.Parent = pivot
			local outLamp = box(gui, cx - d * 0.42, cy - d * 0.42, d * 0.2, d * 0.2, Color3.fromRGB(70, 22, 20))
			round(outLamp)
			outLamp.ZIndex = 4
			local inLamp = box(gui, cx - d * 0.42, cy + d * 0.22, d * 0.2, d * 0.2, Color3.fromRGB(20, 60, 28))
			round(inLamp)
			inLamp.ZIndex = 4
			dials[i] = { pivot = pivot, outLamp = outLamp, inLamp = inLamp, depth = -1 }
			centers[i] = { cx, cy }
		end
		table.insert(rodListeners, function(buf: buffer)
			for i, rod in L.rods do
				local dial = dials[i]
				local depth = buffer.readu8(buf, rod.cell)
				if depth ~= dial.depth then
					dial.depth = depth
					dial.pivot.Rotation = -135 + 270 * depth / 255
					dial.outLamp.BackgroundColor3 = if depth <= 2 then LAMP.red[1] else LAMP.red[2]
					dial.inLamp.BackgroundColor3 = if depth >= 253 then LAMP.green[1] else LAMP.green[2]
				end
			end
		end)
		table.insert(regions[part], {
			x = w.x,
			y = w.y,
			w = w.w,
			h = w.h,
			widget = w,
			tip = function()
				return "Rod position indicators: one synchro dial per rod, laid out as in the core, reading metres inserted.\nRed lamp: rod fully withdrawn. Green lamp: rod fully inserted. The rim colour is the rod type."
			end,
			tipAt = function(u: number, v: number): string?
				local best, bestD = 0, (d * 0.7) ^ 2
				for i, c in centers do
					local dd = (c[1] - u) ^ 2 + (c[2] - v) ^ 2
					if dd < bestD then
						best, bestD = i, dd
					end
				end
				if best == 0 then
					return nil
				end
				local rod = L.rods[best]
				local full = if rod.kind == "USP" then 3.5 else 6.5
				local depth = math.max(dials[best].depth, 0)
				local state = if depth >= 253 then "  FULL IN" elseif depth <= 2 then "  FULL OUT" else ""
				return string.format("Rod %s (%s): %.2f m inserted%s", rod.label, rod.kind, depth / 255 * full, state)
			end,
		} :: any)
	end

	-- The four-rod display: for up to four selected rods, the rod's
	-- coordinates, its position in metres inserted, and FULL IN / FULL OUT /
	-- STUCK lamps.
	builders.fourrod = function(gui, face, part, w)
		gui = overlay(face, part, w.x, w.y, w.w, w.h)
		bezel(controls, face, w.x, w.y, w.w, w.h, 0.08, BEZEL, 0.05)
		box(gui, w.x, w.y, w.w, w.h, Color3.fromRGB(44, 46, 48))
		local L = CoreLayout.get()
		local cw = w.w / 4
		local columns = {}
		for k = 1, 4 do
			local x0 = w.x + (k - 1) * cw
			local id = text(gui, x0 + 0.08, w.y + 0.08, cw - 0.16, 0.28, "--", 0.17, Color3.fromRGB(236, 236, 226), Enum.Font.ArialBold)
			id.BackgroundTransparency = 0
			id.BackgroundColor3 = Color3.fromRGB(14, 14, 16)
			local screen = box(gui, x0 + 0.08, w.y + 0.44, cw - 0.16, 0.6, SCREEN)
			outline(screen, Color3.fromRGB(70, 70, 70), 1)
			local show = sevenSeg(gui, x0 + 0.08, w.y + 0.44, cw - 0.16, 0.6, 3, DIGIT, DIGIT_DIM)
			local lamps = {}
			for j, def in { { "IN", LAMP.green }, { "OUT", LAMP.red }, { "STUCK", LAMP.amber } } do
				local lx = x0 + 0.1 + (j - 1) * (cw - 0.2) / 3
				local bulb = box(gui, lx + (cw - 0.2) / 6 - 0.08, w.y + 1.16, 0.16, 0.16, def[2][2])
				round(bulb)
				local t = text(gui, lx, w.y + 1.36, (cw - 0.2) / 3, 0.14, def[1], 0.075, Color3.fromRGB(210, 210, 200), Enum.Font.ArialBold)
				t.TextWrapped = false
				lamps[j] = { bulb = bulb, colors = def[2] }
			end
			columns[k] = { id = id, show = show, lamps = lamps }
		end
		local shown: { number } = {}
		table.insert(rodListeners, function(buf: buffer)
			local NC = L.nCells
			table.clear(shown)
			for i in L.rods do
				if buffer.readu8(buf, 2 * NC + i) % 2 == 1 and #shown < 4 then
					table.insert(shown, i)
				end
			end
			for k, col in columns do
				local i = shown[k]
				if i then
					local rod = L.rods[i]
					local flag = buffer.readu8(buf, 2 * NC + i)
					local depth = buffer.readu8(buf, rod.cell)
					local full = if rod.kind == "USP" then 3.5 else 6.5
					col.id.Text = rod.label
					col.show(string.format("%.2f", depth / 255 * full))
					local on = { depth >= 253, depth <= 2, (flag // 2) % 2 == 1 }
					for j, lampDef in col.lamps do
						lampDef.bulb.BackgroundColor3 = lampDef.colors[if on[j] then 1 else 2]
					end
				else
					col.id.Text = "--"
					col.show("")
					for _, lampDef in col.lamps do
						lampDef.bulb.BackgroundColor3 = lampDef.colors[2]
					end
				end
			end
		end)
		region(part, w, nil, function()
			return "Four rod display: the rods selected for movement (up to four), with their coordinates and metres inserted.\nLamps: FULL IN, FULL OUT, STUCK."
		end)
	end

	-- The rod movement switch: a pistol grip that springs back to OFF. Hold
	-- it to the left to insert the selected rods, to the right to withdraw.
	builders.rodswitch = function(gui, face, part, w)
		plate(gui, w.x + 0.05, w.y, w.w - 0.1, 0.22, w.label, 0.085)
		-- A large engraved escutcheon: INSERT to the left, OFF at the top,
		-- WITHDRAW to the right; the pistol grip springs back to OFF.
		local cx = w.x + w.w / 2
		local ey, ew, eh = w.y + 0.3, math.min(w.w - 0.06, 1.3), w.h - 0.32
		box(gui, cx - ew / 2, ey, ew, eh, Color3.fromRGB(22, 22, 24))
		local white = Color3.fromRGB(232, 232, 224)
		local l = text(gui, cx - ew / 2 + 0.04, ey + eh - 0.2, ew / 2, 0.13, w.positions[1], 0.075, white, Enum.Font.ArialBold)
		l.TextXAlignment = Enum.TextXAlignment.Left
		text(gui, cx - 0.3, ey + 0.03, 0.6, 0.13, w.positions[2], 0.075, white, Enum.Font.ArialBold)
		local r = text(gui, cx - 0.04, ey + eh - 0.2, ew / 2, 0.13, w.positions[3], 0.075, white, Enum.Font.ArialBold)
		r.TextXAlignment = Enum.TextXAlignment.Right
		local turn = pistolGrip(face, cx, ey + eh * 0.62, 0, 1.25)
		region(part, w, function(_button: number, u: number)
			ctx.click()
			local insert = u < cx
			turn(if insert then -45 else 45)
			return {
				hold = w.cmd,
				value = if insert then 1 else -1,
				onRelease = function()
					turn(0)
				end,
			}
		end, function()
			return "Rod movement switch: hold to the left to INSERT, to the right to WITHDRAW the selected rods.\nIt springs back to OFF when released."
		end)
	end

	-- A manual/automatic control station: process scale with setpoint index,
	-- AUTO and MAN lamps, an output meter, and A / M / lower / raise buttons.
	builders.station = function(gui, face, part, w)
		plate(gui, w.x, w.y, w.w, 0.22, w.label, 0.1)
		local x0, y0, cw, ch = w.x, w.y + 0.26, w.w, w.h - 0.26
		local case = box(gui, x0, y0, cw, ch, Color3.fromRGB(70, 72, 74))
		outline(case, Color3.fromRGB(30, 30, 32), 2)
		bezel(controls, face, x0, y0, cw, ch, 0.12, BEZEL, 0.05)
		local sx, sy, sw, sh = x0 + 0.1, y0 + 0.1, 0.5, 0.88
		box(gui, sx, sy, sw, sh, PAPER)
		local span = w.hi - w.lo
		local function yOf(v: number): number
			return sy + 0.07 + (sh - 0.14) * (1 - math.clamp((v - w.lo) / span, 0, 1))
		end
		for i = 0, 10 do
			local major = i % 5 == 0
			local tw = if major then 0.2 else 0.12
			box(gui, sx + sw - tw, yOf(w.lo + span * i / 10) - 0.005, tw, 0.01, INK).ZIndex = 2
		end
		local hiText = text(gui, sx + 0.03, yOf(w.hi) - 0.02, 0.3, 0.1, string.format("%g", w.hi), 0.075, INK, Enum.Font.Arial)
		hiText.TextXAlignment = Enum.TextXAlignment.Left
		hiText.ZIndex = 2
		local loText = text(gui, sx + 0.03, yOf(w.lo) - 0.08, 0.3, 0.1, string.format("%g", w.lo), 0.075, INK, Enum.Font.Arial)
		loText.TextXAlignment = Enum.TextXAlignment.Left
		loText.ZIndex = 2
		local unitText = text(gui, sx + 0.03, sy + sh / 2 - 0.05, 0.3, 0.1, w.unit, 0.07, Color3.fromRGB(70, 70, 70), Enum.Font.ArialBold)
		unitText.TextXAlignment = Enum.TextXAlignment.Left
		unitText.ZIndex = 2
		local spMark = box(gui, sx, sy, 0.09, 0.05, Color3.fromRGB(215, 30, 26))
		spMark.ZIndex = 3
		spMark.Visible = w.sp ~= nil or w.spValue ~= nil
		local pointer = block(controls, face, sx + sw / 2, yOf(w.lo), sw + 0.02, 0.03, 0.03, Color3.fromRGB(20, 20, 20))
		local setAuto = lens(controls, face, x0 + 1.02, y0 + 0.28, 0.16, LAMP.white)
		local setMan = lens(controls, face, x0 + 1.02, y0 + 0.66, 0.16, LAMP.amber)
		local light = Color3.fromRGB(220, 220, 210)
		text(gui, x0 + 0.74, y0 + 0.4, 0.56, 0.1, "AUTO", 0.07, light, Enum.Font.ArialBold).ZIndex = 2
		text(gui, x0 + 0.74, y0 + 0.78, 0.56, 0.1, "MAN", 0.07, light, Enum.Font.ArialBold).ZIndex = 2
		-- Output meter, 0 to 100 per cent.
		local ox, oy, ow, oh = x0 + 0.1, y0 + 1.04, cw - 0.2, 0.18
		box(gui, ox, oy, ow, oh, PAPER)
		for i = 0, 4 do
			box(gui, ox + 0.04 + (ow - 0.08) * i / 4 - 0.005, oy + oh - (if i % 2 == 0 then 0.1 else 0.06), 0.01, if i % 2 == 0 then 0.1 else 0.06, INK).ZIndex = 2
		end
		local outLabel = text(gui, ox + 0.03, oy + 0.01, 0.6, 0.08, "OUTPUT %", 0.06, Color3.fromRGB(70, 70, 70), Enum.Font.ArialBold)
		outLabel.TextXAlignment = Enum.TextXAlignment.Left
		outLabel.ZIndex = 2
		local outPointer = block(controls, face, ox, oy + oh / 2, 0.025, oh + 0.02, 0.03, Color3.fromRGB(215, 25, 25))
		-- Pushbuttons.
		local legends = { "A", "M", "<", ">" }
		local capColors = { BUTTON.white, Color3.fromRGB(230, 170, 40), BUTTON.black, BUTTON.black }
		local bw = (cw - 0.2) / 4
		local caps = {}
		for k = 1, 4 do
			local bx = x0 + 0.1 + (k - 0.5) * bw
			text(gui, bx - bw / 2, y0 + 1.25, bw, 0.1, legends[k], 0.09, light, Enum.Font.ArialBold).ZIndex = 2
			caps[k] = block(controls, face, bx, y0 + 1.47, bw - 0.06, 0.16, 0.05, capColors[k])
		end
		local last = ""
		table.insert(updaters, function()
			local v = get(w.sig)
			local sp = if w.sp then get(w.sp) else w.spValue
			local out = get(w.out)
			local auto = get(w.auto) >= 0.5
			local key = string.format("%.4g|%s|%.3g|%s", v, tostring(sp), out, tostring(auto))
			if key == last then
				return
			end
			last = key
			pointer.CFrame = blockCFrame(face, sx + sw / 2, yOf(v), 0.05, 0)
			if sp then
				spMark.Position = UDim2.fromOffset(px(sx), px(yOf(sp) - 0.025))
			end
			outPointer.CFrame = blockCFrame(face, ox + 0.04 + (ow - 0.08) * math.clamp(out / 100, 0, 1), oy + oh / 2, 0.05, 0)
			setAuto(auto)
			setMan(not auto)
		end)
		region(part, w, function(_button: number, u: number, v: number)
			if v < y0 + 1.22 then
				return nil
			end
			local k = math.clamp(math.floor((u - x0 - 0.1) / bw) + 1, 1, 4)
			ctx.click()
			local cap = caps[k]
			local home = cap.CFrame
			cap.CFrame = home - face.normal * 0.03 * S
			if k <= 2 then
				task.delay(0.15, function()
					cap.CFrame = home
				end)
				ctx.send(w.autoCmd, if k == 1 then 1 else 0)
				return nil
			end
			return {
				hold = w.cmd,
				value = if k == 4 then 1 else -1,
				onRelease = function()
					cap.CFrame = home
				end,
			}
		end, function()
			local sp = if w.sp then get(w.sp) else w.spValue
			local spText = if sp then string.format(", setpoint " .. w.fmt, sp) else ""
			return string.format("%s: " .. w.fmt .. " %s%s, output %.0f%%, %s\nA = automatic, M = manual. The arrows move the %s.%s", cleanLabel(w.label), get(w.sig), w.unit, spText, get(w.out), if get(w.auto) >= 0.5 then "AUTO" else "MANUAL", string.lower(w.adjusts), if w.tip then "\n" .. w.tip else "")
		end)
	end

	-- Annunciator TEST: lights every window on this panel while held.
	builders.lamptest = function(gui, face, part, w)
		local d = 0.3
		local cx, cy = w.x + w.w / 2, w.y + d / 2 + 0.09
		local cap = pushbutton(controls, blockCFrame(face, cx, cy, 0, 0), BUTTON.white)
		local plateY = cy + d / 2 + 0.12
		plate(gui, w.x - 0.02, plateY, w.w + 0.04, math.min(0.3, w.y + w.h - plateY), w.label, 0.075)
		local panelId = part:GetAttribute("Panel")
		region(part, w, function()
			ctx.click()
			cap.move(CFrame.new(0, 0, -0.05 * S))
			testing[panelId] = true
			return {
				onRelease = function()
					testing[panelId] = nil
					cap.move(CFrame.new())
				end,
			}
		end, function()
			return "Annunciator TEST: hold to light every window on this panel."
		end)
	end

	builders.axial = function(gui, face, part, w)
		gui = overlay(face, part, w.x, w.y, w.w, w.h)
		bezel(controls, face, w.x, w.y, w.w, w.h, 0.14, BEZEL, 0.08)
		box(gui, w.x, w.y, w.w, w.h, Color3.fromRGB(14, 14, 16))
		plate(gui, w.x + 0.06, w.y + 0.04, w.w - 0.12, 0.22, "AXIAL", 0.13, true)
		text(gui, w.x, w.y + 0.3, w.w, 0.18, "TOP", 0.11, Color3.fromRGB(190, 190, 180))
		text(gui, w.x, w.y + w.h - 0.2, w.w, 0.18, "BOTTOM", 0.11, Color3.fromRGB(190, 190, 180))
		local N = 14
		local y0, rowH = w.y + 0.5, (w.h - 0.75) / N
		local bars = {}
		for z = 1, N do
			local bar = box(gui, w.x + 0.06, y0 + (z - 1) * rowH + 0.03, 0.1, rowH - 0.06, Color3.fromRGB(255, 120, 40))
			bars[z] = bar
		end
		local maxW = w.w - 0.12
		table.insert(updaters, function()
			for z = 1, N do
				local v = get("core.ax" .. z)
				bars[z].Size = UDim2.fromOffset(math.max(1, px(maxW * math.clamp(v / 2, 0, 1))), px(rowH - 0.06))
				-- Neon bargraph: orange, burning brighter and redder as a layer peaks.
				bars[z].BackgroundColor3 = if v > 1.6 then Color3.fromRGB(255, 50, 36) elseif v > 1.4 then Color3.fromRGB(255, 176, 60) else Color3.fromRGB(255, 120, 40)
			end
		end)
		region(part, w, nil, function()
			return string.format("Axial power shape, top of core at the top.\nPeak %.2f, offset %+.0f%% (positive = top-heavy)", get("core.kz"), get("core.offset"))
		end)
	end

	builders.computer = function(gui, face, part, w)
		gui = overlay(face, part, w.x, w.y, w.w, w.h)
		bezel(controls, face, w.x, w.y, w.w, w.h, 0.16, BEZEL, 0.09)
		local screen = box(gui, w.x, w.y, w.w, w.h, TUBE)
		outline(screen, Color3.fromRGB(60, 60, 60), 3)
		local left = text(gui, w.x + 0.1, w.y + 0.06, 3.5, w.h - 0.12, "", 0.165, PHOSPHOR, Enum.Font.Code)
		left.TextXAlignment = Enum.TextXAlignment.Left
		left.TextYAlignment = Enum.TextYAlignment.Top
		left.TextWrapped = false
		local right = text(gui, w.x + 3.65, w.y + 0.06, w.w - 3.75, w.h - 0.12, "", 0.14, Color3.fromRGB(84, 214, 112), Enum.Font.Code)
		right.TextXAlignment = Enum.TextXAlignment.Left
		right.TextYAlignment = Enum.TextYAlignment.Top
		local function clock(t: number): string
			local s = math.floor(t)
			return string.format("%02d:%02d:%02d", s // 3600, (s // 60) % 60, s % 60)
		end
		local tickCount = 0
		table.insert(updaters, function()
			tickCount += 1
			if tickCount % 3 ~= 1 then
				return
			end
			left.Text = table.concat({
				string.format("RBMK-800 UNIT   T+%s", clock(get("time"))),
				string.format("THERMAL %6.0f MW %6.2f%%", get("n.thermal"), get("n.power")),
				string.format("GROSS   %6.0f MW  NET %4.0f", get("plant.gross"), get("plant.net")),
				string.format("MARGIN  %6.0f RODS", get("core.orm")),
				string.format("XENON   %+6.2f %%dk", get("core.xenon")),
				string.format("VOID    %+6.2f BETA", get("core.void")),
				string.format("PEAKING R %.2f  Z %.2f", get("core.fluxPeak"), get("core.kz")),
				string.format("TILT %3.0f%%  OFFSET %+3.0f%%", get("core.tilt"), get("core.offset")),
				string.format("FUEL MAX %5.0f C  CLAD %4.0f", get("core.maxFuel"), get("core.maxClad")),
				string.format("DRYOUT MARGIN  %5.2f", get("core.minMargin")),
				string.format("ENERGY %7.1f MWh  SCRAMS %d", get("stats.energy"), get("stats.scrams")),
			}, "\n")
			local n = #logLines
			local shown = {}
			for i = math.max(1, n - 8), n do
				table.insert(shown, logLines[i])
			end
			right.Text = table.concat(shown, "\n")
		end)
		region(part, w, nil, function()
			return "Unit computer: calculated core parameters on the left, the event log on the right.\nThe reactivity margin (ORM) must stay above 26 rods; below 15 the reactor must be shut down."
		end)
	end

	builders.sync = function(gui, face, part, w)
		local frame = box(gui, w.x, w.y, w.w, w.h, Color3.new(0, 0, 0))
		frame.BackgroundTransparency = 1
		outline(frame, Color3.fromRGB(70, 74, 70), 2)
		plate(gui, w.x + 0.7, w.y + 0.05, w.w - 1.4, 0.22, "SYNCHROSCOPE", 0.13)
		local d = 1.9
		local cx, cy = w.x + w.w / 2, w.y + 0.36 + d / 2
		local dial = box(gui, cx - d / 2, cy - d / 2, d, d, PAPER)
		round(dial)
		bezel(controls, face, cx - d / 2 - 0.06, cy - d / 2 - 0.06, d + 0.12, d + 0.12, 0.12, BEZEL, 0.07)
		outline(dial, Color3.fromRGB(30, 30, 30), 3)
		box(gui, cx - 0.02, cy - d / 2, 0.04, 0.2, INK)
		text(gui, cx - d / 2 + 0.1, cy - 0.12, 0.6, 0.24, "SLOW", 0.12, Color3.fromRGB(80, 80, 80))
		text(gui, cx + d / 2 - 0.7, cy - 0.12, 0.6, 0.24, "FAST", 0.12, Color3.fromRGB(80, 80, 80))
		-- A rotated frame turns about its centre, so the hand is the top half
		-- of an invisible pivot twice its length.
		local pivot = Instance.new("Frame")
		pivot.BackgroundTransparency = 1
		pivot.BorderSizePixel = 0
		pivot.AnchorPoint = Vector2.new(0.5, 0.5)
		pivot.Position = UDim2.fromOffset(px(cx), px(cy))
		pivot.Size = UDim2.fromOffset(px(0.05), px(d - 0.24))
		pivot.ZIndex = 3
		pivot.Parent = gui
		local hand = Instance.new("Frame")
		hand.BorderSizePixel = 0
		hand.BackgroundColor3 = Color3.fromRGB(200, 20, 20)
		hand.Size = UDim2.fromScale(1, 0.5)
		hand.ZIndex = 3
		hand.Parent = pivot
		local okBulb = box(gui, w.x + 0.2, w.y + w.h - 0.62, 0.24, 0.24, LAMP.green[2])
		round(okBulb)
		local okText = text(gui, w.x + 0.5, w.y + w.h - 0.66, 1.1, 0.3, "IN SYNC", 0.14)
		okText.TextXAlignment = Enum.TextXAlignment.Left
		local info = text(gui, w.x + 1.5, w.y + w.h - 0.7, w.w - 1.6, 0.6, "", 0.14, INK, Enum.Font.Code)
		table.insert(updaters, function()
			local on = get("sync.on") >= 0.5
			pivot.Visible = on
			pivot.Rotation = get("sync.angle")
			okBulb.BackgroundColor3 = LAMP.green[if get("sync.ok") >= 0.5 then 1 else 2]
			info.Text = if on then string.format("%+.2f Hz\n%+.1f %% V", get("sync.df"), get("sync.dv")) else "scope off"
		end)
		region(part, w, nil, function()
			return "Synchroscope. Select a generator, bring it to 1800 rpm with the field on, and close the\ngenerator breaker as the hand passes slowly through the top with the IN SYNC lamp lit."
		end)
	end

	for _, p in PanelLayout.panels do
		local guis: { [string]: SurfaceGui } = {}
		local faceGeom: { [string]: PanelLayout.Face } = {}
		local faceParts: { [string]: Instance } = {}
		for _, faceName in { "bench", "vert", "ann" } do
			local part = room:WaitForChild(p.id .. "_" .. faceName) :: BasePart
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Artwork"
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = PPS / S
			gui.LightInfluence = if faceName == "ann" then 0 else 1
			gui.ResetOnSpawn = false
			gui.Adornee = part
			gui.Parent = part
			guis[faceName] = gui
			faceGeom[faceName] = PanelLayout.face(p.index, faceName)
			faceParts[faceName] = part
			faces[part] = faceGeom[faceName]
			regions[part] = {}
		end
		for _, w in p.widgets do
			local builder = builders[w.kind]
			if builder then
				builder(guis[w.face], faceGeom[w.face], faceParts[w.face], w)
			end
		end
	end

	-- Annunciator windows: 0 dark, 1 new (flashing), 2 acknowledged (steady).
	out.setAlarm = function(index: number, state: number)
		local t = annTiles[index]
		if t then
			t.state = state
		end
	end
	out.flash = function(fast: boolean, slow: boolean?)
		for _, t in annTiles do
			local lit = testing[t.panel] == true or t.state == 2 or (t.state == 1 and fast) or (t.state == 3 and slow == true)
			if lit ~= t.lit then
				t.lit = lit
				if lit then
					t.tile.BackgroundColor3 = if t.urgent then Color3.fromRGB(240, 40, 30) else Color3.fromRGB(255, 252, 226)
					t.label.TextColor3 = if t.urgent then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(10, 10, 10)
				else
					t.tile.BackgroundColor3 = ANN_DARK
					t.label.TextColor3 = ANN_DARK_TEXT
				end
			end
		end
	end
	out.setRods = function(buf: buffer)
		for _, fn in rodListeners do
			fn(buf)
		end
	end
	out.refresh = function()
		for _, fn in updaters do
			fn()
		end
	end
	return out
end

return Panels
