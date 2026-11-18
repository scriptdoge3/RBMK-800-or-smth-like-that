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

-- Panels carry GE-style numbers on their title plates: H11-P601 and on.
local function panel(id: string, title: string)
	local index = #panels + 1
	current = { id = id, title = title, index = index, number = "H11-P60" .. index, widgets = {} }
	table.insert(panels, current)
end

local function add(w: Widget): Widget
	table.insert(current.widgets, w)
	return w
end

local function section(face: string, x: number, y: number, w: number, h: number, title: string)
	add({ kind = "section", face = face, x = x, y = y, w = w, h = h, label = title })
end

local function meter(face: string, x: number, y: number, label: string, sig: string, lo: number, hi: number, unit: string, opts: any?)
	local o = opts or {}
	add({ kind = "meter", face = face, x = x, y = y, w = 0.8, h = o.h or 2.5, label = label, sig = sig, lo = lo, hi = hi, unit = unit, fmt = o.fmt or "%.0f", red = o.red, amber = o.amber, low = o.low, tip = o.tip })
end

-- A digital panel meter: a seven-segment display with `cells` digits.
local function digital(face: string, x: number, y: number, label: string, sig: string, fmt: string, unit: string, w: number?, cells: number?)
	add({ kind = "digital", face = face, x = x, y = y, w = w or 1.35, h = 0.8, label = label, sig = sig, fmt = fmt, unit = unit, cells = cells })
end

-- A lamp is lit when the signal is above `gt` (default 0.5) or, with `eq`,
-- when it equals that value.
local function lamp(face: string, x: number, y: number, label: string, sig: string, color: string, opts: any?)
	local o = opts or {}
	add({ kind = "lamp", face = face, x = x, y = y, w = o.w or 1.2, h = o.h or 0.36, label = label, sig = sig, color = color, gt = o.gt, eq = o.eq, lt = o.lt })
end

local function button(face: string, x: number, y: number, label: string, cmd: string, opts: any?)
	local o = opts or {}
	add({ kind = "button", face = face, x = x, y = y, w = o.w or 0.9, h = o.h or 1.0, label = label, cmd = cmd, value = o.value or 1, hold = o.hold, color = o.color or "black", lit = o.lit, litEq = o.litEq, big = o.big })
end

local function toggle(face: string, x: number, y: number, label: string, cmd: string, sig: string, opts: any?)
	local o = opts or {}
	local compact = o.compact
	add({ kind = "toggle", face = face, x = x, y = y, w = if compact then 0.9 else 1.0, h = if compact then 1.1 else 1.25, label = label, cmd = cmd, sig = sig, positions = o.labels or { "OFF", "ON" }, key = o.key, compact = compact })
end

-- Rotary selector. The value sent and shown is the position number counted
-- from `base` (0 unless given).
local function selector(face: string, x: number, y: number, label: string, cmd: string, sig: string, positions: { string }, base: number?, width: number?)
	add({ kind = "selector", face = face, x = x, y = y, w = width or 1.3, h = 1.25, label = label, cmd = cmd, sig = sig, positions = positions, base = base or 0 })
end

-- Motor control switch with red (running) and green (stopped) lamps.
local function pump(face: string, x: number, y: number, label: string, cmd: string, sig: string)
	add({ kind = "pump", face = face, x = x, y = y, w = 1.0, h = 1.55, label = label, cmd = cmd, sig = sig })
end

-- Lower / raise pushbuttons with a readout between them.
-- Lower / raise pushbuttons with a position indicator under them (lo to hi),
-- or a seven-segment readout when `digits` is set.
local function jog(face: string, x: number, y: number, label: string, cmd: string, sig: string, fmt: string, unit: string, opts: any?)
	local o = opts or {}
	add({ kind = "jog", face = face, x = x, y = y, w = 1.5, h = 1.25, label = label, cmd = cmd, sig = sig, fmt = fmt, unit = unit, lo = o.lo or 0, hi = o.hi or 100, digits = o.digits })
end

local function recorder(face: string, x: number, y: number, w: number, h: number, label: string, pens: { any })
	add({ kind = "recorder", face = face, x = x, y = y, w = w, h = h, label = label, pens = pens })
end

-- A coloured flow line painted on the board through the given points.
local function mimic(face: string, color: string, pts: { { number } })
	add({ kind = "mimic", face = face, x = 0, y = 0, w = 0, h = 0, color = color, pts = pts })
end

-- Standard recorder size: a case about 0.42 m square.
local REC_W, REC_H = 2.3, 2.45

local function pen(sig: string, lo: number, hi: number, color: string, name: string, unit: string?)
	return { sig = sig, lo = lo, hi = hi, color = color, name = name, unit = unit or "" }
end

local function annunciators()
	add({ kind = "ann", face = "ann", x = 0, y = 0, w = PanelLayout.PANEL_WIDTH, h = PanelLayout.ANN_HEIGHT, alarms = AlarmList.forPanel(current.id) })
	add({ kind = "label", face = "vert", x = 0.2, y = 0.08, w = 15.6, h = 0.42, label = current.number .. "   " .. current.title, title = true })
end

