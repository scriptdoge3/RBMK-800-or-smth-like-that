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
PanelLayout.PANEL_WIDTH = 11
PanelLayout.BENCH_DEPTH = 5
PanelLayout.BENCH_FRONT_HEIGHT = 5
PanelLayout.BENCH_SLOPE = math.rad(22)
PanelLayout.VERT_HEIGHT = 6.6
PanelLayout.ANN_HEIGHT = 2.2
PanelLayout.BACK_WALL_Z = -36 -- bench front edge of the back wall of panels
PanelLayout.CORNER_X = -36 -- bench front edge of the left wing, square to the back wall
PanelLayout.CORNER_PANEL = 3 -- the reactor panel stands across the corner; the panels before it are on the wing
-- The operators' desk faces the corner, so the reactor panel is straight ahead.
PanelLayout.DESK_X = -18
PanelLayout.DESK_Z = -18
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
	add({ kind = "hmeter", face = face, x = x, y = y, w = o.w or 1.35, h = o.h or (if face == "bench" then 0.72 else 0.62), label = label, sig = sig, lo = lo, hi = hi, unit = unit, fmt = o.fmt or "%.0f", red = o.red, low = o.low, tip = o.tip })
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
-- above `gt` (default 0.5), or below `lt`, or equal to `eq`. Bench lamps
-- are bigger than the ones on the vertical boards.
local function lamp(face: string, x: number, y: number, label: string, sig: string, color: string, opts: any?)
	local o = opts or {}
	add({ kind = "lamp", face = face, x = x, y = y, w = o.w or 1.4, h = o.h or (if face == "bench" then 0.42 else 0.3), label = label, sig = sig, color = color, gt = o.gt, eq = o.eq, lt = o.lt })
end

-- An oiltight pushbutton with its nameplate below. `guard` puts it under
-- a hinged cover that has to be lifted before it can be pressed, as on the
-- protective functions; `big` makes it a mushroom head.
local function button(face: string, x: number, y: number, label: string, cmd: string, opts: any?)
	local o = opts or {}
	local h = o.h or (if o.guard then 1.35 else 1.0)
	add({ kind = "button", face = face, x = x, y = y, w = o.w or 1.0, h = h, label = label, cmd = cmd, value = o.value or 1, hold = o.hold, color = o.color or "black", lit = o.lit, litEq = o.litEq, big = o.big, guard = o.guard })
end

-- A control switch module: nameplate, red/green lamps (white for a mode
-- switch, none for a key switch) and an engraved escutcheon with a
-- pistol-grip handle or a key lock.
local function toggle(face: string, x: number, y: number, label: string, cmd: string, sig: string, opts: any?)
	local o = opts or {}
	local compact = o.compact
	add({ kind = "toggle", face = face, x = x, y = y, w = o.w or (if compact then 1.1 else 1.35), h = if compact then 1.7 else 1.85, label = label, cmd = cmd, sig = sig, positions = o.labels or { "OFF", "ON" }, key = o.key, compact = compact })
end

-- Rotary selector. The value sent and shown is the position number counted
-- from `base` (0 unless given).
local function selector(face: string, x: number, y: number, label: string, cmd: string, sig: string, positions: { string }, base: number?, width: number?)
	add({ kind = "selector", face = face, x = x, y = y, w = width or 1.5, h = 1.75, label = label, cmd = cmd, sig = sig, positions = positions, base = base or 0 })
end

-- A pump motor's breaker control switch, green lamp stopped, red running.
local function pump(face: string, x: number, y: number, label: string, cmd: string, sig: string, w: number?)
	add({ kind = "pump", face = face, x = x, y = y, w = w or 1.35, h = 1.85, label = label, cmd = cmd, sig = sig })
end

-- A raise/lower control: spring-return switch under a position indicator
-- (lo to hi), or a digital readout when `digits` is set.
local function jog(face: string, x: number, y: number, label: string, cmd: string, sig: string, fmt: string, unit: string, opts: any?)
	local o = opts or {}
	add({ kind = "jog", face = face, x = x, y = y, w = o.w or 1.7, h = 1.95, label = label, cmd = cmd, sig = sig, fmt = fmt, unit = unit, lo = o.lo or 0, hi = o.hi or 100, digits = o.digits })
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
	local bw = w or 1.0
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
	add({ kind = "lamptest", face = "bench", x = x3, y = y3, w = bw, h = 1.0, label = "TEST" })
end

