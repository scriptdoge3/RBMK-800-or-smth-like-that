--!strict
-- Steam and feedwater side: the pressure regulator and turbine bypass, two
-- 400 MWe turbines with their condensers, the condensate system, the
-- deaerator, the feedwater pumps and the drum level controllers, and the
-- main safety valves.
--
-- Steam control follows the boiling-water-reactor pattern this control room
-- is styled on: one pressure regulator produces a total steam-flow demand,
-- each turbine takes the smaller of its share of that demand and its own
-- speed/load demand, and whatever is left over goes to the bypass valves.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local Config = require(Shared.Config)
local Steam = require(Shared.Steam)
local Util = require(Shared.Util)

local Sec = Config.Secondary

local Secondary = {}
Secondary.__index = Secondary

local NOMINAL_P = Config.Primary.NOMINAL_PRESSURE
local RATED = Config.NOMINAL_ELECTRIC / 2 -- W per machine
local STEAM_WORK = 698e3 -- J per kg of steam at design conditions (31% gross cycle efficiency)
local ROTOR_ENERGY = 2.7e9 -- J at rated speed
local WINDAGE = 6e6 -- W at rated speed
local FEED_BUS = { "1A", "1B", "2A", "2B" }
local COND_BUS = { "1A", "2A", "1B" }
local AUX_FEED_BUS = { "E1", "E2", "E3" }
local FEED_H0 = 9.5 -- MPa shutoff head
local FEED_A = 1.2 / (Sec.FEED_PUMP_FLOW ^ 2)
local FEED_CV = 651
local CP = 4300

local function newPump(name: string, bus: string)
	return { name = name, bus = bus, on = false, failed = false, repair = 0, flow = 0 }
end