-- ------------------------------------------------------------------ P1
panel("P1", "REACTOR AUXILIARIES AND EMERGENCY COOLING")
annunciators()
section("vert", 0.3, 0.7, 4.3, 3.2, "REACTOR SPACE")
meter("vert", 0.6, 1.1, "SPACE\nPRESS", "rs.press", 0, 200, "kPa", { red = 5, tip = "Reactor space pressure. Any reading means a fuel channel is leaking into the graphite stack." })
meter("vert", 1.6, 1.1, "GAS\nACTIVITY", "rad.gas", 0, 100, "", { red = 20 })
meter("vert", 2.6, 1.1, "POOL\nTEMP", "pool.temp", 0, 100, "C", { red = 45 })
section("vert", 0.3, 4.05, 4.3, 2.52, "CHANNEL INTEGRITY")
digital("vert", 0.5, 4.4, "RUPTURED", "core.ruptured", "%.0f", "", 1.25, 4)
digital("vert", 1.85, 4.4, "FUEL DAMAGED", "core.damaged", "%.0f", "", 1.25, 4)
digital("vert", 3.2, 4.4, "FLOW BLOCKED", "core.blocked", "%.0f", "", 1.25, 4)
lamp("vert", 0.5, 5.45, "SPACE PRESS HIGH", "rs.press", "red", { w = 1.95, gt = 5 })
lamp("vert", 2.5, 5.45, "GAS ACTIVITY HIGH", "rad.gas", "amber", { w = 1.95, gt = 20 })
lamp("vert", 0.5, 5.95, "CHANNEL FLOW LOW", "core.blocked", "amber", { w = 1.95 })
lamp("vert", 2.5, 5.95, "FUEL FAILURE", "core.damaged", "red", { w = 1.95 })
section("vert", 4.9, 0.7, 4.3, 3.2, "ROD CHANNEL COOLING")
meter("vert", 5.2, 1.1, "FLOW", "cps.flow", 0, 100, "%", { low = 50 })
meter("vert", 6.2, 1.1, "TANK\nLEVEL", "cps.tank", 0, 100, "%", { low = 60 })
meter("vert", 7.2, 1.1, "WATER\nTEMP", "cps.temp", 0, 150, "C", { amber = 90 })
section("vert", 9.5, 0.7, 6.2, 3.2, "EMERGENCY CORE COOLING")
meter("vert", 9.8, 1.1, "ACCUM\nLEVEL", "eccs.accum", 0, 100, "%")
meter("vert", 10.8, 1.1, "INJECT\nFLOW", "eccs.flow", 0, 2500, "t/h")
lamp("vert", 12.0, 1.3, "ECCS ACTUATED", "eccs.active", "red", { w = 1.6 })
lamp("vert", 12.0, 2.0, "AUTO ARMED", "eccs.auto", "green", { w = 1.6 })
lamp("vert", 13.8, 1.3, "PUMP 1", "eccs.pump.1.run", "red", { w = 1.2 })
lamp("vert", 13.8, 2.0, "PUMP 2", "eccs.pump.2.run", "red", { w = 1.2 })
lamp("vert", 13.8, 2.7, "PUMP 3", "eccs.pump.3.run", "red", { w = 1.2 })
recorder("vert", 4.9, 4.05, REC_W, REC_H, "REACTOR SPACE", { pen("rs.press", 0, 200, "red", "SPACE PRESS", "kPa"), pen("rad.gas", 0, 100, "blue", "GAS ACTIVITY") })
recorder("vert", 7.35, 4.05, REC_W, REC_H, "DRUM SEPARATORS", { pen("pri.press", 0, 8, "red", "PRESSURE", "MPa"), pen("pri.temp", 0, 400, "blue", "TEMPERATURE", "C") })
recorder("vert", 9.8, 4.05, REC_W, REC_H, "EMERGENCY COOLING", { pen("eccs.flow", 0, 2500, "red", "INJECTION", "t/h"), pen("cps.flow", 0, 100, "blue", "CPS FLOW", "%") })
section("vert", 12.3, 4.05, 3.4, 2.52, "CORE TEMPERATURES")
meter("vert", 12.55, 4.35, "FUEL\nMAX", "core.maxFuel", 0, 3000, "C", { red = 1800, h = 2.2 })
meter("vert", 13.6, 4.35, "CLAD\nMAX", "core.maxClad", 0, 1200, "C", { h = 2.2 })
meter("vert", 14.65, 4.35, "GRAPH-\nITE", "core.graphT", 0, 1000, "C", { red = 750, h = 2.2 })
section("bench", 0.3, 0.2, 4.4, 2.0, "ROD CHANNEL COOLING")
pump("bench", 0.6, 0.55, "PUMP 1", "cps.pump.1", "cps.pump.1.run")
pump("bench", 1.8, 0.55, "PUMP 2", "cps.pump.2", "cps.pump.2.run")
toggle("bench", 3.2, 0.7, "TANK\nMAKEUP", "cps.makeup", "cps.makeup", { labels = { "SHUT", "OPEN" } })
section("bench", 5.0, 0.2, 7.0, 2.0, "EMERGENCY CORE COOLING")
toggle("bench", 5.3, 0.7, "AUTO\nACTUATION", "eccs.auto", "eccs.auto", { labels = { "OFF", "ARMED" }, key = true })
button("bench", 6.6, 0.7, "MANUAL\nINITIATE", "eccs.manual", { color = "red" })
button("bench", 7.7, 0.7, "ECCS\nRESET", "eccs.reset", { color = "black" })
toggle("bench", 8.9, 0.7, "PUMP 1", "eccs.pump.1", "eccs.pump.1.sw", { labels = { "AUTO", "RUN" } })
toggle("bench", 9.9, 0.7, "PUMP 2", "eccs.pump.2", "eccs.pump.2.sw", { labels = { "AUTO", "RUN" } })
toggle("bench", 10.9, 0.7, "PUMP 3", "eccs.pump.3", "eccs.pump.3.sw", { labels = { "AUTO", "RUN" } })
section("bench", 12.3, 0.2, 3.4, 2.0, "SHUTDOWN COOLING")
toggle("bench", 12.6, 0.7, "COOLDOWN\nSYSTEM", "pri.cooldown", "pri.cooldown")
digital("bench", 13.9, 0.9, "CIRCUIT TEMP", "pri.temp", "%.0f", "C", 1.5, 4)
section("bench", 0.3, 2.6, 6.2, 2.2, "MAIN SAFETY VALVES")
for g = 1, 3 do
	toggle("bench", 0.6 + (g - 1) * 1.9, 3.1, "GROUP " .. g, "srv." .. g, "srv." .. g .. ".sw", { labels = { "AUTO", "OPEN" } })
	lamp("bench", 1.65 + (g - 1) * 1.9, 3.5, "OPEN", "srv." .. g .. ".open", "red", { w = 0.8 })
