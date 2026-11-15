--!strict
-- Annunciator logic. Each window follows the usual control-room sequence:
-- a new alarm flashes and sounds the horn until acknowledged, then stays
-- lit steadily until the condition clears.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local AlarmList = require(Shared.AlarmList)
local Config = require(Shared.Config)

local Alarms = {}
Alarms.__index = Alarms

local CLEAR, NEW, ACKED = 0, 1, 2

-- Conditions read the published signal table `S` (and the plant for a few
-- things that are not signals).
local function conditions(plant): { [string]: (S: { [string]: number }) -> boolean }
	local Pr = Config.Protection
	local c: { [string]: (S: { [string]: number }) -> boolean } = {}
	c["rs.press"] = function(S) return S["rs.press"] > 5 end
	c["chan.rupture"] = function(S) return S["core.ruptured"] > 0 end
	c["rad.gas"] = function(S) return S["rad.gas"] > 20 end
	c["cps.flow"] = function(S) return S["cps.flow"] < 50 end
	c["cps.tank"] = function(S) return S["cps.tank"] < 80 end
	c["cps.temp"] = function(S) return S["cps.temp"] > 90 end
	c["eccs"] = function(S) return S["eccs.active"] > 0 end
	c["eccs.off"] = function(S) return S["eccs.auto"] < 1 end
	c["eccs.accum"] = function(S) return S["eccs.accum"] < 90 end
	c["srv.open"] = function(S) return S["srv.1.open"] + S["srv.2.open"] + S["srv.3.open"] > 0 end
	c["pool.temp"] = function(S) return S["pool.temp"] > 45 end
	c["leak"] = function(S) return S["core.ruptured"] > 0 or plant.safety.compartmentLeak end

	c["mcp.cav"] = function(S)
		for l = 1, 2 do
			for i = 1, 4 do
				if S[string.format("mcp.%d%d.cav", l, i)] > 0 then
					return true
				end
			end
		end
		return false
	end
	c["loop1.flow"] = function(S) return S["n.power"] > 5 and S["loop.1.flow"] < 9000 end
	c["loop2.flow"] = function(S) return S["n.power"] > 5 and S["loop.2.flow"] < 9000 end
	c["lvl1.low"] = function(S) return S["loop.1.level"] < -300 end
	c["lvl1.high"] = function(S) return S["loop.1.level"] > 250 end
	c["lvl2.low"] = function(S) return S["loop.2.level"] < -300 end
	c["lvl2.high"] = function(S) return S["loop.2.level"] > 250 end
	c["press.high"] = function(S) return S["pri.press"] > 7.2 end
	c["press.low"] = function(S) return S["n.power"] > 20 and S["pri.press"] < 6.3 end
	c["heatup"] = function(S) return math.abs(S["pri.heatup"]) > Config.Primary.HEATUP_LIMIT * 60 * 1.05 end
	c["subcool"] = function(S)
		return (S["loop.1.npsh"] < 0.13 and S["loop.1.flow"] > 3000) or (S["loop.2.npsh"] < 0.13 and S["loop.2.flow"] > 3000)
	end

	c["az5"] = function(S) return S["az5.active"] > 0 end
	c["az4"] = function(S) return S["az4.active"] > 0 end
	c["az3"] = function(S) return S["az3.active"] > 0 end
	c["az2"] = function(S) return S["az2.active"] > 0 end
	c["az1"] = function(S) return S["az1.active"] > 0 end
	c["power.high"] = function(S) return S["n.power"] > 105 end
	c["period.short"] = function(S) return S["n.period"] > 0 and S["n.period"] < Pr.PERIOD_ALARM and S["n.power"] > 3e-6 end
	c["rod.block"] = function(S) return S["rod.block"] > 0 and S["rod.moving"] < 0 end
	c["orm.low"] = function(S) return S["n.power"] > 1 and S["core.orm"] < Pr.ORM_ADMIN_LIMIT end
	c["orm.lowlow"] = function(S) return S["n.power"] > 1 and S["core.orm"] < Pr.ORM_SHUTDOWN_LIMIT end
	c["ar.limit"] = function(S) return S["ar.limit"] > 0 end
	c["ar.dev"] = function(S) return S["ar.mode"] > 0 and math.abs(S["ar.error"]) > 3 end
	c["lar.limit"] = function(S) return S["lar.limit"] > 0 end
	c["rod.stuck"] = function(S) return S["rod.stuck"] > 0 end
	c["chan.margin"] = function(S) return S["core.minMargin"] < 1.3 end
	c["fuel.temp"] = function(S) return S["core.maxFuel"] > 1800 end
	c["tilt"] = function(S) return S["n.power"] > 10 and S["core.tilt"] > 15 end
	c["axial"] = function(S) return S["n.power"] > 10 and math.abs(S["core.offset"]) > 15 end
	c["kom"] = function(S) return S["kom"] > 0 end
	c["prot.bypass"] = function(S) return S["prot.anyBypass"] > 0 end
	c["chan.flow"] = function(S) return S["core.blocked"] > 0 end
	c["regs.off"] = function(S) return S["n.power"] > 5 and S["ar.mode"] < 1 and S["lar.on"] < 1 end
	c["core.damage"] = function(S) return S["core.damaged"] > 0 or S["core.destroyed"] > 0 end

	c["fw.low"] = function(S) return S["n.power"] > 20 and S["fw.total"] < 0.7 * S["steam.total"] end
	c["fw.temp"] = function(S) return S["n.power"] > 30 and S["fw.temp"] < 140 end
	c["da.low"] = function(S) return S["da.level"] < 25 end
	c["da.high"] = function(S) return S["da.level"] > 90 end
	c["afw"] = function(S) return S["afw.pump.1.run"] + S["afw.pump.2.run"] + S["afw.pump.3.run"] > 0 end
	c["lvl.manual"] = function(S) return S["n.power"] > 10 and (S["lvl.1.auto"] < 1 or S["lvl.2.auto"] < 1) end

	for k = 1, 2 do
		c["tg" .. k .. ".vac"] = function(S) return S["tg." .. k .. ".rpm"] > 50 and S["tg." .. k .. ".vac"] > 15 end
		c["tg" .. k .. ".vib"] = function(S) return S["tg." .. k .. ".vib"] > 7.1 end
		c["tg" .. k .. ".lube"] = function(S) return S["tg." .. k .. ".rpm"] > 20 and S["tg." .. k .. ".lube"] < 0.15 end
		c["tg" .. k .. ".stress"] = function(S) return S["tg." .. k .. ".stress"] > 60 end
	end
	c["bypass.open"] = function(S) return S["tg.1.bypass"] > 2 or S["tg.2.bypass"] > 2 end
	c["ehc.manual"] = function(S) return S["ehc.pressAuto"] < 1 end

	c["bus.dead"] = function(S) return S["bus.dead"] > 0 end
	c["dg.run"] = function(S) return S["dg.1.run"] + S["dg.2.run"] + S["dg.3.run"] > 0 end
	c["grid"] = function(S) return S["grid.live"] < 1 end
	c["gen.island"] = function(S) return S["gen.1.island"] + S["gen.2.island"] > 0 end
	return c