function Secondary.new(plant)
	local self = setmetatable({}, Secondary)
	self.plant = plant
	self.pressSet = 6.9
	self.pressDir = 0
	self.pressInt = 0
	self.pressAuto = true
	self.demand = 0 -- total steam demand, fraction of nominal flow
	self.steamTotal = 0
	self.auxSteam = 0
	self.turbines = {}
	for k = 1, 2 do
		self.turbines[k] = {
			index = k,
			speed = 0,
			tripped = true,
			tripCause = "not latched",
			stopOpen = false,
			iso = 0, -- main steam isolation valve
			isoDir = 0,
			cv = 0,
			loadSet = 0, -- fraction of machine rating
			loadDir = 0,
			speedTarget = 0, -- 0, 1 = 500 rpm, 2 = 1800 rpm
			speedRef = 0,
			speedInt = 0,
			steam = 0,
			shaftPower = 0,
			metal = 40,
			wear = 0,
			bow = 0,
			vib = 0,
			lubeAC = false,
			lube = 0,
			turningGear = false,
			gland = false,
			bypass = 0,
			bypassAuto = true,
			bypassDir = 0,
			bypassFlow = 0,
			-- condenser
			cw = { newPump(string.format("CW-%dA", k), if k == 1 then "1A" else "2A"), newPump(string.format("CW-%dB", k), if k == 1 then "1B" else "2B") },
			vacPump = false,
			sjae = false,
			vacBreaker = true,
			air = 0.1013,
			condP = 0.1013,
			condT = 25,
			airLeak = 1, -- multiplier, raised by faults
			hotwell = 0.6,
			bearingDamage = 0,
		}
	end
	self.safety = {}
	for g = 1, 3 do
		self.safety[g] = { open = false, manual = false, stuck = false, flow = 0 }
	end
	self.feedPumps = {}
	for i = 1, Sec.N_FEED_PUMPS do
		self.feedPumps[i] = newPump("FWP-" .. i, FEED_BUS[i])
	end
	self.auxFeed = {}
	for i = 1, Sec.N_AUX_FEED_PUMPS do
		self.auxFeed[i] = newPump("AFWP-" .. i, AUX_FEED_BUS[i])
	end
	self.auxFeedAuto = true
	self.condPumps = {}
	for i = 1, Sec.N_COND_PUMPS do
		self.condPumps[i] = newPump("CP-" .. i, COND_BUS[i])
	end
	self.feedHeader = 0
	self.feedTotal = 0
	self.level = {}
	for l = 1, 2 do
		self.level[l] = { auto = false, valve = 0, dir = 0, set = 0, int = 0, autoSeconds = 0, stuck = 0, lastFeed = 0, demand = 0 }
	end
	self.da = { mass = 1.2e5, temp = 35, peg = false, levelAuto = true, valve = 0, dir = 0, pegFlow = 0 }
	self.condFlow = 0
	self.poolHeat = 0 -- W dumped into the suppression pool this tick
	self.autoSeconds = 0

	local c = plant.cmd
	c["ehc.press"] = function(v)
		self.pressDir = if v > 0.5 then 1 elseif v < -0.5 then -1 else 0
	end
	c["ehc.pressAuto"] = function(v)
		self.pressAuto = v >= 0.5
	end
	for k = 1, 2 do
		local t = self.turbines[k]
		local key = "tg." .. k
		c[key .. ".trip"] = function()
			self:tripTurbine(k, "manual trip")
		end
		c[key .. ".reset"] = function()
			self:resetTurbine(k)
		end
		c[key .. ".iso"] = function(v)
			t.isoDir = if v > 0.5 then 1 elseif v < -0.5 then -1 else 0
		end
		c[key .. ".load"] = function(v)
			t.loadDir = if v > 0.5 then 1 elseif v < -0.5 then -1 else 0
		end
		c[key .. ".speed"] = function(v)
			t.speedTarget = Util.clamp(math.floor(v), 0, 2)
		end
		c[key .. ".lube"] = function(v)
			t.lubeAC = v >= 0.5
		end
		c[key .. ".tgear"] = function(v)
			t.turningGear = v >= 0.5
		end
		c[key .. ".gland"] = function(v)
			t.gland = v >= 0.5
		end
		c[key .. ".bypassAuto"] = function(v)
			t.bypassAuto = v >= 0.5
		end
		c[key .. ".bypass"] = function(v)
			t.bypassDir = if v > 0.5 then 1 elseif v < -0.5 then -1 else 0
		end
		c[key .. ".vacPump"] = function(v)
			t.vacPump = v >= 0.5
		end
		c[key .. ".sjae"] = function(v)
			t.sjae = v >= 0.5
		end
		c[key .. ".vacBreaker"] = function(v)
			t.vacBreaker = v >= 0.5
		end
		for j = 1, 2 do
			c[key .. ".cw" .. j] = function(v)
				self:switchPump(t.cw[j], v >= 0.5)
			end
		end
	end
	for g = 1, 3 do
		c["srv." .. g] = function(v)
			self.safety[g].manual = v >= 0.5
		end
	end
	for i, pump in self.feedPumps do
		c["fw.pump." .. i] = function(v)
			self:switchPump(pump, v >= 0.5)
		end
	end
	for i, pump in self.auxFeed do
		c["afw.pump." .. i] = function(v)
			self:switchPump(pump, v >= 0.5)
		end
	end
	c["afw.auto"] = function(v)
		self.auxFeedAuto = v >= 0.5
	end
	for i, pump in self.condPumps do
		c["cond.pump." .. i] = function(v)
			self:switchPump(pump, v >= 0.5)
		end
	end
	for l = 1, 2 do
		local lc = self.level[l]
		c["lvl." .. l .. ".auto"] = function(v)
			local on = v >= 0.5
			if on and not lc.auto then
				lc.int = 0
			end
			lc.auto = on
		end
		c["lvl." .. l .. ".valve"] = function(v)
			lc.dir = if v > 0.5 then 1 elseif v < -0.5 then -1 else 0
		end
	end
	c["da.peg"] = function(v)
		self.da.peg = v >= 0.5
	end
	c["da.levelAuto"] = function(v)
		self.da.levelAuto = v >= 0.5
	end
	c["da.valve"] = function(v)
		self.da.dir = if v > 0.5 then 1 elseif v < -0.5 then -1 else 0
	end
	return self
end