end
section("bench", 6.9, 2.6, 2.3, 2.2, "ANNUNCIATORS")
button("bench", 7.45, 3.1, "ALARM\nACK", "ann.ack", { color = "yellow", w = 1.2 })
section("bench", 9.4, 2.6, 6.3, 2.2, "ACCIDENT LOCALISATION")
digital("bench", 9.95, 3.05, "BUBBLER POOL TEMP", "pool.temp", "%.1f", "C", 2.0, 4)
digital("bench", 12.75, 3.05, "REACTOR SPACE PRESS", "rs.press", "%.0f", "kPa", 2.4, 4)
-- Relief steam from the safety valve groups runs down to the bubbler pool.
mimic("bench", "steam", { { 1.1, 4.33 }, { 1.1, 4.9 }, { 10.95, 4.9 }, { 10.95, 3.88 } })
mimic("bench", "steam", { { 3.0, 4.33 }, { 3.0, 4.9 } })
mimic("bench", "steam", { { 4.9, 4.33 }, { 4.9, 4.9 } })

-- ------------------------------------------------------------------ P2
panel("P2", "MAIN CIRCULATION")
annunciators()
for l = 1, 2 do
	local x0 = if l == 1 then 0.3 else 9.9
	local name = if l == 1 then "A" else "B"
	local k = "loop." .. l
	section("vert", x0, 0.7, 5.8, 3.2, "LOOP " .. name .. " (" .. (if l == 1 then "WEST" else "EAST") .. " HALF)")
	meter("vert", x0 + 0.3, 1.1, "DRUM\nLEVEL", k .. ".level", -600, 600, "mm", { tip = "Narrow-range drum level, the one the level controller uses. Scram at -600 and +400 mm." })
	meter("vert", x0 + 1.3, 1.1, "LEVEL\nWIDE", k .. ".levelWide", -1500, 1500, "mm")
	meter("vert", x0 + 2.3, 1.1, "LOOP\nFLOW", k .. ".flow", 0, 20000, "t/h")
	meter("vert", x0 + 3.3, 1.1, "INLET\nSUBCOOL", k .. ".subcool", 0, 40, "C", { fmt = "%.1f", tip = "How far below boiling the water entering the core is. Feedwater flow is what provides it." })
	meter("vert", x0 + 4.3, 1.1, "SUCTION\nMARGIN", k .. ".npsh", 0, 2, "MPa", { fmt = "%.2f", low = 0.13, tip = "Pump suction margin. Below the red mark the pumps cavitate: throttle them or restore feedwater." })
end
section("vert", 6.4, 0.7, 3.2, 3.2, "DRUM SEPARATORS")
meter("vert", 6.6, 1.1, "PRESS", "pri.press", 0, 10, "MPa", { fmt = "%.2f", red = 7.35 })
meter("vert", 7.6, 1.1, "TEMP", "pri.temp", 0, 350, "C")
meter("vert", 8.6, 1.1, "HEATUP\nRATE", "pri.heatup", -20, 20, "C/min", { fmt = "%.1f", red = 10 })
recorder("vert", 0.4, 4.05, REC_W, REC_H, "DRUM LEVEL", { pen("loop.1.level", -600, 600, "red", "DRUM A", "mm"), pen("loop.2.level", -600, 600, "blue", "DRUM B", "mm") })
recorder("vert", 2.85, 4.05, REC_W, REC_H, "LOOP FLOW", { pen("loop.1.flow", 0, 20000, "red", "LOOP A", "t/h"), pen("loop.2.flow", 0, 20000, "blue", "LOOP B", "t/h") })
recorder("vert", 5.3, 4.05, REC_W, REC_H, "CORE FLOW AND STEAM", { pen("pri.flow", 0, 40000, "red", "CORE FLOW", "t/h"), pen("steam.total", 0, 5000, "blue", "STEAM", "t/h") })
recorder("vert", 7.75, 4.05, REC_W, REC_H, "CORE INLET TEMP", { pen("loop.1.tin", 0, 300, "red", "LOOP A", "C"), pen("loop.2.tin", 0, 300, "blue", "LOOP B", "C") })
section("vert", 10.2, 4.05, 5.5, 2.52, "PUMP HEAD AND CORE FLOW")
meter("vert", 10.5, 4.35, "HEAD\nLOOP A", "loop.1.dp", 0, 2.5, "MPa", { fmt = "%.2f", h = 2.2 })
meter("vert", 11.8, 4.35, "HEAD\nLOOP B", "loop.2.dp", 0, 2.5, "MPa", { fmt = "%.2f", h = 2.2 })
meter("vert", 13.1, 4.35, "CORE\nFLOW", "pri.flow", 0, 40000, "t/h", { h = 2.2 })
meter("vert", 14.4, 4.35, "CORE\nSTEAM", "core.steam", 0, 5000, "t/h", { h = 2.2 })
for l = 1, 2 do
	local x0 = if l == 1 then 0.2 else 8.1
	section("bench", x0, 0.15, 7.7, 4.7, "LOOP " .. (if l == 1 then "A" else "B") .. " MAIN CIRCULATION PUMPS")
	for i = 1, 4 do
		local key = string.format("mcp.%d%d", l, i)
		local x = x0 + 0.25 + (i - 1) * 1.55
		pump("bench", x + 0.15, 0.5, string.format("MCP-%d%d", l, i), key .. ".sw", key .. ".run")
		lamp("bench", x + 0.1, 2.1, "CAVIT", key .. ".cav", "amber", { w = 1.2 })
		digital("bench", x, 2.75, "FLOW", key .. ".flow", "%.0f", "m3/h", 1.4, 4)
		jog("bench", x - 0.05, 3.55, "THROTTLE", key .. ".valve", key .. ".valve", "%.0f", "%")
	end
	-- Pressure header: the pumps' discharge joined and led off to the core.
	local first, last = x0 + 0.25 + 0.65, x0 + 0.25 + 3 * 1.55 + 0.65
	mimic("bench", "water", { { first, 2.6 }, { last + 0.95, 2.6 } })
	for i = 1, 4 do
		local cx = x0 + 0.25 + (i - 1) * 1.55 + 0.65
		mimic("bench", "water", { { cx, 2.46 }, { cx, 2.6 } })
	end
	jog("bench", x0 + 6.3, 0.6, "BLOWDOWN", "loop." .. l .. ".blowdown", "loop." .. l .. ".blowdown", "%.0f", "%")
	toggle("bench", x0 + 6.5, 2.2, "LETDOWN\nAUTO", "loop." .. l .. ".letdownAuto", "loop." .. l .. ".letdownAuto")
