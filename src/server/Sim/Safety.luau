--!nonstrict
-- Reactor auxiliaries and safety systems: the rod-channel (CPS) cooling
-- circuit, the reactor space around the graphite stack, emergency core
-- cooling, the suppression pool and the activity monitors.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Safety = {}
Safety.__index = Safety

local LID_LIFT = 180 -- kPa gauge in the reactor space that lifts the upper plate
local RELIEF = 45 -- kg/s the relief pipes pass at 100 kPa

function Safety.new(plant)
	local self = setmetatable({}, Safety)
	self.plant = plant
	-- Rod channel cooling.
	self.cpsPumps = {
		{ name = "CPS-1", bus = "E1", on = true, failed = false, repair = 0 },
		{ name = "CPS-2", bus = "E2", on = false, failed = false, repair = 0 },
	}
	self.cpsFlow = 1
	self.cpsTank = 1 -- header tank level, 0..1
	self.cpsLeak = 0 -- fraction per second, set by faults
	self.cpsMakeup = false
	self.cpsTemp = 45
	self.cpsNoFlow = 0
	-- Reactor space.
	self.rsPress = 0
	self.activity = 1
	-- Emergency core cooling.
	self.eccsAuto = true
	self.eccsActive = false
	self.eccsAccum = 1.6e5 -- kg in the accumulators
	self.eccsPumps = {
		{ name = "ECCS-1", bus = "E1", on = false, manual = false, failed = false, repair = 0 },
		{ name = "ECCS-2", bus = "E2", on = false, manual = false, failed = false, repair = 0 },
		{ name = "ECCS-3", bus = "E3", on = false, manual = false, failed = false, repair = 0 },
	}
	self.eccsFlow = 0
	self.poolTemp = 30
	self.compartmentLeak = false

	local c = plant.cmd
	for i, pump in self.cpsPumps do
		c["cps.pump." .. i] = function(v)
			local on = v >= 0.5
			if on and not pump.on then
				if pump.failed or not plant:busLive(pump.bus) then
					plant:log(pump.name .. " will not start")
					return
				end
				pump.on = true
				plant:log(pump.name .. " started")
			elseif not on and pump.on then
				pump.on = false
				plant:log(pump.name .. " stopped")
			end
		end
	end
	c["cps.makeup"] = function(v)
		self.cpsMakeup = v >= 0.5
	end
	c["eccs.auto"] = function(v)
		local on = v >= 0.5
		if on ~= self.eccsAuto then
			self.eccsAuto = on
			plant:log(if on then "ECCS automatic actuation armed" else "ECCS AUTOMATIC ACTUATION DISABLED")
		end
	end
	c["eccs.manual"] = function()
		self:actuate("manual")
	end
	c["eccs.reset"] = function()
		if self.eccsActive then
			self.eccsActive = false
			plant:log("ECCS reset")
		end
	end
	for i, pump in self.eccsPumps do
		c["eccs.pump." .. i] = function(v)
			pump.manual = v >= 0.5
		end
	end
	return self
end

function Safety.actuate(self, why: string)
	if not self.eccsActive then
		self.eccsActive = true
		self.plant:log("ECCS ACTUATED: " .. why)
		self.plant:raise("eccs")
	end
end

