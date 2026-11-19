--!nonstrict
-- The control room, as data.
--
-- Six benchboard sections stand in an L around the operators, with the
-- reactor panel in the corner, in the style of a boiling-water-reactor
-- control room. Each section is a sloping bench of controls,
-- a vertical board of meters and recorders behind it, and a row of
-- annunciator windows on top. Each widget names the plant signal it shows
-- (`sig`) and the operator command it sends (`cmd`); the server and the
-- client both read this one description, so they cannot drift apart.
--
-- Positions are in studs on the face, measured from its top-left corner.
local AlarmList = require(script.Parent.AlarmList)

local PanelLayout = {}

-- Sizes and positions are in board units; SCALE turns them into studs (see
-- the geometry section at the end).
PanelLayout.SCALE = 0.55
PanelLayout.PANEL_WIDTH = 16
PanelLayout.BENCH_DEPTH = 5
PanelLayout.BENCH_FRONT_HEIGHT = 5
PanelLayout.BENCH_SLOPE = math.rad(22)
PanelLayout.VERT_HEIGHT = 6.6
PanelLayout.ANN_HEIGHT = 2.2
PanelLayout.BACK_WALL_Z = -36 -- bench front edge of the back wall of panels
PanelLayout.CORNER_X = -36 -- bench front edge of the left wing, square to the back wall
PanelLayout.CORNER_PANEL = 3 -- the reactor panel stands across the corner; the panels before it are on the wing
-- The operators' desk faces the corner, so the reactor panel is straight ahead.
PanelLayout.DESK_X = -15
PanelLayout.DESK_Z = -15
PanelLayout.DESK_YAW = math.rad(45)
PanelLayout.PIXELS_PER_STUD = 80 -- artwork pixels per board unit
PanelLayout.FACE_THICKNESS = 0.3

export type Widget = { [string]: any }
export type Panel = { id: string, title: string, index: number, widgets: { Widget } }

local panels: { Panel } = {}
local current: Panel

-- Panels are numbered 1 to 6 along the L; a title plate names each one and,
-- on the operators' own panels, the operator's post: SIUR (senior reactor
-- control engineer), SIUB (senior unit engineer), SIUT (senior turbine
-- engineer).
-- Most sections are PANEL_WIDTH wide; the reactor panel is wider.
local function panel(id: string, title: string, width: number?)
	local index = #panels + 1
	current = { id = id, title = title, index = index, number = "PANEL " .. index, width = width or PanelLayout.PANEL_WIDTH, widgets = {} }
	table.insert(panels, current)
end

local function add(w: Widget): Widget
	table.insert(current.widgets, w)
	return w
end

-- A group nameplate over the devices of one system (no outline box: boards
-- of the period had none).
local function section(face: string, x: number, y: number, w: number, h: number, title: string)
	add({ kind = "section", face = face, x = x, y = y, w = w, h = h, label = title })
end

local function group(face: string, x: number, y: number, w: number, title: string)
	section(face, x, y, w, 0.26, title)
end

-- A vertical profile meter: 0.6 wide, nameplate on top.
local function meter(face: string, x: number, y: number, label: string, sig: string, lo: number, hi: number, unit: string, opts: any?)
	local o = opts or {}
	add({ kind = "meter", face = face, x = x, y = y, w = o.w or 0.6, h = o.h or 2.5, label = label, sig = sig, lo = lo, hi = hi, unit = unit, fmt = o.fmt or "%.0f", red = o.red, amber = o.amber, low = o.low, tip = o.tip })
end

-- A horizontal edgewise meter, for a pump's flow or a valve's position.
local function hmeter(face: string, x: number, y: number, label: string, sig: string, lo: number, hi: number, unit: string, opts: any?)
	local o = opts or {}
	add({ kind = "hmeter", face = face, x = x, y = y, w = o.w or 1.35, h = 0.62, label = label, sig = sig, lo = lo, hi = hi, unit = unit, fmt = o.fmt or "%.0f", red = o.red, low = o.low, tip = o.tip })
end

-- A digital panel meter (red LED digits) with `cells` digits.
local function digital(face: string, x: number, y: number, label: string, sig: string, fmt: string, unit: string, w: number?, cells: number?)
	add({ kind = "digital", face = face, x = x, y = y, w = w or 1.2, h = 0.72, label = label, sig = sig, fmt = fmt, unit = unit, cells = cells })
end

-- A mechanical counter: white figures on black drums.
local function counter(face: string, x: number, y: number, label: string, sig: string, w: number, cells: number)
	add({ kind = "digital", face = face, x = x, y = y, w = w, h = 0.72, label = label, sig = sig, fmt = "%.0f", unit = "", cells = cells, counter = true })
end

-- An indicating light with its legend beside it. Lit when the signal is
-- above `gt` (default 0.5), or below `lt`, or equal to `eq`.
local function lamp(face: string, x: number, y: number, label: string, sig: string, color: string, opts: any?)
	local o = opts or {}
	add({ kind = "lamp", face = face, x = x, y = y, w = o.w or 1.4, h = o.h or 0.3, label = label, sig = sig, color = color, gt = o.gt, eq = o.eq, lt = o.lt })
end

-- An oiltight pushbutton with its nameplate below. `guard` puts it under
-- a hinged cover that has to be lifted before it can be pressed, as on the
-- protective functions; `big` makes it a mushroom head.
local function button(face: string, x: number, y: number, label: string, cmd: string, opts: any?)
	local o = opts or {}
	local h = o.h or (if o.guard then 1.0 else 0.9)
	add({ kind = "button", face = face, x = x, y = y, w = o.w or 0.75, h = h, label = label, cmd = cmd, value = o.value or 1, hold = o.hold, color = o.color or "black", lit = o.lit, litEq = o.litEq, big = o.big, guard = o.guard })
end

-- A control switch module: nameplate, red/green lamps (white for a mode
-- switch, none for a key switch) and an engraved escutcheon with a
-- pistol-grip handle or a key lock.
local function toggle(face: string, x: number, y: number, label: string, cmd: string, sig: string, opts: any?)
	local o = opts or {}
	local compact = o.compact
	add({ kind = "toggle", face = face, x = x, y = y, w = o.w or (if compact then 0.85 else 0.95), h = if compact then 1.2 else 1.3, label = label, cmd = cmd, sig = sig, positions = o.labels or { "OFF", "ON" }, key = o.key, compact = compact })
end

-- Rotary selector. The value sent and shown is the position number counted
-- from `base` (0 unless given).
local function selector(face: string, x: number, y: number, label: string, cmd: string, sig: string, positions: { string }, base: number?, width: number?)
	add({ kind = "selector", face = face, x = x, y = y, w = width or 1.1, h = 1.25, label = label, cmd = cmd, sig = sig, positions = positions, base = base or 0 })
end

-- A pump motor's breaker control switch, green lamp stopped, red running.
local function pump(face: string, x: number, y: number, label: string, cmd: string, sig: string)
	add({ kind = "pump", face = face, x = x, y = y, w = 0.95, h = 1.3, label = label, cmd = cmd, sig = sig })
end

-- A raise/lower control: spring-return switch under a position indicator
-- (lo to hi), or a digital readout when `digits` is set.
local function jog(face: string, x: number, y: number, label: string, cmd: string, sig: string, fmt: string, unit: string, opts: any?)
	local o = opts or {}
	add({ kind = "jog", face = face, x = x, y = y, w = o.w or 1.25, h = 1.35, label = label, cmd = cmd, sig = sig, fmt = fmt, unit = unit, lo = o.lo or 0, hi = o.hi or 100, digits = o.digits })
end

local function recorder(face: string, x: number, y: number, w: number, h: number, label: string, pens: { any })
	add({ kind = "recorder", face = face, x = x, y = y, w = w, h = h, label = label, pens = pens })
end

-- A coloured flow line painted on the board through the given points.
local function mimic(face: string, color: string, pts: { { number } })
	add({ kind = "mimic", face = face, x = 0, y = 0, w = 0, h = 0, color = color, pts = pts })
end

-- Standard recorder size: a case about a third of a metre square.
local REC_W, REC_H = 1.8, 2.45

