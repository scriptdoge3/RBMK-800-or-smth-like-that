--!native
--!optimize 2
-- Main circulation circuit: two loops, each with four main circulation
-- pumps (three run, one is standby) and a pair of drum separators that are
-- lumped into one water inventory per loop. Both loops share one steam space,
-- so there is a single pressure, but each loop has its own flow, inlet
-- subcooling and drum level.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local Config = require(Shared.Config)
local Steam = require(Shared.Steam)
local Util = require(Shared.Util)

local P = Config.Primary

local Primary = {}
Primary.__index = Primary

local PUMP_BUS = { "1A", "1B", "2A", "2B" }
local ATMOSPHERE = 0.1013

-- Pump curve: head = H0*w^2 - A*q^2 (MPa, kg/s).
local PUMP_A = (P.PUMP_SHUTOFF_HEAD - P.PUMP_RATED_HEAD) / (P.PUMP_RATED_FLOW ^ 2)
local VALVE_K = 0.08 / (P.PUMP_RATED_FLOW ^ 2)
local CORE_DP_NOMINAL = 0.95
local PIPE_R = 0.50 / (P.LOOP_RATED_FLOW ^ 2)

function Primary.new(plant)
	local self = setmetatable({}, Primary)
	self.plant = plant
	self.core = plant.core
	self.temp = Config.Core.T_REF -- bulk water temperature; saturation once pressurised
	self.pressure = ATMOSPHERE
	self.heatupRate = 0 -- K/s, filtered
	self.stress = 0 -- accumulated thermal-shock damage, feeds the wear model
	self.steamOut = 0 -- kg/s leaving the drums, set by the secondary side
	self.cooldownOn = false
	self.loops = {}
	self.pumps = {}
	self.cond = { pressure = { ATMOSPHERE, ATMOSPHERE }, inletEnthalpy = { 0, 0 }, flow = { 0, 0 } }

	local rhoHot = Steam.rhoLiquid(Steam.tsat(P.NOMINAL_PRESSURE))
	for l = 1, P.N_LOOPS do
		local voidRef = (self.core.designVoidVolume and self.core.designVoidVolume[l]) or 30
		local vRef = P.DRUM_NOMINAL_MASS / rhoHot + voidRef
		self.loops[l] = {
			vRef = vRef,
			-- Start cold with the drums a little under the normal level.
			mass = (vRef - 0.15 * P.DRUM_AREA) * Steam.rhoLiquid(self.temp),
			level = 0,
			flow = 0,
			dp = 0,
			inletEnthalpy = Steam.hLiquid(self.temp),
			inletTemp = self.temp,
			subcool = 0,
			feed = 0, -- kg/s feedwater in, set by the secondary side
			feedEnthalpy = Steam.hLiquid(30),
			eccs = 0, -- kg/s emergency injection
			steam = 0,
			blowdown = 0, -- valve position 0..1
			blowdownDir = 0,
			letdownAuto = true, -- letdown holds the drum level by itself
			leak = 0, -- kg/s from a pipe break in the compartments
			levelBias = 0, -- mm error on the narrow-range transmitter (instrument fault)
			indicated = 0,
			kc = 1,
			ncHead = 0,
			npsh = 1,
		}
		self.pumps[l] = {}
		for i = 1, P.PUMPS_PER_LOOP do
			self.pumps[l][i] = {
				on = false,
				speed = 0,
				valve = 1, -- throttles stand open in shutdown so the core can thermosiphon
				valveDir = 0,
				bus = PUMP_BUS[i],
				failed = false,
				repair = 0,
				wear = 0,
				cav = 0,
				flow = 0,
				power = 0,
				overload = 0,
				name = string.format("MCP-%d%d", l, i),
			}
		end
	end
	self:calibrate()

	local c = plant.cmd
	for l = 1, P.N_LOOPS do
		for i = 1, P.PUMPS_PER_LOOP do
			local pump = self.pumps[l][i]
			local key = string.format("mcp.%d%d", l, i)
			c[key .. ".sw"] = function(v)
				if v >= 0.5 then
					self:startPump(pump)
				else
					self:stopPump(pump, "stopped by operator")
				end
			end
			c[key .. ".valve"] = function(v)
				pump.valveDir = if v > 0.5 then 1 elseif v < -0.5 then -1 else 0
			end
		end
		local loop = self.loops[l]
		c[string.format("loop.%d.blowdown", l)] = function(v)
			loop.blowdownDir = if v > 0.5 then 1 elseif v < -0.5 then -1 else 0
		end
		c[string.format("loop.%d.letdownAuto", l)] = function(v)
			loop.letdownAuto = v >= 0.5
		end
		-- The loop's throttles together: the panel has one control per loop.
		c[string.format("loop.%d.throttle", l)] = function(v)
			local dir = if v > 0.5 then 1 elseif v < -0.5 then -1 else 0
			for _, pump in self.pumps[l] do
				pump.valveDir = dir
			end
		end
	end
	c["pri.cooldown"] = function(v)
		self.cooldownOn = v >= 0.5
	end
	return self