end

function Alarms.new(plant)
	local self = setmetatable({}, Alarms)
	self.plant = plant
	self.cond = conditions(plant)
	self.state = table.create(#AlarmList.list, CLEAR)
	self.pulse = {} -- id -> seconds remaining, for event-type alarms
	self.changed = {} -- indices changed this tick, drained by the network layer
	self.horn = false
	plant.cmd["ann.ack"] = function()
		self:acknowledge()
	end
	return self
end

-- Fire an event-type alarm (a pump trip, say) that has no standing condition.
function Alarms.raise(self, id: string)
	self.pulse[id] = 6
end

function Alarms.acknowledge(self)
	for i, s in self.state do
		if s == NEW then
			self.state[i] = ACKED
			table.insert(self.changed, i)
		end
	end
end

function Alarms.step(self, dt: number)
	local S = self.plant.S
	local horn = false
	for i, alarm in AlarmList.list do
		local on = false
		local fn = self.cond[alarm.id]
		if fn then
			on = fn(S)
		end
		local p = self.pulse[alarm.id]
		if p then
			on = true
			p -= dt
			self.pulse[alarm.id] = if p > 0 then p else nil
		end
		local s = self.state[i]
		if on and s == CLEAR then
			self.state[i] = NEW
			table.insert(self.changed, i)
			self.plant:log("ALARM: " .. string.gsub(alarm.text, "\n", " "))
		elseif not on and s == ACKED then
			self.state[i] = CLEAR
			table.insert(self.changed, i)
		end
		if self.state[i] == NEW then
			horn = true
		end
	end
	self.horn = horn
end

-- Ids that have neither a standing condition nor are known pulse alarms.
function Alarms.unhandled(self, pulseIds: { string }): { string }
	local known = {}
	for _, id in pulseIds do
		known[id] = true
	end
	local out = {}
	for _, alarm in AlarmList.list do
		if not self.cond[alarm.id] and not known[alarm.id] then
			table.insert(out, alarm.id)
		end
	end
	return out
end

return Alarms
