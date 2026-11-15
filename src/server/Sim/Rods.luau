--!native
--!optimize 2
-- Control and protection system: rod drives, manual selection and motion,
-- the automatic regulators (AR-1/2/3 and the twelve local regulators), the
-- AZ protection actions and the clutch release key (KOM).
--
-- Pre-1986 behaviour is kept on purpose: rods travel at 0.4 m/s whatever
-- the emergency, the shortened bottom-entry rods (USP) do not move on AZ-5,
-- and the regulator setpoint does not follow the reactor when a regulator
-- is switched off, so engaging one with a mismatch drags the power with it.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local R = Config.Rods

local Rods = {}
Rods.__index = Rods

local RUNBACK_TARGET = { 0.60, 0.50, 0.20 } -- AZ-1, AZ-2, AZ-3

function Rods.new(plant)
	local self = setmetatable({}, Rods)
	local core = plant.core
	local L = core.layout
	self.plant = plant
	self.core = core
	self.NR = core.NR
	self.kind = {}
	self.group = {}
	self.label = {}
	self.stroke = {}
	self.selected = table.create(self.NR, false)
	self.selCount = 0
	self.stuck = table.create(self.NR, false)
	self.velocity = table.create(self.NR, 0)
	self.byKind = { RR = {}, AR = {}, LAR = {}, AZ = {}, USP = {} }
	self.arGroups = { {}, {}, {} }
	self.larRod = table.create(12, 0)
	for i, rod in L.rods do
		self.kind[i] = rod.kind
		self.group[i] = rod.group
		self.label[i] = rod.label
		self.stroke[i] = if rod.kind == "USP" then R.USP_STROKE else R.STROKE
		table.insert(self.byKind[rod.kind], i)
		if rod.kind == "AR" then
			table.insert(self.arGroups[rod.group], i)
		elseif rod.kind == "LAR" then
			self.larRod[rod.group] = i
		end
	end

	self.manual = 0 -- -1 withdraw, +1 insert
	self.quadSelect = false
	self.az5 = false
	self.az4 = false
	self.runback = 0 -- 0 none, 1..3 = AZ-1..AZ-3 latched
	self.runbackDone = true
	self.kom = false
	self.drivePower = true
	self.arMode = 0 -- 0 off, 1..3
	self.setpoint = 0 -- fraction of nominal power
	self.setpointDir = 0
	self.arError = 0
	self.arAtLimit = false
	self.larOn = false
	self.larAtLimit = false
	self.zoneRef = table.create(12, 1 / 12)
	self.zoneAbs = table.create(12, 0)
	self.blockBypass = false
	self.azInterlockBypass = false
	self.rodBlock = 0 -- 0 none, otherwise a reason code
	self.azRodsOut = false
	self.allIn = true
	self.autoSeconds = 0 -- time spent under automatic regulation (for scoring)

	local c = plant.cmd
	c["rod.select"] = function(v)
		self:toggleSelect(math.floor(v))
	end
	c["rod.clear"] = function()
		self:clearSelection()
	end
	c["rod.group"] = function(v)
		local names = { "AZ", "USP", "AR", "LAR" }
		self:selectKind(names[math.floor(v)] or "")
	end
	c["rod.quad"] = function(v)
		self.quadSelect = v >= 0.5
	end
	c["rod.move"] = function(v)
		self.manual = if v > 0.5 then 1 elseif v < -0.5 then -1 else 0
	end
	c["rod.blockBypass"] = function(v)
		self.blockBypass = v >= 0.5
	end
	c["rod.azInterlockBypass"] = function(v)
		self.azInterlockBypass = v >= 0.5
	end
	c["kom"] = function(v)
		local on = v >= 0.5
		if on and not self.kom then
			plant:log("KOM: rod drive clutches de-energised")
		end
		self.kom = on
	end
	c["ar.mode"] = function(v)
		local mode = Util.clamp(math.floor(v), 0, 3)
		if mode ~= self.arMode then
			self.arMode = mode
			plant:log(if mode == 0 then "Automatic regulator OFF" else string.format("Automatic regulator AR-%d ON", mode))
		end
	end
	c["ar.sp"] = function(v)
		self.setpointDir = if v > 0.5 then 1 elseif v < -0.5 then -1 else 0
	end
	c["lar.sw"] = function(v)
		local on = v >= 0.5
		if on ~= self.larOn then
			self.larOn = on
			plant:log(if on then "Local automatic regulators ON" else "Local automatic regulators OFF")
		end
	end
	return self
end

function Rods.clearSelection(self)
	for i = 1, self.NR do
		self.selected[i] = false
	end
	self.selCount = 0
end

local function addSel(self, i: number)
	if not self.selected[i] then
		self.selected[i] = true
		self.selCount += 1
	end
end

