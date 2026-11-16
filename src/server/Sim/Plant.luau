--!strict
-- The whole unit. Owns every subsystem, steps them in order, and exposes two
-- flat interfaces to the rest of the game:
--
--   plant.S[name]            numbers the control room displays
--   plant:command(name, v)   everything an operator can do
--
-- Nothing in here touches Roblox APIs, so the same code runs under the
-- headless tests.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local Config = require(Shared.Config)
local Steam = require(Shared.Steam)
local Util = require(Shared.Util)

local Core = require(script.Parent.Core)
local Rods = require(script.Parent.Rods)
local Primary = require(script.Parent.Primary)
local Secondary = require(script.Parent.Secondary)
local Electrical = require(script.Parent.Electrical)
local Safety = require(script.Parent.Safety)
local Protection = require(script.Parent.Protection)
local Alarms = require(script.Parent.Alarms)
local Failures = require(script.Parent.Failures)

local Plant = {}
Plant.__index = Plant

Plant.MAP_MODES = { "FLUX", "POWER", "MARGIN", "FLOW", "QUALITY", "FUEL T", "XENON", "GRAPHITE" }

export type Options = {
	seed: number?,
	age: number?, -- 0 = young core, 1 = equilibrium burnup
	hoursSinceShutdown: number?, -- sets how much xenon is left at start
	failures: boolean?,
	yield: (() -> ())?,
}

local function nominalConditions()
	local p = Config.Primary.NOMINAL_PRESSURE + Config.Primary.RISER_HEAD
	local hf = Steam.hf(Config.Primary.NOMINAL_PRESSURE)
	local sub = (Config.Secondary.STEAM_NOMINAL / 2) / Config.Primary.LOOP_RATED_FLOW * (hf - Steam.hLiquid(Config.Secondary.FEEDWATER_TEMP))
	return {
		pressure = { p, p },
		inletEnthalpy = { hf - sub, hf - sub },
		flow = { Config.Primary.LOOP_RATED_FLOW, Config.Primary.LOOP_RATED_FLOW },
	}
end
Plant.nominalConditions = nominalConditions