local function pen(sig: string, lo: number, hi: number, color: string, name: string, unit: string?)
	return { sig = sig, lo = lo, hi = hi, color = color, name = name, unit = unit or "" }
end

local function annunciators()
	add({ kind = "ann", face = "ann", x = 0, y = 0, w = current.width, h = PanelLayout.ANN_HEIGHT, alarms = AlarmList.forPanel(current.id) })
	add({ kind = "label", face = "vert", x = 0.2, y = 0.06, w = current.width - 0.4, h = 0.42, label = current.number .. "  ·  " .. current.title, title = true })
end

-- The annunciator pushbuttons of the ISA ringback sequence: ACKNOWLEDGE
-- silences the horn and steadies the flashing windows, RESET puts out the
-- windows whose conditions have cleared (they flash slowly until then),
-- and TEST lights every window on the panel while held. Laid out left to
-- right from x with the given pitch, or top to bottom when `down`.
local function annunciatorButtons(x: number, y: number, pitch: number, down: boolean?, w: number?)
	local bw = w or 0.75
	local function at(i: number): (number, number)
		if down then
			return x, y + (i - 1) * pitch
		end
		return x + (i - 1) * pitch, y
	end
	local x1, y1 = at(1)
	button("bench", x1, y1, "ACK", "ann.ack", { color = "yellow", w = bw })
	local x2, y2 = at(2)
	button("bench", x2, y2, "RESET", "ann.reset", { color = "black", w = bw })
	local x3, y3 = at(3)
	add({ kind = "lamptest", face = "bench", x = x3, y = y3, w = bw, h = 0.9, label = "TEST" })
end

-- A manual/automatic control station of the period: a vertical scale with
-- the measured value and the setpoint, an output meter, and A / M / lower /
-- raise pushbuttons. The arrows move the output in manual, or the setpoint
-- where the controller has one the operator sets.
local function station(face: string, x: number, y: number, label: string, o: any)
	add({
		kind = "station", face = face, x = x, y = y, w = 1.4, h = 1.9, label = label,
		sig = o.pv, lo = o.lo, hi = o.hi, unit = o.unit or "", fmt = o.fmt or "%.0f",
		sp = o.sp, spValue = o.spValue, out = o.out, auto = o.auto, autoCmd = o.auto,
		cmd = o.adj, adjusts = o.adjusts or "OUTPUT", tip = o.tip,
	})
end

-- Rows on the vertical boards: group plates, then the instruments under
-- them. Meters stand at a pitch of 0.72 within a group.
local PLATE_A, ROW_A = 0.56, 0.92
local PLATE_B, ROW_B = 3.58, 3.94
local PITCH = 0.72

-- A group of meters from x, with its nameplate over them; each item is
-- { label, signal, lo, hi, unit, options }. Returns the right edge.
local function meterGroup(x: number, plateY: number, y: number, title: string, items: { any }, h: number?): number
	for i, m in items do
		local o = table.clone(m[6] or {})
		o.h = o.h or h
		meter("vert", x + (i - 1) * PITCH, y, m[1], m[2], m[3], m[4], m[5], o)
	end
	local right = x + #items * PITCH - (PITCH - 0.6)
	group("vert", x - 0.05, plateY, right - x + 0.1, title)
	return right
end

-- ------------------------------------------------------------------ P1
panel("P1", "REACTOR AUXILIARIES AND EMERGENCY COOLING")
annunciators()
meterGroup(0.35, PLATE_A, ROW_A, "REACTOR SPACE", {
	{ "SPACE\nPRESS", "rs.press", 0, 200, "kPa", { red = 5, tip = "Reactor space pressure. Any reading means a fuel channel is leaking into the graphite stack." } },
	{ "GAS\nACTIVITY", "rad.gas", 0, 100, "", { red = 20 } },
	{ "GRAPHITE\nTEMP", "core.graphT", 0, 1000, "C", { red = 750 } },
})
meterGroup(2.85, PLATE_A, ROW_A, "FUEL TEMPERATURE", {
	{ "HOTTEST\nFUEL", "core.maxFuel", 0, 3000, "C", { red = 1800 } },
	{ "HOTTEST\nCLAD", "core.maxClad", 0, 1200, "C" },
	{ "MEAN\nFUEL", "core.fuelT", 0, 2000, "C" },
})
meterGroup(5.35, PLATE_A, ROW_A, "ROD CHANNEL COOLING", {
	{ "FLOW", "cps.flow", 0, 100, "%", { low = 50 } },
	{ "TANK\nLEVEL", "cps.tank", 0, 100, "%", { low = 60 } },
	{ "WATER\nTEMP", "cps.temp", 0, 150, "C", { amber = 90 } },
	{ "PUMP 1\nAMPS", "cps.pump.1.current", 0, 100, "A" },
	{ "PUMP 2\nAMPS", "cps.pump.2.current", 0, 100, "A" },
})
meterGroup(9.3, PLATE_A, ROW_A, "EMERGENCY CORE COOLING", {
	{ "ACCUM\nLEVEL", "eccs.accum", 0, 100, "%" },
	{ "INJECT\nFLOW", "eccs.flow", 0, 2500, "t/h" },
	{ "PUMP 1\nAMPS", "eccs.pump.1.current", 0, 250, "A" },
	{ "PUMP 2\nAMPS", "eccs.pump.2.current", 0, 250, "A" },
	{ "PUMP 3\nAMPS", "eccs.pump.3.current", 0, 250, "A" },
})
group("vert", 13.15, PLATE_A, 2.55, "ECCS STATUS")
lamp("vert", 13.2, 1.0, "ECCS ACTUATED", "eccs.active", "red", { w = 2.45 })
lamp("vert", 13.2, 1.42, "AUTO ARMED", "eccs.auto", "white", { w = 2.45 })
lamp("vert", 13.2, 1.84, "PUMP 1 RUNNING", "eccs.pump.1.run", "red", { w = 2.45 })
lamp("vert", 13.2, 2.26, "PUMP 2 RUNNING", "eccs.pump.2.run", "red", { w = 2.45 })
lamp("vert", 13.2, 2.68, "PUMP 3 RUNNING", "eccs.pump.3.run", "red", { w = 2.45 })
lamp("vert", 13.2, 3.1, "INJECTING", "eccs.flow", "red", { w = 2.45, gt = 10 })
recorder("vert", 0.35, ROW_B, REC_W, REC_H, "REACTOR SPACE", { pen("rs.press", 0, 200, "red", "SPACE PRESS", "kPa"), pen("rad.gas", 0, 100, "blue", "GAS ACTIVITY") })
recorder("vert", 2.3, ROW_B, REC_W, REC_H, "DRUM SEPARATORS", { pen("pri.press", 0, 8, "red", "PRESSURE", "MPa"), pen("pri.temp", 0, 400, "blue", "TEMPERATURE", "C") })
recorder("vert", 4.25, ROW_B, REC_W, REC_H, "EMERGENCY COOLING", { pen("eccs.flow", 0, 2500, "red", "INJECTION", "t/h"), pen("cps.flow", 0, 100, "blue", "CPS FLOW", "%") })
group("vert", 6.45, PLATE_B, 3.95, "CHANNEL INTEGRITY")
counter("vert", 6.5, ROW_B, "RUPTURED", "core.ruptured", 1.3, 4)
counter("vert", 6.5, ROW_B + 0.86, "FUEL DAMAGED", "core.damaged", 1.3, 4)
counter("vert", 6.5, ROW_B + 1.72, "FLOW BLOCKED", "core.blocked", 1.3, 4)
lamp("vert", 8.0, ROW_B + 0.08, "SPACE PRESS HIGH", "rs.press", "red", { w = 2.35, gt = 5 })
lamp("vert", 8.0, ROW_B + 0.5, "GAS ACTIVITY HIGH", "rad.gas", "amber", { w = 2.35, gt = 20 })
lamp("vert", 8.0, ROW_B + 0.92, "CHANNEL FLOW LOW", "core.blocked", "amber", { w = 2.35 })
lamp("vert", 8.0, ROW_B + 1.34, "FUEL FAILURE", "core.damaged", "red", { w = 2.35 })
lamp("vert", 8.0, ROW_B + 1.76, "CHANNEL RUPTURE", "core.ruptured", "red", { w = 2.35 })
meterGroup(10.85, PLATE_B, ROW_B, "CIRCUIT AND POOL", {
	{ "CIRCUIT\nTEMP", "pri.temp", 0, 350, "C" },
	{ "HEATUP\nRATE", "pri.heatup", -20, 20, "C/min", { fmt = "%.1f", red = 10 } },
	{ "BUBBLER\nPOOL", "pool.temp", 0, 100, "C", { red = 45 } },
}, 2.4)
group("vert", 13.4, PLATE_B, 2.3, "SAFETY VALVES")
for g = 1, 3 do
	lamp("vert", 13.45, ROW_B + 0.08 + (g - 1) * 0.42, "GROUP " .. g .. " OPEN", "srv." .. g .. ".open", "red", { w = 2.2 })
