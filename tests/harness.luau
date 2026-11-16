-- Headless test harness. Runs the game's modules under Lune by emulating
-- just enough of the Roblox instance tree for `require(script.Parent.X)` and
-- `game:GetService(...)` to resolve to files under src/.
--
-- Run from the repository root:  lune run tests/<name>
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Harness = {}

local moduleCache: { [string]: any } = {}
local nodeMeta = {}

local function newNode(name: string, parent: any, dir: string?, file: string?)
	return setmetatable({ _name = name, _parent = parent, _dir = dir, _file = file, _kids = {} }, nodeMeta)
end

-- The tree is scanned eagerly: file system calls yield under Lune and a
-- yield is not allowed inside the __index metamethod below.
local function scan(node: any, dir: string)
	local kids = rawget(node, "_kids")
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			local init = if fs.isFile(path .. "/init.luau") then path .. "/init.luau" else nil
			local child = newNode(entry, node, path, init)
			kids[entry] = child
			scan(child, path)
		elseif entry ~= "init.luau" then
			local name = entry:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", "")
			kids[name] = newNode(name, node, nil, path)
		end
	end
end

local function findChild(node: any, key: string): any
	return rawget(node, "_kids")[key]
end

nodeMeta.__index = function(node, key)
	if key == "Name" then
		return rawget(node, "_name")
	elseif key == "Parent" then
		return rawget(node, "_parent")
	elseif key == "WaitForChild" or key == "FindFirstChild" then
		return function(self, name)
			return findChild(self, name)
		end
	end
	local child = findChild(node, key)
	if child == nil then
		error(string.format("%s is not a valid member of %s", tostring(key), rawget(node, "_name")), 2)
	end
	return child
end

local services: { [string]: any } = {
	ReplicatedStorage = newNode("ReplicatedStorage", nil, nil, nil),
	ServerScriptService = newNode("ServerScriptService", nil, nil, nil),
	StarterPlayerScripts = newNode("StarterPlayerScripts", nil, nil, nil),
}
rawget(services.ReplicatedStorage, "_kids").RBMK = newNode("RBMK", services.ReplicatedStorage, "src/shared", nil)
rawget(services.ServerScriptService, "_kids").RBMKServer =
	newNode("RBMKServer", services.ServerScriptService, "src/server", nil)
scan(rawget(services.ReplicatedStorage, "_kids").RBMK, "src/shared")
scan(rawget(services.ServerScriptService, "_kids").RBMKServer, "src/server")
rawget(services.StarterPlayerScripts, "_kids").RBMKClient =
	newNode("RBMKClient", services.StarterPlayerScripts, "src/client", nil)
scan(rawget(services.StarterPlayerScripts, "_kids").RBMKClient, "src/client")

local game = {
	GetService = function(_, name: string)
		return services[name] or error("unknown service " .. name)
	end,
}

-- Extra globals handed to every module (the Roblox mock adds Instance,
-- Vector3, workspace and friends here before anything is required).
local extraNames: { string } = {}
local extraValues: { any } = {}
function Harness.setGlobal(name: string, value: any)
	table.insert(extraNames, name)
	table.insert(extraValues, value)
end
function Harness.setService(name: string, value: any)
	services[name] = value
end

local function requireNode(node: any): any
	local file = rawget(node, "_file")
	if not file then
		error("cannot require " .. tostring(rawget(node, "_name")) .. ": not a module", 2)
	end
	local hit = moduleCache[file]
	if hit ~= nil then
		return hit.value
	end
	-- The Roblox globals are passed in as locals rather than through a custom
	-- environment: Luau turns native code generation off for chunks with a
	-- replaced environment, and the core model is ten times slower without it.
	local names = "script, game, require, warn"
	if #extraNames > 0 then
		names ..= ", " .. table.concat(extraNames, ", ")
	end
	local source = "local " .. names .. " = ...; " .. fs.readFile(file)
	local bytecode = luau.compile(source, { optimizationLevel = 2, debugLevel = 1 })
	local chunk = luau.load(bytecode, { debugName = file, codegenEnabled = true })
	local value = chunk(node, game, requireNode, print, table.unpack(extraValues))
	moduleCache[file] = { value = value }
	return value
end

Harness.shared = rawget(services.ReplicatedStorage, "_kids").RBMK
Harness.server = rawget(services.ServerScriptService, "_kids").RBMKServer
Harness.client = rawget(services.StarterPlayerScripts, "_kids").RBMKClient
Harness.sharedNode = rawget(services.ReplicatedStorage, "_kids").RBMK
Harness.require = requireNode

-- Minimal assertion helpers.
local failures = 0
function Harness.check(cond: boolean, message: string)
	if cond then
		print("  ok   " .. message)
	else
		failures += 1
		print("  FAIL " .. message)
	end
end
function Harness.near(value: number, lo: number, hi: number, message: string)
	Harness.check(value >= lo and value <= hi, string.format("%s = %.5g (want %.5g .. %.5g)", message, value, lo, hi))
end
function Harness.finish()
	if failures > 0 then
		print(string.format("\n%d check(s) FAILED", failures))
		require("@lune/process").exit(1)
	end
	print("\nall checks passed")
end

return Harness
