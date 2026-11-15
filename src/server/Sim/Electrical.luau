--!strict
-- Electrical system.
--
-- Each turbine-generator connects through its generator breaker (GCB) to a
-- unit bus; the unit bus reaches the 345 kV grid through the main
-- transformer and a switchyard breaker, and feeds two 6.9 kV auxiliary buses
-- through the unit auxiliary transformer. Every auxiliary bus also has a
-- reserve feed from the startup transformer. Three emergency buses hang off
-- auxiliary buses and each has a diesel generator.
--
-- With the switchyard breaker open and the generator breaker closed, a
-- coasting turbine keeps feeding its own auxiliary buses at falling
-- frequency: the "rundown" mode the 1986 test was about.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Electrical = {}
Electrical.__index = Electrical

local HZ = Config.GRID_HZ
local AUX = { "1A", "1B", "2A", "2B" }
local EMERGENCY = { { name = "E1", parent = "1A" }, { name = "E2", parent = "1B" }, { name = "E3", parent = "2A" } }
local RIDE_THROUGH = 1.5 -- seconds a motor stays connected through a dead bus

function Electrical.new(plant)
	local self = setmetatable({}, Electrical)
	self.plant = plant
	self.grid = { live = true, freq = HZ, volts = 1.0 }
	self.gens = {}
	for k = 1, 2 do
		self.gens[k] = {
			field = false,
			vset = 1.0,
			vdir = 0,
			volts = 0,
			freq = 0,
			gcb = false,
			yard = true,
			mode = "open", -- "open" | "grid" | "island"
			pe = 0, -- electrical power drawn from the shaft, W
			mvar = 0,
			angle = 0,
			reverse = 0,
			unitLive = false,
			unitFreq = 0,
			unitLoad = 0,
			tripped = false,
		}
	end
	self.buses = {}
	for i, name in AUX do
		self.buses[name] = {
			unit = if i <= 2 then 1 else 2,
			normal = false,
			reserve = true,
			ats = true,
			live = true,
			freq = HZ,
			dead = 0,
			load = 0,
			loadNext = 0,
			onReserve = true,
		}
	end
	self.ebus = {}
	for i, e in EMERGENCY do
		self.ebus[e.name] = {
			index = i,
			parent = e.parent,
			tie = true,
			live = true,
			freq = HZ,
			dead = 0,
			load = 0,
			loadNext = 0,
			dgMode = 1, -- 0 off, 1 auto, 2 run
			dgState = 0, -- 0 standby, 1 starting, 2 running, 3 failed
			dgSpeed = 0,
			dgBreaker = false,
			dgTimer = 0,
			dgWillFail = false,
			parentBack = 0,
		}
	end
	self.syncSelect = 0
	self.syncBypass = false
	self.gross = 0
	self.aux = 0

	local c = plant.cmd
	for k = 1, 2 do
		local g = self.gens[k]
		local key = "gen." .. k
		c[key .. ".field"] = function(v)
			g.field = v >= 0.5
		end
		c[key .. ".volt"] = function(v)
			g.vdir = if v > 0.5 then 1 elseif v < -0.5 then -1 else 0
		end
		c[key .. ".gcb"] = function(v)
			if v >= 0.5 then
				self:closeGcb(k)
			else
				self:openGcb(k, "opened by operator")
			end
		end
		c[key .. ".yard"] = function(v)
			local close = v >= 0.5
			if close and not g.yard and g.gcb and g.mode == "island" then
				-- Reconnecting an islanded unit needs the same care as the
				-- generator breaker.
				if not self:syncOk(k) and not self.syncBypass then
					plant:log(string.format("Switchyard breaker %d blocked by sync check", k))
					return
				end
			end
			if close ~= g.yard then
				g.yard = close
				plant:log(string.format("Switchyard breaker %d %s", k, if close then "closed" else "opened"))
			end
		end
	end
	c["sync.select"] = function(v)
		self.syncSelect = Util.clamp(math.floor(v), 0, 2)
	end
	c["sync.bypass"] = function(v)
		self.syncBypass = v >= 0.5
	end
	for _, name in AUX do
		local b = self.buses[name]
		c["bus." .. name .. ".normal"] = function(v)
			b.normal = v >= 0.5
		end
		c["bus." .. name .. ".reserve"] = function(v)
			b.reserve = v >= 0.5
		end
		c["bus." .. name .. ".ats"] = function(v)
			b.ats = v >= 0.5
		end
	end
	for _, e in EMERGENCY do
		local b = self.ebus[e.name]
		local i = b.index
		c["dg." .. i .. ".mode"] = function(v)
			b.dgMode = Util.clamp(math.floor(v), 0, 2)
		end
		c["ebus." .. i .. ".tie"] = function(v)
			b.tie = v >= 0.5
		end
	end
	return self
