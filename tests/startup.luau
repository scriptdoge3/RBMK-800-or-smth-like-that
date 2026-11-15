-- A scripted operator takes the unit from cold shutdown to full power on the
-- grid, following the same procedure the in-game checklist gives players.
-- This is the main integration test: if it passes, the plant is startable
-- and every major system does its job.
--
--   lune run tests/startup            by-the-book startup
--   lune run tests/startup -- quiet   same, summary only
local H = require("./harness")
local process = require("@lune/process")
local Config = H.require(H.shared.Config)
local Plant = H.require(H.server.Sim.Plant)

local quiet = table.find(process.args, "quiet") ~= nil
local trace = table.find(process.args, "trace") ~= nil
local stopAfter: string? = nil
for _, a in process.args do
	local v = string.match(a, "^until=(.+)$")
	if v then
		stopAfter = v
	end
end
local DT = 0.1

local plant = Plant.new({ seed = 3, age = 1, hoursSinceShutdown = 80, failures = false })
local S = plant.S
local core, rods = plant.core, plant.rods

-- ---------------------------------------------------------------- runner
local held: { [string]: number } = {}
local lastReport = -1e9
local phase = "init"
local seenLog = 0

local function report(force: boolean?)
	if quiet and not force then
		return
	end
	print(string.format(
		"[%5.1f min] %-10s P=%8.3f%% (%6.0f MWt) T=%5.1f C p=%5.2f MPa lvl=%5.0f/%5.0f flow=%5.0f steam=%5.0f t/h fw=%5.0f  MWe=%5.1f  ORM=%5.1f Kf=%.2f AR=%d sp=%5.1f%% ARpos=%.1f",
		plant.time / 60, phase, S["n.power"], S["n.thermal"], S["pri.temp"], S["pri.press"], S["loop.1.level"], S["loop.2.level"],
		S["pri.flow"], S["steam.total"], S["fw.total"], S["plant.gross"], S["core.orm"], S["core.fluxPeak"], S["ar.mode"], S["ar.setpoint"],
		S["ar.pos" .. math.max(1, S["ar.mode"])]))
end

local function tick()
	for name, v in held do
		plant:hold(name, v)
	end
	plant:step(DT)
	if trace and phase ~= "aux" and phase ~= "mcp" and phase ~= "critical" and phase ~= "heatup" and math.floor(plant.time / 4) ~= math.floor((plant.time - DT) / 4) then
		print(string.format("   t=%7.1f P=%6.2f sp=%5.1f per=%6.0f rho=%+.3f AR=%.2f p=%5.3f lvl=%4.0f/%4.0f fw=%4.0f/%4.0f stm=%4.0f byp=%3.0f/%3.0f sub=%4.1f x=%.3f fwT=%3.0f dem=%3.0f cv=%3.0f rpm=%4.0f",
			plant.time, S["n.power"], S["ar.setpoint"], S["n.period"], S["n.rho"], S["ar.pos1"], S["pri.press"], S["loop.1.level"], S["loop.2.level"],
			S["loop.1.feed"], S["loop.2.feed"], S["steam.total"], S["tg.1.bypass"], S["tg.2.bypass"], S["loop.1.subcool"], core.loopExitQuality[1], S["fw.temp"], S["ehc.demand"], S["tg.1.cv"], S["tg.1.rpm"]))
	end
	if not quiet then
		for i = seenLog + 1, #plant.logLines do
			print(string.format("           | %s", plant.logLines[i].text))
		end
	end
	seenLog = #plant.logLines
	if plant.time - lastReport >= 120 then
		lastReport = plant.time
		report()
	end
	if core.destroyed then
		report(true)
		error("the reactor was destroyed during the startup")
	end
	if S["az5.active"] == 1 and phase ~= "aux" and phase ~= "mcp" and phase ~= "critical" then
		report(true)
		error("reactor scrammed during phase '" .. phase .. "'")
	end
end

local function wait(seconds: number)
	local n = math.ceil(seconds / DT)
	for _ = 1, n do
		tick()
	end
end

