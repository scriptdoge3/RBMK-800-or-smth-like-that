-- End-to-end smoke test of the Roblox-facing code, with no Roblox.
--
-- Lune ships Roblox's class and property database, so creating instances
-- here catches misspelt properties, wrong value types and unknown classes.
-- Services, events and remotes are faked just far enough to run the real
-- server script and the real client script against each other: the server
-- builds the room and the plant, the client dresses the panels, snapshots
-- flow one way and operator commands the other.
local H = require("./harness")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3, Vector2, CFrame = roblox.Vector3, roblox.Vector2, roblox.CFrame
local Enum = roblox.Enum

-- ---------------------------------------------------------------- fakes
local function signal()
	local handlers = {}
	local s = { handlers = handlers }
	function s:Connect(fn)
		table.insert(handlers, fn)
		return { Disconnect = function() end }
	end
	function s.fire(...)
		for _, h in handlers do
			h(...)
		end
	end
	return s
end

local dm = Instance.new("DataModel")
local workspace = dm:GetService("Workspace")
local replicated = dm:GetService("ReplicatedStorage")
local soundService = dm:GetService("SoundService")
local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"

roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	local found = self:FindFirstChild(name)
	if not found then
		error("WaitForChild would hang: " .. tostring(name) .. " is not in " .. self.Name)
	end
	return found
end)
roblox.implementMethod("ReplicatedStorage", "WaitForChild", function(self, name)
	if name == "RBMK" then
		return H.sharedNode
	end
	return self:FindFirstChild(name) or error("no " .. name .. " in ReplicatedStorage")
end)

-- Remotes: one shared set of fake signals keyed by remote name.
local serverSignals, clientSignals, invokers = {}, {}, {}
local fakePlayer = { Name = "Tester", Character = nil :: any }
function fakePlayer:WaitForChild(_name)
	return playerGui
end
local function named(tbl, name)
	tbl[name] = tbl[name] or signal()
	return tbl[name]
end
roblox.implementProperty("RemoteEvent", "OnServerEvent", function(self)
	return named(serverSignals, self.Name)
end)
roblox.implementProperty("RemoteEvent", "OnClientEvent", function(self)
	return named(clientSignals, self.Name)
end)
local fired = {}
roblox.implementMethod("RemoteEvent", "FireAllClients", function(self, ...)
	fired[self.Name] = (fired[self.Name] or 0) + 1
	named(clientSignals, self.Name).fire(...)
end)
local sent = {}
roblox.implementMethod("RemoteEvent", "FireServer", function(self, ...)
	table.insert(sent, { ... })
	named(serverSignals, self.Name).fire(fakePlayer, ...)
end)
roblox.implementProperty("RemoteFunction", "OnServerInvoke", function(self)
	return invokers[self.Name]
end, function(self, fn)
	invokers[self.Name] = fn
end)
roblox.implementMethod("RemoteFunction", "InvokeServer", function(self, ...)
	return invokers[self.Name](fakePlayer, ...)
end)
local buttonSignals = {}
roblox.implementProperty("TextButton", "MouseButton1Click", function(self)
	local s = signal()
	table.insert(buttonSignals, s)
	return s
end)
local soundPlays = 0
roblox.implementMethod("Sound", "Play", function()
	soundPlays += 1
end)
roblox.implementMethod("Sound", "Stop", function() end)
roblox.implementProperty("Sound", "IsPlaying", function()
	return false
end)

-- Camera and ray casting are scripted by the test.
local camera = Instance.new("Camera")
camera.Parent = workspace
local cameraState = { CFrame = CFrame.new(0, 6, 0), FieldOfView = 70, CameraType = Enum.CameraType.Custom }
local nextHit: any = nil
roblox.implementMethod("Camera", "ViewportPointToRay", function()
	return { Origin = Vector3.new(0, 6, 0), Direction = Vector3.new(0, 0, -1) }
end)
roblox.implementMethod("Workspace", "Raycast", function()
	return nextHit
end)
-- A table stands in for the camera so the scripts can set what they like.
local cameraProxy = setmetatable({}, {
	__index = function(_, k)
		if k == "ViewportPointToRay" then
			return function()
				return { Origin = Vector3.new(0, 6, 0), Direction = Vector3.new(0, 0, -1) }
			end
		end
		return cameraState[k]
	end,
	__newindex = function(_, k, v)
		cameraState[k] = v
	end,
})
local workspaceProxy = setmetatable({}, {
	__index = function(_, k)
		if k == "CurrentCamera" then
			return cameraProxy
		elseif k == "Raycast" then
			return function()
				return nextHit
			end
		elseif k == "WaitForChild" or k == "FindFirstChild" then
			return function(_, name)
				return workspace:FindFirstChild(name)
			end
		end
		return (workspace :: any)[k]
	end,
})
-- Parenting to the proxy has to reach the real Workspace.
local realInstanceNew = Instance.new

