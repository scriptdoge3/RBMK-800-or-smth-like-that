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
	H.check(peak < 102, "no power rise on AZ-5 from the design state")
	H.check(S["rod.allIn"] == 1 and S["n.power"] < 1, "reactor shut down")
	H.near(S["pri.press"], 5.0, 7.4, "pressure held after the scram (MPa)")
	H.near(math.abs(S["pri.heatup"]), 0, 10, "cooldown rate inside the limit (C/min)")
	H.check(S["core.ruptured"] == 0, "no damage")
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