end

-- ------------------------------------------------------------------ P3
panel("P3", "REACTOR CONTROL")
annunciators()
add({ kind = "coremap", face = "vert", x = 0.3, y = 0.62, w = 5.85, h = 5.85, label = "CORE MAP" })
add({ kind = "axial", face = "vert", x = 6.3, y = 0.62, w = 1.3, h = 5.85, label = "AXIAL" })
section("vert", 7.8, 0.62, 7.9, 3.05, "NEUTRON MONITORING")
meter("vert", 8.0, 1.0, "SOURCE\nRANGE", "n.logcps", 0, 6, "log cps", { fmt = "%.1f", tip = "Source range count rate, log scale. Watch it double as rods come out on the approach to criticality." })
meter("vert", 9.0, 1.0, "INTERM\nRANGE", "n.log", -9, 1, "log P", { fmt = "%.1f", tip = "Intermediate range: log10 of reactor power as a fraction of nominal." })
meter("vert", 10.0, 1.0, "POWER\nRANGE", "n.power", 0, 125, "%", { fmt = "%.1f", red = 110, amber = 100 })
meter("vert", 11.0, 1.0, "STARTUP\nRATE", "n.sur", -1, 3, "dec/min", { fmt = "%.2f", red = 2.6, amber = 1.3, tip = "Startup rate in decades per minute. 1.3 is a 20 s period (rod block), 2.6 is a 10 s period (scram)." })
meter("vert", 12.0, 1.0, "AR\nERROR", "ar.error", -10, 10, "%", { fmt = "%.1f", tip = "Reactor power minus regulator setpoint. Null this before switching a regulator in." })
digital("vert", 13.1, 1.05, "THERMAL POWER", "n.thermal", "%.0f", "MW", 2.4, 4)
digital("vert", 13.1, 1.9, "PERIOD", "n.period", "%.0f", "s", 1.0, 4)
digital("vert", 14.15, 1.9, "REACTIVITY", "n.rho", "%+.2f", "beta", 1.35, 5)
digital("vert", 13.1, 2.75, "ORM", "core.orm", "%.0f", "rods", 1.15, 3)
digital("vert", 14.35, 2.75, "VOID COEF", "core.void", "%+.2f", "beta", 1.2, 4)
add({ kind = "computer", face = "vert", x = 7.8, y = 3.8, w = 7.9, h = 2.67, label = "UNIT COMPUTER" })

add({ kind = "rodmatrix", face = "bench", x = 0.25, y = 0.25, w = 4.5, h = 4.5, label = "ROD SELECT" })
section("bench", 5.0, 0.15, 5.3, 2.35, "ROD MOTION")
button("bench", 5.15, 0.5, "WITHDRAW", "rod.move", { value = -1, hold = true, color = "white", w = 1.1 })
button("bench", 6.3, 0.5, "INSERT", "rod.move", { value = 1, hold = true, color = "white", w = 1.1 })
button("bench", 7.45, 0.5, "CLEAR\nSELECT", "rod.clear", { color = "black" })
toggle("bench", 8.4, 0.45, "SELECT", "rod.quad", "rod.quad", { labels = { "ONE", "FOUR" } })
digital("bench", 5.15, 1.62, "SELECTED", "rod.selCount", "%.0f", "", 0.95, 3)
digital("bench", 6.15, 1.62, "DEPTH", "rod.selPos", "%.2f", "m", 1.25, 3)
lamp("bench", 7.5, 1.78, "ROD BLOCK", "rod.block", "amber", { w = 1.3 })
lamp("bench", 8.85, 1.78, "AZ RODS OUT", "rod.azOut", "green", { w = 1.4 })
section("bench", 5.0, 2.65, 5.3, 2.25, "GROUPS AND INTERLOCKS")
button("bench", 5.15, 2.92, "SELECT\nAZ RODS", "rod.group", { value = 1, color = "red" })
button("bench", 6.1, 2.92, "SELECT\nUSP", "rod.group", { value = 2, color = "blue" })
button("bench", 7.05, 2.92, "SELECT\nAR", "rod.group", { value = 3, color = "green" })
button("bench", 8.0, 2.92, "SELECT\nLAR", "rod.group", { value = 4, color = "yellow" })
digital("bench", 5.15, 4.0, "RR MEAN", "rod.meanRR", "%.2f", "m", 1.2, 3)
digital("bench", 6.4, 4.0, "AZ MEAN", "rod.meanAZ", "%.2f", "m", 1.2, 3)
digital("bench", 7.65, 4.0, "USP MEAN", "rod.meanUSP", "%.2f", "m", 1.2, 3)
toggle("bench", 9.25, 2.72, "BLOCK", "rod.blockBypass", "rod.blockBypass", { labels = { "NORM", "BYP" }, key = true, compact = true })
toggle("bench", 9.25, 3.84, "AZ INTLK", "rod.azInterlockBypass", "rod.azInterlockBypass", { labels = { "NORM", "BYP" }, key = true, compact = true })

section("bench", 10.5, 0.15, 5.3, 1.9, "EMERGENCY PROTECTION")
button("bench", 10.65, 0.45, "AZ-5", "az5.button", { color = "red", big = true, w = 1.3, h = 1.45 })
button("bench", 12.05, 0.6, "AZ\nRESET", "az.reset", { color = "black" })
toggle("bench", 13.05, 0.5, "KOM\nCLUTCHES", "kom", "kom", { labels = { "NORM", "DROP" }, key = true })
for n = 1, 5 do
	lamp("bench", 14.2, 0.42 + (5 - n) * 0.31, "AZ-" .. n, "az" .. n .. ".active", "red", { w = 1.4, h = 0.3 })