local function waitUntil(cond: () -> boolean, timeout: number, what: string)
	local t = 0
	while not cond() do
		tick()
		t += DT
		if t > timeout then
			report(true)
			error("timed out waiting for: " .. what)
		end
	end
end

local function cmd(name: string, v: number?)
	if not plant:command(name, v or 1) then
		error("unknown command " .. name)
	end
end

local function hold(name: string, v: number)
	if not plant.cmd[name] then
		error("unknown command " .. name)
	end
	held[name] = v
end

local function release(name: string)
	held[name] = nil
	plant:hold(name, 0)
end

-- Hold a raise/lower switch until a signal reaches a value.
local function drive(name: string, signal: string, target: number, timeout: number?)
	local dir = if S[signal] < target then 1 else -1
	hold(name, dir)
	waitUntil(function()
		return (dir > 0 and S[signal] >= target) or (dir < 0 and S[signal] <= target)
	end, timeout or 300, signal .. " -> " .. target)
	release(name)
end

local function checkpoint(name: string)
	if stopAfter == name then
		print("\nstopping after '" .. name .. "' as requested")
		H.finish()
		process.exit(0)
	end
end

-- ---------------------------------------------------------------- rods
-- The operator reads the core map: rods come out where the flux is lowest
-- and go back in where it is highest, which keeps the power shape flat.
local L = core.layout
local function localPower(i: number): number
	local cell = L.rods[i].cell
	local x, y = L.cellX[cell], L.cellY[cell]
	local s, n = 0, 0
	for f = 1, core.NF do
		local c = core.fuelCell[f]
		local dx, dy = L.cellX[c] - x, L.cellY[c] - y
		if dx * dx + dy * dy <= 16 then
			s += core.fluxRel[f]
			n += 1
		end
	end
	return if n > 0 then s / n else 0
end

local function pickRods(count: number, wantInserted: boolean): { number }
	local cand = {}
	for _, i in rods.byKind.RR do
		local pos = core.rodPos[i]
		if not rods.stuck[i] and ((wantInserted and pos > 0.05) or (not wantInserted and pos < 6.45)) then
			table.insert(cand, { i = i, p = localPower(i) })
		end
	end
	table.sort(cand, function(a, b)
		if wantInserted then
			return a.p < b.p
		end
		return a.p > b.p
	end)
	local out = {}
	for _, c in cand do
		if #out >= count then
			break
		end
		-- Keep the members of one gang well apart.
		local ok = true
		local cell = L.rods[c.i].cell
		for _, j in out do
			local o = L.rods[j].cell
			local dx, dy = L.cellX[cell] - L.cellX[o], L.cellY[cell] - L.cellY[o]
			if dx * dx + dy * dy < 100 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(out, c.i)
		end
	end
	return out
end

local function moveSelected(dir: number, untilFn: () -> boolean, timeout: number)
	hold("rod.move", dir)
	local t = 0
	while not untilFn() do
		tick()
		t += DT
		if t > timeout then
			break
		end
	end
	release("rod.move")
end

local function countOut(): number
	local n = 0
	for _, i in rods.byKind.RR do
		if core.rodPos[i] < 3.25 then
			n += 1
		end
	end
	return n
end

-- Move `count` rods by `distance` metres (the whole stroke by default).
local function withdrawGang(count: number, distance: number?)
	local gang = pickRods(count, true)
	if #gang == 0 then
		return false
	end
	cmd("rod.clear")
	local target = {}
	for _, i in gang do
		cmd("rod.select", i)
		target[i] = math.max(0, core.rodPos[i] - (distance or 6.5))
	end
	moveSelected(-1, function()
		for _, i in gang do
			if core.rodPos[i] > target[i] + 0.01 then
				return false
			end
		end
		return true
	end, 30)
	cmd("rod.clear")
	return true
end