-- The three other rods of the same kind closest to this rod's position
-- turned through 90, 180 and 270 degrees about the core centre.
function Rods.quadPartners(self, i: number): { number }
	local L = self.core.layout
	local cell = L.rods[i].cell
	local x, y = L.cellX[cell], L.cellY[cell]
	local out = {}
	local used = { [i] = true }
	for _, t in { { -y, x }, { -x, -y }, { y, -x } } do
		local best, bestD = 0, math.huge
		for _, j in self.byKind[self.kind[i]] do
			if not used[j] then
				local c = L.rods[j].cell
				local dx, dy = L.cellX[c] - t[1], L.cellY[c] - t[2]
				local d = dx * dx + dy * dy
				if d < bestD then
					best, bestD = j, d
				end
			end
		end
		if best > 0 and bestD <= 8 then
			used[best] = true
			table.insert(out, best)
		end
	end
	return out
end

function Rods.toggleSelect(self, i: number)
	if i < 1 or i > self.NR then
		return
	end
	local members = { i }
	if self.quadSelect then
		for _, j in self:quadPartners(i) do
			table.insert(members, j)
		end
	end
	if self.selected[i] then
		for _, j in members do
			if self.selected[j] then
				self.selected[j] = false
				self.selCount -= 1
			end
		end
		return
	end
	for _, j in members do
		if self.selCount < R.MAX_SELECTED then
			addSel(self, j)
		end
	end
end

-- Group buttons select a whole family at once (used to cock the shutdown
-- rods or to move the shortened rods together).
function Rods.selectKind(self, kind: string)
	local list = self.byKind[kind]
	if not list then
		return
	end
	self:clearSelection()
	for _, i in list do
		addSel(self, i)
	end
end

function Rods.isAuto(self, i: number): boolean
	local k = self.kind[i]
	if k == "AR" then
		return self.arMode == self.group[i]
	elseif k == "LAR" then
		return self.larOn
	end
	return false
end

-- Protection actions, called by the protection logic.
function Rods.tripAz5(self)
	self.az5 = true
end

function Rods.setAz4(self, active: boolean)
	self.az4 = active
end

function Rods.tripRunback(self, level: number)
	if level > self.runback then
		self.runback = level
		self.runbackDone = false
		self.setpoint = math.min(self.setpoint, RUNBACK_TARGET[level])
	end
end

function Rods.resetProtection(self)
	self.az5 = false
	self.runback = 0
	self.runbackDone = true
end

function Rods.jam(self, i: number)
	self.stuck[i] = true
end

function Rods.jamAll(self)
	for i = 1, self.NR do
		self.stuck[i] = true
	end
end

function Rods.step(self, dt: number)
	local core = self.core
	local NR = self.NR
	local power = core.fission / Config.NOMINAL_THERMAL
	local pos = core.rodPos

	-- Regulator setpoint device: about 15% of nominal per minute, slower
	-- in the low range where a small change is a big ratio.
	if self.setpointDir ~= 0 then
		local rate = if self.setpoint < 0.05 then math.max(self.setpoint, 0.0005) * 0.06 else 0.0025
		self.setpoint = Util.clamp(self.setpoint + self.setpointDir * rate * dt, 0, 1.10)
	end

	-- Zone powers for the local regulators.
	local zoneAbs = self.zoneAbs
	for z = 1, 12 do
		zoneAbs[z] = 0
	end
	local fuelZone, chPower = core.fuelZone, core.power
	for f = 1, core.NF do
		zoneAbs[fuelZone[f]] += chPower[f]
	end
	local nominal = Config.NOMINAL_THERMAL

	-- Automatic regulator demand, metres per second (+ = insert).
	local arSpeed = 0
	self.arError = power - self.setpoint
	if self.arMode == 3 then
		local sp = math.max(self.setpoint, 1e-6)
		local e = (power - sp) / sp
		if math.abs(e) > 0.02 then
			arSpeed = Util.clamp(e * 2.0, -1, 1) * R.SPEED_AUTO
		end
	elseif self.arMode > 0 then
		local e = power - self.setpoint
		if math.abs(e) > 0.003 then
			arSpeed = Util.clamp(e * 50, -1, 1) * R.SPEED_AUTO
		end
	end
	-- The local regulators need a few percent of power to see anything.
	if self.larOn and power < 0.06 then
		self.larOn = false
		self.plant:log("Local automatic regulators dropped out: power below range")
		self.plant:raise("lar.dropout")
	end

	local gravity = self.kom or not self.drivePower
	local runbackActive = false
	if self.runback > 0 and not self.runbackDone then
		if power > RUNBACK_TARGET[self.runback] + 0.01 then
			runbackActive = true
		else
			self.runbackDone = true
		end
	end

	-- Withdrawal permissives for manual motion.
	local block = 0
	if self.az5 or self.az4 or runbackActive then
		block = 1
	elseif gravity then
		block = 2
	elseif not self.blockBypass and core.period > 0 and core.period < Config.Protection.PERIOD_ALARM then
		block = 3
	elseif not self.blockBypass and power > 1.05 then
		block = 4
	end
	local azOut = true
	for _, i in self.byKind.AZ do
		if pos[i] > 0.05 then
			azOut = false
			break
		end
	end
	self.azRodsOut = azOut

	local arLimit, larLimit = false, false
	local allIn = true
	local manual = self.manual
	local anyAuto = false
	for i = 1, NR do
		local kind = self.kind[i]
		local usp = kind == "USP"
		local v = 0
		if self.stuck[i] then
			v = 0
		elseif gravity and not usp then
			v = R.SPEED_GRAVITY
		elseif self.az5 and not usp then
			v = R.SPEED_AZ
		elseif self.az4 and not usp then
			v = R.SPEED_MANUAL
		elseif runbackActive and (kind == "AR" or kind == "LAR") then
			v = R.SPEED_MANUAL
		elseif kind == "AR" and self.arMode == self.group[i] then
			v = arSpeed
			anyAuto = true
			if (pos[i] < 0.8 and v < 0) or (pos[i] > 5.7 and v > 0) then
				arLimit = true
			end
			if pos[i] < 0.5 and v < 0 then
				v = 0
			elseif pos[i] > 6.0 and v > 0 then
				v = 0
			end
		elseif kind == "LAR" and self.larOn then
			local z = self.group[i]
			local ref = self.zoneRef[z] * math.max(self.setpoint, 0.02) * nominal
			local e = (zoneAbs[z] - ref) / ref
			anyAuto = true
			if math.abs(e) > 0.015 then
				v = Util.clamp(e * 3, -1, 1) * R.SPEED_AUTO
			end
			if (pos[i] < 0.8 and v < 0) or (pos[i] > 5.7 and v > 0) then
				larLimit = true
			end
			if pos[i] < 0.5 and v < 0 then
				v = 0
			elseif pos[i] > 6.0 and v > 0 then
				v = 0
			end
		elseif self.selected[i] and manual ~= 0 then
			if manual > 0 then
				v = R.SPEED_MANUAL
			else
				local blocked = block ~= 0
				if not blocked and kind ~= "AZ" and not usp and not azOut and not self.azInterlockBypass then
					blocked = true
					block = 5
				end
				if not blocked then
					v = -R.SPEED_MANUAL
				end
			end
		end
		-- USP rods are driven from below: "insert" raises them into the core.
		self.velocity[i] = v
		if v ~= 0 then
			local x = Util.clamp(pos[i] + v * dt, 0, self.stroke[i])
			if x ~= pos[i] then
				core:setRodPosition(i, x)
			end
		end
		if not usp and pos[i] < self.stroke[i] - 0.02 then
			allIn = false
		end
	end
	self.rodBlock = block
	self.arAtLimit = arLimit
	self.larAtLimit = larLimit
	self.allIn = allIn
	if anyAuto then
		self.autoSeconds += dt
	end