function Secondary.switchPump(self, pump, on: boolean)
	local plant = self.plant
	if on then
		if pump.on then
			return
		end
		if pump.failed then
			plant:log(pump.name .. " will not start: out of service")
			return
		end
		if not plant:busLive(pump.bus) then
			plant:log(pump.name .. " will not start: bus " .. pump.bus .. " dead")
			return
		end
		pump.on = true
		plant:log(pump.name .. " started")
	elseif pump.on then
		pump.on = false
		plant:log(pump.name .. " stopped")
	end
end

local function servicePump(self, pump, dt: number, alarm: string?)
	if pump.on and not self.plant:busLive(pump.bus) then
		pump.on = false
		self.plant:log(pump.name .. " tripped: bus undervoltage")
		if alarm then
			self.plant:raise(alarm)
		end
	end
	if pump.repair > 0 then
		pump.repair -= dt
		if pump.repair <= 0 then
			pump.failed = false
			self.plant:log(pump.name .. " returned to service")
		end
	end
end

function Secondary.tripTurbine(self, k: number, cause: string)
	local t = self.turbines[k]
	if not t.tripped then
		t.tripped = true
		t.tripCause = cause
		t.stopOpen = false
		t.speedTarget = 0
		self.plant:log(string.format("TURBINE %d TRIP: %s", k, cause))
		self.plant:raise("tg." .. k .. ".trip")
	end
end

function Secondary.resetTurbine(self, k: number)
	local t = self.turbines[k]
	local plant = self.plant
	if not t.tripped then
		return
	end
	if t.condP > 0.030 then
		plant:log(string.format("Turbine %d will not latch: condenser vacuum low", k))
		return
	end
	if t.lube < 0.5 then
		plant:log(string.format("Turbine %d will not latch: lube oil pressure low", k))
		return
	end
	if t.bearingDamage >= 1 then
		plant:log(string.format("Turbine %d will not latch: bearing damage", k))
		return
	end
	t.tripped = false
	t.tripCause = ""
	t.stopOpen = true
	t.speedInt = 0
	t.speedRef = t.speed
	plant:log(string.format("Turbine %d latched, stop valves open", k))
end

-- Mechanical shock from a bad synchronisation.
function Secondary.shock(self, k: number, severity: number)
	self.turbines[k].wear += 0.15 * severity
end

-- The governor picks up a little load the moment the breaker closes so the
-- machine does not motor.
function Secondary.onSynchronised(self, k: number)
	local t = self.turbines[k]
	t.loadSet = math.max(t.loadSet, 0.04)
end