function Plant.new(opts: Options?)
	local o: Options = opts or {}
	local self = setmetatable({}, Plant)
	local seed = o.seed or 1
	self.rng = Util.rng(seed * 7919 + 13)
	self.S = {} :: { [string]: number }
	self.cmd = {} :: { [string]: (v: number, who: any?) -> () }
	self.holds = {} :: { [string]: number }
	self.time = 0
	self.logLines = {} :: { { t: number, text: string } }
	self.logSeq = 0
	self.mapMode = 1
	self.stats = { energy = 0, scrams = 0, autoSeconds = 0, violations = 0 }

	-- The core is designed at full power with equilibrium xenon, then given
	-- its shutdown history and cooled down.
	local age = o.age or self.rng:range(0.55, 1.0)
	self.age = age
	self.core = Core.new({ seed = seed, age = age })
	local core = self.core
	core:design(nominalConditions(), o.yield)

	local hours = o.hoursSinceShutdown or self.rng:range(40, 110)
	self.hoursSinceShutdown = hours
	core:evolve(hours, 0, nominalConditions(), 1800)
	for i, g in Config.Core.DECAY do
		core.decay[i] *= math.exp(-hours * 3600 / g[2])
	end
	if o.yield then
		o.yield()
	end

	self.rods = Rods.new(self)
	for z = 1, 12 do
		self.rods.zoneRef[z] = core.designZonePower[z]
	end
	self.primary = Primary.new(self)
	self.secondary = Secondary.new(self)
	self.elec = Electrical.new(self)
	self.safety = Safety.new(self)
	self.protection = Protection.new(self)
	self.alarms = Alarms.new(self)
	self.failures = Failures.new(self)
	self.failures.enabled = o.failures ~= false

	-- Cold shutdown: every rod in, cooldown system holding temperature.
	local pri = self.primary
	pri.temp = 55
	pri.cooldownOn = true
	core:resetCold(pri.temp, true)
	for i = 1, core.NR do
		core:setRodPosition(i, self.rods.stroke[i])
	end
	local cond = pri:hydraulics(0.1)
	core:distributeFlow(cond)
	core:thermal(0, cond, 0)
	core:settle(80)
	core.fission = math.max(1, Config.Core.SOURCE * Config.Core.LAMBDA_PROMPT / math.max(1e-4, -core.rho))
	core:equilibratePrecursors()
	core:distributePower()
	core:slow(0)

	self.cmd["map.mode"] = function(v)
		self.mapMode = Util.clamp(math.floor(v), 1, #Plant.MAP_MODES)
	end
	self.cmd["failures.enable"] = function(v)
		self.failures.enabled = v >= 0.5
	end

	-- Let natural circulation and the cooldown system find their balance,
	-- then start the clock with a clean log and annunciator board.
	local failuresOn = self.failures.enabled
	self.failures.enabled = false
	for i = 1, 400 do
		self:step(0.1)
		if o.yield and i % 50 == 0 then
			o.yield()
		end
	end
	self.failures.enabled = failuresOn
	self.time = 0
	table.clear(self.logLines)
	table.clear(self.alarms.changed)
	for i in self.alarms.state do
		self.alarms.state[i] = 0
	end
	self.stats = { energy = 0, scrams = 0, autoSeconds = 0, violations = 0 }
	self.rods.autoSeconds = 0
	self.secondary.autoSeconds = 0
	self.primary.stress = 0

	self:log(string.format("Unit in cold shutdown. Core burnup index %.0f%%, %.0f h since shutdown, xenon %.2f%%.", age * 100, hours, core.xenonWorth * 100))
	self:publish()
	return self
end

function Plant.log(self, text: string)
	self.logSeq += 1
	table.insert(self.logLines, { t = self.time, text = text, seq = self.logSeq } :: any)
	if #self.logLines > 250 then
		table.remove(self.logLines, 1)
	end
end

function Plant.raise(self, id: string)
	self.alarms:raise(id)
end

function Plant.busLive(self, name: string): boolean
	return self.elec:busLive(name)
end

function Plant.busFrequency(self, name: string): number
	return self.elec:busFrequency(name)
end

-- Run an operator command. Returns false for an unknown command.
function Plant.command(self, name: string, value: number, who: any?): boolean
	local fn = self.cmd[name]
	if not fn then
		return false
	end
	fn(value, who)
	return true
end

-- A command that is held (a raise/lower switch, the rod motion switch).
-- The control room re-sends it while held; if the refresh stops, it is
-- released here so nothing keeps moving after a player disconnects.
function Plant.hold(self, name: string, value: number, who: any?): boolean
	if not self.cmd[name] then
		return false
	end
	self.cmd[name](value, who)
	self.holds[name] = if value ~= 0 then self.time + 0.8 else nil
	return true
end

function Plant.step(self, dt: number)
	self.time += dt
	for name, expires in self.holds do
		if self.time >= expires then
			self.holds[name] = nil
			self.cmd[name](0)
		end
	end

	local core = self.core
	self.elec:step(dt)
	local cond = self.primary:hydraulics(dt)
	self.rods.drivePower = self:busLive("E1") or self:busLive("E2")
	self.rods:step(dt)
	core:step(dt, cond)
	self.secondary:step(dt)
	self.primary:thermal(dt)
	self.safety:step(dt)
	self.protection:step(dt)
	self.failures:step(dt)

	-- Main circulation pump motors load their buses.
	for l = 1, 2 do
		for _, pump in self.primary.pumps[l] do
			if pump.on then
				self.elec:addLoad(pump.bus, pump.power)
			end
		end
	end

	for _, ev in core.events do
		if ev.kind == "rupture" then
			local c = core.fuelCell[ev.channel]
			self:log(string.format("FUEL CHANNEL %02d-%02d RUPTURED (%s)", core.layout.cellGX[c], core.layout.cellGY[c], ev.cause))
		elseif ev.kind == "destroyed" then
			self:log("REACTOR DESTROYED: " .. ev.cause)
			self.rods:jamAll()
		end
	end
	table.clear(core.events)

	self.stats.energy += self.elec.gross * dt / 3.6e9
	self.stats.scrams = self.protection.scrams
	self.stats.autoSeconds = self.rods.autoSeconds + self.secondary.autoSeconds
	if math.abs(self.primary.heatupRate) > Config.Primary.HEATUP_LIMIT * 1.05 then
		self.stats.violations += dt
	end
	if core.thermalPower > 0.02 * Config.NOMINAL_THERMAL and core.orm < Config.Protection.ORM_SHUTDOWN_LIMIT then
		self.stats.violations += dt
	end

	self:publish()
	self.alarms:step(dt)
end

function Plant.publish(self)
	local S = self.S
	local core = self.core
	local frac = core.fission / Config.NOMINAL_THERMAL
	S["time"] = self.time
	S["n.power"] = frac * 100
	S["n.log"] = math.log10(math.max(frac, 1e-11))
	S["n.cps"] = math.min(1e6, 1.2e10 * frac)
	S["n.logcps"] = math.log10(math.max(1, math.min(1e6, 1.2e10 * frac)))
	local period = core.period
	if period ~= period or math.abs(period) > 999 then
		period = 999
	end
	S["n.period"] = period
	-- Startup rate in decades per minute, the usual control-room form.
	S["n.sur"] = if math.abs(period) >= 999 then 0 else Util.clamp(26.06 / period, -1, 5)
	S["n.thermal"] = core.thermalPower / 1e6
	S["n.heat"] = (core.loopHeat[1] + core.loopHeat[2]) / 1e6
	S["n.rho"] = core.rho / core.beta
	S["core.orm"] = core.orm
	S["core.kr"] = if core.thermalPower > 0 then core.maxChannelPower / (core.thermalPower / core.NF) else 0
	local maxFlux = 0
	for f = 1, core.NF do
		local v = core.fluxRel[f]
		if v > maxFlux then
			maxFlux = v
		end
	end
	S["core.fluxPeak"] = maxFlux
	local kz, top, bottom = 0, 0, 0
	local NZ = core.NZ
	for z = 1, NZ do
		local a = core.axial[z]
		S["core.ax" .. z] = a
		if a > kz then
			kz = a
		end
		if z <= NZ / 2 then
			top += a
		else
			bottom += a
		end
	end
	S["core.kz"] = kz
	S["core.offset"] = if top + bottom > 0 then (top - bottom) / (top + bottom) * 100 else 0
	local tilt = 0
	for z = 1, 12 do
		local ref = self.rods.zoneRef[z]
		local rel = if ref > 0 then core.zonePower[z] / ref else 1
		S["core.zone" .. z] = rel * 100
		tilt = math.max(tilt, math.abs(rel - 1) * 100)
	end
	S["core.tilt"] = tilt
	S["core.xenon"] = core.xenonWorth * 100
	S["core.void"] = core.voidCoefCore / core.beta
	S["core.maxFuel"] = core.maxFuelTemp
	S["core.maxClad"] = core.maxCladTemp
	S["core.minMargin"] = math.min(core.minMargin, 9.9)
	S["core.maxChannel"] = core.maxChannelPower / 1e6
	S["core.fuelT"] = core.avgFuelTemp
	S["core.graphT"] = core.avgGraphiteTemp
	S["core.ruptured"] = core.nRuptured
	S["core.damaged"] = core.nFuelDamaged
	S["core.destroyed"] = if core.destroyed then 1 else 0
	S["core.blocked"] = self.failures:blockedCount()
	S["core.steam"] = (core.loopSteam[1] + core.loopSteam[2]) * 3.6
	S["map.mode"] = self.mapMode
	S["horn"] = if self.alarms.horn then 1 else 0
	S["stats.energy"] = self.stats.energy
	S["stats.scrams"] = self.stats.scrams
	self.rods:publish(S)
	self.primary:publish(S)
	self.secondary:publish(S)
	self.elec:publish(S)
	self.safety:publish(S)
	self.protection:publish(S)
end

-- Snapshot of the core for the map display: one byte per lattice cell for
-- the selected quantity, one for its condition, then one flag byte per rod.
function Plant.mapBuffer(self): buffer
	local core = self.core
	local L = core.layout
	local NC, NR, NZ = core.NC, core.NR, core.NZ
	local buf = buffer.create(1 + NC * 2 + NR)
	local mode = self.mapMode
	buffer.writeu8(buf, 0, mode)
	local tsat = Steam.tsat(self.primary.pressure)
	for c = 1, NC do
		local value, flag = 0, 0
		local ref = L.cellRef[c]
		if L.cellKind[c] == 2 then
			value = core.rodPos[ref] / self.rods.stroke[ref] * 255
		else
			local f = ref
			if mode == 1 then
				value = core.fluxRel[f] / 2.5 * 255
			elseif mode == 2 then
				value = core.power[f] / 3.2e6 * 255
			elseif mode == 3 then
				value = core.margin[f] / 4 * 255
			elseif mode == 4 then
				value = core.flow[f] / 9 * 255
			elseif mode == 5 then
				value = core.xExit[f] / 0.4 * 255
			elseif mode == 6 then
				value = core.tfMax[f] / 2000 * 255
			else
				local base = (c - 1) * NZ
				local s = 0
				local arr = if mode == 7 then core.xe else core.tg
				for z = 1, NZ do
					s += arr[base + z]
				end
				value = if mode == 7 then s / NZ / 2.5 * 255 else s / NZ / 800 * 255
			end
			if core.status[f] ~= 0 then
				flag = 1
			elseif self.failures.blocked[f] then
				flag = 2
			elseif core.cladT[f] > tsat + 80 then
				flag = 3
			end
		end
		buffer.writeu8(buf, c, math.floor(Util.clamp(value, 0, 255)))
		buffer.writeu8(buf, NC + c, flag)
	end
	local rods = self.rods
	for i = 1, NR do
		local flag = 0
		if rods.selected[i] then
			flag += 1
		end
		if rods.stuck[i] then
			flag += 2
		end
		local v = rods.velocity[i]
		if v > 0 then
			flag += 4
		elseif v < 0 then
			flag += 8
		end
		if rods:isAuto(i) then
			flag += 16
		end
		buffer.writeu8(buf, 2 * NC + i, flag)
	end
	return buf
end

return Plant
