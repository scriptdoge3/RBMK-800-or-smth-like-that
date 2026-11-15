-- Static checks of the core model: design-point criticality, power shape,
-- rod worth, void effect and the positive scram effect.
local H = require("./harness")
local Config = H.require(H.shared.Config)
local Steam = H.require(H.shared.Steam)
local Core = H.require(H.server.Sim.Core)

local function nominalCond()
	local hf = Steam.hf(6.9)
	local hfw = Steam.hLiquid(165)
	local sub = 645 / 4165 * (hf - hfw)
	return { pressure = { 6.9, 6.9 }, inletEnthalpy = { hf - sub, hf - sub }, flow = { 4165, 4165 } }
end

local function settle(core, n)
	return core:settle(n)
end

local function report(core, title)
	print("--- " .. title)
	print(string.format("keff %.5f  rho %.3f beta  ORM %.1f", core.keff, core.rho / core.beta, core.orm))
	local NF = core.NF
	local avg = core.thermalPower / NF
	local maxP, minP = 0, math.huge
	for f = 1, NF do
		maxP = math.max(maxP, core.power[f])
		minP = math.min(minP, core.power[f])
	end
	print(string.format("channel power avg %.2f MW  max %.2f  min %.2f  Kr %.2f", avg / 1e6, maxP / 1e6, minP / 1e6, maxP / avg))
	local ax = {}
	for z = 1, core.NZ do
		ax[z] = string.format("%.2f", core.axial[z])
	end
	print("axial (top->bottom): " .. table.concat(ax, " "))
	print(string.format("fuel T avg %.0f max %.0f  graphite avg %.0f  clad max %.0f", core.avgFuelTemp, core.maxFuelTemp, core.avgGraphiteTemp, core.maxCladTemp))
	print(string.format("exit quality %.3f %.3f  steam %.0f kg/s  min margin %.2f", core.loopExitQuality[1], core.loopExitQuality[2], core.loopSteam[1] + core.loopSteam[2], core.minMargin))
	print(string.format("void effect (100%%) %.2f beta   xenon %.2f%%", core.voidCoefCore / core.beta, core.xenonWorth * 100))
	-- radial profile by ring
	local rings, cnt = {}, {}
	for f = 1, NF do
		local c = core.fuelCell[f]
		local r = math.sqrt(core.layout.cellX[c] ^ 2 + core.layout.cellY[c] ^ 2)
		local b = math.floor(r / 3) + 1
		rings[b] = (rings[b] or 0) + core.power[f] / avg
		cnt[b] = (cnt[b] or 0) + 1
	end
	local out = {}
	for b = 1, #rings do
		out[b] = string.format("%.2f", rings[b] / cnt[b])
	end
	print("radial rings: " .. table.concat(out, " "))
end

local t0 = os.clock()
local core = Core.new({ seed = 7, age = 1 })
local cond = nominalCond()
core:design(cond)
report(core, "design point")
print(string.format("kOffset %.5f  ormScale %.2f  rod worth total %.2f%%  (%.2f s)", core.kOffset, core.ormScale, core.rodWorthTotal * 100, os.clock() - t0))
H.near(core.keff, 0.9995, 1.0005, "design keff")

-- Frozen-feedback reactivity experiments from the design point.
local saved = table.clone(core.rodPos)
local psiSaved = table.clone(core.psi)
local function restore()
	for i = 1, core.NR do
		core:setRodPosition(i, saved[i])
	end
	for n = 1, core.N do
		core.psi[n] = psiSaved[n]
	end
	core.keff = 1
end
local k0 = settle(core, 300)
psiSaved = table.clone(core.psi)

for i, rod in core.layout.rods do
	if rod.kind ~= "USP" then
		core:setRodPosition(i, 0)
	end
end
local kOut = settle(core, 600)
for i, rod in core.layout.rods do
	core:setRodPosition(i, if rod.kind == "USP" then 3.5 else 6.5)
end
local kIn = settle(core, 600)
print(string.format("hot: k0 %.5f  all out %.5f  all in %.5f  -> total worth %.2f%%  excess over design %.2f%%", k0, kOut, kIn, (kOut - kIn) * 100, (kOut - k0) * 100))
restore()