local heartbeat, renderStepped = signal(), signal()
local inputBegan, inputEnded, inputChanged, focusReleased = signal(), signal(), signal(), signal()
local mouse = Vector2.new(400, 300)
local boundActions = {}
local delayed = {}
local services = {
	ReplicatedStorage = replicated,
	SoundService = soundService,
	Players = { LocalPlayer = fakePlayer, PlayerRemoving = signal() },
	RunService = { Heartbeat = heartbeat, RenderStepped = renderStepped },
	UserInputService = {
		InputBegan = inputBegan,
		InputEnded = inputEnded,
		InputChanged = inputChanged,
		WindowFocusReleased = focusReleased,
		GetMouseLocation = function()
			return mouse
		end,
	},
	ContextActionService = {
		BindActionAtPriority = function(_, name, fn)
			boundActions[name] = fn
		end,
		UnbindAction = function(_, name)
			boundActions[name] = nil
		end,
	},
}
for name, value in services do
	H.setService(name, value)
end

local taskLib = {
	spawn = function(fn, ...)
		fn(...)
	end,
	wait = function() end,
	delay = function(_, fn)
		table.insert(delayed, fn)
	end,
}
local raycastParams = {
	new = function()
		return {}
	end,
}

for name, value in {
	Instance = Instance,
	Vector3 = Vector3,
	Vector2 = Vector2,
	CFrame = CFrame,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = Enum,
	RaycastParams = raycastParams,
	task = taskLib,
} :: { [string]: any } do
	H.setGlobal(name, value)
end
-- The server parents the room to `workspace`; the client reads the camera
-- from it. Give the server the real instance and the client the proxy.
H.setGlobal("workspace", workspace)
local _ = realInstanceNew

-- ---------------------------------------------------------------- server
print("starting the server script")
local t0 = os.clock()
H.require(H.server.Main)
print(string.format("  server ready in %.1f s", os.clock() - t0))
local room = workspace:FindFirstChild("ControlRoom")
H.check(room ~= nil, "server built the control room")
local PanelLayout = H.require(H.shared.PanelLayout)
local missingFaces = 0
for _, p in PanelLayout.panels do
	for _, face in { "bench", "vert", "ann" } do
		if not room:FindFirstChild(p.id .. "_" .. face) then
			missingFaces += 1
		end
	end
end
H.check(missingFaces == 0, "every panel face exists")
H.check(replicated:FindFirstChild("RBMKRemotes") ~= nil, "remotes created")
H.check(#room:GetChildren() > 40, string.format("room has %d parts", #room:GetChildren()))
for _ = 1, 30 do
	heartbeat.fire(0.1)
end
H.check((fired.Snapshot or 0) >= 10, "server broadcasts snapshots")
H.check((fired.CoreMap or 0) >= 2, "server broadcasts the core map")

-- Geometry sanity: the board must face the operator and the bench must face up.
do
	local f = PanelLayout.face(3, "vert")
	local toOperator = (Vector3.new(0, f.center.Y, 0) - f.center).Unit
	H.check(f.normal:Dot(toOperator) > 0.95, "vertical boards face the middle of the room")
	local b = PanelLayout.face(3, "bench")
	H.check(b.normal.Y > 0.8 and b.normal:Dot(toOperator) > 0.2, "benches slope up and toward the operator")
	local u, v = PanelLayout.toFace(f, PanelLayout.toWorld(f, 3.25, 1.5, 0))
	H.near(u, 3.24, 3.26, "face coordinates round-trip (u)")
	H.near(v, 1.49, 1.51, "face coordinates round-trip (v)")
	local cf = PanelLayout.faceCFrame(f)
	H.check((cf.LookVector - f.normal).Magnitude < 1e-3, "display parts show their Front face to the operator")
	local right = PanelLayout.toWorld(f, 16, 0, 0) - PanelLayout.toWorld(f, 0, 0, 0)
	H.check(right.Unit:Dot(f.right) > 0.999 and f.right:Dot(-cf.RightVector) > 0.999, "canvas x runs to the operator's right")
end

-- ---------------------------------------------------------------- client
print("starting the client script")
-- Rebind `workspace` for client modules: they need CurrentCamera and Raycast.
H.setGlobal("workspace", workspaceProxy)
local t1 = os.clock()
H.require(H.client.Main)
print(string.format("  client ready in %.1f s", os.clock() - t1))
local guiCount, partCount = 0, 0
for _, d in room:GetDescendants() do
	if d:IsA("GuiObject") then
		guiCount += 1
	elseif d:IsA("BasePart") then
		partCount += 1
	end
end
print(string.format("  %d GUI objects and %d parts in the room", guiCount, partCount))
H.check(guiCount > 3000, "panels are dressed")

local function findText(pattern: string): boolean
	for _, d in room:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, pattern, 1, true) then
			return true
		end
	end
	return false
