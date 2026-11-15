--!strict
-- Emergency protection logic. Five levels, as on the unit:
--
--   AZ-5  full shutdown: every top-entry rod driven in, latched
--   AZ-4  all rods inserted for as long as the signal lasts
--   AZ-3  runback to 20% power
--   AZ-2  runback to 50% power
--   AZ-1  runback to 60% power
--
-- Several trips can be bypassed from the control room with key switches,
-- exactly as the pre-1986 plant allowed.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local Config = require(Shared.Config)

local Protection = {}
Protection.__index = Protection

local Pr = Config.Protection

-- id, level, bypass key (or nil when the trip cannot be bypassed), description
Protection.SIGNALS = {
	{ id = "manual", level = 5, text = "Manual AZ-5" },
	{ id = "overpower", level = 5, text = "Neutron power high" },
	{ id = "period", level = 5, bypass = "period", text = "Reactor period short" },
	{ id = "press", level = 5, bypass = "press", text = "Drum pressure high" },
	{ id = "levelLow", level = 5, bypass = "level", text = "Drum level low" },
	{ id = "levelHigh", level = 5, bypass = "level", text = "Drum level high" },
	{ id = "feed", level = 5, bypass = "feed", text = "Feedwater flow low" },
	{ id = "mcp", level = 5, bypass = "mcp", text = "Main circulation flow low" },
	{ id = "turbines", level = 5, bypass = "turbines", text = "Both turbines tripped" },
	{ id = "rs", level = 5, text = "Reactor space pressure high" },
	{ id = "cps", level = 5, bypass = "cps", text = "Rod cooling lost" },
	{ id = "power", level = 5, text = "Loss of auxiliary power" },
	{ id = "eccs", level = 5, text = "ECCS actuation" },
	{ id = "period4", level = 4, bypass = "period", text = "Reactor period short (warning band)" },
	{ id = "deviation", level = 4, text = "Power above regulator setpoint" },
	{ id = "loadReject", level = 3, bypass = "turbines", text = "No generator on the grid" },
	{ id = "oneTurbine", level = 2, bypass = "turbines", text = "One turbine out" },
	{ id = "oneMcp", level = 1, bypass = "mcp", text = "Main circulation pump out" },
	{ id = "feedPump", level = 1, bypass = "feed", text = "Feedwater pump out" },
}

Protection.BYPASS_KEYS = { "period", "press", "level", "feed", "mcp", "turbines", "cps" }

function Protection.new(plant)
	local self = setmetatable({}, Protection)
	self.plant = plant
	self.active = {} -- condition present right now
	self.latched = {} -- has fired since the last reset
	self.bypass = {}
	self.timer = {}
	for _, sig in Protection.SIGNALS do
		self.active[sig.id] = false
		self.latched[sig.id] = false
		self.timer[sig.id] = 0
	end
	for _, key in Protection.BYPASS_KEYS do
		self.bypass[key] = false
	end
	self.manual = false
	self.firstOut = 0 -- index of the signal that started the present AZ-5
	self.scrams = 0

	local c = plant.cmd
	c["az5.button"] = function()
		self.manual = true
	end
	c["az.reset"] = function()
		self:reset()
	end
	for _, key in Protection.BYPASS_KEYS do
		c["prot.bypass." .. key] = function(v)
			local on = v >= 0.5
			if on ~= self.bypass[key] then
				self.bypass[key] = on
				plant:log(string.format("Protection %s: %s", if on then "BYPASSED" else "restored", key))
			end
		end
	end
	return self
end

function Protection.reset(self)
	local plant = self.plant
	for _, sig in Protection.SIGNALS do
		if sig.level == 5 and self.active[sig.id] and not (sig.bypass and self.bypass[sig.bypass]) then
			plant:log("Protection will not reset: " .. sig.text)
			return
		end
	end
	for _, sig in Protection.SIGNALS do
		self.latched[sig.id] = false
	end
	self.firstOut = 0
	plant.rods:resetProtection()
	plant:log("Protection reset")
end

-- True once a condition has held for `seconds`.
local function held(self, id: string, cond: boolean, seconds: number, dt: number): boolean
	if cond then
		self.timer[id] += dt
	else
		self.timer[id] = 0
	end
	return self.timer[id] >= seconds
