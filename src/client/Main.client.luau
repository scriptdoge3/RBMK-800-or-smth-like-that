--!nonstrict
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

-- On the operators' desk: a green-screen terminal with a live summary, and
-- the alarm teleprinter, which prints the event log on its paper.
local function surface(target: Instance, pixelsPerStud: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Adornee = target :: any
	gui.Parent = target
	return gui
end
local function typed(gui: SurfaceGui, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -14, 1, -10)
	label.Position = UDim2.fromOffset(7, 5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Text = ""
	label.Parent = gui
	return label
end
local terminalText: TextLabel? = nil
local alarmText: TextLabel? = nil
local paperText: TextLabel? = nil
local boardText: TextLabel? = nil
do
	local screenPart = room:WaitForChild("DeskScreen1", 10)
	if screenPart then
		terminalText = typed(surface(screenPart, 330), 14, Color3.fromRGB(110, 255, 140))
		terminalText.Text = "UNIT COMPUTER\nNOT READY"
	end
	local alarmPart = room:WaitForChild("DeskScreen2", 10)
	if alarmPart then
		alarmText = typed(surface(alarmPart, 330), 13, Color3.fromRGB(110, 255, 140))
		alarmText.Text = "ALARM SUMMARY\nNOT READY"
	end
	local paperPart = room:WaitForChild("PrinterPaper", 10)
	if paperPart then
		paperText = typed(surface(paperPart, 220), 11, Color3.fromRGB(30, 30, 34))
		paperText.TextYAlignment = Enum.TextYAlignment.Bottom
	end
	-- The shift status board, kept up in marker by the operators.
	local boardPart = room:WaitForChild("StatusBoard", 10)
	if boardPart then
		boardText = typed(surface(boardPart, 60), 19, Color3.fromRGB(28, 40, 120))
		boardText.Font = Enum.Font.PermanentMarker
		boardText.Position = UDim2.fromOffset(18, 10)
		boardText.Size = UDim2.new(1, -30, 1, -16)
	end
end
-- What the shift board says the unit is doing.
local function unitMode(g: (string) -> number): string
	if g("core.destroyed") >= 0.5 then
		return "REACTOR DESTROYED"
	elseif g("n.power") < 0.05 and g("pri.temp") < 100 then
		return "COLD SHUTDOWN"
	elseif g("n.power") < 0.05 then
		return "HOT SHUTDOWN"
	elseif g("plant.gross") > 1 then
		return "POWER OPERATION"
	end
	return "STARTUP"
end
local function refreshDesk()
	local g = ctx.get
	local t = math.floor(g("time"))
	if alarmText then
		local lines = { "ALARM SUMMARY", "" }
		for _, tile in built.annTiles do
			if tile.state > 0 and #lines < 13 then
				table.insert(lines, (if tile.state == 1 then "* " else "  ") .. string.upper(string.gsub(tile.label.Text, "\n", " ")))
			end
		end
		if #lines == 2 then
			table.insert(lines, "NO ALARMS")
		end
		alarmText.Text = table.concat(lines, "\n")
	end
	if boardText then
		boardText.Text = string.format(
			"UNIT 1 - SHIFT STATUS\nMODE:  %s\nREACTOR:  %.0f MWt  (%.1f %%)\nGROSS:  %.0f MWe\nORM:  %.0f RODS   (MIN 26)\nDRUMS:  %.2f MPa  %.0f C\nSCRAMS THIS SHIFT:  %d",
			unitMode(g), g("n.thermal"), g("n.power"), g("plant.gross"), g("core.orm"), g("pri.press"), g("pri.temp"), g("stats.scrams")
		)
	end
	if terminalText then
		terminalText.Text = string.format(
			"RBMK-800 UNIT 1   %02d:%02d:%02d\n\nPOWER  %7.2f %%  %5.0f MWT\nPERIOD %7.0f S\nMARGIN %7.0f RODS\nPRESS  %7.2f MPA %4.0f C\nFLOW   %7.0f T/H\nSTEAM  %7.0f  FEED %5.0f\nGROSS  %7.0f MWE",
			t // 3600, (t // 60) % 60, t % 60, g("n.power"), g("n.thermal"), g("n.period"), g("core.orm"), g("pri.press"), g("pri.temp"), g("pri.flow"), g("steam.total"), g("fw.total"), g("plant.gross")
		)
	end
	if paperText then
		local lines = built.logLines
		local shown = {}
		for i = math.max(1, #lines - 11), #lines do
			table.insert(shown, string.upper(lines[i]))
		end
		paperText.Text = table.concat(shown, "\n")
	end
end

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
local snapshotCount = 0
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
	snapshotCount += 1
	if snapshotCount % 5 == 1 then
		refreshDesk()
	end

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
			local k = 0.3 * (1 - age / 6)
			camera.CFrame *= CFrame.new((math.random() - 0.5) * k, (math.random() - 0.5) * k, 0)
		end
	end
end)