function Safety.step(self, dt: number)
	local plant = self.plant
	local core = plant.core
	local pri = plant.primary
	local elec = plant.elec
	local power = core.thermalPower / Config.NOMINAL_THERMAL

	-- Rod channel cooling circuit.
	local flowing = false
	for _, pump in self.cpsPumps do
		if pump.on and not plant:busLive(pump.bus) then
			pump.on = false
			plant:log(pump.name .. " tripped: bus undervoltage")
		end
		if pump.repair > 0 then
			pump.repair -= dt
			if pump.repair <= 0 then
				pump.failed = false
			end
		end
		if pump.on then
			flowing = true
			elec:addLoad(pump.bus, 0.4e6)
		end
	end
	self.cpsFlow = Util.lag(self.cpsFlow, if flowing and self.cpsTank > 0.15 then 1 else 0, dt, 3)
	self.cpsTank = Util.clamp(self.cpsTank - self.cpsLeak * dt + (if self.cpsMakeup then 0.004 * dt else 0), 0, 1)
	-- With no flow the water in the rod channels heats up and boils away.
	if self.cpsFlow > 0.5 then
		self.cpsTemp = Util.lag(self.cpsTemp, 45 + 25 * power, dt, 20)
		self.cpsNoFlow = 0
	else
		self.cpsTemp = math.min(self.cpsTemp + (0.02 + 1.5 * power) * dt, 400)
		self.cpsNoFlow += dt
	end
	local water = Util.clamp(self.cpsTank / 0.5, 0, 1)
	if self.cpsTemp > 105 then
		water = math.min(water, Util.clamp(1 - (self.cpsTemp - 105) / 120, 0, 1))
	end
	core:setCpsWater(water)
	-- Dry, hot guide tubes distort and seize the rods in them.
	if self.cpsTemp > 250 and plant.rng:next() < 0.02 * dt then
		local i = plant.rng:int(1, core.NR)
		if not plant.rods.stuck[i] then
			plant.rods:jam(i)
			plant:log(string.format("Rod %s seized: guide tube overheated", plant.rods.label[i]))
		end
	end

	-- Reactor space: steam from burst tubes against the relief pipes.
	local inflow = core.loopLeak[1] + core.loopLeak[2]
	local equilibrium = math.min(600, 100 * (inflow / RELIEF) ^ 2)
	self.rsPress = Util.lag(self.rsPress, equilibrium, dt, 2.5)
	if self.rsPress > LID_LIFT and not core.destroyed then
		core:destroy("reactor space overpressure lifted the upper plate")
	end
	local activity = 1 + 40 * core.nFuelDamaged + 6 * core.nRuptured + (if core.maxCladTemp > Config.Core.CLAD_FAIL then 200 else 0)
	if core.destroyed then
		activity = 1e5
	end
	self.activity = Util.lag(self.activity, activity, dt, 10)

	-- Emergency core cooling.
	local low = math.min(pri.loops[1].level, pri.loops[2].level)
	if self.eccsAuto and not self.eccsActive then
		if low < -1000 then
			self:actuate("drum level low-low")
		elseif (self.rsPress > 20 or self.compartmentLeak) and low < -600 then
			self:actuate("loss of coolant")
		end
	end
	local flow = 0
	if self.eccsActive and self.eccsAccum > 0 and pri.pressure < 9 then
		local q = math.min(300, self.eccsAccum / dt)
		self.eccsAccum -= q * dt
		flow += q
	end
	for _, pump in self.eccsPumps do
		local want = pump.manual or self.eccsActive
		if want and not pump.on and not pump.failed and plant:busLive(pump.bus) then
			pump.on = true
			plant:log(pump.name .. " started")
		elseif pump.on and (not want or not plant:busLive(pump.bus)) then
			pump.on = false
		end
		if pump.on then
			elec:addLoad(pump.bus, 1.4e6)
			if pri.pressure < 8.5 then
				flow += 110
			end
		end
	end
	self.eccsFlow = flow
	-- Inject into whichever loop is lower.
	local a, b = pri.loops[1], pri.loops[2]
	if a.level < b.level - 100 then
		a.eccs, b.eccs = flow * 0.7, flow * 0.3
	elseif b.level < a.level - 100 then
		a.eccs, b.eccs = flow * 0.3, flow * 0.7
	else
		a.eccs, b.eccs = flow * 0.5, flow * 0.5
	end

	-- Suppression pool soaks up safety valve discharge.
	self.poolTemp += plant.secondary.poolHeat / (3.0e6 * 4200) * dt
	self.poolTemp += (30 - self.poolTemp) * dt / 20000
end

function Safety.publish(self, S)
	for i, pump in self.cpsPumps do
		S["cps.pump." .. i .. ".run"] = if pump.on then 1 else 0
	end
	S["cps.flow"] = self.cpsFlow * 100
	S["cps.tank"] = self.cpsTank * 100
	S["cps.temp"] = self.cpsTemp
	S["cps.makeup"] = if self.cpsMakeup then 1 else 0
	S["rs.press"] = self.rsPress
	S["rad.gas"] = self.activity
	S["eccs.auto"] = if self.eccsAuto then 1 else 0
	S["eccs.active"] = if self.eccsActive then 1 else 0
	S["eccs.accum"] = self.eccsAccum / 1.6e5 * 100
	S["eccs.flow"] = self.eccsFlow * 3.6
	for i, pump in self.eccsPumps do
		S["eccs.pump." .. i .. ".run"] = if pump.on then 1 else 0
		S["eccs.pump." .. i .. ".sw"] = if pump.manual then 1 else 0
	end
	S["pool.temp"] = self.poolTemp
end

return Safety