end
for _ = 1, 30 do
	heartbeat.fire(0.1)
	renderStepped.fire(0.016)
end
H.check(findText("RBMK-800 UNIT"), "unit computer shows live data")
H.check(findText("CORE MAP: FLUX"), "core map received and titled")
H.check(findText("Unit in cold shutdown"), "event log reached the client")

-- Click every control on every face, the way a player would.
local Plant = H.require(H.server.Sim.Plant)
local _ = Plant
local Panels = H.require(H.client.Panels)
local _ = Panels
local clicks, tips, errors = 0, 0, {}
local AlarmList = H.require(H.shared.AlarmList)
local _ = AlarmList
local function leftDown()
	inputBegan.fire({ UserInputType = Enum.UserInputType.MouseButton1 }, false)
end
local function leftUp()
	inputEnded.fire({ UserInputType = Enum.UserInputType.MouseButton1 })
end
for _, p in PanelLayout.panels do
	for _, faceName in { "bench", "vert", "ann" } do
		local part = room:FindFirstChild(p.id .. "_" .. faceName)
		local face = PanelLayout.face(p.index, faceName)
		for _, w in p.widgets do
			if w.face == faceName and w.kind ~= "section" and w.kind ~= "label" then
				for _, frac in { 0.25, 0.75 } do
					local u, v = w.x + w.w * frac, w.y + w.h * 0.5
					nextHit = { Instance = part, Position = PanelLayout.toWorld(face, u, v, 0) }
					local ok, err = pcall(function()
						renderStepped.fire(0.016)
						tips += 1
						leftDown()
						renderStepped.fire(0.3)
						leftUp()
						clicks += 1
					end)
					if not ok then
						table.insert(errors, string.format("%s %s '%s': %s", p.id, w.kind, tostring(w.label), string.sub(tostring(err), 1, 160)))
					end
				end
			end
		end
	end
end
nextHit = nil
renderStepped.fire(0.016)
for _, e in errors do
	print("  error " .. e)
end
H.check(#errors == 0, string.format("clicked and hovered %d spots with no script errors", clicks))
H.check(#sent > 150, string.format("controls sent %d commands to the server", #sent))
local unknown = {}
for _, s in sent do
	if not PanelLayout.commands[s[1]] then
		unknown[s[1]] = true
	end
end
H.check(next(unknown) == nil, "every command sent is one the server accepts")
H.check(soundPlays > 0, "controls click")
for _, fn in delayed do
	fn()
end

-- Panel view: sit down, look around, stand up.
fakePlayer.Character = {
	FindFirstChild = function()
		return { Position = Vector3.new(0, 3, -30) }
	end,
}
local function key(code)
	inputBegan.fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = code }, false)
end
key(Enum.KeyCode.E)
H.check(cameraState.CameraType == Enum.CameraType.Scriptable, "E sits the player at the nearest panel")
local handler = boundActions.RBMKPanelKeys
H.check(handler ~= nil, "movement keys are captured while seated")
for _, code in { Enum.KeyCode.A, Enum.KeyCode.D, Enum.KeyCode.D, Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.S } do
	handler("RBMKPanelKeys", Enum.UserInputState.Begin, { KeyCode = code })
	renderStepped.fire(0.016)
end
inputChanged.fire({ UserInputType = Enum.UserInputType.MouseWheel, Position = Vector3.new(0, 0, 1) })
H.check(cameraState.FieldOfView < 60, "mouse wheel zooms the panel view")
key(Enum.KeyCode.E)
H.check(cameraState.CameraType == Enum.CameraType.Custom and boundActions.RBMKPanelKeys == nil, "E again stands up")
key(Enum.KeyCode.P)
local binder = playerGui:FindFirstChild("RBMKProcedures")
H.check(binder ~= nil and binder.Enabled == true, "P opens the procedures binder")
-- Turn the pages (the first signals made are the tabs), then tick every
-- step on the startup checklist.
local Procedures = H.require(H.shared.Procedures)
local nTabs = #Procedures.pages
for _, i in { 1, 3, 4, 5, 6 } do
	buttonSignals[i].fire()