-- A manual/automatic control station of the period: a vertical scale with
-- the measured value and the setpoint, an output meter, and A / M / lower /
-- raise pushbuttons. The arrows move the output in manual, or the setpoint
-- where the controller has one the operator sets.
local function station(face: string, x: number, y: number, label: string, o: any)
	add({
		kind = "station", face = face, x = x, y = y, w = 1.7, h = 2.25, label = label,
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

-- Rows on the benches. Each group has a nameplate along the back edge;
-- under it the back row carries the indications and the controls used
-- now and then, and the front row, nearest the operator, the main
-- controls. The controls are few and big: one switch where a real board
-- has a row of them, with the rest of the plant left to its automatics.
-- (The recorders along the foot of the vertical board stand out over the
-- back edge of the bench, so the plates keep clear of it.)
local BENCH_PLATE, BACK_ROW, FRONT_ROW = 0.2, 0.54, 2.88
-- Below the front row: the pumps' discharge headers and the one-line.
local FOOT = FRONT_ROW + 2.0

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
meterGroup(0.3, PLATE_A, ROW_A, "REACTOR SPACE", {
	{ "SPACE\nPRESS", "rs.press", 0, 200, "kPa", { red = 5, tip = "Reactor space pressure. Any reading means a fuel channel is leaking into the graphite stack." } },
	{ "GAS\nACTIVITY", "rad.gas", 0, 100, "", { red = 20 } },
})
meterGroup(2.0, PLATE_A, ROW_A, "FUEL", {
	{ "HOTTEST\nFUEL", "core.maxFuel", 0, 3000, "C", { red = 1800 } },
	{ "GRAPHITE\nTEMP", "core.graphT", 0, 1000, "C", { red = 750 } },
})
meterGroup(3.7, PLATE_A, ROW_A, "ROD CHANNEL COOLING", {
	{ "FLOW", "cps.flow", 0, 100, "%", { low = 50 } },
	{ "TANK\nLEVEL", "cps.tank", 0, 100, "%", { low = 60 } },
	{ "WATER\nTEMP", "cps.temp", 0, 150, "C", { amber = 90 } },
})
meterGroup(6.1, PLATE_A, ROW_A, "ECCS", {
	{ "ACCUM\nLEVEL", "eccs.accum", 0, 100, "%" },
	{ "INJECT\nFLOW", "eccs.flow", 0, 2500, "t/h" },
})
group("vert", 7.8, PLATE_A, 3.0, "ECCS STATUS")
lamp("vert", 7.85, 1.0, "ECCS ACTUATED", "eccs.active", "red", { w = 2.9 })
lamp("vert", 7.85, 1.42, "AUTO ARMED", "eccs.auto", "white", { w = 2.9 })
lamp("vert", 7.85, 1.84, "PUMP 1 RUNNING", "eccs.pump.1.run", "red", { w = 2.9 })
lamp("vert", 7.85, 2.26, "PUMP 2 RUNNING", "eccs.pump.2.run", "red", { w = 2.9 })
lamp("vert", 7.85, 2.68, "PUMP 3 RUNNING", "eccs.pump.3.run", "red", { w = 2.9 })
lamp("vert", 7.85, 3.1, "INJECTING", "eccs.flow", "red", { w = 2.9, gt = 10 })
recorder("vert", 0.3, ROW_B, REC_W, REC_H, "REACTOR SPACE", { pen("rs.press", 0, 200, "red", "SPACE PRESS", "kPa"), pen("rad.gas", 0, 100, "blue", "GAS ACTIVITY") })
recorder("vert", 2.25, ROW_B, REC_W, REC_H, "EMERGENCY COOLING", { pen("eccs.flow", 0, 2500, "red", "INJECTION", "t/h"), pen("cps.flow", 0, 100, "blue", "CPS FLOW", "%") })
group("vert", 4.4, PLATE_B, 3.7, "CHANNEL INTEGRITY")
counter("vert", 4.45, ROW_B, "RUPTURED", "core.ruptured", 1.3, 4)
counter("vert", 4.45, ROW_B + 0.86, "FUEL DAMAGED", "core.damaged", 1.3, 4)
counter("vert", 4.45, ROW_B + 1.72, "FLOW BLOCKED", "core.blocked", 1.3, 4)
lamp("vert", 5.9, ROW_B + 0.08, "SPACE PRESS HIGH", "rs.press", "red", { w = 2.15, gt = 5 })
lamp("vert", 5.9, ROW_B + 0.5, "GAS ACTIVITY HIGH", "rad.gas", "amber", { w = 2.15, gt = 20 })
lamp("vert", 5.9, ROW_B + 0.92, "CHANNEL FLOW LOW", "core.blocked", "amber", { w = 2.15 })
lamp("vert", 5.9, ROW_B + 1.34, "FUEL FAILURE", "core.damaged", "red", { w = 2.15 })
lamp("vert", 5.9, ROW_B + 1.76, "CHANNEL RUPTURE", "core.ruptured", "red", { w = 2.15 })
group("vert", 8.4, PLATE_B, 2.4, "SAFETY VALVES")
for g = 1, 3 do
	lamp("vert", 8.45, ROW_B + 0.08 + (g - 1) * 0.42, "GROUP " .. g .. " OPEN", "srv." .. g .. ".open", "red", { w = 2.3 })
end
lamp("vert", 8.45, ROW_B + 1.34, "POOL TEMP HIGH", "pool.temp", "amber", { w = 2.3, gt = 45 })

-- Bench. Rod channel cooling on the left; emergency core cooling, which
-- arms and actuates itself, in the middle; the cooldown system and the
-- safety valves, which open by themselves on high pressure, on the right.
group("bench", 0.2, BENCH_PLATE, 2.95, "ROD CHANNEL COOLING")
hmeter("bench", 0.25, BACK_ROW, "CPS FLOW", "cps.flow", 0, 100, "%", { w = 2.85, low = 50 })
hmeter("bench", 0.25, BACK_ROW + 0.8, "HEADER TANK LEVEL", "cps.tank", 0, 100, "%", { w = 2.85, low = 60 })
lamp("bench", 0.25, BACK_ROW + 1.6, "TANK MAKEUP OPEN", "cps.makeup", "white", { w = 2.85 })
pump("bench", 0.25, FRONT_ROW, "CPS\nPUMP 1", "cps.pump.1", "cps.pump.1.run")
pump("bench", 1.75, FRONT_ROW, "CPS\nPUMP 2", "cps.pump.2", "cps.pump.2.run")
group("bench", 3.35, BENCH_PLATE, 3.85, "EMERGENCY CORE COOLING")
lamp("bench", 3.4, BACK_ROW, "ECCS ACTUATED", "eccs.active", "red", { w = 1.85 })
lamp("bench", 3.4, BACK_ROW + 0.48, "INJECTING", "eccs.flow", "red", { w = 1.85, gt = 10 })
lamp("bench", 3.4, BACK_ROW + 0.96, "AUTO ARMED", "eccs.auto", "white", { w = 1.85 })
lamp("bench", 3.4, BACK_ROW + 1.44, "ACCUMULATOR LOW", "eccs.accum", "amber", { w = 1.85, lt = 90 })
for i = 1, 3 do
	lamp("bench", 5.3, BACK_ROW + (i - 1) * 0.48, "PUMP " .. i .. " RUNNING", "eccs.pump." .. i .. ".run", "red", { w = 1.85 })
end
lamp("bench", 5.3, BACK_ROW + 1.44, "POOL TEMP HIGH", "pool.temp", "amber", { w = 1.85, gt = 45 })
toggle("bench", 3.4, FRONT_ROW, "AUTO\nACTUATION", "eccs.auto", "eccs.auto", { labels = { "OFF", "ARMED" }, key = true })
button("bench", 4.9, FRONT_ROW, "MANUAL\nINITIATE", "eccs.manual", { color = "red", guard = true, w = 1.1 })
button("bench", 6.15, FRONT_ROW, "ECCS\nRESET", "eccs.reset", { color = "black" })
group("bench", 7.45, BENCH_PLATE, 1.45, "COOLDOWN")
digital("bench", 7.5, BACK_ROW, "CIRCUIT TEMP", "pri.temp", "%.0f", "C", 1.35, 3)
digital("bench", 7.5, BACK_ROW + 0.9, "HEATUP RATE", "pri.heatup", "%.1f", "C/min", 1.35, 3)
toggle("bench", 7.5, FRONT_ROW, "COOLDOWN\nSYSTEM", "pri.cooldown", "pri.cooldown")
group("bench", 9.1, BENCH_PLATE, 1.75, "SAFETY VALVES")
for g = 1, 3 do
	lamp("bench", 9.15, BACK_ROW + (g - 1) * 0.48, "GROUP " .. g .. " OPEN", "srv." .. g .. ".open", "red", { w = 1.65 })
end
lamp("bench", 9.15, BACK_ROW + 1.44, "PRESS HIGH", "pri.press", "amber", { w = 1.65, gt = 7.2 })
toggle("bench", 9.3, FRONT_ROW, "SAFETY\nVALVES", "srv.manual", "srv.manual", { labels = { "AUTO", "OPEN" } })

-- ------------------------------------------------------------------ P2
panel("P2", "MAIN CIRCULATION CIRCUIT  ·  SIUB")
annunciators()
for l = 1, 2 do
	local k = "loop." .. l
	meterGroup(if l == 1 then 0.3 else 5.9, PLATE_A, ROW_A, "LOOP " .. (if l == 1 then "A (WEST" else "B (EAST") .. " HALF)", {
		{ "DRUM\nLEVEL", k .. ".level", -600, 600, "mm", { tip = "Narrow-range drum level, the one the level controller uses. Scram at -600 and +400 mm." } },
		{ "LOOP\nFLOW", k .. ".flow", 0, 20000, "t/h" },
		{ "INLET\nSUBCOOL", k .. ".subcool", 0, 40, "C", { fmt = "%.1f", tip = "How far below boiling the water entering the core is. Feedwater flow is what provides it." } },
		{ "SUCTION\nMARGIN", k .. ".npsh", 0, 2, "MPa", { fmt = "%.2f", low = 0.13, tip = "Pump suction margin. Below the red mark the pumps cavitate: throttle them or restore feedwater." } },
	})
end
meterGroup(3.45, PLATE_A, ROW_A, "DRUM SEPARATORS", {
	{ "PRESS", "pri.press", 0, 10, "MPa", { fmt = "%.2f", red = 7.35 } },
	{ "TEMP", "pri.temp", 0, 350, "C" },
	{ "HEATUP\nRATE", "pri.heatup", -20, 20, "C/min", { fmt = "%.1f", red = 10 } },
})
meterGroup(9.05, PLATE_A, ROW_A, "CORE FLOW", {
	{ "CORE\nFLOW", "pri.flow", 0, 40000, "t/h" },
	{ "CORE\nSTEAM", "core.steam", 0, 5000, "t/h" },
})
recorder("vert", 0.3, ROW_B, REC_W, REC_H, "DRUM LEVEL", { pen("loop.1.level", -600, 600, "red", "DRUM A", "mm"), pen("loop.2.level", -600, 600, "blue", "DRUM B", "mm") })
recorder("vert", 2.25, ROW_B, REC_W, REC_H, "LOOP FLOW", { pen("loop.1.flow", 0, 20000, "red", "LOOP A", "t/h"), pen("loop.2.flow", 0, 20000, "blue", "LOOP B", "t/h") })
do
	local items = {}
	for l = 1, 2 do
		for i = 1, 4 do
			table.insert(items, { string.format("MCP\n%d%d", l, i), string.format("mcp.%d%d.current", l, i), 0, 800, "A", { red = 700 } })
		end
	end
	meterGroup(4.45, PLATE_B, ROW_B, "MCP MOTOR CURRENT", items, 2.4)
end

-- Bench: each loop's four main circulation pumps in the front row; behind
-- them the loop's throttles (one control moves all four), its flow and
-- suction margin, and a cavitation lamp for each pump.
for l = 1, 2 do
	local x0 = if l == 1 then 0.2 else 5.8
	local k = "loop." .. l
	group("bench", x0 - 0.05, BENCH_PLATE, 5.1, "LOOP " .. (if l == 1 then "A" else "B") .. " MAIN CIRCULATION PUMPS")
	jog("bench", x0, BACK_ROW, "THROTTLES", k .. ".throttle", k .. ".throttle", "%.0f", "%")
	hmeter("bench", x0 + 1.77, BACK_ROW, "LOOP FLOW", k .. ".flow", 0, 20000, "t/h", { w = 1.6 })
	hmeter("bench", x0 + 1.77, BACK_ROW + 0.8, "SUCTION MARGIN", k .. ".npsh", 0, 2, "MPa", { w = 1.6, low = 0.13, fmt = "%.2f" })
	lamp("bench", x0 + 1.77, BACK_ROW + 1.6, "FLOW LOW", k .. ".flow", "amber", { w = 1.6, lt = 9000 })
	for i = 1, 4 do
		local key = string.format("mcp.%d%d", l, i)
		lamp("bench", x0 + 3.44, BACK_ROW + (i - 1) * 0.48, string.format("MCP-%d%d CAVIT", l, i), key .. ".cav", "amber", { w = 1.56 })
		pump("bench", x0 + (i - 1) * 1.27, FRONT_ROW, string.format("MCP-%d%d", l, i), key .. ".sw", key .. ".run", 1.2)
		-- Each pump's discharge into the loop's pressure header.
		local cx = x0 + (i - 1) * 1.27 + 0.6
		mimic("bench", "water", { { cx, FRONT_ROW + 1.85 }, { cx, FOOT } })
	end
	mimic("bench", "water", { { x0 + 0.6, FOOT }, { x0 + 3 * 1.27 + 0.6, FOOT } })
end

-- ------------------------------------------------------------------ P3
-- The reactor operator's board, the widest section, set across the corner.
-- Its vertical board carries the rod position indicators (a synchro dial
-- for every rod, laid out as the core, as on the RBMK's rod position
-- board), the channel cartogram (click it to change what it shows), the
-- axial power bargraph, the neutron monitoring and the SKALA figures. Its
-- bench is the SIUR's desk: rod selection keys in core geometry, the rod
-- movement switch and a four-rod display, the group selections, the power
-- regulators, and the emergency protection: AZ-5 under its cover, the KOM
-- key and the bypass keys.
panel("P3", "REACTOR CONTROL  ·  SIUR", 19)
annunciators()
add({ kind = "rodpos", face = "vert", x = 0.2, y = 0.62, w = 5.8, h = 5.8, label = "ROD POSITION" })
add({ kind = "coremap", face = "vert", x = 6.15, y = 0.62, w = 5.8, h = 5.8, label = "CORE MAP" })
add({ kind = "axial", face = "vert", x = 12.1, y = 0.62, w = 1.0, h = 5.8, label = "AXIAL" })
meterGroup(13.5, PLATE_A, ROW_A, "NEUTRON MONITORING", {
	{ "SOURCE\nRANGE", "n.logcps", 0, 6, "log cps", { fmt = "%.1f", tip = "Source range count rate, log scale. Watch it double as rods come out on the approach to criticality." } },
	{ "INTERM\nRANGE", "n.log", -9, 1, "log P", { fmt = "%.1f", tip = "Intermediate range: log10 of reactor power as a fraction of nominal." } },
	{ "POWER\nRANGE", "n.power", 0, 125, "%", { fmt = "%.1f", red = 110, amber = 100 } },
	{ "STARTUP\nRATE", "n.sur", -1, 3, "dec/min", { fmt = "%.2f", red = 2.6, amber = 1.3, tip = "Startup rate in decades per minute. 1.3 is a 20 s period (rod block), 2.6 is a 10 s period (scram)." } },
	{ "AR\nERROR", "ar.error", -10, 10, "%", { fmt = "%.1f", tip = "Reactor power minus regulator setpoint. Null this before switching a regulator in." } },
	{ "AXIAL\nOFFSET", "core.offset", -50, 50, "%", { tip = "Axial power offset: positive is top-heavy." } },
})
group("vert", 13.45, PLATE_B, 5.35, "SKALA")
digital("vert", 13.5, ROW_B, "THERMAL POWER", "n.thermal", "%.0f", "MW", 2.55, 4)
digital("vert", 16.2, ROW_B, "PERIOD", "n.period", "%.0f", "s", 2.55, 4)
digital("vert", 13.5, ROW_B + 0.86, "ORM", "core.orm", "%.0f", "rods", 2.55, 3)
digital("vert", 16.2, ROW_B + 0.86, "VOID COEF", "core.void", "%+.2f", "beta", 2.55, 4)
digital("vert", 13.5, ROW_B + 1.72, "XENON", "core.xenon", "%+.2f", "% dk", 2.55, 4)
digital("vert", 16.2, ROW_B + 1.72, "REACTIVITY", "n.rho", "%+.2f", "beta", 2.55, 5)

add({ kind = "rodmatrix", face = "bench", x = 0.2, y = 0.35, w = 4.2, h = 4.5, label = "ROD SELECT" })
group("bench", 4.55, BENCH_PLATE, 5.45, "ROD MOTION")
add({ kind = "fourrod", face = "bench", x = 4.6, y = BACK_ROW, w = 4.0, h = 1.85, label = "FOUR ROD DISPLAY" })
lamp("bench", 8.7, BACK_ROW, "ROD BLOCK", "rod.block", "amber", { w = 1.25 })
lamp("bench", 8.7, BACK_ROW + 0.48, "AZ RODS OUT", "rod.azOut", "green", { w = 1.25 })
digital("bench", 8.7, BACK_ROW + 0.98, "SELECTED", "rod.selCount", "%.0f", "", 1.25, 3)
add({ kind = "rodswitch", face = "bench", x = 4.6, y = FRONT_ROW, w = 2.0, h = 1.85, label = "ROD MOVEMENT", cmd = "rod.move", positions = { "INSERT", "OFF", "WITHDRAW" } })
button("bench", 6.7, FRONT_ROW, "CLEAR\nSELECT", "rod.clear", { color = "black" })
button("bench", 7.8, FRONT_ROW, "SELECT\nAZ RODS", "rod.group", { value = 1, color = "red" })
button("bench", 8.9, FRONT_ROW, "SELECT\nUSP", "rod.group", { value = 2, color = "blue" })
group("bench", 10.15, BENCH_PLATE, 3.45, "POWER REGULATORS")
toggle("bench", 10.2, BACK_ROW, "LOCAL\nREGULATORS", "lar.sw", "lar.on")
digital("bench", 11.7, BACK_ROW, "RR MEAN", "rod.meanRR", "%.2f", "m", 1.8, 3)
digital("bench", 11.7, BACK_ROW + 0.86, "AZ MEAN", "rod.meanAZ", "%.2f", "m", 1.8, 3)
selector("bench", 10.2, FRONT_ROW, "REGULATOR", "ar.mode", "ar.mode", { "OFF", "AR-1", "AR-2", "AR-3" })
jog("bench", 11.8, FRONT_ROW, "SETPOINT", "ar.sp", "ar.setpoint", "%.2f", "%", { digits = true })
group("bench", 13.8, BENCH_PLATE, 5.1, "EMERGENCY PROTECTION")
for n = 1, 5 do
	lamp("bench", 13.85, BACK_ROW + (5 - n) * 0.38, "AZ-" .. n, "az" .. n .. ".active", "red", { w = 1.5, h = 0.36 })
end
for i, k in { { "turbines", "2 TG" }, { "level", "LEVEL" }, { "mcp", "MCP" } } do
	add({ kind = "toggle", face = "bench", x = 15.45 + (i - 1) * 1.15, y = BACK_ROW, w = 1.1, h = 1.7, label = k[2] .. "\nBYPASS", cmd = "prot.bypass." .. k[1], sig = "prot.bypass." .. k[1], positions = { "", "BYP" }, key = true, compact = true })
end
button("bench", 13.85, FRONT_ROW, "AZ-5", "az5.button", { color = "red", big = true, guard = true, w = 1.5, h = 1.95 })
button("bench", 15.5, FRONT_ROW, "AZ\nRESET", "az.reset", { color = "black" })
toggle("bench", 16.65, FRONT_ROW, "KOM\nCLUTCHES", "kom", "kom", { labels = { "NORM", "DROP" }, key = true, compact = true })

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
meterGroup(4.9, PLATE_A, ROW_A, "DEAERATOR", {
	{ "DEAER\nLEVEL", "da.level", 0, 100, "%", { low = 25 } },
	{ "DEAER\nTEMP", "da.temp", 0, 200, "C" },
	{ "COND\nFLOW", "cond.flow", 0, 5000, "t/h" },
})
do
	local items = {}
	for i = 1, 3 do
		table.insert(items, { "AFWP-" .. i .. "\nAMPS", "afw.pump." .. i .. ".current", 0, 150, "A" })
	end
	meterGroup(7.35, PLATE_A, ROW_A, "EMERGENCY FEED", items)
end
recorder("vert", 0.3, ROW_B, REC_W, REC_H, "FEEDWATER FLOW", { pen("loop.1.feed", 0, 2500, "red", "DRUMS A", "t/h"), pen("loop.2.feed", 0, 2500, "blue", "DRUMS B", "t/h") })
recorder("vert", 2.25, ROW_B, REC_W, REC_H, "DRUM LEVEL", { pen("loop.1.level", -600, 600, "red", "DRUM A", "mm"), pen("loop.2.level", -600, 600, "blue", "DRUM B", "mm") })
do
	local items = {}
	for i = 1, 4 do
		table.insert(items, { "FWP-" .. i .. "\nAMPS", "fw.pump." .. i .. ".current", 0, 700, "A", { red = 620 } })
	end
	meterGroup(4.45, PLATE_B, ROW_B, "FEED PUMP CURRENT", items, 2.4)
	local cps = {}
	for i = 1, 2 do
		table.insert(cps, { "CP-" .. i .. "\nAMPS", "cond.pump." .. i .. ".current", 0, 200, "A" })
	end
	meterGroup(7.6, PLATE_B, ROW_B, "COND PUMPS", cps, 2.4)
end
meterGroup(9.3, PLATE_B, ROW_B, "TOTALS", {
	{ "TOTAL\nFEED", "fw.total", 0, 5000, "t/h" },
	{ "TOTAL\nSTEAM", "steam.total", 0, 5000, "t/h" },
}, 2.4)

-- Bench: the feed pumps under the drum level controllers and their feed
-- valves; the condensate pumps under the deaerator; the emergency feed
-- pumps, which start and stop by themselves, have lamps only. The
-- deaerator level controller and the pegging steam look after themselves.
group("bench", 0.15, BENCH_PLATE, 5.85, "FEEDWATER")
for l = 1, 2 do
	local d = if l == 1 then "A" else "B"
	station("bench", 0.2 + (l - 1) * 1.8, BACK_ROW, "DRUM " .. d .. " LEVEL", {
		pv = "loop." .. l .. ".level", lo = -600, hi = 600, unit = "mm", spValue = 0,
		out = "lvl." .. l .. ".valve", auto = "lvl." .. l .. ".auto", adj = "lvl." .. l .. ".valve",
		tip = "Drum level controller: the feed regulating valve. A for automatic (three-element), M for manual; in manual the arrows move the valve.",
	})
	hmeter("bench", 3.8, BACK_ROW + (l - 1) * 0.8, "FEED VALVE " .. d, "lvl." .. l .. ".valve", 0, 100, "%", { w = 2.15 })
end
for i = 1, 4 do
	pump("bench", 0.2 + (i - 1) * 1.45, FRONT_ROW, "FWP-" .. i, "fw.pump." .. i, "fw.pump." .. i .. ".run")
end
group("bench", 6.2, BENCH_PLATE, 2.95, "CONDENSATE")
hmeter("bench", 6.25, BACK_ROW, "DEAERATOR LEVEL", "da.level", 0, 100, "%", { w = 2.85, low = 25 })
hmeter("bench", 6.25, BACK_ROW + 0.8, "CONDENSATE FLOW", "cond.flow", 0, 5000, "t/h", { w = 2.85 })
lamp("bench", 6.25, BACK_ROW + 1.6, "DEAERATOR LEVEL LOW", "da.level", "amber", { w = 2.85, lt = 25 })
for i = 1, 2 do
	pump("bench", 6.3 + (i - 1) * 1.45, FRONT_ROW, "CP-" .. i, "cond.pump." .. i, "cond.pump." .. i .. ".run")
end
group("bench", 9.3, BENCH_PLATE, 1.6, "EMERGENCY FEED")
for i = 1, 3 do
	lamp("bench", 9.35, BACK_ROW + (i - 1) * 0.48, "AFWP-" .. i .. " RUN", "afw.pump." .. i .. ".run", "red", { w = 1.5 })
end
lamp("bench", 9.35, BACK_ROW + 1.44, "AUTO ARMED", "afw.auto", "white", { w = 1.5 })
group("bench", 9.3, FRONT_ROW - 0.34, 1.6, "FEED HEADER")
hmeter("bench", 9.35, FRONT_ROW + 0.1, "FEED TEMP", "fw.temp", 0, 250, "C", { w = 1.5 })
hmeter("bench", 9.35, FRONT_ROW + 0.9, "HEADER PRESS", "fw.header", 0, 12, "MPa", { w = 1.5, fmt = "%.1f" })
-- The feedwater train: condensate pumps and feed pumps on one header.
mimic("bench", "feed", { { 0.875, FOOT }, { 8.425, FOOT } })
for _, x in { 0.875, 2.325, 3.775, 5.225, 6.975, 8.425 } do
	mimic("bench", "feed", { { x, FRONT_ROW + 1.85 }, { x, FOOT } })
end

-- ------------------------------------------------------------------ P5
panel("P5", "TURBINE-GENERATORS  ·  SIUT")
annunciators()
for k = 1, 2 do
	local key = "tg." .. k
	meterGroup(if k == 1 then 0.3 else 5.95, PLATE_A, ROW_A, "TURBINE " .. k, {
		{ "SPEED", key .. ".rpm", 0, 2200, "rpm", { red = 1980 } },
		{ "CONTROL\nVALVES", key .. ".cv", 0, 110, "%" },
		{ "COND\nPRESS", key .. ".vac", 0, 105, "kPa", { fmt = "%.1f", red = 30, amber = 15, tip = "Condenser absolute pressure. About 5 kPa is good vacuum; the turbine trips at 30." } },
		{ "VIBRA-\nTION", key .. ".vib", 0, 15, "mm/s", { fmt = "%.1f", red = 11.8, amber = 7.1 } },
		{ "THERMAL\nSTRESS", key .. ".stress", 0, 150, "", { red = 60, tip = "Steam-to-metal temperature difference weighted by steam flow. Above the red mark the turbine is being damaged: slow down." } },
		{ "LUBE\nOIL", key .. ".lube", 0, 0.3, "MPa", { fmt = "%.2f", low = 0.12 } },
	})
end
meterGroup(4.95, PLATE_A, ROW_A, "GRID", {
	{ "GRID\nFREQ", "grid.hz", 58, 62, "Hz", { fmt = "%.2f", tip = "Grid frequency. Bring the generator to this before closing its breaker." } },
})
meterGroup(0.3, PLATE_B, ROW_B, "PRESSURE CONTROL", {
	{ "STEAM\nPRESS", "pri.press", 0, 10, "MPa", { fmt = "%.2f", red = 7.35 } },
	{ "PRESS\nSET", "ehc.pressSet", 0, 10, "MPa", { fmt = "%.2f" } },
	{ "STEAM\nDEMAND", "ehc.demand", 0, 120, "%" },
}, 2.4)
recorder("vert", 2.75, ROW_B, REC_W, REC_H, "TURBINE SPEED", { pen("tg.1.rpm", 0, 2000, "red", "TG-1", "rpm"), pen("tg.2.rpm", 0, 2000, "blue", "TG-2", "rpm") })
recorder("vert", 4.7, ROW_B, REC_W, REC_H, "GENERATOR LOAD", { pen("gen.1.mw", 0, 450, "red", "GEN 1", "MW"), pen("gen.2.mw", 0, 450, "blue", "GEN 2", "MW") })
recorder("vert", 6.65, ROW_B, REC_W, REC_H, "CONDENSER PRESSURE", { pen("tg.1.vac", 0, 30, "red", "COND 1", "kPa"), pen("tg.2.vac", 0, 30, "blue", "COND 2", "kPa") })
meterGroup(8.85, PLATE_B, ROW_B, "TURBINE STEAM", {
	{ "TG-1\nSTEAM", "tg.1.steam", 0, 2500, "t/h" },
	{ "TG-2\nSTEAM", "tg.2.steam", 0, 2500, "t/h" },
}, 2.4)

-- Bench: for each turbine, the back row holds its auxiliaries switch (circ
-- pumps, vacuum, ejectors and gland steam together; lube oil and turning
-- gear run by themselves), the latch and the steam admission; the front
-- row the trip, speed set and load set. The pressure regulator stands
-- between them. The bypass valves are automatic.
for k = 1, 2 do
	local x0 = if k == 1 then 0.15 else 6.45
	local key = "tg." .. k
	group("bench", x0 - 0.05, BENCH_PLATE, 4.5, "TURBINE " .. k)
	toggle("bench", x0, BACK_ROW, "TURBINE\nAUXILIARIES", key .. ".aux", key .. ".aux")
	button("bench", x0 + 1.45, BACK_ROW, "RESET\nLATCH", key .. ".reset", { color = "green" })
	lamp("bench", x0 + 1.45, BACK_ROW + 1.12, "LATCHED", key .. ".stop", "green", { w = 1.0 })
	jog("bench", x0 + 2.6, BACK_ROW, "STEAM ISOL", key .. ".iso", key .. ".iso", "%.0f", "%")
	button("bench", x0, FRONT_ROW, "TRIP", key .. ".trip", { color = "red", guard = true })
	lamp("bench", x0, FRONT_ROW + 1.45, "TRIPPED", key .. ".trip", "red", { w = 1.0 })
	selector("bench", x0 + 1.1, FRONT_ROW, "SPEED SET", key .. ".speed", key .. ".speedTarget", { "STOP", "500", "1800" })
	jog("bench", x0 + 2.7, FRONT_ROW, "LOAD SET", key .. ".load", key .. ".load", "%.0f", "%")
end
group("bench", 4.6, BENCH_PLATE, 1.8, "PRESSURE REG")
station("bench", 4.65, BACK_ROW, "DRUM PRESSURE", {
	pv = "pri.press", lo = 0, hi = 10, unit = "MPa", fmt = "%.2f", sp = "ehc.pressSet",
	out = "ehc.demand", auto = "ehc.pressAuto", adj = "ehc.press", adjusts = "SETPOINT",
	tip = "Pressure regulator: holds drum pressure at the setpoint by moving the turbine steam demand. A puts it in, M takes it out; the arrows move the setpoint.",
})
digital("bench", 4.65, FRONT_ROW + 0.1, "PRESS SET", "ehc.pressSet", "%.2f", "MPa", 1.7, 3)
digital("bench", 4.65, FRONT_ROW + 0.96, "STEAM DEMAND", "ehc.demand", "%.0f", "%", 1.7, 3)

-- ------------------------------------------------------------------ P6
panel("P6", "ELECTRICAL")
annunciators()
for k = 1, 2 do
	local key = "gen." .. k
	meterGroup(if k == 1 then 0.3 else 5.55, PLATE_A, ROW_A, "GENERATOR " .. k, {
		{ "MW", key .. ".mw", 0, 450, "MW" },
		{ "VOLTS", key .. ".kv", 0, 26, "kV", { fmt = "%.1f" } },
		{ "FREQ", key .. ".hz", 55, 65, "Hz", { fmt = "%.2f" } },
	})
end
add({ kind = "sync", face = "vert", x = 2.65, y = 0.6, w = 2.65, h = 2.85, label = "SYNCHROSCOPE" })
meterGroup(8.0, PLATE_A, ROW_A, "UNIT OUTPUT", {
	{ "GROSS", "plant.gross", 0, 900, "MW" },
	{ "AUXIL-\nIARIES", "plant.aux", 0, 80, "MW", { fmt = "%.1f" } },
	{ "NET", "plant.net", 0, 900, "MW" },
})
meterGroup(0.3, PLATE_B, ROW_B, "BUS LOAD", {
	{ "BUS\n1A", "bus.1A.mw", 0, 30, "MW", { fmt = "%.1f" } },
	{ "BUS\n1B", "bus.1B.mw", 0, 30, "MW", { fmt = "%.1f" } },
	{ "BUS\n2A", "bus.2A.mw", 0, 30, "MW", { fmt = "%.1f" } },
	{ "BUS\n2B", "bus.2B.mw", 0, 30, "MW", { fmt = "%.1f" } },
}, 2.4)
group("vert", 3.4, PLATE_B, 3.75, "AUXILIARY BUS SUPPLY")
for i, name in { "1A", "1B", "2A", "2B" } do
	lamp("vert", 3.45, ROW_B + 0.08 + (i - 1) * 0.42, "BUS " .. name .. " LIVE", "bus." .. name .. ".live", "red", { w = 1.8 })
	lamp("vert", 5.3, ROW_B + 0.08 + (i - 1) * 0.42, "ON RESERVE", "bus." .. name .. ".reserve", "amber", { w = 1.8 })
end
group("vert", 7.45, PLATE_B, 3.4, "EMERGENCY POWER")
for i = 1, 3 do
	lamp("vert", 7.5, ROW_B + 0.08 + (i - 1) * 0.42, "BUS E" .. i .. " LIVE", "ebus." .. i .. ".live", "red", { w = 1.6 })
	lamp("vert", 9.15, ROW_B + 0.08 + (i - 1) * 0.42, "DG-" .. i .. " RUN", "dg." .. i .. ".run", "red", { w = 1.6 })
	lamp("vert", 7.5, ROW_B + 1.34 + (i - 1) * 0.42, "DG-" .. i .. " BREAKER", "dg." .. i .. ".bkr", "red", { w = 1.6 })
end

-- Bench: each generator's field, generator and yard breakers in the front
-- row, the synchronising lamp beside them; behind them the synchroscope
-- selector, one selector for the three diesels, and one switch that moves
-- all four auxiliary buses between the reserve feed and their unit
-- transformers. The voltage regulators, the automatic transfer and the
-- emergency bus ties look after themselves.
for k = 1, 2 do
	local x0 = if k == 1 then 0.2 else 4.75
	local key = "gen." .. k
	group("bench", x0 - 0.05, FRONT_ROW - 0.34, 4.35, "GENERATOR " .. k)
	toggle("bench", x0, FRONT_ROW, "FIELD\nBREAKER", key .. ".field", key .. ".field")
	toggle("bench", x0 + 1.45, FRONT_ROW, "GENERATOR\nBREAKER", key .. ".gcb", key .. ".gcb", { labels = { "TRIP", "CLOSE" } })
	toggle("bench", x0 + 2.9, FRONT_ROW, "YARD\nBREAKER", key .. ".yard", key .. ".yard", { labels = { "TRIP", "CLOSE" } })
	-- One-line: generator breaker to yard breaker and on to the grid.
	mimic("bench", "power", { { x0 + 2.125, FRONT_ROW + 1.85 }, { x0 + 2.125, FOOT }, { x0 + 3.575, FOOT }, { x0 + 3.575, FRONT_ROW + 1.85 } })
	mimic("bench", "power", { { x0 + 3.575, FOOT }, { x0 + 4.3, FOOT } })
end
group("bench", 9.1, FRONT_ROW - 0.34, 1.8, "SYNC")
lamp("bench", 9.15, FRONT_ROW, "IN SYNC", "sync.ok", "white", { w = 1.7 })
digital("bench", 9.15, FRONT_ROW + 0.56, "GRID FREQ", "grid.hz", "%.2f", "Hz", 1.7, 4)
group("bench", 0.15, BENCH_PLATE, 1.6, "SYNCHRONIZING")
selector("bench", 0.2, BACK_ROW, "SCOPE", "sync.select", "sync.select", { "OFF", "GEN 1", "GEN 2" })
group("bench", 1.85, BENCH_PLATE, 3.35, "DIESEL GENERATORS")
selector("bench", 1.9, BACK_ROW, "DIESELS", "dg.mode", "dg.mode", { "OFF", "AUTO", "RUN" })
for i = 1, 3 do
	lamp("bench", 3.5, BACK_ROW + (i - 1) * 0.48, "DG-" .. i .. " RUNNING", "dg." .. i .. ".run", "red", { w = 1.65 })
end
group("bench", 5.35, BENCH_PLATE, 3.3, "AUXILIARY BUSES")
toggle("bench", 5.4, BACK_ROW, "BUS\nSUPPLY", "bus.supply", "bus.supply", { labels = { "RESERVE", "UNIT" } })
for i, name in { "1A", "1B", "2A", "2B" } do
	lamp("bench", 6.85, BACK_ROW + (i - 1) * 0.48, name .. " ON RESERVE", "bus." .. name .. ".reserve", "amber", { w = 1.75 })
end
group("bench", 8.8, BENCH_PLATE, 2.05, "OUTPUT")
hmeter("bench", 8.85, BACK_ROW, "GENERATOR 1", "gen.1.mw", 0, 450, "MW", { w = 1.95 })
hmeter("bench", 8.85, BACK_ROW + 0.8, "GENERATOR 2", "gen.2.mw", 0, 450, "MW", { w = 1.95 })

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
-- Commands with no panel widget of their own: the rod select matrix, the
-- cartogram (a click changes what it shows) and the light boxes (a click
-- acknowledges, a right click resets).
for _, name in { "rod.select", "map.mode", "ann.ack", "ann.reset" } do
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