local function insertGang(count: number, distance: number?)
	local gang = pickRods(count, false)
	if #gang == 0 then
		return false
	end
	cmd("rod.clear")
	local target = {}
	for _, i in gang do
		cmd("rod.select", i)
		target[i] = math.min(6.5, core.rodPos[i] + (distance or 6.5))
	end
	moveSelected(1, function()
		for _, i in gang do
			if core.rodPos[i] < target[i] - 0.01 then
				return false
			end
		end
		return true
	end, 30)
	cmd("rod.clear")
	return true
end

-- Keep the automatic regulator's rods in their working band by shifting
-- manual rods a metre at a time, the way an operator does all day long.
local function compensate()
	local mode = S["ar.mode"]
	if mode < 1 or S["rod.block"] ~= 0 then
		return
	end
	local pos = S["ar.pos" .. mode]
	if pos < 1.8 then
		withdrawGang(2, 1.0)
	elseif pos > 4.7 then
		insertGang(2, 1.0)
	end
end

local function waitCompensating(seconds: number)
	local t = 0
	while t < seconds do
		wait(5)
		t += 5
		compensate()
	end
end

-- Walk the regulator setpoint to a new value, pausing whenever the reactor
-- has fallen behind so power never has to chase a distant target.
local function rampSetpoint(target: number, holdAfter: number?)
	local guard = 0
	while math.abs(S["ar.setpoint"] - target) > 0.02 * math.max(target, 0.05) do
		local sp, power = S["ar.setpoint"], S["n.power"]
		local dir = if sp < target then 1 else -1
		local behind = if sp < 5 then power < 0.85 * sp else sp - power > 1.5
		if dir > 0 and behind then
			wait(3)
			compensate()
		else
			hold("ar.sp", dir)
			wait(1)
			release("ar.sp")
		end
		guard += 1
		if guard > 6000 then
			error("setpoint ramp to " .. target .. " stalled")
		end
	end
	if holdAfter then
		waitCompensating(holdAfter)
	end
end

-- ---------------------------------------------------------------- procedure
local wall = os.clock()

phase = "aux"
H.check(S["bus.1A.live"] == 1 and S["bus.2B.live"] == 1, "auxiliary buses energised from the startup transformer")
cmd("cond.pump.1", 1)
for k = 1, 2 do
	cmd("tg." .. k .. ".cw1", 1)
	cmd("tg." .. k .. ".cw2", 1)
	cmd("tg." .. k .. ".lube", 1)
	cmd("tg." .. k .. ".tgear", 1)
	cmd("tg." .. k .. ".vacBreaker", 0)
	cmd("tg." .. k .. ".vacPump", 1)
end
cmd("loop.1.letdownAuto", 1)
cmd("loop.2.letdownAuto", 1)
wait(5)

phase = "mcp"
-- Cold water at low pressure gives the pumps little suction head, so they
-- are started against partly closed throttles.
for l = 1, 2 do
	for i = 1, 3 do
		hold(string.format("mcp.%d%d.valve", l, i), -1)
	end
end
waitUntil(function()
	return S["mcp.11.valve"] <= 35
end, 60, "throttles to 35%")
for l = 1, 2 do
	for i = 1, 3 do
		release(string.format("mcp.%d%d.valve", l, i))
	end
end
for l = 1, 2 do
	for i = 1, 3 do
		cmd(string.format("mcp.%d%d.sw", l, i), 1)
		wait(8)
	end
end
wait(20)
print(string.format("  cold flow with throttles at 35%%: %.0f / %.0f t/h, suction margin %.3f MPa", S["loop.1.flow"], S["loop.2.flow"], S["loop.1.npsh"]))
H.near(S["loop.1.flow"], 8000, 15000, "loop A flow with three throttled pumps (t/h)")
H.check(S["mcp.11.cav"] == 0, "no cavitation with throttled pumps")
cmd("pri.cooldown", 0)

phase = "critical"
cmd("az.reset")
wait(1)
H.check(S["az5.active"] == 0, "protection resets in cold shutdown")
cmd("rod.group", 1) -- shutdown (AZ) rods
moveSelected(-1, function()
	return S["rod.azOut"] == 1
end, 40)
cmd("rod.clear")
H.check(S["rod.azOut"] == 1, "shutdown rods cocked")
-- Coarse withdrawal well below critical, finer as the count rate climbs.
while core.keff < 0.985 do
	if not withdrawGang(8) then
		break
	end
	wait(3)
