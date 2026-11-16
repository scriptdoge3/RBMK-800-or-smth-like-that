-- Plant transients from full power. Each case starts from a fresh unit
-- placed directly in operation (see Plant.hotStart).
--
--   lune run tests/transients            all cases
--   lune run tests/transients -- steady  one case by name
local H = require("./harness")
local process = require("@lune/process")
local Config = H.require(H.shared.Config)
local Plant = H.require(H.server.Sim.Plant)

local only: string? = nil
for _, a in process.args do
	if a ~= "--" then
		only = a
	end
end
local DT = 0.1

local function fresh(power: number?)
	local plant = Plant.new({ seed = 11, age = 1, hoursSinceShutdown = 90, failures = false })
	plant:hotStart(power or 1)
	return plant
end

local function run(plant, seconds: number, each: ((t: number) -> ())?)
	local n = math.floor(seconds / DT + 0.5)
	for i = 1, n do
		plant:step(DT)
		if each then
			each(i * DT)
		end
	end
end

local function line(plant, label: string)
	local S = plant.S
	print(string.format("    %-22s P=%6.1f%%  %4.0f MWe  p=%.2f MPa  lvl=%5.0f/%5.0f  flow=%5.0f  fw=%4.0f stm=%4.0f t/h  margin=%.2f  ORM=%.0f  AR=%.1f m",
		label, S["n.power"], S["plant.gross"], S["pri.press"], S["loop.1.level"], S["loop.2.level"], S["pri.flow"], S["fw.total"], S["steam.total"],
		S["core.minMargin"], S["core.orm"], S["ar.pos1"]))
end

local function logSince(plant, from: number): { string }
	local out = {}
	for i = from + 1, #plant.logLines do
		table.insert(out, plant.logLines[i].text)
	end
	return out
end

local cases: { { name: string, fn: () -> () } } = {}
local function case(name: string, fn: () -> ())
	table.insert(cases, { name = name, fn = fn })
end

case("steady", function()
	local plant = fresh(1)
	local S = plant.S
	line(plant, "after hot start")
	local mark = #plant.logLines
	local minP, maxP = 999, 0
	run(plant, 600, function()
		minP, maxP = math.min(minP, S["n.power"]), math.max(maxP, S["n.power"])
	end)
	line(plant, "10 minutes later")
	for _, l in logSince(plant, mark) do
		print("      | " .. l)
	end
	H.near(minP, 96, 101, "power never sags (min %)")
	H.near(maxP, 99, 103, "power never overshoots (max %)")
	H.near(S["plant.gross"], 780, 820, "gross generation at full power (MWe)")
	H.near(S["pri.press"], 6.8, 7.0, "pressure (MPa)")
	H.near(S["loop.1.level"], -80, 80, "drum level A (mm)")
	H.check(S["az5.active"] == 0 and S["core.ruptured"] == 0, "no trips, no damage")
	H.near(S["core.tilt"], 0, 12, "local regulators hold the power shape (tilt %)")
end)

case("pumptrip", function()
	local plant = fresh(1)
	local S = plant.S
	local mark = #plant.logLines
	plant.primary:stopPump(plant.primary.pumps[1][2], "tripped: test")
	run(plant, 90)
	line(plant, "90 s after MCP trip")
	for _, l in logSince(plant, mark) do
		print("      | " .. l)
	end
	H.check(S["az1.active"] == 1, "AZ-1 runback on loss of one main circulation pump")
	H.near(S["n.power"], 50, 63, "power run back to about 60% (%)")
	H.check(S["az5.active"] == 0, "no scram")
	plant:command("mcp.14.sw", 1)
	run(plant, 60)
	H.check(S["loop.1.running"] == 3, "standby pump restores three-pump operation")
	H.check(S["core.ruptured"] == 0, "no damage")
end)