end

-- Tie the channel hydraulic weights to the design pressure drop.
function Primary.calibrate(self)
	for l = 1, P.N_LOOPS do
		local y = (self.core.designConductance and self.core.designConductance[l]) or self.core.loopConductance[l]
		if y <= 0 then
			y = 1
		end
		self.loops[l].kc = P.LOOP_RATED_FLOW / (y * math.sqrt(CORE_DP_NOMINAL))
	end
end

function Primary.startPump(self, pump)
	if pump.on then
		return
	end
	if pump.failed then
		self.plant:log(pump.name .. " will not start: out of service")
		return
	end
	if not self.plant:busLive(pump.bus) then
		self.plant:log(pump.name .. " will not start: bus " .. pump.bus .. " dead")
		return
	end
	pump.on = true
	pump.overload = 0
	if pump.valve > 0.25 then
		-- Starting against an open throttle is hard on the motor.
		pump.wear += 0.03
	end
	self.plant:log(pump.name .. " started")
end

function Primary.stopPump(self, pump, why: string)
	if pump.on then
		pump.on = false
		self.plant:log(pump.name .. " " .. why)
		if string.sub(why, 1, 7) == "tripped" then
			self.plant:raise("mcp.trip")
		end
	end
end

function Primary.runningCount(self, l: number): number
	local n = 0
	for _, pump in self.pumps[l] do
		if pump.on and pump.speed > 0.5 then
			n += 1
		end
	end
	return n
end

