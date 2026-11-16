--!strict
-- Client entry point: dresses the panels, keeps them in step with the
-- server's plant, and handles the player's input.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("RBMK")
local Config = require(Shared.Config)
local PanelLayout = require(Shared.PanelLayout)
local Panels = require(script.Parent.Panels)
local Controls = require(script.Parent.Controls)
local ProcedureGui = require(script.Parent.ProcedureGui)

local player = Players.LocalPlayer
local room = workspace:WaitForChild("ControlRoom")
local remotes = ReplicatedStorage:WaitForChild("RBMKRemotes")
local commandEvent = remotes:WaitForChild("Command") :: RemoteEvent
local snapshotEvent = remotes:WaitForChild("Snapshot") :: RemoteEvent
local mapEvent = remotes:WaitForChild("CoreMap") :: RemoteEvent
local alarmEvent = remotes:WaitForChild("Alarm") :: RemoteEvent
local logEvent = remotes:WaitForChild("Log") :: RemoteEvent
local helloFunction = remotes:WaitForChild("Hello") :: RemoteFunction

-- Sounds.
local function sound(id: string, volume: number, looped: boolean): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Looped = looped
	s.Parent = SoundService
	return s
end
local clickSound = sound(Config.Sounds.CLICK, 0.5, false)
local hornSound = sound(Config.Sounds.ALARM, 0.35, true)

-- Latest plant values, indexed as in PanelLayout.signals.
local signalIndex = PanelLayout.signalIndex
local values = table.create(#PanelLayout.signals, 0)
local ctx = {
	get = function(name: string): number
		local i = signalIndex[name]
		return if i then values[i] else 0
	end,
	send = function(name: string, value: number)
		commandEvent:FireServer(name, value)
	end,
	click = function()
		clickSound:Play()
	end,
}

local built = Panels.build(room, ctx)
Controls.start(built, ctx)
ProcedureGui.start()

-- Status banner: shown until the plant model is running, and when it is lost.
local screen = Instance.new("ScreenGui")
screen.Name = "RBMKStatus"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 20
screen.Parent = player:WaitForChild("PlayerGui")
local banner = Instance.new("TextLabel")
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 60)
banner.Size = UDim2.fromOffset(620, 54)
banner.BackgroundColor3 = Color3.fromRGB(20, 22, 24)
banner.BackgroundTransparency = 0.15
banner.BorderSizePixel = 0
banner.TextColor3 = Color3.fromRGB(240, 240, 230)
banner.Font = Enum.Font.SourceSansBold
banner.TextSize = 22
banner.Text = "Commissioning the unit: calculating the core..."
banner.Parent = screen
local flashOverlay = Instance.new("Frame")
flashOverlay.Size = UDim2.fromScale(1, 1)
flashOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
flashOverlay.BackgroundTransparency = 1
flashOverlay.BorderSizePixel = 0
flashOverlay.Parent = screen

local function stamp(t: number): string
	local s = math.floor(t)
	return string.format("%02d:%02d:%02d", s // 3600, (s // 60) % 60, s % 60)
end

local function addLog(lines: { any })
	for _, l in lines do
		table.insert(built.logLines, stamp(l.t) .. " " .. l.text)
	end
	while #built.logLines > 80 do
		table.remove(built.logLines, 1)
	end
end

local gotSnapshot = false
local hornOn = false
local wasDestroyed = false
local destroyedAt = 0

snapshotEvent.OnClientEvent:Connect(function(buf: buffer)
	local n = math.min(#values, buffer.len(buf) // 4)
	for i = 1, n do
		values[i] = buffer.readf32(buf, (i - 1) * 4)
	end
	if not gotSnapshot then
		gotSnapshot = true
		banner.Visible = false
	end
	built.refresh()

	local horn = ctx.get("horn") >= 0.5
	if horn ~= hornOn then
		hornOn = horn
		if horn then
			hornSound:Play()
		else
			hornSound:Stop()
		end
	end

	local destroyed = ctx.get("core.destroyed") >= 0.5
	if destroyed and not wasDestroyed then
		destroyedAt = os.clock()
		banner.Text = "THE REACTOR HAS BEEN DESTROYED\nA new unit will be commissioned shortly."
		banner.TextColor3 = Color3.fromRGB(255, 90, 70)
		banner.Visible = true
		flashOverlay.BackgroundTransparency = 0
	elseif not destroyed and wasDestroyed then
		banner.Visible = false
		banner.TextColor3 = Color3.fromRGB(240, 240, 230)
		table.clear(built.logLines)
	end
	wasDestroyed = destroyed
end)

mapEvent.OnClientEvent:Connect(function(buf: buffer)
	if built.setMap then
		built.setMap(buf)
	end
	if built.setRods then
		built.setRods(buf)
	end
end)

alarmEvent.OnClientEvent:Connect(function(index: number, state: number)
	built.setAlarm(index, state)
end)

logEvent.OnClientEvent:Connect(addLog)

-- Ask for the standing state; keep asking while the unit is still being built.
task.spawn(function()
	while true do
		local ok, state = pcall(function()
			return helloFunction:InvokeServer()
		end)
		if ok and state and state.ready then
			for i, s in state.alarms do
				built.setAlarm(i, s)
			end
			addLog(state.log)
			break
		end
		task.wait(1.5)
	end
end)

-- Annunciator flash, the camera shake of a destroyed core, and the fading flash.
local camera = workspace.CurrentCamera
local flashClock = 0
RunService.RenderStepped:Connect(function(dt: number)
	flashClock += dt
	built.flash(flashClock % 0.5 < 0.25)
	if wasDestroyed then
		local age = os.clock() - destroyedAt
		flashOverlay.BackgroundTransparency = math.clamp(age / 2.5, 0, 1)
		if age < 6 and camera then
			local k = 0.5 * (1 - age / 6)
			camera.CFrame *= CFrame.new((math.random() - 0.5) * k, (math.random() - 0.5) * k, 0)
		end
	end
end)