function Secondary.step(self, dt: number)
	local plant = self.plant
	local pri = plant.primary
	local elec = plant.elec
	local P = pri.pressure
	local pRatio = math.max(0, P - 0.12) / NOMINAL_P
	local tSteam = Steam.tsat(P)

	-- Pressure regulator.
	self.pressSet = Util.clamp(self.pressSet + self.pressDir * 0.02 * dt, 0.3, 7.2)
	local err = P - self.pressSet
	if self.pressAuto then
		self.pressInt = Util.clamp(self.pressInt + err * 0.35 * dt, 0, 1.4)
		self.demand = Util.clamp(err * 4 + self.pressInt, 0, 1.45)
		self.autoSeconds += dt
	else
		self.pressInt = 0
		self.demand = 1.45 -- regulator out of service: turbines follow load set alone
	end

	-- Speed / load demand of each machine.
	local limits = {}
	local order = {}
	for k = 1, 2 do
		local t = self.turbines[k]
		local gen = elec.gens[k]
		t.iso = Util.clamp(t.iso + t.isoDir * dt / 20, 0, 1)
		t.loadSet = Util.clamp(t.loadSet + t.loadDir * 0.01 * dt, 0, 1.08)
		local s = 0
		if t.stopOpen and t.iso > 0.02 then
			if gen.mode == "grid" then
				s = t.loadSet
			elseif gen.mode == "island" then
				-- Isolated: hold frequency with a 5% droop.
				s = Util.clamp(t.loadSet + (1 - t.speed) / 0.05, 0, 1.08)
			else
				local target = if t.speedTarget == 2 then 1 elseif t.speedTarget == 1 then 500 / Config.TURBINE_RPM else 0
				-- Speed reference ramps at 150 rpm per minute... per second it is quicker than a real unit.
				t.speedRef = Util.approach(t.speedRef, target, dt * (if target > t.speedRef then 1 / 90 else 1 / 30))
				local e = t.speedRef - t.speed
				t.speedInt = Util.clamp(t.speedInt + e * 0.05 * dt, 0, 0.08)
				s = Util.clamp(e * 1.2 + t.speedInt, 0, 0.12)
				if t.speedTarget == 0 then
					s = 0
				end
			end
		else
			t.speedInt = 0
			t.speedRef = t.speed
		end
		limits[k] = s
		order[k] = k
	end
	if limits[order[1]] > limits[order[2]] then
		order[1], order[2] = order[2], order[1]
	end
	-- Hand out the regulator's demand, most restricted machine first.
	local remaining = self.demand
	local turbineSteamFrac = 0
	for n, k in order do
		local t = self.turbines[k]
		local share = remaining / (3 - n) -- fraction of total nominal flow
		local cvDemand = math.min(limits[k], share / 0.5)
		if not t.stopOpen then
			cvDemand = 0
		end
		-- Control valves stroke in about three seconds, shut much faster.
		t.cv = Util.approach(t.cv, cvDemand, dt * (if cvDemand < t.cv then 2 else 0.35))
		local isoFactor = math.min(1, t.iso * 3)
		t.steam = if t.stopOpen then Sec.TURBINE_STEAM * t.cv * pRatio * isoFactor else 0
		local frac = t.steam / Sec.STEAM_NOMINAL
		remaining = math.max(0, remaining - cvDemand * 0.5)
		turbineSteamFrac += frac
	end

	-- Bypass takes the surplus, if the condenser can accept it.
	local surplus = if self.pressAuto then math.max(0, self.demand - turbineSteamFrac / math.max(pRatio, 0.05)) else 0
	local available = 0
	for k = 1, 2 do
		local t = self.turbines[k]
		if t.bypassAuto and t.condP < 0.040 then
			available += 1
		end
	end
	local steamTotal = 0
	local aux = 0
	for k = 1, 2 do
		local t = self.turbines[k]
		local gen = elec.gens[k]
		local target
		if t.condP >= 0.040 then
			target = 0 -- vacuum interlock
		elseif t.bypassAuto then
			target = if available > 0 then Util.clamp(surplus / available / Sec.BYPASS_CAPACITY, 0, 1) else 0
		else
			t.bypass = Util.clamp(t.bypass + t.bypassDir * 0.1 * dt, 0, 1)
			target = t.bypass
		end
		t.bypass = Util.approach(t.bypass, target, dt * 1.5)
		t.bypassFlow = Sec.BYPASS_CAPACITY * Sec.STEAM_NOMINAL * t.bypass * pRatio

		-- Shaft.
		local vacFactor = Util.clamp(1 - 1.2 * (t.condP - 0.005) / 0.1, 0.3, 1.02)
		local flowFrac = t.steam / Sec.TURBINE_STEAM
		local eff = (1 - 0.12 * (1 - math.min(flowFrac, 1)) ^ 2) * vacFactor * (math.max(P, 0.2) / NOMINAL_P) ^ 0.12
		local mech = t.steam * STEAM_WORK * eff
		local loss = WINDAGE * t.speed * t.speed * (0.4 + 0.6 * t.speed)
		if gen.mode == "grid" then
			t.speed = elec.grid.freq / Config.GRID_HZ
			t.shaftPower = mech - loss
		else
			local net = mech - loss - gen.pe
			t.speed = math.max(0, t.speed + net / (2 * ROTOR_ENERGY * math.max(t.speed, 0.03)) * dt)
			t.shaftPower = mech - loss
			if t.turningGear and t.lube > 0.5 and t.speed < 0.004 and plant:busLive("E1") then
				t.speed = 0.002
			end
		end

		-- Lube oil: shaft pump near rated speed, AC pump, or the DC standby.
		local lube = 0
		if t.speed > 0.9 then
			lube = 1
		elseif t.lubeAC and plant:busLive("E" .. k) then
			lube = 1
			elec:addLoad("E" .. k, 0.2e6)
		else
			lube = 0.75 -- battery-driven emergency pump cuts in by itself
		end
		if t.bearingDamage >= 1 then
			lube = 0.2
		end
		t.lube = Util.lag(t.lube, lube, dt, 1.5)

		-- Metal temperature and thermal stress.
		local warmRate = (0.012 + flowFrac) / 60
		local steamAtInlet = if t.steam > 0.5 then tSteam else math.max(t.metal - 40, 35)
		local stress = math.abs(tSteam - t.metal) * flowFrac
		t.metal += (steamAtInlet - t.metal) * (1 - math.exp(-warmRate * dt))
		if stress > 60 and t.steam > 1 then
			t.wear += (stress / 60 - 1) * dt / 900
		end
		t.stress = stress

		-- A hot rotor left standing sags; turning gear straightens it again.
		if t.speed < 0.001 and t.metal > 150 then
			t.bow = math.min(1, t.bow + dt / 600)
		elseif t.speed > 0.0015 then
			t.bow = math.max(0, t.bow - dt / 500)
		end
		local critical = math.exp(-((t.speed - 0.55) / 0.07) ^ 2)
		local vib = 1.2 + 9 * t.wear + 3.5 * critical * (0.4 + t.speed) + 7 * t.bow * math.min(1, t.speed * 3) + 10 * t.bearingDamage
		if t.speed < 0.01 then
			vib = 0
		end
		t.vib = Util.lag(t.vib, vib, dt, 1.5)

		-- Condenser.
		local cwFrac = 0
		for _, pump in t.cw do
			servicePump(self, pump, dt)
			if pump.on then
				cwFrac += 0.6
				elec:addLoad(pump.bus, 2.2e6)
			end
		end
		cwFrac = math.min(cwFrac, 1)
		local rejected = (t.steam * (1 - 0.3 * eff) + t.bypassFlow) * 2.2e6
		local qFrac = rejected / (Sec.TURBINE_STEAM * 2.2e6)
		local condT = 18 + 10 * qFrac / math.max(cwFrac, 0.04) + 4 * math.sqrt(qFrac)
		t.condT = Util.lag(t.condT, math.min(condT, 140), dt, 20)
		local leak = t.airLeak * (if t.gland and P > 0.5 then 1 else 5)
		local airTarget, tau
		if t.vacBreaker then
			airTarget, tau = 0.1013, 6
		elseif t.sjae and P > 1.0 then
			airTarget, tau = 0.0003 * leak, 45
			aux += 2
		elseif t.vacPump and plant:busLive(t.cw[1].bus) then
			airTarget, tau = 0.004 + 0.0015 * leak, 70
			elec:addLoad(t.cw[1].bus, 0.3e6)
		else
			airTarget, tau = 0.1013, 1500 / leak
		end
		t.air = Util.lag(t.air, airTarget, dt, tau)
		t.condP = math.min(0.1013, t.air + Steam.psat(t.condT))
		if t.gland and P > 0.5 then
			aux += 1.5
		end

		-- Turbine protection.
		if not t.tripped then
			if t.speed > 1.10 then
				self:tripTurbine(k, "overspeed")
				t.wear += 0.05
			elseif t.condP > 0.030 and t.speed > 0.05 then
				self:tripTurbine(k, "condenser vacuum low")
			elseif t.lube < 0.5 and t.speed > 0.02 then
				self:tripTurbine(k, "lube oil pressure low")
			elseif t.vib > 11.8 then
				self:tripTurbine(k, "vibration high")
			elseif math.max(pri.loops[1].level, pri.loops[2].level) > 700 then
				self:tripTurbine(k, "drum level high (water carryover)")
			end
		end
		-- Running a bearing with no oil ruins it.
		if t.lube < 0.4 and t.speed > 0.05 then
			t.bearingDamage = math.min(1, t.bearingDamage + dt / 60)
		end
		steamTotal += t.steam + t.bypassFlow
	end

	-- Main safety valves, three groups, blowing down to the suppression pool.
	local poolSteam = 0
	for g = 1, 3 do
		local v = self.safety[g]
		local set = Sec.SAFETY_VALVE_SETPOINTS[g]
		if P > set then
			if not v.open then
				plant:log(string.format("Safety valve group %d lifted at %.2f MPa", g, P))
			end
			v.open = true
		elseif P < set - 0.35 and not v.stuck then
			v.open = false
		elseif v.stuck and v.open and P < 4.0 then
			-- A valve that failed to reseat finally closes at low pressure.
			v.stuck = false
			v.open = false
			plant:log(string.format("Safety valve group %d reseated", g))
		end
		local isOpen = v.open or v.manual
		v.flow = if isOpen then Sec.SAFETY_VALVE_CAPACITY * Sec.STEAM_NOMINAL * pRatio else 0
		poolSteam += v.flow
	end
	steamTotal += poolSteam
	local _, _, hfgNow = Steam.sat(P)
	self.poolHeat = poolSteam * (hfgNow + 4.2e5)

	-- Condensate and deaerator.
	local da = self.da
	local condCapacity = 0
	for _, pump in self.condPumps do
		servicePump(self, pump, dt, "cond.pump")
		if pump.on then
			condCapacity += Sec.COND_PUMP_FLOW
			elec:addLoad(pump.bus, 1.2e6)
		end
	end
	local daLevel = da.mass / 2.5e5
	if da.levelAuto then
		da.valve = Util.clamp(da.valve + ((0.50 - daLevel) * 0.8 - (da.valve - 0.5) * 0.02) * dt, 0, 1)
	else
		da.valve = Util.clamp(da.valve + da.dir * 0.1 * dt, 0, 1)
	end
	local condFlow = math.min(condCapacity, da.valve * 1600)
	if daLevel > 0.98 then
		condFlow = 0
	end
	self.condFlow = condFlow
	local loadFrac = (self.turbines[1].steam + self.turbines[2].steam) / Sec.STEAM_NOMINAL
	local condTemp = 0.5 * (self.turbines[1].condT + self.turbines[2].condT) + 70 * loadFrac
	-- Heating steam: turbine extraction first, then pegging steam from the main header.
	local target = Sec.FEEDWATER_TEMP
	local need = condFlow * CP * math.max(0, target - condTemp) + da.mass * CP * (target - da.temp) / 400
	local extraction = loadFrac * Sec.STEAM_NOMINAL * 0.13 * 2.0e6
	local pegAvail = if da.peg and P > 0.8 then 110e6 * math.min(1, pRatio * 1.2) else 0
	local heat = Util.clamp(need, 0, extraction + pegAvail)
	da.pegFlow = math.max(0, heat - extraction) / 2.0e6
	aux += da.pegFlow
	da.temp += (condFlow * CP * (condTemp - da.temp) + heat) / (da.mass * CP) * dt
	da.temp = Util.clamp(da.temp, 20, 175)
	self.auxSteam = aux
	steamTotal += aux
	self.steamTotal = steamTotal
	pri.steamOut = steamTotal

	-- Feedwater pumps.
	local running = 0
	for _, pump in self.feedPumps do
		servicePump(self, pump, dt, "fw.pump")
		if pump.on and daLevel < 0.08 then
			pump.on = false
			plant:log(pump.name .. " tripped: deaerator level low")
			plant:raise("fw.pump")
		end
		if pump.on then
			running += 1
		end
	end
	local suction = math.max(Steam.psat(da.temp), 0.1) + 0.2

	-- Drum level controllers, three-element: the level error trims a feed
	-- flow demand that otherwise follows steam flow, and the valve is moved
	-- until measured feed flow meets that demand.
	for l = 1, 2 do
		local lc = self.level[l]
		local loop = pri.loops[l]
		if lc.stuck > 0 then
			-- Valve actuator fault: it stays where it is.
			lc.stuck -= dt
		elseif lc.auto then
			local e = (lc.set - loop.indicated) / 1000 -- metres
			-- No integrating against a valve that is already hard closed or open.
			if not ((lc.valve <= 0.001 and e < 0) or (lc.valve >= 0.999 and e > 0)) then
				lc.int = Util.clamp(lc.int + e * 4 * dt, -150, 150)
			end
			local demand = math.max(0, loop.steam + 350 * e + lc.int)
			lc.demand = demand
			if running > 0 then
				lc.valve = Util.clamp(lc.valve + Util.clamp((demand - lc.lastFeed) / 900, -0.15, 0.15) * dt, 0, 1)
			else
				lc.valve = Util.approach(lc.valve, 0.05, 0.05 * dt)
			end
			lc.autoSeconds += dt
			self.autoSeconds += dt * 0.5
		else
			lc.valve = Util.clamp(lc.valve + lc.dir * 0.05 * dt, 0, 1)
		end
	end

	-- Header pressure where pump supply meets valve demand.
	local feed = { 0, 0 }
	local header = suction
	if running > 0 then
		local lo, hi = P, suction + FEED_H0
		for _ = 1, 24 do
			local mid = 0.5 * (lo + hi)
			local supply = running * math.sqrt(math.max(0, suction + FEED_H0 - mid) / FEED_A)
			local demand = 0
			for l = 1, 2 do
				local dp = mid - P - 0.2
				if dp > 0 then
					demand += FEED_CV * (self.level[l].valve ^ 1.5) * math.sqrt(dp)
				end
			end
			if supply > demand then
				lo = mid
			else
				hi = mid
			end
		end
		header = 0.5 * (lo + hi)
		for l = 1, 2 do
			local dp = header - P - 0.2
			feed[l] = if dp > 0 then FEED_CV * (self.level[l].valve ^ 1.5) * math.sqrt(dp) else 0
		end
		-- Pumps run out at about 120% of rated flow.
		local limit = running * Sec.FEED_PUMP_FLOW * 1.2
		local sum = feed[1] + feed[2]
		if sum > limit then
			feed[1] *= limit / sum
			feed[2] *= limit / sum
		end
	end
	self.level[1].lastFeed = feed[1]
	self.level[2].lastFeed = feed[2]
	self.feedHeader = header
	local mainFeed = feed[1] + feed[2]
	for _, pump in self.feedPumps do
		pump.flow = if pump.on then mainFeed / running else 0
		if pump.on then
			elec:addLoad(pump.bus, 4.2e6 * (0.45 + 0.55 * pump.flow / Sec.FEED_PUMP_FLOW))
		end
	end

	-- Emergency feed pumps.
	local lowLevel = math.min(pri.loops[1].level, pri.loops[2].level) < -500
	local auxFlow = 0
	for _, pump in self.auxFeed do
		servicePump(self, pump, dt)
		if self.auxFeedAuto and lowLevel and not pump.on and not pump.failed and plant:busLive(pump.bus) then
			pump.on = true
			plant:log(pump.name .. " auto-started on low drum level")
		end
		if pump.on then
			if daLevel > 0.03 and P < 8.5 then
				auxFlow += Sec.AUX_FEED_FLOW
				pump.flow = Sec.AUX_FEED_FLOW
			else
				pump.flow = 0
			end
			elec:addLoad(pump.bus, 0.9e6)
		else
			pump.flow = 0
		end
	end
	local hFeed = Steam.hLiquid(da.temp)
	for l = 1, 2 do
		local loop = pri.loops[l]
		loop.feed = feed[l] + auxFlow / 2
		loop.feedEnthalpy = hFeed
	end
	self.feedTotal = mainFeed + auxFlow
	da.mass = Util.clamp(da.mass + (condFlow + heat / 2.2e6 - self.feedTotal) * dt, 0, 2.5e5)

	-- Hotwells: condensed steam in, condensate out, automatic makeup and reject.
	for k = 1, 2 do
		local t = self.turbines[k]
		local inflow = t.steam + t.bypassFlow
		local level = t.hotwell + (inflow - condFlow / 2) * dt / 6.0e4
		level += (0.6 - level) * math.min(1, dt / 40)
		t.hotwell = Util.clamp(level, 0, 1)
	end