end

group("bench", 0.3, 0.06, 2.95, "ROD CHANNEL COOLING")
pump("bench", 0.3, 0.4, "CPS\nPUMP 1", "cps.pump.1", "cps.pump.1.run")
pump("bench", 1.3, 0.4, "CPS\nPUMP 2", "cps.pump.2", "cps.pump.2.run")
toggle("bench", 2.3, 0.4, "TANK\nMAKEUP", "cps.makeup", "cps.makeup", { labels = { "SHUT", "OPEN" } })
group("bench", 3.7, 0.06, 6.05, "EMERGENCY CORE COOLING")
toggle("bench", 3.75, 0.4, "AUTO\nACTUATION", "eccs.auto", "eccs.auto", { labels = { "OFF", "ARMED" }, key = true })
button("bench", 4.85, 0.4, "MANUAL\nINITIATE", "eccs.manual", { color = "red", guard = true })
button("bench", 5.7, 0.4, "ECCS\nRESET", "eccs.reset", { color = "black" })
for i = 1, 3 do
	toggle("bench", 6.65 + (i - 1) * 1.05, 0.4, "ECCS\nPUMP " .. i, "eccs.pump." .. i, "eccs.pump." .. i .. ".sw", { labels = { "AUTO", "RUN" } })
end
group("bench", 10.1, 0.06, 2.0, "SHUTDOWN COOLING")
toggle("bench", 10.6, 0.4, "COOLDOWN\nSYSTEM", "pri.cooldown", "pri.cooldown")
group("bench", 12.45, 0.06, 3.2, "ANNUNCIATOR")
annunciatorButtons(12.55, 0.4, 1.05)
-- ECCS pumps discharge into the injection header.
mimic("bench", "eccs", { { 7.125, 1.72 }, { 7.125, 2.12 }, { 9.225, 2.12 }, { 9.225, 1.72 } })
mimic("bench", "eccs", { { 8.175, 1.72 }, { 8.175, 2.4 } })
lamp("bench", 7.4, 2.4, "INJECTION VALVES OPEN", "eccs.active", "red", { w = 2.35 })
group("bench", 0.3, 2.0, 4.1, "MAIN SAFETY VALVES")
for g = 1, 3 do
	local x = 0.3 + (g - 1) * 1.4
	toggle("bench", x, 2.34, "GROUP " .. g, "srv." .. g, "srv." .. g .. ".sw", { labels = { "AUTO", "OPEN" } })
	lamp("bench", x, 3.74, "OPEN", "srv." .. g .. ".open", "red", { w = 0.95 })
end
-- Relief steam from the safety valve groups goes down to the bubbler pool.
group("bench", 5.0, 4.45, 2.2, "TO BUBBLER POOL")
mimic("bench", "steam", { { 0.775, 4.08 }, { 0.775, 4.3 }, { 6.1, 4.3 }, { 6.1, 4.45 } })
mimic("bench", "steam", { { 2.175, 4.08 }, { 2.175, 4.3 } })
mimic("bench", "steam", { { 3.575, 4.08 }, { 3.575, 4.3 } })

-- ------------------------------------------------------------------ P2
panel("P2", "MAIN CIRCULATION CIRCUIT  ·  SIUB")
annunciators()
for l = 1, 2 do
	local k = "loop." .. l
	meterGroup(if l == 1 then 0.3 else 7.45, PLATE_A, ROW_A, "LOOP " .. (if l == 1 then "A (WEST" else "B (EAST") .. " HALF)", {
		{ "DRUM\nLEVEL", k .. ".level", -600, 600, "mm", { tip = "Narrow-range drum level, the one the level controller uses. Scram at -600 and +400 mm." } },
		{ "LEVEL\nWIDE", k .. ".levelWide", -1500, 1500, "mm" },
		{ "LOOP\nFLOW", k .. ".flow", 0, 20000, "t/h" },
		{ "INLET\nTEMP", k .. ".tin", 0, 300, "C" },
		{ "INLET\nSUBCOOL", k .. ".subcool", 0, 40, "C", { fmt = "%.1f", tip = "How far below boiling the water entering the core is. Feedwater flow is what provides it." } },
		{ "SUCTION\nMARGIN", k .. ".npsh", 0, 2, "MPa", { fmt = "%.2f", low = 0.13, tip = "Pump suction margin. Below the red mark the pumps cavitate: throttle them or restore feedwater." } },
	})
end
meterGroup(4.95, PLATE_A, ROW_A, "DRUM SEPARATORS", {
	{ "PRESS", "pri.press", 0, 10, "MPa", { fmt = "%.2f", red = 7.35 } },
	{ "TEMP", "pri.temp", 0, 350, "C" },
	{ "HEATUP\nRATE", "pri.heatup", -20, 20, "C/min", { fmt = "%.1f", red = 10 } },
})
meterGroup(12.1, PLATE_A, ROW_A, "CORE FLOW", {
	{ "CORE\nFLOW", "pri.flow", 0, 40000, "t/h" },
	{ "CORE\nSTEAM", "core.steam", 0, 5000, "t/h" },
	{ "HEAD\nLOOP A", "loop.1.dp", 0, 2.5, "MPa", { fmt = "%.2f" } },
	{ "HEAD\nLOOP B", "loop.2.dp", 0, 2.5, "MPa", { fmt = "%.2f" } },
})
recorder("vert", 0.3, ROW_B, REC_W, REC_H, "DRUM LEVEL", { pen("loop.1.level", -600, 600, "red", "DRUM A", "mm"), pen("loop.2.level", -600, 600, "blue", "DRUM B", "mm") })
recorder("vert", 2.25, ROW_B, REC_W, REC_H, "LOOP FLOW", { pen("loop.1.flow", 0, 20000, "red", "LOOP A", "t/h"), pen("loop.2.flow", 0, 20000, "blue", "LOOP B", "t/h") })
recorder("vert", 4.2, ROW_B, REC_W, REC_H, "CORE FLOW AND STEAM", { pen("pri.flow", 0, 40000, "red", "CORE FLOW", "t/h"), pen("steam.total", 0, 5000, "blue", "STEAM", "t/h") })
recorder("vert", 6.15, ROW_B, REC_W, REC_H, "CORE INLET TEMP", { pen("loop.1.tin", 0, 300, "red", "LOOP A", "C"), pen("loop.2.tin", 0, 300, "blue", "LOOP B", "C") })
do
	local items = {}
	for l = 1, 2 do
		for i = 1, 4 do
			table.insert(items, { string.format("MCP\n%d%d", l, i), string.format("mcp.%d%d.current", l, i), 0, 800, "A", { red = 700 } })
		end
	end
	meterGroup(8.45, PLATE_B, ROW_B, "MCP MOTOR CURRENT", items, 2.4)