end

function Electrical.busLive(self, name: string): boolean
	local b = self.buses[name] or self.ebus[name]
	if not b then
		return false
	end
	return b.live or b.dead < RIDE_THROUGH
end

function Electrical.busFrequency(self, name: string): number
	local b = self.buses[name] or self.ebus[name]
	if not b or not b.live then
		return 0
	end
	return b.freq
end

-- Consumers call this every tick while they are running.
function Electrical.addLoad(self, name: string, watts: number)
	local b = self.buses[name] or self.ebus[name]
	if b then
		b.loadNext += watts
	end
end

function Electrical.syncOk(self, k: number): boolean
	local g = self.gens[k]
	local a = g.angle
	if a > 180 then
		a -= 360
	end
	return math.abs(g.freq - self.grid.freq) < 0.15 and math.abs(a) < 15 and math.abs(g.volts - self.grid.volts) < 0.05
end

function Electrical.closeGcb(self, k: number)
	local g = self.gens[k]
	local plant = self.plant
	if g.gcb then
		return
	end
	if g.volts < 0.8 then
		plant:log(string.format("Generator %d breaker will not close: no field", k))
		return
	end
	local busFromGrid = g.yard and self.grid.live
	if busFromGrid then
		if not self:syncOk(k) then
			if not self.syncBypass then
				plant:log(string.format("Generator %d breaker blocked by sync check", k))
				return
			end
			-- Out-of-phase closure: a violent torque on the shaft.
			local a = math.rad(g.angle)
			local severity = math.abs(math.sin(a / 2)) + math.abs(g.freq - self.grid.freq) / 3
			plant:log(string.format("GENERATOR %d CLOSED OUT OF PHASE", k))
			plant.secondary:shock(k, severity)
			if severity > 0.25 then
				plant.secondary:tripTurbine(k, "generator fault")
				plant:raise("gen." .. k .. ".fault")
				return
			end
		end
	end
	g.gcb = true
	g.reverse = 0
	plant:log(string.format("Generator %d breaker closed%s", k, if busFromGrid then " - synchronised" else " on dead bus"))
	if busFromGrid then
		plant.secondary:onSynchronised(k)
	end
end

function Electrical.openGcb(self, k: number, why: string)
	local g = self.gens[k]
	if g.gcb then
		g.gcb = false
		self.plant:log(string.format("Generator %d breaker %s", k, why))
	end
end