-- Pump speeds, loop flows and the inlet conditions the core will see.
function Primary.hydraulics(self, dt: number)
	local plant = self.plant
	local core = self.core
	local tsat, hf, _, rhof, rhog = Steam.sat(self.pressure)
	local hBulk = Steam.hLiquid(self.temp)
	for l = 1, P.N_LOOPS do
		local loop = self.loops[l]
		local pumps = self.pumps[l]

		-- Natural circulation head from the density difference between the
		-- downcomers and the channels plus risers.
		local rhoDown = Steam.rhoLiquid(math.min(loop.inletTemp, self.temp))
		local x = Util.clamp(core.loopExitQuality[l], 0, 1)
		local rhoCore = core.loopDensity[l]
		local rhoRiser = rhoCore
		if x > 0 then
			local slip = 1 + 0.12 * math.sqrt(rhof / rhog)
			local alpha = x / (x + (1 - x) * slip * rhog / rhof)
			rhoRiser = alpha * rhog + (1 - alpha) * rhof
		end
		local nc = 9.81e-6 * ((rhoDown - rhoCore) * 7 + (rhoDown - rhoRiser) * 18)
		if nc < 0 then
			nc = 0
		end
		loop.ncHead = nc

		local maxHead = 0
		for _, pump in pumps do
			local live = plant:busLive(pump.bus)
			if pump.on and not live then
				self:stopPump(pump, "tripped: bus undervoltage")
			end
			if pump.repair > 0 then
				pump.repair -= dt
				if pump.repair <= 0 then
					pump.failed = false
					plant:log(pump.name .. " returned to service")
				end
			end
			if pump.on then
				local target = plant:busFrequency(pump.bus) / Config.GRID_HZ
				pump.speed += (target - pump.speed) * (1 - math.exp(-dt / 4))
			else
				-- Coastdown on the flywheel.
				local s = pump.speed
				s -= (s * s / P.PUMP_COASTDOWN + 0.004) * dt
				pump.speed = math.max(s, 0)
			end
			pump.valve = Util.clamp(pump.valve + pump.valveDir * 0.05 * dt, 0, 1)
			local head = P.PUMP_SHUTOFF_HEAD * pump.speed * pump.speed * (1 - 0.5 * pump.cav)
			pump._head = head
			-- A stopped rotor is a much bigger obstruction than a turning one.
			local a = if pump.speed < 0.05 then PUMP_A * 4 else PUMP_A
			pump._res = if pump.valve < 0.01 then math.huge else a + VALVE_K * (1 / (pump.valve * pump.valve) - 1)
			if head > maxHead then
				maxHead = head
			end
		end

		local y = core.loopConductance[l]
		local rCore = if y > 0 then 1 / ((loop.kc * y) ^ 2) else math.huge
		local rSys = rCore + PIPE_R
		local function imbalance(dp: number): (number, number)
			local supply = 0
			for _, pump in pumps do
				local h = pump._head - dp
				if h > 0 and pump._res < math.huge then
					supply += math.sqrt(h / pump._res)
				end
			end
			local demand = if dp + nc > 0 then math.sqrt((dp + nc) / rSys) else 0
			return supply - demand, supply
		end
		local lo, hi = -nc, maxHead + 1e-6
		local flow = 0
		for _ = 1, 28 do
			local mid = 0.5 * (lo + hi)
			local f, supply = imbalance(mid)
			flow = supply
			if f > 0 then
				lo = mid
			else
				hi = mid
			end
		end
		local dp = 0.5 * (lo + hi)
		loop.flow = flow
		loop.dp = math.max(dp, 0)

		-- Feedwater mixes with the saturated water coming down from the drums.
		local hin = hBulk
		if flow > 1 then
			local fwFrac = math.min(1, loop.feed / flow)
			hin -= fwFrac * (hBulk - loop.feedEnthalpy)
			local eccsFrac = math.min(1, loop.eccs / flow)
			hin -= eccsFrac * (hBulk - Steam.hLiquid(40))
		end
		local tSuction = Steam.tLiquid(hin)
		local psatSuction = Steam.psat(tSuction)
		local npsh = self.pressure + P.DRUM_ELEVATION_HEAD - psatSuction - 0.15 * (flow / P.LOOP_RATED_FLOW) ^ 2
		-- A badly low drum level starves the suction as well.
		if loop.level < -900 then
			npsh -= 0.0004 * (-900 - loop.level)
		end
		loop.npsh = npsh

		local pumpHeat = 0
		for _, pump in pumps do
			local q = 0
			local h = pump._head - dp
			if h > 0 and pump._res < math.huge then
				q = math.sqrt(h / pump._res)
			end
			pump.flow = q
			local qr = q / P.PUMP_RATED_FLOW
			local margin = npsh - 0.11 * qr * qr
			local severity = if margin < 0 and pump.speed > 0.3 then Util.clamp(-margin / 0.05, 0, 1) else 0
			pump.cav = Util.lag(pump.cav, severity, dt, 2)
			if pump.cav > 0.1 then
				pump.wear += pump.cav * dt * 4e-4
			end
			local w = pump.speed
			pump.power = if pump.on then P.PUMP_MOTOR_MW * 1e6 * w * w * (0.45 * w + 0.55 * qr) else 0
			pumpHeat += 0.9 * pump.power
			-- Sustained overload trips the motor.
			if pump.power > 1.22 * P.PUMP_MOTOR_MW * 1e6 then
				pump.overload += dt
				if pump.overload > 12 then
					self:stopPump(pump, "tripped: motor overload")
				end
			else
				pump.overload = math.max(0, pump.overload - dt)
			end
			if pump.on and loop.level < -1300 then
				self:stopPump(pump, "tripped: drum level low-low")
			end
		end
		loop.pumpHeat = pumpHeat
		if flow > 1 then
			-- (Capped: a pump spinning up against almost no flow would
			-- otherwise appear to flash the water in its casing.)
			hin += math.min(pumpHeat / flow, 2.0e4)
		end
		hin = math.max(hin, Steam.hLiquid(15))
		-- A change in feedwater takes several seconds to work its way down
		-- the downcomers and through the pumps to the channel inlets.
		if loop.inletLag then
			hin = Util.lag(loop.inletLag, hin, dt, 7)
		end
		loop.inletLag = hin
		loop.inletEnthalpy = hin
		loop.inletTemp = Steam.tLiquid(math.min(hin, hf))
		loop.subcool = math.max(0, tsat - loop.inletTemp)
		-- The channels sit under the static head of the risers, so they
		-- boil at a slightly higher temperature than the drums.
		self.cond.pressure[l] = self.pressure + P.RISER_HEAD
		self.cond.inletEnthalpy[l] = math.min(hin, hf + 1e5)
		self.cond.flow[l] = flow
	end
	return self.cond
end