end
for l = 1, 2 do
	local x0 = if l == 1 then 0.3 else 8.15
	group("bench", x0, 0.06, 7.1, "LOOP " .. (if l == 1 then "A" else "B") .. " MAIN CIRCULATION PUMPS")
	for i = 1, 4 do
		local key = string.format("mcp.%d%d", l, i)
		local x = x0 + (i - 1) * 1.45
		pump("bench", x + 0.2, 0.4, string.format("MCP-%d%d", l, i), key .. ".sw", key .. ".run")
		lamp("bench", x, 1.82, "CAVITATION", key .. ".cav", "amber", { w = 1.35 })
		hmeter("bench", x, 2.24, "FLOW", key .. ".flow", 0, 10000, "m3/h")
		jog("bench", x + 0.05, 3.45, "THROTTLE", key .. ".valve", key .. ".valve", "%.0f", "%")
	end
	-- Pressure header: the pumps' discharge joined and led off to the core.
	mimic("bench", "water", { { x0 + 0.675, 3.18 }, { x0 + 3 * 1.45 + 0.675, 3.18 }, { x0 + 6.45, 3.18 } })
	for i = 1, 4 do
		local cx = x0 + (i - 1) * 1.45 + 0.675
		mimic("bench", "water", { { cx, 2.86 }, { cx, 3.18 } })
	end
	jog("bench", x0 + 5.85, 0.4, "BLOWDOWN", "loop." .. l .. ".blowdown", "loop." .. l .. ".blowdown", "%.0f", "%")
	toggle("bench", x0 + 6.0, 1.9, "LETDOWN\nAUTO", "loop." .. l .. ".letdownAuto", "loop." .. l .. ".letdownAuto")
	group("bench", x0 + 5.85, 3.3, 1.25, "TO CORE")
end

-- ------------------------------------------------------------------ P3
-- The reactor operator's board, the widest section, set across the corner.
-- Its vertical board carries the rod position indicators (a synchro dial
-- for every rod, laid out as the core, as on the RBMK's rod position
-- board), the channel cartogram, the axial power bargraph and the neutron
-- monitoring. Its bench is the SIUR's desk: rod selection keys in core
-- geometry, a spring-return rod movement key and a four-rod display, the
-- rod groups, the power regulators, the emergency protection (AZ-5 under
-- its cover) and the bypass keys.
panel("P3", "REACTOR CONTROL  ·  SIUR", 24)
annunciators()
add({ kind = "rodpos", face = "vert", x = 0.3, y = 0.62, w = 6.2, h = 5.85, label = "ROD POSITION" })
add({ kind = "coremap", face = "vert", x = 6.7, y = 0.62, w = 5.85, h = 5.85, label = "CORE MAP" })
add({ kind = "axial", face = "vert", x = 12.7, y = 0.62, w = 1.3, h = 5.85, label = "AXIAL" })
meterGroup(14.35, PLATE_A, ROW_A, "NEUTRON MONITORING", {
	{ "SOURCE\nRANGE", "n.logcps", 0, 6, "log cps", { fmt = "%.1f", tip = "Source range count rate, log scale. Watch it double as rods come out on the approach to criticality." } },
	{ "INTERM\nRANGE", "n.log", -9, 1, "log P", { fmt = "%.1f", tip = "Intermediate range: log10 of reactor power as a fraction of nominal." } },
	{ "POWER\nRANGE", "n.power", 0, 125, "%", { fmt = "%.1f", red = 110, amber = 100 } },
	{ "STARTUP\nRATE", "n.sur", -1, 3, "dec/min", { fmt = "%.2f", red = 2.6, amber = 1.3, tip = "Startup rate in decades per minute. 1.3 is a 20 s period (rod block), 2.6 is a 10 s period (scram)." } },
	{ "AR\nERROR", "ar.error", -10, 10, "%", { fmt = "%.1f", tip = "Reactor power minus regulator setpoint. Null this before switching a regulator in." } },
	{ "AXIAL\nOFFSET", "core.offset", -50, 50, "%", { tip = "Axial power offset: positive is top-heavy." } },
})
group("vert", 19.0, PLATE_A, 4.7, "SKALA")
digital("vert", 19.05, 0.95, "THERMAL POWER", "n.thermal", "%.0f", "MW", 2.2, 4)
digital("vert", 21.45, 0.95, "PERIOD", "n.period", "%.0f", "s", 2.2, 4)
digital("vert", 19.05, 1.85, "ORM", "core.orm", "%.0f", "rods", 2.2, 3)
digital("vert", 21.45, 1.85, "VOID COEF", "core.void", "%+.2f", "beta", 2.2, 4)
digital("vert", 19.05, 2.75, "XENON", "core.xenon", "%+.2f", "% dk", 2.2, 4)
digital("vert", 21.45, 2.75, "REACTIVITY", "n.rho", "%+.2f", "beta", 2.2, 5)
add({ kind = "computer", face = "vert", x = 14.35, y = 3.75, w = 6.6, h = 2.7, label = "SKALA" })
recorder("vert", 21.45, ROW_B, REC_W, REC_H, "NEUTRON POWER", { pen("n.log", -9, 1, "red", "LOG POWER", "log P"), pen("n.power", 0, 125, "blue", "LINEAR", "%") })

add({ kind = "rodmatrix", face = "bench", x = 0.25, y = 0.25, w = 4.5, h = 4.5, label = "ROD SELECT" })
group("bench", 5.0, 0.06, 5.35, "ROD MOTION")
add({ kind = "rodswitch", face = "bench", x = 5.05, y = 0.4, w = 1.6, h = 1.45, label = "ROD MOVEMENT", cmd = "rod.move", positions = { "INSERT", "OFF", "WITHDRAW" } })
button("bench", 6.8, 0.4, "CLEAR\nSELECT", "rod.clear", { color = "black" })
toggle("bench", 7.7, 0.4, "SELECT", "rod.quad", "rod.quad", { labels = { "ONE", "FOUR" } })
lamp("bench", 8.8, 0.48, "ROD BLOCK", "rod.block", "amber", { w = 1.5 })
lamp("bench", 8.8, 0.9, "AZ RODS OUT", "rod.azOut", "green", { w = 1.5 })
digital("bench", 8.8, 1.3, "SELECTED", "rod.selCount", "%.0f", "", 1.5, 3)
group("bench", 5.0, 2.18, 5.35, "FOUR ROD DISPLAY")
add({ kind = "fourrod", face = "bench", x = 5.05, y = 2.52, w = 5.25, h = 1.85, label = "FOUR ROD DISPLAY" })
group("bench", 10.6, 0.06, 5.8, "ROD GROUPS")
button("bench", 10.65, 0.4, "SELECT\nAZ RODS", "rod.group", { value = 1, color = "red" })
button("bench", 11.5, 0.4, "SELECT\nUSP", "rod.group", { value = 2, color = "blue" })
button("bench", 12.35, 0.4, "SELECT\nAR", "rod.group", { value = 3, color = "green" })
button("bench", 13.2, 0.4, "SELECT\nLAR", "rod.group", { value = 4, color = "yellow" })
toggle("bench", 14.1, 0.4, "BLOCK", "rod.blockBypass", "rod.blockBypass", { labels = { "NORM", "BYP" }, key = true, compact = true })
toggle("bench", 15.05, 0.4, "AZ INTLK", "rod.azInterlockBypass", "rod.azInterlockBypass", { labels = { "NORM", "BYP" }, key = true, compact = true })
digital("bench", 10.65, 1.72, "RR MEAN", "rod.meanRR", "%.2f", "m", 1.38, 3)
digital("bench", 12.1, 1.72, "AZ MEAN", "rod.meanAZ", "%.2f", "m", 1.38, 3)
digital("bench", 13.55, 1.72, "USP MEAN", "rod.meanUSP", "%.2f", "m", 1.38, 3)
digital("bench", 15.0, 1.72, "LAR MEAN", "rod.meanLAR", "%.2f", "m", 1.38, 3)
group("bench", 10.6, 2.62, 5.8, "POWER REGULATORS")
selector("bench", 10.65, 2.96, "REGULATOR", "ar.mode", "ar.mode", { "OFF", "AR-1", "AR-2", "AR-3" })
jog("bench", 11.9, 2.96, "SETPOINT", "ar.sp", "ar.setpoint", "%.2f", "%", { digits = true, w = 1.3 })
toggle("bench", 13.35, 2.96, "LOCAL REG", "lar.sw", "lar.on", { labels = { "OFF", "ON" } })
selector("bench", 14.45, 2.96, "MAP SHOWS", "map.mode", "map.mode", { "FLUX", "POWER", "MARGIN", "FLOW", "QUAL", "FUEL T", "XENON", "GRAPH" }, 1)
group("bench", 16.75, 0.06, 5.35, "EMERGENCY PROTECTION")
button("bench", 16.8, 0.4, "AZ-5", "az5.button", { color = "red", big = true, guard = true, w = 1.3, h = 1.45 })
button("bench", 18.25, 0.48, "AZ\nRESET", "az.reset", { color = "black" })
toggle("bench", 19.15, 0.4, "KOM\nCLUTCHES", "kom", "kom", { labels = { "NORM", "DROP" }, key = true })
for n = 1, 5 do
	lamp("bench", 20.3, 0.4 + (5 - n) * 0.34, "AZ-" .. n, "az" .. n .. ".active", "red", { w = 1.75 })