end
section("bench", 10.5, 2.15, 5.3, 1.35, "")
selector("bench", 10.6, 2.2, "REGULATOR", "ar.mode", "ar.mode", { "OFF", "AR-1", "AR-2", "AR-3" })
jog("bench", 11.95, 2.2, "SETPOINT", "ar.sp", "ar.setpoint", "%.2f", "%", { digits = true })
toggle("bench", 13.5, 2.2, "LOCAL REG", "lar.sw", "lar.on", { labels = { "OFF", "ON" } })
selector("bench", 14.5, 2.2, "MAP SHOWS", "map.mode", "map.mode", { "FLUX", "POWER", "MARGIN", "FLOW", "QUAL", "FUEL T", "XENON", "GRAPH" }, 1)
section("bench", 10.5, 3.58, 5.3, 1.4, "PROTECTION BYPASS KEYS")
do
	local keys = { { "period", "PERIOD" }, { "press", "PRESS" }, { "level", "LEVEL" }, { "feed", "FEED" }, { "mcp", "MCP" }, { "turbines", "2 TG" }, { "cps", "CPS" } }
	for i, k in keys do
		add({ kind = "toggle", face = "bench", x = 10.55 + (i - 1) * 0.74, y = 3.84, w = 0.72, h = 1.12, label = k[2], cmd = "prot.bypass." .. k[1], sig = "prot.bypass." .. k[1], positions = { "", "BYP" }, key = true, compact = true })
	end
end

-- ------------------------------------------------------------------ P4
panel("P4", "FEEDWATER AND CONDENSATE")
annunciators()
section("vert", 0.3, 0.7, 6.3, 3.2, "FEEDWATER")
meter("vert", 0.5, 1.1, "FEED\nFLOW A", "loop.1.feed", 0, 2500, "t/h")
meter("vert", 1.5, 1.1, "STEAM\nFLOW A", "loop.1.steam", 0, 2500, "t/h")
meter("vert", 2.5, 1.1, "FEED\nFLOW B", "loop.2.feed", 0, 2500, "t/h")
meter("vert", 3.5, 1.1, "STEAM\nFLOW B", "loop.2.steam", 0, 2500, "t/h")
meter("vert", 4.5, 1.1, "HEADER\nPRESS", "fw.header", 0, 12, "MPa", { fmt = "%.1f" })
meter("vert", 5.5, 1.1, "FEED\nTEMP", "fw.temp", 0, 200, "C")
section("vert", 6.9, 0.7, 4.3, 3.2, "DEAERATOR AND CONDENSATE")
meter("vert", 7.1, 1.1, "DEAER\nLEVEL", "da.level", 0, 100, "%", { low = 25 })
meter("vert", 8.1, 1.1, "COND\nFLOW", "cond.flow", 0, 5000, "t/h")
meter("vert", 9.1, 1.1, "HOTWELL\n1", "tg.1.hotwell", 0, 100, "%")
meter("vert", 10.1, 1.1, "HOTWELL\n2", "tg.2.hotwell", 0, 100, "%")
section("vert", 11.5, 0.7, 4.2, 3.2, "DRUM LEVEL")
meter("vert", 11.8, 1.1, "DRUM A", "loop.1.level", -600, 600, "mm")
meter("vert", 12.8, 1.1, "DRUM B", "loop.2.level", -600, 600, "mm")
meter("vert", 13.8, 1.1, "VALVE A", "lvl.1.valve", 0, 100, "%")
meter("vert", 14.8, 1.1, "VALVE B", "lvl.2.valve", 0, 100, "%")
recorder("vert", 0.4, 4.05, REC_W, REC_H, "FEEDWATER FLOW", { pen("loop.1.feed", 0, 2500, "red", "DRUMS A", "t/h"), pen("loop.2.feed", 0, 2500, "blue", "DRUMS B", "t/h") })
recorder("vert", 2.85, 4.05, REC_W, REC_H, "STEAM FLOW", { pen("loop.1.steam", 0, 2500, "red", "DRUMS A", "t/h"), pen("loop.2.steam", 0, 2500, "blue", "DRUMS B", "t/h") })
recorder("vert", 5.3, 4.05, REC_W, REC_H, "DRUM LEVEL", { pen("loop.1.level", -600, 600, "red", "DRUM A", "mm"), pen("loop.2.level", -600, 600, "blue", "DRUM B", "mm") })
recorder("vert", 7.75, 4.05, REC_W, REC_H, "DEAERATOR", { pen("da.level", 0, 100, "red", "LEVEL", "%"), pen("da.temp", 0, 200, "blue", "TEMPERATURE", "C") })
section("vert", 10.2, 4.05, 5.5, 2.52, "UNIT TOTALS")
meter("vert", 10.5, 4.35, "TOTAL\nFEED", "fw.total", 0, 5000, "t/h", { h = 2.2 })
meter("vert", 11.8, 4.35, "TOTAL\nSTEAM", "steam.total", 0, 5000, "t/h", { h = 2.2 })
meter("vert", 13.1, 4.35, "CONDEN-\nSATE", "cond.flow", 0, 5000, "t/h", { h = 2.2 })
meter("vert", 14.4, 4.35, "DEAER\nTEMP", "da.temp", 0, 200, "C", { h = 2.2 })
section("bench", 0.2, 0.15, 5.0, 2.3, "MAIN FEEDWATER PUMPS")
for i = 1, 4 do
	pump("bench", 0.45 + (i - 1) * 1.2, 0.5, "FWP-" .. i, "fw.pump." .. i, "fw.pump." .. i .. ".run")
end
section("bench", 5.4, 0.15, 5.1, 2.3, "EMERGENCY FEEDWATER PUMPS")
for i = 1, 3 do
	pump("bench", 5.65 + (i - 1) * 1.2, 0.5, "AFWP-" .. i, "afw.pump." .. i, "afw.pump." .. i .. ".run")