end
local before = #buttonSignals
buttonSignals[2].fire()
local steps = 0
for i = before + 1, #buttonSignals do
	buttonSignals[i].fire()
	steps += 1
end
H.check(nTabs == 6 and steps > 30, string.format("binder pages turn and %d checklist steps tick", steps))

-- Let the plant run on with everything the clicking did to it.
for _ = 1, 100 do
	heartbeat.fire(0.1)
	renderStepped.fire(0.016)
end
H.check((fired.Alarm or 0) > 0, "annunciator changes reach the client")

-- Optional: dump the artwork of every panel face as JSON so it can be
-- rendered outside Roblox for a quick look at the layout.
--   lune run tests/roblox_mock -- dump=/some/dir
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local dumpDir: string? = nil
for _, a in process.args do
	dumpDir = string.match(a, "^dump=(.+)$") or dumpDir
end
if dumpDir then
	local function rgb(c)
		return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
	end
	local function describe(obj, into)
		for _, child in obj:GetChildren() do
			if child:IsA("GuiObject") then
				local item: any = {
					class = child.ClassName,
					x = child.Position.X.Offset,
					y = child.Position.Y.Offset,
					sx = child.Position.X.Scale,
					sy = child.Position.Y.Scale,
					w = child.Size.X.Offset,
					h = child.Size.Y.Offset,
					ws = child.Size.X.Scale,
					hs = child.Size.Y.Scale,
					ax = child.AnchorPoint.X,
					ay = child.AnchorPoint.Y,
					bg = rgb(child.BackgroundColor3),
					alpha = 1 - child.BackgroundTransparency,
					z = child.ZIndex,
					rot = child.Rotation,
					visible = child.Visible,
					round = child:FindFirstChildOfClass("UICorner") ~= nil,
					kids = {},
				}
				local stroke = child:FindFirstChildOfClass("UIStroke")
				if stroke and stroke.Enabled then
					item.stroke = rgb(stroke.Color)
					item.strokeW = stroke.Thickness
				end
				if child:IsA("TextLabel") then
					item.text = child.Text
					item.size = child.TextSize
					item.color = rgb(child.TextColor3)
					item.font = child.Font.Name
					item.alignX = child.TextXAlignment.Name
					item.alignY = child.TextYAlignment.Name
				end
				describe(child, item.kids)
				table.insert(into, item)
			end
		end
	end
	local faces = {}
	for _, p in PanelLayout.panels do
		for _, faceName in { "ann", "vert", "bench" } do
			local part = room:FindFirstChild(p.id .. "_" .. faceName)
			local gui = part:FindFirstChildOfClass("SurfaceGui")
			local items = {}
			describe(gui, items)
			local widgets = {}
			for _, w in p.widgets do
				if w.face == faceName then
					table.insert(widgets, { kind = w.kind, x = w.x, y = w.y, w = w.w, h = w.h, color = w.color, big = w.big, key = w.key, compact = w.compact })
				end
			end
			table.insert(faces, {
				panel = p.id,
				face = faceName,
				width = part.Size.X * PanelLayout.PIXELS_PER_STUD,
				height = part.Size.Y * PanelLayout.PIXELS_PER_STUD,
				pps = PanelLayout.PIXELS_PER_STUD,
				color = rgb(part.Color),
				items = items,
				widgets = widgets,
			})
		end
	end
	-- Every part in the room too, for a 3D view.
	local parts = {}
	for _, d in room:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, {
				name = d.Name,
				size = { d.Size.X, d.Size.Y, d.Size.Z },
				cf = { d.CFrame:GetComponents() },
				color = rgb(d.Color),
				shape = if d:IsA("Part") then d.Shape.Name else "Block",
				neon = d.Material == Enum.Material.Neon,
				transparency = d.Transparency,
				face = d:GetAttribute("Face"),
				panel = d:GetAttribute("Panel"),
			})
		end
	end
	fs.writeFile(dumpDir .. "/parts.json", serde.encode("json", parts))
	fs.writeFile(dumpDir .. "/panels.json", serde.encode("json", faces))
	print("  artwork dumped to " .. dumpDir .. "/panels.json")
end
H.finish()