case("feedloss", function()
	local plant = fresh(1)
	local S = plant.S
	local mark = #plant.logLines
	for i = 1, 4 do
		plant:command("fw.pump." .. i, 0)
	end
	local scramAt: number? = nil
	run(plant, 240, function(t)
		if not scramAt and S["az5.active"] == 1 then
			scramAt = t
		end
	end)
	line(plant, "4 min after feed loss")
	for _, l in logSince(plant, mark) do
		print("      | " .. l)
	end
	H.check(scramAt ~= nil, string.format("reactor scrams on loss of feedwater (after %.0f s)", scramAt or -1))
	H.check((scramAt or 0) > 3, "the loss of subcooling takes a few seconds to reach the core")
	H.check(S["afw.pump.1.run"] == 1, "emergency feed pumps start on low level")
	H.check(S["core.ruptured"] == 0 and S["core.destroyed"] == 0, "no damage")
	H.check(math.min(S["loop.1.levelWide"], S["loop.2.levelWide"]) > -1300, "drum level recovers before the pumps lose suction")
end)

case("blockage", function()
	local plant = fresh(1)
	local S = plant.S
	local core = plant.core
	-- Starve one of the hottest channels.
	local hot, hp = 0, 0
	for f = 1, core.NF do
		if core.power[f] > hp then
			hot, hp = f, core.power[f]
		end
	end
	local mark = #plant.logLines
	core.valve[hot] *= 0.12
	plant.failures.blocked[hot] = core.valve[hot] / 0.12
	local ruptureAt: number? = nil
	run(plant, 300, function(t)
		if not ruptureAt and S["core.ruptured"] > 0 then
			ruptureAt = t
		end
	end)
	line(plant, "5 min after blockage")
	for _, l in logSince(plant, mark) do
		print("      | " .. l)
	end
	print(string.format("    channel %.2f MW, clad %.0f C, reactor space %.1f kPa", hp / 1e6, core.cladT[hot], S["rs.press"]))
	H.check(ruptureAt ~= nil, string.format("a starved channel at full power bursts (after %.0f s)", ruptureAt or -1))
	H.check(S["az5.active"] == 1, "reactor space pressure scrams the reactor")
	H.check(S["core.destroyed"] == 0, "one burst channel does not wreck the unit")
	H.check(S["core.ruptured"] <= 2, "the damage stays local")
end)

case("turbinetrip", function()
	local plant = fresh(1)
	local S = plant.S
	local mark = #plant.logLines
	plant:command("tg.1.trip", 1)
	run(plant, 120)
	line(plant, "2 min after TG-1 trip")
	for _, l in logSince(plant, mark) do
		print("      | " .. l)
	end
	H.check(S["az2.active"] == 1, "AZ-2 runback when one turbine trips")
	H.near(S["n.power"], 40, 53, "power run back to about 50% (%)")
	H.check(S["az5.active"] == 0, "no scram")
	H.check(S["gen.1.gcb"] == 0, "generator 1 breaker opened on reverse power")
	H.near(S["pri.press"], 6.5, 7.4, "bypass keeps pressure in hand (MPa)")
end)

case("scram", function()
	local plant = fresh(1)
	local S = plant.S
	local mark = #plant.logLines
	plant:command("az5.button", 1)
	local peak = 0
	run(plant, 30, function()
		peak = math.max(peak, S["n.power"])
	end)
	line(plant, "30 s after AZ-5")
	run(plant, 570)
	line(plant, "10 min after AZ-5")
	for _, l in logSince(plant, mark) do
		print("      | " .. l)
	end
	-- The pre-1986 scram does almost nothing for its first three seconds;
	-- at the design point that shows as a small bump, not an excursion.
	H.near(peak, 99, 106, "power barely moves in the scram's dead first seconds (peak %)")
	H.check(S["rod.allIn"] == 1 and S["n.power"] < 1, "reactor shut down")
	H.near(S["pri.press"], 5.0, 7.4, "pressure held after the scram (MPa)")
	H.near(math.abs(S["pri.heatup"]), 0, 10, "cooldown rate inside the limit (C/min)")
	H.check(S["core.ruptured"] == 0, "no damage")
end)

