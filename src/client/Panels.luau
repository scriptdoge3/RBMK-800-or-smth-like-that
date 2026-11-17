--!nonstrict
-- Dresses the benchboards: every instrument, lamp, switch and display in the
-- shared layout is drawn here, on each player's own machine. The flat
-- artwork goes on a SurfaceGui per panel face; buttons, switch handles and
-- knobs are small parts standing proud of the panel.
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
	local t = text(parent, x, y, w, h, str, size, if dark then TITLE_TEXT else PLATE_TEXT)
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

-- An indicator lamp lens: a low dome that glows when lit.
local function lens(folder: Instance, face: PanelLayout.Face, x: number, y: number, diameter: number, colors: { Color3 }): (boolean) -> ()
	cylinder(folder, face, x, y, diameter + 0.07, 0.03, Color3.fromRGB(46, 46, 48))
	local glass = cylinder(folder, face, x, y, diameter, 0.09, colors[2])
	return function(on: boolean)
		glass.Color = colors[if on then 1 else 2]
		glass.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

local BEZEL = Color3.fromRGB(34, 35, 38)
-- Annunciator windows are milky white plastic, lit from behind.
local ANN_DARK = Color3.fromRGB(204, 200, 186)
local ANN_DARK_TEXT = Color3.fromRGB(58, 56, 50)
local ANN_SPARE = Color3.fromRGB(196, 192, 178)