end
group("bench", 16.75, 2.62, 5.35, "PROTECTION BYPASS KEYS")
do
	local keys = { { "period", "PERIOD" }, { "press", "PRESS" }, { "level", "LEVEL" }, { "feed", "FEED" }, { "mcp", "MCP" }, { "turbines", "2 TG" }, { "cps", "CPS" } }
	for i, k in keys do
		add({ kind = "toggle", face = "bench", x = 16.8 + (i - 1) * 0.76, y = 2.96, w = 0.72, h = 1.2, label = k[2], cmd = "prot.bypass." .. k[1], sig = "prot.bypass." .. k[1], positions = { "", "BYP" }, key = true, compact = true })
	end
end
group("bench", 22.3, 0.06, 1.55, "ANNUNCIATOR")
annunciatorButtons(22.7, 0.4, 1.05, true)

-- ------------------------------------------------------------------ P4
panel("P4", "FEEDWATER AND CONDENSATE  ·  SIUB")
annunciators()
meterGroup(0.3, PLATE_A, ROW_A, "FEEDWATER", {
	{ "FEED\nFLOW A", "loop.1.feed", 0, 2500, "t/h" },
	{ "STEAM\nFLOW A", "loop.1.steam", 0, 2500, "t/h" },
	{ "FEED\nFLOW B", "loop.2.feed", 0, 2500, "t/h" },
	{ "STEAM\nFLOW B", "loop.2.steam", 0, 2500, "t/h" },
	{ "HEADER\nPRESS", "fw.header", 0, 12, "MPa", { fmt = "%.1f" } },
	{ "FEED\nTEMP", "fw.temp", 0, 250, "C" },
})
do
	local items = {}
	for i = 1, 4 do
		table.insert(items, { "FWP-" .. i .. "\nFLOW", "fw.pump." .. i .. ".flow", 0, 2000, "t/h" })
	end
	meterGroup(4.95, PLATE_A, ROW_A, "FEED PUMPS", items)
end
meterGroup(8.15, PLATE_A, ROW_A, "DEAERATOR AND CONDENSATE", {
	{ "DEAER\nLEVEL", "da.level", 0, 100, "%", { low = 25 } },
	{ "DEAER\nTEMP", "da.temp", 0, 200, "C" },
	{ "COND\nFLOW", "cond.flow", 0, 5000, "t/h" },
	{ "HOTWELL\n1", "tg.1.hotwell", 0, 100, "%" },
	{ "HOTWELL\n2", "tg.2.hotwell", 0, 100, "%" },
})
do
	local items = {}
	for i = 1, 3 do
		table.insert(items, { "AFWP-" .. i .. "\nAMPS", "afw.pump." .. i .. ".current", 0, 150, "A" })
	end
	meterGroup(12.1, PLATE_A, ROW_A, "EMERGENCY FEED", items)
end
recorder("vert", 0.3, ROW_B, REC_W, REC_H, "FEEDWATER FLOW", { pen("loop.1.feed", 0, 2500, "red", "DRUMS A", "t/h"), pen("loop.2.feed", 0, 2500, "blue", "DRUMS B", "t/h") })
recorder("vert", 2.25, ROW_B, REC_W, REC_H, "STEAM FLOW", { pen("loop.1.steam", 0, 2500, "red", "DRUMS A", "t/h"), pen("loop.2.steam", 0, 2500, "blue", "DRUMS B", "t/h") })
recorder("vert", 4.2, ROW_B, REC_W, REC_H, "DRUM LEVEL", { pen("loop.1.level", -600, 600, "red", "DRUM A", "mm"), pen("loop.2.level", -600, 600, "blue", "DRUM B", "mm") })
recorder("vert", 6.15, ROW_B, REC_W, REC_H, "DEAERATOR", { pen("da.level", 0, 100, "red", "LEVEL", "%"), pen("da.temp", 0, 200, "blue", "TEMPERATURE", "C") })
do
	local items = {}
	for i = 1, 4 do
		table.insert(items, { "FWP-" .. i .. "\nAMPS", "fw.pump." .. i .. ".current", 0, 700, "A", { red = 620 } })
	end
	meterGroup(8.45, PLATE_B, ROW_B, "FEED PUMP CURRENT", items, 2.4)
	local cps = {}
	for i = 1, 3 do
		table.insert(cps, { "CP-" .. i .. "\nAMPS", "cond.pump." .. i .. ".current", 0, 200, "A" })
	end
	meterGroup(11.65, PLATE_B, ROW_B, "COND PUMPS", cps, 2.4)
end
meterGroup(14.15, PLATE_B, ROW_B, "TOTALS", {
	{ "TOTAL\nFEED", "fw.total", 0, 5000, "t/h" },
	{ "TOTAL\nSTEAM", "steam.total", 0, 5000, "t/h" },
}, 2.4)
group("bench", 0.3, 0.06, 3.95, "MAIN FEEDWATER PUMPS")
for i = 1, 4 do
	pump("bench", 0.3 + (i - 1) * 1.0, 0.4, "FWP-" .. i, "fw.pump." .. i, "fw.pump." .. i .. ".run")
end
group("bench", 4.7, 0.06, 3.95, "EMERGENCY FEEDWATER")
for i = 1, 3 do
	pump("bench", 4.7 + (i - 1) * 1.0, 0.4, "AFWP-" .. i, "afw.pump." .. i, "afw.pump." .. i .. ".run")
end
toggle("bench", 7.7, 0.4, "AUTO\nSTART", "afw.auto", "afw.auto")
group("bench", 9.05, 0.06, 2.95, "CONDENSATE PUMPS")
for i = 1, 3 do
	pump("bench", 9.05 + (i - 1) * 1.0, 0.4, "CP-" .. i, "cond.pump." .. i, "cond.pump." .. i .. ".run")
end
group("bench", 12.4, 0.06, 1.0, "DEAER")
toggle("bench", 12.45, 0.4, "PEGGING\nSTEAM", "da.peg", "da.peg")
group("bench", 13.7, 0.06, 2.1, "ANNUNCIATOR")
annunciatorButtons(13.75, 0.4, 0.68, false, 0.62)
-- Feedwater train: condensate pumps to the deaerator, feed pumps to the
-- drum level control valves.
mimic("bench", "feed", { { 0.775, 1.86 }, { 11.525, 1.86 } })
for _, x in { 0.775, 1.775, 2.775, 3.775, 5.175, 6.175, 7.175, 9.525, 10.525, 11.525 } do
	mimic("bench", "feed", { { x, 1.72 }, { x, 1.86 } })
end
for _, x in { 1.0, 2.55, 4.45 } do
	mimic("bench", "feed", { { x, 1.86 }, { x, 2.0 } })
end
group("bench", 0.3, 2.0, 3.0, "DRUM LEVEL CONTROL")
for l = 1, 2 do
	station("bench", 0.3 + (l - 1) * 1.55, 2.34, "DRUM " .. (if l == 1 then "A" else "B") .. " LEVEL", {
		pv = "loop." .. l .. ".level", lo = -600, hi = 600, unit = "mm", spValue = 0,
		out = "lvl." .. l .. ".valve", auto = "lvl." .. l .. ".auto", adj = "lvl." .. l .. ".valve",
		tip = "Drum level controller: the feed regulating valve. A for automatic (three-element), M for manual; in manual the arrows move the valve.",
	})