-- The accident this reactor is known for, compressed. The unit is brought
-- to low power deep in a xenon pit, so nearly every rod has to come out to
-- keep it critical; protections are bypassed; feedwater is cut back and all
-- eight pumps run, leaving the core on the edge of boiling; then the
-- turbine is tripped for a rundown test and AZ-5 is pressed.
case("accident", function()
	local plant = fresh(1)
	local S = plant.S
	local core, rods = plant.core, plant.rods
	local L = core.layout
	for _, key in { "turbines", "level", "press", "feed", "mcp", "period" } do
		plant:command("prot.bypass." .. key, 1)
	end
	plant:command("eccs.auto", 0)
	plant:command("rod.blockBypass", 1)
	plant:command("lar.sw", 0)
	plant:command("ar.mode", 0)

	-- The operator chases the falling power by pulling rods wherever the
	-- flux is lowest (manual rods, then the idle regulators' rods and the
	-- short bottom rods), exactly as on the night.
	local function pull(count: number): number
		local cand = {}
		for i = 1, core.NR do
			local kind = rods.kind[i]
			local idle = kind ~= "AZ" and not rods:isAuto(i)
			if idle and core.rodPos[i] > 0.05 and not rods.stuck[i] then
				local sum, n = 0, 0
				for _, c in core.rodNeighbors[i] do
					sum += core.fluxRel[L.cellRef[c]]
					n += 1
				end
				table.insert(cand, { i = i, p = if n > 0 then sum / n else 0 })
			end
		end
		table.sort(cand, function(a, b)
			return a.p < b.p
		end)
		plant:command("rod.clear", 1)
		for k = 1, math.min(count, #cand) do
			plant:command("rod.select", cand[k].i)
		end
		for _ = 1, 170 do
			plant:hold("rod.move", -1)
			plant:step(DT)
		end
		plant:hold("rod.move", 0)
		plant:command("rod.clear", 1)
		return #cand
	end
	-- Xenon keeps building (time passing in the pit) for as long as the
	-- operator can keep up, until almost nothing is left in the core.
	local function poison(factor: number)
		for n = 1, core.N do
			core.xe[n] *= factor
		end
	end
	-- Power falls as the xenon builds; the regulator is switched back in
	-- at 200 MW with its setpoint matched.
	local guard = 0
	while S["n.power"] > 8.2 and guard < 400 do
		guard += 1
		poison(1.012)
		run(plant, 2)
	end
	rods.setpoint = S["n.power"] / 100
	plant:command("ar.mode", 1)
	line(plant, "regulator in at low power")
	guard = 0
	while guard < 500 and not core.destroyed and S["az5.active"] == 0 do
		guard += 1
		run(plant, 5)
		local power, ar = S["n.power"], S["ar.pos1"]
		local target = rods.setpoint * 100
		if S["rod.azOut"] == 0 then
			-- Re-cock the shutdown rods before anything else may be withdrawn.
			plant:command("rod.group", 1)
			for _ = 1, 170 do
				plant:hold("rod.move", -1)
				plant:step(DT)
			end
			plant:hold("rod.move", 0)
			plant:command("rod.clear", 1)
		elseif power < target * 0.93 and ar < 1.5 then
			if pull(8) == 0 then
				break
			end
		elseif power > target * 1.1 or ar > 4.5 then
			poison(1.02)
		elseif S["core.orm"] > 7.5 then
			poison(1.008)
		else
			break
		end
		if guard % 25 == 0 then
			line(plant, string.format("  xenon %.2f%%", S["core.xenon"]))
		end
	end
	line(plant, "low power, poisoned")
	-- Feedwater nearly off, fourth pump on in each loop.
	plant:command("lvl.1.auto", 0)
	plant:command("lvl.2.auto", 0)
	plant.secondary.level[1].valve = 0.06
	plant.secondary.level[2].valve = 0.06
	plant:command("mcp.14.sw", 1)
	plant:command("mcp.24.sw", 1)
	guard = 0
	while guard < 30 do
		guard += 1
		run(plant, 10)
		local target = rods.setpoint * 100
		if S["n.power"] < target * 0.93 and S["ar.pos1"] < 1.5 then
			if pull(8) == 0 then
				break
			end
		elseif S["n.power"] > target * 1.1 or S["ar.pos1"] > 4.5 then
			poison(1.02)
		end
	end
	line(plant, "before the test")
	print(string.format("    margin %.1f rods, void effect %+.2f beta, axial offset %+.0f%%, subcooling %.1f C, xenon %.2f%%, scram state az5=%d",
		S["core.orm"], S["core.void"], S["core.offset"], S["loop.1.subcool"], S["core.xenon"], S["az5.active"]))
	H.check(S["core.orm"] < 15, string.format("the unit is being run far below the 15-rod limit (ORM %.1f)", S["core.orm"]))
	H.check(S["az5.active"] == 0 and not core.destroyed, "still running, with the protections bypassed")

	-- The rundown test: steam to the turbine shut off, four pumps coasting down.
	local mark = #plant.logLines
	plant:command("tg.1.trip", 1)
	plant:command("tg.2.trip", 1)
	for l = 1, 2 do
		plant:command(string.format("mcp.%d3.sw", l), 0)
		plant:command(string.format("mcp.%d4.sw", l), 0)
	end
	run(plant, 36, function(t)
		if math.abs(t % 6) < 0.05 then
			print(string.format("      rundown t=%2.0f s  P=%6.2f%%  rho=%+.2f b  flow=%5.0f t/h  AR=%.2f m  period=%4.0f s", t, S["n.power"], S["n.rho"], S["pri.flow"], S["ar.pos1"], S["n.period"]))
		end
	end)
	local atButton = S["n.power"]
	line(plant, "36 s into the rundown")
	plant:command("az5.button", 1)
	local peak, peakAt = atButton, 0
	run(plant, 20, function(t)
		if S["n.power"] > peak then
			peak, peakAt = S["n.power"], t
		end
		if t <= 8.05 and math.abs(t * 2 - math.floor(t * 2 + 0.5)) < 0.01 then
			print(string.format("      AZ-5 +%.1f s  P=%9.2f%%  rho=%+.2f b  offset=%+3.0f%%  fuel max %4.0f C  ruptured %d", t, S["n.power"], S["n.rho"], S["core.offset"], S["core.maxFuel"], S["core.ruptured"]))
		end
	end)
	for _, l in logSince(plant, mark) do
		if not string.find(l, "RUPTURED") then
			print("      | " .. l)
		end
	end
	print(string.format("    AZ-5 pressed at %.1f%% power; peak %.0f%% of nominal %.1f s later; %d channels burst; reactor %s",
		atButton, peak, peakAt, S["core.ruptured"], if core.destroyed then "DESTROYED" else "survived"))
	H.check(peak > atButton * 2, "pressing AZ-5 in this state drives the power up, not down")
	H.check(S["rod.allIn"] == 1 or core.destroyed, "it ends with the rods in or the reactor gone")
end)

-- The end state itself: a prompt-critical excursion must wreck the core,
-- and the wrecked plant must keep stepping sanely until it is replaced.
case("runaway", function()
	local plant = fresh(1)
	local S = plant.S
	local core = plant.core
	local mark = #plant.logLines
	core:shiftK(0.012) -- a reactivity step of well over one beta
	local peak = 0
	run(plant, 20, function()
		peak = math.max(peak, S["n.power"])
	end)
	local shown = 0
	for _, l in logSince(plant, mark) do
		if not string.find(l, "RUPTURED") and not string.find(l, "ALARM") and shown < 8 then
			shown += 1
			print("      | " .. l)
		end
	end
	print(string.format("    peak %.0f%% of nominal, %d channels burst, reactor space %.0f kPa", peak, S["core.ruptured"], S["rs.press"]))
	H.check(peak > 1000, "prompt-critical excursion")
	H.check(core.destroyed, "the reactor is destroyed")
	H.check(S["core.destroyed"] == 1 and S["rod.stuck"] > 100, "the control room shows it: rods jammed, core lost")
	run(plant, 120)
	local bad = 0
	for _, v in S do
		if v ~= v or v == math.huge or v == -math.huge then
			bad += 1
		end
	end
	H.check(bad == 0, "the wrecked plant keeps running without numerical trouble")
	H.check(S["n.power"] < 5, "what is left is subcritical")
end)

for _, c in cases do
	if not only or only == c.name then
		print("== " .. c.name)
		local t0 = os.clock()
		c.fn()
		print(string.format("   (%.0f s)", os.clock() - t0))
	end
end
H.finish()