end
while core.keff < 0.9960 do
	if not withdrawGang(4) then
		break
	end
	wait(6)
end
report()
-- Final approach in one-metre steps, waiting out each rise in count rate.
-- The low-range regulator is armed so that it catches the power at 0.02%.
hold("ar.sp", 1)
waitUntil(function()
	return S["ar.setpoint"] >= 0.02
end, 600, "low-range setpoint")
release("ar.sp")
cmd("ar.mode", 3)
local steps = 0
while S["n.power"] < 0.018 and steps < 200 do
	if S["n.period"] > 0 and S["n.period"] < 45 then
		wait(5)
	else
		withdrawGang(2, 1.0)
		steps += 1
		wait(8)
	end
end
waitCompensating(60)
report()
H.check(S["az5.active"] == 0, "criticality reached without a scram")
H.near(S["n.power"], 0.015, 0.03, "low-range regulator holding 0.02% power")
print(string.format("  critical with %d of %d manual rods withdrawn, ORM %.1f, flux peaking %.2f, at %.1f min", countOut(), #rods.byKind.RR, S["core.orm"], S["core.fluxPeak"], plant.time / 60))

checkpoint("critical")

phase = "heatup"
-- Raise to the point of adding heat and warm the circuit inside the limit.
rampSetpoint(1.0)
rampSetpoint(3.6, 20)
cmd("ehc.pressAuto", 1)
local glandOn, sjaeOn, feedOn = false, false, false
local maxRate = 0
while S["pri.press"] < 6.6 do
	waitCompensating(10)
	maxRate = math.max(maxRate, S["pri.heatup"])
	local p = S["pri.press"]
	if p > 0.6 and not glandOn then
		glandOn = true
		cmd("tg.1.gland", 1)
		cmd("tg.2.gland", 1)
	end
	if p > 1.2 and not sjaeOn then
		sjaeOn = true
		cmd("tg.1.sjae", 1)
		cmd("tg.2.sjae", 1)
		cmd("tg.1.vacPump", 0)
		cmd("tg.2.vacPump", 0)
	end
	if p > 1.0 and not feedOn then
		feedOn = true
		cmd("fw.pump.1", 1)
		cmd("lvl.1.auto", 1)
		cmd("lvl.2.auto", 1)
	end
	if plant.time > 3 * 3600 then
		error("heatup took more than three hours")
	end
end
report()
print(string.format("  heatup complete at %.1f min, peak rate %.1f C/min", plant.time / 60, maxRate))
H.check(maxRate < 11.5, "heatup stayed inside the 10 C/min limit")
H.check(S["az5.active"] == 0, "no scram during heatup")

checkpoint("heatup")

phase = "regulator"
-- With pressure held by the bypass there is steam to spare: start warming
-- the feedwater, then hand over from the low-range regulator to AR-1 with
-- the setpoint matched.
cmd("da.peg", 1)
rampSetpoint(6)
waitCompensating(30)
cmd("ar.mode", 1)
waitCompensating(20)
rampSetpoint(16, 30)
waitUntil(function()
	return S["pri.press"] > 6.8
end, 1200, "pressure at the regulator setpoint")
H.check(S["tg.1.bypass"] + S["tg.2.bypass"] > 1, "bypass valves are holding pressure")
report()

checkpoint("regulator")

phase = "turbine 1"
local function startTurbine(k: number)
	local key = "tg." .. k
	cmd(key .. ".reset")
	wait(1)
	if S[key .. ".trip"] == 1 then
		error("turbine " .. k .. " would not latch")
	end
	drive(key .. ".iso", key .. ".iso", 100, 60)
	cmd(key .. ".speed", 1)
	waitUntil(function()
		return S[key .. ".rpm"] > 480
	end, 400, "turbine at 500 rpm")
	waitCompensating(120) -- warm-up soak
	cmd(key .. ".speed", 2)
	waitUntil(function()
		return S[key .. ".rpm"] > 1795
	end, 600, "turbine at 1800 rpm")
	waitCompensating(40)
	cmd("gen." .. k .. ".field", 1)
	cmd("sync.select", k)
	wait(5)
	waitUntil(function()
		if S["sync.ok"] == 1 then
			cmd("gen." .. k .. ".gcb", 1)
		end
		return S["gen." .. k .. ".gcb"] == 1
	end, 600, "generator synchronised")
	cmd("sync.select", 0)
	-- Initial load, then a soak before loading further.
	drive(key .. ".load", key .. ".load", 12, 60)
	waitCompensating(120)
end
startTurbine(1)
H.check(S["gen.1.gcb"] == 1 and S["gen.1.mw"] > 5, "generator 1 on the grid and carrying load")
report()
drive("tg.1.load", "tg.1.load", 104, 200)

phase = "turbine 2"
startTurbine(2)
H.check(S["gen.2.gcb"] == 1 and S["gen.2.mw"] > 5, "generator 2 on the grid and carrying load")
drive("tg.2.load", "tg.2.load", 104, 200)
report()

checkpoint("turbines")

phase = "ascension"
cmd("fw.pump.2", 1)
cmd("cond.pump.2", 1)
for _, target in { 30, 45, 60 } do
	rampSetpoint(target, 60)
	if target == 30 then
		cmd("lar.sw", 1)
	end
	if target == 45 then
		cmd("fw.pump.3", 1)
	end
end
for _, target in { 75, 90, 100 } do
	rampSetpoint(target, 60)
end
waitCompensating(600)
report(true)

local scrams = plant.protection.scrams
print(string.format("\nstartup finished: %.1f min of plant time, %.0f s wall", plant.time / 60, os.clock() - wall))
H.near(S["n.power"], 97, 103, "reactor power (%)")
H.near(S["plant.gross"], 740, 840, "gross generation (MWe)")
H.near(S["pri.press"], 6.7, 7.1, "drum pressure (MPa)")
H.near(S["loop.1.level"], -120, 120, "drum A level (mm)")
H.near(S["loop.2.level"], -120, 120, "drum B level (mm)")
H.near(S["fw.temp"], 150, 172, "feedwater temperature (C)")
H.near(S["core.kr"], 1.0, 1.9, "radial peaking factor")
H.check(S["core.minMargin"] > 1.3, string.format("dryout margin healthy (%.2f)", S["core.minMargin"]))
H.check(scrams == 0, "no scram on the way up")
H.check(S["core.ruptured"] == 0, "no channel ruptures")
H.check(plant.time < 100 * 60, string.format("by-the-book startup takes under 100 minutes (%.0f)", plant.time / 60))

-- Finally, the big red button from full power: at the design point the
-- scram must work cleanly.
phase = "scram"
local before = S["n.power"]
cmd("az5.button")
local peak = before
for _ = 1, 250 do
	plant:step(DT)
	peak = math.max(peak, S["n.power"])
end
print(string.format("  AZ-5 from %.0f%%: peak %.1f%%, 25 s later %.2f%%, rods mean depth %.1f m", before, peak, S["n.power"], S["rod.meanRR"]))
H.check(peak < before + 2, "no power rise on AZ-5 from the design state")
H.check(S["n.power"] < 5, "reactor shut down 25 s after AZ-5")
for _ = 1, 3000 do
	plant:step(DT)
end
print(string.format("  5 min after scram: %.0f MWt decay heat, p=%.2f MPa, levels %.0f/%.0f mm, turbines tripped %d, ruptures %d",
	S["n.thermal"], S["pri.press"], S["loop.1.level"], S["loop.2.level"], S["tg.tripped"], S["core.ruptured"]))
H.check(S["rod.allIn"] == 1, "every rod fully inserted")
H.check(S["core.ruptured"] == 0 and S["core.destroyed"] == 0, "no damage from the scram")
H.near(S["pri.press"], 4.0, 7.5, "pressure under control after the scram (MPa)")
H.finish()