end
group("bench", 3.75, 2.0, 1.5, "DEAER LEVEL")
station("bench", 3.8, 2.34, "DEAERATOR", {
	pv = "da.level", lo = 0, hi = 100, unit = "%", spValue = 50,
	out = "da.valve", auto = "da.levelAuto", adj = "da.valve",
	tip = "Deaerator level controller: the condensate valve. A for automatic, M for manual; in manual the arrows move the valve.",
})
group("bench", 5.7, 2.0, 4.6, "LEVELS AND VALVES")
hmeter("bench", 5.75, 2.34, "DRUM A LEVEL", "loop.1.level", -600, 600, "mm", { w = 1.45 })
hmeter("bench", 5.75, 3.06, "DRUM B LEVEL", "loop.2.level", -600, 600, "mm", { w = 1.45 })
hmeter("bench", 5.75, 3.78, "DEAER LEVEL", "da.level", 0, 100, "%", { w = 1.45, low = 25 })
hmeter("bench", 7.3, 2.34, "FEED VALVE A", "lvl.1.valve", 0, 100, "%", { w = 1.45 })
hmeter("bench", 7.3, 3.06, "FEED VALVE B", "lvl.2.valve", 0, 100, "%", { w = 1.45 })
hmeter("bench", 7.3, 3.78, "COND VALVE", "da.valve", 0, 100, "%", { w = 1.45 })
hmeter("bench", 8.85, 2.34, "HEADER PRESS", "fw.header", 0, 12, "MPa", { w = 1.45, fmt = "%.1f" })
hmeter("bench", 8.85, 3.06, "FEED TEMP", "fw.temp", 0, 250, "C", { w = 1.45 })
hmeter("bench", 8.85, 3.78, "DEAER TEMP", "da.temp", 0, 200, "C", { w = 1.45 })

-- ------------------------------------------------------------------ P5
panel("P5", "TURBINE-GENERATORS  ·  SIUT")
annunciators()
for k = 1, 2 do
	local key = "tg." .. k
	meterGroup(if k == 1 then 0.3 else 7.45, PLATE_A, ROW_A, "TURBINE " .. k, {
		{ "SPEED", key .. ".rpm", 0, 2200, "rpm", { red = 1980 } },
		{ "CONTROL\nVALVES", key .. ".cv", 0, 110, "%" },
		{ "BYPASS", key .. ".bypass", 0, 100, "%" },
		{ "COND\nPRESS", key .. ".vac", 0, 105, "kPa", { fmt = "%.1f", red = 30, amber = 15, tip = "Condenser absolute pressure. About 5 kPa is good vacuum; the turbine trips at 30." } },
		{ "VIBRA-\nTION", key .. ".vib", 0, 15, "mm/s", { fmt = "%.1f", red = 11.8, amber = 7.1 } },
		{ "METAL\nTEMP", key .. ".metal", 0, 300, "C" },
		{ "THERMAL\nSTRESS", key .. ".stress", 0, 150, "", { red = 60, tip = "Steam-to-metal temperature difference weighted by steam flow. Above the red mark the turbine is being damaged: slow down." } },
		{ "LUBE\nOIL", key .. ".lube", 0, 0.3, "MPa", { fmt = "%.2f", low = 0.12 } },
	})
end
meterGroup(6.45, PLATE_A, ROW_A, "GRID", {
	{ "GRID\nFREQ", "grid.hz", 58, 62, "Hz", { fmt = "%.2f", tip = "Grid frequency. Bring the generator to this before closing its breaker." } },
})
meterGroup(13.55, PLATE_A, ROW_A, "CONDENSERS", {
	{ "COND 1\nTEMP", "tg.1.condT", 0, 100, "C" },
	{ "COND 2\nTEMP", "tg.2.condT", 0, 100, "C" },
})
meterGroup(0.3, PLATE_B, ROW_B, "PRESSURE CONTROL", {
	{ "STEAM\nPRESS", "pri.press", 0, 10, "MPa", { fmt = "%.2f", red = 7.35 } },
	{ "PRESS\nSET", "ehc.pressSet", 0, 10, "MPa", { fmt = "%.2f" } },
	{ "STEAM\nDEMAND", "ehc.demand", 0, 120, "%" },
	{ "TOTAL\nSTEAM", "steam.total", 0, 5000, "t/h" },
}, 2.4)
recorder("vert", 3.55, ROW_B, REC_W, REC_H, "TURBINE SPEED", { pen("tg.1.rpm", 0, 2000, "red", "TG-1", "rpm"), pen("tg.2.rpm", 0, 2000, "blue", "TG-2", "rpm") })
recorder("vert", 5.5, ROW_B, REC_W, REC_H, "GENERATOR LOAD", { pen("gen.1.mw", 0, 450, "red", "GEN 1", "MW"), pen("gen.2.mw", 0, 450, "blue", "GEN 2", "MW") })
recorder("vert", 7.45, ROW_B, REC_W, REC_H, "CONDENSER PRESSURE", { pen("tg.1.vac", 0, 30, "red", "COND 1", "kPa"), pen("tg.2.vac", 0, 30, "blue", "COND 2", "kPa") })
recorder("vert", 9.4, ROW_B, REC_W, REC_H, "SHELL METAL TEMP", { pen("tg.1.metal", 0, 300, "red", "TG-1", "C"), pen("tg.2.metal", 0, 300, "blue", "TG-2", "C") })
meterGroup(11.7, PLATE_B, ROW_B, "TURBINE STEAM", {
	{ "TG-1\nSTEAM", "tg.1.steam", 0, 2500, "t/h" },
	{ "TG-2\nSTEAM", "tg.2.steam", 0, 2500, "t/h" },
	{ "TG-1\nISOL VLV", "tg.1.iso", 0, 100, "%" },
	{ "TG-2\nISOL VLV", "tg.2.iso", 0, 100, "%" },
}, 2.4)
for k = 1, 2 do
	local x0 = if k == 1 then 0.2 else 9.05
	local key = "tg." .. k
	group("bench", x0, 0.06, 6.6, "TURBINE " .. k)
	button("bench", x0, 0.4, "TRIP", key .. ".trip", { color = "red", guard = true })
	button("bench", x0 + 0.85, 0.4, "RESET\nLATCH", key .. ".reset", { color = "green" })
	lamp("bench", x0, 1.42, "TRIPPED", key .. ".trip", "red", { w = 1.6 })
	lamp("bench", x0, 1.8, "LATCHED", key .. ".stop", "green", { w = 1.6 })
	selector("bench", x0 + 1.75, 0.4, "SPEED SET", key .. ".speed", key .. ".speedTarget", { "STOP", "500", "1800" })
	jog("bench", x0 + 2.95, 0.4, "STEAM ISOL", key .. ".iso", key .. ".iso", "%.0f", "%", { w = 1.2 })
	jog("bench", x0 + 4.25, 0.4, "LOAD SET", key .. ".load", key .. ".load", "%.0f", "%", { w = 1.2 })
	toggle("bench", x0, 2.25, "BYPASS\nCONTROL", key .. ".bypassAuto", key .. ".bypassAuto", { labels = { "MAN", "AUTO" } })
	jog("bench", x0 + 1.05, 2.2, "BYPASS VALVE", key .. ".bypass", key .. ".bypass", "%.0f", "%", { w = 1.2 })
	toggle("bench", x0 + 2.35, 2.25, "VACUUM\nBREAKER", key .. ".vacBreaker", key .. ".vacBreaker", { labels = { "SHUT", "OPEN" } })
	hmeter("bench", x0 + 3.45, 2.25, "GENERATOR", "gen." .. k .. ".mw", 0, 450, "MW", { w = 1.6 })
	local row = {
		{ "LUBE OIL\nPUMP", ".lube", ".lubeAC" },
		{ "TURNING\nGEAR", ".tgear", ".tgear" },
		{ "GLAND\nSTEAM", ".gland", ".gland" },
		{ "CIRC\nPUMP A", ".cw1", ".cw1" },
		{ "CIRC\nPUMP B", ".cw2", ".cw2" },
		{ "VACUUM\nPUMP", ".vacPump", ".vacPump" },
		{ "STEAM\nEJECTOR", ".sjae", ".sjae" },
	}
	for i, r in row do
		toggle("bench", x0 + (i - 1) * 0.93, 3.68, r[1], key .. r[2], key .. r[3], { compact = true })
	end
