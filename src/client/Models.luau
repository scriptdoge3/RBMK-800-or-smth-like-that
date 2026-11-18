--!nonstrict
-- The panel hardware modelled in Blender (models/blender/build_models.py):
-- pushbuttons and their hinged guards, indicating lights, pistol-grip
-- handles, key switches and selector knobs. Panels places copies of these
-- meshes on the boards.
--
-- The meshes reach the game in one of two ways, tried in this order:
--   1. Imported in Studio from models/RBMKModels.glb (File > Import 3D).
--      The import is a model called RBMKModels holding one MeshPart per
--      mesh; it can be left in Workspace (the server moves it out of the
--      room) or put in ReplicatedStorage.
--   2. Built while the game runs from the triangles in Meshes/, with
--      EditableMesh. Roblox only allows this when "Allow Mesh / Image APIs"
--      is on in Game Settings > Security.
-- With neither, `Models.ready` stays false and the panels are dressed with
-- plain parts instead.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("RBMK")
local PanelLayout = require(Shared.PanelLayout)
local Meshes = require(script.Parent.Meshes)

local Models = {}
Models.ready = false
Models.source = "parts"
-- Why the meshes could not be built in the game, when they could not.
Models.note = nil :: string?
Models.info = Meshes.info
Models.hinge = Meshes.hinge

local S = PanelLayout.SCALE

-- One template per mesh, never parented, and the size each copy is given
-- before scaling, in the template's own axes.
local templates: { [string]: BasePart } = {}
local baseSize: { [string]: Vector3 } = {}
-- Turns the panel frame of a model into the axes of its mesh, for meshes
-- that the importer turned on their way in.
local correction = CFrame.new()
-- Copies placed so far: their mesh and scale, for moving them later.
local placed: { [BasePart]: { name: string, k: number } } = setmetatable({}, { __mode = "k" }) :: any

local function vec(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function absolute(v: Vector3): Vector3
	return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
end

-- Strip a mesh down to a template: no children (an importer may add a
-- SurfaceAppearance, which would hide the colours), no physics.
local function prepare(part: BasePart): BasePart
	for _, child in part:GetChildren() do
		child:Destroy()
	end
	if part:IsA("MeshPart") then
		pcall(function()
			(part :: MeshPart).TextureID = ""
		end)
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 0
	return part
end

-- 1. Meshes imported in Studio.
local function fromImport(): boolean
	local root = ReplicatedStorage:FindFirstChild("RBMKModels") or workspace:FindFirstChild("RBMKModels")
	if not root then
		return false
	end
	local found: { [string]: BasePart } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("MeshPart") and found[d.Name] == nil then
			found[d.Name] = d
		end
	end
	-- The probes say where each axis of the panel frame went. Measured in
	-- the frame of the probe at the origin, so moving or turning the whole
	-- import does not matter.
	local axes = { Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1) }
	local origin = found.ProbeO
	if origin and found.ProbeX and found.ProbeY and found.ProbeZ then
		for i, name in { "ProbeX", "ProbeY", "ProbeZ" } do
			local d = origin.CFrame:VectorToObjectSpace(found[name].CFrame.Position - origin.CFrame.Position)
			if d.Magnitude < 1e-6 then
				warn("[RBMK-800] RBMKModels: the probe cubes are on top of each other; not using the import")
				return false
			end
			d = d.Unit
			local ax, ay, az = math.abs(d.X), math.abs(d.Y), math.abs(d.Z)
			local best = math.max(ax, ay, az)
			if best < 0.99 then
				warn("[RBMK-800] RBMKModels: the probe cubes have been moved; not using the import")
				return false
			end
			axes[i] = if best == ax
				then Vector3.new(math.sign(d.X), 0, 0)
				elseif best == ay then Vector3.new(0, math.sign(d.Y), 0)
				else Vector3.new(0, 0, math.sign(d.Z))
		end
		if axes[1]:Cross(axes[2]):Dot(axes[3]) < 0.99 then
			warn("[RBMK-800] RBMKModels: the import is mirrored; not using it")
			return false
		end
	end
	local turn = CFrame.fromMatrix(Vector3.new(), axes[1], axes[2], axes[3])
	-- Every mesh must be there, scaled the same along all three axes.
	local sizes: { [string]: Vector3 } = {}
	for name, info in Meshes.info do
		local part = found[name]
		if not part then
			warn("[RBMK-800] RBMKModels has no " .. name .. "; not using the import")
			return false
		end
		local want = absolute(turn:VectorToWorldSpace(vec(info.size)))
		local have = part.Size
		local r = have.X / want.X
		if math.abs(have.Y / want.Y / r - 1) > 0.05 or math.abs(have.Z / want.Z / r - 1) > 0.05 then
			warn("[RBMK-800] RBMKModels." .. name .. " is not the shape it should be; not using the import")
			return false
		end
		sizes[name] = want * S
	end
	for name in Meshes.info do
		templates[name] = prepare(found[name]:Clone())
		baseSize[name] = sizes[name]
	end
	correction = turn:Inverse()
	return true