end

function Protection.step(self, dt: number)
	local plant = self.plant
	local core, pri, sec, elec, rods, safety = plant.core, plant.primary, plant.secondary, plant.elec, plant.rods, plant.safety
	local power = core.fission / Config.NOMINAL_THERMAL
	local period = core.period
	local a = self.active

	local lowLevel = math.min(pri.loops[1].level, pri.loops[2].level)
	local highLevel = math.max(pri.loops[1].level, pri.loops[2].level)
	local minRunning = math.min(pri:runningCount(1), pri:runningCount(2))
	local minFlow = math.min(pri.loops[1].flow, pri.loops[2].flow) / Config.Primary.LOOP_RATED_FLOW
	local tripped = (if sec.turbines[1].tripped then 1 else 0) + (if sec.turbines[2].tripped then 1 else 0)
	local onGrid = (if elec.gens[1].mode == "grid" then 1 else 0) + (if elec.gens[2].mode == "grid" then 1 else 0)
	local feedRunning = 0
	for _, pump in sec.feedPumps do
		if pump.on then
			feedRunning += 1
		end
	end
	local deadBuses = 0
	for _, name in { "1A", "1B", "2A", "2B" } do
		if not elec.buses[name].live then
			deadBuses += 1
		end
	end
	local startupRange = power > 3e-8 and power < 0.10

	a.manual = self.manual
	self.manual = false
	a.overpower = power > Pr.OVERPOWER
	a.period = startupRange and period > 0 and period < Pr.PERIOD_TRIP
	a.press = pri.pressure > Pr.PRESSURE_HIGH
	a.levelLow = held(self, "levelLow", lowLevel < Pr.LEVEL_LOW, 2, dt)
	a.levelHigh = held(self, "levelHigh", highLevel > Pr.LEVEL_HIGH, 2, dt)
	a.feed = held(self, "feed", power > 0.30 and sec.feedTotal < 0.5 * sec.steamTotal, 10, dt)
	a.mcp = (power > 0.05 and minRunning < 2) or (power > 0.50 and minFlow < 0.55)
	a.turbines = power > 0.25 and tripped == 2
	a.rs = safety.rsPress > 5
	a.cps = held(self, "cps", safety.cpsFlow < 0.5 and power > 0.01, 15, dt) or safety.cpsTank < 0.6
	a.power = held(self, "power", deadBuses >= 2, 1.5, dt)
	a.eccs = safety.eccsActive
	a.period4 = startupRange and period > 0 and period < 15 and not a.period
	a.deviation = (rods.arMode > 0 or rods.larOn) and power > 0.10 and power - rods.setpoint > 0.07
	a.loadReject = power > 0.25 and onGrid == 0 and tripped < 2
	a.oneTurbine = power > 0.52 and onGrid == 1
	a.oneMcp = power > 0.62 and minRunning < 3
	a.feedPump = power > 0.62 and feedRunning < 3

	local az4 = false
	for index, sig in Protection.SIGNALS do
		local on = a[sig.id] and not (sig.bypass ~= nil and self.bypass[sig.bypass])
		if on then
			if not self.latched[sig.id] then
				self.latched[sig.id] = true
				plant:log(string.format("AZ-%d: %s", sig.level, sig.text))
				if sig.level == 5 and not rods.az5 then
					self.firstOut = index
					self.scrams += 1
				end
			end
			if sig.level == 5 then
				rods:tripAz5()
			elseif sig.level == 4 then
				az4 = true
			else
				rods:tripRunback(sig.level)
			end
		end
	end
	rods:setAz4(az4)
end

function Protection.publish(self, S)
	local anyBypass = 0
	for _, key in Protection.BYPASS_KEYS do
		local on = self.bypass[key]
		S["prot.bypass." .. key] = if on then 1 else 0
		if on then
			anyBypass = 1
		end
	end
	S["prot.anyBypass"] = anyBypass
	S["prot.firstOut"] = self.firstOut
	for _, sig in Protection.SIGNALS do
		-- 0 normal, 1 latched but cleared, 2 present now
		S["prot." .. sig.id] = if self.active[sig.id] then 2 elseif self.latched[sig.id] then 1 else 0
	end
end

return Protection