end
group("bench", 6.95, 0.06, 1.95, "PRESSURE REG")
station("bench", 7.22, 0.4, "DRUM PRESSURE", {
	pv = "pri.press", lo = 0, hi = 10, unit = "MPa", fmt = "%.2f", sp = "ehc.pressSet",
	out = "ehc.demand", auto = "ehc.pressAuto", adj = "ehc.press", adjusts = "SETPOINT",
	tip = "Pressure regulator: holds drum pressure at the setpoint by moving the turbine steam demand. A puts it in, M takes it out; the arrows move the setpoint.",
})
digital("bench", 7.05, 2.45, "PRESS SET", "ehc.pressSet", "%.2f", "MPa", 1.75, 3)
digital("bench", 7.05, 3.3, "DEMAND", "ehc.demand", "%.0f", "%", 1.75, 3)

-- ------------------------------------------------------------------ P6
panel("P6", "ELECTRICAL")
annunciators()
for k = 1, 2 do
	local key = "gen." .. k
	meterGroup(if k == 1 then 0.3 else 7.2, PLATE_A, ROW_A, "GENERATOR " .. k, {
		{ "MW", key .. ".mw", 0, 450, "MW" },
		{ "MVAR", key .. ".mvar", -200, 200, "MVAr" },
		{ "VOLTS", key .. ".kv", 0, 26, "kV", { fmt = "%.1f" } },
		{ "FREQ", key .. ".hz", 55, 65, "Hz", { fmt = "%.2f" } },
	})
end
add({ kind = "sync", face = "vert", x = 3.6, y = 0.6, w = 3.2, h = 2.85, label = "SYNCHROSCOPE" })
meterGroup(10.4, PLATE_A, ROW_A, "UNIT OUTPUT", {
	{ "GROSS", "plant.gross", 0, 900, "MW" },
	{ "AUXIL-\nIARIES", "plant.aux", 0, 80, "MW", { fmt = "%.1f" } },
	{ "NET", "plant.net", 0, 900, "MW" },
})
group("vert", 12.9, PLATE_A, 2.8, "EMERGENCY POWER")
for i = 1, 3 do
	lamp("vert", 12.95, 1.0 + (i - 1) * 0.42, "BUS E" .. i .. " LIVE", "ebus." .. i .. ".live", "red", { w = 2.7 })
	lamp("vert", 12.95, 2.26 + (i - 1) * 0.42, "DG-" .. i .. " RUNNING", "dg." .. i .. ".run", "red", { w = 2.7 })
end
meterGroup(0.3, PLATE_B, ROW_B, "BUS LOAD", {
	{ "BUS\n1A", "bus.1A.mw", 0, 30, "MW", { fmt = "%.1f" } },
	{ "BUS\n1B", "bus.1B.mw", 0, 30, "MW", { fmt = "%.1f" } },
	{ "BUS\n2A", "bus.2A.mw", 0, 30, "MW", { fmt = "%.1f" } },
	{ "BUS\n2B", "bus.2B.mw", 0, 30, "MW", { fmt = "%.1f" } },
}, 2.4)
group("vert", 3.4, PLATE_B, 3.8, "AUXILIARY BUS SUPPLY")
for i, name in { "1A", "1B", "2A", "2B" } do
	lamp("vert", 3.45, ROW_B + 0.08 + (i - 1) * 0.42, "BUS " .. name .. " LIVE", "bus." .. name .. ".live", "red", { w = 1.8 })
	lamp("vert", 5.35, ROW_B + 0.08 + (i - 1) * 0.42, "ON RESERVE", "bus." .. name .. ".reserve", "amber", { w = 1.8 })
end
recorder("vert", 7.6, ROW_B, REC_W, REC_H, "UNIT OUTPUT", { pen("plant.gross", 0, 900, "red", "GROSS", "MW"), pen("plant.net", 0, 900, "blue", "NET", "MW") })
recorder("vert", 9.55, ROW_B, REC_W, REC_H, "FREQUENCY", { pen("grid.hz", 58, 62, "red", "GRID", "Hz"), pen("gen.1.hz", 58, 62, "blue", "GEN 1", "Hz") })
group("vert", 11.8, PLATE_B, 3.9, "DIESEL GENERATOR BREAKERS")
for i = 1, 3 do
	lamp("vert", 11.85, ROW_B + 0.08 + (i - 1) * 0.42, "DG-" .. i .. " BREAKER CLOSED", "dg." .. i .. ".bkr", "red", { w = 3.8 })
end
for k = 1, 2 do
	local x0 = if k == 1 then 0.3 else 4.85
	local key = "gen." .. k
	group("bench", x0, 0.06, 4.3, "GENERATOR " .. k)
	toggle("bench", x0, 0.4, "FIELD\nBREAKER", key .. ".field", key .. ".field")
	jog("bench", x0 + 1.03, 0.4, "VOLTAGE", key .. ".volt", key .. ".kv", "%.1f", "kV", { lo = 0, hi = 26, w = 1.2 })
	toggle("bench", x0 + 2.31, 0.4, "GEN\nBREAKER", key .. ".gcb", key .. ".gcb", { labels = { "TRIP", "CLOSE" } })
	toggle("bench", x0 + 3.33, 0.4, "YARD\nBREAKER", key .. ".yard", key .. ".yard", { labels = { "TRIP", "CLOSE" } })
	-- One-line: generator breaker to yard breaker and on to the grid.
	mimic("bench", "power", { { x0 + 2.785, 1.72 }, { x0 + 2.785, 2.02 }, { x0 + 4.3, 2.02 } })
	mimic("bench", "power", { { x0 + 3.805, 1.72 }, { x0 + 3.805, 2.02 } })
end
group("bench", 9.4, 0.06, 2.2, "SYNCHRONISING")
selector("bench", 9.4, 0.4, "SCOPE", "sync.select", "sync.select", { "OFF", "GEN 1", "GEN 2" }, 0, 1.15)
toggle("bench", 10.65, 0.4, "SYNC\nCHECK", "sync.bypass", "sync.bypass", { labels = { "NORM", "BYP" }, key = true })
group("bench", 12.05, 0.06, 3.5, "DIESEL GENERATORS")
for i = 1, 3 do
	selector("bench", 12.05 + (i - 1) * 1.18, 0.4, "DG-" .. i, "dg." .. i .. ".mode", "dg." .. i .. ".mode", { "OFF", "AUTO", "RUN" }, 0, 1.1)
end
group("bench", 0.3, 2.3, 12.1, "6.9 kV AUXILIARY BUSES")
for i, name in { "1A", "1B", "2A", "2B" } do
	local x = 0.3 + (i - 1) * 3.05
	toggle("bench", x, 2.64, name .. "\nNORMAL", "bus." .. name .. ".normal", "bus." .. name .. ".normal", { labels = { "TRIP", "CLOSE" } })
	toggle("bench", x + 1.0, 2.64, name .. "\nRESERVE", "bus." .. name .. ".reserve", "bus." .. name .. ".reserve", { labels = { "TRIP", "CLOSE" } })
	toggle("bench", x + 2.0, 2.64, "AUTO\nTRANSFER", "bus." .. name .. ".ats", "bus." .. name .. ".ats")
	-- One-line: each bus fed from its normal or its reserve breaker.
	mimic("bench", "power", { { x + 0.475, 3.96 }, { x + 0.475, 4.3 }, { x + 1.475, 4.3 }, { x + 1.475, 3.96 } })
	mimic("bench", "power", { { x + 0.975, 4.3 }, { x + 0.975, 4.6 } })