end
toggle("bench", 9.3, 0.6, "AUTO\nSTART", "afw.auto", "afw.auto")
section("bench", 10.7, 0.15, 5.1, 2.3, "CONDENSATE PUMPS")
for i = 1, 3 do
	pump("bench", 10.95 + (i - 1) * 1.2, 0.5, "CP-" .. i, "cond.pump." .. i, "cond.pump." .. i .. ".run")
end
for l = 1, 2 do
	local x0 = if l == 1 then 0.2 else 5.4
	section("bench", x0, 2.6, 5.0, 2.25, "DRUM " .. (if l == 1 then "A" else "B") .. " LEVEL CONTROL")
	toggle("bench", x0 + 0.3, 3.05, "CONTROLLER", "lvl." .. l .. ".auto", "lvl." .. l .. ".auto", { labels = { "MAN", "AUTO" } })
	jog("bench", x0 + 1.5, 3.05, "FEED VALVE", "lvl." .. l .. ".valve", "lvl." .. l .. ".valve", "%.0f", "%")
	digital("bench", x0 + 3.3, 3.25, "LEVEL", "loop." .. l .. ".level", "%.0f", "mm", 1.4, 4)
end
-- Feedwater train: condensate pumps to the deaerator, feed pumps to the
-- drum level control valves.
mimic("bench", "feed", { { 0.95, 2.52 }, { 13.85, 2.52 } })
for _, x in { 0.95, 2.15, 3.35, 4.55, 6.15, 7.35, 8.55, 11.45, 12.65, 13.85 } do
	mimic("bench", "feed", { { x, 2.05 }, { x, 2.52 } })
end
for _, x in { 3.0, 8.2, 14.5 } do
	mimic("bench", "feed", { { x, 2.52 }, { x, 2.6 } })
end
section("bench", 10.7, 2.6, 5.1, 2.25, "DEAERATOR")
toggle("bench", 10.95, 3.05, "PEGGING\nSTEAM", "da.peg", "da.peg")
toggle("bench", 12.05, 3.05, "LEVEL\nCONTROL", "da.levelAuto", "da.levelAuto", { labels = { "MAN", "AUTO" } })
jog("bench", 13.2, 3.05, "COND VALVE", "da.valve", "da.valve", "%.0f", "%")
digital("bench", 14.75, 3.25, "TEMP", "da.temp", "%.0f", "C", 0.95, 3)

-- ------------------------------------------------------------------ P5
panel("P5", "TURBINE-GENERATORS")
annunciators()
for k = 1, 2 do
	local x0 = if k == 1 then 0.2 else 8.6
	local key = "tg." .. k
	section("vert", x0, 0.7, 7.2, 3.2, "TURBINE " .. k)
	meter("vert", x0 + 0.2, 1.1, "SPEED", key .. ".rpm", 0, 2200, "rpm", { red = 1980 })
	meter("vert", x0 + 1.07, 1.1, "CONTROL\nVALVES", key .. ".cv", 0, 110, "%")
	meter("vert", x0 + 1.94, 1.1, "BYPASS", key .. ".bypass", 0, 100, "%")
	meter("vert", x0 + 2.81, 1.1, "COND\nPRESS", key .. ".vac", 0, 105, "kPa", { fmt = "%.1f", red = 30, amber = 15, tip = "Condenser absolute pressure. About 5 kPa is good vacuum; the turbine trips at 30." })
	meter("vert", x0 + 3.68, 1.1, "VIBRA-\nTION", key .. ".vib", 0, 15, "mm/s", { fmt = "%.1f", red = 11.8, amber = 7.1 })
	meter("vert", x0 + 4.55, 1.1, "METAL\nTEMP", key .. ".metal", 0, 300, "C")
	meter("vert", x0 + 5.42, 1.1, "THERMAL\nSTRESS", key .. ".stress", 0, 150, "", { red = 60, tip = "Steam-to-metal temperature difference weighted by steam flow. Above the red mark the turbine is being damaged: slow down." })
	meter("vert", x0 + 6.29, 1.1, "LUBE\nOIL", key .. ".lube", 0, 0.3, "MPa", { fmt = "%.2f", low = 0.12 })