local function cleanLabel(s: string?): string
	return (string.gsub(s or "", "\n", " "))
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

	builders.section = function(gui, _face, _part, w)
		local f = box(gui, w.x, w.y, w.w, w.h, Color3.new(0, 0, 0))
		f.BackgroundTransparency = 1
		outline(f, Color3.fromRGB(60, 54, 44), 2)
		if w.label ~= "" then
			plate(gui, w.x + 0.06, w.y + 0.04, math.min(w.w - 0.12, #w.label * 0.098 + 0.3), 0.2, w.label, 0.135, true)
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

	builders.meter = function(gui, face, part, w)
		plate(gui, w.x - 0.06, w.y + 0.04, w.w + 0.12, 0.42, w.label, 0.125)
		local sx, sy, sw, sh = w.x + 0.1, w.y + 0.52, w.w - 0.2, 1.6
		local frameBack = box(gui, sx - 0.04, sy - 0.04, sw + 0.08, sh + 0.08, Color3.fromRGB(30, 30, 32))
		local scale = box(gui, sx, sy, sw, sh, PAPER)
		local span = w.hi - w.lo
		local function band(from: number, to: number, color: Color3)
			local a = math.clamp((from - w.lo) / span, 0, 1)
			local b = math.clamp((to - w.lo) / span, 0, 1)
			if b > a then
				box(gui, sx + sw * 0.72, sy + sh * (1 - b), sw * 0.28, sh * (b - a), color)
			end
		end
		if w.amber then
			band(w.amber, w.red or w.hi, Color3.fromRGB(240, 180, 40))
		end
		if w.red then
			band(w.red, w.hi, Color3.fromRGB(220, 50, 40))
		end
		if w.low then
			band(w.lo, w.low, Color3.fromRGB(220, 50, 40))
		end
		for i = 0, 4 do
			local ty = sy + sh * (1 - i / 4)
			local tick = box(gui, sx, ty - 0.01, sw * 0.3, 0.02, INK)
			tick.ZIndex = 2
			local v = w.lo + span * i / 4
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
			local n = text(gui, sx + sw * 0.28, ty - 0.09, sw * 0.5, 0.18, label, 0.11, Color3.fromRGB(60, 60, 60), Enum.Font.SourceSans)
			n.ZIndex = 2
			if i == 0 then
				n.Position = UDim2.fromOffset(px(sx + sw * 0.28), px(ty - 0.17))
			elseif i == 4 then
				n.Position = UDim2.fromOffset(px(sx + sw * 0.28), px(ty))
			end
		end
		-- The frame and the needle are real parts standing off the scale.
		bezel(controls, face, sx, sy, sw, sh, 0.1, BEZEL, 0.05)
		local needle = block(controls, face, sx + sw / 2, sy + sh, sw + 0.04, 0.045, 0.03, Color3.fromRGB(215, 25, 25))
		local readout = text(gui, w.x - 0.05, w.y + 2.16, w.w + 0.1, 0.3, "", 0.15, INK, Enum.Font.Code)
		local _ = frameBack, scale
		local last = math.huge
		table.insert(updaters, function()
			local v = get(w.sig)
			if v ~= last then
				last = v
				local f = math.clamp((v - w.lo) / span, 0, 1)
				needle.CFrame = blockCFrame(face, sx + sw / 2, sy + sh * (1 - f), 0.055, 0)
				readout.Text = string.format(w.fmt, v)
			end
		end)
		region(part, w, nil, valueTip(w))
	end

	builders.digital = function(gui, face, part, w)
		plate(gui, w.x, w.y + 0.01, w.w, 0.22, w.label, 0.125)
		bezel(controls, face, w.x, w.y + 0.28, w.w, w.h - 0.3, 0.07, BEZEL, 0.04)
		local screen = box(gui, w.x, w.y + 0.28, w.w, w.h - 0.3, SCREEN)
		outline(screen, Color3.fromRGB(70, 70, 70), 1)
		local suffix = if w.unit ~= "" then " " .. w.unit else ""
		-- Size the digits so the widest value this readout can show still fits.
		local widest = #(string.format(w.fmt, -8888.88) .. suffix)
		local digitSize = math.min(0.3, (w.w - 0.1) / (widest * 0.56))
		local value = text(gui, w.x, w.y + 0.28, w.w, w.h - 0.3, "", digitSize, DIGIT, Enum.Font.Code)
		value.TextWrapped = false
		local last = math.huge
		table.insert(updaters, function()
			local v = get(w.sig)
			if v ~= last then
				last = v
				value.Text = string.format(w.fmt, v) .. suffix
			end
		end)
		region(part, w, nil, valueTip(w))
	end

	builders.lamp = function(gui, face, part, w)
		local d = math.min(0.24, w.h - 0.06)
		local setLens = lens(controls, face, w.x + 0.03 + d / 2, w.y + w.h / 2, d, LAMP[w.color])
		plate(gui, w.x + d + 0.12, w.y + 0.05, w.w - d - 0.14, w.h - 0.1, w.label, 0.12)
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

	builders.button = function(gui, face, part, w)
		local d = if w.big then 0.95 else 0.5
		local cx, cy = w.x + w.w / 2, w.y + d / 2 + 0.06
		local ring = box(gui, cx - d / 2 - 0.05, cy - d / 2 - 0.05, d + 0.1, d + 0.1, Color3.fromRGB(60, 62, 64))
		round(ring)
		local cap = cylinder(controls, face, cx, cy, d, 0.16, BUTTON[w.color])
		local home = cap.CFrame
		plate(gui, w.x - 0.02, w.y + d + 0.16, w.w + 0.04, w.h - d - 0.18, w.label, if w.big then 0.2 else 0.12)
		-- A bright metal collar under the cap; the scram button also gets a yellow guard plate.
		if w.big then
			block(controls, face, cx, cy, d + 0.3, d + 0.3, 0.03, Color3.fromRGB(232, 196, 40))
		end
		cylinder(controls, face, cx, cy, d + 0.12, 0.06, Color3.fromRGB(186, 186, 190)).Material = Enum.Material.Metal
		region(part, w, function(_button: number)
			ctx.click()
			cap.CFrame = home - face.normal * 0.06 * S
			task.delay(0.15, function()
				cap.CFrame = home
			end)
			if w.hold then
				return { hold = w.cmd, value = w.value }
			end
			ctx.send(w.cmd, w.value)
			return nil
		end, function()
			return cleanLabel(w.label) .. (if w.hold then " (hold)" else "")
		end)
	end

	-- Shared by toggles and pump switches: a lever that leans left or right.
	local function lever(face: PanelLayout.Face, cx: number, cy: number, key: boolean?): (boolean) -> ()
		local baseColor = if key then Color3.fromRGB(190, 160, 70) else Color3.fromRGB(50, 52, 56)
		-- Black escutcheon plate, then the hub the handle turns on.
		block(controls, face, cx, cy, 0.58, 0.58, 0.025, Color3.fromRGB(26, 26, 28))
		cylinder(controls, face, cx, cy, 0.36, 0.07, baseColor).Material = Enum.Material.Metal
		local handle = block(controls, face, cx, cy, 0.13, 0.44, 0.2, if key then Color3.fromRGB(230, 200, 90) else Color3.fromRGB(20, 20, 22), -32)
		return function(on: boolean)
			handle.CFrame = blockCFrame(face, cx, cy, 0.1 + 0.05, if on then 32 else -32)
		end
	end

	builders.toggle = function(gui, face, part, w)
		local compact = w.compact
		local labelH = if compact then 0.26 else 0.42
		if w.label ~= "" then
			plate(gui, w.x + 0.01, w.y + 0.01, w.w - 0.02, labelH - 0.05, w.label, 0.115)
		end
		local cy = w.y + labelH + 0.28
		local set = lever(face, w.x + w.w / 2, cy, w.key)
		local py = cy + 0.28
		local left = text(gui, w.x, py, w.w / 2, 0.22, w.positions[1], 0.12, Color3.fromRGB(70, 70, 70))
		local right = text(gui, w.x + w.w / 2, py, w.w / 2, 0.22, w.positions[2], 0.12, Color3.fromRGB(70, 70, 70))
		local last: boolean? = nil
		table.insert(updaters, function()
			local on = get(w.sig) >= 0.5
			if on ~= last then
				last = on
				set(on)
				left.TextColor3 = if on then Color3.fromRGB(110, 110, 110) else INK
				right.TextColor3 = if on then INK else Color3.fromRGB(110, 110, 110)
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

	builders.pump = function(gui, face, part, w)
		plate(gui, w.x + 0.03, w.y + 0.01, w.w - 0.06, 0.24, w.label, 0.13)
		local setGreen = lens(controls, face, w.x + 0.26, w.y + 0.44, 0.22, LAMP.green)
		local setRed = lens(controls, face, w.x + w.w - 0.26, w.y + 0.44, 0.22, LAMP.red)
		local cy = w.y + 0.88
		local set = lever(face, w.x + w.w / 2, cy, false)
		text(gui, w.x, cy + 0.3, w.w / 2, 0.2, "STOP", 0.12, Color3.fromRGB(60, 60, 60))
		text(gui, w.x + w.w / 2, cy + 0.3, w.w / 2, 0.2, "START", 0.12, Color3.fromRGB(60, 60, 60))
		local last: boolean? = nil
		table.insert(updaters, function()
			local on = get(w.sig) >= 0.5
			if on ~= last then
				last = on
				set(on)
				setRed(on)
				setGreen(not on)
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

	builders.selector = function(gui, face, part, w)
		if w.label ~= "" then
			plate(gui, w.x + 0.03, w.y + 0.01, w.w - 0.06, 0.22, w.label, 0.12)
		end
		local cx, cy = w.x + w.w / 2, w.y + 0.58
		block(controls, face, cx, cy, 0.62, 0.62, 0.025, Color3.fromRGB(26, 26, 28))
		local n = #w.positions
		cylinder(controls, face, cx, cy, 0.5, 0.12, Color3.fromRGB(40, 42, 46))
		local pointer = block(controls, face, cx, cy, 0.09, 0.5, 0.18, Color3.fromRGB(230, 230, 225), 0)
		-- A legend window under the knob shows the selected position.
		local readout = plate(gui, w.x + 0.08, w.y + 0.94, w.w - 0.16, 0.27, "", 0.15, true)
		local function index(): number
			return math.clamp(math.floor(get(w.sig) - w.base + 1.5), 1, n)
		end
		local last = 0
		table.insert(updaters, function()
			local i = index()
			if i ~= last then
				last = i
				local angle = if n > 1 then -120 + (i - 1) / (n - 1) * 240 else 0
				pointer.CFrame = blockCFrame(face, cx, cy, 0.12 + 0.09, angle)
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

	builders.jog = function(gui, face, part, w)
		plate(gui, w.x + 0.08, w.y + 0.01, w.w - 0.16, 0.22, w.label, 0.12)
		local cy = w.y + 0.56
		for _, bx in { w.x + 0.32, w.x + w.w - 0.32 } do
			cylinder(controls, face, bx, cy, 0.52, 0.05, Color3.fromRGB(186, 186, 190)).Material = Enum.Material.Metal
		end
		local lower = cylinder(controls, face, w.x + 0.32, cy, 0.42, 0.14, BUTTON.black)
		local raise = cylinder(controls, face, w.x + w.w - 0.32, cy, 0.42, 0.14, BUTTON.black)
		text(gui, w.x + 0.55, cy - 0.2, w.w - 1.1, 0.4, "<  >", 0.2, Color3.fromRGB(60, 60, 60))
		text(gui, w.x + 0.02, cy + 0.2, 0.6, 0.16, "LOWER", 0.1, Color3.fromRGB(60, 60, 60))
		text(gui, w.x + w.w - 0.62, cy + 0.2, 0.6, 0.16, "RAISE", 0.1, Color3.fromRGB(60, 60, 60))
		local screen = box(gui, w.x + 0.1, w.y + 0.94, w.w - 0.2, 0.29, SCREEN)
		local readout = text(gui, w.x + 0.1, w.y + 0.94, w.w - 0.2, 0.29, "", 0.2, DIGIT, Enum.Font.Code)
		local _ = screen
		local suffix = if w.unit ~= "" then " " .. w.unit else ""
		local last = math.huge
		table.insert(updaters, function()
			local v = get(w.sig)
			if v ~= last then
				last = v
				readout.Text = string.format(w.fmt, v) .. suffix
			end
		end)
		local lowerHome, raiseHome = lower.CFrame, raise.CFrame
		region(part, w, function(_button: number, u: number)
			ctx.click()
			local up = u > w.x + w.w / 2
			local cap = if up then raise else lower
			local home = if up then raiseHome else lowerHome
			cap.CFrame = home - face.normal * 0.05 * S
			task.delay(0.2, function()
				cap.CFrame = home
			end)
			return { hold = w.cmd, value = if up then 1 else -1 }
		end, function()
			return string.format("%s: " .. w.fmt .. "%s\nhold the left button to lower, the right to raise", cleanLabel(w.label), get(w.sig), suffix)
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
		local cols, rows = 10, 3
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
				local label = text(gui, c * tw + 0.06, r * th + 0.05, tw - 0.12, th - 0.1, alarm.text, 0.15, ANN_DARK_TEXT)
				local index = AlarmList.index[alarm.id]
				local urgent = alarm.id == "az5" or alarm.id == "chan.rupture" or alarm.id == "core.damage" or alarm.id == "rs.press"
				annTiles[index] = { tile = tile, label = label, state = 0, urgent = urgent }
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
				return "Annunciators: click to acknowledge"
			end,
		})
	end

	-- Core map: one coloured cell per lattice position.
	builders.coremap = function(gui, face, part, w)
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
		local title = text(gui, w.x + 0.1, w.y + 0.03, w.w - 0.2, 0.25, "ROD SELECT   white RR  green AR  yellow LAR  red AZ  blue USP", 0.115, Color3.fromRGB(230, 230, 220))
		title.TextXAlignment = Enum.TextXAlignment.Left
		local size = math.max(6, math.floor(pitch * 1.9))
		local buttons = table.create(L.nRods)
		local centers = table.create(L.nRods)
		for i, rod in L.rods do
			local cx = ox + (rod.gx - 0.5) * pitch
			local cy = oy + (rod.gy - 0.5) * scaleY
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = ROD_COLOR[rod.kind]
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
		out.setRods = function(buf: buffer)
			local NC = L.nCells
			for i, rod in L.rods do
				local b = buttons[i]
				local flag = buffer.readu8(buf, 2 * NC + i)
				local depth = buffer.readu8(buf, rod.cell)
				if flag ~= b.flag or depth ~= b.depth then
					b.flag = flag
					b.depth = depth
					local selected = flag % 2 == 1
					local stuck = (flag // 2) % 2 == 1
					b.stroke.Enabled = selected
					local color = ROD_COLOR[rod.kind]:Lerp(Color3.new(0, 0, 0), depth / 255 * 0.55)
					if stuck then
						color = Color3.fromRGB(255, 0, 255)
					end
					b.frame.BackgroundColor3 = color
				end
			end
		end
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
				return "Rod select matrix: click a rod to select or deselect it.\nA white outline marks a selected rod; darker means deeper in the core."
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

	builders.axial = function(gui, face, part, w)
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
			gui.LightInfluence = 0
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
	out.flash = function(bright: boolean)
		for _, t in annTiles do
			local lit = t.state == 2 or (t.state == 1 and bright)
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
	out.refresh = function()
		for _, fn in updaters do
			fn()
		end
	end
	return out
end

return Panels