end
group("bench", 12.75, 2.3, 2.95, "EMERGENCY BUS TIES")
for i = 1, 3 do
	toggle("bench", 12.75 + (i - 1) * 1.0, 2.64, "E" .. i .. " TIE", "ebus." .. i .. ".tie", "ebus." .. i .. ".tie", { labels = { "OPEN", "CLOSE" } })
end

PanelLayout.panels = panels

-- ------------------------------------------------------------------ signals and commands
-- Every signal the control room displays, in a fixed order. The server
-- packs a snapshot in this order; the client unpacks it the same way.
local signalIndex: { [string]: number } = {}
local signalList: { string } = {}
local commandSet: { [string]: boolean } = {}
local holdSet: { [string]: boolean } = {}

local function needSignal(name: string?)
	if name and name ~= "" and not signalIndex[name] then
		table.insert(signalList, name)
		signalIndex[name] = #signalList
	end
end

for _, p in panels do
	for _, w in p.widgets do
		needSignal(w.sig)
		needSignal(w.lit)
		if w.kind == "station" then
			needSignal(w.sp)
			needSignal(w.out)
			needSignal(w.auto)
			commandSet[w.autoCmd] = true
		end
		if w.pens then
			for _, pen in w.pens do
				needSignal(pen.sig)
			end
		end
		if w.cmd then
			commandSet[w.cmd] = true
			if w.hold or w.kind == "jog" or w.kind == "station" or w.kind == "rodswitch" then
				holdSet[w.cmd] = true
			end
		end
	end
end
-- Signals used by the special displays and the client itself.
for _, name in {
	"horn", "time", "n.power", "n.thermal", "n.period", "n.rho", "n.log", "core.orm", "core.xenon", "core.void", "core.kr", "core.kz", "core.offset",
	"core.tilt", "core.maxFuel", "core.maxClad", "core.minMargin", "core.maxChannel", "core.fuelT", "core.graphT", "core.fluxPeak", "core.destroyed",
	"core.ruptured", "map.mode", "pri.press", "pri.temp", "plant.gross", "plant.net", "ar.setpoint", "ar.mode", "lar.on", "rod.selFirst", "rod.selCount",
	"sync.angle", "sync.df", "sync.dv", "sync.ok", "sync.on", "sync.select", "prot.firstOut", "stats.energy", "stats.scrams", "ar.pos1", "ar.pos2", "ar.pos3",
	"rod.meanLAR", "steam.total", "fw.total",
} do
	needSignal(name)
end
for z = 1, 14 do
	needSignal("core.ax" .. z)
end
for z = 1, 12 do
	needSignal("core.zone" .. z)
end
-- Commands with no panel widget of their own.
for _, name in { "rod.select", "map.mode", "ann.ack" } do
	commandSet[name] = true
end

PanelLayout.signals = signalList
PanelLayout.signalIndex = signalIndex
PanelLayout.commands = commandSet
PanelLayout.holdCommands = holdSet

-- ------------------------------------------------------------------ geometry
-- Everything above, and the room built around it, is drawn in board units.
-- SCALE turns board units into studs: at 0.55 the boards, desk and chairs
-- come out life-size beside a standard Roblox character (about 1.75 m tall
-- at 5.3 studs), with a bench front at hip height and the top of the
-- annunciators a little under three metres up.
export type Face = { center: Vector3, right: Vector3, up: Vector3, normal: Vector3, width: number, height: number, scale: number }

-- Where a panel stands, in board units: its origin is the floor point under
-- the middle of the bench's front edge; x is the operator's right, z points
-- back at them.
--
-- The boards form an L, as in a boiling-water-reactor control room: P1 and
-- P2 stand on a wing along the left wall, P4 to P6 along the back wall, and
-- the two runs are square to each other. The reactor panel, P3, stands in
-- the corner itself: a corner section set across it at 45 degrees, so the
-- operator at the controls faces straight into the corner, with the wing on
-- the left hand and the back wall on the right. The cabinets behind it are
-- filled out to the square corner.
function PanelLayout.designFrame(index: number): (Vector3, Vector3, Vector3)
	local z = PanelLayout.BACK_WALL_Z
	local cx = PanelLayout.CORNER_X
	local corner = PanelLayout.CORNER_PANEL
	local function width(i: number): number
		return panels[i].width
	end
	-- How far the corner section reaches along each run from the corner point.
	local reach = width(corner) / math.sqrt(2)
	if index < corner then
		-- On the wing, facing east.
		local fromCorner = reach + width(index) / 2
		for j = index + 1, corner - 1 do
			fromCorner += width(j)
		end
		return Vector3.new(cx, 0, z + fromCorner), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0)
	elseif index == corner then
		local d = 1 / math.sqrt(2)
		return Vector3.new(cx + reach / 2, 0, z + reach / 2), Vector3.new(d, 0, -d), Vector3.new(d, 0, d)
	end
	-- On the back wall, facing south.
	local along = reach + width(index) / 2
	for j = corner + 1, index - 1 do
		along += width(j)
	end
	return Vector3.new(cx + along, 0, z), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1)
end

-- The same, in studs.
function PanelLayout.panelFrame(index: number): (Vector3, Vector3, Vector3)
	local origin, right, back = PanelLayout.designFrame(index)
	return origin * PanelLayout.SCALE, right, back
end

-- A panel face in board units, as the room builder lays it out.
function PanelLayout.designFace(index: number, face: string): Face
	local origin, right, back = PanelLayout.designFrame(index)
	local up = Vector3.new(0, 1, 0)
	local s = PanelLayout.BENCH_SLOPE
	local depth = PanelLayout.BENCH_DEPTH
	local h0 = PanelLayout.BENCH_FRONT_HEIGHT
	local backY = h0 + depth * math.sin(s)
	local backZ = -depth * math.cos(s)
	local function at(y: number, z: number): Vector3
		return origin + up * y + back * z
	end
	if face == "bench" then
		return {
			center = at(h0 + depth / 2 * math.sin(s), -depth / 2 * math.cos(s)),
			right = right,
			up = up * math.sin(s) - back * math.cos(s),
			normal = up * math.cos(s) + back * math.sin(s),
			width = panels[index].width,
			height = depth,
			scale = 1,
		}
	elseif face == "vert" then
		return {
			center = at(backY + PanelLayout.VERT_HEIGHT / 2, backZ),
			right = right,
			up = up,
			normal = back,
			width = panels[index].width,
			height = PanelLayout.VERT_HEIGHT,
			scale = 1,
		}
	else
		return {
			center = at(backY + PanelLayout.VERT_HEIGHT + PanelLayout.ANN_HEIGHT / 2, backZ),
			right = right,
			up = up,
			normal = back,
			width = panels[index].width,
			height = PanelLayout.ANN_HEIGHT,
			scale = 1,
		}
	end
end

-- A panel face in the world. Its width and height stay in board units, the
-- units every widget is placed in; `scale` turns them into studs.
function PanelLayout.face(index: number, face: string): Face
	local f = PanelLayout.designFace(index, face)
	f.center *= PanelLayout.SCALE
	f.scale = PanelLayout.SCALE
	return f
end

-- World position of a point on a face, `lift` board units proud of the surface.
function PanelLayout.toWorld(f: Face, x: number, y: number, lift: number?): Vector3
	return f.center + (f.right * (x - f.width / 2) + f.up * (f.height / 2 - y) + f.normal * (PanelLayout.FACE_THICKNESS / 2 + (lift or 0))) * f.scale
end

-- Face coordinates of a world point (the inverse of toWorld).
function PanelLayout.toFace(f: Face, p: Vector3): (number, number)
	local d = (p - f.center) / f.scale
	return d:Dot(f.right) + f.width / 2, f.height / 2 - d:Dot(f.up)
end

-- CFrame for a part whose Front face is the display surface.
function PanelLayout.faceCFrame(f: Face): CFrame
	-- Part axes: +Z is the back of the part, so it points into the panel.
	local z = -f.normal
	local y = f.up
	local x = y:Cross(z)
	return CFrame.fromMatrix(f.center, x, y, z)
end

return PanelLayout