end
section("vert", 7.5, 0.7, 1.0, 3.2, "")
meter("vert", 7.6, 1.1, "GRID\nFREQ", "grid.hz", 58, 62, "Hz", { fmt = "%.2f", tip = "Grid frequency. Bring the generator to this before closing its breaker." })
section("vert", 0.2, 4.05, 4.7, 2.52, "PRESSURE CONTROL")
meter("vert", 0.5, 4.35, "STEAM\nPRESS", "pri.press", 0, 10, "MPa", { fmt = "%.2f", red = 7.35, h = 2.2 })
meter("vert", 1.6, 4.35, "PRESS\nSET", "ehc.pressSet", 0, 10, "MPa", { fmt = "%.2f", h = 2.2 })
meter("vert", 2.7, 4.35, "STEAM\nDEMAND", "ehc.demand", 0, 120, "%", { h = 2.2 })
meter("vert", 3.8, 4.35, "TOTAL\nSTEAM", "steam.total", 0, 5000, "t/h", { h = 2.2 })
recorder("vert", 5.1, 4.05, REC_W, REC_H, "TURBINE SPEED", { pen("tg.1.rpm", 0, 2000, "red", "TG-1", "rpm"), pen("tg.2.rpm", 0, 2000, "blue", "TG-2", "rpm") })
recorder("vert", 7.6, 4.05, REC_W, REC_H, "GENERATOR LOAD", { pen("gen.1.mw", 0, 450, "red", "GEN 1", "MW"), pen("gen.2.mw", 0, 450, "blue", "GEN 2", "MW") })
recorder("vert", 10.1, 4.05, REC_W, REC_H, "CONDENSER PRESSURE", { pen("tg.1.vac", 0, 30, "red", "COND 1", "kPa"), pen("tg.2.vac", 0, 30, "blue", "COND 2", "kPa") })
recorder("vert", 12.6, 4.05, REC_W, REC_H, "SHELL METAL TEMP", { pen("tg.1.metal", 0, 300, "red", "TG-1", "C"), pen("tg.2.metal", 0, 300, "blue", "TG-2", "C") })
section("bench", 6.9, 0.15, 2.2, 4.7, "PRESSURE REG")
toggle("bench", 7.5, 0.5, "REGULATOR", "ehc.pressAuto", "ehc.pressAuto", { labels = { "OUT", "IN" } })
jog("bench", 7.25, 2.0, "PRESS SET", "ehc.press", "ehc.pressSet", "%.2f", "MPa", { digits = true })
digital("bench", 7.3, 3.6, "DEMAND", "ehc.demand", "%.0f", "%", 1.4, 3)
for k = 1, 2 do
	local x0 = if k == 1 then 0.15 else 9.25
	local key = "tg." .. k
	section("bench", x0, 0.15, 6.6, 4.7, "TURBINE " .. k)
	button("bench", x0 + 0.15, 0.5, "TRIP", key .. ".trip", { color = "red" })
	button("bench", x0 + 1.05, 0.5, "RESET\nLATCH", key .. ".reset", { color = "green" })
	lamp("bench", x0 + 0.1, 1.6, "TRIPPED", key .. ".trip", "red", { w = 0.95 })
	lamp("bench", x0 + 1.05, 1.6, "LATCHED", key .. ".stop", "green", { w = 0.95 })
	jog("bench", x0 + 2.05, 0.4, "STEAM ISOL", key .. ".iso", key .. ".iso", "%.0f", "%")
	selector("bench", x0 + 3.65, 0.4, "SPEED SET", key .. ".speed", key .. ".speedTarget", { "STOP", "500", "1800" })
	jog("bench", x0 + 5.0, 0.4, "LOAD SET", key .. ".load", key .. ".load", "%.0f", "%")
	toggle("bench", x0 + 2.15, 1.85, "BYPASS", key .. ".bypassAuto", key .. ".bypassAuto", { labels = { "MAN", "AUTO" } })
	jog("bench", x0 + 3.3, 1.85, "BYPASS VLV", key .. ".bypass", key .. ".bypass", "%.0f", "%")
	digital("bench", x0 + 5.0, 2.05, "GENERATOR", "gen." .. k .. ".mw", "%.0f", "MW", 1.4, 3)
	local row = {
		{ "LUBE\nOIL PUMP", ".lube", ".lubeAC" },
		{ "TURNING\nGEAR", ".tgear", ".tgear" },
		{ "GLAND\nSTEAM", ".gland", ".gland" },
		{ "CIRC\nPUMP A", ".cw1", ".cw1" },
		{ "CIRC\nPUMP B", ".cw2", ".cw2" },
		{ "VACUUM\nPUMP", ".vacPump", ".vacPump" },
		{ "STEAM\nEJECTOR", ".sjae", ".sjae" },
	}
	for i, r in row do
		toggle("bench", x0 + 0.08 + (i - 1) * 0.93, 3.55, r[1], key .. r[2], key .. r[3], { compact = true })
	end
	toggle("bench", x0 + 0.55, 2.2, "VAC BREAKER", key .. ".vacBreaker", key .. ".vacBreaker", { labels = { "SHUT", "OPEN" }, compact = true })
end

-- ------------------------------------------------------------------ P6
panel("P6", "ELECTRICAL")
annunciators()
for k = 1, 2 do
	local x0 = if k == 1 then 0.2 else 4.6
	local key = "gen." .. k
	section("vert", x0, 0.7, 4.2, 3.2, "GENERATOR " .. k)
	meter("vert", x0 + 0.2, 1.1, "MW", key .. ".mw", 0, 450, "MW")
	meter("vert", x0 + 1.2, 1.1, "MVAR", key .. ".mvar", -200, 200, "MVAr")
	meter("vert", x0 + 2.2, 1.1, "VOLTS", key .. ".kv", 0, 26, "kV", { fmt = "%.1f" })
	meter("vert", x0 + 3.2, 1.1, "FREQ", key .. ".hz", 55, 65, "Hz", { fmt = "%.2f" })
end
add({ kind = "sync", face = "vert", x = 9.1, y = 0.7, w = 3.2, h = 3.2, label = "SYNCHROSCOPE" })
section("vert", 12.6, 0.7, 3.2, 3.2, "UNIT OUTPUT")
digital("vert", 12.8, 1.05, "GROSS", "plant.gross", "%.0f", "MW", 2.8, 4)
digital("vert", 12.8, 1.95, "AUXILIARIES", "plant.aux", "%.1f", "MW", 2.8, 4)
digital("vert", 12.8, 2.85, "NET TO GRID", "plant.net", "%.0f", "MW", 2.8, 4)
section("vert", 0.2, 4.1, 9.0, 2.3, "BUSES")
do
	local names = { "1A", "1B", "2A", "2B" }
	for i, name in names do
		local x = 0.4 + (i - 1) * 1.55
		lamp("vert", x, 4.5, "BUS " .. name, "bus." .. name .. ".live", "red", { w = 1.4 })
		lamp("vert", x, 5.05, "ON RESERVE", "bus." .. name .. ".reserve", "amber", { w = 1.4 })
		digital("vert", x, 5.55, "LOAD", "bus." .. name .. ".mw", "%.1f", "MW", 1.4, 4)
	end
	for i = 1, 3 do
		local x = 6.7 + (i - 1) * 0.83
		lamp("vert", x, 4.5, "E" .. i, "ebus." .. i .. ".live", "red", { w = 0.8 })
		lamp("vert", x, 5.05, "DG" .. i, "dg." .. i .. ".run", "amber", { w = 0.8 })
		lamp("vert", x, 5.6, "BKR", "dg." .. i .. ".bkr", "red", { w = 0.8 })
	end