-- Positive scram: drive every top-entry rod in by steps and watch k with
-- only a few sweeps (the shape has no time to move in the first seconds).
print("--- scram from design point (rods move 0.4 m/s)")
for step = 1, 8 do
	for i, rod in core.layout.rods do
		if rod.kind ~= "USP" then
			core:setRodPosition(i, math.min(6.5, saved[i] + step * 0.4))
		end
	end
	local k = settle(core, 10)
	print(string.format("  t=%ds  dk %.3f beta", step, (k - k0) / core.beta))
end
restore()

-- Cold and hot-standby reactivity with no xenon.
local function uniformState(temp, pressure)
	local c = { pressure = { pressure, pressure }, inletEnthalpy = { Steam.hLiquid(temp), Steam.hLiquid(temp) }, flow = { 4165, 4165 } }
	for n = 1, core.N do
		core.tf[n] = temp
		core.tg[n] = temp
		core.xe[n] = 0
		core.pnode[n] = 0
	end
	core:distributeFlow(c)
	core:thermal(0, c, 1)
	return c
end
local function kWith(posTop, posUsp, sweeps)
	for i, rod in core.layout.rods do
		core:setRodPosition(i, if rod.kind == "USP" then posUsp else posTop)
	end
	return settle(core, sweeps or 500)
end
local xeSaved, tfSaved, tgSaved = table.clone(core.xe), table.clone(core.tf), table.clone(core.tg)
uniformState(40, 0.101)
local coldIn, coldOut = kWith(6.5, 3.5), kWith(0, 0)
print(string.format("cold 40C clean: all in %.4f  all out %.4f", coldIn, coldOut))
uniformState(284, 6.9)
local hotIn, hotOut = kWith(6.5, 3.5), kWith(0, 0)
print(string.format("hot 284C clean: all in %.4f  all out %.4f", hotIn, hotOut))
H.check(coldIn < 0.97, "cold shutdown margin with all rods in is more than 3%")

-- The dangerous state, reached the way the real one was: a long run at full
-- power, half a day at half power, then a slump to low power. Xenon piles
-- up in the middle of the core, so nearly every rod has to come out.
for n = 1, core.N do
	core.xe[n] = xeSaved[n]
	core.tf[n] = tfSaved[n]
	core.tg[n] = tgSaved[n]
end
core:setDesignPattern()
core:solveSteady(Config.NOMINAL_THERMAL, cond, { xenon = true, iterations = 20 })
local t1 = os.clock()
core:evolve(12, 0.5 * Config.NOMINAL_THERMAL, cond)
print(string.format("after 12 h at 50%%: xenon %.2f%%", core.xenonWorth * 100))
local hf = Steam.hf(6.5)
local low = { pressure = { 6.5, 6.5 }, inletEnthalpy = { hf - 12e3, hf - 12e3 }, flow = { 5500, 5500 } }
core:evolve(1.5, 200e6, low)
print(string.format("after 1.5 h at 200 MW: xenon %.2f%%  (history took %.1f s)", core.xenonWorth * 100, os.clock() - t1))
local function pattern(nIn)
	local rr = 0
	for i, rod in core.layout.rods do
		local x = 0
		if rod.kind == "RR" then
			rr += 1
			if rr % 5 == 0 and rr / 5 <= nIn then
				x = 6.5
			end
		elseif rod.kind == "AR" then
			x = 1.5
		end
		core:setRodPosition(i, x)
	end
end
pattern(0)
core:solveSteady(200e6, low, { xenon = false, iterations = 40 })
report(core, "poisoned 200 MW state, every manual rod out")
-- Nudge k to exactly critical; this stands in for picking the exact moment.
local shift = 1 - core.keff
print(string.format("  (k shifted by %+.2f%% to make it critical)", shift * 100))
core:shiftK(shift)
core:solveSteady(200e6, low, { xenon = false, iterations = 25 })
report(core, "poisoned 200 MW state, critical")
saved = table.clone(core.rodPos)
k0 = settle(core, 200)
psiSaved = table.clone(core.psi)
print("--- AZ-5 from the poisoned state")
local worst = -1
for step = 1, 12 do
	for i, rod in core.layout.rods do
		if rod.kind ~= "USP" then
			core:setRodPosition(i, math.min(6.5, saved[i] + step * 0.4))
		end
	end
	local k = settle(core, 10)
	local dk = (k - k0) / core.beta
	worst = math.max(worst, dk)
	print(string.format("  t=%ds  dk %+.3f beta", step, dk))
end
H.check(worst > 0.1, string.format("positive scram appears in the poisoned state (peak %+.2f beta)", worst))
H.finish()
