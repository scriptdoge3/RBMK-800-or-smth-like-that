--!nonstrict
-- Server entry point: builds the room, runs the plant simulation, and
-- keeps every client's control room in step with it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("RBMK")
local PanelLayout = require(Shared.PanelLayout)
local AlarmList = require(Shared.AlarmList)
local RoomBuilder = require(script.Parent.RoomBuilder)
local Plant = require(script.Parent.Sim.Plant)

local STEP = 0.1 -- plant time step, seconds
local SNAPSHOT_PERIOD = 0.2
local MAP_PERIOD = 1.0
local REBUILD_DELAY = 75 -- seconds a destroyed unit stays before a new one is commissioned

local remotes = Instance.new("Folder")
remotes.Name = "RBMKRemotes"
local function remote(className: string, name: string): any
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotes
	return r
end
local commandEvent: RemoteEvent = remote("RemoteEvent", "Command")
local snapshotEvent: RemoteEvent = remote("RemoteEvent", "Snapshot")
local mapEvent: RemoteEvent = remote("RemoteEvent", "CoreMap")
local alarmEvent: RemoteEvent = remote("RemoteEvent", "Alarm")
local logEvent: RemoteEvent = remote("RemoteEvent", "Log")
local helloFunction: RemoteFunction = remote("RemoteFunction", "Hello")
remotes.Parent = ReplicatedStorage

RoomBuilder.build()

local plant: any = nil
local building = false
local unitNumber = 0
local lastLogSeq = 0

local function commission()
	if building then
		return
	end
	building = true
	plant = nil
	task.spawn(function()
		unitNumber += 1
		local started = os.clock()
		local fresh = Plant.new({
			seed = (os.time() + unitNumber * 7919) % 1000000,
			yield = function()
				task.wait()
			end,
		})
		lastLogSeq = 0
		plant = fresh
		building = false
		print(string.format("[RBMK-800] unit %d ready after %.1f s", unitNumber, os.clock() - started))
		-- Give every client the clean annunciator board of the new unit.
		for i in AlarmList.list do
			alarmEvent:FireAllClients(i, 0)
		end
	end)
end
commission()

-- A client asks for the standing state when it joins.
helloFunction.OnServerInvoke = function(_player: Player)
	if not plant then
		return { ready = false }
	end
	local lines = {}
	for i = math.max(1, #plant.logLines - 40), #plant.logLines do
		local l = plant.logLines[i]
		table.insert(lines, { t = l.t, text = l.text })
	end
	return { ready = true, alarms = table.clone(plant.alarms.state), log = lines, unit = unitNumber }
end

-- Operator commands. Only commands that exist on a panel are accepted, and
-- each player is limited to a sensible rate.
local NOTABLE = {
	["az5.button"] = "pressed AZ-5",
	["eccs.manual"] = "initiated ECCS manually",
	["tg.1.trip"] = "tripped turbine 1",
	["tg.2.trip"] = "tripped turbine 2",
}
local budget: { [Player]: number } = {}
commandEvent.OnServerEvent:Connect(function(player: Player, name: any, value: any)
	if not plant or type(name) ~= "string" or type(value) ~= "number" or value ~= value then
		return
	end
	if not PanelLayout.commands[name] then
		return
	end
	local left = budget[player] or 40
	if left <= 0 then
		return
	end
	budget[player] = left - 1
	value = math.clamp(value, -100000, 100000)
	if PanelLayout.holdCommands[name] then
		plant:hold(name, value, player)
	else
		plant:command(name, value, player)
		local what = NOTABLE[name]
		if what then
			plant:log(player.Name .. " " .. what)
		elseif string.sub(name, 1, 12) == "prot.bypass." or name == "kom" then
			plant:log(string.format("%s set %s to %d", player.Name, name, value))
		end
	end
end)
Players.PlayerRemoving:Connect(function(player: Player)
	budget[player] = nil
end)

local signals = PanelLayout.signals
local snapshot = buffer.create(#signals * 4)
local stepClock, snapshotClock, mapClock, budgetClock, destroyedClock = 0, 0, 0, 0, 0

RunService.Heartbeat:Connect(function(dt: number)
	budgetClock += dt
	if budgetClock >= 1 then
		budgetClock = 0
		table.clear(budget)
	end
	if not plant then
		return
	end
	local p = plant

	-- Fixed-step simulation in real time; never more than two steps a frame.
	stepClock += math.min(dt, 0.25)
	local steps = 0
	while stepClock >= STEP and steps < 2 do
		p:step(STEP)
		stepClock -= STEP
		steps += 1
	end
	if stepClock > 3 * STEP then
		stepClock = 0
	end

	snapshotClock += dt
	if snapshotClock >= SNAPSHOT_PERIOD then
		snapshotClock = 0
		local S = p.S
		for i, name in signals do
			buffer.writef32(snapshot, (i - 1) * 4, S[name] or 0)
		end
		snapshotEvent:FireAllClients(snapshot)
		-- Annunciator changes and new log lines ride along at the same rate.
		local changed = p.alarms.changed
		if #changed > 0 then
			for _, index in changed do
				alarmEvent:FireAllClients(index, p.alarms.state[index])
			end
			table.clear(changed)
		end
		local lines = p.logLines
		local last = lines[#lines]
		if last and last.seq > lastLogSeq then
			local fresh = {}
			for i = #lines, 1, -1 do
				if lines[i].seq <= lastLogSeq then
					break
				end
				table.insert(fresh, 1, { t = lines[i].t, text = lines[i].text })
			end
			lastLogSeq = last.seq
			logEvent:FireAllClients(fresh)
		end
	end

	mapClock += dt
	if mapClock >= MAP_PERIOD then
		mapClock = 0
		mapEvent:FireAllClients(p:mapBuffer())
	end

	-- A wrecked unit is replaced by a new one after a pause.
	if p.core.destroyed then
		destroyedClock += dt
		if destroyedClock > REBUILD_DELAY then
			destroyedClock = 0
			commission()
		end
	else
		destroyedClock = 0
	end
end)