end
recorder("vert", 9.5, 4.05, REC_W, REC_H, "UNIT OUTPUT", { pen("plant.gross", 0, 900, "red", "GROSS", "MW"), pen("plant.net", 0, 900, "blue", "NET", "MW") })
recorder("vert", 11.95, 4.05, REC_W, REC_H, "FREQUENCY", { pen("grid.hz", 58, 62, "red", "GRID", "Hz"), pen("gen.1.hz", 58, 62, "blue", "GEN 1", "Hz") })
meter("vert", 14.6, 4.05, "AUX\nLOAD", "plant.aux", 0, 80, "MW", { h = 2.4 })
for k = 1, 2 do
	local x0 = if k == 1 then 0.15 else 5.0
	local key = "gen." .. k
	section("bench", x0, 0.15, 4.75, 2.3, "GENERATOR " .. k)
	toggle("bench", x0 + 0.1, 0.6, "FIELD\nBREAKER", key .. ".field", key .. ".field")
	jog("bench", x0 + 1.12, 0.6, "VOLTAGE", key .. ".volt", key .. ".kv", "%.1f", "kV", { lo = 0, hi = 26 })
	toggle("bench", x0 + 2.65, 0.6, "GEN\nBREAKER", key .. ".gcb", key .. ".gcb", { labels = { "TRIP", "CLOSE" } })
	toggle("bench", x0 + 3.68, 0.6, "YARD\nBREAKER", key .. ".yard", key .. ".yard", { labels = { "TRIP", "CLOSE" } })
end
-- One-line diagram: each generator through its breaker and the yard
-- breaker to the grid, and each auxiliary bus fed from its normal or its
-- reserve breaker.
for k = 1, 2 do
	local x0 = if k == 1 then 0.15 else 5.0
	mimic("bench", "power", { { x0 + 3.15, 1.88 }, { x0 + 3.15, 2.2 }, { x0 + 4.66, 2.2 } })
	mimic("bench", "power", { { x0 + 4.18, 1.88 }, { x0 + 4.18, 2.2 } })
end
for i = 1, 4 do
	local x = 0.3 + (i - 1) * 3.05
	mimic("bench", "power", { { x + 0.5, 4.33 }, { x + 0.5, 4.6 }, { x + 1.5, 4.6 }, { x + 1.5, 4.33 } })
end
section("bench", 9.85, 0.15, 2.65, 2.3, "SYNCHRONISING")
selector("bench", 9.95, 0.6, "SCOPE", "sync.select", "sync.select", { "OFF", "GEN 1", "GEN 2" }, 0, 1.25)
toggle("bench", 11.3, 0.6, "SYNC\nCHECK", "sync.bypass", "sync.bypass", { labels = { "NORM", "BYP" }, key = true })
section("bench", 12.6, 0.15, 3.3, 2.3, "DIESEL GENERATORS")
for i = 1, 3 do
	selector("bench", 12.65 + (i - 1) * 1.08, 0.6, "DG-" .. i, "dg." .. i .. ".mode", "dg." .. i .. ".mode", { "OFF", "AUTO", "RUN" }, 0, 1.05)
end
section("bench", 0.15, 2.6, 12.35, 2.25, "6.9 kV AUXILIARY BUSES")
do
	local names = { "1A", "1B", "2A", "2B" }
	for i, name in names do
		local x = 0.3 + (i - 1) * 3.05
		toggle("bench", x, 3.05, name .. "\nNORMAL", "bus." .. name .. ".normal", "bus." .. name .. ".normal", { labels = { "TRIP", "CLOSE" } })
		toggle("bench", x + 1.0, 3.05, name .. "\nRESERVE", "bus." .. name .. ".reserve", "bus." .. name .. ".reserve", { labels = { "TRIP", "CLOSE" } })
		toggle("bench", x + 2.0, 3.05, "AUTO\nTRANSFER", "bus." .. name .. ".ats", "bus." .. name .. ".ats")
	end
end
section("bench", 12.6, 2.6, 3.3, 2.25, "EMERGENCY BUS TIES")
for i = 1, 3 do
	toggle("bench", 12.65 + (i - 1) * 1.07, 3.05, "E" .. i .. " TIE", "ebus." .. i .. ".tie", "ebus." .. i .. ".tie", { labels = { "OPEN", "CLOSE" } })
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
		if w.pens then
			for _, pen in w.pens do
				needSignal(pen.sig)
			end
		end
		if w.cmd then
			commandSet[w.cmd] = true
			if w.hold or w.kind == "jog" then
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
	local W = PanelLayout.PANEL_WIDTH
	local z = PanelLayout.BACK_WALL_Z
	local cx = PanelLayout.CORNER_X
	local corner = PanelLayout.CORNER_PANEL
	-- How far the corner section reaches along each run from the corner point.
	local reach = W / math.sqrt(2)
	if index < corner then
		-- On the wing, facing east.
		local fromCorner = reach + (corner - index - 0.5) * W
		return Vector3.new(cx, 0, z + fromCorner), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0)
	elseif index == corner then
		local d = 1 / math.sqrt(2)
		return Vector3.new(cx + reach / 2, 0, z + reach / 2), Vector3.new(d, 0, -d), Vector3.new(d, 0, d)
	end
	-- On the back wall, facing south.
	return Vector3.new(cx + reach + (index - corner - 0.5) * W, 0, z), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1)
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
			width = PanelLayout.PANEL_WIDTH,
			height = depth,
			scale = 1,
		}
	elseif face == "vert" then
		return {
			center = at(backY + PanelLayout.VERT_HEIGHT / 2, backZ),
			right = right,
			up = up,
			normal = back,
			width = PanelLayout.PANEL_WIDTH,
			height = PanelLayout.VERT_HEIGHT,
			scale = 1,
		}
	else
		return {
			center = at(backY + PanelLayout.VERT_HEIGHT + PanelLayout.ANN_HEIGHT / 2, backZ),
			right = right,
			up = up,
			normal = back,
			width = PanelLayout.PANEL_WIDTH,
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