function Electrical.step(self, dt: number)
	local plant = self.plant
	local sec = plant.secondary
	local grid = self.grid

	-- Roll the load accumulators.
	for _, b in self.buses do
		b.load = b.loadNext
		b.loadNext = 0
	end
	for _, b in self.ebus do
		b.load = b.loadNext
		b.loadNext = 0
	end

	-- Generators and unit buses.
	for k = 1, 2 do
		local g = self.gens[k]
		local speed = sec.turbines[k].speed
		g.vset = Util.clamp(g.vset + g.vdir * 0.01 * dt, 0.90, 1.10)
		g.freq = speed * HZ
		-- The regulator holds terminal volts until the machine is too slow.
		local volts = if g.field then g.vset * math.min(1, speed / 0.92) else 0
		g.volts = Util.lag(g.volts, volts, dt, 0.8)
		local gridSide = g.yard and grid.live
		local genSide = g.gcb and g.volts > 0.7
		if g.gcb and gridSide then
			g.mode = "grid"
			g.unitLive, g.unitFreq = true, grid.freq
		elseif genSide then
			g.mode = "island"
			g.unitLive, g.unitFreq = true, g.freq
		else
			g.mode = "open"
			g.unitLive, g.unitFreq = gridSide, if gridSide then grid.freq else 0
		end
		if g.gcb and not g.field and g.mode == "grid" then
			self:openGcb(k, "tripped: loss of field")
			sec:tripTurbine(k, "generator loss of field")
			plant:raise("gen." .. k .. ".fault")
		end
		if g.gcb and g.mode == "open" and not gridSide then
			-- Collapsed island.
			self:openGcb(k, "tripped: undervoltage")
		end
		-- Synchroscope: angle of the machine relative to the system.
		g.angle = (g.angle + (g.freq - grid.freq) * 360 * dt) % 360
	end

	-- Auxiliary buses.
	local unitLoad = { 0, 0 }
	for _, name in AUX do
		local b = self.buses[name]
		local g = self.gens[b.unit]
		local fromUnit = b.normal and g.unitLive
		local fromReserve = b.reserve and grid.live
		if fromReserve then
			b.live, b.freq, b.onReserve = true, grid.freq, true
		elseif fromUnit then
			b.live, b.freq, b.onReserve = true, g.unitFreq, false
		else
			b.live, b.freq = false, 0
		end
		if b.live then
			b.dead = 0
		else
			b.dead += dt
			-- Automatic transfer to the reserve feed.
			if b.ats and grid.live and b.dead > 0.6 and not b.reserve then
				b.reserve = true
				b.normal = false
				plant:log("Bus " .. name .. " transferred to reserve feed")
				plant:raise("bus.reserve")
			end
		end
	end

	-- Emergency buses and diesels.
	for _, e in EMERGENCY do
		local b = self.ebus[e.name]
		local parent = self.buses[b.parent]
		local fromParent = b.tie and parent.live
		-- Diesel state machine.
		local want = b.dgMode == 2 or (b.dgMode == 1 and (not parent.live and parent.dead > 2 or b.dgBreaker))
		if b.dgMode == 0 then
			want = false
		end
		if b.dgState == 0 and want then
			b.dgState = 1
			b.dgTimer = 0
			plant:log(string.format("Diesel generator %d starting", b.index))
		elseif b.dgState == 1 then
			b.dgTimer += dt
			b.dgSpeed = math.min(1, b.dgTimer / 12)
			if b.dgWillFail and b.dgTimer > 4 then
				b.dgState = 3
				b.dgSpeed = 0
				b.dgWillFail = false
				plant:log(string.format("Diesel generator %d FAILED TO START", b.index))
				plant:raise("dg.fail")
			elseif b.dgTimer >= 12 then
				b.dgState = 2
				plant:log(string.format("Diesel generator %d at rated speed", b.index))
			end
			if not want then
				b.dgState = 0
			end
		elseif b.dgState == 2 then
			if not want then
				b.dgState = 0
				b.dgBreaker = false
				plant:log(string.format("Diesel generator %d stopped", b.index))
			end
		elseif b.dgState == 3 and b.dgMode == 0 then
			b.dgState = 0 -- reset by switching to OFF
		end
		if b.dgState ~= 2 and b.dgState ~= 1 then
			b.dgSpeed = math.max(0, b.dgSpeed - dt / 8)
		end
		-- Breaker logic in AUTO: pick up the bus when the parent is dead,
		-- hand it back after the parent has been healthy for a while.
		if b.dgState == 2 and b.dgMode >= 1 and not fromParent and not b.dgBreaker then
			b.tie = false
			b.dgBreaker = true
			plant:log(string.format("Diesel generator %d feeding bus %s", b.index, e.name))
		end
		if b.dgBreaker and parent.live then
			b.parentBack += dt
			if b.parentBack > 30 and b.dgMode == 1 then
				b.dgBreaker = false
				b.tie = true
				plant:log(string.format("Bus %s returned to normal feed", e.name))
			end
		else
			b.parentBack = 0
		end
		if b.dgState ~= 2 then
			b.dgBreaker = false
		end
		if b.dgBreaker then
			b.live, b.freq = true, HZ
		elseif b.tie and parent.live then
			b.live, b.freq = true, parent.freq
		else
			b.live, b.freq = false, 0
		end
		b.dead = if b.live then 0 else b.dead + dt
		if b.live and not b.dgBreaker then
			parent.load += b.load
		end
	end

	-- Power drawn from each unit by its own auxiliaries.
	local aux = 0
	for _, name in AUX do
		local b = self.buses[name]
		aux += b.load
		if b.live and not b.onReserve then
			unitLoad[b.unit] += b.load
		end
	end
	self.aux = aux

	local gross = 0
	for k = 1, 2 do
		local g = self.gens[k]
		local t = sec.turbines[k]
		g.unitLoad = unitLoad[k]
		if g.mode == "grid" then
			g.pe = t.shaftPower
			g.mvar = (g.volts - grid.volts) * 900
			-- Motoring: the reverse power relay opens the breaker.
			if g.pe < -3e6 then
				g.reverse += dt
				if g.reverse > 3 then
					self:openGcb(k, "tripped: reverse power")
				end
			else
				g.reverse = 0
			end
		elseif g.mode == "island" then
			g.pe = unitLoad[k]
			g.mvar = 0
		else
			g.pe = 0
			g.mvar = 0
			g.reverse = 0
		end
		if g.gcb then
			gross += g.pe
		end
	end
	self.gross = gross
