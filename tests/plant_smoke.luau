-- Build the whole plant and let it sit in cold shutdown.
local H = require("./harness")
local Plant = H.require(H.server.Sim.Plant)
local AlarmList = H.require(H.shared.AlarmList)

local t0 = os.clock()
local plant = Plant.new({ seed = 3, age = 1, hoursSinceShutdown = 80, failures = false })
print(string.format("plant built in %.1f s", os.clock() - t0))
for _, line in plant.logLines do
	print("  log: " .. line.text)
end
local t1 = os.clock()
for _ = 1, 600 do
	plant:step(0.1)
end
print(string.format("60 s of plant time in %.2f s wall (%.2f ms per step)", os.clock() - t1, (os.clock() - t1) / 600 * 1000))
local S = plant.S
local bad = 0
local count = 0
for name, v in S do
	count += 1
	if v ~= v or v == math.huge or v == -math.huge then
		bad += 1
		print("  bad signal", name, v)
	end
end
print(count .. " signals")
H.check(bad == 0, "no NaN or infinite signals")
print(string.format("power %.3e %%  cps %.1f  keff %.4f  rho %.1f beta  T %.1f C  P %.3f MPa  levels %.0f / %.0f mm",
	S["n.power"], S["n.cps"], plant.core.keff, S["n.rho"], S["pri.temp"], S["pri.press"], S["loop.1.level"], S["loop.2.level"]))
print(string.format("decay heat %.2f MW  xenon %.2f%%  ORM %.1f  loop flow %.0f t/h (natural circulation)", S["n.thermal"], S["core.xenon"], S["core.orm"], S["loop.1.flow"]))
H.near(plant.core.keff, 0.90, 0.97, "cold shutdown keff with all rods in")
H.near(S["pri.temp"], 30, 80, "cold shutdown temperature holds")
local missing = plant.alarms:unhandled({ "mcp.trip", "fw.pump", "cond.pump", "tg.1.trip", "tg.2.trip", "gen.1.fault", "gen.2.fault", "dg.fail", "bus.reserve", "lar.dropout" })
H.check(#missing == 0, "every annunciator has a condition (" .. table.concat(missing, ", ") .. ")")
local lit = {}
for i, a in AlarmList.list do
	if plant.alarms.state[i] ~= 0 then
		table.insert(lit, a.id)
	end
end
print("alarms standing in cold shutdown: " .. table.concat(lit, ", "))
local active = {}
for id, on in plant.protection.active do
	if on then table.insert(active, id) end
end
print("protection signals present: " .. table.concat(active, ", "))
local buf = plant:mapBuffer()
H.check(buffer.len(buf) == 1 + plant.core.NC * 2 + plant.core.NR, "map buffer size")
-- Annunciator ringback sequence (ISA S18.1): new, acknowledged, cleared
-- awaiting reset, reset.
do
	local index = AlarmList.index["mcp.trip"]
	plant:raise("mcp.trip")
	plant:step(0.1)
	H.check(plant.alarms.state[index] == 1, "a new alarm flashes")
	plant:command("ann.ack", 1)
	H.check(plant.alarms.state[index] == 2, "acknowledged while the condition stands: steady")
	for _ = 1, 80 do
		plant:step(0.1)
	end
	H.check(plant.alarms.state[index] == 3, "condition gone: ringback until reset")
	plant:command("ann.reset", 1)
	H.check(plant.alarms.state[index] == 0, "reset puts the window out")
end
H.finish()
