--!strict
-- Mouse interaction with the panels and the seated "panel view" camera.
--
-- Every control is a region on a panel face. A ray from the camera through
-- the mouse finds the face and the point on it, and the region under that
-- point decides what a click does. Pressing E near a benchboard locks the
-- camera onto it for precise work.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local PanelLayout = require(Shared.PanelLayout)

local Controls = {}

local REACH = 70 -- studs
local HOLD_REFRESH = 0.25
local VIEWS = { "bench", "board", "wide" }

function Controls.start(built: any, ctx: any)
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera :: Camera
	local faceParts: { Instance } = {}
	for part in built.faces do
		table.insert(faceParts, part)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = faceParts

	-- Heads-up elements: tooltip and key hints.
	local gui = Instance.new("ScreenGui")
	gui.Name = "RBMKHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")
	local tip = Instance.new("TextLabel")
	tip.BackgroundColor3 = Color3.fromRGB(20, 22, 24)
	tip.BackgroundTransparency = 0.1
	tip.BorderSizePixel = 0
	tip.TextColor3 = Color3.fromRGB(240, 240, 230)
	tip.Font = Enum.Font.SourceSans
	tip.TextSize = 17
	tip.TextXAlignment = Enum.TextXAlignment.Left
	tip.AutomaticSize = Enum.AutomaticSize.XY
	tip.Visible = false
	tip.ZIndex = 10
	tip.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.Parent = tip
	local hint = Instance.new("TextLabel")
	hint.BackgroundColor3 = Color3.fromRGB(20, 22, 24)
	hint.BackgroundTransparency = 0.35
	hint.BorderSizePixel = 0
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -12)
	hint.Size = UDim2.fromOffset(640, 26)
	hint.TextColor3 = Color3.fromRGB(235, 235, 225)
	hint.Font = Enum.Font.SourceSans
	hint.TextSize = 16
	hint.Parent = gui
	local HINT_WALK = "[E] sit at the nearest panel     [P] procedures     click any control; hover for details"
	local HINT_VIEW = "[A] [D] next panel     [W] [S] bench / board / wide     [wheel] zoom     [E] stand up"
	hint.Text = HINT_WALK

	-- What is under the mouse?
	local function pick(): (any, number, number)
		local m = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(m.X, m.Y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * REACH, params)
		if not hit then
			return nil, 0, 0
		end
		local face = built.faces[hit.Instance]
		if not face then
			return nil, 0, 0
		end
		local u, v = PanelLayout.toFace(face, hit.Position)
		local best: any = nil
		for _, r in built.regions[hit.Instance] do
			if u >= r.x and u <= r.x + r.w and v >= r.y and v <= r.y + r.h then
				if not best or r.w * r.h < best.w * best.h then
					best = r
				end
			end
		end
		return best, u, v
	end

	local holding: { cmd: string, value: number }? = nil
	local holdClock = 0

	local function release()
		if holding then
			ctx.send(holding.cmd, 0)
			holding = nil
		end
	end

	local function press(button: number)
		local r, u, v = pick()
		if not r or not r.press then
			return
		end
		local result = r.press(button, u, v)
		if result and result.hold then
			release()
			holding = { cmd = result.hold, value = result.value }
			holdClock = 0
			ctx.send(result.hold, result.value)
		end
	end

	-- Panel view.
	local viewing: number? = nil
	local view = 2
	local targetCF: CFrame? = nil

	local function aim()
		if not viewing then
			return
		end
		local origin, _, back = PanelLayout.panelFrame(viewing)
		local up = Vector3.new(0, 1, 0)
		local mode = VIEWS[view]
		if mode == "bench" then
			local bench = PanelLayout.face(viewing, "bench")
			targetCF = CFrame.lookAt(origin + up * 9.4 + back * 2.6, bench.center)
		elseif mode == "board" then
			local board = PanelLayout.face(viewing, "vert")
			targetCF = CFrame.lookAt(origin + up * 8.6 + back * 6.4, board.center)
		else
			targetCF = CFrame.lookAt(origin + up * 9.5 + back * 14, origin + up * 7.2)
		end
	end

	local function nearestPanel(): number?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return nil
		end
		local best, bestD = nil, 26
		for _, p in PanelLayout.panels do
			local origin, _, back = PanelLayout.panelFrame(p.index)
			local d = (root.Position - (origin + back * 4)).Magnitude
			if d < bestD then
				best, bestD = p.index, d
			end
		end
		return best
	end

	local function keys(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin and viewing then
			local key = input.KeyCode
			if key == Enum.KeyCode.A or key == Enum.KeyCode.Left then
				viewing = math.max(1, viewing - 1)
			elseif key == Enum.KeyCode.D or key == Enum.KeyCode.Right then
				viewing = math.min(#PanelLayout.panels, viewing + 1)
			elseif key == Enum.KeyCode.W or key == Enum.KeyCode.Up then
				view = math.min(#VIEWS, view + 1)
			elseif key == Enum.KeyCode.S or key == Enum.KeyCode.Down then
				view = math.max(1, view - 1)
			end
			aim()
		end
		return Enum.ContextActionResult.Sink
	end

	local function leaveView()
		if not viewing then
			return
		end
		viewing = nil
		targetCF = nil
		ContextActionService:UnbindAction("RBMKPanelKeys")
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		hint.Text = HINT_WALK
	end

	local function enterView()
		local index = nearestPanel()
		if not index then
			return
		end
		viewing = index
		view = 2
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 60
		aim()
		ContextActionService:BindActionAtPriority(
			"RBMKPanelKeys",
			keys,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.W,
			Enum.KeyCode.A,
			Enum.KeyCode.S,
			Enum.KeyCode.D,
			Enum.KeyCode.Up,
			Enum.KeyCode.Down,
			Enum.KeyCode.Left,
			Enum.KeyCode.Right,
			Enum.KeyCode.Space
		)
		hint.Text = HINT_VIEW
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
			press(1)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 and not processed and viewing then
			press(2)
		elseif input.KeyCode == Enum.KeyCode.E and not processed then
			if viewing then
				leaveView()
			else
				enterView()
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			release()
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if viewing and input.UserInputType == Enum.UserInputType.MouseWheel then
			camera.FieldOfView = math.clamp(camera.FieldOfView - input.Position.Z * 5, 18, 75)
		end
	end)
	UserInputService.WindowFocusReleased:Connect(release)

	RunService.RenderStepped:Connect(function(dt: number)
		if viewing and targetCF then
			camera.CFrame = camera.CFrame:Lerp(targetCF, math.min(1, dt * 10))
		end
		if holding then
			holdClock += dt
			if holdClock >= HOLD_REFRESH then
				holdClock = 0
				ctx.send(holding.cmd, holding.value)
			end
		end
		-- Tooltip.
		local r, u, v = pick()
		local textOut: string? = nil
		if r then
			local kind = r.widget.kind
			if kind == "coremap" and built.mapCellAt then
				textOut = built.mapInfo(built.mapCellAt(u, v))
			elseif kind == "rodmatrix" and built.rodAt then
				textOut = built.rodAt(u, v)
			end
			if not textOut and r.tip then
				textOut = r.tip()
			end
		end
		if textOut then
			local m = UserInputService:GetMouseLocation()
			tip.Text = textOut
			tip.Position = UDim2.fromOffset(m.X + 18, m.Y + 14)
			tip.Visible = true
		else
			tip.Visible = false
		end
	end)

	return { gui = gui, leaveView = leaveView }
end

return Controls