end

-- Capture the present zone split as the local regulators' reference.
function Rods.captureZoneReference(self)
	local total = 0
	for z = 1, 12 do
		total += self.core.zonePower[z]
	end
	if total > 0 then
		for z = 1, 12 do
			self.zoneRef[z] = self.core.zonePower[z] / total
		end
	end
end

function Rods.groupMean(self, list: { number }): number
	local s = 0
	for _, i in list do
		s += self.core.rodPos[i]
	end
	return if #list > 0 then s / #list else 0
end

function Rods.publish(self, S)
	local core = self.core
	S["rod.selCount"] = self.selCount
	local selPos, n, first = 0, 0, 0
	for i = 1, self.NR do
		if self.selected[i] then
			selPos += core.rodPos[i]
			n += 1
			if first == 0 then
				first = i
			end
		end
	end
	S["rod.selPos"] = if n > 0 then selPos / n else 0
	S["rod.selFirst"] = first
	S["rod.moving"] = self.manual
	S["rod.block"] = self.rodBlock
	S["rod.blockBypass"] = if self.blockBypass then 1 else 0
	S["rod.azInterlockBypass"] = if self.azInterlockBypass then 1 else 0
	S["rod.quad"] = if self.quadSelect then 1 else 0
	S["rod.azOut"] = if self.azRodsOut then 1 else 0
	S["rod.allIn"] = if self.allIn then 1 else 0
	S["rod.meanRR"] = self:groupMean(self.byKind.RR)
	S["rod.meanAZ"] = self:groupMean(self.byKind.AZ)
	S["rod.meanUSP"] = self:groupMean(self.byKind.USP)
	S["rod.meanLAR"] = self:groupMean(self.byKind.LAR)
	for g = 1, 3 do
		S["ar.pos" .. g] = self:groupMean(self.arGroups[g])
	end
	S["ar.mode"] = self.arMode
	S["ar.setpoint"] = self.setpoint * 100
	S["ar.error"] = self.arError * 100
	S["ar.limit"] = if self.arAtLimit then 1 else 0
	S["lar.on"] = if self.larOn then 1 else 0
	S["lar.limit"] = if self.larAtLimit then 1 else 0
	S["kom"] = if self.kom then 1 else 0
	S["az5.active"] = if self.az5 then 1 else 0
	S["az4.active"] = if self.az4 then 1 else 0
	S["az1.active"] = if self.runback == 1 then 1 else 0
	S["az2.active"] = if self.runback == 2 then 1 else 0
	S["az3.active"] = if self.runback == 3 then 1 else 0
	local stuck = 0
	for i = 1, self.NR do
		if self.stuck[i] then
			stuck += 1
		end
	end
	S["rod.stuck"] = stuck
end

return Rods
