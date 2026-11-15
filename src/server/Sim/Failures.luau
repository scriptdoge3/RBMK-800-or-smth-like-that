--!strict
-- Random equipment failures, wear and aging, and the maintenance that puts
-- things right once the unit is cold.
--
-- Failures arrive at random while the unit is operating, roughly one every
-- half hour, more often on a unit that has been treated roughly. Wear comes
-- from how the plant is run: heating or cooling the circuit faster than the
-- limit weakens every pressure tube, cavitating a pump shortens its life,
-- and loading a cold turbine damages it.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Failures = {}
Failures.__index = Failures

function Failures.new(plant)
	local self = setmetatable({}, Failures)
	self.plant = plant
	self.enabled = true
	self.clock = 0
	self.nextEvent = plant.rng:range(700, 1600)
	self.lastStress = 0
	self.timers = {} -- { remaining, onExpire }
	self.blocked = {} -- fuel channel indices with a restricted inlet
	self.coldTime = 0
	self.count = 0
	return self
end

local function after(self, seconds: number, fn: () -> ())
	table.insert(self.timers, { remaining = seconds, fn = fn })
end

local function runningPump(rng, pumps): any
	local list = {}
	for _, p in pumps do
		if p.on and not p.failed then
			table.insert(list, p)
		end
	end
	if #list == 0 then
		return nil
	end
	return list[rng:int(1, #list)]
end

local function failPump(self, pump, alarm: string, minutes: number)
	pump.on = false
	pump.failed = true
	pump.repair = minutes * 60
	self.plant:log(pump.name .. " tripped: equipment fault (repair about " .. minutes .. " min)")
	self.plant:raise(alarm)
end

-- Each entry: weight and a function that returns true if it did something.
local function eventTable(self)
	local plant = self.plant
	local rng = plant.rng
	local core, pri, sec, elec, rods, safety = plant.core, plant.primary, plant.secondary, plant.elec, plant.rods, plant.safety
	return {
		{ 12, function()
			local l = rng:int(1, 2)
			local pump = runningPump(rng, pri.pumps[l])
			if not pump then return false end
			failPump(self, pump, "mcp.trip", rng:int(4, 8))
			return true
		end },
		{ 10, function()
			local pump = runningPump(rng, sec.feedPumps)
			if not pump then return false end
			failPump(self, pump, "fw.pump", rng:int(3, 6))
			return true
		end },
		{ 6, function()
			local pump = runningPump(rng, sec.condPumps)
			if not pump then return false end
			failPump(self, pump, "cond.pump", rng:int(3, 6))
			return true
		end },
		{ 8, function()
			local list = rods.byKind.RR
			local i = list[rng:int(1, #list)]
			if rods.stuck[i] then return false end
			rods:jam(i)
			plant:log(string.format("Rod %s drive fault: rod will not move", rods.label[i]))
			after(self, rng:range(360, 720), function()
				if not core.destroyed then
					rods.stuck[i] = false
					plant:log(string.format("Rod %s drive repaired", rods.label[i]))
				end
			end)
			return true
		end },
		{ 7, function()
			if rods.arMode == 0 then return false end
			plant:log(string.format("Automatic regulator AR-%d fault: regulator tripped out", rods.arMode))
			rods.arMode = 0
			return true
		end },
		{ 5, function()
			if not rods.larOn then return false end
			rods.larOn = false
			plant:log("Local automatic regulators fault: dropped out")
			plant:raise("lar.dropout")
			return true
		end },
		{ 8, function()
			if core.thermalPower < 0.2 * Config.NOMINAL_THERMAL then return false end
			local f = rng:int(1, core.NF)
			if core.status[f] ~= 0 or self.blocked[f] then return false end
			self.blocked[f] = core.valve[f]
			core.valve[f] *= 0.32
			local c = core.fuelCell[f]
			plant:log(string.format("Channel %02d-%02d: coolant flow dropping (inlet valve fault)", core.layout.cellGX[c], core.layout.cellGY[c]))
			return true
		end },
		{ 7, function()
			local k = rng:int(1, 2)
			local t = sec.turbines[k]
			if t.airLeak > 1 or t.vacBreaker then return false end
			t.airLeak = 5
			plant:log(string.format("Condenser %d: air in-leakage increasing", k))
			after(self, rng:range(300, 600), function()
				t.airLeak = 1
				plant:log(string.format("Condenser %d: air leak sealed", k))
			end)
			return true
		end },
		{ 5, function()
			local names = { "E1", "E2", "E3" }
			local b = elec.ebus[names[rng:int(1, 3)]]
			if b.dgWillFail or b.dgState ~= 0 then return false end
			b.dgWillFail = true -- latent: shows up the next time it is called on
			return true
		end },
		{ 4, function()
			local v = sec.safety[rng:int(1, 3)]
			if v.stuck then return false end
			v.stuck = true -- latent: fails to reseat after it next lifts
			return true
		end },
		{ 7, function()
			local l = rng:int(1, 2)
			local loop = pri.loops[l]
			if loop.levelBias ~= 0 then return false end
			loop.levelBias = (if rng:next() < 0.5 then -1 else 1) * rng:range(120, 260)
			plant:log(string.format("Drum %s narrow-range level transmitter drifting", if l == 1 then "A" else "B"))
			after(self, rng:range(400, 700), function()
				loop.levelBias = 0
				plant:log(string.format("Drum %s level transmitter recalibrated", if l == 1 then "A" else "B"))
			end)
			return true
		end },
		{ 5, function()
			if safety.cpsLeak > 0 then return false end
			safety.cpsLeak = 0.0015
			plant:log("Rod cooling circuit: leak, header tank level falling")
			after(self, rng:range(480, 720), function()
				safety.cpsLeak = 0
				plant:log("Rod cooling circuit: leak isolated")
			end)
			return true
		end },
		{ 2, function()
			if not elec.grid.live then return false end
			elec.grid.live = false
			elec.gens[1].yard = false
			elec.gens[2].yard = false
			plant:log("LOSS OF OFFSITE POWER: switchyard breakers open")
			after(self, rng:range(40, 100), function()
				elec.grid.live = true
				plant:log("Offsite power restored: reclose the switchyard breakers")
			end)
			return true
		end },
		{ 6, function()
			local f = rng:int(1, core.NF)
			core.wear[f] = math.min(1, core.wear[f] + 0.2) -- latent tube weakening
			return true
		end },
		{ 5, function()
			local k = rng:int(1, 2)
			local t = sec.turbines[k]
			if t.speed < 0.5 then return false end
			t.wear += 0.12
			plant:log(string.format("Turbine %d: vibration step change", k))
			return true
		end },
		{ 5, function()
			local l = rng:int(1, 2)
			local lc = sec.level[l]
			if lc.stuck > 0 then return false end
			lc.stuck = rng:range(120, 240)
			plant:log(string.format("Feedwater control valve %s not responding", if l == 1 then "A" else "B"))
			return true
		end },
	}
end

function Failures.trigger(self)
	local events = eventTable(self)
	local total = 0
	for _, e in events do
		total += e[1]
	end
	for _ = 1, 12 do
		local pick = self.plant.rng:next() * total
		for _, e in events do
			pick -= e[1]
			if pick <= 0 then
				if e[2]() then
					self.count += 1
					return
				end
				break
			end
		end
	end
end

-- With the unit cold and shut down the maintenance crews can work.
function Failures.maintenance(self)
	local plant = self.plant
	local core = plant.core
	local replaced, cleared, freed = 0, 0, 0
	for f = 1, core.NF do
		if core.status[f] ~= 0 then
			core.status[f] = 0
			core.leak[f] = 0
			core.wear[f] = 0.05
			replaced += 1
		end
	end
	core.nRuptured = 0
	core.nFuelDamaged = 0
	for f, original in self.blocked do
		core.valve[f] = original
		cleared += 1
	end
	self.blocked = {}
	for i = 1, core.NR do
		if plant.rods.stuck[i] then
			plant.rods.stuck[i] = false
			freed += 1
		end
	end
	if replaced + cleared + freed > 0 then
		plant:log(string.format("Maintenance: %d channels retubed, %d inlet valves cleared, %d rod drives freed", replaced, cleared, freed))
	end
end

function Failures.step(self, dt: number)
	local plant = self.plant
	local core, pri = plant.core, plant.primary

	-- Thermal shock spreads onto every pressure tube.
	local ds = pri.stress - self.lastStress
	if ds > 0.002 then
		self.lastStress = pri.stress
		local add = ds * 0.12
		for f = 1, core.NF do
			local w = core.wear[f] + add
			core.wear[f] = if w > 1 then 1 else w
		end
	end

	for i = #self.timers, 1, -1 do
		local t = self.timers[i]
		t.remaining -= dt
		if t.remaining <= 0 then
			table.remove(self.timers, i)
			t.fn()
		end
	end

	local operating = core.thermalPower > 0.01 * Config.NOMINAL_THERMAL or pri.pressure > 1
	if operating and self.enabled and not core.destroyed then
		-- A battered plant breaks more often.
		local abuse = 1 + Util.clamp(pri.stress * 2, 0, 3)
		self.clock += dt * abuse
		if self.clock >= self.nextEvent then
			self.clock = 0
			self.nextEvent = plant.rng:range(900, 2400)
			self:trigger()
		end
	end

	if not core.destroyed and core.thermalPower < 0.002 * Config.NOMINAL_THERMAL and pri.temp < 80 and plant.rods.allIn then
		self.coldTime += dt
		if self.coldTime > 180 then
			self.coldTime = 0
			self:maintenance()
		end
	else
		self.coldTime = 0
	end
end

function Failures.blockedCount(self): number
	local n = 0
	for _ in self.blocked do
		n += 1
	end
	return n
end

return Failures