end

-- 2. Meshes built in the game.
local function fromEditable(): boolean
	local okService, assets = pcall(function()
		return game:GetService("AssetService")
	end)
	if not okService or not assets then
		return false
	end
	local made: { [string]: BasePart } = {}
	for name, info in Meshes.info do
		local ok, result = pcall(function()
			local g = Meshes.geometry(name)
			local mesh = assets:CreateEditableMesh()
			if not mesh then
				error("out of mesh memory")
			end
			local v, n, t = g.v, g.n, g.t
			local verts = table.create(#v // 3)
			for i = 1, #v, 3 do
				verts[(i + 2) // 3] = mesh:AddVertex(Vector3.new(v[i], v[i + 1], v[i + 2]) * S)
			end
			local normals = table.create(#n // 3)
			for i = 1, #n, 3 do
				normals[(i + 2) // 3] = mesh:AddNormal(Vector3.new(n[i], n[i + 1], n[i + 2]))
			end
			for i = 1, #t, 6 do
				local face = mesh:AddTriangle(verts[t[i]], verts[t[i + 1]], verts[t[i + 2]])
				mesh:SetFaceNormals(face, { normals[t[i + 3]], normals[t[i + 4]], normals[t[i + 5]] })
			end
			return assets:CreateMeshPartAsync((Content :: any).fromObject(mesh))
		end)
		if not ok or not result then
			Models.note = string.format("could not build the %s mesh: %s", name, tostring(result))
			return false
		end
		made[name] = result
		baseSize[name] = vec(info.size) * S
	end
	for name, part in made do
		templates[name] = prepare(part)
	end
	return true
end

-- Find or build the meshes. Returns where they came from: "imported",
-- "built" or "parts" (none, use plain parts).
function Models.init(): string
	if Models.ready then
		return Models.source
	end
	if fromImport() then
		Models.source = "imported"
	elseif fromEditable() then
		Models.source = "built"
	else
		table.clear(templates)
		Models.source = "parts"
	end
	Models.ready = Models.source ~= "parts"
	return Models.source
end

-- The CFrame of a copy of `name` at scale `k` whose mounting point is at
-- `frame` (a CFrame in studs: X right, Y up the panel, Z out of it).
local function placement(name: string, frame: CFrame, k: number): CFrame
	local c = Meshes.info[name].center
	return frame * CFrame.new(c[1] * S * k, c[2] * S * k, c[3] * S * k) * correction
end

-- Put a copy of mesh `name`, `k` times its modelled size, at `frame`.
function Models.place(name: string, parent: Instance, frame: CFrame, k: number, color: Color3, material: Enum.Material, transparency: number?): BasePart
	local template = templates[name]
	assert(template, "no mesh called " .. name)
	local part = template:Clone()
	part.Name = name
	part.Size = baseSize[name] * k
	part.CFrame = placement(name, frame, k)
	part.Color = color
	part.Material = material
	part.Transparency = transparency or 0
	part:SetAttribute("Model", name)
	part.Parent = parent
	placed[part] = { name = name, k = k }
	return part
end

-- Move a copy made by `place` so that its mounting point is at `frame`.
function Models.move(part: BasePart, frame: CFrame)
	local p = placed[part]
	part.CFrame = placement(p.name, frame, p.k)
end

return Models