end

function Electrical.publish(self, S)
	local running = 0
	for k = 1, 2 do
		local g = self.gens[k]
		local key = "gen." .. k
		S[key .. ".mw"] = if g.gcb then g.pe / 1e6 else 0
		S[key .. ".mvar"] = g.mvar
		S[key .. ".kv"] = g.volts * 22
		S[key .. ".hz"] = g.freq
		S[key .. ".gcb"] = if g.gcb then 1 else 0
		S[key .. ".yard"] = if g.yard then 1 else 0
		S[key .. ".field"] = if g.field then 1 else 0
		S[key .. ".island"] = if g.mode == "island" then 1 else 0
		S[key .. ".unitLive"] = if g.unitLive then 1 else 0
		if g.gcb and g.mode == "grid" then
			running += 1
		end
	end
	S["gen.onGrid"] = running
	local sel = self.gens[self.syncSelect]
	S["sync.select"] = self.syncSelect
	S["sync.bypass"] = if self.syncBypass then 1 else 0
	if sel and sel.volts > 0.5 and sel.yard and self.grid.live and not sel.gcb then
		S["sync.angle"] = sel.angle
		S["sync.df"] = sel.freq - self.grid.freq
		S["sync.dv"] = (sel.volts - self.grid.volts) * 100
		S["sync.ok"] = if self:syncOk(self.syncSelect) then 1 else 0
		S["sync.on"] = 1
	else
		S["sync.angle"] = 0
		S["sync.df"] = 0
		S["sync.dv"] = 0
		S["sync.ok"] = 0
		S["sync.on"] = 0
	end
	local dead = 0
	for _, name in AUX do
		local b = self.buses[name]
		local key = "bus." .. name
		S[key .. ".live"] = if b.live then 1 else 0
		S[key .. ".kv"] = if b.live then 6.9 else 0
		S[key .. ".hz"] = b.freq
		S[key .. ".mw"] = b.load / 1e6
		S[key .. ".normal"] = if b.normal then 1 else 0
		S[key .. ".reserve"] = if b.reserve then 1 else 0
		S[key .. ".ats"] = if b.ats then 1 else 0
		if not b.live then
			dead += 1
		end
	end
	S["bus.dead"] = dead
	for _, e in EMERGENCY do
		local b = self.ebus[e.name]
		local i = b.index
		S["ebus." .. i .. ".live"] = if b.live then 1 else 0
		S["ebus." .. i .. ".tie"] = if b.tie then 1 else 0
		S["dg." .. i .. ".mode"] = b.dgMode
		S["dg." .. i .. ".state"] = b.dgState
		S["dg." .. i .. ".run"] = if b.dgState == 2 then 1 else 0
		S["dg." .. i .. ".hz"] = b.dgSpeed * HZ
		S["dg." .. i .. ".bkr"] = if b.dgBreaker then 1 else 0
	end
	S["grid.live"] = if self.grid.live then 1 else 0
	S["grid.hz"] = self.grid.freq
	S["plant.gross"] = self.gross / 1e6
	S["plant.aux"] = self.aux / 1e6
	S["plant.net"] = (self.gross - self.aux) / 1e6
end

return Electrical
