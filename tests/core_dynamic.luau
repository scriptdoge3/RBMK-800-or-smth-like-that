-- Free-running core with fixed loop conditions and no control action.
local H = require("./harness")
local Config = H.require(H.shared.Config)
local Steam = H.require(H.shared.Steam)
local Core = H.require(H.server.Sim.Core)

local hf = Steam.hf(6.9)
local sub = 645 / 4165 * (hf - Steam.hLiquid(165))
local cond = { pressure = { 6.9, 6.9 }, inletEnthalpy = { hf - sub, hf - sub }, flow = { 4165, 4165 } }
local core = Core.new({ seed = 7, age = 1 })
core:design(cond)

local function run(seconds, every, label)
	local t = 0
	local nextPrint = 0
	local clock = os.clock()
	while t < seconds do
		if t >= nextPrint then
			local avg = core.thermalPower / core.NF
			print(string.format("%s t=%4ds  P=%7.1f MW  rho=%+.3fb  period=%7.1f  Kr=%.2f  axTop=%.2f axBot=%.2f  Tf=%.0f Tg=%.0f  zoneMax=%.3f zoneMin=%.3f",
				label, t, core.thermalPower / 1e6, core.rho / core.beta, math.clamp(core.period, -9999, 9999), core.maxChannelPower / avg,
				core.axial[3], core.axial[12], core.avgFuelTemp, core.avgGraphiteTemp,
				math.max(table.unpack(core.zonePower)) * 12, math.min(table.unpack(core.zonePower)) * 12))
			nextPrint += every
		end
		core:step(0.1, cond)
		t += 0.1
		if core.destroyed then
			print("CORE DESTROYED at t=" .. t)
			break
		end
	end
	print(string.format("  (%.1f s wall for %d s sim)", os.clock() - clock, seconds))
end

print("=== full power, hands off")
run(900, 100, "100%")
H.near(core.thermalPower / Config.NOMINAL_THERMAL, 0.7, 1.3, "full power stays within 30% for 15 min with no control")

print("=== step: one manual rod pulled 1 m at full power")
local target
for i, rod in core.layout.rods do
	if rod.kind == "RR" and core.rodPos[i] > 5 then
		target = i
		break
	end
end
core:setRodPosition(target, core.rodPos[target] - 1)
run(60, 10, "rod ")
H.finish()