end

function Secondary.publish(self, S)
	local plant = self.plant
	S["ehc.pressSet"] = self.pressSet
	S["ehc.pressAuto"] = if self.pressAuto then 1 else 0
	S["ehc.demand"] = self.demand * 100
	S["steam.total"] = self.steamTotal * 3.6
	S["steam.aux"] = self.auxSteam * 3.6
	local tripped = 0
	for k = 1, 2 do
		local t = self.turbines[k]
		local key = "tg." .. k
		S[key .. ".rpm"] = t.speed * Config.TURBINE_RPM
		S[key .. ".trip"] = if t.tripped then 1 else 0
		S[key .. ".stop"] = if t.stopOpen then 1 else 0
		S[key .. ".iso"] = t.iso * 100
		S[key .. ".cv"] = t.cv * 100
		S[key .. ".load"] = t.loadSet * 100
		S[key .. ".speedTarget"] = t.speedTarget
		S[key .. ".steam"] = t.steam * 3.6
		S[key .. ".bypass"] = t.bypass * 100
		S[key .. ".bypassAuto"] = if t.bypassAuto then 1 else 0
		S[key .. ".vac"] = t.condP * 1000
		S[key .. ".condT"] = t.condT
		S[key .. ".vib"] = t.vib
		S[key .. ".metal"] = t.metal
		S[key .. ".stress"] = t.stress or 0
		S[key .. ".lube"] = t.lube * 0.25
		S[key .. ".lubeAC"] = if t.lubeAC then 1 else 0
		S[key .. ".tgear"] = if t.turningGear then 1 else 0
		S[key .. ".gland"] = if t.gland then 1 else 0
		S[key .. ".vacPump"] = if t.vacPump then 1 else 0
		S[key .. ".sjae"] = if t.sjae then 1 else 0
		S[key .. ".vacBreaker"] = if t.vacBreaker then 1 else 0
		S[key .. ".hotwell"] = t.hotwell * 100
		S[key .. ".wear"] = t.wear
		for j = 1, 2 do
			S[key .. ".cw" .. j] = if t.cw[j].on then 1 else 0
		end
		if t.tripped then
			tripped += 1
		end
	end
	S["tg.tripped"] = tripped
	for g = 1, 3 do
		local v = self.safety[g]
		S["srv." .. g .. ".open"] = if v.open or v.manual then 1 else 0
		S["srv." .. g .. ".sw"] = if v.manual then 1 else 0
	end
	local feedRunning = 0
	for i, pump in self.feedPumps do
		S["fw.pump." .. i .. ".run"] = if pump.on then 1 else 0
		S["fw.pump." .. i .. ".flow"] = pump.flow * 3.6
		if pump.on then
			feedRunning += 1
		end
	end
	S["fw.running"] = feedRunning
	S["fw.header"] = self.feedHeader
	S["fw.total"] = self.feedTotal * 3.6
	S["fw.temp"] = self.da.temp
	for i, pump in self.auxFeed do
		S["afw.pump." .. i .. ".run"] = if pump.on then 1 else 0
	end
	S["afw.auto"] = if self.auxFeedAuto then 1 else 0
	local condRunning = 0
	for i, pump in self.condPumps do
		S["cond.pump." .. i .. ".run"] = if pump.on then 1 else 0
		if pump.on then
			condRunning += 1
		end
	end
	S["cond.running"] = condRunning
	S["cond.flow"] = self.condFlow * 3.6
	for l = 1, 2 do
		local lc = self.level[l]
		S["lvl." .. l .. ".auto"] = if lc.auto then 1 else 0
		S["lvl." .. l .. ".valve"] = lc.valve * 100
	end
	S["da.level"] = self.da.mass / 2.5e5 * 100
	S["da.temp"] = self.da.temp
	S["da.peg"] = if self.da.peg then 1 else 0
	S["da.levelAuto"] = if self.da.levelAuto then 1 else 0
	S["da.valve"] = self.da.valve * 100
	local _ = plant
end

return Secondary