-- Energy and mass balance: pressure/temperature and the drum levels.
function Primary.thermal(self, dt: number)
	local core = self.core
	local _, _, hfg = Steam.sat(self.pressure)
	local hBulk = Steam.hLiquid(self.temp)
	local qIn = core.loopHeat[1] + core.loopHeat[2]
	local qOut = self.steamOut * hfg
	local genTotal = core.loopSteam[1] + core.loopSteam[2]
	for l = 1, P.N_LOOPS do
		local loop = self.loops[l]
		qIn += loop.pumpHeat or 0
		qOut += loop.feed * math.max(0, hBulk - loop.feedEnthalpy)
		qOut += loop.eccs * math.max(0, hBulk - Steam.hLiquid(40))
	end
	-- Standing losses, and the cooldown heat exchangers when in service.
	qOut += 2.5e6 * (self.temp - 30) / 250
	if self.cooldownOn then
		qOut += 90e6 * math.max(0, self.temp - 30) / 250
	end
	local dT = (qIn - qOut) / P.THERMAL_MASS * dt
	self.temp = Util.clamp(self.temp + dT, 15, 360)
	self.pressure = math.max(ATMOSPHERE, Steam.psat(self.temp))
	local rate = dT / dt
	self.heatupRate = Util.lag(self.heatupRate, rate, dt, 15)
	local over = math.abs(self.heatupRate) / P.HEATUP_LIMIT - 1
	if over > 0 then
		self.stress += over * dt / 600
	end

	local rho = Steam.rhoLiquid(self.temp)
	for l = 1, P.N_LOOPS do
		local loop = self.loops[l]
		local share = if genTotal > 1 then core.loopSteam[l] / genTotal else 0.5
		loop.steam = self.steamOut * share
		loop.blowdown = Util.clamp(loop.blowdown + loop.blowdownDir * 0.1 * dt, 0, 1)
		local letdown = loop.blowdown * 30
		if loop.letdownAuto and loop.level > 60 then
			letdown = math.max(letdown, Util.clamp((loop.level - 60) / 100, 0, 1) * 30)
		end
		loop.letdown = letdown
		local tubeLeak = core.loopLeak[l]
		loop.mass += (loop.feed + loop.eccs - loop.steam - letdown - tubeLeak - loop.leak) * dt
		if loop.mass < 1000 then
			loop.mass = 1000
		end
		local volume = loop.mass / rho + core.loopVoidVolume[l]
		loop.level = Util.clamp((volume - loop.vRef) / P.DRUM_AREA * 1000, -2000, 1500)
		loop.indicated = loop.level + loop.levelBias
	end
end

function Primary.publish(self, S)
	S["pri.press"] = self.pressure
	S["pri.temp"] = self.temp
	S["pri.heatup"] = self.heatupRate * 60
	S["pri.cooldown"] = if self.cooldownOn then 1 else 0
	S["pri.stress"] = self.stress
	local total = 0
	for l = 1, P.N_LOOPS do
		local loop = self.loops[l]
		local k = "loop." .. l
		S[k .. ".flow"] = loop.flow * 3.6
		S[k .. ".level"] = loop.indicated
		S[k .. ".levelWide"] = loop.level
		S[k .. ".dp"] = loop.dp
		S[k .. ".subcool"] = loop.subcool
		S[k .. ".tin"] = loop.inletTemp
		S[k .. ".steam"] = loop.steam * 3.6
		S[k .. ".feed"] = loop.feed * 3.6
		S[k .. ".blowdown"] = loop.blowdown * 100
		S[k .. ".letdownAuto"] = if loop.letdownAuto then 1 else 0
		S[k .. ".npsh"] = loop.npsh
		S[k .. ".running"] = self:runningCount(l)
		local valves = 0
		for _, pump in self.pumps[l] do
			valves += pump.valve
		end
		S[k .. ".throttle"] = valves / #self.pumps[l] * 100
		total += loop.flow
		local rho = Steam.rhoLiquid(loop.inletTemp)
		for i, pump in self.pumps[l] do
			local pk = string.format("mcp.%d%d", l, i)
			S[pk .. ".run"] = if pump.on then 1 else 0
			S[pk .. ".flow"] = pump.flow / rho * 3600
			S[pk .. ".speed"] = pump.speed * 100
			S[pk .. ".amps"] = pump.power / (P.PUMP_MOTOR_MW * 1e6) * 100
			-- Motor current in amperes: a 6 kV induction motor at 0.88 power factor.
			S[pk .. ".current"] = pump.power / (math.sqrt(3) * 6000 * 0.88)
			S[pk .. ".valve"] = pump.valve * 100
			S[pk .. ".cav"] = if pump.cav > 0.15 then 1 else 0
			S[pk .. ".fail"] = if pump.failed then 1 else 0
		end
	end
	S["pri.flow"] = total * 3.6
end

return Primary
