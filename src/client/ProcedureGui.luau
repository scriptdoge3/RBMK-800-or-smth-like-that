--!nonstrict
-- The procedures binder: press P to open or close it.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local Procedures = require(Shared.Procedures)

local ProcedureGui = {}

function ProcedureGui.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "RBMKProcedures"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local binder = Instance.new("Frame")
	binder.AnchorPoint = Vector2.new(1, 0.5)
	binder.Position = UDim2.new(1, -16, 0.5, 0)
	binder.Size = UDim2.new(0, 640, 0.86, 0)
	binder.BackgroundColor3 = Color3.fromRGB(238, 234, 220)
	binder.BorderSizePixel = 0
	binder.Parent = gui

	local tabs = Instance.new("Frame")
	tabs.Size = UDim2.new(1, 0, 0, 34)
	tabs.BackgroundColor3 = Color3.fromRGB(60, 70, 84)
	tabs.BorderSizePixel = 0
	tabs.Parent = binder
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabs

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(0, 34)
	scroll.Size = UDim2.new(1, 0, 1, -34)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = binder
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.Parent = scroll

	local ticked: { [string]: boolean } = {}

	local function show(pageIndex: number)
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local page = Procedures.pages[pageIndex]
		for i, line in page.lines do
			local isStep = string.sub(line, 1, 3) == "[ ]"
			local key = pageIndex .. ":" .. i
			local row: any = Instance.new(if isStep then "TextButton" else "TextLabel")
			row.LayoutOrder = i
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, 0)
			row.AutomaticSize = Enum.AutomaticSize.Y
			row.Font = Enum.Font.Code
			row.TextSize = 15
			row.TextWrapped = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextColor3 = Color3.fromRGB(24, 26, 30)
			local function paint()
				if isStep then
					row.Text = (if ticked[key] then "[x]" else "[ ]") .. string.sub(line, 4)
					row.TextColor3 = if ticked[key] then Color3.fromRGB(120, 120, 112) else Color3.fromRGB(24, 26, 30)
				else
					row.Text = if line == "" then " " else line
				end
			end
			paint()
			if isStep then
				row.AutoButtonColor = false
				row.MouseButton1Click:Connect(function()
					ticked[key] = not ticked[key]
					paint()
				end)
			end
			row.Parent = scroll
		end
		scroll.CanvasPosition = Vector2.new(0, 0)
	end

	for i, page in Procedures.pages do
		local tab = Instance.new("TextButton")
		tab.LayoutOrder = i
		tab.Size = UDim2.new(1 / #Procedures.pages, 0, 1, 0)
		tab.BackgroundColor3 = Color3.fromRGB(60, 70, 84)
		tab.BorderSizePixel = 0
		tab.Font = Enum.Font.SourceSansBold
		tab.TextSize = 14
		tab.TextColor3 = Color3.fromRGB(240, 240, 235)
		tab.Text = page.title
		tab.Parent = tabs
		tab.MouseButton1Click:Connect(function()
			show(i)
		end)
	end
	show(1)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.KeyCode == Enum.KeyCode.P and not processed then
			gui.Enabled = not gui.Enabled
		end
	end)
	return gui
end

return ProcedureGui
